#!/usr/bin/env bash
# Recoge las métricas de una corrida de capacidad: VM, Cloud SQL y cola.
#
#   load/metricas.sh --corrida esc1-n200 --minutos 15
#   load/metricas.sh --corrida esc2-p3 --desde 2026-09-27T14:00:00Z --hasta 2026-09-27T14:20:00Z
#
# Escribe load/salida/metricas-<corrida>.json y un Markdown colindante.
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

serie() {
  local nombre="$1" tipo="$2"
  gcloud monitoring time-series list \
    --project="$proyecto" \
    --filter="metric.type=\"${tipo}\"" \
    --interval-start-time="$desde" \
    --interval-end-time="$hasta" \
    --format=json >"$tmp/${nombre}.json" 2>/dev/null || echo "[]" >"$tmp/${nombre}.json"
}

echo "recogiendo métricas $desde → $hasta (proyecto $proyecto)" >&2

serie cpu_vm compute.googleapis.com/instance/cpu/utilization
serie memoria_vm agent.googleapis.com/memory/percent_used
serie red_entrada compute.googleapis.com/instance/network/received_bytes_count
serie red_salida compute.googleapis.com/instance/network/sent_bytes_count
serie disco_lectura compute.googleapis.com/instance/disk/read_bytes_count
serie disco_escritura compute.googleapis.com/instance/disk/write_bytes_count
serie cpu_sql cloudsql.googleapis.com/database/cpu/utilization
serie memoria_sql cloudsql.googleapis.com/database/memory/utilization
serie conexiones_sql cloudsql.googleapis.com/database/network/connections

echo null >"$tmp/cola.json"
if [[ -x "$RAIZ/deploy/gcp/remoto.sh" ]]; then
  # Snapshot de asynq al cerrar. No es una serie: profundidad y trabajos
  # reintentados/archivados en ese instante.
  if cola_raw="$("$RAIZ/deploy/gcp/remoto.sh" worker \
      'c=$(sudo docker ps -qf name=redis | head -1); sudo docker exec "$c" redis-cli LLEN "asynq:{default}:pending"; sudo docker exec "$c" redis-cli ZCARD "asynq:{default}:active"; sudo docker exec "$c" redis-cli ZCARD "asynq:{default}:scheduled"; sudo docker exec "$c" redis-cli ZCARD "asynq:{default}:retry"; sudo docker exec "$c" redis-cli ZCARD "asynq:{default}:archived"' \
      2>/dev/null)"; then
    printf '%s\n' "$cola_raw" | python3 -c '
import json,sys
ns=[int(x) for x in sys.stdin.read().split() if x.isdigit()]
keys=["pending","active","scheduled","retry","archived"]
print(json.dumps({k: (ns[i] if i<len(ns) else None) for i,k in enumerate(keys)} | {"fuente":"redis/asynq"}))
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
    "conexiones_sql",
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
for nombre in nombres:
    try:
        series = json.loads((tmp / f"{nombre}.json").read_text(encoding="utf-8") or "[]")
    except json.JSONDecodeError:
        series = []
    out["series"][nombre] = {
        "resumen": resumen(puntos(series)),
        "crudo_n": len(series) if isinstance(series, list) else 0,
    }

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
