// Fonds de carte. Toutes les URL et tous les identifiants de couches ont été
// vérifiés dans les GetCapabilities des services (voir docs/sources.md).

export type BasemapId = 'ign-classique' | 'ign-standard' | 'swisstopo' | 'ign-es' | 'osm' | 'ortho';
export type BasemapChoice = BasemapId | 'auto';

/**
 * Ce que le fournisseur d'un fond permet d'enregistrer à l'avance pour le mode hors
 * ligne. Les plafonds et les freins sont des choix du projet, fondés sur les
 * conditions d'utilisation lues (voir docs/sources.md) ; sur une réponse 429 ou 503,
 * le préchargement attend la durée demandée, puis abandonne ce fond après quelques
 * refus (src/offline/manager.ts).
 */
export interface PreloadPolicy {
  allowed: boolean;
  /** Nombre maximal de tuiles enregistrées par tracé. */
  maxTiles: number;
  minZoom: number;
  maxZoom: number;
  /** Requêtes simultanées, au plus. */
  concurrency: number;
  /** Requêtes par seconde, au plus ; 0 : pas d'autre frein que les requêtes simultanées. */
  perSecond: number;
}

interface BasemapBase {
  id: BasemapId;
  /** Clé de traduction du nom. */
  labelKey: string;
  /** Mention à afficher dans le pied de carte. */
  attribution: string;
  /** Préchargement pour le mode hors ligne, selon les conditions du fournisseur (voir docs/sources.md). */
  offline: PreloadPolicy;
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

/**
 * Plan IGN vectoriel : Licence Ouverte 2.0, limite publiée de 400 requêtes par seconde et
 * par adresse. Tuiles légères : on descend jusqu'au zoom 15.
 */
const IGN_OFFLINE: PreloadPolicy = { allowed: true, maxTiles: 900, minZoom: 7, maxZoom: 15, concurrency: 4, perSecond: 0 };
/** IGN en images (photos aériennes, Plan IGN de repli, estompage) : WMTS sans limite d'usage publiée. */
const IGN_RASTER_OFFLINE: PreloadPolicy = { allowed: true, maxTiles: 600, minZoom: 9, maxZoom: 16, concurrency: 4, perSecond: 0 };
/** Plan IGN en images, quand le style vectoriel est injoignable. */
export const PLAN_IGN_RASTER_OFFLINE: PreloadPolicy = { ...IGN_RASTER_OFFLINE, maxZoom: 15 };

export const BASEMAPS: Record<BasemapId, Basemap> = {
  'ign-classique': {
    id: 'ign-classique',
    kind: 'vector',
    labelKey: 'basemap.ignClassique',
    attribution: '© IGN',
    offline: IGN_OFFLINE,
    styleUrl: `${IGN_STYLES}/classique.json`,
    fallback: PLAN_IGN_RASTER,
  },
  'ign-standard': {
    id: 'ign-standard',
    kind: 'vector',
    labelKey: 'basemap.ignStandard',
    attribution: '© IGN',
    offline: IGN_OFFLINE,
    styleUrl: `${IGN_STYLES}/standard.json`,
    fallback: PLAN_IGN_RASTER,
  },
  swisstopo: {
    id: 'swisstopo',
    kind: 'raster',
    labelKey: 'basemap.swisstopo',
    attribution: '© swisstopo',
    // Usage équitable (1 200 requêtes par minute), cache local prévu par la documentation : 2 requêtes par seconde au plus.
    offline: { allowed: true, maxTiles: 600, minZoom: 9, maxZoom: 15, concurrency: 2, perSecond: 2 },
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
    // CC BY 4.0, aucune limite publiée : prudence, 5 requêtes par seconde au plus.
    offline: { allowed: true, maxTiles: 600, minZoom: 9, maxZoom: 15, concurrency: 2, perSecond: 5 },
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
    // Le fournisseur ne garantit pas la disponibilité de son serveur et demande d'éviter les
    // téléchargements en masse : pas d'enregistrement à l'avance.
    offline: { allowed: false, maxTiles: 0, minZoom: 0, maxZoom: 0, concurrency: 0, perSecond: 0 },
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
    offline: IGN_RASTER_OFFLINE,
    tiles: [`${GEOPF_WMTS}&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&FORMAT=image/jpeg&STYLE=normal`],
    tileSize: 256,
    minzoom: 0,
    maxzoom: 19,
  },
};

/** Ordre d'affichage dans le panneau « Fond ». */
export const BASEMAP_ORDER: BasemapId[] = ['ign-classique', 'ign-standard', 'swisstopo', 'ign-es', 'osm', 'ortho'];

/** Estompage du relief (IGN), proposé en option par-dessus le fond. France uniquement. */
export const HILLSHADE: RasterSpec & { attribution: string; offline: PreloadPolicy } = {
  tiles: [`${GEOPF_WMTS}&LAYER=ELEVATION.ELEVATIONGRIDCOVERAGE.SHADOW&FORMAT=image/png&STYLE=estompage_grayscale`],
  tileSize: 256,
  minzoom: 0,
  maxzoom: 15,
  bounds: [-5.6, 41.2, 9.9, 51.3],
  attribution: '© IGN',
  offline: { ...IGN_RASTER_OFFLINE, maxZoom: 15 },
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

/** Plages de glyphes enregistrées pour le hors ligne : latin de base, latin étendu, ponctuation générale. */
const GLYPH_RANGES = ['0-255', '256-511', '8192-8447'];

export interface BasemapPack {
  /** Fond, ou « hillshade » pour l'estompage du relief. */
  id: BasemapId | 'hillshade';
  policy: PreloadPolicy;
  /** Gabarits d'URL des tuiles ({z}, {x}, {y}). */
  tileTemplates: string[];
  /** Emprise servie par le fournisseur : rien n'est demandé au-delà. */
  bounds?: [number, number, number, number];
  /** Ressources à enregistrer en plus des tuiles : style, sprites, polices. */
  extraUrls: string[];
}

interface VectorStyleLike {
  sources?: Record<string, { type?: string; tiles?: string[] }>;
  sprite?: unknown;
  glyphs?: string;
  layers?: { layout?: Record<string, unknown> }[];
}

/**
 * Ce qu'il faut enregistrer pour afficher un fond sans réseau. Pour un fond
 * vectoriel, il faut le style déjà téléchargé : on y lit l'adresse des tuiles,
 * des sprites et des polices, sans rien supposer.
 */
export function basemapPack(id: BasemapId, vectorStyle: VectorStyleLike | null): BasemapPack {
  const basemap = BASEMAPS[id];
  if (basemap.kind === 'raster') {
    return { id, policy: basemap.offline, tileTemplates: basemap.tiles, bounds: basemap.bounds, extraUrls: [] };
  }
  if (!vectorStyle) {
    // Style vectoriel injoignable : c'est le Plan IGN en images qui est affiché.
    return { id, policy: PLAN_IGN_RASTER_OFFLINE, tileTemplates: basemap.fallback.tiles, extraUrls: [] };
  }
  const tileTemplates = Object.values(vectorStyle.sources ?? {})
    .filter((source) => source.type === 'vector')
    .flatMap((source) => source.tiles ?? []);
  const extraUrls = [basemap.styleUrl];
  if (typeof vectorStyle.sprite === 'string') {
    for (const suffix of ['.json', '.png', '@2x.json', '@2x.png']) extraUrls.push(`${vectorStyle.sprite}${suffix}`);
  }
  if (vectorStyle.glyphs) {
    const stacks = new Set<string>();
    for (const layer of vectorStyle.layers ?? []) {
      const font = layer.layout?.['text-font'];
      if (Array.isArray(font) && font.every((f) => typeof f === 'string')) stacks.add(font.join(','));
    }
    for (const stack of stacks) {
      for (const range of GLYPH_RANGES) {
        extraUrls.push(vectorStyle.glyphs.replace('{fontstack}', encodeURIComponent(stack)).replace('{range}', range));
      }
    }
  }
  return { id, policy: basemap.offline, tileTemplates, extraUrls };
}

/** Ce qu'il faut enregistrer pour l'estompage du relief. */
export function hillshadePack(): BasemapPack {
  return { id: 'hillshade', policy: HILLSHADE.offline, tileTemplates: HILLSHADE.tiles, bounds: HILLSHADE.bounds, extraUrls: [] };
}

/** Fond que le mode Auto afficherait dans ce pays (code ISO). */
export function nationalBasemap(iso: string): BasemapId {
  return NATIONAL_BASEMAP[iso] ?? FALLBACK_BASEMAP;
}
