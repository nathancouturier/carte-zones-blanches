// État de l'application et réglages mémorisés.

import type { Manifest, ServiceId } from './coverage/manifest';
import type { ParsedGpx } from './gpx/parse';
import type { Report, TrackAnalysis } from './gpx/report';
import type { Sample } from './gpx/resample';
import { DEFAULT_BASEMAP, isBasemapChoice, type BasemapChoice, type BasemapId } from './map/basemaps';
import { offlineInfo, type OfflineInfo } from './offline/manager';

export type PanelId = 'network' | 'basemap' | 'gpx' | 'report' | 'settings' | 'sources';

export interface NetworkSettings {
  service: ServiceId;
  /** Opérateur choisi par pays (code ISO). Absent : tous les opérateurs du pays. */
  operators: Record<string, string>;
  showAll: boolean;
  opacity: number;
}

export interface BasemapSettings {
  choice: BasemapChoice;
  hillshade: boolean;
}

export interface LoadedTrack {
  fileName: string;
  /** Texte du fichier d'origine, gardé pour l'export enrichi. Il ne quitte pas le navigateur. */
  xml: string;
  parsed: ParsedGpx;
  samples: Sample[];
  length: number;
  /** Résultat de la lecture des tuiles, null tant qu'elle n'est pas faite. */
  analysis: TrackAnalysis | null;
  /** Rapport pour les réglages courants. */
  report: Report | null;
}

export type TrackStatus = 'idle' | 'reading' | 'analyzing' | 'ready' | 'error';

export interface OfflineState {
  status: 'idle' | 'preparing' | 'error';
  /** Avancement de l'enregistrement, de 0 à 1. */
  progress: number;
  /** Tracé déjà préparé pour le hors ligne, s'il y en a un. */
  info: OfflineInfo | null;
}

export interface AppState {
  panel: PanelId | null;
  network: NetworkSettings;
  basemap: BasemapSettings;
  /** Fond réellement affiché (le mode Auto est résolu). */
  activeBasemap: BasemapId;
  manifest: Manifest | null;
  dataStatus: 'loading' | 'ready' | 'missing';
  track: LoadedTrack | null;
  trackStatus: TrackStatus;
  /** Avancement de l'analyse, de 0 à 1. */
  progress: number;
  /** Clé de traduction du dernier message d'erreur du GPX. */
  trackError: { key: string; params?: Record<string, string | number> } | null;
  /** Numéro de la zone blanche sélectionnée dans le rapport. */
  selectedZone: number | null;
  /** Codes ISO des pays dont des données sont visibles à l'écran. */
  visibleCountries: string[];
  /** Tuiles de couverture qui n'ont pas pu être lues depuis le dernier essai (affichées hachurées en gris). */
  coverageErrors: number;
  offline: OfflineState;
}

const NETWORK_KEY = 'czb.reseau';
const BASEMAP_KEY = 'czb.fond';

function readJson(key: string): unknown {
  try {
    const raw = globalThis.localStorage?.getItem(key);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null; // stockage bloqué ou contenu illisible
  }
}

function writeJson(key: string, value: unknown): void {
  try {
    globalThis.localStorage?.setItem(key, JSON.stringify(value));
  } catch {
    // tant pis : le réglage ne sera pas mémorisé
  }
}

export function defaultNetwork(): NetworkSettings {
  return { service: 'data', operators: {}, showAll: false, opacity: 0.65 };
}

export function loadNetworkSettings(): NetworkSettings {
  const base = defaultNetwork();
  const stored = readJson(NETWORK_KEY);
  if (typeof stored !== 'object' || stored === null) return base;
  const s = stored as Record<string, unknown>;
  if (s.service === 'data' || s.service === 'voice') base.service = s.service;
  if (typeof s.showAll === 'boolean') base.showAll = s.showAll;
  if (typeof s.opacity === 'number' && s.opacity >= 0.1 && s.opacity <= 1) base.opacity = s.opacity;
  if (typeof s.operators === 'object' && s.operators !== null) {
    for (const [iso, id] of Object.entries(s.operators as Record<string, unknown>)) {
      if (/^[A-Z]{2}$/.test(iso) && typeof id === 'string') base.operators[iso] = id;
    }
  }
  return base;
}

export function saveNetworkSettings(settings: NetworkSettings): void {
  writeJson(NETWORK_KEY, settings);
}

export function loadBasemapSettings(): BasemapSettings {
  const base: BasemapSettings = { choice: 'auto', hillshade: false };
  const stored = readJson(BASEMAP_KEY);
  if (typeof stored !== 'object' || stored === null) return base;
  const s = stored as Record<string, unknown>;
  if (isBasemapChoice(s.choice)) base.choice = s.choice;
  if (typeof s.hillshade === 'boolean') base.hillshade = s.hillshade;
  return base;
}

export function saveBasemapSettings(settings: BasemapSettings): void {
  writeJson(BASEMAP_KEY, settings);
}

export function initialState(): AppState {
  const basemap = loadBasemapSettings();
  return {
    panel: null,
    network: loadNetworkSettings(),
    basemap,
    activeBasemap: basemap.choice === 'auto' ? DEFAULT_BASEMAP : basemap.choice,
    manifest: null,
    dataStatus: 'loading',
    track: null,
    trackStatus: 'idle',
    progress: 0,
    trackError: null,
    selectedZone: null,
    visibleCountries: [],
    coverageErrors: 0,
    offline: { status: 'idle', progress: 0, info: offlineInfo() },
  };
}

type Listener = (state: AppState, previous: AppState) => void;

/** Magasin d'état minimal : un objet, des abonnés. */
export class Store {
  private state: AppState;
  private readonly listeners = new Set<Listener>();

  constructor(state: AppState) {
    this.state = state;
  }

  get(): AppState {
    return this.state;
  }

  set(patch: Partial<AppState>): void {
    const previous = this.state;
    this.state = { ...previous, ...patch };
    for (const listener of this.listeners) listener(this.state, previous);
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
}
