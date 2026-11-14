// Profil altimétrique du tracé, coloré selon la couverture.
//
// Chaque colonne du graphique prend la couleur de la pire couverture rencontrée
// sur la portion qu'elle représente : une courte zone blanche reste visible même
// sur un très long parcours. Comme sur la carte et dans le rapport, les portions
// dont la couverture est estimée sont hachurées, et dites « estimées » au survol.
// Le profil se parcourt aussi au clavier (curseur de type « slider » : flèches,
// pages, Début et Fin) et se résume pour les lecteurs d'écran.

import { LEVEL_GOOD, LEVEL_LIMITED, LEVEL_NONE, LEVEL_VERY_GOOD, SOURCE_ESTIMATED, unpackSourceType } from '../coverage/codec';
import { LEVEL_SOLID } from '../coverage/render';
import { CLASS_OUTSIDE, CLASS_UNKNOWN, computeStats, enoughElevation, type RawCoverage } from '../gpx/analyze';
import { LEVEL_KEYS } from '../gpx/report';
import type { Sample } from '../gpx/resample';
import { formatKm, formatNumber, formatPercent, t } from '../i18n';

const SVG_NS = 'http://www.w3.org/2000/svg';
const WIDTH = 600;
const HEIGHT = 150;
const PAD = { top: 8, right: 4, bottom: 4, left: 4 };
/** Nombre maximal de colonnes dessinées. */
const MAX_COLUMNS = 300;
const NEUTRAL = '#7a8794';

export interface ProfileColumn {
  /** Indices du premier et du dernier point représentés. */
  first: number;
  last: number;
  /** Distances de début et de fin, en mètres. */
  start: number;
  end: number;
  /** Altitudes au début et à la fin de la colonne, null là où le GPX n'en donne pas. */
  eleStart: number | null;
  eleEnd: number | null;
  /** Classe de couverture retenue : la pire de la portion. */
  cls: number;
  /** Vrai si la couverture d'au moins un point de la portion vient d'une source estimée. */
  estimated: boolean;
}

/** 1 pour les points dont la couverture vient d'une source estimée, 0 sinon. */
export function estimatedFlags(raw: Pick<RawCoverage, 'meta' | 'inside'>): Uint8Array {
  const flags = new Uint8Array(raw.meta.length);
  for (let i = 0; i < flags.length; i++) flags[i] = raw.inside[i] && unpackSourceType(raw.meta[i]) === SOURCE_ESTIMATED ? 1 : 0;
  return flags;
}

/** Ordre de gravité : pas de couverture d'abord, puis limitée, puis hors zone, puis le reste. */
function severity(cls: number): number {
  switch (cls) {
    case LEVEL_NONE:
      return 0;
    case LEVEL_LIMITED:
      return 1;
    case CLASS_OUTSIDE:
    case CLASS_UNKNOWN:
      return 2;
    case LEVEL_GOOD:
      return 3;
    case LEVEL_VERY_GOOD:
      return 4;
    default:
      return 5; // pas encore analysé
  }
}

/**
 * Regroupe les points du tracé en colonnes de largeur égale en distance.
 * Renvoie un tableau vide si trop peu de points ont une altitude.
 */
