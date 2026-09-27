# Comandos de evidencia (ítems 14–19)

Correrlos después del primer despliegue. Pegar salidas y capturas en
`capacity-planning/evidencias/` y en el video.

Sustituir `<proyecto>`, `<bucket_objetos>`, `<bucket_hls>`, `<bd>`,
`<ip>`. Salen de `terraform -chdir=deploy/gcp/terraform output`.

## 14. Configuración

```bash
deploy/gcp/resumen.sh
gcloud compute instances describe mooc-web --zone ZONE
gcloud compute instances describe mooc-worker --zone ZONE
gcloud sql instances describe BD
gcloud compute firewall-rules list --filter='name~mooc'
gcloud compute networks subnets list --filter='network~mooc'
```

## 15. Seguridad y red

Desde fuera (el portátil, no las VM):

```bash
nc -vz IP 22      # tiene que fallar
nc -vz IP 6379
nc -vz IP 5432
curl -vI https://IP.sslip.io/
# Cookie: Secure; certificado de Let's Encrypt (no autofirmado)
```

SSL de la base, desde el Web:

```bash
deploy/gcp/remoto.sh web
# psql con sslmode=require; luego:
SELECT * FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

## 16. Almacenamiento

En el navegador: carga simple (< 5 MiB) y multipart (perfil `largo`).
La respuesta del PUT tiene que exponer `ETag` (CORS). Reproducir cuando
el recurso esté `ready`.

```bash
# URL firmada (la de /content o una de upload): 200
curl -I "$URL_FIRMADA"
# La misma sin query string, o con X-Amz-Expires=1 ya vencida: 403
curl -I "${URL_SIN_FIRMA}"
# Listar el bucket HLS como anónimo: 403 (legacyObjectReader no lista)
curl -I "https://storage.googleapis.com/${BUCKET_HLS}/"
```

## 17. Permisos por componente

Con las HMAC de Secret Manager (`mooc-hmac-web-secret`,
`mooc-hmac-worker-secret`) y un cliente S3 (mc o aws):

- Worker: PUT a `resources/<uuid>/original` en el bucket privado → 403
- API: PUT a `hls/prueba.ts` en el bucket HLS → 403

No pegar los secretos en el video; sí el 403 y la clave (access id, no
el secreto).

## 18. Asíncrono

Confirmar la misma carga dos veces: mismo `media_asset_id`. Subir un
WAV truncado o matar FFmpeg a mitad: reintento visible en
`docker compose logs worker`. Al terminar, cola vacía (`metricas.sh` o
`GET /api/v1/admin/queues`).

## 19. CI

Consola → IAM → Workload Identity: condición del proveedor (repo +
`ref == refs/heads/main` + entorno `gcp` o `gcp-rutina`). Cuenta
`…-compute@developer.gserviceaccount.com` deshabilitada y sin Editor.
Settings → Environments: `gcp` y `gcp-rutina` limitados a `main`.
