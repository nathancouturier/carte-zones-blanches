// Tuiles à précharger pour suivre un tracé hors ligne : un couloir de part et
// d'autre du parcours, à plusieurs zooms.

import { lonLatToTilePixel } from '../coverage/tilemath';
import type { Sample } from '../gpx/resample';

export interface TileId {
  z: number;
  x: number;
  y: number;
}

const EARTH_RADIUS_M = 6371008.8;

/** Décale un point de « east » et « north » mètres. */
function offset(lon: number, lat: number, east: number, north: number): [number, number] {
  const dLat = (north / EARTH_RADIUS_M) * (180 / Math.PI);
  const dLon = (east / (EARTH_RADIUS_M * Math.cos((lat * Math.PI) / 180))) * (180 / Math.PI);
  return [lon + dLon, lat + dLat];
}

/**
 * Tuiles du zoom z qui touchent un couloir de « buffer » mètres autour du tracé.
 * Les points du tracé sont espacés de 20 m : il suffit de regarder, pour chacun,
 * le carré de côté 2 x buffer centré sur lui.
 */
export function corridorTiles(samples: readonly Sample[], z: number, buffer: number): TileId[] {
  const seen = new Set<string>();
  const tiles: TileId[] = [];
  const n = 2 ** z;
  let lastKey = '';
  for (const s of samples) {
    const [west, south] = offset(s.lon, s.lat, -buffer, -buffer);
    const [east, north] = offset(s.lon, s.lat, buffer, buffer);
    const a = lonLatToTilePixel(west, north, z);
    const b = lonLatToTilePixel(east, south, z);
    if (!a || !b) continue;
    const key = `${a.x}/${a.y}/${b.x}/${b.y}`;
    if (key === lastKey) continue; // même pavé que le point précédent
    lastKey = key;
    // Le couloir est toujours bien plus étroit que le monde : pas de passage par l'antiméridien à gérer ici.
    for (let x = Math.min(a.x, b.x); x <= Math.max(a.x, b.x); x++) {
      for (let y = a.y; y <= b.y; y++) {
        if (x < 0 || y < 0 || x >= n || y >= n) continue;
        const id = `${x}/${y}`;
        if (seen.has(id)) continue;
        seen.add(id);
        tiles.push({ z, x, y });
      }
    }
  }
  return tiles;
}

export interface CorridorPlan {
  tiles: TileId[];
  /** Zoom le plus fin retenu. */
  maxZoom: number;
  /** Vrai si le zoom maximal demandé a dû être réduit pour tenir sous le plafond. */
  reduced: boolean;
}

/**
 * Tuiles de minZoom à maxZoom le long du tracé, sans dépasser « maxTiles ».
 * Si le total dépasse le plafond, on renonce aux zooms les plus fins : ce sont
 * eux qui coûtent le plus de requêtes au fournisseur.
 */
export function planCorridor(
  samples: readonly Sample[],
  options: { minZoom: number; maxZoom: number; buffer: number; maxTiles: number },
): CorridorPlan {
  const byZoom: TileId[][] = [];
  for (let z = options.minZoom; z <= options.maxZoom; z++) byZoom.push(corridorTiles(samples, z, options.buffer));
  let top = byZoom.length;
  let total = byZoom.reduce((sum, tiles) => sum + tiles.length, 0);
  while (top > 1 && total > options.maxTiles) {
    top--;
    total -= byZoom[top].length;
  }
  const tiles = byZoom.slice(0, top).flat();
  return {
    tiles: tiles.length > options.maxTiles ? tiles.slice(0, options.maxTiles) : tiles,
    maxZoom: options.minZoom + top - 1,
    reduced: top < byZoom.length || tiles.length > options.maxTiles,
  };
}

/** Remplace {z}, {x} et {y} dans un gabarit d'URL de tuiles. */
export function tileUrl(template: string, tile: TileId): string {
  return template.replace('{z}', String(tile.z)).replace('{x}', String(tile.x)).replace('{y}', String(tile.y));
}
