#!/usr/bin/env bash
# Abre una sesión o ejecuta un comando en una VM por el túnel de IAP. Con
# api o worker entra en la primera instancia en marcha de su MIG.
#
#   deploy/gcp/remoto.sh redis                                    # sesión interactiva
#   deploy/gcp/remoto.sh api 'sudo /opt/mooc/bin/en-vm.sh estado'
#   deploy/gcp/remoto.sh worker 'sudo docker logs -f mooc-worker-worker-1'
#   deploy/gcp/remoto.sh redis -- -L 8025:127.0.0.1:8025 -N       # Mailpit en localhost:8025
#
# Lo que sigue a `--` va tal cual a ssh (túneles de puertos).
source "$(dirname "$0")/lib.sh"
requiere terraform
comprobar_gcloud
requiere_infra

rol="${1:?uso: remoto.sh <api|worker|redis> [comando | -- opciones de ssh]}"
shift
vm="$(vm_de "$rol")"
if [[ "${1:-}" == "--" ]]; then
  gc compute ssh "$vm" --zone "$(salida zona)" --tunnel-through-iap "$@"
elif [[ $# -gt 0 ]]; then
  ssh_vm "$rol" "$*"
else
  gc compute ssh "$vm" --zone "$(salida zona)" --tunnel-through-iap
fi
