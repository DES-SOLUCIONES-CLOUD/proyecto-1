# Cómputo de la Entrega 3:
#
# - mig-api: plantilla e2-small con la API (8080) y el frontend (3000), detrás
#   del balanceador. Autoescala por CPU.
# - mig-workers: plantilla e2-small con el worker asynq (FFmpeg, LibreOffice).
#   Autoescala por CPU.
# - <prefijo>-redis: VM fija, sin IP externa, IP interna estática. Redis con
#   la cola y Mailpit.
#
# Ninguna VM se configura entrando a ella: el script de arranque lee de sus
# metadatos su rol, su .env (sin secretos, solo los nombres en Secret
# Manager), su docker-compose.yml y en-vm.sh, y levanta los contenedores
# solo. Todo lo que define una VM está en Terraform.
#
# Todo archivo que va a los metadatos pasa por replace(..., "\r\n", "\n"):
# con core.autocrlf (Windows) git los deja con CRLF, bash no ejecuta un
# script así, y además un apply desde Windows y otro desde CI producirían
# metadatos distintos y reemplazarían las instancias sin motivo.

locals {
  arranque = replace(templatefile("${path.module}/arranque.sh.tftpl", {
    registro_host      = "${var.region}-docker.pkg.dev"
    instalar_ops_agent = var.instalar_ops_agent
  }), "\r\n", "\n")

  # Archivos que viajan en los metadatos. Un metadato admite 256 KB; estos
  # suman unos 20.
  dir_deploy = "${path.module}/../.."

  metadatos_comunes = {
    # Acceso SSH por identidad de Google (roles/compute.osAdminLogin) y no por
    # llaves en los metadatos del proyecto, que valdrían para cualquier VM.
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    startup-script         = local.arranque
    mooc-en-vm             = replace(file("${local.dir_deploy}/gcp/en-vm.sh"), "\r\n", "\n")
    mooc-env-lib           = replace(file("${local.dir_deploy}/gcp/env.sh"), "\r\n", "\n")
  }

  redis_addr = "${var.ip_redis}:6379"
  bd_host    = var.crear_bd ? google_sql_database_instance.bd[0].private_ip_address : ""

  # .env de cada rol: el común más el propio. Mismo formato que lee
  # `docker compose --env-file` y env.sh. Sin secretos: solo los nombres de
  # los secretos, que en-vm.sh lee en la VM con la cuenta de servicio de la
  # instancia.
  env_comun = <<-EOT
    PROYECTO_GCP=${var.project_id}
    REGISTRO=${local.registro}
    MOOC_TAG=${var.imagen_tag}
    DB_HOST=${local.bd_host}
    DB_USER=mooc
    DB_NAME=mooc
    SECRETO_DB_PASSWORD=${google_secret_manager_secret.s["bd-password"].secret_id}
    REDIS_ADDR=${local.redis_addr}
    S3_BUCKET=${google_storage_bucket.objetos.name}
    S3_BUCKET_HLS=${google_storage_bucket.hls.name}
  EOT

  env_api = <<-EOT
    S3_ACCESS_KEY=${google_storage_hmac_key.web.access_id}
    SECRETO_S3_SECRET_KEY=${google_secret_manager_secret.s["hmac-web-secret"].secret_id}
    DB_MAX_CONNS=${var.api_db_max_conns}
    PUBLIC_BASE_URL=${local.url_publica}
    SMTP_HOST=${var.ip_redis}
    SMTP_FROM=no-reply@mooc.local
    AUTH_RATE_LIMIT_PER_MINUTE=${var.auth_rate_limit_per_minute}
    BADGE_KEY_ID=mooc-badges-1
    ISSUER_NAME=Plataforma MOOC
    SECRETO_BADGE_SIGNING_KEY=${local.secreto_badge}
    ADMIN_EMAIL=${var.admin_email}
    SECRETO_ADMIN_PASSWORD=${google_secret_manager_secret.s["admin-password"].secret_id}
    COMPOSE_PROFILES=frontend
  EOT

  env_worker = <<-EOT
    S3_ACCESS_KEY=${google_storage_hmac_key.worker.access_id}
    SECRETO_S3_SECRET_KEY=${google_secret_manager_secret.s["hmac-worker-secret"].secret_id}
    DB_MAX_CONNS=${var.worker_db_max_conns}
    WORKER_CONCURRENCY=${var.worker_concurrency}
  EOT

  env_redis = <<-EOT
    PROYECTO_GCP=${var.project_id}
    REDIS_BIND_IP=${var.ip_redis}
  EOT
}

