//llena el catalogo con cursos de ejemplo y crea las cuentas de la demostracion
//
//todo pasa por la api publica, igual que si alguien lo hiciera en el navegador:
//el administrador crea las cuentas, y el profesor crea los cursos con lecciones,
//archivos (video, imagen, pdf), quizzes, espera a que los workers los procesen y publica.
//se puede correr varias veces: lo que ya existe se salta.
//
//uso (necesita node 20 o mas nuevo), en powershell:
//  $env:MOOC_URL="https://136.82.109.164.sslip.io"
//  $env:ADMIN_EMAIL="<correo del administrador>"
//  $env:ADMIN_PASSWORD="<clave del administrador>"
//  $env:DEMO_PASSWORD="<clave para las cuentas de la demo>"
//  node data/catalogo/poblar.mjs
//
//las claves no se guardan en el repositorio: se pasan al correrlo

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const URL_BASE = (process.env.MOOC_URL ?? "").replace(/\/$/, "");
const ADMIN_EMAIL = process.env.ADMIN_EMAIL ?? "";
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? "";
const DEMO_PASSWORD = process.env.DEMO_PASSWORD ?? "";

if (!URL_BASE || !ADMIN_EMAIL || !ADMIN_PASSWORD || DEMO_PASSWORD.length < 10) {
  console.error("faltan variables: MOOC_URL, ADMIN_EMAIL, ADMIN_PASSWORD y DEMO_PASSWORD (minimo 10 caracteres)");
  process.exit(1);
}

const datos = JSON.parse(await readFile(new URL("./cursos.json", import.meta.url), "utf8"));

const espera = (ms) => new Promise((ok) => setTimeout(ok, ms));

//tipo de contenido de cada archivo segun su extension
const TIPOS_MIME = { ".mp4": "video/mp4", ".png": "image/png", ".jpg": "image/jpeg", ".pdf": "application/pdf" };

//una sesion es un "navegador" con sus cookies: la de sesion y la del token anti-csrf
function nuevaSesion() {
  const cookies = new Map();

  async function pedir(metodo, ruta, cuerpo) {
    for (let intento = 1; ; intento++) {
      const cabeceras = { "Content-Type": "application/json" };
      if (cookies.size) cabeceras.Cookie = [...cookies].map(([k, v]) => `${k}=${v}`).join("; ");
      //igual que el frontend: en peticiones que cambian algo se repite el token anti-csrf
      if (metodo !== "GET" && cookies.has("mooc_csrf")) cabeceras["X-CSRF-Token"] = decodeURIComponent(cookies.get("mooc_csrf"));
      const res = await fetch(URL_BASE + ruta, {
        method: metodo,
        headers: cabeceras,
        body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
      });
      for (const c of res.headers.getSetCookie()) {
        const [par] = c.split(";");
        const i = par.indexOf("=");
        cookies.set(par.slice(0, i).trim(), par.slice(i + 1).trim());
      }
      //el login tiene limite de intentos por minuto: si se llega, se espera
      if (res.status === 429 && intento < 5) {
        console.log("  limite de peticiones, esperando 20 s...");
        await espera(20000);
        continue;
      }
      const texto = await res.text();
      const json = texto ? JSON.parse(texto) : null;
      if (!res.ok) {
        const e = new Error(`${metodo} ${ruta} -> ${res.status} ${json?.error?.code ?? ""} ${(json?.error?.details ?? []).join(" | ")}`);
        e.status = res.status;
        e.codigo = json?.error?.code;
        throw e;
      }
      return json;
    }
  }

  return {
    get: (ruta) => pedir("GET", ruta),
    post: (ruta, cuerpo = {}) => pedir("POST", ruta, cuerpo),
    put: (ruta, cuerpo) => pedir("PUT", ruta, cuerpo),
    patch: (ruta, cuerpo) => pedir("PATCH", ruta, cuerpo),
    entrar: (email, password) => pedir("POST", "/api/v1/auth/login", { email, password }),
  };
}

//1. cuentas: el administrador las crea ya activas, con su rol y la clave de la demo
async function prepararCuentas() {
  const admin = nuevaSesion();
  await admin.entrar(ADMIN_EMAIL, ADMIN_PASSWORD);
  console.log("admin con sesion");

  for (const c of datos.cuentas) {
    try {
      await admin.post("/api/v1/admin/users", { email: c.email, full_name: c.nombre, role: c.rol, password: DEMO_PASSWORD });
      console.log(`cuenta creada: ${c.email} (${c.rol})`);
    } catch (e) {
      //si ya existia se deja como esta
      if (e.status === 409) console.log(`ya existia: ${c.email}`);
      else throw e;
    }
  }
}

//sube un archivo igual que el navegador: pide la url firmada, lo manda directo al bucket
//y le avisa a la api con su huella sha-256 para que lo verifique y lo mande a la cola
async function subirArchivo(profe, v, recursoId, nombre) {
  const bytes = await readFile(new URL(`./medios/${nombre}`, import.meta.url));
  const mime = TIPOS_MIME[nombre.slice(nombre.lastIndexOf("."))] ?? "application/octet-stream";
  const { upload_url } = await profe.post(`${v}/resources/${recursoId}/upload-url`, { mime_type: mime });
  const res = await fetch(upload_url, { method: "PUT", body: bytes, headers: { "Content-Type": mime } });
  if (!res.ok) throw new Error(`subida de ${nombre} -> ${res.status}`);
  const huella = createHash("sha256").update(bytes).digest("hex");
  await profe.post(`${v}/resources/${recursoId}/confirm-upload`, { checksum_sha256: huella });
}

