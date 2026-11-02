#!/usr/bin/env bash
# Series de tiempo de una corrida de autoscaling: instancias de cada MIG y
# estado de la cola. Cloud Monitoring no sabe nada de Redis y sus métricas
# llegan con minutos de retraso, así que esto se guarda aparte.
#
#   load/observar.sh --corrida esc3a-1 [--cada 15]
#
# Corre hasta recibir Ctrl-C o SIGTERM. Escribe en load/salida:
#   serie-<corrida>-mig.csv    ts_utc,mig,objetivo,recomendado,estables,en_cambio
#   serie-<corrida>-cola.csv   ts_utc,cola,pending,active,scheduled,retry,archived,antiguedad_s
#
# Necesita gcloud con permisos del proyecto y OS Login: se corre desde Cloud
# Shell o un portátil, no desde mooc-k6. No pasa por remoto.sh a propósito:
# ese script lee el estado de Terraform, que contiene secretos, y aquí solo
# hace falta el nombre de una VM fija (VM_REDIS).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SALIDA="${SALIDA:-$DIR/salida}"
ZONA="${GCP_ZONE:-us-central1-a}"
VM_REDIS="${VM_REDIS:-mooc-redis}"
corrida=""
cada=15

while [[ $# -gt 0 ]]; do
  case "$1" in
    --corrida) corrida="${2:?}"; shift 2 ;;
    --cada) cada="${2:?}"; shift 2 ;;
    *) echo "uso: $0 --corrida <id> [--cada segundos]" >&2; exit 2 ;;
  esac
done
[[ -n "$corrida" ]] || { echo "falta --corrida" >&2; exit 2; }

proyecto="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$proyecto" && "$proyecto" != "(unset)" ]] || {
  echo "define GCP_PROJECT_ID o gcloud config set project" >&2
  exit 1
}

mkdir -p "$SALIDA"
csv_mig="$SALIDA/serie-${corrida}-mig.csv"
csv_cola="$SALIDA/serie-${corrida}-cola.csv"
echo "ts_utc,mig,objetivo,recomendado,estables,en_cambio" >"$csv_mig"
echo "ts_utc,cola,pending,active,scheduled,retry,archived,antiguedad_s" >"$csv_cola"

# Una sola sesión SSH: abrir un túnel de IAP en cada lectura tarda varios
# segundos y deformaría la serie.
programa="$(base64 -w0 "$DIR/cola-en-redis.sh")"
gcloud compute ssh "$VM_REDIS" --project "$proyecto" --zone "$ZONA" --tunnel-through-iap --quiet \
  --command "echo $programa | base64 -d | bash -s -- $cada" >>"$csv_cola" &
pid_cola=$!
trap 'kill "$pid_cola" 2>/dev/null || true' EXIT
trap 'exit 0' INT TERM

leer_mig() {
  local mig="$1" ts tamanos estados estables en_cambio
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tamanos="$(gcloud compute instance-groups managed describe "$mig" \
    --project "$proyecto" --zone "$ZONA" \
    --format='csv[no-heading](targetSize,autoscaler.recommendedSize)')" || return 0
  estados="$(gcloud compute instance-groups managed list-instances "$mig" \
    --project "$proyecto" --zone "$ZONA" --format='value(currentAction)')" || return 0
  estables="$(grep -c '^NONE$' <<<"$estados" || true)"
  en_cambio="$(grep -cv -e '^NONE$' -e '^$' <<<"$estados" || true)"
  echo "$ts,$mig,$tamanos,$estables,$en_cambio" >>"$csv_mig"
}

echo "observando $corrida cada ${cada}s; Ctrl-C para terminar" >&2
while true; do
  leer_mig mig-api
  leer_mig mig-workers
  sleep "$cada"
done
