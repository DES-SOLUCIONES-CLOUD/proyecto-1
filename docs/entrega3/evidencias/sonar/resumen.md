## SonarQube: commit `83eb29e`

Puerta de calidad: **OK** (http://localhost:9000)

| Metrica | Valor |
|---|---|
| Lineas de codigo | 19780 |
| Duplicacion (%) | 0.4 |
| Bloques duplicados | 6 |
| Mantenibilidad | A |
| Deuda tecnica (min) | 1152 |
| Ratio de deuda (%) | 0.2 |
| Confiabilidad | A |
| Seguridad | A |
| Bugs | 0 |
| Vulnerabilidades | 0 |
| Code smells | 196 |
| Security hotspots | 9 |
| Cobertura (%) | 30.1 |

| Condicion | Umbral | Medido | Estado |
|---|---|---|---|
| sqale_rating | GT 3 | 1 | OK |
| duplicated_lines_density | GT 20 | 0.4 | OK |

### Hallazgos abiertos: 196

| Severidad | Cantidad |
|---|---|
| Bloqueante | 0 |
| Critico | 38 |
| Mayor | 119 |
| Menor | 12 |
| Informativo | 27 |

### Inventario por regla

| Severidad | Regla | Tipo | Casos | Ejemplo (archivo:linea) | Mensaje |
|---|---|---|---|---|---|
| Critico | `go:S3776` | CODE_SMELL | 16 | `backend/internal/platform/antimalware/antimalware.go:162` | Refactor this method to reduce its Cognitive Complexity from 19 to the 15 allowed. |
| Critico | `typescript:S2310` | CODE_SMELL | 13 | `frontend/lib/markdown.ts:105` | Remove this assignment of "i". |
| Critico | `typescript:S2004` | CODE_SMELL | 3 | `frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:123` | Refactor this code to not nest functions more than 4 levels deep. |
| Critico | `go:S1192` | CODE_SMELL | 3 | `backend/internal/platform/antimalware/antimalware.go:173` | Define a constant instead of duplicating this literal "%w: %v" 6 times. |
| Critico | `typescript:S3776` | CODE_SMELL | 3 | `frontend/lib/carga.ts:230` | Refactor this function to reduce its Cognitive Complexity from 18 to the 15 allowed. |
| Mayor | `typescript:S6759` | CODE_SMELL | 46 | `frontend/components/NavegacionDelCurso.tsx:76` | Mark the props of the component as read-only. |
| Mayor | `typescript:S6819` | CODE_SMELL | 40 | `frontend/app/profesor/versiones/[versionId]/page.tsx:155` | Use <output> instead of the "status" role to ensure accessibility across all devices. |
| Mayor | `typescript:S6479` | CODE_SMELL | 15 | `frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:293` | Do not use Array index in keys |
| Mayor | `typescript:S3358` | CODE_SMELL | 11 | `frontend/app/cursos/[courseId]/page.tsx:106` | Extract this nested ternary operation into an independent statement. |
| Mayor | `typescript:S4624` | CODE_SMELL | 2 | `frontend/lib/api.ts:379` | Refactor this code to not use nested template literals. |
| Mayor | `typescript:S1854` | CODE_SMELL | 1 | `frontend/app/admin/page.tsx:21` | Remove this useless assignment to variable "locale". |
| Mayor | `typescript:S6478` | CODE_SMELL | 1 | `frontend/app/mis-cursos/page.tsx:116` | Move this component definition out of the parent component and pass data as props. |
| Mayor | `docker:S7031` | CODE_SMELL | 1 | `backend/Dockerfile:6` | Merge this RUN instruction with the consecutive ones. |
| Mayor | `typescript:S6481` | CODE_SMELL | 1 | `frontend/lib/auth-context.tsx:39` | The object passed as the value prop to the Context provider changes every render. To fix this consider wrapping it in a useMemo hook. |
| Mayor | `go:S1479` | CODE_SMELL | 1 | `backend/internal/platform/httpserver/respond.go:74` | Reduce the number of switch branches from 46 to at most 30. |
| Menor | `typescript:S6606` | CODE_SMELL | 4 | `frontend/components/BlockEditor.tsx:174` | Prefer using nullish coalescing operator (`??`) instead of a logical or (`\|\|`), as it is a safer operator. |
| Menor | `typescript:S6582` | CODE_SMELL | 2 | `frontend/app/page.tsx:200` | Prefer using an optional chain expression instead, as it's more concise and easier to read. |
| Menor | `typescript:S4084` | CODE_SMELL | 2 | `frontend/components/ReproductorHLS.tsx:127` | Media elements such as <audio> and <video> must have a <track> for captions. |
| Menor | `typescript:S6845` | CODE_SMELL | 2 | `frontend/components/OperacionEnVivo.tsx:138` | `tabIndex` should only be declared on interactive elements. |
| Menor | `typescript:S6594` | CODE_SMELL | 1 | `frontend/lib/actividad.ts:51` | Use the "RegExp.exec()" method instead. |
| Menor | `docker:S7018` | CODE_SMELL | 1 | `backend/Dockerfile:30` | Sort these package names alphanumerically. |
| Informativo | `go:S1135` | CODE_SMELL | 23 | `backend/internal/platform/postgres/exportacion_repo.go:12` | Complete the task associated to this TODO comment. |
| Informativo | `typescript:S1135` | CODE_SMELL | 4 | `frontend/lib/errores.ts:79` | Complete the task associated to this "TODO" comment. |

### Ubicaciones de los hallazgos Mayor o superior

| Severidad | Regla | Ubicaciones |
|---|---|---|
| Critico | `go:S3776` | `backend/cmd/seed/main.go:150`<br>`backend/cmd/seed/main.go:278`<br>`backend/internal/app/courses/courses.go:111`<br>`backend/internal/app/enrollments/enrollments.go:174`<br>`backend/internal/app/progreso/progreso.go:117`<br>`backend/internal/app/progreso/progreso.go:252`<br>`backend/internal/app/quizzes/quizzes.go:211`<br>`backend/internal/app/quizzes/quizzes.go:356`<br>`backend/internal/domain/course/course.go:205`<br>`backend/internal/domain/quiz/agregado.go:126`<br>`backend/internal/platform/antimalware/antimalware.go:114`<br>`backend/internal/platform/antimalware/antimalware.go:162`<br>`backend/internal/platform/httpserver/idempotency.go:54`<br>`backend/internal/platform/postgres/courses_repo.go:410`<br>`backend/internal/platform/postgres/migrate.go:22`<br>`backend/internal/platform/postgres/quizzes_repo.go:56` |
| Critico | `typescript:S2310` | `frontend/lib/markdown.ts:105`<br>`frontend/lib/markdown.ts:108`<br>`frontend/lib/markdown.ts:110`<br>`frontend/lib/markdown.ts:124`<br>`frontend/lib/markdown.ts:126`<br>`frontend/lib/markdown.ts:138`<br>`frontend/lib/markdown.ts:140`<br>`frontend/lib/markdown.ts:150`<br>`frontend/lib/markdown.ts:152`<br>`frontend/lib/markdown.ts:78`<br>`frontend/lib/markdown.ts:81`<br>`frontend/lib/markdown.ts:92`<br>`frontend/lib/markdown.ts:95` |
| Critico | `typescript:S2004` | `frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:123`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:131`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:135` |
| Critico | `go:S1192` | `backend/internal/app/auth/auth.go:179`<br>`backend/internal/platform/antimalware/antimalware.go:173`<br>`backend/internal/platform/httpserver/respond.go:41` |
| Critico | `typescript:S3776` | `frontend/components/BlockEditor.tsx:157`<br>`frontend/lib/carga.ts:230`<br>`frontend/lib/markdown.ts:57` |
| Mayor | `typescript:S6759` | `frontend/app/admin/layout.tsx:5`<br>`frontend/app/admin/page.tsx:177`<br>`frontend/app/admin/page.tsx:239`<br>`frontend/app/admin/page.tsx:407`<br>`frontend/app/admin/page.tsx:457`<br>`frontend/app/admin/page.tsx:543`<br>`frontend/app/cursos/[courseId]/recursos/[resourceId]/page.tsx:226`<br>`frontend/app/layout.tsx:21`<br>`frontend/app/mis-cursos/page.tsx:23`<br>`frontend/app/profesor/layout.tsx:6`<br>`frontend/app/profesor/page.tsx:130`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:213`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:335`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:364`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:418`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:462`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:518`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:748`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:832`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:910`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:411`<br>`frontend/app/restablecer-contrasena/page.tsx:43`<br>`frontend/components/BlockEditor.tsx:341`<br>`frontend/components/BlockEditor.tsx:41`<br>`frontend/components/BlockEditor.tsx:430`<br>`frontend/components/Coautoria.tsx:16`<br>`frontend/components/Foro.tsx:145`<br>`frontend/components/Foro.tsx:17`<br>`frontend/components/HistorialDeRevisiones.tsx:21`<br>`frontend/components/Icono.tsx:3`<br>`frontend/components/ListaPersonal.tsx:31`<br>`frontend/components/MarcoIncrustado.tsx:18`<br>`frontend/components/NavegacionDelCurso.tsx:51`<br>`frontend/components/NavegacionDelCurso.tsx:76`<br>`frontend/components/OperacionEnVivo.tsx:152`<br>`frontend/components/OperacionEnVivo.tsx:183`<br>`frontend/components/Portada.tsx:28`<br>`frontend/components/Portada.tsx:51`<br>`frontend/components/QuizPlayer.tsx:20`<br>`frontend/components/ReproductorHLS.tsx:27`<br>`frontend/components/SoloParaRol.tsx:13`<br>`frontend/components/TextoConFormato.tsx:10`<br>`frontend/components/TextoConFormato.tsx:21`<br>`frontend/components/VisorPDF.tsx:15`<br>`frontend/lib/auth-context.tsx:15`<br>`frontend/lib/i18n.tsx:92` |
| Mayor | `typescript:S6819` | `frontend/app/admin/page.tsx:353`<br>`frontend/app/admin/page.tsx:358`<br>`frontend/app/cuenta/sesiones/page.tsx:77`<br>`frontend/app/cursos/[courseId]/page.tsx:118`<br>`frontend/app/cursos/[courseId]/page.tsx:126`<br>`frontend/app/cursos/[courseId]/page.tsx:162`<br>`frontend/app/cursos/[courseId]/page.tsx:75`<br>`frontend/app/cursos/[courseId]/recursos/[resourceId]/page.tsx:107`<br>`frontend/app/cursos/[courseId]/recursos/[resourceId]/page.tsx:118`<br>`frontend/app/cursos/[courseId]/recursos/[resourceId]/page.tsx:252`<br>`frontend/app/insignias/[code]/page.tsx:71`<br>`frontend/app/insignias/[code]/page.tsx:86`<br>`frontend/app/insignias/[code]/page.tsx:90`<br>`frontend/app/page.tsx:161`<br>`frontend/app/page.tsx:164`<br>`frontend/app/profesor/page.tsx:119`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:128`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:155`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:195`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:327`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:680`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:695`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:706`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:727`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:797`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:856`<br>`frontend/app/profesor/versiones/[versionId]/previsualizacion/page.tsx:42`<br>`frontend/app/profesor/versiones/[versionId]/previsualizacion/page.tsx:68`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:198`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:209`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:221`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:467`<br>`frontend/components/ListaPersonal.tsx:69`<br>`frontend/components/MarcoIncrustado.tsx:24`<br>`frontend/components/MarcoIncrustado.tsx:46`<br>`frontend/components/OperacionEnVivo.tsx:83`<br>`frontend/components/QuizPlayer.tsx:151`<br>`frontend/components/QuizPlayer.tsx:163`<br>`frontend/components/QuizPlayer.tsx:227`<br>`frontend/components/SoloParaRol.tsx:19` |
| Mayor | `typescript:S6479` | `frontend/app/profesor/versiones/[versionId]/page.tsx:189`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:293`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:344`<br>`frontend/components/BlockEditor.tsx:368`<br>`frontend/components/BlockEditor.tsx:370`<br>`frontend/components/BlockEditor.tsx:458`<br>`frontend/components/TextoConFormato.tsx:100`<br>`frontend/components/TextoConFormato.tsx:101`<br>`frontend/components/TextoConFormato.tsx:106`<br>`frontend/components/TextoConFormato.tsx:33`<br>`frontend/components/TextoConFormato.tsx:41`<br>`frontend/components/TextoConFormato.tsx:70`<br>`frontend/components/TextoConFormato.tsx:76`<br>`frontend/components/TextoConFormato.tsx:78`<br>`frontend/components/TextoConFormato.tsx:99` |
| Mayor | `typescript:S3358` | `frontend/app/cursos/[courseId]/page.tsx:106`<br>`frontend/app/cursos/[courseId]/recursos/[resourceId]/page.tsx:253`<br>`frontend/app/profesor/page.tsx:208`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:650`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:652`<br>`frontend/components/BlockEditor.tsx:239`<br>`frontend/components/BlockEditor.tsx:242`<br>`frontend/components/BlockEditor.tsx:250`<br>`frontend/components/BlockEditor.tsx:258`<br>`frontend/components/BlockEditor.tsx:272`<br>`frontend/components/BlockEditor.tsx:277` |
| Mayor | `typescript:S4624` | `frontend/lib/api.ts:379`<br>`frontend/lib/api.ts:600` |
| Mayor | `typescript:S1854` | `frontend/app/admin/page.tsx:21` |
| Mayor | `typescript:S6478` | `frontend/app/mis-cursos/page.tsx:116` |
| Mayor | `docker:S7031` | `backend/Dockerfile:6` |
| Mayor | `typescript:S6481` | `frontend/lib/auth-context.tsx:39` |
| Mayor | `go:S1479` | `backend/internal/platform/httpserver/respond.go:74` |
