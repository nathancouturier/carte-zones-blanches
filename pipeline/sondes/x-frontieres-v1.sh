#!/usr/bin/env bash
# Contre-vérification « Frontières et masques de pays », sonde frontieres-v1.
# Refait de façon indépendante : URL, couches, champs, filtres, SCR, surfaces, caractère terrestre des masques
# de la Suisse (swisstopo), de l'Italie (ISTAT), de l'Espagne (IGN), d'Andorre et de Monaco (OpenStreetMap, Geofabrik).
set -u
. "$(dirname "$0")/_lib.sh"
# Client générique : aucun identifiant personnel dans les requêtes vers des services tiers.
UA="sonde-verification/1.0"
export GDAL_HTTP_USERAGENT="$UA"
cd "$T"
mkdir -p py d/ch d/it d/es d/ad d/mc
tete() { curl -sS -I -L -m 60 -A "$UA" "$1" 2>&1 | tr -d '\r' | grep -i -E '^(HTTP/|content-length|content-type|last-modified|accept-ranges)' | tr '\n' ' ' | cut -c1-300; echo " <= $1"; }

CH_URL="https://data.geo.admin.ch/ch.swisstopo.swissboundaries3d/swissboundaries3d_2026-01/swissboundaries3d_2026-01_2056_5728.gpkg.zip"
IT_URL="https://www.istat.it/storage/cartografia/confini_amministrativi/non_generalizzati/2026/Limiti01012026.zip"
ES_URL="https://api-features.ign.es/collections/administrativeunit/items?f=json&nationalcode="
AD_URL="https://download.geofabrik.de/europe/andorra-latest.osm.pbf"
MC_URL="https://download.geofabrik.de/europe/monaco-latest.osm.pbf"

echo "##### A. CATALOGUE STAC SUISSE : quel est l'item le plus recent ?"
get stac-items.json "https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swissboundaries3d/items?limit=100"
python3 -I - stac-items.json <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
feats = j.get("features", [])
print("   %d item(s) ; liens de pagination : %s" % (len(feats), [l.get("rel") for l in j.get("links", [])]))
feats.sort(key=lambda f: f["properties"].get("datetime") or "")
print("   ids tries par datetime : " + ", ".join(f["id"].replace("swissboundaries3d_", "") for f in feats))
last = feats[-1]
print("   plus recent : %s | datetime %s | created %s | updated %s" % (last["id"], last["properties"].get("datetime"), last["properties"].get("created"), last["properties"].get("updated")))
for k, a in sorted(last.get("assets", {}).items()):
    print("     asset %s | type %s | epsg %s | href %s" % (k, a.get("type"), a.get("proj:epsg"), a.get("href")))
PY

echo
echo "##### B. EN-TETES DES CINQ TELECHARGEMENTS"
tete "$CH_URL"
tete "$IT_URL"
tete "${ES_URL}34090000000"
tete "$AD_URL"
tete "$MC_URL"

echo
echo "##### C. TELECHARGEMENTS"
get d/ch/swissboundaries3d_2026-01_2056_5728.gpkg.zip "$CH_URL"
get d/it/Limiti01012026.zip "$IT_URL"
for code in 34020000000 34090000000 34150000000 34160000000; do
  get "d/es/es-$code.geojson" "${ES_URL}$code"
done
get d/es/es-faux.geojson "${ES_URL}34990000000"
get d/es/es-total.json "https://api-features.ign.es/collections/administrativeunit/items?f=json&limit=1&skipGeometry=true"
get d/ad/andorra-latest.osm.pbf "$AD_URL"
get d/mc/monaco-latest.osm.pbf "$MC_URL"
ls -l d/ch d/it d/es d/ad d/mc | awk 'NF>=9 {print "   " $5, $9}'

echo
echo "##### D. OGRINFO BRUT (resume)"
echo "--- Suisse, couche tlm_landesgebiet"
ogrinfo -ro -so -nomd d/ch/swissboundaries3d_2026-01_2056_5728.gpkg.zip tlm_landesgebiet 2>&1 | grep -E '^(INFO|Layer name|Geometry|Feature Count|Extent|FID Column|Geometry Column|    ID\["EPSG"|PROJCRS|ERROR|FAILURE)' | cut -c1-200
ogrinfo -ro -so -nomd d/ch/swissboundaries3d_2026-01_2056_5728.gpkg.zip tlm_landesgebiet 2>&1 | grep -E '^[a-z_]+: [A-Z]' | tr '\n' ';' | cut -c1-600; echo
echo "--- Italie, lecture distante /vsizip//vsicurl/ (sans telecharger l'archive)"
t0=$(date +%s)
ogrinfo -ro -so -nomd "/vsizip//vsicurl/$IT_URL/Reg01012026/Reg01012026_WGS84.shp" Reg01012026_WGS84 2>&1 | grep -E '^(INFO|Layer name|Geometry|Feature Count|Extent|ERROR|FAILURE|[A-Za-z_]+: [A-Z][a-z0-9]+ \()' | tr '\n' ';' | cut -c1-600; echo
echo "   [lecture distante : $(( $(date +%s) - t0 )) s]"
echo "--- Italie, archive locale ouverte telle quelle"
ogrinfo -ro -so -nomd d/it/Limiti01012026.zip 2>&1 | head -3 | cut -c1-300

