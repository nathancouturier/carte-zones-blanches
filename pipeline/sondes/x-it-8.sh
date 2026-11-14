#!/usr/bin/env bash
# Italie, sonde 8 (dernière) : existe-t-il sur les serveurs de l'AGCOM une couche mobile par opérateur ou en 2G/3G ?
# Liste complète des services des dossiers BBmap et grid20, couches des deux services mobiles plus anciens
# (Hosted/AppMobileEoY2022_v2, Hosted/DESI_2020_mobile). Recoupement du décalage de grille par reprojection locale.
set -u
. "$(dirname "$0")/_lib.sh"
export UA T
mkdir -p "$T/it"
python3 - <<'PY'
import re, os, subprocess, json, traceback
from urllib.parse import urlencode
from osgeo import ogr, osr, gdal
ogr.UseExceptions()
gdal.PushErrorHandler("CPLQuietErrorHandler")

T = os.environ["T"]; UA = os.environ["UA"]
REST = "https://geo3.agcom.it/MapET-SFS/rest/services"
REST2 = "https://geo.agcom.it/server/rest/services"

def fetch(url, out, maxtime=240):
    r = subprocess.run(["curl", "-sS", "-L", "-m", str(maxtime), "-A", UA, "-o", out, "-w", "%{http_code} %{size_download}o %{time_total}s %{content_type}", url], capture_output=True, text=True)
    return (r.stdout or r.stderr).strip()

def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""

n = [0]
def jget(url, params=None, quiet=True, out=None):
    if params:
        url = url + "?" + urlencode(params)
    n[0] += 1
    out = out or f"{T}/j{n[0]}.json"
    st = fetch(url, out)
    if not quiet or not st.startswith("200"):
        print("  ->", st, url[:240])
    try:
        return json.loads(read(out))
    except Exception as e:
        print("     (pas du JSON :", str(e)[:80], "|", read(out)[:160].replace("\n", " "), ")")
        return None

def guarded(fn):
    try:
        fn()
    except Exception:
        print("    ECHEC :", traceback.format_exc()[-700:])

print("##### 1. Tous les services des dossiers BBmap, grid20 et Hosted (geo.agcom.it/server)")
def s1():
    for folder in ("BBmap", "grid20", "Hosted"):
        d = jget(f"{REST2}/{folder}", {"f": "json"})
        names = [s.get("name", "").split("/", 1)[-1] + ":" + s.get("type", "").replace("Server", "") for s in (d or {}).get("services", [])]
        print(f"    {folder} ({len(names)}) :", ", ".join(names)[:1500])
guarded(s1)

def describe(service, kind):
    url = f"{REST2}/{service}/{kind}"
    print("  ====", service, kind)
    d = jget(url, {"f": "json"}, quiet=False)
    if not d or d.get("error"):
        print("    erreur :", (d or {}).get("error")); return
    for k in ("serviceDescription", "description", "copyrightText", "capabilities", "maxRecordCount"):
        if d.get(k) not in (None, ""):
            print(f"    {k}: {str(d.get(k))[:300]}")
    print("    couches :", [(l.get("id"), l.get("name")) for l in d.get("layers", [])][:40], "| tables :", [(t.get("id"), t.get("name")) for t in d.get("tables", [])][:10])
    ls = jget(url + "/layers", {"f": "json"})
    for l in (ls or {}).get("layers", [])[:12]:
        fields = [f.get("name") + ":" + f.get("type", "").replace("esriFieldType", "") for f in (l.get("fields") or [])]
        r = (l.get("drawingInfo") or {}).get("renderer") or {}
        rend = r.get("type", "") + " " + str(r.get("field1") or r.get("field") or "") + " " + "; ".join(str(u.get("value")) + "=" + str(u.get("label")) for u in r.get("uniqueValueInfos", [])[:10]) + "; ".join(str(c.get("classMaxValue")) + ":" + str(c.get("label")) for c in r.get("classBreakInfos", [])[:10])
        print(f"    -- couche {l.get('id')} « {l.get('name')} » geom={l.get('geometryType')} | champs : {str(fields)[:700]}")
        print(f"       rendu : {rend[:400]} | description : {str(l.get('description'))[:200]}")
        lurl = f"{url}/{l.get('id')}/query"
        c = jget(lurl, {"where": "1=1", "returnCountOnly": "true", "f": "json"})
        s = jget(lurl, {"where": "1=1", "outFields": "*", "resultRecordCount": 2, "returnGeometry": "false", "f": "json"})
        print(f"       nombre : {c} | échantillon : {json.dumps([f.get('attributes') for f in (s or {}).get('features', [])][:2], ensure_ascii=False)[:600]}")

print("##### 2. Services mobiles plus anciens")
guarded(lambda: describe("Hosted/AppMobileEoY2022_v2", "FeatureServer"))
guarded(lambda: describe("Hosted/DESI_2020_mobile", "FeatureServer"))

print("##### 3. Décalage de grille : Vallée d'Aoste demandée en EPSG:3857 puis reprojetée localement en EPSG:3035")
def s3():
    q = {"where": "COD_REG=2 AND n_infrastrutture_totali=1", "outFields": "fid,n_infrastrutture_totali,PRO_COM_T", "returnGeometry": "true", "outSR": 3857, "orderByFields": "fid", "resultRecordCount": 250, "f": "json"}
    st = fetch(f"{REST}/Grid100/mobile_4G/MapServer/0/query?" + urlencode(q), f"{T}/it/v3857.json"); print("  ->", st, "COD_REG=2 AND n_infrastrutture_totali=1, outSR=3857")
    q["outSR"] = 4326
    st = fetch(f"{REST}/Grid100/mobile_4G/MapServer/0/query?" + urlencode(q), f"{T}/it/v4326.json"); print("  ->", st, "idem, outSR=4326")
    laea = osr.SpatialReference(); laea.ImportFromEPSG(3035); laea.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    for name in ("v3857", "v4326"):
        ds = ogr.Open(f"{T}/it/{name}.json"); lyr = ds.GetLayer(0)
        src = lyr.GetSpatialRef(); src.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
        tr = osr.CoordinateTransformation(src, laea)
        hist = {}; total = 0; nf = 0
        for ft in lyr:
            g = ft.GetGeometryRef().Clone(); g.Transform(tr); nf += 1
            for m in re.finditer(r"(\d+\.\d+) (\d+\.\d+)", g.ExportToWkt()[:300000]):
                key = (round(float(m.group(1)) % 100, 1), round(float(m.group(2)) % 100, 1)); hist[key] = hist.get(key, 0) + 1; total += 1
        top = sorted(hist.items(), key=lambda kv: -kv[1])[:3]
        print(f"    {name} ({src.GetAuthorityCode(None)}) : {nf} entités, {total} sommets ; restes modulo 100 m les plus fréquents après reprojection locale en EPSG:3035 : {top}")
guarded(s3)
print("FIN")
PY
