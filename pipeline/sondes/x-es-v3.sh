#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Espagne : ministère et régions », sonde es-v3.
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

# Sonde es-v3 : liens du pied de la carte (copyright), expressions de la fenêtre d'information et table des
# opérateurs, page Conectemos, service d'origine (mêmes données ?), maille de la grille, et essai de la méthode
# de récupération proposée (extraction createReplica sur une petite commune, deux pages de pagination, pilote OGR).
# Les hôtes des tuiles (tiledimageservices*) interdisent les robots : ils ne sont pas interrogés.
from osgeo import gdal, ogr
gdal.UseExceptions()
gdal.SetConfigOption("GDAL_HTTP_USERAGENT", UA)

SHARING = "https://www.arcgis.com/sharing/rest"
EXP = "ef9f55c81f304e5185fcdd7cecf98e7f"            # lu sur la page du ministère (sonde es-v2)
WM4 = "21cb30f5fd6944ff9bb1f803bd028df3"            # carte web 4G de cette expérience (sonde es-v2)
FL = "https://services-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/InfoCob4G_2024/FeatureServer/0"
FS_ITEM = "84599189a281451c8ac61bc4901459d1"        # serviceItemId de la couche (sonde es-v2)
CIFS = ["A78923125", "A80907397", "A82009812", "A82528548"]   # lus dans les données (sonde es-v2)
EMPRISE = "-3.6,39.7,3.5,43.9"
ETAT = {}


def proprietaire(o):
    """Les comptes du ministère sont affichés ; tout autre compte (qui peut porter un nom de personne) est masqué."""
    return o if (o or "").startswith("coberturaBA") else "<compte tiers masqué>"


def element(i):
    d = get_json("%s/content/items/%s?f=json" % (SHARING, i)) or {}
    P("  ELEMENT %s : title=%r type=%s owner=%s access=%s créé %s modifié %s licenseInfo=%r url=%s" % (
        i, d.get("title"), d.get("type"), proprietaire(d.get("owner")), d.get("access"), jour(d.get("created")), jour(d.get("modified")), d.get("licenseInfo"), d.get("url")), 420)
    return d


def chaines(o, acc):
    if isinstance(o, str):
        acc.append(o)
    elif isinstance(o, dict):
        for v in o.values():
            chaines(v, acc)
    elif isinstance(o, list):
        for v in o:
            chaines(v, acc)


def A():
    d = get_json("%s/content/items/%s/data?f=json" % (SHARING, EXP)) or {}
    ws = d.get("widgets") or {}
    w = ws.get("widget_21") or {}
    P("  widget_21 (%r, %s), configuration brute : %s" % (w.get("label"), w.get("uri"), sans_courriel(json.dumps(w.get("config"), ensure_ascii=False))[:900]), 1000)
    liens = collections.OrderedDict()
    for k, x in ws.items():
        acc = []
        chaines(x.get("config"), acc)
        for a in acc:
            for m in re.finditer(r"https?://[^\s\"'<>\\)]+", a):
                u = m.group(0)
                if not re.search(r"arcgisonline|\.png|\.jpg|\.svg|geocode|js\.arcgis", u):
                    liens.setdefault(u, []).append(k)
    P("  adresses citées dans les widgets (hors fonds de carte et images) : %d" % len(liens))
    for u, ks in list(liens.items())[:30]:
        P("     %s  (%s)" % (sans_courriel(u)[:200], ",".join(sorted(set(ks)))[:60]))
    acc = []
    chaines(d, acc)
    tout = " ".join(acc)
    P("  dans toute la configuration : « nota-legal »=%d, « aviso »=%d, « copyright »=%d, « licen »=%d, « reutiliz »=%d" % tuple(
        len(re.findall(m, tout, flags=re.I)) for m in ("nota-legal", "aviso", "copyright", "licen", "reutiliz")))


