"""Points témoins du test de cohérence, pour les sources vectorielles.

Avant de traiter une source, on tire des pixels au hasard dans le pays. Pendant
le traitement, la valeur attendue de chaque point est établie par un test
géométrique exact (GEOS) sur les polygones de la source, indépendamment de la
rastérisation. À la fin de la construction, ces points sont relus dans les
archives PMTiles : le moindre écart fait échouer le job.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, Callable

from .context import BuildContext
from .grid import mercator_to_lonlat

if TYPE_CHECKING:
    import numpy as np
    from osgeo import ogr

#: Un point à moins de cette distance (dans l'unité du SCR de la source) d'un bord de polygone est écarté :
#: le résultat dépendrait d'un arrondi.
DEFAULT_MARGIN = 0.5


def country_window(ctx: BuildContext, country_code: int) -> tuple[int, int, int, int] | None:
    """Fenêtre de la grille qui englobe le pays (col0, row0, largeur, hauteur)."""
    if country_code not in ctx.country_windows:
        canvas, layers = ctx.canvas, ctx.layers
        assert canvas is not None and layers is not None
        extent = layers.country_extent(country_code)
        ctx.country_windows[country_code] = None if extent is None else canvas.window_for_envelope(extent[0], extent[2], extent[1], extent[3])
    return ctx.country_windows[country_code]


def draw_country_pixels(ctx: BuildContext, country_code: int, rng: "np.random.Generator", batch: int) -> tuple[list[int], list[int]]:
    """Un lot de pixels (colonnes, lignes) du pays, décrits par ses sources, tirés au hasard.

    Le tirage se fait dans la fenêtre qui englobe le pays, pas sur toute la grille : sinon un
    petit pays (Monaco, 2 700 pixels sur 2 milliards) ne recevrait aucun point témoin.
    """
    layers = ctx.layers
    assert layers is not None
    win = country_window(ctx, country_code)
    if win is None:
        return [], []
    cols = rng.integers(win[0], win[0] + win[2], size=batch)
    rows = rng.integers(win[1], win[1] + win[3], size=batch)
    inside = layers.described(rows, cols, country_code)
    return cols[inside].tolist(), rows[inside].tolist()


class VectorWitnesses:
    def __init__(self, ctx: BuildContext, country_code: int, from_merc: Any, rng: "np.random.Generator", margin: float = DEFAULT_MARGIN, initial: int = 0):
        """Tire des pixels du pays et calcule la position de leur centre dans le SCR de la source.

        from_merc : transformation de l'EPSG:3857 vers le SCR de la source, ou None si la source est déjà en EPSG:3857.
        """
        from osgeo import ogr

        canvas, layers = ctx.canvas, ctx.layers
        assert canvas is not None and layers is not None
        wanted = int(ctx.cfg["verification"]["candidates_per_file"])
        self.margin = margin
        self.candidates: list[dict[str, Any]] = []
        attempts = 0
        while len(self.candidates) < wanted and attempts < 400:
            attempts += 1
            for col, row in zip(*draw_country_pixels(ctx, country_code, rng, wanted * 4)):
                x, y = canvas.pixel_center(col, row)
                if from_merc is None:
                    sx, sy = x, y
                else:
                    sx, sy, _ = from_merc.TransformPoint(x, y)
                points = []
                for dx, dy in ((0, 0), (-1, -1), (1, -1), (1, 1), (-1, 1)):
                    pt = ogr.Geometry(ogr.wkbPoint)
                    pt.AddPoint_2D(sx + dx * margin, sy + dy * margin)
                    points.append(pt)
                self.candidates.append({"col": col, "row": row, "x": x, "y": y, "sx": sx, "sy": sy, "points": points, "value": initial, "ambiguous": False})
                if len(self.candidates) >= wanted:
                    break

    def update(self, geom: "ogr.Geometry", value: int, combine: Callable[[int, int], int] = max) -> None:
        """Enregistre que les points situés dans ce polygone valent « value » (combiné à leur valeur précédente)."""
        minx, maxx, miny, maxy = geom.GetEnvelope()
        m = self.margin
        near = [w for w in self.candidates if minx - m <= w["sx"] <= maxx + m and miny - m <= w["sy"] <= maxy + m]
        if not near:
            return
        from .raster import make_valid, quiet_gdal

        with quiet_gdal():
            if not geom.IsValid():
                geom = make_valid(geom)
        tester = geom.CreatePreparedGeometry() if hasattr(geom, "CreatePreparedGeometry") else geom
        for w in near:
            results = [bool(tester.Contains(pt)) for pt in w["points"]]
            if any(results) and not all(results):
                w["ambiguous"] = True  # trop près d'un bord : on ne s'en sert pas
            if results[0]:
                w["value"] = combine(w["value"], value)

    def select(self, ctx: BuildContext, source_id: str, country_iso: str, service: str, slot_index: int, slot_id: str, expected_of: Callable[[int], int] = lambda v: v) -> list[dict[str, Any]]:
        """Garde un échantillon équilibré entre les niveaux attendus et l'ajoute aux points témoins de la construction."""
        canvas = ctx.canvas
        assert canvas is not None
        keep_total = int(ctx.cfg["verification"]["points_per_file"])
        usable = [w for w in self.candidates if not w["ambiguous"]]
        by_level: dict[int, list[dict[str, Any]]] = {}
        for w in usable:
            by_level.setdefault(int(expected_of(w["value"])), []).append(w)
        kept: list[tuple[int, dict[str, Any]]] = []
        # Tour à tour un point de chaque niveau, jusqu'à atteindre le quota.
        while len(kept) < keep_total and any(by_level.values()):
            for level in sorted(by_level):
                if by_level[level] and len(kept) < keep_total:
                    kept.append((level, by_level[level].pop()))
        out = []
        for level, w in kept:
            tx, ty, px, py = canvas.tile_and_pixel(w["col"], w["row"])
            lon, lat = mercator_to_lonlat(w["x"], w["y"])
            out.append(
                {
                    "source": source_id,
                    "country": country_iso,
                    "service": service,
                    "slot": slot_index,
                    "operator": slot_id,
                    "z": canvas.grid.zoom,
                    "x": tx,
                    "y": ty,
                    "px": px,
                    "py": py,
                    "lon": round(lon, 6),
                    "lat": round(lat, 6),
                    "expected": level,
                }
            )
        counts = {level: sum(1 for w in out if w["expected"] == level) for level in sorted({w["expected"] for w in out})}
        print(f"    points témoins ({slot_id}) : {len(out)} retenus sur {len(usable)} utilisables, par niveau {counts}", flush=True)
        ctx.witnesses.extend(out)
        return out
