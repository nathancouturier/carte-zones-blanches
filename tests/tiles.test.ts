import { describe, expect, it } from 'vitest';
import { LEVEL_GOOD, LEVEL_LIMITED, LEVEL_NONE, LEVEL_VERY_GOOD, packMeta, packSlots, TILE_SIZE, unpackSlot, writePixel } from '../src/coverage/codec';
import { LruCache } from '../src/coverage/lru';
import { buildLevelTables } from '../src/coverage/manifest';
import { LEVEL_COLORS, renderTile, renderUnavailable } from '../src/coverage/render';
import { TileStore } from '../src/coverage/store';
import { lonLatToTilePixel, tileToLonLat } from '../src/coverage/tilemath';
import { fixtureStore, readJsonFixture, sampleManifest } from './helpers';

describe('géométrie des tuiles', () => {
  it('place un point dans la bonne tuile et le bon pixel', () => {
    // Coin nord-ouest de la tuile 12/2114/1470, puis son centre.
    const corner = tileToLonLat(2114, 1470, 12);
    const next = tileToLonLat(2115, 1471, 12);
    expect(lonLatToTilePixel(corner.lon + 1e-9, corner.lat - 1e-9, 12)).toEqual({ z: 12, x: 2114, y: 1470, px: 0, py: 0 });
    const mid = lonLatToTilePixel((corner.lon + next.lon) / 2, (corner.lat + next.lat) / 2, 12);
    expect(mid).toMatchObject({ x: 2114, y: 1470 });
    expect(mid!.px).toBeGreaterThanOrEqual(127);
    expect(mid!.px).toBeLessThanOrEqual(128);
    expect(lonLatToTilePixel(next.lon - 1e-9, next.lat + 1e-9, 12)).toEqual({ z: 12, x: 2114, y: 1470, px: 255, py: 255 });
  });

  it('gère les zooms inférieurs et les points hors du monde Mercator', () => {
    expect(lonLatToTilePixel(0, 0, 0)).toEqual({ z: 0, x: 0, y: 0, px: 128, py: 128 });
    expect(lonLatToTilePixel(6.08, 44.56, 8)).toMatchObject({ z: 8, x: 132, y: 92 });
    expect(lonLatToTilePixel(6.08, 89, 12)).toBeNull();
    expect(lonLatToTilePixel(Number.NaN, 45, 12)).toBeNull();
  });
});

describe('cache LRU', () => {
  it('évince l\'entrée la plus anciennement utilisée', () => {
    const cache = new LruCache<string, number>(2);
    cache.set('a', 1);
    cache.set('b', 2);
    expect(cache.get('a')).toBe(1); // « a » redevient la plus récente
    cache.set('c', 3);
    expect(cache.has('b')).toBe(false);
    expect(cache.keys()).toEqual(['a', 'c']);
    expect(cache.size).toBe(2);
    expect(() => new LruCache(0)).toThrow(RangeError);
  });
});

