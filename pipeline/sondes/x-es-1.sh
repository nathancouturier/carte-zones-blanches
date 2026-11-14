#!/usr/bin/env bash
# Sonde Espagne 1 : exploration de la carte « Mapa de Servicios de Banda Ancha Móvil 2024 » du ministère
# par l'API REST publique d'ArcGIS (élément, configuration, cartes web, services), puis recherche
# d'alternatives ouvertes (datos.gob.es et catalogues régionaux). Quelques dizaines de petites requêtes JSON.
set -u
. "$(dirname "$0")/_lib.sh"
export UA
python3 - <<'PY'
import html, json, os, re, sys, time, traceback, urllib.error, urllib.parse, urllib.request

UA = os.environ.get("UA") or "carte-zones-blanches-sonde/1.0"
NREQ = 0
BBOX = (-3.5, 39.8, 3.4, 43.5)      # emprise utile, lon/lat
PT = (0.66, 42.63)                   # point d'essai : haute vallée de Benasque (Aragon)
SHARING = "https://www.arcgis.com/sharing/rest"
ROOT = "ef9f55c81f304e5185fcdd7cecf98e7f"


def P(s="", n=420):
    for line in str(s).split("\n"):
        print(line[:n] + (" …" if len(line) > n else ""), flush=True)


def fetch(url, timeout=120):
    global NREQ
    NREQ += 1
    time.sleep(0.3)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.headers.get("Content-Type", ""), r.read(40_000_000)
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
    if not quiet or j is None or (isinstance(j, dict) and "error" in j) or code != 200:
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


def walk(o, path=""):
    if isinstance(o, dict):
        for k, v in o.items():
            yield from walk(v, path + "/" + str(k))
    elif isinstance(o, list):
        for i, v in enumerate(o):
            yield from walk(v, f"{path}[{i}]")
    else:
        yield path, o


SEEN_ITEMS = {}


def show_item(itemid, label=""):
    if itemid in SEEN_ITEMS:
        return SEEN_ITEMS[itemid]
    j = jget(f"{SHARING}/content/items/{itemid}?f=json")
    SEEN_ITEMS[itemid] = j
    if not isinstance(j, dict):
        return None
    P(f"   ELEMENT {itemid} {label}")
    P(f"     title={j.get('title')!r} | type={j.get('type')} | owner={j.get('owner')} | orgId={j.get('orgId')} | access={j.get('access')}")
    P(f"     created={day(j.get('created'))} | modified={day(j.get('modified'))} | size={j.get('size')} | numViews={j.get('numViews')} | url={j.get('url')}")
    P("     typeKeywords: " + ", ".join(j.get("typeKeywords") or []) + " | tags: " + ", ".join(j.get("tags") or []), 420)
    if j.get("snippet"):
        P(f"     snippet: {clean(j.get('snippet'), 350)}")
    if j.get("description"):
        P(f"     description: {clean(j.get('description'), 1100)}", 1200)
    P(f"     licenseInfo: {clean(j.get('licenseInfo'), 1800)}", 1900)
    P(f"     accessInformation: {clean(j.get('accessInformation'), 300)} | extent={j.get('extent')} | sr={j.get('spatialReference')}")
    return j


def renderer_summary(r, indent="       "):
    if not isinstance(r, dict):
        return
    t = r.get("type")
    if t == "uniqueValue":
        P(f"{indent}rendu uniqueValue field1={r.get('field1')} field2={r.get('field2')} expr={clean(r.get('valueExpression'), 160)}")
        for u in (r.get("uniqueValueInfos") or [])[:14]:
            P(f"{indent}  valeur={u.get('value')!r} libellé={u.get('label')!r} couleur={(u.get('symbol') or {}).get('color')}")
    elif t == "classBreaks":
        P(f"{indent}rendu classBreaks field={r.get('field')} min={r.get('minValue')}")
        for c in (r.get("classBreakInfos") or [])[:14]:
            P(f"{indent}  max={c.get('classMaxValue')} libellé={c.get('label')!r} couleur={(c.get('symbol') or {}).get('color')}")
    else:
        P(f"{indent}rendu {t} libellé={r.get('label')!r} couleur={((r.get('symbol') or {}).get('color'))} " + cj({k: v for k, v in r.items() if k not in ('symbol', 'type', 'label')}, 200))


