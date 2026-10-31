#!/usr/bin/env bash
# Lee la cola asynq desde la VM de Redis. No se ejecuta a mano: observar.sh y
# metricas.sh lo mandan por SSH, para no pelear con las comillas de Lua.
#
#   cola-en-redis.sh 0    # una sola lectura
#   cola-en-redis.sh 15   # una lectura cada 15 s, hasta que corten la sesión
#
# CSV: ts_utc,cola,pending,active,scheduled,retry,archived,antiguedad_s
#
# Las claves y los tipos son los de asynq 0.26: pending y active son listas,
# scheduled, retry y archived son conjuntos ordenados. La antigüedad sale del
# campo pending_since (nanosegundos) de la tarea más vieja, que es de donde la
# calcula el propio asynq.
set -euo pipefail

cada="${1:-0}"
c="$(sudo docker ps -qf name=redis | head -1)"
[[ -n "$c" ]] || { echo "no hay contenedor de redis en esta VM" >&2; exit 1; }

lua='
local p = "asynq:{" .. ARGV[1] .. "}:"
local desde = 0
local id = redis.call("LRANGE", p .. "pending", -1, -1)[1]
if id then desde = redis.call("HGET", p .. "t:" .. id, "pending_since") or 0 end
return {
  tostring(redis.call("LLEN", p .. "pending")),
  tostring(redis.call("LLEN", p .. "active")),
  tostring(redis.call("ZCARD", p .. "scheduled")),
  tostring(redis.call("ZCARD", p .. "retry")),
  tostring(redis.call("ZCARD", p .. "archived")),
  tostring(desde),
}'

leer() {
  local ts cola campos ahora
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for cola in critical default; do
    mapfile -t campos < <(sudo docker exec "$c" redis-cli --raw EVAL "$lua" 0 "$cola")
    ahora="$(date +%s%N)"
    awk -v ts="$ts" -v cola="$cola" -v ahora="$ahora" \
      -v p="${campos[0]}" -v a="${campos[1]}" -v s="${campos[2]}" \
      -v r="${campos[3]}" -v x="${campos[4]}" -v d="${campos[5]}" \
      'BEGIN { printf "%s,%s,%s,%s,%s,%s,%s,%.1f\n", ts, cola, p, a, s, r, x, (d > 0 ? (ahora - d) / 1e9 : 0) }'
  done
}

if [[ "$cada" == 0 ]]; then
  leer
  exit 0
fi
while true; do
  leer
  sleep "$cada"
done
