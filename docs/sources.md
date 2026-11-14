# Sources

Ce document dit d'où viennent les données du site, sous quelles conditions elles sont réutilisées, comment le pipeline les transforme et quelles sont leurs limites. Il tient aussi l'inventaire des sources examinées pour les pays frontaliers.

État au 14 novembre 2026. Les licences et les conditions d'usage ont été lues les 13 et 14 novembre 2026 par des sondes : de petits scripts lancés sur les machines de GitHub Actions, car l'environnement de développement ne joint pas ces sites (scripts dans `pipeline/sondes/`). Ce qui n'a pas pu être vérifié est marqué « non vérifié ». Dans les citations, les tirets longs des textes d'origine sont remplacés par des traits d'union.

## Ce que montre la carte

- La carte montre une couverture **théorique** : simulée ou déclarée par les opérateurs, ou estimée là où il n'existe pas de source officielle exploitable. Ce n'est pas une mesure. Le panneau « Sources » du site le rappelle : « Couverture théorique, des écarts locaux sont possibles. »
- Chaque pixel porte la nature de sa source :
  - **officielle, par opérateur** : on sait quel opérateur couvre (France, Espagne) ;
  - **officielle, agrégée** : on sait combien de réseaux couvrent, pas lesquels (Suisse, Italie) ;
  - **estimée** : calculée par le projet à partir de positions d'antennes et du relief (Andorre, Monaco). Ces zones sont hachurées sur la carte et marquées « estimée » dans le rapport.
- Niveaux : 0 pas de couverture, 1 couverture limitée, 2 bonne couverture, 3 très bonne couverture. Seule la France a les quatre niveaux. Les sources suisse, italienne et espagnole disent seulement « couvert » ou « non couvert » : pour ces pays, « bonne couverture » veut dire « couvert » sur la carte et dans le rapport, sans indication de qualité. Les zones estimées ont trois niveaux et jamais « très bonne ».
- « Tous opérateurs » est le meilleur niveau parmi les opérateurs du pays, calculé par le site. À l'étranger, la couverture réelle d'un visiteur dépend des accords d'itinérance de son opérateur.
- Toutes les sources sont ramenées sur une même grille : les tuiles du zoom 12, dont le pixel mesure 38,2 m en projection Web Mercator, soit 26 à 28 m au sol à ces latitudes.
- Appels et SMS : seulement en France.

## Synthèse par pays

