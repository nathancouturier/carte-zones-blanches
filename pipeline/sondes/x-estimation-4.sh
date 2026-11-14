#!/usr/bin/env bash
# Estimation, sonde 4 : essai chronométré de gdal_viewshed (GDAL 3.13) sur une vraie tuile Copernicus GLO-30
# (N45 E006, Savoie), portées de 10 km puis 30 km ; ligne de commande et API Python ; calcul direct sur la grille
# EPSG:3857 du projet ; sensibilité à la hauteur d'antenne et à l'erreur de position.
set -u
. "$(dirname "$0")/_lib.sh"
cd "$T"

echo "##### 1. gdal_viewshed --long-usage"
gdal_viewshed --long-usage 2>&1 | cut -c1-230 | head -70

echo "##### 2. Tuile N45 E006 : téléchargement, statistiques, reprojections"
B=https://copernicus-dem-30m.s3.amazonaws.com; N=Copernicus_DSM_COG_10_N45_00_E006_00_DEM
t0=$(date +%s.%N); curl -sS -m 900 -A "$UA" -o dem.tif -w "  -> %{http_code} %{size_download}o en %{time_total}s\n" "$B/$N/$N.tif"
gdalinfo -stats dem.tif 2>&1 | grep -E "Size is|NoData|STATISTICS_(MINIMUM|MAXIMUM|MEAN|VALID_PERCENT)" | tr '\n' ' '; echo
chrono() { local a b; a=$(date +%s.%N); "$@"; b=$(date +%s.%N); python3 -c "print('   durée : %.1f s' % ($b - $a))"; }
chrono gdalwarp -q -overwrite -t_srs EPSG:32632 -tr 30 30 -r bilinear -dstnodata -32767 -co TILED=YES -co COMPRESS=DEFLATE -co PREDICTOR=3 dem.tif dem_utm.tif
gdalinfo dem_utm.tif | grep -E "^Size is|^Pixel Size|NoData" | tr '\n' ' '; echo "| $(stat -c %s dem_utm.tif) octets"
chrono gdalwarp -q -overwrite -t_srs EPSG:3857 -tr 38.21851414258813 38.21851414258813 -tap -r bilinear -dstnodata -32767 -co TILED=YES -co COMPRESS=DEFLATE -co PREDICTOR=3 dem.tif dem_3857.tif
gdalinfo dem_3857.tif | grep -E "^Size is|^Pixel Size|^Origin|NoData" | tr '\n' ' '; echo "| $(stat -c %s dem_3857.tif) octets"

echo "##### 3. Essais"
python3 - <<'PY'
import math, os, subprocess, time, statistics
import numpy as np
from osgeo import gdal, osr
gdal.UseExceptions()

def ct(epsg):
    a = osr.SpatialReference(); a.ImportFromEPSG(4326); a.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    b = osr.SpatialReference(); b.ImportFromEPSG(epsg); b.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return osr.CoordinateTransformation(a, b)
to_utm, to_merc = ct(32632), ct(3857)
OZ, TZ, CC = 30.0, 1.5, 0.75          # antenne 30 m, mobile 1,5 m, courbure avec réfraction radio (rayon terrestre 4/3)
SITES = [("A sommet (Mont Jovet présumé)", 6.6156, 45.4969), ("B vallée (Moûtiers présumé)", 6.5347, 45.4856), ("C station d'altitude (La Plagne présumée)", 6.6775, 45.5065)]

utm = gdal.Open("dem_utm.tif"); gtu = utm.GetGeoTransform(); W, H = utm.RasterXSize, utm.RasterYSize
t = time.perf_counter(); mem = gdal.GetDriverByName("MEM").CreateCopy("", utm); bu = mem.GetRasterBand(1); demu = bu.ReadAsArray()
print("   MNT UTM en mémoire : %d x %d px, chargé en %.1f s, %.0f Mo" % (W, H, time.perf_counter() - t, demu.nbytes / 1e6))
m3 = gdal.GetDriverByName("MEM").CreateCopy("", gdal.Open("dem_3857.tif")); b3 = m3.GetRasterBand(1); gt3 = m3.GetGeoTransform()

def alt(lon, lat):
    x, y, _ = to_utm.TransformPoint(lon, lat); return float(demu[int((gtu[3] - y) / 30), int((x - gtu[0]) / 30)])

def cli(x, y, md, mode="NORMAL", out="out.tif", oz=OZ):
    cmd = ["gdal_viewshed", "--quiet", "-ox", str(x), "-oy", str(y), "-oz", str(oz), "-tz", str(TZ), "-md", str(md), "-cc", str(CC),
           "-vv", "255", "-iv", "1", "-ov", "0", "-om", mode, "-of", "GTiff", "-co", "COMPRESS=DEFLATE", "dem_utm.tif", out]
    t = time.perf_counter(); r = subprocess.run(cmd, capture_output=True, text=True); dt = time.perf_counter() - t
    if r.returncode != 0: print("   ERREUR CLI :", (r.stderr or r.stdout)[:300]); return None
    ds = gdal.Open(out); a = ds.ReadAsArray()
    return dt, ds.RasterXSize, ds.RasterYSize, os.path.getsize(out), gdal.GetDataTypeName(ds.GetRasterBand(1).DataType), a, ds.GetGeoTransform(), ds.GetRasterBand(1).GetNoDataValue()

