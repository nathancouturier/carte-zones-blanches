#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Espagne : ministère et régions », sonde es-v2.
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

# Sonde es-v1 : chaîne officielle (page du ministère -> expérience -> carte web -> couches), métadonnées,
# valeurs et statistiques de la couche d'entités 4G, table des opérateurs, points de contrôle,
# comparaison avec le service d'origine, recherche d'une édition plus récente, compléments sur les mentions légales.
# Les hôtes des tuiles (tiledimageservices*) interdisent les robots : ils ne sont pas interrogés (filtre robots.txt de commun.py).
PAGE_MIN = ("https://digital.gob.es/telecomunicaciones-infraestructuras-digitales/areas-interes/banda-ancha/"
            "informacion-cobertura/mapas-servicios-banda-ancha")
PAGE_CON = "https://conectemos.digital.gob.es/es/mapas-y-graficos/servicios-de-banda-ancha"
SHARING = "https://www.arcgis.com/sharing/rest"
REGIONS = ["02", "09", "15", "16"]
MOTS = re.compile(r"(?i)reutiliz|licen|propiedad intelectual|prohib|descarg|copyright|derechos|t[ée]rminos|referida|fuente")
ETAT = {"exp": {}, "cartes": {}, "couches": [], "table": None, "cifs": [], "fl": None, "fl_orig": None}


def liens_arcgis(url, nom):
    st, hd, body, _ = get(url)
    txt = body.decode("utf-8", "replace")
    ids = []
    for m in re.finditer(r'href="([^"]*arcgis[^"]*)"', txt):
        href = html.unescape(m.group(1))
        avant = plat(to_text(txt[max(0, m.start() - 1500):m.start()]))[-230:]
        apres = plat(to_text(txt[m.end():m.end() + 300]))[:60]
        P("  lien : %s" % href[:200])
        P("     texte qui précède : … %s | ancre : %s" % (avant, apres))
        i = re.search(r"([0-9a-f]{32})", href)
        if i and i.group(1) not in ids:
            ids.append(i.group(1))
    t = to_text(txt)
    for k, m in enumerate(re.finditer(r"(?i)banda ancha m[óo]vil\s+20\d\d|referid[ao]s? a[^.]{0,60}20\d\d|reutiliza[^.]{0,120}", t)):
        if k < 10:
            P("  mention : %s" % plat(t[max(0, m.start() - 60):m.end() + 60])[:280])
    P("  %s : %d identifiant(s) ArcGIS trouvé(s) : %s" % (nom, len(ids), ", ".join(ids)))
    return ids


def element(i, role):
    d = get_json("%s/content/items/%s?f=json" % (SHARING, i)) or {}
    src = [k for k in d.get("typeKeywords") or [] if k.startswith("source-")]
    P("  ELEMENT %s (%s) : title=%r type=%s owner=%s access=%s created=%s modified=%s" % (
        i, role, d.get("title"), d.get("type"), d.get("owner"), d.get("access"), jour(d.get("created")), jour(d.get("modified"))))
    P("     licenseInfo=%r | accessInformation=%r | snippet=%r | description=%r | tags=%s | %s | url=%s" % (
        d.get("licenseInfo"), d.get("accessInformation"), (d.get("snippet") or "")[:80], plat(to_text(d.get("description") or ""))[:120],
        d.get("tags"), ",".join(src), d.get("url")), 420)
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


def experience(i, role):
    element(i, role)
    d = get_json("%s/content/items/%s/data?f=json" % (SHARING, i)) or {}
    cartes = []
    for k, v in (d.get("dataSources") or {}).items():
        if v.get("type") == "WEB_MAP":
            cartes.append(v.get("itemId"))
            P("  source %s : WEB_MAP %r itemId=%s portail=%s" % (k, v.get("sourceLabel") or v.get("label"), v.get("itemId"), v.get("portalUrl")))
    n = 0
    for k, w in (d.get("widgets") or {}).items():
        acc = []
        chaines(w.get("config"), acc)
        t = plat(to_text(" ".join(a for a in acc if len(a) > 25)))
        if not t or "text" not in (w.get("uri") or ""):
            continue
        n += 1
        if MOTS.search(t):
            P("  TEXTE %s (%r, %d caractères) :" % (k, w.get("label"), len(t)))
            P("     " + sans_courriel(t)[:2400], 2500)
    P("  widgets de texte : %d ; publishTimestamp=%s" % (n, jour(d.get("publishTimestamp"))))
    ETAT["exp"][i] = cartes
    return cartes


