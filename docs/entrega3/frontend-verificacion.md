# Verificación funcional del frontend — Entrega 3

**Responsable:** Laura Fernanda Martínez Galindo (Persona 2: frontend y almacenamiento)

En esta parte revisé que un profesor y un estudiante puedan hacer todo lo que pide el enunciado desde el navegador, sobre la plataforma desplegada en GCP, sin llamar a la API a mano. También revisé otras cuatro cosas:

* que la interfaz muestre los cinco estados (cargando, vacío, procesando, éxito y error);
* que cada rol solo pueda hacer lo que le toca;
* que los archivos queden en Cloud Storage y los datos en Cloud SQL;
* que la sesión siga funcionando aunque cambie la réplica de la API que atiende.

Todas las capturas son del entorno de GCP (`https://136.82.109.164.sslip.io`).

## 1. Dónde vive el frontend y cómo habla con la API

| Tema | Cómo quedó |
|---|---|
| **Dónde corre** | El frontend (Next.js) es un contenedor en las mismas máquinas del grupo `mig-api`, en el puerto 3000. Cuando el autoscaling crea otra máquina de API, también aparece otra copia del frontend. |
| **Una sola URL** | El balanceador recibe todo por HTTPS en `https://136.82.109.164.sslip.io`. Lo que empieza por `/api/` va a la API (puerto 8080) y todo lo demás al frontend (puerto 3000). |
| **Versión identificable** | La imagen `mooc-frontend` se etiqueta con los 12 primeros caracteres del commit (`deploy/gcp/publicar.sh`). El administrador ve la versión desplegada en **Administración → Operación en vivo**, y `GET /api/v1/health` también la devuelve. |
| **Conexión con la API** | `NEXT_PUBLIC_API_URL` queda fija al construir la imagen con la URL del balanceador. |
| **Sesión** | Al iniciar sesión, la API guarda la sesión en PostgreSQL y manda una cookie `HttpOnly` con `SameSite=Lax`, más una cookie `mooc_csrf`. El frontend repite esa segunda cookie en la cabecera `X-CSRF-Token` en cada cambio. Como la sesión no vive en la máquina, no importa qué réplica atienda. |
| **CORS** | Entre el frontend y la API no hace falta, porque están en el mismo dominio. Solo se configura CORS en los buckets de Cloud Storage, porque los archivos se suben directo del navegador al bucket con URLs firmadas. |

## 2. Matriz de rutas y vistas

| Ruta | Vista (componente de Next.js) | Quién puede entrar |
|---|---|---|
| `/` | Catálogo con búsqueda y filtros (`app/page.tsx`) | Todos |
| `/login`, `/registro` | Iniciar sesión y crear cuenta de estudiante | Todos |
| `/cursos/[courseId]` | Detalle del curso, temario, inscripción y avance (`app/cursos/[courseId]/page.tsx`) | Todos; inscribirse, solo estudiantes |
| `/cursos/[courseId]/recursos/[resourceId]` | Lectura, video HLS, visor de PDF, imagen, quiz, con anterior y siguiente | Estudiantes inscritos (y el profesor dueño) |
| `/mis-cursos` | Mis cursos con el avance de cada uno | Estudiante |
| `/mis-insignias` | Insignias ganadas | Estudiante |
| `/insignias/[code]` | Verificación pública de una insignia | Todos |
| `/profesor` | Cursos del profesor y crear curso (`app/profesor/page.tsx`) | Profesor o administrador |
| `/profesor/versiones/[versionId]` | Editor en 3 pasos: datos y portada, contenido, publicar | Profesor dueño o coeditor |
| `/profesor/versiones/[versionId]/quiz/[resourceId]` | Editor del quiz | Profesor dueño o coeditor |
| `/admin` | Operación en vivo, crear cuentas, usuarios, métricas, auditoría | Administrador |
| `/cuenta/sesiones` | Mi cuenta: sesiones abiertas y descargar mis datos | Cualquiera con sesión |

## 3. Matriz de flujos

