#!/usr/bin/env bash
# Sonde gpx-2 : schéma officiel GPX 1.1 (pour valider les fichiers ici), page de la licence ODbL 1.0,
# directives d'attribution de la fondation OpenStreetMap. Trois requêtes, l'une après l'autre.
set -u
. "$(dirname "$0")/_lib.sh"
cd "$T"

echo "### 1. Schéma GPX 1.1 (topografix)"
code=$(curl -sS -L -m 120 -A "$UA" -o gpx.xsd -w "%{http_code} %{size_download}o %{content_type} %{url_effective}" "https://www.topografix.com/GPX/1/1/gpx.xsd" 2>&1)
echo "  -> $code"
sha256sum gpx.xsd | cut -c1-64
grep -o 'targetNamespace="[^"]*"' gpx.xsd | head -2
grep -n -E '<xsd:(element|complexType) name="(gpx|metadataType|copyrightType|linkType|trkType|trksegType|wptType)"' gpx.xsd | cut -c1-120 | head -10
echo "=== DEBUT gpx.xsd ==="
base64 -w 1000 gpx.xsd
echo "=== FIN gpx.xsd ==="

sleep 3
echo "### 2. Licence ODbL 1.0 (Open Data Commons)"
code=$(curl -sS -L -m 120 -A "$UA" -o odbl.html -w "%{http_code} %{size_download}o %{content_type} %{url_effective}" "https://opendatacommons.org/licenses/odbl/1-0/" 2>&1)
echo "  -> $code"
grep -o '<title>[^<]*</title>' odbl.html | head -1
texte odbl.html 100000 > odbl.txt
python3 - odbl.txt <<'PY'
import re, sys
s = re.sub(r"\s+", " ", open(sys.argv[1], encoding="utf-8").read())
for m in re.finditer(r"[^.]{0,200}(?:Open Database License|ODbL)[^.]{0,200}\.", s):
    print("  > " + m.group(0).strip()[:300])
    break
for m in re.finditer(r"[^.]{0,250}(?:Derivative Database)[^.]{0,250}\.", s):
    t = m.group(0).strip()
    if "Publicly" in t or "Share" in t or "offer" in t:
        print("  > " + t[:400])
PY

sleep 3
echo "### 3. Directives d'attribution (fondation OpenStreetMap)"
get attr.html "https://osmfoundation.org/wiki/Licence/Attribution_Guidelines"
texte attr.html 300000 > attr.txt
python3 - attr.txt <<'PY'
import re, sys
s = re.sub(r"\s+", " ", open(sys.argv[1], encoding="utf-8").read())
phr = re.split(r"(?<=[.!?])\s+", s)
mots = ("contributors", "translat", "language", "acceptable", "openstreetmap.org/copyright", "Open Database License")
n = 0
for p in phr:
    if any(m.lower() in p.lower() for m in mots):
        print("  > " + p[:350]); n += 1
    if n >= 14: break
PY
echo "### fin"
