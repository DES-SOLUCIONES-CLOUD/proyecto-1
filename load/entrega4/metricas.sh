#!/usr/bin/env bash
# Métricas de escalamiento de la Entrega 4, leídas de Cloud Monitoring:
#
#   - run.googleapis.com/container/instance_count   instancias por servicio y estado (active/idle)
#   - run.googleapis.com/request_count              peticiones por servicio y clase de respuesta
#   - pubsub .../num_undelivered_messages           mensajes pendientes de la suscripción push
#   - pubsub .../oldest_unacked_message_age         antigüedad del mensaje más viejo sin ack
#
#   load/entrega4/metricas.sh [<minutos hacia atrás>]   # por defecto 30
#
# Imprime una tabla por minuto (máximo de cada serie en el minuto) y guarda
# las series crudas en load/salida/e4-metricas-<fecha>.json. Las métricas de
# Cloud Run llegan con 1-3 minutos de retraso: correrlo un rato después de la
# carga.
set -euo pipefail

MIN="${1:-30}"
PROYECTO="${PROYECTO:-$(gcloud config get-value project 2>/dev/null)}"
PREFIJO="${PREFIJO:-mooc}"
SUSCRIPCION="${SUSCRIPCION:-$PREFIJO-tareas-push}"
TOKEN="$(gcloud auth print-access-token)"
FIN="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
INICIO="$(date -u -d "-$MIN min" +%Y-%m-%dT%H:%M:%SZ)"
SALIDA="$(dirname "$0")/../salida"
mkdir -p "$SALIDA"
ARCHIVO="$SALIDA/e4-metricas-$(date +%Y%m%d-%H%M%S).json"

serie() { # serie <filtro> <alineador>
  curl -sS -G -H "Authorization: Bearer $TOKEN" \
    "https://monitoring.googleapis.com/v3/projects/$PROYECTO/timeSeries" \
    --data-urlencode "filter=$1" \
    --data-urlencode "interval.startTime=$INICIO" \
    --data-urlencode "interval.endTime=$FIN" \
    --data-urlencode "aggregation.alignmentPeriod=60s" \
    --data-urlencode "aggregation.perSeriesAligner=$2"
}

{
  echo '{'
  echo '"instancias":'; serie 'metric.type="run.googleapis.com/container/instance_count" AND resource.type="cloud_run_revision"' ALIGN_MAX; echo ','
  echo '"peticiones":'; serie 'metric.type="run.googleapis.com/request_count" AND resource.type="cloud_run_revision"' ALIGN_DELTA; echo ','
  echo '"pendientes":'; serie "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" AND resource.label.subscription_id=\"$SUSCRIPCION\"" ALIGN_MAX; echo ','
  echo '"antiguedad":'; serie "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" AND resource.label.subscription_id=\"$SUSCRIPCION\"" ALIGN_MAX
  echo '}'
} > "$ARCHIVO"

python3 - "$ARCHIVO" <<'EOF'
import json, sys
from collections import defaultdict
d = json.load(open(sys.argv[1]))
filas = defaultdict(dict)
cols = []
def valor(p):
    v = p["value"]
    return float(v.get("int64Value", v.get("doubleValue", 0)))
def agregar(nombre, serie):
    if nombre not in cols:
        cols.append(nombre)
    for p in serie.get("points", []):
        t = p["interval"]["endTime"][11:16]
        filas[t][nombre] = filas[t].get(nombre, 0) + valor(p)
for s in d["instancias"].get("timeSeries", []):
    svc = s["resource"]["labels"]["service_name"].replace("mooc-", "")
    agregar(f"inst {svc} {s['metric']['labels'].get('state', '')}", s)
for s in d["peticiones"].get("timeSeries", []):
    svc = s["resource"]["labels"]["service_name"].replace("mooc-", "")
    agregar(f"req {svc} {s['metric']['labels'].get('response_code_class', '')}", s)
for s in d["pendientes"].get("timeSeries", []):
    agregar("pubsub pendientes", s)
for s in d["antiguedad"].get("timeSeries", []):
    agregar("pubsub antig s", s)
cols.sort()
print("| UTC | " + " | ".join(cols) + " |")
print("|---" * (len(cols) + 1) + "|")
for t in sorted(filas):
    print(f"| {t} | " + " | ".join(str(int(filas[t].get(c, 0))) for c in cols) + " |")
maximos = {c: int(max((filas[t].get(c, 0) for t in filas), default=0)) for c in cols if c.startswith("inst") and "active" in c}
print("\nMáximo de instancias activas por servicio:", maximos)
EOF
echo "series crudas: $ARCHIVO"
