#!/usr/bin/env bash
# Sonde frontieres-1 : reconnaissance des sources de masques de pays (Suisse, Italie, Espagne, Andorre, Monaco).
# Petites requêtes seulement : catalogues, capacités, en-têtes, métadonnées. Aucun gros téléchargement.
set -u
. "$(dirname "$0")/_lib.sh"
cd "$T"
c300() { cut -c1-300; }
tete() { # tete <url> : code HTTP, taille, type, date de modification (requête HEAD)
  curl -sS -I -L -m 60 -A "$UA" "$1" 2>&1 | tr -d '\r' | grep -i -E '^(HTTP/|content-length|content-type|last-modified|accept-ranges)' | tr '\n' ' ' | c300; echo " <= $1"
}

echo "##### 0. Outils disponibles"
ogrinfo --version
ogrinfo --formats 2>/dev/null | grep -E -i ' (OSM|GML|GPKG|WFS|OAPIF|GeoJSON|ESRI Shapefile|OpenFileGDB|FlatGeobuf) ' | c300
python3 -c "import osgeo, numpy; from osgeo import ogr; print('python gdal', osgeo.__version__, 'numpy', numpy.__version__, 'GEOS', ogr.GetGEOSVersionMajor(), ogr.GetGEOSVersionMinor())"

echo
echo "##### A. SUISSE : swissBOUNDARIES3D (STAC)"
get ch-coll.json "https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swissboundaries3d"
python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/ch-coll.json"))
    for k in ("id", "title", "license", "created", "updated"):
        print("  ", k, ":", str(d.get(k))[:200])
    print("   description :", (d.get("description") or "").replace("\n", " ")[:500])
    print("   fournisseurs :", [(p.get("name"), p.get("roles"), p.get("url")) for p in d.get("providers", [])])
    print("   etendue :", json.dumps(d.get("extent"))[:300])
    print("   resume :", json.dumps(d.get("summaries"))[:500])
    for l in d.get("links", []):
        print("   lien", l.get("rel"), "|", l.get("href"), "|", (l.get("title") or "")[:80])
except Exception as e:
    print("   ERREUR", e)
PY
get ch-items.json "https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swissboundaries3d/items?limit=100"
python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/ch-items.json"))
    feats = d.get("features", [])
    print("   nombre d'items :", len(feats))
    feats.sort(key=lambda f: str(f.get("properties", {}).get("datetime") or f.get("id")))
    for f in feats[:-2]:
        p = f.get("properties", {})
        print("   item", f.get("id"), "| datetime", p.get("datetime"), "| assets", len(f.get("assets", {})))
    for f in feats[-2:]:
        p = f.get("properties", {})
        print("   ITEM", f.get("id"), "| datetime", p.get("datetime"), "| cree", p.get("created"), "| maj", p.get("updated"), "| bbox", f.get("bbox"))
        for name, a in f.get("assets", {}).items():
            print("      asset", name, "|", a.get("type"), "| epsg", a.get("proj:epsg"), "| maj", a.get("updated"), "|", a.get("href"))
    for l in d.get("links", []):
        print("   lien", l.get("rel"), l.get("href"))
except Exception as e:
    print("   ERREUR", e)
PY
if ! grep -q '"id"' ch-coll.json 2>/dev/null; then
  echo "   collection introuvable : recherche dans le catalogue"
  u="https://data.geo.admin.ch/api/stac/v0.9/collections?limit=100"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    curl -sS -L -m 120 -A "$UA" -o coll-page.json "$u" || break
    u=$(python3 - <<'PY'
import json
d = json.load(open("/tmp/sonde/coll-page.json"))
for c in d.get("collections", []):
    if "bound" in c.get("id", "").lower() or "grenz" in (c.get("title") or "").lower():
        print("   CANDIDAT", c.get("id"), "|", c.get("title"), flush=True, file=__import__("sys").stderr)
nxt = [l["href"] for l in d.get("links", []) if l.get("rel") == "next"]
print(nxt[0] if nxt else "")
PY
)
    [ -z "$u" ] && break
  done
