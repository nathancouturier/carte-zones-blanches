// Mode hors ligne vu de l'application : la vraie classe App, avec une carte simulée,
// une Cache API factice et un faux réseau. Le Service Worker est imité pour le
// manifest : quand le réseau manque ou ne répond pas, il sert la copie enregistrée
// avec le tracé (public/sw.js).

import { DOMParser } from '@xmldom/xmldom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { keyOf, makeCaches, type FakeCaches } from './fakeCaches';
import { readFixture, readJsonFixture } from './helpers';

const map = vi.hoisted(() => ({ view: { lon: 6.03, lat: 44.58, zoom: 12 }, styles: [] as string[] }));

vi.mock('maplibre-gl', () => ({ addProtocol: () => undefined }));
vi.mock('../src/map/mapView', () => ({
  MapView: class {
    async setStyleInputs(inputs: { basemap: string }): Promise<void> {
      map.styles.push(inputs.basemap);
    }
    currentVectorStyle(): null {
      return null;
    }
    refreshCoverage(): void {}
    setCoverageOpacity(): void {}
    setTrack(): void {}
    setZone(): void {}
    setEndpoints(): void {}
    setCursor(): void {}
    fitBounds(): void {}
    flyTo(): void {}
    locate(): void {}
    viewSamplePoints(): { lon: number; lat: number }[] {
      return [{ lon: map.view.lon, lat: map.view.lat }];
    }
    dataZoom(min: number, max: number): number {
      return Math.max(min, Math.min(max, Math.round(map.view.zoom + 1)));
    }
    updateLabels(): void {}
  },
}));

const ORIGIN = 'https://exemple.github.io';
const PAGE = `${ORIGIN}/carte-zones-blanches/`;
const ARCHIVE_A = 'couverture-20261113-00.pmtiles';
const ARCHIVE_B = 'couverture-20261205-0900-00.pmtiles';
const pmBytes = readFixture(`synthetique/${ARCHIVE_A}`);
const manifestA = readJsonFixture<Record<string, unknown>>('synthetique/manifest.json');
/** Édition suivante des données : nouvelle archive (mêmes octets ici), nouveau trimestre. */
const manifestB = (() => {
  const countries = structuredClone(manifestA.countries) as { sources: { date: string }[] }[];
  countries[0].sources[0].date = '2026-T3';
  return { ...manifestA, generated: '2026-12-05', archives: [{ file: ARCHIVE_B, minzoom: 0, maxzoom: 12 }], countries };
})();

const net = {
  /** up : tout répond ; down : plus de réseau ; hang : « en ligne », mais rien ne revient. */
  mode: 'up' as 'up' | 'down' | 'hang',
  /** Mode des archives PMTiles seules, s'il diffère (coupure pendant la lecture par exemple). */
  pmtiles: null as null | 'up' | 'down' | 'hang',
  manifest: manifestA as unknown,
  pmCalls: 0,
};
const nav = { onLine: true, serviceWorker: {}, storage: { persist: async () => true }, userAgent: 'test' };
let caches: FakeCaches;
let ls: Map<string, string>;

function serveRange(init?: RequestInit): Response {
  const range = new Headers(init?.headers).get('range') ?? '';
  const m = /bytes=(\d+)-(\d+)/.exec(range)!;
  const start = Number(m[1]);
  const end = Math.min(Number(m[2]), pmBytes.length - 1);
  const slice = new Uint8Array(pmBytes.subarray(start, end + 1));
  return new Response(slice, { status: 206, headers: { 'content-length': String(slice.length), 'content-range': `bytes ${start}-${end}/${pmBytes.length}` } });
}

const never = (): Promise<Response> => new Promise<Response>(() => undefined);

beforeEach(() => {
  map.view = { lon: 6.03, lat: 44.58, zoom: 12 };
  map.styles.length = 0;
  net.mode = 'up';
  net.pmtiles = null;
  net.manifest = manifestA;
  net.pmCalls = 0;
  nav.onLine = true;
  caches = makeCaches();
  ls = new Map();
  vi.stubGlobal('caches', caches);
  vi.stubGlobal('navigator', nav);
  vi.stubGlobal('location', { href: PAGE, origin: ORIGIN });
  vi.stubGlobal('localStorage', { getItem: (k: string) => ls.get(k) ?? null, setItem: (k: string, v: string) => ls.set(k, v), removeItem: (k: string) => ls.delete(k) });
  vi.stubGlobal('DOMParser', DOMParser);
  vi.stubGlobal('fetch', async (input: unknown, init?: RequestInit) => {
    const url = keyOf(input);
    if (url.endsWith('/data/manifest.json')) {
      if (net.mode === 'up') return new Response(JSON.stringify(net.manifest), { status: 200 });
      // Le Service Worker sert alors la copie enregistrée avec le tracé, s'il y en a une.
      const copy = await (await caches.open('czb-hors-ligne-v1')).match(new URL(url, PAGE).href);
      if (copy) return copy;
      if (net.mode === 'hang') return never();
      throw new TypeError('Failed to fetch');
    }
    if (url.includes('.pmtiles')) {
      net.pmCalls++;
      const mode = net.pmtiles ?? net.mode;
      if (mode === 'hang') return never();
      if (mode === 'down') throw new TypeError('Failed to fetch');
      return url.includes(ARCHIVE_A) || url.includes(ARCHIVE_B) ? serveRange(init) : new Response('', { status: 404 });
    }
    if (net.mode === 'hang') return never();
    if (net.mode === 'down') throw new TypeError('Failed to fetch');
    return new Response('', { status: 404 });
  });
});
afterEach(() => vi.unstubAllGlobals());

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

