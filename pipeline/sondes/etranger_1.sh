#!/usr/bin/env bash
# Inventaire des sources étrangères, premier passage : Suisse (STAC OFCOM), Italie (AGCOM),
# Espagne (ministère), licences des fonds et des contours.
set -u
. "$(dirname "$0")/_lib.sh"
jqpy() { python3 -c "$1" "${@:2}"; }

echo "##### 1. Suisse : collections STAC de l'OFCOM"
for c in ch.bakom.mobilnetz-4g ch.bakom.mobilnetz-5g ch.bakom.mobilnetz-3g ch.bakom.mobilnetz-2g; do
  get "$T/col.json" "https://data.geo.admin.ch/api/stac/v0.9/collections/$c"
  python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/col.json"))
    print("  id:", d.get("id"), "| titre:", d.get("title"), "| licence:", d.get("license"), "| maj:", d.get("updated"), "| cree:", d.get("created"))
    print("  description:", (d.get("description") or "")[:900].replace("\n", " "))
    print("  fournisseurs:", [(p.get("name"), p.get("roles")) for p in d.get("providers", [])])
    print("  etendue:", json.dumps(d.get("extent"))[:300])
    print("  resume:", json.dumps(d.get("summaries"))[:400])
    for l in d.get("links", []):
        if l.get("rel") in ("license", "describedby", "items", "about"):
            print("  lien", l.get("rel"), l.get("href"), l.get("title"))
except Exception as e:
    print("  ERREUR", e)
PY
  get "$T/items.json" "https://data.geo.admin.ch/api/stac/v0.9/collections/$c/items?limit=20"
  python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/items.json"))
    feats = d.get("features", [])
    print("  items:", len(feats))
    for f in feats[:6]:
        p = f.get("properties", {})
        print("   -", f.get("id"), "| datetime:", p.get("datetime"), "| maj:", p.get("updated"), "| bbox:", f.get("bbox"))
        for name, a in f.get("assets", {}).items():
            print("       asset", name, "|", a.get("type"), "| epsg:", a.get("proj:epsg"), "| gsd:", a.get("eo:gsd"), "| maj:", a.get("updated"), "|", a.get("href"))
except Exception as e:
    print("  ERREUR", e)
PY
done

echo "##### 2. Suisse : contenu d'un fichier 4G"
python3 - <<'PY' > "$T/ch_assets.txt"
import json
d = json.load(open("/tmp/sonde/items.json"))
PY
get "$T/items4g.json" "https://data.geo.admin.ch/api/stac/v0.9/collections/ch.bakom.mobilnetz-4g/items?limit=20"
python3 - <<'PY' > "$T/ch_urls.txt"
import json
d = json.load(open("/tmp/sonde/items4g.json"))
for f in d.get("features", []):
    for name, a in f.get("assets", {}).items():
        print(a.get("href"))
PY
cat "$T/ch_urls.txt"
mkdir -p "$T/ch"; cd "$T/ch"
for u in $(cat "$T/ch_urls.txt"); do
  f=$(basename "$u")
  curl -sS -L -m 600 -A "$UA" -o "$f" -w "  -> %{http_code} %{size_download}o $f\n" "$u"
  case "$f" in
    *.zip) python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); [print('     zip:', i.filename, i.file_size) for i in z.infolist()[:20]]; z.extractall('.')" "$f" ;;
  esac
done
ls -la "$T/ch" | head -40
for f in $(find "$T/ch" -type f \( -name "*.tif" -o -name "*.tiff" \) | head -3); do
  echo "--- gdalinfo $f"; gdalinfo -stats -hist "$f" 2>&1 | grep -v "^  [0-9 ]*$" | head -60
done
for f in $(find "$T/ch" -type f \( -name "*.gpkg" -o -name "*.shp" -o -name "*.gdb" -o -name "*.geojson" -o -name "*.json" \) | head -3); do
  echo "--- ogrinfo $f"; ogrinfo -so -al "$f" 2>&1 | head -60
done
for f in $(find "$T/ch" -type f -name "*.csv" | head -2); do
  echo "--- csv $f"; head -5 "$f"; wc -l "$f"
  python3 - "$f" <<'PY'
import csv, sys, collections
with open(sys.argv[1], newline="", encoding="utf-8", errors="replace") as fh:
    sample = fh.read(4096); fh.seek(0)
    dialect = csv.Sniffer().sniff(sample, delimiters=",;\t")
    rd = csv.DictReader(fh, dialect=dialect)
    cnt = {k: collections.Counter() for k in rd.fieldnames}
    n = 0
    for row in rd:
        n += 1
        for k, v in row.items():
            if len(cnt[k]) < 50: cnt[k][v] += 1
        if n >= 400000: break
    print("   colonnes:", rd.fieldnames, "| lignes lues:", n)
    for k, c in cnt.items():
        print("   ", k, "->", c.most_common(12) if len(c) < 50 else f"{len(c)}+ valeurs, ex. {list(c)[:5]}")