### Estudiante

| Flujo del enunciado | Ruta | Cómo se verifica | Evidencia |
|---|---|---|---|
| Iniciar y cerrar sesión | `/login` y botón **Salir** | Recorrido en la nube y E2E `01-identidad` | Figura 1 |
| Consultar el catálogo y el detalle de un curso | `/` y `/cursos/[courseId]` | Recorrido y E2E `05-consumo` | Figuras 1 y 2 |
| Inscribirse | Botón **Inscribirme** | Recorrido y E2E `05-consumo` | Figura 4 |
| Acceder a sus cursos y navegar módulos, unidades y recursos | `/mis-cursos`, temario y botones anterior/siguiente | Recorrido y E2E `05-consumo` | Figuras 3 y 5 |
| Consumir video y documentos | Reproductor HLS, visor de PDF e imagen | Recorrido y E2E `03-multimedia` | Figura 6 |
| Consultar su progreso | **Tu avance** y barra en `/mis-cursos` | Recorrido y E2E `07-progreso` | Figuras 4 y 5 |
| Presentar un quiz y ver el resultado | Recurso quiz: **Empezar o retomar**, enviar y nota | Recorrido y E2E `06-quiz` | Figura 7 |

### Profesor

| Flujo del enunciado | Ruta | Cómo se verifica | Evidencia |
|---|---|---|---|
| Iniciar y cerrar sesión | `/login` y **Salir** | Recorrido y E2E `01-identidad` | — |
| Consultar sus cursos | `/profesor` | Recorrido y E2E `02-autoria` | Figura 8 |
| Crear y editar un curso con módulos y unidades | `/profesor/versiones/[versionId]`, pasos 1 y 2 | Recorrido y E2E `02-autoria` | Figura 9 |
| Agregar recursos, cargar archivos y ver su procesamiento | Paso 2; el estado se actualiza solo cada 5 s | Recorrido y E2E `03-multimedia` y `04-procesamiento` | Figuras 10 y 13 |
| Crear o editar un quiz básico | Editor del quiz (carga las preguntas guardadas) | Recorrido y E2E `06-quiz` | Figura 11 |
| Publicar y ver el resultado | Paso 3; si falta algo dice qué y dónde | Recorrido y E2E `02-autoria` | Figuras 9 y 12 |

## 4. Recorrido conectado en la nube

Este fue el orden, todo desde el navegador y con datos reales del entorno de GCP:

1. Como profesora (`laura@mooc.test`) creo el curso **Kubernetes desde cero** y le escojo una portada.
2. Le agrego el módulo *Fundamentos* y la unidad *¿Qué es Kubernetes?*, con:
   * una lectura;
   * un video que se sube de una vez (4,1 MB);
   * un video que se sube por partes (25,6 MB), cortando la subida a la mitad y retomándola;
   * la guía en PDF;
   * un quiz.
3. Los videos pasan a **En cola**, **Procesando** y **Listo** sin recargar la página. En el panel del administrador se ve qué worker tomó cada video y cada calidad que generó (h720, h480, h360).
4. Publico. Si algo falta (por ejemplo, un video todavía en proceso), la lista dice qué; cuando todo está bien, aparece **¡Curso publicado!**.
5. Como estudiante (`ana@mooc.test`) encuentro el curso en el catálogo, me inscribo, leo, veo el video en calidad adaptativa y abro el PDF.
6. Presento el quiz (si salgo y vuelvo, retoma el mismo intento), veo la nota y mi avance. Al aprobar recibo la insignia.

![Figura 1. Catálogo publicado en GCP](evidencias/frontend/01-catalogo.jpg)

*Figura 1. Catálogo en GCP. Los 6 cursos de ejemplo los crea el script reproducible `data/catalogo/poblar.mjs` y "Kubernetes desde cero" se creó en vivo.*

![Figura 2. Detalle del curso](evidencias/frontend/02-detalle-curso.jpg)

*Figura 2. Detalle del curso con la portada que escogió la profesora.*

