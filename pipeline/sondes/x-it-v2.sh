#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Italie : AGCOM », sonde it-v2.
# Client générique : aucun identifiant personnel dans les requêtes vers des services tiers.
UA="sonde-verification/1.0"
export UA T
python3 - <<'PY_FIN_SONDE'
# Fonctions communes aux sondes de contre-vérification « Italie : AGCOM ».
# Ce fichier est recopié en tête de chaque sonde (voir assembler.sh) : il n'est pas importé.
import collections, difflib, gzip, html, json, os, re, sys, time
import urllib.error, urllib.parse, urllib.request, urllib.robotparser

UA = os.environ.get("UA", "sonde-verification/1.0")
T = os.environ.get("T", "/tmp/sonde")
os.makedirs(T, exist_ok=True)
REQ = collections.Counter()
OCTETS = collections.Counter()
LAST = {}
ROBOTS = {}
PAUSE = 0.7


def P(s=""):
    for line in str(s).split("\n"):
        print(line[:300])
    sys.stdout.flush()


def mask(s):
    """Masque tout ce qui ressemble à une clé ou à un jeton avant affichage."""
    s = re.sub(r"(?i)((?:api[_-]?key|apikey|token|secret|password|pwd)[\"']?\s*[:=]\s*[\"']?)[^\"'&\s,;)]+", r"\1<masque>", s)
    return re.sub(r"[A-Za-z0-9_\-]{30,}", "<masque>", s)


def fetch(url, data=None, timeout=120, tries=2):
    """Requête HTTP polie : une pause entre deux requêtes vers le même hôte, pas de nouvel essai sur une erreur HTTP."""
    host = urllib.parse.urlsplit(url).netloc
    wait = PAUSE - (time.time() - LAST.get(host, 0))
    if wait > 0:
        time.sleep(wait)
    err = None
    for _ in range(tries):
        req = urllib.request.Request(url, data=data, headers={"User-Agent": UA, "Accept-Encoding": "gzip"})
        REQ[host] += 1
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                body = r.read()
                if (r.headers.get("Content-Encoding") or "").lower() == "gzip":
                    body = gzip.decompress(body)
                LAST[host] = time.time()
                OCTETS[host] += len(body)
                return r.status, dict(r.headers), body, r.geturl()
        except urllib.error.HTTPError as e:
            body = e.read() or b""
            try:
                if (e.headers.get("Content-Encoding") or "").lower() == "gzip":
                    body = gzip.decompress(body)
            except Exception:
                pass
            LAST[host] = time.time()
            OCTETS[host] += len(body)
            return e.code, dict(e.headers or {}), body, e.geturl()
        except Exception as e:  # réseau, délai
            err = e
            LAST[host] = time.time()
            time.sleep(3)
    return 0, {}, repr(err).encode(), url


def robots_for(host):
    """Lit robots.txt une fois par hôte. Sans fichier robots valable : rien n'est déclaré, tout est permis."""
    if host in ROBOTS:
        return ROBOTS[host]
    st, hd, body, _ = fetch("https://%s/robots.txt" % host, timeout=40)
    txt = body.decode("utf-8", "replace")
    ok = st == 200 and "<html" not in txt[:600].lower() and re.search(r"(?im)^\s*(user-agent|disallow|allow|sitemap)\s*:", txt) is not None
    rp = urllib.robotparser.RobotFileParser()
    rp.parse(txt.splitlines() if ok else [])
    ROBOTS[host] = (rp, st, ok, txt, hd.get("Content-Type", ""))
    return ROBOTS[host]


def allowed(url):
    return robots_for(urllib.parse.urlsplit(url).netloc)[0].can_fetch(UA, url)


def get(url, quiet=False, **kw):
    """Requête soumise à robots.txt. Renvoie (code, en-têtes, corps, url finale) ou None si robots.txt l'interdit."""
    if not allowed(url):
        P("  [SAUT : interdit par robots.txt] %s" % url[:240])
        return None
    st, hd, body, final = fetch(url, **kw)
    if not quiet:
        extra = "" if final == url else " final=%s" % final[:120]
        P("  -> %s %so %s %s%s" % (st, len(body), (hd.get("Content-Type") or "")[:40], url[:200], extra))
    return st, hd, body, final


