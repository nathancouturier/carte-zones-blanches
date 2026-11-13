// Géométrie des tuiles XYZ (Web Mercator).

import { TILE_SIZE } from './codec';

export const MAX_MERCATOR_LAT = 85.0511287798066;

/** Position en « pixels monde » au zoom z (l'origine est le coin nord-ouest). */
export function lonLatToWorldPixel(lon: number, lat: number, z: number): { x: number; y: number } {
  const n = 2 ** z * TILE_SIZE;
  const clamped = Math.max(-MAX_MERCATOR_LAT, Math.min(MAX_MERCATOR_LAT, lat));
  const sin = Math.sin((clamped * Math.PI) / 180);
  const x = ((lon + 180) / 360) * n;
  const y = (0.5 - Math.log((1 + sin) / (1 - sin)) / (4 * Math.PI)) * n;
  return { x, y };
}

export interface TilePixel {
  z: number;
  /** Colonne et ligne de la tuile. */
  x: number;
  y: number;
  /** Pixel dans la tuile, de 0 à 255. */
  px: number;
  py: number;
}

/** Tuile et pixel qui contiennent un point, au zoom z. Renvoie null hors du monde Mercator. */
export function lonLatToTilePixel(lon: number, lat: number, z: number): TilePixel | null {
  if (!Number.isFinite(lon) || !Number.isFinite(lat) || Math.abs(lat) > MAX_MERCATOR_LAT) return null;
  const world = lonLatToWorldPixel(lon, lat, z);
  const size = 2 ** z * TILE_SIZE;
  // La longitude boucle, la latitude non.
  const wx = ((Math.floor(world.x) % size) + size) % size;
  const wy = Math.min(size - 1, Math.max(0, Math.floor(world.y)));
  return {
    z,
    x: Math.floor(wx / TILE_SIZE),
    y: Math.floor(wy / TILE_SIZE),
    px: wx % TILE_SIZE,
    py: wy % TILE_SIZE,
  };
}

/** Longitude et latitude du coin nord-ouest d'une tuile. */
export function tileToLonLat(x: number, y: number, z: number): { lon: number; lat: number } {
  const n = 2 ** z;
  const lon = (x / n) * 360 - 180;
  const lat = (Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / n))) * 180) / Math.PI;
  return { lon, lat };
}

export function tileKey(z: number, x: number, y: number): string {
  return `${z}/${x}/${y}`;
}
