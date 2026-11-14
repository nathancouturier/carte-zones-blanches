#!/usr/bin/env bash
# Sonde Espagne 4 : derniers contrôles avant intégration.
# - entités hors commune (CCOM vide) dans les territoires non municipaux de Navarre (Bardenas, Urbasa-Andía) ;
# - requêtes par enveloppe de taille moyenne (compte, durée) ;
# - part du territoire sans 4G par région ; valeur de la couche en quelques lieux de randonnée ;
# - méthodologie 2024 du ministère (seuil de présence 4G, résolution) ;
# - raster catalan « Cobertura mòbil 112 » : valeurs.
set -u
. "$(dirname "$0")/_lib.sh"
export UA T
apt-get update -qq >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends poppler-utils >/dev/null 2>&1

python3 - <<'PY'
import gzip, html, json, math, os, re, sys, time, traceback, urllib.error, urllib.parse, urllib.request

UA = os.environ.get("UA") or "carte-zones-blanches-sonde/1.0"
T = os.environ.get("T") or "/tmp/sonde"
NREQ = 0
F4 = "https://services-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/InfoCob4G_2024/FeatureServer/0"
REGIONS = "CCOM IN ('02','09','15','16')"
NOMS = {"A78923125": "Telefónica Móviles", "A80907397": "Vodafone", "A82009812": "Orange", "A82528548": "Xfera"}


def P(s="", n=420):
    for line in str(s).split("\n"):
        print(line[:n] + (" …" if len(line) > n else ""), flush=True)


def fetch(url, timeout=240):
    global NREQ
    NREQ += 1
    time.sleep(0.4)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "gzip"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read(80_000_000)
            body = gzip.decompress(raw) if r.headers.get("Content-Encoding") == "gzip" else raw
            return r.status, body, time.time() - t0
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:3000], time.time() - t0
    except Exception as e:  # noqa: BLE001
        return 0, repr(e).encode(), time.time() - t0


def q(params, label):
    """Requête sur la couche 4G ; renvoie (json ou None, durée)."""
    url = F4 + "/query?" + urllib.parse.urlencode(params)
    code, body, dt = fetch(url)
    try:
        j = json.loads(body.decode("utf-8", "replace"))
    except Exception:  # noqa: BLE001
        j = None
    if not isinstance(j, dict) or "error" in j:
        P(f"   {label} -> {code} en {dt:.1f} s ERREUR " + (json.dumps(j.get("error"), ensure_ascii=False)[:260] if isinstance(j, dict) else body[:200].decode("utf-8", "replace")), 600)
        return None, dt
    return j, dt


def cj(o, n=300):
    return json.dumps(o, ensure_ascii=False, separators=(",", ":"))[:n]


def env(x0, y0, x1, y1):
    return {"geometry": f"{x0},{y0},{x1},{y1}", "geometryType": "esriGeometryEnvelope", "inSR": "4258", "spatialRel": "esriSpatialRelIntersects"}


def section(title):
    P("")
    P("##### " + title)


def s_hors_commune():
    section("1. Entités sans commune (CCOM vide)")
    for label, where in (("toute l'Espagne, CCOM=''", "CCOM=''"), ("toute l'Espagne, CCOM='' et NATCODE<>''", "CCOM='' AND NATCODE<>''")):
        j, dt = q({"where": where, "returnCountOnly": "true", "f": "json"}, label)
        P(f"   compte ({label}) : {(j or {}).get('count')} en {dt:.1f} s")
    zones = {
        "Bardenas Reales (Navarre)": (-1.60, 42.05, -1.35, 42.30),
        "Urbasa et Andía (Navarre)": (-2.20, 42.78, -1.95, 42.90),
        "Aralar (Navarre et Guipuscoa)": (-2.10, 42.93, -1.90, 43.02),
    }
    for name, box in zones.items():
        p = {"where": "1=1", "returnCountOnly": "true", "f": "json"}; p.update(env(*box))
        j, dt = q(p, name)
        p2 = {"where": "CCOM=''", "returnCountOnly": "true", "f": "json"}; p2.update(env(*box))
        j2, _ = q(p2, name + " CCOM vide")
        p3 = {"where": "1=1", "outFields": "CCOM,NATCODE,Municipio", "returnDistinctValues": "true", "returnGeometry": "false", "orderByFields": "NATCODE", "f": "json"}; p3.update(env(*box))
        j3, _ = q(p3, name + " communes")
        munis = [f"{f['attributes'].get('NATCODE')}={f['attributes'].get('Municipio')}[{f['attributes'].get('CCOM')}]" for f in (j3 or {}).get("features") or []]
        P(f"   {name}, enveloppe {box} : {(j or {}).get('count')} entités ({dt:.1f} s) dont {(j2 or {}).get('count')} avec CCOM vide ; {len(munis)} communes distinctes")
        P("     " + " ; ".join(munis[:40]), 1500)
        if (j2 or {}).get("count"):
            p4 = {"where": "CCOM=''", "outFields": "OBJECTID,COBERTURA,NATCODE,Municipio,FID_Municipios_IGN_Cat2023,Shape__Area", "returnGeometry": "false", "orderByFields": "Shape__Area DESC", "resultRecordCount": "4", "f": "json"}; p4.update(env(*box))
            j4, _ = q(p4, name + " échantillon")
            for f in (j4 or {}).get("features") or []:
                P("     plus grandes entités sans commune : " + cj(f.get("attributes"), 400))


