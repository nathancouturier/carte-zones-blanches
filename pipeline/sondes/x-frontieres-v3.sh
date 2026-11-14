#!/usr/bin/env bash
# Contre-vérification « Frontières et masques de pays », sonde frontieres-v3.
# 1. Geofabrik (injoignable pendant la sonde v1) : nouvel essai avec reprises, et repli par l'API OSM.
# 2. Andorre et Monaco : couches, filtres, surfaces, caractère terrestre (mêmes contrôles que la sonde v1).
# 3. Écarts entre contours voisins, trous fermés de l'union, comptes de pixels sur la grille z12 (code du vérificateur).
# 4. Licence de l'IGN España (PDF, en erreur 502 pendant la sonde v2) et surface officielle de la Catalogne (Idescat).
set -u
. "$(dirname "$0")/_lib.sh"
# Client générique : aucun identifiant personnel dans les requêtes vers des services tiers.
UA="sonde-verification/1.0"
export GDAL_HTTP_USERAGENT="$UA"
cd "$T"
mkdir -p py d/fr d/ch d/it d/es d/ad d/mc lic

CH_URL="https://data.geo.admin.ch/ch.swisstopo.swissboundaries3d/swissboundaries3d_2026-01/swissboundaries3d_2026-01_2056_5728.gpkg.zip"
IT_URL="https://www.istat.it/storage/cartografia/confini_amministrativi/non_generalizzati/2026/Limiti01012026.zip"
ES_URL="https://api-features.ign.es/collections/administrativeunit/items?f=json&nationalcode="
AD_URL="https://download.geofabrik.de/europe/andorra-latest.osm.pbf"
MC_URL="https://download.geofabrik.de/europe/monaco-latest.osm.pbf"
FR_URL="https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/departements-5m.geojson.gz"

essais() { # essais <nb> <pause_s> <fichier> <url> : télécharge, avec reprises tant que le code HTTP n'est pas 200
  local i code
  for i in $(seq 1 "$1"); do
    code=$(curl -sS -L -m 180 -A "$UA" -o "$3" -w "%{http_code} %{size_download}o en %{time_total}s (serveur %{remote_ip})" "$4" 2>&1 | tr '\n' ' ' | cut -c1-200)
    echo "   essai $i : $code  $4"
    case "$code" in 200*) return 0 ;; esac
    rm -f "$3"
    [ "$i" -lt "$1" ] && sleep "$2"
  done
  return 1
}

echo "##### 1. GEOFABRIK : nouvel essai (jusqu'a 6 fois, 20 s d'attente)"
date -u +"   heure UTC : %Y-%m-%d %H:%M:%S"
n_ad=6
essais $n_ad 20 d/ad/andorra-latest.osm.pbf "$AD_URL"; gf_ad=$?
if [ "$gf_ad" -ne 0 ]; then n_mc=2; else n_mc=6; fi
essais $n_mc 20 d/mc/monaco-latest.osm.pbf "$MC_URL"; gf_mc=$?
echo "   bilan Geofabrik : andorre $([ $gf_ad -eq 0 ] && echo OK || echo ECHEC), monaco $([ $gf_mc -eq 0 ] && echo OK || echo ECHEC)"

echo
echo "##### 2. REPLI : API OSM, relation/<id>/full (XML lisible par le pilote OSM de GDAL)"
get d/ad/api-9407.osm "https://api.openstreetmap.org/api/0.6/relation/9407/full"
get d/mc/api-36990.osm "https://api.openstreetmap.org/api/0.6/relation/36990/full"
for f in d/ad/api-9407.osm d/mc/api-36990.osm; do
  echo "   $f : $(wc -c < "$f") octets, $(grep -c '<node ' "$f") noeuds, $(grep -c '<way ' "$f") chemins, $(grep -c '<relation ' "$f") relation(s) ; debut : $(head -c 120 "$f" | tr '\n' ' ')"
