#!/usr/bin/env bash
# Andorre, sonde 6 : inventaire précis du catalogue de l'IDE Andorra (835 fiches) et de l'espace « geodades » du WMS.
# But : établir s'il existe une fiche ou une couche de couverture mobile, de télécommunications ou d'antennes.
# Lecture de métadonnées seulement, aucune donnée de carte.
set -u
. "$(dirname "$0")/_lib.sh"
# User-Agent générique : aucun nom de projet ni de personne dans les requêtes sortantes.
UA="sonde-sources-ouvertes/1.0 (verification ponctuelle de sources publiques)"
export UA T
python3 - <<'PY'
import re, os, subprocess, html, json, traceback, urllib.parse
import xml.etree.ElementTree as ET

T = os.environ["T"]; UA = os.environ["UA"]
KW = r"telecom|telef|antena|antenes|antrepetidor|cobertura|radio|m[oò]bil|emissi|comunicaci|electromagn|\b[45]g\b|xarxa|repetidor|fibra"

def fetch(url, out, maxtime=60, extra=()):
    try:
        os.remove(out)   # jamais de relecture d'une réponse précédente
    except OSError:
        pass
    r = subprocess.run(["curl", "-sS", "-L", "--connect-timeout", "15", "-m", str(maxtime), "-A", UA, *extra, "-o", out, "-w",
                        "%{http_code} %{size_download}o %{content_type} | final=%{url_effective}", url],
                       capture_output=True, text=True)
    err = (r.stderr or "").strip().replace("\n", " ")[:140]
    return ((r.stdout or "").strip()[:260] + (" | ERREUR " + err if err else ""))

def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""

def text_of(s):
    s = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
    s = re.sub(r"<!--.*?-->", " ", s, flags=re.S)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s))).strip()

def show(s, maxc=1500, width=240, indent="    "):
    s = re.sub(r"\s+", " ", str(s)).strip()
    cut = s[:maxc]
    for k in range(0, len(cut), width):
        print(indent + cut[k:k + width])
    if len(s) > maxc:
        print(indent + f"[... tronqué, {len(s)} caractères au total]")

def title_of(s):
    m = re.search(r"<title[^>]*>(.*?)</title>", s, flags=re.S | re.I)
    return re.sub(r"\s+", " ", html.unescape(m.group(1))).strip()[:160] if m else "(pas de titre)"

def links(s, base):
    out, seen = [], set()
    for m in re.finditer(r'<a\b[^>]*?href\s*=\s*["\']([^"\'#]+)["\'][^>]*>(.*?)</a>', s, flags=re.S | re.I):
        href = urllib.parse.urljoin(base, html.unescape(m.group(1)).strip())
        if href in seen or href.startswith(("javascript:", "mailto:", "tel:")):
            continue
        seen.add(href)
        out.append((href, text_of(m.group(2))[:90]))
    return out

def guarded(fn):
    try:
        fn()
    except Exception:
        print("    ECHEC :", traceback.format_exc()[-700:])

def contexts(t, rx, n=2, before=250, after=450, flags=re.I):
    k, last = 0, -10**9
    for m in re.finditer(rx, t, flags=flags):
        if m.start() - last < after:
            continue
        show("« " + t[max(0, m.start() - before):m.start() + after] + " »", before + after + 10)
        last = m.start(); k += 1
        if k >= n:
            break
    return k

def main_text(s):
    m = re.search(r"<(main|article)\b.*?</\1>", s, flags=re.S | re.I)
    return text_of(m.group(0)) if m else text_of(s)

def loc(t):
    return t.rsplit("}", 1)[-1]

# ---------------------------------------------------------------------------------------------------------------
print("##### A. ANDORRE : inventaire précis du catalogue (CSW) et de l'espace de travail « geodades » (WMS)")
def parse_records(s):
    root = ET.fromstring(s.encode("utf-8", "replace"))
    sr = next((e for e in root.iter() if loc(e.tag) == "SearchResults"), None)
    if sr is None:
        return None, 0, 0
    recs = []
    for rec in sr:
        d = {"id": None, "title": None, "type": None, "subject": [], "abstract": None}
        for c in rec:
            k = loc(c.tag); v = (c.text or "").strip()
            if k == "identifier" and not d["id"]: d["id"] = v
            elif k == "title" and not d["title"]: d["title"] = v
            elif k == "type" and not d["type"]: d["type"] = v
            elif k == "subject" and v: d["subject"].append(v)
            elif k == "abstract" and not d["abstract"]: d["abstract"] = v
        recs.append(d)
    return recs, int(sr.attrib.get("numberOfRecordsMatched", "0")), int(sr.attrib.get("nextRecord", "0"))

def collapse(t):
    t = re.sub(r'\s*-?\s*Full\s+"[^"]*"', "", t or "?")
    return re.sub(r"\d+", "#", t).strip()

