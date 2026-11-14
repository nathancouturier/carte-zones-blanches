// Contenu des panneaux. Chaque fonction renvoie les éléments à afficher pour
// l'état courant : rien n'est gardé d'un affichage à l'autre.

import type { App } from '../app';
import { LEVEL_GOOD, LEVEL_LIMITED, LEVEL_NONE, LEVEL_VERY_GOOD, SOURCE_ESTIMATED } from '../coverage/codec';
import {
  ALL_OPERATORS,
  countryHasOperatorChoice,
  countryHasService,
  manifestHasService,
  selectableSlots,
  SERVICES,
  SOURCE_TYPE_KEYS,
  type ManifestCountry,
} from '../coverage/manifest';
import { LEVEL_SOLID } from '../coverage/render';
import { hasThresholdSlots, slotLabel } from '../coverage/slotLabel';
import type { CoverageStats } from '../gpx/analyze';
import { describeOperators, describeZone, LEVEL_KEYS } from '../gpx/report';
import { WHITE_ZONE_MIN_LENGTH_M } from '../config';
import {
  availableLanguages,
  countryName,
  formatDataDate,
  formatKm,
  formatNumber,
  formatPercent,
  getLanguage,
  t,
} from '../i18n';
import { BASEMAP_ORDER, BASEMAPS, HILLSHADE, type BasemapChoice } from '../map/basemaps';
import { OUTSIDE_COLOR } from '../map/style';
import { offlineSupported } from '../offline/manager';
import { h, icon, ICONS } from './dom';
import { elevationProfile } from './profile';

type Node_ = Node | string | null | false | undefined | Node_[];

const LEVELS = [LEVEL_NONE, LEVEL_LIMITED, LEVEL_GOOD, LEVEL_VERY_GOOD];
export const REPO_URL = 'https://github.com/nathancouturier/carte-zones-blanches';

/** Noms des opérateurs d'un pays : ceux des emplacements, ou la liste du pays si la source est agrégée. */
function operatorNames(country: ManifestCountry): string[] {
  const named = country.slots.map((slot) => slot.name).filter((name): name is string => !!name);
  return named.length > 0 ? named : (country.operators ?? []);
}

function capitalize(text: string): string {
  return text.charAt(0).toLocaleUpperCase(getLanguage()) + text.slice(1);
}

function section(title: string | null, ...children: Node_[]): HTMLElement {
  return h('section', { class: 'block' }, title ? h('h3', { class: 'block__title' }, title) : null, children as never);
}

function note(text: string, kind: 'info' | 'warning' = 'info'): HTMLElement {
  return h('p', { class: `note note--${kind}` }, icon(kind === 'warning' ? ICONS.warning : ICONS.info, 18), h('span', null, text));
}

// ---------------------------------------------------------------------------
// Réseau
// ---------------------------------------------------------------------------

function operatorChips(app: App, country: ManifestCountry): HTMLElement {
  const selected = app.state.network.operators[country.iso] ?? ALL_OPERATORS;
  const chip = (id: string, label: string): HTMLElement =>
    h(
      'button',
      {
        type: 'button',
        class: `chip${selected === id ? ' chip--on' : ''}`,
        'aria-pressed': String(selected === id),
        dataset: { focus: `op-${country.iso}-${id}` },
        onclick: () => app.setOperator(country.iso, id),
      },
      label,
    );
  return h(
    'div',
    { class: 'chips', role: 'group', 'aria-label': t('network.operator') },
    chip(ALL_OPERATORS, t('network.allOperators')),
    selectableSlots(country).map((slot) => chip(slot.id, slotLabel(slot, country))),
  );
}

