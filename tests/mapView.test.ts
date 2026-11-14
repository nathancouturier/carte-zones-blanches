// La carte (MapView) sur une fausse carte MapLibre : cadrages, style de fond, position.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { FakeElement, FakeMap, FakeMarker, type FakeStyle } from './fakeMaplibre';

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

describe('Ma position sur la carte (carte-5)', () => {
  /** Géolocalisation du navigateur simulée : positions envoyées à la demande. */
  function gps() {
    const rappels: PositionCallback[] = [];
    vi.stubGlobal('navigator', { geolocation: { watchPosition: (succes: PositionCallback) => rappels.push(succes), clearWatch: () => undefined } });
    return (lat: number, lon: number, accuracy = 30) => rappels.forEach((r) => r({ coords: { latitude: lat, longitude: lon, accuracy } } as GeolocationPosition));
  }
  const reperes = () => [...FakeMarker.live].map((m) => m.element.className);
  const marges = { top: 84, right: 56, bottom: 500, left: 40 };

  it('dessine le point et le cercle de précision, centre la carte une fois, puis le point suit sans la déplacer', async () => {
    FakeMarker.live.clear();
    const envoyer = gps();
    const { view, map } = creerCarte({ padding: () => marges });
    const appui = view.locate();
    envoyer(44.9, 6.42, 30);
    await appui;
    expect(reperes()).toEqual(['maplibregl-user-location-accuracy-circle', 'maplibregl-user-location-dot']);
    expect(map.moves).toHaveLength(1);
    // Le cercle de précision est cadré dans la partie libre ; fitBounds ne garde pas cette marge.
    expect(map.moves[0]).toMatchObject({ kind: 'fitBounds', options: { padding: marges, maxZoom: 15 } });
    envoyer(44.901, 6.421, 30);
    envoyer(44.902, 6.422, 12);
    expect(map.moves).toHaveLength(1);
    const point = [...FakeMarker.live].find((m) => m.element.className.includes('dot'))!;
    expect(point.lngLat).toEqual([6.422, 44.902]);
    const cercle = [...FakeMarker.live].find((m) => m.element.className.includes('circle'))!;
    expect(cercle.element.style.width).toMatch(/^\d+px$/);
  });

  it('un cadrage du site pendant l\'attente du GPS n\'est pas annulé par la position qui arrive', async () => {
    FakeMarker.live.clear();
    const envoyer = gps();
    const { view, map } = creerCarte({ padding: () => marges });
    const appui = view.locate();
    view.fitBounds([6.4, 44.8, 6.5, 44.95], marges); // import d'un GPX pendant que le GPS cherche
    envoyer(44.9, 6.42);
    await appui;
    expect(map.moves.map((m) => m.kind)).toEqual(['fitBounds']);
    expect(map.moves[0].options).toMatchObject({ maxZoom: 15, duration: 600 }); // celui du tracé
    expect(reperes()).toContain('maplibregl-user-location-dot');
  });
});

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
