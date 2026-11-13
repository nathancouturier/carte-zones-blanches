// Décodage d'une tuile PNG en tableau RGBA.
//
// Voie normale : le navigateur décode l'image (createImageBitmap, sans
// prémultiplication de l'alpha ni conversion de couleurs), puis on relit les
// pixels avec getImageData.
//
// Certains navigateurs ajoutent volontairement un léger bruit aux pixels relus
// d'un canvas (protection contre le pistage). Ici ce bruit fausserait les
// données. Les premières tuiles sont donc décodées une seconde fois en
// JavaScript pur : au moindre écart, on bascule définitivement sur ce décodeur.

import { TILE_SIZE } from './codec';

export type TileDecoder = (bytes: ArrayBuffer) => Promise<Uint8ClampedArray>;

const PIXELS = TILE_SIZE * TILE_SIZE;

let sharedContext: OffscreenCanvasRenderingContext2D | CanvasRenderingContext2D | null = null;

function context2d(): OffscreenCanvasRenderingContext2D | CanvasRenderingContext2D {
  if (sharedContext) return sharedContext;
  let ctx: OffscreenCanvasRenderingContext2D | CanvasRenderingContext2D | null;
  if (typeof OffscreenCanvas !== 'undefined') {
    ctx = new OffscreenCanvas(TILE_SIZE, TILE_SIZE).getContext('2d', { willReadFrequently: true });
  } else {
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = TILE_SIZE;
    ctx = canvas.getContext('2d', { willReadFrequently: true });
  }
  if (!ctx) throw new Error('Canvas 2D indisponible');
  sharedContext = ctx;
  return ctx;
}

export function canvasDecodingAvailable(): boolean {
  return typeof createImageBitmap === 'function' && (typeof OffscreenCanvas !== 'undefined' || typeof document !== 'undefined');
}

/** Décodage par le navigateur. */
export async function decodeWithCanvas(bytes: ArrayBuffer): Promise<Uint8ClampedArray> {
  const bitmap = await createImageBitmap(new Blob([bytes], { type: 'image/png' }), {
    premultiplyAlpha: 'none',
    colorSpaceConversion: 'none',
  });
  try {
    if (bitmap.width !== TILE_SIZE || bitmap.height !== TILE_SIZE) {
      throw new Error(`Tuile de ${bitmap.width} x ${bitmap.height} px, ${TILE_SIZE} attendus`);
    }
    const ctx = context2d();
    ctx.globalCompositeOperation = 'copy';
    ctx.drawImage(bitmap, 0, 0);
    return ctx.getImageData(0, 0, TILE_SIZE, TILE_SIZE).data;
  } finally {
    bitmap.close();
  }
}

/** Décodage en JavaScript pur, insensible au navigateur. */
export async function decodeWithJs(bytes: ArrayBuffer): Promise<Uint8ClampedArray> {
  const { decode, convertIndexedToRgb } = await import('fast-png');
  const png = decode(bytes);
  if (png.width !== TILE_SIZE || png.height !== TILE_SIZE) {
    throw new Error(`Tuile de ${png.width} x ${png.height} px, ${TILE_SIZE} attendus`);
  }
  if (png.depth === 16) throw new Error('PNG 16 bits non pris en charge');
  let source: ArrayLike<number>;
  let channels: number;
  if (png.palette) {
    source = convertIndexedToRgb(png);
    channels = png.palette[0].length;
  } else {
    if (png.depth !== 8) throw new Error(`Profondeur PNG non prise en charge : ${png.depth}`);
    source = png.data;
    channels = png.channels;
  }
  const out = new Uint8ClampedArray(PIXELS * 4);
  if (channels === 4) {
    out.set(source);
  } else if (channels === 3) {
    for (let i = 0, s = 0, o = 0; i < PIXELS; i++, s += 3, o += 4) {
      out[o] = source[s];
      out[o + 1] = source[s + 1];
      out[o + 2] = source[s + 2];
      out[o + 3] = 255;
    }
  } else {
    throw new Error(`PNG à ${channels} canal ou canaux non pris en charge`);
  }
  // Même convention que le canvas : un pixel transparent n'a pas de couleur.
  for (let o = 0; o < out.length; o += 4) {
    if (out[o + 3] === 0) out[o] = out[o + 1] = out[o + 2] = 0;
  }
  return out;
}

function sameData(a: Uint8ClampedArray, b: Uint8ClampedArray): boolean {
  if (a.length !== b.length) return false;
  for (let o = 0; o < a.length; o += 4) {
    // Hors zone (alpha nul), seule la transparence compte.
    if (a[o + 3] !== b[o + 3]) return false;
    if (a[o + 3] !== 0 && (a[o] !== b[o] || a[o + 1] !== b[o + 1] || a[o + 2] !== b[o + 2])) return false;
  }
  return true;
}

/** Nombre de tuiles vérifiées avec les deux décodeurs avant de faire confiance au canvas. */
const CROSS_CHECKS = 3;

export interface DecoderStatus {
  /** « canvas » tant que le navigateur est fiable, « js » sinon. */
  mode: 'canvas' | 'js';
  checked: number;
}

/**
 * Crée le décodeur de tuiles. Il utilise le canvas du navigateur et contrôle
 * les premières tuiles avec le décodeur JavaScript.
 */
export function createTileDecoder(onFallback?: (reason: string) => void): TileDecoder & { status: DecoderStatus } {
  const status: DecoderStatus = { mode: canvasDecodingAvailable() ? 'canvas' : 'js', checked: 0 };
  const fallback = (reason: string): void => {
    if (status.mode === 'js') return;
    status.mode = 'js';
    onFallback?.(reason);
  };
  const decoder = async (bytes: ArrayBuffer): Promise<Uint8ClampedArray> => {
    if (status.mode === 'js') return decodeWithJs(bytes);
    let fromCanvas: Uint8ClampedArray;
    try {
      fromCanvas = await decodeWithCanvas(bytes);
    } catch (error) {
      fallback(`décodage par le navigateur impossible (${String(error)})`);
      return decodeWithJs(bytes);
    }
    if (status.checked < CROSS_CHECKS) {
      const reference = await decodeWithJs(bytes);
      status.checked++;
      if (!sameData(fromCanvas, reference)) {
        fallback('le navigateur modifie les pixels relus du canvas');
        return reference;
      }
    }
    return fromCanvas;
  };
  return Object.assign(decoder, { status });
}
