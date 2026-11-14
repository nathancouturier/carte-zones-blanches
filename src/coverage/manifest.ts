// Lecture du manifest.json publié avec les tuiles de couverture.
//
// Le manifest décrit, pour chaque pays, ce que contient chaque emplacement
// d'opérateur, comment lire les niveaux, et d'où viennent les données. Le
// décodeur est entièrement piloté par ce fichier.

import {
  LEVEL_UNKNOWN,
  SLOT_COUNT,
  SOURCE_ESTIMATED,
  SOURCE_OFFICIAL_AGGREGATED,
  SOURCE_OFFICIAL_OPERATOR,
  unpackSlot,
} from './codec';

export type ServiceId = 'data' | 'voice';
export const SERVICES: readonly ServiceId[] = ['data', 'voice'];

/**
 * Façon de lire les niveaux d'une source :
 * - four : pas de couverture, limitée, bonne, très bonne ;
 * - three : pas de couverture, limitée, bonne ;
 * - binary : couvert ou non couvert.
 */
export type LevelsKind = 'four' | 'three' | 'binary';

export interface ManifestSlot {
  /** Identifiant stable de l'emplacement (par exemple « orange »). */
  id: string;
  /** Nom de l'opérateur (nom propre, non traduit). Absent pour un emplacement à seuil. */
  name?: string;
  /**
   * Emplacement à seuil d'une source agrégée : il vaut « couvert » là où au moins
   * ce nombre d'opérateurs couvrent, sans qu'on sache lesquels.
   */
  minOperators?: number;
}

export interface ManifestSource {
  /** Valeur des bits 4 et 5 du canal B pour les pixels issus de cette source. */
  type: number;
  /** Identifiant du module du pipeline (par exemple « fr_arcep »). */
  id: string;
  /** Nom de la source, tel qu'il doit être cité. */
  name: string;
  url?: string;
  /** Date des données : AAAA-Tn (trimestre), AAAA-MM ou AAAA-MM-JJ. */
  date: string;
  licence: string;
  licenceUrl?: string;
  /** Mention que la licence demande d'afficher telle quelle (non traduite). */
  licenceNotice?: string;
  /** Logo que la licence demande d'afficher : chemin d'un fichier du site, relatif à sa racine. */
  licenceLogo?: string;
  /** Mention courte pour le pied de carte. */
  attribution: string;
  /** Services fournis par cette source. */
  services: ServiceId[];
  levels: LevelsKind;
  /** Correspondance valeur brute (0 à 3) vers niveau (0 à 3). Identité par défaut. */
  levelMap?: number[];
  /**
   * Vrai si les emplacements se lisent un par un : un opérateur par emplacement,
   * ou un seuil par emplacement pour une source agrégée. Sinon la valeur
   * (tous opérateurs confondus) est rangée dans l'emplacement 0.
   */
  perOperator: boolean;
  /** Technologies prises en compte, par service (par exemple « 4G »). */
  technology?: Partial<Record<ServiceId, string>>;
  /** Résolution approximative de la source, en mètres. */
  resolutionM?: number;
}

export interface ManifestCountry {
  /** Code du pays dans les bits 0 à 3 du canal B (1 à 15). */
  code: number;
  /** Code ISO 3166-1 à deux lettres. */
  iso: string;
  /** Faux si le pays est hors de l'itinérance « comme à la maison » de l'UE. */
  euRoaming: boolean;
  /** Opérateurs (ou seuils) rangés dans les emplacements 0 à 3. */
  slots: ManifestSlot[];
  /** Noms des opérateurs du pays, quand la source ne les distingue pas. */
  operators?: string[];
  sources: ManifestSource[];
}

export interface ManifestArchive {
  file: string;
  minzoom: number;
  maxzoom: number;
  /**
   * Blocs contenus dans l'archive, sous la forme « x/y » au zoom tiles.blockZoom.
   * Absent : l'archive contient toutes les tuiles de ses zooms.
   */
  blocks?: string[];
  bytes?: number;
}

