#!/usr/bin/env bash
# Contre-vérification « Andorre et Monaco », sonde 3 : Monaco. Le portail data.gouv.mc existe-t-il (mentions
# officielles, nouvel essai, Common Crawl) ? Le géoportail du Gouvernement a-t-il une couche de couverture mobile ?
# Catalogues et métadonnées seulement : aucune entité demandée.
set -u
. "$(dirname "$0")/_lib.sh"
UA="sonde-sources-ouvertes/1.0"   # User-Agent générique (pas de nom de projet ni de compte envoyé à des tiers)
export UA
cd "$T" || exit 1
g() { # g <fichier> <url> : un seul essai, délais courts ; affiche code, taille, type, adresse finale
  local f="$1" u="$2" r
  r=$(curl -sS -L --connect-timeout 12 -m 90 -A "$UA" -o "$f" -w "%{http_code} %{size_download}o %{content_type} final=%{url_effective}" "$u" 2>&1)
  echo "  -> $r | $u" | cut -c1-260
}
cat > mentions.py <<'PY'
# Cherche dans une page les mentions d'un portail de données ouvertes et les liens vers data.gouv.mc.
import re, html, sys
try:
    s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except Exception as e:
    print("     illisible :", e); raise SystemExit
t = re.search(r"<title[^>]*>(.*?)</title>", s, re.S | re.I)
print("     titre :", html.unescape(t.group(1)).strip()[:110] if t else None, "| taille", len(s))
links = []
for h, x in re.findall(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', s, re.S | re.I):
    x = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", x))).strip()
    if re.search(r"data\.gouv\.mc|open[ -]?data|donn[ée]es[ -]ouvertes|opendata", h + " " + x, re.I):
        links.append((h[:140], x[:70]))
print("     liens vers un portail de données :", sorted(set(links))[:8])
b = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
b = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
for w in (r"data\.gouv\.mc", r"open ?data", r"donn[ée]es ouvertes", r"Data Monaco", r"jeux de donn[ée]es"):
    ms = [m.start() for m in re.finditer(w, b, re.I)]
    raw = len(re.findall(w, s, re.I))
    if ms or raw:
        print("     motif « %s » : %d dans le texte, %d dans le code" % (w, len(ms), raw), ("| «" + b[max(0, ms[0] - 160): ms[0] + 200] + "»") if ms else "")
PY

echo "### A. Mentions officielles d'un portail de données ouvertes monégasque"
g gouv.html "https://www.gouv.mc/"; python3 mentions.py gouv.html
for u in "https://www.gouv.mc/en/sitemap" "https://www.monacostatistics.mc/" "https://extendedmonaco.com/" "https://monservicepublic.gouv.mc/"; do
  rm -f page.bin; g page.bin "$u"; [ -s page.bin ] && python3 mentions.py page.bin
done
echo "  -- plans de site (sitemap.xml)"
python3 - <<'PY'
import re, os, urllib.request
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
W = re.compile(r"open-?data|donnees-ouvertes|data-monaco|/data(?:[/-]|$)|reutilisation|jeux-de-donnees", re.I)
def fetch(u):
    with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=60) as r:
        return r.read().decode("utf-8", "replace")
for start in ("https://www.gouv.mc/sitemap.xml", "https://www.monacostatistics.mc/sitemap.xml", "https://extendedmonaco.com/sitemap.xml"):
    todo, urls, n = [start], [], 0
    while todo and n < 7:
        u = todo.pop(0); n += 1
        try:
            x = fetch(u)
        except Exception as e:
            print("    ", u[:90], ": échec", str(e)[:90]); continue
        locs = re.findall(r"<loc>\s*([^<\s]+)\s*</loc>", x)
        if "<sitemapindex" in x:
            todo += locs[:6]
        else:
            urls += locs
    hits = sorted({u for u in urls if W.search(u)})
    print("    ", start, ":", len(urls), "adresses, évocatrices :", len(hits))
    for u in hits[:12]:
        print("        ", u[:170])
PY
echo "  -- formulaires de recherche de gouv.mc"
python3 - <<'PY'
import re, html, os, urllib.request, urllib.parse
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
s = open("gouv.html", encoding="utf-8", errors="replace").read()
forms = re.findall(r"<form\b([^>]*)>(.*?)</form>", s, re.S | re.I)
print("     formulaires :", len(forms))
cand = None
for attrs, inner in forms[:6]:
    act = re.search(r'action="([^"]*)"', attrs)
    names = re.findall(r'<input\b[^>]*name="([^"]+)"', inner)
    print("       action=%r champs=%r" % (act.group(1)[:90] if act else None, names[:6]))
    if act and names and re.search(r"rech|search|cerca", act.group(1) + " " + attrs, re.I) and cand is None:
        cand = (urllib.parse.urljoin("https://www.gouv.mc/", html.unescape(act.group(1))), names[0])
