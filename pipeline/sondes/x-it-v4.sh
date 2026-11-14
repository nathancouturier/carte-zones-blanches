#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Italie : AGCOM », sonde it-v4.
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

# Sonde it-v4 : libellés officiels de la carte mobile de l'AGCOM (carte web publique) et anciennes couches
# « scoperture » 2G, 3G, 4G de 2019-2020 hébergées dans l'organisation ArcGIS Online de l'AGCOM.
# Charge : quelques descriptions JSON. Aucune tuile, aucune géométrie.

GEO = "https://geo.agcom.it"
SHARING = GEO + "/arcgis/sharing/rest"
ORG = "yx6R8yH6bZXTjlyg"
TILES = "https://tiles.arcgis.com/tiles/%s/arcgis/rest/services" % ORG
MOBRE = re.compile(r"(?i)mobil|scopert|(?<![a-z0-9])(2g|3g|34g|234g|4g|5g|lte|umts|gsm)(?![a-z0-9])")


def walk_layers(layers, depth=0):
    for l in layers or []:
        yield depth, l
        for x in walk_layers(l.get("layers"), depth + 1):
            yield x


def section_cartes():
    P("##### 1. Cartes web « Agcom Mobile » : titres complets des couches, fiches, adresses des services")
    found = []
    for wid, label in (("aecba72e6ad34c9587c0837097657c9d", "Agcom Mobile HD_v10"), ("7eb20e530eb7436089c27d7df01def6a", "Agcom Mobile HD_v8")):
        it = get_json("%s/content/items/%s?f=json" % (SHARING, wid)) or {}
        P("  -- %s : titre=%r type=%s accès=%s créée %s modifiée %s étiquettes=%s" % (
            label, it.get("title"), it.get("type"), it.get("access"), time.strftime("%Y-%m-%d", time.gmtime((it.get("created") or 0) / 1000)),
            time.strftime("%Y-%m-%d", time.gmtime((it.get("modified") or 0) / 1000)), it.get("tags")))
        P("     snippet=%r description=%r licenseInfo=%r accessInformation=%r" % (it.get("snippet"), flat(to_text(it.get("description") or ""))[:120], flat(to_text(it.get("licenseInfo") or ""))[:120], it.get("accessInformation")))
        data = get_json("%s/content/items/%s/data?f=json" % (SHARING, wid)) or {}
        for top in data.get("operationalLayers") or []:
            ttitle = top.get("title") or top.get("name") or ""
            turl = (top.get("url") or "").split("?")[0]
            if not MOBRE.search("%s %s" % (ttitle, turl)) and "AppMobile" not in turl:
                continue
            found.append((ttitle, turl))
            for depth, l in walk_layers([top]):
                title = l.get("title") or l.get("name") or ""
                url = (l.get("url") or "").split("?")[0]
                pop = l.get("popupInfo") or {}
                pad = "   " * depth
                P("     %s[%s] « %s » %s visible=%s" % (pad, l.get("id"), title, l.get("layerType") or "", l.get("visibility")))
                if url:
                    P("     %s    adresse : %s" % (pad, url))
                if pop:
                    P("     %s    fiche : titre=%r champs=%s" % (pad, flat(to_text(pop.get("title") or ""))[:90], [(fi.get("fieldName"), fi.get("label")) for fi in pop.get("fieldInfos", []) if fi.get("visible")][:6]))
                    desc = flat(to_text(pop.get("description") or ""))
                    if desc:
                        P("     %s    texte de la fiche : %s" % (pad, desc[:250]))
                rend = ((l.get("layerDefinition") or {}).get("drawingInfo") or {}).get("renderer") or {}
                if rend.get("uniqueValueInfos"):
                    P("     %s    légende : %s" % (pad, [(u.get("value"), u.get("label")) for u in rend["uniqueValueInfos"]][:8]))
    return found