# --- Plantillas ----------------------------------------------------------------
#
# Una plantilla es inmutable: cualquier cambio (otra imagen de VM, otro .env,
# otro compose) crea una nueva con otro nombre (name_prefix) y el MIG la
# despliega con un reemplazo gradual (update_policy). create_before_destroy
# porque el MIG no suelta la vieja hasta tener la nueva.

resource "google_compute_instance_template" "api" {
  name_prefix  = "${var.prefijo}-api-"
  description  = "API y frontend de la plataforma MOOC (Entrega 3)."
  machine_type = var.tipo_maquina

  disk {
    source_image = var.imagen_vm
    disk_size_gb = var.disco_gb
    disk_type    = "pd-balanced"
    auto_delete  = true
    boot         = true
  }

  # Sin access_config: sin IP externa. El tráfico entra por el balanceador y
  # sale a Google por Private Google Access y a lo demás por Cloud NAT.
  network_interface {
    subnetwork = google_compute_subnetwork.api.id
  }

  service_account {
    email = data.google_service_account.web.email
    # cloud-platform porque Secret Manager no tiene un alcance propio: los
    # alcances son un mecanismo heredado y Google recomienda este con los
    # permisos acotados por IAM. Lo que la VM puede hacer es lo que tiene
    # su cuenta de servicio (identidades.tf, almacenamiento.tf), nada más.
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = merge(local.metadatos_comunes, {
    mooc-rol     = "api"
    mooc-env     = "${local.env_comun}${local.env_api}"
    mooc-compose = replace(file("${local.dir_deploy}/api/docker-compose.yml"), "\r\n", "\n")
  })

  labels = {
    rol = "api"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_template" "worker" {
  name_prefix  = "${var.prefijo}-worker-"
  description  = "Worker asynq de la plataforma MOOC con FFmpeg y LibreOffice (Entrega 3)."
  machine_type = var.tipo_maquina

  disk {
    source_image = var.imagen_vm
    disk_size_gb = var.disco_gb
    disk_type    = "pd-balanced"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.workers.id
  }

  service_account {
    email  = data.google_service_account.worker.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = merge(local.metadatos_comunes, {
    mooc-rol     = "worker"
    mooc-env     = "${local.env_comun}${local.env_worker}"
    mooc-compose = replace(file("${local.dir_deploy}/worker/docker-compose.yml"), "\r\n", "\n")
  })

  labels = {
    rol = "worker"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Autohealing -----------------------------------------------------------------
#
# Distinto del health check del balanceador (balanceador.tf), y más
# tolerante a propósito: el del balanceador solo saca la instancia de la
# rotación, este la BORRA y la recrea. Con los umbrales del balanceador
# (2 fallos de 3 s) una API saturada en plena prueba de carga se recrearía,
# que es justo lo contrario de escalar. Aquí hace falta un minuto entero sin
# responder.
resource "google_compute_health_check" "autohealing_api" {
  name                = "${var.prefijo}-autohealing-api"
  check_interval_sec  = 15
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 4

  http_health_check {
    port         = 8080
    request_path = "/healthz"
  }
}

# El autohealing consulta desde los mismos rangos que los health checks del
# balanceador; el balanceador además entrega el tráfico desde ahí. Solo a la
# API (8080) y al frontend (3000): nada más de las instancias queda expuesto.
resource "google_compute_firewall" "health_checks" {
  name                    = "${var.prefijo}-permitir-hc-y-lb-a-api"
  network                 = google_compute_network.vpc.id
  direction               = "INGRESS"
  priority                = 1000
  source_ranges           = ["130.211.0.0/22", "35.191.0.0/16"]
  target_service_accounts = [data.google_service_account.web.email]

  allow {
    protocol = "tcp"
    ports    = ["8080", "3000"]
  }
}

# --- MIG de API --------------------------------------------------------------------

resource "google_compute_instance_group_manager" "api" {
  name               = "mig-api"
  description        = "API y frontend detrás del balanceador externo."
  zone               = var.zona
  base_instance_name = "${var.prefijo}-api"

  version {
    instance_template = google_compute_instance_template.api.self_link_unique
  }

  # Puertos con nombre: los backend services del balanceador los usan para
  # saber a qué puerto de cada instancia entregar.
  named_port {
    name = "http-api"
    port = 8080
  }
  named_port {
    name = "http-web"
    port = 3000
  }

  auto_healing_policies {
    health_check = google_compute_health_check.autohealing_api.id
    # Una instancia nueva instala Docker y baja las imágenes antes de que la
    # API responda: unos 3-4 minutos en una e2-small.
    initial_delay_sec = var.mig_retraso_inicial
  }

  # Al cambiar la plantilla: una instancia nueva de más mientras se reemplaza
  # cada vieja (surge 1), y nunca menos de las que había (unavailable 0).
  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 1
    max_unavailable_fixed = 0
    replacement_method    = "SUBSTITUTE"
  }

  # Sin target_size: el número de instancias lo decide el autoscaler.

  # Las instancias instalan Docker desde Internet al nacer.
  depends_on = [google_compute_router_nat.nat]
}

resource "google_compute_autoscaler" "api" {
  name   = "${var.prefijo}-autoscaler-api"
  zone   = var.zona
  target = google_compute_instance_group_manager.api.id

  autoscaling_policy {
    min_replicas = var.mig_api_min
    max_replicas = var.mig_api_max
    # Periodo de inicialización ("cooldown" en la API): el autoscaler ignora
    # la CPU de una instancia durante sus primeros N segundos, mientras
    # arranca, para no decidir con el pico del arranque.
    cooldown_period = var.mig_cooldown
    mode            = "ON"

    cpu_utilization {
      target = var.mig_cpu_objetivo
    }
  }
}

# --- MIG de workers ------------------------------------------------------------------
#
# Sin autohealing: el worker no expone HTTP. Si el contenedor cae, Docker lo
# reinicia (restart: unless-stopped) y asynq reentrega la tarea.

resource "google_compute_instance_group_manager" "workers" {
  name               = "mig-workers"
  description        = "Workers asynq: transcodificación HLS y conversión de presentaciones."
  zone               = var.zona
  base_instance_name = "${var.prefijo}-worker"

  version {
    instance_template = google_compute_instance_template.worker.self_link_unique
  }

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 1
    max_unavailable_fixed = 0
    replacement_method    = "SUBSTITUTE"
  }

  depends_on = [google_compute_router_nat.nat]
}

resource "google_compute_autoscaler" "workers" {
  name   = "${var.prefijo}-autoscaler-workers"
  zone   = var.zona
  target = google_compute_instance_group_manager.workers.id

  autoscaling_policy {
    min_replicas    = var.mig_workers_min
    max_replicas    = var.mig_workers_max
    cooldown_period = var.mig_cooldown
    mode            = "ON"

    # FFmpeg satura la CPU mientras transcodifica: con la cola llena, la CPU
    # de los workers es la señal de que hacen falta más.
    cpu_utilization {
      target = var.mig_cpu_objetivo
    }
  }
}

# --- VM de Redis -----------------------------------------------------------------

resource "google_compute_instance" "redis" {
  name         = "${var.prefijo}-redis"
  machine_type = var.tipo_maquina_redis
  zone         = var.zona

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = var.imagen_vm
      size  = var.disco_gb
      type  = "pd-balanced"
    }
  }

  # Sin access_config: sin IP externa. IP interna fija, la de REDIS_ADDR.
  network_interface {
    subnetwork = google_compute_subnetwork.datos.id
    network_ip = google_compute_address.redis_interna.address
  }

  service_account {
    email = data.google_service_account.redis.email
    # cloud-platform porque los alcances son un mecanismo heredado y Google
    # recomienda este con los permisos acotados por IAM. Lo que la VM puede
    # hacer es lo que tiene su cuenta de servicio (identidades.tf).
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = merge(local.metadatos_comunes, {
    mooc-rol     = "redis"
    mooc-env     = local.env_redis
    mooc-compose = replace(file("${local.dir_deploy}/redis/docker-compose.yml"), "\r\n", "\n")
  })

  labels = {
    rol = "redis"
  }

  # El arranque instala Docker desde Internet: sin NAT fallaría la primera
  # vez y la marca de arranque no se escribiría.
  depends_on = [google_compute_router_nat.nat]
}
