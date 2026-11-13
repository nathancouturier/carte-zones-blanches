"""Génération des tuiles : zoom maximal, puis zooms inférieurs en plus proche voisin.

On ne fait jamais de moyenne entre pixels : les canaux portent des données
codées, une moyenne les rendrait fausses.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Iterator

import numpy as np
from pmtiles.tile import zxy_to_tileid

from .context import BuildContext
from .encoding import compose_rgba, encode_png


class TileStore:
    """Tuiles encodées, rangées dans une base SQLite temporaire."""

    def __init__(self, path: Path, block_zoom: int):
        self.path = Path(path)
        self.path.unlink(missing_ok=True)
        self.block_zoom = block_zoom
        self.db = sqlite3.connect(self.path)
        self.db.execute("PRAGMA journal_mode=OFF")
        self.db.execute("PRAGMA synchronous=OFF")
        self.db.execute(
            "CREATE TABLE tiles (tileid INTEGER PRIMARY KEY, z INTEGER, x INTEGER, y INTEGER, bx INTEGER, by INTEGER, size INTEGER, data BLOB)"
        )
        self._pending: list[tuple] = []

    def put(self, z: int, x: int, y: int, data: bytes) -> None:
        if z >= self.block_zoom:
            shift = z - self.block_zoom
            bx, by = x >> shift, y >> shift
        else:
            bx = by = -1  # tuiles d'aperçu, hors blocs
        self._pending.append((zxy_to_tileid(z, x, y), z, x, y, bx, by, len(data), data))
        if len(self._pending) >= 500:
            self.commit()

    def commit(self) -> None:
        if self._pending:
            self.db.executemany("INSERT INTO tiles VALUES (?,?,?,?,?,?,?,?)", self._pending)
            self.db.commit()
            self._pending.clear()

    def stats_by_zoom(self) -> dict[int, dict[str, int]]:
        self.commit()
        rows = self.db.execute("SELECT z, COUNT(*), SUM(size) FROM tiles GROUP BY z ORDER BY z").fetchall()
        return {z: {"tiles": n, "bytes": size} for z, n, size in rows}

    def total_bytes(self) -> int:
        self.commit()
        return int(self.db.execute("SELECT COALESCE(SUM(size), 0) FROM tiles").fetchone()[0])

    def block_sizes(self) -> dict[tuple[int, int], int]:
        self.commit()
        rows = self.db.execute("SELECT bx, by, SUM(size) FROM tiles WHERE bx >= 0 GROUP BY bx, by").fetchall()
        return {(bx, by): int(size) for bx, by, size in rows}

    def iter_tiles(self, where: str, params: tuple = ()) -> Iterator[tuple[int, bytes]]:
        """Tuiles (identifiant PMTiles, données) dans l'ordre des identifiants."""
        self.commit()
        cur = self.db.execute(f"SELECT tileid, data FROM tiles WHERE {where} ORDER BY tileid", params)
        yield from cur

    def close(self) -> None:
        self.commit()
        self.db.close()
        self.path.unlink(missing_ok=True)


def _downsample(level: np.ndarray, factor: int) -> np.ndarray:
    """Plus proche voisin : on garde le pixel central de chaque carré factor x factor."""
    if factor == 1:
        return level
    return level[factor // 2 :: factor, factor // 2 :: factor]


def build_tiles(ctx: BuildContext, store: TileStore) -> None:
    canvas, layers = ctx.canvas, ctx.layers
    assert canvas is not None and layers is not None
    grid = canvas.grid
    ts = grid.tile_size
    max_zoom = grid.zoom
    min_zoom = int(ctx.cfg["grid"]["min_zoom"])
    block_zoom = min(int(ctx.cfg["grid"]["block_zoom"]), max_zoom)
    per_block = 1 << (max_zoom - block_zoom)  # tuiles du zoom maximal par côté de bloc
    block_px = per_block * ts

    bx0, bx1 = canvas.tx0 // per_block, canvas.tx1 // per_block
    by0, by1 = canvas.ty0 // per_block, canvas.ty1 // per_block
    overview: dict[tuple[int, int], np.ndarray] = {}  # tuiles du zoom des blocs, pour bâtir les zooms inférieurs
    total_blocks = (bx1 - bx0 + 1) * (by1 - by0 + 1)
    done = 0
    for by in range(by0, by1 + 1):
        for bx in range(bx0, bx1 + 1):
            done += 1
            # Partie du bloc présente dans la grille.
            c0 = max(0, (bx * per_block - canvas.tx0) * ts)
            c1 = min(canvas.width, ((bx + 1) * per_block - canvas.tx0) * ts)
            r0 = max(0, (by * per_block - canvas.ty0) * ts)
            r1 = min(canvas.height, ((by + 1) * per_block - canvas.ty0) * ts)
            if c1 <= c0 or r1 <= r0:
                continue
            b = np.asarray(layers.B[r0:r1, c0:c1])
            if not (b & 0x0F).any():
                continue
            part = compose_rgba(np.asarray(layers.R[r0:r1, c0:c1]), np.asarray(layers.G[r0:r1, c0:c1]), b)
            block = np.zeros((block_px, block_px, 4), dtype=np.uint8)
            off_c = c0 - (bx * per_block - canvas.tx0) * ts
            off_r = r0 - (by * per_block - canvas.ty0) * ts
            block[off_r : off_r + part.shape[0], off_c : off_c + part.shape[1]] = part
            del part
            for z in range(max_zoom, block_zoom - 1, -1):
                level = _downsample(block, 1 << (max_zoom - z))
                n = 1 << (z - block_zoom)
                for j in range(n):
                    for i in range(n):
                        tile = level[j * ts : (j + 1) * ts, i * ts : (i + 1) * ts]
                        if not tile[..., 3].any():
                            continue
                        if z >= min_zoom:
                            store.put(z, (bx << (z - block_zoom)) + i, (by << (z - block_zoom)) + j, encode_png(tile))
                        if z == block_zoom:
                            overview[(bx, by)] = np.ascontiguousarray(tile)
            if done % 10 == 0 or done == total_blocks:
                print(f"   blocs traités : {done}/{total_blocks}", flush=True)

    # Zooms inférieurs au zoom des blocs : chaque tuile est bâtie à partir de ses 4 filles.
    current = overview
    for z in range(block_zoom - 1, -1, -1):
        parents: dict[tuple[int, int], np.ndarray] = {}
        for px, py in sorted({(x >> 1, y >> 1) for x, y in current}):
            mosaic = np.zeros((2 * ts, 2 * ts, 4), dtype=np.uint8)
            for dy in (0, 1):
                for dx in (0, 1):
                    child = current.get((2 * px + dx, 2 * py + dy))
                    if child is not None:
                        mosaic[dy * ts : (dy + 1) * ts, dx * ts : (dx + 1) * ts] = child
            tile = np.ascontiguousarray(_downsample(mosaic, 2))
            if tile[..., 3].any():
                parents[(px, py)] = tile
                if z >= min_zoom:
                    store.put(z, px, py, encode_png(tile))
        current = parents
    store.commit()
