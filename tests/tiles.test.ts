import { describe, expect, it } from 'vitest';
import { LEVEL_GOOD, LEVEL_LIMITED, LEVEL_NONE, LEVEL_VERY_GOOD, packMeta, packSlots, TILE_SIZE, unpackSlot, writePixel } from '../src/coverage/codec';
import { LruCache } from '../src/coverage/lru';
import { buildLevelTables } from '../src/coverage/manifest';
import { childTile, ESTIMATED_MASKED_STRIPE, LEVEL_COLORS, renderTile, renderUnavailable, UNAVAILABLE_STRIPE } from '../src/coverage/render';
import { TileStore } from '../src/coverage/store';
import { lonLatToTilePixel, tileToLonLat } from '../src/coverage/tilemath';
import { sampleCoverage } from '../src/gpx/analyze';
import { distance } from '../src/gpx/geodesy';
import type { Sample } from '../src/gpx/resample';
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

  it('marque d\'un motif gris léger les zones estimées dont le niveau est masqué (sources-24)', () => {
    const tables = buildLevelTables(manifest, { service: 'data', operators: {} });
    // Toute une tuile en bonne couverture : estimée (Andorre) ou officielle (France).
    const tile = (country: number, sourceType: number): Uint8ClampedArray => {
      const d = new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4);
      for (let i = 0; i < TILE_SIZE * TILE_SIZE; i++) writePixel(d, i, { data: [2, 2, 2, 2], country, sourceType });
      return d;
    };
    const colors = (out: Uint8ClampedArray): Set<string> => {
      const seen = new Set<string>();
      for (let i = 0; i < 16 * TILE_SIZE; i++) seen.add(rgba(out, i).join());
      return seen;
    };
    const out = new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4);
    // Par défaut, la bonne couverture n'est pas dessinée : la zone estimée garde des traits gris légers.
    expect(renderTile(tile(5, 2), tables, { service: 'data', showAll: false }, out)).toBe(true);
    expect(colors(out)).toEqual(new Set(['0,0,0,0', ESTIMATED_MASKED_STRIPE.join()]));
    // Gris et peu opaques : ni une couleur de niveau, ni la tuile « données indisponibles » (voile et rayures foncées).
    expect(ESTIMATED_MASKED_STRIPE[3]).toBeLessThan(LEVEL_COLORS[LEVEL_GOOD][3]);
    expect(ESTIMATED_MASKED_STRIPE[3]).toBeLessThan(UNAVAILABLE_STRIPE[3]);
    expect(ESTIMATED_MASKED_STRIPE.slice(0, 3)).not.toEqual(UNAVAILABLE_STRIPE.slice(0, 3));
    // Même sens que les hachures des niveaux (x + y constant), pas celui des tuiles illisibles.
    const alpha = (x: number, y: number): number => out[(y * TILE_SIZE + x) * 4 + 3];
    for (let i = 1; i < 32; i++) expect(alpha(i, 0), `colonne ${i}`).toBe(alpha(i - 1, 1));
    // Une zone officielle bien couverte reste transparente, comme avant.
    expect(renderTile(tile(1, 0), tables, { service: 'data', showAll: false }, out)).toBe(false);
    // Toute la couverture affichée : la zone estimée prend la couleur de son niveau, hachurée comme les autres.
    renderTile(tile(5, 2), tables, { service: 'data', showAll: true }, out);
    expect(Math.max(...[...colors(out)].map((c) => Number(c.split(',')[3])))).toBe(LEVEL_COLORS[LEVEL_GOOD][3]);
    // Pas de donnée pour le service choisi (appels et SMS en Andorre) : rien n'est estimé, rien n'est dessiné.
    const voice = buildLevelTables(manifest, { service: 'voice', operators: {} });
    expect(renderTile(tile(5, 2), voice, { service: 'voice', showAll: false }, out)).toBe(false);
  });

  it('agrandit une partie de tuile en plus proche voisin pour les zooms au-delà des données', () => {
    const parent = new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4);
    for (let i = 0; i < TILE_SIZE * TILE_SIZE; i++) parent.set([i % TILE_SIZE, (i / TILE_SIZE) | 0, 7, 255], i * 4);
    const pixel = (data: Uint8ClampedArray, x: number, y: number): number[] => Array.from(data.slice((y * TILE_SIZE + x) * 4, (y * TILE_SIZE + x) * 4 + 4));
    // Un zoom plus loin, quart nord-est : chaque pixel de la tuile parente devient un carré de 2 x 2.
    const ne = childTile(parent, 1, 1, 0);
    expect(pixel(ne, 0, 0)).toEqual([128, 0, 7, 255]);
    expect(pixel(ne, 1, 1)).toEqual([128, 0, 7, 255]);
    expect(pixel(ne, 2, 1)).toEqual([129, 0, 7, 255]);
    expect(pixel(ne, 255, 255)).toEqual([255, 127, 7, 255]);
    // Quatre zooms plus loin (zoom 16 depuis le zoom 12) : carrés de 16 x 16.
    const z16 = childTile(parent, 4, 5, 9);
    expect(pixel(z16, 0, 0)).toEqual([80, 144, 7, 255]);
    expect(pixel(z16, 15, 15)).toEqual([80, 144, 7, 255]);
    expect(pixel(z16, 16, 0)).toEqual([81, 144, 7, 255]);
    expect(pixel(z16, 255, 255)).toEqual([95, 159, 7, 255]);
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

  it('l\'analyse d\'un tracé de 900 km n\'évince pas les tuiles affichées : un changement de réglage ne relit rien (archi-21)', async () => {
    // Archive simulée : chaque lecture est comptée, le décodage rend une tuile de données uniforme.
    const lues: string[] = [];
    const store = new TileStore(
      sampleManifest(),
      async (_file, z, x, y) => {
        lues.push(`${z}/${x}/${y}`);
        return new ArrayBuffer(8);
      },
      async () => new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4).fill(255),
    );
    // Une vue au zoom 8 : 9 x 6 tuiles affichées.
    const vue: [number, number, number][] = [];
    for (let x = 128; x < 137; x++) for (let y = 88; y < 94; y++) vue.push([8, x, y]);
    const afficher = (): Promise<unknown> => Promise.all(vue.map(([z, x, y]) => store.get(z, x, y)));
    await afficher();
    expect(lues).toHaveLength(54);
    // Un tracé de 900 km en diagonale, des Pyrénées au Jura : bien plus de tuiles du zoom 12 que le cache n'en garde.
    const debut = { lon: 0, lat: 42 };
    const pas = 4500;
    const samples: Sample[] = Array.from({ length: pas + 1 }, (_, i) => ({ lon: debut.lon + (8 * i) / pas, lat: debut.lat + (6 * i) / pas, ele: null, dist: 0, seg: 0 }));
    for (let i = 1; i < samples.length; i++) samples[i].dist = samples[i - 1].dist + distance(samples[i - 1].lon, samples[i - 1].lat, samples[i].lon, samples[i].lat);
    expect(samples[pas].dist).toBeGreaterThan(900_000);
    const avant = lues.length;
    const raw = await sampleCoverage(samples, store);
    expect(raw.inside.every((v) => v === 1)).toBe(true);
    expect(lues.length - avant).toBeGreaterThan(160);
    // Changement de réglage : la couche réseau redemande les tuiles affichées, toujours en cache.
    const apres = lues.length;
    await afficher();
    expect(lues.length - apres).toBe(0);
  });

  it('la carte, cadrée ensuite sur un tracé court, affiche ses tuiles sans les relire (archi-21)', async () => {
    const lues: string[] = [];
    const store = new TileStore(
      sampleManifest(),
      async (_file, z, x, y) => {
        lues.push(`${z}/${x}/${y}`);
        return new ArrayBuffer(8);
      },
      async () => new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4).fill(255),
    );
    // Une vue au zoom 8, puis une randonnée d'une vingtaine de kilomètres (quelques tuiles du zoom 12).
    const vue: [number, number, number][] = [];
    for (let x = 128; x < 137; x++) for (let y = 88; y < 94; y++) vue.push([8, x, y]);
    await Promise.all(vue.map(([z, x, y]) => store.get(z, x, y)));
    const samples: Sample[] = Array.from({ length: 1001 }, (_, i) => ({ lon: 6.73 + (0.17 * i) / 1000, lat: 45.7 + (0.09 * i) / 1000, ele: null, dist: i * 20, seg: 0 }));
    lues.length = 0;
    await sampleCoverage(samples, store);
    const trace = lues.map((cle) => cle.split('/').map(Number) as [number, number, number]);
    expect(trace.length).toBeGreaterThan(1);
    // Après l'analyse, la carte zoome sur le tracé : elle trouve ses tuiles sans relire l'archive,
    // et les tuiles de la vue précédente sont toujours en cache.
    lues.length = 0;
    await Promise.all(trace.map(([z, x, y]) => store.get(z, x, y)));
    await Promise.all(vue.map(([z, x, y]) => store.get(z, x, y)));
    expect(lues).toEqual([]);
  });

  it('une tuile lue pour l\'analyse et demandée en même temps par la carte n\'est lue qu\'une fois (archi-21)', async () => {
    let lectures = 0;
    let liberer = (): void => undefined;
    const attente = new Promise<void>((resolve) => (liberer = resolve));
    const store = new TileStore(
      sampleManifest(),
      async () => {
        lectures++;
        await attente;
        return new ArrayBuffer(8);
      },
      async () => new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4).fill(255),
    );
    const analyse = store.getTransient(12, 2116, 1479);
    const carte = store.get(12, 2116, 1479);
    liberer();
    expect(await carte).toBe(await analyse);
    expect(lectures).toBe(1);
    // La carte l'a demandée : elle reste en cache. Lue pour l'analyse seule, une tuile n'y entre pas.
    expect(store.peek(12, 2116, 1479)).not.toBeUndefined();
    await store.getTransient(12, 2117, 1479);
    expect(store.peek(12, 2117, 1479)).toBeUndefined();
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

  it('trouve tout ce que la vue affiche, même un petit pays entre deux points de la vue, et rien au-delà', async () => {
    // Deux tuiles voisines au zoom 8 : la France, avec 2 x 2 pixels d'Andorre estimée ; la Suisse, sur la moitié est de l'autre.
    const tuiles = new Map<number, Uint8ClampedArray>();
    const france = new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4);
    for (let i = 0; i < TILE_SIZE * TILE_SIZE; i++) writePixel(france, i, { data: [2], country: 1 });
    for (const [px, py] of [[200, 10], [201, 10], [200, 11], [201, 11]]) writePixel(france, py * TILE_SIZE + px, { data: [0], country: 5, sourceType: 2 });
    const suisse = new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4);
    for (let py = 0; py < TILE_SIZE; py++) for (let px = 128; px < TILE_SIZE; px++) writePixel(suisse, py * TILE_SIZE + px, { data: [3], country: 2, sourceType: 1 });
    tuiles.set(132, france);
    tuiles.set(133, suisse);
    const lues: string[] = [];
    const store = new TileStore(
      sampleManifest(),
      async (_file, z, x, y) => {
        lues.push(`${z}/${x}/${y}`);
        return z === 8 && y === 92 && tuiles.has(x) ? new Uint8Array([x]).buffer : undefined;
      },
      async (bytes) => tuiles.get(new Uint8Array(bytes)[0])!,
    );
    const ouest = tileToLonLat(132, 92, 8);
    const sud = tileToLonLat(133, 93, 8).lat;
    // Toute la tuile française, et la tuile suisse jusqu'à son 100e pixel : pas de Suisse à l'écran.
    const jusqua = (px: number): number => tileToLonLat(133 + px / TILE_SIZE, 92, 8).lon;
    expect(await store.metaInBounds([ouest.lon, sud, jusqua(100), ouest.lat], 8)).toEqual([packMeta(1, 0), packMeta(5, 2)]);
    expect(await store.metaInBounds([ouest.lon, sud, jusqua(200), ouest.lat], 8)).toEqual([packMeta(1, 0), packMeta(2, 1), packMeta(5, 2)]);
    // Une vue qui demanderait trop de tuiles est lue au zoom inférieur.
    lues.length = 0;
    await store.metaInBounds([ouest.lon, sud, jusqua(200), ouest.lat], 8, 1);
    expect(lues).toEqual(['7/66/46']);
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
