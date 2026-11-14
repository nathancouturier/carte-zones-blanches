# Tracés GPX de test

> **Tracés de test, ne pas s'en servir pour s'orienter.** Ils ont été calculés automatiquement à partir
> d'OpenStreetMap, sans reconnaissance sur le terrain. Ils ne disent rien de l'état des sentiers, de la neige, de
> la météo ni des passages délicats (échelle des Sarradets, montée finale à la brèche de Roland).

Deux fichiers pour tester l'import d'un GPX et le rapport de couverture du site. Chacun franchit une frontière et
traverse une zone blanche réelle des données françaises (Arcep), vérifiée dans les tuiles publiées.

| Fichier | Itinéraire | Distance | Dénivelé + / - | Altitude | Points | Frontière |
|---|---|---|---|---|---|---|
| `test-alpes.gpx` | Les Chapieux, col de la Seigne, refuge Elisabetta, La Visaille | 19,90 km | 1 023 m / 928 m | 1 548 à 2 512 m | 1 070 | France, Italie : col de la Seigne, km 10,25 |
| `test-pyrenees.gpx` | Gavarnie, refuge des Sarradets, brèche de Roland, refuge de Góriz | 14,05 km | 1 585 m / 773 m | 1 374 à 2 811 m | 843 | France, Espagne : brèche de Roland, km 7,81 |

Dénivelés calculés comme le fait le site : tracé rééchantillonné tous les 20 m, variations d'altitude de moins de
5 m ignorées. Les altitudes extrêmes sont celles des points du fichier ; le site, qui lit le tracé rééchantillonné,
affiche 2 511 m et 2 808 m pour les maximums. Le script `e2e/verif.mjs` importe `test-alpes.gpx`.

## Les itinéraires

### `test-alpes.gpx` : Tour du Mont-Blanc, des Chapieux au val Veny

Départ aux Chapieux (Savoie, 1 556 m), route de la Ville des Glaciers jusqu'à La Ville des Glaciers (km 4,6),
piste et sentier par Les Mottets, col de la Seigne (frontière franco-italienne, km 10,25, 45,751309 N
6,807186 E), descente par La Casermetta (vers le km 11) et le refuge Elisabetta (km 13,6), lac Combal (vers le
km 16,8), puis la piste du val Veny jusqu'à La Visaille (Vallée d'Aoste, Italie, 1 647 m). Le tracé suit
l'itinéraire principal du Tour du Mont-Blanc sur 16 km, puis la piste et les sentiers balisés du val Veny
(balisage AV2, sentiers 8 et 12). Chemins : 9,4 km de piste, 5,5 km de sentier, 5,0 km de petite route.

### `test-pyrenees.gpx` : de Gavarnie au refuge de Góriz par la brèche de Roland

Départ à Gavarnie (Hautes-Pyrénées, 1 374 m), chemin du Cirque, puis sentiers jusqu'au pied de l'échelle des
Sarradets, échelle (vers les km 4,6 à 5,3, cotée « demanding_mountain_hiking » dans OpenStreetMap), refuge des
Sarradets, aussi appelé refuge de la Brèche de Roland (km 7,1), brèche de Roland (frontière franco-espagnole,
km 7,81, 42,691062 N 0,034022 O ; la montée du refuge à la brèche est cotée « alpine_hiking »), puis descente
côté espagnol par le collado de Millaris (km 9,6) et le collado del Descargador (km 11,0) jusqu'au refuge de
Góriz (Aragon, Espagne, 2 190 m).

## Zones blanches attendues dans le rapport

Données lues dans la release `data-2026-11-14-2` : Arcep, couverture théorique 4G (internet mobile) au
30 juin 2026 (édition 2026-T2). « Tous opérateurs » est le maximum des quatre opérateurs. Une zone blanche fait au
moins 100 m ; deux zones séparées par moins de 50 m de couverture sont fusionnées. Ces chiffres ont été recalculés
avec le code du site (`src/gpx`) et peuvent changer avec une nouvelle release.

### `test-alpes.gpx` (10,25 km dans les données françaises, 9,65 km hors zone en Italie)

| Opérateur | Sans couverture côté France | Zones blanches |
|---|---|---|
| Tous opérateurs | 10 250 m | km 0 à 10,25 (10,25 km, altitude 1 548 à 2 511 m) |
| Orange, SFR, Bouygues Telecom, Free | 10 250 m chacun | km 0 à 10,25 |

Tout le côté français, des Chapieux au col de la Seigne, est sans couverture pour les quatre opérateurs : le tracé
commence dans la zone blanche et la quitte à la frontière. Il ne teste donc pas le passage d'une zone couverte à
une zone blanche (le tracé des Pyrénées le fait).

### `test-pyrenees.gpx` (7,83 km dans les données françaises, 6,22 km hors zone en Espagne)

Côté France, tous opérateurs : pas de couverture 2,00 km, couverture limitée 0,90 km, bonne 1,74 km, très bonne
3,19 km.

