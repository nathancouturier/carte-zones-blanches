#!/usr/bin/env bash
# Contre-vérification « Andorre et Monaco », sonde 6 (dernière) : depuis quand l'hôte data.gouv.mc existe-t-il
# (certificat, journaux de transparence), le Journal de Monaco en parle-t-il ; plan du site du Govern d'Andorre sur
# des mots précis ; contexte du mot « telecom » dans le catalogue andorran ; libellé de l'EPSG:3944 ; lien entre
# « Mobiland » et Andorra Telecom ; codes français de la liste UIT. Pages, métadonnées et registres seulement.
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

echo "### A. data.gouv.mc : certificat du serveur et journaux de transparence des certificats"
python3 - <<'PY'
import socket, ssl, json, os, urllib.request
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
for host in ("data.gouv.mc", "www.gouv.mc"):
    try:
        ctx = ssl.create_default_context()
        with socket.create_connection((host, 443), timeout=15) as s:
            with ctx.wrap_socket(s, server_hostname=host) as t:
                c = t.getpeercert()
        subj = dict(x[0] for x in c.get("subject", ()))
        iss = dict(x[0] for x in c.get("issuer", ()))
        san = [v for k, v in c.get("subjectAltName", ())]
        print("  certificat de", host, ": sujet=%r | émetteur=%r | du %s au %s" % (subj.get("commonName"), iss.get("organizationName"), c.get("notBefore"), c.get("notAfter")))
        print("     noms couverts (%d) :" % len(san), san[:14])
    except Exception as e:
        print("  certificat de", host, ": échec", str(e)[:160])
try:
    with urllib.request.urlopen(urllib.request.Request("https://crt.sh/?q=data.gouv.mc&output=json", headers={"User-Agent": UA}), timeout=75) as r:
        rows = json.loads(r.read().decode("utf-8", "replace"))
    nb = sorted(x.get("not_before", "") for x in rows)
    print("  crt.sh, certificats émis pour data.gouv.mc :", len(rows), "| premier :", nb[0] if nb else None, "| dernier :", nb[-1] if nb else None)
    print("     noms :", sorted({n for x in rows for n in (x.get("name_value") or "").split("\n")})[:10])
    print("     émetteurs :", sorted({(x.get("issuer_name") or "")[-60:] for x in rows})[:4])
except Exception as e:
    print("  crt.sh : échec", str(e)[:160])
PY
g mc.html "https://data.gouv.mc/"
date -u +"  heure de la sonde (UTC) : %Y-%m-%d %H:%M"

echo "### B. Journal de Monaco : un texte officiel cite-t-il data.gouv.mc ou l'ouverture des données ?"
g jm.html "https://journaldemonaco.gouv.mc/"
python3 - <<'PY'
import re, html, os, urllib.request, urllib.parse
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
try:
    s = open("jm.html", encoding="utf-8", errors="replace").read()
except Exception as e:
    print("  page d'accueil illisible :", e); raise SystemExit
def links(p):
    out = []
    for h, x in re.findall(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', p, re.S | re.I):
        x = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", x))).strip()
        out.append((html.unescape(h), x))
    return out
home = {h for h, x in links(s)}
cand = None
for attrs, inner in re.findall(r"<form\b([^>]*)>(.*?)</form>", s, re.S | re.I)[:6]:
    act = re.search(r'action="([^"]*)"', attrs)
    names = re.findall(r'<input\b[^>]*name="([^"]+)"', inner)
    print("  formulaire : action=%r champs=%r" % (act.group(1)[:90] if act else None, names[:5]))
    if act and names and cand is None and re.search(r"search|rech", act.group(1) + " ".join(names), re.I):
        field = [n for n in names if re.search(r"text|query|q$|search", n, re.I)] or names
        cand = (urllib.parse.urljoin("https://journaldemonaco.gouv.mc/", html.unescape(act.group(1))), field[0])
if not cand:
    cand = ("https://journaldemonaco.gouv.mc/content/search", "SearchText")
    print("  pas de formulaire reconnu : essai de l'adresse habituelle", cand)
for q in ('"data.gouv.mc"', '"open data"', '"données ouvertes"'):
    u = cand[0] + ("&" if "?" in cand[0] else "?") + urllib.parse.urlencode({cand[1]: q})
    try:
        with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=60) as r:
            p = r.read().decode("utf-8", "replace")
    except Exception as e:
        print("  recherche %s : échec %s | %s" % (q, str(e)[:90], u[:110])); continue
    b = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", p, flags=re.S | re.I)
    b = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
    m = re.search(r"(\d+)\s+r[ée]sultats?|aucun r[ée]sultat|no results?|(\d+)\s+results?", b, re.I)
    new = []
    for h, x in links(p):
        if h not in home and len(x) > 14 and not h.startswith(("#", "javascript", "mailto")) and (h, x) not in new:
            new.append((h, x))
    print("  recherche %s : %s | %d lien(s) propres à la page" % (q, ("«" + b[max(0, m.start() - 50): m.end() + 50] + "»") if m else "pas de compteur lu", len(new)))
    for h, x in new[:7]:
        print("       ", x[:120], "|", h[:100])
PY

echo "### C. govern.ad : adresses du plan du site sur des mots précis"
python3 - <<'PY'
import re, os, urllib.request
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
W = re.compile(r"dades-obertes|open-?data|donnees-ouvertes|datos-abiertos|antena|antenes|antenne|radiaci|electromagn|cobertura-(?:mobil|de-la-xarxa|5g|4g|de-telefonia)|couverture-mobile|(?:^|[-/])5g(?:[-/]|$)|telecomunicacions|telecommunications|telecomunicaciones|telefonia-mobil|xarxa-mobil|mapa-de-cobertura", re.I)
def fetch(u):
    with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=60) as r:
        return r.read().decode("utf-8", "replace")
