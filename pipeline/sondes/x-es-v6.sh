#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Espagne : ministère et régions », sonde es-v6.
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

# Sonde es-v6 : portail de données ouvertes du ministère sur ArcGIS Hub (suite de la sonde es-v5).
# Texte intégral de la page « Aviso Legal », contenu du catalogue ouvert, et place de la couche 4G détaillée.
SHARING = "https://www.arcgis.com/sharing/rest"
HUB_SITE = "5e292c4175544a5f89bfe5cee6641506"
HUB_AVISO = "457e0fa87a924ad08d7385d295b5ad19"
GROUPE = "4588e7c66cdb4de2ba5f54af64c69a3e"           # groupe du catalogue du site Hub (sonde es-v5)
ORIG = {"service d'entités 4G d'origine": "5d7ccfd795e44c3e94f17170fce570f5", "expérience mobile d'origine": "8f319e778b924f2ab790e9e1f7b0c76d",
        "carte web 4G liée par le ministère": "21cb30f5fd6944ff9bb1f803bd028df3", "table des opérateurs": "378d9746a2814325ba52c2698bdcd8fe"}
HUBS_ORIG = {"HubTest": "8ef28a40266e41a9af23698b65fe6577", "Hub.Gov": "99c0857c029c42e49e0a710fef48c8a3"}
AVISO_ORIG = "f5db6f4d211c48b894c19f6e7bde28ae"


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


def textes(d, mini=40):
    acc = []
    chaines(d, acc)
    out = []
    for a in acc:
        if len(a) >= mini and ("<" in a or " " in a) and not a.startswith("data:") and not re.match(r"^https?://\S+$", a):
            t = plat(to_text(a))
            if len(t) >= mini and t not in out:
                out.append(t)
    return out


def en_morceaux(t, n=1400, maxi=7):
    t = sans_courriel(t)
    for k in range(0, min(len(t), n * maxi), n):
        P("     [%d] %s" % (k, t[k:k + n]), n + 20)


def A():
    dd = get_json("%s/content/items/%s/data?f=json" % (SHARING, HUB_AVISO)) or {}
    ts = textes(dd)
    P("  page « Aviso Legal » du site Hub (%s) : %d morceau(x)" % (HUB_AVISO, len(ts)))
    for t in ts[:2]:
        P("  texte de %d caractères :" % len(t))
        en_morceaux(t)
    ETAT_A = " ".join(ts)
    d2 = get_json("%s/content/items/%s/data?f=json" % (SHARING, AVISO_ORIG)) or {}
    t2 = " ".join(textes(d2))
    P("  page « Aviso Legal » du compte d'origine (%s) : %d caractères ; identique à la précédente : %s" % (AVISO_ORIG, len(t2), t2 == ETAT_A))
    if t2 and t2 != ETAT_A:
        P("     début : %s" % sans_courriel(t2)[:500], 520)


def B():
    dd = get_json("%s/content/items/%s/data?f=json" % (SHARING, HUB_SITE)) or {}
    v = dd.get("values") or {}
    ts = textes(v.get("layout") or {}) + [t for t in textes(dd.get("layout") or {})]
    for t in ts[:3]:
        P("  texte d'accueil (%d caractères) :" % len(t))
        en_morceaux(t, maxi=2)
    tout = plat(to_text(" ".join(textes(dd, mini=10))))
    for m in list(re.finditer(r"(?i)licen[^.]{0,200}", tout))[:3]:
        P("  « licen » : … %s" % sans_courriel(tout[max(0, m.start() - 160):m.end() + 60])[:520], 540)
    P("  updatedAt=%s ; capabilities=%s" % (v.get("updatedAt"), v.get("capabilities")), 400)


def C():
    g = get_json("%s/community/groups/%s?f=json" % (SHARING, GROUPE)) or {}
    P("  groupe %s : title=%r access=%s isOpenData=%s créé %s modifié %s description=%r" % (
        GROUPE, g.get("title"), g.get("access"), g.get("isOpenData"), jour(g.get("created")), jour(g.get("modified")), plat(to_text(g.get("description") or ""))[:120]))
    s = get_json("%s/search?%s" % (SHARING, urllib.parse.urlencode({"q": "group:%s" % GROUPE, "num": 40, "f": "json"}))) or {}
    P("  %s éléments publics dans le catalogue ouvert :" % s.get("total"))
    for r in s.get("results") or []:
        P("     %s | %-16s | %-34s | owner=%s | créé %s | licenseInfo=%r | url=%s" % (
            r.get("id"), (r.get("type") or "")[:16], (r.get("title") or "")[:34], proprietaire(r.get("owner")), jour(r.get("created")),
            plat(to_text(r.get("licenseInfo") or ""))[:110], (r.get("url") or "")[:110]), 480)
        if r.get("type") == "Feature Service" and r.get("url"):
            m = get_json(r["url"] + "/0?f=json") or {}
            P("        couche 0 : name=%r géométrie=%s capabilities=%s champs=%s" % (m.get("name"), m.get("geometryType"), m.get("capabilities"), [f["name"] for f in m.get("fields") or []][:26]), 620)


def D():
    for nom, i in ORIG.items():
        d = get_json("%s/content/items/%s/groups?f=json" % (SHARING, i)) or {}
        gs = (d.get("admin") or []) + (d.get("member") or []) + (d.get("other") or [])
        P("  %s (%s) : partagé dans %d groupe(s) public(s) %s" % (nom, i, len(gs), [(x.get("id"), (x.get("title") or "")[:30], x.get("isOpenData")) for x in gs[:5]]), 420)
    for nom, i in HUBS_ORIG.items():
        dd = get_json("%s/content/items/%s/data?f=json" % (SHARING, i)) or {}
        ids = sorted(set(re.findall(r"[0-9a-f]{32}", json.dumps(dd.get("catalogV2") or {}) + json.dumps(dd.get("catalog") or {}))))
        P("  site %s (%s) : groupes du catalogue %s" % (nom, i, ids[:5]))
        for gid in ids[:2]:
            s = get_json("%s/search?%s" % (SHARING, urllib.parse.urlencode({"q": "group:%s" % gid, "num": 40, "f": "json"}))) or {}
            res = s.get("results") or []
            P("     groupe %s : %s éléments publics : %s" % (gid, s.get("total"), [((r.get("title") or "")[:34], (r.get("type") or "")[:16]) for r in res[:14]]), 900)


bloc("A. Page « Aviso Legal » du portail de données ouvertes (texte intégral)", A)
bloc("B. Page d'accueil du portail de données ouvertes", B)
bloc("C. Contenu du catalogue ouvert", C)
bloc("D. Les éléments de la carte mobile sont-ils dans un catalogue ouvert ?", D)
bilan()
PY_FIN_SONDE
echo "FIN (code python : $?)"