done
if [ "$gf_ad" -ne 0 ]; then cp d/ad/api-9407.osm d/ad/andorra-latest.osm; echo "   Andorre : la suite utilise la reponse de l'API OSM"; fi
if [ "$gf_mc" -ne 0 ]; then cp d/mc/api-36990.osm d/mc/monaco-latest.osm; echo "   Monaco : la suite utilise la reponse de l'API OSM"; fi

echo
echo "##### 3. AUTRES TELECHARGEMENTS"
get d/fr/departements.geojson.gz "$FR_URL"
gunzip -f d/fr/departements.geojson.gz && echo "   departements.geojson : $(wc -c < d/fr/departements.geojson) octets"
get d/ch/swissboundaries3d_2026-01_2056_5728.gpkg.zip "$CH_URL"
for code in 34020000000 34090000000 34150000000 34160000000; do
  get "d/es/es-$code.geojson" "${ES_URL}$code"
done
IT_SRC="/vsizip//vsicurl/$IT_URL/Reg01012026/Reg01012026_WGS84.shp"
if ogrinfo -ro -so -nomd "$IT_SRC" Reg01012026_WGS84 2>&1 | grep -q '^Feature Count: 20'; then
  echo "   Italie : lecture distante /vsizip//vsicurl/ disponible (20 entites)"
else
  echo "   Italie : lecture distante indisponible, telechargement de l'archive"
  get d/it/Limiti01012026.zip "$IT_URL"
  IT_SRC="/vsizip/$T/d/it/Limiti01012026.zip/Reg01012026/Reg01012026_WGS84.shp"
fi

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
cat > py/v3.py <<'PY_FIN_SONDE'
# Contre-vérification « frontières », sonde v3 : écarts entre contours voisins, trous de l'union, grille z12.
# Code écrit par le vérificateur (aucune reprise des scripts de l'enquêteur). Surfaces en EPSG:3035 (équivalente).
import json
import math
import os
import sys
import time
import traceback

import numpy as np
from osgeo import gdal, ogr, osr

gdal.UseExceptions()
ogr.UseExceptions()
osr.UseExceptions()

R = 6378137.0
ORIGIN = math.pi * R
RES = 2 * ORIGIN / (256 * 4096)
ORDRE = ["FR", "CH", "IT", "ES", "AD", "MC"]
CODE = {"FR": 1, "CH": 2, "IT": 3, "ES": 4, "AD": 5, "MC": 6}
NOM = {v: k for k, v in CODE.items()}
DEPS = ["01", "39", "25", "90", "68", "74", "73", "05", "04", "06", "64", "65", "31", "09", "66"]
SEUIL_HA = 100.0
IT_MEMBRE = "Reg01012026/Reg01012026_WGS84.shp"


def srs(epsg):
    s = osr.SpatialReference()
    s.ImportFromEPSG(epsg)
    s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return s


WGS, MERC, LAEA = srs(4326), srs(3857), srs(3035)
MERC_WKT = MERC.ExportToWkt()


def vers(src, dst):
    a = src.Clone()
    a.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return osr.CoordinateTransformation(a, dst)


MERC_LAEA = vers(MERC, LAEA)


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
    if g is None or g.IsEmpty():
        return []
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


def ha(g3857):
    """Surface au sol en hectares (EPSG:3035) d'une géométrie donnée en EPSG:3857."""
    k = g3857.Clone()
    k.Transform(MERC_LAEA)
    return k.GetArea() / 1e4


def largeur_max(g3857, borne=2000.0):
    """Largeur maximale approchée (m) : deux fois le plus grand retrait qui laisse quelque chose (EPSG:3035)."""
    k = g3857.Clone()
    k.Transform(MERC_LAEA)
    bas, haut = 0.0, borne
    if not k.Buffer(-haut / 2).IsEmpty():
        return haut
    while haut - bas > 2.0:
        mid = (bas + haut) / 2
        if k.Buffer(-mid / 2).IsEmpty():
            haut = mid
        else:
            bas = mid
    return bas


def centre(g3857):
    ct = g3857.Centroid()
    return lonlat(ct.GetX(), ct.GetY())


