#!/usr/bin/env bash
# Italie, sonde 5 : extraction complète de la couche 4G de l'AGCOM pour Piémont, Vallée d'Aoste et Ligurie avec une
# pagination par identifiant croissant (le décalage resultOffset est ignoré par geo3.agcom.it), statistiques par
# région, cohérence avec les limites, second serveur, métadonnées du portail ArcGIS, adresse du portail BBMap.
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
PAGE = 250

def fetch(url, out, maxtime=300, fmt="%{http_code} %{size_download}o %{time_total}s %{content_type}"):
    r = subprocess.run(["curl", "-sS", "-L", "-m", str(maxtime), "-A", UA, "-o", out, "-w", fmt, url], capture_output=True, text=True)
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
        print("  ->", st, url[:300])
    try:
        return json.loads(read(out)), st
    except Exception as e:
        print("     (pas du JSON :", str(e)[:80], "|", read(out)[:200].replace("\n", " "), ")")
        return None, st

def guarded(fn):
    try:
        fn()
    except Exception:
        print("    ECHEC :", traceback.format_exc()[-800:])

state = {"files": []}
print("##### 1. Extraction des trois régions, pagination par fid croissant, pages de", PAGE)
def s1():
    c, _ = jget(L4G, {"where": "COD_REG IN (1,2,7)", "returnCountOnly": "true", "f": "json"}, quiet=True)
    expected = (c or {}).get("count")
    last = 0; fids = []; nbytes = 0; t0 = time.time(); k = 0
    while k < 40:
        out = f"{T}/it/p_{k:02d}.json"
        params = {"where": f"COD_REG IN (1,2,7) AND fid > {last}", "outFields": "fid,n_infrastrutture_totali,COD_REG,PRO_COM_T", "returnGeometry": "true",
                  "outSR": 3857, "geometryPrecision": 1, "orderByFields": "fid", "resultRecordCount": PAGE, "f": "json"}
        d, st = jget(L4G, params, quiet=(k > 0), out=out)
        if not d or d.get("error"):
            print("     erreur :", st, json.dumps((d or {}).get("error"))[:300]); break
        page = [f["attributes"]["fid"] for f in d.get("features", [])]
        if not page:
            os.remove(out); break
        ok = page == sorted(page) and min(page) > last
        print(f"     page {k:02d} : {st.split(' application')[0]} | {len(page)} entités, fid {min(page)} à {max(page)}, ordre croissant et sans reprise : {ok}")
        fids += page; nbytes += os.path.getsize(out); state["files"].append(out); last = max(page); k += 1
        if len(page) < PAGE:
            break
    print(f"    total : {len(fids)} entités, {len(set(fids))} fid distincts (attendu {expected}), {nbytes / 1e6:.1f} Mo de JSON, {k} requêtes, {time.time() - t0:.0f} s")
guarded(s1)

print("##### 2. Assemblage et statistiques par région (surfaces en EPSG:3035)")
def region_from(service_layer, cod):
    out = f"{T}/it/r_{service_layer.replace('/', '_')}_{cod}.json"
    jget(f"{REST}/{service_layer}/query", {"where": f"COD_REG={cod}", "outFields": "COD_REG,DEN_REG", "returnGeometry": "true", "outSR": 3035, "f": "json"}, quiet=True, out=out)
    ds = ogr.Open(out); ft = ds.GetLayer(0).GetNextFeature()
    g = ft.GetGeometryRef().Clone()
    npts = len(re.findall(r"\[\s*-?\d", read(out)))
    return (g if g.IsValid() else g.MakeValid()), ft.GetField("DEN_REG"), npts