def section_a():
    CSW = "https://www.ideandorra.ad/Cataleg/srv/cat/csw"
    body_tpl = ('<?xml version="1.0" encoding="UTF-8"?>'
                '<csw:GetRecords xmlns:csw="http://www.opengis.net/cat/csw/2.0.2" service="CSW" version="2.0.2" '
                'resultType="results" startPosition="%d" maxRecords="200" outputSchema="http://www.opengis.net/cat/csw/2.0.2">'
                '<csw:Query typeNames="csw:Record"><csw:ElementSetName>summary</csw:ElementSetName></csw:Query></csw:GetRecords>')
    records, start, matched = [], 1, None
    for page in range(6):
        req = f"{T}/req.xml"
        open(req, "w", encoding="utf-8").write(body_tpl % start)
        out = f"{T}/csw_post.xml"
        st = fetch(CSW, out, 120, ("-H", "Content-Type: application/xml", "--data-binary", "@" + req))
        recs, matched, nxt = parse_records(read(out))
        if recs is None:
            print("  ->", st[:90], "| pas de SearchResults"); break
        records += recs
        if not recs or nxt == 0 or nxt > matched:
            break
        start = nxt
    print("     fiches lues :", len(records), "sur", matched)
    def blob(d):
        return " ".join([d["title"] or "", " ".join(d["subject"]), d["abstract"] or ""])
    tests = (("télécoms au sens strict", r"telecom|t[eè]l[eé]com|telef|t[eé]l[eé]ph|antena|antenes|antenne|antrepetidor|radioel|radiocomunic|radiodif|emissor|[eé]metteur|electromagn|[eé]lectromagn|repetidor|r[eé]p[eé]teur|fibra [oò]ptica|fibre optique|\b[2345]g\b|wi-?fi|m[oò]bil|mobile"),
             ("« cobertura », « couverture » ou « coverage »", r"cobertura|couverture|coverage"),
             ("« radio »", r"radio"),
             ("« xarxa », « réseau » ou « network »", r"xarxa|r[eé]seau|network"))
    for label, rx in tests:
        hits = [d for d in records if re.search(rx, blob(d), re.I)]
        print(f"   --- {label} : {len(hits)} fiche(s)")
        seen = {}
        for d in hits:
            m = re.search(rx, blob(d), re.I)
            b = blob(d)
            key = (collapse(d["title"]), m.group(0).lower())
            if key not in seen:
                seen[key] = [0, b[max(0, m.start() - 90):m.start() + 130]]
            seen[key][0] += 1
        for (t, w), (n, ctx) in list(seen.items())[:14]:
            print(f"       {n} x « {t[:80]} » | mot « {w} » | contexte : … {re.sub(chr(10), ' ', ctx)[:220]} …")
    uc = {}
    for d in records:
        if any(x == "utilitiesCommunication" for x in d["subject"]):
            uc[collapse(d["title"])] = uc.get(collapse(d["title"]), 0) + 1
    print("   --- fiches de la catégorie ISO « utilitiesCommunication » :", sum(uc.values()))
    show(" ¦ ".join(f"{k} ({v})" for k, v in sorted(uc.items(), key=lambda kv: -kv[1])), 2600, 230, "       ")
    print("   --- services décrits dans le catalogue :", sum(1 for d in records if d["type"] == "service"))
    show(" ¦ ".join(sorted({d["title"] or "?" for d in records if d["type"] == "service"})), 2600, 230, "       ")
    col = {}
    for d in records:
        if d["type"] != "service":
            col[collapse(d["title"])] = col.get(collapse(d["title"]), 0) + 1
    print(f"   --- titres des jeux de données, numéros remplacés par # : {len(col)} titres distincts pour {sum(col.values())} fiches")
    show(" ¦ ".join(f"{k} ({v})" if v > 1 else k for k, v in sorted(col.items())), 11000, 230, "       ")

    print("--- espace de travail « geodades » et couches sans préfixe du WMS global")
    out = f"{T}/wms.xml"
    st = fetch("https://www.ideandorra.ad/Serveis/ows?service=WMS&version=1.3.0&request=GetCapabilities", out, 180)
    print("  ->", st[:100])
    root = ET.fromstring(read(out).encode("utf-8", "replace"))
    layers = []
    for e in root.iter():
        if loc(e.tag) == "Layer":
            n = next(((c.text or "").strip() for c in e if loc(c.tag) == "Name"), None)
            t = next(((c.text or "").strip() for c in e if loc(c.tag) == "Title"), None)
            if n:
                layers.append((n, t))
    g = [(n, t) for n, t in layers if n.startswith("geodades:") or ":" not in n or n.startswith(("wms_feda:", "wms_cesi:", "wfs_demo:", "wms_cartogeneral:"))]
    show(" ; ".join(f"{n}={t}" if t and t != n.split(':')[-1] else n for n, t in g), 5200, 230, "       ")
guarded(section_a)
PY
echo "FIN"
