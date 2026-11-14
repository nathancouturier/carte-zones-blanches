import { describe, expect, it } from 'vitest';
import { lonLatToTilePixel } from '../src/coverage/tilemath';
import type { Sample } from '../src/gpx/resample';
import { corridorTiles, planCorridor, tileUrl } from '../src/offline/corridor';

/** Tracé rectiligne d'ouest en est, un point tous les 20 m environ. */
function line(lon0: number, lat: number, km: number): Sample[] {
  const n = Math.round((km * 1000) / 20) + 1;
  return Array.from({ length: n }, (_, i) => ({ lon: lon0 + i * 0.000254, lat, ele: null, dist: i * 20, seg: 0 }));
}

describe('couloir de tuiles pour le hors ligne', () => {
  const samples = line(6.4, 44.9, 10);

  it('contient les tuiles traversées par le tracé, sans doublon', () => {
    const tiles = corridorTiles(samples, 12, 0);
    const keys = tiles.map((t) => `${t.x}/${t.y}`);
    expect(new Set(keys).size).toBe(keys.length);
    for (const s of [samples[0], samples[250], samples[samples.length - 1]]) {
      const tp = lonLatToTilePixel(s.lon, s.lat, 12)!;
      expect(keys).toContain(`${tp.x}/${tp.y}`);
    }
    // 10 km d'ouest en est à cette latitude : 2 tuiles z12 (environ 6,9 km de large chacune).
    expect(tiles.length).toBeGreaterThanOrEqual(2);
    expect(tiles.length).toBeLessThanOrEqual(3);
    expect(new Set(tiles.map((t) => t.y)).size).toBe(1);
  });

  it('élargit le couloir avec la marge', () => {
    const narrow = corridorTiles(samples, 15, 0);
    const wide = corridorTiles(samples, 15, 1000);
    expect(wide.length).toBeGreaterThan(narrow.length);
    const narrowKeys = new Set(narrow.map((t) => `${t.x}/${t.y}`));
    const wideKeys = new Set(wide.map((t) => `${t.x}/${t.y}`));
    for (const key of narrowKeys) expect(wideKeys.has(key)).toBe(true);
    // Une tuile z15 fait environ 870 m ici : 1 km de marge ajoute au moins une rangée de chaque côté.
    expect(new Set(wide.map((t) => t.y)).size).toBeGreaterThanOrEqual(3);
  });

  it('respecte le plafond en renonçant aux zooms les plus fins', () => {
    const full = planCorridor(samples, { minZoom: 10, maxZoom: 16, buffer: 500, maxTiles: 100000 });
    expect(full.reduced).toBe(false);
    expect(full.maxZoom).toBe(16);
    const capped = planCorridor(samples, { minZoom: 10, maxZoom: 16, buffer: 500, maxTiles: 40 });
    expect(capped.reduced).toBe(true);
    expect(capped.maxZoom).toBeLessThan(16);
    expect(capped.tiles.length).toBeLessThanOrEqual(40);
    expect(capped.tiles.every((t) => t.z <= capped.maxZoom)).toBe(true);
    // Le zoom le plus grossier est toujours gardé, quitte à le tronquer.
    const tiny = planCorridor(samples, { minZoom: 14, maxZoom: 16, buffer: 500, maxTiles: 3 });
    expect(tiny.maxZoom).toBe(14);
    expect(tiny.tiles).toHaveLength(3);
    expect(tiny.reduced).toBe(true);
  });

  it('fabrique les URL de tuiles', () => {
    expect(tileUrl('https://ex.test/{z}/{x}/{y}.png', { z: 12, x: 2121, y: 1476 })).toBe('https://ex.test/12/2121/1476.png');
    expect(tileUrl('https://ex.test/wmts?TILEMATRIX={z}&TILECOL={x}&TILEROW={y}', { z: 5, x: 16, y: 11 })).toBe('https://ex.test/wmts?TILEMATRIX=5&TILECOL=16&TILEROW=11');
  });

  it('ignore un tracé vide', () => {
    expect(corridorTiles([], 12, 500)).toEqual([]);
    expect(planCorridor([], { minZoom: 10, maxZoom: 12, buffer: 0, maxTiles: 10 }).tiles).toEqual([]);
  });
});