def charge(path, couche=None, filtre=None, garde=None):
    ds = ogr.Open(path)
    if ds is None:
        raise RuntimeError("impossible d'ouvrir " + path)
    lyr = ds.GetLayerByName(couche) if couche else ds.GetLayer(0)
    if filtre:
        lyr.SetAttributeFilter(filtre)
    to_merc = vers(lyr.GetSpatialRef(), MERC)
    geoms = []
    for f in lyr:
        if garde is not None and not garde(f):
            continue
        g = f.GetGeometryRef()
        if g is None:
            continue
        g = g.Clone()
        g.FlattenTo2D()
        g.Transform(to_merc)
        geoms.append(g)
    return geoms


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


def charge_terre_osm(path, relation):
    ds = ogr.Open(path)
    lyr = ds.GetLayerByName("other_relations")
    lyr.SetAttributeFilter("osm_id = '%s'" % relation)
    f = lyr.GetNextFeature()
    ml = ogr.Geometry(ogr.wkbMultiLineString)
    lignes(f.GetGeometryRef(), ml)
    faces = ml.Polygonize()
    to_merc = vers(lyr.GetSpatialRef(), MERC)
    out = []
    for i in range(faces.GetGeometryCount()):
        k = faces.GetGeometryRef(i).Clone()
        k.Transform(to_merc)
        out.append(k)
    return out


def premier(*noms):
    for n in noms:
        if os.path.exists(n):
            return n
    return noms[0]


# ------------------------------------------------------------------------------------------ trous de l'union
def anneaux_interieurs(u):
    out = []
    for p in polygones(u):
        for i in range(1, p.GetGeometryCount()):
            t = ogr.Geometry(ogr.wkbPolygon)
            t.AddGeometry(p.GetGeometryRef(i).Clone())
            out.append(t)
    return out


def recense(titre, trous_ha, details=None):
    """trous_ha : liste de surfaces en ha. Affiche la répartition par classe."""
    classes = [(0, 1), (1, 10), (10, 50), (50, 100), (100, float("inf"))]
    print("   %s : %d trou(s) ferme(s), %.1f ha au total" % (titre, len(trous_ha), sum(trous_ha)))
    for a, b in classes:
        sel = [h for h in trous_ha if a <= h < b]
        print("     de %s a %s ha : %d trou(s), %.1f ha" % (a, "plus" if b == float("inf") else b, len(sel), sum(sel)))
    petits = [h for h in trous_ha if h < SEUIL_HA]
    grands = [h for h in trous_ha if h >= SEUIL_HA]
    print("     plus grand trou sous %d ha : %.2f ha ; plus petit trou de %d ha ou plus : %s ; total sous le seuil : %.1f ha" % (
        SEUIL_HA, max(petits) if petits else 0.0, SEUIL_HA, ("%.1f ha" % min(grands)) if grands else "aucun", sum(petits)))


def comble(par_pays, tout, ordre):
    """Répartit les trous fermés de moins de SEUIL_HA : chacun va au pays le moins prioritaire qui le touche.
    Renvoie ({pays: [trous]}, liste (ha, trou) de tous les trous, trous orphelins)."""
    prep = {iso: (g.GetEnvelope(), g.CreatePreparedGeometry()) for iso, g in par_pays.items()}
    donnes = {iso: [] for iso in ordre}
    tous, orphelins = [], 0
    for t in anneaux_interieurs(tout):
        s = ha(t)
        tous.append((s, t))
        if s >= SEUIL_HA:
            continue
        sonde = t.Buffer(0.01)
        x0, x1, y0, y1 = sonde.GetEnvelope()
        for iso in reversed(ordre):
            if iso not in prep:
                continue
            (m0, m1, n0, n1), p = prep[iso]
            if x1 < m0 or x0 > m1 or y1 < n0 or y0 > n1:
                continue
            if p.Intersects(sonde):
                donnes[iso].append(t)
                break
        else:
            orphelins += 1
    return donnes, tous, orphelins


