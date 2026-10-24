#!/usr/bin/env bash
# Se ejecuta EN la VM, como root. El script de arranque
# (terraform/arranque.sh.tftpl) lo copia de los metadatos de la instancia a
# /opt/mooc/bin/en-vm.sh, junto con el .env y el docker-compose.yml del rol,
# y lo llama en cada arranque. También se usa a mano tras
# `deploy/gcp/remoto.sh`.
#
#   en-vm.sh api       # api + frontend (instancias de mig-api)
#   en-vm.sh worker    # worker asynq (instancias de mig-workers)
#   en-vm.sh redis     # redis + mailpit (VM fija)
#   en-vm.sh migrar    # migraciones contra Cloud SQL (en una instancia de API)
#   en-vm.sh sembrar   # datos sintéticos de las pruebas de carga (API)
#   en-vm.sh estado    # contenedores, disco y memoria
#
# Los secretos acaban en el entorno de los contenedores (visible con
# `docker inspect` para quien ya es root en la VM), pero no en disco, ni en
# el repositorio, ni en los metadatos de la VM, ni en la imagen. Cada VM solo
# puede leer los suyos: los permisos están por secreto en Terraform.
set -euo pipefail

BASE="${MOOC_BASE:-/opt/mooc}"

# El rol de esta VM es el único con .env en config/.
rol_local() {
  local r
  for r in api worker redis; do
    [[ -f "$BASE/config/$r.env" ]] && { echo "$r"; return; }
  done
  echo "sin configuración en $BASE/config: ¿terminó el script de arranque? sudo tail -50 /var/log/mooc-arranque.log" >&2
  exit 1
}

accion="${1:?uso: en-vm.sh <api|worker|redis|migrar|sembrar|estado>}"
case "$accion" in
  api|worker|redis) rol="$accion" ;;
  migrar|sembrar)
    rol=api
    [[ "$(rol_local)" == api ]] || { echo "$accion solo corre en una instancia de mig-api" >&2; exit 1; }
    ;;
  estado) rol="$(rol_local)" ;;
  *) echo "acción desconocida '$accion'" >&2; exit 1 ;;
esac

DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${MOOC_CONFIG:-$BASE/config/$rol.env}"
COMPOSE_FILE="$BASE/$rol/docker-compose.yml"
[[ -f "$CONFIG" ]] || { echo "falta $CONFIG (lo escribe el script de arranque desde el metadato mooc-env)" >&2; exit 1; }
[[ -f "$COMPOSE_FILE" ]] || { echo "falta $COMPOSE_FILE (metadato mooc-compose)" >&2; exit 1; }
# shellcheck source=deploy/gcp/env.sh
source "$DIR/env.sh"
cargar_env "$CONFIG"
# El frontend va siempre, salvo que el .env lo declare (aunque sea vacío).
if [[ "$rol" == api && -z "${COMPOSE_PROFILES+x}" ]]; then
  export COMPOSE_PROFILES=frontend
fi

compose() { docker compose -f "$COMPOSE_FILE" --env-file "$CONFIG" "$@"; }

# secreto <nombre>: última versión, vacío si no existe o no hay permiso.
secreto() {
  [[ -n "${1:-}" ]] || return 0
  gcloud secrets versions access latest --secret "$1" --project "${PROYECTO_GCP:?falta PROYECTO_GCP en $CONFIG}" 2>/dev/null || true
}

obligatorio() {
  [[ -n "${!1:-}" ]] || {
    echo "no se pudo leer $1 de Secret Manager (secreto '$2'): ¿existe con versión activa? ¿la cuenta de servicio de esta VM tiene secretAccessor sobre él?" >&2
    exit 1
  }
}

cargar_secretos() {
  # Si ya vienen en el entorno se respetan (pruebas a mano).
  DB_PASSWORD="${DB_PASSWORD:-$(secreto "${SECRETO_DB_PASSWORD:-}")}"
  obligatorio DB_PASSWORD "${SECRETO_DB_PASSWORD:-}"
  S3_SECRET_KEY="${S3_SECRET_KEY:-$(secreto "${SECRETO_S3_SECRET_KEY:-}")}"
  obligatorio S3_SECRET_KEY "${SECRETO_S3_SECRET_KEY:-}"
  export DB_PASSWORD S3_SECRET_KEY
  if [[ "$rol" == api ]]; then
    # La contraseña del administrador solo viaja mientras ADMIN_EMAIL esté
    # definido: el administrador se crea en el primer arranque y después
    # conviene retirar el correo (variable admin_email de Terraform).
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
    if [[ -n "${ADMIN_EMAIL:-}" && -z "$ADMIN_PASSWORD" ]]; then
      ADMIN_PASSWORD="$(secreto "${SECRETO_ADMIN_PASSWORD:-}")"
    fi
    BADGE_SIGNING_KEY="${BADGE_SIGNING_KEY:-$(secreto "${SECRETO_BADGE_SIGNING_KEY:-}")}"
    export ADMIN_PASSWORD BADGE_SIGNING_KEY
  fi
}

# Imágenes de Artifact Registry con la etiqueta de la plantilla (MOOC_TAG,
# normalmente "desplegada", que desplegar-vm.sh mueve al commit desplegado).
fijar_imagenes() {
  : "${REGISTRO:?falta REGISTRO en $CONFIG}"
  local tag="${MOOC_TAG:?falta MOOC_TAG en $CONFIG}"
  if [[ "$rol" == api ]]; then
    export IMAGEN_API="$REGISTRO/mooc-api:$tag"
    export IMAGEN_MIGRATE="$REGISTRO/mooc-migrate:$tag"
    export IMAGEN_SEED="$REGISTRO/mooc-seed:$tag"
    export IMAGEN_FRONTEND="$REGISTRO/mooc-frontend:$tag"
  else
    export IMAGEN_WORKER="$REGISTRO/mooc-worker:$tag"
  fi
}

case "$accion" in
  api|worker)
    cargar_secretos
    fijar_imagenes
    compose pull --quiet
    compose up -d --remove-orphans
    compose ps
    ;;
  redis)
    compose pull --quiet
    compose up -d --remove-orphans
    compose ps
    ;;
  migrar)
    cargar_secretos
    fijar_imagenes
    compose run --rm migrate
    ;;
  sembrar)
    # Cloud SQL solo es alcanzable desde las instancias, así que el sembrador
    # corre aquí. El escenario (ids y sesiones) queda en /opt/mooc/salida
    # para copiarlo a la máquina del generador de carga:
    #   deploy/gcp/remoto.sh api 'sudo cat /opt/mooc/salida/escenario.json' > load/salida/escenario.json
    cargar_secretos
    fijar_imagenes
    mkdir -p /opt/mooc/salida
    compose run --rm \
      -e SEED_STUDENTS="${SEED_STUDENTS:-500}" \
      -e SEED_TEACHERS="${SEED_TEACHERS:-3}" \
      -e SEED_ENROLL="${SEED_ENROLL:-1}" \
      seed
    ;;
  estado)
    compose ps
    df -h / | tail -1
    free -m
    ;;
esac
