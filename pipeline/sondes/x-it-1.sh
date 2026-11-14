#!/usr/bin/env bash
# Italie, sonde 1 : scripts du portail open data AGCOM (geo3.agcom.it/opendata), fonctions getContent*,
# URL appelées, suivi automatique de ces URL, liens « Termini e condizioni » de www.agcom.it/broadband-map.
set -u
. "$(dirname "$0")/_lib.sh"
export UA T
python3 - <<'PY'
import re, os, subprocess, html
from urllib.parse import urljoin, urlparse

T = os.environ["T"]; UA = os.environ["UA"]
BASE = "https://geo3.agcom.it/opendata/"

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

def links_of(s):
    out = []
    for m in re.finditer(r'<a\b([^>]*)>(.*?)</a>', s, flags=re.S | re.I):
        attrs = m.group(1)
        href = re.search(r'href="([^"]*)"', attrs); onclick = re.search(r'onclick="([^"]*)"', attrs)
        label = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", m.group(2))).strip()
        item = (html.unescape(href.group(1)) if href else "", html.unescape(onclick.group(1)) if onclick else "", label[:90])
        if item not in out:
            out.append(item)
    return out

def bodies(src, pattern):
    out = []
    rx = r"(?:async\s+)?function\s+(" + pattern + r")\s*\(|\b(" + pattern + r")\s*[=:]\s*(?:async\s*)?(?:function\b|\([^)]*\)\s*=>)"
    for m in re.finditer(rx, src):
        name = m.group(1) or m.group(2)
        i = src.find("{", m.end())
        if i < 0:
            continue
        depth = 0; j = i
        while j < len(src):
            c = src[j]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        out.append((name, src[m.start(): j + 1]))
    return out

print("##### 1. Page du portail : scripts")
print("  ->", fetch(BASE, f"{T}/it.html"), BASE)
page = read(f"{T}/it.html")
srcs = re.findall(r'<script\b[^>]*\bsrc="([^"]+)"', page, flags=re.I)
print("  scripts externes :", len(srcs))
local = []
for s in srcs:
    u = urljoin(BASE, html.unescape(s))
    same = urlparse(u).netloc == "geo3.agcom.it"
    print("   ", "LOCAL " if same else "CDN   ", s[:160])
    if same and u not in local:
        local.append(u)
inline = [b for b in re.findall(r"<script\b(?![^>]*\bsrc=)[^>]*>(.*?)</script>", page, flags=re.S | re.I) if b.strip()]
print("  scripts en ligne :", len(inline))
for b in inline:
    show(b, 700)
for m in re.finditer(r'<input[^>]*type="hidden"[^>]*>', page, flags=re.I):
    print("  champ caché :", m.group(0)[:220])

os.makedirs(f"{T}/js", exist_ok=True)
VENDOR = re.compile(r"vendor/|jquery|bootstrap|leaflet|toastr|dropify|chart|datatables|esri|proj4|turf|\.min\.js", re.I)
sources = {}
for k, u in enumerate(local):
    out = f"{T}/js/{k:02d}.js"
    st = fetch(u, out)
    code = read(out)
    sources[u] = code
    print("  ->", st, u.split("?")[0])

print("##### 2. Fonctions du portail")
allcode = "\n".join(sources.values())
for u, code in sources.items():
    if VENDOR.search(u):
        continue
    names = sorted(set(re.findall(r"function\s+([A-Za-z_$][\w$]*)\s*\(", code)))
    print("  fichier", u.split("?")[0].replace(BASE, ""), "|", len(code), "caractères |", len(names), "fonctions")
    show(", ".join(names), 1600)
prio = re.compile(r"Download|Termin|Terms|Privacy|MappeReteMobile|Licen", re.I)
seen_names = set(); follow_src = []
found = bodies(allcode, r"getContent\w*")
print("  fonctions getContent* :", [n for n, _ in found])
for name, body in found:
    if name in seen_names:
        continue
    seen_names.add(name)
    print("  ---", name)
    show(body, 2600 if prio.search(name) else 500)
    if prio.search(name):
        follow_src.append(body)
# fonctions appelées par les fonctions prioritaires (un niveau)
called = set()
for body in list(follow_src):
    for ident in set(re.findall(r"\b([A-Za-z_$][\w$]*)\s*\(", body)):
        if ident in seen_names or ident in called or ident in ("function", "if", "for", "while", "switch", "catch", "return", "typeof", "$", "jQuery", "alert", "console", "parseInt", "setTimeout"):
            continue
        sub = bodies(allcode, re.escape(ident))
        if sub and not VENDOR.search(ident):
            called.add(ident)
            print("  --- appelée :", ident)
            show(sub[0][1], 1800)
            follow_src.append(sub[0][1])