# ------------------------------------------------------------------------------------------ grille z12
def memoire_vecteur():
    try:
        ds = gdal.GetDriverByName("MEM").Create("", 0, 0, 0, gdal.GDT_Unknown)
        if ds is not None and ds.TestCapability(ogr.ODsCCreateLayer):
            return ds
    except Exception:  # noqa: BLE001
        pass
    return ogr.GetDriverByName("Memory").CreateDataSource("")


class Grille:
    def __init__(self, geoms_par_pays):
        env = [g.GetEnvelope() for gs in geoms_par_pays.values() for g in gs]
        minx, maxx = min(e[0] for e in env), max(e[1] for e in env)
        miny, maxy = min(e[2] for e in env), max(e[3] for e in env)
        ts = 256 * RES
        self.tx0, self.tx1 = int(math.floor((minx + ORIGIN) / ts)), int(math.floor((maxx + ORIGIN) / ts))
        self.ty0, self.ty1 = int(math.floor((ORIGIN - maxy) / ts)), int(math.floor((ORIGIN - miny) / ts))
        self.w, self.h = (self.tx1 - self.tx0 + 1) * 256, (self.ty1 - self.ty0 + 1) * 256
        self.x0, self.y0 = -ORIGIN + self.tx0 * ts, ORIGIN - self.ty0 * ts
        self.pays = np.zeros((self.h, self.w), dtype=np.uint8)

    def fenetres(self, geoms, cote=8192):
        env = [g.GetEnvelope() for g in geoms]
        minx, maxx = min(e[0] for e in env), max(e[1] for e in env)
        miny, maxy = min(e[2] for e in env), max(e[3] for e in env)
        c0 = max(0, int(math.floor((minx - self.x0) / RES)))
        c1 = min(self.w, int(math.ceil((maxx - self.x0) / RES)))
        r0 = max(0, int(math.floor((self.y0 - maxy) / RES)))
        r1 = min(self.h, int(math.ceil((self.y0 - miny) / RES)))
        for r in range(r0, r1, cote):
            for k in range(c0, c1, cote):
                yield k, r, min(cote, c1 - k), min(cote, r1 - r)

    def masque(self, geoms, col0, row0, w, h):
        ras = gdal.GetDriverByName("MEM").Create("", w, h, 1, gdal.GDT_Byte)
        ras.SetGeoTransform((self.x0 + col0 * RES, RES, 0.0, self.y0 - row0 * RES, 0.0, -RES))
        ras.SetProjection(MERC_WKT)
        vec = memoire_vecteur()
        lyr = vec.CreateLayer("g", MERC, ogr.wkbUnknown)
        for g in geoms:
            f = ogr.Feature(lyr.GetLayerDefn())
            f.SetGeometry(g)
            lyr.CreateFeature(f)
        gdal.RasterizeLayer(ras, [1], lyr, burn_values=[1])
        return ras.GetRasterBand(1).ReadAsArray().astype(bool)

    def revendique(self, geoms, code, un_par_un=True):
        """Le premier pays garde le pixel. Renvoie (pixels gagnés, {pays déjà en place: pixels refusés})."""
        gagne, refuse = 0, {}
        lots = [[g] for g in geoms] if un_par_un else [geoms]
        for lot in lots:
            for col0, row0, w, h in self.fenetres(lot):
                m = self.masque(lot, col0, row0, w, h)
                if not m.any():
                    continue
                sub = self.pays[row0 : row0 + h, col0 : col0 + w]
                libre = m & (sub == 0)
                pris = m & (sub != 0) & (sub != code)
                if pris.any():
                    vals, nb = np.unique(sub[pris], return_counts=True)
                    for v, n in zip(vals, nb):
                        refuse[NOM[int(v)]] = refuse.get(NOM[int(v)], 0) + int(n)
                gagne += int(libre.sum())
                sub[libre] = code
        return gagne, refuse

    def coinces(self, bande=2048):
        """Pixels sans pays dont le voisinage 3 x 3 contient au moins deux pays différents."""
        total = 0
        exemples = []
        for a in range(0, self.h, bande):
            b = min(self.h, a + bande)
            sub = np.zeros((b - a + 2, self.w + 2), dtype=np.uint8)
            lo, hi = max(0, a - 1), min(self.h, b + 1)
            sub[(lo - (a - 1)) : (lo - (a - 1)) + (hi - lo), 1:-1] = self.pays[lo:hi]
            v = np.maximum(np.maximum(sub[:-2], sub[1:-1]), sub[2:])
            maxi = np.maximum(np.maximum(v[:, :-2], v[:, 1:-1]), v[:, 2:])
            sub2 = np.where(sub == 0, np.uint8(255), sub)
            v = np.minimum(np.minimum(sub2[:-2], sub2[1:-1]), sub2[2:])
            mini = np.minimum(np.minimum(v[:, :-2], v[:, 1:-1]), v[:, 2:])
            coince = (sub[1:-1, 1:-1] == 0) & (maxi != 0) & (mini != maxi)
            n = int(coince.sum())
            total += n
            if n and len(exemples) < 6:
                rr, cc = np.nonzero(coince)
                i = len(rr) // 2
                x = self.x0 + (cc[i] + 0.5) * RES
                y = self.y0 - (a + rr[i] + 0.5) * RES
                exemples.append("(%.4f, %.4f) entre %s et %s" % (lonlat(x, y) + (NOM[int(mini[rr[i], cc[i]])], NOM[int(maxi[rr[i], cc[i]])])))
        return total, exemples

    def compte(self):
        vals, nb = np.unique(self.pays, return_counts=True)
        return {NOM.get(int(v), "aucun"): int(n) for v, n in zip(vals, nb)}


