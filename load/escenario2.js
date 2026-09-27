// Escenario 2 de capacidad (Entrega 2). No existía: el de Etapa 1 no mide
// la carga multimedia a propósito.
//
// Profesores: firman URL, suben el original al bucket, confirman y esperan
// hasta processing_status=ready (en el producto es "ready", no "available").
// Tres perfiles de vídeo (corto / medio / largo) y un WAV suelto, generados
// con load/perfiles/generar.sh. El enunciado pide video y audio.
//
// Estudiantes: inscriben, piden el manifiesto y consumen HLS al ritmo de
// EXTINF (no a ráfaga). Miden la entrega, no el worker.
//
// Métricas propias (segundos):
//   mooc_firma          POST upload-url
//   mooc_transferencia  PUT al bucket
//   mooc_confirmacion   POST confirm-upload
//   mooc_espera_cola    confirmado → primer estado processing
//   mooc_procesamiento  processing → ready
//   mooc_total_subida   firma → ready
//   mooc_hls_segmento   GET de cada segmento
//
// setup() deja 3 vídeos publicados (uno por perfil) para que los estudiantes
// tengan qué reproducir desde el primer segundo. Los profesores del escenario
// siguen subiendo en paralelo para cargar la cola.

import http from "k6/http";
import { check, sleep } from "k6";
import { Counter, Rate, Trend } from "k6/metrics";
import { SharedArray } from "k6/data";
import crypto from "k6/crypto";
import exec from "k6/execution";

const BASE = __ENV.BASE_URL || "http://localhost:8080";
const ESCENARIO = __ENV.ESCENARIO || "/salida/escenario.json";
const SALIDA = __ENV.SALIDA || "/salida";
const MESETA = __ENV.MESETA || "5m";
const PROFESORES = Number(__ENV.PROFESORES || 3);
const ESTUDIANTES = Number(__ENV.ESTUDIANTES || 20);
const POLL_S = Number(__ENV.POLL_S || 2);
const TIMEOUT_READY_S = Number(__ENV.TIMEOUT_READY_S || 600);

const DIR_PERFILES = __ENV.PERFILES_DIR || "perfiles";
const PERFILES = {
  corto: { archivo: __ENV.VIDEO_CORTO || `${DIR_PERFILES}/corto.mp4`, mime: "video/mp4", tipo: "video" },
  medio: { archivo: __ENV.VIDEO_MEDIO || `${DIR_PERFILES}/medio.mp4`, mime: "video/mp4", tipo: "video" },
  largo: { archivo: __ENV.VIDEO_LARGO || `${DIR_PERFILES}/largo.mp4`, mime: "video/mp4", tipo: "video" },
  audio: { archivo: __ENV.AUDIO_WAV || `${DIR_PERFILES}/audio.wav`, mime: "audio/wav", tipo: "audio" },
};

const nombres = Object.keys(PERFILES);
const binarios = {};
for (const nombre of nombres) {
  binarios[nombre] = open(PERFILES[nombre].archivo, "b");
}

const datos = new SharedArray("escenario", () => [JSON.parse(open(ESCENARIO))]);
const escenario = datos[0];

const firma = new Trend("mooc_firma", true);
const transferencia = new Trend("mooc_transferencia", true);
const confirmacion = new Trend("mooc_confirmacion", true);
const esperaCola = new Trend("mooc_espera_cola", true);
const procesamiento = new Trend("mooc_procesamiento", true);
const totalSubida = new Trend("mooc_total_subida", true);
const hlsSegmento = new Trend("mooc_hls_segmento", true);
const listos = new Counter("mooc_videos_listos");
const fallosReady = new Rate("mooc_ready_fallido");

export const options = {
  scenarios: {
    profesores: {
      executor: "constant-vus",
      exec: "subirVideo",
      vus: PROFESORES,
      duration: MESETA,
      tags: { escenario: "profesores" },
    },
    estudiantes: {
      executor: "constant-vus",
      exec: "consumirHLS",
      vus: ESTUDIANTES,
      duration: MESETA,
      tags: { escenario: "estudiantes" },
    },
  },
  thresholds: {
    http_req_failed: [{ threshold: "rate<0.05", abortOnFail: false }],
    mooc_ready_fallido: ["rate<0.2"],
    checks: ["rate>0.9"],
  },
};

