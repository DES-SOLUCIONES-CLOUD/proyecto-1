#!/usr/bin/env bash
# Entrega 5: arma el código desplegable de la Cloud Function de audio en
# deploy/gcp/terraform/.build/funcion-audio.zip (ignorado por git). Terraform
# lo sube al bucket de código y despliega la función con él (funcion.tf).
# Hay que correrlo antes de `terraform plan` y cada vez que cambie backend/ o
# se quiera otra versión de FFmpeg (desplegar-infra.sh ya lo llama).
#
#   deploy/gcp/preparar-funcion.sh
#   FFMPEG_URL=https://.../ffmpeg-7.0.2-amd64-static.tar.xz deploy/gcp/preparar-funcion.sh
#
# Qué contiene:
#
#   go.mod, go.sum, internal/, migrations/   el módulo del backend, sin pruebas
#   funcion.go                                backend/funciones/audio, en la raíz:
#                                             el buildpack de Go compila el
#                                             paquete raíz del módulo
#   bin/ffmpeg, bin/ffprobe                   FFmpeg estático para linux/amd64
#
# FFmpeg va dentro porque la imagen base por defecto de Cloud Run functions
# para Go (google-24) no lo trae, y la función usa exactamente los mismos
# comandos que el worker.
#
# De dónde sale FFmpeg, en orden:
#   1. la copia local (.build/cache), si su MD5 es FFMPEG_MD5;
#   2. la copia del proyecto en gs://<bucket del estado>/cache/ (FFMPEG_GCS);
#   3. el sitio de origen (FFMPEG_URL), y si llega bien se guarda en (2).
# El sitio bloquea con una página anti-bots a los runners de GitHub, así que
# en CI la fuente real es (2). FFMPEG_MD5 fija la versión: sin él, una
# versión nueva publicada en el sitio cambiaría la función sin pasar por git.
source "$(dirname "$0")/lib.sh"
requiere curl tar xz md5sum

FFMPEG_URL="${FFMPEG_URL:-https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz}"
# ffmpeg-7.0.2-amd64-static (release de johnvansickle.com, agosto de 2024).
FFMPEG_MD5="${FFMPEG_MD5:-7fa72b652e19bf84c9461e332ea1cdf3}"
BUILD="$DIR_TF/.build"
DESTINO="$BUILD/funcion-audio"
ZIP="$BUILD/funcion-audio.zip"
CACHE="$BUILD/cache"
BACKEND="$RAIZ/backend"

mkdir -p "$CACHE"

# --- FFmpeg ----------------------------------------------------------------------
nombre="$(basename "$FFMPEG_URL")"
paquete="$CACHE/$nombre"
if [[ -z "${FFMPEG_GCS:-}" ]]; then
  # bucket_estado sale con `morir` si no hay TF_STATE_BUCKET ni tfvars: sin
  # bucket simplemente no hay copia en GCS.
  bucket="$(bucket_estado 2>/dev/null)" || bucket=""
  if [[ -n "$bucket" ]]; then
    FFMPEG_GCS="gs://$bucket/cache/$FFMPEG_MD5-$nombre"
  fi
fi

# valido <archivo>: .tar.xz íntegro y con el MD5 esperado.
valido() {
  [[ -s "$1" ]] && xz -t "$1" 2>/dev/null && [[ "$(md5sum "$1" | awk '{print $1}')" == "$FFMPEG_MD5" ]]
}

if valido "$paquete"; then
  aviso "FFmpeg: copia local (md5 $FFMPEG_MD5)"