# ------------------------------------------------------------------------------------------ paires
def paire(nom, a, b, details=3):
    t0 = time.time()
    inter = a.Intersection(b)
    morceaux = sorted(((ha(p), p) for p in polygones(inter)), key=lambda t: -t[0])
    tot = sum(m[0] for m in morceaux)
    u = union([a, b])
    tr = sorted(((ha(t), t) for t in anneaux_interieurs(u)), key=lambda t: -t[0])
    petits = [t for t in tr if t[0] < SEUIL_HA]
    grands = [t for t in tr if t[0] >= SEUIL_HA]
    print("   PAIRE %s [%.1f s]" % (nom, time.time() - t0))
    print("     recouvrement : %.2f ha en %d morceau(x)%s" % (tot, len(morceaux), "".join(
        " ; %.2f ha, large de %.0f m, vers (%.4f, %.4f)" % ((m[0], largeur_max(m[1])) + centre(m[1])) for m in morceaux[:details])))
    print("     trous fermes de moins de %d ha : %.2f ha en %d trou(s) (%d de 10 ha ou plus, %d de 1 a 10 ha)%s" % (
        SEUIL_HA, sum(t[0] for t in petits), len(petits), sum(1 for t in petits if t[0] >= 10), sum(1 for t in petits if 1 <= t[0] < 10), "".join(
            " ; %.2f ha, large de %.0f m, vers (%.4f, %.4f)" % ((t[0], largeur_max(t[1])) + centre(t[1])) for t in petits[:details])))
    if grands:
        print("     trous de %d ha ou plus : %s" % (SEUIL_HA, " ; ".join("%.1f ha vers (%.4f, %.4f)" % ((t[0],) + centre(t[1])) for t in grands)))


