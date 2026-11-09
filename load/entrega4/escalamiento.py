#!/usr/bin/env python3
"""Verificación de escalamiento de la Entrega 4 (Cloud Run + Pub/Sub).

Carga controlada en dos fases, solo con la biblioteca estándar:

  api      N hilos piden el catálogo (GET /api/v1/catalog) durante S segundos
           a través del balanceador. Mide estados y latencias; Cloud Run
           escala la API por peticiones simultáneas.
  workers  Un profesor crea un curso borrador con K recursos de video, sube
           el mismo MP4 a cada uno y confirma las K cargas de golpe: la API
           publica K mensajes en Pub/Sub y responde sin esperar. Con una tarea
           por instancia de worker, los mensajes pendientes hacen que Cloud Run
           levante workers hasta el máximo (3). Se sigue cada recurso hasta
           'ready' y se registra cuándo cambió de estado.

Las métricas de instancias y de mensajes pendientes se leen de Cloud
Monitoring con load/entrega4/metricas.sh durante y después de la corrida.

  export MOOC_URL=https://<ip>.sslip.io
  export PROFESOR_EMAIL=... PROFESOR_PASSWORD=...
  python3 load/entrega4/escalamiento.py api --hilos 120 --segundos 120
  python3 load/entrega4/escalamiento.py workers --videos 9 --archivo data/catalogo/medios/docker-en-un-minuto.mp4

La salida (JSON con cada evento y un resumen) queda en load/salida/.
"""

import argparse
import hashlib
import http.cookiejar
import json
import os
import statistics
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from datetime import datetime, timezone

BASE = os.environ.get("MOOC_URL", "").rstrip("/")
SALIDA = os.path.join(os.path.dirname(__file__), "..", "salida")


def ahora():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


class Sesion:
    """Un "navegador": cookie de sesión y token anti-CSRF, como el frontend."""

    def __init__(self):
        self.jar = http.cookiejar.CookieJar()
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar))

    def csrf(self):
        for c in self.jar:
            if c.name == "mooc_csrf":
                return urllib.parse.unquote(c.value)
        return None

    def pedir(self, metodo, ruta, cuerpo=None, intentos=5):
        datos = None if cuerpo is None else json.dumps(cuerpo).encode()
        for intento in range(1, intentos + 1):
            req = urllib.request.Request(BASE + ruta, data=datos, method=metodo)
            req.add_header("Content-Type", "application/json")
            if metodo != "GET" and self.csrf():
                req.add_header("X-CSRF-Token", self.csrf())
            try:
                with self.op.open(req, timeout=120) as r:
                    texto = r.read().decode() or "null"
                    return r.status, json.loads(texto)
            except urllib.error.HTTPError as e:
                texto = e.read().decode(errors="replace")
                if e.code == 429 and intento < intentos:
                    time.sleep(20)
                    continue
                return e.code, texto
            except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
                # fallos de red del lado del generador (DNS, reset): se reintenta
                if intento < intentos:
                    time.sleep(2 * intento)
                    continue
                return "red", str(e)

    def login(self, email, clave):
        estado, cuerpo = self.pedir("POST", "/api/v1/auth/login", {"email": email, "password": clave})
        if estado != 200:
            sys.exit(f"login de {email}: {estado} {cuerpo}")


def campo(obj, *nombres):
    for n in nombres:
        if isinstance(obj, dict) and obj.get(n) is not None:
            return obj[n]
    return None


# --- Fase API -----------------------------------------------------------------


def fase_api(args):
    fin = time.time() + args.segundos
    estados, latencias, lock = Counter(), [], threading.Lock()

    def golpear():
        while time.time() < fin:
            t0 = time.time()
            try:
                with urllib.request.urlopen(BASE + args.ruta, timeout=30) as r:
                    r.read()
                    codigo = r.status
            except urllib.error.HTTPError as e:
                codigo = e.code
            except Exception:
                codigo = "error"
            with lock:
                estados[codigo] += 1
                latencias.append(time.time() - t0)

    print(f"{ahora()} api: {args.hilos} hilos contra {BASE}{args.ruta} durante {args.segundos} s")
    inicio = ahora()
    hilos = [threading.Thread(target=golpear, daemon=True) for _ in range(args.hilos)]
    for h in hilos:
        h.start()
    for h in hilos:
        h.join()
    latencias.sort()
    total = len(latencias)
    resumen = {
        "fase": "api",
        "inicio": inicio,
        "fin": ahora(),
        "hilos": args.hilos,
        "segundos": args.segundos,
        "ruta": args.ruta,
        "peticiones": total,
        "rps": round(total / args.segundos, 1),
        "estados": {str(k): v for k, v in estados.items()},
        "p50_ms": round(statistics.median(latencias) * 1000) if total else None,
        "p95_ms": round(latencias[int(total * 0.95) - 1] * 1000) if total else None,
        "p99_ms": round(latencias[int(total * 0.99) - 1] * 1000) if total else None,
    }
    guardar("api", resumen)


# --- Fase workers -------------------------------------------------------------


