import { describe, expect, it } from 'vitest';
import { LEVEL_NONE, packMeta, packSlots } from '../src/coverage/codec';
import { buildLevelTables } from '../src/coverage/manifest';
import {
  CLASS_OUTSIDE,
  CLASS_UNKNOWN,
  classify,
  computeStats,
  countriesCrossed,
  elevationGain,
  findWhiteZones,
  sampleCoverage,
  sampleSpans,
  type RawCoverage,
  type WhiteZone,
} from '../src/gpx/analyze';
import { enrichedFileName, enrichGpx, WAYPOINT_TYPE } from '../src/gpx/export';
import { distance } from '../src/gpx/geodesy';
import { decodeGpx, GpxError, parseGpx } from '../src/gpx/parse';
import { analyzeTrack, buildReport, describeZone, reportText, zoneWaypoints } from '../src/gpx/report';
import { resample, trackLength, type Sample } from '../src/gpx/resample';
import { availableLanguages, setLanguage } from '../src/i18n';
import { profileColumns } from '../src/ui/profile';
import { fixtureStore, sampleManifest, xmlParser, xmlTools } from './helpers';

const GPX_HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">';

const trackGpx = `${GPX_HEAD}
<metadata><name>Fichier</name></metadata>
<wpt lat="44.60" lon="6.10"><name>Parking</name></wpt>
<trk><name>Tour du lac</name><trkseg>
<trkpt lat="44.6000" lon="6.1000"><ele>1000</ele></trkpt>
<trkpt lat="44.6010" lon="6.1000"><ele>1020</ele></trkpt>
<trkpt lat="44.6020" lon="6.1010"><ele>1010</ele></trkpt>
</trkseg></trk></gpx>`;

const multiSegmentGpx = `${GPX_HEAD}
<trk><name>Jour 1</name>
<trkseg><trkpt lat="44.60" lon="6.10"><ele>1000</ele></trkpt><trkpt lat="44.61" lon="6.10"><ele>1100</ele></trkpt></trkseg>
<trkseg><trkpt lat="44.61" lon="6.10"><ele>1100</ele></trkpt><trkpt lat="44.62" lon="6.11"><ele>1200</ele></trkpt></trkseg>
</trk>
<trk><name>Jour 2</name><trkseg><trkpt lat="44.70" lon="6.20"><ele>900</ele></trkpt><trkpt lat="44.71" lon="6.20"><ele>950</ele></trkpt></trkseg></trk>
</gpx>`;

const routeGpx = `${GPX_HEAD}
<rte><name>Itinéraire</name>
<rtept lat="42.50" lon="1.50"/><rtept lat="42.51" lon="1.52"/><rtept lat="42.53" lon="1.52"/>
</rte></gpx>`;

// Même trace, avec un préfixe sur chaque élément GPX (sorties JAXB ou XSLT).
const prefixedGpx = `<?xml version="1.0" encoding="UTF-8"?>
<gpx:gpx version="1.1" creator="test" xmlns:gpx="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
<gpx:wpt lat="44.60" lon="6.10"><gpx:name>Parking</gpx:name></gpx:wpt>
<gpx:trk><gpx:name>Tour du lac</gpx:name><gpx:trkseg>
<gpx:trkpt lat="44.6000" lon="6.1000"><gpx:ele>1000</gpx:ele></gpx:trkpt>
<gpx:trkpt lat="44.6010" lon="6.1000"><gpx:ele>1020</gpx:ele><gpx:extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>120</gpxtpx:hr></gpxtpx:TrackPointExtension></gpx:extensions></gpx:trkpt>
<gpx:trkpt lat="44.6020" lon="6.1010"><gpx:ele>1010</gpx:ele></gpx:trkpt>
</gpx:trkseg></gpx:trk></gpx:gpx>`;

