"use client";

import Link from "next/link";
import { useAuth } from "@/lib/auth-context";
import { useI18n } from "@/lib/i18n";

interface Props<T> {
  titulo: string;
  subtitulo: string;
  /** aviso para quien entra sin haber iniciado sesion */
  requiereSesion: string;
  /** null mientras carga */
  items: T[] | null;
  error: string;
  /** lo que se muestra cuando la lista esta vacia */
  vacio: React.ReactNode;
  clave: (item: T) => string;
  /** contenido de cada <li> */
  fila: (item: T) => React.ReactNode;
}

/**
 * esqueleto comun de las paginas que listan lo del usuario (mis cursos y
 * mis insignias)
 *
 * antes las dos paginas repetian la revision de sesion, el encabezado y los
 * estados de carga, vacio y error, y ya no se comportaban igual: mis cursos
 * mostraba "Cargando..." junto con el error. ahora eso vive aqui y cada
 * pagina solo dice que carga y como se ve cada fila
 */
export function ListaPersonal<T>({
  titulo,
  subtitulo,
  requiereSesion,
  items,
  error,
  vacio,
  clave,
  fila,
}: Props<T>) {
  const { user, loading: authLoading } = useAuth();
  const { t } = useI18n();

  if (!authLoading && !user) {
    return (
      <div className="estado-vacio columna-estrecha">
        <p>{requiereSesion}</p>
        <p>
          <Link href="/login">{t("nav.entrar")}</Link>
        </p>
      </div>
    );
  }

  return (
    <div>
      <header className="page-header">
        <div>
          <h1>{titulo}</h1>
          <p>{subtitulo}</p>
        </div>
      </header>

      {error && (
        <p className="error-banner" role="alert">
          {error}
        </p>
      )}
      {items === null && !error && <p role="status">{t("comun.cargando")}</p>}

      {items?.length === 0 && <div className="estado-vacio">{vacio}</div>}

      <ul className="lista-filas">
        {items?.map((item) => (
          <li key={clave(item)} className="card fila">
            {fila(item)}
          </li>
        ))}
      </ul>
    </div>
  );
}
