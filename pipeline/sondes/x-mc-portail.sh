#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
echo "##### data.gouv.mc : le portail répond-il maintenant ? (quelques requêtes, sans insister)"
code=$(curl -s -o "$T/mc.html" -w '%{http_code}' -A "$UA" --max-time 40 -L "https://data.gouv.mc/")
echo "accueil : HTTP $code, $(wc -c < "$T/mc.html") octets"
if [ "$code" != "200" ]; then
  texte "$T/mc.html" 300; echo
  echo "Portail toujours indisponible : on s'arrête là."
  exit 0
fi
texte "$T/mc.html" 700; echo
grep -o -i 'opendatasoft\|ckan\|udata\|data\.gouv\.fr\|dkan\|arcgis' "$T/mc.html" | sort | uniq -c | head
for api in "api/explore/v2.1/catalog/datasets?limit=100" "api/3/action/package_search?rows=300" "api/1/datasets/?page_size=200"; do
  c=$(curl -s -o "$T/api.json" -w '%{http_code}' -A "$UA" --max-time 40 "https://data.gouv.mc/$api")
  echo "== $api : HTTP $c, $(wc -c < "$T/api.json") octets"
  [ "$c" = "200" ] || continue
  python3 - "$T/api.json" <<'PY'
import json, re, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    print("  pas du JSON :", e); sys.exit(0)
items = d.get("results") or d.get("data") or (d.get("result") or {}).get("results") or []
total = d.get("total_count") or d.get("total") or (d.get("result") or {}).get("count")
print("  jeux annoncés :", total, "| lus :", len(items))
pat = re.compile(r"mobile|couverture|r[ée]seau|t[ée]l[ée]com|antenne|radio|4g|5g|fr[ée]quence", re.I)
for it in items:
    title = it.get("title") or (it.get("metas") or {}).get("default", {}).get("title") or it.get("dataset_id") or ""
    lic = it.get("license") or it.get("license_title") or (it.get("metas") or {}).get("default", {}).get("license") or ""
    if pat.search(str(title)):
        print("  *", str(title)[:110], "| licence :", str(lic)[:60])
print("  premiers titres :", [str(it.get("title") or (it.get("metas") or {}).get("default", {}).get("title") or it.get("dataset_id"))[:50] for it in items[:8]])
PY
  break
done
