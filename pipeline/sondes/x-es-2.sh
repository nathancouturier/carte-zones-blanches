#!/usr/bin/env bash
# Sonde Espagne 2 : conditions d'usage de la carte du ministère (texte intégral), fenêtres d'information
# (popup) des cartes web, structure et valeurs des couches 4G (entités et image tuilée), décodage d'une
# tuile LERC, cohérence image/entités sur une petite fenêtre, puis alternatives régionales.
# Uniquement des requêtes d'échantillon sur les API publiques.
set -u
. "$(dirname "$0")/_lib.sh"
export UA T
apt-get update -qq >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends python3-pip poppler-utils >/dev/null 2>&1
pip install -q --break-system-packages lerc >/dev/null 2>&1 || pip install -q lerc >/dev/null 2>&1
python3 -c "import lerc; print('module python lerc : présent')" 2>&1 | tail -1
gdalinfo --version
gdalinfo --formats 2>/dev/null | grep -E "^ *(MRF|ESRIJSON|GPKG|GeoJSON|WMS) " | cut -c1-110

python3 - <<'PY'
import csv, html, io, json, math, os, re, subprocess, sys, textwrap, time, traceback, urllib.error, urllib.parse, urllib.request

UA = os.environ.get("UA") or "carte-zones-blanches-sonde/1.0"
T = os.environ.get("T") or "/tmp/sonde"
NREQ = 0
PT = (0.66, 42.63)                   # point d'essai : haute vallée de Benasque (Aragon)
SHARING = "https://www.arcgis.com/sharing/rest"
ROOT = "ef9f55c81f304e5185fcdd7cecf98e7f"
WM4G = "21cb30f5fd6944ff9bb1f803bd028df3"
WM5G = "0ca5cb94b09d46dbb61c267b0765dfe1"
F4 = "https://services-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/InfoCob4G_2024/FeatureServer/0"
IMG = "https://tiledimageservices9.arcgis.com/b5sc9d51LIwFoyfR/arcgis/rest/services/Cob4G_2024/ImageServer"
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


