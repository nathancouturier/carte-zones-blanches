#!/usr/bin/env bash
# Italie, sonde 2 : corps des fonctions de téléchargement du portail open data AGCOM, textes « Download Rete
# Mobile » et « Termini e condizioni » (translations.js), script de la carte mobile, métadonnées des services
# ArcGIS REST Grid100/mobile_* (couches, champs, légende, comptage, échantillon), date de publication.
set -u
. "$(dirname "$0")/_lib.sh"
export UA T
python3 - <<'PY'
import re, os, subprocess, html, json
from urllib.parse import urlencode

T = os.environ["T"]; UA = os.environ["UA"]
BASE = "https://geo3.agcom.it/opendata/"
REST = "https://geo3.agcom.it/MapET-SFS/rest/services"

def fetch(url, out, maxtime=120):
    r = subprocess.run(["curl", "-sS", "-L", "-m", str(maxtime), "-A", UA, "-o", out, "-w",
                        "%{http_code} %{size_download}o %{content_type}", url], capture_output=True, text=True)
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
    s = re.sub(r"<!--.*?-->", " ", s, flags=re.S)
    return html.unescape(re.sub(r"<[^>]+>", " ", s))

def js_html_text(s):
    s = re.sub(r"'\s*\+\s*'", "", s)
    s = s.replace("\\'", "'")
    return text_of(s)

