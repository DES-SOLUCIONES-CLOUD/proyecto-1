#!/usr/bin/env bash
# Migra los objetos de MinIO local y la base de Postgres local a GCS y
# Cloud SQL, y deja evidencia reproducible en capacity-planning/evidencias/:
# conteo de objetos trasladados, checksum MD5 de cada uno (local vs. GCS)
# y el registro completo de `gcloud sql import sql`. Antes esto era un
# procedimiento manual documentado en el README; la rúbrica pide la salida,
# no solo la receta.
#
#   deploy/gcp/migrar-datos.sh
#
# Precondiciones: el compose local está arriba con los datos de la entrega
# anterior (MinIO + Postgres) y la infraestructura de GCP ya existe
# (desplegar-infra.sh). Correrlo ANTES de desplegar la API (paso 7 del
# README de deploy/gcp): si arranca contra la base vacía, migra el esquema
# y la importación de abajo choca con las tablas ya creadas.
source "$(dirname "$0")/lib.sh"
requiere terraform mc openssl docker
comprobar_gcloud
requiere_infra

BUCKET_OBJ="$(salida bucket_objetos)"
BUCKET_HLS="$(salida bucket_hls)"
BUCKET_RESP="$(salida bucket_respaldos)"
BD="$(salida bd_instancia)"
[[ -n "$BD" ]] || morir "no hay instancia de Cloud SQL (crear_bd=false): nada que importar"

SELLO="$(date -u +%Y%m%dT%H%M%SZ)"
DIR_TMP="$(mktemp -d)"
trap 'rm -rf "$DIR_TMP"' EXIT
EVIDENCIA="$RAIZ/capacity-planning/evidencias/migracion-datos-$SELLO.md"
mkdir -p "$(dirname "$EVIDENCIA")"

aviso "1/5 — exportando objetos de MinIO local"
mc alias set local "http://localhost:${MINIO_API_PORT:-9100}" \
  "${MINIO_ROOT_USER:-minioadmin}" "${MINIO_ROOT_PASSWORD:-minioadmin}" >/dev/null
mc mirror --quiet local/mooc "$DIR_TMP/objetos"
TOTAL_LOCAL="$(find "$DIR_TMP/objetos" -type f | wc -l | tr -d ' ')"
aviso "$TOTAL_LOCAL objetos en MinIO local"

aviso "2/5 — subiendo a GCS (las claves no cambian; solo hls/ va a otro bucket)"
if [[ -d "$DIR_TMP/objetos/hls" ]]; then
  gc storage rsync --recursive "$DIR_TMP/objetos/hls" "gs://$BUCKET_HLS/hls"
fi
gc storage rsync --recursive --exclude '^hls/' "$DIR_TMP/objetos" "gs://$BUCKET_OBJ"

aviso "3/5 — verificando el checksum de los $TOTAL_LOCAL objetos (un gcloud por objeto: tarda)"
REPORTE_CHECKSUM="$DIR_TMP/checksums.tsv"
printf 'clave\testado\tmd5_local\tmd5_remoto\n' > "$REPORTE_CHECKSUM"
OK=0
MAL=0
while IFS= read -r -d '' archivo; do
  clave="${archivo#"$DIR_TMP"/objetos/}"
  if [[ "$clave" == hls/* ]]; then bucket="$BUCKET_HLS"; else bucket="$BUCKET_OBJ"; fi
  md5_local="$(openssl md5 -binary "$archivo" | base64)"
  md5_remoto="$(gc storage objects describe "gs://$bucket/$clave" --format='value(md5_hash)' 2>/dev/null || true)"
  if [[ -n "$md5_remoto" && "$md5_local" == "$md5_remoto" ]]; then
    estado=OK
    OK=$((OK + 1))
  else
    estado=DIFERENTE
    MAL=$((MAL + 1))
  fi
  printf '%s\t%s\t%s\t%s\n' "$clave" "$estado" "$md5_local" "$md5_remoto" >> "$REPORTE_CHECKSUM"
done < <(find "$DIR_TMP/objetos" -type f -print0)
aviso "checksums: $OK coinciden, $MAL no coinciden (de $TOTAL_LOCAL)"

aviso "4/5 — exportando Postgres local e importando en Cloud SQL ($BD)"
(cd "$RAIZ" && docker compose exec -T postgres pg_dump -U mooc --no-owner --no-acl mooc) \
  | gzip > "$DIR_TMP/mooc.sql.gz"
DESTINO_EXPORT="gs://$BUCKET_RESP/exports/mooc-migracion-$SELLO.sql.gz"
gc storage cp "$DIR_TMP/mooc.sql.gz" "$DESTINO_EXPORT"
LOG_IMPORT="$DIR_TMP/import-cloudsql.log"
if gc sql import sql "$BD" "$DESTINO_EXPORT" --database mooc --user mooc --quiet 2>&1 | tee "$LOG_IMPORT"; then
  ESTADO_IMPORT="correcta"
else
  ESTADO_IMPORT="FALLÓ (ver registro)"
fi

aviso "5/5 — escribiendo evidencia en $EVIDENCIA"
{
  echo "# Migración de datos — $SELLO"
  echo
  echo "| Campo | Valor |"
  echo "|---|---|"
  echo "| Fecha (UTC) | $SELLO |"
  echo "| Objetos en MinIO local | $TOTAL_LOCAL |"
  echo "| Objetos con checksum verificado (coincide) | $OK |"
  echo "| Objetos con checksum distinto | $MAL |"
  echo "| Bucket privado destino | \`$BUCKET_OBJ\` |"
  echo "| Bucket HLS destino | \`$BUCKET_HLS\` |"
  echo "| Instancia Cloud SQL | \`$BD\` |"
  echo "| Export de la base | \`$DESTINO_EXPORT\` |"
  echo "| Importación a Cloud SQL | $ESTADO_IMPORT |"
  echo
  echo "## Checksums por objeto (MD5 en base64, local vs. GCS)"
  echo
  echo '```'
  cat "$REPORTE_CHECKSUM"
  echo '```'
  echo
  echo "## Registro de \`gcloud sql import sql\`"
  echo
  echo '```'
  cat "$LOG_IMPORT"
  echo '```'
} > "$EVIDENCIA"
aviso "evidencia escrita: $EVIDENCIA"

[[ "$MAL" -eq 0 ]] || morir "$MAL objeto(s) no verificaron checksum: revisar $EVIDENCIA antes de desplegar la API"
[[ "$ESTADO_IMPORT" == "correcta" ]] || morir "la importación a Cloud SQL falló: ver $EVIDENCIA"
aviso "migración completa: $TOTAL_LOCAL objetos verificados, importación a $BD correcta"