export function profileColumns(
  samples: readonly Sample[],
  classes: Uint8Array | null,
  maxColumns: number = MAX_COLUMNS,
  estimated: Uint8Array | null = null,
): ProfileColumn[] {
  const n = samples.length;
  if (n < 2 || !enoughElevation(samples)) return [];
  const total = samples[n - 1].dist;
  if (!(total > 0)) return [];
  const count = Math.max(1, Math.min(maxColumns, n - 1));
  const width = total / count;
  const columns: ProfileColumn[] = [];
  let i = 0;
  for (let c = 0; c < count; c++) {
    const limit = c === count - 1 ? Infinity : (c + 1) * width;
    const first = i;
    let cls = classes ? classes[i] : -1;
    let partlyEstimated = false;
    // La colonne va jusqu'au premier point situé au-delà de sa limite, pour que les colonnes se touchent.
    // Comme sur la carte, chaque intervalle prend la couleur de son point de départ : un point n'est donc
    // compté que dans une seule colonne (sauf le tout dernier, rattaché à la dernière).
    while (i < n - 1 && samples[i].dist < limit) {
      const here = classes ? classes[i] : -1;
      if (severity(here) < severity(cls)) cls = here;
      if (estimated?.[i]) partlyEstimated = true;
      i++;
    }
    if (i === first) continue;
    if (i === n - 1 && classes && severity(classes[i]) < severity(cls)) cls = classes[i];
    if (i === n - 1 && estimated?.[i]) partlyEstimated = true;
    columns.push({
      first,
      last: i,
      start: samples[first].dist,
      end: samples[i].dist,
      eleStart: samples[first].ele,
      eleEnd: samples[i].ele,
      cls,
      estimated: partlyEstimated,
    });
    if (i >= n - 1) break;
  }
  return columns;
}

function colorOf(cls: number): string {
  return LEVEL_SOLID[cls] ?? NEUTRAL;
}

/** Ce que dit le profil d'un point : km, altitude, couverture, et « estimée » le cas échéant. */
export function profilePointText(sample: Sample, cls: number, estimated: boolean): string {
  const km = formatKm(sample.dist);
  const parts = [sample.ele === null ? t('profile.atNoElevation', { km }) : t('profile.at', { km, ele: formatNumber(Math.round(sample.ele)) })];
  if (LEVEL_KEYS[cls]) parts.push(t(LEVEL_KEYS[cls]));
  else if (cls === CLASS_OUTSIDE) parts.push(t('profile.outside'));
  else if (cls === CLASS_UNKNOWN) parts.push(t('profile.unknown'));
  if (estimated && LEVEL_KEYS[cls]) parts.push(t('report.zoneEstimated'));
  return parts.join(', ');
}

/** Nouvelle position du curseur après une touche (1 % du tracé par flèche, 10 % par page), ou null pour une autre touche. */
export function profileKeyIndex(key: string, index: number, count: number): number | null {
  const last = count - 1;
  const step = Math.max(1, Math.round(last / 100));
  const page = Math.max(1, Math.round(last / 10));
  switch (key) {
    case 'ArrowRight':
    case 'ArrowUp':
      return Math.min(last, index + step);
    case 'ArrowLeft':
    case 'ArrowDown':
      return Math.max(0, index - step);
    case 'PageUp':
      return Math.min(last, index + page);
    case 'PageDown':
      return Math.max(0, index - page);
    case 'Home':
      return 0;
    case 'End':
      return last;
    default:
      return null;
  }
}

/** Résumé pour les lecteurs d'écran : la part du parcours sans couverture, que seules les couleurs montrent. */
export function profileSummary(samples: readonly Sample[], classes: Uint8Array | null): string {
  if (!classes) return '';
  const stats = computeStats(samples, classes);
  if (!(stats.measured > 0)) return '';
  return t('profile.summary', { share: formatPercent(stats.byLevel[LEVEL_NONE] / stats.measured) });
}

/** Les motifs de hachures sont désignés par un identifiant, unique dans la page. */
let hatchSeq = 0;

function svg<K extends keyof SVGElementTagNameMap>(tag: K, attrs: Record<string, string | number>): SVGElementTagNameMap[K] {
  const el = document.createElementNS(SVG_NS, tag);
  for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, String(value));
  return el;
}

export interface ProfileOptions {
  samples: readonly Sample[];
  classes: Uint8Array | null;
  /** Valeurs lues dans les tuiles, qui disent où la couverture est estimée ; null avant l'analyse. */
  raw?: Pick<RawCoverage, 'meta' | 'inside'> | null;
  /** Appelé quand le doigt ou la souris survole le profil : indice du point, ou null en sortant. */
  onHover: (index: number | null) => void;
}

