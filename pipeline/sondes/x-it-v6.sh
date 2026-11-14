#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Italie : AGCOM », sonde it-v6.
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

# Sonde it-v6 : texte méthodologique de l'AGCOM sur la cartographie mobile (critère de couverture) et
# conditions déclarées sur les fiches ArcGIS Online des cartes mobiles de 2017. Quelques descriptions JSON seulement.

ORG = "yx6R8yH6bZXTjlyg"
AGOL = "https://www.arcgis.com/sharing/rest"
TILES = "https://tiles.arcgis.com/tiles/%s/arcgis/rest/services" % ORG
TECH = re.compile(r"(?i)mobil|radiomobil|cellular|(?<![a-z0-9])(2g|3g|4g|5g|lte|umts|gsm)(?![a-z0-9])|segnale|dbm|outdoor|indoor|pixel|operator[ei] di rete|numero (di )?reti|scopert")
PERSON = re.compile(r"(?i)@|a cura di|autor[ei]\b|author|dati forniti a|dott\.|ing\.")


def day(ms):
    return time.strftime("%Y-%m-%d", time.gmtime((ms or 0) / 1000))


def strings_of(obj, out):
    """Toutes les chaînes d'un JSON, dans l'ordre."""
    if isinstance(obj, str):
        out.append(obj)
    elif isinstance(obj, dict):
        for v in obj.values():
            strings_of(v, out)
    elif isinstance(obj, list):
        for v in obj:
            strings_of(v, out)


def section_methodes():
    P("##### 1. « Metodologie mappatura della banda larga » (application publique de l'AGCOM) : passages sur le mobile")
    wid = "6cdc107171ae4eb685fbf2cf444a3d01"
    it = get_json("%s/content/items/%s?f=json" % (AGOL, wid)) or {}
    P("  fiche : titre=%r type=%s accès=%s créée %s modifiée %s licenseInfo=%r description=%r" % (
        it.get("title"), it.get("type"), it.get("access"), day(it.get("created")), day(it.get("modified")), flat(to_text(it.get("licenseInfo") or ""))[:120], flat(to_text(it.get("description") or ""))[:120]))
    data = get_json("%s/content/items/%s/data?f=json" % (AGOL, wid))
    if not data:
        return
    raw = []
    strings_of(data, raw)
    blocks, seen = [], set()
    for s in raw:
        if "<" not in s and len(s) < 60:
            continue
        for para in to_text(s).split("\n"):
            para = flat(para)
            if len(para) >= 50 and para not in seen:
                seen.add(para)
                blocks.append(para)
    P("  %d chaînes, %d paragraphes de texte ; %d évoquent le mobile ou le critère de couverture" % (len(raw), len(blocks), sum(1 for b in blocks if TECH.search(b))))
    shown = 0
    for b in blocks:
        if not TECH.search(b) or PERSON.search(b) or shown >= 16:
            continue
        shown += 1
        wrap(b, limit=560, indent="    > " if shown else "    ")
    titles = [flat(to_text(s)) for s in raw if 8 < len(s) < 90 and re.search(r"(?i)mobil|metodolog|mappatura|rete", s) and "<" not in s and "/" not in s]
    P("  titres courts cités : %s" % "; ".join(dict.fromkeys(titles))[:270])


def section_fiches_2017():
    P("##### 2. Cartes mobiles de 2017 dans l'organisation ArcGIS Online de l'AGCOM : conditions déclarées, couches")
    for wid in ("9719164aaa2d410daee12310c4e60f1f", "1124f266646b44a3b5030f1b63b7b4c7"):
        it = get_json("%s/content/items/%s?f=json" % (AGOL, wid)) or {}
        P("  -- %r (%s, accès %s, créée %s, modifiée %s) : %s" % (it.get("title"), it.get("type"), it.get("access"), day(it.get("created")), day(it.get("modified")), it.get("snippet")))
        P("     licenseInfo : %s" % flat(to_text(it.get("licenseInfo") or ""))[:240])
        P("     accessInformation : %s" % flat(str(it.get("accessInformation") or ""))[:240])
        P("     description : %s" % flat(to_text(it.get("description") or ""))[:240])
        data = get_json("%s/content/items/%s/data?f=json" % (AGOL, wid)) or {}
        for l in (data.get("operationalLayers") or [])[:8]:
            pop = l.get("popupInfo") or {}
            P("     « %s » %s %s%s" % ((l.get("title") or "")[:80], l.get("layerType"), (l.get("url") or "").split("?")[0].split("/rest/services/")[-1][:90],
                                    (" | fiche : %s" % flat(to_text(pop.get("title") or ""))[:60]) if pop else ""))
    P("##### 3. Légendes et mentions des services de tuiles 2G (2016 et 2019)")
    for name in ("Mappatura_2G_cov_l15_161215_170227b", "Mobile2020_scoperture_2G_l15"):
        d = get_json("%s/%s/MapServer?f=json" % (TILES, name)) or {}
        P("  %s : copyrightText=%r" % (name, flat(d.get("copyrightText") or "")[:200]))
        P("      description=%r" % flat(to_text(d.get("serviceDescription") or d.get("description") or ""))[:230])
        leg = get_json("%s/%s/MapServer/legend?f=json" % (TILES, name)) or {}
        for l in (leg.get("layers") or [])[:3]:
            P("      légende couche « %s » : %s" % (l.get("layerName"), [x.get("label") for x in l.get("legend", [])][:10]))


def main():
    for fn in (section_methodes, section_fiches_2017):
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
