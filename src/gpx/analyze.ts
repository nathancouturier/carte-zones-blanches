// Analyse d'un tracé : quel réseau sur chaque portion du parcours.
//
// 1. Le tracé est rééchantillonné tous les 20 m.
// 2. Pour chaque point, on lit au pixel près les tuiles du zoom maximal.
// 3. Les points sont classés (pas de couverture, limitée, bonne, très bonne,
//    hors zone) selon l'opérateur choisi, puis regroupés en zones blanches.
//
// Les valeurs brutes des pixels sont gardées : changer d'opérateur ou de
// service refait le classement sans rien relire.

import {
  ELEVATION_THRESHOLD_M,
  SAMPLING_CONCURRENCY,
  WHITE_ZONE_MERGE_GAP_M,
  WHITE_ZONE_MIN_LENGTH_M,
} from '../config';
import { LEVEL_NONE, LEVEL_UNKNOWN, SOURCE_ESTIMATED, TILE_SIZE, unpackCountry, unpackSourceType } from '../coverage/codec';
import type { LevelTables, ServiceId } from '../coverage/manifest';
import type { TileStore } from '../coverage/store';
import { lonLatToTilePixel, tileKey } from '../coverage/tilemath';
import { distance } from './geodesy';
import type { Sample } from './resample';

/** Classe d'un point : un niveau de 0 à 3, ou l'une des deux valeurs ci-dessous. */
export const CLASS_OUTSIDE = 254; // hors de la zone couverte par les données
export const CLASS_UNKNOWN = LEVEL_UNKNOWN; // pas de donnée pour ce service à cet endroit

/** Valeurs brutes lues dans les tuiles, un élément par point du tracé. */
export interface RawCoverage {
  data: Uint8Array; // canal R
  voice: Uint8Array; // canal G
  meta: Uint8Array; // canal B
  inside: Uint8Array; // 1 dans la zone couverte, 0 ailleurs
}

/** Lit dans les tuiles la valeur du pixel de chaque point. */
export async function sampleCoverage(
  samples: readonly Sample[],
  store: TileStore,
  onProgress?: (done: number, total: number) => void,
): Promise<RawCoverage> {
  const n = samples.length;
  const raw: RawCoverage = {
    data: new Uint8Array(n),
    voice: new Uint8Array(n),
    meta: new Uint8Array(n),
    inside: new Uint8Array(n),
  };
  // Points regroupés par tuile : chaque tuile n'est lue qu'une fois.
  const groups = new Map<string, { z: number; x: number; y: number; items: number[] }>();
  const offsets = new Int32Array(n).fill(-1);
  for (let i = 0; i < n; i++) {
    const tp = lonLatToTilePixel(samples[i].lon, samples[i].lat, store.maxZoom);
    if (!tp) continue;
    offsets[i] = (tp.py * TILE_SIZE + tp.px) * 4;
    const key = tileKey(tp.z, tp.x, tp.y);
    let group = groups.get(key);
    if (!group) {
      group = { z: tp.z, x: tp.x, y: tp.y, items: [] };
      groups.set(key, group);
    }
    group.items.push(i);
  }
  const queue = [...groups.values()];
  const total = queue.length;
  let done = 0;
  const worker = async (): Promise<void> => {
    for (;;) {
      const group = queue.pop();
      if (!group) return;
      const tile = await store.get(group.z, group.x, group.y);
      if (tile) {
        for (const i of group.items) {
          const o = offsets[i];
          raw.data[i] = tile[o];
          raw.voice[i] = tile[o + 1];
          raw.meta[i] = tile[o + 2];
          raw.inside[i] = tile[o + 3] !== 0 ? 1 : 0;
        }
      }
      done++;
      onProgress?.(done, total);
    }
  };
  await Promise.all(Array.from({ length: Math.min(SAMPLING_CONCURRENCY, Math.max(1, total)) }, worker));
  return raw;
}

/** Classe chaque point selon les tables de niveaux (opérateur choisi ou tous opérateurs). */
export function classify(raw: RawCoverage, tables: LevelTables, service: ServiceId): Uint8Array {
  const n = raw.inside.length;
  const classes = new Uint8Array(n);
  const channel = service === 'voice' ? raw.voice : raw.data;
  for (let i = 0; i < n; i++) {
    if (!raw.inside[i]) {
      classes[i] = CLASS_OUTSIDE;
      continue;
    }
    const table = tables[raw.meta[i] & 0x3f];
    classes[i] = table ? table[channel[i]] : CLASS_OUTSIDE;
  }
  return classes;
}

