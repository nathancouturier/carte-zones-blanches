#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Italie : AGCOM », sonde it-v1.
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

# Sonde it-v1 : licence relue à la source, portail open data, catalogue REST, service 4G, comptages, pagination.
# Aucune géométrie n'est téléchargée ici : seulement des pages, des scripts publics et de petites réponses JSON.

GEO3 = "https://geo3.agcom.it"
REST = GEO3 + "/MapET-SFS/rest/services"
L4G = REST + "/Grid100/mobile_4G/MapServer"


def section_robots():
    P("##### 1. robots.txt des hôtes interrogés (lu avant toute autre requête)")
    for host in ("www.agcom.it", "geo3.agcom.it", "geo.agcom.it", "maps.agcom.it"):
        rp, st, ok, txt, ctype = robots_for(host)
        if ok:
            lines = [l.strip() for l in txt.splitlines() if l.strip() and not l.strip().startswith("#")]
            P("  %s/robots.txt : code %s, %d lignes utiles" % (host, st, len(lines)))
            for l in lines[:14]:
                P("      " + l[:200])
            if len(lines) > 14:
                P("      ... (%d lignes de plus)" % (len(lines) - 14))
        else:
            P("  %s/robots.txt : code %s, type %s, pas un fichier robots (début : %r)" % (host, st, ctype[:30], flat(txt[:90])))
    for url in (GEO3 + "/opendata/", REST + "?f=json", L4G + "/0/query?where=1%3D1&f=json", "https://www.agcom.it/termini-e-condizioni"):
        P("  autorisé pour « %s » : %s  %s" % (UA, allowed(url), url))


def section_conditions():
    P("##### 2. Conditions d'utilisation, texte intégral relu à la source")
    r = get("https://www.agcom.it/termini-e-condizioni")
    if r is None or r[0] != 200:
        return ""
    page = r[2].decode("utf-8", "replace")
    txt = to_text(page)
    i = txt.find("Aspetti generali")
    j = txt.find("Data ultimo aggiornamento", max(i, 0))
    main = txt[max(i, 0):(j + 45) if j > 0 else max(i, 0) + 6000]
    P("  texte principal : %d caractères (de « Aspetti generali » à « Data ultimo aggiornamento »)" % len(main))
    wrap(main)
    low = main.lower()
    P("  mots-clés cherchés dans ce texte :")
    absent = []
    for kw in ("automat", "scraping", "massiv", "robot", "api", "servizi web", "web service", "scaric", "download", "commercial",
               "vietat", "non è consentit", "autorizzazion", "condizione", "logo", "violazione", "accesso"):
        hits = [m.start() for m in re.finditer(re.escape(kw), low)]
        if hits:
            k = hits[0]
            P("      « %s » x%d : ...%s..." % (kw, len(hits), flat(main[max(0, k - 70):k + 110])))
        else:
            absent.append(kw)
    P("      absents du texte : %s" % ", ".join(absent))
    k = page.find("seguente logo")
    if k > 0:
        after = page[k:k + 1400]
        for tag in re.findall(r"(?is)<img\b[^>]*>", after)[:3]:
            P("  image qui suit « seguente logo » : " + flat(tag)[:260])
        for a in re.findall(r"(?is)<a\b[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", after)[:4]:
            P("  lien qui suit « seguente logo » : %s | %s" % (a[0][:120], flat(to_text(a[1]))[:100]))
    return main


