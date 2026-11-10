# Cómputo en VM que sigue en la Entrega 4: solo la VM fija de Redis
# (<prefijo>-redis), sin IP externa e IP interna estática, con Redis
# (sesiones de idempotencia, límites de tasa y panel de actividad) y Mailpit.
#
# La API, el frontend y los workers ya no corren en MIG: son servicios de
# Cloud Run (cloudrun.tf) y los trabajos asíncronos van por Pub/Sub
# (pubsub.tf). Las plantillas, MIG y autoscalers de la Entrega 3 están en el
# historial de git.
#
# La VM no se configura entrando a ella: el script de arranque lee de sus
# metadatos su rol, su .env, su docker-compose.yml y en-vm.sh.
#
# Todo archivo que va a los metadatos pasa por replace(..., "\r\n", "\n"):
# con core.autocrlf (Windows) git los deja con CRLF y bash no ejecuta un
# script así.

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

  env_redis = <<-EOT
    PROYECTO_GCP=${var.project_id}
    REDIS_BIND_IP=${var.ip_redis}
  EOT
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
