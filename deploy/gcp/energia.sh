#!/usr/bin/env bash
# Enciende o apaga el entorno entre sesiones de trabajo.
#
#   deploy/gcp/energia.sh detener [--con-bd]
#   deploy/gcp/energia.sh iniciar [--con-bd]
#   deploy/gcp/energia.sh estado
#
# Los MIG no se "detienen": se apaga su autoscaler (modo off, conserva la
# política) y se reducen a 0 instancias, que se borran. Al iniciar, el
# autoscaler vuelve a modo on y crea el mínimo; las instancias nuevas se
# configuran solas desde la plantilla. La VM de Redis sí se detiene y se
# enciende: su disco guarda la cola (appendonly). Un `terraform apply` con
# los MIG apagados vuelve a encender sus autoscalers.
#
# Detener no deja el costo en cero: siguen cobrándose el disco de Redis, las
# reglas de reenvío del balanceador, Cloud NAT si está habilitada, el
# almacenamiento de Cloud SQL y sus backups, los buckets y Artifact Registry.
# Ver README.
source "$(dirname "$0")/lib.sh"
requiere terraform
comprobar_gcloud
requiere_infra

accion="${1:?uso: energia.sh <detener|iniciar|estado> [--con-bd]}"
con_bd=false
[[ "${2:-}" == "--con-bd" ]] && con_bd=true
ZONA="$(salida zona)"
BD="$(salida bd_instancia)"
MIGS=("$(salida mig_api)" "$(salida mig_workers)")

case "$accion" in
  detener)
    for mig in "${MIGS[@]}"; do
      gc compute instance-groups managed update-autoscaling "$mig" --zone "$ZONA" --mode off --quiet >/dev/null
      gc compute instance-groups managed resize "$mig" --zone "$ZONA" --size 0 --quiet >/dev/null
      aviso "$mig: autoscaler apagado, 0 instancias"
    done
    gc compute instances stop "$(salida vm_redis)" --zone "$ZONA"
    aviso "VM de Redis detenida"
    if [[ "$con_bd" == true && -n "$BD" ]]; then
      # Cloud SQL detenida no se vuelve a encender sola, pero
      # sigue cobrando almacenamiento y backups.
      gc sql instances patch "$BD" --activation-policy NEVER --quiet
      aviso "Cloud SQL $BD detenida"
    fi
    if [[ "$(salida nat_activa)" == true ]]; then
      aviso "Cloud NAT sigue habilitada y cobrando. Los MIG la necesitan para crear instancias: no quitarla si se va a volver a iniciar."
    fi
    registrar_bitacora "apagar" "$con_bd"
    ;;
  iniciar)
    if [[ "$con_bd" == true && -n "$BD" ]]; then
      gc sql instances patch "$BD" --activation-policy ALWAYS --quiet
      aviso "Cloud SQL $BD en marcha"
    fi
    # Primero Redis: la API y los workers conectan con él al arrancar.
    gc compute instances start "$(salida vm_redis)" --zone "$ZONA"
    for mig in "${MIGS[@]}"; do
      gc compute instance-groups managed update-autoscaling "$mig" --zone "$ZONA" --mode on --quiet >/dev/null
      aviso "$mig: autoscaler encendido; crea el mínimo de instancias"
    done
    aviso "Las instancias tardan unos 4 minutos en atender. Comprobar: curl -sI $(salida url_publica)/"
    registrar_bitacora "encender" "$con_bd"
    ;;
  estado)
    gc compute instances list --filter "labels.proyecto=$(salida prefijo)" \
      --format 'table(name,zone.basename(),machineType.basename(),status,networkInterfaces[0].networkIP)'
    for mig in "${MIGS[@]}"; do
      gc compute instance-groups managed describe "$mig" --zone "$ZONA" \
        --format 'table(name,targetSize,status.isStable,status.autoscaler.basename())'
    done
    if [[ -n "$BD" ]]; then
      gc sql instances describe "$BD" \
        --format 'table(name,settings.tier,state,settings.activationPolicy,ipAddresses[0].ipAddress)'
    fi
    ;;
  *)
    morir "acción desconocida '$accion'"
    ;;
esac
