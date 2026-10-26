#!/usr/bin/env bash
# Imprime en Markdown la configuración efectiva del entorno: lo que de verdad
# está corriendo, leído de GCP, no lo que dicen las variables. Es la
# evidencia que el informe de capacidad pide registrar en cada corrida (tipo
# de VM, tamaño de los MIG, tier de la base, commit).
#
#   deploy/gcp/resumen.sh                   # a la terminal
#   deploy/gcp/resumen.sh >> "$GITHUB_STEP_SUMMARY"
#
# No entra en las VM: lee la API de Compute Engine y las salidas de
# Terraform. No imprime secretos.
source "$(dirname "$0")/lib.sh"
requiere terraform curl
comprobar_gcloud
requiere_infra

ZONA="$(salida zona)"
URL="$(salida url_publica)"
BD="$(salida bd_instancia)"
REGISTRO="$(salida registro)"
ETIQUETA="$(salida imagen_tag)"

# mig <nombre>: tipo de máquina de la plantilla vigente, instancias en marcha
# y política del autoscaler.
mig() {
  local plantilla tipo en_marcha autoscaler politica
  plantilla="$(gc compute instance-groups managed describe "$1" --zone "$ZONA" \
                 --format 'value(versions[0].instanceTemplate.basename())' 2>/dev/null || true)"
  [[ -n "$plantilla" ]] || { echo "no existe"; return; }
  tipo="$(gc compute instance-templates describe "$plantilla" \
            --format 'value(properties.machineType)' 2>/dev/null || true)"
  en_marcha="$(gc compute instance-groups managed list-instances "$1" --zone "$ZONA" \
                 --filter 'instanceStatus=RUNNING' --format 'value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  autoscaler="$(gc compute instance-groups managed describe "$1" --zone "$ZONA" \
                  --format 'value(status.autoscaler.basename())' 2>/dev/null || true)"
  politica="sin autoscaler"
  if [[ -n "$autoscaler" ]]; then
    politica="$(gc compute autoscalers describe "$autoscaler" --zone "$ZONA" \
                  --format 'value(autoscalingPolicy.mode,autoscalingPolicy.minNumReplicas,autoscalingPolicy.maxNumReplicas,autoscalingPolicy.cpuUtilization.utilizationTarget,autoscalingPolicy.coolDownPeriodSec)' 2>/dev/null \
                | awk -F'\t' '{printf "autoscaler %s, %s-%s instancias, CPU %s, cooldown %s s", $1, $2, $3, $4, $5}')"
  fi
  printf '%s, %s en marcha, %s' "${tipo:-?}" "$en_marcha" "$politica"
}

vm() {
  local datos
  datos="$(gc compute instances describe "$1" --zone "$ZONA" \
             --format 'value(machineType.basename(),status,networkInterfaces[0].networkIP)' 2>/dev/null || true)"
  [[ -n "$datos" ]] || { echo "no existe"; return; }
  awk -F'\t' '{printf "%s, %s, IP interna %s", $1, $2, $3}' <<<"$datos"
}

# Commit al que apunta la etiqueta móvil: el otro tag con el mismo digest.
commit_desplegado() {
  local digest
  digest="$(gc artifacts docker images describe "$REGISTRO/mooc-api:$ETIQUETA" \
              --format 'value(image_summary.digest)' 2>/dev/null || true)"
  [[ -n "$digest" ]] || { echo "?"; return; }
  gc artifacts docker tags list "$REGISTRO/mooc-api" --format 'value(tag.basename(),version.basename())' 2>/dev/null \
    | awk -F'\t' -v d="$digest" -v e="$ETIQUETA" '$2 == d && $1 != e {print $1; exit}'
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
| Commit desplegado | \`$(commit_desplegado)\` (etiqueta \`$ETIQUETA\`) |
| Proyecto, región y zona | $(salida proyecto), $(salida region), $ZONA |
| $(salida mig_api) | $(mig "$(salida mig_api)") |
| $(salida mig_workers) | $(mig "$(salida mig_workers)") |
| $(salida vm_redis) | $(vm "$(salida vm_redis)") |
| Cloud SQL (tier, edición, estado, activación, GB) | $bd |
| Cloud NAT | $(salida nat_activa) |
| Registro de imágenes | $REGISTRO |

Leído el $(TZ=America/Bogota date '+%Y-%m-%d %H:%M') hora de Colombia ($(date -u '+%H:%M') UTC).
EOF