else
  rm -f "$paquete"
  if [[ -n "${FFMPEG_GCS:-}" ]] && command -v gcloud >/dev/null 2>&1 \
     && gcloud storage cp --quiet "$FFMPEG_GCS" "$paquete.tmp" >/dev/null 2>&1 && valido "$paquete.tmp"; then
    mv "$paquete.tmp" "$paquete"
    aviso "FFmpeg: copia del proyecto $FFMPEG_GCS (md5 $FFMPEG_MD5)"
  else
    rm -f "$paquete.tmp"
    # El sitio a veces responde con una página de espera anti-bots ("One
    # moment, please...") con código 200: se exige un .tar.xz íntegro con el
    # MD5 fijado, y si no, se reintenta con espera creciente.
    intento=1
    until valido "$paquete"; do
      aviso "descargando $FFMPEG_URL (intento $intento)"
      if curl -fsSL --retry 3 -A "mooc-deploy (curl)" -o "$paquete.tmp" "$FFMPEG_URL" && valido "$paquete.tmp"; then
        mv "$paquete.tmp" "$paquete"
        break
      fi
      if [[ -s "$paquete.tmp" ]] && xz -t "$paquete.tmp" 2>/dev/null; then
        rm -f "$paquete.tmp"
        morir "el sitio publicó otro FFmpeg (md5 distinto de $FFMPEG_MD5): para usarlo, fijar FFMPEG_MD5 a propósito"
      fi
      rm -f "$paquete.tmp"
      (( intento < 4 )) || morir "no se pudo obtener FFmpeg: ni ${FFMPEG_GCS:-(sin copia en GCS)} ni $FFMPEG_URL (bloqueado por el sitio). Subir la copia: gcloud storage cp <ffmpeg.tar.xz> ${FFMPEG_GCS:-gs://<bucket>/cache/$FFMPEG_MD5-$nombre}"
      sleep $(( intento * 15 ))
      intento=$(( intento + 1 ))
    done
    aviso "FFmpeg: descargado del sitio (md5 $FFMPEG_MD5)"
    if [[ -n "${FFMPEG_GCS:-}" ]] && command -v gcloud >/dev/null 2>&1; then
      if gcloud storage cp --quiet "$paquete" "$FFMPEG_GCS" >/dev/null 2>&1; then
        aviso "FFmpeg: guardado en $FFMPEG_GCS para los próximos despliegues"
      else
        aviso "AVISO: no se pudo guardar FFmpeg en $FFMPEG_GCS"
      fi
    fi
  fi
fi

# --- Código ----------------------------------------------------------------------
rm -rf "$DESTINO"
mkdir -p "$DESTINO/bin"

cp "$BACKEND/go.mod" "$BACKEND/go.sum" "$DESTINO/"
cp -r "$BACKEND/internal" "$BACKEND/migrations" "$DESTINO/"
find "$DESTINO" -name '*_test.go' -delete
cp "$BACKEND/funciones/audio/funcion.go" "$DESTINO/funcion.go"

tar -xJf "$paquete" -C "$DESTINO/bin" --strip-components 1 --wildcards '*/ffmpeg' '*/ffprobe'
chmod 0755 "$DESTINO/bin/ffmpeg" "$DESTINO/bin/ffprobe"

# --- Zip determinista ------------------------------------------------------------
#
# En CI el plan y el apply corren en máquinas distintas y el apply usa el plan
# guardado: el zip se vuelve a armar en la segunda y tiene que salir idéntico
# (su MD5 va en el nombre del objeto que planificó la primera). Por eso no se
# usa archive_file ni `zip`: aquí van rutas ordenadas, fecha fija y permisos
# 0755 (también para bin/ffmpeg cuando se arma en Windows).
PY="$(command -v python3 || command -v python || true)"
[[ -n "$PY" ]] || morir "falta python3 para armar el zip"
"$PY" - "$DESTINO" "$ZIP" <<'PYEOF'
import os, sys, zipfile
origen, destino = sys.argv[1], sys.argv[2]
rutas = []
for raiz, dirs, archivos in os.walk(origen):
    dirs.sort()
    for a in sorted(archivos):
        rutas.append(os.path.join(raiz, a))
tmp = destino + ".tmp"
with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for ruta in rutas:
        nombre = os.path.relpath(ruta, origen).replace(os.sep, "/")
        info = zipfile.ZipInfo(nombre, date_time=(2020, 1, 1, 0, 0, 0))
        info.external_attr = (0o100755 & 0xFFFF) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        with open(ruta, "rb") as f:
            z.writestr(info, f.read(), compresslevel=6)
os.replace(tmp, destino)
PYEOF

aviso "código de la función listo: $ZIP ($(du -h "$ZIP" | awk '{print $1}'), md5 $(md5sum "$ZIP" | awk '{print $1}'))"
aviso "siguiente: terraform plan / apply (funcion.tf lo sube y despliega la función)"