//espera a que los workers terminen de procesar los archivos de la version (maximo 10 minutos)
async function esperarProcesamiento(profe, v) {
  for (let i = 0; i < 120; i++) {
    const version = await profe.get(v);
    const recursos = (version.Modules ?? []).flatMap((m) => (m.Units ?? []).flatMap((u) => u.Resources ?? []));
    const pendientes = recursos.filter((r) => r.ProcessingStatus === "pending" || r.ProcessingStatus === "processing");
    const fallidos = recursos.filter((r) => r.ProcessingStatus === "failed");
    if (fallidos.length) throw new Error(`fallo el procesamiento de: ${fallidos.map((r) => r.Title).join(", ")}`);
    if (!pendientes.length) return;
    if (i % 6 === 0) console.log(`  esperando a los workers: ${pendientes.length} archivo(s) en proceso`);
    await espera(5000);
  }
  throw new Error("los archivos no terminaron de procesarse en 10 minutos");
}

//2. cursos: los crea el profesor dueno con modulos, unidades, lecciones, archivos y quizzes, y los publica
async function crearCursos() {
  const profe = nuevaSesion();
  await profe.entrar(datos.dueno, DEMO_PASSWORD);
  const { items: mios } = await profe.get("/api/v1/courses/mine");
  const yaEstan = new Set((mios ?? []).filter((c) => c.CurrentPublishedVersionID).map((c) => c.Slug));

  for (const curso of datos.cursos) {
    if (yaEstan.has(curso.slug)) {
      console.log(`ya publicado, se salta: ${curso.titulo}`);
      continue;
    }
    console.log(`creando: ${curso.titulo}`);
    //si quedo un borrador a medias de una corrida anterior se reutiliza
    const previo = (mios ?? []).find((c) => c.Slug === curso.slug);
    let versionId = previo?.LatestDraftVersionID;
    if (!versionId) {
      const creado = await profe.post("/api/v1/courses", { slug: curso.slug, title: curso.titulo });
      versionId = creado.version_id;
    }
    const v = `/api/v1/courses/versions/${versionId}`;

    await profe.patch(v, {
      title: curso.titulo,
      summary: curso.resumen,
      description_md: curso.descripcion,
      category: curso.categoria,
      level: curso.nivel,
      language: "es",
      approval_min_score: 60,
      approval_required_resources_pct: 100,
      portada: curso.portada ?? 0,
    });

    //un borrador reutilizado puede traer contenido viejo: se arma solo si esta vacio
    const actual = await profe.get(v);
    if ((actual.Modules ?? []).length === 0) {
      for (const [im, modulo] of curso.modulos.entries()) {
        const m = await profe.post(`${v}/modules`, { title: modulo.titulo, position: im + 1 });
        for (const [iu, unidad] of modulo.unidades.entries()) {
          const u = await profe.post(`${v}/modules/${m.ID}/units`, { title: unidad.titulo, position: iu + 1 });
          let pos = 1;
          for (const leccion of unidad.lecciones) {
            const tipo = leccion.tipo ?? "text";
            const r = await profe.post(`${v}/units/${u.ID}/resources`, {
              type: tipo,
              title: leccion.titulo,
              position: pos++,
              visible: true,
              //el texto y lo marcado como obligatorio cuentan para el avance
              required: tipo === "text" ? true : Boolean(leccion.obligatorio),
              downloadable: tipo === "pdf",
              text_content_md: tipo === "text" ? leccion.texto : "",
              external_url: "",
            });
            if (leccion.archivo) await subirArchivo(profe, v, r.ID, leccion.archivo);
          }
          if (unidad.quiz) {
            const r = await profe.post(`${v}/units/${u.ID}/resources`, {
              type: "quiz",
              title: unidad.quiz.titulo,
              position: pos++,
              visible: true,
              required: true,
              downloadable: false,
              text_content_md: "",
              external_url: "",
            });
            await profe.put(`${v}/resources/${r.ID}/quiz`, {
              title: unidad.quiz.titulo,
              pass_score: 60,
              feedback_policy: "after_submit",
              shuffle_questions: false,
              time_limit_seconds: null,
              max_attempts: 3,
              questions: unidad.quiz.preguntas.map((p) => ({
                prompt_md: p.pregunta,
                type: "single",
                points: 1,
                options: p.opciones.map((texto, i) => ({ text_md: texto, is_correct: i === p.correcta })),
              })),
            });
          }
        }
      }
    }

    await esperarProcesamiento(profe, v);
    await profe.post(`${v}/publish`);
    console.log(`publicado: ${curso.titulo}`);
  }
}

await prepararCuentas();
await crearCursos();
const { items } = await nuevaSesion().get("/api/v1/catalog");
console.log(`listo: el catalogo tiene ${items?.length ?? 0} cursos publicados`);