def B():
    st, hd, body, _ = get("%s/content/items/%s/data?f=json" % (SHARING, WM4), quiet=True)
    txt = body.decode("utf-8", "replace")
    acc = []
    chaines(json.loads(txt), acc)
    table = None
    n = 0
    for a in acc:
        if "Split(" in a or "FeatureSetBy" in a:
            for ligne in a.split("\n"):
                if re.search(r"(?i)split\(|FeatureSetBy|Filter\(|RAZON|OPERADOR|return", ligne) and n < 14:
                    n += 1
                    P("     arcade : %s" % plat(ligne)[:260])
            m = re.search(r"['\"]([0-9a-f]{32})['\"]\s*,\s*(\d+)", a)
            if m:
                table = (m.group(1), int(m.group(2)))
    if not table:
        P("  table des opérateurs introuvable dans la carte web")
        return
    d = element(table[0])
    url = "%s/%d" % (d.get("url"), table[1])
    m = get_json(url + "?f=json") or {}
    P("  %s : name=%r type=%s champs=%s" % (url, m.get("name"), m.get("type"), [f["name"] for f in m.get("fields") or []]))
    c = query(url, where="1=1", returnCountOnly="true") or {}
    P("  lignes : %s" % c.get("count"))
    r = query(url, where="OPERADOR IN (%s)" % ",".join("'%s'" % j for j in CIFS), outFields="OPERADOR,RAZON_SOCIAL,PAGWEB,TIPO", returnGeometry="false") or {}
    for f in r.get("features") or []:
        a = f["attributes"]
        if CIF_MORALE.match((a.get("OPERADOR") or "").strip()):
            P("     %s | %s | %s | %s" % (a.get("OPERADOR"), a.get("RAZON_SOCIAL"), a.get("PAGWEB"), a.get("TIPO")))
    r = query(url, where="UPPER(RAZON_SOCIAL) LIKE 'DIGI%'", outFields="OPERADOR,RAZON_SOCIAL,TIPO", returnGeometry="false") or {}
    fs = [f["attributes"] for f in r.get("features") or [] if CIF_MORALE.match((f["attributes"].get("OPERADOR") or "").strip())]
    P("  personnes morales dont la raison sociale commence par « DIGI » : %d" % len(fs))
    for a in fs[:4]:
        P("     %s | %s | %s" % (a.get("OPERADOR"), a.get("RAZON_SOCIAL"), a.get("TIPO")))
    st = [{"statisticType": "count", "onStatisticField": "OBJECTID", "outStatisticFieldName": "n"}]
    r = query(url, where="1=1", outStatistics=json.dumps(st), groupByFieldsForStatistics="TIPO", returnGeometry="false") or {}
    P("  lignes par TIPO : %s" % {f["attributes"].get("TIPO"): f["attributes"].get("n") for f in r.get("features") or []})


def C():
    st, hd, body, _ = get("https://conectemos.digital.gob.es/es/mapas-y-graficos/servicios-de-banda-ancha")
    raw = body.decode("utf-8", "replace")
    t = plat(to_text(raw))
    for m in list(re.finditer(r"(?i)banda ancha m[óo]vil[^.]{0,200}", t))[:3]:
        P("     texte : … %s" % t[max(0, m.start() - 80):m.end() + 40][:330])
    ids = []
    for m in re.finditer(r"arcgis\.com[^\s\"'<>]{0,80}?([0-9a-f]{32})", raw):
        if m.group(1) not in ids:
            ids.append(m.group(1))
    P("  identifiants ArcGIS cités : %s ; occurrences de « arcgis » dans la page : %d ; autres suites de 32 caractères hexadécimaux : %s" % (
        ids, raw.count("arcgis"), sorted(set(re.findall(r"(?<![0-9a-f])[0-9a-f]{32}(?![0-9a-f])", raw)) - set(ids))[:6]), 600)
    for i in ids[:5]:
        d = element(i)
        if "xperience" in (d.get("type") or "") and re.search(r"(?i)m[oó]vil", d.get("title") or ""):
            dd = get_json("%s/content/items/%s/data?f=json" % (SHARING, i)) or {}
            acc = []
            chaines(dd.get("widgets"), acc)
            for m in list(re.finditer(r"4G[^.]{0,200}referida a[^.<]{0,40}", plat(to_text(" ".join(acc)))))[:1]:
                P("     texte de cette expérience : … %s" % m.group(0)[-120:])
            for k, v in (dd.get("dataSources") or {}).items():
                if v.get("type") == "WEB_MAP":
                    P("     source %s : %r itemId=%s" % (k, v.get("sourceLabel") or v.get("label"), v.get("itemId")))


