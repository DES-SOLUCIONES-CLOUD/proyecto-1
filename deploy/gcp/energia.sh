#!/usr/bin/env bash
# Enciende o apaga el entorno entre sesiones de trabajo.
#
#   deploy/gcp/energia.sh detener [--con-bd]
#   deploy/gcp/energia.sh iniciar [--con-bd]
#   deploy/gcp/energia.sh estado
#
# Entrega 4: los servicios de Cloud Run tienen mínimo 0 instancias y no
# cobran cómputo sin tráfico, así que no se apagan. Se detienen la VM de
# Redis y, con --con-bd, Cloud SQL.
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

case "$accion" in
  detener)
    gc compute instances stop "$(salida vm_redis)" --zone "$ZONA"
    aviso "VM de Redis detenida"
    if [[ "$con_bd" == true && -n "$BD" ]]; then
      # Cloud SQL detenida no se vuelve a encender sola, pero
      # sigue cobrando almacenamiento y backups.
      gc sql instances patch "$BD" --activation-policy NEVER --quiet
      aviso "Cloud SQL $BD detenida"
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
    aviso "Comprobar: curl -s $(salida url_publica)/api/v1/health"
    registrar_bitacora "encender" "$con_bd"
    ;;
  estado)
    gc compute instances list --filter "labels.proyecto=$(salida prefijo)" \
      --format 'table(name,zone.basename(),machineType.basename(),status,networkInterfaces[0].networkIP)'
    gc run services list --region "$(salida region)" \
      --format 'table(metadata.name,status.latestReadyRevisionName,status.url)'
    if [[ -n "$BD" ]]; then
      gc sql instances describe "$BD" \
        --format 'table(name,settings.tier,state,settings.activationPolicy,ipAddresses[0].ipAddress)'
    fi
    ;;
  *)
    morir "acción desconocida '$accion'"
    ;;
esac
