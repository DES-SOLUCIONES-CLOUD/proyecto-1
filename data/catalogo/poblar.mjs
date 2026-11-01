//llena el catalogo con cursos de ejemplo y crea las cuentas de la demostracion
//
//todo pasa por la api publica, igual que si alguien lo hiciera en el navegador:
//registro, activacion por un administrador, creacion de cursos, lecciones, quiz y publicacion.
//se puede correr varias veces: lo que ya existe se salta.
//
//uso (necesita node 20 o mas nuevo):
//  MOOC_URL=https://136.82.109.164.sslip.io \
//  ADMIN_EMAIL=... ADMIN_PASSWORD=... \
//  DEMO_PASSWORD=una-clave-de-10-o-mas \
//  node data/catalogo/poblar.mjs
//
//en windows powershell las variables se ponen asi: $env:MOOC_URL="https://..."
//
//las claves no se guardan en el repositorio: se pasan al correrlo

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
      //el login y el registro tienen limite de intentos por minuto: si se llega, se espera
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

//1. cuentas: cada una se registra como estudiante y el admin la activa y le pone su rol
async function prepararCuentas() {
  const admin = nuevaSesion();
  await admin.entrar(ADMIN_EMAIL, ADMIN_PASSWORD);
  console.log("admin con sesion");

  for (const c of datos.cuentas) {
    const publico = nuevaSesion();
    //si el correo ya existe la api responde igual (no revela que correos hay), asi que no falla
    await publico.post("/api/v1/auth/register", { email: c.email, password: DEMO_PASSWORD, full_name: c.nombre });

    const { items } = await admin.get(`/api/v1/admin/users?${new URLSearchParams({ q: c.email })}`);
    const u = (items ?? []).find((x) => x.email === c.email);
    if (!u) throw new Error(`no aparece la cuenta ${c.email} despues de registrarla`);
    if (u.status !== "active") await admin.patch(`/api/v1/admin/users/${u.id}/status`, { status: "active" });
    if (u.role !== c.rol) await admin.patch(`/api/v1/admin/users/${u.id}/role`, { role: c.rol });
    console.log(`cuenta lista: ${c.email} (${c.rol})`);
  }
}

//2. cursos: los crea el profesor dueno con modulos, unidades, lecciones de texto y un quiz, y los publica
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
            await profe.post(`${v}/units/${u.ID}/resources`, {
              type: "text",
              title: leccion.titulo,
              position: pos++,
              visible: true,
              required: true,
              downloadable: false,
              text_content_md: leccion.texto,
              external_url: "",
            });
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

    await profe.post(`${v}/publish`);
    console.log(`publicado: ${curso.titulo}`);
  }
}

await prepararCuentas();
await crearCursos();
const { items } = await nuevaSesion().get("/api/v1/catalog");
console.log(`listo: el catalogo tiene ${items?.length ?? 0} cursos publicados`);
