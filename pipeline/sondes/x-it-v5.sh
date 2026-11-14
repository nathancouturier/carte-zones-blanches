#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Italie : AGCOM », sonde it-v5.
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

# Sonde it-v5 : anciennes couches mobiles (2G, 3G, zones non desservies) de l'organisation ArcGIS Online de l'AGCOM :
# existent-elles en données interrogeables, de quand datent-elles, sous quelles conditions ?
# Charge : descriptions JSON et quelques lignes d'attributs. Aucune tuile, aucune géométrie.

ORG = "yx6R8yH6bZXTjlyg"
AGOL = "https://www.arcgis.com/sharing/rest"
TILES = "https://tiles.arcgis.com/tiles/%s/arcgis/rest/services" % ORG
PTS = [("centre d'Aoste", 7.3206, 45.7370), ("lac Majeur, en pleine eau", 8.565, 45.905), ("coeur du Val Grande (Cossogno)", 8.43, 46.045), ("haute vallée du Gesso (Entracque)", 7.37, 44.15)]


def day(ms):
    return time.strftime("%Y-%m-%d", time.gmtime((ms or 0) / 1000))


def section_fiches():
    P("##### 1. Fiches publiques de l'organisation ArcGIS Online de l'AGCOM : zones non desservies, 2G, 3G, Infratel")
    seen = {}
    for q in ('orgid:%s AND (infratel OR Simulazioni OR "non servite" OR "due operatori" OR scoperture)' % ORG,
              'orgid:%s AND (Mappatura OR "Copertura_Mobile" OR 2G OR 3G)' % ORG):
        d = get_json(AGOL + "/search?" + urllib.parse.urlencode(dict(q=q, num=40, f="json", sortField="modified", sortOrder="desc"))) or {}
        P("  recherche « %s » : %s résultats" % (q.split(" AND ", 1)[1][:90], d.get("total")))
        for it in d.get("results", []):
            seen.setdefault(it.get("id"), it)
    items = sorted(seen.values(), key=lambda it: -(it.get("modified") or 0))
    for it in items[:26]:
        extra = "; ".join("%s=%s" % (k, flat(to_text(str(it.get(k) or "")))[:70]) for k in ("snippet", "description", "licenseInfo", "accessInformation") if it.get(k))
        P("  [%s, créée %s] %s | %s | %s | %s" % (day(it.get("modified")), day(it.get("created")), it.get("title"), it.get("type"), it.get("id"), (it.get("url") or "")[:120]))
        if extra:
            P("       " + extra[:270])
    return items


def describe_feature_service(it):
    url = (it.get("url") or "").split("?")[0]
    P("  -- %s : %s" % (it.get("title"), url))
    d = get_json(url + "?f=json")
    if not d or "error" in d:
        P("     erreur ou réponse vide : %s" % str((d or {}).get("error"))[:160])
        return
    P("     capabilities=%s maxRecordCount=%s formats=%s copyrightText=%r description=%r SCR=%s" % (
        d.get("capabilities"), d.get("maxRecordCount"), d.get("supportedQueryFormats"), d.get("copyrightText"), flat(to_text(d.get("serviceDescription") or d.get("description") or ""))[:80],
        (d.get("spatialReference") or {}).get("latestWkid")))
    layers = [(l.get("id"), l.get("name")) for l in (d.get("layers") or [])]
    P("     couches : %s | tables : %s" % (layers[:10], [(t.get("id"), t.get("name")) for t in (d.get("tables") or [])][:5]))
    for lid, name in layers[:3]:
        base = "%s/%s" % (url, lid)
        lay = get_json(base + "?f=json") or {}
        P("     couche %s « %s » : %s, champs %s" % (lid, name, lay.get("geometryType"), [(f.get("name"), (f.get("type") or "").replace("esriFieldType", ""), f.get("alias")) for f in lay.get("fields") or []][:14]))
        P("        description=%r copyright=%r dernière modification=%s étendue=%s" % (
            flat(to_text(lay.get("description") or ""))[:90], lay.get("copyrightText"), day((lay.get("editingInfo") or {}).get("lastEditDate")),
            json.dumps({k: round(v) for k, v in (lay.get("extent") or {}).items() if isinstance(v, (int, float))})))
        rend = (lay.get("drawingInfo") or {}).get("renderer") or {}
        P("        rendu %s sur %s : %s" % (rend.get("type"), rend.get("field1") or rend.get("field"), [u.get("label") for u in rend.get("uniqueValueInfos", [])][:8] or (rend.get("label") or "")))
        cnt = query(base, where="1=1", returnCountOnly="true") or {}
        smp = query(base, where="1=1", outFields="*", returnGeometry="false", resultRecordCount=2) or {}
        P("        %s entités ; exemples : %s" % (cnt.get("count"), json.dumps([f.get("attributes") for f in smp.get("features", [])][:2], ensure_ascii=False)[:250]))
        if lay.get("geometryType") == "esriGeometryPolygon" and re.search(r"(?i)scopert|infratel", "%s %s" % (it.get("title"), name)):
            for label, lon, lat in PTS:
                r = query(base, geometry="%.5f,%.5f" % (lon, lat), geometryType="esriGeometryPoint", inSR=4326, spatialRel="esriSpatialRelIntersects", outFields="*", returnGeometry="false", resultRecordCount=3) or {}
                P("        point %-34s : %s" % (label, json.dumps([f.get("attributes") for f in r.get("features", [])][:1], ensure_ascii=False)[:200] if r.get("features") else ("aucune entité" if "error" not in r else "erreur %s" % str(r["error"])[:100])))


