# Entrega 3 — Índice de Documentación

Directorio de documentación técnica, evidencias y entregables correspondientes a la **Entrega 3: Aplicación elástica IaaS, consolidación del frontend funcional y diagnóstico de deuda técnica**.

---

## 1. Documentos Principales

| Documento | Responsable / Rol | Contenido |
|---|---|---|
| [**Verificación funcional del frontend**](frontend-verificacion.md) | Laura Martínez (Persona 2) | Matriz de rutas, flujos de estudiante y profesor, recorrido conectado en GCP, 5 estados de UI (`cargando`, `vacío`, `procesando`, `éxito`, `error`), control de acceso por rol y continuidad de sesión entre réplicas. |
| [**Diagnóstico de deuda técnica y retiro seguro**](deuda-tecnica.md) | Equipo / Persona 3 | Diagnóstico formal con SonarQube 10.7 Community, perfiles Sonar way (Go / TS), calidad de código, inventario de deuda técnica y lineamientos de retiro seguro. |
| [**Informe formal de arquitectura (PDF)**](Documento.pdf) | Equipo | Documento consolidado de arquitectura de la Entrega 3 (`Documento.pdf`). |

---

## 2. Evidencias y Mediciones

* **SonarQube y Calidad de Código:**
  * [Resumen exportado de SonarQube](evidencias/sonar/resumen.md)
  * [Hallazgos detallados (JSON)](evidencias/sonar/hallazgos.json)
  * [Métricas y medidas (JSON)](evidencias/sonar/medidas.json)
  * [Estado de la puerta de calidad (JSON)](evidencias/sonar/puerta.json)
* **Verificación de Frontend en GCP:**
  * Directorio de capturas y evidencias visuales: [`evidencias/frontend/`](evidencias/frontend/)
* **Pruebas de Carga y Capacidad (Escenarios 1, 2, 3A y 3B):**
  * Resumen y resultados comparativos: [`capacity-planning/evidencias/entrega3/`](../../capacity-planning/evidencias/entrega3/)
  * [Resumen primera vuelta de corridas](../../capacity-planning/evidencias/entrega3/resumen-primera-vuelta.md)
