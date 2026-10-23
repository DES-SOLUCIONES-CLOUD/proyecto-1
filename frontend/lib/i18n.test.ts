import { describe, expect, it } from "vitest";

import en from "./i18n/en.json";
import es from "./i18n/es.json";

// los catalogos pasaron de i18n.tsx a json. typescript sigue avisando si falta
// una clave en ingles, pero ya no si sobra una, asi que eso se revisa aqui

describe("catálogos de idioma", () => {
  it("tienen exactamente las mismas claves", () => {
    expect(Object.keys(en).sort()).toEqual(Object.keys(es).sort());
  });

  it("no dejan ningún texto vacío", () => {
    for (const catalogo of [es, en]) {
      const vacias = Object.entries(catalogo).filter(([, texto]) => texto.trim() === "");
      expect(vacias).toEqual([]);
    }
  });

  it("conservan los marcadores {nombre} en la traducción", () => {
    // si se pierde un marcador en ingles, en pantalla sale "{email}" tal cual
    const marcadores = (texto: string) => (texto.match(/\{[a-zA-Z]+\}/g) ?? []).sort();
    const distintos = Object.keys(es).filter(
      (clave) =>
        JSON.stringify(marcadores(es[clave as keyof typeof es])) !==
        JSON.stringify(marcadores(en[clave as keyof typeof en])),
    );
    expect(distintos).toEqual([]);
  });
});
