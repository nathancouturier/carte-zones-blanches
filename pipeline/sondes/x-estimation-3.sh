#!/usr/bin/env bash
# Estimation, sonde 3 : suite de la documentation. OpenCelliD (nouveau site docs.opencellid.org : téléchargements,
# format de la base, limites), Copernicus (licence fournie avec la tuile, métadonnées XML), antennes suisses
# (GeoJSON de l'OFCOM), Italie (ARPA Piemonte, Ligurie, Vallée d'Aoste), Andorre, Monaco, sites Arcep.
set -u
. "$(dirname "$0")/_lib.sh"
cd "$T"

autour() {
  python3 - "$1" "$2" "${3:-350}" "${4:-6}" <<'PY'
import re, sys, html
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
s = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
s = html.unescape(re.sub(r"<[^>]+>", " ", s))
s = re.sub(r"\s+", " ", s)
w = int(sys.argv[3]); seen = []
for m in re.finditer(sys.argv[2], s, flags=re.I):
    a = max(0, m.start() - w // 3); b = min(len(s), m.end() + w)
    if any(abs(a - x) < w for x in seen): continue
    seen.append(a); print("   …", s[a:b].strip(), "…")
    if len(seen) >= int(sys.argv[4]): break
if not seen: print("   (motif absent)")
PY
}
# contenu <fichier.html> [max] : contenu principal d'une page (balise article ou main), tableaux à plat
contenu() {
  python3 - "$1" "${2:-3000}" <<'PY'
import re, sys, html
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"<article\b.*?</article>", s, flags=re.S | re.I) or re.search(r"<main\b.*?</main>", s, flags=re.S | re.I)
if m: s = m.group(0)
s = re.sub(r"<(script|style|svg|noscript|nav|button)\b.*?</\1>", " ", s, flags=re.S | re.I)
s = re.sub(r"</(td|th)>", " | ", s, flags=re.I)
s = re.sub(r"<br\s*/?>|</(p|div|li|tr|h[1-6]|pre|summary|details)>", "\n", s, flags=re.I)
s = html.unescape(re.sub(r"<[^>]+>", " ", s))
s = re.sub(r"[ \t\r\f\v]+", " ", s)
lines = [l.strip() for l in s.split("\n") if l.strip()]
out = "\n".join(lines)[: int(sys.argv[2])]
for l in out.split("\n"): print("   |", l[:700])
PY
}

echo "##### A. OpenCelliD : pages de docs.opencellid.org"
get "$T/d0.html" "https://docs.opencellid.org/docs/attribution"
python3 - <<'PY' > "$T/docs_urls.txt"
import re
s = open("/tmp/sonde/d0.html", encoding="utf-8", errors="replace").read()
seen = []
for h in re.findall(r'href="(/docs/[^"#?]*)', s):
    if h not in seen: seen.append(h)
print("\n".join(seen))
PY
echo "   pages : $(tr '\n' ' ' < "$T/docs_urls.txt")"
n=0
for p in $(grep -i -E "download|database|format|limit|access|mvno|operator|start|introduction" "$T/docs_urls.txt" | head -8); do
  n=$((n+1)); echo "--- $p"
  get "$T/d$n.html" "https://docs.opencellid.org$p"
  contenu "$T/d$n.html" 4200
done
for p in $(grep -i -E "faq|question|common|glossary|error" "$T/docs_urls.txt" | head -3); do
  n=$((n+1)); echo "--- $p (passages)"
  get "$T/d$n.html" "https://docs.opencellid.org$p"
  autour "$T/d$n.html" "exact location|samples|changeable|range column|18.month|how often|how accurate|daily|rate.limit|RATE_LIMITED|twice|per day|INVALID" 600 7
done

