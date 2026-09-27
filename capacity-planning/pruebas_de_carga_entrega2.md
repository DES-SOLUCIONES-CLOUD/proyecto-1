# Pruebas de carga — Entrega 2

Plantilla del informe. Las celdas en *cursiva* se rellenan tras las
corridas en GCP. Los criterios de éxito, saturación y parada sí están
fijados: no se inventan después de ver los números.

Configuración fija de todas las corridas de este informe (no mezclar
con otra):

| Parámetro | Valor |
|---|---|
| Commit | *hash* |
| `WORKER_CONCURRENCY` | *2 (salvo que se declare otra)* |
| `DB_MAX_CONNS` (API / worker) | *20 / 5* |
| Cloud NAT | *activa / apagada* |
| Tipo de las 2 VM | e2-small, pd-balanced 30 GB |
| Cloud SQL | `db-custom-1-3840`, Enterprise, zonal |
| Generador de carga | *e2-standard-2, zona, vCPU, RAM — no es una de las 2 VM* |
| Reposo antes de cada corrida | 10 min |

## Datos sintéticos

Sembrados con `en-vm.sh sembrar` (`SEED_ENROLL=0` para el Escenario 1).
Declaración (copiar de `escenario.json` → `cantidades`):

| Qué | Cantidad |
|---|---|
| Usuarios | *—* |
| Cursos | *—* (1 de texto/quiz + los que cree el Escenario 2) |
| Recursos | *—* texto + quiz; vídeos los crea k6 |
| Inscripciones | *0 al sembrar; las hace el recorrido* |
| Intentos | *0 al sembrar; los hace el quiz* |
| Perfiles multimedia | corto (5 s 240p), medio (20 s 480p), largo (45 s 720p) |
| Estudiantes / profesores | *—* / *—* |

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

| Corrida | VU | req | error % | p50 / p95 / p99 catálogo | consumo | quiz | login | req/s | evidencias |
|---|---:|---:|---:|---|---|---|---|---:|---|
| base | 50 | | | | | | | | *resumen + métricas* |
| n1 | 100 | | | | | | | | |
| n2 | 200 | | | | | | | | |
| n3 | 300 | | | | | | | | |
| n3-bis | 300 | | | | | | | | *repetición cerca del límite* |

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
| e2-a | 3 / 20 | | | | | | | | | | |
| e2-b | *—* | | | | | | | | | | |

## Degradación y cuello de botella

*Párrafo tras las corridas. Hipótesis previa: Escenario 1 — pool de
Cloud SQL o CPU del Web cuando el p95 de quiz se mueve y las
conexiones se acercan a 100. Escenario 2 — FFmpeg en e2-small
(0,5 vCPU sostenidas). No afirmar el cuello sin la gráfica que lo
muestra.*

## Propuesta de evolución

*Una configuración siguiente, no un deseo. Ejemplo: `WORKER_CONCURRENCY=2`
en `e2-standard-2` solo para el Worker, misma SQL, repetir Escenario 2.
O `DB_MAX_CONNS=10` si el cuello fue la base. Una variable cada vez.*

## Gráficas y originales

| Qué | Dónde |
|---|---|
| Resúmenes k6 | `load/salida/resumen-escenario1.json`, `resumen-escenario2.json` |
| Métricas GCP | `load/salida/metricas-*.json` y `.md` |
| Capturas de Monitoring / Facturación | `capacity-planning/evidencias/` *(crear al capturar)* |
