import { PMTiles } from 'pmtiles';
import { describe, expect, it } from 'vitest';
import { createArchiveReader } from '../src/coverage/archives';
import { decodeWithJs } from '../src/coverage/decode';
import { NewDataWatcher, sameData } from '../src/coverage/freshness';
import { parseManifest, type Manifest } from '../src/coverage/manifest';
import { TileStore } from '../src/coverage/store';
import { FlakySource, readFixture, readJsonFixture } from './helpers';

const FILE = 'couverture-20261113-00.pmtiles';

/** Le manifest des fixtures, et une version plus ancienne qui annonce une archive disparue du serveur. */
function manifests(): { current: Manifest; old: Manifest } {
  const raw = readJsonFixture<Record<string, unknown> & { archives: { file: string }[] }>('synthetique/manifest.json');
  const current = parseManifest(raw);
  const old = parseManifest({ ...raw, generated: '2026-10-01', archives: raw.archives.map((a) => ({ ...a, file: 'couverture-20261001-00.pmtiles' })) });
  return { current, old };
}

const notFound = (): Error => new Error('Bad response code: 404');

describe('nouvelle publication des données', () => {
  it('compare les manifests sur la date de génération et les archives', () => {
    const { current, old } = manifests();
    expect(sameData(current, current)).toBe(true);
    expect(sameData(current, old)).toBe(false);
    expect(sameData(current, { ...current, archives: [] })).toBe(false);
  });

  it('relit le manifest après une erreur de lecture et repart sur les nouvelles données', async () => {
    const { current, old } = manifests();
    let fetches = 0;
    const received: Manifest[] = [];
    const watcher = new NewDataWatcher(
      old,
      async () => {
        fetches++;
        return current;
      },
      (manifest) => received.push(manifest),
    );
    // Plusieurs tuiles échouent en même temps : une seule relecture.
    await Promise.all([watcher.report(notFound()), watcher.report(notFound()), watcher.report(notFound())]);
    expect(fetches).toBe(1);
    expect(received).toEqual([current]);
  });

  it('ne relit pas pour une annulation, ni plus d\'une fois par intervalle si rien n\'a changé', async () => {
    const { current } = manifests();
    let now = 0;
    let fetches = 0;
    const received: Manifest[] = [];
    const watcher = new NewDataWatcher(
      current,
      async () => {
        fetches++;
        return current;
      },
      (manifest) => received.push(manifest),
      60_000,
      () => now,
    );
    const abort = new Error('Requête annulée');
    abort.name = 'AbortError';
    await watcher.report(abort);
    expect(fetches).toBe(0);
    await watcher.report(notFound());
    expect(fetches).toBe(1);
    now = 30_000;
    await watcher.report(notFound());
    expect(fetches).toBe(1); // trop tôt : le manifest vient d'être relu
    now = 61_000;
    await watcher.report(notFound());
    expect(fetches).toBe(2);
    expect(received).toEqual([]); // mêmes données : rien ne change
  });

  it('une relecture en échec ne bloque pas la suivante', async () => {
    const { current, old } = manifests();
    let now = 0;
    let fail = true;
    const received: Manifest[] = [];
    const watcher = new NewDataWatcher(
      old,
      async () => {
        if (fail) throw new TypeError('Failed to fetch');
        return current;
      },
      (manifest) => received.push(manifest),
      60_000,
      () => now,
    );
    await watcher.report(notFound());
    fail = false;
    now = 61_000;
    await watcher.report(notFound());
    expect(received).toEqual([current]);
  });

  it('de bout en bout : l\'archive annoncée a disparu, les tuiles se lisent dans la nouvelle', async () => {
    const { current, old } = manifests();
    const source = new FlakySource(FILE, readFixture(`synthetique/${FILE}`));
    const errors: unknown[] = [];
    // Le serveur ne connaît plus que l'archive de la nouvelle publication.
    const read = createArchiveReader((file) => {
      if (file !== FILE) return new PMTiles({ getKey: () => file, getBytes: async () => Promise.reject(notFound()) });
      return new PMTiles(source);
    }, (error) => errors.push(error));
    let store = new TileStore(old, read, decodeWithJs);
    const watcher = new NewDataWatcher(old, async () => current, (manifest) => {
      store = new TileStore(manifest, read, decodeWithJs);
    });
    await expect(store.get(12, 2116, 1479)).rejects.toThrow('404');
    expect(errors).toHaveLength(1);
    await watcher.report(errors[0]);
    expect(store.manifest).toBe(current);
    expect(await store.get(12, 2116, 1479)).not.toBeNull();
  });
});