| Opérateur | Sans couverture côté France | Zones blanches |
|---|---|---|
| Tous opérateurs | 2 000 m | km 5,71 à 7,55 (1 840 m, altitude 2 223 à 2 727 m) ; km 7,73 à 7,83 (100 m, juste sous la brèche) |
| Orange | 3 840 m | km 3,51 à 3,75 ; 4,09 à 4,73 ; 4,79 à 5,55 ; 5,61 à 7,83 |
| SFR | 2 400 m | km 4,93 à 5,39 ; 5,71 à 7,55 ; 7,73 à 7,83 |
| Bouygues Telecom | 2 340 m | km 5,33 à 5,45 ; 5,61 à 7,83 |
| Free | 7 830 m | km 0 à 7,83 (tout le côté français) |

La première zone va du haut de l'échelle des Sarradets jusqu'au-dessus du refuge. La seconde mesure exactement
100 m, le seuil : elle teste la règle de longueur minimale, mais un seul point de 20 m de moins la ferait sortir
du rapport, si bien qu'elle peut disparaître avec une prochaine release.

### Appels et SMS

Avec le service « Appels et SMS » (couverture 2G et 3G de la même édition), tous opérateurs : une zone blanche
de km 0,23 à 10,25 (10,02 km) sur le tracé des Alpes, et une de km 6,85 à 7,83 (980 m) sur celui des Pyrénées.

### Côté étranger

Les données italiennes et espagnoles ne sont pas encore publiées : ces parties du parcours sont aujourd'hui
« hors zone ». Ce qu'on peut en attendre, sans certitude :

- Italie (AGCOM, couche 4G agrégée, édition du 27 janvier 2026) : 92,8 % de la Vallée d'Aoste est couverte par au
  moins un réseau et un point de contrôle près de Courmayeur l'est par trois, mais aucun point du val Veny n'a été
  contrôlé et aucune zone blanche précise n'a été localisée. Le résultat sur le col de la Seigne et le haut du
  vallon reste à voir.
- Espagne (carte du ministère, situation au 30 juin 2024) : un point lu dans la couche par opérateur au refuge de
  Góriz (0,0151 E, 42,6633 N, commune de Fanlo) n'a aucun opérateur 4G. L'arrivée devrait donc tomber en zone
  sans couverture ; le reste du versant espagnol n'a pas été vérifié.

## Comment ils ont été faits

1. **Chemins** : une seule requête à l'API Overpass le 14 novembre 2026 (base OpenStreetMap du
   2026-11-14T12:26:07Z), sur deux emprises serrées (Alpes : 45,68 à 45,80 N, 6,71 à 6,91 E ; Pyrénées : 42,65 à
   42,745 N, 0,10 O à 0,04 E) : chemins `highway` = path, footway, track, steps, bridleway, pedestrian, plus les
   chemins des relations `route` = hiking ou foot, avec leur géométrie ; refuges, cols et lieux ; frontière
   (relations `boundary=administrative`, `admin_level=2`).
