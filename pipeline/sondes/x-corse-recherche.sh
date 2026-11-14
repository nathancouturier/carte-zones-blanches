#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
echo "##### Géocodage IGN (complétion) : terr=METROPOLE propose-t-il des lieux de Corse ?"
for q in "Ajaccio" "Corte" "Bonifacio" "Calvi"; do
  get "$T/c.json" "https://data.geopf.fr/geocodage/completion?text=$q&terr=METROPOLE&type=PositionOfInterest,StreetAddress&maximumResponses=5"
  python3 - "$T/c.json" "$q" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    print("  pas du JSON :", e); sys.exit(0)
print("  ", sys.argv[2], "| statut", d.get("status"), "|", [(r.get("fulltext"), round(r.get("x", 0), 3), round(r.get("y", 0), 3)) for r in d.get("results", [])][:5])
PY
done
