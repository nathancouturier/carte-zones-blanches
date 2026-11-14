// Protocole MapLibre « couverture:// » : fournit à la carte les tuiles de
// couverture recolorées selon les réglages de l'interface.
//
// MapLibre demande couverture://z/x/y. On lit la tuile de données (cache LRU,
// puis archive PMTiles), on la recolore et on renvoie une image. Quand un
// réglage change, la carte redemande ses tuiles (refreshTiles) : elles sont
// redessinées à partir du cache, sans téléchargement.

import { addProtocol, type GetResourceResponse, type RequestParameters } from 'maplibre-gl';
import { untilAborted } from './abort';
import { TILE_SIZE } from './codec';
import type { LevelTables } from './manifest';
import { renderTile, renderUnavailable, type RenderSettings } from './render';
import type { TileStore } from './store';

export const COVERAGE_PROTOCOL = 'couverture';

export interface CoverageRenderState {
  store: TileStore;
  tables: LevelTables;
  settings: RenderSettings;
}

type TileLoader = (params: Pick<RequestParameters, 'url'>, abortController: AbortController) => Promise<GetResourceResponse<ImageBitmap>>;

const URL_RE = new RegExp(`^${COVERAGE_PROTOCOL}://(\\d+)/(\\d+)/(\\d+)`);

async function transparentTile(): Promise<ImageBitmap> {
  return createImageBitmap(new ImageData(1, 1));
}

async function unavailableTile(): Promise<ImageBitmap> {
  const image = new ImageData(TILE_SIZE, TILE_SIZE);
  renderUnavailable(image.data);
  return createImageBitmap(image);
}

/**
 * Fonction qui répond aux demandes de tuiles de MapLibre. « getState » donne
 * l'état courant au moment de chaque requête ; « onError » est appelé quand une
 * tuile n'a pas pu être lue.
 */
export function coverageTileLoader(getState: () => CoverageRenderState | null, onError?: (error: unknown) => void): TileLoader {
  return async (params, abortController) => {
    const match = URL_RE.exec(params.url);
    const state = getState();
    if (!match || !state) return { data: await transparentTile() };
    const [z, x, y] = [Number(match[1]), Number(match[2]), Number(match[3])];
    let data;
    try {
      // Tuile annulée (sortie de la vue) : on rend la main tout de suite, sans attendre la lecture,
      // qui continue et remplira le cache. Sinon une lecture qui cale garderait sa place dans la
      // file d'images de MapLibre, partagée avec les fonds raster, et bloquerait leur affichage.
      data = await untilAborted(state.store.get(z, x, y), abortController.signal);
    } catch (error) {
      if (abortController.signal.aborted) throw error;
      // Une tuile vide passerait pour une zone bien couverte : on montre que les données manquent.
      onError?.(error);
      return { data: await unavailableTile() };
    }
    if (!data) return { data: await transparentTile() };
    // L'état a pu changer pendant le téléchargement : on dessine avec le plus récent.
    const current = getState() ?? state;
    const image = new ImageData(TILE_SIZE, TILE_SIZE);
    const visible = renderTile(data, current.tables, current.settings, image.data);
    if (!visible) return { data: await transparentTile() };
    return { data: await createImageBitmap(image) };
  };
}

/** Enregistre le protocole auprès de MapLibre. */
export function registerCoverageProtocol(getState: () => CoverageRenderState | null, onError?: (error: unknown) => void): void {
  addProtocol(COVERAGE_PROTOCOL, coverageTileLoader(getState, onError));
}
