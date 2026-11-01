"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { api, type Version, type CourseProgress } from "@/lib/api";
import { Portada } from "@/components/Portada";
import { mensajeDeError } from "@/lib/errores";
import { useAuth } from "@/lib/auth-context";
import { useI18n, type Clave } from "@/lib/i18n";

const claveDeEstado: Record<CourseProgress["status"], Clave> = {
  active: "estado.active",
  withdrawn: "estado.withdrawn",
  completed: "estado.completed",
  approved: "estado.approved",
};

export default function CourseDetailPage() {
  const { courseId } = useParams<{ courseId: string }>();
  const { user } = useAuth();
  const { t } = useI18n();
  const [version, setVersion] = useState<Version | null>(null);
  const [error, setError] = useState("");
  const [enrollMessage, setEnrollMessage] = useState("");
  //el error va aparte del mensaje de exito para pintarlo en rojo y no en verde
  const [enrollError, setEnrollError] = useState("");
  const [inscribiendo, setInscribiendo] = useState(false);
  const [progress, setProgress] = useState<CourseProgress | null>(null);

  useEffect(() => {
    api
      .getPublishedCourse(courseId)
      .then(setVersion)
      .catch((e) => setError(mensajeDeError(e, t, "curso.error")));
  }, [courseId, t]);

  const loadProgress = useCallback(() => {
    if (user?.role !== "student") return;
    // Un 404 aquí significa "no inscrito", que es un estado normal y no un
    // error: por eso se ignora en silencio en vez de mostrar un banner.
    api.getCourseProgress(courseId).then(setProgress).catch(() => setProgress(null));
  }, [courseId, user?.role]);

  useEffect(() => {
    loadProgress();
  }, [loadProgress]);

  async function handleEnroll() {
    setEnrollMessage("");
    setEnrollError("");
    setInscribiendo(true);
    try {
      await api.enroll(courseId);
      setEnrollMessage(t("curso.inscrito"));
      loadProgress();
    } catch (e) {
      setEnrollError(mensajeDeError(e, t, "curso.errorInscripcion"));
    } finally {
      setInscribiendo(false);
    }
  }

  if (error) {
    return (
      <div className="columna-estrecha">
        <p className="error-banner" role="alert">
          {error}
        </p>
        <Link href="/">{t("acceso.irAlCatalogo")}</Link>
      </div>
    );
  }
  if (!version) {
    return <p role="status">{t("curso.cargando")}</p>;
  }

  //el primer recurso visible del curso, para el boton de empezar
  const primerRecurso = (version.Modules ?? [])
    .flatMap((m) => m.Units ?? [])
    .flatMap((u) => u.Resources ?? [])
    .find((r) => r.Visible);
  const esEstudiante = user?.role === "student";
  //un estudiante que se retiro puede volver a inscribirse y conserva su progreso
  const retirado = progress?.status === "withdrawn";
  const inscrito = Boolean(progress) && !retirado;

  return (
    <div>
      {/*la misma portada de colores del catalogo, en grande*/}
      <Portada titulo={version.Title} categoria={version.Category} ancha />
      <header className="page-header">
        <div>
          <h1>{version.Title}</h1>
          <p>{version.Summary}</p>
          <div className="row" style={{ marginTop: "0.5rem" }}>
            {version.Category && <span className="badge">{version.Category}</span>}
            {version.Level && <span className="badge">{version.Level}</span>}
            <span className="badge">{version.Language}</span>
          </div>
        </div>
        {/*lo que se ofrece depende de quien mira el curso*/}
        <div className="stack">
          {esEstudiante && !inscrito && (
            <button onClick={handleEnroll} disabled={inscribiendo}>
              {inscribiendo ? t("curso.inscribiendo") : retirado ? t("curso.reinscribirme") : t("curso.inscribirme")}
            </button>
          )}
          {inscrito && primerRecurso && (
            <Link className="boton" href={`/cursos/${courseId}/recursos/${primerRecurso.ID}`}>
              {t("curso.irAlContenido")}
            </Link>
          )}
        </div>
      </header>

      {!user && (
        <p className="warning-banner" role="status">
          {t("curso.entrarParaInscribirse")} <Link href="/login">{t("nav.entrar")}</Link>
        </p>
      )}
      {user && !esEstudiante && <p className="muted">{t("curso.soloEstudiantes")}</p>}
      {retirado && <p className="warning-banner">{t("curso.retiradoAyuda")}</p>}

      {enrollMessage && (
        <p className="success-banner" role="status">
          {enrollMessage}
        </p>
      )}
      {enrollError && (
        <p className="error-banner" role="alert">
          {enrollError}
        </p>
      )}

      {progress && (
        <div className="card">
          <h2 style={{ marginTop: 0 }}>{t("curso.tuAvance")}</h2>
          <p className="row" style={{ alignItems: "center" }}>
            <span className="badge">{t(claveDeEstado[progress.status])}</span>
            <span>
              {t("curso.recursosCompletados", {
                hechos: progress.required_completed,
                total: progress.required_total,
                pct: progress.required_percent.toFixed(0),
              })}
            </span>
          </p>
          {/*barra de avance: muestra de un vistazo cuanto falta*/}
          <progress
            value={progress.required_percent}
            max={100}
            aria-label={t("curso.tuAvance")}
            style={{ width: "100%" }}
          />
          {progress.quizzes_pending > 0 && (
            <p className="muted">
              {t("curso.evaluacionesPendientes", { n: progress.quizzes_pending })}
            </p>
          )}
          {progress.badge_code && (
            <p className="success-banner" role="status">
              {t("curso.insigniaObtenida")}{" "}
              <Link href={`/insignias/${progress.badge_code}`}>{t("curso.verVerificacion")}</Link>
            </p>
          )}
        </div>
      )}

      <h2>{t("curso.contenido")}</h2>
      {/*temario: cada modulo es un panel, cada unidad un subtitulo y cada recurso una fila*/}
      <ol className="temario">
        {version.Modules?.map((m) => (
          <li key={m.ID} className="card">
            <h3>{m.Title}</h3>
            {m.Units?.map((u) => (
              <section key={u.ID} className="temario__unidad">
                <h4>{u.Title}</h4>
                <ul>
                  {u.Resources?.filter((r) => r.Visible).map((r) => (
                    <li key={r.ID}>
                      {/* Solo quien esté inscrito recibirá el contenido; la
                          API lo comprueba en cada entrega. El enlace se
                          muestra igual para que se vea qué trae el curso. */}
                      <Link href={`/cursos/${courseId}/recursos/${r.ID}`}>{r.Title}</Link>
                      <span className="temario__datos">
                        {t(`tipo.${r.Type}` as Clave)}
                        {r.Required && <> · {t("curso.obligatorio")}</>}
                      </span>
                    </li>
                  ))}
                </ul>
              </section>
            ))}
          </li>
        ))}
      </ol>
    </div>
  );
}
