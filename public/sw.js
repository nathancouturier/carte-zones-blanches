// Service Worker de la carte des zones blanches : le site reste utilisable sans réseau.
//
// - Coque du site (index.html et tous les fichiers qu'il charge) : la construction écrit
//   ci-dessous leur liste et leur version (src/offline/shell.ts). Ils sont enregistrés
//   ensemble à l'installation, dans un cache propre à cette version, et les coques des
//   versions précédentes sont effacées à l'activation : index.html vient toujours avec
//   ses propres scripts, jamais avec ceux d'une autre version.
// - Page (quels que soient ?lang et les autres paramètres) et manifest des données :
//   réseau d'abord ; s'il ne répond pas dans le délai (réseau faible) ou s'il échoue,
//   copie locale ; sans copie, on attend le réseau. Ce qui arrive ainsi du réseau n'est
//   rangé nulle part : la coque ne change qu'avec une nouvelle version du Service Worker.
// - Fichiers de la coque (scripts, styles, icône) : copie locale d'abord.
// - Manifest des données : la seule copie locale est celle enregistrée avec le tracé
//   préparé, pour aller avec les tuiles de couverture enregistrées en même temps.
// - Tuiles de fond, styles et polices (autres origines) : copie locale d'abord SI elle
//   existe, sinon réseau. Rien n'est enregistré automatiquement : seul le bouton
//   « Préparer le hors ligne » remplit ce cache, tracé par tracé, dans le respect
//   des conditions de chaque fournisseur de fond.
// - Les lectures partielles des archives PMTiles (en-tête Range) ne passent pas par
//   ici : la page enregistre elle-même les tuiles de couverture du tracé.

// Écrit à la construction (src/offline/shell.ts) : version de la coque et liste de ses fichiers.
const SHELL = { version: 'source', index: '', files: [] };

const COQUE = `czb-coque-${SHELL.version}`;
// Doit rester identique à OFFLINE_CACHE dans src/offline/manager.ts.
const HORS_LIGNE = 'czb-hors-ligne-v1';
const SANS_VARY = { ignoreVary: true };
const PORTEE = new URL(self.registration.scope);
// Doit rester identique à DATA_BASE_URL dans src/config.ts.
const MANIFEST = new URL('data/manifest.json', PORTEE).href;
// Liste de la coque, rangée avec elle : la page y vérifie que la coque est complète.
const LISTE = new URL('coque.json', PORTEE).href;
// Délai d'attente du réseau avant de servir la copie locale : NETWORK_TIMEOUT_MS dans
// src/config.ts, transmis dans l'adresse du Service Worker (sw.js?delai=...).
const DELAI = Number(new URL(self.location.href).searchParams.get('delai')) || 3000;

async function empreinte(reponse) {
  const octets = await crypto.subtle.digest('SHA-256', await reponse.arrayBuffer());
  return Array.from(new Uint8Array(octets), (o) => o.toString(16).padStart(2, '0')).join('');
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(COQUE);
      // Tout ou rien (addAll). « no-cache » : chaque fichier est revalidé auprès du serveur.
      await cache.addAll(SHELL.files.map((fichier) => new Request(new URL(fichier, PORTEE), { cache: 'no-cache' })));
      // index.html doit être celui de cette version : sinon il réclamerait d'autres scripts.
      const index = await cache.match(PORTEE.href, SANS_VARY);
      if (!index || (await empreinte(index)) !== SHELL.index) throw new Error('Coque hors ligne : index.html ne correspond pas à cette version');
      // Écrite en dernier : sa présence dit que la coque est complète.
      await cache.put(LISTE, new Response(JSON.stringify(SHELL), { headers: { 'content-type': 'application/json' } }));
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      // Une seule version de la coque à la fois : les précédentes sont effacées.
      const noms = await caches.keys();
      await Promise.all(noms.filter((nom) => nom.startsWith('czb-coque-') && nom !== COQUE).map((nom) => caches.delete(nom)));
      await self.clients.claim();
    })(),
  );
});

/** Réponse du réseau si elle arrive dans le délai ; sinon la copie locale si elle existe ; sinon le réseau, quand il répondra. */
async function reseauDansLeDelai(request, copieLocale) {
  const reseau = fetch(request);
  reseau.catch(() => undefined); // un échec tardif, après la copie, n'est pas une erreur
  let minuterie;
  const delai = new Promise((resolve) => {
    minuterie = setTimeout(resolve, DELAI);
  });
  try {
    const reponse = await Promise.race([reseau, delai]);
    if (reponse) return reponse;
  } catch {
    // réseau en échec avant la fin du délai : copie locale
  } finally {
    clearTimeout(minuterie);
  }
  return (await copieLocale()) || reseau;
}

/** La page : celle du réseau, ou à défaut l'index.html de la coque, quels que soient ?lang et les autres paramètres. */
function page(request) {
  return reseauDansLeDelai(request, async () => {
    const cache = await caches.open(COQUE);
    const url = new URL(request.url);
    return (await cache.match(url.origin + url.pathname, SANS_VARY)) || (await cache.match(PORTEE.href, SANS_VARY));
  });
}

/** Le manifest des données : celui du réseau, ou à défaut celui enregistré avec le tracé préparé. */
function manifest(request) {
  return reseauDansLeDelai(request, async () => (await caches.open(HORS_LIGNE)).match(MANIFEST, SANS_VARY));
}

/** Un fichier du site : sa copie dans la coque, sinon le réseau (fichier d'une autre version par exemple). */
async function fichier(request) {
  // ignoreVary : certains serveurs répondent « Vary: Origin », et une feuille de style ou un script chargé
  // avec l'attribut crossorigin n'a pas les mêmes en-têtes que la requête qui a servi à l'enregistrer.
  const copie = await (await caches.open(COQUE)).match(request.url, SANS_VARY);
  return copie || fetch(request);
}

async function copiePuisReseau(request) {
  const cache = await caches.open(HORS_LIGNE);
  const copie = await cache.match(request.url, SANS_VARY);
  if (copie) return copie;
  return fetch(request);
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  let url;
  try {
    url = new URL(request.url);
  } catch {
    return;
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return;
  if (url.origin === self.location.origin) {
    if (request.headers.has('range')) return; // archives PMTiles : lecture directe
    if (request.mode === 'navigate') event.respondWith(page(request));
    else if (url.origin + url.pathname === MANIFEST) event.respondWith(manifest(request));
    else event.respondWith(fichier(request));
    return;
  }
  event.respondWith(copiePuisReseau(request));
});