cat > py/v1.py <<'PY_FIN_SONDE'
# Contre-vérification « frontières », sonde v1 : sources de masques (CH, IT, ES, AD, MC).
# Pour chaque zone : ouverture comme le fait le pipeline, schéma, filtre, SCR, reprojection en EPSG:3857,
# surfaces (ellipsoïde, EPSG:3035, grille z12), caractère terrestre (points de contrôle choisis par le vérificateur).
import json
import math
import os
import sys
import time
import traceback
import zipfile

import numpy as np
from osgeo import gdal, ogr, osr

gdal.UseExceptions()
ogr.UseExceptions()
osr.UseExceptions()

D = sys.argv[1]
SEULEMENT = sys.argv[2].split(",") if len(sys.argv) > 2 else None
R = 6378137.0
ORIGIN = math.pi * R
RES = 2 * ORIGIN / (256 * 4096)
E2 = 0.00669437999014
BILAN = []


def srs(epsg):
    s = osr.SpatialReference()
    s.ImportFromEPSG(epsg)
    s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return s


WGS, MERC, LAEA = srs(4326), srs(3857), srs(3035)


def vers(src, dst):
    a = src.Clone()
    a.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return osr.CoordinateTransformation(a, dst)


MERC_LAEA = vers(MERC, LAEA)
MERC_WGS = vers(MERC, WGS)


def merc(lon, lat):
    return math.radians(lon) * R, math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * R


def lonlat(x, y):
    return math.degrees(x / R), math.degrees(2 * math.atan(math.exp(y / R)) - math.pi / 2)


def c(s, n=300):
    s = str(s)
    return s if len(s) <= n else s[: n - 3] + "..."


def nb_sommets(g):
    n = g.GetPointCount()
    for i in range(g.GetGeometryCount()):
        n += nb_sommets(g.GetGeometryRef(i))
    return n


def polygones(g):
    if g.GetGeometryName() == "POLYGON":
        return [g]
    out = []
    for i in range(g.GetGeometryCount()):
        out.extend(polygones(g.GetGeometryRef(i)))
    return out


def union(geoms):
    gc = ogr.Geometry(ogr.wkbGeometryCollection)
    for g in geoms:
        gc.AddGeometry(g if g.IsValid() else g.MakeValid())
    if hasattr(gc, "UnaryUnion"):
        return gc.UnaryUnion()
    out = None
    for i in range(gc.GetGeometryCount()):
        p = gc.GetGeometryRef(i)
        out = p.Clone() if out is None else out.Union(p)
    return out


def aire_laea(g3857):
    k = g3857.Clone()
    k.Transform(MERC_LAEA)
    return k.GetArea() / 1e6


def aire_geod(g3857):
    k = g3857.Clone()
    k.Transform(MERC_WGS)
    if not hasattr(k, "GeodesicArea"):
        return float("nan")
    try:
        return abs(k.GeodesicArea()) / 1e6
    except Exception as exc:  # noqa: BLE001
        print("   (GeodesicArea indisponible : %s)" % c(exc, 120))
        return float("nan")


def memoire_vecteur():
    try:
        ds = gdal.GetDriverByName("MEM").Create("", 0, 0, 0, gdal.GDT_Unknown)
        if ds is not None and ds.TestCapability(ogr.ODsCCreateLayer):
            return ds
    except Exception:  # noqa: BLE001
        pass
    return ogr.GetDriverByName("Memory").CreateDataSource("")


def grille_z12(geoms):
    """Rastérise sur la grille mondiale des pixels z12 (centre du pixel dans le polygone).
    Renvoie (pixels, surface au sol en km2, largeur, hauteur)."""
    env = [g.GetEnvelope() for g in geoms]
    minx, maxx = min(e[0] for e in env), max(e[1] for e in env)
    miny, maxy = min(e[2] for e in env), max(e[3] for e in env)
    col0, col1 = int(math.floor((minx + ORIGIN) / RES)), int(math.ceil((maxx + ORIGIN) / RES))
    row0, row1 = int(math.floor((ORIGIN - maxy) / RES)), int(math.ceil((ORIGIN - miny) / RES))
    w, h = col1 - col0, row1 - row0
    ras = gdal.GetDriverByName("MEM").Create("", w, h, 1, gdal.GDT_Byte)
    ras.SetGeoTransform((-ORIGIN + col0 * RES, RES, 0.0, ORIGIN - row0 * RES, 0.0, -RES))
    ras.SetProjection(MERC.ExportToWkt())
    vec = memoire_vecteur()
    lyr = vec.CreateLayer("g", MERC, ogr.wkbUnknown)
    for g in geoms:
        f = ogr.Feature(lyr.GetLayerDefn())
        f.SetGeometry(g)
        lyr.CreateFeature(f)
    gdal.RasterizeLayer(ras, [1], lyr, burn_values=[1])
    par_ligne = np.zeros(h, dtype=np.int64)
    band = ras.GetRasterBand(1)
    for r0 in range(0, h, 2048):
        n = min(2048, h - r0)
        par_ligne[r0 : r0 + n] = band.ReadAsArray(0, r0, w, n).sum(axis=1, dtype=np.int64)
    y = ORIGIN - (row0 + np.arange(h) + 0.5) * RES
    lat = 2 * np.arctan(np.exp(y / R)) - np.pi / 2
    # Facteur de surface exact du pseudo-Mercator sur l'ellipsoïde WGS 84 (sol / carte).
    fact = (1 - E2) * np.cos(lat) ** 2 / (1 - E2 * np.sin(lat) ** 2) ** 2
    return int(par_ligne.sum()), float((par_ligne * fact).sum() * RES * RES / 1e6), w, h


