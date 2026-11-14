#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
echo "##### Jeu « Contours administratifs » sur data.gouv.fr : licence et fichiers"
get "$T/ca.json" "https://www.data.gouv.fr/api/1/datasets/contours-administratifs/"
python3 - "$T/ca.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print("titre:", d.get("title"), "| licence:", d.get("license"), "| organisation:", (d.get("organization") or {}).get("name"), "| page:", d.get("page"))
print("modifié:", d.get("last_modified"), "| fréquence:", d.get("frequency"))
desc = " ".join((d.get("description") or "").split())
print("description:", desc[:1500])
for r in (d.get("resources") or [])[:12]:
    print("  ressource:", (r.get("title") or "")[:80], "|", (r.get("url") or "")[:160])
PY
echo "##### Lisez-moi du dossier publié"
for u in "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/" "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/"; do
  get "$T/idx.html" "$u"; texte "$T/idx.html" 600; echo
done
echo "##### Lisez-moi du dépôt etalab/contours-administratifs : lignes sur la licence"
get "$T/readme.md" "https://raw.githubusercontent.com/etalab/contours-administratifs/master/README.md"
grep -n -i "licen\|odbl\|ouverte\|open licence\|osm\|openstreetmap" "$T/readme.md" | cut -c1-400 | head -30
get "$T/pkg.json" "https://raw.githubusercontent.com/etalab/contours-administratifs/master/package.json"
grep -n -i '"license"' "$T/pkg.json" | head -3
