#!/usr/bin/env bash
# Genera los tres perfiles de vídeo del Escenario 2. Hace falta ffmpeg en
# la máquina del generador de carga (no en las e2-small).
#
#   load/perfiles/generar.sh
#
# No se versionan los .mp4: son sintéticos y se regeneran. Las duraciones
# caben en una e2-small con WORKER_CONCURRENCY=2; subirlas cambia el
# experimento.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v ffmpeg >/dev/null; then
  echo "hace falta ffmpeg (apt install ffmpeg / brew install ffmpeg)" >&2
  exit 1
fi

# testsrc + sine: no dependen de un archivo de entrada.
# corto  ~5 s, 426x240,  ~0,4 MB  (carga simple)
# medio  ~20 s, 854x480, ~2 MB    (cerca del umbral multipart de 5 MiB)
# largo  ~45 s, 1280x720,~8 MB    (multipart; fuerza ETag/CORS)
ffmpeg -y -f lavfi -i testsrc=size=426x240:rate=24:duration=5 \
  -f lavfi -i sine=frequency=440:duration=5 \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest corto.mp4
ffmpeg -y -f lavfi -i testsrc=size=854x480:rate=24:duration=20 \
  -f lavfi -i sine=frequency=440:duration=20 \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest medio.mp4
ffmpeg -y -f lavfi -i testsrc=size=1280x720:rate=24:duration=45 \
  -f lavfi -i sine=frequency=440:duration=45 \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest largo.mp4

echo "perfiles:"
ls -lh corto.mp4 medio.mp4 largo.mp4