def carte_web(i):
    element(i, "carte web")
    d = get_json("%s/content/items/%s/data?f=json" % (SHARING, i)) or {}
    out = []
    for lyr in d.get("operationalLayers") or []:
        P("  couche [%s] %r url=%s itemId=%s opacité=%s" % (lyr.get("layerType"), lyr.get("title"), lyr.get("url"), lyr.get("itemId"), lyr.get("opacity")))
        out.append(lyr)
        pop = lyr.get("popupInfo") or {}
        for e in pop.get("expressionInfos") or []:
            ex = e.get("expression") or ""
            for ligne in ex.split("\n"):
                if re.search(r"(?i)split|FeatureSetBy|cobertura|OPERADOR|RAZON", ligne):
                    P("     arcade %s : %s" % (e.get("name"), plat(ligne)[:230]))
            for m in re.finditer(r"['\"]([0-9a-f]{32})['\"]\s*,\s*(\d+)", ex):
                lyr["_table"] = (m.group(1), int(m.group(2)))
        if pop.get("title") or pop.get("description"):
            P("     fenêtre : titre=%r description=%r" % (pop.get("title"), plat(to_text(pop.get("description") or ""))[:160]))
    return out


def A():
    ids = liens_arcgis(PAGE_MIN, "page du ministère")
    ETAT["ids_min"] = ids


def B():
    for i in ETAT.get("ids_min") or []:
        d = get_json("%s/content/items/%s?f=json" % (SHARING, i), quiet=True) or {}
        if "xperience" not in (d.get("type") or ""):
            P("  %s : type=%s title=%r (pas une expérience, non suivi)" % (i, d.get("type"), d.get("title")))
            continue
        if not re.search(r"(?i)m[oó]vil", d.get("title") or ""):
            P("  %s : title=%r (autre carte, non suivie)" % (i, d.get("title")))
            continue
        for c in experience(i, "expérience liée par le ministère"):
            for lyr in carte_web(c):
                if "4G" in (lyr.get("url") or "") or "4G" in (lyr.get("title") or ""):
                    ETAT["couches"].append(lyr)
                    if lyr.get("_table"):
                        ETAT["table"] = lyr["_table"]
                    if lyr.get("layerType") != "ArcGISFeatureLayer" and lyr.get("itemId"):
                        element(lyr["itemId"], "élément de la couche image 4G")


