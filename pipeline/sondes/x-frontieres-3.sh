#!/usr/bin/env bash
# Sonde frontieres-3 : compléments (entités suisses, extraction distante ISTAT, Monaco par Geofabrik, régions italiennes par OSM),
# trous fermés et ouverts le long des frontières communes, grands trous de l'union des masques.
set -u
. "$(dirname "$0")/_lib.sh"
cd "$T"
mkdir -p py ch it es osm fr sel lic
c300() { cut -c1-300; }
tete() { curl -sS -I -L -m 60 -A "$UA" "$1" 2>&1 | tr -d '\r' | grep -i -E '^(HTTP/|content-length|content-type|last-modified)' | tr '\n' ' ' | c300; echo " <= $1"; }
oinfo() { # ogrinfo -so sans le bloc WKT du SCR
  ogrinfo -ro -so -nomd "$@" 2>&1 | awk '/^Layer SRS WKT:/{skip=1; next} skip && /^(Data axis|FID Column|Geometry Column|[A-Za-z_0-9]+: [A-Z][A-Za-z0-9]+ \()/{skip=0} !skip' | c300
}
dezip() { # dezip <archive> <dossier> [motif] [q] : liste l'archive (sauf q) et extrait les entrées qui contiennent le motif
  python3 -I - "$@" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); motif = sys.argv[3] if len(sys.argv) > 3 else ""
infos = z.infolist()
print("   archive : %d entrees, %.1f Mo decompresses" % (len(infos), sum(i.file_size for i in infos) / 1e6))
vus = 0
for i in infos:
    if len(sys.argv) > 4:
        break
    if i.filename.lower().endswith((".shp", ".gpkg", ".gdb/", ".prj", ".cpg")) and vus < 40 and (not motif or motif.lower() in i.filename.lower() or i.filename.lower().endswith((".shp", ".gpkg"))):
        print("     ", i.filename, i.file_size); vus += 1
for i in infos:
    if not motif or motif.lower() in i.filename.lower():
        z.extract(i, sys.argv[2])
PY
}
cat > py/lib_f.py <<'PYLIB'
"""Fonctions communes aux sondes « frontieres » (GDAL/OGR seulement)."""
import json
import math
import sys
import time

from osgeo import gdal, ogr, osr

gdal.UseExceptions()
ogr.UseExceptions()
osr.UseExceptions()


def srs(epsg):
    s = osr.SpatialReference()
    s.ImportFromEPSG(epsg)
    s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return s


L93, WGS, LAEA, MERC = srs(2154), srs(4326), srs(3035), srs(3857)


def tr(src, dst):
    s = src.Clone()
    s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return osr.CoordinateTransformation(s, dst)


def npoints(g):
    n = g.GetPointCount()
    for i in range(g.GetGeometryCount()):
        n += npoints(g.GetGeometryRef(i))
    return n


def parts(g):
    """Polygones élémentaires d'une géométrie quelconque."""
    name = g.GetGeometryName()
    if name == "POLYGON":
        return [g]
    out = []
    for i in range(g.GetGeometryCount()):
        out.extend(parts(g.GetGeometryRef(i)))
    return out


def polys_only(g):
    mp = ogr.Geometry(ogr.wkbMultiPolygon)
    for p in parts(g):
        if not p.IsEmpty():
            mp.AddGeometry(p)
    return mp


def valid(g):
    if g.IsValid():
        return g
    try:
        return polys_only(g.MakeValid())
    except Exception:
        return polys_only(g.Buffer(0))


def uunion(g):
    """Union unaire (GEOS) avec repli pour les anciennes versions de GDAL."""
    if hasattr(g, "UnaryUnion"):
        return g.UnaryUnion()
    out = None
    for i in range(g.GetGeometryCount()):
        p = g.GetGeometryRef(i)
        out = p.Clone() if out is None else out.Union(p)
    return out


def union(geoms):
    if len(geoms) == 1:
        return valid(geoms[0].Clone())
    gc = ogr.Geometry(ogr.wkbGeometryCollection)
    for g in geoms:
        gc.AddGeometry(valid(g))
    return polys_only(uunion(gc))


def to(g, src, dst):
    g = g.Clone()
    g.FlattenTo2D()
    g.Transform(tr(src, dst))
    return g


