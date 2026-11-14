#!/usr/bin/env bash
# Sonde Espagne 7 (très courte) : les entités sans commune (CCOM vide) comptent-elles dans les Pyrénées ?
# Sert à décider si le filtre par région (CCOM) suffit ou s'il faut un filtre spatial. Une dizaine de petites requêtes.
set -u
. "$(dirname "$0")/_lib.sh"
export UA
python3 - <<'PY'
import json, os, time, urllib.error, urllib.parse, urllib.request

UA = os.environ.get("UA") or "carte-zones-blanches-sonde/1.0"
F4 = "https://services-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/InfoCob4G_2024/FeatureServer/0"
NOMS = {"A78923125": "Telefónica Móviles", "A80907397": "Vodafone", "A82009812": "Orange", "A82528548": "Xfera"}
CELL = 0.000346111018645788 ** 2


def q(params):
    url = F4 + "/query?" + urllib.parse.urlencode(params)
    time.sleep(0.4)
    t0 = time.time()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=240) as r:
            j = json.loads(r.read().decode("utf-8", "replace"))
    except Exception as e:  # noqa: BLE001
        return {"error": repr(e)[:200]}, time.time() - t0
    return j, time.time() - t0


def env(x0, y0, x1, y1):
    return {"geometry": f"{x0},{y0},{x1},{y1}", "geometryType": "esriGeometryEnvelope", "inSR": "4258", "spatialRel": "esriSpatialRelIntersects"}


boxes = {
    "Pyrénées (-1.0,42.0,2.0,43.0)": (-1.0, 42.0, 2.0, 43.0),
    "intérieur Navarre et Aragon (-1.5,42.3,-0.5,42.9)": (-1.5, 42.3, -0.5, 42.9),
    "Pays basque et côte (-3.2,42.9,-1.7,43.5)": (-3.2, 42.9, -1.7, 43.5),
}
stats = json.dumps([{"statisticType": "count", "onStatisticField": "OBJECTID", "outStatisticFieldName": "n"},
                    {"statisticType": "sum", "onStatisticField": "Shape__Area", "outStatisticFieldName": "aire"},
                    {"statisticType": "max", "onStatisticField": "Shape__Area", "outStatisticFieldName": "aire_max"}])
for name, box in boxes.items():
    print(f"##### {name}", flush=True)
    for label, where in (("toutes les entités", "1=1"), ("CCOM vide", "CCOM=''"), ("CCOM vide et couverture", "CCOM='' AND COBERTURA<>''"),
                         ("CCOM vide, couverture, au moins une maille", f"CCOM='' AND COBERTURA<>'' AND Shape__Area>={CELL * 0.99}")):
        p = {"where": where, "outStatistics": stats, "f": "json"}; p.update(env(*box))
        j, dt = q(p)
        a = ((j.get("features") or [{}])[0].get("attributes") or {}) if "error" not in j else {"erreur": j["error"]}
        aire = a.get("aire") or 0
        print(f"   {label} : n={a.get('n')} ; surface={aire:.6f} deg² (soit {aire / CELL:.0f} mailles) ; plus grande={((a.get('aire_max') or 0) / CELL):.1f} mailles ; {dt:.1f} s" + (f" ; {a.get('erreur')}" if a.get("erreur") else ""), flush=True)
    p = {"where": "CCOM='' AND COBERTURA<>''", "outFields": "OBJECTID,COBERTURA,Shape__Area", "returnGeometry": "false", "returnCentroid": "true",
         "orderByFields": "Shape__Area DESC", "resultRecordCount": "6", "outSR": "4326", "f": "json"}
    p.update(env(*box))
    j, dt = q(p)
    if "error" in j:
        print("   échantillon : ERREUR", json.dumps(j["error"], ensure_ascii=False)[:200])
    for f in j.get("features") or []:
        a, c = f.get("attributes") or {}, f.get("centroid") or {}
        ops = ", ".join(sorted(NOMS.get(x, x) for x in (a.get("COBERTURA") or "").split(";") if x))
        print(f"   plus grandes sans commune : {(a.get('Shape__Area') or 0) / CELL:.1f} mailles, centre ({c.get('x')}, {c.get('y')}), opérateurs : {ops}"[:300], flush=True)
print("FIN")
PY
