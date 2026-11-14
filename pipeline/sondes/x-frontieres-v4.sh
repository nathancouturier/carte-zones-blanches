#!/usr/bin/env bash
# Contre-vérification « Frontières et masques de pays », sonde frontieres-v4 (petite sonde de clôture).
# 1. Geofabrik : nouvelle mesure de disponibilité depuis un runner. 2. Monaco : Mareterra est-il dans la terre ferme ?
# 3. Italie : à quelle région appartiennent les deux anneaux intérieurs du masque (Piémont, Val d'Aoste, Ligurie) ?
set -u
. "$(dirname "$0")/_lib.sh"
# Client générique : aucun identifiant personnel dans les requêtes vers des services tiers.
UA="sonde-verification/1.0"
export GDAL_HTTP_USERAGENT="$UA"
cd "$T"
mkdir -p py d/mc
IT_URL="https://www.istat.it/storage/cartografia/confini_amministrativi/non_generalizzati/2026/Limiti01012026.zip"
MC_URL="https://download.geofabrik.de/europe/monaco-latest.osm.pbf"

echo "##### 1. GEOFABRIK : disponibilite"
date -u +"   heure UTC : %Y-%m-%d %H:%M:%S"
echo "   adresses de download.geofabrik.de : $(getent ahosts download.geofabrik.de 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')"
ok=1
for i in 1 2 3; do
  code=$(curl -sS -L -m 120 -A "$UA" -o d/mc/monaco-latest.osm.pbf -w "%{http_code} %{size_download}o en %{time_total}s (serveur %{remote_ip})" "$MC_URL" 2>&1 | tr '\n' ' ' | cut -c1-200)
  echo "   essai $i : $code  $MC_URL"
  case "$code" in 200*) ok=0; break ;; esac
  rm -f d/mc/monaco-latest.osm.pbf; sleep 15
done
if [ "$ok" -ne 0 ]; then
  echo "   Geofabrik injoignable : repli sur l'API OSM"
  get d/mc/api-36990.osm "https://api.openstreetmap.org/api/0.6/relation/36990/full"
fi
cat > py/v4.py <<'PY_FIN_SONDE'
# Contre-vérification « frontières », sonde v4 : trois points restés en suspens après les sondes v1 à v3.
#  1. Monaco : le quartier gagné sur la mer (Mareterra) est-il dans la terre ferme de la relation 36990 ?
#  2. Italie : à quelle région appartiennent les deux anneaux intérieurs (19,3 et 18,0 ha) du masque italien ?
import math
import os
import sys

from osgeo import gdal, ogr, osr

gdal.UseExceptions()
ogr.UseExceptions()
osr.UseExceptions()

D, IT_SRC = sys.argv[1], sys.argv[2]


def srs(epsg):
    s = osr.SpatialReference()
    s.ImportFromEPSG(epsg)
    s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return s


WGS, LAEA = srs(4326), srs(3035)


def vers(src, dst):
    a = src.Clone()
    a.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return osr.CoordinateTransformation(a, dst)


WGS_LAEA = vers(WGS, LAEA)


def c(s, n=300):
    s = str(s)
    return s if len(s) <= n else s[: n - 3] + "..."


def laea(g):
    k = g.Clone()
    k.Transform(WGS_LAEA)
    return k


def point(lon, lat):
    p = ogr.Geometry(ogr.wkbPoint)
    p.AddPoint_2D(lon, lat)
    return p


def lignes(g, ml):
    if g.GetGeometryName() in ("LINESTRING", "LINEARRING"):
        ls = ogr.Geometry(ogr.wkbLineString)
        for i in range(g.GetPointCount()):
            x, y = g.GetPoint_2D(i)
            ls.AddPoint_2D(x, y)
        ml.AddGeometry(ls)
    else:
        for i in range(g.GetGeometryCount()):
            lignes(g.GetGeometryRef(i), ml)


def attributs(f):
    out = []
    for i in range(f.GetFieldCount()):
        if f.IsFieldSetAndNotNull(i):
            out.append("%s=%s" % (f.GetFieldDefnRef(i).GetName(), c(f.GetField(i), 70)))
    return " | ".join(out)


