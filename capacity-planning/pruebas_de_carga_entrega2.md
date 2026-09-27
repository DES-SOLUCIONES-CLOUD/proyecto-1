# Pruebas de carga — Entrega 2

Plantilla del informe. Las celdas en *cursiva* se rellenan tras las
corridas en GCP. Los criterios de éxito, saturación y parada sí están
fijados: no se inventan después de ver los números.

Configuración fija de todas las corridas de este informe (no mezclar
con otra):

| Parámetro | Valor |
|---|---|
| Commit | `dbb6e6d` (el de las VM en las corridas) |
| `WORKER_CONCURRENCY` | 2 |
| `DB_MAX_CONNS` (API / worker) | 20 / 5 |
| Cloud NAT | activa (subred worker) |
| Tipo de las 2 VM | e2-small, pd-balanced 30 GB |
| Cloud SQL | `db-custom-1-3840`, Enterprise, zonal (`mooc-bd-aeab`) |
| Generador de carga | e2-standard-2, `us-central1-a`, 2 vCPU / 8 GB (`mooc-k6`) — no es una de las 2 VM |
| Reposo antes de cada corrida | 10 min |

## Datos sintéticos

Sembrados con `en-vm.sh sembrar` (`SEED_ENROLL=0` para el Escenario 1).
Declaración (copiar de `escenario.json` → `cantidades`):

| Qué | Cantidad |
|---|---|
| Usuarios | 404 (`cantidades` del `setup_data`: 400 estudiantes + 3 profesores + admin) |
| Cursos | 1 en la semilla; el Escenario 2 crea más (setup `course_id` `ecbf6109-…`) |
| Recursos | 27 en la semilla (texto/quiz); k6 añade corto/medio/largo + **audio** |
| Inscripciones | 0 al sembrar; 210 `201` en el Escenario 1; 14 341 checks de inscripción (201 o ya inscrito) |
| Intentos | 0 al sembrar; **2367** calificados; el reenvío coincidió en los 2367 |
| Perfiles multimedia | corto, medio, largo, `audio.wav` (setup del Escenario 2) |
| Estudiantes / profesores | 400 / 3 |

## Escenario 1 — recorrido de estudiante

Adaptación de `load/etapa1.js` en `load/escenario1.js`.

**Recorrido:** catálogo anónimo → inscripción (`POST /enrollments`) →
consumo con heartbeats → quiz con envío duplicado (misma
`Idempotency-Key`, misma nota). Una cuenta por VU.

**Login:** se mide, a 8/min, **fuera del mix de VU**. No autenticamos a
cada VU por `/auth/login`: el limitador es 10/min por IP y falsearía la
plataforma. Las sesiones del recorrido se siembran.

**Niveles:** línea base 50 VU y tres crecientes (100, 200, 300), con
una meseta extra en 300. `NIVELES` se cambia sin tocar el guion.

| Criterio | Definición operativa |
|---|---|
| Éxito | error HTTP < 0,5 %; p95 catálogo < 400 ms, consumo < 600 ms, quiz < 900 ms; reenvío del quiz con la misma nota; > 99 % de comprobaciones |
| Saturación | p95 de consumo o quiz ×2 respecto de la línea base, o error ≥ 0,5 %, o 5xx sostenidos, con la plataforma aún respondiendo |
| Parada | error ≥ 5 %, o p95 > 5 s, o la VM/SQL inalcanzable, o el generador es el que satura (CPU del generador > 80 % y p95 de k6 disparado con la API holgada) |

### Resultados

Una sola ejecución (`correr.sh escenario1`, reposo 600 s, inicio
**2026-09-27T17:03:10Z**, k6 **1056 s**). k6 se configuró con
`avg/min/med/max/p(90)/p(95)`: **no hay p99** en el JSON. El p50 del
resumen en pantalla falló por el nombre de la métrica; en el JSON el
p50 es `med`.

| Corrida | VU | req | error % | catálogo med / p90 / p95 | consumo | quiz | login | req/s | evidencias |
|---|---:|---:|---:|---|---|---|---|---:|---|
| agregada 50–300+bis | 50–300 (máx. 301) | 142493 | **9,92** (14 131 fallidas) | 35 / 994 / **1280** | 269 / 1997 / **2460** | 243 / 1011 / **1626** | 1759 / 2257 / **2459** | 135 | [resumen-escenario1.json](evidencias/resumen-escenario1.json), [corrida](evidencias/corrida-escenario1-20260927T170310Z.md) |

Umbrales de k6 rotos: `http_req_failed` &lt; 0,5 %; p95 catálogo &lt; 400,
consumo &lt; 600, quiz &lt; 900, login &lt; 2000. **Éxito no. Saturación
sí. Parada sí** (error ≥ 5 %). Integridad: checks **100 %** (153 279);
progreso 23 948/23 948; quiz 2367 aperturas, 2367 calificados, **2367
reenvíos con la misma nota**; login 141/141 a 200 y **0** respuestas
429. Connecting p95 = 0 ms: el generador no era el cuello de red.

Infraestructura por corrida: CPU/memoria/red/disco de cada VM;
conexiones y CPU de Cloud SQL; cola (profundidad, reintentos). Enlazar
`load/salida/metricas-*.md`.

## Escenario 2 — profesores + HLS

`load/escenario2.js`. No existía en Etapa 1.

**Profesores:** firman, hacen PUT al bucket, confirman, esperan
`ready`. Tres perfiles. **Estudiantes:** inscriben y recorren HLS al
ritmo de `EXTINF` (no a ráfaga).

