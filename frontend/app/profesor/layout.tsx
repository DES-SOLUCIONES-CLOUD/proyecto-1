import type { ReactNode } from "react";
import { SoloParaRol } from "@/components/SoloParaRol";

//todas las paginas dentro de /profesor pasan por aqui
//solo profesores y administradores pueden verlas
export default function LayoutProfesor({ children }: { children: ReactNode }) {
  return <SoloParaRol roles={["teacher", "admin"]}>{children}</SoloParaRol>;
}