if cand:
    for q in ("open data", "data.gouv.mc"):
        u = cand[0] + ("&" if "?" in cand[0] else "?") + urllib.parse.urlencode({cand[1]: q})
        try:
            with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=60) as r:
                p = r.read().decode("utf-8", "replace")
        except Exception as e:
            print("     recherche", u[:110], ": échec", str(e)[:90]); continue
        res = []
        for h, x in re.findall(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', p, re.S | re.I):
            x = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", x))).strip()
            if re.search(r"data|donn[ée]es", x, re.I) and len(x) > 12:
                res.append((x[:90], h[:110]))
        print("     recherche « %s » (%s) : %d lien(s) évocateur(s)" % (q, u[:100], len(set(res))))
        for x, h in sorted(set(res))[:8]:
            print("        ", x, "|", h)
else:
    print("     pas de formulaire de recherche exploitable dans la page d'accueil")
PY

echo "### B. data.gouv.mc : nouvel essai"
g mc1.html "https://data.gouv.mc/"; python3 mentions.py mc1.html
g mc2.html "http://data.gouv.mc/"; python3 mentions.py mc2.html

echo "### C. data.gouv.mc dans Common Crawl : nouvel essai (2 tentatives par index, 3 index)"
python3 - <<'PY'
import json, os, urllib.request, urllib.parse, urllib.error, gzip, re, html, io, time
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
def fetch(url, timeout=100, headers=None):
    h = {"User-Agent": UA}; h.update(headers or {})
    with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=timeout) as r:
        return r.read()
try:
    colls = json.loads(fetch("https://index.commoncrawl.org/collinfo.json", 40))
except Exception as e:
    print("  liste des index illisible :", e); colls = []
rows, answered = [], 0
for c in colls[:3]:
    q = c["cdx-api"] + "?" + urllib.parse.urlencode({"url": "data.gouv.mc/*", "output": "json", "limit": "60"})
    for attempt in (1, 2):
        try:
            raw = fetch(q)
            rs = [json.loads(l) for l in raw.decode("utf-8", "replace").splitlines() if l.strip().startswith("{")]
            print("  ", c["id"], ": réponse 200,", len(rs), "capture(s)"); answered += 1; rows += rs; break
        except urllib.error.HTTPError as e:
            body = e.read()[:140]
            print("  ", c["id"], "essai", attempt, ": HTTP", e.code, re.sub(rb"\s+", b" ", body))
            if e.code == 404:
                answered += 1; break
            time.sleep(8)
        except Exception as e:
            print("  ", c["id"], "essai", attempt, ": échec", str(e)[:100]); time.sleep(8)
    if rows:
        break
print("  index ayant répondu :", answered, "| captures trouvées :", len(rows))
for r in rows[:14]:
    print("     ", r.get("timestamp"), r.get("status"), r.get("mime"), r.get("url", "")[:110])
ok = [r for r in rows if r.get("status") == "200" and "html" in (r.get("mime") or "")]
def read(r):
    off, ln = int(r["offset"]), int(r["length"])
    raw = fetch("https://data.commoncrawl.org/" + r["filename"], 100, {"Range": "bytes=%d-%d" % (off, off + ln - 1)})
    rec = gzip.GzipFile(fileobj=io.BytesIO(raw)).read().decode("utf-8", "replace")
    return rec.split("\r\n\r\n", 2)[-1]
picks = sorted(ok, key=lambda r: len(r.get("url", "")))[:1] + [r for r in ok if re.search(r"licen|condition|mention|legal|apropos|about", r.get("url", ""), re.I)][:2]
for r in picks:
    try:
        s = read(r)
    except Exception as e:
        print("  lecture impossible :", r.get("url"), str(e)[:120]); continue
    t = re.search(r"<title[^>]*>(.*?)</title>", s, re.S | re.I)
    b = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
    b = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
    print("  CAPTURE", r["url"], r["timestamp"], "| titre :", html.unescape(t.group(1)).strip()[:160] if t else None)
    print("     texte :", b[:1100])
    for w in (r"licen[cs]e", r"r[ée]utilis", r"t[ée]l[ée]com|antenne|radio[ée]lectrique|couverture"):
        ms = [m.start() for m in re.finditer(w, b, re.I)]
        if ms:
            print("     motif « %s » : %d | «%s»" % (w, len(ms), b[max(0, ms[0] - 150): ms[0] + 220]))
