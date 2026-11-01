# Datos de la demostración del frontend

Aquí están los datos sintéticos que usamos para la demostración del frontend de la entrega 3. Son reproducibles: se crean con un script que usa la API pública, igual que si alguien lo hiciera desde el navegador.

* `cursos.json`: las 3 cuentas de la demostración y 6 cursos de ejemplo, cada uno con módulos, lecciones en Markdown y un quiz.
* `poblar.mjs`: registra las cuentas y las activa con el administrador (rol de profesor o de estudiante, según el archivo). Después crea los cursos con el profesor dueño y los publica. Si se corre otra vez, se salta lo que ya existe.

Las cuentas que crea:

| Correo | Rol | Para qué |
|---|---|---|
| `laura.profesora@demo.mooc.local` | profesor | Crea en vivo el curso de Kubernetes |
| `carlos.profesor@demo.mooc.local` | profesor | Dueño de los cursos del catálogo; también es el "profesor ajeno" que no puede editar los cursos de Laura |
| `ana.estudiante@demo.mooc.local` | estudiante | Se inscribe, ve el contenido, presenta el quiz y gana la insignia |

Las contraseñas no están en el repositorio: se pasan al correrlo. Con Node 20 o más nuevo, en PowerShell:

```powershell
$env:MOOC_URL="https://136.82.109.164.sslip.io"
$env:ADMIN_EMAIL="<correo del administrador>"
$env:ADMIN_PASSWORD="<clave del administrador>"
$env:DEMO_PASSWORD="<clave para las cuentas de la demo, mínimo 10 caracteres>"
node data/catalogo/poblar.mjs
```

El curso de la demostración en vivo, "Kubernetes desde cero", no lo crea el script. Ese lo crea la profesora desde el navegador, porque el enunciado pide que la autoría se vea en la interfaz y no por llamadas a la API.
