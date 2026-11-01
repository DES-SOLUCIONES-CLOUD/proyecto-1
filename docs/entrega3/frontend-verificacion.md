# Verificación funcional del frontend — Entrega 3

**Responsable:** Laura Fernanda Martínez Galindo (frontend, flujos y almacenamiento)

En esta parte revisé que un profesor y un estudiante puedan hacer todo lo que
pide el enunciado desde el navegador, sobre la plataforma desplegada en GCP,
sin tener que llamar a la API a mano. También revisé que la interfaz muestre
bien los estados (cargando, vacío, procesando, éxito y error), que cada rol
solo pueda hacer lo que le toca y que los datos queden guardados en Cloud SQL y
en Cloud Storage.

> Las capturas de este documento se toman sobre el entorno de GCP. Donde dice
> **Evidencia pendiente** falta pegar la captura del recorrido en la nube.

## 1. Cómo lo revisé

| Qué | Cómo |
|---|---|
| Recorrido completo | Lo hice a mano en el navegador sobre `https://136.82.109.164.sslip.io`, primero como profesor y después como estudiante (sección 4). |
| Pruebas automáticas de la interfaz | Las 34 pruebas E2E de `frontend/e2e/` (Playwright), una carpeta por flujo, más la auditoría de accesibilidad (`10-accesibilidad.spec.ts`). |
| Pruebas del backend que usan los flujos | Las pruebas de integración de `backend/internal/platform/httpserver/`, que corren contra PostgreSQL real en el pipeline. |
| Pruebas unitarias del frontend | `npm test` en `frontend/` (mensajes de error, formato del texto, catálogos de idioma). |
| Commit evaluado | **Pendiente:** se escribe aquí el commit del tag `entrega-3`. |

## 2. Dónde vive el frontend y cómo habla con la API

- **Dónde corre:** el frontend (Next.js) corre como contenedor en las mismas
  máquinas del grupo `mig-api`, en el puerto 3000. Por eso, cuando el
  autoscaling crea otra máquina de API, también aparece otra copia del
  frontend, y cuando la quita, también se va.
- **Una sola URL:** el balanceador recibe todo por HTTPS en
  `https://136.82.109.164.sslip.io` y mira la ruta: lo que empieza por
  `/api/` va a la API (puerto 8080) y todo lo demás va al frontend.
- **Versión identificable:** la imagen `mooc-frontend` se etiqueta con los 12
  primeros caracteres del commit (`deploy/gcp/publicar.sh`), así que se sabe
  exactamente qué código está corriendo. La URL de la API
  (`NEXT_PUBLIC_API_URL`) queda fija al construir la imagen, con la URL del
  balanceador.
- **Sesión:** al iniciar sesión, la API guarda la sesión en PostgreSQL y le
  manda al navegador una cookie `HttpOnly` (JavaScript no la puede leer) con
  `SameSite=Lax`, más una cookie `mooc_csrf` que el frontend repite en la
  cabecera `X-CSRF-Token` en cada cambio. Como la sesión no vive en la
  máquina, no importa a qué réplica de la API llegue cada petición.
- **CORS:** entre el frontend y la API no hace falta, porque los dos están en
  el mismo dominio. Solo se configura CORS en los buckets de Cloud Storage,
  porque los archivos se suben directo del navegador al bucket con URLs
  firmadas (`deploy/gcp/terraform/almacenamiento.tf`).

## 3. Matriz de flujos

### Estudiante

| Flujo del enunciado | Ruta en la interfaz | Cómo se verifica | Evidencia |
|---|---|---|---|
| Iniciar y cerrar sesión | `/login` y botón **Salir** del menú | E2E `01-identidad` y recorrido | Evidencia pendiente |
| Consultar el catálogo y el detalle de un curso | `/` y `/cursos/[courseId]` | E2E `05-consumo` y recorrido | Evidencia pendiente |
| Inscribirse | Botón **Inscribirme** en `/cursos/[courseId]` | E2E `05-consumo` y recorrido | Evidencia pendiente |
| Ver sus cursos y navegar módulos, unidades y recursos | `/mis-cursos`, temario en `/cursos/[courseId]` y botones anterior / siguiente en cada recurso | E2E `05-consumo` y recorrido | Evidencia pendiente |
| Ver video y documentos | `/cursos/[courseId]/recursos/[resourceId]` (reproductor HLS y visor de PDF) | E2E `03-multimedia` y `05-consumo` | Evidencia pendiente |
| Consultar su progreso | **Tu avance** en `/cursos/[courseId]` y barra en `/mis-cursos` | E2E `07-progreso` y recorrido | Evidencia pendiente |
| Presentar un quiz y ver el resultado | Recurso de tipo quiz: botón **Empezar o retomar la evaluación**, envío y nota | E2E `06-quiz` y recorrido | Evidencia pendiente |

