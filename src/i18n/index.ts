// Traductions de l'interface.
//
// Un fichier JSON par langue dans ./locales/. Pour ajouter une langue (l'anglais
// par exemple), il suffit de déposer un fichier en.json avec les mêmes clés que
// fr.json et un bloc "_meta" : elle apparaît toute seule dans les paramètres.
// Si une clé manque dans une langue, on retombe sur le français.

export interface LocaleMeta {
  /** Nom de la langue, écrit dans cette langue (par exemple « Deutsch »). */
  name: string;
  /** Balise BCP 47 utilisée pour formater les nombres (par exemple « de-DE »). */
  locale: string;
}

type LocaleFile = { _meta: LocaleMeta } & Record<string, unknown>;

export const DEFAULT_LANG = 'fr';
const STORAGE_KEY = 'czb.lang';
/** Ordre d'affichage. Les langues absentes de cette liste viennent ensuite, par ordre alphabétique. */
const PREFERRED_ORDER = ['fr', 'es', 'ca', 'it', 'de', 'en'];

const files = import.meta.glob<LocaleFile>('./locales/*.json', { eager: true, import: 'default' });

const dictionaries = new Map<string, Record<string, string>>();
const metas = new Map<string, LocaleMeta>();

for (const [path, file] of Object.entries(files)) {
  const code = /\/([A-Za-z-]+)\.json$/.exec(path)?.[1];
  if (!code || !file || typeof file !== 'object') continue;
  const { _meta, ...rest } = file;
  if (!_meta || typeof _meta.name !== 'string' || typeof _meta.locale !== 'string') continue;
  const dict: Record<string, string> = {};
  for (const [key, value] of Object.entries(rest)) {
    if (typeof value === 'string') dict[key] = value;
  }
  dictionaries.set(code, dict);
  metas.set(code, _meta);
}

function rank(code: string): number {
  const i = PREFERRED_ORDER.indexOf(code);
  return i === -1 ? PREFERRED_ORDER.length : i;
}

/** Langues disponibles, dans l'ordre d'affichage. */
export function availableLanguages(): { code: string; name: string; locale: string }[] {
  return [...metas.entries()]
    .map(([code, meta]) => ({ code, name: meta.name, locale: meta.locale }))
    .sort((a, b) => rank(a.code) - rank(b.code) || a.code.localeCompare(b.code));
}

export function isSupported(code: string | null | undefined): code is string {
  return !!code && dictionaries.has(code);
}

let current = DEFAULT_LANG;
const listeners = new Set<(lang: string) => void>();

function readStored(): string | null {
  try {
    return globalThis.localStorage?.getItem(STORAGE_KEY) ?? null;
  } catch {
    return null; // stockage bloqué (navigation privée, réglages du navigateur)
  }
}

function writeStored(code: string): void {
  try {
    globalThis.localStorage?.setItem(STORAGE_KEY, code);
  } catch {
    // tant pis : la langue ne sera pas mémorisée
  }
}

/** Langue demandée par le paramètre d'URL ?lang=xx, s'il est valide. */
export function langFromUrl(search: string): string | null {
  try {
    const value = new URLSearchParams(search).get('lang')?.toLowerCase().trim();
    return isSupported(value) ? value : null;
  } catch {
    return null;
  }
}

/**
 * Choisit la langue au démarrage : le paramètre d'URL l'emporte, puis le choix
 * mémorisé, puis le français.
 */
export function initLanguage(search: string = globalThis.location?.search ?? ''): string {
  const fromUrl = langFromUrl(search);
  const stored = readStored();
  current = fromUrl ?? (isSupported(stored) ? stored : DEFAULT_LANG);
  applyDocumentLang();
  return current;
}

function applyDocumentLang(): void {
  const doc = globalThis.document;
  if (doc?.documentElement) doc.documentElement.lang = current;
}

/** Change la langue, la mémorise et prévient l'interface. */
export function setLanguage(code: string): void {
  if (!isSupported(code) || code === current) return;
  current = code;
  writeStored(code);
  applyDocumentLang();
  // Si l'URL force une langue, on la met à jour pour qu'un rechargement garde le nouveau choix.
  try {
    const loc = globalThis.location;
    if (loc && new URLSearchParams(loc.search).has('lang')) {
      const url = new URL(loc.href);
      url.searchParams.set('lang', code);
      globalThis.history?.replaceState(globalThis.history.state, '', url);
    }
  } catch {
    // sans importance
  }
  for (const fn of listeners) fn(code);
}

export function getLanguage(): string {
  return current;
}

export function getLocale(): string {
  return metas.get(current)?.locale ?? 'fr-FR';
}

