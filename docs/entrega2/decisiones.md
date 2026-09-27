# Decisiones de diseño (Entrega 2)

Cada una aparece en el video y en la sustentación. El detalle operativo
está en [`deploy/gcp/README.md`](../../deploy/gcp/README.md).

## Bucket HLS público

El reproductor pide la lista maestra y, de ahí, variantes y segmentos
con **rutas relativas**, que no heredan la firma. En MinIO se abre el
prefijo `hls/`. En GCS con acceso uniforme eso no se puede: los
permisos son del bucket entero, y las IAM Conditions no admiten
`allUsers`.

Elegimos un bucket aparte, público, solo para `hls/*`, con
`legacyObjectReader` (get, no list). El privado mantiene prevención de
acceso público **forzada**. Quien conozca la URL de un segmento (UUID)
puede descargarlo sin estar inscrito; el bucket no se lista. El
enunciado lo admite. **El HLS es público: lo declaramos aquí y en el
video.**

Descartado: ACL por objeto, reescribir listas en la API, proxy nginx,
`S3_PUBLIC_URL` (quitaría la firma de *todos* los objetos).

## Cloud NAT

El Worker no tiene IP externa. Cloud Storage, Artifact Registry, Secret
Manager y Monitoring le llegan por Private Google Access, sin NAT. La
NAT existe para el **primer arranque** (repo de Docker, paquetes de
Debian, Ops Agent). Redis se replica en Artifact Registry para no
depender de Docker Hub. Se puede apagar con `habilitar_nat=false`
después del aprovisionamiento; hay que volver a encenderla para recrear
el Worker. El tráfico pesado (originales, HLS) no pasa por ella.

## e2-small (CPU compartida)

El enunciado fija 2 vCPU, 2 GiB, 30 GiB. `e2-small` es exactamente eso,
pero las vCPU son **compartidas**: 25 % garantizado (0,5 vCPU
sostenidas) y ráfaga al 100 % mientras queden créditos. La API pasa el
tiempo esperando a la base: le basta. FFmpeg no: una transcodificación
larga agota la ráfaga y corre a un cuarto. Es el cuello de botella
esperable del Escenario 2. Cada corrida deja las VM 10 minutos en
reposo para no medir con créditos prestados de la anterior.

`e2-custom-2-2048` daría 2 vCPU dedicadas al triple de precio: otra
configuración, no esta.

## Cloud SQL Enterprise, no Enterprise Plus

`edition = ENTERPRISE` va explícito. Para PostgreSQL 16 la API puede
crear Enterprise Plus, que no admite `db-custom-1-3840` y cuesta más.
No hay réplicas, no hay PITR, no hay HA regional: es zonal, como pide
esta etapa. `ssl_mode = ENCRYPTED_ONLY`. El pool de la API es
`DB_MAX_CONNS` (20 por defecto); el del worker, 5.

## Firewall de egress, no de ingress a Cloud SQL

Cloud SQL vive en la VPC del productor, enlazada por peering. Las
reglas de *esta* VPC **no filtran su entrada**. Lo que sí se controla
es la salida: egress 5432 al rango PSA solo desde `mooc-web` y
`mooc-worker`; otra regla deniega el resto. Una VM nueva en la VPC no
llega a la base. Por eso no hay (ni puede haber) una regla de ingress
«5432 solo desde las VM» sobre Cloud SQL.

22, 6379 y 5432 no están abiertos a Internet: 22 solo IAP, 6379 solo
Web→Worker, 5432 sin IP pública.

## HMAC por componente

El código ya habla S3. GCS acepta SigV4 con claves HMAC de cuenta de
servicio. Cada VM tiene la suya: la API es `objectUser` en el privado y
`objectViewer` en HLS; el worker es `objectViewer` + `objectUser`
condicionado a `presentaciones/` en el privado, y `objectUser` en HLS.
La llave del worker recibe 403 al escribir en `resources/`; la de la
API, 403 al escribir en el bucket HLS. No se usa la cadena de
credenciales de AWS (en GCE solo añadía arranque lento).
