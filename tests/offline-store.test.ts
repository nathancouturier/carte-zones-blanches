// Données hors ligne : tuiles de couverture enregistrées, lecteur « copie locale d'abord ».

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Sample } from '../src/gpx/resample';
import { BASEMAPS, type BasemapPack, type PreloadPolicy } from '../src/map/basemaps';
import { basemapGroups, coverageTileKey, offlineOutdated, prepareOffline, retryAfterMs, withStoredTiles, type BasemapJob, type OfflineInfo } from '../src/offline/manager';
import { keyOf, makeCaches, type FakeCaches } from './fakeCaches';
import { sampleManifest } from './helpers';

const ORIGIN = 'https://exemple.github.io';
const PAGE = `${ORIGIN}/carte-zones-blanches/`;
const BASE = '/carte-zones-blanches/';
let caches: FakeCaches;

beforeEach(() => {
  caches = makeCaches();
  vi.stubGlobal('caches', caches);
  vi.stubGlobal('location', { href: PAGE, origin: ORIGIN });
});
afterEach(() => vi.unstubAllGlobals());

function info(archives: string[]): OfflineInfo {
  return { name: 'Essai', date: '2026-11-14T10:00:00Z', complete: true, persisted: true, archives, generated: '2026-11-14', coverageTiles: 1, basemaps: [] };
}

describe('édition des données enregistrées', () => {
  it('signale un enregistrement fait avec d\'autres archives que celles du manifest', () => {
    const manifest = { archives: [{ file: 'couverture-A.pmtiles', minzoom: 0, maxzoom: 12 }] };
    expect(offlineOutdated(info(['couverture-A.pmtiles']), manifest)).toBe(false);
    expect(offlineOutdated(info(['couverture-B.pmtiles']), manifest)).toBe(true);
    expect(offlineOutdated(info(['couverture-A.pmtiles', 'couverture-A2.pmtiles']), manifest)).toBe(true);
    // Enregistrement d'une version précédente du site : édition inconnue.
    expect(offlineOutdated(info([]), manifest)).toBe(true);
  });
});

describe('lecture des tuiles de couverture, copie locale d\'abord', () => {
  const tile = new Uint8Array([1, 2, 3]).buffer;

  it('sert la tuile enregistrée de la même archive sans appeler le réseau, et elle seule', async () => {
    const cache = await caches.open('czb-hors-ligne-v1');
    await cache.put(coverageTileKey(BASE, 'couverture-A.pmtiles', 12, 2116, 1479), new Response(tile, { headers: { 'x-czb-vide': '0' } }));
    await cache.put(coverageTileKey(BASE, 'couverture-A.pmtiles', 12, 2117, 1479), new Response(new ArrayBuffer(0), { headers: { 'x-czb-vide': '1' } }));
    const online = vi.fn(async () => new Uint8Array([9]).buffer as ArrayBuffer);
    const read = withStoredTiles(BASE, online, (file) => file === 'couverture-A.pmtiles');
    expect(new Uint8Array((await read('couverture-A.pmtiles', 12, 2116, 1479))!)).toEqual(new Uint8Array([1, 2, 3]));
    expect(await read('couverture-A.pmtiles', 12, 2117, 1479)).toBeUndefined(); // tuile vide enregistrée
    expect(online).not.toHaveBeenCalled();
    // Hors du couloir, ou autre édition des données : le réseau.
    expect(new Uint8Array((await read('couverture-A.pmtiles', 12, 2000, 1400))!)).toEqual(new Uint8Array([9]));
    expect(new Uint8Array((await read('couverture-B.pmtiles', 12, 2116, 1479))!)).toEqual(new Uint8Array([9]));
    expect(online).toHaveBeenCalledTimes(2);
  });

  it('ne cherche rien en local pour une archive dont aucune tuile n\'est enregistrée', async () => {
    const open = vi.spyOn(caches, 'open');
    const read = withStoredTiles(BASE, async () => undefined, () => false);
    await read('couverture-A.pmtiles', 12, 2116, 1479);
    expect(open).not.toHaveBeenCalled();
  });
});

/** Points espacés de 20 m vers l'est. */
function line(lon0: number, lat: number, n: number): Sample[] {
  return Array.from({ length: n }, (_, i) => ({ lon: lon0 + i * 0.00026, lat, ele: null, dist: i * 20, seg: 0 }));
}

