#!/usr/bin/env bash
# Sonde Espagne 3 : table officielle des opérateurs (CIF vers raison sociale), copie « eu1 » de l'image 4G
# (grille native), cohérence image/entités, faisabilité de la récupération (pages par OBJECTID, compression,
# extraction « Extract » sur une seule commune, lecture OGR paginée), textes juridiques complets et
# raster catalan « Cobertura mòbil 112 ». Uniquement des requêtes d'échantillon.
set -u
. "$(dirname "$0")/_lib.sh"
export UA T
apt-get update -qq >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends python3-pip poppler-utils >/dev/null 2>&1
pip install -q --break-system-packages lerc >/dev/null 2>&1 || pip install -q lerc >/dev/null 2>&1

python3 - <<'PY'
import gzip, html, json, math, os, re, subprocess, sys, textwrap, time, traceback, urllib.error, urllib.parse, urllib.request, zipfile

UA = os.environ.get("UA") or "carte-zones-blanches-sonde/1.0"
T = os.environ.get("T") or "/tmp/sonde"
NREQ = 0
PT = (0.66, 42.63)
SHARING = "https://www.arcgis.com/sharing/rest"
FS4 = "https://services-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/InfoCob4G_2024/FeatureServer"
F4 = FS4 + "/0"
IMG_US = "https://tiledimageservices9.arcgis.com/b5sc9d51LIwFoyfR/arcgis/rest/services/Cob4G_2024/ImageServer"
IMG_EU = "https://tiledimageservices-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/Cob4G_2024/ImageServer"
OPS_ITEM = "378d9746a2814325ba52c2698bdcd8fe"
CIFS = ("A78923125", "A80907397", "A82009812", "A82528548")
REGIONS = "CCOM IN ('02','09','15','16')"
quote = urllib.parse.quote


def P(s="", n=420):
    for line in str(s).split("\n"):
        print(line[:n] + (" …" if len(line) > n else ""), flush=True)


def wrap(text, maxchars=6000, width=360, indent="   "):
    text = text or ""
    for line in textwrap.wrap(text[:maxchars], width):
        P(indent + line, width + 40)
    if len(text) > maxchars:
        P(indent + f"(… tronqué, {len(text)} caractères au total)")


def fetch(url, timeout=240, data=None, gz=False, cap=80_000_000):
    """Renvoie (code, type, corps décodé, octets reçus, secondes)."""
    global NREQ
    NREQ += 1
    time.sleep(0.4)
    headers = {"User-Agent": UA}
    if gz:
        headers["Accept-Encoding"] = "gzip"
    req = urllib.request.Request(url, headers=headers, data=data)
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read(cap)
            body = gzip.decompress(raw) if r.headers.get("Content-Encoding") == "gzip" else raw
            return r.status, r.headers.get("Content-Type", ""), body, len(raw), time.time() - t0
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Content-Type", ""), e.read()[:3000], 0, time.time() - t0
    except Exception as e:  # noqa: BLE001
        return 0, "", repr(e).encode(), 0, time.time() - t0


def jget(url, quiet=True, data=None):
    code, ctype, body, _, _ = fetch(url, data=data)
    try:
        j = json.loads(body.decode("utf-8", "replace"))
    except Exception:  # noqa: BLE001
        j = None
    bad = j is None or (isinstance(j, dict) and "error" in j) or code != 200
    if not quiet or bad:
        P(f"  -> {code} {len(body)}o {ctype[:35]}  {url}", 600)
    if j is None:
        P("     (pas du JSON) " + body[:300].decode("utf-8", "replace").replace("\n", " "))
    elif isinstance(j, dict) and "error" in j:
        P("     ERREUR API : " + json.dumps(j["error"], ensure_ascii=False)[:500], 600)
        return None
    return j


def clean(s, n=600):
    if s is None:
        return None
    s = re.sub(r"<[^>]+>", " ", str(s))
    s = re.sub(r"\s+", " ", html.unescape(s)).strip()
    return s[:n] + (" …" if len(s) > n else "")


def day(ms):
    try:
        return time.strftime("%Y-%m-%d", time.gmtime(int(ms) / 1000))
    except Exception:  # noqa: BLE001
        return str(ms)


def cj(o, n=300):
    return json.dumps(o, ensure_ascii=False, separators=(",", ":"))[:n]


def section(title):
    P("")
    P("##### " + title)


