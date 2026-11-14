// L'application vue de l'interface : import d'un GPX, analyse, cadrage et fond Auto.
// La vraie classe App, avec une carte simulée et un faux réseau qui sert le jeu
// synthétique (tests/fixtures/synthetique).

import { DOMParser } from '@xmldom/xmldom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { readFixture, readJsonFixture } from './helpers';

const carte = vi.hoisted(() => ({
  /** Points de la vue, le centre en premier. */
  vue: [] as { lon: number; lat: number }[],
  zoom: 11,
  /** Marges des cadrages demandés, dans l'ordre. */
  cadrages: [] as { bottom: number }[],
  /** Rappel de MapView à la fin d'un mouvement de la carte. */
  finDeMouvement: (): void => undefined,
}));

vi.mock('maplibre-gl', () => ({ addProtocol: () => undefined }));
vi.mock('../src/map/mapView', () => ({
  MapView: class {
    constructor(options: { onMoveEnd: () => void }) {
      carte.finDeMouvement = options.onMoveEnd;
    }
    async setStyleInputs(): Promise<void> {}
    currentVectorStyle(): null {
      return null;
    }
    refreshCoverage(): void {}
    setCoverageOpacity(): void {}
    setTrack(): void {}
    setZone(): void {}
    setEndpoints(): void {}
    setCursor(): void {}
    fitBounds(_bbox: unknown, padding: { bottom: number }): void {
      carte.cadrages.push({ bottom: padding.bottom });
    }
    flyTo(): void {}
    locate(): void {}
    viewSamplePoints(): { lon: number; lat: number }[] {
      return carte.vue;
    }
    dataZoom(min: number, max: number): number {
      return Math.max(min, Math.min(max, Math.round(carte.zoom + 1)));
    }
    updateLabels(): void {}
  },
}));

const ARCHIVE = 'couverture-20261113-00.pmtiles';
const pmBytes = readFixture(`synthetique/${ARCHIVE}`);
const manifest = readJsonFixture<Record<string, unknown>>('synthetique/manifest.json');

/** Vue dans les données du jeu synthétique (France), puis vue sur Milan, hors des données. */
const grille = (lon: number, lat: number, pas: number): { lon: number; lat: number }[] => [
  { lon, lat },
  ...[-1, 0, 1].flatMap((dy) => [-1, 0, 1].filter((dx) => dx !== 0 || dy !== 0).map((dx) => ({ lon: lon + dx * pas, lat: lat + dy * pas }))),
];
const EN_FRANCE = grille(6.0, 44.55, 0.05);
const MILAN = grille(9.19, 45.46, 0.05);

/** Une barrière : les réponses attendent qu'on la lève. */
function barriere(): { attendre: Promise<void>; lever: () => void } {
  let lever = (): void => undefined;
  const attendre = new Promise<void>((resolve) => (lever = resolve));
  return { attendre, lever };
}

const reseau = {
  manifestStatus: 200,
  manifest: null as Promise<void> | null,
  /** Date de génération du manifest servi : une autre date simule une nouvelle publication. */
  generation: null as string | null,
  tuiles: null as Promise<void> | null,
  tuilesEnPanne: false,
  /** Nombre de lectures dans l'archive qui échouent encore (404 : archive disparue du serveur). */
  lecturesPerdues: 0,
};

function serveRange(init?: RequestInit): Response {
  const range = new Headers(init?.headers).get('range') ?? '';
  const m = /bytes=(\d+)-(\d+)/.exec(range)!;
  const start = Number(m[1]);
  const end = Math.min(Number(m[2]), pmBytes.length - 1);
  const slice = new Uint8Array(pmBytes.subarray(start, end + 1));
  return new Response(slice, { status: 206, headers: { 'content-length': String(slice.length), 'content-range': `bytes ${start}-${end}/${pmBytes.length}` } });
}

beforeEach(() => {
  carte.vue = EN_FRANCE;
  carte.zoom = 11;
  carte.cadrages = [];
  reseau.manifestStatus = 200;
  reseau.manifest = null;
  reseau.generation = null;
  reseau.tuiles = null;
  reseau.tuilesEnPanne = false;
  reseau.lecturesPerdues = 0;
  vi.stubGlobal('window', { addEventListener: () => undefined });
  vi.stubGlobal('navigator', { onLine: true });
  vi.stubGlobal('DOMParser', DOMParser);
  vi.stubGlobal('fetch', async (input: unknown, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url.endsWith('/data/manifest.json')) {
      if (reseau.manifest) await reseau.manifest;
      if (reseau.manifestStatus !== 200) return new Response('', { status: reseau.manifestStatus });
      const servi = reseau.generation ? { ...manifest, generated: reseau.generation } : manifest;
      return new Response(JSON.stringify(servi), { status: 200, headers: { 'content-type': 'application/json' } });
    }
    if (url.includes('.pmtiles')) {
      if (reseau.tuiles) await reseau.tuiles;
      if (reseau.tuilesEnPanne) throw new TypeError('Failed to fetch');
      if (reseau.lecturesPerdues > 0) {
        reseau.lecturesPerdues--;
        return new Response('', { status: 404 });
      }
      return serveRange(init);
    }
    return new Response('', { status: 404 });
  });
});
afterEach(() => vi.unstubAllGlobals());

