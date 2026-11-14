// Fausse carte MapLibre pour les tests de MapView : elle note ce qu'on lui demande
// (styles, mouvements, repères) et émet les événements comme la vraie, sans WebGL.

type Listener = (event: Record<string, unknown>) => void;

export interface FakeStyle {
  version: 8;
  sources: Record<string, unknown>;
  layers: { id: string; type: string; layout?: Record<string, unknown> }[];
  glyphs?: string;
  sprite?: unknown;
}

/** Élément HTML réduit à ce que MapView et les repères utilisent. */
export class FakeElement {
  className = '';
  title = '';
  readonly style: Record<string, string> = {};
  readonly attributes = new Map<string, string>();
  readonly classList = {
    toggle: (name: string, on?: boolean): void => {
      const names = new Set(this.className.split(' ').filter(Boolean));
      if (on ?? !names.has(name)) names.add(name);
      else names.delete(name);
      this.className = [...names].join(' ');
    },
    contains: (name: string): boolean => this.className.split(' ').includes(name),
  };
  setAttribute(name: string, value: string): void {
    this.attributes.set(name, value);
  }
  querySelector(): null {
    return null;
  }
}

export class FakeMarker {
  static live = new Set<FakeMarker>();
  readonly element: FakeElement;
  lngLat: [number, number] | null = null;
  constructor(options: { element: FakeElement }) {
    this.element = options.element;
  }
  setLngLat(lngLat: [number, number]): this {
    this.lngLat = lngLat;
    return this;
  }
  addTo(): this {
    FakeMarker.live.add(this);
    return this;
  }
  remove(): this {
    FakeMarker.live.delete(this);
    return this;
  }
  getElement(): FakeElement {
    return this.element;
  }
}

export class FakeMap {
  static last: FakeMap | null = null;
  /** Règle de validation des styles, comme celle de MapLibre : messages d'erreur, vide si le style est accepté. */
  static validate: (style: FakeStyle) => string[] = () => [];
  readonly styles: FakeStyle[] = [];
  readonly moves: { kind: 'flyTo' | 'fitBounds' | 'easeTo'; options: Record<string, unknown> }[] = [];
  /** Dernier style accepté. */
  style: FakeStyle | null = null;
  center = { lng: 2.6, lat: 46.5 };
  zoom = 5.2;
  readonly touchZoomRotate = { disableRotation: (): void => undefined };
  readonly keyboard = { disableRotation: (): void => undefined };
  private readonly listeners = new Map<string, Set<Listener>>();
  private readonly container = new FakeElement();
  private readonly canvas = new FakeElement();

  constructor(readonly options: Record<string, unknown>) {
    FakeMap.last = this;
  }

  on(type: string, listener: Listener): { unsubscribe: () => void } {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set());
    this.listeners.get(type)!.add(listener);
    return { unsubscribe: () => this.off(type, listener) };
  }

  off(type: string, listener: Listener): this {
    this.listeners.get(type)?.delete(listener);
    return this;
  }

  fire(type: string, event: Record<string, unknown> = {}): void {
    for (const listener of [...(this.listeners.get(type) ?? [])]) listener({ type, ...event });
  }

  addControl(): this {
    return this;
  }

  setStyle(style: FakeStyle): this {
    this.styles.push(style);
    const errors = FakeMap.validate(style);
    // Comme MapLibre avec un style déjà chargé : la validation et le chargement se font pendant l'appel.
    for (const message of errors) this.fire('error', { error: new Error(message) });
    if (errors.length === 0) {
      this.style = style;
      this.fire('style.load');
    }
    return this;
  }

  getSource(id: string): unknown {
    return this.style?.sources[id];
  }

  getLayer(id: string): unknown {
    return this.style?.layers.find((layer) => layer.id === id);
  }

  setPaintProperty(): void {}
  refreshTiles(): void {}

  private move(kind: 'flyTo' | 'fitBounds' | 'easeTo', options: Record<string, unknown>, eventData?: Record<string, unknown>): this {
    this.moves.push({ kind, options });
    this.fire('movestart', { ...eventData });
    if (Array.isArray(options.center)) this.center = { lng: options.center[0] as number, lat: options.center[1] as number };
    if (typeof options.zoom === 'number') this.zoom = options.zoom;
    this.fire('moveend', { ...eventData });
    return this;
  }

  flyTo(options: Record<string, unknown>, eventData?: Record<string, unknown>): this {
    return this.move('flyTo', options, eventData);
  }

  easeTo(options: Record<string, unknown>, eventData?: Record<string, unknown>): this {
    return this.move('easeTo', options, eventData);
  }

  fitBounds(bounds: unknown, options: Record<string, unknown>, eventData?: Record<string, unknown>): this {
    return this.move('fitBounds', { bounds, ...options }, eventData);
  }

  getCenter(): { lng: number; lat: number } {
    return this.center;
  }

  getZoom(): number {
    return this.zoom;
  }

  getContainer(): FakeElement {
    return this.container;
  }

  getCanvas(): FakeElement {
    return this.canvas;
  }
}

/** Module « maplibre-gl » remplacé, à passer à vi.mock. */
export const fakeMaplibreModule = {
  Map: FakeMap,
  Marker: FakeMarker,
  NavigationControl: class {},
  ScaleControl: class {},
  setWorkerUrl: (): void => undefined,
  addProtocol: (): void => undefined,
};
