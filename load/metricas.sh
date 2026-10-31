#!/usr/bin/env bash
# Recoge las métricas de una corrida de capacidad: VM, Cloud SQL y cola.
#
#   load/metricas.sh --corrida esc1-n200 --minutos 15
#   load/metricas.sh --corrida esc2-p3 --desde 2026-09-27T14:00:00Z --hasta 2026-09-27T14:20:00Z
#
# Escribe load/salida/metricas-<corrida>.json, un Markdown colindante y
# series-<corrida>.csv con los puntos crudos. Un resumen por instancia.
# Requiere gcloud autenticado en el proyecto del despliegue.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$DIR/.." && pwd)"
SALIDA="${SALIDA:-$DIR/salida}"
corrida=""
minutos=15
desde=""
hasta=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --corrida) corrida="${2:?}"; shift 2 ;;
    --minutos) minutos="${2:?}"; shift 2 ;;
    --desde) desde="${2:?}"; shift 2 ;;
    --hasta) hasta="${2:?}"; shift 2 ;;
    *) echo "uso: $0 --corrida <id> [--minutos N | --desde RFC3339 --hasta RFC3339]" >&2; exit 2 ;;
  esac
done
[[ -n "$corrida" ]] || { echo "falta --corrida" >&2; exit 2; }

if [[ -z "$desde" ]]; then
  hasta="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if date -u -d "-${minutos} minutes" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    desde="$(date -u -d "-${minutos} minutes" +%Y-%m-%dT%H:%M:%SZ)"
  else
    desde="$(python3 -c "from datetime import datetime,timedelta,timezone; print((datetime.now(timezone.utc)-timedelta(minutes=${minutos})).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  fi
fi
[[ -n "$hasta" ]] || hasta="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

proyecto="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$proyecto" && "$proyecto" != "(unset)" ]] || {
  echo "define GCP_PROJECT_ID o gcloud config set project" >&2
  exit 1
}

mkdir -p "$SALIDA"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Por la API REST y no por gcloud: los errores tienen que verse. Una serie
# vacía en silencio deja la corrida sin evidencia y nadie se entera.
serie() {
  local nombre="$1" filtro="$2"
  python3 "$DIR/serie-monitoring.py" "$proyecto" "$filtro" "$desde" "$hasta" \
    >"$tmp/${nombre}.json" || {
    echo "AVISO: sin datos de $nombre" >&2
    echo "[]" >"$tmp/${nombre}.json"
  }
}

echo "recogiendo métricas $desde → $hasta (proyecto $proyecto)" >&2

serie cpu_vm 'metric.type="compute.googleapis.com/instance/cpu/utilization"'
serie memoria_vm 'metric.type="agent.googleapis.com/memory/percent_used" AND metric.labels.state="used"'
serie red_entrada 'metric.type="compute.googleapis.com/instance/network/received_bytes_count"'
serie red_salida 'metric.type="compute.googleapis.com/instance/network/sent_bytes_count"'
serie disco_lectura 'metric.type="compute.googleapis.com/instance/disk/read_bytes_count"'
serie disco_escritura 'metric.type="compute.googleapis.com/instance/disk/write_bytes_count"'
serie cpu_sql 'metric.type="cloudsql.googleapis.com/database/cpu/utilization"'
serie memoria_sql 'metric.type="cloudsql.googleapis.com/database/memory/utilization"'
serie conexiones_sql 'metric.type="cloudsql.googleapis.com/database/network/connections"'
serie lb_peticiones 'metric.type="loadbalancing.googleapis.com/https/backend_request_count"'
serie tamano_mig 'metric.type="compute.googleapis.com/instance_group/size"'

echo null >"$tmp/cola.json"
if [[ -x "$RAIZ/deploy/gcp/remoto.sh" ]]; then
  # Foto al cerrar. La serie completa la deja observar.sh.
  programa="$(base64 -w0 "$DIR/cola-en-redis.sh")"
  if cola_raw="$("$RAIZ/deploy/gcp/remoto.sh" redis "echo $programa | base64 -d | bash -s -- 0" 2>/dev/null)"; then
    printf '%s\n' "$cola_raw" | python3 -c '
import json,sys
claves=["ts_utc","cola","pending","active","scheduled","retry","archived","antiguedad_s"]
print(json.dumps({"fuente":"redis/asynq","colas":[dict(zip(claves,l.split(","))) for l in sys.stdin.read().split()]}))
' >"$tmp/cola.json" || echo null >"$tmp/cola.json"
  fi