def read(path, layer=None, where=None):
    ds = ogr.Open(path)
    lyr = ds.GetLayerByName(layer) if layer else ds.GetLayer(0)
    if lyr is None:
        raise RuntimeError("couche introuvable : %s dans %s" % (layer, path))
    if where:
        lyr.SetAttributeFilter(where)
    s = lyr.GetSpatialRef()
    s = s.Clone() if s is not None else None
    feats = []
    for f in lyr:
        g = f.GetGeometryRef()
        feats.append(({k: f.GetField(k) for k in f.keys()}, g.Clone() if g is not None else None))
    return feats, s


def save(path, g, s=L93):
    ds = ogr.GetDriverByName("GPKG").CreateDataSource(path)
    lyr = ds.CreateLayer("m", s, ogr.wkbMultiPolygon)
    f = ogr.Feature(lyr.GetLayerDefn())
    f.SetGeometry(ogr.ForceToMultiPolygon(g))
    lyr.CreateFeature(f)
    ds = None


def load(path):
    feats, s = read(path)
    return feats[0][1]


def km2(g_l93):
    return to(g_l93, L93, LAEA).GetArea() / 1e6


def fiche(nom, g_l93, mer=(), terre=(), info=()):
    """Résumé d'un masque (en Lambert-93) : surface, emprise, points de contrôle en mer et à terre."""
    w = to(g_l93, L93, WGS)
    e = w.GetEnvelope()
    print("   FICHE %s : %d polygone(s), %d sommets, surface %.3f km2 (EPSG:3035), emprise lon %.5f a %.5f, lat %.5f a %.5f"
          % (nom, len(parts(g_l93)), npoints(g_l93), km2(g_l93), e[0], e[1], e[2], e[3]))
    for label, pts, attendu in (("mer", mer, False), ("terre", terre, True), ("info", info, None)):
        for lon, lat, quoi in pts:
            p = ogr.Geometry(ogr.wkbPoint)
            p.AddPoint_2D(lon, lat)
            dedans = w.Contains(p)
            verdict = "" if attendu is None else ("(conforme)" if dedans == attendu else "(ANOMALIE)")
            print("      point %s %s (%.4f, %.4f) : %s %s" % (label, quoi, lon, lat, "DEDANS" if dedans else "dehors", verdict))


def box(minx, miny, maxx, maxy):
    r = ogr.Geometry(ogr.wkbLinearRing)
    for x, y in ((minx, miny), (maxx, miny), (maxx, maxy), (minx, maxy), (minx, miny)):
        r.AddPoint_2D(x, y)
    p = ogr.Geometry(ogr.wkbPolygon)
    p.AddGeometry(r)
    return p


LARGEURS = (2, 5, 10, 20, 40, 60, 100, 150, 200, 300, 400, 600, 1000)


def profil(g):
    """Surface (ha) des parties dont la largeur locale dépasse w, par ouverture morphologique (érosion puis dilatation de w/2)."""
    out = []
    for w in LARGEURS:
        try:
            er = g.Buffer(-w / 2.0, 4)
            a = 0.0 if er is None or er.IsEmpty() else er.Buffer(w / 2.0, 4).GetArea()
        except Exception as exc:  # pragma: no cover
            a = float("nan")
        out.append((w, a / 1e4))
        if a == 0.0:
            break
    return out


def epaisseur(p):
    """Plus grande largeur w de la liste telle que l'érosion de w/2 n'est pas vide."""
    best = 0
    for w in LARGEURS:
        er = p.Buffer(-w / 2.0, 4)
        if er is None or er.IsEmpty():
            break
        best = w
    return best