describe('recolorisation des tuiles', () => {
  const manifest = sampleManifest();
  const data = new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4);
  // 0 : hors zone ; 1 à 4 : France, niveaux 0 à 3 pour Orange ; 5 : Andorre estimée, pas de couverture.
  writePixel(data, 1, { data: [0, 3, 3, 3], country: 1 });
  writePixel(data, 2, { data: [1, 3, 3, 3], country: 1 });
  writePixel(data, 3, { data: [2, 0, 0, 0], country: 1 });
  writePixel(data, 4, { data: [3, 0, 0, 0], country: 1 });
  writePixel(data, 5, { data: [0], country: 5, sourceType: 2 });
  writePixel(data, 6, { data: [3], country: 9 }); // pays inconnu du manifest
  const rgba = (out: Uint8ClampedArray, i: number): number[] => Array.from(out.slice(i * 4, i * 4 + 4));

  it('ne montre que les problèmes par défaut', () => {
    const tables = buildLevelTables(manifest, { service: 'data', operators: { FR: 'orange' } });
    const out = new Uint8ClampedArray(data.length);
    expect(renderTile(data, tables, { service: 'data', showAll: false }, out)).toBe(true);
    expect(rgba(out, 0)).toEqual([0, 0, 0, 0]);
    expect(rgba(out, 1)).toEqual([...LEVEL_COLORS[LEVEL_NONE]]);
    expect(rgba(out, 2)).toEqual([...LEVEL_COLORS[LEVEL_LIMITED]]);
    expect(rgba(out, 3)).toEqual([0, 0, 0, 0]);
    expect(rgba(out, 4)).toEqual([0, 0, 0, 0]);
    expect(rgba(out, 6)).toEqual([0, 0, 0, 0]);
  });

  it('montre toute la couverture sur demande', () => {
    const tables = buildLevelTables(manifest, { service: 'data', operators: { FR: 'orange' } });
    const out = new Uint8ClampedArray(data.length);
    renderTile(data, tables, { service: 'data', showAll: true }, out);
    expect(rgba(out, 3)).toEqual([...LEVEL_COLORS[LEVEL_GOOD]]);
    expect(rgba(out, 4)).toEqual([...LEVEL_COLORS[LEVEL_VERY_GOOD]]);
  });

  it('applique « tous opérateurs » : le maximum des emplacements', () => {
    const tables = buildLevelTables(manifest, { service: 'data', operators: {} });
    const out = new Uint8ClampedArray(data.length);
    renderTile(data, tables, { service: 'data', showAll: false }, out);
    // Les pixels 1 et 2 sont très bien couverts par les autres opérateurs : rien à signaler.
    expect(rgba(out, 1)).toEqual([0, 0, 0, 0]);
    expect(rgba(out, 2)).toEqual([0, 0, 0, 0]);
  });

  it('hachure les zones estimées', () => {
    const tables = buildLevelTables(manifest, { service: 'data', operators: {} });
    const estimated = new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4);
    for (let i = 0; i < TILE_SIZE * TILE_SIZE; i++) writePixel(estimated, i, { data: [0], country: 5, sourceType: 2 });
    const out = new Uint8ClampedArray(estimated.length);
    renderTile(estimated, tables, { service: 'data', showAll: false }, out);
    const alphas = new Set<number>();
    for (let i = 0; i < 64; i++) alphas.add(out[i * 4 + 3]);
    expect(alphas.size).toBe(2); // bandes pleines et bandes claires
    expect(Math.max(...alphas)).toBe(LEVEL_COLORS[LEVEL_NONE][3]);
    // Une zone officielle n'est pas hachurée.
    const official = new Uint8ClampedArray(estimated.length);
    for (let i = 0; i < TILE_SIZE * TILE_SIZE; i++) writePixel(official, i, { data: [0], country: 1 });
    renderTile(official, tables, { service: 'data', showAll: false }, out);
    const officialAlphas = new Set<number>();
    for (let i = 0; i < 64; i++) officialAlphas.add(out[i * 4 + 3]);
    expect(officialAlphas.size).toBe(1);
  });

  it('raccorde les rayures des tuiles illisibles d\'une tuile à l\'autre', () => {
    const out = new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4);
    renderUnavailable(out);
    const alpha = (x: number, y: number): number => out[(y * TILE_SIZE + x) * 4 + 3];
    // Les rayures suivent la diagonale : le premier pixel d'une ligne de la tuile voisine (à droite)
    // prolonge le dernier pixel de la ligne du dessus, et de même pour la tuile du dessous.
    for (let i = 1; i < TILE_SIZE; i++) {
      expect(alpha(0, i), `ligne ${i}`).toBe(alpha(TILE_SIZE - 1, i - 1));
      expect(alpha(i, 0), `colonne ${i}`).toBe(alpha(i - 1, TILE_SIZE - 1));
    }
  });

  it('ne dessine rien pour un service sans données', () => {
    const tables = buildLevelTables(manifest, { service: 'voice', operators: {} });
    const out = new Uint8ClampedArray(data.length);
    expect(renderTile(data, tables, { service: 'voice', showAll: true }, out)).toBe(false);
  });
});

