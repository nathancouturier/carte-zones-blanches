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
//   4. les tuiles du fond de carte affiché, si son fournisseur l'autorise, dans la
//      limite qu'il tolère (voir src/map/basemaps.ts et docs/sources.md).
// Un seul tracé à la fois : ce qui ne lui sert pas est effacé au début. L'information
// sur l'enregistrement est écrite dès le début, marquée incomplète jusqu'à la fin :
// interrompu, annulé ou en échec, il reste visible et peut être repris ou supprimé.
// Tout reste dans le navigateur (Cache API). Rien n'est envoyé.

import { NETWORK_TIMEOUT_MS } from '../config';
import { archiveForTile, type Manifest } from '../coverage/manifest';
import type { ArchiveReader } from '../coverage/store';
import type { Sample } from '../gpx/resample';
import type { BasemapPack, PreloadPolicy } from '../map/basemaps';
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
const CONCURRENCY = 4;
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
  /** Identifiant du fond préchargé, ou null si aucun. */
  basemap: string | null;
  coverageTiles: number;
  /** Nombre de tuiles de fond effectivement enregistrées. */
  basemapTiles: number;
  /** Nombre de requêtes de fond qui ont échoué. */
  failed: number;
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
  basemap: BasemapPack | null;
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

async function pool<T>(items: readonly T[], worker: (item: T) => Promise<void>, signal?: AbortSignal): Promise<void> {
  let next = 0;
  const run = async (): Promise<void> => {
    while (next < items.length) {
      if (signal?.aborted) throw new DOMException('Annulé', 'AbortError');
      const item = items[next++];
      await worker(item);
    }
  };
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, Math.max(1, items.length)) }, run));
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
  const plan = options.basemap ? basemapCorridor(options.samples, options.basemap.policy) : { tiles: [], maxZoom: 0, reduced: false };
  const template = options.basemap?.tileTemplates[0];
  const basemapUrls = template ? plan.tiles.map((tile) => tileUrl(template, tile)) : [];
  const extras = options.basemap?.policy.allowed ? options.basemap.extraUrls : [];
  const info: OfflineInfo = {
    name: options.trackName,
    date: new Date().toISOString(),
    complete: false,
    persisted,
    archives: manifest.archives.map((archive) => archive.file),
    generated: manifest.generated,
    basemap: options.basemap?.policy.allowed ? options.basemap.id : null,
    coverageTiles: coverage.length,
    basemapTiles: 0,
    failed: 0,
  };
  // Écrite avant toute donnée : même interrompu, l'enregistrement reste visible, donc supprimable.
  saveInfo(info);

  const cache = await caches.open(OFFLINE_CACHE);
  // Un seul tracé à la fois : ce qui ne sert pas à celui-ci (tracé précédent, autre édition des
  // données) est effacé ; ce qui resservira est gardé (mise à jour, reprise après une coupure).
  const keep = new Set([trackKey(base), manifestKey(base), ...coverage.map((tile) => tile.key), ...extras, ...basemapUrls].map((url) => new URL(url, location.href).href));
  for (const request of await cache.keys()) if (!keep.has(request.url)) await cache.delete(request);

  const total = 1 + coverage.length + basemapUrls.length + extras.length;
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
          const bytes = await options.readArchive(tile.file, tile.z, tile.x, tile.y);
          const headers = { 'content-type': 'application/octet-stream', 'x-czb-vide': bytes ? '0' : '1' };
          await cache.put(tile.key, new Response(bytes ?? new ArrayBuffer(0), { headers }));
        }
        step();
      },
      signal,
    );

    // 4. Fond de carte : seulement si le fournisseur l'autorise.
    await pool(
      [...extras.map((url) => ({ url, tile: false })), ...basemapUrls.map((url) => ({ url, tile: true }))],
      async ({ url, tile }) => {
        try {
          let stored = !!(await cache.match(url, IGNORE_VARY));
          if (!stored) {
            const response = await fetch(url, { mode: 'cors', credentials: 'omit', signal });
            if (response.ok) {
              await cache.put(url, response);
              stored = true;
            }
          }
          if (!stored) info.failed++;
          else if (tile) info.basemapTiles++;
        } catch (error) {
          if (error instanceof DOMException && (error.name === 'AbortError' || error.name === 'QuotaExceededError')) throw error;
          info.failed++;
        }
        step();
      },
      signal,
    );
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
  return async (file, z, x, y) => {
    if (COVERAGE_ZOOMS.includes(z) && stored(file)) {
      const tile = await storedCoverageTile(base, file, z, x, y);
      if (tile !== undefined) return tile ?? undefined;
    }
    return online(file, z, x, y);
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
