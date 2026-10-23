# Calidad de código, deuda técnica y retiro seguro (Entrega 3)

Los valores de SonarQube salen tal cual del pipeline (resumen de la corrida y
artefacto `sonarqube-evidencia`, archivo `resumen.md`). Las celdas que siguen
en `POR MEDIR` esperan una corrida que todavía no se ha hecho.

## 1. Alcance y método de diagnóstico

| Campo | Valor |
|---|---|
| Herramienta | SonarQube 10.7 Community (imagen `sonarqube:10.7-community`) y SonarScanner CLI 11.1 |
| Perfiles de calidad | Sonar way para Go y Sonar way para TypeScript (los de fábrica, sin reglas desactivadas) |
| Puerta de calidad | `Entrega 3`: duplicación <= 20 % y mantenibilidad C o mejor, sobre todo el código |
| Código analizado | `backend/` (Go) y `frontend/` (TypeScript/React). Fuera: pruebas, migraciones SQL, scripts de despliegue y de carga |
| Configuración | [sonar-project.properties](../../sonar-project.properties) |
| Pipeline | [.github/workflows/sonar.yml](../../.github/workflows/sonar.yml), en cada push y pull request |
| Script (local y CI) | [deploy/sonarqube/analizar.sh](../../deploy/sonarqube/analizar.sh) |
| Commit evaluado | `0c63963` |
| Corrida de GitHub Actions | [SonarQube #2](https://github.com/DES-SOLUCIONES-CLOUD/proyecto-1/actions/runs/39881777108) (en verde, puerta de calidad OK) |

### Cómo corre

El pipeline mide primero la cobertura del backend con PostgreSQL real
(`go test -coverprofile`) y después llama a `analizar.sh`, que tiene dos modos:

- **Con los secretos `SONAR_HOST_URL` y `SONAR_TOKEN`** analiza contra ese
  servidor (SonarQube propio o SonarCloud; este último pide también
  `SONAR_ORGANIZATION`). El panel queda publicado y guarda el historial.
- **Sin secretos** levanta SonarQube 10 dentro del runner, fija la clave del
  administrador, crea la puerta `Entrega 3` y analiza ahí. No depende de
  ninguna infraestructura externa.

En los dos casos el scanner espera el veredicto de la puerta
(`sonar.qualitygate.wait=true`) y el trabajo falla si no pasa. Al final se
descargan de la API las medidas, el estado de la puerta y los hallazgos
abiertos, y `deploy/sonarqube/resumen.py` los convierte en las tablas de este
documento. Quedan en el resumen de la corrida y en el artefacto
`sonarqube-evidencia`.

Para el panel de la sustentación se corre lo mismo en local:

```bash
bash deploy/sonarqube/analizar.sh
# Panel: http://localhost:9000/dashboard?id=mooc-plataforma
```

## 2. Medición inicial vs final

La medición inicial es la del commit anterior a las refactorizaciones
(`31d5af0`); la final, la de `0c63963`, primera corrida en verde del
pipeline.

| Métrica | Inicial (`31d5af0`) | Final (`0c63963`) | Umbral |
|---|---|---|---|
| Líneas de código | POR MEDIR | 17.422 | |
| Duplicación (%) | POR MEDIR | 0,4 | <= 20 % |
| Bloques duplicados | POR MEDIR | 6 | |
| Mantenibilidad | POR MEDIR | A | C o mejor |
| Deuda técnica (min) | POR MEDIR | 973 | |
| Ratio de deuda (%) | POR MEDIR | 0,2 | |
| Confiabilidad | POR MEDIR | A | |
| Seguridad | POR MEDIR | E | |
| Bugs | POR MEDIR | 0 | 0 |
| Vulnerabilidades | POR MEDIR | 1 | 0 |
| Code smells | POR MEDIR | 158 | |
| Security hotspots | POR MEDIR | 6 | |
| Cobertura (%) | POR MEDIR | 12,0 | |

La puerta `Entrega 3` pasa: `sqale_rating` = 1 (A, umbral: peor que 3) y
`duplicated_lines_density` = 0,4 (umbral: mayor que 20).

La nota E de Seguridad viene de una sola vulnerabilidad, `secrets:S6698`
(clave de PostgreSQL escrita en `backend/internal/config/config.go`). Se
corrigió después de esta medición (ver R4); la próxima corrida debe
confirmarlo. La cobertura es baja porque se calcula sobre todo el código y el
frontend no reporta cobertura (ver 4.2).

Para medir el inicial basta con correr el workflow a mano
(`workflow_dispatch`) sobre el commit `31d5af0`, o en local:
`git checkout 31d5af0 && bash deploy/sonarqube/analizar.sh`.

**Estimación previa, sin SonarQube.** Antes de tener el servidor se midió la
duplicación con un detector propio (ventanas de 10 líneas normalizadas, sin
pruebas ni migraciones). No es la cifra de Sonar, que cuenta tokens, pero
indica el orden de magnitud y dónde estaba concentrada: **7,6 % -> 2,7 %**.
Casi toda la duplicación inicial estaba en un solo archivo,
`frontend/lib/i18n.tsx` (unas 1.000 líneas repetidas).

## 3. Refactorizaciones realizadas

| # | Cambio | Archivos | Problema | Efecto |
|---|---|---|---|---|
| R1 | Catálogos de idioma a JSON | `frontend/lib/i18n.tsx` -> `frontend/lib/i18n/es.json`, `en.json`, `i18n.test.ts` | Los catálogos español e inglés eran dos objetos literales de 470 claves idénticas salvo por el texto: para el análisis de duplicación, dos bloques iguales de 540 líneas | `i18n.tsx` baja de 1.236 a 171 líneas. Los textos son datos y se pueden entregar a quien traduce sin tocar TypeScript. La comprobación de claves se conserva: TypeScript sigue detectando una clave sin traducir y la prueba nueva detecta una sobrante, un texto vacío o un marcador `{nombre}` perdido |
| R2 | Esqueleto común de las listas personales | `frontend/components/ListaPersonal.tsx`, `app/mis-cursos/page.tsx`, `app/mis-insignias/page.tsx` | Las dos páginas repetían la guardia de sesión, el encabezado y los estados de carga, vacío y error, y ya se habían separado: *Mis cursos* mostraba "Cargando..." junto al mensaje de error | Los estados se deciden en un solo componente. Cada página aporta solo qué carga y cómo pinta una fila. El HTML resultante es el mismo, así que las pruebas E2E no cambian |
| R3 | Retiro seguro de workers | `backend/cmd/worker/main.go`, `internal/platform/queue/queue.go`, `media/processor.go`, `documentos/convertidor.go`, `postgres/media_repo.go` | Ver sección 6: al detener un worker a mitad de un video, el trabajo volvía a la cola pero el siguiente worker lo descartaba como duplicado y el recurso quedaba atascado 30 minutos | El trabajo vuelve a la cola sin consumir reintento y otro worker lo termina. Cubierto con pruebas unitarias (cola) y de integración (PostgreSQL) |

| R4 | Sin clave de base de datos en el código | `backend/internal/config/config.go`, `backend/README.md` | `DATABASE_URL` tenía como valor por defecto una cadena de conexión con la clave de desarrollo (`secrets:S6698`, único hallazgo Bloqueante) | La variable pasa a ser obligatoria. Compose, el despliegue en GCP y el CI ya la definían, así que no cambia ningún entorno |
| R5 | Filas de las listas fuera del componente | `frontend/app/mis-cursos/page.tsx`, `app/mis-insignias/page.tsx` | R2 pasaba las filas como funciones que devuelven JSX definidas dentro del componente (`typescript:S6478`, 2 casos) | Las filas son funciones a nivel de módulo y ya no se recrean en cada render |

R1 y R2 atacan la duplicación medida; R3 es un defecto de confiabilidad
encontrado al preparar la prueba de retiro, y se trata como deuda pagada en
esta entrega porque sin él la demostración no se sostiene. R4 y R5 salen de
la primera corrida de SonarQube: el único Bloqueante y un Mayor que había
introducido R2.

## 4. Inventario priorizado de deuda técnica

### 4.1 Hallazgos de SonarQube

Tabla "Inventario por regla" de la corrida `0c63963`, agrupada por regla
porque veinte casos de la misma regla son una sola decisión de tratamiento.

Resumen por severidad: 159 hallazgos abiertos.

| Severidad | Cantidad |
|---|---|
| Bloqueante | 1 |
| Crítico | 43 |
| Mayor | 87 |
| Menor | 5 |
| Informativo | 23 |

| Severidad | Regla | Tipo | Casos | Ejemplo (archivo:línea) | Impacto técnico | Estado |
|---|---|---|---|---|---|---|
| Bloqueante | `secrets:S6698` | Vulnerabilidad | 1 | `backend/internal/config/config.go:100` | Clave de PostgreSQL en el código; cualquiera con acceso al repo la conoce | Resuelto (R4) |
| Crítico | `go:S3776` | Code smell | 16 | `backend/internal/platform/postgres/courses_repo.go:410` | Funciones con complejidad cognitiva hasta 30 (máximo 15): difíciles de leer y de probar | Aceptado |
| Crítico | `typescript:S2310` | Code smell | 13 | `frontend/lib/markdown.ts:105` | Se modifica el contador dentro del `for`; el recorrido es difícil de seguir | Aceptado |
| Crítico | `typescript:S3735` | Code smell | 5 | `frontend/app/admin/page.tsx:486` | Uso de `void` para descartar promesas; oculta errores no manejados | Aceptado |
| Crítico | `typescript:S3776` | Code smell | 3 | `frontend/lib/carga.ts:218` | Complejidad cognitiva 18 (máximo 15) en la carga por partes | Aceptado |
| Crítico | `go:S1192` | Code smell | 3 | `backend/internal/platform/httpserver/respond.go:41` | Literal `"Content-Type"` repetido; un cambio hay que hacerlo en varios sitios | Aceptado |
| Crítico | `typescript:S2004` | Code smell | 3 | `frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:107` | Funciones anidadas más de 4 niveles | Aceptado |
| Mayor | `typescript:S6759` | Code smell | 33 | `frontend/app/admin/page.tsx:403` | Props de componentes sin `readonly`; nada impide mutarlas por error | Aceptado |
| Mayor | `typescript:S6819` | Code smell | 30 | `frontend/app/cuenta/sesiones/page.tsx:76` | `role="status"` en lugar de `<output>`; accesibilidad menos consistente entre lectores de pantalla | Aceptado |
| Mayor | `typescript:S3358` | Code smell | 10 | `frontend/components/BlockEditor.tsx:233` | Ternarios anidados en el render | Aceptado |
| Mayor | `typescript:S6479` | Code smell | 6 | `frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:325` | Índice del arreglo como `key`; React puede confundir filas al reordenar preguntas | Aceptado |
| Mayor | `typescript:S6478` | Code smell | 2 | `frontend/app/mis-insignias/page.tsx:38` | Funciones que devuelven JSX definidas dentro del componente | Resuelto (R5) |
| Mayor | `typescript:S4624` | Code smell | 2 | `frontend/lib/api.ts:584` | Template literals anidados | Aceptado |
| Mayor | `go:S1479` | Code smell | 1 | `backend/internal/platform/httpserver/respond.go:74` | `switch` de 46 ramas para mapear errores a respuestas HTTP | Aceptado |
| Mayor | `docker:S7031` | Code smell | 1 | `backend/Dockerfile:6` | `RUN` consecutivos que se podrían unir (más capas en la imagen) | Aceptado |
| Mayor | `typescript:S1854` | Code smell | 1 | `frontend/app/admin/page.tsx:20` | Variable `locale` asignada y no usada | Aceptado |
| Mayor | `typescript:S6481` | Code smell | 1 | `frontend/lib/auth-context.tsx:39` | El valor del contexto de sesión cambia en cada render y re-renderiza a todos sus consumidores | Aceptado |
| Menor | `typescript:S6582` | Code smell | 2 | `frontend/lib/markdown.ts:58` | Se puede usar encadenamiento opcional | Aceptado |
| Menor | `typescript:S4084` | Code smell | 2 | `frontend/components/ReproductorHLS.tsx:127` | Elementos de video sin pista de subtítulos declarada | Aceptado |
| Menor | `docker:S7018` | Code smell | 1 | `backend/Dockerfile:27` | Paquetes de `apk add` sin orden alfabético | Aceptado |
| Informativo | `go:S1135` | Code smell | 22 | `backend/internal/app/courses/courses.go:28` | Comentarios TODO pendientes | Aceptado |
| Informativo | `typescript:S1135` | Code smell | 1 | `frontend/components/ReproductorHLS.tsx:138` | Comentario TODO pendiente | Aceptado |

### 4.2 Hallazgos de revisión manual

Deuda que una herramienta de análisis estático no ve porque es de
comportamiento o de arquitectura, no de forma del código.

| Severidad | Hallazgo | Archivo | Impacto técnico | Estado |
|---|---|---|---|---|
| Bloqueante | El worker detenido con SIGTERM dejaba el activo en `processing` con arrendamiento de 30 min; el reintento se descartaba como entrega duplicada | `media/processor.go`, `postgres/media_repo.go` | Cada scale-down del MIG de workers con un video en curso lo dejaba sin procesar | Resuelto (R3) |
| Crítico | `asynq.Server.Run` instalaba su propio manejador de SIGTERM, en paralelo con el de `main` | `cmd/worker/main.go` | Dos apagados simultáneos sin orden: no había forma de liberar el activo antes de devolver la tarea | Resuelto (R3) |
| Mayor | Si la VM del worker muere sin SIGTERM (SIGKILL, falla de hardware, preemption sin aviso), asynq reentrega la tarea al vencer su lease, pero el activo sigue arrendado 30 min y la entrega se descarta | `postgres/media_repo.go` (`Reclamar`) | Mismo atasco que el bloqueante, pero solo ante caídas abruptas. GCP manda ACPI shutdown (SIGTERM) al reducir un MIG, así que no ocurre en el scale-down normal | Aceptado temporalmente |
| Mayor | Duplicación de catálogos de idioma | `frontend/lib/i18n.tsx` | Mayor parte de la duplicación medida | Resuelto (R1) |
| Menor | Esqueleto repetido en *Mis cursos* y *Mis insignias* | `frontend/app/mis-*` | Estados de interfaz divergentes | Resuelto (R2) |
| Menor | Redis sin contraseña; el control de acceso es solo de red (firewall de la VPC) | `deploy/worker/docker-compose.yml` | Cualquier proceso dentro de la VPC con acceso al puerto 6379 puede leer o vaciar la cola | Aceptado temporalmente |
| Menor | `eslint-disable react-hooks/exhaustive-deps` en la carga de *Mis cursos* | `frontend/app/mis-cursos/page.tsx` | El efecto no se relanza si cambia el traductor; un mensaje de error puede quedar en el idioma anterior | Aceptado temporalmente |
| Menor | El frontend no reporta cobertura a SonarQube | `frontend/package.json` | La cobertura del panel es solo la del backend | Aceptado temporalmente |

## 5. Plan de tratamiento

### Resuelto en esta entrega

R1 a R5 (sección 3). De SonarQube: el único Bloqueante (`secrets:S6698`,
R4) y la regla Mayor `typescript:S6478` (R5).

### Aceptado temporalmente

| Hallazgo | Justificación | Tratamiento previsto | Responsable | Plazo |
|---|---|---|---|---|
| Atasco tras caída abrupta del worker | El scale-down del MIG manda SIGTERM, que ya está cubierto. La caída sin aviso es rara y se autocorrige: a los 30 min el arrendamiento vence | Cuando `Reclamar` encuentre el activo arrendado, devolver un error reintentable con espera igual al tiempo restante del arrendamiento, en lugar de descartar la entrega. Exige subir `MaxRetry` solo para ese caso, que hoy fija el enunciado en 3 | Equipo | Entrega 4 |
| Redis sin contraseña | La VM de Redis no tiene IP pública y el firewall solo admite el puerto 6379 desde las cuentas de servicio de la API y los workers | Añadir `REDIS_PASSWORD` a la configuración y pasarlo a `asynq.RedisClientOpt` y al cliente de idempotencia, con el secreto en Secret Manager | Equipo | Entrega 4 |
| `exhaustive-deps` desactivado | El efecto solo se perdería un cambio de idioma con un error ya visible en pantalla | Pasar la carga a `useTraductorEstable`, como el resto de páginas | Equipo | Entrega 4 |
| Sin cobertura del frontend | Las pruebas unitarias del frontend son pocas (Markdown e i18n); la lógica crítica está en el backend y en las E2E | Añadir `@vitest/coverage-v8`, generar `lcov.info` y declararlo en `sonar.javascript.lcov.reportPaths` | Equipo | Entrega 4 |
| Críticos de complejidad (`go:S3776`, `typescript:S3776`, `typescript:S2004`, 22 casos) | Son funciones que funcionan y están cubiertas por pruebas; partirlas sin necesidad funcional arriesga regresiones a días de la sustentación. La puerta de calidad pasa con mantenibilidad A | Partir primero las de mayor complejidad (`courses_repo.go`, `carga.ts`), una por commit y con sus pruebas | Equipo | Entrega 4 |
| Otros Críticos (`typescript:S2310`, `typescript:S3735`, `go:S1192`, 21 casos) | Estilo, no comportamiento: no hay bug asociado (Confiabilidad A, 0 bugs) | Corregir por archivo cuando se toque cada uno | Equipo | Entrega 4 |
| Mayores de React y accesibilidad (`S6759`, `S6819`, `S3358`, `S6479`, `S6481`, 80 casos) | Casi todos son `readonly` en props y `<output>` en lugar de `role="status"`: mecánicos y repartidos en muchos archivos. Las E2E de accesibilidad (axe) ya pasan | Aplicarlos por página. `S6479` (keys por índice) y `S6481` (contexto de sesión) van primero porque sí afectan al render | Equipo | Entrega 4 |
| Otros Mayores (`S4624`, `go:S1479`, `docker:S7031`, `S1854`, 5 casos) | Casos sueltos de estilo; el `switch` de 46 ramas es la tabla de errores HTTP y partirlo no la hace más clara | Quitar la variable sin uso y unir los `RUN` del Dockerfile al tocarlos; el `switch`, reevaluarlo si crece | Equipo | Entrega 4 |
| Menores e informativos (`S6582`, `S4084`, `S7018`, `S1135`, 28 casos) | Sin impacto en el funcionamiento. Los TODO marcan alcance opcional que no entró | Revisar los TODO al planear la entrega 4; el resto, al tocar cada archivo | Equipo | Entrega 4 |

## 6. Evidencia de retiro seguro de workers

### El defecto que había

Al detener un worker con `docker stop` (o al reducir el MIG de workers) a
mitad de una transcodificación pasaba esto:

1. asynq recibía SIGTERM, esperaba 8 s a que el trabajo terminara y, como un
   video no termina en 8 s, devolvía la tarea a Redis.
2. El activo seguía en la base como `processing`, con `processing_started_at`
   de hace unos segundos.
3. Otro worker tomaba la tarea; `Reclamar` veía el arrendamiento vigente
   (30 min) y la descartaba como entrega duplicada.
4. El recurso quedaba en "procesando" hasta que alguien volviera a subir el
   archivo: nadie reencolaba el trabajo al vencer el arrendamiento.

Además `srv.Run` instalaba su propio manejador de SIGTERM, que apagaba el
servidor en paralelo con el de `main`.

### La corrección

- `main` arranca la cola con `srv.Start` (sin manejador de señales propio) y
  ante SIGTERM apaga en tres pasos: deja de tomar trabajos (`srv.Stop`),
  cancela los trabajos en curso y espera a que terminen (`srv.Shutdown`).
- El middleware `queue.Retirable` cancela el contexto de cada trabajo con la
  causa `ErrRetiro`. FFmpeg y LibreOffice corren con `exec.CommandContext`,
  así que mueren al instante.
- El manejador ve `queue.Retirado(ctx)` y llama a `MediaRepo.Liberar`, que
  devuelve el activo a `queued` y borra el arrendamiento. No lo marca como
  fallido: el original está intacto.
- asynq recibe el error envuelto en `ErrRetiro`: `EsFallo` dice que no es un
  fallo (no consume ninguno de los 3 reintentos) y `EsperaAntesDeReintentar`
  lo devuelve a la cola sin backoff. Otro worker lo toma en unos segundos.
- `PlazoDeRetiro` (8 s) queda por debajo de los 10 s de `docker stop`, así que
  el proceso termina antes del SIGKILL.

### Procedimiento de la demostración

En local, con el compose del repositorio:

```bash
bash deploy/retiro-seguro/demo-local.sh
```

El script deja dos workers, espera a que se suba un video desde la web,
detiene con `docker stop` al worker que lo tomó cuando FFmpeg lleva unos
segundos trabajando, muestra los registros del retiro, sigue al otro worker
hasta `media: activo listo` y corre
[deploy/retiro-seguro/verificar.sql](../../deploy/retiro-seguro/verificar.sql).

Para la pantalla dividida del video, en otra terminal:

```bash
docker compose logs -f worker
```

En GCP, sobre el MIG de workers, el equivalente es detener el contenedor en
una de las VMs (`sudo docker stop mooc-worker-worker-1`) o eliminar la
instancia del grupo, que manda ACPI shutdown y con él SIGTERM.

### Registros esperados

Del worker retirado (formato JSON de `slog`, campos recortados):

```text
{"msg":"media: trabajo aceptado, empieza la transcodificación", ...}
{"msg":"worker: senal de apagado recibida, retiro seguro en curso","accion":"worker.retiro"}
{"msg":"media: worker en retiro, el activo vuelve a la cola", ...}
{"level":"WARN","msg":"worker en retiro: el trabajo vuelve a la cola sin consumir reintento","accion":"queue.task_requeued_on_shutdown", ...}
{"msg":"worker detenido"}
```

Del worker que retoma: `trabajo aceptado`, una línea `calidad transcodificada`
por calidad y `media: activo listo`.

Consulta de integridad: una sola fila por recurso, en `ready`, con
`hls_master_key`; las consultas de duplicados y de atascados, vacías.

### Evidencia de la corrida

| Elemento | Valor |
|---|---|
| Fecha y entorno | POR MEDIR |
| Tiempo de `docker stop` | POR MEDIR (debe ser < 10 s) |
| Registros del worker retirado | POR MEDIR (pegar) |
| Registros del worker que retoma | POR MEDIR (pegar) |
| Resultado de `verificar.sql` | POR MEDIR (pegar) |

### Pruebas automáticas que lo cubren

| Prueba | Qué acredita |
|---|---|
| `queue.TestRetirableCortaElTrabajoYMarcaElError` | Al retirarse, el trabajo en curso ve `Retirado(ctx)` y su error sale marcado como retiro |
| `queue.TestRetirableNoTocaUnTrabajoNormal` | Sin retiro, los errores pasan intactos |
| `queue.TestUnRetiroVuelveALaColaSinConsumirReintento` | Un retiro no cuenta como fallo y vuelve sin backoff |
| `queue.TestUnRetiroSeRegistraSinAlertar` | Un retiro en el último intento no manda el trabajo a la DLQ |
| `queue.TestElPlazoDeRetiroCabeEnElDeDocker` | El plazo de apagado queda por debajo de los 10 s de `docker stop` |
| `postgres.TestUnRetiroDevuelveElActivoParaQueOtroWorkerLoRetome` | Tras `Liberar`, otro worker puede reclamar el activo de inmediato |
| `postgres.TestUnRetiroTardioNoDeshaceUnActivoListo` | Un retiro que llega después de terminar no deshace el `ready` |
