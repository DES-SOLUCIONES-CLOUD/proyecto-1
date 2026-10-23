-- revisa la base despues del retiro seguro de un worker (entrega 3)
--
--   docker compose exec -T postgres psql -U mooc -d mooc < deploy/retiro-seguro/verificar.sql
--
-- despues de detener un worker a mitad de un video y dejar que otro lo
-- termine, deberia verse:
--   1. el video con una sola fila, en 'ready' y con su hls_master_key
--   2. ningun recurso con mas de un activo (consulta vacia)
--   3. ningun activo pegado en 'processing' (consulta vacia)

\echo '1. Ultimos activos multimedia'
SELECT id, resource_id, status, hls_master_key, failure_reason, updated_at
  FROM media_assets
 ORDER BY updated_at DESC
 LIMIT 5;

\echo '2. Recursos con mas de un activo (debe salir vacio)'
SELECT resource_id, count(*) AS activos
  FROM media_assets
 GROUP BY resource_id
HAVING count(*) > 1;

\echo '3. Activos atascados en processing (debe salir vacio)'
SELECT id, resource_id, processing_started_at
  FROM media_assets
 WHERE status = 'processing';