def monaco():
    p = None
    for nom in ("monaco-latest.osm.pbf", "api-36990.osm", "monaco-latest.osm"):
        if os.path.exists(os.path.join(D, "mc", nom)) and os.path.getsize(os.path.join(D, "mc", nom)) > 0:
            p = os.path.join(D, "mc", nom)
            break
    print("   source : %s (%d octets)" % (os.path.basename(p), os.path.getsize(p)))
    ds = ogr.Open(p)
    lyr = ds.GetLayerByName("other_relations")
    lyr.SetAttributeFilter("osm_id = '36990'")
    f = lyr.GetNextFeature()
    ml = ogr.Geometry(ogr.wkbMultiLineString)
    lignes(f.GetGeometryRef(), ml)
    faces = ml.Polygonize()
    terre = None
    for i in range(faces.GetGeometryCount()):
        g = faces.GetGeometryRef(i)
        terre = g.Clone() if terre is None else terre.Union(g)
    ds = None
    terre_l = laea(terre)
    bord = terre_l.Boundary()
    print("   terre ferme (relation 36990) : %.4f km2" % (terre_l.GetArea() / 1e6))
    for lib, lon, lat in (
        ("point de l'enqueteur", 7.4322, 43.7412), ("point de la sonde v1", 7.4330, 43.7405),
        ("50 m plus a l'ouest", 7.4324, 43.7405), ("100 m plus a l'ouest", 7.4318, 43.7405),
        ("vers le nord-est du quartier", 7.4335, 43.7418), ("vers le sud-ouest du quartier", 7.4312, 43.7400),
        ("150 m plus au large", 7.4348, 43.7400)):
        pt = point(lon, lat)
        print("     %-32s (%.4f, %.4f) : %s, a %.0f m du bord de la terre ferme" % (
            lib, lon, lat, "DEDANS" if terre.Contains(pt) else "DEHORS", laea(pt).Distance(bord)))
    # Objets de l'extrait dont le nom parle de Mareterra ou de l'anse du Portier
    vus = 0
    for couche in ("multipolygons", "points", "lines"):
        ds = ogr.Open(p)
        lyr = ds.GetLayerByName(couche)
        if lyr is None:
            continue
        for f in lyr:
            nom = f.GetField("name") if f.GetFieldIndex("name") >= 0 else None
            if not nom or not any(m in nom.lower() for m in ("mareterra", "anse du portier")):
                continue
            g = f.GetGeometryRef()
            vus += 1
            if vus > 8:
                break
            msg = "     objet %s : %s | %s" % (couche, c(attributs(f), 200), g.GetGeometryName())
            if g.GetGeometryName() in ("POLYGON", "MULTIPOLYGON"):
                gl = laea(g)
                inter = gl.Intersection(terre_l).GetArea()
                msg += " | %.2f ha, dont %.1f %% dans la terre ferme" % (gl.GetArea() / 1e4, 100.0 * inter / gl.GetArea() if gl.GetArea() else 0.0)
            else:
                ct = g.Centroid()
                msg += " | centre (%.4f, %.4f) %s" % (ct.GetX(), ct.GetY(), "DEDANS" if terre.Contains(ct) else "DEHORS")
            print(msg)
        ds = None
    if vus == 0:
        print("     aucun objet nomme Mareterra ou Anse du Portier dans cette source")


def italie():
    ds = ogr.Open(IT_SRC)
    lyr = ds.GetLayer(0)
    to_wgs = vers(lyr.GetSpatialRef(), WGS)
    regions = []
    for f in lyr:
        g = f.GetGeometryRef().Clone()
        g.Transform(to_wgs)
        regions.append((f.GetField("COD_REG"), f.GetField("DEN_REG"), g))
    print("   %d regions lues par %s" % (len(regions), c(IT_SRC, 120)))
    for lib, lon, lat in (("anneau de 19,3 ha", 8.7053, 45.0180), ("anneau de 18,0 ha", 8.8138, 45.0193)):
        pt = point(lon, lat)
        dans = ["%s=%s" % (cod, den) for cod, den, g in regions if g.Contains(pt)]
        print("     %s, centre (%.4f, %.4f) : contenu dans %s" % (lib, lon, lat, dans or "AUCUNE REGION"))
    for cod, den, g in regions:
        if cod not in (1, 2, 7):
            continue
        n = 0
        details = []
        polys = [g] if g.GetGeometryName() == "POLYGON" else [g.GetGeometryRef(i) for i in range(g.GetGeometryCount())]
        for poly in polys:
            for i in range(1, poly.GetGeometryCount()):
                n += 1
                t = ogr.Geometry(ogr.wkbPolygon)
                t.AddGeometry(poly.GetGeometryRef(i).Clone())
                ct = t.Centroid()
                details.append("%.1f ha vers (%.4f, %.4f)" % (laea(t).GetArea() / 1e4, ct.GetX(), ct.GetY()))
        print("     region %s (%s) : %d polygone(s), %d anneau(x) interieur(s) %s" % (cod, den, len(polys), n, "; ".join(details[:6])))
    # Morceaux de Lombardie entièrement entourés par le Piémont
    piemonte = [g for cod, den, g in regions if cod == 1][0]
    plein = ogr.Geometry(ogr.wkbPolygon)
    ext = (piemonte if piemonte.GetGeometryName() == "POLYGON" else piemonte.GetGeometryRef(0)).GetGeometryRef(0)
    plein.AddGeometry(ext.Clone())
    for cod, den, g in regions:
        if cod in (1, 2, 7):
            continue
        polys = [g] if g.GetGeometryName() == "POLYGON" else [g.GetGeometryRef(i) for i in range(g.GetGeometryCount())]
        for poly in polys:
            if poly.Within(plein):
                ct = poly.Centroid()
                print("     morceau de %s=%s entierement entoure par le Piemont : %.1f ha vers (%.4f, %.4f)" % (cod, den, laea(poly).GetArea() / 1e4, ct.GetX(), ct.GetY()))


for nom, fn in (("MONACO : Mareterra", monaco), ("ITALIE : anneaux interieurs du masque", italie)):
    print()
    print("##### " + nom)
    try:
        fn()
    except Exception as exc:  # noqa: BLE001
        import traceback
        print("   !!! EXCEPTION : " + c(traceback.format_exc(), 1200))
PY_FIN_SONDE
python3 -I py/v4.py "$T/d" "/vsizip//vsicurl/$IT_URL/Reg01012026/Reg01012026_WGS84.shp" 2>&1 | grep -v "memory leak" | cut -c1-600
echo "FIN (code python : ${PIPESTATUS[0]})"