def main(D, it_source):
    t00 = time.time()
    print("GDAL %s | numpy %s | UnaryUnion %s" % (gdal.__version__, np.__version__, hasattr(ogr.Geometry, "UnaryUnion")))
    print()
    print("##### A. CHARGEMENT DES MASQUES (EPSG:3857)")
    geoms = {}
    t0 = time.time()
    fr_par_dep = {}
    ds = ogr.Open(os.path.join(D, "fr", "departements.geojson"))
    lyr = ds.GetLayer(0)
    d = lyr.GetLayerDefn()
    print("   France (Etalab) : %d entites, champs %s, SCR %s" % (lyr.GetFeatureCount(), [d.GetFieldDefn(i).GetName() for i in range(d.GetFieldCount())], lyr.GetSpatialRef().GetName()))
    to_merc = vers(lyr.GetSpatialRef(), MERC)
    for f in lyr:
        code = f.GetField("code")
        if code in DEPS:
            g = f.GetGeometryRef().Clone()
            g.FlattenTo2D()
            g.Transform(to_merc)
            fr_par_dep[code] = g
    ds = None
    manquants = [k for k in DEPS if k not in fr_par_dep]
    print("   departements frontaliers retenus : %d sur %d%s" % (len(fr_par_dep), len(DEPS), (" ; MANQUANTS : %s" % manquants) if manquants else ""))
    geoms["FR"] = [fr_par_dep[k] for k in DEPS if k in fr_par_dep]
    ad_pbf, ad_api = os.path.join(D, "ad", "andorra-latest.osm.pbf"), os.path.join(D, "ad", "api-9407.osm")
    mc_pbf, mc_api = os.path.join(D, "mc", "monaco-latest.osm.pbf"), os.path.join(D, "mc", "api-36990.osm")
    ad_src = premier(ad_pbf, os.path.join(D, "ad", "andorra-latest.osm"), ad_api)
    mc_src = premier(mc_pbf, os.path.join(D, "mc", "monaco-latest.osm"), mc_api)

    def es():
        out = []
        for code in ("34020000000", "34090000000", "34150000000", "34160000000"):
            out.extend(charge(os.path.join(D, "es", "es-%s.geojson" % code)))
        return out

    chargeurs = [
        ("CH", lambda: charge(os.path.join(D, "ch", "swissboundaries3d_2026-01_2056_5728.gpkg.zip"), "tlm_landesgebiet", "icc = 'CH'")),
        ("IT", lambda: charge(it_source, None, "COD_REG IN (1, 2, 7)")),
        ("ES", es),
        ("AD", lambda: charge(ad_src, "multipolygons", "osm_id = '9407'")),
        ("MC", lambda: charge_terre_osm(mc_src, 36990)),
    ]
    for iso, fn in chargeurs:
        t1 = time.time()
        try:
            geoms[iso] = fn()
        except Exception as exc:  # noqa: BLE001
            geoms[iso] = []
            print("   !!! %s : chargement impossible : %s" % (iso, c(exc, 240)))
        if iso == "IT":
            print("   Italie lue par %s en %.1f s" % (c(it_source, 170), time.time() - t1))
    print("   source Andorre : %s ; source Monaco : %s" % (os.path.basename(ad_src), os.path.basename(mc_src)))
    ordre = [iso for iso in ORDRE if geoms.get(iso)]
    if ordre != ORDRE:
        print("   !!! pays absents : %s ; la suite ne porte que sur %s" % ([i for i in ORDRE if i not in ordre], ordre))
    for iso in ordre:
        print("   %s : %d geometrie(s), %d sommets, %.3f km2" % (iso, len(geoms[iso]), sum(nb_sommets(g) for g in geoms[iso]), sum(ha(g) for g in geoms[iso]) / 100))
    print("   [chargement : %.1f s]" % (time.time() - t0))

    print()
    print("##### A bis. REPLI : memes relations lues dans la reponse de l'API OSM (relation/<id>/full)")
    for iso, api, fn in (("AD", ad_api, lambda: charge(ad_api, "multipolygons", "osm_id = '9407'")), ("MC", mc_api, lambda: charge_terre_osm(mc_api, 36990))):
        if not os.path.exists(api):
            print("   %s : fichier de l'API absent" % iso)
            continue
        try:
            autre = fn()
            ua = union(autre)
            msg = "   %s par l'API OSM (%d octets) : %d polygone(s), %d sommets, %.4f km2" % (iso, os.path.getsize(api), len(polygones(ua)), sum(nb_sommets(g) for g in autre), ha(ua) / 100)
            if geoms.get(iso) and os.path.abspath(api) != os.path.abspath(ad_src if iso == "AD" else mc_src):
                msg += " ; difference symetrique avec l'extrait Geofabrik : %.4f ha" % ha(ua.SymDifference(union(geoms[iso])))
            print(msg)
        except Exception as exc:  # noqa: BLE001
            print("   %s par l'API OSM : echec : %s" % (iso, c(exc, 240)))

    t0 = time.time()
    par_pays = {iso: union(geoms[iso]) for iso in ordre}
    tout = union([par_pays[iso] for iso in ordre])
    print("   [unions par pays et union generale : %.1f s]" % (time.time() - t0))

    print()
    print("##### B. TROUS FERMES DE L'UNION DE TOUS LES MASQUES")
    t0 = time.time()
    donnes, tous, orphelins = comble(par_pays, tout, ordre)
    recense("union (15 departements frontaliers, CH, IT, ES, AD, MC)", [s for s, _ in tous])
    for s, t in sorted(tous, key=lambda x: -x[0])[:18]:
        if s < 10:
            break
        print("     trou de %.1f ha vers (%.4f, %.4f)%s" % ((s,) + centre(t) + ("" if s >= SEUIL_HA else ", large de %.0f m" % largeur_max(t),)))
    print("   repartition des trous de moins de %d ha (au pays le moins prioritaire qui les touche) : %s ; orphelins : %d" % (
        SEUIL_HA, " | ".join("%s %d trous, %.1f ha" % (iso, len(donnes[iso]), sum(ha(t) for t in donnes[iso])) for iso in ordre), orphelins))
    print("   [recensement : %.1f s]" % (time.time() - t0))

    print()
    print("##### C. GRILLE Z12 : priorite, pixels coinces, comblement")
    try:
        t0 = time.time()
        gr = Grille(geoms)
        print("   canevas : tuiles x %d a %d, y %d a %d, soit %d x %d pixels" % (gr.tx0, gr.tx1, gr.ty0, gr.ty1, gr.w, gr.h))
        for iso in ordre:
            gagne, refuse = gr.revendique(geoms[iso], CODE[iso])
            print("   %s : %d pixels gagnes ; pixels deja pris par un pays prioritaire : %s" % (iso, gagne, refuse or "aucun"))
        print("   [rasterisation : %.1f s]" % (time.time() - t0))
        t0 = time.time()
        n, ex = gr.coinces()
        print("   pixels sans pays coinces entre deux pays, AVANT comblement : %d   [%.1f s]" % (n, time.time() - t0))
        print("     exemples : " + " ; ".join(ex))
        avant = gr.compte()
        t0 = time.time()
        gains = {}
        for iso in ordre:
            if donnes[iso]:
                gains[iso], _ = gr.revendique(donnes[iso], CODE[iso], un_par_un=False)
        print("   pixels gagnes par les trous combles : %s | total %d   [%.1f s]" % (gains, sum(gains.values()), time.time() - t0))
        n, ex = gr.coinces()
        print("   pixels sans pays coinces entre deux pays, APRES comblement : %d" % n)
        print("     exemples : " + " ; ".join(ex))
        apres = gr.compte()
        print("   pixels par pays avant comblement : %s" % avant)
        print("   pixels par pays apres comblement : %s" % apres)
        del gr
    except Exception:  # noqa: BLE001
        print("   !!! EXCEPTION dans la partie grille")
        print(c(traceback.format_exc(), 1500))

    print()
    print("##### D. ECARTS PAR PAIRE DE VOISINS (surfaces en EPSG:3035)")
    def fr(codes):
        return union([fr_par_dep[k] for k in codes if k in fr_par_dep])
    essais = [
        ("Italie ISTAT / France (74, 73, 05, 04, 06)", lambda: (par_pays.get("IT"), fr(["74", "73", "05", "04", "06"]))),
        ("Suisse / Italie ISTAT", lambda: (par_pays.get("CH"), par_pays.get("IT"))),
        ("Andorre / Espagne", lambda: (par_pays.get("AD"), par_pays.get("ES"))),
        ("Suisse / France (01, 39, 25, 90, 68, 74)", lambda: (par_pays.get("CH"), fr(["01", "39", "25", "90", "68", "74"]))),
        ("Espagne / France (64, 65, 31, 09, 66)", lambda: (par_pays.get("ES"), fr(["64", "65", "31", "09", "66"]))),
        ("Andorre / France (09, 66)", lambda: (par_pays.get("AD"), fr(["09", "66"]))),
        ("Monaco / France (06)", lambda: (par_pays.get("MC"), fr(["06"]))),
    ]
    for nom, f in essais:
        try:
            a, b = f()
            if a is None or b is None:
                continue
            paire(nom, a, b)
        except Exception:  # noqa: BLE001
            print("   !!! EXCEPTION pour la paire %s" % nom)
            print(c(traceback.format_exc(), 900))
    print()
    print("   [duree totale : %.0f s]" % (time.time() - t00))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