fi
echo "--- conditions d'utilisation swisstopo"
for u in "https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices" \
         "https://www.swisstopo.admin.ch/en/source-reference-ogd-swisstopo" \
         "https://www.swisstopo.admin.ch/fr/conditions-generales-d-utilisation-des-geodonnees-et-geoservices-gratuits"; do
  get page.html "$u"
  texte page.html 60000 | grep -i -E "free of charge|may be used|must be indicated|source|©|sans frais|gratuit|peuvent être|indication de la source|commercial" | grep -v -i -E "cookie|javascript" | awk 'length($0) > 25' | c300 | head -14
done

echo
echo "##### B. ITALIE : ISTAT, confini delle unità amministrative"
get istat.html "https://www.istat.it/notizia/confini-delle-unita-amministrative-a-fini-statistici-al-1-gennaio-2018-2/"
echo "--- liens zip (2024 à 2026)"
grep -o -E 'href="[^"]+\.zip"' istat.html | sort -u | grep -E '20(24|25|26)' | c300 | head -20
echo "--- phrases utiles de la page"
texte istat.html 200000 | grep -i -E "generalizzat|WGS84|UTM|licenz|creative|aggiornat|sistema di riferimento|ED50|shapefile|poligon|revision|definitiv|provvisor" | awk 'length($0) > 30' | c300 | head -24
echo "--- en-têtes des archives"
for u in $(grep -o -E 'href="[^"]+\.zip"' istat.html | sed -E 's/^href="//; s/"$//' | sort -u | grep -E '20(25|26)' | head -6); do
  case "$u" in http*) ;; *) u="https://www.istat.it$u" ;; esac
  tete "$u"
done
echo "--- licence ISTAT (note legali)"
for u in "https://www.istat.it/note-legali/" "https://www.istat.it/en/legal-notice/"; do
  get page.html "$u"
  texte page.html 80000 | grep -i -E "creative commons|licenza|license|riprodurre|attribuzione|attribution|fonte|source" | awk 'length($0) > 25' | c300 | head -10
  grep -o -E 'https?://creativecommons\.org/[^"<> ]+' page.html | sort -u | head -5
done

echo
echo "##### C. ESPAGNE : IGN / CNIG"
echo "--- WFS INSPIRE unidades administrativas : capacités"
get es-cap.xml "https://www.ign.es/wfs-inspire/unidades-administrativas?service=WFS&version=2.0.0&request=GetCapabilities"
python3 - <<'PY'
import re
try:
    s = open("/tmp/sonde/es-cap.xml", encoding="utf-8", errors="replace").read()
    print("   taille", len(s))
    for tag in ("ows:Title", "ows:Abstract", "ows:Fees", "ows:AccessConstraints", "ows:ProviderName"):
        m = re.search(r"<%s[^>]*>(.*?)</%s>" % (tag, tag), s, re.S)
        print("  ", tag, ":", re.sub(r"\s+", " ", m.group(1))[:600] if m else None)
    for ft in re.findall(r"<(?:wfs:)?FeatureType>.*?</(?:wfs:)?FeatureType>", s, re.S):
        name = re.search(r"<(?:wfs:)?Name>(.*?)</", ft)
        title = re.search(r"<(?:wfs:)?Title>(.*?)</", ft)
        crs = re.findall(r"<(?:wfs:)?(?:DefaultCRS|OtherCRS)>(.*?)</", ft)
        fmts = re.findall(r"<(?:wfs:)?Format>(.*?)</", ft)
        bbox = re.search(r"<ows:LowerCorner>(.*?)</ows:LowerCorner>\s*<ows:UpperCorner>(.*?)</", ft)
        print("   TYPE", name.group(1) if name else None, "|", title.group(1) if title else None, "| SCR", crs[:8], "| formats", fmts[:8], "| bbox", bbox.groups() if bbox else None)
    m = re.search(r'<ows:Operation name="GetFeature">.*?</ows:Operation>', s, re.S)
    if m:
        for p in re.findall(r'<ows:Parameter name="([^"]+)">(.*?)</ows:Parameter>', m.group(0), re.S):
            print("   GetFeature parametre", p[0], re.findall(r"<ows:Value>(.*?)</ows:Value>", p[1])[:12])
    for c in re.findall(r'<ows:Constraint name="([^"]+)">(.*?)</ows:Constraint>', s, re.S):
        v = re.findall(r"<ows:(?:DefaultValue|Value)>(.*?)</", c[1])
        if c[0] in ("CountDefault", "ImplementsResultPaging", "KVPEncoding", "ImplementsSpatialJoins") or "Count" in c[0]:
            print("   contrainte", c[0], v)
