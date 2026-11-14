#!/usr/bin/env bash
# Sonde frontieres-2 : téléchargement des contours candidats (Suisse, Italie, Espagne, Andorre, Monaco),
# schémas (ogrinfo), filtres attributaires, contrôle « terrestre », écarts le long des frontières communes
# (avec la France : contours Etalab des départements), textes de licence.
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


LARGEURS = (2, 5, 10, 20, 40, 60, 100, 150, 200, 300)


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
cat > py/ch.py <<'PYEOF'
# Suisse : couches du GeoPackage swissBOUNDARIES3D, entités du territoire national, filtre, masque.
import sys
sys.path.insert(0, "/tmp/sonde/py")
from lib_f import *

ds = ogr.Open(sys.argv[1])
cible = None
for i in range(ds.GetLayerCount()):
    l = ds.GetLayer(i)
    s = l.GetSpatialRef()
    codes = [s.GetAuthorityCode(k) for k in ("PROJCS", "VERT_CS")] if s else None
    print("   couche %s | %s | %d entites | SCR %s | compose %s | EPSG horizontal, vertical %s"
          % (l.GetName(), ogr.GeometryTypeToName(l.GetGeomType()), l.GetFeatureCount(), s.GetName() if s else None, bool(s.IsCompound()) if s else None, codes))
    if "landesgebiet" in l.GetName().lower():
        cible = l.GetName()
print("   couche du territoire national :", cible)
l = ds.GetLayerByName(cible)
d = l.GetLayerDefn()
print("   champs :", ", ".join("%s (%s)" % (d.GetFieldDefn(i).GetName(), d.GetFieldDefn(i).GetTypeName()) for i in range(d.GetFieldCount())))
s = l.GetSpatialRef()
sel, champ = [], None
premier = None
for f in l:
    g = f.GetGeometryRef()
    if premier is None:
        gg = g
        while gg.GetGeometryCount():
            gg = gg.GetGeometryRef(0)
        premier = gg.GetPoint(0)
    vals = {k: f.GetField(k) for k in f.keys()}
    g2 = to(g, s, L93)
    print("   entite :", str({k: v for k, v in vals.items() if v not in (None, "")})[:420], "|", g.GetGeometryName(), "| 3D", bool(g.Is3D()), "| sommets", npoints(g), "| surface %.3f km2" % km2(g2))
    for k, v in vals.items():
        if v == "CH":
            champ = k
            sel.append(g2)
print("   champ dont la valeur est 'CH' :", champ, "|", len(sel), "entite(s)")
if champ:
    l.SetAttributeFilter("%s = 'CH'" % champ)
    print("   filtre attributaire \"%s = 'CH'\" : %d entite(s)" % (champ, l.GetFeatureCount()))
    l.SetAttributeFilter(None)
# Transformation vers EPSG:3857 : SCR composé de la couche (comme le fait le pipeline) contre EPSG:2056 seul.
t1, t2 = tr(s, MERC), tr(srs(2056), MERC)
p1, p2 = t1.TransformPoint(*premier[:3]), t2.TransformPoint(premier[0], premier[1])
print("   sommet %s -> EPSG:3857 par le SCR de la couche %.3f %.3f, par EPSG:2056 %.3f %.3f, ecart %.4f m"
      % (str(tuple(round(v, 2) for v in premier)), p1[0], p1[1], p2[0], p2[1], math.hypot(p1[0] - p2[0], p1[1] - p2[1])))
g = union(sel)
save("/tmp/sonde/sel/CH.gpkg", g)
fiche("Suisse", g,
      terre=[(7.4474, 46.9480, "Berne"), (7.7491, 46.0207, "Zermatt")],
      info=[(6.60, 46.42, "Leman, au large d'Evian (cote francais)"), (6.60, 46.48, "Leman, au large de Lausanne (cote suisse)"),
            (9.42, 47.58, "lac de Constance, au large de Romanshorn"), (8.9710, 45.9690, "Campione d'Italia (enclave italienne)"),
            (8.6900, 47.6967, "Busingen (enclave allemande)"), (9.5209, 47.1410, "Vaduz (Liechtenstein)")])
