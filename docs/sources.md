# Sources

Ce document dit d'où viennent les données du site, sous quelles conditions elles sont réutilisées, comment le pipeline (la chaîne de traitement qui fabrique les tuiles de couverture, lancée dans GitHub Actions) les transforme et quelles sont leurs limites. Il tient aussi l'inventaire des sources examinées pour les pays frontaliers.

État au 14 novembre 2026. Les licences et les conditions d'usage ont été lues les 13 et 14 novembre 2026 par des sondes : de petits scripts lancés sur les machines de GitHub Actions, car l'environnement de développement ne joint pas ces sites. Les points qui comptent ont été relus une seconde fois par d'autres sondes (contre-vérification) : c'est leur version qui est retenue ici. Ce qui n'a pas pu être vérifié est marqué « non vérifié ». Quand un site ne répondait pas, des sondes ont parfois lu sa copie chez Internet Archive : ce document ne s'appuie pas sur ces copies. Dans les citations, les tirets longs des textes d'origine sont remplacés par des traits d'union.

## Ce que montre la carte

- La carte montre une couverture **théorique** : simulée ou déclarée par les opérateurs, ou estimée là où il n'existe pas de source officielle exploitable. Ce n'est pas une mesure. Le panneau « Sources » du site le rappelle : « Couverture théorique, des écarts locaux sont possibles. »
- Chaque pixel porte la nature de sa source :
  - **officielle, par opérateur** : on sait quel opérateur couvre (France, Espagne) ;
  - **officielle, agrégée** : on sait combien de réseaux couvrent, pas lesquels (Suisse, Italie) ;
  - **estimée** : calculée par le projet à partir de positions d'antennes et du relief (Andorre, Monaco). Ces zones sont hachurées sur la carte et dans le profil altimétrique, dessinées en pointillé sur le tracé, et marquées « estimée » dans le rapport et dans le GPX enrichi.
- Sur la carte, quand seuls les problèmes sont affichés, une zone estimée de niveau « bonne » n'est pas coloriée. Elle reçoit alors de fins traits gris peu opaques, dans le sens des hachures des zones estimées, sur fond transparent. Une tuile « données indisponibles » se distingue : elle est voilée de gris et rayée dans l'autre sens. Monaco et le centre de l'Andorre restent ainsi marqués comme estimés. La légende le dit : « Zone estimée avec une bonne ou très bonne couverture (fins traits gris) ».
- Niveaux : 0 pas de couverture, 1 couverture limitée, 2 bonne couverture, 3 très bonne couverture. Seule la France a les quatre niveaux. Les sources suisse, italienne et espagnole disent seulement « couvert » ou « non couvert » : pour ces pays, « bonne couverture » veut dire « couvert » sur la carte et dans le rapport, sans indication de qualité. Les zones estimées ont trois niveaux et jamais « très bonne ».
- « Tous opérateurs » est le meilleur niveau parmi les opérateurs du pays, calculé par le site. À l'étranger, la couverture réelle d'un visiteur dépend des accords d'itinérance de son opérateur.
- Toutes les sources sont ramenées sur une même grille : les tuiles (images carrées de 256 pixels qui forment la carte) du zoom 12, dont le pixel mesure 38,2 m en projection Web Mercator (celle des cartes en ligne), soit 24 à 29 m au sol selon la latitude (26 à 28 m dans les Alpes et les Pyrénées).
- Appels et SMS : seulement en France.
- Un point d'un tracé situé en dehors des données de couverture est dit « hors zone » dans le rapport et dans le profil, et il est exclu des pourcentages.

## Synthèse par pays

