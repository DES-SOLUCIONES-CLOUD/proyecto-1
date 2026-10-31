#!/usr/bin/env bash
# Una corrida de capacidad con la disciplina que pide el enunciado:
# 10 minutos de reposo (créditos de CPU de e2-small), registro de la
# configuración fija, k6 y recolección de métricas.
#
#   load/correr.sh escenario1
#   load/correr.sh escenario2
#   load/correr.sh escenario3a   # ciclo de autoscaling de la API
#   load/correr.sh escenario3b   # ciclo de autoscaling de los workers
#
# Variables: BASE_URL, REPOSO_S (por defecto 600).
#   escenario1/2:  NIVELES, MESETA, PROFESORES, ESTUDIANTES
#   escenario3a/b: VUS_REPOSO, VUS_PICO, RAMPA, MESETA_INICIAL, MESETA_ALTA, MESETA_BAJA
# El escenario sembrado tiene que estar en load/salida/escenario.json.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

escenario="${1:?uso: $0 escenario1|escenario2|escenario3a|escenario3b}"
case "$escenario" in
  escenario1 | escenario2 | escenario3a | escenario3b) ;;
  *)
    echo "escenario desconocido: $escenario" >&2
    exit 2
    ;;
esac

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
  if [[ "$escenario" == escenario3a || "$escenario" == escenario3b ]]; then
    echo "| VUS_REPOSO | \`${VUS_REPOSO:-sin registrar}\` |"
    echo "| VUS_PICO | \`${VUS_PICO:-sin registrar}\` |"
    echo "| RAMPA | \`${RAMPA:-sin registrar}\` |"
    echo "| MESETA_INICIAL | \`${MESETA_INICIAL:-3m}\` |"
    echo "| MESETA_ALTA | \`${MESETA_ALTA:-sin registrar}\` |"
    echo "| MESETA_BAJA | \`${MESETA_BAJA:-15m}\` |"
  elif [[ "$escenario" == escenario1 ]]; then
    echo "| NIVELES | \`${NIVELES:-50,100,200,300}\` |"
    echo "| RAMPA | \`${RAMPA:-sin registrar}\` |"
    echo "| MESETA | \`${MESETA:-3m}\` |"
  else
    echo "| MESETA | \`${MESETA:-5m}\` |"
    echo "| PROFESORES | \`${PROFESORES:-3}\` |"
    echo "| ESTUDIANTES | \`${ESTUDIANTES:-20}\` |"
  fi
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
export VUS_REPOSO VUS_PICO RAMPA MESETA_INICIAL MESETA_ALTA MESETA_BAJA
export PERFILES_DIR="${PERFILES_DIR:-$DIR/perfiles}"
export VIDEO_CORTO="${VIDEO_CORTO:-$PERFILES_DIR/corto.mp4}"
export VIDEO_MEDIO="${VIDEO_MEDIO:-$PERFILES_DIR/medio.mp4}"
export VIDEO_LARGO="${VIDEO_LARGO:-$PERFILES_DIR/largo.mp4}"
export AUDIO_WAV="${AUDIO_WAV:-$PERFILES_DIR/audio.wav}"

# p(50) y p(99) no están entre las estadísticas por defecto de k6.
k6 run --summary-trend-stats "avg,min,med,max,p(50),p(90),p(95),p(99)" "$DIR/${escenario}.js"
fin="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "| Fin UTC | $fin |" >>"$meta"

if command -v gcloud >/dev/null; then
  "$DIR/metricas.sh" --corrida "$id" --desde "$inicio" --hasta "$fin" || true
else
  echo "sin gcloud: no se recogen métricas de Cloud Monitoring" >&2
fi

echo "evidencia en $SALIDA (corrida-${id}.md, resumen-${escenario}.json, metricas-${id}.*)"
