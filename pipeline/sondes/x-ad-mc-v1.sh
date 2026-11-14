#!/usr/bin/env bash
# Contre-vérification « Andorre et Monaco », sonde 1 : Monaco (data.gouv.mc, cartoradio.mc, CGU de gouv.mc)
# et liste UIT E.212. Lecture de pages, de métadonnées et de conditions seulement : aucune entité demandée.
set -u
. "$(dirname "$0")/_lib.sh"
UA="sonde-sources-ouvertes/1.0"   # User-Agent générique (pas de nom de projet ni de compte envoyé à des tiers)
export UA
cd "$T" || exit 1
g() { # g <fichier> <url> : un seul essai, délais courts ; affiche code, taille, type, adresse finale
  local f="$1" u="$2" r
  r=$(curl -sS -L --connect-timeout 12 -m 90 -A "$UA" -o "$f" -D "$f.hdr" -w "%{http_code} %{size_download}o %{content_type} final=%{url_effective}" "$u" 2>&1)
  echo "  -> $r | $u" | cut -c1-300
}

echo "### A. data.gouv.mc : existe-t-il un portail de données ouvertes ?"
python3 - <<'PY'
import socket
for h in ("data.gouv.mc", "www.gouv.mc", "cartoradio.mc", "montecarto.gouv.mc", "montecarto-srv.gouv.mc"):
    try:
        print("  DNS", h, "->", sorted({i[4][0] for i in socket.getaddrinfo(h, 443)})[:4])
    except Exception as e:
        print("  DNS", h, "ECHEC", e)
PY
g dns.json "https://dns.google/resolve?name=data.gouv.mc&type=CNAME"
python3 - <<'PY'
import json
try:
    d = json.load(open("dns.json"))
    print("  CNAME data.gouv.mc :", [a.get("data") for a in d.get("Answer", [])] or ("aucun ; autorité : %s" % [a.get("data") for a in d.get("Authority", [])]))
except Exception as e:
    print("  réponse DNS illisible :", e)
PY
g mc_home.html "https://data.gouv.mc/"
echo "  en-têtes de la dernière réponse :"
awk 'BEGIN{RS="\r\n\r\n"} {if (length($0) > 5) last=$0} END{print last}' mc_home.html.hdr | tr -d '\r' | grep -i -E '^(HTTP/|server:|via:|retry-after:|content-type:|content-length:|x-[a-z0-9-]+:|cf-|age:|cache-control:)' | cut -c1-150 | head -14
python3 - <<'PY'
import re, html
s = open("mc_home.html", encoding="utf-8", errors="replace").read()
t = re.search(r"<title[^>]*>(.*?)</title>", s, re.S | re.I)
print("  titre :", html.unescape(t.group(1)).strip()[:200] if t else None)
for m in re.finditer(r'<meta[^>]+(?:name|property)="(generator|description|og:site_name|application-name)"[^>]*content="([^"]*)"', s, re.I):
    print("  meta", m.group(1), ":", html.unescape(m.group(2))[:200])
body = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
body = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", body))).strip()
print("  texte (début) :", body[:500])
hits = sorted(set(re.findall(r'(?:href|src)="([^"]*(?:api|dataset|jeux|licen|condition|mentions|explore|catalog)[^"]*)"', s, re.I)))
print("  liens évocateurs (%d) :" % len(hits), hits[:25])
for w in ("opendatasoft", "huwise", "ckan", "udata", "dkan", "socrata", "arcgis", "dawex", "data4", "jeux de données", "open data", "licence", "maintenance"):
    n = len(re.findall(re.escape(w), s, re.I))
    if n:
        print("  mot « %s » : %d" % (w, n))
PY
for p in "robots.txt" "api/explore/v2.1/catalog/datasets?limit=1" "api/3/action/package_list?limit=1"; do
  g mc_p.bin "https://data.gouv.mc/$p"; head -c 220 mc_p.bin | tr '\n\r' '  ' | cut -c1-220; echo
done