def fetch(url, timeout=180, method="GET"):
    global NREQ
    NREQ += 1
    time.sleep(0.3)
    req = urllib.request.Request(url, headers={"User-Agent": UA}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = b"" if method == "HEAD" else r.read(60_000_000)
            return r.status, (r.headers.get("Content-Type", "") + (" len=" + r.headers.get("Content-Length", "?") if method == "HEAD" else "")), body
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Content-Type", ""), e.read()[:3000]
    except Exception as e:  # noqa: BLE001
        return 0, "", repr(e).encode()


def jget(url, quiet=False):
    code, ctype, body = fetch(url)
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
        P("     ERREUR API : " + json.dumps(j["error"], ensure_ascii=False)[:400])
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


def fq(base, params, timeout=180):
    url = base + "/query?" + urllib.parse.urlencode(params)
    code, ctype, body = fetch(url, timeout)
    return code, ctype, body, url


def fqj(base, params, label):
    code, ctype, body, url = fq(base, params)
    try:
        j = json.loads(body.decode("utf-8", "replace"))
    except Exception:  # noqa: BLE001
        j = None
    if not isinstance(j, dict) or "error" in j:
        P(f"   {label} -> {code} {len(body)}o ERREUR " + (cj(j.get("error"), 300) if isinstance(j, dict) else body[:200].decode("utf-8", "replace")), 600)
        P("     " + url, 520)
        return None
    return j


# ---------------------------------------------------------------- 1. conditions et textes
def s_terms():
    section("1. « Términos y condiciones » de la carte (widget_695), texte intégral")
    d = jget(f"{SHARING}/content/items/{ROOT}/data?f=json", quiet=True) or {}
    W = d.get("widgets") or {}

    def wtext(wid):
        return clean(((W.get(wid) or {}).get("config") or {}).get("text"), 40000)

    t = wtext("widget_695") or ""
    P(f"   longueur : {len(t)} caractères ; publishTimestamp={day(d.get('publishTimestamp'))} ; exbVersion={d.get('exbVersion')}")
    wrap(t, 7000)
    seen = {t}
    section("1b. Autres textes de la carte (700 premiers caractères de chacun)")
    n = 0
    for wid, w in W.items():
        if w.get("uri") != "widgets/common/text/":
            continue
        t = wtext(wid)
        if not t or len(t) < 60 or t in seen:
            continue
        seen.add(t)
        n += 1
        if n <= 14:
            P(f"   [{wid} {w.get('label')!r}] {t[:700]}", 820)


# ---------------------------------------------------------------- 2. popups des cartes web
def s_popups():
    section("2. Cartes web : définition des couches et fenêtres d'information")
    for iid, budget in ((WM4G, 3600), (WM5G, 1300)):
        wd = jget(f"{SHARING}/content/items/{iid}/data?f=json", quiet=True) or {}
        P(f"   CARTE {iid} : version={wd.get('version')} auteur={wd.get('authoringApp')} {wd.get('authoringAppVersion')}")
        for L in wd.get("operationalLayers") or []:
            P(f"   couche {L.get('title')!r} [{L.get('layerType')}] clés={sorted(L.keys())}", 500)
            rest = {k: v for k, v in L.items() if k not in ("popupInfo", "title", "layerType")}
            P("     définition : " + cj(rest, 1100), 1200)
            pi = L.get("popupInfo") or {}
            if not pi:
                continue
            P(f"     popup : titre={pi.get('title')!r} | description={clean(pi.get('description'), 700)}", 900)
            P("     champs visibles : " + " ; ".join(f"{f.get('fieldName')}={f.get('label')!r}" for f in (pi.get("fieldInfos") or []) if f.get("visible")), 700)
            for e in pi.get("expressionInfos") or []:
                P(f"     expression {e.get('name')} titre={e.get('title')!r} type={e.get('returnType')} :")
                P(textwrap.indent((e.get("expression") or "")[:budget], "       | "), 600)
            for el in pi.get("popupElements") or []:
                if el.get("type") == "text":
                    P("     élément texte : " + str(clean(el.get("text"), 900)), 1000)
                elif el.get("type") == "expression":
                    ei = el.get("expressionInfo") or {}
                    P(f"     élément expression titre={ei.get('title')!r} :")
                    P(textwrap.indent((ei.get("expression") or "")[:budget], "       | "), 600)
                else:
                    P(f"     élément {el.get('type')} : " + cj({k: v for k, v in el.items() if k != 'type'}, 300))


# ---------------------------------------------------------------- 3. organisation et éléments du compte
def s_org():
    section("3. Organisation ArcGIS Online et éléments publics du compte coberturaBA_eu")
    o = jget("https://conectemos.maps.arcgis.com/sharing/rest/portals/self?f=json", quiet=True) or {}
    P(f"   conectemos.maps.arcgis.com : id={o.get('id')} name={o.get('name')!r} urlKey={o.get('urlKey')} portalName={o.get('portalName')!r} region={o.get('region')} | description={clean(o.get('description'), 300)}", 800)
    o2 = jget(f"{SHARING}/portals/b5sc9d51LIwFoyfR?f=json", quiet=True) or {}
    P(f"   organisation b5sc9d51LIwFoyfR (hôte de l'image tuilée) : name={o2.get('name')!r} urlKey={o2.get('urlKey')} | description={clean(o2.get('description'), 200)}", 600)
    it = jget(f"{SHARING}/content/items/683c13c004604bd09c182143fc778d72?f=json", quiet=True) or {}
    P(f"   élément source 683c13c0… : title={it.get('title')!r} type={it.get('type')} owner={it.get('owner')} access={it.get('access')} created={day(it.get('created'))} modified={day(it.get('modified'))} licenseInfo={clean(it.get('licenseInfo'), 300)!r} url={it.get('url')}", 800)
    eu = jget("https://tiledimageservices-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/Cob4G_2024/ImageServer?f=json", quiet=True)
    P("   copie « eu1 » de Cob4G_2024 : " + ("absente ou refusée" if not eu else f"présente, capabilities={eu.get('capabilities')} pixelSizeX={eu.get('pixelSizeX')}"))
    s = jget(f"{SHARING}/search?q=" + quote("owner:coberturaBA_eu") + "&num=100&sortField=modified&sortOrder=desc&f=json", quiet=True) or {}
    res = s.get("results") or []
    P(f"   recherche owner:coberturaBA_eu : total={s.get('total')} (affichés : éléments 4G, 5G ou mobile)")
    n = 0
    for r in res:
        if re.search(r"4G|5G|m[oó]vil|cob.?m", str(r.get("title")), re.I) and n < 34:
            n += 1
            P(f"     {day(r.get('modified'))} | {r.get('type')} | {r.get('title')!r} | {r.get('id')} | {r.get('access')} | {r.get('url') or ''}", 330)


# ---------------------------------------------------------------- 4. couche d'entités 4G
SPATIAL = {}


def s_feature():
    section("4. Couche d'entités 4G : InfoCob4G_2024/FeatureServer/0")
    m = jget(F4 + "?f=json", quiet=True) or {}
    P(f"   name={m.get('name')!r} | description={clean(m.get('description'), 300)!r} | copyrightText={m.get('copyrightText')!r}")
    P("   " + " | ".join(f"{k}={m.get(k)}" for k in ("maxRecordCount", "standardMaxRecordCountNoGeometry", "tileMaxRecordCount", "maxRecordCountFactor", "cacheMaxAge", "supportsExceedsLimitStatistics", "infoInEstimates")), 700)
    for ix in (m.get("indexes") or [])[:12]:
        P(f"   index {ix.get('name')} champs={ix.get('fields')} unique={ix.get('isUnique')}")
    j = fqj(F4, {"where": "OBJECTID<=2", "outFields": "*", "returnGeometry": "true", "f": "json"}, "4a. échantillon OBJECTID<=2")
    if j:
        P(f"   4a. échantillon OBJECTID<=2 : sr={j.get('spatialReference')} geometryType={j.get('geometryType')}")
        for f in j.get("features") or []:
            rings = (f.get("geometry") or {}).get("rings") or []
            P("     attributs=" + cj(f.get("attributes"), 900), 1000)
            P(f"     géométrie : {len(rings)} anneau(x), {sum(len(r) for r in rings)} sommets ; 1er anneau={cj(rings[0] if rings else None, 420)}", 600)
    regions = {}
    j = fqj(F4, {"where": "1=1", "outFields": "CCOM,Comunidad_Autonoma", "returnDistinctValues": "true", "returnGeometry": "false", "orderByFields": "CCOM", "f": "json"}, "4b. valeurs distinctes de CCOM")
    if j:
        pairs = [(f["attributes"].get("CCOM"), f["attributes"].get("Comunidad_Autonoma")) for f in j.get("features") or []]
        P("   4b. CCOM=Comunidad_Autonoma : " + " ; ".join(f"{a}={b}" for a, b in pairs), 1000)
        for a, b in pairs:
            if b and re.search(r"Arag|Catalu|Navarra|Vasco|Euskadi", b):
                regions[a] = b
    if not regions:
        regions = {"02": "Aragón ?", "09": "Cataluña ?", "15": "Navarra ?", "16": "País Vasco ?"}
    total = 0
    for code_, name in regions.items():
        j = fqj(F4, {"where": f"CCOM='{code_}'", "returnCountOnly": "true", "f": "json"}, f"4c. compte CCOM={code_}")
        if j:
            total += j.get("count") or 0
            P(f"   4c. entités avec CCOM='{code_}' ({name}) : {j.get('count')}")
    P(f"   4c. total des régions utiles : {total} entités, soit {math.ceil(total / 2000)} pages de 2000")
    j = fqj(F4, {"where": "1=1", "outFields": "COBERTURA", "returnDistinctValues": "true", "returnGeometry": "false", "orderByFields": "COBERTURA", "f": "json"}, "4d. valeurs distinctes de COBERTURA")
    if j:
        vals = [f["attributes"].get("COBERTURA") for f in j.get("features") or []]
        P(f"   4d. COBERTURA : {len(vals)} valeurs distinctes (exceededTransferLimit={j.get('exceededTransferLimit')})")
        for i in range(0, min(len(vals), 48), 6):
            P("     " + " | ".join(repr(v) for v in vals[i:i + 6]), 800)
        tokens = sorted({t.strip() for v in vals if v for t in re.split(r"[;,/| ]+", v) if t.strip()})
        P(f"     identifiants élémentaires ({len(tokens)}) : " + ", ".join(tokens[:40]), 800)
    where = "Municipio='Benasque'"
    j = fqj(F4, {"where": where, "returnCountOnly": "true", "f": "json"}, "4e. compte Benasque")
    P(f"   4e. {where} : {(j or {}).get('count')} entités")
    stats = json.dumps([{"statisticType": "count", "onStatisticField": "OBJECTID", "outStatisticFieldName": "n"},
                        {"statisticType": "sum", "onStatisticField": "Shape__Area", "outStatisticFieldName": "aire_deg2"}])
    j = fqj(F4, {"where": where, "outStatistics": stats, "groupByFieldsForStatistics": "COBERTURA", "f": "json"}, "4e. statistiques Benasque")
    if j:
        for f in (j.get("features") or [])[:16]:
            P("     " + cj(f.get("attributes"), 300))
    for fmt in ("json", "geojson", "pbf"):
        code, ctype, body, url = fq(F4, {"where": where, "outFields": "COBERTURA,NATCODE", "returnGeometry": "true", "orderByFields": "OBJECTID", "resultOffset": "0", "resultRecordCount": "2000", "f": fmt})
        n = extra = None
        if fmt != "pbf":
            try:
                jj = json.loads(body.decode("utf-8", "replace"))
                n = len(jj.get("features") or [])
                extra = jj.get("exceededTransferLimit") or (jj.get("properties") or {}).get("exceededTransferLimit")
                if "error" in jj:
                    P("     ERREUR " + cj(jj["error"], 300))
                if fmt == "geojson":
                    open(T + "/benasque.geojson", "wb").write(body)
            except Exception as e:  # noqa: BLE001
                P(f"     illisible : {e!r}")
        P(f"   4e. première page (2000 au plus) en f={fmt} -> {code} {len(body)}o {ctype[:30]} entités={n} exceededTransferLimit={extra}")
        if fmt == "json":
            P("       " + url, 520)
    try:
        from osgeo import ogr, osr
        ogr.UseExceptions()
        ds = ogr.Open(T + "/benasque.geojson")
        lyr = ds.GetLayer(0)
        src = lyr.GetSpatialRef()
        dst = osr.SpatialReference(); dst.ImportFromEPSG(25831)
        src.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER); dst.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
        tr = osr.CoordinateTransformation(src, dst)
        area, nv, wmin, hmin, nf = {}, 0, 9.0, 9.0, 0
        for feat in lyr:
            g = feat.GetGeometryRef()
            x0, x1, y0, y1 = g.GetEnvelope()
            wmin, hmin = min(wmin, x1 - x0), min(hmin, y1 - y0)
            nv += sum(g.GetGeometryRef(i).GetPointCount() if g.GetGeometryRef(i).GetGeometryCount() == 0 else sum(g.GetGeometryRef(i).GetGeometryRef(k).GetPointCount() for k in range(g.GetGeometryRef(i).GetGeometryCount())) for i in range(g.GetGeometryCount()))
            g2 = g.Clone(); g2.Transform(tr)
            key = feat.GetField("COBERTURA")
            area[key] = area.get(key, 0.0) + g2.GetArea()
            nf += 1
        P(f"   4e. lecture OGR du GeoJSON : {nf} entités, {nv} sommets, plus petite emprise d'entité : {wmin:.7f}° x {hmin:.7f}° (pas de la grille)")
        P("       surface par valeur de COBERTURA (km², ETRS89 UTM 31N) : " + cj({k: round(v / 1e6, 3) for k, v in sorted(area.items(), key=lambda kv: -kv[1])}, 700), 800)
        out = subprocess.run(["ogrinfo", "-ro", "-so", "-al", T + "/benasque.geojson"], capture_output=True, text=True).stdout
        keep = [l for l in out.split("\n") if re.match(r"^(INFO|Layer name|Geometry|Feature Count|Extent|COBERTURA|NATCODE|Data axis)", l) or "ID[" in l]
        P("       ogrinfo -so : " + " | ".join(keep), 900)
    except Exception:  # noqa: BLE001
        P("   4e. analyse OGR en échec : " + traceback.format_exc()[-400:].replace("\n", " "), 600)
    x, y = PT
    env = f"{x - 0.01},{y - 0.01},{x + 0.01},{y + 0.01}"
    variants = {
        "inSR=4258": {"geometry": env, "geometryType": "esriGeometryEnvelope", "inSR": "4258", "spatialRel": "esriSpatialRelIntersects"},
        "inSR=4326": {"geometry": env, "geometryType": "esriGeometryEnvelope", "inSR": "4326", "spatialRel": "esriSpatialRelIntersects"},
        "sans inSR": {"geometry": env, "geometryType": "esriGeometryEnvelope", "spatialRel": "esriSpatialRelIntersects"},
    }
    for label, extra in variants.items():
        p = {"where": "1=1", "returnCountOnly": "true", "f": "json"}
        p.update(extra)
        j = fqj(F4, p, f"4f. compte par enveloppe ({label})")
        if j:
            P(f"   4f. compte par enveloppe de 0,02° autour de {PT} ({label}) : {j.get('count')}")
            if not SPATIAL:
                SPATIAL.update({k: v for k, v in extra.items() if k != "geometry"})
    if SPATIAL:
        for label, extra in (("sans outSR", {}), ("outSR=4326", {"outSR": "4326"}), ("outSR=3857", {"outSR": "3857"}), ("geometryPrecision=5", {"geometryPrecision": "5"})):
            p = {"where": "1=1", "geometry": env, "outFields": "COBERTURA", "returnGeometry": "true", "resultRecordCount": "2", "f": "json"}
            p.update(SPATIAL); p.update(extra)
            j = fqj(F4, p, f"4g. entités par enveloppe ({label})")
            if j:
                P(f"   4g. entités par enveloppe ({label}) : {len(j.get('features') or [])} entité(s), sr={j.get('spatialReference')}, exceededTransferLimit={j.get('exceededTransferLimit')}")