PY_FIN_SONDE
echo
echo "########## ANDORRE ET MONACO (memes controles que la sonde v1)"
python3 -I py/v1.py "$T/d" ANDORRE,MONACO 2>&1 | grep -v "memory leak" | cut -c1-720
echo "FIN v1 (code python : ${PIPESTATUS[0]})"
echo
echo "########## ECARTS, TROUS ET GRILLE"
python3 -I py/v3.py "$T/d" "$IT_SRC" 2>&1 | grep -v "memory leak" | cut -c1-720
echo "FIN v3 (code python : ${PIPESTATUS[0]})"

echo
echo "##### 9. LICENCE DE L'IGN ESPANA (PDF), nouvel essai"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq poppler-utils >/dev/null 2>&1
if essais 5 20 lic/ign.pdf "https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf"; then
  pdftotext -layout lic/ign.pdf lic/ign-brut.txt 2>&1 | head -2
  python3 -I - lic/ign-brut.txt <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
print("   PDF : %d page(s), %d caracteres de texte" % (s.count("\f") + (0 if s.endswith("\f") else 1), len(s)))
s = re.sub(r"-\n\s*", "", s)
s = re.sub(r"\s+", " ", s)
motif = re.compile(r"CC-BY|CC BY|Obra derivada|expresión general|libre y gratuito|a pie de mapa|Orden FOM|scne\.es", re.I)
vus = 0
for ph in re.split(r"(?<=[.;:])\s+(?=[A-ZÁÉÍÓÚ«“\"(])", s):
    ph = ph.strip()
    if motif.search(ph) and vus < 14:
        vus += 1
        print("   | " + (ph if len(ph) <= 560 else ph[:557] + "..."))
