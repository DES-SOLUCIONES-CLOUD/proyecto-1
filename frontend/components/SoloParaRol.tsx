"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import type { User } from "@/lib/api";
import { useAuth } from "@/lib/auth-context";
import { useI18n } from "@/lib/i18n";

//muestra el contenido solo si el usuario tiene uno de los roles permitidos
//si no, explica por que no puede entrar y a donde puede ir
//ojo: esto es solo para que la pantalla sea clara, el servidor igual revisa
//los permisos en cada peticion
export function SoloParaRol({ roles, children }: { roles: User["role"][]; children: ReactNode }) {
  const { user, loading } = useAuth();
  const { t } = useI18n();

  //mientras se sabe quien es el usuario
  if (loading) {
    return <p role="status">{t("comun.cargando")}</p>;
  }

  //no ha iniciado sesion
  if (!user) {
    return (
      <div className="columna-estrecha">
        <p className="warning-banner" role="alert">
          {t("acceso.requiereSesion")}
        </p>
        <Link href="/login">{t("nav.entrar")}</Link>
      </div>
    );
  }

  //inicio sesion pero con un rol que no puede ver esta seccion
  if (!roles.includes(user.role)) {
    return (
      <div className="columna-estrecha">
        <p className="error-banner" role="alert">
          {roles.includes("teacher") ? t("acceso.soloProfesores") : t("acceso.soloAdministradores")}
        </p>
        <Link href={user.role === "student" ? "/mis-cursos" : "/"}>
          {user.role === "student" ? t("acceso.irAMisCursos") : t("acceso.irAlCatalogo")}
        </Link>
      </div>
    );
  }

  return <>{children}</>;
}