except Exception as e:
    print("   ERREUR", e)
PY
echo "--- API OGC Features de l'IGN"
get es-api.json "https://api-features.ign.es/collections?f=json"
python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/es-api.json"))
    cols = d.get("collections", [])
    print("   collections :", len(cols))
    for c in cols:
        cid = c.get("id", "")
        if any(k in (cid + " " + (c.get("title") or "")).lower() for k in ("admin", "limit", "límit", "boundar", "recint")):
            print("   COLLECTION", cid, "|", c.get("title"), "|", (c.get("description") or "")[:200].replace("\n", " "), "| crs", (c.get("crs") or [])[:4], "| items", c.get("itemType"))
    print("   toutes :", [c.get("id") for c in cols][:80])
    for l in d.get("links", []):
        if l.get("rel") in ("license", "describedby", "service-desc"):
            print("   lien", l.get("rel"), l.get("href"), l.get("title"))
except Exception as e:
    print("   ERREUR", e)
PY
for c in administrativeunit administrativeboundary; do
  get es-c.json "https://api-features.ign.es/collections/$c?f=json"
  python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/es-c.json"))
    print("   id", d.get("id"), "| titre", d.get("title"), "| desc", (d.get("description") or "")[:300].replace("\n", " "))
    print("   etendue", json.dumps(d.get("extent"))[:260], "| crs", (d.get("crs") or [])[:6], "| storageCrs", d.get("storageCrs"))
    for l in d.get("links", []):
        print("   lien", l.get("rel"), "|", l.get("type"), "|", l.get("href"))
except Exception as e:
    print("   ERREUR", e)
PY
  get es-q.json "https://api-features.ign.es/collections/$c/queryables?f=json"
  python3 -c "
import json
try:
    d = json.load(open('/tmp/sonde/es-q.json')); print('   queryables', {k: (v.get('type'), v.get('enum')) for k, v in d.get('properties', {}).items()})
except Exception as e: print('   ERREUR queryables', e)" | cut -c1-900
  get es-i.json "https://api-features.ign.es/collections/$c/items?f=json&limit=2"
  python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/es-i.json"))
    print("   numberMatched", d.get("numberMatched"), "numberReturned", d.get("numberReturned"))
    for f in d.get("features", [])[:2]:
        g = f.get("geometry") or {}
        print("   entite id", f.get("id"), "| geom", g.get("type"), "| proprietes", json.dumps(f.get("properties"), ensure_ascii=False)[:700])
    for l in d.get("links", []):
        print("   lien", l.get("rel"), l.get("type"), l.get("href"))
except Exception as e:
    print("   ERREUR", e)
PY
done
echo "--- CNIG : page des limites et licence"
get cnig.html "https://centrodedescargas.cnig.es/CentroDescargas/limites-municipales-provinciales-autonomicos"
grep -o -i -E '(href|data-[a-z]+|onclick)="[^"]*(zip|descargaDir|secuencial|secDesc)[^"]*"' cnig.html | sort -u | c300 | head -15
texte cnig.html 60000 | grep -i -E "licencia|CC[- ]BY|recintos|l[ií]neas l[ií]mite|ETRS89|REGCAN|shapefile|formato|fecha|tamaño" | awk 'length($0) > 20' | c300 | head -16
for u in "https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf"; do tete "$u"; done

echo
echo "##### D. OPENSTREETMAP : Andorre, Monaco"
get ovp-status.txt "https://overpass-api.de/api/status"; head -8 ovp-status.txt | c300
cat > q1.txt <<'Q'
[out:json][timeout:120];
(
  relation["ISO3166-1"="AD"];
  relation["ISO3166-1"="MC"];
  relation["boundary"="land_area"](43.70,7.38,43.77,7.46);
  relation["type"="land_area"](43.70,7.38,43.77,7.46);
  relation["boundary"="administrative"]["admin_level"~"^(2|3|4|8|9|10)$"](43.725,7.41,43.75,7.44);
  relation["boundary"="administrative"]["admin_level"="2"](42.43,1.41,42.66,1.79);
);
out tags bb;
Q
curl -sS -m 200 -A "$UA" -o ovp1.json -w "  -> %{http_code} %{size_download}o %{content_type}\n" --data-urlencode "data@q1.txt" "https://overpass-api.de/api/interpreter"
python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/ovp1.json"))
    print("   base OSM du", d.get("osm3s", {}).get("timestamp_osm_base"), "|", d.get("osm3s", {}).get("copyright"))
    for e in d.get("elements", []):
        t = e.get("tags", {})
        b = e.get("bounds", {})
        keep = {k: t[k] for k in ("name", "name:fr", "type", "boundary", "admin_level", "ISO3166-1", "ISO3166-2", "land_area", "border_type", "maritime", "wikidata", "place", "note") if k in t}
        print("   rel", e.get("id"), "| bbox", [b.get(k) for k in ("minlat", "minlon", "maxlat", "maxlon")], "|", json.dumps(keep, ensure_ascii=False)[:330])
