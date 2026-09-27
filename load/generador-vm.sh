#!/usr/bin/env bash
# VM temporal del generador de carga. No es una de las dos e2-small:
# e2-standard-2 en la misma región, red default, IP pública, para pegarle
# a la URL https://…sslip.io como un cliente real.
#
#   load/generador-vm.sh crear
#   load/generador-vm.sh ssh
#   load/generador-vm.sh borrar     # cuando terminen las corridas
#
# No vive en Terraform: si se olvida, sigue cobrando (~0,07 USD/h).
set -euo pipefail

PROYECTO="${GCP_PROJECT_ID:-totemic-gravity-509902-u2}"
ZONA="${GCP_ZONE:-us-central1-a}"
NOMBRE="${GENERADOR_VM:-mooc-k6}"
TIPO="${GENERADOR_TIPO:-e2-standard-2}"

gc() { gcloud --project "$PROYECTO" "$@"; }

crear() {
  if gc compute instances describe "$NOMBRE" --zone "$ZONA" >/dev/null 2>&1; then
    echo "ya existe $NOMBRE en $ZONA" >&2
    return
  fi
  gc compute instances create "$NOMBRE" \
    --zone "$ZONA" \
    --machine-type "$TIPO" \
    --image-family debian-12 \
    --image-project debian-cloud \
    --boot-disk-size 30GB \
    --boot-disk-type pd-balanced \
    --tags mooc-generador \
    --labels entrega=2,rol=generador,proyecto=mooc \
    --metadata=enable-oslogin=TRUE \
    --metadata-from-file startup-script=<(cat <<'ARR'
#!/bin/bash
set -euo pipefail
exec >>/var/log/mooc-k6-arranque.log 2>&1
echo "== arranque $(date -Is)"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg git ffmpeg
# Misma versión que docker-compose (load/README.md).
curl -fsSL https://github.com/grafana/k6/releases/download/v1.8.1/k6-v1.8.1-linux-amd64.tar.gz \
  | tar -xz -C /tmp
install -m 0755 /tmp/k6-v1.8.1-linux-amd64/k6 /usr/local/bin/k6
rm -rf /tmp/k6-v1.8.1-linux-amd64
touch /var/lib/mooc-k6-ok
echo "== listo $(date -Is) k6=$(k6 version)"
ARR
)
  echo "creada $NOMBRE ($TIPO). Espera 2-3 min: sudo tail -f /var/log/mooc-k6-arranque.log"
}

ssh_gen() {
  gc compute ssh "$NOMBRE" --zone "$ZONA" "$@"
}

borrar() {
  gc compute instances delete "$NOMBRE" --zone "$ZONA" --quiet
  echo "borrada $NOMBRE"
}

case "${1:-}" in
  crear) crear ;;
  ssh) shift; ssh_gen "$@" ;;
  borrar) borrar ;;
  *)
    echo "uso: $0 crear|ssh|borrar" >&2
    exit 2
    ;;
esac
