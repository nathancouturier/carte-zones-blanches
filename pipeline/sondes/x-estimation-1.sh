#!/usr/bin/env bash
# Estimation, sonde 1 : documentation OpenCelliD (licence, API, schéma du CSV), Copernicus DEM GLO-30
# (lisez-moi du bucket AWS, listing, gdalinfo par /vsicurl/, licence), aide de gdal_viewshed (GDAL 3.13),
# collections STAC des antennes suisses, listing des sites Arcep (pour un calage éventuel).
set -u
. "$(dirname "$0")/_lib.sh"

# autour <fichier> <motif> [largeur] [max] : texte autour de chaque occurrence d'un motif (HTML ou texte)
autour() {
  python3 - "$1" "$2" "${3:-350}" "${4:-8}" <<'PY'
import re, sys, html
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
s = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
s = html.unescape(re.sub(r"<[^>]+>", " ", s))
s = re.sub(r"\s+", " ", s)
w = int(sys.argv[3]); seen = []
for m in re.finditer(sys.argv[2], s, flags=re.I):
    a = max(0, m.start() - w // 3); b = min(len(s), m.end() + w)
    if any(abs(a - x) < w for x in seen): continue
    seen.append(a); print("   …", s[a:b].strip(), "…")
    if len(seen) >= int(sys.argv[4]): break
if not seen: print("   (motif absent)")
PY
}
# liens <fichier> [filtre] : liens d'une page HTML
liens() {
  python3 - "$1" "${2:-.}" <<'PY'
import re, sys, html
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
out = []
for m in re.finditer(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', s, flags=re.S | re.I):
    href = html.unescape(m.group(1)); label = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", m.group(2))).strip()
    if re.search(sys.argv[2], href + " " + label, re.I) and (href, label) not in out: out.append((href, label))
for href, label in out[:40]: print("   ", href[:200], "|", label[:80])
print("   (", len(out), "liens )")
PY
}
# wiki <titre> : récupère une page du wiki OpenCelliD en wikitexte brut, sinon en HTML converti en texte
wiki() {
  local t="$1" f="$T/w_$1.txt"
  get "$f" "https://wiki.opencellid.org/index.php?title=$t&action=raw"
  if head -c 300 "$f" | grep -q -i -E "<!DOCTYPE|<html"; then
    echo "   (pas de wikitexte brut : repli sur la page HTML)"
    get "$T/w_$t.html" "https://wiki.opencellid.org/wiki/$t"
    texte "$T/w_$t.html" 200000 > "$f"
  fi
  echo "   $(wc -c < "$f") caractères, $(wc -l < "$f") lignes"
}
# lignes <fichier> <motif> <avant> <après> <max> : lignes autour d'un motif, tronquées
lignes() { grep -n -i -E -B "$3" -A "$4" "$2" "$1" | cut -c1-420 | head -n "$5"; }

echo "##### A1. OpenCelliD : page d'accueil, mention de licence"
get "$T/oc.html" "https://opencellid.org/"
autour "$T/oc.html" "licen[cs]|creative commons|CC[ -]BY" 300 4
liens "$T/oc.html" "licen|creativecommons|wiki|download|register|api"

echo "##### A2. OpenCelliD : pages du wiki"
get "$T/pages.json" "https://wiki.opencellid.org/api.php?action=query&list=allpages&aplimit=500&format=json"
python3 - <<'PY' 2>&1 | cut -c1-2500
import json
try:
    d = json.load(open("/tmp/sonde/pages.json"))
    print("  ", [p["title"] for p in d["query"]["allpages"]])
except Exception as e:
    print("   ERREUR", e, open("/tmp/sonde/pages.json", errors="replace").read()[:300].replace("\n", " "))
PY

echo "##### A3. wiki Licensing (texte entier, borné)"
wiki Licensing
cut -c1-900 "$T/w_Licensing.txt" | grep -v "^\s*$" | head -40

echo "##### A4. wiki API : titres puis passages sur le téléchargement et les limites"
wiki API
grep -n -E "^=+[^=]+=+\s*$" "$T/w_API.txt" | cut -c1-120 | head -60
echo "--- téléchargement de la base"
lignes "$T/w_API.txt" "downloads\?|downloads\.php|csv\.gz|cell_towers|diff" 3 6 70
echo "--- limites"
lignes "$T/w_API.txt" "limit|per day|quota|twice|times a day|RATE" 1 2 30

echo "##### A5. wiki Menu_map_view : description des colonnes de la base"
wiki Menu_map_view
lignes "$T/w_Menu_map_view.txt" "changeable|averageSignal|samples|\bradio\b|\brange\b|\bcreated\b|\bupdated\b|\bunit\b|\bnet\b|\barea\b|\bmcc\b" 1 2 80

echo "##### A6. wiki FAQ : précision des positions, limites"
wiki FAQ
lignes "$T/w_FAQ.txt" "accura|precis|download|limit|changeable|token|licen" 1 3 40

echo "##### A7. Page des téléchargements sans jeton, et forme de l'erreur de l'API sans jeton (une seule requête)"
get "$T/dl.html" "https://opencellid.org/downloads.php"
texte "$T/dl.html" 1500 | cut -c1-400 | head -25
autour "$T/dl.html" "per day|limit|token|csv\.gz|licen" 300 6
curl -sS -m 60 -A "$UA" -D "$T/h.txt" -o "$T/dl.bin" -w "  -> %{http_code} %{size_download}o %{content_type}\n" "https://opencellid.org/ocid/downloads?type=mcc&file=213.csv.gz"
grep -i -E "^(HTTP|content-type|content-disposition|location)" "$T/h.txt" | cut -c1-200
head -c 400 "$T/dl.bin" | tr -c '[:print:]\n' '?' ; echo

echo "##### B1. Copernicus DEM : lisez-moi du bucket AWS"
B=https://copernicus-dem-30m.s3.amazonaws.com
get "$T/readme.html" "$B/readme.html"
texte "$T/readme.html" 7000 | cut -c1-700 | head -60
liens "$T/readme.html"

echo "##### B2. Bucket : contenu du dossier d'une tuile, tuiles absentes, liste des tuiles"
get "$T/ls.xml" "$B/?list-type=2&prefix=Copernicus_DSM_COG_10_N45_00_E006_00_DEM/&max-keys=100"
python3 - <<'PY'
import re
s = open("/tmp/sonde/ls.xml", encoding="utf-8", errors="replace").read()
for k, z in re.findall(r"<Key>([^<]+)</Key>.*?<Size>(\d+)</Size>", s, flags=re.S)[:40]:
    print("   ", z.rjust(10), k)
if "<Key>" not in s: print("   ", s[:400])
PY
for t in N45_00_E006_00 N42_00_E005_00 N42_00_E001_00 N43_00_E007_00 N50_00_E002_00; do
  u="$B/Copernicus_DSM_COG_10_${t}_DEM/Copernicus_DSM_COG_10_${t}_DEM.tif"
  echo "   $t : $(curl -sI -m 60 -A "$UA" "$u" | tr -d '\r' | grep -i -E "^(HTTP|content-length|last-modified)" | tr '\n' ' ')"
done
get "$T/tiles.txt" "$B/tileList.txt"
echo "   lignes : $(wc -l < "$T/tiles.txt")"; head -3 "$T/tiles.txt" | cut -c1-200; grep -n -E "N45_00_E006|N42_00_E001|N43_00_E007" "$T/tiles.txt" | cut -c1-200 | head

echo "##### B3. gdalinfo par /vsicurl/ (N45 E006), puis taille d'une tuile N50"
export GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR CPL_VSIL_CURL_ALLOWED_EXTENSIONS=.tif
U="/vsicurl/$B/Copernicus_DSM_COG_10_N45_00_E006_00_DEM/Copernicus_DSM_COG_10_N45_00_E006_00_DEM.tif"
t0=$(date +%s.%N); gdalinfo "$U" 2>&1 | cut -c1-220 | head -90; t1=$(date +%s.%N)
echo "   durée gdalinfo : $(python3 -c "print(round($t1-$t0,2))") s"
gdalinfo "/vsicurl/$B/Copernicus_DSM_COG_10_N50_00_E002_00_DEM/Copernicus_DSM_COG_10_N50_00_E002_00_DEM.tif" 2>&1 | grep -E "^Size is|^Pixel Size|^Origin|Upper Left|Lower Right" | cut -c1-200

echo "##### B4. Licence Copernicus DEM"
apt-get install -y -qq poppler-utils >/dev/null 2>&1
get "$T/lic.pdf" "https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf"
if pdftotext -layout "$T/lic.pdf" "$T/lic.txt" 2>/dev/null; then
  python3 - <<'PY'
import re
s = open("/tmp/sonde/lic.txt", encoding="utf-8", errors="replace").read()
s = re.sub(r"[ \t]+", " ", s); s = re.sub(r"\n\s*\n+", "\n", s)
print("   longueur :", len(s))
for line in s[:9000].split("\n"):
    if line.strip(): print("   |", line.strip()[:600])
PY
else echo "   pdftotext a échoué"; head -c 200 "$T/lic.pdf" | tr -c '[:print:]\n' '?'; fi
get "$T/cdse.html" "https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM"
autour "$T/cdse.html" "licen[cs]e|free of charge|EGM2008|vertical datum|attribution" 450 8
liens "$T/cdse.html" "licen|\.pdf"
get "$T/aws.html" "https://registry.opendata.aws/copernicus-dem/"
autour "$T/aws.html" "licen[cs]e|EGM|vertical|arn:aws|no-sign-request|Update Frequency" 400 8

echo "##### C. gdal_viewshed dans l'image"
gdalinfo --version; echo "   cœurs : $(nproc) ; mémoire : $(free -g | awk 'NR==2{print $2" Go"}')"
echo "--- gdal_viewshed --help"
gdal_viewshed --help 2>&1 | cut -c1-240 | head -70
echo "--- gdal raster viewshed --help"
gdal raster viewshed --help 2>&1 | cut -c1-240 | head -90
echo "--- API Python"
python3 - <<'PY' 2>&1 | cut -c1-900 | head -40
from osgeo import gdal
print(gdal.ViewshedGenerate.__doc__)
print([n for n in dir(gdal) if n.startswith(("GVM_", "GVOT_"))], [(n, getattr(gdal, n)) for n in dir(gdal) if n.startswith(("GVM_", "GVOT_"))])
PY

echo "##### D. Suisse : collections STAC des antennes (v0.9), éléments et fichiers"
python3 - <<'PY'
import json, urllib.request
UA = {"User-Agent": "carte-zones-blanches-sonde/1.0 (+https://github.com/nathancouturier/carte-zones-blanches)"}
def getj(u):
    with urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=60) as r:
        return json.load(r)
# toutes les collections dont l'identifiant contient « bakom »
u = "https://data.geo.admin.ch/api/stac/v0.9/collections?limit=100"; found = []; pages = 0; total = 0
try:
    while u and pages < 30:
        d = getj(u); pages += 1
        for c in d.get("collections", []):
            total += 1
            if "bakom" in c.get("id", ""): found.append((c["id"], c.get("title"), c.get("license")))
        u = next((l["href"] for l in d.get("links", []) if l.get("rel") == "next"), None)
except Exception as e:
    print("   ERREUR listing", e)
print("   collections lues :", total, "en", pages, "pages ; collections bakom :", len(found))
for f in found: print("    -", f)
PY
for c in ch.bakom.mobil-antennenstandorte-4g ch.bakom.mobil-antennenstandorte-5g ch.bakom.mobil-antennenstandorte-lte ch.bakom.standorte-mobilfunkanlagen; do
  get "$T/col.json" "https://data.geo.admin.ch/api/stac/v0.9/collections/$c"
  python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/col.json"))
    if "id" not in d: print("   ", json.dumps(d)[:200]); raise SystemExit
    print("   id:", d.get("id"), "| titre:", d.get("title"), "| licence:", d.get("license"), "| maj:", d.get("updated"))
    print("   description:", (d.get("description") or "")[:700].replace("\n", " "))
    print("   fournisseurs:", [(p.get("name"), p.get("roles")) for p in d.get("providers", [])])
    for l in d.get("links", []):
        if l.get("rel") in ("license", "describedby", "about"): print("   lien", l.get("rel"), l.get("href"), l.get("title"))
except SystemExit: pass
except Exception as e: print("   ERREUR", e)
PY
  get "$T/items.json" "https://data.geo.admin.ch/api/stac/v0.9/collections/$c/items?limit=20"
  python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/items.json")); feats = d.get("features", [])
    print("   éléments:", len(feats))
    for f in feats[:5]:
        p = f.get("properties", {})
        print("    -", f.get("id"), "| datetime:", p.get("datetime"), "| maj:", p.get("updated"), "| bbox:", f.get("bbox"))
        for name, a in f.get("assets", {}).items():
            print("        fichier", name, "|", a.get("type"), "| epsg:", a.get("proj:epsg"), "| maj:", a.get("updated"), "|", a.get("href"))
except Exception as e: print("   ERREUR", e)
PY
done
get "$T/col1.json" "https://data.geo.admin.ch/api/stac/v1/collections/ch.bakom.mobil-antennenstandorte-4g"
head -c 300 "$T/col1.json"; echo

echo "##### E. France : fichiers « sites » de l'Arcep (positions officielles, pour caler la méthode)"
get "$T/sites.html" "https://data.arcep.fr/mobile/sites/last/"
python3 - <<'PY'
import re, html
s = open("/tmp/sonde/sites.html", encoding="utf-8", errors="replace").read()
for href, size, mod in re.findall(r'<a href="([^"]+)"[^>]*>.*?data-size="(\d+)".*?datetime="([^"]+)"', s, flags=re.S)[:30]:
    print("   ", html.unescape(href), "|", round(int(size) / 1e6, 2), "Mo |", mod)
if "data-size" not in s: print("   ", re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", s))[:600])
PY
echo "FIN"
