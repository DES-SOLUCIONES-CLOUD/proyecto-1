# Balanceador de aplicaciones externo global (EXTERNAL_MANAGED). En la
# Entrega 4 entrega a Cloud Run mediante NEG serverless en lugar de a un MIG:
#
#   Internet -> IP global :443 (TLS) -> mapa de URL
#                 /api/*  -> backend service -> NEG serverless -> mooc-api
#                 resto   -> backend service -> NEG serverless -> mooc-frontend
#               IP global :80 -> redirección a https
#
# Se conserva para que la API y el frontend sigan bajo el MISMO origen
# (https://<IP>.sslip.io): las cookies de sesión (Secure, SameSite=Lax) y el
# token CSRF funcionan igual que antes. Con dos URLs *.run.app serían dos
# sitios distintos (run.app está en la Public Suffix List) y el navegador no
# enviaría la cookie de sesión en las llamadas a la API.
#
# Sin health checks: con NEG serverless la disponibilidad la gestiona Cloud
# Run (sondas de arranque de cada servicio).

resource "google_compute_region_network_endpoint_group" "api" {
  name                  = "${var.prefijo}-neg-api"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = google_cloud_run_v2_service.api.name
  }
}

resource "google_compute_region_network_endpoint_group" "frontend" {
  name                  = "${var.prefijo}-neg-frontend"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = google_cloud_run_v2_service.frontend.name
  }
}

# --- Backend services ----------------------------------------------------------
#
# Nombres nuevos (bs-run-*) para que Terraform cree estos, mueva el mapa de URL
# y después borre los de la Entrega 3, sin dejar el balanceador sin destino.
# Con NEG serverless no se fija timeout_sec ni puerto: el tiempo máximo es el
# del servicio de Cloud Run.

resource "google_compute_backend_service" "api" {
  name                  = "${var.prefijo}-bs-run-api"
  description           = "API REST /api/v1 en Cloud Run."
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"

  lifecycle {
    create_before_destroy = true
  }

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }

  log_config {
    enable      = true
    sample_rate = var.lb_muestreo_logs
  }
}

resource "google_compute_backend_service" "frontend" {
  name                  = "${var.prefijo}-bs-run-frontend"
  description           = "Frontend Next.js en Cloud Run."
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"

  lifecycle {
    create_before_destroy = true
  }

  backend {
    group = google_compute_region_network_endpoint_group.frontend.id
  }
}

# --- Mapa de URL -----------------------------------------------------------------

resource "google_compute_url_map" "https" {
  name            = "${var.prefijo}-lb"
  description     = "/api/* a la API, el resto al frontend (Cloud Run)."
  default_service = google_compute_backend_service.frontend.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "rutas"
  }

  path_matcher {
    name            = "rutas"
    default_service = google_compute_backend_service.frontend.id

    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.api.id
    }
  }
}

# Puerto 80: solo redirige a https. Las cookies de sesión son Secure y no
# viajarían por http.
resource "google_compute_url_map" "redireccion" {
  name        = "${var.prefijo}-lb-redireccion"
  description = "http -> https"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# --- TLS ----------------------------------------------------------------------------
#
# Certificado administrado por Google para el nombre público (por defecto
# <IP del balanceador>.sslip.io). Google lo emite cuando el nombre resuelve a
# la IP del balanceador: entre 15 y 60 minutos después del primer apply. El
# sufijo cambia con el nombre para poder crear el nuevo antes de borrar el
# viejo (un proxy no puede quedarse sin certificado).

resource "google_compute_managed_ssl_certificate" "web" {
  name = "${var.prefijo}-cert-${substr(md5(local.host_web), 0, 8)}"

  managed {
    domains = [local.host_web]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Política TLS: 1.2 como mínimo, como pide el enunciado (sección 7).
resource "google_compute_ssl_policy" "tls12" {
  name            = "${var.prefijo}-tls12"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

# --- Proxies y reglas de reenvío ---------------------------------------------------

resource "google_compute_target_https_proxy" "web" {
  name             = "${var.prefijo}-proxy-https"
  url_map          = google_compute_url_map.https.id
  ssl_certificates = [google_compute_managed_ssl_certificate.web.id]
  ssl_policy       = google_compute_ssl_policy.tls12.id
}

resource "google_compute_target_http_proxy" "redireccion" {
  name    = "${var.prefijo}-proxy-http"
  url_map = google_compute_url_map.redireccion.id
}

resource "google_compute_global_forwarding_rule" "https" {
  name                  = "${var.prefijo}-regla-https"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.id
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.web.id
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.prefijo}-regla-http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.id
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.redireccion.id
}
