#!/usr/bin/env bash
# demo del retiro seguro de un worker con el compose local
#
#   bash deploy/retiro-seguro/demo-local.sh
#
# 1. deja dos workers corriendo, uno se detiene y el otro sigue el trabajo
# 2. espera a que se suba un video desde la web y un worker lo tome
# 3. con ffmpeg trabajando, detiene ese worker con docker stop
#    (manda sigterm y espera 10 s antes de matarlo)
# 4. muestra los logs del worker detenido, espera a que el otro termine el
#    video y corre las consultas de verificar.sql
#
# variable: ESPERA_S, segundos entre que el worker toma el video y se
# detiene (por defecto 8, suficiente para que ffmpeg vaya a mitad de la
# primera calidad con un video de un par de minutos)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$DIR/../.." && pwd)"
cd "$RAIZ"
ESPERA_S="${ESPERA_S:-8}"

echo "==> Dos workers"
docker compose up -d --scale worker=2 worker
mapfile -t workers < <(docker compose ps -q worker)
[[ ${#workers[@]} -ge 2 ]] || { echo "no hay dos workers corriendo" >&2; exit 1; }
desde="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo
echo "==> Sube ahora un video desde la web (profesor -> version -> recurso de video)."
echo "    Esperando a que un worker lo tome..."
elegido=""
for _ in $(seq 1 300); do
  for w in "${workers[@]}"; do
    if docker logs --since "$desde" "$w" 2>&1 | grep -q "trabajo aceptado, empieza la transcodificaci"; then
      elegido="$w"
      break 2
    fi
  done
  sleep 2
done
[[ -n "$elegido" ]] || { echo "ningun worker tomo un video en 10 minutos" >&2; exit 1; }
nombre="$(docker inspect -f '{{.Name}}' "$elegido" | tr -d /)"
echo "    Lo tomo $nombre. Se le detiene en ${ESPERA_S}s, con FFmpeg trabajando."
sleep "$ESPERA_S"

echo
echo "==> docker stop $nombre"
inicio=$(date +%s)
docker stop -t 10 "$elegido" >/dev/null
echo "    Se detuvo en $(( $(date +%s) - inicio ))s (por debajo de 10: no hizo falta SIGKILL)."

echo
echo "==> Registros del worker retirado"
docker logs --since "$desde" "$elegido" 2>&1 | grep -E "retiro|vuelve a la cola|requeued_on_shutdown|detenido" || true

echo
echo "==> El otro worker retoma el trabajo"
for w in "${workers[@]}"; do
  [[ "$w" == "$elegido" ]] && continue
  for _ in $(seq 1 300); do
    docker logs --since "$desde" "$w" 2>&1 | grep -q "media: activo listo" && break
    sleep 2
  done
  docker logs --since "$desde" "$w" 2>&1 | grep -E "trabajo aceptado|calidad transcodificada|activo listo" || true
done

echo
echo "==> Integridad en PostgreSQL"
docker compose exec -T postgres psql -U "${POSTGRES_USER:-mooc}" -d "${POSTGRES_DB:-mooc}" < "$DIR/verificar.sql"

echo
echo "==> Cola en Redis (pending y retry de la cola default; deben quedar en 0)"
docker compose exec -T redis redis-cli LLEN "asynq:{default}:pending"
docker compose exec -T redis redis-cli ZCARD "asynq:{default}:retry"

echo
echo "Para volver a dos workers: docker compose up -d --scale worker=2 worker"
