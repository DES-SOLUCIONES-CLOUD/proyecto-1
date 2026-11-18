# Identidades, secretos y registro de imágenes.
#
# Una cuenta de servicio por componente: la VM corre con ella, las reglas de
# firewall la usan como origen/destino y su clave HMAC es con la que la API o
# el worker firman contra Cloud Storage. Así los permisos sobre los buckets
# son distintos por componente, como pide el enunciado.

# Cuentas de servicio, una por componente (Entrega 5: las gestiona Terraform).
#
# Hasta la Entrega 4 las creaba deploy/gcp/bootstrap-ci.sh y aquí solo se
# leían. La guía de la Entrega 5 pide que Terraform gestione las cuentas, así
# que ahora son recursos. Las que ya existen en el proyecto se importan al
# estado con los bloques import de abajo (no se borran ni se recrean).
#
# Lo que no cambia es la seguridad: la cuenta de CI (mooc-deployer) no recibe
# iam.serviceAccountAdmin. Después de importarlas, un plan de CI solo las lee
# (le basta el actAs que ya tiene sobre cada una). Crearlas en un proyecto
# nuevo lo hace el primer apply del dueño del proyecto (README de la Entrega 5).
locals {
  cuentas_de_servicio = {
    web = {
      sufijo      = "web"
      nombre      = "MOOC API (mig-api)"
      descripcion = "Instancias de API y frontend: firma cargas y descargas, lee Secret Manager y Artifact Registry."
    }
    worker = {
      sufijo      = "worker"
      nombre      = "MOOC Workers (mig-workers)"
      descripcion = "Instancias de worker: leen originales, escriben derivados HLS y PDFs de presentaciones."
    }
    # VM de Redis (Entrega 3): solo registros, métricas e imágenes.
    redis = {
      sufijo      = "redis"
      nombre      = "MOOC Redis"
      descripcion = "VM fija de Redis y Mailpit: solo registros, métricas e imágenes."
    }
    # Entrega 4: frontend sin permisos e identidad OIDC de la suscripción push.
    frontend = {
      sufijo      = "frontend"
      nombre      = "MOOC frontend (Entrega 4)"
      descripcion = null
    }
    pubsub_push = {
      sufijo      = "pubsub-push"
      nombre      = "MOOC pubsub-push (Entrega 4)"
      descripcion = null
    }
    # Entrega 5: la función de audio y Cloud Build (construye la función).
    funcion_audio = {
      sufijo      = "fn-audio"
      nombre      = "MOOC Cloud Function de audio"
      descripcion = null
    }
    build = {
      sufijo      = "build"
      nombre      = "MOOC Cloud Build"
      descripcion = null
    }
  }
}

resource "google_service_account" "cuenta" {
  for_each     = local.cuentas_de_servicio
  account_id   = "${var.prefijo}-${each.value.sufijo}"
  display_name = each.value.nombre
  description  = each.value.descripcion
}

# Recursos existentes: con importar_cuentas_existentes = true (el valor por
# defecto, porque en plasma-sol-513002-k6 ya existen) el plan las importa al
# estado en lugar de crearlas. Una vez en el estado, el bloque no hace nada.
# En un proyecto nuevo se pone en false y el apply las crea.
import {
  for_each = var.importar_cuentas_existentes ? local.cuentas_de_servicio : {}
  to       = google_service_account.cuenta[each.key]
  id       = "projects/${var.project_id}/serviceAccounts/${var.prefijo}-${each.value.sufijo}@${var.project_id}.iam.gserviceaccount.com"
}

locals {
  cuentas = {
    web    = google_service_account.cuenta["web"]
    worker = google_service_account.cuenta["worker"]
    redis  = google_service_account.cuenta["redis"]
    # Entrega 5: la Cloud Function de audio.
    funcion-audio = google_service_account.cuenta["funcion_audio"]
  }
}

# Escribir registros y métricas (Ops Agent). Nada más a nivel de proyecto.
resource "google_project_iam_member" "registros" {
  for_each = local.cuentas
  project  = var.project_id
  role     = "roles/logging.logWriter"
  member   = each.value.member
}

resource "google_project_iam_member" "metricas" {
  for_each = local.cuentas
  project  = var.project_id
  role     = "roles/monitoring.metricWriter"
  member   = each.value.member
}

# --- Claves HMAC -------------------------------------------------------------
#
# La API XML de Cloud Storage acepta firmas SigV4 con claves HMAC, que es lo
# que habla minio-go sin tocar el código de firma, las URLs prefirmadas ni el
# multipart. El access_id no es secreto (identifica la clave, como un
# usuario); el secret va a Secret Manager y a ningún archivo.

resource "google_storage_hmac_key" "web" {
  service_account_email = google_service_account.cuenta["web"].email
}

resource "google_storage_hmac_key" "worker" {
  service_account_email = google_service_account.cuenta["worker"].email
}