def s_enveloppes():
    section("2. Comptes par enveloppe de taille croissante (toutes entités)")
    for name, box in (("0,5° x 0,5° autour de Jaca", (-0.80, 42.40, -0.30, 42.90)), ("Navarre entière", (-2.50, 41.90, -0.72, 43.32)), ("Pyrénées aragonaises et catalanes", (-1.0, 42.0, 2.0, 43.0))):
        p = {"where": "1=1", "returnCountOnly": "true", "f": "json"}; p.update(env(*box))
        j, dt = q(p, name)
        P(f"   {name}, enveloppe {box} : {(j or {}).get('count')} entités en {dt:.1f} s")


def s_surfaces():
    section("3. Surface sans 4G par région (somme de Shape__Area, en degrés carrés)")
    stats = json.dumps([{"statisticType": "sum", "onStatisticField": "Shape__Area", "outStatisticFieldName": "aire"}, {"statisticType": "count", "onStatisticField": "OBJECTID", "outStatisticFieldName": "n"}])
    tot, sans = {}, {}
    j, dt = q({"where": REGIONS, "outStatistics": stats, "groupByFieldsForStatistics": "CCOM,Comunidad_Autonoma", "f": "json"}, "surface totale")
    for f in (j or {}).get("features") or []:
        a = f["attributes"]; tot[a["CCOM"]] = (a.get("Comunidad_Autonoma"), a.get("aire"), a.get("n"))
    j, dt2 = q({"where": REGIONS + " AND COBERTURA=''", "outStatistics": stats, "groupByFieldsForStatistics": "CCOM", "f": "json"}, "surface sans couverture")
    for f in (j or {}).get("features") or []:
        a = f["attributes"]; sans[a["CCOM"]] = (a.get("aire"), a.get("n"))
    for k, (name, aire, n) in sorted(tot.items()):
        aire = aire or 1e-12
        s = sans.get(k) or (0, 0)
        s = (s[0] or 0, s[1] or 0)
        P(f"   {k} {name} : {n} entités, {aire:.4f} deg² au total ; sans 4G (COBERTURA vide) : {s[1]} entités, {s[0]:.4f} deg², soit {100.0 * s[0] / aire:.1f} % de la surface")
    P(f"   durées : {dt:.1f} s et {dt2:.1f} s")
    for cif, nom in NOMS.items():
        j, dt = q({"where": REGIONS + f" AND COBERTURA LIKE '%{cif}%'", "outStatistics": stats, "f": "json"}, nom)
        a = ((j or {}).get("features") or [{}])[0].get("attributes") or {}
        total = sum((v[1] or 0) for v in tot.values()) or 1
        P(f"   {cif} ({nom}) : {a.get('n')} entités, {(a.get('aire') or 0):.4f} deg², soit {100.0 * (a.get('aire') or 0) / total:.1f} % de la surface des 4 régions ({dt:.1f} s)")


def s_lieux():
    section("4. Valeur de la couche en quelques lieux de randonnée (coordonnées approximatives)")
    lieux = {
        "Refuge de Góriz (Ordesa)": (0.0151, 42.6633),
        "Refuge de la Renclusa (Aneto)": (0.6500, 42.6710),
        "Sommet de l'Aneto": (0.6567, 42.6311),
        "Refuge de Respomuso": (-0.2889, 42.8186),
        "Ibón de Estanés": (-0.5886, 42.7964),
        "Estany de Sant Maurici": (0.9990, 42.5820),
        "Refuge de Colomers (Val d'Aran)": (0.9210, 42.6240),
        "Belagua, refuge de Linza": (-0.8010, 42.8960),
        "Col d'Ibañeta (Roncevaux)": (-1.3190, 43.0200),
        "Centre de Jaca": (-0.5490, 42.5700),
    }
    for name, (x, y) in lieux.items():
        j, dt = q({"where": "1=1", "geometry": f"{x},{y}", "geometryType": "esriGeometryPoint", "inSR": "4258", "spatialRel": "esriSpatialRelIntersects",
                   "outFields": "COBERTURA,Municipio,CCOM", "returnGeometry": "false", "f": "json"}, name)
        vals = []
        for f in (j or {}).get("features") or []:
            a = f["attributes"]
            ops = [NOMS.get(c, c) for c in (a.get("COBERTURA") or "").split(";") if c]
            vals.append(f"{a.get('Municipio')} : " + (", ".join(sorted(ops)) if ops else "AUCUN OPERATEUR (COBERTURA vide)"))
        P(f"   {name} ({x}, {y}) : " + (" | ".join(vals) if vals else "aucune entité"), 500)


