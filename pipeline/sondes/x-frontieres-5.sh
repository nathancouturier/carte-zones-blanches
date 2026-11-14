#!/usr/bin/env bash
# Sonde frontieres-5 : essai d'intégration des masques recommandés avec le code du pipeline (pipeline/czb) :
# chargeurs existants, comblement des trous fermés, rastérisation z12, pixels disputés, comblés, coincés.
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$(dirname "$0")/_lib.sh"
cd "$T"
mkdir -p py5 lic
export DEBIAN_FRONTEND=noninteractive
echo "##### 0. Environnement du pipeline (comme .github/workflows/donnees.yml)"
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends python3-pip >/dev/null 2>&1
python3 -m pip install --break-system-packages -q -r "$REPO/pipeline/requirements.txt" 2>&1 | tail -2
python3 -c "import yaml, PIL, numpy, osgeo; print('   yaml', yaml.__version__, '| pillow', PIL.__version__, '| numpy', numpy.__version__, '| gdal', osgeo.__version__)"
echo "   depot : $REPO ($(cd "$REPO" && git log --oneline -1 2>/dev/null | cut -c1-60))"
cat > py5/combler_trous.py <<'PYEOF'
"""Comblement des petits trous fermés entre masques de pays voisins (proposition pour pipeline/czb/masks.py).

Les contours nationaux ne coïncident pas exactement : le long d'une frontière ils laissent des interstices
(« trous ») que personne ne revendique. Chaque interstice fermé est un anneau intérieur de l'union de tous
les masques. On donne les petits (moins de seuil_ha au sol) au pays de plus faible priorité qui les touche ;
les grands (enclaves, lacs) restent vides. Géométries en EPSG:3857, comme dans load_mask_geometries().
"""
from __future__ import annotations

import math

from osgeo import ogr

RAYON = 6378137.0


def _polygones(g: ogr.Geometry) -> list[ogr.Geometry]:
    if g.GetGeometryName() == "POLYGON":
        return [g]
    out: list[ogr.Geometry] = []
    for i in range(g.GetGeometryCount()):
        out.extend(_polygones(g.GetGeometryRef(i)))
    return out


def _union(geoms: list[ogr.Geometry]) -> ogr.Geometry:
    gc = ogr.Geometry(ogr.wkbGeometryCollection)
    for g in geoms:
        gc.AddGeometry(g if g.IsValid() else g.MakeValid())
    if hasattr(gc, "UnaryUnion"):  # absent des liaisons Python de GDAL 3.8
        return gc.UnaryUnion()
    out = None
    for i in range(gc.GetGeometryCount()):
        out = gc.GetGeometryRef(i).Clone() if out is None else out.Union(gc.GetGeometryRef(i))
    return out


def combler_trous(geoms: dict[str, list[ogr.Geometry]], ordre: list[str], seuil_ha: float = 100.0) -> dict[str, float]:
    """Ajoute à geoms[pays] les trous fermés de moins de seuil_ha. Renvoie la surface ajoutée (ha au sol) par pays."""
    par_pays = {iso: _union(geoms[iso]) for iso in ordre}
    prepares = {iso: (g.GetEnvelope(), g.CreatePreparedGeometry()) for iso, g in par_pays.items()}
    tout = _union([par_pays[iso] for iso in ordre])
    ajoute = {iso: 0.0 for iso in ordre}
    for poly in _polygones(tout):
        for i in range(1, poly.GetGeometryCount()):
            trou = ogr.Geometry(ogr.wkbPolygon)
            trou.AddGeometry(poly.GetGeometryRef(i).Clone())
            x0, x1, y0, y1 = trou.GetEnvelope()
            lat = 2 * math.atan(math.exp((y0 + y1) / 2 / RAYON)) - math.pi / 2
            sol_ha = trou.GetArea() * math.cos(lat) ** 2 / 1e4
            if sol_ha >= seuil_ha:
                continue
            for iso in reversed(ordre):  # le pays de plus faible priorité qui touche le trou
                (m0, m1, n0, n1), prep = prepares[iso]
                if x1 < m0 or x0 > m1 or y1 < n0 or y0 > n1:
                    continue
                if prep.Intersects(trou):
                    geoms[iso].append(trou)
                    ajoute[iso] += sol_ha
                    break
    return ajoute
PYEOF
cat > py5/integration.py <<'PYEOF'
# Essai d'intégration des masques recommandés avec le code du pipeline (pipeline/czb du dépôt) :
# chargement par les chargeurs existants, comblement des trous, rastérisation sur la grille z12 avec la règle
# « le premier qui revendique un pixel le garde », comptage des pixels disputés, comblés et restés coincés.
import json, math, os, sys, time, zipfile
from pathlib import Path

