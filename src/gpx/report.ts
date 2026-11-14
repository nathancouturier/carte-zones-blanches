// Rapport de couverture d'un tracé : chiffres, zones blanches et version texte.

import { TRACK_MAX_JUMP_M, WHITE_ZONE_MIN_LENGTH_M } from '../config';
import {
  countryName,
  formatDataDate,
  formatKm,
  formatNumber,
  formatPercent,
  t,
} from '../i18n';
import { LEVEL_GOOD, LEVEL_LIMITED, LEVEL_NONE, LEVEL_VERY_GOOD } from '../coverage/codec';
import {
  ALL_OPERATORS,
  buildLevelTables,
  countryByCode,
  countryHasOperatorChoice,
  countryHasService,
  effectiveOperator,
  type DecodeSettings,
  type Manifest,
  type ManifestCountry,
} from '../coverage/manifest';
import { slotLabel } from '../coverage/slotLabel';
import {
  classify,
  computeStats,
  countriesCrossed,
  elevationGain,
  findWhiteZones,
  hasEstimatedData,
  type CoverageStats,
  type ElevationGain,
  type RawCoverage,
  type WhiteZone,
} from './analyze';
import type { ExtraWaypoint } from './export';
import type { ParsedGpx } from './parse';
import type { Sample } from './resample';

/** Résultat de la lecture des tuiles pour un tracé. Indépendant des réglages. */
export interface TrackAnalysis {
  samples: Sample[];
  raw: RawCoverage;
  /** Longueur du parcours, en mètres. */
  length: number;
  gain: ElevationGain | null;
}

/** Rapport pour un réglage donné (service et opérateurs). */
export interface Report {
  /** Classe de chaque point pour l'opérateur choisi, et pour tous opérateurs. */
  classes: Uint8Array;
  classesAll: Uint8Array;
  stats: CoverageStats;
  statsAll: CoverageStats;
  zones: WhiteZone[];
  /** Pays traversés, dans l'ordre du parcours. */
  countries: ManifestCountry[];
  /** Pays traversés hors de l'itinérance UE. */
  nonEuCountries: ManifestCountry[];
  /** Vrai si au moins un pays traversé a un opérateur précis sélectionné. */
  specificOperator: boolean;
  /** Vrai si une partie du parcours repose sur une source estimée. */
  estimated: boolean;
  /** Pays traversés qui n'ont pas de données pour le service choisi. */
  missingService: ManifestCountry[];
  /** Pays traversés dont la source dit seulement « couvert » ou « non couvert » pour le service choisi. */
  binaryCountries: ManifestCountry[];
}

export function analyzeTrack(samples: Sample[], raw: RawCoverage): TrackAnalysis {
  const length = samples.length > 0 ? samples[samples.length - 1].dist : 0;
  return { samples, raw, length, gain: elevationGain(samples) };
}

export function buildReport(analysis: TrackAnalysis, manifest: Manifest, settings: DecodeSettings): Report {
  const tables = buildLevelTables(manifest, settings);
  const tablesAll = buildLevelTables(manifest, settings, true);
  const classes = classify(analysis.raw, tables, settings.service);
  const classesAll = classify(analysis.raw, tablesAll, settings.service);
  const countries = countriesCrossed(analysis.raw)
    .map((code) => countryByCode(manifest, code))
    .filter((c): c is ManifestCountry => c !== undefined);
  return {
    classes,
    classesAll,
    stats: computeStats(analysis.samples, classes),
    statsAll: computeStats(analysis.samples, classesAll),
    zones: findWhiteZones(analysis.samples, classes, analysis.raw),
    countries,
    nonEuCountries: countries.filter((c) => !c.euRoaming),
    specificOperator: countries.some((c) => effectiveOperator(c, settings) !== null),
    estimated: hasEstimatedData(analysis.raw),
    missingService: countries.filter((c) => !countryHasService(c, settings.service)),
    binaryCountries: countries.filter((c) => c.sources.some((source) => source.levels === 'binary' && source.services.includes(settings.service))),
  };
}

// ---------------------------------------------------------------------------
// Textes
// ---------------------------------------------------------------------------

