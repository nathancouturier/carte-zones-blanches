// Constantes de l'application, regroupées ici pour être faciles à ajuster.

/** Dossier des données de couverture (manifest.json et archives PMTiles), relatif à la page. */
export const DATA_BASE_URL = `${import.meta.env.BASE_URL}data/`;

/** Vue de départ : la France métropolitaine. */
export const INITIAL_VIEW = { center: [2.6, 46.5] as [number, number], zoom: 5.2 };
/** Emprise utile de la carte : ouest, sud, est, nord. */
export const MAX_BOUNDS: [number, number, number, number] = [-12, 36, 18, 54.5];
/**
 * Réseau faible : délai d'attente de la page et du manifest des données avant que
 * le Service Worker serve leur copie locale, si elle existe (sinon il attend le
 * réseau). En montagne, une barre EDGE laisse le téléphone « en ligne » sans que
 * rien n'arrive. En millisecondes ; transmis dans l'adresse du Service Worker.
 */
export const NETWORK_TIMEOUT_MS = 3000;

// ---------------------------------------------------------------------------
// Analyse des GPX
// ---------------------------------------------------------------------------

/** Pas de rééchantillonnage du tracé, en mètres (distance géodésique). */
export const RESAMPLE_STEP_M = 20;
/** Longueur minimale d'une zone blanche pour figurer dans le rapport, en mètres. */
export const WHITE_ZONE_MIN_LENGTH_M = 100;
/** Deux zones blanches séparées par moins de cette distance de couverture sont fusionnées, en mètres. */
export const WHITE_ZONE_MERGE_GAP_M = 50;
/**
 * Deux segments du GPX qui se suivent à moins de cette distance (pause du GPS,
 * trace coupée en deux) forment un parcours continu : une zone blanche peut
 * passer de l'un à l'autre. Au-delà, le parcours est interrompu. En mètres.
 */
export const SEGMENT_JOIN_MAX_M = 50;
/** Seuil du calcul du dénivelé : les variations plus petites sont ignorées (bruit du GPS), en mètres. */
export const ELEVATION_THRESHOLD_M = 5;
/**
 * Part des points qui doivent avoir une altitude (lue dans le GPX ou interpolée
 * entre deux points connus) pour annoncer un dénivelé, un profil ou l'altitude
 * d'une zone blanche. Au-dessous, le chiffre reposerait sur trop peu de points.
 */
export const ELEVATION_MIN_SHARE = 0.5;
/**
 * Saut maximal entre deux points consécutifs d'une trace (trkpt), en mètres.
 * Au-delà, c'est une erreur de position ou une portion faite sans enregistrer
 * (appareil éteint pendant un trajet en voiture) : la trace est coupée là et le
 * saut ne compte ni dans la distance ni dans l'analyse ; un point isolé loin de
 * ses deux voisins est écarté. Une trace dessinée à la main peut avoir des
 * points espacés de 5 km : d'où une valeur large. Les routes (rtept), aux points
 * souvent très espacés, ne sont pas concernées.
 */
export const TRACK_MAX_JUMP_M = 10_000;
/** Taille maximale d'un fichier GPX accepté, en octets. */
export const MAX_GPX_BYTES = 40 * 1024 * 1024;
/** Nombre de tuiles lues en parallèle pendant l'analyse. */
export const SAMPLING_CONCURRENCY = 6;

// ---------------------------------------------------------------------------
// Recherche de lieux
// ---------------------------------------------------------------------------

export const SEARCH_MIN_CHARS = 3;
export const SEARCH_DEBOUNCE_MS = 350;
export const SEARCH_MAX_RESULTS = 6;
/** Géocodage de la Géoplateforme (IGN) : autocomplétion, France. */
export const IGN_COMPLETION_URL = 'https://data.geopf.fr/geocodage/completion';
/** Photon (komoot), basé sur OpenStreetMap : pour les lieux hors de France. */
export const PHOTON_URL = 'https://photon.komoot.io/api/';
/** Langues acceptées par Photon. Pour les autres, on demande les noms locaux. */
export const PHOTON_LANGS = ['de', 'en', 'fr'];