def api(band, x, y, md, cc=CC, oz=OZ, hm=gdal.GVOT_NORMAL):
    t = time.perf_counter()
    ds = gdal.ViewshedGenerate(band, "MEM", "", [], x, y, oz, TZ, 255, 1, 0, -1.0, cc, gdal.GVM_Edge, float(md), heightMode=hm)
    a = ds.ReadAsArray(); return time.perf_counter() - t, a, ds.GetGeoTransform(), ds

def share(a):
    v, i = int((a == 255).sum()), int((a == 1).sum()); return 100.0 * v / max(1, v + i), v, i

print("--- 3a. Ligne de commande, mode NORMAL (255 visible, 1 non visible, 0 hors portée), antenne %g m, mobile %g m, -cc %g" % (OZ, TZ, CC))
for name, lon, lat in SITES:
    x, y, _ = to_utm.TransformPoint(lon, lat)
    for md in (10000, 30000):
        r = cli(x, y, md)
        if r is None: continue
        dt, w, h, size, typ, a, gt, nd = r; p, v, i = share(a)
        print("   %-42s alt. MNT %4.0f m | portée %2d km : %.2f s | sortie %d x %d px %s, %d octets (%.0f ko), nodata %s | visible %.1f %% de la zone à portée (%.0f km2)" % (name, alt(lon, lat), md / 1000, dt, w, h, typ, size, size / 1e3, nd, p, v * 900 / 1e6))
print("--- 3b. Modes DEM et GROUND (hauteur minimale pour être vu), site A, 30 km")
name, lon, lat = SITES[0]; x, y, _ = to_utm.TransformPoint(lon, lat)
ref = cli(x, y, 30000)
for mode in ("GROUND", "DEM"):
    r = cli(x, y, 30000, mode, "out_%s.tif" % mode)
    if r is None: continue
    dt, w, h, size, typ, a, gt, nd = r
    yy, xx = np.mgrid[0:h, 0:w]; d = np.hypot(gt[0] + (xx + 0.5) * gt[1] - x, gt[3] + (yy + 0.5) * gt[5] - y); inr = d <= 30000
    line = "   mode %-6s : %.2f s | %d x %d px %s, %d octets, nodata %s | min %.1f max %.1f" % (mode, dt, w, h, typ, size, nd, float(a[inr].min()), float(a[inr].max()))
    if mode == "GROUND":
        q = [100.0 * float((a[inr] <= s).mean()) for s in (0, 1.5, 5, 10, 20, 50, 100)]
        line += " | part à portée avec hauteur requise <= 0 / 1,5 / 5 / 10 / 20 / 50 / 100 m : " + " / ".join("%.1f" % v for v in q) + " %"
        if ref is not None and ref[5].shape == a.shape:
            both = (ref[5] > 0) & inr
            line += " | accord avec NORMAL (hauteur <= 1,5 m contre visible) : %.2f %%" % (100.0 * float(((a <= TZ) == (ref[5] == 255))[both].mean()))
    print(line)

print("--- 3c. API Python gdal.ViewshedGenerate, MNT en mémoire, sortie MEM")
for name, lon, lat in SITES:
    x, y, _ = to_utm.TransformPoint(lon, lat)
    for md in (10000, 30000):
        dt, a, gt, ds = api(bu, x, y, md); p, v, i = share(a)
        print("   %-42s portée %2d km : %.3f s | %d x %d px | visible %.1f %%" % (name, md / 1000, dt, a.shape[1], a.shape[0], p))
rng = np.random.default_rng(20261114)
pts = [(float(rng.uniform(6.40, 6.62)), float(rng.uniform(45.30, 45.70))) for _ in range(30)]
for md in (10000, 30000):
    ts, ps = [], []
    for lon, lat in pts:
        x, y, _ = to_utm.TransformPoint(lon, lat); dt, a, gt, ds = api(bu, x, y, md); ts.append(dt); ps.append(share(a)[0])
    print("   30 points au hasard, portée %2d km : moyenne %.3f s, médiane %.3f s, min %.3f, max %.3f | part visible moyenne %.1f %%, médiane %.1f %%" % (md / 1000, statistics.mean(ts), statistics.median(ts), min(ts), max(ts), statistics.mean(ps), statistics.median(ps)))
    for n in (1000, 3000, 10000):
        print("      %5d sites : %.1f min sur 1 cœur, %.1f min sur 4 cœurs" % (n, n * statistics.mean(ts) / 60, n * statistics.mean(ts) / 240))