describe('lecture du GPX', () => {
  it('lit une trace simple avec ses altitudes', () => {
    const gpx = parseGpx(trackGpx, xmlParser);
    expect(gpx.kind).toBe('track');
    expect(gpx.name).toBe('Tour du lac');
    expect(gpx.segments).toHaveLength(1);
    expect(gpx.segments[0]).toEqual([
      { lon: 6.1, lat: 44.6, ele: 1000 },
      { lon: 6.1, lat: 44.601, ele: 1020 },
      { lon: 6.101, lat: 44.602, ele: 1010 },
    ]);
    expect(gpx.hasElevation).toBe(true);
    expect(gpx.pointCount).toBe(3);
  });

  it('lit plusieurs segments et plusieurs traces dans l\'ordre', () => {
    const gpx = parseGpx(multiSegmentGpx, xmlParser);
    expect(gpx.segments).toHaveLength(3);
    expect(gpx.segments.map((s) => s.length)).toEqual([2, 2, 2]);
    expect(gpx.segments[2][0]).toMatchObject({ lon: 6.2, lat: 44.7 });
    expect(gpx.name).toBe('Jour 1');
  });

  it('lit une route sans altitude', () => {
    const gpx = parseGpx(routeGpx, xmlParser);
    expect(gpx.kind).toBe('route');
    expect(gpx.name).toBe('Itinéraire');
    expect(gpx.segments).toHaveLength(1);
    expect(gpx.segments[0]).toHaveLength(3);
    expect(gpx.hasElevation).toBe(false);
    expect(gpx.segments[0][0].ele).toBeNull();
  });

  it('préfère les traces aux routes quand le fichier contient les deux', () => {
    const both = trackGpx.replace('</gpx>', '<rte><rtept lat="1" lon="1"/><rtept lat="2" lon="2"/></rte></gpx>');
    const gpx = parseGpx(both, xmlParser);
    expect(gpx.kind).toBe('track');
    expect(gpx.segments).toHaveLength(1);
  });

  it('lit un GPX dont les éléments portent un préfixe d\'espace de noms', () => {
    const gpx = parseGpx(prefixedGpx, xmlParser);
    expect(gpx.kind).toBe('track');
    expect(gpx.name).toBe('Tour du lac');
    expect(gpx.segments).toEqual(parseGpx(trackGpx, xmlParser).segments);
  });

  it('accepte des blancs ou une marque d\'ordre des octets avant la déclaration XML', () => {
    for (const before of ['\n', '\r\n  ', '\uFEFF', '\uFEFF\n']) {
      expect(parseGpx(before + trackGpx, xmlParser).name, JSON.stringify(before)).toBe('Tour du lac');
    }
  });

  it('signale un fichier invalide ou vide', () => {
    const code = (text: string): string => {
      try {
        parseGpx(text, xmlParser);
      } catch (error) {
        return error instanceof GpxError ? error.code : 'autre';
      }
      return 'aucune erreur';
    };
    expect(code('<html><body>pas un gpx</body></html>')).toBe('invalid');
    expect(code(`${GPX_HEAD}<wpt lat="44" lon="6"><name>Seul</name></wpt></gpx>`)).toBe('empty');
    expect(code(`${GPX_HEAD}<trk><trkseg><trkpt lat="44" lon="6"/></trkseg></trk></gpx>`)).toBe('empty');
  });
});

describe('encodage du fichier', () => {
  const named = trackGpx.replace('Tour du lac', 'Tour du Râteau');
  const latin1 = named.replace('encoding="UTF-8"', 'encoding="ISO-8859-1"');

  it('décode selon l\'encodage de la déclaration XML', () => {
    expect(parseGpx(decodeGpx(Buffer.from(latin1, 'latin1')), xmlParser).name).toBe('Tour du Râteau');
    expect(parseGpx(decodeGpx(Buffer.from(named.replace('UTF-8', 'windows-1252'), 'latin1')), xmlParser).name).toBe('Tour du Râteau');
  });

  it('donne la priorité à la marque d\'ordre des octets', () => {
    const utf16 = Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from(named, 'utf16le')]);
    expect(parseGpx(decodeGpx(utf16), xmlParser).name).toBe('Tour du Râteau');
    const utf8 = Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(latin1, 'utf8')]);
    expect(decodeGpx(utf8).startsWith('<?xml')).toBe(true);
    expect(parseGpx(decodeGpx(utf8), xmlParser).name).toBe('Tour du Râteau');
  });

  it('lit en UTF-8 sans déclaration d\'encodage, ou si l\'encodage est inconnu', () => {
    expect(parseGpx(decodeGpx(Buffer.from(named.replace(' encoding="UTF-8"', ''), 'utf8')), xmlParser).name).toBe('Tour du Râteau');
    expect(parseGpx(decodeGpx(Buffer.from(named.replace('UTF-8', 'x-inconnu'), 'utf8')), xmlParser).name).toBe('Tour du Râteau');
  });
});

