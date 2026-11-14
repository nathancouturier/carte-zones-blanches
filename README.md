# Carte des zones blanches

Une carte de randonnée qui montre où il y a du réseau mobile et où il n'y en a pas : en France métropolitaine et en Corse, en Suisse, dans l'Italie frontalière (Val d'Aoste, Piémont, Ligurie), dans l'Espagne pyrénéenne (Catalogne, Aragon, Navarre, Pays basque), en Andorre et à Monaco. On importe un tracé GPX et on obtient la liste des portions du parcours sans réseau. Les données en ligne ne couvrent pas forcément encore tous ces pays : le panneau « Sources » du site dit lesquels sont présents (voir [Pays couverts et nature des données](#pays-couverts-et-nature-des-données)).

**Le site : https://nathancouturier.github.io/carte-zones-blanches/**

Site personnel, 100 % statique : pas de serveur, pas de compte, pas de suivi. Le GPX reste dans le navigateur, il n'est jamais envoyé nulle part. L'interface est pensée d'abord pour le téléphone (Chrome sur Android) et marche aussi sur ordinateur.

## Sommaire

- [Ce que fait le site](#ce-que-fait-le-site)
- [Pays couverts et nature des données](#pays-couverts-et-nature-des-données)
- [Architecture](#architecture)
- [Le pipeline de données](#le-pipeline-de-données)
- [Les workflows GitHub](#les-workflows-github)
- [Mettre à jour les données](#mettre-à-jour-les-données)
- [Faire évoluer le projet](#faire-évoluer-le-projet)
- [Développement local](#développement-local)
- [Limites](#limites)
- [Vie privée](#vie-privée)
- [Licences et crédits](#licences-et-crédits)

## Ce que fait le site

La carte affiche, par-dessus un fond de carte de randonnée, la couverture mobile théorique publiée par les autorités de chaque pays, ou une estimation là où il n'existe pas de source officielle exploitable. Par défaut, seuls les problèmes sont dessinés : en rouge les zones sans couverture, en orange la couverture limitée. Un GPX importé est découpé en portions selon la couverture, et un rapport liste les zones blanches avec leurs kilomètres et leurs altitudes.

Sur téléphone, les panneaux s'ouvrent en bas de l'écran. Sur ordinateur (fenêtre d'au moins 900 px de large), ils s'ouvrent sur le côté. Rien n'est empilé : chaque panneau s'ouvre au clic.

### Mode d'emploi

- **Carte.** Plein écran, centrée sur la France au départ. L'adresse de la page garde la position de la carte (par exemple `#11/44.9/6.42` : zoom, latitude, longitude) : on peut la mettre en favori ou l'envoyer.
- **Loupe.** Recherche d'un lieu avec suggestions, dès 3 caractères : en France par le géocodage de l'IGN, à l'étranger par Photon (données OpenStreetMap).
- **Ma position.** Le bouton du haut affiche votre position sur la carte et la suit.
- **Réseau.**
  - Service : « Internet mobile » ou « Appels et SMS ». Les appels et SMS n'existent que pour la France.
  - Opérateur en France : « Tous opérateurs », Orange, SFR, Bouygues Telecom ou Free. « Tous opérateurs » donne, en chaque point, le meilleur niveau parmi les opérateurs. C'est ce qui compte pour le 112, qui passe par n'importe quel réseau.
  - Rubrique « À l'étranger » : « Tous opérateurs du pays » par défaut, car la couverture réelle dépend des accords d'itinérance de votre opérateur. Quand la source le permet, on peut choisir un opérateur (Espagne) ou un nombre de réseaux (Suisse, Italie).
  - Case « Afficher toute la couverture » : ajoute la bonne et la très bonne couverture, en vert. Les zones estimées sont hachurées. Un curseur règle l'opacité, et le panneau donne la légende.
- **Fond.** « Automatique » prend le fond national du pays au centre de la carte : Plan IGN en France, swisstopo en Suisse, IGN España en Espagne, OpenTopoMap (OpenStreetMap) ailleurs. Le pays est lu dans les données de couverture : hors de la zone couverte, le fond ne change pas. On peut aussi choisir soi-même Plan IGN classique, Plan IGN standard, swisstopo, IGN España, OpenTopoMap ou les photos aériennes de l'IGN, et ajouter l'estompage du relief de l'IGN (France seulement).
- **Importer un GPX.** Par le bouton, ou en glissant le fichier sur la carte (ordinateur). Le site lit les traces, sinon les routes. Plusieurs traces ou segments forment un seul parcours, dans l'ordre du fichier. Le tracé s'affiche avec un liseré blanc et la carte zoome dessus. Une fois l'analyse faite, il prend les couleurs de la couverture : rouge, orange, vert, et gris là où il n'y a pas de données.
- **Rapport** (le bouton apparaît après l'import). On y trouve :
  - la distance, le dénivelé et les altitudes si le GPX les donne, les pays traversés, l'opérateur appliqué dans chaque pays ;
  - la part du parcours par niveau, pour l'opérateur choisi (si vous en avez choisi un) et pour tous opérateurs ;
  - la liste des zones blanches, par exemple « km 12,4 à 14,1, soit 1,7 km, altitude 1 850 à 2 100 m, Italie, estimée ». Toucher une zone la met en surbrillance et zoome dessus ;
  - des avertissements : pays hors de l'itinérance de l'Union européenne (Suisse, Andorre, Monaco : vérifiez votre forfait), partie du parcours estimée, source qui dit seulement « couvert » ou « non couvert ».
- **Profil altimétrique** (dans le rapport, si tous les points du GPX ont une altitude). Il est coloré selon la couverture. Chaque colonne prend la couleur de la pire couverture de sa portion : une courte zone blanche reste visible sur un long parcours. Survoler ou toucher le profil place un repère sur la carte.
- **Emporter le résultat.** « Télécharger le GPX enrichi » donne le GPX d'origine avec un point de passage au début et à la fin de chaque zone blanche (« Zone blanche 1, début », etc.), pour une montre ou une application GPS. `rando.gpx` devient `rando-zones-blanches.gpx` (le suffixe suit la langue). « Copier le rapport » met le rapport en texte dans le presse-papiers. Ce texte est aussi visible sous « Rapport en texte ».
- **Hors ligne** (dans le rapport). « Préparer ce tracé pour le hors ligne » enregistre dans le navigateur les fichiers du site, la couverture d'un couloir de 700 m de part et d'autre du tracé, le fond de carte affiché quand son fournisseur l'autorise, et le GPX lui-même. Sans réseau, le site redémarre et recharge tout seul le tracé enregistré. Le panneau « Importer un GPX » propose aussi « Reprendre le tracé enregistré ». Le dernier tracé préparé remplace le précédent. « Supprimer les données hors ligne » efface les tuiles et le tracé enregistrés. À faire avant de partir, avec du réseau, et avec un autre fond qu'OpenTopoMap (voir [Limites](#limites)).
- **Langues.** Bouton « Paramètres » (roue dentée), puis « Langue » : Français, Español, Català, Italiano, Deutsch. Le choix est mémorisé dans le navigateur. Le paramètre `?lang=` dans l'adresse force une langue, par exemple https://nathancouturier.github.io/carte-zones-blanches/?lang=es. Les nombres et les distances suivent la langue choisie.
- **Sources.** Les mentions des fonds et des données affichés sont en pied de carte. Sur téléphone, elles sont repliées : il faut toucher le bouton « © » pour les lire. Le panneau « Sources » (lien « Sources » du pied de carte, ou « Paramètres » puis « Sources des données ») donne, pour chaque pays, la source, la date des données, la méthode et la licence, avec la phrase « Couverture théorique, des écarts locaux sont possibles. »

## Pays couverts et nature des données

| Zone | Source de la couverture | Nature | Choix proposés | Services | Date des données |
|---|---|---|---|---|---|
| France métropolitaine et Corse | Arcep, « Mon réseau mobile » (couvertures théoriques) | officielle par opérateur, 4 niveaux | Tous opérateurs, Orange, SFR, Bouygues Telecom, Free | internet mobile (4G), appels et SMS (2G et 3G) | 2e trimestre 2026 (situation au 30 juin 2026) |
| Suisse | OFCOM, atlas de la large bande | officielle agrégée, couvert ou non | Tous opérateurs du pays, Les 3 réseaux à la fois | internet mobile (4G) | 30 avril 2026 |
| Italie : Val d'Aoste, Piémont, Ligurie | AGCOM, Broadband Map | officielle agrégée, couvert ou non | Tous opérateurs du pays, Au moins 2 réseaux, Au moins 3 réseaux, Les 4 réseaux à la fois | internet mobile (4G) | 27 janvier 2026 |
| Espagne : Catalogne, Aragon, Navarre, Pays basque | Ministerio para la Transformación Digital y de la Función Pública, « Mapa de Servicios de Banda Ancha Móvil 2024 » | officielle par opérateur, couvert ou non | Tous opérateurs du pays, Movistar, Orange, Vodafone, Xfera Móviles | internet mobile (4G) | 30 juin 2024 |
| Andorre | estimation : antennes OpenCellID et relief Copernicus DEM | estimée, 3 niveaux | aucun choix : tous réseaux confondus | internet mobile (4G et 5G) | mois du calcul |
| Monaco | la même estimation | estimée, 3 niveaux | aucun choix : antennes du code pays monégasque seulement (voir [Limites](#limites)) | internet mobile (4G et 5G) | mois du calcul |

Ce que veulent dire ces mots :

- **Officielle par opérateur** : la source dit quel opérateur couvre chaque lieu.
- **Officielle agrégée** : la source dit combien de réseaux couvrent un lieu, mais pas lesquels. On choisit alors un seuil. Par exemple, « Les 3 réseaux à la fois » en Suisse montre où vous aurez du réseau quel que soit l'opérateur utilisé en itinérance.
- **Estimée** : il n'existe pas de carte officielle exploitable. La couverture est calculée (voir [L'estimation](#lestimation)). Ces zones sont hachurées sur la carte et marquées « estimée » dans le rapport.
- **Couvert ou non** : la source n'a pas de niveau de qualité. Sur la carte et dans le rapport, « bonne couverture » y veut dire « couvert ».

Ce tableau décrit ce que construit la configuration de production (`pipeline/config.yaml`). Le panneau « Sources » du site dit quels pays figurent vraiment dans les données publiées, avec la date de chaque source. Le détail des sources (adresses, licences, méthodes, limites) est dans [docs/sources.md](docs/sources.md).

### Andorre et Monaco : créer le secret OPENCELLID_TOKEN

L'estimation a besoin d'une clé d'accès gratuite à OpenCellID, la base d'antennes utilisée. Tant que le secret `OPENCELLID_TOKEN` n'existe pas dans le dépôt, la construction laisse ces deux pays de côté. Ils n'apparaissent pas sur la carte, et le panneau « Sources » affiche « Pas encore de données pour : Andorre, Monaco ». Un tracé qui y passe est compté « hors zone » : le rapport ne peut donc pas y signaler la sortie de l'itinérance de l'Union européenne.

Pour les ajouter :

1. Créer un compte gratuit sur [opencellid.org](https://opencellid.org) (page d'inscription : https://my.opencellid.org/register). Se connecter, puis afficher la clé dans la rubrique « API Access Tokens » du tableau de bord.
2. Dans le dépôt GitHub : Settings, Secrets and variables, Actions, puis New repository secret. Nom : `OPENCELLID_TOKEN`. Valeur : la clé.
3. Relancer le workflow « Données » : onglet Actions, « Données », « Run workflow », périmètre « production ». Le pipeline voit que la source est devenue disponible et reconstruit les données. Il est inutile de cocher « Reconstruire même si aucune source n'a changé ». Sans cette relance, le passage mensuel suivant le fera.

La clé n'apparaît pas dans les journaux : GitHub masque les secrets, et le module retire la clé de ses propres messages.

### L'estimation

Le module `estimation_opencellid` (réglages dans la section `estimation` de `pipeline/config.yaml`) procède ainsi :

1. Il lit les cellules 4G et 5G d'OpenCellID du pays et de ses abords (2 km). Il les regroupe par station, puis fusionne en un seul site les points à moins de 300 m l'un de l'autre.
2. Pour chaque site, GDAL calcule sur le relief (Copernicus DEM GLO-30, ramené sur la grille du projet), en chaque pixel, la hauteur au-dessus du sol qu'il faudrait pour voir l'antenne, placée à 30 m de haut. Le site est « visible » si cette hauteur ne dépasse pas 1,5 m (un téléphone tenu à la main), et « presque visible » s'il manque moins de 30 m.
3. Un pixel reçoit « bonne couverture » si un site est visible à 5 km au plus, presque visible à 1 km au plus, ou présent à 500 m au plus. Sinon, il reçoit « couverture limitée » avec les distances 15 km, 7,5 km et 2 km. Sinon, « pas de couverture ». « Très bonne couverture » n'est jamais attribué.

Cette règle a été calée sur la France, là où la vérité officielle existe : sites et cartes de l'Arcep dans les Hautes-Alpes et en Ariège, soit 21,7 millions de pixels comparés. Les résultats de ce calage sont dans [Limites](#limites).

## Architecture

### Le site

Le site est une seule page, construite avec Vite et TypeScript. Il utilise MapLibre GL JS (la carte), pmtiles (lecture des archives de tuiles), @tmcw/togeojson (lecture du GPX) et fast-png (décodeur PNG écrit en JavaScript, qui sert de contrôle et de secours). Il n'y a pas de serveur d'application : GitHub Pages sert des fichiers statiques sous `/carte-zones-blanches/` (réglage `base` de `vite.config.ts`). Au déploiement, les données de couverture sont posées dans `data/`, à côté de la page : un fichier `manifest.json` et une ou plusieurs archives `.pmtiles`. Ces données ne sont jamais enregistrées dans git : elles sont jointes aux releases `data-*` du dépôt, et le déploiement les copie dans le site.

```
index.html              la page
src/
  main.ts, app.ts       démarrage, puis chef d'orchestre (état, carte, données, interface)
  config.ts             constantes réglables : seuils de l'analyse, recherche, vue de départ, emprise
  state.ts              état de l'application, réglages mémorisés
  coverage/             tuiles de couverture : encodage, manifest, décodage, cache, protocole MapLibre, couleurs
  gpx/                  lecture du GPX, rééchantillonnage, zones blanches, rapport, export
  map/                  fonds de carte, style MapLibre, carte
  offline/              mode hors ligne : couloir de tuiles, enregistrement
  search/               recherche de lieux
  ui/                   barres, panneaux, profil altimétrique
  i18n/                 traductions : index.ts, et un fichier JSON par langue dans locales/
public/
  sw.js                 Service Worker (mode hors ligne)
  licences/             logo exigé par la licence de l'AGCOM
tests/                  tests Vitest du site
samples/                deux GPX de test : test-alpes.gpx et test-pyrenees.gpx
e2e/verif.mjs           vérification du site en ligne dans un vrai navigateur (Playwright)
pipeline/               pipeline de données : Python et GDAL
  config.yaml           la référence : grille, limites, pays, sources, périmètres
  czb/                  grille, masques, canaux, tuiles, archives, manifest, test de cohérence, copies de travail
  czb/sources/          un module par source de couverture
  sondes/               scripts de vérification des sources (workflow Sonde)
  tests/                tests du pipeline sur des données synthétiques
docs/sources.md         inventaire des sources, licences et méthodes
.github/workflows/      Tests, Données, Déploiement, Vérification, Sonde
```

### Des tuiles de données, pas des images

Une archive PMTiles est un seul fichier qui contient toutes les tuiles ; le navigateur n'en lit que les morceaux utiles. Ici, les tuiles sont des PNG sans perte de 256 px, des zooms 0 à 12, et chaque pixel porte des données, pas une couleur. L'encodage est le même dans `pipeline/czb/encoding.py`, qui écrit les tuiles, et dans `src/coverage/codec.ts`, qui les lit :

| Canal | Contenu |
|---|---|
| R | internet mobile : 4 emplacements d'opérateur de 2 bits chacun. L'emplacement i occupe les bits 2i et 2i+1. Valeur : 0 pas de couverture, 1 limitée, 2 bonne, 3 très bonne |
| G | appels et SMS : même encodage (0 là où le service n'est pas construit) |
| B | bits 0 à 3 : code du pays (1 France, 2 Suisse, 3 Italie, 4 Espagne, 5 Andorre, 6 Monaco). Bits 4 et 5 : type de source (0 officielle par opérateur, 1 officielle agrégée, 2 estimée) |
| A | 255 dans la zone couverte par les données, 0 ailleurs |

Une source qui dit seulement « couvert » écrit le niveau 2. L'estimation n'écrit que 0, 1 ou 2. Le zoom 12 est la résolution de travail : un pixel y fait 38,2 m en projection Mercator, soit 26 à 28 m au sol dans les Alpes et les Pyrénées (la taille au sol varie avec la latitude). Les zooms inférieurs recopient le pixel central du carré qu'ils représentent (plus proche voisin). Il n'y a jamais de moyenne : elle mélangerait les bits et fausserait les données. Une tuile qui a peu de valeurs différentes est enregistrée en PNG à palette, plus léger.

Ce choix donne peu de fichiers, un changement d'opérateur instantané, et les mêmes tuiles servent à l'affichage et à l'analyse des GPX.

### Le manifest

Le fichier `manifest.json`, publié avec les tuiles, dit au site tout ce qu'il doit savoir :

- les tuiles : taille, zooms, format, emprise ;
- les archives : nom, zooms et, pour une archive découpée, la liste de ses blocs ;
- pour chaque pays : son code (canal B), son code ISO, l'itinérance de l'Union européenne (oui ou non), la mention à citer pour son contour, et le contenu de chaque emplacement : un opérateur nommé, ou un seuil « au moins N réseaux » ;
- pour chaque source : type, nom, adresse, date des données, licence et mention à afficher, services fournis, façon de lire les niveaux (`four`, `three` ou `binary`), technologie, résolution ;
- les pays prévus mais absents des données (`missing`), par exemple faute de clé d'accès.

Le décodeur du site est piloté par ce fichier. Pour chaque pays et chaque source, il fabrique une table de 256 cases qui donne, pour un octet R ou G, le niveau de l'opérateur choisi. Rien n'est codé en dur par pays : un pays ajouté dans le pipeline apparaît sur la carte sans toucher au code de la couche réseau. Un service absent d'une source (les appels et SMS hors de France) est lu « pas de donnée », jamais « pas de couverture ».

### Affichage de la couche réseau

- Un protocole MapLibre personnalisé, `couverture://` (fonction `addProtocol`, fichier `src/coverage/protocol.ts`), répond aux demandes de tuiles de la carte. Il trouve l'archive qui contient la tuile, la lit, la décode (`createImageBitmap` avec `premultiplyAlpha` et `colorSpaceConversion` à `none`, puis `getImageData`), la recolore selon les réglages et la rend à MapLibre.
- Un cache LRU garde les 160 dernières tuiles décodées (`src/coverage/store.ts`). Le même cache sert à l'analyse des GPX. Quand un réglage change (opérateur, service, affichage), la couche est redessinée à partir du cache, sans rien retélécharger.
- « Tous opérateurs » est le maximum des emplacements du pays, calculé dans le navigateur.
- Décodeur de secours : certains navigateurs ajoutent exprès un léger bruit aux pixels relus d'un canvas, pour gêner le pistage. Les 3 premières tuiles sont donc décodées une seconde fois en JavaScript pur. Au moindre écart, le site passe pour de bon sur ce décodeur, qui donne des pixels exacts.
- La couche est dessinée en plus proche voisin (`raster-resampling: nearest`), sous les libellés du fond : juste avant la première couche `symbol` du style.
- Plusieurs archives : si les tuiles dépassent 70 Mo au total, le pipeline écrit une archive d'aperçu (zooms 0 à 7) et des archives par blocs. Un bloc est une tuile du zoom 8 avec tout ce qu'elle contient aux zooms 8 à 12. Le manifest donne les blocs de chaque archive, et le site choisit la bonne archive selon x et y.
- Les noms des archives contiennent la date et l'heure de la construction (`couverture-AAAAMMJJ-HHMM-NN.pmtiles`). Un navigateur ne peut donc pas mélanger d'anciennes tuiles gardées en cache avec un nouveau manifest.

### Analyse d'un GPX

1. Le GPX est lu avec @tmcw/togeojson : les traces, ou à défaut les routes.
2. Le parcours est rééchantillonné tous les 20 m (distance géodésique). Les sauts entre deux segments ne comptent pas dans la distance.
3. Pour chaque point, le site lit au pixel près les tuiles du zoom 12 : niveau pour l'opérateur choisi et pour tous opérateurs, pays, type de source. Chaque tuile n'est lue qu'une fois.
4. Les points sans couverture qui se suivent forment des tronçons. Deux tronçons séparés par moins de 50 m de couverture sont fusionnés. Une zone blanche fait au moins 100 m. Deux segments éloignés de plus de 50 m ne sont jamais réunis.
5. Les points hors de la zone couverte par les données sont « hors zone ». Les points où la source ne fournit pas le service choisi sont « sans donnée pour ce service ». Les deux sont exclus des pourcentages.
6. Les valeurs brutes des pixels sont gardées : changer d'opérateur ou de service refait le rapport sans rien relire.

Les seuils sont des constantes de `src/config.ts` : `RESAMPLE_STEP_M` (20 m), `WHITE_ZONE_MIN_LENGTH_M` (100 m), `WHITE_ZONE_MERGE_GAP_M` (50 m), et `ELEVATION_THRESHOLD_M` (5 m : le dénivelé ignore les variations plus petites, dues au bruit du GPS).

### Mode hors ligne

Le Service Worker (`public/sw.js`) est un petit programme que le navigateur garde à côté du site. Il sert les fichiers enregistrés quand il n'y a pas de réseau :

- fichiers servis par le site lui-même : le réseau d'abord, la copie locale en secours. En ligne on a donc toujours la dernière version, hors ligne la dernière vue ;
- tuiles de fond, styles et polices, servis par d'autres sites : la copie locale si elle existe, sinon le réseau. Rien n'est enregistré automatiquement : seul le bouton « Préparer ce tracé pour le hors ligne » remplit ce cache ;
- les lectures partielles des archives PMTiles ne passent pas par lui. La page enregistre elle-même les tuiles de couverture du couloir (zooms 8 à 12) et les relit quand le réseau manque (`src/offline/manager.ts`).

Le fond n'est préchargé que si son fournisseur l'accepte, et dans une limite (champ `offline` de `src/map/basemaps.ts`) :

| Fond | Préchargement | Plafond par tracé | Zooms |
|---|---|---|---|
| Plan IGN classique et standard (tuiles vectorielles) | oui | 900 tuiles | 7 à 15 |
| Photos aériennes (IGN) | oui | 600 tuiles | 9 à 16 |
| swisstopo | oui | 600 tuiles | 9 à 15 |
| IGN España | oui | 600 tuiles | 9 à 15 |
| OpenTopoMap | non | aucun | aucun |

Ces plafonds sont des choix du projet, compatibles avec les conditions lues chez chaque fournisseur (voir [docs/sources.md](docs/sources.md)). Si le couloir demande plus de tuiles, les zooms les plus fins sont abandonnés. Pour le Plan IGN, le style, les icônes et les polices sont enregistrés aussi. Le Service Worker n'est installé que par la version construite du site, pas par `npm run dev`.

### Tests

- **Site** (`npm test`, Vitest, dossier `tests/`) : encodage et décodage des 4 canaux, lecture du manifest et tables de niveaux ; lecture du GPX (trace, route, multi-segments, sans altitude), rééchantillonnage, zones blanches, kilomètres, statistiques, export ; profil altimétrique ; couloir du mode hors ligne ; recherche et style de la carte ; recoloration des tuiles et cache. Pour les traductions : mêmes clés dans toutes les langues, mêmes paramètres entre accolades, aucun texte vide, glossaire respecté, toutes les clés utilisées par le code présentes, et aucun tiret cadratin ni demi-cadratin dans les traductions, ce README, `index.html`, le manifeste web et `docs/`.
- **Site et pipeline ensemble** : les tests du site relisent une petite archive PMTiles produite par le pipeline sur des données synthétiques (`tests/fixtures/synthetique/`) et comparent ses pixels aux points témoins du pipeline. L'encodage du pipeline (Python) et le décodage du site (TypeScript) sont ainsi contrôlés ensemble.
- **Pipeline** (`pipeline/tests/`, pytest) : tout tourne sur des données synthétiques, sans réseau. Faux fichiers Arcep (adresses `file://`, archives 7z), GeoTIFF fabriqué pour la Suisse, faux service ArcGIS pour l'Italie et l'Espagne (`fake_arcgis.py`), relief et cellules inventés pour l'estimation, frontières entre deux pays. Une construction complète passe le test de cohérence, qui doit aussi détecter un niveau faux. D'autres tests vérifient la pyramide en plus proche voisin, le découpage en archives, le calage de la grille espagnole et le refus des téléchargements coupés.
- **GPX de test** : `samples/test-alpes.gpx` (des Chapieux à La Visaille par le col de la Seigne, France et Italie) et `samples/test-pyrenees.gpx` (de Gavarnie au refuge de Góriz par la brèche de Roland, France et Espagne). Chacun traverse une zone blanche des données de l'Arcep. Ce sont des tracés de test, à ne pas utiliser pour s'orienter. Leur fabrication, leurs licences et les zones blanches attendues sont décrites dans `samples/README.md`.
- **Site en ligne** : `e2e/verif.mjs` (voir [Les workflows GitHub](#les-workflows-github)).

## Le pipeline de données

Le pipeline transforme les sources de couverture en tuiles. Il est écrit en Python avec GDAL et tourne dans GitHub Actions, dans l'image `ghcr.io/osgeo/gdal:ubuntu-small-3.13.3`. On l'appelle depuis le dossier `pipeline/` :

| Commande | Rôle |
|---|---|
| `python3 -m czb.cli state --scope ... --services ...` | affiche l'état des sources en ligne |
| `python3 -m czb.cli changed --repo propriétaire/nom ...` | compare cet état à celui de la dernière release de données |
| `python3 -m czb.cli production` | affiche le périmètre et les services de la production (`config.yaml`) |
| `python3 -m czb.cli fetch-cache --repo propriétaire/nom` | récupère les copies de travail de la dernière release |
| `python3 -m czb.cli build --scope ... --services ...` | construit les archives PMTiles et le manifest |
| `python3 -m czb.cli verify --out out` | test de cohérence : source contre pixels du PMTiles |

### Étapes d'une construction

1. **Préparation des sources.** Chaque source dit si elle peut être traitée. Une source impossible à traiter (clé d'accès absente, par exemple) est laissée de côté avec sa raison, et son pays est noté absent dans le manifest.
2. **État des sources.** Il est écrit dans `etat-sources.json`. Il sert à détecter les nouvelles versions.
3. **Masques des pays.** Le contour de chaque pays est posé sur la grille : le canal B reçoit le code du pays.
4. **Sources, l'une après l'autre.** Chaque module télécharge et décompresse un fichier à la fois, et supprime les fichiers intermédiaires au fur et à mesure. Il reprojette en EPSG:3857 et rastérise sur la grille commune : un pixel est allumé si son centre est dans le polygone (pour une source en image, il prend la valeur de la case qui contient son centre). Si deux niveaux se chevauchent, le plus élevé gagne. Une source n'écrit que dans les pixels de son pays.
5. **Interstices de frontière.** Les petits trous comblés entre deux contours reçoivent un niveau tiré de leurs voisins (voir plus bas).
6. **Tuiles.** Les canaux R, G, B et A sont assemblés. Le pipeline fabrique les tuiles du zoom 12, puis les zooms inférieurs en plus proche voisin, et écrit les archives PMTiles, découpées si besoin. Il écrit aussi `manifest.json`, les points témoins (`temoins.json` pour les sources, `temoins-contours.json` pour les contours) et `rapport-construction.json` (grille, nombre de tuiles, tailles, durées).
7. **Test de cohérence** (`verify`), décrit plus bas.
8. **Publication**, par le workflow « Données » : une release GitHub `data-AAAA-MM-JJ`, c'est-à-dire une publication du dépôt avec ces fichiers joints.

### Un module par source

| Module (`pipeline/czb/sources/`) | Source(s) de `config.yaml` | Ce qu'il lit |
|---|---|---|
| `fr_arcep.py` | `fr_arcep` | fichiers GeoPackage de l'Arcep, un par opérateur, technologie et usage, listés sur https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/00_Metropole/ (EPSG:2154, champ `niveau` : TBC, BC, CL ; pas de polygone = pas de couverture) |
| `ch_bakom.py` | `ch_bakom` | GeoTIFF de l'OFCOM, collection STAC `ch.bakom.mobilnetz-4g` (EPSG:2056, carrés de 100 m, valeurs 0, 2 et 3) |
| `it_agcom.py` | `it_agcom` | service ArcGIS REST de l'AGCOM, `Grid100/mobile_4G` (EPSG:3857, champ `n_infrastrutture_totali` de 1 à 4) |
| `es_mtd.py` | `es_mtd` | couche ArcGIS Online du ministère espagnol, `InfoCob4G_2024` (EPSG:4258, champ `COBERTURA` : identifiants fiscaux des opérateurs présents ; champ `CCOM` : communauté autonome) |
| `estimation_opencellid.py` | `ad_estimation`, `mc_estimation` | cellules OpenCellID (codes pays mobiles 213 et 212), relief Copernicus DEM GLO-30, calcul de visibilité de GDAL |

Chaque module commence par un commentaire qui décrit la source telle qu'elle a été vérifiée. Tous suivent l'interface de `base.py` et sont enregistrés dans `__init__.py`. Ils s'appuient sur des outils communs : `czb/arcgis.py` (lecture page par page d'un service ArcGIS REST, par identifiant croissant), `czb/net.py` (téléchargements avec nouveaux essais et contrôle de la taille reçue, 7-Zip), `czb/raster.py` (rastérisation, reprojection).

### Grille commune et frontières

- Toutes les sources sont ramenées sur la même grille : EPSG:3857, pixels alignés sur les tuiles du zoom 12. La fenêtre de travail est la plus petite fenêtre alignée sur les tuiles qui contient tous les pays du périmètre. Pour la France entière, elle fait 43 008 x 41 472 pixels.
- Les trois canaux sont des fichiers sur disque, jamais chargés en entier en mémoire (environ 2 Go par canal pour la France).
- Contours des pays : départements d'Etalab pour la France (dérivés d'ADMIN EXPRESS de l'IGN ; la Corse comprise), swissBOUNDARIES3D de swisstopo pour la Suisse, limites administratives de l'ISTAT pour l'Italie, unités administratives de l'IGN España pour l'Espagne, OpenStreetMap pour l'Andorre et Monaco (terre ferme seulement pour Monaco). OpenStreetMap étant modifiable par tous, la construction s'arrête si la surface de ces deux contours sort d'une fourchette attendue.
- Ces contours viennent de producteurs différents et ne coïncident pas exactement. Quand deux pays revendiquent un pixel, le pays le plus haut dans `config.yaml` le garde (France, Suisse, Italie, Espagne, Andorre, Monaco). Les trous fermés de moins de 100 ha entre deux contours sont donnés au pays le moins prioritaire qui les touche. Leurs pixels prennent, pour chaque opérateur, le plus petit niveau de leurs voisins connus, jusqu'à 16 pixels de distance : dans le doute, on annonce le moins de couverture. Les trous plus grands sont de vraies enclaves ou des lacs, et restent hors zone.
- En Suisse, les carrés sans donnée collés à la frontière sont comblés de la même façon, sur deux carrés de profondeur.

### Points témoins et test de cohérence

- Pour chaque fichier ou chaque emplacement d'une source, 240 pixels du pays sont tirés au hasard (graine fixe, section `verification` de `config.yaml`), et 60 sont gardés, répartis entre les niveaux.
- Le niveau attendu de chaque point est établi directement dans la source, sans passer par la rastérisation ni la reprojection sur la grille commune : test géométrique exact sur les polygones (France, Italie), case de la grille d'origine (Suisse, Espagne), tableau du calcul (estimation). Un point trop près d'un bord est écarté.
- Les contours sont contrôlés de la même façon. Des pixels sont tirés au hasard sur toute la grille et autour de chaque pays. Leur pays attendu (ou aucun) est établi par un test géométrique exact sur les contours, dans l'ordre de priorité ; les points des interstices comblés et ceux trop près d'un contour sont écartés.
- Une fois les archives écrites, `verify` relit tous ces points dans les pixels décodés du PMTiles : niveau dans les canaux R et G, pays dans le canal B. Le job échoue au moindre écart, ou si une source, un service ou un emplacement annoncé dans le manifest a moins de 20 points.
- Pour l'Espagne, le module mesure en plus le calage de la grille des polygones, et compare sa copie de travail (voir ci-dessous) aux polygones en des points tirés au hasard dans chaque région. Un changement de grille de la source arrête la construction.

### Copies de travail

Certaines sources coûtent cher à relire : un bon millier de requêtes pour l'Espagne (environ 2,1 millions de polygones). D'autres limitent les téléchargements : OpenCellID permet deux téléchargements par jour et par fichier. Leur résultat, ramené à une image compacte, est publié avec les données sous le nom `cache-<source>.tif` (code dans `pipeline/czb/cache.py`).

- Avant de construire, le workflow « Données » récupère ces fichiers dans la dernière release (`fetch-cache`). S'ils manquent, les sources sont relues en entier.
- La copie espagnole sert tant que l'édition en ligne, l'emprise et la liste des opérateurs n'ont pas changé.
- La copie d'une estimation sert pendant tout le mois où elle a été faite. Si OpenCellID ne répond pas, la copie d'un mois précédent est reprise : mieux vaut une estimation un peu ancienne que pas de pays du tout.
- Le site n'utilise pas ces fichiers : le déploiement ne télécharge que les archives `.pmtiles` et `manifest.json`.

### Chiffres des constructions

Constructions réelles dans GitHub Actions, le 14 novembre 2026 :

| Construction | Ce qui a été lu | Taille | Résultat | Durée | Test de cohérence |
|---|---|---|---|---|---|
| France entière, internet mobile et appels et SMS | 8 fichiers Arcep, 2,2 Go compressés | grille de 43 008 x 41 472 pixels | 17 324 tuiles, 332 Mo en 6 archives (la plus grosse : 69,8 Mo) | 45 min | 480 points, aucun écart |
| Suisse seule (essai) | le GeoTIFF de l'OFCOM | 60,3 millions de pixels en Suisse | 1,1 Mo | 88 s | 120 points, aucun écart |
| Italie seule, 3 régions (essai) | 4 697 polygones en 19 requêtes | 46,7 millions de pixels en Italie | 2,9 Mo | 149 s | 240 points, aucun écart |
| Espagne, 4 régions | environ 2,1 millions de polygones | | essai en cours au moment où ce texte est écrit | | |
| Andorre et Monaco | | | estimation prête, pas encore construite : le secret `OPENCELLID_TOKEN` n'existe pas encore | | |

## Les workflows GitHub

Un workflow est une tâche automatique de GitHub Actions. Ils sont dans `.github/workflows/`. Certains se lancent à la main depuis l'onglet Actions du dépôt (bouton « Run workflow »), d'autres tout seuls.

| Workflow | Fichier | Quand | Rôle |
|---|---|---|---|
| Tests | `ci.yml` | à chaque push sur une autre branche que `main` (sauf s'il ne touche que les sondes ou des fichiers `.md`), et sur chaque pull request | teste et construit le site ; teste le pipeline dans l'image GDAL |
| Données | `build-data.yml` | à la main, et le 5 de chaque mois à 3 h 23 UTC | construit les tuiles ; ne publie que la production |
| Déploiement | `deploy.yml` | à chaque push sur `main`, à chaque release publiée, à la main, et relancé par « Données » après une nouvelle release | construit le site avec la dernière release de données et le publie sur GitHub Pages |
| Vérification | `verification.yml` | après chaque déploiement, ou à la main (adresse à vérifier) | contrôle le site en ligne dans un vrai navigateur |
| Sonde | `sonde.yml` | à la main (nom du script) | lance un script de vérification d'une source sur une machine de GitHub qui a accès à Internet |

### Données

- **Production et essais.** La production est ce qu'indique la section `production` de `pipeline/config.yaml` : le périmètre `complet` (tous les pays), avec les services `data` (internet mobile) et `voice` (appels et SMS). Seul le choix « production » du lancement à la main, et le passage mensuel, sont publiés. Tout autre choix est un essai, même le périmètre `complet` : il est toujours construit, même si rien n'a changé, et vérifié comme la production, puis gardé 7 jours dans l'artefact « donnees » du run (des fichiers téléchargeables depuis la page du run). Un essai ne remplace jamais les données du site.
- **Réglages du lancement à la main** : « Périmètre » (`production`, ou un périmètre d'essai), « Services d'un essai » (`data` ou `data,voice`, ignoré pour la production), « Reconstruire même si aucune source n'a changé ».
- **Étapes** : installation des outils (7-Zip, dépendances Python), lecture de la production, tests du pipeline sur données synthétiques, « Une source a-t-elle changé ? », récupération des copies de travail, construction, test de cohérence, conservation du résultat. Pour la production, si une source a changé, un second job publie la release `data-AAAA-MM-JJ` (puis `data-AAAA-MM-JJ-2`, `-3` s'il y en a déjà une ce jour-là), ne garde que les trois releases de données les plus récentes, et relance le déploiement.
- **Ne reconstruire que si une source a changé.** Chaque release contient `etat-sources.json`, l'état des sources au moment de la construction. Avant de construire, le workflow relit l'état en ligne et le compare. S'il n'a pas changé, rien n'est construit.
- **Passage mensuel.** Le 5 de chaque mois à 3 h 23 UTC. GitHub désactive les workflows planifiés d'un dépôt resté 60 jours sans activité : un petit job réactive ce workflow à chaque passage mensuel.
- **Constructions simultanées.** Les constructions de production (passage mensuel ou choix « production ») passent l'une après l'autre. Les essais peuvent tourner en même temps : ils ne publient rien.

### Déploiement

1. tests du site (`npm test`) ;
2. téléchargement, dans `public/data/`, des archives `.pmtiles` et du `manifest.json` de la release de données la plus récente (par date de publication) ;
3. contrôles : le manifest doit être lisible et toutes les archives qu'il cite doivent être présentes. Sinon le déploiement échoue, et le site déjà en ligne garde ses données. S'il n'existe aucune release de données, il échoue aussi, sauf s'il a été lancé à la main avec l'option « Publier même s'il n'existe aucune release de données » (le site est alors publié sans couche réseau) ;
4. construction du site (`npm run build`) ;
5. contrôle des tailles : chaque fichier sous 95 Mo, le site complet sous 900 Mo ;
6. publication sur GitHub Pages ;
7. vérification du site en ligne (workflow « Vérification »).

### Vérification

Le script `e2e/verif.mjs` ouvre le site dans Chromium, avec Playwright : sur ordinateur en français, puis sur un écran de téléphone en allemand, en français pour le mode hors ligne, et en espagnol avec un passage au catalan et à l'italien. Il contrôle le chargement du fond de carte et des données de couverture, la recherche, l'import d'un GPX, le rapport, le GPX enrichi, le profil, les appels et SMS quand ils sont publiés, le redémarrage sans réseau, et l'absence d'erreur JavaScript. Il utilise `samples/test-alpes.gpx` si ce fichier existe, sinon un court tracé écrit dans le script. Les captures d'écran sont gardées 14 jours dans l'artefact « captures ».

### Sonde

Une sonde sert à vérifier une source avant de l'intégrer : une adresse, un identifiant de couche, un schéma (`ogrinfo`, `gdalinfo`) ou une licence. Le script choisi dans `pipeline/sondes/` tourne dans l'image GDAL, et on lit le résultat dans le journal du job. Les scripts `x-*.sh` sont ceux des recherches déjà faites.

## Mettre à jour les données

### Ce qui est automatique

Le 5 de chaque mois, le workflow « Données » regarde si une source a changé. Si oui, il reconstruit tout, vérifie, publie une nouvelle release et relance le déploiement. Ce qu'il surveille :

| Source | Ce qui est comparé |
|---|---|
| Arcep | les fichiers de la page de téléchargement (noms, tailles, dates). Un nouveau trimestre change les noms. |
| OFCOM | la date de l'item STAC et la date de mise à jour de son GeoTIFF |
| AGCOM | le nom du service (il contient la date des données), la phrase de publication, le nombre de polygones |
| Ministère espagnol | le nom de la couche, sa date de dernière modification, le nombre de polygones par région, la date de modification de l'élément ArcGIS |
| Estimation | seulement ses réglages. OpenCellID change tous les jours, ce n'est pas une raison de tout reconstruire. L'estimation est refaite quand une construction a lieu un autre mois. |

L'état compare aussi le périmètre, les services et le numéro de version du pipeline (`pipeline/czb/__init__.py`) : augmenter ce numéro provoque une reconstruction au passage suivant.

Deux choses ne sont pas surveillées et se mettent à jour à la main dans `pipeline/config.yaml` :

- les contours des pays : un nouveau contour ne déclenche pas de reconstruction. Deux adresses portent un millésime, à changer quand un nouveau paraît : swissBOUNDARIES3D (janvier 2026) et les limites de l'ISTAT (1er janvier 2026) ;
- une nouvelle édition de la carte espagnole publiée à une autre adresse. Le pipeline surveille la couche configurée, pas la page du ministère. Il faudrait alors changer `layer_url`, `item_url`, `name` et `data_date` de la source `es_mtd`.

De même, le pipeline lit le service italien `Grid100/mobile_4G` : que la prochaine édition de l'AGCOM soit publiée à cette même adresse n'est pas vérifié.

### Forcer une reconstruction

Onglet Actions, « Données », « Run workflow » : périmètre « production », et cocher « Reconstruire même si aucune source n'a changé ». C'est utile après une modification du pipeline.

### Faire un essai sur un seul pays

Onglet Actions, « Données », « Run workflow » : choisir un périmètre d'essai et les services (`data`, ou `data,voice`). Les périmètres sont définis dans la section `scopes` de `pipeline/config.yaml` :

| Périmètre | Contenu |
|---|---|
| `suisse`, `italie`, `espagne` | un seul pays |
| `espagne-essai` | l'Espagne avec la couverture d'une seule région, le Pays basque : toute la chaîne en peu de temps |
| `andorre-monaco` | l'Andorre et Monaco (il faut le secret `OPENCELLID_TOKEN`) |
| `hautes-alpes` | la France réduite au département 05 (prototype) |
| `france` | la France entière |
| `alpes` | les départements 04, 05, 06, 73 et 74, la Suisse et l'Italie |
| `frontieres` | les 15 départements frontaliers et tous les pays voisins |
| `complet` | tout : le même périmètre que la production, mais en essai |

Un essai n'est jamais publié. Pour le regarder, télécharger l'artefact « donnees » depuis la page du run (il est gardé 7 jours), copier ses fichiers `.pmtiles` et `manifest.json` dans `public/data/`, puis lancer `npm run dev` (voir [Développement local](#développement-local)).

### Savoir ce qui est en ligne

Le panneau « Sources » du site donne la date de chaque source et la date de génération des tuiles. Sur GitHub, la release `data-*` la plus récente contient aussi `rapport-construction.json` (les chiffres de la construction) et les fichiers de points témoins.

## Faire évoluer le projet

### Ajouter une langue

1. Copier `src/i18n/locales/fr.json` sous le code de la langue, par exemple `en.json`.
2. Dans le bloc `_meta`, mettre le nom de la langue, écrit dans cette langue, et la balise qui sert à formater les nombres et les dates : `{"name": "English", "locale": "en-GB"}`.
3. Traduire les valeurs, sans toucher aux clés ni aux paramètres entre accolades (`{km}`, `{count}`, etc.). Les clés qui finissent par `_one` et `_other` sont les formes du singulier et du pluriel. Pas de tiret cadratin ni demi-cadratin : un test les refuse.
4. Mettre à jour le premier test de `tests/i18n.test.ts` (« propose les cinq langues, le français en premier »), qui vérifie la liste exacte des langues. L'ordre d'affichage vient de `PREFERRED_ORDER` dans `src/i18n/index.ts` (l'anglais y est déjà prévu, après l'allemand). Une langue absente de cette liste vient après les autres, par ordre alphabétique.
5. Lancer `npm test`. Le test « toutes les langues ont exactement les mêmes clés » signale toute clé manquante ou en trop. D'autres tests vérifient les paramètres entre accolades et qu'aucun texte n'est vide.

La langue apparaît toute seule dans les paramètres et répond à `?lang=`. Si une clé manque malgré tout, le site retombe sur le français. La recherche à l'étranger (Photon) ne connaît que l'allemand, l'anglais et le français : pour une autre langue, elle donne les noms locaux.

### Ajouter ou changer une source

1. **Vérifier la source** avant tout : la licence doit autoriser la réutilisation ; puis la date, le format, les champs, les valeurs. Le workflow « Sonde » sert à cela. Ne rien deviner, et ne jamais récupérer de données sur les sites des opérateurs ni sur des cartes non ouvertes.
2. **La documenter** dans `docs/sources.md` : source, date, licence, méthode, limites.
3. **La déclarer** dans `pipeline/config.yaml` :
   - le pays, dans `countries` : `code` (de 1 à 15, unique : c'est la valeur du canal B), `eu_roaming`, `mask` (le contour), `slots` (4 au plus : des opérateurs nommés, ou des seuils `min_operators`) et `sources` ;
   - la source, dans `sources` : `country`, `type` (0, 1 ou 2), `name`, `attribution`, `url`, `licence`, `licence_url`, `services` (avec la technologie), `levels_kind` (`four`, `three` ou `binary`), `resolution_m`, plus les réglages propres au module (adresses, champs, valeurs). Une source désigne son module par la clé `module`, ou à défaut par son propre nom : c'est ainsi qu'un même module sert l'Andorre et Monaco.
4. **Écrire le module** dans `pipeline/czb/sources/`, en partant d'un module proche, et le commencer par un commentaire qui décrit la source vérifiée. Il hérite de `Source` (`base.py`) et fournit :
   - `remote_state()` : un petit état de la source en ligne (dates, tailles, nombres d'entités), qui sert à détecter une nouvelle version ;
   - `process()` : il remplit la grille commune avec `merge_level`, avec des niveaux de 0 à 3, uniquement dans les pixels de son pays. Il ajoute des points témoins pour chaque service et chaque emplacement (20 au moins pour chacun). Il renvoie au moins la date des données ;
   - si besoin, `available()` (par exemple quand une clé d'accès manque) et `prepare()`. Une source qui se révèle inutilisable en cours de route lève `SourceUnavailable` : la construction continue sans elle.
5. **L'enregistrer** dans `pipeline/czb/sources/__init__.py` (dictionnaire `REGISTRY`).
6. **Ajouter un test** sur des données synthétiques dans `pipeline/tests/`, sans réseau. Exemples : `test_ch_bakom.py` (GeoTIFF fabriqué), `test_it_agcom.py` et `test_es_mtd.py` (faux service ArcGIS de `fake_arcgis.py`).
7. Pour un nouveau pays, **ajouter un périmètre** dans `scopes` et son nom dans la liste `options` de `.github/workflows/build-data.yml`, pour pouvoir l'essayer seul. Puis lancer un essai.

Le site n'a pas besoin d'être modifié : il lit le nouveau pays dans le manifest. Seul le fond du mode Automatique se règle à part, dans `NATIONAL_BASEMAP` de `src/map/basemaps.ts` (à défaut, le pays reçoit OpenTopoMap).

### Changer l'emprise

Tout se règle dans `pipeline/config.yaml` :

- `countries` : les pays, dans l'ordre de priorité aux frontières. Pour chacun, le contour (`mask`) : adresse, couche, filtre `where`, nombre d'entités attendu `expect` (le pipeline s'arrête si le filtre ne trouve plus ce qu'il doit), fourchette de surface `expect_area_km2` pour un contour tiré d'OpenStreetMap, et mention à citer `credit`.
- Les filtres des sources doivent suivre le contour. Pour l'Italie : `where: "COD_REG IN (1, 2, 7)"` et `expect: 3` dans le masque, et `regions: [1, 2, 7]` dans `it_agcom`. Pour l'Espagne : une adresse de contour par communauté autonome (`nationalcode`) et `expect: 4`, et `regions: ["02", "09", "15", "16"]` dans `es_mtd`.
- La France est prise en entier (les départements dont le code a 2 caractères, Corse comprise), sauf dans un périmètre qui donne une liste de `departements`.
- `scopes` : les périmètres. `production` : ce que le site en ligne utilise.
- `limits` : 70 Mo visés par archive, 90 Mo au plus, 900 Mo pour tout le site. `grid.block_zoom` règle la taille des blocs.

Côté site, `MAX_BOUNDS` dans `src/config.ts` limite la zone où la carte peut aller (c'est aussi la zone de la recherche à l'étranger), et `INITIAL_VIEW` est la vue de départ.

## Développement local

### Le site

Il faut Node 22 (la version des workflows) et npm.

| Commande | Effet |
|---|---|
| `npm ci` (ou `npm install`) | installe les dépendances |
| `npm run dev` | serveur de développement Vite. L'adresse locale s'affiche dans le terminal ; le site est sous `/carte-zones-blanches/` |
| `npm test` | lance les tests Vitest une fois |
| `npm run test:watch` | relance les tests à chaque modification |
| `npm run typecheck` | vérifie les types TypeScript |
| `npm run build` | vérifie les types, puis construit le site dans `dist/` |
| `npm run preview` | sert `dist/` en local, par exemple pour essayer le Service Worker (absent de `npm run dev`) |

Pour avoir la couche réseau en local, mettre `manifest.json` et les archives `.pmtiles` d'une release de données dans `public/data/` (ce dossier est ignoré par git). Avec l'outil `gh` de GitHub :

```bash
gh release list --limit 10
gh release download data-AAAA-MM-JJ --dir public/data --pattern '*.pmtiles' --pattern 'manifest.json'
```

On peut y mettre de la même façon le résultat d'un essai (artefact « donnees ») ou d'une construction locale (`pipeline/out/`). Sans données, le site marche, mais sans couche réseau.

### Le pipeline

Il faut Python 3, GDAL avec son module Python (`osgeo`), NumPy, 7-Zip (`7z`) et les paquets de `pipeline/requirements.txt`. Le plus simple est l'image des workflows, `ghcr.io/osgeo/gdal:ubuntu-small-3.13.3`. Dans un conteneur de cette image, à la racine du dépôt, ce sont les commandes du job « Pipeline » de `.github/workflows/ci.yml` :

```bash
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends p7zip-full python3-pip
python3 -m pip install --break-system-packages -q -r pipeline/requirements.txt
cd pipeline && python3 -m pytest -q tests
```

Les tests n'utilisent que des données synthétiques et n'ont pas besoin du réseau.

Une vraie construction a besoin d'Internet pour joindre les sources. Par exemple, sur le petit périmètre des Hautes-Alpes (il télécharge quand même les 4 fichiers 4G de l'Arcep pour toute la métropole, environ 1,1 Go en tout) :

```bash
cd pipeline
python3 -m czb.cli build --scope hautes-alpes --services data
python3 -m czb.cli verify --out out
mkdir -p ../public/data && cp out/*.pmtiles out/manifest.json ../public/data/
```

Le résultat est dans `pipeline/out/`, les fichiers de travail dans `pipeline/work/` (deux dossiers ignorés par git). Pour l'Andorre et Monaco, il faut la variable d'environnement `OPENCELLID_TOKEN` ; sans elle, ces pays sont laissés de côté, avec un message.

### La vérification dans un navigateur

Les mêmes commandes que le workflow « Vérification » :

```bash
cd e2e
npm install --no-audit --no-fund
npx playwright install --with-deps chromium
SITE_URL=https://nathancouturier.github.io/carte-zones-blanches/ node verif.mjs
```

`SITE_URL` désigne le site à vérifier (par défaut, le site en ligne). `SANS_FONDS=1` saute les contrôles qui ont besoin des fonds de carte et de la recherche. `CAPTURES_DANS_LES_LOGS=1` écrit aussi les captures dans la sortie. Les captures sont enregistrées dans `e2e/captures/` (ignoré par git). Le script se termine en erreur si un contrôle échoue.

## Limites

- **Couverture théorique.** Les cartes officielles sont des simulations ou des déclarations des opérateurs, pas des mesures. Sur le terrain, le relief, la végétation, la météo et votre téléphone changent le résultat : « Couverture théorique, des écarts locaux sont possibles. » En montagne, ne comptez pas sur votre seul téléphone pour donner l'alerte.
- **Suisse, Italie, Espagne : « couvert » ou « non couvert » seulement.** Ces trois sources n'ont pas de niveau de qualité. « Bonne couverture » y veut dire « couvert » : on n'y voit jamais d'orange, et l'affichage par défaut n'y montre que le rouge des zones sans couverture. Ce n'est pas comparable aux 4 niveaux de l'Arcep. Les critères diffèrent aussi : en Espagne, un signal 4G d'au moins -115 dBm sous 1 GHz et -117 dBm au-dessus ; en Suisse, la couverture extérieure annoncée par les opérateurs ; en Italie, le critère n'est pas documenté dans les textes lus.
- **Sources agrégées.** En Suisse et en Italie, la source dit combien de réseaux couvrent un lieu, pas lesquels. À l'étranger, la couverture réelle dépend aussi des accords d'itinérance de votre opérateur. La Suisse, l'Andorre et Monaco ne font pas partie de l'itinérance de l'Union européenne. Les données italiennes datent du 27 janvier 2026.
- **Espagne : données de 2024.** Situation au 30 juin 2024 : c'est l'édition la plus récente liée par le site du ministère au 14 novembre 2026. La vue par opérateur peut sous-estimer la couverture des clients d'opérateurs hébergés sur un autre réseau (opérateurs virtuels, itinérance nationale), et Digi n'apparaît pas dans les données. « Tous opérateurs du pays » est la vue la plus sûre.
- **Appels et SMS : France seulement.** Les sources étrangères utilisées ne donnent que la 4G, et l'estimation ne porte que sur la 4G et la 5G.
- **Zones estimées (Andorre, Monaco) : les données.** Elles ne sont pas encore construites (voir [le secret OPENCELLID_TOKEN](#andorre-et-monaco--créer-le-secret-opencellid_token)). Les positions d'OpenCellID sont estimées à partir de mesures faites par les téléphones de bénévoles : ce ne sont pas des positions de pylônes, et seules les cellules vues dans les 18 derniers mois sont publiées. Elles sont très peu nombreuses : dans toute la base OpenCellID, le 14 novembre 2026, l'Andorre comptait 344 cellules 4G et 11 cellules 5G, Monaco 55 cellules 4G et aucune 5G. À Monaco, seules les cellules du code pays mobile monégasque (212, celui de Monaco Telecom) sont lues : les réseaux français captés à Monaco ne comptent pas.
- **Zones estimées : la fiabilité.** Ni la puissance, ni l'orientation des antennes, ni la végétation fine ne sont prises en compte. Lors du calage sur la France, une zone estimée « bonne » était réellement couverte dans 95 à 99 % des cas. Mais une zone blanche estimée n'était juste qu'à 81 % avec des positions d'antennes exactes, et environ une fois sur deux avec des positions approximatives et des antennes manquantes, ce qui ressemble davantage à OpenCellID. Ces erreurs de position étaient simulées : la fiabilité réelle avec les données d'OpenCellID n'est pas mesurée. Une antenne absente de la base crée une fausse zone blanche. Ne comptez pas sur une zone estimée pour un appel d'urgence.
- **Résolution.** Un pixel du zoom 12 fait 26 à 28 m au sol dans les Alpes et les Pyrénées. Les sources sont souvent plus grossières : `config.yaml` annonce environ 50 m pour l'Arcep, 100 m pour la Suisse et l'Italie, 38 m pour l'Espagne, 30 m pour l'estimation.
- **Frontières.** Les contours des pays viennent de producteurs différents et ne coïncident pas exactement. Le pipeline donne chaque pixel disputé à un seul pays et comble les petits interstices. Une bande étroite le long d'une frontière peut pourtant sortir « sans couverture » ou « hors zone » à tort, surtout du côté italien. La partie française du Léman, le Liechtenstein et quelques enclaves (Büsingen, Campione d'Italia, Treviño, Valle de Villaverde) restent hors zone.
- **PNG plutôt que WebP sans perte.** Le cahier des charges admettait le WebP sans perte s'il était plus léger. Les tuiles restent en PNG : le décodeur de secours en JavaScript ne lit que le PNG, et c'est lui qui garantit des pixels exacts sur tous les navigateurs. Le gain de taille du WebP sur ces tuiles n'est pas vérifié.
- **Hors ligne.** Le fond OpenTopoMap (OpenStreetMap) n'est jamais préchargé : c'est un serveur bénévole, qui demande d'éviter les téléchargements en masse. Or c'est le fond du mode Automatique en Italie, en Andorre et à Monaco : pour préparer un tracé dans ces pays, il faut choisir un autre fond, s'il couvre la zone. Les autres fonds sont plafonnés (900 ou 600 tuiles) et perdent leurs zooms les plus fins sur un long tracé. L'estompage du relief n'est pas enregistré, la recherche de lieux ne marche pas sans réseau, et un seul tracé est gardé. Le navigateur peut effacer ces données s'il manque de place ; le site lui demande de les garder.
- **Fonds de carte.** OpenTopoMap est un service bénévole, sans garantie de disponibilité. Si le style vectoriel du Plan IGN ne se charge pas, le site affiche le Plan IGN en images.
- **Mises à jour à la main.** Les nouveaux millésimes des contours et une nouvelle édition de la carte espagnole publiée à une autre adresse ne sont pas détectés automatiquement ; pour la carte italienne, ce point n'est pas vérifié (voir [Mettre à jour les données](#mettre-à-jour-les-données)).

## Vie privée

- Aucun cookie, aucun outil de mesure d'audience, aucun compte.
- Le GPX est lu et analysé dans le navigateur. Il n'est envoyé nulle part, et le GPX enrichi est fabriqué dans le navigateur.
- Le site télécharge les tuiles des fonds de carte de la zone affichée (les serveurs de ces fonds voient donc la zone regardée, comme pour toute carte en ligne) et les données de couverture, servies par le site lui-même. Le mode hors ligne télécharge en plus le couloir du tracé, quand on le demande.
- La recherche de lieux n'interroge l'IGN et Photon que quand on tape dans le champ de recherche. Elle leur envoie le texte tapé ; Photon reçoit aussi la langue et le centre de la carte, pour classer les résultats proches.
- La position donnée par « Ma position » sert seulement à placer la carte.
- La langue et les réglages sont mémorisés dans le navigateur (`localStorage`). Le mode hors ligne range ses fichiers dans le cache du navigateur.

## Licences et crédits

Chaque source a sa licence et ses mentions obligatoires. Le site affiche celles des fonds et des données de couverture en pied de carte et dans le panneau « Sources ». Sur téléphone, le texte du pied de carte n'apparaît qu'après un appui sur le bouton « © » : c'est un écart, pas encore corrigé, avec ce que demandent IGN España, OpenTopoMap, OpenCellID et OpenStreetMap (une mention visible sans action de l'utilisateur). Le détail (texte exact des mentions, adresses, dates de lecture des conditions) est dans [docs/sources.md](docs/sources.md). En résumé :

- couverture : Arcep (Licence Ouverte / Open Licence, Etalab) ; OFCOM (géodonnées de la Confédération, utilisation libre, source à citer) ; AGCOM (CC BY 4.0, avec un logo et une phrase à afficher, logo dans `public/licences/agcom-bbmap.jpg`) ; ministère espagnol (aucune licence attachée à la carte ; le site du ministère publie des conditions générales de réutilisation qui demandent de citer la source et la date, mais aucun texte ne dit qu'elles visent cette carte : lecture raisonnable, pas une autorisation écrite) ;
- zones estimées : OpenCellID (CC BY-SA 4.0 : les zones estimées en sont dérivées) et Copernicus DEM (mention obligatoire) ;
- fonds de carte : IGN (Géoplateforme), swisstopo, IGN España (CC BY 4.0), OpenTopoMap (CC BY-SA, données © les contributeurs d'OpenStreetMap) ;
- recherche de lieux : géocodage de la Géoplateforme (IGN) ; Photon (komoot), données © les contributeurs d'OpenStreetMap ;
- contours des pays : Etalab (d'après ADMIN EXPRESS de l'IGN), swisstopo, ISTAT (CC BY 4.0), IGN España (CC BY 4.0), OpenStreetMap (ODbL 1.0) ;
- GPX de test de `samples/` : chemins © les contributeurs d'OpenStreetMap (ODbL 1.0), altitudes Copernicus DEM.

Le site s'appuie sur MapLibre GL JS, pmtiles, @tmcw/togeojson, fast-png et Vite ; le pipeline sur GDAL, NumPy, Pillow, PyYAML et la bibliothèque Python pmtiles.

Licence du code : `package.json` indique MIT, mais le dépôt n'a pas de fichier de licence. À confirmer par le propriétaire.