function operatorSelect(app: App, country: ManifestCountry): HTMLElement {
  const selected = app.state.network.operators[country.iso] ?? ALL_OPERATORS;
  const id = `operateur-${country.iso}`;
  const control = countryHasOperatorChoice(country)
    ? h(
        'select',
        {
          id,
          class: 'select',
          dataset: { focus: id },
          onchange: (event: Event) => app.setOperator(country.iso, (event.target as HTMLSelectElement).value),
        },
        h('option', { value: ALL_OPERATORS, selected: selected === ALL_OPERATORS }, t('network.allOperatorsCountry')),
        selectableSlots(country).map((slot) => h('option', { value: slot.id, selected: selected === slot.id }, slotLabel(slot, country))),
      )
    : // Un seul opérateur dans le pays : on le nomme. Sinon la source ne détaille pas.
      h('span', { class: 'muted' }, country.slots.length === 1 && country.slots[0].name ? country.slots[0].name : t('network.aggregatedOnly'));
  return h(
    'div',
    { class: 'country-choice' },
    h('div', { class: 'field field--row' }, h('label', { for: id, class: 'field__label' }, countryName(country.iso)), control),
    hasThresholdSlots(country) && country.operators
      ? h('p', { class: 'hint' }, t('network.thresholdHint', { count: country.operators.length }), ' ', t('sources.operators', { operators: country.operators.join(', ') }))
      : null,
  );
}

function legend(app: App): HTMLElement {
  const { network, manifest } = app.state;
  const levels = network.showAll ? LEVELS : [LEVEL_NONE, LEVEL_LIMITED];
  const hasEstimated = manifest?.countries.some((c) => c.sources.some((s) => s.type === SOURCE_ESTIMATED)) ?? false;
  return h(
    'ul',
    { class: 'legend' },
    levels.map((level) =>
      h('li', null, h('span', { class: 'swatch', style: { background: LEVEL_SOLID[level] } }), t(LEVEL_KEYS[level])),
    ),
    hasEstimated ? h('li', null, h('span', { class: 'swatch swatch--hatch' }), t('legend.estimated')) : null,
  );
}

export function networkPanel(app: App): Node_[] {
  const { manifest, dataStatus, network } = app.state;
  if (dataStatus === 'loading') return [h('p', { class: 'muted' }, t('network.loading'))];
  if (!manifest) return [note(t('network.noData'), 'warning')];

  const parts: Node_[] = [];
  const services = SERVICES.filter((s) => manifestHasService(manifest, s));
  if (services.length > 1) {
    parts.push(
      section(
        t('network.service'),
        h(
          'div',
          { class: 'chips', role: 'group', 'aria-label': t('network.service') },
          services.map((service) =>
            h(
              'button',
              {
                type: 'button',
                class: `chip${network.service === service ? ' chip--on' : ''}`,
                'aria-pressed': String(network.service === service),
                dataset: { focus: `service-${service}` },
                onclick: () => app.setService(service),
              },
              t(`service.${service}`),
            ),
          ),
        ),
      ),
    );
    const missing = manifest.countries.filter((c) => !countryHasService(c, network.service));
    if (missing.length > 0) {
      parts.push(
        note(t('network.serviceMissing', { service: t(`service.${network.service}`), countries: missing.map((c) => countryName(c.iso)).join(', ') })),
      );
    }
  }

  // Le premier pays du manifest est le pays principal ; les autres sont rangés sous « À l'étranger ».
  const [home, ...abroad] = manifest.countries;
  const multiCountry = abroad.length > 0;
  parts.push(
    section(
      multiCountry ? t('network.operatorIn', { country: countryName(home.iso) }) : t('network.operator'),
      countryHasOperatorChoice(home) ? operatorChips(app, home) : h('p', { class: 'muted' }, t('network.aggregatedOnly')),
      h('p', { class: 'hint' }, t('network.allHint')),
    ),
  );
  if (multiCountry) {
    parts.push(
      h(
        'details',
        { class: 'block details', open: abroad.some((c) => network.operators[c.iso]) },
        h('summary', { dataset: { focus: 'abroad' } }, t('network.abroad')),
        h('p', { class: 'hint' }, t('network.abroadHint')),
        abroad.map((country) => operatorSelect(app, country)),
      ),
    );
  }

  const opacityId = 'opacite';
  parts.push(
    section(
      t('network.display'),
      h(
        'label',
        { class: 'check' },
        h('input', {
          type: 'checkbox',
          checked: network.showAll,
          dataset: { focus: 'show-all' },
          onchange: (event: Event) => app.setShowAll((event.target as HTMLInputElement).checked),
        }),
        h('span', null, t('network.showAll'), h('small', null, t('network.showAllHint'))),
      ),
      h(
        'div',
        { class: 'field' },
        h('label', { for: opacityId, class: 'field__label' }, t('network.opacity')),
        h('input', {
          id: opacityId,
          type: 'range',
          min: '10',
          max: '100',
          step: '5',
          value: String(Math.round(network.opacity * 100)),
          dataset: { focus: opacityId },
          oninput: (event: Event) => app.setOpacity(Number((event.target as HTMLInputElement).value) / 100, false),
          onchange: (event: Event) => app.setOpacity(Number((event.target as HTMLInputElement).value) / 100, true),
        }),
      ),
    ),
  );
  parts.push(section(t('network.legend'), legend(app)));
  parts.push(
    h('p', { class: 'disclaimer' }, t('sources.disclaimer')),
    h('button', { type: 'button', class: 'link', dataset: { focus: 'to-sources' }, onclick: () => app.openPanel('sources') }, t('network.sourcesLink')),
  );
  return parts;
}