describe('fonds à enregistrer pour un tracé', () => {
  it('en mode Auto, le fond national de chaque pays traversé ; ailleurs, le fond OpenStreetMap', () => {
    const samples = line(6.8, 45.9, 10);
    const iso = ['FR', 'FR', null, 'CH', 'CH', 'IT', null, 'IT', 'FR', 'AD'];
    const groups = basemapGroups(samples, (i) => iso[i], 'auto', 'ign-classique');
    expect(groups.map((g) => [g.id, g.samples.length, g.countries.join()])).toEqual([
      ['ign-classique', 4, 'FR'], // le point hors données suit le pays qui le précède
      ['swisstopo', 2, 'CH'],
      ['osm', 4, 'IT,AD'],
    ]);
  });

  it('un point hors données au départ suit le pays qui le suit ; sans pays connu, le fond affiché', () => {
    const samples = line(6.8, 45.9, 3);
    expect(basemapGroups(samples, (i) => [null, 'CH', 'CH'][i], 'auto', 'ign-classique').map((g) => g.id)).toEqual(['swisstopo']);
    expect(basemapGroups(samples, () => null, 'auto', 'ortho').map((g) => [g.id, g.samples.length])).toEqual([['ortho', 3]]);
  });

  it('hors mode Auto, le fond choisi pour tout le tracé', () => {
    const samples = line(6.8, 45.9, 3);
    expect(basemapGroups(samples, () => 'CH', 'ign-es', 'ign-es').map((g) => [g.id, g.samples.length, g.countries.length])).toEqual([['ign-es', 3, 0]]);
  });

  it('suit les règles du projet pour chaque fournisseur', () => {
    const rule = (id: keyof typeof BASEMAPS): Pick<PreloadPolicy, 'allowed' | 'maxTiles' | 'concurrency' | 'perSecond'> => {
      const { allowed, maxTiles, concurrency, perSecond } = BASEMAPS[id].offline;
      return { allowed, maxTiles, concurrency, perSecond };
    };
    expect(rule('ign-classique')).toEqual({ allowed: true, maxTiles: 900, concurrency: 4, perSecond: 0 });
    expect(rule('ortho')).toEqual({ allowed: true, maxTiles: 600, concurrency: 4, perSecond: 0 });
    expect(rule('swisstopo')).toEqual({ allowed: true, maxTiles: 600, concurrency: 2, perSecond: 2 });
    expect(rule('ign-es')).toEqual({ allowed: true, maxTiles: 600, concurrency: 2, perSecond: 5 });
    expect(rule('osm').allowed).toBe(false);
  });
});

describe('attente demandée par le serveur (Retry-After)', () => {
  it('lit des secondes ou une date, et attend 5 s à défaut', () => {
    const now = Date.parse('2026-11-14T12:00:00Z');
    expect(retryAfterMs('7', now)).toBe(7000);
    expect(retryAfterMs('0', now)).toBe(0);
    expect(retryAfterMs('Sat, 14 Nov 2026 12:00:30 GMT', now)).toBe(30_000);
    expect(retryAfterMs(null, now)).toBe(5000);
    expect(retryAfterMs('bientôt', now)).toBe(5000);
  });
});