# Entrega 5: la función firma con su propia cuenta, no con la del worker, para
# que sus permisos sobre los buckets sean solo los suyos (funcion.tf).
resource "google_storage_hmac_key" "funcion_audio" {
  service_account_email = google_service_account.cuenta["funcion_audio"].email
}

# --- Secret Manager ------------------------------------------------------------

resource "random_password" "bd" {
  length = 32
  # Sin especiales: va dentro de DATABASE_URL y un @, / o : la rompería.
  special = false
}

resource "random_password" "admin" {
  length  = 24
  special = false
}

locals {
  # Secretos con valor generado aquí y qué VM puede leer cada uno. La clave
  # de insignias va aparte (abajo).
  #
  # Los valores van en un mapa distinto porque son sensibles, y un for_each no
  # puede recorrer nada derivado de un valor sensible.
  secretos = {
    bd-password               = ["web", "worker", "funcion-audio"]
    hmac-web-secret           = ["web"]
    hmac-worker-secret        = ["worker"]
    hmac-funcion-audio-secret = ["funcion-audio"]
    admin-password            = ["web"]
  }
  valores_secretos = {
    bd-password               = random_password.bd.result
    hmac-web-secret           = google_storage_hmac_key.web.secret
    hmac-worker-secret        = google_storage_hmac_key.worker.secret
    hmac-funcion-audio-secret = google_storage_hmac_key.funcion_audio.secret
    admin-password            = random_password.admin.result
  }
  lectores_de_secretos = merge(
    [for nombre, lectores in local.secretos : { for l in lectores : "${nombre}/${l}" => { secreto = nombre, lector = l } }]...
  )
}

resource "google_secret_manager_secret" "s" {
  for_each  = local.secretos
  secret_id = "${var.prefijo}-${each.key}"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "s" {
  for_each    = local.secretos
  secret      = google_secret_manager_secret.s[each.key].id
  secret_data = local.valores_secretos[each.key]
}

# Cada VM lee solo sus secretos: el Worker no puede leer la clave HMAC de la
# API ni la contraseña del administrador.
resource "google_secret_manager_secret_iam_member" "lector" {
  for_each  = local.lectores_de_secretos
  secret_id = google_secret_manager_secret.s[each.value.secreto].id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.cuentas[each.value.lector].member
}

# La clave de firma de insignias vive fuera de Terraform (la crean
# bootstrap-ci.sh o desplegar-infra.sh), para que sobreviva a un destroy: con
# otra clave, las credenciales Open Badges ya emitidas dejarían de
# verificarse. Aquí solo se da acceso a la API. El ID se compone en lugar de
# leerse con un data source para que el plan no dependa de que ya exista: en
# CI el plan no crea nada, y la clave se asegura justo antes del apply.
locals {
  secreto_badge = "${var.prefijo}-badge-signing-key"
}

resource "google_secret_manager_secret_iam_member" "badge_web" {
  secret_id = "projects/${var.project_id}/secrets/${local.secreto_badge}"
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.cuenta["web"].member
}

# --- Artifact Registry ---------------------------------------------------------
#
# Las imágenes se construyen fuera de las e2-small (publicar.sh) y las VM
# solo hacen pull con su cuenta de servicio. El Worker llega por Private
# Google Access, sin NAT.

resource "google_artifact_registry_repository" "imagenes" {
  location      = var.region
  repository_id = var.prefijo
  format        = "DOCKER"
  description   = "Imágenes de la plataforma MOOC (api, migrate, worker, frontend y réplica de redis)."

  # Cada publicación deja ~1 GB (el worker lleva LibreOffice y FFmpeg). Se
  # conservan las 5 más recientes por imagen y el resto se borra a las dos
  # semanas: por encima de 0,5 GB el registro se cobra por GB-mes.
  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "conservar-recientes"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }
  # La etiqueta que arrancan las instancias de los MIG (desplegar-vm.sh la
  # mueve): borrar esa versión dejaría sin imagen al próximo scale-out.
  cleanup_policies {
    id     = "conservar-desplegada"
    action = "KEEP"
    condition {
      tag_state    = "TAGGED"
      tag_prefixes = [var.imagen_tag]
    }
  }
  cleanup_policies {
    id     = "borrar-antiguas"
    action = "DELETE"
    condition {
      older_than = "1209600s"
    }
  }
}

resource "google_artifact_registry_repository_iam_member" "lector" {
  # La imagen de la función la baja el agente de servicio de Cloud Run, no
  # su cuenta: no necesita leer el repositorio.
  for_each   = { for k, v in local.cuentas : k => v if k != "funcion-audio" }
  location   = google_artifact_registry_repository.imagenes.location
  repository = google_artifact_registry_repository.imagenes.name
  role       = "roles/artifactregistry.reader"
  member     = each.value.member
}
