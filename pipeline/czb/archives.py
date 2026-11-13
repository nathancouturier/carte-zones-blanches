"""Écriture des archives PMTiles, découpées pour rester sous la limite de taille."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from pmtiles.tile import Compression, TileType, zxy_to_tileid
from pmtiles.writer import write as pmtiles_write

from .context import BuildContext
from .tiles import TileStore


def _write_archive(ctx: BuildContext, path: Path, tiles: Any, min_zoom: int, max_zoom: int) -> int:
    assert ctx.canvas is not None
    west, south, east, north = ctx.canvas.lonlat_bounds
    count = 0
    with pmtiles_write(str(path)) as writer:
        for tileid, data in tiles:
            writer.write_tile(tileid, bytes(data))
            count += 1
        if count == 0:
            raise RuntimeError(f"archive vide : {path.name}")
        header = {
            "tile_type": TileType.PNG,
            "tile_compression": Compression.NONE,
            "min_lon_e7": int(west * 1e7),
            "min_lat_e7": int(south * 1e7),
            "max_lon_e7": int(east * 1e7),
            "max_lat_e7": int(north * 1e7),
            "center_zoom": min(max_zoom, max(min_zoom, 8)),
            "center_lon_e7": int((west + east) / 2 * 1e7),
            "center_lat_e7": int((south + north) / 2 * 1e7),
        }
        metadata = {
            "name": "Carte des zones blanches : couverture mobile",
            "format": "png",
            "description": "Tuiles de données (pas de couleurs) : voir manifest.json pour l'encodage.",
            "minzoom": min_zoom,
            "maxzoom": max_zoom,
        }
        writer.finalize(header, metadata)
    return count


def write_archives(ctx: BuildContext, store: TileStore, date_tag: str) -> list[dict[str, Any]]:
    """Écrit une archive unique si elle tient sous la limite, sinon un aperçu et des archives par blocs."""
    limits = ctx.cfg["limits"]
    max_bytes = int(limits["archive_max_mb"]) * 1_000_000
    target_bytes = int(limits["target_archive_mb"]) * 1_000_000
    grid_cfg = ctx.cfg["grid"]
    min_zoom, max_zoom = int(grid_cfg["min_zoom"]), int(grid_cfg["max_zoom"])
    block_zoom = min(int(grid_cfg["block_zoom"]), max_zoom)
    ctx.outdir.mkdir(parents=True, exist_ok=True)
    archives: list[dict[str, Any]] = []
    total = store.total_bytes()

    if total <= target_bytes:
        name = f"couverture-{date_tag}-00.pmtiles"
        _write_archive(ctx, ctx.outdir / name, store.iter_tiles("1=1"), min_zoom, max_zoom)
        archives.append({"file": name, "minzoom": min_zoom, "maxzoom": max_zoom})
    else:
        # Aperçu : tous les zooms inférieurs au zoom des blocs.
        if block_zoom > min_zoom:
            name = f"couverture-{date_tag}-00.pmtiles"
            _write_archive(ctx, ctx.outdir / name, store.iter_tiles("z < ?", (block_zoom,)), min_zoom, block_zoom - 1)
            archives.append({"file": name, "minzoom": min_zoom, "maxzoom": block_zoom - 1})
        # Blocs regroupés dans l'ordre de la courbe de Hilbert : chaque archive reste compacte sur la carte.
        sizes = store.block_sizes()
        ordered = sorted(sizes, key=lambda b: zxy_to_tileid(block_zoom, b[0], b[1]))
        groups: list[list[tuple[int, int]]] = []
        current: list[tuple[int, int]] = []
        current_size = 0
        for block in ordered:
            if sizes[block] > max_bytes:
                raise RuntimeError(
                    f"le bloc {block} pèse {sizes[block] / 1e6:.0f} Mo à lui seul : augmenter grid.block_zoom dans config.yaml"
                )
            if current and current_size + sizes[block] > target_bytes:
                groups.append(current)
                current, current_size = [], 0
            current.append(block)
            current_size += sizes[block]
        if current:
            groups.append(current)
        for index, group in enumerate(groups, start=1):
            name = f"couverture-{date_tag}-{index:02d}.pmtiles"
            placeholders = ",".join("(?,?)" for _ in group)
            params = tuple(v for block in group for v in block)
            _write_archive(
                ctx,
                ctx.outdir / name,
                store.iter_tiles(f"bx >= 0 AND (bx, by) IN (VALUES {placeholders})", params),
                block_zoom,
                max_zoom,
            )
            archives.append(
                {
                    "file": name,
                    "minzoom": block_zoom,
                    "maxzoom": max_zoom,
                    "blocks": [f"{bx}/{by}" for bx, by in group],
                }
            )

    for archive in archives:
        size = (ctx.outdir / archive["file"]).stat().st_size
        archive["bytes"] = size
        print(f"   {archive['file']} : {size / 1e6:.2f} Mo", flush=True)
        if size > max_bytes:
            raise RuntimeError(f"{archive['file']} dépasse la limite de {limits['archive_max_mb']} Mo")
    site_total = sum(a["bytes"] for a in archives)
    if site_total > int(limits["site_max_mb"]) * 1_000_000:
        raise RuntimeError(f"les données pèsent {site_total / 1e6:.0f} Mo, plus que la limite du site ({limits['site_max_mb']} Mo)")
    return archives
