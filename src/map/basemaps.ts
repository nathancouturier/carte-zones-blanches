// Fonds de carte. Toutes les URL et tous les identifiants de couches ont été
// vérifiés dans les GetCapabilities des services (voir docs/sources.md).

export type BasemapId = 'ign-classique' | 'ign-standard' | 'swisstopo' | 'ign-es' | 'osm' | 'ortho';
export type BasemapChoice = BasemapId | 'auto';

interface BasemapBase {
  id: BasemapId;
  /** Clé de traduction du nom. */
  labelKey: string;
  /** Mention à afficher dans le pied de carte. */
  attribution: string;
}

export interface VectorBasemap extends BasemapBase {
  kind: 'vector';
  styleUrl: string;
  /** Fond raster équivalent, utilisé si le style vectoriel ne peut pas être chargé. */
  fallback: RasterSpec;
}

export interface RasterSpec {
  tiles: string[];
  tileSize: number;
  minzoom: number;
  maxzoom: number;
  /** Emprise servie par le fournisseur : ouest, sud, est, nord. */
  bounds?: [number, number, number, number];
}

export interface RasterBasemap extends BasemapBase, RasterSpec {
  kind: 'raster';
}

export type Basemap = VectorBasemap | RasterBasemap;

const GEOPF_WMTS = 'https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&TILEMATRIXSET=PM&TILEMATRIX={z}&TILECOL={x}&TILEROW={y}';
const IGN_STYLES = 'https://data.geopf.fr/annexes/ressources/vectorTiles/styles/PLAN.IGN';

/** Plan IGN v2 en tuiles raster : repli des styles vectoriels. */
const PLAN_IGN_RASTER: RasterSpec = {
  tiles: [`${GEOPF_WMTS}&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&FORMAT=image/png&STYLE=normal`],
  tileSize: 256,
  minzoom: 0,
  maxzoom: 19,
};

export const BASEMAPS: Record<BasemapId, Basemap> = {
  'ign-classique': {
    id: 'ign-classique',
    kind: 'vector',
    labelKey: 'basemap.ignClassique',
    attribution: '© IGN',
    styleUrl: `${IGN_STYLES}/classique.json`,
    fallback: PLAN_IGN_RASTER,
  },
  'ign-standard': {
    id: 'ign-standard',
    kind: 'vector',
    labelKey: 'basemap.ignStandard',
    attribution: '© IGN',
    styleUrl: `${IGN_STYLES}/standard.json`,
    fallback: PLAN_IGN_RASTER,
  },
  swisstopo: {
    id: 'swisstopo',
    kind: 'raster',
    labelKey: 'basemap.swisstopo',
    attribution: '© swisstopo',
    tiles: ['https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-farbe/default/current/3857/{z}/{x}/{y}.jpeg'],
    tileSize: 256,
    minzoom: 0,
    maxzoom: 18,
    bounds: [5.14, 45.39, 11.48, 48.23],
  },
  'ign-es': {
    id: 'ign-es',
    kind: 'raster',
    labelKey: 'basemap.ignEs',
    attribution: 'CC BY 4.0 ign.es',
    tiles: [
      'https://www.ign.es/wmts/mapa-raster?service=WMTS&request=GetTile&version=1.0.0&layer=MTN&style=default&tilematrixset=GoogleMapsCompatible&format=image/jpeg&TileMatrix={z}&TileCol={x}&TileRow={y}',
    ],
    tileSize: 256,
    minzoom: 0,
    maxzoom: 17,
    bounds: [-18.5, 27.4, 4.7, 44.1],
  },
  osm: {
    id: 'osm',
    kind: 'raster',
    labelKey: 'basemap.osm',
    attribution: '© OpenStreetMap, SRTM | © OpenTopoMap (CC BY-SA)',
    tiles: ['https://a.tile.opentopomap.org/{z}/{x}/{y}.png', 'https://b.tile.opentopomap.org/{z}/{x}/{y}.png', 'https://c.tile.opentopomap.org/{z}/{x}/{y}.png'],
    tileSize: 256,
    minzoom: 0,
    maxzoom: 17,
  },
  ortho: {
    id: 'ortho',
    kind: 'raster',
    labelKey: 'basemap.ortho',
    attribution: '© IGN',
    tiles: [`${GEOPF_WMTS}&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&FORMAT=image/jpeg&STYLE=normal`],
    tileSize: 256,
    minzoom: 0,
    maxzoom: 19,
  },
};

/** Ordre d'affichage dans le panneau « Fond ». */
export const BASEMAP_ORDER: BasemapId[] = ['ign-classique', 'ign-standard', 'swisstopo', 'ign-es', 'osm', 'ortho'];

/** Estompage du relief (IGN), proposé en option par-dessus le fond. France uniquement. */
export const HILLSHADE: RasterSpec & { attribution: string } = {
  tiles: [`${GEOPF_WMTS}&LAYER=ELEVATION.ELEVATIONGRIDCOVERAGE.SHADOW&FORMAT=image/png&STYLE=estompage_grayscale`],
  tileSize: 256,
  minzoom: 0,
  maxzoom: 15,
  bounds: [-5.6, 41.2, 9.9, 51.3],
  attribution: '© IGN',
};

/** Fond national par pays (code ISO), pour le mode Auto. Les autres pays reçoivent le fond OpenStreetMap. */
const NATIONAL_BASEMAP: Record<string, BasemapId> = {
  FR: 'ign-classique',
  CH: 'swisstopo',
  ES: 'ign-es',
};

export const DEFAULT_BASEMAP: BasemapId = 'ign-classique';
export const FALLBACK_BASEMAP: BasemapId = 'osm';

/** Fond du mode Auto pour le pays au centre de la carte. null : pays inconnu, on garde le fond courant. */
export function autoBasemap(iso: string | null): BasemapId | null {
  if (!iso) return null;
  return NATIONAL_BASEMAP[iso] ?? FALLBACK_BASEMAP;
}

export function isBasemapChoice(value: unknown): value is BasemapChoice {
  return value === 'auto' || (typeof value === 'string' && value in BASEMAPS);
}