echo "##### B. Copernicus : licence livrée avec la tuile, métadonnées XML, fin du lisez-moi"
B=https://copernicus-dem-30m.s3.amazonaws.com; N=Copernicus_DSM_COG_10_N45_00_E006_00_DEM
apt-get install -y -qq poppler-utils >/dev/null 2>&1
get "$T/eula.pdf" "$B/$N/INFO/eula_F.pdf"
get "$T/lic.pdf" "https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf"
pdftotext -layout "$T/eula.pdf" "$T/eula.txt" 2>/dev/null; pdftotext -layout "$T/lic.pdf" "$T/lic.txt" 2>/dev/null
python3 - <<'PY'
import re, difflib
def norm(p):
    try: return re.sub(r"\s+", " ", open(p, encoding="utf-8", errors="replace").read()).strip()
    except Exception as e: return ""
a, b = norm("/tmp/sonde/eula.txt"), norm("/tmp/sonde/lic.txt")
print("   eula_F.pdf :", len(a), "caractères ; License-COPDEM-30.pdf :", len(b), "caractères ; identiques :", a == b, "; similarité :", round(difflib.SequenceMatcher(None, a, b).ratio(), 4))
print("   début eula :", a[:260])
for m in re.finditer(r"(Article 6\. User Obligations.{0,900})", a): print("   art. 6 eula :", m.group(1)[:900])
PY
get "$T/meta.xml" "$B/$N/Copernicus_DSM_10_N45_00_E006_00.xml"
grep -o -i -E "<[^>]*(vertical|datum|geoid|EGM|nodata|void|version|resolution|license|licence)[^>]*>[^<]{0,160}" "$T/meta.xml" | sort -u | cut -c1-260 | head -30
grep -o -i -E "EGM[0-9]+|EPSG:{1,2}[0-9]+|WGS ?84[^<]{0,40}" "$T/meta.xml" | sort | uniq -c | head -10
get "$T/readme.html" "$B/readme.html"
autour "$T/readme.html" "licen[cs]|naming|Copernicus_DSM_COG|northing|easting|tileList|resolution in arc" 500 6

echo "##### C. Suisse : fichier des emplacements d'antennes de l'OFCOM"
get "$T/ch.json" "https://data.geo.admin.ch/ch.bakom.standorte-mobilfunkanlagen/standorte-mobilfunkanlagen/standorte-mobilfunkanlagen_2056.json"
ogrinfo -so -al "$T/ch.json" 2>&1 | grep -v -E "^(PROJCRS|    |  [A-Z]+\[)" | cut -c1-200 | head -40
python3 - <<'PY'
import json, collections
try:
    d = json.load(open("/tmp/sonde/ch.json", encoding="utf-8"))
    feats = d.get("features", [])
    print("   entités :", len(feats), "| crs :", json.dumps(d.get("crs"))[:160], "| clés racine :", list(d.keys()))
    cnt = collections.defaultdict(collections.Counter); gt = collections.Counter()
    for f in feats:
        gt[(f.get("geometry") or {}).get("type")] += 1
        for k, v in (f.get("properties") or {}).items():
            if len(cnt[k]) < 4000: cnt[k][json.dumps(v, ensure_ascii=False)[:80]] += 1
    print("   géométries :", dict(gt))
    for k, c in cnt.items():
        print("   champ", k, ":", len(c), "valeurs distinctes ; les plus fréquentes :", c.most_common(8))
    print("   exemple :", json.dumps(feats[0], ensure_ascii=False)[:700])
except Exception as e:
    print("   ERREUR", e, open("/tmp/sonde/ch.json", errors="replace").read()[:300])
PY
get "$T/terms.html" "https://opendata.swiss/en/terms-of-use"
autour "$T/terms.html" "terms_by|Open use\. Must provide the source|must be provided|Freie Nutzung\. Quellenangabe" 450 4
get "$T/bakom.html" "https://www.bakom.admin.ch/bakom/en/homepage/frequencies-and-antennas/location-of-radio-transmitters.html"
autour "$T/bakom.html" "operator|transmission power|radiated power|accuracy|updated|locations of" 420 6