REPO, CFG = sys.argv[1], json.load(open(sys.argv[2], encoding="utf-8"))
sys.path.insert(0, REPO + "/pipeline")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from osgeo import gdal, ogr, osr

from czb.grid import Grid
from czb.masks import _load_etalab_departements, _load_vector_file
from czb.net import download
from czb.raster import geometry_windows, transformer_to_mercator
from combler_trous import combler_trous, _polygones, _union

gdal.SetConfigOption("GDAL_HTTP_USERAGENT", "carte-zones-blanches/1.0 (+https://github.com/nathancouturier/carte-zones-blanches)")

W = Path(CFG["workdir"]); W.mkdir(parents=True, exist_ok=True)
ORDRE = ["FR", "CH", "IT", "ES", "AD", "MC"]
CODE = {iso: i + 1 for i, iso in enumerate(ORDRE)}
FRONTALIERS = ["01", "39", "25", "90", "68", "74", "73", "05", "04", "06", "64", "65", "31", "09", "66"]


def chrono(label, t0):
    print("   [%s : %.1f s]" % (label, time.time() - t0), flush=True)


def sommets(g):
    n = g.GetPointCount()
    for i in range(g.GetGeometryCount()):
        n += sommets(g.GetGeometryRef(i))
    return n


def resume(iso, gs):
    e = [float("inf"), float("-inf"), float("inf"), float("-inf")]
    for g in gs:
        x0, x1, y0, y1 = g.GetEnvelope()
        e = [min(e[0], x0), max(e[1], x1), min(e[2], y0), max(e[3], y1)]
    print("   %s : %d geometrie(s), %d sommets, types %s, emprise EPSG:3857 x %.0f a %.0f, y %.0f a %.0f"
          % (iso, len(gs), sum(sommets(g) for g in gs), sorted({g.GetGeometryName() + (" Z" if g.Is3D() else "") for g in gs}), e[0], e[1], e[2], e[3]), flush=True)


def charge_zip_shp(url, membre, where):
    """Italie : couche d'une archive zip lue à distance (/vsizip//vsicurl), avec un filtre attributaire."""
    ds = ogr.Open("/vsizip//vsicurl/%s/%s" % (url, membre))
    layer = ds.GetLayer(0)
    layer.SetAttributeFilter(where)
    to_merc = transformer_to_mercator(layer.GetSpatialRef())
    out = []
    for feat in layer:
        g = feat.GetGeometryRef().Clone()
        g.Transform(to_merc)
        out.append(g)
    return out


def chemins(g, ml):
    n = g.GetGeometryName()
    if n in ("LINESTRING", "LINEARRING"):
        ls = ogr.Geometry(ogr.wkbLineString)
        for i in range(g.GetPointCount()):
            x, y = g.GetPoint_2D(i)
            ls.AddPoint_2D(x, y)
        ml.AddGeometry(ls)
    else:
        for i in range(g.GetGeometryCount()):
            chemins(g.GetGeometryRef(i), ml)


def charge_osm_land_area(url, relation, workdir):
    """Monaco : relation OSM de type land_area lue dans other_relations (pilote OSM), polygonisée."""
    local = workdir / url.rsplit("/", 1)[-1]
    if not local.exists():
        download(url, local)
    ds = ogr.Open(str(local))
    layer = ds.GetLayerByName("other_relations")
    layer.SetAttributeFilter("osm_id = '%s'" % relation)
    feat = layer.GetNextFeature()
    ml = ogr.Geometry(ogr.wkbMultiLineString)
    chemins(feat.GetGeometryRef(), ml)
    faces = ml.Polygonize()
    to_merc = transformer_to_mercator(layer.GetSpatialRef())
    out = []
    for i in range(faces.GetGeometryCount()):
        g = faces.GetGeometryRef(i).Clone()
        g.Transform(to_merc)
        out.append(g)
    return out


t0 = time.time()
geoms = {}
print("--- chargement par les chargeurs du pipeline")
geoms["FR"] = _load_etalab_departements({"url": CFG["fr"], "metropole_only": True}, {"departements": FRONTALIERS}, W)
resume("FR (15 departements frontaliers)", geoms["FR"])
geoms["CH"] = _load_vector_file({"url": CFG["ch"], "layer": "tlm_landesgebiet", "where": "icc = 'CH'"}, {}, W)
resume("CH", geoms["CH"])
# Italie : le chargeur générique ouvre-t-il l'archive zip telle quelle ? (essai sur l'archive généralisée, plus légère)
try:
    local = W / CFG["it_g"].rsplit("/", 1)[-1]
    download(CFG["it_g"], local)
    ds = ogr.Open(str(local))
    print("   ogr.Open('%s') : %s" % (local.name, "echec" if ds is None else "pilote %s, couches %s" % (ds.GetDriver().GetName(), [ds.GetLayer(i).GetName() for i in range(ds.GetLayerCount())])))
    ds = None
    print("   membres .shp de l'archive generalisee :", [n for n in zipfile.ZipFile(local).namelist() if n.lower().endswith(".shp")])
