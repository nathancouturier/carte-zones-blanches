// Chef d'orchestre : relie l'état, la carte, les données et l'interface.

import { PMTiles } from 'pmtiles';
import { DATA_BASE_URL, MAX_GPX_BYTES, TILE_READ_TIMEOUT_MS } from './config';
import { createArchiveReader, type OnlineArchiveReader } from './coverage/archives';
import { unpackCountry } from './coverage/codec';
import { createTileDecoder } from './coverage/decode';
import {
  ALL_OPERATORS,
  buildLevelTables,
  countryByCode,
  countryHasOperatorChoice,
  manifestHasService,
  parseManifest,
  selectableSlots,
  type DecodeSettings,
  type LevelTables,
  type Manifest,
  type ServiceId,
} from './coverage/manifest';
import { registerCoverageProtocol, type CoverageRenderState } from './coverage/protocol';
import { archiveForTile } from './coverage/manifest';
import { TileStore, type ArchiveReader } from './coverage/store';
import { sampleCoverage } from './gpx/analyze';
import { enrichedFileName, enrichGpx } from './gpx/export';
import { decodeGpx, GpxError, parseGpx } from './gpx/parse';
import { analyzeTrack, buildReport, reportText, zoneWaypoints } from './gpx/report';
import { resample } from './gpx/resample';
import { getLanguage, setLanguage, t } from './i18n';
import { autoBasemap, basemapPack, BASEMAPS, type BasemapChoice, type BasemapId } from './map/basemaps';
import { clearOffline, offlineSupported, prepareOffline, storedCoverageTile, storedTrack } from './offline/manager';
import { MapView, type Padding } from './map/mapView';
import { samplesBounds, trackToGeoJson, zoneToGeoJson, EMPTY_COLLECTION } from './map/trackGeojson';
import {
  saveBasemapSettings,
  saveNetworkSettings,
  Store,
  type AppState,
  type LoadedTrack,
  type NetworkSettings,
  type PanelId,
} from './state';

export interface AppHooks {
  /** Affiche un message bref. */
  toast: (message: string) => void;
  /** Marges à laisser libres autour d'un cadrage (panneau ouvert, barres). */
  padding: () => Padding;
}

export class App {
  readonly mapView: MapView;
  private tileStore: TileStore | null = null;
  private tables: LevelTables = [];
  private renderState: CoverageRenderState | null = null;
  private importSeq = 0;
  private readArchive: OnlineArchiveReader | null = null;
  private offlineAbort: AbortController | null = null;
  private moveTimer: ReturnType<typeof setTimeout> | undefined;
  private hooks: AppHooks = { toast: () => undefined, padding: () => ({ top: 40, right: 40, bottom: 40, left: 40 }) };

  constructor(
    readonly store: Store,
    mapContainer: HTMLElement,
  ) {
    registerCoverageProtocol(() => this.renderState);
    this.mapView = new MapView({
      container: mapContainer,
      labels: () => ({
        'NavigationControl.ZoomIn': t('action.zoomIn'),
        'NavigationControl.ZoomOut': t('action.zoomOut'),
        'GeolocateControl.FindMyLocation': t('action.locate'),
        'GeolocateControl.LocationNotAvailable': t('locate.error'),
      }),
      onMoveEnd: () => this.scheduleViewUpdate(),
      onLocateError: () => this.hooks.toast(t('locate.error')),
      onStyleFallback: () => this.hooks.toast(t('basemap.fallback')),
    });
  }

  setHooks(hooks: AppHooks): void {
    this.hooks = hooks;
  }

  get state(): AppState {
    return this.store.get();
  }

  // -- démarrage ------------------------------------------------------------

  async start(): Promise<void> {
    void this.applyStyle();
    await this.loadManifest();
  }

