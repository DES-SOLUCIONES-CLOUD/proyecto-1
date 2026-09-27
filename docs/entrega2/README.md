# Entrega 2 — arquitectura en GCP

La plataforma de la Entrega 1 desplegada en dos VM de Compute Engine, con
Cloud SQL, Cloud Storage y la cola en Redis. El código de infraestructura
está en [`deploy/gcp/`](../../deploy/gcp/README.md); aquí está el modelo
que hay que defender en la sustentación.

**El HLS es público.** El bucket de derivados (`…-hls`) admite
`objects.get` anónimo. El enunciado lo permite; el profesor lo va a
preguntar. La justificación está en [decisiones](decisiones.md#bucket-hls-público).

| Documento | Contenido |
|---|---|
| [Componentes](componentes.md) | Qué corre dónde y cómo se hablan |
| [Despliegue](despliegue.md) | Diagrama (fuente en el repo) y correspondencia con GCP |
| [Decisiones](decisiones.md) | HLS público, NAT, e2-small, Enterprise, firewall, HMAC |
| [Operación](operacion.md) | Encender, apagar, migrar, recrear, destruir |
| [Capacidad, costos y límites](capacidad-costos.md) | Cuello de botella, SPOF, camino elástico |
| [Video](video.md) | Guion de 20 minutos |
| [Arranque en GCP y GitHub](arranque.md) | Lo que solo puede hacer el equipo |
| [Evidencias](evidencias.md) | Comandos de los ítems 14–19 |

Informe de las corridas: [`capacity-planning/pruebas_de_carga_entrega2.md`](../../capacity-planning/pruebas_de_carga_entrega2.md).
Orden de ejecución (VM generadora, semilla, k6): [`capacidad-corridas.md`](capacidad-corridas.md).
Bitácora de horas: [`capacity-planning/bitacora-costos.md`](../../capacity-planning/bitacora-costos.md).
