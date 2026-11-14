# Architecture du site

Ce document décrit le site en détail. Il dit comment les données de couverture sont rangées dans les tuiles (les carrés d'image qui composent la carte), et ce que dit le manifest (le fichier qui décrit ces données). Il dit ensuite comment la carte lit et affiche les tuiles, comment un GPX (le fichier d'un parcours) est analysé et comment marche le mode hors ligne. Il finit par les tests et par les réglages que le propriétaire peut revoir. La vue d'ensemble est dans le [README](../README.md#architecture). Le pipeline qui fabrique les données et les workflows GitHub (les tâches automatiques du dépôt) sont décrits dans [pipeline.md](pipeline.md), les sources dans [sources.md](sources.md).

Le site est une seule page, sans serveur d'application. Il est écrit en TypeScript (du JavaScript dont les types sont vérifiés) et assemblé par Vite (l'outil qui assemble les fichiers du site). La carte est dessinée par MapLibre GL JS, une bibliothèque de cartes pour le navigateur. Le code est dans `src/` (voir l'[arborescence du dépôt](../README.md#arborescence-du-dépôt)).

## Sommaire

- [Encodage des tuiles](#encodage-des-tuiles)
- [Le manifest](#le-manifest)
- [Protocole, archives et cache](#protocole-archives-et-cache)
- [Affichage de la couche réseau](#affichage-de-la-couche-réseau)
- [Fonds de carte](#fonds-de-carte)
- [Recherche de lieux](#recherche-de-lieux)
- [Ma position](#ma-position)
- [Analyse d'un GPX](#analyse-dun-gpx)
- [Rapport, profil et export](#rapport-profil-et-export)
- [Pied de carte et panneau Sources](#pied-de-carte-et-panneau-sources)
- [Mode hors ligne](#mode-hors-ligne)
- [Tests](#tests)
- [Réglages que le propriétaire peut revoir](#réglages-que-le-propriétaire-peut-revoir)

## Encodage des tuiles

Une tuile est un carré de carte de 256 pixels de côté. À chaque niveau de zoom, la carte est découpée en tuiles plus nombreuses et plus détaillées. Une archive PMTiles est un seul fichier qui contient toutes les tuiles ; le navigateur n'en lit que les morceaux utiles.

Ici, les tuiles sont des PNG (un format d'image sans perte) de 256 px, des zooms 0 à 12, et chaque pixel porte des données, pas une couleur. Un pixel a quatre canaux, d'habitude le rouge (R), le vert (G), le bleu (B) et l'opacité (A). Chaque canal est un octet : un nombre de 0 à 255, écrit sur 8 bits. L'encodage est le même dans `pipeline/czb/encoding.py`, qui écrit les tuiles, et dans `src/coverage/codec.ts`, qui les lit :

| Canal | Contenu |
|---|---|
| R | internet mobile : 4 emplacements d'opérateur de 2 bits chacun. L'emplacement i occupe les bits 2i et 2i+1. Valeur : 0 pas de couverture, 1 limitée, 2 bonne, 3 très bonne |
| G | appels et SMS : même encodage (0 là où le service n'est pas construit) |
| B | bits 0 à 3 : code du pays (1 France, 2 Suisse, 3 Italie, 4 Espagne, 5 Andorre, 6 Monaco). Bits 4 et 5 : type de source (0 officielle par opérateur, 1 officielle agrégée, 2 estimée) |
| A | 255 dans la zone couverte par les données, 0 ailleurs |

Un emplacement contient un opérateur nommé, ou un seuil « au moins N réseaux » : le manifest dit lequel, pays par pays (voir [Le manifest](#le-manifest)). Un emplacement qu'un pays ne déclare pas vaut toujours 0. Une source qui dit seulement « couvert » écrit le niveau 2. L'estimation n'écrit que 0, 1 ou 2.

Le zoom 12 est la résolution de travail. Un pixel y fait 38,2 m en projection Mercator (la projection des cartes en ligne), soit 26 à 28 m au sol dans les Alpes et les Pyrénées : la taille au sol varie avec la latitude. Les zooms inférieurs recopient le pixel central du carré qu'ils représentent (plus proche voisin). Il n'y a jamais de moyenne : elle mélangerait les bits et fausserait les données. Une tuile qui a au plus 256 valeurs différentes est enregistrée en PNG à palette (ses valeurs sont numérotées dans une petite table), plus léger.

Pour l'affichage, du zoom 13 au zoom 16, le site fabrique lui-même les tuiles à partir de celle du zoom 12, en plus proche voisin : les hachures des zones estimées restent fines à l'écran. L'analyse des GPX lit toujours le zoom 12.

Ce choix donne peu de fichiers, un changement d'opérateur instantané, et les mêmes tuiles servent à l'affichage et à l'analyse des GPX. Les tuiles restent en PNG, bien que le WebP sans perte (un autre format d'image) soit plus léger : la raison et la mesure sont dans [Limites](../README.md#limites).

## Le manifest

Le fichier `manifest.json`, publié avec les tuiles, dit au site tout ce qu'il doit savoir. C'est un fichier JSON (un format de texte pour les données). Il est écrit par `pipeline/czb/manifest.py` et lu par `src/coverage/manifest.ts`. Il donne :

- la version du format (`version`), la date de génération des tuiles (`generated`) et le nom du périmètre construit (`scope`, les pays et régions de la construction) ;
- les tuiles (`tiles`) : taille, zooms, format, zoom des blocs. Le format est toujours le PNG : le site refuse un manifest qui annonce du WebP ;
- l'emprise des données (`bounds`, la zone qu'elles couvrent) et une description de l'encodage en clair (`encoding`). Cette description dit aussi ce que valent les emplacements qu'un pays ne déclare pas : l'emplacement i est le i-ème élément de la liste `slots` du pays ; au-delà, il est inutilisé et vaut toujours 0. Ni le site ni le pipeline ne lisent `encoding` : il est écrit pour qui ouvre le fichier ;
- les archives (`archives`) : nom, zooms, taille et, pour une archive découpée, la liste de ses blocs ;
- pour chaque pays (`countries`) : son code (canal B) et son code ISO (le code international du pays). Puis l'itinérance de l'Union européenne, oui ou non (`euRoaming` ; elle permet d'utiliser son forfait dans les autres pays de l'Union), et la mention de son contour (`boundary`). Enfin, les noms de ses opérateurs quand la source ne les distingue pas (`operators`), et le contenu de chaque emplacement (`slots`) : un opérateur nommé, ou un seuil « au moins N réseaux » ;
- pour chaque source : identifiant, type, nom, adresse, date des données (`date`, et `dataDate` quand le jour est connu), licence et son adresse, mention à afficher (`attribution`), phrase ou logo que la licence impose (`licenceNotice`, `licenceLogo`, `licenceLogoUrl`), services fournis, façon de lire les niveaux (`four`, `three` ou `binary`), correspondance des valeurs (`levelMap`), lecture emplacement par emplacement ou non (`perOperator`), technologie et résolution (`resolutionM`). La résolution de l'Arcep n'est pas donnée : aucun texte lu ne la documente ;
- les pays prévus mais absents des données (`missing`), par exemple faute de clé d'accès. Ce champ n'existe que s'il manque un pays.

Champs facultatifs, que le site lit quand ils existent :

- par source, `nameI18n` et `licenceI18n`, et par pays, `boundary.textI18n` : les traductions du nom, de la licence et de la mention du contour, en dictionnaires par langue (es, ca, it, de). Le français reste dans `name`, `licence` et `boundary.text`. Les noms propres et les formules imposées ne sont pas traduits : le nom de la carte espagnole, les licences de l'Arcep et de l'AGCOM, et les mentions des contours suisse, espagnol, andorran et monégasque n'ont donc pas de traduction. Dans le nom de la source suisse, le sigle de l'office suit la langue : OFCOM en français, en espagnol et en catalan, UFCOM en italien, BAKOM en allemand ; sa mention reste « OFCOM » ;
- par source, `mentionLang`, et par pays, `boundary.lang` : la langue des mentions écrites telles quelles. Ce sera it pour l'AGCOM, es pour le ministère espagnol et en pour l'estimation ; es pour le contour espagnol, en pour ceux de l'Andorre et de Monaco. Le site en fait l'attribut `lang` de ces mentions (voir [Pied de carte et panneau Sources](#pied-de-carte-et-panneau-sources)) ;
- pour une source estimée, `estimation` : le nombre de sites et de cellules utilisés, par exemple `{"sites": 12, "cells": 41}` pour l'Andorre.

La mention d'une source estimée (`attribution`) ne dit pas elle-même « estimation » : c'est le site qui l'ajoute, dans sa langue. Des manifests plus anciens l'écrivaient (« Estimation : ») : le site retire ce préfixe à la lecture. La technologie de l'estimation s'écrit « 4G, 5G ».

Le manifest en ligne, celui de la release `data-2026-11-14` (voir [pipeline.md](pipeline.md#chiffres-de-la-construction-de-production)), a les traductions et la phrase sur les emplacements. Il n'a pas encore `mentionLang`, `boundary.lang` ni `estimation`. Le pipeline écrit les deux premiers depuis le commit `dfc96f0`, postérieur à cette construction : ils arriveront avec la prochaine. Le troisième arrivera au prochain recalcul de l'estimation, car les copies de travail reprises par cette construction datent d'avant ce champ (voir [Copies de travail](pipeline.md#copies-de-travail)).

Le décodeur du site est piloté par ce fichier. Pour chaque pays et chaque source, il fabrique une table de 256 cases qui donne, pour un octet R ou G, le niveau de l'opérateur choisi. Rien n'est codé en dur par pays : un pays ajouté dans le pipeline apparaît sur la carte sans toucher au code de la couche réseau. Un service absent d'une source (les appels et SMS hors de France) est lu « pas de donnée », jamais « pas de couverture ». Une adresse du manifest ne devient un lien que si elle commence par `https:`, et un logo de licence doit être un fichier du site.

## Protocole, archives et cache

- Un protocole MapLibre personnalisé, `couverture://` (fonction `addProtocol`, fichier `src/coverage/protocol.ts`), répond aux demandes de tuiles de la carte : au lieu de télécharger des images toutes faites, MapLibre demande chaque tuile à ce code. Il trouve l'archive qui contient la tuile, la lit, la décode, la recolore selon les réglages et la rend à MapLibre. Le décodage passe par `createImageBitmap` avec `premultiplyAlpha` et `colorSpaceConversion` à `none`, puis par `getImageData` : ces fonctions du navigateur lisent les valeurs des pixels, et les deux réglages à `none` lui demandent de ne pas les modifier.
- Un cache LRU garde les 160 dernières tuiles décodées (`src/coverage/store.ts`). Un cache est une réserve en mémoire ; celui-ci est « LRU » : quand il est plein, il oublie la tuile servie le moins récemment. Quand un réglage change (opérateur, service, affichage), la couche est redessinée à partir du cache, sans rien retélécharger.
- L'analyse d'un GPX range les tuiles qu'elle lit dans un petit cache à part, de 32 tuiles (un cinquième du premier). Même un très long tracé n'évince donc pas les tuiles affichées, et un changement de réglage ne relit rien dans les archives. Quand la carte se cadre ensuite sur un tracé court, elle trouve ses tuiles dans ce petit cache, sans les relire. Une tuile demandée à la fois par la carte et par l'analyse n'est lue qu'une fois.
- Décodeur de secours : certains navigateurs ajoutent exprès un léger bruit aux pixels relus d'un canvas (la surface de dessin de la page), pour gêner le pistage. Les 3 premières tuiles sont donc décodées une seconde fois en JavaScript pur, par fast-png (un décodeur PNG écrit en JavaScript). Au moindre écart, le site passe pour de bon sur ce décodeur, qui donne des pixels exacts.
- Chaque lecture de tuile a un délai maximal de 20 secondes (`TILE_READ_TIMEOUT_MS`). Une tuile qui n'a pas pu être lue est dessinée en gris rayé (« données indisponibles »), pour ne pas passer pour une zone couverte, et un bandeau propose « Réessayer ». Quand le réseau revient, ces tuiles sont relues toutes seules.
- Nouvelle publication pendant qu'un onglet est ouvert : les anciennes archives disparaissent du serveur. Sur une erreur de lecture, le site relit `manifest.json` (au plus une fois par minute tant que rien ne change, `MANIFEST_RECHECK_MS`). Si les données ont changé, il repart sur les nouvelles, redessine la couche, le dit, et refait l'analyse du tracé chargé sans rouvrir le rapport ni déplacer la carte.
- Plusieurs archives : si les tuiles dépassent 70 Mo au total, le pipeline écrit une archive d'aperçu (zooms 0 à 7) et des archives par blocs. Un bloc est une tuile du zoom 8 avec tout ce qu'elle contient aux zooms 8 à 12. Le manifest donne les blocs de chaque archive, et le site choisit la bonne archive selon x et y (la colonne et la ligne de la tuile).
- Les noms des archives contiennent la date et l'heure de la construction (`couverture-AAAAMMJJ-HHMM-NN.pmtiles`). Un navigateur ne peut donc pas mélanger d'anciennes tuiles gardées en cache avec un nouveau manifest.

## Affichage de la couche réseau

- Les couleurs suivent les réglages du panneau « Réseau », décrits dans le [mode d'emploi](../README.md#mode-demploi).
- « Tous opérateurs » est le maximum des emplacements du pays, calculé dans le navigateur.
- Les zones estimées sont hachurées. Là où leur niveau n'est pas dessiné (la bonne couverture, dans l'affichage par défaut), de fins traits gris peu opaques disent quand même qu'elles sont estimées, et la légende le dit. Ils ne ressemblent pas aux tuiles illisibles, voilées de gris et rayées dans l'autre sens. Rien n'est marqué « estimé » pour un service que l'estimation ne fournit pas (les appels et SMS).
- La couche est dessinée en plus proche voisin (`raster-resampling: nearest` : chaque pixel garde sa valeur, sans lissage). Elle passe sous les libellés du fond : juste avant la première couche `symbol` du style (la description des couches de la carte), celle des textes et des icônes. Sur les fonds en images, les noms font partie de l'image et passent donc sous la couche.

## Fonds de carte

- Le mode « Automatique » (le choix par défaut) prend le fond national du pays au centre de la carte. C'est le Plan IGN classique en France, swisstopo en Suisse, IGN España en Espagne, et OpenTopoMap (données OpenStreetMap, la carte libre et collaborative) ailleurs, y compris hors de la zone couverte par les données.
- Le pays est lu dans les données de couverture. Si le centre tombe hors des données (en mer près d'une côte, par exemple), c'est le pays le plus présent dans le reste de la vue qui décide.
- Sans réseau, le mode Automatique ne passe qu'à un fond enregistré pour le hors ligne (voir [Mode hors ligne](#mode-hors-ligne)).
- Le Plan IGN s'affiche d'abord en images, le temps que son style vectoriel arrive (8 secondes au plus, `VECTOR_STYLE_TIMEOUT_MS`). Un style vectoriel est la recette qui permet au navigateur de dessiner lui-même la carte. Si ce style ne vient pas ou ne peut pas être lu, la version en images reste, et un message le dit.
- Les fonds sont déclarés dans `src/map/basemaps.ts` : `NATIONAL_BASEMAP` pour le mode Automatique, `BASEMAPS` et `BASEMAP_ORDER` pour la liste, avec la mention de chaque fond et sa règle de préchargement hors ligne (voir [Ajouter ou changer une source](../README.md#ajouter-ou-changer-une-source)).

## Recherche de lieux

- La loupe propose des lieux avec suggestions, dès 3 caractères : en France par le géocodage de l'IGN (le service qui trouve un lieu à partir de son nom), Corse comprise ; à l'étranger par Photon (données OpenStreetMap).
- Les lieux du premier service qui répond s'affichent tout de suite. Un service qui ne répond pas en 5 secondes est signalé sous la liste, et les lieux de l'autre restent.
- Quand le centre de la carte est hors de France, les lieux étrangers passent en premier.
- Les deux services reçoivent le texte tapé et le centre de la carte, arrondi au dixième de degré (environ 10 km), pour classer les lieux proches. Après « Ma position », la carte est centrée près de vous : l'arrondi évite d'envoyer votre position.
- Chaque lieu porte son origine (IGN ou OSM, pour OpenStreetMap). Pour l'IGN, le type d'adresse, la commune et le département sont traduits ; les autres catégories restent en français (voir [Limites](../README.md#limites)).
- Entrée choisit le premier lieu trouvé pour la saisie en cours, jamais celui d'une saisie précédente.
- Les réglages (`SEARCH_MIN_CHARS`, `SEARCH_DEBOUNCE_MS`, `SEARCH_MAX_RESULTS`, `SEARCH_TIMEOUT_MS`, `PHOTON_LANGS`, `MAX_BOUNDS`) sont dans le [tableau des réglages](#réglages-que-le-propriétaire-peut-revoir). Tout ce que reçoivent les deux services est dans [Vie privée](../README.md#vie-privée).

## Ma position

- Le bouton en haut à droite, à côté de la roue dentée, affiche votre position et centre la carte dessus. Le point suit ensuite la marche tant que la page est visible, sans déplacer la carte : un nouvel appui recentre.
- Si la carte bouge entre l'appui et l'arrivée de la position (geste, import d'un GPX, recherche), elle n'est pas recentrée.
- Le suivi s'arrête quand la page est cachée (pour la batterie) et reprend à son retour ; le point devient gris tant que la position n'est plus à jour.
- Un message dit pourquoi la position manque : autorisation refusée, position indisponible, ou GPS qui cherche encore au bout de 15 secondes (`LOCATE_SLOW_MS`). Le zoom du recentrage est plafonné par `LOCATE_MAX_ZOOM`.
- La position vient du navigateur et reste dans le navigateur (voir [Vie privée](../README.md#vie-privée)).

## Analyse d'un GPX

Un GPX est un fichier texte qui décrit un parcours : des traces (suites de points, souvent enregistrées pendant la marche, parfois en plusieurs segments) ou des routes (des points de passage, souvent très espacés).

### Import

- Par le bouton « Importer un GPX », ou en glissant le fichier sur la carte (ordinateur).
- Le site lit les traces, sinon les routes. Plusieurs traces ou segments forment un seul parcours, dans l'ordre du fichier.
- Il respecte l'encodage du fichier (la façon dont les lettres y sont écrites) : UTF-8 par défaut, UTF-16, ou celui que déclare son en-tête (ISO-8859-1, par exemple). Il accepte aussi les éléments préfixés, c'est-à-dire les balises écrites avec un préfixe (`gpx:trk`).
- Les points aberrants sont écartés : position (0, 0), ou point isolé à plus de 10 km de ses deux voisins. Une trace est coupée là où elle saute de plus de 10 km d'un point au suivant, et ce saut ne compte ni dans la distance ni dans l'analyse. Le panneau signale ces corrections.
- Un fichier de plus de 41,9 millions d'octets est refusé.
- Le tracé s'affiche avec un liseré blanc, des repères de départ et d'arrivée, et la carte zoome dessus. Une fois l'analyse faite, il prend les couleurs de la couverture : rouge, orange, vert, et gris là où il n'y a pas de données. Les portions dont la couverture est estimée sont en pointillé.

### Étapes de l'analyse

1. Le GPX est lu avec @tmcw/togeojson, une bibliothèque qui lit le GPX : les traces, ou à défaut les routes. L'encodage vient de la marque d'ordre des octets s'il y en a une (quelques octets en tête du fichier qui annoncent l'encodage), sinon de la déclaration en tête du fichier, sinon c'est l'UTF-8. Les points aberrants sont écartés et une trace est coupée à ses sauts de plus de 10 km (voir [Import](#import)). Les routes, aux points souvent très espacés, ne sont pas coupées. S'il ne reste rien d'utilisable après les coupures, c'est une trace dessinée à la main avec des points très espacés : elle est gardée telle quelle.
2. Le parcours est rééchantillonné tous les 20 m : des points sont recalculés à intervalles réguliers. La distance est géodésique : mesurée sur une sphère du rayon moyen de la Terre. Les sauts entre deux segments ne comptent pas dans la distance.
3. Les altitudes manquantes sont interpolées, c'est-à-dire estimées entre les deux points connus les plus proches d'un même segment. Avant le premier et après le dernier point connu, l'altitude reste inconnue. Le dénivelé, les altitudes extrêmes et le profil ne sont annoncés que si plus de la moitié des points ont une altitude ; l'altitude d'une zone blanche, que si plus de la moitié de ses points en ont une. Le dénivelé ignore les variations de moins de 5 m, dues au bruit du GPS.
4. Pour chaque point, le site lit au pixel près les tuiles du zoom 12 : niveau pour l'opérateur choisi et pour tous opérateurs, pays, type de source. Chaque tuile n'est lue qu'une fois, 6 à la fois.
5. Chaque point représente le parcours jusqu'à mi-chemin de ses voisins. Les points sans couverture qui se suivent forment des tronçons. Deux tronçons séparés par moins de 50 m sont fusionnés. Une zone blanche fait au moins 100 m. Une zone ne franchit jamais une interruption du parcours : deux segments éloignés de plus de 50 m. Deux segments plus proches (pause du GPS, trace coupée en deux) forment un parcours continu.
6. La longueur affichée d'une zone est tirée de ses bornes arrondies à 100 m : la soustraction que fait le lecteur tombe juste.
7. Les points hors de la zone couverte par les données sont « hors zone ». Les points où la source ne fournit pas le service choisi sont « sans donnée pour ce service ». Les deux sont exclus des pourcentages.
8. Les valeurs brutes des pixels sont gardées : changer d'opérateur ou de service refait le rapport sans rien relire.

Les seuils sont des constantes de `src/config.ts` : `RESAMPLE_STEP_M` (20 m), `WHITE_ZONE_MIN_LENGTH_M` (100 m), `WHITE_ZONE_MERGE_GAP_M` (50 m), `SEGMENT_JOIN_MAX_M` (50 m), `ELEVATION_THRESHOLD_M` (5 m), `ELEVATION_MIN_SHARE` (0,5), `TRACK_MAX_JUMP_M` (10 km), `MAX_GPX_BYTES` et `SAMPLING_CONCURRENCY` (6). Voir [Réglages que le propriétaire peut revoir](#réglages-que-le-propriétaire-peut-revoir).

## Rapport, profil et export

### Rapport

Le bouton « Rapport » apparaît après l'import. On y trouve :

- la distance, le dénivelé et les altitudes extrêmes (quand plus de la moitié des points ont une altitude), les pays traversés, l'opérateur appliqué dans chaque pays, avec un lien « Modifier » ;
- la part du parcours par niveau, pour l'opérateur choisi (si vous en avez choisi un) et pour tous opérateurs. Les portions hors des données de couverture, et celles où la source ne fournit pas le service choisi, sont données à part et exclues des pourcentages ;
- la liste des zones blanches pour l'opérateur appliqué, par exemple « km 12,4 à 14,1, soit 1,7 km, altitude 1 850 à 2 100 m, Italie, estimée ». Toucher une zone la met en surbrillance et zoome dessus ;
- des avertissements : pays hors de l'itinérance de l'Union européenne (Suisse, Andorre, Monaco : vérifiez votre forfait), partie du parcours estimée (elle est alors en pointillé sur la carte), source qui dit seulement « couvert » ou « non couvert », service absent dans un pays traversé.

Les portions hors des données portent le libellé « hors zone », avec une courte explication (« hors des données de couverture »), dans le panneau, dans le texte du rapport et dans le profil. Sur téléphone, le bouton « Réduire le panneau » ramène le rapport à son titre pour laisser voir la carte ; le tracé y est recadré.

### Profil altimétrique

Le profil est dans le rapport, quand plus de la moitié des points du tracé ont une altitude, lue dans le GPX ou interpolée. Il est coloré selon la couverture. Chaque colonne prend la couleur de la pire couverture de sa portion : une courte zone blanche reste visible sur un long parcours. Les portions estimées sont hachurées, sauf pour un service que l'estimation ne fournit pas. Survoler ou toucher le profil place un repère sur la carte et affiche le kilomètre, l'altitude et la couverture. Sur écran tactile, cette lecture disparaît quand on lève le doigt : constaté en émulation, non vérifié sur un vrai téléphone. Au clavier, le profil se parcourt avec les flèches (1 % du tracé par appui), les touches Page (10 %), Début et Fin ; les lecteurs d'écran annoncent la part du parcours sans couverture.

### GPX enrichi et rapport en texte

- « Télécharger le GPX enrichi » donne le GPX d'origine avec un point de passage au début et à la fin de chaque zone blanche (« Zone blanche 1, début », etc.), pour une montre ou une application GPS. `rando.gpx` devient `rando-zones-blanches.gpx` (le suffixe suit la langue).
- Le fichier est toujours écrit en UTF-8. Il est fabriqué dans le navigateur. Chaque point ajouté porte le type `zone-blanche`, écrit ainsi dans toutes les langues : si l'on réimporte un GPX déjà enrichi, ces anciens points sont reconnus et remplacés au prochain export.
- « Copier le rapport » met le rapport en texte dans le presse-papiers. Ce texte est aussi visible sous « Rapport en texte ».

## Pied de carte et panneau Sources

- Les mentions des fonds et des données affichés sont en pied de carte, avec leurs liens. Le pied de carte crédite les données de chaque pays présent à l'écran, pour le service choisi. Quand un pays estimé est à l'écran, il ajoute le crédit d'OpenCellID (la base d'antennes de l'estimation), précédé du mot « estimation » dans la langue choisie.
- Sur ordinateur, il reste visible. Sur téléphone, il est déplié au chargement, se replie au premier geste sur la carte, et le bouton « © » le rouvre ; la mention d'OpenTopoMap y prend sa forme courte. Ce repli est un compromis à valider (voir [Limites](../README.md#limites)).
- Le panneau « Sources » s'ouvre par le lien « Sources » du pied de carte, ou par « Paramètres » puis « Sources des données ». Il commence par la phrase « Couverture théorique, des écarts locaux sont possibles. » Il a une section par pays, ouverte d'emblée pour les pays à l'écran : source, date des données, méthode, niveaux, technologies, licence (avec la phrase ou le logo que la licence impose), contour du pays, opérateurs, avertissement d'itinérance. Viennent ensuite la phrase sur les données transformées et la date de génération des tuiles, puis les crédits des fonds de carte et de la recherche, et un lien vers [sources.md](sources.md).
- La phrase sur les données transformées dit, dans les cinq langues, que les données d'origine ont été rastérisées (changées en pixels) sur une grille commune, puis ramenées à des niveaux ou à des seuils. Pour une source estimée, le panneau donne aussi le nombre de sites d'antennes connus, avec une phrase qui rappelle que moins il y a de sites, moins l'estimation est fiable. Il le fait seulement quand le manifest donne ce nombre, ce que ne fait pas encore le manifest en ligne (voir [Le manifest](#le-manifest)).
- Les noms des sources, les licences et les mentions de contour s'affichent dans la langue choisie quand le manifest en donne la traduction, sinon en français.
- Les mentions imposées, écrites telles quelles, portent l'attribut `lang` de leur langue, utile aux lecteurs d'écran. C'est déjà le cas de la mention d'OpenTopoMap (en allemand) et du crédit d'OpenCellID en pied de carte (en anglais). Pour l'AGCOM, le ministère espagnol, la phrase de licence de l'estimation et les contours espagnol, andorran et monégasque, la langue viendra du manifest (`mentionLang`, `boundary.lang`). D'ici là, ces mentions n'ont pas d'attribut de langue, et les phrases de licence portent `lang="mul"` (langue non précisée).
- Le texte exact des mentions est dans [Licences et crédits](../README.md#licences-et-crédits) et dans [sources.md](sources.md#affichage-des-mentions).

## Mode hors ligne

### Ce que voit l'utilisateur

« Préparer ce tracé pour le hors ligne », dans le rapport, enregistre dans le navigateur le GPX et une copie du manifest des données. Il enregistre aussi la couverture d'un couloir de 700 m de part et d'autre du tracé (zooms 8 à 12), et le fond de carte le long du parcours, quand son fournisseur l'autorise. En mode Automatique, chaque portion du tracé reçoit le fond national de son pays ; l'estompage du relief (l'ombrage qui le fait ressortir) suit s'il est affiché.

- « Annuler l'enregistrement » l'arrête. Un enregistrement interrompu reste visible, marqué incomplet : « Reprendre l'enregistrement » le termine sans retélécharger ce qui est déjà là. À la fin, le panneau dit ce qui a été enregistré et ce qui manque, fond par fond.
- Sans réseau, ou quand le réseau ne livre pas le manifest des données en 3 secondes, le site travaille sur la copie enregistrée et recharge tout seul le tracé préparé. Le panneau « Importer un GPX » propose aussi « Reprendre le tracé enregistré ».
- Un seul tracé est gardé : en préparer un autre remplace le précédent. Si les données de couverture ont été republiées depuis, le panneau invite à mettre l'enregistrement à jour.
- « Supprimer les données hors ligne » efface les tuiles et le tracé enregistrés, après confirmation.
- À faire avant de partir, avec du réseau. Les limites du mode hors ligne sont dans [Limites](../README.md#limites).

### Le Service Worker

Le Service Worker (`public/sw.js`) est un petit programme que le navigateur garde à côté du site. Il sert les fichiers enregistrés quand il n'y a pas de réseau. Il n'est installé que par la version construite du site, pas par `npm run dev` (le serveur de développement).

- **La coque du site** : `index.html` et tous les fichiers du site construit (scripts, styles, icône, logo de licence), sauf les données de couverture, le Service Worker lui-même et les fichiers d'aide au débogage (`.map`). À la construction, `src/offline/shell.ts` en dresse la liste, en tire une version (une empreinte de leur contenu) et l'écrit dans `dist/sw.js`. Le Service Worker enregistre toute la liste d'un coup à son installation, dans un cache propre à cette version, et vérifie qu'`index.html` est bien celui de cette version. Les coques des versions précédentes sont effacées : `index.html` vient toujours avec ses propres scripts. Avant de préparer un tracé, la page vérifie que la coque est complète (elle l'attend jusqu'à 30 secondes à la première visite) ; sinon elle le dit.
- **La page et ses fichiers** : dès qu'une coque complète est enregistrée, la page vient d'elle, sans attendre le réseau, quels que soient `?lang=` et les autres paramètres de l'adresse. Ses fichiers aussi : il n'y a jamais de mélange de versions. Une nouvelle version du site s'installe en arrière-plan, dans sa propre coque. Elle ne sert qu'une fois fermés tous les onglets de la version en cours : sur un téléphone, un onglet gardé ouvert garde l'ancienne version, et un simple rechargement ne suffit pas. À la première visite, avant que la coque soit complète, la page vient du réseau.
- **Le manifest des données** : celui du réseau s'il arrive en 3 secondes (`NETWORK_TIMEOUT_MS`) et n'est pas une erreur du serveur (code 500 ou plus). Sinon, c'est la copie enregistrée avec le tracé préparé ; sans copie, on attend le réseau. Ce qui arrive du réseau n'est rangé nulle part : seule la préparation d'un tracé enregistre le manifest. La copie porte un en-tête (`x-czb-copie-locale`), une étiquette jointe à la réponse : la page sait ainsi qu'elle travaille sur les données enregistrées, et recharge le tracé préparé.
- **Les tuiles de fond, styles et polices**, servis par d'autres sites : la copie locale si elle existe, sinon le réseau. Seul le bouton « Préparer ce tracé pour le hors ligne » remplit ce cache, tracé par tracé.
- **Les tuiles de couverture** : les lectures partielles des archives PMTiles ne passent pas par le Service Worker. La page enregistre elle-même les tuiles du couloir (zooms 8 à 12), rangées sous le nom de leur archive (`hors-ligne/couverture/<archive>/z/x/y`), et les relit avant le réseau (`src/offline/manager.ts`). Un tracé préparé ne dépend donc plus du réseau, et les tuiles d'une édition des données ne sont jamais lues avec le manifest d'une autre.

Le Service Worker est écrit en JavaScript, pas en TypeScript comme le reste du site : le compilateur ne le vérifie pas (voir [Limites](../README.md#limites)). Il recopie à la main deux constantes du code : le nom du cache hors ligne (`OFFLINE_CACHE` de `src/offline/manager.ts`) et le dossier des données (`DATA_BASE_URL` de `src/config.ts`). Le délai réseau lui arrive dans son adresse (`sw.js?delai=`), avec 3 secondes par défaut.

### Le préchargement

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

Ces plafonds et ces freins sont des choix du projet, compatibles avec les conditions lues chez chaque fournisseur (voir [sources.md](sources.md#mode-hors-ligne)).

- Si le couloir demande plus de tuiles que le plafond, les zooms les plus fins sont abandonnés.
- L'écart entre deux requêtes se compte depuis le départ réel de la précédente.
- Sur une réponse 429 ou 503 (trop de requêtes, ou service indisponible), tout ce fond attend la durée de l'en-tête `Retry-After` (5 secondes s'il est absent ou illisible), puis reprend. Il est abandonné après 3 refus d'une même tuile, une attente demandée de plus de 60 secondes, ou 8 échecs réseau d'affilée ; le panneau dit alors combien d'éléments manquent.
- Pour swisstopo, IGN España et l'estompage, rien n'est demandé hors de l'emprise que le fournisseur sert (champ `bounds`). `tile.openstreetmap.org` n'est jamais préchargé : ses conditions interdisent l'usage hors ligne.

## Tests

Vitest et pytest sont des outils qui lancent des tests automatiques ; Playwright pilote un vrai navigateur.

- **Site** (`npm test`, Vitest, dossier `tests/`) : 230 tests dans 17 fichiers, tous réussis sur l'état final du code (commit `dfc96f0` ; un commit est un état enregistré du code), et `npx tsc --noEmit` (le contrôle des types de TypeScript) sans erreur. Ils couvrent :
  - l'encodage et le décodage des 4 canaux, la lecture du manifest (champs facultatifs, entrées mal formées, ancien préfixe « Estimation : ») et les tables de niveaux ;
  - la lecture du GPX (trace, route, multi-segments, sans altitude, encodages, préfixes, points aberrants, sauts), le rééchantillonnage, les zones blanches, les kilomètres, les statistiques, la partie « hors zone », le rapport en texte et l'export ;
  - le profil altimétrique (clavier, portions estimées, « hors zone ») ;
  - le mode hors ligne (couloir, coque du Service Worker et page servie par elle, enregistrement, reprise, fonds au rythme de chaque fournisseur, mode Automatique sans réseau) ;
  - la recherche (services lents, en panne ou annulés, centre arrondi) et le style de la carte ; « Ma position » ;
  - la lecture des archives (lectures qui calent, tuile illisible, nouvelle publication) ; la recoloration des tuiles (hachures et fins traits gris des zones estimées) et les deux caches ; le contrôle du décodage par le canvas ;
  - les traductions : mêmes clés dans toutes les langues, mêmes paramètres entre accolades, aucun texte vide, glossaire respecté, toutes les clés utilisées par le code présentes, nombres insérés écrits selon la langue, message sans JavaScript dans chaque langue, et aucun tiret cadratin ni demi-cadratin dans les traductions, le README, `index.html`, le manifeste web et `docs/`. Le test du glossaire porte sur toutes les clés dont le texte français parle de zone blanche.
- **Site et pipeline ensemble** : les tests du site relisent une petite archive PMTiles produite par le pipeline sur des données synthétiques (`tests/fixtures/synthetique/`) et comparent ses pixels aux points témoins du pipeline (des pixels de contrôle dont il connaît la valeur attendue). L'encodage du pipeline (Python) et le décodage du site (TypeScript) sont ainsi contrôlés ensemble.
- **Pipeline** (`pipeline/tests/`, pytest) : 67 tests, tous réussis. Tout tourne sur des données synthétiques, sans réseau (les termes du pipeline sont expliqués dans [pipeline.md](pipeline.md)) :
  - faux fichiers Arcep (adresses `file://`, archives 7z, des fichiers compressés), GeoTIFF (image géoréférencée) fabriqué pour la Suisse, faux service ArcGIS (service web de données géographiques) pour l'Italie et l'Espagne (`fake_arcgis.py`), relief et cellules inventés pour l'estimation, frontières entre deux pays ;
  - une construction complète passe le test de cohérence, qui doit aussi détecter un niveau faux ;
  - d'autres tests vérifient la pyramide en plus proche voisin, le découpage en archives, le calage de la grille espagnole et la reprise des copies de travail (les résultats gardés d'une construction à l'autre). D'autres encore vérifient le comblement des interstices de frontière (les petits trous entre les contours, comblés seulement s'ils sont bordés par deux entités), le garde-fou de surface des contours, la suppression des contours dès qu'ils sont lus, les emplacements non déclarés toujours à 0, le refus des téléchargements coupés, la clé d'OpenCellID absente des journaux, et les mentions et le logo de `SOURCES.md` ;
  - les traductions des textes du manifest (les quatre langues ou aucune, noms propres et formules imposées gardés, langue des mentions imposées), et la détection d'une nouvelle édition de la carte espagnole par la page du ministère ;
  - la commande `changed` (détection d'une source qui a changé) a ses propres tests : rien n'a changé, une source a changé, version du pipeline changée, aucune release (publication des données sur GitHub), option `--force`. Un dernier test vérifie que l'échec du redéploiement du site n'est pas masqué dans le workflow « Données ».
- **GPX de test** : `samples/test-alpes.gpx` (de Préfumet à La Visaille par Les Chapieux et le col de la Seigne, France et Italie, 27,1 km) part d'une zone couverte. Il entre en zone blanche au km 2,7, dans les données de l'Arcep, et sa dernière zone blanche s'arrête à la frontière, au km 17,5 : son rapport, tous opérateurs, en liste quatre, toutes en France, séparées par de courts passages en couverture limitée. `samples/test-pyrenees.gpx` (de Gavarnie au refuge de Góriz par la brèche de Roland, France et Espagne, 14,0 km) traverse des zones blanches des deux côtés : son rapport en liste six, deux en France et quatre en Espagne, dont l'arrivée au refuge de Góriz, sans réseau 4G dans la carte espagnole. Ces rapports ont été recalculés avec le code final du site sur les tuiles de la release en ligne, `data-2026-11-14`. Ce sont des tracés de test, à ne pas utiliser pour s'orienter. Leur fabrication, leurs licences et les zones blanches attendues sont décrites dans [`samples/README.md`](../samples/README.md).
- **Site en ligne** : `e2e/verif.mjs`, lancé par le workflow « Vérification » (voir [pipeline.md](pipeline.md#vérification)).

## Réglages que le propriétaire peut revoir

Ces valeurs sont des choix du projet. Elles se changent dans le code, puis le site est republié par un push sur `main`, c'est-à-dire l'envoi des modifications sur la branche principale du dépôt.

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
| `NETWORK_TIMEOUT_MS` | `src/config.ts` | 3 s | attente du réseau avant de servir la copie enregistrée du manifest des données ; la page, elle, vient de la coque sans attendre |
| `VECTOR_STYLE_TIMEOUT_MS` | `src/config.ts` | 8 s | attente du style vectoriel du Plan IGN |
| `COVERAGE_DISPLAY_MAX_ZOOM` | `src/config.ts` | 16 | dernier zoom des tuiles de couverture fabriquées pour l'affichage |
| `SEARCH_MIN_CHARS`, `SEARCH_DEBOUNCE_MS`, `SEARCH_MAX_RESULTS` | `src/config.ts` | 3 caractères, 350 ms, 6 lieux | déclenchement et longueur de la recherche |
| `SEARCH_TIMEOUT_MS` | `src/config.ts` | 5 s | délai maximal de chaque service de recherche |
| `PHOTON_LANGS` | `src/config.ts` | de, en, fr | langues demandées à Photon |
| `INITIAL_VIEW`, `MAX_BOUNDS` | `src/config.ts` | la France ; de 12° ouest à 18° est, de 36° à 54,5° nord | vue de départ ; zone où la carte peut aller, et recherche à l'étranger |
| arrondi du centre envoyé à la recherche | `src/search/geocode.ts` (`roundedCenter`) | 0,1° (environ 10 km) | précision du centre de la carte que reçoivent l'IGN et Photon |
| `LOCATE_SLOW_MS` | `src/map/locator.ts` | 15 s | message « le GPS cherche encore » |
| `LOCATE_MAX_ZOOM` | `src/map/mapView.ts` | 15 | zoom maximal du recentrage sur la position |
| capacité des caches | `src/coverage/store.ts` | 160 tuiles, plus 32 pour l'analyse | tuiles décodées gardées en mémoire |
| `MANIFEST_RECHECK_MS` | `src/coverage/freshness.ts` | 1 min | écart minimal entre deux relectures de `manifest.json` qui n'ont rien trouvé de nouveau |
| `CORRIDOR_BUFFER_M` | `src/offline/manager.ts` | 700 m | couloir enregistré de chaque côté du tracé |
| `RETRY_DEFAULT_MS`, `RETRY_MAX_WAIT_MS`, `RETRY_TRIES`, `MAX_FAILURES_IN_A_ROW` | `src/offline/manager.ts` | 5 s, 60 s, 3 refus, 8 échecs | attente et abandon d'un fond pendant le préchargement |
| champ `offline` de chaque fond | `src/map/basemaps.ts` | voir [Le préchargement](#le-préchargement) | plafonds et freins du préchargement |

Choix faits dans le code, à confirmer :

- la longueur d'une zone blanche est tirée de ses bornes arrondies à 100 m (`src/gpx/report.ts`) ;
- le manifest refuse le WebP (`src/coverage/manifest.ts`), et le pipeline écrit du PNG (voir [Limites](../README.md#limites)) ;
- la page vient de la coque enregistrée, si bien qu'une nouvelle version n'apparaît qu'une fois fermés tous les onglets de l'ancienne ; et le préchargement est piloté par la page, pas par le Service Worker comme le décrit le cahier des charges (voir [Décisions laissées au propriétaire](../README.md#décisions-laissées-au-propriétaire)) ;
- les crédits d'OpenStreetMap de la recherche et du panneau Sources sont traduits (« © les contributeurs d'OpenStreetMap » en français), avec un lien vers la page des droits ;
- en pied de carte, une zone estimée affiche le crédit qu'OpenCellID demande (« Cell tower data from OpenCellID, licensed under CC BY-SA 4.0 »), à la place de la mention de la source du manifest. La mention complète, Copernicus compris (le relief utilisé par l'estimation), est dans le panneau Sources ;
- la mention d'IGN España reste « CC BY 4.0 ign.es » (voir [Décisions laissées au propriétaire](../README.md#décisions-laissées-au-propriétaire)) ;
- le lien d'OpenTopoMap reste http://opentopomap.org, mot pour mot comme dans sa mention.

Les réglages du pipeline (limites de taille, points témoins, estimation, interstices de frontière) sont dans [pipeline.md](pipeline.md#réglages-du-pipeline).
