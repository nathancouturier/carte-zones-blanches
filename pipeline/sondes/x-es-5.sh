#!/usr/bin/env bash
# Sonde Espagne 5 : millésime et pérennité.
# - portail « Conectemos » de la SETELECO : liens sur la couverture, mentions légales ;
# - communiqué de mai 2026 (rapport de couverture 2025) : que dit-il des cartes ;
# - couches « 2026 » en préparation sur le compte du ministère (schéma seulement, sans les utiliser) ;
# - méthodologie 2024 (PDF image) : lecture par OCR du seuil de présence 4G.
set -u
. "$(dirname "$0")/_lib.sh"
export UA T
apt-get update -qq >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends poppler-utils tesseract-ocr tesseract-ocr-spa >/dev/null 2>&1

python3 - <<'PY'
import html, json, os, re, sys, time, traceback, urllib.error, urllib.parse, urllib.request

UA = os.environ.get("UA") or "carte-zones-blanches-sonde/1.0"
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
            return r.status, r.headers.get("Content-Type", ""), r.read(30_000_000), r.geturl()
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Content-Type", ""), e.read()[:2000], url
    except Exception as e:  # noqa: BLE001
        return 0, "", repr(e).encode(), url


def text_of(page):
    s = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", page, flags=re.S | re.I)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s)))


def links_of(page, base):
    out = []
    for href, label in re.findall(r'<a[^>]+href="([^"#]+)"[^>]*>(.*?)</a>', page, flags=re.S | re.I):
        label = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", label))).strip()
        out.append((urllib.parse.urljoin(base, html.unescape(href)), label))
    return out


def around(text, rx, radius=350, maxn=3, indent="     "):
    last, n = -10**9, 0
    for m in re.finditer(rx, text, re.I):
        if m.start() - last < radius:
            continue
        last = m.start(); n += 1
        P(indent + "… " + text[max(0, m.start() - radius): m.end() + radius] + " …", 2 * radius + 120)
        if n >= maxn:
            break
    if n == 0:
        P(indent + f"(aucune occurrence de {rx})")


def section(title):
    P("")
    P("##### " + title)


def s_conectemos():
    section("1. Portail « Conectemos » (conectemos.digital.gob.es)")
    code, ctype, body, final = fetch("https://conectemos.digital.gob.es/")
    P(f"  -> {code} {len(body)}o {ctype[:30]} {final}")
    if code != 200:
        P("     " + body[:200].decode("utf-8", "replace"))
        return
    page = body.decode("utf-8", "replace")
    links = links_of(page, final)
    P(f"   titre : {re.sub(r'<[^>]+>', '', (re.search(r'<title[^>]*>(.*?)</title>', page, re.S | re.I) or [None, ''])[1]).strip()[:120]!r} ; {len(links)} liens")
    seen, legal, cover = set(), [], []
    for href, label in links:
        if href in seen:
            continue
        seen.add(href)
        if re.search(r"legal|privacidad|reutiliz", href + " " + label, re.I):
            legal.append((href, label))
        elif re.search(r"cobertura|mapa|datos|descarga|informe", href + " " + label, re.I):
            cover.append((href, label))
    for href, label in (cover[:14] + legal[:4]):
        P(f"     {label[:70]!r} -> {href}", 300)
    for href, label in legal[:1]:
        code, ctype, body, final = fetch(href)
        P(f"   mentions légales -> {code} {len(body)}o {final}", 300)
        if code == 200:
            around(text_of(body.decode("utf-8", "replace")), r"reutilizaci[oó]n|licencia|propiedad intelectual", 420, 3)
    n = 0
    for href, label in cover:
        if n >= 2 or not re.search(r"cobertura", href + " " + label, re.I) or re.search(r"\.pdf", href, re.I) or "conectemos" not in href:
            continue
        n += 1
        code, ctype, body, final = fetch(href)
        P(f"   page {label[:60]!r} -> {code} {len(body)}o {final}", 300)
        if code == 200:
            sub = body.decode("utf-8", "replace")
            for h, l in [x for x in dict(links_of(sub, final)).items() if re.search(r"arcgis|experience|\.zip|\.csv|\.xlsx?|\.gpkg|\.shp|descarga|datos-abiertos|opendata", x[0] + " " + x[1], re.I)][:12]:
                P(f"       {l[:70]!r} -> {h}", 300)
            around(text_of(sub), r"descarg|datos abiertos|reutiliz|mapa de servicios", 300, 3)


def s_communique():
    section("2. Communiqué du ministère de mai 2026 (rapport de couverture 2025)")
    url = "https://digital.gob.es/comunicacion/notas-prensa/secretaria-estado-telecomunicaciones-e-infraestructuras-digitales/2026/05/el-5g-alcanza-ya-al-99--de-la-poblacion-espanola-y-al-96--en-zon0"
    code, ctype, body, final = fetch(url)
    P(f"  -> {code} {len(body)}o {final}", 300)
    if code == 200:
        t = text_of(body.decode("utf-8", "replace"))
        m = re.search(r"El 5G alcanza ya al 99", t)
        i = [x.start() for x in re.finditer(r"El 5G alcanza ya al 99", t)]
        P("     date ou chapeau : " + (t[i[-1] - 200: i[-1] + 500] if i else "(titre non trouvé)"), 800)
        around(t, r"mapas? (interactivos? )?de (servicios|cobertura)|30 de junio|visor", 380, 4)