except Exception as e:
    print("   ERREUR", e, open("/tmp/sonde/ovp1.json", errors="replace").read()[:400])
PY
echo "--- licence OSM et politique d'usage d'Overpass"
get osm-c.html "https://www.openstreetmap.org/copyright"
texte osm-c.html 60000 | grep -i -E "open data, licensed|Open Database License|free to copy|credit|attribution|contributors" | awk 'length($0) > 25' | c300 | head -10
get ovp-c.html "https://dev.overpass-api.de/overpass-doc/en/preface/commons.html"
texte ovp-c.html 60000 | grep -i -E "queries per day|per day|10[ ,.]?000|1 ?GB|heavy use|own instance|disturb" | c300 | head -8
echo "--- extraits Geofabrik et polygones terrestres OSM (en-têtes seulement)"
tete "https://download.geofabrik.de/europe/monaco-latest.osm.pbf"
tete "https://download.geofabrik.de/europe/andorra-latest.osm.pbf"
tete "https://osmdata.openstreetmap.de/download/land-polygons-split-4326.zip"
tete "https://osmdata.openstreetmap.de/download/land-polygons-complete-4326.zip"

echo
echo "##### E. geoBoundaries (Andorre, Monaco)"
for iso in MCO AND; do
  get gb.json "https://www.geoboundaries.org/api/current/gbOpen/$iso/ADM0/"
  python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/gb.json"))
    for k in ("boundaryID", "boundaryName", "boundaryISO", "boundaryYearRepresented", "boundaryType", "boundaryCanonical", "boundarySource", "boundaryLicense", "licenseDetail", "licenseSource", "boundarySourceURL", "sourceDataUpdateDate", "buildDate", "admUnitCount", "meanVertices", "minVertices", "maxVertices", "meanPerimeterLengthKM", "meanAreaSqKM", "gjDownloadURL", "simplifiedGeometryGeoJSON", "staticDownloadLink"):
        print("  ", k, ":", str(d.get(k))[:260])
    open("/tmp/sonde/gb-url.txt", "w").write(d.get("gjDownloadURL") or "")
except Exception as e:
    print("   ERREUR", e); open("/tmp/sonde/gb-url.txt", "w").write("")
PY
  u=$(cat gb-url.txt)
  if [ -n "$u" ]; then
    get "gb-$iso.geojson" "$u"
    python3 - "gb-$iso.geojson" <<'PY'
import sys
from osgeo import ogr, osr
ogr.UseExceptions()
try:
    ds = ogr.Open(sys.argv[1]); lyr = ds.GetLayer(0)
    src = lyr.GetSpatialRef(); src.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    dst = osr.SpatialReference(); dst.ImportFromEPSG(3035); dst.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    tr = osr.CoordinateTransformation(src, dst)
    for f in lyr:
        g = f.GetGeometryRef(); env = g.GetEnvelope()
        n = sum(r.GetPointCount() for p in (g if g.GetGeometryName() == "MULTIPOLYGON" else [g]) for r in p)
        g2 = g.Clone(); g2.Transform(tr)
        print("   entite", {k: f.GetField(k) for k in f.keys()}, "| type", g.GetGeometryName(), "| sommets", n, "| emprise lon/lat", [round(v, 5) for v in env], "| surface km2 (EPSG:3035)", round(g2.GetArea() / 1e6, 4))
except Exception as e:
    print("   ERREUR", e)
PY
  fi
done

echo
echo "##### F. Référence France (Etalab) : en-têtes"
tete "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/departements-5m.geojson.gz"
echo "FIN frontieres-1"
