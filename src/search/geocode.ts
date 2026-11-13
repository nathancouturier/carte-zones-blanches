// Recherche de lieux avec suggestions.
//
// - En France : autocomplétion du géocodage de la Géoplateforme (IGN).
// - À l'étranger : Photon (komoot), basé sur OpenStreetMap.
//
// Les deux services sont interrogés seulement quand l'utilisateur tape dans la
// recherche. Rien d'autre ne leur est envoyé.

import {
  IGN_COMPLETION_URL,
  PHOTON_LANGS,
  PHOTON_URL,
  SEARCH_MAX_RESULTS,
} from '../config';

export interface Place {
  /** Nom principal. */
  label: string;
  /** Précision : commune, région, pays. */
  detail: string;
  lon: number;
  lat: number;
  /** Zoom conseillé pour afficher le lieu. */
  zoom: number;
  /** Emprise du lieu si elle est connue : ouest, sud, est, nord. */
  bbox?: [number, number, number, number];
  source: 'ign' | 'osm';
}

export interface SearchOptions {
  lang: string;
  /** Centre de la carte : les résultats proches passent en premier. */
  center: [number, number];
  /** Emprise de recherche à l'étranger : ouest, sud, est, nord. */
  bounds: [number, number, number, number];
  /** Vrai si le centre de la carte est hors de France : les résultats étrangers passent devant. */
  abroadFirst: boolean;
  signal?: AbortSignal;
}

// -- Géoplateforme (IGN) ---------------------------------------------------

interface IgnCompletionResult {
  x: number;
  y: number;
  fulltext?: string;
  kind?: string;
  city?: string;
  zipcode?: string;
  country?: string; // « PositionOfInterest » ou « StreetAddress »
  names?: string[];
  street?: string;
}

/** Zoom adapté au type de lieu renvoyé par l'IGN. */
function ignZoom(result: IgnCompletionResult): number {
  if (result.country === 'StreetAddress') return 16;
  const kind = (result.kind ?? '').toLowerCase();
  if (/commune|pr[ée]fecture|capitale/.test(kind)) return 12.5;
  if (/d[ée]partement|r[ée]gion|massif|vall[ée]e|for[êe]t|parc/.test(kind)) return 10.5;
  return 14.5;
}

export function parseIgnCompletion(payload: unknown): Place[] {
  if (typeof payload !== 'object' || payload === null) return [];
  const results = (payload as { results?: unknown }).results;
  if (!Array.isArray(results)) return [];
  const places: Place[] = [];
  for (const raw of results as IgnCompletionResult[]) {
    if (typeof raw?.x !== 'number' || typeof raw?.y !== 'number') continue;
    const name = raw.country === 'PositionOfInterest' ? (raw.names?.[0] ?? raw.street) : undefined;
    const label = name ?? raw.fulltext ?? '';
    if (!label) continue;
    const where = [raw.zipcode, raw.city].filter(Boolean).join(' ');
    const detail = name ? [raw.kind, where].filter(Boolean).join(', ') : (raw.kind ?? '');
    places.push({ label, detail, lon: raw.x, lat: raw.y, zoom: ignZoom(raw), source: 'ign' });
  }
  return places;
}

async function searchIgn(query: string, signal?: AbortSignal): Promise<Place[]> {
  const url = new URL(IGN_COMPLETION_URL);
  url.searchParams.set('text', query);
  url.searchParams.set('type', 'PositionOfInterest,StreetAddress');
  url.searchParams.set('terr', 'METROPOLE');
  url.searchParams.set('maximumResponses', String(SEARCH_MAX_RESULTS));
  const response = await fetch(url, { signal });
  if (!response.ok) throw new Error(`IGN : HTTP ${response.status}`);
  return parseIgnCompletion(await response.json());
}

// -- Photon (OpenStreetMap) --------------------------------------------------

interface PhotonProperties {
  name?: string;
  street?: string;
  housenumber?: string;
  city?: string;
  county?: string;
  state?: string;
  country?: string;
  countrycode?: string;
  osm_key?: string;
  osm_value?: string;
  type?: string;
  extent?: [number, number, number, number]; // ouest, nord, est, sud
}