const attendre = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function fichier(name: string, text: string, size = text.length): File {
  return { name, size, arrayBuffer: async () => new TextEncoder().encode(text).buffer } as unknown as File;
}

function gpx(name: string, lat0: number, lon0: number): File {
  const points = Array.from({ length: 30 }, (_, i) => `<trkpt lat="${(lat0 + i * 0.002).toFixed(5)}" lon="${(lon0 + i * 0.002).toFixed(5)}"><ele>${1500 + i * 10}</ele></trkpt>`);
  return fichier(`${name}.gpx`, `<?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>${name}</name><trkseg>${points.join('')}</trkseg></trk></gpx>`);
}
const essai = gpx('Essai', 44.55, 6.0);
/** Un autre tracé, une vingtaine de kilomètres plus loin : ses tuiles ne sont pas encore lues. */
const ailleurs = gpx('Ailleurs', 44.35, 5.7);

/** L'application, branchée sur une interface minimale : le panneau Rapport ouvert réserve 500 px en bas. */
async function creerApp() {
  const { App } = await import('../src/app');
  const { Store, initialState } = await import('../src/state');
  const app = new App(new Store(initialState()), {} as HTMLElement);
  app.setHooks({ toast: () => undefined, padding: () => ({ top: 0, right: 0, bottom: app.state.panel === 'report' ? 500 : 0, left: 0 }) });
  return app;
}

async function demarrer() {
  const app = await creerApp();
  await app.start();
  await attendre(300); // le pays au centre est relu 200 ms après chaque mouvement
  return app;
}

describe('import et analyse d\'un GPX', () => {
  it('cadre le tracé une fois le rapport ouvert, pour qu\'il ne soit pas caché dessous (ui-1)', async () => {
    const app = await demarrer();
    await app.importGpx(essai);
    expect(app.state.panel).toBe('report');
    expect(carte.cadrages.length).toBeGreaterThan(0);
    expect(carte.cadrages.at(-1)).toEqual({ bottom: 500 });
  });

  it('un fichier refusé pendant l\'analyse du tracé précédent ne l\'interrompt pas (ui-2)', async () => {
    const app = await demarrer();
    const tuiles = barriere();
    reseau.tuiles = tuiles.attendre; // tuiles lentes : l'analyse de « Ailleurs » dure
    const importAilleurs = app.importGpx(ailleurs);
    await vi.waitFor(() => expect(app.state.trackStatus).toBe('analyzing'));

    await app.importGpx(fichier('note.gpx', 'Ceci n\'est pas un GPX.'));
    expect(app.state.trackError?.key).toBe('gpx.error.invalid');
    expect(app.state.track?.parsed.name).toBe('Ailleurs');
    expect(app.state.trackStatus).toBe('analyzing');
    await app.importGpx(fichier('enorme.gpx', '<gpx/>', 41 * 1024 * 1024));
    expect(app.state.trackError?.key).toBe('gpx.error.tooBig');
    expect(app.state.trackStatus).toBe('analyzing');

    tuiles.lever();
    await importAilleurs;
    expect(app.state.track?.parsed.name).toBe('Ailleurs');
    expect(app.state.track?.analysis).not.toBeNull();
    expect(app.state.track?.report).not.toBeNull();
    expect(app.state.trackStatus).toBe('ready');
    expect(app.state.panel).toBe('report');
  });

  it('un fichier trop gros est annoncé plus gros que le maximum', async () => {
    const app = await demarrer();
    // 41 943 041 octets : un octet de plus que le maximum (40 Mio, soit 41,9 Mo).
    await app.importGpx(fichier('enorme.gpx', '<gpx/>', 40 * 1024 * 1024 + 1));
    const { size, max } = app.state.trackError?.params ?? {};
    expect(app.state.trackError?.key).toBe('gpx.error.tooBig');
    expect(Number(size)).toBeGreaterThan(Number(max));
  });

  it('un tracé importé avant l\'arrivée du manifest est analysé dès son arrivée, sans faux message d\'échec (ui-5)', async () => {
    const manifeste = barriere();
    reseau.manifest = manifeste.attendre; // réseau lent en montagne
    const app = await creerApp();
    const demarrage = app.start();
    expect(app.state.dataStatus).toBe('loading');
    await app.importGpx(essai);
    expect(app.state.track?.parsed.name).toBe('Essai');
    expect(app.state.trackError).toBeNull();
    expect(app.state.trackStatus).toBe('analyzing');
    expect(app.state.panel).not.toBe('report');

    manifeste.lever();
    await demarrage;
    await vi.waitFor(() => expect(app.state.track?.analysis).not.toBeNull());
    expect(app.state.trackStatus).toBe('ready');
    expect(app.state.trackError).toBeNull();
    expect(app.state.panel).toBe('report');
  });

  it('sans manifest, le tracé importé pendant le chargement annonce des données indisponibles (ui-5)', async () => {
    const manifeste = barriere();
    reseau.manifest = manifeste.attendre;
    reseau.manifestStatus = 404;
    const app = await creerApp();
    const demarrage = app.start();
    await app.importGpx(essai);
    manifeste.lever();
    await demarrage;
    expect(app.state.dataStatus).toBe('missing');
    expect(app.state.trackStatus).toBe('ready'); // et non « analyse en cours » pour toujours
    expect(app.state.trackError).toBeNull();
    expect(app.state.panel).toBe('report');
  });
});

