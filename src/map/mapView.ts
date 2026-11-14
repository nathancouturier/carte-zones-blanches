// La carte MapLibre : fond, couche réseau, tracé GPX, position.

import {
  GeolocateControl,
  Map as MapLibreMap,
  Marker,
  NavigationControl,
  ScaleControl,
  setWorkerUrl,
  type StyleSpecification,
} from 'maplibre-gl';
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?url';
import { INITIAL_VIEW, MAX_BOUNDS } from '../config';
import { COVERAGE_PROTOCOL } from '../coverage/protocol';
import { BASEMAPS, type BasemapId } from './basemaps';
import {
  buildStyle,
  COVERAGE_LAYER,
  COVERAGE_SOURCE,
  loadedVectorStyle,
  loadVectorStyle,
  TRACK_SOURCE,
  ZONE_SOURCE,
  type CoverageLayerOptions,
} from './style';
import { EMPTY_COLLECTION } from './trackGeojson';

// Le worker de MapLibre est un fichier à part : on indique son adresse au bundler.
setWorkerUrl(workerUrl);

/** Délai maximal pour obtenir la position GPS, en millisecondes. */
const LOCATE_TIMEOUT_MS = 15_000;
/** Délai au-delà duquel un style sans réponse de MapLibre (rien à changer) est tenu pour accepté. */
const STYLE_CHECK_MS = 2000;

export interface StyleInputs {
  basemap: BasemapId;
  hillshade: boolean;
  coverage: Omit<CoverageLayerOptions, 'tilesUrl'> | null;
}

export interface Padding {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

/** Décalage, depuis le centre de la carte, du centre de la partie laissée libre par les marges. */
export function centerOffset(padding: Padding): [number, number] {
  return [(padding.left - padding.right) / 2, (padding.top - padding.bottom) / 2];
}

export interface MapViewOptions {
  container: HTMLElement;
  /** Libellés des contrôles de la carte, dans la langue courante. */
  labels: () => Record<string, string>;
  onMoveEnd: () => void;
  onLocateError: () => void;
  /** Appelé quand un style vectoriel n'a pas pu être chargé (ou a été refusé) et qu'on affiche le fond de repli. */
  onStyleFallback: (basemap: BasemapId, reason: 'unreachable' | 'refused') => void;
}

export class MapView {
  readonly map: MapLibreMap;
  private readonly geolocate: GeolocateControl;
  private styleSeq = 0;
  private track: GeoJSON.FeatureCollection = EMPTY_COLLECTION;
  private zone: GeoJSON.FeatureCollection = EMPTY_COLLECTION;
  private markers: Marker[] = [];
  private cursor: Marker | null = null;
  private vectorStyle: StyleSpecification | null = null;
  private inputs: StyleInputs | null = null;
  /** Styles vectoriels que MapLibre a refusés : la version en images les remplace sans nouvel essai. */
  private readonly refusedStyles = new Set<string>();

  constructor(private readonly options: MapViewOptions) {
    this.map = new MapLibreMap({
      container: options.container,
      style: { version: 8, sources: {}, layers: [{ id: 'fond-uni', type: 'background', paint: { 'background-color': '#e9ecef' } }] },
      center: INITIAL_VIEW.center,
      zoom: INITIAL_VIEW.zoom,
      minZoom: 3,
      maxZoom: 18,
      maxBounds: [
        [MAX_BOUNDS[0], MAX_BOUNDS[1]],
        [MAX_BOUNDS[2], MAX_BOUNDS[3]],
      ],
      hash: true,
      attributionControl: false,
      dragRotate: false,
      pitchWithRotate: false,
      touchPitch: false,
      locale: options.labels(),
    });
    // La carte reste orientée au nord : plus simple à lire avec des fonds en image.
    this.map.touchZoomRotate.disableRotation();
    this.map.keyboard.disableRotation();

    this.map.addControl(new NavigationControl({ showCompass: false }), 'top-right');
    // Chaque appui sur « Ma position » relit la position, l'affiche et centre la carte dessus.
    // En mode suivi (trackUserLocation), un second appui coupait la localisation, et la carte
    // revenait seule sur l'utilisateur après une recherche.
    this.geolocate = new GeolocateControl({
      positionOptions: { enableHighAccuracy: true, timeout: LOCATE_TIMEOUT_MS },
      trackUserLocation: false,
      showAccuracyCircle: true,
    });
    this.map.addControl(this.geolocate, 'top-right');
    this.geolocate.on('error', () => options.onLocateError());
    this.map.addControl(new ScaleControl({ maxWidth: 120, unit: 'metric' }), 'bottom-left');
    this.map.on('moveend', () => options.onMoveEnd());
    // Une tuile de fond manquante ne doit pas remplir la console d'erreurs bloquantes.
    // Les erreurs de la couche réseau, elles, sont signalées (la source le dit, pas le message).
    this.map.on('error', (event) => {
      const { sourceId, error } = event as { sourceId?: string; error?: unknown };
      if (sourceId === COVERAGE_SOURCE) console.warn('Couche réseau :', error);
    });
  }