export interface Manifest {
  version: number;
  /** Date de génération (AAAA-MM-JJ). */
  generated: string;
  tiles: {
    size: number;
    minzoom: number;
    maxzoom: number;
    /**
     * Toujours du PNG : le décodeur de secours en JavaScript, qui garantit des
     * pixels exacts quand le navigateur bruite le canvas, ne lit que ce format.
     */
    format: 'png';
    /** Zoom des blocs servant à répartir les tuiles entre les archives. */
    blockZoom?: number;
  };
  /** Emprise des données : ouest, sud, est, nord. */
  bounds: [number, number, number, number];
  archives: ManifestArchive[];
  countries: ManifestCountry[];
  /** Pays prévus mais absents de ces données (codes ISO), faute de source disponible à la construction. */
  missing: string[];
}

export const SOURCE_TYPE_KEYS: Record<number, string> = {
  [SOURCE_OFFICIAL_OPERATOR]: 'official_operator',
  [SOURCE_OFFICIAL_AGGREGATED]: 'official_aggregated',
  [SOURCE_ESTIMATED]: 'estimated',
};

export const ALL_OPERATORS = 'all';

function fail(message: string): never {
  throw new Error(`manifest.json invalide : ${message}`);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function str(value: unknown, where: string): string {
  if (typeof value !== 'string' || value === '') fail(`${where} doit être une chaîne non vide`);
  return value;
}

function int(value: unknown, where: string, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) {
    fail(`${where} doit être un entier entre ${min} et ${max}`);
  }
  return value;
}