def qurl(base, params):
    return base + "/query?" + urllib.parse.urlencode(params)


# ---------------------------------------------------------------- A. table des opérateurs
def s_operateurs():
    section("A. Table des opérateurs citée par la fenêtre d'information (élément 378d9746…)")
    it = jget(f"{SHARING}/content/items/{OPS_ITEM}?f=json") or {}
    P(f"   élément : title={it.get('title')!r} type={it.get('type')} owner={it.get('owner')} access={it.get('access')} created={day(it.get('created'))} modified={day(it.get('modified'))} licenseInfo={clean(it.get('licenseInfo'), 200)!r}")
    P(f"   url={it.get('url')}")
    url = (it.get("url") or "").rstrip("/")
    if not url:
        return
    if re.search(r"/\d+$", url):
        subs = [(url.rsplit("/", 1)[1], None, "couche ou table")]
        url = url.rsplit("/", 1)[0]
    else:
        root = jget(url + "?f=json") or {}
        subs = [(x.get("id"), x.get("name"), "couche") for x in root.get("layers") or []] + [(x.get("id"), x.get("name"), "table") for x in root.get("tables") or []]
    P("   contenu du service : " + cj(subs, 400))
    for sid, name, kind in subs[:2]:
        base = f"{url}/{sid}"
        m = jget(base + "?f=json") or {}
        P(f"   {kind} {sid} {name!r} : type={m.get('type')} capabilities={m.get('capabilities')} champs=" + " ; ".join(f"{f.get('name')}({str(f.get('type')).replace('esriFieldType', '')})" for f in m.get("fields") or []), 900)
        c = jget(qurl(base, {"where": "1=1", "returnCountOnly": "true", "f": "json"})) or {}
        P(f"     nombre de lignes : {c.get('count')}")
        j = jget(qurl(base, {"where": "OPERADOR IN (" + ",".join(f"'{c_}'" for c_ in CIFS) + ")", "outFields": "*", "returnGeometry": "false", "f": "json"}))
        for f in (j or {}).get("features") or []:
            P("     " + cj(f.get("attributes"), 700), 800)


# ---------------------------------------------------------------- B. image eu1 et cohérence
def lerc_mask(body):
    import lerc
    res = lerc.decode(body)
    arr, msk = res[1], (res[2] if len(res) > 2 else None)
    import numpy as np
    return arr, (np.ones(arr.shape, bool) if msk is None else msk.astype(bool))


def merc(lon, lat):
    return lon * 20037508.342789244 / 180.0, math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * 6378137.0


def unmerc(x, y):
    return x / 20037508.342789244 * 180.0, math.degrees(2 * math.atan(math.exp(y / 6378137.0)) - math.pi / 2)


def window_features(env):
    feats, offset = [], 0
    for _ in range(5):
        j = jget(qurl(F4, {"where": "COBERTURA<>''", "geometry": env, "geometryType": "esriGeometryEnvelope", "inSR": "4258", "spatialRel": "esriSpatialRelIntersects",
                           "outFields": "COBERTURA", "returnGeometry": "true", "orderByFields": "OBJECTID", "resultOffset": str(offset), "resultRecordCount": "2000", "f": "geojson"}))
        if not j:
            break
        got = j.get("features") or []
        feats += got
        offset += len(got)
        if len(got) < 2000:
            break
    return feats


def compare(label, mask, geotransform, epsg, feats):
    import numpy as np
    from osgeo import gdal, osr
    gdal.UseExceptions()
    path = f"{T}/win_{label}.geojson"
    open(path, "w").write(json.dumps({"type": "FeatureCollection", "name": "w", "features": feats}))
    src = path
    if epsg != 4326:
        src = f"/vsimem/win_{label}.gpkg"
        gdal.VectorTranslate(src, path, format="GPKG", dstSRS=f"EPSG:{epsg}", layerName="w")
    sr = osr.SpatialReference(); sr.ImportFromEPSG(epsg)
    out = {}
    ops = [None] + list(CIFS)
    for op in ops:
        dst = gdal.GetDriverByName("MEM").Create("", mask.shape[1], mask.shape[0], 1, gdal.GDT_Byte)
        dst.SetGeoTransform(geotransform)
        dst.SetProjection(sr.ExportToWkt())
        kw = {"burnValues": [1], "layers": ["w"]}
        if op:
            kw["where"] = f"COBERTURA LIKE '%{op}%'"
        gdal.Rasterize(dst, src, **kw)
        out[op] = dst.ReadAsArray().astype(bool)
    vec = out[None]
    P(f"   [{label}] pixels={mask.size} ; image={int(mask.sum())} ; entités (centre du pixel)={int(vec.sum())} ; les deux={int((mask & vec).sum())} ; image seule={int((mask & ~vec).sum())} ; entités seules={int((~mask & vec).sum())} ; accord={100.0 * float((mask == vec).mean()):.2f} %")
    P(f"   [{label}] pixels couverts par opérateur (entités) : " + " ; ".join(f"{op}={int(out[op].sum())}" for op in CIFS))


