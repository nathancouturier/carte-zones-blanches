// Service Worker (public/sw.js), chargé tel quel dans une machine virtuelle, avec
// une Cache API factice et un faux GitHub Pages : chaque déploiement remplace
// tout le site, comme actions/deploy-pages.

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { shellComplete } from '../src/offline/manager';
import { injectShell, shellList, type ShellList } from '../src/offline/shell';

const ORIGIN = 'https://exemple.github.io';
const BASE = `${ORIGIN}/carte-zones-blanches/`;
const SOURCE = readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8');
/** Délai d'attente du réseau donné au Service Worker dans ces tests, en millisecondes. */
const DELAI = 40;

interface Entry {
  body: ArrayBuffer;
  status: number;
  headers: [string, string][];
}

const keyOf = (r: unknown): string => String(typeof r === 'string' ? r : (r as { url: string }).url).split('#')[0];

/** Cache API factice, partagée par toutes les versions du Service Worker. */
function makeCaches(network: (request: unknown) => Promise<Response>) {
  const store = new Map<string, Map<string, Entry>>();
  const toResponse = (e: Entry): Response => {
    const r = new Response(e.body.slice(0), { status: e.status, headers: e.headers });
    Object.defineProperty(r, 'type', { value: 'basic' });
    return r;
  };
  const entry = async (res: Response): Promise<Entry> => ({ body: await res.arrayBuffer(), status: res.status, headers: [...res.headers] });
  class FakeCache {
    constructor(private readonly map: Map<string, Entry>) {}
    async put(req: unknown, res: Response): Promise<void> {
      this.map.set(keyOf(req), await entry(res));
    }
    async addAll(requests: unknown[]): Promise<void> {
      // Comme le vrai addAll : tout ou rien.
      const responses = await Promise.all(requests.map((r) => network(r)));
      if (responses.some((r) => !r.ok)) throw new TypeError('addAll : réponse en erreur');
      const entries = await Promise.all(responses.map(entry));
      requests.forEach((r, i) => this.map.set(keyOf(r), entries[i]));
    }
    async match(req: unknown): Promise<Response | undefined> {
      const e = this.map.get(keyOf(req));
      return e ? toResponse(e) : undefined;
    }
    async keys(): Promise<{ url: string }[]> {
      return [...this.map.keys()].map((url) => ({ url }));
    }
    async delete(req: unknown): Promise<boolean> {
      return this.map.delete(keyOf(req));
    }
  }
  return {
    store,
    async open(name: string) {
      if (!store.has(name)) store.set(name, new Map());
      return new FakeCache(store.get(name)!);
    },
    async match(req: unknown) {
      for (const m of store.values()) {
        const e = m.get(keyOf(req));
        if (e) return toResponse(e);
      }
      return undefined;
    },
    async has(name: string) {
      return store.has(name);
    },
    async delete(name: string) {
      return store.delete(name);
    },
    async keys() {
      return [...store.keys()];
    },
  };
}

interface Deployment {
  files: Map<string, string>;
  shell: ShellList;
}

/** Fichiers d'une version du site, et la liste que la construction écrit dans sw.js. */
function build(version: string): Deployment {
  const js = `assets/index-${version}.js`;
  const css = `assets/index-${version}.css`;
  const index = `<!doctype html><script type="module" src="/carte-zones-blanches/${js}"></script><link rel="stylesheet" href="/carte-zones-blanches/${css}">`;
  const files = new Map([
    [BASE, index],
    [`${BASE}${js}`, `// code ${version}`],
    [`${BASE}${css}`, `/* css ${version} */`],
    [`${BASE}icon.svg`, '<svg/>'],
    [`${BASE}data/manifest.json`, JSON.stringify({ generated: version })],
  ]);
  const shell: ShellList = {
    version: `v${version}`,
    index: createHash('sha256').update(index).digest('hex'),
    files: ['./', js, css, 'icon.svg'],
  };
  return { files, shell };
}

function makeServer() {
  let files = new Map<string, string>();
  const state = { mode: 'up' as 'up' | 'down' | 'hang' | 'slow', hits: [] as string[] };
  const network = async (req: unknown): Promise<Response> => {
    const url = keyOf(req).split('?')[0]; // GitHub Pages ignore la chaîne de requête
    state.hits.push(url);
    if (state.mode === 'hang') return new Promise<Response>(() => undefined);
    if (state.mode === 'down') throw new TypeError('Failed to fetch');
    if (state.mode === 'slow') await new Promise((resolve) => setTimeout(resolve, DELAI * 3));
    const body = files.get(url);
    const r = new Response(body ?? 'Not found', { status: body === undefined ? 404 : 200 });
    Object.defineProperty(r, 'type', { value: 'basic' });
    return r;
  };
  return { network, state, deploy: (d: Deployment) => (files = d.files) };
}

