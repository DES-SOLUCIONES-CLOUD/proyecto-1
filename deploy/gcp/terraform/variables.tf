variable "project_id" {
  description = "ID del proyecto de GCP (no el nombre ni el número)."
  type        = string
}

variable "region" {
  description = "Región de todo el despliegue. us-central1 es de las más baratas y tiene todos los servicios usados."
  type        = string
  default     = "us-central1"
}

variable "zona" {
  description = "Zona de las VM y de Cloud SQL. La misma para todo: el tráfico entre zonas se cobra y añade latencia."
  type        = string
  default     = "us-central1-a"
}

variable "prefijo" {
  description = "Prefijo de nombres de recursos. Solo minúsculas, dígitos y guiones (va en nombres de buckets)."
  type        = string
  default     = "mooc"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}$", var.prefijo))
    error_message = "prefijo: 2-15 caracteres, minúsculas, dígitos o guiones, empezando por letra."
  }
}

# --- Cómputo -----------------------------------------------------------------

variable "tipo_maquina" {
  description = "Tipo de las instancias de los MIG. e2-small = 2 vCPU compartidas (0,5 vCPU sostenida con ráfaga) y 2 GB, dentro del límite de referencia (2 vCPU / 2 GiB / 30 GiB)."
  type        = string
  default     = "e2-small"
}

variable "tipo_maquina_redis" {
  description = "Tipo de la VM fija de Redis."
  type        = string
  default     = "e2-small"
}

variable "disco_gb" {
  description = "Disco de arranque de cada VM (pd-balanced)."
  type        = number
  default     = 30
}