/** Construit le profil. Renvoie null si trop peu de points ont une altitude. */
export function elevationProfile(options: ProfileOptions): HTMLElement | null {
  const { samples, classes } = options;
  const estimated = options.raw ? estimatedFlags(options.raw) : null;
  const columns = profileColumns(samples, classes, MAX_COLUMNS, estimated);
  if (columns.length === 0) return null;
  let min = Infinity;
  let max = -Infinity;
  for (const s of samples) {
    if (s.ele === null) continue;
    if (s.ele < min) min = s.ele;
    if (s.ele > max) max = s.ele;
  }
  // Une marge verticale évite un profil plat écrasé sur le bord, et un relief minuscule exagéré.
  const span = Math.max(max - min, 50);
  const low = min - span * 0.08;
  const high = min + span * 1.05;
  const total = samples[samples.length - 1].dist;
  const innerW = WIDTH - PAD.left - PAD.right;
  const innerH = HEIGHT - PAD.top - PAD.bottom;
  const x = (dist: number): number => PAD.left + (dist / total) * innerW;
  const y = (ele: number): number => PAD.top + (1 - (ele - low) / (high - low)) * innerH;
  const base = HEIGHT - PAD.bottom;

  const label = t('profile.label', { min: formatNumber(Math.round(min)), max: formatNumber(Math.round(max)) });
  const summary = profileSummary(samples, classes);
  // Un curseur au clavier : sa valeur est le point du tracé, dite en km, altitude et couverture.
  const root = svg('svg', {
    viewBox: `0 0 ${WIDTH} ${HEIGHT}`,
    preserveAspectRatio: 'none',
    class: 'profile__svg',
    role: 'slider',
    tabindex: 0,
    'aria-label': summary ? `${label}. ${summary}` : label,
    'aria-valuemin': 0,
    'aria-valuemax': samples.length - 1,
    'aria-valuenow': 0,
    'aria-valuetext': profilePointText(samples[0], classes ? classes[0] : -1, estimated?.[0] === 1),
  });
  const hatchId = `profil-hachures-${++hatchSeq}`;
  const anyEstimated = columns.some((column) => column.estimated);
  if (anyEstimated) {
    const pattern = svg('pattern', { id: hatchId, patternUnits: 'userSpaceOnUse', width: 8, height: 8, patternTransform: 'rotate(45)' });
    pattern.appendChild(svg('rect', { width: 4, height: 8, fill: '#ffffff', 'fill-opacity': 0.6 }));
    const defs = svg('defs', {});
    defs.appendChild(pattern);
    root.appendChild(defs);
  }
  // Ligne de crête, pour que le relief reste lisible quelle que soit la couleur.
  // Là où l'altitude manque (début ou fin d'un segment du GPX), le profil laisse un vide.
  let crest = '';
  let drawing = false; // vrai tant que la ligne de crête continue sans vide
  for (const column of columns) {
    if (column.eleStart === null || column.eleEnd === null) {
      drawing = false;
      continue;
    }
    const x0 = x(column.start).toFixed(2);
    const x1 = x(column.end).toFixed(2);
    const y0 = y(column.eleStart).toFixed(2);
    const y1 = y(column.eleEnd).toFixed(2);
    const points = `${x0},${base} ${x0},${y0} ${x1},${y1} ${x1},${base}`;
    root.appendChild(svg('polygon', { points, fill: colorOf(column.cls), stroke: colorOf(column.cls), 'stroke-width': 0.6 }));
    // Couverture estimée : hachures par-dessus la couleur, comme sur la carte.
    if (column.estimated) root.appendChild(svg('polygon', { points, fill: `url(#${hatchId})`, stroke: 'none' }));
    crest += `${drawing ? '' : `M${x0},${y0} `}L${x1},${y1} `;
    drawing = true;
  }
  root.appendChild(svg('path', { d: crest.trim(), fill: 'none', stroke: '#1b2733', 'stroke-width': 1.5, 'vector-effect': 'non-scaling-stroke' }));
  const cursor = svg('line', { x1: 0, x2: 0, y1: PAD.top, y2: base, stroke: '#111827', 'stroke-width': 1.5, 'vector-effect': 'non-scaling-stroke', visibility: 'hidden' });
  root.appendChild(cursor);

  const readout = document.createElement('p');
  readout.className = 'profile__readout';
  readout.setAttribute('aria-live', 'off');
  const idle = t('profile.hint');
  readout.textContent = idle;

  const scale = document.createElement('div');
  scale.className = 'profile__scale';
  const top = document.createElement('span');
  top.textContent = `${formatNumber(Math.round(max))} m`;
  const bottom = document.createElement('span');
  bottom.textContent = `${formatNumber(Math.round(min))} m`;
  scale.append(top, bottom);

  const distances = document.createElement('div');
  distances.className = 'profile__distances';
  const d0 = document.createElement('span');
  d0.textContent = '0';
  const d1 = document.createElement('span');
  d1.textContent = `${formatKm(total)} km`;
  distances.append(d0, d1);

  const chart = document.createElement('div');
  chart.className = 'profile__chart';
  chart.append(root, scale);

  // Point du tracé le plus proche d'une distance donnée (recherche par dichotomie).
  const indexAt = (dist: number): number => {
    let lo = 0;
    let hi = samples.length - 1;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (samples[mid].dist < dist) lo = mid + 1;
      else hi = mid;
    }
    if (lo > 0 && dist - samples[lo - 1].dist < samples[lo].dist - dist) return lo - 1;
    return lo;
  };
  let current = 0;
  const showIndex = (index: number): void => {
    current = index;
    const sample = samples[index];
    const px = x(sample.dist);
    cursor.setAttribute('x1', String(px));
    cursor.setAttribute('x2', String(px));
    cursor.setAttribute('visibility', 'visible');
    const text = profilePointText(sample, classes ? classes[index] : -1, estimated?.[index] === 1);
    readout.textContent = text;
    root.setAttribute('aria-valuenow', String(index));
    root.setAttribute('aria-valuetext', text);
    options.onHover(index);
  };
  const show = (clientX: number): void => {
    const rect = root.getBoundingClientRect();
    if (rect.width <= 0) return;
    const ratio = Math.min(1, Math.max(0, ((clientX - rect.left) / rect.width) * WIDTH - PAD.left) / innerW);
    showIndex(indexAt(Math.min(1, Math.max(0, ratio)) * total));
  };
  const hide = (): void => {
    cursor.setAttribute('visibility', 'hidden');
    readout.textContent = idle;
    options.onHover(null);
  };
  root.addEventListener('pointermove', (event) => show(event.clientX));
  root.addEventListener('pointerdown', (event) => show(event.clientX));
  root.addEventListener('pointerleave', hide);
  root.addEventListener('pointercancel', hide);
  // Au clavier : le curseur apparaît avec le focus et se déplace avec les flèches, les pages, Début et Fin.
  root.addEventListener('focus', () => showIndex(current));
  root.addEventListener('blur', hide);
  root.addEventListener('keydown', (event) => {
    const index = profileKeyIndex(event.key, current, samples.length);
    if (index === null) return;
    event.preventDefault();
    showIndex(index);
  });

  const wrapper = document.createElement('div');
  wrapper.className = 'profile';
  wrapper.append(chart, distances, readout);
  if (anyEstimated) {
    const legend = document.createElement('p');
    legend.className = 'profile__legend';
    const swatch = document.createElement('span');
    swatch.className = 'swatch swatch--hatch';
    legend.append(swatch, t('legend.estimated'));
    wrapper.append(legend);
  }
  return wrapper;
}
