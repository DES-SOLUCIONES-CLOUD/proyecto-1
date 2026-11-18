#!/usr/bin/env bash
# Entregas 4 y 5: publica las imágenes del commit actual y despliega con
# Terraform los tres servicios de Cloud Run, la Cloud Function de audio,
# Pub/Sub, el balanceador y el resto.
#
#   deploy/gcp/desplegar-run.sh                 # publicar + terraform apply (pide confirmación)
#   deploy/gcp/desplegar-run.sh --sin-publicar  # solo apply, con las imágenes ya publicadas
#   deploy/gcp/desplegar-run.sh -- -auto-approve
#
# El commit es la etiqueta: cada despliegue crea revisiones nuevas en Cloud
# Run que apuntan a esas imágenes, y volver atrás es desplegar otro commit
# con --sin-publicar y MOOC_TAG=<commit>.
source "$(dirname "$0")/lib.sh"
requiere git terraform
comprobar_gcloud

publicar=1
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sin-publicar) publicar=0 ;;
    --) shift; extra=("$@"); break ;;
    *) morir "opción desconocida '$1'" ;;
  esac
  shift
done

cd "$RAIZ" || exit 1
TAG="${MOOC_TAG:-$(git rev-parse --short=12 HEAD)}"
export MOOC_TAG="$TAG"

if [[ "$publicar" == 1 ]]; then
  "$RAIZ/deploy/gcp/publicar.sh"
fi

# Entrega 5: Terraform gestiona las imágenes, así que el apply con run_tag es
# el despliegue (también de la Cloud Function, que se construye del código
# que arma preparar-funcion.sh).
aviso "infraestructura (Cloud Run, Pub/Sub, Cloud Function, balanceador, IAM)"
"$RAIZ/deploy/gcp/desplegar-infra.sh" -var "run_tag=$TAG" ${extra[@]+"${extra[@]}"}
aviso "listo: $(salida url_publica)  (API: $(salida url_publica)/api/v1/health)"
