## SonarQube: commit `4e1c008`

Puerta de calidad: **OK** (http://localhost:9000)

| Metrica | Valor |
|---|---|
| Lineas de codigo | 17529 |
| Duplicacion (%) | 0.4 |
| Bloques duplicados | 6 |
| Mantenibilidad | A |
| Deuda tecnica (min) | 958 |
| Ratio de deuda (%) | 0.2 |
| Confiabilidad | A |
| Seguridad | A |
| Bugs | 0 |
| Vulnerabilidades | 0 |
| Code smells | 155 |
| Security hotspots | 6 |
| Cobertura (%) | 30.6 |

| Condicion | Umbral | Medido | Estado |
|---|---|---|---|
| sqale_rating | GT 3 | 1 | OK |
| duplicated_lines_density | GT 20 | 0.4 | OK |

### Hallazgos abiertos: 155

| Severidad | Cantidad |
|---|---|
| Bloqueante | 0 |
| Critico | 38 |
| Mayor | 85 |
| Menor | 9 |
| Informativo | 23 |

### Inventario por regla

| Severidad | Regla | Tipo | Casos | Ejemplo (archivo:linea) | Mensaje |
|---|---|---|---|---|---|
| Critico | `go:S3776` | CODE_SMELL | 16 | `backend/internal/platform/antimalware/antimalware.go:162` | Refactor this method to reduce its Cognitive Complexity from 19 to the 15 allowed. |
| Critico | `typescript:S2310` | CODE_SMELL | 13 | `frontend/lib/markdown.ts:105` | Remove this assignment of "i". |
| Critico | `typescript:S2004` | CODE_SMELL | 3 | `frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:107` | Refactor this code to not nest functions more than 4 levels deep. |
| Critico | `go:S1192` | CODE_SMELL | 3 | `backend/internal/platform/antimalware/antimalware.go:173` | Define a constant instead of duplicating this literal "%w: %v" 6 times. |
| Critico | `typescript:S3776` | CODE_SMELL | 3 | `frontend/lib/carga.ts:218` | Refactor this function to reduce its Cognitive Complexity from 18 to the 15 allowed. |
| Mayor | `typescript:S6759` | CODE_SMELL | 33 | `frontend/components/Foro.tsx:16` | Mark the props of the component as read-only. |
| Mayor | `typescript:S6819` | CODE_SMELL | 30 | `frontend/app/profesor/versiones/[versionId]/page.tsx:105` | Use <output> instead of the "status" role to ensure accessibility across all devices. |
| Mayor | `typescript:S3358` | CODE_SMELL | 10 | `frontend/components/BlockEditor.tsx:266` | Extract this nested ternary operation into an independent statement. |
| Mayor | `typescript:S6479` | CODE_SMELL | 6 | `frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:274` | Do not use Array index in keys |
| Mayor | `typescript:S4624` | CODE_SMELL | 2 | `frontend/lib/api.ts:368` | Refactor this code to not use nested template literals. |
| Mayor | `typescript:S1854` | CODE_SMELL | 1 | `frontend/app/admin/page.tsx:20` | Remove this useless assignment to variable "locale". |
| Mayor | `docker:S7031` | CODE_SMELL | 1 | `backend/Dockerfile:6` | Merge this RUN instruction with the consecutive ones. |
| Mayor | `typescript:S6481` | CODE_SMELL | 1 | `frontend/lib/auth-context.tsx:39` | The object passed as the value prop to the Context provider changes every render. To fix this consider wrapping it in a useMemo hook. |
| Mayor | `go:S1479` | CODE_SMELL | 1 | `backend/internal/platform/httpserver/respond.go:74` | Reduce the number of switch branches from 46 to at most 30. |
| Menor | `typescript:S6606` | CODE_SMELL | 4 | `frontend/components/BlockEditor.tsx:174` | Prefer using nullish coalescing operator (`??`) instead of a logical or (`\|\|`), as it is a safer operator. |
| Menor | `typescript:S6582` | CODE_SMELL | 2 | `frontend/app/page.tsx:190` | Prefer using an optional chain expression instead, as it's more concise and easier to read. |
| Menor | `typescript:S4084` | CODE_SMELL | 2 | `frontend/components/ReproductorHLS.tsx:127` | Media elements such as <audio> and <video> must have a <track> for captions. |
| Menor | `docker:S7018` | CODE_SMELL | 1 | `backend/Dockerfile:27` | Sort these package names alphanumerically. |
| Informativo | `go:S1135` | CODE_SMELL | 22 | `backend/internal/platform/postgres/exportacion_repo.go:12` | Complete the task associated to this TODO comment. |
| Informativo | `typescript:S1135` | CODE_SMELL | 1 | `frontend/components/ReproductorHLS.tsx:138` | Complete the task associated to this "TODO" comment. |

### Ubicaciones de los hallazgos Mayor o superior

| Severidad | Regla | Ubicaciones |
|---|---|---|
| Critico | `go:S3776` | `backend/cmd/seed/main.go:150`<br>`backend/cmd/seed/main.go:278`<br>`backend/internal/app/courses/courses.go:110`<br>`backend/internal/app/enrollments/enrollments.go:174`<br>`backend/internal/app/progreso/progreso.go:117`<br>`backend/internal/app/progreso/progreso.go:252`<br>`backend/internal/app/quizzes/quizzes.go:211`<br>`backend/internal/app/quizzes/quizzes.go:356`<br>`backend/internal/domain/course/course.go:201`<br>`backend/internal/domain/quiz/agregado.go:126`<br>`backend/internal/platform/antimalware/antimalware.go:114`<br>`backend/internal/platform/antimalware/antimalware.go:162`<br>`backend/internal/platform/httpserver/idempotency.go:54`<br>`backend/internal/platform/postgres/courses_repo.go:410`<br>`backend/internal/platform/postgres/migrate.go:22`<br>`backend/internal/platform/postgres/quizzes_repo.go:56` |
| Critico | `typescript:S2310` | `frontend/lib/markdown.ts:105`<br>`frontend/lib/markdown.ts:108`<br>`frontend/lib/markdown.ts:110`<br>`frontend/lib/markdown.ts:124`<br>`frontend/lib/markdown.ts:126`<br>`frontend/lib/markdown.ts:138`<br>`frontend/lib/markdown.ts:140`<br>`frontend/lib/markdown.ts:150`<br>`frontend/lib/markdown.ts:152`<br>`frontend/lib/markdown.ts:78`<br>`frontend/lib/markdown.ts:81`<br>`frontend/lib/markdown.ts:92`<br>`frontend/lib/markdown.ts:95` |
| Critico | `typescript:S2004` | `frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:107`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:115`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:119` |
| Critico | `go:S1192` | `backend/internal/app/auth/auth.go:179`<br>`backend/internal/platform/antimalware/antimalware.go:173`<br>`backend/internal/platform/httpserver/respond.go:41` |
| Critico | `typescript:S3776` | `frontend/components/BlockEditor.tsx:156`<br>`frontend/lib/carga.ts:218`<br>`frontend/lib/markdown.ts:57` |
| Mayor | `typescript:S6759` | `frontend/app/admin/page.tsx:173`<br>`frontend/app/admin/page.tsx:235`<br>`frontend/app/admin/page.tsx:403`<br>`frontend/app/admin/page.tsx:453`<br>`frontend/app/admin/page.tsx:537`<br>`frontend/app/cursos/[courseId]/recursos/[resourceId]/page.tsx:223`<br>`frontend/app/layout.tsx:13`<br>`frontend/app/profesor/page.tsx:104`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:146`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:251`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:280`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:321`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:353`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:396`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:563`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:647`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:725`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:392`<br>`frontend/app/restablecer-contrasena/page.tsx:42`<br>`frontend/components/BlockEditor.tsx:335`<br>`frontend/components/BlockEditor.tsx:40`<br>`frontend/components/BlockEditor.tsx:424`<br>`frontend/components/Coautoria.tsx:15`<br>`frontend/components/Foro.tsx:144`<br>`frontend/components/Foro.tsx:16`<br>`frontend/components/HistorialDeRevisiones.tsx:20`<br>`frontend/components/ListaPersonal.tsx:31`<br>`frontend/components/MarcoIncrustado.tsx:18`<br>`frontend/components/QuizPlayer.tsx:18`<br>`frontend/components/ReproductorHLS.tsx:27`<br>`frontend/components/VisorPDF.tsx:15`<br>`frontend/lib/auth-context.tsx:15`<br>`frontend/lib/i18n.tsx:92` |
| Mayor | `typescript:S6819` | `frontend/app/admin/page.tsx:349`<br>`frontend/app/admin/page.tsx:354`<br>`frontend/app/cuenta/sesiones/page.tsx:76`<br>`frontend/app/cursos/[courseId]/page.tsx:110`<br>`frontend/app/cursos/[courseId]/page.tsx:86`<br>`frontend/app/cursos/[courseId]/recursos/[resourceId]/page.tsx:102`<br>`frontend/app/cursos/[courseId]/recursos/[resourceId]/page.tsx:113`<br>`frontend/app/cursos/[courseId]/recursos/[resourceId]/page.tsx:249`<br>`frontend/app/insignias/[code]/page.tsx:71`<br>`frontend/app/insignias/[code]/page.tsx:86`<br>`frontend/app/insignias/[code]/page.tsx:90`<br>`frontend/app/page.tsx:152`<br>`frontend/app/page.tsx:155`<br>`frontend/app/profesor/page.tsx:93`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:105`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:518`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:527`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:612`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:671`<br>`frontend/app/profesor/versiones/[versionId]/previsualizacion/page.tsx:40`<br>`frontend/app/profesor/versiones/[versionId]/previsualizacion/page.tsx:66`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:182`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:192`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:202`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:448`<br>`frontend/components/ListaPersonal.tsx:69`<br>`frontend/components/MarcoIncrustado.tsx:24`<br>`frontend/components/MarcoIncrustado.tsx:46`<br>`frontend/components/QuizPlayer.tsx:110`<br>`frontend/components/QuizPlayer.tsx:124` |
| Mayor | `typescript:S3358` | `frontend/app/cursos/[courseId]/recursos/[resourceId]/page.tsx:250`<br>`frontend/app/profesor/page.tsx:170`<br>`frontend/app/profesor/versiones/[versionId]/page.tsx:491`<br>`frontend/components/BlockEditor.tsx:233`<br>`frontend/components/BlockEditor.tsx:236`<br>`frontend/components/BlockEditor.tsx:244`<br>`frontend/components/BlockEditor.tsx:252`<br>`frontend/components/BlockEditor.tsx:266`<br>`frontend/components/BlockEditor.tsx:271`<br>`frontend/components/Coautoria.tsx:51` |
| Mayor | `typescript:S6479` | `frontend/app/profesor/versiones/[versionId]/page.tsx:117`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:274`<br>`frontend/app/profesor/versiones/[versionId]/quiz/[resourceId]/page.tsx:325`<br>`frontend/components/BlockEditor.tsx:362`<br>`frontend/components/BlockEditor.tsx:364`<br>`frontend/components/BlockEditor.tsx:452` |
| Mayor | `typescript:S4624` | `frontend/lib/api.ts:368`<br>`frontend/lib/api.ts:584` |
| Mayor | `typescript:S1854` | `frontend/app/admin/page.tsx:20` |
| Mayor | `docker:S7031` | `backend/Dockerfile:6` |
| Mayor | `typescript:S6481` | `frontend/lib/auth-context.tsx:39` |
| Mayor | `go:S1479` | `backend/internal/platform/httpserver/respond.go:74` |