export function setup() {
  if (!escenario.profesores?.length) {
    throw new Error(
      "el escenario no tiene profesores: vuelve a sembrar (SEED_TEACHERS>=1). " +
        "El semillero de Etapa 1 no bastaba para este escenario.",
    );
  }
  if (!escenario.estudiantes?.length || escenario.estudiantes.length < ESTUDIANTES) {
    throw new Error(
      `hacen falta ${ESTUDIANTES} estudiantes (hay ${escenario.estudiantes?.length ?? 0}). ` +
        `SEED_STUDENTS=${ESTUDIANTES}`,
    );
  }
  for (const nombre of nombres) {
    if (!binarios[nombre] || binarios[nombre].byteLength < 32) {
      throw new Error(
        `falta el perfil ${nombre} (${PERFILES[nombre].archivo}). ` +
          `Genera los perfiles: load/perfiles/generar.sh`,
      );
    }
  }

  const profesor = escenario.profesores[0];
  const publicados = prepararCursoPublicado(profesor);
  return {
    course_id: publicados.course_id,
    recursos_video: publicados.recursos,
    perfiles: nombres,
    cantidades: escenario.cantidades || {},
  };
}

function auth(token) {
  return {
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
  };
}

function campo(obj, ...nombres) {
  if (!obj) return undefined;
  for (const n of nombres) {
    if (obj[n] !== undefined && obj[n] !== null) return obj[n];
  }
  return undefined;
}

function prepararCursoPublicado(profesor) {
  const cfg = auth(profesor.token);
  const marca = `${Date.now()}`;
  const alta = http.post(
    `${BASE}/api/v1/courses`,
    JSON.stringify({ slug: `carga-e2-${marca}`, title: "Carga escenario 2" }),
    cfg,
  );
  if (alta.status !== 201) {
    throw new Error(`setup: no se pudo crear el curso (${alta.status}): ${alta.body}`);
  }
  const courseId = alta.json("course_id");
  const versionId = alta.json("version_id");

  const meta = http.patch(
    `${BASE}/api/v1/courses/versions/${versionId}`,
    JSON.stringify({
      title: "Carga escenario 2",
      summary: "Vídeos sintéticos de los tres perfiles.",
      description_md: "Generado por load/escenario2.js.",
      category: "Infraestructura",
      level: "Introductorio",
      language: "es",
      approval_min_score: 60,
      approval_required_resources_pct: 0,
    }),
    cfg,
  );
  if (meta.status !== 200) {
    throw new Error(`setup: metadatos (${meta.status}): ${meta.body}`);
  }

  const modulo = http.post(
    `${BASE}/api/v1/courses/versions/${versionId}/modules`,
    JSON.stringify({ title: "Vídeos", position: 1 }),
    cfg,
  );
  const moduloId = campo(modulo.json(), "ID", "id");
  const unidad = http.post(
    `${BASE}/api/v1/courses/versions/${versionId}/modules/${moduloId}/units`,
    JSON.stringify({ title: "Perfiles", position: 1 }),
    cfg,
  );
  const unidadId = campo(unidad.json(), "ID", "id");

  const recursos = [];
  for (let i = 0; i < nombres.length; i++) {
    const nombre = nombres[i];
    const creado = http.post(
      `${BASE}/api/v1/courses/versions/${versionId}/units/${unidadId}/resources`,
      JSON.stringify({
        type: PERFILES[nombre].tipo,
        title: `Perfil ${nombre}`,
        position: i + 1,
        visible: true,
        required: false,
        downloadable: false,
      }),
      cfg,
    );
    const resourceId = campo(creado.json(), "ID", "id");
    if (!resourceId) {
      throw new Error(`setup: no se creó el recurso ${nombre}: ${creado.status} ${creado.body}`);
    }
    const r = subirYEsperar(profesor.token, versionId, resourceId, nombre);
    if (r.estado !== "ready") {
      throw new Error(`setup: el perfil ${nombre} no quedó ready (${r.estado})`);
    }
    recursos.push({ id: resourceId, perfil: nombre });
  }

  const pub = http.post(`${BASE}/api/v1/courses/versions/${versionId}/publish`, null, cfg);
  if (pub.status !== 200) {
    throw new Error(`setup: publicar (${pub.status}): ${pub.body}`);
  }
  return { course_id: courseId, version_id: versionId, recursos };
}

