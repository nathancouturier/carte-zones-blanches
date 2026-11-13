#!/usr/bin/env bash
# Inventaire des sources étrangères, deuxième passage : détails OFCOM, téléchargements AGCOM,
# cartes du ministère espagnol, politiques d'usage.
set -u
. "$(dirname "$0")/_lib.sh"

# autour <fichier> <motif> [largeur] : affiche le texte autour de chaque occurrence d'un motif
autour() {
  python3 - "$1" "$2" "${3:-350}" <<'PY'
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
    if len(seen) >= 8: break
if not seen: print("   (motif absent)")
PY
}
liens() { # liens <fichier> [filtre] : liste les liens d'une page
  python3 - "$1" "${2:-.}" <<'PY'
import re, sys, html
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
out = []
for m in re.finditer(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', s, flags=re.S | re.I):
    href = html.unescape(m.group(1)); label = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", m.group(2))).strip()
    if re.search(sys.argv[2], href + " " + label, re.I) and (href, label) not in out: out.append((href, label))
for href, label in out[:80]: print("   ", href, "|", label[:80])
print("   (", len(out), "liens )")
PY
}

echo "##### 1. Suisse : bande du GeoTIFF 4G, lisez-moi, conditions"
mkdir -p "$T/ch"; cd "$T/ch"
for techno in 4g 5g 3g; do
  curl -sS -L -m 600 -A "$UA" -o "mobilnetz-$techno.tif" -w "  -> %{http_code} %{size_download}o mobilnetz-$techno.tif\n" "https://data.geo.admin.ch/ch.bakom.mobilnetz-$techno/mobilnetz-$techno/mobilnetz-${techno}_2056.tif"
  gdalinfo "mobilnetz-$techno.tif" 2>&1 | sed -n '/^Band 1/,$p' | head -12
  python3 - "mobilnetz-$techno.tif" <<'PY'
import sys, numpy as np
from osgeo import gdal
ds = gdal.Open(sys.argv[1]); b = ds.GetRasterBand(1); a = b.ReadAsArray()
vals, counts = np.unique(a, return_counts=True)
print("   type:", gdal.GetDataTypeName(b.DataType), "| nodata:", b.GetNoDataValue(), "| taille:", a.shape, "| valeurs:", dict(zip(vals.tolist()[:20], counts.tolist()[:20])))
PY
done
curl -sS -L -m 120 -A "$UA" -o z.zip "https://data.geo.admin.ch/ch.bakom.mobilnetz-4g/mobilnetz-4g/mobilnetz-4g.zip" && python3 -c "import zipfile; z=zipfile.ZipFile('z.zip'); print(z.read('readme.txt').decode('utf-8','replace'))"
cd /
get "$T/p.html" "https://www.geo.admin.ch/en/general-terms-of-use-fsdi"
autour "$T/p.html" "source|attribution|reference" 500
get "$T/p.html" "https://opendata.swiss/en/terms-of-use"
autour "$T/p.html" "Open use|terms_open|must be provided|Source" 500
get "$T/p.html" "https://www.bakom.admin.ch/en/broadband-atlas"
autour "$T/p.html" "mobile|operators|update" 400

echo "##### 2. Italie : open data AGCOM"
get "$T/it.html" "https://geo3.agcom.it/opendata/"
liens "$T/it.html"
for page in Download/Mobile Download/RetiMobili Download/Mobili download/mobile Termini TerminiCondizioni Home/Termini; do
  get "$T/itp.html" "https://geo3.agcom.it/opendata/$page"
done
grep -o -i 'href="[^"]*"' "$T/it.html" | sort -u | head -60
grep -n -i -E "download|mobile|termini" "$T/it.html" | cut -c1-260 | head -40

echo "##### 3. Espagne : cartes du ministère"
get "$T/es.html" "https://digital.gob.es/telecomunicaciones-infraestructuras-digitales/areas-interes/banda-ancha/informacion-cobertura/mapas-servicios-banda-ancha"
liens "$T/es.html" "arcgis|experience|visor|mapa|descarg|datos\.gob|\.zip|\.csv|wms|geoportal"
autour "$T/es.html" "banda ancha m[oó]vil|cuadr[ií]cula|4G|operador" 600
get "$T/es2.html" "https://digital.gob.es/telecomunicaciones-infraestructuras-digitales/areas-interes/banda-ancha/informacion-cobertura/mapas-cobertura-agregada"
liens "$T/es2.html" "arcgis|experience|visor|descarg|datos\.gob|\.zip|\.csv|\.xlsx|wms"
autour "$T/es2.html" "descarg|reutiliz|4G" 500
get "$T/esl.html" "https://digital.gob.es/nota-legal"
autour "$T/esl.html" "reutiliz|propiedad intelectual|licencia|cita" 700
get "$T/p.json" "https://datos.gob.es/apidata/catalog/dataset/e05251701-base-de-datos-historica-desde-2013-a2020-de-cobertura-banda-ancha-fija-y-movil.json"
head -c 1500 "$T/p.json"; echo

echo "##### 4. OpenTopoMap : politique d'usage"
get "$T/otm.html" "https://opentopomap.org/about"
autour "$T/otm.html" "Verwendung|Nutzung|usage|Lizenz|CC-BY|Kachel|tile" 700

echo "##### 5. Géoplateforme IGN : conditions"
get "$T/ign.html" "https://geoservices.ign.fr/cgu-licences"
autour "$T/ign.html" "Licence Ouverte|gratuit|sans cl[ée]|limite|requ[êe]tes par seconde|mention" 600
get "$T/ign2.html" "https://geoservices.ign.fr/documentation/services/services-geoplateforme/diffusion"
autour "$T/ign2.html" "limite|requ[êe]tes|cl[ée]" 500

echo "##### 6. Contours Etalab : licence"
for q in "contours%20administratifs" "admin%20express"; do
  get "$T/p.json" "https://www.data.gouv.fr/api/1/datasets/?q=$q&page_size=8"
  python3 - <<'PY'
import json
try:
    for d in json.load(open("/tmp/sonde/p.json")).get("data", []):
        print("   -", d.get("slug"), "|", d.get("title"), "| licence:", d.get("license"), "| org:", (d.get("organization") or {}).get("name"))
except Exception as e:
    print("   ERREUR", e)
PY
done
echo "FIN"
