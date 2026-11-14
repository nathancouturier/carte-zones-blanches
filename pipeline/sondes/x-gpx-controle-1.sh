#!/usr/bin/env bash
# Sonde gpx-controle-1 : les deux GPX de test contre les contours officiels.
# France : Etalab (départements), Italie : ISTAT (Vallée d'Aoste, lecture distante), Espagne : IGN España (Aragon).
# Trois sources, interrogées l'une après l'autre. Sortie compacte.
set -u
. "$(dirname "$0")/_lib.sh"
cd "$T"
cat > traces.b64 <<'B64'
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
B64
export GDAL_HTTP_USERAGENT="$UA"
echo "### 1. France : Etalab, contours des départements (celui du pipeline)"
get dep.geojson.gz "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/departements-5m.geojson.gz"
gzip -dc dep.geojson.gz > dep.geojson && ls -l dep.geojson | awk '{print "  décompressé : " $5 " o"}'
sleep 3
echo "### 2. Espagne : IGN España, API OGC Features, Aragón (34020000000)"
get es.geojson "https://api-features.ign.es/collections/administrativeunit/items?f=json&nationalcode=34020000000"
sleep 3
echo "### 3. Italie : ISTAT, régions au 1er janvier 2026, Vallée d'Aoste (lecture distante de l'archive)"
cat > c.py <<'PY'
import base64, json, lzma, math, sys
from osgeo import gdal, ogr, osr
gdal.UseExceptions()
tr = json.loads(lzma.decompress(base64.b64decode(open("traces.b64").read())))
R = 6371008.8
def hav(lat1, lon1, lat2, lon2):
    r = math.pi / 180
    a = math.sin((lat2 - lat1) * r / 2) ** 2 + math.cos(lat1 * r) * math.cos(lat2 * r) * math.sin((lon2 - lon1) * r / 2) ** 2
    return 2 * R * math.asin(min(1, math.sqrt(a)))
cum = {}
for k, pts in tr.items():
    c = [0.0]
    for i in range(1, len(pts)):
        c.append(c[-1] + hav(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1]))
    cum[k] = c
wgs = osr.SpatialReference(); wgs.ImportFromEPSG(4326); wgs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
def load(path, where=None, boxes=None, label=""):
    ds = gdal.OpenEx(path, gdal.OF_VECTOR)
    lyr = ds.GetLayer(0)
    srs = lyr.GetSpatialRef()
    if srs is not None:
        srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    if where:
        lyr.SetAttributeFilter(where)
    to = osr.CoordinateTransformation(srs, wgs) if srs is not None and not srs.IsSame(wgs) else None
    defn = lyr.GetLayerDefn()
    names = [defn.GetFieldDefn(i).GetName() for i in range(defn.GetFieldCount())]
    feats = []
    for f in lyr:
        g = f.GetGeometryRef().Clone()
        if to: g.Transform(to)
        e = g.GetEnvelope()
        if boxes and not any(not (e[1] < b[0] or e[0] > b[2] or e[3] < b[1] or e[2] > b[3]) for b in boxes):
            continue
        feats.append(({n: f.GetField(n) for n in names[:4]}, g))
    print(f"  {label} : {lyr.GetFeatureCount()} entité(s) lue(s) après filtre, {len(feats)} gardée(s) près des tracés ; SCR {srs.GetAuthorityCode(None) if srs else None} ; champs {names[:8]}")
    for a, g in feats:
        print("    entité", json.dumps(a, ensure_ascii=False)[:160], "| valide", g.IsValid())
    return feats
BOXES = [[6.70, 45.68, 6.92, 45.80], [-0.05, 42.65, 0.03, 42.74]]
fr = load("dep.geojson", boxes=BOXES, label="France (départements)")
es = load("es.geojson", label="Espagne (Aragón)")
gdal.SetConfigOption("CPL_VSIL_CURL_CHUNK_SIZE", "1048576")
gdal.SetConfigOption("CPL_VSIL_SHOW_NETWORK_STATS", "YES")
url = "https://www.istat.it/storage/cartografia/confini_amministrativi/non_generalizzati/2026/Limiti01012026.zip"
it = load(f"/vsizip//vsicurl/{url}/Reg01012026/Reg01012026_WGS84.shp", where="COD_REG = 2", label="Italie (ISTAT, COD_REG = 2)")
print("### 4. Appartenance des points et franchissements")
def union(feats):
    u = None
    for _, g in feats:
        u = g.Clone() if u is None else u.Union(g)
    return u
pays = {"FR": union(fr), "IT": union(it), "ES": union(es)}
for k, pts in tr.items():
    c = cum[k]
    etats = []
    for lat, lon in pts:
        p = ogr.Geometry(ogr.wkbPoint); p.AddPoint_2D(lon, lat)
        etats.append("+".join(n for n, g in pays.items() if g is not None and g.Contains(p)) or "aucun")
    runs = []
    for i, e in enumerate(etats):
        if runs and runs[-1][0] == e:
            runs[-1][2] = i
        else:
            runs.append([e, i, i])
    print(f"  {k} : {len(pts)} points, {c[-1]/1000:.3f} km ; suites :", " | ".join(f"{e} pts {a}-{b} (km {c[a]/1000:.3f}-{c[b]/1000:.3f})" for e, a, b in runs))
    line = ogr.Geometry(ogr.wkbLineString)
    for lat, lon in pts:
        line.AddPoint_2D(lon, lat)
    for n, g in pays.items():
        if g is None:
            continue
        x = line.Intersection(g.Boundary())
        sub = [x.GetGeometryRef(i) for i in range(x.GetGeometryCount())] if x.GetGeometryCount() else ([x] if not x.IsEmpty() else [])
        res = []
        for q in sub:
            if q.GetGeometryName() != "POINT":
                res.append(q.GetGeometryName()); continue
            lon, lat = q.GetX(), q.GetY()
            best = None
            for i in range(len(pts) - 1):
                (a1, o1), (a2, o2) = pts[i], pts[i + 1]
                dx, dy = o2 - o1, a2 - a1
                L = dx * dx + dy * dy
                t = 0 if L == 0 else max(0, min(1, ((lon - o1) * dx + (lat - a1) * dy) / L))
                d = math.hypot(o1 + t * dx - lon, a1 + t * dy - lat)
                if best is None or d < best[0]:
                    best = (d, c[i] + t * (c[i + 1] - c[i]))
            res.append(f"km {best[1]/1000:.3f} ({lat:.6f} N, {lon:.6f} E)")
        print(f"    limite {n} coupée {len(sub)} fois : {', '.join(res) if res else 'jamais'}")
    print(f"    départ : {etats[0]}, arrivée : {etats[-1]}")
PY
python3 -I c.py > out.txt 2> err.txt; echo "  code $?"
grep -v '^[[:space:]]*[]{}"[]' out.txt | cut -c1-400 | head -60
echo "### 5. Requêtes de la lecture distante (statistiques réseau de GDAL)"
cat out.txt err.txt | grep -v '^Warning' | grep -E '"(count|downloaded_bytes|uploaded_bytes)"|ERROR|Error|Traceback' | tr -s ' ' | head -12 | tr '\n' ' ' | cut -c1-600; echo
grep -E 'Traceback|Error' -A3 err.txt | head -8 | cut -c1-300
echo "### fin"
