#!/usr/bin/env bash
# Vérifie les fonds de carte, le géocodage et le listing Arcep depuis un runner.
set -u
. "$(dirname "$0")/_lib.sh"

echo "##### 1. Styles vectoriels Plan IGN"
for s in classique standard; do
  get "$T/$s.json" "https://data.geopf.fr/annexes/ressources/vectorTiles/styles/PLAN.IGN/$s.json"
done
python3 - <<'PY'
import json, collections
for s in ("classique", "standard"):
    try:
        d = json.load(open(f"/tmp/sonde/{s}.json"))
    except Exception as e:
        print(s, "ERREUR", e); continue
    L = d["layers"]
    print(f"[{s}] name={d.get('name')!r} version={d.get('version')} cles={sorted(d.keys())}")
    print("   sources:", json.dumps(d.get("sources"), ensure_ascii=False)[:900])
    print("   sprite:", d.get("sprite"), "| glyphs:", d.get("glyphs"))
    print("   couches:", len(L), dict(collections.Counter(l["type"] for l in L)))
    i = next((i for i, l in enumerate(L) if l["type"] == "symbol"), None)
    print("   premiere couche symbol: index", i, "id", L[i]["id"] if i is not None else None)
    print("   ids 0..5:", [l["id"] for l in L[:6]])
    fonts = sorted({f for l in L for f in (l.get("layout", {}).get("text-font") or []) if isinstance(f, str)})
    print("   polices:", fonts)
PY

echo "##### 2. Source vectorielle PLAN.IGN (metadata TMS)"
get "$T/tms.json" "https://data.geopf.fr/tms/1.0.0/PLAN.IGN/metadata.json"
head -c 1500 "$T/tms.json"; echo

echo "##### 3. WMTS Geoplateforme GetCapabilities"
get "$T/geopf.xml" "https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetCapabilities"
python3 - <<'PY'
import xml.etree.ElementTree as ET
ns = {"w": "http://www.opengis.net/wmts/1.0", "o": "http://www.opengis.net/ows/1.1"}
root = ET.parse("/tmp/sonde/geopf.xml").getroot()
want = ("GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2", "ORTHOIMAGERY.ORTHOPHOTOS", "ELEVATION.ELEVATIONGRIDCOVERAGE.SHADOW",
        "GEOGRAPHICALGRIDSYSTEMS.MAPS", "ELEVATION.SLOPES", "GEOGRAPHICALGRIDSYSTEMS.MAPS.SCAN25TOUR")
layers = root.findall(".//w:Layer", ns)
print("nb couches:", len(layers))
for l in layers:
    ident = l.findtext("o:Identifier", namespaces=ns)
    if ident in want or ident.startswith("ELEVATION.ELEVATIONGRIDCOVERAGE") or ident.startswith("GEOGRAPHICALGRIDSYSTEMS.PLANIGN"):
        fmts = [f.text for f in l.findall("w:Format", ns)]
        styles = [s.findtext("o:Identifier", namespaces=ns) for s in l.findall("w:Style", ns)]
        tms = []
        for t in l.findall("w:TileMatrixSetLink", ns):
            name = t.findtext("w:TileMatrixSet", namespaces=ns)
            lim = [x.findtext("w:TileMatrix", namespaces=ns) for x in t.findall(".//w:TileMatrixLimits", ns)]
            tms.append((name, (lim[0], lim[-1]) if lim else None))
        bbox = l.find("o:WGS84BoundingBox", ns)
        bb = (bbox.findtext("o:LowerCorner", namespaces=ns), bbox.findtext("o:UpperCorner", namespaces=ns)) if bbox is not None else None
        print(f"- {ident} | titre={l.findtext('o:Title', namespaces=ns)!r} | formats={fmts} | styles={styles} | tms={tms} | bbox={bb}")
PY
get "$T/t1.png" "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&TILEMATRIXSET=PM&TILEMATRIX=12&TILECOL=2114&TILEROW=1470&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&FORMAT=image/png&STYLE=normal"
get "$T/t2.jpg" "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&TILEMATRIXSET=PM&TILEMATRIX=12&TILECOL=2114&TILEROW=1470&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&FORMAT=image/jpeg&STYLE=normal"
get "$T/t3.png" "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&TILEMATRIXSET=PM&TILEMATRIX=12&TILECOL=2114&TILEROW=1470&LAYER=ELEVATION.ELEVATIONGRIDCOVERAGE.SHADOW&FORMAT=image/png&STYLE=estompage_grayscale"
curl -sS -I -m 60 "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&TILEMATRIXSET=PM&TILEMATRIX=12&TILECOL=2114&TILEROW=1470&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&FORMAT=image/png&STYLE=normal" | grep -i -E "^(HTTP|access-control|cache-control|content-type)"