![Figura 3. Temario del curso](evidencias/frontend/03-temario-curso.jpg)

*Figura 3. Temario: módulo, unidad y recursos con su tipo y si son obligatorios.*

![Figura 4. Inscripción y progreso del estudiante](evidencias/frontend/04-inscripcion-progreso.jpg)

*Figura 4. Detalle del curso tras pulsar **Inscribirme**: se habilita el acceso completo a los contenidos y la barra de avance inicial en 0 %.*

![Figura 5. Mis cursos y navegación de unidades](evidencias/frontend/05-mis-cursos-avance.jpg)

*Figura 5. Vista de **Mis cursos** (`/mis-cursos`) con el porcentaje de avance calculado por el servidor y botones anterior/siguiente entre unidades.*

![Figura 6. Reproducción de video HLS y visor de PDF](evidencias/frontend/06-reproductor-hls-pdf.jpg)

*Figura 6. Reproductor HLS con calidades adaptativas (h720, h480, h360) servidas desde Cloud Storage y visor integrado de la guía en PDF.*

![Figura 7. Presentación y calificación del quiz](evidencias/frontend/07-quiz-resultado.jpg)

*Figura 7. Evaluación completada: calificación calculada en servidor, retroalimentación inmediata, registro de intento e insignia digital otorgada.*

![Figura 8. Panel de autoría de profesor](evidencias/frontend/08-panel-profesor.jpg)

*Figura 8. Panel de autoría (`/profesor`): listado de cursos propios, estado de publicación y botón para crear nuevo curso.*

![Figura 9. Editor de curso — Paso 1 y Paso 2](evidencias/frontend/09-editor-curso.jpg)

*Figura 9. Editor en 3 pasos: configuración de título, slug, resumen, descripción y selector visual de portada en el Paso 1.*

![Figura 10. Carga de recursos multimedia y archivos](evidencias/frontend/10-carga-archivos.jpg)

*Figura 10. Subida directa con URL prefirmada a Cloud Storage (multipart reanudable para archivos > 5 MB y subida simple para PDF/video corto).*

![Figura 11. Editor del quiz](evidencias/frontend/11-editor-quiz.jpg)

*Figura 11. Editor del quiz: configuración de preguntas, opciones, respuesta correcta (oculta al estudiante) y puntaje mínimo de aprobación.*

![Figura 12. Validación y publicación del curso](evidencias/frontend/12-curso-publicado.jpg)

*Figura 12. Paso 3 (Publicación): verificación exhaustiva de reglas de negocio en el servidor y mensaje de éxito "¡Curso publicado!".*

![Figura 13. Monitoreo del procesamiento asíncrono](evidencias/frontend/13-estado-procesamiento.jpg)

*Figura 13. Estados de procesamiento en tiempo real: polling automático cada 5 segundos reflejando transiciones `pending` → `processing` → `ready`.*

## 5. Estados de la interfaz

| Estado | Dónde se ve | Qué ve la persona |
|---|---|---|
| Cargando | Catálogo, mis cursos, curso, recurso, editor y paneles | El texto "Cargando…" mientras llega la respuesta |
| Vacío | Mis cursos y mis insignias sin nada, panel del profesor sin cursos, catálogo sin resultados | Un bloque que explica qué falta y qué hacer, por ejemplo "Explorar el catálogo" |
| Procesando | Editor del profesor y recurso del estudiante | El profesor ve **Procesando** con una explicación; el estudiante ve "Este recurso todavía se está procesando". Un archivo en proceso nunca aparece como disponible, y el curso no se puede publicar hasta que esté listo |
| Éxito | Guardar datos, publicar, inscribirse, guardar el quiz, nota del quiz | Un aviso verde que dice lo que pasó y, si aplica, a dónde ir |
| Error | Cualquier pantalla | Un aviso rojo con un mensaje claro en español o inglés, nunca un texto técnico del servidor |

**Si se corta algo, se retoma:**

