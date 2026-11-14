// Mode hors ligne pour un tracé.
//
// « Préparer le hors ligne » enregistre dans le navigateur, pour le tracé chargé :
//   1. les fichiers du site ;
//   2. les tuiles de couverture du couloir du tracé (lues dans les archives PMTiles) ;
//   3. les tuiles du fond de carte affiché, si son fournisseur l'autorise, dans la
//      limite qu'il tolère (voir src/map/basemaps.ts et docs/sources.md) ;
//   4. le GPX lui-même, pour le retrouver sans réseau.
// Tout reste dans le navigateur (Cache API). Rien n'est envoyé.

import type { Sample } from '../gpx/resample';
import type { BasemapPack, PreloadPolicy } from '../map/basemaps';
import { corridorTiles, planCorridor, tileUrl, type TileId } from './corridor';

/** Doit rester identique à HORS_LIGNE dans public/sw.js. */
export const OFFLINE_CACHE = 'czb-hors-ligne-v1';
const SHELL_CACHE = 'czb-coque-v1';
const INFO_KEY = 'czb.horsLigne';
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
  const shell = shellUrls(base);
  const total = coverage.length + basemapUrls.length + extras.length + shell.length + 1;
  let done = 0;
  const step = (): void => options.onProgress(++done, total);
  options.onProgress(0, total);

  // 1. Fichiers du site.
  const shellCache = await caches.open(SHELL_CACHE);
  await pool(
    shell,
    async (url) => {
      try {
        const response = await fetch(url, { cache: 'no-cache', signal: options.signal });
        if (response.ok) await shellCache.put(url, response);
      } catch {
        // un fichier secondaire manquant n'empêche pas le reste
      }
      step();
    },
    options.signal,
  );

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

  // 4. Le tracé lui-même.
  await cache.put(
    trackKey(base),
    new Response(options.gpxText, { headers: { 'content-type': 'application/gpx+xml', 'x-czb-nom': encodeURIComponent(options.fileName) } }),
  );
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

/** Fichiers du site déjà chargés par la page : ce sont eux qu'il faut pour redémarrer sans réseau. */
function shellUrls(base: string): string[] {
  const origin = location.origin;
  const urls = new Set<string>([new URL(base, location.href).href, new URL(`${base}data/manifest.json`, location.href).href]);
  for (const entry of performance.getEntriesByType('resource')) {
    try {
      const url = new URL(entry.name);
      if (url.origin !== origin) continue;
      if (url.pathname.endsWith('.pmtiles') || url.pathname.includes('/hors-ligne/')) continue;
      url.hash = '';
      urls.add(url.href);
    } catch {
      // adresse illisible : on passe
    }
  }
  return [...urls];
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
    navigator.serviceWorker.register(`${base}sw.js`, { scope: base }).catch((error) => {
      console.warn('Service Worker non enregistré :', error);
    });
  });
}
