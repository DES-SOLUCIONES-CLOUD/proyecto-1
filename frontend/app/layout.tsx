import type { Metadata } from "next";
//letras de la plataforma, instaladas como paquete para no depender de google al cargar
import "@fontsource/plus-jakarta-sans/400.css";
import "@fontsource/plus-jakarta-sans/500.css";
import "@fontsource/plus-jakarta-sans/600.css";
import "@fontsource/plus-jakarta-sans/700.css";
import "@fontsource/bricolage-grotesque/600.css";
import "@fontsource/bricolage-grotesque/700.css";
import "@fontsource/bricolage-grotesque/800.css";
import "./globals.css";
import { AuthProvider } from "@/lib/auth-context";
import { I18nProvider } from "@/lib/i18n";
import { NavBar } from "@/components/NavBar";
import { SaltarAlContenido } from "@/components/SaltarAlContenido";
import { PieDePagina } from "@/components/PieDePagina";

export const metadata: Metadata = {
  title: "Plataforma MOOC",
  description: "Plataforma web de cursos masivos abiertos en línea",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  // El atributo lang lo actualiza I18nProvider cuando la persona cambia de
  // idioma: un lector de pantalla necesita saber en qué idioma está el texto
  // que va a pronunciar. Aquí queda el idioma de origen, que es con el que se
  // sirve la primera carga.
  return (
    <html lang="es">
      <body>
        <I18nProvider>
          <SaltarAlContenido />
          <AuthProvider>
            <NavBar />
            <main id="main-content" className="container">
              {children}
            </main>
            <PieDePagina />
          </AuthProvider>
        </I18nProvider>
      </body>
    </html>
  );
}
