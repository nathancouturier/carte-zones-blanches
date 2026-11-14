// « Ma position » : la position suit la marche tant que la page est visible, sans
// jamais déplacer la carte d'elle-même. Un appui sur le bouton recentre la carte
// sur la position ; un autre appui ne coupe rien. Le suivi s'arrête quand la page
// est cachée (batterie) et reprend à son retour.

/** Position affichée : longitude, latitude et précision, en mètres. */
export interface UserPosition {
  lon: number;
  lat: number;
  accuracy: number;
}

/** Pourquoi la position manque : autorisation refusée, position indisponible, GPS encore en recherche. */
export type LocateProblem = 'denied' | 'unavailable' | 'timeout';

/**
 * Délai au-delà duquel on prévient que le GPS cherche encore, en millisecondes.
 * Loin de tout relais, sans aide du réseau, le premier point peut prendre plus
 * longtemps : le suivi continue, la position s'affichera à son arrivée.
 */
export const LOCATE_SLOW_MS = 15_000;

/** Réglages de la géolocalisation : précision du GPS, position de moins de 10 s acceptée. */
const WATCH_OPTIONS: PositionOptions = { enableHighAccuracy: true, maximumAge: 10_000 };

/** Codes d'erreur de la géolocalisation (GeolocationPositionError). */
const PERMISSION_DENIED = 1;
const TIMEOUT = 3;

export interface LocatorOptions {
  geolocation: Pick<Geolocation, 'watchPosition' | 'clearWatch'> | undefined;
  /** Montre la position, « stale » quand le suivi est arrêté ; null la retire. */
  show: (position: UserPosition | null, stale: boolean) => void;
  /** Centre la carte sur la position. */
  center: (position: UserPosition) => void;
  onProblem: (problem: LocateProblem) => void;
  slowAfterMs?: number;
}

export class Locator {
  private watchId: number | null = null;
  /** L'utilisateur a demandé sa position : le suivi tourne tant que la page est visible. */
  private wanted = false;
  private last: UserPosition | null = null;
  /** Aucune position depuis l'appui : un échec se dit ; ensuite, il grise seulement le point. */
  private searching = false;
  /** Un appui attend la position pour centrer la carte dessus. */
  private centerOnFix = false;
  /** Termine l'attente du bouton (position trouvée, problème ou délai). */
  private release: (() => void) | null = null;
  private slowTimer: ReturnType<typeof setTimeout> | undefined;
  /** Problèmes déjà dits depuis le dernier appui : on ne les répète pas. */
  private readonly told = new Set<LocateProblem>();

  constructor(private readonly options: LocatorOptions) {}

  /**
   * Appui sur « Ma position » : démarre le suivi s'il ne tourne pas, et centre la carte
   * sur la position, tout de suite si elle est connue, sinon à son arrivée. La promesse
   * se termine quand c'est fait, ou quand on a dit pourquoi la position manque.
   */
  locate(): Promise<void> {
    if (!this.options.geolocation) {
      this.options.onProblem('unavailable');
      return Promise.resolve();
    }
    this.wanted = true;
    this.told.clear();
    this.start();
    if (this.last) {
      this.options.center(this.last);
      return Promise.resolve();
    }
    this.searching = true;
    this.centerOnFix = true;
    this.release?.();
    return new Promise((resolve) => {
      this.release = () => {
        this.release = null;
        clearTimeout(this.slowTimer);
        resolve();
      };
      this.slowTimer = setTimeout(() => this.problem('timeout'), this.options.slowAfterMs ?? LOCATE_SLOW_MS);
    });
  }

  /** La carte a bougé autrement que par « Ma position » (geste, cadrage commandé par le site) : on ne la recentrera pas. */
  cancelCenter(): void {
    this.centerOnFix = false;
  }

  /** Page cachée : le suivi s'arrête et la position affichée devient ancienne ; au retour, il reprend s'il était demandé. */
  setVisible(visible: boolean): void {
    if (!visible) {
      this.stop();
      if (this.last) this.options.show(this.last, true);
    } else if (this.wanted) {
      this.start();
    }
  }

  private start(): void {
    if (this.watchId !== null || !this.options.geolocation) return;
    this.watchId = this.options.geolocation.watchPosition(
      (position) => this.onPosition(position),
      (error) => this.onError(error),
      WATCH_OPTIONS,
    );
  }

  private stop(): void {
    if (this.watchId === null) return;
    this.options.geolocation?.clearWatch(this.watchId);
    this.watchId = null;
  }

  private onPosition(position: GeolocationPosition): void {
    const { longitude: lon, latitude: lat, accuracy } = position.coords;
    this.last = { lon, lat, accuracy };
    this.searching = false;
    this.options.show(this.last, false);
    // La carte ne suit pas : elle ne bouge que pour l'appui qui attendait ce point.
    if (this.centerOnFix) {
      this.centerOnFix = false;
      this.options.center(this.last);
    }
    this.release?.();
  }

  private onError(error: GeolocationPositionError): void {
    if (error.code === PERMISSION_DENIED) {
      // Refusée : plus de suivi, plus de position affichée.
      this.wanted = false;
      this.centerOnFix = false;
      this.stop();
      this.last = null;
      this.options.show(null, false);
      this.problem('denied');
      return;
    }
    // Délai dépassé ou position indisponible : le suivi continue, la position viendra peut-être.
    // Avant le premier point, on le dit ; ensuite (signal perdu en marchant), le point devient gris.
    if (this.searching) this.problem(error.code === TIMEOUT ? 'timeout' : 'unavailable');
    else if (this.last) this.options.show(this.last, true);
  }

  private problem(problem: LocateProblem): void {
    if (!this.told.has(problem)) {
      this.told.add(problem);
      this.options.onProblem(problem);
    }
    this.release?.();
  }
}

/** Mètres par pixel de la carte, à cette latitude et à ce zoom (tuiles de 512 px, comme MapLibre). */
export function metersPerPixel(lat: number, zoom: number): number {
  return (40_075_016.686 * Math.cos((lat * Math.PI) / 180)) / (512 * 2 ** zoom);
}

/** Emprise du cercle de précision : ouest, sud, est, nord. */
export function accuracyBounds(position: UserPosition): [number, number, number, number] {
  const dLat = position.accuracy / 111_320;
  const dLon = position.accuracy / (111_320 * Math.max(Math.cos((position.lat * Math.PI) / 180), 0.01));
  return [position.lon - dLon, position.lat - dLat, position.lon + dLon, position.lat + dLat];
}
