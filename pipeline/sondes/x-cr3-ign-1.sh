#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Autocomplétion de la Géoplateforme : forme des réponses (kind, poiType, names, zipcode),
# effet et acceptation du paramètre lonlat (longitude positive et négative). Quelques requêtes espacées.
B="https://data.geopf.fr/geocodage/completion"
show() { # show <fichier>
  python3 - "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    print("  JSON illisible :", e, open(sys.argv[1], encoding="utf-8", errors="replace").read()[:300]); sys.exit()
if not isinstance(d, dict) or "results" not in d:
    print("  ", json.dumps(d, ensure_ascii=False)[:400]); sys.exit()
print("  status", d.get("status"), "nb", len(d["results"]))
for r in d["results"]:
    keep = {k: r.get(k) for k in ("country", "kind", "poiType", "names", "street", "city", "zipcode", "fulltext", "classification")}
    keep["xy"] = [round(r.get("x", 0), 3), round(r.get("y", 0), 3)]
    print("   ", json.dumps(keep, ensure_ascii=False)[:330])
PY
}
q() { # q <etiquette> <parametres>
  echo "== $1"
  get "$T/r.json" "$B?$2"
  show "$T/r.json"
  sleep 1
}
q "Briançon sans lonlat" "text=Brian%C3%A7on&type=PositionOfInterest,StreetAddress&terr=METROPOLE&maximumResponses=6"
q "Briançon, lonlat Briançon" "text=Brian%C3%A7on&type=PositionOfInterest,StreetAddress&terr=METROPOLE&maximumResponses=6&lonlat=6.64,44.90"
q "Saint-Jean sans lonlat" "text=Saint-Jean&type=PositionOfInterest,StreetAddress&terr=METROPOLE&maximumResponses=6"
q "Saint-Jean, lonlat Bayonne (longitude negative)" "text=Saint-Jean&type=PositionOfInterest,StreetAddress&terr=METROPOLE&maximumResponses=6&lonlat=-1.47,43.48"
q "Saint-Jean, lonlat Nice" "text=Saint-Jean&type=PositionOfInterest,StreetAddress&terr=METROPOLE&maximumResponses=6&lonlat=7.25,43.70"
q "Hautes-Alpes" "text=Hautes-Alpes&type=PositionOfInterest,StreetAddress&terr=METROPOLE&maximumResponses=4"
q "Refuge du Glacier Blanc" "text=Refuge%20du%20Glacier%20Blanc&type=PositionOfInterest,StreetAddress&terr=METROPOLE&maximumResponses=4"
q "Chamonix" "text=Chamonix&type=PositionOfInterest,StreetAddress&terr=METROPOLE&maximumResponses=6"
q "10 rue de la Paix" "text=10%20rue%20de%20la%20Paix&type=StreetAddress&terr=METROPOLE&maximumResponses=3"
echo "== OpenAPI de l'autocomplétion (paramètre lonlat)"
get "$T/c.yaml" "https://data.geopf.fr/geocodage/completion/openapi.yaml"
grep -n -i -A14 'name: lonlat' "$T/c.yaml" | cut -c1-200 | head -30