echo "##### 4. swisstopo WMTS"
get "$T/ch.xml" "https://wmts.geo.admin.ch/EPSG/3857/1.0.0/WMTSCapabilities.xml"
python3 - <<'PY'
import xml.etree.ElementTree as ET
ns = {"w": "http://www.opengis.net/wmts/1.0", "o": "http://www.opengis.net/ows/1.1"}
try:
    root = ET.parse("/tmp/sonde/ch.xml").getroot()
    for l in root.findall(".//w:Layer", ns):
        ident = l.findtext("o:Identifier", namespaces=ns)
        if ident in ("ch.swisstopo.pixelkarte-farbe", "ch.swisstopo.swissimage", "ch.bakom.mobilnetz-4g", "ch.bakom.mobilnetz-5g", "ch.bakom.mobilnetz-3g", "ch.bakom.mobilnetz-2g"):
            fmts = [f.text for f in l.findall("w:Format", ns)]
            dims = [(d.findtext("o:Identifier", namespaces=ns), d.findtext("w:Default", namespaces=ns), [v.text for v in d.findall("w:Value", ns)][:6]) for d in l.findall("w:Dimension", ns)]
            tms = [t.findtext("w:TileMatrixSet", namespaces=ns) for t in l.findall("w:TileMatrixSetLink", ns)]
            res = [r.get("template") for r in l.findall("w:ResourceURL", ns)]
            print(f"- {ident} | titre={l.findtext('o:Title', namespaces=ns)!r} | formats={fmts} | dims={dims} | tms={tms} | url={res}")
    for t in root.findall(".//w:Contents/w:TileMatrixSet", ns):
        ids = [m.findtext("o:Identifier", namespaces=ns) for m in t.findall("w:TileMatrix", ns)]
        print("  TMS", t.findtext("o:Identifier", namespaces=ns), "niveaux", ids[0], "a", ids[-1])
except Exception as e:
    print("ERREUR", e)
PY
get "$T/ch1.jpg" "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-farbe/default/current/3857/12/2133/1451.jpeg"
get "$T/ch2.jpg" "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-farbe/default/current/3857/17/68270/46450.jpeg"
get "$T/ch3.jpg" "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-farbe/default/current/3857/6/32/22.jpeg"
curl -sS -I -m 60 "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-farbe/default/current/3857/12/2133/1451.jpeg" | grep -i -E "^(HTTP|access-control|cache-control|content-type)"

echo "##### 5. IGN España WMTS"
get "$T/es.xml" "https://www.ign.es/wmts/mapa-raster?service=WMTS&request=GetCapabilities"
python3 - <<'PY'
import xml.etree.ElementTree as ET
ns = {"w": "http://www.opengis.net/wmts/1.0", "o": "http://www.opengis.net/ows/1.1"}
try:
    root = ET.parse("/tmp/sonde/es.xml").getroot()
    print("AccessConstraints:", root.findtext(".//o:AccessConstraints", namespaces=ns), "| Fees:", root.findtext(".//o:Fees", namespaces=ns))
    for l in root.findall(".//w:Layer", ns):
        ident = l.findtext("o:Identifier", namespaces=ns)
        fmts = [f.text for f in l.findall("w:Format", ns)]
        styles = [s.findtext("o:Identifier", namespaces=ns) for s in l.findall("w:Style", ns)]
        tms = [t.findtext("w:TileMatrixSet", namespaces=ns) for t in l.findall("w:TileMatrixSetLink", ns)]
        print(f"- {ident} | titre={l.findtext('o:Title', namespaces=ns)!r} | formats={fmts} | styles={styles} | tms={tms}")
    for t in root.findall(".//w:Contents/w:TileMatrixSet", ns):
        ids = [m.findtext("o:Identifier", namespaces=ns) for m in t.findall("w:TileMatrix", ns)]
        print("  TMS", t.findtext("o:Identifier", namespaces=ns), "niveaux", ids[0], "a", ids[-1])
except Exception as e:
    print("ERREUR", e)
PY
get "$T/es1.jpg" "https://www.ign.es/wmts/mapa-raster?service=WMTS&request=GetTile&version=1.0.0&layer=MTN&style=default&tilematrixset=GoogleMapsCompatible&format=image/jpeg&TileMatrix=12&TileCol=2058&TileRow=1508"
curl -sS -I -m 60 "https://www.ign.es/wmts/mapa-raster?service=WMTS&request=GetTile&version=1.0.0&layer=MTN&style=default&tilematrixset=GoogleMapsCompatible&format=image/jpeg&TileMatrix=12&TileCol=2058&TileRow=1508" | grep -i -E "^(HTTP|access-control|cache-control|content-type)"

