#!/usr/bin/env python3
"""Baja una serie de Cloud Monitoring y la imprime como JSON.

    serie-monitoring.py <proyecto> <filtro> <desde> <hasta>

Lo usa metricas.sh. El token sale de gcloud; cualquier error de la API termina
con código distinto de cero para que la corrida no quede sin datos en silencio.
"""
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

proyecto, filtro, desde, hasta = sys.argv[1:5]
token = subprocess.run(
    ["gcloud", "auth", "print-access-token"],
    check=True,
    capture_output=True,
    text=True,
).stdout.strip()

series, pagina = [], ""
while True:
    consulta = {"filter": filtro, "interval.startTime": desde, "interval.endTime": hasta}
    if pagina:
        consulta["pageToken"] = pagina
    url = (
        f"https://monitoring.googleapis.com/v3/projects/{proyecto}/timeSeries?"
        + urllib.parse.urlencode(consulta)
    )
    pedido = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(pedido, timeout=60) as respuesta:
            datos = json.load(respuesta)
    except urllib.error.HTTPError as e:
        sys.exit(f"Monitoring respondió {e.code}: {e.read().decode(errors='replace')[:300]}")
    series += datos.get("timeSeries", [])
    pagina = datos.get("nextPageToken", "")
    if not pagina:
        break

json.dump(series, sys.stdout)