function photonZoom(p: PhotonProperties): number {
  switch (p.type) {
    case 'country':
      return 6;
    case 'state':
      return 8;
    case 'county':
      return 10;
    case 'city':
      return 12.5;
    case 'district':
    case 'locality':
      return 14;
    case 'street':
    case 'house':
      return 16;
    default:
      return 14.5;
  }
}

export function parsePhoton(payload: unknown, excludeCountry?: string): Place[] {
  if (typeof payload !== 'object' || payload === null) return [];
  const features = (payload as { features?: unknown }).features;
  if (!Array.isArray(features)) return [];
  const places: Place[] = [];
  for (const feature of features as { properties?: PhotonProperties; geometry?: { coordinates?: unknown } }[]) {
    const p = feature.properties ?? {};
    const coords = feature.geometry?.coordinates;
    if (!Array.isArray(coords) || typeof coords[0] !== 'number' || typeof coords[1] !== 'number') continue;
    if (excludeCountry && p.countrycode?.toUpperCase() === excludeCountry) continue;
    const label = p.name ?? [p.street, p.housenumber].filter(Boolean).join(' ');
    if (!label) continue;
    const detail = [p.city && p.city !== label ? p.city : null, p.county, p.state, p.country]
      .filter((v): v is string => typeof v === 'string' && v !== '' && v !== label)
      .filter((v, i, all) => all.indexOf(v) === i)
      .join(', ');
    const place: Place = { label, detail, lon: coords[0], lat: coords[1], zoom: photonZoom(p), source: 'osm' };
    if (Array.isArray(p.extent) && p.extent.length === 4 && p.extent.every((v) => typeof v === 'number')) {
      const [west, north, east, south] = p.extent;
      place.bbox = [west, south, east, north];
    }
    places.push(place);
  }
  return places;
}

async function searchPhoton(query: string, options: SearchOptions): Promise<Place[]> {
  const url = new URL(PHOTON_URL);
  url.searchParams.set('q', query);
  url.searchParams.set('limit', String(SEARCH_MAX_RESULTS + 4));
  // Photon ne connaît que quelques langues : pour les autres, on demande les noms locaux.
  url.searchParams.set('lang', PHOTON_LANGS.includes(options.lang) ? options.lang : 'default');
  url.searchParams.set('lon', options.center[0].toFixed(4));
  url.searchParams.set('lat', options.center[1].toFixed(4));
  url.searchParams.set('bbox', options.bounds.join(','));
  const response = await fetch(url, { signal: options.signal });
  if (!response.ok) throw new Error(`Photon : HTTP ${response.status}`);
  // La France est servie par l'IGN : on écarte ses résultats ici pour éviter les doublons.
  return parsePhoton(await response.json(), 'FR');
}

/**
 * Cherche un lieu en France et à l'étranger. Si un des deux services échoue,
 * on renvoie les résultats de l'autre. L'erreur n'est levée que si les deux
 * échouent.
 */
export async function searchPlaces(query: string, options: SearchOptions): Promise<Place[]> {
  const [ign, osm] = await Promise.allSettled([searchIgn(query, options.signal), searchPhoton(query, options)]);
  if (options.signal?.aborted) return [];
  if (ign.status === 'rejected' && osm.status === 'rejected') throw ign.reason;
  const france = ign.status === 'fulfilled' ? ign.value : [];
  const abroad = osm.status === 'fulfilled' ? osm.value : [];
  return mergePlaces(france, abroad, options.abroadFirst);
}

/** Alterne les deux listes en commençant par celle du pays où se trouve la carte. */
export function mergePlaces(france: Place[], abroad: Place[], abroadFirst: boolean, max: number = SEARCH_MAX_RESULTS): Place[] {
  const first = abroadFirst ? abroad : france;
  const second = abroadFirst ? france : abroad;
  // La liste principale garde au moins les deux tiers des places.
  const mainQuota = second.length === 0 ? max : Math.max(max - second.length, Math.ceil((max * 2) / 3));
  const main = first.slice(0, mainQuota);
  return [...main, ...second.slice(0, max - main.length)];
}