def png_colors(body):
    try:
        import numpy as np
        from osgeo import gdal
        gdal.UseExceptions()
        path = f"/vsimem/t_{NREQ}"
        gdal.FileFromMemBuffer(path, body)
        ds = gdal.Open(path)
        a = ds.ReadAsArray()
        desc = f"{ds.GetDriver().ShortName} {ds.RasterXSize}x{ds.RasterYSize} bandes={ds.RasterCount}"
        if ds.RasterCount == 1:
            ct = ds.GetRasterBand(1).GetColorTable()
            vals, counts = np.unique(a, return_counts=True)
            items = []
            for v, c in sorted(zip(vals.tolist(), counts.tolist()), key=lambda x: -x[1])[:8]:
                items.append(f"{ct.GetColorEntry(int(v)) if ct else v}:{c}")
            desc += f" valeurs_distinctes={len(vals)}"
        else:
            flat = a.reshape(a.shape[0], -1).T
            vals, counts = np.unique(flat, axis=0, return_counts=True)
            order = np.argsort(-counts)[:8]
            items = [f"{tuple(int(x) for x in vals[i])}:{int(counts[i])}" for i in order]
            desc += f" couleurs_distinctes={len(vals)}"
        ds = None
        gdal.Unlink(path)
        return desc + " | " + " ".join(items)
    except Exception as e:  # noqa: BLE001
        return f"décodage impossible : {e!r}"


def to_sr(lon, lat, wkid):
    from osgeo import osr
    wkid = {102100: 3857, 102113: 3857, 900913: 3857}.get(int(wkid), int(wkid))
    s = osr.SpatialReference(); s.ImportFromEPSG(4326); s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    t = osr.SpatialReference(); t.ImportFromEPSG(wkid); t.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    x, y, _ = osr.CoordinateTransformation(s, t).TransformPoint(lon, lat)
    return x, y