def section_adresses(main):
    P("##### 3. Adresse du portail citée par les conditions, pages officielles, logo")
    m = re.search(r"disponibile all'indirizzo\s+(\S+)", main)
    P("  adresse citée dans le texte : %s" % (m.group(1) if m else "(non trouvée)"))
    for url in ("https://www.agcom.it/broadbandmap", "https://www.agcom.it/broadband-map"):
        r = get(url)
        if r and r[0] == 200:
            page = r[2].decode("utf-8", "replace")
            for href, lab in re.findall(r"(?is)<a\b[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", page):
                if re.search(r"(?i)maps\.agcom|geo\d?\.agcom|opendata|termini|open-data|dati", href):
                    P("      lien : %s | %s" % (href[:140], flat(to_text(lab))[:80]))
    r = get("https://www.agcom.it/mappatura-delle-reti-di-accesso-ad-internet")
    if r and r[0] == 200:
        page = r[2].decode("utf-8", "replace")
        txt = to_text(page)
        for sent in re.split(r"(?<=[.!?])\s+", flat(txt)):
            if re.search(r"(?i)\b(open|scaricabil|licenza|2G|cellulari|opendata)\b", sent) and len(sent) < 700:
                P("      phrase : " + sent[:290])
        for href, lab in re.findall(r"(?is)<a\b[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", page):
            if re.search(r"(?i)maps\.agcom|geo\d?\.agcom|opendata|termini", href):
                P("      lien : %s | %s" % (href[:140], flat(to_text(lab))[:80]))
    logo = "https://www.agcom.it/sites/default/files/inline-images/licenza%20uso%20mappatura%20reti.jpg"
    r = get(logo)
    if r and r[0] == 200:
        path = os.path.join(T, "logo.jpg")
        open(path, "wb").write(r[2])
        try:
            from osgeo import gdal
            ds = gdal.Open(path)
            P("      logo : pilote %s, %d x %d pixels" % (ds.GetDriver().ShortName, ds.RasterXSize, ds.RasterYSize))
        except Exception as e:
            P("      logo : lecture impossible (%r)" % e)
    r = get("https://maps.agcom.it/")
    if r:
        P("      maps.agcom.it : " + flat(to_text(r[2].decode("utf-8", "replace")))[:200])


