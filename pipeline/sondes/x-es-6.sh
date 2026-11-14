#!/usr/bin/env bash
# Sonde Espagne 6 (courte) : millésime des couches. Les éléments actuels ont été créés en mai 2026 par copie ;
# on lit la date et le nombre d'entités des éléments d'origine (mots clés « source-… »), puis les pages du
# portail Conectemos qui présentent les cartes de services et les données téléchargeables.
set -u
. "$(dirname "$0")/_lib.sh"
export UA T
python3 - <<'PY'
import html, json, os, re, time, traceback, urllib.error, urllib.parse, urllib.request

UA = os.environ.get("UA") or "carte-zones-blanches-sonde/1.0"
SHARING = "https://www.arcgis.com/sharing/rest"
NREQ = 0


def P(s="", n=420):
    for line in str(s).split("\n"):
        print(line[:n] + (" …" if len(line) > n else ""), flush=True)


def fetch(url, timeout=120):
    global NREQ
    NREQ += 1
    time.sleep(0.4)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(30_000_000), r.geturl()
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:2000], url
    except Exception as e:  # noqa: BLE001
        return 0, repr(e).encode(), url


def jget(url):
    code, body, _ = fetch(url)
    try:
        j = json.loads(body.decode("utf-8", "replace"))
    except Exception:  # noqa: BLE001
        return None, f"{code} (pas du JSON) {body[:120]!r}"
    if isinstance(j, dict) and "error" in j:
        return None, f"{code} ERREUR " + json.dumps(j["error"], ensure_ascii=False)[:200]
    return j, ""


def day(ms):
    try:
        return time.strftime("%Y-%m-%d", time.gmtime(int(ms) / 1000))
    except Exception:  # noqa: BLE001
        return str(ms)


def text_of(page):
    s = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", page, flags=re.S | re.I)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s)))


def links_of(page, base):
    out = {}
    for href, label in re.findall(r'<a[^>]+href="([^"#]+)"[^>]*>(.*?)</a>', page, flags=re.S | re.I):
        label = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", label))).strip()
        out.setdefault(urllib.parse.urljoin(base, html.unescape(href)), label)
    return out


def around(text, rx, radius=300, maxn=3):
    last, n = -10**9, 0
    for m in re.finditer(rx, text, re.I):
        if m.start() - last < radius:
            continue
        last = m.start(); n += 1
        P("     … " + text[max(0, m.start() - radius): m.end() + radius] + " …", 2 * radius + 140)
        if n >= maxn:
            break
    if n == 0:
        P(f"     (aucune occurrence de {rx})")


def section(title):
    P("")
    P("##### " + title)


