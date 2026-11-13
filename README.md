# Carte des zones blanches

Une carte de randonnée qui montre où il y a du réseau mobile et où il n'y en a pas, en France métropolitaine, en Corse, et de l'autre côté des Alpes et des Pyrénées. On importe un GPX et on obtient la liste des portions du parcours sans réseau.

**Le site : https://nathancouturier.github.io/carte-zones-blanches/**

Site personnel, 100 % statique : pas de serveur, pas de compte, pas de suivi. Le GPX reste dans le navigateur, il n'est jamais envoyé nulle part.

## Ce que fait le site

- **Carte** plein écran aux couleurs de la carte de randonnée (Plan IGN), pensée pour le téléphone.
- **Réseau** : couverture par opérateur ou tous opérateurs confondus. Par défaut seuls les problèmes sont affichés : pas de couverture en rouge, couverture limitée en orange. Les zones estimées sont hachurées.
- **Fond** : automatique selon le pays au centre de la carte (Plan IGN, swisstopo, IGN España, sinon OpenTopoMap), ou au choix, avec l'estompage du relief en option.
- **Import d'un GPX** (traces, routes, multi-segments), par le bouton ou par glisser-déposer. Le tracé est coloré selon la couverture.
- **Rapport** : distance, dénivelé, pays traversés, part du parcours par niveau, liste des zones blanches avec leurs kilomètres et leurs altitudes. Un clic sur une zone zoome dessus.
- **Export** : un GPX enrichi d'un point de passage au début et à la fin de chaque zone blanche, et le rapport en texte.
- **Recherche de lieux**, **ma position**, et une interface en français, español, català, italiano et deutsch.

## Limites à connaître

- **Couverture théorique, des écarts locaux sont possibles.** Les cartes officielles sont des simulations fournies par les opérateurs. Sur le terrain, le relief, la végétation, la météo et le téléphone changent le résultat.
- **Zones estimées.** Là où il n'existe pas de source officielle réutilisable, la couverture est estimée à partir de la position des antennes et du relief. C'est moins fiable : ces zones sont hachurées sur la carte et marquées « estimée » dans le rapport.
- **À l'étranger**, la couverture réelle dépend des accords d'itinérance de votre opérateur. La Suisse, l'Andorre et Monaco ne font pas partie de l'itinérance de l'Union européenne : vérifiez votre forfait.
- **Résolution** : un pixel de donnée fait environ 27 m de côté sous nos latitudes (grille des tuiles au zoom 12).
- En montagne, ne comptez pas sur votre seul téléphone pour donner l'alerte.

Le détail des sources, de leurs dates, de leurs licences et de leurs limites est dans [docs/sources.md](docs/sources.md).

## Architecture

```
src/                  front : Vite, TypeScript, MapLibre GL JS, pmtiles, @tmcw/togeojson
  coverage/           décodage des tuiles, manifest, cache, protocole MapLibre
  gpx/                lecture du GPX, rééchantillonnage, zones blanches, rapport, export
  map/                fonds de carte, style, carte
  search/             recherche de lieux
  ui/                 panneaux et barres
  i18n/locales/       un fichier de traductions par langue
tests/                tests Vitest du front
pipeline/             pipeline de données : Python et GDAL
  config.yaml         emprise, opérateurs, sources, limites de taille
  czb/                grille, masques, tuiles, archives, test de cohérence
  czb/sources/        un module par source de couverture
  sondes/             petits scripts de vérification des sources
  tests/              tests du pipeline sur des données synthétiques
samples/              GPX de test
docs/sources.md       inventaire des sources
.github/workflows/    Données, Déploiement, Tests, Sonde, Vérification
```

### Des tuiles de données, pas des images

