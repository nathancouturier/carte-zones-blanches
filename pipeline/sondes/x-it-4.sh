#!/usr/bin/env bash
# Italie, sonde 4 : second serveur ArcGIS de l'AGCOM (geo.agcom.it/server, piste « AppMobile »), pagination de la
# couche 4G (identifiants, décalage), extraction complète de la Ligurie, surfaces, cohérence avec les limites,
# logo exigé par la licence, circulaire AGCOM du 3 juillet 2026.
set -u
. "$(dirname "$0")/_lib.sh"
export UA T
mkdir -p "$T/it"
python3 - <<'PY'
import re, os, subprocess, html, json, time, traceback
from urllib.parse import urlencode
from osgeo import ogr, osr, gdal
ogr.UseExceptions()
gdal.PushErrorHandler("CPLQuietErrorHandler")

T = os.environ["T"]; UA = os.environ["UA"]
REST = "https://geo3.agcom.it/MapET-SFS/rest/services"
REST2 = "https://geo.agcom.it/server/rest/services"
L4G = REST + "/Grid100/mobile_4G/MapServer/0/query"

def fetch(url, out, maxtime=300, data=None, head=False):
    cmd = ["curl", "-sS", "-L", "-m", str(maxtime), "-A", UA, "-o", out, "-w", "%{http_code} %{size_download}o %{time_total}s %{content_type}"]
    if data is not None:
        cmd += ["--data", data]
    if head:
        cmd += ["-I"]
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

n = [0]
def jget(url, params=None, quiet=False, out=None):
    if params:
        url = url + "?" + urlencode(params)
    n[0] += 1
    out = out or f"{T}/j{n[0]}.json"
    st = fetch(url, out)
    if not quiet or not st.startswith("200"):
        print("  ->", st, url[:240])
    try:
        return json.loads(read(out)), st
    except Exception as e:
        print("     (pas du JSON :", str(e)[:80], "|", read(out)[:200].replace("\n", " "), ")")
        return None, st

def guarded(fn):
    try:
        fn()
    except Exception:
        print("    ECHEC :", traceback.format_exc()[-700:])

def renderer_summary(r):
    if not r:
        return "aucun"
    t = r.get("type")
    if t == "uniqueValue":
        return f"uniqueValue champ={r.get('field1')} " + "; ".join(f"{u.get('value')}={u.get('label')}" for u in r.get("uniqueValueInfos", [])[:12])
    if t == "classBreaks":
        return f"classBreaks champ={r.get('field')} " + "; ".join(f"<={c.get('classMaxValue')}:{c.get('label')}" for c in r.get("classBreakInfos", [])[:12])
    return f"{t} label={r.get('label')}"