describe('rééchantillonnage', () => {
  // Ligne droite plein nord d'environ 1 km.
  const north = [[
    { lon: 6, lat: 45, ele: 1000 },
    { lon: 6, lat: 45.009, ele: 1100 },
  ]];

  it('place un point tous les 20 m, plus l\'arrivée', () => {
    const total = trackLength(north);
    expect(total).toBeGreaterThan(1000);
    expect(total).toBeLessThan(1002);
    const samples = resample(north, 20);
    expect(samples[0]).toMatchObject({ dist: 0, lon: 6, lat: 45, ele: 1000, seg: 0 });
    expect(samples[1].dist).toBe(20);
    expect(samples).toHaveLength(Math.floor(total / 20) + 2);
    const last = samples[samples.length - 1];
    expect(last.dist).toBeCloseTo(total, 6);
    expect(last.lat).toBe(45.009);
    // La distance géodésique entre deux points consécutifs vaut bien 20 m.
    for (let i = 1; i < samples.length - 1; i++) {
      expect(distance(samples[i - 1].lon, samples[i - 1].lat, samples[i].lon, samples[i].lat)).toBeCloseTo(20, 3);
    }
    // L'altitude est interpolée.
    expect(samples[25].ele).toBeCloseTo(1000 + (100 * 500) / total, 3);
  });

  it('garde un pas régulier à travers les sommets intermédiaires', () => {
    const bent = [[
      { lon: 6, lat: 45, ele: null },
      { lon: 6, lat: 45.00013, ele: null }, // environ 14,5 m
      { lon: 6, lat: 45.0005, ele: null },
    ]];
    const samples = resample(bent, 20);
    expect(samples.map((s) => Math.round(s.dist))).toEqual([0, 20, 40, 56]);
    expect(samples.every((s) => s.ele === null)).toBe(true);
  });

  it('cumule les distances sur plusieurs segments sans compter les sauts', () => {
    const gpx = parseGpx(multiSegmentGpx, xmlParser);
    const samples = resample(gpx.segments, 20);
    const total = trackLength(gpx.segments);
    expect(samples[samples.length - 1].dist).toBeCloseTo(total, 6);
    expect(new Set(samples.map((s) => s.seg))).toEqual(new Set([0, 1, 2]));
    // Les distances ne reculent jamais.
    for (let i = 1; i < samples.length; i++) expect(samples[i].dist).toBeGreaterThanOrEqual(samples[i - 1].dist);
    const { lo, hi } = sampleSpans(samples);
    let sum = 0;
    for (let i = 0; i < samples.length; i++) sum += hi[i] - lo[i];
    expect(sum).toBeCloseTo(total, 6);
  });

  it('refuse un pas nul', () => {
    expect(() => resample(north, 0)).toThrow(RangeError);
  });

  it('interpole les altitudes manquantes entre les points connus', () => {
    const gaps = [[
      { lon: 6, lat: 45, ele: 1000 },
      { lon: 6, lat: 45.0045, ele: null }, // à mi-chemin
      { lon: 6, lat: 45.009, ele: 1100 },
    ]];
    const samples = resample(gaps, 20);
    expect(samples.every((s) => s.ele !== null)).toBe(true);
    const total = samples[samples.length - 1].dist;
    for (const s of samples) expect(s.ele).toBeCloseTo(1000 + (100 * s.dist) / total, 6);
  });

  it('n\'invente pas d\'altitude avant le premier point connu ni après le dernier', () => {
    const ends = [[
      { lon: 6, lat: 45, ele: null },
      { lon: 6, lat: 45.0045, ele: 1000 },
      { lon: 6, lat: 45.009, ele: 1100 },
      { lon: 6, lat: 45.0135, ele: null },
    ]];
    const firstKnown = trackLength([ends[0].slice(0, 2)]);
    const lastKnown = trackLength([ends[0].slice(0, 3)]);
    for (const s of resample(ends, 20)) {
      expect(s.ele === null, `${s.dist} m`).toBe(s.dist < firstKnown || s.dist > lastKnown);
    }
  });

  it('garde le dénivelé et le profil quand une seule altitude manque', () => {
    // Trace de 40 points, dont un seul sans <ele>.
    const trkpts = Array.from({ length: 40 }, (_, i) => {
      const ele = i === 17 ? '' : `<ele>${1000 + i * 10}</ele>`;
      return `<trkpt lat="${(44.6 + i * 0.001).toFixed(4)}" lon="6.1000">${ele}</trkpt>`;
    }).join('');
    const parsed = parseGpx(`${GPX_HEAD}<trk><trkseg>${trkpts}</trkseg></trk></gpx>`, xmlParser);
    expect(parsed.hasElevation).toBe(false);
    const samples = resample(parsed.segments);
    expect(samples.every((s) => s.ele !== null)).toBe(true);
    const gain = elevationGain(samples);
    expect(gain).toMatchObject({ descent: 0, min: 1000, max: 1390 });
    expect(gain?.ascent).toBeGreaterThan(385); // le seuil de 5 m peut laisser les derniers mètres de côté
    expect(profileColumns(samples, null).length).toBeGreaterThan(0);
  });
});