// ---------------------------------------------------------------------------
// Fond
// ---------------------------------------------------------------------------

export function basemapPanel(app: App): Node_[] {
  const { basemap, activeBasemap } = app.state;
  const option = (value: BasemapChoice, label: string, hint?: string): HTMLElement =>
    h(
      'label',
      { class: `radio${basemap.choice === value ? ' radio--on' : ''}` },
      h('input', {
        type: 'radio',
        name: 'fond',
        value,
        checked: basemap.choice === value,
        dataset: { focus: `fond-${value}` },
        onchange: () => app.setBasemapChoice(value),
      }),
      h('span', null, label, hint ? h('small', null, hint) : null),
    );
  return [
    section(
      null,
      h(
        'div',
        { class: 'radios', role: 'radiogroup', 'aria-label': t('basemap.title') },
        option('auto', t('basemap.auto'), `${t('basemap.autoHint')} ${t('basemap.current', { name: t(BASEMAPS[activeBasemap].labelKey) })}`),
        BASEMAP_ORDER.map((id) => option(id, t(BASEMAPS[id].labelKey))),
      ),
    ),
    section(
      t('basemap.options'),
      h(
        'label',
        { class: 'check' },
        h('input', {
          type: 'checkbox',
          checked: basemap.hillshade,
          dataset: { focus: 'estompage' },
          onchange: (event: Event) => app.setHillshade((event.target as HTMLInputElement).checked),
        }),
        h('span', null, t('basemap.hillshade'), h('small', null, t('basemap.hillshadeHint'))),
      ),
    ),
  ];
}

// ---------------------------------------------------------------------------
// GPX
// ---------------------------------------------------------------------------