describe('enregistrement des fonds, au rythme de chaque fournisseur', () => {
  type Reply = (url: string, attempt: number) => Response;
  let requests: { url: string; at: number }[];
  let inFlight: number;
  let maxInFlight: number;

  function stubNetwork(reply: Reply = () => new Response('tuile')): void {
    requests = [];
    inFlight = 0;
    maxInFlight = 0;
    const attempts = new Map<string, number>();
    vi.stubGlobal('fetch', async (input: unknown) => {
      const url = keyOf(input);
      requests.push({ url, at: Date.now() });
      attempts.set(url, (attempts.get(url) ?? 0) + 1);
      inFlight++;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await new Promise((r) => setTimeout(r, 5));
      inFlight--;
      return reply(url, attempts.get(url)!);
    });
  }

  beforeEach(() => {
    const store = new Map<string, string>();
    vi.stubGlobal('localStorage', { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => store.set(k, v), removeItem: (k: string) => store.delete(k) });
    vi.stubGlobal('navigator', { storage: { persist: async () => true } });
  });

  function pack(id: BasemapPack['id'], policy: Partial<PreloadPolicy>, host = 'tuiles.test', bounds?: [number, number, number, number]): BasemapPack {
    return {
      id,
      policy: { allowed: true, maxTiles: 30, minZoom: 14, maxZoom: 16, concurrency: 2, perSecond: 0, ...policy },
      tileTemplates: [`https://${host}/{z}/{x}/{y}.png`],
      bounds,
      extraUrls: [],
    };
  }

  async function prepare(basemaps: BasemapJob[]): Promise<OfflineInfo> {
    return prepareOffline(BASE, {
      samples: line(7.0, 46.0, 120),
      trackName: 'Essai',
      gpxText: '<gpx/>',
      fileName: 'essai.gpx',
      manifest: sampleManifest(),
      readArchive: async () => undefined,
      basemaps,
      onProgress: () => undefined,
    });
  }

  it('respecte le plafond, les requêtes simultanées et le débit du fournisseur', async () => {
    stubNetwork();
    const samples = line(7.0, 46.0, 120);
    const info = await prepare([{ pack: pack('swisstopo', { maxTiles: 12, concurrency: 2, perSecond: 40 }), samples, countries: ['CH'] }]);
    expect(requests.length).toBeLessThanOrEqual(12);
    expect(maxInFlight).toBeLessThanOrEqual(2);
    const gaps = requests.slice(1).map((r, i) => r.at - requests[i].at);
    expect(Math.min(...gaps)).toBeGreaterThanOrEqual(20); // 40 requêtes par seconde au plus : 25 ms d'écart, à quelques ms près
    expect(info.basemaps).toEqual([{ id: 'swisstopo', countries: ['CH'], allowed: true, total: requests.length, stored: requests.length, tiles: requests.length }]);
    expect(info.complete).toBe(true);
  });

  it('sur 429, attend puis reprend ; après trois refus, abandonne ce fond et compte ce qui manque', async () => {
    stubNetwork((_url, attempt) => (attempt === 1 ? new Response('', { status: 429, headers: { 'retry-after': '0' } }) : new Response('tuile')));
    const samples = line(7.0, 46.0, 120);
    let info = await prepare([{ pack: pack('swisstopo', { maxTiles: 6 }), samples, countries: [] }]);
    expect(info.basemaps[0].stored).toBe(info.basemaps[0].total);
    expect(requests.length).toBe(info.basemaps[0].total * 2);

    stubNetwork(() => new Response('', { status: 503, headers: { 'retry-after': '0' } }));
    info = await prepare([{ pack: pack('ign-es', { maxTiles: 20, concurrency: 1 }, 'autre.test'), samples, countries: [] }]);
    expect(requests.length).toBe(3); // une tuile, trois essais, puis plus rien pour ce fond
    expect(info.basemaps[0]).toMatchObject({ allowed: true, stored: 0 });
    expect(info.basemaps[0].total).toBeGreaterThan(3);
    expect(info.complete).toBe(true);
  });

  it('ne demande rien à un fournisseur qui ne le permet pas, ni à tile.openstreetmap.org', async () => {
    stubNetwork();
    const samples = line(7.0, 46.0, 50);
    const info = await prepare([
      { pack: pack('osm', { allowed: false }, 'a.tile.opentopomap.org'), samples, countries: ['IT'] },
      { pack: pack('ortho', {}, 'tile.openstreetmap.org'), samples, countries: [] },
    ]);
    expect(requests).toEqual([]);
    expect(info.basemaps.map((r) => [r.id, r.allowed, r.total])).toEqual([
      ['osm', false, 0],
      ['ortho', false, 0],
    ]);
  });

  it('ne demande pas de tuiles hors de l\'emprise servie par le fournisseur', async () => {
    stubNetwork();
    const samples = line(7.0, 46.0, 50);
    const info = await prepare([{ pack: pack('hillshade', {}, 'tuiles.test', [-5.6, 41.2, 6.5, 51.3]), samples, countries: [] }]);
    expect(requests).toEqual([]);
    expect(info.basemaps[0]).toMatchObject({ id: 'hillshade', allowed: true, total: 0, tiles: 0 });
  });
});