def champs(lyr):
    d = lyr.GetLayerDefn()
    return ["%s:%s" % (d.GetFieldDefn(i).GetName(), d.GetFieldDefn(i).GetTypeName()) for i in range(d.GetFieldCount())]


def attributs(f, sauf=()):
    out = []
    for i in range(f.GetFieldCount()):
        nom = f.GetFieldDefnRef(i).GetName()
        if nom in sauf or not f.IsFieldSetAndNotNull(i):
            continue
        out.append("%s=%s" % (nom, c(f.GetField(i), 90)))
    return " | ".join(out)


def decrit_scr(s):
    if s is None:
        return "AUCUN SCR"
    k = s.Clone()
    try:
        k.AutoIdentifyEPSG()
    except Exception:  # noqa: BLE001
        pass
    code = k.GetAuthorityCode(None)
    meilleur = ""
    try:
        m = s.FindMatches()
        if m:
            meilleur = " | meilleure correspondance EPSG:%s (%d %%)" % (m[0][0].GetAuthorityCode(None), m[0][1])
    except Exception:  # noqa: BLE001
        pass
    return "%s | autorite %s:%s%s | compose %s | geographique %s" % (
        s.GetName(), k.GetAuthorityName(None), code, meilleur, bool(s.IsCompound()), bool(s.IsGeographic()))


def charge(path, couche=None, filtre=None):
    """Même suite d'appels que czb.masks._load_vector_file : Open, couche, filtre, Clone, FlattenTo2D, Transform."""
    ds = ogr.Open(path)
    if ds is None:
        raise RuntimeError("impossible d'ouvrir " + path)
    lyr = ds.GetLayerByName(couche) if couche else ds.GetLayer(0)
    if lyr is None:
        raise RuntimeError("couche absente : %s" % couche)
    if filtre:
        lyr.SetAttributeFilter(filtre)
    to_merc = vers(lyr.GetSpatialRef(), MERC)
    geoms = []
    for f in lyr:
        g = f.GetGeometryRef()
        if g is None:
            continue
        g = g.Clone()
        g.FlattenTo2D()
        g.Transform(to_merc)
        geoms.append(g)
    return geoms


def points(zone, u, liste):
    """liste : (libellé, lon, lat, attendu) avec attendu = dedans, dehors ou info."""
    ecarts = 0
    for lib, lon, lat, attendu in liste:
        p = ogr.Geometry(ogr.wkbPoint)
        x, y = merc(lon, lat)
        p.AddPoint_2D(x, y)
        etat = "dedans" if u.Contains(p) else "dehors"
        if attendu == "info":
            verdict = "(info)"
        elif attendu == etat:
            verdict = "conforme"
        else:
            verdict = "*** ECART : attendu %s ***" % attendu
            ecarts += 1
        print("   point %-52s (%8.4f, %7.4f) : %s %s" % (lib, lon, lat, etat.upper() if attendu == "info" else etat, verdict))
    print("   => %s : %d point(s) teste(s), %d ecart(s)" % (zone, len(liste), ecarts))
    return ecarts


def trous(u, seuil_ha=0.0, maxi=12):
    out = []
    for p in polygones(u):
        for i in range(1, p.GetGeometryCount()):
            poly = ogr.Geometry(ogr.wkbPolygon)
            poly.AddGeometry(p.GetGeometryRef(i).Clone())
            ha = aire_laea(poly) * 100
            if ha >= seuil_ha:
                ct = poly.Centroid()
                out.append((ha,) + lonlat(ct.GetX(), ct.GetY()))
    out.sort(reverse=True)
    return out[:maxi], len(out)


def fiche(zone, geoms, officiel=None):
    """Bilan d'une zone : surfaces par trois méthodes à partir des géométries en EPSG:3857."""
    t0 = time.time()
    u = union(geoms)
    polys = polygones(u)
    env = u.GetEnvelope()
    w, s = lonlat(env[0], env[2])
    e, n = lonlat(env[1], env[3])
    a_geod, a_laea = aire_geod(u), aire_laea(u)
    somme = sum(aire_laea(g) for g in geoms)
    px, a_px, lw, lh = grille_z12(geoms)
    print("   FICHE %s : %d entite(s), %d polygone(s) apres union, %d sommets, valide %s" % (
        zone, len(geoms), len(polys), sum(nb_sommets(g) for g in geoms), u.IsValid()))
    print("     emprise lon %.5f a %.5f, lat %.5f a %.5f" % (w, e, s, n))
    print("     surface ellipsoide (GeodesicArea) %.3f km2 | EPSG:3035 union %.3f km2 (somme des entites %.3f) | grille z12 : %d pixels = %.3f km2 (fenetre %d x %d) [%.1f s]" % (
        a_geod, a_laea, somme, px, a_px, lw, lh, time.time() - t0))
    BILAN.append((zone, len(geoms), len(polys), a_geod, a_laea, px, a_px))
    return u


