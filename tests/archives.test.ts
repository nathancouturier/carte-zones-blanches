import { PMTiles } from 'pmtiles';
import { describe, expect, it } from 'vitest';
import { createArchiveReader } from '../src/coverage/archives';
import { decodeWithJs } from '../src/coverage/decode';
import { parseManifest } from '../src/coverage/manifest';
import { TileStore, type ArchiveReader } from '../src/coverage/store';
import { sampleCoverage } from '../src/gpx/analyze';
import type { Sample } from '../src/gpx/resample';
import { FlakySource, readFixture, readJsonFixture, sampleManifest } from './helpers';

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

/** Issue d'une promesse au bout de « ms » millisecondes. */
function outcome(promise: Promise<unknown>, ms: number): Promise<'résolue' | 'rejetée' | 'en attente'> {
  return Promise.race([
    promise.then(
      () => 'résolue' as const,
      () => 'rejetée' as const,
    ),
    new Promise<'en attente'>((resolve) => setTimeout(() => resolve('en attente'), ms)),
  ]);
}

describe('lectures qui calent', () => {
  const samples: Sample[] = [{ lon: 6.08, lat: 44.56, ele: null, dist: 0, seg: 0 }];

  it('une lecture sans réponse échoue au bout du délai, et une nouvelle tentative relit vraiment', async () => {
    let reads = 0;
    const silent: ArchiveReader = () => {
      reads++;
      return new Promise<ArrayBuffer | undefined>(() => undefined);
    };
    const store = new TileStore(sampleManifest(), silent, decodeWithJs, 160, 40);
    // L'analyse d'un tracé ne reste pas figée : elle échoue, l'interface peut proposer de relancer.
    expect(await outcome(sampleCoverage(samples, store), 400)).toBe('rejetée');
    expect(reads).toBe(1);
    // « Relancer l'analyse » refait une vraie lecture au lieu d'attendre la requête figée.
    expect(await outcome(sampleCoverage(samples, store), 400)).toBe('rejetée');
    expect(reads).toBe(2);
  });

  it('une archive dont la connexion a calé redevient lisible une fois le réseau revenu', async () => {
    const { source, opened, read } = flakyArchive();
    const manifest = parseManifest(readJsonFixture('synthetique/manifest.json'));
    const store = new TileStore(manifest, read, decodeWithJs, 160, 40);
    source.stalled = true; // la requête de l'en-tête ne revient jamais
    expect(await outcome(store.get(12, 2116, 1479), 400)).toBe('rejetée');
    source.stalled = false;
    expect(await store.get(12, 2116, 1479)).not.toBeNull();
    expect(opened()).toBe(2); // l'instance dont l'en-tête est resté en attente est abandonnée
  });

  it('« Relancer » n\'attend pas une lecture restée en suspens : il relit vraiment', async () => {
    const { source, opened, read } = flakyArchive();
    const manifest = parseManifest(readJsonFixture('synthetique/manifest.json'));
    const store = new TileStore(manifest, read, decodeWithJs);
    source.stalled = true;
    const stuck = store.get(12, 2116, 1479); // lecture lancée pendant que la connexion cale
    expect(await outcome(stuck, 50)).toBe('en attente');
    source.stalled = false; // le réseau revient, l'utilisateur relance
    store.restart();
    read.reset();
    expect(await outcome(store.get(12, 2116, 1479), 400)).toBe('résolue');
    expect(opened()).toBe(2);
  });

  it('transmet au lecteur un signal déclenché au bout du délai', async () => {
    let received: AbortSignal | undefined;
    const store = new TileStore(sampleManifest(), (_file, _z, _x, _y, signal) => {
      received = signal;
      return new Promise<ArrayBuffer | undefined>(() => undefined);
    }, decodeWithJs, 160, 30);
    await expect(store.get(5, 16, 11)).rejects.toThrow();
    expect(received?.aborted).toBe(true);
  });
});
