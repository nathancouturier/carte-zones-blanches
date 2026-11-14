#!/usr/bin/env bash
# Contre-vérification « Andorre et Monaco », sonde 5 : que sert http://opendata.ad/ ? Résultats du moteur de
# recherche de gouv.mc ; dernier essai sur data.gouv.mc et sur Common Crawl. Pages et catalogues seulement.
set -u
. "$(dirname "$0")/_lib.sh"
UA="sonde-sources-ouvertes/1.0"   # User-Agent générique (pas de nom de projet ni de compte envoyé à des tiers)
export UA
cd "$T" || exit 1
g() { # g <fichier> <url> : un seul essai, délais courts ; affiche code, taille, type, adresse finale
  local f="$1" u="$2" r
  r=$(curl -sS -L --connect-timeout 12 -m 90 -A "$UA" -o "$f" -D "$f.hdr" -w "%{http_code} %{size_download}o %{content_type} final=%{url_effective}" "$u" 2>&1)
  echo "  -> $r | $u" | cut -c1-260
}

echo "### A. Andorre : que sert opendata.ad ?"
python3 - <<'PY'
import socket
for h in ("opendata.ad", "www.opendata.ad", "www.govern.ad", "www.andorratelecom.ad"):
    try:
        print("  DNS", h, "->", sorted({i[4][0] for i in socket.getaddrinfo(h, 80)})[:4])
    except Exception as e:
        print("  DNS", h, "ECHEC", e)
PY
g od.html "http://opendata.ad/"
grep -i -E '^(HTTP/|server:|location:|x-powered-by:|content-type:|last-modified:)' od.html.hdr | tr -d '\r' | cut -c1-150 | head -8
python3 - <<'PY'
import re, html
try:
    s = open("od.html", encoding="utf-8", errors="replace").read()
except Exception as e:
    print("  illisible :", e); raise SystemExit
t = re.search(r"<title[^>]*>(.*?)</title>", s, re.S | re.I)
print("  titre :", html.unescape(t.group(1)).strip()[:160] if t else None, "| taille", len(s))
for m in re.finditer(r'<meta[^>]+(?:name|property)="(generator|description|og:site_name|author)"[^>]*content="([^"]*)"', s, re.I):
    print("  meta", m.group(1), ":", html.unescape(m.group(2))[:200])
b = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
b = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
print("  texte (début) :", b[:900])
links = []
for h, x in re.findall(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', s, re.S | re.I):
    x = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", x))).strip()
    links.append((h[:110], x[:50]))
u = sorted(set(links))
print("  liens :", len(u))
for h, x in u[:40]:
    print("     ", h, "|", x)
print("  scripts et cadres :", (re.findall(r'<(?:script|iframe)[^>]+src="([^"]+)"', s) or [])[:10])
for w in ("ckan", "opendatasoft", "dkan", "socrata", "arcgis", "udata", "wordpress", "dataset", "conjunt de dades", "dades obertes", "open data", "llic", "creative commons", "telecom", "cobertura", "antena", "mòbil", "govern", "domini", "parking", "venda"):
    n = len(re.findall(re.escape(w), s, re.I))
    if n:
        print("  mot « %s » : %d" % (w, n))
PY
for p in "robots.txt" "api/3/action/package_search?q=telecom&rows=5" "api/3/action/package_search?q=cobertura&rows=5" "data.json" "api/explore/v2.1/catalog/datasets?limit=5"; do
  rm -f od_p.bin; g od_p.bin "http://opendata.ad/$p"; [ -s od_p.bin ] && { head -c 420 od_p.bin | tr '\n\r\t' '   ' | cut -c1-420; echo; }
done

echo "### B. gouv.mc : résultats du moteur de recherche du portail"
g gouv.html "https://www.gouv.mc/"
python3 - <<'PY'
import re, html, os, urllib.request, urllib.parse
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
def links(s):
    out = []
    for h, x in re.findall(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', s, re.S | re.I):
        x = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", x))).strip()
        out.append((html.unescape(h), x))
    return out
home = {h for h, x in links(open("gouv.html", encoding="utf-8", errors="replace").read())}
for q in ("open data", "données ouvertes", "data.gouv.mc", "couverture mobile", "cartoradio"):
    u = "https://www.gouv.mc/recherche/resultats?" + urllib.parse.urlencode({"query": q})
    try:
        with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=60) as r:
            p = r.read().decode("utf-8", "replace")
    except Exception as e:
        print("  recherche « %s » : échec %s" % (q, str(e)[:100])); continue
    b = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", p, flags=re.S | re.I)
    b = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
    m = re.search(r"(\d+)\s+r[ée]sultats?|aucun r[ée]sultat", b, re.I)
    new = []
    for h, x in links(p):
        if h not in home and len(x) > 8 and not h.startswith(("#", "javascript", "mailto")) and "/recherche/" not in h and (h, x) not in new:
            new.append((h, x))
    print("  recherche « %s » : %s | %d lien(s) propres à la page" % (q, ("«" + b[max(0, m.start() - 60): m.end() + 60] + "»") if m else "pas de compteur lu", len(new)))
    for h, x in new[:9]:
        print("       ", x[:95], "|", h[:95])
    n = len(re.findall(r"data\.gouv\.mc", p, re.I))
    print("        occurrences de « data.gouv.mc » dans la page de résultats :", n)
PY

echo "### C. data.gouv.mc : dernier essai du jour"
g mc.html "https://data.gouv.mc/"
grep -i -E '^(HTTP/|server:|retry-after:|content-length:)' mc.html.hdr | tr -d '\r' | head -4
python3 -c "
import re,html
s=open('mc.html',encoding='utf-8',errors='replace').read()
t=re.search(r'<title[^>]*>(.*?)</title>',s,re.S|re.I)
print('  titre :', html.unescape(t.group(1)).strip()[:160] if t else None)"
date -u +"  heure de la sonde (UTC) : %Y-%m-%d %H:%M"

echo "### D. Common Crawl : autres index (un essai chacun)"
python3 - <<'PY'
import json, os, urllib.request, urllib.parse, urllib.error, re, time
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
def fetch(url, timeout=75):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=timeout) as r:
        return r.read()
try:
    colls = json.loads(fetch("https://index.commoncrawl.org/collinfo.json", 40))
except Exception as e:
    print("  liste des index illisible :", e); colls = []
for c in colls[:6]:
    if c["id"] == "CC-MAIN-2026-39":
        print("  ", c["id"], ": déjà lu par la sonde 3 (aucune capture)"); continue
    q = c["cdx-api"] + "?" + urllib.parse.urlencode({"url": "data.gouv.mc/*", "output": "json", "limit": "40"})
    try:
        raw = fetch(q)
        rs = [json.loads(l) for l in raw.decode("utf-8", "replace").splitlines() if l.strip().startswith("{")]
        print("  ", c["id"], ": réponse 200,", len(rs), "capture(s)")
        for r in rs[:10]:
            print("       ", r.get("timestamp"), r.get("status"), r.get("mime"), r.get("url", "")[:110], "|", r.get("filename", "")[-50:], r.get("offset"), r.get("length"))
    except urllib.error.HTTPError as e:
        print("  ", c["id"], ": HTTP", e.code, re.sub(rb"\s+", b" ", e.read()[:110]))
    except Exception as e:
        print("  ", c["id"], ": échec", str(e)[:100])
    time.sleep(3)
PY
echo "### fin"
