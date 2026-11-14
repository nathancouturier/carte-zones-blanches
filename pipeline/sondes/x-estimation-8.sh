#!/usr/bin/env bash
# Estimation, sonde 8 (dernière) : texte de la licence CC BY-SA 4.0 (attribution, partage à l'identique, bases de
# données), consignes d'attribution d'OpenCelliD (emplacement), opérateurs du fichier ligure, dernier essai Monaco.
set -u
. "$(dirname "$0")/_lib.sh"
cd "$T"

echo "##### A. CC BY-SA 4.0 : extraits du texte juridique"
get "$T/cc.txt" "https://creativecommons.org/licenses/by-sa/4.0/legalcode.txt"
python3 - <<'PY'
import re
s = open("/tmp/sonde/cc.txt", encoding="utf-8", errors="replace").read()
if "<html" in s[:2000].lower():
    import html
    s = re.sub(r"<(script|style)\b.*?</\1>", " ", s, flags=re.S | re.I); s = html.unescape(re.sub(r"<[^>]+>", " ", s))
s = re.sub(r"[ \t]+", " ", s); flat = re.sub(r"\s+", " ", s)
print("   longueur :", len(flat), "| début :", flat[:160])
def cut(start, end, maxlen):
    i = flat.find(start)
    if i < 0: print("   (introuvable :", start, ")"); return
    j = flat.find(end, i + len(start)); j = j if j > 0 else i + maxlen
    print("   |", flat[i:min(j, i + maxlen)].strip())
cut("a. Adapted Material means", "b. Adapter's License", 700)
cut("b. Adapter's License means", "c. BY-SA Compatible License", 400)
cut("Section 3 -- License Conditions", "4. If requested by the Licensor", 1900)
cut("b. ShareAlike.", "Section 4", 1100)
cut("Section 4 -- Sui Generis Database Rights", "Section 5", 1100)
PY

echo "##### B. OpenCelliD : page License and attribution, contenu complet"
get "$T/att.html" "https://docs.opencellid.org/docs/attribution"
python3 - <<'PY'
import re, html
s = open("/tmp/sonde/att.html", encoding="utf-8", errors="replace").read()
m = re.search(r"<article\b.*?</article>", s, flags=re.S | re.I) or re.search(r"<main\b.*?</main>", s, flags=re.S | re.I)
if m: s = m.group(0)
s = re.sub(r"<(script|style|svg|noscript|nav|button|pre)\b.*?</\1>", " ", s, flags=re.S | re.I)
s = re.sub(r"<br\s*/?>|</(p|div|li|tr|h[1-6]|summary|details)>", "\n", s, flags=re.I)
s = html.unescape(re.sub(r"<[^>]+>", " ", s)); s = re.sub(r"[ \t\r\f\v]+", " ", s)
for l in [l.strip() for l in s.split("\n") if l.strip()][:60]: print("   |", l[:700])
PY

echo "##### C. Ligurie : opérateurs et qualité des positions dans la couche des installations actives"
W="WFS:https://geoservizi.regione.liguria.it/geoserver/M2196/wfs"
ogrinfo -ro -so "$W" "M2196:L7991" 2>&1 | grep -E "ID\[\"EPSG\"|PROJCRS\[|Feature Count|Extent" | tail -4 | cut -c1-200
ogr2ogr -f CSV "$T/lig.csv" "$W" "M2196:L7991" -select d_gestore,d_provincia,coordinate_arpal,flgimpiantoattivo,f_data_collaudo -lco GEOMETRY=AS_XY 2>&1 | head -3
python3 - <<'PY'
import csv, collections
try:
    rows = list(csv.DictReader(open("/tmp/sonde/lig.csv", encoding="utf-8", errors="replace")))
    print("   lignes :", len(rows), "| colonnes :", list(rows[0].keys()) if rows else None)
    print("   exploitants :", collections.Counter(r.get("d_gestore") for r in rows).most_common(14))
    print("   provinces :", collections.Counter(r.get("d_provincia") for r in rows).most_common(6))
    print("   position vérifiée par ARPAL :", collections.Counter(r.get("coordinate_arpal") for r in rows).most_common(4))
    xs = [float(r.get("X") or 0) for r in rows]; ys = [float(r.get("Y") or 0) for r in rows]
    print("   coordonnées nulles :", sum(1 for x, y in zip(xs, ys) if x == 0 or y == 0), "| X de", min(x for x in xs if x) if any(xs) else None, "à", max(xs) if xs else None, "| Y de", min(y for y in ys if y) if any(ys) else None, "à", max(ys) if ys else None)
    print("   années de mise en service (f_data_collaudo) :", sorted(collections.Counter((r.get("f_data_collaudo") or "")[-4:] for r in rows).items(), key=lambda kv: -kv[1])[:8])
except Exception as e: print("   ERREUR", e)
PY

echo "##### D. Monaco : dernier essai"
curl -sS -m 60 -A "$UA" -o "$T/mc.html" -w "  -> %{http_code} %{size_download}o https://data.gouv.mc/\n" "https://data.gouv.mc/"
grep -o -i -E "<title[^>]*>[^<]*" "$T/mc.html" | head -1 | cut -c1-200
echo "FIN"
