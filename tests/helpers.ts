// Outils communs aux tests.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { DOMParser, XMLSerializer } from '@xmldom/xmldom';
import { PMTiles, type RangeResponse, type Source } from 'pmtiles';
import { decodeWithJs } from '../src/coverage/decode';
import { parseManifest, type Manifest } from '../src/coverage/manifest';
import { TileStore, type ArchiveReader } from '../src/coverage/store';
import type { XmlTools } from '../src/gpx/export';
import type { XmlParser } from '../src/gpx/parse';

export function fixturePath(name: string): string {
  return fileURLToPath(new URL(`./fixtures/${name}`, import.meta.url));
}

export function readFixture(name: string): Buffer {
  return readFileSync(fixturePath(name));
}

export function readJsonFixture<T>(name: string): T {
  return JSON.parse(readFixture(name).toString('utf-8')) as T;
}

/** Analyseur XML pour Node (le navigateur fournit DOMParser). */
export const xmlParser: XmlParser = {
  parseFromString: (text) => new DOMParser().parseFromString(text, 'text/xml') as unknown as Document,
};

export const xmlTools: XmlTools = {
  parse: (text) => new DOMParser().parseFromString(text, 'text/xml') as unknown as Document,
  serialize: (doc) => new XMLSerializer().serializeToString(doc as never),
};

/** Source PMTiles lue dans un tampon en mémoire. */
class BufferSource implements Source {
  constructor(
    private readonly key: string,
    private readonly buffer: Buffer,
  ) {}

  getKey(): string {
    return this.key;
  }

  async getBytes(offset: number, length: number): Promise<RangeResponse> {
    const slice = this.buffer.subarray(offset, offset + length);
    return { data: slice.buffer.slice(slice.byteOffset, slice.byteOffset + slice.byteLength) as ArrayBuffer };
  }
}

/** Magasin de tuiles branché sur les archives d'un dossier de fixtures. */
export function fixtureStore(dir: string): { store: TileStore; manifest: Manifest; reads: string[] } {
  const manifest = parseManifest(readJsonFixture(`${dir}/manifest.json`));
  const archives = new Map<string, PMTiles>();
  const reads: string[] = [];
  const read: ArchiveReader = async (file, z, x, y) => {
    reads.push(`${file}:${z}/${x}/${y}`);
    let archive = archives.get(file);
    if (!archive) {
      archive = new PMTiles(new BufferSource(file, readFixture(`${dir}/${file}`)));
      archives.set(file, archive);
    }
    return (await archive.getZxy(z, x, y))?.data;
  };
  return { store: new TileStore(manifest, read, decodeWithJs), manifest, reads };
}

/** Manifest minimal à deux pays, pour tester le décodeur sans fichier. */
export function sampleManifest(): Manifest {
  return parseManifest({
    version: 1,
    generated: '2026-11-13',
    tiles: { size: 256, minzoom: 0, maxzoom: 12, format: 'png' },
    bounds: [-5.2, 41.3, 10.5, 51.1],
    archives: [{ file: 'a.pmtiles', minzoom: 0, maxzoom: 12 }],
    countries: [
      {
        code: 1,
        iso: 'FR',
        euRoaming: true,
        slots: [
          { id: 'orange', name: 'Orange' },
          { id: 'sfr', name: 'SFR' },
          { id: 'bouygues', name: 'Bouygues Telecom' },
          { id: 'free', name: 'Free' },
        ],
        sources: [
          {
            type: 0,
            id: 'fr_arcep',
            name: 'Arcep',
            date: '2026-T2',
            licence: 'Licence Ouverte',
            attribution: 'Arcep',
            services: ['data'],
            levels: 'four',
            perOperator: true,
          },
        ],
      },
      {
        code: 2,
        iso: 'CH',
        euRoaming: false,
        slots: [],
        sources: [
          {
            type: 1,
            id: 'ch_bakom',
            name: 'OFCOM',
            date: '2026-03',
            licence: 'Open data',
            attribution: 'OFCOM',
            services: ['data', 'voice'],
            levels: 'binary',
            levelMap: [0, 2, 2, 2],
            perOperator: false,
          },
        ],
      },
      {
        code: 5,
        iso: 'AD',
        euRoaming: false,
        slots: [{ id: 'andorra-telecom', name: 'Andorra Telecom' }],
        sources: [
          {
            type: 2,
            id: 'estimation_opencellid',
            name: 'Estimation',
            date: '2026-11',
            licence: 'CC BY-SA 4.0',
            attribution: 'OpenCelliD',
            services: ['data'],
            levels: 'binary',
            levelMap: [0, 1, 2, 2],
            perOperator: true,
          },
        ],
      },
    ],
  });
}
