// Escenario 1 de capacidad (Entrega 2). Parte de load/etapa1.js.
//
// Qué cambia respecto de Etapa 1:
//   - Línea base y al menos 3 niveles crecientes (NIVELES), con una meseta
//     extra en el último nivel para repetir la medición cerca del límite.
//   - La inscripción va DENTRO del recorrido (POST /enrollments), no solo
//     sembrada. Sembrar con SEED_ENROLL=0.
//   - Sigue habiendo una cuenta distinta por VU (setup() corta si no).
//   - El envío duplicado del quiz sigue comprobando que no hay doble nota.
//
// Login: SÍ se mide, pero NO forma parte del mix de VU del recorrido. Corre
// a 8/min por la puerta principal, dentro del presupuesto del limitador
// (10/min por IP). Las sesiones del catálogo/consumo/quiz se siembran: si
// autenticáramos a cada VU por /auth/login, mediríamos el limitador y no
// la plataforma. Esta declaración es la que pide el enunciado.

import http from "k6/http";
import { check, group, sleep } from "k6";
import { Counter, Rate, Trend } from "k6/metrics";
import { SharedArray } from "k6/data";
import exec from "k6/execution";

const BASE = __ENV.BASE_URL || "http://localhost:8080";
const ESCENARIO = __ENV.ESCENARIO || "/salida/escenario.json";
const SALIDA = __ENV.SALIDA || "/salida";
const MESETA = __ENV.MESETA || "3m";
const RAMPA = __ENV.RAMPA || "30s";

// Por defecto: línea base 50 y tres escalones. El último se sostiene dos
// veces (la repetición cerca del límite). Se cambia sin tocar el guion.
const NIVELES = (__ENV.NIVELES || "50,100,200,300")
  .split(",")
  .map((s) => Number(s.trim()))
  .filter((n) => n > 0);
const VUS = Math.max(...NIVELES);

const datos = new SharedArray("escenario", () => [JSON.parse(open(ESCENARIO))]);
const escenario = datos[0];

const progresoAceptado = new Rate("mooc_progreso_aceptado");
const intentosCalificados = new Counter("mooc_intentos_calificados");
const notaDelIntento = new Trend("mooc_nota_intento");
const loginLimitado = new Rate("mooc_login_limitado");
const inscripciones = new Counter("mooc_inscripciones");

function etapas(peso) {
  const stages = [];
  for (const n of NIVELES) {
    stages.push({ duration: RAMPA, target: Math.ceil(n * peso) });
    stages.push({ duration: MESETA, target: Math.ceil(n * peso) });
  }
  // Repetir la medición en el último nivel (el más cercano al límite).
  const ultimo = NIVELES[NIVELES.length - 1];
  stages.push({ duration: MESETA, target: Math.ceil(ultimo * peso) });
  stages.push({ duration: RAMPA, target: 0 });
  return stages;
}

const duracionLogin = NIVELES.length + 1; // mesetas + la repetición

export const options = {
  scenarios: {
    catalogo: {
      executor: "ramping-vus",
      exec: "navegarCatalogo",
      startVUs: 0,
      stages: etapas(0.3),
      tags: { escenario: "catalogo" },
    },
    consumo: {
      executor: "ramping-vus",
      exec: "consumirContenido",
      startVUs: 0,
      stages: etapas(0.55),
      tags: { escenario: "consumo" },
    },
    quiz: {
      executor: "ramping-vus",
      exec: "presentarQuiz",
      startVUs: 0,
      stages: etapas(0.15),
      tags: { escenario: "quiz" },
    },
    // Medido, fuera del mix de VU. Ver el comentario del archivo.
    login: {
      executor: "constant-arrival-rate",
      exec: "iniciarSesion",
      rate: 8,
      timeUnit: "1m",
      duration: `${duracionLogin * (parseMesetaSegundos(MESETA) + parseMesetaSegundos(RAMPA))}s`,
      preAllocatedVUs: 2,
      tags: { escenario: "login" },
    },
  },
  thresholds: {
    http_req_failed: [{ threshold: "rate<0.005", abortOnFail: false }],
    "http_req_duration{escenario:catalogo}": ["p(95)<400", "p(99)<800"],
    "http_req_duration{escenario:consumo}": ["p(95)<600", "p(99)<1200"],
    "http_req_duration{escenario:quiz}": ["p(95)<900", "p(99)<1800"],
    "http_req_duration{escenario:login}": ["p(95)<2000"],
    mooc_progreso_aceptado: ["rate>0.99"],
    mooc_login_limitado: ["rate<0.01"],
    checks: ["rate>0.99"],
  },
};

function parseMesetaSegundos(s) {
  const m = /^(\d+)(ms|s|m|h)?$/.exec(String(s).trim());
  if (!m) return 180;
  const n = Number(m[1]);
  switch (m[2] || "s") {
    case "ms":
      return Math.max(1, n / 1000);
    case "s":
      return n;
    case "m":
      return n * 60;
    case "h":
      return n * 3600;
    default:
      return n;
  }
}