export const LEVEL_KEYS: Record<number, string> = {
  [LEVEL_NONE]: 'level.none',
  [LEVEL_LIMITED]: 'level.limited',
  [LEVEL_GOOD]: 'level.good',
  [LEVEL_VERY_GOOD]: 'level.veryGood',
};

/** Les espaces insécables fines posent problème dans certains GPS : on les remplace dans les exports. */
function plain(text: string): string {
  return text.replace(/[  ]/g, ' ');
}

/** « km 12,4 à 14,1, soit 1,7 km, altitude 1 850 à 2 100 m, Italie, estimée ». */
export function describeZone(zone: WhiteZone, manifest: Manifest): string {
  // Bornes arrondies à 100 m (la décimale affichée), puis longueur tirée de ces bornes :
  // arrondie à part, elle pourrait contredire la soustraction que fait le lecteur.
  const start = Math.round(zone.start / 100) * 100;
  const end = Math.round(zone.end / 100) * 100;
  const parts = [
    t('report.zoneRange', {
      start: formatKm(start),
      end: formatKm(end),
      length: formatKm(end - start),
    }),
  ];
  if (zone.eleMin !== null && zone.eleMax !== null) {
    parts.push(
      t('report.zoneAltitude', {
        min: formatNumber(Math.round(zone.eleMin)),
        max: formatNumber(Math.round(zone.eleMax)),
      }),
    );
  }
  const names = zone.countries
    .map((code) => countryByCode(manifest, code))
    .filter((c): c is ManifestCountry => c !== undefined)
    .map((c) => countryName(c.iso));
  if (names.length > 0) parts.push(names.join(', '));
  if (zone.estimated) parts.push(t('report.zoneEstimated'));
  return parts.join(', ');
}

/** Corrections faites à la lecture du GPX, à signaler : points aberrants écartés, sauts ignorés. */
export function importNotes(parsed: Pick<ParsedGpx, 'discarded' | 'jumps'>): string[] {
  const km = formatNumber(TRACK_MAX_JUMP_M / 1000);
  const notes: string[] = [];
  if (parsed.discarded > 0) notes.push(t('gpx.discarded', { count: parsed.discarded, km }));
  if (parsed.jumps > 0) notes.push(t('gpx.jumps', { count: parsed.jumps, km }));
  return notes;
}

/** Message à afficher quand aucune part du parcours n'est mesurée, selon la cause. */
export function noDataMessage(analysis: TrackAnalysis, report: Report): string {
  if (!(analysis.length > 0)) return t('report.zeroLength'); // points tous confondus
  if (report.stats.unknown > 0) return t('report.noServiceData'); // pays sans donnée pour ce service
  return t('report.noData'); // hors de la zone couverte par les données
}

/** « Aucune zone blanche de plus de 100 m sur ce parcours. », dans le panneau comme dans le texte. */
export function noZonesMessage(): string {
  return t('report.noZones', { min: formatNumber(WHITE_ZONE_MIN_LENGTH_M) });
}

/** Opérateur appliqué dans chaque pays traversé : « Orange (France), tous opérateurs (Italie) ». */
export function describeOperators(report: Report, settings: DecodeSettings): string {
  return report.countries
    .map((country) => {
      const operator = effectiveOperator(country, settings);
      const label = operator ? slotLabel(operator, country) : t('network.allOperatorsShort');
      return t('report.operatorInCountry', { operator: label, country: countryName(country.iso) });
    })
    .join(', ');
}

function statsLines(stats: CoverageStats): string[] {
  const lines: string[] = [];
  for (const level of [LEVEL_NONE, LEVEL_LIMITED, LEVEL_GOOD, LEVEL_VERY_GOOD]) {
    const length = stats.byLevel[level];
    const share = stats.measured > 0 ? length / stats.measured : 0;
    lines.push(
      `  ${t('report.statLine', { level: t(LEVEL_KEYS[level]), percent: formatPercent(share), km: formatKm(length) })}`,
    );
  }
  return lines;
}

