import type { ReactNode } from "react";
import { SoloParaRol } from "@/components/SoloParaRol";

//la pagina de administracion solo la ven los administradores
export default function LayoutAdmin({ children }: { children: ReactNode }) {
  return <SoloParaRol roles={["admin"]}>{children}</SoloParaRol>;
}
