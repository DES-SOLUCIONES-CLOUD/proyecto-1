-- Reconciliación del Escenario 3B: compara lo aceptado con su estado final.
-- Los cursos de la corrida se reconocen por su slug e3b-*.
--
-- Comparar la suma de la consulta 1 con mooc_trabajos_encolados del resumen
-- de k6. Se corre al terminar el drenaje; las consultas 2 y 3 deben salir
-- vacías.

\echo '1. Activos del 3B por estado'
WITH activos AS (
  SELECT ma.*
    FROM media_assets ma
    JOIN resources r ON r.id = ma.resource_id
    JOIN units u ON u.id = r.unit_id
    JOIN modules m ON m.id = u.module_id
    JOIN course_versions cv ON cv.id = m.course_version_id
    JOIN courses c ON c.id = cv.course_id
   WHERE c.slug LIKE 'e3b-%'
)
SELECT status, count(*) AS activos FROM activos GROUP BY status ORDER BY status;

\echo '2. Recursos con mas de un activo (efecto duplicado)'
SELECT resource_id, count(*) AS activos
  FROM media_assets
 GROUP BY resource_id
HAVING count(*) > 1;

\echo '3. Activos sin estado final (trabajo perdido o atascado)'
SELECT ma.id, ma.status, ma.processing_started_at
  FROM media_assets ma
  JOIN resources r ON r.id = ma.resource_id
  JOIN units u ON u.id = r.unit_id
  JOIN modules m ON m.id = u.module_id
  JOIN course_versions cv ON cv.id = m.course_version_id
  JOIN courses c ON c.id = cv.course_id
 WHERE c.slug LIKE 'e3b-%'
   AND ma.status NOT IN ('ready', 'failed');

\echo '4. Fallos diagnosticables'
SELECT failure_reason, count(*) AS activos
  FROM media_assets
 WHERE status = 'failed'
 GROUP BY failure_reason
 ORDER BY activos DESC;