def section(nom, fn):
    if SEULEMENT and nom not in SEULEMENT:
        return
    print()
    print("##### %s" % nom)
    t0 = time.time()
    try:
        fn()
    except Exception:  # noqa: BLE001
        print("   !!! EXCEPTION dans la section %s" % nom)
        print(c(traceback.format_exc(), 1500))
    print("   [section %s : %.1f s]" % (nom, time.time() - t0))


def premier(*noms):
    for n in noms:
        if os.path.exists(n):
            return n
    return noms[0]


# ---------------------------------------------------------------------------------------------- Suisse
def suisse():
    path = os.path.join(D, "ch", "swissboundaries3d_2026-01_2056_5728.gpkg.zip")
    print("   fichier : %d octets" % os.path.getsize(path))
    with zipfile.ZipFile(path) as z:
        for i in z.infolist():
            print("   entree de l'archive : %s (%d octets)" % (i.filename, i.file_size))
    t0 = time.time()
    ds = ogr.Open(path)  # comme le pipeline : ogr.Open(str(local)) sur le .gpkg.zip
    print("   ogr.Open(<.gpkg.zip>) : pilote %s, %d couches" % (ds.GetDriver().GetName(), ds.GetLayerCount()))
    for i in range(ds.GetLayerCount()):
        lyr = ds.GetLayer(i)
        print("     couche %-20s %-18s %5d entites | %s" % (lyr.GetName(), ogr.GeometryTypeToName(lyr.GetGeomType()), lyr.GetFeatureCount(), decrit_scr(lyr.GetSpatialRef())))
    lyr = ds.GetLayerByName("tlm_landesgebiet")
    print("   champs de tlm_landesgebiet : " + c(", ".join(champs(lyr)), 600))
    to_merc = vers(lyr.GetSpatialRef(), MERC)
    for f in lyr:
        g = f.GetGeometryRef()
        plan = g.GetArea() / 1e6
        k = g.Clone()
        k.FlattenTo2D()
        k.Transform(to_merc)
        print("   entite : " + c(attributs(f, sauf=("uuid", "datum_erstellung", "erstellung_jahr", "erstellung_monat", "grund_aenderung", "herkunft_jahr", "herkunft_monat", "revision_jahr", "revision_monat", "revision_qualitaet")), 330))
        print("            %s, 3D %s, valide %s, %d sommets, surface plane LV95 %.3f km2, ellipsoide %.3f km2, EPSG:3035 %.3f km2" % (
            g.GetGeometryName(), bool(g.Is3D()), g.IsValid(), nb_sommets(g), plan, aire_geod(k), aire_laea(k)))
    for filtre in ("icc = 'CH'", "ICC = 'CH'", "name = 'Schweiz'"):
        try:
            lyr.SetAttributeFilter(filtre)
            print("   filtre %-18s : %d entite(s)" % (filtre, lyr.GetFeatureCount()))
        except Exception as exc:  # noqa: BLE001
            print("   filtre %-18s : exception %s" % (filtre, c(exc, 150)))
    ds = None
    geoms = charge(path, "tlm_landesgebiet", "icc = 'CH'")
    print("   chargement facon pipeline : %d geometrie(s), types %s, en %.1f s depuis l'ouverture" % (len(geoms), sorted({g.GetGeometryName() for g in geoms}), time.time() - t0))
    u = fiche("Suisse", geoms)
    gros, n = trous(u)
    print("   anneaux interieurs du masque suisse : %d" % n)
    for ha, lon, lat in gros:
        print("     trou %.1f ha, centre lon %.4f lat %.4f" % (ha, lon, lat))
    points("Suisse", u, [
        ("Berne, Palais federal", 7.4443, 46.9466, "dedans"),
        ("Zermatt", 7.7491, 46.0207, "dedans"),
        ("Mendrisio (Tessin)", 8.9850, 45.8700, "dedans"),
        ("Samnaun (Grisons)", 10.3600, 46.9440, "dedans"),
        ("Bale, Marktplatz", 7.5880, 47.5580, "dedans"),
        ("Geneve, rade (lac)", 6.1560, 46.2080, "dedans"),
        ("Leman, 3 km au sud de Morges (cote suisse)", 6.5000, 46.4800, "dedans"),
        ("Leman, 4 km au nord de Thonon (cote francaise)", 6.5000, 46.4100, "dehors"),
        ("lac Majeur devant Locarno", 8.8000, 46.1550, "dedans"),
        ("Vaduz (Liechtenstein)", 9.5215, 47.1410, "dehors"),
        ("Busingen am Hochrhein (enclave allemande)", 8.6900, 47.6970, "dehors"),
        ("Campione d'Italia (enclave italienne)", 8.9710, 45.9700, "dehors"),
        ("Constance, vieille ville (Allemagne)", 9.1750, 47.6600, "dehors"),
        ("Domodossola (Italie)", 8.2920, 46.1150, "dehors"),
        ("Chamonix (France)", 6.8690, 45.9240, "dehors"),
        ("lac de Constance, milieu de l'Obersee", 9.4500, 47.6000, "info"),
    ])