def s_image():
    section("B. Image tuilée 4G, copie « eu1 » (grille native) : Cob4G_2024/ImageServer")
    import numpy as np
    m = jget(IMG_EU + "?f=json") or {}
    keys = ("name", "capabilities", "pixelSizeX", "pixelSizeY", "pixelType", "bandCount", "serviceItemId", "datasetFormat", "compressionType", "minValues", "maxValues", "access", "allowCopy", "exportTilesAllowed", "created", "modified", "uncompressedSize")
    parts = [f"{k}={m.get(k)}" for k in keys if k in m]
    for i in range(0, len(parts), 6):
        P("   " + " | ".join(parts[i:i + 6]), 800)
    P(f"   spatialReference={cj(m.get('spatialReference'))} | extent={cj(m.get('extent'), 300)}", 700)
    ti = m.get("tileInfo") or {}
    lods = ti.get("lods") or []
    P(f"   tuiles : {ti.get('cols')}x{ti.get('rows')} format={ti.get('format')} origine={ti.get('origin')} sr={ti.get('spatialReference')}")
    P("   niveaux (niveau:résolution) : " + " ".join(f"{l.get('level')}:{l.get('resolution')!r}" for l in lods), 900)
    code, ctype, body, _, _ = fetch(IMG_EU + "/keyProperties?f=json")
    P("   keyProperties : " + body[:240].decode("utf-8", "replace"))
    if m.get("serviceItemId"):
        it = jget(f"{SHARING}/content/items/{m['serviceItemId']}?f=json") or {}
        P(f"   élément {m['serviceItemId']} : title={it.get('title')!r} type={it.get('type')} owner={it.get('owner')} access={it.get('access')} created={day(it.get('created'))} modified={day(it.get('modified'))} licenseInfo={clean(it.get('licenseInfo'), 200)!r} url={it.get('url')}", 800)
    if not lods:
        return
    ox, oy = ti["origin"]["x"], ti["origin"]["y"]
    res = lods[-1]["resolution"]
    ts = res * 256
    col, row = int((PT[0] - ox) // ts), int((oy - PT[1]) // ts)
    url = f"{IMG_EU}/tile/{lods[-1]['level']}/{row}/{col}"
    code, ctype, body, _, _ = fetch(url)
    P(f"   tuile eu1 au point d'essai -> {code} {len(body)}o {ctype[:28]} {url}", 500)
    if code != 200 or body[:5] != b"Lerc2":
        P(f"     début : {body[:80]!r}")
        return
    arr, mask = lerc_mask(body)
    vals, counts = np.unique(arr[mask], return_counts=True)
    P(f"     décodage : {arr.shape} {arr.dtype}, pixels valides={int(mask.sum())}, valeurs:effectifs=" + " ".join(f"{v}:{c}" for v, c in zip(vals.tolist()[:8], counts.tolist()[:8])))
    x0, y0 = ox + col * ts, oy - row * ts
    P(f"     coin haut gauche de la tuile : lon={x0!r} lat={y0!r} ; pas={res!r}° ; emprise au sol d'un pixel vers 42,6° N : {res * 111320 * math.cos(math.radians(42.63)):.1f} m x {res * 111132:.1f} m")
    jp, ip = int((PT[0] - x0) // res), int((y0 - PT[1]) // res)
    j0, j1, i0, i1 = max(0, jp - 60), min(256, jp + 60), max(0, ip - 60), min(256, ip + 60)
    wx0, wy0, wx1, wy1 = x0 + j0 * res, y0 - i0 * res, x0 + j1 * res, y0 - i1 * res
    feats = window_features(f"{wx0},{wy1},{wx1},{wy0}")
    P(f"   fenêtre eu1 : lignes {i0} à {i1}, colonnes {j0} à {j1} ; enveloppe {wx0:.6f},{wy1:.6f},{wx1:.6f},{wy0:.6f} ; {len(feats)} entités avec COBERTURA<>''")
    compare("eu1_natif", mask[i0:i1, j0:j1], (wx0, res, 0, wy0, 0, -res), 4326, feats)
    # même comparaison avec la tuile en EPSG:3857 utilisée par la carte officielle
    mu = jget(IMG_US + "?f=json") or {}
    tiu = mu.get("tileInfo") or {}
    oxu, oyu = tiu["origin"]["x"], tiu["origin"]["y"]
    resu = tiu["lods"][-1]["resolution"]
    tsu = resu * 256
    mx, my = merc(*PT)
    colu, rowu = int((mx - oxu) // tsu), int((oyu - my) // tsu)
    code, ctype, body, _, _ = fetch(f"{IMG_US}/tile/{tiu['lods'][-1]['level']}/{rowu}/{colu}")
    arru, masku = lerc_mask(body)
    x0u, y0u = oxu + colu * tsu, oyu - rowu * tsu
    jp, ip = int((mx - x0u) // resu), int((y0u - my) // resu)
    j0, j1, i0, i1 = max(0, jp - 45), min(256, jp + 45), max(0, ip - 45), min(256, ip + 45)
    ux0, uy0, ux1, uy1 = x0u + j0 * resu, y0u - i0 * resu, x0u + j1 * resu, y0u - i1 * resu
    (lo0, la1), (lo1, la0) = unmerc(ux0, uy0), unmerc(ux1, uy1)
    feats = window_features(f"{lo0},{la0},{lo1},{la1}")
    P(f"   fenêtre 3857 (tuile {rowu}/{colu}) : {len(feats)} entités avec COBERTURA<>''")
    compare("carte_3857", masku[i0:i1, j0:j1], (ux0, resu, 0, uy0, 0, -resu), 3857, feats)


# ---------------------------------------------------------------- C. faisabilité de la récupération
def s_recuperation():
    section("C. Récupération des entités : volumes, pagination, compression")
    for label, where in (("régions utiles, COBERTURA<>''", REGIONS + " AND COBERTURA<>''"), ("régions utiles, COBERTURA=''", REGIONS + " AND COBERTURA=''")):
        j = jget(qurl(F4, {"where": where, "returnCountOnly": "true", "f": "json"})) or {}
        P(f"   compte ({label}) : {j.get('count')}")
    last = 0
    for label, params, gz in (
        ("page 1 par OBJECTID, JSON gzip", {"where": "CCOM='02' AND OBJECTID>0", "f": "json"}, True),
        ("page 2 par OBJECTID, JSON gzip", {"where": "CCOM='02' AND OBJECTID>{last}", "f": "json"}, True),
        ("page à resultOffset=1000000, JSON gzip", {"where": "CCOM='02'", "resultOffset": "1000000", "f": "json"}, True),
        ("page 1 par OBJECTID, PBF", {"where": "CCOM='02' AND OBJECTID>0", "f": "pbf"}, False),
    ):
        p = {"outFields": "OBJECTID,COBERTURA", "returnGeometry": "true", "orderByFields": "OBJECTID", "resultRecordCount": "2000"}
        p.update(params)
        p["where"] = p["where"].replace("{last}", str(last))
        code, ctype, body, nraw, dt = fetch(qurl(F4, p), gz=gz)
        info = ""
        if p["f"] == "json":
            try:
                jj = json.loads(body.decode("utf-8", "replace"))
                feats = jj.get("features") or []
                ids = [f["attributes"]["OBJECTID"] for f in feats]
                if ids and "OBJECTID>" in p["where"]:
                    last = max(ids)
                info = f"entités={len(feats)} OBJECTID de {min(ids) if ids else None} à {max(ids) if ids else None} exceededTransferLimit={jj.get('exceededTransferLimit')}" + (" ERREUR " + cj(jj.get("error"), 200) if "error" in jj else "")
            except Exception as e:  # noqa: BLE001
                info = f"illisible {e!r}"
        P(f"   {label} -> {code} en {dt:.1f} s ; reçu {nraw}o, décodé {len(body)}o ; {info}", 500)


def s_extract():
    section("D. Capacité « Extract » : essai de createReplica anonyme sur une seule commune (Benasque)")
    data = urllib.parse.urlencode({
        "f": "json", "layers": "0", "replicaName": "essai_une_commune",
        "layerQueries": json.dumps({"0": {"where": "Municipio='Benasque'", "useGeometry": True, "queryOption": "useFilter"}}),
        "geometry": "0.40,42.50,0.75,42.75", "geometryType": "esriGeometryEnvelope", "inSR": "4258",
        "returnAttachments": "false", "syncModel": "none", "dataFormat": "filegdb", "async": "true", "transportType": "esriTransportTypeUrl",
    }).encode()
    code, ctype, body, _, dt = fetch(FS4 + "/createReplica", data=data)
    P(f"   POST createReplica -> {code} en {dt:.1f} s : " + body[:400].decode("utf-8", "replace").replace("\n", " "), 600)
    try:
        j = json.loads(body.decode("utf-8", "replace"))
    except Exception:  # noqa: BLE001
        return
    status_url = j.get("statusUrl")
    result_url = j.get("resultUrl") or j.get("URL")
    if status_url and not result_url:
        for i in range(24):
            time.sleep(5)
            code, ctype, body, _, _ = fetch(status_url + "?f=json")
            try:
                s = json.loads(body.decode("utf-8", "replace"))
            except Exception:  # noqa: BLE001
                s = {}
            if i in (0, 3, 11, 23) or s.get("status") in ("Completed", "Failed", "CompletedWithErrors"):
                P(f"   état après {5 * (i + 1)} s : " + cj({k: s.get(k) for k in ("status", "resultUrl", "error", "recordCount", "replicaName")}, 500), 600)
            if s.get("status") in ("Completed", "Failed", "CompletedWithErrors") or "error" in s:
                result_url = s.get("resultUrl")
                break
    if not result_url:
        P("   pas de fichier produit")
        return
    code, ctype, body, nraw, dt = fetch(result_url, cap=120_000_000)
    P(f"   fichier produit -> {code} {len(body)}o {ctype[:40]} en {dt:.1f} s : {result_url.split('?')[0][:160]}", 500)
    if code != 200 or body[:2] != b"PK":
        P(f"     début : {body[:120]!r}")
        return
    zpath = T + "/extrait.zip"
    open(zpath, "wb").write(body)
    names = zipfile.ZipFile(zpath).namelist()
    gdbs = sorted({n.split("/")[0] for n in names if ".gdb" in n.split("/")[0]})
    P(f"   archive : {len(names)} fichiers ; géodatabases : {gdbs}")
    if gdbs:
        out = subprocess.run(["ogrinfo", "-ro", "-so", "-al", f"/vsizip/{zpath}/{gdbs[0]}"], capture_output=True, text=True)
        lines = [l for l in (out.stdout + out.stderr).split("\n") if l.strip() and not re.match(r"^\s+(BBOX|AREA|SCOPE|USAGE|LENGTHUNIT|ANGLEUNIT|AXIS|ORDER|CS\[|PRIMEM|DATUM|ELLIPSOID|ENSEMBLE|MEMBER|ID\[)", l)]
        for l in lines[:44]:
            P("     " + l, 300)


def s_ogr():
    section("E. Lecture directe par GDAL/OGR (pilote ESRIJSON, pagination automatique) : commune de Benasque")
    url = qurl(F4, {"where": "Municipio='Benasque' AND COBERTURA<>''", "outFields": "OBJECTID,COBERTURA,NATCODE,CCOM,Municipio", "orderByFields": "OBJECTID", "resultRecordCount": "2000", "f": "json"})
    t0 = time.time()
    out = subprocess.run(["ogrinfo", "-ro", "-so", "-al", "-oo", "FEATURE_SERVER_PAGING=YES", "ESRIJSON:" + url], capture_output=True, text=True, timeout=600)
    P(f"   commande : ogrinfo -ro -so -al -oo FEATURE_SERVER_PAGING=YES \"ESRIJSON:{url}\"", 700)
    lines = [l for l in (out.stdout + out.stderr).split("\n") if l.strip() and not re.match(r"^\s+(BBOX|AREA|SCOPE|USAGE|LENGTHUNIT|ANGLEUNIT|AXIS|ORDER|CS\[|PRIMEM|ENSEMBLE|MEMBER)", l)]
    for l in lines[:30]:
        P("     " + l, 300)
    P(f"   durée : {time.time() - t0:.1f} s (attendu : 3420 entités si la pagination fonctionne, la commune en compte 3421 dont 1 sans couverture)")


for fn in (s_operateurs, s_image, s_recuperation, s_extract, s_ogr):
    try:
        fn()
    except Exception:  # noqa: BLE001
        P("ECHEC de la section : " + traceback.format_exc()[-1100:])
P("")
P(f"FIN python ({NREQ} requêtes)")
PY

# extrait <fichier> <regex de début> <nb de caractères> [avant] : texte continu à partir de la 1re occurrence
extrait() {
  python3 - "$1" "$2" "$3" "${4:-0}" <<'PY'
import re, sys, html, textwrap
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
if "<html" in s[:5000].lower() or "<!doctype" in s[:300].lower():
    s = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
    s = html.unescape(re.sub(r"<[^>]+>", " ", s))
s = re.sub(r"\s+", " ", s)
ms = list(re.finditer(sys.argv[2], s))
if not ms:
    print("   (aucune occurrence de", sys.argv[2], ")")
else:
    m = ms[-1] if sys.argv[2].startswith("(?#dernier)") else ms[0]
    a = max(0, m.start() - int(sys.argv[4]))
    for line in textwrap.wrap(s[a: m.start() + int(sys.argv[3])], 360):
        print("   " + line)
PY
}

autour() { # autour <fichier> <regex> [rayon] [max] : extraits autour des occurrences
  python3 - "$1" "$2" "${3:-300}" "${4:-5}" <<'PY'
import re, sys, html
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
if "<html" in s[:5000].lower() or "<!doctype" in s[:300].lower():
    s = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
    s = html.unescape(re.sub(r"<[^>]+>", " ", s))
s = re.sub(r"\s+", " ", s)
r, n, last = int(sys.argv[3]), 0, -10**9
for m in re.finditer(sys.argv[2], s, re.I):
    if m.start() - last < r:
        continue
    last = m.start(); n += 1
    print("   …", s[max(0, m.start() - r): m.end() + r], "…")
    if n >= int(sys.argv[4]):
        break
if n == 0:
    print("   (aucune occurrence de", sys.argv[2], ")")
PY
}

echo
echo "##### F. Mentions légales du ministère : section « Condiciones generales de reutilización » (texte continu)"
get "$T/nota.html" "https://digital.gob.es/nota-legal"
extrait "$T/nota.html" "(?#dernier)Condiciones generales de reutilizaci[oó]n" 5200 900

echo
echo "##### G. Page du ministère sur les cartes : description de la carte mobile"
get "$T/mapas.html" "https://digital.gob.es/telecomunicaciones-infraestructuras-digitales/areas-interes/banda-ancha/informacion-cobertura/mapas-servicios-banda-ancha"
extrait "$T/mapas.html" "(?#dernier)cuadr[ií]cula" 1500 1700
python3 - "$T/mapas.html" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
hrefs = sorted(set(re.findall(r'href="([^"]*informe[s]?-cobertura[^"]*)"', s)))
print("   liens « informes de cobertura » :", [h for h in hrefs if re.search(r"202[45]|informes-cobertura$", h)][:8])
PY

echo
echo "##### H. datos.gob.es : demande « Datos en abierto de conectividad móvil y antenas » (texte de la demande et de la réponse)"
get "$T/sol.html" "https://datos.gob.es/es/solicitud-de-datos/datos-en-abierto-de-conectividad-movil-y-antenas"
extrait "$T/sol.html" "(?#dernier)Fecha de la petici[oó]n" 2600 60

echo
echo "##### I. Catalunya : conditions d'usage des données ouvertes et raster « Cobertura mòbil 112 »"
get "$T/llic.html" "https://administraciodigital.gencat.cat/ca/dades/dades-obertes/informacio-practica/llicencies/"
autour "$T/llic.html" "Creative Commons|llic[eè]ncia oberta|CC0|CC BY|domini p[uú]blic" 450 4 | cut -c1-1100
python3 - <<'PY'
import os, subprocess, time, urllib.request
UA, T = os.environ.get("UA", "sonde"), os.environ.get("T", "/tmp/sonde")
url = "https://sig.gencat.cat/admin/server/servletFileDownloadDataRaster?rasterName=TELCO_COBERTURA_112"
path, cap, n, t0 = T + "/cat112.bin", 300_000_000, 0, time.time()
try:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=300) as r, open(path, "wb") as f:
        print("   en-têtes :", r.status, r.headers.get("Content-Type"), "Content-Length=", r.headers.get("Content-Length"), "Content-Disposition=", r.headers.get("Content-Disposition"))
        if int(r.headers.get("Content-Length") or 0) > cap:
            raise RuntimeError("fichier de plus de 300 Mo, téléchargement abandonné")
        while n < cap:
            chunk = r.read(4_000_000)
            if not chunk:
                break
            f.write(chunk); n += len(chunk)
    print(f"   téléchargé : {n} octets en {time.time() - t0:.0f} s" + (" (plafond atteint, fichier incomplet)" if n >= cap else ""))
    head = open(path, "rb").read(8)
    print("   signature :", head)
    target = path
    if head[:2] == b"PK":
        import zipfile
        names = zipfile.ZipFile(path).namelist()
        print("   archive :", names[:12])
        tifs = [x for x in names if x.lower().endswith((".tif", ".tiff"))]
        target = f"/vsizip/{path}/{tifs[0]}" if tifs else path
    out = subprocess.run(["gdalinfo", "-stats", "-hist", target], capture_output=True, text=True, timeout=900)
    import re
    lines = [l for l in (out.stdout + out.stderr).split("\n") if re.match(r"^(Driver|Size is|Origin|Pixel Size|Band |  NoData|  Min|  Minimum|  Color|ERROR|Warning|Upper Left|Lower Right|  \d+ buckets)", l) or "ID[\"EPSG\"" in l or "PROJCRS" in l or "TIFFTAG" in l or "AREA_OR_POINT" in l or "STATISTICS_VALID_PERCENT" in l]
    for l in lines[:26]:
        print("     " + l[:300])
    hist = [l for l in out.stdout.split("\n") if re.match(r"^\s+\d+( \d+)+\s*$", l)]
    if hist:
        print("     histogramme (début) :", hist[0].strip()[:400])
    from osgeo import gdal
    import numpy as np
    ds = gdal.Open(target)
    b = ds.GetRasterBand(1)
    a = b.ReadAsArray(buf_xsize=min(ds.RasterXSize, 4000), buf_ysize=min(ds.RasterYSize, 4000), resample_alg=gdal.GRIORA_NearestNeighbour)
    vals, counts = np.unique(a, return_counts=True)
    print("     valeurs (lecture sous-échantillonnée) :", " ".join(f"{v}:{c}" for v, c in list(zip(vals.tolist(), counts.tolist()))[:16]), "| catégories :", b.GetCategoryNames(), "| table de couleurs :", bool(b.GetColorTable()))
    md = ds.GetMetadata()
    print("     métadonnées :", {k: str(v)[:120] for k, v in list(md.items())[:10]})
except Exception as e:
    print("   échec :", repr(e)[:300])
PY

echo
echo "##### J. Méthodologie 2025 du ministère : seuils de présence 4G"
get "$T/metodo.pdf" "https://conectemos.digital.gob.es/content/dam/seteleco-portal-connect/resources/pdf/icba2025/Metodolog%C3%ADa_Informe_Cobertura-BA-2025.pdf"
pdftotext -layout "$T/metodo.pdf" "$T/metodo.txt" 2>/dev/null
python3 - "$T/metodo.txt" <<'PY'
import re, sys, textwrap
s = re.sub(r"\s+", " ", open(sys.argv[1], encoding="utf-8", errors="replace").read())
shown, last = 0, -10**9
for m in re.finditer(r"RSRP", s):
    if m.start() - last < 900:
        continue
    last = m.start(); shown += 1
    for line in textwrap.wrap("… " + s[max(0, m.start() - 650): m.start() + 650] + " …", 360):
        print("   " + line)
    print("   --")
    if shown >= 3:
        break
print("   occurrences de « RSRP » :", len(re.findall("RSRP", s)), "| de « 50 m » ou « 50m » :", len(re.findall(r"\b50 ?m\b", s)), "| de « operador » :", len(re.findall("operador", s, re.I)))
m = re.search(r"cobertura (móvil )?(por|de cada) operador|desglos\w+ por operador|informaci[oó]n por operador", s, re.I)
if m:
    print("   passage « par opérateur » :", s[max(0, m.start() - 400): m.start() + 500])
PY
echo "FIN"
