#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Italie : AGCOM », sonde it-v3.
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

# Sonde it-v3 : recherche d'une couche 2G, 3G ou par opérateur que le rapport aurait manquée.
# Recensement des couches (et non des seuls noms de services) du second serveur, cartes web du portail ArcGIS,
# page de la carte principale (en direct et archivée), éditeur AGCOM dans le catalogue national.
# Charge : petites réponses JSON de description, aucune géométrie.

GEO = "https://geo.agcom.it"
REST2 = GEO + "/server/rest/services"
SHARING = GEO + "/arcgis/sharing/rest"
MOB = re.compile(r"(?i)mobil|radiomobil|cellul|(?<![a-z0-9])(2g|3g|4g|5g|lte|umts|gsm|hspa|nr|voce|voice|tim|telecom|vodafone|wind|windtre|wind3|iliad|fastweb|operator\w*)(?![a-z0-9])")


def section_couches():
    P("##### 1. Second serveur : couches de chaque service (les noms de services ne suffisent pas)")
    root = get_json(REST2 + "?f=json") or {}
    svcs = [(s.get("name"), s.get("type")) for s in root.get("services", [])]
    for folder in root.get("folders", []):
        d = get_json("%s/%s?f=json" % (REST2, urllib.parse.quote(folder))) or {}
        svcs += [(s.get("name"), s.get("type")) for s in d.get("services", [])]
    hors = re.compile(r"(?i)_stage$|^Test|scuole|voucher|cabine|catasto|polimi|prossimita|AppMobile2602")
    P("  services écartés d'après leur nom (doublons « stage », essais, écoles, bons, cabines, cadastre, service déjà décrit) : %s" % ", ".join(sorted(set(n.split("/")[-1] for n, t in svcs if hors.search(n.split("/")[-1]))))[:250])
    todo = [(n, t) for n, t in svcs if t in ("MapServer", "FeatureServer") and not hors.search(n.split("/")[-1])]
    # un seul type par service : MapServer de préférence
    names = {}
    for n, t in todo:
        if n not in names or t == "MapServer":
            names[n] = t
    P("  %d services publiés, %d décrits ici (hors doublons « stage » et essais)" % (len(svcs), len(names)))
    flagged = []
    for n in sorted(names):
        base = "%s/%s/%s" % (REST2, n, names[n])
        d = get_json(base + "?f=json")
        if d is None:
            continue
        if "error" in d:
            P("  %s : erreur %s" % (n, str(d["error"])[:120]))
            continue
        layers = [(l.get("id"), l.get("name") or "") for l in (d.get("layers") or []) + (d.get("tables") or [])]
        hits = [(i, nm) for i, nm in layers if MOB.search(nm.replace("_", " "))]
        info = "%s %s" % ((d.get("documentInfo") or {}).get("Subject") or "", flat(to_text(d.get("serviceDescription") or d.get("description") or ""))[:70])
        P("  %s (%s, %d couches) %s : %s" % (n, names[n].replace("Server", ""), len(layers), info.strip(), "; ".join("%s %s" % (i, nm) for i, nm in layers)[:200]))
        if len("; ".join(nm for _, nm in layers)) > 190:
            wrap("; ".join("%s %s" % (i, nm) for i, nm in layers)[200:], limit=1400, indent="        ")
        for i, nm in hits:
            flagged.append((n, base, i, nm))
    P("  couches dont le nom évoque le mobile, une technologie radio ou un opérateur : %d" % len(flagged))
    done = 0
    for n, base, i, nm in flagged:
        if done >= 6:
            P("    (non détaillée) %s / %s « %s »" % (n, i, nm))
            continue
        done += 1
        lay = get_json("%s/%s?f=json" % (base, i)) or {}
        cnt = query("%s/%s" % (base, i), where="1=1", returnCountOnly="true") or {}
        smp = query("%s/%s" % (base, i), where="1=1", outFields="*", returnGeometry="false", resultRecordCount=2) or {}
        rend = (lay.get("drawingInfo") or {}).get("renderer") or {}
        P("    %s / %s « %s » : %s, %s entités, champs %s" % (n, i, nm, lay.get("geometryType"), cnt.get("count"), [f.get("name") for f in lay.get("fields") or []][:14]))
        P("        rendu %s sur %s : %s" % (rend.get("type"), rend.get("field1") or rend.get("field"), [u.get("label") for u in rend.get("uniqueValueInfos", [])][:8] or [c.get("label") for c in rend.get("classBreakInfos", [])][:8]))
        P("        exemple : %s" % json.dumps([f.get("attributes") for f in smp.get("features", [])][:1], ensure_ascii=False)[:250])