def C():
    fl = [l for l in ETAT["couches"] if l.get("layerType") == "ArcGISFeatureLayer"]
    if not fl:
        P("  aucune couche d'entités 4G trouvée par la chaîne : arrêt du bloc")
        return
    url = fl[0]["url"]
    ETAT["fl"] = url
    d = get_json(url + "?f=json", quiet=False) or {}
    P("  name=%r type=%s geometryType=%s wkid=%s capabilities=%s maxRecordCount=%s" % (
        d.get("name"), d.get("type"), d.get("geometryType"), (d.get("extent") or {}).get("spatialReference"), d.get("capabilities"), d.get("maxRecordCount")))
    P("  supportedQueryFormats=%s | supportedExportFormats=%s | hasStaticData=%s" % (d.get("supportedQueryFormats"), d.get("supportedExportFormats"), d.get("hasStaticData")))
    ei = d.get("editingInfo") or {}
    P("  editingInfo : %s | copyrightText=%r | description=%r | serviceItemId=%s" % (
        {k: jour(v) for k, v in ei.items()}, d.get("copyrightText"), d.get("description"), d.get("serviceItemId")))
    P("  extent=%s" % json.dumps(d.get("extent")), 330)
    P("  champs : " + " ; ".join("%s(%s%s)" % (f["name"], f["type"].replace("esriFieldType", ""), ",%s" % f["length"] if f.get("length") else "") for f in d.get("fields") or []), 900)
    P("  index : " + " ; ".join("%s[%s]" % (x.get("name"), x.get("fields")) for x in d.get("indexes") or []), 500)
    racine = url.rsplit("/", 1)[0]
    r = get_json(racine + "?f=json") or {}
    P("  racine du service : capabilities=%s | syncEnabled=%s | supportedExportFormats=%s | copyrightText=%r | serviceDescription=%r | couches=%s | tables=%s" % (
        r.get("capabilities"), r.get("syncEnabled"), r.get("supportedExportFormats"), r.get("copyrightText"), (r.get("serviceDescription") or "")[:80],
        [(l.get("id"), l.get("name")) for l in r.get("layers") or []], [(l.get("id"), l.get("name")) for l in r.get("tables") or []]), 600)
    if d.get("serviceItemId"):
        element(d["serviceItemId"], "service d'entités")
    st, hd, body, _ = get(url + "/query?where=1%3D1&returnCountOnly=true&f=json", quiet=True)
    P("  nombre total d'entités : %s" % body[:60].decode("utf-8", "replace"))
    P("  en-têtes de la réponse : " + " | ".join("%s=%s" % (k, str(v)[:70]) for k, v in sorted(hd.items())
                                                 if re.search(r"(?i)^x-esri|rate|retry|cache-control|^age$|^server$|x-cache", k)), 700)


def stats(url, where, groupes):
    st = [{"statisticType": "count", "onStatisticField": "OBJECTID", "outStatisticFieldName": "n"},
          {"statisticType": "sum", "onStatisticField": "Shape__Area", "outStatisticFieldName": "a"}]
    t0 = time.time()
    d = query(url, where=where, outStatistics=json.dumps(st), groupByFieldsForStatistics=groupes, returnGeometry="false") or {}
    rows = [f["attributes"] for f in d.get("features") or []]
    P("  statistiques (%s ; groupes %s) : %d lignes en %.1f s%s" % (where, groupes, len(rows), time.time() - t0,
                                                                  " ; exceededTransferLimit" if d.get("exceededTransferLimit") else ""))
    return rows


