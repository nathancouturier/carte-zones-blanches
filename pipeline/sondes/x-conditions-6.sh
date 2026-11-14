#!/usr/bin/env bash
# Sonde « conditions » : lit les conditions d'usage publiées par les fournisseurs de fonds et de géocodage.
# Lecture seule, une requête par page. Assemblée par assembler.sh (entete.sh + ext.py + corps-N.sh).
set -u
. "$(dirname "$0")/_lib.sh"
# User-Agent générique : aucun nom de projet ni de personne dans les requêtes vers les services tiers.
UAG="Mozilla/5.0 (compatible; lecture-conditions-usage/1.0)"
D="$T/dl"; O="$T/outils"; mkdir -p "$D" "$O"
page() { # page <fichier> <url> : télécharge (3 essais), affiche code HTTP, taille, type et adresse finale
  local code i
  for i in 1 2 3; do
    code=$(curl -sS -L -m 120 --compressed -A "$UAG" -o "$1" -w "%{http_code} %{size_download}o %{content_type} final=%{url_effective}" "$2" 2>&1) && break
    sleep 3
  done
  echo "  -> $code  $2"
}
entetes() { # entetes <url> : en-têtes de réponse utiles (cache, CORS, limites de débit)
  echo "  $1"
  curl -sS -m 60 -A "$UAG" -H "Origin: https://example.org" -D - -o /dev/null "$1" 2>&1 \
    | tr -d '\r' | grep -i -E "^(HTTP/|cache-control|expires|age:|etag|last-modified|access-control-allow-origin|vary|retry-after|x-cache|via|server:|[a-z-]*rate-?limit[a-z-]*)" \
    | cut -c1-200 | sed 's/^/      /'
}
py() { python3 -I "$O/ext.py" "$@" 2>&1 | cut -c1-420; }
pdf2txt() { # pdf2txt <fichier.pdf> <fichier.txt>
  command -v pdftotext >/dev/null 2>&1 || { apt-get update -qq >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq poppler-utils >/dev/null 2>&1; }
  pdftotext -layout "$1" "$2" 2>&1 | head -2
  echo "  texte extrait : $(wc -c < "$2" 2>/dev/null || echo 0) octets, $(pdfinfo "$1" 2>/dev/null | grep -E '^(Pages|CreationDate|ModDate|Title)' | tr -s ' ' | tr '\n' ';')"
}
cat > "$O/ext.py" <<'EXT_PY'
# Extraction compacte de texte pour les sondes « conditions ».
# usage : ext.py <mode> <fichier> [arguments]
#   info  f                      titre, nombre de paragraphes, nombre de caractères
#   heads f [max]                titres (h1 à h6)
#   links f regex [max] [base]   liens dont l'adresse ou le texte correspond
#   kw    f regex [max] [minlen] paragraphes HTML qui correspondent, avec leur titre de rubrique
#   all   f [max] [debut] [fin] [minlen]  tous les paragraphes HTML, entre deux repères facultatifs
#   kwt / allt                   comme kw / all, pour un fichier texte (PDF converti, RST, Markdown)
#   raw   f regex [span] [max]   contexte brut autour des occurrences (pages rendues en JavaScript)
#   count f                      nombre de caractères de texte ; urls f regex [max] [base] : adresses absolues
import html
import re
import sys
import textwrap
from urllib.parse import urljoin

INLINE = (r"a|b|strong|em|i|span|sup|sub|u|abbr|code|small|mark|font|cite|q|time|label|bdi|bdo|wbr|ins|del|s|kbd|var|"
          r"samp|dfn|nobr")
WIDTH = 230


def lire(path):
    return open(path, encoding="utf-8", errors="replace").read()


