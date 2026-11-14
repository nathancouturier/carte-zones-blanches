// Mode hors ligne pour un tracé.
//
// « Préparer le hors ligne » enregistre dans le navigateur, pour le tracé chargé :
//   1. rien pour le site lui-même : le Service Worker en a enregistré la coque
//      entière à son installation (public/sw.js) ; on vérifie seulement qu'elle
//      est complète, sans quoi rien ne s'ouvrirait sans réseau ;
//   2. le GPX lui-même et le manifest des données, pour les retrouver sans réseau ;
//   3. les tuiles de couverture du couloir du tracé (lues dans les archives PMTiles),
//      rangées sous le nom de leur archive : celles d'une autre édition des données
//      ne sont jamais relues avec ce manifest ;
//   4. les tuiles des fonds de carte le long du parcours, si leur fournisseur
//      l'autorise, dans les limites qu'il tolère (plafond, requêtes simultanées,
//      débit, attente sur 429 ou 503 : voir src/map/basemaps.ts et docs/sources.md).
//      En mode Auto, chaque portion du tracé reçoit le fond que le mode Auto
//      afficherait dans son pays ; l'estompage du relief suit s'il est affiché.
// Un seul tracé à la fois : ce qui ne lui sert pas est effacé au début. L'information
// sur l'enregistrement est écrite dès le début, marquée incomplète jusqu'à la fin :
// interrompu, annulé ou en échec, il reste visible et peut être repris ou supprimé.
// Tout reste dans le navigateur (Cache API). Rien n'est envoyé.

import { NETWORK_TIMEOUT_MS, TILE_READ_TIMEOUT_MS } from '../config';
import { archiveForTile, type Manifest } from '../coverage/manifest';
import type { ArchiveReader } from '../coverage/store';
import type { Sample } from '../gpx/resample';
import { nationalBasemap, type BasemapChoice, type BasemapId, type BasemapPack, type PreloadPolicy } from '../map/basemaps';
import { corridorTiles, planCorridor, tileUrl, type TileId } from './corridor';

/** Doit rester identique à HORS_LIGNE dans public/sw.js. */
export const OFFLINE_CACHE = 'czb-hors-ligne-v1';
/** Préfixe des caches de la coque, un par version du site (public/sw.js). */
const SHELL_CACHE_PREFIX = 'czb-coque-';
const INFO_KEY = 'czb.horsLigne';
/**
 * En-tête de la copie du manifest enregistrée avec le tracé : le Service Worker la
 * sert telle quelle quand le réseau manque ou tarde, et la page sait ainsi qu'elle
 * travaille sur les données enregistrées.
 */
export const LOCAL_COPY_HEADER = 'x-czb-copie-locale';
/** Attente maximale de la coque à la première visite (Service Worker en cours d'installation), en millisecondes. */
const SHELL_WAIT_MS = 30_000;
/** Marge du couloir autour du tracé, en mètres. */
export const CORRIDOR_BUFFER_M = 700;
/** Zooms des tuiles de couverture enregistrées (le zoom 12 sert à l'analyse, les autres à l'affichage dézoomé). */
const COVERAGE_ZOOMS = [8, 9, 10, 11, 12];
/** Lectures simultanées dans les archives de couverture (publiées avec le site). */
const CONCURRENCY = 4;
/** Attente quand un serveur de fond demande de ralentir (429 ou 503) sans dire combien de temps, en millisecondes. */
const RETRY_DEFAULT_MS = 5000;
/** Au-delà de cette attente demandée, on renonce à ce fond plutôt que de bloquer la préparation. */
const RETRY_MAX_WAIT_MS = 60_000;
/** Refus (429 ou 503) d'une même tuile avant de renoncer à ce fond. */
const RETRY_TRIES = 3;
/** Échecs réseau d'affilée avant de renoncer à ce fond (serveur injoignable ou qui refuse). */
const MAX_FAILURES_IN_A_ROW = 8;
/** Les entrées sont rangées par adresse : on ignore l'en-tête Vary du serveur. */
const IGNORE_VARY = { ignoreVary: true };

