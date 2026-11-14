// Mode hors ligne pour un tracé.
//
// « Préparer le hors ligne » enregistre dans le navigateur, pour le tracé chargé :
//   1. rien pour le site lui-même : le Service Worker en a enregistré la coque
//      entière à son installation (public/sw.js) ; on vérifie seulement qu'elle
//      est complète, sans quoi rien ne s'ouvrirait sans réseau ;
//   2. les tuiles de couverture du couloir du tracé (lues dans les archives PMTiles) ;
//   3. les tuiles du fond de carte affiché, si son fournisseur l'autorise, dans la
//      limite qu'il tolère (voir src/map/basemaps.ts et docs/sources.md) ;
//   4. le GPX lui-même et le manifest des données, pour les retrouver sans réseau.
// Tout reste dans le navigateur (Cache API). Rien n'est envoyé.

import { NETWORK_TIMEOUT_MS } from '../config';
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
  /** Manifest des données utilisé par la page, en JSON : il accompagne les tuiles de couverture enregistrées. */
  manifestJson: string;
  /** Lit les octets d'une tuile de couverture, undefined si elle n'existe pas. */
  readCoverageTile: (z: number, x: number, y: number) => Promise<ArrayBuffer | undefined>;
  coverageMaxZoom: number;
  basemap: BasemapPack | null;
  onProgress: (done: number, total: number) => void;
  signal?: AbortSignal;
}

export function offlineSupported(): boolean {
  return typeof caches !== 'undefined' && typeof navigator !== 'undefined' && 'serviceWorker' in navigator;
}

/** Adresse sous laquelle une tuile de couverture est enregistrée. */
export function coverageTileKey(base: string, z: number, x: number, y: number): string {
  return new URL(`${base}hors-ligne/couverture/${z}/${x}/${y}`, location.href).href;
}

function trackKey(base: string): string {
  return new URL(`${base}hors-ligne/trace.gpx`, location.href).href;
}

/** Adresse du manifest des données : sa copie enregistrée est servie par le Service Worker à la même adresse. */
function manifestKey(base: string): string {
  return new URL(`${base}data/manifest.json`, location.href).href;
}

/** Erreur de préparation dont la cause est expliquée à l'utilisateur (clé de traduction offline.error.<code>). */
export class OfflineError extends Error {
  constructor(readonly code: 'shell') {
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
  const cache = await caches.open(OFFLINE_CACHE);
  const coverage = coverageCorridor(options.samples, options.coverageMaxZoom);
  const plan = options.basemap ? basemapCorridor(options.samples, options.basemap.policy) : { tiles: [], maxZoom: 0, reduced: false };
  const template = options.basemap?.tileTemplates[0];
  const basemapUrls = template ? plan.tiles.map((tile) => tileUrl(template, tile)) : [];
  const extras = options.basemap?.policy.allowed ? options.basemap.extraUrls : [];
  const total = coverage.length + basemapUrls.length + extras.length + 1;
  let done = 0;
  const step = (): void => options.onProgress(++done, total);
  options.onProgress(0, total);

  // 1. La coque du site, enregistrée par le Service Worker : sans elle, rien ne s'ouvrirait sans réseau.
  if (!(await waitForShell(base))) throw new OfflineError('shell');

  // 2. Tuiles de couverture : une entrée par tuile, vide si la tuile n'existe pas.
  await pool(
    coverage,
    async (tile) => {
      const bytes = await options.readCoverageTile(tile.z, tile.x, tile.y);
      const headers = { 'content-type': 'application/octet-stream', 'x-czb-vide': bytes ? '0' : '1' };
      await cache.put(coverageTileKey(base, tile.z, tile.x, tile.y), new Response(bytes ?? new ArrayBuffer(0), { headers }));
      step();
    },
    options.signal,
  );

  // 3. Fond de carte : seulement si le fournisseur l'autorise.
  let failed = 0;
  let storedTiles = 0;
  await pool(
    [...extras.map((url) => ({ url, tile: false })), ...basemapUrls.map((url) => ({ url, tile: true }))],
    async ({ url, tile }) => {
      try {
        let stored = !!(await cache.match(url, IGNORE_VARY));
        if (!stored) {
          const response = await fetch(url, { mode: 'cors', credentials: 'omit', signal: options.signal });
          if (response.ok) {
            await cache.put(url, response);
            stored = true;
          }
        }
        if (!stored) failed++;
        else if (tile) storedTiles++;
      } catch (error) {
        if (error instanceof DOMException && error.name === 'AbortError') throw error;
        failed++;
      }
      step();
    },
    options.signal,
  );

  // 4. Le tracé lui-même, et le manifest qui va avec les tuiles de couverture enregistrées.
  await cache.put(
    trackKey(base),
    new Response(options.gpxText, { headers: { 'content-type': 'application/gpx+xml', 'x-czb-nom': encodeURIComponent(options.fileName) } }),
  );
  await cache.put(manifestKey(base), new Response(options.manifestJson, { headers: { 'content-type': 'application/json', [LOCAL_COPY_HEADER]: '1' } }));
  step();

  const info: OfflineInfo = {
    name: options.trackName,
    date: new Date().toISOString(),
    basemap: options.basemap?.policy.allowed ? options.basemap.id : null,
    coverageTiles: coverage.length,
    basemapTiles: storedTiles,
    failed,
  };
  try {
    localStorage.setItem(INFO_KEY, JSON.stringify(info));
  } catch {
    // sans importance : l'information sert seulement à l'affichage
  }
  // On demande au navigateur de ne pas effacer ces données s'il manque de place.
  try {
    await navigator.storage?.persist?.();
  } catch {
    // facultatif
  }
  return info;
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
    return typeof info?.name === 'string' && typeof info?.date === 'string' ? info : null;
  } catch {
    return null;
  }
}

/** Octets d'une tuile de couverture enregistrée : undefined si elle n'a pas été enregistrée, null si elle est vide. */
export async function storedCoverageTile(base: string, z: number, x: number, y: number): Promise<ArrayBuffer | null | undefined> {
  if (typeof caches === 'undefined') return undefined;
  try {
    const cache = await caches.open(OFFLINE_CACHE);
    const response = await cache.match(coverageTileKey(base, z, x, y), IGNORE_VARY);
    if (!response) return undefined;
    if (response.headers.get('x-czb-vide') === '1') return null;
    return await response.arrayBuffer();
  } catch {
    return undefined;
  }
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
