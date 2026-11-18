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
# comandos que el worker. Se verifica con el MD5 que publica el sitio.
source "$(dirname "$0")/lib.sh"
requiere curl tar xz md5sum

FFMPEG_URL="${FFMPEG_URL:-https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz}"
BUILD="$DIR_TF/.build"
DESTINO="$BUILD/funcion-audio"
ZIP="$BUILD/funcion-audio.zip"
CACHE="$BUILD/cache"
BACKEND="$RAIZ/backend"

mkdir -p "$CACHE"

# --- FFmpeg ----------------------------------------------------------------------
#
# El sitio a veces responde con una página de espera anti-bots ("One moment,
# please...") en lugar del archivo, con código 200. Por eso no basta con que
# curl termine bien: se comprueba que lo descargado sea un .tar.xz íntegro
# (xz -t) y, si no, se reintenta con espera creciente.
paquete="$CACHE/$(basename "$FFMPEG_URL")"
if [[ -s "$paquete" ]] && ! xz -t "$paquete" 2>/dev/null; then
  rm -f "$paquete"
fi
intento=1
while [[ ! -s "$paquete" ]]; do
  aviso "descargando $FFMPEG_URL (intento $intento)"
  if curl -fsSL --retry 3 -A "mooc-deploy (curl)" -o "$paquete.tmp" "$FFMPEG_URL" && xz -t "$paquete.tmp" 2>/dev/null; then
    mv "$paquete.tmp" "$paquete"
    break
  fi
  rm -f "$paquete.tmp"
  (( intento < 6 )) || morir "no se pudo descargar FFmpeg de $FFMPEG_URL (el sitio no entregó un .tar.xz válido); probar más tarde o pasar otro FFMPEG_URL"
  sleep $(( intento * 15 ))
  intento=$(( intento + 1 ))
done

# MD5 publicado por el sitio, solo si lo que devuelve es de verdad un hash (la
# misma página de espera puede llegar en lugar del .md5).
esperado="$(curl -fsSL --retry 3 -A "mooc-deploy (curl)" "$FFMPEG_URL.md5" 2>/dev/null | awk 'NR==1 {print $1}' || true)"
obtenido="$(md5sum "$paquete" | awk '{print $1}')"
if [[ "$esperado" =~ ^[0-9a-f]{32}$ ]]; then
  [[ "$esperado" == "$obtenido" ]] || { rm -f "$paquete"; morir "MD5 de FFmpeg no coincide ($obtenido != $esperado); se borró la descarga"; }
  aviso "FFmpeg verificado (md5 $obtenido)"
else
  aviso "AVISO: el sitio no entregó el .md5; FFmpeg verificado solo como .tar.xz íntegro (md5 $obtenido)"
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