export interface OfflineInfo {
  /** Nom du tracé préparé. */
  name: string;
  /** Date de préparation (ISO). */
  date: string;
  /** Faux tant que l'enregistrement n'est pas allé au bout (en cours, interrompu, annulé, en échec). */
  complete: boolean;
  /** Vrai si le navigateur a promis de ne pas effacer ces données quand la place manque. */
  persisted: boolean;
  /** Édition des données enregistrées : noms des archives du manifest de la préparation. */
  archives: string[];
  /** Date de ces données (manifest.generated). */
  generated: string;
  coverageTiles: number;
  /** Fonds de carte : ce qui a été enregistré ou non, fond par fond. */
  basemaps: BasemapRecord[];
}

/** Ce qui a été enregistré pour un fond de carte (ou pour l'estompage du relief). */
export interface BasemapRecord {
  id: BasemapId | 'hillshade';
  /** Pays du tracé pour lesquels le mode Auto a choisi ce fond (codes ISO) ; vide hors mode Auto. */
  countries: string[];
  /** Faux si le fournisseur ne permet pas l'enregistrement à l'avance. */
  allowed: boolean;
  /** Adresses prévues (tuiles, style, polices) et adresses enregistrées. */
  total: number;
  stored: number;
  /** Tuiles enregistrées. */
  tiles: number;
}

/** Un fond à enregistrer, pour une partie des points du tracé. */
export interface BasemapJob {
  pack: BasemapPack;
  samples: readonly Sample[];
  /** Pays concernés (mode Auto). */
  countries: string[];
}

export interface PrepareOptions {
  samples: readonly Sample[];
  trackName: string;
  gpxText: string;
  fileName: string;
  /** Manifest des données utilisé par la page : sa copie accompagne les tuiles de couverture enregistrées. */
  manifest: Manifest;
  /** Lecture des archives PMTiles en ligne. */
  readArchive: ArchiveReader;
  /** Fonds à enregistrer (voir basemapGroups). */
  basemaps: BasemapJob[];
  onProgress: (done: number, total: number) => void;
  signal?: AbortSignal;
}

export function offlineSupported(): boolean {
  return typeof caches !== 'undefined' && typeof navigator !== 'undefined' && 'serviceWorker' in navigator;
}

/** Adresse sous laquelle une tuile de couverture est enregistrée : le nom de l'archive en fait partie. */
export function coverageTileKey(base: string, file: string, z: number, x: number, y: number): string {
  return new URL(`${base}hors-ligne/couverture/${encodeURIComponent(file)}/${z}/${x}/${y}`, location.href).href;
}

function trackKey(base: string): string {
  return new URL(`${base}hors-ligne/trace.gpx`, location.href).href;
}

/** Adresse du manifest des données : sa copie enregistrée est servie par le Service Worker à la même adresse. */
function manifestKey(base: string): string {
  return new URL(`${base}data/manifest.json`, location.href).href;
}

/** Erreur de préparation dont la cause est expliquée à l'utilisateur. */
export class OfflineError extends Error {
  /** shell : la coque du site manque ; quota : plus de place dans le navigateur. */
  constructor(readonly code: 'shell' | 'quota') {
    super(`Hors ligne : ${code}`);
  }
}

async function pool<T>(items: readonly T[], worker: (item: T) => Promise<void>, concurrency: number, signal?: AbortSignal): Promise<void> {
  let next = 0;
  const run = async (): Promise<void> => {
    while (next < items.length) {
      if (signal?.aborted) throw new DOMException('Annulé', 'AbortError');
      const item = items[next++];
      await worker(item);
    }
  };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(concurrency, items.length)) }, run));
}

function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(resolve, ms);
    signal?.addEventListener(
      'abort',
      () => {
        clearTimeout(timer);
        reject(new DOMException('Annulé', 'AbortError'));
      },
      { once: true },
    );
  });
}

/**
 * Attente demandée par l'en-tête Retry-After (en secondes, ou date HTTP), en millisecondes.
 * Sur une autre origine, le navigateur ne laisse lire cet en-tête que si le serveur l'expose :
 * à défaut, RETRY_DEFAULT_MS.
 */
export function retryAfterMs(value: string | null, now: number = Date.now()): number {
  if (!value) return RETRY_DEFAULT_MS;
  const seconds = Number(value);
  if (value.trim() !== '' && Number.isFinite(seconds) && seconds >= 0) return seconds * 1000;
  const date = Date.parse(value);
  return Number.isFinite(date) ? Math.max(0, date - now) : RETRY_DEFAULT_MS;
}

