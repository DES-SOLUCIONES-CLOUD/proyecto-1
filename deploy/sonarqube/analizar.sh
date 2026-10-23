#!/usr/bin/env bash
# analisis de deuda tecnica con sonarqube, igual en local y en el ci
#
#   bash deploy/sonarqube/analizar.sh
#
# sin SONAR_HOST_URL levanta sonarqube 10 en docker, cambia la clave del
# admin, crea un token y configura la puerta de calidad de la entrega 3
# con SONAR_HOST_URL y SONAR_TOKEN usa ese servidor y no le cambia nada
#
# deja los resultados en docs/entrega3/evidencias/sonar/ (o en SALIDA):
# resumen.md, medidas.json y hallazgos.json
# sale con error si la puerta de calidad no pasa
#
# variables: SONAR_HOST_URL, SONAR_TOKEN, SONAR_ORGANIZATION (sonarcloud),
# SONAR_ADMIN_PASSWORD (solo en local), SALIDA
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$DIR/../.." && pwd)"
SALIDA="${SALIDA:-$RAIZ/docs/entrega3/evidencias/sonar}"
PROYECTO="mooc-plataforma"
# umbrales del enunciado, la puerta solo se crea en modo local
PUERTA="Entrega 3"
DUPLICACION_MAXIMA=20
MANTENIBILIDAD_MINIMA=3 # sqale_rating: 1=a ... 3=c ... 5=e, peor que c falla

compose=(docker compose -f "$DIR/docker-compose.yml")
PY="$(command -v python3 || command -v python)"
mkdir -p "$SALIDA"

local_=false
if [[ -z "${SONAR_HOST_URL:-}" ]]; then
  local_=true
  SONAR_HOST_URL="http://localhost:9000"
  ADMIN_PASS="${SONAR_ADMIN_PASSWORD:-Mooc-Sonar-2026!}"

  echo "==> Levantando SonarQube 10 Community"
  "${compose[@]}" up -d sonarqube
  for _ in $(seq 1 90); do
    estado="$(curl -fsS "$SONAR_HOST_URL/api/system/status" 2>/dev/null | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["status"])' 2>/dev/null || true)"
    [[ "$estado" == "UP" ]] && break
    sleep 5
  done
  [[ "${estado:-}" == "UP" ]] || { echo "SonarQube no arranco en 7 minutos" >&2; exit 1; }

  # la primera vez la clave es admin/admin y hay que cambiarla
  # si ya se cambio antes esto falla y no pasa nada
  curl -fsS -u admin:admin -X POST "$SONAR_HOST_URL/api/users/change_password" \
    --data-urlencode "login=admin" --data-urlencode "previousPassword=admin" \
    --data-urlencode "password=$ADMIN_PASS" >/dev/null 2>&1 || true

  api() { curl -fsS -u "admin:$ADMIN_PASS" -X POST "$SONAR_HOST_URL/api/$1" "${@:2}"; }

  echo "==> Puerta de calidad \"$PUERTA\": duplicacion <= $DUPLICACION_MAXIMA% y mantenibilidad C o mejor"
  if api qualitygates/create --data-urlencode "name=$PUERTA" >/dev/null 2>&1; then
    api qualitygates/create_condition --data-urlencode "gateName=$PUERTA" \
      -d metric=duplicated_lines_density -d op=GT -d "error=$DUPLICACION_MAXIMA" >/dev/null
    api qualitygates/create_condition --data-urlencode "gateName=$PUERTA" \
      -d metric=sqale_rating -d op=GT -d "error=$MANTENIBILIDAD_MINIMA" >/dev/null
  fi
  api qualitygates/set_as_default --data-urlencode "name=$PUERTA" >/dev/null

  SONAR_TOKEN="$(api user_tokens/generate --data-urlencode "name=analisis-$(date +%s)" \
    -d type=GLOBAL_ANALYSIS_TOKEN | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["token"])')"
  # dentro de la red del compose el servidor se llama sonarqube
  url_scanner="http://sonarqube:9000"
  # el token de analisis solo sirve para analizar, la api de lectura
  # responde 403 con el, por eso los resultados se leen como admin
  auth_lectura="admin:$ADMIN_PASS"
else
  : "${SONAR_TOKEN:?con SONAR_HOST_URL hace falta SONAR_TOKEN}"
  url_scanner="$SONAR_HOST_URL"
  auth_lectura="$SONAR_TOKEN:"
fi

extra=()
[[ -n "${SONAR_ORGANIZATION:-}" ]] && extra+=("-Dsonar.organization=$SONAR_ORGANIZATION")
commit="$(git -C "$RAIZ" rev-parse --short HEAD 2>/dev/null || echo desconocido)"

echo "==> Analizando el commit $commit"
# qualitygate.wait hace que el scanner espere el resultado y falle si la
# puerta no pasa. se guarda el codigo de salida para recoger los resultados
# igual, sobre todo cuando falla
set +e
SONAR_HOST_URL="$url_scanner" SONAR_TOKEN="$SONAR_TOKEN" \
  "${compose[@]}" run --rm $([[ $local_ == false ]] && echo --no-deps) scanner \
  -Dsonar.projectVersion="$commit" \
  -Dsonar.working.directory=/tmp/scannerwork \
  -Dsonar.qualitygate.wait=true -Dsonar.qualitygate.timeout=600 \
  "${extra[@]}"
resultado=$?
set -e

echo "==> Recogiendo la evidencia en $SALIDA"
leer() { curl -fsS -u "$auth_lectura" "$SONAR_HOST_URL/api/$1"; }
leer "measures/component?component=$PROYECTO&metricKeys=ncloc,duplicated_lines_density,duplicated_blocks,sqale_rating,sqale_index,sqale_debt_ratio,reliability_rating,security_rating,bugs,vulnerabilities,code_smells,security_hotspots,coverage" \
  > "$SALIDA/medidas.json"
leer "qualitygates/project_status?projectKey=$PROYECTO" > "$SALIDA/puerta.json"
# hasta 500 hallazgos abiertos, del mas grave al menos grave
# con esto se arma el inventario de docs/entrega3/deuda-tecnica.md
leer "issues/search?componentKeys=$PROYECTO&resolved=false&ps=500&s=SEVERITY&asc=false&facets=severities,types,rules" \
  > "$SALIDA/hallazgos.json"

"$PY" "$DIR/resumen.py" "$SALIDA" "$commit" "$SONAR_HOST_URL" | tee "$SALIDA/resumen.md"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$SALIDA/resumen.md" >> "$GITHUB_STEP_SUMMARY"
fi

if [[ $local_ == true ]]; then
  echo
  echo "Panel: $SONAR_HOST_URL/dashboard?id=$PROYECTO (admin / la clave de SONAR_ADMIN_PASSWORD)"
fi
exit $resultado
