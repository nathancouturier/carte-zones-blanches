#!/usr/bin/env bash
# Sonde ap-zone03-es-1 (audit de conformité, partie pipeline) :
# 1. zone-03 : sur les contours réels (chargeurs du pipeline, config.yaml du dépôt), trous fermés de moins de
#    100 ha comblés par la règle actuelle de fill_gaps, et ceux que la règle « bordé par au moins deux entités
#    de masque » ne comblerait plus (pays, surface, centre, entités qui le bordent, pixels z12).
# 2. archi-27 (b) : la page du ministère espagnol (clé « url » de es_mtd), lue sans JavaScript comme le ferait
#    le pipeline (czb.net), cite-t-elle l'identifiant d'élément ArcGIS de item_url ? Contexte de chaque identifiant.
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$(dirname "$0")/_lib.sh"
cd "$T"
mkdir -p py work
export DEBIAN_FRONTEND=noninteractive
echo "##### 0. Environnement du pipeline (comme build-data.yml)"
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends python3-pip >/dev/null 2>&1
python3 -m pip install --break-system-packages -q -r "$REPO/pipeline/requirements.txt" 2>&1 | tail -2
echo "   depot : $(cd "$REPO" && git log --oneline -1 2>/dev/null | cut -c1-70)"
cat > py/sonde.py <<'PY_FIN_SONDE'
import math
import re
import subprocess
import sys
import time
import traceback
import urllib.request
from pathlib import Path

from osgeo import ogr

from czb import masks
from czb.context import BuildContext, apply_scope, grid_from_config, load_config
from czb.grid import mercator_to_lonlat
from czb.raster import geometry_windows, make_valid

WORK = Path(sys.argv[1])
UA_SONDE = sys.argv[2]


def ground_ha(g):
    x0, x1, y0, y1 = g.GetEnvelope()
    lat = 2 * math.atan(math.exp((y0 + y1) / 2 / 6378137.0)) - math.pi / 2
    return g.GetArea() * math.cos(lat) ** 2 / 1e4


def zone03():
    cfg = apply_scope(load_config(), "complet")
    ctx = BuildContext(cfg=cfg, scope_name="complet", services=["data"], workdir=WORK, outdir=WORK / "out", grid=grid_from_config(cfg))
    geoms = {}
    for iso in ctx.countries:
        mask_cfg = cfg["countries"][iso]["mask"]
        t0 = time.time()
        try:
            geoms[iso] = masks.LOADERS[mask_cfg["type"]](mask_cfg, ctx.scope, WORK)
        except Exception as exc:  # noqa: BLE001
            print("   !!! %s : contour illisible : %s" % (iso, str(exc)[:300]))
            continue
        print("   %s : %d entite(s), %.1f km2, %.0f s" % (iso, len(geoms[iso]), masks.ground_area_km2(geoms[iso]), time.time() - t0))
    order = [iso for iso in ctx.countries if iso in geoms]
    canvas = masks.canvas_for_geometries(ctx, geoms)
    t0 = time.time()
    unions = masks.country_unions(geoms, order)
    prepared = {iso: (g.GetEnvelope(), g.CreatePreparedGeometry()) for iso, g in unions.items()}
    everything = masks._union(list(unions.values()))
    print("   unions des pays et de l'ensemble : %.0f s" % (time.time() - t0))
    tol = masks.GAP_TOUCH_M
    entities = {}

    def touching_entities(iso, probe, env):
        if iso not in entities:
            entities[iso] = [(g.GetEnvelope(), (g if g.IsValid() else make_valid(g)).CreatePreparedGeometry()) for g in geoms[iso]]
        x0, x1, y0, y1 = env
        out = []
        for index, ((m0, m1, n0, n1), prep) in enumerate(entities[iso]):
            if x1 + tol < m0 or x0 - tol > m1 or y1 + tol < n0 or y0 - tol > n1:
                continue
            if prep.Intersects(probe):
                out.append(index)
        return out

    old, new, single, dropped = {}, {}, {}, []
    candidates = orphans = 0
    t0 = time.time()
    for poly in masks._polygons(everything):
        for i in range(1, poly.GetGeometryCount()):
            hole = ogr.Geometry(ogr.wkbPolygon)
            hole.AddGeometry(poly.GetGeometryRef(i).Clone())
            ha = ground_ha(hole)
            if ha >= masks.GAP_MAX_HA:
                continue
            candidates += 1
            env = hole.GetEnvelope()
            x0, x1, y0, y1 = env
            probe = hole.Buffer(tol)
            touching = []
            for iso in reversed(order):
                (m0, m1, n0, n1), prep = prepared[iso]
                if x1 + tol < m0 or x0 - tol > m1 or y1 + tol < n0 or y0 - tol > n1:
                    continue
                if prep.Intersects(probe):
                    touching.append(iso)
            if not touching:
                orphans += 1
                continue
            winner = touching[0]
            o = old.setdefault(winner, [0, 0.0])
            o[0] += 1
            o[1] += ha
            ents = touching_entities(winner, probe, env) if len(touching) == 1 else None
            keep = len(touching) >= 2 or len(ents) >= 2
            if len(touching) == 1:
                single.setdefault(winner, [0, 0])[0 if keep else 1] += 1
            if keep:
                n = new.setdefault(winner, [0, 0.0])
                n[0] += 1
                n[1] += ha
            else:
                dropped.append((winner, ha, hole, ents))
    print("   trous fermes de moins de %.0f ha : %d, dont %d sans pays au contact ; boucle : %.1f s" % (masks.GAP_MAX_HA, candidates, orphans, time.time() - t0))
    for iso in order:
        o, n = old.get(iso, [0, 0.0]), new.get(iso, [0, 0.0])
        s = single.get(iso, [0, 0])
        print("   %s : regle actuelle %d trous (%.2f ha) ; regle deux entites %d trous (%.2f ha) ; trous au contact de ce seul pays : %d bordes par 2 entites ou plus, %d par une seule" % (iso, o[0], o[1], n[0], n[1], s[0], s[1]))
    total = 0
    print("   trous que la nouvelle regle ne comble plus : %d" % len(dropped))
    for iso, ha, hole, ents in sorted(dropped, key=lambda d: -d[1])[:40]:
        px = sum(int(mask.sum()) for _, mask in geometry_windows(hole, canvas))
        total += px
        c = hole.Centroid()
        lon, lat = mercator_to_lonlat(c.GetX(), c.GetY())
        print("     %s : %.2f ha, centre (%.4f, %.4f), entite(s) au contact %s, %d pixel(s) z12" % (iso, ha, lon, lat, ents, px))
    print("   pixels z12 de ces trous (40 plus grands) : %d" % total)


