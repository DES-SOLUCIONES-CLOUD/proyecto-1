# Infraestructura de la Entrega 3 en GCP: un balanceador de aplicaciones
# externo delante de un grupo administrado (MIG) de API, otro MIG de workers,
# una VM fija con Redis (la cola), Cloud SQL for PostgreSQL por IP privada,
# Cloud Storage por su API XML compatible con S3 y Artifact Registry.
#
# Este archivo tiene lo común y la red; el resto está repartido por tema:
# computo.tf (VM de Redis, y plantillas, MIGs y autoscalers), balanceador.tf,
# basedatos.tf, almacenamiento.tf, identidades.tf, costos.tf.

data "google_project" "actual" {}

locals {
  host_web    = var.dominio_web != "" ? var.dominio_web : "${google_compute_global_address.lb.address}.sslip.io"
  url_publica = "https://${local.host_web}"

  # Nombres de bucket sin puntos: minio-go firma en estilo virtual-host
  # (<bucket>.storage.googleapis.com) y el certificado comodín de Google no
  # cubre un nombre con puntos.
  bucket_objetos   = "${var.project_id}-${var.prefijo}-objetos"
  bucket_hls       = "${var.project_id}-${var.prefijo}-hls"
  bucket_respaldos = "${var.project_id}-${var.prefijo}-respaldos"

  registro = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.imagenes.repository_id}"

  rango_psa = "${var.psa_direccion}/${var.psa_prefijo}"
}

# --- VPC ---------------------------------------------------------------------
#
# Modo custom: la red default trae subredes en todas las regiones y reglas
# que abren SSH, RDP e ICMP a Internet. Aquí solo existe lo que se declara.