/** Vérifie la structure du manifest et renvoie un objet typé. Lève une erreur claire sinon. */
export function parseManifest(raw: unknown): Manifest {
  if (!isObject(raw)) fail('la racine doit être un objet');
  if (raw.version !== 1) fail(`version non prise en charge (${String(raw.version)})`);
  const generated = str(raw.generated, 'generated');

  if (!isObject(raw.tiles)) fail('tiles manquant');
  const size = int(raw.tiles.size, 'tiles.size', 256, 256);
  const minzoom = int(raw.tiles.minzoom, 'tiles.minzoom', 0, 24);
  const maxzoom = int(raw.tiles.maxzoom, 'tiles.maxzoom', minzoom, 24);
  const format = raw.tiles.format;
  if (format === 'webp') {
    fail('tiles.format doit valoir png : les tuiles WebP ne sont pas prises en charge (le décodeur de secours en JavaScript, qui garantit des pixels exacts, ne lit que le PNG)');
  }
  if (format !== 'png') fail('tiles.format doit valoir png');
  const blockZoom =
    raw.tiles.blockZoom === undefined ? undefined : int(raw.tiles.blockZoom, 'tiles.blockZoom', 0, maxzoom);

  const bounds = raw.bounds;
  if (!Array.isArray(bounds) || bounds.length !== 4 || bounds.some((v) => typeof v !== 'number')) {
    fail('bounds doit contenir 4 nombres');
  }

  if (!Array.isArray(raw.archives) || raw.archives.length === 0) fail('archives doit être une liste non vide');
  const archives: ManifestArchive[] = raw.archives.map((a, i) => {
    if (!isObject(a)) fail(`archives[${i}] doit être un objet`);
    const archive: ManifestArchive = {
      file: str(a.file, `archives[${i}].file`),
      minzoom: int(a.minzoom, `archives[${i}].minzoom`, 0, 24),
      maxzoom: int(a.maxzoom, `archives[${i}].maxzoom`, 0, 24),
    };
    if (a.blocks !== undefined) {
      if (!Array.isArray(a.blocks) || a.blocks.some((b) => typeof b !== 'string' || !/^\d+\/\d+$/.test(b))) {
        fail(`archives[${i}].blocks doit être une liste de « x/y »`);
      }
      if (blockZoom === undefined) fail('tiles.blockZoom est requis quand une archive déclare des blocs');
      archive.blocks = a.blocks as string[];
    }
    if (typeof a.bytes === 'number') archive.bytes = a.bytes;
    return archive;
  });

  if (!Array.isArray(raw.countries) || raw.countries.length === 0) fail('countries doit être une liste non vide');
  const seenCodes = new Set<number>();
  const countries: ManifestCountry[] = raw.countries.map((c, i) => {
    if (!isObject(c)) fail(`countries[${i}] doit être un objet`);
    const code = int(c.code, `countries[${i}].code`, 1, 15);
    if (seenCodes.has(code)) fail(`code pays en double : ${code}`);
    seenCodes.add(code);
    const iso = str(c.iso, `countries[${i}].iso`).toUpperCase();
    if (!/^[A-Z]{2}$/.test(iso)) fail(`countries[${i}].iso doit être un code à deux lettres`);
    if (!Array.isArray(c.slots) || c.slots.length > SLOT_COUNT) {
      fail(`countries[${i}].slots doit contenir au plus ${SLOT_COUNT} opérateurs`);
    }
    const slots: ManifestSlot[] = c.slots.map((s, j) => {
      const where = `countries[${i}].slots[${j}]`;
      if (!isObject(s)) fail(`${where} doit être un objet`);
      const slot: ManifestSlot = { id: str(s.id, `${where}.id`) };
      if (s.name !== undefined) slot.name = str(s.name, `${where}.name`);
      if (s.minOperators !== undefined) slot.minOperators = int(s.minOperators, `${where}.minOperators`, 1, 9);
      if (slot.name === undefined && slot.minOperators === undefined) fail(`${where} doit avoir un nom ou un seuil minOperators`);
      return slot;
    });
    if (new Set(slots.map((s) => s.id)).size !== slots.length) fail(`countries[${i}].slots contient des identifiants en double`);
    if (slots.some((s) => s.id === ALL_OPERATORS)) fail(`« ${ALL_OPERATORS} » est un identifiant réservé`);
    if (!Array.isArray(c.sources) || c.sources.length === 0) fail(`countries[${i}].sources doit être une liste non vide`);
    const seenTypes = new Set<number>();
    const sources: ManifestSource[] = c.sources.map((s, j) => {
      const where = `countries[${i}].sources[${j}]`;
      if (!isObject(s)) fail(`${where} doit être un objet`);
      const type = int(s.type, `${where}.type`, 0, 3);
      if (seenTypes.has(type)) fail(`${where}.type en double pour ce pays`);
      seenTypes.add(type);
      if (!Array.isArray(s.services) || s.services.length === 0 || s.services.some((v) => v !== 'data' && v !== 'voice')) {
        fail(`${where}.services doit lister data et/ou voice`);
      }
      const levels = s.levels;
      if (levels !== 'four' && levels !== 'three' && levels !== 'binary') fail(`${where}.levels inconnu`);
      let levelMap: number[] | undefined;
      if (s.levelMap !== undefined) {
        if (!Array.isArray(s.levelMap) || s.levelMap.length !== 4) fail(`${where}.levelMap doit contenir 4 valeurs`);
        levelMap = s.levelMap.map((v, k) => int(v, `${where}.levelMap[${k}]`, 0, 3));
      }
      if (typeof s.perOperator !== 'boolean') fail(`${where}.perOperator doit être un booléen`);
      if (s.perOperator && slots.length === 0) fail(`${where} est par opérateur mais le pays ne déclare aucun emplacement`);
      const source: ManifestSource = {
        type,
        id: str(s.id, `${where}.id`),
        name: str(s.name, `${where}.name`),
        date: str(s.date, `${where}.date`),
        licence: str(s.licence, `${where}.licence`),
        attribution: str(s.attribution, `${where}.attribution`),
        services: s.services as ServiceId[],
        levels,
        perOperator: s.perOperator,
      };
      if (levelMap) source.levelMap = levelMap;
      if (typeof s.url === 'string') source.url = s.url;
      if (typeof s.licenceUrl === 'string') source.licenceUrl = s.licenceUrl;
      if (typeof s.licenceNotice === 'string' && s.licenceNotice !== '') source.licenceNotice = s.licenceNotice;
      // Un chemin simple à l'intérieur du site : jamais une adresse externe.
      if (typeof s.licenceLogo === 'string' && /^[a-z0-9][a-z0-9/_.-]*\.(?:png|jpe?g|svg|webp)$/i.test(s.licenceLogo) && !s.licenceLogo.includes('..')) {
        source.licenceLogo = s.licenceLogo;
      }
      if (isObject(s.technology)) source.technology = s.technology as Partial<Record<ServiceId, string>>;
      if (typeof s.resolutionM === 'number') source.resolutionM = s.resolutionM;
      return source;
    });
    if (typeof c.euRoaming !== 'boolean') fail(`countries[${i}].euRoaming doit être un booléen`);
    const country: ManifestCountry = { code, iso, euRoaming: c.euRoaming, slots, sources };
    if (c.operators !== undefined) {
      if (!Array.isArray(c.operators) || c.operators.some((o) => typeof o !== 'string' || o === '')) {
        fail(`countries[${i}].operators doit être une liste de noms`);
      }
      country.operators = c.operators as string[];
    }
    return country;
  });

  const missing = Array.isArray(raw.missing)
    ? raw.missing.flatMap((m) => (isObject(m) && typeof m.iso === 'string' && /^[A-Za-z]{2}$/.test(m.iso) ? [m.iso.toUpperCase()] : []))
    : [];

  return {
    version: 1,
    generated,
    tiles: { size, minzoom, maxzoom, format, ...(blockZoom === undefined ? {} : { blockZoom }) },
    bounds: bounds as [number, number, number, number],
    archives,
    countries,
    missing,
  };
}

