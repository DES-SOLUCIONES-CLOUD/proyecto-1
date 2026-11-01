"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth-context";
import { IDIOMAS, NOMBRES_DE_IDIOMA, useI18n, type Idioma } from "@/lib/i18n";

//el simbolo de la plataforma: un libro abierto, dibujado en el color de acento
function Simbolo() {
  return (
    <svg width="26" height="26" viewBox="0 0 26 26" aria-hidden="true">
      <rect width="26" height="26" rx="8" fill="var(--color-accent)" />
      <path
        d="M6 8.5c2.6-.9 5-.6 7 1.1 2-1.7 4.4-2 7-1.1v9.2c-2.6-.9-5-.6-7 1.1-2-1.7-4.4-2-7-1.1z"
        fill="none"
        stroke="var(--color-bg)"
        strokeWidth="1.6"
        strokeLinejoin="round"
      />
      <path d="M13 9.6v9.2" stroke="var(--color-bg)" strokeWidth="1.6" />
    </svg>
  );
}

export function NavBar() {
  const { user, loading, logout } = useAuth();
  const { t, idioma, cambiar } = useI18n();
  const router = useRouter();
  const ruta = usePathname();

  async function handleLogout() {
    await logout();
    router.push("/");
  }

  //marca el enlace de la seccion donde esta el usuario (se ve con una pastilla gris)
  function actual(destino: string) {
    const estaAqui = destino === "/" ? ruta === "/" : ruta.startsWith(destino);
    return estaAqui ? ("page" as const) : undefined;
  }

  return (
    <header className="navbar">
      <Link href="/" className="brand">
        <Simbolo />
        Plataforma MOOC
      </Link>
      <nav aria-label={t("nav.principal")}>
        <Link href="/" aria-current={actual("/")}>
          {t("nav.catalogo")}
        </Link>
        {!loading && user?.role === "student" && (
          <Link href="/mis-cursos" aria-current={actual("/mis-cursos")}>
            {t("nav.misCursos")}
          </Link>
        )}
        {!loading && user?.role === "student" && (
          <Link href="/mis-insignias" aria-current={actual("/mis-insignias")}>
            {t("nav.misInsignias")}
          </Link>
        )}
        {!loading && (user?.role === "teacher" || user?.role === "admin") && (
          <Link href="/profesor" aria-current={actual("/profesor")}>
            {t("nav.autoria")}
          </Link>
        )}
        {!loading && user?.role === "admin" && (
          <Link href="/admin" aria-current={actual("/admin")}>
            {t("nav.administracion")}
          </Link>
        )}

        {!loading && user && (
          <span className="row" style={{ gap: "0.25rem" }}>
            <Link href="/cuenta/sesiones" aria-current={actual("/cuenta")}>
              {t("nav.sesiones")}
            </Link>
            <span className="usuario">
              {user.full_name} · {t(`rol.${user.role}`)}
            </span>
            <button className="secondary" onClick={handleLogout}>
              {t("nav.salir")}
            </button>
          </span>
        )}
        {!loading && !user && (
          <span className="row" style={{ gap: "0.25rem" }}>
            <Link href="/login" aria-current={actual("/login")}>
              {t("nav.entrar")}
            </Link>
            <Link href="/registro" className="boton">
              {t("nav.registrarse")}
            </Link>
          </span>
        )}

        <span className="row">
          <label htmlFor="idioma" className="visually-hidden">
            {t("nav.idioma")}
          </label>
          <select
            id="idioma"
            value={idioma}
            onChange={(e) => cambiar(e.target.value as Idioma)}
            style={{ minHeight: "2.25rem", padding: "0.25rem 0.6rem", fontSize: "0.875rem" }}
          >
            {IDIOMAS.map((i) => (
              <option key={i} value={i}>
                {NOMBRES_DE_IDIOMA[i]}
              </option>
            ))}
          </select>
        </span>
      </nav>
    </header>
  );
}