function subirYEsperar(token, versionId, resourceId, perfil) {
  const cfg = auth(token);
  const t0 = Date.now();
  const cuerpo = binarios[perfil];
  const sha = crypto.sha256(cuerpo, "hex");

  const tFirma = Date.now();
  const urlRes = http.post(
    `${BASE}/api/v1/courses/versions/${versionId}/resources/${resourceId}/upload-url`,
    JSON.stringify({ mime_type: PERFILES[perfil].mime }),
    { ...cfg, tags: { fase: "firma", perfil } },
  );
  firma.add(Date.now() - tFirma);
  if (!check(urlRes, { "firma 200": (r) => r.status === 200 })) {
    return { estado: "error_firma" };
  }
  const uploadUrl = urlRes.json("upload_url");

  const tPut = Date.now();
  const put = http.put(uploadUrl, cuerpo, {
    headers: { "Content-Type": PERFILES[perfil].mime },
    tags: { fase: "transferencia", perfil, name: "PUT bucket" },
    timeout: "10m",
  });
  transferencia.add(Date.now() - tPut);
  if (!check(put, { "transferencia 2xx": (r) => r.status >= 200 && r.status < 300 })) {
    return { estado: "error_transferencia" };
  }

  const tConf = Date.now();
  const conf = http.post(
    `${BASE}/api/v1/courses/versions/${versionId}/resources/${resourceId}/confirm-upload`,
    JSON.stringify({ checksum_sha256: sha }),
    { ...cfg, tags: { fase: "confirmacion", perfil } },
  );
  confirmacion.add(Date.now() - tConf);
  if (!check(conf, { "confirmación 202/200": (r) => r.status === 202 || r.status === 200 })) {
    return { estado: "error_confirmacion" };
  }

  let vistoProcessing = false;
  let tProcessing = 0;
  const tCola = Date.now();
  let estado = "pending";
  const limite = Date.now() + TIMEOUT_READY_S * 1000;
  while (Date.now() < limite) {
    sleep(POLL_S);
    estado = estadoDe(token, versionId, resourceId);
    if (estado === "processing" && !vistoProcessing) {
      vistoProcessing = true;
      tProcessing = Date.now();
      esperaCola.add(tProcessing - tCola);
    }
    if (estado === "ready") {
      if (vistoProcessing) procesamiento.add(Date.now() - tProcessing);
      else esperaCola.add(Date.now() - tCola);
      totalSubida.add(Date.now() - t0);
      listos.add(1);
      fallosReady.add(0);
      return { estado };
    }
    if (estado === "failed") break;
  }
  fallosReady.add(1);
  totalSubida.add(Date.now() - t0);
  return { estado };
}

function estadoDe(token, versionId, resourceId) {
  const res = http.get(`${BASE}/api/v1/courses/versions/${versionId}`, auth(token));
  if (res.status !== 200) return "desconocido";
  const version = res.json();
  const recursos = (version.Modules || version.modules || []).flatMap((m) =>
    (m.Units || m.units || []).flatMap((u) => u.Resources || u.resources || []),
  );
  const r = recursos.find((x) => String(campo(x, "ID", "id")) === String(resourceId));
  return campo(r, "ProcessingStatus", "processing_status") || "desconocido";
}

export function subirVideo() {
  const profesores = escenario.profesores;
  const profesor = profesores[(exec.vu.idInTest - 1) % profesores.length];
  const perfil = nombres[(exec.vu.iterationInScenario + exec.vu.idInTest) % nombres.length];
  const cfg = auth(profesor.token);
  const marca = `${exec.vu.idInTest}-${exec.vu.iterationInScenario}-${Date.now()}`;

  const alta = http.post(
    `${BASE}/api/v1/courses`,
    JSON.stringify({ slug: `e2-${marca}`, title: `Subida ${perfil} ${marca}` }),
    { ...cfg, tags: { escenario: "profesores" } },
  );
  if (!check(alta, { "curso creado": (r) => r.status === 201 })) return;
  const versionId = alta.json("version_id");

  http.patch(
    `${BASE}/api/v1/courses/versions/${versionId}`,
    JSON.stringify({
      title: `Subida ${perfil}`,
      summary: "Carga escenario 2",
      description_md: "Borrador de carga; no hace falta publicarlo.",
      category: "Infraestructura",
      level: "Introductorio",
      language: "es",
    }),
    cfg,
  );

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
    JSON.stringify({
      type: PERFILES[perfil].tipo,
      title: perfil,
      position: 1,
      visible: true,
      required: false,
      downloadable: false,
    }),
    cfg,
  );
  const resourceId = campo(creado.json(), "ID", "id");
  if (!resourceId) return;

  subirYEsperar(profesor.token, versionId, resourceId, perfil);
  sleep(1);
}

