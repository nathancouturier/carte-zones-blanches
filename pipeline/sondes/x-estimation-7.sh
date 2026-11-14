#!/usr/bin/env bash
# Estimation, sonde 7 : (1) forme des liens de téléchargement OpenCelliD d'après le site officiel, antennes de Ligurie,
# nouveaux essais Monaco et Piémont ; (2) calage, deuxième passe : règle à trois niveaux, sites manquants, erreur de
# position, hauteur d'antenne. Le programme Python est aussi dans agents/estimation/calage2.py.
set -u
. "$(dirname "$0")/_lib.sh"
cd "$T"
apt-get install -y -qq p7zip-full >/dev/null 2>&1

contenu() {
  python3 - "$1" "${2:-3000}" <<'PY'
import re, sys, html
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"<article\b.*?</article>", s, flags=re.S | re.I) or re.search(r"<main\b.*?</main>", s, flags=re.S | re.I)
if m: s = m.group(0)
s = re.sub(r"<(script|style|svg|noscript|nav|button)\b.*?</\1>", " ", s, flags=re.S | re.I)
s = re.sub(r"</(td|th)>", " | ", s, flags=re.I)
s = re.sub(r"<br\s*/?>|</(p|div|li|tr|h[1-6]|pre|summary|details)>", "\n", s, flags=re.I)
s = html.unescape(re.sub(r"<[^>]+>", " ", s))
s = re.sub(r"[ \t\r\f\v]+", " ", s)
lines = [l.strip() for l in s.split("\n") if l.strip()]
out = "\n".join(lines)[: int(sys.argv[2])]
for l in out.split("\n"): print("   |", l[:800])
PY
}

echo "##### A. OpenCelliD : page des téléchargements (formulaire, scripts) et page sur les exports"
get "$T/dl.html" "https://opencellid.org/downloads.php"
python3 - <<'PY'
import re
s = open("/tmp/sonde/dl.html", encoding="utf-8", errors="replace").read()
for m in re.findall(r"<form\b[^>]*>", s, flags=re.I)[:4]: print("   formulaire :", m[:300])
for m in re.findall(r"<input\b[^>]*>", s, flags=re.I)[:8]: print("   champ :", m[:240])
print("   scripts externes :", re.findall(r'<script\b[^>]*src="([^"]+)"', s, flags=re.I)[:10])
for b in re.findall(r"<script\b[^>]*>(.*?)</script>", s, flags=re.S | re.I):
    b = re.sub(r"\s+", " ", b).strip()
    if re.search(r"download|token|csv", b, re.I): print("   script en ligne :", b[:1500])
