// Recolorisation d'une tuile de données selon les réglages de l'interface.
//
// Entrée : la tuile décodée (R, G, B, A = données). Sortie : une image RGBA
// prête à afficher. Par défaut seuls les problèmes sont dessinés (pas de
// couverture en rouge, couverture limitée en orange). Les zones estimées sont
// hachurées pour qu'on les distingue des données officielles.

import {
  LEVEL_GOOD,
  LEVEL_LIMITED,
  LEVEL_NONE,
  LEVEL_UNKNOWN,
  LEVEL_VERY_GOOD,
  SOURCE_ESTIMATED,
  TILE_SIZE,
} from './codec';
import type { LevelTables, ServiceId } from './manifest';

export type Rgba = readonly [number, number, number, number];

/** Couleurs des niveaux (opacité comprise, avant le curseur d'opacité de la couche). */
export const LEVEL_COLORS: Record<number, Rgba> = {
  [LEVEL_NONE]: [214, 40, 40, 215],
  [LEVEL_LIMITED]: [245, 130, 0, 205],
  [LEVEL_GOOD]: [124, 190, 80, 150],
  [LEVEL_VERY_GOOD]: [30, 130, 70, 150],
};

/** Mêmes couleurs, opaques, pour la légende et le tracé GPX. */
export const LEVEL_SOLID: Record<number, string> = {
  [LEVEL_NONE]: '#d62828',
  [LEVEL_LIMITED]: '#f58200',
  [LEVEL_GOOD]: '#5fae3c',
  [LEVEL_VERY_GOOD]: '#1e8246',
};

export interface RenderSettings {
  service: ServiceId;
  /** Vrai : dessiner aussi la bonne et la très bonne couverture, en vert. */
  showAll: boolean;
}

/** Période des hachures des zones estimées, en pixels de tuile. */
const HATCH_PERIOD = 8;
const HATCH_WIDTH = 3;
/** Part de l'opacité gardée sur les bandes claires des hachures. */
const HATCH_ALPHA = 0.35;

/**
 * Dessine une tuile de données dans « out » (RGBA, même taille).
 * Renvoie vrai si au moins un pixel est visible.
 */
export function renderTile(
  data: Uint8ClampedArray | Uint8Array,
  tables: LevelTables,
  settings: RenderSettings,
  out: Uint8ClampedArray,
  size: number = TILE_SIZE,
): boolean {
  const channel = settings.service === 'voice' ? 1 : 0;
  const minHidden = settings.showAll ? 4 : LEVEL_GOOD;
  let visible = false;
  let lastKey = -1;
  let table: Uint8Array | null = null;
  let estimated = false;
  for (let i = 0, o = 0; i < size * size; i++, o += 4) {
    if (data[o + 3] === 0) {
      out[o] = out[o + 1] = out[o + 2] = out[o + 3] = 0;
      continue;
    }
    const key = data[o + 2] & 0x3f;
    if (key !== lastKey) {
      lastKey = key;
      table = tables[key] ?? null;
      estimated = ((key >> 4) & 3) === SOURCE_ESTIMATED;
    }
    const level = table ? table[data[o + channel]] : LEVEL_UNKNOWN;
    if (level === LEVEL_UNKNOWN || level >= minHidden) {
      out[o] = out[o + 1] = out[o + 2] = out[o + 3] = 0;
      continue;
    }
    const color = LEVEL_COLORS[level];
    out[o] = color[0];
    out[o + 1] = color[1];
    out[o + 2] = color[2];
    let alpha = color[3];
    if (estimated) {
      const x = i % size;
      const y = (i / size) | 0;
      if ((x + y) % HATCH_PERIOD < HATCH_WIDTH) alpha = Math.round(alpha * HATCH_ALPHA);
    }
    out[o + 3] = alpha;
    visible = true;
  }
  return visible;
}
