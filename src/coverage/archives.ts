// Lecture des tuiles dans les archives PMTiles publiées avec le site.

import type { PMTiles } from 'pmtiles';
import { isAbortError, untilAborted } from './abort';
import type { ArchiveReader } from './store';

export interface OnlineArchiveReader extends ArchiveReader {
  /** Oublie toutes les instances : les lectures suivantes repartent d'instances neuves. */
  reset(): void;
}

/**
 * Lecteur des archives : une instance PMTiles par fichier, créée à la première
 * lecture. « open » fabrique l'instance d'un fichier.
 *
 * pmtiles garde en cache la promesse de l'en-tête et des répertoires, même
 * rejetée ou restée sans réponse : après une coupure, l'instance resterait
 * inutilisable jusqu'au rechargement de la page. Sur toute erreur autre qu'une
 * annulation (délai dépassé compris), on l'oublie donc, et la lecture suivante
 * repart d'une instance neuve.
 */
export function createArchiveReader(open: (file: string) => PMTiles): OnlineArchiveReader {
  const archives = new Map<string, PMTiles>();
  const read: ArchiveReader = async (file, z, x, y, signal) => {
    let archive = archives.get(file);
    if (!archive) {
      archive = open(file);
      archives.set(file, archive);
    }
    try {
      // pmtiles ne transmet pas le signal à la lecture de l'en-tête : on n'attend pas au-delà du signal.
      return (await untilAborted(archive.getZxy(z, x, y, signal), signal))?.data;
    } catch (error) {
      // Une autre lecture a pu remplacer l'instance entre-temps : on ne retire que la nôtre.
      if (!isAbortError(error) && archives.get(file) === archive) archives.delete(file);
      throw error;
    }
  };
  return Object.assign(read, { reset: () => archives.clear() });
}
