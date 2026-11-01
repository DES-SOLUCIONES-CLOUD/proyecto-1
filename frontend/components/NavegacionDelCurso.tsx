"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, type Version } from "@/lib/api";
import { useI18n } from "@/lib/i18n";

//un recurso con el modulo y la unidad donde esta, en el orden del curso
interface Paso {
  id: string;
  titulo: string;
  modulo: string;
  unidad: string;
}

//arma la lista de recursos visibles en orden: modulo por modulo, unidad por unidad
function pasosDelCurso(v: Version): Paso[] {
  const porPosicion = <T extends { Position: number }>(a: T, b: T) => a.Position - b.Position;
  const pasos: Paso[] = [];
  for (const m of [...(v.Modules ?? [])].sort(porPosicion)) {
    for (const u of [...(m.Units ?? [])].sort(porPosicion)) {
      for (const r of [...(u.Resources ?? [])].sort(porPosicion)) {
        if (r.Visible) pasos.push({ id: r.ID, titulo: r.Title, modulo: m.Title, unidad: u.Title });
      }
    }
  }
  return pasos;
}

//pide el curso una sola vez y devuelve el recurso actual, el anterior y el siguiente
export function useNavegacionDelCurso(courseId: string, resourceId: string) {
  const [pasos, setPasos] = useState<Paso[]>([]);
  useEffect(() => {
    api
      .getPublishedCourse(courseId)
      .then((v) => setPasos(pasosDelCurso(v)))
      .catch(() => setPasos([]));
  }, [courseId]);

  const i = pasos.findIndex((p) => p.id === resourceId);
  return {
    actual: i >= 0 ? pasos[i] : null,
    anterior: i > 0 ? pasos[i - 1] : null,
    siguiente: i >= 0 && i < pasos.length - 1 ? pasos[i + 1] : null,
    numero: i + 1,
    total: pasos.length,
  };
}

//migas de pan: Curso › Modulo › Unidad, para saber donde esta el estudiante
export function MigasDelRecurso({
  courseId,
  nav,
}: {
  courseId: string;
  nav: ReturnType<typeof useNavegacionDelCurso>;
}) {
  const { t } = useI18n();
  return (
    <nav aria-label={t("navegacion.migas")} className="muted" style={{ fontSize: "0.9rem" }}>
      <Link href={`/cursos/${courseId}`}>{t("navegacion.curso")}</Link>
      {nav.actual && (
        <>
          {" › "}
          {nav.actual.modulo} {" › "}
          {nav.actual.unidad}
          {" · "}
          {t("navegacion.recursoDe", { n: nav.numero, total: nav.total })}
        </>
      )}
    </nav>
  );
}

//botones de anterior y siguiente al final de cada recurso
export function AnteriorSiguiente({
  courseId,
  nav,
}: {
  courseId: string;
  nav: ReturnType<typeof useNavegacionDelCurso>;
}) {
  const { t } = useI18n();
  if (!nav.actual) return null;
  return (
    <nav aria-label={t("navegacion.entreRecursos")} className="row" style={{ justifyContent: "space-between", marginTop: "1.5rem" }}>
      {nav.anterior ? (
        <Link className="boton secondary" href={`/cursos/${courseId}/recursos/${nav.anterior.id}`}>
          ← {nav.anterior.titulo}
        </Link>
      ) : (
        <span />
      )}
      {nav.siguiente ? (
        <Link className="boton" href={`/cursos/${courseId}/recursos/${nav.siguiente.id}`}>
          {nav.siguiente.titulo} →
        </Link>
      ) : (
        //en el ultimo recurso se ofrece volver al curso para ver el avance
        <Link className="boton" href={`/cursos/${courseId}`}>
          {t("navegacion.terminar")}
        </Link>
      )}
    </nav>
  );
}
