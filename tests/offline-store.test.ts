// Données hors ligne : tuiles de couverture enregistrées, lecteur « copie locale d'abord ».

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { coverageTileKey, offlineOutdated, withStoredTiles, type OfflineInfo } from '../src/offline/manager';
import { makeCaches, type FakeCaches } from './fakeCaches';

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
  return { name: 'Essai', date: '2026-11-14T10:00:00Z', archives, generated: '2026-11-14', basemap: null, coverageTiles: 1, basemapTiles: 0, failed: 0 };
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
