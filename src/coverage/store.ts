// Accès aux tuiles de couverture : lecture dans les archives PMTiles, décodage
// et cache LRU des tuiles décodées. Le même cache sert à l'affichage et à
// l'analyse des GPX : changer un réglage ne retélécharge rien.

import { TILE_READ_TIMEOUT_MS } from '../config';
import { untilAborted } from './abort';
import { TILE_SIZE } from './codec';
import { LruCache } from './lru';
import { archiveForTile, type Manifest } from './manifest';
import { lonLatToTilePixel, tileKey } from './tilemath';
import type { TileDecoder } from './decode';

/**
 * Lit les octets d'une tuile dans une archive. Renvoie undefined si la tuile
 * n'existe pas. « signal » est déclenché quand la lecture n'est plus attendue.
 */
export type ArchiveReader = (file: string, z: number, x: number, y: number, signal?: AbortSignal) => Promise<ArrayBuffer | undefined>;

/** Tuile décodée (RGBA, 256 x 256), ou null s'il n'y a pas de données à cet endroit. */
export type DecodedTile = Uint8ClampedArray | null;

/** Valeurs brutes d'un pixel : R, G, B, A. */
export type RawPixel = [number, number, number, number];

const EMPTY = Symbol('tuile vide');
type Cached = Uint8ClampedArray | typeof EMPTY;

export class TileStore {
  private readonly cache: LruCache<string, Cached>;
  private readonly pending = new Map<string, Promise<DecodedTile>>();

  constructor(
    readonly manifest: Manifest,
    private readonly read: ArchiveReader,
    private readonly decode: TileDecoder,
    capacity = 160,
    /** Délai maximal d'une lecture, en millisecondes. */
    private readonly timeoutMs = TILE_READ_TIMEOUT_MS,
  ) {
    this.cache = new LruCache(capacity);
  }

  get maxZoom(): number {
    return this.manifest.tiles.maxzoom;
  }

  /** Tuile déjà en cache, sans rien télécharger. undefined si elle n'y est pas. */
  peek(z: number, x: number, y: number): DecodedTile | undefined {
    const cached = this.cache.get(tileKey(z, x, y));
    if (cached === undefined) return undefined;
    return cached === EMPTY ? null : cached;
  }

  /** Tuile décodée, depuis le cache ou depuis l'archive. */
  get(z: number, x: number, y: number): Promise<DecodedTile> {
    const key = tileKey(z, x, y);
    const cached = this.cache.get(key);
    if (cached !== undefined) return Promise.resolve(cached === EMPTY ? null : cached);
    let promise = this.pending.get(key);
    if (!promise) {
      const loading: Promise<DecodedTile> = this.load(z, x, y)
        .then((tile) => {
          this.cache.set(key, tile ?? EMPTY);
          return tile;
        })
        .finally(() => {
          // Après restart(), une lecture plus récente de la même tuile a pu prendre la place.
          if (this.pending.get(key) === loading) this.pending.delete(key);
        });
      promise = loading;
      this.pending.set(key, promise);
    }
    return promise;
  }

  /**
   * Oublie les lectures en cours : les prochaines demandes relisent l'archive au
   * lieu d'attendre une requête restée en suspens (« Réessayer » après une panne).
   */
  restart(): void {
    this.pending.clear();
  }

  private async load(z: number, x: number, y: number): Promise<DecodedTile> {
    const { minzoom, maxzoom } = this.manifest.tiles;
    const n = 2 ** z;
    if (z < minzoom || z > maxzoom || x < 0 || y < 0 || x >= n || y >= n) return null;
    const archive = archiveForTile(this.manifest, z, x, y);
    if (!archive) return null;
    // Une lecture qui cale échoue au bout du délai, même si le lecteur ignore le signal :
    // elle quitte alors « pending », et une nouvelle demande relit vraiment.
    const signal = AbortSignal.timeout(this.timeoutMs);
    const bytes = await untilAborted(this.read(archive.file, z, x, y, signal), signal);
    if (!bytes || bytes.byteLength === 0) return null;
    const data = await this.decode(bytes);
    if (data.length !== TILE_SIZE * TILE_SIZE * 4) throw new Error(`Tuile ${key3(z, x, y)} : taille inattendue`);
    return data;
  }

  /** Valeurs brutes du pixel qui contient un point (au zoom maximal par défaut). null hors des données. */
  async sample(lon: number, lat: number, zoom: number = this.maxZoom): Promise<RawPixel | null> {
    const tp = lonLatToTilePixel(lon, lat, zoom);
    if (!tp) return null;
    const tile = await this.get(tp.z, tp.x, tp.y);
    if (!tile) return null;
    const o = (tp.py * TILE_SIZE + tp.px) * 4;
    return [tile[o], tile[o + 1], tile[o + 2], tile[o + 3]];
  }

  clear(): void {
    this.cache.clear();
  }
}

function key3(z: number, x: number, y: number): string {
  return `${z}/${x}/${y}`;
}