urls = []
for lang in ("ca", "en", "fr", "es"):
    try:
        locs = re.findall(r"<loc>\s*([^<\s]+)\s*</loc>", fetch("https://www.govern.ad/%s/sitemap.xml" % lang))
        urls += locs
    except Exception as e:
        print("  plan", lang, ": échec", str(e)[:100])
hits = sorted({u for u in urls if W.search(u)})
print("  adresses lues :", len(urls), "| sur les mots précis :", len(hits))
for u in hits[:40]:
    print("    ", u.replace("https://www.govern.ad", "")[:175])
PY

echo "### D. IDE Andorra : où apparaît « telecom » dans les 8 fiches trouvées par la sonde 2 ?"
python3 - <<'PY'
import re, html, os, urllib.request
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
body = ('<?xml version="1.0" encoding="UTF-8"?><csw:GetRecords xmlns:csw="http://www.opengis.net/cat/csw/2.0.2" xmlns:ogc="http://www.opengis.net/ogc" '
        'xmlns:gmd="http://www.isotc211.org/2005/gmd" service="CSW" version="2.0.2" resultType="results" startPosition="1" maxRecords="2" outputSchema="http://www.isotc211.org/2005/gmd">'
        '<csw:Query typeNames="gmd:MD_Metadata"><csw:ElementSetName>full</csw:ElementSetName><csw:Constraint version="1.1.0"><ogc:Filter>'
        '<ogc:PropertyIsLike wildCard="%" singleChar="_" escapeChar="\\"><ogc:PropertyName>AnyText</ogc:PropertyName><ogc:Literal>%telecom%</ogc:Literal></ogc:PropertyIsLike>'
        '</ogc:Filter></csw:Constraint></csw:Query></csw:GetRecords>')
try:
    req = urllib.request.Request("https://www.ideandorra.ad/Cataleg/srv/cat/csw", data=body.encode("utf-8"), headers={"User-Agent": UA, "Content-Type": "application/xml"})
    with urllib.request.urlopen(req, timeout=90) as r:
        x = r.read().decode("utf-8", "replace")
except Exception as e:
    print("  échec :", str(e)[:160]); raise SystemExit
m = re.search(r'numberOfRecordsMatched="(\d+)"', x)
print("  fiches trouvées :", m.group(1) if m else None)
for rec in re.findall(r"<gmd:MD_Metadata\b.*?</gmd:MD_Metadata>", x, re.S)[:2]:
    t = re.findall(r"<gmd:title>(.*?)</gmd:title>", rec, re.S)[:1]
    flat = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", rec))).strip()
    print("   fiche", [re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", v)).strip() for v in t], "| longueur du texte", len(flat))
    for q in [k.start() for k in re.finditer(r"telecom", flat, re.I)][:2]:
        print("     contexte : «" + flat[max(0, q - 260): q + 200] + "»")
PY

echo "### E. Libellé de l'EPSG:3944 (GDAL de l'image, sans réseau)"
python3 - <<'PY'
from osgeo import osr
s = osr.SpatialReference(); s.ImportFromEPSG(3944)
print("  EPSG:3944 :", s.GetName(), "| projection :", s.GetAttrValue("PROJECTION") or s.GetAttrValue("CONVERSION|METHOD"), "| unité :", s.GetLinearUnitsName())
print("  proj4 :", s.ExportToProj4())
PY

echo "### F. « Mobiland » et Andorra Telecom (page d'accueil et avis légal de l'opérateur public, rien d'autre)"
for u in "https://www.andorratelecom.ad/" "https://www.andorratelecom.ad/avis-legal"; do
  rm -f at.html; g at.html "$u"
  [ -s at.html ] && python3 - <<'PY'
import re, html
s = open("at.html", encoding="utf-8", errors="replace").read()
b = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
b = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
for w in (r"mobiland", r"\bS\.?A\.?U\.?\b", r"titular", r"operador"):
    ms = [m.start() for m in re.finditer(w, b, re.I)]
    print("     motif « %s » : %d dans le texte, %d dans le code" % (w, len(ms), len(re.findall(w, s, re.I))), ("| «" + b[max(0, ms[0] - 170): ms[0] + 230] + "»") if ms else "")
PY
done

echo "### G. Liste UIT : codes français cités pour Monaco"
g itu.pdf "https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-E.212B-2023-PDF-E.pdf"
(apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq poppler-utils) >/dev/null 2>&1
pdftotext -layout itu.pdf itu.txt 2>&1 | head -2
python3 - <<'PY'
import re
try:
    L = open("itu.txt", encoding="utf-8", errors="replace").read().splitlines()
except Exception as e:
    print("  texte du PDF illisible :", e); raise SystemExit
for code in ("208 01", "208 10", "208 15", "208 20", "228 01", "228 02", "228 03", "901 27"):
    print("  ", code, ":", [re.sub(r"\s+", " ", l.strip())[:90] for l in L if re.search(r"\b%s\s*$" % code, l)][:4])
print("  entrées du MCC 208 :", sum(1 for l in L if re.search(r"\b208 \d{2}\s*$", l)), "| du MCC 228 :", sum(1 for l in L if re.search(r"\b228 \d{2}\s*$", l)), "| du MCC 222 :", sum(1 for l in L if re.search(r"\b222 \d{2}\s*$", l)))
PY
echo "### fin"