// ---------------------------------------------------------------------------
// Découpage du parcours
// ---------------------------------------------------------------------------

/**
 * Bornes de la portion de parcours représentée par chaque point : du milieu de
 * l'intervalle précédent au milieu du suivant. La somme des portions vaut la
 * longueur du parcours.
 */
export function sampleSpans(samples: readonly Sample[]): { lo: Float64Array; hi: Float64Array } {
  const n = samples.length;
  const lo = new Float64Array(n);
  const hi = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const d = samples[i].dist;
    lo[i] = i > 0 && samples[i - 1].seg === samples[i].seg ? (samples[i - 1].dist + d) / 2 : d;
    hi[i] = i < n - 1 && samples[i + 1].seg === samples[i].seg ? (samples[i + 1].dist + d) / 2 : d;
  }
  return { lo, hi };
}

export interface CoverageStats {
  /** Longueur par niveau (0 à 3), en mètres. */
  byLevel: [number, number, number, number];
  /** Longueur hors de la zone couverte par les données, exclue des pourcentages. */
  outside: number;
  /** Longueur sans donnée pour ce service, exclue des pourcentages. */
  unknown: number;
  /** Longueur prise en compte dans les pourcentages. */
  measured: number;
}

export function computeStats(samples: readonly Sample[], classes: Uint8Array): CoverageStats {
  const { lo, hi } = sampleSpans(samples);
  const stats: CoverageStats = { byLevel: [0, 0, 0, 0], outside: 0, unknown: 0, measured: 0 };
  for (let i = 0; i < samples.length; i++) {
    const length = hi[i] - lo[i];
    const c = classes[i];
    if (c === CLASS_OUTSIDE) stats.outside += length;
    else if (c === CLASS_UNKNOWN) stats.unknown += length;
    else {
      stats.byLevel[c] += length;
      stats.measured += length;
    }
  }
  return stats;
}

export interface WhiteZone {
  /** Numéro de la zone, à partir de 1. */
  index: number;
  /** Indices du premier et du dernier point de la zone. */
  first: number;
  last: number;
  /** Distances depuis le départ, en mètres. */
  start: number;
  end: number;
  length: number;
  /** Altitudes minimale et maximale dans la zone, ou null sans altitude. */
  eleMin: number | null;
  eleMax: number | null;
  /** Codes des pays traversés (canal B), dans l'ordre du parcours. */
  countries: number[];
  /** Vrai si une partie de la zone vient d'une source estimée. */
  estimated: boolean;
  startPoint: [number, number];
  endPoint: [number, number];
  /** Emprise : ouest, sud, est, nord. */
  bbox: [number, number, number, number];
}

export interface ZoneOptions {
  minLength?: number;
  mergeGap?: number;
}

/** Vrai si le parcours est interrompu entre les points i et i+1 (segments éloignés l'un de l'autre). */
function isBreak(samples: readonly Sample[], i: number, mergeGap: number): boolean {
  const a = samples[i];
  const b = samples[i + 1];
  if (a.seg === b.seg) return false;
  return distance(a.lon, a.lat, b.lon, b.lat) > mergeGap;
}

/**
 * Regroupe les points sans couverture en zones blanches.
 * - Deux zones séparées par moins de « mergeGap » mètres de couverture sont fusionnées.
 * - Une zone de moins de « minLength » mètres est ignorée.
 */