def s_brouillons():
    section("3. Couches « 2026 » visibles sur le compte coberturaBA_eu (non liées depuis le site du ministère : schéma seulement)")
    base = "https://services-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/"
    for name in ("Cobertura_Movil_X_4G_2026", "Cobertura_Movil_Prueba_4G_2026"):
        code, ctype, body, _ = fetch(base + name + "/FeatureServer/0?f=json")
        try:
            m = json.loads(body.decode("utf-8", "replace"))
        except Exception:  # noqa: BLE001
            m = {}
        if "error" in m or not m:
            P(f"   {name} -> {code} : " + body[:200].decode("utf-8", "replace"))
            continue
        ei = m.get("editingInfo") or {}
        P(f"   {name}/FeatureServer/0 : name={m.get('name')!r} geom={m.get('geometryType')} capabilities={m.get('capabilities')} sr={(m.get('extent') or {}).get('spatialReference')} dataLastEditDate={time.strftime('%Y-%m-%d', time.gmtime((ei.get('dataLastEditDate') or 0) / 1000))}")
        P("     champs : " + " ; ".join(f"{f.get('name')}({str(f.get('type')).replace('esriFieldType', '')})" for f in m.get("fields") or []), 700)
        code, ctype, body, _ = fetch(base + name + "/FeatureServer/0/query?where=1%3D1&returnCountOnly=true&f=json")
        P("     nombre d'entités : " + body[:80].decode("utf-8", "replace"))
        code, ctype, body, _ = fetch(base + name + "/FeatureServer/0/query?where=1%3D1&outFields=*&returnGeometry=false&resultRecordCount=2&f=json")
        try:
            for f in json.loads(body.decode("utf-8", "replace")).get("features") or []:
                P("     exemple : " + json.dumps(f.get("attributes"), ensure_ascii=False)[:500], 600)
        except Exception:  # noqa: BLE001
            P("     exemple illisible : " + body[:160].decode("utf-8", "replace"))
    code, ctype, body, _ = fetch("https://tiles-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/Cobertura_Movil_X_vtpk_4G_2026/VectorTileServer?f=json")
    try:
        m = json.loads(body.decode("utf-8", "replace"))
        lods = (m.get("tileInfo") or {}).get("lods") or []
        P(f"   Cobertura_Movil_X_vtpk_4G_2026/VectorTileServer : capabilities={m.get('capabilities')} minLOD={m.get('minLOD')} maxLOD={m.get('maxLOD')} niveaux={len(lods)} tiles={m.get('tiles')} exportTilesAllowed={m.get('exportTilesAllowed')} sr={(m.get('tileInfo') or {}).get('spatialReference')}", 600)
    except Exception:  # noqa: BLE001
        P("   VectorTileServer illisible : " + body[:200].decode("utf-8", "replace"))


for fn in (s_conectemos, s_communique, s_brouillons):
    try:
        fn()
    except Exception:  # noqa: BLE001
        P("ECHEC de la section : " + traceback.format_exc()[-900:])
P("")
P(f"FIN python ({NREQ} requêtes)")
PY

echo
echo "##### 4. Méthodologie 2024 du ministère (PDF image) : lecture par OCR"
U="https://digital.gob.es/content/dam/portal-mtdfp/avance-digital/telecomunicacion-e-infraestructuras-digitales/areas_interes/banda-ancha/cobertura/documents/informe-de-cobertura-2024/metodologia-informe-cobertura-ba-2024.pdf"
get "$T/m2024.pdf" "$U"
NP=$(pdfinfo "$T/m2024.pdf" 2>/dev/null | awk '/^Pages/{print $2}')
echo "   pages : ${NP:-?} ; texte extractible : $(pdftotext "$T/m2024.pdf" - 2>/dev/null | wc -c) caractères"
mkdir -p "$T/ocr"
pdftoppm -r 110 -gray -png "$T/m2024.pdf" "$T/ocr/p" 2>/dev/null
n=0
for f in "$T"/ocr/p-*.png; do
  [ -f "$f" ] || continue
  tesseract "$f" "${f%.png}" -l spa --psm 6 >/dev/null 2>&1
  n=$((n + 1))
done
echo "   pages passées à l'OCR : $n"
cat "$T"/ocr/p-*.txt > "$T/m2024.txt" 2>/dev/null
python3 - "$T/m2024.txt" <<'PY'
import re, sys, textwrap
try:
    s = re.sub(r"\s+", " ", open(sys.argv[1], encoding="utf-8", errors="replace").read())
except Exception as e:
    print("   pas de texte OCR :", e); sys.exit()
print("   longueur du texte OCR :", len(s), "| occurrences de RSRP :", len(re.findall(r"RSRP", s)), "| de dBm :", len(re.findall(r"dBm", s)))
for rx, before, after in ((r"Presencia,? entendida como la zona", 700, 520), (r"resoluci[oó]n m[ií]nima", 250, 350), (r"30 de junio de 2024", 250, 250)):
    m = re.search(rx, s, re.I)
    if m:
        for line in textwrap.wrap("… " + s[max(0, m.start() - before): m.start() + after] + " …", 360):
            print("   " + line)
        print("   --")
    else:
        print("   (aucune occurrence de", rx, ")")
PY
echo "FIN"