* **Subida interrumpida.** Si se cierra la página a mitad de la subida, al volver el editor dice qué archivo era y cuánto pesa. Al elegirlo otra vez dice "Retomando" y solo sube las partes que faltaban; se puede retomar durante 24 horas.
* **Quiz interrumpido.** Cada respuesta se guarda al marcarla. Al volver, el estudiante retoma el mismo intento.
* **Video.** Sigue desde la última posición.

## 6. Control de acceso por rol

| Caso | Qué pasa en la interfaz | Qué responde el servidor |
|---|---|---|
| Un estudiante abre `/profesor` | "Esta sección es solo para profesores" y un enlace a sus cursos | 403 |
| Un estudiante abre `/admin` | "Esta sección es solo para administradores" | 403 |
| Un profesor abre el curso de otro profesor (`carlos@mooc.test` o `profe-carlos@mooc.com` con el curso de Laura) | Mensaje de que no tiene permiso y enlace a sus cursos; tampoco aparece en su listado de `/profesor` | 403 |
| Alguien abre un recurso de un curso en el que no está inscrito | "Debes inscribirte en el curso para ver este contenido" | 404 `not_enrolled` |
| Alguien sin sesión abre una sección privada | Le pide iniciar sesión | 401 |
| Un estudiante u otro profesor intenta leer las respuestas de un quiz | No hay pantalla que las muestre | 403 (prueba `TestNadieMasLeeLasRespuestasDelQuiz`) |

La pantalla solo hace las cosas más claras. Quien manda es el servidor, que revisa en cada petición el rol, la propiedad del curso y la inscripción.

## 7. Persistencia en Cloud Storage y Cloud SQL

| Qué se guarda | Dónde |
|---|---|
| Curso, versiones, módulos, unidades, recursos, inscripciones, intentos, progreso, insignias y sesiones | Cloud SQL (PostgreSQL 16 administrado, `mooc-bd-3bce`, solo IP privada `10.30.0.3`) |
| Archivo original que sube el profesor | Bucket privado `plasma-sol-513002-k6-mooc-objetos`, en `resources/<id-del-recurso>/original` |
| Video convertido a HLS (`.m3u8` y `.ts` por calidad) | Bucket `plasma-sol-513002-k6-mooc-hls`, en `hls/<id-del-recurso>/` |

Ninguna máquina de API o de workers guarda nada en su disco. Por eso el autoscaler puede crear o borrar máquinas sin perder datos.

![Figura 14. Original en el bucket](evidencias/frontend/22-bucket-original.jpg)

*Figura 14. El video que subió la profesora, en `resources/<id>/original` del bucket privado.*

![Figura 15. Segmentos HLS](evidencias/frontend/23-bucket-hls.jpg)

*Figura 15. Lo que generó el worker: listas `.m3u8` y segmentos `.ts` en el bucket HLS.*

![Figura 16. Cloud SQL](evidencias/frontend/25-cloud-sql.jpg)

*Figura 16. Cloud SQL: PostgreSQL 16 administrado, sin IP pública, solo la IP privada 10.30.0.3.*

## 8. Sesión y continuidad entre réplicas

Para que se pueda ver sin entrar por SSH a cada máquina, agregué **Administración → Operación en vivo**, que se actualiza cada 2 segundos y solo ve el administrador:

* **Versión desplegada** y la réplica de la API que está respondiendo.
* **Reparto entre réplicas**: cuántas peticiones atendió cada máquina `mooc-api-xxxx`.
* **Acciones de los usuarios**: qué hizo cada persona, con qué resultado, cuánto tardó y **qué réplica la atendió**.
* **Procesamiento de archivos**: qué worker `mooc-worker-xxxx` tomó cada video, cada calidad que generó y cuánto tardó.

Esa actividad la anotan todas las máquinas en Redis, la VM fija de la cola que comparten todas, así que el panel ve juntas las 3 réplicas y todos los workers.