export function onLanguageChange(fn: (lang: string) => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export type Params = Record<string, string | number>;

function lookup(key: string): string | undefined {
  return dictionaries.get(current)?.[key] ?? dictionaries.get(DEFAULT_LANG)?.[key];
}

/**
 * Traduit une clé. Les paramètres remplacent les {noms} entre accolades.
 * Avec un paramètre « count », on cherche d'abord la forme plurielle de la
 * langue (clé suffixée par _one, _other, etc.).
 */
export function t(key: string, params?: Params): string {
  const text = template(key, params);
  if (!params) return text;
  return text.replace(/\{(\w+)\}/g, (match, name: string) =>
    name in params ? String(params[name]) : match,
  );
}

/** Texte de la clé, avant remplacement des paramètres (forme plurielle choisie selon « count »). */
function template(key: string, params?: Record<string, unknown>): string {
  let text: string | undefined;
  if (params && typeof params.count === 'number') {
    let category = 'other';
    try {
      category = new Intl.PluralRules(getLocale()).select(params.count);
    } catch {
      // on garde « other »
    }
    text = lookup(`${key}_${category}`) ?? lookup(`${key}_other`);
  }
  text ??= lookup(key);
  return text ?? key;
}

/**
 * Comme t(), mais les paramètres peuvent être autre chose que du texte (des liens,
 * par exemple) : renvoie les morceaux du texte traduit, dans l'ordre, avec les
 * valeurs des paramètres à leur place. La ponctuation reste celle de la langue.
 */
export function tParts<T>(key: string, params: Record<string, T | string | number>): (T | string)[] {
  const parts: (T | string)[] = [];
  let last = 0;
  const text = template(key, params);
  for (const match of text.matchAll(/\{(\w+)\}/g)) {
    if (!(match[1] in params)) continue;
    if (match.index > last) parts.push(text.slice(last, match.index));
    const value = params[match[1]];
    parts.push(typeof value === 'number' ? String(value) : value);
    last = match.index + match[0].length;
  }
  if (last < text.length) parts.push(text.slice(last));
  return parts;
}

/** Vrai si la clé existe dans la langue courante ou en français. */
export function hasKey(key: string): boolean {
  return lookup(key) !== undefined;
}

// ---------------------------------------------------------------------------
// Nombres et distances
// ---------------------------------------------------------------------------

const formatters = new Map<string, Intl.NumberFormat>();

function numberFormat(digits: number, style: 'decimal' | 'percent' = 'decimal'): Intl.NumberFormat {
  const id = `${getLocale()}|${digits}|${style}`;
  let nf = formatters.get(id);
  if (!nf) {
    nf = new Intl.NumberFormat(getLocale(), {
      style,
      minimumFractionDigits: digits,
      maximumFractionDigits: digits,
    });
    formatters.set(id, nf);
  }
  return nf;
}

export function formatNumber(value: number, digits = 0): string {
  return numberFormat(digits).format(value);
}

/** Distance en kilomètres avec une décimale, sans l'unité : « 12,4 ». */
export function formatKm(meters: number, digits = 1): string {
  return formatNumber(meters / 1000, digits);
}

/** Distance lisible : en mètres sous 1 km, en kilomètres au-delà. */
export function formatDistance(meters: number): string {
  if (Math.abs(meters) < 1000) return `${formatNumber(Math.round(meters))} m`;
  return `${formatKm(meters)} km`;
}

export function formatMeters(meters: number): string {
  return `${formatNumber(Math.round(meters))} m`;
}

/**
 * Pourcentage selon la langue (« 53 % », « 53% » en italien), avec une décimale
 * sous 10 %. La décimale se décide sur la valeur arrondie : 9,97 % s'écrit « 10 % ».
 */
export function formatPercent(ratio: number): string {
  const digits = ratio > 0 && Math.round(ratio * 1000) < 100 ? 1 : 0;
  return numberFormat(digits, 'percent').format(ratio);
}

/** Nom d'un pays dans la langue courante, à partir de son code ISO à deux lettres. */
export function countryName(iso: string): string {
  try {
    return new Intl.DisplayNames([getLocale()], { type: 'region' }).of(iso) ?? iso;
  } catch {
    return iso;
  }
}

/** Date lisible à partir d'une date ISO (AAAA-MM-JJ) ou d'un trimestre (AAAA-Tn). */
export function formatDataDate(value: string): string {
  const quarter = /^(\d{4})-T([1-4])$/.exec(value);
  if (quarter) return t('date.quarter', { quarter: quarter[2], year: quarter[1] });
  const month = /^(\d{4})-(\d{2})$/.exec(value);
  const day = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  try {
    if (day) {
      const d = new Date(Date.UTC(+day[1], +day[2] - 1, +day[3]));
      return new Intl.DateTimeFormat(getLocale(), { dateStyle: 'long', timeZone: 'UTC' }).format(d);
    }
    if (month) {
      const d = new Date(Date.UTC(+month[1], +month[2] - 1, 1));
      return new Intl.DateTimeFormat(getLocale(), { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(d);
    }
  } catch {
    // on renvoie la valeur brute
  }
  return value;
}

/** Réservé aux tests : accès direct aux dictionnaires. */
export function _dictionaries(): Map<string, Record<string, string>> {
  return dictionaries;
}
