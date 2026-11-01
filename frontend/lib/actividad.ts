//traduce una peticion de la api (metodo + ruta) a algo que se entienda en el panel
//por ejemplo "POST /api/v1/enrollments" -> "Se inscribe en un curso"

import type { Clave } from "./i18n";

const UUID = "[0-9a-f-]{36}";

//cada regla: metodo, patron de la ruta y la clave del texto que la describe
const REGLAS: [string, RegExp, Clave][] = [
  ["POST", /^\/api\/v1\/auth\/login$/, "actividad.login"],
  ["POST", /^\/api\/v1\/auth\/logout$/, "actividad.logout"],
  ["POST", /^\/api\/v1\/auth\/register$/, "actividad.registro"],
  ["GET", /^\/api\/v1\/auth\/me$/, "actividad.quienSoy"],
  ["GET", /^\/api\/v1\/catalog$/, "actividad.catalogo"],
  ["GET", new RegExp(`^/api/v1/catalog/${UUID}$`), "actividad.detalleCurso"],
  ["POST", /^\/api\/v1\/enrollments$/, "actividad.inscripcion"],
  ["GET", /^\/api\/v1\/enrollments\/mine$/, "actividad.misCursos"],
  ["GET", new RegExp(`^/api/v1/enrollments/${UUID}/progress$`), "actividad.avance"],
  ["GET", new RegExp(`^/api/v1/resources/${UUID}/content$`), "actividad.abreRecurso"],
  ["POST", new RegExp(`^/api/v1/resources/${UUID}/progress$`), "actividad.registraAvance"],
  ["PUT", new RegExp(`^/api/v1/resources/${UUID}/position$`), "actividad.guardaPosicion"],
  ["POST", new RegExp(`^/api/v1/resources/${UUID}/quiz/attempts$`), "actividad.empiezaQuiz"],
  ["PUT", new RegExp(`^/api/v1/quiz/attempts/${UUID}/answers$`), "actividad.respondeQuiz"],
  ["POST", new RegExp(`^/api/v1/quiz/attempts/${UUID}/submit$`), "actividad.enviaQuiz"],
  ["GET", /^\/api\/v1\/badges\/mine$/, "actividad.insignias"],
  ["POST", /^\/api\/v1\/courses$/, "actividad.creaCurso"],
  ["GET", /^\/api\/v1\/courses\/mine$/, "actividad.cursosDelProfesor"],
  ["PATCH", new RegExp(`^/api/v1/courses/versions/${UUID}$`), "actividad.datosCurso"],
  ["POST", new RegExp(`^/api/v1/courses/versions/${UUID}/modules$`), "actividad.creaModulo"],
  ["POST", new RegExp(`^/api/v1/courses/versions/${UUID}/modules/${UUID}/units$`), "actividad.creaUnidad"],
  ["POST", new RegExp(`^/api/v1/courses/versions/${UUID}/units/${UUID}/resources$`), "actividad.creaRecurso"],
  ["POST", /\/(upload-url|multipart\/initiate|multipart\/part-url)$/, "actividad.subiendo"],
  ["POST", /\/(confirm-upload|multipart\/complete)$/, "actividad.subidaTerminada"],
  ["PUT", new RegExp(`^/api/v1/courses/versions/${UUID}/resources/${UUID}/quiz$`), "actividad.guardaQuiz"],
  ["POST", new RegExp(`^/api/v1/courses/versions/${UUID}/publish$`), "actividad.publica"],
  ["POST", new RegExp(`^/api/v1/courses/${UUID}/unpublish$`), "actividad.despublica"],
  ["POST", new RegExp(`^/api/v1/courses/${UUID}/update-draft$`), "actividad.nuevaVersion"],
  ["POST", /^\/api\/v1\/admin\/users$/, "actividad.creaCuenta"],
];

//devuelve la clave del texto, o null si no hay una descripcion para esa ruta
export function describirPeticion(metodo: string, ruta: string): Clave | null {
  for (const [m, patron, clave] of REGLAS) {
    if (m === metodo && patron.test(ruta)) return clave;
  }
  return null;
}

//saca el id del recurso de una ruta de subida, para buscar el archivo en el bucket
export function recursoDeLaRuta(ruta: string): string | null {
  const m = ruta.match(new RegExp(`/resources/(${UUID})/`));
  return m ? m[1] : null;
}