echo "### A2. data.gouv.mc dans Internet Archive (avec une requête témoin)"
g wb0.json "https://archive.org/wayback/available?url=data.gouv.mc"
head -c 300 wb0.json; echo
g wb1.json "https://web.archive.org/cdx/search/cdx?url=data.gouv.mc&matchType=host&output=json&limit=6&fl=timestamp,original,statuscode,mimetype,length"
head -c 700 wb1.json | tr '\n' ' '; echo
g wb2.json "https://web.archive.org/cdx/search/cdx?url=data.gouv.mc&matchType=host&output=json&limit=-6&fl=timestamp,original,statuscode,mimetype,length"
head -c 700 wb2.json | tr '\n' ' '; echo
g wb3.json "https://web.archive.org/cdx/search/cdx?url=data.gouv.mc&matchType=host&showNumPages=true"
echo "  nombre de pages d'index pour l'hôte : $(head -c 40 wb3.json | tr '\n' ' ')"
g wbt.json "https://web.archive.org/cdx/search/cdx?url=cartoradio.mc&matchType=host&output=json&limit=3&fl=timestamp,original,statuscode"
echo "  témoin cartoradio.mc : $(head -c 300 wbt.json | tr '\n' ' ')"

echo "### A3. data.gouv.mc dans Common Crawl (archive ouverte)"
python3 - <<'PY'
import json, os, urllib.request, urllib.parse, gzip, re, html, io
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
def fetch(url, timeout=60, headers=None):
    h = {"User-Agent": UA}
    h.update(headers or {})
    with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=timeout) as r:
        return r.status, r.read()
try:
    st, raw = fetch("https://index.commoncrawl.org/collinfo.json", 40)
    colls = json.loads(raw)
except Exception as e:
    print("  liste des index illisible :", e); colls = []
print("  index disponibles :", len(colls), "| les plus récents :", [c.get("id") for c in colls[:4]])
found = []
for c in colls[:4]:
    api = c.get("cdx-api")
    q = api + "?" + urllib.parse.urlencode({"url": "data.gouv.mc/*", "output": "json", "limit": "40"})
    try:
        st, raw = fetch(q, 60)
        rows = [json.loads(l) for l in raw.decode("utf-8", "replace").splitlines() if l.strip().startswith("{")]
    except urllib.error.HTTPError as e:
        print("  ", c.get("id"), ": HTTP", e.code, e.read()[:120]); continue
    except Exception as e:
        print("  ", c.get("id"), ": échec", str(e)[:120]); continue
    print("  ", c.get("id"), ":", len(rows), "capture(s)")
    for r in rows[:12]:
        print("     ", r.get("timestamp"), r.get("status"), r.get("mime"), r.get("url", "")[:110])
    found += [r for r in rows if r.get("status") == "200" and "html" in (r.get("mime") or "")]
    if found:
        break
if found:
    r = sorted(found, key=lambda r: (len(r.get("url", "")), r.get("timestamp")))[0]
    off, ln = int(r["offset"]), int(r["length"])
    try:
        st, raw = fetch("https://data.commoncrawl.org/" + r["filename"], 90, {"Range": "bytes=%d-%d" % (off, off + ln - 1)})
        rec = gzip.GzipFile(fileobj=io.BytesIO(raw)).read().decode("utf-8", "replace")
        s = rec.split("\r\n\r\n", 2)[-1]
        t = re.search(r"<title[^>]*>(.*?)</title>", s, re.S | re.I)
        print("  capture lue :", r["url"], r["timestamp"], "| titre :", html.unescape(t.group(1)).strip()[:200] if t else None)
        body = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
        body = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", body))).strip()
        print("  texte (début) :", body[:900])
        print("  liens évocateurs :", sorted(set(re.findall(r'href="([^"]*(?:licen|condition|mentions|api|explore|dataset|jeux)[^"]*)"', s, re.I)))[:25])
    except Exception as e:
        print("  lecture de la capture impossible :", str(e)[:160])
PY

