#!/usr/bin/env bash
# Entrega 4: despliega en los tres servicios de Cloud Run las imágenes de un
# commit ya publicado (publicar.sh). Cada servicio crea una revisión nueva y
# Cloud Run pasa el tráfico a ella cuando su sonda de arranque responde.
#
#   deploy/gcp/desplegar-imagenes.sh [<etiqueta>]   # por defecto, el commit actual
#
# Lo usa el push a main en CI para desplegar sin un apply. Desde la Entrega 5
# Terraform gestiona la imagen (run_tag), y desplegar-infra.sh toma como
# run_tag la etiqueta que este script dejó corriendo: el siguiente plan no ve
# diferencia ni devuelve los servicios a una imagen anterior. A mano, lo
# preferible es deploy/gcp/desplegar-run.sh (publicar + apply).
source "$(dirname "$0")/lib.sh"
comprobar_gcloud
requiere_infra

TAG="${1:-${MOOC_TAG:-$(git -C "$RAIZ" rev-parse --short=12 HEAD)}}"
REGISTRO="$(salida registro)"
PROYECTO="$(salida proyecto)"
REGION="$(salida region)"

# Los workers primero: una API nueva puede publicar tareas que solo entiende
# un worker nuevo, nunca al revés.
for par in "worker:$(salida run_worker)" "api:$(salida run_api)" "frontend:$(salida run_frontend)"; do
  imagen="${par%%:*}" servicio="${par#*:}"
  [[ -n "$servicio" ]] || morir "sin salida run_$imagen: ¿se aplicó cloudrun.tf? (deploy/gcp/desplegar-run.sh)"
  gcloud artifacts docker images describe "$REGISTRO/mooc-$imagen:$TAG" >/dev/null 2>&1 \
    || morir "no existe $REGISTRO/mooc-$imagen:$TAG: publicar primero (deploy/gcp/publicar.sh)"
  aviso "desplegando $servicio <- mooc-$imagen:$TAG"
  gcloud run services update "$servicio" --project "$PROYECTO" --region "$REGION" \
    --image "$REGISTRO/mooc-$imagen:$TAG" --quiet
done

gcloud run services list --project "$PROYECTO" --region "$REGION" \
  --format 'table(metadata.name, status.latestReadyRevisionName, status.url)'