### Profesor

| Flujo del enunciado | Ruta en la interfaz | Cómo se verifica | Evidencia |
|---|---|---|---|
| Iniciar y cerrar sesión | `/login` y botón **Salir** | E2E `01-identidad` y recorrido | Evidencia pendiente |
| Consultar sus cursos | `/profesor` | E2E `02-autoria` y recorrido | Evidencia pendiente |
| Crear y editar un curso con módulos y unidades | `/profesor` (crear) y `/profesor/versiones/[versionId]`, pasos 1 y 2 | E2E `02-autoria` y recorrido | Evidencia pendiente |
| Agregar recursos, cargar archivos y ver su estado de procesamiento | `/profesor/versiones/[versionId]`, paso 2 (el estado se actualiza solo cada 5 s) | E2E `03-multimedia` y `04-procesamiento` | Evidencia pendiente |
| Crear o editar un quiz básico | `/profesor/versiones/[versionId]/quiz/[resourceId]` (carga las preguntas guardadas) | E2E `06-quiz` y prueba `TestElProfesorLeeSuQuizParaEditarlo` | Evidencia pendiente |
| Publicar y ver el resultado | Paso 3 en `/profesor/versiones/[versionId]` y vista previa en `.../previsualizacion` | E2E `02-autoria` y recorrido | Evidencia pendiente |

## 4. Recorrido conectado en la nube

Este es el orden que seguí, todo desde el navegador y con datos reales del
entorno de GCP:

1. Entro como **profesor** y creo el curso *Computación en la Nube 2026*.
2. Le agrego un módulo, una unidad, una lectura, un video y un quiz.
3. Subo el video (MP4). Mientras sube se ve el porcentaje; después el recurso
   pasa a **En espera**, **Procesando…** y **Listo** sin recargar la página.
4. Creo el quiz con dos preguntas de selección única.
5. Publico. Si falta algo, la lista dice exactamente qué y dónde; cuando todo
   está bien, aparece **¡Curso publicado!** con el enlace al catálogo.
6. Salgo y entro como **estudiante**. Busco el curso en el catálogo y me
   inscribo.
7. Leo la lectura, veo el video (con calidad adaptativa) y paso al siguiente
   recurso con el botón de abajo.
8. Presento el quiz y veo la nota.
9. Vuelvo al curso y veo mi avance actualizado.

| Paso | Evidencia |
|---|---|
| 1-2. Curso creado con su estructura | Evidencia pendiente |
| 3. Video procesándose y luego listo | Evidencia pendiente |
| 4. Quiz guardado | Evidencia pendiente |
| 5. Curso publicado | Evidencia pendiente |
| 6. Inscripción del estudiante | Evidencia pendiente |
| 7. Video reproduciéndose | Evidencia pendiente |
| 8. Nota del quiz | Evidencia pendiente |
| 9. Avance del estudiante | Evidencia pendiente |

## 5. Estados de la interfaz

| Estado | Dónde se ve | Qué ve la persona | Evidencia |
|---|---|---|---|
| Cargando | Catálogo, mis cursos, curso, recurso, editor | Un texto "Cargando…" mientras llega la respuesta | Evidencia pendiente |
| Vacío | Catálogo sin resultados, mis cursos, módulo sin unidades, unidad sin recursos | Un bloque que explica qué falta y qué hacer (por ejemplo "Explorar el catálogo") | Evidencia pendiente |
| Procesando | Editor del profesor y recurso del estudiante | El profesor ve **Procesando…** con una explicación; el estudiante ve "Este recurso todavía se está procesando". Un archivo en proceso nunca aparece como disponible, y el curso no se puede publicar hasta que esté listo | Evidencia pendiente |
| Éxito | Publicar, inscribirse, guardar el quiz, guardar los datos del curso | Un aviso verde que dice lo que pasó y, si aplica, a dónde ir | Evidencia pendiente |
| Error | Cualquier pantalla | Un aviso rojo con un mensaje claro en español o inglés (por ejemplo "Ya usaste todos los intentos permitidos"), nunca un texto técnico del servidor | Evidencia pendiente |

**Si se corta algo, se retoma:**

- **Subida interrumpida:** si se cierra la página o se cae la conexión, el
  editor dice qué archivo era, que puede volver a elegirlo y que la subida
  sigue desde la parte en que iba, sin empezar de cero (tiene 24 horas).
- **Procesamiento interrumpido:** el editor avisa que se puede cerrar la
  página porque el procesamiento sigue en el servidor y, si un worker se
  apaga, el trabajo se retoma solo.
