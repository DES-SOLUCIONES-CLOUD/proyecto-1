# Bitácora de horas de uso (GCP)

Cada encendido y apagado, con propósito. Las filas de Actions
(`encender` / `apagar`) ya salen en el resumen de la ejecución; esta
tabla es la que va al informe. Hora de Colombia.

| Fecha | Hora | Acción | Cloud SQL | Quién | Propósito | Notas / USD si se sabe |
|---|---|---|---|---|---|---|
| 2026-09-27 | 00:26–01:04 | `infra` / `publicar` / `desplegar` / `certificado` | sí | maarojasga | primer arranque (Actions #1–#7) | VM creadas ~00:35 COT; SQL `mooc-bd-aeab` |
| 2026-09-27 | ~01:10 | encender (ya UP) | sí | equipo | prueba de humo | login admin + HTTPS; catálogo aún sin cursos publicados |
| 2026-09-27 | ~01:20 | `desplegar` | sí | maarojasga | Actions #8–#9 | tras borrar `ADMIN_EMAIL` |
| 2026-09-27 | ~01:30 | push `6474a2c` | sí | maarojasga | Actions #10 (automático) | publicar + desplegar, 14 min |
| | | apagar | sí | | fin de sesión | *pendiente* |
| | | encender | sí | | corridas Escenario 1 | reposo 10 min |
| | | apagar | sí | | | |
| | | encender | sí | | corridas Escenario 2 | salida a Internet |
| | | `bd.sh eliminar` | instancia borrada | | export + techo de costo | |
| | | apagar VM | — | | cierra la entrega; documentar qué queda vivo | |

Al cerrar: qué sigue cobrando (discos, IP reservada, NAT, GCS, AR,
almacenamiento de SQL si no se borró), estimación mensual, y cómo
recrear (`bd.sh recrear` + `desplegar-vm.sh` + `rsync` de objetos si
hubo respaldo).
