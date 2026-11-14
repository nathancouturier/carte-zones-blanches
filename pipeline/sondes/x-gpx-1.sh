#!/usr/bin/env bash
# Sonde gpx-1 : politique d'usage d'Overpass, mentions OpenStreetMap, puis UNE requête Overpass
# (chemins piétons, routes de randonnée, refuges, cols, lieux, frontière) sur deux emprises serrées.
# Le résultat est compacté (deltas entiers, xz) et affiché en base64 entre deux lignes repères.
set -u
. "$(dirname "$0")/_lib.sh"
cd "$T"

echo "### 1. Politique d'usage d'Overpass (page officielle du manuel)"
get commons.html "https://dev.overpass-api.de/overpass-doc/en/preface/commons.html"
texte commons.html 200000 > commons.txt
python3 - commons.txt <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
s = re.sub(r"\s+", " ", s)
phrases = re.split(r"(?<=[.!?])\s+", s)
mots = ("10000", "10 000", "1 GB", "per day", "rate", "slot", "commercial", "fair", "User-Agent", "load", "heavy")
n = 0
for p in phrases:
    if any(m.lower() in p.lower() for m in mots):
        print("  > " + p[:400]); n += 1
    if n >= 14: break
PY

echo "### 2. Mentions OpenStreetMap (page de copyright, version française)"
get copyright.html "https://www.openstreetmap.org/copyright/fr"
texte copyright.html 200000 > copyright.txt
python3 - copyright.txt <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
s = re.sub(r"\s+", " ", s)
phrases = re.split(r"(?<=[.!?»])\s+", s)
mots = ("ODbL", "Open Database", "contributeurs d", "crédit", "créditer", "attribution", "copyright")
n = 0
for p in phrases:
    if any(m.lower() in p.lower() for m in mots):
        print("  > " + p[:400]); n += 1
    if n >= 12: break
PY

echo "### 3. État du serveur Overpass"
curl -sS -m 30 -A "$UA" "https://overpass-api.de/api/status" | head -8 | cut -c1-200

echo "### 4. Requête Overpass (une seule, deux emprises)"
A="45.68,6.71,45.80,6.91"      # Alpes : Chapieux, vallée des Glaciers, col de la Seigne, val Veny
P="42.65,-0.10,42.745,0.04"    # Pyrénées : Gavarnie, Sarradets, brèche de Roland, Góriz
cat > requete.overpassql <<EOF
[out:json][timeout:180];
( way["highway"~"^(path|footway|track|steps|bridleway|pedestrian)$"]($A);
  way["highway"~"^(path|footway|track|steps|bridleway|pedestrian)$"]($P); )->.chemins;
( rel["route"~"^(hiking|foot)$"]($A); rel["route"~"^(hiking|foot)$"]($P); )->.routes;
( way(r.routes)["highway"]($A); way(r.routes)["highway"]($P); )->.wroutes;
( .chemins; .wroutes; )->.w;
.w out geom;
.routes out body;
( node["tourism"~"^(alpine_hut|wilderness_hut|camp_site)$"]($A); node["tourism"~"^(alpine_hut|wilderness_hut|camp_site)$"]($P);
  way["tourism"~"^(alpine_hut|wilderness_hut)$"]($A); way["tourism"~"^(alpine_hut|wilderness_hut)$"]($P);
  node["natural"="saddle"]($A); node["natural"="saddle"]($P);
  node["mountain_pass"="yes"]($A); node["mountain_pass"="yes"]($P);
  node["place"~"^(village|hamlet|locality|isolated_dwelling)$"]($A); node["place"~"^(village|hamlet|locality|isolated_dwelling)$"]($P); )->.poi;
.poi out center;
( rel["boundary"="administrative"]["admin_level"="2"]($A); rel["boundary"="administrative"]["admin_level"="2"]($P); )->.pays;
( way(r.pays)($A); way(r.pays)($P); )->.frontiere;
.frontiere out geom;
EOF
ok=0
for essai in 1 2 3; do
  code=$(curl -sS -m 300 -A "$UA" -o osm.json -w "%{http_code} %{size_download}o %{time_total}s" \
    --data-urlencode "data@requete.overpassql" "https://overpass-api.de/api/interpreter" 2>&1)
  echo "  essai $essai -> $code"
  case "$code" in 200*) ok=1; break;; esac
  head -c 300 osm.json | tr '\n' ' ' | cut -c1-300; echo
  sleep $((60 * essai))
