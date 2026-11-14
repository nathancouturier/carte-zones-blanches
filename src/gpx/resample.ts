// Rééchantillonnage d'un tracé à pas constant.

import { RESAMPLE_STEP_M } from '../config';
import { distance, interpolate } from './geodesy';
import type { TrackPoint } from './parse';

export interface Sample {
  lon: number;
  lat: number;
  ele: number | null;
  /** Distance parcourue depuis le départ, en mètres (les sauts entre segments ne comptent pas). */
  dist: number;
  /** Indice du segment d'origine. */
  seg: number;
}

/**
 * Altitudes des points d'un segment, les manquantes interpolées (selon la
 * distance parcourue) entre les deux points connus les plus proches. Avant le
 * premier point connu et après le dernier, l'altitude reste inconnue : on ne
 * l'invente pas.
 */
function fillElevations(segment: readonly TrackPoint[]): (number | null)[] {
  const ele = segment.map((p) => p.ele);
  // Distance de chaque point depuis le début du segment.
  const along = [0];
  for (let i = 1; i < segment.length; i++) {
    along.push(along[i - 1] + distance(segment[i - 1].lon, segment[i - 1].lat, segment[i].lon, segment[i].lat));
  }
  let previous = -1; // dernier point dont l'altitude est connue
  for (let i = 0; i < segment.length; i++) {
    const to = ele[i];
    if (to === null) continue;
    const from = previous >= 0 ? ele[previous] : null;
    if (from !== null) {
      const span = along[i] - along[previous];
      for (let j = previous + 1; j < i; j++) ele[j] = from + (to - from) * (span > 0 ? (along[j] - along[previous]) / span : 0);
    }
    previous = i;
  }
  return ele;
}

/**
 * Place un point tous les « step » mètres le long de chaque segment, plus le
 * dernier point du segment. Les distances sont géodésiques.
 */
export function resample(segments: readonly TrackPoint[][], step: number = RESAMPLE_STEP_M): Sample[] {
  if (!(step > 0)) throw new RangeError('Le pas doit être positif');
  const samples: Sample[] = [];
  let offset = 0;
  segments.forEach((segment, seg) => {
    if (segment.length === 0) return;
    const elevations = fillElevations(segment);
    const first = segment[0];
    samples.push({ lon: first.lon, lat: first.lat, ele: elevations[0], dist: offset, seg });
    let travelled = 0; // distance depuis le début du segment
    let next = step; // distance du prochain point à placer
    for (let i = 1; i < segment.length; i++) {
      const a = segment[i - 1];
      const b = segment[i];
      const length = distance(a.lon, a.lat, b.lon, b.lat);
      if (length === 0) continue;
      const eleA = elevations[i - 1];
      const eleB = elevations[i];
      while (next <= travelled + length) {
        const t = (next - travelled) / length;
        const [lon, lat] = interpolate(a.lon, a.lat, b.lon, b.lat, t);
        const ele = eleA !== null && eleB !== null ? eleA + (eleB - eleA) * t : null;
        samples.push({ lon, lat, ele, dist: offset + next, seg });
        next += step;
      }
      travelled += length;
    }
    const last = segment[segment.length - 1];
    const lastSample = samples[samples.length - 1];
    // On ajoute l'arrivée du segment, sauf si un point vient d'y être placé.
    if (offset + travelled - lastSample.dist > 0.01) {
      samples.push({ lon: last.lon, lat: last.lat, ele: elevations[segment.length - 1], dist: offset + travelled, seg });
    }
    offset += travelled;
  });
  return samples;
}

/** Longueur totale du parcours, en mètres. */
export function trackLength(segments: readonly TrackPoint[][]): number {
  let total = 0;
  for (const segment of segments) {
    for (let i = 1; i < segment.length; i++) {
      total += distance(segment[i - 1].lon, segment[i - 1].lat, segment[i].lon, segment[i].lat);
    }
  }
  return total;
}