export function setup() {
  const faltan = [];
  const exigir = (campo, minimo, para) => {
    const n = escenario[campo]?.length ?? 0;
    if (n < minimo) faltan.push(`${campo}: ${n} (hacen falta ${minimo} para ${para})`);
  };

  exigir("recursos_texto", 1, "el escenario de consumo");
  exigir("recursos_quiz", 1, "el escenario de quiz");
  exigir("estudiantes", 1, "cualquier escenario con sesión");
  if (!escenario.course_id) faltan.push("course_id: ausente");
  if (!escenario.cuenta_de_prueba?.email) faltan.push("cuenta_de_prueba: ausente (escenario de login)");

  if (faltan.length > 0) {
    throw new Error(
      `el escenario de ${ESCENARIO} está incompleto:\n  - ${faltan.join("\n  - ")}\n` +
        `Vuelve a sembrarlo con SEED_ENROLL=0 para este escenario.`,
    );
  }

  const cuentas = escenario.estudiantes.length;
  if (cuentas < VUS) {
    throw new Error(
      `el escenario tiene ${cuentas} cuentas y el nivel más alto pide ${VUS} VU: ` +
        `siembra al menos ${VUS} (SEED_STUDENTS=${VUS}) o baja NIVELES. ` +
        `Compartir cuentas entre usuarios virtuales produce conflictos del arnés.`,
    );
  }
  return {
    cuentas,
    niveles: NIVELES,
    estudiantes_inscritos: escenario.estudiantes_inscritos === true,
    cantidades: escenario.cantidades || {},
  };
}

function sesion(indice) {
  const cuentas = escenario.estudiantes;
  return cuentas[indice % cuentas.length];
}

function auth(token) {
  return {
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
  };
}

function inscribir(cfg, tags) {
  const res = http.post(
    `${BASE}/api/v1/enrollments`,
    JSON.stringify({ course_id: escenario.course_id }),
    { ...cfg, tags },
  );
  // 201: inscripción nueva. 409 already_enrolled: el estudiante ya estaba
  // (re-siembra o SEED_ENROLL=1). Las dos cuentan como inscripción en el
  // recorrido; no se trata el 409 como error de la plataforma.
  const ok = res.status === 201 || res.status === 409;
  if (res.status === 201) inscripciones.add(1);
  check(res, { "inscripción aceptada o ya inscrito": () => ok });
  return ok;
}

export function navegarCatalogo() {
  group("catálogo", () => {
    const lista = http.get(`${BASE}/api/v1/catalog`, { tags: { escenario: "catalogo" } });
    check(lista, {
      "catálogo responde 200": (r) => r.status === 200,
      "catálogo trae cursos": (r) => (r.json("items") || []).length > 0,
    });
    const filtrado = http.get(`${BASE}/api/v1/catalog?q=cloud&level=Introductorio`, {
      tags: { escenario: "catalogo" },
    });
    check(filtrado, { "búsqueda responde 200": (r) => r.status === 200 });
    const detalle = http.get(`${BASE}/api/v1/catalog/${escenario.course_id}`, {
      tags: { escenario: "catalogo" },
    });
    check(detalle, { "detalle responde 200": (r) => r.status === 200 });
  });
  sleep(1 + Math.random() * 2);
}

export function consumirContenido() {
  const cuenta = sesion(exec.vu.idInTest);
  const cfg = auth(cuenta.token);
  const tags = { escenario: "consumo" };

  group("inscripción", () => {
    inscribir(cfg, tags);
  });

  const recursos = escenario.recursos_texto;
  const recurso = recursos[Math.floor(Math.random() * recursos.length)];

  group("consumo", () => {
    const contenido = http.get(`${BASE}/api/v1/resources/${recurso}/content`, {
      ...cfg,
      tags,
    });
    check(contenido, { "contenido responde 200": (r) => r.status === 200 });

    const apertura = http.post(
      `${BASE}/api/v1/resources/${recurso}/progress`,
      JSON.stringify({ type: "open", complete: false }),
      { ...cfg, tags },
    );
    progresoAceptado.add(apertura.status === 200);
    check(apertura, { "apertura registrada": (r) => r.status === 200 });

    sleep(2 + Math.random() * 3);

    const latido = http.post(
      `${BASE}/api/v1/resources/${recurso}/progress`,
      JSON.stringify({ type: "heartbeat", complete: false }),
      { ...cfg, tags },
    );
    progresoAceptado.add(latido.status === 200);

    const resumen = http.get(`${BASE}/api/v1/enrollments/${escenario.course_id}/progress`, {
      ...cfg,
      tags,
    });
    check(resumen, { "resumen de progreso responde 200": (r) => r.status === 200 });
  });
  sleep(1 + Math.random() * 2);
}