# ---------------------------------------------------------------- 5. image tuilée 4G
TILE = {}


def lerc_decode(body, label):
    """Décode une tuile LERC avec GDAL (pilote MRF) puis avec le module lerc ; renvoie (valeurs, masque)."""
    import numpy as np
    path = f"{T}/tile_{label}.lerc2"
    open(path, "wb").write(body)
    data = mask = None
    try:
        from osgeo import gdal
        gdal.UseExceptions()
        try:
            ds = gdal.OpenEx(path, gdal.OF_RASTER, open_options=["NDV=-9999"])
            opt = "avec -oo NDV=-9999"
        except Exception as e:  # noqa: BLE001
            P(f"     GDAL avec NDV refusé : {str(e)[:160]}")
            ds = gdal.OpenEx(path, gdal.OF_RASTER)
            opt = "sans option"
        b = ds.GetRasterBand(1)
        a = b.ReadAsArray()
        vals, counts = np.unique(a, return_counts=True)
        P(f"     GDAL ({opt}) : pilote={ds.GetDriver().ShortName} {ds.RasterXSize}x{ds.RasterYSize} type={gdal.GetDataTypeName(b.DataType)} nodata={b.GetNoDataValue()} valeurs:effectifs=" + " ".join(f"{v}:{c}" for v, c in zip(vals.tolist()[:12], counts.tolist()[:12])), 700)
        data, mask = a, (a != -9999)
    except Exception as e:  # noqa: BLE001
        P(f"     GDAL : lecture impossible : {str(e)[:300]}")
    try:
        import lerc
        info = lerc.getLercBlobInfo(body)
        P(f"     lerc.getLercBlobInfo : {info}", 500)
        res = lerc.decode(body)
        arr, msk = res[1], (res[2] if len(res) > 2 else None)
        valid = arr[msk.astype(bool)] if msk is not None else arr
        vals, counts = np.unique(valid, return_counts=True)
        P(f"     module lerc : tableau {arr.shape} {arr.dtype}, pixels valides={int(msk.sum()) if msk is not None else 'tous'} sur {arr.size}, valeurs valides:effectifs=" + " ".join(f"{v}:{c}" for v, c in zip(vals.tolist()[:12], counts.tolist()[:12])), 700)
        if msk is not None:
            data, mask = arr, msk.astype(bool)
    except Exception as e:  # noqa: BLE001
        P(f"     module lerc : indisponible ou en échec : {str(e)[:200]}")
    return data, mask