/** Rapport en texte brut, prêt à copier. */
export function reportText(
  analysis: TrackAnalysis,
  report: Report,
  manifest: Manifest,
  settings: DecodeSettings,
  trackName: string | null,
): string {
  const lines: string[] = [];
  lines.push(trackName ? t('report.titleNamed', { name: trackName }) : t('report.title'));
  lines.push(t('report.distanceLine', { km: formatKm(analysis.length) }));
  if (analysis.gain) {
    lines.push(
      t('report.elevationLine', {
        up: formatNumber(Math.round(analysis.gain.ascent)),
        down: formatNumber(Math.round(analysis.gain.descent)),
        min: formatNumber(Math.round(analysis.gain.min)),
        max: formatNumber(Math.round(analysis.gain.max)),
      }),
    );
  }
  if (report.countries.length > 0) {
    lines.push(t('report.countriesLine', { countries: report.countries.map((c) => countryName(c.iso)).join(', ') }));
  }
  lines.push(t('report.serviceLine', { service: t(`service.${settings.service}`) }));
  if (report.countries.length > 0) lines.push(t('report.operatorLine', { operators: describeOperators(report, settings) }));
  lines.push('');
  if (report.stats.measured > 0) {
    lines.push(report.specificOperator ? t('report.shareSelected') : t('report.shareAll'));
    lines.push(...statsLines(report.stats));
    if (report.specificOperator) {
      lines.push(t('report.shareAll'));
      lines.push(...statsLines(report.statsAll));
    }
  } else {
    lines.push(noDataMessage(analysis, report));
  }
  if (report.stats.outside > 0) lines.push(t('report.outsideLine', { km: formatKm(report.stats.outside) }));
  if (report.stats.unknown > 0) lines.push(t('report.unknownLine', { km: formatKm(report.stats.unknown) }));
  lines.push('');
  if (report.zones.length === 0) {
    lines.push(noZonesMessage());
  } else {
    lines.push(t('report.zonesTitle', { count: report.zones.length }));
    for (const zone of report.zones) lines.push(`  ${zone.index}. ${describeZone(zone, manifest)}`);
  }
  lines.push('');
  for (const country of report.nonEuCountries) {
    lines.push(t('report.roamingWarning', { country: countryName(country.iso) }));
  }
  if (report.estimated) lines.push(t('report.estimatedWarning'));
  if (report.binaryCountries.length > 0) {
    lines.push(t('report.binaryNote', { countries: report.binaryCountries.map((c) => countryName(c.iso)).join(', ') }));
  }
  lines.push(t('sources.disclaimer'));
  const sources = report.countries.flatMap((country) =>
    country.sources
      .filter((s) => s.services.includes(settings.service))
      .map((s) => `${s.attribution} (${countryName(country.iso)}, ${formatDataDate(s.date)})`),
  );
  if (sources.length > 0) lines.push(t('report.sourcesLine', { sources: sources.join(' ; ') }));
  return plain(lines.join('\n'));
}

/** Points de passage à ajouter au GPX : début et fin de chaque zone blanche. */
export function zoneWaypoints(analysis: TrackAnalysis, report: Report, manifest: Manifest): ExtraWaypoint[] {
  const waypoints: ExtraWaypoint[] = [];
  for (const zone of report.zones) {
    const desc = plain(describeZone(zone, manifest));
    const first = analysis.samples[zone.first];
    const last = analysis.samples[zone.last];
    waypoints.push({
      lon: first.lon,
      lat: first.lat,
      ele: first.ele,
      name: plain(t('export.waypointStart', { n: zone.index })),
      desc,
      sym: 'Flag, Red',
    });
    waypoints.push({
      lon: last.lon,
      lat: last.lat,
      ele: last.ele,
      name: plain(t('export.waypointEnd', { n: zone.index })),
      desc,
      sym: 'Flag, Green',
    });
  }
  return waypoints;
}

/** Vrai si l'utilisateur peut choisir un opérateur précis dans au moins un pays traversé. */
export function anyOperatorChoice(report: Report): boolean {
  return report.countries.some((c) => countryHasOperatorChoice(c));
}

export { ALL_OPERATORS };
