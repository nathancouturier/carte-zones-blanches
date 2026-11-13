// Construction du style MapLibre : le fond choisi, l'estompage, la couche
// réseau et le tracé GPX. Le style est rebâti à chaque changement de fond, ce
// qui garde toutes les couches en place.

import type {
  LayerSpecification,
  SourceSpecification,
  StyleSpecification,
} from 'maplibre-gl';
import { LEVEL_GOOD, LEVEL_LIMITED, LEVEL_NONE, LEVEL_VERY_GOOD } from '../coverage/codec';
import { LEVEL_SOLID } from '../coverage/render';
import { CLASS_OUTSIDE, CLASS_UNKNOWN } from '../gpx/analyze';
import { BASEMAPS, HILLSHADE, type BasemapId, type RasterSpec } from './basemaps';

export const COVERAGE_SOURCE = 'couverture';
export const COVERAGE_LAYER = 'couverture';
export const TRACK_SOURCE = 'trace';
export const ZONE_SOURCE = 'zone';
const BACKGROUND_COLOR = '#e9ecef';
export const OUTSIDE_COLOR = '#7a8794';

export interface CoverageLayerOptions {
  tilesUrl: string;
  minzoom: number;
  maxzoom: number;
  bounds: [number, number, number, number];
  opacity: number;
}

export interface StyleOptions {
  basemap: BasemapId;
  /** Style vectoriel IGN déjà téléchargé, quand le fond est vectoriel. */
  vectorStyle: StyleSpecification | null;
  hillshade: boolean;
  coverage: CoverageLayerOptions | null;
  track: GeoJSON.FeatureCollection;
  zone: GeoJSON.FeatureCollection;
}

const styleCache = new Map<string, Promise<StyleSpecification>>();

/** Télécharge un style vectoriel (une seule fois). */
export function loadVectorStyle(url: string): Promise<StyleSpecification> {
  let promise = styleCache.get(url);
  if (!promise) {
    promise = fetch(url)
      .then((response) => {
        if (!response.ok) throw new Error(`Style ${url} : HTTP ${response.status}`);
        return response.json() as Promise<StyleSpecification>;
      })
      .catch((error) => {
        styleCache.delete(url); // on réessaiera
        throw error;
      });
    styleCache.set(url, promise);
  }
  return promise;
}

function rasterSource(spec: RasterSpec): SourceSpecification {
  const source: SourceSpecification = {
    type: 'raster',
    tiles: spec.tiles,
    tileSize: spec.tileSize,
    minzoom: spec.minzoom,
    maxzoom: spec.maxzoom,
  };
  if (spec.bounds) source.bounds = spec.bounds;
  return source;
}

function overlayLayers(options: StyleOptions): LayerSpecification[] {
  const layers: LayerSpecification[] = [];
  if (options.hillshade) {
    layers.push({
      id: 'estompage',
      type: 'raster',
      source: 'estompage',
      paint: { 'raster-opacity': 0.45, 'raster-fade-duration': 0 },
    });
  }
  if (options.coverage) {
    layers.push({
      id: COVERAGE_LAYER,
      type: 'raster',
      source: COVERAGE_SOURCE,
      paint: {
        'raster-opacity': options.coverage.opacity,
        // Plus proche voisin : chaque pixel de donnée reste net, sans dégradé trompeur.
        'raster-resampling': 'nearest',
        'raster-fade-duration': 0,
      },
    });
  }
  return layers;
}

const TRACK_COLOR = [
  'match',
  ['get', 'c'],
  LEVEL_NONE,
  LEVEL_SOLID[LEVEL_NONE],
  LEVEL_LIMITED,
  LEVEL_SOLID[LEVEL_LIMITED],
  LEVEL_GOOD,
  LEVEL_SOLID[LEVEL_GOOD],
  LEVEL_VERY_GOOD,
  LEVEL_SOLID[LEVEL_VERY_GOOD],
  CLASS_OUTSIDE,
  OUTSIDE_COLOR,
  CLASS_UNKNOWN,
  OUTSIDE_COLOR,
  '#1f3a5f',
] as unknown as string;

function trackLayers(): LayerSpecification[] {
  const round = { 'line-cap': 'round', 'line-join': 'round' } as const;
  return [
    // Surbrillance de la zone blanche sélectionnée.
    {
      id: 'zone-halo',
      type: 'line',
      source: ZONE_SOURCE,
      layout: round,
      paint: { 'line-color': '#111827', 'line-width': 15, 'line-opacity': 0.9 },
    },
    {
      id: 'zone-jaune',
      type: 'line',
      source: ZONE_SOURCE,
      layout: round,
      paint: { 'line-color': '#ffd60a', 'line-width': 11 },
    },
    // Tracé : liseré blanc, puis couleur selon la couverture.
    {
      id: 'trace-lisere',
      type: 'line',
      source: TRACK_SOURCE,
      layout: round,
      paint: { 'line-color': '#ffffff', 'line-width': 7.5 },
    },
    {
      id: 'trace-couleur',
      type: 'line',
      source: TRACK_SOURCE,
      layout: round,
      paint: { 'line-color': TRACK_COLOR, 'line-width': 4.5 },
    },
  ];
}

/** Bâtit le style complet pour l'état courant de l'application. */
export function buildStyle(options: StyleOptions): StyleSpecification {
  const basemap = BASEMAPS[options.basemap];
  const sources: Record<string, SourceSpecification> = {
    [TRACK_SOURCE]: { type: 'geojson', data: options.track },
    [ZONE_SOURCE]: { type: 'geojson', data: options.zone },
  };
  if (options.hillshade) sources.estompage = rasterSource(HILLSHADE);
  if (options.coverage) {
    sources[COVERAGE_SOURCE] = {
      type: 'raster',
      tiles: [options.coverage.tilesUrl],
      tileSize: 256,
      minzoom: options.coverage.minzoom,
      maxzoom: options.coverage.maxzoom,
      bounds: options.coverage.bounds,
    };
  }
  const background: LayerSpecification = {
    id: 'fond-uni',
    type: 'background',
    paint: { 'background-color': BACKGROUND_COLOR },
  };

  if (basemap.kind === 'vector' && options.vectorStyle) {
    const base = options.vectorStyle;
    const layers = base.layers ?? [];
    // La couche réseau passe sous les libellés : juste avant la première couche « symbol » du style.
    let firstSymbol = layers.findIndex((layer) => layer.type === 'symbol');
    if (firstSymbol === -1) firstSymbol = layers.length;
    return {
      version: 8,
      name: basemap.id,
      glyphs: base.glyphs,
      sprite: base.sprite,
      sources: { ...base.sources, ...sources },
      layers: [
        background,
        ...layers.slice(0, firstSymbol),
        ...overlayLayers(options),
        ...layers.slice(firstSymbol),
        ...trackLayers(),
      ],
    };
  }

  const spec: RasterSpec = basemap.kind === 'raster' ? basemap : basemap.fallback;
  sources.fond = rasterSource(spec);
  return {
    version: 8,
    name: basemap.id,
    sources,
    layers: [
      background,
      { id: 'fond', type: 'raster', source: 'fond', paint: { 'raster-fade-duration': 0 } },
      ...overlayLayers(options),
      ...trackLayers(),
    ],
  };
}