def body_of(src, name):
    m = re.search(r"function\s+" + re.escape(name) + r"\s*\(", src)
    if not m:
        return ""
    i = src.find("{", m.end()); depth = 0; j = i
    while j < len(src):
        c = src[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    return src[m.start(): j + 1]

n = [0]
def jget(url, params=None, quiet=False):
    if params:
        url = url + "?" + urlencode(params)
    n[0] += 1
    out = f"{T}/j{n[0]}.json"
    st = fetch(url, out)
    if not quiet or not st.startswith("200"):
        print("  ->", st, url[:230])
    try:
        return json.loads(read(out))
    except Exception as e:
        print("     (pas du JSON :", str(e)[:80], "|", read(out)[:200].replace("\n", " "), ")")
        return None

print("##### 1. app.js : objet AgcomApp et fonctions de téléchargement mobile")
print("  ->", fetch(BASE + "js/app.js", f"{T}/app.js"), BASE + "js/app.js")
app = read(f"{T}/app.js")
print("  --- début de app.js")
show(app, 2200)
for name in ("initRegioni", "selRegioneMobileChange", "selProvinciaMobileChange", "generateDownloadMobileRequest", "generateDownloadFixedRequest"):
    print("  ---", name)
    show(body_of(app, name), 3200 if name == "generateDownloadMobileRequest" else 1500)
print("  --- lignes avec ashx / ajax / fetch")
for line in app.splitlines():
    if re.search(r"\.ashx|\$\.ajax|\$\.get|\$\.post|fetch\(|XMLHttpRequest|getJSON", line):
        print("     ", line.strip()[:230])

print("##### 2. translations.js : textes du portail")
print("  ->", fetch(BASE + "js/translations.js", f"{T}/tr.js"), BASE + "js/translations.js")
tr = read(f"{T}/tr.js")
keys = re.findall(r"^\s*([A-Za-z_]\w*)\s*:", tr, flags=re.M)
print("  clés :", ", ".join(dict.fromkeys(keys))[:900])
for key, maxc in (("contentDownloadMobile", 3500), ("contentTerms", 6500), ("contentHome", 1200)):
    pos = [m.start() for m in re.finditer(r"\b" + key + r"\s*:", tr)]
    print("  ---", key, ": occurrences aux positions", pos)
    if pos:
        end = min([m.start() for m in re.finditer(r"^\s*[A-Za-z_]\w*\s*:", tr, flags=re.M) if m.start() > pos[0] + len(key) + 2] or [len(tr)])
        raw = tr[pos[0]: end]
        if key == "contentDownloadMobile":
            print("    (HTML brut, début)"); show(raw, 1800)
        print("    (texte)"); show(js_html_text(raw), maxc)

print("##### 3. map-mobile.js (carte « Visualizzazione > Rete mobile »)")
print("  ->", fetch(BASE + "js/map-mobile.js", f"{T}/mm.js"), BASE + "js/map-mobile.js")
mm = read(f"{T}/mm.js")
mm2 = re.sub(r"/\*.*?\*/", " ", mm, flags=re.S)
mm2 = "\n".join(l for l in mm2.splitlines() if not l.strip().startswith("//"))
show(mm2, 9000)

print("##### 4. Catalogue ArcGIS REST")
root = jget(REST, {"f": "json"})
if root:
    print("    version:", root.get("currentVersion"), "| dossiers:", root.get("folders"), "| services:", [(s.get("name"), s.get("type")) for s in root.get("services", [])][:30])
    for folder in [f for f in (root.get("folders") or []) if re.search(r"Grid100|Mobile|Limiti", f, re.I)][:8]:
        d = jget(REST + "/" + folder, {"f": "json"}, quiet=True)
        if d:
            print("    dossier", folder, ":", [(s.get("name"), s.get("type")) for s in d.get("services", [])][:40])

def renderer_summary(r):
    if not r:
        return "aucun"
    t = r.get("type")
    if t == "uniqueValue":
        return f"uniqueValue champ={r.get('field1')} " + "; ".join(f"{u.get('value')}={u.get('label')} couleur={(u.get('symbol') or {}).get('color')}" for u in r.get("uniqueValueInfos", [])[:14])
    if t == "classBreaks":
        return f"classBreaks champ={r.get('field')} min={r.get('minValue')} " + "; ".join(f"<={c.get('classMaxValue')}:{c.get('label')} couleur={(c.get('symbol') or {}).get('color')}" for c in r.get("classBreakInfos", [])[:14])
    return f"{t} label={r.get('label')} couleur={(r.get('symbol') or {}).get('color')}"

def explore(service, deep):
    url = f"{REST}/{service}/MapServer"
    print("  ====", service)
    d = jget(url, {"f": "json"})
    if not d:
        return
    for k in ("serviceDescription", "description", "copyrightText", "capabilities", "maxRecordCount", "supportedQueryFormats", "singleFusedMapCache", "units", "exportTilesAllowed", "supportsDynamicLayers", "maxImageWidth", "maxImageHeight"):
        if d.get(k) not in (None, ""):
            print(f"    {k}: {str(d.get(k))[:300]}")
    print("    spatialReference:", d.get("spatialReference"), "| fullExtent:", json.dumps(d.get("fullExtent"))[:260])
    print("    documentInfo:", json.dumps(d.get("documentInfo"), ensure_ascii=False)[:300])
    print("    couches:", [(l.get("id"), l.get("name"), l.get("minScale"), l.get("maxScale"), l.get("subLayerIds")) for l in d.get("layers", [])][:40])
    print("    tables:", d.get("tables"))
    ls = jget(url + "/layers", {"f": "json"}, quiet=True)
    layers = (ls or {}).get("layers", [])
    for l in layers[: (8 if deep else 4)]:
        fields = [(f.get("name"), f.get("type", "").replace("esriFieldType", ""), f.get("alias")) for f in (l.get("fields") or [])]
        print(f"    -- couche {l.get('id')} « {l.get('name')} » type={l.get('type')} geom={l.get('geometryType')} minScale={l.get('minScale')} maxScale={l.get('maxScale')} maxRecordCount={l.get('maxRecordCount')} capabilities={l.get('capabilities')}")
        print("       description:", str(l.get("description"))[:300], "| copyright:", str(l.get("copyrightText"))[:200])
        print("       extent:", json.dumps(l.get("extent"))[:260], "| sourceSR:", l.get("sourceSpatialReference"))
        print("       champs:", fields)
        print("       rendu:", renderer_summary((l.get("drawingInfo") or {}).get("renderer"))[:1200])
        print("       definitionExpression:", l.get("definitionExpression"), "| advancedQuery:", json.dumps(l.get("advancedQueryCapabilities"))[:300])
        if not deep or l.get("type") != "Feature Layer":
            continue
        lurl = f"{url}/{l.get('id')}/query"
        c = jget(lurl, {"where": "1=1", "returnCountOnly": "true", "f": "json"}, quiet=True)
        print("       nombre d'entités:", c)
        s = jget(lurl, {"where": "1=1", "outFields": "*", "resultRecordCount": 2, "returnGeometry": "true", "outSR": 3035, "f": "json"}, quiet=True)
        if s:
            print("       échantillon: exceededTransferLimit=", s.get("exceededTransferLimit"), "| erreur=", s.get("error"))
            for ft in (s.get("features") or [])[:2]:
                print("         attributs:", json.dumps(ft.get("attributes"), ensure_ascii=False)[:500])
                print("         géométrie (EPSG:3035):", json.dumps(ft.get("geometry"))[:400])
        for fname, ftype, _ in fields:
            if ftype in ("OID", "Geometry", "GlobalID") or re.search(r"shape|objectid|^id$|^fid$", fname, re.I):
                continue
            dv = jget(lurl, {"where": "1=1", "outFields": fname, "returnDistinctValues": "true", "returnGeometry": "false", "resultRecordCount": 40, "f": "json"}, quiet=True)
            if dv:
                vals = [ft.get("attributes", {}).get(fname) for ft in (dv.get("features") or [])]
                print(f"       valeurs distinctes de {fname} ({len(vals)}{'+' if dv.get('exceededTransferLimit') else ''}):", str(vals[:40])[:500], "| erreur=", dv.get("error"))
    lg = jget(url + "/legend", {"f": "json"}, quiet=True)
    for l in (lg or {}).get("layers", [])[:8]:
        print(f"    légende couche {l.get('layerId')} « {l.get('layerName')} »:", [x.get("label") for x in l.get("legend", [])][:20])
    # identify au centre de Turin (7.6869 E, 45.0703 N)
    idf = jget(url + "/identify", {"geometry": "7.6869,45.0703", "geometryType": "esriGeometryPoint", "sr": 4326, "layers": "all", "tolerance": 1,
                                   "mapExtent": "7.60,45.02,7.78,45.12", "imageDisplay": "900,500,96", "returnGeometry": "false", "f": "json"}, quiet=True)
    for r in (idf or {}).get("results", [])[:6]:
        print("    identify Turin: couche", r.get("layerId"), r.get("layerName"), "|", json.dumps(r.get("attributes"), ensure_ascii=False)[:500])
    if idf is not None and not idf.get("results"):
        print("    identify Turin:", json.dumps(idf)[:300])

print("##### 5. Services de couverture mobile")
explore("Grid100/mobile_4G", True)
explore("Grid100/mobile_5G", False)
explore("Grid100/mobile_5G_DSS", False)

print("##### 6. Date de publication et régions")
d = jget(REST + "/Grid100/data_pubblicazione/FeatureServer/0/query", {"where": "1=1", "outFields": "*", "returnGeometry": "false", "f": "json"})
if d:
    print("    champs:", [(f.get("name"), f.get("type")) for f in d.get("fields", [])])
    for ft in (d.get("features") or [])[:12]:
        print("    ", json.dumps(ft.get("attributes"), ensure_ascii=False)[:400])
d = jget(REST + "/Limiti/regioni/MapServer/0/query", {"where": "1=1", "outFields": "*", "returnGeometry": "false", "f": "json"})
if d:
    print("    champs:", [(f.get("name"), f.get("type")) for f in d.get("fields", [])])
    for ft in (d.get("features") or []):
        a = ft.get("attributes") or {}
        if re.search(r"piemonte|aosta|liguria", json.dumps(a), re.I):
            print("    ", json.dumps(a, ensure_ascii=False)[:400])
    print("    nombre de régions:", len(d.get("features") or []))

print("##### 7. Éditions et métadonnées « AI-Ready »")
print("  ->", fetch(BASE + "data/edizioni.ashx", f"{T}/ed.txt"), BASE + "data/edizioni.ashx")
show(read(f"{T}/ed.txt"), 900)
print("  ->", fetch("https://geo.agcom.it/reportistica/ai/index.html", f"{T}/ai.html"), "https://geo.agcom.it/reportistica/ai/index.html")
ai = read(f"{T}/ai.html")
show(text_of(ai), 1800)
for m in list(dict.fromkeys(re.findall(r'(?:href|src)="([^"]+)"', ai)))[:30]:
    if not re.search(r"\.css|fonts|\.ico|\.png|\.svg", m):
        print("    lien :", m[:200])
print("FIN")
PY