def get_json(url, **kw):
    r = get(url, quiet=True, **kw)
    if r is None:
        return None
    st, hd, body, _ = r
    try:
        return json.loads(body.decode("utf-8", "replace"))
    except Exception:
        P("  [réponse non JSON, code %s] %s : %s" % (st, url[:160], body[:160].decode("utf-8", "replace").replace("\n", " ")))
        return None


def query(layer_url, **params):
    params.setdefault("f", "json")
    return get_json(layer_url + "/query?" + urllib.parse.urlencode(params))


def to_text(s):
    s = re.sub(r"(?is)<(script|style|svg|noscript)\b.*?</\1>", " ", s)
    s = re.sub(r"(?i)<br\s*/?>|</(p|div|li|tr|h[1-6]|td|th)>", "\n", s)
    s = html.unescape(re.sub(r"<[^>]+>", " ", s))
    s = re.sub(r"[ \t\r\f\v\xa0]+", " ", s)
    return re.sub(r"\n\s*\n+", "\n", s).strip()


def flat(s):
    return re.sub(r"\s+", " ", s).strip()


def wrap(s, width=285, indent="    ", limit=6000):
    s = flat(s)[:limit]
    for i in range(0, len(s), width):
        P(indent + s[i:i + width])


def norm(s):
    return re.sub(r"[^a-z0-9àèéìòù]+", " ", html.unescape(s).lower()).strip()


def js_literal(src, pos):
    """Lit un littéral de chaîne JavaScript (et ses concaténations par +) à partir de pos. Renvoie (texte, fin)."""
    out, n = [], len(src)
    while True:
        while pos < n and src[pos] in " \t\r\n":
            pos += 1
        if pos >= n or src[pos] not in "'\"`":
            break
        quote = src[pos]
        pos += 1
        buf = []
        while pos < n and src[pos] != quote:
            c = src[pos]
            if c == "\\" and pos + 1 < n:
                d = src[pos + 1]
                if d == "u" and re.match(r"[0-9a-fA-F]{4}", src[pos + 2:pos + 6] or ""):
                    buf.append(chr(int(src[pos + 2:pos + 6], 16)))
                    pos += 6
                    continue
                buf.append({"n": "\n", "t": "\t", "r": "", "\n": ""}.get(d, d))
                pos += 2
            else:
                buf.append(c)
                pos += 1
        pos += 1
        out.append("".join(buf))
        k = pos
        while k < n and src[k] in " \t\r\n":
            k += 1
        if k < n and src[k] == "+":
            pos = k + 1
            continue
        break
    return "".join(out), pos


def js_block(src, brace):
    """Renvoie le bloc { ... } qui commence à l'indice brace, en sautant chaînes et commentaires."""
    n, depth, i = len(src), 0, brace
    while i < n:
        c = src[i]
        if c in "'\"`":
            _, i = js_literal(src, i)
            continue
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i)
            i = n if j < 0 else j + 2
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return src[brace:i + 1]
        i += 1
    return src[brace:]


def find_def(src, name):
    """Indice de l'accolade ouvrante de la définition de la fonction name, ou None."""
    for m in re.finditer(r"(?<![\w$.])%s\b" % re.escape(name), src):
        tail = src[m.end():m.end() + 300]
        mm = re.match(r"\s*(?:[:=]\s*(?:async\s+)?function\s*[\w$]*\s*)?\(([^)]*)\)\s*(?:=>\s*)?\{", tail)
        if mm:
            return m.end() + mm.end() - 1
    return None


def bilan():
    P("##### Bilan des requêtes de cette sonde (client : %s)" % UA)
    for host in sorted(REQ):
        P("  %-28s %3d requêtes, %8.1f ko reçus" % (host, REQ[host], OCTETS[host] / 1000.0))

# Sonde it-v2 : schéma de la couche, petit échantillon de géométries, requêtes ponctuelles, second serveur,
# portail ArcGIS, carte principale, catalogue national. Charge : petites réponses JSON, une poignée d'entités.
import math

