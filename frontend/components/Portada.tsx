//portada de colores para un curso
//los cursos no guardan foto: el profesor escoge una de las 8 portadas al crear el curso
//(degradado vivo + un patron de adorno). si no escoge, sale una automatica segun el titulo

//cuantas portadas hay para escoger, definidas en globals.css (.portada[data-portada="1"] ... "8")
export const PORTADAS = 8;

//portada automatica: se escoge a partir del titulo, asi cada curso tiene siempre la misma
//(se mezclan las letras con el metodo fnv para que titulos parecidos no caigan en la misma)
export function portadaAutomatica(texto: string): number {
  let h = 2166136261;
  for (const letra of texto) {
    h ^= letra.charCodeAt(0);
    h = Math.imul(h, 16777619) >>> 0;
  }
  //revuelve los bits del final para que el resultado se reparta mejor
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0;
  return (h % PORTADAS) + 1;
}

//la portada que se ve: la elegida si es valida, si no la automatica
export function portadaDe(titulo: string, elegida?: number | null): number {
  return elegida && elegida >= 1 && elegida <= PORTADAS ? elegida : portadaAutomatica(titulo);
}

//ancha es la version grande que va arriba en el detalle del curso
export function Portada({
  titulo,
  categoria,
  portada,
  ancha = false,
}: {
  titulo: string;
  categoria?: string | null;
  portada?: number | null;
  ancha?: boolean;
}) {
  return (
    <div
      className={ancha ? "portada portada--ancha" : "portada"}
      data-portada={portadaDe(titulo, portada)}
      aria-hidden="true"
    >
      {categoria && <span className="portada__categoria">{categoria}</span>}
    </div>
  );
}

//selector de portada para el formulario del curso: 8 muestras de color y "automatica"
export function ElegirPortada({
  valor,
  titulo,
  onCambio,
  disabled,
  etiqueta,
  textoAutomatica,
}: {
  valor: number;
  titulo: string;
  onCambio: (n: number) => void;
  disabled?: boolean;
  etiqueta: string;
  textoAutomatica: string;
}) {
  const opciones = [0, ...Array.from({ length: PORTADAS }, (_, i) => i + 1)];
  return (
    <fieldset className="elegir-portada" disabled={disabled}>
      <legend>{etiqueta}</legend>
      <div className="elegir-portada__opciones">
        {opciones.map((n) => (
          <label key={n} className="elegir-portada__opcion">
            <input
              type="radio"
              name="portada"
              value={n}
              checked={valor === n}
              onChange={() => onCambio(n)}
              className="visually-hidden"
            />
            {/*la muestra usa las mismas clases que la portada real*/}
            <span className="portada portada--muestra" data-portada={n === 0 ? portadaAutomatica(titulo) : n} />
            <span className="elegir-portada__nombre">{n === 0 ? textoAutomatica : n}</span>
          </label>
        ))}
      </div>
    </fieldset>
  );
}