done
[ "$ok" = 1 ] || { echo "ECHEC Overpass"; exit 0; }

python3 - osm.json <<'PY'
import base64, collections, hashlib, json, lzma, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print("  osm3s :", json.dumps(d.get("osm3s", {}), ensure_ascii=False)[:300])
if d.get("remark"): print("  remarque :", d["remark"][:300])
els = d["elements"]
print("  éléments :", collections.Counter(e["type"] for e in els))
GARDER = ("highway", "name", "ref", "sac_scale", "trail_visibility", "foot", "access", "bridge", "tunnel",
          "informal", "via_ferrata_scale", "hazard", "seasonal", "surface", "tracktype", "boundary", "admin_level",
          "mountain_pass", "natural", "tourism", "place", "ele", "network", "route", "osmc:symbol", "operator",
          "name:fr", "name:it", "name:es", "wikidata")
def tags(e): return {k: v for k, v in e.get("tags", {}).items() if k in GARDER}
ways, routes, pois, front = [], [], [], []
apres = False  # vrai après la sortie des chemins : les chemins suivants avec géométrie sont la frontière
for e in els:
    t = e["type"]
    if t in ("relation", "node"): apres = True
    if t == "way" and "geometry" in e:
        g = e["geometry"]
        nodes = e["nodes"]
        lat = [round(p["lat"] * 1e6) if p else 0 for p in g]
        lon = [round(p["lon"] * 1e6) if p else 0 for p in g]
        dn = [nodes[0]] + [nodes[i] - nodes[i - 1] for i in range(1, len(nodes))]
        dla = [lat[0]] + [lat[i] - lat[i - 1] for i in range(1, len(lat))]
        dlo = [lon[0]] + [lon[i] - lon[i - 1] for i in range(1, len(lon))]
        rec = [e["id"], tags(e), dn, dla, dlo]
        (front if apres else ways).append(rec)
    elif t == "relation":
        routes.append([e["id"], tags(e), [m["ref"] for m in e.get("members", []) if m["type"] == "way"]])
    elif t == "node" or (t == "way" and "center" in e):
        c = e.get("center", e)
        pois.append([t, e["id"], tags(e), round(c["lat"] * 1e6), round(c["lon"] * 1e6)])
wid = {w[0] for w in ways}
for r in routes:
    r[2] = [m for m in r[2] if m in wid]
out = {"osm3s": d.get("osm3s", {}), "ways": ways, "routes": routes, "pois": pois, "frontiere": front}
raw = json.dumps(out, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
xz = lzma.compress(raw, preset=9 | lzma.PRESET_EXTREME)
print(f"  chemins {len(ways)}, routes {len(routes)}, points {len(pois)}, frontière {len(front)} ; json {len(raw)} o, xz {len(xz)} o, sha256 {hashlib.sha256(xz).hexdigest()}")
for f in front:
    print("  frontière", f[0], json.dumps(f[1], ensure_ascii=False)[:120], "noeuds", len(f[2]))
hw = collections.Counter(w[1].get("highway", "(sans highway)") for w in ways)
print("  types :", dict(hw))
for r in routes:
    print("  route", r[0], r[1].get("route"), "|", r[1].get("name", "")[:70], "|", r[1].get("ref", ""), "|", r[1].get("network", ""), "| membres gardés", len(r[2]))
n = 0
for p in pois:
    tg = p[2]
    if tg.get("tourism") in ("alpine_hut", "wilderness_hut") or tg.get("natural") == "saddle" or tg.get("mountain_pass") or tg.get("place") in ("village", "hamlet"):
        n += 1
        if n <= 90:
            print("  poi", p[0][0], p[1], f"{p[3]/1e6:.6f},{p[4]/1e6:.6f}", "|", tg.get("name", "")[:50], "|", tg.get("tourism", tg.get("natural", tg.get("place", ""))), "|", tg.get("ele", ""))
b = base64.b64encode(xz).decode()
print("=== DEBUT osm.json.xz ===")
for i in range(0, len(b), 1000): print(b[i:i + 1000])
print("=== FIN osm.json.xz ===")
PY
echo "### fin"