PY
done
cd /

echo "##### 3. Suisse : conditions d'utilisation"
get "$T/p.html" "https://www.geo.admin.ch/en/general-terms-of-use-fsdi"
texte "$T/p.html" 2500
get "$T/p.html" "https://opendata.swiss/api/3/action/package_show?id=4g-lte-lte-a-verfugbarkeit"
python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/p.html"))["result"]
    print("  titre:", d.get("title"), "| licence:", d.get("license_id"), d.get("license_title"), "| maj:", d.get("metadata_modified"), "| periodicite:", d.get("accrual_periodicity"))
    print("  description:", json.dumps(d.get("description"), ensure_ascii=False)[:1500])
    for r in d.get("resources", [])[:8]:
        print("   ressource:", r.get("format"), "|", r.get("rights") or r.get("license"), "|", r.get("url") or r.get("download_url"))
except Exception as e:
    print("  ERREUR", e)
PY

echo "##### 4. Italie : AGCOM"
for u in "https://geo3.agcom.it/opendata" "https://geo3.agcom.it/opendata/" "https://maps.agcom.it/" "https://geo.agcom.it/reportistica" "https://www.agcom.it/broadband-map"; do
  get "$T/p.html" "$u"
  echo "  --- liens:"; python3 - <<'PY'
import re
s = open("/tmp/sonde/p.html", encoding="utf-8", errors="replace").read()
hrefs = sorted(set(re.findall(r'(?:href|src)="([^"#]+)"', s)))
keep = [h for h in hrefs if re.search(r"opendata|download|\.zip|\.csv|\.gpkg|\.shp|\.json|licen|mobile|copertura|wms|wfs|geoserver|arcgis|api", h, re.I)]
print("   ", len(hrefs), "liens ;", keep[:50])
PY
  echo "  --- texte:"; texte "$T/p.html" 1500
done

echo "##### 5. Espagne : ministère"
get "$T/p.html" "https://digital.gob.es/telecomunicaciones-infraestructuras-digitales/areas-interes/banda-ancha/informacion-cobertura/mapas-servicios-banda-ancha"
python3 - <<'PY'
import re
s = open("/tmp/sonde/p.html", encoding="utf-8", errors="replace").read()
hrefs = sorted(set(re.findall(r'href="([^"#]+)"', s)))
print("   liens utiles:", [h for h in hrefs if re.search(r"arcgis|experience|mapa|visor|datos|descarga|\.zip|\.csv|wms|aviso|legal|reutiliz", h, re.I)][:60])
PY
texte "$T/p.html" 3500
get "$T/p.html" "https://digital.gob.es/aviso-legal"
texte "$T/p.html" 3000

echo "##### 6. Licences diverses"
get "$T/p.json" "https://www.data.gouv.fr/api/1/datasets/?q=contours%20administratifs%20etalab&page_size=6"
python3 - <<'PY'
import json
try:
    for d in json.load(open("/tmp/sonde/p.json")).get("data", []):
        print("  -", d.get("slug"), "|", d.get("title"), "| licence:", d.get("license"), "| org:", (d.get("organization") or {}).get("name"))
except Exception as e:
    print("  ERREUR", e)
PY
get "$T/p.md" "https://raw.githubusercontent.com/etalab/contours-administratifs/master/README.md"
grep -n -i -E "licen|source|ign|osm|admin.express" "$T/p.md" | head -20
get "$T/p.html" "https://opentopomap.org/about"
texte "$T/p.html" 2500
get "$T/p.html" "https://photon.komoot.io/"
texte "$T/p.html" 1800
get "$T/p.html" "https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices"
texte "$T/p.html" 2200
get "$T/p.html" "https://geoservices.ign.fr/cgu-licences"
texte "$T/p.html" 2500

echo "##### 7. Étiquettes de l'image GDAL"
tok=$(curl -sS -m 60 "https://ghcr.io/token?scope=repository:osgeo/gdal:pull" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))")
curl -sS -m 60 -H "Authorization: Bearer $tok" "https://ghcr.io/v2/osgeo/gdal/tags/list?n=2000" | python3 -c "
import sys, json, re
tags = json.load(sys.stdin).get('tags', [])
small = sorted([t for t in tags if re.fullmatch(r'ubuntu-small-\d+\.\d+\.\d+', t)], key=lambda t: [int(x) for x in t.split('-')[-1].split('.')])
print('  ubuntu-small:', small[-12:])
"
echo "FIN"
