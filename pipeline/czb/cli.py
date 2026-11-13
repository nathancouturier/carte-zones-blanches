"""Ligne de commande du pipeline.

  python -m czb.cli state                      état des sources en ligne (détection des nouvelles versions)
  python -m czb.cli changed --repo o/r          compare cet état à celui de la dernière release de données
  python -m czb.cli build --scope hautes-alpes construit les archives PMTiles et le manifest
  python -m czb.cli verify --out out           test de cohérence source contre pixels
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import shutil
import sys
import time
from pathlib import Path
from typing import Any

from . import __version__
from .context import BuildContext, Timer, grid_from_config, load_config
from .sources import create_source


def remote_state(cfg: dict[str, Any], scope_name: str, services: list[str]) -> dict[str, Any]:
    scope = cfg["scopes"][scope_name]
    state: dict[str, Any] = {}
    for iso in cfg["countries"]:
        if iso not in scope["countries"]:
            continue
        for source_id in cfg["countries"][iso]["sources"]:
            source = create_source(source_id, cfg)
            wanted = [s for s in services if s in cfg["sources"][source_id]["services"]]
            state[source_id] = source.remote_state(wanted) if wanted else {}
    return {"pipeline": __version__, "scope": scope_name, "services": services, "sources": state}


def cmd_state(args: argparse.Namespace) -> int:
    cfg = load_config(args.config)
    state = remote_state(cfg, args.scope, args.services.split(","))
    text = json.dumps(state, ensure_ascii=False, indent=1, sort_keys=True)
    if args.out:
        Path(args.out).write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


def cmd_changed(args: argparse.Namespace) -> int:
    """Compare l'état des sources en ligne à celui de la dernière release de données."""
    from .release_state import latest_release_state, write_github_output

    cfg = load_config(args.config)
    current = remote_state(cfg, args.scope, args.services.split(","))
    tag, previous = latest_release_state(args.repo)
    if args.force:
        changed, reason = True, "reconstruction forcée"
    elif previous is None:
        changed, reason = True, "aucune release de données" if tag is None else f"la release {tag} n'a pas d'état des sources"
    elif previous != current:
        keys = sorted(k for k in set(previous) | set(current) if previous.get(k) != current.get(k))
        changed, reason = True, f"changement depuis {tag} : {', '.join(keys)}"
    else:
        changed, reason = False, f"sources inchangées depuis {tag}"
    print(f"changed={str(changed).lower()} ({reason})")
    write_github_output({"changed": str(changed).lower(), "reason": reason})
    return 0


def cmd_build(args: argparse.Namespace) -> int:
    # Imports tardifs : GDAL n'est nécessaire que pour construire.
    from .archives import write_archives
    from .layers import Layers
    from .manifest import build_manifest
    from .masks import canvas_for_geometries, load_mask_geometries, rasterize_masks
    from .tiles import TileStore, build_tiles

    cfg = load_config(args.config)
    services = args.services.split(",")
    workdir, outdir = Path(args.work), Path(args.out)
    workdir.mkdir(parents=True, exist_ok=True)
    if outdir.exists():
        shutil.rmtree(outdir)
    outdir.mkdir(parents=True)
    ctx = BuildContext(cfg=cfg, scope_name=args.scope, services=services, workdir=workdir, outdir=outdir, grid=grid_from_config(cfg))
    t_start = time.time()
    generated = args.date or dt.date.today().isoformat()

    with Timer(ctx, "état des sources"):
        state = remote_state(cfg, args.scope, services)
        (outdir / "etat-sources.json").write_text(json.dumps(state, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")

    with Timer(ctx, "masques des pays"):
        geoms = load_mask_geometries(ctx)
        ctx.canvas = canvas_for_geometries(ctx, geoms)
        c = ctx.canvas
        print(f"   grille : tuiles z{c.grid.zoom} x {c.tx0} à {c.tx1}, y {c.ty0} à {c.ty1}, soit {c.width} x {c.height} px ({c.grid.resolution:.3f} m Mercator par pixel)", flush=True)
        ctx.layers = Layers(ctx.canvas, workdir)
        rasterize_masks(ctx, geoms)
        del geoms

    for iso in ctx.countries:
        for source_id in cfg["countries"][iso]["sources"]:
            with Timer(ctx, f"source {source_id}"):
                ctx.source_info[source_id] = create_source(source_id, cfg).process(ctx)
    ctx.layers.flush()

    store = TileStore(workdir / "tuiles.sqlite", min(int(cfg["grid"]["block_zoom"]), int(cfg["grid"]["max_zoom"])))
    with Timer(ctx, "tuiles"):
        build_tiles(ctx, store)
        by_zoom = store.stats_by_zoom()
        for z, s in by_zoom.items():
            print(f"   z{z} : {s['tiles']} tuiles, {s['bytes'] / 1e6:.2f} Mo", flush=True)

    with Timer(ctx, "archives PMTiles"):
        archives = write_archives(ctx, store, generated.replace("-", ""))
    store.close()

    manifest = build_manifest(ctx, archives, generated)
    (outdir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    (outdir / "temoins.json").write_text(json.dumps(ctx.witnesses, ensure_ascii=False) + "\n", encoding="utf-8")
    ctx.layers.cleanup()

    total = sum(a["bytes"] for a in archives)
    report = {
        "scope": args.scope,
        "services": services,
        "generated": generated,
        "grid": {"tx0": ctx.canvas.tx0, "ty0": ctx.canvas.ty0, "tx1": ctx.canvas.tx1, "ty1": ctx.canvas.ty1, "width": ctx.canvas.width, "height": ctx.canvas.height},
        "tiles_by_zoom": {str(z): s for z, s in by_zoom.items()},
        "archives": [{"file": a["file"], "mb": round(a["bytes"] / 1e6, 2)} for a in archives],
        "total_mb": round(total / 1e6, 2),
        "witnesses": len(ctx.witnesses),
        "timings_s": ctx.timings,
        "total_s": round(time.time() - t_start, 1),
        "stats": ctx.stats,
    }
    (outdir / "rapport-construction.json").write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("== bilan")
    print(json.dumps(report, ensure_ascii=False, indent=1))
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    from .verify import verify

    return verify(Path(args.out))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="czb", description="Pipeline de la carte des zones blanches")
    parser.add_argument("--config", type=Path, default=None, help="chemin de config.yaml")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("state", help="affiche l'état des sources en ligne")
    p.add_argument("--scope", default="complet")
    p.add_argument("--services", default="data")
    p.add_argument("--out", default=None)
    p.set_defaults(func=cmd_state)

    p = sub.add_parser("changed", help="dit si une source a changé depuis la dernière release de données")
    p.add_argument("--scope", default="complet")
    p.add_argument("--services", default="data")
    p.add_argument("--repo", required=True, help="dépôt GitHub, sous la forme propriétaire/nom")
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_changed)

    p = sub.add_parser("build", help="construit les archives PMTiles et le manifest")
    p.add_argument("--scope", default="complet")
    p.add_argument("--services", default="data", help="services séparés par des virgules : data, voice")
    p.add_argument("--work", default="work")
    p.add_argument("--out", default="out")
    p.add_argument("--date", default=None, help="date de la release (AAAA-MM-JJ), aujourd'hui par défaut")
    p.set_defaults(func=cmd_build)

    p = sub.add_parser("verify", help="test de cohérence source contre pixels")
    p.add_argument("--out", default="out")
    p.set_defaults(func=cmd_verify)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