export function findWhiteZones(
  samples: readonly Sample[],
  classes: Uint8Array,
  raw: RawCoverage,
  options: ZoneOptions = {},
): WhiteZone[] {
  const minLength = options.minLength ?? WHITE_ZONE_MIN_LENGTH_M;
  const mergeGap = options.mergeGap ?? WHITE_ZONE_MERGE_GAP_M;
  const n = samples.length;
  const { lo, hi } = sampleSpans(samples);

  // 1. Suites de points consécutifs sans couverture.
  const runs: { first: number; last: number }[] = [];
  let start = -1;
  for (let i = 0; i < n; i++) {
    const white = classes[i] === LEVEL_NONE;
    if (white && start === -1) start = i;
    const endsHere = start !== -1 && (!white || i === n - 1 || isBreak(samples, i, mergeGap));
    if (endsHere) {
      runs.push({ first: start, last: white ? i : i - 1 });
      start = -1;
    }
  }

  // 2. Fusion des suites séparées par un court passage couvert.
  const merged: { first: number; last: number }[] = [];
  for (const run of runs) {
    const previous = merged[merged.length - 1];
    if (previous) {
      const gap = lo[run.first] - hi[previous.last];
      let broken = false;
      for (let i = previous.last; i < run.first && !broken; i++) broken = isBreak(samples, i, mergeGap);
      if (!broken && gap < mergeGap) {
        previous.last = run.last;
        continue;
      }
    }
    merged.push({ ...run });
  }

  // 3. On ne garde que les zones assez longues.
  const zones: WhiteZone[] = [];
  for (const run of merged) {
    const startDist = lo[run.first];
    const endDist = hi[run.last];
    const length = endDist - startDist;
    if (length < minLength) continue;
    let eleMin: number | null = null;
    let eleMax: number | null = null;
    let west = Infinity;
    let south = Infinity;
    let east = -Infinity;
    let north = -Infinity;
    const countries: number[] = [];
    let estimated = false;
    for (let i = run.first; i <= run.last; i++) {
      const s = samples[i];
      if (s.ele !== null) {
        eleMin = eleMin === null ? s.ele : Math.min(eleMin, s.ele);
        eleMax = eleMax === null ? s.ele : Math.max(eleMax, s.ele);
      }
      west = Math.min(west, s.lon);
      east = Math.max(east, s.lon);
      south = Math.min(south, s.lat);
      north = Math.max(north, s.lat);
      if (raw.inside[i]) {
        const country = unpackCountry(raw.meta[i]);
        if (country !== 0 && !countries.includes(country)) countries.push(country);
        if (classes[i] === LEVEL_NONE && unpackSourceType(raw.meta[i]) === SOURCE_ESTIMATED) estimated = true;
      }
    }
    zones.push({
      index: zones.length + 1,
      first: run.first,
      last: run.last,
      start: startDist,
      end: endDist,
      length,
      eleMin,
      eleMax,
      countries,
      estimated,
      startPoint: [samples[run.first].lon, samples[run.first].lat],
      endPoint: [samples[run.last].lon, samples[run.last].lat],
      bbox: [west, south, east, north],
    });
  }
  return zones;
}

/** Codes des pays traversés, dans l'ordre du parcours. */
export function countriesCrossed(raw: RawCoverage): number[] {
  const seen: number[] = [];
  let last = -1;
  for (let i = 0; i < raw.meta.length; i++) {
    if (!raw.inside[i]) continue;
    const country = unpackCountry(raw.meta[i]);
    if (country === last || country === 0) continue;
    last = country;
    if (!seen.includes(country)) seen.push(country);
  }
  return seen;
}

/** Vrai si au moins un point du parcours vient d'une source estimée. */
export function hasEstimatedData(raw: RawCoverage): boolean {
  for (let i = 0; i < raw.meta.length; i++) {
    if (raw.inside[i] && unpackSourceType(raw.meta[i]) === SOURCE_ESTIMATED) return true;
  }
  return false;
}

export interface ElevationGain {
  ascent: number;
  descent: number;
  min: number;
  max: number;
}

/**
 * Dénivelé positif et négatif cumulés. Les variations inférieures au seuil
 * sont ignorées, sinon le bruit du GPS gonfle le total.
 */
export function elevationGain(samples: readonly Sample[], threshold: number = ELEVATION_THRESHOLD_M): ElevationGain | null {
  let reference: number | null = null;
  let ascent = 0;
  let descent = 0;
  let min = Infinity;
  let max = -Infinity;
  let seg = -1;
  for (const s of samples) {
    if (s.ele === null) return null;
    min = Math.min(min, s.ele);
    max = Math.max(max, s.ele);
    if (reference === null || s.seg !== seg) {
      // Nouveau segment : on ne compte pas le saut d'altitude entre deux segments.
      reference = s.ele;
      seg = s.seg;
      continue;
    }
    const delta = s.ele - reference;
    if (delta >= threshold) {
      ascent += delta;
      reference = s.ele;
    } else if (delta <= -threshold) {
      descent -= delta;
      reference = s.ele;
    }
  }
  if (reference === null) return null;
  return { ascent, descent, min, max };
}
