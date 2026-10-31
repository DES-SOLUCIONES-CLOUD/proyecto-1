"""resume en markdown los resultados que deja analizar.sh

    python3 resumen.py <dir-evidencia> <commit> <url-servidor>

lee medidas.json, puerta.json y hallazgos.json (tal cual los devuelve la api
de sonarqube) e imprime las tablas que se copian a
docs/entrega3/deuda-tecnica.md: metricas, puerta de calidad e inventario
"""

import json
import sys
from collections import Counter
from pathlib import Path

NOTAS = {"1.0": "A", "2.0": "B", "3.0": "C", "4.0": "D", "5.0": "E"}
SEVERIDADES = ["BLOCKER", "CRITICAL", "MAJOR", "MINOR", "INFO"]
NOMBRES = {
    "BLOCKER": "Bloqueante",
    "CRITICAL": "Critico",
    "MAJOR": "Mayor",
    "MINOR": "Menor",
    "INFO": "Informativo",
}
METRICAS = [
    ("ncloc", "Lineas de codigo"),
    ("duplicated_lines_density", "Duplicacion (%)"),
    ("duplicated_blocks", "Bloques duplicados"),
    ("sqale_rating", "Mantenibilidad"),
    ("sqale_index", "Deuda tecnica (min)"),
    ("sqale_debt_ratio", "Ratio de deuda (%)"),
    ("reliability_rating", "Confiabilidad"),
    ("security_rating", "Seguridad"),
    ("bugs", "Bugs"),
    ("vulnerabilities", "Vulnerabilidades"),
    ("code_smells", "Code smells"),
    ("security_hotspots", "Security hotspots"),
    ("coverage", "Cobertura (%)"),
]


def leer(directorio: Path, nombre: str) -> dict:
    return json.loads((directorio / nombre).read_text(encoding="utf-8"))


def valor(clave: str, crudo: str) -> str:
    if clave.endswith("_rating"):
        return NOTAS.get(crudo, crudo)
    return crudo


def main() -> None:
    directorio, commit, servidor = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    medidas = {m["metric"]: m.get("value", "-") for m in leer(directorio, "medidas.json")["component"]["measures"]}
    puerta = leer(directorio, "puerta.json")["projectStatus"]
    hallazgos = leer(directorio, "hallazgos.json")

    print(f"## SonarQube: commit `{commit}`\n")
    print(f"Puerta de calidad: **{puerta['status']}** ({servidor})\n")

    print("| Metrica | Valor |")
    print("|---|---|")
    for clave, nombre in METRICAS:
        print(f"| {nombre} | {valor(clave, medidas.get(clave, '-'))} |")

    if puerta.get("conditions"):
        print("\n| Condicion | Umbral | Medido | Estado |")
        print("|---|---|---|---|")
        for c in puerta["conditions"]:
            print(f"| {c['metricKey']} | {c.get('comparator', '')} {c.get('errorThreshold', '')} "
                  f"| {c.get('actualValue', '-')} | {c['status']} |")

    issues = hallazgos.get("issues", [])
    por_severidad = Counter(i.get("severity", "INFO") for i in issues)
    print(f"\n### Hallazgos abiertos: {hallazgos.get('total', len(issues))}\n")
    print("| Severidad | Cantidad |")
    print("|---|---|")
    for s in SEVERIDADES:
        print(f"| {NOMBRES[s]} | {por_severidad.get(s, 0)} |")

    # se agrupa por regla porque veinte casos de la misma regla se tratan
    # con una sola decision
    grupos: dict[tuple[str, str], list[dict]] = {}
    for i in issues:
        grupos.setdefault((i.get("severity", "INFO"), i["rule"]), []).append(i)
    orden = sorted(grupos.items(), key=lambda kv: (SEVERIDADES.index(kv[0][0]), -len(kv[1])))

    print("\n### Inventario por regla\n")
    print("| Severidad | Regla | Tipo | Casos | Ejemplo (archivo:linea) | Mensaje |")
    print("|---|---|---|---|---|---|")
    for (severidad, regla), casos in orden:
        ejemplo = casos[0]
        archivo = ejemplo["component"].split(":", 1)[-1]
        linea = ejemplo.get("line", "")
        mensaje = ejemplo.get("message", "").replace("|", "\\|")
        print(f"| {NOMBRES[severidad]} | `{regla}` | {ejemplo.get('type', '')} | {len(casos)} "
              f"| `{archivo}:{linea}` | {mensaje} |")

    # el enunciado pide la ubicacion de todo hallazgo mayor o superior que siga
    # abierto, y arriba solo sale un ejemplo por regla
    print("\n### Ubicaciones de los hallazgos Mayor o superior\n")
    print("| Severidad | Regla | Ubicaciones |")
    print("|---|---|---|")
    for (severidad, regla), casos in orden:
        if SEVERIDADES.index(severidad) > SEVERIDADES.index("MAJOR"):
            continue
        ubicaciones = sorted(f"{c['component'].split(':', 1)[-1]}:{c.get('line', '')}" for c in casos)
        lista = "<br>".join(f"`{u}`" for u in ubicaciones)
        print(f"| {NOMBRES[severidad]} | `{regla}` | {lista} |")


if __name__ == "__main__":
    main()