echo "### B. cartoradio.mc : carte, couches, licence"
g cr.html "https://cartoradio.mc/"
python3 - <<'PY'
import re, html, json
s = open("cr.html", encoding="utf-8", errors="replace").read()
t = re.search(r"<title[^>]*>(.*?)</title>", s, re.S | re.I)
print("  titre :", html.unescape(t.group(1)).strip()[:120] if t else None, "| taille", len(s))
s2 = s.replace("\\/", "/").replace("&quot;", '"')
items = sorted(set(re.findall(r"https://[a-z0-9.-]*gouv\.mc/[A-Za-z0-9/_.-]*?content/items/[0-9a-f]{32}", s2)))
print("  éléments ArcGIS cités dans la page :", items)
print("  hôtes cités :", sorted(set(re.findall(r"https?://([a-z0-9.-]+\.[a-z]{2,})", s2)))[:30])
for w in (r"licen[cs]e", r"mentions? l[eé]gales?", r"conditions? (?:g[eé]n[eé]rales? )?d.utilisation", r"r[eé]utilis", r"open ?data", r"donn[eé]es ouvertes", r"droits? r[eé]serv", r"propri[eé]t[eé] intellectuelle", r"copyright|©"):
    ms = [m.start() for m in re.finditer(w, s2, re.I)]
    print("  motif « %s » : %d" % (w, len(ms)), ("| ex. : " + re.sub(r"\s+", " ", s2[max(0, ms[0] - 70): ms[0] + 110])) if ms else "")
print("  scripts de la page :", re.findall(r'<script[^>]+src="([^"]+)"', s)[:8])
open("items.json", "w").write(json.dumps(items))
PY
python3 - <<'PY'
import json, os, re, urllib.request, urllib.parse, time
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
def jget(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=60) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except Exception as e:
        return {"_erreur": str(e)[:160]}
def ms(v):
    return time.strftime("%Y-%m-%d", time.gmtime(v / 1000)) if isinstance(v, (int, float)) and v > 0 else v
def fiche(url):
    d = jget(url + "?f=json")
    if "_erreur" in d or "error" in d:
        print("     fiche illisible :", str(d)[:200]); return d
    print("     fiche : titre=%r type=%r accès=%r créé=%s modifié=%s" % (d.get("title"), d.get("type"), d.get("access"), ms(d.get("created")), ms(d.get("modified"))))
    print("     licenseInfo=%r | accessInformation=%r | description=%r | snippet=%r | tags=%r" % (d.get("licenseInfo"), d.get("accessInformation"), (d.get("description") or "")[:160], (d.get("snippet") or "")[:160], d.get("tags")))
    return d
items = json.load(open("items.json"))
if not items:
    print("  aucun élément trouvé dans la page : arrêt de la partie B"); raise SystemExit
for it in items[:2]:
    print("  ELEMENT", it)
    d = fiche(it)
    data = jget(it + "/data?f=json")
    layers = data.get("operationalLayers") or []
    print("     couches de la carte :", len(layers), "| fond :", [b.get("title") for b in (data.get("baseMap") or {}).get("baseMapLayers", [])][:4])
    for l in layers:
        url = l.get("url"); iid = l.get("itemId")
        print("   COUCHE", repr(l.get("title")), "|", l.get("layerType"), "|", url)
        if iid:
            fiche(it.rsplit("/", 1)[0] + "/" + iid)
        if not url:
            continue
        lj = jget(url + "?f=json")
        if "_erreur" in lj or "error" in lj:
            print("     service illisible :", str(lj)[:200]); continue
        f = lj.get("fields") or []
        sr = (lj.get("extent") or {}).get("spatialReference") or {}
        print("     couche : name=%r type=%r géométrie=%r capabilities=%r maxRecordCount=%r formats=%r" % (lj.get("name"), lj.get("type"), lj.get("geometryType"), lj.get("capabilities"), lj.get("maxRecordCount"), lj.get("supportedQueryFormats")))
        print("     copyrightText=%r | description=%r | SR=%r | dernière édition=%s | version=%r" % (lj.get("copyrightText"), (lj.get("description") or "")[:120], sr, ms((lj.get("editingInfo") or {}).get("lastEditDate")), lj.get("currentVersion")))
        names = [x.get("name") for x in f]
        print("     champs : %d" % len(names))
        if "Sites" in url:
            for k in range(0, len(names), 14):
                print("     noms :", " ".join(names[k:k + 14]))
            ops = sorted({m.group(1) for n in names for m in [re.match(r"ope_([a-z]+)$", n)] if m})
            print("     groupes « ope_* » :", ops, "| types :", sorted({x.get("type") for x in f}))
        root = jget(url.rsplit("/", 1)[0] + "?f=json")
        print("     service : serviceDescription=%r | copyrightText=%r | capabilities=%r | exports=%r" % ((root.get("serviceDescription") or "")[:120], root.get("copyrightText"), root.get("capabilities"), root.get("supportedExportFormats")))
