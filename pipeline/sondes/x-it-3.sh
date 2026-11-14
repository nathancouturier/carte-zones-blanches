#!/usr/bin/env bash
# Italie, sonde 3 : couche 4G du service ArcGIS REST de l'AGCOM (Grid100/mobile_4G). Comptages par région,
# extraction paginée de la Vallée d'Aoste, schéma (ogrinfo), surfaces par valeur, essai d'une page du Piémont,
# pagination automatique de GDAL, légendes, éditions, métadonnées « AI-Ready ».
set -u
. "$(dirname "$0")/_lib.sh"
export UA T
mkdir -p "$T/it"
python3 - <<'PY'
import re, os, subprocess, html, json, time
from urllib.parse import urlencode
from osgeo import ogr, osr, gdal
ogr.UseExceptions()

T = os.environ["T"]; UA = os.environ["UA"]
REST = "https://geo3.agcom.it/MapET-SFS/rest/services"
L4G = REST + "/Grid100/mobile_4G/MapServer/0/query"

def fetch(url, out, maxtime=300, data=None):
    cmd = ["curl", "-sS", "-L", "-m", str(maxtime), "-A", UA, "-o", out, "-w", "%{http_code} %{size_download}o %{time_total}s %{content_type}"]
    if data is not None:
        cmd += ["--data", data]
    r = subprocess.run(cmd + [url], capture_output=True, text=True)
    return (r.stdout or r.stderr).strip()

def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""

def show(s, maxc=1500, width=250, indent="    "):
    s = re.sub(r"\s+", " ", s).strip()
    cut = s[:maxc]
    for k in range(0, len(cut), width):
        print(indent + cut[k:k + width])
    if len(s) > maxc:
        print(indent + f"[... tronqué, {len(s)} caractères au total]")

def text_of(s):
    s = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
    return html.unescape(re.sub(r"<[^>]+>", " ", s))

n = [0]
def jget(url, params=None, quiet=False, out=None):
    if params:
        url = url + "?" + urlencode(params)
    n[0] += 1
    out = out or f"{T}/j{n[0]}.json"
    st = fetch(url, out)
    if not quiet or not st.startswith("200"):
        print("  ->", st, url[:260])
    try:
        return json.loads(read(out)), st
    except Exception as e:
        print("     (pas du JSON :", str(e)[:80], "|", read(out)[:200].replace("\n", " "), ")")
        return None, st

print("##### 1. Comptages de la couche 4G")
for where in ("1=1", "COD_REG IN (1,2,7)", "COD_REG=1", "COD_REG=2", "COD_REG=7"):
    d, _ = jget(L4G, {"where": where, "returnCountOnly": "true", "f": "json"}, quiet=True)
    print(f"    {where} : {d}")
stats = json.dumps([{"statisticType": "count", "onStatisticField": "fid", "outStatisticFieldName": "nb"}])
d, _ = jget(L4G, {"where": "COD_REG IN (1,2,7)", "groupByFieldsForStatistics": "COD_REG,n_infrastrutture_totali", "outStatistics": stats,
                  "orderByFields": "COD_REG,n_infrastrutture_totali", "f": "json"})
if d:
    print("    entités par (COD_REG, n_infrastrutture_totali) :", [tuple(f["attributes"].values()) for f in d.get("features", [])], "| erreur:", d.get("error"))

print("##### 2. Extraction paginée : Vallée d'Aoste (COD_REG=2), pages de 250, outSR=3857, geometryPrecision=1")
def pages(where, size, prefix, maxpages=20):
    files = []; total = 0; nbytes = 0; t0 = time.time()
    for k in range(maxpages):
        out = f"{T}/it/{prefix}_{k}.json"
        d, st = jget(L4G, {"where": where, "outFields": "fid,n_infrastrutture_totali,COD_REG,PRO_COM_T", "returnGeometry": "true", "outSR": 3857,
                           "geometryPrecision": 1, "orderByFields": "fid", "resultOffset": k * size, "resultRecordCount": size, "f": "json"}, out=out)
        if not d or d.get("error"):
            print("     erreur :", json.dumps((d or {}).get("error"))[:300]); break
        got = len(d.get("features", []))
        total += got; nbytes += os.path.getsize(out); files.append(out)
        print(f"     page {k} : {got} entités, exceededTransferLimit={d.get('exceededTransferLimit')}, geometryType={d.get('geometryType')}, SR={d.get('spatialReference')}, champs={[f['name'] for f in d.get('fields', [])]}")
        if got < size and not d.get("exceededTransferLimit"):
            break
        if got == 0:
            break
    print(f"    total {where} : {total} entités, {nbytes / 1e6:.1f} Mo de JSON, {len(files)} requêtes, {time.time() - t0:.0f} s")
    return files
