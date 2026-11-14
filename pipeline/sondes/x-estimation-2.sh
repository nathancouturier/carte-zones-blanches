#!/usr/bin/env bash
# Estimation, sonde 2 : existe-t-il des positions d'antennes ouvertes et réutilisables en Espagne, en Italie,
# en Andorre et à Monaco ? Catalogues officiels interrogés par leur API de recherche (aucun scraping de carte).
set -u
. "$(dirname "$0")/_lib.sh"

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
liens() {
  python3 - "$1" "${2:-.}" <<'PY'
import re, sys, html
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
out = []
for m in re.finditer(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', s, flags=re.S | re.I):
    href = html.unescape(m.group(1)); label = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", m.group(2))).strip()
    if re.search(sys.argv[2], href + " " + label, re.I) and (href, label) not in out: out.append((href, label))
for href, label in out[:25]: print("   ", href[:200], "|", label[:80])
print("   (", len(out), "liens )")
PY
}
titre() { python3 -c "
import re,sys,html
s=open(sys.argv[1],encoding='utf-8',errors='replace').read()
m=re.search(r'<title[^>]*>(.*?)</title>',s,flags=re.S|re.I)
print('   titre :', html.unescape(re.sub(r'\s+',' ',m.group(1))).strip()[:160] if m else '(aucun)')" "$1"; }

echo "##### 1. Espagne : service du ministère sur les stations radioélectriques (Infoantenas)"
get "$T/es1.html" "https://digital.gob.es/telecomunicaciones-infraestructuras-digitales/areas-interes/inspeccion-telecomunicaciones/niveles-exposicion/servicio-estaciones-radioelectricas.html"
autour "$T/es1.html" "geoportal|infoantenas|descarg|reutiliz|datos abiertos" 500 5
liens "$T/es1.html" "geoportal|antenas|vcne|VCTEL|descarg|datos\.gob"

echo "##### 2. Espagne : catalogue national datos.gob.es (fédère les portails régionaux), recherche par titre"
for q in antenas telefonia "estaciones%20base" radioelectric; do
  get "$T/dg.json" "https://datos.gob.es/apidata/catalog/dataset/title/$q.json?_pageSize=50&_page=0"
  python3 - "$q" <<'PY'
import json, sys, re
def txt(v):
    if isinstance(v, list): v = next((x for x in v if isinstance(x, dict) and x.get("_lang") == "es"), v[0] if v else "")
    if isinstance(v, dict): v = v.get("_value") or v.get("_about") or ""
    return str(v)
try:
    items = json.load(open("/tmp/sonde/dg.json")).get("result", {}).get("items", [])
    print("   requête", sys.argv[1], ":", len(items), "jeux de données")
    n = 0
    for it in items:
        t = txt(it.get("title"))
        if not re.search(r"antena|telefon|m[oó]vil|radioel|estacion|cobertura", t, re.I): continue
        dist = it.get("distribution") or []
        if isinstance(dist, dict): dist = [dist]
        fmts = sorted({txt((d.get("format") or {}).get("value") if isinstance(d.get("format"), dict) else d.get("format")).split("/")[-1] for d in dist if isinstance(d, dict)})
        print("    -", t[:110], "| éditeur:", txt(it.get("publisher")).split("/")[-1], "| licence:", txt(it.get("license"))[:70], "| formats:", fmts[:5], "|", txt(it.get("_about")).split("/")[-1][:70])
        n += 1
        if n >= 14: break
except Exception as e:
    print("   ERREUR", e, open("/tmp/sonde/dg.json", errors="replace").read()[:200].replace("\n", " "))
PY
done

echo "##### 3. Catalogne : catalogue des données ouvertes (API Socrata)"
for q in "telefonia%20m%C3%B2bil" "antenes" "cobertura%20m%C3%B2bil" "estacions%20base"; do
  get "$T/cat.json" "https://analisi.transparenciacatalunya.cat/api/catalog/v1?q=$q&limit=8&only=datasets"
  python3 - "$q" <<'PY'
import json, sys
try:
    d = json.load(open("/tmp/sonde/cat.json")); res = d.get("results", [])
    print("   requête", sys.argv[1], ":", d.get("resultSetSize"), "résultats")
    for r in res[:8]:
        x = r.get("resource", {}); m = r.get("metadata", {})
        print("    -", (x.get("name") or "")[:100], "| id:", x.get("id"), "| maj:", (x.get("updatedAt") or "")[:10], "| licence:", m.get("license"), "| attribution:", (x.get("attribution") or "")[:50], "| colonnes:", (x.get("columns_field_name") or [])[:14])
except Exception as e:
    print("   ERREUR", e, open("/tmp/sonde/cat.json", errors="replace").read()[:200].replace("\n", " "))
PY
done

echo "##### 4. Aragon et Navarre : catalogues CKAN"
for base in "https://opendata.aragon.es/ckan/api/3/action" "https://datosabiertos.navarra.es/api/3/action"; do
  for q in "telefon%C3%ADa%20m%C3%B3vil" "antenas"; do
    get "$T/ck.json" "$base/package_search?q=$q&rows=8"
    python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/ck.json"))["result"]
    print("     ", d.get("count"), "résultats")
    for p in d.get("results", [])[:8]:
        print("    -", (p.get("title") or "")[:100], "| org:", ((p.get("organization") or {}).get("title") or "")[:40], "| licence:", p.get("license_id") or p.get("license_title"), "| formats:", sorted({(r.get("format") or "") for r in p.get("resources", [])})[:5])
except Exception as e:
    print("     ERREUR", e, open("/tmp/sonde/ck.json", errors="replace").read()[:160].replace("\n", " "))
PY
  done
done

echo "##### 5. Italie : catalogue national dati.gov.it (CKAN, fédère régions et ARPA)"
for q in "%22stazioni%20radio%20base%22" "telefonia%20mobile%20impianti" "%22impianti%20di%20telecomunicazione%22" "catasto%20impianti%20radioelettrici" "SRB%20telefonia"; do
  get "$T/it.json" "https://www.dati.gov.it/opendata/api/3/action/package_search?q=$q&rows=60"
  python3 - "$q" <<'PY'
import json, sys, re, collections
try:
    d = json.load(open("/tmp/sonde/it.json"))["result"]; res = d.get("results", [])
    print("   requête", sys.argv[1], ":", d.get("count"), "résultats,", len(res), "lus")
    def holder(p): return (p.get("holder_name") or (p.get("organization") or {}).get("title") or "")
    cnt = collections.Counter(holder(p)[:45] for p in res)
    print("     détenteurs :", cnt.most_common(12))
    n = 0
    for p in res:
        h = holder(p); t = p.get("title") or ""
        if not re.search(r"piemont|aosta|vall[ée]e|liguri|arpa", h + " " + t, re.I): continue
        if not re.search(r"telefon|radio|telecom|antenn|srb|elettromagn", t + " " + (p.get("notes") or "")[:300], re.I): continue
        print("    -", t[:100], "| détenteur:", h[:45], "| licence:", p.get("license_title") or p.get("license_id"), "| formats:", sorted({(r.get("format") or "") for r in p.get("resources", [])})[:6], "| nom:", (p.get("name") or "")[:70])
        n += 1
        if n >= 10: break
except Exception as e:
    print("   ERREUR", e, open("/tmp/sonde/it.json", errors="replace").read()[:200].replace("\n", " "))
PY
done

echo "##### 6. Italie : géoportail ARPA Piemonte (recherche du catalogue)"
get "$T/arpa.json" "https://webgis.arpa.piemonte.it/geoportalserver_arpa/rest/find/document?searchText=telefonia&f=pjson&max=15"
python3 - <<'PY'
import json
try:
    d = json.load(open("/tmp/sonde/arpa.json"))
    recs = d.get("records") or d.get("features") or []
    print("   enregistrements :", len(recs))
    for r in recs[:15]:
        print("    -", (r.get("title") or (r.get("properties") or {}).get("title") or "")[:110], "|", [l.get("href") for l in (r.get("links") or (r.get("properties") or {}).get("links") or [])][:2])
except Exception as e:
    print("   ERREUR", e, open("/tmp/sonde/arpa.json", errors="replace").read()[:300].replace("\n", " "))
PY

echo "##### 7. Andorre : portails de données ouvertes et infrastructure de données spatiales"
for u in "https://www.dadesobertes.ad/" "https://dadesobertes.ad/" "https://opendata.ad/" "https://www.ideandorra.ad/" "https://www.estadistica.ad/"; do
  get "$T/ad.html" "$u"; titre "$T/ad.html"
  liens "$T/ad.html" "telecom|antena|antene|cobertura|m[oò]bil|dades obertes|open ?data|cat[aà]leg|descarreg|llic[eè]ncia" | head -12
done

echo "##### 8. Monaco : portail de données ouvertes"
get "$T/mc.html" "https://data.gouv.mc/"; titre "$T/mc.html"
for api in "https://data.gouv.mc/api/explore/v2.1/catalog/datasets?limit=100" "https://data.gouv.mc/api/3/action/package_list" "https://data.gouv.mc/api/1/datasets/?page_size=100"; do
  get "$T/mc.json" "$api"
  python3 - <<'PY'
import json, re
try:
    d = json.load(open("/tmp/sonde/mc.json"))
    if "results" in d and isinstance(d["results"], list):   # Opendatasoft
        names = [((x.get("metas") or {}).get("default") or {}).get("title") or x.get("dataset_id") for x in d["results"]]
        print("     Opendatasoft :", d.get("total_count"), "jeux ;", [n for n in names if re.search(r"antenn|t[ée]l[ée]ph|mobile|onde|radio|r[ée]seau|4G|5G", str(n), re.I)][:20])
        print("     tous les titres :", [str(n)[:50] for n in names][:100])
    elif "result" in d:                                      # CKAN
        r = d["result"]; print("     CKAN :", len(r), "jeux ;", [n for n in r if re.search(r"antenn|telephon|mobile|onde|radio|reseau|4g|5g", str(n), re.I)][:20]); print("     tous :", r[:100])
    elif "data" in d:                                        # udata
        names = [x.get("title") for x in d["data"]]
        print("     udata :", d.get("total"), "jeux ;", [n for n in names if re.search(r"antenn|t[ée]l[ée]ph|mobile|onde|radio|r[ée]seau|4G|5G", str(n), re.I)][:20]); print("     tous :", [str(n)[:50] for n in names][:100])
    else: print("     ", json.dumps(d)[:200])
except Exception as e:
    print("     (pas de JSON :", str(e)[:60], ")")
PY
done 2>&1 | cut -c1-2500
liens "$T/mc.html" "licen|jeux|dataset|api|catalog|th[eè]me" | head -14
echo "FIN"