PYEOF
cat > py/ecarts.py <<'PYEOF'
# Écarts le long des frontières communes : recouvrements et trous entre masques voisins.
import os, sys, traceback
sys.path.insert(0, "/tmp/sonde/py")
from lib_f import *

feats, s = read(sys.argv[1])
print("   contours Etalab : %d entites, SCR %s, champs %s" % (len(feats), s.GetName(), list(feats[0][0].keys())))
CODES = ("01", "39", "25", "90", "68", "74", "73", "05", "04", "06", "64", "65", "31", "09", "66")
dep = {f["code"]: valid(to(g, s, L93)) for f, g in feats if f["code"] in CODES}
print("   sommets par departement :", {c: npoints(g) for c, g in sorted(dep.items())})


def fr(*codes):
    return union([dep[c].Clone() for c in codes])


def masque(nom):
    p = "/tmp/sonde/sel/%s.gpkg" % nom
    return valid(load(p)) if os.path.exists(p) else None


m = {k: masque(k) for k in ("CH", "IT", "ES", "AD", "MC")}
print("   masques disponibles :", {k: (v is not None) for k, v in m.items()})
PAIRES = (
    ("Suisse", "CH", "France (01, 39, 25, 90, 68, 74)", lambda: fr("01", "39", "25", "90", "68", "74"), None),
    ("Italie", "IT", "France (74, 73, 05, 04, 06)", lambda: fr("74", "73", "05", "04", "06"), "MC"),
    ("Espagne", "ES", "France (64, 65, 31, 09, 66)", lambda: fr("64", "65", "31", "09", "66"), "AD"),
    ("Andorre", "AD", "France (09, 66)", lambda: fr("09", "66"), None),
    ("Andorre", "AD", "Espagne", lambda: m["ES"], None),
    ("Monaco", "MC", "France (06)", lambda: fr("06"), None),
    ("Suisse", "CH", "Italie", lambda: m["IT"], None),
)
for nom_a, ka, nom_f, f_fn, excl in PAIRES:
    try:
        a = m.get(ka)
        f = f_fn()
        if a is None or f is None:
            print("   PAIRE %s / %s : masque manquant" % (nom_a, nom_f))
            continue
        paire(nom_a, a, nom_f, f, exclure=m.get(excl) if excl else None)
    except Exception as exc:
        print("   PAIRE %s / %s : ERREUR %s" % (nom_a, nom_f, str(exc)[:300]))
        traceback.print_exc(limit=2)
# Points de contrôle côté français.
fiche("France, departement 74", dep["74"], info=[(6.60, 46.42, "Leman, au large d'Evian (cote francais)"), (6.8652, 45.8326, "sommet du mont Blanc")])
fiche("France, departement 06", dep["06"], info=[(7.4203, 43.7312, "Palais princier de Monaco"), (7.45, 43.70, "en mer au sud de Monaco")])
if m["IT"] is not None:
    fiche("Italie, rappel", m["IT"], info=[(6.8652, 45.8326, "sommet du mont Blanc"), (6.8540, 45.8420, "dome du Gouter")])
PYEOF
cat > py/es_geo.py <<'PYEOF'
# Espagne : géométries des quatre communautés autonomes (GeoJSON de l'API), masque.
import json, os, sys
sys.path.insert(0, "/tmp/sonde/py")
from lib_f import *

