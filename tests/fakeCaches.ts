// Cache API factice (caches.open, match, put, addAll, keys, delete), pour les tests du
// mode hors ligne : la page et le Service Worker la partagent comme dans le navigateur.

interface Entry {
  body: ArrayBuffer;
  status: number;
  headers: [string, string][];
}

/** Adresse d'une requête, sans fragment. */
export const keyOf = (r: unknown): string => String(typeof r === 'string' ? r : (r as { url: string }).url).split('#')[0];

export type FakeCaches = ReturnType<typeof makeCaches>;

/** « network » sert à addAll, qui télécharge lui-même les fichiers. */
export function makeCaches(network: (request: unknown) => Promise<Response> = () => Promise.reject(new TypeError('Failed to fetch'))) {
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
    /** Adresses enregistrées dans un cache, pour les vérifications. */
    urls(name: string): string[] {
      return [...(store.get(name)?.keys() ?? [])];
    },
  };
}
