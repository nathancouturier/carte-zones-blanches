import { describe, expect, it } from 'vitest';
import {
  autoBasemap,
  autoBasemapForView,
  BASEMAP_ORDER,
  BASEMAPS,
  ESTIMATED_CREDIT,
  HILLSHADE,
  isBasemapChoice,
  OSM_COPYRIGHT_URL,
  type Credit,
} from '../src/map/basemaps';
import { buildStyle, COVERAGE_LAYER } from '../src/map/style';
import { EMPTY_COLLECTION, trackToGeoJson, zoneToGeoJson } from '../src/map/trackGeojson';
import { mergePlaces, parseIgnCompletion, parsePhoton, type Place } from '../src/search/geocode';
import type { Sample } from '../src/gpx/resample';

describe('recherche de lieux', () => {
  it('lit la réponse de l\'autocomplétion IGN', () => {
    const places = parseIgnCompletion({
      status: 'OK',
      results: [
        { x: 6.405134, y: 45.035403, country: 'PositionOfInterest', names: ['Col du Lautaret'], city: 'Le Monêtier-les-Bains', zipcode: '05220', kind: 'col', fulltext: 'Col du Lautaret, 05220 Le Monêtier-les-Bains' },
        { x: 5.891852, y: 45.57442, country: 'StreetAddress', city: 'Chambéry', kind: 'street', zipcode: '73000', street: 'Rue du Lautaret', fulltext: 'Rue du Lautaret, 73000 Chambéry' },
        { fulltext: 'sans coordonnées' },
      ],
    });
    expect(places).toHaveLength(2);
    expect(places[0]).toMatchObject({ label: 'Col du Lautaret', detail: 'col, 05220 Le Monêtier-les-Bains', lon: 6.405134, lat: 45.035403, source: 'ign' });
    expect(places[1]).toMatchObject({ label: 'Rue du Lautaret, 73000 Chambéry', zoom: 16 });
    expect(parseIgnCompletion(null)).toEqual([]);
    expect(parseIgnCompletion({ results: 'x' })).toEqual([]);
  });

  it('lit la réponse de Photon et écarte la France', () => {
    const payload = {
      features: [
        { properties: { name: 'Zermatt', county: 'Visp', state: 'Valais', country: 'Suisse', countrycode: 'CH', type: 'city', extent: [7.57, 46.06, 7.9, 45.91] }, geometry: { coordinates: [7.749, 46.021] } },
        { properties: { name: 'Chamonix', country: 'France', countrycode: 'FR', type: 'city' }, geometry: { coordinates: [6.87, 45.92] } },
        { properties: { country: 'Italie' }, geometry: { coordinates: [7, 45] } },
      ],
    };
    const places = parsePhoton(payload, 'FR');
    expect(places).toHaveLength(1);
    expect(places[0]).toMatchObject({ label: 'Zermatt', detail: 'Visp, Valais, Suisse', source: 'osm', zoom: 12.5 });
    expect(places[0].bbox).toEqual([7.57, 45.91, 7.9, 46.06]); // ouest, sud, est, nord
    expect(parsePhoton(payload)).toHaveLength(2);
  });

  it('met en premier les résultats du pays où se trouve la carte', () => {
    const make = (label: string, source: 'ign' | 'osm'): Place => ({ label, detail: '', lon: 0, lat: 0, zoom: 12, source });
    const france = ['a', 'b', 'c', 'd', 'e', 'f', 'g'].map((l) => make(l, 'ign'));
    const abroad = ['x', 'y', 'z'].map((l) => make(l, 'osm'));
    expect(mergePlaces(france, abroad, false, 6).map((p) => p.label)).toEqual(['a', 'b', 'c', 'd', 'x', 'y']);
    expect(mergePlaces(france, abroad, true, 6).map((p) => p.label)).toEqual(['x', 'y', 'z', 'a', 'b', 'c']);
    expect(mergePlaces(france, [], false, 6)).toHaveLength(6);
    expect(mergePlaces([], abroad, false, 6).map((p) => p.label)).toEqual(['x', 'y', 'z']);
  });
});

