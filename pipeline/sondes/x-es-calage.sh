#!/usr/bin/env bash
# Mesure le calage de la grille des polygones 4G du ministère espagnol : restes des coordonnées des sommets modulo le pas.
. "$(dirname "$0")/_lib.sh"
L='https://services-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/InfoCob4G_2024/FeatureServer/0/query'
for ccom in 02 09 15 16; do
  curl -sS -m 120 -A "$UA" --compressed -G "$L" --data-urlencode "where=CCOM='$ccom' AND COBERTURA<>''" --data-urlencode "outFields=OBJECTID" --data-urlencode "orderByFields=OBJECTID" --data-urlencode "resultRecordCount=2000" --data-urlencode "f=json" -o "$T/p$ccom.json" -w "région $ccom : code=%{http_code} octets=%{size_download}\n"
done
python3 - "$T" <<'PY'
import json, sys, math, collections
from decimal import Decimal as D
T = sys.argv[1]
STEP = 0.000346111018645788
X0, Y0 = -18.356176100718844, 43.95448719807852
for ccom in ('02', '09', '15', '16'):
    d = json.load(open(f'{T}/p{ccom}.json'))
    feats = d.get('features', [])
    print('== région', ccom, len(feats), 'entités, SR', d.get('spatialReference'))
    fx = collections.Counter(); fy = collections.Counter(); dxs = collections.Counter(); n = 0
    small = 0
    for f in feats:
        rings = f['geometry']['rings']
        ring = rings[0]
        if len(ring) == 5 and len(rings) == 1:
            small += 1
        for (x, y) in ring[:8]:
            qx = (x - X0) / STEP; qy = (Y0 - y) / STEP
            fx[round(qx - math.floor(qx), 2)] += 1; fy[round(qy - math.floor(qy), 2)] += 1; n += 1
        for (a, b) in zip(ring, ring[1:]):
            dx = abs(b[0] - a[0]) / STEP; dy = abs(b[1] - a[1]) / STEP
            for v in (dx, dy):
                if v > 1e-6:
                    dxs[round(v, 3)] += 1
    print('  carrés simples (5 sommets) :', small)
    print('  restes en x les plus fréquents :', fx.most_common(4), 'sur', n)
    print('  restes en y les plus fréquents :', fy.most_common(4))
    print('  longueurs de côté (en pas) les plus fréquentes :', dxs.most_common(6))
    if feats:
        r = feats[0]['geometry']['rings'][0]
        print('  premier anneau :', [[repr(c) for c in p] for p in r[:5]])
PY
# Emprise et origine annoncées par les deux images tuilées.
for u in 'https://tiledimageservices-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/Cob4G_2024/ImageServer' 'https://tiledimageservices9.arcgis.com/b5sc9d51LIwFoyfR/arcgis/rest/services/Cob4G_2024/ImageServer'; do
  curl -sS -m 60 -A "$UA" "$u?f=json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('image', d.get('name'), 'pixel', d.get('pixelSizeX'), d.get('pixelSizeY'), 'emprise', {k: d.get('extent', {}).get(k) for k in ('xmin','ymin','xmax','ymax')}, 'SR', d.get('extent', {}).get('spatialReference'), 'origine', (d.get('tileInfo') or {}).get('origin'))
"
done
