#!/usr/bin/env bash
# Estimation, sonde 5 : dernières pages de documentation. OpenCelliD (guide de téléchargement, format de la base,
# statistiques par pays), opérateurs dans le fichier suisse, ARPA Piemonte (licence et WFS), Ligurie, Monaco.
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
for l in out.split("\n"): print("   |", l[:800])
PY
}

echo "##### A. OpenCelliD : guide de téléchargement et format de la base"
get "$T/dl.html" "https://opencellid.org/downloads.php"
get "$T/intro.html" "https://docs.opencellid.org/docs/introduction"
get "$T/acc.html" "https://docs.opencellid.org/docs/getting-started/access-and-limits"
python3 - <<'PY' > "$T/urls.txt"
import re, html
seen = []
for f, base in (("dl.html", "https://opencellid.org"), ("intro.html", "https://docs.opencellid.org"), ("acc.html", "https://docs.opencellid.org")):
    s = open("/tmp/sonde/" + f, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', s, flags=re.S | re.I):
        href = html.unescape(m.group(1)).split("#")[0]; label = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", m.group(2))).strip()
        if href.startswith("/"): href = base + href
        if not href.startswith("http"): continue
        if re.search(r"download|database|format|dataset|coverage|missing|stat", href + " " + label, re.I) and "unwiredlabs" not in href and href not in [u for u, _ in seen]:
            seen.append((href, label))
for u, l in seen: print(u, "|", l[:70])
PY
cut -c1-220 "$T/urls.txt" | head -20
n=0
for u in $(grep -i -E "docs\.opencellid\.org" "$T/urls.txt" | grep -v -E "access-and-limits|introduction$" | awk '{print $1}' | head -5); do
  n=$((n+1)); echo "--- $u"
  get "$T/p$n.html" "$u"
  contenu "$T/p$n.html" 6500
done
echo "--- questions fréquentes : positions, portée, échantillons"
get "$T/faq.html" "https://docs.opencellid.org/docs/help/troubleshooting"
autour "$T/faq.html" "exact location of a physical tower|What does the range|What does samples|changeable|How often|how current|Why is a cell missing|duplicate" 750 6
echo "--- statistiques par pays"
s=$(grep -i -E "stat" "$T/urls.txt" | grep "opencellid.org" | awk '{print $1}' | head -1); [ -z "$s" ] && s="https://opencellid.org/stats.php"
get "$T/stats.html" "$s"
python3 - <<'PY'
import re, html
s = open("/tmp/sonde/stats.html", encoding="utf-8", errors="replace").read()
rows = re.findall(r"<tr\b.*?</tr>", s, flags=re.S | re.I)
print("   lignes de tableau :", len(rows))
def cells(r): return [re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", c))).strip() for c in re.findall(r"<t[dh]\b.*?</t[dh]>", r, flags=re.S | re.I)]
for r in rows[:2]: print("   en-tête :", cells(r)[:12])
for r in rows:
    c = cells(r)
    if c and re.search(r"^(Andorra|Monaco|Italy|Spain|Switzerland|France)$", c[0].strip(), re.I) or (len(c) > 1 and re.search(r"^(Andorra|Monaco|Italy|Spain|Switzerland|France)$", c[1].strip(), re.I)):
        print("   ", c[:12])
if not rows: print("   ", re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", re.sub(r"<(script|style)\b.*?</\1>", " ", s, flags=re.S))))[:900])
PY

echo "##### B. Suisse : opérateurs dans le champ station"
get "$T/ch.json" "https://data.geo.admin.ch/ch.bakom.standorte-mobilfunkanlagen/standorte-mobilfunkanlagen/standorte-mobilfunkanlagen_2056.json"
python3 - <<'PY'
import json, collections, re
d = json.load(open("/tmp/sonde/ch.json", encoding="utf-8")); feats = d["features"]
op = collections.Counter(); cross = collections.Counter(); pat = collections.Counter()
for f in feats:
    p = f["properties"]; name = (p.get("station") or "").split(" ")[0]; op[name] += 1
    pat[re.sub(r"[0-9]", "9", re.sub(r"[A-Za-z]", "a", (p.get("station") or "")[len(name):]))[:14]] += 1
    t = p.get("techno_en", "").replace("Technology ", ""); out = p.get("typ_en", "")
    if "4G" in t or "5G" in t: cross[(name, out)] += 1
print("   premier mot de station :", op.most_common(10))
print("   sites 4G ou 5G par opérateur et type :", sorted(cross.items(), key=lambda kv: -kv[1])[:16])
k = collections.Counter(tuple(f["geometry"]["coordinates"]) for f in feats)
print("   positions distinctes :", len(k), "sur", len(feats), "| positions partagées par plusieurs lignes :", sum(1 for v in k.values() if v > 1))
PY

echo "##### C. ARPA Piemonte : licence du service et WFS"
apt-get install -y -qq poppler-utils >/dev/null 2>&1
get "$T/lic.pdf" "http://webgis.arpa.piemonte.it/w-metadoc/_Licenze/Licenza_map_service.pdf"
pdftotext -layout "$T/lic.pdf" "$T/lic.txt" 2>/dev/null && python3 -c "
import re
s = re.sub(r'\s+', ' ', open('/tmp/sonde/lic.txt', encoding='utf-8', errors='replace').read()).strip()
print('   longueur :', len(s)); print('   |', s[:2600])"
get "$T/ms.json" "https://webgis.arpa.piemonte.it/ags101free/rest/services/campi_elettromagnetici/Radiazioni_non_ionizzanti_pubblico/MapServer?f=pjson"
head -c 300 "$T/ms.json"; echo
W="WFS:https://webgis.arpa.piemonte.it/ags101free/services/campi_elettromagnetici/Radiazioni_non_ionizzanti_pubblico/MapServer/WFSServer?"
ogrinfo -ro -so "$W" 2>&1 | cut -c1-200 | head -14
for l in $(ogrinfo -ro -so "$W" 2>/dev/null | grep -E "^[0-9]+:" | sed -E 's/^[0-9]+: ([^ ]+).*/\1/' | head -3); do
  echo "--- couche $l"
  ogrinfo -ro -so "$W" "$l" 2>&1 | grep -v -E "^(PROJCRS|GEOGCRS|    |  [A-Z]+\[|INFO)" | cut -c1-160 | head -45
  ogrinfo -ro -al -limit 2 -geom=SUMMARY "$W" "$l" 2>&1 | grep -E "^  [A-Za-z_]+ \(" | cut -c1-200 | head -60
done

echo "##### D. Ligurie : fiche du catalogue national"
get "$T/lig.json" "https://www.dati.gov.it/opendata/api/3/action/package_search?q=liguria%20telecomunicazion*&rows=3"
python3 - <<'PY'
import json
try:
    for p in json.load(open("/tmp/sonde/lig.json"))["result"]["results"][:3]:
        print("   titre :", p.get("title"), "| nom :", p.get("name"), "| détenteur :", p.get("holder_name"), "| licence :", p.get("license_title"), "| identifiant :", p.get("identifier"), "| modifié :", p.get("modified") or p.get("metadata_modified"))
        print("   notes :", (p.get("notes") or "")[:900].replace("\n", " "))
        for r in p.get("resources", [])[:8]: print("     ressource :", r.get("format"), "|", (r.get("name") or "")[:60], "|", r.get("url"), "| licence :", r.get("license") or r.get("license_type"))
        ex = {e.get("key"): e.get("value") for e in p.get("extras", [])} if isinstance(p.get("extras"), list) else {}
        print("   extras :", {k: str(v)[:120] for k, v in ex.items() if k in ("holder_name", "source", "access_rights", "conforms_to", "creator_name", "publisher_name", "spatial", "frequency")})
except Exception as e: print("   ERREUR", e)
PY

echo "##### E. Monaco : nouvel essai"
for u in "https://data.gouv.mc/" "https://data.gouv.mc/explore/"; do
  curl -sS -m 60 -A "$UA" -o "$T/mc.html" -w "  -> %{http_code} %{size_download}o $u\n" "$u"
  python3 -c "
import re,html
s=open('/tmp/sonde/mc.html',encoding='utf-8',errors='replace').read()
m=re.search(r'<title[^>]*>(.*?)</title>',s,flags=re.S|re.I)
print('   titre :', html.unescape(re.sub(r'\s+',' ',m.group(1))).strip()[:160] if m else '(aucun)')"
done
echo "FIN"