sel = []
for line in open(sys.argv[1], encoding="utf-8"):
    code, nom = line.rstrip("\n").split("\t")
    path = "/tmp/sonde/es/%s.geojson" % code
    try:
        d = json.load(open(path, encoding="utf-8"))
    except Exception as exc:
        print("   %s : ILLISIBLE %s" % (nom, exc))
        continue
    fs = d.get("features", [])
    c = fs[0]["geometry"]["coordinates"] if fs else None
    while c and isinstance(c[0], list):
        c = c[0]
    print("   %s : %.1f Mo | numberMatched %s | numberReturned %s | timeStamp %s | membre crs %s | premier sommet %s"
          % (nom, os.path.getsize(path) / 1e6, d.get("numberMatched"), d.get("numberReturned"), d.get("timeStamp"), d.get("crs"), c))
    feats, s = read(path)
    for f, g in feats:
        g2 = to(g, s, L93)
        sel.append(g2)
        print("      SCR lu par OGR : %s (EPSG %s) | %s | valide %s | sommets %d | surface %.3f km2 | champs %s"
              % (s.GetName(), s.GetAuthorityCode(None), g.GetGeometryName(), g.IsValid(), npoints(g), km2(g2), list(f.keys())))
        save("/tmp/sonde/sel/ES-%s.gpkg" % code, g2)
g = union(sel)
save("/tmp/sonde/sel/ES.gpkg", g)
fiche("Espagne (4 communautes)", g,
      mer=[(2.25, 41.30, "10 km au large de Barcelone"), (-2.20, 43.40, "10 km au large de Getaria"), (3.30, 42.10, "13 km au large de L'Escala"), (0.90, 40.60, "au large du delta de l'Ebre")],
      terre=[(2.1734, 41.3851, "Barcelone"), (-2.9350, 43.2630, "Bilbao"), (-1.6440, 42.8170, "Pampelune"), (-0.8890, 41.6490, "Saragosse"), (1.9806, 42.4644, "Llivia (enclave en France)")],
      info=[(-1.7656, 43.3428, "ile des Faisans (condominium)"), (1.5218, 42.5063, "Andorre-la-Vieille")])
PYEOF
cat > py/es_liste.py <<'PYEOF'
# Espagne : liste des communautés autonomes renvoyées par l'API (sans géométrie) et codes des quatre voulues.
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
feats = d.get("features", [])
print("   numberMatched", d.get("numberMatched"), "| numberReturned", d.get("numberReturned"), "| geometrie absente :", all(f.get("geometry") is None for f in feats))
if feats:
    print("   proprietes de la premiere :", json.dumps(feats[0].get("properties"), ensure_ascii=False)[:420], "| id", feats[0].get("id"))
print("   toutes (nationalcode=nameunit, codnut2) :", "; ".join("%s=%s, %s" % (f["properties"].get("nationalcode"), f["properties"].get("nameunit"), f["properties"].get("codnut2")) for f in feats)[:1500])
voulu = ("catalu", "arag", "navarra", "vasco")
with open(sys.argv[2], "w", encoding="utf-8") as out:
    for f in feats:
        p = f["properties"]
        if any(v in (p.get("nameunit") or "").lower() for v in voulu):
            out.write("%s\t%s\n" % (p.get("nationalcode"), p.get("nameunit")))
            print("   RETENUE :", json.dumps(p, ensure_ascii=False)[:420])
PYEOF
cat > py/it.py <<'PYEOF'
# Italie : couche des régions de l'ISTAT (version non généralisée et généralisée), filtre, masque.
import sys
sys.path.insert(0, "/tmp/sonde/py")
from lib_f import *

VOULU = {1: "Piemonte", 2: "Valle d'Aosta", 7: "Liguria"}


def charge(path, detail):
    feats, s = read(path)
    if detail:
        print("   SCR :", s.GetName(), "| EPSG", s.GetAuthorityCode(None), "| champs :", list(feats[0][0].keys()))
        print("   regions (COD_REG=DEN_REG) :", "; ".join("%s=%s" % (f.get("COD_REG"), f.get("DEN_REG")) for f, g in sorted(feats, key=lambda x: (x[0].get("COD_REG") or 0))))
    sel = []
    for f, g in feats:
        if f.get("COD_REG") in VOULU:
            g2 = to(g, s, L93)
            sel.append(g2)
            print("   %s : %s | %s | sommets %d | surface calculee %.3f km2" % ("retenue" if detail else "generalisee", str(f)[:230], g.GetGeometryName(), npoints(g), km2(g2)))
    return union(sel), s