/** Fabrique un tracé rectiligne et sa couverture à partir d'une liste de classes par point (pas de 20 m). */
function synthetic(levels: (number | 'out')[], options: { country?: number; sourceType?: number; ele?: (i: number) => number | null } = {}): { samples: Sample[]; raw: RawCoverage } {
  const n = levels.length;
  const samples: Sample[] = levels.map((_, i) => ({ lon: 6 + i * 0.00025, lat: 45, ele: options.ele ? options.ele(i) : null, dist: i * 20, seg: 0 }));
  const raw: RawCoverage = { data: new Uint8Array(n), voice: new Uint8Array(n), meta: new Uint8Array(n), inside: new Uint8Array(n) };
  levels.forEach((level, i) => {
    if (level === 'out') return;
    raw.data[i] = packSlots([level, level, level, level]);
    raw.meta[i] = packMeta(options.country ?? 1, options.sourceType ?? 0);
    raw.inside[i] = 1;
  });
  return { samples, raw };
}

function repeat<T>(value: T, count: number): T[] {
  return Array.from({ length: count }, () => value);
}

describe('regroupement en zones blanches', () => {
  const manifest = sampleManifest();
  const tables = buildLevelTables(manifest, { service: 'data', operators: {} });

  it('trouve une zone blanche et calcule ses km', () => {
    // 10 points couverts, 11 points sans réseau, 10 points couverts.
    const { samples, raw } = synthetic([...repeat(3, 10), ...repeat(0, 11), ...repeat(2, 10)], { ele: (i) => 1000 + i * 10 });
    const classes = classify(raw, tables, 'data');
    const zones = findWhiteZones(samples, classes, raw);
    expect(zones).toHaveLength(1);
    const zone = zones[0];
    expect(zone.index).toBe(1);
    expect([zone.first, zone.last]).toEqual([10, 20]);
    // Bornes au milieu des intervalles : de 190 m à 410 m.
    expect(zone.start).toBe(190);
    expect(zone.end).toBe(410);
    expect(zone.length).toBe(220);
    expect(zone.eleMin).toBe(1100);
    expect(zone.eleMax).toBe(1200);
    expect(zone.countries).toEqual([1]);
    expect(zone.estimated).toBe(false);
    expect(zone.bbox[0]).toBeCloseTo(6.0025, 6);
  });

  it('ignore une zone de moins de 100 m', () => {
    const { samples, raw } = synthetic([...repeat(3, 10), ...repeat(0, 4), ...repeat(3, 10)]); // 80 m
    const zones = findWhiteZones(samples, classify(raw, tables, 'data'), raw);
    expect(zones).toHaveLength(0);
    // Exactement 100 m : la zone est gardée.
    const five = synthetic([...repeat(3, 10), ...repeat(0, 5), ...repeat(3, 10)]);
    expect(findWhiteZones(five.samples, classify(five.raw, tables, 'data'), five.raw)).toHaveLength(1);
  });

  it('fusionne deux zones séparées par moins de 50 m de couverture', () => {
    // 80 m sans réseau, 40 m couverts, 80 m sans réseau : une seule zone de 200 m.
    const close = synthetic([...repeat(3, 5), ...repeat(0, 4), ...repeat(3, 2), ...repeat(0, 4), ...repeat(3, 5)]);
    const zones = findWhiteZones(close.samples, classify(close.raw, tables, 'data'), close.raw);
    expect(zones).toHaveLength(1);
    expect(zones[0].length).toBe(200);
    // 60 m couverts entre les deux : elles restent séparées, et chacune fait moins de 100 m.
    const far = synthetic([...repeat(3, 5), ...repeat(0, 4), ...repeat(3, 3), ...repeat(0, 4), ...repeat(3, 5)]);
    expect(findWhiteZones(far.samples, classify(far.raw, tables, 'data'), far.raw)).toHaveLength(0);
    // Avec des zones plus longues, 60 m de couverture donnent bien deux zones.
    const two = synthetic([...repeat(3, 5), ...repeat(0, 8), ...repeat(3, 3), ...repeat(0, 8), ...repeat(3, 5)]);
    const twoZones = findWhiteZones(two.samples, classify(two.raw, tables, 'data'), two.raw);
    expect(twoZones.map((z) => z.index)).toEqual([1, 2]);
    expect(twoZones.map((z) => z.length)).toEqual([160, 160]);
  });

  it('accepte des seuils différents', () => {
    const { samples, raw } = synthetic([...repeat(3, 10), ...repeat(0, 4), ...repeat(3, 10)]);
    const zones = findWhiteZones(samples, classify(raw, tables, 'data'), raw, { minLength: 50 });
    expect(zones).toHaveLength(1);
  });

  it('gère une zone qui touche le début ou la fin du tracé', () => {
    const { samples, raw } = synthetic([...repeat(0, 8), ...repeat(3, 10), ...repeat(0, 8)]);
    const zones = findWhiteZones(samples, classify(raw, tables, 'data'), raw);
    expect(zones).toHaveLength(2);
    expect(zones[0].start).toBe(0);
    expect(zones[0].end).toBe(150);
    expect(zones[1].end).toBe(samples[samples.length - 1].dist);
  });

  it('ne fusionne pas deux segments éloignés l\'un de l\'autre', () => {
    const a = synthetic(repeat(0, 8));
    const b = synthetic(repeat(0, 8));
    const samples = [...a.samples, ...b.samples.map((s, i) => ({ ...s, seg: 1, dist: 140 + i * 20, lat: 46 }))];
    const raw: RawCoverage = {
      data: new Uint8Array([...a.raw.data, ...b.raw.data]),
      voice: new Uint8Array(16),
      meta: new Uint8Array([...a.raw.meta, ...b.raw.meta]),
      inside: new Uint8Array([...a.raw.inside, ...b.raw.inside]),
    };
    const zones = findWhiteZones(samples, classify(raw, tables, 'data'), raw);
    expect(zones).toHaveLength(2);
    expect(zones.map((z) => [z.first, z.last])).toEqual([[0, 7], [8, 15]]);
  });

  it('prolonge une zone d\'un segment au suivant quand ils se touchent, quel que soit le seuil de fusion', () => {
    // Deux segments de 80 m sans réseau, à 11 m l'un de l'autre (pause du GPS) : une seule zone de 160 m.
    const a = synthetic(repeat(0, 5));
    const b = synthetic(repeat(0, 5));
    const join = a.samples[4].lon + 0.00014; // environ 11 m plus à l'est
    const samples = [...a.samples, ...b.samples.map((s, i) => ({ ...s, seg: 1, dist: 80 + i * 20, lon: join + i * 0.00025 }))];
    expect(distance(a.samples[4].lon, 45, join, 45)).toBeCloseTo(11, 0);
    const raw: RawCoverage = {
      data: new Uint8Array([...a.raw.data, ...b.raw.data]),
      voice: new Uint8Array(10),
      meta: new Uint8Array([...a.raw.meta, ...b.raw.meta]),
      inside: new Uint8Array([...a.raw.inside, ...b.raw.inside]),
    };
    for (const mergeGap of [50, 10, 0]) {
      const zones = findWhiteZones(samples, classify(raw, tables, 'data'), raw, { mergeGap });
      expect(zones.map((z) => z.length), `fusion à ${mergeGap} m`).toEqual([160]);
    }
  });

  it('n\'annonce l\'altitude d\'une zone que si la plupart de ses points en ont une', () => {
    // Seul le départ a une altitude : la zone n'a pas d'altitude.
    const lone = synthetic([...repeat(0, 11), ...repeat(3, 5)], { ele: (i) => (i === 0 ? 1000 : null) });
    const zone = findWhiteZones(lone.samples, classify(lone.raw, tables, 'data'), lone.raw)[0];
    expect([zone.eleMin, zone.eleMax]).toEqual([null, null]);
    // 8 points sur 11 ont une altitude : elle est annoncée, calculée sur ces points.
    const most = synthetic([...repeat(0, 11), ...repeat(3, 5)], { ele: (i) => (i < 8 ? 1000 + i : null) });
    const known = findWhiteZones(most.samples, classify(most.raw, tables, 'data'), most.raw)[0];
    expect([known.eleMin, known.eleMax]).toEqual([1000, 1007]);
  });

  it('marque les zones estimées et liste les pays', () => {
    const { samples, raw } = synthetic(repeat(0, 10), { country: 5, sourceType: 2 });
    const zones = findWhiteZones(samples, classify(raw, tables, 'data'), raw);
    expect(zones[0].estimated).toBe(true);
    expect(zones[0].countries).toEqual([5]);
  });
});

