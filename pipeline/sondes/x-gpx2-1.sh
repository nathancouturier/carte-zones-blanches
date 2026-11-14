#!/usr/bin/env bash
# Sonde gpx2-1 : UNE requête Overpass, sur une emprise serrée au sud des Chapieux (Savoie), pour prolonger le
# tracé de test des Alpes vers le sud : tous les chemins et routes (highway), les itinéraires de randonnée qui les
# empruntent, et quelques lieux nommés (hameaux, parkings, refuges). Pas d'autre requête.
# Le résultat est compacté (deltas entiers, xz) et affiché en base64 entre deux lignes repères.
set -u
. "$(dirname "$0")/_lib.sh"
cd "$T"

B="45.655,6.728,45.6985,6.792"   # sud, ouest, nord, est : des Chapieux jusqu'au-dessus de Bonneval-les-Bains
cat > requete.overpassql <<EOF
[out:json][timeout:120];
way["highway"]($B)->.w;
.w out geom;
rel(bw.w)["route"~"^(hiking|foot)$"]->.routes;
.routes out body;
( node["place"~"^(village|hamlet|locality|isolated_dwelling|farm)$"]($B);
  node["tourism"~"^(alpine_hut|wilderness_hut|camp_site|chalet|guest_house|hotel)$"]($B);
  nwr["amenity"="parking"]($B);
  node["natural"="saddle"]($B);
  node["mountain_pass"="yes"]($B); )->.poi;
.poi out center;
EOF
echo "### Requête Overpass (une seule), emprise $B"
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
print("  éléments :", dict(collections.Counter(e["type"] for e in els)))
GARDER = ("highway", "name", "ref", "sac_scale", "trail_visibility", "foot", "access", "bridge", "tunnel",
          "informal", "via_ferrata_scale", "hazard", "seasonal", "surface", "tracktype", "mountain_pass", "natural",
          "tourism", "place", "ele", "network", "route", "osmc:symbol", "operator", "name:fr", "name:it", "wikidata",
          "amenity", "motor_vehicle", "motorcar", "oneway", "smoothness", "layer")
def tags(e): return {k: v for k, v in e.get("tags", {}).items() if k in GARDER}
ways, routes, pois = [], [], []
for e in els:
    t = e["type"]
    if t == "way" and "geometry" in e:
        g = e["geometry"]
        nodes = e["nodes"]
        lat = [round(p["lat"] * 1e6) if p else 0 for p in g]
        lon = [round(p["lon"] * 1e6) if p else 0 for p in g]
        dn = [nodes[0]] + [nodes[i] - nodes[i - 1] for i in range(1, len(nodes))]
        dla = [lat[0]] + [lat[i] - lat[i - 1] for i in range(1, len(lat))]
        dlo = [lon[0]] + [lon[i] - lon[i - 1] for i in range(1, len(lon))]
        ways.append([e["id"], tags(e), dn, dla, dlo])
    elif t == "relation" and e.get("tags", {}).get("route") in ("hiking", "foot"):
        routes.append([e["id"], tags(e), [m["ref"] for m in e.get("members", []) if m["type"] == "way"]])
    elif t == "node" or "center" in e:
        c = e.get("center", e)
        pois.append([t, e["id"], tags(e), round(c["lat"] * 1e6), round(c["lon"] * 1e6)])
wid = {w[0] for w in ways}
for r in routes:
    r[2] = [m for m in r[2] if m in wid]
out = {"osm3s": d.get("osm3s", {}), "ways": ways, "routes": routes, "pois": pois, "frontiere": []}
raw = json.dumps(out, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
xz = lzma.compress(raw, preset=9 | lzma.PRESET_EXTREME)
print(f"  chemins {len(ways)}, routes {len(routes)}, points {len(pois)} ; json {len(raw)} o, xz {len(xz)} o, sha256 {hashlib.sha256(xz).hexdigest()}")
print("  types :", dict(collections.Counter(w[1].get("highway", "?") for w in ways)))
for r in routes:
    print("  route", r[0], "|", r[1].get("name", "")[:70], "|", r[1].get("ref", ""), "|", r[1].get("network", ""), "| chemins dans l'emprise", len(r[2]))
n = 0
for w in ways:
    tg = w[1]
    if tg.get("highway") not in ("path", "footway", "track", "steps", "service") or tg.get("name") or tg.get("ref"):
        n += 1
        if n <= 80:
            print("  way", w[0], json.dumps(tg, ensure_ascii=False)[:150])
for p in pois[:60]:
    tg = p[2]
    print("  poi", p[0][0], p[1], f"{p[3]/1e6:.6f},{p[4]/1e6:.6f}", "|", tg.get("name", "")[:50], "|", tg.get("place", tg.get("tourism", tg.get("amenity", tg.get("natural", "")))), "|", tg.get("ele", ""))
b = base64.b64encode(xz).decode()
print("=== DEBUT osm.json.xz ===")
for i in range(0, len(b), 1000): print(b[i:i + 1000])
print("=== FIN osm.json.xz ===")
PY
echo "### fin"