for m in sorted(set(re.findall(r"[\w./?=&;-]*(?:downloads?\?|csv\.gz|type=)[\w./?=&;%{}$+' \"-]{0,120}", s)))[:12]: print("   motif :", m[:260])
PY
for js in $(python3 -c "
import re
s = open('/tmp/sonde/dl.html', encoding='utf-8', errors='replace').read()
for u in re.findall(r'<script\b[^>]*src=\"([^\"]+)\"', s, flags=re.I):
    if u.startswith('/'): u = 'https://opencellid.org' + u
    if 'opencellid.org' in u: print(u)" | head -4); do
  get "$T/x.js" "$js"
  python3 - <<'PY'
import re
s = open("/tmp/sonde/x.js", encoding="utf-8", errors="replace").read()
hits = sorted(set(re.findall(r".{0,160}(?:ocid/downloads|downloads\?|csv\.gz|type=mcc|type=full|type=diff).{0,220}", s)))
for h in hits[:8]: print("   js :", re.sub(r"\s+", " ", h)[:420])
if not hits: print("   (aucun motif de téléchargement dans ce script)")
PY
done
get "$T/ov.html" "https://docs.opencellid.org/docs/downloads/overview"
for u in $(python3 -c "
import re, html
s = open('/tmp/sonde/ov.html', encoding='utf-8', errors='replace').read(); seen = []
for h in re.findall(r'href=\"(/docs/downloads/[^\"#?]*)', s):
    if h not in seen and not h.endswith(('overview', 'database-format')): seen.append(h)
print(' '.join(seen[:3]))"); do
  echo "--- $u"; get "$T/p.html" "https://docs.opencellid.org$u"; contenu "$T/p.html" 5000
done

echo "##### B. Ligurie : services du géoportail régional pour les installations de télécommunication"
get "$T/pk.json" "https://www.dati.gov.it/opendata/api/3/action/package_show?id=impianti-di-telecomunicazione"
python3 - <<'PY'
import json
try:
    p = json.load(open("/tmp/sonde/pk.json"))["result"]
    print("   url :", p.get("url"), "| identifiant :", p.get("identifier"), "| thèmes :", str(p.get("theme"))[:120], "| publié :", p.get("issued"), "| modifié :", p.get("modified"))
    for e in p.get("extras", []):
        if e.get("key") in ("identifier", "source", "landing_page", "uri", "harvest_source_title", "guid", "alternate_identifier"): print("   extra", e.get("key"), ":", str(e.get("value"))[:300])
    for r in p.get("resources", [])[:6]: print("   ressource :", json.dumps({k: r.get(k) for k in ("name", "format", "url", "access_url", "download_url", "distribution_format", "license", "rights")}, ensure_ascii=False)[:500])
except Exception as e: print("   ERREUR", e, open("/tmp/sonde/pk.json", errors="replace").read()[:200])
PY
for id in "r_liguri:D.2196" "r_liguri:D.1235.VS"; do
  get "$T/rndt.xml" "https://geodati.gov.it/RNDT/csw?service=CSW&version=2.0.2&request=GetRecordById&id=$id&elementSetName=full&outputSchema=http://www.isotc211.org/2005/gmd"
  python3 - <<'PY'
import re, html
s = open("/tmp/sonde/rndt.xml", encoding="utf-8", errors="replace").read()
def texts(tag, n=3):
    return [re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", x))).strip() for x in re.findall(r"<(?:\w+:)?%s\b.*?</(?:\w+:)?%s>" % (tag, tag), s, flags=re.S)][:n]
print("    titre :", [t[:160] for t in texts("title", 1)], "| dates :", sorted(set(re.findall(r"<(?:\w+:)?Date>([^<]+)", s)))[:4])
for tag in ("useLimitation", "otherConstraints"):
    for t in texts(tag, 3): print("   ", tag, ":", t[:300])
print("    URL :", sorted(set(html.unescape(u) for u in re.findall(r"<(?:\w+:)?URL>([^<]+)", s)))[:8])
if "<" not in s[:5]: print("   ", s[:200])
PY
done
for m in M1235 M2196; do
  for svc in WMS WFS; do
    l=$(echo "$svc" | tr 'A-Z' 'a-z')
    get "$T/cap.xml" "https://geoservizi.regione.liguria.it/geoserver/$m/$l?service=$svc&request=GetCapabilities"
    python3 - <<'PY'
import re, html
s = open("/tmp/sonde/cap.xml", encoding="utf-8", errors="replace").read()
names = re.findall(r"<(?:\w+:)?Name>([^<]+)</(?:\w+:)?Name>", s); titles = re.findall(r"<(?:\w+:)?Title>([^<]+)</(?:\w+:)?Title>", s)
print("      noms :", [html.unescape(n) for n in names][:14]); print("      titres :", [html.unescape(t)[:60] for t in titles][:10])
for tag in ("Fees", "AccessConstraints"):
    print("     ", tag, ":", [html.unescape(x)[:200] for x in re.findall(r"<(?:\w+:)?%s>([^<]*)</(?:\w+:)?%s>" % (tag, tag), s)][:2])
PY
  done
done
for m in M1235 M2196; do
  W="WFS:https://geoservizi.regione.liguria.it/geoserver/$m/wfs"
  for l in $(ogrinfo -ro -so "$W" 2>/dev/null | grep -E "^[0-9]+:" | sed -E 's/^[0-9]+: ([^ ]+).*/\1/' | head -3); do
    echo "--- $m couche $l"
    ogrinfo -ro -so "$W" "$l" 2>&1 | grep -v -E "^(PROJCRS|GEOGCRS|BOUNDCRS|    |  [A-Z]+\[|INFO)" | cut -c1-160 | head -40
    ogrinfo -ro -al -limit 2 -geom=SUMMARY "$W" "$l" 2>&1 | grep -E "^  [A-Za-z_0-9]+ \(" | cut -c1-200 | head -50
  done
done

echo "##### C. Nouveaux essais : Monaco, ARPA Piemonte"
curl -sS -m 60 -A "$UA" -o "$T/mc.html" -w "  -> %{http_code} %{size_download}o https://data.gouv.mc/\n" "https://data.gouv.mc/"
grep -o -i -E "<title[^>]*>[^<]*" "$T/mc.html" | head -1 | cut -c1-200
get "$T/ms.json" "https://webgis.arpa.piemonte.it/ags101free/rest/services/campi_elettromagnetici/Radiazioni_non_ionizzanti_pubblico/MapServer?f=pjson"
head -c 400 "$T/ms.json" | tr '\n' ' '; echo

echo "##### D. Calage, deuxième passe"
get "$T/departements.geojson.gz" "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/departements-5m.geojson.gz"
gunzip -f "$T/departements.geojson.gz"
get "$T/sites.html" "https://data.arcep.fr/mobile/sites/last/"
f=$(grep -o -E "[0-9]{4}_T[1-4]_sites_Metropole\.csv" "$T/sites.html" | head -1)
get "$T/sites.csv" "https://data.arcep.fr/mobile/sites/last/$f"
LIST=https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/00_Metropole/
get "$T/listing.html" "$LIST"
for op in OF SFR0; do
  f=$(grep -o -E "[0-9]{4}_T[1-4]_couv_Metropole_${op}_4G_data\.gpkg\.7z" "$T/listing.html" | head -1)
  curl -sS -L -m 1500 -A "$UA" -o "$T/a.7z" -w "   $f -> %{http_code} %{size_download}o en %{time_total}s\n" "$LIST$f"
  7z x -y -o"$T/x_$op" "$T/a.7z" >/dev/null && mv "$T/x_$op"/*.gpkg "$T/arcep_$op.gpkg"; rm -f "$T/a.7z"
done
python3 - <<'CALAGE_PY' 2>&1 | grep -v -E "swig/python detected|observer location falls outside" | cut -c1-340
"""Calage, deuxième passe : règle à trois niveaux, sites manquants, erreur de position, hauteur d'antenne.

Calage de la méthode d'estimation sur la France, où la vérité officielle existe.

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


def accumulate(band, gt, shape, sites, shift=None, rng=None, keep=1.0, oz=OZ):
    """Distance (km) au site le plus proche : visible (dlos), presque visible (dq), quelconque (dany)."""
    H, W = shape
    if keep < 1.0: sites = [s for s in sites if rng.random() < keep]
    dlos = np.full(shape, np.inf, np.float32); dq = np.full(shape, np.inf, np.float32); dany = np.full(shape, np.inf, np.float32)
    for xm, ym, lat, _, _ in sites:
        k = 1.0 / math.cos(math.radians(lat))
        if shift is not None:
            r = float(rng.rayleigh(shift[1])) if shift[0] == "rayleigh" else shift[1]; a = float(rng.uniform(0, 2 * math.pi))
            xm, ym = xm + r * k * math.cos(a), ym + r * k * math.sin(a)
        ds = gdal.ViewshedGenerate(band, "MEM", "", [], xm, ym, oz, TZ, 255, 1, 0, -1.0, CC / (k * k), gdal.GVM_Edge, MD * k,
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
    return dlos, dq, dany, len(sites)


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


SCENARIOS = [
    ("positions exactes", {}),
    ("erreur de position 500 m", {"shift": ("rayleigh", 500.0)}),
    ("30 % des sites manquants", {"keep": 0.7}),
    ("erreur 500 m et 30 % des sites manquants", {"shift": ("rayleigh", 500.0), "keep": 0.7}),
    ("erreur 1000 m et 50 % des sites manquants", {"shift": ("rayleigh", 1000.0), "keep": 0.5}),
    ("positions exactes, antenne supposée à 15 m", {"oz": 15.0}),
]
# règles à trois niveaux : (bonne : vue, presque vue, distance ; limitée : vue, presque vue, distance), en km
P1 = (5, 1, 0.5, 15, 7.5, 2)
P2 = (3, 0.5, 0, 10, 5, 1)


def levels3(rule):
    return np.where(covered(*rule[:3]), 2, np.where(covered(*rule[3:]), 1, 0))


def matrix3(J, P):
    M = np.zeros((3, 4))
    for p in range(3): M[p] = J[P == p].sum(axis=0)
    return M


def summary3(M):
    tot = M.sum(); parts = 100 * M.sum(axis=1) / tot
    return {"exact3": (M[0, 0] + M[1, 1] + M[2, 2] + M[2, 3]) / tot, "rappel_blanc": M[0, 0] / max(1.0, M[:, 0].sum()), "precision_blanc": M[0, 0] / max(1.0, M[0].sum()),
            "couv2": M[2, 1:].sum() / max(1.0, M[2].sum()), "bon2": M[2, 2:].sum() / max(1.0, M[2].sum()), "couv1": M[1, 1:].sum() / max(1.0, M[1].sum()), "parts": parts,
            "faux_couvert": (M[1, 0] + M[2, 0]) / max(1.0, M[:, 0].sum())}


def fmt3(s):
    return "prédit 0/1/2 : %4.1f / %4.1f / %4.1f %% | zones blanches : rappel %.1f %%, précision %.1f %% | prédit 2 : couvert %.1f %%, niveau >= 2 %.1f %% | prédit 1 : couvert %.1f %% | accord 3 classes %.1f %%" % (
        s["parts"][0], s["parts"][1], s["parts"][2], 100 * s["rappel_blanc"], 100 * s["precision_blanc"], 100 * s["couv2"], 100 * s["bon2"], 100 * s["couv1"], 100 * s["exact3"])


def search3(J, min_rappel=0.0):
    best = None
    for g1 in (2, 3, 5, 7.5):
        for g2 in (0, 0.5, 1, 2):
            for g3 in (0, 0.5, 1):
                G = covered(g1, g2, g3)
                for l1 in (10, 15, 20, 30):
                    for l2 in (3, 5, 7.5, 10):
                        for l3 in (1, 2, 3):
                            P = np.where(G, 2, np.where(covered(l1, l2, l3), 1, 0)); s = summary3(matrix3(J, P))
                            if s["rappel_blanc"] < min_rappel: continue
                            if best is None or s["exact3"] > best[0]["exact3"]: best = (s, (g1, g2, g3, l1, l2, l3))
    return best


def main():
    rng = np.random.default_rng(20261115); pooled = {}; per = []
    for dept, code_op, arcep_op in COMBOS:
        t = time.time(); geom, nom = dept_geometry(dept); gm, bounds, W, H = window_for(geom)
        gt = (bounds[0], RES, 0, bounds[3], 0, -RES)
        dem, ntiles = load_dem(bounds, W, H); band = dem.GetRasterBand(1)
        sites, total = load_sites(code_op, geom)
        mask_ds = gdal.GetDriverByName("MEM").Create("", W, H, 1, gdal.GDT_Byte); mask_ds.SetGeoTransform(gt); mask_ds.SetProjection(srs(3857).ExportToWkt()); burn(mask_ds, [gm], 1)
        mask = mask_ds.GetRasterBand(1).ReadAsArray() == 1
        level = arcep_raster(os.path.join(T, "arcep_%s.gpkg" % arcep_op), dept, bounds, W, H)[0]
        print("== %s (%s), %s : %d sites, préparation %.0f s" % (nom, dept, arcep_op, len(sites), time.time() - t))
        for label, kw in SCENARIOS:
            if time.time() - T0 > 50 * 60: print("   (%s : sauté, budget de temps dépassé)" % label); continue
            t = time.time(); dlos, dq, dany, n = accumulate(band, gt, (H, W), sites, kw.get("shift"), rng, kw.get("keep", 1.0), kw.get("oz", OZ))
            J = joint_hist(dlos, dq, dany, level, mask); pooled[label] = pooled.get(label, 0) + J; per.append((nom, arcep_op, label, J))
            print("   %-45s %d sites, %.0f s" % (label, n, time.time() - t))
        del dem, level, mask
    print("== Règles à trois niveaux, tous cas réunis (niveau 2 = bonne, 1 = limitée, 0 = pas de couverture ; comparées aux niveaux Arcep 0, 1, 2 ou 3)")
    J0 = pooled["positions exactes"]; b = search3(J0); bp = search3(J0, 0.85)
    rules = {"P1 %s" % (P1,): P1, "P2 %s" % (P2,): P2, "meilleur accord %s" % (b[1],): b[1]}
    if bp: rules["meilleur accord avec rappel des zones blanches >= 85 %% %s" % (bp[1],)] = bp[1]
    for label, J in pooled.items():
        print("   -- %s" % label)
        for name, r in rules.items(): print("      %-78s %s" % (name[:78], fmt3(summary3(matrix3(J, levels3(r))))))
        bj = search3(J); print("      %-78s %s" % (("recalculé pour ce cas %s" % (bj[1],))[:78], fmt3(bj[0])))
        for name, r in (("couvert ou non, règle (10, 5, 1)", (10, 5, 1)), ("couvert ou non, règle (15, 10, 2)", (15, 10, 2))):
            print("      %-78s %s" % (name, fmt(scores(J, covered(*r)))))
    for label in ("positions exactes", "erreur 500 m et 30 % des sites manquants"):
        if label not in pooled: continue
        M = matrix3(pooled[label], levels3(P1))
        print("   -- matrice P1, %s (lignes = prédit 0, 1, 2 ; colonnes = Arcep 0, 1, 2, 3 ; %% du total)" % label)
        for p in range(3): print("        prédit %d : %s" % (p, "  ".join("%5.1f" % (100 * v / M.sum()) for v in M[p])))
    print("   -- par cas, règle P1")
    for nom, op, label, J in per:
        if label in ("positions exactes", "erreur 500 m et 30 % des sites manquants", "erreur 1000 m et 50 % des sites manquants"):
            print("      %-13s %-5s %-42s %s" % (nom, op, label, fmt3(summary3(matrix3(J, levels3(P1))))))
    if "erreur 500 m et 30 % des sites manquants" in pooled: table(pooled["erreur 500 m et 30 % des sites manquants"], "Tableau par classe de distance, erreur 500 m et 30 % des sites manquants")
    print("   durée totale : %.0f s" % (time.time() - T0))


main()
CALAGE_PY
echo "FIN"
