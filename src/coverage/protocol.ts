// Protocole MapLibre « couverture:// » : fournit à la carte les tuiles de
// couverture recolorées selon les réglages de l'interface.
//
// MapLibre demande couverture://z/x/y?v=N. On lit la tuile de données (cache
// LRU, puis archive PMTiles), on la recolore et on renvoie une image. Quand un
// réglage change, il suffit de changer N : toutes les tuiles sont redessinées
// à partir du cache, sans téléchargement.

import { addProtocol, type GetResourceResponse, type RequestParameters } from 'maplibre-gl';
import { TILE_SIZE } from './codec';
import type { LevelTables } from './manifest';
import { renderTile, type RenderSettings } from './render';
import type { TileStore } from './store';

export const COVERAGE_PROTOCOL = 'couverture';

export interface CoverageRenderState {
  store: TileStore;
  tables: LevelTables;
  settings: RenderSettings;
}

const URL_RE = new RegExp(`^${COVERAGE_PROTOCOL}://(\\d+)/(\\d+)/(\\d+)`);

function abortError(): Error {
  const error = new Error('Requête annulée');
  error.name = 'AbortError';
  return error;
}

async function transparentTile(): Promise<ImageBitmap> {
  return createImageBitmap(new ImageData(1, 1));
}

/** Enregistre le protocole. « getState » donne l'état courant au moment de chaque requête. */
export function registerCoverageProtocol(getState: () => CoverageRenderState | null): void {
  addProtocol(
    COVERAGE_PROTOCOL,
    async (params: RequestParameters, abortController: AbortController): Promise<GetResourceResponse<ImageBitmap>> => {
      const match = URL_RE.exec(params.url);
      const state = getState();
      if (!match || !state) return { data: await transparentTile() };
      const [z, x, y] = [Number(match[1]), Number(match[2]), Number(match[3])];
      const data = await state.store.get(z, x, y);
      if (abortController.signal.aborted) throw abortError();
      if (!data) return { data: await transparentTile() };
      // L'état a pu changer pendant le téléchargement : on dessine avec le plus récent.
      const current = getState() ?? state;
      const image = new ImageData(TILE_SIZE, TILE_SIZE);
      const visible = renderTile(data, current.tables, current.settings, image.data);
      if (!visible) return { data: await transparentTile() };
      return { data: await createImageBitmap(image) };
    },
  );
}

export function coverageTileUrl(version: number): string {
  return `${COVERAGE_PROTOCOL}://{z}/{x}/{y}?v=${version}`;
}
