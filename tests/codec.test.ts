import { describe, expect, it } from 'vitest';
import {
  LEVEL_UNKNOWN,
  metaKey,
  packMeta,
  packSlots,
  readPixel,
  unpackCountry,
  unpackSlot,
  unpackSlots,
  unpackSourceType,
  writePixel,
} from '../src/coverage/codec';
import {
  ALL_OPERATORS,
  archiveForTile,
  buildLevelTable,
  buildLevelTables,
  countryByCode,
  countryHasOperatorChoice,
  effectiveOperator,
  manifestHasService,
  parseManifest,
} from '../src/coverage/manifest';
import { sampleManifest } from './helpers';

describe('encodage des canaux', () => {
  it('range 4 niveaux dans un octet et les relit', () => {
    for (const levels of [[0, 0, 0, 0], [3, 3, 3, 3], [1, 2, 3, 0], [3, 0, 1, 2]]) {
      const byte = packSlots(levels);
      expect(unpackSlots(byte)).toEqual(levels);
      levels.forEach((level, slot) => expect(unpackSlot(byte, slot)).toBe(level));
    }
    // Même disposition que le pipeline Python : l'emplacement i occupe les bits 2i et 2i+1.
    expect(packSlots([1, 2, 3, 0])).toBe(0b00111001);
    expect(packSlots([3])).toBe(3);
  });

  it('refuse un niveau hors de 0 à 3', () => {
    expect(() => packSlots([4, 0, 0, 0])).toThrow(RangeError);
    expect(() => packSlots([-1])).toThrow(RangeError);
    expect(() => packSlots([1.5])).toThrow(RangeError);
  });

  it('range le pays et le type de source dans le canal B', () => {
    for (let country = 0; country < 16; country++) {
      for (let type = 0; type < 4; type++) {
        const b = packMeta(country, type);
        expect(unpackCountry(b)).toBe(country);
        expect(unpackSourceType(b)).toBe(type);
        expect(metaKey(b)).toBe(b);
      }
    }
    expect(packMeta(3, 2)).toBe(0b100011);
    expect(() => packMeta(16, 0)).toThrow(RangeError);
    expect(() => packMeta(1, 4)).toThrow(RangeError);
  });

  it('écrit et relit un pixel sur les 4 canaux', () => {
    const rgba = new Uint8ClampedArray(4 * 4);
    writePixel(rgba, 1, { data: [3, 2, 1, 0], voice: [1, 1, 0, 3], country: 4, sourceType: 2 });
    writePixel(rgba, 2, null);
    expect(Array.from(rgba.slice(4, 8))).toEqual([packSlots([3, 2, 1, 0]), packSlots([1, 1, 0, 3]), packMeta(4, 2), 255]);
    const pixel = readPixel(rgba, 1);
    expect(pixel).toEqual({ data: packSlots([3, 2, 1, 0]), voice: packSlots([1, 1, 0, 3]), country: 4, sourceType: 2, inside: true });
    expect(readPixel(rgba, 2).inside).toBe(false);
    expect(readPixel(rgba, 0).inside).toBe(false);
  });
});

describe('lecture du manifest', () => {
  it('accepte un manifest valide', () => {
    const manifest = sampleManifest();
    expect(manifest.countries.map((c) => c.iso)).toEqual(['FR', 'CH', 'AD']);
    expect(countryByCode(manifest, 2)?.iso).toBe('CH');
    expect(countryByCode(manifest, 9)).toBeUndefined();
    expect(manifestHasService(manifest, 'voice')).toBe(true);
    expect(countryHasOperatorChoice(manifest.countries[0])).toBe(true);
    expect(countryHasOperatorChoice(manifest.countries[1])).toBe(false); // source agrégée
    expect(countryHasOperatorChoice(manifest.countries[2])).toBe(false); // opérateur unique
  });

  it('refuse un manifest mal formé avec un message clair', () => {
    const base = JSON.parse(JSON.stringify(sampleManifest()));
    expect(() => parseManifest(null)).toThrow(/manifest\.json invalide/);
    expect(() => parseManifest({ ...base, version: 2 })).toThrow(/version/);
    expect(() => parseManifest({ ...base, archives: [] })).toThrow(/archives/);
    const dup = JSON.parse(JSON.stringify(base));
    dup.countries[1].code = 1;
    expect(() => parseManifest(dup)).toThrow(/code pays en double/);
    const tooMany = JSON.parse(JSON.stringify(base));
    tooMany.countries[0].slots.push({ id: 'x', name: 'X' });
    expect(() => parseManifest(tooMany)).toThrow(/au plus 4/);
    const badService = JSON.parse(JSON.stringify(base));
    badService.countries[0].sources[0].services = ['fax'];
    expect(() => parseManifest(badService)).toThrow(/services/);
    const reserved = JSON.parse(JSON.stringify(base));
    reserved.countries[0].slots[0].id = ALL_OPERATORS;
    expect(() => parseManifest(reserved)).toThrow(/réservé/);
  });

  it('choisit la bonne archive selon z, x et y', () => {
    const manifest = parseManifest({
      ...JSON.parse(JSON.stringify(sampleManifest())),
      tiles: { size: 256, minzoom: 0, maxzoom: 12, format: 'png', blockZoom: 8 },
      archives: [
        { file: 'apercu.pmtiles', minzoom: 0, maxzoom: 7 },
        { file: 'ouest.pmtiles', minzoom: 8, maxzoom: 12, blocks: ['130/90', '130/91'] },
        { file: 'est.pmtiles', minzoom: 8, maxzoom: 12, blocks: ['131/90'] },
      ],
    });
    expect(archiveForTile(manifest, 5, 16, 11)?.file).toBe('apercu.pmtiles');
    expect(archiveForTile(manifest, 8, 130, 91)?.file).toBe('ouest.pmtiles');
    expect(archiveForTile(manifest, 8, 131, 90)?.file).toBe('est.pmtiles');
    // Une tuile z12 appartient au bloc z8 obtenu en divisant x et y par 16.
    expect(archiveForTile(manifest, 12, 130 * 16 + 5, 90 * 16 + 15)?.file).toBe('ouest.pmtiles');
    expect(archiveForTile(manifest, 12, 131 * 16, 90 * 16)?.file).toBe('est.pmtiles');
    expect(archiveForTile(manifest, 12, 132 * 16, 90 * 16)).toBeNull();
    expect(archiveForTile(manifest, 13, 0, 0)).toBeNull();
  });

  it('refuse des blocs sans zoom de bloc', () => {
    const bad = JSON.parse(JSON.stringify(sampleManifest()));
    bad.archives = [{ file: 'a.pmtiles', minzoom: 8, maxzoom: 12, blocks: ['1/2'] }];
    expect(() => parseManifest(bad)).toThrow(/blockZoom/);
  });
});