vda = pages("COD_REG=2", 250, "vda")
gpkg = f"{T}/it/vda_4g.gpkg"
for k, f in enumerate(vda):
    cmd = ["ogr2ogr", "-f", "GPKG", gpkg, f, "-nln", "mobile_4g", "-nlt", "MULTIPOLYGON"] + (["-append", "-update"] if k else [])
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode or r.stderr.strip():
        print("    ogr2ogr :", r.returncode, r.stderr.strip()[:300])
print("    GeoPackage :", os.path.getsize(gpkg) if os.path.exists(gpkg) else "absent", "octets")

print("##### 3. Surfaces par valeur (EPSG:3035) et part du territoire, Vallée d'Aoste")
ds = ogr.Open(gpkg); lyr = ds.GetLayer(0)
src = lyr.GetSpatialRef(); laea = osr.SpatialReference(); laea.ImportFromEPSG(3035)
src.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER); laea.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
tr = osr.CoordinateTransformation(src, laea)
area = {}; cnt = {}; invalid = 0; parts = 0; pts = 0; geoms = []; comuni = set(); types = {}
for ft in lyr:
    g = ft.GetGeometryRef().Clone(); g.Transform(tr)
    v = ft.GetField("n_infrastrutture_totali")
    area[v] = area.get(v, 0.0) + g.GetArea(); cnt[v] = cnt.get(v, 0) + 1
    invalid += 0 if g.IsValid() else 1
    parts += g.GetGeometryCount(); comuni.add(ft.GetField("PRO_COM_T"))
    types[g.GetGeometryName()] = types.get(g.GetGeometryName(), 0) + 1
    pts += sum(ring.GetPointCount() for i in range(g.GetGeometryCount()) for ring in [g.GetGeometryRef(i).GetGeometryRef(j) for j in range(g.GetGeometryRef(i).GetGeometryCount())])
    geoms.append(g)
print("    entités par valeur :", dict(sorted(cnt.items())), "| communes distinctes :", len(comuni), "| types :", types)
print("    géométries invalides :", invalid, "| polygones :", parts, "| sommets :", pts)
print("    surface par valeur (km2) :", {k: round(a / 1e6, 1) for k, a in sorted(area.items())}, "| somme :", round(sum(area.values()) / 1e6, 1))
try:
    t0 = time.time(); coll = ogr.Geometry(ogr.wkbGeometryCollection)
    for g in geoms:
        coll.AddGeometry(g.MakeValid() if not g.IsValid() else g)
    u = coll.UnaryUnion()
    print("    surface de l'union (km2) :", round(u.GetArea() / 1e6, 1), f"({time.time() - t0:.0f} s) : égale à la somme si les valeurs ne se chevauchent pas")
except Exception as e:
    print("    union impossible :", str(e)[:200])
d, _ = jget(REST + "/Limiti/regioni/MapServer/0/query", {"where": "COD_REG=2", "outFields": "COD_REG,DEN_REG", "returnGeometry": "true", "outSR": 3035, "f": "json"}, out=f"{T}/it/reg2.json")
try:
    rds = ogr.Open(f"{T}/it/reg2.json"); rg = rds.GetLayer(0).GetNextFeature().GetGeometryRef()
    ra = rg.GetArea()
    print("    surface de la région d'après Limiti/regioni (km2) :", round(ra / 1e6, 1), "| part couverte en 4G par au moins 1 infrastructure :", f"{100 * sum(area.values()) / ra:.1f} %")
    for k, a in sorted(area.items()):
        print(f"      au moins... valeur {k} : {100 * a / ra:.1f} % du territoire")
except Exception as e:
    print("    région illisible :", str(e)[:200])
# points de contrôle : Aoste (ville), Courmayeur, sommet du Grand Paradis, haut val de Rhêmes
wgs = osr.SpatialReference(); wgs.ImportFromEPSG(4326); wgs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
tp = osr.CoordinateTransformation(wgs, laea)
for name, lon, lat in (("Aoste centre", 7.3206, 45.7370), ("Courmayeur", 6.9690, 45.7969), ("Grand Paradis sommet", 7.2664, 45.5172), ("haut val de Rhêmes (Thumel)", 7.1060, 45.5330), ("col du Grand-Saint-Bernard", 7.1700, 45.8690)):
    x, y, _ = tp.TransformPoint(lon, lat); p = ogr.Geometry(ogr.wkbPoint); p.AddPoint_2D(x, y)
    hit = [ft_v for ft_v, g in zip([None] * 0, [])]
    vals = []
    lyr.ResetReading()
    for ft, g in zip(lyr, geoms):
        if g.Contains(p):
            vals.append(ft.GetField("n_infrastrutture_totali"))
    print(f"    {name} ({lon}, {lat}) : n_infrastrutture_totali = {vals or 'aucun polygone (0)'}")

