#!/usr/bin/env bash
# comprobacion controlada del retiro de un worker en gcp, con cloud sql
#
#   bash deploy/retiro-seguro/demo-gcp.sh preparar     # deja mig-workers en 2
#   bash deploy/retiro-seguro/demo-gcp.sh contenedor   # docker stop (sigterm)
#   bash deploy/retiro-seguro/demo-gcp.sh instancia    # el mig borra la vm
#   bash deploy/retiro-seguro/demo-gcp.sh caida        # docker kill (sigkill)
#   bash deploy/retiro-seguro/demo-gcp.sh restaurar    # vuelve al minimo de 1
#
# 1. espera a que se suba un video desde la web y un worker lo tome. usar uno
#    de un par de minutos: los perfiles de load/perfiles terminan muy rapido
# 2. con ffmpeg trabajando retira ese worker, segun el modo
# 3. sigue los registros de todos hasta que otro termine el mismo activo
# 4. corre verificar.sql contra cloud sql y mira la cola en redis
#
# deja todo en docs/entrega3/evidencias/retiro-seguro/<modo>-<fecha>/ y
# escribe ahi registro.md con lo que va en la seccion 6 de deuda-tecnica.md
#
# los registros se siguen por ssh desde antes de retirar el worker porque
# viven en la vm y en el modo instancia se borran con ella
#
# el modo caida no da oportunidad de liberar el activo: otro worker solo lo
# toma al vencer el arrendamiento de 30 min, por eso tarda mucho mas
#
# variables: ESPERA_S, segundos entre que el worker toma el video y se retira
# (por defecto 20, en una e2-small ffmpeg va mas lento que en local)
source "$(dirname "$0")/../gcp/lib.sh"
requiere terraform base64
comprobar_gcloud
requiere_infra

modo="${1:?uso: demo-gcp.sh preparar|contenedor|instancia|caida|restaurar}"
ESPERA_S="${ESPERA_S:-20}"
CONTENEDOR=mooc-worker-worker-1
ZONA="$(salida zona)"
MIG="$(salida mig_workers)"
DIR="$(cd "$(dirname "$0")" && pwd)"

workers() {
  gc compute instance-groups managed list-instances "$MIG" --zone "$ZONA" \
    --filter 'instanceStatus=RUNNING' --format 'value(name)'
}

# ssh_a <vm> <comando>: ssh_vm entra en la primera instancia del grupo, y aqui
# hace falta elegir cual
ssh_a() {
  local vm="$1"
  shift
  gc compute ssh "$vm" --zone "$ZONA" --tunnel-through-iap --quiet \
    ${OPCIONES_SSH[@]+"${OPCIONES_SSH[@]}"} --command "$*"
}

case "$modo" in
  preparar)
    # con el minimo en 1 no hay quien retome el trabajo. es un cambio manual,
    # valido para esta comprobacion y no como evidencia de autoscaling
    gc compute instance-groups managed update-autoscaling "$MIG" --zone "$ZONA" \
      --min-num-replicas 2 --max-num-replicas 3 --quiet >/dev/null
    gc compute instance-groups managed wait-until "$MIG" --zone "$ZONA" --stable --timeout 900
    aviso "$MIG con minimo 2. Instancias en marcha:"
    workers
    exit 0
    ;;
  restaurar)
    gc compute instance-groups managed update-autoscaling "$MIG" --zone "$ZONA" \
      --min-num-replicas 1 --max-num-replicas 3 --quiet >/dev/null
    aviso "$MIG con minimo 1: el autoscaler reducira cuando pase la estabilizacion"
    exit 0
    ;;
  contenedor | instancia | caida) ;;
  *) morir "modo desconocido '$modo'" ;;
esac

