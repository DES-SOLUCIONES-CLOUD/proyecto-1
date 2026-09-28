# Entrega 2 — índice

Video de sustentación: [YouTube](https://www.youtube.com/watch?v=M2FF9Pv12gE).
El informe formal (componentes, despliegue en GCP, decisiones de diseño,
capacidad resumida y costos) está en
[`Documento Arquitectura.docx`](Documento%20Arquitectura.docx).
Diagramas: [`Diagrama_Componentes.png`](Diagrama_Componentes.png),
[`Diagrama_Despliegue.png`](Diagrama_Despliegue.png),
[`Diagramas.vsdx`](Diagramas.vsdx).
Costos de lista: [`Costos - Proyecto Entrega 2.pdf`](Costos%20-%20Proyecto%20Entrega%202.pdf).

Lo que sigue **no** está en ese documento: procedimientos para reproducir
el despliegue, las evidencias 14–19 y las corridas de k6.

| Documento | Contenido |
|---|---|
| [Arranque en GCP y GitHub](arranque.md) | Bootstrap, variables de Actions, WIF, orden `infra` → `publicar` → `desplegar` |
| [Operación y recuperación](operacion.md) | Encender/apagar, Mailpit, recrear Cloud SQL, destrucción |
| [Evidencias 14–19](evidencias.md) | Comandos de configuración, red, almacenamiento, HMAC, asíncrono y CI |
| [Corridas de capacidad](capacidad-corridas.md) | Orden: sembrar, VM `mooc-k6`, Escenario 1 y 2, Monitoring, borrar generador |

Informe de las corridas en GCP (números de k6; **no** la Etapa 1 local):
[`capacity-planning/pruebas_de_carga_entrega2.md`](../../capacity-planning/pruebas_de_carga_entrega2.md).
La prueba de §10 (42.075 peticiones, 0 % de error) es Compose: [`load/README.md`](../../load/README.md).
Bitácora de horas de las VM:
[`capacity-planning/bitacora-costos.md`](../../capacity-planning/bitacora-costos.md).
Infraestructura como código: [`deploy/gcp/README.md`](../../deploy/gcp/README.md).