- **Quiz interrumpido:** cada respuesta se guarda al marcarla. Si el
  estudiante vuelve, retoma el mismo intento y ve el aviso "Retomaste tu
  intento: tus respuestas anteriores siguen guardadas".
- **Video:** al volver a un video, sigue desde la última posición.

## 6. Control de acceso por rol

| Caso | Qué pasa en la interfaz | Qué responde el servidor | Evidencia |
|---|---|---|---|
| Un estudiante abre `/profesor` | "Esta sección es solo para profesores" y un enlace a sus cursos | 403 en `/api/v1/courses/mine` | Evidencia pendiente |
| Un profesor abre el curso de otro profesor | "No tienes permiso… solo el dueño o sus coeditores pueden cambiarlo" y un enlace a sus cursos | 403 | Evidencia pendiente |
| Un estudiante no inscrito abre un recurso | "Debes inscribirte en el curso para ver este contenido" | 404 `not_enrolled` | Evidencia pendiente |
| Alguien sin sesión abre una sección privada | Le pide iniciar sesión | 401 | Evidencia pendiente |
| Un estudiante u otro profesor intenta leer las respuestas de un quiz | No hay ninguna pantalla que las muestre | 403 (prueba `TestNadieMasLeeLasRespuestasDelQuiz`) | Pipeline de CI |

La pantalla solo hace las cosas más claras: el servidor revisa el rol, la
propiedad del curso y la inscripción en cada petición.

## 7. Datos en Cloud SQL y Cloud Storage

| Qué se guarda | Dónde | Evidencia |
|---|---|---|
| Curso, versiones, módulos, unidades, recursos, inscripciones, intentos y progreso | Cloud SQL (PostgreSQL), sin nada en el disco de las máquinas | Evidencia pendiente |
| Video original que sube el profesor | Bucket `plasma-sol-513002-k6-mooc-objetos`, en `resources/<id>/original` | Evidencia pendiente |
| Segmentos HLS (`.m3u8` y `.ts`) | Bucket `plasma-sol-513002-k6-mooc-hls` | Evidencia pendiente |

## 8. Continuidad de la sesión entre réplicas

Mientras se corre el escenario 3A de carga y el grupo `mig-api` pasa a dos o
tres máquinas, sigo navegando con la misma sesión iniciada: catálogo, curso,
recurso y quiz. La sesión no se cierra ni aparecen errores 502, porque la
sesión está en PostgreSQL y no en la máquina que atiende.

| Qué se revisa | Evidencia |
|---|---|
| Dos o más instancias sanas detrás del balanceador | Evidencia pendiente |
| Navegación sin perder la sesión durante el escalamiento | Evidencia pendiente |

## 9. Cambios que hice al frontend en esta entrega

Todos están en `main` con su commit:

- Mensajes de error claros y traducidos (antes salían textos técnicos del servidor).
- Estados, tipos de recurso y roles traducidos (antes salía `draft`, `processing`, `student`).
- El estado de procesamiento se actualiza solo y explica qué pasa.
- La subida interrumpida dice cómo retomarla sin empezar de cero.
- El editor del curso quedó en tres pasos: datos, contenido y publicar.
- Avisos cuando falla agregar o eliminar partes del curso.
- El panel del profesor muestra el título de cada curso.
- Cada rol ve solo sus secciones, con un mensaje claro si entra donde no le toca.
- Inscripción más clara: error en rojo, volver a inscribirse y barra de avance.
- "Mis cursos" muestra el nombre y el avance de cada curso.
- El quiz empieza solo cuando el estudiante lo pide y avisa cuando se retoma.
- El texto de los recursos se ve con formato (títulos, listas, tablas).
- Navegación entre recursos con anterior y siguiente.
- El editor dice si cada quiz ya tiene preguntas.
- Rediseño visual de toda la plataforma (letras, colores, menú, catálogo con portadas, modo oscuro).
- En el backend, para que estos flujos funcionen bien: el profesor puede
  cargar su quiz guardado para editarlo, no se puede publicar un quiz sin
  preguntas, y al despublicar para editar el curso los quizzes ya no se
  pierden.

## 10. Cuentas de prueba

Para la demostración uso las cuentas sintéticas del entorno de GCP
(profesores `profesor@carga.mooc.local` y `profesor-0001@carga.mooc.local`,
estudiante `estudiante-0001@carga.mooc.local`). Las contraseñas no se
escriben en este documento.

## 11. Lo que queda pendiente

- Pegar las capturas de la nube donde dice **Evidencia pendiente**.
- Escribir el commit del tag `entrega-3` en la sección 1.