print("##### 1. Second serveur ArcGIS : geo.agcom.it/server")
def s1():
    root, _ = jget(REST2, {"f": "json"})
    if not root:
        return
    print("    version:", root.get("currentVersion"), "| dossiers:", root.get("folders"), "| services:", [(s.get("name"), s.get("type")) for s in root.get("services", [])][:30])
    if root.get("error"):
        print("    erreur:", root.get("error")); return
    for folder in (root.get("folders") or [])[:12]:
        d, _ = jget(REST2 + "/" + folder, {"f": "json"}, quiet=True)
        names = [s.get("name") + ":" + s.get("type", "") for s in (d or {}).get("services", [])]
        mob = [x for x in names if re.search(r"mobil|4g|5g|lte|cell|radio|app", x, re.I)]
        print(f"    dossier {folder} : {len(names)} services | liés au mobile : {mob[:30]}")
        if len(names) <= 14:
            print("       tous :", names)
    svc = "grid20/AppMobile2602"
    d, _ = jget(f"{REST2}/{svc}/MapServer", {"f": "json"})
    if not d or d.get("error"):
        print("    erreur:", (d or {}).get("error")); return
    for k in ("serviceDescription", "description", "copyrightText", "capabilities", "maxRecordCount", "singleFusedMapCache"):
        if d.get(k) not in (None, ""):
            print(f"    {k}: {str(d.get(k))[:400]}")
    print("    spatialReference:", d.get("spatialReference"), "| documentInfo:", json.dumps(d.get("documentInfo"), ensure_ascii=False)[:300])
    print("    couches:", [(l.get("id"), l.get("name"), l.get("parentLayerId")) for l in d.get("layers", [])][:60])
    ls, _ = jget(f"{REST2}/{svc}/MapServer/layers", {"f": "json"}, quiet=True)
    layers = (ls or {}).get("layers", [])
    for l in layers[:30]:
        fields = [f.get("name") + ":" + f.get("type", "").replace("esriFieldType", "") for f in (l.get("fields") or [])]
        print(f"    -- couche {l.get('id')} « {l.get('name')} » type={l.get('type')} geom={l.get('geometryType')} minScale={l.get('minScale')} def={l.get('definitionExpression')}")
        print("       champs:", str(fields)[:600])
        print("       rendu:", renderer_summary((l.get("drawingInfo") or {}).get("renderer"))[:500], "| description:", str(l.get("description"))[:200])
    deep = [l for l in layers if l.get("type") == "Feature Layer"][:3]
    for l in deep:
        lurl = f"{REST2}/{svc}/MapServer/{l.get('id')}/query"
        c, _ = jget(lurl, {"where": "1=1", "returnCountOnly": "true", "f": "json"}, quiet=True)
        s, _ = jget(lurl, {"where": "1=1", "outFields": "*", "resultRecordCount": 2, "returnGeometry": "false", "f": "json"}, quiet=True)
        print(f"    couche {l.get('id')} : nombre = {c} | échantillon = {json.dumps([f.get('attributes') for f in (s or {}).get('features', [])][:2], ensure_ascii=False)[:700]} | erreur = {(s or {}).get('error')}")
guarded(s1)

print("##### 2. Pagination de la couche 4G (geo3.agcom.it, Grid100/mobile_4G)")
def s2():
    d, _ = jget(L4G, {"where": "COD_REG IN (1,2,7)", "returnIdsOnly": "true", "f": "json"}, quiet=True)
    ids = (d or {}).get("objectIds") or []
    print("    returnIdsOnly : champ", (d or {}).get("objectIdFieldName"), "|", len(ids), "identifiants | min", min(ids) if ids else None, "| max", max(ids) if ids else None)
    seen = []
    for off in (0, 100, 200):
        d, _ = jget(L4G, {"where": "COD_REG=2", "outFields": "fid", "returnGeometry": "false", "orderByFields": "fid", "resultOffset": off, "resultRecordCount": 100, "f": "json"}, quiet=True)
        fids = [f["attributes"]["fid"] for f in (d or {}).get("features", [])]
        seen += fids
        print(f"    resultOffset={off} : {len(fids)} entités, fid de {min(fids) if fids else None} à {max(fids) if fids else None}, exceededTransferLimit={(d or {}).get('exceededTransferLimit')}, erreur={(d or {}).get('error')}")
    print("    identifiants distincts sur les 3 pages :", len(set(seen)), "(attendu 215)")
    if ids:
        d, _ = jget(L4G, {"objectIds": ",".join(str(i) for i in ids[:3]), "outFields": "fid,n_infrastrutture_totali,COD_REG,PRO_COM_T", "returnGeometry": "false", "f": "json"}, quiet=True)
        print("    requête par objectIds :", [f.get("attributes") for f in (d or {}).get("features", [])], "| erreur :", (d or {}).get("error"))
guarded(s2)