def plain(s):
    s = re.sub(r"<!--.*?-->", " ", s, flags=re.S)
    s = re.sub(r"<(script|style|svg|noscript|template|head)\b.*?</\1\s*>", " ", s, flags=re.S | re.I)
    s = re.sub(r"<h([1-6])\b[^>]*>", lambda m: "\n" + "#" * int(m.group(1)) + " ", s, flags=re.I)
    s = re.sub(r"<(br|hr)\b[^>]*>", "\n", s, flags=re.I)
    s = re.sub(r"</?(?:%s)\b[^>]*>" % INLINE, "", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "\n", s)
    s = html.unescape(s).replace("\xa0", " ").replace("​", "").replace("­", "")
    out = []
    for p in s.split("\n"):
        p = re.sub(r"\s+", " ", p).strip()
        if p and p.strip("#").strip():
            out.append(p)
    return out


def txtparas(t):
    under = re.compile(r"\s*([=\-~^\"'*+#_.])\1{2,}\s*")
    out = []
    for blk in re.split(r"\n[ \t]*\n", t.replace("\r", "").replace("\x0c", "\n\n")):
        ls = [l for l in blk.split("\n") if l.strip()]
        cur = []
        i = 0
        while i < len(ls):
            if i + 1 < len(ls) and under.fullmatch(ls[i + 1]) and not under.fullmatch(ls[i]):
                if cur:
                    out.append(re.sub(r"\s+", " ", " ".join(cur)).strip())
                    cur = []
                out.append("## " + ls[i].strip())
                i += 2
                continue
            if under.fullmatch(ls[i]):
                i += 1
                continue
            m = re.match(r"\s*(#{1,6})\s+(.*)", ls[i])
            if m:
                if cur:
                    out.append(re.sub(r"\s+", " ", " ".join(cur)).strip())
                    cur = []
                out.append(m.group(1) + " " + m.group(2).strip())
                i += 1
                continue
            cur.append(ls[i].strip())
            i += 1
        if cur:
            out.append(re.sub(r"\s+", " ", " ".join(cur)).strip())
    return [p for p in out if p]


def emit(paras, rx, maxlines, minlen, start=None, stop=None):
    head = ""
    last_head = None
    n = 0
    skipped = 0
    seen = set()
    active = start is None
    for p in paras:
        is_head = p.startswith("#")
        if is_head:
            head = p
        if not active:
            if start.search(p):
                active = True
            else:
                continue
        elif stop is not None and stop.search(p):
            break
        if rx is not None and not rx.search(p):
            continue
        if not is_head and len(p) < minlen:
            continue
        if p in seen:
            continue
        seen.add(p)
        lines = textwrap.wrap(p, WIDTH, break_long_words=False, break_on_hyphens=False) or [p]
        extra = 1 if (rx is not None and not is_head and head and head != last_head) else 0
        if n + len(lines) + extra > maxlines:
            skipped += 1
            continue
        if extra:
            print("  § " + head[:150])
            last_head = head
            n += 1
        if is_head:
            last_head = p
        for k, line in enumerate(lines):
            print(("  | " if k == 0 else "  |   ") + line)
        n += len(lines)
    if skipped:
        print(f"  [... {skipped} paragraphe(s) non affiché(s) : limite de {maxlines} lignes]")
    if n == 0:
        print("  (rien)")


