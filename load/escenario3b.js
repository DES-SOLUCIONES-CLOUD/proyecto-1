// Escenario 3B de capacidad (Entrega 3): ciclo de autoscaling de los workers.
//
// Reutiliza el flujo de subida de escenario2.js (firma, PUT al bucket,
// confirmar), pero a diferencia de ese guion NO espera a `ready`: confirma y
// pasa de inmediato al siguiente video. El objetivo es sostener la cola
// asynq llena —y, en consecuencia, los workers existentes ocupados
// transcodificando varios videos a la vez— el tiempo suficiente para que el
// autoscaler del MIG de workers decida crear instancias adicionales.
//
// Funciona sin importar qué señal haya quedado configurada (CPU o
// profundidad de cola, ver docs/entrega3/arquitectura.md): encolar más
// rápido de lo que los workers drenan sube las dos cosas a la vez, porque
// cada worker ocupado transcodificando sostiene su CPU mientras la cola
// sigue creciendo detrás.
//
// VUS_PICO por defecto es 8. Cada VU en el pico es un "profesor" subiendo
// videos sin parar; en el reposo baja a VUS_REPOSO para dejar que la cola
// drene y observar la reducción.
//
// La profundidad de cola NO la reporta k6 (vive en Redis, no en la API): la
// serie sale de load/observar.sh y la reconciliación de los trabajos
// aceptados, de load/reconciliar-3b.sql.
//
//   BASE_URL=https://<balanceador> \
//   VUS_REPOSO=1 VUS_PICO=8 RAMPA=20s MESETA_INICIAL=3m MESETA_ALTA=6m MESETA_BAJA=15m \
//   k6 run load/escenario3b.js

import http from "k6/http";
import { check, group, sleep } from "k6";
import { Counter, Trend } from "k6/metrics";
import { SharedArray } from "k6/data";
import crypto from "k6/crypto";
import exec from "k6/execution";

const BASE = __ENV.BASE_URL || "http://localhost:8080";
const ESCENARIO = __ENV.ESCENARIO || "/salida/escenario.json";
const SALIDA = __ENV.SALIDA || "/salida";

const VUS_REPOSO = Number(__ENV.VUS_REPOSO || 1);
const VUS_PICO = Number(__ENV.VUS_PICO || 8);
const RAMPA = __ENV.RAMPA || "20s";
const MESETA_ALTA = __ENV.MESETA_ALTA || "6m";
const MESETA_INICIAL = __ENV.MESETA_INICIAL || "3m";
// El reposo final tiene que cubrir la ventana de estabilización del autoscaler
// (unos 10 minutos antes de reducir) y lo que tarde en retirarse la instancia.
const MESETA_BAJA = __ENV.MESETA_BAJA || "15m";


const DIR_PERFILES = __ENV.PERFILES_DIR || "perfiles";
const PERFILES = {
  corto: { archivo: __ENV.VIDEO_CORTO || `${DIR_PERFILES}/corto.mp4`, mime: "video/mp4" },
  medio: { archivo: __ENV.VIDEO_MEDIO || `${DIR_PERFILES}/medio.mp4`, mime: "video/mp4" },
};
const nombresPerfiles = Object.keys(PERFILES);
const binarios = {};
for (const nombre of nombresPerfiles) {
  binarios[nombre] = open(PERFILES[nombre].archivo, "b");
}

const datos = new SharedArray("escenario", () => [JSON.parse(open(ESCENARIO))]);
const escenario = datos[0];

const trabajosEncolados = new Counter("mooc_trabajos_encolados");
const confirmacion = new Trend("mooc_confirmacion_3b", true);

