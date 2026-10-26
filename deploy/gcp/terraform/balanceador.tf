# Balanceador de aplicaciones externo global (EXTERNAL_MANAGED) delante del
# MIG de API. Sustituye al Nginx con IP pública de la Entrega 2.
#
#   Internet -> IP global :443 (TLS) -> mapa de URL
#                 /api/*  -> backend service API      -> mig-api :8080
#                 resto   -> backend service frontend -> mig-api :3000
#               IP global :80 -> redirección a https
#
# API y frontend van en las mismas instancias y bajo el mismo origen, como en
# la Entrega 2: sin CORS entre ellos, y las cookies de sesión (Secure,
# SameSite) y el token CSRF siguen funcionando igual. La IP global está en
# main.tf y la regla de firewall que deja entrar al balanceador, en
# computo.tf.

# --- Health checks -------------------------------------------------------------
#
# El del balanceador decide a qué instancias se envía tráfico: estricto, para
# sacar rápido de la rotación una instancia que no responde. No la borra (eso
# es el autohealing, computo.tf).

resource "google_compute_health_check" "api" {
  name                = "${var.prefijo}-hc-api"
  description         = "GET /healthz en el 8080 de cada instancia de mig-api."
  check_interval_sec  = 5
  timeout_sec         = 3
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port         = 8080
    request_path = "/healthz"
  }

  log_config {
    enable = true
  }
}

resource "google_compute_health_check" "frontend" {
  name                = "${var.prefijo}-hc-frontend"
  description         = "GET / en el 3000 de cada instancia de mig-api (Next.js)."
  check_interval_sec  = 5
  timeout_sec         = 3
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port         = 3000
    request_path = "/"
  }
}

# --- Backend services ----------------------------------------------------------

resource "google_compute_backend_service" "api" {
  name                  = "${var.prefijo}-bs-api"
  description           = "API REST /api/v1 en mig-api."
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"
  port_name             = "http-api"
  # Tiempo máximo de una respuesta. Las dos rutas que verifican una carga
  # (checksum, MIME y antivirus sobre el archivo entero) tienen 600 s en el
  # mapa de URL, como tenían en el Nginx de la Entrega 2.
  timeout_sec   = 60
  health_checks = [google_compute_health_check.api.id]
  # Al sacar una instancia (scale-in, reemplazo), las peticiones en curso
  # tienen este margen para terminar. La API además atiende SIGTERM con un
  # cierre ordenado.
  connection_draining_timeout_sec = 30

  backend {
    group           = google_compute_instance_group_manager.api.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }

  log_config {
    enable      = true
    sample_rate = var.lb_muestreo_logs
  }
}

resource "google_compute_backend_service" "frontend" {
  name                            = "${var.prefijo}-bs-frontend"
  description                     = "Frontend Next.js en mig-api."
  load_balancing_scheme           = "EXTERNAL_MANAGED"
  protocol                        = "HTTP"
  port_name                       = "http-web"
  timeout_sec                     = 30
  health_checks                   = [google_compute_health_check.frontend.id]
  connection_draining_timeout_sec = 30

  backend {
    group           = google_compute_instance_group_manager.api.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }
}

# --- Mapa de URL -----------------------------------------------------------------

resource "google_compute_url_map" "https" {
  name            = "${var.prefijo}-lb"
  description     = "/api/* a la API, el resto al frontend."
  default_service = google_compute_backend_service.frontend.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "rutas"
  }

  path_matcher {
    name            = "rutas"
    default_service = google_compute_backend_service.frontend.id

    # Confirmar una carga verifica el archivo entero en el servidor y puede
    # tardar minutos con un video grande.
    route_rules {
      priority = 1
      service  = google_compute_backend_service.api.id
      match_rules {
        regex_match = "^/api/v1/courses/versions/[^/]+/resources/[^/]+/(confirm-upload|multipart/complete)$"
      }
      route_action {
        timeout {
          seconds = 600
        }
      }
    }

    route_rules {
      priority = 2
      service  = google_compute_backend_service.api.id
      match_rules {
        prefix_match = "/api/"
      }
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
