mock_provider "google" {
  mock_data "google_project" { defaults = { number = "123456789" } }
  mock_data "google_service_account" { defaults = { email = "sa@p.iam.gserviceaccount.com", member = "serviceAccount:sa@p.iam.gserviceaccount.com" } }
  mock_resource "google_compute_network" { defaults = { id = "projects/mi-proyecto/global/networks/mooc-vpc" } }
  mock_resource "google_compute_subnetwork" { defaults = { id = "projects/mi-proyecto/regions/us-central1/subnetworks/s" } }
  mock_resource "google_compute_address" { defaults = { address = "10.0.1.5" } }
  mock_resource "google_compute_global_address" { defaults = { address = "203.0.113.10", id = "projects/mi-proyecto/global/addresses/mooc-lb-ip" } }
  mock_resource "google_cloud_run_v2_service" { defaults = { uri = "https://mooc-worker-abc-uc.a.run.app" } }
  mock_resource "google_pubsub_topic" { defaults = { id = "projects/mi-proyecto/topics/t" } }
  mock_resource "google_pubsub_subscription" { defaults = { id = "projects/mi-proyecto/subscriptions/s" } }
  mock_resource "google_sql_database_instance" { defaults = { service_account_email_address = "p123@gcp-sa-cloud-sql.iam.gserviceaccount.com", private_ip_address = "10.30.0.3" } }
}
mock_provider "random" {}

variables {
  project_id = "mi-proyecto"
}