# ---------------------------------------------------------------------------------------------- Italie
def italie():
    z = os.path.join(D, "it", "Limiti01012026.zip")
    membre = "Reg01012026/Reg01012026_WGS84.shp"
    print("   fichier : %d octets" % os.path.getsize(z))
    with zipfile.ZipFile(z) as zf:
        infos = zf.infolist()
        print("   archive : %d entrees, %.1f Mo decompresses, methodes de compression %s" % (
            len(infos), sum(i.file_size for i in infos) / 1e6, sorted({i.compress_type for i in infos})))
        for i in infos:
            if i.filename.lower().endswith((".shp", ".cpg")) or (i.filename.lower().endswith(".prj") and "Reg" in i.filename):
                print("     %s (%d octets)" % (i.filename, i.file_size))
        try:
            print("   .prj : " + c(zf.read(membre[:-4] + ".prj").decode("utf-8", "replace").strip(), 260))
        except KeyError as exc:
            print("   .prj introuvable : %s" % exc)
    try:
        ds = ogr.Open(z)
        print("   ogr.Open(<archive.zip>) : %s" % ("None" if ds is None else "pilote %s, %d couche(s)" % (ds.GetDriver().GetName(), ds.GetLayerCount())))
    except Exception as exc:  # noqa: BLE001
        print("   ogr.Open(<archive.zip>) : exception " + c(exc, 260))
    path = "/vsizip/%s/%s" % (z, membre)  # forme locale, celle de czb.masks (cle member)
    t0 = time.time()
    ds = ogr.Open(path)
    lyr = ds.GetLayer(0)
    print("   ogr.Open(/vsizip/<archive locale>/%s) : pilote %s, couche %s, %s, %d entites" % (
        membre, ds.GetDriver().GetName(), lyr.GetName(), ogr.GeometryTypeToName(lyr.GetGeomType()), lyr.GetFeatureCount()))
    print("   SCR : " + decrit_scr(lyr.GetSpatialRef()))
    print("   champs : " + ", ".join(champs(lyr)))
    toutes = []
    for f in lyr:
        toutes.append("%s=%s" % (f.GetField("COD_REG"), f.GetField("DEN_REG")))
    print("   COD_REG=DEN_REG (%d) : %s" % (len(toutes), c(" ; ".join(toutes), 700)))
    filtre = "COD_REG IN (1, 2, 7)"
    lyr.SetAttributeFilter(filtre)
    print("   filtre %s : %d entite(s)" % (filtre, lyr.GetFeatureCount()))
    to_merc = vers(lyr.GetSpatialRef(), MERC)
    somme_attr = 0.0
    for f in lyr:
        g = f.GetGeometryRef()
        k = g.Clone()
        k.FlattenTo2D()
        k.Transform(to_merc)
        somme_attr += f.GetField("Shape_Area") / 1e6
        print("     COD_REG %s | %s | %s | valide %s | %d sommets | Shape_Area %.3f km2 | surface plane UTM %.3f | ellipsoide %.3f | EPSG:3035 %.3f" % (
            f.GetField("COD_REG"), f.GetField("DEN_REG"), g.GetGeometryName(), g.IsValid(), nb_sommets(g),
            f.GetField("Shape_Area") / 1e6, g.GetArea() / 1e6, aire_geod(k), aire_laea(k)))
    print("   somme des Shape_Area des trois regions : %.3f km2" % somme_attr)
    ds = None
    geoms = charge(path, None, filtre)
    print("   chargement facon pipeline (forme locale /vsizip/) : %d geometrie(s) en %.1f s" % (len(geoms), time.time() - t0))
    u = fiche("Italie (Piemonte, Valle d'Aosta, Liguria)", geoms)
    gros, n = trous(u)
    print("   anneaux interieurs du masque italien : %d ; les plus grands : %s" % (n, "; ".join("%.1f ha (%.4f, %.4f)" % t for t in gros[:6])))
    points("Italie", u, [
        ("Turin, Piazza Castello", 7.6860, 45.0710, "dedans"),
        ("Aoste", 7.3200, 45.7370, "dedans"),
        ("Genes, Piazza De Ferrari", 8.9340, 44.4070, "dedans"),
        ("La Spezia, centre", 9.8240, 44.1070, "dedans"),
        ("Vintimille, centre", 7.6080, 43.7910, "dedans"),
        ("ile Palmaria (golfe de La Spezia)", 9.8450, 44.0420, "dedans"),
        ("lac d'Orta", 8.4000, 45.8100, "dedans"),
        ("mer, 3 km au large du port de Genes", 8.9200, 44.3700, "dehors"),
        ("mer, 2,5 km au large de Sanremo", 7.7800, 43.7900, "dehors"),
        ("mer, 2 km au sud du cap de Portofino", 9.2100, 44.2800, "dehors"),
        ("mer, milieu du golfe de La Spezia", 9.8700, 44.0600, "dehors"),
        ("mer, 1 km devant Vintimille", 7.6080, 43.7780, "dehors"),
        ("Milan (Lombardie, hors perimetre)", 9.1900, 45.4640, "dehors"),
        ("Menton (France)", 7.5000, 43.7760, "dehors"),
        ("Monaco, Casino", 7.4283, 43.7392, "dehors"),
        ("lac Majeur, milieu entre Stresa et Laveno", 8.6000, 45.9000, "info"),
        ("mont Blanc, sommet (6.8652, 45.8326)", 6.8652, 45.8326, "info"),
        ("bassin du vieux port de Genes (approx.)", 8.9200, 44.4090, "info"),
    ])