interface Witness {
  service: 'data' | 'voice';
  slot: number;
  x: number;
  y: number;
  px: number;
  py: number;
  lon: number;
  lat: number;
  expected: number;
}

describe('lecture des archives PMTiles produites par le pipeline', () => {
  it('retrouve dans les tuiles les niveaux lus dans la source par le pipeline', async () => {
    const { store } = fixtureStore('synthetique');
    const witnesses = readJsonFixture<Witness[]>('synthetique/temoins.json');
    expect(witnesses.length).toBeGreaterThan(100);
    const seen = new Set<number>();
    for (const w of witnesses) {
      const tile = await store.get(12, w.x, w.y);
      expect(tile).not.toBeNull();
      const o = (w.py * TILE_SIZE + w.px) * 4;
      expect(tile![o + 3]).toBe(255);
      expect(tile![o + 2]).toBe(packMeta(1, 0));
      expect(unpackSlot(tile![o + (w.service === 'voice' ? 1 : 0)], w.slot)).toBe(w.expected);
      // Même résultat en partant de la longitude et de la latitude.
      const pixel = await store.sample(w.lon, w.lat);
      expect(pixel).not.toBeNull();
      expect(unpackSlot(pixel![w.service === 'voice' ? 1 : 0], w.slot)).toBe(w.expected);
      seen.add(w.expected);
    }
    expect([...seen].sort()).toEqual([0, 1, 2, 3]);
  });

  it('met les tuiles en cache et ne relit pas l\'archive', async () => {
    const { store, reads } = fixtureStore('synthetique');
    const first = await store.get(12, 2116, 1479);
    const [again, parallel] = await Promise.all([store.get(12, 2116, 1479), store.get(12, 2116, 1479)]);
    expect(first).toBe(again);
    expect(again).toBe(parallel);
    expect(reads.filter((r) => r.endsWith('12/2116/1479'))).toHaveLength(1);
    expect(store.peek(12, 2116, 1479)).toBe(first);
    expect(store.peek(12, 1, 1)).toBeUndefined();
  });

  it('renvoie null hors des données, sans erreur', async () => {
    const { store, reads } = fixtureStore('synthetique');
    expect(await store.get(12, 100, 100)).toBeNull();
    expect(await store.get(13, 0, 0)).toBeNull();
    expect(await store.get(12, -1, 5)).toBeNull();
    expect(await store.sample(2.35, 48.85)).toBeNull(); // Paris, hors du jeu de test
    expect(await store.sample(0, 89)).toBeNull();
    await store.get(12, 100, 100);
    expect(reads.filter((r) => r.endsWith('12/100/100'))).toHaveLength(1); // l'absence est aussi mise en cache
  });

  it('lit les zooms inférieurs', async () => {
    const { store } = fixtureStore('synthetique');
    const tile = await store.get(8, 132, 92);
    expect(tile).not.toBeNull();
    const pixel = await store.sample(6.0768, 44.5632, 8);
    expect(pixel?.[3]).toBe(255);
  });

  it('propage une erreur de lecture sans la mettre en cache', async () => {
    const manifest = sampleManifest();
    let calls = 0;
    const store = new TileStore(
      manifest,
      async () => {
        calls++;
        throw new Error('réseau coupé');
      },
      async () => new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4),
    );
    await expect(store.get(5, 16, 11)).rejects.toThrow('réseau coupé');
    await expect(store.get(5, 16, 11)).rejects.toThrow('réseau coupé');
    expect(calls).toBe(2);
    expect(packSlots([0])).toBe(0);
  });
});