def stats(url, where):
    st = [{"statisticType": "count", "onStatisticField": "OBJECTID", "outStatisticFieldName": "n"},
          {"statisticType": "sum", "onStatisticField": "Shape__Area", "outStatisticFieldName": "a"}]
    d = query(url, where=where, outStatistics=json.dumps(st), groupByFieldsForStatistics="COBERTURA", returnGeometry="false") or {}
    return {(f["attributes"].get("COBERTURA") or ""): (f["attributes"]["n"], round(f["attributes"]["a"] or 0, 8)) for f in d.get("features") or []}


def D():
    d = get_json("%s/content/items/%s?f=json" % (SHARING, FS_ITEM)) or {}
    src = [k[7:] for k in d.get("typeKeywords") or [] if k.startswith("source-")]
    P("  élément du service lié par le ministère : %s, mot-clé d'origine : %s" % (FS_ITEM, src))
    if not src:
        return
    o = element(src[0])
    orig = (o.get("url") or "") + "/0"
    m = get_json(orig + "?f=json") or {}
    P("  service d'origine %s : name=%r capabilities=%s editingInfo=%s" % (orig, m.get("name"), m.get("capabilities"), {k: jour(v) for k, v in (m.get("editingInfo") or {}).items()}), 420)
    c = query(orig, where="1=1", returnCountOnly="true") or {}
    P("  service d'origine, nombre total d'entités : %s" % c.get("count"))
    for cc in ("16", "15"):
        a, b = stats(orig, "CCOM='%s'" % cc), stats(FL, "CCOM='%s'" % cc)
        P("  CCOM %s : origine %d valeurs, %d entités ; copie %d valeurs, %d entités ; effectifs et surfaces identiques : %s" % (
            cc, len(a), sum(v[0] for v in a.values()), len(b), sum(v[0] for v in b.values()), a == b))
        for k in sorted(set(a) | set(b)):
            if a.get(k) != b.get(k):
                P("     écart %r : origine=%s copie=%s" % (k[:44], a.get(k), b.get(k)))


def E():
    d = query(FL, where="CCOM='15' AND COBERTURA<>''", geometry="-1.70,42.775,-1.66,42.80", geometryType="esriGeometryEnvelope", inSR="4258",
              spatialRel="esriSpatialRelIntersects", outFields="OBJECTID", returnGeometry="true", resultRecordCount=600, orderByFields="OBJECTID") or {}
    fs = d.get("features") or []
    xs, ys = set(), set()
    for f in fs:
        for r in (f.get("geometry") or {}).get("rings") or []:
            for p in r:
                xs.add(round(p[0], 10))
                ys.add(round(p[1], 10))
    P("  %d entités lues (sr=%s), %d abscisses et %d ordonnées distinctes" % (len(fs), d.get("spatialReference"), len(xs), len(ys)))
    for nom, vals, orig in (("x", sorted(xs), -180.0), ("y", sorted(ys), 90.0)):
        diffs = collections.Counter(round(b - a, 9) for a, b in zip(vals, vals[1:]))
        P("     pas le plus fréquent en %s : %s" % (nom, ", ".join("%.9f° (%d fois)" % (k, n) for k, n in diffs.most_common(3))))
        pas = 0.000346111018645788
        fr = collections.Counter(round(((v - orig) / pas) % 1.0, 2) % 1.0 for v in vals)
        P("     position sur une grille de pas %.15f° d'origine %s : fractions les plus fréquentes %s" % (pas, orig, fr.most_common(3)))


