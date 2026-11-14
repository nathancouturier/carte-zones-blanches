// Accès aux tuiles de couverture : lecture dans les archives PMTiles, décodage
// et cache LRU des tuiles décodées. Le cache garde les tuiles affichées :
// changer un réglage ne retélécharge rien. L'analyse d'un GPX y prend ce qui s'y
// trouve déjà, mais range ce qu'elle lit à part, dans un petit cache à elle : un
// long tracé n'évince pas les tuiles de la carte, et la carte, cadrée ensuite sur
// un tracé court, y trouve ses tuiles sans les relire.

import { TILE_READ_TIMEOUT_MS } from '../config';
import { untilAborted } from './abort';
import { TILE_SIZE } from './codec';
import { LruCache } from './lru';
import { archiveForTile, type Manifest } from './manifest';
import { lonLatToTilePixel, lonLatToWorldPixel, tileKey } from './tilemath';
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
  /**
   * Dernières tuiles lues pour l'analyse d'un tracé, à part des tuiles affichées (un cinquième
   * de leur nombre) : une tuile que la carte demande ensuite passe de l'un à l'autre sans relecture.
   */
  private readonly analysed: LruCache<string, Cached>;
  /** Lectures en cours qui rempliront le cache. */
  private readonly pending = new Map<string, Promise<DecodedTile>>();
  /** Lectures en cours pour l'analyse d'un tracé, hors du cache des tuiles affichées. */
  private readonly transient = new Map<string, Promise<DecodedTile>>();

  constructor(
    readonly manifest: Manifest,
    private readonly read: ArchiveReader,
    private readonly decode: TileDecoder,
    capacity = 160,
    /** Délai maximal d'une lecture, en millisecondes. */
    private readonly timeoutMs = TILE_READ_TIMEOUT_MS,
  ) {
    this.cache = new LruCache(capacity);
    this.analysed = new LruCache(Math.max(1, Math.round(capacity / 5)));
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

  /** Tuile décodée, depuis le cache (ou celui de l'analyse d'un tracé) ou depuis l'archive. */
  get(z: number, x: number, y: number): Promise<DecodedTile> {
    const key = tileKey(z, x, y);
    const cached = this.cache.get(key) ?? this.fromAnalysis(key);
    if (cached !== undefined) return Promise.resolve(cached === EMPTY ? null : cached);
    let promise = this.pending.get(key);
    if (!promise) {
      // Une lecture de la même tuile pour l'analyse est déjà en route : on l'attend plutôt que de relire.
      const loading: Promise<DecodedTile> = (this.transient.get(key) ?? this.load(z, x, y))
        .then((tile) => {
          this.cache.set(key, tile ?? EMPTY);
          this.analysed.delete(key);
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
   * Tuile décodée pour l'analyse d'un tracé : celle d'un des deux caches si elle y est, sinon
   * lue dans l'archive et rangée dans le cache de l'analyse, jamais dans celui des tuiles
   * affichées : un long tracé n'en évince rien.
   */
  getTransient(z: number, x: number, y: number): Promise<DecodedTile> {
    const key = tileKey(z, x, y);
    const cached = this.cache.get(key) ?? this.analysed.get(key);
    if (cached !== undefined) return Promise.resolve(cached === EMPTY ? null : cached);
    const reading = this.pending.get(key) ?? this.transient.get(key);
    if (reading) return reading;
    const loading = this.load(z, x, y)
      .then((tile) => {
        this.analysed.set(key, tile ?? EMPTY);
        return tile;
      })
      .finally(() => {
        if (this.transient.get(key) === loading) this.transient.delete(key);
      });
    this.transient.set(key, loading);
    return loading;
  }

  /** Tuile lue pour l'analyse d'un tracé, que la carte affiche maintenant : elle passe dans le cache des tuiles affichées. */
  private fromAnalysis(key: string): Cached | undefined {
    const tile = this.analysed.get(key);
    if (tile !== undefined) {
      this.analysed.delete(key);
      this.cache.set(key, tile);
    }
    return tile;
  }

  /**
   * Oublie les lectures en cours : les prochaines demandes relisent l'archive au
   * lieu d'attendre une requête restée en suspens (« Réessayer » après une panne).
   */
  restart(): void {
    this.pending.clear();
    this.transient.clear();
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

  /**
   * Valeurs du canal B (pays et type de source) de tous les pixels de données d'une
   * emprise (ouest, sud, est, nord), lues au zoom donné dans les tuiles qui la couvrent :
   * tout ce que la carte affiche, même un petit pays (Monaco) entre deux points de la vue.
   * Au-delà de maxTiles tuiles (très grand écran), la lecture se fait au zoom inférieur.
   * Une tuile illisible est ignorée : rien n'y est affiché.
   */
  async metaInBounds(bounds: readonly [number, number, number, number], zoom: number, maxTiles = 64): Promise<number[]> {
    const { minzoom } = this.manifest.tiles;
    let z = Math.max(minzoom, Math.min(this.maxZoom, Math.round(zoom)));
    let area = pixelArea(bounds, z);
    while (z > minzoom && tileCount(area) > maxTiles) area = pixelArea(bounds, --z);
    const seen = new Uint8Array(256);
    const reads: Promise<void>[] = [];
    for (let ty = Math.floor(area.top / TILE_SIZE); ty <= Math.floor(area.bottom / TILE_SIZE); ty++) {
      for (let tx = Math.floor(area.left / TILE_SIZE); tx <= Math.floor(area.right / TILE_SIZE); tx++) {
        const read = this.get(z, tx, ty).then((tile) => {
          if (!tile) return;
          // Partie de la tuile à l'intérieur de l'emprise.
          const x0 = Math.max(0, area.left - tx * TILE_SIZE);
          const x1 = Math.min(TILE_SIZE - 1, area.right - tx * TILE_SIZE);
          const y0 = Math.max(0, area.top - ty * TILE_SIZE);
          const y1 = Math.min(TILE_SIZE - 1, area.bottom - ty * TILE_SIZE);
          for (let py = y0; py <= y1; py++) {
            for (let o = (py * TILE_SIZE + x0) * 4, end = (py * TILE_SIZE + x1) * 4; o <= end; o += 4) {
              if (tile[o + 3] !== 0) seen[tile[o + 2]] = 1;
            }
          }
        });
        reads.push(read.catch(() => undefined));
      }
    }
    await Promise.all(reads);
    return Array.from(seen.keys()).filter((meta) => seen[meta] === 1);
  }

  clear(): void {
    this.cache.clear();
    this.analysed.clear();
  }
}

function key3(z: number, x: number, y: number): string {
  return `${z}/${x}/${y}`;
}

/** Pixels « monde » d'une emprise au zoom z : premières et dernières colonnes et lignes, incluses. */
interface PixelArea {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

function pixelArea([west, south, east, north]: readonly [number, number, number, number], z: number): PixelArea {
  const size = 2 ** z * TILE_SIZE;
  const clamp = (v: number): number => Math.min(size - 1, Math.max(0, Math.floor(v)));
  const nw = lonLatToWorldPixel(west, north, z);
  const se = lonLatToWorldPixel(east, south, z);
  return { left: clamp(nw.x), top: clamp(nw.y), right: clamp(se.x), bottom: clamp(se.y) };
}

function tileCount(area: PixelArea): number {
  const columns = Math.floor(area.right / TILE_SIZE) - Math.floor(area.left / TILE_SIZE) + 1;
  const rows = Math.floor(area.bottom / TILE_SIZE) - Math.floor(area.top / TILE_SIZE) + 1;
  return columns * rows;
}
