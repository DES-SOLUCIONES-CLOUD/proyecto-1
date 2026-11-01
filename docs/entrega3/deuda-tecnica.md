# Calidad de código, deuda técnica y retiro seguro (Entrega 3)

Primer diagnóstico formal de deuda técnica del proyecto. El reporte del commit
final y este inventario son la línea base de las entregas siguientes.

Los valores de SonarQube salen tal cual del pipeline. Las celdas en `POR MEDIR`
esperan una corrida que todavía no se ha hecho.

## 1. Alcance y método de diagnóstico

| Campo | Valor |
|---|---|
| Herramienta | SonarQube 10.7 Community (imagen `sonarqube:10.7-community`) y SonarScanner CLI 11.1 |
| Perfiles de calidad | Sonar way para Go y Sonar way para TypeScript (los de fábrica, sin reglas desactivadas) |
| Puerta de calidad | `Entrega 3`: duplicación <= 20 % y mantenibilidad C o mejor, sobre todo el código |
| Código analizado | API y workers en `backend/` (Go) y `frontend/` (TypeScript/React) |
| Exclusiones | Dependencias, salidas de build, pruebas y sus ayudas (`pgtest`), estáticos y un archivo generado por Next. Ningún código de aplicación queda fuera. Las migraciones SQL siguen en el alcance, pero SonarQube Community no trae analizador de SQL y están fuera del cálculo de duplicación porque no se editan después de aplicarse |
| Configuración | [sonar-project.properties](../../sonar-project.properties) |
| Pipeline | [.github/workflows/sonar.yml](../../.github/workflows/sonar.yml), en cada push y pull request |
| Script (local y CI) | [deploy/sonarqube/analizar.sh](../../deploy/sonarqube/analizar.sh) |
| Última medición del pipeline | `b023430`, [SonarQube #6](https://github.com/DES-SOLUCIONES-CLOUD/proyecto-1/actions/runs/39884217156), puerta de calidad OK |
| Medición previa al cierre | `4e1c008`, 2026-10-31, corrida local con `analizar.sh`, puerta de calidad OK. [Reporte](evidencias/sonar/resumen.md) |
| Línea base (commit `746f11d`) | 2026-11-01, [SonarQube #58](https://github.com/DES-SOLUCIONES-CLOUD/proyecto-1/actions/runs/41277280190) en verde. [Reporte exportado](evidencias/sonar/resumen.md), generado con `analizar.sh` sobre el mismo commit, puerta de calidad OK. Si después cambia el código, se repite la medición |

Además del análisis automático, el diagnóstico revisó a mano:

- El código de cola, retiro e idempotencia del worker, contrastado con el
  código fuente de asynq v0.26.0.
- Terraform, el arranque de las instancias y los compose de cada rol.
- Los scripts de carga y de recolección de métricas.
- Lo que el CI ejecuta y lo que omite.

`deploy/sonarqube/analizar.sh` funciona de dos formas:

- **Con `SONAR_HOST_URL` y `SONAR_TOKEN`** analiza contra ese servidor
  (SonarQube propio o SonarCloud, que pide también `SONAR_ORGANIZATION`).
- **Sin secretos** levanta SonarQube dentro del runner, crea la puerta
  `Entrega 3` y analiza ahí. Es como corre hoy el pipeline, así que el panel
  desaparece con el runner. Para mostrarlo se corre lo mismo en local:

```bash
bash deploy/sonarqube/analizar.sh
# Panel: http://localhost:9000/dashboard?id=mooc-plataforma
```

SonarQube agrega condiciones de código nuevo a toda puerta que se crea, y solo
las evalúa desde el segundo análisis. El script las quita porque los umbrales
de la entrega miden todo el código.

En los dos casos el scanner espera el veredicto de la puerta y el trabajo falla
si no pasa. Después se descargan las medidas, la puerta y los hallazgos
abiertos, y `deploy/sonarqube/resumen.py` genera `resumen.md`. El artefacto de
GitHub dura 30 días, así que el reporte de la línea base se versiona en
[evidencias/sonar/](evidencias/sonar/).

## 2. Medición

| Métrica | Inicial (`31d5af0`) | Primera corrida (`0c63963`) | Pipeline (`b023430`) | Previa al cierre (`4e1c008`) | Commit `746f11d` | Umbral |
|---|---|---|---|---|---|---|
| Líneas de código | 18.344 | 17.422 | 17.429 | 17.529 | 17.529 | |
| Duplicación (%) | 5,2 | 0,4 | 0,4 | 0,4 | 0,4 | <= 20 % |
| Bloques duplicados | 295 | 6 | 6 | 6 | 6 | |
| Mantenibilidad | A | A | A | A | A | C o mejor |
| Deuda técnica (min) | 963 | 973 | 963 | 958 | 958 | Registrar |
| Ratio de deuda (%) | 0,2 | 0,2 | 0,2 | 0,2 | 0,2 | |
| Confiabilidad | A | A | A | A | A | |
| Seguridad | E | E | A | A | A | |
| Bugs | 0 | 0 | 0 | 0 | 0 | |
| Vulnerabilidades | 1 | 1 | 0 | 0 | 0 | |
| Code smells | 156 | 158 | 156 | 155 | 155 | |
| Security hotspots | 6 | 6 | 6 | 6 | 6 | |
| Cobertura (%) | 11,8 | 12,0 | 12,1 | 30,6 | 30,6 | |
| Hallazgos Bloqueantes | 1 | 1 | 0 | 0 | 0 | |

Mediciones:

- **Inicial (`31d5af0`):** el commit anterior a las refactorizaciones, medido en
  la rama temporal `medicion-inicial`, que solo le agrega los archivos del
  análisis ([SonarQube #8](https://github.com/DES-SOLUCIONES-CLOUD/proyecto-1/actions/runs/39885940557)).
- **Primera corrida (`0c63963`):** con R1, R2 y R3. Dio el inventario por regla
  de la sección 4.
- **Pipeline (`b023430`):** con R4 y R5. Hallazgos abiertos: 156
  (0 Bloqueantes, 43 Críticos, 85 Mayores, 5 Menores, 23 Informativos).
- **Previa al cierre (`4e1c008`):** corrida local con R6 a R10. Hallazgos
  abiertos: 155 (0 Bloqueantes, 38 Críticos, 85 Mayores, 9 Menores,
  23 Informativos). No reemplaza al reporte del commit final.

**Interpretación.**

- **Deuda técnica:** 958 minutos, unas 16 horas de esfuerzo estimado, con un
  ratio de 0,2 %. Es la primera medición de referencia. Mide esfuerzo de
  corregir reglas de estilo y complejidad, no riesgo: los defectos más graves
  de este diagnóstico (DT-01, DT-02) no aparecen en ese número. Por eso esta
  cifra se lee junto con la sección 4.
- **Duplicación:** baja de 5,2 % a 0,4 % y los bloques de 295 a 6, por R1 y R2.
  La línea base ya cumplía el umbral, así que las refactorizaciones no fueron
  para pasar la puerta sino para bajar deuda concreta.
- **Seguridad:** pasa de E a A con R4, que quita la única vulnerabilidad
  (`secrets:S6698`).
- **Cobertura:** sube de 12,1 % a 30,6 % porque el análisis ya ejecuta las
  pruebas de integración de la API, que antes se omitían por falta de Redis.
  El aumento viene sobre todo de medir pruebas que ya existían. Sigue baja
  porque el frontend no reporta cobertura (DT-12).
- **Diferencia con el pipeline:** en `4e1c008` no aparece `typescript:S3735` y
  aparece `typescript:S6606`. La corrida local tiene las dependencias del
  frontend y, con ellas, información de tipos. `sonar.yml` ahora las instala,
  y la corrida del commit final debe confirmar que los dos resultados
  coinciden.

## 3. Correcciones realizadas durante este ejercicio

No hacen parte de la línea base final: se registran para distinguirlas de los
pendientes de la sección 4.

| # | Cambio | Problema | Efecto y verificación | Commit |
|---|---|---|---|---|
| R1 | Catálogos de idioma a JSON (`frontend/lib/i18n.tsx` -> `frontend/lib/i18n/es.json`, `en.json`) | Dos objetos literales de 470 claves idénticas salvo por el texto: dos bloques iguales de 540 líneas | `i18n.tsx` baja de 1.236 a 171 líneas. `i18n.test.ts` detecta claves sobrantes, textos vacíos y marcadores perdidos, y TypeScript detecta las claves sin traducir | `98a6bb8` |
| R2 | Esqueleto común de las listas (`frontend/components/ListaPersonal.tsx`) | *Mis cursos* y *Mis insignias* repetían la guardia de sesión y los estados de carga, vacío y error, y ya se habían separado | Los estados se deciden en un solo componente. El HTML es el mismo, así que las E2E no cambian | `98a6bb8` |
| R3 | Retiro seguro de workers | Al detener un worker a mitad de un video, el siguiente descartaba el trabajo como duplicado y el recurso quedaba atascado | El trabajo vuelve a la cola sin consumir reintento. Ver sección 6 | `98a6bb8` |
| R4 | Sin clave de base de datos en el código (`backend/internal/config/config.go`) | `DATABASE_URL` traía por defecto una cadena con la clave de desarrollo (`secrets:S6698`, único Bloqueante) | La variable es obligatoria. Compose, GCP y CI ya la definían. El hallazgo no aparece en `b023430` | `e07e872` |
| R5 | Filas de las listas fuera del componente | R2 pasaba funciones que devuelven JSX definidas dentro del componente (`typescript:S6478`, 2 casos) | Son funciones de módulo. El hallazgo no aparece en `b023430` | `9f04c2e` |
| R6 | Recuperación tras una caída abrupta del worker (`media/processor.go`, `documentos/convertidor.go`, `postgres/media_repo.go`, `queue/queue.go`) | Si el worker moría sin SIGTERM, la reentrega se daba por terminada, el trabajo aceptado se perdía y el recurso quedaba en `processing` para siempre | La entrega se aplaza hasta que venza el arrendamiento y entonces otro worker la toma. Pruebas en la sección 6, en verde contra PostgreSQL y Redis reales | `ca0760b` |
| R7 | Salidas por retiro sin devolver el activo | Un retiro entre `Reclamar` y la transcodificación dejaba el activo arrendado | Toda salida por retiro lo devuelve, y las escrituras finales no se cancelan | `ca0760b` |
| R8 | Registro falso en el último intento | El registro decía que un retiro en el último intento volvía a la cola, pero asynq lo archiva. Una prueba fijaba ese comportamiento falso | El registro alerta y la prueba refleja lo que hace asynq. Ver DT-11 | `ca0760b` |
| R9 | Alcance y evidencia del análisis | Las migraciones se excluían del análisis sin justificarlo, el pipeline omitía las pruebas con Redis, el script traía una clave por defecto y el reporte no daba todas las ubicaciones | Corregido en `sonar-project.properties`, `sonar.yml`, `analizar.sh` y `resumen.py` | `4e1c008` |
| R11 | Puerta de calidad que fallaba al repetir el análisis | SonarQube añade condiciones de código nuevo a la puerta. En CI no se veían porque cada corrida es un primer análisis, y en local el segundo daba `ERROR` con los umbrales cumplidos | `analizar.sh` deja solo duplicación y mantenibilidad. Un análisis repetido sobre `4e1c008` pasa con código de salida 0 | `fix: dejar solo los umbrales de la entrega en la puerta` |
| R10 | Evidencia del retiro en GCP (`deploy/retiro-seguro/`) | La demo solo existía contra el PostgreSQL local, afirmaba "sin SIGKILL" sin comprobarlo y su consulta de duplicados no podía fallar por el índice único | `demo-gcp.sh` genera la evidencia contra Cloud SQL y `demo-local.sh` revisa el código de salida. Falta ejecutarla en GCP (sección 6) | `124b7ef` |

## 4. Inventario priorizado

### Criterio de prioridad

| Prioridad | Significado |
|---|---|
| P0 | Afecta un requisito obligatorio de esta entrega. Registrarlo no lo subsana: se cierra antes de la entrega |
| P1 | Riesgo real de pérdida de datos, seguridad o fallo en operación |
| P2 | Frena el mantenimiento o la verificación, sin fallo inmediato |
| P3 | Estilo o limpieza. Se atiende al tocar el archivo |

Dentro de cada prioridad se atiende primero lo que desbloquea a otros ítems.

### 4.1 Arquitectura, infraestructura, pruebas y operación

| ID y categoría | Descripción y ubicación | Evidencia | Impacto | Prioridad y justificación | Tratamiento y verificación | Responsable y plazo | Estado y decisión |
|---|---|---|---|---|---|---|---|
| DT-01 Arquitectura | Los workers escalan por CPU y no por demanda de cola. `deploy/gcp/terraform/computo.tf` | Autoscaler con `cpu_utilization` y FFmpeg sin límite de hilos | Un solo video puede escalar con la cola vacía, y el retiro no sabe qué instancia trabaja. Más costo y trabajo repetido | P0. El enunciado pide una señal de demanda de procesamiento | Publicar pendientes + activos por worker como métrica propia y usarla en el autoscaler. Se cierra si 3B muestra escalamiento por esa señal | Infraestructura, Entrega 3 | En tratamiento |
| DT-02 Operación | Registros en la VM y sin identificador de instancia. `deploy/*/docker-compose.yml`, `backend/internal/platform/httpserver` | Driver `json-file`, sin configuración del Ops Agent para contenedores, sin campo de instancia | Los registros se borran con la instancia y no se puede demostrar el reparto entre réplicas | P0. Sin esto no hay evidencia de balanceo ni de retiro real | Enviar los registros a Cloud Logging y añadir el identificador de instancia. Se cierra si los registros de una instancia borrada siguen consultables | Infraestructura, Entrega 3 | En tratamiento |
| DT-03 Infraestructura | Plantillas con etiqueta móvil `desplegada`. `deploy/gcp/terraform/variables.tf`, `deploy/gcp/desplegar-vm.sh` | La plantilla no nombra el commit y la etiqueta se mueve antes de reemplazar | Un reinicio o una instancia nueva pueden correr otra versión que el resto del grupo | P0. El enunciado pide versión identificable y la misma en cada grupo y corrida | Fijar el commit o el digest en la plantilla. Se cierra si `instance-templates describe` muestra la versión | Infraestructura, Entrega 3 | En tratamiento |
| DT-04 Infraestructura | Inicialización más larga que el periodo del autoscaler. `computo.tf`, `arranque.sh.tftpl` | `mig_cooldown` = 120 s frente a 3-4 min estimados, con Docker instalado al nacer | La CPU del arranque cuenta en las decisiones, y una caída de los repositorios de Docker impide escalar | P0. El tiempo de arranque es un parámetro obligatorio y sigue sin medirse | Medir el arranque, ajustar el periodo o usar imagen con Docker preinstalado. Se cierra con el tiempo medido en el informe | Infraestructura, Entrega 3 | En tratamiento |
| DT-05 Infraestructura | `/healthz` responde 200 sin mirar dependencias, y los workers no tienen health check. `backend/internal/platform/httpserver/health.go`, `computo.tf` | Manejador estático y grupo de workers sin autohealing | Una API sin base sigue recibiendo tráfico, y un worker que no arrancó cuenta como capacidad | P0 para la API: el enunciado pide reflejar la capacidad de atender. P1 para workers | Separar disponibilidad con ping corto a la base, y exponer salud del worker. Se cierra al probarlo con la base inalcanzable | Infraestructura, Entrega 3 | En tratamiento |
| DT-06 Infraestructura | Cada réplica migra al arrancar y el paso explícito corre después. `backend/cmd/api/main.go`, `.github/workflows/desplegar-gcp.yml` | `postgres.Migrate` en el arranque, con cerrojo consultivo | Una migración fallida se ve como réplicas que no arrancan, y `migrar.sh` llega tarde | P0. El enunciado pide migraciones controladas | Desactivar la migración en los MIG y migrar antes de reemplazar. Se cierra si una réplica nueva no ejecuta migraciones | Infraestructura, Entrega 3 | En tratamiento |
| DT-07 Pruebas | La medición de las corridas sigue incompleta. `load/correr.sh`, `load/cola-en-redis.sh` | `8163c1a` añadió series de Monitoring, tamaño de los MIG y serie de la cola. Falta: `k6 run` sin `--out` no deja latencia en el tiempo, y `docker ps -qf name=redis` también coincide con el contenedor de Mailpit | No se podrían correlacionar latencias con el escalamiento, y la lectura de la cola puede fallar | P0. Bloquea el informe de capacidad | Exportar las métricas de k6 y usar el nombre exacto del contenedor. Se cierra con una corrida corta con series reales | Pruebas de carga, Entrega 3 | En tratamiento |
| DT-08 Pruebas | 3B sigue encolando en reposo. `load/escenario3b.js` | `VUS_REPOSO=1` sigue subiendo videos en bucle con `sleep(0.2)`. 3A y el reposo final de 15 min ya se corrigieron en `8163c1a` | La cola no drena y no se observaría la reducción automática, que es obligatoria | P0 | Demanda en 0 durante el drenaje. Se cierra al observar el ciclo completo | Pruebas de carga, Entrega 3 | En tratamiento |
| DT-20 Pruebas | El pipeline CI lleva en rojo desde al menos el 27 de septiembre. `.github/workflows/ci.yml` | Las últimas 80 corridas consultadas no incluyen ninguna exitosa. En [CI #117](https://github.com/DES-SOLUCIONES-CLOUD/proyecto-1/actions/runs/41217929216) fallaba la descarga de `minio`: `quay.io/minio` ya no admite descargas anónimas. Al corregirlo, [CI #126](https://github.com/DES-SOLUCIONES-CLOUD/proyecto-1/actions/runs/41269741328) pasó las E2E y mostró otros tres fallos: Postman recibía 429 porque corría tras la prueba que agota el limitador, la credencial firmada daba 503 por falta de `BADGE_SIGNING_KEY`, y gitleaks marcaba 146 identificadores aleatorios de la exportación de Sonar | Las pruebas no bloqueaban regresiones. No afecta a GCP, que usa Cloud Storage | P0. El enunciado exige mantener operativa la automatización existente | `pgsty` con versión fija, espera de 65 s antes de Postman, clave de firma de un solo uso en CI y evidencia sin `key`, `hash` ni `author`. Se cierra con CI en verde en el commit final | Calidad, Entrega 3 | En tratamiento: las E2E ya pasan, falta confirmar CI en verde |
| DT-09 Pruebas | Las pruebas de integración de la API no corren en `ci.yml`. `.github/workflows/ci.yml` | Define `REDIS_ADDR`, y `entorno_test.go` lee `TEST_REDIS_ADDR` | Un cambio puede romper la API con el CI en verde. Con la variable correcta pasan en local | P1. Es un cambio de una línea y sostiene las demás correcciones | Definir `TEST_REDIS_ADDR` en `ci.yml`. Se cierra si el registro del CI muestra esas pruebas ejecutadas | Calidad, Entrega 3 | Pendiente |
| DT-10 Seguridad | Hotspots sin revisión registrada. Sección 4.3 | 6 `security hotspots` en todas las mediciones | Una exposición real podría quedar sin atender. No afecta la nota A, que solo mira vulnerabilidades | P1. Es revisión, no refactorización | Revisar cada uno. Se cierra con los 6 clasificados en la sección 4.3 | Calidad, Entrega 3 | Resuelto: 4 sin riesgo y 2 confirmados, que pasan a DT-19 |
| DT-19 Seguridad | Todos los contenedores corren como root. `backend/Dockerfile`, `frontend/Dockerfile` | Ninguna etapa define `USER`. Sonar lo marca en la última etapa de cada archivo | El worker procesa con FFmpeg y LibreOffice archivos subidos por usuarios: una vulnerabilidad en ellos daría root dentro del contenedor. Lo limitan la VM sin IP externa y los permisos de su cuenta de servicio | P1. Es entrada no confiable sobre software complejo, y exige probar los permisos del worker | Crear un usuario sin privilegios y definir `USER` en cada imagen. Se cierra si `docker exec <contenedor> id` no devuelve root y las demos y E2E siguen en verde | Calidad, Entrega 4 | Aplazado: cambiar permisos del worker a días de las pruebas puede romper las conversiones |
| DT-11 Código | Un retiro en el último intento va a la DLQ. Comportamiento de asynq v0.26.0, `backend/internal/platform/queue/queue.go` | `handleFailedMessage` compara el contador antes de consultar `IsFailure` | El trabajo no se pierde, pero queda archivado hasta relanzarlo. Solo ocurre tras gastar todos los reintentos | P2. Es raro, alerta y se recupera | Relanzar desde la DLQ. Si se repite, llevar la cuenta de fallos fuera de asynq | Calidad, Entrega 4 | Aceptado temporalmente: emite alerta y es recuperable |
| DT-12 Pruebas | El frontend no reporta cobertura. `frontend/package.json` | `sonar.javascript.lcov.reportPaths` sin definir; cobertura total 30,6 % | El panel subestima lo probado y la lógica de la interfaz no tiene medida | P2 | Añadir `@vitest/coverage-v8` y declarar `lcov.info`. Se cierra si el panel muestra cobertura del frontend | Frontend, Entrega 4 | Aceptado temporalmente: las E2E cubren los flujos |
| DT-13 Arquitectura | Puntos únicos de falla: VM de Redis, Cloud SQL zonal y todo en una zona. `computo.tf`, `basedatos.tf` | Una sola VM con AOF sin respaldo externo, `availability_type = "ZONAL"` | Una caída detiene la cola o la API. La pérdida de Redis cubriría hasta 1 s de escrituras y, sin disco, la cola entera | P2. El enunciado no exige alta disponibilidad | Evaluar un servicio administrado y respaldos del AOF. Se cierra con una prueba de restauración | Infraestructura, Entrega 4 | Aceptado temporalmente: fuera del alcance exigido |
| DT-14 Seguridad | Redis sin contraseña. `deploy/redis/docker-compose.yml` | Comentario del compose y cliente sin credenciales | Cualquier proceso con acceso al puerto puede leer o vaciar la cola | P2. La VM no tiene IP externa y el firewall solo admite API y workers | Añadir `REDIS_PASSWORD` desde Secret Manager a asynq y al cliente de Redis. Se cierra si una conexión sin clave falla | Calidad, Entrega 4 | Aceptado temporalmente |
| DT-15 Seguridad | Sin antivirus con firmas en GCP. `deploy/api/docker-compose.yml` | `CLAMAV_ADDR: ""`: solo opera el motor integrado | Un archivo malicioso sin patrón conocido pasa el escaneo | P2. El tamaño de las VM no admite clamd | Desplegar clamd aparte. Se cierra al detectar un archivo de prueba en GCP | Infraestructura, Entrega 4 | Aceptado temporalmente |
| DT-16 Operación | Conexiones del balanceador contra Next. `deploy/api/docker-compose.yml` | Next no tiene el keepalive configurado por encima de los 600 s del balanceador | Posibles 502 intermitentes en el frontend | P2. Riesgo sin observar todavía | Subir el keepalive. Se cierra sin ese error en los registros del balanceador durante una corrida | Infraestructura, Entrega 3 | Pendiente de verificar |
| DT-17 Infraestructura | MinIO depende de un fork comunitario. `docker-compose.yml` | `pgsty/minio` y `pgsty/mc` reemplazan las imágenes oficiales, que ya no admiten descarga anónima. Las etiquetas quedaron fijas | El proyecto confía en un tercero para local y CI. No afecta a GCP, que usa Cloud Storage | P3. Usa solo datos de prueba | Evaluar un almacén S3 mantenido, como Garage o SeaweedFS. Se cierra al reemplazarlo con las E2E en verde | Calidad, Entrega 4 | Aceptado temporalmente: es la opción con menos cambios |
| DT-18 Código | `eslint-disable react-hooks/exhaustive-deps` en *Mis cursos*. `frontend/app/mis-cursos/page.tsx` | Comentario en el archivo | Un error ya visible puede quedar en el idioma anterior | P3 | Pasar la carga a `useTraductorEstable` | Frontend, Entrega 4 | Aceptado temporalmente |

### 4.2 Hallazgos de SonarQube

Tabla por regla de la medición previa al cierre (`4e1c008`), porque los casos
de una misma regla son una sola decisión de tratamiento. Cada caso abierto de
severidad Mayor o superior, con archivo y línea, está en la sección
*Ubicaciones* del [reporte](evidencias/sonar/resumen.md). Esta tabla se revisa
contra el reporte del commit final.

| ID y categoría | Regla, severidad y casos | Ejemplo | Impacto | Prioridad y justificación | Tratamiento y verificación | Responsable y plazo | Estado y decisión |
|---|---|---|---|---|---|---|---|
| DT-S01 Código | `go:S3776`, Crítico, 16 | `backend/internal/platform/postgres/courses_repo.go:410` | Complejidad hasta 30 frente a 15: difícil de leer y de probar, y la cobertura de `postgres` es baja | P2. Es donde se concentra el riesgo de regresión | Ver Plan C1 | Calidad, Entrega 4 | Pendiente: partirlas a días del cierre arriesga regresiones |
| DT-S02 Código | `typescript:S2310`, Crítico, 13 | `frontend/lib/markdown.ts:105` | Contador modificado dentro del `for`: recorrido difícil de seguir | P3. El Markdown tiene pruebas de ida y vuelta que frenan regresiones | Ver Plan C2 | Frontend, Entrega 4 | Pendiente |
| DT-S03 Código | `typescript:S3735`, Crítico, 5 en `b023430` y 0 en `4e1c008` | `frontend/app/admin/page.tsx:486` | `void` descarta promesas. Solo apareció en el pipeline, que analizaba sin dependencias del frontend | P2. Hay que confirmar que no vuelva con el nuevo pipeline | Comparar la corrida del commit final. Si reaparece, revisar cada promesa descartada y mostrar el error en la interfaz | Calidad, Entrega 3 | En tratamiento: no aparece en la corrida local |
| DT-S04 Código | `typescript:S3776`, Crítico, 3 | `frontend/lib/carga.ts:218` | Complejidad 18 en la carga por partes, un flujo central | P2 | Ver Plan C1 | Frontend, Entrega 4 | Pendiente |
| DT-S05 Código | `go:S1192`, Crítico, 3 | `backend/internal/platform/httpserver/respond.go:41` | Literal repetido: un cambio toca varios sitios | P3 | Ver Plan C2 | Calidad, Entrega 4 | Pendiente |
| DT-S06 Código | `typescript:S2004`, Crítico, 3 | `frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:107` | Más de 4 niveles de funciones anidadas | P2 | Ver Plan C1 | Frontend, Entrega 4 | Pendiente |
| DT-S07 Código | `typescript:S6759`, Mayor, 33 | `frontend/app/admin/page.tsx:403` | Props sin `readonly` | P3. Mecánico | Aplicar por página. Regla en 0 | Frontend, Entrega 4 | Aplazado: sin efecto en ejecución |
| DT-S08 Código | `typescript:S6819`, Mayor, 30 | `frontend/app/cuenta/sesiones/page.tsx:76` | `role="status"` en lugar de `<output>` | P3. Las pruebas axe pasan | Aplicar por página. Regla en 0 y axe en verde | Frontend, Entrega 4 | Aplazado: sin incumplimiento WCAG detectado |
| DT-S09 Código | `typescript:S3358`, Mayor, 10 | `frontend/components/BlockEditor.tsx:233` | Ternarios anidados en el render | P3 | Extraer a variables. Regla en 0 | Frontend, Entrega 4 | Aplazado: solo legibilidad |
| DT-S10 Código | `typescript:S6479`, Mayor, 6 | `frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:325` | Índice como `key`: React puede confundir filas al reordenar preguntas | P2. Afecta el comportamiento | Usar identificadores estables. Regla en 0 | Frontend, Entrega 4 | Aplazado: sin fallo observado en E2E |
| DT-S11 Código | `typescript:S4624`, Mayor, 2 | `frontend/lib/api.ts:584` | Template literals anidados | P3 | Extraer a variables. Regla en 0 | Frontend, Entrega 4 | Aplazado: solo legibilidad |
| DT-S12 Código | `go:S1479`, Mayor, 1 | `backend/internal/platform/httpserver/respond.go:74` | `switch` de 46 ramas | P3 | Reevaluar si crece | Calidad, Entrega 4 | Aceptado: es una tabla de errores y partirla no la aclara |
| DT-S13 Infraestructura | `docker:S7031`, Mayor, 1 | `backend/Dockerfile:6` | `RUN` consecutivos: más capas | P3 | Unir los `RUN`. Regla en 0 | Calidad, Entrega 4 | Aplazado: sin efecto funcional |
| DT-S14 Código | `typescript:S1854`, Mayor, 1 | `frontend/app/admin/page.tsx:20` | Variable `locale` sin usar | P3 | Quitarla. Regla en 0 | Frontend, Entrega 4 | Aplazado: sin efecto funcional |
| DT-S15 Código | `typescript:S6481`, Mayor, 1 | `frontend/lib/auth-context.tsx:39` | El contexto de sesión cambia en cada render y re-renderiza a sus consumidores | P2. Afecta a toda la interfaz | Memoizar el valor. Regla en 0 | Frontend, Entrega 4 | Aplazado: sin problema de desempeño observado |
| DT-S16 Código | `typescript:S6582`, Menor, 2 | `frontend/app/page.tsx:190` | Se puede usar encadenamiento opcional | P3 | Al tocar el archivo | Frontend, Entrega 4 | Aceptado |
| DT-S17 Código | `typescript:S4084`, Menor, 2 | `frontend/components/ReproductorHLS.tsx:127` | Video sin pista de subtítulos declarada | P3 | Al tocar el archivo | Frontend, Entrega 4 | Aceptado |
| DT-S18 Infraestructura | `docker:S7018`, Menor, 1 | `backend/Dockerfile:27` | Paquetes sin orden alfabético | P3 | Al tocar el archivo | Calidad, Entrega 4 | Aceptado |
| DT-S19 Código | `go:S1135`, Informativo, 22 | `backend/internal/platform/postgres/exportacion_repo.go:12` | Comentarios TODO | P3 | Revisarlos al planear la Entrega 4 | Calidad, Entrega 4 | Aceptado: marcan alcance opcional |
| DT-S20 Código | `typescript:S1135`, Informativo, 1 | `frontend/components/ReproductorHLS.tsx:138` | Comentario TODO | P3 | Revisarlo al planear la Entrega 4 | Frontend, Entrega 4 | Aceptado |
| DT-S21 Código | `typescript:S6606`, Menor, 4 | `frontend/components/BlockEditor.tsx:174` | `\|\|` en lugar de `??`: un valor vacío o 0 se trataría como ausente | P3 | Revisar cada caso al tocar el archivo | Frontend, Entrega 4 | Aceptado |

### 4.3 Revisión de security hotspots

Revisión manual de los 6 hotspots del panel. Un hotspot no es una vulnerabilidad
confirmada: pide a una persona decidir si el código es seguro en su contexto.

| Ubicación | Regla y mensaje | Prioridad de la herramienta | Decisión | Justificación |
|---|---|---|---|---|
| `backend/Dockerfile:53` | La imagen corre como root | Media | Riesgo confirmado | Se trata en DT-19. Aplica a todas las imágenes del backend, no solo a esta etapa |
| `frontend/Dockerfile:21` | La imagen corre como root | Media | Riesgo confirmado | Se trata en DT-19 |
| `backend/Dockerfile:5` | `COPY . .` recursivo | Media | Sin riesgo en la imagen final | Es la etapa de compilación: las imágenes finales solo copian binarios. El directorio no tiene `.dockerignore`, así que conviene añadirlo como limpieza |
| `frontend/Dockerfile:13` | `COPY . .` recursivo | Media | Sin riesgo | Es la etapa de compilación y `frontend/.dockerignore` excluye `.env` y `.env.*` |
| `frontend/lib/markdown.ts:45` | `Math.random` | Media | Sin riesgo | Solo diferencia bloques del editor dentro de una sesión. No protege nada |
| `frontend/Dockerfile:8` | `npm ci` sin `--ignore-scripts` | Baja | Sin riesgo aceptable | Corre en construcción, fuera de las VM, con versiones fijadas por el lockfile |

## 5. Plan de tratamiento

### Antes del cierre de esta entrega

Orden por dependencias: la medición y la evidencia dependen de la versión y de
los registros.

1. DT-03 y DT-06: versión fija y migración controlada.
2. DT-01, DT-02, DT-04 y DT-05: señal, registros, arranque y salud.
3. DT-07 y DT-08: medición y escenarios, antes de cualquier corrida evaluada.
4. DT-20, DT-09 y DT-S03: CI en verde, pruebas de integración y confirmación
   del nuevo pipeline de SonarQube.
5. Congelar el código, correr SonarQube y versionar el reporte como línea base.

### Hallazgos Críticos

Ninguno se resuelve en esta entrega: los 38 de `4e1c008` son de mantenibilidad,
con Confiabilidad A y 0 bugs. Se aplazan porque tocar funciones centrales a días de
las pruebas de carga arriesga más de lo que corrige. Cada plan se verifica con
SonarQube en la corrida de cierre de la Entrega 4.

| Plan | Hallazgos | Pasos | Responsable | Plazo |
|---|---|---|---|---|
| C1 | DT-S01, DT-S04, DT-S06 (22 casos) | 1. Ordenar por complejidad. 2. Añadir pruebas de caracterización a `courses_repo.go` y `carga.ts`. 3. Partir una función por commit, con las pruebas en verde. 4. Repetir hasta que la regla quede en 0 | Calidad (Go) y Frontend (TypeScript) | Primera semana de la Entrega 4 |
| C2 | DT-S02, DT-S05 (16 casos) | 1. Extraer constantes en Go. 2. Reescribir los recorridos con las pruebas de ida y vuelta como red de seguridad. 3. Confirmar que las 29 pruebas siguen en verde | Calidad (Go) y Frontend (TypeScript) | Segunda semana de la Entrega 4 |

## 6. Evidencia de retiro seguro de workers

### El defecto que había

Al detener un worker con `docker stop` a mitad de una transcodificación:

1. asynq recibía SIGTERM, esperaba 8 s y devolvía la tarea a Redis.
2. El activo seguía en `processing`, con el arrendamiento de 30 min vigente.
3. Otro worker tomaba la tarea, veía el arrendamiento y la daba por duplicada.
4. El recurso quedaba en "procesando" hasta volver a subir el archivo, porque
   nadie reencolaba el trabajo al vencer el arrendamiento.

Además, `srv.Run` instalaba su propio manejador de SIGTERM, que apagaba el
servidor en paralelo con el de `main`. Una caída sin SIGTERM producía el mismo
atasco. R3 corrigió el primer caso y R6 el segundo.

### La corrección

- **Retiro con aviso (SIGTERM).** `main` deja de tomar trabajos (`srv.Stop`),
  cancela los que están en curso con la causa `ErrRetiro` y espera a que
  terminen (`srv.Shutdown`). FFmpeg y LibreOffice mueren con el contexto. El
  activo vuelve a `queued` con `Liberar` y la tarea vuelve a la cola sin
  backoff ni gasto de reintento.
- **El trabajo se reinicia.** Otro worker lo toma desde el original, que sigue
  intacto. No se retoma el punto donde iba: se conserva el trabajo aceptado, no
  su avance.
- **Caída sin aviso (SIGKILL, fallo de la VM).** asynq reentrega la tarea al
  vencer su lease. Si el activo sigue arrendado, el manejador devuelve
  `queue.Arrendado` y la entrega se aplaza hasta que venza, sin gastar
  reintento. Entonces, si el activo está listo se descarta, y si no, se toma.
  El peor caso son unos 30 minutos en `processing`.
- **Tiempos.** `PlazoDeRetiro` (8 s) queda por debajo de los 10 s de
  `docker stop`.

### Procedimiento

La evidencia evaluada sale de GCP con Cloud SQL. `demo-local.sh` usa el
PostgreSQL de Compose y solo sirve para ensayar.

```bash
bash deploy/retiro-seguro/demo-gcp.sh preparar     # mig-workers con minimo 2
bash deploy/retiro-seguro/demo-gcp.sh contenedor   # docker stop con un video en curso
bash deploy/retiro-seguro/demo-gcp.sh instancia    # el MIG borra la instancia
bash deploy/retiro-seguro/demo-gcp.sh caida        # docker kill (tarda hasta 40 min)
bash deploy/retiro-seguro/demo-gcp.sh restaurar    # vuelve al minimo de 1
```

Corre desde Cloud Shell y solo necesita `gcloud`: no lee el estado de Terraform,
que contiene secretos. Para seguir los registros en otra terminal se usa
`demo-gcp.sh registros`. El worker detenido no vuelve a arrancar hasta el final,
para que el trabajo lo termine otro.

Cada modo espera a que se suba un video desde la web. Deja los registros, la
consulta y la cola en `docs/entrega3/evidencias/retiro-seguro/<modo>-<fecha>/`,
y falla si el worker termina con SIGKILL en un retiro limpio o si el activo no
termina exactamente una vez.

[verificar.sql](../../deploy/retiro-seguro/verificar.sql) revisa el activo, el
recurso y los trabajos sin terminar. Que no haya dos filas por recurso no prueba
nada, porque lo garantiza un índice único. Lo que demuestra que no hubo efectos
duplicados es una sola línea `media: activo listo` para ese activo.

Esta comprobación complementa la reducción por autoscaling de 3B, no la
reemplaza.

### Registros esperados

Del worker retirado (JSON de `slog`, campos recortados):

```text
{"msg":"media: trabajo aceptado, empieza la transcodificación", ...}
{"msg":"worker: senal de apagado recibida, retiro seguro en curso","accion":"worker.retiro"}
{"msg":"media: worker en retiro, el activo vuelve a la cola", ...}
{"level":"WARN","msg":"worker en retiro: el trabajo vuelve a la cola sin consumir reintento","accion":"queue.task_requeued_on_shutdown", ...}
{"msg":"worker detenido"}
```

Del worker que retoma: `trabajo aceptado`, una línea `calidad transcodificada`
por calidad y `media: activo listo`. Tras una caída aparece antes la acción
`queue.task_postponed_by_lease`.

### Evidencia de las corridas

| Elemento | `contenedor` | `instancia` | `caida` |
|---|---|---|---|
| Fecha y commit | POR MEDIR | POR MEDIR | POR MEDIR |
| Tiempo y código de salida | POR MEDIR | POR MEDIR | POR MEDIR |
| Carpeta de evidencia | POR MEDIR | POR MEDIR | POR MEDIR |
| Tiempo hasta `ready` | POR MEDIR | POR MEDIR | POR MEDIR |
| `activo listo` del activo | POR MEDIR | POR MEDIR | POR MEDIR |
| Cola al final | POR MEDIR | POR MEDIR | POR MEDIR |

### Pruebas automáticas que lo cubren

| Prueba | Qué acredita |
|---|---|
| `queue.TestRetirableCortaElTrabajoYMarcaElError` | Al retirarse, el trabajo en curso ve `Retirado(ctx)` y su error sale marcado como retiro |
| `queue.TestRetirableNoTocaUnTrabajoNormal` | Sin retiro, los errores pasan intactos |
| `queue.TestUnRetiroVuelveALaColaSinConsumirReintento` | Un retiro no cuenta como fallo y vuelve sin backoff |
| `queue.TestUnRetiroSeRegistraSinAlertar` | Un retiro con intentos disponibles no alerta |
| `queue.TestUnRetiroEnElUltimoIntentoAlerta` | Un retiro en el último intento sí alerta, porque asynq lo archiva |
| `queue.TestElPlazoDeRetiroCabeEnElDeDocker` | El plazo de apagado queda por debajo de los 10 s de `docker stop` |
| `queue.TestUnActivoArrendadoSeAplazaSinConsumirReintento` | Una entrega aplazada espera lo que falta del arrendamiento |
| `queue.TestUnAplazamientoSeRegistraSinAlertar` | Aplazar deja rastro y no alerta |
| `queue.TestUnAplazamientoNoGastaReintentosEnAsynq` | Contra Redis real, asynq vuelve a entregar el trabajo con el contador intacto |
| `postgres.TestUnRetiroDevuelveElActivoParaQueOtroWorkerLoRetome` | Tras `Liberar`, otro worker puede reclamar el activo de inmediato |
| `postgres.TestUnRetiroTardioNoDeshaceUnActivoListo` | Un retiro que llega después de terminar no deshace el `ready` |
| `postgres.TestLaEsperaDeArrendamientoDiceCuandoReclamar` | La espera calculada alcanza para volver a reclamar |
| `postgres.TestLaEntregaTrasUnaCaidaAbruptaSeAplazaEnLugarDePerderse` | Tras una caída, ni el video ni la presentación se dan por terminados |
| `postgres.TestUnaEntregaDuplicadaDeUnActivoListoSeDescarta` | Una entrega duplicada de un activo listo sigue sin reprocesarse |
