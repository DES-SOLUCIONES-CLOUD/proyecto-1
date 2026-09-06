import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Genera un servidor autocontenido en .next/standalone, que es lo que copia
  // la imagen de Docker para mantenerla liviana.
  output: "standalone",
};

export default nextConfig;
