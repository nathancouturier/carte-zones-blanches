import { PMTiles } from 'pmtiles';
import { describe, expect, it } from 'vitest';
import { createArchiveReader } from '../src/coverage/archives';
import { decodeWithJs } from '../src/coverage/decode';
import { parseManifest } from '../src/coverage/manifest';
import { TileStore } from '../src/coverage/store';
import { FlakySource, readFixture, readJsonFixture } from './helpers';

const FILE = 'couverture-20261113-00.pmtiles';

function flakyArchive(): { source: FlakySource; opened: () => number; read: ReturnType<typeof createArchiveReader> } {
  const source = new FlakySource(FILE, readFixture(`synthetique/${FILE}`));
  let count = 0;
  const read = createArchiveReader(() => {
    count++;
    return new PMTiles(source);
  });
  return { source, opened: () => count, read };
}

describe('lecture des archives PMTiles en ligne', () => {
  it('repart d\'une archive neuve après une coupure du réseau', async () => {
    const { source, opened, read } = flakyArchive();
    source.failures = 1; // la toute première lecture (l'en-tête) échoue
    await expect(read(FILE, 12, 2116, 1479)).rejects.toThrow('Failed to fetch');
    // pmtiles garde en cache la promesse rejetée de l'en-tête : sans instance neuve, plus rien ne passerait.
    const tile = await read(FILE, 12, 2116, 1479);
    expect(tile?.byteLength).toBeGreaterThan(0);
    expect(opened()).toBe(2);
    // L'instance neuve sert ensuite les lectures suivantes, sans en recréer.
    await read(FILE, 12, 2117, 1479);
    expect(opened()).toBe(2);
  });

  it('le magasin de tuiles retrouve les données après la coupure', async () => {
    const { source, read } = flakyArchive();
    const manifest = parseManifest(readJsonFixture('synthetique/manifest.json'));
    const store = new TileStore(manifest, read, decodeWithJs);
    source.failures = 1;
    await expect(store.get(12, 2116, 1479)).rejects.toThrow('Failed to fetch');
    const calls = source.calls;
    expect(await store.get(12, 2116, 1479)).not.toBeNull();
    expect(source.calls).toBeGreaterThan(calls); // le réseau a bien été rappelé
  });
});