def paire(nom_a, a, nom_f, f, r=125.0, exclure=None, pixel=38.218514):
    """Écart entre deux masques voisins (Lambert-93).
    RECOUVREMENT : points qui sont dans les deux masques.
    TROU : points qui ne sont dans aucun des deux mais que comble une fermeture morphologique de rayon r
    (donc les interstices de moins de 2 r de large), à moins de 2 r des deux masques."""
    t0 = time.time()
    d = 2 * r
    ea, ef = a.GetEnvelope(), f.GetEnvelope()
    minx, maxx = max(ea[0], ef[0]) - 3000, min(ea[1], ef[1]) + 3000
    miny, maxy = max(ea[2], ef[2]) - 3000, min(ea[3], ef[3]) + 3000
    if minx >= maxx or miny >= maxy:
        print("   PAIRE %s / %s : emprises disjointes" % (nom_a, nom_f))
        return
    grand, petit = box(minx, miny, maxx, maxy), box(minx + 1000, miny + 1000, maxx - 1000, maxy - 1000)
    a, f = valid(a.Intersection(grand)), valid(f.Intersection(grand))
    ab, fb = a.Buffer(d, 4), f.Buffer(d, 4)
    zone = ab.Intersection(fb)
    if zone.IsEmpty():
        print("   PAIRE %s / %s : aucun point a moins de %d m des deux" % (nom_a, nom_f, d))
        return
    commun = a.Boundary().Intersection(fb).Intersection(petit).Length()
    recouvrement = polys_only(a.Intersection(f).Intersection(petit))
    couloir = zone.Buffer(2 * d, 4)
    u = valid(polys_only(a.Intersection(couloir).Union(f.Intersection(couloir))))
    ferme = u.Buffer(r, 4).Buffer(-r, 4)
    trou = ferme.Difference(u).Intersection(zone)
    if exclure is not None:
        trou = trou.Difference(exclure)
    trou = polys_only(trou.Intersection(petit))
    c = to(zone.Centroid(), L93, WGS)
    lat = c.GetY()
    px = (pixel * math.cos(math.radians(lat))) ** 2
    print("   PAIRE %s / %s : frontiere commune %.1f km (bord de %s a moins de %d m de %s), latitude moyenne %.2f, pixel z12 au sol %.1f m"
          % (nom_a, nom_f, commun / 1000, nom_a, d, nom_f, lat, math.sqrt(px)))
    for label, g in (("RECOUVREMENT", recouvrement), ("TROU", trou)):
        area = g.GetArea()
        ps = sorted(parts(g), key=lambda p: -p.GetArea())
        print("      %s : %.2f ha en %d morceaux, largeur moyenne %.1f m (surface / longueur commune), equivalent %.0f pixels z12"
              % (label, area / 1e4, len(ps), area / commun if commun else float("nan"), area / px))
        print("         surface (ha) des parties plus larges que w : " + ", ".join("w=%d m: %.2f" % (w, s) for w, s in profil(g)))
        for p in ps[:4]:
            cc = to(p.Centroid(), L93, WGS)
            e = p.GetEnvelope()
            print("         morceau %.2f ha, emprise %.0f x %.0f m, largeur max >= %d m, centre lon %.4f lat %.4f"
                  % (p.GetArea() / 1e4, e[1] - e[0], e[3] - e[2], epaisseur(p), cc.GetX(), cc.GetY()))
    print("      [%.0f s]" % (time.time() - t0), flush=True)


def anneaux_interieurs(u):
    """Trous fermés d'une union de masques : un polygone par anneau intérieur."""
    out = []
    for p in parts(u):
        for i in range(1, p.GetGeometryCount()):
            hp = ogr.Geometry(ogr.wkbPolygon)
            hp.AddGeometry(p.GetGeometryRef(i).Clone())
            out.append(hp)
    return out


def _morceaux(ps, n=3):
    for p in ps[:n]:
        cc = to(p.Centroid(), L93, WGS)
        e = p.GetEnvelope()
        print("         morceau %.2f ha, emprise %.0f x %.0f m, largeur max >= %d m, centre lon %.4f lat %.4f"
              % (p.GetArea() / 1e4, e[1] - e[0], e[3] - e[2], epaisseur(p), cc.GetX(), cc.GetY()))


