"use client";

import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { API_URL } from "@/lib/api";
import { useI18n } from "@/lib/i18n";

//version del frontend: el commit con el que se construyo la imagen (dev en local)
const VERSION_WEB = process.env.NEXT_PUBLIC_VERSION ?? "dev";

interface Salud {
  version?: string;
  instancia?: string;
}

//pie de pagina con la version desplegada y la maquina de la api que respondio
//cada vez que se cambia de pagina se vuelve a preguntar, asi se ve que el
//balanceador reparte entre las replicas y la sesion sigue igual
export function PieDePagina() {
  const { t } = useI18n();
  const ruta = usePathname();
  const [salud, setSalud] = useState<Salud | null>(null);

  useEffect(() => {
    let vigente = true;
    fetch(`${API_URL}/api/v1/health`, { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null))
      .then((datos: Salud | null) => {
        if (vigente) setSalud(datos);
      })
      .catch(() => {
        if (vigente) setSalud(null);
      });
    return () => {
      vigente = false;
    };
  }, [ruta]);

  return (
    <footer className="pie">
      <span>{t("pie.versionWeb", { v: VERSION_WEB })}</span>
      {salud?.version && <span>{t("pie.versionApi", { v: salud.version })}</span>}
      {salud?.instancia && <span>{t("pie.atendidoPor", { maquina: salud.instancia })}</span>}
    </footer>
  );
}
