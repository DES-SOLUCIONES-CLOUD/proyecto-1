# Operación y recuperación

Todo se opera con los scripts de `deploy/gcp/` o con los botones del
workflow `desplegar-gcp.yml`. Nadie necesita una llave JSON en el
portátil.

## Día a día

| Acción | Cómo |
|---|---|
| Ver qué hay | Actions → `estado`, o `deploy/gcp/resumen.sh` |
| Cambiar código | `publicar` + `desplegar` (o `todo`) |
| Encender / apagar | `encender` / `apagar` (`con_bd` incluye Cloud SQL). Queda en el resumen: es la bitácora |
| Apagado nocturno | variable `APAGADO_NOCTURNO=true` |
| Sembrar carga | `sembrar`, luego copiar `/opt/mooc/salida/escenario.json` |
| Mailpit | `remoto.sh web -- -L 8025:127.0.0.1:8025 -N` |
| Volver atrás | `desplegar` con `tag` = commit ya publicado |

Tras el primer arranque con `ADMIN_EMAIL`: la contraseña está en
`mooc-admin-password`. Borrar la variable y volver a `desplegar`.

## Recreación (la de la sustentación)

```bash
deploy/gcp/bd.sh eliminar          # export a GCS y a disco, borra Cloud SQL
deploy/gcp/bd.sh recrear gs://…/exports/<export>.sql.gz
deploy/gcp/generar-env.sh -f       # la IP privada cambió
deploy/gcp/energia.sh iniciar
deploy/gcp/desplegar-vm.sh worker && deploy/gcp/desplegar-vm.sh web
```

La importación va **antes** de que la API arranque contra la base vacía:
si migrara, el import choca con las tablas. Tras `bd.sh eliminar` en un
equipo que despliega desde GitHub, `CREAR_BD=false` hasta recrear.

Ensayarlo **una vez** antes de necesitarlo. Cada integrante tiene que
poder explicarlo.

## Qué sobrevive a un apagado

`energia.sh detener --con-bd` para el cobro de vCPU de las VM y de
Cloud SQL. Siguen cobrando: discos de 30 GB, la IP estática (tarifa de
reservada sin uso), la NAT si sigue, el almacenamiento y los backups de
Cloud SQL, los buckets y Artifact Registry. Unos 15 USD/mes de lista.

Cloud SQL detenida (`activation-policy=NEVER`) no se enciende sola.
Sigue cobrando almacenamiento y backups. Documentación de Google,
«Start, stop, and restart instances» (Cloud SQL), consultada el
2026-09-26: *Stopping an instance suspends instance charges. The
instance data is unaffected, and charges for storage and IP addresses
continue to apply.* Las instancias **suspendidas** (estado
`SUSPENDED`, por facturación) se borran a los 90 días; las
**detenidas** (`RUNNABLE` + política NEVER) no.

## Destrucción

`destruir.sh --confirmar --respaldar-buckets ~/respaldo-mooc` deja el
proyecto en cero salvo la clave de insignias (vive fuera de Terraform
para que lo firmado siga verificándose). El export de la base queda en
`deploy/gcp/respaldos/` (gitignorado).

## Cuentas sintéticas

Contraseña pública, en el código. Al terminar las pruebas, el SQL de
suspensión está en [`deploy/gcp/README.md`](../../deploy/gcp/README.md#cuentas-sintéticas-después-de-las-pruebas).
No se borran: el curso las referencia.
