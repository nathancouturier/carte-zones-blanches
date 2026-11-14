# Carte des zones blanches

Une carte de randonnée qui montre où il y a du réseau mobile et où il n'y en a pas : en France métropolitaine et en Corse, en Suisse, dans l'Italie frontalière (Val d'Aoste, Piémont, Ligurie), dans l'Espagne pyrénéenne (Catalogne, Aragon, Navarre, Pays basque), en Andorre et à Monaco. On importe un tracé GPX (le fichier d'un parcours, tel que l'enregistre une montre ou une application de randonnée) et on obtient la liste des portions du parcours sans réseau. Les six pays sont présents dans les données en ligne (voir [Pays couverts et nature des données](#pays-couverts-et-nature-des-données)).

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
- [Décisions laissées au propriétaire](#décisions-laissées-au-propriétaire)
- [Réglages que le propriétaire peut revoir](#réglages-que-le-propriétaire-peut-revoir)
- [Vie privée](#vie-privée)
- [Licences et crédits](#licences-et-crédits)

## Ce que fait le site

La carte affiche, par-dessus un fond de carte de randonnée, la couverture mobile théorique publiée par les autorités de chaque pays, ou une estimation là où il n'existe pas de source officielle exploitable. Par défaut, seuls les problèmes sont dessinés : en rouge les zones sans couverture, en orange la couverture limitée. Un GPX importé est découpé en portions selon la couverture, et un rapport liste les zones blanches avec leurs kilomètres et leurs altitudes.

Sur téléphone, les panneaux s'ouvrent en bas de l'écran. Sur ordinateur (fenêtre d'au moins 900 px de large), ils s'ouvrent sur le côté. Rien n'est empilé : chaque panneau s'ouvre au clic, et ouvrir un panneau ferme la recherche.

### Mode d'emploi

- **Carte.** Plein écran, centrée sur la France au départ. Elle reste orientée au nord. L'adresse de la page garde la position de la carte (par exemple `#11/44.9/6.42` : zoom, latitude, longitude) : on peut la mettre en favori ou l'envoyer.
- **Loupe.** Recherche d'un lieu avec suggestions, dès 3 caractères : en France par le géocodage de l'IGN (Corse comprise), à l'étranger par Photon (données OpenStreetMap). Les lieux du premier service qui répond s'affichent tout de suite. Un service qui ne répond pas en 5 secondes est signalé sous la liste, et les lieux de l'autre restent. Quand le centre de la carte est hors de France, les lieux étrangers passent en premier. Chaque lieu porte son origine (IGN ou OSM) ; pour l'IGN, le type d'adresse, la commune et le département sont traduits. Entrée choisit le premier lieu trouvé pour la saisie en cours, jamais celui d'une saisie précédente.
- **Ma position.** Le bouton en haut à droite, à côté de la roue dentée, affiche votre position et centre la carte dessus. Le point suit ensuite la marche tant que la page est visible, sans déplacer la carte : un nouvel appui recentre. Si la carte bouge entre l'appui et l'arrivée de la position (geste, import d'un GPX, recherche), elle n'est pas recentrée. Le suivi s'arrête quand la page est cachée (pour la batterie) et reprend à son retour ; le point devient gris tant que la position n'est plus à jour. Un message dit pourquoi la position manque : autorisation refusée, position indisponible, ou GPS qui cherche encore au bout de 15 secondes.
- **Réseau.**
  - Service : « Internet mobile » ou « Appels et SMS ». Les appels et SMS n'existent que pour la France ; le panneau dit pour quels pays le service choisi manque.
  - Opérateur en France : « Tous opérateurs », Orange, SFR, Bouygues Telecom ou Free. « Tous opérateurs » donne, en chaque point, le meilleur niveau parmi les opérateurs. C'est ce qui compte pour le 112, qui passe par n'importe quel réseau.
  - Rubrique repliable « À l'étranger » : « Tous opérateurs du pays » par défaut, car la couverture réelle dépend des accords d'itinérance de votre opérateur. Quand la source le permet, on peut choisir un opérateur (Espagne) ou un nombre de réseaux (Suisse, Italie). En Andorre et à Monaco, il n'y a pas de choix.
  - Case « Afficher toute la couverture » : ajoute la bonne et la très bonne couverture, en vert. Les zones estimées sont hachurées. Un curseur règle l'opacité, et le panneau donne la légende. Ces réglages sont mémorisés dans le navigateur.
  - Là où le niveau d'une zone estimée n'est pas dessiné (la « bonne » couverture, dans l'affichage par défaut), elle reçoit des hachures grises légères, distinctes de celles des niveaux, et la légende le dit. <!-- À VÉRIFIER : lot en cours -->
- **Fond.** « Automatique » (le choix par défaut) prend le fond national du pays au centre de la carte : Plan IGN classique en France, swisstopo en Suisse, IGN España en Espagne, OpenTopoMap (données OpenStreetMap) ailleurs, y compris hors de la zone couverte par les données. Le pays est lu dans les données de couverture. Si le centre tombe hors des données (en mer près d'une côte, par exemple), c'est le pays le plus présent dans le reste de la vue qui décide. Sans réseau, le mode Automatique ne passe qu'à un fond enregistré pour le hors ligne. On peut aussi choisir soi-même Plan IGN classique, Plan IGN standard, swisstopo, IGN España, OpenTopoMap ou les photos aériennes de l'IGN, et ajouter l'estompage du relief de l'IGN (France seulement). Le Plan IGN s'affiche d'abord en images, le temps que son style vectoriel arrive (8 secondes au plus) ; si ce style ne vient pas ou ne peut pas être lu, la version en images reste, et un message le dit.
- **Importer un GPX.** Par le bouton, ou en glissant le fichier sur la carte (ordinateur). Le site lit les traces, sinon les routes. Plusieurs traces ou segments forment un seul parcours, dans l'ordre du fichier. Il respecte l'encodage du fichier : UTF-8 par défaut, UTF-16, ou celui que déclare son en-tête (ISO-8859-1, par exemple). Il accepte aussi les éléments préfixés (`gpx:trk`). Les points aberrants sont écartés : position (0, 0), ou point isolé à plus de 10 km de ses deux voisins. Une trace est coupée là où elle saute de plus de 10 km d'un point au suivant, et ce saut ne compte ni dans la distance ni dans l'analyse. Le panneau signale ces corrections. Un fichier de plus de 41,9 millions d'octets est refusé. Le tracé s'affiche avec un liseré blanc, des repères de départ et d'arrivée, et la carte zoome dessus. Une fois l'analyse faite, il prend les couleurs de la couverture : rouge, orange, vert, et gris là où il n'y a pas de données.
- **Rapport** (le bouton apparaît après l'import). On y trouve :
  - la distance, le dénivelé et les altitudes extrêmes (quand plus de la moitié des points ont une altitude), les pays traversés, l'opérateur appliqué dans chaque pays, avec un lien « Modifier » ;
  - la part du parcours par niveau, pour l'opérateur choisi (si vous en avez choisi un) et pour tous opérateurs. Les portions hors des données de couverture, et celles où la source ne fournit pas le service choisi, sont données à part et exclues des pourcentages ;
  - la liste des zones blanches pour l'opérateur appliqué, par exemple « km 12,4 à 14,1, soit 1,7 km, altitude 1 850 à 2 100 m, Italie, estimée ». Toucher une zone la met en surbrillance et zoome dessus ;
  - des avertissements : pays hors de l'itinérance de l'Union européenne (Suisse, Andorre, Monaco : vérifiez votre forfait), partie du parcours estimée, source qui dit seulement « couvert » ou « non couvert », service absent dans un pays traversé.

  Les portions hors des données portent le libellé « hors zone », avec une courte explication, dans le panneau, dans le texte du rapport et dans le profil. <!-- À VÉRIFIER : lot en cours --> Sur téléphone, le bouton « Réduire le panneau » ramène le rapport à son titre pour laisser voir la carte ; le tracé y est recadré.
- **Profil altimétrique** (dans le rapport, quand plus de la moitié des points du tracé ont une altitude, lue dans le GPX ou interpolée). Il est coloré selon la couverture. Chaque colonne prend la couleur de la pire couverture de sa portion : une courte zone blanche reste visible sur un long parcours. Les portions estimées sont hachurées. Survoler ou toucher le profil place un repère sur la carte et affiche le kilomètre, l'altitude et la couverture. Au clavier, le profil se parcourt avec les flèches (1 % du tracé par appui), les touches Page (10 %), Début et Fin ; les lecteurs d'écran annoncent la part du parcours sans couverture.
- **Emporter le résultat.** « Télécharger le GPX enrichi » donne le GPX d'origine avec un point de passage au début et à la fin de chaque zone blanche (« Zone blanche 1, début », etc.), pour une montre ou une application GPS. `rando.gpx` devient `rando-zones-blanches.gpx` (le suffixe suit la langue). Le fichier est toujours écrit en UTF-8. Si l'on réimporte un GPX déjà enrichi, ses anciens points de zone blanche sont remplacés au prochain export. « Copier le rapport » met le rapport en texte dans le presse-papiers. Ce texte est aussi visible sous « Rapport en texte ».
- **Hors ligne** (dans le rapport). « Préparer ce tracé pour le hors ligne » enregistre dans le navigateur le GPX, une copie du manifest des données, la couverture d'un couloir de 700 m de part et d'autre du tracé (zooms 8 à 12) et le fond de carte le long du parcours, quand son fournisseur l'autorise. En mode Automatique, chaque portion du tracé reçoit le fond national de son pays ; l'estompage du relief suit s'il est affiché. « Annuler l'enregistrement » l'arrête. Un enregistrement interrompu reste visible, marqué incomplet : « Reprendre l'enregistrement » le termine sans retélécharger ce qui est déjà là. À la fin, le panneau dit ce qui a été enregistré et ce qui manque, fond par fond. Sans réseau, ou quand le réseau ne livre pas le manifest des données en 3 secondes, le site travaille sur la copie enregistrée et recharge tout seul le tracé préparé. Le panneau « Importer un GPX » propose aussi « Reprendre le tracé enregistré ». Un seul tracé est gardé : en préparer un autre remplace le précédent. Si les données de couverture ont été republiées depuis, le panneau invite à mettre l'enregistrement à jour. « Supprimer les données hors ligne » efface les tuiles et le tracé enregistrés, après confirmation. À faire avant de partir, avec du réseau (voir [Limites](#limites)).
- **Langues.** Bouton « Paramètres » (roue dentée), puis « Langue » : Français, Español, Català, Italiano, Deutsch. Le choix est mémorisé dans le navigateur. Le paramètre `?lang=` dans l'adresse force une langue, par exemple https://nathancouturier.github.io/carte-zones-blanches/?lang=es. Les nombres et les distances suivent la langue choisie, y compris les nombres insérés dans les messages. <!-- À VÉRIFIER : lot en cours -->
- **Sources.** Les mentions des fonds et des données affichés sont en pied de carte, avec leurs liens. Le pied de carte crédite les données de chaque pays présent à l'écran, et ajoute le crédit d'OpenCellID quand une zone estimée est visible. Sur ordinateur, il reste visible. Sur téléphone, il est déplié au chargement, se replie au premier geste sur la carte, et le bouton « © » le rouvre ; la mention d'OpenTopoMap y prend sa forme courte. Le panneau « Sources » (lien « Sources » du pied de carte, ou « Paramètres » puis « Sources des données ») commence par la phrase « Couverture théorique, des écarts locaux sont possibles. » Il a une section par pays, ouverte d'emblée pour les pays à l'écran : source, date des données, méthode, licence (avec la phrase ou le logo que la licence impose), contour du pays, opérateurs. Il se termine par les crédits des fonds de carte et de la recherche.

  Le panneau dit aussi, dans les cinq langues, que les données d'origine ont été transformées pour ce site (rastérisées sur une grille commune, ramenées à des niveaux ou à des seuils). Pour une source estimée, il donne le nombre de sites d'antennes connus, avec une phrase qui rappelle que moins il y a de sites, moins l'estimation est fiable. Les noms des sources, les licences et les mentions de contour s'affichent dans la langue choisie quand le manifest en donne la traduction, sinon en français. Les mentions imposées dans une autre langue que celle de l'interface portent un attribut de langue. <!-- À VÉRIFIER : lot en cours -->

## Pays couverts et nature des données

| Zone | Source de la couverture | Nature | Choix proposés | Services | Date des données |
|---|---|---|---|---|---|
| France métropolitaine et Corse | Arcep, « Mon réseau mobile » (couvertures théoriques) | officielle par opérateur, 4 niveaux | Tous opérateurs, Orange, SFR, Bouygues Telecom, Free | internet mobile (4G), appels et SMS (2G et 3G) | 2e trimestre 2026 (situation au 30 juin 2026) |
| Suisse | OFCOM, atlas de la large bande | officielle agrégée, couvert ou non | Tous opérateurs du pays, Les 3 réseaux à la fois | internet mobile (4G) | 30 avril 2026 |
| Italie : Val d'Aoste, Piémont, Ligurie | AGCOM, Broadband Map | officielle agrégée, couvert ou non | Tous opérateurs du pays, Au moins 2 réseaux, Au moins 3 réseaux, Les 4 réseaux à la fois | internet mobile (4G) | 27 janvier 2026 |
| Espagne : Catalogne, Aragon, Navarre, Pays basque | Ministerio para la Transformación Digital y de la Función Pública, « Mapa de Servicios de Banda Ancha Móvil 2024 » | officielle par opérateur, couvert ou non | Tous opérateurs du pays, Movistar, Orange, Vodafone, Xfera Móviles | internet mobile (4G) | 30 juin 2024 |
| Andorre | estimation : antennes OpenCellID et relief Copernicus DEM | estimée, 3 niveaux | aucun choix : tous réseaux confondus | internet mobile (cellules 4G et 5G ; aucune cellule 5G dans le fichier lu) | mois du calcul |
| Monaco | la même estimation | estimée, 3 niveaux | aucun choix : cellules du code pays mobile monégasque seulement (voir [Limites](#limites)) | internet mobile (cellules 4G et 5G ; aucune cellule 5G dans le fichier lu) | mois du calcul |

Les six pays sont publiés : ils figurent tous dans la release de données en ligne, `data-2026-11-14-4`, construite le 14 novembre 2026, avec une estimation de novembre 2026 pour l'Andorre et Monaco. <!-- À VÉRIFIER : lot en cours -->

Ce que veulent dire ces mots :

- **Officielle par opérateur** : la source dit quel opérateur couvre chaque lieu.
- **Officielle agrégée** : la source dit combien de réseaux couvrent un lieu, mais pas lesquels. On choisit alors un seuil. Par exemple, « Les 3 réseaux à la fois » en Suisse montre où vous aurez du réseau quel que soit l'opérateur utilisé en itinérance.
- **Estimée** : il n'existe pas de carte officielle exploitable. La couverture est calculée (voir [L'estimation](#lestimation)). Ces zones sont hachurées sur la carte et dans le profil, et marquées « estimée » dans le rapport et dans le GPX enrichi.
- **Couvert ou non** : la source n'a pas de niveau de qualité. Sur la carte et dans le rapport, « bonne couverture » y veut dire « couvert ».

Ce tableau décrit ce que construit la configuration de production (`pipeline/config.yaml`). Le panneau « Sources » du site dit quels pays figurent vraiment dans les données publiées, avec la date de chaque source. Le détail des sources (adresses, licences, méthodes, limites) est dans [docs/sources.md](docs/sources.md).

### Andorre et Monaco : le secret OPENCELLID_TOKEN

L'estimation a besoin d'une clé d'accès gratuite à OpenCellID, la base d'antennes utilisée. Cette clé est rangée dans un secret du dépôt : une valeur que GitHub donne aux workflows sans jamais l'afficher. Le secret `OPENCELLID_TOKEN` existe depuis le 14 novembre 2026. Le premier téléchargement réel a réussi le même jour (run 43601236437) : le module trouve le lien du fichier dans la page des téléchargements d'OpenCellID, qui ne le montre qu'après l'envoi de la clé, et les fichiers des codes pays mobiles 213 (Andorre) et 212 (Monaco) ont été téléchargés et lus.

Si OpenCellID ne répond pas ou refuse la clé, la construction reprend la copie de travail d'un mois précédent quand elle existe (voir [Copies de travail](#copies-de-travail)). Si le secret n'existe pas, ou s'il n'y a pas de copie, elle laisse ces deux pays de côté : ils disparaissent de la carte, et le panneau « Sources » affiche « Pas encore de données pour : Andorre, Monaco ». Un tracé qui y passe est alors compté hors de la zone couverte, et le rapport ne peut pas y signaler la sortie de l'itinérance de l'Union européenne.

Pour créer ou remplacer la clé :

1. Créer un compte gratuit sur [opencellid.org](https://opencellid.org) (page d'inscription : https://my.opencellid.org/register). Se connecter, puis afficher la clé dans la rubrique « API Access Tokens » du tableau de bord.
2. Dans le dépôt GitHub : Settings, Secrets and variables, Actions, puis New repository secret (ou la modification du secret existant). Nom : `OPENCELLID_TOKEN`. Valeur : la clé.
3. Si les deux pays étaient absents, relancer le workflow « Données » : onglet Actions, « Données », « Run workflow », périmètre « production ». Le pipeline voit que la source est redevenue disponible et reconstruit les données. Il est inutile de cocher « Reconstruire même si aucune source n'a changé ». Sans cette relance, le passage mensuel suivant le fera.

La clé n'apparaît pas dans les journaux : GitHub masque les secrets, et le module retire la clé de ses propres messages. OpenCellID permet deux téléchargements par jour et par fichier : la copie de travail du mois, publiée avec la release, évite de retélécharger lors des constructions suivantes du même mois.

### L'estimation

Le module `estimation_opencellid` (réglages dans la section `estimation` de `pipeline/config.yaml`) procède ainsi :

1. Il lit les cellules 4G et 5G d'OpenCellID du pays et de ses abords (2 km). Il les regroupe par station, puis fusionne en un seul site les points à moins de 300 m l'un de l'autre.
2. Pour chaque site, GDAL calcule sur le relief (Copernicus DEM GLO-30, ramené sur la grille du projet), en chaque pixel, la hauteur au-dessus du sol qu'il faudrait pour voir l'antenne, placée à 30 m de haut. Le site est « visible » si cette hauteur ne dépasse pas 1,5 m (un téléphone tenu à la main), et « presque visible » s'il manque moins de 30 m.
3. Un pixel reçoit « bonne couverture » si un site est visible à 5 km au plus, presque visible à 1 km au plus, ou présent à 500 m au plus. Sinon, il reçoit « couverture limitée » avec les distances 15 km, 7,5 km et 2 km. Sinon, « pas de couverture ». « Très bonne couverture » n'est jamais attribué.

Cette règle a été calée sur la France, là où la vérité officielle existe : sites et cartes de l'Arcep dans les Hautes-Alpes et en Ariège, soit 21,7 millions de pixels comparés. Les résultats de ce calage sont dans [Limites](#limites).

Ce qu'a donné la construction de production n° 2 : <!-- À VÉRIFIER : lot en cours -->

- Andorre (code pays mobile 213) : 111 cellules dans le fichier (65 GSM, 41 LTE, 5 UMTS), 41 cellules 4G retenues, toutes du même code réseau, regroupées en 12 sites. Résultat : 85,2 % du pays sans couverture, 5,6 % de couverture limitée, 9,2 % de bonne couverture.
- Monaco (code pays mobile 212) : 1 813 cellules dans le fichier (16 GSM, 1 436 LTE, 361 UMTS), 1 433 cellules 4G retenues, toutes du même code réseau, en 109 stations (dont une trop dispersée pour être réunie) et 18 sites. Résultat : 100 % de bonne couverture.
- Aucune cellule « NR » (5G) dans ces deux fichiers : l'estimation repose en pratique sur la 4G.

## Architecture

### Le site

Le site est une seule page, construite avec Vite (l'outil qui assemble les fichiers du site) et TypeScript (du JavaScript dont les types sont vérifiés). Il utilise MapLibre GL JS (la carte), pmtiles (lecture des archives de tuiles), @tmcw/togeojson (lecture du GPX) et fast-png (décodeur PNG écrit en JavaScript, qui sert de contrôle et de secours). Il n'y a pas de serveur d'application : GitHub Pages sert des fichiers statiques sous `/carte-zones-blanches/` (réglage `base` de `vite.config.ts`). Au déploiement, les données de couverture sont posées dans `data/`, à côté de la page : un fichier `manifest.json` et une ou plusieurs archives `.pmtiles`. Ces données ne sont jamais enregistrées dans git : elles sont jointes aux releases `data-*` du dépôt, et le déploiement les copie dans le site.

```
index.html              la page
src/
  main.ts, app.ts       démarrage, puis chef d'orchestre (état, carte, données, interface)
  config.ts             constantes réglables : délais, seuils de l'analyse, recherche, vue de départ, emprise
  state.ts              état de l'application, réglages mémorisés
  coverage/             tuiles de couverture : encodage, manifest, lecture des archives, décodage, cache,
                        protocole MapLibre, couleurs, nouvelle publication des données
  gpx/                  lecture du GPX, rééchantillonnage, zones blanches, rapport, export
  map/                  fonds de carte, style MapLibre, carte, « Ma position »
  offline/              mode hors ligne : couloir de tuiles, enregistrement, liste de la coque du site
  search/               recherche de lieux
  ui/                   barres, panneaux, profil altimétrique
  i18n/                 traductions : index.ts, et un fichier JSON par langue dans locales/
public/
  sw.js                 Service Worker (mode hors ligne)
  licences/             logo exigé par la licence de l'AGCOM
  manifest.webmanifest  nom, icône et couleurs du site ajouté à l'écran d'accueil
tests/                  tests Vitest du site
samples/                deux GPX de test : test-alpes.gpx et test-pyrenees.gpx
e2e/verif.mjs           vérification du site en ligne dans un vrai navigateur (Playwright)
pipeline/               pipeline de données : Python et GDAL
  config.yaml           la référence : grille, limites, pays, sources, périmètres
  czb/                  grille, masques, canaux, tuiles, archives, manifest, SOURCES.md, test de cohérence,
                        copies de travail
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

Une source qui dit seulement « couvert » écrit le niveau 2. L'estimation n'écrit que 0, 1 ou 2. Le zoom 12 est la résolution de travail : un pixel y fait 38,2 m en projection Mercator, soit 26 à 28 m au sol dans les Alpes et les Pyrénées (la taille au sol varie avec la latitude). Les zooms inférieurs recopient le pixel central du carré qu'ils représentent (plus proche voisin). Il n'y a jamais de moyenne : elle mélangerait les bits et fausserait les données. Une tuile qui a peu de valeurs différentes est enregistrée en PNG à palette, plus léger. Pour l'affichage, du zoom 13 au zoom 16, le site fabrique lui-même les tuiles à partir de celle du zoom 12, en plus proche voisin : les hachures des zones estimées restent fines à l'écran. L'analyse des GPX lit toujours le zoom 12.

Ce choix donne peu de fichiers, un changement d'opérateur instantané, et les mêmes tuiles servent à l'affichage et à l'analyse des GPX.

### Le manifest

Le fichier `manifest.json`, publié avec les tuiles, dit au site tout ce qu'il doit savoir :

- la version du format, la date de génération des tuiles et le périmètre construit ;
- les tuiles : taille, zooms, format, zoom des blocs. Le format est toujours le PNG : le site refuse un manifest qui annonce du WebP ;
- l'emprise des données et une description de l'encodage en clair (`encoding`) ;
- les archives : nom, zooms, taille et, pour une archive découpée, la liste de ses blocs ;
- pour chaque pays : son code (canal B), son code ISO, l'itinérance de l'Union européenne (oui ou non), la mention de son contour (`boundary`), les noms de ses opérateurs quand la source ne les distingue pas (`operators`), et le contenu de chaque emplacement : un opérateur nommé, ou un seuil « au moins N réseaux » ;
- pour chaque source : type, nom, adresse, date des données, licence et son adresse, mention à afficher, phrase ou logo que la licence impose (`licenceNotice`, `licenceLogo`, `licenceLogoUrl`), services fournis, façon de lire les niveaux (`four`, `three` ou `binary`), technologie, résolution ;
- les pays prévus mais absents des données (`missing`), par exemple faute de clé d'accès.

Le manifest porte aussi, en champs facultatifs que le site lit quand ils existent : <!-- À VÉRIFIER : lot en cours -->

- par source, `nameI18n` et `licenceI18n`, et par pays, `boundary.textI18n` : les traductions du nom, de la licence et de la mention du contour, en dictionnaires par langue (es, ca, it, de). Le français reste dans `name`, `licence` et `boundary.text`. La mention d'une source estimée ne dit pas elle-même « estimation » : c'est le site qui l'ajoute, dans sa langue. Sa technologie s'écrit « 4G, 5G » ;
- pour une source estimée, `estimation` : le nombre de sites et de cellules utilisés, par exemple `{"sites": 12, "cells": 41}` ;
- dans `encoding`, une phrase qui dit ce que valent les emplacements qu'un pays ne déclare pas : l'emplacement i est le i-ème élément de la liste `slots` du pays ; au-delà, il est inutilisé et vaut toujours 0 ;
- la résolution de l'Arcep n'est pas donnée : aucun texte lu ne la documente.

Le décodeur du site est piloté par ce fichier. Pour chaque pays et chaque source, il fabrique une table de 256 cases qui donne, pour un octet R ou G, le niveau de l'opérateur choisi. Rien n'est codé en dur par pays : un pays ajouté dans le pipeline apparaît sur la carte sans toucher au code de la couche réseau. Un service absent d'une source (les appels et SMS hors de France) est lu « pas de donnée », jamais « pas de couverture ». Une adresse du manifest ne devient un lien que si elle commence par `https:`, et un logo de licence doit être un fichier du site.

### Affichage de la couche réseau

- Un protocole MapLibre personnalisé, `couverture://` (fonction `addProtocol`, fichier `src/coverage/protocol.ts`), répond aux demandes de tuiles de la carte. Il trouve l'archive qui contient la tuile, la lit, la décode (`createImageBitmap` avec `premultiplyAlpha` et `colorSpaceConversion` à `none`, puis `getImageData`), la recolore selon les réglages et la rend à MapLibre.
- Un cache LRU garde les 160 dernières tuiles décodées (`src/coverage/store.ts`) : quand il est plein, il oublie la tuile servie le moins récemment. Quand un réglage change (opérateur, service, affichage), la couche est redessinée à partir du cache, sans rien retélécharger.
- L'analyse d'un GPX lit ses tuiles sans chasser celles de l'affichage : même après un très long tracé, un changement de réglage ne relit rien dans les archives. <!-- À VÉRIFIER : lot en cours -->
- « Tous opérateurs » est le maximum des emplacements du pays, calculé dans le navigateur.
- Décodeur de secours : certains navigateurs ajoutent exprès un léger bruit aux pixels relus d'un canvas, pour gêner le pistage. Les 3 premières tuiles sont donc décodées une seconde fois en JavaScript pur. Au moindre écart, le site passe pour de bon sur ce décodeur, qui donne des pixels exacts.
- La couche est dessinée en plus proche voisin (`raster-resampling: nearest`), sous les libellés du fond : juste avant la première couche `symbol` du style. Sur les fonds en images, les noms font partie de l'image et passent donc sous la couche.
- Chaque lecture de tuile a un délai maximal de 20 secondes. Une tuile qui n'a pas pu être lue est dessinée en gris rayé (« données indisponibles »), pour ne pas passer pour une zone couverte, et un bandeau propose « Réessayer ». Quand le réseau revient, ces tuiles sont relues toutes seules.
- Nouvelle publication pendant qu'un onglet est ouvert : les anciennes archives disparaissent du serveur. Sur une erreur de lecture, le site relit `manifest.json` (au plus une fois par minute tant que rien ne change). Si les données ont changé, il repart sur les nouvelles, redessine la couche, le dit, et refait l'analyse du tracé chargé sans rouvrir le rapport ni déplacer la carte.
- Plusieurs archives : si les tuiles dépassent 70 Mo au total, le pipeline écrit une archive d'aperçu (zooms 0 à 7) et des archives par blocs. Un bloc est une tuile du zoom 8 avec tout ce qu'elle contient aux zooms 8 à 12. Le manifest donne les blocs de chaque archive, et le site choisit la bonne archive selon x et y.
- Les noms des archives contiennent la date et l'heure de la construction (`couverture-AAAAMMJJ-HHMM-NN.pmtiles`). Un navigateur ne peut donc pas mélanger d'anciennes tuiles gardées en cache avec un nouveau manifest.

### Analyse d'un GPX

1. Le GPX est lu avec @tmcw/togeojson : les traces, ou à défaut les routes. L'encodage vient de la marque d'ordre des octets s'il y en a une, sinon de la déclaration en tête du fichier, sinon c'est l'UTF-8. Les points aberrants sont écartés et une trace est coupée à ses sauts de plus de 10 km (voir le [mode d'emploi](#mode-demploi)). Les routes, aux points souvent très espacés, ne sont pas coupées. S'il ne reste rien d'utilisable après les coupures, c'est une trace dessinée à la main avec des points très espacés : elle est gardée telle quelle.
2. Le parcours est rééchantillonné tous les 20 m. La distance est géodésique : mesurée sur une sphère du rayon moyen de la Terre. Les sauts entre deux segments ne comptent pas dans la distance.
3. Les altitudes manquantes sont interpolées entre les deux points connus les plus proches d'un même segment. Avant le premier et après le dernier point connu, l'altitude reste inconnue. Le dénivelé, les altitudes extrêmes et le profil ne sont annoncés que si plus de la moitié des points ont une altitude ; l'altitude d'une zone blanche, que si plus de la moitié de ses points en ont une. Le dénivelé ignore les variations de moins de 5 m, dues au bruit du GPS.
4. Pour chaque point, le site lit au pixel près les tuiles du zoom 12 : niveau pour l'opérateur choisi et pour tous opérateurs, pays, type de source. Chaque tuile n'est lue qu'une fois, 6 à la fois.
5. Chaque point représente le parcours jusqu'à mi-chemin de ses voisins. Les points sans couverture qui se suivent forment des tronçons. Deux tronçons séparés par moins de 50 m sont fusionnés. Une zone blanche fait au moins 100 m. Une zone ne franchit jamais une interruption du parcours : deux segments éloignés de plus de 50 m. Deux segments plus proches (pause du GPS, trace coupée en deux) forment un parcours continu.
6. La longueur affichée d'une zone est tirée de ses bornes arrondies à 100 m : la soustraction que fait le lecteur tombe juste.
7. Les points hors de la zone couverte par les données sont « hors zone ». Les points où la source ne fournit pas le service choisi sont « sans donnée pour ce service ». Les deux sont exclus des pourcentages.
8. Les valeurs brutes des pixels sont gardées : changer d'opérateur ou de service refait le rapport sans rien relire.

Les seuils sont des constantes de `src/config.ts` : `RESAMPLE_STEP_M` (20 m), `WHITE_ZONE_MIN_LENGTH_M` (100 m), `WHITE_ZONE_MERGE_GAP_M` (50 m), `SEGMENT_JOIN_MAX_M` (50 m), `ELEVATION_THRESHOLD_M` (5 m), `ELEVATION_MIN_SHARE` (0,5), `TRACK_MAX_JUMP_M` (10 km), `MAX_GPX_BYTES` et `SAMPLING_CONCURRENCY` (6). Voir [Réglages que le propriétaire peut revoir](#réglages-que-le-propriétaire-peut-revoir).

### Mode hors ligne

Le Service Worker (`public/sw.js`) est un petit programme que le navigateur garde à côté du site. Il sert les fichiers enregistrés quand il n'y a pas de réseau.

- **La coque du site** : `index.html` et tous les fichiers qu'il charge. À la construction, `src/offline/shell.ts` en dresse la liste, en tire une version (une empreinte de leur contenu) et l'écrit dans `dist/sw.js`. Le Service Worker enregistre toute la liste d'un coup à son installation, dans un cache propre à cette version, et vérifie qu'`index.html` est bien celui de cette version. Les coques des versions précédentes sont effacées : `index.html` vient toujours avec ses propres scripts. Avant de préparer un tracé, la page vérifie que la coque est complète ; sinon elle le dit.
- **La page et ses fichiers** : quand une coque complète est enregistrée, ils viennent de cette coque, quels que soient `?lang=` et les autres paramètres de l'adresse. Il n'y a jamais de mélange de versions. Une nouvelle version du site s'installe en arrière-plan et sert à la visite suivante. À la première visite, avant que la coque soit complète, la page vient du réseau. <!-- À VÉRIFIER : lot en cours -->
- **Le manifest des données** : celui du réseau s'il arrive en 3 secondes (`NETWORK_TIMEOUT_MS`), sinon la copie enregistrée avec le tracé préparé ; sans copie, on attend le réseau. Une réponse en erreur du serveur ne remplace pas la copie enregistrée. <!-- À VÉRIFIER : lot en cours --> La copie porte un en-tête (`x-czb-copie-locale`) : la page sait ainsi qu'elle travaille sur les données enregistrées, et recharge le tracé préparé.
- **Les tuiles de fond, styles et polices**, servis par d'autres sites : la copie locale si elle existe, sinon le réseau. Seul le bouton « Préparer ce tracé pour le hors ligne » remplit ce cache, tracé par tracé.
- **Les tuiles de couverture** : les lectures partielles des archives PMTiles ne passent pas par le Service Worker. La page enregistre elle-même les tuiles du couloir (zooms 8 à 12), rangées sous le nom de leur archive (`hors-ligne/couverture/<archive>/z/x/y`), et les relit avant le réseau (`src/offline/manager.ts`). Un tracé préparé ne dépend donc plus du réseau, et les tuiles d'une édition des données ne sont jamais lues avec le manifest d'une autre.

Le préchargement est piloté par la page. S'il est interrompu (onglet fermé, réseau perdu), l'enregistrement reste marqué incomplet et se reprend ensuite sans retélécharger ce qui est déjà là. Le Service Worker, lui, ne fait que servir les copies. Avant de télécharger, le site demande au navigateur de garder ces données même quand la place manque ; s'il ne le promet pas, le panneau le dit.

Le fond n'est préchargé que si son fournisseur l'accepte, et dans une limite (champ `offline` de `src/map/basemaps.ts`) :

| Fond | Préchargement | Plafond par tracé | Zooms | Requêtes simultanées | Débit maximal |
|---|---|---|---|---|---|
| Plan IGN classique et standard (tuiles vectorielles, plus le style, les icônes et les polices) | oui | 900 tuiles | 7 à 15 | 4 | pas d'autre frein |
| Plan IGN en images (quand le style vectoriel est injoignable) | oui | 600 tuiles | 9 à 15 | 4 | pas d'autre frein |
| Photos aériennes (IGN) | oui | 600 tuiles | 9 à 16 | 4 | pas d'autre frein |
| Estompage du relief (IGN), s'il est affiché | oui | 600 tuiles | 9 à 15 | 4 | pas d'autre frein |
| swisstopo | oui | 600 tuiles | 9 à 15 | 2 | 2 requêtes par seconde |
| IGN España | oui | 600 tuiles | 9 à 15 | 2 | 5 requêtes par seconde |
| OpenTopoMap | non | aucun | aucun | aucune | aucun |

Ces plafonds et ces freins sont des choix du projet, compatibles avec les conditions lues chez chaque fournisseur (voir [docs/sources.md](docs/sources.md)). Si le couloir demande plus de tuiles que le plafond, les zooms les plus fins sont abandonnés. L'écart entre deux requêtes se compte depuis le départ réel de la précédente. Sur une réponse 429 ou 503 (trop de requêtes, ou service indisponible), tout ce fond attend la durée de l'en-tête `Retry-After` (5 secondes s'il est absent ou illisible), puis reprend. Il est abandonné après 3 refus d'une même tuile, une attente demandée de plus de 60 secondes, ou 8 échecs réseau d'affilée ; le panneau dit alors combien d'éléments manquent. Rien n'est demandé hors de l'emprise du fournisseur, et `tile.openstreetmap.org` n'est jamais préchargé (ses conditions interdisent l'usage hors ligne). Le Service Worker n'est installé que par la version construite du site, pas par `npm run dev`.

### Tests

Vitest et pytest sont des outils qui lancent des tests automatiques ; Playwright pilote un vrai navigateur.

- **Site** (`npm test`, Vitest, dossier `tests/`) : 212 tests dans 17 fichiers au commit `deadf53`, tous réussis, et `npx tsc --noEmit` sans erreur. <!-- À VÉRIFIER : lot en cours --> Ils couvrent l'encodage et le décodage des 4 canaux, la lecture du manifest et les tables de niveaux ; la lecture du GPX (trace, route, multi-segments, sans altitude, encodages, préfixes, points aberrants, sauts), le rééchantillonnage, les zones blanches, les kilomètres, les statistiques, le rapport en texte et l'export ; le profil altimétrique (clavier, portions estimées) ; le mode hors ligne (couloir, coque du Service Worker, enregistrement, reprise, fonds au rythme de chaque fournisseur, mode Automatique sans réseau) ; la recherche (services lents, en panne ou annulés) et le style de la carte ; « Ma position » ; la lecture des archives (lectures qui calent, tuile illisible, nouvelle publication) ; la recoloration des tuiles et le cache ; le contrôle du décodage par le canvas. Pour les traductions : mêmes clés dans toutes les langues, mêmes paramètres entre accolades, aucun texte vide, glossaire respecté, toutes les clés utilisées par le code présentes, et aucun tiret cadratin ni demi-cadratin dans les traductions, ce README, `index.html`, le manifeste web et `docs/`. Le test du glossaire porte sur toutes les clés dont le texte français parle de zone blanche. <!-- À VÉRIFIER : lot en cours -->
- **Site et pipeline ensemble** : les tests du site relisent une petite archive PMTiles produite par le pipeline sur des données synthétiques (`tests/fixtures/synthetique/`) et comparent ses pixels aux points témoins du pipeline. L'encodage du pipeline (Python) et le décodage du site (TypeScript) sont ainsi contrôlés ensemble.
- **Pipeline** (`pipeline/tests/`, pytest) : 48 tests, tous réussis. <!-- À VÉRIFIER : lot en cours --> Tout tourne sur des données synthétiques, sans réseau. Faux fichiers Arcep (adresses `file://`, archives 7z), GeoTIFF fabriqué pour la Suisse, faux service ArcGIS pour l'Italie et l'Espagne (`fake_arcgis.py`), relief et cellules inventés pour l'estimation, frontières entre deux pays. Une construction complète passe le test de cohérence, qui doit aussi détecter un niveau faux. D'autres tests vérifient la pyramide en plus proche voisin, le découpage en archives, le calage de la grille espagnole, la reprise des copies de travail, le comblement des interstices de frontière, le garde-fou de surface des contours, le refus des téléchargements coupés, la clé d'OpenCellID absente des journaux et les mentions de `SOURCES.md`. La commande `changed` (détection d'une source qui a changé) a ses propres tests : rien n'a changé, une source a changé, version du pipeline changée, aucune release, option `--force`. <!-- À VÉRIFIER : lot en cours -->
- **GPX de test** : `samples/test-alpes.gpx` (jusqu'à La Visaille par Les Chapieux et le col de la Seigne, France et Italie) part d'une zone couverte, entre dans une zone blanche des données de l'Arcep et la quitte à la frontière. <!-- À VÉRIFIER : lot en cours --> `samples/test-pyrenees.gpx` (de Gavarnie au refuge de Góriz par la brèche de Roland, France et Espagne) traverse des zones blanches des deux côtés : sur les données publiées le 14 novembre 2026, son rapport en liste six, dont l'arrivée au refuge de Góriz, sans réseau 4G dans la carte espagnole. <!-- À VÉRIFIER : lot en cours --> Ce sont des tracés de test, à ne pas utiliser pour s'orienter. Leur fabrication, leurs licences et les zones blanches attendues sont décrites dans `samples/README.md`.
- **Site en ligne** : `e2e/verif.mjs` (voir [Les workflows GitHub](#les-workflows-github)).

## Le pipeline de données

Le pipeline transforme les sources de couverture en tuiles. Il est écrit en Python avec GDAL (une bibliothèque de traitement des données géographiques) et tourne dans GitHub Actions, dans l'image `ghcr.io/osgeo/gdal:ubuntu-small-3.13.3`. On l'appelle depuis le dossier `pipeline/` :

| Commande | Rôle |
|---|---|
| `python3 -m czb.cli state --scope ... --services ...` | affiche l'état des sources en ligne |
| `python3 -m czb.cli changed --repo propriétaire/nom ...` | compare cet état à celui de la dernière release de données |
| `python3 -m czb.cli production` | affiche le périmètre et les services de la production (`config.yaml`) |
| `python3 -m czb.cli fetch-cache --repo propriétaire/nom` | récupère les copies de travail de la dernière release |
| `python3 -m czb.cli build --scope ... --services ...` | construit les archives PMTiles et le manifest |
| `python3 -m czb.cli verify --out out` | test de cohérence : source contre pixels du PMTiles |

### Étapes d'une construction

1. **Préparation des sources.** Chaque source dit si elle peut être traitée, et récupère ce qui peut manquer (les fichiers d'OpenCellID, par exemple). Une source impossible à traiter (clé d'accès absente, par exemple) est laissée de côté avec sa raison, et son pays est noté absent dans le manifest.
2. **État des sources.** Il est écrit dans `etat-sources.json`. Il sert à détecter les nouvelles versions.
3. **Masques des pays.** Le contour de chaque pays est téléchargé et posé sur la grille : le canal B reçoit le code du pays. Chaque fichier de contour est supprimé dès que ses géométries sont lues. <!-- À VÉRIFIER : lot en cours -->
4. **Sources, l'une après l'autre.** Chaque module télécharge et décompresse un fichier à la fois, et supprime les fichiers intermédiaires au fur et à mesure. Il reprojette en EPSG:3857 (la projection Mercator des cartes en ligne) et rastérise sur la grille commune : un pixel est allumé si son centre est dans le polygone (pour une source en image, il prend la valeur de la case qui contient son centre). Si deux niveaux se chevauchent, le plus élevé gagne. Une source n'écrit que dans les pixels de son pays.
5. **Interstices de frontière.** Les petits trous comblés entre deux contours reçoivent un niveau tiré de leurs voisins (voir plus bas).
6. **Tuiles.** Les canaux R, G, B et A sont assemblés. Le pipeline fabrique les tuiles du zoom 12, puis les zooms inférieurs en plus proche voisin, et écrit les archives PMTiles, découpées si besoin. Il écrit aussi `manifest.json`, `SOURCES.md`, les points témoins (`temoins.json` pour les sources, `temoins-contours.json` pour les contours, `temoins-attendus.json` pour le minimum attendu par source) et `rapport-construction.json` (grille, nombre de tuiles, tailles, durées, statistiques), plus les copies de travail `cache-*.tif`. Le logo de licence d'une source qui en a un (celui de l'AGCOM) est copié avec les données. <!-- À VÉRIFIER : lot en cours -->
7. **Test de cohérence** (`verify`), décrit plus bas.
8. **Publication**, par le workflow « Données » : une release GitHub `data-AAAA-MM-JJ`, c'est-à-dire une publication du dépôt avec ces fichiers joints.

### Un module par source

| Module (`pipeline/czb/sources/`) | Source(s) de `config.yaml` | Ce qu'il lit |
|---|---|---|
| `fr_arcep.py` | `fr_arcep` | fichiers GeoPackage (base de données géographique en un fichier) de l'Arcep, un par opérateur, technologie et usage, listés sur https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/00_Metropole/ (EPSG:2154, champ `niveau` : TBC, BC, CL ; pas de polygone = pas de couverture) |
| `ch_bakom.py` | `ch_bakom` | GeoTIFF (image géoréférencée) de l'OFCOM, trouvé par le catalogue STAC (format standard de catalogue de données géographiques) de data.geo.admin.ch, collection `ch.bakom.mobilnetz-4g` (EPSG:2056, carrés de 100 m, valeurs 0, 2 et 3) |
| `it_agcom.py` | `it_agcom` | service ArcGIS REST (service web de données géographiques) de l'AGCOM, `Grid100/mobile_4G` (EPSG:3857, champ `n_infrastrutture_totali` de 1 à 4) |
| `es_mtd.py` | `es_mtd` | couche ArcGIS Online du ministère espagnol, `InfoCob4G_2024` (EPSG:4258, champ `COBERTURA` : identifiants fiscaux des opérateurs présents ; champ `CCOM` : communauté autonome) |
| `estimation_opencellid.py` | `ad_estimation`, `mc_estimation` | cellules OpenCellID (codes pays mobiles 213 et 212), relief Copernicus DEM GLO-30, calcul de visibilité de GDAL |

Chaque module commence par un commentaire qui décrit la source telle qu'elle a été vérifiée. Tous suivent l'interface de `base.py` et sont enregistrés dans `__init__.py`. Ils s'appuient sur des outils communs : `czb/arcgis.py` (lecture page par page d'un service ArcGIS REST, par identifiant croissant), `czb/net.py` (téléchargements avec nouveaux essais et contrôle de la taille reçue, 7-Zip), `czb/raster.py` (rastérisation, reprojection), `czb/witness.py` (tirage des points témoins), `czb/cache.py` (copies de travail).

### Grille commune et frontières

- Toutes les sources sont ramenées sur la même grille : EPSG:3857, pixels alignés sur les tuiles du zoom 12. La fenêtre de travail est la plus petite fenêtre alignée sur les tuiles qui contient tous les pays du périmètre. Pour la production, elle fait 45 824 x 47 104 pixels (tuiles du zoom 12 de x 1989 à 2167 et de y 1369 à 1552). <!-- À VÉRIFIER : lot en cours -->
- Les trois canaux sont des fichiers sur disque, jamais chargés en entier en mémoire (environ 2,2 Go par canal pour la grille de production).
- Contours des pays : « Contours administratifs » de data.gouv.fr pour la France (départements calculés à partir d'ADMIN EXPRESS de l'IGN ; la Corse comprise), swissBOUNDARIES3D de swisstopo pour la Suisse, limites administratives de l'ISTAT pour l'Italie, unités administratives de l'IGN España pour l'Espagne (une requête par communauté autonome), OpenStreetMap pour l'Andorre et Monaco (extraits quotidiens de Geofabrik ; terre ferme seulement pour Monaco). OpenStreetMap étant modifiable par tous, la construction s'arrête si la surface de ces deux contours sort d'une fourchette attendue (455 à 480 km² pour l'Andorre, 1,9 à 2,4 km² pour Monaco).
- Ces contours viennent de producteurs différents et ne coïncident pas exactement. Quand deux pays revendiquent un pixel, le pays le plus haut dans `config.yaml` le garde (France, Suisse, Italie, Espagne, Andorre, Monaco). Les trous fermés de moins de 100 ha entre deux contours sont donnés au pays le moins prioritaire qui les touche ; sur les contours réels, le plus grand interstice mesuré fait 28,5 ha et la plus petite enclave 264 ha. Les trous plus grands sont de vraies enclaves ou des lacs, et restent hors zone.
- Seuls sont comblés les trous bordés par au moins deux entités différentes des contours : deux pays, ou deux régions d'un même pays (les interstices entre les quatre communautés espagnoles restent comblés). Un trou à l'intérieur d'une seule entité reste hors zone : c'est le cas de deux enclaves lombardes à l'intérieur du Piémont, environ 500 pixels. <!-- À VÉRIFIER : lot en cours -->
- Les pixels des interstices comblés prennent, pour chaque opérateur, le plus petit niveau de leurs voisins connus, jusqu'à 16 pixels de distance : dans le doute, on annonce le moins de couverture. Ils gardent le type de source de leur pays (voir [Limites](#limites)).
- En Suisse, les carrés sans donnée collés à la frontière sont comblés de la même façon, sur deux carrés de profondeur ; les autres pixels du pays sans donnée sont comptés comme non couverts.

### Points témoins et test de cohérence

- Pour chaque fichier ou chaque emplacement d'une source, 240 pixels du pays sont tirés au hasard et 60 sont gardés, répartis entre les niveaux. Le tirage est reproductible (graine fixe, section `verification` de `config.yaml`).
- Le niveau attendu de chaque point est établi directement dans la source, sans passer par la rastérisation ni la reprojection sur la grille commune : test géométrique exact sur les polygones (France, Italie), case de la grille d'origine (Suisse, Espagne), tableau du calcul (estimation). Un point trop près d'un bord est écarté.
- Les contours sont contrôlés de la même façon : 60 pixels tirés au hasard sur toute la grille et 60 autour de chaque pays. Leur pays attendu (ou aucun) est établi par un test géométrique exact sur les contours, dans l'ordre de priorité ; les points des interstices comblés et ceux trop près d'un contour sont écartés.
- Une fois les archives écrites, `verify` relit tous ces points dans les pixels décodés du PMTiles : niveau dans les canaux R et G, pays dans le canal B. Le job échoue au moindre écart, ou si une source, un service ou un emplacement annoncé dans le manifest a moins de 20 points (liste `temoins-attendus.json`).
- Pour l'Espagne, à chaque lecture complète de la couche, le module mesure en plus le calage de la grille des polygones, et compare sa copie de travail (voir ci-dessous) aux polygones en des points tirés au hasard dans chaque région, avec une tolérance de 3 % (des mailles sont coupées par les limites des communes). Un changement de grille de la source arrête la construction.

### Copies de travail

Certaines sources coûtent cher à relire : un bon millier de requêtes pour l'Espagne (environ 2,1 millions de polygones). D'autres limitent les téléchargements : OpenCellID permet deux téléchargements par jour et par fichier. Leur résultat, ramené à une image compacte, est publié avec les données sous le nom `cache-<source>.tif` (code dans `pipeline/czb/cache.py`).

- Avant de construire, le workflow « Données » récupère ces fichiers dans la dernière release (`fetch-cache`). S'ils manquent, les sources sont relues en entier.
- La copie espagnole sert tant que l'édition en ligne, la fenêtre, la grille et la liste des opérateurs n'ont pas changé. Ce chemin a tourné en vrai : la construction n° 2 a repris `cache-es_mtd.tif` (19 712 x 10 752 mailles) et traité l'Espagne en 116,1 s, contre 1 496,8 s pour une lecture complète. <!-- À VÉRIFIER : lot en cours -->
- La copie d'une estimation sert pendant tout le mois où elle a été faite. Si OpenCellID ne répond pas, la copie d'un mois précédent est reprise : mieux vaut une estimation un peu ancienne que pas de pays du tout.
- Le site n'utilise pas ces fichiers : le déploiement ne télécharge que les archives `.pmtiles` et `manifest.json`. Mais ils sont publics, joints à chaque release : la copie espagnole est une image de la couche du ministère (voir [Décisions laissées au propriétaire](#décisions-laissées-au-propriétaire)), et celles de l'estimation dérivent d'OpenCellID (CC BY-SA 4.0).

### Contenu d'une release et SOURCES.md

Une release de données contient les archives `.pmtiles`, `manifest.json`, `SOURCES.md`, `etat-sources.json`, `rapport-construction.json`, les trois fichiers de points témoins et les copies de travail `cache-*.tif`. Elle contient aussi le fichier du logo de licence de l'AGCOM. <!-- À VÉRIFIER : lot en cours -->

`SOURCES.md` est écrit par `pipeline/czb/notices.py` à partir du manifest. Il redit en clair, pays par pays, la source, sa date, sa licence, la mention à citer, la phrase que la licence impose et le contour du pays. Il est aussi recopié dans le texte de la release : les mentions suivent les données là où elles sont redistribuées. Il reste en français. Il dit en plus, pour chaque source, que les données ont été transformées (rastérisées sur une grille commune, ramenées à des niveaux ou à des seuils), c'est l'indication de modification que demandent les licences CC BY ; il cite le logo d'une source qui en a un, avec son lien. <!-- À VÉRIFIER : lot en cours -->

### Chiffres de la construction de production

<!-- À VÉRIFIER : lot en cours -->
Construction n° 2, lancée à la main avec le périmètre « production », en forçant la reconstruction, le 14 novembre 2026 (run 43602636462, de 14 h 01 à 14 h 55 UTC). Elle a publié la release `data-2026-11-14-4`, celle qu'utilise le site.

| Étape | Ce qui a été lu ou produit | Durée |
|---|---|---|
| Masques des pays | les contours des six pays, posés sur une grille de 45 824 x 47 104 pixels | 63,1 s |
| Arcep | 8 fichiers (internet mobile, appels et SMS, quatre opérateurs), 2 174,7 Mo téléchargés | 1 623,8 s |
| OFCOM | le GeoTIFF de la Suisse (9 908 pixels du pays sans donnée, comptés non couverts) | 83,2 s |
| AGCOM | 4 697 polygones des trois régions | 80,7 s |
| Ministère espagnol | copie de travail reprise, sans relire les polygones | 116,1 s |
| Andorre | 111 cellules lues, 41 retenues, 12 sites | 4,4 s |
| Monaco | 1 813 cellules lues, 1 433 retenues, 18 sites | 3,5 s |
| Tuiles | 22 231 tuiles, dont 16 388 au zoom 12 (185,6 Mo), 4 253 au zoom 11 et 1 128 au zoom 10 | 1 225,9 s |
| Ensemble | 353,13 Mo en 7 archives (la plus grosse : 69,67 Mo) | 3 203,9 s (53 min), job de 54 min |

- Pixels par pays : France 797 184 391, Suisse 60 303 271, Italie 46 666 326, Espagne 120 410 608, Andorre 586 881, Monaco 2 716.
- Interstices de frontière comblés : Suisse 57 pixels, Italie 13 323, Espagne 221, Andorre 684, Monaco 2. En tout, 14 287 pixels marqués, 14 284 extrapolés et 3 restés sans voisin connu (niveau 0).
- Test de cohérence : 1 200 points source contre pixels et 420 points de contour, aucun écart.
- Release : 17 fichiers, dont `SOURCES.md` (4 585 octets) et les copies de travail `cache-es_mtd.tif` (7,3 Mo), `cache-ad_estimation.tif` et `cache-mc_estimation.tif`. La plus ancienne release (`data-2026-11-14`) a été supprimée : trois sont gardées.
- Le site déployé avec ces données pèse 358 Mo (limite : 900 Mo).

Le chemin « aucune source n'a changé » a aussi tourné en vrai, le 14 novembre 2026 (run 43618564529, choix « production », sans forcer) : le journal dit « changed=false (sources inchangées depuis data-2026-11-14-4) », le job a duré 41 s, rien n'a été reconstruit ni publié.

## Les workflows GitHub

Un workflow est une tâche automatique de GitHub Actions. Ils sont dans `.github/workflows/`. Certains se lancent à la main depuis l'onglet Actions du dépôt (bouton « Run workflow »), d'autres tout seuls.

| Workflow | Fichier | Quand | Rôle |
|---|---|---|---|
| Tests | `ci.yml` | à chaque push sur une autre branche que `main` (sauf s'il ne touche que les sondes ou des fichiers `.md`), et sur chaque pull request | teste et construit le site ; teste le pipeline dans l'image GDAL |
| Données | `build-data.yml` | à la main, et le 5 de chaque mois à 3 h 23 UTC | construit les tuiles ; ne publie que la production |
| Déploiement | `deploy.yml` | à chaque push sur `main`, à la main, et relancé par « Données » après chaque nouvelle release | construit le site avec la dernière release de données et le publie sur GitHub Pages |
| Vérification | `verification.yml` | après chaque déploiement, ou à la main (adresse à vérifier) | contrôle le site en ligne dans un vrai navigateur |
| Sonde | `sonde.yml` | à la main (nom du script) | lance un script de vérification d'une source sur une machine de GitHub qui a accès à Internet |

`deploy.yml` déclare aussi un départ à chaque release publiée. Mais une release créée par le workflow « Données » ne lance pas d'elle-même d'autre workflow (règle de GitHub pour ce qui est fait avec le jeton d'Actions) : c'est l'étape « Relancer le déploiement du site » de `build-data.yml` qui lance le déploiement. Si elle échoue, le job échoue et le dit. <!-- À VÉRIFIER : lot en cours -->

### Données

- **Production et essais.** La production est ce qu'indique la section `production` de `pipeline/config.yaml` : le périmètre `complet` (tous les pays), avec les services `data` (internet mobile) et `voice` (appels et SMS). Seul le choix « production » du lancement à la main, et le passage mensuel, sont publiés. Tout autre choix est un essai, même le périmètre `complet` : il est toujours construit, même si rien n'a changé, et vérifié comme la production, puis gardé 7 jours dans l'artefact « donnees » du run (des fichiers téléchargeables depuis la page du run). Un essai ne remplace jamais les données du site.
- **Réglages du lancement à la main** : « Périmètre » (`production`, ou un périmètre d'essai), « Services d'un essai » (`data` ou `data,voice`, ignoré pour la production), « Reconstruire même si aucune source n'a changé ».
- **Étapes** : installation des outils (7-Zip, dépendances Python), lecture de la production, paramètres, tests du pipeline sur données synthétiques, « Une source a-t-elle changé ? », récupération des copies de travail, construction, test de cohérence, conservation du résultat. Pour la production, si une source a changé, un second job publie la release `data-AAAA-MM-JJ` (puis `data-AAAA-MM-JJ-2`, `-3` s'il y en a déjà une ce jour-là), recopie `SOURCES.md` dans son texte, ne garde que les trois releases de données les plus récentes, et relance le déploiement. La construction a 340 minutes au plus.
- **Ne reconstruire que si une source a changé.** Chaque release contient `etat-sources.json`, l'état des sources au moment de la construction. Avant de construire, le workflow relit l'état en ligne et le compare. S'il n'a pas changé, rien n'est construit.
- **Passage mensuel.** Le 5 de chaque mois à 3 h 23 UTC. GitHub désactive les workflows planifiés d'un dépôt resté 60 jours sans activité : un petit job réactive ce workflow à chaque passage mensuel.
- **Constructions simultanées.** Les constructions de production (passage mensuel ou choix « production ») passent l'une après l'autre. Les essais peuvent tourner en même temps : ils ne publient rien.

### Déploiement

1. tests du site (`npm test`) ;
2. téléchargement, dans `public/data/`, des archives `.pmtiles` et du `manifest.json` de la release de données la plus récente (par date de publication) ;
3. contrôles : le manifest doit être lisible et toutes les archives qu'il cite doivent être présentes. Sinon le déploiement échoue, et le site déjà en ligne garde ses données. S'il n'existe aucune release de données, il échoue aussi, sauf s'il a été lancé à la main avec l'option « Publier même s'il n'existe aucune release de données » (le site est alors publié sans couche réseau) ;
4. construction du site (`npm run build`), qui écrit aussi la liste de la coque hors ligne dans `dist/sw.js` ;
5. contrôle des tailles : chaque fichier sous 95 Mo, le site complet sous 900 Mo (en millions d'octets, comme le pipeline) ;
6. publication sur GitHub Pages ;
7. vérification du site en ligne (workflow « Vérification »).

### Vérification

Le script `e2e/verif.mjs` ouvre le site dans Chromium, avec Playwright, sur un écran d'ordinateur (1 280 x 800) et sur un écran de téléphone (412 x 915, comme un Pixel 9a), en français, en allemand et en espagnol, avec un passage au catalan et à l'italien. Il contrôle le chargement du fond de carte et des données de couverture, la recherche, l'import d'un GPX (dont un GPX « difficile » : ISO-8859-1, éléments préfixés, point (0, 0), altitude manquante), le rapport, le GPX enrichi, le profil au clavier, les appels et SMS quand ils sont publiés, le fond suisse, le panneau Sources et ses mentions, et l'absence d'erreur JavaScript. D'autres scénarios jouent le mode hors ligne (préparation d'un tracé entièrement en France, redémarrage sans réseau, `?lang=es` sans réseau, suppression confirmée), des tuiles de couverture illisibles puis « Réessayer », une nouvelle publication des données pendant la visite, les fonds enregistrés selon leur fournisseur, le pied de carte, « Ma position », le rapport réduit, le fond Automatique, un style du Plan IGN lent ou refusé, et les deux GPX de test de part et d'autre d'une frontière quand l'Italie et l'Espagne sont publiées. Certains services y sont simulés. Le script utilise `samples/test-alpes.gpx` quand les données publiées couvrent la région de son départ, sinon un court tracé écrit dans le script. Les captures d'écran sont gardées 14 jours dans l'artefact « captures ».

Le 14 novembre 2026, sur le site en ligne (commit `deadf53`, données `data-2026-11-14-4`), 101 contrôles sur 101 ont réussi (run 43620100839). <!-- À VÉRIFIER : lot en cours -->

### Sonde

Une sonde sert à vérifier une source avant de l'intégrer : une adresse, un identifiant de couche, un schéma (`ogrinfo`, `gdalinfo`) ou une licence. Le script choisi dans `pipeline/sondes/` tourne dans l'image GDAL, avec les fonctions communes de `_lib.sh`, et on lit le résultat dans le journal du job. Le secret `OPENCELLID_TOKEN` y est disponible, masqué dans les journaux.

## Mettre à jour les données

### Ce qui est automatique

Le 5 de chaque mois, le workflow « Données » regarde si une source a changé. Si oui, il reconstruit tout, vérifie, publie une nouvelle release et relance le déploiement. Ce qu'il surveille :

| Source | Ce qui est comparé |
|---|---|
| Arcep | les fichiers de la page de téléchargement (noms, tailles, dates) et le dernier trimestre. Un nouveau trimestre change les noms. |
| OFCOM | la date de l'item STAC et la date de mise à jour de son GeoTIFF |
| AGCOM | le nom du service (il contient la date des données), la couche, la phrase de publication, le nombre de polygones |
| Ministère espagnol | le nom de la couche, sa date de dernière modification, le nombre de polygones par région, la date de modification de l'élément ArcGIS |
| Estimation | seulement ses réglages. OpenCellID change tous les jours, ce n'est pas une raison de tout reconstruire. L'estimation est refaite quand une construction a lieu un autre mois. |

L'état compare aussi le périmètre, les services et le numéro de version du pipeline (`pipeline/czb/__init__.py`) : augmenter ce numéro provoque une reconstruction au passage suivant. Une source qui devient disponible, ou indisponible, change aussi l'état.

Pour l'Espagne, le pipeline lit en plus la page du ministère (clé `url` de la source `es_mtd`) et relève les identifiants des éléments ArcGIS qu'elle cite. Si la page répond, contient des identifiants, et ne cite plus celui de `item_url`, la détection échoue avec un message clair : « nouvelle édition probable : mettre à jour layer_url, item_url, name et data_date de es_mtd ». Si la page ne répond pas, ou ne contient aucun identifiant, c'est un simple avertissement, et l'état ne change pas. L'état publié avec la release actuelle n'a pas ce champ : la première détection qui suit verra donc un changement, et une reconstruction aura lieu. <!-- À VÉRIFIER : lot en cours -->

Ce qui n'est pas surveillé et se met à jour à la main dans `pipeline/config.yaml` :

- les contours des pays : un nouveau contour ne déclenche pas de reconstruction. Deux adresses portent un millésime, à changer quand un nouveau paraît : swissBOUNDARIES3D (janvier 2026) et les limites de l'ISTAT (1er janvier 2026) ;
- une nouvelle édition de la carte espagnole : le garde-fou ci-dessus la signale, mais il faut changer à la main `layer_url`, `item_url`, `name` et `data_date` de la source `es_mtd` (la date des données est écrite dans la configuration).

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

Le panneau « Sources » du site donne la date de chaque source et la date de génération des tuiles. Sur GitHub, la release `data-*` la plus récente contient aussi `rapport-construction.json` (les chiffres de la construction), `SOURCES.md`, `etat-sources.json` et les fichiers de points témoins.

## Faire évoluer le projet

### Ajouter une langue

1. Copier `src/i18n/locales/fr.json` sous le code de la langue, par exemple `en.json`.
2. Dans le bloc `_meta`, mettre le nom de la langue, écrit dans cette langue, et la balise qui sert à formater les nombres et les dates : `{"name": "English", "locale": "en-GB"}`.
3. Traduire les valeurs, sans toucher aux clés ni aux paramètres entre accolades (`{km}`, `{count}`, etc.). Les clés qui finissent par `_one` et `_other` sont les formes du singulier et du pluriel. Pas de tiret cadratin ni demi-cadratin : un test les refuse.
4. Mettre à jour le premier test de `tests/i18n.test.ts` (« propose les cinq langues, le français en premier »), qui vérifie la liste exacte des langues. L'ordre d'affichage vient de `PREFERRED_ORDER` dans `src/i18n/index.ts` (l'anglais y est déjà prévu, après l'allemand). Une langue absente de cette liste vient après les autres, par ordre alphabétique.
5. Lancer `npm test`. Le test « toutes les langues ont exactement les mêmes clés » signale toute clé manquante ou en trop. D'autres tests vérifient les paramètres entre accolades et qu'aucun texte n'est vide.

La langue apparaît toute seule dans les paramètres et répond à `?lang=`. Si une clé manque malgré tout, le site retombe sur le français. Les noms des pays viennent du navigateur (`Intl.DisplayNames`) : rien à traduire. La recherche à l'étranger (Photon) ne connaît que l'allemand, l'anglais et le français : pour une autre langue, elle donne les noms locaux. Le manifeste web (`public/manifest.webmanifest`) reste en français.

Deux textes vivent hors des fichiers de langue : la phrase `<noscript>` d'`index.html`, écrite dans chaque langue, et les traductions des textes du manifest (noms des sources, licences, mentions de contour), dans `pipeline/config.yaml` (clés `name_i18n`, `licence_i18n` et `credit.text_i18n`). Sans elles, la nouvelle langue montre ces textes en français. <!-- À VÉRIFIER : lot en cours -->

### Ajouter ou changer une source

1. **Vérifier la source** avant tout : la licence doit autoriser la réutilisation ; puis la date, le format, les champs, les valeurs. Le workflow « Sonde » sert à cela. Ne rien deviner, et ne jamais récupérer de données sur les sites des opérateurs ni sur des cartes non ouvertes.
2. **La documenter** dans `docs/sources.md` : source, date, licence, méthode, limites.
3. **La déclarer** dans `pipeline/config.yaml` :
   - le pays, dans `countries` : `name` (pour `SOURCES.md`), `code` (de 1 à 15, unique : c'est la valeur du canal B), `eu_roaming`, `mask` (le contour et sa mention `credit`), `operators` si la source ne les distingue pas, `slots` (4 au plus : des opérateurs nommés, ou des seuils `min_operators`) et `sources` ;
   - la source, dans `sources` : `country`, `type` (0, 1 ou 2), `name`, `attribution`, `url`, `licence`, `licence_url`, éventuellement `licence_notice`, `licence_logo` et `licence_logo_url`, `services` (avec la technologie), `levels_kind` (`four`, `three` ou `binary`), `resolution_m`, plus les réglages propres au module (adresses, champs, valeurs). Une source désigne son module par la clé `module`, ou à défaut par son propre nom : c'est ainsi qu'un même module sert l'Andorre et Monaco ;
   - les traductions facultatives `name_i18n` et `licence_i18n` de la source, et `text_i18n` dans la mention du contour (dictionnaires es, ca, it, de). Les noms propres et les formules de licence imposées ne se traduisent pas. <!-- À VÉRIFIER : lot en cours -->
4. **Écrire le module** dans `pipeline/czb/sources/`, en partant d'un module proche, et le commencer par un commentaire qui décrit la source vérifiée. Il hérite de `Source` (`base.py`) et fournit :
   - `remote_state()` : un petit état de la source en ligne (dates, tailles, nombres d'entités), qui sert à détecter une nouvelle version ;
   - `process()` : il remplit la grille commune avec `merge_level`, avec des niveaux de 0 à 3, uniquement dans les pixels de son pays. Il ajoute des points témoins pour chaque service et chaque emplacement (20 au moins pour chacun). Il renvoie au moins la date des données ;
   - si besoin, `available()` (par exemple quand une clé d'accès manque) et `prepare()`. Une source qui se révèle inutilisable en cours de route lève `SourceUnavailable` : la construction continue sans elle, et un pays qui n'a plus de source est retiré de la construction.
5. **L'enregistrer** dans `pipeline/czb/sources/__init__.py` (dictionnaire `REGISTRY`).
6. **Ajouter un test** sur des données synthétiques dans `pipeline/tests/`, sans réseau. Exemples : `test_ch_bakom.py` (GeoTIFF fabriqué), `test_it_agcom.py` et `test_es_mtd.py` (faux service ArcGIS de `fake_arcgis.py`).
7. Pour un nouveau pays, **ajouter un périmètre** dans `scopes` et son nom dans la liste `options` de `.github/workflows/build-data.yml`, pour pouvoir l'essayer seul. Puis lancer un essai.

Le site n'a pas besoin d'être modifié : il lit le nouveau pays dans le manifest. Seul le fond du mode Automatique se règle à part, dans `NATIONAL_BASEMAP` de `src/map/basemaps.ts` (à défaut, le pays reçoit OpenTopoMap). Un nouveau fond de carte se déclare dans `BASEMAPS` et `BASEMAP_ORDER` du même fichier, avec sa mention et sa règle de préchargement hors ligne, et son nom dans les fichiers de langue.

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
| `npm run typecheck` | vérifie les types TypeScript (`tsc --noEmit`) |
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

`SITE_URL` désigne le site à vérifier (par défaut, le site en ligne). `SANS_FONDS=1` saute les contrôles qui ont besoin des fonds de carte et de la recherche (pour un essai local, sans accès à ces services). `CAPTURES_DANS_LES_LOGS=1` écrit aussi les captures dans la sortie. Les captures sont enregistrées dans `e2e/captures/` (ignoré par git). Le script se termine en erreur si un contrôle échoue.

## Limites

Les écarts relevés par l'audit de conformité au cahier des charges (14 novembre 2026, 130 exigences) et non corrigés figurent dans cette liste et dans [Décisions laissées au propriétaire](#décisions-laissées-au-propriétaire).

- **Couverture théorique.** Les cartes officielles sont des simulations ou des déclarations des opérateurs, pas des mesures. Sur le terrain, le relief, la végétation, la météo et votre téléphone changent le résultat : « Couverture théorique, des écarts locaux sont possibles. » En montagne, ne comptez pas sur votre seul téléphone pour donner l'alerte.
- **Suisse, Italie, Espagne : « couvert » ou « non couvert » seulement.** Ces trois sources n'ont pas de niveau de qualité. « Bonne couverture » y veut dire « couvert » : on n'y voit jamais d'orange, et l'affichage par défaut n'y montre que le rouge des zones sans couverture. Ce n'est pas comparable aux 4 niveaux de l'Arcep. Les critères diffèrent aussi : en Espagne, un signal 4G d'au moins -115 dBm sous 1 GHz et -117 dBm au-dessus ; en Suisse, la couverture extérieure annoncée par les opérateurs ; en Italie, le critère n'est pas documenté dans les textes lus.
- **Sources agrégées.** En Suisse et en Italie, la source dit combien de réseaux couvrent un lieu, pas lesquels. À l'étranger, la couverture réelle dépend aussi des accords d'itinérance de votre opérateur. La Suisse, l'Andorre et Monaco ne font pas partie de l'itinérance de l'Union européenne. Les données italiennes datent du 27 janvier 2026.
- **Espagne : données de 2024.** Situation au 30 juin 2024 : c'est l'édition la plus récente liée par le site du ministère au 14 novembre 2026. La vue par opérateur peut sous-estimer la couverture des clients d'opérateurs hébergés sur un autre réseau (opérateurs virtuels, itinérance nationale), et Digi n'apparaît pas dans les données. « Tous opérateurs du pays » est la vue la plus sûre.
- **Appels et SMS : France seulement.** Les sources étrangères utilisées ne donnent que la 4G, et l'estimation ne lit que les cellules 4G et 5G.
- **Andorre : une estimation très pessimiste.** Le fichier d'OpenCellID ne donne que 12 sites 4G en Andorre, tous autour d'Andorre-la-Vieille. Tout le nord et l'est du pays (vallées d'Encamp, de Canillo et d'Ordino, Soldeu, le Pas de la Case) ressortent « sans couverture », ce qui est très probablement faux : 85,2 % du pays sans couverture. <!-- À VÉRIFIER : lot en cours --> L'erreur est du côté prudent, mais elle est grande. Rien ne détecte automatiquement une base d'antennes aussi pauvre. Voir les choix possibles dans [Décisions laissées au propriétaire](#décisions-laissées-au-propriétaire).
- **Zones estimées : la fiabilité.** Les positions d'OpenCellID sont des positions estimées de cellules, calculées à partir de mesures faites par les téléphones de bénévoles : ce ne sont pas des positions de pylônes. Elles reposent sur peu de mesures (médiane de 6 mesures par cellule retenue en Andorre, 12 à Monaco), <!-- À VÉRIFIER : lot en cours --> et seules les cellules vues dans les 18 derniers mois sont publiées. Ni la puissance, ni l'orientation des antennes, ni la végétation fine ne sont prises en compte. Lors du calage sur la France, une zone estimée « bonne » était réellement couverte dans 95 à 99 % des cas. Mais une zone blanche estimée n'était juste qu'à 81 % avec des positions d'antennes exactes, et environ une fois sur deux avec des positions approximatives et des antennes manquantes, ce qui ressemble davantage à OpenCellID. Ces erreurs de position étaient simulées : la fiabilité réelle avec les données d'OpenCellID n'est pas mesurée. Une antenne absente de la base crée une fausse zone blanche. Ne comptez pas sur une zone estimée pour un appel d'urgence.
- **Monaco.** Seules les cellules du code pays mobile monégasque (212, dont la seule entrée dans la liste de l'UIT est Monaco Telecom) sont lues : les réseaux français captés à Monaco ne comptent pas. Le portail data.gouv.mc répondait encore par une erreur 503 et une page « Site en maintenance » au dernier essai, le 14 novembre 2026 : la conclusion « pas de source officielle exploitable » reste provisoire.
- **Frontières.** Les contours des pays viennent de producteurs différents et ne coïncident pas exactement. Le pipeline donne chaque pixel disputé à un seul pays et comble les petits interstices. Mesure faite sur les tuiles du 14 novembre 2026 : il n'y a pas de bande blanche artificielle large, mais une frange de 1 à 3 pixels (30 à 85 m) plus souvent « sans couverture » côté italien et côté espagnol. Côté italien face à la France, la part des pixels sans couverture vaut 32,7 % au premier pixel, 25,1 % au deuxième, 20,5 % au troisième, puis 17 à 18 % ; côté espagnol, 48,7 % au premier pixel, puis 37,8 %. Les mailles des sources n'arrivent pas exactement au contour (mailles coupées en Espagne, carrés de 100 m en Italie). L'erreur est du côté prudent : au passage d'une frontière, une zone blanche du rapport peut être allongée de quelques dizaines de mètres. <!-- À VÉRIFIER : lot en cours -->
- **Hors zone.** La partie française du Léman, le Liechtenstein et quelques enclaves (Büsingen, Campione d'Italia, Treviño, Valle de Villaverde) restent hors zone.
- **Interstices de frontière.** Leurs pixels (14 287 dans les données en ligne) ont un niveau extrapolé de leurs voisins, mais ils portent le type de source officielle de leur pays : rien ne les distingue sur la carte. <!-- À VÉRIFIER : lot en cours -->
- **Résolution.** Un pixel du zoom 12 fait 26 à 28 m au sol dans les Alpes et les Pyrénées. Les sources sont souvent plus grossières : 100 m pour la Suisse et l'Italie, des mailles d'environ 28 m sur 38 m pour l'Espagne, 30 m pour l'estimation. La résolution des fichiers de l'Arcep n'est documentée dans aucun texte lu.
- **PNG plutôt que WebP sans perte.** Le cahier des charges prévoit le WebP sans perte s'il est plus léger. Il l'est : sur 800 tuiles tirées au hasard, 9,02 Mo en WebP sans perte contre 12,77 Mo en PNG, soit environ 29 % de moins, pour des pixels identiques (mesure de l'audit). Les tuiles restent en PNG, parce que le décodeur de secours en JavaScript ne lit que le PNG, et c'est lui qui garantit des pixels exacts sur tous les navigateurs.
- **Hors ligne.** Le fond OpenTopoMap n'est jamais préchargé : son fournisseur ne garantit pas la disponibilité de son serveur (« keinerlei Ausfallsicherheit ») et demande d'éviter les téléchargements en masse. Or c'est le fond du mode Automatique en Italie, en Andorre et à Monaco : pour un tracé dans ces pays, le panneau dit que ces pays n'ont pas de fond enregistré. Il faut alors choisir soi-même un autre fond avant de préparer le tracé ; qu'il montre bien ces pays n'est pas vérifié. Les autres fonds sont plafonnés (900 ou 600 tuiles) et perdent leurs zooms les plus fins sur un long tracé. Le préchargement réel de swisstopo et d'IGN España n'a pas été essayé avec leurs vrais serveurs (celui du Plan IGN l'a été, sur le site en ligne). Les tuiles de fond enregistrées ne sont jamais renouvelées : une mise à jour de l'enregistrement garde celles qui sont déjà là, alors que la documentation de swisstopo demande de vider un cache local quand sa couche change. Pour les rafraîchir, supprimer les données hors ligne puis préparer de nouveau le tracé. La recherche de lieux ne marche pas sans réseau, et un seul tracé est gardé. Le navigateur peut effacer ces données s'il manque de place ; le site lui demande de les garder.
- **Service Worker en JavaScript.** `public/sw.js` est écrit en JavaScript, pas en TypeScript : le compilateur ne le vérifie pas, et il recopie à la main des constantes du code TypeScript (nom du cache hors ligne, adresse du manifest, délai réseau).
- **Fonds de carte.** OpenTopoMap ne garantit pas la disponibilité de son serveur. Si le style vectoriel du Plan IGN ne se charge pas, le site affiche le Plan IGN en images.
- **Mentions sur téléphone.** Le pied de carte est visible au chargement, puis se replie au premier geste sur la carte. IGN España demande une mention visible au pied de la carte, OpenCellID un crédit à côté de la carte, et les règles d'OpenStreetMap une mention qui ne demande aucune action pour être vue : ce repli est un compromis, à valider.
- **Recherche.** Seuls les types d'adresse, « commune » et « département » sont traduits : les autres catégories de lieux de l'IGN (refuge, par exemple) restent en français dans toutes les langues.
- **Mises à jour à la main.** Les nouveaux millésimes des contours ne sont pas détectés, et une nouvelle édition de la carte espagnole demande une modification à la main ; pour la carte italienne, la prochaine adresse n'est pas vérifiée. Une nouvelle extraction d'OpenCellID ne déclenche pas de reconstruction (choix assumé). Voir [Mettre à jour les données](#mettre-à-jour-les-données).
- **Nom des releases.** Le cahier des charges demande `data-AAAA-MM-JJ`. Quand il y a plusieurs publications le même jour, le workflow ajoute `-2`, `-3`, etc. : la release en ligne s'appelle `data-2026-11-14-4`. <!-- À VÉRIFIER : lot en cours -->
- **Lectures faites pendant l'enquête sur les sources.** Une dizaine de tuiles d'image du ministère espagnol ont été lues sur un hôte dont le fichier robots.txt interdit les robots. Le pipeline ne les lit pas, et rien de publié n'en dépend. Quand maps.agcom.it et www.mimit.gov.it ne répondaient pas, des sondes ont lu des copies chez Internet Archive : rien de publié n'en dépend, et ces points restent non vérifiés à la source. Les conditions d'utilisation d'ArcGIS Online (Esri), la plateforme qui sert la couche espagnole, n'ont pas été lues.

## Décisions laissées au propriétaire

- **Licence de la couche espagnole.** Aucune licence n'est attachée à la couche `InfoCob4G_2024`. Elle n'est pas dans le portail de données ouvertes du ministère (https://datos-conectemos.hub.arcgis.com, qui ne publie que des agrégats), et une demande d'ouverture de 2021 sur datos.gob.es est à l'état « No viable ». Vont dans le sens de la réutilisation : les conditions générales de réutilisation du site du ministère (citer la source et la date), la Ley 11/2022 (article 48.1), le Real Decreto 1495/2011 (article 8.1) et les mentions légales de Conectemos (« Se prohíbe la reproducción total o parcial de los contenidos del Portal sin citar su origen o solicitar autorización. »). Appelle la prudence : la loi 37/2007 exclut les documents sur lesquels des tiers ont des droits de propriété intellectuelle, et les données viennent des opérateurs ; rien de lu ne dit si c'est le cas. Les hôtes des images tuilées du ministère interdisent les robots (robots.txt « Disallow: / ») : le pipeline ne les lit pas, il ne lit que la couche d'entités. La copie de travail `cache-es_mtd.tif`, publiée avec chaque release, est une image de cette couche. Trois choix : garder la source officielle, écrire au ministère (S.G. de Operadores de Telecomunicaciones e Infraestructuras Digitales) pour demander si la couche relève des conditions générales, ou passer l'Espagne en « estimée ».
- **Lecture du service italien.** Le pipeline lit le service REST public de la carte de l'AGCOM (geo3.agcom.it) : 19 requêtes par édition, sans jeton, dans la limite que le service annonce. Ce n'est pas la voie de téléchargement que désigne le portail, une demande par courriel. La licence CC BY 4.0 couvre les données. À trancher : garder cette lecture, passer par la demande officielle, ou informer l'AGCOM.
- **Estimation de l'Andorre.** Trois choix : la garder telle quelle, masquer l'Andorre, ou enrichir l'estimation avec les cellules 2G et 3G du même fichier (non essayé). L'audit suggère aussi un contrôle de vraisemblance (densité de sites, part de « pas de couverture »), qui publierait alors « limitée » au lieu de « pas de couverture », ou signalerait une estimation insuffisante.
- **Licence du code.** `package.json` ne déclare pas de licence, et le dépôt n'a pas de fichier LICENSE. Les deux GPX de test, eux, sont sous ODbL 1.0 quoi qu'il en soit (voir [Licences et crédits](#licences-et-crédits)).
- **Forme de la mention IGN España.** « CC BY 4.0 ign.es » est la valeur exacte du champ AccessConstraints du service et la formule demandée par le propriétaire. La licence de l'IGN préfère, quand des données couplées existent, leurs propres formules (par exemple « CC-BY 4.0 ign.es 2025 »). La mention affichée n'a pas changé.
- **Navigation hors ligne.** La page vient de la coque enregistrée dès qu'elle est complète : jamais de mélange de versions, et le site s'ouvre sans attendre un réseau faible ; en échange, une nouvelle version n'apparaît qu'à la visite suivante. L'autre choix, « réseau d'abord, 3 secondes », montre plus vite une nouvelle version, mais risque une page blanche par réseau faible juste après une mise en ligne. <!-- À VÉRIFIER : lot en cours --> Le préchargement des tuiles est fait par la page, pas par le Service Worker comme le décrit le cahier des charges : il s'arrête si l'onglet est fermé, et se reprend. Le déplacer dans le Service Worker, ou utiliser Background Fetch (Chrome seulement), reste à décider.
- **Autres choix à confirmer.**
  - Monaco : ne lire que les cellules du code 212, ou ajouter celles des réseaux français captés à Monaco.
  - Contours sous ODbL (France, Andorre, Monaco) : le code pays des tuiles en dérive. La question du partage à l'identique (lecture « Produced Work » de l'ODbL) n'est pas tranchée. Pour la France, une piste serait de prendre ADMIN EXPRESS de l'IGN directement (licence non vérifiée).
  - Partie française du Léman hors zone, PNG ou WebP, nom des releases, Service Worker en JavaScript, mentions repliées sur téléphone : voir [Limites](#limites).
  - Points aberrants : deux points aberrants consécutifs loin du tracé restent comme un petit segment, et un aller-retour dessiné en 3 points avec des étapes de plus de 10 km perd son point le plus éloigné. Une règle tenant compte de la densité des points reste à choisir.
  - Le pipeline se présente aux serveurs des sources sous un nom générique (`pipeline-couverture-mobile/1.0`). Pour être identifiable par un fournisseur, mettre un nom et une adresse de contact dans `USER_AGENT` de `pipeline/czb/net.py`.

## Réglages que le propriétaire peut revoir

Ces valeurs sont des choix du projet. Elles se changent dans le code, puis le site est republié par un push sur `main`.

| Réglage | Fichier | Valeur | Effet |
|---|---|---|---|
| `RESAMPLE_STEP_M` | `src/config.ts` | 20 m | pas du rééchantillonnage du tracé |
| `WHITE_ZONE_MIN_LENGTH_M` | `src/config.ts` | 100 m | longueur minimale d'une zone blanche |
| `WHITE_ZONE_MERGE_GAP_M` | `src/config.ts` | 50 m | deux zones séparées par moins que cela sont fusionnées |
| `SEGMENT_JOIN_MAX_M` | `src/config.ts` | 50 m | deux segments plus proches forment un parcours continu |
| `ELEVATION_THRESHOLD_M` | `src/config.ts` | 5 m | variations d'altitude ignorées dans le dénivelé |
| `ELEVATION_MIN_SHARE` | `src/config.ts` | 0,5 | part des points qui doivent avoir une altitude pour annoncer dénivelé, profil et altitude des zones |
| `TRACK_MAX_JUMP_M` | `src/config.ts` | 10 km | saut qui coupe une trace ; un point isolé plus loin de ses deux voisins est écarté |
| `MAX_GPX_BYTES` | `src/config.ts` | 40 x 1 024 x 1 024 octets (41,9 millions) | taille maximale d'un GPX |
| `SAMPLING_CONCURRENCY` | `src/config.ts` | 6 | tuiles lues en même temps pendant l'analyse |
| `TILE_READ_TIMEOUT_MS` | `src/config.ts` | 20 s | délai maximal d'une lecture de tuile de couverture ; par réseau très lent, des tuiles peuvent passer en gris avec « Réessayer » |
| `NETWORK_TIMEOUT_MS` | `src/config.ts` | 3 s | attente du réseau avant de servir la copie locale du manifest des données <!-- À VÉRIFIER : lot en cours --> |
| `VECTOR_STYLE_TIMEOUT_MS` | `src/config.ts` | 8 s | attente du style vectoriel du Plan IGN |
| `COVERAGE_DISPLAY_MAX_ZOOM` | `src/config.ts` | 16 | dernier zoom des tuiles de couverture fabriquées pour l'affichage |
| `SEARCH_MIN_CHARS`, `SEARCH_DEBOUNCE_MS`, `SEARCH_MAX_RESULTS` | `src/config.ts` | 3 caractères, 350 ms, 6 lieux | déclenchement et longueur de la recherche |
| `SEARCH_TIMEOUT_MS` | `src/config.ts` | 5 s | délai maximal de chaque service de recherche |
| `PHOTON_LANGS` | `src/config.ts` | de, en, fr | langues demandées à Photon |
| `INITIAL_VIEW`, `MAX_BOUNDS` | `src/config.ts` | la France ; de 12° ouest à 18° est, de 36° à 54,5° nord | vue de départ ; zone où la carte peut aller, et recherche à l'étranger |
| `LOCATE_SLOW_MS` | `src/map/locator.ts` | 15 s | message « le GPS cherche encore » |
| `LOCATE_MAX_ZOOM` | `src/map/mapView.ts` | 15 | zoom maximal du recentrage sur la position |
| capacité du cache | `src/coverage/store.ts` | 160 tuiles | tuiles décodées gardées en mémoire |
| `CORRIDOR_BUFFER_M` | `src/offline/manager.ts` | 700 m | couloir enregistré de chaque côté du tracé |
| champ `offline` de chaque fond | `src/map/basemaps.ts` | voir [Mode hors ligne](#mode-hors-ligne) | plafonds et freins du préchargement |

Choix faits dans le code, à confirmer :

- la longueur d'une zone blanche est tirée de ses bornes arrondies à 100 m (`src/gpx/report.ts`) ;
- le manifest refuse le WebP (`src/coverage/manifest.ts`), et le pipeline écrit du PNG (voir [Limites](#limites)) ;
- les crédits d'OpenStreetMap de la recherche et du panneau Sources sont traduits (« © les contributeurs d'OpenStreetMap » en français), avec un lien vers la page des droits ;
- en pied de carte, une zone estimée affiche le crédit qu'OpenCellID demande (« Cell tower data from OpenCellID, licensed under CC BY-SA 4.0 »), à la place de la mention de la source du manifest ; la mention complète, Copernicus compris, est dans le panneau Sources ;
- le lien d'OpenTopoMap reste http://opentopomap.org, mot pour mot comme dans sa mention.

Dans le pipeline : les limites de taille et le nombre de points témoins sont dans `pipeline/config.yaml` (sections `limits` et `verification`), comme les réglages de l'estimation (section `estimation`). Le seuil de 100 ha des interstices est `GAP_MAX_HA` dans `pipeline/czb/masks.py`, et la propagation sur 16 pixels se règle dans `extrapolate_marked` (`pipeline/czb/layers.py`).

## Vie privée

- Aucun cookie, aucun outil de mesure d'audience, aucun compte. Le site n'a ni formulaire, ni balise de suivi, et ne fait aucune requête d'envoi de données : il lit des fichiers et interroge les services ci-dessous (vérifié par l'audit du 14 novembre 2026, dans le code et dans le site construit).
- Le GPX est lu et analysé dans le navigateur. Il n'est envoyé nulle part, et le GPX enrichi est fabriqué dans le navigateur.
- Services contactés, et ce qu'ils reçoivent :

| Service | Adresse | Quand | Ce qu'il reçoit |
|---|---|---|---|
| le site lui-même (GitHub Pages) | nathancouturier.github.io | toujours | demandes de la page, des scripts, du manifest et des morceaux d'archives de couverture de la zone affichée (et du couloir du tracé, quand on prépare le hors ligne) |
| IGN (Géoplateforme) | data.geopf.fr | fond Plan IGN (style, tuiles, icônes, polices), Plan IGN en images, photos aériennes, estompage | demandes de tuiles de la zone affichée |
| swisstopo | wmts.geo.admin.ch | fond swisstopo | demandes de tuiles de la zone affichée |
| IGN España | www.ign.es | fond IGN España | demandes de tuiles de la zone affichée |
| OpenTopoMap | a.tile.opentopomap.org, b.tile.opentopomap.org, c.tile.opentopomap.org | fond OpenTopoMap | demandes de tuiles de la zone affichée |
| géocodage de l'IGN | data.geopf.fr/geocodage/completion | quand on tape au moins 3 caractères dans la recherche | le texte tapé, le centre de la carte arrondi, les types de lieux cherchés, la zone (`METROPOLE`) et le nombre de réponses voulu |
| Photon (komoot) | photon.komoot.io | quand on tape au moins 3 caractères dans la recherche | le texte tapé, la langue, le centre de la carte arrondi, l'emprise fixe de la carte (`MAX_BOUNDS`) et le nombre de réponses voulu |

- Le centre de la carte envoyé aux deux services de recherche est arrondi au dixième de degré, soit environ 10 km : après « Ma position », la carte est centrée près de vous, et rien de plus précis ne part. <!-- À VÉRIFIER : lot en cours -->
- Les serveurs des fonds voient la zone regardée, comme pour toute carte en ligne. Quand on prépare un tracé pour le hors ligne, ils reçoivent en plus les demandes de tuiles du couloir du tracé (sauf OpenTopoMap, jamais préchargé) : ils peuvent donc deviner le parcours, mais ne reçoivent jamais le fichier GPX.
- Les autres sites ne reçoivent que l'origine du site (https://nathancouturier.github.io), jamais l'adresse complète de la page (réglage `strict-origin-when-cross-origin` d'`index.html`). La position de la carte, après le `#` de l'adresse, n'est jamais envoyée.
- La position donnée par « Ma position » vient du navigateur et reste dans le navigateur : elle sert seulement à placer le point et la carte.
- Les liens (GitHub, licences, sources) ne sont suivis que si on clique dessus.
- Ce qui est rangé dans le navigateur : la langue, les réglages et l'état du tracé préparé dans `localStorage` (clés `czb.lang`, `czb.reseau`, `czb.fond` et `czb.horsLigne`) ; la coque du site (cache `czb-coque-` suivi de sa version) et le tracé préparé pour le hors ligne (cache `czb-hors-ligne-v1`) dans le cache du navigateur. « Supprimer les données hors ligne » efface le second cache et l'information sur l'enregistrement ; la coque reste, c'est le site lui-même.
- Le pipeline, dans GitHub Actions, se présente aux serveurs des sources sous un nom générique, sans le nom du dépôt ni de son propriétaire. La clé d'OpenCellID est un secret, jamais écrit dans les journaux.

## Licences et crédits

Chaque source a sa licence et ses mentions obligatoires. Le site affiche celles des fonds et des données de couverture en pied de carte et dans le panneau « Sources ». Le détail (texte exact des mentions, adresses, dates de lecture des conditions) est dans [docs/sources.md](docs/sources.md). En résumé :

- couverture :
  - Arcep : « Licence Ouverte / Open Licence » (identifiant `fr-lo` sur data.gouv.fr). L'adresse officielle de cette licence renvoie aujourd'hui au texte de la version 2.0, et le site lie la page de cette version (https://www.data.gouv.fr/pages/legal/licences/etalab-2-0) ;
  - OFCOM : géodonnées de la Confédération, utilisation libre, source à citer ;
  - AGCOM : CC BY 4.0. Les conditions demandent de reproduire un logo dans toute œuvre dérivée de ces données ; le site affiche aussi la phrase placée sous ce logo : « BroadbandMap di Agcom - Autorità per le garanzie nelle comunicazioni è distribuito con Licenza Creative Commons Attribuzione 4.0 Internazionale. » Le logo est dans `public/licences/agcom-bbmap.jpg` ; le panneau Sources l'affiche, en lien vers https://maps.agcom.it/. Il est aussi joint à la release de données et cité dans `SOURCES.md` ; <!-- À VÉRIFIER : lot en cours -->
  - ministère espagnol : aucune licence n'est attachée à la carte. Mention affichée : « Origen de los datos: Ministerio para la Transformación Digital y de la Función Pública ». La réutilisation s'appuie sur les conditions générales de réutilisation du site du ministère (citer la source et la date) : lecture raisonnable, pas une autorisation écrite (voir [Décisions laissées au propriétaire](#décisions-laissées-au-propriétaire)) ;
- zones estimées : OpenCellID, CC BY-SA 4.0 (« Cell tower data from OpenCellID, licensed under CC BY-SA 4.0 ») : les zones estimées en dérivent et suivent cette licence. Copernicus DEM GLO-30 : la licence demande que les mentions de ses articles 6 (b) et 6 (c) suivent les données redistribuées ; la mention 6 (b) reste en anglais, mot pour mot, seule la phrase 6 (c) peut être traduite. Son article 6 (e) impose de lier les utilisateurs suivants aux mêmes obligations. Le manifest et `SOURCES.md` portent ces phrases ;
- fonds de carte : « © IGN » (Géoplateforme, en lien vers ses conditions générales d'utilisation) ; « ©swisstopo », sans espace, forme courte admise par les conditions de swisstopo ; « CC BY 4.0 ign.es » pour IGN España ; pour OpenTopoMap, « Kartendaten: © OpenStreetMap-Mitwirkende, SRTM | Kartendarstellung: © OpenTopoMap (CC-BY-SA) », et sur téléphone sa forme courte « © OpenStreetMap, SRTM | © OpenTopoMap (CC-BY-SA) », avec leurs liens ;
- recherche de lieux : géocodage de la Géoplateforme (IGN) ; Photon (komoot), données © les contributeurs d'OpenStreetMap, avec un lien vers https://www.openstreetmap.org/copyright. Ce crédit vient des règles d'attribution d'OpenStreetMap, pas des conditions de Photon ;
- contours des pays (mentions du manifest, affichées dans le panneau Sources) : « Contours administratifs, data.gouv.fr (licence ODbL), d'après ADMIN EXPRESS de l'IGN » ; « ©swisstopo, swissBOUNDARIES3D » ; « Istat, Confini delle unità amministrative a fini statistici al 1° gennaio 2026, CC BY 4.0, données modifiées » ; « Obra derivada de BDLJE CC-BY 4.0 ign.es » ; « © OpenStreetMap contributors (ODbL 1.0) » pour l'Andorre et Monaco ;
- GPX de test de `samples/` : chemins © les contributeurs d'OpenStreetMap, lus par l'API Overpass ; ces deux fichiers sont mis à disposition sous ODbL 1.0. Altitudes : Copernicus DEM GLO-30.

Le site s'appuie sur MapLibre GL JS, pmtiles, @tmcw/togeojson, fast-png et Vite ; le pipeline sur GDAL, NumPy, Pillow, PyYAML et la bibliothèque Python pmtiles.

Licence du code : `package.json` ne déclare pas de licence, et le dépôt n'a pas de fichier de licence. Le choix revient au propriétaire.
