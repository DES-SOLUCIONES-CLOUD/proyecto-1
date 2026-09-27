# Modelo de componentes

La aplicación no cambió de forma: sigue siendo un monolito modular en Go
(API) y workers sin estado, un frontend Next.js y PostgreSQL como fuente
de verdad. Lo que cambia en esta entrega es **dónde vive cada pieza** y
con qué identidad habla.

```
Navegador
  │  HTTPS (cookie Secure, SameSite)
  ▼
nginx (Web Server) ──► API Go
                         │
                         ├─ PostgreSQL (Cloud SQL, TLS, IP privada)
                         ├─ Redis (contenedor en el Worker, 6379 solo desde el Web)
                         ├─ cola asynq (el mismo Redis)
                         └─ Cloud Storage API XML (clave HMAC de mooc-web)
                              originales, PDF, insignias  → bucket privado
                              firmas de subida / descarga

Worker Go (Worker Server)
  ├─ PostgreSQL (pool más pequeño)
  ├─ Redis local (consume asynq)
  └─ Cloud Storage (clave HMAC de mooc-worker)
       lee originals; escribe presentaciones/ y el bucket HLS
```

## Correspondencia enunciado → proceso

| Componente del enunciado | Proceso | Máquina | Identidad |
|---|---|---|---|
| Web Server | nginx + `cmd/api` + frontend + Mailpit | e2-small pública | `mooc-web` |
| Worker Server | Redis 7.4 + `cmd/worker` | e2-small privada | `mooc-worker` |
| Base de datos | Cloud SQL PostgreSQL 16 Enterprise | peering PSA | usuario `mooc` |
| Objetos | Cloud Storage (API XML, HMAC) | regional | HMAC por cuenta |
| Cola | asynq sobre Redis | disco del Worker (AOF) | red, no contraseña |
| Secretos | Secret Manager | — | cada VM lee los suyos |
| Imágenes | Artifact Registry | — | pull con la SA de la VM |

No hay balanceador, no hay CDN, no hay Memorystore. El enunciado los
excluye o no los pide. El frontend se sirve en el mismo origen que la
API (`COMPOSE_PROFILES=frontend`, encendido por defecto).

## Fronteras que importan

- **La API nunca recibe el binario.** Firma un PUT, el navegador habla
  con `storage.googleapis.com`, y al confirmar la API lee el objeto una
  vez (checksum, MIME, antimalware) y encola.
- **El worker no escribe en `resources/`.** Un reintento no puede
  sustituir el original. Tampoco la API escribe derivados HLS: cada
  componente tiene su HMAC.
- **Redis no es alcanzable desde Internet.** Bind a la IP interna,
  firewall de 6379 solo desde `mooc-web`. Sin contraseña: el código no
  la soporta; lo documentamos como limitación, no como olvido.
- **Cloud SQL no escucha en Internet.** Sin IP pública. El firewall de
  *esta* VPC no filtra la entrada al rango de PSA (vive en la VPC del
  productor); lo que se controla es el *egress* 5432 desde las dos
  cuentas de servicio. Ver [decisiones](decisiones.md#firewall-de-egress).