export function gpxPanel(app: App, chooseFile: () => void): Node_[] {
  const { track, trackStatus, trackError, progress, dataStatus } = app.state;
  const parts: Node_[] = [];
  if (trackError) parts.push(note(t(trackError.key, trackError.params), 'warning'));
  if (trackStatus === 'reading') parts.push(h('p', { class: 'muted', role: 'status' }, t('gpx.reading')));

  if (track) {
    const name = track.parsed.name ?? track.fileName;
    parts.push(
      section(
        t('gpx.loaded'),
        h('p', { class: 'track-name' }, name),
        h('p', { class: 'muted' }, t('gpx.summary', { km: formatKm(track.length), points: formatNumber(track.parsed.pointCount) })),
        trackStatus === 'analyzing'
          ? h(
              'div',
              { class: 'progress', role: 'status' },
              h('span', null, t('gpx.analyzing')),
              h('progress', { max: '1', value: String(progress), dataset: { role: 'progress' } }),
            )
          : null,
        trackStatus === 'ready' && !track.analysis && dataStatus === 'ready'
          ? h('button', { type: 'button', class: 'btn', onclick: () => void app.retryAnalysis() }, t('gpx.retry'))
          : null,
        trackStatus === 'ready' && !track.analysis && dataStatus === 'missing' ? note(t('gpx.noCoverageData'), 'warning') : null,
        h(
          'div',
          { class: 'actions' },
          track.report
            ? h('button', { type: 'button', class: 'btn btn--primary', dataset: { focus: 'voir-rapport' }, onclick: () => app.openPanel('report') }, icon(ICONS.report, 20), t('gpx.showReport'))
            : null,
          h('button', { type: 'button', class: 'btn', dataset: { focus: 'recadrer' }, onclick: () => app.fitTrack() }, t('gpx.fit')),
        ),
      ),
    );
  } else {
    parts.push(h('p', null, t('gpx.intro')));
    // Un tracé a été préparé pour le hors ligne : on propose de le reprendre.
    const stored = app.state.offline.info;
    if (stored) {
      parts.push(
        h(
          'div',
          { class: 'actions' },
          h('button', { type: 'button', class: 'btn', dataset: { focus: 'reprendre' }, onclick: () => void app.restoreOfflineTrack() }, icon(ICONS.report, 20), t('offline.resume', { name: stored.name })),
        ),
      );
    }
  }

  parts.push(
    h(
      'div',
      { class: 'actions' },
      h(
        'button',
        { type: 'button', class: `btn${track ? '' : ' btn--primary'}`, dataset: { focus: 'choisir-gpx' }, onclick: chooseFile },
        icon(ICONS.upload, 20),
        track ? t('gpx.replace') : t('gpx.choose'),
      ),
      track
        ? h('button', { type: 'button', class: 'btn btn--danger', dataset: { focus: 'retirer-gpx' }, onclick: () => app.removeTrack() }, icon(ICONS.trash, 20), t('gpx.remove'))
        : null,
    ),
    h('p', { class: 'hint hint--desktop' }, t('gpx.drop')),
    h('p', { class: 'hint' }, t('gpx.privacy')),
  );
  return parts;
}

// ---------------------------------------------------------------------------
// Rapport
// ---------------------------------------------------------------------------

function statsBlock(title: string, stats: CoverageStats): HTMLElement {
  const total = stats.measured;
  return h(
    'div',
    { class: 'stats' },
    h('h4', { class: 'stats__title' }, title),
    h(
      'div',
      { class: 'bar', role: 'img', 'aria-label': title },
      total > 0
        ? LEVELS.map((level) =>
            stats.byLevel[level] > 0
              ? h('span', { class: 'bar__part', style: { width: `${(stats.byLevel[level] / total) * 100}%`, background: LEVEL_SOLID[level] } })
              : null,
          )
        : h('span', { class: 'bar__part', style: { width: '100%', background: OUTSIDE_COLOR } }),
    ),
    h(
      'table',
      { class: 'stats__table' },
      h(
        'tbody',
        null,
        LEVELS.map((level) =>
          h(
            'tr',
            null,
            h('th', { scope: 'row' }, h('span', { class: 'swatch', style: { background: LEVEL_SOLID[level] } }), t(LEVEL_KEYS[level])),
            h('td', null, total > 0 ? formatPercent(stats.byLevel[level] / total) : ''),
            h('td', null, `${formatKm(stats.byLevel[level])} km`),
          ),
        ),
      ),
    ),
  );
}

