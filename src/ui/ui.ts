// Coque de l'interface : barre du haut (recherche, paramètres), barre du bas
// (Réseau, Fond, GPX, Rapport), panneau unique, pied de carte, messages.
// Divulgation progressive : rien n'est empilé, tout s'ouvre au clic.

import type { App } from '../app';
import { SEARCH_DEBOUNCE_MS, SEARCH_MIN_CHARS, MAX_BOUNDS } from '../config';
import { countryByIso } from '../coverage/manifest';
import { getLanguage, onLanguageChange, t } from '../i18n';
import { BASEMAPS, HILLSHADE } from '../map/basemaps';
import type { Padding } from '../map/mapView';
import { searchPlaces, type Place } from '../search/geocode';
import type { AppState, PanelId } from '../state';
import { h, icon, ICONS, setChildren } from './dom';
import { basemapPanel, gpxPanel, networkPanel, reportPanel, settingsPanel, sourcesPanel } from './panels';

const PANEL_TITLES: Record<PanelId, string> = {
  network: 'network.title',
  basemap: 'basemap.title',
  gpx: 'gpx.title',
  report: 'report.heading',
  settings: 'settings.title',
  sources: 'sources.title',
};

const DESKTOP = '(min-width: 900px)';

/** Boutons de la barre du bas, dans l'ordre. Le bouton Rapport n'apparaît qu'après l'import d'un tracé. */
const TOOLS: { id: PanelId; icon: string; label: string }[] = [
  { id: 'network', icon: ICONS.network, label: 'toolbar.network' },
  { id: 'basemap', icon: ICONS.layers, label: 'toolbar.basemap' },
  { id: 'gpx', icon: ICONS.upload, label: 'toolbar.gpx' },
  { id: 'report', icon: ICONS.report, label: 'toolbar.report' },
];

export class Ui {
  private readonly toolbar: HTMLElement;
  private readonly topbar: HTMLElement;
  // Les boutons des barres sont créés une fois et mis à jour : recréés, ils perdraient le focus clavier.
  private readonly tools: HTMLButtonElement[];
  private readonly searchButton: HTMLButtonElement;
  private readonly locateButton: HTMLButtonElement;
  private readonly settingsButton: HTMLButtonElement;
  private readonly panel: HTMLElement;
  private readonly panelTitle: HTMLElement;
  private readonly panelBody: HTMLElement;
  private readonly panelBack: HTMLButtonElement;
  private readonly panelCollapse: HTMLButtonElement;
  private readonly attribution: HTMLElement;
  private readonly coverageAlert: HTMLElement;
  private readonly toastEl: HTMLElement;
  private readonly dropzone: HTMLElement;
  private readonly fileInput: HTMLInputElement;
  private readonly searchBox: HTMLElement;
  private readonly searchInput: HTMLInputElement;
  private readonly searchResults: HTMLElement;
  private searchOpen = false;
  private searchTimer: ReturnType<typeof setTimeout> | undefined;
  private searchAbort: AbortController | null = null;
  private searchSeq = 0;
  /** Saisie qui a produit la liste affichée : Entrée ne choisit que dans une liste à jour. */
  private resultsQuery: string | null = null;
  /** Entrée appuyée avant l'arrivée des résultats : le premier sera choisi. */
  private pickFirst = false;
  private toastTimer: ReturnType<typeof setTimeout> | undefined;
  private attributionOpen = false;
  /** Panneau Rapport réduit à son titre (téléphone), pour voir la carte. */
  private panelCollapsed = false;
  private dragDepth = 0;
  /** « Ma position » attend le GPS. */
  private locating = false;