g, s = charge(sys.argv[1], True)
feats, _ = read(sys.argv[1], where="COD_REG IN (1, 2, 7)")
print("   filtre attributaire \"COD_REG IN (1, 2, 7)\" : %d entite(s) : %s" % (len(feats), [f.get("DEN_REG") for f, _ in feats]))
save("/tmp/sonde/sel/IT.gpkg", g)
fiche("Italie (Piemonte, Valle d'Aosta, Liguria)", g,
      mer=[(8.95, 44.30, "11 km au large de Genes"), (7.60, 43.70, "10 km au large de Vintimille"), (9.85, 44.00, "au sud de l'ile du Tino (La Spezia)")],
      terre=[(8.9326, 44.4072, "Genes"), (7.3206, 45.7370, "Aoste"), (7.6869, 45.0703, "Turin")],
      info=[(8.555, 45.895, "lac Majeur, pres de Stresa")])
if len(sys.argv) > 2 and sys.argv[2]:
    gg, _ = charge(sys.argv[2], False)
    sym = polys_only(g.SymDifference(gg))
    lon = g.Boundary().Length()
    print("   version generalisee contre non generalisee : %d sommets contre %d ; difference symetrique %.1f ha pour %.0f km de contour, soit %.1f m d'ecart moyen"
          % (npoints(gg), npoints(g), sym.GetArea() / 1e4, lon / 1000, sym.GetArea() / lon))
    print("      surface (ha) des ecarts plus larges que w : " + ", ".join("w=%d m: %.1f" % (w, a) for w, a in profil(sym)))
PYEOF
cat > py/osm_gf.py <<'PYEOF'
# OSM par les extraits Geofabrik (PBF lus par le pilote OSM de GDAL) : relations de frontière d'Andorre et de Monaco.
import sys
sys.path.insert(0, "/tmp/sonde/py")
from lib_f import *

for nom, pbf, ids in (("Monaco", sys.argv[1], ("36990", "2220322", "1124039")), ("Andorre", sys.argv[2], ("9407",))):
    ds = ogr.Open(pbf)
    print("   %s : couches %s" % (nom, [ds.GetLayer(i).GetName() for i in range(ds.GetLayerCount())]))
    l = ds.GetLayerByName("multipolygons")
    d = l.GetLayerDefn()
    if nom == "Monaco":
        print("   champs de multipolygons :", [d.GetFieldDefn(i).GetName() for i in range(d.GetFieldCount())])
    s = l.GetSpatialRef()
    l.SetAttributeFilter("boundary IS NOT NULL AND (admin_level IN ('2', '8') OR boundary = 'land_area')")
    for f in l:
        g = f.GetGeometryRef()
        e = g.GetEnvelope()
        print("   %s multipolygons : osm_id %s | name %s | type %s | boundary %s | admin_level %s | land_area %s | sommets %d | surface %.4f km2 | emprise lon %.4f a %.4f lat %.4f a %.4f"
              % (nom, f.GetField("osm_id"), f.GetField("name"), f.GetField("type"), f.GetField("boundary"), f.GetField("admin_level"), f.GetField("land_area"),
                 npoints(g), km2(to(g, s, L93)), e[0], e[1], e[2], e[3]))
    ds = None
    for i in ids:  # le motif d'accès de pipeline/czb/masks.py : ouvrir, choisir la couche, filtrer, itérer
        ds = ogr.Open(pbf)
        l = ds.GetLayerByName("multipolygons")
        l.SetAttributeFilter("osm_id = '%s'" % i)
        n = 0
        for f in l:
            n += 1
            save("/tmp/sonde/sel/gf-%s.gpkg" % i, to(f.GetGeometryRef(), l.GetSpatialRef(), L93))
        print("   %s : filtre \"osm_id = '%s'\" sur multipolygons : %d entite(s)" % (nom, i, n))
        ds = None
    ds = ogr.Open(pbf)
    l = ds.GetLayerByName("other_relations")
    l.SetAttributeFilter("osm_id IN ('36990', '9407', '2220322', '1124039')")
    for f in l:
        g = f.GetGeometryRef()
        print("   %s other_relations : osm_id %s | name %s | type %s | %s de %d elements | other_tags %s"
              % (nom, f.GetField("osm_id"), f.GetField("name"), f.GetField("type"), g.GetGeometryName(), g.GetGeometryCount(), (f.GetField("other_tags") or "")[:160]))
    ds = None
