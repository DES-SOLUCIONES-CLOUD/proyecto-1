-- revisa la base despues del retiro seguro de un worker (entrega 3)
--
--   en gcp, contra cloud sql: lo corre deploy/retiro-seguro/demo-gcp.sh
--   en local: docker compose exec -T postgres psql -U mooc -d mooc < deploy/retiro-seguro/verificar.sql
--
-- despues de detener un worker a mitad de un video y dejar que otro lo
-- termine, deberia verse:
--   1. el video en 'ready', con su hls_master_key y el recurso tambien en 'ready'
--   2. ningun activo pegado en 'processing' o 'queued' (consulta vacia)
--   3. ningun recurso que diga algo distinto de su activo (consulta vacia)
--
-- que no haya dos filas por recurso no prueba nada: lo garantiza el indice
-- unico idx_media_assets_un_recurso. lo que demuestra que el trabajo termino
-- una sola vez es una sola linea 'media: activo listo' en los registros

\echo '1. Ultimos activos multimedia'
SELECT a.id, a.resource_id, a.status, r.processing_status,
       a.hls_master_key, a.failure_reason, a.updated_at
  FROM media_assets a
  JOIN resources r ON r.id = a.resource_id
 ORDER BY a.updated_at DESC
 LIMIT 5;

\echo '2. Activos sin terminar (debe salir vacio cuando la cola este en 0)'
SELECT id, resource_id, status, processing_started_at
  FROM media_assets
 WHERE status IN ('processing', 'queued');

\echo '3. Activo y recurso en desacuerdo (debe salir vacio)'
SELECT a.id, a.resource_id, a.status, r.processing_status
  FROM media_assets a
  JOIN resources r ON r.id = a.resource_id
 WHERE (a.status = 'ready') <> (r.processing_status = 'ready');
