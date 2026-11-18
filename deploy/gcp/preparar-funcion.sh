#!/usr/bin/env bash
# Entrega 5: arma el código desplegable de la Cloud Function de audio en
# deploy/gcp/terraform/.build/funcion-audio/ (ignorado por git). Terraform lo
# comprime (archive_file), lo sube al bucket de código y despliega la función
# con él (funcion.tf). Hay que correrlo antes de `terraform plan` y cada vez
# que cambie backend/ o se quiera otra versión de FFmpeg.
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
# comandos que el worker. Se verifica con el MD5 que publica el sitio.
source "$(dirname "$0")/lib.sh"
requiere curl tar xz md5sum

FFMPEG_URL="${FFMPEG_URL:-https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz}"
BUILD="$DIR_TF/.build"
DESTINO="$BUILD/funcion-audio"
CACHE="$BUILD/cache"
BACKEND="$RAIZ/backend"

mkdir -p "$CACHE"

# --- FFmpeg ----------------------------------------------------------------------
paquete="$CACHE/$(basename "$FFMPEG_URL")"
if [[ ! -s "$paquete" ]]; then
  aviso "descargando $FFMPEG_URL"
  curl -fsSL --retry 3 -o "$paquete.tmp" "$FFMPEG_URL"
  mv "$paquete.tmp" "$paquete"
fi
if curl -fsSL --retry 3 -o "$paquete.md5" "$FFMPEG_URL.md5" 2>/dev/null; then
  esperado="$(awk '{print $1}' "$paquete.md5")"
  obtenido="$(md5sum "$paquete" | awk '{print $1}')"
  [[ "$esperado" == "$obtenido" ]] || { rm -f "$paquete"; morir "MD5 de FFmpeg no coincide ($obtenido != $esperado); se borró la descarga"; }
  aviso "FFmpeg verificado (md5 $obtenido)"
else
  aviso "AVISO: no hay $FFMPEG_URL.md5; FFmpeg sin verificar"
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

aviso "código de la función listo en $DESTINO ($(du -sh "$DESTINO" | awk '{print $1}'))"
aviso "siguiente: terraform plan / apply (funcion.tf lo comprime y lo sube)"