GEO3 = "https://geo3.agcom.it"
REST = GEO3 + "/MapET-SFS/rest/services"
L4G = REST + "/Grid100/mobile_4G/MapServer"
Q = L4G + "/0"
GEO = "https://geo.agcom.it"
REST2 = GEO + "/server/rest/services"
OPER = re.compile(r"(?i)(?<![a-z0-9])(2g|3g|gsm|umts|hspa|voce|voice|tim|telecom|vodafone|wind|windtre|iliad|fastweb|operator\w*)(?![a-z0-9])")


def rings_of(feature):
    return (feature.get("geometry") or {}).get("rings") or []


def ring_area(ring):
    s = 0.0
    for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
        s += x1 * y2 - x2 * y1
    return s / 2.0


def ring_stats(rings):
    """Statistiques sur des anneaux en mètres : restes modulo 100 des sommets, arêtes alignées sur les axes, surface."""
    mods, n_edges, axis, mult = collections.Counter(), 0, 0, 0
    signed = 0.0
    for ring in rings:
        signed += ring_area(ring)
        for x, y in ring[:-1]:
            mods[(round(x % 100.0, 1) % 100.0, round(y % 100.0, 1) % 100.0)] += 1
        for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
            dx, dy = abs(x2 - x1), abs(y2 - y1)
            n_edges += 1
            if dx < 0.01 or dy < 0.01:
                axis += 1
                length = max(dx, dy)
                if abs(length / 100.0 - round(length / 100.0)) < 1e-3 and length > 1:
                    mult += 1
    nv = sum(len(r) - 1 for r in rings)
    return {"anneaux": len(rings), "sommets": nv, "aretes": n_edges, "alignees": axis, "multiples_de_100m": mult,
            "surface_km2": round(abs(signed) / 1e6, 4), "restes": mods.most_common(3)}


def section_schema():
    P("##### 1. Schéma de la couche 4G (MapServer/layers), réponse de MapServer/0, noms de colonnes des statistiques")
    r = get(L4G + "/0?f=json", quiet=True)
    if r:
        P("  MapServer/0?f=json : code %s, %d octets, début %r" % (r[0], len(r[2]), r[2][:60]))
    d = get_json(L4G + "/layers?f=json") or {}
    for lay in d.get("layers", [])[:2]:
        for k in ("id", "name", "type", "geometryType", "description", "copyrightText", "capabilities", "maxRecordCount", "displayField", "supportedQueryFormats", "extent"):
            P("  couche %s: %s" % (k, json.dumps(lay.get(k), ensure_ascii=False)[:240]))
        P("  couche champs: %s" % [(f.get("name"), (f.get("type") or "").replace("esriFieldType", ""), f.get("alias"), f.get("length")) for f in lay.get("fields", [])])
        P("  couche advancedQueryCapabilities: %s" % json.dumps(lay.get("advancedQueryCapabilities"))[:240])
        rend = (lay.get("drawingInfo") or {}).get("renderer") or {}
        P("  rendu: type=%s champ=%s valeurs=%s" % (rend.get("type"), rend.get("field1"), [(u.get("value"), u.get("label"), (u.get("symbol") or {}).get("color")) for u in rend.get("uniqueValueInfos", [])]))
    stat = json.dumps([{"statisticType": "count", "onStatisticField": "fid", "outStatisticFieldName": "nb"}])
    for group in ("COD_REG,n_infrastrutture_totali", "n_infrastrutture_totali,COD_REG"):
        d = query(Q, where="COD_REG=2", outStatistics=stat, groupByFieldsForStatistics=group) or {}
        P("  groupBy « %s », COD_REG=2 : champs=%s lignes=%s" % (group, [f.get("name") for f in d.get("fields", [])], [f.get("attributes") for f in d.get("features", [])][:4]))
    for leg in ("legend0", "legend1"):
        d = get_json("%s/Legend/%s/MapServer/legend?f=json" % (REST, leg)) or {}
        for l in d.get("layers", [])[:3]:
            P("  Legend/%s couche « %s » : %s" % (leg, l.get("layerName"), [x.get("label") for x in l.get("legend", [])][:12]))