describe('fonds de carte et style', () => {
  it('choisit le fond national en mode Auto', () => {
    expect(autoBasemap('FR')).toBe('ign-classique');
    expect(autoBasemap('CH')).toBe('swisstopo');
    expect(autoBasemap('ES')).toBe('ign-es');
    expect(autoBasemap('IT')).toBe('osm');
    expect(autoBasemap('AD')).toBe('osm');
    expect(autoBasemap(null)).toBeNull();
    // Pour la vue : le pays au centre, sinon le pays le plus présent autour, sinon OpenStreetMap (ui-10).
    expect(autoBasemapForView('CH', ['FR', 'FR', 'FR'])).toBe('swisstopo');
    expect(autoBasemapForView(null, ['FR', 'ES', 'ES', null, 'FR', 'ES'])).toBe('ign-es');
    expect(autoBasemapForView(null, [null, null])).toBe('osm');
    expect(autoBasemapForView(null, [])).toBe('osm');
    expect(isBasemapChoice('auto')).toBe(true);
    expect(isBasemapChoice('ortho')).toBe(true);
    expect(isBasemapChoice('google')).toBe(false);
    expect(BASEMAP_ORDER.every((id) => BASEMAPS[id].id === id)).toBe(true);
    for (const id of BASEMAP_ORDER) {
      const b = BASEMAPS[id];
      const tiles = b.kind === 'raster' ? b.tiles : [b.styleUrl, ...b.fallback.tiles];
      expect(tiles.every((u) => u.startsWith('https://'))).toBe(true);
    }
  });

  it('donne les mentions des fonds mot pour mot, avec leurs liens (carte-4)', () => {
    const texte = (credit: Credit): string => credit.map((part) => part.text).join('');
    const liens = (credit: Credit): Record<string, string> => Object.fromEntries(credit.filter((p) => p.href).map((p) => [p.text, p.href!]));
    for (const id of ['ign-classique', 'ign-standard', 'ortho'] as const) {
      expect(texte(BASEMAPS[id].attribution)).toBe('© IGN');
      expect(liens(BASEMAPS[id].attribution)).toEqual({ '© IGN': 'https://cartes.gouv.fr/cgu/' });
    }
    expect(HILLSHADE.attribution).toBe(BASEMAPS['ign-classique'].attribution);
    expect(texte(BASEMAPS.swisstopo.attribution)).toBe('©swisstopo');
    expect(liens(BASEMAPS.swisstopo.attribution)).toEqual({ '©swisstopo': 'https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices' });
    expect(texte(BASEMAPS['ign-es'].attribution)).toBe('CC BY 4.0 ign.es');
    expect(liens(BASEMAPS['ign-es'].attribution)).toEqual({ 'ign.es': 'https://www.ign.es' });
    // OpenTopoMap : sa mention, et la forme courte admise en pied de carte, avec les mêmes liens.
    const osm = BASEMAPS.osm;
    expect(texte(osm.attribution)).toBe('Kartendaten: © OpenStreetMap-Mitwirkende, SRTM | Kartendarstellung: © OpenTopoMap (CC-BY-SA)');
    expect(texte(osm.shortAttribution!)).toBe('© OpenStreetMap, SRTM | © OpenTopoMap (CC-BY-SA)');
    const attendus = { OpenStreetMap: 'https://openstreetmap.org/copyright', OpenTopoMap: 'http://opentopomap.org', 'CC-BY-SA': 'https://creativecommons.org/licenses/by-sa/3.0/' };
    expect(liens(osm.attribution)).toEqual(attendus);
    expect(liens(osm.shortAttribution!)).toEqual(attendus);
    // Zones estimées : le crédit d'OpenCellID.
    expect(texte(ESTIMATED_CREDIT)).toBe('Cell tower data from OpenCellID, licensed under CC BY-SA 4.0');
    expect(liens(ESTIMATED_CREDIT)).toEqual({ OpenCellID: 'https://opencellid.org', 'CC BY-SA 4.0': 'https://creativecommons.org/licenses/by-sa/4.0/' });
    expect(OSM_COPYRIGHT_URL).toBe('https://www.openstreetmap.org/copyright');
  });

  const coverage = { tilesUrl: 'couverture://{z}/{x}/{y}', minzoom: 0, maxzoom: 12, bounds: [-5, 41, 10, 51] as [number, number, number, number], opacity: 0.6 };

  it('place la couche réseau juste avant la première couche de libellés d\'un style vectoriel', () => {
    const vectorStyle = {
      version: 8 as const,
      glyphs: 'https://exemple.test/{fontstack}/{range}.pbf',
      sprite: 'https://exemple.test/sprite',
      sources: { plan_ign: { type: 'vector' as const, tiles: ['https://exemple.test/{z}/{x}/{y}.pbf'] } },
      layers: [
        { id: 'fond', type: 'fill' as const, source: 'plan_ign', 'source-layer': 'a' },
        { id: 'courbes', type: 'line' as const, source: 'plan_ign', 'source-layer': 'b' },
        { id: 'cotes', type: 'symbol' as const, source: 'plan_ign', 'source-layer': 'c' },
        { id: 'routes', type: 'line' as const, source: 'plan_ign', 'source-layer': 'd' },
        { id: 'noms', type: 'symbol' as const, source: 'plan_ign', 'source-layer': 'e' },
      ],
    };
    const style = buildStyle({ basemap: 'ign-classique', vectorStyle, hillshade: true, coverage, track: EMPTY_COLLECTION, zone: EMPTY_COLLECTION });
    const ids = style.layers.map((l) => l.id);
    expect(ids).toEqual(['fond-uni', 'fond', 'courbes', 'estompage', COVERAGE_LAYER, 'cotes', 'routes', 'noms', 'zone-halo', 'zone-jaune', 'trace-lisere', 'trace-couleur']);
    const layer = style.layers.find((l) => l.id === COVERAGE_LAYER)!;
    expect(layer.paint).toMatchObject({ 'raster-resampling': 'nearest', 'raster-opacity': 0.6 });
    expect(style.glyphs).toBe(vectorStyle.glyphs);
    expect(style.sources.couverture).toMatchObject({ type: 'raster', tileSize: 256, maxzoom: 12, tiles: ['couverture://{z}/{x}/{y}'] });
  });

  it('bâtit un style raster, avec ou sans couche réseau', () => {
    const style = buildStyle({ basemap: 'swisstopo', vectorStyle: null, hillshade: false, coverage, track: EMPTY_COLLECTION, zone: EMPTY_COLLECTION });
    expect(style.layers.map((l) => l.id)).toEqual(['fond-uni', 'fond', COVERAGE_LAYER, 'zone-halo', 'zone-jaune', 'trace-lisere', 'trace-couleur']);
    expect(style.sources.fond).toMatchObject({ type: 'raster', maxzoom: 18 });
    const bare = buildStyle({ basemap: 'osm', vectorStyle: null, hillshade: false, coverage: null, track: EMPTY_COLLECTION, zone: EMPTY_COLLECTION });
    expect(bare.layers.some((l) => l.id === COVERAGE_LAYER)).toBe(false);
    // Style vectoriel injoignable : repli sur le Plan IGN en images.
    const fallback = buildStyle({ basemap: 'ign-classique', vectorStyle: null, hillshade: false, coverage: null, track: EMPTY_COLLECTION, zone: EMPTY_COLLECTION });
    expect((fallback.sources.fond as { tiles: string[] }).tiles[0]).toContain('GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2');
  });

  it('découpe le tracé en portions de même couverture, sans trou', () => {
    const samples: Sample[] = [0, 1, 2, 3, 4, 5].map((i) => ({ lon: 6 + i * 0.001, lat: 45, ele: null, dist: i * 20, seg: i < 4 ? 0 : 1 }));
    const fc = trackToGeoJson(samples, new Uint8Array([3, 3, 0, 0, 0, 2]));
    expect(fc.features.map((f) => f.properties?.c)).toEqual([3, 0, 0]);
    const coords = fc.features.map((f) => (f.geometry as GeoJSON.LineString).coordinates.length);
    expect(coords).toEqual([3, 2, 2]); // la première portion va jusqu'au point où la couleur change
    expect(trackToGeoJson(samples, null).features).toHaveLength(2); // sans analyse : une ligne par segment
    expect(zoneToGeoJson(samples, null)).toBe(EMPTY_COLLECTION);
  });
});
