import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';
import {
  _dictionaries,
  availableLanguages,
  countryName,
  DEFAULT_LANG,
  formatDataDate,
  formatDistance,
  formatKm,
  formatNumber,
  formatPercent,
  getLanguage,
  initLanguage,
  langFromUrl,
  setLanguage,
  t,
} from '../src/i18n';

const root = fileURLToPath(new URL('..', import.meta.url));

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return sourceFiles(path);
    return /\.ts$/.test(name) ? [path] : [];
  });
}

afterEach(() => setLanguage(DEFAULT_LANG));

describe('traductions', () => {
  const dictionaries = _dictionaries();
  const french = dictionaries.get('fr')!;

  it('propose les cinq langues, le français en premier', () => {
    expect(availableLanguages().map((l) => l.code)).toEqual(['fr', 'es', 'ca', 'it', 'de']);
    expect(availableLanguages().map((l) => l.name)).toEqual(['Français', 'Español', 'Català', 'Italiano', 'Deutsch']);
  });

  it('toutes les langues ont exactement les mêmes clés', () => {
    const reference = Object.keys(french).sort();
    expect(reference.length).toBeGreaterThan(100);
    for (const [code, dict] of dictionaries) {
      expect(Object.keys(dict).sort(), `langue ${code}`).toEqual(reference);
    }
  });

  it('les paramètres entre accolades sont les mêmes dans toutes les langues', () => {
    const params = (text: string): string[] => [...text.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();
    for (const [code, dict] of dictionaries) {
      for (const key of Object.keys(french)) {
        expect(params(dict[key]), `${code} : ${key}`).toEqual(params(french[key]));
      }
    }
  });

  it('aucune traduction n\'est vide', () => {
    for (const [code, dict] of dictionaries) {
      for (const [key, value] of Object.entries(dict)) expect(value.trim(), `${code} : ${key}`).not.toBe('');
    }
  });

  it('aucun texte ne contient de tiret cadratin ni demi-cadratin', () => {
    const files = [
      ...readdirSync(join(root, 'src/i18n/locales')).map((f) => join(root, 'src/i18n/locales', f)),
      join(root, 'README.md'),
      join(root, 'index.html'),
      join(root, 'public/manifest.webmanifest'),
      ...readdirSync(join(root, 'docs')).map((f) => join(root, 'docs', f)),
    ];
    for (const file of files) {
      const text = readFileSync(file, 'utf-8');
      expect(/[–—]/.test(text), file).toBe(false);
    }
  });

  it('toutes les clés utilisées dans le code existent en français', () => {
    const used = new Set<string>();
    for (const file of sourceFiles(join(root, 'src'))) {
      const text = readFileSync(file, 'utf-8');
      for (const match of text.matchAll(/\bt\(\s*'([a-zA-Z0-9_.]+)'/g)) used.add(match[1]);
      for (const match of text.matchAll(/(?:labelKey|key): '([a-zA-Z0-9_.]+\.[a-zA-Z0-9_.]+)'/g)) used.add(match[1]);
    }
    expect(used.size).toBeGreaterThan(80);
    const missing = [...used].filter((key) => !(key in french) && !(`${key}_other` in french));
    expect(missing).toEqual([]);
    // Clés composées à l'exécution.
    for (const key of ['service.data', 'service.voice', 'gpx.error.invalid', 'gpx.error.empty', 'sources.method.official_operator', 'sources.method.official_aggregated', 'sources.method.estimated', 'sources.levels.four', 'sources.levels.three', 'sources.levels.binary', 'level.none', 'level.limited', 'level.good', 'level.veryGood']) {
      expect(key in french, key).toBe(true);
    }
  });

  it('respecte le glossaire', () => {
    const term = (code: string, key: string): string => dictionaries.get(code)![key];
    expect(term('es', 'level.limited')).toBe('Cobertura limitada');
    expect(term('ca', 'level.limited')).toBe('Cobertura limitada');
    expect(term('it', 'level.limited')).toBe('Copertura limitata');
    expect(term('de', 'level.limited')).toBe('Eingeschränkte Abdeckung');
    expect(term('es', 'level.good')).toBe('Buena cobertura');
    expect(term('ca', 'level.good')).toBe('Bona cobertura');
    expect(term('it', 'level.good')).toBe('Buona copertura');
    expect(term('de', 'level.good')).toBe('Gute Abdeckung');
    expect(term('es', 'level.veryGood')).toBe('Muy buena cobertura');
    expect(term('ca', 'level.veryGood')).toBe('Molt bona cobertura');
    expect(term('it', 'level.veryGood')).toBe('Ottima copertura');
    expect(term('de', 'level.veryGood')).toBe('Sehr gute Abdeckung');
    expect(term('es', 'report.zonesHeading_one')).toContain('Zona sin cobertura');
    expect(term('ca', 'report.zonesHeading_one')).toContain('Zona sense cobertura');
    expect(term('it', 'report.zonesHeading_one')).toContain('Zona senza copertura');
    expect(term('de', 'report.zonesHeading_one')).toContain('Funkloch');
  });
});

describe('choix de la langue', () => {
  it('démarre en français par défaut', () => {
    expect(initLanguage('')).toBe('fr');
    expect(getLanguage()).toBe('fr');
  });

  it('le paramètre d\'URL ?lang force la langue', () => {
    expect(langFromUrl('?lang=es')).toBe('es');
    expect(langFromUrl('?lang=DE')).toBe('de');
    expect(langFromUrl('?lang=xx')).toBeNull();
    expect(langFromUrl('?autre=1')).toBeNull();
    expect(initLanguage('?lang=it')).toBe('it');
    expect(t('toolbar.network')).toBe('Rete');
  });

  it('retombe sur le français si une clé manque, puis sur la clé elle-même', () => {
    setLanguage('de');
    const german = _dictionaries().get('de')!;
    const saved = german['toolbar.report'];
    delete german['toolbar.report'];
    try {
      expect(t('toolbar.report')).toBe('Rapport');
    } finally {
      german['toolbar.report'] = saved;
    }
    expect(t('cle.inexistante')).toBe('cle.inexistante');
  });

  it('remplace les paramètres et choisit le pluriel', () => {
    setLanguage('fr');
    expect(t('report.zonesHeading', { count: 1 })).toBe('Zone blanche (1)');
    expect(t('report.zonesHeading', { count: 3 })).toBe('Zones blanches (3)');
    setLanguage('de');
    expect(t('report.zonesHeading', { count: 1 })).toBe('Funkloch (1)');
    expect(t('report.zonesHeading', { count: 2 })).toBe('Funklöcher (2)');
    expect(t('basemap.current', { name: 'swisstopo' })).toBe('Angezeigte Karte: swisstopo.');
  });

  it('ignore une langue inconnue', () => {
    setLanguage('fr');
    setLanguage('zz');
    expect(getLanguage()).toBe('fr');
  });
});

describe('nombres, distances et dates selon la langue', () => {
  it('formate en français', () => {
    setLanguage('fr');
    expect(formatKm(12449)).toBe('12,4');
    expect(formatNumber(1850).replace(/\s/g, ' ')).toBe('1 850');
    expect(formatDistance(850).replace(/\s/g, ' ')).toBe('850 m');
    expect(formatDistance(12449).replace(/\s/g, ' ')).toBe('12,4 km');
    expect(formatPercent(0.123).replace(/\s/g, ' ')).toBe('12 %');
    expect(formatPercent(0.034).replace(/\s/g, ' ')).toBe('3,4 %');
    expect(countryName('CH')).toBe('Suisse');
    expect(formatDataDate('2026-T2')).toBe('T2 2026');
    expect(formatDataDate('2026-11-13')).toBe('13 novembre 2026');
  });

  it('formate dans les autres langues', () => {
    setLanguage('de');
    expect(formatKm(12449)).toBe('12,4');
    expect(formatNumber(21850)).toBe('21.850');
    expect(countryName('CH')).toBe('Schweiz');
    expect(formatDataDate('2026-T2')).toBe('Q2 2026');
    setLanguage('es');
    expect(countryName('FR')).toBe('Francia');
    expect(formatDataDate('2026-03')).toMatch(/marzo de 2026/);
    setLanguage('ca');
    expect(countryName('AD')).toBe('Andorra');
    setLanguage('it');
    expect(countryName('CH')).toBe('Svizzera');
    expect(formatKm(1500)).toBe('1,5');
  });
});