/**
 * Fonds à enregistrer et points du tracé que chacun doit couvrir. Hors mode Auto, le fond
 * choisi pour tout le tracé. En mode Auto, chaque point reçoit le fond que le mode Auto
 * afficherait dans son pays ; un point hors des données suit le pays qui le précède (ou,
 * au départ, celui qui le suit), et sans aucun pays connu c'est le fond affiché.
 */
export function basemapGroups(
  samples: readonly Sample[],
  countryAt: (index: number) => string | null,
  choice: BasemapChoice,
  active: BasemapId,
): { id: BasemapId; samples: Sample[]; countries: string[] }[] {
  if (choice !== 'auto') return samples.length > 0 ? [{ id: choice, samples: [...samples], countries: [] }] : [];
  const iso = samples.map((_, i) => countryAt(i));
  const first = iso.find((code) => code !== null) ?? null;
  let current = first;
  const groups = new Map<BasemapId, { id: BasemapId; samples: Sample[]; countries: string[] }>();
  samples.forEach((sample, i) => {
    if (iso[i] !== null) current = iso[i];
    const id = current === null ? active : nationalBasemap(current);
    let group = groups.get(id);
    if (!group) groups.set(id, (group = { id, samples: [], countries: [] }));
    group.samples.push(sample);
    if (current !== null && !group.countries.includes(current)) group.countries.push(current);
  });
  return [...groups.values()];
}

/** Fonds dont des tuiles ont été enregistrées : les seuls qu'on peut afficher sans réseau. */
export function storedBasemaps(info: OfflineInfo | null): (BasemapId | 'hillshade')[] {
  return info ? info.basemaps.filter((record) => record.tiles > 0).map((record) => record.id) : [];
}

/** Hôte dont les conditions interdisent l'usage hors ligne (« Offline use is not permitted »). */
function forbiddenHost(url: string): boolean {
  try {
    return /(^|\.)tile\.openstreetmap\.org$/.test(new URL(url).hostname);
  } catch {
    return true;
  }
}

/**
 * Télécharge et enregistre les adresses d'un fond, au rythme que permet son fournisseur :
 * requêtes simultanées et débit plafonnés ; sur une réponse 429 ou 503, tout le fond
 * attend la durée demandée puis reprend ; après RETRY_TRIES refus d'une même tuile, ou
 * MAX_FAILURES_IN_A_ROW échecs d'affilée, le reste de ce fond est abandonné (il manquera).
 * Renvoie les adresses enregistrées.
 */
async function download(cache: Cache, urls: readonly string[], policy: PreloadPolicy, step: () => void, signal?: AbortSignal): Promise<Set<string>> {
  const stored = new Set<string>();
  const spacing = policy.perSecond > 0 ? 1000 / policy.perSecond : 0;
  let nextAt = 0; // aucune requête ne part avant cet instant
  let failures = 0;
  let gaveUp = false;
  const slot = async (): Promise<void> => {
    const now = Date.now();
    const at = Math.max(now, nextAt);
    nextAt = at + spacing;
    if (at > now) await sleep(at - now, signal);
  };
  await pool(
    urls,
    async (url) => {
      try {
        if (gaveUp) return;
        if (await cache.match(url, IGNORE_VARY)) {
          stored.add(url);
          return;
        }
        for (let attempt = 1; !gaveUp; attempt++) {
          await slot();
          if (gaveUp) return;
          let response: Response;
          try {
            response = await fetch(url, { mode: 'cors', credentials: 'omit', signal });
          } catch (error) {
            if (signal?.aborted) throw error;
            if (++failures >= MAX_FAILURES_IN_A_ROW) gaveUp = true;
            return;
          }
          if (response.ok) {
            await cache.put(url, response);
            stored.add(url);
            failures = 0;
            return;
          }
          if (response.status !== 429 && response.status !== 503) return; // tuile absente ou refusée : elle manquera
          const wait = retryAfterMs(response.headers.get('retry-after'));
          if (attempt >= RETRY_TRIES || wait > RETRY_MAX_WAIT_MS) gaveUp = true;
          else nextAt = Math.max(nextAt, Date.now() + wait); // tout le fond ralentit, pas seulement cette tuile
        }
      } finally {
        step();
      }
    },
    Math.max(1, policy.concurrency),
    signal,
  );
  return stored;
}

