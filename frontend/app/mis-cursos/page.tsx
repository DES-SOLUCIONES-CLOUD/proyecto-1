"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, type Enrollment, ApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth-context";
import { ListaPersonal } from "@/components/ListaPersonal";
import { useI18n, type Clave, type Traducir } from "@/lib/i18n";

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
function filaDeCurso(e: Enrollment, t: Traducir, retirarse: (courseId: string) => void) {
  return (
    <>
      <div className="fila__datos">
        <Link href={`/cursos/${e.CourseID}`}>{t("misCursos.verCurso")}</Link>
        <p>
          <span className="badge">{t(claveDeEstado[e.Status])}</span>
        </p>
      </div>
      {e.Status === "active" && (
        <button className="secondary" onClick={() => retirarse(e.CourseID)}>
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
      setError(e instanceof ApiError ? e.message : t("misCursos.error"));
    }
  }

  async function handleWithdraw(courseId: string) {
    try {
      await api.withdraw(courseId);
      load();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : t("misCursos.errorRetirar"));
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
      fila={(e) => filaDeCurso(e, t, handleWithdraw)}
    />
  );
}
