#!/usr/bin/env bash
# Sonde frontieres-4 : petits compléments. Monaco terre ferme depuis le PBF Geofabrik (relation 36990, y compris
# les chemins fermés), comparaison avec Overpass ; table d'attribution de l'IGN España ; conditions swisstopo en français.
set -u
. "$(dirname "$0")/_lib.sh"
cd "$T"
mkdir -p py osm lic
c300() { cut -c1-300; }
PYI="python3 -I"

echo "##### A. MONACO : relation 36990 (type=land_area) depuis le PBF Geofabrik"
get osm/monaco-latest.osm.pbf https://download.geofabrik.de/europe/monaco-latest.osm.pbf
printf '%s\n' '[out:json][timeout:60];' 'relation(36990);' 'out geom;' > osm/q4.txt
for i in 1 2 3 4; do
  code=$(curl -sS -m 120 -A "$UA" -o osm/ovp4.json -w "%{http_code} %{size_download}o %{content_type}" --data-urlencode "data@osm/q4.txt" "https://overpass-api.de/api/interpreter" 2>&1)
  echo "  -> $code (essai $i)  POST https://overpass-api.de/api/interpreter  data=$(tr '\n' ' ' < osm/q4.txt)"
  case "$code" in 200*) break ;; esac
  sleep $((i * 20))
done
cat > py/monaco.py <<'PY'
# Recette « Monaco terre ferme » : polygoniser les chemins de la relation 36990 lus dans la couche other_relations
# du pilote OSM de GDAL. Les chemins ouverts arrivent en LINESTRING, les chemins fermés en POLYGON (anneau LINEARRING).
import json, sys
from osgeo import ogr, osr
ogr.UseExceptions(); osr.UseExceptions()


def srs(epsg):
    s = osr.SpatialReference(); s.ImportFromEPSG(epsg); s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER); return s


def chemins(g, ml, compte):
    """Ajoute à ml, comme lignes, tous les chemins contenus dans g (récursif)."""
    n = g.GetGeometryName()
    if n in ("LINESTRING", "LINEARRING"):
        compte[n] = compte.get(n, 0) + 1
        ls = ogr.Geometry(ogr.wkbLineString)
        for i in range(g.GetPointCount()):
            x, y = g.GetPoint_2D(i)
            ls.AddPoint_2D(x, y)
        ml.AddGeometry(ls)
    elif g.GetGeometryCount():
        compte[n] = compte.get(n, 0) + 1
        for i in range(g.GetGeometryCount()):
            chemins(g.GetGeometryRef(i), ml, compte)
    else:
        compte[n] = compte.get(n, 0) + 1


def polygones(ml):
    """Polygonise des lignes jointives et réunit les faces en un multipolygone."""
    faces = ml.Polygonize()
    out = None
    for i in range(faces.GetGeometryCount()):
        p = faces.GetGeometryRef(i)
        out = p.Clone() if out is None else out.Union(p)
    return ogr.ForceToMultiPolygon(out)


def decrit(nom, mp, src):
    t = osr.CoordinateTransformation(src, srs(3035))
    tot = 0.0
    for i in range(mp.GetGeometryCount()):
        p = mp.GetGeometryRef(i)
        q = p.Clone(); q.Transform(t)
        c = p.Centroid()
        tot += q.GetArea()
        print("      polygone %d : %.4f ha, %d sommets, centre lon %.5f lat %.5f" % (i + 1, q.GetArea() / 1e4, p.GetGeometryRef(0).GetPointCount(), c.GetX(), c.GetY()))
    e = mp.GetEnvelope()
    print("   %s : %d polygone(s), %.4f km2 (EPSG:3035), emprise lon %.5f a %.5f, lat %.5f a %.5f" % (nom, mp.GetGeometryCount(), tot / 1e6, e[0], e[1], e[2], e[3]))
    return mp