def paire2(nom_a, a, nom_f, f, r=150.0, exclure=None, pixel=38.218514):
    """Comme paire(), en séparant les trous FERMES (anneaux intérieurs de l'union des deux masques, sans limite
    de largeur) des trous OUVERTS (interstices de moins de 2 r de large que seule une fermeture morphologique comble)."""
    t0 = time.time()
    d = 250.0
    ea, ef = a.GetEnvelope(), f.GetEnvelope()
    minx, maxx = max(ea[0], ef[0]) - 3000, min(ea[1], ef[1]) + 3000
    miny, maxy = max(ea[2], ef[2]) - 3000, min(ea[3], ef[3]) + 3000
    if minx >= maxx or miny >= maxy:
        print("   PAIRE %s / %s : emprises disjointes" % (nom_a, nom_f))
        return None
    grand, petit = box(minx, miny, maxx, maxy), box(minx + 1000, miny + 1000, maxx - 1000, maxy - 1000)
    a, f = valid(a.Intersection(grand)), valid(f.Intersection(grand))
    ab, fb = a.Buffer(d, 4), f.Buffer(d, 4)
    zone = ab.Intersection(fb)
    if zone.IsEmpty():
        print("   PAIRE %s / %s : aucun point a moins de %d m des deux" % (nom_a, nom_f, d))
        return None
    commun = a.Boundary().Intersection(fb).Intersection(petit).Length()
    recouvrement = polys_only(a.Intersection(f).Intersection(petit))
    couloir = zone.Buffer(4 * d, 4)
    u = valid(polys_only(a.Intersection(couloir).Union(f.Intersection(couloir))))
    fermes = [h for h in anneaux_interieurs(u) if h.Intersects(petit)]
    if exclure is not None:
        fermes = [h for h in fermes if not h.Intersects(exclure)]
    fermes.sort(key=lambda h: -h.GetArea())
    mpf = ogr.Geometry(ogr.wkbMultiPolygon)
    for h in fermes:
        mpf.AddGeometry(h)
    ferme = u.Buffer(r, 4).Buffer(-r, 4)
    ouverts = ferme.Difference(u).Intersection(zone)
    if mpf.GetGeometryCount():
        ouverts = ouverts.Difference(valid(mpf))
    if exclure is not None:
        ouverts = ouverts.Difference(exclure)
    ouverts = polys_only(ouverts.Intersection(petit))
    lat = to(zone.Centroid(), L93, WGS).GetY()
    px = (pixel * math.cos(math.radians(lat))) ** 2
    print("   PAIRE %s / %s : frontiere commune %.1f km, pixel z12 au sol %.1f m" % (nom_a, nom_f, commun / 1000, math.sqrt(px)))
    area = recouvrement.GetArea()
    ps = sorted(parts(recouvrement), key=lambda p: -p.GetArea())
    print("      RECOUVREMENT : %.2f ha en %d morceaux, largeur moyenne %.1f m, equivalent %.0f pixels z12" % (area / 1e4, len(ps), area / commun if commun else float("nan"), area / px))
    print("         surface (ha) des parties plus larges que w : " + ", ".join("w=%d: %.2f" % (w, s) for w, s in profil(recouvrement)))
    _morceaux(ps)
    area = sum(h.GetArea() for h in fermes)
    classes = ((0, 0.1), (0.1, 1), (1, 10), (10, 100), (100, 1e9))
    rep = []
    for lo, hi in classes:
        sel = [h.GetArea() / 1e4 for h in fermes if lo <= h.GetArea() / 1e4 < hi]
        rep.append("%s a %s ha : %d trous, %.2f ha" % (lo, hi if hi < 1e9 else "plus", len(sel), sum(sel)))
    print("      TROUS FERMES (anneaux interieurs de l'union) : %.2f ha en %d trous, largeur moyenne %.1f m, equivalent %.0f pixels z12"
          % (area / 1e4, len(fermes), area / commun if commun else float("nan"), area / px))
    print("         par taille : " + " ; ".join(rep))
    if mpf.GetGeometryCount():
        print("         surface (ha) des parties plus larges que w : " + ", ".join("w=%d: %.2f" % (w, s) for w, s in profil(valid(mpf))))
    _morceaux(fermes)
    area = ouverts.GetArea()
    ps = sorted(parts(ouverts), key=lambda p: -p.GetArea())
    print("      TROUS OUVERTS (combles seulement par une fermeture de rayon %d m) : %.2f ha en %d morceaux" % (r, area / 1e4, len(ps)))
    _morceaux(ps)
    print("      [%.0f s]" % (time.time() - t0), flush=True)
    return mpf


def relation_polygone(rel):
    """Assemble le polygone d'une relation OSM issue d'Overpass (« out geom ») : anneaux « outer » moins « inner »."""
    lignes = {"outer": ogr.Geometry(ogr.wkbMultiLineString), "inner": ogr.Geometry(ogr.wkbMultiLineString)}
    roles = {}
    for m in rel.get("members", []):
        roles[(m.get("type"), m.get("role"))] = roles.get((m.get("type"), m.get("role")), 0) + 1
        if m.get("type") != "way" or not m.get("geometry"):
            continue
        ls = ogr.Geometry(ogr.wkbLineString)
        for p in m["geometry"]:
            ls.AddPoint_2D(p["lon"], p["lat"])
        lignes["inner" if m.get("role") == "inner" else "outer"].AddGeometry(ls)
    res = {}
    for k, ml in lignes.items():
        if ml.GetGeometryCount() == 0:
            res[k] = None
            continue
        pg = polys_only(ml.Polygonize())
        if pg.GetGeometryCount() == 0:
            pg = polys_only(uunion(ml).Polygonize())
        res[k] = union([p.Clone() for p in parts(pg)]) if pg.GetGeometryCount() else None
    g = res["outer"]
    if g is not None and res["inner"] is not None:
        g = polys_only(g.Difference(res["inner"]))
    return g, roles