PY

echo "### D. Géoportail du Gouvernement (ArcGIS) : y a-t-il une couche de couverture mobile ?"
python3 - <<'PY'
import json, os, re, urllib.request, urllib.parse, time
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
def jget(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=60) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except Exception as e:
        return {"_erreur": str(e)[:160]}
def day(v):
    return time.strftime("%Y-%m-%d", time.gmtime(v / 1000)) if isinstance(v, (int, float)) and v > 0 else v
P = "https://montecarto.gouv.mc/arcgis/sharing/rest"
def search(base, q, num=15, show=True):
    d = jget(base + "/search?" + urllib.parse.urlencode({"q": q, "f": "json", "num": num, "sortField": "modified", "sortOrder": "desc"}))
    res = d.get("results") or []
    print("  recherche %r : total=%s%s" % (q, d.get("total"), "" if "results" in d else " | " + str(d)[:200]))
    if show:
        for r in res:
            print("       %s | %s | accès=%s | licence=%r | modifié=%s" % ((r.get("title") or "")[:60], r.get("type"), r.get("access"), re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", r.get("licenseInfo") or ""))[:70], day(r.get("modified"))))
    return res, d.get("total")
for q in ("couverture", "mobile", "antenne OR antennes", "radio OR radioélectrique OR radioelectrique", "telecom OR télécom OR télécommunications", "5G OR 4G", "réseau OR reseau"):
    search(P, q, 6)
allr = []
for typ in ("Feature Service", "Map Service", "Web Map", "Web Mapping Application"):
    res, tot = search(P, 'type:"%s"' % typ, 100, show=False)
    allr += res
    titles = sorted({(r.get("title") or "")[:46] for r in res})
    for k in range(0, len(titles), 8):
        print("       ", " ; ".join(titles[k:k + 8]))
lic = [r for r in allr if (r.get("licenseInfo") or "").strip()]
print("  éléments publics listés :", len(allr), "| avec un champ licenseInfo rempli :", len(lic))
for r in lic[:6]:
    print("       ", (r.get("title") or "")[:50], "|", re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", r.get("licenseInfo") or ""))[:200])
for path in ("", "/Hosted"):
    d = jget("https://montecarto-srv.gouv.mc/arcgis/rest/services%s?f=json" % path)
    svcs = [s.get("name", "") + " (" + s.get("type", "") + ")" for s in d.get("services") or []]
    print("  répertoire des services%s : dossiers=%s services=%d%s" % (path or "/", d.get("folders"), len(svcs), "" if "services" in d else " | " + str(d)[:200]))
    hits = [s for s in svcs if re.search(r"radio|couv|mobil|telecom|antenn|[2345]g\b|reseau|ondes|cem", s, re.I)]
    print("       évocateurs :", hits[:20])
    for k in range(0, min(len(svcs), 90), 6):
        print("       ", " ; ".join(x[:44] for x in svcs[k:k + 6]))
o = jget("https://gvt-mc.maps.arcgis.com/sharing/rest/portals/self?f=json")
print("  organisation ArcGIS Online gvt-mc : id=%r name=%r urlKey=%r accès=%r%s" % (o.get("id"), o.get("name"), o.get("urlKey"), o.get("access"), "" if "id" in o else " | " + str(o)[:200]))
if o.get("id"):
    res, tot = search("https://www.arcgis.com/sharing/rest", "orgid:%s" % o["id"], 60, show=False)
    titles = sorted({(r.get("title") or "")[:46] + " [" + (r.get("type") or "")[:18] + "]" for r in res})
    for k in range(0, len(titles), 4):
        print("       ", " ; ".join(titles[k:k + 4]))
    hits = [r for r in res if re.search(r"radio|couv|mobil|t[ée]l[ée]com|antenn|[2345]g\b|ondes", (r.get("title") or "") + " " + (r.get("snippet") or ""), re.I)]
    print("       éléments évoquant télécoms ou couverture :", [(r.get("title"), r.get("type"), (r.get("licenseInfo") or "")[:60]) for r in hits][:10])
PY
echo "### fin"
