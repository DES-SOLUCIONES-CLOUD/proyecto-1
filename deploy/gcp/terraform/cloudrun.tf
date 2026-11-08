# Entrega 4: frontend, backend (API) y workers como tres servicios de Cloud
# Run, con imágenes de Artifact Registry.
#
#   Internet -> balanceador (balanceador.tf, mismo dominio y certificado)
#                 /api/*  -> NEG serverless -> mooc-api      (público)
#                 resto   -> NEG serverless -> mooc-frontend (público)
#   mooc-api --publica--> Pub/Sub (pubsub.tf) --push OIDC--> mooc-worker (privado)
#
# Las tres revisiones tienen un máximo de 3 instancias y un contenedor por
# instancia. El mínimo es 0: sin tráfico no se paga cómputo (el primer
# usuario tras un rato de inactividad espera el arranque en frío).
#
# Ninguna réplica guarda estado en su disco: el sistema de archivos de Cloud
# Run es memoria y desaparece con la instancia. Lo persistente está en Cloud
# SQL (datos y estado de las tareas), Cloud Storage (originales, HLS y PDF) y
# Redis (idempotencia de peticiones y límites de tasa). El worker solo usa
# /tmp como espacio de trabajo de FFmpeg y LibreOffice mientras dura una tarea.
#
# Red: la API y el worker salen a la VPC con Direct VPC egress (sin conector)
# para llegar a Cloud SQL por IP privada y a Redis por su IP interna. Solo el
# tráfico a rangos privados entra a la VPC (PRIVATE_RANGES_ONLY); Cloud
# Storage y Pub/Sub se alcanzan por sus endpoints públicos de Google.

locals {
  imagen = { for n in ["api", "worker", "frontend"] : n => "${local.registro}/mooc-${n}:${var.run_tag}" }

  # Etiquetas de red de las salidas a la VPC: el firewall (main.tf) deja pasar
  # al 5432 de Cloud SQL solo a estas, y al 6379/1025 de Redis solo desde las
  # subredes de la API y de los workers.
  tag_run_api    = "${var.prefijo}-run-api"
  tag_run_worker = "${var.prefijo}-run-worker"

  # Variables comunes a la API y al worker. Sin secretos: los secretos van
  # aparte, como referencias a Secret Manager que Cloud Run resuelve al
  # arrancar cada instancia con la cuenta de servicio del servicio.
  env_backend = {
    APP_ENV          = "production"
    DB_HOST          = local.bd_host
    DB_USER          = "mooc"
    DB_NAME          = "mooc"
    DB_SSLMODE       = "require"
    REDIS_ADDR       = local.redis_addr
    S3_ENDPOINT      = "storage.googleapis.com"
    S3_REGION        = "auto"
    S3_BUCKET        = google_storage_bucket.objetos.name
    S3_BUCKET_HLS    = google_storage_bucket.hls.name
    S3_USE_SSL       = "true"
    S3_CREATE_BUCKET = "false"
    QUEUE_BACKEND    = "pubsub"
  }

  env_api = merge(local.env_backend, {
    DB_MAX_CONNS               = tostring(var.api_db_max_conns)
    S3_ACCESS_KEY              = google_storage_hmac_key.web.access_id
    S3_PUBLIC_ENDPOINT         = "storage.googleapis.com"
    S3_PUBLIC_USE_SSL          = "true"
    PUBLIC_BASE_URL            = local.url_publica
    COOKIE_SECURE              = "true"
    SMTP_HOST                  = var.ip_redis
    SMTP_PORT                  = "1025"
    SMTP_FROM                  = "no-reply@mooc.local"
    TRUSTED_PROXY_HOPS         = "2"
    BADGE_KEY_ID               = "mooc-badges-1"
    ISSUER_NAME                = "Plataforma MOOC"
    GOOGLE_CLOUD_PROJECT       = var.project_id
    PUBSUB_TOPIC               = google_pubsub_topic.tareas.name
    ADMIN_EMAIL                = var.admin_email
    AUTH_RATE_LIMIT_PER_MINUTE = var.auth_rate_limit_per_minute
  })

  env_worker = merge(local.env_backend, {
    DB_MAX_CONNS        = tostring(var.worker_db_max_conns)
    S3_ACCESS_KEY       = google_storage_hmac_key.worker.access_id
    PUBSUB_MAX_ENTREGAS = tostring(var.pubsub_max_entregas)
  })

  secretos_api = merge({
    DB_PASSWORD       = google_secret_manager_secret.s["bd-password"].secret_id
    S3_SECRET_KEY     = google_secret_manager_secret.s["hmac-web-secret"].secret_id
    BADGE_SIGNING_KEY = local.secreto_badge
    },
    # La contraseña del administrador solo viaja mientras admin_email esté
    # definido (crea el administrador en el primer arranque).
    var.admin_email != "" ? { ADMIN_PASSWORD = google_secret_manager_secret.s["admin-password"].secret_id } : {}
  )

  secretos_worker = {
    DB_PASSWORD   = google_secret_manager_secret.s["bd-password"].secret_id
    S3_SECRET_KEY = google_secret_manager_secret.s["hmac-worker-secret"].secret_id
  }
}

# --- Backend (API) -----------------------------------------------------------------