describe('statistiques du parcours', () => {
  const manifest = sampleManifest();
  const tables = buildLevelTables(manifest, { service: 'data', operators: {} });

  it('répartit la longueur par niveau et exclut le hors zone', () => {
    const { samples, raw } = synthetic([...repeat(0, 5), ...repeat(1, 5), ...repeat(2, 5), ...repeat(3, 5), ...repeat('out' as const, 5)]);
    const classes = classify(raw, tables, 'data');
    expect(classes[24]).toBe(CLASS_OUTSIDE);
    const stats = computeStats(samples, classes);
    expect(stats.byLevel).toEqual([90, 100, 100, 100]);
    expect(stats.outside).toBe(90);
    expect(stats.measured).toBe(390);
    expect(stats.byLevel.reduce((a, b) => a + b, 0) + stats.outside).toBe(samples[samples.length - 1].dist);
  });

  it('compte à part les portions sans donnée pour le service', () => {
    const { samples, raw } = synthetic(repeat(3, 10));
    const voice = buildLevelTables(manifest, { service: 'voice', operators: {} });
    const classes = classify(raw, voice, 'voice');
    expect(classes[0]).toBe(CLASS_UNKNOWN);
    const stats = computeStats(samples, classes);
    expect(stats.unknown).toBe(180);
    expect(stats.measured).toBe(0);
  });

  it('distingue l\'opérateur choisi de tous les opérateurs', () => {
    const { samples, raw } = synthetic(repeat(0, 10));
    for (let i = 0; i < 10; i++) raw.data[i] = packSlots([0, 3, 0, 0]); // seul SFR couvre
    const selected = classify(raw, buildLevelTables(manifest, { service: 'data', operators: { FR: 'orange' } }), 'data');
    const all = classify(raw, buildLevelTables(manifest, { service: 'data', operators: { FR: 'orange' } }, true), 'data');
    expect(Array.from(new Set(selected))).toEqual([LEVEL_NONE]);
    expect(Array.from(new Set(all))).toEqual([3]);
    expect(computeStats(samples, selected).byLevel[0]).toBe(180);
  });

  it('calcule le dénivelé en ignorant le bruit', () => {
    const profile = [1000, 1002, 1001, 1003, 1050, 1049, 1100, 1090, 1040, 1041];
    const { samples } = synthetic(repeat(3, profile.length), { ele: (i) => profile[i] });
    const gain = elevationGain(samples, 5);
    expect(gain).toEqual({ ascent: 100, descent: 60, min: 1000, max: 1100 });
    expect(elevationGain(synthetic(repeat(3, 4)).samples)).toBeNull();
  });

  it('calcule le dénivelé sur les points qui ont une altitude, jamais sur trop peu', () => {
    const start = [null, null, 1000, 1010, 1020, 1030, 1040, 1050, 1060, 1070];
    expect(elevationGain(synthetic(repeat(3, 10), { ele: (i) => start[i] }).samples)).toEqual({ ascent: 70, descent: 0, min: 1000, max: 1070 });
    // Seul le départ a une altitude, ou le tracé se réduit à un point : rien n'est annoncé.
    expect(elevationGain(synthetic(repeat(3, 10), { ele: (i) => (i === 0 ? 1000 : null) }).samples)).toBeNull();
    expect(elevationGain(synthetic([3], { ele: () => 1000 }).samples)).toBeNull();
  });

  it('liste les pays dans l\'ordre du parcours', () => {
    const { raw } = synthetic(repeat(3, 9));
    [1, 1, 1, 2, 2, 1, 5, 5, 5].forEach((country, i) => (raw.meta[i] = packMeta(country, 0)));
    raw.inside[4] = 0;
    expect(countriesCrossed(raw)).toEqual([1, 2, 5]);
  });
});

