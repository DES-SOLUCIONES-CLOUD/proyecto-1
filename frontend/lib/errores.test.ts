import { describe, expect, it } from "vitest";

import { ApiError } from "./api";
import { mensajeDeError, motivoDePublicacion, sinPrefijo } from "./errores";
import type { Traducir } from "./i18n";
import es from "./i18n/es.json";

//traductor de mentiras para la prueba: usa el catalogo en español
const t: Traducir = (clave, valores) => {
  let texto: string = es[clave];
  for (const [nombre, valor] of Object.entries(valores ?? {})) {
    texto = texto.replace(`{${nombre}}`, String(valor));
  }
  return texto;
};

describe("mensajes de error", () => {
  it("quita el prefijo tecnico del backend", () => {
    expect(sinPrefijo("quiz: el intento expiró")).toBe("el intento expiró");
    expect(sinPrefijo("Hola")).toBe("Hola");
  });

  it("usa el mensaje traducido cuando conoce el codigo", () => {
    const e = new ApiError(409, "max_attempts_reached", "quiz: se alcanzó el número máximo de intentos");
    expect(mensajeDeError(e, t, "quiz.errorAbrir")).toBe(es["error.max_attempts_reached"]);
  });

  it("si no conoce el codigo muestra el mensaje sin prefijo", () => {
    const e = new ApiError(400, "otro_codigo", "courses: algo raro");
    expect(mensajeDeError(e, t, "quiz.errorAbrir")).toBe("algo raro");
  });

  it("avisa cuando no hay conexion", () => {
    expect(mensajeDeError(new TypeError("Failed to fetch"), t, "quiz.errorAbrir")).toBe(es["error.red"]);
  });

  it("traduce los motivos de publicacion con los nombres", () => {
    const motivo = 'course: todo módulo debe tener al menos una unidad: módulo "Intro"';
    expect(motivoDePublicacion(motivo, t)).toBe("El módulo «Intro» no tiene unidades. Agrega al menos una.");
  });
});
