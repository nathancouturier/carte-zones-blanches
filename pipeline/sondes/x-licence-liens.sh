#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
echo "##### Les adresses de licence répondent-elles ? (en-têtes seulement, redirections suivies)"
for u in \
  "https://www.etalab.gouv.fr/wp-content/uploads/2014/05/Licence_Ouverte.pdf" \
  "https://www.etalab.gouv.fr/licence-ouverte-open-licence" \
  "https://www.data.gouv.fr/datasets/contours-administratifs" \
  "http://opendatacommons.org/licenses/odbl/summary/" \
  "https://opendatacommons.org/licenses/odbl/1-0/" \
  "https://www.data.gouv.fr/datasets/mon-reseau-mobile"; do
  echo "== $u"
  curl -sIL -A "$UA" --max-time 40 "$u" | grep -i -E "^HTTP/|^location:|^content-type:" | tr -d '\r' | cut -c1-200
done
echo "##### Jeu « Mon réseau mobile » : licence déclarée aujourd'hui"
get "$T/mrm.json" "https://www.data.gouv.fr/api/1/datasets/mon-reseau-mobile/"
python3 - "$T/mrm.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print("titre:", d.get("title"), "| licence:", d.get("license"), "| organisation:", (d.get("organization") or {}).get("name"), "| modifié:", d.get("last_modified"))
PY
