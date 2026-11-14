// La carte (MapView) sur une fausse carte MapLibre : cadrages, style de fond, position.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { FakeElement, FakeMap, type FakeStyle } from './fakeMaplibre';

vi.mock('maplibre-gl', async () => (await import('./fakeMaplibre')).fakeMaplibreModule);
vi.mock('maplibre-gl/dist/maplibre-gl-worker.mjs?url', () => ({ default: 'worker.mjs' }));
// Délai du style vectoriel raccourci pour les essais.
vi.mock('../src/config', async (original) => ({ ...(await original<typeof import('../src/config')>()), VECTOR_STYLE_TIMEOUT_MS: 100 }));

const { centerOffset, MapView } = await import('../src/map/mapView');
type Options = ConstructorParameters<typeof MapView>[0];

function creerCarte(options: Partial<Options> = {}) {
  const view = new MapView({
    container: new FakeElement() as unknown as HTMLElement,
    labels: () => ({}),
    onMoveEnd: () => undefined,
    onLocateError: () => undefined,
    onStyleFallback: () => undefined,
    ...options,
  });
  return { view, map: FakeMap.last! };
}

beforeEach(() => {
  vi.stubGlobal('document', { createElement: () => new FakeElement() });
});
afterEach(() => {
  vi.unstubAllGlobals();
  FakeMap.validate = () => [];
});

/** Style vectoriel réduit, au format de celui de l'IGN (source « plan_ign », libellés). */
const STYLE_IGN = {
  version: 8,
  glyphs: 'https://exemple.test/{fontstack}/{range}.pbf',
  sources: { plan_ign: { type: 'vector', tiles: ['https://exemple.test/{z}/{x}/{y}.pbf'] } },
  layers: [
    { id: 'routes', type: 'line', source: 'plan_ign', 'source-layer': 'a' },
    { id: 'noms', type: 'symbol', source: 'plan_ign', 'source-layer': 'b', layout: { 'text-field': '{nom}' } },
  ],
};

/** Faux réseau du style vectoriel : il répond après « delai » ms, ou jamais (il attend alors l'annulation). */
function styleServi(reponse: unknown, delai: number | null): void {
  vi.stubGlobal('fetch', (_url: string, init?: RequestInit) =>
    new Promise<Response>((resolve, reject) => {
      if (delai !== null) setTimeout(() => resolve(new Response(JSON.stringify(reponse), { status: 200 })), delai);
      init?.signal?.addEventListener('abort', () => reject(init.signal!.reason));
    }),
  );
}

const ENTREES = { hillshade: false, coverage: { minzoom: 0, maxzoom: 16, bounds: [-5, 41, 10, 51] as [number, number, number, number], opacity: 0.65 } };
const fond = (style: FakeStyle | undefined): string => {
  const source = style?.sources.fond as { tiles?: string[] } | undefined;
  if (source?.tiles?.[0].includes('PLANIGNV2')) return 'Plan IGN en images';
  return style && 'plan_ign' in style.sources ? 'Plan IGN vectoriel' : 'autre';
};
const attendre = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

describe('style du fond (carte-2)', () => {
  it('style lent : la couche réseau et le tracé s\'affichent tout de suite sur le Plan IGN en images, puis le délai passé, on le dit', async () => {
    styleServi(STYLE_IGN, null); // le style ne vient jamais
    const replis: string[] = [];
    const { view, map } = creerCarte({ onStyleFallback: (_id, raison) => replis.push(raison) });
    const application = view.setStyleInputs({ basemap: 'ign-classique', ...ENTREES });
    // Avant même la réponse : un style complet, avec la couverture et le tracé.
    expect(map.styles).toHaveLength(1);
    expect(fond(map.styles[0])).toBe('Plan IGN en images');
    expect(Object.keys(map.styles[0].sources)).toEqual(expect.arrayContaining(['couverture', 'trace', 'zone']));
    await application;
    expect(replis).toEqual(['unreachable']);
    expect(view.currentVectorStyle()).toBeNull();
  });

  it('style arrivé ensuite : il remplace la version en images, puis s\'applique sans attente', async () => {
    styleServi(STYLE_IGN, 20);
    const replis: string[] = [];
    const { view, map } = creerCarte({ onStyleFallback: (_id, raison) => replis.push(raison) });
    await view.setStyleInputs({ basemap: 'ign-classique', ...ENTREES });
    expect(map.styles.map(fond)).toEqual(['Plan IGN en images', 'Plan IGN vectoriel']);
    expect(map.styles[1].glyphs).toBe(STYLE_IGN.glyphs);
    await view.setStyleInputs({ basemap: 'ign-classique', ...ENTREES, hillshade: true });
    expect(map.styles.map(fond)).toEqual(['Plan IGN en images', 'Plan IGN vectoriel', 'Plan IGN vectoriel']);
    expect(replis).toEqual([]);
  });

  it('style refusé par MapLibre : retour à la version en images, dit une fois, sans nouvel essai', async () => {
    // Libellés sans « glyphs » : MapLibre refuse le style (validation) et la carte resterait grise.
    styleServi({ ...STYLE_IGN, glyphs: undefined }, 10);
    FakeMap.validate = (style) => (style.layers.some((l) => l.layout?.['text-field']) && !style.glyphs ? ['use of "text-field" requires a style "glyphs" property'] : []);
    const replis: string[] = [];
    const { view, map } = creerCarte({ onStyleFallback: (_id, raison) => replis.push(raison) });
    await view.setStyleInputs({ basemap: 'ign-standard', ...ENTREES });
    await attendre(10);
    expect(map.styles.map(fond)).toEqual(['Plan IGN en images', 'Plan IGN vectoriel', 'Plan IGN en images']);
    expect('glyphs' in map.styles[1]).toBe(false); // jamais « glyphs: undefined »
    expect(fond(map.style!)).toBe('Plan IGN en images');
    expect(replis).toEqual(['refused']);
    await view.setStyleInputs({ basemap: 'ign-standard', ...ENTREES, hillshade: true });
    expect(map.styles.map(fond).at(-1)).toBe('Plan IGN en images');
    expect(replis).toEqual(['refused']);
  });
});

describe('cadrages', () => {
  const marges = { top: 84, right: 56, bottom: 500, left: 40 };

  it('centre un lieu dans la partie libre de la carte par un décalage, jamais par une marge gardée (carte-1)', () => {
    const { view, map } = creerCarte();
    view.flyTo(6.4075, 44.9356, 14.5, marges);
    const vol = map.moves.at(-1)!;
    expect(vol.kind).toBe('flyTo');
    // Une marge (padding) passée à flyTo resterait dans la carte et fausserait tous les cadrages suivants.
    expect(vol.options.padding).toBeUndefined();
    expect(vol.options).toMatchObject({ center: [6.4075, 44.9356], zoom: 14.5, offset: [-8, -208] });
  });

  it('le décalage vise le milieu de la partie libre', () => {
    expect(centerOffset({ top: 0, right: 0, bottom: 0, left: 0 })).toEqual([0, 0]);
    // Panneau de 420 px à gauche (ordinateur) : le centre libre est 210 px plus à droite.
    expect(centerOffset({ top: 84, right: 56, bottom: 110, left: 476 })).toEqual([210, -13]);
  });
});