// ---------------------------------------------------------------------------
// Recherches dans le manifest
// ---------------------------------------------------------------------------

export function countryByCode(manifest: Manifest, code: number): ManifestCountry | undefined {
  return manifest.countries.find((c) => c.code === code);
}

export function countryByIso(manifest: Manifest, iso: string): ManifestCountry | undefined {
  return manifest.countries.find((c) => c.iso === iso);
}

export function sourceByType(country: ManifestCountry, type: number): ManifestSource | undefined {
  return country.sources.find((s) => s.type === type);
}

/** Vrai si au moins une source du pays fournit ce service. */
export function countryHasService(country: ManifestCountry, service: ServiceId): boolean {
  return country.sources.some((s) => s.services.includes(service));
}

/** Vrai si au moins un pays fournit ce service. */
export function manifestHasService(manifest: Manifest, service: ServiceId): boolean {
  return manifest.countries.some((c) => countryHasService(c, service));
}

/**
 * Emplacements proposés au choix dans l'interface. Le seuil « au moins un
 * opérateur » n'y figure pas : c'est exactement « tous opérateurs ».
 */
export function selectableSlots(country: ManifestCountry): ManifestSlot[] {
  if (!country.sources.some((s) => s.perOperator)) return [];
  return country.slots.filter((slot) => slot.minOperators !== 1);
}

/** Vrai si on peut choisir autre chose que « tous opérateurs » dans ce pays. */
export function countryHasOperatorChoice(country: ManifestCountry): boolean {
  const slots = selectableSlots(country);
  // Un seul opérateur nommé : le choisir ne changerait rien. Un seuil, lui, est toujours un vrai choix.
  return slots.length > 1 || slots.some((slot) => slot.minOperators !== undefined);
}