def page():
    from czb.net import _request, fetch_text

    s = load_config()["sources"]["es_mtd"]
    url, item = s["url"], s["item_url"].rstrip("/").rsplit("/", 1)[-1]
    print("   page : %s" % url)
    print("   identifiant de item_url : %s" % item)
    pattern = re.compile(r"(?<![0-9A-Fa-f])[0-9A-Fa-f]{32}(?![0-9A-Fa-f])")
    read = 0
    for attempt in (1, 2):
        try:
            if attempt == 1:
                with urllib.request.urlopen(_request(url), timeout=60) as resp:
                    raw = resp.read()
                    print("   lecture 1 (urllib, en-tetes du pipeline) : HTTP %s, adresse finale %s, type %s, %d octets" % (resp.status, resp.geturl()[:160], resp.headers.get("Content-Type"), len(raw)))
                text = raw.decode("utf-8", errors="replace")
            else:
                time.sleep(5)
                text = fetch_text(url, tries=3, timeout=60)
                print("   lecture 2 (czb.net.fetch_text) : %d caracteres" % len(text))
        except Exception as exc:  # noqa: BLE001
            print("   lecture %d : ECHEC %s" % (attempt, str(exc)[:300]))
            continue
        read += 1
        ids = sorted({m.lower() for m in pattern.findall(text)})
        print("   identifiants de 32 caracteres hexadecimaux : %d : %s" % (len(ids), ids[:25]))
        print("   l'identifiant de item_url est cite : %s" % (item in ids))
        if attempt == 1:
            title = re.search(r"<title[^>]*>(.*?)</title>", text, flags=re.S | re.I)
            print("   titre : %s" % (re.sub(r"\s+", " ", title.group(1)).strip()[:160] if title else None))
            for ident in ids[:25]:
                for m in list(re.finditer(ident, text, flags=re.I))[:2]:
                    around = re.sub(r"\s+", " ", text[max(0, m.start() - 110) : m.end() + 30])
                    print("     %s : ...%s..." % (ident[:8], around[:230]))
            links = sorted(set(re.findall(r"https?://[^\s\"'<>]*arcgis\.com[^\s\"'<>]*", text, flags=re.I)))
            print("   liens vers arcgis.com : %d" % len(links))
            for link in links[:15]:
                print("     " + link[:200])
    if read == 0:
        # Diagnostic seulement : la même page avec curl et l'agent des sondes.
        out = subprocess.run(["curl", "-sS", "-L", "-m", "60", "-A", UA_SONDE, "-o", str(WORK / "page.html"), "-w", "%{http_code} %{size_download}o %{content_type}", url], capture_output=True, text=True)
        print("   lecture curl (agent des sondes) : %s %s" % (out.stdout[:120], out.stderr[:200]))


for title, fn in (("1. ZONE-03 : trous fermes des contours reels", zone03), ("2. ARCHI-27 : page du ministere espagnol", page)):
    print()
    print("##### " + title)
    try:
        fn()
    except Exception:  # noqa: BLE001
        print("   !!! EXCEPTION : " + traceback.format_exc()[-1500:])
PY_FIN_SONDE
PYTHONPATH="$REPO/pipeline" python3 py/sonde.py "$T/work" "$UA" 2>&1 | grep -v "memory leak" | cut -c1-420 | head -300
echo "FIN (code python : ${PIPESTATUS[0]})"