/** Tuiles de couverture du couloir, aux zooms utiles. */
export function coverageCorridor(samples: readonly Sample[], maxZoom: number): TileId[] {
  return COVERAGE_ZOOMS.filter((z) => z <= maxZoom).flatMap((z) => corridorTiles(samples, z, CORRIDOR_BUFFER_M));
}

/** Tuiles de fond qui seraient préchargées pour ce tracé, selon la politique du fournisseur. */
export function basemapCorridor(samples: readonly Sample[], policy: PreloadPolicy): { tiles: TileId[]; maxZoom: number; reduced: boolean } {
  if (!policy.allowed) return { tiles: [], maxZoom: policy.minZoom, reduced: false };
  return planCorridor(samples, { minZoom: policy.minZoom, maxZoom: policy.maxZoom, buffer: CORRIDOR_BUFFER_M, maxTiles: policy.maxTiles });
}

/** Enregistre tout ce qu'il faut pour suivre le tracé sans réseau. */
export async function prepareOffline(base: string, options: PrepareOptions): Promise<OfflineInfo> {
  const { manifest, signal } = options;
  // Le navigateur gardera-t-il ces données s'il manque de place ? On le demande avant de télécharger.
  const persisted = await requestPersistence();
  // 1. La coque du site, enregistrée par le Service Worker : sans elle, rien ne s'ouvrirait sans réseau.
  if (!(await waitForShell(base))) throw new OfflineError('shell');
  signal?.throwIfAborted();

  const coverage = coverageCorridor(options.samples, manifest.tiles.maxzoom).flatMap((tile) => {
    const file = archiveForTile(manifest, tile.z, tile.x, tile.y)?.file;
    return file ? [{ ...tile, file, key: coverageTileKey(base, file, tile.z, tile.x, tile.y) }] : [];
  });
  // Fonds de carte : tuiles du couloir de chaque partie du tracé, dans l'emprise du fournisseur.
  const basemaps = options.basemaps.map((job) => {
    const urls = [...job.pack.extraUrls];
    const allowed = job.pack.policy.allowed && !job.pack.tileTemplates.some(forbiddenHost);
    const template = job.pack.tileTemplates[0];
    let tiles: string[] = [];
    if (allowed && template) {
      const bounds = job.pack.bounds;
      const inside = bounds ? job.samples.filter((p) => p.lon >= bounds[0] && p.lat >= bounds[1] && p.lon <= bounds[2] && p.lat <= bounds[3]) : job.samples;
      tiles = basemapCorridor(inside, job.pack.policy).tiles.map((tile) => tileUrl(template, tile));
    }
    return { job, allowed, extras: allowed ? urls.filter((url) => !forbiddenHost(url)) : [], tiles };
  });
  const info: OfflineInfo = {
    name: options.trackName,
    date: new Date().toISOString(),
    complete: false,
    persisted,
    archives: manifest.archives.map((archive) => archive.file),
    generated: manifest.generated,
    coverageTiles: coverage.length,
    basemaps: basemaps.map(({ job, allowed, extras, tiles }) => ({
      id: job.pack.id,
      countries: job.countries,
      allowed,
      total: extras.length + tiles.length,
      stored: 0,
      tiles: 0,
    })),
  };
  // Écrite avant toute donnée : même interrompu, l'enregistrement reste visible, donc supprimable.
  saveInfo(info);

  const cache = await caches.open(OFFLINE_CACHE);
  // Un seul tracé à la fois : ce qui ne sert pas à celui-ci (tracé précédent, autre édition des
  // données) est effacé ; ce qui resservira est gardé (mise à jour, reprise après une coupure).
  const basemapUrls = basemaps.flatMap(({ extras, tiles }) => [...extras, ...tiles]);
  const keep = new Set([trackKey(base), manifestKey(base), ...coverage.map((tile) => tile.key), ...basemapUrls].map((url) => new URL(url, location.href).href));
  for (const request of await cache.keys()) if (!keep.has(request.url)) await cache.delete(request);

  const total = 1 + coverage.length + basemapUrls.length;
  let done = 0;
  const step = (): void => options.onProgress(++done, total);
  options.onProgress(0, total);
  try {
    // 2. Le tracé et le manifest qui va avec les tuiles de couverture : d'abord, pour qu'un
    //    enregistrement interrompu puisse être repris.
    await cache.put(
      trackKey(base),
      new Response(options.gpxText, { headers: { 'content-type': 'application/gpx+xml', 'x-czb-nom': encodeURIComponent(options.fileName) } }),
    );
    await cache.put(manifestKey(base), new Response(JSON.stringify(manifest), { headers: { 'content-type': 'application/json', [LOCAL_COPY_HEADER]: '1' } }));
    step();

    // 3. Tuiles de couverture : une entrée par tuile, vide si la tuile n'existe pas, sous le nom de son archive.
    await pool(
      coverage,
      async (tile) => {
        // Déjà enregistrée (mise à jour, reprise) : même archive, donc mêmes octets.
        if (!(await cache.match(tile.key, IGNORE_VARY))) {
          // Même délai que pour l'affichage : une connexion qui cale ne fige pas l'enregistrement.
          const bytes = await options.readArchive(tile.file, tile.z, tile.x, tile.y, AbortSignal.timeout(TILE_READ_TIMEOUT_MS));
          const headers = { 'content-type': 'application/octet-stream', 'x-czb-vide': bytes ? '0' : '1' };
          await cache.put(tile.key, new Response(bytes ?? new ArrayBuffer(0), { headers }));
        }
        step();
      },
      CONCURRENCY,
      signal,
    );

    // 4. Fonds de carte, l'un après l'autre, chacun au rythme de son fournisseur.
    for (const [i, { job, extras, tiles }] of basemaps.entries()) {
      const stored = await download(cache, [...extras, ...tiles], job.pack.policy, step, signal);
      info.basemaps[i].stored = stored.size;
      info.basemaps[i].tiles = tiles.filter((url) => stored.has(url)).length;
      saveInfo(info); // interrompu ensuite, l'enregistrement dit quand même ce fond
    }
  } catch (error) {
    if (error instanceof DOMException && error.name === 'QuotaExceededError') throw new OfflineError('quota');
    throw error;
  }
  signal?.throwIfAborted();
  info.complete = true;
  saveInfo(info);
  return info;
}

