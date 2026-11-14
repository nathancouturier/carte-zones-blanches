# Pipeline de données et workflows

Le pipeline est la chaîne de traitement qui transforme les sources de couverture en tuiles pour le site (les carrés d'image qui composent la carte, détaillés dans l'[encodage des tuiles](architecture.md#encodage-des-tuiles)). Il produit des archives PMTiles (un fichier par archive, qui contient ses tuiles) et un manifest (le fichier `manifest.json`, qui décrit les données pour le site). Il est écrit en Python avec GDAL (une bibliothèque de traitement des données géographiques). Il tourne dans GitHub Actions, le service de GitHub qui lance des tâches automatiques, les workflows, sur ses propres machines. Il y utilise l'image `ghcr.io/osgeo/gdal:ubuntu-small-3.13.3` : un système tout prêt, où GDAL est installé. Le résultat est publié dans une release : une publication du dépôt GitHub, avec les fichiers de données joints.

Ce document décrit d'abord les commandes et les étapes d'une construction, les modules, la grille commune et les frontières, les contrôles et l'estimation. Il décrit ensuite les copies de travail (le résultat de sources longues à relire, gardé d'une construction à l'autre), le contenu d'une release et les chiffres de la construction de production. Il finit par chaque workflow et par les périmètres d'essai (les pays ou régions que l'on peut construire seuls, pour essayer). La vue d'ensemble est dans le [README](../README.md#le-pipeline-de-données). Le site, qui lit les tuiles, est décrit dans [architecture.md](architecture.md). Les sources (adresses, licences, méthodes, limites) sont dans [sources.md](sources.md).

## Sommaire

- [Les commandes](#les-commandes)
- [Étapes d'une construction](#étapes-dune-construction)
- [Un module par source](#un-module-par-source)
- [Grille commune et frontières](#grille-commune-et-frontières)
- [Points témoins et test de cohérence](#points-témoins-et-test-de-cohérence)
- [L'estimation](#lestimation)
- [OpenCellID et le secret OPENCELLID_TOKEN](#opencellid-et-le-secret-opencellid_token)
- [Copies de travail](#copies-de-travail)
- [Contenu d'une release et SOURCES.md](#contenu-dune-release-et-sourcesmd)
- [Chiffres de la construction de production](#chiffres-de-la-construction-de-production)
- [Les workflows](#les-workflows)
- [Périmètres d'essai](#périmètres-dessai)
- [Ajouter une source en détail](#ajouter-une-source-en-détail)
- [Réglages du pipeline](#réglages-du-pipeline)

## Les commandes

On appelle le pipeline depuis le dossier `pipeline/` :

| Commande | Rôle |
|---|---|
| `python3 -m czb.cli state --scope ... --services ...` | affiche l'état des sources en ligne |
| `python3 -m czb.cli changed --repo propriétaire/nom ...` | compare cet état à celui de la dernière release de données |
| `python3 -m czb.cli production` | affiche le périmètre et les services de la production (`config.yaml`) |
| `python3 -m czb.cli fetch-cache --repo propriétaire/nom` | récupère les copies de travail de la dernière release |
| `python3 -m czb.cli build --scope ... --services ...` | construit les archives PMTiles et le manifest |
| `python3 -m czb.cli verify --out out` | test de cohérence : source contre pixels du PMTiles |

Le périmètre (`--scope`) dit quels pays et quelles régions construire (voir [Périmètres d'essai](#périmètres-dessai)). Les services (`--services`) sont `data` (internet mobile) et `voice` (appels et SMS). L'installation et un exemple de construction locale sont dans le [README](../README.md#lancer-le-pipeline-en-local).

## Étapes d'une construction

1. **Préparation des sources.** Chaque source dit si elle peut être traitée, et récupère ce qui peut manquer (par exemple les fichiers d'OpenCellID, la base d'antennes de l'estimation). Une source impossible à traiter (clé d'accès absente, par exemple) est laissée de côté avec sa raison, et son pays est noté absent dans le manifest.
2. **État des sources.** Il est écrit dans `etat-sources.json`. Il sert à détecter les nouvelles versions (voir [Ce que compare la détection](#ce-que-compare-la-détection)).
3. **Masques des pays.** Le contour de chaque pays est téléchargé et posé sur la grille : le canal B (la valeur de chaque pixel qui porte le pays) reçoit le code du pays. Chaque fichier de contour est supprimé dès que ses géométries sont lues. <!-- À VÉRIFIER : lot en cours -->
4. **Sources, l'une après l'autre.** Chaque module télécharge et décompresse un fichier à la fois, et supprime les fichiers intermédiaires au fur et à mesure. Il reprojette en EPSG:3857, la projection Mercator des cartes en ligne (un code EPSG désigne une projection). Puis il rastérise sur la grille commune, c'est-à-dire qu'il change les polygones en pixels : un pixel est allumé si son centre est dans le polygone (pour une source en image, il prend la valeur de la case qui contient son centre). Si deux niveaux se chevauchent, le plus élevé gagne. Une source n'écrit que dans les pixels de son pays.
5. **Interstices de frontière.** Les petits trous comblés entre deux contours reçoivent un niveau tiré de leurs voisins (voir [Grille commune et frontières](#grille-commune-et-frontières)).
6. **Tuiles.** Les canaux R, G, B et A sont assemblés. Le pipeline fabrique les tuiles du zoom 12, le niveau de détail le plus fin, puis les zooms inférieurs en plus proche voisin (chaque pixel recopie le pixel central du carré qu'il représente, sans moyenne), et écrit les archives PMTiles, découpées si besoin. Il écrit aussi `manifest.json` et `SOURCES.md`. Il écrit les points témoins, des pixels de contrôle décrits plus bas : `temoins.json` pour les sources, `temoins-contours.json` pour les contours, `temoins-attendus.json` pour le minimum attendu par source. Il écrit enfin `rapport-construction.json` (grille, nombre de tuiles, tailles, durées, statistiques), plus les copies de travail `cache-*.tif`. Le logo de licence d'une source qui en a un (celui de l'AGCOM) est copié avec les données. <!-- À VÉRIFIER : lot en cours -->
7. **Test de cohérence** (`verify`), décrit dans [Points témoins et test de cohérence](#points-témoins-et-test-de-cohérence).
8. **Publication**, par le workflow « Données » : une release GitHub `data-AAAA-MM-JJ`, c'est-à-dire une publication du dépôt avec ces fichiers joints.

## Un module par source

Un module est le fichier Python qui sait lire une source.

| Module (`pipeline/czb/sources/`) | Source(s) de `config.yaml` | Ce qu'il lit |
|---|---|---|
| `fr_arcep.py` | `fr_arcep` | fichiers GeoPackage (base de données géographique en un fichier) de l'Arcep, un par opérateur, technologie et usage, listés sur https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/00_Metropole/ (EPSG:2154, champ `niveau` : TBC, BC, CL ; pas de polygone = pas de couverture) |
| `ch_bakom.py` | `ch_bakom` | GeoTIFF (image géoréférencée) de l'OFCOM, trouvé par le catalogue STAC (format standard de catalogue de données géographiques) de data.geo.admin.ch, collection `ch.bakom.mobilnetz-4g` (EPSG:2056, carrés de 100 m, valeurs 0, 2 et 3) |
| `it_agcom.py` | `it_agcom` | service ArcGIS REST (service web de données géographiques) de l'AGCOM, `Grid100/mobile_4G` (EPSG:3857, champ `n_infrastrutture_totali` de 1 à 4) |
| `es_mtd.py` | `es_mtd` | couche ArcGIS Online (la plateforme d'Esri qui sert la couche) du ministère espagnol, `InfoCob4G_2024` (EPSG:4258, champ `COBERTURA` : identifiants fiscaux des opérateurs présents ; champ `CCOM` : communauté autonome) |
| `estimation_opencellid.py` | `ad_estimation`, `mc_estimation` | cellules OpenCellID (codes pays mobiles 213 et 212), relief Copernicus DEM GLO-30, calcul de visibilité de GDAL |

Chaque module commence par un commentaire qui décrit la source telle qu'elle a été vérifiée. Tous suivent l'interface de `base.py` et sont enregistrés dans `__init__.py`. Ils s'appuient sur des outils communs :

- `czb/arcgis.py` : lecture page par page d'un service ArcGIS REST, par identifiant croissant ;
- `czb/net.py` : téléchargements avec nouveaux essais et contrôle de la taille reçue, 7-Zip (l'outil de décompression) ;
- `czb/raster.py` : rastérisation, reprojection ;
- `czb/witness.py` : tirage des points témoins ;
- `czb/cache.py` : copies de travail.

## Grille commune et frontières

- Toutes les sources sont ramenées sur la même grille : EPSG:3857, pixels alignés sur les tuiles du zoom 12. La fenêtre de travail est la plus petite fenêtre alignée sur les tuiles qui contient tous les pays du périmètre. Pour la production, elle fait 45 824 x 47 104 pixels (tuiles du zoom 12 de x 1989 à 2167 et de y 1369 à 1552). <!-- À VÉRIFIER : lot en cours -->
- Les trois canaux sont des fichiers sur disque, jamais chargés en entier en mémoire (environ 2,2 Go par canal pour la grille de production).
- Contours des pays. France : « Contours administratifs » de data.gouv.fr (départements calculés à partir d'ADMIN EXPRESS de l'IGN ; la Corse comprise). Suisse : swissBOUNDARIES3D de swisstopo. Italie : limites administratives de l'ISTAT. Espagne : unités administratives de l'IGN España (une requête par communauté autonome). Andorre et Monaco : OpenStreetMap, la carte libre et collaborative (extraits quotidiens de Geofabrik ; terre ferme seulement pour Monaco). OpenStreetMap étant modifiable par tous, la construction s'arrête si la surface de ces deux contours sort d'une fourchette attendue (455 à 480 km² pour l'Andorre, 1,9 à 2,4 km² pour Monaco).
- Ces contours viennent de producteurs différents et ne coïncident pas exactement. Quand deux pays revendiquent un pixel, le pays le plus haut dans `config.yaml` le garde (France, Suisse, Italie, Espagne, Andorre, Monaco). Les trous fermés de moins de 100 ha entre deux contours sont donnés au pays le moins prioritaire qui les touche ; sur les contours réels, le plus grand interstice mesuré fait 28,5 ha et la plus petite enclave 264 ha. Les trous plus grands sont de vraies enclaves ou des lacs, et restent hors zone.
- Seuls sont comblés les trous bordés par au moins deux entités différentes des contours : deux pays, ou deux régions d'un même pays (les interstices entre les quatre communautés espagnoles restent comblés). Un trou à l'intérieur d'une seule entité reste hors zone : c'est le cas de deux enclaves lombardes à l'intérieur du Piémont, environ 500 pixels. <!-- À VÉRIFIER : lot en cours -->
- Les pixels des interstices comblés prennent, pour chaque opérateur, le plus petit niveau de leurs voisins connus, jusqu'à 16 pixels de distance : dans le doute, on annonce le moins de couverture. Ils gardent le type de source de leur pays (voir [Limites](../README.md#limites)).
- En Suisse, les carrés sans donnée collés à la frontière sont comblés de la même façon, sur deux carrés de profondeur ; les autres pixels du pays sans donnée sont comptés comme non couverts.

Ce que l'on voit le long des frontières, d'après une mesure faite sur les tuiles du 14 novembre 2026 : il n'y a pas de bande blanche artificielle large. Mais une frange de 1 à 3 pixels (30 à 85 m) est plus souvent « sans couverture » côté italien et côté espagnol. Côté italien face à la France, la part des pixels sans couverture vaut 32,7 % au premier pixel, 25,1 % au deuxième, 20,5 % au troisième, puis 17 à 18 % ; côté espagnol, 48,7 % au premier pixel, puis 37,8 %. Les mailles des sources n'arrivent pas exactement au contour (mailles coupées en Espagne, carrés de 100 m en Italie). L'erreur est du côté prudent : au passage d'une frontière, une zone blanche du rapport peut être allongée de quelques dizaines de mètres. <!-- À VÉRIFIER : lot en cours -->

## Points témoins et test de cohérence

Les points témoins sont des pixels tirés au hasard dont on connaît, par ailleurs, la valeur attendue.

- Pour chaque fichier ou chaque emplacement d'une source, 240 pixels du pays sont tirés au hasard et 60 sont gardés, répartis entre les niveaux. Le tirage est reproductible (graine fixe, section `verification` de `config.yaml` : le même hasard à chaque construction).
- Le niveau attendu de chaque point est établi directement dans la source, sans passer par la rastérisation ni la reprojection sur la grille commune : test géométrique exact sur les polygones (France, Italie), case de la grille d'origine (Suisse, Espagne), tableau du calcul (estimation). Un point trop près d'un bord est écarté.
- Les contours sont contrôlés de la même façon : 60 pixels tirés au hasard sur toute la grille et 60 autour de chaque pays. Leur pays attendu (ou aucun) est établi par un test géométrique exact sur les contours, dans l'ordre de priorité ; les points des interstices comblés et ceux trop près d'un contour sont écartés.
- Une fois les archives écrites, `verify` relit tous ces points dans les pixels décodés du PMTiles : niveau dans les canaux R et G, pays dans le canal B. Le job (la tâche du workflow qui fait la construction) échoue au moindre écart, ou si une source, un service ou un emplacement annoncé dans le manifest a moins de 20 points (liste `temoins-attendus.json`).
- Pour l'Espagne, à chaque lecture complète de la couche, le module mesure en plus le calage de la grille des polygones. Il compare aussi sa copie de travail (voir [Copies de travail](#copies-de-travail)) aux polygones en des points tirés au hasard dans chaque région, avec une tolérance de 3 % (des mailles sont coupées par les limites des communes). Un changement de grille de la source arrête la construction.

## L'estimation

Pour l'Andorre et Monaco, il n'existe pas de carte officielle exploitable : la couverture est estimée. Le module `estimation_opencellid` (réglages dans la section `estimation` de `pipeline/config.yaml`) procède ainsi :

1. Il lit les cellules 4G et 5G d'OpenCellID du pays et de ses abords (2 km). Une cellule est l'émetteur d'un opérateur auquel un téléphone se connecte. Il les regroupe par station, puis fusionne en un seul site les points à moins de 300 m l'un de l'autre.
2. Pour chaque site, GDAL calcule sur le relief (Copernicus DEM GLO-30, un modèle du relief, ramené sur la grille du projet), en chaque pixel, la hauteur au-dessus du sol qu'il faudrait pour voir l'antenne, placée à 30 m de haut. Le site est « visible » si cette hauteur ne dépasse pas 1,5 m (un téléphone tenu à la main), et « presque visible » s'il manque moins de 30 m.
3. Un pixel reçoit « bonne couverture » si un site est visible à 5 km au plus, presque visible à 1 km au plus, ou présent à 500 m au plus. Sinon, il reçoit « couverture limitée » avec les distances 15 km, 7,5 km et 2 km. Sinon, « pas de couverture ». « Très bonne couverture » n'est jamais attribué.

Cette règle a été calée sur la France, là où la vérité officielle existe : sites et cartes de l'Arcep dans les Hautes-Alpes et en Ariège, soit 21,7 millions de pixels comparés. Les résultats de ce calage, et la fiabilité des zones estimées, sont dans [Limites](../README.md#limites).

Ce qu'a donné la construction de production n° 2 : <!-- À VÉRIFIER : lot en cours -->

- Andorre (code pays mobile 213, le code qui désigne le pays d'un réseau mobile) : 111 cellules dans le fichier (65 GSM, 41 LTE, 5 UMTS ; GSM désigne la 2G, UMTS la 3G, LTE la 4G), 41 cellules 4G retenues, toutes du même code réseau, regroupées en 12 sites. Résultat : 85,2 % du pays sans couverture, 5,6 % de couverture limitée, 9,2 % de bonne couverture.
- Monaco (code pays mobile 212) : 1 813 cellules dans le fichier (16 GSM, 1 436 LTE, 361 UMTS), 1 433 cellules 4G retenues, toutes du même code réseau, en 109 stations (dont une trop dispersée pour être réunie) et 18 sites. Résultat : 100 % de bonne couverture.
- Aucune cellule « NR » (5G) dans ces deux fichiers : l'estimation repose en pratique sur la 4G.

## OpenCellID et le secret OPENCELLID_TOKEN

OpenCellID est la base d'antennes utilisée par l'estimation. Son téléchargement demande une clé d'accès gratuite, rangée dans le secret `OPENCELLID_TOKEN` du dépôt : une valeur que GitHub donne aux workflows sans jamais l'afficher. La façon de créer ou de remplacer la clé est dans le [README](../README.md#le-secret-opencellid_token).

- Le secret existe depuis le 14 novembre 2026. Le premier téléchargement réel a réussi le même jour (run 43601236437 ; un run est un lancement de workflow). Le module trouve le lien du fichier dans la page des téléchargements d'OpenCellID, qui ne le montre qu'après l'envoi de la clé. Les fichiers des codes pays mobiles 213 (Andorre) et 212 (Monaco) ont été téléchargés et lus.
- Si OpenCellID ne répond pas ou refuse la clé, la construction reprend la copie de travail d'un mois précédent quand elle existe (voir [Copies de travail](#copies-de-travail)).
- Si le secret n'existe pas, ou s'il n'y a pas de copie, elle laisse ces deux pays de côté : ils disparaissent de la carte, et le panneau « Sources » affiche « Pas encore de données pour : Andorre, Monaco ». Un tracé qui y passe est alors compté hors de la zone couverte, et le rapport ne peut pas y signaler la sortie de l'itinérance de l'Union européenne (l'usage de son forfait dans les autres pays de l'Union).
- La clé n'apparaît pas dans les journaux : GitHub masque les secrets, et le module retire la clé de ses propres messages.
- OpenCellID permet deux téléchargements par jour et par fichier : la copie de travail du mois, publiée avec la release, évite de retélécharger lors des constructions suivantes du même mois.
- Le secret est aussi disponible dans le workflow « Sonde », qui vérifie une source avant de l'intégrer (voir [Sonde](#sonde)). Pour une construction locale, il faut la variable d'environnement `OPENCELLID_TOKEN` (voir le [README](../README.md#lancer-le-pipeline-en-local)).

## Copies de travail

Certaines sources coûtent cher à relire : un bon millier de requêtes pour l'Espagne (environ 2,1 millions de polygones). D'autres limitent les téléchargements : OpenCellID permet deux téléchargements par jour et par fichier. Leur résultat, ramené à une image compacte, est publié avec les données sous le nom `cache-<source>.tif` (code dans `pipeline/czb/cache.py`). C'est la copie de travail de la source.

- Avant de construire, le workflow « Données » récupère ces fichiers dans la dernière release (`fetch-cache`). S'ils manquent, les sources sont relues en entier.
- La copie espagnole sert tant que l'édition en ligne, la fenêtre, la grille et la liste des opérateurs n'ont pas changé. Ce chemin a tourné en vrai : la construction n° 2 a repris `cache-es_mtd.tif` (19 712 x 10 752 mailles) et traité l'Espagne en 116,1 s, contre 1 496,8 s pour une lecture complète. <!-- À VÉRIFIER : lot en cours -->
- La copie d'une estimation sert pendant tout le mois où elle a été faite. Si OpenCellID ne répond pas, la copie d'un mois précédent est reprise : mieux vaut une estimation un peu ancienne que pas de pays du tout.
- Le site n'utilise pas ces fichiers : le déploiement ne télécharge que les archives `.pmtiles` et `manifest.json`. Mais ils sont publics, joints à chaque release : la copie espagnole est une image de la couche du ministère (voir [Décisions laissées au propriétaire](../README.md#décisions-laissées-au-propriétaire)), et celles de l'estimation dérivent d'OpenCellID (CC BY-SA 4.0, une licence libre).

## Contenu d'une release et SOURCES.md

Une release de données contient les archives `.pmtiles`, `manifest.json`, `SOURCES.md`, `etat-sources.json`, `rapport-construction.json`, les trois fichiers de points témoins et les copies de travail `cache-*.tif`. Elle contient aussi le fichier du logo de licence de l'AGCOM. <!-- À VÉRIFIER : lot en cours -->

`SOURCES.md` est écrit par `pipeline/czb/notices.py` à partir du manifest. Il redit en clair, pays par pays, la source, sa date, sa licence, la mention à citer, la phrase que la licence impose et le contour du pays. Il est aussi recopié dans le texte de la release : les mentions suivent les données là où elles sont redistribuées. Il reste en français. Il dit en plus, pour chaque source, que les données ont été transformées (rastérisées sur une grille commune, ramenées à des niveaux ou à des seuils). C'est l'indication de modification que demandent les licences CC BY (des licences libres qui demandent de citer la source). Il cite le logo d'une source qui en a un, avec son lien. <!-- À VÉRIFIER : lot en cours -->

## Chiffres de la construction de production

<!-- À VÉRIFIER : lot en cours -->
Construction n° 2, lancée à la main avec le périmètre « production », en forçant la reconstruction, le 14 novembre 2026 (run 43602636462, de 14 h 01 à 14 h 55 UTC, le temps universel). Elle a publié la release `data-2026-11-14-4`, celle qu'utilise le site.

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

Le chemin « aucune source n'a changé » a aussi tourné en vrai, le 14 novembre 2026 (run 43618564529, choix « production », sans forcer). Le journal dit « changed=false (sources inchangées depuis data-2026-11-14-4) ». Le job a duré 41 s, et rien n'a été reconstruit ni publié.

## Les workflows

Un workflow est une tâche automatique de GitHub Actions. Ils sont dans `.github/workflows/`. Certains se lancent à la main depuis l'onglet Actions du dépôt (bouton « Run workflow »), d'autres tout seuls. Chaque lancement est un run, avec sa page ; un run se compose d'un ou de plusieurs jobs, des suites d'étapes qui ont chacune leur journal. Dans le tableau, un push est l'envoi de modifications vers GitHub, sur une branche (une ligne de travail du dépôt ; `main` est la principale). Une pull request est une demande de fusion d'une branche dans une autre. GitHub Pages est l'hébergement de sites statiques de GitHub.

| Workflow | Fichier | Quand | Rôle |
|---|---|---|---|
| Tests | `ci.yml` | à chaque push sur une autre branche que `main` (sauf s'il ne touche que les sondes ou des fichiers `.md`), et sur chaque pull request | teste et construit le site ; teste le pipeline dans l'image GDAL |
| Données | `build-data.yml` | à la main, et le 5 de chaque mois à 3 h 23 UTC | construit les tuiles ; ne publie que la production |
| Déploiement | `deploy.yml` | à chaque push sur `main`, à la main, et relancé par « Données » après chaque nouvelle release | construit le site avec la dernière release de données et le publie sur GitHub Pages |
| Vérification | `verification.yml` | après chaque déploiement, ou à la main (adresse à vérifier) | contrôle le site en ligne dans un vrai navigateur |
| Sonde | `sonde.yml` | à la main (nom du script) | lance un script de vérification d'une source sur une machine de GitHub qui a accès à Internet |

`deploy.yml` déclare aussi un départ à chaque release publiée. Mais une release créée par le workflow « Données » ne lance pas d'elle-même d'autre workflow. C'est une règle de GitHub pour ce qui est fait avec le jeton d'Actions, la clé d'accès que GitHub prête à chaque workflow. C'est donc l'étape « Relancer le déploiement du site » de `build-data.yml` qui lance le déploiement. Si elle échoue, le job échoue et le dit. <!-- À VÉRIFIER : lot en cours -->

### Données

- **Production et essais.** La production est ce qu'indique la section `production` de `pipeline/config.yaml` : le périmètre `complet` (tous les pays), avec les services `data` (internet mobile) et `voice` (appels et SMS). Seul le choix « production » du lancement à la main, et le passage mensuel, sont publiés. Tout autre choix est un essai, même le périmètre `complet` : il est toujours construit, même si rien n'a changé, et vérifié comme la production, puis gardé 7 jours dans l'artefact « donnees » du run (des fichiers téléchargeables depuis la page du run). Un essai ne remplace jamais les données du site.
- **Réglages du lancement à la main** : « Périmètre » (`production`, ou un périmètre d'essai), « Services d'un essai » (`data` ou `data,voice`, ignoré pour la production), « Reconstruire même si aucune source n'a changé ».
- **Étapes** : installation des outils (7-Zip, dépendances Python), lecture de la production, paramètres, tests du pipeline sur données synthétiques, « Une source a-t-elle changé ? », récupération des copies de travail, construction, test de cohérence, conservation du résultat. Pour la production, si une source a changé, un second job publie la release `data-AAAA-MM-JJ` (puis `data-AAAA-MM-JJ-2`, `-3` s'il y en a déjà une ce jour-là). Il recopie `SOURCES.md` dans son texte, ne garde que les trois releases de données les plus récentes, et relance le déploiement. La construction a 340 minutes au plus.
- **Ne reconstruire que si une source a changé.** Chaque release contient `etat-sources.json`, l'état des sources au moment de la construction. Avant de construire, le workflow relit l'état en ligne et le compare. S'il n'a pas changé, rien n'est construit.
- **Passage mensuel.** Le 5 de chaque mois à 3 h 23 UTC. GitHub désactive les workflows planifiés d'un dépôt resté 60 jours sans activité : un petit job réactive ce workflow à chaque passage mensuel.
- **Constructions simultanées.** Les constructions de production (passage mensuel ou choix « production ») passent l'une après l'autre. Les essais peuvent tourner en même temps : ils ne publient rien.

### Ce que compare la détection

Ce que le workflow « Données » surveille pour savoir si une source a changé :

| Source | Ce qui est comparé |
|---|---|
| Arcep | les fichiers de la page de téléchargement (noms, tailles, dates) et le dernier trimestre. Un nouveau trimestre change les noms. |
| OFCOM | la date de l'item STAC et la date de mise à jour de son GeoTIFF |
| AGCOM | le nom du service (il contient la date des données), la couche, la phrase de publication, le nombre de polygones |
| Ministère espagnol | le nom de la couche, sa date de dernière modification, le nombre de polygones par région, la date de modification de l'élément ArcGIS |
| Estimation | seulement ses réglages. OpenCellID change tous les jours, ce n'est pas une raison de tout reconstruire. L'estimation est refaite quand une construction a lieu un autre mois. |

L'état compare aussi le périmètre, les services et le numéro de version du pipeline (`pipeline/czb/__init__.py`) : augmenter ce numéro provoque une reconstruction au passage suivant. Une source qui devient disponible, ou indisponible, change aussi l'état.

Pour l'Espagne, le pipeline lit en plus la page du ministère (clé `url` de la source `es_mtd`) et relève les identifiants des éléments ArcGIS qu'elle cite. Si la page répond, contient des identifiants, et ne cite plus celui de `item_url`, la détection échoue avec un message clair : « nouvelle édition probable : mettre à jour layer_url, item_url, name et data_date de es_mtd ». Si la page ne répond pas, ou ne contient aucun identifiant, c'est un simple avertissement, et l'état ne change pas. L'état publié avec la release actuelle n'a pas ce champ : la première détection qui suit verra donc un changement, et une reconstruction aura lieu. <!-- À VÉRIFIER : lot en cours -->

Ce qui n'est pas surveillé (contours des pays, nouvelle édition de la carte espagnole, adresse de la prochaine édition italienne) se met à jour à la main : voir le [README](../README.md#ce-qui-se-fait-à-la-main).

### Déploiement

1. tests du site (`npm test`) ;
2. téléchargement, dans `public/data/`, des archives `.pmtiles` et du `manifest.json` de la release de données la plus récente (par date de publication) ;
3. contrôles : le manifest doit être lisible et toutes les archives qu'il cite doivent être présentes. Sinon le déploiement échoue, et le site déjà en ligne garde ses données. S'il n'existe aucune release de données, il échoue aussi, sauf s'il a été lancé à la main avec l'option « Publier même s'il n'existe aucune release de données » (le site est alors publié sans couche réseau) ;
4. construction du site (`npm run build`), qui écrit aussi la liste de la coque hors ligne dans `dist/sw.js` (les fichiers que le mode hors ligne enregistre, voir [architecture.md](architecture.md#le-service-worker)) ;
5. contrôle des tailles : chaque fichier sous 95 Mo, le site complet sous 900 Mo (en millions d'octets, comme le pipeline) ;
6. publication sur GitHub Pages ;
7. vérification du site en ligne (workflow « Vérification »).

### Vérification

Le script `e2e/verif.mjs` ouvre le site dans Chromium (le navigateur libre sur lequel Chrome est bâti), avec Playwright, un outil qui pilote un vrai navigateur. Il l'ouvre sur un écran d'ordinateur (1 280 x 800) et sur un écran de téléphone (412 x 915, comme un Pixel 9a), en français, en allemand et en espagnol, avec un passage au catalan et à l'italien.

- Il contrôle le chargement du fond de carte et des données de couverture, la recherche et l'import d'un GPX (le fichier d'un parcours), dont un GPX « difficile » : ISO-8859-1, éléments préfixés, point (0, 0), altitude manquante. Il contrôle aussi le rapport, le GPX enrichi, le profil au clavier, les appels et SMS quand ils sont publiés, le fond suisse, le panneau Sources et ses mentions, et l'absence d'erreur JavaScript.
- D'autres scénarios jouent le mode hors ligne : préparation d'un tracé entièrement en France, redémarrage sans réseau, `?lang=es` sans réseau, suppression confirmée. D'autres jouent des tuiles de couverture illisibles puis « Réessayer », une nouvelle publication des données pendant la visite, les fonds enregistrés selon leur fournisseur, le pied de carte, « Ma position » et le rapport réduit. D'autres enfin jouent le fond Automatique, un style du Plan IGN lent ou refusé, et les deux GPX de test de part et d'autre d'une frontière quand l'Italie et l'Espagne sont publiées. Certains services y sont simulés.
- Le script utilise `samples/test-alpes.gpx` quand les données publiées couvrent la région de son départ, sinon un court tracé écrit dans le script. Les captures d'écran sont gardées 14 jours dans l'artefact « captures ».

Le 14 novembre 2026, sur le site en ligne (commit `deadf53`, un commit étant un état enregistré du code ; données `data-2026-11-14-4`), 101 contrôles sur 101 ont réussi (run 43620100839). <!-- À VÉRIFIER : lot en cours -->

Les commandes pour lancer cette vérification depuis son ordinateur sont dans le [README](../README.md#vérifier-dans-un-navigateur).

### Sonde

Une sonde sert à vérifier une source avant de l'intégrer : une adresse, un identifiant de couche, un schéma (`ogrinfo`, `gdalinfo` : des outils de GDAL qui décrivent un fichier ou un service) ou une licence. Le script choisi dans `pipeline/sondes/` tourne dans l'image GDAL, avec les fonctions communes de `_lib.sh`, et on lit le résultat dans le journal du job. Le secret `OPENCELLID_TOKEN` y est disponible, masqué dans les journaux.

## Périmètres d'essai

Un essai se lance depuis l'onglet Actions : « Données », « Run workflow », puis un périmètre d'essai et les services (`data`, ou `data,voice`). Les périmètres sont définis dans la section `scopes` de `pipeline/config.yaml` :

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

Un essai n'est jamais publié. Pour le regarder, télécharger l'artefact « donnees » depuis la page du run (il est gardé 7 jours), copier ses fichiers `.pmtiles` et `manifest.json` dans `public/data/`, puis lancer `npm run dev` (voir [Développement local](../README.md#développement-local)).

Pour un nouveau pays, ajouter un périmètre dans `scopes` et son nom dans la liste `options` de `.github/workflows/build-data.yml`, pour pouvoir l'essayer seul.

## Ajouter une source en détail

Les étapes sont dans le [README](../README.md#ajouter-ou-changer-une-source). Voici ce que le pipeline attend.

### Déclarer la source

Dans `pipeline/config.yaml` :

- le pays, dans `countries` : `name` (pour `SOURCES.md`), `code` (de 1 à 15, unique : c'est la valeur du canal B), `eu_roaming`, `mask` (le contour et sa mention `credit`), `operators` si la source ne les distingue pas, `slots` (4 au plus : des opérateurs nommés, ou des seuils `min_operators`) et `sources` ;
- la source, dans `sources` : `country`, `type` (0, 1 ou 2), `name`, `attribution`, `url`, `licence`, `licence_url`, éventuellement `licence_notice`, `licence_logo` et `licence_logo_url`, `services` (avec la technologie), `levels_kind` (`four`, `three` ou `binary`), `resolution_m`, plus les réglages propres au module (adresses, champs, valeurs). Une source désigne son module par la clé `module`, ou à défaut par son propre nom : c'est ainsi qu'un même module sert l'Andorre et Monaco ;
- les traductions facultatives `name_i18n` et `licence_i18n` de la source, et `text_i18n` dans la mention du contour (dictionnaires es, ca, it, de). Les noms propres et les formules de licence imposées ne se traduisent pas. <!-- À VÉRIFIER : lot en cours -->

### Écrire le module

Le module va dans `pipeline/czb/sources/`. On part d'un module proche, et on le commence par un commentaire qui décrit la source vérifiée. Il hérite de `Source` (`base.py`), c'est-à-dire qu'il en reprend le comportement commun, et fournit :

- `remote_state()` : un petit état de la source en ligne (dates, tailles, nombres d'entités), qui sert à détecter une nouvelle version ;
- `process()` : il remplit la grille commune avec `merge_level`, avec des niveaux de 0 à 3, uniquement dans les pixels de son pays. Il ajoute des points témoins pour chaque service et chaque emplacement (20 au moins pour chacun). Il renvoie au moins la date des données ;
- si besoin, `available()` (par exemple quand une clé d'accès manque) et `prepare()`. Une source qui se révèle inutilisable en cours de route lève `SourceUnavailable` : la construction continue sans elle, et un pays qui n'a plus de source est retiré de la construction.

Le module est enregistré dans `pipeline/czb/sources/__init__.py` (dictionnaire `REGISTRY`). Son test, sur des données synthétiques et sans réseau, va dans `pipeline/tests/`. Exemples : `test_ch_bakom.py` (GeoTIFF fabriqué), `test_it_agcom.py` et `test_es_mtd.py` (faux service ArcGIS de `fake_arcgis.py`).

## Réglages du pipeline

- Les limites de taille et le nombre de points témoins sont dans `pipeline/config.yaml` (sections `limits` et `verification`), comme les réglages de l'estimation (section `estimation`). Les limites et l'emprise (la zone couverte) sont décrites dans [Changer l'emprise](../README.md#changer-lemprise).
- Le seuil de 100 ha des interstices est `GAP_MAX_HA` dans `pipeline/czb/masks.py`, et la propagation sur 16 pixels se règle dans `extrapolate_marked` (`pipeline/czb/layers.py`).
- Le nom sous lequel le pipeline se présente aux serveurs des sources est `USER_AGENT`, dans `pipeline/czb/net.py` (voir [Décisions laissées au propriétaire](../README.md#décisions-laissées-au-propriétaire)).
