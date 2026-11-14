#!/usr/bin/env bash
# Contre-vérification « Andorre et Monaco », sonde 2 : Andorre (portails du Govern, IDE Andorra, avis légal,
# mentions légales de l'opérateur public) et page de statistiques d'OpenCelliD. Pages, catalogues et conditions
# seulement : aucune donnée de carte demandée.
set -u
. "$(dirname "$0")/_lib.sh"
UA="sonde-sources-ouvertes/1.0"   # User-Agent générique (pas de nom de projet ni de compte envoyé à des tiers)
export UA
cd "$T" || exit 1
g() { # g <fichier> <url> : un seul essai, délais courts ; affiche code, taille, type, adresse finale
  local f="$1" u="$2" r
  r=$(curl -sS -L --connect-timeout 10 -m 90 -A "$UA" -o "$f" -w "%{http_code} %{size_download}o %{content_type} final=%{url_effective}" "$u" 2>&1)
  echo "  -> $r | $u" | cut -c1-300
}
titre() { python3 -c "
import re,html,sys
s=open(sys.argv[1],encoding='utf-8',errors='replace').read()
t=re.search(r'<title[^>]*>(.*?)</title>',s,re.S|re.I)
print('     titre :', html.unescape(t.group(1)).strip()[:150] if t else None)" "$1" 2>/dev/null; }

echo "### A. Andorre : adresses candidates d'un portail de données ouvertes"
for u in https://dadesobertes.ad/ https://www.dadesobertes.ad/ https://opendata.ad/ https://www.opendata.ad/ \
         https://dadesobertes.govern.ad/ https://opendata.govern.ad/ https://dades.govern.ad/ https://data.govern.ad/ \
         https://www.govern.ad/dades-obertes https://www.govern.ad/ca/dades-obertes; do
  rm -f cand.html; g cand.html "$u"; [ -s cand.html ] && titre cand.html
done

echo "### B. govern.ad : page d'accueil, plan du site"
g gov.html "https://www.govern.ad/"
g gov_robots.txt "https://www.govern.ad/robots.txt"
grep -i -E 'sitemap|disallow' gov_robots.txt | head -6 | cut -c1-160
python3 - <<'PY'
import re, html, os, urllib.request
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
W = re.compile(r"dades[ -]?obertes|open ?data|opendata|telecom|telefon|antena|antenes|cobertura|radiaci|electromagn|m[oò]bil(?!itat)|\b5g\b|transpar|estad[ií]stic|cartograf|geoportal|reutilitz", re.I)
s = open("gov.html", encoding="utf-8", errors="replace").read()
links = re.findall(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', s, re.S | re.I)
print("  liens dans la page d'accueil :", len(links))
seen = set()
for h, t in links:
    t = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", t))).strip()
    if W.search(h) or W.search(t):
        k = (h, t)
        if k in seen: continue
        seen.add(k)
        if len(seen) <= 30: print("    ", h[:120], "|", t[:70])
print("  liens retenus :", len(seen))
sm = re.findall(r"(?im)^sitemap:\s*(\S+)", open("gov_robots.txt", encoding="utf-8", errors="replace").read()) or ["https://www.govern.ad/sitemap.xml"]
def fetch(u):
    with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=60) as r:
        return r.read().decode("utf-8", "replace")
todo, urls, n = list(sm[:2]), [], 0
while todo and n < 6:
    u = todo.pop(0); n += 1
    try:
        x = fetch(u)
    except Exception as e:
        print("  plan du site", u, ": échec", str(e)[:100]); continue
    locs = re.findall(r"<loc>\s*([^<\s]+)\s*</loc>", x)
    print("  plan du site", u[:100], ":", len(locs), "adresses")
    if "<sitemapindex" in x:
        todo += locs[:4]
    else:
        urls += locs
hits = [u for u in urls if W.search(u)]
print("  adresses du plan :", len(urls), "| évocatrices :", len(hits))
for u in hits[:30]: print("    ", u[:160])
PY

echo "### C. IDE Andorra : catalogue CSW (requêtes filtrées, quelques fiches seulement)"
python3 - <<'PY'
import re, html, os, urllib.request
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
CSW = "https://www.ideandorra.ad/Cataleg/srv/cat/csw"
def post(body):
    req = urllib.request.Request(CSW, data=body.encode("utf-8"), headers={"User-Agent": UA, "Content-Type": "application/xml"})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.read().decode("utf-8", "replace")
    except Exception as e:
        return "ERREUR " + str(e)[:200]
def req(term=None, n=8, schema="http://www.opengis.net/cat/csw/2.0.2", es="brief", typ="csw:Record"):
    flt = ""
    if term:
        flt = ('<csw:Constraint version="1.1.0"><ogc:Filter><ogc:PropertyIsLike wildCard="%%" singleChar="_" escapeChar="\\">'
               '<ogc:PropertyName>AnyText</ogc:PropertyName><ogc:Literal>%%%s%%</ogc:Literal></ogc:PropertyIsLike></ogc:Filter></csw:Constraint>' % term)
    return ('<?xml version="1.0" encoding="UTF-8"?><csw:GetRecords xmlns:csw="http://www.opengis.net/cat/csw/2.0.2" xmlns:ogc="http://www.opengis.net/ogc" '
            'xmlns:gmd="http://www.isotc211.org/2005/gmd" service="CSW" version="2.0.2" resultType="results" startPosition="1" maxRecords="%d" outputSchema="%s">'
            '<csw:Query typeNames="%s"><csw:ElementSetName>%s</csw:ElementSetName>%s</csw:Query></csw:GetRecords>' % (n, schema, typ, es, flt))
def titles(x):
    return [re.sub(r"\s+", " ", html.unescape(t)).strip() for t in re.findall(r"<dc:title[^>]*>(.*?)</dc:title>", x, re.S)]
def matched(x):
    m = re.search(r'numberOfRecordsMatched="(\d+)"', x)
    return int(m.group(1)) if m else None
caps_url = CSW + "?service=CSW&version=2.0.2&request=GetCapabilities"
try:
    with urllib.request.urlopen(urllib.request.Request(caps_url, headers={"User-Agent": UA}), timeout=60) as r:
        caps = r.read().decode("utf-8", "replace")
    for tag in ("ows:Title", "ows:Fees", "ows:AccessConstraints", "ows:ProviderName"):
        m = re.search(r"<%s[^>]*>(.*?)</%s>" % (tag, tag), caps, re.S)
        print("  capacités", tag, ":", html.unescape(m.group(1)).strip()[:120] if m else None)
except Exception as e:
    print("  capacités illisibles :", str(e)[:120])
x = post(req(None, 1))
print("  total des fiches (sans filtre) :", matched(x), "" if matched(x) is not None else x[:300])
x = post(req("zzqxjw", 1))
print("  contrôle du filtre, mot inexistant « zzqxjw » :", matched(x), "" if matched(x) is not None else x[:300])
for term in ("telecom", "telef", "antena", "antenes", "repetidor", "cobertura", "mòbil", "mobil", "radio", "electromagn", "emissor", "5G", "fibra", "llicència", "Creative Commons", "reutilitz"):
    x = post(req(term, 6))
    n = matched(x)
    ts = titles(x)
    print("  « %s » : %s fiche(s)" % (term, n), "|", " ; ".join(sorted(set(t[:70] for t in ts)))[:330] if n is not None else x[:200])
# Quelques fiches complètes (ISO 19139) : que disent les contraintes d'usage ?
x = post(req(None, 4, "http://www.isotc211.org/2005/gmd", "full", "gmd:MD_Metadata"))
recs = re.findall(r"<gmd:MD_Metadata\b.*?</gmd:MD_Metadata>", x, re.S)
print("  fiches ISO lues :", len(recs), "" if recs else x[:300])
def txt(frag):
    return [re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", t))).strip() for t in frag]
for r in recs:
    t = txt(re.findall(r"<gmd:title>(.*?)</gmd:title>", r, re.S)[:1])
    ul = txt(re.findall(r"<gmd:useLimitation>(.*?)</gmd:useLimitation>", r, re.S))
    oc = txt(re.findall(r"<gmd:otherConstraints>(.*?)</gmd:otherConstraints>", r, re.S))
    codes = re.findall(r'<gmd:MD_RestrictionCode[^>]*codeListValue="([^"]*)"', r)
    print("    fiche", t, "| useLimitation :", [u[:160] for u in ul][:3], "| otherConstraints :", [o[:160] for o in oc][:3], "| codes :", sorted(set(codes)))
PY

echo "### D. IDE Andorra : service WMS global"
g wms.xml "https://www.ideandorra.ad/Serveis/ows?service=WMS&version=1.3.0&request=GetCapabilities"
python3 - <<'PY'
import re, xml.etree.ElementTree as ET
try:
    root = ET.parse("wms.xml").getroot()
except Exception as e:
    print("  capacités WMS illisibles :", e); raise SystemExit
ns = {"w": "http://www.opengis.net/wms"}
svc = root.find("w:Service", ns)
for tag in ("Title", "Abstract", "Fees", "AccessConstraints"):
    e = svc.find("w:" + tag, ns) if svc is not None else None
    print("  service", tag, ":", (e.text or "").strip()[:140] if e is not None else None)
layers = []
for l in root.iter("{http://www.opengis.net/wms}Layer"):
    n = l.find("w:Name", ns)
    if n is None or not (n.text or "").strip():
        continue
    t = l.find("w:Title", ns); a = l.find("w:Abstract", ns)
    kw = " ".join((k.text or "") for k in l.findall("w:KeywordList/w:Keyword", ns))
    layers.append((n.text.strip(), (t.text or "").strip() if t is not None else "", (a.text or "").strip() if a is not None else "", kw))
print("  couches nommées :", len(layers), "| espaces de travail :", len({n.split(":")[0] for n, *_ in layers if ":" in n}))
W = re.compile(r"telecom|telef|antena|antenes|antrep|repetidor|emissor|cobertura|m[oò]bil(?!itat)|electromagn|\b[2345]g\b|\blte\b|radioel|radioc|radiodif|fibra|comunicacions", re.I)
hits = [(n, t, a) for n, t, a, kw in layers if W.search(n) or W.search(t) or W.search(a) or W.search(kw)]
print("  couches évoquant télécoms, antennes ou couverture :", len(hits))
for n, t, a in hits[:25]:
    print("    ", n[:60], "|", t[:70], "|", re.sub(r"\s+", " ", a)[:110])
PY

echo "### E. IDE Andorra : avis légal et page de téléchargement"
g avis.html "https://www.cartografia.ad/avis-legal"
g desc.html "https://www.cartografia.ad/web-de-descarregues"
python3 - <<'PY'
import re, html
def body(p):
    s = open(p, encoding="utf-8", errors="replace").read()
    b = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
for p, pats in (("avis.html", (r"consentiment previ", r"ús privat i personal", r"propietat intel", r"llic[eè]nci", r"creative commons|CC BY", r"reutilitz", r"dades obertes|open data", r"geoinformaci|cartograf")),
                ("desc.html", (r"condicions d.ús", r"lliure", r"llic[eè]nci", r"creative commons|CC BY", r"gratu"))):
    try:
        b = body(p)
    except Exception as e:
        print("  ", p, "illisible :", e); continue
    print("  ", p, ": longueur du texte", len(b))
    seen = []
    for w in pats:
        ms = [m.start() for m in re.finditer(w, b, re.I)]
        print("   motif « %s » : %d" % (w, len(ms)))
        for q in ms[:2]:
            if any(abs(q - z) < 280 for z in seen): continue
            seen.append(q)
            print("      «", b[max(0, q - 300): q + 300], "»")
PY

echo "### F. Opérateur public Andorra Telecom : seulement la page d'accueil et les mentions légales (aucune carte)"
g at.html "https://www.andorratelecom.ad/"
python3 - <<'PY'
import re, html, os, urllib.request, urllib.parse
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
s = open("at.html", encoding="utf-8", errors="replace").read()
t = re.search(r"<title[^>]*>(.*?)</title>", s, re.S | re.I)
print("  titre :", html.unescape(t.group(1)).strip()[:120] if t else None, "| taille", len(s))
links = []
for h, x in re.findall(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', s, re.S | re.I):
    x = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", x))).strip()
    if re.search(r"legal|condicions|privacitat|cobertura|dades[ -]obertes|open ?data", h + " " + x, re.I):
        links.append((urllib.parse.urljoin("https://www.andorratelecom.ad/", h), x[:60]))
links = sorted(set(links))
print("  liens (mentions légales, couverture, données ouvertes) :", links[:14])
legal = [u for u, x in links if re.search(r"legal", u + " " + x, re.I)]
if legal:
    try:
        with urllib.request.urlopen(urllib.request.Request(legal[0], headers={"User-Agent": UA}), timeout=60) as r:
            p = r.read().decode("utf-8", "replace")
        b = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", p, flags=re.S | re.I)
        b = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
        print("  page lue :", legal[0], "| longueur du texte", len(b))
        seen = []
        for w in (r"propietat intel", r"reproducci", r"autoritzaci", r"llic[eè]nci", r"dades obertes|open data", r"reutilitz"):
            ms = [m.start() for m in re.finditer(w, b, re.I)]
            print("   motif « %s » : %d" % (w, len(ms)))
            for q in ms[:1]:
                if any(abs(q - z) < 300 for z in seen): continue
                seen.append(q)
                print("      «", b[max(0, q - 300): q + 320], "»")
    except Exception as e:
        print("  page des mentions légales illisible :", str(e)[:160])
else:
    print("  aucun lien de mentions légales dans la page d'accueil (page construite par script ?)")
PY

echo "### G. OpenCelliD : page publique de statistiques (lignes Andorre, Monaco, France)"
g oc.html "https://opencellid.org/stats.php"
python3 - <<'PY'
import re, html
s = open("oc.html", encoding="utf-8", errors="replace").read()
rows = re.findall(r"<tr\b.*?</tr>", s, re.S | re.I)
print("  lignes de tableau :", len(rows))
for r in rows:
    cells = [re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", c))).strip() for c in re.findall(r"<t[hd]\b[^>]*>(.*?)</t[hd]>", r, re.S | re.I)]
    if cells and (any(re.fullmatch(r"(Andorra|Monaco|France)", c) for c in cells[:3]) or re.search(r"country|total|gsm", " ".join(cells), re.I) and len(cells) > 3 and not re.search(r"\d{3}", " ".join(cells))):
        print("    ", " | ".join(cells)[:200])
for w in (r"CC[ -]BY[ -]SA[ -]4\.0", r"Creative Commons[^<]{0,80}"):
    m = re.search(w, s, re.I)
    print("  mention de licence « %s » :" % w, re.sub(r"\s+", " ", s[max(0, m.start() - 120): m.end() + 80]) if m else None)
PY
echo "### fin"
