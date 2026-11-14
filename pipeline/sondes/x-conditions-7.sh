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

# ---- conditions-7 : derniers compléments (limite d'usage Géoplateforme, licences des couches, tableau geo.admin.ch,
# ---- fiche geocat, mention et serveur de secours OpenTopoMap, géocodage OSM, IGN España) ----
xmlc() { # xmlc <fichier.xml> : éléments de contraintes et de licence d'une fiche de métadonnées ISO
  python3 -I - "$1" <<'PY' 2>&1 | cut -c1-520 | head -14
import re, sys
import xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception as e:
    print("  XML illisible :", e); sys.exit()
rx = re.compile(r"useLimitation|otherConstraints|accessConstraints|useConstraints|legalConstraints|licen[cs]e|reference$", re.I)
seen = []
for el in root.iter():
    name = el.tag.split("}")[-1]
    if not re.search(r"useLimitation|otherConstraints|accessConstraints|useConstraints|licen[cs]e", name, re.I):
        continue
    txt = re.sub(r"\s+", " ", " ".join(el.itertext())).strip()
    code = " ".join("%s=%s" % (k.split("}")[-1], v) for c in el.iter() for k, v in c.attrib.items() if "codeListValue" in k or "href" in k)
    line = "  <%s> %s %s" % (name, txt[:380], ("[" + code[:200] + "]") if code else "")
    if line not in seen:
        seen.append(line)
        print(line)
if not seen:
    print("  (aucun élément de contrainte ou de licence)")
PY
}

U="https://cartes.gouv.fr/cgu/"
echo "##### 1. $U : annexe 3, article 3.2 et suivants"
page "$D/cgu.html" "$U"
py all "$D/cgu.html" 40 '^#+ Article 3\.2' ''

U="https://cartes.gouv.fr/aide/fr/niveau-de-service/"
echo "##### 2. $U"
page "$D/sla.html" "$U"
py info "$D/sla.html"
py heads "$D/sla.html" 10
py kw "$D/sla.html" 'limit|requ[êe]tes|par seconde|fair|quota|cache|hors[ -]ligne|bloqu|abus|WMTS|TMS|tuile|autocompl|g[ée]ocod' 26 0
echo "--- aide : pages sur le cache, les limites, les mentions"
page "$D/aide.html" "https://cartes.gouv.fr/aide/fr/"
py links "$D/aide.html" 'cache|hors.?ligne|limite|quota|condition|licence|mention|cr[ée]dit|attribution|copyright|r[ée]utilis' 8 "https://cartes.gouv.fr/aide/fr/"

echo "##### 3. Fiches de métadonnées des couches IGN (CSW de la Géoplateforme)"
for id in IGNF_PLAN-IGN IGNF_BD-ORTHO; do
  page "$D/csw-$id.xml" "https://data.geopf.fr/csw?REQUEST=GetRecordById&SERVICE=CSW&VERSION=2.0.2&OUTPUTSCHEMA=http://standards.iso.org/iso/19115/-3/mdb/2.0&elementSetName=full&ID=$id"
  xmlc "$D/csw-$id.xml"
done

echo "##### 4. En-têtes complets : tuile vectorielle TMS, autocomplétion"
for u in "https://data.geopf.fr/tms/1.0.0/PLAN.IGN/12/2114/1470.pbf" "https://data.geopf.fr/geocodage/completion?text=lautaret&type=PositionOfInterest&maximumResponses=1"; do
  echo "  $u"
  curl -sS -m 60 -A "$UAG" -H "Origin: https://example.org" -D - -o /dev/null "$u" 2>&1 | tr -d '\r' | grep -v -i -E '^(set-cookie|content-security|strict-transport|x-frame|x-content-type|x-xss|referrer-policy|permissions-policy|$)' | cut -c1-170 | head -24 | sed 's/^/      /'
done

U="https://www.geo.admin.ch/en/general-terms-of-use-fsdi"
echo "##### 5. geo.admin.ch : où est le tableau des limites ?"
page "$D/fsdi.html" "$U"
python3 -I - "$D/fsdi.html" "$D/fsdi-de.txt" <<'PY' 2>&1 | cut -c1-600
import html, re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for m in re.finditer(r"<img\b[^>]*>", s, flags=re.I):
    print("  img :", " ".join(re.findall(r"(?:src|alt|title)\s*=\s*\"[^\"]*\"", m.group(0)))[:300])
alts = re.findall(r"<link\b[^>]*hreflang\s*=\s*\"([a-zA-Z-]+)\"[^>]*href\s*=\s*\"([^\"]+)\"", s, flags=re.I)
alts += [(b, a) for a, b in re.findall(r"<link\b[^>]*href\s*=\s*\"([^\"]+)\"[^>]*hreflang\s*=\s*\"([a-zA-Z-]+)\"", s, flags=re.I)]
print("  versions linguistiques :", sorted(set(alts))[:8])
de = [u for l, u in alts if l.lower().startswith("de")]
open(sys.argv[2], "w").write((de[0] if de else "") + "\n")
txt = re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), s)
txt = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", txt)))
n = 0
for m in re.finditer(r"(requests?|Anfragen) ?(/|per|pro) ?(second|minute|min|s\b|Sekunde|Minute)|\d[\d' ,.]* ?(requests|Anfragen)", txt, flags=re.I):
    n += 1
    if n <= 6:
        print("  ~ " + txt[max(0, m.start() - 160): m.end() + 200])