Durante el escenario 3A de Juan, cuando `mig-api` pasa a 2 o 3 máquinas, sigo navegando con la misma sesión. El panel muestra que mis acciones las atienden máquinas distintas y que la sesión no se cierra ni salen errores 502. Eso demuestra que la sesión y los datos viven en Cloud SQL, compartidos por todas las réplicas, y no en la máquina que atiende.

![Figura 17. Operación en vivo](evidencias/frontend/20-operacion-en-vivo.jpg)

*Figura 17. Operación en vivo: versión desplegada, réplica que responde, reparto entre réplicas y acciones con la máquina que las atendió.*

![Figura 18. Procesamiento por los workers](evidencias/frontend/21-procesamiento-workers.jpg)

*Figura 18. El worker `mooc-worker-7ps1` convirtió el video de 25 MB a HLS en tres calidades; el trabajo completo tardó 270 s.*

![Figura 19. Grupos de instancias](evidencias/frontend/24-grupos-de-instancias.jpg)

*Figura 19. Los dos grupos administrados, `mig-api` y `mig-workers`, con el número de máquinas en ese momento.*

## 9. Datos de prueba reproducibles

El enunciado permite preparar cuentas con datos de prueba. Lo hice con `data/catalogo/poblar.mjs`, que usa la API pública igual que el navegador:

1. El administrador crea las cuentas ya activas.
2. El profesor crea 6 cursos de temas y largos distintos, con lecturas, video, imagen, PDF y quizzes de 2 a 6 preguntas.
3. El script sube los archivos al bucket, espera a los workers y publica.

Si se corre otra vez, se salta lo que ya existe. Las contraseñas se pasan al correrlo y no están en el repositorio (`data/catalogo/README.md`).

El curso de la demostración en vivo **no** lo crea el script: lo creé desde la interfaz, como pide el enunciado.

| Cuenta | Rol |
|---|---|
| `laura@mooc.test` / `profe-laura@mooc.com` | profesora (crea el curso en vivo) |
| `carlos@mooc.test` / `profe-carlos@mooc.com` | profesor dueño del catálogo (el "profesor ajeno") |
| `ana@mooc.test` / `est-ana@mooc.com`, `luis@mooc.test` | estudiantes |

## 10. Cambios que hice al frontend en esta entrega

* **Diseño nuevo:** colores, letras Bricolage Grotesque y Plus Jakarta Sans, y portadas de colores que el profesor escoge entre 8.
* **Mensajes:** errores claros y traducidos; estados, tipos de recurso y roles en español e inglés.
* **Editor en tres pasos:** datos, contenido y publicar. El estado de procesamiento se actualiza solo.
* **Subida por partes:** se puede retomar y dice qué archivo volver a elegir.
* **Quiz:** el estudiante lo empieza cuando quiere y, si sale, lo retoma. El profesor puede editar un quiz ya guardado.
* **Navegación:** migas de pan, botones anterior y siguiente, avance en Mis cursos y textos con formato.
* **Roles:** cada uno ve solo sus secciones, con un mensaje claro si entra donde no le toca.
* **Administrador:** panel de Operación en vivo, crear cuentas sin correo y ver la versión desplegada.
* **Backend necesario para estos flujos:**
  * copiar los quizzes al abrir una versión nueva;
  * no publicar un quiz sin preguntas;
  * leer el quiz guardado;
  * guardar la portada del curso;
  * registrar la actividad para el panel;
  * crear cuentas desde administración.

## 11. Pruebas automáticas

| Qué | Dónde |
|---|---|
| 35 pruebas E2E (Playwright), una carpeta por flujo, más la auditoría de accesibilidad WCAG 2.2 AA | `frontend/e2e/` |
| Pruebas de integración del backend contra PostgreSQL y Redis reales (incluyen las del panel y la creación de cuentas) | `backend/internal/platform/httpserver/` |
| Pruebas unitarias del frontend (mensajes de error, formato del texto, catálogos de idioma) | `npm test` en `frontend/` |

Todo corre en GitHub Actions en cada push (`.github/workflows/ci.yml`).