| Pays | Source retenue | Nature | Technologie | Niveaux | Date des données | Résolution | Licence |
|---|---|---|---|---|---|---|---|
| France (Corse comprise) | Arcep, « Mon réseau mobile » | officielle, par opérateur | internet : 4G ; appels et SMS : 2G et 3G | 4 | 30 juin 2026 | polygones | Licence Ouverte / Open Licence (Etalab) |
| Suisse | OFCOM, atlas de la large bande | officielle, agrégée | 4G | couvert ou non | 30 avril 2026 | 100 m | utilisation libre, source à citer |
| Italie (Piemonte, Valle d'Aosta, Liguria) | AGCOM, Broadband Map | officielle, agrégée | 4G | couvert ou non | 27 janvier 2026 | 100 m | CC BY 4.0, avec logo obligatoire |
| Espagne (Aragón, Cataluña, Navarra, País Vasco) | Ministerio para la Transformación Digital y de la Función Pública, « Mapa de Servicios de Banda Ancha Móvil 2024 » | officielle, par opérateur | 4G | couvert ou non | 30 juin 2024 | environ 28 m x 38,5 m | aucune licence attachée au jeu ; conditions générales de réutilisation du site du ministère |
| Andorre | estimation : OpenCellID et Copernicus DEM | estimée | 4G, 5G ; en pratique 4G seulement (aucune cellule 5G dans le fichier) | 3 | novembre 2026 (mois du calcul) | calcul au pixel de la grille, relief à 30 m | CC BY-SA 4.0, mention Copernicus |
| Monaco | estimation : OpenCellID et Copernicus DEM | estimée | 4G, 5G ; en pratique 4G seulement (aucune cellule 5G dans le fichier) | 3 | novembre 2026 (mois du calcul) | calcul au pixel de la grille, relief à 30 m | CC BY-SA 4.0, mention Copernicus |

Officielles : France, Suisse, Italie, Espagne. Estimées : Andorre et Monaco, faute de source officielle exploitable. Les six pays sont dans les données publiées (voir « Données publiées »).

## Données publiées

Le pipeline publie ses résultats dans une release GitHub, c'est-à-dire une page du dépôt qui porte des fichiers à télécharger. Elle s'appelle `data-AAAA-MM-JJ`. S'il existe déjà une release de données ce jour-là, elle prend le numéro qui suit le plus grand déjà pris (`data-AAAA-MM-JJ-2`, `-3`, etc.) : un nom libéré par le ménage des anciennes releases n'est pas repris. Le déploiement du site prend la release de données la plus récente par date de publication.

**Release en ligne : `data-2026-11-14`**, publiée le 14 novembre 2026 vers 19 h 03 UTC, avec les six pays. Elle porte le nom sans numéro parce qu'elle a été construite avant la règle de numérotation actuelle, alors que ce nom venait d'être libéré par le ménage. C'est bien la plus récente : le dernier déploiement du site (14 novembre 2026, 19 h 09 UTC) l'a téléchargée. Les deux autres releases gardées, `data-2026-11-14-3` et `data-2026-11-14-4`, sont plus anciennes.

Une release contient :

- les archives PMTiles : des fichiers qui rangent chacun une partie des tuiles, et que le site lit morceau par morceau ;
- `manifest.json`, le fichier qui décrit les tuiles pour le site : pays, opérateurs, sources, dates, licences, mentions. Chaque pixel a quatre places réservées aux opérateurs du pays ; le manifest précise que les places qu'un pays n'utilise pas valent toujours 0 ;
- `SOURCES.md`, qui redit en clair, pour chaque pays, la source, sa date, sa licence, sa mention, la phrase imposée par la licence quand il y en a une et la mention du contour du pays. Il est écrit par `pipeline/czb/notices.py` à partir du manifest, et repris dans le texte de la release ;
- le logo de l'AGCOM (`agcom-bbmap.jpg`), que sa licence exige dans toute œuvre dérivée, cité dans `SOURCES.md` avec son lien. `SOURCES.md` dit aussi, pour chaque source, sur une ligne « Modifications », que les données ont été transformées (rastérisées sur une grille commune, ramenées à des niveaux ou à des seuils) : c'est l'indication de modification que demandent les licences CC BY ;
- les copies de travail `cache-*.tif`, que le site n'utilise pas : la construction suivante les reprend (voir « Espagne » et « Estimation »). Celles de l'estimation (`cache-ad_estimation.tif`, `cache-mc_estimation.tif`) dérivent d'OpenCellID : elles sont sous CC BY-SA 4.0. Celle de l'Espagne (`cache-es_mtd.tif`) donne la présence 4G de chaque opérateur à la maille de la source : elle suit le sort de la couche espagnole (voir « Espagne », « Licence ») ;
- le rapport de construction (`rapport-construction.json`), l'état des sources que la construction suivante compare pour savoir si une source a changé (`etat-sources.json`), et les fichiers du test de cohérence (`temoins.json`, `temoins-attendus.json`, `temoins-contours.json`).

Seul le choix « production » du workflow « Données » (`.github/workflows/build-data.yml`), ou son passage mensuel, publie une release. Un lancement à la main d'un autre périmètre, même « complet » avec les mêmes services, est un essai : il est construit et vérifié, jamais publié. Après une publication, seules les trois releases de données les plus récentes sont gardées.

Construction de la release en ligne (`data-2026-11-14`, 14 novembre 2026, de 18 h 02 à 19 h 03 UTC), d'après son rapport et son journal :

- 353,13 Mo en 7 archives, la plus grosse de 69,67 Mo (chaque fichier doit rester sous 95 Mo) ;
- grille : tuiles du zoom 12 de x 1989 à 2167 et de y 1369 à 1552, soit 45 824 x 47 104 pixels ; 22 231 tuiles en tout, dont 16 388 au zoom 12 (185,60 Mo), 4 253 au zoom 11 et 1 128 au zoom 10 ;
- pixels par pays : France 797 184 391, Suisse 60 303 271, Italie 46 666 326, Espagne 120 410 608, Andorre 586 881, Monaco 2 716 ;
- durée du calcul : 3 620,5 s (le job entier a duré 61 minutes), dont contours des pays 66,1 s, Arcep 1 612,4 s, OFCOM 123,0 s, AGCOM 79,7 s, ministère espagnol 165,5 s, Andorre 1,1 s, Monaco 1,0 s et tuiles 1 567,5 s. Les copies de travail de l'Espagne, de l'Andorre et de Monaco ont été reprises : rien n'a été relu chez le ministère espagnol ni téléchargé chez OpenCellID ;
- test de cohérence : 1 200 points tirés dans les sources et 420 points des contours, comparés aux pixels relus dans les archives publiées : aucun écart ;
- la release contient aussi `SOURCES.md` (5 856 octets), le logo `agcom-bbmap.jpg` (11 900 octets) et `cache-es_mtd.tif` (7,3 Mo).

Le chemin « aucune source n'a changé » a aussi tourné pour de vrai : le 14 novembre 2026 à 16 h 59 UTC, la détection a répondu « changed=false (sources inchangées depuis data-2026-11-14-4) ». Rien n'a été reconstruit ni publié, et le job a duré 41 s.

## France

### Source

- Éditeur : Arcep. Jeu « Mon réseau mobile », couvertures théoriques : https://www.data.gouv.fr/datasets/mon-reseau-mobile
- Fichiers lus : https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/00_Metropole/, nommés `{année}_T{trimestre}_couv_Metropole_{OP}_{TECHNO}_{USAGE}.gpkg.7z`, avec OP = OF (Orange), SFR0 (SFR), BOUY (Bouygues Telecom), FREE (Free). Internet mobile : fichiers `4G_data`. Appels et SMS : fichiers `2G3G_voix`. Huit fichiers en tout.
- Contenu : GeoPackage (fichier de données géographiques) en Lambert-93 (EPSG:2154), un multipolygone par département et par niveau (schéma vérifié sur l'édition du 2e trimestre 2026, d'après l'en-tête du module). Champs : operateur, date, techno, usage, niveau, dept, operateur_infra, operateur_commercial. Le champ `niveau` vaut TBC (très bonne couverture), BC (bonne couverture) ou CL (couverture limitée). Là où il n'y a pas de polygone, il n'y a pas de couverture.

### Date des données

Édition du 2e trimestre 2026, données au 30 juin 2026. L'Arcep publie une édition par trimestre. Chaque mois, le pipeline compare la liste des fichiers (noms, tailles, dates) à celle de la dernière construction.

### Licence

data.gouv.fr déclare le jeu « Mon Réseau Mobile » sous l'identifiant `fr-lo`, « Licence Ouverte / Open Licence » (sonde du 14 novembre 2026). L'adresse officielle de cette licence, https://www.etalab.gouv.fr/wp-content/uploads/2014/05/Licence_Ouverte.pdf, renvoie aujourd'hui au PDF de la Licence Ouverte 2.0 : https://static.data.gouv.fr/resources/licence-ouverte-2-0/20240711-152120/licence-ouverte.pdf. Le manifest et le site renvoient à la page de la version 2.0 : https://www.data.gouv.fr/pages/legal/licences/etalab-2-0.

Le texte de la Licence Ouverte 2.0 (https://raw.githubusercontent.com/etalab/licence-ouverte/master/LO.md) laisse au réutilisateur la liberté « de la communiquer, la reproduire, la copier » et « de la diffuser, la redistribuer, la publier et la transmettre, de l’exploiter à titre commercial », à une condition :

> mentionner la paternité de l’«Information» : sa source (a minima le nom du « Concédant ») et la date de la dernière mise à jour de l’« Information » réutilisée.

### Mention affichée dans le site

- Pied de carte : « Couverture : Arcep ».
- Panneau « Sources » : « Arcep, Mon réseau mobile : couvertures théoriques », avec un lien vers la fiche data.gouv.fr ; date des données (« T2 2026 ») ; méthode « Officielle, par opérateur » ; niveaux ; technologies ; licence avec son lien ; mention du contour du pays (voir « Contours des pays ») ; opérateurs (Orange, SFR, Bouygues Telecom, Free).

### Méthode

Module `pipeline/czb/sources/fr_arcep.py`.

1. Le pipeline lit la page d'index de data.arcep.fr. Pour chaque opérateur et chaque service, il doit y trouver exactement un fichier, sinon il s'arrête.
2. Il télécharge un fichier à la fois, le décompresse et supprime l'archive. Le GeoPackage est supprimé dès qu'il a été traité.
3. Il vérifie le fichier : une seule couche, champ `niveau` présent, système de coordonnées renseigné. Une valeur de niveau inconnue arrête la construction.
4. Il traduit les niveaux (CL = 1, BC = 2, TBC = 3), reprojette les polygones vers la grille du zoom 12 et allume un pixel quand son centre est dans un polygone. Si deux niveaux se chevauchent, le plus élevé gagne. Chaque opérateur a son emplacement, c'est-à-dire une place réservée dans chaque pixel des tuiles : Orange, SFR, Bouygues Telecom, Free.
5. Points témoins (points de contrôle) : 60 points par fichier, tirés au hasard puis répartis entre les niveaux. Leur niveau est calculé dans le fichier source par un test géométrique exact (les points à moins de 50 cm d'un bord sont écartés), puis comparé aux pixels relus dans les archives publiées. Le moindre écart fait échouer la construction.

Construction de la release en ligne (`data-2026-11-14`) : 8 fichiers Arcep (2 174,7 Mo téléchargés, un à la fois), 1 612,4 s de traitement, 797 184 391 pixels pour la France, 480 points témoins sans écart.

### Limites

- Couverture théorique simulée par les opérateurs, pas une mesure de terrain.
- Une édition par trimestre, publiée après la date des données : au 14 novembre 2026, la carte montre la situation au 30 juin 2026.
- Résolution : les fichiers sont des polygones, sans résolution annoncée. Le manifest n'en donne pas pour la France.
- La partie française du Léman est hors zone (voir « Contours des pays »).

## Suisse

### Source

- Éditeur : OFCOM (Office fédéral de la communication ; BAKOM en allemand, UFCOM en italien). Atlas de la large bande : https://www.bakom.admin.ch/en/broadband-atlas
- Jeu : disponibilité des réseaux mobiles 4G, collection `ch.bakom.mobilnetz-4g` du catalogue STAC (catalogue de données géographiques) de la Confédération : https://data.geo.admin.ch/api/stac/v0.9/collections/ch.bakom.mobilnetz-4g/items
- Contenu : un GeoTIFF (image géoréférencée) `mobilnetz-4g_2056.tif`, en CH1903+ / LV95 (EPSG:2056), carrés de 100 m. Valeurs : 0 = pas de couverture ; 2 = couvert par moins de 3 opérateurs ; 3 = couvert par les 3 opérateurs (Swisscom, Sunrise, Salt). La description de la collection dit qu'il s'agit de la couverture extérieure : « For each cell, you can see the number of operators theoretically providing an outdoor 4G connection (on the street, in a public square, etc.). »

### Date des données

Édition du 30 avril 2026 (date de l'item STAC). Le pipeline surveille la date de l'item et celle du fichier.

### Licence

`config.yaml` : « Utilisation libre, source à citer (géodonnées de la Confédération) ». Le site renvoie aux conditions générales de l'infrastructure fédérale de données géographiques (« FSDI »), https://www.geo.admin.ch/en/general-terms-of-use-fsdi, en vigueur depuis le 1er janvier 2025. Mot pour mot :

> The acquisition and use of data or services is free of charge, subject to the provisions on fair use.

> Geodata in machine-readable form is freely available on the Federal Spatial Data Infrastructure FSDI. The geoservices are made available within the framework of the FSDI via geo.admin.ch. The data obtained may be processed, analysed and published in accordance with their terms of use, along with the inclusion of further data.

> In publications and analyses based on the FSDI, any reference to the source must be made in accordance with the terms of use of the corresponding dataset, as is done in the lower right corner of the map viewer.

Les conditions propres au jeu ont été lues sur opendata.swiss : toutes les ressources du jeu « 4G - LTE / LTE-A Verfügbarkeit » renvoient à https://opendata.swiss/terms-of-use#terms_open, l'usage libre (« Open use ») : « You may use this dataset for non-commercial purposes. You may use this dataset for commercial purposes. You are recommended to provide the source (author, title and link to the dataset). » La mention retenue par le projet (« source à citer ») est donc plus prudente que ce qui est demandé. Le catalogue STAC déclare une licence « proprietary » avec un lien « Terms of use » vers http://disclaimer.admin.ch/, page non lue (non vérifié). Les conditions FSDI ont été lues en anglais ; elles précisent que la version allemande fait foi.

### Mention affichée dans le site

- Pied de carte : « Couverture : OFCOM ».
- Panneau « Sources » : « OFCOM, atlas de la large bande : disponibilité des réseaux mobiles 4G » (en allemand, le nom commence par « BAKOM », en italien par « UFCOM »), avec un lien vers l'atlas ; licence avec un lien vers les conditions FSDI ; note « couvert ou non couvert » ; mention du contour du pays ; opérateurs du pays (Swisscom, Sunrise, Salt) ; avertissement : la Suisse ne fait pas partie de l'itinérance de l'Union européenne.

### Méthode

Module `pipeline/czb/sources/ch_bakom.py`.

1. Le pipeline lit la collection STAC. Il attend exactement un item et un GeoTIFF, sinon il s'arrête.
2. Il télécharge le GeoTIFF, vérifie le système de coordonnées (EPSG:2056) et les valeurs. Une valeur inconnue arrête la construction : on ne devine pas son sens.
3. Il traduit chaque carré en nombre minimal d'opérateurs : 0, 1 (pour « moins de 3 ») ou 3.
4. Les carrés sans donnée collés à la frontière sont comblés en deux passes (200 m au plus) avec la plus petite valeur de leurs voisins : dans le doute, on annonce le moins de couverture.
5. Deux emplacements : « au moins un opérateur » et « les trois opérateurs ». Un carré couvert reçoit le niveau 2 (« couvert »), sinon 0. L'image est ramenée sur la grille en plus proche voisin : chaque pixel prend la valeur du carré qui contient son centre. Les pixels suisses sans donnée comptent comme non couverts.
6. Points témoins : niveau lu directement dans la grille de la source (points à moins de 1 m d'un bord de carré écartés), 60 par emplacement.

Construction de la release en ligne (`data-2026-11-14`) : 4 118 100 carrés de 100 m lus, 60 303 271 pixels pour la Suisse, dont 9 908 sans donnée dans la source (comptés comme non couverts), 123,0 s, 120 points témoins sans écart.

### Limites

- Source agrégée : on sait combien d'opérateurs couvrent, pas lesquels. La valeur « moins de 3 » ne dit pas s'il y en a un ou deux ; le pipeline la traduit par « au moins un ». On ne peut pas choisir Swisscom, Sunrise ou Salt.
- Pas de niveau de qualité : « bonne couverture » veut dire « couvert ».
- Pas de carte des appels et SMS : le pipeline ne lit que la couche 4G.
- Couverture théorique annoncée par les opérateurs. La description de la collection prévient : « Information on the coverage is calculated using predictive models and does not guarantee accuracy. »
- Hors itinérance de l'Union européenne : le rapport avertit quand le tracé passe en Suisse.

### Autres sources examinées et pourquoi elles ne sont pas retenues

- Positions des stations de base de l'OFCOM (collection `ch.bakom.standorte-mobilfunkanlagen`, un GeoJSON de 22 732 points avec opérateur, technologie et classe de puissance ; conditions opendata.swiss : « Open use. Must provide the source. You may use this dataset for non-commercial purposes. You may use this dataset for commercial purposes. You must provide the source (author, title and link to the dataset). ») : ce sont des positions d'antennes, pas une carte de couverture. Elles serviraient à une estimation par opérateur si un jour il en fallait une. Inutile tant que la carte officielle existe.
- Couche 5G de l'OFCOM (`ch.bakom.mobilnetz-5g`, identifiant tiré du cahier des charges, non vérifié) : non lue par le pipeline, qui s'en tient à la 4G comme pour les autres pays à source officielle. Non examinée dans les notes de recherche.

## Italie

### Source

- Éditeur : AGCOM (Autorità per le garanzie nelle comunicazioni). Broadband Map, couche « 4G » : https://www.agcom.it/broadband-map ; portail de données ouvertes : https://geo3.agcom.it/opendata/
- **Pas de fichier téléchargeable.** Le menu « Download > Rete mobile » du portail ne donne qu'un code à envoyer par courriel à opendata.bbmap@agcom.it. Le pipeline lit donc, sans clé d'accès, le service ArcGIS REST public (un service web qui renvoie à la demande les données d'une carte) d'où vient la carte du portail : couche 0 de https://geo3.agcom.it/MapET-SFS/rest/services/Grid100/mobile_4G/MapServer (couche « mobile_4G_260127_260205 »). Ce n'est pas la voie de téléchargement que désigne le portail (la demande par courriel). La licence CC BY 4.0 couvre les données (« Tutti i dati del Portale BBMap », voir « Licence ») ; le choix de cette voie d'accès revient au propriétaire du projet.
- Contenu : polygones en EPSG:3857, un par commune et par valeur. Champs utiles : `fid`, `n_infrastrutture_totali` (nombre d'infrastructures de réseau mobile 4G qui couvrent le carré, de 1 à 4), `COD_REG` (1 Piemonte, 2 Valle d'Aosta, 7 Liguria). Les carrés de 100 m suivent une grille ETRS89-LAEA (EPSG:3035), découpée aux limites communales. Pas de polygone : aucun réseau (déduction étayée par la recherche, aucun texte de l'AGCOM ne le dit).

### Date des données

Données du 27 janvier 2026, publiées le 2 février 2026 (« Dati del 27 gennaio 2026 - Pubblicazione del 2 feb 2026 », lu dans le service `data_pubblicazione`).

### Licence

CC BY 4.0. Page « Termini e condizioni » : https://www.agcom.it/termini-e-condizioni (publiée le 15/10/2024). Mot pour mot :

> Tutti i dati del Portale BBMap sono rilasciati sotto licenza Creative Commons Attribuzione 4.0 Internazionale (CC BY 4.0, disponibile all'indirizzo https://creativecommons.org/licenses/by/4.0/ ). In base a tale licenza, è possibile riprodurre, distribuire, trasmettere e adattare liberamente dati e analisi del sistema di mappatura dell'Autorità a condizione che vengano citate la paternità dei dati e l'indirizzo del Portale BBMap. A tal fine in ogni lavoro o opera derivata basata, anche in minima parte, sui dati del Portale BBMap dovrà essere riportato il seguente logo.

Texte placé sous le logo :

> BroadbandMap di Agcom - Autorità per le garanzie nelle comunicazioni è distribuito con Licenza Creative Commons Attribuzione 4.0 Internazionale .

Usages interdits :

> È vietato l'uso o la pubblicazione dei dati del Portale BBMap per finalità di incitamento di attività criminali, illegali, razziste, discriminatorie, diffamatorie, pornografiche, sessiste o omofobe o comunque con modalità che ledano l'immagine dell'Autorità.

- Les conditions nomment l'adresse `www.agcom.it/broadbandmap`, qui répond 404. Dans la page des conditions, le logo et le nom « BroadbandMap di Agcom » renvoient à https://maps.agcom.it/, qui affichait les 13 et 14 novembre 2026 « Sito non disponibile per manutenzione programmata ». Depuis quand ce site est en maintenance : non vérifié. Le nom de la source renvoie donc à https://www.agcom.it/broadband-map, qui répond et mène au portail ; le logo, lui, renvoie à https://maps.agcom.it/, comme le fait l'AGCOM.
- Aucune clause n'interdit l'accès automatisé, aucune ne le décrit non plus.

### Mention affichée dans le site

- Pied de carte : « Couverture : BroadbandMap di Agcom (CC BY 4.0) ».
- Panneau « Sources » : nom de la source avec un lien vers https://www.agcom.it/broadband-map ; licence avec un lien vers les conditions ; la phrase placée sous le logo ; **le logo de l'AGCOM** exigé par la licence (image JPEG de 221 x 110 pixels fournie par l'AGCOM, fichier `public/licences/agcom-bbmap.jpg`), en lien vers https://maps.agcom.it/ ; note « couvert ou non couvert » ; mention du contour du pays.
- La licence CC BY 4.0 demande aussi d'indiquer que les données ont été modifiées. Le panneau « Sources » le dit pour toutes les sources, dans les cinq langues, et `SOURCES.md` le dit dans la release, où le logo est joint (voir « Données publiées »).

### Méthode

Modules `pipeline/czb/sources/it_agcom.py` et `pipeline/czb/arcgis.py`.

1. Détection d'une nouvelle édition : description du service (« mobile_4G_20260127 »), nom de la couche, phrase de date et nombre d'entités des trois régions. La date des données est lue dans cette description du service.
2. Lecture : requêtes filtrées sur `COD_REG IN (1,2,7)`, 250 entités par page, triées par `fid` croissant, envoyées l'une après l'autre avec une pause d'une seconde, soit 19 requêtes pour les trois régions. Ce serveur ignore sans prévenir le paramètre de décalage habituel (`resultOffset`) : on pagine donc par identifiant. À la fin, le nombre d'entités lues doit être égal au nombre annoncé par le service.
3. Chaque page est un fichier temporaire, supprimé dès que la suivante est demandée. Une valeur hors de 1 à 4 arrête la construction.
4. Les polygones sont déjà en EPSG:3857 : ils sont rastérisés directement sur la grille (centre du pixel). Une entité de valeur n écrit « couvert » (niveau 2) dans les emplacements « au moins 1 réseau » à « au moins n réseaux ». Sans polygone, le niveau reste 0.
5. Points témoins : niveau attendu calculé sur les polygones par un test géométrique exact, 60 par emplacement.

Construction de la release en ligne (`data-2026-11-14`) : 4 697 polygones (982 de valeur 1, 1 433 de valeur 2, 1 460 de valeur 3, 822 de valeur 4), 44 126 447 pixels allumés dont 43 169 hors du pays, 46 666 326 pixels pour l'Italie, 79,7 s, 240 points témoins sans écart.

### Limites

- Source agrégée : un nombre de réseaux, pas leur nom. La carte officielle intitule la couche « Copertura 4G (rev. 5/2/2026) - N. Operatori di rete » et le champ « N. infrastrutture di rete » : c'est un nombre d'opérateurs de réseau. Aucune source lue ne nomme ces opérateurs ni ne dit comment sont comptés deux opérateurs qui partagent un même réseau. Le site dit « au moins N réseaux ».
- Pas de niveau de qualité : « bonne couverture » veut dire « couvert ».
- Pas de données 2G ou 3G récentes (voir plus bas) : pas d'appels et SMS pour l'Italie.
- Couverture théorique déclarée par les opérateurs. Le critère de couverture (seuil de signal, extérieur ou intérieur) n'est défini dans aucune source lue. L'AGCOM prévient : « I dati di output sono derivati da elaborazioni statistiche (media statistica campionaria) e/o grafiche dei dati forniti dai singoli operatori. Le rappresentazioni forniscono una descrizione media complessiva, che può discostarsi, anche in modo significativo, dalla prestazione offerta al singolo utente. »
- Parts du territoire couvertes par au moins un réseau, calculées pendant la recherche : Piemonte 94,5 %, Valle d'Aosta 92,8 %, Liguria 95,9 % (non revérifiées). À lire comme une couverture théorique, surtout en montagne.
- Données de janvier 2026. Éditions mobiles repérées d'après les dates des services publics de l'AGCOM : 2016, 2019, fin 2022, janvier 2026, soit environ une tous les trois ans. Aucun texte lu n'annonce la fréquence des mises à jour.
- Carrés de 100 m découpés aux limites communales. Leurs sommets sont décalés de (54,4 ; 64,7) m par rapport à la grille de 100 m de l'EPSG:3035, pour une raison inconnue : compter une incertitude de position de l'ordre d'un carré.
- Le long des frontières, les polygones de l'AGCOM sont découpés sur des limites communales qui ne coïncident pas exactement avec le contour retenu pour l'Italie. Une frange de quelques dizaines de mètres ressort donc plus souvent « sans couverture » côté italien, sans que cela veuille dire qu'il n'y a pas de réseau (mesure dans « Ce que l'on voit le long des frontières ») : sur une crête frontalière, une zone blanche peut s'allonger de quelques dizaines de mètres.
- Voie d'accès : un service REST public au comportement non standard, qui peut changer sans préavis. Les conditions aussi : « L'Autorità si riserva il diritto di: aggiungere e/o modificare e/o rimuovere caratteristiche e dati senza preavviso; cambiare i termini e le condizioni di accesso in qualsiasi momento. » Elles sont à relire à chaque nouvelle édition. Un courriel d'information à l'AGCOM serait une bonne pratique ; c'est au propriétaire du projet de l'envoyer.

### Autres sources examinées et pourquoi elles ne sont pas retenues

- Téléchargement officiel par courriel (opendata.bbmap@agcom.it) : pas automatisable, format et délai de réponse inconnus.
- Le même jeu sur un second serveur de l'AGCOM (https://geo.agcom.it/server/rest/services/grid20/AppMobile2602/MapServer, couche 3 « 4G », 24 307 entités comme sur le premier) : pagination standard, mais le nom du service change à chaque édition. Gardé comme solution de repli.
- Couches 5G et 5G-DSS du même portail (`Grid100/mobile_5G`, `Grid100/mobile_5G_DSS`) : non lues ; la carte « internet mobile » porte sur la 4G dans tous les pays à source officielle.
- Édition précédente (fin 2022, service `Hosted/AppMobileEoY2022_v2`) : périmée.
- Anciennes couches 2G, 3G et 4G de l'AGCOM (données de 2016 et de 2019, ces dernières publiées en avril 2020), sur son hébergement ArcGIS Online : seulement des tuiles d'images, sans requête ni fichier, et des données de sept à dix ans. Les récupérer voudrait dire moissonner les tuiles d'une carte, ce que les règles du projet excluent. Non retenues.
- Service public `scoperture_reti_mobili_infratel_2021` (couche « Aree Scopertura ») : à écarter. Deux de ses couches portent dans leurs attributs : « Dati non utilizzabili per scopi diversi da quelli per cui sono stati forniti ». Réutilisation non autorisée.
- Statistiques DESI de 2020 par province, avec opérateurs anonymisés (« O1 », « O2 ») : pas une carte de couverture.
- Carte principale https://maps.agcom.it/ : en maintenance programmée les 13 et 14 novembre 2026, non consultée.
- Positions d'antennes : Ligurie, jeu régional « Impianti di Telecomunicazione » (WFS, CC BY 4.0, avec l'exploitant, mais toutes les installations sont mêlées et il n'y a pas de champ de technologie) ; Piémont, service de l'ARPA en panne et licence introuvable ; Vallée d'Aoste, rien trouvé. Aucune n'est une carte de couverture.
- Rapport Infratel « mappatura 4G e 5G » de 2021 : non lu (contenu et licence inconnus).

## Espagne

### Source

- Éditeur : Ministerio para la Transformación Digital y de la Función Pública, Secretaría de Estado de Telecomunicaciones e Infraestructuras Digitales (SETELECO). Carte « Mapa de Servicios de Banda Ancha Móvil 2024 ».
- Page du ministère : https://digital.gob.es/telecomunicaciones-infraestructuras-digitales/areas-interes/banda-ancha/informacion-cobertura/mapas-servicios-banda-ancha. Elle renvoie vers la carte https://experience.arcgis.com/experience/ef9f55c81f304e5185fcdd7cecf98e7f (ArcGIS Online, copie sur l'hébergement européen).
- Couche lue : https://services-eu1.arcgis.com/3LqdsBPalJaUFvo1/arcgis/rest/services/InfoCob4G_2024/FeatureServer/0. Polygones en ETRS89 (EPSG:4258), formés de mailles d'une grille de 0,000346111018645788°, soit environ 28 m (est-ouest) x 38,5 m (nord-sud), et découpés par commune.
- Champ `COBERTURA` : identifiants fiscaux (CIF) des opérateurs dont le réseau 4G est présent, séparés par « ; », dans un ordre quelconque. Chaîne vide : partie de la commune sans 4G. Champ `CCOM` : communauté autonome (02 Aragón, 09 Cataluña/Catalunya, 15 Comunidad Foral de Navarra, 16 País Vasco/Euskadi).
- Opérateurs, d'après la table officielle du ministère : A78923125 Telefónica Móviles España (Movistar), A82009812 Orange Espagne, A80907397 Vodafone España, A82528548 Xfera Móviles. Digi figure dans cette table comme opérateur fixe seulement : il n'apparaît pas dans les données 4G.

### Date des données

« cobertura referida a 30 de junio de 2024 » (texte de la carte). Édition 2024 : carte d'origine publiée le 4 juin 2025, copie européenne de mai 2026, avec les mêmes données. Le rapport de couverture 2025 a été présenté le 6 mai 2026, mais la carte détaillée liée depuis le site du ministère est toujours l'édition 2024 au 14 novembre 2026. Le ministère publie un rapport de couverture par an (« publica anualmente el informe sobre la cobertura de la banda ancha en España ») ; aucun calendrier de mise à jour de la carte elle-même n'a été lu.

Une nouvelle édition pourrait être publiée dans de nouveaux éléments ArcGIS, que la surveillance de la couche actuelle ne verrait pas. Le pipeline lit donc aussi la page du ministère et y relève les identifiants des éléments ArcGIS qu'elle cite. Si la page répond, en cite et ne cite plus celui de la carte lue, la détection échoue avec un message clair (nouvelle édition probable : adresses, nom et date de la source à mettre à jour dans `config.yaml`), ce qui prévient le propriétaire. Si la page ne répond pas ou ne cite aucun identifiant, c'est un simple avertissement. Pendant la construction de la release en ligne, la page a été lue sans avertissement : elle cite bien l'élément de la carte lue.

### Licence

**Aucune licence n'est attachée à la couche elle-même** : les champs de licence des éléments ArcGIS et la mention de droits des couches sont vides. Les « Términos y condiciones » affichés dans la carte ne contiennent aucune interdiction de réutilisation. `config.yaml` écrit donc : « Condiciones generales de reutilización del ministerio : source et date à citer (pas de licence propre à cette couche) ».

**La couche n'est pas dans le portail de données ouvertes du ministère.** Ce portail (https://datos-conectemos.hub.arcgis.com, « Portal de Datos Abiertos de la Secretaría de Estado de Telecomunicaciones e Infraestructuras Digitales ») ne publie, pour la couverture, que des agrégats par région et par province ; la couche 4G, la carte et la table des opérateurs ne sont partagées dans aucun groupe public. Sur datos.gob.es, une demande d'ouverture des données de connectivité mobile et d'antennes, déposée le 24 juin 2021, est à l'état « No viable ».

Ce qui va dans le sens de la réutilisation :

- Les conditions générales de réutilisation publiées dans les mentions légales du site du ministère, https://digital.gob.es/nota-legal. Mot pour mot (extraits) :

> Las presentes condiciones generales permiten la reutilización de los documentos sometidos a ellas para fines comerciales y no comerciales.

> La reutilización autorizada incluye, a modo ilustrativo, actividades como la copia, difusión, modificación, adaptación, extracción, reordenación y combinación de la información.

> Está prohibido desnaturalizar el sentido de la información.

> Debe citarse la fuente de los documentos objeto de la reutilización. Esta cita podrá realizarse de la siguiente manera: "Origen de los datos: Ministerio para la Transformación Digital y de la Función Pública"

> Debe mencionarse la fecha de la última actualización de los documentos objeto de la reutilización, siempre cuando estuviera incluida en el documento original.

> No se podrá indicar, insinuar o sugerir que el Ministerio para la Transformación Digital y de la Función Pública, titular de la información reutilizada participa, patrocina o apoya la reutilización que se lleve a cabo con ella.

- La loi générale des télécommunications, Ley 11/2022, article 48 « Estudios geográficos », paragraphe 1 (texte relu au BOE, le journal officiel espagnol) : « La información que no esté sujeta a confidencialidad comercial será accesible de conformidad con la Ley 37/2007, de 16 de noviembre, sobre reutilización de la información del sector público. »
- Le Real Decreto 1495/2011, article 8, paragraphe 1 : « La modalidad general básica para la puesta a disposición de los documentos reutilizables a que se refiere este real decreto será la puesta a disposición sin sujeción a condiciones específicas [...] aplicándose únicamente las condiciones generales establecidas en el artículo 7. » Ces conditions générales sont celles que reproduit la note légale du ministère.
- Les mentions légales du portail Conectemos du ministère : « Se prohíbe la reproducción total o parcial de los contenidos del Portal sin citar su origen o solicitar autorización. » La reproduction avec citation de l'origine y est donc admise.

Ce qui appelle la prudence :

- Ces conditions générales s'appliquent aux « documentos sometidos a ellas », sans en donner la liste. **Aucun texte ne dit que cette carte en fait partie.** Elle se présente comme publiée « dentro del sitio web de la Secretaría de Estado de Telecomunicaciones e Infraestructuras Digitales » et elle est liée depuis digital.gob.es : c'est une lecture raisonnable, pas une autorisation écrite.
- La loi 37/2007 sur la réutilisation exclut « Los documentos sobre los que existan derechos de propiedad intelectual o industrial por parte de terceros ». Les données viennent des opérateurs : rien de lu ne dit si cette exclusion s'applique.
- Le ministère sait attacher une condition à un jeu : un élément de son portail ouvert porte la mention « No autorizado su uso comercial. » La couche 4G n'en porte aucune, ni dans un sens ni dans l'autre.
- Les conditions générales d'Esri pour ArcGIS Online, qui héberge la couche, n'ont pas été lues (non vérifié).

La release publique diffuse en plus la copie de travail `cache-es_mtd.tif`, qui donne la présence 4G de chaque opérateur à la maille de la source (voir « Méthode »).

Décision laissée au propriétaire du projet : garder la source officielle sur cette base, écrire au ministère (son portail ouvert nomme la « S.G. de Operadores de Telecomunicaciones e Infraestructuras Digitales ») pour demander si la couche `InfoCob4G_2024` relève des conditions générales de réutilisation, ou passer l'Espagne en « estimée ».

### Mention affichée dans le site

- Pied de carte : « Couverture : Origen de los datos: Ministerio para la Transformación Digital y de la Función Pública ».
- Panneau « Sources » : nom de la source avec un lien vers la page du ministère ; date des données (juin 2024) ; licence « Condiciones generales de reutilización del ministerio : source et date à citer (pas de licence propre à cette couche) » avec un lien vers les mentions légales ; note « couvert ou non couvert » ; mention du contour du pays ; opérateurs.

### Méthode

Module `pipeline/czb/sources/es_mtd.py`.

1. Le pipeline vérifie d'abord le schéma de la couche (champs `OBJECTID`, `COBERTURA`, `CCOM`, système EPSG:4258). Un changement arrête la construction.
2. Détection d'une nouvelle édition : nom de la couche, date de dernière modification des données, date de modification de l'élément ArcGIS, nombre de polygones de chaque région (et la page du ministère, voir « Date des données »).
3. **Copie de travail.** Les quatre régions comptent environ 2,1 millions de polygones, soit un bon millier de requêtes. Le résultat est donc gardé sous forme d'image à la maille d'origine, avec un bit par opérateur : le fichier `cache-es_mtd.tif`, publié avec les données dans la release (mécanisme commun : `pipeline/czb/cache.py`). Tant que l'édition en ligne, l'emprise et la liste des opérateurs ne changent pas, la construction suivante repart de cette image sans relire le service.
4. Sinon, lecture région par région (CCOM 02, 09, 15, 16), polygones dont `COBERTURA` n'est pas vide, 2 000 par page, par `OBJECTID` croissant, l'une après l'autre avec une pause d'une demi-seconde. Le nombre lu doit égaler le nombre annoncé. Un identifiant d'opérateur inconnu arrête la construction. Les polygones sans commune (CCOM vide : mer, versants français et andorran) ne sont pas lus.
5. Les polygones sont rastérisés sur la grille d'origine de la source, un passage par opérateur. Cette grille a le pas de l'image tuilée du ministère (0,000346111018645788°), dont le coin nord-ouest sert de point de référence, mais elle est décalée d'une fraction de maille. Le module mesure ce décalage sur les sommets des polygones à chaque lecture. Il s'arrête si les sommets ne dessinent plus une grille au pas annoncé, ou si deux régions n'ont pas le même calage. La copie de travail garde son calage exact.
6. Contrôle : pour chaque région, 1 200 points sont tirés au hasard, la moitié dans des mailles couvertes. Là où la copie de travail ou les polygones trouvent un réseau, les deux sont comparés, avec 3 % d'écart toléré. Les mailles coupées par une limite de commune ne sont pas des carrés entiers : sur les données réelles, 0,7 % des points tombent dans un tel éclat (mesure notée dans le module) ; une erreur de calage en donnerait bien plus. Au-delà de la tolérance, la construction s'arrête.
7. Pour chaque opérateur, l'image est ramenée sur la grille du projet en plus proche voisin. « Présent » donne le niveau 2 (« couvert »), sinon 0.
8. Points témoins : niveau lu dans la grille d'origine, 60 par opérateur.

Dernière lecture complète du service, faite le 14 novembre 2026 pour la release `data-2026-11-14-3` : 2 107 325 polygones (Aragón 1 106 848, Cataluña 711 116, Navarra 167 793, País Vasco 121 568), 1 496,8 s ; décalage mesuré de 0,3509 maille en longitude et 0,4893 en latitude, le même dans les quatre régions ; contrôle contre les polygones : 13 écarts sur 887 points couverts comparés (Aragón), 7 sur 856 (Cataluña), 8 sur 828 (Navarra), 7 sur 868 (País Vasco). Les releases suivantes, dont celle en ligne, repartent de la copie de travail issue de cette lecture.

Construction de la release en ligne (`data-2026-11-14`) : « édition inchangée : copie de travail reprise (cache-es_mtd.tif, 19712 x 10752 mailles) », 165,5 s au lieu de 1 496,8 s ; présence sur les mailles du rectangle de calcul, qui englobe les quatre régions (d'où des parts plus basses que les parts de surface citées plus bas) : Movistar 33,5 %, Orange 30,8 %, Vodafone 29,2 %, Xfera Móviles 4,0 % ; 120 410 608 pixels pour l'Espagne ; 240 points témoins sans écart. La copie de travail publiée pèse 7,3 Mo.

### Limites

- Source binaire : la présence est un seuil de signal, sans niveau de qualité. Méthodologie du ministère : « Los cálculos de cobertura se basarán en una probabilidad de 95 % del tiempo y de las ubicaciones. En el caso de redes móviles, se empleará una carga nominal de la celda del 60 %. » et « 1. Presencia, entendida como la zona donde: a. Frecuencias < 1 GHz RSRP >= -115 dBm b. Frecuencias > 1 GHz RSRP >= -117 dBm La capa englobará todas las tecnologías 4G sin distinguir entre ellas. » (méthodologie 2025 ; la méthodologie 2024, un PDF en images lu par reconnaissance de caractères pendant l'enquête, contiendrait le même passage : non revérifié). Pas comparable aux quatre niveaux de l'Arcep. « Bonne couverture » veut dire « couvert ».
- Données au 30 juin 2024 : plus de deux ans à la date de rédaction.
- Couverture théorique déclarée par les opérateurs. Conditions de la carte : « Los datos representados se procesan a partir de los proporcionados por los operadores de telecomunicaciones individuales, llevándose a cabo para cierta información una descripción media, que puede diferir, incluso significativamente, del servicio ofrecido al usuario individual. »
- Sens du champ opérateur : la carte parle des opérateurs « cuya infraestructura presta servicio » ; la page du ministère dit qu'elle inclut aussi des opérateurs servis par des accords de partage. Xfera ne couvre que 9,7 % de la surface des quatre régions (Telefónica 80,5 %, Orange 74,0 %, Vodafone 70,2 %), ce qui ressemble plutôt à son réseau propre. La vue « Tous opérateurs » est donc la plus fiable. La vue par opérateur peut sous-estimer la couverture des clients de marques hébergées.
- Digi et les opérateurs virtuels n'ont pas de couche propre.
- Ni 2G ni 3G : pas d'appels et SMS pour l'Espagne.
- Hébergement ArcGIS Online : les identifiants ont déjà changé une fois (copie de mai 2026). Des couches d'essai « 2026 » existent sur le même compte ; elles ne sont pas liées depuis le site du ministère et ne sont pas utilisées.
- Le long de la frontière, une frange de 1 à 3 pixels ressort plus souvent « sans couverture » côté espagnol, parce que les mailles coupées par la limite n'arrivent pas exactement au contour (voir « Ce que l'on voit le long des frontières »).

### Autres sources examinées et pourquoi elles ne sont pas retenues

- Image tuilée du même ministère (`Cob4G_2024`) : présence d'au moins un réseau 4G, tous opérateurs confondus, moins riche que la couche par opérateur. Les deux hôtes de ces images (tiledimageservices-eu1.arcgis.com et tiledimageservices9.arcgis.com) interdisent tous les programmes automatiques dans leur fichier robots.txt, qui donne aux robots les consignes d'un site : « User-agent: * Disallow: / ». Le pipeline ne les lit pas. Pendant l'enquête, une dizaine de tuiles y ont pourtant été lues avant que ce fichier soit consulté : aucun chiffre qui en vient n'est retenu ici. Le pipeline reprend seulement le pas et le coin de la grille de cette image, lus pendant l'enquête dans la description du service ; le pas est confirmé par l'écart entre les sommets des polygones de la couche d'entités. La vue « Tous opérateurs » se calcule à partir de la couche par opérateur.
- datos.gob.es, base historique de couverture fixe et mobile du ministère : tableaux par commune, pas une carte.
- Portail Conectemos du ministère : agrégats par commune de 2021 à 2025 (XLSX), pas une carte.
- Aragón Open Data, « Cobertura móvil real por tecnología en Aragón » (CC BY 4.0, dernier jeu : juin 2026) : mesures réelles par mailles de 500 m, seulement là où les réseaux sont utilisés, tous opérateurs confondus, Aragon seul. Pas une carte de couverture ; complément possible.
- Catalunya, « Cobertura mòbil 112 » (GeoTIFF de 30 m, Llicència oberta d'ús d'informació - Catalunya) : Catalogne seule, fiche de 2022, valeurs 0 à 5 non documentées.
- Catalunya, données de l'application « Cobertura Mòbil » (2015 à 2019) : mesures ponctuelles, trop anciennes.
- Navarra, « Observatorio de Banda Ancha » : haut débit fixe seulement.
- Euskadi : rien trouvé dans le catalogue national.
- « Infoantenas » (stations radio, ministère) : service de consultation, pas un jeu de données, sans mention de réutilisation. Non moissonné : pas de scraping.

## Andorre

### Source

- **Aucune source officielle exploitable : la couverture est estimée** (voir « Estimation »).
- Codes réseau : le MCC (indicatif de pays mobile) de l'Andorre est 213, vérifié dans la liste des indicatifs de l'UIT (annexe au Bulletin d'exploitation n° 1117, position au 1er février 2017). Un seul MNC (code de réseau) existe sous ce MCC : « 213 03 Mobiland » (liste de l'UIT, position au 15 novembre 2023). Aucune source lue ne relie « Mobiland » à un opérateur nommé : le site et le manifest ne nomment donc aucun opérateur pour l'Andorre. Le pipeline range toutes les cellules du MCC 213 dans un seul emplacement, tous réseaux du pays confondus.
- Cellules d'OpenCellID : la page de statistiques (toute la base, lue le 14 novembre 2026) annonce 1 249 cellules, dont 344 en 4G (LTE) et 11 en 5G (NR). Le fichier téléchargé, qui ne garde que les cellules vues dans les 18 derniers mois, en contient 111 : 65 GSM, 41 LTE, 5 UMTS, aucune 5G.

### Date des données

Novembre 2026 : le mois du calcul, avec les cellules vues par OpenCellID dans les 18 derniers mois.

### Licence

Zones estimées sous CC BY-SA 4.0 (elles dérivent d'OpenCellID), avec la mention obligatoire de Copernicus. Détail et citations dans « Estimation ».

### Mention affichée dans le site

Valable aussi pour Monaco :

- Pied de carte : quand une zone estimée est à l'écran, le crédit qu'OpenCellID demande à côté de la carte, avec ses liens : « Cell tower data from OpenCellID, licensed under CC BY-SA 4.0 ». La mention complète, relief Copernicus compris, est dans le panneau « Sources ».
- Panneau « Sources » : « Estimation : antennes OpenCellID et relief Copernicus DEM », avec un lien vers https://opencellid.org ; date des données ; méthode « Estimée » ; licence « CC BY-SA 4.0 (zones estimées, dérivées d'OpenCellID) » avec un lien vers https://creativecommons.org/licenses/by-sa/4.0/ ; la mention en anglais d'OpenCellID et de Copernicus, en entier (voir « Estimation ») ; le texte sur les zones estimées cité ci-dessous ; la mention du contour du pays ; l'avertissement d'itinérance (l'Andorre et Monaco ne font pas partie de l'itinérance de l'Union européenne).
- Rapport en texte : la ligne « Sources » reprend la mention du manifest, avec le pays et la date.
- Quand le manifest donne le nombre de sites d'antennes connus (champ `estimation`), le panneau « Sources » l'affiche, avec une phrase qui dit que moins il y a de sites, moins l'estimation est fiable. **Le manifest en ligne ne le donne pas encore** : le panneau ne montre donc pas aujourd'hui ces nombres (12 sites en Andorre, 18 à Monaco). Voir « Estimation ».
- Dans le pied de carte et dans la ligne « Sources » du rapport, le site fait précéder la mention d'une source estimée du mot « estimation », dans la langue choisie. La mention du manifest (« OpenCellID (CC BY-SA 4.0), Copernicus DEM ») ne contient plus de mot français.
- Si un pays manque dans les données publiées (par exemple faute de clé OpenCellID), le panneau le signale.

Texte affiché dans le panneau « Sources » pour les zones estimées :

> Faute de carte officielle, la couverture est calculée à partir de positions d'antennes relevées par des bénévoles (OpenCellID) et du relief. Ce n'est pas une carte d'opérateur : une antenne absente de la base crée une fausse zone blanche, une antenne mal placée déplace les limites de plusieurs centaines de mètres. Ne comptez pas sur une zone estimée pour un appel d'urgence.

### Méthode

Celle de « Estimation », avec le fichier OpenCellID du MCC 213.

### Limites

- Estimation, pas une carte d'opérateur (voir « Estimation »).
- **Estimation très pessimiste.** Les 12 sites 4G connus d'OpenCellID sont tous autour d'Andorre-la-Vieille. 85,2 % du pays ressort « pas de couverture ». Tout le nord et l'est du pays sont sans couverture sur la carte : vallées d'Encamp et de Canillo, Soldeu, le Pas de la Case, Ordino, mais aussi La Massana et Arinsal (niveaux relus dans les tuiles publiées). C'est très probablement faux : la base d'antennes est trop pauvre. L'erreur va du côté prudent, mais elle crée de fausses zones blanches sur des villages habités. Le propriétaire a trois choix : garder, masquer l'Andorre, ou enrichir l'estimation avec les cellules 2G et 3G d'OpenCellID (non essayé).
- Hors itinérance de l'Union européenne : le rapport avertit quand le tracé passe en Andorre.

### Autres sources examinées et pourquoi elles ne sont pas retenues

- Govern d'Andorra : pas de portail de données ouvertes (https://www.govern.ad/dades-obertes répond 404, aucun lien vers des données ouvertes, les télécommunications ou la couverture dans le portail) ; le portail de transparence (https://www.transparencia.ad/) n'a aucun lien vers des données ouvertes, des statistiques ou les télécommunications ; dadesobertes.ad ne répond pas, et opendata.ad ne montre qu'une page d'attente de bureau d'enregistrement, sans données.
- IDE Andorra, infrastructure de données spatiales du Govern : 835 fiches de métadonnées et 960 couches WMS passées en revue, sans couverture mobile, sans réseau de télécommunications, sans registre d'antennes. Ses contenus sont de plus sous tous droits réservés (avis légal cité ci-dessous).
- Carte de couverture d'Andorra Telecom : site d'opérateur, exclu par les règles du projet (pas de scraping).
- Carte espagnole : elle contient des polygones sur les versants andorrans (entités sans commune), volontairement non lus. C'est la couverture des réseaux espagnols, pas celle des réseaux andorrans.

Avis légal de l'IDE Andorra (https://www.cartografia.ad/avis-legal), mot pour mot :

> No es podran fer actes totals o parcials de reproducció, publicació, tractament informàtic, distribució, difusió, transformació, compilació, modificació, distribució o comunicació pública dels webs sense el consentiment previ i per escrit del Govern .

## Monaco

### Source

- **Aucune source officielle de couverture : la couverture est estimée** (voir « Estimation »).
- Codes réseau : le MCC de Monaco est 212 (même liste de l'UIT que pour l'Andorre). « 212 10 Monaco Telecom » est le seul code sous ce MCC (liste de l'UIT, position au 15 novembre 2023). La rubrique « Monaco » de l'UIT cite aussi trois codes français utilisés à Monaco : 208 01 (Orange/Monaco Télécom), 208 10 (SFR), 208 20 (Bouygues Telecom).
- Le pipeline ne lit que le MCC 212 : l'estimation ne repose donc que sur les cellules de Monaco Telecom. Les réseaux français présents ou captés à Monaco ne sont pas pris en compte, et la vue « Tous opérateurs du pays » n'est, à Monaco, que celle de Monaco Telecom.
- Cellules d'OpenCellID : la page de statistiques (toute la base) annonce 381 cellules, dont 55 en 4G et aucune en 5G. Le fichier du MCC 212 téléchargé le 14 novembre 2026 en contient pourtant 1 813 : 16 GSM, 1 436 LTE, 361 UMTS, aucune 5G. La page de statistiques ne compte donc pas comme le fichier ; pourquoi, non vérifié.

### Date des données, licence, mention, méthode

Comme pour l'Andorre, avec le fichier OpenCellID du MCC 212.

### Limites

- Estimation tirée de 18 sites, qui donne 100 % du pays en « bonne couverture ».
- Monaco Telecom seulement (voir plus haut). Le code 10 existe sous les deux MCC (212 10 Monaco Telecom, 208 10 SFR) : distinguer un jour les opérateurs demanderait de regrouper par paire (MCC, MNC).
- Hors itinérance de l'Union européenne.
- Contour : terre ferme seulement (voir « Contours des pays »).

### Autres sources examinées et pourquoi elles ne sont pas retenues

- cartoradio.mc (site du Gouvernement Princier) : couche officielle « Sites Radioélectriques » (opérateur, orientation des secteurs, technologies 2G à 5G), lisible sans clé d'accès, mais sans aucune licence (champs vides) et sans mentions légales. Les conditions du portail du Gouvernement (https://www.gouv.mc/mentions-legales-cgu, citées ci-dessous) interdisent toute réutilisation sans autorisation expresse. Elles visent le portail gouv.mc ; cartoradio.mc n'en a pas de propres. Sur le même géoportail, quand le Gouvernement remplit le champ de licence d'une couche publique, il écrit par exemple « Réutilisation extérieure : soumise à autorisation du Gouvernement Princier ». Lecture prudente : pas de licence, donc pas de droit de réutilisation. Cette couche ferait une bien meilleure base d'estimation qu'OpenCellID, mais il faudrait une autorisation écrite de l'administration monégasque.
- data.gouv.mc : en maintenance (erreur 503, « Site en maintenance ») à chaque essai du 14 novembre 2026, de 10 h 47 à 13 h 25 UTC. Le nom a son propre enregistrement DNS, et un résultat de moteur de recherche le présente comme un catalogue de données (« Data Monaco - Home ») : c'est une piste, pas une preuve. Son catalogue et sa licence n'ont pas pu être lus (non vérifié). **Pour Monaco, le verdict « pas de source officielle » reste donc provisoire.**
- Carte de couverture de Monaco Telecom : site d'opérateur, exclu.

Conditions générales du portail du Gouvernement Princier, mot pour mot :

> Toute forme d’utilisation, de représentation, de transformation, de reproduction, d’adaptation ou de diffusion, intégrale ou partielle, de tout élément ou du contenu de ce Site sur quelque support et par quelque procédé que soit est prohibée, à défaut d’autorisation expresse de l’Administration et constitue une infraction pénalement sanctionnée par les Cours et Tribunaux monégasques.

## Estimation (Andorre, Monaco)

Là où aucune source officielle n'est exploitable, la couverture est estimée à partir des positions de cellules d'OpenCellID et du relief Copernicus DEM GLO-30. Module `pipeline/czb/sources/estimation_opencellid.py`, réglages dans le bloc `estimation` de `config.yaml`. La clé gratuite d'OpenCellID est le secret `OPENCELLID_TOKEN` du dépôt ; sans elle, le pipeline laisse l'Andorre et Monaco de côté et le manifest les signale comme manquants. Ces zones sont marquées « estimées » partout : hachures sur la carte et dans le profil altimétrique, pointillé sur le tracé, mention dans le rapport et dans le GPX enrichi, type de source 2 dans les tuiles.

### Résultats de l'estimation en ligne

L'estimation en ligne a été calculée le 14 novembre 2026, pendant la construction de la release `data-2026-11-14-4`. La construction de la release en ligne, `data-2026-11-14`, a repris telle quelle la copie de travail du mois, sans rien télécharger chez OpenCellID : mêmes parts par niveau, mêmes pixels, et 60 points témoins sans écart pour chaque pays. Chiffres du rapport et du journal de la construction de `data-2026-11-14-4` :

| | Andorre (MCC 213) | Monaco (MCC 212) |
|---|---|---|
| Cellules dans le fichier d'OpenCellID | 111 (GSM 65, LTE 41, UMTS 5) | 1 813 (GSM 16, LTE 1 436, UMTS 361) |
| Cellules 4G retenues, dans le pays élargi de 2 km | 41, toutes du code réseau 3 | 1 433, toutes du code réseau 10 |
| Cellules 5G | aucune | aucune |
| Mesures par cellule retenue (1er décile, médiane, 9e décile) | 2, 6, 15 | 2, 12, 25 |
| Stations (cellules regroupées) | 12, aucune trop dispersée | 109, dont 1 trop dispersée |
| Dispersion d'une station : plus grand écart d'une cellule à la position retenue (médiane des stations, maximum) | 625 m, 1 826 m | 440 m, 2 189 m |
| Sites | 12 | 18 |
| Part du pays par niveau estimé | pas de couverture 85,2 %, limitée 5,6 %, bonne 9,2 % | bonne 100 % |
| Pixels du pays | 586 881 | 2 716 |
| Relief | 1 dalle Copernicus (N42 E001) | 1 dalle Copernicus (N43 E007) |
| Calcul | 4,4 s | 3,5 s |
| Points témoins | 60, sans écart | 60, sans écart |

- Le téléchargement réel d'OpenCellID fonctionne depuis la création du secret, le 14 novembre 2026 (un essai limité à l'Andorre et à Monaco à 13 h 44 UTC, puis la construction de `data-2026-11-14-4`) : le lien de chaque fichier est bien trouvé dans la page des téléchargements après l'envoi de la clé, et les fichiers `213.csv.gz` et `212.csv.gz` ont une ligne d'en-tête conforme aux colonnes documentées.
- Aucune cellule 5G (« NR ») dans les deux fichiers : l'estimation repose en pratique sur la 4G.
- Les cellules d'une même station sont loin de leur position médiane (plusieurs centaines de mètres pour une station sur deux) : soit les positions estimées sont imprécises, soit la règle de regroupement ne convient pas. Ce n'est pas tranché.
- Andorre : 12 sites, c'est très peu. L'estimation y sous-estime sans doute beaucoup la couverture (voir « Andorre », « Limites »).
- OpenCellID n'autorise que deux téléchargements par jour et par fichier. La copie de travail du mois, publiée avec la release, évite de retélécharger lors des constructions suivantes du même mois.
- Le pipeline écrit dans le manifest, pour chaque source estimée, le nombre de sites et de cellules utilisés, sous la forme `"estimation": {"sites": 12, "cells": 41}` pour l'Andorre. Il garde aussi ces nombres dans la copie de travail, pour les constructions suivantes du même mois. **Le manifest en ligne n'a pas encore ce champ** : la copie de travail reprise pour `data-2026-11-14` a été faite avant cet ajout. Il apparaîtra au prochain recalcul de l'estimation : à la première construction d'un mois suivant, si le téléchargement chez OpenCellID réussit.

### OpenCellID

- Base ouverte de positions de cellules, alimentée par des mesures de bénévoles : https://opencellid.org. Des fichiers par pays sont proposés (« We provide country files, a full dataset and daily change files. »). Format documenté (https://docs.opencellid.org/docs/downloads/database-format) : CSV compressé de 14 colonnes, radio, mcc, net, area, cell, unit, lon, lat, range, samples, changeable, created, updated, averageSignal. Le module lit un fichier par MCC : `213.csv.gz` pour l'Andorre, `212.csv.gz` pour Monaco.
- Ce ne sont pas des positions de pylônes : « The coordinates are estimated cell positions calculated from contributed observations. They are not surveyed mast coordinates or a device's live GPS position. Estimates can differ from the physical antenna site, especially where observations are sparse or concentrated along a road. »
- Cellules et sites : « One physical site can serve several cells, sectors and radio technologies. Several rows at nearby or identical coordinates can therefore be valid. Do not count rows as physical towers or remove records solely because their coordinates match. »
- La base est incomplète : « A download is not a complete inventory of all cells. » et « A missing record does not mean the cell does not exist or that the area has no mobile signal. »
- Exports et quota : « We generate exports daily by 02:00 GMT. They include towers observed in the last 18 months. You can download each file twice per day from our download page. »
- Pourquoi un fichier par pays et pas l'interface de requêtes : « /cell/getInArea returns at most 50 cells per request. », sur une emprise de 4 km² au plus (« The maximum bounding-box area is 4,000,000 square meters (4 km²). »), et la documentation conseille : « For a city, region or country, download the dataset and filter by coordinates ».

Licence, mot pour mot (https://docs.opencellid.org/docs/attribution) :

> OpenCellID data is licensed under CC BY-SA 4.0, including API results, dataset downloads and daily changes.

Encadré « Attribution required » :

> When sharing OpenCellID data under CC BY-SA 4.0, credit OpenCelliD, link to the source and license, and indicate any changes.

Sur la même page, à propos des modifications :

> If you modify the data, add a description alongside the credit, such as “Changes: coordinates rounded to two decimal places.” Retain supplied notices.

Rubrique « Where to place the credit » :

> Make the credit visible where users encounter the data, helping them discover OpenCellID and contribute back.

Dans le tableau qui suit (colonnes « Use » et « Placement »), la ligne « Website or map » dit : « On the page displaying the data, beside the map or visualization. »

Rubrique « Other license terms » :

> When sharing adapted material, follow the license's ShareAlike requirements. Retain supplied copyright, license and warranty notices, and do not restrict recipients' licensed rights. See the full license terms, including its database provisions.

Page des téléchargements (https://opencellid.org/downloads.php) : « Products or services using data derived from OpenCelliD need to visibly credit OpenCelliD. » La documentation des fichiers (https://docs.opencellid.org/docs/downloads/daily-changes) ajoute : « Full exports, country exports and daily change files use the same CC BY-SA 4.0 license. »

- **Partage à l'identique.** La licence CC BY-SA 4.0 (section 3(b)) impose que le matériel adapté soit diffusé sous une licence aux mêmes éléments : « The Adapter's License You apply must be a Creative Commons license with the same License Elements, this version or later, or a BY-SA Compatible License. » Les zones estimées publiées (tuiles de l'Andorre et de Monaco, copies de travail) sont donc sous CC BY-SA 4.0 : https://creativecommons.org/licenses/by-sa/4.0/. Les autres sources gardent leur propre licence : le manifest porte une licence par source. C'est l'analyse du projet, pas un avis juridique, et le choix de publier ces zones sous CC BY-SA 4.0 revient au propriétaire du projet.
- Modifications apportées aux données d'OpenCellID, comme la licence demande de l'indiquer : seules les cellules 4G et 5G sont retenues ; elles sont regroupées par site ; la couverture est calculée par visibilité sur le relief ; seules les zones estimées sont publiées, pas les positions des cellules. Dans le panneau « Sources », le crédit est suivi du texte sur les zones estimées, qui décrit la méthode dans ses grandes lignes ; le détail des modifications est dans ce document.
- Mention complète, affichée dans le panneau « Sources » et écrite dans `SOURCES.md` (texte de `config.yaml`) : « Cell tower data from OpenCellID, licensed under CC BY-SA 4.0. Produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30. » Pied de carte : le crédit court d'OpenCellID, avec ses liens (voir « Andorre », « Mention affichée dans le site »).

Téléchargement : la page https://opencellid.org/downloads.php ne montre ses liens qu'après l'envoi de la clé, et la forme exacte de ces liens n'est pas documentée publiquement. Le module envoie donc la clé à cette page dans le corps de la requête (pas dans l'adresse de la page), puis suit le lien qui contient « 213.csv.gz » ou « 212.csv.gz ». Si ce lien contient lui-même la clé, elle reste masquée dans les journaux. Le module vérifie ensuite que la réponse est bien un fichier compressé : sans clé valide, le service répond quand même « 200 » avec un message d'erreur.

### Copernicus DEM GLO-30

- Modèle numérique de surface (une grille d'altitudes, bâtiments et végétation compris), au pas d'une seconde d'arc (environ 30 m), version 2021, référence verticale EGM2008. Tuiles d'un degré, en accès libre sans compte dans le dépôt public `copernicus-dem-30m`, par exemple https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N45_00_E006_00_DEM/Copernicus_DSM_COG_10_N45_00_E006_00_DEM.tif (gabarit `dem_url` dans `config.yaml`). Pas de tuile en mer : l'altitude y vaut 0.
- Licence : « Licence for Copernicus DEM instance COP-DEM-GLO-30-F Global 30m Full, Free & Open » (https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf, copie livrée avec chaque tuile). Mot pour mot :

> The Licensor grants to the User the following non-exclusive rights of use regarding the Copernicus WorldDEM-30: (a) reproduction; (b) distribution; (c) communication to the General Public; (d) adaptation, modification and combination with other data and information.

> The use rights granted under this licence are free of charge to the User.

- Mention obligatoire pour des données adaptées (article 6 (b)) et phrase exigée par l'article 6 (c). Elles suivent les données redistribuées : le manifest, `SOURCES.md` et le panneau « Sources » les portent.

> produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved

> The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30

- Seule la phrase de l'article 6 (c) peut être traduite (« The following sentence or its translation in any language shall be added [...] ») : la mention de l'article 6 (b) reste en anglais, mot pour mot, dans les cinq langues.
- Article 6 (e) : qui permet à d'autres de rediffuser ces données, modifiées ou non, doit les lier aux mêmes obligations : « Where the user grants to any Subsequent User the rights to distribute or communicate to the General Public the Copernicus WorldDEM-30, modified or not, he shall ensure that its Subsequent Users are bound by the above obligations. »
- L'estimation ne redistribue pas le relief, seulement un résultat calculé avec lui. Les GPX de test, eux, portent des altitudes tirées du relief (voir « Tracés GPX de test »). Le projet ne doit pas laisser croire qu'il est approuvé par le fournisseur ou par Copernicus (article 6 (d)).

### Méthode en clair

1. **Cellules.** Le pipeline lit le fichier OpenCellID du pays (MCC 213 pour l'Andorre, 212 pour Monaco). Il garde les cellules 4G (LTE) et 5G (NR) situées dans l'emprise du pays élargie de 2 km, car un fichier de pays peut contenir des cellules voisines.
2. **Regroupement par site.** Les cellules 4G d'une même station (même code réseau, même identifiant de cellule divisé par 256) sont réunies à la médiane de leurs positions : les secteurs entourent le pylône. Si elles sont dispersées sur plus de 2 km, elles sont traitées une à une. Ensuite, les points à moins de 300 m les uns des autres forment un seul site. Une cellule 5G rejoint le site situé à moins de 300 m, ou forme le sien. Toutes les cellules du pays vont dans un seul emplacement : pas de distinction par opérateur. Ce regroupement par division de l'identifiant par 256 suit la numérotation des réseaux 4G ; qu'il convienne aux données d'OpenCellID n'est pas vérifié (voir les écarts mesurés plus haut).
3. **Relief.** Les tuiles Copernicus sont ramenées sur la grille du projet (interpolation bilinéaire), la mer à 0.
4. **Visibilité.** Pour chaque site, le calcul de visibilité de GDAL (`ViewshedGenerate`) donne, pour chaque pixel, la hauteur au-dessus du sol qu'il faudrait pour voir l'antenne. Réglages : antenne à 30 m, téléphone à 1,5 m, coefficient de courbure et de réfraction 0,75, portée 15 km. On en tire trois distances par pixel : au site visible le plus proche, au site « presque visible » le plus proche (il manque au plus 30 m de hauteur pour le voir) et au site le plus proche, visible ou non.
5. **Règle à trois niveaux.**
   - « bonne » (niveau 2) : un site visible à 5 km au plus, ou presque visible à 1 km au plus, ou un site à 500 m au plus ;
   - sinon « limitée » (niveau 1) : un site visible à 15 km au plus, ou presque visible à 7,5 km au plus, ou un site à 2 km au plus ;
   - sinon « pas de couverture » (niveau 0).
   - Jamais « très bonne » : l'estimation ne sait pas faire cette distinction (voir le calage).
6. **Copie de travail.** Le résultat est gardé (`cache-ad_estimation.tif`, `cache-mc_estimation.tif`) et repris pendant le mois en cours, car OpenCellID limite chaque fichier à deux téléchargements par jour. Si le téléchargement échoue, l'estimation d'un mois précédent est reprise. L'estimation ne déclenche pas de reconstruction à elle seule : elle est rafraîchie quand une autre source change, au plus une fois par mois.
7. **Points témoins.** Niveau lu dans le tableau de l'estimation, comparé aux pixels publiés.

### Calage sur la France

But : mesurer ce que vaut la méthode là où la vérité officielle existe, avant de l'appliquer à l'aveugle. Les positions officielles des sites de l'Arcep (https://data.arcep.fr/mobile/sites/last/2026_T2_sites_Metropole.csv, Licence Ouverte) ont été passées dans le même calcul de visibilité, puis comparées à la couverture 4G de l'Arcep (2e trimestre 2026). Trois cas : Hautes-Alpes Orange (533 sites), Ariège Orange (683 sites), Hautes-Alpes SFR (525 sites). En tout 21,7 millions de pixels, dont 25,4 % de zones blanches selon l'Arcep. Aucune donnée OpenCellID n'a servi : ses défauts ont été simulés (positions déplacées au hasard, sites retirés au hasard).

- **Couvert ou non : le relief apporte beaucoup.** Avec des positions exactes, la règle « visibilité et distance » classe juste 87 à 90 % des pixels, contre 72,6 % pour la distance seule et 74,6 % si l'on déclare tout couvert.
- **Quatre niveaux : hors de portée.** Le meilleur accord obtenu avec les quatre niveaux de l'Arcep est de 59,1 %. D'où trois niveaux seulement.
- **Règle retenue, selon la qualité des positions :**

| Données d'entrée | Zone annoncée « bonne » réellement couverte | Zone annoncée « limitée » réellement couverte | Zone annoncée « pas de couverture » réellement blanche | Vraies zones blanches annoncées « pas de couverture » |
|---|---|---|---|---|
| Positions exactes | 98,5 % | 83,0 % | 81,4 % | 77,1 % |
| Positions fausses de 500 m | 97,1 % | 84,8 % | 67,8 % | 76,2 % |
| 500 m d'erreur et 30 % de sites manquants | 97,2 % | 88,7 % | 53,0 % | 82,6 % |
| 1 000 m d'erreur et 50 % de sites manquants | 95,4 % | 88,1 % | 44,8 % | 81,2 % |

Ce qui est fiable : une zone estimée « bonne » est couverte au moins 95 fois sur 100 dans tous les cas essayés.

Ce qui ne l'est pas : une zone estimée « pas de couverture » n'est vraiment blanche qu'environ 8 fois sur 10 avec des positions exactes, et environ une fois sur deux avec des données dégradées. Des données incomplètes fabriquent surtout de **fausses zones blanches**. « Limitée » veut dire « incertain ». Avec des positions exactes, sur 100 vraies zones blanches, 77 sont affichées en rouge, 20 en orange et 3 ne sont pas signalées.

Ce que le calage ne dit pas : il porte sur la France, deux départements et deux opérateurs ; la « vérité » est elle-même une simulation d'opérateur ; il utilise des positions de sites, alors qu'OpenCellID donne des positions de cellules estimées ; les vraies erreurs d'OpenCellID sont inconnues, et probablement biaisées vers les routes et les vallées, où passent les contributeurs. La qualité réelle avec de vraies données OpenCellID n'est donc pas connue. Les notes de recherche proposent une auto-évaluation à chaque construction (la même chaîne appliquée aux cellules françaises d'OpenCellID sur un département frontalier, puis comparée à l'Arcep) : elle n'est pas en place.

### Limites à annoncer

- Ce n'est pas une carte d'opérateur. Une antenne absente de la base crée une fausse zone blanche ; une antenne mal placée déplace les limites de plusieurs centaines de mètres.
- Ni la puissance, ni l'orientation des antennes, ni la végétation fine, ni l'intérieur des bâtiments ne sont pris en compte. Le relief est un modèle de surface : forêts et bâtiments masquent un peu plus que le sol nu (effet non mesuré).
- Très peu de sites : 12 en Andorre, 18 à Monaco, et aucune cellule 5G dans les fichiers. En Andorre, l'estimation est très pessimiste (voir « Andorre », « Limites »).
- Aucun contrôle de vraisemblance ne signale une estimation trop pauvre. Seul le nombre de sites en donne une idée : ce document le donne ; le panneau « Sources » l'affichera quand le manifest le portera.
- Trois niveaux seulement. Internet mobile seulement : les appels et SMS ne sont pas estimés.
- La date affichée est le mois de la construction ; les cellules sont celles vues dans les 18 derniers mois.
- Ne pas compter sur une zone estimée pour un appel d'urgence.

## Contours des pays

Chaque pays a un contour, qui dit quels pixels lui appartiennent. Module `pipeline/czb/masks.py`, adresses dans `config.yaml`. Chaque fichier de contour téléchargé est supprimé dès que ses géométries sont lues (sauf réglage `delete_after: false`, prévu pour la mise au point).

### Une source par pays

- **France** : jeu « Contours administratifs » de data.gouv.fr (organisation « data.gouv.fr », page https://www.data.gouv.fr/datasets/contours-administratifs), fichier des départements lu sur https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/departements-5m.geojson.gz. Ce serveur garde un dossier par millésime (2018, 2019, puis 2021 à 2026) et un dossier `latest` ; les ressources listées par data.gouv.fr pointent, elles, vers contours-administratifs.s3.rbx.io.cloud.ovh.net. Départements dont le code a deux caractères : métropole et Corse, 96 départements. Le lisez-moi du projet etalab/contours-administratifs dit « Départements (calculés à partir de ADMIN EXPRESS) ». Licence : data.gouv.fr déclare le jeu sous l'identifiant `odc-odbl` (Open Data Commons Open Database License, ODbL). Mention, dans `config.yaml` et dans le site : « Contours administratifs, data.gouv.fr (licence ODbL), d'après ADMIN EXPRESS de l'IGN », avec un lien vers la page du jeu.
- **Suisse** : swisstopo, swissBOUNDARIES3D, état au 1er janvier 2026 (fichier du 17 décembre 2025) : https://data.geo.admin.ch/ch.swisstopo.swissboundaries3d/swissboundaries3d_2026-01/swissboundaries3d_2026-01_2056_5728.gpkg.zip, couche `tlm_landesgebiet`, filtre `icc = 'CH'`. Précision annoncée (https://www.swisstopo.admin.ch/en/landscape-model-swissboundaries3d) : « Geometric accuracy ± 0.5 m in position and elevation ». Conditions (https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices) : « The free geodata and geoservices of swisstopo may be used, distributed and made accessible. Furthermore, they may be enriched and processed and also used commercially. A reference to the source is mandatory. » La forme courte admise par ces conditions est « ©swisstopo », sans espace (liste « one of the following source references must be attached in any case »). Mention : « ©swisstopo, swissBOUNDARIES3D », avec un lien vers ces conditions.
- **Italie** : ISTAT, limites administratives non généralisées au 1er janvier 2026 : https://www.istat.it/storage/cartografia/confini_amministrativi/non_generalizzati/2026/Limiti01012026.zip, fichier `Reg01012026/Reg01012026_WGS84.shp`, filtre `COD_REG IN (1, 2, 7)`. Licence CC BY 4.0 (https://www.istat.it/note-legali/) : « Salvo diversa indicazione, tutti i contenuti pubblicati su questo sito sono soggetti alla licenza Creative Commons - Attribuzione - versione 4.0. » et « Attribuzione - Devi riconoscere una menzione di paternità adeguata, fornire un link alla licenza e indicare se sono state effettuate delle modifiche. » Mention : « Istat, Confini delle unità amministrative a fini statistici al 1° gennaio 2026, CC BY 4.0, données modifiées », avec un lien vers https://creativecommons.org/licenses/by/4.0/deed.it.
- **Espagne** : IGN España, API OGC Features, collection `administrativeunit`, une requête par communauté : https://api-features.ign.es/collections/administrativeunit/items?f=json&nationalcode=34020000000 (Aragón), et de même avec 34090000000 (Cataluña), 34150000000 (Navarra), 34160000000 (País Vasco). Métadonnées du 23 février 2026 : « BDLJE CC-BY 4.0 ign.es ». Licence d'usage de l'IGN (https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf) : « Cuando el usuario licenciado genere una obra derivada [...] se añadirá «Obra derivada de» delante de la expresión general ». Mention : « Obra derivada de BDLJE CC-BY 4.0 ign.es », avec un lien vers cette licence ; la date à y ajouter n'a pas été établie (non vérifié).
- **Andorre** : OpenStreetMap, relation 9407, extrait quotidien de Geofabrik : https://download.geofabrik.de/europe/andorra-latest.osm.pbf, couche `multipolygons`, filtre `osm_id = '9407'`.
- **Monaco** : OpenStreetMap, relation 36990 (terre ferme, sans les eaux territoriales), extrait quotidien de Geofabrik : https://download.geofabrik.de/europe/monaco-latest.osm.pbf. Le pipeline assemble les chemins de cette relation en polygones (2,08 km²).
- Licence d'OpenStreetMap (https://www.openstreetmap.org/copyright) : « OpenStreetMap is open data, licensed under the Open Data Commons Open Database License (ODbL) by the OpenStreetMap Foundation (OSMF). » et « You are free to copy, distribute, transmit and adapt our data, as long as you credit OpenStreetMap and its contributors. » Mention pour l'Andorre et Monaco : « © OpenStreetMap contributors (ODbL 1.0) », avec un lien vers https://www.openstreetmap.org/copyright.
- **Partage à l'identique (ODbL).** Le code pays des tuiles dérive de contours sous ODbL en France, en Andorre et à Monaco. La question du partage à l'identique d'une base dérivée n'a pas été tranchée. Une ligne directrice de la fondation OpenStreetMap, relue pendant la recherche, distingue une base de données d'un « Produced Work » (œuvre produite à partir des données) ; des tuiles faites pour l'affichage relèveraient plutôt du second cas. C'est une lecture, pas un fait établi : le texte de l'ODbL lui-même n'a pas été relu. Elle vaut aussi pour le contour français.
- **Garde-fous** : pour chaque contour, le nombre d'entités attendu (1 pour la Suisse et l'Andorre, 3 pour l'Italie, 4 pour l'Espagne) ; pour les deux contours tirés d'OpenStreetMap, base modifiable par tous, la surface attendue (Andorre entre 455 et 480 km², Monaco entre 1,9 et 2,4 km²). Hors de ces bornes, la construction s'arrête. Pendant la recherche, le serveur de Geofabrik a parfois refusé la connexion depuis les machines de GitHub : le pipeline fait jusqu'à sept essais pour les fichiers de contour, ceux de Geofabrik compris (quatre pour le fichier des départements français, comme pour les autres téléchargements).

Où sont ces mentions : le panneau « Sources » du site affiche, pour chaque pays, « Contour du pays : » suivi de la mention, avec son lien ; `SOURCES.md` les redit dans la release. Elles ne sont pas dans le pied de carte. Pour swisstopo, la page d'aide (https://www.swisstopo.admin.ch/en/source-reference-ogd-swisstopo) admet ce cas : « Acceptable: The source is mentioned in a central location on a web page listing all sources used in the map application or service. » La licence de l'IGN España demande en principe une mention « visible junto con los datos, de forma legible y a pie de mapa » et n'admet une liste de crédits qu'« En caso de imposibilidad manifiesta y justificable » : point à trancher par le propriétaire.

### Traitement des frontières

Les contours viennent de producteurs différents et ne coïncident pas. Largeur moyenne des recouvrements, mesurée pendant la recherche : 0,1 m entre la Suisse et la France, 16,7 m entre l'Italie et la France, 38,3 m entre l'Andorre et l'Espagne. Le contour de l'ISTAT est le moins fin face à la France : par endroits, jusqu'à 200 à 300 m de trou et 400 à 600 m de recouvrement.

- **Priorité.** Les pays sont rangés dans `config.yaml` dans cet ordre : France, Suisse, Italie, Espagne, Andorre, Monaco. Là où deux contours se recouvrent, le premier pays garde le pixel. La frontière affichée est donc celle du pays prioritaire : le contour français face à tous les voisins de la France, swisstopo face à l'Italie, IGN España face à l'Andorre. Au mont Blanc, 77,7 ha revendiqués par les deux contours vont à la France ; 3 144 pixels revendiqués par l'Espagne et l'Andorre vont à l'Espagne.
- **Petits interstices comblés.** Les trous fermés de moins de 100 ha bordés par au moins deux entités des contours (deux pays, ou deux départements ou régions d'un même pays, comme entre les quatre communautés espagnoles) sont donnés au pays le moins prioritaire qui les touche : le contour du pays prioritaire fait foi, c'est l'autre qui s'étend jusqu'à lui. Pourquoi : sinon un tracé qui passe la frontière traverserait quelques mètres « hors zone ». Le seuil de 100 ha sépare les interstices (le plus grand fait environ 28,5 ha) des vraies enclaves (la plus petite, Campione d'Italia, fait 264 ha) ; les deux seuls trous plus petits qui ne sont pas des interstices sont les enclaves lombardes ci-dessous, écartées par la règle des deux entités. Mesures de la contre-vérification, sur la grille réelle avec les départements frontaliers : 8 499 pixels sans pays coincés entre deux pays avant comblement, 22 après.
- **Enclaves lombardes.** Deux trous de 18,0 et 19,3 ha ne sont pas des interstices entre pays : ce sont des morceaux de Lombardie entourés par le Piémont dans le contour de l'ISTAT. Bordés par une seule entité, ils ne sont pas comblés et restent hors zone, comme le reste de la Lombardie. Vérifié dans les tuiles de la release en ligne : leurs points (8,7053 E 45,0180 N et 8,8138 E 45,0193 N) sont hors zone.
- **Niveau des pixels comblés.** Aucune source ne les décrit. Ils prennent le plus petit niveau de leurs voisins du même pays (dans le doute, on annonce le moins de couverture), de proche en proche jusqu'à 16 pixels ; au-delà, ils restent à 0. Ils gardent le type de source de leur pays : un pixel comblé est affiché comme une donnée officielle, alors que son niveau est extrapolé.
- Construction de la release en ligne (`data-2026-11-14`) : interstices comblés, Suisse 3 704 trous et 57 pixels, Italie 1 666 trous et 12 816 pixels, Espagne 13 275 trous et 221 pixels, Andorre 993 trous et 684 pixels, Monaco 36 trous et 2 pixels ; 13 780 pixels marqués, dont 13 777 extrapolés et 3 sans voisin.
- **Seuls les trous fermés sont comblés.** Un comblement plus large aurait rempli des morceaux de mer, par exemple 5,53 ha au sud de Monaco.
- **Hors zone** (trous de 100 ha ou plus, laissés vides) : la partie française du Léman (le contour du département 74, Haute-Savoie, s'arrête à la rive, alors que la partie suisse du lac est dans la zone) ; les enclaves de Treviño (province de Burgos, dans le Pays basque) et de Valle de Villaverde (Cantabrie), noms déduits des coordonnées ; Büsingen (enclave allemande en Suisse) et Campione d'Italia (enclave italienne en Suisse). Le Liechtenstein est hors zone. L'enclave espagnole de Llívia, en France, est bien dans le contour espagnol.
- **Bords propres à chaque source** : en Suisse, les carrés sans donnée collés à la frontière sont comblés (voir « Suisse ») ; en Italie et en Espagne, une frange reste plus souvent « sans couverture » (voir ci-dessous) ; en Espagne, les polygones sans commune ne sont pas lus.
- **Contrôle.** Des pixels tirés au hasard (60 sur toute la grille et 60 autour de chaque pays) reçoivent leur pays attendu par un test géométrique exact sur les contours, en suivant l'ordre de priorité ; un pixel hors de tous les contours n'a pas de pays. Les pixels des interstices comblés ne servent pas à ce contrôle. Ces points sont ensuite relus dans les tuiles publiées : le moindre écart fait échouer la construction. Construction de la release en ligne : 420 points, aucun écart.

### Ce que l'on voit le long des frontières

Mesure faite sur les tuiles de la release `data-2026-11-14-3`, qui avait les mêmes sources que la release en ligne pour la France, la Suisse, l'Italie et l'Espagne. Dans les 358 tuiles du zoom 12 qui touchent au moins deux pays, part des pixels « pas de couverture » (internet mobile, tous opérateurs) selon la distance à la frontière internationale :

| Pays, face à | 1 à 3 pixels | 4 à 9 pixels | 10 à 20 pixels |
|---|---|---|---|
| France, face à la Suisse | 6,91 % | 5,89 % | 4,07 % |
| France, face à l'Italie | 56,49 % | 51,57 % | 51,37 % |
| France, face à l'Espagne | 34,35 % | 31,13 % | 30,58 % |
| Suisse, face à la France | 1,08 % | 0,86 % | 0,50 % |
| Suisse, face à l'Italie | 0,68 % | 0,68 % | 1,70 % |
| Italie, face à la France | 26,21 % | 17,32 % | 20,69 % |
| Italie, face à la Suisse | 33,42 % | 27,36 % | 28,93 % |
| Espagne, face à la France | 41,42 % | 40,65 % | 44,80 % |

Pixel par pixel : côté italien face à la France, 32,7 % au premier pixel, 25,1 % au deuxième, 20,5 % au troisième, puis 17 à 18 % ; côté espagnol, 48,7 % au premier pixel puis 37,8 % ; côté français, la baisse est douce (face à l'Italie : 59,0 %, puis 56,1 %, 54,3 %, 53,2 %, jusque vers 50,5 %).

Conclusion : il n'y a pas de bande blanche artificielle large. Il reste une frange de 1 à 3 pixels (30 à 85 m) plus souvent « sans couverture » côté italien et côté espagnol, parce que les mailles des sources n'arrivent pas exactement au contour (mailles coupées en Espagne, carrés de 100 m en Italie). L'erreur va du côté prudent. Effet sur un rapport GPX : une zone blanche peut être allongée de quelques dizaines de mètres au passage d'une frontière.

## Fonds de carte et recherche de lieux

Adresses et identifiants des couches de fond, mentions et règles de préchargement : `src/map/basemaps.ts`. Adresses et délais de la recherche de lieux : `src/config.ts` et `src/search/geocode.ts`. Tous ces services sont gratuits et sans clé pour l'usage du site.

### Plan IGN (vectoriel, avec repli en images), photos aériennes, estompage

- Éditeur : IGN, Géoplateforme. Plan IGN en tuiles vectorielles (la carte arrive sous forme de formes et de textes, que le navigateur dessine) : styles https://data.geopf.fr/annexes/ressources/vectorTiles/styles/PLAN.IGN/classique.json et `standard.json`, tuiles https://data.geopf.fr/tms/1.0.0/PLAN.IGN (adresse donnée par le style lui-même). Version en images : WMTS (service de tuiles en images) https://data.geopf.fr/wmts, couche `GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2`. Photos aériennes : même WMTS, couche `ORTHOIMAGERY.ORTHOPHOTOS`. Estompage du relief, en option et en France seulement : couche `ELEVATION.ELEVATIONGRIDCOVERAGE.SHADOW`, style `estompage_grayscale`.
- En attendant le style vectoriel, la carte montre tout de suite le Plan IGN en images, avec la couche réseau et le tracé. Si le style n'arrive pas en 8 secondes (`VECTOR_STYLE_TIMEOUT_MS`), ou s'il ne peut pas être lu, la carte garde la version en images et le dit.
- Conditions : CGU de la Géoplateforme, version du 15 octobre 2024, https://cartes.gouv.fr/cgu/ : « Sur la Géoplateforme, l’utilisation des géodonnées et géoservices est gratuite (sauf licence spécifique). »
- Licence des données : « Licence Ouverte / Open License (compatible ODC-BY, CC-BY 2.0) » dans les métadonnées du Plan IGN (`IGNF_PLAN-IGN`) et des photos aériennes (`IGNF_BD-ORTHO`). Pour l'estompage, le service ne donne aucun lien de métadonnées : c'est la règle par défaut des CGU qui s'applique (« A défaut, la Licence Ouverte / Open Licence - Etalab s’applique sur ce jeu de données. », phrase du passage adressé aux fournisseurs de données), non vérifié couche par couche.
- Mention affichée : « © IGN », en lien vers les CGU de la Géoplateforme.
- Limites : tuiles vectorielles, 400 requêtes par seconde et par adresse IP ; WMTS « Non soumis à limite d'usage ». Au-delà d'une limite, le service répond par une erreur 429 et bloque 5 secondes. En cas d'usage abusif, l'IGN peut limiter ou bloquer l'accès.

### swisstopo

- Éditeur : Office fédéral de topographie swisstopo. Carte nationale en couleurs, couche `ch.swisstopo.pixelkarte-farbe`, WMTS https://wmts.geo.admin.ch.
- Conditions : celles de la FSDI (voir « Suisse ») et celles des géodonnées gratuites de swisstopo (https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices), citées dans « Contours des pays ».
- Mention affichée : « ©swisstopo », sans espace, forme courte de la liste des mentions admises, en lien vers ces conditions.
- Limites : « fair use » (usage raisonnable) de 1'200 requêtes par minute et 631 millions par an pour le WMTS. Le texte ne dit pas si la limite se compte par application, par utilisateur ou par adresse IP ; lecture prudente : pour tous les visiteurs du site réunis. Le texte ajoute : « Note on web scraping: Automatic parsing of geoservices via bots with high query intensities is to be avoided. The download service should be used to obtain the datasets outside the context of the web services (use in offline systems, databases, etc.). » Service fourni au mieux (« best effort »), sans garantie.

### IGN España

- Éditeur : Instituto Geográfico Nacional. « Cartografía Ráster de España del IGN », couche `MTN`, WMTS https://www.ign.es/wmts/mapa-raster.
- Licence : CC BY 4.0, licence d'usage de l'IGN fondée sur l'Orden FOM/2807/2015 (https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf) : « el uso de los productos y servicios de información geográfica del IGN definidos en el ámbito de la Orden FOM/2807/2015 conlleva la aceptación por el usuario de una licencia CC-BY 4.0 ». Et : « Esta mención de atribución obligatoria se mostrará visible junto con los datos, de forma legible y a pie de mapa, imagen, presentación o ventana de visualización. »
- Mention affichée : « CC BY 4.0 ign.es », avec « ign.es » en lien vers https://www.ign.es. C'est la valeur exacte du champ `AccessConstraints` du service, et la formule demandée par le propriétaire du projet.
- Nuance : pour un service utilisé sans modification, la licence retient d'abord la formule des données couplées au service, et celle d'`AccessConstraints` seulement « si no hay datos acoplados ». Or la couche MTN déclare dix fiches couplées, dont « Mapa Alta Resolución 2025 CC-BY 4.0 ign.es » et « MTN25_raster 2025 CC-BY 4.0 ign.es ». La licence admet aussi une forme abrégée, « CC-BY 4.0 <atribución productores> <fecha> », par exemple « CC-BY 4.0 ign.es 2025 ». L'une des dix fiches couplées est une fiche GEBCO (gebco.net), donnée tierce dont les conditions n'ont pas été lues. La mention affichée ne change pas tant que le propriétaire n'a pas tranché.
- Limites : aucune limite de débit publiée, rien sur le cache ni sur l'usage hors ligne (constat de l'enquête, non revérifié).

### Fond OpenStreetMap (OpenTopoMap)

- Tuiles `https://{a|b|c}.tile.opentopomap.org/{z}/{x}/{y}.png` (forme donnée par OpenTopoMap) : carte topographique faite à partir des données OpenStreetMap. En mode Auto, le site prend le fond national du pays au centre de la carte (Plan IGN classique, swisstopo, IGN España) ; OpenTopoMap est celui des pays sans fond national dans le site (Italie, Andorre, Monaco). Si le centre est hors des données, c'est le fond du pays le plus présent dans la vue, et OpenTopoMap si la vue ne montre aucun pays couvert.
- Licence (https://opentopomap.org/about) : « OpenTopoMap steht unter der Lizenz CC-BY-SA. Das bedeutet, dass die Karte kostenlos und frei verwendet werden darf, solange stets Namensnennung erfolgt und die Weitergabe unter gleichen Bedingungen möglich ist. » Dans la mention demandée, le lien de licence vise la version 3.0 (https://creativecommons.org/licenses/by-sa/3.0/).
- Mention demandée : « Als Lizenztext sollte Folgendes deutlich sichtbar sein: Kartendaten: © OpenStreetMap-Mitwirkende, SRTM | Kartendarstellung: © OpenTopoMap (CC-BY-SA) ». Mention affichée sur ordinateur : celle-ci, mot pour mot, avec ses trois liens (https://openstreetmap.org/copyright, http://opentopomap.org et la licence). Sur téléphone, une forme courte, avec les mêmes liens : « © OpenStreetMap, SRTM | © OpenTopoMap (CC-BY-SA) ». OpenTopoMap ne publie pas de forme courte : celle-ci est un choix du projet, qu'aucun texte lu n'approuve.
- Limites : aucun chiffre, mais pas de téléchargements en masse et aucune garantie de disponibilité : « Dies ist jederzeit gerne möglich, sofern unser Server z.B. durch Massendownloads nicht zu stark beansprucht wird. Außerdem kann keinerlei Ausfallsicherheit garantiert werden. » Le serveur a été réduit le 5 janvier 2026 (« We updated our render server to a smaller vServer on 05.01.2026. ») et un passage aux tuiles vectorielles est annoncé : ce fond pourra devoir être remplacé.
- Les tuiles standard d'OpenStreetMap (tile.openstreetmap.org) ne sont pas utilisées. Leur politique interdit le préchargement : « Offline use is not permitted on tile.openstreetmap.org. »

### Recherche de lieux

- France : autocomplétion du géocodage de la Géoplateforme (IGN), https://data.geopf.fr/geocodage/completion, sous les CGU de la Géoplateforme. Le site demande `terr=METROPOLE` : la Corse en fait partie (vérifié le 14 novembre 2026 : Ajaccio, Corte, Bonifacio et Calvi sont proposés). Limite : 10 requêtes par seconde et par adresse IP. Le site n'interroge qu'à partir de 3 caractères et 350 ms après la dernière frappe, soit au plus environ 3 requêtes par seconde. Il envoie aussi le centre de la carte, arrondi au dixième de degré (paramètre `lonlat`), pour que les lieux proches passent en premier ; si le service refusait ce paramètre, la recherche repart sans lui.
- Étranger : Photon (komoot), https://photon.komoot.io/api/, données OpenStreetMap (ODbL). Conditions : « You can use the API for your project, but please be fair - extensive usage will be throttled. We do not guarantee for the availability and usage might be subject of change in the future. » Langues acceptées : allemand, anglais, français ; sinon, noms locaux. Le site envoie le texte tapé, la langue, le centre de la carte arrondi au dixième de degré et une emprise de recherche fixe, la même pour tous (de 12° ouest à 18° est et de 36° à 54,5° nord). Les résultats situés en France sont écartés, car l'IGN les fournit.
- Chaque service a 5 secondes pour répondre (`SEARCH_TIMEOUT_MS`). Les lieux du premier qui répond s'affichent sans attendre l'autre ; un service en panne ou trop lent est signalé dans la liste.
- Mention affichée : sous les résultats, « Résultats : IGN et © les contributeurs d'OpenStreetMap », avec « OpenStreetMap » en lien vers https://www.openstreetmap.org/copyright ; dans le panneau « Sources », « France : géocodage de la Géoplateforme (IGN) » et « Étranger : Photon (komoot), données © les contributeurs d'OpenStreetMap », avec le même lien. Ce crédit vient des règles d'attribution d'OpenStreetMap (« Geocoders that use OpenStreetMap data must credit OpenStreetMap »), pas des conditions de Photon, qui n'en parlent pas. Ces règles citent les formes « © OpenStreetMap contributors » et « © OpenStreetMap » ; la forme traduite du site est un choix à valider.
- Nominatim n'est pas utilisé : sa politique interdit l'autocomplétion côté client (« Auto-complete search This is not yet supported by Nominatim and you must not implement such a service on the client side using the API. »).

### Affichage des mentions

- **Pied de carte.** Une ligne « Fond : » avec la mention du fond affiché et ses liens (et celle de l'estompage s'il est affiché et qu'elle diffère), puis une ligne « Couverture : » avec la mention de chaque source de couverture dont des données sont à l'écran, pour le service choisi. Le site les trouve en lisant le pays de tous les pixels de la vue, dans les tuiles déjà affichées. Pour une zone estimée, c'est le crédit d'OpenCellID avec ses liens (voir « Andorre »). Un bouton « Sources » ouvre le panneau du même nom.
- **Sur ordinateur** (écran de 900 px de large ou plus) : le pied de carte est toujours visible, au-dessus de la barre d'outils, avec les formes complètes des mentions.
- **Sur téléphone** (moins de 900 px) : les mentions sont dépliées au chargement. Au premier geste sur la carte (glisser, pincer, molette), elles se replient derrière un bouton « © » de 44 px, comme le fait MapLibre (la bibliothèque qui affiche la carte) en mode compact. Un appui sur « © » les rouvre. Le fond OpenTopoMap y prend sa forme courte. Une fois repliées, il faut un geste pour les relire : c'est un écart avec plusieurs textes. IGN España demande une mention « visible [...] a pie de mapa », OpenTopoMap un texte « deutlich sichtbar », OpenCellID un crédit « beside the map or visualization », et les règles d'OpenStreetMap disent : « The attribution format should not require individuals to interact with the map or produced work to see the attribution. »
- **Panneau « Sources ».** Une section repliable par pays, ouverte d'emblée pour les pays à l'écran : nom de la source avec son lien, date des données, méthode, niveaux, technologies, licence avec son lien, phrase imposée par la licence (dans la langue de la source) et logo quand il en faut un, mention du contour du pays avec son lien, opérateurs, avertissement d'itinérance. Puis tous les fonds avec leur mention et leurs liens, les deux services de recherche, et un lien vers ce document. Seules les adresses https du manifest deviennent des liens ; ils s'ouvrent dans un nouvel onglet.
- **Rapport en texte** : une ligne « Sources » reprend la mention de chaque source traversée, avec son pays et sa date.
- **Release de données** : `SOURCES.md` (voir « Données publiées »).
- Les noms des sources, les licences et les mentions de contour sont écrits en français dans le manifest. Quand ils contiennent du français, le manifest porte aussi leurs traductions en espagnol, catalan, italien et allemand (champs `nameI18n`, `licenceI18n`, `textI18n`) ; le site affiche celle de la langue choisie, sinon le texte d'origine. Les formules imposées (« Obra derivada de BDLJE CC-BY 4.0 ign.es », « © OpenStreetMap contributors », « ©swisstopo ») et les noms propres ne sont pas traduits : le nom de la source espagnole, par exemple, reste en espagnol.
- Le panneau « Sources » dit une fois, dans les cinq langues, que les données d'origine ont été transformées pour ce site (rastérisées sur une grille commune, ramenées à des niveaux ou à des seuils) : c'est l'indication de modification que demandent les licences CC BY.
- Attribut de langue, utile aux lecteurs d'écran. Le crédit d'OpenCellID (en anglais) et la mention d'OpenTopoMap (en allemand) le portent toujours, car le site connaît leur langue. Pour les mentions venues du manifest (AGCOM en italien, ministère espagnol en espagnol, phrases imposées, mentions de contour espagnole et OpenStreetMap), le site le pose quand le manifest donne leur langue (champs `mentionLang` et `boundary.lang`). **Le manifest en ligne ne la donne pas encore** : le pipeline l'écrira à la prochaine construction. D'ici là, ces mentions n'ont pas d'attribut de langue, et la phrase imposée du panneau « Sources » porte `lang="mul"` (langue non précisée).

## Tracés GPX de test

Les deux tracés de `samples/` servent à essayer l'import d'un GPX et le rapport. Ils viennent de deux sources ouvertes. Détail de leur fabrication et de leurs chiffres : [samples/README.md](../samples/README.md).

### OpenStreetMap, par l'API Overpass

- Source : la base OpenStreetMap, lue par l'API Overpass (https://overpass-api.de/api/interpreter), un service qui renvoie les objets d'une emprise selon une requête : chemins, pistes et itinéraires de randonnée, refuges, cols, lieux et frontière.
- Date : deux requêtes le 14 novembre 2026. La première, sur la base OpenStreetMap du 2026-11-14T12:26:07Z, a servi aux deux tracés ; la seconde, sur la base du 2026-11-14T17:08:49Z, au départ du tracé des Alpes, de Préfumet aux Chapieux.
- Licence : ODbL 1.0 (https://opendatacommons.org/licenses/odbl/1-0/). La licence fixe les conditions de toute base dérivée utilisée publiquement (« Any Derivative Database that You Publicly Use must be only under the terms of » cette licence) : les deux fichiers GPX sont donc mis à disposition sous ODbL 1.0, quelle que soit la licence du code du dépôt. Chaque fichier porte la mention « © les contributeurs d'OpenStreetMap », l'adresse https://www.openstreetmap.org/copyright et l'adresse de la licence.
- Politique d'usage d'Overpass (https://dev.overpass-api.de/overpass-doc/en/preface/commons.html) : « As a broad guideline to stay within safety margins, users are expected to send a maximum of about 10000 requests per day and keep their download volume below about 1 GB per day. » Deux requêtes de données en tout (4,4 Mo puis 0,44 Mo reçus).
- Méthode : plus court chemin sur les chemins d'OpenStreetMap entre les étapes, puis simplification légère.
- Limites : itinéraires calculés, pas parcourus ; OpenStreetMap peut être faux ou daté.

### Copernicus DEM GLO-30, pour les altitudes

- Source : les dalles N45 E006 (Alpes, départ de Préfumet compris), N42 W001 et N42 E000 (Pyrénées) du dépôt public `copernicus-dem-30m`, lues directement.
- Licence : celle décrite dans « Estimation » (« Copernicus DEM GLO-30 »). Les GPX contiennent des altitudes tirées du relief : chaque fichier porte la mention de l'article 6 (b) et la phrase de l'article 6 (c), en anglais, et un lien vers la licence livrée avec la dalle.
- Méthode : interpolation bilinéaire entre les quatre pixels voisins, arrondie à 0,1 m ; altitudes au-dessus du géoïde EGM2008 (la référence du « niveau de la mer »).
- Limites : modèle de surface (forêts et bâtiments compris) au pas de 30 m : les reliefs fins sont lissés, et l'altitude peut être un peu trop haute en forêt.

## Mode hors ligne

Le bouton « Préparer ce tracé pour le hors ligne » enregistre dans le navigateur (dans son cache, l'espace où il garde des fichiers), pour le tracé chargé (`src/offline/manager.ts`) :

1. rien pour le site lui-même : le Service Worker (`public/sw.js`, le programme du site qui sert les fichiers enregistrés quand il n'y a pas de réseau) a déjà enregistré la coque entière du site à son installation, c'est-à-dire `index.html` et tous les fichiers qu'il charge. La construction du site en écrit la liste et la version (`src/offline/shell.ts`) ; le Service Worker les enregistre tous ou aucun, dans un cache propre à cette version, et efface les versions précédentes. Le bouton vérifie seulement que la coque est complète (il attend jusqu'à 30 s à la première visite), sinon il le dit ;
2. le fichier GPX et une copie du manifest des données ;
3. les tuiles de couverture du couloir du tracé (700 m de part et d'autre, zooms 8 à 12), lues dans les archives du projet, 4 à la fois, avec le même délai de 20 s par lecture que pour l'affichage. Elles sont rangées sous le nom de leur archive : celles d'une autre édition des données ne sont jamais relues avec ce manifest ;
4. les tuiles des fonds de carte le long du parcours, si leur fournisseur le permet, dans les limites fixées pour chaque fond (tableau ci-dessous). En mode Auto, chaque portion du tracé reçoit le fond national de son pays ; l'estompage du relief suit s'il est affiché.

Un seul tracé à la fois : ce qui ne sert pas au nouveau tracé est effacé au début. L'enregistrement est noté « incomplet » dès le départ, jusqu'à la fin : interrompu, annulé ou en échec, il reste visible, et peut être repris (ce qui est déjà enregistré n'est pas retéléchargé) ou supprimé, après confirmation. Avant de télécharger, le site demande au navigateur de ne pas effacer ces données quand la place manque ; un refus est signalé, avec le conseil d'installer le site. Au démarrage, si le navigateur a effacé les données, l'enregistrement est oublié et un message le dit.

Le préchargement est piloté par la page : il s'arrête si l'onglet est fermé, et peut être repris plus tard. Le Service Worker, lui, sert ensuite les copies enregistrées.

Le fichier GPX n'est envoyé nulle part : tout reste dans le cache du navigateur. En revanche, le préchargement demande aux fournisseurs de fond les tuiles du couloir : comme lors d'une consultation normale de la carte, ils voient passer la zone du tracé. Si le couloir demande plus de tuiles que le plafond d'un fond, les zooms les plus fins sont abandonnés en premier : ce sont eux qui coûtent le plus de requêtes au fournisseur. Rien n'est demandé hors de l'emprise que sert le fournisseur. Les plafonds et les freins sont des choix du projet, pas des chiffres imposés par les fournisseurs.

| Fond | Préchargé | Plafond codé | Zooms | Requêtes simultanées | Débit maximal | Raison tirée des conditions |
|---|---|---|---|---|---|---|
| Plan IGN classique et standard | oui, avec le style, les pictogrammes et les polices | 900 tuiles | 7 à 15 | 4 | pas d'autre frein | aucun texte ne l'interdit ; la Licence Ouverte autorise la copie ; tuiles vectorielles limitées à 400 requêtes par seconde |
| Plan IGN en images (si le style vectoriel ne se charge pas) | oui | 600 tuiles | 9 à 15 | 4 | pas d'autre frein | mêmes raisons ; WMTS sans limite d'usage |
| Photos aériennes (IGN) | oui | 600 tuiles | 9 à 16 | 4 | pas d'autre frein | mêmes raisons ; WMTS sans limite d'usage |
| Estompage (IGN) | oui, s'il est affiché | 600 tuiles | 9 à 15 | 4 | pas d'autre frein | mêmes raisons ; WMTS sans limite d'usage |
| swisstopo | oui | 600 tuiles | 9 à 15 | 2 | 2 par seconde | toléré en petit nombre : limite de 1'200 requêtes par minute ; les robots à forte intensité sont à éviter et le service de téléchargement est conseillé pour les systèmes hors ligne, mais la documentation du WMTS prévoit qu'une application garde des tuiles en cache local |
| IGN España | oui | 600 tuiles | 9 à 15 | 2 | 5 par seconde | rien dans les textes ; la licence CC BY 4.0 permet de reproduire ; nombre limité par prudence |
| OpenTopoMap | non | aucun | aucun | aucune | aucun | le fournisseur demande d'éviter les téléchargements en masse et ne garantit pas son serveur : un préchargement est un téléchargement en masse |

Sur une réponse 429 (trop de requêtes) ou 503 (service indisponible), tout le fond attend la durée demandée par l'en-tête `Retry-After`, 5 s à défaut, puis reprend. Après 3 refus d'une même tuile, une attente demandée de plus de 60 s, ou 8 échecs réseau d'affilée, le reste de ce fond est abandonné : il manquera, et le bilan affiché fond par fond le dit. Le délai entre deux requêtes se compte depuis le départ réel de la précédente. Les tuiles de tile.openstreetmap.org sont toujours refusées.

Le Service Worker sert ensuite :

- la page (quels que soient `?lang` et les autres paramètres) et ses fichiers depuis la coque enregistrée, dès qu'elle est complète, sans attendre le réseau ; sinon (première visite), le réseau d'abord, puis la copie s'il ne répond pas dans les 3 s. Une seule version à la fois, jamais de mélange. Une nouvelle version du site s'installe en arrière-plan, dans sa propre coque, et ne sert qu'à la visite suivante, une fois fermés tous les onglets de la version en cours ;
- le manifest des données : le réseau d'abord ; s'il ne répond pas dans les 3 s (`NETWORK_TIMEOUT_MS`), ou en cas d'échec, la copie enregistrée avec le tracé. Une réponse du réseau en erreur (5xx) ne remplace pas cette copie. Sans réseau, le site travaille donc avec les données de la préparation ; avec du réseau, il signale si les données ont changé depuis l'enregistrement ;
- les tuiles de fond, les styles et les polices des autres sites : la copie enregistrée si elle existe, sinon le réseau. Rien n'est enregistré automatiquement : seul le bouton remplit ce cache, tracé par tracé ;
- les tuiles de couverture : la page lit elle-même les tuiles enregistrées avant de lire les archives en ligne.

Vérifié sur le site en ligne le 14 novembre 2026, au dernier contrôle dans un navigateur (116 contrôles sur 116, site et données en ligne) : pour le tracé d'essai, entièrement en France, 106 tuiles du vrai Plan IGN, 503 de photos aériennes et 167 d'estompage enregistrées ; le Plan IGN et les photos aériennes ont ensuite été servis sans réseau. Le préchargement de swisstopo et d'IGN España n'a pas été essayé avec leurs vrais serveurs (non vérifié).

Limites :

- Aucune durée de conservation : les tuiles de fond restent jusqu'à ce que l'utilisateur supprime les données hors ligne ou prépare un autre tracé, et une mise à jour de l'enregistrement garde les tuiles déjà enregistrées. Or la documentation du WMTS suisse demande de purger un cache local quand la couche change : « If your application caches tiles locally, you need to invalidate your local cache for this layer. » Les en-têtes de la Géoplateforme admettent 21 jours de conservation dans le cache du navigateur.
- Un serveur d'un autre site ne laisse lire son en-tête `Retry-After` que s'il l'autorise (en-têtes CORS, qui disent ce qu'une page d'un autre site peut lire) : sinon l'attente est de 5 s. Une réponse 429 sans ces en-têtes apparaît comme une erreur réseau.
- OpenTopoMap n'est jamais préchargé : en mode Auto, les portions du tracé en Italie, en Andorre ou à Monaco n'ont pas de fond sans réseau. Le bilan cite ces pays.

## Vie privée et bonnes pratiques

Dans le site :

- Pas de serveur propre au projet : le site et les tuiles de couverture sont servis par GitHub Pages. Pas de compte, aucun cookie déposé par le site, aucun outil de mesure d'audience ni de traçage.
- Le GPX est lu et analysé dans le navigateur. Il n'est jamais envoyé nulle part. En mode hors ligne, il est seulement rangé dans le cache du navigateur.
- La recherche de lieux n'interroge l'IGN et Photon que lorsqu'on tape dans le champ de recherche. Ils reçoivent le texte tapé et le centre de la carte, arrondi ; Photon reçoit aussi la langue et l'emprise fixe décrite plus haut. Rien d'autre qui vienne de l'utilisateur ne leur est envoyé ; comme tout site appelé par le navigateur, ils voient son adresse IP. Après « Ma position », le centre de la carte est proche de la position de l'utilisateur : d'où l'arrondi. Les deux services reçoivent ce centre arrondi au dixième de degré (environ 10 km).
- « Ma position » : la position est lue par le navigateur, avec l'accord de l'utilisateur, et sert seulement à placer le point sur la carte. Elle n'est envoyée nulle part. Le suivi s'arrête quand la page est cachée, et reprend à son retour.
- Les tuiles de fond sont demandées directement aux fournisseurs par le navigateur : comme pour toute carte en ligne, ils voient l'adresse IP du visiteur et la zone affichée. Comme référent, la page ne leur transmet que l'origine du site, sans le chemin de la page (règle `strict-origin-when-cross-origin`).
- La langue, les réglages et la description de l'enregistrement hors ligne sont mémorisés dans le navigateur (`localStorage`).

Dans le pipeline :

- Il tourne dans GitHub Actions (workflow « Données », `.github/workflows/build-data.yml`), une fois par mois (le 5, à 3 h 23 UTC) ou à la main. Il commence par détecter les nouvelles versions et ne reconstruit que si une source a changé, ou la version du pipeline (`pipeline/czb/__init__.py`), sauf lancement forcé (essayé pour de vrai : voir « Données publiées »).
- Les requêtes sont faites l'une après l'autre, avec une pause entre deux pages (1 s pour l'AGCOM, 0,5 s pour le ministère espagnol) ; ces pages sont demandées compressées. Un seul fichier est téléchargé à la fois et les fichiers intermédiaires sont supprimés au fur et à mesure. Les copies de travail évitent de relire les services les plus coûteux.
- Nom de logiciel annoncé aux serveurs (User-Agent) générique : « pipeline-couverture-mobile/1.0 (Python urllib) », sans le nom du dépôt ni celui de son propriétaire. Les sondes s'annoncent aussi sous un nom générique.
- La clé OpenCellID est un secret du dépôt. Elle est envoyée à la page des téléchargements dans le corps de la requête et masquée dans les journaux.
- Pas de scraping : aucune donnée n'est prise sur les sites des opérateurs ni sur des cartes non ouvertes (Infoantenas, cartoradio.mc sans autorisation, cartes d'Andorra Telecom et de Monaco Telecom). Le pipeline ne lit que des fichiers et des services publics dont la licence ou les conditions publiées permettent la réutilisation, avec les réserves dites plus haut pour l'Italie (voie d'accès) et pour l'Espagne (application des conditions générales du ministère à cette carte).
- Deux écarts pendant l'enquête, à connaître : une dizaine de tuiles d'image du ministère espagnol ont été lues sur des hôtes dont le robots.txt interdit les robots (le pipeline ne les lit pas, et aucun chiffre qui en vient n'est retenu) ; quand maps.agcom.it et www.mimit.gov.it ne répondaient pas, des sondes ont lu leurs copies chez Internet Archive (rien de ce document ne s'appuie sur elles).
- Quand une source ne répond pas depuis l'environnement de développement, le traitement se fait dans GitHub Actions, sans contournement.

## Points ouverts

Ce document signale ces points sans les trancher.

Décisions qui reviennent au propriétaire du projet :

- **Espagne, licence de la couche** : garder la source officielle en s'appuyant sur les conditions générales de réutilisation du ministère, faute de licence attachée à la carte ; écrire au ministère (S.G. de Operadores de Telecomunicaciones e Infraestructuras Digitales) ; ou passer l'Espagne en « estimée ». Même décision pour la copie de travail `cache-es_mtd.tif`, publiée dans la release. Les conditions d'ArcGIS Online n'ont pas été lues.
- **Italie, voie d'accès** : lire le service REST public de l'AGCOM plutôt que passer par la demande de téléchargement par courriel ; écrire ou non à opendata.bbmap@agcom.it pour l'informer.
- **Andorre, estimation très pessimiste** (12 sites connus) : la garder, masquer l'Andorre, ou enrichir l'estimation avec les cellules 2G et 3G (non essayé).
- **Zones estimées** : les publier sous CC BY-SA 4.0, comme le demande le partage à l'identique d'OpenCellID.
- **Monaco** : demander une autorisation écrite pour la couche « Sites Radioélectriques » de cartoradio.mc ; garder les seules cellules de Monaco Telecom (MCC 212) ou ajouter celles des réseaux français ; examiner data.gouv.mc quand il répondra (verdict provisoire).
- **Contours sous ODbL** (France, Andorre, Monaco) : régler la question du partage à l'identique pour le code pays des tuiles.
- **IGN España, forme des mentions** : garder « CC BY 4.0 ign.es » ou suivre la formule des données couplées (par exemple « CC-BY 4.0 ign.es 2025 ») ; accepter que la mention du contour espagnol ne soit que dans le panneau « Sources », alors que la licence demande une mention au pied de la carte sauf impossibilité justifiée.
- **Licence du code** : le dépôt n'a pas de fichier LICENSE et `package.json` ne déclare aucune licence. Le code n'a donc pas de licence déclarée. Les données gardent la licence de leurs sources, et les GPX de test sont sous ODbL 1.0.
- **Navigation hors ligne** : le préchargement est fait par la page, pas par le Service Worker comme le décrit le cahier des charges (il s'arrête si l'onglet est fermé, et se reprend) ; la page est servie « coque d'abord », si bien qu'une nouvelle version du site ne sert qu'à la visite suivante, une fois fermés tous les onglets de l'ancienne ; les tuiles de fond enregistrées n'ont pas de durée de conservation.
- **Format des tuiles** : le PNG est gardé, alors que le WebP sans perte serait environ 29 % plus léger (mesure sur 800 tuiles : 12,77 Mo contre 9,02 Mo). Raison : le décodeur de secours du site, en JavaScript, ne lit que le PNG, et le manifest refuse le WebP.
- **Crédit OpenStreetMap de la recherche** : garder la forme traduite (« © les contributeurs d'OpenStreetMap ») ou la forme « © OpenStreetMap contributors » citée par les règles d'OpenStreetMap.

Écarts connus, non corrigés :

- sur un écran de moins de 900 px, le pied de carte se replie derrière un bouton « © » au premier geste sur la carte ;
- la mention du contour espagnol n'est pas au pied de la carte ;
- les releases s'appellent `data-AAAA-MM-JJ-N` quand il y en a plusieurs le même jour, alors que le cahier des charges écrit `data-AAAA-MM-JJ` ;
- le Service Worker est écrit en JavaScript (`public/sw.js`), hors du contrôle de TypeScript : deux constantes du code y sont recopiées à la main ;
- la partie française du Léman est hors zone ;
- les pixels des interstices de frontière ont un niveau extrapolé, mais ils sont affichés comme des données officielles ;
- aucun contrôle de vraisemblance ne signale une estimation trop pauvre ;
- le manifest en ligne n'a pas encore le nombre de sites des estimations (prochain recalcul de l'estimation) ni la langue des mentions imposées (prochaine construction) : le panneau « Sources » ne montre donc pas encore ce nombre, et ces mentions n'ont pas encore d'attribut de langue.