describe('analyse sur les tuiles du pipeline', () => {
  it('lit la couverture d\'un tracé au pixel près et produit le rapport', async () => {
    const { store, manifest } = fixtureStore('synthetique');
    // D'ouest en est à travers le jeu synthétique : zone blanche, puis couverture, puis zone blanche.
    const segments = [[
      { lon: 5.72, lat: 44.56, ele: 900 },
      { lon: 6.3, lat: 44.56, ele: 1400 },
    ]];
    const samples = resample(segments);
    let progress = 0;
    const raw = await sampleCoverage(samples, store, (done, total) => (progress = done / total));
    expect(progress).toBe(1);
    const analysis = analyzeTrack(samples, raw);
    expect(analysis.length).toBeCloseTo(trackLength(segments), 3);
    const settings = { service: 'data' as const, operators: {} };
    const report = buildReport(analysis, manifest, settings);
    expect(report.countries.map((c) => c.iso)).toEqual(['FR']);
    expect(report.nonEuCountries).toEqual([]);
    expect(report.specificOperator).toBe(false);
    expect(report.zones.length).toBeGreaterThanOrEqual(1);
    expect(report.stats.byLevel.every((v) => v > 0)).toBe(true);
    // Tout point intérieur est classé : la somme des portions vaut la longueur du tracé.
    const s = report.stats;
    expect(s.measured + s.outside + s.unknown).toBeCloseTo(analysis.length, 3);

    // Un opérateur précis voit au moins autant de zones blanches que « tous opérateurs ».
    const orange = buildReport(analysis, manifest, { service: 'data', operators: { FR: 'free' } });
    expect(orange.specificOperator).toBe(true);
    expect(orange.stats.byLevel[0]).toBeGreaterThanOrEqual(report.stats.byLevel[0]);
    expect(orange.statsAll.byLevel).toEqual(report.stats.byLevel);

    const text = reportText(analysis, report, manifest, settings, 'Traversée test');
    expect(text).toContain('Rapport de couverture : Traversée test');
    expect(text).toContain('Pays traversés : France');
    expect(text).toContain('Zone');
    expect(text).toContain('Couverture théorique, des écarts locaux sont possibles.');
    expect(text).not.toMatch(/[–— ]/);
    const line = describeZone(report.zones[0], manifest);
    expect(line).toMatch(/^km \d+,\d à \d+,\d, soit \d+,\d km, altitude /);
    expect(line).toContain('France');

    const waypoints = zoneWaypoints(analysis, report, manifest);
    expect(waypoints).toHaveLength(report.zones.length * 2);
    expect(waypoints[0].name).toBe('Zone blanche 1, début');
    expect(waypoints[1].name).toBe('Zone blanche 1, fin');
  });
});