print("  occurrences chiffrées dans le code de la page : %d" % n)
PY
DE=$(head -1 "$D/fsdi-de.txt")
if [ -n "$DE" ]; then
  case "$DE" in /*) DE="https://www.geo.admin.ch$DE" ;; esac
  page "$D/fsdi-de.html" "$DE"
  py kw "$D/fsdi-de.html" 'Anfragen|pro (Sekunde|Minute|Tag)|Limite|Fair Use|Tabelle|Offline|Download' 16 0
  python3 -I - "$D/fsdi-de.html" <<'PY' 2>&1 | cut -c1-300 | head -16
import html, re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
tables = re.findall(r"<table\b.*?</table\s*>", s, flags=re.S | re.I)
print("  tableaux dans la version allemande : %d" % len(tables))
for tb in tables:
    for tr in re.findall(r"<tr\b.*?</tr\s*>", tb, flags=re.S | re.I):
        cells = [re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", c))).strip() for c in re.findall(r"<t[dh]\b[^>]*>(.*?)</t[dh]\s*>", tr, flags=re.S | re.I)]
        print("  | " + " | ".join(cells))
PY
fi

echo "##### 6. Fiche geocat de la couche ch.swisstopo.pixelkarte-farbe"
page "$D/geocat.xml" "https://www.geocat.ch/geonetwork/srv/api/records/f9c31be1-887c-4203-8b11-57b40ecc039b/formatters/xml"
xmlc "$D/geocat.xml"

echo "##### 7. docs.geo.admin.ch : pages sur les conditions et le WMTS"
page "$D/docs.html" "https://docs.geo.admin.ch/"
py links "$D/docs.html" 'wmts|terms|fair|faq|usage|limit|condition|visual|licen|about' 12 "https://docs.geo.admin.ch/"
k=0
while IFS= read -r u || [ -n "$u" ]; do
  [ -n "$u" ] || continue
  k=$((k + 1))
  page "$D/docs$k.html" "$u"
  py kw "$D/docs$k.html" 'fair use|request limit|requests per|offline|bulk|cach|terms of use|attribution|copyright|©|free of charge|referer' 10 30
done < <(python3 -I "$O/ext.py" urls "$D/docs.html" 'wmts|terms|fair|faq' 3 "https://docs.geo.admin.ch/")

echo "##### 8. OpenTopoMap : mentions et couches définies dans la page d'accueil ; serveur de secours"
page "$D/otm-home.html" "https://opentopomap.org/"
python3 -I - "$D/otm-home.html" <<'PY' 2>&1 | cut -c1-760
import re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for m in re.finditer(r"var\s+(topoAttribution\d*)\s*=\s*'(.*?)';", s, flags=re.S):
    print("  %s = %s" % (m.group(1), re.sub(r"\s+", " ", m.group(2))))
for m in re.finditer(r"var\s+(topo\w*)\s*=\s*new\s+L\.TileLayer\((.*?)\);", s, flags=re.S):
    print("  %s = new L.TileLayer(%s)" % (m.group(1), re.sub(r"\s+", " ", m.group(2))))
PY
entetes "https://backup.opentopomap.org/12/2136/1470.png"

echo "##### 9. Attribution OSM : rubrique « Geocoding (search) » ; politique des tuiles vectorielles OSM"
page "$D/attr.html" "https://osmfoundation.org/wiki/Licence/Attribution_Guidelines"
py all "$D/attr.html" 10 '^#+ Geocoding' '^#+ (Machine|Other|Books|Artistic|Data|Routing|Changes|Translations)'
page "$D/vector.html" "https://operations.osmfoundation.org/policies/vector/"
py info "$D/vector.html"
py kw "$D/vector.html" 'offline|prefetch|bulk|scrap|cach|attribution|heavy|user-agent|referer|must' 14 25

echo "##### 10. IGN España : page des services web, table des produits (formule de mention)"
U="https://www.ign.es/web/ign/portal/ide-area-nodo-ide-ign"
page "$D/es-serv.html" "$U"
py info "$D/es-serv.html"
py kw "$D/es-serv.html" 'masiv|uso responsable|l[íi]mite|peticiones|rendimiento|bloque|condiciones|licencia|gratuit|CC.?BY|cach[ée]' 10 30
U="http://www.scne.es/productos.html"
page "$D/scne.html" "$U"
py info "$D/scne.html"
py kw "$D/scne.html" 'MTN|Mapa Topogr|r[áa]ster|ign\.es|atribuci|identificador' 12 0