Les données de couverture sont des archives [PMTiles](https://docs.protomaps.com/pmtiles/) de tuiles PNG de 256 px, des zooms 0 à 12. Chaque pixel porte des données, pas une couleur :

| Canal | Contenu |
|---|---|
| R | internet mobile : 2 bits par emplacement d'opérateur (4 emplacements). 0 = pas de couverture, 1 = limitée, 2 = bonne, 3 = très bonne |
| G | appels et SMS : même encodage |
| B | bits 0 à 3 : pays. Bits 4 et 5 : type de source (0 officielle par opérateur, 1 officielle agrégée, 2 estimée) |
| A | 255 dans la zone couverte par les données, 0 ailleurs |

Le fichier `manifest.json` publié avec les tuiles dit, pour chaque pays, quel opérateur occupe quel emplacement, comment lire les niveaux, et donne la source, sa date et sa licence. Le décodeur du site est piloté par ce manifest : rien n'est codé en dur par pays.

Ce choix donne peu de fichiers, un changement d'opérateur instantané, et les mêmes tuiles servent à l'affichage et à l'analyse des GPX.

### Côté site

- Un protocole MapLibre (`couverture://`) lit la tuile dans le PMTiles, la décode (`createImageBitmap` sans prémultiplication ni conversion de couleurs, puis `getImageData`), la recolore selon les réglages et la rend à MapLibre.
- Un cache LRU garde les tuiles décodées. Quand un réglage change, la couche est redessinée sans rien retélécharger.
- « Tous opérateurs » est le maximum des emplacements du pays, calculé dans le navigateur. C'est utile pour le 112, qui passe par n'importe quel réseau.
- Les premières tuiles sont décodées une seconde fois en JavaScript pur. Certains navigateurs ajoutent du bruit aux pixels relus d'un canvas : dans ce cas le site bascule tout seul sur le décodeur JavaScript.
- La couche réseau est placée sous les libellés du fond (avant la première couche `symbol` du style).

### Analyse d'un GPX

1. Le tracé est rééchantillonné tous les 20 m (distance géodésique).
2. Pour chaque point, on lit au pixel près les tuiles du zoom 12 : niveau pour l'opérateur choisi et pour tous opérateurs, pays, type de source.
3. Les points sont regroupés en tronçons. Une zone blanche fait au moins 100 m, et deux zones séparées par moins de 50 m de couverture sont fusionnées.
4. Les points hors de la zone couverte par les données sont marqués « hors zone » et exclus des pourcentages.

Les seuils sont des constantes de [`src/config.ts`](src/config.ts).

### Pipeline de données

Le pipeline tourne dans GitHub Actions (image `ghcr.io/osgeo/gdal`). Étapes :

1. détecter les nouvelles versions des sources, télécharger et décompresser un fichier à la fois, en supprimant les fichiers intermédiaires au fur et à mesure ;
2. reprojeter en EPSG:3857 et rastériser sur une grille alignée sur les tuiles du zoom 12. Si deux niveaux se chevauchent, le plus élevé gagne ;
3. empaqueter les canaux R, G, B et A ;
4. générer les tuiles du zoom 12, puis les zooms inférieurs en plus proche voisin (jamais de moyenne, elle casserait l'encodage), et écrire les archives PMTiles. Si le tout dépasse la limite de taille, les tuiles sont réparties en plusieurs archives par blocs, et le site choisit la bonne archive selon x et y ;
5. publier le résultat dans une release GitHub `data-AAAA-MM-JJ`, avec le `manifest.json`.

**Test de cohérence.** Pendant le traitement de chaque fichier source, des points sont tirés au hasard et leur niveau est calculé directement dans la source (test géométrique exact). Une fois les archives écrites, ces mêmes points sont relus dans les pixels décodés du PMTiles. Le job échoue au moindre écart.

Les données ne sont jamais commitées dans git : elles vivent dans les releases, et le déploiement les copie dans le site.

## Développement

Il faut Node 22 ou plus récent.

```bash
npm install
```

```bash
npm run dev
```

```bash
npm test
```

```bash
npm run build
```

Pour avoir la couche réseau en local, téléchargez les fichiers `.pmtiles` et `manifest.json` de la dernière release `data-*` dans `public/data/` (ce dossier est ignoré par git).

Pour le pipeline, il faut Python 3, GDAL avec ses bindings Python, et 7-Zip :

```bash
cd pipeline && python3 -m pip install -r requirements.txt && python3 -m pytest tests
```

```bash
cd pipeline && python3 -m czb.cli build --scope hautes-alpes --services data
```

## Mettre à jour les données

Le workflow **Données** (`.github/workflows/donnees.yml`) se lance tout seul le 5 de chaque mois. Il ne reconstruit que si une source a changé (nouveau trimestre Arcep, nouvelle version d'une source étrangère). Une fois la release publiée, il relance le déploiement du site.

Pour le lancer à la main : onglet Actions du dépôt, workflow « Données », bouton « Run workflow ». Trois réglages :

- **Périmètre** : `complet` (tous les pays), `france`, ou `hautes-alpes` pour un essai rapide ;
- **Services** : `data` (internet mobile) ou `data,voice` (avec les appels et SMS) ;
- **Reconstruire même si rien n'a changé** : à cocher après une modification du pipeline.

Le workflow **Déploiement** (`deploy.yml`) se lance à chaque push sur `main` et après chaque release de données. Il télécharge les fichiers de la dernière release `data-*`, construit le site et le publie sur GitHub Pages.

L'estimation des zones sans source officielle a besoin d'une clé OpenCelliD gratuite, à ranger dans le secret `OPENCELLID_TOKEN` du dépôt (Settings, Secrets and variables, Actions).

## Ajouter une langue

1. Copier `src/i18n/locales/fr.json` sous le code de la langue, par exemple `en.json`.
2. Dans le bloc `_meta`, mettre le nom de la langue et sa balise de formatage des nombres : `{"name": "English", "locale": "en-GB"}`.
3. Traduire les valeurs, sans toucher aux clés ni aux paramètres entre accolades.

La langue apparaît toute seule dans les paramètres. Si une clé manque, le site retombe sur le français. Le test `tests/i18n.test.ts` vérifie que toutes les langues ont les mêmes clés.

Le paramètre d'URL `?lang=es` force une langue.

## Ajouter une source de couverture

1. **Vérifier la source** avant tout : licence, date, format, champs. Le workflow « Sonde » lance un script de `pipeline/sondes/` sur un runner et affiche le résultat dans les logs (`ogrinfo`, `gdalinfo`, GetCapabilities). Ne rien deviner.
2. **La noter** dans `docs/sources.md` : source, date, licence, méthode, limites.
3. **La déclarer** dans `pipeline/config.yaml` : le pays (code, opérateurs, masque) et la source (type, licence, niveaux).
4. **Écrire le module** dans `pipeline/czb/sources/`, sur le modèle de `fr_arcep.py`. Il doit fournir l'état de la source en ligne (`remote_state`, pour détecter les nouvelles versions) et remplir la grille commune (`process`) avec des niveaux de 0 à 3, uniquement dans les pixels de son pays. Il doit aussi produire des points témoins pour le test de cohérence.
5. **L'enregistrer** dans `pipeline/czb/sources/__init__.py` et ajouter un test sur des données synthétiques.

Le site n'a pas besoin d'être modifié : il lit le nouveau pays dans le manifest.

## Vie privée

- Aucun cookie, aucun outil de mesure d'audience, aucun compte.
- Le GPX est lu et analysé dans le navigateur. Seules les tuiles de carte nécessaires sont téléchargées.
- La recherche de lieux interroge le géocodage de l'IGN (France) et Photon (étranger) uniquement quand on tape dans le champ de recherche.
- La langue et les réglages sont mémorisés dans le navigateur (`localStorage`).
