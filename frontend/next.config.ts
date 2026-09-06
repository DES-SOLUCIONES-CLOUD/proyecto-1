import type { NextConfig } from "next";

<<<<<<< HEAD
const nextConfig: NextConfig = {
  // Genera un servidor autocontenido en .next/standalone, que es lo que copia
  // la imagen de Docker para mantenerla liviana.
  output: "standalone",
=======
const apiInternalUrl =
  process.env.API_INTERNAL_URL ?? "http://localhost:8080/api/v1";

const nextConfig: NextConfig = {
  // Salida autocontenida: la imagen de produccion no necesita node_modules.
  output: "standalone",
  reactStrictMode: true,
  poweredByHeader: false,

  async rewrites() {
    // El navegador llama a /api/v1/* del mismo origen y Next lo reenvia a la
    // API en Go, evitando CORS y manteniendo las cookies de sesion en SameSite.
    return [
      {
        source: "/api/v1/:ruta*",
        destination: `${apiInternalUrl.replace(/\/$/, "")}/:ruta*`,
      },
    ];
  },
>>>>>>> e92b21c23e2cbfebb4f616a5ad789ab8d34f19d3
};

export default nextConfig;