PYLIB
cat > py/ch3.py <<'PYEOF'
# Suisse : les quatre entités de tlm_landesgebiet, lecture directe du .gpkg.zip avec le filtre du pipeline.
import sys, time
sys.path.insert(0, "/tmp/sonde/py")
from lib_f import *

t0 = time.time()
ds = ogr.Open(sys.argv[1])
l = ds.GetLayerByName("tlm_landesgebiet")
s = l.GetSpatialRef()
for f in l:
    g = f.GetGeometryRef()
    print("   entite : name %s | icc %s | objektart %s | landesflaeche %s | see_flaeche %s | einwohnerzahl %s | herkunft %s %s-%s | revision %s-%s | datum_aenderung %s | %s | sommets %d | surface calculee %.3f km2"
          % (f.GetField("name"), f.GetField("icc"), f.GetField("objektart"), f.GetField("landesflaeche"), f.GetField("see_flaeche"), f.GetField("einwohnerzahl"),
             f.GetField("herkunft"), f.GetField("herkunft_jahr"), f.GetField("herkunft_monat"), f.GetField("revision_jahr"), f.GetField("revision_monat"),
             f.GetField("datum_aenderung"), g.GetGeometryName(), npoints(g), km2(to(g, s, L93))))
t1 = time.time()
l.SetAttributeFilter("icc = 'CH'")
geoms = [to(f.GetGeometryRef(), s, L93) for f in l]
print("   lecture directe de %s, couche tlm_landesgebiet, filtre \"icc = 'CH'\" : %d entite(s) ; ouverture et parcours complet %.1f s, lecture filtree %.1f s"
      % (sys.argv[1], len(geoms), t1 - t0, time.time() - t1))
save("/tmp/sonde/sel/CH.gpkg", union(geoms))
PYEOF
cat > py/ecarts3.py <<'PYEOF'
# Écarts : trous fermés (anneaux intérieurs de l'union) et trous ouverts, par paire de masques voisins ; grands trous restants.
import os, sys, time, traceback
sys.path.insert(0, "/tmp/sonde/py")
from lib_f import *

feats, s = read(sys.argv[1])
CODES = ("01", "39", "25", "90", "68", "74", "73", "05", "04", "06", "64", "65", "31", "09", "66")
dep = {f["code"]: valid(to(g, s, L93)) for f, g in feats if f["code"] in CODES}


def fr(*codes):
    return union([dep[c].Clone() for c in codes])


def masque(nom):
    p = "/tmp/sonde/sel/%s.gpkg" % nom
    return valid(load(p)) if os.path.exists(p) else None


m = {k: masque(k) for k in ("CH", "IT", "ITOSM", "ES", "AD", "MC")}
print("   masques disponibles :", {k: (v is not None) for k, v in m.items()})
PAIRES = (
    ("Suisse", "CH", "France (01, 39, 25, 90, 68, 74)", lambda: fr("01", "39", "25", "90", "68", "74"), None),
    ("Italie ISTAT", "IT", "France (74, 73, 05, 04, 06)", lambda: fr("74", "73", "05", "04", "06"), "MC"),
    ("Italie OSM", "ITOSM", "France (74, 73, 05, 04, 06)", lambda: fr("74", "73", "05", "04", "06"), "MC"),
    ("Espagne", "ES", "France (64, 65, 31, 09, 66)", lambda: fr("64", "65", "31", "09", "66"), "AD"),
    ("Andorre", "AD", "France (09, 66)", lambda: fr("09", "66"), None),
    ("Andorre", "AD", "Espagne", lambda: m["ES"], None),
    ("Monaco", "MC", "France (06)", lambda: fr("06"), None),
    ("Suisse", "CH", "Italie ISTAT", lambda: m["IT"], None),
    ("Suisse", "CH", "Italie OSM", lambda: m["ITOSM"], None),
)
for nom_a, ka, nom_f, f_fn, excl in PAIRES:
    try:
        a = m.get(ka)
        f = f_fn()
        if a is None or f is None:
            print("   PAIRE %s / %s : masque manquant" % (nom_a, nom_f))
            continue
        paire2(nom_a, a, nom_f, f, exclure=m.get(excl) if excl else None)
    except Exception as exc:
        print("   PAIRE %s / %s : ERREUR %s" % (nom_a, nom_f, str(exc)[:300]))
        traceback.print_exc(limit=2)
