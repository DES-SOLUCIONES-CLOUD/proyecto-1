"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, type CourseProgress, type Enrollment } from "@/lib/api";
import { mensajeDeError } from "@/lib/errores";
import { useAuth } from "@/lib/auth-context";
import { ListaPersonal } from "@/components/ListaPersonal";
import { useI18n, type Clave } from "@/lib/i18n";

// El estado de la inscripción llega como identificador del dominio; la clave
// del catálogo se deriva de él para que un estado nuevo en la API falle al
// compilar en vez de aparecer sin traducir.
const claveDeEstado: Record<Enrollment["Status"], Clave> = {
  active: "estado.active",
  withdrawn: "estado.withdrawn",
  completed: "estado.completed",
  approved: "estado.approved",
};

// fila de la lista. va fuera del componente para que no se vuelva a crear en
// cada render (sonarqube typescript:S6478)
function FilaDeCurso({ inscripcion: e, retirarse }: { inscripcion: Enrollment; retirarse: (courseId: string) => void }) {
  const { t } = useI18n();
  const [titulo, setTitulo] = useState("");
  const [avance, setAvance] = useState<CourseProgress | null>(null);

  //la inscripcion no trae el nombre del curso, asi que se pide aparte
  //tambien se pide el avance para mostrar cuanto lleva el estudiante
  useEffect(() => {
    api.getPublishedCourse(e.CourseID).then((v) => setTitulo(v.Title)).catch(() => setTitulo(""));
    api.getCourseProgress(e.CourseID).then(setAvance).catch(() => setAvance(null));
  }, [e.CourseID]);

  //se pregunta antes de retirarse para que no pase por un clic sin querer
  function confirmarRetiro() {
    if (confirm(t("misCursos.confirmarRetiro", { titulo: titulo || t("misCursos.esteCurso") }))) {
      retirarse(e.CourseID);
    }
  }

  return (
    <>
      <div className="fila__datos">
        <Link href={`/cursos/${e.CourseID}`}>
          <strong>{titulo || t("misCursos.verCurso")}</strong>
        </Link>
        <p className="row" style={{ alignItems: "center" }}>
          <span className="badge">{t(claveDeEstado[e.Status])}</span>
          {avance && (
            <span className="muted">
              {t("misCursos.avance", { pct: avance.required_percent.toFixed(0) })}
            </span>
          )}
        </p>
        {avance && (
          <progress value={avance.required_percent} max={100} aria-label={t("curso.tuAvance")} style={{ width: "100%" }} />
        )}
      </div>
      {e.Status === "active" && (
        <button className="secondary" onClick={confirmarRetiro}>
          {t("misCursos.retirarme")}
        </button>
      )}
    </>
  );
}

export default function MyCoursesPage() {
  const { user, loading: authLoading } = useAuth();
  const [items, setItems] = useState<Enrollment[] | null>(null);
  const [error, setError] = useState("");
  const { t } = useI18n();

  useEffect(() => {
    if (!authLoading && user) {
      load();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [authLoading, user]);

  async function load() {
    try {
      const res = await api.listMyEnrollments();
      setItems(res.items ?? []);
    } catch (e) {
      setError(mensajeDeError(e, t, "misCursos.error"));
    }
  }

  async function handleWithdraw(courseId: string) {
    try {
      await api.withdraw(courseId);
      load();
    } catch (e) {
      setError(mensajeDeError(e, t, "misCursos.errorRetirar"));
    }
  }

  return (
    <ListaPersonal
      titulo={t("nav.misCursos")}
      subtitulo={t("misCursos.subtitulo")}
      requiereSesion={t("misCursos.requiereSesion")}
      items={items}
      error={error}
      vacio={
        <>
          <p>{t("misCursos.vacio")}</p>
          <p>
            <Link href="/">{t("misCursos.explorar")}</Link>
          </p>
        </>
      }
      clave={(e) => e.ID}
      fila={(e) => <FilaDeCurso inscripcion={e} retirarse={handleWithdraw} />}
    />
  );
}