function saveInfo(info: OfflineInfo): void {
  try {
    localStorage.setItem(INFO_KEY, JSON.stringify(info));
  } catch {
    // stockage bloqué : l'interface ne saura pas qu'un tracé est enregistré
  }
}

/** Demande au navigateur de ne pas effacer ces données quand la place manque. Vrai s'il l'a promis. */
async function requestPersistence(): Promise<boolean> {
  try {
    const storage = navigator.storage;
    if (!storage?.persist) return false;
    if (await storage.persisted?.()) return true;
    return (await storage.persist()) === true;
  } catch {
    return false;
  }
}

/** Vrai si le tracé enregistré est toujours dans le cache (le navigateur a pu effacer les données). */
export async function offlineDataPresent(base: string): Promise<boolean> {
  if (typeof caches === 'undefined') return false;
  try {
    return !!(await (await caches.open(OFFLINE_CACHE)).match(trackKey(base), IGNORE_VARY));
  } catch {
    return false;
  }
}

/**
 * Vrai si une coque du site est enregistrée en entier : sa liste (coque.json, écrite
 * en dernier par le Service Worker) est présente et chacun de ses fichiers aussi.
 */
export async function shellComplete(base: string): Promise<boolean> {
  const scope = new URL(base, location.href);
  for (const name of await caches.keys()) {
    if (!name.startsWith(SHELL_CACHE_PREFIX)) continue;
    try {
      const cache = await caches.open(name);
      const list = await cache.match(new URL('coque.json', scope).href, IGNORE_VARY);
      const files = list ? ((await list.json()) as { files?: unknown }).files : undefined;
      if (!Array.isArray(files) || files.length === 0) continue;
      const found = await Promise.all(files.map((file) => cache.match(new URL(String(file), scope).href, IGNORE_VARY)));
      if (found.every(Boolean)) return true;
    } catch {
      // cache illisible : on regarde le suivant
    }
  }
  return false;
}

