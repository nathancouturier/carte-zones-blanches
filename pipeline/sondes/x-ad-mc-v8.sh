#!/usr/bin/env bash
# Contre-vérification « Andorre et Monaco », sonde 8 (dernière) : que dit le Gouvernement Princier lui-même de la
# réutilisation des données de cartoradio.mc (communiqué de mise en ligne, page « carte des mesures ») et de son
# « Programme Data » (avis de recrutement paru au Journal de Monaco) ? Pages officielles seulement.
set -u
. "$(dirname "$0")/_lib.sh"
UA="sonde-sources-ouvertes/1.0"   # User-Agent générique (pas de nom de projet ni de compte envoyé à des tiers)
export UA
cd "$T" || exit 1
g() { # g <fichier> <url> : un seul essai, délais courts ; affiche code, taille, type, adresse finale
  local f="$1" u="$2" r
  r=$(curl -sS -L --connect-timeout 12 -m 90 -A "$UA" -o "$f" -w "%{http_code} %{size_download}o %{content_type} final=%{url_effective}" "$u" 2>&1)
  echo "  -> $r | $u" | cut -c1-280
}
cat > lire.py <<'PY'
# Affiche le titre, le début du texte principal et le contexte de quelques motifs.
import re, html, sys
try:
    s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except Exception as e:
    print("     illisible :", e); raise SystemExit
t = re.search(r"<title[^>]*>(.*?)</title>", s, re.S | re.I)
print("     titre :", html.unescape(t.group(1)).strip()[:170] if t else None)
m = re.search(r"<main\b.*?</main>", s, re.S | re.I)
part = m.group(0) if m else s
b = re.sub(r"<(script|style|svg|noscript|nav|header|footer|form)\b.*?</\1>", " ", part, flags=re.S | re.I)
b = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
print("     texte principal : %d caractères | début : %s" % (len(b), b[:int(sys.argv[2])]))
seen = []
for w in sys.argv[3:]:
    ms = [x.start() for x in re.finditer(w, b, re.I)]
    print("     motif « %s » : %d" % (w, len(ms)))
    for q in ms[:2]:
        if any(abs(q - z) < 260 for z in seen):
            continue
        seen.append(q)
        print("        «" + b[max(0, q - 260): q + 300] + "»")
PY

echo "### A. Communiqué du Gouvernement sur la mise en ligne de cartoradio.mc"
g a.html "https://www.gouv.mc/actualites/le-site-web-www.cartoradio.mc-est-en-ligne-la-cartographie-des-ondes-en-principaute-est-effective"
python3 lire.py a.html 700 'open ?data' 'donn[ée]es ouvertes' 'r[ée]utilis' 'licence' 'librement|libre acc' 't[ée]l[ée]charg' 'couverture' 'op[ée]rateurs?' 'transparen' '20\d\d'

echo "### B. Page « Carte des mesures électromagnétiques » (version française)"
g b.html "https://www.gouv.mc/action-gouvernementale/poursuivre-la-transition-energetique-et-renaturer-la-ville/reduire-les-emissions-de-gaz-a-effet-de-serre/carte-des-mesures-electromagnetiques"
python3 lire.py b.html 500 'open ?data' 'donn[ée]es ouvertes' 'r[ée]utilis' 'licence' 'cartoradio' 'couverture'

echo "### C. Journal de Monaco : avis de recrutement du « Responsable du Programme Data »"
python3 - <<'PY'
import re, html, os, urllib.request, urllib.parse
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
def fetch(u):
    with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=60) as r:
        return r.read().decode("utf-8", "replace")
u = "https://journaldemonaco.gouv.mc/content/search?" + urllib.parse.urlencode({"SearchText": '"Responsable du Programme Data"'})
try:
    p = fetch(u)
except Exception as e:
    print("  recherche : échec", str(e)[:120]); raise SystemExit
hits = []
for h, x in re.findall(r'<a\b[^>]*href="(/Journaux/\d{4}/[^"]+)"[^>]*>(.*?)</a>', p, re.S | re.I):
    x = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", x))).strip()
    if "Programme Data" in x and (h, x) not in hits:
        hits.append((h, x))
print("  avis trouvés :", len(hits))
for h, x in hits[:2]:
    print("    ", x[:150], "|", h[:150])
if hits:
    try:
        s = fetch("https://journaldemonaco.gouv.mc" + urllib.parse.quote(html.unescape(hits[0][0]), safe="/%?=&"))
        open("c.html", "w", encoding="utf-8").write(s)
    except Exception as e:
        print("  lecture de l'avis : échec", str(e)[:120])
PY
[ -s c.html ] && python3 lire.py c.html 300 'open ?data' 'data\.gouv' 'donn[ée]es ouvertes' 'plateforme' 'portail' 'catalogue' 'Programme Data'

echo "### D. data.gouv.mc à l'heure de cette sonde"
r=$(curl -sS --connect-timeout 12 -m 40 -A "$UA" -o /dev/null -w "%{http_code} %{size_download}o" "https://data.gouv.mc/" 2>&1)
echo "  https://data.gouv.mc/ : $r | $(date -u +'%Y-%m-%d %H:%M UTC')"
echo "### fin"