for fn in (s_hors_commune, s_enveloppes, s_surfaces, s_lieux):
    try:
        fn()
    except Exception:  # noqa: BLE001
        P("ECHEC de la section : " + traceback.format_exc()[-900:])
P("")
P(f"FIN python ({NREQ} requêtes)")
PY

echo
echo "##### 5. Rapport de couverture 2024 du ministère : documents et méthodologie"
BASE="https://digital.gob.es"
get "$T/ic2024.html" "$BASE/telecomunicaciones-infraestructuras-digitales/areas-interes/banda-ancha/informacion-cobertura/informes-cobertura/informe-cobertura-2024"
python3 - "$T/ic2024.html" > "$T/liens2024.txt" <<'PY'
import re, sys, html
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
seen = []
for href, label in re.findall(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>', s, flags=re.S | re.I):
    if re.search(r"\.(pdf|xlsx?|zip|csv)(\?|$)", href, re.I) or re.search(r"arcgis|experience", href, re.I):
        label = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", label))).strip()
        if href not in [h for h, _ in seen]:
            seen.append((href, label))
for href, label in seen[:30]:
    print(href + " | " + label[:90])
PY
sed 's/^/   /' "$T/liens2024.txt" | cut -c1-330 | head -24
M=$(grep -i -m1 "metodolog" "$T/liens2024.txt" | cut -d' ' -f1)
if [ -n "$M" ]; then
  case "$M" in http*) U="$M" ;; *) U="$BASE$M" ;; esac
  get "$T/metodo2024.pdf" "$U"
  pdftotext -layout "$T/metodo2024.pdf" "$T/metodo2024.txt" 2>/dev/null
  python3 - "$T/metodo2024.txt" <<'PY'
import re, sys, textwrap
s = re.sub(r"\s+", " ", open(sys.argv[1], encoding="utf-8", errors="replace").read())
for rx, before, after in ((r"Presencia, entendida como la zona donde", 900, 700), (r"referid[ao]s? a(l)? 30 de junio", 250, 300)):
    m = re.search(rx, s)
    if m:
        for line in textwrap.wrap("… " + s[max(0, m.start() - before): m.start() + after] + " …", 360):
            print("   " + line)
        print("   --")
    else:
        print("   (aucune occurrence de", rx, ")")
print("   longueur du texte :", len(s), "| occurrences de RSRP :", len(re.findall("RSRP", s)))
PY
else
  echo "   pas de lien « metodología » trouvé sur la page du rapport 2024"
fi

echo
echo "##### 6. Catalunya : raster « Cobertura mòbil 112 » (lecture complète des valeurs)"
python3 - <<'PY'
import os, time, urllib.request
UA, T = os.environ.get("UA", "sonde"), os.environ.get("T", "/tmp/sonde")
url = "https://sig.gencat.cat/admin/server/servletFileDownloadDataRaster?rasterName=TELCO_COBERTURA_112"
path, cap, n, t0 = T + "/cat112.tif", 360_000_000, 0, time.time()
try:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=300) as r, open(path, "wb") as f:
        if int(r.headers.get("Content-Length") or 0) > cap:
            raise RuntimeError("fichier de plus de 360 Mo, téléchargement abandonné")
        while n < cap:
            chunk = r.read(4_000_000)
            if not chunk:
                break
            f.write(chunk); n += len(chunk)
    print(f"   téléchargé : {n} octets en {time.time() - t0:.0f} s" + (" (plafond atteint, fichier incomplet)" if n >= cap else " (complet)"))
    import numpy as np
    from osgeo import gdal
    gdal.UseExceptions()
    ds = gdal.Open(path)
    b = ds.GetRasterBand(1)
    print(f"   {ds.RasterXSize} x {ds.RasterYSize}, type {gdal.GetDataTypeName(b.DataType)}, nodata={b.GetNoDataValue()}, compression={ds.GetMetadataItem('COMPRESSION', 'IMAGE_STRUCTURE')}, géotransformation={ds.GetGeoTransform()}")
    print("   métadonnées TIFF :", {k: str(v)[:100] for k, v in ds.GetMetadata().items()})
    counts = {}
    for y in range(0, ds.RasterYSize, 512):
        a = b.ReadAsArray(0, y, ds.RasterXSize, min(512, ds.RasterYSize - y))
        v, c = np.unique(a, return_counts=True)
        for vv, cc in zip(v.tolist(), c.tolist()):
            counts[vv] = counts.get(vv, 0) + cc
    total = sum(counts.values())
    items = sorted(counts.items(), key=lambda kv: -kv[1])
    print(f"   {len(items)} valeurs distinctes ; valeurs:part = " + " ".join(f"{v}:{100.0 * c / total:.2f}%" for v, c in items[:16]))
    vals = sorted(k for k in counts if k != b.GetNoDataValue())
    print("   plage hors nodata :", vals[:1], "à", vals[-1:], "| catégories :", b.GetCategoryNames(), "| table attributaire :", bool(b.GetDefaultRAT()))
except Exception as e:
    print("   échec :", repr(e)[:300])
PY
echo "FIN"