print("##### 3. Littéraux qui ressemblent à des URL ou des fichiers (scripts non tiers)")
own = "\n".join(code for u, code in sources.items() if not VENDOR.search(u)) + "\n" + "\n".join(inline)
lits = []
for m in re.finditer(r"""(["'`])((?:(?!\1)[^\n\\]){3,300})\1""", own):
    v = m.group(2)
    if re.search(r"^https?://|\.(html?|aspx|ashx|asmx|php|json|zip|csv|gpkg|shp|geojson|7z|parquet|txt|pdf|xlsx?|tif|pbf|mbtiles|pmtiles)(\?|$)|api/|opendata|download|geoserver|wms|wfs|arcgis|tiles|\{z\}", v, re.I):
        if v not in lits:
            lits.append(v)
print("  ", len(lits), "littéraux")
for v in lits[:110]:
    print("   ", v[:230])
print("  --- lignes des scripts mentionnant un format de données")
n = 0
for line in own.splitlines():
    if re.search(r"\.zip|\.gpkg|\.csv|\.shp|\.7z|\.parquet|\.geojson|licen|CC.BY|creative", line, re.I):
        print("   ", line.strip()[:240]); n += 1
        if n >= 40:
            break

print("##### 4. Suivi des URL trouvées dans les fonctions de contenu")
cands = []
for body in follow_src:
    for m in re.finditer(r"""(["'`])((?:(?!\1)[^\n\\]){3,300})\1""", body):
        v = m.group(2).strip()
        if re.search(r"\s|^[#.<]|^(GET|POST|html|json|text)$", v) or not re.search(r"/|\.\w{2,5}(\?|$)", v):
            continue
        u = urljoin(BASE, v)
        if urlparse(u).netloc.endswith("agcom.it") and u not in cands and u != BASE:
            cands.append(u)
print("  candidats :", len(cands))
for k, u in enumerate(cands[:14]):
    out = f"{T}/f{k}.bin"
    st = fetch(u, out)
    print("  ->", st, u)
    if st.startswith("200") and re.search(r"html|json|text|javascript|xml", st):
        body = read(out)
        if "json" in st:
            show(body, 1500)
        else:
            show(text_of(body), 1500)
            for href, onclick, label in links_of(body)[:40]:
                print("      lien :", href[:170], "|", onclick[:120], "|", label)

print("##### 5. www.agcom.it/broadband-map : liens utiles")
print("  ->", fetch("https://www.agcom.it/broadband-map", f"{T}/bb.html"), "https://www.agcom.it/broadband-map")
bb = read(f"{T}/bb.html")
terms = []
for href, onclick, label in links_of(bb):
    if re.search(r"BBMap|Termini|condizioni|open ?data|licen|note legali", label + " " + href, re.I):
        u = urljoin("https://www.agcom.it/broadband-map", href)
        print("    lien :", u, "|", label)
        if re.search(r"Termini|condizioni|note legali|licen", label + " " + href, re.I) and u not in terms:
            terms.append(u)
for k, u in enumerate(terms[:3]):
    out = f"{T}/terms{k}.bin"
    st = fetch(u, out)
    print("  ->", st, u)
    if "pdf" in st.lower() or u.lower().endswith(".pdf"):
        subprocess.run("apt-get install -y -qq poppler-utils >/dev/null 2>&1", shell=True)
        subprocess.run(["pdftotext", "-layout", out, out + ".txt"])
        show(read(out + ".txt"), 7000)
    else:
        body = read(out)
        show(text_of(body), 5000)
        for href, onclick, label in links_of(body):
            if re.search(r"\.pdf|licen|creativecommons|iodl|dati\.gov|termini|condizioni", href + " " + label, re.I):
                print("      lien :", urljoin(u, href)[:200], "|", label)

print("##### 6. geo.agcom.it/reportistica : liens")
print("  ->", fetch("https://geo.agcom.it/reportistica", f"{T}/rep.html"), "https://geo.agcom.it/reportistica")
rep = read(f"{T}/rep.html")
for href, onclick, label in links_of(rep)[:20]:
    print("    lien :", href[:200], "|", onclick[:120], "|", label)
for s in re.findall(r'<script\b[^>]*\bsrc="([^"]+)"', rep, flags=re.I)[:12]:
    print("    script :", s[:200])
for m in re.finditer(r'(?:href|action|src)="([^"]+)"', rep):
    if re.search(r"metadat|ai|json|csv|zip|download", m.group(1), re.I):
        print("    attribut :", m.group(1)[:200])
print("FIN")
PY