resource "google_compute_network" "vpc" {
  name                    = "${var.prefijo}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Tres subredes, una por capa. Ninguna VM tiene IP externa: lo único público
# es la IP del balanceador, que vive en los Google Front Ends y no en la VPC.
# Separarlas permite escribir el firewall por capa y leer en los registros de
# flujo de dónde viene cada conexión. Las tres tienen Private Google Access:
# Cloud Storage, Artifact Registry, Secret Manager y Logging/Monitoring se
# alcanzan sin NAT y sin salir a Internet.

resource "google_compute_subnetwork" "api" {
  name                     = "${var.prefijo}-api"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.cidr_api
  private_ip_google_access = true
}

# Capa de datos privada: la VM de Redis (cola asynq, sesiones, caché, límites)
# y el SMTP de pruebas. Fuera de los MIG a propósito: un scale-down nunca
# borra la VM que tiene la cola.
resource "google_compute_subnetwork" "datos" {
  name                     = "${var.prefijo}-datos"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.cidr_datos
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "workers" {
  name                     = "${var.prefijo}-workers"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.cidr_workers
  private_ip_google_access = true
}

# La ruta por defecto a Internet (0.0.0.0/0 -> default-internet-gateway) que
# crea GCP se conserva a propósito: la usan Cloud NAT y también Private
# Google Access, que con el dominio por defecto (storage.googleapis.com, el
# único que minio-go reconoce como GCS) sale por esa ruta aunque el tráfico
# no deje la red de Google.

# --- Cloud NAT -----------------------------------------------------------------
#
# Salida a Internet para lo que no es de Google: el repositorio de Docker y
# el del Ops Agent en el primer arranque de cada VM, los paquetes de Debian y
# las imágenes de Redis y Mailpit de Docker Hub. Con los MIG ya no es solo el
# primer despliegue: cada instancia que crea el autoscaler instala Docker al
# nacer, así que sin NAT el scale-out falla. Solo salida: nada entra por aquí.

resource "google_compute_router" "router" {
  count   = var.habilitar_nat ? 1 : 0
  name    = "${var.prefijo}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  count                              = var.habilitar_nat ? 1 : 0
  name                               = "${var.prefijo}-nat"
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# --- Direcciones ---------------------------------------------------------------

# IP pública fija del balanceador (balanceador.tf). Global, no regional: el
# balanceador de aplicaciones externo atiende desde los Google Front Ends. El
# nombre sslip.io, el certificado, el CORS de los buckets y
# NEXT_PUBLIC_API_URL dependen de ella.
resource "google_compute_global_address" "lb" {
  name         = "${var.prefijo}-lb-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

# IP interna fija de Redis: REDIS_ADDR de la API y de los workers está en sus
# plantillas, y cambiarla obligaría a reemplazar todas las instancias.
resource "google_compute_address" "redis_interna" {
  name         = "${var.prefijo}-redis-ip"
  region       = var.region
  address_type = "INTERNAL"
  subnetwork   = google_compute_subnetwork.datos.id
  address      = var.ip_redis
}

# --- Firewall ----------------------------------------------------------------
#
# Por cuenta de servicio y no por etiqueta: cambiar las etiquetas de una VM
# solo exige compute.instances.setTags, mientras que cambiar su cuenta de
# servicio exige detenerla y el permiso iam.serviceAccountUser sobre la
# nueva. La regla sigue a la identidad de la máquina, no a una etiqueta.
#
# Todo lo que no está aquí queda cerrado por la regla implícita de denegar la
# entrada. La salida está abierta salvo hacia Cloud SQL (abajo). La regla que
# deja entrar al balanceador y a los health checks está en computo.tf, junto
# al MIG de API.

resource "google_compute_firewall" "redis" {
  name                    = "${var.prefijo}-permitir-redis"
  network                 = google_compute_network.vpc.id
  direction               = "INGRESS"
  priority                = 1000
  source_service_accounts = [data.google_service_account.web.email, data.google_service_account.worker.email]
  target_service_accounts = [data.google_service_account.redis.email]

  # Redis no tiene contraseña (la API y el worker no la soportan): lo
  # protegen esta regla, que la VM no tiene IP externa y que el contenedor
  # solo escucha en la IP interna.
  allow {
    protocol = "tcp"
    ports    = ["6379"]
  }
}

# SMTP de pruebas (Mailpit) en la VM de Redis: solo la API envía correo.
resource "google_compute_firewall" "smtp" {
  name                    = "${var.prefijo}-permitir-smtp-desde-api"
  network                 = google_compute_network.vpc.id
  direction               = "INGRESS"
  priority                = 1000
  source_service_accounts = [data.google_service_account.web.email]
  target_service_accounts = [data.google_service_account.redis.email]

  allow {
    protocol = "tcp"
    ports    = ["1025"]
  }
}

resource "google_compute_firewall" "ssh_iap" {
  name      = "${var.prefijo}-permitir-ssh-iap"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000
  # Rango fijo de IAP TCP forwarding. La administración es
  # `gcloud compute ssh --tunnel-through-iap`: el puerto 22 no está abierto a
  # Internet y quién entra lo decide IAM (roles/iap.tunnelResourceAccessor y
  # OS Login), no una llave repartida.
  source_ranges = ["35.235.240.0/20"]
  target_service_accounts = [
    data.google_service_account.web.email,
    data.google_service_account.worker.email,
    data.google_service_account.redis.email,
  ]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Cloud SQL vive en la red del productor (peering de servicenetworking) y los
# firewalls de esta VPC no filtran su entrada. Lo que sí se controla es la
# salida desde aquí: solo las cuentas de servicio de la API y de los workers
# llegan al rango de Private Service Access, y solo al 5432. La VM de Redis y
# cualquier otra que se cree en la VPC quedan fuera.
resource "google_compute_firewall" "sql_permitir" {
  name                    = "${var.prefijo}-permitir-egress-sql"
  network                 = google_compute_network.vpc.id
  direction               = "EGRESS"
  priority                = 900
  destination_ranges      = [local.rango_psa]
  target_service_accounts = [data.google_service_account.web.email, data.google_service_account.worker.email]

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
}

resource "google_compute_firewall" "sql_denegar" {
  name               = "${var.prefijo}-denegar-egress-sql"
  network            = google_compute_network.vpc.id
  direction          = "EGRESS"
  priority           = 1000
  destination_ranges = [local.rango_psa]

  deny {
    protocol = "all"
  }
}