def section_portail(main):
    P("##### 4. Portail open data geo3.agcom.it/opendata : scripts, téléchargement mobile, conditions")
    r = get(GEO3 + "/opendata/")
    if r is None or r[0] != 200:
        return
    page = r[2].decode("utf-8", "replace")
    srcs = re.findall(r"(?is)<script\b[^>]*\bsrc=[\"']([^\"']+)[\"']", page)
    own = [s for s in srcs if not re.match(r"(?i)(https?:)?//", s)]
    P("  scripts : %d dont %d propres au portail : %s" % (len(srcs), len(own), ", ".join(own)[:230]))
    P("  titre : " + flat(to_text("".join(re.findall(r"(?is)<title>.*?</title>", page))))[:120])
    js = {}
    for name in ("js/app.js", "js/translations.js", "js/map-mobile.js"):
        rr = get(urllib.parse.urljoin(GEO3 + "/opendata/", name))
        js[name] = rr[2].decode("utf-8", "replace") if rr and rr[0] == 200 else ""

    # 4a. translations.js : conditions et textes du téléchargement mobile
    tr = js["js/translations.js"]
    P("  -- translations.js (%d octets)" % len(tr))
    langs = [(m.start(), m.group(1)) for m in re.finditer(r"(?<![\w$])[\"']?(it|en|fr|de|es)[\"']?\s*:\s*\{", tr)]
    P("     blocs de langue repérés : %s" % [(l, p) for p, l in langs])

    def lang_at(pos):
        cur = "?"
        for p, l in langs:
            if p <= pos:
                cur = l
        return cur

    terms = []
    for m in re.finditer(r"\bcontentTerms\w*[\"']?\s*:", tr):
        lit, _ = js_literal(tr, m.end())
        terms.append((lang_at(m.start()), m.group(0).strip(" :\"'"), lit))
    for lang, key, lit in terms:
        P("     clé %s (langue %s) : %d caractères" % (key, lang, len(lit)))
    sentences = (
        "Tutti i dati del Portale BBMap sono rilasciati sotto licenza Creative Commons Attribuzione 4.0 Internazionale",
        "a condizione che vengano citate la paternità dei dati e l'indirizzo del Portale BBMap",
        "dovrà essere riportato il seguente logo",
        "È vietato l'uso o la pubblicazione dei dati del Portale BBMap",
        "cambiare i termini e le condizioni di accesso in qualsiasi momento",
    )
    it_terms = next((to_text(lit) for lang, key, lit in terms if lang in ("it", "?")), "")
    for s in sentences:
        P("     phrase %-5s dans www.agcom.it | %-5s dans translations.js : « %s »" % (norm(s) in norm(main), norm(s) in norm(it_terms), s[:150]))
    if it_terms and main:
        a, b = norm(main), norm(it_terms)
        P("     ressemblance des deux textes (difflib) : %.3f ; longueurs %d et %d" % (difflib.SequenceMatcher(None, a, b, autojunk=False).ratio(), len(a), len(b)))
        ia = norm(it_terms).find("licenza")
        P("     conditions du portail open data (italien), début :")
        wrap(it_terms, limit=1100, indent="       ")
        k = it_terms.find("Licenza")
        if k > 0:
            P("     ... section « Licenza » du portail open data :")
            wrap(it_terms[k:], limit=1500, indent="       ")
    keys = []
    for m in re.finditer(r"(?m)^\s*[\"']?([A-Za-z_]\w*)[\"']?\s*:\s*[\"'`]", tr):
        if m.group(1) not in keys:
            keys.append(m.group(1))
    wanted = [k for k in keys if re.search(r"(?i)download|mobile|opendata|info|note|legend", k)]
    P("     %d clés au total ; clés liées au téléchargement, au mobile, aux notes : %s" % (len(keys), ", ".join(wanted)[:260]))
    shown = 0
    for k in wanted:
        if not re.search(r"(?i)mobile|download", k) or shown >= 9:
            continue
        m = re.search(r"(?m)^\s*[\"']?%s[\"']?\s*:" % re.escape(k), tr)
        lit, _ = js_literal(tr, m.end())
        P("     [%s, %s] %s" % (k, lang_at(m.start()), mask(flat(to_text(lit)))[:560]))
        shown += 1
    for m in list(re.finditer(r"(?i)infrastruttur\w*", tr))[:4]:
        P("     contexte « infrastruttur » : ..." + mask(flat(to_text(tr[max(0, m.start() - 160):m.start() + 200])))[:285])

    # 4b. app.js : fonctions de téléchargement
    app = js["js/app.js"]
    P("  -- app.js (%d octets)" % len(app))
    names = sorted(set(re.findall(r"\b([A-Za-z_$][\w$]*[Dd]ownload[\w$]*)\b", app)))
    P("     identifiants contenant « download » : %s" % ", ".join(names)[:270])
    for name in [n for n in names if re.match(r"(?i)generateDownload|getContentDownload", n)]:
        pos = find_def(app, name)
        if pos is None:
            P("     %s : pas de définition trouvée" % name)
            continue
        body = flat(js_block(app, pos))
        urls = sorted(set(re.findall(r"[\"'`]((?:https?:)?//[^\"'`\s]+|[^\"'`\s]*\.ashx[^\"'`\s]*)[\"'`]", body)))
        P("     %s : %d caractères ; getdownloadrequest x%d ; mailto x%d ; opendata.bbmap@agcom.it x%d ; URL : %s" % (
            name, len(body), body.count("getdownloadrequest"), body.count("mailto:"), body.count("opendata.bbmap@agcom.it"), mask(", ".join(urls))[:120]))
        if name == "generateDownloadMobileRequest":
            wrap(mask(body), limit=1700, indent="       ")
        if name == "getContentDownloadReteMobile":
            wrap(mask(body), limit=900, indent="       ")
    lits = []
    for m in re.finditer(r"[\"'`]([^\"'`\n]{3,220})[\"'`]", app):
        s = m.group(1)
        if re.search(r"(?i)^(https?:)?//|\.ashx|rest/services|\.(zip|csv|gpkg|shp|geojson|xlsx?|7z|gz|pdf|json)(\?|$)|mailto:|@agcom", s) and s not in lits:
            lits.append(s)
    P("     littéraux d'URL, de fichier ou d'adresse (%d) :" % len(lits))
    for s in lits[:26]:
        P("       " + mask(s.split("?")[0])[:200])
    for pat in ("window.open", "location.href", ".download", "Blob(", "saveAs", "getdownloadrequest", "ACTION"):
        P("     occurrences de « %s » : %d" % (pat, app.count(pat)))

    # 4c. map-mobile.js : services utilisés par la carte (aucune ligne brute n'est affichée)
    mm = js["js/map-mobile.js"]
    P("  -- map-mobile.js (%d octets)" % len(mm))
    lits = []
    for m in re.finditer(r"[\"'`]([^\"'`\n]{3,260})[\"'`]", mm):
        s = m.group(1).split("?")[0]
        if re.search(r"(?i)^(https?:)?//|rest/services", s) and s not in lits:
            lits.append(s)
    for s in lits[:14]:
        P("       URL : " + mask(s)[:200])
    for pat in ("tiledMapLayer", "featureLayer", "dynamicMapLayer", ".query(", "identify", "Grid100/", "find("):
        P("     occurrences de « %s » : %d" % (pat, mm.count(pat)))
    for label, src in (("page du portail", page), ("map-mobile.js", mm)):
        seen = 0
        for m in re.finditer(r"(?i)infrastruttur\w*|copertur\w*|coverage", src):
            if seen >= 3:
                break
            ctx = mask(flat(to_text(src[max(0, m.start() - 150):m.start() + 190])))
            P("     %s, contexte « %s » : ...%s" % (label, m.group(0), ctx[:250]))
            seen += 1
        if not seen:
            P("     %s : aucun texte sur les infrastructures ou la couverture" % label)