mapfile -t vms < <(workers)
[[ ${#vms[@]} -ge 2 ]] || morir "hacen falta dos workers en marcha y hay ${#vms[@]}: corre primero demo-gcp.sh preparar"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
desde="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
evidencia="$RAIZ/docs/entrega3/evidencias/retiro-seguro/$modo-$stamp"
mkdir -p "$evidencia"
commit="$(git -C "$RAIZ" rev-parse --short=12 HEAD)"

seguidores=()
trap 'kill "${seguidores[@]}" 2>/dev/null || true' EXIT
for vm in "${vms[@]}"; do
  ssh_a "$vm" "sudo docker logs -f --since $desde $CONTENEDOR" >"$evidencia/worker-$vm.log" 2>&1 &
  seguidores+=("$!")
done

echo "==> Sube ahora un video desde la web. Esperando a que un worker lo tome..."
aceptado='trabajo aceptado, empieza la transcodificaci'
elegido=""
for _ in $(seq 1 300); do
  for vm in "${vms[@]}"; do
    if grep -q "$aceptado" "$evidencia/worker-$vm.log"; then
      elegido="$vm"
      break 2
    fi
  done
  sleep 2
done
[[ -n "$elegido" ]] || morir "ningun worker tomo un video en 10 minutos"
linea="$(grep "$aceptado" "$evidencia/worker-$elegido.log" | head -1)"
activo="$(sed -n 's/.*"activo":"\([^"]*\)".*/\1/p' <<<"$linea")"
[[ -n "$activo" ]] || morir "no se pudo leer el activo de: $linea"
echo "    Lo tomo $elegido (activo $activo). Se retira en ${ESPERA_S}s."
sleep "$ESPERA_S"

echo "==> Retirando $elegido (modo $modo)"
retiro="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
inicio=$SECONDS
codigo="no aplica"
case "$modo" in
  contenedor)
    ssh_a "$elegido" "sudo docker stop -t 10 $CONTENEDOR" >/dev/null
    codigo="$(ssh_a "$elegido" "sudo docker inspect -f '{{.State.ExitCode}}' $CONTENEDOR")"
    # el grupo de workers no tiene autohealing: un contenedor detenido deja la
    # instancia viva y sin consumir
    ssh_a "$elegido" "sudo docker start $CONTENEDOR" >/dev/null
    ;;
  caida)
    ssh_a "$elegido" "sudo docker kill $CONTENEDOR" >/dev/null
    codigo="$(ssh_a "$elegido" "sudo docker inspect -f '{{.State.ExitCode}}' $CONTENEDOR")"
    ssh_a "$elegido" "sudo docker start $CONTENEDOR" >/dev/null
    ;;
  instancia)
    gc compute instance-groups managed delete-instances "$MIG" --zone "$ZONA" \
      --instances "$elegido" --quiet >/dev/null
    ;;
esac
duracion=$((SECONDS - inicio))
echo "    Retirado en ${duracion}s, codigo de salida: $codigo"

# 40 min en el modo caida: 30 de arrendamiento mas el video
limite=1200
[[ "$modo" == caida ]] && limite=2400
echo "==> Esperando a que otro worker termine el activo $activo (hasta ${limite}s)"
listo=""
fin=$((SECONDS + limite))
while [[ -z "$listo" && $SECONDS -lt $fin ]]; do
  listo="$(grep -h 'media: activo listo' "$evidencia"/worker-*.log | grep "$activo" || true)"
  [[ -n "$listo" ]] || sleep 5
done
[[ -n "$listo" ]] || morir "el activo $activo no quedo listo en ${limite}s. Registros en $evidencia"
terminados="$(grep -c . <<<"$listo")"

echo "==> Integridad en Cloud SQL"
sql="$(base64 <"$DIR/verificar.sql" | tr -d '\n')"
remoto="$(cat <<REMOTO | base64 | tr -d '\n'
set -euo pipefail
cfg=/opt/mooc/config/api.env
v() { sed -n "s/^\$1=//p" "\$cfg" | head -1; }
export PGPASSWORD="\$(gcloud secrets versions access latest --secret "\$(v SECRETO_DB_PASSWORD)" --project "\$(v PROYECTO_GCP)")"
echo $sql | base64 -d | docker run --rm -i -e PGPASSWORD postgres:16-alpine \
  psql "host=\$(v DB_HOST) user=\$(v DB_USER) dbname=\$(v DB_NAME) sslmode=require"
REMOTO
)"
ssh_vm api "echo $remoto | base64 -d | sudo bash" | tee "$evidencia/verificar.txt"

echo "==> Cola en Redis (pending, active, retry y archived; deben quedar en 0)"
ssh_vm redis "c=mooc-redis-redis-1; for k in pending active; do echo \$k \$(sudo docker exec \$c redis-cli LLEN \"asynq:{default}:\$k\"); done; for k in retry archived; do echo \$k \$(sudo docker exec \$c redis-cli ZCARD \"asynq:{default}:\$k\"); done" \
  | tee "$evidencia/cola.txt"

kill "${seguidores[@]}" 2>/dev/null || true
trap - EXIT

{
  echo "# Retiro de un worker: modo $modo"
  echo
  echo "| Elemento | Valor |"
  echo "|---|---|"
  echo "| Fecha (UTC) | $retiro |"
  echo "| Entorno | GCP, $MIG en $ZONA, Cloud SQL \`$(salida bd_instancia)\` |"
  echo "| Commit | \`$commit\` |"
  echo "| Worker retirado | \`$elegido\` |"
  echo "| Activo | \`$activo\` |"
  echo "| Tiempo del retiro | ${duracion} s |"
  echo "| Codigo de salida | $codigo |"
  echo "| Lineas \`media: activo listo\` del activo | $terminados |"
  echo
  echo "Del worker retirado:"
  echo
  echo '```text'
  grep -E 'retiro|vuelve a la cola|requeued_on_shutdown|worker detenido' "$evidencia/worker-$elegido.log" || true
  echo '```'
  echo
  echo "Del activo, en todos los workers:"
  echo
  echo '```text'
  grep -h "$activo" "$evidencia"/worker-*.log | grep -E 'trabajo aceptado|aplaza|calidad transcodificada|activo listo' || true
  echo '```'
} >"$evidencia/registro.md"

aviso "evidencia en $evidencia"
[[ "$terminados" == 1 ]] || morir "el activo termino $terminados veces, se esperaba 1"