export const options = {
  scenarios: {
    ciclo_workers: {
      executor: "ramping-vus",
      exec: "subirSinEsperar",
      startVUs: VUS_REPOSO,
      stages: [
        { duration: MESETA_INICIAL, target: VUS_REPOSO }, // 1. reposo: cola casi vacía
        { duration: RAMPA, target: VUS_PICO }, // 2. rampa: empieza a encolar
        { duration: MESETA_ALTA, target: VUS_PICO }, // 3. meseta alta: fuerza el scale-out
        { duration: RAMPA, target: VUS_REPOSO }, // 4. deja de encolar
        { duration: MESETA_BAJA, target: VUS_REPOSO }, // 5. reposo: observa el drenaje y el scale-in
      ],
    },
  },
  thresholds: {
    // Sin threshold de negocio: algunas subidas pueden tardar por la cola
    // llena a propósito. Solo se vigila que el PUT al bucket no falle.
    http_req_failed: [{ threshold: "rate<0.1", abortOnFail: false }],
  },
};

function segundos(s) {
  const m = /^(\d+)(ms|s|m|h)?$/.exec(String(s).trim());
  if (!m) return 0;
  const n = Number(m[1]);
  return { ms: n / 1000, s: n, m: n * 60, h: n * 3600 }[m[2] || "s"];
}

function calcularMarcas(inicioMs) {
  const fases = [
    ["reposo_inicial", MESETA_INICIAL],
    ["rampa_subida", RAMPA],
    ["meseta_alta", MESETA_ALTA],
    ["rampa_bajada", RAMPA],
    ["reposo_final", MESETA_BAJA],
  ];
  let t = inicioMs;
  const marcas = [];
  for (const [fase, dur] of fases) {
    marcas.push({ fase, inicio: new Date(t).toISOString() });
    t += segundos(dur) * 1000;
  }
  marcas.push({ fase: "fin_previsto", inicio: new Date(t).toISOString() });
  return marcas;
}

export function setup() {
  if (!escenario.profesores?.length) {
    throw new Error(
      "el escenario no tiene profesores: vuelve a sembrar (SEED_TEACHERS>=1), igual que escenario2.js",
    );
  }
  for (const nombre of nombresPerfiles) {
    if (!binarios[nombre] || binarios[nombre].byteLength < 32) {
      throw new Error(`falta el perfil ${nombre} (${PERFILES[nombre].archivo}). load/perfiles/generar.sh`);
    }
  }
  const marcas = calcularMarcas(Date.now());
  console.log("");
  console.log("Escenario 3B — ciclo de autoscaling de workers");
  console.log("================================================");
  console.log(`VUs (profesores subiendo sin parar): reposo ${VUS_REPOSO} -> pico ${VUS_PICO} -> reposo ${VUS_REPOSO}`);
  console.log(`Fases (hora prevista, UTC):`);
  for (const m of marcas) console.log(`  ${m.fase.padEnd(16)} ${m.inicio}`);
  console.log("");
  console.log("Correr en paralelo, desde Cloud Shell o un portátil con permisos:");
  console.log("  load/observar.sh --corrida esc3b-<fecha>");
  console.log("");
  return { marcas };
}