function gpxFile(name: string, lat0: number, lon0: number): File {
  const points = Array.from({ length: 30 }, (_, i) => `<trkpt lat="${(lat0 + i * 0.002).toFixed(5)}" lon="${(lon0 + i * 0.002).toFixed(5)}"><ele>${1500 + i * 10}</ele></trkpt>`);
  const xml = `<?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>${name}</name><trkseg>${points.join('')}</trkseg></trk></gpx>`;
  return { name: `${name}.gpx`, size: xml.length, arrayBuffer: async () => new TextEncoder().encode(xml).buffer } as unknown as File;
}
const essai = gpxFile('Essai', 44.55, 6.0);
/** Un autre tracé, à une vingtaine de kilomètres : hors du couloir du premier. */
const ailleurs = gpxFile('Ailleurs', 44.35, 5.7);

async function newApp() {
  const { App } = await import('../src/app');
  const { Store, initialState } = await import('../src/state');
  const app = new App(new Store(initialState()), {} as HTMLElement);
  await app.start();
  await wait(300); // updateView part 200 ms après le démarrage
  return app;
}

/** Première session, en ligne : le tracé est importé et préparé pour le hors ligne. */
async function prepared() {
  const app = await newApp();
  await app.importGpx(essai);
  expect(app.state.track?.analysis).not.toBeNull();
  await app.prepareOffline();
  expect(app.state.offline.status).toBe('idle');
  expect(app.state.offline.info).not.toBeNull();
  return app;
}

describe('hors ligne, dans l\'application', () => {
  it('range les tuiles de couverture sous le nom de leur archive (hl-5)', async () => {
    await prepared();
    const keys = caches.urls('czb-hors-ligne-v1').filter((u) => u.includes('/hors-ligne/couverture/'));
    expect(keys.length).toBeGreaterThan(0);
    expect(keys.every((u) => u.includes(`/hors-ligne/couverture/${ARCHIVE_A}/`))).toBe(true);
  });

  it('ne décode jamais les tuiles d\'une édition avec le manifest d\'une autre (hl-5)', async () => {
    await prepared();
    // Release suivante, vue en ligne ; puis le réseau tombe pendant la lecture des archives.
    net.manifest = manifestB;
    const app = await newApp();
    expect(app.state.manifest?.generated).toBe('2026-12-05');
    net.pmtiles = 'down';
    await app.importGpx(essai);
    // Les tuiles enregistrées sont celles de l'archive A : elles ne servent pas avec le manifest B.
    expect(app.state.track?.analysis ?? null).toBeNull();
    expect(app.state.trackError?.key).toBe('gpx.error.analysis');
  });

  it('sans réseau, relit le tracé avec le manifest de sa préparation, même après une visite plus récente (hl-5)', async () => {
    await prepared();
    net.manifest = manifestB;
    await newApp(); // visite en ligne de la nouvelle édition
    net.mode = 'down';
    nav.onLine = false;
    const app = await newApp(); // recharge tout seul le tracé enregistré
    await wait(300);
    expect(app.state.manifest?.generated).toBe(manifestA.generated);
    expect(app.state.track?.analysis).not.toBeNull();
    expect(app.reportAsText()).toContain('T2 2026');
  });

  it('par réseau faible, recharge le tracé et l\'analyse avec les tuiles enregistrées, sans attendre le réseau (hl-4)', async () => {
    await prepared();
    net.mode = 'hang'; // le téléphone se croit en ligne
    const app = await newApp();
    await wait(500);
    expect(app.state.track?.parsed.name).toBe('Essai');
    expect(app.state.track?.analysis).not.toBeNull();
  });

  it('après un démarrage hors ligne, l\'archive en ligne refonctionne quand le réseau revient (hl-3)', async () => {
    await prepared();
    net.mode = 'down';
    nav.onLine = false;
    map.view = { lon: 2.6, lat: 46.5, zoom: 5.2 }; // vue de départ : tuiles hors du couloir, lues en ligne
    const app = await newApp();
    await wait(300);
    expect(app.state.track?.analysis).not.toBeNull();
    nav.onLine = true;
    net.mode = 'up';
    const before = net.pmCalls;
    await app.importGpx(ailleurs);
    expect(app.state.trackError).toBeNull();
    expect(app.state.track?.analysis).not.toBeNull();
    expect(net.pmCalls).toBeGreaterThan(before);
  });
});
