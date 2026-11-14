# Carte des zones blanches

Une carte de randonnée qui montre où il y a du réseau mobile et où il n'y en a pas. Elle couvre la France métropolitaine et la Corse, la Suisse, l'Italie frontalière (Val d'Aoste, Piémont, Ligurie), l'Espagne pyrénéenne (Catalogne, Aragon, Navarre, Pays basque), l'Andorre et Monaco. On importe un tracé GPX (le fichier d'un parcours, tel que l'enregistre une montre ou une application de randonnée) et on obtient la liste des portions du parcours sans réseau. Les six pays sont présents dans les données en ligne (voir [Pays couverts et nature des données](#pays-couverts-et-nature-des-données)).

**Le site : https://nathancouturier.github.io/carte-zones-blanches/**

Site personnel, 100 % statique : pas de serveur, pas de compte, pas de suivi. Le GPX reste dans le navigateur, il n'est jamais envoyé nulle part. L'interface est pensée d'abord pour le téléphone (Chrome sur Android) et marche aussi sur ordinateur.

Ce README donne l'essentiel. Le détail est dans trois documents. [docs/architecture.md](docs/architecture.md) décrit le site. [docs/pipeline.md](docs/pipeline.md) décrit le pipeline de données (la chaîne de traitement qui fabrique les données de la carte) et les workflows (les tâches automatiques du dépôt sur GitHub). [docs/sources.md](docs/sources.md) décrit les sources, leurs licences et leurs méthodes.

## Sommaire

- [Ce que fait le site](#ce-que-fait-le-site)
- [Pays couverts et nature des données](#pays-couverts-et-nature-des-données)
- [Le secret OPENCELLID_TOKEN](#le-secret-opencellid_token)
- [Architecture](#architecture)
- [Mettre à jour les données](#mettre-à-jour-les-données)
- [Ajouter une langue](#ajouter-une-langue)
- [Ajouter ou changer une source](#ajouter-ou-changer-une-source)
- [Changer l'emprise](#changer-lemprise)
- [Développement local](#développement-local)
- [Limites](#limites)
- [Décisions laissées au propriétaire](#décisions-laissées-au-propriétaire)
- [Vie privée](#vie-privée)
- [Licences et crédits](#licences-et-crédits)

## Ce que fait le site

La carte affiche, par-dessus un fond de carte de randonnée, la couverture mobile théorique publiée par les autorités de chaque pays, ou une estimation là où il n'existe pas de source officielle exploitable. Par défaut, seuls les problèmes sont dessinés : en rouge les zones sans couverture, en orange la couverture limitée. Un GPX importé est découpé en portions selon la couverture, et un rapport liste les zones blanches avec leurs kilomètres et leurs altitudes.

Sur téléphone, les panneaux s'ouvrent en bas de l'écran. Sur ordinateur (fenêtre d'au moins 900 px de large), ils s'ouvrent sur le côté. Rien n'est empilé : chaque panneau s'ouvre au clic, et ouvrir un panneau ferme la recherche.

### Mode d'emploi

- **Carte.** Plein écran, centrée sur la France au départ. Elle reste orientée au nord. L'adresse de la page garde la position de la carte (par exemple `#11/44.9/6.42` : zoom, latitude, longitude) : on peut la mettre en favori ou l'envoyer.
- **Loupe.** Recherche d'un lieu avec suggestions, dès 3 caractères : en France par le géocodage de l'IGN (le service qui trouve un lieu à partir de son nom), Corse comprise ; à l'étranger par Photon (données OpenStreetMap, la carte libre et collaborative). [Détail](docs/architecture.md#recherche-de-lieux).
- **Ma position.** Le bouton en haut à droite, à côté de la roue dentée, affiche votre position et centre la carte dessus. Le point suit ensuite la marche sans déplacer la carte : un nouvel appui recentre. Si la position manque, un message dit pourquoi. [Détail](docs/architecture.md#ma-position).
- **Réseau.**
  - Service : « Internet mobile » ou « Appels et SMS ». Les appels et SMS n'existent que pour la France ; le panneau dit pour quels pays le service choisi manque.
  - Opérateur en France : « Tous opérateurs », Orange, SFR, Bouygues Telecom ou Free. « Tous opérateurs » donne, en chaque point, le meilleur niveau parmi les opérateurs. C'est ce qui compte pour le 112, le numéro d'urgence, qui passe par n'importe quel réseau.
  - Rubrique repliable « À l'étranger » : « Tous opérateurs du pays » par défaut, car la couverture réelle dépend des accords d'itinérance de votre opérateur (l'usage d'un réseau étranger avec votre forfait). Quand la source le permet, on peut choisir un opérateur (Espagne) ou un nombre de réseaux (Suisse, Italie). En Andorre et à Monaco, il n'y a pas de choix.
  - Case « Afficher toute la couverture » : ajoute la bonne et la très bonne couverture, en vert. Un curseur règle l'opacité, et le panneau donne la légende. Ces réglages sont mémorisés dans le navigateur.
  - Zones estimées : elles sont hachurées. Là où leur niveau n'est pas dessiné (la bonne couverture, dans l'affichage par défaut), de fins traits gris les signalent quand même. La légende dit les deux.
- **Fond.** « Automatique » (le choix par défaut) prend le fond national du pays au centre de la carte : Plan IGN classique en France, swisstopo en Suisse, IGN España en Espagne, OpenTopoMap (données OpenStreetMap) ailleurs. On peut aussi choisir soi-même Plan IGN classique, Plan IGN standard, swisstopo, IGN España, OpenTopoMap ou les photos aériennes de l'IGN, et ajouter l'estompage du relief de l'IGN (l'ombrage qui fait ressortir le relief, France seulement). [Détail](docs/architecture.md#fonds-de-carte).
- **Importer un GPX.** Par le bouton, ou en glissant le fichier sur la carte (ordinateur). Le site lit les traces, sinon les routes, et écarte les points aberrants. Le tracé s'affiche avec un liseré blanc, et la carte zoome dessus. Pour l'analyse, le parcours est rééchantillonné : il est refait avec un point tous les 20 m, dont le site lit la couverture. Une fois l'analyse faite, il prend les couleurs de la couverture : rouge, orange, vert, et gris là où il n'y a pas de données. Il passe en pointillé là où la couverture est estimée. [Détail](docs/architecture.md#analyse-dun-gpx).
- **Rapport** (le bouton apparaît après l'import). Il donne la distance, le dénivelé et les pays traversés, puis la part du parcours par niveau, pour l'opérateur choisi et pour tous opérateurs. Il liste les zones blanches, par exemple « km 12,4 à 14,1, soit 1,7 km, altitude 1 850 à 2 100 m, Italie, estimée ». Toucher une zone la met en surbrillance et zoome dessus. Des avertissements s'ajoutent, par exemple pour la Suisse, l'Andorre et Monaco, hors de l'itinérance de l'Union européenne (vérifiez votre forfait). Les portions hors des données de couverture sont exclues des pourcentages. [Détail](docs/architecture.md#rapport).
- **Profil altimétrique** (dans le rapport, quand plus de la moitié des points du tracé ont une altitude). Il est coloré selon la couverture, et une courte zone blanche y reste visible. Survoler ou toucher le profil, ou le parcourir avec les flèches du clavier, place un repère sur la carte. [Détail](docs/architecture.md#profil-altimétrique).
- **Emporter le résultat.** « Télécharger le GPX enrichi » donne le GPX d'origine avec un point de passage au début et à la fin de chaque zone blanche, pour une montre ou une application GPS. « Copier le rapport » met le rapport en texte dans le presse-papiers. [Détail](docs/architecture.md#gpx-enrichi-et-rapport-en-texte).
- **Hors ligne** (dans le rapport). « Préparer ce tracé pour le hors ligne » enregistre dans le navigateur le tracé, la couverture d'un couloir de 700 m de part et d'autre et le fond de carte le long du parcours (avec l'estompage du relief s'il est affiché), quand son fournisseur l'autorise. Sans réseau, le site recharge tout seul le tracé préparé. Un seul tracé est gardé. À faire avant de partir, avec du réseau (voir [Limites](#limites)). [Détail](docs/architecture.md#mode-hors-ligne).
- **Langues.** Bouton « Paramètres » (roue dentée), puis « Langue » : Français, Español, Català, Italiano, Deutsch. Le choix est mémorisé dans le navigateur. Le paramètre `?lang=` dans l'adresse force une langue, par exemple https://nathancouturier.github.io/carte-zones-blanches/?lang=es. Les nombres et les distances suivent la langue choisie, y compris les nombres insérés dans les messages.
- **Sources.** Les mentions des fonds et des données affichés sont en pied de carte, avec leurs liens. Sur téléphone, le pied de carte se replie au premier geste sur la carte, et le bouton « © » le rouvre. Le panneau « Sources » (lien « Sources » du pied de carte, ou « Paramètres » puis « Sources des données ») commence par la phrase « Couverture théorique, des écarts locaux sont possibles. » Il donne, pour chaque pays, la source, la date des données, la méthode et la licence. [Détail](docs/architecture.md#pied-de-carte-et-panneau-sources).

## Pays couverts et nature des données

| Zone | Source de la couverture | Nature | Choix proposés | Services | Date des données |
|---|---|---|---|---|---|
| France métropolitaine et Corse | Arcep, « Mon réseau mobile » (couvertures théoriques) | officielle par opérateur, 4 niveaux | Tous opérateurs, Orange, SFR, Bouygues Telecom, Free | internet mobile (4G), appels et SMS (2G et 3G) | 2e trimestre 2026 (situation au 30 juin 2026) |
| Suisse | OFCOM, atlas de la large bande | officielle agrégée, couvert ou non | Tous opérateurs du pays, Les 3 réseaux à la fois | internet mobile (4G) | 30 avril 2026 |
| Italie : Val d'Aoste, Piémont, Ligurie | AGCOM, Broadband Map | officielle agrégée, couvert ou non | Tous opérateurs du pays, Au moins 2 réseaux, Au moins 3 réseaux, Les 4 réseaux à la fois | internet mobile (4G) | 27 janvier 2026 |
| Espagne : Catalogne, Aragon, Navarre, Pays basque | Ministerio para la Transformación Digital y de la Función Pública, « Mapa de Servicios de Banda Ancha Móvil 2024 » | officielle par opérateur, couvert ou non | Tous opérateurs du pays, Movistar, Orange, Vodafone, Xfera Móviles | internet mobile (4G) | 30 juin 2024 |
| Andorre | estimation : antennes OpenCellID et relief Copernicus DEM | estimée, 3 niveaux | aucun choix : tous réseaux confondus | internet mobile (cellules 4G et 5G ; aucune cellule 5G dans le fichier lu) | mois du calcul |
| Monaco | la même estimation | estimée, 3 niveaux | aucun choix : cellules du code pays mobile monégasque seulement (voir [Limites](#limites)) | internet mobile (cellules 4G et 5G ; aucune cellule 5G dans le fichier lu) | mois du calcul |

Les six pays sont publiés : ils figurent tous dans `data-2026-11-14`, la release de données en ligne (une publication du dépôt GitHub, avec les fichiers de données joints). Elle a été construite le 14 novembre 2026, avec une estimation de novembre 2026 pour l'Andorre et Monaco.

Ce que veulent dire ces mots :

- **Officielle par opérateur** : la source dit quel opérateur couvre chaque lieu.
- **Officielle agrégée** : la source dit combien de réseaux couvrent un lieu, mais pas lesquels. On choisit alors un seuil. Par exemple, « Les 3 réseaux à la fois » en Suisse montre où vous aurez du réseau quel que soit l'opérateur utilisé en itinérance.
- **Estimée** : il n'existe pas de carte officielle exploitable. La couverture est calculée à partir des antennes connues d'OpenCellID et du relief : chaque pixel reçoit un niveau selon la distance des sites d'antennes et leur visibilité (méthode, calage et résultats : [L'estimation](docs/pipeline.md#lestimation)). Ces zones sont signalées partout : hachures ou fins traits gris sur la carte, hachures dans le profil, tracé en pointillé, et le mot « estimée » dans le rapport et dans le GPX enrichi.
- **Couvert ou non** : la source n'a pas de niveau de qualité. Sur la carte et dans le rapport, « bonne couverture » y veut dire « couvert ».

Ce tableau décrit ce que construit la configuration de production (`pipeline/config.yaml`). Le panneau « Sources » du site dit quels pays figurent vraiment dans les données publiées, avec la date de chaque source. Le détail des sources (adresses, licences, méthodes, limites) est dans [docs/sources.md](docs/sources.md).

## Le secret OPENCELLID_TOKEN

L'estimation de l'Andorre et de Monaco a besoin d'une clé d'accès gratuite à OpenCellID, la base d'antennes utilisée. Cette clé est rangée dans un secret du dépôt : une valeur que GitHub donne aux workflows sans jamais l'afficher. Le secret `OPENCELLID_TOKEN` existe depuis le 14 novembre 2026, et le premier téléchargement réel a réussi le même jour.

Si OpenCellID ne répond pas ou refuse la clé, la construction reprend la copie de travail d'un mois précédent quand elle existe (le résultat déjà calculé, gardé avec les données). Sans le secret, l'Andorre et Monaco disparaissent de la carte, même si une copie existe ; de même quand OpenCellID échoue et qu'il n'y a pas de copie. Le panneau « Sources » le dit.

Pour créer ou remplacer la clé :

1. Créer un compte gratuit sur [opencellid.org](https://opencellid.org) (page d'inscription : https://my.opencellid.org/register). Se connecter, puis afficher la clé dans la rubrique « API Access Tokens » du tableau de bord.
2. Dans le dépôt GitHub : Settings, Secrets and variables, Actions, puis New repository secret (ou la modification du secret existant). Nom : `OPENCELLID_TOKEN`. Valeur : la clé.
3. Si les deux pays étaient absents, relancer le workflow « Données » : onglet Actions, « Données », « Run workflow », périmètre « production » (celui du site en ligne). Si le secret manquait, le pipeline voit que la source est redevenue disponible et reconstruit les données : inutile de cocher « Reconstruire même si aucune source n'a changé », et sans relance, le passage mensuel suivant le fera. Si le secret existait mais que la clé était refusée, il faut cocher cette case : rien d'autre ne signale le changement.

La clé n'apparaît jamais dans les journaux. Le détail (téléchargement, repli, limites d'OpenCellID) est dans [docs/pipeline.md](docs/pipeline.md#opencellid-et-le-secret-opencellid_token).

## Architecture

### Le site

Le site est une seule page, construite avec Vite (l'outil qui assemble les fichiers du site) et TypeScript (du JavaScript dont les types sont vérifiés). Il utilise MapLibre GL JS (la carte), pmtiles (lecture des archives de tuiles, les carrés d'image qui forment la carte), @tmcw/togeojson (lecture du GPX) et fast-png (décodeur d'images PNG écrit en JavaScript, qui sert de contrôle et de secours). Il n'y a pas de serveur d'application : GitHub Pages (l'hébergement de sites de GitHub) sert des fichiers statiques sous `/carte-zones-blanches/` (réglage `base` de `vite.config.ts`).

Au déploiement, les données de couverture sont posées dans `data/`, à côté de la page : un fichier `manifest.json`, qui les décrit, et une ou plusieurs archives `.pmtiles`, qui contiennent les tuiles (voir les deux sections suivantes). Ces données ne sont jamais enregistrées dans git (l'historique du code) : elles sont jointes aux releases `data-*` du dépôt, et le déploiement les copie dans le site. Pour le hors ligne, un Service Worker (un petit programme que le navigateur garde à côté du site) enregistre la coque du site : la page et tous les fichiers qu'elle charge. Une fois cette coque complète, la page vient d'elle, avec ou sans réseau. Il sert aussi les tuiles de fond enregistrées pour un tracé. Détail du site : [docs/architecture.md](docs/architecture.md).

### Des tuiles de données, pas des images

La couverture est découpée en tuiles : des carrés de 256 pixels, des zooms 0 à 12 (le zoom est le niveau de détail de la carte). Les tuiles sont réunies dans des archives PMTiles : un seul fichier par archive, dont le navigateur ne lit que les morceaux utiles.

Ces tuiles sont des images PNG (un format d'image sans perte), mais chaque pixel porte des données, pas une couleur. Un pixel a quatre canaux, d'habitude le rouge, le vert, le bleu et l'opacité. Ici, le premier donne le niveau d'internet mobile dans 4 emplacements (un opérateur, ou un seuil « au moins N réseaux »). Le deuxième donne le niveau des appels et SMS, le troisième le pays et le type de source, et le dernier dit si le lieu est dans la zone couverte. Le site lit lui-même ces tuiles par un protocole MapLibre personnalisé (un petit programme qui fournit les tuiles à la carte), et les recolore selon les réglages. Ce choix donne peu de fichiers, un changement d'opérateur instantané, et les mêmes tuiles servent à l'affichage et à l'analyse des GPX. Détail de l'encodage : [docs/architecture.md](docs/architecture.md#encodage-des-tuiles).

### Le manifest

Le fichier `manifest.json`, publié avec les tuiles, dit au site comment les lire. Pour chaque pays, il dit ce que contient chaque emplacement : un opérateur nommé, ou un seuil « au moins N réseaux ». Pour chaque source, il donne son nom, sa date, sa licence, ses mentions et la façon de lire ses niveaux. Le décodeur du site est piloté par ce fichier. Rien n'est codé en dur par pays : un pays ajouté dans le pipeline apparaît sur la carte sans toucher au code de la couche réseau. Liste des champs : [docs/architecture.md](docs/architecture.md#le-manifest).

### Le pipeline de données

Le pipeline transforme les sources de couverture en tuiles. Il est écrit en Python avec GDAL (une bibliothèque de traitement des données géographiques) et tourne dans GitHub Actions, le service de GitHub qui lance les workflows sur ses machines. Il a un module par source, c'est-à-dire un fichier Python qui sait la lire (`fr_arcep`, `ch_bakom`, `it_agcom`, `es_mtd`, `estimation_opencellid`). Toutes les sources sont ramenées sur la même grille, alignée sur les tuiles du zoom 12.

Une construction prépare les sources et pose le contour de chaque pays sur la grille (son masque). Elle lit ensuite les sources l'une après l'autre, un fichier à la fois, et comble les petits trous entre les contours. Puis elle fabrique les tuiles, le manifest et `SOURCES.md` (les mentions des sources). Un test de cohérence relit ensuite des points tirés au hasard : la construction échoue au moindre écart entre la source et les pixels. Le résultat est publié dans une release `data-AAAA-MM-JJ`, avec un numéro en plus s'il y en a déjà une ce jour-là. Détail : [docs/pipeline.md](docs/pipeline.md).

### Les workflows GitHub

Un workflow est une tâche automatique de GitHub Actions, décrite par un fichier de `.github/workflows/`. Il y en a cinq. « Tests » (`ci.yml`) teste et construit le site, et teste le pipeline. Il tourne à chaque push (envoi de modifications) sur une autre branche que `main`, sauf si le push ne touche que des fichiers `.md` ou des sondes, et sur chaque pull request (demande de fusion d'une branche). Une branche est une ligne de travail du dépôt ; `main` est la principale. « Données » (`build-data.yml`) construit les tuiles, à la main et le 5 de chaque mois. Pour la production, il ne reconstruit que si une source a changé, sauf si on le force, puis publie une release ; un essai n'est jamais publié. « Déploiement » (`deploy.yml`) construit le site avec la dernière release de données et le publie sur GitHub Pages, à chaque push sur `main` et après chaque nouvelle release. « Vérification » (`verification.yml`) contrôle ensuite le site en ligne dans un vrai navigateur. « Sonde » (`sonde.yml`) sert à vérifier une source avant de l'intégrer.

Certains se lancent à la main depuis l'onglet Actions du dépôt (bouton « Run workflow »), d'autres tout seuls. Détail de chaque workflow : [docs/pipeline.md](docs/pipeline.md#les-workflows).

### Arborescence du dépôt

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
  i18n/                 traductions : index.ts, noscript.ts (message sans JavaScript), et un fichier
                        JSON par langue dans locales/
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
docs/architecture.md    le site en détail
docs/pipeline.md        le pipeline et les workflows en détail
.github/workflows/      Tests, Données, Déploiement, Vérification, Sonde
```

## Mettre à jour les données

### Ce qui est automatique

Le 5 de chaque mois, le workflow « Données » regarde si une source a changé. Si oui, il reconstruit tout, vérifie, publie une nouvelle release et relance le déploiement. Il compare l'état de chaque source en ligne (fichiers, dates, nombres de polygones) à celui de la dernière release. Augmenter le numéro de version du pipeline (`pipeline/czb/__init__.py`) provoque aussi une reconstruction au passage suivant. C'est le cas en ce moment : ce numéro est passé à 0.2.0 après la construction du 14 novembre 2026, donc le passage du 5 décembre 2026 reconstruira les données une fois. L'estimation de l'Andorre et de Monaco sera alors recalculée, et le panneau « Sources » affichera le nombre de sites d'antennes connus. L'estimation n'est refaite que si une construction a lieu un autre mois : OpenCellID change tous les jours, ce n'est pas une raison de tout reconstruire. Le détail de ce qui est comparé, source par source, est dans [docs/pipeline.md](docs/pipeline.md#ce-que-compare-la-détection).

### Ce qui se fait à la main

Ce qui n'est pas surveillé se met à jour à la main dans `pipeline/config.yaml` :

- les contours des pays : un nouveau contour ne déclenche pas de reconstruction. Deux adresses portent un millésime, à changer quand un nouveau paraît : swissBOUNDARIES3D (janvier 2026) et les limites de l'ISTAT (1er janvier 2026) ;
- une nouvelle édition de la carte espagnole : un garde-fou la signale (voir [docs/pipeline.md](docs/pipeline.md#ce-que-compare-la-détection)), mais il faut changer à la main `layer_url`, `item_url`, `name` et `data_date` de la source `es_mtd` (la date des données est écrite dans la configuration).

De même, le pipeline lit le service italien `Grid100/mobile_4G` : que la prochaine édition de l'AGCOM soit publiée à cette même adresse n'est pas vérifié.

### Forcer une reconstruction

Onglet Actions, « Données », « Run workflow » : périmètre « production », et cocher « Reconstruire même si aucune source n'a changé ». C'est utile après une modification du pipeline.

### Faire un essai sur un seul pays

Onglet Actions, « Données », « Run workflow » : choisir un périmètre d'essai et les services (`data`, ou `data,voice`). La liste des périmètres (section `scopes` de `pipeline/config.yaml`) est dans [docs/pipeline.md](docs/pipeline.md#périmètres-dessai). Un essai n'est jamais publié. Pour le regarder, télécharger l'artefact « donnees » depuis la page du run : l'artefact est un lot de fichiers, gardé 7 jours, et le run est le lancement du workflow. Copier ensuite ses fichiers `.pmtiles` et `manifest.json` dans `public/data/`, puis lancer la commande `npm run dev` (voir [Développement local](#développement-local)).

### Savoir ce qui est en ligne

La release de données en ligne est `data-2026-11-14`, publiée le 14 novembre 2026 à 19 h 03 UTC (run 43624308783) : les six pays, 353,13 Mo en 7 archives (la plus grosse : 69,67 Mo), et un test de cohérence sans écart sur 1 200 points des sources et 420 points des contours. Le panneau « Sources » du site donne la date de chaque source et la date de génération des tuiles. Sur GitHub, la release `data-*` la plus récente par date de publication (le nom ne suffit pas : voir [Limites](#limites)) contient aussi `rapport-construction.json` (les chiffres de la construction), `SOURCES.md`, `etat-sources.json` et les fichiers de points témoins (les pixels de contrôle du test de cohérence). Les chiffres de la construction en ligne sont dans [docs/pipeline.md](docs/pipeline.md#chiffres-de-la-construction-de-production).

## Ajouter une langue

1. Copier `src/i18n/locales/fr.json` sous le code de la langue, par exemple `en.json`.
2. Dans le bloc `_meta`, mettre le nom de la langue, écrit dans cette langue, et la balise qui sert à formater les nombres et les dates : `{"name": "English", "locale": "en-GB"}`.
3. Traduire les valeurs, sans toucher aux clés (les noms des textes) ni aux paramètres entre accolades (`{km}`, `{count}`, etc.). Les clés qui finissent par `_one` et `_other` sont les formes du singulier et du pluriel. Pas de tiret cadratin ni demi-cadratin : un test les refuse.
4. Mettre à jour le premier test de `tests/i18n.test.ts` (« propose les cinq langues, le français en premier »), qui vérifie la liste exacte des langues. L'ordre d'affichage vient de `PREFERRED_ORDER` dans `src/i18n/index.ts` (l'anglais y est déjà prévu, après l'allemand). Une langue absente de cette liste vient après les autres, par ordre alphabétique.
5. Lancer `npm test`. Le test « toutes les langues ont exactement les mêmes clés » signale toute clé manquante ou en trop. D'autres tests vérifient les paramètres entre accolades et qu'aucun texte n'est vide.

La langue apparaît toute seule dans les paramètres et répond à `?lang=`. Si une clé manque malgré tout, le site retombe sur le français. Les noms des pays viennent du navigateur (`Intl.DisplayNames`) : rien à traduire. La recherche à l'étranger (Photon) ne connaît que l'allemand, l'anglais et le français : pour une autre langue, elle donne les noms locaux. Le manifeste web (`public/manifest.webmanifest`, qui donne le nom et l'icône du site ajouté à l'écran d'accueil) reste en français.

La phrase affichée quand JavaScript est désactivé (le `<noscript>` d'`index.html`) est la clé `app.noscript` : la construction l'écrit d'elle-même pour chaque fichier de langue (`src/i18n/noscript.ts`). Seules les traductions des textes du manifest (noms des sources, licences, mentions de contour) vivent ailleurs, dans `pipeline/config.yaml` (clés `name_i18n`, `licence_i18n` et `credit.text_i18n`). Le pipeline exige dans chacune toutes les langues de la liste `LANGUAGES` de `pipeline/czb/context.py`, ni plus ni moins. Pour la nouvelle langue : l'ajouter à cette liste, ajouter sa traduction dans chacune de ces clés, puis [forcer une reconstruction](#forcer-une-reconstruction). D'ici là, elle montre ces textes tels qu'ils sont écrits, en français pour la plupart.

Les tests des traductions sont décrits dans [docs/architecture.md](docs/architecture.md#tests).

## Ajouter ou changer une source

1. **Vérifier la source** avant tout : la licence doit autoriser la réutilisation ; puis la date, le format, les champs, les valeurs. Le workflow « Sonde » sert à cela. Ne rien deviner, et ne jamais récupérer de données sur les sites des opérateurs ni sur des cartes non ouvertes.
2. **La documenter** dans `docs/sources.md` : source, date, licence, méthode, limites.
3. **La déclarer** dans `pipeline/config.yaml` : le pays dans `countries`, la source dans `sources`, et leurs traductions facultatives. La liste des clés est dans [docs/pipeline.md](docs/pipeline.md#déclarer-la-source). Le premier test de `pipeline/tests/test_traductions.py` liste les sources et les contours traduits : y ajouter les nouveaux.
4. **Écrire le module** dans `pipeline/czb/sources/`, en partant d'un module proche, et le commencer par un commentaire qui décrit la source vérifiée. Ce qu'il doit fournir est dans [docs/pipeline.md](docs/pipeline.md#écrire-le-module).
5. **L'enregistrer** dans `pipeline/czb/sources/__init__.py` (dictionnaire `REGISTRY`).
6. **Ajouter un test** sur des données synthétiques dans `pipeline/tests/`, sans réseau.
7. Pour un nouveau pays, **ajouter un périmètre** dans `scopes` et son nom dans la liste `options` de `.github/workflows/build-data.yml`, pour pouvoir l'essayer seul. Puis lancer un essai. Pour le publier, ajouter aussi le pays à la liste `countries` du périmètre `complet`, celui de la production.

Le site n'a pas besoin d'être modifié : il lit le nouveau pays dans le manifest. Seul le fond du mode Automatique se règle à part, dans `NATIONAL_BASEMAP` de `src/map/basemaps.ts` (à défaut, le pays reçoit OpenTopoMap). Un nouveau fond de carte se déclare dans `BASEMAPS` et `BASEMAP_ORDER` du même fichier, avec sa mention et sa règle de préchargement hors ligne, et son nom dans les fichiers de langue.

## Changer l'emprise

L'emprise est la zone couverte par les données. Tout se règle dans `pipeline/config.yaml` :

- `countries` : les pays, dans l'ordre de priorité aux frontières. Pour chacun, le contour (`mask`) : adresse, couche, filtre `where`, nombre d'entités attendu `expect` (le pipeline s'arrête si le filtre ne trouve plus ce qu'il doit), fourchette de surface `expect_area_km2` pour un contour tiré d'OpenStreetMap, et mention à citer `credit`.
- Les filtres des sources doivent suivre le contour. Pour l'Italie : `where: "COD_REG IN (1, 2, 7)"` et `expect: 3` dans le masque, et `regions: [1, 2, 7]` dans `it_agcom`. Pour l'Espagne : une adresse de contour par communauté autonome (`nationalcode`) et `expect: 4`, et `regions: ["02", "09", "15", "16"]` dans `es_mtd`.
- La France est prise en entier (les départements dont le code a 2 caractères, Corse comprise), sauf dans un périmètre qui donne une liste de `departements`.
- `scopes` : les périmètres. La section `production` dit lequel sert au site en ligne : `complet`, avec internet mobile et appels et SMS. Un pays absent de `complet` n'est pas publié.
- `limits` : 70 Mo visés par archive, 90 Mo au plus, 900 Mo pour tout le site. `grid.block_zoom` règle la taille des blocs.

Côté site, `MAX_BOUNDS` dans `src/config.ts` limite la zone où la carte peut aller (c'est aussi la zone de la recherche à l'étranger), et `INITIAL_VIEW` est la vue de départ.

Le traitement des frontières est décrit dans [docs/pipeline.md](docs/pipeline.md#grille-commune-et-frontières), les périmètres d'essai dans [docs/pipeline.md](docs/pipeline.md#périmètres-dessai).

## Développement local

### Lancer le site en local

Il faut Node 22 (la version des workflows) et npm. Node fait tourner JavaScript hors du navigateur ; npm installe les dépendances et lance les commandes du projet. Vitest est l'outil des tests automatiques du site.

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

### Lancer le pipeline en local

Il faut Python 3, GDAL avec son module Python (`osgeo`), NumPy, 7-Zip (`7z`, un outil de décompression) et les paquets de `pipeline/requirements.txt`. Le plus simple est l'image des workflows, `ghcr.io/osgeo/gdal:ubuntu-small-3.13.3` : un système tout prêt, où GDAL est installé. Dans un conteneur de cette image (un système isolé lancé à partir d'elle), à la racine du dépôt, ce sont les commandes du job « Pipeline » (l'une des tâches du workflow) de `.github/workflows/ci.yml` :

```bash
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends p7zip-full python3-pip
python3 -m pip install --break-system-packages -q -r pipeline/requirements.txt
cd pipeline && python3 -m pytest -q tests
```

Les tests, lancés par pytest (l'outil de tests du pipeline), n'utilisent que des données synthétiques et n'ont pas besoin du réseau.

Une vraie construction a besoin d'Internet pour joindre les sources. Par exemple, sur le petit périmètre des Hautes-Alpes (il télécharge quand même les 4 fichiers 4G de l'Arcep pour toute la métropole, environ 1,1 Go en tout) :

```bash
cd pipeline
python3 -m czb.cli build --scope hautes-alpes --services data
python3 -m czb.cli verify --out out
mkdir -p ../public/data && cp out/*.pmtiles out/manifest.json ../public/data/
```

Le résultat est dans `pipeline/out/`, les fichiers de travail dans `pipeline/work/` (deux dossiers ignorés par git). Pour l'Andorre et Monaco, il faut la variable d'environnement `OPENCELLID_TOKEN` ; sans elle, ces pays sont laissés de côté, avec un message. Toutes les commandes du pipeline sont dans [docs/pipeline.md](docs/pipeline.md#les-commandes).

### Vérifier dans un navigateur

Les mêmes commandes que le workflow « Vérification », qui utilise Playwright (un outil qui pilote un vrai navigateur) :

```bash
cd e2e
npm install --no-audit --no-fund
npx playwright install --with-deps chromium
SITE_URL=https://nathancouturier.github.io/carte-zones-blanches/ node verif.mjs
```

`SITE_URL` désigne le site à vérifier (par défaut, le site en ligne). `SANS_FONDS=1` saute les contrôles qui ont besoin des fonds de carte et de la recherche (pour un essai local, sans accès à ces services). `CAPTURES_DANS_LES_LOGS=1` écrit aussi les captures dans la sortie. Les captures sont enregistrées dans `e2e/captures/` (ignoré par git). Le script se termine en erreur si un contrôle échoue. Ce qu'il contrôle : [docs/pipeline.md](docs/pipeline.md#vérification).

## Limites

L'audit de conformité au cahier des charges (14 novembre 2026, 130 exigences) a relevé des écarts. Ceux qui ne sont pas corrigés figurent dans cette liste et dans [Décisions laissées au propriétaire](#décisions-laissées-au-propriétaire).

- **Couverture théorique.** Les cartes officielles sont des simulations ou des déclarations des opérateurs, pas des mesures. Sur le terrain, le relief, la végétation, la météo et votre téléphone changent le résultat. Le site le rappelle : « Couverture théorique, des écarts locaux sont possibles. » En montagne, ne comptez pas sur votre seul téléphone pour donner l'alerte.
- **Suisse, Italie, Espagne : « couvert » ou « non couvert » seulement.** Ces trois sources n'ont pas de niveau de qualité. « Bonne couverture » y veut dire « couvert ». On n'y voit donc jamais d'orange, et l'affichage par défaut n'y montre que le rouge des zones sans couverture. Ce n'est pas comparable aux 4 niveaux de l'Arcep. Les critères diffèrent aussi. En Espagne : un signal 4G d'au moins -115 dBm sous 1 GHz et -117 dBm au-dessus (le dBm mesure la puissance du signal reçu). En Suisse : la couverture extérieure annoncée par les opérateurs. En Italie : le critère n'est pas documenté dans les textes lus.
- **Sources agrégées.** En Suisse et en Italie, la source dit combien de réseaux couvrent un lieu, pas lesquels. À l'étranger, la couverture réelle dépend aussi des accords d'itinérance de votre opérateur. La Suisse, l'Andorre et Monaco ne font pas partie de l'itinérance de l'Union européenne. Les données italiennes datent du 27 janvier 2026.
- **Espagne : données de 2024.** Elles décrivent la situation au 30 juin 2024 : c'est l'édition la plus récente liée par le site du ministère au 14 novembre 2026. La vue par opérateur peut sous-estimer la couverture des clients d'opérateurs hébergés sur un autre réseau (opérateurs virtuels, itinérance nationale). Digi n'apparaît pas dans les données. « Tous opérateurs du pays » est la vue la plus sûre.
- **Appels et SMS : France seulement.** Les sources étrangères utilisées ne donnent que la 4G. L'estimation ne lit que les cellules 4G et 5G.
- **Andorre : une estimation très pessimiste.** Le fichier d'OpenCellID ne donne que 41 cellules 4G en Andorre, regroupées en 12 sites, tous dans le sud-ouest du pays, autour d'Andorre-la-Vieille. Tout le nord et l'est du pays ressortent « sans couverture » : vallées d'Encamp, de Canillo et d'Ordino, Soldeu, le Pas de la Case. Au total, 85,2 % du pays ressort sans couverture, ce qui est très probablement faux. L'erreur est du côté prudent, mais elle est grande. Rien ne détecte automatiquement une base d'antennes aussi pauvre. Les choix possibles sont dans [Décisions laissées au propriétaire](#décisions-laissées-au-propriétaire).
- **Zones estimées : la fiabilité.** Les positions d'OpenCellID sont des positions estimées de cellules, pas des positions de pylônes. Elles sont calculées à partir de mesures faites par les téléphones de bénévoles. Elles reposent sur peu de mesures : médiane de 6 mesures par cellule retenue en Andorre, 12 à Monaco. Seules les cellules vues dans les 18 derniers mois sont publiées. Ni la puissance, ni l'orientation des antennes, ni la végétation fine ne sont prises en compte. Lors du calage sur la France, une zone estimée « bonne » était réellement couverte dans 95 à 99 % des cas. Une zone blanche estimée n'était juste qu'à 81 % avec des positions d'antennes exactes. Avec des positions approximatives et des antennes manquantes, ce qui ressemble davantage à OpenCellID, elle n'était juste qu'environ une fois sur deux. Ces erreurs de position étaient simulées : la fiabilité réelle avec les données d'OpenCellID n'est pas mesurée. Une antenne absente de la base crée une fausse zone blanche. Ne comptez pas sur une zone estimée pour un appel d'urgence.
- **Monaco.** Seules les cellules du code pays mobile monégasque, le 212, sont lues. Dans la liste de l'UIT (l'Union internationale des télécommunications), ce code n'a qu'une entrée : Monaco Telecom. Les réseaux français captés à Monaco ne comptent pas. Au dernier essai, le 14 novembre 2026, le portail data.gouv.mc répondait encore par une erreur 503 et une page « Site en maintenance ». La conclusion « pas de source officielle exploitable » reste donc provisoire.
- **Frontières.** Les contours des pays viennent de producteurs différents et ne coïncident pas exactement. Le pipeline donne chaque pixel disputé à un seul pays et comble les petits interstices. La mesure faite le 14 novembre 2026 sur les tuiles de la release `data-2026-11-14-3` ne montre pas de bande blanche artificielle large. Mais une frange est plus souvent « sans couverture » : 1 à 3 pixels (30 à 85 m) côté italien, le premier pixel côté espagnol (chiffres dans [docs/pipeline.md](docs/pipeline.md#grille-commune-et-frontières)). L'erreur est du côté prudent : au passage d'une frontière, une zone blanche du rapport peut être allongée de quelques dizaines de mètres.
- **Hors zone.** La partie française du Léman, le Liechtenstein, quelques enclaves (Büsingen, Campione d'Italia, Treviño, Valle de Villaverde) et deux morceaux de Lombardie enclavés dans le Piémont (18 et 19 ha) restent hors zone.
- **Interstices de frontière.** Leurs pixels (13 780 dans les données en ligne) ont un niveau tiré de leurs voisins, le plus petit par prudence ; 3 n'ont aucun voisin connu et restent à « pas de couverture ». Mais ils portent le type de source de leur pays, officielle sauf en Andorre et à Monaco : rien ne les distingue sur la carte.
- **Résolution.** Un pixel du zoom 12 fait 26 à 28 m au sol dans les Alpes et les Pyrénées. Les sources sont souvent plus grossières : 100 m pour la Suisse et l'Italie, des mailles d'environ 28 m sur 38 m pour l'Espagne, 30 m pour l'estimation. La résolution des fichiers de l'Arcep n'est documentée dans aucun texte lu.
- **PNG plutôt que WebP sans perte.** Le cahier des charges prévoit le WebP sans perte (un autre format d'image) s'il est plus léger. Il l'est, pour des pixels identiques : sur 800 tuiles tirées au hasard, 9,02 Mo en WebP sans perte contre 12,77 Mo en PNG. C'est environ 29 % de moins (mesure de l'audit). Les tuiles restent pourtant en PNG : le décodeur de secours en JavaScript ne lit que le PNG. Or c'est lui qui garantit des pixels exacts sur tous les navigateurs.
- **Hors ligne : les fonds.** Le fond OpenTopoMap n'est jamais préchargé. Son fournisseur ne garantit pas la disponibilité de son serveur (« keinerlei Ausfallsicherheit ») et demande d'éviter les téléchargements en masse. Or c'est le fond du mode Automatique en Italie, en Andorre et à Monaco. Pour un tracé dans ces pays, le panneau dit que ces pays n'ont pas de fond enregistré. Il faut alors choisir soi-même un autre fond avant de préparer le tracé ; qu'il montre bien ces pays n'est pas vérifié. Les autres fonds sont plafonnés (900 ou 600 tuiles) et perdent leurs zooms les plus fins sur un long tracé. Le préchargement réel de swisstopo et d'IGN España n'a pas été essayé avec leurs vrais serveurs ; celui du Plan IGN l'a été, sur le site en ligne.
- **Hors ligne : le reste.** Les tuiles de fond enregistrées ne sont jamais renouvelées : une mise à jour de l'enregistrement garde celles qui sont déjà là. Or la documentation de swisstopo demande de vider un cache local quand sa couche change. Pour les rafraîchir, supprimer les données hors ligne puis préparer de nouveau le tracé. La recherche de lieux ne marche pas sans réseau, et un seul tracé est gardé. Le navigateur peut effacer ces données s'il manque de place ; le site lui demande de les garder. Détail du mode hors ligne : [docs/architecture.md](docs/architecture.md#mode-hors-ligne).
- **Service Worker en JavaScript.** `public/sw.js` est écrit en JavaScript, pas en TypeScript : le compilateur ne le vérifie pas. Il recopie à la main deux constantes du code TypeScript (nom du cache hors ligne, adresse du manifest), et la valeur par défaut du délai réseau, qui lui est sinon transmis dans son adresse.
- **Fonds de carte.** OpenTopoMap ne garantit pas la disponibilité de son serveur. Le Plan IGN a un style vectoriel : la description qui permet au navigateur de dessiner la carte. Si ce style ne se charge pas, le site affiche le Plan IGN en images.
- **Mentions sur téléphone.** Le pied de carte est visible au chargement, puis se replie au premier geste sur la carte. Or IGN España demande une mention visible au pied de la carte, OpenTopoMap une mention bien visible (« deutlich sichtbar »), et OpenCellID un crédit à côté de la carte. Les règles d'OpenStreetMap demandent une mention qui ne demande aucune action pour être vue. Ce repli est donc un compromis, à valider.
- **Recherche.** Seuls les types d'adresse, « commune » et « département » sont traduits : les autres catégories de lieux de l'IGN (refuge, par exemple) restent en français dans toutes les langues.
- **Mises à jour à la main.** Les nouveaux millésimes des contours ne sont pas détectés. Une nouvelle édition de la carte espagnole demande une modification à la main. Pour la carte italienne, la prochaine adresse n'est pas vérifiée. Une nouvelle extraction d'OpenCellID ne déclenche pas de reconstruction (choix assumé). Voir [Mettre à jour les données](#mettre-à-jour-les-données).
- **Nom des releases.** Le cahier des charges demande `data-AAAA-MM-JJ`. Quand il y a déjà une release ce jour-là, le workflow ajoute `-2`, `-3`, etc., toujours après le plus grand numéro déjà pris. La release en ligne s'appelle pourtant `data-2026-11-14`, sans numéro : publiée après `data-2026-11-14-4`, elle a repris un nom libéré par la suppression des anciennes releases, avant que cette règle existe. Le nom ne dit donc pas toujours quelle release est la plus récente ; le déploiement, lui, prend la plus récente par date de publication.
- **Lectures faites pendant l'enquête sur les sources.** Une dizaine de tuiles d'image du ministère espagnol ont été lues sur un hôte qui interdit les robots. C'est son fichier robots.txt, les consignes du site aux robots, qui le dit. Le pipeline ne les lit pas, et rien de publié n'en dépend. Quand maps.agcom.it et www.mimit.gov.it ne répondaient pas, des sondes ont lu des copies chez Internet Archive. Rien de publié n'en dépend, et ces points restent non vérifiés à la source. Les conditions d'utilisation d'ArcGIS Online (Esri), la plateforme qui sert la couche espagnole, n'ont pas été lues.

## Décisions laissées au propriétaire

- **Licence de la couche espagnole.** Aucune licence n'est attachée à la couche `InfoCob4G_2024`. Elle n'est pas dans le portail de données ouvertes du ministère (https://datos-conectemos.hub.arcgis.com, où la couverture n'est publiée qu'en agrégats par région et par province), et une demande d'ouverture de 2021 sur datos.gob.es est à l'état « No viable ». Vont dans le sens de la réutilisation : les conditions générales de réutilisation du site du ministère (citer la source et la date), la Ley 11/2022 (article 48.1) et le Real Decreto 1495/2011 (article 8.1). Les mentions légales de Conectemos vont dans le même sens : « Se prohíbe la reproducción total o parcial de los contenidos del Portal sin citar su origen o solicitar autorización. » Appelle la prudence : la loi 37/2007 exclut les documents sur lesquels des tiers ont des droits de propriété intellectuelle, et les données viennent des opérateurs ; rien de lu ne dit si c'est le cas. Les hôtes des images tuilées du ministère interdisent les robots (robots.txt « Disallow: / ») : le pipeline ne les lit pas, il ne lit que la couche d'entités. La copie de travail `cache-es_mtd.tif`, publiée avec chaque release, est une image de cette couche. Trois choix : garder la source officielle, écrire au ministère (S.G. de Operadores de Telecomunicaciones e Infraestructuras Digitales) pour demander si la couche relève des conditions générales, ou passer l'Espagne en « estimée ». Détail : [docs/sources.md](docs/sources.md#espagne).
- **Lecture du service italien.** Le pipeline lit le service REST public (un service web) de la carte de l'AGCOM (geo3.agcom.it) : 19 requêtes par édition, sans jeton (clé d'accès), dans la limite que le service annonce. Ce n'est pas la voie de téléchargement que désigne le portail, une demande par courriel. La licence CC BY 4.0 (une licence libre qui demande de citer la source) couvre les données. À trancher : garder cette lecture, passer par la demande officielle, ou informer l'AGCOM.
- **Estimation de l'Andorre.** Trois choix : la garder telle quelle, masquer l'Andorre, ou enrichir l'estimation avec les cellules 2G et 3G du même fichier (non essayé). L'audit suggère aussi un contrôle de vraisemblance (densité de sites, part de « pas de couverture »), qui publierait alors « limitée » au lieu de « pas de couverture », ou signalerait une estimation insuffisante.
- **Licence du code.** `package.json` ne déclare pas de licence, et le dépôt n'a pas de fichier LICENSE. Les deux GPX de test, eux, sont sous ODbL 1.0 (une licence libre pour les bases de données) quoi qu'il en soit (voir [Licences et crédits](#licences-et-crédits)).
- **Forme de la mention IGN España.** « CC BY 4.0 ign.es » est la valeur exacte du champ AccessConstraints du service et la formule demandée par le propriétaire. La licence de l'IGN préfère, quand des données couplées existent, leurs propres formules (par exemple « CC-BY 4.0 ign.es 2025 »). La mention affichée n'a pas changé. Autre point : la mention du contour espagnol (« Obra derivada de BDLJE CC-BY 4.0 ign.es ») n'est que dans le panneau « Sources », alors que la licence la demande au pied de la carte, sauf impossibilité justifiée.
- **Navigation hors ligne.** La page vient de la coque enregistrée (la copie des fichiers du site) dès qu'elle est complète. Il n'y a jamais de mélange de versions, et le site s'ouvre sans attendre un réseau faible. En échange, une nouvelle version ne sert qu'une fois fermés tous les onglets ouverts sur l'ancienne : un simple rechargement de la page ne suffit pas. L'autre choix, « réseau d'abord, 3 secondes », montre plus vite une nouvelle version. Mais il risque une page blanche par réseau faible juste après une mise en ligne. Le préchargement des tuiles est fait par la page, pas par le Service Worker comme le décrit le cahier des charges : il s'arrête si l'onglet est fermé, et se reprend. Le déplacer dans le Service Worker, ou utiliser Background Fetch (un téléchargement en arrière-plan confié au navigateur, Chrome seulement), reste à décider. Détail : [docs/architecture.md](docs/architecture.md#mode-hors-ligne).
- **Autres choix à confirmer.**
  - Monaco : ne lire que les cellules du code 212, ou ajouter celles des réseaux français captés à Monaco.
  - Contours sous ODbL (France, Andorre, Monaco) : le code pays des tuiles en dérive. La question du partage à l'identique (lecture « Produced Work » de l'ODbL) n'est pas tranchée. Pour la France, une piste serait de prendre ADMIN EXPRESS de l'IGN directement (licence non vérifiée).
  - Partie française du Léman hors zone, PNG ou WebP, nom des releases, Service Worker en JavaScript, mentions repliées sur téléphone : voir [Limites](#limites).
  - Points aberrants : deux points aberrants consécutifs loin du tracé restent comme un petit segment, et un aller-retour dessiné en 3 points avec des étapes de plus de 10 km perd son point le plus éloigné. Une règle tenant compte de la densité des points reste à choisir.
  - Le pipeline se présente aux serveurs des sources sous un nom générique (`pipeline-couverture-mobile/1.0 (Python urllib)`). Pour être identifiable par un fournisseur, mettre un nom et une adresse de contact dans `USER_AGENT` de `pipeline/czb/net.py`.
  - Les seuils de l'analyse, les délais et quelques choix faits dans le code (mentions, liens) sont réunis dans [Réglages que le propriétaire peut revoir](docs/architecture.md#réglages-que-le-propriétaire-peut-revoir).

## Vie privée

- Aucun cookie, aucun outil de mesure d'audience, aucun compte. Le site n'a ni formulaire, ni balise de suivi, et ne fait aucune requête d'envoi de données. Il lit des fichiers et interroge les services ci-dessous. L'audit du 14 novembre 2026 l'a vérifié, dans le code et dans le site construit.
- Le GPX est lu et analysé dans le navigateur. Il n'est envoyé nulle part, et le GPX enrichi est fabriqué dans le navigateur.
- Services contactés, et ce qu'ils reçoivent :

| Service | Adresse | Quand | Ce qu'il reçoit |
|---|---|---|---|
| le site lui-même (GitHub Pages) | nathancouturier.github.io | toujours | demandes de la page, des scripts, du manifest et des morceaux d'archives de couverture : ceux de la zone affichée, ceux que lit l'analyse d'un tracé importé, et ceux du couloir du tracé quand on prépare le hors ligne |
| IGN (Géoplateforme) | data.geopf.fr | fond Plan IGN (style, tuiles, icônes, polices), Plan IGN en images, photos aériennes, estompage | demandes de tuiles de la zone affichée |
| swisstopo | wmts.geo.admin.ch | fond swisstopo | demandes de tuiles de la zone affichée |
| IGN España | www.ign.es | fond IGN España | demandes de tuiles de la zone affichée |
| OpenTopoMap | a.tile.opentopomap.org, b.tile.opentopomap.org, c.tile.opentopomap.org | fond OpenTopoMap | demandes de tuiles de la zone affichée |
| géocodage de l'IGN | data.geopf.fr/geocodage/completion | quand on tape au moins 3 caractères dans la recherche | le texte tapé, le centre de la carte arrondi, les types de lieux cherchés, la zone (`METROPOLE`) et le nombre de réponses voulu |
| Photon (komoot) | photon.komoot.io | quand on tape au moins 3 caractères dans la recherche | le texte tapé, la langue, le centre de la carte arrondi, l'emprise fixe de la carte (`MAX_BOUNDS`) et le nombre de réponses voulu |

- Le centre de la carte envoyé aux deux services de recherche est arrondi au dixième de degré, soit environ 10 km : après « Ma position », la carte est centrée près de vous, et rien de plus précis ne part.
- Les serveurs des fonds voient la zone regardée, comme pour toute carte en ligne. Quand on prépare un tracé pour le hors ligne, ils reçoivent en plus les demandes de tuiles du couloir du tracé (sauf OpenTopoMap, jamais préchargé). GitHub Pages, lui, reçoit les demandes des tuiles de couverture que l'analyse lit le long du tracé (des carrés d'environ 7 km de côté). Ils peuvent donc deviner le parcours, mais aucun ne reçoit jamais le fichier GPX.
- Les autres sites ne reçoivent que l'origine du site (https://nathancouturier.github.io), jamais l'adresse complète de la page (réglage `strict-origin-when-cross-origin` d'`index.html`). La position de la carte, après le `#` de l'adresse, n'est jamais envoyée.
- La position donnée par « Ma position » vient du navigateur et reste dans le navigateur : elle sert seulement à placer le point et la carte.
- Les liens (GitHub, licences, sources) ne sont suivis que si on clique dessus.
- Ce qui est rangé dans le navigateur. Dans `localStorage` (un petit espace de stockage du navigateur, propre au site) : la langue, les réglages et l'état du tracé préparé, sous les clés `czb.lang`, `czb.reseau`, `czb.fond` et `czb.horsLigne`. Dans le cache du navigateur : la coque du site (cache `czb-coque-` suivi de sa version) et le tracé préparé pour le hors ligne (cache `czb-hors-ligne-v1`). « Supprimer les données hors ligne » efface le second cache et l'information sur l'enregistrement ; la coque reste, c'est le site lui-même.
- Le pipeline, dans GitHub Actions, se présente aux serveurs des sources sous un nom générique, sans le nom du dépôt ni de son propriétaire. La clé d'OpenCellID est un secret, jamais écrit dans les journaux.

Voir aussi la section [Vie privée et bonnes pratiques](docs/sources.md#vie-privée-et-bonnes-pratiques) de docs/sources.md, et le détail de la [recherche de lieux](docs/architecture.md#recherche-de-lieux).

## Licences et crédits

Chaque source a sa licence et ses mentions obligatoires. Le site affiche celles des fonds et des données de couverture en pied de carte et dans le panneau « Sources ». Le détail (texte exact des mentions, adresses, dates de lecture des conditions) est dans [docs/sources.md](docs/sources.md). En résumé :

- couverture :
  - Arcep : « Licence Ouverte / Open Licence » (identifiant `fr-lo` sur data.gouv.fr). L'adresse officielle de cette licence renvoie aujourd'hui au texte de la version 2.0, et le site lie la page de cette version (https://www.data.gouv.fr/pages/legal/licences/etalab-2-0) ;
  - OFCOM : géodonnées de la Confédération, utilisation libre, source à citer ;
  - AGCOM : CC BY 4.0. Les conditions demandent de reproduire un logo dans toute œuvre dérivée de ces données. Le site affiche aussi la phrase placée sous ce logo : « BroadbandMap di Agcom - Autorità per le garanzie nelle comunicazioni è distribuito con Licenza Creative Commons Attribuzione 4.0 Internazionale. » Le logo est dans `public/licences/agcom-bbmap.jpg` ; le panneau Sources l'affiche, en lien vers https://maps.agcom.it/. Il est aussi joint à la release de données et cité dans `SOURCES.md` ;
  - ministère espagnol : aucune licence n'est attachée à la carte. Mention affichée : « Origen de los datos: Ministerio para la Transformación Digital y de la Función Pública ». La réutilisation s'appuie sur les conditions générales de réutilisation du site du ministère (citer la source et la date) : lecture raisonnable, pas une autorisation écrite (voir [Décisions laissées au propriétaire](#décisions-laissées-au-propriétaire)) ;
- zones estimées : OpenCellID, CC BY-SA 4.0 (« Cell tower data from OpenCellID, licensed under CC BY-SA 4.0 ») : les zones estimées en dérivent et suivent cette licence. Copernicus DEM GLO-30 : la licence demande que les mentions de ses articles 6 (b) et 6 (c) suivent les données redistribuées ; la mention 6 (b) reste en anglais, mot pour mot, seule la phrase 6 (c) peut être traduite. Son article 6 (e) impose de lier les utilisateurs suivants aux mêmes obligations. Le manifest et `SOURCES.md` portent ces phrases ;
- fonds de carte : « © IGN » (Géoplateforme, en lien vers ses conditions générales d'utilisation) ; « ©swisstopo », sans espace, forme courte admise par les conditions de swisstopo ; « CC BY 4.0 ign.es » pour IGN España ; pour OpenTopoMap, « Kartendaten: © OpenStreetMap-Mitwirkende, SRTM | Kartendarstellung: © OpenTopoMap (CC-BY-SA) », et sur téléphone sa forme courte « © OpenStreetMap, SRTM | © OpenTopoMap (CC-BY-SA) », avec leurs liens ;
- recherche de lieux : géocodage de la Géoplateforme (IGN) ; Photon (komoot), données © les contributeurs d'OpenStreetMap, avec un lien vers https://www.openstreetmap.org/copyright. Ce crédit vient des règles d'attribution d'OpenStreetMap, pas des conditions de Photon ;
- contours des pays (mentions du manifest, affichées dans le panneau Sources) : « Contours administratifs, data.gouv.fr (licence ODbL), d'après ADMIN EXPRESS de l'IGN » ; « ©swisstopo, swissBOUNDARIES3D » ; « Istat, Confini delle unità amministrative a fini statistici al 1° gennaio 2026, CC BY 4.0, données modifiées » ; « Obra derivada de BDLJE CC-BY 4.0 ign.es » ; « © OpenStreetMap contributors (ODbL 1.0) » pour l'Andorre et Monaco ;
- GPX de test de `samples/` : chemins © les contributeurs d'OpenStreetMap, lus par l'API Overpass (le service de requêtes d'OpenStreetMap) ; ces deux fichiers sont mis à disposition sous ODbL 1.0. Altitudes : Copernicus DEM GLO-30.

Le site s'appuie sur MapLibre GL JS, pmtiles, @tmcw/togeojson, fast-png et Vite ; le pipeline sur GDAL, NumPy, Pillow, PyYAML et la bibliothèque Python pmtiles.

Licence du code : `package.json` ne déclare pas de licence, et le dépôt n'a pas de fichier de licence. Le choix revient au propriétaire.