PYEOF
cat > py/osm_ovp.py <<'PYEOF'
# OSM par Overpass (« out geom ») : assemblage des polygones des relations, comparaison avec Geofabrik, masques.
import json, os, sys
sys.path.insert(0, "/tmp/sonde/py")
from lib_f import *

try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as exc:
    print("   reponse d'Overpass illisible :", str(exc)[:200])
    d = {}
print("   base OSM du", d.get("osm3s", {}).get("timestamp_osm_base"), "|", len(d.get("elements", [])), "relations |", "%.2f Mo" % (os.path.getsize(sys.argv[1]) / 1e6))
polys = {}
for e in d.get("elements", []):
    t = e.get("tags", {})
    g, roles = relation_polygone(e)
    if g is None:
        print("   relation %s : pas de polygone ; roles %s" % (e.get("id"), roles))
        continue
    g2 = to(g, WGS, L93)
    polys[str(e["id"])] = g2
    env = g.GetEnvelope()
    print("   relation %s | name %s | type %s | boundary %s | admin_level %s | roles %s | %d polygone(s) | sommets %d | surface %.4f km2 | emprise lon %.4f a %.4f lat %.4f a %.4f"
          % (e["id"], t.get("name"), t.get("type"), t.get("boundary"), t.get("admin_level"), {"%s:%s" % k: v for k, v in roles.items()}, len(parts(g)), npoints(g), km2(g2), env[0], env[1], env[2], env[3]))
    save("/tmp/sonde/sel/ovp-%s.gpkg" % e["id"], g2)


def compare(a, b, quoi):
    if a is None or b is None:
        print("   comparaison %s : impossible (une des deux geometries manque)" % quoi)
        return
    sym = a.SymDifference(b)
    print("   comparaison %s : difference symetrique %.4f ha" % (quoi, sym.GetArea() / 1e4))


def gf(i):
    p = "/tmp/sonde/sel/gf-%s.gpkg" % i
    return load(p) if os.path.exists(p) else None


compare(polys.get("36990"), polys.get("2220322"), "Monaco terre ferme 36990 (land_area) contre 2220322 (admin_level 8), Overpass")
compare(polys.get("2220322"), gf("2220322"), "Monaco 2220322 Overpass contre Geofabrik")
compare(polys.get("9407"), gf("9407"), "Andorre 9407 Overpass contre Geofabrik")
ad = polys.get("9407") if polys.get("9407") is not None else gf("9407")
mc = next((x for x in (polys.get("36990"), polys.get("2220322"), gf("2220322")) if x is not None), None)
if ad is not None:
    save("/tmp/sonde/sel/AD.gpkg", ad)
    fiche("Andorre (relation 9407)", ad, terre=[(1.5218, 42.5063, "Andorre-la-Vieille"), (1.7336, 42.5425, "Pas de la Case")], info=[(1.9806, 42.4644, "Llivia")])
if mc is not None:
    save("/tmp/sonde/sel/MC.gpkg", mc)
    fiche("Monaco terre ferme", mc, mer=[(7.4500, 43.7350, "1 km au large du Larvotto"), (7.4300, 43.7200, "1 km au sud du Rocher")],
          terre=[(7.4203, 43.7312, "Palais princier"), (7.4279, 43.7392, "Casino de Monte-Carlo")],
          info=[(7.4245, 43.7350, "bassin du port Hercule"), (7.4322, 43.7412, "Mareterra (extension en mer livree en 2024) ?")])