except Exception as exc:
    print("   ogr.Open sur l'archive zip : exception", str(exc)[:200])
geoms["IT"] = charge_zip_shp(CFG["it"], CFG["it_membre"], "COD_REG IN (1, 2, 7)")
resume("IT", geoms["IT"])
geoms["ES"] = []
for code in CFG["es_codes"]:
    geoms["ES"] += _load_vector_file({"url": CFG["es"] % code, "filename": "es-%s.geojson" % code}, {}, W)
resume("ES", geoms["ES"])
geoms["AD"] = _load_vector_file({"url": CFG["ad"], "layer": "multipolygons", "where": "osm_id = '9407'"}, {}, W)
resume("AD", geoms["AD"])
geoms["MC"] = charge_osm_land_area(CFG["mc"], 36990, W)
resume("MC", geoms["MC"])
chrono("chargement", t0)

print("--- comblement des trous fermes de moins de 100 ha (combler_trous)")
t1 = time.time()
avant = {iso: len(gs) for iso, gs in geoms.items()}
originaux = {iso: list(gs) for iso, gs in geoms.items()}
ajoute = combler_trous(geoms, ORDRE, seuil_ha=100.0)
trous = {iso: geoms[iso][avant[iso]:] for iso in ORDRE}
print("   UnaryUnion disponible dans les liaisons Python :", hasattr(ogr.Geometry(ogr.wkbGeometryCollection), "UnaryUnion"))
print("   trous donnes a chaque pays (nombre, ha au sol) :", {iso: (len(trous[iso]), round(ajoute[iso], 1)) for iso in ORDRE})
chrono("combler_trous, 15 departements", t1)
# Les grands trous laissés vides
t1 = time.time()
tout = _union([g for iso in ORDRE for g in originaux[iso]])
R = 6378137.0
grands = []
for poly in _polygones(tout):
    for i in range(1, poly.GetGeometryCount()):
        h = ogr.Geometry(ogr.wkbPolygon)
        h.AddGeometry(poly.GetGeometryRef(i).Clone())
        x0, x1, y0, y1 = h.GetEnvelope()
        lat = 2 * math.atan(math.exp((y0 + y1) / 2 / R)) - math.pi / 2
        ha = h.GetArea() * math.cos(lat) ** 2 / 1e4
        if ha >= 100:
            grands.append((ha, math.degrees((x0 + x1) / 2 / R), math.degrees(lat)))
print("   trous de 100 ha ou plus laisses vides :", ["%.0f ha vers lon %.3f lat %.3f" % g for g in sorted(grands, reverse=True)])
chrono("union de controle", t1)

print("--- rasterisation sur la grille z%d (le premier pays qui revendique un pixel le garde)" % CFG["zoom"])
t1 = time.time()
e = [float("inf"), float("-inf"), float("inf"), float("-inf")]
for gs in originaux.values():
    for g in gs:
        x0, x1, y0, y1 = g.GetEnvelope()
        e = [min(e[0], x0), max(e[1], x1), min(e[2], y0), max(e[3], y1)]
grid = Grid(zoom=CFG["zoom"], tile_size=256)
canvas = grid.canvas_for_mercator_bounds(e[0], e[2], e[1], e[3])
print("   canevas : tuiles x %d a %d, y %d a %d, soit %d x %d pixels de %.3f m (Mercator)" % (canvas.tx0, canvas.tx1, canvas.ty0, canvas.ty1, canvas.width, canvas.height, grid.resolution))
B = np.memmap(W / "B.bin", dtype=np.uint8, mode="w+", shape=(canvas.height, canvas.width))


def revendique(gs, code, dispute=None):
    gagne = 0
    for g in gs:
        for (c0, r0, w, h), mask in geometry_windows(g, canvas):
            view = B[r0:r0 + h, c0:c0 + w]
            pris = mask & (view != 0)
            if dispute is not None and pris.any():
                vals, cnt = np.unique(view[pris], return_counts=True)
                for v, n in zip(vals.tolist(), cnt.tolist()):
                    if v != code:
                        dispute[(v, code)] = dispute.get((v, code), 0) + n
            libre = mask & (view == 0)
            view[libre] = code
            gagne += int(libre.sum())
    return gagne


