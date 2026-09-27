#!/usr/bin/env bash
# Una corrida de capacidad con la disciplina que pide el enunciado:
# 10 minutos de reposo (créditos de CPU de e2-small), registro de la
# configuración fija, k6 y recolección de métricas.
#
#   load/correr.sh escenario1
#   load/correr.sh escenario2
#
# Variables: BASE_URL, NIVELES, MESETA, PROFESORES, ESTUDIANTES, REPOSO_S
# (por defecto 600). El escenario sembrado tiene que estar en
# load/salida/escenario.json.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

escenario="${1:?uso: $0 escenario1|escenario2}"
[[ "$escenario" == escenario1 || "$escenario" == escenario2 ]] || {
  echo "escenario desconocido: $escenario" >&2
  exit 2
}

BASE_URL="${BASE_URL:?define BASE_URL (https://<ip>.sslip.io)}"
REPOSO_S="${REPOSO_S:-600}"
SALIDA="${SALIDA:-$DIR/salida}"
mkdir -p "$SALIDA"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
id="${escenario}-${stamp}"
meta="$SALIDA/corrida-${id}.md"

commit="$(git -C "$(dirname "$DIR")" rev-parse --short HEAD 2>/dev/null || echo desconocido)"
{
  echo "# Corrida $id"
  echo
  echo "| Campo | Valor |"
  echo "|---|---|"
  echo "| Escenario | $escenario |"
  echo "| Commit | \`$commit\` |"
  echo "| BASE_URL | \`$BASE_URL\` |"
  echo "| NIVELES | \`${NIVELES:-50,100,200,300}\` |"
  echo "| MESETA | \`${MESETA:-3m}\` |"
  echo "| PROFESORES | \`${PROFESORES:-3}\` |"
  echo "| ESTUDIANTES | \`${ESTUDIANTES:-20}\` |"
  echo "| WORKER_CONCURRENCY | \`${WORKER_CONCURRENCY:-sin registrar}\` |"
  echo "| DB_MAX_CONNS | \`${DB_MAX_CONNS:-sin registrar}\` |"
  echo "| Cloud NAT | \`${HABILITAR_NAT:-sin registrar}\` |"
  echo "| Generador | \`${GENERADOR:-sin registrar (anotar tipo y zona)}\` |"
  echo "| Reposo | ${REPOSO_S}s |"
  echo "| Inicio UTC | $(date -u +%Y-%m-%dT%H:%M:%SZ) |"
} >"$meta"

echo "reposo ${REPOSO_S}s (ráfaga de CPU de e2-small)…"
sleep "$REPOSO_S"

inicio="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export BASE_URL ESCENARIO="${ESCENARIO:-$SALIDA/escenario.json}" SALIDA
export NIVELES MESETA PROFESORES ESTUDIANTES
export PERFILES_DIR="${PERFILES_DIR:-$DIR/perfiles}"
export VIDEO_CORTO="${VIDEO_CORTO:-$PERFILES_DIR/corto.mp4}"
export VIDEO_MEDIO="${VIDEO_MEDIO:-$PERFILES_DIR/medio.mp4}"
export VIDEO_LARGO="${VIDEO_LARGO:-$PERFILES_DIR/largo.mp4}"
export AUDIO_WAV="${AUDIO_WAV:-$PERFILES_DIR/audio.wav}"

k6 run "$DIR/${escenario}.js"
fin="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "| Fin UTC | $fin |" >>"$meta"

if command -v gcloud >/dev/null; then
  "$DIR/metricas.sh" --corrida "$id" --desde "$inicio" --hasta "$fin" || true
else
  echo "sin gcloud: no se recogen métricas de Cloud Monitoring" >&2
fi

echo "evidencia en $SALIDA (corrida-${id}.md, resumen-${escenario}.json, metricas-${id}.*)"
