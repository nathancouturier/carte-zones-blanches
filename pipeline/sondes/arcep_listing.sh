#!/usr/bin/env bash
# Vérifie le listing Arcep (noms et tailles des fichiers), le style classique, et les en-têtes CORS des géocodeurs.
set -u
T=/tmp/sonde; mkdir -p "$T"
UA="carte-zones-blanches-sonde/1.0"
get() { # get <fichier> <url> : télécharge (3 essais) et affiche code HTTP, taille, type
  local code i
  for i in 1 2 3; do
    code=$(curl -sS -L -m 180 -A "$UA" -o "$1" -w "%{http_code} %{size_download}o %{content_type}" "$2" 2>&1) && break
    sleep 3
  done
  echo "  -> $code  $2"
}

echo "##### 1. Style classique"
get "$T/classique.json" "https://data.geopf.fr/annexes/ressources/vectorTiles/styles/PLAN.IGN/classique.json"
get "$T/standard.json" "https://data.geopf.fr/annexes/ressources/vectorTiles/styles/PLAN.IGN/standard.json"
python3 - <<'PY'
import json, collections
out = {}
for s in ("classique", "standard"):
    d = json.load(open(f"/tmp/sonde/{s}.json"))
    L = d["layers"]
    i = next((i for i, l in enumerate(L) if l["type"] == "symbol"), None)
    print(f"[{s}] name={d.get('name')!r} couches={len(L)} {dict(collections.Counter(l['type'] for l in L))} premiere symbol: {i} {L[i]['id']!r}")
    print("   sources:", json.dumps(d.get("sources"), ensure_ascii=False))
    print("   sprite:", d.get("sprite"), "| glyphs:", d.get("glyphs"))
    # couches non symbol situées après la première couche symbol
    apres = collections.Counter(l["type"] for l in L[i:])
    print("   types apres la premiere symbol:", dict(apres))
    print("   minzoom/maxzoom globaux:", min(l.get("minzoom", 0) for l in L), max(l.get("maxzoom", 24) for l in L))
    print("   background:", [json.dumps(l.get("paint")) for l in L if l["type"] == "background"], "| couche 0:", json.dumps(L[0])[:300])
PY
for f in sprite/PlanIgn.json sprite/PlanIgn.png sprite/PlanIgn@2x.json sprite/PlanIgn@2x.png; do
  get "$T/sp" "https://data.geopf.fr/annexes/ressources/vectorTiles/styles/PLAN.IGN/$f"
done
get "$T/glyph" "https://data.geopf.fr/annexes/ressources/vectorTiles/fonts/Source%20Sans%20Pro%20Regular/0-255.pbf"

echo "##### 2. Listing Arcep (HTML brut sans scripts)"
get "$T/arcep.html" "https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/00_Metropole/"
python3 - <<'PY'
import re
s = open("/tmp/sonde/arcep.html", encoding="utf-8", errors="replace").read()
s = re.sub(r"<script.*?</script>", "", s, flags=re.S)
s = re.sub(r"<style.*?</style>", "", s, flags=re.S)
s = re.sub(r"\n\s*\n+", "\n", s)
print(s[:7000])
PY
for u in "https://data.arcep.fr/mobile/couvertures_theoriques/last/" "https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/" "https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/00_Metropole/index.json" "https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/00_Metropole/index.html"; do
  get "$T/x.html" "$u"
  python3 - <<'PY'
import re
s = open("/tmp/sonde/x.html", encoding="utf-8", errors="replace").read()
s = re.sub(r"<script.*?</script>", "", s, flags=re.S); s = re.sub(r"<style.*?</style>", "", s, flags=re.S)
hrefs = re.findall(r'href="([^"]+)"', s)
print("   liens:", [h for h in hrefs if not h.startswith("http") and "bootstrap" not in h][:60])
PY
done

echo "##### 3. CORS des géocodeurs (avec en-tête Origin)"
for u in "https://data.geopf.fr/geocodage/completion?text=lac%20d%27allos&type=PositionOfInterest,StreetAddress&maximumResponses=3&terr=METROPOLE" \
         "https://data.geopf.fr/geocodage/search?q=gap&limit=1" \
         "https://photon.komoot.io/api/?q=zermatt&limit=1" \
         "https://photon.komoot.io/api/?q=ordino&limit=2&lang=default&bbox=-5.5,39.5,10.8,51.3"; do
  echo "--- $u"
  curl -sS -m 60 -A "$UA" -H "Origin: https://nathancouturier.github.io" -D "$T/h.txt" -o "$T/b.json" "$u"
  grep -i -E "^(HTTP|access-control-allow-origin|x-ratelimit|ratelimit|content-type)" "$T/h.txt" | tr -d '\r'
  head -c 500 "$T/b.json"; echo
done
echo "FIN"
