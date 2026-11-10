#!/usr/bin/env bash
# Publica las imágenes con Cloud Build y una cuenta propia (mooc-build) con lo
# justo: escribir en el repositorio de Artifact Registry, leer el código
# subido y escribir los registros del build.
#
#   deploy/gcp/publicar-cloudbuild.sh      # etiqueta = commit actual
source "$(dirname "$0")/lib.sh"
comprobar_gcloud
requiere_infra
cd "$RAIZ" || exit 1
P="$(salida proyecto)"; R="$(salida region)"
TAG="${MOOC_TAG:-$(git rev-parse --short=12 HEAD)}"
SA="mooc-build@$P.iam.gserviceaccount.com"
FUENTES="gs://${P}_cloudbuild"

gcloud services enable cloudbuild.googleapis.com --project "$P"
if ! gcloud iam service-accounts describe "$SA" --project "$P" >/dev/null 2>&1; then
  gcloud iam service-accounts create mooc-build --project "$P" --display-name "MOOC Cloud Build"
  sleep 10
fi
gcloud storage buckets describe "$FUENTES" >/dev/null 2>&1 \
  || gcloud storage buckets create "$FUENTES" --project "$P" --location "$R" --uniform-bucket-level-access
gcloud storage buckets add-iam-policy-binding "$FUENTES" --member "serviceAccount:$SA" --role roles/storage.objectViewer >/dev/null
gcloud artifacts repositories add-iam-policy-binding mooc --location "$R" --project "$P" \
  --member "serviceAccount:$SA" --role roles/artifactregistry.writer >/dev/null
gcloud projects add-iam-policy-binding "$P" --member "serviceAccount:$SA" \
  --role roles/logging.logWriter --condition None >/dev/null

aviso "Cloud Build: $(salida registro)/mooc-*:$TAG (frontend para $(salida url_publica))"
gcloud builds submit --project "$P" --region "$R" --config deploy/gcp/cloudbuild.yaml \
  --service-account "projects/$P/serviceAccounts/$SA" --gcs-source-staging-dir "$FUENTES/fuentes" \
  --substitutions "_REGISTRO=$(salida registro),_TAG=$TAG,_API_URL=$(salida url_publica)" .
