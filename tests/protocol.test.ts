import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { TILE_SIZE } from '../src/coverage/codec';
import { decodeWithJs } from '../src/coverage/decode';
import { buildLevelTables } from '../src/coverage/manifest';
import { coverageTileLoader, type CoverageRenderState } from '../src/coverage/protocol';
import { UNAVAILABLE_STRIPE, UNAVAILABLE_VEIL } from '../src/coverage/render';
import { TileStore } from '../src/coverage/store';
import { sampleManifest } from './helpers';

/** État de rendu dont les lectures ne reviennent jamais (connexion qui cale). */
function stalledState(): CoverageRenderState {
  const manifest = sampleManifest();
  const store = new TileStore(manifest, () => new Promise<ArrayBuffer | undefined>(() => undefined), decodeWithJs);
  return { store, tables: buildLevelTables(manifest, { service: 'data', operators: {} }), settings: { service: 'data', showAll: false } };
}

describe('protocole couverture://', () => {
  it('rend la main dès que MapLibre annule la tuile, sans attendre la lecture', async () => {
    const state = stalledState();
    const load = coverageTileLoader(() => state);
    const controller = new AbortController();
    const started = Date.now();
    const response = load({ url: 'couverture://5/16/11' }, controller);
    setTimeout(() => controller.abort(), 20);
    // Sinon la place reste prise dans la file d'images de MapLibre, partagée avec les fonds raster.
    await expect(response).rejects.toMatchObject({ name: 'AbortError' });
    expect(Date.now() - started).toBeLessThan(1000);
  });

  it('refuse tout de suite une tuile déjà annulée', async () => {
    const state = stalledState();
    const controller = new AbortController();
    controller.abort();
    await expect(coverageTileLoader(() => state)({ url: 'couverture://5/16/11' }, controller)).rejects.toMatchObject({ name: 'AbortError' });
  });
});

/** Image minimale pour Node : le navigateur fournit ImageData et createImageBitmap. */
class FakeImageData {
  readonly data: Uint8ClampedArray;
  constructor(
    readonly width: number,
    readonly height: number,
  ) {
    this.data = new Uint8ClampedArray(width * height * 4);
  }
}

describe('tuile illisible', () => {
  beforeEach(() => {
    vi.stubGlobal('ImageData', FakeImageData);
    vi.stubGlobal('createImageBitmap', async (image: FakeImageData) => image);
  });
  afterEach(() => vi.unstubAllGlobals());

  it('affiche une tuile « données indisponibles » et signale l\'échec, au lieu d\'une tuile vide', async () => {
    const manifest = sampleManifest();
    const failing = new TileStore(manifest, async () => {
      throw new TypeError('Failed to fetch');
    }, decodeWithJs);
    const state: CoverageRenderState = { store: failing, tables: buildLevelTables(manifest, { service: 'data', operators: {} }), settings: { service: 'data', showAll: false } };
    const errors: unknown[] = [];
    const load = coverageTileLoader(() => state, (error) => errors.push(error));
    const response = await load({ url: 'couverture://5/16/11' }, new AbortController());
    const image = response.data as unknown as FakeImageData;
    expect(image.width).toBe(TILE_SIZE);
    expect(errors).toHaveLength(1);
    // Gris hachuré : un voile clair et des rayures foncées, sans aucune couleur de niveau.
    const colors = new Set<string>();
    for (let o = 0; o < image.data.length; o += 4) colors.add(Array.from(image.data.slice(o, o + 4)).join());
    expect([...colors].sort()).toEqual([UNAVAILABLE_STRIPE.join(), UNAVAILABLE_VEIL.join()].sort());
    // Les rayures vont dans l'autre sens que celles des zones estimées : x - y constant, et non x + y.
    const alpha = (x: number, y: number): number => image.data[(y * TILE_SIZE + x) * 4 + 3];
    expect([alpha(10, 10), alpha(100, 100), alpha(200, 200)]).toEqual(Array(3).fill(UNAVAILABLE_STRIPE[3]));
    expect([alpha(16, 10), alpha(10, 16)]).toEqual(Array(2).fill(UNAVAILABLE_VEIL[3]));
  });

  it('une annulation ne compte pas comme un échec', async () => {
    const state = stalledState();
    const errors: unknown[] = [];
    const controller = new AbortController();
    const response = coverageTileLoader(() => state, (error) => errors.push(error))({ url: 'couverture://5/16/11' }, controller);
    controller.abort();
    await expect(response).rejects.toMatchObject({ name: 'AbortError' });
    expect(errors).toHaveLength(0);
  });
});