# Grands trous fermés de l'union de tous les masques (enclaves, lacs) : ceux qu'un seuil de surface doit laisser vides.
try:
    t0 = time.time()
    tout = [dep[c].Clone() for c in CODES] + [m[k] for k in ("CH", "IT", "ES", "AD", "MC") if m[k] is not None]
    u = union(tout)
    trous = sorted(anneaux_interieurs(u), key=lambda h: -h.GetArea())
    print("   UNION de tous les masques (15 departements frontaliers, Suisse, Italie ISTAT, Espagne, Andorre, Monaco) : %d trous fermes, %.1f ha au total [%.0f s]"
          % (len(trous), sum(h.GetArea() for h in trous) / 1e4, time.time() - t0))
    for lo, hi in ((0, 1), (1, 10), (10, 50), (50, 100), (100, 1e12)):
        sel = [h.GetArea() / 1e4 for h in trous if lo <= h.GetArea() / 1e4 < hi]
        print("      de %s a %s ha : %d trous, %.1f ha" % (lo, hi if hi < 1e12 else "plus", len(sel), sum(sel)))
    for h in trous[:14]:
        c = to(h.Centroid(), L93, WGS)
        e = h.GetEnvelope()
        print("      trou de %.1f ha, emprise %.0f x %.0f m, largeur max >= %d m, centre lon %.4f lat %.4f" % (h.GetArea() / 1e4, e[1] - e[0], e[3] - e[2], epaisseur(h), c.GetX(), c.GetY()))
except Exception as exc:
    print("   UNION : ERREUR", str(exc)[:300])
PYEOF
cat > py/es3.py <<'PYEOF'
# Espagne : les quatre communautés autonomes (GeoJSON de l'API de l'IGN).
import sys
sys.path.insert(0, "/tmp/sonde/py")
from lib_f import *

sel = []
for code in sys.argv[1:]:
    feats, s = read("/tmp/sonde/es/%s.geojson" % code)
    for f, g in feats:
        g2 = to(g, s, L93)
        sel.append(g2)
        print("   %s=%s | sommets %d | surface %.3f km2" % (f["nationalcode"], f["nameunit"], npoints(g), km2(g2)))
save("/tmp/sonde/sel/ES.gpkg", union(sel))
PYEOF
cat > py/it3.py <<'PYEOF'
# Italie : régions extraites à distance de l'archive ISTAT (ogr2ogr sur /vsizip//vsicurl).
import sys
sys.path.insert(0, "/tmp/sonde/py")
from lib_f import *

feats, s = read(sys.argv[1])
sel = []
for f, g in feats:
    g2 = to(g, s, L93)
    sel.append(g2)
    save("/tmp/sonde/sel/IT-%s.gpkg" % f["COD_REG"], g2)
    print("   %s=%s | %s | sommets %d | surface %.3f km2" % (f["COD_REG"], f["DEN_REG"], g.GetGeometryName(), npoints(g), km2(g2)))
print("   SCR du GeoPackage extrait :", s.GetName(), "EPSG", s.GetAuthorityCode(None))
save("/tmp/sonde/sel/IT.gpkg", union(sel))
PYEOF
cat > py/osm3.py <<'PYEOF'
# OSM : Monaco (relation 36990, type=land_area) depuis le PBF Geofabrik par polygonisation de other_relations ;
# Andorre (relation 9407) depuis multipolygons ; régions italiennes par Overpass (solution de repli).
import json, os, sys
sys.path.insert(0, "/tmp/sonde/py")
from lib_f import *

monaco_pbf, andorre_pbf, ovp = sys.argv[1:4]


def lignes(g, ml, compte):
    n = g.GetGeometryName()
    if n == "LINESTRING":
        ml.AddGeometry(g)
        compte[n] = compte.get(n, 0) + 1
    elif g.GetGeometryCount():
        for i in range(g.GetGeometryCount()):
            lignes(g.GetGeometryRef(i), ml, compte)
    else:
        compte[n] = compte.get(n, 0) + 1


ds = ogr.Open(monaco_pbf)
l = ds.GetLayerByName("other_relations")
l.SetAttributeFilter("osm_id = '36990'")
mc = None
for f in l:
    ml, compte = ogr.Geometry(ogr.wkbMultiLineString), {}
    lignes(f.GetGeometryRef(), ml, compte)
    pg = polys_only(ml.Polygonize())
    mc = to(union([p.Clone() for p in parts(pg)]), l.GetSpatialRef(), L93)
    print("   Monaco, PBF Geofabrik, other_relations osm_id='36990' : elements %s -> Polygonize : %d polygone(s), %.4f km2" % (compte, len(parts(mc)), km2(mc)))
    for p in sorted(parts(mc), key=lambda p: -p.GetArea()):
        c = to(p.Centroid(), L93, WGS)
        print("      polygone de %.4f ha, centre lon %.5f lat %.5f, sommets %d" % (p.GetArea() / 1e4, c.GetX(), c.GetY(), npoints(p)))
