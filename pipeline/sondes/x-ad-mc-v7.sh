#!/usr/bin/env bash
# Contre-vérification « Andorre et Monaco », sonde 7 : la page « Site en maintenance » de data.gouv.mc prouve-t-elle
# qu'un site existe à ce nom, ou est-ce la réponse par défaut de tout nom en .gouv.mc ? Plan du site de gouv.mc sur
# des mots plus larges ; compteurs du moteur de recherche du Journal de Monaco. Pages et DNS seulement.
set -u
. "$(dirname "$0")/_lib.sh"
UA="sonde-sources-ouvertes/1.0"   # User-Agent générique (pas de nom de projet ni de compte envoyé à des tiers)
export UA
cd "$T" || exit 1

echo "### A. data.gouv.mc : nom propre ou réponse par défaut de la zone gouv.mc ?"
python3 - <<'PY'
import socket, os, re, html, hashlib, urllib.request, urllib.error, ssl
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
names = ["data.gouv.mc", "www.gouv.mc", "sonde-inexistant-7391.gouv.mc", "zz-nexiste-pas-2026.gouv.mc", "opendata.gouv.mc", "donnees.gouv.mc"]
ips = {}
for h in names:
    try:
        ips[h] = sorted({i[4][0] for i in socket.getaddrinfo(h, 443)})
        print("  DNS", h, "->", ips[h][:3])
    except Exception as e:
        print("  DNS", h, ": ne se résout pas (%s)" % str(e)[:50])
def page(h):
    try:
        with urllib.request.urlopen(urllib.request.Request("https://%s/" % h, headers={"User-Agent": UA}), timeout=30) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:
        return None, str(e)[:140].encode()
for h in names:
    if h in ips and h != "www.gouv.mc":
        code, body = page(h)
        s = body.decode("utf-8", "replace")
        t = re.search(r"<title[^>]*>(.*?)</title>", s, re.S | re.I)
        print("  GET https://%s/ : code=%s taille=%d sha1=%s titre=%r" % (h, code, len(body), hashlib.sha1(body).hexdigest()[:12], html.unescape(t.group(1)).strip()[:90] if t else s[:120]))
PY
date -u +"  heure de la sonde (UTC) : %Y-%m-%d %H:%M"

echo "### B. Plan du site de gouv.mc : adresses évoquant les données ou une plateforme de données"
python3 - <<'PY'
import re, os, urllib.request
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
def fetch(u):
    with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=60) as r:
        return r.read().decode("utf-8", "replace")
todo, urls, n = ["https://www.gouv.mc/sitemap.xml"], [], 0
while todo and n < 12:
    u = todo.pop(0); n += 1
    try:
        x = fetch(u)
    except Exception as e:
        print("    ", u[:90], ": échec", str(e)[:90]); continue
    locs = re.findall(r"<loc>\s*([^<\s]+)\s*</loc>", x)
    if "<sitemapindex" in x:
        print("     index :", u, "->", len(locs), "plans"); todo += locs[:10]
    else:
        urls += locs
W = re.compile(r"donnee|[-/]data(?![a-z])|open|plateforme|statisti|cartoradio|ondes|electromagn|telecom|couverture|5g|antenne", re.I)
X = re.compile(r"donnees-personnelles|protection-des-donnees", re.I)
hits = sorted({u for u in urls if W.search(u) and not X.search(u)})
print("  adresses lues :", len(urls), "| évocatrices :", len(hits))
for u in hits[:45]:
    print("    ", u.replace("https://www.gouv.mc", "")[:170])
PY

echo "### C. Journal de Monaco : compteurs de la recherche"
python3 - <<'PY'
import re, html, os, urllib.request, urllib.parse
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
for q in ("data.gouv.mc", '"data.gouv.mc"', '"Data Monaco"', '"réutilisation des données publiques"', '"réutilisation des informations publiques"'):
    u = "https://journaldemonaco.gouv.mc/content/search?" + urllib.parse.urlencode({"SearchText": q})
    try:
        with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=60) as r:
            p = r.read().decode("utf-8", "replace")
    except Exception as e:
        print("  recherche %s : échec %s" % (q, str(e)[:100])); continue
    b = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", p, flags=re.S | re.I)
    b = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
    m = re.search(r"La recherche[^.]{0,90}|[Aa]ucun r[ée]sultat[^.]{0,60}", b)
    res = []
    for h, x in re.findall(r'<a\b[^>]*href="(/Journaux/\d{4}/[^"]+)"[^>]*>(.*?)</a>', p, re.S | re.I):
        x = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", x))).strip()
        if len(x) > 20 and x not in res:
            res.append(x)
    print("  recherche %s : %s | %d titre(s)" % (q, ("«" + m.group(0)[:120] + "»") if m else "pas de phrase de résultat lue", len(res)))
    for x in res[:5]:
        print("       ", x[:190])
PY
echo "### fin"