def section_services(items):
    P("##### 2. Services d'entités publics liés aux zones non desservies (Infratel 2021, simulations 5G)")
    for it in items:
        if it.get("type") == "Feature Service" and re.search(r"(?i)infratel|scopert|simulazion", it.get("title") or ""):
            describe_feature_service(it)
    P("##### 3. Cartes web de 2019 sur la couverture 2G et 3G : couches affichées")
    n = 0
    for it in items:
        if it.get("type") == "Web Map" and re.search(r"(?i)2G|non servite|scopert|desi2020", it.get("title") or "") and n < 3:
            n += 1
            data = get_json("%s/content/items/%s/data?f=json" % (AGOL, it.get("id"))) or {}
            ops = data.get("operationalLayers") or []
            P("  -- « %s » (%s) : %d couches" % (it.get("title"), day(it.get("modified")), len(ops)))
            for l in ops[:9]:
                P("       « %s » %s %s" % ((l.get("title") or "")[:90], l.get("layerType"), (l.get("url") or "").split("?")[0].split("/rest/services/")[-1][:100]))
    P("##### 4. Services de tuiles 2G de 2016-2017 (description seule)")
    for name in ("Mappatura_2G_cov_l15_161215_170227b", "Copertura_Mobile_2G_1701", "Mobile_4GLTE_EoY_2022"):
        d = get_json("%s/%s/MapServer?f=json" % (TILES, name))
        if not d or "error" in d:
            P("  %s : erreur %s" % (name, str((d or {}).get("error"))[:140]))
            continue
        ti = d.get("tileInfo") or {}
        lods = [l.get("level") for l in ti.get("lods", [])]
        P("  %s : capabilities=%s exportTilesAllowed=%s niveaux %s à %s ; couches %s ; description=%r ; copyright=%r" % (
            name, d.get("capabilities"), d.get("exportTilesAllowed"), min(lods) if lods else None, max(lods) if lods else None,
            [(l.get("id"), l.get("name")) for l in d.get("layers", [])][:5], flat(to_text(d.get("serviceDescription") or d.get("description") or ""))[:100], d.get("copyrightText")))


def main():
    items = []
    try:
        items = section_fiches() or []
    except Exception as e:
        import traceback
        P("  [ERREUR section_fiches : %r] %s" % (e, flat(traceback.format_exc())[-400:]))
    try:
        section_services(items)
    except Exception as e:
        import traceback
        P("  [ERREUR section_services : %r] %s" % (e, flat(traceback.format_exc())[-400:]))
    bilan()


if __name__ == "__main__":
    main()
PY_FIN_SONDE
echo "FIN (code python : $?)"