/**
 * Archive qui contient la tuile z/x/y, ou null si aucune ne la contient.
 * Les archives peuvent être découpées en blocs : le protocole choisit la bonne
 * selon x et y.
 */
export function archiveForTile(manifest: Manifest, z: number, x: number, y: number): ManifestArchive | null {
  const blockZoom = manifest.tiles.blockZoom;
  for (const archive of manifest.archives) {
    if (z < archive.minzoom || z > archive.maxzoom) continue;
    if (!archive.blocks) return archive;
    if (blockZoom === undefined || z < blockZoom) continue;
    const shift = z - blockZoom;
    const set = blockSet(archive);
    if (set.has(`${x >> shift}/${y >> shift}`)) return archive;
  }
  return null;
}

const blockSets = new WeakMap<ManifestArchive, Set<string>>();
function blockSet(archive: ManifestArchive): Set<string> {
  let set = blockSets.get(archive);
  if (!set) {
    set = new Set(archive.blocks);
    blockSets.set(archive, set);
  }
  return set;
}

// ---------------------------------------------------------------------------
// Tables de décodage
// ---------------------------------------------------------------------------

/**
 * Table de 256 entrées : pour un octet R ou G, donne le niveau (0 à 3) de
 * l'opérateur demandé dans ce pays et pour cette source, ou LEVEL_UNKNOWN si
 * la source ne fournit pas ce service.
 *
 * « Tous opérateurs » est le maximum des emplacements du pays. C'est ce qui
 * compte pour le 112, qui passe par n'importe quel réseau.
 */
export function buildLevelTable(
  country: ManifestCountry,
  source: ManifestSource,
  service: ServiceId,
  operator: string,
): Uint8Array {
  const table = new Uint8Array(256);
  if (!source.services.includes(service)) {
    table.fill(LEVEL_UNKNOWN);
    return table;
  }
  const map = source.levelMap ?? [0, 1, 2, 3];
  // Emplacements à prendre en compte : un seul pour un opérateur précis, tous sinon.
  let slots: number[];
  if (!source.perOperator) {
    slots = [0];
  } else {
    const index = operator === ALL_OPERATORS ? -1 : country.slots.findIndex((s) => s.id === operator);
    slots = index >= 0 ? [index] : country.slots.map((_, i) => i);
  }
  for (let byte = 0; byte < 256; byte++) {
    let best = 0;
    for (const slot of slots) {
      const level = map[unpackSlot(byte, slot)];
      if (level > best) best = level;
    }
    table[byte] = best;
  }
  return table;
}

/** Choix de l'utilisateur qui pilote le décodage. */
export interface DecodeSettings {
  service: ServiceId;
  /** Opérateur choisi par pays (code ISO). Absent : tous les opérateurs du pays. */
  operators: Readonly<Record<string, string>>;
}

/**
 * Tables de niveaux indexées par les 6 bits utiles du canal B (pays et type de
 * source). Une entrée null signifie : combinaison inconnue du manifest.
 */
export type LevelTables = (Uint8Array | null)[];

export function buildLevelTables(manifest: Manifest, settings: DecodeSettings, forceAll = false): LevelTables {
  const tables: LevelTables = new Array<Uint8Array | null>(64).fill(null);
  for (const country of manifest.countries) {
    const operator = forceAll ? ALL_OPERATORS : (settings.operators[country.iso] ?? ALL_OPERATORS);
    for (const source of country.sources) {
      tables[(source.type << 4) | country.code] = buildLevelTable(country, source, settings.service, operator);
    }
  }
  return tables;
}

/** Opérateur effectivement appliqué dans un pays, compte tenu de ce que la source permet. */
export function effectiveOperator(country: ManifestCountry, settings: DecodeSettings): ManifestSlot | null {
  const id = settings.operators[country.iso];
  if (!id || id === ALL_OPERATORS || !countryHasOperatorChoice(country)) return null;
  return selectableSlots(country).find((s) => s.id === id) ?? null;
}
