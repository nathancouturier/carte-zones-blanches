// Service Worker de la carte des zones blanches : le site reste utilisable sans réseau.
//
// - Fichiers du site (même origine) : réseau d'abord, copie locale en secours.
//   En ligne on a donc toujours la dernière version ; hors ligne, la dernière vue.
// - Tuiles de fond, styles et polices (autres origines) : copie locale d'abord SI elle
//   existe, sinon réseau. Rien n'est enregistré automatiquement : seul le bouton
//   « Préparer le hors ligne » remplit ce cache, tracé par tracé, dans le respect
//   des conditions de chaque fournisseur de fond.
// - Les lectures partielles des archives PMTiles (en-tête Range) ne passent pas par
//   ici : la page enregistre elle-même les tuiles de couverture du tracé.

const COQUE = 'czb-coque-v1';
// Doit rester identique à OFFLINE_CACHE dans src/offline/manager.ts.
const HORS_LIGNE = 'czb-hors-ligne-v1';
const SANS_VARY = { ignoreVary: true };

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const noms = await caches.keys();
      await Promise.all(noms.filter((nom) => nom.startsWith('czb-coque-') && nom !== COQUE).map((nom) => caches.delete(nom)));
      await self.clients.claim();
    })(),
  );
});

async function reseauPuisCopie(request) {
  const cache = await caches.open(COQUE);
  try {
    const reponse = await fetch(request);
    if (reponse.ok && reponse.status === 200 && reponse.type === 'basic') {
      cache.put(request, reponse.clone()).catch(() => undefined);
    }
    return reponse;
  } catch (erreur) {
    // ignoreVary : certains serveurs répondent « Vary: Origin », et une feuille de style ou un script chargé
    // avec l'attribut crossorigin n'a pas les mêmes en-têtes que la requête qui a servi à l'enregistrer.
    const copie = (await cache.match(request.url, SANS_VARY)) || (await caches.match(request.url, SANS_VARY));
    if (copie) return copie;
    if (request.mode === 'navigate') {
      const accueil = (await cache.match(self.registration.scope, SANS_VARY)) || (await caches.match(self.registration.scope, SANS_VARY));
      if (accueil) return accueil;
    }
    throw erreur;
  }
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
    event.respondWith(reseauPuisCopie(request));
    return;
  }
  event.respondWith(copiePuisReseau(request));
});