# ---------------------------------------------------------------------------------------------- Espagne
def espagne():
    codes = [("34020000000", "Aragón"), ("34090000000", "Cataluña/Catalunya"),
             ("34150000000", "Comunidad Foral de Navarra"), ("34160000000", "País Vasco/Euskadi")]
    geoms = []
    for code, attendu in codes:
        p = os.path.join(D, "es", "es-%s.geojson" % code)
        brut = open(p, "rb").read()
        j = json.loads(brut)
        feats = j.get("features", [])
        print("   %s : %d octets | type %s | numberMatched %s | numberReturned %s | %d feature(s) | crs %s | liens %s" % (
            code, len(brut), j.get("type"), j.get("numberMatched"), j.get("numberReturned"), len(feats),
            c(j.get("crs"), 80), sorted({l.get("rel") for l in j.get("links", [])})))
        if not feats:
            print("     *** aucune entite ***")
            continue
        f0 = feats[0]
        co = f0["geometry"]["coordinates"]
        while isinstance(co[0], list):
            co = co[0]
        nom = f0.get("properties", {}).get("nameunit")
        print("     proprietes : %s" % c(json.dumps(f0.get("properties"), ensure_ascii=False), 330))
        print("     nameunit %r %s | geometrie %s | premier sommet %s | id %s" % (
            nom, "(conforme)" if nom == attendu else "*** ECART : attendu %r ***" % attendu, f0["geometry"]["type"], co, f0.get("id")))
        ds = ogr.Open(p)
        lyr = ds.GetLayer(0)
        to_merc = vers(lyr.GetSpatialRef(), MERC)
        for f in lyr:
            g = f.GetGeometryRef()
            k = g.Clone()
            k.FlattenTo2D()
            k.Transform(to_merc)
            geoms.append(k)
            print("     OGR : pilote %s | SCR %s | %s | valide %s | %d polygone(s) | %d sommets | ellipsoide %.3f km2 | EPSG:3035 %.3f km2" % (
                ds.GetDriver().GetName(), decrit_scr(lyr.GetSpatialRef()), g.GetGeometryName(), g.IsValid(), len(polygones(g)), nb_sommets(g), aire_geod(k), aire_laea(k)))
    for nom_f in ("es-faux.geojson", "es-total.json"):
        p = os.path.join(D, "es", nom_f)
        if os.path.exists(p):
            try:
                j = json.loads(open(p, "rb").read())
                print("   controle %s : numberMatched %s | numberReturned %s | %d feature(s)" % (nom_f, j.get("numberMatched"), j.get("numberReturned"), len(j.get("features", []))))
            except Exception as exc:  # noqa: BLE001
                print("   controle %s : reponse non JSON (%s) : %s" % (nom_f, c(exc, 80), c(open(p, "rb").read()[:200], 200)))
    u = fiche("Espagne (Aragon, Cataluna, Navarra, Pais Vasco)", geoms)
    gros, n = trous(u, seuil_ha=20.0)
    print("   anneaux interieurs de 20 ha ou plus dans le masque espagnol : %d : %s" % (n, "; ".join("%.1f ha (%.4f, %.4f)" % t for t in gros)))
    points("Espagne", u, [
        ("Barcelone, Placa de Catalunya", 2.1700, 41.3870, "dedans"),
        ("Saragosse, Plaza del Pilar", -0.8780, 41.6560, "dedans"),
        ("Pampelune", -1.6440, 42.8180, "dedans"),
        ("Bilbao", -2.9350, 43.2630, "dedans"),
        ("Vitoria-Gasteiz", -2.6720, 42.8470, "dedans"),
        ("Llivia (enclave en France)", 1.9800, 42.4650, "dedans"),
        ("Vielha (Val d'Aran)", 0.7970, 42.7020, "dedans"),
        ("Deltebre (delta de l'Ebre)", 0.7180, 40.7200, "dedans"),
        ("Petilla de Aragon (enclave navarraise)", -1.0940, 42.4590, "dedans"),
        ("Os de Civis (Espagne, acces par l'Andorre)", 1.4400, 42.5100, "dedans"),
        ("mer, 3 km au large de la Barceloneta", 2.2200, 41.3600, "dehors"),
        ("mer, golfe de Roses", 3.1700, 42.2000, "dehors"),
        ("mer, 1,5 km a l'est du cap de Creus", 3.3400, 42.3200, "dehors"),
        ("mer, 3 km au large de Tarragone", 1.2700, 41.0800, "dehors"),
        ("mer, 5 km a l'est du delta de l'Ebre", 0.9500, 40.7200, "dehors"),
        ("mer, 2,5 km au nord de Saint-Sebastien", -2.0000, 43.3500, "dehors"),
        ("Trevino (enclave de Burgos)", -2.7470, 42.7340, "dehors"),
        ("Logrono (La Rioja, hors perimetre)", -2.4450, 42.4650, "dehors"),
        ("Andorre-la-Vieille", 1.5218, 42.5075, "dehors"),
        ("Saint-Jean-de-Luz (France)", -1.6600, 43.3900, "dehors"),
        ("baie des Alfacs (delta de l'Ebre)", 0.6600, 40.6000, "info"),
        ("baie du Fangar (delta de l'Ebre)", 0.7500, 40.7800, "info"),
        ("zone Andorre/Espagne (1.4169, 42.4879)", 1.4169, 42.4879, "info"),
    ])


