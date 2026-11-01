import { ApiError } from "./api";
import type { Clave, Traducir } from "./i18n";

//codigos de error de la api que tienen su propio mensaje en es.json y en.json
//la clave del mensaje es "error." + el codigo, por ejemplo "error.forbidden"
const CODIGOS_CON_MENSAJE = new Set([
  "account_not_active",
  "already_enrolled",
  "attempt_already_submitted",
  "attempt_expired",
  "attempt_not_open",
  "checksum_mismatch",
  "course_not_published",
  "course_not_published_yet",
  "course_published",
  "csrf_token_mismatch",
  "email_in_use",
  "forbidden",
  "idempotency_in_flight",
  "internal_error",
  "invalid_credentials",
  "invalid_or_expired_token",
  "last_admin_protected",
  "malware_detected",
  "max_attempts_reached",
  "media_not_ready",
  "mime_mismatch",
  "not_enrolled",
  "not_found",
  "queue_unavailable",
  "rate_limited",
  "scanner_unavailable",
  "session_not_found",
  "unauthenticated",
  "upload_missing",
  "version_not_draft",
  "weak_password",
]);

//el backend escribe los errores asi: "quiz: se alcanzo el maximo"
//esto le quita el "quiz: " para que el usuario no vea cosas tecnicas
export function sinPrefijo(texto: string): string {
  return texto.replace(/^([a-z]+: )+/, "");
}

//convierte cualquier error en un mensaje claro y en el idioma elegido
//porDefecto es el mensaje que se usa si no sabemos que paso
export function mensajeDeError(e: unknown, t: Traducir, porDefecto: Clave): string {
  if (e instanceof ApiError) {
    if (CODIGOS_CON_MENSAJE.has(e.code)) {
      return t(`error.${e.code}` as Clave);
    }
    //si la api manda detalles (por ejemplo que campo falta) se muestran tambien
    const detalles = (e.details ?? []).map(sinPrefijo);
    return [sinPrefijo(e.message), ...detalles].join(" ");
  }
  //fetch lanza TypeError cuando no hay internet o el servidor no responde
  if (e instanceof TypeError) {
    return t("error.red");
  }
  return t(porDefecto);
}

//motivos por los que no se puede publicar, tal como los escribe el backend
//cada uno se cambia por un mensaje traducido que dice que hacer
const MOTIVOS_DE_PUBLICACION: ReadonlyArray<readonly [string, Clave]> = [
  ["el título es obligatorio", "publicar.titulo"],
  ["el resumen es obligatorio", "publicar.resumen"],
  ["la versión debe tener al menos un módulo", "publicar.sinModulos"],
  ["todo módulo debe tener al menos una unidad", "publicar.moduloSinUnidades"],
  ["toda unidad debe tener al menos un recurso visible", "publicar.unidadSinRecursos"],
  ["hay recursos visibles que aún no terminan de procesarse", "publicar.recursoNoListo"],
  ["solo un borrador puede publicarse", "publicar.noEsBorrador"],
  ["los criterios de aprobación deben estar entre 0 y 100", "publicar.criterios"],
];

//traduce un motivo de rechazo de la publicacion
//ejemplo: 'course: todo módulo debe tener al menos una unidad: módulo "Intro"'
//queda: 'El módulo «Intro» no tiene unidades...'
export function motivoDePublicacion(detalle: string, t: Traducir): string {
  const limpio = sinPrefijo(detalle);
  for (const [inicio, clave] of MOTIVOS_DE_PUBLICACION) {
    if (limpio.startsWith(inicio)) {
      //los nombres de modulos, unidades y recursos vienen entre comillas
      const nombres = [...limpio.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
      return t(clave, { a: nombres[0] ?? "", b: nombres[1] ?? "" });
    }
  }
  return limpio;
}
