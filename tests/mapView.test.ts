// La carte (MapView) sur une fausse carte MapLibre : cadrages, style de fond, position.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { FakeElement, FakeMap } from './fakeMaplibre';

vi.mock('maplibre-gl', async () => (await import('./fakeMaplibre')).fakeMaplibreModule);
vi.mock('maplibre-gl/dist/maplibre-gl-worker.mjs?url', () => ({ default: 'worker.mjs' }));

const { centerOffset, MapView } = await import('../src/map/mapView');

function creerCarte() {
  const view = new MapView({
    container: new FakeElement() as unknown as HTMLElement,
    labels: () => ({}),
    onMoveEnd: () => undefined,
    onLocateError: () => undefined,
    onStyleFallback: () => undefined,
  });
  return { view, map: FakeMap.last! };
}

beforeEach(() => {
  vi.stubGlobal('document', { createElement: () => new FakeElement() });
});
afterEach(() => vi.unstubAllGlobals());

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