variable "imagen_vm" {
  description = "Imagen de las VM. Debian 12: trae google-cloud-cli y admite Docker Engine con el plugin compose desde el repositorio de Docker."
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "instalar_ops_agent" {
  description = "Instala el Ops Agent en las VM. Sin él Cloud Monitoring no ve memoria ni disco, que el análisis de capacidad exige."
  type        = bool
  default     = true
}

variable "imagen_tag" {
  description = "Etiqueta de las imágenes de Artifact Registry que arrancan las instancias. desplegar-vm.sh mueve 'desplegada' al commit que se despliega y reemplaza las instancias; Terraform no necesita conocer el commit."
  type        = string
  default     = "desplegada"
}

# --- Autoescalado ----------------------------------------------------------------

variable "mig_api_min" {
  description = "Instancias mínimas de mig-api."
  type        = number
  default     = 1
}

variable "mig_api_max" {
  description = "Instancias máximas de mig-api."
  type        = number
  default     = 3
}

variable "mig_workers_min" {
  description = "Instancias mínimas de mig-workers."
  type        = number
  default     = 1
}

variable "mig_workers_max" {
  description = "Instancias máximas de mig-workers."
  type        = number
  default     = 3
}

variable "mig_cpu_objetivo" {
  description = "Utilización de CPU media que el autoscaler intenta mantener en cada MIG (0-1)."
  type        = number
  default     = 0.6

  validation {
    condition     = var.mig_cpu_objetivo > 0 && var.mig_cpu_objetivo < 1
    error_message = "mig_cpu_objetivo va entre 0 y 1 (0.6 = 60 %)."
  }
}

variable "mig_cooldown" {
  description = "Segundos que el autoscaler ignora la CPU de una instancia recién creada (cooldown_period / periodo de inicialización)."
  type        = number
  default     = 120
}

variable "mig_retraso_inicial" {
  description = "Segundos antes de que el autohealing empiece a juzgar una instancia nueva de mig-api: lo que tarda en instalar Docker y bajar las imágenes."
  type        = number
  default     = 300
}

# --- Parámetros de la aplicación -----------------------------------------------------

variable "worker_concurrency" {
  description = "Trabajos simultáneos por instancia de worker. 2 en una e2-small: dos FFmpeg ya rondan los 2 GB."
  type        = number
  default     = 2
}

variable "api_db_max_conns" {
  description = "Pool de conexiones a Cloud SQL por instancia de API. Con el máximo de instancias de los dos MIG: 3 x API + 3 x worker tiene que caber en max_connections (100 en db-custom-1-3840)."
  type        = number
  default     = 20
}

variable "worker_db_max_conns" {
  description = "Pool de conexiones a Cloud SQL por instancia de worker."
  type        = number
  default     = 5
}

variable "auth_rate_limit_per_minute" {
  description = "Intentos de autenticación por IP y minuto. Vacío = 10, el valor de producción. Subirlo solo para una corrida de carga concreta, y registrarlo en el informe."
  type        = string
  default     = ""
}

variable "admin_email" {
  description = "Correo del administrador inicial: se crea en el primer arranque si no existe ninguno, con la contraseña del secreto <prefijo>-admin-password. Vaciarlo después."
  type        = string
  default     = ""
}

variable "lb_muestreo_logs" {
  description = "Fracción de peticiones a la API que el balanceador registra en Cloud Logging (0-1). Las métricas del balanceador no dependen de esto."
  type        = number
  default     = 0.1
}

# --- Red ---------------------------------------------------------------------

variable "cidr_api" {
  description = "Subred de las instancias de mig-api."
  type        = string
  default     = "10.0.0.0/24"
}

variable "cidr_datos" {
  description = "Subred privada de la VM de Redis."
  type        = string
  default     = "10.0.1.0/24"
}

variable "cidr_workers" {
  description = "Subred de las instancias de mig-workers."
  type        = string
  default     = "10.0.2.0/24"
}

variable "ip_redis" {
  description = "IP interna fija de la VM de Redis, dentro de cidr_datos. Fija porque REDIS_ADDR va en las plantillas."
  type        = string
  default     = "10.0.1.5"
}

variable "psa_direccion" {
  description = "Inicio del rango reservado para Private Service Access (Cloud SQL). Explícito para poder escribir las reglas de egress contra él."
  type        = string
  default     = "10.30.0.0"
}

variable "psa_prefijo" {
  description = "Longitud del rango de Private Service Access. /20 es lo que recomienda Google para Cloud SQL."
  type        = number
  default     = 20
}

variable "habilitar_nat" {
  description = "Cloud NAT para la salida de las VM. Cada instancia nueva de un MIG instala Docker desde Internet al arrancar: sin NAT el scale-out falla."
  type        = bool
  default     = true
}

variable "dominio_web" {
  description = "Nombre público para el certificado del balanceador. Vacío: <IP del balanceador>.sslip.io."
  type        = string
  default     = ""
}

# --- Cloud SQL ---------------------------------------------------------------

variable "crear_bd" {
  description = "Crea la instancia de Cloud SQL. false la elimina (antes: deploy/gcp/bd.sh exportar)."
  type        = bool
  default     = true
}

variable "bd_tier" {
  description = "Tier de Cloud SQL. db-custom-1-3840: 1 vCPU dedicada, 3,75 GB, max_connections 100 por defecto. db-g1-small (vCPU compartida, 50 conexiones) es más barato pero añade ruido a las mediciones."
  type        = string
  default     = "db-custom-1-3840"
}

variable "bd_disco_gb" {
  description = "Almacenamiento SSD inicial de Cloud SQL (crece solo hasta bd_disco_max_gb)."
  type        = number
  default     = 10
}

variable "bd_disco_max_gb" {
  description = "Tope del crecimiento automático del disco de Cloud SQL."
  type        = number
  default     = 30
}

variable "bd_retencion_backups" {
  description = "Backups automáticos diarios que se conservan. Se borran con la instancia: el respaldo que sobrevive es el export de bd.sh."
  type        = number
  default     = 3
}

variable "bd_proteccion_terraform" {
  description = "deletion_protection de Terraform: impide que terraform destroy/apply borre la instancia. bd.sh y destruir.sh lo bajan explícitamente."
  type        = bool
  default     = true
}

variable "bd_proteccion_api" {
  description = "settings.deletion_protection_enabled: protección en la propia API de Cloud SQL (también frena la consola y gcloud)."
  type        = bool
  default     = false
}

# --- Almacenamiento ----------------------------------------------------------

variable "permitir_borrar_buckets" {
  description = "force_destroy de los buckets. false: destroy falla si tienen objetos. destruir.sh lo sube tras respaldar."
  type        = bool
  default     = false
}

variable "origenes_cors_extra" {
  description = "Orígenes adicionales permitidos por CORS en los buckets (p. ej. http://localhost:3000 para probar el frontend en local contra GCS)."
  type        = list(string)
  default     = []
}

# --- Costos ------------------------------------------------------------------

variable "cuenta_facturacion" {
  description = "ID de la cuenta de facturación (XXXXXX-XXXXXX-XXXXXX) para el presupuesto. Vacío: no se crea."
  type        = string
  default     = ""
}

variable "presupuesto_monto" {
  description = "Monto mensual del presupuesto, en la moneda de la cuenta de facturación."
  type        = number
  default     = 50
}

variable "presupuesto_moneda" {
  description = "Moneda del presupuesto. Tiene que coincidir con la de la cuenta de facturación (USD, COP...)."
  type        = string
  default     = "USD"
}

# --- Entrega 4: Cloud Run y Pub/Sub ---------------------------------------------

variable "run_tag" {
  description = "Etiqueta de las imágenes que despliegan los servicios de Cloud Run (el commit; desplegar-run.sh la pasa). Una etiqueta nueva crea una revisión nueva."
  type        = string
  default     = "desplegada"
}

# Configuración de cada servicio. max = 3 es el límite del enunciado; un
# contenedor por instancia es como funciona Cloud Run (sin sidecars aquí).
variable "run_api" {
  description = "Backend: región = var.region; min/max instancias, CPU, memoria, peticiones simultáneas por instancia y tiempo máximo de solicitud (s)."
  type = object({
    min = number, max = number, cpu = string, memoria = string, concurrencia = number, timeout = number
  })
  # 600 s: confirmar una carga verifica el archivo entero (checksum, MIME,
  # antivirus), como tenía la ruta en el balanceador de la Entrega 3.
  default = { min = 0, max = 3, cpu = "1", memoria = "512Mi", concurrencia = 80, timeout = 600 }
  validation {
    condition     = var.run_api.max <= 3 && var.run_api.min <= var.run_api.max
    error_message = "El enunciado fija un máximo de 3 instancias por servicio."
  }
}

variable "run_frontend" {
  description = "Frontend: igual que run_api."
  type = object({
    min = number, max = number, cpu = string, memoria = string, concurrencia = number, timeout = number
  })
  default = { min = 0, max = 3, cpu = "1", memoria = "512Mi", concurrencia = 80, timeout = 60 }
  validation {
    condition     = var.run_frontend.max <= 3 && var.run_frontend.min <= var.run_frontend.max
    error_message = "El enunciado fija un máximo de 3 instancias por servicio."
  }
}

variable "run_worker" {
  description = "Workers: igual que run_api. timeout es también el ack deadline de la suscripción (máximo 600)."
  type = object({
    min = number, max = number, cpu = string, memoria = string, concurrencia = number, timeout = number
  })
  # 2 vCPU y 4 GiB: FFmpeg usa toda la CPU y /tmp (originales y segmentos)
  # vive en la memoria de la instancia.
  default = { min = 0, max = 3, cpu = "2", memoria = "4Gi", concurrencia = 1, timeout = 600 }
  validation {
    condition     = var.run_worker.max <= 3 && var.run_worker.min <= var.run_worker.max && var.run_worker.timeout <= 600 && var.run_worker.timeout >= 10
    error_message = "Máximo 3 instancias; timeout entre 10 y 600 s (límites del ack deadline de Pub/Sub)."
  }
}

variable "worker_ingress" {
  description = "Ingress del servicio de workers. INTERNAL_ONLY: Pub/Sub del proyecto entra, Internet no."
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_ONLY"
}

variable "pubsub_max_entregas" {
  description = "Entregas de un mensaje antes de mandarlo a la dead-letter (5 a 100)."
  type        = number
  # Con los 3 workers ocupados, Cloud Run rechaza la entrega push con 429 antes
  # de que llegue al contenedor, y Pub/Sub la cuenta como intento: en la
  # verificación de escalamiento hubo mensajes que llegaron en el 4.º intento.
  # 10 deja margen para colas más largas sin mandar tareas sanas a la DLQ.
  default = 10
}