export function consumirHLS(data) {
  const cuenta = escenario.estudiantes[(exec.vu.idInTest - 1) % escenario.estudiantes.length];
  const cfg = auth(cuenta.token);
  const tags = { escenario: "estudiantes" };
  const recursos = data.recursos_video || [];
  if (recursos.length === 0) return;
  const rec = recursos[Math.floor(Math.random() * recursos.length)];

  const insc = http.post(
    `${BASE}/api/v1/enrollments`,
    JSON.stringify({ course_id: data.course_id }),
    { ...cfg, tags },
  );
  check(insc, { "inscripción 201/409": (r) => r.status === 201 || r.status === 409 });

  const contenido = http.get(`${BASE}/api/v1/resources/${rec.id}/content`, { ...cfg, tags });
  if (!check(contenido, { "manifiesto autorizado": (r) => r.status === 200 })) {
    sleep(2);
    return;
  }
  const masterUrl = contenido.json("url");
  if (!masterUrl) {
    sleep(2);
    return;
  }

  reproducirLista(masterUrl, 1);
}

function reproducirLista(url, profundidad) {
  if (profundidad > 3) return;
  const res = http.get(url, { tags: { escenario: "estudiantes", name: "GET HLS" }, timeout: "2m" });
  if (!check(res, { "lista HLS 200": (r) => r.status === 200 })) return;
  const base = url.replace(/[^/]+(\?.*)?$/, "");
  const lineas = String(res.body || "").split(/\r?\n/);
  let duracion = 2;
  for (const linea of lineas) {
    if (linea.startsWith("#EXTINF:")) {
      const n = parseFloat(linea.slice(8));
      if (!Number.isNaN(n) && n > 0) duracion = n;
      continue;
    }
    if (!linea || linea.startsWith("#")) continue;
    const abs = linea.startsWith("http") ? linea : base + linea;
    if (linea.includes(".m3u8")) {
      reproducirLista(abs, profundidad + 1);
      continue;
    }
    const t = Date.now();
    const seg = http.get(abs, { tags: { escenario: "estudiantes", name: "GET segmento HLS" }, timeout: "2m" });
    hlsSegmento.add(Date.now() - t);
    check(seg, { "segmento 200": (r) => r.status === 200 });
    sleep(duracion);
  }
}

export function handleSummary(data) {
  return {
    stdout: resumenLegible(data),
    [`${SALIDA}/resumen-escenario2.json`]: JSON.stringify(data, null, 2),
  };
}

function resumenLegible(data) {
  const m = data.metrics;
  const ms = (nombre, q) => {
    const v = m[nombre];
    return v && v.values ? `${(v.values[q] ?? 0).toFixed(0)} ms` : "—";
  };
  return [
    "",
    "Prueba de carga — Escenario 2 (capacidad)",
    "========================================",
    `Profesores VU:      ${PROFESORES}`,
    `Estudiantes VU:     ${ESTUDIANTES}`,
    `Vídeos listos:      ${m.mooc_videos_listos?.values?.count ?? 0}`,
    `p50/p95/p99 firma:           ${ms("mooc_firma", "p(50)")} / ${ms("mooc_firma", "p(95)")} / ${ms("mooc_firma", "p(99)")}`,
    `p50/p95/p99 transferencia:   ${ms("mooc_transferencia", "p(50)")} / ${ms("mooc_transferencia", "p(95)")} / ${ms("mooc_transferencia", "p(99)")}`,
    `p50/p95/p99 confirmación:    ${ms("mooc_confirmacion", "p(50)")} / ${ms("mooc_confirmacion", "p(95)")} / ${ms("mooc_confirmacion", "p(99)")}`,
    `p50/p95/p99 espera cola:     ${ms("mooc_espera_cola", "p(50)")} / ${ms("mooc_espera_cola", "p(95)")} / ${ms("mooc_espera_cola", "p(99)")}`,
    `p50/p95/p99 procesamiento:   ${ms("mooc_procesamiento", "p(50)")} / ${ms("mooc_procesamiento", "p(95)")} / ${ms("mooc_procesamiento", "p(99)")}`,
    `p50/p95/p99 total subida:    ${ms("mooc_total_subida", "p(50)")} / ${ms("mooc_total_subida", "p(95)")} / ${ms("mooc_total_subida", "p(99)")}`,
    `p50/p95/p99 segmento HLS:    ${ms("mooc_hls_segmento", "p(50)")} / ${ms("mooc_hls_segmento", "p(95)")} / ${ms("mooc_hls_segmento", "p(99)")}`,
    `Tasa de error HTTP: ${((m.http_req_failed?.values?.rate ?? 0) * 100).toFixed(3)} %`,
    "",
  ].join("\n");
}