def main():
    mode, path = sys.argv[1], sys.argv[2]
    a = sys.argv[3:]
    try:
        raw = lire(path)
    except OSError as e:
        print("  (fichier illisible : %s)" % e)
        return
    if mode == "count":
        print(sum(len(p) for p in plain(raw)))
        return
    if mode == "urls":
        rx = re.compile(a[0], re.I)
        mx = int(a[1]) if len(a) > 1 else 3
        base = a[2] if len(a) > 2 else ""
        out = []
        for m in re.finditer(r"<a\b([^>]*)>(.*?)</a\s*>", raw, flags=re.S | re.I):
            h = re.search(r"href\s*=\s*[\"']([^\"']*)[\"']", m.group(1), flags=re.I)
            if not h:
                continue
            href = html.unescape(h.group(1)).strip()
            text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", m.group(2)))).strip()
            if not (rx.search(href) or rx.search(text)):
                continue
            href = (urljoin(base, href) if base else href).replace(" ", "%20")
            if href.startswith("http") and href not in out:
                out.append(href)
        print("\n".join(out[:mx]))
        return
    if mode == "info":
        t = re.search(r"<title[^>]*>(.*?)</title>", raw, flags=re.S | re.I)
        paras = plain(raw)
        print("  titre=%r | %d paragraphes | %d caractères de texte | %d octets" % (
            html.unescape(re.sub(r"\s+", " ", t.group(1)).strip()) if t else None, len(paras),
            sum(len(p) for p in paras), len(raw.encode("utf-8", "replace"))))
    elif mode == "heads":
        mx = int(a[0]) if a else 50
        hs = [p for p in plain(raw) if p.startswith("#")]
        for h in hs[:mx]:
            print("  " + h[:160])
        if len(hs) > mx:
            print(f"  [... {len(hs) - mx} titre(s) de plus]")
        if not hs:
            print("  (aucun titre)")
    elif mode == "links":
        rx = re.compile(a[0], re.I)
        mx = int(a[1]) if len(a) > 1 else 30
        base = a[2] if len(a) > 2 else ""
        seen = []
        for m in re.finditer(r"<a\b([^>]*)>(.*?)</a\s*>", raw, flags=re.S | re.I):
            h = re.search(r"href\s*=\s*[\"']([^\"']*)[\"']", m.group(1), flags=re.I)
            if not h:
                continue
            href = html.unescape(h.group(1)).strip()
            text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", m.group(2)))).strip()
            if not (rx.search(href) or rx.search(text)):
                continue
            if base:
                href = urljoin(base, href)
            if href in [x[0] for x in seen]:
                continue
            seen.append((href, text))
        for href, text in seen[:mx]:
            print("  - %s -> %s" % (text[:90], href[:230]))
        if len(seen) > mx:
            print(f"  [... {len(seen) - mx} lien(s) de plus]")
        if not seen:
            print("  (aucun lien)")
    elif mode in ("kw", "kwt"):
        rx = re.compile(a[0], re.I)
        mx = int(a[1]) if len(a) > 1 else 60
        minlen = int(a[2]) if len(a) > 2 else 40
        emit(plain(raw) if mode == "kw" else txtparas(raw), rx, mx, minlen)
    elif mode in ("all", "allt"):
        mx = int(a[0]) if a else 80
        start = re.compile(a[1], re.I) if len(a) > 1 and a[1] else None
        stop = re.compile(a[2], re.I) if len(a) > 2 and a[2] else None
        minlen = int(a[3]) if len(a) > 3 else 0
        emit(plain(raw) if mode == "all" else txtparas(raw), None, mx, minlen, start, stop)
    elif mode == "raw":
        rx = re.compile(a[0], re.I)
        span = int(a[1]) if len(a) > 1 else 300
        mx = int(a[2]) if len(a) > 2 else 8
        s = re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), raw)
        s = s.replace("\\n", " ").replace('\\"', '"').replace("\\/", "/")
        s = html.unescape(re.sub(r"<[^>]+>", " ", s))
        s = re.sub(r"\s+", " ", s)
        n = 0
        last = -10 ** 9
        total = 0
        for m in rx.finditer(s):
            total += 1
            if m.start() < last + span:
                continue
            last = m.start()
            if n >= mx:
                continue
            n += 1
            ctx = s[max(0, m.start() - span): m.end() + span]
            for k, line in enumerate(textwrap.wrap(ctx, WIDTH, break_long_words=False, break_on_hyphens=False)):
                print(("  ~ " if k == 0 else "  ~   ") + line)
        print(f"  ({total} occurrence(s), {n} contexte(s) affiché(s))")
    else:
        sys.exit("mode inconnu : " + mode)


if __name__ == "__main__":
    main()