ds = ogr.Open(sys.argv[1])
lyr = ds.GetLayerByName("other_relations")
lyr.SetAttributeFilter("osm_id = '36990'")
feat = lyr.GetNextFeature()
src = lyr.GetSpatialRef(); src.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
print("   SCR de la couche :", src.GetName(), "EPSG", src.GetAuthorityCode(None), "| name", feat.GetField("name"), "| type", feat.GetField("type"))
ml, compte = ogr.Geometry(ogr.wkbMultiLineString), {}
chemins(feat.GetGeometryRef(), ml, compte)
print("   elements lus :", compte, "->", ml.GetGeometryCount(), "lignes")
pbf = decrit("PBF Geofabrik, other_relations, osm_id = '36990'", polygones(ml), src)
try:
    d = json.load(open(sys.argv[2], encoding="utf-8"))
    rel = d["elements"][0]
    ml2 = ogr.Geometry(ogr.wkbMultiLineString)
    fermes = 0
    for m in rel["members"]:
        if m["type"] == "way" and m.get("geometry"):
            ls = ogr.Geometry(ogr.wkbLineString)
            for p in m["geometry"]:
                ls.AddPoint_2D(p["lon"], p["lat"])
            fermes += int(m["geometry"][0] == m["geometry"][-1])
            ml2.AddGeometry(ls)
    print("   Overpass : base OSM du", d["osm3s"]["timestamp_osm_base"], "|", ml2.GetGeometryCount(), "chemins dont", fermes, "ferme(s)")
    ovp = decrit("Overpass, relation(36990); out geom;", polygones(ml2), src)
    t = osr.CoordinateTransformation(src, srs(3035))
    a, b = pbf.Clone(), ovp.Clone()
    a.Transform(t); b.Transform(t)
    print("   difference symetrique PBF contre Overpass : %.4f ha" % (a.SymDifference(b).GetArea() / 1e4))
except Exception as exc:
    print("   comparaison avec Overpass impossible :", str(exc)[:200])
PY
$PYI py/monaco.py osm/monaco-latest.osm.pbf osm/ovp4.json 2>&1 | c300

echo
echo "##### B. IGN España : formule d'attribution et table des produits"
get lic/ign.pdf "https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf"
export DEBIAN_FRONTEND=noninteractive
(apt-get update -qq && apt-get install -y -qq poppler-utils) >/dev/null 2>&1
if command -v pdftotext >/dev/null 2>&1; then
  pdftotext -layout lic/ign.pdf lic/ign.txt
  grep -v -E '^\s*$' lic/ign.txt | sed -E 's/\s+/ /g' > lic/ign-net.txt
  echo "   lignes du texte : $(wc -l < lic/ign-net.txt)"
  sed -n '14,34p;44,70p' lic/ign-net.txt | cut -c1-260
  echo "--- adresses citées dans la licence"
  grep -o -E '(https?://|www\.)[A-Za-z0-9./_?=&%#-]+' lic/ign-net.txt | sort -u | head -12
  for u in $(grep -o -E '(https?://|www\.)[A-Za-z0-9./_?=&%#-]+' lic/ign-net.txt | sort -u | grep -i -E 'ign\.es|cnig\.es' | grep -v -i '\.pdf' | head -3); do
    case "$u" in http*) ;; *) u="https://$u" ;; esac
    get lic/page.html "$u"
    texte lic/page.html 200000 | grep -i -E "BDLJE|l[ií]neas l[ií]mite|l[ií]mites municipales|recintos|identificador" | awk 'length($0) > 5' | c300 | head -12
  done
else
  echo "   pdftotext indisponible"
fi
get lic/cnig.html "https://centrodedescargas.cnig.es/CentroDescargas/limites-municipales-provinciales-autonomicos"
texte lic/cnig.html 80000 | grep -i -A8 "reconocer siempre la autor" | awk 'length($0) > 3' | cut -c1-400 | head -12

echo
echo "##### C. swisstopo : conditions d'utilisation en français"
get lic/st.html "https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices"
grep -o -E 'href="[^"]*/fr/[^"]*"' lic/st.html | sort -u | grep -i -E "condition|utilisation|geodon|terms" | head -6 | c300
FR=$(grep -o -E 'href="[^"]*/fr/[^"]*"' lic/st.html | sort -u | grep -i -E "condition|utilisation" | head -1 | sed -E 's/^href="//; s/"$//')
for u in "$FR" "https://www.swisstopo.admin.ch/fr/conditions-generales-dutilisation-et-modeles-de-geodonnees" "https://www.swisstopo.admin.ch/fr/conditions-d-utilisation-des-geodonnees-et-geoservices-gratuits"; do
  [ -z "$u" ] && continue
  case "$u" in http*) ;; *) u="https://www.swisstopo.admin.ch$u" ;; esac
  get lic/st-fr.html "$u"
  texte lic/st-fr.html 80000 | grep -i -E "peuvent être utilis|indication de la source|source est obligatoire|mention de la source|mentions? suivantes|©" | awk 'length($0) > 8' | c300 | head -8
done
echo "FIN frontieres-4"