  constructor(
    private readonly app: App,
    root: HTMLElement,
  ) {
    this.fileInput = h('input', {
      type: 'file',
      accept: '.gpx,application/gpx+xml,application/xml,text/xml',
      class: 'visually-hidden',
      tabindex: '-1',
      'aria-hidden': 'true',
      onchange: () => {
        const file = this.fileInput.files?.[0];
        this.fileInput.value = '';
        if (file) void this.app.importGpx(file);
      },
    });

    this.searchInput = h('input', {
      type: 'search',
      class: 'search__input',
      autocomplete: 'off',
      autocapitalize: 'off',
      spellcheck: 'false',
      enterkeyhint: 'search',
      oninput: () => this.onSearchInput(),
      onkeydown: (event: KeyboardEvent) => this.onSearchKey(event),
    });
    this.searchResults = h('ul', { class: 'search__results', role: 'listbox' });
    this.searchBox = h('div', { class: 'search', hidden: true, role: 'search' }, this.searchInput, this.searchResults);
    this.searchButton = h('button', { type: 'button', class: 'fab', onclick: () => (this.searchOpen ? this.closeSearch() : this.openSearch()) });
    this.locateButton = h('button', { type: 'button', class: 'fab', onclick: () => this.locate() }, icon(ICONS.locate));
    this.settingsButton = h('button', { type: 'button', class: 'fab', onclick: () => this.app.openPanel('settings') }, icon(ICONS.settings));
    this.topbar = h('div', { class: 'topbar' }, this.searchButton, this.searchBox, h('div', { class: 'topbar__spacer' }), this.locateButton, this.settingsButton);
    this.tools = TOOLS.map(({ id, icon: path }) =>
      h('button', { type: 'button', class: 'tool', dataset: { panel: id }, onclick: () => this.app.openPanel(id) }, icon(path), h('span')),
    );
    this.toolbar = h('nav', { class: 'toolbar' }, this.tools);

    // tabindex -1 : le titre reçoit le focus à l'ouverture du panneau, sans entrer dans l'ordre de tabulation.
    this.panelTitle = h('h2', { class: 'panel__title', id: 'panel-title', tabindex: '-1' });
    this.panelBody = h('div', { class: 'panel__body', id: 'panel-body' });
    this.panelBack = h('button', { type: 'button', class: 'icon-btn', onclick: () => this.app.openPanel('settings') }, icon(ICONS.back));
    this.panelCollapse = h('button', { type: 'button', class: 'icon-btn panel__collapse', 'aria-controls': 'panel-body', onclick: () => this.toggleCollapsed() });
    this.panel = h(
      'section',
      { class: 'panel', hidden: true, 'aria-labelledby': 'panel-title' },
      h(
        'header',
        { class: 'panel__head' },
        this.panelBack,
        this.panelTitle,
        this.panelCollapse,
        h('button', { type: 'button', class: 'icon-btn', dataset: { role: 'close' }, onclick: () => this.app.closePanel() }, icon(ICONS.close)),
      ),
      this.panelBody,
    );

    this.attribution = h('div', { class: 'attribution' });
    this.coverageAlert = h('div', { class: 'coverage-alert', role: 'status', hidden: true });
    this.toastEl = h('div', { class: 'toast', role: 'status', 'aria-live': 'polite', hidden: true });
    this.dropzone = h('div', { class: 'dropzone', hidden: true }, icon(ICONS.upload, 40), h('span'));

    // Le bandeau vient après le panneau et avant le message bref : la feuille de style les place l'un par rapport à l'autre.
    setChildren(root, this.topbar, this.toolbar, this.panel, this.attribution, this.coverageAlert, this.toastEl, this.dropzone, this.fileInput);

    this.app.setHooks({ toast: (message) => this.toast(message), padding: () => this.padding() });
    this.app.store.subscribe((state, previous) => this.onState(state, previous));
    onLanguageChange(() => {
      this.app.onLanguageChanged();
      this.renderAll();
    });
    this.bindDragAndDrop();
    document.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;
      if (this.searchOpen) this.closeSearch();
      else if (this.app.state.panel) this.app.closePanel();
    });
    this.renderAll();
  }

  chooseFile = (): void => {
    this.fileInput.click();
  };

  // -- rendu ----------------------------------------------------------------

  private onState(state: AppState, previous: AppState): void {
    this.render(state, previous);
    // Panneau fermé (Échap, Fermer) alors que le focus y était : il revient au bouton de ce panneau.
    if (previous.panel && !state.panel && this.focusLost()) this.panelButton(previous.panel)?.focus();
  }

  /** Vrai si le focus clavier n'est plus nulle part : sur la page, ou dans le panneau masqué. */
  private focusLost(): boolean {
    const active = document.activeElement;
    return !active || active === document.body || (this.panel.hidden && this.panel.contains(active));
  }

  /** Bouton qui ouvre un panneau : celui de la barre du bas, ou la roue dentée. */
  private panelButton(panel: PanelId): HTMLButtonElement | undefined {
    if (panel === 'settings' || panel === 'sources') return this.settingsButton;
    return this.tools.find((button) => button.dataset.panel === panel && !button.hidden);
  }

  private render(state: AppState, previous: AppState): void {
    // Pendant l'analyse, seul l'avancement change : on ne refait pas tout le panneau.
    const onlyProgress = (Object.keys(state) as (keyof AppState)[]).every((key) => key === 'progress' || state[key] === previous[key]);
    if (onlyProgress) {
      for (const el of this.panelBody.querySelectorAll<HTMLProgressElement>('progress[data-role="progress"]')) el.value = state.progress;
      return;
    }
    // Idem pendant l'enregistrement hors ligne.
    const onlyOffline =
      state.offline !== previous.offline &&
      state.offline.status === 'preparing' &&
      previous.offline.status === 'preparing' &&
      (Object.keys(state) as (keyof AppState)[]).every((key) => key === 'offline' || state[key] === previous[key]);
    if (onlyOffline) {
      for (const el of this.panelBody.querySelectorAll<HTMLProgressElement>('progress[data-role="offline-progress"]')) el.value = state.offline.progress;
      return;
    }
    // Le bandeau des tuiles illisibles suit le compteur d'échecs ; si rien d'autre n'a changé, c'est tout.
    if ((state.coverageErrors > 0) !== (previous.coverageErrors > 0)) this.renderCoverageAlert();
    if ((Object.keys(state) as (keyof AppState)[]).every((key) => key === 'coverageErrors' || state[key] === previous[key])) return;
    this.renderToolbar();
    const panelChanged =
      state.panel !== previous.panel ||
      state.network !== previous.network ||
      state.basemap !== previous.basemap ||
      state.activeBasemap !== previous.activeBasemap ||
      state.manifest !== previous.manifest ||
      state.dataStatus !== previous.dataStatus ||
      state.track !== previous.track ||
      state.trackStatus !== previous.trackStatus ||
      state.trackError !== previous.trackError ||
      state.selectedZone !== previous.selectedZone ||
      state.offline !== previous.offline;
    if (panelChanged) this.renderPanel(state.panel !== previous.panel);
    this.renderAttribution();
  }

  private renderAll(): void {
    document.title = t('app.title');
    document.querySelector('meta[name="description"]')?.setAttribute('content', t('app.description'));
    document.getElementById('map')?.setAttribute('aria-label', t('app.mapLabel'));
    this.renderTopbar();
    this.renderToolbar();
    this.renderPanel(false);
    this.renderAttribution();
    this.renderCoverageAlert();
    this.dropzone.querySelector('span')!.textContent = t('gpx.dropHere');
    this.searchInput.placeholder = t('search.placeholder');
    this.searchInput.setAttribute('aria-label', t('action.search'));
  }

  private renderTopbar(): void {
    const label = (button: HTMLButtonElement, key: string): void => {
      button.setAttribute('aria-label', t(key));
      button.title = t(key);
    };
    label(this.searchButton, 'action.search');
    this.searchButton.setAttribute('aria-expanded', String(this.searchOpen));
    setChildren(this.searchButton, icon(this.searchOpen ? ICONS.close : ICONS.search));
    label(this.locateButton, 'action.locate');
    this.locateButton.classList.toggle('fab--busy', this.locating);
    if (this.locating) this.locateButton.setAttribute('aria-busy', 'true');
    else this.locateButton.removeAttribute('aria-busy');
    label(this.settingsButton, 'action.settings');
    this.settingsButton.classList.toggle('fab--on', this.isPanel('settings', 'sources'));
  }

  /** « Ma position » : le bouton montre l'attente du GPS ; un nouvel appui pendant l'attente ne relance rien. */
  private locate(): void {
    if (this.locating) return;
    this.locating = true;
    this.renderTopbar();
    void this.app.locate().finally(() => {
      this.locating = false;
      this.renderTopbar();
    });
  }

  private isPanel(...ids: PanelId[]): boolean {
    const panel = this.app.state.panel;
    return panel !== null && ids.includes(panel);
  }

  private renderToolbar(): void {
    const { panel, track, trackStatus } = this.app.state;
    TOOLS.forEach(({ id, label }, i) => {
      const button = this.tools[i];
      button.classList.toggle('tool--on', panel === id);
      button.setAttribute('aria-pressed', String(panel === id));
      button.querySelector('span')!.textContent = t(label);
      if (id === 'gpx') button.classList.toggle('tool--busy', trackStatus === 'analyzing' || trackStatus === 'reading');
      if (id === 'report') button.hidden = !track;
    });
    this.toolbar.setAttribute('aria-label', t('toolbar.label'));
  }

  private renderPanel(opened: boolean): void {
    const { panel } = this.app.state;
    if (!panel) {
      this.panel.hidden = true;
      this.renderTopbar();
      return;
    }
    // On retient l'élément actif et le défilement pour les retrouver après le rendu.
    const active = document.activeElement instanceof HTMLElement && this.panel.contains(document.activeElement) ? document.activeElement.dataset.focus : undefined;
    const scroll = opened ? 0 : this.panelBody.scrollTop;
    this.panelTitle.textContent = t(PANEL_TITLES[panel]);
    this.panelBack.hidden = panel !== 'sources';
    this.panelBack.setAttribute('aria-label', t('action.back'));
    if (opened) this.panelCollapsed = false;
    this.renderCollapse(panel);
    this.panel.querySelector<HTMLElement>('[data-role="close"]')?.setAttribute('aria-label', t('action.close'));
    this.panel.dataset.panel = panel;
    let content;
    switch (panel) {
      case 'network':
        content = networkPanel(this.app);
        break;
      case 'basemap':
        content = basemapPanel(this.app);
        break;
      case 'gpx':
        content = gpxPanel(this.app, this.chooseFile);
        break;
      case 'report':
        content = reportPanel(this.app, this.chooseFile);
        break;
      case 'settings':
        content = settingsPanel(this.app);
        break;
      case 'sources':
        content = sourcesPanel(this.app);
        break;
    }
    setChildren(this.panelBody, content as never);
    this.panel.hidden = false;
    this.panelBody.scrollTop = scroll;
    // Panneau qui s'ouvre : le focus va sur son titre (lu par les lecteurs d'écran), sauf pendant une
    // saisie dans la recherche. Sinon, l'élément actif est retrouvé dans le nouveau rendu.
    if (opened) {
      if (!this.searchBox.contains(document.activeElement)) this.panelTitle.focus({ preventScroll: true });
    } else if (active) this.panelBody.querySelector<HTMLElement>(`[data-focus="${CSS.escape(active)}"]`)?.focus({ preventScroll: true });
    this.renderTopbar();
  }

  /** Sur téléphone, le panneau Rapport se réduit à son titre pour laisser voir la carte et le tracé. */
  private renderCollapse(panel: PanelId): void {
    const collapsed = panel === 'report' && this.panelCollapsed;
    this.panel.classList.toggle('panel--collapsed', collapsed);
    this.panelCollapse.hidden = panel !== 'report';
    this.panelCollapse.setAttribute('aria-expanded', String(!collapsed));
    const label = t(collapsed ? 'action.expand' : 'action.collapse');
    this.panelCollapse.setAttribute('aria-label', label);
    this.panelCollapse.title = label;
    setChildren(this.panelCollapse, icon(collapsed ? ICONS.chevronUp : ICONS.chevronDown));
  }

  private toggleCollapsed(): void {
    const { panel } = this.app.state;
    if (!panel) return;
    this.panelCollapsed = !this.panelCollapsed;
    this.renderCollapse(panel);
    // La carte visible a changé de taille : le tracé (ou la zone choisie) y est recadré.
    this.app.refitTrack();
  }

  private renderAttribution(): void {
    const { activeBasemap, basemap, manifest, visibleCountries, network } = this.app.state;
    const mentions = [BASEMAPS[activeBasemap].attribution];
    if (basemap.hillshade && !mentions.includes(HILLSHADE.attribution)) mentions.push(HILLSHADE.attribution);
    const coverage: string[] = [];
    if (manifest) {
      for (const iso of visibleCountries) {
        const country = countryByIso(manifest, iso);
        for (const source of country?.sources ?? []) {
          if (source.services.includes(network.service) && !coverage.includes(source.attribution)) coverage.push(source.attribution);
        }
      }
    }
    const text = [t('attribution.basemap', { names: mentions.join(', ') })];
    if (coverage.length > 0) text.push(t('attribution.coverage', { names: coverage.join(', ') }));
    setChildren(
      this.attribution,
      h(
        'button',
        {
          type: 'button',
          class: 'attribution__toggle',
          'aria-expanded': String(this.attributionOpen),
          'aria-label': t('attribution.toggle'),
          title: t('attribution.toggle'),
          onclick: () => {
            this.attributionOpen = !this.attributionOpen;
            this.renderAttribution();
          },
        },
        '©',
      ),
      h(
        'div',
        { class: `attribution__text${this.attributionOpen ? ' attribution__text--open' : ''}` },
        text.join(' | '),
        ' ',
        h('button', { type: 'button', class: 'link', onclick: () => this.app.openPanel('sources') }, t('attribution.more')),
      ),
    );
  }

  // -- messages -------------------------------------------------------------

  /** Bandeau affiché tant que des tuiles de couverture n'ont pas pu être lues : elles sont hachurées en gris. */
  private renderCoverageAlert(): void {
    const show = this.app.state.coverageErrors > 0;
    this.coverageAlert.hidden = !show;
    setChildren(
      this.coverageAlert,
      show
        ? [
            h('span', { class: 'swatch swatch--unavailable', 'aria-hidden': 'true' }),
            h('span', { class: 'coverage-alert__text' }, t('network.tilesUnavailable')),
            h('button', { type: 'button', class: 'btn', onclick: () => this.app.retryCoverage() }, t('action.retry')),
          ]
        : null,
    );
  }

  toast(message: string): void {
    this.toastEl.textContent = message;
    this.toastEl.hidden = false;
    clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => {
      this.toastEl.hidden = true;
    }, 4500);
  }

  /** Marges à laisser libres quand on cadre la carte : barres et panneau ouvert. */
  padding(): Padding {
    const padding: Padding = { top: 84, right: 56, bottom: 110, left: 40 };
    if (this.panel.hidden) return padding;
    const rect = this.panel.getBoundingClientRect();
    if (window.matchMedia(DESKTOP).matches) padding.left = Math.round(rect.right) + 32;
    else padding.bottom = Math.max(padding.bottom, Math.round(window.innerHeight - rect.top) + 24);
    return padding;
  }

  // -- recherche ------------------------------------------------------------

  private openSearch(): void {
    this.searchOpen = true;
    this.searchBox.hidden = false;
    this.renderTopbar();
    this.searchInput.focus();
    // Sur mobile, la recherche prend la place du panneau.
    if (!window.matchMedia(DESKTOP).matches && this.app.state.panel) this.app.closePanel();
  }

  private closeSearch(): void {
    // Le focus était dans la recherche : il revient à la loupe.
    const hadFocus = this.searchBox.contains(document.activeElement);
    this.searchOpen = false;
    this.searchBox.hidden = true;
    this.searchInput.value = '';
    this.searchAbort?.abort();
    clearTimeout(this.searchTimer);
    this.pickFirst = false;
    setChildren(this.searchResults);
    this.renderTopbar();
    if (hadFocus) this.searchButton.focus();
  }

  private onSearchInput(): void {
    clearTimeout(this.searchTimer);
    this.searchAbort?.abort();
    this.pickFirst = false;
    const query = this.searchInput.value.trim();
    if (query.length < SEARCH_MIN_CHARS) {
      setChildren(this.searchResults, query.length > 0 ? h('li', { class: 'search__info' }, t('search.hint', { count: SEARCH_MIN_CHARS })) : null);
      return;
    }
    this.searchTimer = setTimeout(() => void this.runSearch(query), SEARCH_DEBOUNCE_MS);
  }

  private async runSearch(query: string): Promise<void> {
    const seq = ++this.searchSeq;
    this.searchAbort = new AbortController();
    const center = this.app.mapView.map.getCenter();
    try {
      const places = await searchPlaces(query, {
        lang: getLanguage(),
        center: [center.lng, center.lat],
        bounds: MAX_BOUNDS,
        abroadFirst: this.app.centerIsAbroad(),
        signal: this.searchAbort.signal,
      });
      if (seq !== this.searchSeq || !this.searchOpen) return;
      this.resultsQuery = query;
      if (this.pickFirst && places.length > 0) {
        this.pickFirst = false;
        this.pickPlace(places[0]);
        return;
      }
      this.pickFirst = false;
      this.showResults(places);
    } catch (error) {
      if (seq !== this.searchSeq || (error instanceof Error && error.name === 'AbortError')) return;
      this.pickFirst = false;
      this.resultsQuery = null;
      setChildren(this.searchResults, h('li', { class: 'search__info' }, t('search.error')));
    }
  }

  private showResults(places: Place[]): void {
    if (places.length === 0) {
      setChildren(this.searchResults, h('li', { class: 'search__info' }, t('search.empty')));
      return;
    }
    setChildren(
      this.searchResults,
      places.map((place) =>
        h(
          'li',
          { role: 'presentation' },
          h(
            'button',
            { type: 'button', class: 'search__item', role: 'option', onclick: () => this.pickPlace(place) },
            h('span', { class: 'search__label' }, place.label),
            place.detail ? h('span', { class: 'search__detail' }, place.detail) : null,
            h('span', { class: 'search__source' }, place.source === 'ign' ? 'IGN' : 'OSM'),
          ),
        ),
      ),
      h('li', { class: 'search__credits' }, t('search.credits')),
    );
  }

  private pickPlace(place: Place): void {
    this.app.goTo(place);
    this.closeSearch();
  }

  private onSearchKey(event: KeyboardEvent): void {
    if (event.key === 'Enter') {
      event.preventDefault();
      const query = this.searchInput.value.trim();
      const first = this.searchResults.querySelector<HTMLButtonElement>('.search__item');
      // La liste affichée peut venir de la saisie précédente (« Bri » pour « Brides ») : on ne
      // la prend que si elle répond à la saisie actuelle ; sinon on cherche tout de suite et on
      // prendra le premier résultat à son arrivée.
      if (first && query === this.resultsQuery) first.click();
      else if (query.length >= SEARCH_MIN_CHARS) {
        clearTimeout(this.searchTimer);
        this.searchAbort?.abort();
        this.pickFirst = true;
        void this.runSearch(query);
      }
    } else if (event.key === 'ArrowDown') {
      event.preventDefault();
      this.searchResults.querySelector<HTMLButtonElement>('.search__item')?.focus();
    }
  }

  // -- glisser-déposer ------------------------------------------------------

  private bindDragAndDrop(): void {
    const hasFiles = (event: DragEvent): boolean => Array.from(event.dataTransfer?.types ?? []).includes('Files');
    window.addEventListener('dragenter', (event) => {
      if (!hasFiles(event)) return;
      event.preventDefault();
      this.dragDepth++;
      this.dropzone.hidden = false;
    });
    window.addEventListener('dragover', (event) => {
      if (!hasFiles(event)) return;
      event.preventDefault();
      if (event.dataTransfer) event.dataTransfer.dropEffect = 'copy';
    });
    window.addEventListener('dragleave', (event) => {
      if (!hasFiles(event)) return;
      this.dragDepth = Math.max(0, this.dragDepth - 1);
      if (this.dragDepth === 0) this.dropzone.hidden = true;
    });
    window.addEventListener('drop', (event) => {
      if (!hasFiles(event)) return;
      event.preventDefault();
      this.dragDepth = 0;
      this.dropzone.hidden = true;
      const file = event.dataTransfer?.files?.[0];
      if (file) void this.app.importGpx(file);
    });
  }
}
