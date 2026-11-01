//portada de colores para un curso
//los cursos no guardan foto, asi que la portada se dibuja: un fondo de color segun el curso,
//figuras de adorno y un icono segun la categoria (nube, codigo, datos, seguridad...)

//los 6 colores de portada, definidos en globals.css como --portada-1 ... --portada-6
const COLORES = 6;

//escoge un color a partir del titulo, asi cada curso tiene siempre el mismo
//(se mezclan las letras con el metodo fnv para que titulos parecidos no caigan en el mismo color)
export function colorDe(texto: string): number {
  let h = 2166136261;
  for (const letra of texto) {
    h ^= letra.charCodeAt(0);
    h = Math.imul(h, 16777619) >>> 0;
  }
  //revuelve los bits del final para que el resultado se reparta mejor entre los 6 colores
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0;
  return (h % COLORES) + 1;
}

type Tema = "nube" | "codigo" | "datos" | "seguridad" | "redes" | "diseno" | "libro";

//adivina el tema del curso mirando palabras de la categoria y del titulo
function temaDe(texto: string): Tema {
  const t = texto.toLowerCase();
  if (/(infra|nube|cloud|kubernetes|docker|devops|servidor)/.test(t)) return "nube";
  if (/(program|codigo|código|software|go\b|python|javascript|desarrollo)/.test(t)) return "codigo";
  if (/(dato|base|sql|anal|estad)/.test(t)) return "datos";
  if (/(segur|ciber|crypt|cript)/.test(t)) return "seguridad";
  if (/(red|network|internet|telecom)/.test(t)) return "redes";
  if (/(diseño|diseno|ux|ui\b|arte)/.test(t)) return "diseno";
  return "libro";
}

//dibujos sencillos en lineas blancas, uno por tema
function Icono({ tema }: { tema: Tema }) {
  const comun = {
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 3,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
  };
  switch (tema) {
    case "nube":
      return (
        <g {...comun}>
          <path d="M22 50h40a14 14 0 0 0 0-28 20 20 0 0 0-38-4A15 15 0 0 0 22 50z" />
          <path d="M34 60v8M48 60v8M62 60v8" />
          <rect x="28" y="68" width="40" height="10" rx="3" />
        </g>
      );
    case "codigo":
      return (
        <g {...comun}>
          <rect x="12" y="16" width="72" height="56" rx="8" />
          <path d="M36 36l-10 8 10 8M60 36l10 8-10 8M52 30l-8 28" />
        </g>
      );
    case "datos":
      return (
        <g {...comun}>
          <ellipse cx="48" cy="22" rx="26" ry="9" />
          <path d="M22 22v44c0 5 12 9 26 9s26-4 26-9V22M22 44c0 5 12 9 26 9s26-4 26-9" />
        </g>
      );
    case "seguridad":
      return (
        <g {...comun}>
          <path d="M48 12l30 11v20c0 18-13 31-30 37-17-6-30-19-30-37V23z" />
          <path d="M36 46l9 9 16-18" />
        </g>
      );
    case "redes":
      return (
        <g {...comun}>
          <circle cx="48" cy="20" r="8" />
          <circle cx="20" cy="66" r="8" />
          <circle cx="76" cy="66" r="8" />
          <path d="M43 27L25 59M53 27l18 32M28 66h40" />
        </g>
      );
    case "diseno":
      return (
        <g {...comun}>
          <circle cx="48" cy="44" r="30" />
          <circle cx="36" cy="34" r="5" />
          <circle cx="56" cy="30" r="5" />
          <circle cx="64" cy="48" r="5" />
          <path d="M44 74c-4-8 6-12 2-20" />
        </g>
      );
    default:
      return (
        <g {...comun}>
          <path d="M14 22c12-5 23-4 34 4 11-8 22-9 34-4v50c-12-5-23-4-34 4-11-8-22-9-34-4z" />
          <path d="M48 26v50" />
        </g>
      );
  }
}

//ancha es la version grande que va arriba en el detalle del curso
export function Portada({
  titulo,
  categoria,
  ancha = false,
}: {
  titulo: string;
  categoria?: string | null;
  ancha?: boolean;
}) {
  const color = colorDe(titulo);
  //primero manda la categoria; si no dice nada claro, se mira el titulo
  const porCategoria = temaDe(categoria ?? "");
  const tema = porCategoria !== "libro" ? porCategoria : temaDe(titulo);
  return (
    <div className={ancha ? "portada portada--ancha" : "portada"} data-color={color} aria-hidden="true">
      {/*figuras de adorno detras del icono*/}
      <span className="portada__circulo portada__circulo--grande" />
      <span className="portada__circulo portada__circulo--chico" />
      {categoria && <span className="portada__categoria">{categoria}</span>}
      <svg className="portada__icono" viewBox="0 0 96 88" width="96" height="88">
        <Icono tema={tema} />
      </svg>
    </div>
  );
}