def section_geometrie():
    P("##### 2. Échantillon de géométries : Vallée d'Aoste, entités de valeur 4 puis toutes les entités d'une commune")
    d35 = query(Q, where="COD_REG=2 AND n_infrastrutture_totali=4", outFields="*", returnGeometry="true", outSR=3035, orderByFields="fid") or {}
    feats = d35.get("features", [])
    P("  outSR=3035 : geometryType=%s spatialReference=%s champs=%s" % (d35.get("geometryType"), d35.get("spatialReference"),
                                                                    [(f.get("name"), (f.get("type") or "").replace("esriFieldType", "")) for f in d35.get("fields", [])]))
    for f in feats:
        P("    %s -> %s" % (f.get("attributes"), ring_stats(rings_of(f))))
    if feats:
        ring = max(rings_of(feats[0]), key=len)
        P("    premiers sommets du plus grand anneau (EPSG:3035) : %s" % [[round(c, 3) for c in p] for p in ring[:5]])
    dnat = query(Q, where="COD_REG=2 AND n_infrastrutture_totali=4", outFields="fid", returnGeometry="true", orderByFields="fid") or {}
    P("  sans outSR : spatialReference=%s" % dnat.get("spatialReference"))
    try:
        from osgeo import gdal, ogr, osr
        gdal.UseExceptions()
        gdal.PushErrorHandler("CPLQuietErrorHandler")
        s = osr.SpatialReference(); s.ImportFromEPSG(3857); s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
        t = osr.SpatialReference(); t.ImportFromEPSG(3035); t.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
        ct = osr.CoordinateTransformation(s, t)
        worst, n = 0.0, 0
        for fa, fb in zip(dnat.get("features", []), feats):
            for ra, rb in zip(rings_of(fa), rings_of(fb)):
                if len(ra) != len(rb):
                    continue
                for (xa, ya), (xb, yb) in zip(ra, rb):
                    x, y, _ = ct.TransformPoint(xa, ya)
                    worst = max(worst, math.hypot(x - xb, y - yb))
                    n += 1
        P("  reprojection locale (PROJ) de la réponse native vers EPSG:3035, comparée à la réponse outSR=3035 : %d sommets, écart maximal %.4f m" % (n, worst))
        if dnat.get("features"):
            rings = [[list(ct.TransformPoint(x, y)[:2]) for x, y in ring] for ring in rings_of(dnat["features"][0])]
            P("    mêmes statistiques après reprojection locale : %s" % ring_stats(rings))
    except Exception as e:
        P("  [reprojection locale impossible : %r]" % e)
    if not feats:
        return
    com = feats[0]["attributes"].get("PRO_COM_T")
    url = Q + "/query?" + urllib.parse.urlencode(dict(where="PRO_COM_T='%s'" % com, outFields="fid,n_infrastrutture_totali,COD_REG,PRO_COM_T", returnGeometry="true", outSR=3035, orderByFields="fid", f="json"))
    r = get(url)
    if not r or r[0] != 200:
        return
    path = os.path.join(T, "commune.json")
    open(path, "wb").write(r[2])
    dc = json.loads(r[2].decode("utf-8", "replace"))
    tot = 0.0
    for f in dc.get("features", []):
        st = ring_stats(rings_of(f))
        tot += st["surface_km2"]
        P("    commune %s : %s -> %s" % (com, f.get("attributes"), st))
    try:
        from osgeo import gdal, ogr
        ds = ogr.Open(path)
        lyr = ds.GetLayer(0)
        srs = lyr.GetSpatialRef()
        P("  lecture OGR de la réponse : pilote %s, type %s, SCR %s:%s, champs %s, %d entités" % (
            ds.GetDriver().GetName(), ogr.GeometryTypeToName(lyr.GetGeomType()), srs.GetAuthorityName(None) if srs else None, srs.GetAuthorityCode(None) if srs else None,
            [(lyr.GetLayerDefn().GetFieldDefn(i).GetName(), lyr.GetLayerDefn().GetFieldDefn(i).GetTypeName()) for i in range(lyr.GetLayerDefn().GetFieldCount())], lyr.GetFeatureCount()))
        geoms = []
        for f in lyr:
            g = f.GetGeometryRef()
            valid = g.IsValid()
            g = g.MakeValid()
            geoms.append((f.GetField("n_infrastrutture_totali"), g, valid))
        P("  validité GEOS avant MakeValid : %s ; surfaces OGR (km2) : %s ; somme des surfaces par anneaux : %.4f km2" % (
            [v for _, _, v in geoms], [(n, round(g.GetArea() / 1e6, 4)) for n, g, _ in geoms], tot))
        for i in range(len(geoms)):
            for j in range(i + 1, len(geoms)):
                inter = geoms[i][1].Intersection(geoms[j][1])
                P("    recouvrement entre valeur %s et valeur %s : %.6f km2" % (geoms[i][0], geoms[j][0], (inter.GetArea() if inter else 0.0) / 1e6))
        union = None
        for _, g, _ in geoms:
            union = g if union is None else union.Union(g)
        P("    surface de l'union : %.4f km2" % (union.GetArea() / 1e6 if union else 0.0))
    except Exception as e:
        P("  [analyse OGR impossible : %r]" % e)


