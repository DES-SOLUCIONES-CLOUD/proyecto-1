"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";

import enJson from "./i18n/en.json";
import es from "./i18n/es.json";

// Internacionalización de la interfaz (alcance opcional 5.2).
//
// El catálogo va tipado contra las claves del español, que es el idioma de
// origen: así añadir un texto sin traducirlo es un error de compilación y no
// una cadena que aparece en español dentro de una pantalla en inglés.
//
// Lo que no se traduce aquí es el contenido de los cursos. Ese lo escribe cada
// profesor y ya tiene su propio idioma declarado en la versión
// (`course_versions.language`): traducirlo automáticamente sería inventar
// material didáctico. Por el mismo motivo se dejan sin traducir los valores
// que vienen de la base y se enseñan tal cual —el rol de una cuenta, el estado
// de un intento, la acción de una entrada de auditoría—: son identificadores
// del dominio, y traducirlos rompería la correspondencia con lo que la API
// acepta y con lo que el administrador escribe en el filtro.

export const IDIOMAS = ["es", "en"] as const;
export type Idioma = (typeof IDIOMAS)[number];

export const NOMBRES_DE_IDIOMA: Record<Idioma, string> = {
  es: "Español",
  en: "English",
};

/**
 * LOCALES es la etiqueta con la que se formatean fechas y horas.
 *
 * Va aparte del idioma porque no coinciden: el catálogo distingue "es" de
 * "en", pero una fecha necesita región para elegir entre 14/09/2026 y
 * 9/14/2026, y equivocarse ahí no es un detalle estético.
 */
export const LOCALES: Record<Idioma, string> = {
  es: "es-CO",
  en: "en-US",
};

// los catalogos estan en json al lado de este archivo porque son datos,
// no codigo. asi quien traduce no tiene que tocar typescript, y los dos
// bloques de 470 lineas ya no cuentan como codigo duplicado

/** Clave es cualquiera de los textos del catálogo de origen. */
export type Clave = keyof typeof es;

// con este tipo typescript avisa si falta una clave en ingles
// que no sobre ninguna lo revisa i18n.test.ts
const en: Record<Clave, string> = enJson;

const CATALOGOS: Record<Idioma, Record<Clave, string>> = { es, en };

const CLAVE_ALMACEN = "mooc.idioma";

/** Traducir es la firma de t, para tiparla donde se pasa como argumento. */
export type Traducir = (clave: Clave, valores?: Record<string, string | number>) => string;

interface Contexto {
  idioma: Idioma;
  /** locale es la etiqueta con la que formatear fechas, horas y números. */
  locale: string;
  cambiar: (idioma: Idioma) => void;
  /** t traduce una clave, sustituyendo los marcadores {nombre}. */
  t: Traducir;
}

const I18nContext = createContext<Contexto | null>(null);

/**
 * idiomaInicial elige el idioma de arranque.
 *
 * Manda lo que la persona eligió; si no eligió nada, el del navegador; y si
 * tampoco, español, que es el idioma de origen del contenido.
 */
function idiomaInicial(): Idioma {
  if (typeof window === "undefined") return "es";
  try {
    const guardado = localStorage.getItem(CLAVE_ALMACEN);
    if (guardado && (IDIOMAS as readonly string[]).includes(guardado)) {
      return guardado as Idioma;
    }
  } catch {
    /* sin localStorage se usa el del navegador */
  }
  const navegador = navigator.language?.slice(0, 2);
  return (IDIOMAS as readonly string[]).includes(navegador) ? (navegador as Idioma) : "es";
}

export function I18nProvider({ children }: { children: React.ReactNode }) {
  // Se arranca siempre en español y se ajusta tras montar: leer localStorage o
  // navigator durante el render del servidor produce una hidratación distinta
  // de la que sirvió el servidor, y React lo descarta con un aviso.
  const [idioma, setIdioma] = useState<Idioma>("es");

  useEffect(() => {
    setIdioma(idiomaInicial());
  }, []);

  useEffect(() => {
    document.documentElement.lang = idioma;
  }, [idioma]);

  const cambiar = useCallback((nuevo: Idioma) => {
    setIdioma(nuevo);
    try {
      localStorage.setItem(CLAVE_ALMACEN, nuevo);
    } catch {
      /* la elección no sobrevivirá a la recarga, pero la sesión sí */
    }
  }, []);

  const t = useCallback<Traducir>(
    (clave, valores) => {
      const texto = CATALOGOS[idioma][clave] ?? CATALOGOS.es[clave] ?? clave;
      if (!valores) return texto;
      return Object.entries(valores).reduce(
        (acc, [nombre, valor]) => acc.replaceAll(`{${nombre}}`, String(valor)),
        texto,
      );
    },
    [idioma],
  );

  const valor = useMemo(
    () => ({ idioma, locale: LOCALES[idioma], cambiar, t }),
    [idioma, cambiar, t],
  );
  return <I18nContext.Provider value={valor}>{children}</I18nContext.Provider>;
}

export function useI18n(): Contexto {
  const ctx = useContext(I18nContext);
  if (!ctx) {
    throw new Error("useI18n debe usarse dentro de I18nProvider");
  }
  return ctx;
}

/**
 * useTraductorEstable devuelve un traductor cuya identidad no cambia al
 * cambiar de idioma.
 *
 * Es para traducir dentro de un efecto que no debe volver a ejecutarse solo
 * porque alguien eligió otro idioma. `t` cambia con el idioma, así que
 * declararlo como dependencia relanza el efecto: eso recargaría el catálogo
 * perdiendo los filtros aplicados, o volvería a gastar el token de un enlace
 * de verificación, que es de un solo uso. Nadie pidió eso al pulsar
 * "English".
 *
 * A cambio, un mensaje ya escrito en pantalla se queda en el idioma en que se
 * generó. Es un texto concreto sobre algo que ya pasó, no una etiqueta de la
 * interfaz, y desaparece en cuanto se reintenta la acción.
 */
export function useTraductorEstable(): Traducir {
  const { t } = useI18n();
  const actual = useRef(t);
  // La ref se actualiza en un efecto, no durante el render: con el render
  // concurrente React puede descartar un render a medias, y una escritura
  // hecha ahí se habría aplicado igual.
  useEffect(() => {
    actual.current = t;
  }, [t]);
  return useCallback<Traducir>((clave, valores) => actual.current(clave, valores), []);
}
