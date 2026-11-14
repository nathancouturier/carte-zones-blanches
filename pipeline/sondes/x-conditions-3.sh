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

# ---- conditions-3 : IGN España (WMTS mapa-raster, licence), Photon, Nominatim ----
KW_ES='CC.?BY|licencia|menci[óo]n|atribuci|origen|propiedad|gratuit|libre|servicios? web|WMTS|visualizaci|masiv|l[íi]mite|peticiones|cach[ée]|sin conexi|offline|condiciones de uso|autor[ií]a|©|copyright|comercial|obra derivada|reutiliza'

echo "##### 1. IGN España : GetCapabilities du WMTS mapa-raster"
page "$D/es.xml" "https://www.ign.es/wmts/mapa-raster?request=GetCapabilities&service=WMTS"
python3 -I - "$D/es.xml" "$D/es-meta.txt" <<'PY' 2>&1 | cut -c1-700
import re, sys
import xml.etree.ElementTree as ET
ns = {"w": "http://www.opengis.net/wmts/1.0", "o": "http://www.opengis.net/ows/1.1"}
XL = "{http://www.w3.org/1999/xlink}href"
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception as e:
    print("  XML illisible :", e); open(sys.argv[2], "w").close(); sys.exit()
def t(el, path):
    v = el.findtext(path, namespaces=ns) if el is not None else None
    return re.sub(r"\s+", " ", v).strip() if v else None
si = root.find("o:ServiceIdentification", ns)
for tag in ("Title", "Abstract", "ServiceType", "ServiceTypeVersion", "Fees", "AccessConstraints"):
    print("  %s = %r" % (tag, t(si, "o:" + tag)))
sp = root.find("o:ServiceProvider", ns)
site = sp.find("o:ProviderSite", ns) if sp is not None else None
print("  ProviderName = %r | ProviderSite = %r" % (t(sp, "o:ProviderName"), site.get(XL) if site is not None else None))
metas = []
for l in root.findall(".//w:Layer", ns):
    ident = t(l, "o:Identifier")
    if ident != "MTN":
        continue
    print("  Layer MTN : Title = %r" % t(l, "o:Title"))
    print("  Layer MTN : Abstract = %r" % t(l, "o:Abstract"))
    for m in l.findall("o:Metadata", ns):
        if m.get(XL):
            metas.append(m.get(XL))
for el in root.iter():
    h = el.get(XL)
    if h and re.search(r"csw|catalog|metad|records", h, re.I) and h not in metas:
        metas.append(h)
print("  liens de métadonnées :", metas[:6])
open(sys.argv[2], "w").write("\n".join(m for m in metas[:2] if m))
PY
k=0
while IFS= read -r u; do
  [ -n "$u" ] || continue
  k=$((k + 1))
  echo "--- métadonnées $k"
  page "$D/es-meta$k.xml" "$u"
  py raw "$D/es-meta$k.xml" 'useLimitation|otherConstraints|limitaci|condiciones|CC.?BY|licencia|gratuit' 260 6
done < "$D/es-meta.txt"

U="https://www.ign.es/web/politica-datos"
echo "##### 2. $U"
page "$D/pol.html" "$U"
py info "$D/pol.html"
py heads "$D/pol.html" 14
py kw "$D/pol.html" "$KW_ES" 40 40
py links "$D/pol.html" '\.pdf|licen|condicion|orden|BOE' 12 "$U"

U="https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf"
echo "##### 3. $U"
page "$D/lic.pdf" "$U"
pdf2txt "$D/lic.pdf" "$D/lic.txt"
py allt "$D/lic.txt" 70

U="https://photon.komoot.io/"
echo "##### 4. $U"
page "$D/photon.html" "$U"
py info "$D/photon.html"
py all "$D/photon.html" 34 '' '' 25
py links "$D/photon.html" 'licen|terms|github|openstreetmap|komoot|imprint|privacy|datenschutz' 12 "$U"
echo "--- README du dépôt komoot/photon"
page "$D/photon.md" "https://raw.githubusercontent.com/komoot/photon/master/README.md"
py kwt "$D/photon.md" 'fair|throttl|guarantee|licen|attribution|ODbL|komoot\.io|public|demo server|rate|limit|usage' 18 20
echo "--- en-têtes d'une réponse de l'API"
entetes "https://photon.komoot.io/api/?q=zermatt&limit=1"

U="https://operations.osmfoundation.org/policies/nominatim/"
echo "##### 5. $U"
page "$D/nominatim.html" "$U"
py info "$D/nominatim.html"
py heads "$D/nominatim.html" 14
py kw "$D/nominatim.html" 'auto-?complet|per second|requests?|attribution|bulk|cach|user-agent|referer|heavy|licen|ODbL|copyright|unacceptable|withdraw|block' 36 30
