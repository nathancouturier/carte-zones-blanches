#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Espagne : ministère et régions », sonde es-v4.
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

# Sonde es-v4 : table des opérateurs (CIF vers raison sociale), texte du ministère sur le sens des opérateurs
# affichés, communiqués de presse (annonce d'une réutilisation ou d'une mise à jour de la carte ?), jeux du
# ministère dans le catalogue national, site de données ouvertes éventuel de l'organisation ArcGIS.
SHARING = "https://www.arcgis.com/sharing/rest"
TABLE_ITEM = "378d9746a2814325ba52c2698bdcd8fe"     # lu dans l'expression de la fenêtre d'information (sonde es-v3)
CIFS = ["A78923125", "A80907397", "A82009812", "A82528548"]   # lus dans les données (sonde es-v2)
PAGE_MIN = ("https://digital.gob.es/telecomunicaciones-infraestructuras-digitales/areas-interes/banda-ancha/"
            "informacion-cobertura/mapas-servicios-banda-ancha")


def proprietaire(o):
    return o if (o or "").startswith("coberturaBA") else "<compte tiers masqué>"


def A():
    d = get_json("%s/content/items/%s?f=json" % (SHARING, TABLE_ITEM)) or {}
    P("  ELEMENT %s : title=%r type=%s owner=%s access=%s créé %s modifié %s licenseInfo=%r url=%s" % (
        TABLE_ITEM, d.get("title"), d.get("type"), proprietaire(d.get("owner")), d.get("access"), jour(d.get("created")), jour(d.get("modified")), d.get("licenseInfo"), d.get("url")), 420)
    base = d.get("url")
    if not base:
        return
    r = get_json(base + "?f=json") or {}
    unites = [(x.get("id"), x.get("name"), "couche") for x in r.get("layers") or []] + [(x.get("id"), x.get("name"), "table") for x in r.get("tables") or []]
    P("  service : capabilities=%s ; couches et tables : %s" % (r.get("capabilities"), unites), 500)
    for i, nom, genre in unites[:4]:
        url = "%s/%s" % (base, i)
        m = get_json(url + "?f=json") or {}
        champs = [f["name"] for f in m.get("fields") or []]
        if "OPERADOR" not in champs:
            P("  %s (%s %r) : pas de champ OPERADOR, champs=%s" % (url, genre, nom, champs[:8]))
            continue
        c = query(url, where="1=1", returnCountOnly="true") or {}
        P("  %s (%s %r) : champs=%s ; %s lignes" % (url, genre, nom, champs, c.get("count")), 420)
        q = query(url, where="OPERADOR IN (%s)" % ",".join("'%s'" % j for j in CIFS), outFields="OPERADOR,RAZON_SOCIAL,PAGWEB,TIPO", returnGeometry="false") or {}
        for f in q.get("features") or []:
            a = f["attributes"]
            if CIF_MORALE.match((a.get("OPERADOR") or "").strip()):
                P("     %s | %s | %s | %s" % (a.get("OPERADOR"), a.get("RAZON_SOCIAL"), a.get("PAGWEB"), a.get("TIPO")))
        q = query(url, where="UPPER(RAZON_SOCIAL) LIKE 'DIGI%'", outFields="OPERADOR,RAZON_SOCIAL,TIPO", returnGeometry="false") or {}
        fs = [f["attributes"] for f in q.get("features") or [] if CIF_MORALE.match((f["attributes"].get("OPERADOR") or "").strip())]
        P("     personnes morales dont la raison sociale commence par « DIGI » : %d %s" % (len(fs), [(a.get("OPERADOR"), a.get("RAZON_SOCIAL"), a.get("TIPO")) for a in fs[:3]]), 420)
        st = [{"statisticType": "count", "onStatisticField": "OBJECTID", "outStatisticFieldName": "n"}]
        q = query(url, where="1=1", outStatistics=json.dumps(st), groupByFieldsForStatistics="TIPO", returnGeometry="false") or {}
        P("     lignes par TIPO : %s" % {f["attributes"].get("TIPO"): f["attributes"].get("n") for f in q.get("features") or []})


def B():
    st, hd, body, _ = get(PAGE_MIN)
    if st != 200:
        return
    t = plat(to_text(body.decode("utf-8", "replace")))
    for motif, n in ((r"Mapa de Servicios de Banda Ancha Móvil: Se representan", 420), (r"Atributos de Información que se facilitan", 900)):
        k = t.rfind(motif.replace("\\", ""))
        P("  [%s] position %d" % (motif[:50], k))
        if k >= 0:
            P("     " + t[k:k + n], n + 20)
    P("  occurrences dans la page : reutiliz=%d (hors menu « Reutilización de infraestructuras » : %d), descarg=%d, licencia de uso=%d, datos abiertos=%d" % (
        len(re.findall(r"(?i)reutiliz", t)), len(re.findall(r"(?i)reutiliz(?!ación de infraestructuras)", t)), len(re.findall(r"(?i)descarg", t)),
        len(re.findall(r"(?i)licencia de uso", t)), len(re.findall(r"(?i)datos abiertos", t))))


def phrases(t, motif, maxi=4, avant=150, apres=330):
    vus = []
    n = 0
    for m in re.finditer(motif, t):
        a = max(0, m.start() - avant)
        if any(abs(a - v) < 300 for v in vus):
            continue
        vus.append(a)
        P("     … %s …" % sans_courriel(t[a:m.end() + apres]), avant + apres + 80)
        n += 1
        if n >= maxi:
            break
    return n