echo "##### 6. OpenTopoMap"
for h in a b c; do get "$T/otm.png" "https://$h.tile.opentopomap.org/12/2136/1470.png"; done
get "$T/otm0.png" "https://tile.opentopomap.org/12/2136/1470.png"
curl -sS -I -m 60 "https://a.tile.opentopomap.org/12/2136/1470.png" | grep -i -E "^(HTTP|access-control|cache-control|content-type)"

echo "##### 7. Géocodage IGN"
get "$T/geocap.json" "https://data.geopf.fr/geocodage/getCapabilities"
python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/geocap.json"))
    print("cles:", list(d.keys()))
    print("info:", json.dumps(d.get("info"), ensure_ascii=False)[:600])
    for op in d.get("operations", []):
        print("- operation", op.get("id"), op.get("url"), "methodes", op.get("methods"))
        for p in op.get("parameters", []):
            print("    param", p.get("name"), "| requis:", p.get("required"), "| defaut:", p.get("default"), "| valeurs:", str(p.get("values"))[:160], "|", (p.get("description") or "")[:150])
    for ix in d.get("indexes", []):
        print("- index", ix.get("id"), "|", (ix.get("description") or "")[:120], "| champs:", [f.get("name") for f in ix.get("fields", [])][:40])
except Exception as e:
    print("ERREUR", e)
PY
get "$T/g1.json" "https://data.geopf.fr/geocodage/search?q=lac%20blanc%20chamonix&limit=3"
head -c 1200 "$T/g1.json"; echo
get "$T/g2.json" "https://data.geopf.fr/geocodage/search?q=refuge%20du%20lac%20blanc&index=poi&limit=3"
head -c 1800 "$T/g2.json"; echo
get "$T/g3.json" "https://data.geopf.fr/geocodage/search?q=brian&index=address,poi&limit=4&autocomplete=1"
head -c 1500 "$T/g3.json"; echo
get "$T/g4.json" "https://data.geopf.fr/geocodage/completion?text=col%20du%20lautaret&type=PositionOfInterest,StreetAddress&maximumResponses=4"
head -c 1500 "$T/g4.json"; echo
curl -sS -I -m 60 "https://data.geopf.fr/geocodage/search?q=gap&limit=1" | grep -i -E "^(HTTP|access-control|x-rate|ratelimit|content-type)"

echo "##### 8. Photon"
get "$T/p1.json" "https://photon.komoot.io/api/?q=zermatt&limit=2&lang=fr"
head -c 1500 "$T/p1.json"; echo
get "$T/p2.json" "https://photon.komoot.io/api/?q=refugi%20de%20coma%20pedrosa&limit=2&lang=es"
head -c 300 "$T/p2.json"; echo
get "$T/p3.json" "https://photon.komoot.io/api/?q=ordino&limit=2&lang=ca"
head -c 300 "$T/p3.json"; echo
curl -sS -I -m 60 "https://photon.komoot.io/api/?q=zermatt&limit=1" | grep -i -E "^(HTTP|access-control|content-type)"

echo "##### 9. Listing Arcep"
get "$T/arcep.html" "https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/00_Metropole/"
python3 - <<'PY'
import re, html
s = open("/tmp/sonde/arcep.html", encoding="utf-8", errors="replace").read()
print("taille html", len(s))
rows = re.findall(r'<a href="([^"]+)">[^<]*</a>\s*([0-9]{2}-[A-Za-z]{3}-[0-9]{4} [0-9:]+)?\s*([0-9.]+[KMG]?|-)?', s)
for href, date, size in rows:
    print(" ", html.unescape(href), "|", date, "|", size)
if not rows:
    print(s[:3000])
PY
get "$T/arcep_last.html" "https://data.arcep.fr/mobile/couvertures_theoriques/"
sed -e 's/<[^>]*>/ /g' "$T/arcep_last.html" | tr -s ' \n' | head -c 1500; echo

echo "##### 10. Contours administratifs Etalab"
get "$T/eta.html" "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/"
sed -e 's/<[^>]*>/ /g' "$T/eta.html" | tr -s ' \n' | head -c 800; echo
get "$T/eta2.html" "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/"
sed -e 's/<[^>]*>/ /g' "$T/eta2.html" | tr -s ' \n' | head -c 2500; echo
echo "FIN"