function auth(token) {
  return { headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" } };
}

function campo(obj, ...nombres) {
  if (!obj) return undefined;
  for (const n of nombres) {
    if (obj[n] !== undefined && obj[n] !== null) return obj[n];
  }
  return undefined;
}

// Crea un curso desechable de un solo recurso de vídeo, lo sube y confirma
// SIN esperar a `ready`. El curso nunca se publica: no hace falta para
// encolar el trabajo de transcodificación, que es lo único que le importa a
// este escenario.
export function subirSinEsperar() {
  const profesores = escenario.profesores;
  const profesor = profesores[(exec.vu.idInTest - 1) % profesores.length];
  const perfil = nombresPerfiles[(exec.vu.iterationInScenario + exec.vu.idInTest) % nombresPerfiles.length];
  const cfg = auth(profesor.token);
  const marca = `${exec.vu.idInTest}-${exec.vu.iterationInScenario}-${Date.now()}`;

  const alta = http.post(
    `${BASE}/api/v1/courses`,
    JSON.stringify({ slug: `e3b-${marca}`, title: `Carga 3B ${marca}` }),
    { ...cfg, tags: { fase: "alta_curso" } },
  );
  if (!check(alta, { "curso creado": (r) => r.status === 201 })) {
    sleep(1);
    return;
  }
  const versionId = alta.json("version_id");

  const modulo = http.post(
    `${BASE}/api/v1/courses/versions/${versionId}/modules`,
    JSON.stringify({ title: "M", position: 1 }),
    cfg,
  );
  const moduloId = campo(modulo.json(), "ID", "id");
  const unidad = http.post(
    `${BASE}/api/v1/courses/versions/${versionId}/modules/${moduloId}/units`,
    JSON.stringify({ title: "U", position: 1 }),
    cfg,
  );
  const unidadId = campo(unidad.json(), "ID", "id");
  const creado = http.post(
    `${BASE}/api/v1/courses/versions/${versionId}/units/${unidadId}/resources`,
    JSON.stringify({ type: "video", title: perfil, position: 1, visible: true, required: false, downloadable: false }),
    cfg,
  );
  const resourceId = campo(creado.json(), "ID", "id");
  if (!resourceId) {
    sleep(1);
    return;
  }

  group("subida", () => {
    const cuerpo = binarios[perfil];
    const sha = crypto.sha256(cuerpo, "hex");

    const urlRes = http.post(
      `${BASE}/api/v1/courses/versions/${versionId}/resources/${resourceId}/upload-url`,
      JSON.stringify({ mime_type: PERFILES[perfil].mime }),
      { ...cfg, tags: { fase: "firma" } },
    );
    if (!check(urlRes, { "firma 200": (r) => r.status === 200 })) return;
    const uploadUrl = urlRes.json("upload_url");

    const put = http.put(uploadUrl, cuerpo, {
      headers: { "Content-Type": PERFILES[perfil].mime },
      tags: { fase: "transferencia" },
      timeout: "5m",
    });
    if (!check(put, { "transferencia 2xx": (r) => r.status >= 200 && r.status < 300 })) return;

    const t0 = Date.now();
    const conf = http.post(
      `${BASE}/api/v1/courses/versions/${versionId}/resources/${resourceId}/confirm-upload`,
      JSON.stringify({ checksum_sha256: sha }),
      { ...cfg, tags: { fase: "confirmacion" } },
    );
    confirmacion.add(Date.now() - t0);
    if (check(conf, { "confirmación encola el trabajo": (r) => r.status === 202 || r.status === 200 })) {
      trabajosEncolados.add(1);
    }
  });
  // Sin espera a ready: en cuanto confirma, ya encoló el trabajo. Pasa al
  // siguiente de inmediato (con una pausa corta para no saturar solo la
  // firma de URLs).
  sleep(0.2);
}

export function handleSummary(data) {
  return {
    stdout: resumenLegible(data),
    [`${SALIDA}/resumen-escenario3b.json`]: JSON.stringify(data, null, 2),
  };
}

function resumenLegible(data) {
  const m = data.metrics;
  return [
    "",
    "Escenario 3B — resultado",
    "=========================",
    `Trabajos encolados:       ${m.mooc_trabajos_encolados?.values?.count ?? 0}`,
    `p50/p95/p99 confirmación: ${(m.mooc_confirmacion_3b?.values?.["p(50)"] ?? 0).toFixed(0)} ms / ${(m.mooc_confirmacion_3b?.values?.["p(95)"] ?? 0).toFixed(0)} ms / ${(m.mooc_confirmacion_3b?.values?.["p(99)"] ?? 0).toFixed(0)} ms`,
    `Tasa de error:            ${((m.http_req_failed?.values?.rate ?? 0) * 100).toFixed(3)} %`,
    `VUs máximos:              ${m.vus_max?.values?.value ?? "—"}`,
    "",
    "Completar con load/observar.sh (cola e instancias en el tiempo) y con",
    "load/reconciliar-3b.sql (el drenaje real, no solo lo que mandó k6).",
    "",
  ].join("\n");
}
