# Entrega 5: evidencias

> **Pendiente de completar tras el despliegue.** Cada sección dice qué
> capturar y con qué comando. Las capturas van en `evidencias/` con el
> número de la sección.

## 1. Despliegue con Terraform

- [ ] `terraform plan` con los recursos nuevos: `google_pubsub_topic.audio`,
  `google_cloudfunctions2_function.audio`, `google_storage_bucket.codigo`,
  `google_storage_bucket_object.funcion_audio`, la clave HMAC y el secreto de
  la función, los permisos y el cambio de imagen de Cloud Run (`run_tag`).
  → `evidencias/01-plan.png`
- [ ] `terraform apply` terminado (`Apply complete!` y outputs
  `funcion_audio`, `topic_audio`). → `evidencias/02-apply.png`
- [ ] Una **actualización**: cambiar `funcion_audio.max` o el código, volver
  a hacer `plan`/`apply` y ver el cambio en sitio (`~ update in-place`).
  → `evidencias/03-actualizacion.png`
- [ ] Consola: la función `mooc-audio` (2ª gen., activador Pub/Sub
  `mooc-audio`, cuenta `mooc-fn-audio`, máx. 3 instancias).
  → `evidencias/04-consola-funcion.png`

## 2. Tarea real: Pub/Sub → función → resultado

1. Como profesor, subir un audio (MP3/WAV) a un recurso de tipo audio.
2. Registros del recorrido:

   ```bash
   gcloud logging read 'resource.labels.service_name="mooc-api" AND jsonPayload.accion="queue.task_published"' --freshness 30m --limit 5
   gcloud logging read 'resource.labels.service_name="mooc-audio" AND (jsonPayload.accion=~"queue.task_" OR jsonPayload.message=~"^media:")' \
     --freshness 30m --format 'table(timestamp, jsonPayload.accion, jsonPayload.message, jsonPayload.message_id, jsonPayload.duracion_ms)'
   ```

   - [ ] API publica en `mooc-audio` → `evidencias/05-publicacion.png`
   - [ ] La función: `queue.task_received` → `media: trabajo aceptado` →
     `media: pista de audio transcodificada` → `media: HLS publicado` →
     `media: activo listo` → `queue.task_acked` → `evidencias/06-funcion-logs.png`
3. Resultado:
   - [ ] `gcloud storage ls gs://plasma-sol-513002-k6-mooc-hls/hls/<recurso>/`
     (`master.m3u8`, `audio.m3u8`, `audio_000.ts`…) → `evidencias/07-hls.png`
   - [ ] Estado en Cloud SQL (`status = ready`, `hls_master_key`) y el audio
     reproduciéndose en la plataforma → `evidencias/08-resultado.png`
   - [ ] El worker **no** registra la tarea (`mooc-worker` sin
     `media:process-audio`) → `evidencias/09-worker-sin-audio.png`

## 3. Reintento sin duplicados

- [ ] Volver a publicar el mismo mensaje en `mooc-audio`: la función registra
  `media: entrega duplicada descartada` y confirma. `gcloud storage ls`
  muestra los mismos objetos con la misma fecha. → `evidencias/10-duplicado.png`

## 4. Video

- [ ] Enlace (máximo 20 min): migración, `terraform plan`/`apply` y la tarea
  por Pub/Sub y la función.