ds = None
ds = ogr.Open(andorre_pbf)
l = ds.GetLayerByName("multipolygons")
l.SetAttributeFilter("osm_id = '9407'")
ad = None
for f in l:
    ad = to(f.GetGeometryRef(), l.GetSpatialRef(), L93)
    print("   Andorre, PBF Geofabrik, multipolygons osm_id='9407' : %s, sommets %d, %.4f km2" % (f.GetGeometryRef().GetGeometryName(), npoints(ad), km2(ad)))
ds = None
if mc is not None:
    save("/tmp/sonde/sel/MC.gpkg", mc)
if ad is not None:
    save("/tmp/sonde/sel/AD.gpkg", ad)

try:
    d = json.load(open(ovp, encoding="utf-8"))
except Exception as exc:
    print("   reponse d'Overpass illisible :", str(exc)[:200])
    d = {}
print("   Overpass : base OSM du", d.get("osm3s", {}).get("timestamp_osm_base"), "|", len(d.get("elements", [])), "relations | %.2f Mo" % (os.path.getsize(ovp) / 1e6 if os.path.exists(ovp) else 0))
regions = []
for e in d.get("elements", []):
    t = e.get("tags", {})
    g, roles = relation_polygone(e)
    if g is None:
        print("   relation %s (%s) : pas de polygone ; roles %s" % (e.get("id"), t.get("name"), roles))
        continue
    g2 = to(g, WGS, L93)
    env = g.GetEnvelope()
    print("   relation %s | name %s | ISO3166-2 %s | type %s | boundary %s | admin_level %s | roles %s | %d polygone(s) | sommets %d | surface %.3f km2 | emprise lon %.4f a %.4f lat %.4f a %.4f"
          % (e["id"], t.get("name"), t.get("ISO3166-2"), t.get("type"), t.get("boundary"), t.get("admin_level"), {"%s:%s" % k: v for k, v in roles.items()}, len(parts(g)), npoints(g), km2(g2), env[0], env[1], env[2], env[3]))
    if e["id"] == 36990:
        if mc is not None:
            print("   comparaison Monaco 36990 : Overpass contre PBF Geofabrik polygonise : difference symetrique %.4f ha" % (g2.SymDifference(mc).GetArea() / 1e4))
        continue
    regions.append(g2)
    iso = {"IT-21": "1", "IT-23": "2", "IT-42": "7"}.get(t.get("ISO3166-2"))
    p = "/tmp/sonde/sel/IT-%s.gpkg" % iso
    if iso and os.path.exists(p):
        ist = load(p)
        sym = polys_only(g2.SymDifference(ist))
        lon = ist.Boundary().Length()
        print("      contre ISTAT (COD_REG %s) : difference symetrique %.1f ha pour %.0f km de contour ISTAT, soit %.1f m d'ecart moyen ; parties plus larges que w (ha) : %s"
              % (iso, sym.GetArea() / 1e4, lon / 1000, sym.GetArea() / lon, ", ".join("w=%d: %.0f" % (w, a) for w, a in profil(sym))))
if regions:
    g = union(regions)
    save("/tmp/sonde/sel/ITOSM.gpkg", g)
    fiche("Italie par OSM (3 regions)", g,
          mer=[(8.95, 44.30, "11 km au large de Genes"), (7.60, 43.70, "10 km au large de Vintimille"), (9.85, 44.00, "au sud de l'ile du Tino"), (8.20, 43.90, "5 km au large d'Alassio")],
          terre=[(8.9326, 44.4072, "Genes"), (7.3206, 45.7370, "Aoste"), (7.6869, 45.0703, "Turin")],
          info=[(8.555, 45.895, "lac Majeur, pres de Stresa"), (6.8652, 45.8326, "sommet du mont Blanc")])
PYEOF
export DEBIAN_FRONTEND=noninteractive
export GDAL_HTTP_USERAGENT="$UA"
PYI="python3 -I"
t_debut=$(date +%s)

echo "##### A. SUISSE : entités de tlm_landesgebiet, lecture directe du .gpkg.zip"
B=https://data.geo.admin.ch/ch.swisstopo.swissboundaries3d/swissboundaries3d_2026-01/swissboundaries3d_2026-01_2056_5728
get ch/swissboundaries3d_2026-01_2056_5728.gpkg.zip "$B.gpkg.zip"
$PYI py/ch3.py ch/swissboundaries3d_2026-01_2056_5728.gpkg.zip 2>&1 | cut -c1-420
echo "   [A : $(( $(date +%s) - t_debut )) s]"