/** Attend, à la première visite, que le Service Worker ait fini d'enregistrer la coque. */
async function waitForShell(base: string): Promise<boolean> {
  if (!import.meta.env.PROD) return true; // pas de Service Worker en développement
  if (await shellComplete(base)) return true;
  let timer: ReturnType<typeof setTimeout> | undefined;
  await Promise.race([navigator.serviceWorker.ready, new Promise((resolve) => (timer = setTimeout(resolve, SHELL_WAIT_MS)))]);
  clearTimeout(timer);
  return shellComplete(base);
}

/** Informations sur le tracé préparé, ou null. */
export function offlineInfo(): OfflineInfo | null {
  try {
    const raw = localStorage.getItem(INFO_KEY);
    if (!raw) return null;
    const info = JSON.parse(raw) as OfflineInfo;
    if (typeof info?.name !== 'string' || typeof info?.date !== 'string') return null;
    // Enregistrement d'une version précédente du site, sans édition des données : il est à refaire.
    if (!Array.isArray(info.archives)) info.archives = [];
    if (typeof info.generated !== 'string') info.generated = '';
    info.complete = info.complete === true;
    info.persisted = info.persisted === true;
    if (!Array.isArray(info.basemaps)) info.basemaps = [];
    return info;
  } catch {
    return null;
  }
}

/** Vrai si l'enregistrement a été fait avec une autre édition des données que ce manifest. */
export function offlineOutdated(info: OfflineInfo, manifest: Pick<Manifest, 'archives'>): boolean {
  const files = manifest.archives.map((archive) => archive.file);
  return files.length !== info.archives.length || files.some((file) => !info.archives.includes(file));
}

/** Octets d'une tuile de couverture enregistrée : undefined si elle n'a pas été enregistrée, null si elle est vide. */
export async function storedCoverageTile(base: string, file: string, z: number, x: number, y: number): Promise<ArrayBuffer | null | undefined> {
  if (typeof caches === 'undefined') return undefined;
  try {
    const cache = await caches.open(OFFLINE_CACHE);
    const response = await cache.match(coverageTileKey(base, file, z, x, y), IGNORE_VARY);
    if (!response) return undefined;
    if (response.headers.get('x-czb-vide') === '1') return null;
    return await response.arrayBuffer();
  } catch {
    return undefined;
  }
}

/**
 * Lecteur des tuiles de couverture : la tuile enregistrée pour le hors ligne si elle
 * existe (même archive, donc mêmes octets), sinon l'archive en ligne. Sans réseau ou
 * par réseau faible, un tracé préparé ne dépend donc pas du réseau. « stored » dit
 * si des tuiles de cette archive ont été enregistrées (évite des lectures inutiles).
 */
export function withStoredTiles(base: string, online: ArchiveReader, stored: (file: string) => boolean): ArchiveReader {
  return async (file, z, x, y, signal) => {
    if (COVERAGE_ZOOMS.includes(z) && stored(file)) {
      const tile = await storedCoverageTile(base, file, z, x, y);
      if (tile !== undefined) return tile ?? undefined;
    }
    return online(file, z, x, y, signal);
  };
}

/** Le tracé enregistré pour le hors ligne, ou null. */
export async function storedTrack(base: string): Promise<{ text: string; fileName: string } | null> {
  if (typeof caches === 'undefined') return null;
  try {
    const cache = await caches.open(OFFLINE_CACHE);
    const response = await cache.match(trackKey(base), IGNORE_VARY);
    if (!response) return null;
    const fileName = decodeURIComponent(response.headers.get('x-czb-nom') ?? 'trace.gpx');
    return { text: await response.text(), fileName };
  } catch {
    return null;
  }
}

/** Efface toutes les données hors ligne (tuiles, tracé). Les fichiers du site restent en cache. */
export async function clearOffline(): Promise<void> {
  try {
    localStorage.removeItem(INFO_KEY);
  } catch {
    // sans importance
  }
  if (typeof caches !== 'undefined') await caches.delete(OFFLINE_CACHE);
}

/** Enregistre le Service Worker (en production seulement). */
export function registerServiceWorker(base: string): void {
  if (!offlineSupported() || !import.meta.env.PROD) return;
  window.addEventListener('load', () => {
    navigator.serviceWorker.register(`${base}sw.js?delai=${NETWORK_TIMEOUT_MS}`, { scope: base }).catch((error) => {
      console.warn('Service Worker non enregistré :', error);
    });
  });
}