  private async loadManifest(): Promise<void> {
    let manifest: Manifest;
    try {
      const response = await fetch(`${DATA_BASE_URL}manifest.json`, { cache: 'no-cache' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      manifest = parseManifest(await response.json());
    } catch (error) {
      console.warn('Données de couverture indisponibles :', error);
      this.store.set({ dataStatus: 'missing' });
      return;
    }
    const online = createArchiveReader((file) => new PMTiles(`${DATA_BASE_URL}${file}`));
    // Sans réseau, on sert les tuiles enregistrées par « Préparer le hors ligne ».
    const read: ArchiveReader = async (file, z, x, y, signal) => {
      if (typeof navigator !== 'undefined' && navigator.onLine === false) {
        const stored = await storedCoverageTile(import.meta.env.BASE_URL, z, x, y);
        if (stored !== undefined) return stored ?? undefined;
      }
      try {
        return await online(file, z, x, y, signal);
      } catch (error) {
        const stored = await storedCoverageTile(import.meta.env.BASE_URL, z, x, y);
        if (stored === undefined) throw error;
        return stored ?? undefined;
      }
    };
    this.readArchive = online;
    const decoder = createTileDecoder((reason) => console.warn(`Décodage des tuiles en JavaScript : ${reason}`));
    this.tileStore = new TileStore(manifest, read, decoder);
    const network = this.sanitizeNetwork(this.state.network, manifest);
    this.store.set({ manifest, dataStatus: 'ready', network });
    this.rebuildTables();
    await this.applyStyle();
    this.scheduleViewUpdate();
    // Sans réseau, on recharge tout seul le tracé préparé pour le hors ligne.
    if (typeof navigator !== 'undefined' && navigator.onLine === false && !this.state.track) void this.restoreOfflineTrack();
  }

  /** Écarte les réglages mémorisés qui ne correspondent plus aux données. */
  private sanitizeNetwork(network: NetworkSettings, manifest: Manifest): NetworkSettings {
    const operators: Record<string, string> = {};
    for (const country of manifest.countries) {
      const id = network.operators[country.iso];
      if (id && countryHasOperatorChoice(country) && selectableSlots(country).some((s) => s.id === id)) operators[country.iso] = id;
    }
    const service: ServiceId = manifestHasService(manifest, network.service) ? network.service : 'data';
    return { ...network, operators, service };
  }

  private decodeSettings(): DecodeSettings {
    const { service, operators } = this.state.network;
    return { service, operators };
  }

  private rebuildTables(): void {
    const { manifest, network } = this.state;
    if (!manifest || !this.tileStore) {
      this.renderState = null;
      return;
    }
    this.tables = buildLevelTables(manifest, this.decodeSettings());
    this.renderState = {
      store: this.tileStore,
      tables: this.tables,
      settings: { service: network.service, showAll: network.showAll },
    };
  }

  private async applyStyle(): Promise<void> {
    const { manifest, network, basemap, activeBasemap } = this.state;
    await this.mapView.setStyleInputs({
      basemap: activeBasemap,
      hillshade: basemap.hillshade,
      coverage: manifest
        ? { minzoom: manifest.tiles.minzoom, maxzoom: manifest.tiles.maxzoom, bounds: manifest.bounds, opacity: network.opacity }
        : null,
    });
  }

  // -- panneaux -------------------------------------------------------------

  openPanel(panel: PanelId): void {
    this.store.set({ panel: this.state.panel === panel ? null : panel });
  }

  closePanel(): void {
    this.store.set({ panel: null });
  }

  // -- réseau ---------------------------------------------------------------

  private updateNetwork(patch: Partial<NetworkSettings>, redraw: boolean): void {
    const network = { ...this.state.network, ...patch };
    saveNetworkSettings(network);
    this.store.set({ network });
    if (!redraw) return;
    this.rebuildTables();
    this.mapView.refreshCoverage();
    this.refreshReport();
  }

  setService(service: ServiceId): void {
    this.updateNetwork({ service }, true);
  }

  setOperator(iso: string, operator: string): void {
    const operators = { ...this.state.network.operators };
    if (operator === ALL_OPERATORS) delete operators[iso];
    else operators[iso] = operator;
    this.updateNetwork({ operators }, true);
  }

  setShowAll(showAll: boolean): void {
    this.updateNetwork({ showAll }, true);
  }

  /** Opacité de la couche réseau. « commit » à false pendant le glissement du curseur. */
  setOpacity(opacity: number, commit: boolean): void {
    this.mapView.setCoverageOpacity(opacity);
    if (commit) this.updateNetwork({ opacity }, false);
  }

  // -- fond -----------------------------------------------------------------

  setBasemapChoice(choice: BasemapChoice): void {
    const basemap = { ...this.state.basemap, choice };
    saveBasemapSettings(basemap);
    const active: BasemapId = choice === 'auto' ? this.state.activeBasemap : choice;
    this.store.set({ basemap, activeBasemap: active });
    void this.applyStyle();
    if (choice === 'auto') this.scheduleViewUpdate();
  }

  setHillshade(hillshade: boolean): void {
    const basemap = { ...this.state.basemap, hillshade };
    saveBasemapSettings(basemap);
    this.store.set({ basemap });
    void this.applyStyle();
  }

  // -- vue : pays au centre et pays visibles ---------------------------------

  private scheduleViewUpdate(): void {
    clearTimeout(this.moveTimer);
    this.moveTimer = setTimeout(() => void this.updateView(), 200);
  }

  private async updateView(): Promise<void> {
    const { manifest } = this.state;
    const store = this.tileStore;
    if (!manifest || !store) return;
    const zoom = this.mapView.dataZoom(manifest.tiles.minzoom, manifest.tiles.maxzoom);
    const points = this.mapView.viewSamplePoints();
    let pixels: (Awaited<ReturnType<TileStore['sample']>> | null)[];
    try {
      pixels = await Promise.all(points.map((p) => store.sample(p.lon, p.lat, zoom).catch(() => null)));
    } catch {
      return;
    }
    const isoAt = (pixel: (typeof pixels)[number]): string | null => {
      if (!pixel || pixel[3] === 0) return null;
      return countryByCode(manifest, unpackCountry(pixel[2]))?.iso ?? null;
    };
    const visible = [...new Set(pixels.map(isoAt).filter((iso): iso is string => iso !== null))];
    const patch: Partial<AppState> = {};
    const current = this.state;
    if (visible.join() !== current.visibleCountries.join()) patch.visibleCountries = visible;
    // Mode Auto : le fond national du pays au centre de la carte.
    if (current.basemap.choice === 'auto') {
      const wanted = autoBasemap(isoAt(pixels[0]));
      if (wanted && wanted !== current.activeBasemap) patch.activeBasemap = wanted;
    }
    if (Object.keys(patch).length === 0) return;
    this.store.set(patch);
    if (patch.activeBasemap) void this.applyStyle();
  }

  // -- GPX ------------------------------------------------------------------

  async importGpx(file: File): Promise<void> {
    const seq = ++this.importSeq;
    const fail = (key: string, params?: Record<string, string | number>): void => {
      if (seq !== this.importSeq) return;
      this.store.set({ trackStatus: this.state.track ? 'ready' : 'error', trackError: { key, params }, panel: 'gpx' });
    };
    if (file.size > MAX_GPX_BYTES) {
      fail('gpx.error.tooBig', { size: Math.ceil(file.size / 1e6), max: Math.round(MAX_GPX_BYTES / 1e6) });
      return;
    }
    this.store.set({ trackStatus: 'reading', trackError: null, progress: 0 });
    let xml: string;
    try {
      // Lu en octets : file.text() décoderait toujours en UTF-8, même un GPX en ISO-8859-1.
      xml = decodeGpx(new Uint8Array(await file.arrayBuffer()));
    } catch {
      fail('gpx.error.read');
      return;
    }
    await this.importGpxText(xml, file.name, seq);
  }

  /** Charge et analyse un GPX déjà lu (import d'un fichier, ou tracé enregistré pour le hors ligne). */
  private async importGpxText(xml: string, fileName: string, seq: number = ++this.importSeq): Promise<void> {
    const file = { name: fileName };
    const fail = (key: string, params?: Record<string, string | number>): void => {
      if (seq !== this.importSeq) return;
      this.store.set({ trackStatus: this.state.track ? 'ready' : 'error', trackError: { key, params }, panel: 'gpx' });
    };
    let track: LoadedTrack;
    try {
      const parsed = parseGpx(xml);
      const samples = resample(parsed.segments);
      track = {
        fileName: file.name,
        xml,
        parsed,
        samples,
        length: samples.length > 0 ? samples[samples.length - 1].dist : 0,
        analysis: null,
        report: null,
      };
    } catch (error) {
      fail(error instanceof GpxError ? `gpx.error.${error.code}` : 'gpx.error.invalid');
      return;
    }
    if (seq !== this.importSeq) return;

    // Le tracé s'affiche tout de suite, d'une seule couleur, et la carte zoome dessus.
    this.store.set({ track, selectedZone: null, trackStatus: this.tileStore ? 'analyzing' : 'ready', panel: this.tileStore ? this.state.panel : 'report' });
    this.showTrack(track);
    const bounds = samplesBounds(track.samples);
    if (bounds) this.mapView.fitBounds(bounds, this.hooks.padding());

    const store = this.tileStore;
    const manifest = this.state.manifest;
    if (!store || !manifest) return;
    try {
      const raw = await sampleCoverage(track.samples, store, (done, total) => {
        if (seq === this.importSeq) this.store.set({ progress: total > 0 ? done / total : 1 });
      });
      if (seq !== this.importSeq) return;
      const analysis = analyzeTrack(track.samples, raw);
      const analysed: LoadedTrack = { ...track, analysis, report: buildReport(analysis, manifest, this.decodeSettings()) };
      this.store.set({ track: analysed, trackStatus: 'ready', panel: 'report' });
      this.showTrack(analysed);
    } catch (error) {
      console.warn('Analyse du tracé :', error);
      if (seq !== this.importSeq) return;
      this.store.set({ trackStatus: 'ready', trackError: { key: 'gpx.error.analysis' }, panel: 'gpx' });
    }
  }

  /** Relance l'analyse du tracé chargé (après un échec réseau par exemple). */
  async retryAnalysis(): Promise<void> {
    const { track, manifest } = this.state;
    const store = this.tileStore;
    if (!track || !manifest || !store) return;
    this.restartReads();
    const seq = ++this.importSeq;
    this.store.set({ trackStatus: 'analyzing', trackError: null, progress: 0 });
    try {
      const raw = await sampleCoverage(track.samples, store, (done, total) => {
        if (seq === this.importSeq) this.store.set({ progress: total > 0 ? done / total : 1 });
      });
      if (seq !== this.importSeq) return;
      const analysis = analyzeTrack(track.samples, raw);
      const analysed: LoadedTrack = { ...track, analysis, report: buildReport(analysis, manifest, this.decodeSettings()) };
      this.store.set({ track: analysed, trackStatus: 'ready', panel: 'report' });
      this.showTrack(analysed);
    } catch (error) {
      console.warn('Analyse du tracé :', error);
      if (seq === this.importSeq) this.store.set({ trackStatus: 'ready', trackError: { key: 'gpx.error.analysis' } });
    }
  }

  /**
   * Après une panne : les lectures suivantes repartent du réseau, avec des
   * archives neuves, au lieu d'attendre des requêtes restées en suspens.
   */
  private restartReads(): void {
    this.tileStore?.restart();
    this.readArchive?.reset();
  }

  private showTrack(track: LoadedTrack | null): void {
    if (!track) {
      this.mapView.setTrack(EMPTY_COLLECTION);
      this.mapView.setZone(EMPTY_COLLECTION);
      this.mapView.setEndpoints([]);
      this.mapView.setCursor(null);
      return;
    }
    this.mapView.setTrack(trackToGeoJson(track.samples, track.report?.classes ?? null));
    const first = track.samples[0];
    const last = track.samples[track.samples.length - 1];
    this.mapView.setEndpoints([
      { lon: first.lon, lat: first.lat, kind: 'start', label: t('gpx.start') },
      { lon: last.lon, lat: last.lat, kind: 'end', label: t('gpx.end') },
    ]);
    const zone = track.report?.zones.find((z) => z.index === this.state.selectedZone) ?? null;
    this.mapView.setZone(zoneToGeoJson(track.samples, zone));
  }

  /** Recalcule le rapport après un changement d'opérateur ou de service. Rien n'est relu dans les tuiles. */
  private refreshReport(): void {
    const { track, manifest } = this.state;
    if (!track?.analysis || !manifest) return;
    const updated: LoadedTrack = { ...track, report: buildReport(track.analysis, manifest, this.decodeSettings()) };
    this.store.set({ track: updated, selectedZone: null });
    this.showTrack(updated);
  }

  /** Montre sur la carte le point du tracé survolé dans le profil altimétrique. */
  showTrackCursor(index: number | null): void {
    const sample = index === null ? undefined : this.state.track?.samples[index];
    this.mapView.setCursor(sample ? { lon: sample.lon, lat: sample.lat } : null);
  }

  removeTrack(): void {
    this.importSeq++;
    this.store.set({ track: null, trackStatus: 'idle', trackError: null, selectedZone: null, panel: this.state.panel === 'report' ? 'gpx' : this.state.panel });
    this.showTrack(null);
  }

  fitTrack(): void {
    const bounds = this.state.track ? samplesBounds(this.state.track.samples) : null;
    if (bounds) this.mapView.fitBounds(bounds, this.hooks.padding());
  }

  /** Met une zone blanche en surbrillance et zoome dessus. */
  selectZone(index: number | null): void {
    const { track } = this.state;
    const zone = track?.report?.zones.find((z) => z.index === index) ?? null;
    this.store.set({ selectedZone: zone ? zone.index : null });
    if (!track) return;
    this.mapView.setZone(zoneToGeoJson(track.samples, zone));
    if (zone) this.mapView.fitBounds(zone.bbox, this.hooks.padding(), 16);
  }

  // -- hors ligne -----------------------------------------------------------

  /** Enregistre dans le navigateur le tracé, sa couverture et le fond affiché, pour un usage sans réseau. */
  async prepareOffline(): Promise<void> {
    const { track, manifest, activeBasemap } = this.state;
    const readArchive = this.readArchive;
    if (!track || !manifest || !readArchive || !offlineSupported()) return;
    this.offlineAbort?.abort();
    const abort = new AbortController();
    this.offlineAbort = abort;
    this.store.set({ offline: { ...this.state.offline, status: 'preparing', progress: 0 } });
    try {
      const info = await prepareOffline(import.meta.env.BASE_URL, {
        samples: track.samples,
        trackName: track.parsed.name ?? track.fileName,
        gpxText: track.xml,
        fileName: track.fileName,
        coverageMaxZoom: manifest.tiles.maxzoom,
        readCoverageTile: async (z, x, y) => {
          const archive = archiveForTile(manifest, z, x, y);
          // Même délai que pour l'affichage : une connexion qui cale ne fige pas l'enregistrement.
          return archive ? readArchive(archive.file, z, x, y, AbortSignal.timeout(TILE_READ_TIMEOUT_MS)) : undefined;
        },
        basemap: basemapPack(activeBasemap, this.mapView.currentVectorStyle()),
        onProgress: (done, total) => {
          if (!abort.signal.aborted) this.store.set({ offline: { ...this.state.offline, progress: total > 0 ? done / total : 1 } });
        },
        signal: abort.signal,
      });
      this.store.set({ offline: { status: 'idle', progress: 1, info } });
    } catch (error) {
      if (abort.signal.aborted) return;
      console.warn('Préparation du hors ligne :', error);
      this.store.set({ offline: { ...this.state.offline, status: 'error', progress: 0 } });
    }
  }

  async clearOfflineData(): Promise<void> {
    this.offlineAbort?.abort();
    await clearOffline();
    this.store.set({ offline: { status: 'idle', progress: 0, info: null } });
    this.hooks.toast(t('offline.cleared'));
  }

  /** Recharge le tracé enregistré pour le hors ligne. */
  async restoreOfflineTrack(): Promise<void> {
    const stored = await storedTrack(import.meta.env.BASE_URL);
    if (!stored) return;
    await this.importGpxText(stored.text, stored.fileName);
    const name = this.state.track?.parsed.name ?? stored.fileName;
    if (this.state.track) this.hooks.toast(t('offline.restored', { name }));
  }

  // -- export ---------------------------------------------------------------

  reportAsText(): string | null {
    const { track, manifest } = this.state;
    if (!track?.analysis || !track.report || !manifest) return null;
    return reportText(track.analysis, track.report, manifest, this.decodeSettings(), track.parsed.name ?? track.fileName);
  }

  async copyReport(): Promise<boolean> {
    const text = this.reportAsText();
    if (!text) return false;
    try {
      await navigator.clipboard.writeText(text);
      this.hooks.toast(t('report.copied'));
      return true;
    } catch {
      this.hooks.toast(t('report.copyFailed'));
      return false;
    }
  }

  /** Fabrique le GPX enrichi et le fait télécharger. Tout se passe dans le navigateur. */
  downloadEnrichedGpx(): void {
    const { track, manifest } = this.state;
    if (!track?.analysis || !track.report || !manifest) return;
    try {
      const xml = enrichGpx(track.xml, zoneWaypoints(track.analysis, track.report, manifest));
      const blob = new Blob([xml], { type: 'application/gpx+xml' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = enrichedFileName(track.fileName, t('export.fileSuffix'));
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 10_000);
    } catch (error) {
      console.warn('Export GPX :', error);
      this.hooks.toast(t('export.failed'));
    }
  }

  // -- divers ---------------------------------------------------------------

  locate(): void {
    this.mapView.locate();
  }

  changeLanguage(code: string): void {
    setLanguage(code);
  }

  /** À appeler après un changement de langue : les textes posés sur la carte sont refaits. */
  onLanguageChanged(): void {
    this.mapView.updateLabels();
    if (this.state.track) this.showTrack(this.state.track);
  }

  goTo(place: { lon: number; lat: number; zoom: number; bbox?: [number, number, number, number] }): void {
    if (place.bbox) this.mapView.fitBounds(place.bbox, this.hooks.padding(), 15);
    else this.mapView.flyTo(place.lon, place.lat, place.zoom, this.hooks.padding());
  }

  /** Vrai si le centre de la carte est hors de France (pour l'ordre des résultats de recherche). */
  centerIsAbroad(): boolean {
    const active = this.state.activeBasemap;
    return this.state.basemap.choice === 'auto' && BASEMAPS[active].id !== 'ign-classique';
  }

  language(): string {
    return getLanguage();
  }
}
