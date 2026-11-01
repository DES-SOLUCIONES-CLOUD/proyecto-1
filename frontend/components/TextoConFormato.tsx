"use client";

import type { ReactNode } from "react";
import { aBloques, type Block } from "../lib/markdown";

//muestra el texto de un recurso con su formato (titulos, listas, tablas...)
//antes se mostraba el markdown tal cual, con los ## y los ** a la vista
//no se usa dangerouslySetInnerHTML: todo se arma con elementos de react,
//asi nadie puede meter codigo html o javascript en el texto de un curso
export function TextoConFormato({ markdown }: { markdown: string }) {
  const bloques = aBloques(markdown);
  return (
    <article className="card texto-con-formato">
      {bloques.map((b) => (
        <Bloque key={b.id} bloque={b} />
      ))}
    </article>
  );
}

function Bloque({ bloque: b }: { bloque: Block }) {
  switch (b.type) {
    case "heading": {
      //el h1 ya es el titulo de la pagina, asi que los encabezados bajan un nivel
      if (b.level === 1) return <h2>{enLinea(b.content)}</h2>;
      if (b.level === 2) return <h3>{enLinea(b.content)}</h3>;
      return <h4>{enLinea(b.content)}</h4>;
    }
    case "list":
      return (
        <ul>
          {b.content.split("\n").map((linea, i) => (
            <li key={i}>{enLinea(linea)}</li>
          ))}
        </ul>
      );
    case "task":
      return (
        <ul style={{ listStyle: "none", paddingLeft: 0 }}>
          {b.content.split("\n").map((linea, i) => (
            <li key={i}>
              <input type="checkbox" checked={b.done?.[i] ?? false} readOnly aria-label={linea} /> {enLinea(linea)}
            </li>
          ))}
        </ul>
      );
    case "callout":
      return <blockquote className="warning-banner">{enLinea(b.content)}</blockquote>;
    case "code":
      return (
        <pre className="bloque-codigo">
          <code>{b.content}</code>
        </pre>
      );
    case "formula":
      return (
        <pre className="bloque-codigo" aria-label="LaTeX">
          <code>{b.content}</code>
        </pre>
      );
    case "table": {
      //la primera fila es el encabezado, las celdas van separadas por |
      const [cabecera, ...filas] = b.content.split("\n").map((f) => f.split("|"));
      return (
        <div style={{ overflowX: "auto" }}>
          <table>
            <thead>
              <tr>
                {cabecera.map((c, i) => (
                  <th key={i}>{enLinea(c)}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filas.map((fila, i) => (
                <tr key={i}>
                  {fila.map((c, j) => (
                    <td key={j}>{enLinea(c)}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
    }
    default:
      return <p style={{ whiteSpace: "pre-wrap" }}>{enLinea(b.content)}</p>;
  }
}

//formato dentro de una linea: **negrita**, *cursiva*, `codigo` y [enlace](https://...)
const PATRON_EN_LINEA = /(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`|\[[^\]]+\]\(https?:\/\/[^)\s]+\))/g;

export function enLinea(texto: string): ReactNode[] {
  //split con un grupo deja los pedazos con formato en las posiciones impares
  return texto.split(PATRON_EN_LINEA).map((pedazo, i) => {
    if (i % 2 === 0) return pedazo;
    if (pedazo.startsWith("**")) return <strong key={i}>{pedazo.slice(2, -2)}</strong>;
    if (pedazo.startsWith("`")) return <code key={i}>{pedazo.slice(1, -1)}</code>;
    if (pedazo.startsWith("*")) return <em key={i}>{pedazo.slice(1, -1)}</em>;
    //enlace: [texto](url). solo se aceptan http y https por seguridad
    const enlace = /^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/.exec(pedazo);
    if (enlace) {
      return (
        <a key={i} href={enlace[2]} target="_blank" rel="noopener noreferrer">
          {enlace[1]}
        </a>
      );
    }
    return pedazo;
  });
}
