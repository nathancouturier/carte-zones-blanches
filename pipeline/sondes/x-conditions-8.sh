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
# EXT_DOUBLONS=1 : ne pas supprimer les paragraphes répétés (cellules de tableau identiques)
import html
import os
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
        if p in seen and os.environ.get("EXT_DOUBLONS") != "1":
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

# ---- conditions-8 : dernière sonde : tableau complet des limites (Géoplateforme, geo.admin.ch), guide « limites
# ---- d'usage », absence ou présence des mots cache / hors ligne dans les CGU, WMTS geo.admin.ch, IDEE ----
U="https://cartes.gouv.fr/cgu/"
echo "##### 1. $U : tableau de l'article 3.2 sans suppression des répétitions, puis la suite"
page "$D/cgu.html" "$U"
EXT_DOUBLONS=1 py all "$D/cgu.html" 62 '^#+ Article 3\.2' ''
echo "--- les CGU parlent-elles de cache, de hors ligne, de copie, de robots ?"
python3 -I - "$D/cgu.html" <<'PY' 2>&1 | cut -c1-400
import html, re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
s = re.sub(r"<(script|style|svg)\b.*?</\1\s*>", " ", s, flags=re.S | re.I)
t = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s)))
for w in ("cache", "hors ligne", "hors-ligne", "hors connexion", "aspir", "en masse", "massi", "moisson", "robot", "automatis", "stock", "copie", "reprodu", "extraction", "téléchargement", "mention", "paternité", "gratuit"):
    hits = [m.start() for m in re.finditer(re.escape(w), t, flags=re.I)]
    print("  %-16s %2d occurrence(s)%s" % (w, len(hits), (" : ..." + t[max(0, hits[0] - 90): hits[0] + 130] + "...") if hits and w not in ("gratuit", "mention", "téléchargement") else ""))
PY

U="https://cartes.gouv.fr/aide/fr/guides-utilisateur/utiliser-les-services-de-la-geoplateforme/limites-d-usage/"
echo "##### 2. $U"
page "$D/limites.html" "$U"
py info "$D/limites.html"
EXT_DOUBLONS=1 py all "$D/limites.html" 44 '^# ' '^## (Inscrivez|Communaut|Nos partenaires)' 0
py links "$D/limites.html" 'cache|hors|limite|quota|condition|licence|mention|t[ée]l[ée]charg|diffusion|tuil' 10 "$U"

U="https://www.geo.admin.ch/en/general-terms-of-use-fsdi"
echo "##### 3. $U : tableau des limites (données incluses dans la page)"
page "$D/fsdi.html" "$U"
python3 -I - "$D/fsdi.html" <<'PY' 2>&1 | cut -c1-330 | head -64
import json, re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"<script[^>]*id=\"__NUXT_DATA__\"[^>]*>(.*?)</script>", s, flags=re.S)
items = None
if m:
    try:
        items = json.loads(m.group(1))
    except Exception as e:
        print("  données incluses illisibles :", e)
if not isinstance(items, list):
    print("  pas de bloc __NUXT_DATA__ exploitable ; scripts JSON :", re.findall(r"<script[^>]*type=\"application/json\"[^>]*>", s)[:3])
    sys.exit()
strs = [(i, x) for i, x in enumerate(items) if isinstance(x, str)]
idx = [k for k, (i, x) in enumerate(strs) if re.search(r"requests? / (year|minute)", x)]
print("  %d éléments, %d chaînes, %d cellules chiffrées" % (len(items), len(strs), len(idx)))
if idx:
    a, b = max(0, idx[0] - 14), min(len(strs), idx[-1] + 8)
    for i, x in strs[a:b]:
        x = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", x)).strip()
        if len(x) < 3 or re.fullmatch(r"[a-zA-Z]+", x) and len(x) < 14 and x[0].islower():
            continue
        print("  [%d] %s" % (i, x[:300]))
PY

echo "##### 4. docs.geo.admin.ch : page WMTS (voisine de la page WMS trouvée)"
U="https://docs.geo.admin.ch/visualize-data/wmts.html"
page "$D/wmts-doc.html" "$U"
py info "$D/wmts-doc.html"
py kw "$D/wmts-doc.html" 'fair use|request limit|requests per|offline|bulk|cach|terms of use|attribution|copyright|©|free of charge|referer|registration|api key' 14 25
py links "$D/wmts-doc.html" 'terms|fair|limit|condition|licen' 8 "$U"

echo "##### 5. IGN España : fin du résumé du service WMTS ; page IDEE sur les services"
page "$D/es.xml" "https://www.ign.es/wmts/mapa-raster?request=GetCapabilities&service=WMTS"
python3 -I - "$D/es.xml" <<'PY' 2>&1 | cut -c1-900
import re, sys
import xml.etree.ElementTree as ET
ns = {"o": "http://www.opengis.net/ows/1.1"}
try:
    si = ET.parse(sys.argv[1]).getroot().find("o:ServiceIdentification", ns)
    ab = re.sub(r"\s+", " ", si.findtext("o:Abstract", namespaces=ns) or "")
    print("  longueur du résumé : %d ; fin : ...%s" % (len(ab), ab[-640:]))
except Exception as e:
    print("  illisible :", e)
PY
U="https://www.idee.es/web/idee/segun-tipo-de-servicio"
page "$D/idee.html" "$U"
py info "$D/idee.html"
py kw "$D/idee.html" 'libre y gratuit|menci[óo]n|origen y propiedad|masiv|l[íi]mite de|condiciones de uso|licencia|CC.?BY' 8 30
