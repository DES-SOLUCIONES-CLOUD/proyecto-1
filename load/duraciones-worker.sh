#!/usr/bin/env bash
# Duración real de procesamiento, leída de los registros de los workers.
#
#   load/duraciones-worker.sh --corrida formal-e2-2
#
# k6 no puede separar espera y procesamiento: el recurso nunca pasa por el
# estado "processing", así que mooc_espera_cola incluye las dos cosas. Cada
# worker sí registra "media: activo listo" con duracion_ms, pero en el disco
# de la instancia. Hay que correrlo con la cola ya en 0 y antes de que
# mig-workers reduzca (unos 10 minutos): lo que se va con la instancia se
# pierde.
#
# Escribe load/salida/duraciones-<corrida>.jsonl y resume p50/p95/p99.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SALIDA="${SALIDA:-$DIR/salida}"
ZONA="${GCP_ZONE:-us-central1-a}"
CONTENEDOR="${CONTENEDOR_WORKER:-mooc-worker-worker-1}"
corrida=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --corrida) corrida="${2:?}"; shift 2 ;;
    *) echo "uso: $0 --corrida <id>" >&2; exit 2 ;;
  esac
done
[[ -n "$corrida" ]] || { echo "falta --corrida" >&2; exit 2; }

proyecto="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$proyecto" && "$proyecto" != "(unset)" ]] || {
  echo "define GCP_PROJECT_ID o gcloud config set project" >&2
  exit 1
}

mkdir -p "$SALIDA"
destino="$SALIDA/duraciones-${corrida}.jsonl"
: >"$destino"

instancias="$(gcloud compute instance-groups managed list-instances mig-workers \
  --project "$proyecto" --zone "$ZONA" --format='value(instance.basename())')"
for vm in $instancias; do
  echo "leyendo $vm" >&2
  gcloud compute ssh "$vm" --project "$proyecto" --zone "$ZONA" --tunnel-through-iap --quiet \
    --command "sudo docker logs $CONTENEDOR 2>&1 | grep 'media: activo listo'" >>"$destino" \
    || echo "AVISO: sin registros de $vm" >&2
done

python3 - "$destino" <<'PY'
import json, sys

valores = []
with open(sys.argv[1], encoding="utf-8") as f:
    for linea in f:
        try:
            valores.append(float(json.loads(linea)["duracion_ms"]))
        except (ValueError, KeyError, TypeError):
            continue
if not valores:
    sys.exit("AVISO: ningún registro con duracion_ms")
valores.sort()
pct = lambda q: valores[min(len(valores) - 1, round(q / 100 * (len(valores) - 1)))]
print(f"trabajos: {len(valores)}")
print(f"procesamiento p50/p95/p99/max (ms): {pct(50):.0f} / {pct(95):.0f} / {pct(99):.0f} / {valores[-1]:.0f}")
PY
