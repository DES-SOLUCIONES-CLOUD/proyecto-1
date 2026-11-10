#!/usr/bin/env bash
# Entrega 4: publica las imágenes del commit actual y despliega los tres
# servicios de Cloud Run (y Pub/Sub, el balanceador y el resto) con Terraform.
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

# run_tag solo cuenta al CREAR los servicios; después Terraform ignora la
# imagen y la cambia desplegar-imagenes.sh.
aviso "infraestructura (Cloud Run, Pub/Sub, balanceador, IAM)"
"$RAIZ/deploy/gcp/desplegar-infra.sh" -var "run_tag=$TAG" ${extra[@]+"${extra[@]}"}
"$RAIZ/deploy/gcp/desplegar-imagenes.sh" "$TAG"
aviso "listo: $(salida url_publica)  (API: $(salida url_publica)/api/v1/health)"