if polys.get("1124039") is not None:
    fiche("Monaco, relation 1124039 (admin_level 2, avec les eaux)", polys["1124039"], info=[(7.4500, 43.7350, "1 km au large du Larvotto"), (7.4203, 43.7312, "Palais princier")])
PYEOF
export DEBIAN_FRONTEND=noninteractive
export GDAL_HTTP_USERAGENT="$UA"
PYI="python3 -I"
t_debut=$(date +%s)

echo "##### A. SUISSE : swissBOUNDARIES3D 2026-01 (swisstopo)"
B=https://data.geo.admin.ch/ch.swisstopo.swissboundaries3d/swissboundaries3d_2026-01/swissboundaries3d_2026-01_2056_5728
for e in gpkg shp gdb; do tete "$B.$e.zip"; done
get ch/swissboundaries3d_2026-01_2056_5728.gpkg.zip "$B.gpkg.zip"
dezip ch/swissboundaries3d_2026-01_2056_5728.gpkg.zip ch/x
echo "--- GDAL lit-il directement le .gpkg.zip ?"
ogrinfo -ro -so ch/swissboundaries3d_2026-01_2056_5728.gpkg.zip 2>&1 | head -8 | c300
G=$(find ch/x -name '*.gpkg' | head -1); echo "   gpkg extrait : $G ($(stat -c %s "$G") octets)"
LG=$(ogrinfo -ro -so "$G" 2>/dev/null | grep -i -o -E '[A-Za-z_0-9]*landesgebiet[A-Za-z_0-9]*' | head -1)
echo "--- ogrinfo -so $LG"
oinfo "$G" "$LG"
$PYI py/ch.py "$G" 2>&1 | c300
echo "   [A : $(( $(date +%s) - t_debut )) s]"