def D():
    url = ETAT["fl"]
    rows = stats(url, "1=1", "CCOM,Comunidad_Autonoma,COBERTURA")
    if not rows:
        P("  repli : statistiques limitées aux 4 régions")
        rows = stats(url, "CCOM IN ('02','09','15','16')", "CCOM,Comunidad_Autonoma,COBERTURA")
    ETAT["rows"] = rows
    vals = collections.Counter()
    par_reg = collections.OrderedDict()
    for r in rows:
        vals[r.get("COBERTURA") or ""] += r["n"]
        k = (r.get("CCOM") or "", r.get("Comunidad_Autonoma") or "")
        e = par_reg.setdefault(k, [0, 0.0, 0, 0.0])
        e[0] += r["n"]
        e[1] += r["a"] or 0
        if not (r.get("COBERTURA") or ""):
            e[2] += r["n"]
            e[3] += r["a"] or 0
    jetons = collections.Counter()
    for v, n in vals.items():
        for j in v.split(";"):
            if j.strip():
                jetons[j.strip()] += n
    P("  valeurs distinctes de COBERTURA (toutes régions présentes dans la réponse) : %d, total %d entités" % (len(vals), sum(vals.values())))
    autres = [v for v in vals if not re.fullmatch(r"(?:[A-Z]\d{7}[0-9A-J];?)*", v)]
    P("  valeurs qui ne sont pas une liste de CIF séparés par « ; » : %d" % len(autres))
    for v, n in sorted(vals.items(), key=lambda x: -x[1]):
        P("     %9d  %r" % (n, ";".join(cif_affichable(j) for j in v.split(";")) if v else ""))
    P("  identifiants élémentaires : " + " ; ".join("%s (%d entités)" % (cif_affichable(j), n) for j, n in sorted(jetons.items())))
    ETAT["cifs"] = [j for j in sorted(jetons) if CIF_MORALE.match(j)]
    P("  par région (CCOM, nom, entités, dont COBERTURA vide, part de surface sans 4G en deg²) :")
    tot = [0, 0]
    for (cc, nom), e in sorted(par_reg.items()):
        marque = " <== région utile" if cc in REGIONS else ""
        P("     %-2s %-28s %8d entités ; vides %5d ; surface %.4f deg² ; sans 4G %.4f deg² = %.1f %%%s" % (
            cc, nom[:28], e[0], e[2], e[1], e[3], 100 * e[3] / e[1] if e[1] else 0, marque))
        if cc in REGIONS:
            tot[0] += e[0]
            tot[1] += e[2]
    P("  total des 4 régions utiles : %d entités, dont %d à COBERTURA vide, donc %d avec couverture" % (tot[0], tot[1], tot[0] - tot[1]))
    surf = sum(r["a"] or 0 for r in rows if (r.get("CCOM") or "") in REGIONS)
    for j in ETAT["cifs"]:
        n = sum(r["n"] for r in rows if (r.get("CCOM") or "") in REGIONS and j in (r.get("COBERTURA") or "").split(";"))
        a = sum(r["a"] or 0 for r in rows if (r.get("CCOM") or "") in REGIONS and j in (r.get("COBERTURA") or "").split(";"))
        P("     opérateur %s : %d entités, %.4f deg², soit %.1f %% de la surface des 4 régions" % (j, n, a, 100 * a / surf if surf else 0))
    for cc in REGIONS:
        c = query(url, where="CCOM='%s'" % cc, outFields="NATCODE", returnDistinctValues="true", returnCountOnly="true", returnGeometry="false") or {}
        P("     CCOM %s : %s NATCODE distincts" % (cc, c.get("count")))
    d = query(url, where="CCOM='16' AND COBERTURA<>'' AND Shape__Area<0.00000013 AND Shape__Area>0.00000011", outFields="OBJECTID,Shape__Area,Shape__Length",
              returnGeometry="true", resultRecordCount=1, orderByFields="OBJECTID") or {}
    for f in (d.get("features") or [])[:1]:
        rings = (f.get("geometry") or {}).get("rings") or []
        xs = sorted(set(round(p[0], 9) for r in rings for p in r))
        ys = sorted(set(round(p[1], 9) for r in rings for p in r))
        P("  une petite entité : aire=%.6g deg², périmètre=%.6g deg, %d anneau(x), x=%s, y=%s, sr=%s" % (
            f["attributes"].get("Shape__Area"), f["attributes"].get("Shape__Length"), len(rings), xs[:4], ys[:4], d.get("spatialReference")), 400)
        if len(xs) >= 2 and len(ys) >= 2:
            P("     pas en x : %.12f° ; pas en y : %.12f°" % (xs[1] - xs[0], ys[1] - ys[0]))


def E():
    if not ETAT["table"]:
        P("  aucune table d'opérateurs trouvée dans les expressions de la carte web")
        return
    i, idx = ETAT["table"]
    d = element(i, "table des opérateurs citée par la fenêtre d'information")
    url = "%s/%d" % (d.get("url"), idx)
    m = get_json(url + "?f=json") or {}
    P("  %s : name=%r type=%s champs=%s" % (url, m.get("name"), m.get("type"), [f["name"] for f in m.get("fields") or []]))
    c = query(url, where="1=1", returnCountOnly="true") or {}
    P("  lignes : %s" % c.get("count"))
    if ETAT["cifs"]:
        w = "OPERADOR IN (%s)" % ",".join("'%s'" % j for j in ETAT["cifs"])
        r = query(url, where=w, outFields="*", returnGeometry="false") or {}
        for f in r.get("features") or []:
            a = f["attributes"]
            if CIF_MORALE.match((a.get("OPERADOR") or "").strip()):
                P("     %s | %s | %s | %s" % (a.get("OPERADOR"), a.get("RAZON_SOCIAL"), a.get("PAGWEB"), a.get("TIPO")))
    r = query(url, where="UPPER(RAZON_SOCIAL) LIKE '%DIGI %' OR UPPER(RAZON_SOCIAL) LIKE 'DIGI%'", outFields="OPERADOR,RAZON_SOCIAL,TIPO", returnGeometry="false") or {}
    P("  lignes dont la raison sociale contient « DIGI » : %d" % len(r.get("features") or []))
    for f in (r.get("features") or [])[:5]:
        a = f["attributes"]
        if CIF_MORALE.match((a.get("OPERADOR") or "").strip()):
            P("     %s | %s | %s" % (a.get("OPERADOR"), a.get("RAZON_SOCIAL"), a.get("TIPO")))
    st = [{"statisticType": "count", "onStatisticField": "OBJECTID", "outStatisticFieldName": "n"}]
    r = query(url, where="1=1", outStatistics=json.dumps(st), groupByFieldsForStatistics="TIPO", returnGeometry="false") or {}
    P("  lignes par TIPO : %s" % {f["attributes"].get("TIPO"): f["attributes"].get("n") for f in r.get("features") or []})


