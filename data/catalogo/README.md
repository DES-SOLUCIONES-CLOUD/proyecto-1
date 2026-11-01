# Datos de la demostración del frontend

Aquí están los datos sintéticos que usamos para la demostración del frontend de la entrega 3. Son reproducibles: se crean con un script que usa la API pública, igual que si alguien lo hiciera desde el navegador.

* `cursos.json`: las cuentas de la demostración y 6 cursos de temas variados. Tienen distinto largo (1 o 2 módulos), distintos tipos de recurso (texto, video, imagen, PDF) y quizzes de 2 a 6 preguntas. Cada curso trae una portada elegida.
* `medios/`: los archivos de esos cursos (2 videos cortos, 4 imágenes y 3 PDF, todos de menos de 2,5 MB).
* `poblar.mjs`: hace lo mismo que alguien haría en el navegador.
  1. El administrador crea las cuentas ya activas.
  2. El profesor dueño crea cada curso con sus módulos, unidades y lecciones.
  3. Sube los archivos directo al bucket y espera a que los workers los procesen.
  4. Define los quizzes y publica.

  Si se corre otra vez, se salta lo que ya existe.

Las cuentas que crea:

| Correo | Rol | Para qué |
|---|---|---|
| `laura@mooc.test` | profesor | Crea en vivo el curso de Kubernetes |
| `carlos@mooc.test` | profesor | Dueño de los cursos del catálogo; es el "profesor ajeno" que no puede editar los cursos de Laura |
| `ana@mooc.test` | estudiante | Se inscribe, ve el contenido, presenta el quiz y gana la insignia |
| `luis@mooc.test` | estudiante | Segundo estudiante, para ver qué pasa cuando sale una versión nueva del curso |

`.test` es un dominio reservado: estos correos no existen fuera de la plataforma.

Las contraseñas no están en el repositorio: se pasan al correrlo. Con Node 20 o más nuevo, en PowerShell:

```powershell
$env:MOOC_URL="https://136.82.109.164.sslip.io"
$env:ADMIN_EMAIL="<correo del administrador>"
$env:ADMIN_PASSWORD="<clave del administrador>"
$env:DEMO_PASSWORD="<clave para las cuentas de la demo>"
node data/catalogo/poblar.mjs
```

El curso de la demostración en vivo, "Kubernetes desde cero", no lo crea el script. Ese lo crea la profesora desde el navegador, porque el enunciado pide que la autoría se vea en la interfaz y no por llamadas a la API.