print("##### 3. Extraction complète de la Ligurie (COD_REG=7), pages de 250")
state = {}
def s3():
    files = []; total = 0; nbytes = 0; t0 = time.time()
    for k in range(8):
        out = f"{T}/it/lig_{k}.json"
        d, st = jget(L4G, {"where": "COD_REG=7", "outFields": "fid,n_infrastrutture_totali,COD_REG,PRO_COM_T", "returnGeometry": "true", "outSR": 3857, "geometryPrecision": 1,
                           "orderByFields": "fid", "resultOffset": k * 250, "resultRecordCount": 250, "f": "json"}, quiet=True, out=out)
        if not d or d.get("error"):
            print("     erreur :", st, json.dumps((d or {}).get("error"))[:300]); break
        got = len(d.get("features", []))
        if got == 0:
            break
        total += got; nbytes += os.path.getsize(out); files.append(out)
        print(f"     page {k} : {st.split(' application')[0]} | {got} entités, exceededTransferLimit={d.get('exceededTransferLimit')}")
        if got < 250:
            break
    print(f"    total : {total} entités, {nbytes / 1e6:.1f} Mo de JSON, {len(files)} requêtes, {time.time() - t0:.0f} s")
    gpkg = f"{T}/it/lig_4g.gpkg"
    t0 = time.time()
    for k, f in enumerate(files):
        cmd = ["ogr2ogr", "-f", "GPKG", gpkg, f, "-nln", "mobile_4g", "-nlt", "MULTIPOLYGON"] + (["-append", "-update"] if k else [])
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode:
            print("    ogr2ogr :", r.returncode, r.stderr.strip()[:300])
    print("    GeoPackage :", os.path.getsize(gpkg), "octets, conversion en", f"{time.time() - t0:.0f} s")
    state["gpkg"] = gpkg
guarded(s3)

print("##### 4. Surfaces par valeur et cohérence avec les limites (EPSG:3035)")
def region_geom(cod):
    out = f"{T}/it/reg{cod}.json"
    jget(REST + "/Limiti/regioni/MapServer/0/query", {"where": f"COD_REG={cod}", "outFields": "COD_REG,DEN_REG", "returnGeometry": "true", "outSR": 3035, "f": "json"}, quiet=True, out=out)
    ds = ogr.Open(out); ft = ds.GetLayer(0).GetNextFeature()
    g = ft.GetGeometryRef().Clone()
    npts = sum(g.GetGeometryRef(i).GetPointCount() if g.GetGeometryRef(i).GetGeometryCount() == 0 else sum(g.GetGeometryRef(i).GetGeometryRef(j).GetPointCount() for j in range(g.GetGeometryRef(i).GetGeometryCount())) for i in range(g.GetGeometryCount()))
    return (g if g.IsValid() else g.MakeValid()), ft.GetField("DEN_REG"), npts
def s4():
    laea = osr.SpatialReference(); laea.ImportFromEPSG(3035); laea.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    for cod in (2, 7, 1):
        g, name, npts = region_geom(cod)
        print(f"    région {cod} « {name} » : {g.GetArea() / 1e6:.1f} km2 d'après Limiti/regioni ({npts} sommets)")
        state[f"reg{cod}"] = g
    print(f"    Vallée d'Aoste : 3025.5 km2 couverts par au moins 1 infrastructure (sonde 3), soit {100 * 3025.5e6 / state['reg2'].GetArea():.1f} % de la région")
    ds = ogr.Open(state["gpkg"]); lyr = ds.GetLayer(0)
    src = lyr.GetSpatialRef(); src.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    tr = osr.CoordinateTransformation(src, laea)
    area = {}; cnt = {}; invalid = 0; pts = 0; comuni = set(); coll = ogr.Geometry(ogr.wkbGeometryCollection)
    for ft in lyr:
        g = ft.GetGeometryRef().Clone(); g.Transform(tr)
        v = ft.GetField("n_infrastrutture_totali")
        area[v] = area.get(v, 0.0) + g.GetArea(); cnt[v] = cnt.get(v, 0) + 1; comuni.add(ft.GetField("PRO_COM_T"))
        if not g.IsValid():
            invalid += 1; g = g.MakeValid()
        coll.AddGeometry(g)
    ra = state["reg7"].GetArea()
    print("    Ligurie : entités par valeur", dict(sorted(cnt.items())), "| communes distinctes :", len(comuni), "| géométries invalides :", invalid)
    print("    Ligurie : surface par valeur (km2)", {k: round(a / 1e6, 1) for k, a in sorted(area.items())}, "| somme :", round(sum(area.values()) / 1e6, 1), f"| soit {100 * sum(area.values()) / ra:.1f} % de la région")
    print("    Ligurie : part du territoire par valeur", {k: f"{100 * a / ra:.1f} %" for k, a in sorted(area.items())}, f"| sans polygone : {100 * (1 - sum(area.values()) / ra):.1f} %")
    t0 = time.time(); u = coll.UnaryUnion()
    print(f"    Ligurie : surface de l'union {u.GetArea() / 1e6:.1f} km2 ({time.time() - t0:.0f} s) | hors de la région Limiti/regioni : {u.Difference(state['reg7']).GetArea() / 1e6:.2f} km2")
