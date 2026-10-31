// Escenario 3A de capacidad (Entrega 3): ciclo de autoscaling de la API.
//
// Reutiliza el tráfico de catálogo de escenario1.js, pero sin mezcla de
// quiz ni inscripción: el objetivo no es simular un recorrido realista,
// sino sostener suficiente demanda sobre las instancias de la API el tiempo
// necesario para que el autoscaler del MIG decida crear capacidad y,
// después, reducirla.
//
// e2-small tiene CPU compartida (0,5 vCPU sostenida, con ráfaga mientras
// queden créditos de la familia e2 — ver deploy/gcp/README.md § Decisiones):
// una meseta corta puede no bastar, porque la ráfaga absorbe el pico y la
// CPU sostenida tarda en cruzar el umbral. MESETA_ALTA por defecto son
// 6 minutos; si la primera corrida no dispara el escalamiento, es la
// primera perilla que hay que subir (ver docs/entrega3/arquitectura.md,
// sección de verificaciones de salud, para el cooldown configurado).
//
// Esto NO mide latencia de negocio ni trae thresholds de p95: ya los mide
// escenario1.js contra esta misma arquitectura. Lo que importa aquí es la
// serie de instancias del MIG a lo largo del tiempo (Cloud Monitoring,
// fuera de k6: load/observar.sh y load/metricas.sh), correlacionada con las marcas de fase que
// este script imprime por stdout y guarda en el resumen.
//
//   BASE_URL=https://<balanceador> \
//   VUS_REPOSO=5 VUS_PICO=250 RAMPA=30s MESETA_INICIAL=3m MESETA_ALTA=6m MESETA_BAJA=15m \
//   k6 run load/escenario3a.js

import http from "k6/http";
import { check, group, sleep } from "k6";
import { SharedArray } from "k6/data";

const BASE = __ENV.BASE_URL || "http://localhost:8080";
const ESCENARIO = __ENV.ESCENARIO || "/salida/escenario.json";
const SALIDA = __ENV.SALIDA || "/salida";

// Pico alto a propósito: con e2-small y umbral de CPU al 60 %, hace falta
// bastante concurrencia HTTP para que el trabajo de servir esas peticiones
// (JSON desde Postgres, no estático) sostenga la instancia por encima del
// umbral. Si el MIG no escala con el valor por defecto, subir VUS_PICO antes
// que alargar MESETA_ALTA otra vez.
const VUS_REPOSO = Number(__ENV.VUS_REPOSO || 5);
const VUS_PICO = Number(__ENV.VUS_PICO || 250);
const RAMPA = __ENV.RAMPA || "30s";
const MESETA_ALTA = __ENV.MESETA_ALTA || "6m";
const MESETA_INICIAL = __ENV.MESETA_INICIAL || "3m";
// El reposo final tiene que cubrir la ventana de estabilización del autoscaler
// (unos 10 minutos antes de reducir) y lo que tarde en retirarse la instancia.
const MESETA_BAJA = __ENV.MESETA_BAJA || "15m";

const datos = new SharedArray("escenario", () => [JSON.parse(open(ESCENARIO))]);
const escenario = datos[0];

export const options = {
  scenarios: {
    ciclo_api: {
      executor: "ramping-vus",
      exec: "navegar",
      startVUs: VUS_REPOSO,
      stages: [
        { duration: MESETA_INICIAL, target: VUS_REPOSO }, // 1. reposo: una instancia
        { duration: RAMPA, target: VUS_PICO }, // 2. rampa: sube la demanda
        { duration: MESETA_ALTA, target: VUS_PICO }, // 3. meseta alta: fuerza el scale-out
        { duration: RAMPA, target: VUS_REPOSO }, // 4. reduce la demanda
        { duration: MESETA_BAJA, target: VUS_REPOSO }, // 5. reposo: observa el scale-in
      ],
    },
  },
  thresholds: {
    // Sin umbrales de negocio: el objetivo es observar el autoscaler, no
    // certificar latencia. Solo se vigila que el balanceador no caiga.
    http_req_failed: [{ threshold: "rate<0.05", abortOnFail: false }],
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
  if (!escenario.course_id) {
    throw new Error(`el escenario de ${ESCENARIO} no tiene course_id: siembra primero (load/README.md)`);
  }
  const marcas = calcularMarcas(Date.now());
  console.log("");
  console.log("Escenario 3A — ciclo de autoscaling de la API");
  console.log("==============================================");
  console.log(`VUs:   reposo ${VUS_REPOSO} -> pico ${VUS_PICO} -> reposo ${VUS_REPOSO}`);
  console.log(`Fases (hora prevista, UTC):`);
  for (const m of marcas) console.log(`  ${m.fase.padEnd(16)} ${m.inicio}`);
  console.log("");
  console.log("Pegar estas horas en capacity-planning/pruebas_de_carga_entrega3.md");
  console.log("y correlacionarlas con Cloud Monitoring > mig-api (instancias, CPU) y");
  console.log("con el balanceador (incorporación de nuevas instancias saludables).");
  console.log("");
  return { marcas };
}

export function navegar() {
  group("catálogo", () => {
    const lista = http.get(`${BASE}/api/v1/catalog`, { tags: { fase: "catalogo" } });
    check(lista, { "catálogo responde 200": (r) => r.status === 200 });
    const filtrado = http.get(`${BASE}/api/v1/catalog?q=cloud`, { tags: { fase: "catalogo" } });
    check(filtrado, { "búsqueda responde 200": (r) => r.status === 200 });
    const detalle = http.get(`${BASE}/api/v1/catalog/${escenario.course_id}`, {
      tags: { fase: "detalle" },
    });
    check(detalle, { "detalle responde 200": (r) => r.status === 200 });
  });
  sleep(0.3 + Math.random() * 0.7);
}

export function handleSummary(data) {
  return {
    stdout: resumenLegible(data),
    [`${SALIDA}/resumen-escenario3a.json`]: JSON.stringify(data, null, 2),
  };
}

function resumenLegible(data) {
  const m = data.metrics;
  return [
    "",
    "Escenario 3A — resultado",
    "=========================",
    `Peticiones:     ${m.http_reqs?.values?.count ?? 0}`,
    `Tasa de error:  ${((m.http_req_failed?.values?.rate ?? 0) * 100).toFixed(3)} %`,
    `VUs máximos:    ${m.vus_max?.values?.value ?? "—"}`,
    "",
    "Completar a mano desde Cloud Monitoring (load/metricas.sh --corrida esc3a-...):",
    "  - instancias de mig-api en el tiempo (creación, incorporación al LB, reducción)",
    "  - CPU por instancia antes/durante/después de la meseta alta",
    "  - tiempo desde el cruce del umbral hasta la nueva instancia atendiendo tráfico",
    "",
  ].join("\n");
}