describe('tables de niveaux pilotées par le manifest', () => {
  const manifest = sampleManifest();
  const [france, suisse, andorre] = manifest.countries;

  it('lit un opérateur précis', () => {
    const table = buildLevelTable(france, france.sources[0], 'data', 'sfr');
    expect(table[packSlots([3, 1, 0, 2])]).toBe(1);
    expect(table[packSlots([0, 3, 0, 0])]).toBe(3);
  });

  it('prend le maximum des emplacements pour « tous opérateurs »', () => {
    const table = buildLevelTable(france, france.sources[0], 'data', ALL_OPERATORS);
    expect(table[packSlots([0, 0, 0, 0])]).toBe(0);
    expect(table[packSlots([0, 1, 0, 2])]).toBe(2);
    expect(table[packSlots([3, 1, 0, 2])]).toBe(3);
  });

  it('signale un service absent de la source', () => {
    const table = buildLevelTable(france, france.sources[0], 'voice', ALL_OPERATORS);
    expect(Array.from(new Set(table))).toEqual([LEVEL_UNKNOWN]);
  });

  it('applique la correspondance des niveaux d\'une source binaire ou agrégée', () => {
    // Suisse : valeur agrégée dans l'emplacement 0, tout niveau non nul vaut « bonne couverture ».
    const swiss = buildLevelTable(suisse, suisse.sources[0], 'data', 'peu-importe');
    expect(swiss[packSlots([0, 3, 3, 3])]).toBe(0);
    expect(swiss[packSlots([1, 0, 0, 0])]).toBe(2);
    expect(swiss[packSlots([3, 0, 0, 0])]).toBe(2);
    const andorra = buildLevelTable(andorre, andorre.sources[0], 'data', ALL_OPERATORS);
    expect([0, 1, 2, 3].map((v) => andorra[packSlots([v])])).toEqual([0, 1, 2, 2]);
  });

  it('indexe les tables par pays et type de source', () => {
    const tables = buildLevelTables(manifest, { service: 'data', operators: { FR: 'free' } });
    expect(tables).toHaveLength(64);
    expect(tables[packMeta(1, 0)]?.[packSlots([3, 3, 3, 1])]).toBe(1);
    expect(tables[packMeta(2, 1)]?.[packSlots([2])]).toBe(2);
    expect(tables[packMeta(5, 2)]?.[packSlots([1])]).toBe(1);
    expect(tables[packMeta(1, 2)]).toBeNull(); // combinaison inconnue du manifest
    expect(tables[packMeta(7, 0)]).toBeNull();
    // forceAll ignore l'opérateur choisi.
    const all = buildLevelTables(manifest, { service: 'data', operators: { FR: 'free' } }, true);
    expect(all[packMeta(1, 0)]?.[packSlots([3, 3, 3, 1])]).toBe(3);
  });

  it('retombe sur tous les opérateurs si l\'opérateur demandé n\'existe pas', () => {
    const table = buildLevelTable(france, france.sources[0], 'data', 'inconnu');
    expect(table[packSlots([0, 0, 2, 0])]).toBe(2);
    expect(effectiveOperator(france, { service: 'data', operators: { FR: 'inconnu' } })).toBeNull();
    expect(effectiveOperator(france, { service: 'data', operators: { FR: 'orange' } })?.name).toBe('Orange');
    expect(effectiveOperator(suisse, { service: 'data', operators: { CH: 'orange' } })).toBeNull();
  });
});
