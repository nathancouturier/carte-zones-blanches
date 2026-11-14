// Lecture des tuiles dans les archives PMTiles publiées avec le site.

import type { PMTiles } from 'pmtiles';
import type { ArchiveReader } from './store';

/** Vrai pour une requête annulée par celui qui l'a lancée (ce n'est pas une panne). */
export function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === 'AbortError';
}

/**
 * Lecteur des archives : une instance PMTiles par fichier, créée à la première
 * lecture. « open » fabrique l'instance d'un fichier.
 *
 * pmtiles garde en cache la promesse de l'en-tête et des répertoires, même
 * rejetée : après une coupure, l'instance resterait inutilisable jusqu'au
 * rechargement de la page. Sur toute erreur autre qu'une annulation, on l'oublie
 * donc, et la lecture suivante repart d'une instance neuve.
 */
export function createArchiveReader(open: (file: string) => PMTiles): ArchiveReader {
  const archives = new Map<string, PMTiles>();
  return async (file, z, x, y) => {
    let archive = archives.get(file);
    if (!archive) {
      archive = open(file);
      archives.set(file, archive);
    }
    try {
      return (await archive.getZxy(z, x, y))?.data;
    } catch (error) {
      // Une autre lecture a pu remplacer l'instance entre-temps : on ne retire que la nôtre.
      if (!isAbortError(error) && archives.get(file) === archive) archives.delete(file);
      throw error;
    }
  };
}