POINTS = [
    ("Saragosse, plaza del Pilar (ville)", -0.8780, 41.6566),
    ("Barcelone, plaça de Catalunya (ville)", 2.1700, 41.3870),
    ("Pampelune, plaza del Castillo (ville)", -1.6432, 42.8169),
    ("Bilbao, plaza Moyúa (ville)", -2.9349, 43.2630),
    ("canyon d'Añisclo, fond (Aragon, isolé)", 0.0580, 42.5650),
    ("forêt d'Irati, vers Casas de Irati (Navarre, isolé)", -1.0986, 42.9869),
    ("Estany Llong, Aigüestortes (Catalogne, isolé)", 0.9520, 42.5730),
    ("vers le tunnel de San Adrián (parzonería, Pays basque)", -2.3178, 42.9367),
    ("plateau de Legaire, Entzia (Álava)", -2.3170, 42.8170),
    ("vers Lareo, Enirio-Aralar (Gipuzkoa)", -2.0990, 43.0010),
    ("Bardenas Reales, vers Castildetierra (Navarre)", -1.5120, 42.2086),
]


def F():
    url = ETAT["fl"]
    for nom, lon, lat in POINTS:
        d = query(url, where="1=1", geometry="%s,%s" % (lon, lat), geometryType="esriGeometryPoint", inSR="4258",
                  spatialRel="esriSpatialRelIntersects", outFields="OBJECTID,COBERTURA,Municipio,NATCODE,CCOM,Shape__Area", returnGeometry="false") or {}
        fs = d.get("features") or []
        desc = " || ".join("CCOM=%r Municipio=%r NATCODE=%r COBERTURA=%r aire=%.3g" % (
            a.get("CCOM"), a.get("Municipio"), a.get("NATCODE"), ";".join(cif_affichable(j) for j in (a.get("COBERTURA") or "").split(";") if j), a.get("Shape__Area") or 0)
            for a in (f["attributes"] for f in fs))
        P("  %-52s (%8.4f, %7.4f) : %d entité(s) %s" % (nom, lon, lat, len(fs), desc), 420)
    w = ("CCOM IN ('15','16') AND (Municipio LIKE '%Parzon%' OR Municipio LIKE '%Aralar%' OR Municipio LIKE '%Bardenas%' OR Municipio LIKE '%Urbasa%' "
         "OR Municipio LIKE '%Entzia%' OR Municipio LIKE '%Badaya%' OR Municipio LIKE '%Facer%' OR Municipio LIKE '%Comunidad%' OR Municipio LIKE '%Mancomunidad%' OR Municipio LIKE '%Sierra%')")
    d = query(url, where=w, outFields="CCOM,Municipio,NATCODE", returnDistinctValues="true", returnGeometry="false") or {}
    fs = d.get("features") or []
    P("  « communes » de Navarre ou du Pays basque dont le nom évoque un territoire non municipal : %d" % len(fs))
    for f in fs[:25]:
        a = f["attributes"]
        P("     CCOM=%s NATCODE=%s Municipio=%r" % (a.get("CCOM"), a.get("NATCODE"), a.get("Municipio")))


