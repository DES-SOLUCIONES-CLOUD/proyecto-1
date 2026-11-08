# Entrega 4: Cloud Pub/Sub sustituye a asynq sobre Redis como transporte de
# las tareas asíncronas (transcodificación HLS y conversión a PDF).
#
#   mooc-api --publish--> topic mooc-tareas
#                           |  suscripción push mooc-tareas-push
#                           |  (token OIDC de mooc-pubsub-push, audiencia = URL del worker)
#                           v
#                         mooc-worker POST /pubsub/push
#                           204 = ack (después de persistir el resultado)
#                           5xx = nack -> reentrega con backoff (10 s a 300 s)
#                           5 entregas fallidas -> topic mooc-tareas-dlq
#
# Reentregas sin efectos duplicados: Pub/Sub entrega al menos una vez. El
# worker reclama el activo con un UPDATE condicional en Cloud SQL
# (arrendamiento) y descarta la entrega si el activo ya está listo; una
# entrega que llega mientras otra lo procesa recibe nack y vuelve más tarde.

resource "google_pubsub_topic" "tareas" {
  name = "${var.prefijo}-tareas"
  # Los mensajes se guardan un día aunque nadie los consuma: si el worker no
  # puede arrancar, las tareas esperan en lugar de perderse.
  message_retention_duration = "86400s"
}

resource "google_pubsub_topic" "dlq" {
  name                       = "${var.prefijo}-tareas-dlq"
  message_retention_duration = "604800s"
}

# Suscripción de extracción sobre la dead-letter, para inspeccionar las
# tareas agotadas (gcloud pubsub subscriptions pull ... --auto-ack) y, si
# hace falta, volver a publicarlas.
resource "google_pubsub_subscription" "dlq" {
  name                       = "${var.prefijo}-tareas-dlq-sub"
  topic                      = google_pubsub_topic.dlq.id
  ack_deadline_seconds       = 60
  message_retention_duration = "604800s"

  expiration_policy {
    ttl = ""
  }
}

resource "google_pubsub_subscription" "push" {
  name  = "${var.prefijo}-tareas-push"
  topic = google_pubsub_topic.tareas.id

  # Máximo que admite Pub/Sub, e igual al timeout del servicio de workers: la
  # respuesta de una transcodificación llega dentro de ese plazo.
  ack_deadline_seconds       = var.run_worker.timeout
  message_retention_duration = "86400s"

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.worker.uri}/pubsub/push"

    # Push autenticado: Pub/Sub firma cada entrega con un token OIDC de esta
    # cuenta, y Cloud Run lo valida (firma, audiencia y que la cuenta tenga
    # run.invoker) antes de que la petición llegue al contenedor.
    oidc_token {
      service_account_email = data.google_service_account.pubsub_push.email
      audience              = google_cloud_run_v2_service.worker.uri
    }
    # Sin no_wrapper: el worker lee messageId, atributos y deliveryAttempt del
    # sobre JSON de Pub/Sub.
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = var.pubsub_max_entregas
  }

  expiration_policy {
    ttl = ""
  }

  depends_on = [
    google_cloud_run_v2_service_iam_member.worker_invocador,
    google_pubsub_topic_iam_member.agente_dlq,
  ]
}

# --- Permisos ---------------------------------------------------------------------

# La API solo puede publicar en el topic de tareas (no leer, no administrar,
# no publicar en la dead-letter).
resource "google_pubsub_topic_iam_member" "api_publica" {
  topic  = google_pubsub_topic.tareas.id
  role   = "roles/pubsub.publisher"
  member = data.google_service_account.web.member
}

# El agente de servicio de Pub/Sub mueve los mensajes agotados a la
# dead-letter: necesita publicar en ella y suscribirse a la suscripción de
# origen (para hacer ack del mensaje que mueve).
locals {
  agente_pubsub = "serviceAccount:service-${data.google_project.actual.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_topic_iam_member" "agente_dlq" {
  topic  = google_pubsub_topic.dlq.id
  role   = "roles/pubsub.publisher"
  member = local.agente_pubsub
}

resource "google_pubsub_subscription_iam_member" "agente_origen" {
  subscription = google_pubsub_subscription.push.id
  role         = "roles/pubsub.subscriber"
  member       = local.agente_pubsub
}
