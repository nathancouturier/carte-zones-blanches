#!/usr/bin/env bash
# Estimation, sonde 6 : calage de la méthode « visibilité + distance » sur la France, où la vérité officielle existe.
# Sites 4G officiels (Arcep, fichier « sites »), MNT Copernicus GLO-30, couverture théorique 4G de l'Arcep.
# Deux départements de montagne (Hautes-Alpes, Ariège), deux opérateurs. Aucune donnée OpenCelliD.
# Le programme Python est aussi dans le dossier de travail de l'agent : agents/estimation/calage.py.
set -u
. "$(dirname "$0")/_lib.sh"
cd "$T"
apt-get install -y -qq p7zip-full >/dev/null 2>&1

echo "##### 1. Données"
get "$T/departements.geojson.gz" "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/departements-5m.geojson.gz"
gunzip -f "$T/departements.geojson.gz"
get "$T/sites.html" "https://data.arcep.fr/mobile/sites/last/"
f=$(grep -o -E "[0-9]{4}_T[1-4]_sites_Metropole\.csv" "$T/sites.html" | head -1); echo "   fichier des sites : $f"
get "$T/sites.csv" "https://data.arcep.fr/mobile/sites/last/$f"
LIST=https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/00_Metropole/
get "$T/listing.html" "$LIST"
for op in OF SFR0; do
  f=$(grep -o -E "[0-9]{4}_T[1-4]_couv_Metropole_${op}_4G_data\.gpkg\.7z" "$T/listing.html" | head -1)
  curl -sS -L -m 1500 -A "$UA" -o "$T/a.7z" -w "   $f -> %{http_code} %{size_download}o en %{time_total}s\n" "$LIST$f"
  7z x -y -o"$T/x_$op" "$T/a.7z" >/dev/null && mv "$T/x_$op"/*.gpkg "$T/arcep_$op.gpkg"; rm -f "$T/a.7z"
  ls -l "$T/arcep_$op.gpkg" | awk '{print "   extrait :", $5, "octets", $9}'
done

echo "##### 2. Calage"
python3 - <<'CALAGE_PY' 2>&1 | grep -v "swig/python detected" | cut -c1-330
"""Calage de la méthode d'estimation sur la France, où la vérité officielle existe.

Pour un département de montagne et un opérateur : positions officielles des sites 4G (Arcep, fichier « sites »),
visibilité calculée avec gdal.ViewshedGenerate sur Copernicus GLO-30 ramené sur la grille du projet (EPSG:3857, z12),
puis comparaison pixel à pixel avec la couverture théorique 4G de l'Arcep (niveaux 0 à 3).
Ce script ne lit aucune donnée OpenCelliD : il mesure ce que vaut le modèle « visibilité + distance » quand les
positions sont exactes, puis quand on les déplace au hasard (simulation d'une erreur de position).
"""
import csv, math, os, subprocess, sys, time
import numpy as np
from osgeo import gdal, ogr, osr

gdal.UseExceptions(); ogr.UseExceptions(); osr.UseExceptions()
T = os.environ.get("CZB_T", "/tmp/sonde"); SYNTH = os.environ.get("CZB_SYNTH") == "1"
UA = "carte-zones-blanches-sonde/1.0 (+https://github.com/nathancouturier/carte-zones-blanches)"
RES = 2 * math.pi * 6378137.0 / (4096 * 256)        # pixel de la grille z12 : 38,2185 m Mercator
OZ, TZ, CC, MD, HQ = 30.0, 1.5, 0.75, 30000.0, 30.0  # antenne, mobile, courbure radio, portée max, seuil « presque visible »
UB = np.array([0.5, 1, 2, 3, 5, 7.5, 10, 15, 20, 30], dtype=np.float32)   # bornes hautes des classes de distance (km)
NB = len(UB) + 1
LABELS = ["<=0,5", "0,5-1", "1-2", "2-3", "3-5", "5-7,5", "7,5-10", "10-15", "15-20", "20-30", "aucun"]
T0 = time.time()
COMBOS = [tuple(c.split(":")) for c in os.environ.get("CZB_COMBOS", "05:20801:OF,09:20801:OF,05:20810:SFR0").split(",")]


def srs(epsg):
    s = osr.SpatialReference(); s.ImportFromEPSG(epsg); s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER); return s


def tr(a, b):
    return osr.CoordinateTransformation(srs(a), srs(b))


def mem_vector():
    for name in ("MEM", "Memory"):
        drv = ogr.GetDriverByName(name)
        if drv is None: continue
        try:
            ds = drv.CreateDataSource("")
        except RuntimeError:
            continue
        if ds is not None: return ds
    raise RuntimeError("pas de pilote vecteur en mémoire")


def burn(target, geoms, value):
    vec = mem_vector(); lyr = vec.CreateLayer("g", srs(3857), ogr.wkbUnknown)
    for g in geoms:
        f = ogr.Feature(lyr.GetLayerDefn()); f.SetGeometry(g); lyr.CreateFeature(f)
    gdal.RasterizeLayer(target, [1], lyr, burn_values=[value])


def dept_geometry(code):
    ds = ogr.Open(os.path.join(T, "departements.geojson")); lyr = ds.GetLayer(0)
    for f in lyr:
        if f.GetField("code") == code:
            return f.GetGeometryRef().Clone(), f.GetField("nom")
    raise RuntimeError("département introuvable : " + code)


def window_for(geom4326):
    g = geom4326.Clone(); g.Transform(tr(4326, 3857)); minx, maxx, miny, maxy = g.GetEnvelope()
    _, _, south, north = geom4326.GetEnvelope()
    m = MD / math.cos(math.radians(north)) + 20 * RES
    x0 = math.floor((minx - m) / RES) * RES; x1 = math.ceil((maxx + m) / RES) * RES
    y0 = math.floor((miny - m) / RES) * RES; y1 = math.ceil((maxy + m) / RES) * RES
    return g, (x0, y0, x1, y1), int(round((x1 - x0) / RES)), int(round((y1 - y0) / RES))


def load_dem(bounds, W, H):
    x0, y0, x1, y1 = bounds; back = tr(3857, 4326)
    west, south, _ = back.TransformPoint(x0, y0); east, north, _ = back.TransformPoint(x1, y1)
    files = []
    if SYNTH:
        files = [os.path.join(T, "dem.tif")]
    else:
        os.makedirs(os.path.join(T, "dem"), exist_ok=True)
        for lat in range(math.floor(south), math.floor(north) + 1):
            for lon in range(math.floor(west), math.floor(east) + 1):
                name = "Copernicus_DSM_COG_10_%s%02d_00_%s%03d_00_DEM" % ("N" if lat >= 0 else "S", abs(lat), "E" if lon >= 0 else "W", abs(lon))
                dst = os.path.join(T, "dem", name + ".tif")
                if not os.path.exists(dst):
                    r = subprocess.run(["curl", "-sS", "-f", "-m", "600", "-A", UA, "-o", dst, "https://copernicus-dem-30m.s3.amazonaws.com/%s/%s.tif" % (name, name)], capture_output=True, text=True)
                    if r.returncode != 0:
                        print("      tuile absente (mer ou hors jeu public) :", name, (r.stderr or "").strip()[:80]); continue
                files.append(dst)
    vrt = gdal.BuildVRT(os.path.join(T, "dem.vrt"), files)
    ds = gdal.Warp("", vrt, format="MEM", dstSRS="EPSG:3857", outputBounds=bounds, xRes=RES, yRes=RES, resampleAlg="bilinear",
                   outputType=gdal.GDT_Float32, warpOptions=["INIT_DEST=0"], multithread=True)
    assert ds.RasterXSize == W and ds.RasterYSize == H, (ds.RasterXSize, ds.RasterYSize, W, H)
    return ds, len(files)


def load_sites(code_op, geom4326):
    """Sites 4G de l'opérateur situés à moins de 30 km du département : liste (x Mercator, y Mercator, latitude)."""
    g = geom4326.Clone(); g.Transform(tr(4326, 2154)); buf = g.Buffer(MD); minx, maxx, miny, maxy = buf.GetEnvelope()
    to_m, to_ll = tr(2154, 3857), tr(2154, 4326); out, seen, total = [], set(), 0
    with open(os.path.join(T, "sites.csv"), newline="", encoding="utf-8", errors="replace") as fh:
        for row in csv.DictReader(fh, delimiter=";"):
            if row["code_op"] != code_op or row["site_4g"] != "1": continue
            total += 1
            try:
                x, y = float(row["x"].replace(",", ".")), float(row["y"].replace(",", "."))
            except ValueError:
                continue
            if not (minx <= x <= maxx and miny <= y <= maxy) or (round(x), round(y)) in seen: continue
            p = ogr.Geometry(ogr.wkbPoint); p.AddPoint_2D(x, y)
            if not buf.Contains(p): continue
            seen.add((round(x), round(y)))
            xm, ym, _ = to_m.TransformPoint(x, y); lon, lat, _ = to_ll.TransformPoint(x, y)
            out.append((xm, ym, lat, x, y))
    return out, total


def arcep_raster(gpkg, dept, bounds, W, H):
    """Niveaux Arcep (0 à 3) sur la grille : CL = 1, BC = 2, TBC = 3, le plus élevé gagne."""
    x0, y0, x1, y1 = bounds
    out = gdal.GetDriverByName("MEM").Create("", W, H, 1, gdal.GDT_Byte); out.SetGeoTransform((x0, RES, 0, y1, 0, -RES)); out.SetProjection(srs(3857).ExportToWkt())
    ds = ogr.Open(gpkg); lyr = ds.GetLayer(0); defn = lyr.GetLayerDefn()
    fields = [defn.GetFieldDefn(i).GetName() for i in range(defn.GetFieldCount())]
    epsg = lyr.GetSpatialRef().GetAuthorityCode(None)
    vals, want = [], []
    if "dept" in fields:
        res = ds.ExecuteSQL('SELECT DISTINCT dept FROM "%s"' % lyr.GetName()); vals = sorted({str(f.GetField(0)) for f in res}); ds.ReleaseResultSet(res)
        want = [v for v in vals if v.lstrip("0") == dept.lstrip("0")]
    to_m = osr.CoordinateTransformation(lyr.GetSpatialRef(), srs(3857)) if epsg != "2154" else tr(2154, 3857)
    if not want:                                        # pas de champ dept exploitable : filtre spatial sur la fenêtre
        back = osr.CoordinateTransformation(srs(3857), lyr.GetSpatialRef())
        pts = [back.TransformPoint(x, y)[:2] for x in (x0, x1) for y in (y0, y1)]
        lyr.SetSpatialFilterRect(min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts))
    counts = {}
    for name, value in (("CL", 1), ("BC", 2), ("TBC", 3)):
        lyr.SetAttributeFilter("niveau = '%s'" % name + (" AND dept IN (%s)" % ",".join("'%s'" % v for v in want) if want else ""))
        geoms = []
        for f in lyr:
            g = f.GetGeometryRef()
            if g is None or g.IsEmpty(): continue
            g = g.Clone(); g.Transform(to_m); geoms.append(g)
        counts[name] = len(geoms)
        if geoms: burn(out, geoms, value)
    return out.GetRasterBand(1).ReadAsArray(), fields, epsg, vals[:6], want, counts


def accumulate(band, gt, shape, sites, shift=None, rng=None):
    """Distance (km) au site le plus proche : visible (dlos), presque visible (dq), quelconque (dany)."""
    H, W = shape
    dlos = np.full(shape, np.inf, np.float32); dq = np.full(shape, np.inf, np.float32); dany = np.full(shape, np.inf, np.float32)
    for xm, ym, lat, _, _ in sites:
        k = 1.0 / math.cos(math.radians(lat))
        if shift is not None:
            r = float(rng.rayleigh(shift[1])) if shift[0] == "rayleigh" else shift[1]; a = float(rng.uniform(0, 2 * math.pi))
            xm, ym = xm + r * k * math.cos(a), ym + r * k * math.sin(a)
        ds = gdal.ViewshedGenerate(band, "MEM", "", [], xm, ym, OZ, TZ, 255, 1, 0, -1.0, CC / (k * k), gdal.GVM_Edge, MD * k,
                                   heightMode=gdal.GVOT_MIN_TARGET_HEIGHT_FROM_GROUND)
        h = ds.ReadAsArray(); g = ds.GetGeoTransform(); hh, ww = h.shape
        c0 = int(round((g[0] - gt[0]) / RES)); r0 = int(round((gt[3] - g[3]) / RES))
        xs = ((g[0] + (np.arange(ww) + 0.5) * RES - xm) / k / 1000.0).astype(np.float32)
        ys = ((g[3] - (np.arange(hh) + 0.5) * RES - ym) / k / 1000.0).astype(np.float32)
        d = np.sqrt(xs[None, :] ** 2 + ys[:, None] ** 2)
        d[d > MD / 1000.0] = np.inf
        sl = (slice(r0, r0 + hh), slice(c0, c0 + ww))
        np.minimum(dany[sl], d, out=dany[sl])
        np.minimum(dq[sl], np.where(h <= HQ, d, np.inf), out=dq[sl])
        np.minimum(dlos[sl], np.where(h <= TZ, d, np.inf), out=dlos[sl])
    return dlos, dq, dany


def joint_hist(dlos, dq, dany, level, mask):
    b = [np.digitize(a[mask], UB, right=True) for a in (dlos, dq, dany)]
    idx = np.ravel_multi_index((b[0], b[1], b[2], level[mask].astype(np.int64)), (NB, NB, NB, 4))
    return np.bincount(idx, minlength=NB * NB * NB * 4).reshape(NB, NB, NB, 4).astype(np.float64)


UBX = np.append(UB, np.inf)


def covered(dl, dqq, dn):
    return (UBX[:, None, None] <= dl) | (UBX[None, :, None] <= dqq) | (UBX[None, None, :] <= dn)


def scores(J, cov):
    c = J[cov].sum(axis=0); n = J[~cov].sum(axis=0)        # par niveau Arcep : prédits couverts, prédits blancs
    tn, fn, fp, tp = n[0], n[1:].sum(), c[0], c[1:].sum(); tot = tn + fn + fp + tp
    rw = tn / max(1.0, tn + fp); rc = tp / max(1.0, tp + fn)
    return {"exact": (tn + tp) / tot, "equil": (rw + rc) / 2, "rappel_blanc": rw, "precision_blanc": tn / max(1.0, tn + fn),
            "rappel_couvert": rc, "precision_couvert": tp / max(1.0, tp + fp), "part_predite_blanche": (tn + fn) / tot}


def fmt(s):
    return "exact %.1f %% | équilibré %.1f %% | zones blanches : rappel %.1f %%, précision %.1f %% | couvert : rappel %.1f %%, précision %.1f %% | part prédite blanche %.1f %%" % (
        100 * s["exact"], 100 * s["equil"], 100 * s["rappel_blanc"], 100 * s["precision_blanc"], 100 * s["rappel_couvert"], 100 * s["precision_couvert"], 100 * s["part_predite_blanche"])


CAND = [0, 0.5, 1, 2, 3, 5, 7.5, 10, 15, 20, 30]


def search(J, crit="equil", ok=lambda s: True):
    best = None
    for dl in CAND:
        for dqq in CAND:
            for dn in CAND[:8]:
                s = scores(J, covered(dl, dqq, dn))
                if not ok(s): continue
                if best is None or s[crit] > best[0][crit]: best = (s, (dl, dqq, dn))
    return best


def table(J, title):
    print("   " + title)
    print("      colonnes : distance au site (km) ; A = site visible le plus proche ; B = sans vue directe, site presque visible (obstacle <= 30 m) le plus proche ; C = ni l'un ni l'autre, site le plus proche")
    print("      dans chaque colonne : part des pixels, % couverts selon l'Arcep, % niveau >= 2, % niveau 3")
    tot = J.sum()
    los = J.sum(axis=(1, 2)); quasi = J[NB - 1].sum(axis=1); none = J[NB - 1, NB - 1]
    for i in range(NB):
        cells = []
        for a in (los, quasi, none):
            n = a[i].sum()
            cells.append("%5.1f %% %5.1f %5.1f %5.1f" % (100 * n / tot, 100 * a[i][1:].sum() / max(1.0, n), 100 * a[i][2:].sum() / max(1.0, n), 100 * a[i][3] / max(1.0, n)) if n else "    -")
        if i == NB - 1: cells[0] = "(voir colonnes suivantes)"; cells[1] = "(voir colonne suivante)"
        print("      %-8s %-26s | %-26s | %-26s" % (LABELS[i], cells[0], cells[1], cells[2]))


def levels_eval(J, rule, d3, d2, basis):
    """Matrice 4 x 4 (niveau prédit, niveau Arcep). basis = "vue" : distance au site visible ; "distance" : au site le plus proche."""
    cov = covered(*rule); P = np.where(cov, 1, 0)
    key = UBX[:, None, None] if basis == "vue" else UBX[None, None, :]
    P = np.where(cov & (key <= d2), 2, P); P = np.where(cov & (key <= d3), 3, P)
    M = np.zeros((4, 4))
    for p in range(4): M[p] = J[P == p].sum(axis=0)
    return M


def main():
    rng = np.random.default_rng(20261114); pooled = {}; per = []
    for dept, code_op, arcep_op in COMBOS:
        t = time.time(); geom, nom = dept_geometry(dept); gm, bounds, W, H = window_for(geom)
        gt = (bounds[0], RES, 0, bounds[3], 0, -RES)
        dem, ntiles = load_dem(bounds, W, H); band = dem.GetRasterBand(1); z = band.ReadAsArray()
        sites, total = load_sites(code_op, geom)
        mask_ds = gdal.GetDriverByName("MEM").Create("", W, H, 1, gdal.GDT_Byte); mask_ds.SetGeoTransform(gt); mask_ds.SetProjection(srs(3857).ExportToWkt()); burn(mask_ds, [gm], 1)
        mask = mask_ds.GetRasterBand(1).ReadAsArray() == 1
        level, fields, epsg, vals, want, counts = arcep_raster(os.path.join(T, "arcep_%s.gpkg" % arcep_op), dept, bounds, W, H)
        share = [100.0 * float((level[mask] == i).mean()) for i in range(4)]
        print("== %s (%s), opérateur %s : grille %d x %d px, %d tuiles MNT, %d sites 4G à moins de 30 km (%d en France), %.1f M pixels dans le département, préparation %.0f s" % (nom, dept, arcep_op, W, H, ntiles, len(sites), total, mask.sum() / 1e6, time.time() - t))
        print("   Arcep : champs %s, EPSG:%s, valeurs de dept %s..., retenues %s, entités %s | niveaux 0/1/2/3 : %.1f / %.1f / %.1f / %.1f %%" % (fields, epsg, vals, want, counts, *share))
        # altitude des sites réels par rapport au relief voisin (rayon 300 m)
        ranks, gaps = [], []
        for xm, ym, lat, _, _ in sites:
            c = int((xm - gt[0]) / RES); r = int((gt[3] - ym) / RES); n = max(1, int(round(300 / (RES * math.cos(math.radians(lat))))))
            w = z[max(0, r - n): r + n + 1, max(0, c - n): c + n + 1]
            ranks.append(float((w < z[r, c]).mean())); gaps.append(float(w.max() - z[r, c]))
        print("   sites réels : rang d'altitude médian dans un rayon de 300 m = %.2f (1 = point le plus haut) ; %.0f %% des sites dans le quart le plus haut ; écart médian au point le plus haut = %.0f m" % (float(np.median(ranks)), 100 * float((np.array(ranks) >= 0.75).mean()), float(np.median(gaps))))
        xy = np.array([(s[3], s[4]) for s in sites]); dd = np.sqrt(((xy[:, None, :] - xy[None, :, :]) ** 2).sum(axis=2)); np.fill_diagonal(dd, np.inf); nn = dd.min(axis=1)
        print("   distance au site voisin du même opérateur : 5e centile %.0f m, 1er quartile %.0f m, médiane %.0f m" % (float(np.percentile(nn, 5)), float(np.percentile(nn, 25)), float(np.median(nn))))
        for label, shift in (("positions exactes", None), ("erreur de position aléatoire, 500 m typique", ("rayleigh", 500.0)), ("erreur de position de 1500 m", ("fixe", 1500.0))):
            if time.time() - T0 > 45 * 60 and shift is not None:
                print("   (%s : sauté, budget de temps dépassé)" % label); continue
            t = time.time(); dlos, dq, dany = accumulate(band, gt, (H, W), sites, shift, rng)
            J = joint_hist(dlos, dq, dany, level, mask); pooled[label] = pooled.get(label, 0) + J; per.append((nom, arcep_op, label, J))
            print("   %s : %d visibilités en %.1f s (%.3f s par site)" % (label, len(sites), time.time() - t, (time.time() - t) / max(1, len(sites))))
        del dem, z, level, mask
    print("== Résultats, tous cas réunis")
    J0 = pooled["positions exactes"]; tot = J0.sum(); lev = J0.sum(axis=(0, 1, 2))
    print("   pixels : %.1f M | Arcep niveaux 0/1/2/3 : %s %%" % (tot / 1e6, " / ".join("%.1f" % (100 * v / tot) for v in lev)))
    table(J0, "Positions exactes. Par classe de distance : part des pixels, puis % couverts selon l'Arcep (niveau >= 1), % niveau >= 2, % niveau 3")
    rules = {"tout couvert (aucun modèle)": (0, 0, 30), "vue directe seule, 30 km": (30, 0, 0), "vue directe seule, 10 km": (10, 0, 0)}
    bd = max(((scores(J0, covered(0, 0, x))["equil"], x) for x in CAND), key=lambda v: v[0])
    rules["distance seule, meilleur seuil %s km" % bd[1]] = (0, 0, bd[1])
    b1 = search(J0, "equil"); rules["meilleure règle (score équilibré) : vue <= %s km, presque vue <= %s km, sinon distance <= %s km" % b1[1]] = b1[1]
    b2 = search(J0, "exact"); rules["meilleure règle (taux exact) : vue <= %s, presque vue <= %s, distance <= %s km" % b2[1]] = b2[1]
    for target in (0.7, 0.8, 0.9):
        b3 = search(J0, "rappel_couvert", lambda s, t=target: s["rappel_blanc"] >= t)
        if b3: rules["au moins %d %%%% des zones blanches retrouvées : vue <= %%s, presque vue <= %%s, distance <= %%s km" % round(100 * target) % b3[1]] = b3[1]
    for label, J in pooled.items():
        if label != "positions exactes": table(J, "Même tableau, " + label)
    for label, J in pooled.items():
        print("   -- %s" % label)
        for name, r in rules.items():
            print("      %-95s %s" % (name[:95], fmt(scores(J, covered(*r)))))
        bj = search(J, "equil"); print("      %-95s %s" % (("meilleure règle recalculée pour ce cas : %s" % (bj[1],))[:95], fmt(bj[0])))
    print("   -- par cas, règle au score équilibré %s" % (b1[1],))
    for nom, op, label, J in per:
        print("      %-18s %-5s %-45s %s" % (nom, op, label, fmt(scores(J, covered(*b1[1])))))
    print("   -- niveaux (positions exactes, règle %s) : niveau 3 jusqu'à D3, niveau 2 jusqu'à D2, sinon 1 ; distance comptée au site visible ou au site le plus proche" % (b1[1],))
    best = None
    for basis in ("vue", "distance"):
        for d3, d2 in ((1, 3), (2, 5), (3, 7.5), (5, 10), (2, 10), (3, 15), (5, 20), (0.5, 2), (1, 5)):
            M = levels_eval(J0, b1[1], d3, d2, basis); acc = np.trace(M) / M.sum()
            print("      %-8s D3 = %-3s km, D2 = %-3s km : accord exact sur 4 niveaux %.1f %%" % (basis, d3, d2, 100 * acc))
            if best is None or acc > best[0]: best = (acc, d3, d2, M, basis)
    print("      matrice (lignes = niveau prédit 0 à 3, colonnes = niveau Arcep 0 à 3, en %% du total) pour %s, D3 = %s, D2 = %s :" % (best[4], best[1], best[2]))
    for p in range(4): print("        prédit %d : %s" % (p, "  ".join("%5.1f" % (100 * v / best[3].sum()) for v in best[3][p])))
    print("   durée totale : %.0f s" % (time.time() - T0))


main()
CALAGE_PY
echo "FIN"