echo
echo "##### B. ITALIE : ISTAT, confini delle unità amministrative 2026"
UI=https://www.istat.it/storage/cartografia/confini_amministrativi/non_generalizzati/2026/Limiti01012026.zip
UG=https://www.istat.it/storage/cartografia/confini_amministrativi/generalizzati/2026/Limiti01012026_g.zip
get it/Limiti01012026.zip "$UI"
dezip it/Limiti01012026.zip it/x Reg
get it/Limiti01012026_g.zip "$UG"
dezip it/Limiti01012026_g.zip it/xg Reg q
SHP=$(find it/x -iname 'Reg*.shp' | head -1); SHPG=$(find it/xg -iname 'Reg*.shp' | head -1)
echo "   regions : $SHP | generalise : $SHPG"
echo "--- ogrinfo -so -al"
oinfo -al "$SHP"
echo "   .prj : $(c300 < "${SHP%.shp}.prj")"; echo "   .cpg : $(cat "${SHP%.shp}.cpg" 2>/dev/null)"
$PYI py/it.py "$SHP" "$SHPG" 2>&1 | c300
echo "--- lecture distante sans télécharger l'archive"
INNER=${SHP#it/x/}
t0=$(date +%s); ogrinfo -ro -so -al "/vsizip//vsicurl/$UI/$INNER" 2>&1 | grep -E "Feature Count|ERROR|FAILURE" | c300; echo "   duree : $(( $(date +%s) - t0 )) s pour /vsizip//vsicurl/$UI/$INNER"
echo "   [B : $(( $(date +%s) - t_debut )) s]"

echo
echo "##### C. ESPAGNE : API OGC Features de l'IGN (unidades administrativas)"
API=https://api-features.ign.es
get es/root.json "$API/?f=json"
get es/conf.json "$API/conformance?f=json"
$PYI - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/es/root.json"))
    print("   service :", d.get("title"), "|", (d.get("description") or "")[:300].replace("\n", " "))
    c = json.load(open("/tmp/sonde/es/conf.json"))
    print("   classes de conformite :", [u.split("/spec/")[-1] for u in c.get("conformsTo", [])])
except Exception as e:
    print("   ERREUR", e)
PY
enc() { python3 -c "import sys, urllib.parse as u; print(u.quote(sys.argv[1], safe=''))" "$1"; }
NIV=https://inspire.ec.europa.eu/codelist/AdministrativeHierarchyLevel
get es/t.json "$API/collections/administrativeunit/items?f=json&limit=1&skipGeometry=true"
SKIP=$($PYI -c "import json; d=json.load(open('/tmp/sonde/es/t.json')); print('oui' if d['features'] and d['features'][0].get('geometry') is None else 'non')" 2>/dev/null)
echo "   skipGeometry=true respecte : $SKIP"
if [ "$SKIP" = oui ]; then
  for o in 1stOrder 3rdOrder; do
    get es/n.json "$API/collections/administrativeunit/items?f=json&limit=1&skipGeometry=true&nationallevel=$(enc "$NIV/$o")"
    $PYI -c "import json; d=json.load(open('/tmp/sonde/es/n.json')); print('   niveau $o : numberMatched', d.get('numberMatched'), '|', json.dumps(d['features'][0]['properties'], ensure_ascii=False)[:300] if d.get('features') else None)" 2>&1 | c300
  done
fi
get es/ccaa.json "$API/collections/administrativeunit/items?f=json&limit=50&skipGeometry=true&nationallevel=$(enc "$NIV/2ndOrder")"
$PYI py/es_liste.py es/ccaa.json es/codes.tsv 2>&1 | cut -c1-1600
while IFS=$'\t' read -r code nom; do
  get "es/$code.geojson" "$API/collections/administrativeunit/items?f=json&nationalcode=$code"
done < es/codes.tsv
$PYI py/es_geo.py es/codes.tsv 2>&1 | c300
echo "--- métadonnées du jeu (catalogue IDEE, fiche spaignLLM)"
get es/md.xml "https://www.idee.es/csw-inspire-idee/srv/spa/csw?SERVICE=CSW&VERSION=2.0.2&REQUEST=GetRecordById&outputSchema=http://www.isotc211.org/2005/gmd&ElementSetName=full&ID=spaignLLM"
$PYI - <<'PY'
import re
try:
    s = open("/tmp/sonde/es/md.xml", encoding="utf-8", errors="replace").read()
    def txt(x):
        return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", x)).strip()
    for tag in ("gmd:title", "gmd:dateStamp", "gmd:useLimitation", "gmd:otherConstraints", "gmd:denominator", "gmd:statement"):
        seen = []
        for m in re.findall(r"<%s[ >].*?</%s>" % (tag, tag), s, re.S):
            v = txt(m)
            if v and v not in seen:
                seen.append(v)
        print("  ", tag, ":", " || ".join(seen)[:800])
    print("   dates :", [txt(d) for d in re.findall(r"<gmd:CI_Date>.*?</gmd:CI_Date>", s, re.S)][:6])
except Exception as e:
    print("   ERREUR", e)
PY
echo "   [C : $(( $(date +%s) - t_debut )) s]"

echo
echo "##### D. OPENSTREETMAP : Andorre et Monaco"
get osm/monaco-latest.osm.pbf https://download.geofabrik.de/europe/monaco-latest.osm.pbf
get osm/andorra-latest.osm.pbf https://download.geofabrik.de/europe/andorra-latest.osm.pbf
$PYI py/osm_gf.py osm/monaco-latest.osm.pbf osm/andorra-latest.osm.pbf 2>&1 | cut -c1-420
printf '%s\n' '[out:json][timeout:120];' 'relation(id:36990,2220322,1124039,9407);' 'out geom;' > osm/q2.txt
for i in 1 2 3 4; do
  code=$(curl -sS -m 200 -A "$UA" -o osm/ovp2.json -w "%{http_code} %{size_download}o %{content_type}" --data-urlencode "data@osm/q2.txt" "https://overpass-api.de/api/interpreter" 2>&1)
  echo "  -> $code (essai $i)  POST https://overpass-api.de/api/interpreter  data=$(tr '\n' ' ' < osm/q2.txt)"
  case "$code" in 200*) break ;; esac
  sleep $((i * 20))