def section_points():
    P("##### 3. Requêtes ponctuelles (coordonnées approximatives choisies à la main, WGS 84) : commune puis valeur 4G")
    limits = REST + "/Limiti/limiti_2026/MapServer/0"
    pts = [("centre d'Aoste", 7.3206, 45.7370), ("lac Majeur, en pleine eau, côté piémontais", 8.565, 45.905), ("lac d'Orta, en pleine eau", 8.395, 45.82), ("coeur du Val Grande", 8.43, 46.045),
           ("haut Valgrisenche", 7.02, 45.50), ("haute vallée du Gesso", 7.37, 44.15), ("mont Aiona, Ligurie", 9.47, 44.47)]
    for name, lon, lat in pts:
        geom = dict(geometry="%.5f,%.5f" % (lon, lat), geometryType="esriGeometryPoint", inSR=4326, spatialRel="esriSpatialRelIntersects", returnGeometry="false", resultRecordCount=5)
        c = query(limits, outFields="COMUNE,PRO_COM_T,COD_REG", **geom) or {}
        v = query(Q, outFields="fid,n_infrastrutture_totali,COD_REG,PRO_COM_T", **geom) or {}
        P("  %-44s (%.4f, %.4f) : commune %s | couverture 4G %s%s" % (
            name, lon, lat, [f.get("attributes") for f in c.get("features", [])][:2] or "aucune",
            [f.get("attributes") for f in v.get("features", [])][:3] or "aucun polygone", "" if "error" not in v else " ERREUR %s" % str(v["error"])[:120]))


