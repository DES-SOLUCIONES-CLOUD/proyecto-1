import { describe, expect, it } from "vitest";
import { isValidElement } from "react";

import { enLinea } from "../components/TextoConFormato";

describe("formato dentro de una linea", () => {
  it("deja el texto normal como texto", () => {
    expect(enLinea("hola mundo")).toEqual(["hola mundo"]);
  });

  it("convierte negrita, cursiva y codigo en elementos", () => {
    const partes = enLinea("es **importante** y *bonito* con `x = 1`");
    const elementos = partes.filter(isValidElement);
    expect(elementos.map((e) => e.type)).toEqual(["strong", "em", "code"]);
  });

  it("solo acepta enlaces http y https", () => {
    expect(enLinea("[malo](javascript:alert(1))").filter(isValidElement)).toEqual([]);
    expect(enLinea("[bueno](https://uniandes.edu.co)").filter(isValidElement)[0].type).toBe("a");
  });
});