run "completo" {
  command = apply
  assert {
    condition     = output.url_publica == "https://203.0.113.10.sslip.io" && output.ip_lb == "203.0.113.10"
    error_message = "url_publica: ${output.url_publica}"
  }
  assert {
    condition     = output.bucket_hls == "mi-proyecto-mooc-hls"
    error_message = "bucket_hls"
  }
  assert {
    condition     = length(google_secret_manager_secret_iam_member.lector) == 5
    error_message = "lectores de secretos: ${length(google_secret_manager_secret_iam_member.lector)}"
  }
  assert {
    condition     = length(google_compute_router_nat.nat) == 1 && length(google_sql_database_instance.bd) == 1
    error_message = "nat/bd"
  }
  assert {
    condition     = google_sql_database_instance.bd[0].settings[0].edition == "ENTERPRISE" && google_sql_database_instance.bd[0].settings[0].ip_configuration[0].ipv4_enabled == false
    error_message = "bd"
  }
  assert {
    condition     = contains(google_storage_bucket.objetos.cors[0].response_header, "ETag") && contains(google_storage_bucket.objetos.cors[0].origin, "https://203.0.113.10.sslip.io")
    error_message = "cors"
  }
  # La clave de insignias no se lee con un data source: el plan de CI no
  # debe depender de que ya exista.
  assert {
    condition     = google_secret_manager_secret_iam_member.badge_web.secret_id == "projects/mi-proyecto/secrets/mooc-badge-signing-key" && output.secreto_badge == "mooc-badge-signing-key"
    error_message = "secreto de insignias"
  }
  # Las cuentas de las VM las crea bootstrap-ci.sh; aquí solo se leen.
  assert {
    condition     = google_compute_instance.redis.service_account[0].email == data.google_service_account.redis.email
    error_message = "cuenta de servicio de Redis"
  }

  # Redis: VM fija e2-small, IP 10.0.1.5 en la subred de datos, sin IP externa.
  assert {
    condition     = google_compute_address.redis_interna.address == "10.0.1.5" && google_compute_subnetwork.datos.ip_cidr_range == "10.0.1.0/24"
    error_message = "ip de redis"
  }
  assert {
    condition     = length(google_compute_instance.redis.network_interface[0].access_config) == 0 && google_compute_instance.redis.machine_type == "e2-small"
    error_message = "redis sin ip externa"
  }
  assert {
    condition     = google_compute_instance.redis.metadata["mooc-rol"] == "redis" && strcontains(google_compute_instance.redis.metadata["mooc-env"], "REDIS_BIND_IP=10.0.1.5")
    error_message = "metadatos de redis"
  }
  # Ningún archivo de los metadatos lleva finales CRLF.
  assert {
    condition     = alltrue([for v in values(google_compute_instance.redis.metadata) : !strcontains(v, "\r")])
    error_message = "metadatos con CRLF"
  }

  # Entrega 4: tres servicios de Cloud Run con máximo 3 instancias.
  assert {
    condition = alltrue([for s in [google_cloud_run_v2_service.api, google_cloud_run_v2_service.frontend, google_cloud_run_v2_service.worker] :
    s.template[0].scaling[0].max_instance_count == 3])
    error_message = "máximo de instancias"
  }
  # Workers: una tarea por instancia, solo tráfico interno y solo la cuenta de
  # la suscripción los invoca.
  assert {
    condition = (google_cloud_run_v2_service.worker.template[0].max_instance_request_concurrency == 1 &&
      google_cloud_run_v2_service.worker.ingress == "INGRESS_TRAFFIC_INTERNAL_ONLY" &&
    google_cloud_run_v2_service_iam_member.worker_invocador.member == data.google_service_account.pubsub_push.member)
    error_message = "workers protegidos"
  }
  # Suscripción push autenticada, con dead-letter y ack deadline = timeout.
  assert {
    condition = (google_pubsub_subscription.push.push_config[0].oidc_token[0].service_account_email == data.google_service_account.pubsub_push.email &&
      google_pubsub_subscription.push.push_config[0].push_endpoint == "https://mooc-worker-abc-uc.a.run.app/pubsub/push" &&
      google_pubsub_subscription.push.dead_letter_policy[0].max_delivery_attempts == 10 &&
    google_pubsub_subscription.push.ack_deadline_seconds == 600)
    error_message = "suscripción push"
  }
  # Ningún secreto va como valor en claro en las variables de los servicios.
  assert {
    condition = alltrue([for e in google_cloud_run_v2_service.api.template[0].containers[0].env :
    !contains(["DB_PASSWORD", "S3_SECRET_KEY", "BADGE_SIGNING_KEY", "ADMIN_PASSWORD"], e.name) || e.value == null || e.value == ""])
    error_message = "secretos en claro"
  }
  # La API llega a Redis y a Cloud SQL por la VPC.
  assert {
    condition     = contains([for e in google_cloud_run_v2_service.api.template[0].containers[0].env : "${e.name}=${coalesce(e.value, "-")}"], "REDIS_ADDR=10.0.1.5:6379") && contains([for e in google_cloud_run_v2_service.api.template[0].containers[0].env : "${e.name}=${coalesce(e.value, "-")}"], "DB_HOST=10.30.0.3")
    error_message = "env de la api"
  }
  assert {
    condition     = google_compute_global_forwarding_rule.https.port_range == "443" && google_compute_global_forwarding_rule.http.port_range == "80"
    error_message = "reglas de reenvío"
  }
  assert {
    condition     = google_compute_managed_ssl_certificate.web.managed[0].domains[0] == "203.0.113.10.sslip.io" && google_compute_ssl_policy.tls12.min_tls_version == "TLS_1_2"
    error_message = "certificado y TLS"
  }
}

run "sin_bd_ni_nat_con_presupuesto" {
  command = apply
  variables {
    crear_bd           = false
    habilitar_nat      = false
    cuenta_facturacion = "000000-000000-000000"
    dominio_web        = "mooc.ejemplo.co"
  }
  assert {
    condition     = output.bd_instancia == "" && length(google_compute_router_nat.nat) == 0 && length(google_storage_bucket_iam_member.sql_respaldos) == 0
    error_message = "toggles"
  }
  assert {
    condition     = output.url_publica == "https://mooc.ejemplo.co" && length(google_billing_budget.mensual) == 1
    error_message = "dominio/presupuesto"
  }
  assert {
    condition     = google_billing_budget.mensual[0].budget_filter[0].credit_types_treatment == "EXCLUDE_ALL_CREDITS"
    error_message = "créditos"
  }
}
