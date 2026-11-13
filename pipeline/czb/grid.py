"""Grille commune à toutes les sources.

Toutes les sources sont ramenées sur la même grille : EPSG:3857, pixels alignés
sur les tuiles XYZ du zoom maximal (12 par défaut, tuiles de 256 px).
"""

from __future__ import annotations

import math
from dataclasses import dataclass

EARTH_RADIUS = 6378137.0
ORIGIN = math.pi * EARTH_RADIUS  # 20037508,34 m
WORLD = 2 * ORIGIN
MAX_LAT = 85.0511287798066


def lonlat_to_mercator(lon: float, lat: float) -> tuple[float, float]:
    lat = max(-MAX_LAT, min(MAX_LAT, lat))
    x = math.radians(lon) * EARTH_RADIUS
    y = math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * EARTH_RADIUS
    return x, y


def mercator_to_lonlat(x: float, y: float) -> tuple[float, float]:
    lon = math.degrees(x / EARTH_RADIUS)
    lat = math.degrees(2 * math.atan(math.exp(y / EARTH_RADIUS)) - math.pi / 2)
    return lon, lat


@dataclass(frozen=True)
class Grid:
    zoom: int = 12
    tile_size: int = 256

    @property
    def tiles_per_side(self) -> int:
        return 1 << self.zoom

    @property
    def resolution(self) -> float:
        """Taille d'un pixel en mètres Mercator."""
        return WORLD / (self.tiles_per_side * self.tile_size)

    def tile_of_mercator(self, x: float, y: float) -> tuple[int, int]:
        n = self.tiles_per_side
        tx = int(math.floor((x + ORIGIN) / WORLD * n))
        ty = int(math.floor((ORIGIN - y) / WORLD * n))
        return max(0, min(n - 1, tx)), max(0, min(n - 1, ty))

    def tile_of_lonlat(self, lon: float, lat: float) -> tuple[int, int]:
        return self.tile_of_mercator(*lonlat_to_mercator(lon, lat))

    def canvas_for_mercator_bounds(self, minx: float, miny: float, maxx: float, maxy: float) -> "Canvas":
        """Plus petite fenêtre alignée sur les tuiles qui contient l'emprise."""
        eps = self.resolution * 1e-6
        tx0, ty0 = self.tile_of_mercator(minx + eps, maxy - eps)
        tx1, ty1 = self.tile_of_mercator(maxx - eps, miny + eps)
        return Canvas(self, tx0, ty0, tx1, ty1)


@dataclass(frozen=True)
class Canvas:
    """Fenêtre de la grille alignée sur les tuiles : colonnes tx0 à tx1, lignes ty0 à ty1 (inclus)."""

    grid: Grid
    tx0: int
    ty0: int
    tx1: int
    ty1: int

    @property
    def width(self) -> int:
        return (self.tx1 - self.tx0 + 1) * self.grid.tile_size

    @property
    def height(self) -> int:
        return (self.ty1 - self.ty0 + 1) * self.grid.tile_size

    @property
    def origin_x(self) -> float:
        return -ORIGIN + self.tx0 * self.grid.tile_size * self.grid.resolution

    @property
    def origin_y(self) -> float:
        return ORIGIN - self.ty0 * self.grid.tile_size * self.grid.resolution

    @property
    def mercator_bounds(self) -> tuple[float, float, float, float]:
        res = self.grid.resolution
        return (self.origin_x, self.origin_y - self.height * res, self.origin_x + self.width * res, self.origin_y)

    @property
    def lonlat_bounds(self) -> tuple[float, float, float, float]:
        minx, miny, maxx, maxy = self.mercator_bounds
        west, south = mercator_to_lonlat(minx, miny)
        east, north = mercator_to_lonlat(maxx, maxy)
        return west, south, east, north

    def geotransform(self, col0: int = 0, row0: int = 0) -> tuple[float, float, float, float, float, float]:
        res = self.grid.resolution
        return (self.origin_x + col0 * res, res, 0.0, self.origin_y - row0 * res, 0.0, -res)

    def pixel_center(self, col: int, row: int) -> tuple[float, float]:
        res = self.grid.resolution
        return self.origin_x + (col + 0.5) * res, self.origin_y - (row + 0.5) * res

    def pixel_of_mercator(self, x: float, y: float) -> tuple[int, int]:
        res = self.grid.resolution
        return int(math.floor((x - self.origin_x) / res)), int(math.floor((self.origin_y - y) / res))

    def window_for_envelope(self, minx: float, maxx: float, miny: float, maxy: float) -> tuple[int, int, int, int] | None:
        """Fenêtre (col0, row0, largeur, hauteur) couvrant une enveloppe, limitée à la grille."""
        res = self.grid.resolution
        col0 = max(0, int(math.floor((minx - self.origin_x) / res)))
        col1 = min(self.width, int(math.ceil((maxx - self.origin_x) / res)))
        row0 = max(0, int(math.floor((self.origin_y - maxy) / res)))
        row1 = min(self.height, int(math.ceil((self.origin_y - miny) / res)))
        if col1 <= col0 or row1 <= row0:
            return None
        return col0, row0, col1 - col0, row1 - row0

    def tile_and_pixel(self, col: int, row: int) -> tuple[int, int, int, int]:
        """Tuile (x, y) du zoom de la grille et pixel (px, py) dans cette tuile."""
        ts = self.grid.tile_size
        return self.tx0 + col // ts, self.ty0 + row // ts, col % ts, row % ts
