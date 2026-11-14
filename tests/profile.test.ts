import { afterEach, describe, expect, it } from 'vitest';
import { packMeta, SOURCE_ESTIMATED, SOURCE_OFFICIAL_OPERATOR } from '../src/coverage/codec';
import { CLASS_OUTSIDE } from '../src/gpx/analyze';
import type { Sample } from '../src/gpx/resample';
import { DEFAULT_LANG, setLanguage } from '../src/i18n';
import { estimatedFlags, profileColumns, profileKeyIndex, profilePointText, profileSummary } from '../src/ui/profile';

function track(n: number, ele: (i: number) => number | null = (i) => 1000 + i): Sample[] {
  return Array.from({ length: n }, (_, i) => ({ lon: 6 + i * 0.00025, lat: 45, ele: ele(i), dist: i * 20, seg: 0 }));
}

describe('profil altimétrique', () => {
  it('renvoie une colonne par intervalle sur un tracé court', () => {
    const samples = track(5);
    const columns = profileColumns(samples, new Uint8Array([3, 3, 0, 2, 2]));
    expect(columns).toHaveLength(4);
    expect(columns.map((c) => [c.start, c.end])).toEqual([[0, 20], [20, 40], [40, 60], [60, 80]]);
    // Chaque intervalle prend la couleur de son point de départ, comme le tracé sur la carte.
    expect(columns.map((c) => c.cls)).toEqual([3, 3, 0, 2]);
    expect(columns[0]).toMatchObject({ eleStart: 1000, eleEnd: 1001 });
    // Les colonnes se touchent et couvrent tout le tracé.
    for (let i = 1; i < columns.length; i++) expect(columns[i].start).toBe(columns[i - 1].end);
  });

  it('regroupe un long tracé sans perdre une courte zone blanche', () => {
    const n = 5001; // 100 km
    const classes = new Uint8Array(n).fill(3);
    classes[2500] = 0; // 20 m sans réseau
    classes[4000] = 1;
    const columns = profileColumns(track(n), classes, 100);
    expect(columns.length).toBeLessThanOrEqual(100);
    expect(columns.length).toBeGreaterThan(90);
    expect(columns[0].start).toBe(0);
    expect(columns[columns.length - 1].end).toBe((n - 1) * 20);
    expect(columns.filter((c) => c.cls === 0)).toHaveLength(1);
    expect(columns.filter((c) => c.cls === 1)).toHaveLength(1);
    for (let i = 1; i < columns.length; i++) expect(columns[i].start).toBe(columns[i - 1].end);
  });

  it('donne la priorité à la zone blanche sur le hors zone et la bonne couverture', () => {
    const samples = track(4);
    expect(profileColumns(samples, new Uint8Array([3, CLASS_OUTSIDE, 0, 3]), 1)[0].cls).toBe(0);
    expect(profileColumns(samples, new Uint8Array([3, CLASS_OUTSIDE, 2, 3]), 1)[0].cls).toBe(CLASS_OUTSIDE);
    expect(profileColumns(samples, new Uint8Array([3, 1, 2, 3]), 1)[0].cls).toBe(1);
  });

  it('fonctionne avant l\'analyse et refuse un tracé sans altitude', () => {
    expect(profileColumns(track(10), null)).toHaveLength(9);
    expect(profileColumns(track(10), null)[0].cls).toBe(-1);
    expect(profileColumns(track(10, () => null), null)).toEqual([]);
    // Trop peu de points avec une altitude : pas de profil.
    expect(profileColumns(track(10, (i) => (i < 4 ? 1000 : null)), null)).toEqual([]);
    expect(profileColumns(track(1), null)).toEqual([]);
    expect(profileColumns([], null)).toEqual([]);
  });

  it('garde le profil quand quelques altitudes manquent, sans les inventer', () => {
    // Les deux premiers points n'ont pas d'altitude (avant le premier point connu du GPX).
    const columns = profileColumns(track(10, (i) => (i < 2 ? null : 1000 + i)), null);
    expect(columns).toHaveLength(9);
    expect(columns.map((c) => [c.eleStart, c.eleEnd]).slice(0, 3)).toEqual([[null, null], [null, 1002], [1002, 1003]]);
  });
});

describe('profil altimétrique : portions estimées, clavier, lecteurs d\'écran', () => {
  afterEach(() => setLanguage(DEFAULT_LANG));

  it('repère les points dont la couverture vient d\'une source estimée', () => {
    const meta = new Uint8Array([packMeta(1, SOURCE_OFFICIAL_OPERATOR), packMeta(5, SOURCE_ESTIMATED), packMeta(5, SOURCE_ESTIMATED), 0]);
    expect([...estimatedFlags({ meta, inside: new Uint8Array([1, 1, 0, 0]) })]).toEqual([0, 1, 0, 0]);
  });

  it('marque les colonnes qui comptent une portion estimée', () => {
    const columns = profileColumns(track(6), new Uint8Array([3, 3, 0, 0, 3, 3]), 300, new Uint8Array([0, 0, 1, 1, 0, 0]));
    expect(columns.map((c) => c.estimated)).toEqual([false, false, true, true, false]);
    expect(profileColumns(track(6), null).every((c) => !c.estimated)).toBe(true);
  });

  it('dit, pour un point, le km, l\'altitude, la couverture et si elle est estimée', () => {
    setLanguage('fr');
    const sample = { lon: 6, lat: 45, ele: 1850, dist: 12400, seg: 0 };
    expect(profilePointText(sample, 0, true).replace(/\s/g, ' ')).toBe('km 12,4, 1 850 m, Pas de couverture, estimée');
    expect(profilePointText({ ...sample, ele: null }, 3, false)).toBe('km 12,4, altitude inconnue, Très bonne couverture');
    expect(profilePointText(sample, -1, false).replace(/\s/g, ' ')).toBe('km 12,4, 1 850 m');
  });

  it('se parcourt au clavier : flèches, pages, Début et Fin', () => {
    expect(profileKeyIndex('ArrowRight', 0, 1001)).toBe(10); // 1 % du tracé
    expect(profileKeyIndex('ArrowUp', 0, 1001)).toBe(10);
    expect(profileKeyIndex('ArrowLeft', 5, 1001)).toBe(0);
    expect(profileKeyIndex('PageUp', 0, 1001)).toBe(100); // 10 %
    expect(profileKeyIndex('PageDown', 950, 1001)).toBe(850);
    expect(profileKeyIndex('Home', 500, 1001)).toBe(0);
    expect(profileKeyIndex('End', 3, 1001)).toBe(1000);
    expect(profileKeyIndex('ArrowRight', 999, 1001)).toBe(1000);
    expect(profileKeyIndex('ArrowRight', 0, 20)).toBe(1); // au moins un point
    expect(profileKeyIndex('Enter', 0, 1001)).toBeNull();
  });

  it('résume la part du parcours sans couverture pour les lecteurs d\'écran', () => {
    setLanguage('fr');
    const classes = new Uint8Array([3, 0, 0, 0, 0, 3, 3, 3, 3, 3, 3]);
    expect(profileSummary(track(11), classes).replace(/\s/g, ' ')).toBe('40 % du parcours sans couverture.');
    expect(profileSummary(track(11), null)).toBe('');
    expect(profileSummary(track(3), new Uint8Array([CLASS_OUTSIDE, CLASS_OUTSIDE, CLASS_OUTSIDE]))).toBe('');
  });
});