def F():
    cands = [("15", "34153131185"), ("09", "34092525043"), ("16", "34164848077"), ("02", "34022222107")]
    choisi = None
    for cc, nat in cands:
        w = "CCOM='%s' AND NATCODE='%s' AND COBERTURA<>''" % (cc, nat)
        c = (query(FL, where=w, returnCountOnly="true") or {}).get("count")
        P("  candidat %s : %s entités" % (w, c))
        if c and 200 <= c <= 8000:
            choisi = (w, c)
            break
    if not choisi:
        P("  aucun candidat de taille convenable")
        return
    w, attendu = choisi
    ETAT["where"] = w
    racine = FL.rsplit("/", 1)[0]
    corps = urllib.parse.urlencode({
        "f": "json", "layers": "0", "replicaName": "verif_petite_commune",
        "layerQueries": json.dumps({"0": {"where": w, "useGeometry": True, "queryOption": "useFilter"}}),
        "geometry": EMPRISE, "geometryType": "esriGeometryEnvelope", "inSR": "4258", "returnAttachments": "false",
        "syncModel": "none", "dataFormat": "filegdb", "async": "true", "transportType": "esriTransportTypeUrl"}).encode()
    t0 = time.time()
    st, hd, body, _ = get(racine + "/createReplica", data=corps)
    P("  réponse : %s" % body[:300].decode("utf-8", "replace"))
    try:
        su = json.loads(body).get("statusUrl")
    except Exception:
        su = None
    if not su:
        return
    res = None
    for k in range(40):
        time.sleep(4)
        s = get_json(su + "?f=json") or {}
        if k in (0, 2) or s.get("status") in ("Completed", "Failed", "CompletedWithErrors"):
            P("  état après %.0f s : status=%s recordCount=%s resultUrl=%s erreur=%s" % (time.time() - t0, s.get("status"), s.get("recordCount"), (s.get("resultUrl") or "")[:170], s.get("error")), 420)
        if s.get("status") in ("Completed", "Failed", "CompletedWithErrors"):
            res = s
            break
    if not res or not res.get("resultUrl"):
        P("  pas de fichier produit")
        return
    st, hd, body, _ = get(res["resultUrl"], timeout=300)
    path = os.path.join(T, "extrait.zip")
    open(path, "wb").write(body)
    P("  fichier : %d octets, soit %.0f octets par entité ; signature %r" % (len(body), len(body) / max(1, attendu), body[:2]))
    noms = [n for n in (gdal.ReadDir("/vsizip/" + path) or []) if n.lower().endswith(".gdb")]
    P("  contenu du zip : %s" % (gdal.ReadDir("/vsizip/" + path) or [])[:5])
    if not noms:
        return
    ds = ogr.Open("/vsizip/%s/%s" % (path, noms[0]))
    lyr = ds.GetLayer(0)
    srs = lyr.GetSpatialRef()
    defn = lyr.GetLayerDefn()
    P("  pilote=%s couche=%r géométrie=%s entités=%d (attendu %d) SCR=%s:%s" % (
        ds.GetDriver().GetName(), lyr.GetName(), ogr.GeometryTypeToName(lyr.GetGeomType()), lyr.GetFeatureCount(), attendu,
        srs.GetAuthorityName(None) if srs else None, srs.GetAuthorityCode(None) if srs else None))
    P("  champs : %s" % [defn.GetFieldDefn(i).GetName() for i in range(defn.GetFieldCount())], 500)
    vals = collections.Counter()
    ccom = collections.Counter()
    for f in lyr:
        vals[f.GetField("COBERTURA") or ""] += 1
        ccom[f.GetField("CCOM") or ""] += 1
    P("  valeurs de COBERTURA dans l'extrait : %s ; CCOM : %s" % (dict(vals.most_common(8)), dict(ccom)), 500)