| Pays | Source retenue | Nature | Technologie | Niveaux | Date des données | Résolution | Licence |
|---|---|---|---|---|---|---|---|
| France (Corse comprise) | Arcep, « Mon réseau mobile » | officielle, par opérateur | internet : 4G ; appels et SMS : 2G et 3G | 4 | 30 juin 2026 | polygones | Licence Ouverte / Open Licence (Etalab) |
| Suisse | OFCOM, atlas de la large bande | officielle, agrégée | 4G | couvert ou non | 30 avril 2026 | 100 m | utilisation libre, source à citer |
| Italie (Piemonte, Valle d'Aosta, Liguria) | AGCOM, Broadband Map | officielle, agrégée | 4G | couvert ou non | 27 janvier 2026 | 100 m | CC BY 4.0, avec logo obligatoire |
| Espagne (Aragón, Cataluña, Navarra, País Vasco) | Ministerio para la Transformación Digital y de la Función Pública, « Mapa de Servicios de Banda Ancha Móvil 2024 » | officielle, par opérateur | 4G | couvert ou non | 30 juin 2024 | environ 28 m x 38,5 m | aucune licence attachée au jeu ; conditions générales de réutilisation du site du ministère |
| Andorre | estimation : OpenCellID et Copernicus DEM | estimée | 4G et 5G | 3 | pas encore construite | calcul au pixel de la grille, relief à 30 m | CC BY-SA 4.0, mention Copernicus |
| Monaco | estimation : OpenCellID et Copernicus DEM | estimée | 4G et 5G | 3 | pas encore construite | calcul au pixel de la grille, relief à 30 m | CC BY-SA 4.0, mention Copernicus |

Officielles : France, Suisse, Italie, Espagne. Estimées : Andorre et Monaco, faute de source officielle exploitable. L'estimation est prête dans le pipeline mais n'a pas encore été construite (voir « Estimation »).

## France

### Source

- Éditeur : Arcep. Jeu « Mon réseau mobile », couvertures théoriques : https://www.data.gouv.fr/datasets/mon-reseau-mobile
- Fichiers lus : https://data.arcep.fr/mobile/couvertures_theoriques/last/Metropole/00_Metropole/, nommés `{année}_T{trimestre}_couv_Metropole_{OP}_{TECHNO}_{USAGE}.gpkg.7z`, avec OP = OF (Orange), SFR0 (SFR), BOUY (Bouygues Telecom), FREE (Free). Internet mobile : fichiers `4G_data`. Appels et SMS : fichiers `2G3G_voix`. Huit fichiers en tout.
- Contenu : GeoPackage (fichier de données géographiques) en Lambert-93 (EPSG:2154), un multipolygone par département et par niveau (schéma vérifié sur l'édition du 2e trimestre 2026, d'après l'en-tête du module). Champs : operateur, date, techno, usage, niveau, dept, operateur_infra, operateur_commercial. Le champ `niveau` vaut TBC (très bonne couverture), BC (bonne couverture) ou CL (couverture limitée). Là où il n'y a pas de polygone, il n'y a pas de couverture.

### Date des données

Édition du 2e trimestre 2026, données au 30 juin 2026. L'Arcep publie une édition par trimestre. Chaque mois, le pipeline compare la liste des fichiers (noms, tailles, dates) à celle de la dernière construction.

### Licence

« Licence Ouverte / Open Licence » (Etalab) : https://www.etalab.gouv.fr/licence-ouverte-open-licence

Le texte de la Licence Ouverte 2.0 (https://raw.githubusercontent.com/etalab/licence-ouverte/master/LO.md) laisse au réutilisateur la liberté « de la communiquer, la reproduire, la copier » et « de la diffuser, la redistribuer, la publier et la transmettre, de l'exploiter à titre commercial », à une condition :

> mentionner la paternité de l'«Information» : sa source (a minima le nom du « Concédant ») et la date de la dernière mise à jour de l'« Information » réutilisée.

Le texte cité est celui de la version 2.0. La version attachée au jeu de l'Arcep n'est pas vérifiée : les notes de recherche donnent seulement le nom « Licence Ouverte / Open Licence ».

### Mention affichée dans le site

- Pied de carte : « Couverture : Arcep ».
- Panneau « Sources » : « Arcep, Mon réseau mobile : couvertures théoriques », avec un lien vers la fiche data.gouv.fr ; date des données ; méthode « Officielle, par opérateur » ; niveaux ; technologies ; licence avec son lien ; opérateurs (Orange, SFR, Bouygues Telecom, Free).

### Méthode

Module `pipeline/czb/sources/fr_arcep.py`.

1. Le pipeline lit la page d'index de data.arcep.fr. Pour chaque opérateur et chaque service, il doit y trouver exactement un fichier, sinon il s'arrête.
2. Il télécharge un fichier à la fois, le décompresse et supprime l'archive. Le GeoPackage est supprimé dès qu'il a été traité.
3. Il vérifie le fichier : une seule couche, champ `niveau` présent, système de coordonnées renseigné. Une valeur de niveau inconnue arrête la construction.
4. Il traduit les niveaux (CL = 1, BC = 2, TBC = 3), reprojette les polygones vers la grille du zoom 12 et allume un pixel quand son centre est dans un polygone. Si deux niveaux se chevauchent, le plus élevé gagne. Chaque opérateur a son emplacement, c'est-à-dire une place réservée dans chaque pixel des tuiles : Orange, SFR, Bouygues Telecom, Free.
5. Points témoins (points de contrôle) : 60 points par fichier, tirés au hasard puis répartis entre les niveaux. Leur niveau est calculé dans le fichier source par un test géométrique exact (les points à moins de 50 cm d'un bord sont écartés), puis comparé aux pixels relus dans les archives publiées. Le moindre écart fait échouer la construction.

Construction du 14 novembre 2026 (France entière, internet mobile et appels et SMS) : grille de 43 008 x 41 472 pixels, 8 fichiers Arcep (2,5 Go compressés), 17 324 tuiles, 332 Mo en 6 archives PMTiles (la plus grosse : 69,8 Mo), 45 minutes, 480 points témoins sans écart.

### Limites

- Couverture théorique simulée par les opérateurs, pas une mesure de terrain.
- Une édition par trimestre, publiée après la date des données : au 14 novembre 2026, la carte montre la situation au 30 juin 2026.
- Résolution : les fichiers sont des polygones. `config.yaml` retient 50 m, valeur que les notes de recherche ne documentent pas (non vérifié).
- La partie française du Léman est hors zone (voir « Contours des pays »).

## Suisse

### Source

- Éditeur : OFCOM (Office fédéral de la communication). Atlas de la large bande : https://www.bakom.admin.ch/en/broadband-atlas
- Jeu : disponibilité des réseaux mobiles 4G, collection `ch.bakom.mobilnetz-4g` du catalogue STAC (catalogue de données géographiques) de la Confédération : https://data.geo.admin.ch/api/stac/v0.9/collections/ch.bakom.mobilnetz-4g/items
- Contenu : un GeoTIFF (image géoréférencée) `mobilnetz-4g_2056.tif`, en CH1903+ / LV95 (EPSG:2056), carrés de 100 m. Valeurs : 0 = pas de couverture ; 2 = couvert par moins de 3 opérateurs ; 3 = couvert par les 3 opérateurs (Swisscom, Sunrise, Salt). D'après l'en-tête du module, vérifié sur le lisez-moi de l'OFCOM, il s'agit de la couverture extérieure annoncée par les opérateurs.

### Date des données

Édition du 30 avril 2026 (date de l'item STAC). Le pipeline surveille la date de l'item et celle du fichier.

### Licence

`config.yaml` : « Utilisation libre, source à citer (géodonnées de la Confédération) ». Page : conditions générales de l'infrastructure fédérale de données géographiques (« FSDI »), https://www.geo.admin.ch/en/general-terms-of-use-fsdi, en vigueur depuis le 1er janvier 2025. Mot pour mot :

> The acquisition and use of data or services is free of charge, subject to the provisions on fair use.

> Geodata in machine-readable form is freely available on the Federal Spatial Data Infrastructure FSDI. The geoservices are made available within the framework of the FSDI via geo.admin.ch. The data obtained may be processed, analysed and published in accordance with their terms of use, along with the inclusion of further data.

> In publications and analyses based on the FSDI, any reference to the source must be made in accordance with the terms of use of the corresponding dataset, as is done in the lower right corner of the map viewer.

Les conditions propres au jeu de l'OFCOM, auxquelles renvoie ce texte (fiche geocat.ch, rubrique « Legal restrictions »), n'ont pas été lues : non vérifié. La page a été lue en anglais ; elle précise que la version allemande fait foi.

### Mention affichée dans le site

- Pied de carte : « Couverture : OFCOM ».
- Panneau « Sources » : « OFCOM, atlas de la large bande : disponibilité des réseaux mobiles 4G », avec un lien vers l'atlas ; licence avec un lien vers les conditions ; note « couvert ou non couvert » ; opérateurs du pays (Swisscom, Sunrise, Salt) ; avertissement : la Suisse ne fait pas partie de l'itinérance de l'Union européenne.

### Méthode

Module `pipeline/czb/sources/ch_bakom.py`.

1. Le pipeline lit la collection STAC. Il attend exactement un item et un GeoTIFF, sinon il s'arrête.
2. Il télécharge le GeoTIFF, vérifie le système de coordonnées (EPSG:2056) et les valeurs. Une valeur inconnue arrête la construction : on ne devine pas son sens.
3. Il traduit chaque carré en nombre minimal d'opérateurs : 0, 1 (pour « moins de 3 ») ou 3.
4. Les carrés sans donnée collés à la frontière sont comblés en deux passes (200 m au plus) avec la plus petite valeur de leurs voisins : dans le doute, on annonce le moins de couverture.
5. Deux emplacements : « au moins un opérateur » et « les trois opérateurs ». Un carré couvert reçoit le niveau 2 (« couvert »), sinon 0. L'image est ramenée sur la grille en plus proche voisin : chaque pixel prend la valeur du carré qui contient son centre. Les pixels suisses sans donnée comptent comme non couverts.
6. Points témoins : niveau lu directement dans la grille de la source (points à moins de 1 m d'un bord de carré écartés), 60 par emplacement.

Construction du 14 novembre 2026 (Suisse seule) : 60,3 millions de pixels, 1,1 Mo, 88 secondes, 120 points témoins sans écart.

### Limites

- Source agrégée : on sait combien d'opérateurs couvrent, pas lesquels. La valeur « moins de 3 » ne dit pas s'il y en a un ou deux ; le pipeline la traduit par « au moins un ». On ne peut pas choisir Swisscom, Sunrise ou Salt.
- Pas de niveau de qualité : « bonne couverture » veut dire « couvert ».
- Pas de carte des appels et SMS : le pipeline ne lit que la couche 4G.
- Couverture théorique annoncée par les opérateurs.
- Hors itinérance de l'Union européenne : le rapport avertit quand le tracé passe en Suisse.

### Autres sources examinées et pourquoi elles ne sont pas retenues

- Positions des stations de base de l'OFCOM (collection `ch.bakom.standorte-mobilfunkanlagen`, un GeoJSON de 22 732 points avec opérateur, technologie et classe de puissance ; conditions opendata.swiss : « Open use. Must provide the source. You may use this dataset for non-commercial purposes. You may use this dataset for commercial purposes. You must provide the source (author, title and link to the dataset). ») : ce sont des positions d'antennes, pas une carte de couverture. Elles serviraient à une estimation par opérateur si un jour il en fallait une. Inutile tant que la carte officielle existe.
- Couche 5G de l'OFCOM (`ch.bakom.mobilnetz-5g`, identifiant tiré du cahier des charges, non vérifié) : non lue par le pipeline, qui s'en tient à la 4G comme pour les autres pays à source officielle. Non examinée dans les notes de recherche.

## Italie

### Source

- Éditeur : AGCOM (Autorità per le garanzie nelle comunicazioni). Broadband Map, couche « 4G » : https://www.agcom.it/broadband-map ; portail de données ouvertes : https://geo3.agcom.it/opendata/
- **Pas de fichier téléchargeable.** Le menu « Download > Rete mobile » du portail ne donne qu'un code à envoyer par courriel à opendata.bbmap@agcom.it. Le pipeline lit donc, sans clé d'accès, le service ArcGIS REST public (un service web qui renvoie à la demande les données d'une carte) d'où vient la carte du portail : couche 0 de https://geo3.agcom.it/MapET-SFS/rest/services/Grid100/mobile_4G/MapServer (couche « mobile_4G_260127_260205 »). Ce n'est pas la voie de téléchargement que désigne le portail (la demande par courriel) : ce choix revient au propriétaire du projet.
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

- Les conditions nomment l'adresse `www.agcom.it/broadbandmap`, qui répond 404. Dans la page des conditions, le logo et le nom « BroadbandMap di Agcom » renvoient à https://maps.agcom.it/, en maintenance les 13 et 14 novembre 2026 comme dans des copies archivées du 6 juillet et du 22 septembre 2026. Le site du projet renvoie donc à https://www.agcom.it/broadband-map, qui répond et mène au portail.
- Aucune clause n'interdit l'accès automatisé, aucune ne le décrit non plus.

### Mention affichée dans le site

- Pied de carte : « Couverture : BroadbandMap di Agcom (CC BY 4.0) ».
- Panneau « Sources » : nom de la source avec un lien vers https://www.agcom.it/broadband-map ; licence avec un lien vers les conditions ; la phrase placée sous le logo ; **le logo de l'AGCOM** exigé par la licence (image JPEG de 221 x 110 pixels fournie par l'AGCOM, fichier `public/licences/agcom-bbmap.jpg`) ; note « couvert ou non couvert ». Le manifest (fichier `manifest.json` qui décrit les tuiles pour le site) porte aussi l'adresse https://maps.agcom.it/ pour le logo, mais le site n'en fait pas encore un lien (état du code au 14 novembre 2026).

### Méthode

Modules `pipeline/czb/sources/it_agcom.py` et `pipeline/czb/arcgis.py`.

1. Détection d'une nouvelle édition : description du service (« mobile_4G_20260127 »), nom de la couche, phrase de date et nombre d'entités des trois régions. La date des données est lue dans cette description du service.
2. Lecture : requêtes filtrées sur `COD_REG IN (1,2,7)`, 250 entités par page, triées par `fid` croissant, envoyées l'une après l'autre avec une pause d'une seconde. Ce serveur ignore sans prévenir le paramètre de décalage habituel (`resultOffset`) : on pagine donc par identifiant. À la fin, le nombre d'entités lues doit être égal au nombre annoncé par le service.
3. Chaque page est un fichier temporaire, supprimé dès que la suivante est demandée. Une valeur hors de 1 à 4 arrête la construction.
4. Les polygones sont déjà en EPSG:3857 : ils sont rastérisés directement sur la grille (centre du pixel). Une entité de valeur n écrit « couvert » (niveau 2) dans les emplacements « au moins 1 réseau » à « au moins n réseaux ». Sans polygone, le niveau reste 0.
5. Points témoins : niveau attendu calculé sur les polygones par un test géométrique exact, 60 par emplacement.

Construction du 14 novembre 2026 (Italie seule, trois régions) : 4 697 polygones lus en 19 requêtes, 46,7 millions de pixels, 2,9 Mo, 149 secondes, 240 points témoins sans écart.

### Limites

- Source agrégée : un nombre de réseaux, pas leur nom. La carte officielle intitule la couche « Copertura 4G (rev. 5/2/2026) - N. Operatori di rete » et le champ « N. infrastrutture di rete » : c'est un nombre d'opérateurs de réseau. Aucune source lue ne nomme ces opérateurs ni ne dit comment sont comptés deux opérateurs qui partagent un même réseau. Le site dit « au moins N réseaux ».
- Pas de niveau de qualité : « bonne couverture » veut dire « couvert ».
- Pas de données 2G ou 3G récentes (voir plus bas) : pas d'appels et SMS pour l'Italie.
- Couverture théorique déclarée par les opérateurs. Le critère de couverture (seuil de signal, extérieur ou intérieur) n'est défini dans aucune source lue. L'AGCOM prévient : « I dati di output sono derivati da elaborazioni statistiche (media statistica campionaria) e/o grafiche dei dati forniti dai singoli operatori. Le rappresentazioni forniscono una descrizione media complessiva, che può discostarsi, anche in modo significativo, dalla prestazione offerta al singolo utente. »
- Parts du territoire couvertes par au moins un réseau, calculées pendant la recherche : Piemonte 94,5 %, Valle d'Aosta 92,8 %, Liguria 95,9 %. À lire comme une couverture théorique, surtout en montagne.
- Données de janvier 2026. Éditions mobiles repérées d'après les dates des services publics de l'AGCOM : 2016, 2019, fin 2022, janvier 2026, soit environ une tous les trois ans. Aucun texte lu n'annonce la fréquence des mises à jour.
- Carrés de 100 m découpés aux limites communales. Leurs sommets sont décalés de (54,4 ; 64,7) m par rapport à la grille de 100 m de l'EPSG:3035, pour une raison inconnue : compter une incertitude de position de l'ordre d'un carré.
- Le long des frontières, les polygones de l'AGCOM sont découpés sur des limites communales qui ne coïncident pas exactement avec le contour retenu pour l'Italie. Quel que soit ce contour, une bande de quelques dizaines de mètres peut rester « sans polygone » parce qu'elle sort de l'emprise des données, et non parce qu'il n'y a pas de réseau : cela peut créer de fausses zones blanches sur une crête frontalière.
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
- Opérateurs, d'après la table officielle du ministère : A78923125 Telefónica Móviles España (Movistar), A82009812 Orange Espagne, A80907397 Vodafone España, A82528548 Xfera Móviles. Digi n'apparaît pas dans les données.

### Date des données

« cobertura referida a 30 de junio de 2024 » (texte de la carte). Édition 2024 : carte d'origine publiée le 4 juin 2025, copie européenne de mai 2026. Le rapport de couverture 2025 a été présenté le 6 mai 2026, mais la carte détaillée liée depuis le site du ministère est toujours l'édition 2024 au 14 novembre 2026. Le ministère publie un rapport de couverture par an (« publica anualmente el informe sobre la cobertura de la banda ancha en España ») ; aucun calendrier de mise à jour de la carte elle-même n'a été lu.

### Licence

**Aucune licence n'est attachée au jeu lui-même** : les champs de licence des éléments ArcGIS et la mention de droits des couches sont vides. Les « Términos y condiciones » affichés dans la carte ne contiennent aucune interdiction de réutilisation. La réutilisation repose sur les conditions générales de réutilisation publiées dans les mentions légales du site du ministère : https://digital.gob.es/nota-legal. Mot pour mot (extraits) :

> Las presentes condiciones generales permiten la reutilización de los documentos sometidos a ellas para fines comerciales y no comerciales.

> La reutilización autorizada incluye, a modo ilustrativo, actividades como la copia, difusión, modificación, adaptación, extracción, reordenación y combinación de la información.

> Está prohibido desnaturalizar el sentido de la información.

> Debe citarse la fuente de los documentos objeto de la reutilización. Esta cita podrá realizarse de la siguiente manera: "Origen de los datos: Ministerio para la Transformación Digital y de la Función Pública"

> Debe mencionarse la fecha de la última actualización de los documentos objeto de la reutilización, siempre cuando estuviera incluida en el documento original.

> No se podrá indicar, insinuar o sugerir que el Ministerio para la Transformación Digital y de la Función Pública, titular de la información reutilizada participa, patrocina o apoya la reutilización que se lleve a cabo con ella.

Ce qu'il faut savoir : ces conditions s'appliquent aux « documentos sometidos a ellas », sans en donner la liste. **Aucun texte ne dit explicitement que cette carte en fait partie.** La carte se présente comme publiée « dentro del sitio web de la Secretaría de Estado de Telecomunicaciones e Infraestructuras Digitales » et elle est liée depuis digital.gob.es : c'est une lecture raisonnable, pas une autorisation écrite. La couche n'est pas non plus dans le portail de données ouvertes du ministère (d'après `config.yaml`, qui s'appuie aussi sur l'article 48 de la loi 11/2022).

Une contre-vérification du 14 novembre 2026 a relu au BOE (journal officiel espagnol) deux textes qui jouent en sens contraire :

- en faveur de la réutilisation, la loi générale des télécommunications, Ley 11/2022, article 48 « Estudios geográficos » : « La información que no esté sujeta a confidencialidad comercial será accesible de conformidad con la Ley 37/2007, de 16 de noviembre, sobre reutilización de la información del sector público. » ;
- en sens inverse, la loi 37/2007 sur la réutilisation exclut « Los documentos sobre los que existan derechos de propiedad intelectual o industrial por parte de terceros ». Les données viennent des opérateurs : rien de lu ne dit si cette exclusion s'applique.

Si la lecture du projet était contestée, il faudrait écrire au ministère ou passer l'Espagne en « estimée ». Les conditions générales d'Esri pour ArcGIS Online n'ont pas été lues (non vérifié).

### Mention affichée dans le site

- Pied de carte : « Couverture : Origen de los datos: Ministerio para la Transformación Digital y de la Función Pública ».
- Panneau « Sources » : nom de la source avec un lien vers la page du ministère ; date des données (juin 2024) ; licence « Condiciones generales de reutilización del ministerio : source et date à citer (pas de licence propre à cette couche) » avec un lien vers les mentions légales ; note « couvert ou non couvert » ; opérateurs.

### Méthode

Module `pipeline/czb/sources/es_mtd.py`.

1. Le pipeline vérifie d'abord le schéma de la couche (champs `OBJECTID`, `COBERTURA`, `CCOM`, système EPSG:4258). Un changement arrête la construction.
2. Détection d'une nouvelle édition : nom de la couche, date de dernière modification des données, date de modification de l'élément ArcGIS, nombre de polygones de chaque région.
3. **Copie de travail.** Les quatre régions comptent environ 2,1 millions de polygones, soit un bon millier de requêtes. Le résultat est donc gardé sous forme d'image à la maille d'origine, avec un bit par opérateur : le fichier `cache-es_mtd.tif`, publié avec les données dans la release (mécanisme commun : `pipeline/czb/cache.py`). Tant que l'édition en ligne, l'emprise et la liste des opérateurs ne changent pas, la construction suivante repart de cette image sans relire le service.
4. Sinon, lecture région par région (CCOM 02, 09, 15, 16), polygones dont `COBERTURA` n'est pas vide, 2 000 par page, par `OBJECTID` croissant, l'une après l'autre avec une pause d'une demi-seconde. Le nombre lu doit égaler le nombre annoncé. Un identifiant d'opérateur inconnu arrête la construction. Les polygones sans commune (CCOM vide : mer, versants français et andorran) ne sont pas lus.
5. Les polygones sont rastérisés sur la grille d'origine de la source, un passage par opérateur. Cette grille a le pas de l'image tuilée du ministère (0,000346111018645788°), dont le coin nord-ouest sert de point de référence, mais elle est décalée d'une fraction de maille (0,35 en longitude et 0,49 en latitude en 2024). Le module mesure ce décalage sur les sommets des polygones à chaque lecture. Il s'arrête si les sommets ne dessinent plus une grille au pas annoncé, ou si deux régions n'ont pas le même calage. La copie de travail garde son calage exact.
6. Contrôle : pour chaque région, 1 200 points tirés au hasard sont comparés aux polygones, avec 3 % d'écart toléré. Les mailles coupées par une limite de commune ne sont pas des carrés entiers : sur les données réelles, 0,7 % des points tombent dans un tel éclat ; une erreur de calage en donnerait bien plus. Au-delà de la tolérance, la construction s'arrête.
7. Pour chaque opérateur, l'image est ramenée sur la grille du projet en plus proche voisin. « Présent » donne le niveau 2 (« couvert »), sinon 0.
8. Points témoins : niveau lu dans la grille d'origine, 60 par opérateur.

Chiffres de construction : pas encore disponibles à la date de rédaction.

### Limites

- Source binaire : la présence est un seuil de signal, sans niveau de qualité. Méthodologie du ministère : « Los cálculos de cobertura se basarán en una probabilidad de 95 % del tiempo y de las ubicaciones. En el caso de redes móviles, se empleará una carga nominal de la celda del 60 %. » et « 1. Presencia, entendida como la zona donde: a. Frecuencias < 1 GHz RSRP >= -115 dBm b. Frecuencias > 1 GHz RSRP >= -117 dBm La capa englobará todas las tecnologías 4G sin distinguir entre ellas. » (méthodologie 2025 ; la méthodologie 2024, lue par reconnaissance de caractères, contient le même passage). Pas comparable aux quatre niveaux de l'Arcep. « Bonne couverture » veut dire « couvert ».
- Données au 30 juin 2024 : plus de deux ans à la date de rédaction.
- Couverture théorique déclarée par les opérateurs. Conditions de la carte : « Los datos representados se procesan a partir de los proporcionados por los operadores de telecomunicaciones individuales, llevándose a cabo para cierta información una descripción media, que puede diferir, incluso significativamente, del servicio ofrecido al usuario individual. »
- Sens du champ opérateur : la carte parle des opérateurs « cuya infraestructura presta servicio » ; la page du ministère dit qu'elle inclut aussi des opérateurs servis par des accords de partage. Xfera ne couvre que 9,7 % de la surface des quatre régions (Telefónica 80,5 %, Orange 74,0 %, Vodafone 70,2 %), ce qui ressemble plutôt à son réseau propre. La vue « Tous opérateurs » est donc la plus fiable. La vue par opérateur peut sous-estimer la couverture des clients de marques hébergées.
- Digi et les opérateurs virtuels n'ont pas de couche propre.
- Ni 2G ni 3G : pas d'appels et SMS pour l'Espagne.
- Hébergement ArcGIS Online : les identifiants ont déjà changé une fois (copie de mai 2026). Des couches d'essai « 2026 » existent sur le même compte ; elles ne sont pas liées depuis le site du ministère et ne sont pas utilisées.

### Autres sources examinées et pourquoi elles ne sont pas retenues

- Image tuilée du même ministère (`Cob4G_2024`) : présence d'au moins un réseau 4G, en accord à 99,77 % avec la couche par opérateur sur la zone d'essai. Moins riche (agrégée) et non utilisée par le pipeline, qui ne reprend d'elle que le pas et le coin de sa grille. La vue « Tous opérateurs » se calcule à partir de la couche par opérateur.
- datos.gob.es, base historique de couverture fixe et mobile du ministère : tableaux par commune, pas une carte.
- Portail Conectemos du ministère : agrégats par commune de 2021 à 2025 (XLSX), pas une carte.
- Aragón Open Data, « Cobertura móvil real por tecnología en Aragón » (CC BY 4.0, dernier jeu : juin 2026) : mesures réelles par mailles de 500 m, seulement là où les réseaux sont utilisés, tous opérateurs confondus, Aragon seul. Pas une carte de couverture ; complément possible.
- Catalunya, « Cobertura mòbil 112 » (GeoTIFF de 30 m, Llicència oberta d'ús d'informació - Catalunya) : Catalogne seule, fiche de 2022, valeurs 0 à 5 non documentées.
- Catalunya, données de l'application « Cobertura Mòbil » (2015 à 2019) : mesures ponctuelles, trop anciennes.
- Navarra, « Observatorio de Banda Ancha » : haut débit fixe seulement.
- Euskadi : rien trouvé dans le catalogue national.
- « Infoantenas » (stations radio, ministère) : service de consultation, pas un jeu de données, sans mention de réutilisation. Non moissonné : pas de scraping.
- Sur datos.gob.es, une demande d'ouverture des données de connectivité mobile et d'antennes porte l'état « No viable ».

## Andorre

### Source

- **Aucune source officielle exploitable : la couverture est estimée** (voir « Estimation »).
- Codes réseau : un seul code sous le MCC 213, « 213 03 Mobiland » (liste de l'UIT, position au 15 novembre 2023). Que Mobiland soit la marque mobile d'Andorra Telecom, opérateur unique du pays : non vérifié par sonde. Le pipeline range toutes les cellules du MCC 213 dans un seul emplacement, tous réseaux du pays confondus.
- Cellules OpenCellID (toute la base, page de statistiques lue le 14 novembre 2026) : 1 249, dont 344 en 4G (LTE) et 11 en 5G (NR).

### Date des données

Pas encore construite. Ensuite : le mois de la construction, avec les cellules vues par OpenCellID dans les 18 derniers mois.

### Licence

Zones estimées sous CC BY-SA 4.0 (elles dérivent d'OpenCellID), avec la mention obligatoire de Copernicus. Détail et citations dans « Estimation ».

### Mention affichée dans le site

Valable aussi pour Monaco, dès que ces pays seront construits :

- Pied de carte : « Couverture : Estimation : OpenCellID (CC BY-SA 4.0), Copernicus DEM ».
- Panneau « Sources » : « Estimation : antennes OpenCellID et relief Copernicus DEM », avec un lien vers https://opencellid.org ; licence « CC BY-SA 4.0 (zones estimées, dérivées d'OpenCellID) » avec un lien vers https://creativecommons.org/licenses/by-sa/4.0/ ; la mention en anglais d'OpenCellID et de Copernicus (voir « Estimation ») ; le texte sur les zones estimées cité ci-dessous ; l'avertissement d'itinérance (l'Andorre et Monaco ne font pas partie de l'itinérance de l'Union européenne).
- Tant qu'un pays n'est pas construit, le panneau indique « Pas encore de données pour : » suivi de son nom.

Texte affiché dans le panneau « Sources » pour les zones estimées :

> Faute de carte officielle, la couverture est calculée à partir de positions d'antennes relevées par des bénévoles (OpenCellID) et du relief. Ce n'est pas une carte d'opérateur : une antenne absente de la base crée une fausse zone blanche, une antenne mal placée déplace les limites de plusieurs centaines de mètres. Ne comptez pas sur une zone estimée pour un appel d'urgence.

### Méthode

Celle de « Estimation », avec le fichier OpenCellID du MCC 213.

### Limites

- Estimation, pas une carte d'opérateur (voir « Estimation »).
- Peu de matière : 344 cellules 4G et 11 cellules 5G dans toute la base, et moins encore dans l'export des 18 derniers mois.
- Hors itinérance de l'Union européenne : le rapport avertit quand le tracé passe en Andorre.

### Autres sources examinées et pourquoi elles ne sont pas retenues

- Govern d'Andorra : pas de portail de données ouvertes (https://www.govern.ad/dades-obertes répond 404, aucun lien vers des données ouvertes, les télécommunications ou la couverture dans le portail) ; le portail de transparence (https://www.transparencia.ad/) n'a aucun lien vers des données ouvertes, des statistiques ou les télécommunications ; dadesobertes.ad et opendata.ad ne répondent pas.
- IDE Andorra, infrastructure de données spatiales du Govern : 835 fiches de métadonnées et 960 couches WMS passées en revue, sans couverture mobile, sans réseau de télécommunications, sans registre d'antennes. Ses contenus sont de plus sous tous droits réservés (avis légal cité ci-dessous).
- Carte de couverture d'Andorra Telecom : site d'opérateur, exclu par les règles du projet (pas de scraping).
- Carte espagnole : elle contient des polygones sur les versants andorrans (entités sans commune), volontairement non lus. C'est la couverture des réseaux espagnols, pas celle des réseaux andorrans.

Avis légal de l'IDE Andorra (https://www.cartografia.ad/avis-legal), mot pour mot :

> No es podran fer actes totals o parcials de reproducció, publicació, tractament informàtic, distribució, difusió, transformació, compilació, modificació, distribució o comunicació pública dels webs sense el consentiment previ i per escrit del Govern .

## Monaco

### Source

- **Aucune source officielle de couverture : la couverture est estimée** (voir « Estimation »).
- Codes réseau : « 212 10 Monaco Telecom », seul code sous le MCC 212 (liste de l'UIT, position au 15 novembre 2023). La rubrique « Monaco » de l'UIT cite aussi trois codes français utilisés à Monaco : 208 01 (Orange/Monaco Télécom), 208 10 (SFR), 208 20 (Bouygues Telecom).
- Le pipeline ne lit que le MCC 212 : l'estimation ne repose donc que sur les cellules de Monaco Telecom. Les réseaux français présents ou captés à Monaco ne sont pas pris en compte, et la vue « Tous opérateurs du pays » n'est, à Monaco, que celle de Monaco Telecom.
- Cellules OpenCellID (toute la base) : 381, dont 55 en 4G et aucune en 5G.

### Date des données, licence, mention, méthode

Comme pour l'Andorre, avec le fichier OpenCellID du MCC 212.

### Limites

- Très peu de matière : 55 cellules 4G dans toute la base.
- Monaco Telecom seulement (voir plus haut). Le code 10 existe sous les deux MCC (212 10 Monaco Telecom, 208 10 SFR) : distinguer un jour les opérateurs demanderait de regrouper par paire (MCC, MNC).
- Hors itinérance de l'Union européenne.
- Contour : terre ferme seulement (voir « Contours des pays »).

### Autres sources examinées et pourquoi elles ne sont pas retenues

- cartoradio.mc (site du Gouvernement Princier) : couche officielle « Sites Radioélectriques » (opérateur, orientation des secteurs, technologies 2G à 5G), lisible sans clé d'accès, mais sans aucune licence (champs vides) et sans mentions légales. Les conditions du portail du Gouvernement (https://www.gouv.mc/mentions-legales-cgu, citées ci-dessous) interdisent toute réutilisation sans autorisation expresse. Elles visent le portail gouv.mc ; cartoradio.mc n'en a pas de propres. Lecture prudente : pas de licence, donc pas de droit de réutilisation. Cette couche ferait une bien meilleure base d'estimation qu'OpenCellID, mais il faudrait une autorisation écrite de l'administration monégasque.
- data.gouv.mc : en maintenance (erreur 503) à chaque essai du 14 novembre 2026, de 10 h 47 à 11 h 43 UTC, et aucune copie archivée par Internet Archive. Son contenu n'a donc pas pu être lu : sur ce point, la conclusion pour Monaco reste provisoire.
- Carte de couverture de Monaco Telecom : site d'opérateur, exclu.

Conditions générales du portail du Gouvernement Princier, mot pour mot :

> Toute forme d’utilisation, de représentation, de transformation, de reproduction, d’adaptation ou de diffusion, intégrale ou partielle, de tout élément ou du contenu de ce Site sur quelque support et par quelque procédé que soit est prohibée, à défaut d’autorisation expresse de l’Administration et constitue une infraction pénalement sanctionnée par les Cours et Tribunaux monégasques.

## Estimation (Andorre, Monaco)

Là où aucune source officielle n'est exploitable, la couverture est estimée à partir des positions de cellules d'OpenCellID et du relief Copernicus DEM GLO-30. Module `pipeline/czb/sources/estimation_opencellid.py`, réglages dans le bloc `estimation` de `config.yaml`. Ces zones sont marquées « estimées » partout : hachures sur la carte, mention dans le rapport, type de source 2 dans les tuiles.

**État au 14 novembre 2026 : le module est prêt, mais l'estimation n'a pas encore été construite, car le secret `OPENCELLID_TOKEN` n'existe pas encore dans le dépôt.** Sans cette clé, le pipeline laisse l'Andorre et Monaco de côté et le manifest les signale comme manquants.

### OpenCellID

- Base ouverte de positions de cellules, alimentée par des mesures de bénévoles : https://opencellid.org. Des fichiers par pays sont proposés (« We provide country files, a full dataset and daily change files. »). Format documenté (https://docs.opencellid.org/docs/downloads/database-format) : CSV compressé de 14 colonnes, radio, mcc, net, area, cell, unit, lon, lat, range, samples, changeable, created, updated, averageSignal. Le module attend un fichier par code MCC, par exemple « 213.csv.gz » : ce nommage n'a pas pu être vérifié (voir « Téléchargement » plus bas).
- Ce ne sont pas des positions de pylônes : « The coordinates are estimated cell positions calculated from contributed observations. They are not surveyed mast coordinates or a device's live GPS position. Estimates can differ from the physical antenna site, especially where observations are sparse or concentrated along a road. »
- La base est incomplète : « A download is not a complete inventory of all cells. »
- Exports et quota : « We generate exports daily by 02:00 GMT. They include towers observed in the last 18 months. You can download each file twice per day from our download page. »

Licence, mot pour mot (https://docs.opencellid.org/docs/attribution) :

> OpenCellID data is licensed under CC BY-SA 4.0, including API results, dataset downloads and daily changes.

> Attribution required. When sharing OpenCellID data under CC BY-SA 4.0, credit OpenCelliD, link to the source and license, and indicate any changes.

> Where to place the credit. Make the credit visible where users encounter the data [...]. Website or map: On the page displaying the data, beside the map or visualization.

> Other license terms. When sharing adapted material, follow the license's ShareAlike requirements. Retain supplied copyright, license and warranty notices, and do not restrict recipients' licensed rights. See the full license terms, including its database provisions.

- **Partage à l'identique.** La licence CC BY-SA 4.0 (section 3(b)) impose que le matériel adapté soit diffusé sous une licence aux mêmes éléments : « The Adapter's License You apply must be a Creative Commons license with the same License Elements, this version or later, or a BY-SA Compatible License. » Les zones estimées publiées (tuiles de l'Andorre et de Monaco, copies de travail) sont donc sous CC BY-SA 4.0 : https://creativecommons.org/licenses/by-sa/4.0/. Les autres sources gardent leur propre licence : le manifest porte une licence par source. C'est l'analyse du projet, pas un avis juridique, et le choix de publier ces zones sous CC BY-SA 4.0 revient au propriétaire du projet.
- Modifications apportées aux données d'OpenCellID, comme la licence demande de l'indiquer : seules les cellules 4G et 5G sont retenues ; elles sont regroupées par site ; la couverture est calculée par visibilité sur le relief ; seules les zones estimées sont publiées, pas les positions des cellules. Dans le panneau « Sources », le crédit est suivi du texte sur les zones estimées, qui décrit la méthode dans ses grandes lignes ; le détail des modifications est dans ce document.
- Mention affichée dans le panneau « Sources » (texte de `config.yaml`) : « Cell tower data from OpenCellID, licensed under CC BY-SA 4.0. Produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30. » Pied de carte : « Estimation : OpenCellID (CC BY-SA 4.0), Copernicus DEM ».

Téléchargement : la page https://opencellid.org/downloads.php ne montre ses liens qu'après l'envoi de la clé, et la forme exacte de ces liens n'est pas documentée publiquement. Le module envoie donc la clé à cette page dans le corps de la requête (pas dans l'adresse de la page), puis suit le lien qui contient « 213.csv.gz » (Andorre) ou « 212.csv.gz » (Monaco). Si ce lien contient lui-même la clé, elle reste masquée dans les journaux. Le module vérifie ensuite que la réponse est bien un fichier compressé : sans clé valide, le service répond quand même « 200 » avec un message d'erreur (essai sans clé sur l'adresse https://opencellid.org/ocid/downloads?type=mcc&file=213.csv.gz : `{"status":"error","message":"INVALID_DATA"}`). **Faute de clé, le téléchargement n'a pas pu être essayé** : la forme des liens sera lue dans la page au premier passage.

### Copernicus DEM GLO-30

- Modèle numérique de surface (bâtiments et végétation compris), au pas d'une seconde d'arc (environ 30 m), version 2021, référence verticale EGM2008. Tuiles d'un degré, en accès libre sans compte dans le dépôt public `copernicus-dem-30m`, par exemple https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N45_00_E006_00_DEM/Copernicus_DSM_COG_10_N45_00_E006_00_DEM.tif (gabarit `dem_url` dans `config.yaml`). Pas de tuile en mer : l'altitude y vaut 0.
- Licence : « Licence for Copernicus DEM instance COP-DEM-GLO-30-F Global 30m Full, Free & Open » (https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf, copie livrée avec chaque tuile). Mot pour mot :

> The Licensor grants to the User the following non-exclusive rights of use regarding the Copernicus WorldDEM-30: (a) reproduction; (b) distribution; (c) communication to the General Public; (d) adaptation, modification and combination with other data and information.

> The use rights granted under this licence are free of charge to the User.

- Mention obligatoire pour des données adaptées (article 6 (b)) et phrase exigée par l'article 6 (c), toutes deux reprises dans le panneau « Sources » :

> produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved

> The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30

- Le projet ne redistribue pas le relief, seulement un résultat calculé avec lui. Il ne doit pas laisser croire qu'il est approuvé par le fournisseur ou par Copernicus (article 6 (d)).

### Méthode en clair

1. **Cellules.** Le pipeline lit le fichier OpenCellID du pays (MCC 213 pour l'Andorre, 212 pour Monaco). Il garde les cellules 4G (LTE) et 5G (NR) situées dans l'emprise du pays élargie de 2 km, car un fichier de pays peut contenir des cellules voisines.
2. **Regroupement par site.** Les cellules 4G d'une même station (même code réseau, même identifiant de cellule divisé par 256) sont réunies à la médiane de leurs positions : les secteurs entourent le pylône. Si elles sont dispersées sur plus de 2 km, elles sont traitées une à une. Ensuite, les points à moins de 300 m les uns des autres forment un seul site. Une cellule 5G rejoint le site situé à moins de 300 m, ou forme le sien. Toutes les cellules du pays vont dans un seul emplacement : pas de distinction par opérateur. Ce regroupement par division de l'identifiant par 256 suit la numérotation des réseaux 4G : non vérifié sur de vraies données OpenCellID.
3. **Relief.** Les tuiles Copernicus sont ramenées sur la grille du projet (interpolation bilinéaire), la mer à 0.
4. **Visibilité.** Pour chaque site, le calcul de visibilité de GDAL (`ViewshedGenerate`) donne, pour chaque pixel, la hauteur au-dessus du sol qu'il faudrait pour voir l'antenne. Réglages : antenne à 30 m, téléphone à 1,5 m, coefficient de courbure et de réfraction 0,75, portée 15 km. On en tire trois distances par pixel : au site visible le plus proche, au site « presque visible » le plus proche (il manque au plus 30 m de hauteur pour le voir) et au site le plus proche, visible ou non.
5. **Règle à trois niveaux.**
   - « bonne » (niveau 2) : un site visible à 5 km au plus, ou presque visible à 1 km au plus, ou un site à 500 m au plus ;
   - sinon « limitée » (niveau 1) : un site visible à 15 km au plus, ou presque visible à 7,5 km au plus, ou un site à 2 km au plus ;
   - sinon « pas de couverture » (niveau 0).
   - Jamais « très bonne » : l'estimation ne sait pas faire cette distinction (voir le calage).
6. **Copie de travail.** Le résultat est gardé (`cache-ad_estimation.tif`, `cache-mc_estimation.tif`) et repris pendant le mois en cours, car OpenCellID limite chaque fichier à deux téléchargements par jour. Si le téléchargement échoue, l'estimation d'un mois précédent est reprise. L'estimation ne déclenche pas de reconstruction à elle seule : elle est rafraîchie quand une autre source change, au plus une fois par mois. Exception : la création du secret `OPENCELLID_TOKEN` change l'état des sources et déclenche donc la construction suivante.
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

Ce que le calage ne dit pas : il porte sur la France, deux départements et deux opérateurs ; la « vérité » est elle-même une simulation d'opérateur ; il utilise des positions de sites, alors qu'OpenCellID donne des positions de cellules estimées ; les vraies erreurs d'OpenCellID sont inconnues, et probablement biaisées vers les routes et les vallées, où passent les contributeurs. La qualité réelle avec de vraies données OpenCellID n'est donc pas connue. Les notes de recherche proposent une auto-évaluation à chaque construction (la même chaîne appliquée aux cellules françaises d'OpenCellID sur un département frontalier, puis comparée à l'Arcep) : elle n'est pas encore en place.

### Limites à annoncer

- Ce n'est pas une carte d'opérateur. Une antenne absente de la base crée une fausse zone blanche ; une antenne mal placée déplace les limites de plusieurs centaines de mètres.
- Ni la puissance, ni l'orientation des antennes, ni la végétation fine, ni l'intérieur des bâtiments ne sont pris en compte. Le relief est un modèle de surface : forêts et bâtiments masquent un peu plus que le sol nu (effet non mesuré).
- Très peu de cellules : Andorre, 344 en 4G et 11 en 5G ; Monaco, 55 en 4G et aucune en 5G, dans toute la base. Il se peut même qu'un pays n'ait pas de fichier dans l'export des 18 derniers mois.
- Trois niveaux seulement. Internet mobile seulement : les appels et SMS ne sont pas estimés.
- La date affichée est le mois de la construction ; les cellules sont celles vues dans les 18 derniers mois.
- Ne pas compter sur une zone estimée pour un appel d'urgence.

## Contours des pays

Chaque pays a un contour, qui dit quels pixels lui appartiennent. Module `pipeline/czb/masks.py`, adresses dans `config.yaml`.

### Une source par pays

- **France** : contours des départements d'Etalab, dérivés d'ADMIN EXPRESS de l'IGN : https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/departements-5m.geojson.gz. Départements dont le code a deux caractères : métropole et Corse, 96 départements. Licence : non vérifiée (les notes de recherche ne la citent pas). Mention prévue dans `config.yaml` : « Contours administratifs (Etalab), d'après ADMIN EXPRESS de l'IGN ».
- **Suisse** : swisstopo, swissBOUNDARIES3D, état au 1er janvier 2026 (fichier du 17 décembre 2025) : https://data.geo.admin.ch/ch.swisstopo.swissboundaries3d/swissboundaries3d_2026-01/swissboundaries3d_2026-01_2056_5728.gpkg.zip, couche `tlm_landesgebiet`, filtre `icc = 'CH'`. Précision annoncée (https://www.swisstopo.admin.ch/en/landscape-model-swissboundaries3d) : « Geometric accuracy ± 0.5 m in position and elevation ». Conditions (https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices) : « The free geodata and geoservices of swisstopo may be used, distributed and made accessible. Furthermore, they may be enriched and processed and also used commercially. A reference to the source is mandatory. » Mention prévue dans `config.yaml` : « © swisstopo, swissBOUNDARIES3D », avec un lien vers ces conditions.
- **Italie** : ISTAT, limites administratives non généralisées au 1er janvier 2026 : https://www.istat.it/storage/cartografia/confini_amministrativi/non_generalizzati/2026/Limiti01012026.zip, fichier `Reg01012026/Reg01012026_WGS84.shp`, filtre `COD_REG IN (1, 2, 7)`. Licence CC BY 4.0 (https://www.istat.it/note-legali/) : « Salvo diversa indicazione, tutti i contenuti pubblicati su questo sito sono soggetti alla licenza Creative Commons - Attribuzione - versione 4.0. » et « Attribuzione - Devi riconoscere una menzione di paternità adeguata, fornire un link alla licenza e indicare se sono state effettuate delle modifiche. » Mention prévue dans `config.yaml` : « Istat, Confini delle unità amministrative a fini statistici al 1° gennaio 2026, CC BY 4.0, données modifiées », avec un lien vers https://creativecommons.org/licenses/by/4.0/deed.it.
- **Espagne** : IGN España, API OGC Features, collection `administrativeunit`, une requête par communauté : https://api-features.ign.es/collections/administrativeunit/items?f=json&nationalcode=34020000000 (Aragón), et de même avec 34090000000 (Cataluña), 34150000000 (Navarra), 34160000000 (País Vasco). Métadonnées du 23 février 2026 : « BDLJE CC-BY 4.0 ign.es ». Licence d'usage de l'IGN (https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf) : « Cuando el usuario licenciado genere una obra derivada [...] se añadirá «Obra derivada de» delante de la expresión general ». Mention prévue dans `config.yaml` : « Obra derivada de BDLJE CC-BY 4.0 ign.es », avec un lien vers cette licence ; la date à y ajouter n'a pas été établie (non vérifié).
- **Andorre** : OpenStreetMap, relation 9407, extrait quotidien de Geofabrik : https://download.geofabrik.de/europe/andorra-latest.osm.pbf, couche `multipolygons`, filtre `osm_id = '9407'`.
- **Monaco** : OpenStreetMap, relation 36990 (terre ferme, sans les eaux territoriales), extrait quotidien de Geofabrik : https://download.geofabrik.de/europe/monaco-latest.osm.pbf. Le pipeline assemble les chemins de cette relation en polygones (2,08 km²).
- Licence d'OpenStreetMap (https://www.openstreetmap.org/copyright) : « OpenStreetMap is open data, licensed under the Open Data Commons Open Database License (ODbL) by the OpenStreetMap Foundation (OSMF). » et « You are free to copy, distribute, transmit and adapt our data, as long as you credit OpenStreetMap and its contributors. » Mention prévue dans `config.yaml` pour l'Andorre et Monaco : « © OpenStreetMap contributors (ODbL 1.0) », avec un lien vers https://www.openstreetmap.org/copyright. La question du partage à l'identique d'une base dérivée (le code pays des tuiles, pour l'Andorre et Monaco) n'a pas été tranchée. Une ligne directrice de la fondation OpenStreetMap, relue pendant la recherche, distingue une base de données d'un « Produced Work » (œuvre produite à partir des données) ; des tuiles faites pour l'affichage relèveraient plutôt du second cas. C'est une lecture, pas un fait établi : le texte de l'ODbL lui-même n'a pas été relu.
- **Garde-fous** : pour chaque contour, le nombre d'entités attendu (1 pour la Suisse et l'Andorre, 3 pour l'Italie, 4 pour l'Espagne) ; pour les deux contours tirés d'OpenStreetMap, base modifiable par tous, la surface attendue (Andorre entre 455 et 480 km², Monaco entre 1,9 et 2,4 km²). Hors de ces bornes, la construction s'arrête. Pendant la recherche, le serveur de Geofabrik a parfois refusé la connexion depuis les machines de GitHub : le pipeline fait jusqu'à sept essais pour ces fichiers.

Où sont ces mentions : le manifest reprend la mention de chaque contour, mais le site ne l'affiche pas encore (état du code au 14 novembre 2026). Elles figurent dans ce document, lié depuis le panneau « Sources » (« Détail des sources, des licences et des méthodes »). Pour swisstopo, la page d'aide (https://www.swisstopo.admin.ch/en/source-reference-ogd-swisstopo) admet ce cas : « Acceptable: The source is mentioned in a central location on a web page listing all sources used in the map application or service. » La licence de l'IGN España demande en principe une mention « visible junto con los datos, de forma legible y a pie de mapa » et n'admet une liste de crédits qu'« En caso de imposibilidad manifiesta y justificable » : point à trancher par le propriétaire.

### Traitement des frontières

Les contours viennent de producteurs différents et ne coïncident pas. Largeur moyenne des recouvrements, mesurée pendant la recherche : 0,1 m entre la Suisse et la France, 16,7 m entre l'Italie et la France, 38,3 m entre l'Andorre et l'Espagne. Le contour de l'ISTAT est le moins fin face à la France : par endroits, jusqu'à 200 ou 300 m de trou et 400 à 600 m de recouvrement.

- **Priorité.** Les pays sont rangés dans `config.yaml` dans cet ordre : France, Suisse, Italie, Espagne, Andorre, Monaco. Là où deux contours se recouvrent, le premier pays garde le pixel. La frontière affichée est donc celle du pays prioritaire : Etalab face à tous les voisins de la France, swisstopo face à l'Italie, IGN España face à l'Andorre. Au mont Blanc, 77,7 ha revendiqués par les deux contours vont à la France ; 3 144 pixels revendiqués par l'Espagne et l'Andorre vont à l'Espagne.
- **Petits interstices comblés.** Les trous fermés de moins de 100 ha entre deux contours sont donnés au pays le moins prioritaire qui les touche : le contour du pays prioritaire fait foi, c'est l'autre qui s'étend jusqu'à lui. Pourquoi : sinon un tracé qui passe la frontière traverserait quelques mètres « hors zone ». Le seuil de 100 ha sépare sans ambiguïté les interstices (le plus grand mesuré fait 28,5 ha) des vraies enclaves (la plus petite fait 263,8 ha). Essai pendant la recherche, sur la grille réelle avec les départements frontaliers et une version d'essai de la même règle : 8 502 pixels sans pays coincés entre deux pays avant comblement, 14 292 pixels gagnés (dont 13 309 pour l'Italie, face à la France et à la Suisse), 22 pixels coincés après. Deux de ces trous (18,0 et 19,3 ha) ne sont pas des interstices entre pays : ce sont des morceaux de Lombardie entourés par le Piémont dans le contour de l'ISTAT. Le comblement les donne à l'Italie, qui est le bon pays, et environ 500 pixels de Lombardie entrent ainsi dans la zone couverte.
- **Niveau des pixels comblés.** Aucune source ne les décrit. Ils prennent le plus petit niveau de leurs voisins du même pays (dans le doute, on annonce le moins de couverture), de proche en proche jusqu'à 16 pixels ; au-delà, ils restent à 0.
- **Seuls les trous fermés sont comblés.** Un comblement plus large aurait rempli des morceaux de mer, par exemple 5,53 ha au sud de Monaco.
- **Hors zone** (trous de 100 ha ou plus, laissés vides) : la partie française du Léman (le contour du département 74, Haute-Savoie, s'arrête à la rive, alors que la partie suisse du lac est dans la zone) ; les enclaves de Treviño (province de Burgos, dans le Pays basque) et de Valle de Villaverde (Cantabrie), noms déduits des coordonnées ; Büsingen (enclave allemande en Suisse) et Campione d'Italia (enclave italienne en Suisse). Le Liechtenstein est hors zone. L'enclave espagnole de Llívia, en France, est bien dans le contour espagnol.
- **Bords propres à chaque source** : en Suisse, les carrés sans donnée collés à la frontière sont comblés (voir « Suisse ») ; en Italie, une bande d'incertitude subsiste (voir « Italie ») ; en Espagne, les polygones sans commune ne sont pas lus.
- **Contrôle.** Des pixels tirés au hasard (60 sur toute la grille et 60 autour de chaque pays) reçoivent leur pays attendu par un test géométrique exact sur les contours, en suivant l'ordre de priorité ; un pixel hors de tous les contours n'a pas de pays. Les pixels des interstices comblés ne servent pas à ce contrôle. Ces points sont ensuite relus dans les tuiles publiées : le moindre écart fait échouer la construction.

## Fonds de carte et recherche de lieux

Adresses et identifiants des couches de fond : `src/map/basemaps.ts`. Adresses de la recherche de lieux : `src/config.ts`. Tous ces services sont gratuits et sans clé pour l'usage du site.

### Plan IGN (vectoriel, avec repli en images), photos aériennes, estompage

- Éditeur : IGN, Géoplateforme. Plan IGN vectoriel : styles https://data.geopf.fr/annexes/ressources/vectorTiles/styles/PLAN.IGN/classique.json et `standard.json`, tuiles https://data.geopf.fr/tms/1.0.0/PLAN.IGN (adresse donnée par le style lui-même). Repli en images si le style vectoriel ne se charge pas : WMTS https://data.geopf.fr/wmts, couche `GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2`. Photos aériennes : même WMTS, couche `ORTHOIMAGERY.ORTHOPHOTOS`. Estompage du relief, en option et en France seulement : couche `ELEVATION.ELEVATIONGRIDCOVERAGE.SHADOW`, style `estompage_grayscale`.
- Conditions : CGU de la Géoplateforme, version du 15 octobre 2024, https://cartes.gouv.fr/cgu/ : « Sur la Géoplateforme, l'utilisation des géodonnées et géoservices est gratuite (sauf licence spécifique). »
- Licence des données : « Licence Ouverte / Open License (compatible ODC-BY, CC-BY 2.0) » dans les métadonnées du Plan IGN (`IGNF_PLAN-IGN`) et des photos aériennes (`IGNF_BD-ORTHO`). Pour l'estompage, le service ne donne aucun lien de métadonnées : c'est la règle par défaut des CGU qui s'applique (« A défaut, la Licence Ouverte / Open Licence - Etalab s'applique sur ce jeu de données. »), non vérifié couche par couche.
- Mention affichée : « © IGN ».
- Limites : tuiles vectorielles, 400 requêtes par seconde et par adresse IP ; WMTS « Non soumis à limite d'usage ». Au-delà d'une limite, le service répond par une erreur 429 et bloque 5 secondes. En cas d'usage abusif, l'IGN peut limiter ou bloquer l'accès.

### swisstopo

- Éditeur : Office fédéral de topographie swisstopo. Carte nationale en couleurs, couche `ch.swisstopo.pixelkarte-farbe`, WMTS https://wmts.geo.admin.ch.
- Conditions : celles de la FSDI (voir « Suisse ») et celles des géodonnées gratuites de swisstopo (https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices), citées dans « Contours des pays ».
- Mention affichée : « © swisstopo » (forme officielle : « ©swisstopo »).
- Limites : « fair use » (usage raisonnable) de 1'200 requêtes par minute et 631 millions par an pour le WMTS. Le texte ne dit pas si la limite se compte par application, par utilisateur ou par adresse IP ; lecture prudente : pour tous les visiteurs du site réunis. Le texte ajoute : « Note on web scraping: Automatic parsing of geoservices via bots with high query intensities is to be avoided. The download service should be used to obtain the datasets outside the context of the web services (use in offline systems, databases, etc.). » Service fourni au mieux (« best effort »), sans garantie.

### IGN España

- Éditeur : Instituto Geográfico Nacional. « Cartografía Ráster de España del IGN », couche `MTN`, WMTS https://www.ign.es/wmts/mapa-raster.
- Licence : CC BY 4.0, licence d'usage de l'IGN fondée sur l'Orden FOM/2807/2015 (https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf) : « el uso de los productos y servicios de información geográfica del IGN definidos en el ámbito de la Orden FOM/2807/2015 conlleva la aceptación por el usuario de una licencia CC-BY 4.0 ». Et : « Esta mención de atribución obligatoria se mostrará visible junto con los datos, de forma legible y a pie de mapa, imagen, presentación o ventana de visualización. »
- Mention affichée : « CC BY 4.0 ign.es » (formule donnée par le service lui-même). Forme longue : « Cartografía Ráster de España del IGN (capa MTN), CC BY 4.0 ign.es ».
- Limites : aucune limite de débit publiée, rien sur le cache ni sur l'usage hors ligne.

### Fond OpenStreetMap (OpenTopoMap)

- Tuiles `https://{a|b|c}.tile.opentopomap.org/{z}/{x}/{y}.png` (forme donnée par OpenTopoMap) : carte topographique faite à partir des données OpenStreetMap, par un service bénévole. En mode Auto, c'est le fond des pays sans fond national dans le site : Italie, Andorre, Monaco.
- Licence (https://opentopomap.org/about) : « OpenTopoMap steht unter der Lizenz CC-BY-SA. Das bedeutet, dass die Karte kostenlos und frei verwendet werden darf, solange stets Namensnennung erfolgt und die Weitergabe unter gleichen Bedingungen möglich ist. »
- Mention demandée : « Kartendaten: © OpenStreetMap-Mitwirkende, SRTM | Kartendarstellung: © OpenTopoMap (CC-BY-SA) ». Mention affichée aujourd'hui : « © OpenStreetMap, SRTM | © OpenTopoMap (CC BY-SA) », plus courte et sans liens. Écart relevé pendant la recherche.
- Limites : aucun chiffre, mais pas de téléchargements en masse et aucune garantie : « Dies ist jederzeit gerne möglich, sofern unser Server z.B. durch Massendownloads nicht zu stark beansprucht wird. Außerdem kann keinerlei Ausfallsicherheit garantiert werden. » Le serveur a été réduit le 5 janvier 2026 et un passage aux tuiles vectorielles est annoncé : ce fond pourra devoir être remplacé.
- Les tuiles standard d'OpenStreetMap (tile.openstreetmap.org) ne sont pas utilisées. Leur politique interdit le préchargement : « Offline use is not permitted on tile.openstreetmap.org. »

### Recherche de lieux

- France : autocomplétion du géocodage de la Géoplateforme (IGN), https://data.geopf.fr/geocodage/completion, sous les CGU de la Géoplateforme. Limite : 10 requêtes par seconde et par adresse IP. Le site n'interroge qu'à partir de 3 caractères et 350 ms après la dernière frappe, soit au plus environ 3 requêtes par seconde.
- Étranger : Photon (komoot), https://photon.komoot.io/api/, données OpenStreetMap (ODbL). Conditions : « You can use the API for your project, but please be fair - extensive usage will be throttled. We do not guarantee for the availability and usage might be subject of change in the future. » Langues acceptées : allemand, anglais, français ; sinon, noms locaux. Le site envoie aussi le centre et l'emprise de la carte, pour que les lieux proches passent en premier. Les résultats situés en France sont écartés, car l'IGN les fournit.
- Mention affichée : sous les résultats, « Résultats : IGN et © les contributeurs d'OpenStreetMap » ; dans le panneau « Sources », « France : géocodage de la Géoplateforme (IGN) » et « Étranger : Photon (komoot), données © les contributeurs d'OpenStreetMap ».
- Nominatim n'est pas utilisé : sa politique interdit l'autocomplétion côté client (« Auto-complete search This is not yet supported by Nominatim and you must not implement such a service on the client side using the API. »).

### Affichage des mentions

- Le pied de carte affiche « Fond : ... | Couverture : ... » : le fond visible, l'estompage s'il est activé et les sources de couverture des pays à l'écran, avec un lien vers le panneau « Sources ». Ce panneau liste aussi tous les fonds et leur mention.
- Sur un écran de moins de 900 px de large, seul un bouton « © » est visible ; le texte apparaît après un appui. C'est un écart avec la licence de l'IGN España (mention visible « a pie de mapa »), avec la demande d'OpenTopoMap (« Als Lizenztext sollte Folgendes deutlich sichtbar sein »), avec la consigne d'OpenCellID pour les zones estimées (« beside the map or visualization ») et avec les recommandations d'OpenStreetMap (« The attribution format should not require individuals to interact with the map or produced work to see the attribution. »). État du code au 14 novembre 2026.

## Mode hors ligne

Le bouton « Préparer ce tracé pour le hors ligne » enregistre dans le navigateur, pour le tracé chargé (`src/offline/manager.ts`) :

1. les fichiers du site ;
2. les tuiles de couverture du couloir du tracé (700 m de part et d'autre, zooms 8 à 12), lues dans les archives du projet ;
3. les tuiles du fond affiché, si son fournisseur le permet, dans la limite fixée pour ce fond ;
4. le fichier GPX lui-même.

Le fichier GPX n'est envoyé nulle part : tout reste dans le cache du navigateur. En revanche, le préchargement demande aux fournisseurs de fond les tuiles du couloir : comme lors d'une consultation normale de la carte, ils voient passer la zone du tracé. Le Service Worker (`public/sw.js`, le programme du site qui sert les fichiers enregistrés quand il n'y a pas de réseau) garde à chaque visite une copie des fichiers du site eux-mêmes, mais n'enregistre aucune tuile de fond de lui-même : seul ce bouton remplit le cache des tuiles. Si le couloir demande plus de tuiles que le plafond, les zooms les plus fins sont abandonnés en premier : ce sont eux qui coûtent le plus de requêtes au fournisseur. Les plafonds sont des choix du projet, pas des chiffres imposés par les fournisseurs.

| Fond | Préchargé | Plafond codé | Zooms | Raison tirée des conditions |
|---|---|---|---|---|
| Plan IGN classique et standard | oui, avec le style, les pictogrammes et les polices | 900 tuiles | 7 à 15 | aucun texte ne l'interdit ; la Licence Ouverte autorise la copie ; tuiles vectorielles limitées à 400 requêtes par seconde. Si le style vectoriel ne se charge pas, ce sont les tuiles en images du Plan IGN qui sont enregistrées. |
| Photos aériennes (IGN) | oui | 600 tuiles | 9 à 16 | mêmes raisons ; WMTS sans limite d'usage |
| swisstopo | oui | 600 tuiles | 9 à 15 | toléré en petit nombre : limite de 1'200 requêtes par minute ; les robots à forte intensité sont à éviter et le service de téléchargement est conseillé pour les systèmes hors ligne, mais la documentation du WMTS prévoit qu'une application garde des tuiles en cache local |
| IGN España | oui | 600 tuiles | 9 à 15 | rien dans les textes ; la licence CC BY 4.0 permet de reproduire ; nombre limité par prudence |
| OpenTopoMap | non | aucun | aucun | serveur bénévole qui demande d'éviter les téléchargements en masse : un préchargement en est un |
| Estompage (IGN) | non | aucun | aucun | non prévu : seul le fond affiché est préchargé |

Écarts connus (état du code au 14 novembre 2026) :

- Pas de frein de débit propre à chaque fournisseur : 4 requêtes simultanées au plus, pour tous. Une erreur 429 est seulement comptée comme un échec, sans attendre la durée indiquée par le serveur.
- Aucune durée de conservation : les tuiles restent jusqu'à ce que l'utilisateur efface les données hors ligne. Or la documentation du WMTS suisse demande de purger un cache local quand la couche change : « If your application caches tiles locally, you need to invalidate your local cache for this layer. » Les en-têtes de la Géoplateforme admettent 21 jours de conservation dans le cache du navigateur.

## Vie privée et bonnes pratiques

Dans le site :

- Pas de serveur propre au projet : le site et les tuiles de couverture sont servis par GitHub Pages. Pas de compte, aucun cookie déposé par le site, aucun outil de mesure d'audience ni de traçage.
- Le GPX est lu et analysé dans le navigateur. Il n'est jamais envoyé nulle part. En mode hors ligne, il est seulement rangé dans le cache du navigateur.
- La recherche de lieux n'interroge l'IGN et Photon que lorsqu'on tape dans le champ de recherche. Ils reçoivent le texte tapé ; Photon reçoit aussi le centre et l'emprise de la carte. Rien d'autre ne leur est envoyé.
- Les tuiles de fond sont demandées directement aux fournisseurs par le navigateur : comme pour toute carte en ligne, ils voient l'adresse IP du visiteur et la zone affichée. Comme référent, la page ne leur transmet que l'origine du site, sans le chemin de la page (règle `strict-origin-when-cross-origin`).
- La langue et les réglages sont mémorisés dans le navigateur (`localStorage`).

Dans le pipeline :

- Il tourne dans GitHub Actions (workflow « Données », `.github/workflows/build-data.yml`), une fois par mois (le 5, à 3 h 23 UTC) ou à la main. Il commence par détecter les nouvelles versions et ne reconstruit que si une source a changé.
- Les requêtes sont faites l'une après l'autre, avec une pause entre deux pages (1 s pour l'AGCOM, 0,5 s pour le ministère espagnol) ; ces pages sont demandées compressées. Un seul fichier est téléchargé à la fois et les fichiers intermédiaires sont supprimés au fur et à mesure. Les copies de travail évitent de relire les services les plus coûteux.
- Nom de logiciel annoncé aux serveurs (User-Agent) générique : « pipeline-couverture-mobile/1.0 (Python urllib) », sans le nom du dépôt ni celui de son propriétaire.
- La clé OpenCellID est un secret du dépôt. Elle est envoyée à la page des téléchargements dans le corps de la requête et masquée dans les journaux.
- Pas de scraping : aucune donnée n'est prise sur les sites des opérateurs ni sur des cartes non ouvertes (Infoantenas, cartoradio.mc sans autorisation, cartes d'Andorra Telecom et de Monaco Telecom). Le pipeline ne lit que des fichiers et des services publics dont la licence ou les conditions publiées permettent la réutilisation, avec les réserves dites plus haut pour l'Italie (voie d'accès) et pour l'Espagne (application des conditions générales du ministère à cette carte).
- Quand une source ne répond pas depuis l'environnement de développement, le traitement se fait dans GitHub Actions, sans contournement.

## Points ouverts

Ce document signale ces points sans les trancher.

Décisions qui reviennent au propriétaire du projet :

- Italie : lire le service public de l'AGCOM plutôt que passer par la demande de téléchargement par courriel ; écrire ou non à opendata.bbmap@agcom.it pour l'informer.
- Espagne : s'appuyer sur les conditions générales de réutilisation du ministère, faute de licence attachée à la carte ; sinon, écrire au ministère ou passer l'Espagne en « estimée ».
- Zones estimées : les publier sous CC BY-SA 4.0, comme le demande le partage à l'identique d'OpenCellID.
- Monaco : demander une autorisation écrite pour la couche « Sites Radioélectriques » de cartoradio.mc ; garder les seules cellules de Monaco Telecom (MCC 212) ou ajouter celles des réseaux français.
- OpenStreetMap : régler la question du partage à l'identique pour le code pays des tuiles de l'Andorre et de Monaco.
- IGN España : sa licence demande une mention visible au pied de la carte ; une simple liste de crédits n'est admise qu'en cas d'impossibilité justifiée.

Écarts connus entre le code et ce que demandent les fournisseurs (état du code au 14 novembre 2026), décrits plus haut :

- sur un écran de moins de 900 px, le pied de carte est replié derrière un bouton « © » ;
- la mention d'OpenTopoMap est plus courte que celle qu'il demande ;
- le logo de l'AGCOM n'est pas un lien vers https://maps.agcom.it/, alors que l'AGCOM le présente ainsi ;
- les mentions des contours de pays ne sont pas affichées dans le site ;
- le mode hors ligne n'a ni frein de débit par fournisseur, ni attente après une erreur 429, ni durée de conservation des tuiles.