fi

python3 - "$SALIDA" "$corrida" "$desde" "$hasta" "$proyecto" "$tmp" <<'PY'
import json, statistics, sys
from pathlib import Path

salida, corrida, desde, hasta, proyecto, tmp = sys.argv[1:7]
tmp = Path(tmp)
nombres = [
    "cpu_vm", "memoria_vm", "red_entrada", "red_salida",
    "disco_lectura", "disco_escritura", "cpu_sql", "memoria_sql",
    "conexiones_sql", "lb_peticiones", "tamano_mig",
]

def puntos(series):
    vals = []
    if not isinstance(series, list):
        return vals
    for s in series:
        for p in s.get("points", []):
            v = p.get("value", {})
            if "doubleValue" in v:
                vals.append(float(v["doubleValue"]))
            elif "int64Value" in v:
                vals.append(float(v["int64Value"]))
    return vals

def origen(s):
    """De qué instancia, grupo o base sale una serie."""
    metrica = s.get("metric", {}).get("labels", {})
    recurso = s.get("resource", {}).get("labels", {})
    for valor in (
        metrica.get("instance_name"),
        recurso.get("instance_group_manager_name"),
        recurso.get("instance_group_name"),
        recurso.get("backend_name"),
        recurso.get("database_id"),
        recurso.get("instance_id"),
    ):
        if valor:
            return valor
    return "desconocido"

def resumen(vals):
    if not vals:
        return {"n": 0}
    vals = sorted(vals)
    def pct(q):
        i = min(len(vals) - 1, max(0, int(round((q / 100) * (len(vals) - 1)))))
        return vals[i]
    return {
        "n": len(vals),
        "min": vals[0],
        "p50": pct(50),
        "p95": pct(95),
        "p99": pct(99),
        "max": vals[-1],
        "media": statistics.fmean(vals),
    }

out = {
    "corrida": corrida,
    "desde": desde,
    "hasta": hasta,
    "proyecto": proyecto,
    "series": {},
}
# Un resumen por origen: promediar la CPU de la API con la de Redis y los
# workers no dice nada. Los puntos crudos van a un CSV para las gráficas.
crudo = Path(salida) / f"series-{corrida}.csv"
with crudo.open("w", encoding="utf-8") as f:
    f.write("serie,origen,ts_utc,valor\n")
    for nombre in nombres:
        try:
            series = json.loads((tmp / f"{nombre}.json").read_text(encoding="utf-8") or "[]")
        except json.JSONDecodeError:
            series = []
        por_origen = {}
        for s in series:
            por_origen.setdefault(origen(s), []).append(s)
            for p in s.get("points", []):
                v = p.get("value", {})
                valor = v.get("doubleValue", v.get("int64Value"))
                if valor is not None:
                    f.write(f"{nombre},{origen(s)},{p['interval']['endTime']},{valor}\n")
        for fuente, grupo in sorted(por_origen.items()):
            out["series"][f"{nombre}/{fuente}"] = {
                "resumen": resumen(puntos(grupo)),
                "crudo_n": len(grupo),
            }
        if not por_origen:
            out["series"][nombre] = {"resumen": {"n": 0}, "crudo_n": 0}

try:
    out["cola"] = json.loads((tmp / "cola.json").read_text(encoding="utf-8"))
except json.JSONDecodeError:
    out["cola"] = None

destino = Path(salida) / f"metricas-{corrida}.json"
destino.write_text(json.dumps(out, indent=2), encoding="utf-8")

lineas = [
    f"# Métricas — {corrida}",
    "",
    f"- Ventana: `{desde}` → `{hasta}`",
    f"- Proyecto: `{proyecto}`",
    "",
    "| Serie | n | p50 | p95 | p99 | max |",
    "|---|---:|---:|---:|---:|---:|",
]
for nombre, bloque in out["series"].items():
    r = bloque["resumen"]
    if not r.get("n"):
        lineas.append(f"| {nombre} | 0 | — | — | — | — |")
        continue
    lineas.append(
        f"| {nombre} | {r['n']} | {r['p50']:.4g} | {r['p95']:.4g} | {r['p99']:.4g} | {r['max']:.4g} |"
    )
lineas += ["", "## Cola (snapshot al cerrar)", "", "```json", json.dumps(out.get("cola"), indent=2), "```", ""]
md = Path(salida) / f"metricas-{corrida}.md"
md.write_text("\n".join(lineas), encoding="utf-8")
print(destino)
print(md)
PY
