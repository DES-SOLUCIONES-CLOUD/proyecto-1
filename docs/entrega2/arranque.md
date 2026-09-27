# Arranque en GCP y GitHub

Esto no se puede hacer desde el repo. Lo hace el dueño del proyecto.
El detalle de cada variable y entorno está en
[`deploy/gcp/README.md`](../../deploy/gcp/README.md#desplegar-desde-github-actions).

## Una vez

1. `gcloud projects list` — anotar el **ID**, no el nombre visible.
   Confirmado: el proyecto se llama `desarrollo-soluciones-cloud`; el ID
   es `totemic-gravity-509902-u2`. Usar ese ID en el bootstrap, en
   `GCP_PROJECT_ID` y en `project_id` de Terraform.
2. Si el proyecto cuelga de la universidad:
   ```bash
   gcloud resource-manager org-policies describe iam.allowedPolicyMemberDomains --project ID --effective
   gcloud resource-manager org-policies describe storage.publicAccessPrevention --project ID --effective
   ```
   Si alguna impide `allUsers` en el bucket HLS, `terraform apply` falla
   en `hls_publico`. Pedir excepción o no hay opción (a).
3. En Cloud Shell, con el repo
   [DES-SOLUCIONES-CLOUD/proyecto-1](https://github.com/DES-SOLUCIONES-CLOUD/proyecto-1)
   (si se omite `--repo`, el script lo lee de `git remote origin`):
   ```bash
   git clone https://github.com/DES-SOLUCIONES-CLOUD/proyecto-1 && cd proyecto-1
   bash deploy/gcp/bootstrap-ci.sh --proyecto totemic-gravity-509902-u2 \
     --repo DES-SOLUCIONES-CLOUD/proyecto-1
   ```
   El script imprime los `gh variable set`. La federación solo acepta
   tokens de **este** repositorio: un `--repo` de un fork o de un
   remoto viejo dejaría a Actions sin credenciales.
4. Variables del repositorio (Settings → Secrets and variables →
   Actions → **Variables**, no Secrets), **incluida `CREAR_BD=true`**.
   Valores del bootstrap (2026-09-27):

   | Variable | Valor |
   |---|---|
   | `GCP_PROJECT_ID` | `totemic-gravity-509902-u2` |
   | `GCP_WIF_PROVIDER` | `projects/645904488560/locations/global/workloadIdentityPools/github/providers/github` |
   | `GCP_DEPLOYER_SA` | `mooc-deployer@totemic-gravity-509902-u2.iam.gserviceaccount.com` |
   | `TF_STATE_BUCKET` | `totemic-gravity-509902-u2-tfstate` |
   | `GCP_REGION` | `us-central1` |
   | `GCP_ZONE` | `us-central1-a` |
   | `CREAR_BD` | `true` |
   | `TLS_EMAIL` | correo del equipo (Let's Encrypt) |
   | `ADMIN_EMAIL` | correo del admin inicial; **borrarla** tras el primer `desplegar` |

   Condición del proveedor (evidencia 19):  
   `assertion.repository == 'DES-SOLUCIONES-CLOUD/proyecto-1' && assertion.repository_id == '1358524243' && (assertion.environment == 'gcp' || assertion.environment == 'gcp-rutina') && assertion.ref == 'refs/heads/main'`

5. Entornos `gcp` y `gcp-rutina`, los dos limitados a `main`.
   `gcp` puede exigir revisores; `gcp-rutina` no (si no, el apagado
   nocturno se queda esperando).
6. Proteger `main`: exigir PR, sin force-push.
7. Fusionar esta rama a `main` (si no, Actions no muestra el botón).

## Despliegue

En este orden: `infra` → `publicar` → `desplegar` → `certificado`.
Cloud SQL tarda 10–15 min. Si `desplegar` llega antes de que el
arranque de la VM termine, repetirlo.

Luego: contraseña del admin en Secret Manager, borrar `ADMIN_EMAIL`,
volver a `desplegar`. Humo con Postman contra
   [https://34.28.87.172.sslip.io/](https://34.28.87.172.sslip.io/).

Migrar MinIO → GCS y el dump local → Cloud SQL **antes** de sembrar,
comprobando checksums y que cada `object_key` existe. Commit de
`.terraform.lock.hcl` tras el primer `init` real. Ensayar
`bd.sh eliminar` → `bd.sh recrear` una vez.

## Evidencia (video y documentos)

Los ítems 14–19 del checklist: `terraform output`, descripción de VM /
SQL / firewall / subredes; 22/6379/5432 cerrados; `curl -v` y cookies
Secure; `pg_stat_ssl`; carga simple y multipart; HLS `ready` y
reproducción; URL firmada vs 403; listado HLS 403; HMAC cruzado 403;
idempotencia y reintento; condición del proveedor WIF; Compute default
sin Editor; reglas de los entornos.

## Capacidad

Máquina **fuera** de las dos VM (`e2-standard-2` temporal, misma
región). Sembrar con `SEED_ENROLL=0` y `SEED_STUDENTS` ≥ el nivel más
alto. Generar perfiles (`load/perfiles/generar.sh`). Diez minutos de
reposo antes de cada corrida. Registrar commit,
`WORKER_CONCURRENCY`, `DB_MAX_CONNS`, NAT. Rellenar
[`capacity-planning/pruebas_de_carga_entrega2.md`](../../capacity-planning/pruebas_de_carga_entrega2.md).