PY
else
  echo "   licence IGN : toujours inaccessible"
fi

echo
echo "##### 10. SURFACE OFFICIELLE DE LA CATALOGNE (Idescat, API « Municipis en xifres »)"
get lic/idescat.json "https://api.idescat.cat/emex/v1/dades.json?id=080193&lang=es"
python3 -I - lic/idescat.json <<'PY'
import json, sys
try:
    j = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as exc:
    print("   reponse non JSON : %s : %s" % (exc, open(sys.argv[1], errors="replace").read()[:200].replace("\n", " ")))
    sys.exit(0)
cols, trouves = [], []
def visite(x):
    if isinstance(x, dict):
        if "col" in x and isinstance(x["col"], list):
            for k in x["col"]:
                if isinstance(k, dict):
                    cols.append("%s=%s" % (k.get("scheme"), k.get("content")))
        if isinstance(x.get("c"), str) and "uperf" in x["c"] and "v" in x:
            trouves.append("id %s | %s | unidad %s | valores %s | actualizado %s" % (x.get("id"), x.get("c"), x.get("u"), x.get("v"), x.get("updated")))
        for v in x.values():
            visite(v)
    elif isinstance(x, list):
        for v in x:
            visite(v)
visite(j)
print("   colonnes : " + " ; ".join(cols)[:300])
for t in trouves[:6]:
    print("   indicateur : " + t[:300])
if not trouves:
    print("   aucun indicateur de superficie trouve ; cles de premier niveau : %s" % list(j)[:10])
PY
echo "FIN"
