#!/usr/bin/env bash
# comprobacion controlada del retiro de un worker en gcp, con cloud sql
#
#   bash deploy/retiro-seguro/demo-gcp.sh preparar     # deja mig-workers en 2
#   bash deploy/retiro-seguro/demo-gcp.sh contenedor   # docker stop (sigterm)
#   bash deploy/retiro-seguro/demo-gcp.sh instancia    # el mig borra la vm
#   bash deploy/retiro-seguro/demo-gcp.sh caida        # docker kill (sigkill)
#   bash deploy/retiro-seguro/demo-gcp.sh restaurar    # vuelve al minimo de 1
#
# para grabar, en otra terminal, despues de lanzar el modo:
#
#   bash deploy/retiro-seguro/demo-gcp.sh registros
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
# solo necesita gcloud con permisos del proyecto y os login, por eso corre
# desde cloud shell. no pasa por deploy/gcp/lib.sh a proposito: ese archivo lee
# el estado de terraform, que contiene secretos, y aqui bastan nombres fijos
#
# los registros se siguen por ssh desde antes de retirar el worker porque
# viven en la vm y en el modo instancia se borran con ella. el worker detenido
# no vuelve a arrancar hasta el final, si no podria retomar el mismo trabajo y
# no se veria a otro terminarlo
#
# el modo caida no da oportunidad de liberar el activo: otro worker solo lo
# toma al vencer el arrendamiento de 30 min, por eso tarda mucho mas
#
# variables: ESPERA_S, segundos entre que el worker toma el video y se retira
# (por defecto 20, en una e2-small ffmpeg va mas lento que en local);
# GCP_PROJECT_ID, GCP_ZONE, MIG_WORKERS, MIG_API, VM_REDIS
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$DIR/../.." && pwd)"
PROYECTO="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
ZONA="${GCP_ZONE:-us-central1-a}"
MIG="${MIG_WORKERS:-mig-workers}"
MIG_API="${MIG_API:-mig-api}"
VM_REDIS="${VM_REDIS:-mooc-redis}"
ESPERA_S="${ESPERA_S:-20}"
CONTENEDOR=mooc-worker-worker-1
CARPETA="$RAIZ/docs/entrega3/evidencias/retiro-seguro"

morir() { echo "error: $*" >&2; exit 1; }
aviso() { echo ">> $*" >&2; }

modo="${1:?uso: demo-gcp.sh preparar|contenedor|instancia|caida|registros|restaurar}"

# registros no toca gcp: solo muestra lo que ya esta guardando el modo en curso
if [[ "$modo" == registros ]]; then
  ultima="$(ls -td "$CARPETA"/*/ 2>/dev/null | head -1)"
  [[ -n "$ultima" ]] || morir "todavia no hay corridas: lanza primero un modo en la otra terminal"
  aviso "siguiendo $ultima"
  # el json se reduce al mensaje y la accion para que se lea en el video.
  # tail escribe el nombre del worker antes de cada grupo de lineas
  cd "$ultima"
  tail -n +1 -f worker-*.log \
    | grep --line-buffered -E '^==>|trabajo aceptado|calidad transcodificada|apagado|retiro|arrendado|detenido|activo listo' \
    | sed -u -E 's/.*"msg":"([^"]*)".*"accion":"([^"]*)".*/\1 [\2]/; s/.*"msg":"([^"]*)".*/\1/'
  exit 0
fi

command -v gcloud >/dev/null || morir "falta gcloud: corre esto desde Cloud Shell"
command -v base64 >/dev/null || morir "falta base64"
[[ -n "$PROYECTO" && "$PROYECTO" != "(unset)" ]] || morir "define GCP_PROJECT_ID o gcloud config set project"

gc() { gcloud --project "$PROYECTO" "$@"; }

en_marcha() {
  gc compute instance-groups managed list-instances "$1" --zone "$ZONA" \
    --filter 'instanceStatus=RUNNING' --format 'value(name)'
}

ssh_a() {
  local vm="$1"
  shift
  gc compute ssh "$vm" --zone "$ZONA" --tunnel-through-iap --quiet --command "$*"
}

case "$modo" in
  preparar)
    # con el minimo en 1 no hay quien retome el trabajo. es un cambio manual,
    # valido para esta comprobacion y no como evidencia de autoscaling
    gc compute instance-groups managed update-autoscaling "$MIG" --zone "$ZONA" \
      --min-num-replicas 2 --max-num-replicas 3 --quiet >/dev/null
    gc compute instance-groups managed wait-until "$MIG" --zone "$ZONA" --stable --timeout 900
    aviso "$MIG con minimo 2. Instancias en marcha:"
    en_marcha "$MIG"
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

