// Recherche de lieux avec suggestions.
//
// - En France : autocomplétion du géocodage de la Géoplateforme (IGN).
// - À l'étranger : Photon (komoot), basé sur OpenStreetMap.
//
// Les deux services sont interrogés seulement quand l'utilisateur tape dans la
// recherche. Rien d'autre ne leur est envoyé.

import { abortError } from '../coverage/abort';
import {
  IGN_COMPLETION_URL,
  PHOTON_LANGS,
  PHOTON_URL,
  SEARCH_MAX_RESULTS,
  SEARCH_TIMEOUT_MS,
} from '../config';

export interface Place {
  /** Nom principal. */
  label: string;
  /** Précision : code postal, commune, région, pays. */
  detail: string;
  /** Type de lieu, en clé de traduction (« search.kind.municipality ») : affiché avant la précision. */
  kindKey?: string;
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

/** Les deux services : l'IGN pour la France, Photon pour l'étranger. */
export type SearchService = 'france' | 'abroad';

export interface SearchResult {
  places: Place[];
  /** Vrai tant qu'un des deux services n'a pas répondu. */
  pending: boolean;
  /** Services en panne ou trop lents : leurs lieux manquent à la liste. */
  failed: SearchService[];
}

/** Position de la carte envoyée aux services, arrondie au centième de degré (environ 1 km) : rien de plus précis ne part. */
function roundedCenter(center: [number, number]): [string, string] {
  return [center[0].toFixed(2), center[1].toFixed(2)];
}

/** Signal d'une requête : annulée avec la recherche, ou au bout du délai maximal d'un service. */
function serviceSignal(signal?: AbortSignal): AbortSignal {
  const timeout = AbortSignal.timeout(SEARCH_TIMEOUT_MS);
  if (!signal) return timeout;
  if (typeof AbortSignal.any === 'function') return AbortSignal.any([signal, timeout]);
  // Navigateurs sans AbortSignal.any : même résultat à la main.
  const controller = new AbortController();
  for (const s of [signal, timeout]) {
    if (s.aborted) controller.abort(s.reason);
    else s.addEventListener('abort', () => controller.abort(s.reason), { once: true });
  }
  return controller.signal;
}

// -- Géoplateforme (IGN) ---------------------------------------------------

/** Réponse de l'autocomplétion (formatResult du géocodeur de la Géoplateforme, réponses lues par sonde). */
interface IgnCompletionResult {
  x: number;
  y: number;
  fulltext?: string;
  /** Adresse : type de la Base Adresse Nationale ; lieu : sa première catégorie IGN (en français). */
  kind?: string;
  /** Lieu : toutes ses catégories, par exemple ["administratif", "commune"]. */
  poiType?: unknown;
  city?: string;
  zipcode?: string;
  country?: string; // « PositionOfInterest » ou « StreetAddress »
  names?: string[];
  street?: string;
}

/** Types d'adresse de la Base Adresse Nationale, traduits dans l'interface, et zoom adapté à chacun. */
const ADDRESS_KINDS: Record<string, number> = { municipality: 12.5, locality: 14.5, street: 16, housenumber: 17 };

function poiTypes(result: IgnCompletionResult): string[] {
  return Array.isArray(result.poiType) ? result.poiType.filter((v): v is string => typeof v === 'string') : [];
}

/** Zoom adapté au type de lieu renvoyé par l'IGN. */
function ignZoom(result: IgnCompletionResult): number {
  if (result.country === 'StreetAddress') return ADDRESS_KINDS[result.kind ?? ''] ?? 16;
  const types = poiTypes(result);
  if (types.includes('département')) return 9;
  if (types.includes('commune') || types.includes('administratif')) return 12.5;
  const kind = (result.kind ?? '').toLowerCase();
  if (/commune|pr[ée]fecture|capitale/.test(kind)) return 12.5;
  if (/d[ée]partement|r[ée]gion|massif|vall[ée]e|for[êe]t|parc/.test(kind)) return 10.5;
  return 14.5;
}

/** Clé de traduction du type de lieu, quand il en a une ; sinon la catégorie IGN reste dans la précision. */
function ignKindKey(result: IgnCompletionResult): string | undefined {
  if (result.country === 'StreetAddress') return result.kind && result.kind in ADDRESS_KINDS ? `search.kind.${result.kind}` : undefined;
  const types = poiTypes(result);
  if (types.includes('commune')) return 'search.kind.municipality';
  if (types.includes('département')) return 'search.kind.department';
  return undefined;
}

const sameName = (a?: string, b?: string): boolean => !!a && !!b && a.trim().toLocaleLowerCase('fr') === b.trim().toLocaleLowerCase('fr');

export function parseIgnCompletion(payload: unknown): Place[] {
  if (typeof payload !== 'object' || payload === null) return [];
  const results = (payload as { results?: unknown }).results;
  if (!Array.isArray(results)) return [];
  const valid = (results as IgnCompletionResult[]).filter((raw) => typeof raw?.x === 'number' && typeof raw?.y === 'number');
  // Une commune vient deux fois, comme lieu (« administratif ») et comme adresse : on garde le lieu.
  const communes = valid.filter((raw) => raw.country === 'PositionOfInterest' && poiTypes(raw).includes('commune'));
  const places: Place[] = [];
  for (const raw of valid) {
    if (raw.country === 'StreetAddress' && raw.kind === 'municipality' && communes.some((c) => sameName(c.names?.[0], raw.city) && c.zipcode === raw.zipcode)) continue;
    const name = raw.country === 'PositionOfInterest' ? (raw.names?.[0] ?? raw.street) : undefined;
    const label = name ?? raw.fulltext ?? '';
    if (!label) continue;
    const kindKey = ignKindKey(raw);
    const where = [raw.zipcode, raw.city].filter(Boolean).join(' ');
    // Adresse : son libellé contient déjà le code postal et la commune. Lieu : sa catégorie IGN si elle n'est pas traduite.
    const detail = name ? [kindKey ? null : raw.kind, where].filter(Boolean).join(', ') : '';
    const place: Place = { label, detail, lon: raw.x, lat: raw.y, zoom: ignZoom(raw), source: 'ign' };
    if (kindKey) place.kindKey = kindKey;
    places.push(place);
  }
  return places;
}

async function requestIgn(query: string, center: [number, number] | null, signal: AbortSignal): Promise<Response> {
  const url = new URL(IGN_COMPLETION_URL);
  url.searchParams.set('text', query);
  url.searchParams.set('type', 'PositionOfInterest,StreetAddress');
  url.searchParams.set('terr', 'METROPOLE');
  url.searchParams.set('maximumResponses', String(SEARCH_MAX_RESULTS));
  // « lonlat » favorise les lieux proches de la carte (documenté par la Géoplateforme).
  if (center) url.searchParams.set('lonlat', roundedCenter(center).join(','));
  return fetch(url, { signal });
}

async function searchIgn(query: string, options: SearchOptions): Promise<Place[]> {
  const signal = serviceSignal(options.signal);
  let response = await requestIgn(query, options.center, signal);
  // Le motif de « lonlat » publié par la Géoplateforme refuse une longitude négative (ouest de la France),
  // que le service accepte aujourd'hui (vérifié par sonde) : s'il la refusait un jour, on cherche sans.
  if (response.status === 400) response = await requestIgn(query, null, signal);
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
  const [lon, lat] = roundedCenter(options.center);
  url.searchParams.set('lon', lon);
  url.searchParams.set('lat', lat);
  url.searchParams.set('bbox', options.bounds.join(','));
  const response = await fetch(url, { signal: serviceSignal(options.signal) });
  if (!response.ok) throw new Error(`Photon : HTTP ${response.status}`);
  // La France est servie par l'IGN : on écarte ses résultats ici pour éviter les doublons.
  return parsePhoton(await response.json(), 'FR');
}

/**
 * Cherche un lieu en France (IGN) et à l'étranger (Photon). Chaque service a un
 * délai maximal ; « onUpdate » reçoit les lieux du premier qui répond, sans
 * attendre l'autre. La promesse donne la liste complète, avec les services en
 * panne. Elle échoue si la recherche est annulée (AbortError), ou si un service
 * est en panne et que l'autre ne trouve rien : « aucun lieu trouvé » serait faux.
 */
export async function searchPlaces(query: string, options: SearchOptions, onUpdate?: (result: SearchResult) => void): Promise<SearchResult> {
  const found: Record<SearchService, Place[] | null> = { france: null, abroad: null };
  const failed: SearchService[] = [];
  const errors: unknown[] = [];
  const current = (): SearchResult => ({
    places: mergePlaces(found.france ?? [], found.abroad ?? [], options.abroadFirst),
    pending: (['france', 'abroad'] as const).some((service) => found[service] === null && !failed.includes(service)),
    failed: [...failed],
  });
  const run = (service: SearchService, search: Promise<Place[]>): Promise<void> =>
    search.then(
      (places) => {
        found[service] = places;
      },
      (error: unknown) => {
        failed.push(service);
        errors.push(error);
      },
    ).then(() => {
      // Un service a répondu, l'autre cherche encore : on montre déjà ce qu'on a.
      const partial = current();
      if (partial.pending && !options.signal?.aborted) onUpdate?.(partial);
    });
  await Promise.all([run('france', searchIgn(query, options)), run('abroad', searchPhoton(query, options))]);
  if (options.signal?.aborted) throw options.signal.reason ?? abortError();
  const result = current();
  if (result.places.length === 0 && errors.length > 0) throw errors[0];
  return result;
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