  /**
   * Applique le fond, l'estompage et la couche réseau demandés. Un fond vectoriel dont
   * le style n'est pas encore là est d'abord montré en images (Plan IGN raster), avec
   * la couche réseau et le tracé : rien n'attend le style, dont le téléchargement est
   * borné. Style injoignable, trop lent ou refusé par MapLibre : la version en images
   * reste, et on le dit.
   */
  async setStyleInputs(inputs: StyleInputs): Promise<void> {
    this.inputs = inputs;
    const seq = ++this.styleSeq;
    const basemap = BASEMAPS[inputs.basemap];
    if (basemap.kind !== 'vector' || this.refusedStyles.has(basemap.styleUrl)) {
      void this.applyStyle(inputs, null);
      return;
    }
    let vectorStyle = loadedVectorStyle(basemap.styleUrl);
    if (!vectorStyle) {
      void this.applyStyle(inputs, null);
      try {
        vectorStyle = await loadVectorStyle(basemap.styleUrl);
      } catch (error) {
        if (seq !== this.styleSeq) return;
        console.warn('Style du Plan IGN injoignable, version en images :', error);
        this.options.onStyleFallback(inputs.basemap, 'unreachable');
        return;
      }
      if (seq !== this.styleSeq) return; // un autre changement est arrivé entre-temps
    }
    const { styleUrl } = basemap;
    void this.applyStyle(inputs, vectorStyle).then((accepted) => {
      if (accepted || seq !== this.styleSeq) return;
      console.warn(`Style ${styleUrl} refusé par MapLibre : version en images.`);
      this.refusedStyles.add(styleUrl);
      void this.applyStyle(inputs, null);
      this.options.onStyleFallback(inputs.basemap, 'refused');
    });
  }

  /**
   * Bâtit et applique le style. Résout faux si MapLibre le refuse : il le valide pendant
   * l'appel (style déjà chargé) ou à l'image suivante (style rechargé en entier), et
   * signale chaque défaut par une erreur qui ne vient d'aucune source ni d'aucune tuile.
   */
  private applyStyle(inputs: StyleInputs, vectorStyle: StyleSpecification | null): Promise<boolean> {
    this.vectorStyle = vectorStyle;
    const style = buildStyle({
      basemap: inputs.basemap,
      vectorStyle,
      hillshade: inputs.hillshade,
      coverage: inputs.coverage ? { ...inputs.coverage, tilesUrl: `${COVERAGE_PROTOCOL}://{z}/{x}/{y}` } : null,
      track: this.track,
      zone: this.zone,
    });
    return new Promise((resolve) => {
      let refused = false;
      const finish = (): void => {
        clearTimeout(timer);
        this.map.off('error', onError);
        this.map.off('style.load', finish);
        resolve(!refused);
      };
      const onError = (event: unknown): void => {
        const { sourceId, tile } = event as { sourceId?: string; tile?: unknown };
        if (sourceId || tile) return;
        refused = true;
        finish();
      };
      this.map.on('error', onError);
      this.map.on('style.load', finish);
      // Rien à changer : MapLibre n'émet rien. Passé ce délai, le style est tenu pour accepté.
      const timer = setTimeout(finish, STYLE_CHECK_MS);
      this.map.setStyle(style, { diff: true });
    });
  }

  /** Style vectoriel du fond affiché, ou null si le fond est en images. */
  currentVectorStyle(): StyleSpecification | null {
    return this.vectorStyle;
  }

  /** Redessine la couche réseau après un changement de réglage, sans rien retélécharger. */
  refreshCoverage(): void {
    if (this.map.getSource(COVERAGE_SOURCE)) this.map.refreshTiles(COVERAGE_SOURCE);
  }

  setCoverageOpacity(opacity: number): void {
    if (this.inputs?.coverage) this.inputs.coverage.opacity = opacity;
    if (this.map.getLayer(COVERAGE_LAYER)) this.map.setPaintProperty(COVERAGE_LAYER, 'raster-opacity', opacity);
  }

  setTrack(track: GeoJSON.FeatureCollection): void {
    this.track = track;
    const source = this.map.getSource(TRACK_SOURCE) as { setData?: (data: GeoJSON.FeatureCollection) => void } | undefined;
    source?.setData?.(track);
  }

