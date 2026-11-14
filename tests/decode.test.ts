import { describe, expect, it } from 'vitest';
import { TILE_SIZE } from '../src/coverage/codec';
import { createTileDecoder } from '../src/coverage/decode';

// Décodeurs factices : la tuile n° i est un octet i ; ses vrais pixels ont tous R = i.
// Le « canvas » d'un navigateur qui protège contre le pistage ajoute un léger bruit.

const wait = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

function truth(i: number): Uint8ClampedArray {
  const data = new Uint8ClampedArray(TILE_SIZE * TILE_SIZE * 4);
  for (let o = 0; o < data.length; o += 4) {
    data[o] = i;
    data[o + 3] = 255;
  }
  return data;
}

function noisy(i: number): Uint8ClampedArray {
  const data = truth(i);
  data[4 * 1000 + 1] += 1; // un canal d'un pixel modifié
  return data;
}

const tile = (i: number): ArrayBuffer => new Uint8Array([i]).buffer;
const index = (bytes: ArrayBuffer): number => new Uint8Array(bytes)[0];

function fakes(options: { noise: boolean; canvasDelay: (i: number) => number; jsDelay?: number; jsFails?: boolean }) {
  const calls = { js: 0, canvas: 0 };
  return {
    calls,
    decoders: {
      canvas: async (bytes: ArrayBuffer) => {
        calls.canvas++;
        const i = index(bytes);
        await wait(options.canvasDelay(i));
        return options.noise ? noisy(i) : truth(i);
      },
      js: async (bytes: ArrayBuffer) => {
        calls.js++;
        await wait(options.jsDelay ?? 5);
        if (options.jsFails) throw new Error('wrong PNG signature');
        return truth(index(bytes));
      },
    },
  };
}

function corrupted(results: Uint8ClampedArray[]): number {
  return results.filter((data, i) => {
    const expected = truth(i);
    return data.length !== expected.length || data.some((v, o) => v !== expected[o]);
  }).length;
}

describe('décodeur des tuiles : contrôle du canvas', () => {
  it('ne laisse passer aucune tuile bruitée quand les tuiles arrivent en rafale', async () => {
    const { decoders } = fakes({ noise: true, canvasDelay: (i) => (i * 7) % 23 });
    const decode = createTileDecoder(undefined, decoders);
    const results = await Promise.all(Array.from({ length: 32 }, (_, i) => decode(tile(i))));
    expect(corrupted(results)).toBe(0);
    expect(decode.status.mode).toBe('js');
  });

  it('ne laisse passer aucune tuile bruitée quand les tuiles arrivent en flux', async () => {
    const { decoders } = fakes({ noise: true, canvasDelay: (i) => (i % 3 === 0 ? 12 : 1) });
    const decode = createTileDecoder(undefined, decoders);
    const pending: Promise<Uint8ClampedArray>[] = [];
    for (let i = 0; i < 40; i++) {
      pending.push(decode(tile(i)));
      await wait(1 + (i % 3));
    }
    expect(corrupted(await Promise.all(pending))).toBe(0);
  });

  it('fait confiance au canvas après trois vérifications sans écart, sans en lancer davantage', async () => {
    const { decoders, calls } = fakes({ noise: false, canvasDelay: () => 1, jsDelay: 10 });
    const decode = createTileDecoder(undefined, decoders);
    // Les dix tuiles sortent du canvas pendant que les trois premières vérifications sont en cours.
    const results = await Promise.all(Array.from({ length: 10 }, (_, i) => decode(tile(i))));
    expect(corrupted(results)).toBe(0);
    expect(calls.js).toBe(3);
    expect(decode.status).toEqual({ mode: 'canvas', checked: 3 });
    await decode(tile(11));
    expect(calls.js).toBe(3);
  });

  it('une erreur du décodeur de référence ne fait pas échouer la tuile', async () => {
    const { decoders } = fakes({ noise: false, canvasDelay: () => 1, jsFails: true });
    const decode = createTileDecoder(undefined, decoders);
    const results = await Promise.all(Array.from({ length: 5 }, (_, i) => decode(tile(i))));
    expect(corrupted(results)).toBe(0);
    expect(decode.status.mode).toBe('canvas');
  });

  it('passe au décodeur JavaScript si le canvas ne sait pas décoder', async () => {
    const reasons: string[] = [];
    const decode = createTileDecoder((reason) => reasons.push(reason), {
      canvas: async () => {
        throw new Error('canvas indisponible');
      },
      js: async (bytes) => truth(index(bytes)),
    });
    expect(corrupted([await decode(tile(0))])).toBe(0);
    expect(decode.status.mode).toBe('js');
    expect(reasons).toHaveLength(1);
  });
});