resource "google_cloud_run_v2_service" "api" {
  name                = "${var.prefijo}-api"
  location            = var.region
  description         = "API REST /api/v1: autentica, firma cargas y publica tareas en Pub/Sub."
  deletion_protection = false
  # Pública: la API tiene su propia autenticación (sesión + CSRF). El tráfico
  # normal entra por el balanceador, que le da el mismo origen que el
  # frontend (las cookies SameSite=Lax lo necesitan).
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account                  = data.google_service_account.web.email
    timeout                          = "${var.run_api.timeout}s"
    max_instance_request_concurrency = var.run_api.concurrencia
    execution_environment            = "EXECUTION_ENVIRONMENT_GEN2"

    scaling {
      min_instance_count = var.run_api.min
      max_instance_count = var.run_api.max
    }

    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = google_compute_network.vpc.id
        subnetwork = google_compute_subnetwork.api.id
        tags       = [local.tag_run_api]
      }
    }

    containers {
      name  = "api"
      image = local.imagen["api"]

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.run_api.cpu
          memory = var.run_api.memoria
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      dynamic "env" {
        for_each = { for k, v in local.env_api : k => v if v != "" }
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.secretos_api
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }

      # La API migra la base al arrancar: se le da hasta dos minutos.
      startup_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds    = 5
        timeout_seconds   = 3
        failure_threshold = 24
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.lector,
    google_secret_manager_secret_iam_member.badge_web,
  ]

  # La imagen la cambia desplegar-imagenes.sh (y el push a main en CI) sin
  # pasar por Terraform; run_tag solo fija la de la creación.
  lifecycle {
    ignore_changes = [template[0].containers[0].image, client, client_version]
  }
}

resource "google_cloud_run_v2_service_iam_member" "api_publica" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- Frontend --------------------------------------------------------------------

resource "google_cloud_run_v2_service" "frontend" {
  name                = "${var.prefijo}-frontend"
  location            = var.region
  description         = "Frontend Next.js (standalone)."
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    # Cuenta propia y sin ningún permiso: el frontend no toca la base, los
    # buckets ni los secretos. Cloud Run baja la imagen con su agente de
    # servicio, no con esta cuenta.
    service_account                  = data.google_service_account.frontend.email
    timeout                          = "${var.run_frontend.timeout}s"
    max_instance_request_concurrency = var.run_frontend.concurrencia

    scaling {
      min_instance_count = var.run_frontend.min
      max_instance_count = var.run_frontend.max
    }

    containers {
      name  = "frontend"
      image = local.imagen["frontend"]

      ports {
        container_port = 3000
      }

      resources {
        limits = {
          cpu    = var.run_frontend.cpu
          memory = var.run_frontend.memoria
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }
    }
  }

  # La imagen la cambia desplegar-imagenes.sh (y el push a main en CI) sin
  # pasar por Terraform; run_tag solo fija la de la creación.
  lifecycle {
    ignore_changes = [template[0].containers[0].image, client, client_version]
  }
}

resource "google_cloud_run_v2_service_iam_member" "frontend_publico" {
  name     = google_cloud_run_v2_service.frontend.name
  location = google_cloud_run_v2_service.frontend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- Workers -----------------------------------------------------------------------

resource "google_cloud_run_v2_service" "worker" {
  name                = "${var.prefijo}-worker"
  location            = var.region
  description         = "Workers: reciben las tareas de Pub/Sub (push) y transcodifican o convierten."
  deletion_protection = false
  # Solo tráfico interno: Pub/Sub del mismo proyecto cuenta como interno, y
  # además (abajo) solo la cuenta de la suscripción puede invocarlo. Desde
  # Internet la URL responde 404 aunque se tenga un token.
  ingress = var.worker_ingress

  template {
    service_account = data.google_service_account.worker.email
    # Igual al ack deadline de la suscripción (600 s): si la tarea pasa de ahí,
    # Pub/Sub da la entrega por perdida y Cloud Run corta la petición a la vez.
    timeout = "${var.run_worker.timeout}s"
    # Una tarea por instancia: cada una es un FFmpeg o un LibreOffice que
    # ocupa la CPU entera. Con mensajes pendientes, Cloud Run escala a más
    # instancias (hasta el máximo) en lugar de apilar trabajos en una.
    max_instance_request_concurrency = var.run_worker.concurrencia
    execution_environment            = "EXECUTION_ENVIRONMENT_GEN2"

    scaling {
      min_instance_count = var.run_worker.min
      max_instance_count = var.run_worker.max
    }

    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = google_compute_network.vpc.id
        subnetwork = google_compute_subnetwork.workers.id
        tags       = [local.tag_run_worker]
      }
    }

    containers {
      name  = "worker"
      image = local.imagen["worker"]

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.run_worker.cpu
          memory = var.run_worker.memoria
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      dynamic "env" {
        for_each = local.env_worker
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.secretos_worker
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds    = 5
        timeout_seconds   = 3
        failure_threshold = 12
      }
    }
  }

  depends_on = [google_secret_manager_secret_iam_member.lector]

  # La imagen la cambia desplegar-imagenes.sh (y el push a main en CI) sin
  # pasar por Terraform; run_tag solo fija la de la creación.
  lifecycle {
    ignore_changes = [template[0].containers[0].image, client, client_version]
  }
}

# Solo la identidad de la suscripción push invoca a los workers. Ni allUsers,
# ni la API, ni ninguna otra cuenta.
resource "google_cloud_run_v2_service_iam_member" "worker_invocador" {
  name     = google_cloud_run_v2_service.worker.name
  location = google_cloud_run_v2_service.worker.location
  role     = "roles/run.invoker"
  member   = data.google_service_account.pubsub_push.member
}
