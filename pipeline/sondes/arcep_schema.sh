#!/usr/bin/env bash
# Inspecte le schéma d'un fichier de couverture Arcep (champs, valeurs, SCR), la licence du jeu de
# données, les contours Etalab et l'ordre des couches des styles Plan IGN.
set -u
. "$(dirname "$0")/_lib.sh"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq p7zip-full >/dev/null 2>&1
BASE="https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/00_Metropole"

echo "##### 1. Listing complet"
get "$T/arcep.html" "$BASE/"
python3 - <<'PY'
import re
s = open("/tmp/sonde/arcep.html", encoding="utf-8", errors="replace").read()
print("fil d'Ariane:", re.findall(r'breadcrumb-item"><a href="[^"]*">([^<]+)</a>', s))
for m in re.finditer(r'<a href="([^"]+\.7z)"[^>]*>.*?data-size="(\d+)".*?datetime="([^"]+)"', s, flags=re.S):
    print(f"  {m.group(1)} | {int(m.group(2))/1e6:.1f} Mo | {m.group(3)}")
PY

echo "##### 2. Licence (API data.gouv.fr)"
get "$T/dg.json" "https://www.data.gouv.fr/api/1/datasets/mon-reseau-mobile/"
python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/dg.json"))
    print("titre:", d.get("title"), "| licence:", d.get("license"), "| frequence:", d.get("frequency"), "| maj:", d.get("last_modified"))
    print("organisation:", (d.get("organization") or {}).get("name"), "| page:", d.get("page"))
    print("description:", (d.get("description") or "")[:1500].replace("\n", " "))
except Exception as e:
    print("ERREUR", e)
PY
get "$T/lic.json" "https://www.data.gouv.fr/api/1/datasets/licenses/"
python3 - <<'PY'
import json
try:
    for l in json.load(open("/tmp/sonde/lic.json")):
        if l.get("id") in ("lov2", "fr-lo", "odc-odbl", "notspecified"):
            print("  licence", l.get("id"), "|", l.get("title"), "|", l.get("url"))
except Exception as e:
    print("ERREUR", e)
PY

echo "##### 3. Téléchargement Orange 4G data"
F=2026_T2_couv_Metropole_OF_4G_data.gpkg.7z
cd "$T"
SECONDS=0
curl -sS -L -m 1800 -A "$UA" -o "$F" -w "  -> %{http_code} %{size_download}o en %{time_total}s (%{speed_download} o/s)\n" "$BASE/$F"
echo "telechargement: ${SECONDS}s"
SECONDS=0
7z l "$F" | tail -8
7z x -y "$F" >/dev/null
echo "extraction: ${SECONDS}s"
ls -la "$T" | grep -i -E "gpkg|shp|7z"
G=$(ls "$T"/*.gpkg | head -1)
echo "fichier: $G"

echo "##### 4. Schéma (ogrinfo -so -al)"
ogrinfo -so -al "$G" 2>&1 | head -80

echo "##### 5. Valeurs distinctes et géométries"
python3 - "$G" <<'PY'
import sys, time
from osgeo import ogr, gdal
gdal.UseExceptions()
ds = ogr.Open(sys.argv[1])
print("pilote:", ds.GetDriver().GetName(), "| couches:", ds.GetLayerCount())
for i in range(ds.GetLayerCount()):
    lyr = ds.GetLayerByIndex(i)
    name = lyr.GetName()
    defn = lyr.GetLayerDefn()
    srs = lyr.GetSpatialRef()
    print(f"couche {name!r} | entites: {lyr.GetFeatureCount()} | geom: {ogr.GeometryTypeToName(lyr.GetGeomType())} | colonne geom: {lyr.GetGeometryColumn()!r} | FID: {lyr.GetFIDColumn()!r}")
    print("  SCR:", srs.GetAuthorityName(None), srs.GetAuthorityCode(None), "|", srs.GetName() if srs else None)
    print("  emprise:", lyr.GetExtent())
    for j in range(defn.GetFieldCount()):
        fd = defn.GetFieldDefn(j)
        fname = fd.GetName()
        t0 = time.time()
        res = ds.ExecuteSQL(f'SELECT "{fname}" AS v, COUNT(*) AS n FROM "{name}" GROUP BY "{fname}" ORDER BY n DESC LIMIT 15')
        vals = [(f.GetField(0), f.GetField(1)) for f in res]
        ds.ReleaseResultSet(res)
        print(f"  champ {fname!r} ({fd.GetTypeName()}) -> {vals} [{time.time()-t0:.1f}s]")
    # tailles des géométries
    t0 = time.time()
    lyr.ResetReading()
    stats = []
    for k, f in enumerate(lyr):
        g = f.GetGeometryRef()
        if g is None:
            stats.append((k, None)); continue
        env = g.GetEnvelope()
        stats.append((f.GetFID(), g.GetGeometryName(), g.GetGeometryCount(), g.WkbSize(), [round(v) for v in env], [f.GetField(j) for j in range(defn.GetFieldCount())]))
        if k >= 11: break
    for s in stats: print("   entite:", s)
    print(f"  lecture des 12 premieres entites: {time.time()-t0:.1f}s")
PY

echo "##### 6. Contours Etalab (départements)"
get "$T/dep.geojson.gz" "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/departements-5m.geojson.gz"
gunzip -f "$T/dep.geojson.gz"
ogrinfo -so -al "$T/dep.geojson" 2>&1 | head -30
ogrinfo -q -sql "SELECT code, nom, region FROM \"dep\" WHERE code IN ('05','2A','2B','75','971')" "$T/dep.geojson" 2>&1 | grep -E "code|nom|region" | paste - - - | head
get "$T/readme" "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/"
texte "$T/readme" 1500
get "$T/dgc.json" "https://www.data.gouv.fr/api/1/datasets/contours-administratifs-1/"
python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/dgc.json"))
    print("titre:", d.get("title"), "| licence:", d.get("license"), "| organisation:", (d.get("organization") or {}).get("name"), "| page:", d.get("page"))
    print("description:", (d.get("description") or "")[:800].replace("\n", " "))
except Exception as e:
    print("ERREUR", e)
PY

echo "##### 7. Ordre des couches du style classique"
get "$T/classique.json" "https://data.geopf.fr/annexes/ressources/vectorTiles/styles/PLAN.IGN/classique.json"
python3 - <<'PY'
import json
d = json.load(open("/tmp/sonde/classique.json"))
for i, l in enumerate(d["layers"]):
    p = l.get("paint", {})
    op = p.get("fill-opacity", p.get("line-opacity", ""))
    print(f"L|{i}|{l['type']}|{l['id']}|{l.get('source-layer')}|{l.get('minzoom','')}|{l.get('maxzoom','')}|{json.dumps(op)[:40]}")
PY
echo "FIN"
