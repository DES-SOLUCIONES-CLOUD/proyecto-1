# Capacidad, costos y limitaciones

## Puntos únicos de falla

Esta etapa los pide, no los esconde:

| Recurso | Qué se pierde si cae |
|---|---|
| Web Server | HTTPS, API, Mailpit. No hay réplica ni LB |
| Worker Server | Cola (Redis en disco) y transcodificación |
| Redis | Trabajos pendientes no consumidos; AOF mitiga un reinicio, no un disco perdido |
| Cloud SQL zonal | Toda la persistencia. Sin réplica, sin HA |
| Zona `us-central1-a` | Las dos VM y la base |
| IP estática del Web | El nombre `sslip.io` y el certificado |

No hay camino automático de conmutación. La recuperación es
`energia.sh iniciar`, `bd.sh recrear` o `desplegar-vm.sh` del tag
conocido. RTO/RPO del enunciado (15 min / 4 h) **no están acreditados**
con una prueba de recuperación cronometrada: el export de `bd.sh` es el
respaldo que sobrevive al borrar la instancia; los backups automáticos
de Cloud SQL se van con ella.

## Camino hacia una arquitectura elástica

No se vende como hecho. El orden razonable, cuando el enunciado lo
permita:

1. **Separar Redis** (Memorystore) para que el Worker deje de ser el
   disco de la cola.
2. **Más workers** detrás de la misma cola: `WORKER_CONCURRENCY` y N
   VM, no una e2-small compartiendo FFmpeg con Redis.
3. **CPU dedicada** (`e2-standard-2` o custom) cuando las corridas
   demuestren que la ráfaga de e2-small es el ruido, no la señal.
4. **Cloud SQL con HA** o al menos PITR, cuando haya que cumplir RPO.
5. **LB + más API** cuando el Escenario 1 deje de caber en una VM.
6. **CDN delante del bucket HLS**, que es cuando el HLS público deja de
   ser la entrega definitiva.

El código ya admite varias instancias de API (el compose local escala
con nginx). En GCP hay una.

## Costos

Tabla de lista en [`deploy/gcp/README.md`](../../deploy/gcp/README.md#costos):
unas **0,12 USD/hora** todo encendido, ~90 USD/mes, ~15 USD/mes
apagado. Verificar en la calculadora de GCP **con la fecha del
informe**, incluyendo la salida a Internet del Escenario 2 (~0,12 USD/GB;
un 720p de 10 min son 300–400 MB por reproducción).

Presupuesto: Cloud Billing Budget al 50/90/100 % y 100 % proyectado,
`EXCLUDE_ALL_CREDITS`. Si el equipo no administra la cuenta de
facturación, no se puede crear y hay que documentarlo.

Bitácora de cada encendido: [`capacity-planning/bitacora-costos.md`](../../capacity-planning/bitacora-costos.md).
Consumo observado: Facturación → Informes, filtro `proyecto=mooc`, una
captura al día mientras esté vivo.

## Lo que esta entrega no acredita todavía

Las corridas de capacidad, el punto de degradación y el cuello de
botella con evidencia viven en
[`capacity-planning/pruebas_de_carga_entrega2.md`](../../capacity-planning/pruebas_de_carga_entrega2.md).
Hasta que no se ejecuten contra GCP, ese informe es la plantilla y los
criterios; no un resultado.
