import { describe, expect, it } from 'vitest';
import { decodeWithJs } from '../src/coverage/decode';
import { buildLevelTables } from '../src/coverage/manifest';
import { coverageTileLoader, type CoverageRenderState } from '../src/coverage/protocol';
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