# ---------------------------------------------------------------------------------------------- Andorre
def andorre():
    p = premier(os.path.join(D, "ad", "andorra-latest.osm.pbf"), os.path.join(D, "ad", "andorra-latest.osm"))
    print("   fichier : %d octets" % os.path.getsize(p))
    ds = ogr.Open(p)
    print("   pilote %s, couches : %s" % (ds.GetDriver().GetName(), ", ".join(ds.GetLayer(i).GetName() for i in range(ds.GetLayerCount()))))
    lyr = ds.GetLayerByName("multipolygons")
    print("   champs de multipolygons : " + c(", ".join(champs(lyr)), 500))
    print("   SCR : " + decrit_scr(lyr.GetSpatialRef()))
    ds = None
    for filtre in ("osm_id = '9407'", "osm_id = 9407", "admin_level = '2'"):
        try:
            ds = ogr.Open(p)
            lyr = ds.GetLayerByName("multipolygons")
            lyr.SetAttributeFilter(filtre)
            n = 0
            for f in lyr:
                n += 1
                g = f.GetGeometryRef()
                print("     [%s] %s | %s, %d polygone(s), %d sommets" % (filtre, c(attributs(f), 330), g.GetGeometryName(), len(polygones(g)), nb_sommets(g)))
            print("   filtre %-20s : %d entite(s)" % (filtre, n))
            ds = None
        except Exception as exc:  # noqa: BLE001
            print("   filtre %-20s : exception %s" % (filtre, c(exc, 200)))
    t0 = time.time()
    geoms = charge(p, "multipolygons", "osm_id = '9407'")
    print("   chargement facon pipeline : %d geometrie(s) en %.1f s" % (len(geoms), time.time() - t0))
    u = fiche("Andorre", geoms)
    points("Andorre", u, [
        ("Andorre-la-Vieille", 1.5218, 42.5075, "dedans"),
        ("Pas de la Case", 1.7300, 42.5420, "dedans"),
        ("Ordino", 1.5330, 42.5560, "dedans"),
        ("Os de Civis (Espagne)", 1.4400, 42.5100, "dehors"),
        ("La Seu d'Urgell (Espagne)", 1.4560, 42.3580, "dehors"),
        ("L'Hospitalet-pres-l'Andorre (France)", 1.8000, 42.5900, "dehors"),
        ("zone Andorre/Espagne (1.4169, 42.4879)", 1.4169, 42.4879, "info"),
        ("zone Andorre/Espagne (1.6701, 42.4971)", 1.6701, 42.4971, "info"),
        ("zone Andorre/Espagne (1.5566, 42.4444)", 1.5566, 42.4444, "info"),
    ])


# ---------------------------------------------------------------------------------------------- Monaco
def lignes(g, ml, compte):
    n = g.GetGeometryName()
    compte[n] = compte.get(n, 0) + 1
    if n in ("LINESTRING", "LINEARRING"):
        ls = ogr.Geometry(ogr.wkbLineString)
        for i in range(g.GetPointCount()):
            x, y = g.GetPoint_2D(i)
            ls.AddPoint_2D(x, y)
        ml.AddGeometry(ls)
    else:
        for i in range(g.GetGeometryCount()):
            lignes(g.GetGeometryRef(i), ml, compte)