type Caches = ReturnType<typeof makeCaches>;

/** Une version du Service Worker : celle que la construction de « deployment » a écrite. */
function serviceWorker(caches: Caches, network: (req: unknown) => Promise<Response>, deployment: Deployment) {
  const listeners: Record<string, (event: unknown) => void> = {};
  const self = {
    addEventListener: (type: string, fn: (event: unknown) => void) => (listeners[type] = fn),
    skipWaiting: async () => undefined,
    clients: { claim: async () => undefined },
    registration: { scope: BASE },
    location: { origin: ORIGIN, href: `${BASE}sw.js?delai=${DELAI}` },
  };
  vm.runInNewContext(injectShell(SOURCE, deployment.shell), { self, caches, fetch: network, URL, Request, Response, Headers, crypto, setTimeout, clearTimeout, console });
  const lifecycle = async (type: 'install' | 'activate'): Promise<void> => {
    let p: unknown;
    listeners[type]?.({ waitUntil: (x: unknown) => (p = x) });
    await p;
  };
  const swFetch = (url: string, mode = 'cors'): Promise<Response> => {
    const request = { url, method: 'GET', mode, headers: new Headers() };
    let response: Promise<Response> | null = null;
    listeners.fetch({ request, respondWith: (p: Promise<Response>) => (response = p) });
    return response ?? network(request);
  };
  /** Le navigateur charge le document, puis son script. */
  const loadPage = async (url = BASE): Promise<string> => {
    let step = 'document';
    try {
      const html = await (await swFetch(url, 'navigate')).text();
      const js = /src="\/carte-zones-blanches\/(assets\/[^"]+\.js)"/.exec(html)![1];
      step = js;
      const script = await swFetch(`${BASE}${js}`);
      if (!script.ok) throw new Error(`HTTP ${script.status}`);
      return await script.text();
    } catch (error) {
      return `PAGE BLANCHE (${step} : ${String(error)})`;
    }
  };
  return { install: () => lifecycle('install'), activate: () => lifecycle('activate'), swFetch, loadPage };
}

let server: ReturnType<typeof makeServer>;
let caches: Caches;

/** Déploie une version et installe son Service Worker, comme le navigateur à la visite suivante. */
async function deployAndInstall(version: string) {
  const deployment = build(version);
  server.deploy(deployment);
  const sw = serviceWorker(caches, server.network, deployment);
  await sw.install();
  await sw.activate();
  return sw;
}

const shellCaches = (): string[] => [...caches.store.keys()].filter((name) => name.startsWith('czb-coque-'));

beforeEach(() => {
  server = makeServer();
  caches = makeCaches(server.network);
});