export function reportPanel(app: App, chooseFile: () => void): Node_[] {
  const { track, trackStatus, manifest, network, selectedZone, progress } = app.state;
  if (!track) {
    return [
      h('p', null, t('report.empty')),
      h('button', { type: 'button', class: 'btn btn--primary', onclick: chooseFile }, icon(ICONS.upload, 20), t('gpx.choose')),
    ];
  }
  const parts: Node_[] = [];
  const name = track.parsed.name ?? track.fileName;
  const gain = track.analysis?.gain ?? null;
  const report = track.report;
  const settings = { service: network.service, operators: network.operators };

  parts.push(
    h(
      'div',
      { class: 'report-head' },
      h('p', { class: 'track-name' }, name),
      h(
        'dl',
        { class: 'facts' },
        h('div', null, h('dt', null, t('report.distance')), h('dd', null, `${formatKm(track.length)} km`)),
        gain
          ? h(
              'div',
              null,
              h('dt', null, t('report.elevation')),
              h('dd', null, t('report.elevationValue', { up: formatNumber(Math.round(gain.ascent)), down: formatNumber(Math.round(gain.descent)) })),
            )
          : null,
        gain
          ? h(
              'div',
              null,
              h('dt', null, t('report.altitude')),
              h('dd', null, t('report.altitudeValue', { min: formatNumber(Math.round(gain.min)), max: formatNumber(Math.round(gain.max)) })),
            )
          : null,
        report && report.countries.length > 0
          ? h('div', null, h('dt', null, t('report.countries')), h('dd', null, report.countries.map((c) => countryName(c.iso)).join(', ')))
          : null,
        report && report.countries.length > 0
          ? h(
              'div',
              null,
              h('dt', null, t('report.operator')),
              h(
                'dd',
                null,
                `${capitalize(describeOperators(report, settings))} `,
                h('button', { type: 'button', class: 'link', dataset: { focus: 'changer-operateur' }, onclick: () => app.openPanel('network') }, t('report.change')),
              ),
            )
          : null,
      ),
    ),
  );

  if (trackStatus === 'analyzing') {
    parts.push(
      h('div', { class: 'progress', role: 'status' }, h('span', null, t('gpx.analyzing')), h('progress', { max: '1', value: String(progress), dataset: { role: 'progress' } })),
    );
    return parts;
  }
  if (!report || !manifest || !track.analysis) {
    parts.push(note(t(app.state.dataStatus === 'missing' ? 'gpx.noCoverageData' : 'gpx.error.analysis'), 'warning'));
    if (app.state.dataStatus === 'ready') {
      parts.push(h('button', { type: 'button', class: 'btn', onclick: () => void app.retryAnalysis() }, t('gpx.retry')));
    }
    return parts;
  }

  for (const country of report.nonEuCountries) {
    parts.push(note(t('report.roamingWarning', { country: countryName(country.iso) }), 'warning'));
  }
  if (report.missingService.length > 0) {
    parts.push(
      note(t('network.serviceMissing', { service: t(`service.${network.service}`), countries: report.missingService.map((c) => countryName(c.iso)).join(', ') })),
    );
  }
  if (report.estimated) parts.push(note(t('report.estimatedWarning')));

  if (report.stats.measured > 0 || report.statsAll.measured > 0) {
    parts.push(
      section(
        t('report.share'),
        report.specificOperator ? statsBlock(t('report.selectedHeader'), report.stats) : null,
        statsBlock(t('report.allHeader'), report.statsAll),
        report.stats.outside > 0 ? h('p', { class: 'hint' }, t('report.outsideLine', { km: formatKm(report.stats.outside) })) : null,
        report.stats.unknown > 0 ? h('p', { class: 'hint' }, t('report.unknownLine', { km: formatKm(report.stats.unknown) })) : null,
      ),
    );
  } else {
    parts.push(note(t('report.noData'), 'warning'));
  }

  // Profil altimétrique coloré selon la couverture (seulement si le GPX a des altitudes).
  const profile = elevationProfile({
    samples: track.samples,
    classes: report.classes,
    onHover: (index) => app.showTrackCursor(index),
  });
  if (profile) parts.push(section(t('report.profile'), profile));

  parts.push(
    section(
      t('report.zonesHeading', { count: report.zones.length }),
      report.zones.length === 0
        ? h('p', { class: 'muted' }, t('report.noZones', { min: formatNumber(WHITE_ZONE_MIN_LENGTH_M) }))
        : [
            h('p', { class: 'hint' }, t('report.zonesHint')),
            h(
              'ol',
              { class: 'zones' },
              report.zones.map((zone) =>
                h(
                  'li',
                  null,
                  h(
                    'button',
                    {
                      type: 'button',
                      class: `zone${selectedZone === zone.index ? ' zone--on' : ''}`,
                      'aria-pressed': String(selectedZone === zone.index),
                      dataset: { focus: `zone-${zone.index}` },
                      onclick: () => app.selectZone(selectedZone === zone.index ? null : zone.index),
                    },
                    h('span', { class: 'zone__num' }, String(zone.index)),
                    h('span', { class: 'zone__text' }, describeZone(zone, manifest)),
                    icon(ICONS.chevron, 18),
                  ),
                ),
              ),
            ),
          ],
    ),
  );

  const text = app.reportAsText() ?? '';
  parts.push(
    section(
      t('report.exportHeading'),
      h(
        'div',
        { class: 'actions' },
        h('button', { type: 'button', class: 'btn btn--primary', dataset: { focus: 'gpx-enrichi' }, onclick: () => app.downloadEnrichedGpx() }, icon(ICONS.download, 20), t('report.download')),
        h('button', { type: 'button', class: 'btn', dataset: { focus: 'copier' }, onclick: () => void app.copyReport() }, icon(ICONS.copy, 20), t('report.copy')),
      ),
      h('p', { class: 'hint' }, t('report.downloadHint')),
      h(
        'details',
        { class: 'details' },
        h('summary', { dataset: { focus: 'texte' } }, t('report.textTitle')),
        h('textarea', { class: 'report-text', readonly: true, rows: '12', 'aria-label': t('report.textTitle'), onfocus: (event: Event) => (event.target as HTMLTextAreaElement).select() }, text),
      ),
    ),
    offlineSection(app),
    h('p', { class: 'disclaimer' }, t('sources.disclaimer')),
  );
  return parts;
}

