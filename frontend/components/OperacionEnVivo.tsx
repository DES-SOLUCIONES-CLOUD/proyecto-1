"use client";

import { useEffect, useMemo, useState } from "react";
import { api, type Actividad, type EventoDeProcesamiento, type PeticionRegistrada } from "@/lib/api";
import { describirPeticion, recursoDeLaRuta } from "@/lib/actividad";
import { mensajeDeError } from "@/lib/errores";
import { useI18n } from "@/lib/i18n";

//cada cuanto se pide la actividad mientras esta en vivo
const CADA_MS = 2000;

//color fijo para cada maquina, asi se distingue de un vistazo quien atendio
function colorDeMaquina(nombre: string): number {
  let suma = 0;
  for (const letra of nombre) suma = (suma * 31 + letra.charCodeAt(0)) % 997;
  return (suma % 6) + 1;
}

function horaCorta(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleTimeString();
}

//panel de operacion para el administrador: que paso en la plataforma, en vivo
//junta lo de todas las replicas de la api y todos los workers (lo guardan en redis)
//sirve para ver el reparto del balanceador y el procesamiento de los videos sin entrar por ssh
export function OperacionEnVivo() {
  const { t } = useI18n();
  const [datos, setDatos] = useState<Actividad | null>(null);
  const [error, setError] = useState("");
  const [enVivo, setEnVivo] = useState(true);

  useEffect(() => {
    if (!enVivo) return;
    let vigente = true;
    async function pedir() {
      try {
        const d = await api.actividad();
        if (vigente) {
          setDatos(d);
          setError("");
        }
      } catch (e) {
        if (vigente) setError(mensajeDeError(e, t, "operacion.error"));
      }
    }
    pedir();
    const reloj = setInterval(pedir, CADA_MS);
    return () => {
      vigente = false;
      clearInterval(reloj);
    };
  }, [enVivo, t]);

  const peticiones = useMemo(() => datos?.peticiones ?? [], [datos]);
  const procesamiento = datos?.procesamiento ?? [];

  //cuantas peticiones atendio cada maquina en lo que se ve en pantalla
  const reparto = useMemo(() => {
    const cuenta = new Map<string, number>();
    for (const p of peticiones) cuenta.set(p.instancia, (cuenta.get(p.instancia) ?? 0) + 1);
    return [...cuenta.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  }, [peticiones]);
  const total = peticiones.length || 1;

  return (
    <section className="card operacion">
      <header className="row" style={{ justifyContent: "space-between", alignItems: "flex-start" }}>
        <div>
          <h2>{t("operacion.titulo")}</h2>
          <p>{t("operacion.ayuda")}</p>
        </div>
        <button type="button" className={enVivo ? "secondary" : ""} onClick={() => setEnVivo(!enVivo)}>
          {enVivo ? t("operacion.pausar") : t("operacion.reanudar")}
        </button>
      </header>

      {error && (
        <p className="error-banner" role="alert">
          {error}
        </p>
      )}
      {!datos && !error && <p role="status">{t("comun.cargando")}</p>}

      {datos && (
        <>
          <div className="operacion__datos">
            <div className="dato">
              <span className="dato__titulo">{t("operacion.version")}</span>
              <code>{datos.version}</code>
            </div>
            <div className="dato">
              <span className="dato__titulo">{t("operacion.teRespondio")}</span>
              <span className="maquina" data-color={colorDeMaquina(datos.instancia)}>
                {datos.instancia}
              </span>
            </div>
            <div className="dato">
              <span className="dato__titulo">{enVivo ? t("operacion.enVivo") : t("operacion.enPausa")}</span>
              <span className={enVivo ? "punto-vivo" : "punto-pausa"} aria-hidden="true" />
            </div>
          </div>

          <h3>{t("operacion.reparto")}</h3>
          {reparto.length === 0 ? (
            <p className="muted">{t("operacion.sinPeticiones")}</p>
          ) : (
            <ul className="reparto">
              {reparto.map(([maquina, n]) => (
                <li key={maquina}>
                  <span className="maquina" data-color={colorDeMaquina(maquina)}>
                    {maquina}
                  </span>
                  <span className="reparto__barra">
                    <span data-color={colorDeMaquina(maquina)} style={{ width: `${(n / total) * 100}%` }} />
                  </span>
                  <span className="reparto__numero">{n}</span>
                </li>
              ))}
            </ul>
          )}

          <div className="operacion__columnas">
            <div>
              <h3>{t("operacion.peticiones")}</h3>
              <ol className="bitacora" aria-live="off">
                {peticiones.slice(0, 60).map((p, i) => (
                  <FilaDePeticion key={`${p.hora}-${p.ruta}-${i}`} p={p} />
                ))}
              </ol>
            </div>
            <div>
              <h3>{t("operacion.procesamiento")}</h3>
              {procesamiento.length === 0 ? (
                <p className="muted">{t("operacion.sinTrabajos")}</p>
              ) : (
                <ol className="bitacora">
                  {procesamiento.slice(0, 40).map((e, i) => (
                    <FilaDeTrabajo key={`${e.hora}-${i}`} e={e} />
                  ))}
                </ol>
              )}
            </div>
          </div>
        </>
      )}
    </section>
  );
}

function FilaDePeticion({ p }: { p: PeticionRegistrada }) {
  const { t } = useI18n();
  const clave = describirPeticion(p.metodo, p.ruta);
  const recurso = recursoDeLaRuta(p.ruta);
  const fallo = p.estado >= 400;
  return (
    <li className="bitacora__fila">
      <span className="bitacora__hora">{horaCorta(p.hora)}</span>
      <span className="bitacora__texto">
        <strong>{clave ? t(clave) : `${p.metodo} ${p.ruta}`}</strong>
        {/*quien lo hizo; la ruta tecnica solo cuando no hay una descripcion*/}
        {p.usuario && <span className="muted">{p.usuario}</span>}
        {recurso && clave && (clave === "actividad.subiendo" || clave === "actividad.subidaTerminada") && (
          <span className="muted">
            {t("operacion.carpeta")} <code>resources/{recurso}/</code>
          </span>
        )}
      </span>
      <span className={fallo ? "estado estado--mal" : "estado"}>
        {p.estado} · {p.ms} ms
      </span>
      <span className="maquina" data-color={colorDeMaquina(p.instancia)}>
        {p.instancia}
      </span>
    </li>
  );
}

//atributos del trabajo que vale la pena mostrar (el resto queda en los logs)
const ATRIBUTOS_UTILES = ["recurso", "calidad", "tipo", "origen", "hls", "pdf", "duracion_ms", "error"];

function FilaDeTrabajo({ e }: { e: EventoDeProcesamiento }) {
  const texto = e.mensaje.replace(/^(media|documentos): /, "");
  const detalles = ATRIBUTOS_UTILES.filter((k) => e.atributos?.[k] !== undefined && e.atributos[k] !== "");
  return (
    <li className="bitacora__fila">
      <span className="bitacora__hora">{horaCorta(e.hora)}</span>
      <span className="bitacora__texto">
        <strong>{texto}</strong>
        {detalles.map((k) => (
          <span key={k} className="muted">
            {k}: <code>{String(e.atributos[k])}</code>
          </span>
        ))}
      </span>
      <span className={e.nivel === "INFO" ? "estado" : "estado estado--mal"}>{e.nivel}</span>
      <span className="maquina" data-color={colorDeMaquina(e.worker)}>
        {e.worker}
      </span>
    </li>
  );
}
