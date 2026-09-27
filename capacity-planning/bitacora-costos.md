# Bitácora de horas de uso (GCP)

Cada encendido y apagado, con propósito. Las filas de Actions
(`encender` / `apagar`) ya salen en el resumen de la ejecución; esta
tabla es la que va al informe. Hora de Colombia.

| Fecha | Hora | Acción | Cloud SQL | Quién | Propósito | Notas / USD si se sabe |
|---|---|---|---|---|---|---|
| *aaaa-mm-dd* | *hh:mm* | encender | sí | | primer `infra` + prueba de humo | |
| | | apagar | sí | | fin de sesión | |
| | | encender | sí | | corridas Escenario 1 | reposo 10 min |
| | | apagar | sí | | | |
| | | encender | sí | | corridas Escenario 2 | salida a Internet |
| | | `bd.sh eliminar` | instancia borrada | | export + techo de costo | |
| | | apagar VM | — | | cierra la entrega; documentar qué queda vivo | |

Al cerrar: qué sigue cobrando (discos, IP reservada, NAT, GCS, AR,
almacenamiento de SQL si no se borró), estimación mensual, y cómo
recrear (`bd.sh recrear` + `desplegar-vm.sh` + `rsync` de objetos si
hubo respaldo).