def section_second_serveur():
    P("##### 4. Second serveur geo.agcom.it/server : tous les services, service mobile daté")
    root = get_json(REST2 + "?f=json")
    if not root:
        return
    P("  currentVersion=%s dossiers=%s services racine=%s" % (root.get("currentVersion"), root.get("folders"), [s.get("name") for s in root.get("services", [])]))
    names = [(s.get("name"), s.get("type")) for s in root.get("services", [])]
    for folder in root.get("folders", []):
        d = get_json("%s/%s?f=json" % (REST2, urllib.parse.quote(folder))) or {}
        svcs = [(s.get("name"), s.get("type")) for s in d.get("services", [])]
        names += svcs
        P("  %-10s %2d services : %s" % (folder, len(svcs), ", ".join("%s (%s)" % (n.split("/")[-1], t.replace("Server", "")) for n, t in svcs)[:262]))
    P("  %d services ; noms évoquant 2G, 3G, voix ou un opérateur : %s" % (len(names), [n for n, _ in names if OPER.search(n.replace("_", " "))] or "aucun"))
    mob = [(n, t) for n, t in names if re.search(r"(?i)mobile|4g|5g|lte|desi", n)]
    P("  noms évoquant le mobile ou DESI : %s" % mob)
    app = [n for n, t in names if re.search(r"(?i)appmobile", n) and t == "MapServer"]
    for n in app[:2]:
        base = "%s/%s/MapServer" % (REST2, n)
        d = get_json(base + "?f=json") or {}
        P("  %s : serviceDescription=%r description=%r copyrightText=%r capabilities=%s formats=%s maxRecordCount=%s" % (
            n, (d.get("serviceDescription") or "")[:80], (d.get("description") or "")[:80], d.get("copyrightText"), d.get("capabilities"), d.get("supportedQueryFormats"), d.get("maxRecordCount")))
        P("    documentInfo=%s" % json.dumps(d.get("documentInfo"), ensure_ascii=False)[:230])
        ls = get_json(base + "/layers?f=json") or {}
        for lay in ls.get("layers", []):
            P("    couche %s « %s » %s : champs %s ; description=%r ; copyright=%r" % (
                lay.get("id"), lay.get("name"), lay.get("geometryType"), [f.get("name") for f in lay.get("fields") or []], (lay.get("description") or "")[:120], (lay.get("copyrightText") or "")[:80]))
            rend = (lay.get("drawingInfo") or {}).get("renderer") or {}
            if rend.get("uniqueValueInfos"):
                P("      rendu : %s" % [(u.get("value"), u.get("label")) for u in rend.get("uniqueValueInfos", [])])
        for lay in ls.get("layers", []) + ls.get("tables", []):
            if re.search(r"(?i)note", lay.get("name") or ""):
                dd = query("%s/%s" % (base, lay.get("id")), where="1=1", outFields="*", returnGeometry="false") or {}
                P("    couche « note » : %s" % json.dumps([f.get("attributes") for f in dd.get("features", [])][:3], ensure_ascii=False)[:270])
            if (lay.get("name") or "").strip() == "4G":
                lid = "%s/%s" % (base, lay.get("id"))
                P("    couche 4G : total %s ; préfixe 007 : %s ; valeurs hors de 1 à 4 : %s" % (
                    query(lid, where="1=1", returnCountOnly="true"), query(lid, where="pro_com_t LIKE '007%'", returnCountOnly="true"),
                    query(lid, where="n_infrastrutture_totali NOT IN (1,2,3,4) OR n_infrastrutture_totali IS NULL", returnCountOnly="true")))


def section_portail_arcgis():
    P("##### 5. Portail ArcGIS de l'AGCOM (geo.agcom.it/arcgis) : fiches publiques sur le mobile, licence déclarée")
    seen = {}
    for q in ("mobile", "EoY", "4G OR 5G OR LTE OR copertura"):
        d = get_json(GEO + "/arcgis/sharing/rest/search?" + urllib.parse.urlencode(dict(q=q, num=40, f="json", sortField="modified", sortOrder="desc"))) or {}
        P("  recherche « %s » : %s résultats" % (q, d.get("total")))
        for it in d.get("results", []):
            seen.setdefault(it.get("id"), it)
    items = sorted(seen.values(), key=lambda it: -(it.get("modified") or 0))
    shown = 0
    for it in items:
        blob = " ".join(str(it.get(k) or "") for k in ("title", "snippet", "description", "tags", "url"))
        if not re.search(r"(?i)mobil|4g|5g|lte|eoy|2g|3g|copertura", blob) or shown >= 16:
            continue
        shown += 1
        P("  [%s] %s | %s | %s | accès %s | url %s" % (time.strftime("%Y-%m-%d", time.gmtime((it.get("modified") or 0) / 1000)), it.get("title"), it.get("type"), it.get("id"), it.get("access"), (it.get("url") or "")[:110]))
        for k in ("snippet", "description", "licenseInfo", "accessInformation"):
            v = flat(to_text(str(it.get(k) or "")))
            if v:
                P("       %s : %s" % (k, v[:250]))
    P("  %d fiches distinctes lues, %d affichées" % (len(items), shown))
    return items