describe('nouvelle publication des données pendant la visite', () => {
  it('le tracé est analysé de nouveau sans rouvrir le rapport ni déplacer la carte', async () => {
    const app = await demarrer();
    await app.importGpx(essai);
    const premiere = app.state.track?.analysis;
    expect(premiere).toBeTruthy();
    app.selectZone(app.state.track?.report?.zones[0]?.index ?? null);
    app.closePanel();
    const cadrages = carte.cadrages.length;
    // L'utilisateur regarde ailleurs, rapport fermé. Les données ont été republiées : l'archive
    // annoncée par le manifest chargé a disparu du serveur, et le manifest a changé.
    reseau.generation = '2026-12-01';
    reseau.lecturesPerdues = 1;
    carte.vue = grille(6.2, 44.7, 0.05);
    carte.finDeMouvement();
    await vi.waitFor(() => {
      expect(app.state.manifest?.generated).toBe('2026-12-01');
      expect(app.state.track?.analysis).not.toBe(premiere); // refaite sur les nouvelles données
      expect(app.state.trackStatus).toBe('ready');
    });
    expect(app.state.track?.report).not.toBeNull();
    expect(app.state.panel).toBeNull(); // le rapport ne se rouvre pas tout seul
    expect(carte.cadrages.length).toBe(cadrages); // la carte reste où l'utilisateur l'a mise
    expect(app.state.selectedZone).toBeNull(); // les zones ont pu changer avec les données
  });
});

describe('fond Auto', () => {
  async function deplacer(vue: { lon: number; lat: number }[]): Promise<void> {
    carte.vue = vue;
    carte.finDeMouvement();
    await attendre(300);
  }

  it('hors des données, passe au fond OpenStreetMap, puis revient au fond national (ui-10)', async () => {
    const app = await demarrer();
    expect(app.state.activeBasemap).toBe('ign-classique');
    await deplacer(MILAN);
    expect(app.state.activeBasemap).toBe('osm');
    await deplacer(EN_FRANCE);
    expect(app.state.activeBasemap).toBe('ign-classique');
  });

  it('centre hors des données (en mer, au bord des données) : fond du pays le plus présent dans la vue (ui-10)', async () => {
    const app = await demarrer();
    await deplacer(MILAN);
    expect(app.state.activeBasemap).toBe('osm');
    // Centre à l'ouest de l'emprise du jeu synthétique, les huit autres points en France.
    await deplacer([{ lon: 5.4, lat: 44.55 }, ...EN_FRANCE.slice(1)]);
    expect(app.state.activeBasemap).toBe('ign-classique');
  });

  it('une lecture de tuile qui échoue ne change pas de fond (ui-10)', async () => {
    const app = await demarrer();
    app.setBasemapChoice('swisstopo');
    app.setBasemapChoice('auto');
    expect(app.state.activeBasemap).toBe('swisstopo');
    reseau.tuilesEnPanne = true;
    await deplacer(grille(6.2, 44.7, 0.05)); // dans les données, mais rien ne se lit
    expect(app.state.activeBasemap).toBe('swisstopo');
  });
});
