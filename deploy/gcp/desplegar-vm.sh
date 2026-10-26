#!/usr/bin/env bash
# Despliega en los dos MIG un commit publicado con publicar.sh.
#
#   deploy/gcp/desplegar-vm.sh            # el último publicado desde aquí
#   deploy/gcp/desplegar-vm.sh <tag>      # un commit publicado concreto
#
# Las plantillas arrancan las imágenes con la etiqueta "desplegada"
# (variable imagen_tag de Terraform). Desplegar es:
#
# 1. mover "desplegada" al commit en Artifact Registry, y
# 2. reemplazar de forma gradual las instancias de mig-workers y mig-api
#    (una nueva antes de retirar cada vieja, nunca menos de las que había).
#
# Así Terraform no necesita conocer el commit y un `terraform apply` sin
# argumentos no puede volver atrás una versión. Una instancia que el
# autoscaler cree después ya nace con el commit nuevo. Volver atrás es
# desplegar el tag anterior.
source "$(dirname "$0")/lib.sh"
requiere git terraform
comprobar_gcloud
requiere_infra

TAG="${1:-$(cat "$ESTADO/ultimo-tag" 2>/dev/null || true)}"
[[ -n "$TAG" ]] || morir "sin tag: ejecuta publicar.sh o pásalo como argumento"
git -C "$RAIZ" cat-file -e "$TAG^{commit}" 2>/dev/null || morir "el tag $TAG no es un commit de este repositorio"
REGISTRO="$(salida registro)"
ETIQUETA="$(salida imagen_tag)"
ZONA="$(salida zona)"
[[ "$ETIQUETA" != "$TAG" ]] || morir "imagen_tag de Terraform es el propio commit; este script solo sirve con una etiqueta móvil (desplegada)"

# Que el commit exista en git no quiere decir que se haya publicado. Sin
# esta comprobación el fallo llega después, en instancias que no arrancan.
imagenes=(mooc-api mooc-migrate mooc-seed mooc-frontend mooc-worker)
for img in "${imagenes[@]}"; do
  gc artifacts docker images describe "$REGISTRO/$img:$TAG" >/dev/null 2>&1 \
    || morir "no está publicada $REGISTRO/$img:$TAG: ejecuta deploy/gcp/publicar.sh en ese commit"
done

aviso "moviendo :$ETIQUETA a $TAG"
for img in "${imagenes[@]}"; do
  gc artifacts docker tags add "$REGISTRO/$img:$TAG" "$REGISTRO/$img:$ETIQUETA" --quiet >/dev/null
done

# Primero los workers: una API nueva puede encolar trabajos con un formato
# que un worker viejo no entienda; al revés no pasa.
for mig in "$(salida mig_workers)" "$(salida mig_api)"; do
  aviso "reemplazando las instancias de $mig"
  gc compute instance-groups managed rolling-action replace "$mig" --zone "$ZONA" \
    --max-surge 1 --max-unavailable 0 --quiet >/dev/null
  # Estable = todas las instancias con la plantilla vigente y en marcha. Con
  # el arranque (Docker, imágenes) cada reemplazo tarda unos minutos.
  gc compute instance-groups managed wait-until "$mig" --zone "$ZONA" --stable --timeout 1800
done

mkdir -p "$ESTADO"
echo "$TAG" > "$ESTADO/ultimo-desplegado"
aviso "desplegado $TAG. Comprobar: curl -sI $(salida url_publica)/"
