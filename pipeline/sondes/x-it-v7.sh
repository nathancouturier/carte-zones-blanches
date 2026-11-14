#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Italie : AGCOM », sonde it-v7.
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

# Sonde it-v7 : la boucle de pagination de la recette, rejouée sur les trois régions SANS géométrie
# (attributs seulement), puis comparaison avec la liste des communes publiée par l'AGCOM :
# une commune entièrement absente de la couche 4G serait une fausse zone blanche.

GEO3 = "https://geo3.agcom.it"
REST = GEO3 + "/MapET-SFS/rest/services"
Q = REST + "/Grid100/mobile_4G/MapServer/0"
LIM = REST + "/Limiti/limiti_2026/MapServer/0"
WHERE = "COD_REG IN (1,2,7)"


def keyset(layer, where, fields, page):
    """Pagination par fid croissant, comme dans la recette, mais sans géométrie."""
    last, rows, n, sizes = 0, [], 0, []
    while n < 40:
        d = query(layer, where="(%s) AND fid > %d" % (where, last), outFields=fields, returnGeometry="false", orderByFields="fid", resultRecordCount=page) or {}
        feats = [f["attributes"] for f in d.get("features", [])]
        n += 1
        sizes.append(len(feats))
        if not feats:
            break
        rows += feats
        last = max(a["fid"] for a in feats)
        if len(feats) < page:
            break
    return rows, n, sizes


def main():
    P("##### 1. Boucle de la recette sans géométrie : COD_REG IN (1,2,7), pages de 250 par fid croissant")
    expected = (query(Q, where=WHERE, returnCountOnly="true") or {}).get("count")
    rows, n, sizes = keyset(Q, WHERE, "fid,n_infrastrutture_totali,COD_REG,PRO_COM_T", 250)
    fids = [a["fid"] for a in rows]
    P("  attendu (returnCountOnly) : %s ; lu : %d lignes en %d requêtes ; %d fid distincts ; tailles des pages : %s" % (expected, len(rows), n, len(set(fids)), sizes))
    P("  fid croissants d'une page à l'autre : %s ; fid minimal %s, maximal %s" % (fids == sorted(fids), min(fids or [0]), max(fids or [0])))
    by_reg = collections.defaultdict(list)
    for a in rows:
        by_reg[int(a["COD_REG"])].append(a)
    pairs = collections.Counter((a["PRO_COM_T"], a["n_infrastrutture_totali"]) for a in rows)
    P("  couples (commune, valeur) : %d distincts pour %d lignes ; doublons : %d" % (len(pairs), len(rows), sum(1 for v in pairs.values() if v > 1)))
    com4g = {}
    for reg in sorted(by_reg):
        r = by_reg[reg]
        coms = set(a["PRO_COM_T"] for a in r)
        com4g[reg] = coms
        vals = collections.Counter(a["n_infrastrutture_totali"] for a in r)
        P("  COD_REG %d : %d entités, par valeur %s, %d communes distinctes, préfixes de province %s" % (reg, len(r), dict(sorted(vals.items())), len(coms), sorted(set(c[:3] for c in coms))))

    P("##### 2. Communes publiées par l'AGCOM (Limiti/limiti_2026, couche 0) comparées aux communes présentes dans la couche 4G")
    lrows, ln, lsizes = keyset(LIM, WHERE, "fid,PRO_COM_T,COD_REG,COMUNE", 1000)
    P("  limites : %d communes lues en %d requêtes (pages %s) ; attendu %s" % (len(lrows), ln, lsizes, (query(LIM, where=WHERE, returnCountOnly="true") or {}).get("count")))
    lim = collections.defaultdict(dict)
    for a in lrows:
        lim[int(a["COD_REG"])][a["PRO_COM_T"]] = a.get("COMUNE")
    for reg in sorted(lim):
        missing = sorted(set(lim[reg]) - com4g.get(reg, set()))
        extra = sorted(com4g.get(reg, set()) - set(lim[reg]))
        P("  COD_REG %d : %d communes dans les limites, %d dans la couche 4G ; sans aucun polygone 4G : %d %s ; dans la couche 4G mais pas dans les limites : %d %s" % (
            reg, len(lim[reg]), len(com4g.get(reg, set())), len(missing), [(c, lim[reg][c]) for c in missing][:8], len(extra), extra[:8]))
    # communes des deux points sans polygone relevés par la sonde it-v2
    for code in ("103023", "004084"):
        vals = sorted(a["n_infrastrutture_totali"] for a in rows if a["PRO_COM_T"] == code)
        name = next((lim[r][code] for r in lim if code in lim[r]), None)
        P("  commune %s (%s) : valeurs présentes dans la couche 4G %s" % (code, name, vals))
    bilan()


if __name__ == "__main__":
    main()
PY_FIN_SONDE
echo "FIN (code python : $?)"