def s2():
    gpkg = f"{T}/it/it_4g.gpkg"; t0 = time.time()
    for k, f in enumerate(state["files"]):
        cmd = ["ogr2ogr", "-f", "GPKG", gpkg, f, "-nln", "mobile_4g", "-nlt", "MULTIPOLYGON"] + (["-append", "-update"] if k else [])
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode:
            print("    ogr2ogr :", r.returncode, r.stderr.strip()[:300])
    print(f"    GeoPackage : {os.path.getsize(gpkg) / 1e6:.1f} Mo, assemblé en {time.time() - t0:.0f} s")
    laea = osr.SpatialReference(); laea.ImportFromEPSG(3035); laea.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    ds = ogr.Open(gpkg); lyr = ds.GetLayer(0)
    src = lyr.GetSpatialRef(); src.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    tr = osr.CoordinateTransformation(src, laea)
    area = {}; cnt = {}; invalid = {}; comuni = {}; colls = {2: ogr.Geometry(ogr.wkbGeometryCollection), 7: ogr.Geometry(ogr.wkbGeometryCollection)}
    npts = 0; biggest = (0, None); t0 = time.time()
    for ft in lyr:
        g = ft.GetGeometryRef().Clone(); g.Transform(tr)
        reg = int(ft.GetField("COD_REG")); v = ft.GetField("n_infrastrutture_totali")
        area[(reg, v)] = area.get((reg, v), 0.0) + g.GetArea(); cnt[(reg, v)] = cnt.get((reg, v), 0) + 1
        comuni.setdefault(reg, set()).add(ft.GetField("PRO_COM_T"))
        wkb = g.WkbSize(); npts += wkb // 16
        if wkb > biggest[0]:
            biggest = (wkb, ft.GetField("PRO_COM_T"))
        if not g.IsValid():
            invalid[reg] = invalid.get(reg, 0) + 1
            if reg in colls:
                g = g.MakeValid()
        if reg in colls:
            colls[reg].AddGeometry(g)
    print(f"    lecture et validité : {time.time() - t0:.0f} s | sommets (environ) : {npts} | plus grosse entité : {biggest[0] / 1e6:.2f} Mo de WKB, commune {biggest[1]}")
    for reg, name in ((1, "Piemonte"), (2, "Valle d'Aosta"), (7, "Liguria")):
        g1, n1, p1 = region_from("Limiti/regioni/MapServer/0", reg)
        g2, n2, p2 = region_from("Limiti/limiti_2026/MapServer/2", reg)
        ra = g2.GetArea()
        tot = sum(a for (r, v), a in area.items() if r == reg)
        print(f"    {name} : {sum(c for (r, v), c in cnt.items() if r == reg)} entités {dict(sorted((v, c) for (r, v), c in cnt.items() if r == reg))}, {len(comuni.get(reg, []))} communes, {invalid.get(reg, 0)} géométries invalides")
        print(f"       surface région : Limiti/regioni {g1.GetArea() / 1e6:.1f} km2 ({p1} sommets) ; Limiti/limiti_2026 couche 2 {ra / 1e6:.1f} km2 ({p2} sommets)")
        print(f"       surface par valeur (km2) : { {v: round(a / 1e6, 1) for (r, v), a in sorted(area.items()) if r == reg} } | total couvert {tot / 1e6:.1f} km2 = {100 * tot / ra:.1f} % | sans polygone {100 * (1 - tot / ra):.1f} %")
        print(f"       part du territoire par valeur : { {v: f'{100 * a / ra:.1f} %' for (r, v), a in sorted(area.items()) if r == reg} }")
        if reg in colls:
            t0 = time.time(); u = colls[reg].UnaryUnion()
            print(f"       union {u.GetArea() / 1e6:.1f} km2 ({time.time() - t0:.0f} s) | hors région : {u.Difference(g1).GetArea() / 1e6:.2f} km2 (Limiti/regioni), {u.Difference(g2).GetArea() / 1e6:.2f} km2 (limiti_2026 couche 2)")
guarded(s2)