export function presentarQuiz() {
  const cuenta = sesion(exec.vu.idInTest);
  const cfg = auth(cuenta.token);
  const tags = { escenario: "quiz" };

  group("inscripción", () => {
    inscribir(cfg, tags);
  });

  const quizzes = escenario.recursos_quiz;
  const recurso = quizzes[Math.floor(Math.random() * quizzes.length)];

  group("quiz", () => {
    const inicio = http.post(`${BASE}/api/v1/resources/${recurso}/quiz/attempts`, null, {
      ...cfg,
      tags,
    });
    if (!check(inicio, { "intento abierto": (r) => r.status === 200 || r.status === 201 })) {
      return;
    }

    const intento = inicio.json();
    const attemptId = intento.attempt_id;
    const preguntas = intento.questions || [];

    check(inicio, {
      "el intento no expone la respuesta correcta": (r) =>
        !/"is_correct"|"es_correcta"/.test(r.body || ""),
    });

    for (const p of preguntas) {
      const opciones = p.options || [];
      if (opciones.length === 0) continue;
      const elegida = opciones[Math.floor(Math.random() * opciones.length)];
      const guardado = http.put(
        `${BASE}/api/v1/quiz/attempts/${attemptId}/answers`,
        JSON.stringify({
          question_stable_id: p.stable_id,
          selected_option_stable_ids: [elegida.stable_id],
        }),
        { ...cfg, tags },
      );
      check(guardado, { "respuesta guardada": (r) => r.status === 200 || r.status === 204 });
      sleep(0.5 + Math.random());
    }

    const cabeceras = {
      ...cfg.headers,
      "Idempotency-Key": `carga-${attemptId}`,
    };
    const envio = http.post(`${BASE}/api/v1/quiz/attempts/${attemptId}/submit`, null, {
      headers: cabeceras,
      tags,
    });
    if (check(envio, { "intento calificado": (r) => r.status === 200 })) {
      intentosCalificados.add(1);
      const nota = envio.json("score");
      if (typeof nota === "number") notaDelIntento.add(nota);

      const reenvio = http.post(`${BASE}/api/v1/quiz/attempts/${attemptId}/submit`, null, {
        headers: cabeceras,
        tags,
      });
      check(reenvio, {
        "el reenvío devuelve la misma nota": (r) => r.status === 200 && r.json("score") === nota,
      });
    }
  });
  sleep(2 + Math.random() * 3);
}

export function iniciarSesion() {
  const cuenta = escenario.cuenta_de_prueba;
  const res = http.post(
    `${BASE}/api/v1/auth/login`,
    JSON.stringify({ email: cuenta.email, password: cuenta.password }),
    { headers: { "Content-Type": "application/json" }, tags: { escenario: "login" } },
  );
  loginLimitado.add(res.status === 429);
  check(res, { "login responde 200": (r) => r.status === 200 });
}

export function handleSummary(data) {
  return {
    stdout: resumenLegible(data),
    [`${SALIDA}/resumen-escenario1.json`]: JSON.stringify(data, null, 2),
  };
}

function resumenLegible(data) {
  const m = data.metrics;
  const p = (nombre, q) => {
    const v = m[nombre];
    return v && v.values ? `${v.values[q]?.toFixed(0) ?? "—"} ms` : "—";
  };
  return [
    "",
    "Prueba de carga — Escenario 1 (capacidad)",
    "========================================",
    `Niveles:            ${NIVELES.join(" → ")} (+ repetición de ${NIVELES[NIVELES.length - 1]})`,
    `Login:              medido a 8/min, fuera del mix de VU`,
    `Inscripción:        dentro del recorrido (201 o 409)`,
    `Peticiones:         ${m.http_reqs?.values?.count ?? 0}`,
    `Tasa de error:      ${((m.http_req_failed?.values?.rate ?? 0) * 100).toFixed(3)} %`,
    `p50/p95/p99 catálogo: ${p("http_req_duration{escenario:catalogo}", "p(50)")} / ${p("http_req_duration{escenario:catalogo}", "p(95)")} / ${p("http_req_duration{escenario:catalogo}", "p(99)")}`,
    `p50/p95/p99 consumo:  ${p("http_req_duration{escenario:consumo}", "p(50)")} / ${p("http_req_duration{escenario:consumo}", "p(95)")} / ${p("http_req_duration{escenario:consumo}", "p(99)")}`,
    `p50/p95/p99 quiz:     ${p("http_req_duration{escenario:quiz}", "p(50)")} / ${p("http_req_duration{escenario:quiz}", "p(95)")} / ${p("http_req_duration{escenario:quiz}", "p(99)")}`,
    `p50/p95/p99 login:    ${p("http_req_duration{escenario:login}", "p(50)")} / ${p("http_req_duration{escenario:login}", "p(95)")} / ${p("http_req_duration{escenario:login}", "p(99)")}`,
    `Inscripciones 201:  ${m.mooc_inscripciones?.values?.count ?? 0}`,
    `Intentos calificados: ${m.mooc_intentos_calificados?.values?.count ?? 0}`,
    `Comprobaciones OK:  ${((m.checks?.values?.rate ?? 0) * 100).toFixed(2)} %`,
    "",
  ].join("\n");
}
