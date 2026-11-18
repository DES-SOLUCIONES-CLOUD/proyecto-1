# Entrega 5: la transcodificación de audio sale del worker y la ejecuta una
# Cloud Function de 2ª generación (Cloud Run functions) activada por Pub/Sub.
#
#   mooc-api --publica--> topic mooc-audio --Eventarc (RETRY)--> función mooc-audio
#                                                                  |-> GCS hls/<recurso>/ (bucket hls)
#                                                                  '-> Cloud SQL (activo y recurso 'ready')
#
# El código es backend/funciones/audio: llama al mismo
# media.Processor.HandleProcessMedia que el worker, así que el resultado (los
# archivos HLS y los estados en la base) es idéntico. Video y presentaciones
# siguen en mooc-tareas -> mooc-worker (pubsub.tf, cloudrun.tf).
#
# Reintentos sin duplicados: Eventarc reentrega mientras la función devuelva
# error (retry_policy = RETRY_POLICY_RETRY, backoff exponencial). El activo se
# reclama con un UPDATE condicional en Cloud SQL, así que una entrega repetida
# de un audio ya listo se descarta y una simultánea se aplaza. Los errores
# permanentes (original sin pista de audio) se confirman sin reintento, y
# pasado var.funcion_audio.plazo_reintentos la función deja de pedir más
# entregas (queda registrado como queue.task_dead_letter).
#
# Código: deploy/gcp/preparar-funcion.sh arma var.zip_funcion (módulo del
# backend + FFmpeg estático, zip determinista); aquí se sube con su MD5 en el
# nombre (un cambio de código crea un objeto nuevo y redespliega) y la
# función se construye con Cloud Build a partir de él. No se usa archive_file:
# en CI el apply corre el plan guardado en otra máquina, donde ese data source
# no se vuelve a leer y el zip no existiría.

# --- Topic ---------------------------------------------------------------------------

resource "google_pubsub_topic" "audio" {
  name = "${var.prefijo}-audio"
  # Un día, como mooc-tareas: si la función no puede arrancar, los audios
  # esperan en el topic en lugar de perderse.
  message_retention_duration = "86400s"
}

# La API solo publica en él (no lo lee ni lo administra).
resource "google_pubsub_topic_iam_member" "api_publica_audio" {
  topic  = google_pubsub_topic.audio.id
  role   = "roles/pubsub.publisher"
  member = data.google_service_account.web.member
}

# --- Código desplegable -------------------------------------------------------------

