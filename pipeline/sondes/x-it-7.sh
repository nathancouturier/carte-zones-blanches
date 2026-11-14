#!/usr/bin/env bash
# Italie, sonde 7 : règle de déclaration d'une cellule couverte dans la spécification d'entrée de la Broadband Map,
# recherche d'une version plus récente de la spécification, et emprise réelle des données 4G : les polygones de
# couverture sont-ils découpés exactement sur les communes du service Limiti/limiti_2026 (Vallée d'Aoste) ?
set -u
. "$(dirname "$0")/_lib.sh"
export UA T
apt-get install -y -qq poppler-utils >/dev/null 2>&1
mkdir -p "$T/it"
python3 - <<'PY'
import re, os, subprocess, html, json, time, traceback
from urllib.parse import urlencode
from osgeo import ogr, osr, gdal
ogr.UseExceptions()
gdal.PushErrorHandler("CPLQuietErrorHandler")

T = os.environ["T"]; UA = os.environ["UA"]
REST = "https://geo3.agcom.it/MapET-SFS/rest/services"

def fetch(url, out, maxtime=240):
    r = subprocess.run(["curl", "-sS", "-L", "-m", str(maxtime), "-A", UA, "-o", out, "-w", "%{http_code} %{size_download}o %{time_total}s %{content_type}", url], capture_output=True, text=True)
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

def guarded(fn):
    try:
        fn()
    except Exception:
        print("    ECHEC :", traceback.format_exc()[-800:])

print("##### 1. Spécification 2.1 : résolution spatiale et règle de déclaration d'une cellule")
def s1():
    u = "https://maps.agcom.it/risorse/specifiche/spec_2_1.pdf"
    st = fetch(u, f"{T}/spec.pdf"); print("  ->", st, u)
    subprocess.run(["pdftotext", "-layout", f"{T}/spec.pdf", f"{T}/spec.txt"])
    lines = read(f"{T}/spec.txt").splitlines()
    for a, b, label in ((36, 60, "introduction et références"), (84, 112, "définitions (suite) et résolution spatiale"), (184, 192, "codes de type de réseau"), (380, 398, "règle pour une cellule de la grille")):
        print(f"    --- lignes {a} à {b} : {label}")
        show(" ".join(lines[a:b]), 2600)
    notes = [re.sub(r"\s+", " ", l).strip() for l in lines if re.match(r"^\s*[234]\s+(Per uso futuro|[A-Z])", l)]
    print("    notes de bas de page :", notes[:8])
guarded(s1)

print("##### 2. Versions plus récentes de la spécification ?")
def s2():
    for u in ("https://maps.agcom.it/risorse/specifiche/", "https://maps.agcom.it/risorse/"):
        st = fetch(u, f"{T}/dir.html"); print("  ->", st, u)
        page = read(f"{T}/dir.html")
        show(text_of(page), 260)
        print("    liens :", [h for h in re.findall(r'href="([^"]+)"', page) if re.search(r"\.pdf|spec", h, re.I)][:20])
guarded(s2)

print("##### 3. Emprise des données 4G : communes de la Vallée d'Aoste (Limiti/limiti_2026/MapServer/0)")
def load(path):
    ds = ogr.Open(path); lyr = ds.GetLayer(0); out = []
    for ft in lyr:
        g = ft.GetGeometryRef().Clone()
        out.append((ft, g if g.IsValid() else g.MakeValid()))
    return ds, out
def union(geoms):
    coll = ogr.Geometry(ogr.wkbGeometryCollection)
    for g in geoms:
        coll.AddGeometry(g)
    return coll.UnaryUnion()
def s3():
    q = {"where": "COD_REG=2", "outFields": "PRO_COM_T,COMUNE", "returnGeometry": "true", "outSR": 3035, "f": "json"}
    st = fetch(f"{REST}/Limiti/limiti_2026/MapServer/0/query?" + urlencode(q), f"{T}/it/comuni.json"); print("  ->", st, "communes, COD_REG=2")
    q = {"where": "COD_REG=2", "outFields": "fid,n_infrastrutture_totali,COD_REG,PRO_COM_T", "returnGeometry": "true", "outSR": 3035, "orderByFields": "fid", "resultRecordCount": 250, "f": "json"}
    st = fetch(f"{REST}/Grid100/mobile_4G/MapServer/0/query?" + urlencode(q), f"{T}/it/cov.json"); print("  ->", st, "couverture 4G, COD_REG=2, outSR=3035")
    q = {"where": "COD_REG=2", "outFields": "COD_REG", "returnGeometry": "true", "outSR": 3035, "f": "json"}
    st = fetch(f"{REST}/Limiti/regioni/MapServer/0/query?" + urlencode(q), f"{T}/it/reg.json"); print("  ->", st, "région, COD_REG=2")
    d1, comuni = load(f"{T}/it/comuni.json"); d2, cov = load(f"{T}/it/cov.json"); d3, reg = load(f"{T}/it/reg.json")
    npts = len(re.findall(r"\[\s*-?\d", read(f"{T}/it/comuni.json")))
    print(f"    communes : {len(comuni)} entités, {npts} sommets | couverture : {len(cov)} entités")
    by_com = {ft.GetField("PRO_COM_T"): g for ft, g in comuni}
    ucom = union([g for _, g in comuni]); ucov = union([g for _, g in cov]); r = reg[0][1]
    print(f"    surface : union des communes {ucom.GetArea() / 1e6:.2f} km2 | région (Limiti/regioni) {r.GetArea() / 1e6:.2f} km2 | couverture {ucov.GetArea() / 1e6:.2f} km2")
    print(f"    couverture hors de l'union des communes : {ucov.Difference(ucom).GetArea() / 1e6:.4f} km2 | hors de la région généralisée : {ucov.Difference(r).GetArea() / 1e6:.2f} km2")
    print(f"    communes hors de la région généralisée : {ucom.Difference(r).GetArea() / 1e6:.2f} km2 | région généralisée hors des communes : {r.Difference(ucom).GetArea() / 1e6:.2f} km2")
    worst = 0.0; missing = 0
    for ft, g in cov:
        c = by_com.get(ft.GetField("PRO_COM_T"))
        if c is None:
            missing += 1; continue
        worst = max(worst, g.Difference(c).GetArea())
    print(f"    entité de couverture dépassant le plus de sa propre commune : {worst:.1f} m2 | entités sans commune correspondante : {missing}")
    print(f"    non couvert (aucune infrastructure) dans l'union des communes : {ucom.Difference(ucov).GetArea() / 1e6:.1f} km2, soit {100 * ucom.Difference(ucov).GetArea() / ucom.GetArea():.1f} %")
    # la grille : coordonnées des sommets modulo 100 m dans EPSG:3035
    xs = {}; 
    for ft, g in cov[:40]:
        for m in re.finditer(r"(\d+\.\d+) (\d+\.\d+)", g.ExportToWkt()[:200000]):
            key = (round(float(m.group(1)) % 100, 1), round(float(m.group(2)) % 100, 1))
            xs[key] = xs.get(key, 0) + 1
    top = sorted(xs.items(), key=lambda kv: -kv[1])[:4]
    print("    restes modulo 100 m des sommets (x, y) les plus fréquents :", top, "| sommets examinés :", sum(xs.values()))
guarded(s3)
print("FIN")
PY