| Criterio | Definición operativa |
|---|---|
| Éxito | vídeos listos sin `failed`; estudiantes reciben manifiesto 200 y segmentos 200; p95 de firma+confirmación en el mismo orden que el Escenario 1 |
| Saturación | espera en cola o procesamiento ×3 respecto del primer vídeo de setup; o la ráfaga de e2-small se agota (CPU en techo ~25 % sostenido tras minutos de FFmpeg) |
| Parada | más del 20 % de subidas sin `ready` en el timeout (10 min); OOM del worker; disco de 30 GB lleno |

Métricas separadas (p50/p95/p99): firma, transferencia, confirmación,
espera en cola, procesamiento, total, segmento HLS.

| Corrida | prof. / est. | listos | error % | firma | transfer | confirm | cola | proc. | total | HLS | evidencias |
|---|---|---:|---:|---|---|---|---|---|---|---|---|
Tiempos de firma/transfer/confirm/cola/total en **ms** (k6 `mooc_*`).
HLS en ms. Inicio **2026-09-27T17:30:56Z**, k6 **384 s**. Setup publicó
corto, medio, largo y **audio**. 13 `ready` (`mooc_ready_fallido` = 0).
820 segmentos HLS 200; 380 listas 200.

| Corrida | prof. / est. | listos | error % | firma med/p95 | transfer | confirm | cola med/p95 | total med/p95 | HLS med/p95 | evidencias |
|---|---|---:|---:|---|---|---|---|---|---|---|
| e2-a | 3 / 20 | **13** | **5,97** (123/2059) | 15 / **18** | 104 / **173** | 107 / **260** | 20 s / **279 s** | 20 s / **279 s** | 36 / **72** | [resumen-escenario2.json](evidencias/resumen-escenario2.json) |
| e2-b | — | | | | | | | | | no corrida | |

La API de carga (firma + PUT a GCS + confirm) cabe en cientos de ms. El
p95 de 279 s es **espera en cola + FFmpeg**. El umbral `http_req_failed
< 5 %` se cruzó (5,97 %); las comprobaciones funcionales quedaron en
100 %. Saturación de procesamiento: sí. Parada por &gt; 20 % sin
`ready`: **no**.

## Degradación y cuello de botella

En el Escenario 1 el p95 de catálogo (1280 ms), consumo (2460 ms) y quiz
(1626 ms) queda 2–4× por encima de los umbrales de éxito, con casi 10 %
de error HTTP. Eso no es el generador: `mooc-k6` es e2-standard-2 y k6
terminó 142 k peticiones. El mix escribe (inscripción, heartbeats, quiz)
contra **una** API en e2-small (0,5 vCPU sostenidas, ráfaga) y un pool
de 20 conexiones a Cloud SQL zonal. Hasta no pegar la gráfica de
Monitoring (CPU del Web vs conexiones de `mooc-bd-aeab` en la misma
ventana UTC), no se elige entre esos dos; sí se afirma que **esa
máquina + esa SQL** no sostienen 300 VU del mix académico dentro de
umbral.

En el Escenario 2 el p95 de firma es **18 ms**, el de PUT al bucket
**173 ms** y el de confirmación **260 ms**. El p95 de espera en cola y
de total-subida es el mismo orden: **279 s**. El p95 de segmento HLS es
**72 ms** (820 GET 200). Quien limita es la **cola + FFmpeg** en el
Worker e2-small (`WORKER_CONCURRENCY=2`), no GCS ni la API de firma.
`mooc_ready_fallido` = 0 (13 listos). El 5,97 % de error HTTP (umbral
5 %) encaja con iteraciones cortadas al final de la meseta, no con
transcodificaciones `failed`. Falta la captura de CPU del worker
(17:30–17:40 UTC) para el video.

## Propuesta de evolución

**Una** variable, la del Escenario 2 (el número más claro): dejar SQL y
Web iguales y pasar **solo el Worker** a `e2-standard-2` (2 vCPU
dedicadas), mismo `WORKER_CONCURRENCY=2`, repetir e2-a. Si el p95 de
total-subida baja de ~280 s hacia el orden de minutos de un solo
FFmpeg en CPU dedicada, el cuello era la ráfaga de e2-small. Si no
baja, el siguiente experimento es `WORKER_CONCURRENCY=1` (menos
contención) o separar Redis de FFmpeg, no “subir el tier de todo”.

Para el Escenario 1, el experimento análogo es **solo el Web** a
`e2-standard-2`, misma SQL y mismos 20 `DB_MAX_CONNS`. No se corre en
esta entrega; es la medición que permitiría esperar bajar el p95 de
consumo/quiz si Monitoring muestra el Web al techo y la SQL holgada.

## Gráficas y originales

| Qué | Dónde |
|---|---|
| Resúmenes k6 | [`evidencias/resumen-escenario1.json`](evidencias/resumen-escenario1.json), [`evidencias/resumen-escenario2.json`](evidencias/resumen-escenario2.json) |
| Metadatos de corrida | [`evidencias/corrida-escenario1-20260927T170310Z.md`](evidencias/corrida-escenario1-20260927T170310Z.md), [escenario 2](evidencias/corrida-escenario2-20260927T173056Z.md) |
| Métricas GCP | no se recogieron desde `mooc-k6` (sin `gcloud` allí); capturas de Monitoring a mano |
| Capturas de Monitoring / Facturación | `capacity-planning/evidencias/` |