def G():
    ids = liens_arcgis(PAGE_CON, "portail Conectemos")
    ETAT["ids_con"] = ids
    orig = None
    for i in ids:
        d = get_json("%s/content/items/%s?f=json" % (SHARING, i)) or {}
        P("  %s : type=%s title=%r owner=%s created=%s modified=%s" % (i, d.get("type"), d.get("title"), d.get("owner"), jour(d.get("created")), jour(d.get("modified"))))
        if "xperience" in (d.get("type") or "") and re.search(r"(?i)m[oó]vil", d.get("title") or "") and i not in ETAT["exp"]:
            dd = get_json("%s/content/items/%s/data?f=json" % (SHARING, i)) or {}
            for k, v in (dd.get("dataSources") or {}).items():
                if v.get("type") == "WEB_MAP" and "4G" in (v.get("sourceLabel") or v.get("label") or ""):
                    wm = get_json("%s/content/items/%s/data?f=json" % (SHARING, v.get("itemId"))) or {}
                    for lyr in wm.get("operationalLayers") or []:
                        P("     carte web %s, couche [%s] %r url=%s" % (v.get("itemId"), lyr.get("layerType"), lyr.get("title"), lyr.get("url")))
                        if lyr.get("layerType") == "ArcGISFeatureLayer":
                            orig = lyr.get("url")
            acc = []
            chaines(dd.get("widgets"), acc)
            for m in re.finditer(r"referid[ao] a[^.<]{0,60}", plat(to_text(" ".join(acc)))):
                P("     texte de l'expérience d'origine : %s" % m.group(0))
    if not orig or orig == ETAT["fl"]:
        P("  pas de service d'origine distinct trouvé (orig=%s)" % orig)
        return
    ETAT["fl_orig"] = orig
    d = get_json(orig + "?f=json") or {}
    P("  service d'origine : name=%r editingInfo=%s capabilities=%s" % (d.get("name"), {k: jour(v) for k, v in (d.get("editingInfo") or {}).items()}, d.get("capabilities")))
    c = query(orig, where="1=1", returnCountOnly="true") or {}
    P("  service d'origine, nombre total d'entités : %s" % c.get("count"))
    a = {(r.get("COBERTURA") or ""): (r["n"], round(r["a"] or 0, 9)) for r in stats(orig, "CCOM='16'", "COBERTURA")}
    b = {(r.get("COBERTURA") or ""): (r["n"], round(r["a"] or 0, 9)) for r in ETAT.get("rows") or [] if (r.get("CCOM") or "") == "16"}
    P("  Pays basque, comparaison origine / copie liée par le ministère : %d et %d valeurs ; identiques (effectifs et surfaces) : %s" % (len(a), len(b), a == b))
    if a != b:
        for k in sorted(set(a) | set(b)):
            if a.get(k) != b.get(k):
                P("     écart %r : origine=%s copie=%s" % (k[:40], a.get(k), b.get(k)))


def H():
    for owner in ("coberturaBA_eu", "coberturaBA"):
        q = "owner:%s AND (4G OR Movil OR Móvil)" % owner
        d = get_json("%s/search?%s" % (SHARING, urllib.parse.urlencode({"q": q, "num": 100, "sortField": "modified", "sortOrder": "desc", "f": "json"}))) or {}
        res = d.get("results") or []
        P("  %s : %s éléments publics répondent à la recherche ; les plus récemment modifiés :" % (owner, d.get("total")))
        for r in res[:22]:
            P("     %s | %-18s | %-44s | créé %s | modifié %s" % (r.get("id"), (r.get("type") or "")[:18], (r.get("title") or "")[:44], jour(r.get("created")), jour(r.get("modified"))))


