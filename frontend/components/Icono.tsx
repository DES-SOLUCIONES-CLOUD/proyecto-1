//iconos pequeños dibujados en svg, con el mismo grosor de linea
//se usan en vez de caracteres como ✓ o ✕, que cambian segun el sistema operativo
export function Icono({ nombre, tamano = 14 }: { nombre: "listo" | "cerrar"; tamano?: number }) {
  return (
    <svg
      width={tamano}
      height={tamano}
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      style={{ verticalAlign: "-0.15em", flex: "none" }}
    >
      {nombre === "listo" ? <path d="M3 8.5l3.2 3.2L13 4.8" /> : <path d="M4 4l8 8M12 4l-8 8" />}
    </svg>
  );
}
