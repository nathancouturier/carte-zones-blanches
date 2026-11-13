// Encodage des tuiles de couverture.
//
// Une tuile ne contient pas des couleurs mais des données :
//   R : internet mobile, 2 bits par emplacement d'opérateur (4 emplacements)
//   G : appels et SMS, même encodage
//   B : bits 0 à 3 = pays, bits 4 et 5 = type de source
//   A : 255 dans la zone couverte par les données, 0 ailleurs
//
// La signification des emplacements et des codes pays est donnée par le
// manifest.json : rien n'est codé en dur ici.

export const TILE_SIZE = 256;
export const SLOT_COUNT = 4;

/** Niveaux de couverture, du pire au meilleur. */
export const LEVEL_NONE = 0;
export const LEVEL_LIMITED = 1;
export const LEVEL_GOOD = 2;
export const LEVEL_VERY_GOOD = 3;
/** Pas de donnée pour ce service à cet endroit. */
export const LEVEL_UNKNOWN = 255;

export type Level = 0 | 1 | 2 | 3;

/** Types de source (bits 4 et 5 du canal B). */
export const SOURCE_OFFICIAL_OPERATOR = 0;
export const SOURCE_OFFICIAL_AGGREGATED = 1;
export const SOURCE_ESTIMATED = 2;

/** Assemble 4 niveaux (0 à 3) dans un octet : l'emplacement i occupe les bits 2i et 2i+1. */
export function packSlots(levels: readonly number[]): number {
  let byte = 0;
  for (let i = 0; i < SLOT_COUNT; i++) {
    const level = levels[i] ?? 0;
    if (!Number.isInteger(level) || level < 0 || level > 3) {
      throw new RangeError(`Niveau invalide pour l'emplacement ${i} : ${level}`);
    }
    byte |= level << (2 * i);
  }
  return byte;
}

/** Niveau (0 à 3) d'un emplacement dans un octet R ou G. */
export function unpackSlot(byte: number, slot: number): number {
  return (byte >> (2 * slot)) & 0b11;
}

export function unpackSlots(byte: number): [number, number, number, number] {
  return [byte & 3, (byte >> 2) & 3, (byte >> 4) & 3, (byte >> 6) & 3];
}

/** Assemble le canal B : code pays (0 à 15) et type de source (0 à 3). */
export function packMeta(country: number, sourceType: number): number {
  if (!Number.isInteger(country) || country < 0 || country > 15) {
    throw new RangeError(`Code pays invalide : ${country}`);
  }
  if (!Number.isInteger(sourceType) || sourceType < 0 || sourceType > 3) {
    throw new RangeError(`Type de source invalide : ${sourceType}`);
  }
  return (sourceType << 4) | country;
}

export function unpackCountry(b: number): number {
  return b & 0x0f;
}

export function unpackSourceType(b: number): number {
  return (b >> 4) & 0b11;
}

/** Clé « pays + type de source » : les 6 bits utiles du canal B. */
export function metaKey(b: number): number {
  return b & 0x3f;
}

export interface Pixel {
  /** Octet du service internet mobile. */
  data: number;
  /** Octet du service appels et SMS. */
  voice: number;
  country: number;
  sourceType: number;
  /** Faux hors de la zone couverte par les données. */
  inside: boolean;
}

/** Décode le pixel d'indice i (0 à 65 535) d'une tuile RGBA. */
export function readPixel(rgba: Uint8ClampedArray | Uint8Array, index: number): Pixel {
  const o = index * 4;
  const b = rgba[o + 2];
  return {
    data: rgba[o],
    voice: rgba[o + 1],
    country: unpackCountry(b),
    sourceType: unpackSourceType(b),
    inside: rgba[o + 3] !== 0,
  };
}

/** Écrit un pixel dans une tuile RGBA (sert aux tests et aux données de démonstration). */
export function writePixel(
  rgba: Uint8ClampedArray | Uint8Array,
  index: number,
  pixel: { data?: readonly number[]; voice?: readonly number[]; country: number; sourceType?: number } | null,
): void {
  const o = index * 4;
  if (!pixel) {
    rgba[o] = rgba[o + 1] = rgba[o + 2] = rgba[o + 3] = 0;
    return;
  }
  rgba[o] = packSlots(pixel.data ?? [0, 0, 0, 0]);
  rgba[o + 1] = packSlots(pixel.voice ?? [0, 0, 0, 0]);
  rgba[o + 2] = packMeta(pixel.country, pixel.sourceType ?? 0);
  rgba[o + 3] = 255;
}