  setZone(zone: GeoJSON.FeatureCollection): void {
    this.zone = zone;
    const source = this.map.getSource(ZONE_SOURCE) as { setData?: (data: GeoJSON.FeatureCollection) => void } | undefined;
    source?.setData?.(zone);
  }

  /** Place les repères de départ et d'arrivée du tracé. */
  setEndpoints(points: { lon: number; lat: number; kind: 'start' | 'end'; label: string }[]): void {
    for (const marker of this.markers) marker.remove();
    this.markers = points.map((p) => {
      const el = document.createElement('div');
      el.className = `track-marker track-marker--${p.kind}`;
      el.title = p.label;
      el.setAttribute('aria-label', p.label);
      return new Marker({ element: el }).setLngLat([p.lon, p.lat]).addTo(this.map);
    });
  }

  /** Repère mobile sur le tracé (point survolé dans le profil altimétrique). null pour le retirer. */
  setCursor(point: { lon: number; lat: number } | null): void {
    if (!point) {
      this.cursor?.remove();
      this.cursor = null;
      return;
    }
    if (!this.cursor) {
      const el = document.createElement('div');
      el.className = 'track-cursor';
      this.cursor = new Marker({ element: el }).setLngLat([point.lon, point.lat]).addTo(this.map);
    } else {
      this.cursor.setLngLat([point.lon, point.lat]);
    }
  }

  fitBounds(bbox: [number, number, number, number], padding: Padding, maxZoom = 15): void {
    const [west, south, east, north] = bbox;
    this.map.fitBounds(
      [
        [west, south],
        [east, north],
      ],
      { padding, maxZoom, duration: 600 },
    );
  }

  /**
   * Centre la carte sur un point, au milieu de la partie que les marges laissent libre.
   * Un décalage (offset) et non une marge (padding) : MapLibre garderait la marge après
   * le vol et l'ajouterait à chaque cadrage suivant (import d'un GPX, zone du rapport).
   */
  flyTo(lon: number, lat: number, zoom: number, padding: Padding): void {
    this.map.flyTo({ center: [lon, lat], zoom, offset: centerOffset(padding), duration: 700 });
  }

  /**
   * Lit la position, l'affiche et centre la carte dessus. La promesse se termine
   * quand la position est connue ou se révèle indisponible.
   */
  locate(): Promise<void> {
    return new Promise((resolve) => {
      const done = (): void => {
        clearTimeout(timer);
        for (const subscription of subscriptions) subscription.unsubscribe();
        resolve();
      };
      const subscriptions = [this.geolocate.on('geolocate', done), this.geolocate.on('error', done), this.geolocate.on('outofmaxbounds', done)];
      // Filet de sécurité : sans réponse à la demande d'autorisation, certains navigateurs ne disent rien.
      const timer = setTimeout(done, LOCATE_TIMEOUT_MS + 5000);
      if (!this.geolocate.trigger()) done();
    });
  }

  /** Points répartis dans la vue (dont le centre en premier), pour savoir quels pays sont à l'écran. */
  viewSamplePoints(): { lon: number; lat: number }[] {
    const center = this.map.getCenter();
    const bounds = this.map.getBounds();
    const west = bounds.getWest();
    const east = bounds.getEast();
    const south = bounds.getSouth();
    const north = bounds.getNorth();
    const points = [{ lon: center.lng, lat: center.lat }];
    for (const fy of [0.15, 0.5, 0.85]) {
      for (const fx of [0.15, 0.5, 0.85]) {
        if (fx === 0.5 && fy === 0.5) continue;
        points.push({ lon: west + (east - west) * fx, lat: south + (north - south) * fy });
      }
    }
    return points;
  }

  /** Zoom des tuiles de données actuellement affichées. */
  dataZoom(minzoom: number, maxzoom: number): number {
    return Math.max(minzoom, Math.min(maxzoom, Math.round(this.map.getZoom() + 1)));
  }

  /** Met à jour les infobulles des contrôles et le nom de la carte après un changement de langue. */
  updateLabels(): void {
    const labels = this.options.labels();
    const set = (selector: string, key: string): void => {
      const el = this.map.getContainer().querySelector<HTMLElement>(selector);
      if (el && labels[key]) {
        el.title = labels[key];
        el.setAttribute('aria-label', labels[key]);
      }
    };
    set('.maplibregl-ctrl-zoom-in', 'NavigationControl.ZoomIn');
    set('.maplibregl-ctrl-zoom-out', 'NavigationControl.ZoomOut');
    set('.maplibregl-ctrl-geolocate', 'GeolocateControl.FindMyLocation');
    // Le canevas n'a pas d'infobulle : seul son nom accessible change.
    if (labels['Map.Title']) this.map.getCanvas().setAttribute('aria-label', labels['Map.Title']);
  }
}