print("##### 3. Second serveur (geo.agcom.it/server), couche 3 « 4G » du service grid20/AppMobile2602")
def s3():
    q = f"{REST2}/grid20/AppMobile2602/MapServer/3/query"
    c, _ = jget(q, {"where": "1=1", "returnCountOnly": "true", "f": "json"}, quiet=True)
    c2, _ = jget(q, {"where": "pro_com_t LIKE '007%'", "returnCountOnly": "true", "f": "json"}, quiet=True)
    print("    nombre total :", c, "| communes 007xxx (Vallée d'Aoste) :", c2)
    ids, _ = jget(q, {"where": "1=1", "returnIdsOnly": "true", "f": "json"}, quiet=True)
    print("    returnIdsOnly :", (ids or {}).get("objectIdFieldName"), len((ids or {}).get("objectIds") or []), "identifiants")
    seen = []
    for off in (0, 100, 200):
        d, _ = jget(q, {"where": "pro_com_t LIKE '007%'", "outFields": "objectid", "returnGeometry": "false", "orderByFields": "objectid", "resultOffset": off, "resultRecordCount": 100, "f": "json"}, quiet=True)
        page = [f["attributes"]["objectid"] for f in (d or {}).get("features", [])]
        seen += page
        print(f"    resultOffset={off} : {len(page)} entités, exceededTransferLimit={(d or {}).get('exceededTransferLimit')}, erreur={(d or {}).get('error')}")
    print("    identifiants distincts :", len(set(seen)), "(attendu : le nombre ci-dessus)")
    l, _ = jget(f"{REST2}/grid20/AppMobile2602/MapServer/3", {"f": "json"}, quiet=True)
    if l:
        print("    couche 3 : maxRecordCount", l.get("maxRecordCount"), "| pagination", (l.get("advancedQueryCapabilities") or {}).get("supportsPagination"), "| formats", l.get("supportedQueryFormats"), "| description", repr(l.get("description"))[:200], "| copyright", repr(l.get("copyrightText"))[:200])
guarded(s3)

print("##### 4. Portail ArcGIS de l'AGCOM : fiches des jeux mobiles")
def s4():
    for q in ("mobile", "AppMobile"):
        d, _ = jget("https://geo.agcom.it/arcgis/sharing/rest/search", {"q": q, "num": 12, "f": "json"})
        if not d:
            continue
        print(f"    recherche « {q} » : total {d.get('total')} | erreur {d.get('error')}")
        for it in (d.get("results") or [])[:12]:
            print(f"     - {it.get('title')} | {it.get('type')} | modifié {time.strftime('%Y-%m-%d', time.gmtime((it.get('modified') or 0) / 1000))} | accès {it.get('access')} | licence: {re.sub(r'<[^>]+>', ' ', str(it.get('licenseInfo')))[:160]} | crédits: {str(it.get('accessInformation'))[:80]}")
            desc = re.sub(r"\s+", " ", text_of(str(it.get("description") or ""))).strip()
            if desc and desc != "None":
                print("       description:", desc[:420])
            if it.get("snippet"):
                print("       résumé:", str(it.get("snippet"))[:300])
            if it.get("url"):
                print("       url:", str(it.get("url"))[:200])
guarded(s4)

print("##### 5. Adresse du portail BBMap citée par les conditions")
def s5():
    for u in ("https://www.agcom.it/broadbandmap", "https://geo.agcom.it/", "https://maps.agcom.it/"):
        st = fetch(u, f"{T}/p.html", fmt="%{http_code} %{size_download}o %{content_type} final=%{url_effective}")
        print("  ->", st, u)
        page = read(f"{T}/p.html")
        t = re.search(r"<title[^>]*>(.*?)</title>", page, flags=re.S | re.I)
        print("    titre :", (t.group(1).strip()[:120] if t else None), "| texte :", re.sub(r"\s+", " ", text_of(page)).strip()[:260])
guarded(s5)
PY

echo "##### 6. Schéma (ogrinfo -so -al) du GeoPackage des trois régions"
ogrinfo -so -al "$T/it/it_4g.gpkg" 2>/dev/null | grep -v -E "^\s+(MEMBER|ELLIPSOID|LENGTHUNIT|ANGLEUNIT|ID\[|PARAMETER|AXIS|ORDER|ENSEMBLE|PRIMEM|METHOD|CONVERSION|BASEGEOGCRS|CS\[|USAGE|SCOPE|AREA|BBOX)" | cut -c1-200 | head -20
ogrinfo -ro "$T/it/it_4g.gpkg" -sql "SELECT COD_REG, n_infrastrutture_totali, COUNT(*) AS nb FROM mobile_4g GROUP BY COD_REG, n_infrastrutture_totali" 2>/dev/null | grep -E "^\s+(COD_REG|n_infrastrutture_totali|nb) " | paste - - - | cut -c1-200
echo "FIN"