describe('Service Worker : coque hors ligne', () => {
  it('enregistre à l\'installation index.html et tous ses fichiers, puis démarre sans réseau', async () => {
    const sw = await deployAndInstall('AAAA');
    server.state.mode = 'down';
    expect(await sw.loadPage()).toBe('// code AAAA');
  });

  it('ne mélange jamais deux versions : index.html reçu en ligne puis réseau coupé avant le script (hl-1)', async () => {
    const v1 = await deployAndInstall('AAAA');
    // Push sur main : le document V2 arrive, puis le réseau tombe avant son script.
    server.deploy(build('BBBB'));
    await (await v1.swFetch(BASE, 'navigate')).text();
    server.state.mode = 'down';
    expect(await v1.loadPage()).toBe('// code AAAA');
  });

  it('une seule version à la fois : les anciennes coques sont effacées et ?lang retrouve la page (hl-7)', async () => {
    const v1 = await deployAndInstall('V1');
    await v1.loadPage(`${BASE}?lang=es`); // signet visité en V1
    let sw = v1;
    for (const version of ['V2', 'V3', 'V4']) {
      sw = await deployAndInstall(version);
      await sw.loadPage();
    }
    expect(shellCaches()).toEqual(['czb-coque-vV4']);
    const entries = (await (await caches.open('czb-coque-vV4')).keys()).map((k) => k.url.replace(BASE, ''));
    expect(entries.filter((e) => e.startsWith('assets/'))).toEqual(['assets/index-V4.js', 'assets/index-V4.css']);
    server.state.mode = 'down';
    expect(await sw.loadPage(`${BASE}?lang=es`)).toBe('// code V4');
    expect(await sw.loadPage(`${BASE}index.html?lang=de`)).toBe('// code V4');
  });

  it('refuse une installation dont index.html ne correspond pas à la liste (fichiers d\'une autre version)', async () => {
    const v1 = await deployAndInstall('V1');
    const v2 = build('V2');
    // Le serveur sert encore l'index.html de V1 avec les fichiers de V2.
    server.deploy({ ...v2, files: new Map([...v2.files, [BASE, build('V1').files.get(BASE)!]]) });
    const sw = serviceWorker(caches, server.network, v2);
    await expect(sw.install()).rejects.toThrow();
    // La version installée reste entière.
    server.state.mode = 'down';
    expect(await v1.loadPage()).toBe('// code V1');
  });

  it('par réseau faible, sert la copie locale après un court délai (hl-4)', async () => {
    const sw = await deployAndInstall('AAAA');
    server.state.mode = 'hang'; // « en ligne », mais rien ne revient
    const started = Date.now();
    expect(await sw.loadPage(`${BASE}?lang=it`)).toBe('// code AAAA');
    expect(Date.now() - started).toBeLessThan(DELAI + 400);
  });

  it('sert le manifest enregistré pour le hors ligne quand le réseau tarde, et seulement celui-là', async () => {
    const sw = await deployAndInstall('AAAA');
    // En ligne : le manifest du serveur, jamais rangé dans la coque.
    expect(await (await sw.swFetch(`${BASE}data/manifest.json`)).text()).toBe('{"generated":"AAAA"}');
    const offline = await caches.open('czb-hors-ligne-v1');
    await offline.put(`${BASE}data/manifest.json`, new Response('{"generated":"préparation"}', { headers: { 'x-czb-copie-locale': '1' } }));
    server.state.mode = 'hang';
    const copy = await sw.swFetch(`${BASE}data/manifest.json`);
    expect(await copy.text()).toBe('{"generated":"préparation"}');
    expect(copy.headers.get('x-czb-copie-locale')).toBe('1');
    server.state.mode = 'down';
    expect(await (await sw.swFetch(`${BASE}data/manifest.json`)).text()).toBe('{"generated":"préparation"}');
  });

  it('sans copie locale, attend le réseau au-delà du délai', async () => {
    const deployment = build('AAAA');
    server.deploy(deployment);
    const sw = serviceWorker(caches, server.network, deployment); // pas encore installé : rien en local
    server.state.mode = 'slow'; // le réseau répond, mais après le délai
    expect(await (await sw.swFetch(`${BASE}data/manifest.json`)).text()).toBe('{"generated":"AAAA"}');
    expect(await sw.loadPage()).toBe('// code AAAA');
  });
});

describe('liste de la coque écrite à la construction', () => {
  const file = (path: string, content = path) => ({ path, content: Buffer.from(content) });

  it('garde index.html et ses fichiers, sans les données ni les cartes de source', () => {
    const list = shellList([
      file('index.html', '<html>'),
      file('assets/index-A.js'),
      file('assets/index-A.js.map'),
      file('assets/maplibre-gl-worker-B.mjs'),
      file('icon.svg'),
      file('sw.js'),
      file('data/manifest.json'),
      file('data/couverture-1.pmtiles'),
    ]);
    expect(list.files).toEqual(['assets/index-A.js', 'assets/maplibre-gl-worker-B.mjs', 'icon.svg', './']);
    expect(list.index).toBe(createHash('sha256').update('<html>').digest('hex'));
    expect(list.version).toMatch(/^[0-9a-f]{12}$/);
  });

  it('change de version quand un fichier change, pas quand seules les données changent', () => {
    const base = [file('index.html', '<html>'), file('assets/index-A.js', 'code')];
    const version = shellList(base).version;
    expect(shellList([...base, file('data/manifest.json', 'autre')]).version).toBe(version);
    expect(shellList([file('index.html', '<html>'), file('assets/index-A.js', 'code modifié')]).version).not.toBe(version);
  });

  it('écrit la liste dans le Service Worker, et refuse un fichier sans la ligne prévue', () => {
    const shell = { version: 'abc', index: 'def', files: ['./'] };
    expect(injectShell(SOURCE, shell)).toContain('const SHELL = {"version":"abc","index":"def","files":["./"]};');
    expect(() => injectShell('// rien', shell)).toThrow();
  });
});

describe('vérification de la coque par la page avant « Préparer »', () => {
  beforeEach(() => {
    vi.stubGlobal('caches', caches);
    vi.stubGlobal('location', { href: BASE, origin: ORIGIN });
  });
  afterEach(() => vi.unstubAllGlobals());

  it('vraie si la coque installée est complète, fausse s\'il en manque un fichier ou s\'il n\'y en a pas', async () => {
    expect(await shellComplete('/carte-zones-blanches/')).toBe(false);
    await deployAndInstall('AAAA');
    expect(await shellComplete('/carte-zones-blanches/')).toBe(true);
    await (await caches.open('czb-coque-vAAAA')).delete(`${BASE}assets/index-AAAA.js`);
    expect(await shellComplete('/carte-zones-blanches/')).toBe(false);
  });
});