# Bucket del código fuente de las funciones. Privado; solo lo lee Cloud Build
# (cuenta mooc-build) al construir la función.
resource "google_storage_bucket" "codigo" {
  name                        = "${var.project_id}-${var.prefijo}-funciones"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  soft_delete_policy {
    retention_duration_seconds = 0
  }

  # Cada despliegue con código nuevo deja un zip de ~60 MB; los viejos no
  # se vuelven a usar.
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

locals {
  zip_funcion = startswith(var.zip_funcion, "/") ? var.zip_funcion : "${path.module}/${var.zip_funcion}"
}

resource "google_storage_bucket_object" "funcion_audio" {
  name   = "audio/${filemd5(local.zip_funcion)}.zip"
  bucket = google_storage_bucket.codigo.name
  source = local.zip_funcion
}

resource "google_storage_bucket_iam_member" "build_codigo" {
  bucket = google_storage_bucket.codigo.name
  role   = "roles/storage.objectViewer"
  member = data.google_service_account.build.member
}

# --- Función ---------------------------------------------------------------------------

resource "google_cloudfunctions2_function" "audio" {
  name        = "${var.prefijo}-audio"
  location    = var.region
  description = "Transcodifica pistas de audio a HLS (tarea migrada del worker, Entrega 5)."

  build_config {
    runtime     = var.funcion_audio.runtime
    entry_point = "TranscodificarAudio"
    # Cloud Build corre con mooc-build (lee el zip, escribe la imagen en el
    # repositorio mooc y sus registros), no con la cuenta por defecto de
    # Compute, a la que bootstrap-ci.sh le quitó Editor.
    service_account   = data.google_service_account.build.id
    docker_repository = google_artifact_registry_repository.imagenes.id

    source {
      storage_source {
        bucket = google_storage_bucket.codigo.name
        object = google_storage_bucket_object.funcion_audio.name
      }
    }
  }

  service_config {
    service_account_email = data.google_service_account.funcion_audio.email
    available_memory      = var.funcion_audio.memoria
    available_cpu         = var.funcion_audio.cpu
    timeout_seconds       = var.funcion_audio.timeout
    min_instance_count    = 0
    max_instance_count    = var.funcion_audio.max
    # Un audio por instancia: es un FFmpeg que ocupa la CPU entera, y /tmp
    # (en memoria) guarda el original y los segmentos.
    max_instance_request_concurrency = 1
    # Solo la invoca Eventarc desde dentro del proyecto.
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true

    # Direct VPC egress, igual que el worker: Cloud SQL por IP privada. Solo
    # los rangos privados entran a la VPC; Storage va por su endpoint público.
    direct_vpc_egress = "VPC_EGRESS_PRIVATE_RANGES_ONLY"
    direct_vpc_network_interface {
      network    = google_compute_network.vpc.id
      subnetwork = google_compute_subnetwork.workers.id
      tags       = [local.tag_funcion_audio]
    }

    environment_variables = local.env_funcion_audio

    dynamic "secret_environment_variables" {
      for_each = local.secretos_funcion_audio
      content {
        key        = secret_environment_variables.key
        project_id = var.project_id
        secret     = secret_environment_variables.value
        version    = "latest"
      }
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.audio.id
    retry_policy   = "RETRY_POLICY_RETRY"
    # La misma identidad que firma las entregas push al worker: solo puede
    # invocar a los consumidores de las tareas.
    service_account_email = data.google_service_account.pubsub_push.email
  }

  depends_on = [
    google_secret_manager_secret_iam_member.lector,
    google_storage_bucket_iam_member.build_codigo,
    google_artifact_registry_repository_iam_member.build_escribe,
    google_project_iam_member.build_registros,
  ]
}

# Eventarc invoca el servicio de Cloud Run que hay debajo de la función con la
# cuenta del disparador.
resource "google_cloud_run_service_iam_member" "funcion_audio_invocador" {
  location = google_cloudfunctions2_function.audio.location
  service  = google_cloudfunctions2_function.audio.service_config[0].service
  role     = "roles/run.invoker"
  member   = data.google_service_account.pubsub_push.member
}

locals {
  tag_funcion_audio = "${var.prefijo}-fn-audio"

  # Lo mismo que el worker necesita para transcodificar, con la clave HMAC de
  # la función. Sin Redis: el panel de actividad es del worker.
  env_funcion_audio = {
    APP_ENV          = "production"
    DB_HOST          = local.bd_host
    DB_USER          = "mooc"
    DB_NAME          = "mooc"
    DB_SSLMODE       = "require"
    DB_MAX_CONNS     = "2"
    S3_ENDPOINT      = "storage.googleapis.com"
    S3_REGION        = "auto"
    S3_BUCKET        = google_storage_bucket.objetos.name
    S3_BUCKET_HLS    = google_storage_bucket.hls.name
    S3_USE_SSL       = "true"
    S3_CREATE_BUCKET = "false"
    S3_ACCESS_KEY    = google_storage_hmac_key.funcion_audio.access_id
    PLAZO_REINTENTOS = var.funcion_audio.plazo_reintentos
  }

  secretos_funcion_audio = {
    DB_PASSWORD   = google_secret_manager_secret.s["bd-password"].secret_id
    S3_SECRET_KEY = google_secret_manager_secret.s["hmac-funcion-audio-secret"].secret_id
  }
}

# --- Permisos de la función sobre Storage ------------------------------------------
#
# Lee los originales y escribe solo los derivados HLS. Nada de presentaciones/,
# badges/ ni del bucket de respaldos.

resource "google_storage_bucket_iam_member" "funcion_audio_objetos_lectura" {
  bucket = google_storage_bucket.objetos.name
  role   = "roles/storage.objectViewer"
  member = data.google_service_account.funcion_audio.member

  condition {
    title       = "solo-originales"
    description = "La función de audio solo lee los originales subidos."
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.objetos.name}/objects/resources/\")"
  }
}

# objectUser y no objectCreator: un reintento reescribe las mismas claves
# hls/<recurso>/..., y sobrescribir exige storage.objects.delete.
resource "google_storage_bucket_iam_member" "funcion_audio_hls" {
  bucket = google_storage_bucket.hls.name
  role   = "roles/storage.objectUser"
  member = data.google_service_account.funcion_audio.member
}

# --- Cloud Build de la función -----------------------------------------------------

resource "google_artifact_registry_repository_iam_member" "build_escribe" {
  location   = google_artifact_registry_repository.imagenes.location
  repository = google_artifact_registry_repository.imagenes.name
  role       = "roles/artifactregistry.writer"
  member     = data.google_service_account.build.member
}

resource "google_project_iam_member" "build_registros" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = data.google_service_account.build.member
}