print("##### 4. Essai d'une page du Piémont (COD_REG=1), 250 entités")
d, st = jget(L4G, {"where": "COD_REG=1", "outFields": "fid,n_infrastrutture_totali,COD_REG,PRO_COM_T", "returnGeometry": "true", "outSR": 3857, "geometryPrecision": 1,
                   "orderByFields": "fid", "resultOffset": 0, "resultRecordCount": 250, "f": "json"}, out=f"{T}/it/pie_0.json")
if d:
    print("    entités :", len(d.get("features", [])), "| exceededTransferLimit :", d.get("exceededTransferLimit"), "| octets :", os.path.getsize(f"{T}/it/pie_0.json"), "| erreur :", d.get("error"))

print("##### 5. Légendes, éditions, carte principale, métadonnées")
d, _ = jget(REST + "/Legend", {"f": "json"}, quiet=True)
print("    dossier Legend :", [(s.get("name"), s.get("type")) for s in (d or {}).get("services", [])])
for s in (d or {}).get("services", [])[:4]:
    lg, _ = jget(f"{REST}/{s['name']}/MapServer/legend", {"f": "json"}, quiet=True)
    for l in (lg or {}).get("layers", [])[:6]:
        print(f"    {s['name']} couche {l.get('layerId')} « {l.get('layerName')} » :", [x.get("label") for x in l.get("legend", [])][:12])
print("  ->", fetch("https://geo3.agcom.it/opendata/data/edizioni.ashx", f"{T}/ed.json", data="ACTION=getedizioni"), "POST ACTION=getedizioni https://geo3.agcom.it/opendata/data/edizioni.ashx")
show(read(f"{T}/ed.json"), 1500)
print("  ->", fetch("https://maps.agcom.it/", f"{T}/maps.html"), "https://maps.agcom.it/")
mp = read(f"{T}/maps.html")
show(text_of(mp), 300)
print("    scripts :", re.findall(r'<script\b[^>]*\bsrc="([^"]+)"', mp, flags=re.I)[:15])
print("  ->", fetch("https://geo.agcom.it/reportistica/ai/ai_2026_14_10_regioni.html", f"{T}/air.html"), "https://geo.agcom.it/reportistica/ai/ai_2026_14_10_regioni.html")
air = read(f"{T}/air.html")
show(text_of(air), 700)
links = [m for m in dict.fromkeys(re.findall(r'(?:href|src)="([^"]+)"', air)) if not re.search(r"\.css|fonts|\.ico|\.png|\.svg", m)]
print("    liens :", len(links), links[:8])
first = next((l for l in links if re.search(r"json", l, re.I)), None)
if first:
    u = first if first.startswith("http") else "https://geo.agcom.it/reportistica/ai/" + first
    print("  ->", fetch(u, f"{T}/ai1.json"), u)
    body = read(f"{T}/ai1.json")
    show(body, 1800)
    print("    mentions mobile/4G/infrastrutture :", sorted(set(re.findall(r"[^\"]{0,60}(?:mobile|4G|5G|infrastruttur)[^\"]{0,60}", body, flags=re.I)))[:8])
PY

echo "##### 6. Schéma (ogrinfo -so -al) du GeoPackage assemblé pour la Vallée d'Aoste"
ogrinfo -so -al "$T/it/vda_4g.gpkg" 2>&1 | cut -c1-240 | head -45

echo "##### 7. Pagination automatique de GDAL (pilote ESRIJSON) sur la même requête, pages de 100"
URL="https://geo3.agcom.it/MapET-SFS/rest/services/Grid100/mobile_4G/MapServer/0/query?where=COD_REG%3D2&outFields=fid,n_infrastrutture_totali,COD_REG,PRO_COM_T&returnGeometry=true&outSR=3857&geometryPrecision=1&orderByFields=fid&resultRecordCount=100&f=json"
time ogrinfo -so -ro --config GDAL_HTTP_USERAGENT "$UA" -oo FEATURE_SERVER_PAGING=YES "ESRIJSON:$URL" -al 2>&1 | grep -E "Layer name|Geometry|Feature Count|Extent|ERROR|Warning|AUTHORITY|ID\[" | cut -c1-240 | head -14
echo "FIN"