def section_catalogue():
    P("##### 5. Catalogue ArcGIS REST de geo3.agcom.it (tous les dossiers)")
    root = get_json(REST + "?f=json")
    if not root:
        return
    P("  currentVersion=%s dossiers=%s services racine=%s" % (root.get("currentVersion"), root.get("folders"), [s.get("name") for s in root.get("services", [])]))
    allnames = [(s.get("name"), s.get("type")) for s in root.get("services", [])]
    for folder in root.get("folders", []):
        d = get_json("%s/%s?f=json" % (REST, urllib.parse.quote(folder)))
        svcs = [(s.get("name"), s.get("type")) for s in (d or {}).get("services", [])]
        allnames += svcs
        short = ", ".join("%s (%s)" % (n.split("/")[-1], t.replace("Server", "")) for n, t in svcs)
        P("  %-13s %2d services : %s" % (folder, len(svcs), short[:240]))
    pat = re.compile(r"(?i)(?<![a-z0-9])(2g|3g|gsm|umts|hspa|voce|voice|tim|vodafone|wind|windtre|iliad|fastweb|operator\w*)(?![a-z0-9])")
    hits = [n for n, _ in allnames if pat.search(n.replace("_", " "))]
    mob = [n for n, _ in allnames if re.search(r"(?i)mobile|4g|5g|lte", n)]
    P("  %d services au total ; noms évoquant 2G, 3G, voix ou un opérateur : %s" % (len(allnames), hits or "aucun"))
    P("  noms évoquant le mobile : %s" % mob)


