"use client";

import { useMemo, useState } from "react";
import { api, type QuizAttempt, type QuizQuestion } from "@/lib/api";
import { mensajeDeError } from "@/lib/errores";
import { useI18n } from "@/lib/i18n";

/**
 * Reproductor de un quiz para el estudiante.
 *
 * Al pulsar "Empezar", abre un intento (o recupera el que ya estuviera en
 * curso) y muestra las preguntas en el orden congelado en ese momento. Cada
 * cambio de selección se guarda de inmediato en el servidor: nada se acumula
 * solo en memoria del navegador, así que recargar la página no pierde nada.
 *
 * La clave correcta nunca llega aquí: el servidor solo entrega el texto de
 * las opciones, nunca cuál es la correcta.
 */
export function QuizPlayer({ resourceId }: { resourceId: string }) {
  const { t, locale } = useI18n();
  const [attempt, setAttempt] = useState<QuizAttempt | null>(null);
  const [error, setError] = useState("");
  const [abriendo, setAbriendo] = useState(false);
  //true si al abrir se encontro un intento a medias con respuestas guardadas
  const [retomado, setRetomado] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [savingQuestion, setSavingQuestion] = useState<string | null>(null);
  const [guardadas, setGuardadas] = useState<Set<string>>(new Set());

  //el intento ya no se abre solo al entrar a la pagina: antes, con solo mirar
  //se gastaba un intento. ahora se abre cuando el estudiante lo pide
  async function abrirIntento() {
    setAbriendo(true);
    setError("");
    try {
      const a = await api.startQuizAttempt(resourceId);
      setAttempt(a);
      setRetomado(a.status === "in_progress" && Object.keys(a.answers).length > 0);
      setGuardadas(new Set(Object.keys(a.answers)));
    } catch (e) {
      setError(mensajeDeError(e, t, "quiz.errorAbrir"));
    } finally {
      setAbriendo(false);
    }
  }

  async function handleSelect(question: QuizQuestion, optionStableId: string) {
    if (!attempt) return;
    const previa = attempt.answers[question.stable_id] ?? [];
    let seleccion: string[];
    if (question.type === "single") {
      seleccion = [optionStableId];
    } else {
      seleccion = previa.includes(optionStableId)
        ? previa.filter((id) => id !== optionStableId)
        : [...previa, optionStableId];
    }

    // Optimista: se refleja de inmediato y se corrige si el servidor rechaza.
    setAttempt({ ...attempt, answers: { ...attempt.answers, [question.stable_id]: seleccion } });
    setSavingQuestion(question.stable_id);
    setError("");
    try {
      await api.saveQuizAnswer(attempt.attempt_id, question.stable_id, seleccion);
      //se marca la pregunta como guardada para mostrarle al estudiante que no se pierde
      setGuardadas((g) => new Set(g).add(question.stable_id));
    } catch (e) {
      setAttempt({ ...attempt, answers: { ...attempt.answers, [question.stable_id]: previa } });
      setError(mensajeDeError(e, t, "quiz.errorGuardarRespuesta"));
    } finally {
      setSavingQuestion(null);
    }
  }

  // Una clave estable por intento hace que reintentar tras un corte de red
  // (el usuario pulsa "Enviar" dos veces, o el navegador reintenta solo)
  // devuelva la misma nota en vez de calificar dos veces.
  const attemptId = attempt?.attempt_id;
  const idempotencyKey = useMemo(() => (attemptId ? `quiz-submit-${attemptId}` : ""), [attemptId]);

  async function handleSubmit() {
    if (!attempt) return;
    const faltantes = attempt.questions.filter((q) => (attempt.answers[q.stable_id] ?? []).length === 0);
    if (
      faltantes.length > 0 &&
      !confirm(t("quiz.confirmarFaltantes", { n: faltantes.length }))
    ) {
      return;
    }
    setSubmitting(true);
    setError("");
    try {
      const resultado = await api.submitQuizAttempt(attempt.attempt_id, idempotencyKey);
      setAttempt(resultado);
      setRetomado(false);
      // El avance del curso (completado, aprobado, insignia) se recalcula al
      // procesar una señal de progreso. Se fuerza aquí, en vez de esperar a
      // que el estudiante abandone la página, para que quien consulte el
      // resumen justo después del envío ya vea el resultado actualizado.
      void api.recordProgress(resourceId, "close", true).catch(() => undefined);
    } catch (e) {
      setError(mensajeDeError(e, t, "quiz.errorEnviar"));
    } finally {
      setSubmitting(false);
    }
  }

  //pantalla de inicio: explica como funciona antes de abrir el intento
  if (!attempt) {
    return (
      <section className="card stack">
        <p style={{ margin: 0 }}>{t("quiz.explicacion")}</p>
        {error && (
          <p className="error-banner" role="alert">
            {error}
          </p>
        )}
        <div>
          <button onClick={abrirIntento} disabled={abriendo}>
            {abriendo ? t("quiz.abriendo") : t("quiz.empezar")}
          </button>
        </div>
      </section>
    );
  }

  const cerrado = attempt.status !== "in_progress";
  const respondidas = attempt.questions.filter((q) => (attempt.answers[q.stable_id] ?? []).length > 0).length;

  return (
    <div className="stack">
      {/*datos del intento: numero, cuantas lleva y hasta cuando tiene tiempo*/}
      <p className="row" style={{ alignItems: "center" }}>
        <span className="badge">{t("quiz.intentoNumero", { n: attempt.attempt_number })}</span>
        {!cerrado && (
          <span className="muted">
            {t("quiz.respondidas", { n: respondidas, total: attempt.questions.length })}
          </span>
        )}
        {!cerrado && attempt.expires_at && (
          <span className="muted">
            {t("quiz.tiempoHasta", {
              hora: new Date(attempt.expires_at).toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" }),
            })}
          </span>
        )}
      </p>

      {retomado && (
        <p className="warning-banner" role="status">
          {t("quiz.retomado")}
        </p>
      )}

      {error && (
        <p className="error-banner" role="alert">
          {error}
        </p>
      )}

      {cerrado && (
        <div className={attempt.passed ? "success-banner" : "warning-banner"} role="status">
          <strong>
            {attempt.status === "expired" ? t("quiz.intentoExpirado") : t("quiz.intentoCalificado")}
          </strong>
          {typeof attempt.score === "number" ? (
            <>
              {" "}
              {t("quiz.nota", { nota: attempt.score.toFixed(1) })}{" "}
              {attempt.passed ? t("quiz.aprobaste") : t("quiz.noAprobaste")}
            </>
          ) : (
            //el profesor puede haber decidido mostrar la nota mas tarde
            <> {t("quiz.notaOculta")}</>
          )}
        </div>
      )}

      {/*si no aprobo, puede intentarlo otra vez (el servidor dice si le quedan intentos)*/}
      {cerrado && attempt.passed === false && (
        <div>
          <button className="secondary" onClick={abrirIntento} disabled={abriendo}>
            {abriendo ? t("quiz.abriendo") : t("quiz.intentarDeNuevo")}
          </button>
        </div>
      )}

      <ol className="stack">
        {attempt.questions.map((q, i) => (
          <li key={q.stable_id} className="card">
            <p>
              <strong>
                {i + 1}. {q.prompt_md}
              </strong>{" "}
              <span className="muted">
                ({q.points === 1 ? t("quiz.unPunto") : t("quiz.nPuntos", { n: q.points })})
              </span>
            </p>
            <fieldset disabled={cerrado || savingQuestion === q.stable_id} style={{ border: "none", padding: 0, margin: 0 }}>
              <legend className="muted" style={{ fontSize: "0.85rem" }}>
                {q.type === "single" ? t("quiz.elegirUna") : t("quiz.elegirVarias")}
              </legend>
              <ul className="stack" style={{ gap: "0.35rem" }}>
                {q.options.map((o) => {
                  const marcada = (attempt.answers[q.stable_id] ?? []).includes(o.stable_id);
                  return (
                    <li key={o.stable_id}>
                      <label className="row" style={{ gap: "0.5rem" }}>
                        <input
                          type={q.type === "single" ? "radio" : "checkbox"}
                          name={`pregunta-${q.stable_id}`}
                          checked={marcada}
                          onChange={() => handleSelect(q, o.stable_id)}
                        />
                        {o.text_md}
                      </label>
                    </li>
                  );
                })}
              </ul>
            </fieldset>
            {/*indicador pequeño para que el estudiante sepa que su respuesta quedo guardada*/}
            {!cerrado && savingQuestion === q.stable_id && (
              <p className="muted" role="status">
                {t("comun.guardando")}
              </p>
            )}
            {!cerrado && savingQuestion !== q.stable_id && guardadas.has(q.stable_id) && (
              <p className="muted">✓ {t("quiz.respuestaGuardada")}</p>
            )}
          </li>
        ))}
      </ol>

      {!cerrado && (
        <div>
          <button onClick={handleSubmit} disabled={submitting}>
            {submitting ? t("quiz.enviando") : t("quiz.enviar")}
          </button>
        </div>
      )}
    </div>
  );
}