print("--- 3d. Calcul direct sur la grille du projet (EPSG:3857, z12) : portée x 1/cos(lat), courbure x cos2(lat)")
for name, lon, lat in SITES:
    k = 1.0 / math.cos(math.radians(lat)); xu, yu, _ = to_utm.TransformPoint(lon, lat); xm, ym, _ = to_merc.TransformPoint(lon, lat)
    for md in (10000, 30000):
        dtu, au, gu, dsu = api(bu, xu, yu, md)
        dtm, am, gm, dsm = api(b3, xm, ym, md * k, cc=CC / (k * k))
        hh, ww = am.shape
        wp = gdal.Warp("", dsu, format="MEM", dstSRS="EPSG:3857", outputBounds=(gm[0], gm[3] + hh * gm[5], gm[0] + ww * gm[1], gm[3]), width=ww, height=hh, resampleAlg="near")
        aw = wp.ReadAsArray(); both = (aw > 0) & (am > 0)
        agree = 100.0 * float(((aw == 255) == (am == 255))[both].mean())
        line = "   %-42s %2d km : 3857 %.3f s, %d x %d px, visible %.1f %% | UTM visible %.1f %% | accord pixel à pixel %.2f %%" % (name, md / 1000, dtm, ww, hh, share(am)[0], share(au)[0], agree)
        if md == 30000:
            dtx, ax, gx, dsx = api(b3, xm, ym, md * k, cc=CC)
            line += " | sans corriger la courbure : visible %.1f %%" % share(ax)[0]
        print(line)

print("--- 3e. Sensibilité : courbure, hauteur d'antenne (site, 30 km, UTM)")
for name, lon, lat in SITES:
    x, y, _ = to_utm.TransformPoint(lon, lat)
    out = ["cc 0 : %.1f %%" % share(api(bu, x, y, 30000, cc=0.0)[1])[0], "cc 0,75 : %.1f %%" % share(api(bu, x, y, 30000)[1])[0], "cc 0,85714 : %.1f %%" % share(api(bu, x, y, 30000, cc=0.85714)[1])[0]]
    out += ["antenne %d m : %.1f %%" % (oz, share(api(bu, x, y, 30000, oz=float(oz))[1])[0]) for oz in (10, 20, 30, 40, 60)]
    print("   %-42s %s" % (name, " | ".join(out)))

print("--- 3f. Sensibilité à l'erreur de position (10 km) : indice de Jaccard entre la zone visible du point vrai et celle du point déplacé")
def full(a, gt):
    f = np.zeros((H, W), dtype=bool); c0 = int(round((gt[0] - gtu[0]) / 30)); r0 = int(round((gtu[3] - gt[3]) / 30))
    f[r0:r0 + a.shape[0], c0:c0 + a.shape[1]] = (a == 255); return f
allpts = [(n, lo, la) for n, lo, la in SITES] + [("hasard %d" % i, lo, la) for i, (lo, la) in enumerate(pts[:12])]
for err in (100, 300, 1000, 2000):
    js, ratios = [], []
    for name, lon, lat in allpts:
        x, y, _ = to_utm.TransformPoint(lon, lat); dt, a, gt, ds = api(bu, x, y, 10000); f0 = full(a, gt)
        for ang in (0, 90, 180, 270):
            dx, dy = err * math.sin(math.radians(ang)), err * math.cos(math.radians(ang))
            dt, a1, gt1, ds1 = api(bu, x + dx, y + dy, 10000); f1 = full(a1, gt1)
            u = int((f0 | f1).sum()); js.append(float((f0 & f1).sum()) / u if u else 1.0); ratios.append(float(f1.sum()) / max(1, int(f0.sum())))
    print("   erreur %4d m : Jaccard moyen %.2f, médian %.2f, 1er décile %.2f | rapport des surfaces visibles : médian %.2f, de %.2f à %.2f (15 points x 4 directions)" % (err, statistics.mean(js), statistics.median(js), sorted(js)[len(js) // 10], statistics.median(ratios), min(ratios), max(ratios)))
print("--- 3g. Parade testée : réunion des zones visibles depuis le point annoncé et 4 points à 300 m (comparée à un point vrai situé à 300 m)")
js1, js5, cov1, cov5 = [], [], [], []
for name, lon, lat in allpts:
    x, y, _ = to_utm.TransformPoint(lon, lat)
    fs = [full(*api(bu, x + dx, y + dy, 10000)[1:3]) for dx, dy in ((0, 0), (300, 0), (-300, 0), (0, 300), (0, -300))]
    union = fs[0] | fs[1] | fs[2] | fs[3] | fs[4]
    for ang in (45, 135, 225, 315):
        tx, ty = x + 300 * math.sin(math.radians(ang)), y + 300 * math.cos(math.radians(ang)); ft = full(*api(bu, tx, ty, 10000)[1:3])
        js1.append(float((fs[0] & ft).sum()) / max(1, int((fs[0] | ft).sum()))); js5.append(float((union & ft).sum()) / max(1, int((union | ft).sum())))
        cov1.append(float((fs[0] & ft).sum()) / max(1, int(ft.sum()))); cov5.append(float((union & ft).sum()) / max(1, int(ft.sum())))
print("   un seul calcul : Jaccard médian %.2f, part de la vraie zone visible retrouvée %.2f | réunion de 5 calculs : Jaccard médian %.2f, part retrouvée %.2f" % (statistics.median(js1), statistics.median(cov1), statistics.median(js5), statistics.median(cov5)))
PY
echo "FIN"
