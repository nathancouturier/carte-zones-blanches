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

# ---- conditions-5 : Géoplateforme (suite) : articles des CGU, limites par service, en-têtes, licence des couches ----
U="https://cartes.gouv.fr/cgu/"
echo "##### 1. $U : articles utiles"
page "$D/cgu.html" "$U"
py info "$D/cgu.html"
echo "--- dates et version"
py kw "$D/cgu.html" 'version|mise [àa] jour le|en vigueur|derni[èe]re modification|[àa] compter du|applicables? au' 6 0
echo "--- préambule et définitions"
py all "$D/cgu.html" 40 '^# Conditions g' '^## Acc.s aux API par' 60
echo "--- Accès aux API"
py all "$D/cgu.html" 12 '^## Acc.s aux API par' '^### Cr.ation d.un compte'
echo "--- Authentification ; aucun transfert de droit"
py all "$D/cgu.html" 14 '^### Acc.s et utilisation de certaines API' '^## Utilisation des API'
echo "--- Utilisation conforme des API"
py all "$D/cgu.html" 26 '^## Utilisation des API' '^### Droits des Fournisseurs d.API'
echo "--- Blocage"
py all "$D/cgu.html" 8 '^### Blocage d.acc' '^## ENGAGEMENTS'
echo "--- Annexe 1 : liste des API"
py all "$D/cgu.html" 36 '^## Annexe 1' '^## Annexe 2'
echo "--- Annexe 2 : lignes sur les quotas et la consommation"
py kw "$D/cgu.html" 'consommation|quota|requ[êe]tes|par seconde|plafond' 10 0
echo "--- Annexe 3, article 3 et suivants (limite d'usage)"
py all "$D/cgu.html" 46 '^#+ Article 3' ''
echo "--- liens vers la documentation"
py links "$D/cgu.html" 'aide|documentation|limite|fair|geoplateforme|data\.geopf|mentions' 14 "$U"

echo "##### 2. data.gouv.fr : fiches « API Géoplateforme » publiées par l'IGN"
page "$D/org.json" "https://www.data.gouv.fr/api/1/organizations/institut-national-de-linformation-geographique-et-forestiere/"
OID=$(python3 -I -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("id") or "")
except Exception: print("")' "$D/org.json")
echo "  organisation : id=$OID"
if [ -n "$OID" ]; then
  page "$D/ds.json" "https://www.data.gouv.fr/api/1/dataservices/?organization=$OID&page_size=100"
else
  page "$D/ds.json" "https://www.data.gouv.fr/api/1/dataservices/?q=API%20G%C3%A9oplateforme&page_size=60"
fi
python3 -I - "$D/ds.json" <<'PY' 2>&1 | cut -c1-460 | head -70
import json, re, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    print("  JSON illisible :", e); sys.exit()
items = d.get("data", []) if isinstance(d, dict) else d
print("  total=%s reçus=%d" % (d.get("total") if isinstance(d, dict) else "?", len(items)))
if items:
    print("  champs :", ", ".join(sorted(items[0].keys())))
utile = re.compile(r"WMTS|TMS|tuil|g[ée]ocod|autocompl|images?|vecto", re.I)
for it in sorted(items, key=lambda x: x.get("title") or ""):
    title = it.get("title") or ""
    url = it.get("base_api_url") or ""
    if not re.search(r"g[ée]oplateforme|geopf", title + " " + url, re.I):
        continue
    print("- %s | %s" % (title, url))
    print("    accès=%s | limite=%r | disponibilité=%r | licence=%r | modifié=%s | fiche=%s" % (
        it.get("access_type"), it.get("rate_limiting"), it.get("availability"), it.get("license"),
        str(it.get("metadata_modified_at") or it.get("last_modified") or "")[:10], it.get("self_web_url") or it.get("page")))
    if utile.search(title):
        for sent in re.split(r"(?<=[.!?])\s+|\n+", it.get("description") or ""):
            if re.search(r"limit|requ[êe]tes? par|gratuit|sans cl|cl[ée] |cache|mention|ouvert|libre", sent, re.I):
                print("    > " + re.sub(r"\s+", " ", sent).strip()[:380])
PY

echo "##### 3. En-têtes des réponses de data.geopf.fr (une requête par service)"
entetes "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&TILEMATRIXSET=PM&TILEMATRIX=12&TILECOL=2114&TILEROW=1470&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&FORMAT=image/png&STYLE=normal"
entetes "https://data.geopf.fr/tms/1.0.0/PLAN.IGN/12/2114/1470.pbf"
entetes "https://data.geopf.fr/annexes/ressources/vectorTiles/styles/PLAN.IGN/classique.json"
entetes "https://data.geopf.fr/geocodage/completion?text=lautaret&type=PositionOfInterest&maximumResponses=1"

echo "##### 4. WMTS data.geopf.fr : identification du service, métadonnées des trois couches"
page "$D/geopf.xml" "https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetCapabilities"
python3 -I - "$D/geopf.xml" "$D/geopf-meta.txt" <<'PY' 2>&1 | cut -c1-600
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
want = ("GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2", "ORTHOIMAGERY.ORTHOPHOTOS", "ELEVATION.ELEVATIONGRIDCOVERAGE.SHADOW")
metas = []
for l in root.findall(".//w:Layer", ns):
    ident = t(l, "o:Identifier")
    if ident not in want:
        continue
    hrefs = [m.get(XL) for m in l.findall("o:Metadata", ns) if m.get(XL)]
    print("  %s : Title=%r | Abstract=%r" % (ident, t(l, "o:Title"), (t(l, "o:Abstract") or "")[:160]))
    print("      métadonnées : %s" % hrefs[:3])
    if hrefs:
        metas.append(hrefs[0])
open(sys.argv[2], "w").write("\n".join(metas))
PY
k=0
while IFS= read -r u; do
  [ -n "$u" ] || continue
  k=$((k + 1))
  echo "--- métadonnées $k"
  page "$D/geopf-meta$k.xml" "$u"
  py raw "$D/geopf-meta$k.xml" 'useLimitation|otherConstraints|licence ouverte|open licence|etalab|conditions? (d.utilisation|g[ée]n[ée]rales)|©|mention' 220 4
done < "$D/geopf-meta.txt"
echo "--- TMS PLAN.IGN : clés de metadata.json (hors vector_layers)"
page "$D/tms.json" "https://data.geopf.fr/tms/1.0.0/PLAN.IGN/metadata.json"
python3 -I -c 'import json,sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    print("  " + json.dumps({k: v for k, v in d.items() if k != "vector_layers"}, ensure_ascii=False)[:700])
except Exception as e:
    print("  illisible :", e)' "$D/tms.json"

echo "##### 5. Licence Ouverte 2.0 (texte du dépôt etalab/licence-ouverte, lié depuis les CGU)"
page "$D/lo.md" "https://raw.githubusercontent.com/etalab/licence-ouverte/master/LO.md"
py kwt "$D/lo.md" 'paternit|mention|source|mise [àa] jour|hypertexte|librement|gratuit|commercial|version 2|compatib' 18 30