mapfile -t vms < <(en_marcha "$MIG")
[[ ${#vms[@]} -ge 2 ]] || morir "hacen falta dos workers en marcha y hay ${#vms[@]}: corre primero demo-gcp.sh preparar"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
desde="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
evidencia="$CARPETA/$modo-$stamp"
mkdir -p "$evidencia"
commit="$(git -C "$RAIZ" rev-parse --short=12 HEAD 2>/dev/null || echo desconocido)"

seguidores=()
elegido=""
detenido=false

# pase lo que pase, el worker no se queda detenido: el grupo de workers no
# tiene autohealing y una instancia viva sin contenedor cuenta como capacidad
limpiar() {
  kill "${seguidores[@]}" 2>/dev/null || true
  if [[ "$detenido" == true ]]; then
    ssh_a "$elegido" "sudo docker start $CONTENEDOR" >/dev/null || aviso "no se pudo reiniciar el worker de $elegido"
  fi
}
trap limpiar EXIT

for vm in "${vms[@]}"; do
  ssh_a "$vm" "sudo docker logs -f --since $desde $CONTENEDOR" >"$evidencia/worker-$vm.log" 2>&1 &
  seguidores+=("$!")
done

echo "==> Sube ahora un video desde la web. Esperando a que un worker lo tome..."
aceptado='trabajo aceptado, empieza la transcodificaci'
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
imagen="$(ssh_a "$elegido" "sudo docker inspect -f '{{.Config.Image}} {{.Image}}' $CONTENEDOR" | tr -d '\r')"
echo "    Lo tomo $elegido (activo $activo). Se retira en ${ESPERA_S}s."
sleep "$ESPERA_S"

echo "==> Retirando $elegido (modo $modo)"
retiro="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
inicio=$SECONDS
codigo="no aplica"
case "$modo" in
  contenedor | caida)
    detenido=true
    if [[ "$modo" == contenedor ]]; then orden="docker stop -t 10"; else orden="docker kill"; fi
    ssh_a "$elegido" "sudo $orden $CONTENEDOR" >/dev/null
    codigo="$(ssh_a "$elegido" "sudo docker inspect -f '{{.State.ExitCode}}' $CONTENEDOR" | tr -d '\r')"
    ;;
  instancia)
    gc compute instance-groups managed delete-instances "$MIG" --zone "$ZONA" \
      --instances "$elegido" --quiet >/dev/null
    ;;
esac
duracion=$((SECONDS - inicio))
echo "    Retirado en ${duracion}s, codigo de salida: $codigo"
# 137 = 128 + 9: docker se canso de esperar y lo mato con sigkill
if [[ "$modo" == contenedor && "$codigo" == 137 ]]; then
  morir "el retiro NO fue limpio: el worker termino con SIGKILL. Registros en $evidencia"
fi

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
espera_total=$((SECONDS - inicio))

mapfile -t apis < <(en_marcha "$MIG_API")
[[ ${#apis[@]} -ge 1 ]] || morir "$MIG_API no tiene instancias en marcha"
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
ssh_a "${apis[0]}" "echo $remoto | base64 -d | sudo bash" | tee "$evidencia/verificar.txt"

echo "==> Cola en Redis (pending, active, retry y archived; deben quedar en 0)"
ssh_a "$VM_REDIS" "c=mooc-redis-redis-1; for k in pending active; do echo \$k \$(sudo docker exec \$c redis-cli LLEN \"asynq:{default}:\$k\"); done; for k in retry archived; do echo \$k \$(sudo docker exec \$c redis-cli ZCARD \"asynq:{default}:\$k\"); done" \
  | tr -d '\r' | tee "$evidencia/cola.txt"

{
  echo "# Retiro de un worker: modo $modo"
  echo
  echo "| Elemento | Valor |"
  echo "|---|---|"
  echo "| Fecha (UTC) | $retiro |"
  echo "| Entorno | GCP, $MIG en $ZONA, proyecto $PROYECTO, con Cloud SQL |"
  echo "| Commit del repositorio | \`$commit\` |"
  echo "| Imagen del worker | \`$imagen\` |"
  echo "| Worker retirado | \`$elegido\` |"
  echo "| Activo | \`$activo\` |"
  echo "| Tiempo del retiro | ${duracion} s |"
  echo "| Codigo de salida | $codigo |"
  echo "| Tiempo hasta \`ready\` desde el retiro | ${espera_total} s |"
  echo "| Lineas \`media: activo listo\` del activo | $terminados |"
  echo
  echo "Del worker retirado:"
  echo
  echo '```text'
  grep -E 'apagado|retiro|vuelve a la cola|requeued_on_shutdown|worker detenido' "$evidencia/worker-$elegido.log" || true
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