def C():
    for nom, u in (("communiqué du 4 juin 2025", "https://digital.gob.es/comunicacion/notas-prensa/secretaria-estado-telecomunicaciones-e-infraestructuras-digitales/2025/06/2025-06-04"),
                   ("communiqué de mai 2026", "https://digital.gob.es/comunicacion/notas-prensa/secretaria-estado-telecomunicaciones-e-infraestructuras-digitales/2026/05/el-5g-alcanza-ya-al-99--de-la-poblacion-espanola-y-al-96--en-zon0")):
        st, hd, body, _ = get(u)
        if st != 200:
            continue
        raw = body.decode("utf-8", "replace")
        m = re.search(r"(?is)<title[^>]*>(.*?)</title>", raw)
        t = plat(to_text(raw))
        k = t.find("Nota de prensa")
        corps = t[k:] if k > 0 else t
        P("  %s : titre=%r ; %d caractères ; occurrences : mapa=%d, reutiliz=%d, datos abiertos=%d, descarg=%d" % (
            nom, plat(html.unescape(m.group(1)))[:110] if m else None, len(corps), len(re.findall(r"(?i)\bmapas?\b", corps)), len(re.findall(r"(?i)reutiliz", corps)),
            len(re.findall(r"(?i)datos abiertos", corps)), len(re.findall(r"(?i)descarg", corps))))
        phrases(corps, r"(?i)\bmapas? (?:de servicios|interactiv|de cobertura)|herramienta[^.]{0,60}mapa|reutiliz|datos abiertos", maxi=4)


def D():
    for u in ("https://datos.gob.es/apidata/catalog/dataset/publisher/E05251701.json?_pageSize=50&_page=0",
              "https://datos.gob.es/apidata/catalog/dataset/title/cobertura.json?_pageSize=50&_page=0"):
        d = get_json(u, quiet=False) or {}
        items = ((d.get("result") or {}).get("items")) or []
        P("     %d jeux dans la réponse" % len(items))
        n = 0
        for it in items:
            tit = it.get("title")
            if isinstance(tit, list):
                tit = next((x.get("_value") for x in tit if isinstance(x, dict) and x.get("_lang") == "es"), None) or (tit[0].get("_value") if tit and isinstance(tit[0], dict) else str(tit[0]) if tit else "")
            elif isinstance(tit, dict):
                tit = tit.get("_value")
            tit = str(tit or "")
            if not re.search(r"(?i)cobertura|banda ancha|m[óo]vil|telefon|4G|antena", tit):
                continue
            n += 1
            if n <= 14:
                pub = it.get("publisher")
                pub = pub.rsplit("/", 1)[-1] if isinstance(pub, str) else pub
                P("     - %s | éditeur=%s | licence=%s | %s" % (tit[:110], pub, str(it.get("license"))[:70], str(it.get("_about"))[-90:]), 420)
        P("     dont %d dont le titre évoque la couverture, le haut débit ou le mobile" % n)


def E():
    for u in ("https://conectemos.maps.arcgis.com/sharing/rest/portals/self?f=json",):
        d = get_json(u, quiet=False) or {}
        pp = d.get("portalProperties") or {}
        P("  organisation : name=%r urlKey=%r id=%s access=%s région=%s description=%r" % (
            d.get("name"), d.get("urlKey"), d.get("id"), d.get("access"), d.get("region"), sans_courriel(plat(to_text(d.get("description") or "")))[:160]), 420)
        P("     données ouvertes (portalProperties.openData) : %s ; hub : %s" % (json.dumps(pp.get("openData"))[:200], json.dumps(pp.get("hub"))[:160]), 420)
    d = get_json("%s/search?%s" % (SHARING, urllib.parse.urlencode({"q": "owner:coberturaBA_eu AND (type:\"Hub Site Application\" OR type:\"Site Application\" OR typekeywords:opendata)", "num": 10, "f": "json"}))) or {}
    P("  sites Hub ou éléments « opendata » du compte coberturaBA_eu : %s" % d.get("total"))
    for r in (d.get("results") or [])[:5]:
        P("     %s | %s | %s" % (r.get("id"), r.get("type"), (r.get("title") or "")[:60]))


def F():
    for h in ("tiledimageservices-eu1.arcgis.com", "tiledimageservices9.arcgis.com", "services-eu1.arcgis.com", "www.arcgis.com"):
        rp, st, ok, txt = robots_de(h)
        P("  https://%s/robots.txt -> code %s, %d octets, texte brut : %r" % (h, st, len(txt), txt[:160]))


bloc("A. Table des opérateurs citée par la fenêtre d'information", A)
bloc("B. Page du ministère : sens des opérateurs affichés, mentions de réutilisation", B)
bloc("C. Communiqués de presse du ministère", C)
bloc("D. Catalogue national datos.gob.es : jeux du ministère et jeux « cobertura »", D)
bloc("E. Organisation ArcGIS du ministère : site de données ouvertes ?", E)
bloc("F. robots.txt des hôtes ArcGIS, texte brut", F)
bilan()
PY_FIN_SONDE
echo "FIN (code python : $?)"
