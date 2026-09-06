# Frontend

Next.js 16 (App Router) con React 19, TypeScript y Tailwind 4. El código de la
aplicación vive en `src/app/`.

La forma normal de ejecutarlo es junto al resto del stack, desde la raíz del
repositorio:

```bash
docker compose up --build
```

Queda disponible en http://localhost:3000.

Para desarrollo con recarga en caliente, con Node 20.9 o superior instalado:

```bash
npm install
npm run dev
```

Ver el [README de la raíz](../README.md) para la arquitectura completa del
proyecto y el resto de los servicios.
