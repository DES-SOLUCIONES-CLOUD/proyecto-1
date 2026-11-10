#!/usr/bin/env bash
# Imprime en Markdown la configuración efectiva del entorno: lo que de verdad
# está corriendo, leído de GCP, no lo que dicen las variables. Es la
# evidencia que el informe de capacidad pide registrar en cada corrida (tipo
# de los servicios de Cloud Run, instancias, tier de la base, imagen).
#
#   deploy/gcp/resumen.sh                   # a la terminal
#   deploy/gcp/resumen.sh >> "$GITHUB_STEP_SUMMARY"
#
# Lee las APIs de Cloud Run, Compute Engine y Cloud SQL y las salidas de
# Terraform. No imprime secretos.
source "$(dirname "$0")/lib.sh"
requiere terraform curl jq
comprobar_gcloud
requiere_infra

ZONA="$(salida zona)"
URL="$(salida url_publica)"
BD="$(salida bd_instancia)"
REGISTRO="$(salida registro)"
REGION="$(salida region)"

# servicio <nombre>: configuración de la revisión que recibe el tráfico, leída
# de Cloud Run (no de las variables de Terraform).
servicio() {
  local datos
  datos="$(gc run services describe "$1" --region "$REGION" --format json 2>/dev/null || true)"
  [[ -n "$datos" ]] || { echo "no existe"; return; }
  jq -r '
    .spec.template as $t |
    ($t.metadata.annotations // {}) as $a |
    "\($a["autoscaling.knative.dev/minScale"] // "0")-\($a["autoscaling.knative.dev/maxScale"] // "?") instancias, " +
    "\($t.spec.containers[0].resources.limits.cpu) vCPU, \($t.spec.containers[0].resources.limits.memory), " +
    "concurrencia \($t.spec.containerConcurrency), timeout \($t.spec.timeoutSeconds) s, " +
    "ingress \(.metadata.annotations["run.googleapis.com/ingress"]), revisión \(.status.latestReadyRevisionName), " +
    "imagen `\($t.spec.containers[0].image | split(":") | last)`"' <<<"$datos"
}

vm() {
  local datos
  datos="$(gc compute instances describe "$1" --zone "$ZONA" \
             --format 'value(machineType.basename(),status,networkInterfaces[0].networkIP)' 2>/dev/null || true)"
  [[ -n "$datos" ]] || { echo "no existe"; return; }
  awk -F'\t' '{printf "%s, %s, IP interna %s", $1, $2, $3}' <<<"$datos"
}

if [[ -n "$BD" ]]; then
  bd="$(gc sql instances describe "$BD" \
          --format 'value(settings.tier,settings.edition,state,settings.activationPolicy,settings.dataDiskSizeGb)' 2>/dev/null \
        | tr '\t' ' ' || true)"
  bd="$BD: ${bd:-sin datos}"
else
  bd="sin instancia (crear_bd=false)"
fi

# Salud: primero con verificación de certificado; si solo responde sin
# verificar, el certificado administrado aún no está activo.
salud="sin respuesta"
if codigo="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL/api/v1/health")" && [[ "$codigo" != 000 ]]; then
  salud="HTTP $codigo, certificado válido"
elif codigo="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$URL/api/v1/health")" && [[ "$codigo" != 000 ]]; then
  salud="HTTP $codigo, certificado aún no activo ($(salida certificado))"
fi

cat <<EOF
### Configuración efectiva en GCP

| | |
|---|---|
| URL pública | $URL (IP del balanceador $(salida ip_lb)) |
| Salud de la API | $salud |
| Proyecto, región y zona | $(salida proyecto), $REGION, $ZONA |
| Cloud Run $(salida run_frontend) | $(servicio "$(salida run_frontend)") |
| Cloud Run $(salida run_api) | $(servicio "$(salida run_api)") |
| Cloud Run $(salida run_worker) | $(servicio "$(salida run_worker)") |
| Pub/Sub | topic $(salida pubsub_topic), suscripción push $(salida pubsub_suscripcion), dead-letter $(salida pubsub_dlq) |
| $(salida vm_redis) | $(vm "$(salida vm_redis)") |
| Cloud SQL (tier, edición, estado, activación, GB) | $bd |
| Cloud NAT | $(salida nat_activa) |
| Registro de imágenes | $REGISTRO |

Leído el $(TZ=America/Bogota date '+%Y-%m-%d %H:%M') hora de Colombia ($(date -u '+%H:%M') UTC).
EOF