/** Mode hors ligne : enregistrer le tracé, sa couverture et le fond affiché dans le navigateur. */
function offlineSection(app: App): Node_ {
  const { offline, activeBasemap, track } = app.state;
  if (!track?.analysis) return null;
  if (!offlineSupported()) return section(t('offline.heading'), h('p', { class: 'muted' }, t('offline.unsupported')));
  const basemap = BASEMAPS[activeBasemap];
  const parts: Node_[] = [h('p', { class: 'hint hint--first' }, t('offline.intro'))];
  if (!basemap.offline.allowed) parts.push(note(t('offline.basemapNotAllowed', { name: t(basemap.labelKey) })));
  if (offline.status === 'preparing') {
    parts.push(
      h('div', { class: 'progress', role: 'status' }, h('span', null, t('offline.preparing')), h('progress', { max: '1', value: String(offline.progress), dataset: { role: 'offline-progress' } })),
    );
  } else {
    if (offline.status === 'error') parts.push(note(t('offline.error'), 'warning'));
    const info = offline.info;
    if (info) {
      parts.push(
        h(
          'p',
          { class: 'offline-ready' },
          info.basemapTiles > 0
            ? t('offline.ready', { name: info.name, coverage: formatNumber(info.coverageTiles), basemap: formatNumber(info.basemapTiles) })
            : t('offline.readyNoBasemap', { name: info.name, coverage: formatNumber(info.coverageTiles) }),
        ),
      );
      if (info.failed > 0) parts.push(note(t('offline.failed', { count: info.failed }), 'warning'));
    }
    parts.push(
      h(
        'div',
        { class: 'actions' },
        h(
          'button',
          { type: 'button', class: 'btn', dataset: { focus: 'hors-ligne' }, onclick: () => void app.prepareOffline() },
          icon(ICONS.download, 20),
          info ? t('offline.update') : t('offline.prepare'),
        ),
        info
          ? h('button', { type: 'button', class: 'btn btn--danger', dataset: { focus: 'hors-ligne-effacer' }, onclick: () => void app.clearOfflineData() }, icon(ICONS.trash, 20), t('offline.clear'))
          : null,
      ),
    );
  }
  return section(t('offline.heading'), parts);
}

// ---------------------------------------------------------------------------
// Paramètres et sources
// ---------------------------------------------------------------------------