def G():
    w = "CCOM='16' AND COBERTURA<>''"
    dernier = 0
    for page in (1, 2):
        u = FL + "/query?" + urllib.parse.urlencode({"where": "%s AND OBJECTID>%d" % (w, dernier), "outFields": "OBJECTID,COBERTURA", "orderByFields": "OBJECTID",
                                                    "resultRecordCount": 2000, "returnGeometry": "true", "f": "json"})
        st, hd, body, _ = get(u, quiet=True)
        d = json.loads(body) if st == 200 else {}
        fs = d.get("features") or []
        P("  page %d (OBJECTID>%d) : code %s en %s s ; reçu %s octets (%s), décodé %d octets ; %d entités ; exceededTransferLimit=%s" % (
            page, dernier, st, hd.get("_duree"), hd.get("_recu"), hd.get("Content-Encoding"), len(body), len(fs), d.get("exceededTransferLimit")))
        if not fs:
            break
        dernier = fs[-1]["attributes"]["OBJECTID"]
    w2 = ETAT.get("where")
    if not w2:
        return
    u = "ESRIJSON:" + FL + "/query?" + urllib.parse.urlencode({"where": w2, "outFields": "OBJECTID,COBERTURA,CCOM", "orderByFields": "OBJECTID", "resultRecordCount": 2000, "f": "json"})
    t0 = time.time()
    ds = gdal.OpenEx(u, gdal.OF_VECTOR, open_options=["FEATURE_SERVER_PAGING=YES"])
    lyr = ds.GetLayer(0)
    n = sum(1 for _ in lyr)
    srs = lyr.GetSpatialRef()
    P("  pilote OGR %s, pagination automatique : %d entités lues en %.1f s, géométrie=%s, SCR=%s:%s" % (
        ds.GetDriver().ShortName, n, time.time() - t0, ogr.GeometryTypeToName(lyr.GetGeomType()), srs.GetAuthorityName(None) if srs else None, srs.GetAuthorityCode(None) if srs else None))


def H():
    d = get_json("https://opendata.aragon.es/ckan/api/3/action/package_show?id=cobertura-movil-real-por-tecnologia-en-aragon-junio-2026", quiet=False) or {}
    r = d.get("result") or {}
    P("  Aragon : title=%r license_id=%r license_title=%r organisme=%r ressources=%d" % (
        r.get("title"), r.get("license_id"), r.get("license_title"), (r.get("organization") or {}).get("title"), len(r.get("resources") or [])))
    notes = plat(to_text(r.get("notes") or ""))
    for m in list(re.finditer(r"(?i)cuadr[íi]culas?[^.]{0,160}|operador[^.]{0,120}|calidad de la cobertura[^.]{0,160}", notes))[:3]:
        P("     description : … %s" % m.group(0)[:300])
    for x in (r.get("resources") or [])[:6]:
        P("     ressource : %r format=%s url=%s" % (x.get("name"), x.get("format"), (x.get("url") or "")[:150]))
    d = get_json("https://analisi.transparenciacatalunya.cat/api/views/4tqz-ha5q.json", quiet=False) or {}
    lic = d.get("license") or {}
    P("  Catalogne : name=%r licenseId=%r licence=%r créé=%s mis à jour=%s attribution=%r" % (
        d.get("name"), d.get("licenseId"), lic.get("name"), jour((d.get("createdAt") or 0) * 1000), jour((d.get("rowsUpdatedAt") or d.get("viewLastModified") or 0) * 1000), d.get("attribution")))
    P("     description : %s" % plat(to_text(d.get("description") or ""))[:420], 460)


bloc("A. Pied de la carte : lien « Información de copyright » et adresses citées", A)
bloc("B. Fenêtre d'information de la carte 4G et table des opérateurs", B)
bloc("C. Page « servicios de banda ancha » du portail Conectemos", C)
bloc("D. Service d'origine et copie liée par le ministère : mêmes données ?", D)
bloc("E. Maille de la grille des polygones", E)
bloc("F. Extraction createReplica sur une petite commune (forme de la recette proposée)", F)
bloc("G. Pagination (deux pages) et lecture par le pilote OGR", G)
bloc("H. Alternatives régionales : licence des jeux d'Aragon et de Catalogne", H)
bilan()
PY_FIN_SONDE
echo "FIN (code python : $?)"
