// Distances sur la Terre.

const EARTH_RADIUS_M = 6371008.8; // rayon moyen
const RAD = Math.PI / 180;

/** Distance géodésique (grand cercle) entre deux points, en mètres. */
export function distance(lon1: number, lat1: number, lon2: number, lat2: number): number {
  const dLat = (lat2 - lat1) * RAD;
  const dLon = (lon2 - lon1) * RAD;
  const a =
    Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * RAD) * Math.cos(lat2 * RAD) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** Point situé à la fraction t (0 à 1) entre deux points proches. */
export function interpolate(
  lon1: number,
  lat1: number,
  lon2: number,
  lat2: number,
  t: number,
): [number, number] {
  return [lon1 + (lon2 - lon1) * t, lat1 + (lat2 - lat1) * t];
}