EXT_PY
echo "date de la sonde : $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- conditions-6 : compléments : tableau des limites geo.admin.ch, mentions swisstopo, OpenTopoMap (encodage,
# ---- serveur de secours), résumé de la politique des tuiles OSM, en-têtes des tuiles ----
U="https://www.geo.admin.ch/en/general-terms-of-use-fsdi"
echo "##### 1. $U : tableau du point 2.3 (code HTML allégé)"
page "$D/fsdi.html" "$U"
python3 -I - "$D/fsdi.html" <<'PY' 2>&1 | cut -c1-1200
import html, re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
s = re.sub(r"<(script|style|svg)\b.*?</\1\s*>", " ", s, flags=re.S | re.I)
a = s.find("A maximum number of requests")
b = s.find("Obligations on data use", a) if a >= 0 else -1
print("  repère trouvé : %s ; <table : %d ; <img : %d" % (a >= 0, len(re.findall(r"<table", s, re.I)), len(re.findall(r"<img", s, re.I))))
if a >= 0:
    seg = s[a: b if b > a else a + 9000]
    def keep(m):
        tag = m.group(0)
        name = re.match(r"</?\s*([a-zA-Z0-9]+)", tag)
        name = name.group(1).lower() if name else ""
        if name in ("table", "tr", "td", "th", "thead", "tbody", "ul", "ol", "li", "p", "h1", "h2", "h3", "h4", "figure", "figcaption"):
            return "<" + ("/" if tag.startswith("</") else "") + name + ">"
        if name in ("img", "a", "iframe", "object", "embed"):
            attrs = " ".join(re.findall(r"(?:src|alt|href|title)\s*=\s*\"[^\"]*\"", tag))
            return "<%s %s>" % (name, attrs)
        return ""
    seg = html.unescape(re.sub(r"<[^>]+>", keep, seg))
    seg = re.sub(r"\s+", " ", seg)
    for k in range(0, min(len(seg), 3600), 1150):
        print("  ~ " + seg[k:k + 1150])