def section_carte_principale():
    P("##### 6. Carte principale maps.agcom.it (en maintenance ?) : scripts de la page et services qu'ils citent")
    r = get("https://maps.agcom.it/")
    if not r or r[0] != 200:
        return
    page = r[2].decode("utf-8", "replace")
    P("  texte : " + flat(to_text(page))[:230])
    srcs = re.findall(r"(?is)<script\b[^>]*\bsrc=[\"']([^\"']+)[\"']", page)
    own = [s for s in srcs if not re.match(r"(?i)(https?:)?//", s) or "agcom.it" in s]
    P("  %d scripts dont %d du site : %s" % (len(srcs), len(own), ", ".join(own)[:250]))
    texts = [("page", page)]
    skip = re.compile(r"(?i)jquery|bootstrap|leaflet(?!.*agcom)|esri|proj4|popper|fontawesome|chart|d3\.|moment|toastr|select2|datatables|sb-admin|easing")
    for s in [s for s in own if not skip.search(s)][:7]:
        rr = get(urllib.parse.urljoin("https://maps.agcom.it/", s))
        if rr and rr[0] == 200:
            texts.append((s, rr[2].decode("utf-8", "replace")))
    urls = []
    for name, txt in texts:
        for m in re.finditer(r"[\"'`]((?:https?:)?//[^\"'`\s]{6,240}|[^\"'`\s]{0,80}(?:rest/services|\.ashx|/wms|/wfs|geoserver)[^\"'`\s]{0,160})[\"'`]", txt):
            u = m.group(1).split("?")[0]
            if re.search(r"(?i)agcom|rest/services|ashx|wms|wfs|geoserver", u) and u not in urls:
                urls.append(u)
    P("  adresses de services citées (%d) :" % len(urls))
    for u in urls[:30]:
        P("      " + mask(u)[:200])
    for kw in ("2G", "3G", "4G", "5G", "mobile", "Mobile", "operator", "infrastruttur", "manutenzione"):
        P("  « %s » : %s" % (kw, {name[-40:]: len(re.findall(r"(?<![A-Za-z0-9])%s" % re.escape(kw), txt)) for name, txt in texts if re.search(r"(?<![A-Za-z0-9])%s" % re.escape(kw), txt)} or "absent"))
    for kw in ("2G", "3G"):
        n = 0
        for name, txt in texts:
            for m in re.finditer(r"(?<![A-Za-z0-9])%s(?![A-Za-z0-9])" % kw, txt):
                if n >= 3:
                    break
                P("      contexte « %s » (%s) : ...%s" % (kw, name[-30:], mask(flat(to_text(txt[max(0, m.start() - 120):m.start() + 140])))[:230]))
                n += 1
    d = get_json("https://archive.org/wayback/available?url=maps.agcom.it&timestamp=20261001") or {}
    P("  archive la plus proche du 1er octobre 2026 : %s" % json.dumps((d.get("archived_snapshots") or {}).get("closest"))[:230])


def section_catalogue_national():
    P("##### 7. Catalogue national dati.gov.it (API CKAN) : jeux de l'AGCOM sur la couverture mobile ?")
    for q in ("agcom broadband map", "copertura rete mobile 4G", "AGCOM"):
        d = get_json("https://www.dati.gov.it/opendata/api/3/action/package_search?" + urllib.parse.urlencode(dict(q=q, rows=8)))
        res = ((d or {}).get("result") or {})
        P("  recherche « %s » : %s jeux" % (q, res.get("count")))
        for p in res.get("results", [])[:8]:
            P("      %s | %s | %s" % ((p.get("title") or "")[:110], ((p.get("organization") or {}).get("title") or "")[:50], sorted(set((x.get("format") or "").upper() for x in p.get("resources", [])))[:6]))


def section_logo():
    P("##### 8. Conditions : fragment HTML autour du logo (adresse associée au logo)")
    r = get("https://www.agcom.it/termini-e-condizioni")
    if r and r[0] == 200:
        page = r[2].decode("utf-8", "replace")
        k = page.find("seguente logo")
        frag = re.sub(r"\s+(class|data-[\w-]+|loading|rel|target|style|title)=\"[^\"]*\"", "", page[k:k + 1300])
        wrap(frag, limit=900)


def main():
    for fn in (section_schema, section_geometrie, section_points, section_second_serveur, section_portail_arcgis, section_carte_principale, section_catalogue_national, section_logo):
        try:
            fn()
        except Exception as e:
            import traceback
            P("  [ERREUR dans %s : %r] %s" % (fn.__name__, e, flat(traceback.format_exc())[-400:]))
    bilan()


if __name__ == "__main__":
    main()
PY_FIN_SONDE
echo "FIN (code python : $?)"
