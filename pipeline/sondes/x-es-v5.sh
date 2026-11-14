#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Espagne : ministère et régions », sonde es-v5.
# Client générique : aucun identifiant du projet ni de personne dans les requêtes vers des services tiers.
UA="sonde-verification/1.0"
export UA T
python3 - <<'PY_FIN_SONDE'
# Fonctions communes aux sondes de contre-vérification « Espagne : ministère et régions ».
# Ce fichier est recopié en tête de chaque sonde (voir assembler.sh) : il n'est pas importé.
import collections, gzip, html, json, os, re, sys, time, traceback
import urllib.error, urllib.parse, urllib.request, urllib.robotparser

UA = os.environ.get("UA", "sonde-verification/1.0")
T = os.environ.get("T", "/tmp/sonde")
os.makedirs(T, exist_ok=True)
REQ = collections.Counter()
OCTETS = collections.Counter()
LAST = {}
ROBOTS = {}
PAUSE = 0.6


def P(s="", n=300):
    for line in str(s).split("\n"):
        print(line[:n])
    sys.stdout.flush()


def sans_courriel(s):
    """Retire les adresses électroniques avant affichage (pas de données de personnes dans les logs)."""
    return re.sub(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+", "<courriel retiré>", s)


def fetch(url, data=None, timeout=150, tries=2, headers=None):
    """Requête HTTP polie : pause entre deux requêtes vers le même hôte, pas de nouvel essai sur une erreur HTTP."""
    host = urllib.parse.urlsplit(url).netloc
    wait = PAUSE - (time.time() - LAST.get(host, 0))
    if wait > 0:
        time.sleep(wait)
    err = None
    hd = {"User-Agent": UA, "Accept-Encoding": "gzip"}
    hd.update(headers or {})
    for _ in range(tries):
        req = urllib.request.Request(url, data=data, headers=hd)
        REQ[host] += 1
        t0 = time.time()
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read()
                body = raw
                if (r.headers.get("Content-Encoding") or "").lower() == "gzip":
                    body = gzip.decompress(raw)
                LAST[host] = time.time()
                OCTETS[host] += len(raw)
                h = dict(r.headers)
                h["_recu"] = len(raw)
                h["_duree"] = round(time.time() - t0, 1)
                return r.status, h, body, r.geturl()
        except urllib.error.HTTPError as e:
            body = e.read() or b""
            try:
                if (e.headers.get("Content-Encoding") or "").lower() == "gzip":
                    body = gzip.decompress(body)
            except Exception:
                pass
            LAST[host] = time.time()
            h = dict(e.headers or {})
            h["_recu"] = len(body)
            h["_duree"] = round(time.time() - t0, 1)
            return e.code, h, body, e.geturl()
        except Exception as e:  # réseau, délai dépassé
            err = e
            LAST[host] = time.time()
            time.sleep(3)
    return 0, {"_recu": 0, "_duree": 0}, repr(err).encode(), url


def robots_de(host):
    """Lit robots.txt une fois par hôte. Sans fichier robots valable, rien n'est déclaré : tout est permis."""
    if host in ROBOTS:
        return ROBOTS[host]
    st, hd, body, _ = fetch("https://%s/robots.txt" % host, timeout=40)
    txt = body.decode("utf-8", "replace")
    ok = st == 200 and "<html" not in txt[:600].lower() and re.search(r"(?im)^\s*(user-agent|disallow|allow|sitemap)\s*:", txt) is not None
    rp = urllib.robotparser.RobotFileParser()
    rp.parse(txt.splitlines() if ok else [])
    ROBOTS[host] = (rp, st, ok, txt)
    return ROBOTS[host]


def permis(url):
    return robots_de(urllib.parse.urlsplit(url).netloc)[0].can_fetch(UA, url)


def get(url, quiet=False, **kw):
    """Requête soumise à robots.txt : une adresse interdite aux robots n'est pas demandée (code -1)."""
    if not permis(url):
        P("  [SAUT : interdit par robots.txt] %s" % url[:230])
        return -1, {"_recu": 0, "_duree": 0}, b"", url
    st, hd, body, final = fetch(url, **kw)
    if not quiet:
        extra = "" if final == url else " (final : %s)" % final[:140]
        P("  -> %s %so %s en %ss  %s%s" % (st, len(body), (hd.get("Content-Type") or "")[:38], hd.get("_duree"), url[:230], extra))
    return st, hd, body, final


def get_json(url, quiet=True, **kw):
    st, hd, body, _ = get(url, quiet=quiet, **kw)
    if st == -1:
        return None
    try:
        d = json.loads(body.decode("utf-8", "replace"))
    except Exception:
        P("  [réponse non JSON, code %s] %s : %s" % (st, url[:170], body[:160].decode("utf-8", "replace").replace("\n", " ")))
        return None
    if isinstance(d, dict) and "error" in d and len(d) == 1:
        P("  [erreur de l'API] %s : %s" % (url[:200], json.dumps(d["error"], ensure_ascii=False)[:230]))
    return d


def query(layer_url, quiet=True, **params):
    params.setdefault("f", "json")
    return get_json(layer_url + "/query?" + urllib.parse.urlencode(params), quiet=quiet)


def to_text(s):
    s = re.sub(r"(?is)<(script|style|svg|noscript)\b.*?</\1>", " ", s)
    s = re.sub(r"(?i)<br\s*/?>|</(p|div|li|tr|h[1-6]|td|th)>", "\n", s)
    s = html.unescape(re.sub(r"<[^>]+>", " ", s))
    s = re.sub(r"[ \t\r\f\v\xa0]+", " ", s)
    return re.sub(r"\n\s*\n+", "\n", s).strip()


def plat(s):
    """Texte sur une seule ligne, espaces compactés."""
    return re.sub(r"\s+", " ", s).strip()


def jour(ms):
    try:
        return time.strftime("%Y-%m-%d", time.gmtime(int(ms) / 1000))
    except Exception:
        return str(ms)


def bloc(titre, fn):
    P("")
    P("##### " + titre)
    try:
        fn()
    except Exception as e:
        tb = traceback.extract_tb(sys.exc_info()[2])[-1]
        P("  [ECHEC DU BLOC] %s : %s (ligne %s)" % (type(e).__name__, str(e)[:240], tb.lineno))


def bilan():
    P("")
    P("##### Bilan des requêtes")
    for h in sorted(REQ):
        P("  %-46s %3d requêtes, %9d octets reçus" % (h, REQ[h], OCTETS[h]))
    P("  total : %d requêtes" % sum(REQ.values()))


# Identifiant fiscal d'une personne morale espagnole (CIF) : une lettre de société, 7 chiffres, un caractère de contrôle.
CIF_MORALE = re.compile(r"^[ABCDEFGHJNPQRSUVW]\d{7}[0-9A-J]$")


def cif_affichable(s):
    """N'affiche que les identifiants de personnes morales ; tout autre identifiant est masqué."""
    s = (s or "").strip()
    return s if CIF_MORALE.match(s) else ("<identifiant masqué, %d caractères>" % len(s) if s else "")

# Sonde es-v5 : le compte ArcGIS du ministère possède un site Hub (« HubConectemos ») et une page Hub « Aviso Legal ».
# Que dit cette page ? Le site Hub propose-t-il la couche 4G au téléchargement, avec une licence ?
SHARING = "https://www.arcgis.com/sharing/rest"
HUB_SITE = "5e292c4175544a5f89bfe5cee6641506"       # trouvé par la recherche de la sonde es-v4
HUB_AVISO = "457e0fa87a924ad08d7385d295b5ad19"      # idem
FS_ITEM = "84599189a281451c8ac61bc4901459d1"        # service d'entités 4G lié par le ministère
EXP = "ef9f55c81f304e5185fcdd7cecf98e7f"
ETAT = {"groupes": []}


def proprietaire(o):
    return o if (o or "").startswith("coberturaBA") else "<compte tiers masqué>"


def chaines(o, acc):
    if isinstance(o, str):
        acc.append(o)
    elif isinstance(o, dict):
        for v in o.values():
            chaines(v, acc)
    elif isinstance(o, list):
        for v in o:
            chaines(v, acc)


def element(i):
    d = get_json("%s/content/items/%s?f=json" % (SHARING, i)) or {}
    P("  ELEMENT %s : title=%r type=%s owner=%s access=%s créé %s modifié %s url=%s" % (
        i, d.get("title"), d.get("type"), proprietaire(d.get("owner")), d.get("access"), jour(d.get("created")), jour(d.get("modified")), d.get("url")), 420)
    P("     licenseInfo=%r | snippet=%r | description=%r | typeKeywords=%s" % (
        d.get("licenseInfo"), (d.get("snippet") or "")[:120], sans_courriel(plat(to_text(d.get("description") or "")))[:200], [k for k in d.get("typeKeywords") or [] if re.search(r"(?i)hub|open|source-", k)][:8]), 600)
    return d


def texte_des_cartes(d, mini=40):
    acc = []
    chaines(d, acc)
    morceaux = []
    for a in acc:
        if len(a) >= mini and ("<" in a or " " in a) and not a.startswith("data:") and not re.match(r"^https?://\S+$", a):
            t = plat(to_text(a))
            if len(t) >= mini and t not in morceaux:
                morceaux.append(t)
    liens = []
    for a in acc:
        for m in re.finditer(r"https?://[^\s\"'<>\\)]+", a):
            u = m.group(0)
            if u not in liens and not re.search(r"\.(png|jpg|jpeg|svg|gif|woff2?|css|js)(\?|$)|w3\.org|fonts\.g", u):
                liens.append(u)
    return morceaux, liens


def A():
    d = element(HUB_SITE)
    dd = get_json("%s/content/items/%s/data?f=json" % (SHARING, HUB_SITE)) or {}
    v = dd.get("values") or {}
    P("  clés : %s ; values : %s" % (sorted(dd.keys()), sorted(v.keys())[:40]), 700)
    P("  title=%r subdomain=%r defaultHostname=%r customHostname=%r internalUrl=%r" % (v.get("title"), v.get("subdomain"), v.get("defaultHostname"), v.get("customHostname"), v.get("internalUrl")))
    cat = dd.get("catalog") or {}
    ETAT["groupes"] = [g for g in (cat.get("groups") or []) if isinstance(g, str)]
    P("  catalog=%s" % json.dumps(cat)[:400], 460)
    if dd.get("catalogV2") or dd.get("catalogs"):
        P("  catalogV2/catalogs=%s" % json.dumps(dd.get("catalogV2") or dd.get("catalogs"))[:700], 760)
        for m in re.finditer(r"[0-9a-f]{32}", json.dumps(dd.get("catalogV2") or dd.get("catalogs"))):
            if m.group(0) not in ETAT["groupes"]:
                ETAT["groupes"].append(m.group(0))
    pages = v.get("pages") or dd.get("pages") or []
    P("  pages du site : %s" % [(p.get("id"), p.get("title"), p.get("slug")) for p in pages if isinstance(p, dict)][:12], 700)
    morceaux, liens = texte_des_cartes(v.get("layout") or {})
    P("  textes de la page d'accueil : %d morceaux" % len(morceaux))
    for t in morceaux[:10]:
        P("     · " + sans_courriel(t)[:420], 440)
    P("  liens cités : %s" % [sans_courriel(u)[:110] for u in liens[:16]], 1500)
    tout = json.dumps(dd)
    P("  occurrences dans la configuration du site : descarg=%d, download=%d, reutiliz=%d, licen=%d, datos abiertos=%d, open data=%d" % tuple(
        len(re.findall(m, tout, flags=re.I)) for m in ("descarg", "download", "reutiliz", "licen", "datos abiertos", "open ?data")))


def B():
    d = element(HUB_AVISO)
    dd = get_json("%s/content/items/%s/data?f=json" % (SHARING, HUB_AVISO)) or {}
    morceaux, liens = texte_des_cartes(dd)
    tout = " ".join(morceaux)
    P("  page « Aviso Legal » du site Hub : %d morceaux de texte, %d caractères" % (len(morceaux), len(tout)))
    for t in morceaux[:14]:
        P("     · " + sans_courriel(t)[:1500], 1520)
    P("  liens cités : %s" % [sans_courriel(u)[:120] for u in liens[:10]], 1100)
    P("  occurrences : reutiliz=%d, reproduc=%d, propiedad intelectual=%d, prohib=%d, licen=%d, citar=%d, autorizaci=%d" % tuple(
        len(re.findall(m, tout, flags=re.I)) for m in ("reutiliz", "reproduc", "propiedad intelectual", "prohib", "licen", "citar", "autorizaci")))


def C():
    for nom, i in (("service d'entités 4G", FS_ITEM), ("expérience « carte mobile 2024 »", EXP)):
        d = get_json("%s/content/items/%s/groups?f=json" % (SHARING, i)) or {}
        gs = (d.get("admin") or []) + (d.get("member") or []) + (d.get("other") or [])
        P("  groupes publics où est partagé l'élément %s (%s) : %d" % (i, nom, len(gs)))
        for g in gs[:8]:
            P("     %s | %r | access=%s | isOpenData=%s | dans le catalogue du site Hub : %s" % (g.get("id"), (g.get("title") or "")[:60], g.get("access"), g.get("isOpenData"), g.get("id") in ETAT["groupes"]))
    for gid in ETAT["groupes"][:4]:
        g = get_json("%s/community/groups/%s?f=json" % (SHARING, gid)) or {}
        P("  groupe du catalogue Hub %s : title=%r access=%s isOpenData=%s tags=%s" % (gid, (g.get("title") or "")[:70], g.get("access"), g.get("isOpenData"), (g.get("tags") or [])[:6]))
        s = get_json("%s/search?%s" % (SHARING, urllib.parse.urlencode({"q": "group:%s" % gid, "num": 40, "sortField": "modified", "sortOrder": "desc", "f": "json"}))) or {}
        res = s.get("results") or []
        P("     %s éléments publics dans ce groupe ; ceux qui évoquent le mobile :" % s.get("total"))
        for r in res:
            if re.search(r"(?i)4G|5G|m[oó]vil|Cob", r.get("title") or ""):
                P("       %s | %-18s | %s | licenseInfo=%r" % (r.get("id"), (r.get("type") or "")[:18], (r.get("title") or "")[:50], (r.get("licenseInfo") or "")[:60]))


def D():
    for owner in ("coberturaBA_eu", "coberturaBA"):
        s = get_json("%s/search?%s" % (SHARING, urllib.parse.urlencode({"q": "owner:%s AND (type:\"Hub Page\" OR type:\"Hub Site Application\" OR type:\"Site Page\" OR type:\"Site Application\")" % owner, "num": 30, "f": "json"}))) or {}
        P("  %s : %s sites ou pages Hub publics" % (owner, s.get("total")))
        for r in (s.get("results") or [])[:14]:
            P("     %s | %-22s | %-40s | créé %s | modifié %s | url=%s" % (r.get("id"), (r.get("type") or "")[:22], (r.get("title") or "")[:40], jour(r.get("created")), jour(r.get("modified")), (r.get("url") or "")[:80]))


bloc("A. Site Hub « HubConectemos »", A)
bloc("B. Page Hub « Aviso Legal »", B)
bloc("C. La couche 4G est-elle dans le catalogue du site Hub ?", C)
bloc("D. Autres sites et pages Hub des comptes du ministère", D)
bilan()
PY_FIN_SONDE
echo "FIN (code python : $?)"
