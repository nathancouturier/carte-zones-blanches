// GeoJSON du tracé pour l'affichage : une ligne par portion de même couverture.

import { LEVEL_VERY_GOOD } from '../coverage/codec';
import type { WhiteZone } from '../gpx/analyze';
import type { Sample } from '../gpx/resample';

export const EMPTY_COLLECTION: GeoJSON.FeatureCollection = { type: 'FeatureCollection', features: [] };

/**
 * Découpe le tracé en lignes d'aspect constant : classe de couverture (propriété
 * « c ») et couverture estimée ou non (« e », 1 pour une portion estimée, dessinée
 * en pointillé). « classes » peut être absent tant que l'analyse n'est pas faite :
 * le tracé est alors d'une seule couleur. « estimated » vaut 1 pour les points dont
 * la couverture vient d'une source estimée ; seuls ceux qui ont un niveau comptent.
 */
export function trackToGeoJson(samples: readonly Sample[], classes: Uint8Array | null, estimated: Uint8Array | null = null): GeoJSON.FeatureCollection {
  const features: GeoJSON.Feature[] = [];
  let coords: [number, number][] = [];
  let current = -1;
  let currentEstimated = 0;
  const flush = (): void => {
    if (coords.length >= 2) {
      features.push({
        type: 'Feature',
        properties: { c: current, e: currentEstimated },
        geometry: { type: 'LineString', coordinates: coords },
      });
    }
    coords = [];
  };
  for (let i = 0; i < samples.length; i++) {
    const s = samples[i];
    const c = classes ? classes[i] : -1;
    const e = estimated?.[i] && c >= 0 && c <= LEVEL_VERY_GOOD ? 1 : 0;
    const newSegment = i > 0 && samples[i - 1].seg !== s.seg;
    if (i === 0 || newSegment) {
      flush();
      current = c;
      currentEstimated = e;
    } else if (c !== current || e !== currentEstimated) {
      // La portion précédente va jusqu'à ce point : pas de trou entre deux couleurs.
      coords.push([s.lon, s.lat]);
      flush();
      current = c;
      currentEstimated = e;
    }
    coords.push([s.lon, s.lat]);
  }
  flush();
  return { type: 'FeatureCollection', features };
}

/** Ligne de la zone blanche sélectionnée, pour la surbrillance. */
export function zoneToGeoJson(samples: readonly Sample[], zone: WhiteZone | null): GeoJSON.FeatureCollection {
  if (!zone) return EMPTY_COLLECTION;
  const lines: [number, number][][] = [];
  let line: [number, number][] = [];
  for (let i = zone.first; i <= zone.last; i++) {
    if (i > zone.first && samples[i - 1].seg !== samples[i].seg) {
      if (line.length >= 2) lines.push(line);
      line = [];
    }
    line.push([samples[i].lon, samples[i].lat]);
  }
  if (line.length >= 2) lines.push(line);
  if (lines.length === 0) return EMPTY_COLLECTION;
  return {
    type: 'FeatureCollection',
    features: [{ type: 'Feature', properties: {}, geometry: { type: 'MultiLineString', coordinates: lines } }],
  };
}

/** Emprise d'un tracé : ouest, sud, est, nord. */
export function samplesBounds(samples: readonly Sample[]): [number, number, number, number] | null {
  if (samples.length === 0) return null;
  let west = Infinity;
  let south = Infinity;
  let east = -Infinity;
  let north = -Infinity;
  for (const s of samples) {
    west = Math.min(west, s.lon);
    east = Math.max(east, s.lon);
    south = Math.min(south, s.lat);
    north = Math.max(north, s.lat);
  }
  return [west, south, east, north];
}