echo "##### D. Italie : ARPA Piemonte (fiche de métadonnées et service), Ligurie, Vallée d'Aoste"
get "$T/arpa.json" "https://webgis.arpa.piemonte.it/geoportalserver_arpa/rest/find/document?searchText=telefonia&f=pjson&max=15"
python3 - <<'PY' > "$T/arpa_meta.txt"
import json
try:
    d = json.load(open("/tmp/sonde/arpa.json")); recs = d.get("records") or []
    for r in recs:
        if (r.get("title") or "").strip().endswith("Sorgenti di campo elettromagnetico"):
            print("ID", r.get("id")); print("RESUME", (r.get("summary") or "")[:700].replace("\n", " "))
            for l in r.get("links") or []: print("LIEN", l.get("type"), l.get("href"))
except Exception as e: print("ERREUR", e)
PY
cut -c1-900 "$T/arpa_meta.txt" | head -14
m=$(grep -E "^LIEN (metadata|fullMetadata)" "$T/arpa_meta.txt" | head -1 | awk '{print $3}')
if [ -n "$m" ]; then
  get "$T/arpa_meta.xml" "$m"
  python3 - <<'PY'
import re, html
s = open("/tmp/sonde/arpa_meta.xml", encoding="utf-8", errors="replace").read()
def texts(tag):
    return [re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", x))).strip() for x in re.findall(r"<(?:\w+:)?%s\b.*?</(?:\w+:)?%s>" % (tag, tag), s, flags=re.S)]
for tag in ("useLimitation", "otherConstraints", "accessConstraints", "useConstraints", "MD_RestrictionCode"):
    for t in texts(tag)[:4]: print("   ", tag, ":", t[:500])
print("    URL :", sorted(set(re.findall(r"<(?:\w+:)?URL>([^<]+)", s)))[:12])
print("    dates :", sorted(set(re.findall(r"<(?:\w+:)?Date>([^<]+)", s)))[:6])
PY
fi
R="https://webgis.arpa.piemonte.it/ags101free/rest/services/campi_elettromagnetici/Radiazioni_non_ionizzanti_pubblico/MapServer"
get "$T/ms.json" "$R?f=pjson"
python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/ms.json"))
    print("   capacités :", d.get("capabilities"), "| max :", d.get("maxRecordCount"), "| droits :", (d.get("copyrightText") or "")[:200], "| scr :", d.get("spatialReference"))
    print("   description :", (d.get("serviceDescription") or d.get("description") or "")[:400].replace("\n", " "))
    for l in d.get("layers", []): print("    couche", l.get("id"), "|", l.get("name"), "| parent :", l.get("parentLayerId"))
except Exception as e: print("   ERREUR", e, open("/tmp/sonde/ms.json", errors="replace").read()[:300])
PY
for id in $(python3 -c "
import json
try:
    d = json.load(open('/tmp/sonde/ms.json'))
    print(' '.join(str(l['id']) for l in d.get('layers', []) if not l.get('subLayerIds'))[:40])
except Exception: pass" | cut -d' ' -f1-4); do
  get "$T/ly.json" "$R/$id?f=pjson"
  python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/ly.json"))
    print("    couche", d.get("id"), d.get("name"), "| géométrie :", d.get("geometryType"), "| droits :", (d.get("copyrightText") or "")[:160])
    print("      champs :", [(f.get("name"), f.get("type", "").replace("esriFieldType", "")) for f in d.get("fields") or []][:30])
except Exception as e: print("    ERREUR", e)
PY
  get "$T/q.json" "$R/$id/query?where=1%3D1&returnCountOnly=true&f=json"; head -c 200 "$T/q.json"; echo
  get "$T/q.json" "$R/$id/query?where=1%3D1&outFields=*&resultRecordCount=2&returnGeometry=true&outSR=4326&f=json"
  python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/q.json"))
    for f in (d.get("features") or [])[:2]: print("      exemple :", json.dumps(f, ensure_ascii=False)[:600])
    if not d.get("features"): print("      ", json.dumps(d)[:300])
except Exception as e: print("      ERREUR", e)
PY
done
for id in "r_liguri:D.2196" "r_liguri:D.1235.VS"; do
  get "$T/lig.xml" "https://inspire-geoportal.ec.europa.eu/srv/api/records/$id/formatters/xml"
  python3 - <<'PY'
import re, html
s = open("/tmp/sonde/lig.xml", encoding="utf-8", errors="replace").read()
def texts(tag, n=3):
    return [re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", x))).strip() for x in re.findall(r"<(?:\w+:)?%s\b.*?</(?:\w+:)?%s>" % (tag, tag), s, flags=re.S)][:n]
print("    titre :", [t[:200] for t in texts("title", 2)])
print("    résumé :", [t[:700] for t in texts("abstract", 1)])
for tag in ("useLimitation", "otherConstraints"):
    for t in texts(tag, 4): print("   ", tag, ":", t[:400])
print("    URL :", sorted(set(re.findall(r"<(?:\w+:)?URL>([^<]+)", s)))[:10])
PY
done
for q in "aosta%20telefonia" "aosta%20radioelettric*" "piemonte%20telefonia%20impianti" "liguria%20telecomunicazion*"; do
  get "$T/it.json" "https://www.dati.gov.it/opendata/api/3/action/package_search?q=$q&rows=8"
  python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/it.json"))["result"]
    print("     ", d.get("count"), "résultats :", [((p.get("title") or "")[:60], (p.get("holder_name") or "")[:30], p.get("license_id")) for p in d.get("results", [])[:8]])
except Exception as e: print("      ERREUR", e)
PY
done 2>&1 | cut -c1-1500

echo "##### E. Andorre (IDE Andorra) et Monaco"
for u in "https://www.ideandorra.ad/cataleg-de-metadades" "https://www.ideandorra.ad/web-de-descarregues"; do
  get "$T/ad.html" "$u"
  autour "$T/ad.html" "telecom|antena|antenes|cobertura m|telefonia|llic[eè]ncia|condicions d.[uú]s|CC BY" 300 5
done
get "$T/mc.html" "https://data.gouv.mc/"
python3 -c "
import re,html
s=open('/tmp/sonde/mc.html',encoding='utf-8',errors='replace').read()
m=re.search(r'<title[^>]*>(.*?)</title>',s,flags=re.S|re.I)
print('   titre :', html.unescape(re.sub(r'\s+',' ',m.group(1))).strip()[:160] if m else '(aucun)')"

echo "##### F. France : en-tête du fichier des sites Arcep et décompte"
get "$T/sites.csv" "https://data.arcep.fr/mobile/sites/last/2026_T2_sites_Metropole.csv"
head -c 1500 "$T/sites.csv" | head -3 | cut -c1-1200
python3 - <<'PY'
import csv, collections
try:
    with open("/tmp/sonde/sites.csv", newline="", encoding="utf-8", errors="replace") as fh:
        sample = fh.read(8192); fh.seek(0)
        delim = ";" if sample.split("\n")[0].count(";") > sample.split("\n")[0].count(",") else ","
        rd = csv.DictReader(fh, delimiter=delim)
        cols = rd.fieldnames; n = 0
        cnt = {k: collections.Counter() for k in cols}
        for row in rd:
            n += 1
            for k in cols:
                if len(cnt[k]) < 60: cnt[k][row.get(k)] += 1
    print("   séparateur :", repr(delim), "| lignes :", n, "| colonnes :", cols)
    for k in cols:
        c = cnt[k]
        print("   ", k, "->", c.most_common(8) if len(c) < 60 else f"60+ valeurs, ex. {list(c)[:4]}")
except Exception as e: print("   ERREUR", e)
PY
echo "FIN"