PY
echo "--- lignes de tableau en texte"
python3 -I - "$D/fsdi.html" <<'PY' 2>&1 | cut -c1-300 | head -24
import html, re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for tb in re.findall(r"<table\b.*?</table\s*>", s, flags=re.S | re.I):
    for tr in re.findall(r"<tr\b.*?</tr\s*>", tb, flags=re.S | re.I):
        cells = [re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", c))).strip() for c in re.findall(r"<t[dh]\b[^>]*>(.*?)</t[dh]\s*>", tr, flags=re.S | re.I)]
        print("  | " + " | ".join(cells))
    print("  ----")
PY

U="https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices"
echo "##### 2. $U : point 2 complet"
page "$D/swt.html" "$U"
py all "$D/swt.html" 22 '^## 2\. Terms of use' '^## 3\.'

echo "##### 3. WMTS swisstopo : identification du service, couche pixelkarte-farbe"
page "$D/ch.xml" "https://wmts.geo.admin.ch/EPSG/3857/1.0.0/WMTSCapabilities.xml"
python3 -I - "$D/ch.xml" "$D/ch-meta.txt" <<'PY' 2>&1 | cut -c1-700
import re, sys
import xml.etree.ElementTree as ET
ns = {"w": "http://www.opengis.net/wmts/1.0", "o": "http://www.opengis.net/ows/1.1"}
XL = "{http://www.w3.org/1999/xlink}href"
open(sys.argv[2], "w").close()
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception as e:
    print("  XML illisible :", e); sys.exit()
def t(el, path):
    v = el.findtext(path, namespaces=ns) if el is not None else None
    return re.sub(r"\s+", " ", v).strip() if v else None
si = root.find("o:ServiceIdentification", ns)
for tag in ("Title", "Abstract", "Fees", "AccessConstraints"):
    print("  %s = %r" % (tag, t(si, "o:" + tag)))
sp = root.find("o:ServiceProvider", ns)
print("  ProviderName = %r" % t(sp, "o:ProviderName"))
for l in root.findall(".//w:Layer", ns):
    if t(l, "o:Identifier") != "ch.swisstopo.pixelkarte-farbe":
        continue
    hrefs = [m.get(XL) for m in l.findall("o:Metadata", ns) if m.get(XL)]
    print("  couche : Title=%r | Abstract=%r" % (t(l, "o:Title"), (t(l, "o:Abstract") or "")[:300]))
    print("      métadonnées : %s" % hrefs[:3])
    urls = hrefs[:1]
    m = re.search(r"(?:uuid=|/metadata/|/records/)([0-9a-fA-F]{8}-[0-9a-fA-F-]{27})", hrefs[0]) if hrefs else None
    if m:
        urls.append("https://www.geocat.ch/geonetwork/srv/api/records/%s/formatters/xml" % m.group(1))
    open(sys.argv[2], "w").write("\n".join(urls))
PY
k=0
while IFS= read -r u; do
  [ -n "$u" ] || continue
  k=$((k + 1))
  echo "--- fiche de métadonnées de la couche ($k)"
  page "$D/ch-meta$k.txt" "$u"
  py raw "$D/ch-meta$k.txt" 'otherConstraints|useLimitation|legal (restriction|constraint)|nutzungsbedingung|terms of use|©|opendata|open government' 220 4
done < "$D/ch-meta.txt"

echo "##### 4. Documentation de l'API geo.admin.ch"
for u in "https://api3.geo.admin.ch/api/faq/index.html" "https://api3.geo.admin.ch/services/sdiservices.html" "https://docs.geo.admin.ch/"; do
  f="$D/doc-$(echo "$u" | tr -c 'a-zA-Z0-9' '_' | cut -c1-60).html"
  page "$f" "$u"
  py info "$f"
  py kw "$f" 'fair use|request limit|offline|bulk|cach|terms of use|attribution|copyright|©|free of charge|registration|referer' 12 30
done

echo "##### 5. En-têtes des tuiles (une requête par fournisseur)"
entetes "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-farbe/default/current/3857/12/2133/1451.jpeg"
entetes "https://www.ign.es/wmts/mapa-raster?service=WMTS&request=GetTile&version=1.0.0&layer=MTN&style=default&tilematrixset=GoogleMapsCompatible&format=image/jpeg&TileMatrix=12&TileCol=2058&TileRow=1508"
entetes "https://a.tile.opentopomap.org/12/2136/1470.png"

echo "##### 6. OpenTopoMap : page about avec le bon encodage"
page "$D/otm.html" "https://opentopomap.org/about"
python3 -I - "$D/otm.html" "$D/otm8.html" <<'PY'
import re, sys
b = open(sys.argv[1], "rb").read()
meta = re.findall(rb"<meta[^>]*charset[^>]*>", b, flags=re.I)
print("  balises meta charset :", [m.decode("ascii", "replace") for m in meta][:2])
try:
    s = b.decode("utf-8"); enc = "utf-8"
except UnicodeDecodeError:
    s = b.decode("cp1252", "replace"); enc = "cp1252 (iso-8859-1)"
print("  encodage retenu :", enc)
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY
echo "--- Roadmap"
py all "$D/otm8.html" 8 '^# Roadmap' '^# Legende'
echo "--- Verwendung"
py all "$D/otm8.html" 12 '^# Verwendung' '^# Details'
echo "--- Details"
py all "$D/otm8.html" 14 '^# Details' '^# H.ufig'
echo "--- Häufig gestellte Fragen"
py all "$D/otm8.html" 44 '^# H.ufig gestellte' '^# Datenstand'
echo "--- Datenstand"
py all "$D/otm8.html" 8 '^# Datenstand' '^# Mitwirkende'

echo "##### 7. OpenTopoMap : adresse du serveur de secours (page d'accueil et ses scripts)"
page "$D/otm-home.html" "https://opentopomap.org/"
python3 -I - "$D/otm-home.html" "$D/otm-scripts.txt" <<'PY' 2>&1 | cut -c1-500
import re, sys
from urllib.parse import urljoin
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
srcs = [urljoin("https://opentopomap.org/", x) for x in re.findall(r"<script[^>]*\bsrc\s*=\s*[\"']([^\"']+)[\"']", s, flags=re.I)]
print("  scripts :", srcs[:12])
own = [u for u in srcs if re.match(r"https?://(www\.)?opentopomap\.org/", u)]
open(sys.argv[2], "w").write("\n".join(own[:5]))
def scan(name, txt):
    seen = []
    for m in re.finditer(r"(?:https?:)?//[^\"'\s<>]*\{z\}[^\"'\s<>]*", txt):
        if m.group(0) not in seen:
            seen.append(m.group(0))
    for u in seen[:12]:
        print("  [%s] gabarit de tuiles : %s" % (name, u))
    last = -10 ** 9; n = 0
    for m in re.finditer(r"backup", txt, flags=re.I):
        if m.start() < last + 300 or n >= 4:
            continue
        last = m.start(); n += 1
        print("  [%s] ~ %s" % (name, re.sub(r"\s+", " ", txt[max(0, m.start() - 220): m.end() + 260])))
    if not seen and n == 0:
        print("  [%s] ni gabarit de tuiles ni « backup »" % name)
scan("accueil", s)
PY
while IFS= read -r u; do
  [ -n "$u" ] || continue
  f="$D/otm-js-$(basename "$u" | tr -c 'a-zA-Z0-9.' '_' | cut -c1-40)"
  page "$f" "$u"
  python3 -I - "$f" "$(basename "$u")" <<'PY' 2>&1 | cut -c1-520 | head -14
import re, sys
txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
name = sys.argv[2][:30]
seen = []
for m in re.finditer(r"(?:https?:)?//[^\"'\s<>]*\{z\}[^\"'\s<>]*", txt):
    if m.group(0) not in seen:
        seen.append(m.group(0))
for u in seen[:8]:
    print("  [%s] gabarit de tuiles : %s" % (name, u))
last = -10 ** 9; n = 0
for m in re.finditer(r"backup", txt, flags=re.I):
    if m.start() < last + 300 or n >= 4:
        continue
    last = m.start(); n += 1
    print("  [%s] ~ %s" % (name, re.sub(r"\s+", " ", txt[max(0, m.start() - 220): m.end() + 260])))
if not seen and n == 0:
    print("  [%s] ni gabarit de tuiles ni « backup »" % name)
PY
done < "$D/otm-scripts.txt"

echo "##### 8. Politique des tuiles OSM : résumé avec les intitulés des listes ; fin de la rubrique 9"
page "$D/osm.html" "https://operations.osmfoundation.org/policies/tiles/"
py all "$D/osm.html" 26 '^## Quick summary' '^## 1\. Correct'
py all "$D/osm.html" 14 '^## 9\. Alternatives' ''
python3 -I - "$D/osm.html" <<'PY' 2>&1 | cut -c1-300
import re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for m in re.finditer(r"(last (updated|modified|revised)|updated on|effective)[^<]{0,80}", s, flags=re.I):
    print("  date ? ~ " + re.sub(r"\s+", " ", m.group(0)))
PY

echo "##### 9. Attribution OSM pour le géocodage ; licence du logiciel Photon"
page "$D/attr.html" "https://osmfoundation.org/wiki/Licence/Attribution_Guidelines"
py kw "$D/attr.html" 'geocod|search result|ODbL|Open Database Licen[cs]e' 10 30
page "$D/photon.md" "https://raw.githubusercontent.com/komoot/photon/master/README.md"
py kwt "$D/photon.md" 'licen[cs]e|apache|ODbL|attribution' 6 10