host = items[0].split("/arcgis/")[0]
p = jget(host + "/arcgis/sharing/rest/portals/self?f=json")
print("  PORTAIL", host, ": name=%r | access=%r | description=%r" % (p.get("name"), p.get("access"), (p.get("description") or "")[:160]))
for k, v in p.items():
    if re.search(r"terms|licen|notice|copyright|banner|legal|disclaimer", k, re.I):
        print("     clé", k, "=", str(v)[:260])
PY

echo "### C. Conditions générales du portail du Gouvernement Princier"
g cgu.html "https://www.gouv.mc/mentions-legales-cgu"
python3 - <<'PY'
import re, html
s = open("cgu.html", encoding="utf-8", errors="replace").read()
t = re.search(r"<title[^>]*>(.*?)</title>", s, re.S | re.I)
print("  titre :", html.unescape(t.group(1)).strip()[:160] if t else None)
b = re.sub(r"<(script|style|svg|noscript|nav|header|footer)\b.*?</\1>", " ", s, flags=re.S | re.I)
b = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
print("  longueur du texte :", len(b))
seen = []
for w in (r"prohib", r"autorisation expresse", r"r[eé]utilis", r"open ?data", r"donn[eé]es ouvertes", r"donn[eé]es publiques", r"licence", r"data\.gouv\.mc", r"exploité par", r"Droit d.auteur"):
    ms = [m.start() for m in re.finditer(w, b, re.I)]
    print("  motif « %s » : %d occurrence(s)" % (w, len(ms)))
    for p in ms[:2]:
        if any(abs(p - q) < 300 for q in seen):
            continue
        seen.append(p)
        print("     «", b[max(0, p - 330): p + 330], "»")
PY

echo "### D. Liste UIT E.212 : édition, Andorre, Monaco"
for y in 2026 2025 2024 2023; do
  r=$(curl -sS -I --connect-timeout 12 -m 40 -A "$UA" -o /dev/null -w "%{http_code} %{content_type}" "https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-E.212B-$y-PDF-E.pdf" 2>&1)
  echo "  édition $y : $r"
done
g itu.pdf "https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-E.212B-2023-PDF-E.pdf"
(apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq poppler-utils) >/dev/null 2>&1
pdftotext -layout itu.pdf itu.txt 2>&1 | head -3
python3 - <<'PY'
import re
try:
    L = open("itu.txt", encoding="utf-8", errors="replace").read().splitlines()
except Exception as e:
    print("  texte du PDF illisible :", e); raise SystemExit
print("  lignes :", len(L))
for l in L[:60]:
    if re.search(r"POSITION ON|Operational Bulletin|E\.212", l, re.I):
        print("  en-tête :", l.strip()[:170])
ent = [(i, l) for i, l in enumerate(L) if re.search(r"\b\d{3} \d{2,3}\s*$", l)]
print("  entrées « MCC MNC » reconnues :", len(ent))
for mcc in ("212", "213"):
    print("  MCC", mcc, ":", [re.sub(r"\s+", " ", l.strip()) for i, l in ent if re.search(r"\b%s \d{2,3}\s*$" % mcc, l)])
for pays in ("Andorra", "Monaco", "Kosovo"):
    for i, l in enumerate(L):
        if l.strip() == pays or re.match(r"^%s\b" % pays, l.strip()) and len(l.strip()) < 40:
            bloc = [re.sub(r"\s+", " ", x.strip()) for x in L[i:i + 7] if x.strip()]
            print("  bloc « %s » (ligne %d) :" % (pays, i + 1), " | ".join(bloc)[:420])
for i, l in enumerate(L):
    if "Monaco" in l and "Country B" in l:
        print("  extraterritorial :", re.sub(r"\s+", " ", l.strip())[:200])
print("  occurrences de « 212 01 » :", sum(1 for l in L if re.search(r"\b212 01\b", l)), "| de « Andorra Telecom » :", sum(1 for l in L if "Andorra Telecom" in l), "| de « Mobiland » :", sum(1 for l in L if "Mobiland" in l))
PY
echo "### fin"