export function settingsPanel(app: App): Node_[] {
  const id = 'langue';
  return [
    section(
      null,
      h(
        'div',
        { class: 'field' },
        h('label', { for: id, class: 'field__label' }, t('settings.language')),
        h(
          'select',
          {
            id,
            class: 'select',
            dataset: { focus: id },
            onchange: (event: Event) => app.changeLanguage((event.target as HTMLSelectElement).value),
          },
          availableLanguages().map((lang) => h('option', { value: lang.code, selected: lang.code === getLanguage(), lang: lang.code }, lang.name)),
        ),
      ),
    ),
    section(
      null,
      h('button', { type: 'button', class: 'btn btn--wide', dataset: { focus: 'sources' }, onclick: () => app.openPanel('sources') }, icon(ICONS.info, 20), t('settings.sources')),
    ),
    section(
      t('settings.about'),
      h('p', null, t('settings.aboutText')),
      h('p', null, h('a', { href: REPO_URL, target: '_blank', rel: 'noopener noreferrer' }, t('settings.code'))),
    ),
  ];
}

function externalLink(label: string, url?: string): Node_ {
  return url ? h('a', { href: url, target: '_blank', rel: 'noopener noreferrer' }, label) : label;
}

export function sourcesPanel(app: App): Node_[] {
  const { manifest, dataStatus } = app.state;
  const parts: Node_[] = [h('p', { class: 'disclaimer disclaimer--strong' }, t('sources.disclaimer')), h('p', null, t('sources.limits'))];

  if (manifest) {
    for (const country of manifest.countries) {
      parts.push(
        section(
          t('sources.coverageIn', { country: countryName(country.iso) }),
          country.sources.map((source) =>
            h(
              'dl',
              { class: 'facts facts--stacked' },
              h('div', null, h('dt', null, t('sources.source')), h('dd', null, externalLink(source.name, source.url))),
              h('div', null, h('dt', null, t('sources.date')), h('dd', null, formatDataDate(source.date))),
              h(
                'div',
                null,
                h('dt', null, t('sources.method')),
                h(
                  'dd',
                  null,
                  t(`sources.method.${SOURCE_TYPE_KEYS[source.type] ?? 'estimated'}`),
                  h('br'),
                  h('small', null, t(`sources.levels.${source.levels}`)),
                  source.technology
                    ? [
                        h('br'),
                        h(
                          'small',
                          null,
                          source.services
                            .filter((s) => source.technology?.[s])
                            .map((s) => t('sources.technology', { service: t(`service.${s}`), techno: source.technology?.[s] ?? '' }))
                            .join(' ; '),
                        ),
                      ]
                    : null,
                ),
              ),
              h('div', null, h('dt', null, t('sources.licence')), h('dd', null, externalLink(source.licence, source.licenceUrl))),
            ),
          ),
          operatorNames(country).length > 0 ? h('p', { class: 'hint' }, t('sources.operators', { operators: operatorNames(country).join(', ') })) : null,
          country.euRoaming ? null : h('p', { class: 'hint' }, t('report.roamingWarning', { country: countryName(country.iso) })),
        ),
      );
    }
    parts.push(h('p', { class: 'hint' }, t('sources.generated', { date: formatDataDate(manifest.generated) })));
  } else if (dataStatus === 'missing') {
    parts.push(note(t('network.noData'), 'warning'));
  }

  const basemapItems = BASEMAP_ORDER.map((id) => BASEMAPS[id]).map((b) => h('li', null, `${t(b.labelKey)} : ${b.attribution}`));
  parts.push(
    section(
      t('sources.basemaps'),
      h('ul', { class: 'plain' }, basemapItems, h('li', null, `${t('basemap.hillshade')} : ${HILLSHADE.attribution}`)),
    ),
    section(t('sources.search'), h('ul', { class: 'plain' }, h('li', null, t('sources.searchIgn')), h('li', null, t('sources.searchOsm')))),
    h('p', null, h('a', { href: `${REPO_URL}/blob/main/docs/sources.md`, target: '_blank', rel: 'noopener noreferrer' }, t('sources.details'))),
  );
  return parts;
}