def I():
    st, hd, body, _ = get("https://digital.gob.es/nota-legal")
    if st == 200:
        t = plat(to_text(body.decode("utf-8", "replace")))
        b = t.rfind("Condiciones generales de reutilización")
        a = t.rfind("Condiciones generales de uso del portal web", 0, b)
        P("  section « Condiciones generales de uso del portal web » (positions %d à %d), texte :" % (a, b))
        if 0 <= a < b:
            P("     " + sans_courriel(t[a:b])[:4200], 4300)
            sec = t[a:b]
            P("     mots dans cette section : robot=%d, automatiz=%d, masiv=%d, extracci=%d, descarga=%d, prohib=%d" % tuple(
                len(re.findall(m, sec, flags=re.I)) for m in ("robot", "automatiz", "masiv", "extracci", "descarga", "prohib")))
    st, hd, body, _ = get("https://conectemos.digital.gob.es/es/aviso-legal")
    if st == 200:
        t = plat(to_text(body.decode("utf-8", "replace")))
        a = t.rfind("El dominio digital.gob.es es de titularidad")
        b = t.rfind("Se prohíbe la reproducción")
        P("  mentions légales de Conectemos, texte visible (positions %d à %d) :" % (a, b))
        if 0 <= a < b:
            P("     " + sans_courriel(t[a:b + 130])[:4200], 4300)
    st, hd, body, _ = get("https://conectemos.digital.gob.es/es/areas-de-interes/banda-ancha/informacion-de-cobertura")
    if st == 200:
        raw = body.decode("utf-8", "replace")
        t = plat(to_text(raw))
        a = t.rfind("La SETELECO publica también en su portal")
        P("  page « información de cobertura » de Conectemos, paragraphe sur les cartes :")
        if a >= 0:
            P("     " + t[a:a + 1500], 1600)
        liens = []
        for m in re.finditer(r'href=\\?"([^"\\]*mapas-y-graficos[^"\\]*)', raw):
            u = html.unescape(m.group(1))
            if u not in liens:
                liens.append(u)
        P("  liens vers des pages de cartes : %s" % liens[:12], 900)
        ETAT["pages_cartes"] = liens


def K():
    vus = set(ETAT.get("ids_min") or []) | set(ETAT.get("ids_con") or [])
    n = 0
    for u in ETAT.get("pages_cartes") or []:
        u = re.sub(r"^/content/seteleco-portal-connect/language-masters", "", u).replace(".html", "")
        if u.startswith("/"):
            u = "https://conectemos.digital.gob.es" + u
        if "servicios-de-banda-ancha" in u or n >= 5 or not u.startswith("https://conectemos.digital.gob.es/"):
            continue
        n += 1
        st, hd, body, _ = get(u)
        if st != 200:
            continue
        raw = body.decode("utf-8", "replace")
        t = plat(to_text(raw))
        for m in list(re.finditer(r"(?i)30 de junio de 20\d\d", t))[:2]:
            P("     date citée : … %s …" % t[max(0, m.start() - 110):m.end() + 60])
        ids = []
        for m in re.finditer(r"arcgis\.com[^\"'\\ <>]*?([0-9a-f]{32})", raw):
            if m.group(1) not in ids:
                ids.append(m.group(1))
        for i in ids[:6]:
            d = get_json("%s/content/items/%s?f=json" % (SHARING, i)) or {}
            neuf = "" if i in vus else "  <== pas vu sur les pages précédentes"
            P("     %s : type=%s title=%r owner=%s créé %s modifié %s%s" % (i, d.get("type"), d.get("title"), d.get("owner"), jour(d.get("created")), jour(d.get("modified")), neuf))
            vus.add(i)


bloc("A. Page du ministère : liens vers les cartes", A)
bloc("B. Expérience liée, textes, cartes web, couches", B)
bloc("C. Couche d'entités 4G : métadonnées", C)
bloc("D. Valeurs de COBERTURA, régions, surfaces (une requête de statistiques)", D)
bloc("E. Table des opérateurs", E)
bloc("F. Points de contrôle et territoires non municipaux", F)
bloc("G. Portail Conectemos et service d'origine : mêmes données ?", G)
bloc("H. Édition plus récente sur les comptes ArcGIS ?", H)
bloc("I. Compléments : conditions d'usage du portail du ministère, mentions légales et page de Conectemos", I)
bloc("K. Autres pages de cartes de Conectemos : une édition 2025 de la carte mobile détaillée ?", K)
bilan()
PY_FIN_SONDE
echo "FIN (code python : $?)"