describe('rapport en texte', () => {
  const manifest = sampleManifest();
  const settings = { service: 'data' as const, operators: {} };

  it('remplace toutes les variables, même sans zone blanche, dans toutes les langues', () => {
    const { samples, raw } = synthetic(repeat(3, 20));
    const analysis = analyzeTrack(samples, raw);
    const report = buildReport(analysis, manifest, settings);
    expect(report.zones).toHaveLength(0);
    expect(reportText(analysis, report, manifest, settings, 'Sans zone')).toContain('Aucune zone blanche de plus de 100 m sur ce parcours.');
    try {
      for (const { code } of availableLanguages()) {
        setLanguage(code);
        expect(reportText(analysis, report, manifest, settings, 'Sans zone'), code).not.toMatch(/[{}]/);
      }
    } finally {
      setLanguage('fr');
    }
  });

  it('explique pourquoi aucune part du parcours n\'est mesurée', () => {
    const textOf = (track: { samples: Sample[]; raw: RawCoverage }, service: 'data' | 'voice'): string => {
      const analysis = analyzeTrack(track.samples, track.raw);
      return reportText(analysis, buildReport(analysis, manifest, { service, operators: {} }), manifest, { service, operators: {} }, null);
    };
    // Andorre (source estimée, internet seulement), avec le service Appels et SMS.
    const andorra = textOf(synthetic(repeat(2, 30), { country: 5, sourceType: 2 }), 'voice');
    expect(andorra).toContain('Aucune donnée pour ce service sur ce parcours.');
    expect(andorra).toContain('Sans donnée pour ce service : 0,6 km');
    expect(andorra).not.toContain('hors de la zone couverte');
    // Tout le tracé hors de la zone couverte par les données.
    const outside = textOf(synthetic(repeat('out' as const, 30)), 'data');
    expect(outside).toContain('Le tracé est entièrement hors de la zone couverte par les données.');
    expect(outside).not.toContain('Aucune donnée pour ce service');
    // Points tous confondus : le tracé ne mesure rien.
    const same = textOf(synthetic([3]), 'data');
    expect(same).toContain('Le tracé a une longueur nulle : tous ses points sont au même endroit.');
    expect(same).not.toContain('hors de la zone couverte');
  });

  it('donne une longueur cohérente avec les bornes affichées', () => {
    const zone = (start: number, end: number): WhiteZone => ({
      index: 1,
      first: 0,
      last: 1,
      start,
      end,
      length: end - start,
      eleMin: null,
      eleMax: null,
      countries: [],
      estimated: false,
      startPoint: [6, 45],
      endPoint: [6.1, 45],
      bbox: [6, 45, 6.1, 45],
    });
    expect(describeZone(zone(12430, 14070), manifest)).toBe('km 12,4 à 14,1, soit 1,7 km');
    expect(describeZone(zone(2030, 2170), manifest)).toBe('km 2,0 à 2,2, soit 0,2 km');
    expect(describeZone(zone(190, 410), manifest)).toBe('km 0,2 à 0,4, soit 0,2 km');
  });
});