def describe_tiles(url):
    d = get_json(url + "?f=json")
    if d is None:
        return
    if "error" in d:
        P("  %s : erreur %s" % (url.split("/services/")[-1], str(d["error"])[:160]))
        return
    ti = d.get("tileInfo") or {}
    lods = [l.get("level") for l in ti.get("lods", [])]
    P("  %s : capabilities=%s exportTilesAllowed=%s tuiles %sx%s %s niveaux %s à %s SCR=%s" % (
        url.split("/services/")[-1], d.get("capabilities"), d.get("exportTilesAllowed"), ti.get("rows"), ti.get("cols"), ti.get("format"),
        min(lods) if lods else None, max(lods) if lods else None, (ti.get("spatialReference") or d.get("spatialReference") or {}).get("latestWkid")))
    P("      serviceDescription=%r description=%r copyrightText=%r" % (flat(to_text(d.get("serviceDescription") or ""))[:110], flat(to_text(d.get("description") or ""))[:110], d.get("copyrightText")))
    P("      couches=%s étendue=%s" % ([(l.get("id"), l.get("name")) for l in d.get("layers", [])][:6], json.dumps({k: round(v) for k, v in (d.get("fullExtent") or {}).items() if isinstance(v, (int, float))})))
    P("      documentInfo=%s" % json.dumps(d.get("documentInfo"), ensure_ascii=False)[:230])


def section_tuiles(found):
    P("##### 2. Services de tuiles de l'organisation ArcGIS Online de l'AGCOM cités par ces cartes (description seule, aucune tuile lue)")
    seen = []
    for title, url in found:
        if "tiles.arcgis.com" in url and url not in seen:
            seen.append(url)
            P("  « %s »" % title)
            describe_tiles(url)
    P("##### 3. Répertoire public des services hébergés de l'organisation")
    for base, kind in ((TILES, "tuiles"), ("https://services.arcgis.com/%s/arcgis/rest/services" % ORG, "entités")):
        d = get_json(base + "?f=json")
        if d is None:
            continue
        if "error" in d:
            P("  %s : erreur %s" % (kind, str(d["error"])[:160]))
            continue
        names = [(s.get("name"), s.get("type")) for s in d.get("services", [])]
        mob = [n for n, t in names if MOBRE.search((n or "").replace("_", " "))]
        P("  %s : %d services publics ; noms évoquant le mobile (%d) : %s" % (kind, len(names), len(mob), "; ".join(mob)[:230]))
        if len("; ".join(mob)) > 230:
            wrap("; ".join(mob)[230:], limit=1700, indent="      ")


def section_fiches():
    P("##### 4. Fiches publiques ArcGIS Online de l'organisation (recherche), licence déclarée")
    seen = {}
    for q in ("orgid:%s AND (mobile OR scoperture OR Mobile2020)" % ORG, "orgid:%s AND (4G OR 5G OR LTE OR 2G OR 3G)" % ORG):
        d = get_json("https://www.arcgis.com/sharing/rest/search?" + urllib.parse.urlencode(dict(q=q, num=50, f="json", sortField="modified", sortOrder="desc")))
        if d is None:
            continue
        P("  recherche « %s » : %s résultats" % (q.split(" AND ", 1)[1], d.get("total")))
        for it in d.get("results", []):
            seen.setdefault(it.get("id"), it)
    for it in sorted(seen.values(), key=lambda it: -(it.get("modified") or 0))[:22]:
        P("  [%s] %s | %s | accès %s | %s" % (time.strftime("%Y-%m-%d", time.gmtime((it.get("modified") or 0) / 1000)), it.get("title"), it.get("type"), it.get("access"), (it.get("url") or "").split("/services/")[-1][:90]))
        for k in ("snippet", "description", "licenseInfo", "accessInformation"):
            v = flat(to_text(str(it.get(k) or "")))
            if v:
                P("       %s : %s" % (k, v[:230]))


def main():
    found = []
    try:
        found = section_cartes() or []
    except Exception as e:
        import traceback
        P("  [ERREUR section_cartes : %r] %s" % (e, flat(traceback.format_exc())[-400:]))
    for fn, args in ((section_tuiles, (found,)), (section_fiches, ())):
        try:
            fn(*args)
        except Exception as e:
            import traceback
            P("  [ERREUR dans %s : %r] %s" % (fn.__name__, e, flat(traceback.format_exc())[-400:]))
    bilan()


if __name__ == "__main__":
    main()
PY_FIN_SONDE
echo "FIN (code python : $?)"
