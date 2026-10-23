"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, type Badge, ApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth-context";
import { ListaPersonal } from "@/components/ListaPersonal";
import { useI18n, type Traducir } from "@/lib/i18n";

// fila de la lista. va fuera del componente para que no se vuelva a crear en
// cada render (sonarqube typescript:S6478)
function filaDeInsignia(b: Badge, t: Traducir, locale: string) {
  const fecha = new Date(b.issued_at).toLocaleDateString(locale);
  return (
    <>
      {b.image_url && (
        /* eslint-disable-next-line @next/next/no-img-element */
        <img
          src={b.image_url}
          alt={t("insignias.alt", { fecha })}
          width={96}
          height={96}
          style={{ borderRadius: "8px" }}
        />
      )}
      <div className="fila__datos">
        <p>
          <span className="badge">
            {b.valid ? t("insignias.vigente") : t("insignias.revocada")}
          </span>{" "}
          {t("insignias.emitidaEl", { fecha })}
        </p>
        <p className="muted">
          {t("insignias.codigoVerificacion")} <code>{b.code}</code>
        </p>
      </div>
      <Link href={`/insignias/${b.code}`}>{t("curso.verVerificacion")}</Link>
    </>
  );
}

export default function MyBadgesPage() {
  const { user, loading: authLoading } = useAuth();
  const [items, setItems] = useState<Badge[] | null>(null);
  const [error, setError] = useState("");
  const { t, locale } = useI18n();

  useEffect(() => {
    if (authLoading || !user) return;
    api
      .listMyBadges()
      .then((res) => setItems(res.items ?? []))
      .catch((e) => setError(e instanceof ApiError ? e.message : t("insignias.error")));
  }, [authLoading, user, t]);

  return (
    <ListaPersonal
      titulo={t("nav.misInsignias")}
      subtitulo={t("insignias.subtitulo")}
      requiereSesion={t("insignias.requiereSesion")}
      items={items}
      error={error}
      vacio={
        <>
          <p>{t("insignias.vacio")}</p>
          <p>{t("insignias.vacioAccion")}</p>
        </>
      }
      clave={(b) => b.code}
      fila={(b) => filaDeInsignia(b, t, locale)}
    />
  );
}