2. **Graphe et plus court chemin** : les chemins sont reliés par leurs noeuds partagés. Le poids d'un tronçon est
   sa longueur multipliée par un facteur : 1 pour un sentier ou une piste, 1,6 pour une route, 1,15 à 10 selon la
   cotation `sac_scale`, 3 si le sentier est peu visible. Un tronçon emprunté par un itinéraire balisé n'est pas
   pénalisé (facteur ramené à 1, ou 1,05 pour une route, cotation comprise) et reçoit en plus 0,95 (0,7 de plus sur
   le Tour du Mont-Blanc et l'Alta Via 2 pour le tracé des Alpes) : les passages alpins balisés restent donc
   possibles, comme la montée à la brèche de Roland. Plus court chemin (Dijkstra) entre les étapes (départ, col, refuges, arrivée), sans repasser
   par un noeud déjà emprunté. Le tracé suit les chemins de bout en bout, sans saut. À l'arrivée des Alpes, le
   noeud le plus proche du hameau de La Visaille était sur une piste parallèle à la route : le calcul dépassait le
   hameau puis revenait sur environ 150 m. Ce crochet a été retiré, le tracé s'arrête sur la route, à 21 m du
   hameau.
3. **Simplification légère** : Douglas-Peucker à 2 m, puis des points intermédiaires pris sur le chemin là où deux
   points sont à plus de 25 m. Écart entre points : 18,6 m en moyenne (Alpes), 16,7 m (Pyrénées), 25 m au plus.
   Coordonnées à 6 décimales, pas de doublon, pas d'horodatage.
4. **Altitudes** : Copernicus DEM GLO-30 (dalles N45 E006, N42 W001 et N42 E000, lues directement sur le
   dépôt public), interpolation bilinéaire entre les quatre pixels voisins, arrondie à 0,1 m. Altitudes au-dessus
   du géoïde EGM2008.
5. **Vérifications** : les deux fichiers sont valides selon le schéma officiel GPX 1.1
   (http://www.topografix.com/GPX/1/1/gpx.xsd) ; l'analyse ci-dessus a été refaite avec le code du site
   (lecture GPX, rééchantillonnage, tables de niveaux du manifest, zones blanches, dénivelé) sur les mêmes pixels,
   avec des résultats identiques. Frontière : d'après les contours officiels (Etalab pour la France, ISTAT pour la
   Vallée d'Aoste, IGN España pour l'Aragon), chaque tracé la franchit une seule fois, au km 10,23 (Alpes) et au
   km 7,82 (Pyrénées). OpenStreetMap la place au km 10,25 et au km 7,81 ; les tuiles françaises s'arrêtent entre
   les km 10,24 et 10,26 et entre les km 7,82 et 7,84 (pixels de 27 à 28 m).

## Sources, licences et mentions

- **OpenStreetMap** : géométrie des chemins. « © les contributeurs d'OpenStreetMap »,
  https://www.openstreetmap.org/copyright. Les données sont sous licence Open Database License (ODbL) 1.0,
  https://opendatacommons.org/licenses/odbl/1-0/ : « Vous êtes libre de copier, distribuer, transmettre et
  adapter nos données, à condition que vous créditiez OpenStreetMap et ses contributeurs » (page de copyright).
  La licence fixe les conditions de toute base dérivée utilisée publiquement (« Any Derivative Database that You
  Publicly Use must be only under the terms of » cette licence) : **ces deux fichiers GPX sont donc mis à
  disposition sous ODbL 1.0**, quelle que soit la licence du code du dépôt. Chaque fichier porte la mention et
  l'adresse https://www.openstreetmap.org/copyright dans sa description, comme le demandent les directives
  d'attribution de la fondation OpenStreetMap
  (https://osmfoundation.org/wiki/Licence/Attribution_Guidelines).
- **API Overpass** (https://overpass-api.de/api/interpreter) : politique d'usage du manuel officiel
  (https://dev.overpass-api.de/overpass-doc/en/preface/commons.html) : « As a broad guideline to stay within
  safety margins, users are expected to send a maximum of about 10000 requests per day and keep their download
  volume below about 1 GB per day. » Une seule requête de données a été envoyée (4,4 Mo reçus), plus une lecture
  de l'état du serveur.
- **Copernicus DEM GLO-30** : altitudes. Licence lue dans chaque dossier de dalle, par exemple
  https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N45_00_E006_00_DEM/INFO/eula_F.pdf (présentation
  du jeu : https://copernicus-dem-30m.s3.amazonaws.com/readme.html). Mentions obligatoires (article 6) :
  « produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018
  provided under COPERNICUS by the European Union and ESA; all rights reserved » ; « The organisations in charge of
  the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus
  WorldDEM-30 », soit en français : les organismes chargés du programme Copernicus, par la loi ou par délégation,
  n'encourent aucune responsabilité pour quelque utilisation que ce soit du Copernicus WorldDEM-30.
- **Arcep, Mon réseau mobile** : couverture théorique, Licence Ouverte / Open Licence (Etalab), d'après le manifest
  de la release. Elle a seulement servi à vérifier les zones blanches : les fichiers GPX n'en contiennent rien.
- **Contours officiels des pays** : contours administratifs d'Etalab (d'après ADMIN EXPRESS de l'IGN, ceux du
  pipeline), limites des régions de l'ISTAT au 1er janvier 2026 (CC BY 4.0) et unités administratives de l'IGN
  España (« BDLJE CC-BY 4.0 ign.es »), lus le 14 novembre 2026. Ils ont seulement servi à vérifier le passage de la
  frontière : les fichiers GPX n'en contiennent rien.

## Limites

- Itinéraires calculés, pas parcourus. OpenStreetMap peut être faux ou daté ; la cotation `sac_scale` vient des
  contributeurs. Pyrénées : 7,1 km cotés « demanding_mountain_hiking » et 0,75 km « alpine_hiking » de part et
  d'autre de la brèche.
- Le MNT Copernicus est un modèle de surface : « The Copernicus DEM is a Digital Surface Model (DSM) which
  represents the surface of the Earth including buildings, infrastructure and vegetation. » En forêt (bas du val
  Veny), l'altitude peut être un peu trop haute.
- Pas de 30 m : les reliefs fins sont lissés. La brèche de Roland sort à 2 784 m (2 807 m dans OpenStreetMap) et
  le point le plus haut du tracé (2 811 m) est 80 m plus loin, côté espagnol ; le col de la Seigne sort à 2 511 m
  (2 515 m dans OpenStreetMap). Dans l'échelle des Sarradets (km 4,7 à 4,9), le chemin longe des falaises et
  l'altitude saute de 16 à 37 m entre points voisins, parfois vers le bas alors que le chemin monte, ce qui gonfle
  un peu le dénivelé.
- Couverture théorique, des écarts locaux sont possibles.