guarded(s4)
def s4b():
    ls, _ = jget(REST + "/Limiti/limiti_2026/MapServer/layers", {"f": "json"}, quiet=True)
    for l in (ls or {}).get("layers", [])[:6]:
        print(f"    Limiti/limiti_2026 couche {l.get('id')} « {l.get('name')} » geom={l.get('geometryType')} champs={[f.get('name') for f in (l.get('fields') or [])]}")
    c, _ = jget(REST + "/Limiti/limiti_2026/MapServer/0/query", {"where": "COD_REG IN (1,2,7)", "returnCountOnly": "true", "f": "json"}, quiet=True)
    print("    communes des trois régions dans Limiti/limiti_2026/0 :", c)
guarded(s4b)

print("##### 5. Logo exigé par la licence")
def s5():
    print("  ->", fetch("https://www.agcom.it/termini-e-condizioni", f"{T}/terms.html"), "https://www.agcom.it/termini-e-condizioni")
    page = read(f"{T}/terms.html")
    i = page.find("seguente logo")
    seg = page[i: i + 1500] if i >= 0 else ""
    imgs = re.findall(r"<img\b[^>]*>", seg, flags=re.I)
    print("    balises img après « seguente logo » :", [x[:260] for x in imgs[:3]])
    for u in ["https://geo.agcom.it/homeData.16/images/bbmap/BBmapCC.jpg"] + [re.sub(r"^/", "https://www.agcom.it/", m) for m in re.findall(r'src="([^"]+)"', " ".join(imgs))][:2]:
        print("  ->", fetch(u, f"{T}/logo.bin"), u)
        r = subprocess.run(["gdalinfo", f"{T}/logo.bin"], capture_output=True, text=True)
        print("    ", " | ".join(l.strip() for l in r.stdout.splitlines() if re.search(r"^Driver|^Size is", l)))
guarded(s5)

print("##### 6. Circulaire AGCOM du 3 juillet 2026 (piste : définitions de la cartographie mobile)")
def s6():
    u = "https://www.agcom.it/sites/default/files/provvedimenti/comunicazione/2026/circolare%203%20luglio%20PNRR%20e%20mappatura.pdf"
    st = fetch(u, f"{T}/circ.pdf")
    print("  ->", st, u)
    if not st.startswith("200"):
        return
    subprocess.run("apt-get install -y -qq poppler-utils >/dev/null 2>&1", shell=True)
    subprocess.run(["pdftotext", "-layout", f"{T}/circ.pdf", f"{T}/circ.txt"])
    txt = read(f"{T}/circ.txt")
    print("    caractères :", len(txt))
    show(txt, 900)
    k = 0
    for line in txt.splitlines():
        if re.search(r"mobil|broadband ?map|bbmap|100 ?m|pixel|infrastruttur|open ?data", line, re.I):
            print("     |", re.sub(r"\s+", " ", line).strip()[:230]); k += 1
            if k >= 28:
                break
guarded(s6)
PY

echo "##### 7. Schéma (ogrinfo -so) : page ESRI JSON brute puis GeoPackage de la Ligurie"
ogrinfo -so -al "$T/it/lig_0.json" 2>/dev/null | grep -v -E "^\s+(MEMBER|ELLIPSOID|LENGTHUNIT|ANGLEUNIT|ID\[|PARAMETER|AXIS|ORDER|ENSEMBLE|PRIMEM|METHOD|CONVERSION|BASEGEOGCRS|CS\[)" | cut -c1-200 | head -24
ogrinfo -so -al "$T/it/lig_4g.gpkg" 2>/dev/null | grep -v -E "^\s+(MEMBER|ELLIPSOID|LENGTHUNIT|ANGLEUNIT|ID\[|PARAMETER|AXIS|ORDER|ENSEMBLE|PRIMEM|METHOD|CONVERSION|BASEGEOGCRS|CS\[)" | cut -c1-200 | head -24
echo "FIN"