def tile_probe(url, j):
    ti = j.get("tileInfo") or {}
    lods = ti.get("lods") or []
    if not lods:
        return
    sr = ti.get("spatialReference") or j.get("spatialReference") or {}
    wkid = sr.get("latestWkid") or sr.get("wkid")
    P(f"     tuiles : {ti.get('cols')}x{ti.get('rows')} px, format={ti.get('format')}, dpi={ti.get('dpi')}, origine={ti.get('origin')}, sr={sr}")
    P("     niveaux (niveau:résolution) : " + " ".join(f"{l.get('level')}:{l.get('resolution'):.4f}" for l in lods), 900)
    minlod, maxlod = j.get("minLOD"), j.get("maxLOD")
    P(f"     minLOD={minlod} maxLOD={maxlod} minScale={j.get('minScale')} maxScale={j.get('maxScale')} exportTilesAllowed={j.get('exportTilesAllowed')} maxExportTilesCount={j.get('maxExportTilesCount')}")
    try:
        x, y = to_sr(PT[0], PT[1], wkid)
    except Exception as e:  # noqa: BLE001
        P(f"     projection du point d'essai impossible : {e!r}")
        return
    usable = [l for l in lods if (minlod is None or l["level"] >= minlod) and (maxlod is None or l["level"] <= maxlod)] or lods
    near12 = min(usable, key=lambda l: abs(l["resolution"] - 38.21851414))
    chosen = {near12["level"]: near12, usable[-1]["level"]: usable[-1], usable[len(usable) // 2]["level"]: usable[len(usable) // 2]}
    ext = ".pbf" if "VectorTileServer" in url else ""
    for level, l in sorted(chosen.items()):
        col = int((x - ti["origin"]["x"]) // (l["resolution"] * ti.get("cols", 256)))
        row = int((ti["origin"]["y"] - y) // (l["resolution"] * ti.get("rows", 256)))
        turl = f"{url.rstrip('/')}/tile/{level}/{row}/{col}{ext}"
        code, ctype, body = fetch(turl)
        extra = png_colors(body) if code == 200 and not ext and body[:4] in (b"\x89PNG", b"\xff\xd8\xff\xe0", b"\xff\xd8\xff\xe1", b"RIFF") else body[:120]
        P(f"     tuile niveau {level} (rés {l['resolution']:.2f}) -> {code} {len(body)}o {ctype[:25]} {turl}", 600)
        P(f"       {extra}", 700)


SEEN_SERVICES = {}


def show_service(url, deep=True):
    url = url.split("?")[0].rstrip("/")
    if url in SEEN_SERVICES:
        return SEEN_SERVICES[url]
    j = jget(url + "?f=json")
    SEEN_SERVICES[url] = j
    if not isinstance(j, dict):
        return None
    P("     clés : " + ", ".join(sorted(j.keys())), 900)
    simple = ("currentVersion", "name", "type", "geometryType", "mapName", "serviceDescription", "description", "copyrightText",
              "capabilities", "supportedQueryFormats", "supportedImageFormatTypes", "supportedExportFormats", "maxRecordCount",
              "standardMaxRecordCount", "tileMaxRecordCount", "maxRecordCountFactor", "singleFusedMapCache", "serviceItemId",
              "hasStaticData", "pixelSizeX", "pixelSizeY", "bandCount", "pixelType", "serviceDataType", "maxImageHeight",
              "maxImageWidth", "cacheType", "units", "displayField", "objectIdField", "syncEnabled", "tiles", "defaultStyles",
              "supportsDynamicLayers", "hasRasterAttributeTable", "allowRasterFunction", "exportTilesAllowed", "minScale", "maxScale")
    parts = [f"{k}={clean(j[k], 260)}" for k in simple if k in j and j[k] not in (None, "", [])]
    for i in range(0, len(parts), 4):
        P("     " + " | ".join(parts[i:i + 4]), 900)
    for k in ("spatialReference", "extent", "fullExtent"):
        if k in j:
            P(f"     {k}={cj(j[k], 260)}")
    for k in ("editingInfo", "documentInfo", "advancedQueryCapabilities"):
        if k in j:
            v = j[k]
            if k == "editingInfo" and isinstance(v, dict):
                v = {kk: day(vv) for kk, vv in v.items()}
            P(f"     {k}={cj(v, 520)}", 560)
    for L in (j.get("layers") or [])[:25]:
        P(f"     couche {L.get('id')}: {L.get('name')!r} type={L.get('type')} geom={L.get('geometryType')} minScale={L.get('minScale')} maxScale={L.get('maxScale')} sous-couches={L.get('subLayerIds')}")
    for L in (j.get("tables") or [])[:10]:
        P(f"     table {L.get('id')}: {L.get('name')!r}")
    if j.get("fields"):
        fl = [f"{f.get('name')}({str(f.get('type')).replace('esriFieldType', '')}{', ' + str(f.get('alias')) if f.get('alias') and f.get('alias') != f.get('name') else ''})" for f in j["fields"]]
        for i in range(0, len(fl), 6):
            P("     champs : " + " ; ".join(fl[i:i + 6]), 700)
        for f in j["fields"]:
            dom = f.get("domain")
            if isinstance(dom, dict):
                P(f"     domaine {f.get('name')} : {dom.get('type')} " + cj(dom.get("codedValues") or dom.get("range"), 400))
    if isinstance(j.get("drawingInfo"), dict):
        renderer_summary(j["drawingInfo"].get("renderer"), "     ")
    if j.get("tileInfo"):
        try:
            tile_probe(url, j)
        except Exception:  # noqa: BLE001
            P("     essai de tuile en échec : " + traceback.format_exc()[-300:].replace("\n", " "))
    if deep and j.get("type") in ("Feature Layer", "Table") and "Query" in str(j.get("capabilities", "")):
        try:
            feature_probe(url, j)
        except Exception:  # noqa: BLE001
            P("     essai de requête en échec : " + traceback.format_exc()[-300:].replace("\n", " "))
    return j


def feature_probe(url, j):
    q = url + "/query?"
    env = urllib.parse.quote(",".join(str(v) for v in BBOX))
    base_env = f"geometry={env}&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects"
    r = jget(q + "where=1%3D1&returnCountOnly=true&f=json", quiet=True)
    P(f"     nombre total d'entités : {r.get('count') if r else '?'}")
    r = jget(q + "where=1%3D1&" + base_env + "&returnCountOnly=true&f=json", quiet=True)
    P(f"     nombre d'entités dans l'emprise utile {BBOX} : {r.get('count') if r else '?'}")
    small = urllib.parse.quote(f"{PT[0] - 0.02},{PT[1] - 0.02},{PT[0] + 0.02},{PT[1] + 0.02}")
    code, ctype, body = fetch(q + f"where=1%3D1&geometry={small}&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects"
                              "&outFields=*&returnGeometry=true&outSR=4326&geometryPrecision=5&resultRecordCount=2&f=json")
    P(f"     échantillon (2 entités près de {PT}) -> {code} {len(body)}o")
    try:
        s = json.loads(body.decode("utf-8", "replace"))
        if "error" in s:
            P("       ERREUR : " + cj(s["error"], 300))
        P(f"       exceededTransferLimit={s.get('exceededTransferLimit')} geometryType={s.get('geometryType')} sr={s.get('spatialReference')}")
        for f in (s.get("features") or [])[:2]:
            g = f.get("geometry") or {}
            pts = [p for ring in (g.get("rings") or g.get("paths") or []) for p in ring]
            if pts:
                xs, ys = [p[0] for p in pts], [p[1] for p in pts]
                gs = f"{len(g.get('rings') or g.get('paths') or [])} anneau(x), {len(pts)} sommets, bbox=({min(xs):.5f},{min(ys):.5f},{max(xs):.5f},{max(ys):.5f})"
            else:
                gs = cj(g, 160)
            P(f"       attributs={cj(f.get('attributes'), 520)}", 620)
            P(f"       géométrie : {gs}")
    except Exception as e:  # noqa: BLE001
        P(f"       illisible : {e!r}")
    rend = (j.get("drawingInfo") or {}).get("renderer") or {}
    field = rend.get("field1") or rend.get("field")
    oid = j.get("objectIdField") or "OBJECTID"
    if field:
        stats = urllib.parse.quote(json.dumps([{"statisticType": "count", "onStatisticField": oid, "outStatisticFieldName": "n"}]))
        r = jget(q + f"where=1%3D1&outStatistics={stats}&groupByFieldsForStatistics={urllib.parse.quote(field)}&f=json", quiet=True)
        if r:
            P(f"     répartition par {field} : " + cj([f.get("attributes") for f in (r.get("features") or [])[:20]], 600), 700)


def collect_layers(lst, out, depth=0):
    for L in lst or []:
        ld = L.get("layerDefinition") or {}
        P("     " + "  " * depth + f"- [{L.get('layerType')}] {L.get('title')!r} visible={L.get('visibility')} opacité={L.get('opacity')} itemId={L.get('itemId')}")
        if L.get("url") or L.get("styleUrl"):
            P("     " + "  " * depth + f"  url={L.get('url') or L.get('styleUrl')}", 600)
        if ld.get("definitionExpression"):
            P("     " + "  " * depth + f"  filtre={ld['definitionExpression'][:200]}")
        if ld.get("minScale") or ld.get("maxScale"):
            P("     " + "  " * depth + f"  minScale={ld.get('minScale')} maxScale={ld.get('maxScale')}")
        if isinstance(ld.get("drawingInfo"), dict) and ld["drawingInfo"].get("renderer"):
            renderer_summary(ld["drawingInfo"]["renderer"], "     " + "  " * depth + "  ")
        if L.get("featureCollection"):
            P("     " + "  " * depth + "  (featureCollection embarquée)")
        if L.get("url"):
            out.append(L)
        collect_layers(L.get("layers"), out, depth + 1)


def section(title):
    P("")
    P("##### " + title)


def main_arcgis():
    section("A1. Élément de l'expérience")
    it = show_item(ROOT, "(expérience)")
    if it:
        if it.get("orgId"):
            o = jget(f"{SHARING}/portals/{it['orgId']}?f=json", quiet=True)
            if o:
                P(f"   ORGANISATION {it['orgId']} : name={o.get('name')!r} urlKey={o.get('urlKey')} | description={clean(o.get('description'), 300)}")
        if it.get("owner"):
            u = jget(f"{SHARING}/community/users/{urllib.parse.quote(it['owner'])}?f=json", quiet=True)
            if u:
                P(f"   UTILISATEUR {it['owner']} : fullName={u.get('fullName')!r} orgId={u.get('orgId')} description={clean(u.get('description'), 200)}")
    section("A2. Configuration de l'expérience (data)")
    d = jget(f"{SHARING}/content/items/{ROOT}/data?f=json")
    item_ids, urls = [], []
    if isinstance(d, dict):
        P("   clés : " + ", ".join(sorted(d.keys())), 500)
        for k, v in (d.get("dataSources") or {}).items():
            P(f"   SOURCE {k} | {v.get('type')} | {v.get('sourceLabel') or v.get('label')!r} | itemId={v.get('itemId')} | url={v.get('url')} | portal={v.get('portalUrl')}", 600)
            if v.get("itemId"):
                item_ids.append((v["itemId"], v.get("type")))
            for ck, cv in list((v.get("childDataSourceJsons") or {}).items())[:12]:
                P(f"      enfant {ck} | {cv.get('type')} | {cv.get('sourceLabel') or cv.get('label')!r} | url={cv.get('url')} | itemId={cv.get('itemId')}", 600)
        for k, w in list((d.get("widgets") or {}).items())[:40]:
            uds = w.get("useDataSources")
            P(f"   WIDGET {k} | {w.get('uri')} | {w.get('label')!r}" + (f" | sources={cj([u.get('dataSourceId') for u in uds], 160)}" if uds else ""), 400)
        for k, pg in list((d.get("pages") or {}).items())[:12]:
            P(f"   PAGE {k} | {pg.get('label')!r}")
        seen_txt = 0
        for path, v in walk(d):
            if isinstance(v, str):
                for m in re.findall(r"https?://[^\s\"'<>\\)]+", v):
                    if m not in urls and not re.search(r"\.(png|jpg|jpeg|svg|gif|css|js|woff2?)(\?|$)", m, re.I):
                        urls.append(m)
                txt = clean(v, 900)
                if seen_txt < 14 and len(txt or "") > 90 and re.search(r"cobertura|operador|fuente|reutiliz|licen|condicion|cuadr[ií]cula|datos|4G|5G|Mbps|descarg", txt, re.I) and not txt.startswith("http"):
                    seen_txt += 1
                    P(f"   TEXTE {path[-70:]} : {txt}", 1000)
        P("   URL citées dans la configuration :")
        for u in urls[:40]:
            P("     " + u, 300)
    section("A3. Cartes web et couches")
    layers = []
    for iid, typ in item_ids[:6]:
        show_item(iid, f"({typ})")
        wd = jget(f"{SHARING}/content/items/{iid}/data?f=json")
        if isinstance(wd, dict):
            if wd.get("operationalLayers") is not None:
                P("   couches opérationnelles :")
                collect_layers(wd.get("operationalLayers"), layers)
                bm = wd.get("baseMap") or {}
                P("   fond : " + repr(bm.get("title")) + " | " + " ; ".join(str(L.get("layerType")) + " " + str(L.get("url") or L.get("styleUrl") or L.get("itemId")) for L in (bm.get("baseMapLayers") or [])), 500)
                for tb in (wd.get("tables") or [])[:6]:
                    P(f"   table : {tb.get('title')!r} url={tb.get('url')}")
            else:
                P("   clés des données : " + ", ".join(sorted(wd.keys())), 400)
    section("A4. Services référencés")
    done_roots = set()
    budget = 12
    for L in layers:
        url = (L.get("url") or "").split("?")[0].rstrip("/")
        if not url or url in SEEN_SERVICES:
            continue
        if budget <= 0:
            P(f"   (non exploré, budget atteint) {L.get('title')!r} {url}")
            continue
        budget -= 1
        P(f"   SERVICE de la couche {L.get('title')!r} [{L.get('layerType')}]")
        j = show_service(url)
        m = re.match(r"^(.*/(?:FeatureServer|MapServer))/\d+$", url)
        if m and m.group(1) not in done_roots:
            done_roots.add(m.group(1))
            P("   racine du service :")
            show_service(m.group(1), deep=False)
        sid = L.get("itemId") or (j or {}).get("serviceItemId")
        if sid and sid not in SEEN_ITEMS:
            show_item(sid, "(élément de la couche)")


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


RX = re.compile(r"m[oó]vil|mòbil|mugikor|banda ancha|banda ampla|banda zabal|\b[345]G\b|LTE|telefon|telecom", re.I)


def dist_list(ds):
    dists = ds.get("distribution") or []
    if isinstance(dists, dict):
        dists = [dists]
    out = []
    for x in dists:
        if isinstance(x, dict):
            fmt = x.get("format")
            fmt = (fmt.get("value") if isinstance(fmt, dict) else fmt) or ""
            out.append((str(fmt).split("/")[-1], x.get("accessURL"), lv(x.get("title")), x.get("byteSize")))
    return out


def main_datos():
    section("B1. datos.gob.es : jeu historique du ministère")
    base = "https://datos.gob.es/apidata/catalog/dataset"
    j = jget(base + "/e05251701-base-de-datos-historica-desde-2013-a2020-de-cobertura-banda-ancha-fija-y-movil.json")
    try:
        for ds in j["result"]["items"]:
            P(f"   titre={lv(ds.get('title'))!r} | issued={ds.get('issued')} | modified={ds.get('modified')} | licence={ds.get('license')} | publisher={ds.get('publisher')}", 600)
            P(f"   description={clean(lv(ds.get('description')), 400)}")
            P(f"   spatial={cj(ds.get('spatial'), 200)} | keyword={cj(ds.get('keyword'), 300)}", 600)
            for fmt, url, title, size in dist_list(ds)[:12]:
                P(f"     distribution [{fmt}] {title!r} taille={size} {url}", 500)
    except Exception as e:  # noqa: BLE001
        P(f"   illisible : {e!r}")
    section("B2. datos.gob.es : recherche par titre (catalogue national, qui fédère les catalogues régionaux)")
    seen = set()
    for term, maxpages in (("cobertura", 8), ("banda ancha", 4), ("banda ampla", 1), ("telefonía móvil", 2), ("telefonia mòbil", 1), ("antenas", 2)):
        total = 0
        for page in range(maxpages):
            j = jget(f"{base}/title/{urllib.parse.quote(term)}.json?_pageSize=50&_page={page}", quiet=True)
            items = ((j or {}).get("result") or {}).get("items") or []
            total += len(items)
            for ds in items:
                about = ds.get("_about", "")
                titles = ds.get("title")
                text = " ".join(str(x.get("_value") if isinstance(x, dict) else x) for x in (titles if isinstance(titles, list) else [titles]))
                if about in seen or not RX.search(text):
                    continue
                seen.add(about)
                fmts = sorted({f for f, *_ in dist_list(ds)})
                P(f"   [{term}] {lv(titles)!r} | modified={str(ds.get('modified'))[:10]} | formats={','.join(fmts)[:80]} | {about}", 520)
            if len(items) < 50:
                break
        P(f"   terme « {term} » : {total} jeux parcourus")


def main_regions():
    section("C1. Aragón Open Data (CKAN)")
    for q in ("cobertura", "telefonia movil"):
        j = jget("https://opendata.aragon.es/ckan/api/3/action/package_search?rows=40&q=" + urllib.parse.quote(q))
        res = ((j or {}).get("result") or {})
        P(f"   « {q} » : {res.get('count')} résultat(s)")
        for p in (res.get("results") or []):
            if RX.search((p.get("title") or "") + " " + (p.get("notes") or "")[:400]):
                P(f"     {p.get('title')!r} | org={(p.get('organization') or {}).get('title')} | licence={p.get('license_title')} | modifié={str(p.get('metadata_modified'))[:10]} | formats={sorted({str(r.get('format')) for r in p.get('resources') or []})} | name={p.get('name')}", 520)
    section("C2. Catalunya : dades obertes (Socrata)")
    for q in ("cobertura mòbil", "cobertura"):
        j = jget("https://analisi.transparenciacatalunya.cat/api/catalog/v1?limit=40&q=" + urllib.parse.quote(q))
        if not j:
            j = jget("https://api.eu.socrata.com/api/catalog/v1?domains=analisi.transparenciacatalunya.cat&limit=40&q=" + urllib.parse.quote(q))
        res = (j or {}).get("results") or []
        P(f"   « {q} » : {(j or {}).get('resultSetSize')} résultat(s)")
        for r in res:
            rs = r.get("resource") or {}
            if RX.search((rs.get("name") or "") + " " + (rs.get("description") or "")[:400]):
                P(f"     {rs.get('name')!r} | id={rs.get('id')} | type={rs.get('type')} | maj={str(rs.get('data_updated_at') or rs.get('updatedAt'))[:10]} | licence={(r.get('metadata') or {}).get('license')} | {r.get('permalink')}", 520)
                P(f"       {clean(rs.get('description'), 300)}")
    section("C3. Navarra : datos abiertos (CKAN)")
    for q in ("cobertura", "telefonia movil"):
        j = jget("https://datosabiertos.navarra.es/api/3/action/package_search?rows=40&q=" + urllib.parse.quote(q))
        res = ((j or {}).get("result") or {})
        P(f"   « {q} » : {res.get('count')} résultat(s)")
        for p in (res.get("results") or []):
            if RX.search((p.get("title") or "") + " " + (p.get("notes") or "")[:400]):
                P(f"     {p.get('title')!r} | org={(p.get('organization') or {}).get('title')} | licence={p.get('license_title')} | modifié={str(p.get('metadata_modified'))[:10]} | formats={sorted({str(r.get('format')) for r in p.get('resources') or []})} | name={p.get('name')}", 520)


for fn in (main_arcgis, main_datos, main_regions):
    try:
        fn()
    except Exception:  # noqa: BLE001
        P("ECHEC de la section : " + traceback.format_exc()[-900:])
P("")
P(f"FIN ({NREQ} requêtes)")
PY