describe('export du GPX enrichi', () => {
  const waypoints = [
    { lon: 6.1, lat: 44.6, ele: 1850.26, name: 'Zone blanche 1, début', desc: 'km 0,1 à 0,4 & plus', sym: 'Flag, Red' },
    { lon: 6.101, lat: 44.602, ele: null, name: 'Zone blanche 1, fin', desc: 'km 0,1 à 0,4 & plus', sym: 'Flag, Green' },
  ];

  it('ajoute les points au bon endroit et garde le reste du fichier', () => {
    const out = enrichGpx(trackGpx, waypoints, xmlTools);
    expect(out.startsWith('<?xml')).toBe(true);
    const doc = xmlTools.parse(out);
    const names = Array.from(doc.getElementsByTagName('wpt')).map((w) => w.getElementsByTagName('name')[0].textContent);
    expect(names).toEqual(['Parking', 'Zone blanche 1, début', 'Zone blanche 1, fin']);
    // Les points sont placés avant la trace, comme l'impose le schéma GPX.
    expect(out.indexOf('<wpt')).toBeLessThan(out.indexOf('<trk>'));
    expect(out.lastIndexOf('</wpt>')).toBeLessThan(out.indexOf('<trk>'));
    expect(out).toContain('<ele>1850.3</ele>');
    expect(out).toContain('km 0,1 à 0,4 &amp; plus');
    expect(out).not.toContain('xmlns=""');
    // La trace d'origine est intacte et le fichier se relit.
    const again = parseGpx(out, xmlParser);
    expect(again.segments).toEqual(parseGpx(trackGpx, xmlParser).segments);
    const added = Array.from(doc.getElementsByTagName('wpt'))[1];
    expect(added.getAttribute('lat')).toBe('44.600000');
    expect(added.getElementsByTagName('type')[0].textContent).toBe(WAYPOINT_TYPE);
  });

  it('remplace les points d\'un export précédent au lieu de les empiler', () => {
    const once = enrichGpx(trackGpx, waypoints, xmlTools);
    const twice = enrichGpx(once, [waypoints[0]], xmlTools);
    const doc = xmlTools.parse(twice);
    expect(doc.getElementsByTagName('wpt')).toHaveLength(2); // Parking + 1 point
  });

  it('déclare toujours l\'UTF-8, l\'encodage du fichier produit', () => {
    const latin1 = trackGpx.replace('encoding="UTF-8"', 'encoding="ISO-8859-1"').replace('Tour du lac', 'Tour du Râteau');
    const out = enrichGpx(latin1, waypoints, xmlTools);
    expect(out.startsWith('<?xml version="1.0" encoding="UTF-8"?>')).toBe(true);
    expect(out).not.toContain('ISO-8859-1');
    expect(out.match(/<\?xml\s/g)).toHaveLength(1);
    expect(parseGpx(out, xmlParser).name).toBe('Tour du Râteau');
    // Sans déclaration dans le fichier d'origine, on en ajoute une.
    expect(enrichGpx(trackGpx.replace(/^<\?xml[^>]*>\n/, ''), waypoints, xmlTools).startsWith('<?xml version="1.0" encoding="UTF-8"?>\n<gpx')).toBe(true);
  });

  it('garde le préfixe d\'espace de noms du fichier d\'origine', () => {
    const out = enrichGpx(prefixedGpx, waypoints, xmlTools);
    expect(out).toContain('<gpx:wpt lat="44.600000"');
    expect(out).not.toMatch(/<wpt[\s>]/);
    const doc = xmlTools.parse(out);
    const ns = 'http://www.topografix.com/GPX/1/1';
    const names = Array.from(doc.getElementsByTagNameNS(ns, 'wpt')).map((w) => w.getElementsByTagNameNS(ns, 'name')[0].textContent);
    expect(names).toEqual(['Parking', 'Zone blanche 1, début', 'Zone blanche 1, fin']);
    expect(parseGpx(out, xmlParser).segments).toEqual(parseGpx(trackGpx, xmlParser).segments);
  });

  it('exporte un GPX précédé d\'un saut de ligne', () => {
    const out = enrichGpx(`\n${trackGpx}`, waypoints, xmlTools);
    expect(out.startsWith('<?xml')).toBe(true);
    expect(parseGpx(out, xmlParser).segments).toEqual(parseGpx(trackGpx, xmlParser).segments);
  });

  it('fonctionne sur une route et sans point existant', () => {
    const out = enrichGpx(routeGpx, waypoints, xmlTools);
    expect(out.indexOf('<wpt')).toBeLessThan(out.indexOf('<rte>'));
    expect(parseGpx(out, xmlParser).kind).toBe('route');
  });

  it('nomme le fichier exporté', () => {
    expect(enrichedFileName('Ma rando.gpx', 'zones-blanches')).toBe('Ma rando-zones-blanches.gpx');
    expect(enrichedFileName('a/b:c.GPX', 'x')).toBe('a-b-c-x.gpx');
    expect(enrichedFileName(null, 'x')).toBe('trace-x.gpx');
  });
});