def walk_layers(layers, depth=0):
    for l in layers or []:
        yield depth, l
        for x in walk_layers(l.get("layers"), depth + 1):
            yield x


def section_cartes_web():
    P("##### 2. Portail ArcGIS : cartes web publiques de l'AGCOM et couches qu'elles affichent")
    d = get_json(SHARING + "/search?" + urllib.parse.urlencode(dict(q='type:"Web Map"', num=60, f="json", sortField="modified", sortOrder="desc"))) or {}
    res = [it for it in d.get("results", []) if it.get("type") == "Web Map"]
    P("  %s cartes web (total annoncé %s) : %s" % (len(res), d.get("total"), "; ".join("%s [%s]" % (it.get("title"), time.strftime("%Y-%m", time.gmtime((it.get("modified") or 0) / 1000))) for it in res)[:240]))
    if len(res) > 6:
        wrap("; ".join("%s [%s]" % (it.get("title"), time.strftime("%Y-%m", time.gmtime((it.get("modified") or 0) / 1000))) for it in res)[240:], limit=900, indent="      ")
    chosen = [it for it in res if re.search(r"(?i)mobile", it.get("title") or "")][:2]
    chosen += [it for it in res if it not in chosen and re.search(r"(?i)agcom|bbmap|broadband", (it.get("title") or "") + " " + (it.get("snippet") or ""))][:2]
    urls = []
    for it in chosen:
        P("  -- carte « %s » (%s, propriétaire masqué, modifiée %s) : licenseInfo=%r accessInformation=%r description=%r" % (
            it.get("title"), it.get("id"), time.strftime("%Y-%m-%d", time.gmtime((it.get("modified") or 0) / 1000)),
            flat(to_text(it.get("licenseInfo") or ""))[:80], (it.get("accessInformation") or "")[:60], flat(to_text(it.get("description") or ""))[:100]))
        data = get_json("%s/content/items/%s/data?f=json" % (SHARING, it.get("id"))) or {}
        ops = list(walk_layers(data.get("operationalLayers")))
        P("     %d couches opérationnelles ; fond : %s" % (len(ops), ((data.get("baseMap") or {}).get("title"))))
        for depth, l in ops[:22]:
            u = (l.get("url") or "").split("?")[0]
            if u and u not in urls:
                urls.append(u)
            pop = l.get("popupInfo") or {}
            labels = [fi.get("label") for fi in pop.get("fieldInfos", []) if fi.get("visible")][:6]
            P("     %s« %s » %s visible=%s %s%s" % ("  " * depth, (l.get("title") or "")[:60], l.get("layerType"), l.get("visibility"), mask(u.replace(REST2, "…"))[:110],
                                                  (" | fiche : %s %s" % (flat(to_text(pop.get("title") or ""))[:50], labels)) if pop else ""))
    return urls


