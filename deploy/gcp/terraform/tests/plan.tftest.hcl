mock_provider "google" {
  mock_data "google_project" { defaults = { number = "123456789" } }
  mock_data "google_service_account" { defaults = { email = "sa@p.iam.gserviceaccount.com", member = "serviceAccount:sa@p.iam.gserviceaccount.com" } }
  mock_resource "google_compute_network" { defaults = { id = "projects/mi-proyecto/global/networks/mooc-vpc" } }
  mock_resource "google_compute_subnetwork" { defaults = { id = "projects/mi-proyecto/regions/us-central1/subnetworks/s" } }
  mock_resource "google_compute_address" { defaults = { address = "10.0.1.5" } }
  mock_resource "google_compute_global_address" { defaults = { address = "203.0.113.10", id = "projects/mi-proyecto/global/addresses/mooc-lb-ip" } }
  mock_resource "google_compute_instance_group_manager" { defaults = { id = "projects/mi-proyecto/zones/us-central1-a/instanceGroupManagers/mig", instance_group = "projects/mi-proyecto/zones/us-central1-a/instanceGroups/mig" } }
  mock_resource "google_compute_instance_template" { defaults = { self_link_unique = "projects/mi-proyecto/global/instanceTemplates/t?uniqueId=1" } }
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
    condition = alltrue([for m in [google_compute_instance.redis.metadata, google_compute_instance_template.api.metadata, google_compute_instance_template.worker.metadata] :
    alltrue([for v in values(m) : !strcontains(v, "\r")])])
    error_message = "metadatos con CRLF"
  }

  # Ninguna plantilla tiene IP externa.
  assert {
    condition     = length(google_compute_instance_template.api.network_interface[0].access_config) == 0 && length(google_compute_instance_template.worker.network_interface[0].access_config) == 0
    error_message = "plantillas sin ip externa"
  }
  # La plantilla de API lleva DATABASE_URL (sus partes) y REDIS_ADDR.
  assert {
    condition     = strcontains(google_compute_instance_template.api.metadata["mooc-env"], "REDIS_ADDR=10.0.1.5:6379") && strcontains(google_compute_instance_template.api.metadata["mooc-env"], "DB_HOST=10.30.0.3") && google_compute_instance_template.api.metadata["mooc-rol"] == "api"
    error_message = "env de la api"
  }
  assert {
    condition     = strcontains(google_compute_instance_template.worker.metadata["mooc-env"], "REDIS_ADDR=10.0.1.5:6379") && strcontains(google_compute_instance_template.worker.metadata["mooc-env"], "WORKER_CONCURRENCY=2")
    error_message = "env del worker"
  }
  # Autoscalers: 1 a 3, CPU 60 %, cooldown 120 s.
  assert {
    condition = alltrue([for a in [google_compute_autoscaler.api, google_compute_autoscaler.workers] :
      a.autoscaling_policy[0].min_replicas == 1 && a.autoscaling_policy[0].max_replicas == 3 &&
    a.autoscaling_policy[0].cpu_utilization[0].target == 0.6 && a.autoscaling_policy[0].cooldown_period == 120])
    error_message = "autoscalers"
  }
  assert {
    condition     = google_compute_instance_group_manager.api.name == "mig-api" && google_compute_instance_group_manager.workers.name == "mig-workers"
    error_message = "nombres de los MIG"
  }
  # Health check del balanceador: /healthz en el 8080, 5 s, 3 s, 2 fallos.
  assert {
    condition = (google_compute_health_check.api.http_health_check[0].request_path == "/healthz" &&
      google_compute_health_check.api.http_health_check[0].port == 8080 &&
      google_compute_health_check.api.check_interval_sec == 5 &&
      google_compute_health_check.api.timeout_sec == 3 &&
    google_compute_health_check.api.unhealthy_threshold == 2)
    error_message = "health check"
  }
  assert {
    condition     = google_compute_backend_service.api.port_name == "http-api" && google_compute_backend_service.frontend.port_name == "http-web"
    error_message = "puertos con nombre"
  }
  assert {
    condition     = google_compute_global_forwarding_rule.https.port_range == "443" && google_compute_global_forwarding_rule.http.port_range == "80"
    error_message = "reglas de reenvío"
  }
  assert {
    condition     = google_compute_managed_ssl_certificate.web.managed[0].domains[0] == "203.0.113.10.sslip.io" && google_compute_ssl_policy.tls12.min_tls_version == "TLS_1_2"
    error_message = "certificado y TLS"
  }
  # Solo los rangos de los health checks y del balanceador llegan a la API.
  assert {
    condition     = toset(google_compute_firewall.health_checks.source_ranges) == toset(["130.211.0.0/22", "35.191.0.0/16"])
    error_message = "firewall de health checks"
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