def section_service():
    P("##### 6. Service Grid100/mobile_4G : description, couche 0, légende")
    svc = get_json(L4G + "?f=json") or {}
    for k in ("currentVersion", "serviceDescription", "description", "copyrightText", "capabilities", "maxRecordCount", "supportedQueryFormats",
              "singleFusedMapCache", "exportTilesAllowed", "spatialReference", "documentInfo"):
        P("  %s: %s" % (k, json.dumps(svc.get(k), ensure_ascii=False)[:230]))
    P("  layers: %s | tables: %s" % ([(l.get("id"), l.get("name")) for l in svc.get("layers", [])], svc.get("tables")))
    lay = get_json(L4G + "/0?f=json") or {}
    for k in ("name", "type", "geometryType", "description", "copyrightText", "capabilities", "maxRecordCount", "objectIdField", "displayField",
              "supportedQueryFormats", "advancedQueryCapabilities", "extent"):
        P("  couche 0 %s: %s" % (k, json.dumps(lay.get(k), ensure_ascii=False)[:230]))
    P("  couche 0 champs: %s" % [(f.get("name"), f.get("type"), f.get("alias")) for f in lay.get("fields", [])])
    rend = (lay.get("drawingInfo") or {}).get("renderer") or {}
    P("  rendu: type=%s champ=%s valeurs=%s" % (rend.get("type"), rend.get("field1"), [(u.get("value"), u.get("label"), (u.get("symbol") or {}).get("color")) for u in rend.get("uniqueValueInfos", [])]))
    leg = get_json(L4G + "/legend?f=json") or {}
    for l in leg.get("layers", [])[:2]:
        P("  légende couche %s « %s » : %s" % (l.get("layerId"), l.get("layerName"), [x.get("label") for x in l.get("legend", [])]))
    r = get(L4G + "/0/query?where=1%3D1&returnCountOnly=true&f=json", quiet=True)
    if r:
        hd = r[1]
        P("  en-têtes d'une réponse query : %s" % {k: hd[k][:60] for k in hd if k.lower() in ("server", "x-powered-by", "access-control-allow-origin", "cache-control", "content-type", "www-authenticate")})
        P("  réponse sans jeton : code %s, corps %s" % (r[0], r[2][:80].decode("utf-8", "replace")))

    P("##### 7. Comptages côté serveur (aucune géométrie)")
    Q = L4G + "/0"
    stat = json.dumps([{"statisticType": "count", "onStatisticField": "fid", "outStatisticFieldName": "nb"}])
    P("  total Italie : %s" % query(Q, where="1=1", returnCountOnly="true"))
    P("  COD_REG IN (1,2,7) : %s" % query(Q, where="COD_REG IN (1,2,7)", returnCountOnly="true"))
    P("  valeurs hors de 1 à 4 ou nulles : %s" % query(Q, where="n_infrastrutture_totali NOT IN (1,2,3,4) OR n_infrastrutture_totali IS NULL", returnCountOnly="true"))
    d = query(Q, where="1=1", outStatistics=stat, groupByFieldsForStatistics="n_infrastrutture_totali") or {}
    P("  Italie, entités par valeur : %s" % sorted((f["attributes"].get("n_infrastrutture_totali"), f["attributes"].get("nb")) for f in d.get("features", [])))
    d = query(Q, where="COD_REG IN (1,2,7)", outStatistics=stat, groupByFieldsForStatistics="COD_REG,n_infrastrutture_totali") or {}
    tab = collections.defaultdict(dict)
    for f in d.get("features", []):
        a = f["attributes"]
        tab[a.get("COD_REG")][a.get("n_infrastrutture_totali")] = a.get("nb")
    for reg in sorted(tab):
        P("  COD_REG %s : total %s, par valeur %s" % (reg, sum(tab[reg].values()), dict(sorted(tab[reg].items()))))
    d = query(REST + "/Limiti/regioni/MapServer/0", where="COD_REG IN (1,2,7)", outFields="COD_REG,DEN_REG", returnGeometry="false") or {}
    P("  Limiti/regioni : %s" % sorted((f["attributes"].get("COD_REG"), f["attributes"].get("DEN_REG")) for f in d.get("features", [])))
    d = query(REST + "/Grid100/data_pubblicazione/FeatureServer/0", where="1=1", outFields="*", returnGeometry="false") or {}
    P("  data_pubblicazione : %s" % [f.get("attributes") for f in d.get("features", [])])

    P("##### 8. Pagination et structure, sur la Vallée d'Aoste (COD_REG=2), sans géométrie")
    base = dict(where="COD_REG=2", outFields="fid,PRO_COM_T,n_infrastrutture_totali", returnGeometry="false", orderByFields="fid")
    ref = query(Q, **base) or {}
    rows = [f["attributes"] for f in ref.get("features", [])]
    fids = [a["fid"] for a in rows]
    P("  requête unique : %d lignes, %d fid distincts, fid de %s à %s, exceededTransferLimit=%s" % (len(rows), len(set(fids)), min(fids or [0]), max(fids or [0]), ref.get("exceededTransferLimit")))
    pairs = collections.Counter((a["PRO_COM_T"], a["n_infrastrutture_totali"]) for a in rows)
    P("  couples (commune, valeur) : %d distincts pour %d lignes ; communes distinctes : %d ; préfixes de PRO_COM_T : %s" % (
        len(pairs), len(rows), len(set(a["PRO_COM_T"] for a in rows)), dict(collections.Counter(str(a["PRO_COM_T"])[:3] for a in rows))))
    P("  exemples : %s" % rows[:3])
    pages = []
    for off in (0, 100):
        d = query(Q, resultOffset=off, resultRecordCount=100, **base) or {}
        ids = [f["attributes"]["fid"] for f in d.get("features", [])]
        pages.append(ids)
        P("  resultOffset=%d, resultRecordCount=100 : %d lignes, fid de %s à %s, exceededTransferLimit=%s" % (off, len(ids), min(ids or [0]), max(ids or [0]), d.get("exceededTransferLimit")))
    P("  les deux pages sont identiques : %s ; attendu si resultOffset fonctionnait : page 2 = lignes 101 à 200 de la requête unique : %s" % (pages[0] == pages[1], pages[1] == fids[100:200]))
    d = query(Q, where="COD_REG IN (1,2,7)", returnIdsOnly="true") or {}
    P("  returnIdsOnly sur les trois régions : objectIdFieldName=%s, %d identifiants (4 697 attendus)" % (d.get("objectIdFieldName"), len(d.get("objectIds") or [])))
    last, seen, n = 0, [], 0
    while n < 6:
        d = query(Q, where="COD_REG=2 AND fid > %d" % last, outFields="fid", returnGeometry="false", orderByFields="fid", resultRecordCount=100) or {}
        ids = [f["attributes"]["fid"] for f in d.get("features", [])]
        n += 1
        if not ids:
            break
        seen += ids
        last = max(ids)
        if len(ids) < 100:
            break
    P("  pagination par fid croissant, pages de 100 : %d requêtes, %d lignes, %d fid distincts, mêmes fid que la requête unique : %s" % (n, len(seen), len(set(seen)), sorted(seen) == sorted(fids)))
    if fids:
        r = get(Q + "/query?" + urllib.parse.urlencode(dict(where="fid=%d" % fids[0], outFields="fid", returnGeometry="false", f="geojson")), quiet=True)
        if r:
            P("  f=geojson : code %s, type %s, début %s" % (r[0], (r[1].get("Content-Type") or "")[:40], flat(r[2][:150].decode("utf-8", "replace"))))


def main():
    section_robots()
    main_txt = section_conditions()
    section_adresses(main_txt)
    section_portail(main_txt)
    if allowed(REST + "?f=json"):
        section_catalogue()
        section_service()
    else:
        P("##### 5 à 8 : sautées, robots.txt interdit le service REST à ce client")
    bilan()


if __name__ == "__main__":
    main()
PY_FIN_SONDE
echo "FIN (code python : $?)"