echo
echo "##### B. ITALIE : extraction à distance des trois régions (sans télécharger l'archive de 98 Mo)"
UI=https://www.istat.it/storage/cartografia/confini_amministrativi/non_generalizzati/2026/Limiti01012026.zip
t0=$(date +%s)
ogr2ogr --config CPL_VSIL_SHOW_NETWORK_STATS YES -f GPKG it/it.gpkg "/vsizip//vsicurl/$UI/Reg01012026/Reg01012026_WGS84.shp" -where "COD_REG IN (1, 2, 7)" -nln regioni > it/ogr2ogr.log 2>&1
echo "   ogr2ogr -f GPKG it.gpkg \"/vsizip//vsicurl/$UI/Reg01012026/Reg01012026_WGS84.shp\" -where \"COD_REG IN (1, 2, 7)\" -nln regioni : code $? en $(( $(date +%s) - t0 )) s, $(stat -c %s it/it.gpkg 2>/dev/null) octets"
grep -E '"(count|downloaded_bytes)"|ERROR|Warning' it/ogr2ogr.log | head -6 | tr -s ' ' | tr '\n' ' ' | c300; echo
$PYI py/it3.py it/it.gpkg 2>&1 | c300
echo "   [B : $(( $(date +%s) - t_debut )) s]"

echo
echo "##### C. ESPAGNE : les quatre communautés autonomes"
API=https://api-features.ign.es
for code in 34020000000 34090000000 34150000000 34160000000; do
  get "es/$code.geojson" "$API/collections/administrativeunit/items?f=json&nationalcode=$code"
done
$PYI py/es3.py 34020000000 34090000000 34150000000 34160000000 2>&1 | c300
echo "   [C : $(( $(date +%s) - t_debut )) s]"

echo
echo "##### D. OPENSTREETMAP : Monaco et Andorre par Geofabrik, régions italiennes par Overpass (repli)"
tete https://download.geofabrik.de/europe/monaco-latest.osm.pbf
get osm/monaco-latest.osm.pbf https://download.geofabrik.de/europe/monaco-latest.osm.pbf
get osm/andorra-latest.osm.pbf https://download.geofabrik.de/europe/andorra-latest.osm.pbf
cat > osm/q3.txt <<'Q'
[out:json][timeout:180];
(
  relation(36990);
  relation["boundary"="administrative"]["admin_level"="4"]["ISO3166-2"~"^IT-(21|23|42)$"];
);
out geom;
Q
for i in 1 2 3 4; do
  code=$(curl -sS -m 300 -A "$UA" -o osm/ovp3.json -w "%{http_code} %{size_download}o %{content_type}" --data-urlencode "data@osm/q3.txt" "https://overpass-api.de/api/interpreter" 2>&1)
  echo "  -> $code (essai $i)  POST https://overpass-api.de/api/interpreter  data=$(tr '\n' ' ' < osm/q3.txt)"
  case "$code" in 200*) break ;; esac
  sleep $((i * 20))
done
$PYI py/osm3.py osm/monaco-latest.osm.pbf osm/andorra-latest.osm.pbf osm/ovp3.json 2>&1 | cut -c1-520
echo "   [D : $(( $(date +%s) - t_debut )) s]"

echo
echo "##### E. ECARTS : trous fermés et ouverts par paire, grands trous de l'union"
get fr/departements-5m.geojson.gz https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/departements-5m.geojson.gz
gunzip -f fr/departements-5m.geojson.gz
$PYI py/ecarts3.py fr/departements-5m.geojson 2>&1 | cut -c1-330
echo "   [E : $(( $(date +%s) - t_debut )) s]"

echo
echo "##### F. Licence de l'IGN España : identifiants de produit de la table d'attribution"
get lic/ign.pdf "https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf"
(apt-get update -qq && apt-get install -y -qq poppler-utils) >/dev/null 2>&1
if command -v pdftotext >/dev/null 2>&1; then
  pdftotext -layout lic/ign.pdf lic/ign.txt
  grep -v -E '^\s*$' lic/ign.txt | sed -E 's/\s+/ /g' | grep -n -i -E "l[ií]mite|BDLJE|BDDAE|SIGLIM|recinto|Tabla|identificador del producto|RCC|a[ñn]o|vigente|fecha" | cut -c1-330 | head -24
else
  echo "   pdftotext indisponible"
fi
echo "FIN frontieres-3 [$(( $(date +%s) - t_debut )) s]"