def coinces():
    """Pixels sans pays dont le voisinage 3 x 3 contient au moins deux pays différents."""
    total, H = 0, B.shape[0]
    pas = 1024
    for r0 in range(0, H, pas):
        a0, a1 = max(0, r0 - 1), min(H, r0 + pas + 1)
        blk = np.asarray(B[a0:a1])
        presents = [c for c in np.nonzero(np.bincount(blk.ravel(), minlength=16))[0].tolist() if c != 0]
        if len(presents) < 2:
            continue
        n = np.zeros(blk.shape, np.uint8)
        for c in presents:
            m = blk == c
            d = m.copy()
            d[1:, :] |= m[:-1, :]
            d[:-1, :] |= m[1:, :]
            v = d.copy()
            v[:, 1:] |= d[:, :-1]
            v[:, :-1] |= d[:, 1:]
            n += v
        drapeau = (blk == 0) & (n >= 2)
        off = r0 - a0
        total += int(drapeau[off:off + min(pas, H - r0)].sum())
    return total


dispute, gagne = {}, {}
for iso in ORDRE:
    gagne[iso] = revendique(originaux[iso], CODE[iso], dispute)
px_sol = (grid.resolution * math.cos(math.radians(45.0))) ** 2
print("   pixels par pays (masques d'origine) :", gagne)
print("   pixels revendiques deux fois, gardes par le premier (premier, second) :", {"%s puis %s" % (ORDRE[a - 1], ORDRE[b - 1]): n for (a, b), n in sorted(dispute.items())})
chrono("rasterisation des masques", t1)
t1 = time.time()
c_avant = coinces()
print("   pixels sans pays coinces entre deux pays, AVANT comblement :", c_avant)
chrono("comptage", t1)
t1 = time.time()
comble = {iso: revendique(trous[iso], CODE[iso]) for iso in ORDRE}
print("   pixels gagnes par les trous combles :", comble, "| total", sum(comble.values()))
c_apres = coinces()
print("   pixels sans pays coinces entre deux pays, APRES comblement :", c_apres)
chrono("comblement et comptage", t1)

if CFG.get("fr_complet"):
    print("--- duree de combler_trous sur le perimetre complet (tous les departements de metropole)")
    t1 = time.time()
    g2 = {iso: list(originaux[iso]) for iso in ORDRE}
    g2["FR"] = _load_etalab_departements({"url": CFG["fr"], "metropole_only": True}, {}, W)
    resume("FR (metropole entiere)", g2["FR"])
    n0 = {iso: len(v) for iso, v in g2.items()}
    aj = combler_trous(g2, ORDRE, seuil_ha=100.0)
    print("   trous donnes a chaque pays (nombre, ha au sol) :", {iso: (len(g2[iso]) - n0[iso], round(aj[iso], 1)) for iso in ORDRE})
    chrono("combler_trous, metropole entiere", t1)
chrono("total", t0)
PYEOF
cat > cfg5.json <<'JSON'
{"workdir": "/tmp/sonde/w5", "zoom": 12, "fr_complet": true,
 "fr": "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/departements-5m.geojson.gz",
 "ch": "https://data.geo.admin.ch/ch.swisstopo.swissboundaries3d/swissboundaries3d_2026-01/swissboundaries3d_2026-01_2056_5728.gpkg.zip",
 "it": "https://www.istat.it/storage/cartografia/confini_amministrativi/non_generalizzati/2026/Limiti01012026.zip",
 "it_membre": "Reg01012026/Reg01012026_WGS84.shp",
 "it_g": "https://www.istat.it/storage/cartografia/confini_amministrativi/generalizzati/2026/Limiti01012026_g.zip",
 "es": "https://api-features.ign.es/collections/administrativeunit/items?f=json&nationalcode=%s",
 "es_codes": ["34020000000", "34090000000", "34150000000", "34160000000"],
 "ad": "https://download.geofabrik.de/europe/andorra-latest.osm.pbf",
 "mc": "https://download.geofabrik.de/europe/monaco-latest.osm.pbf"}
JSON
echo "##### 1. Essai d'intégration"
python3 -I py5/integration.py "$REPO" cfg5.json 2>&1 | cut -c1-420

echo
echo "##### 2. IGN España : table des produits (identifiant et date pour l'attribution)"
get lic/scne.html "http://www.scne.es/productos.html"
texte lic/scne.html 200000 | grep -i -B1 -A3 -E "BDLJE|l[ií]neas l[ií]mite" | awk 'length($0) > 2' | cut -c1-300 | head -16
echo "FIN frontieres-5"