done
$PYI py/osm_ovp.py osm/ovp2.json 2>&1 | cut -c1-420
echo "   [D : $(( $(date +%s) - t_debut )) s]"

echo
echo "##### E. ECARTS LE LONG DES FRONTIERES COMMUNES (contours Etalab pour la France)"
get fr/departements-5m.geojson.gz https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/departements-5m.geojson.gz
gunzip -f fr/departements-5m.geojson.gz
$PYI py/ecarts.py fr/departements-5m.geojson 2>&1 | c300
echo "   [E : $(( $(date +%s) - t_debut )) s]"

echo
echo "##### F. LICENCES ET MENTIONS"
echo "--- swisstopo"
get lic/st.html "https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices"
texte lic/st.html 80000 | grep -i -A9 "source references must be attached" | c300 | head -12
FR=$(grep -o -E '<link[^>]+hreflang="fr"[^>]*>' lic/st.html | grep -o -E 'href="[^"]+"' | head -1 | sed -E 's/^href="//; s/"$//')
echo "   version française : ${FR:-introuvable dans la page}"
if [ -n "$FR" ]; then
  case "$FR" in http*) ;; *) FR="https://www.swisstopo.admin.ch$FR" ;; esac
  get lic/st-fr.html "$FR"
  texte lic/st-fr.html 80000 | grep -i -E "peuvent être|indication de la source|source est obligatoire|mention de la source|©|Source ?:" | awk 'length($0) > 8' | c300 | head -10
fi
get lic/sb.html "https://www.swisstopo.admin.ch/en/landscape-model-swissboundaries3d"
texte lic/sb.html 80000 | grep -i -E "accuracy|precision|updated|annual|Liechtenstein" | awk 'length($0) > 20' | c300 | head -8
echo "--- ISTAT"
get lic/istat.html "https://www.istat.it/notizia/confini-delle-unita-amministrative-a-fini-statistici-al-1-gennaio-2018-2/"
texte lic/istat.html 200000 | grep -i -E "versione generalizzata|scala non|sistema di riferimento" | cut -c1-900 | head -4
echo "--- IGN España / CNIG"
get lic/cnig.html "https://centrodedescargas.cnig.es/CentroDescargas/limites-municipales-provinciales-autonomicos"
texte lic/cnig.html 80000 | grep -i -A2 "conlleva la aceptaci" | cut -c1-1500 | head -5
get lic/ign.pdf "https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf"
(apt-get update -qq && apt-get install -y -qq poppler-utils) >/dev/null 2>&1
if command -v pdftotext >/dev/null 2>&1; then
  pdftotext -layout lic/ign.pdf lic/ign.txt; echo "   $(pdfinfo lic/ign.pdf 2>/dev/null | grep -i -E '^Pages' | tr -s ' ')"
  grep -v -E '^\s*$' lic/ign.txt | sed -E 's/\s+/ /g' | grep -i -E "CC|atribuci|reconoc|menci|origen|autor|obra derivada|gratuit|comercial" | cut -c1-420 | head -30
else
  echo "   pdftotext indisponible"
fi
echo "--- OpenStreetMap"
get lic/osmf.html "https://osmfoundation.org/wiki/Licence/Attribution_Guidelines"
texte lic/osmf.html 80000 | grep -i -E "© OpenStreetMap|attribution text|ODbL" | awk 'length($0) > 20' | c300 | head -8
get lic/gf.html "https://download.geofabrik.de/europe/monaco.html"
texte lic/gf.html 30000 | grep -i -E "ODbL|Open Database|OpenStreetMap contributors|licen|copyright" | c300 | head -6
echo "FIN frontieres-2 [$(( $(date +%s) - t_debut )) s]"
