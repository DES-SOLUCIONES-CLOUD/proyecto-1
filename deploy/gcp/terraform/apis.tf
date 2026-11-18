# Entrega 5: APIs del proyecto y rol de proyecto de Cloud Build, gestionados por
# Terraform (antes los habilitaba o concedía solo un script).
#
# deploy/gcp/desplegar-infra.sh sigue habilitando las que falten ANTES del
# primer plan, porque Terraform necesita algunas encendidas para poder leer el
# proyecto. Con estos recursos quedan además en el estado: un apply las
# habilita si alguien las apaga, y destruir la infraestructura no las apaga
# (disable_on_destroy = false), porque otras cosas del proyecto las usan.
locals {
  apis = toset([
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "iap.googleapis.com",
    "oslogin.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "billingbudgets.googleapis.com",
    # Entrega 4
    "run.googleapis.com",
    "pubsub.googleapis.com",
    # Entrega 5: la función se construye con Cloud Build y la activa Eventarc.
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
  ])
}

resource "google_project_service" "api" {
  for_each                   = local.apis
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Cloud Build construye la Cloud Function con la cuenta mooc-build (funcion.tf).
# Necesita este rol de proyecto; antes lo concedía bootstrap-ci.sh.
resource "google_project_iam_member" "build_constructor" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = google_service_account.cuenta["build"].member
}