def monaco():
    p = premier(os.path.join(D, "mc", "monaco-latest.osm.pbf"), os.path.join(D, "mc", "monaco-latest.osm"))
    print("   fichier : %d octets" % os.path.getsize(p))
    ds = ogr.Open(p)
    print("   pilote %s, couches : %s" % (ds.GetDriver().GetName(), ", ".join(ds.GetLayer(i).GetName() for i in range(ds.GetLayerCount()))))
    lyr = ds.GetLayerByName("other_relations")
    print("   champs de other_relations : " + c(", ".join(champs(lyr)), 300))
    to_merc = vers(lyr.GetSpatialRef(), MERC)
    ds = None
    mp = {}
    for oid in ("1124039", "10691624", "2220322", "36990"):
        ds = ogr.Open(p)
        lyr = ds.GetLayerByName("multipolygons")
        lyr.SetAttributeFilter("osm_id = '%s'" % oid)
        n = 0
        for f in lyr:
            n += 1
            k = f.GetGeometryRef().Clone()
            k.Transform(to_merc)
            mp[oid] = k
            print("   multipolygons osm_id %s : %s | %d polygone(s) | ellipsoide %.4f km2 | EPSG:3035 %.4f km2" % (
                oid, c(attributs(f, sauf=("osm_way_id",)), 230), len(polygones(k)), aire_geod(k), aire_laea(k)))
        if n == 0:
            print("   multipolygons osm_id %s : 0 entite" % oid)
        ds = None
    # Toutes les relations de other_relations qui parlent de land_area ou de Monaco
    ds = ogr.Open(p)
    lyr = ds.GetLayerByName("other_relations")
    total = 0
    for f in lyr:
        total += 1
        a = attributs(f)
        if "land_area" in a or f.GetField("osm_id") == "36990":
            print("   other_relations : " + c(a, 420))
    print("   other_relations : %d relation(s) au total dans l'extrait" % total)
    ds = None
    ds = ogr.Open(p)
    lyr = ds.GetLayerByName("other_relations")
    lyr.SetAttributeFilter("osm_id = '36990'")
    feats = [f for f in lyr]
    print("   filtre osm_id = '36990' sur other_relations : %d entite(s)" % len(feats))
    g = feats[0].GetGeometryRef()
    ml = ogr.Geometry(ogr.wkbMultiLineString)
    compte = {}
    lignes(g, ml, compte)
    faces = ml.Polygonize()
    print("   geometrie %s ; elements %s ; %d lignes rassemblees ; Polygonize -> %s, %d face(s)" % (
        g.GetGeometryName(), compte, ml.GetGeometryCount(), faces.GetGeometryName(), faces.GetGeometryCount()))
    geoms = []
    for i in range(faces.GetGeometryCount()):
        k = faces.GetGeometryRef(i).Clone()
        k.Transform(to_merc)
        geoms.append(k)
        ct = k.Centroid()
        print("     face %d : %s, %d anneau(x), %d sommets, %.4f ha, centre lon %.5f lat %.5f" % (
            (i + 1, k.GetGeometryName(), k.GetGeometryCount(), nb_sommets(k), aire_laea(k) * 100) + lonlat(ct.GetX(), ct.GetY())))
    ds = None
    u = fiche("Monaco (relation 36990, terre ferme)", geoms)
    for oid, lib in (("1124039", "pays, admin_level 2"), ("2220322", "commune"), ("10691624", "eaux territoriales")):
        if oid in mp:
            a = mp[oid]
            print("   terre ferme contre %s (%s) : terre hors de ce polygone %.4f ha ; ce polygone hors de la terre %.2f ha" % (
                oid, lib, aire_laea(u.Difference(a)) * 100, aire_laea(a.Difference(u)) * 100))
    if "1124039" in mp and "10691624" in mp:
        reste = mp["1124039"].Difference(mp["10691624"])
        print("   pays (1124039) moins eaux territoriales (10691624) : %.4f km2 ; difference symetrique avec la terre ferme : %.2f ha" % (
            aire_laea(reste), aire_laea(reste.SymDifference(u)) * 100))
    points("Monaco", u, [
        ("Palais princier", 7.4203, 43.7313, "dedans"),
        ("Casino de Monte-Carlo", 7.4283, 43.7392, "dedans"),
        ("Stade Louis-II (Fontvieille)", 7.4155, 43.7275, "dedans"),
        ("mer, 400 m a l'est de la digue du port Hercule", 7.4350, 43.7330, "dehors"),
        ("mer, 350 m au sud-est du Musee oceanographique", 7.4290, 43.7285, "dehors"),
        ("mer, 1 km au large du Larvotto", 7.4480, 43.7420, "dehors"),
        ("Cap-d'Ail, centre (France)", 7.4050, 43.7210, "dehors"),
        ("Beausoleil, haut de la ville (France)", 7.4230, 43.7460, "dehors"),
        ("Roquebrune-Cap-Martin (France)", 7.4500, 43.7550, "dehors"),
        ("bassin du port Hercule", 7.4235, 43.7355, "info"),
        ("bassin du port de Fontvieille", 7.4215, 43.7290, "info"),
        ("Mareterra (terre gagnee sur la mer)", 7.4330, 43.7405, "info"),
        ("Jardin exotique", 7.4140, 43.7315, "info"),
    ])


print("GDAL %s | GEOS %s | numpy %s | GeodesicArea %s | UnaryUnion %s" % (
    gdal.__version__, gdal.VersionInfo("BUILD_INFO").split("GEOS_VERSION=")[-1].split("\n")[0] if "GEOS_VERSION=" in gdal.VersionInfo("BUILD_INFO") else "?",
    np.__version__, hasattr(ogr.Geometry, "GeodesicArea"), hasattr(ogr.Geometry, "UnaryUnion")))
section("SUISSE", suisse)
section("ITALIE", italie)
section("ESPAGNE", espagne)
section("ANDORRE", andorre)
section("MONACO", monaco)
print()
print("##### BILAN (surfaces recalculees a partir des geometries reprojetees en EPSG:3857)")
print("   %-48s %8s %9s %14s %14s %12s %14s" % ("zone", "entites", "polygones", "ellipsoide km2", "EPSG:3035 km2", "pixels z12", "grille z12 km2"))
for zone, n, npoly, ag, al, px, apx in BILAN:
    print("   %-48s %8d %9d %14.3f %14.3f %12d %14.3f" % (zone, n, npoly, ag, al, px, apx))
PY_FIN_SONDE
python3 -I py/v1.py "$T/d" 2>&1 | grep -v "memory leak" | cut -c1-720
echo "FIN (code python : ${PIPESTATUS[0]})"