def fase_workers(args):
    email = os.environ.get("PROFESOR_EMAIL")
    clave = os.environ.get("PROFESOR_PASSWORD")
    if not (email and clave):
        sys.exit("faltan PROFESOR_EMAIL y PROFESOR_PASSWORD")
    contenido = open(args.archivo, "rb").read()
    sha = hashlib.sha256(contenido).hexdigest()

    s = Sesion()
    s.login(email, clave)
    marca = datetime.now().strftime("%m%d%H%M%S")
    estado, curso = s.pedir("POST", "/api/v1/courses", {"slug": f"escala-e4-{marca}", "title": f"Escalamiento E4 {marca}"})
    if estado != 201:
        sys.exit(f"crear curso: {estado} {curso}")
    version = curso["version_id"]
    _, modulo = s.pedir("POST", f"/api/v1/courses/versions/{version}/modules", {"title": "Carga", "position": 1})
    _, unidad = s.pedir("POST", f"/api/v1/courses/versions/{version}/modules/{campo(modulo, 'ID', 'id')}/units", {"title": "Videos", "position": 1})
    unidad_id = campo(unidad, "ID", "id")

    recursos = []
    for i in range(args.videos):
        estado, r = s.pedir("POST", f"/api/v1/courses/versions/{version}/units/{unidad_id}/resources", {
            "type": "video", "title": f"Video {i + 1}", "position": i + 1,
            "visible": True, "required": False, "downloadable": False,
        })
        rid = campo(r, "ID", "id")
        if not rid:
            sys.exit(f"crear recurso: {estado} {r}")
        # Firmar y subir antes de confirmar: así las K confirmaciones (las que
        # publican en Pub/Sub) salen juntas.
        estado, firma = s.pedir("POST", f"/api/v1/courses/versions/{version}/resources/{rid}/upload-url", {"mime_type": "video/mp4"})
        if estado != 200:
            sys.exit(f"upload-url: {estado} {firma}")
        put = urllib.request.Request(firma["upload_url"], data=contenido, method="PUT")
        put.add_header("Content-Type", "video/mp4")
        for intento in range(5):
            try:
                with urllib.request.urlopen(put, timeout=300) as res:
                    res.read()
                break
            except urllib.error.URLError:
                time.sleep(2 * (intento + 1))
        recursos.append({"id": rid})
    print(f"{ahora()} workers: {len(recursos)} originales subidos al bucket; confirmando todas las cargas")

    eventos = []

    def confirmar(rec):
        t0 = time.time()
        estado, cuerpo = s.pedir("POST", f"/api/v1/courses/versions/{version}/resources/{rec['id']}/confirm-upload", {"checksum_sha256": sha})
        rec["confirmado"] = ahora()
        rec["confirmacion_ms"] = round((time.time() - t0) * 1000)
        rec["confirmacion_estado"] = estado

    hilos = [threading.Thread(target=confirmar, args=(r,)) for r in recursos]
    for h in hilos:
        h.start()
    for h in hilos:
        h.join()
    print(f"{ahora()} workers: confirmaciones {Counter(r['confirmacion_estado'] for r in recursos)}; "
          f"la API respondió en {max(r['confirmacion_ms'] for r in recursos)} ms como máximo (no espera a los workers)")

    pendientes = {r["id"]: r for r in recursos}
    ultimo = {}
    limite = time.time() + args.limite
    while pendientes and time.time() < limite:
        time.sleep(3)
        estado, v = s.pedir("GET", f"/api/v1/courses/versions/{version}")
        if estado != 200:
            continue
        todos = [x for m in (v.get("Modules") or v.get("modules") or [])
                 for u in (m.get("Units") or m.get("units") or [])
                 for x in (u.get("Resources") or u.get("resources") or [])]
        for x in todos:
            rid = str(campo(x, "ID", "id"))
            st = campo(x, "ProcessingStatus", "processing_status")
            if rid in pendientes and ultimo.get(rid) != st:
                ultimo[rid] = st
                pendientes[rid][f"t_{st}"] = ahora()
                eventos.append({"t": ahora(), "recurso": rid, "estado": st})
                print(f"{ahora()}   {rid[:8]} -> {st}")
                if st in ("ready", "failed"):
                    pendientes.pop(rid)

    resumen = {
        "fase": "workers",
        "curso_version": version,
        "videos": args.videos,
        "archivo": os.path.basename(args.archivo),
        "bytes": len(contenido),
        "finales": dict(Counter(ultimo.values())),
        "sin_terminar": list(pendientes),
        "recursos": recursos,
        "eventos": eventos,
    }
    guardar("workers", resumen)


def guardar(nombre, resumen):
    os.makedirs(SALIDA, exist_ok=True)
    ruta = os.path.join(SALIDA, f"e4-{nombre}-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json")
    with open(ruta, "w") as f:
        json.dump(resumen, f, indent=2, ensure_ascii=False)
    print(json.dumps({k: v for k, v in resumen.items() if k not in ("recursos", "eventos")}, indent=2, ensure_ascii=False))
    print(f"guardado en {ruta}")


def main():
    if not BASE:
        sys.exit("falta MOOC_URL (https://<ip>.sslip.io)")
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="fase", required=True)
    a = sub.add_parser("api")
    a.add_argument("--hilos", type=int, default=120)
    a.add_argument("--segundos", type=int, default=120)
    a.add_argument("--ruta", default="/api/v1/catalog")
    w = sub.add_parser("workers")
    w.add_argument("--videos", type=int, default=9)
    w.add_argument("--archivo", default="data/catalogo/medios/docker-en-un-minuto.mp4")
    w.add_argument("--limite", type=int, default=900, help="segundos máximos esperando 'ready'")
    args = p.parse_args()
    {"api": fase_api, "workers": fase_workers}[args.fase](args)


if __name__ == "__main__":
    main()
