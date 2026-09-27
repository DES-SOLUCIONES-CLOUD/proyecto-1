# Guion del video (máximo 20 minutos)

Sustituye al enlace roto `docs/video-sustentacion.md` (ese archivo era
material de preparación y está fuera del repo). Esto sí se entrega.

**Declarar en voz alta:** el HLS se sirve desde un bucket público de
solo lectura. El enunciado lo admite; no es un descuido.

| Min | Qué mostrar | Qué decir |
|---|---|---|
| 0–3 | Diagrama de [`despliegue.mmd`](despliegue.mmd) y consola de GCP | Correspondencia Web/Worker/SQL/GCS/NAT/IAP. Por qué no hay ingress a Cloud SQL. Por qué e2-small es CPU compartida |
| 3–8 | Recorrido en `https://<ip>.sslip.io` | Registro o login admin, un curso, un quiz. Cookies `Secure` en DevTools. Certificado de Let's Encrypt (`curl -v`) |
| 8–12 | Carga directa y asíncrono | PUT firmado (simple y multipart, ETag/CORS). Recurso `queued` → `ready`. Confirmar dos veces: mismo `media_asset_id`. Un fallo con reintento en logs del worker. Cola vacía al final |
| 12–16 | Persistencia e integridad | Objeto en el bucket privado; HLS en el público; URL firmada 200 y la misma sin firma o caducada 403; listado anónimo del HLS 403; HMAC del worker 403 en `resources/` |
| 16–19 | Capacidad | Una gráfica del Escenario 1 y otra del 2. p95, throughput, el punto donde se rompe, el cuello (casi seguro FFmpeg en e2-small o el pool de SQL). Propuesta de evolución: más workers / CPU dedicada, no «subir el tier y ya» |
| 19–20 | Operación | `terraform output`, VMs detenibles, `bd.sh eliminar` exporta. Cerrar: qué queda vivo y cuánto cuesta |

No afirmar OpenTelemetry, HA ni RTO medido. Si falta una evidencia, decir
que falta.