def s_sources():
    section("1. Éléments d'origine des copies de mai 2026 (mots clés « source-… »)")
    items = {
        "expérience (source de ef9f55c8…)": "8f319e778b924f2ab790e9e1f7b0c76d",
        "carte web 4G (source de 21cb30f5…)": "b8b0a747a0654f8c8a05f415bf9a306b",
        "entités 4G (source de 84599189…)": "5d7ccfd795e44c3e94f17170fce570f5",
        "entités 5G (source de dc7b5355…)": "1e18b2d69df74848aa541aeea424ad47",
        "image 4G (source de 954ae020…)": "683c13c004604bd09c182143fc778d72",
    }
    for label, iid in items.items():
        it, err = jget(f"{SHARING}/content/items/{iid}?f=json")
        if not it:
            P(f"   {label} {iid} : {err}")
            continue
        P(f"   {label} {iid} : title={it.get('title')!r} type={it.get('type')} owner={it.get('owner')} access={it.get('access')} created={day(it.get('created'))} modified={day(it.get('modified'))} url={it.get('url')}", 600)
        if it.get("type") == "Feature Service" and it.get("url"):
            m, err = jget(it["url"].rstrip("/") + "/0?f=json")
            if not m:
                P(f"     couche 0 : {err}")
                continue
            ei = m.get("editingInfo") or {}
            c, err = jget(it["url"].rstrip("/") + "/0/query?where=1%3D1&returnCountOnly=true&f=json")
            P(f"     couche 0 : name={m.get('name')!r} sr={(m.get('extent') or {}).get('spatialReference')} dataLastEditDate={day(ei.get('dataLastEditDate'))} lastEditDate={day(ei.get('lastEditDate'))} nombre d'entités={(c or {}).get('count') if c else err}")
            P("     champs : " + " ; ".join(f.get("name") for f in m.get("fields") or []), 600)
        if it.get("type") == "Web Experience":
            d, err = jget(f"{SHARING}/content/items/{iid}/data?f=json")
            if d:
                texts = [re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", (w.get("config") or {}).get("text") or ""))).strip() for w in (d.get("widgets") or {}).values() if w.get("uri") == "widgets/common/text/"]
                dates = sorted(set(re.findall(r"30 de junio de 20\d\d", " ".join(texts))))
                P(f"     publishTimestamp={day(d.get('publishTimestamp'))} ; dates citées dans les textes : {dates} ; sources : " + " | ".join(f"{v.get('sourceLabel')}={v.get('itemId')}" for v in (d.get("dataSources") or {}).values() if v.get("itemId")), 600)
            else:
                P(f"     configuration : {err}")
    # dates des versions actuelles, pour comparaison
    for label, url in (("entités 4G actuelles", "https://services-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/InfoCob4G_2024/FeatureServer/0"),):
        m, err = jget(url + "?f=json")
        ei = (m or {}).get("editingInfo") or {}
        P(f"   {label} : name={(m or {}).get('name')!r} dataLastEditDate={day(ei.get('dataLastEditDate'))} lastEditDate={day(ei.get('lastEditDate'))} schemaLastEditDate={day(ei.get('schemaLastEditDate'))}")


def s_conectemos():
    section("2. Portail Conectemos : page « Servicios de banda ancha » (cartes) et données téléchargeables")
    for url, rx in (("https://conectemos.digital.gob.es/es/mapas-y-graficos/servicios-de-banda-ancha", r"m[oó]vil|30 de junio|actualiza"),
                    ("https://conectemos.digital.gob.es/es/mapas-y-graficos", r"servicios de banda ancha m[oó]vil|mapa de servicios"),
                    ("https://conectemos.digital.gob.es/es/areas-de-interes/banda-ancha/informacion-de-cobertura", r"reutilizable|descarg|licencia")):
        code, body, final = fetch(url)
        P(f"  -> {code} {len(body)}o {final}", 300)
        if code != 200:
            continue
        page = body.decode("utf-8", "replace")
        ids = sorted(set(re.findall(r"experience\.arcgis\.com/experience/([0-9a-f]{32})[^\"'\\ <]*", page)))
        dash = sorted(set(re.findall(r"(?:apps/dashboards|apps/webappviewer/index\.html\?id=|apps/mapviewer/index\.html\?webmap=)/?([0-9a-f]{32})", page)))
        P(f"     expériences ArcGIS citées : {ids} ; autres applications : {dash}")
        n = 0
        for href, label in links_of(page, final).items():
            if re.search(r"arcgis|\.xlsx?|\.zip|\.csv|\.gpkg|\.shp|datos\.gob", href, re.I) and n < 10:
                n += 1
                P(f"     {label[:80]!r} -> {href}", 330)
        around(text_of(page), rx, 260, 3)
    code, body, final = fetch("https://conectemos.digital.gob.es/es/aviso-legal")
    t = text_of(body.decode("utf-8", "replace"))
    P(f"   mentions légales de Conectemos -> {code} ; occurrences de « reutiliz » : {len(re.findall('reutiliz', t, re.I))} ; de « licencia » : {len(re.findall('licencia', t, re.I))} ; de « datos abiertos » : {len(re.findall('datos abiertos', t, re.I))}")
    around(t, r"reutiliz|se autoriza|queda prohibid|no est[aá] permitid", 300, 3)


for fn in (s_sources, s_conectemos):
    try:
        fn()
    except Exception:  # noqa: BLE001
        P("ECHEC de la section : " + traceback.format_exc()[-900:])
P("")
P(f"FIN ({NREQ} requêtes)")
PY