def s_image():
    section("5. Image tuilée 4G : Cob4G_2024/ImageServer")
    m = jget(IMG + "?f=json", quiet=True) or {}
    keys = ("description", "serviceDescription", "copyrightText", "created", "modified", "access", "allowCopy", "allowAnalysis", "compressionType", "datasetFormat",
            "serviceSourceType", "hasColormap", "hasHistograms", "minValues", "maxValues", "meanValues", "stdvValues", "uncompressedSize", "blockWidth", "blockHeight",
            "bandNames", "minPixelSize", "maxPixelSize", "meanPixelSize", "noDataValue", "noDataValues", "status", "server", "fields")
    parts = [f"{k}={clean(m.get(k), 160) if not isinstance(m.get(k), (int, float)) else m.get(k)}" for k in keys if k in m]
    for i in range(0, len(parts), 6):
        P("   " + " | ".join(parts[i:i + 6]), 800)
    P(f"   created={day(m.get('created'))} modified={day(m.get('modified'))}")
    for sub in ("keyProperties", "histograms", "statistics"):
        code, ctype, body = fetch(f"{IMG}/{sub}?f=json")
        P(f"   /{sub} -> {code} {len(body)}o : " + body[:260].decode("utf-8", "replace").replace("\n", " "), 420)
    ti = m.get("tileInfo") or {}
    lods = ti.get("lods") or []
    if not lods:
        P("   pas de tileInfo")
        return
    ox, oy = ti["origin"]["x"], ti["origin"]["y"]
    lod = lods[-1]
    res = lod["resolution"]
    ts = res * ti.get("cols", 256)
    ext = m.get("fullExtent") or {}
    P(f"   niveau le plus fin : {lod['level']} résolution={res!r} m (EPSG:3857), tuile={ts:.2f} m, origine=({ox!r}, {oy!r})")
    P(f"   grille complète au niveau {lod['level']} : {math.ceil((ext.get('xmax', 0) - ox) / ts)} colonnes x {math.ceil((oy - ext.get('ymin', 0)) / ts)} lignes")
    code, ctype, body = fetch(f"{IMG}/exportImage?bbox=60000,5250000,70000,5260000&bboxSR=3857&size=64,64&format=tiff&f=json")
    P(f"   exportImage (essai) -> {code} : " + body[:220].decode("utf-8", "replace").replace("\n", " "), 420)

    def merc(lon, lat):
        return lon * 20037508.342789244 / 180.0, math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * 6378137.0

    def tile_of(lon, lat):
        mx, my = merc(lon, lat)
        return int((mx - ox) // ts), int((oy - my) // ts)

    for label, (lon, lat) in (("benasque", PT), ("saragosse", (-0.8891, 41.6488)), ("mont_perdu", (0.034, 42.676)), ("mer", (2.6, 41.0))):
        col, row = tile_of(lon, lat)
        url = f"{IMG}/tile/{lod['level']}/{row}/{col}"
        code, ctype, body = fetch(url)
        P(f"   tuile « {label} » ({lon}, {lat}) -> {code} {len(body)}o {ctype[:28]} {url}", 500)
        if code == 200 and body[:5] == b"Lerc2":
            data, mask = lerc_decode(body, label)
            if label == "benasque" and data is not None:
                TILE.update({"data": data, "mask": mask, "col": col, "row": row, "res": res, "x0": ox + col * ts, "y0": oy - row * ts})
        elif code == 200:
            P(f"     début : {body[:60]!r}")
    # tuiles existantes sur l'emprise utile (ressource tilemap), sans télécharger les tuiles
    c0, r0 = tile_of(-3.5, 43.5)
    c1, r1 = tile_of(3.4, 39.8)
    P(f"   emprise utile au niveau {lod['level']} : colonnes {c0} à {c1}, lignes {r0} à {r1}, soit {(c1 - c0 + 1) * (r1 - r0 + 1)} tuiles au plus")
    present = total = 0
    ok = True
    for rr in range(r0, r1 + 1, 32):
        for cc in range(c0, c1 + 1, 32):
            w, h = min(32, c1 - cc + 1), min(32, r1 - rr + 1)
            code, ctype, body = fetch(f"{IMG}/tilemap/{lod['level']}/{rr}/{cc}/{w}/{h}?f=json")
            try:
                tm = json.loads(body.decode("utf-8", "replace"))
                data = tm.get("data") or []
                if "error" in tm or not data:
                    P(f"   tilemap {rr}/{cc}/{w}/{h} -> {code} : " + cj(tm, 260))
                    ok = False
                    break
                present += sum(1 for v in data if v) if len(data) > 1 else (w * h if data[0] else 0)
                total += w * h
            except Exception as e:  # noqa: BLE001
                P(f"   tilemap illisible ({code}) : {body[:160]!r} {e!r}")
                ok = False
                break
        if not ok:
            break
    if ok:
        P(f"   tilemap : {present} tuiles présentes sur {total} dans l'emprise utile (niveau {lod['level']})")


# ---------------------------------------------------------------- 6. cohérence image / entités
def s_coherence():
    section("6. Cohérence entre l'image tuilée et les entités (fenêtre autour du point d'essai)")
    if not TILE or not SPATIAL:
        P(f"   non réalisable (tuile décodée : {bool(TILE)}, requête spatiale : {bool(SPATIAL)})")
        return
    import numpy as np
    from osgeo import gdal, osr
    gdal.UseExceptions()
    res, x0, y0 = TILE["res"], TILE["x0"], TILE["y0"]
    mx = PT[0] * 20037508.342789244 / 180.0
    my = math.log(math.tan(math.pi / 4 + math.radians(PT[1]) / 2)) * 6378137.0
    jp, ip = int((mx - x0) // res), int((y0 - my) // res)
    j0, j1, i0, i1 = max(0, jp - 40), min(256, jp + 40), max(0, ip - 40), min(256, ip + 40)
    wx0, wy0, wx1, wy1 = x0 + j0 * res, y0 - i0 * res, x0 + j1 * res, y0 - i1 * res

    def lonlat(x, y):
        return x / 20037508.342789244 * 180.0, math.degrees(2 * math.atan(math.exp(y / 6378137.0)) - math.pi / 2)

    (lo0, la1), (lo1, la0) = lonlat(wx0, wy0), lonlat(wx1, wy1)
    env = f"{lo0},{la0},{lo1},{la1}"
    feats, offset = [], 0
    for _ in range(4):
        p = {"where": "1=1", "geometry": env, "outFields": "COBERTURA", "returnGeometry": "true", "orderByFields": "OBJECTID", "resultOffset": str(offset), "resultRecordCount": "2000", "f": "geojson"}
        p.update(SPATIAL)
        j = fqj(F4, p, "6. entités de la fenêtre")
        if not j:
            return
        got = j.get("features") or []
        feats += got
        offset += len(got)
        if len(got) < 2000:
            break
    P(f"   fenêtre : pixels lignes {i0} à {i1}, colonnes {j0} à {j1} de la tuile {TILE['row']}/{TILE['col']} ; enveloppe {env} ; {len(feats)} entités")
    open(T + "/win.geojson", "w").write(json.dumps({"type": "FeatureCollection", "features": feats}))
    gdal.VectorTranslate("/vsimem/win.gpkg", T + "/win.geojson", format="GPKG", dstSRS="EPSG:3857", layerName="w")
    sr = osr.SpatialReference(); sr.ImportFromEPSG(3857)
    dst = gdal.GetDriverByName("MEM").Create("", j1 - j0, i1 - i0, 1, gdal.GDT_Byte)
    dst.SetGeoTransform((wx0, res, 0, wy0, 0, -res))
    dst.SetProjection(sr.ExportToWkt())
    gdal.Rasterize(dst, "/vsimem/win.gpkg", layers=["w"], burnValues=[1])
    vec = dst.ReadAsArray().astype(bool)
    ras = TILE["mask"][i0:i1, j0:j1].astype(bool)
    P(f"   pixels : {ras.size} ; couverts dans l'image={int(ras.sum())} ; couverts d'après les entités (centre du pixel)={int(vec.sum())}")
    P(f"   les deux={int((ras & vec).sum())} ; image seule={int((ras & ~vec).sum())} ; entités seules={int((~ras & vec).sum())} ; aucun={int((~ras & ~vec).sum())} ; accord={100.0 * float((ras == vec).mean()):.1f} %")
    byop = {}
    for f in feats:
        byop[(f.get("properties") or {}).get("COBERTURA")] = byop.get((f.get("properties") or {}).get("COBERTURA"), 0) + 1
    P("   entités de la fenêtre par COBERTURA : " + cj(byop, 500), 600)


# ---------------------------------------------------------------- 7. Aragon
def summarize_csv(body, maxrows=400000):
    for enc in ("utf-8-sig", "latin-1"):
        try:
            text = body.decode(enc)
            break
        except Exception:  # noqa: BLE001
            continue
    first = text.split("\n", 1)[0]
    delim = ";" if first.count(";") > first.count(",") else ","
    rows = list(csv.reader(io.StringIO(text), delimiter=delim))
    if not rows:
        return
    head, data = rows[0], rows[1:maxrows]
    P(f"     {len(rows) - 1} lignes, {len(head)} colonnes, séparateur {delim!r}")
    for i, name in enumerate(head[:30]):
        col = [r[i] for r in data if len(r) > i]
        distinct = sorted(set(col))
        P(f"     colonne {name!r} : {len(distinct)} valeurs distinctes, ex. " + " | ".join(distinct[:5])[:180], 330)


def s_aragon():
    section("7. Aragón Open Data : « Cobertura móvil real por tecnología en Aragón »")
    base = "https://opendata.aragon.es/ckan/api/3/action/"
    r = (jget(base + "package_show?id=cobertura-movil-real-por-tecnologia-en-aragon-junio-2026", quiet=True) or {}).get("result") or {}
    P(f"   titre={r.get('title')!r} | licence={r.get('license_id')} {r.get('license_title')!r} {r.get('license_url')} | créé={str(r.get('metadata_created'))[:10]} modifié={str(r.get('metadata_modified'))[:10]} | org={(r.get('organization') or {}).get('title')!r}", 800)
    wrap(clean(r.get("notes"), 1500), 1500, indent="     ")
    P("     extras : " + cj({e.get("key"): e.get("value") for e in r.get("extras") or []}, 900), 1000)
    csv_url = None
    for res in r.get("resources") or []:
        P(f"     ressource {res.get('name')!r} [{res.get('format')}] taille={res.get('size')} {res.get('url')}", 500)
        if str(res.get("format")).upper() == "CSV" and not csv_url:
            csv_url = res.get("url")
    if csv_url:
        code, ctype, body = fetch(csv_url)
        P(f"   CSV -> {code} {len(body)}o {ctype[:40]}")
        if code == 200:
            try:
                summarize_csv(body)
            except Exception as e:  # noqa: BLE001
                P(f"     résumé impossible : {e!r} ; début : {body[:300]!r}")
    r = (jget(base + "package_show?id=conectividad-y-territorio", quiet=True) or {}).get("result") or {}
    P(f"   autre jeu : {r.get('title')!r} | licence={r.get('license_title')!r} | modifié={str(r.get('metadata_modified'))[:10]}")
    P("     " + clean(r.get("notes"), 500), 600)
    P("     ressources : " + " ; ".join(f"{x.get('name')} [{x.get('format')}]" for x in (r.get("resources") or [])[:14]), 900)


# ---------------------------------------------------------------- 8. Catalogne
def s_catalunya():
    section("8. Catalunya : « Cobertura mòbil 112 » (4tqz-ha5q) et mesures de l'application (g9ma-vbt8)")
    base = "https://analisi.transparenciacatalunya.cat"
    for vid in ("4tqz-ha5q", "g9ma-vbt8"):
        v = jget(f"{base}/api/views/{vid}.json", quiet=True) or {}
        lic, md = v.get("license") or {}, v.get("metadata") or {}
        P(f"   {vid} : name={v.get('name')!r} | assetType={v.get('assetType')} viewType={v.get('viewType')} | attribution={v.get('attribution')!r} {v.get('attributionLink')} | licenseId={v.get('licenseId')} licence={lic.get('name')!r} {lic.get('termsLink')}", 900)
        P(f"     créé={day((v.get('createdAt') or 0) * 1000)} | données mises à jour={day((v.get('rowsUpdatedAt') or 0) * 1000)} | vue modifiée={day((v.get('viewLastModified') or 0) * 1000)}")
        wrap(clean(v.get("description"), 1100), 1100, indent="     ")
        P("     custom_fields=" + cj(md.get("custom_fields"), 1300), 1400)
        P("     accessPoints=" + cj(md.get("accessPoints"), 500) + " | additionalAccessPoints=" + cj(md.get("additionalAccessPoints"), 700), 1300)
        cols = v.get("columns") or []
        if cols:
            P("     colonnes : " + " ; ".join(f"{c.get('fieldName')}({c.get('dataTypeName')})" for c in cols), 1300)
        links = sorted(set(re.findall(r"https?://[^\s\"'<>\\)]+", json.dumps(md) + " " + str(v.get("description")))))
        for u in links[:5]:
            code, ctype, _ = fetch(u, method="HEAD")
            P(f"     lien -> {code} {ctype[:60]} {u}", 500)
    j = jget(f"{base}/resource/g9ma-vbt8.json?$select=count(*)", quiet=True)
    P("   g9ma-vbt8 : nombre de lignes = " + cj(j, 120))
    j = jget(f"{base}/resource/g9ma-vbt8.json?$limit=1", quiet=True)
    P("   g9ma-vbt8 : une ligne = " + cj(j, 800), 900)


# ---------------------------------------------------------------- 9. Navarre, Euskadi, datos.gob.es
def lv(v, lang="es"):
    if isinstance(v, list):
        for x in v:
            if isinstance(x, dict) and x.get("_lang") == lang:
                return x.get("_value")
        x = v[0] if v else None
        return x.get("_value") if isinstance(x, dict) else x
    if isinstance(v, dict):
        return v.get("_value") or v.get("value")
    return v


def s_autres():
    section("9. Navarra, Euskadi et catalogue national : recherches complémentaires")
    base = "https://datos.gob.es/apidata/catalog/dataset"
    j = jget(base + "/a15002917-plan-director-de-banda-ancha-velocidades-de-banda-ancha1.json", quiet=True)
    for ds in (((j or {}).get("result") or {}).get("items") or [])[:1]:
        P(f"   Navarra, « {lv(ds.get('title'))} » : modified={str(ds.get('modified'))[:16]} licence={ds.get('license')}")
        P("     " + str(clean(lv(ds.get("description")), 600)), 700)
        dists = ds.get("distribution") or []
        for x in (dists if isinstance(dists, list) else [dists])[:4]:
            P(f"     distribution : {lv(x.get('title'))!r} {x.get('accessURL')}", 400)
    for q in ("banda ancha", "movil", "cobertura"):
        res = (jget("https://datosabiertos.navarra.es/api/3/action/package_search?rows=12&q=" + quote(q), quiet=True) or {}).get("result") or {}
        P(f"   Navarra CKAN « {q} » : {res.get('count')} résultat(s) : " + " ; ".join(repr(p.get("title")) for p in (res.get("results") or [])[:12]), 900)
    RX2 = re.compile(r"cobertura|antena|estaci[oó]n(es)? base|\b[345]G\b|LTE|se[ñn]al m|estaldura|banda zabal", re.I)
    seen, shown = set(), 0
    for term, maxpages in (("móvil", 6), ("movil", 3), ("telefonía", 4), ("4G", 2), ("LTE", 1), ("estaldura", 1), ("mugikor", 2), ("telecomunicaciones", 4)):
        total = 0
        for page in range(maxpages):
            j = jget(f"{base}/title/{quote(term)}.json?_pageSize=50&_page={page}", quiet=True)
            items = ((j or {}).get("result") or {}).get("items") or []
            total += len(items)
            for ds in items:
                about = ds.get("_about", "")
                titles = ds.get("title")
                text = " ".join(str(x.get("_value") if isinstance(x, dict) else x) for x in (titles if isinstance(titles, list) else [titles]))
                if about in seen or not RX2.search(text):
                    continue
                seen.add(about)
                shown += 1
                if shown <= 24:
                    P(f"     [{term}] {str(lv(titles))[:110]!r} | {about.rsplit('/', 1)[-1][:90]}", 330)
            if len(items) < 50:
                break
        P(f"   datos.gob.es, titre contenant « {term} » : {total} jeux parcourus")


for fn in (s_terms, s_popups, s_org, s_feature, s_image, s_coherence, s_aragon, s_catalunya, s_autres):
    try:
        fn()
    except Exception:  # noqa: BLE001
        P("ECHEC de la section : " + traceback.format_exc()[-900:])
P("")
P(f"FIN python ({NREQ} requêtes)")
PY

autour() { # autour <fichier texte ou html> <regex> [rayon] [max] : extraits autour des occurrences
  python3 - "$1" "$2" "${3:-300}" "${4:-5}" <<'PY'
import re, sys, html
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
if "<html" in s[:3000].lower() or "<!doctype" in s[:200].lower():
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
echo "##### 10. Méthodologie du rapport de couverture 2025 (PDF du ministère)"
get "$T/metodo.pdf" "https://conectemos.digital.gob.es/content/dam/seteleco-portal-connect/resources/pdf/icba2025/Metodolog%C3%ADa_Informe_Cobertura-BA-2025.pdf"
if pdftotext -layout "$T/metodo.pdf" "$T/metodo.txt" 2>/dev/null; then
  echo "   pages : $(pdfinfo "$T/metodo.pdf" 2>/dev/null | grep -E '^Pages' | tr -s ' ')"
  autour "$T/metodo.txt" "cuadr[ií]cula" 420 4 | cut -c1-1000
  autour "$T/metodo.txt" "dBm|RSRP|nivel de se[ñn]al|umbral" 380 3 | cut -c1-900
else
  echo "   pdftotext en échec"; head -c 200 "$T/metodo.pdf" | tr -c '[:print:]' ' '; echo
fi

echo
echo "##### 11. datos.gob.es : demande de données « conectividad móvil y antenas »"
get "$T/sol.html" "https://datos.gob.es/es/solicitud-de-datos/datos-en-abierto-de-conectividad-movil-y-antenas"
autour "$T/sol.html" "conectividad m[oó]vil y antenas" 700 2 | cut -c1-1700
autour "$T/sol.html" "Propiedad Intelectual|por operador|separad" 500 3 | cut -c1-1200
echo "FIN"
