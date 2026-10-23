# Calidad de código, deuda técnica y retiro seguro (Entrega 3)

Las celdas marcadas con `POR MEDIR` se llenan con la salida de la primera
corrida del pipeline de SonarQube (artefacto `sonarqube-evidencia`, archivo
`resumen.md`). No se escriben a mano: el valor que vale es el que mide la
herramienta sobre el commit de entrega.

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
| Commit evaluado | `POR MEDIR` |
| Corrida de GitHub Actions | `POR MEDIR` (enlace a la corrida en verde) |

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
(`31d5af0`); la final, la del commit de entrega.

| Métrica | Inicial (`31d5af0`) | Final | Umbral |
|---|---|---|---|
| Duplicación (%) | POR MEDIR | POR MEDIR | <= 20 % |
| Bloques duplicados | POR MEDIR | POR MEDIR | |
| Mantenibilidad | POR MEDIR | POR MEDIR | C o mejor |
| Deuda técnica (min) | POR MEDIR | POR MEDIR | |
| Confiabilidad | POR MEDIR | POR MEDIR | |
| Bugs | POR MEDIR | POR MEDIR | 0 |
| Vulnerabilidades | POR MEDIR | POR MEDIR | 0 |
| Code smells | POR MEDIR | POR MEDIR | |
| Cobertura backend (%) | POR MEDIR | POR MEDIR | |

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

R1 y R2 atacan la duplicación medida; R3 es un defecto de confiabilidad
encontrado al preparar la prueba de retiro, y se trata como deuda pagada en
esta entrega porque sin él la demostración no se sostiene.

## 4. Inventario priorizado de deuda técnica

### 4.1 Hallazgos de SonarQube

Se copia la tabla "Inventario por regla" de `resumen.md` (corrida final). Va
agrupada por regla porque veinte casos de la misma regla son una sola
decisión de tratamiento.

| Severidad | Regla | Tipo | Casos | Ejemplo (archivo:línea) | Impacto técnico |
|---|---|---|---|---|---|
| POR MEDIR | | | | | |

Resumen por severidad (corrida final):

| Severidad | Cantidad |
|---|---|
| Bloqueante | POR MEDIR |
| Crítico | POR MEDIR |
| Mayor | POR MEDIR |
| Menor | POR MEDIR |

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

R1, R2 y R3 (sección 3), más los hallazgos de SonarQube de severidad
Bloqueante y Crítico que aparezcan en la corrida final: `POR MEDIR`.

### Aceptado temporalmente

| Hallazgo | Justificación | Tratamiento previsto | Responsable | Plazo |
|---|---|---|---|---|
| Atasco tras caída abrupta del worker | El scale-down del MIG manda SIGTERM, que ya está cubierto. La caída sin aviso es rara y se autocorrige: a los 30 min el arrendamiento vence | Cuando `Reclamar` encuentre el activo arrendado, devolver un error reintentable con espera igual al tiempo restante del arrendamiento, en lugar de descartar la entrega. Exige subir `MaxRetry` solo para ese caso, que hoy fija el enunciado en 3 | Equipo | Entrega 4 |
| Redis sin contraseña | La VM de Redis no tiene IP pública y el firewall solo admite el puerto 6379 desde las cuentas de servicio de la API y los workers | Añadir `REDIS_PASSWORD` a la configuración y pasarlo a `asynq.RedisClientOpt` y al cliente de idempotencia, con el secreto en Secret Manager | Equipo | Entrega 4 |
| `exhaustive-deps` desactivado | El efecto solo se perdería un cambio de idioma con un error ya visible en pantalla | Pasar la carga a `useTraductorEstable`, como el resto de páginas | Equipo | Entrega 4 |
| Sin cobertura del frontend | Las pruebas unitarias del frontend son pocas (Markdown e i18n); la lógica crítica está en el backend y en las E2E | Añadir `@vitest/coverage-v8`, generar `lcov.info` y declararlo en `sonar.javascript.lcov.reportPaths` | Equipo | Entrega 4 |
| Hallazgos Menores de SonarQube | `POR MEDIR`: listar las reglas aceptadas con su motivo | | | |

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