def section_carte_principale():
    P("##### 3. Page de la carte principale maps.agcom.it : en direct, puis copie archivée")
    r = get("https://maps.agcom.it/")
    live = r[2].decode("utf-8", "replace") if r and r[0] == 200 else ""
    attrs = []
    for m in re.finditer(r"(?i)\b(?:href|src|action|data-url)\s*=\s*[\"']([^\"'#][^\"']*)[\"']", live):
        if m.group(1) not in attrs:
            attrs.append(m.group(1))
    P("  page en direct : %d octets, %d commentaires HTML, attributs href/src (%d) : %s" % (len(live), live.count("<!--"), len(attrs), mask("; ".join(a.split("?")[0] for a in attrs))[:230]))
    P("  texte hors commentaires : " + flat(to_text(re.sub(r"(?s)<!--.*?-->", " ", live)))[:200])
    best = None
    for ts in ("20260922131122", "20260601", "20251201"):
        d = get_json("https://archive.org/wayback/available?url=maps.agcom.it&timestamp=%s" % ts) or {}
        snap = (d.get("archived_snapshots") or {}).get("closest") or {}
        if not snap.get("timestamp"):
            continue
        raw = "https://web.archive.org/web/%sid_/https://maps.agcom.it/" % snap["timestamp"]
        rr = get(raw)
        if not rr or rr[0] != 200:
            continue
        page = rr[2].decode("utf-8", "replace")
        maint = "manutenzione" in page.lower()
        srcs = re.findall(r"(?is)<script\b[^>]*\bsrc=[\"']([^\"']+)[\"']", page)
        P("  copie du %s : %d octets, en maintenance : %s, %d scripts : %s" % (snap["timestamp"], len(page), maint, len(srcs), mask("; ".join(s.split("?")[0] for s in srcs))[:200]))
        if not maint or srcs:
            best = (snap["timestamp"], page, srcs)
            break
    if not best:
        P("  aucune copie exploitable de la page (toutes en maintenance ou sans script)")
        return
    ts, page, srcs = best
    texts = [("page", page)]
    skip = re.compile(r"(?i)jquery|bootstrap|leaflet\.js|leaflet-src|esri-leaflet|proj4|popper|fontawesome|chart|d3\.|moment|toastr|select2|datatables|easing|polyfill|arcgis\.com|googleapis|cloudflare|gstatic")
    for s in [s for s in srcs if not skip.search(s)][:5]:
        full = urllib.parse.urljoin("https://maps.agcom.it/", s)
        rr = get("https://web.archive.org/web/%sid_/%s" % (ts, full))
        if rr and rr[0] == 200:
            texts.append((s, rr[2].decode("utf-8", "replace")))
    P("  texte de la copie : " + flat(to_text(page))[:260])
    urls = []
    for name, txt in texts:
        for m in re.finditer(r"[\"'`]((?:https?:)?//[^\"'`\s]{6,240}|[^\"'`\s]{0,80}(?:rest/services|\.ashx|/wms|/wfs|geoserver)[^\"'`\s]{0,160})[\"'`]", txt):
            u = m.group(1).split("?")[0]
            if re.search(r"(?i)agcom|rest/services|ashx|wms|wfs|geoserver", u) and u not in urls:
                urls.append(u)
    P("  adresses citées par la copie et ses scripts (%d) :" % len(urls))
    for u in urls[:24]:
        P("      " + mask(u)[:200])
    for kw in ("2G", "3G", "4G", "5G", "GSM", "UMTS", "LTE", "operator", "Operator", "infrastrutture"):
        hits = {name[-36:]: len(re.findall(r"(?<![A-Za-z0-9])%s(?![a-z0-9])" % re.escape(kw), txt)) for name, txt in texts}
        hits = {k: v for k, v in hits.items() if v}
        if hits:
            P("  « %s » : %s" % (kw, hits))
    shown = 0
    for name, txt in texts:
        for m in re.finditer(r"(?<![A-Za-z0-9])(2G|3G|GSM|UMTS)(?![A-Za-z0-9])", txt):
            if shown >= 6:
                break
            P("      contexte « %s » (%s) : ...%s" % (m.group(1), name[-30:], mask(flat(to_text(txt[max(0, m.start() - 130):m.start() + 150])))[:240]))
            shown += 1


def section_catalogue_national():
    P("##### 4. Catalogue national dati.gov.it : l'AGCOM y publie-t-elle ? jeux « copertura AGCOM » de la Regione Piemonte")
    api = "https://www.dati.gov.it/opendata/api/3/action/"
    orgs = []
    for q in ("garanzie", "agcom", "comunicazioni"):
        d = get_json(api + "organization_autocomplete?" + urllib.parse.urlencode(dict(q=q, limit=20))) or {}
        found = [(o.get("name"), o.get("title")) for o in d.get("result") or []]
        P("  organisations « %s » : %s" % (q, found[:8]))
        orgs += [n for n, t in found if re.search(r"(?i)garanzie nelle comunicazioni|agcom", "%s %s" % (n, t))]
    for name in sorted(set(orgs))[:2]:
        d = get_json(api + "package_search?" + urllib.parse.urlencode(dict(fq="organization:%s" % name, rows=30))) or {}
        res = (d.get("result") or {})
        P("  éditeur %s : %s jeux : %s" % (name, res.get("count"), "; ".join((p.get("title") or "")[:60] for p in res.get("results", []))[:230]))
    d = get_json(api + "package_search?" + urllib.parse.urlencode(dict(q='title:"copertura AGCOM"', rows=4))) or {}
    for p in ((d.get("result") or {}).get("results") or [])[:3]:
        P("  jeu « %s » | %s | licence %s | modifié %s" % (p.get("title"), (p.get("organization") or {}).get("title"), p.get("license_title") or p.get("license_id"), (p.get("metadata_modified") or "")[:10]))
        P("      notes : " + flat(to_text(p.get("notes") or ""))[:270])
        for x in (p.get("resources") or [])[:3]:
            P("      ressource : %s | %s | %s" % ((x.get("name") or "")[:60], x.get("format"), (x.get("url") or "")[:130]))


def main():
    urls = []
    for fn in (section_couches, section_cartes_web, section_carte_principale, section_catalogue_national):
        try:
            out = fn()
            if fn is section_cartes_web and out:
                urls = out
        except Exception as e:
            import traceback
            P("  [ERREUR dans %s : %r] %s" % (fn.__name__, e, flat(traceback.format_exc())[-400:]))
    bilan()


if __name__ == "__main__":
    main()
PY_FIN_SONDE
echo "FIN (code python : $?)"
