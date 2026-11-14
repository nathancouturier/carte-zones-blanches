// Vérification du site déployé, dans un vrai navigateur (Chromium via Playwright).
//
// Le script ouvre le site sur ordinateur et en vue mobile, dans plusieurs
// langues, et contrôle ce qui compte : le fond de carte se charge, la couche
// réseau est lue, la recherche répond, un GPX importé donne un rapport.
// Les captures d'écran sont enregistrées dans captures/ et, avec
// CAPTURES_DANS_LES_LOGS=1, écrites en base64 dans la sortie.
//
//   SITE_URL=https://nathancouturier.github.io/carte-zones-blanches/ node verif.mjs

import { mkdirSync, readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const SITE = (process.env.SITE_URL ?? 'https://nathancouturier.github.io/carte-zones-blanches/').replace(/\/?$/, '/');
const HORS_LIGNE = process.env.SANS_FONDS === '1'; // en local sans accès aux fonds de carte
const DANS_LES_LOGS = process.env.CAPTURES_DANS_LES_LOGS === '1';
const dossier = fileURLToPath(new URL('./captures/', import.meta.url));
mkdirSync(dossier, { recursive: true });

const resultats = [];
function controle(nom, ok, detail = '') {
  resultats.push({ nom, ok, detail });
  console.log(`${ok ? 'OK   ' : 'ÉCHEC'} ${nom}${detail ? ` : ${detail}` : ''}`);
}

const GPX_SECOURS = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="verif" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>Vallouise, Glacier Blanc</name><trkseg>
<trkpt lat="44.8460" lon="6.4890"><ele>1160</ele></trkpt><trkpt lat="44.8760" lon="6.4420"><ele>1450</ele></trkpt>
<trkpt lat="44.9170" lon="6.4160"><ele>1874</ele></trkpt><trkpt lat="44.9380" lon="6.4000"><ele>2542</ele></trkpt>
</trkseg></trk></gpx>`;

// GPX « difficile », lu comme un GPX ordinaire : encodé en ISO-8859-1, précédé d'un saut de ligne,
// éléments préfixés (gpx:trk), un point (0, 0) dû à une perte du signal et une altitude manquante.
const GPX_DIFFICILE = Buffer.from(`
<?xml version="1.0" encoding="ISO-8859-1"?>
<gpx:gpx version="1.1" creator="verif" xmlns:gpx="http://www.topografix.com/GPX/1/1"><gpx:trk><gpx:name>Tour du Râteau</gpx:name><gpx:trkseg>
<gpx:trkpt lat="44.8460" lon="6.4890"><gpx:ele>1160</gpx:ele></gpx:trkpt><gpx:trkpt lat="44.8760" lon="6.4420"><gpx:ele>1450</gpx:ele></gpx:trkpt>
<gpx:trkpt lat="0" lon="0"><gpx:ele>0</gpx:ele></gpx:trkpt>
<gpx:trkpt lat="44.9170" lon="6.4160"/><gpx:trkpt lat="44.9380" lon="6.4000"><gpx:ele>2542</gpx:ele></gpx:trkpt>
</gpx:trkseg></gpx:trk></gpx:gpx>`, 'latin1');

// Tracé entièrement en France : le mode hors ligne y précharge le Plan IGN, fond du mode Automatique.
// (Un tracé qui passe à l'étranger peut tomber sur un fond qu'on ne précharge pas, comme OpenTopoMap.)
const TRACE_FRANCE = { name: 'vallouise.gpx', mimeType: 'application/gpx+xml', buffer: Buffer.from(GPX_SECOURS) };

// Ce que le site publie : pays présents et emprise des données (lus dans son manifest).
const manifest = await fetch(`${SITE}data/manifest.json`).then((r) => (r.ok ? r.json() : null), () => null);
const paysPublies = (manifest?.countries ?? []).map((c) => c.iso);
const [ouest, sud, est, nord] = manifest?.bounds ?? [0, 0, 0, 0];

function echantillon(nom) {
  const chemin = fileURLToPath(new URL(`../samples/${nom}`, import.meta.url));
  return existsSync(chemin) ? { name: nom, mimeType: 'application/gpx+xml', buffer: readFileSync(chemin) } : null;
}

// Le GPX de test des Alpes si les données publiées couvrent son départ (Les Chapieux), sinon un court tracé
// des Hautes-Alpes : des données d'essai réduites à ce département suffisent alors.
function gpx(nom) {
  const fichier = echantillon(nom);
  const couvert = ouest <= 6.73 && 6.73 <= est && sud <= 45.7 && 45.7 <= nord;
  return fichier && couvert ? fichier : TRACE_FRANCE;
}

async function ouvrir(navigateur, options, chemin, preparer) {
  const contexte = await navigateur.newContext(options);
  if (preparer) await preparer(contexte); // par exemple pour simuler une panne avant le chargement
  const page = await contexte.newPage();
  const suivi = { reponses: new Map(), erreurs: [], echecs: new Map(), manifest: 0, archives: 0 };
  page.on('response', (r) => {
    const adresse = new URL(r.url());
    const cle = `${adresse.host} ${r.status() < 400 ? 'ok' : 'ko'}`;
    suivi.reponses.set(cle, (suivi.reponses.get(cle) ?? 0) + 1);
    // Données de couverture : le manifest (200) et les lectures partielles des archives PMTiles (200 ou 206).
    if (adresse.pathname.endsWith('/data/manifest.json') && r.status() === 200) suivi.manifest += 1;
    if (adresse.pathname.endsWith('.pmtiles') && (r.status() === 200 || r.status() === 206)) suivi.archives += 1;
  });
  page.on('requestfailed', (r) => {
    const hote = new URL(r.url()).host;
    suivi.echecs.set(hote, (suivi.echecs.get(hote) ?? 0) + 1);
  });
  page.on('pageerror', (e) => suivi.erreurs.push(e.message));
  page.on('console', (m) => {
    if (m.type() === 'error' && !/Failed to load resource|ERR_/.test(m.text())) suivi.erreurs.push(m.text());
  });
  await page.goto(SITE + chemin, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  return { contexte, page, suivi };
}

const ok = (suivi, hote) => suivi.reponses.get(`${hote} ok`) ?? 0;

async function capture(page, nom) {
  const fichier = `${dossier}${nom}.jpg`;
  await page.screenshot({ path: fichier, type: 'jpeg', quality: 60 });
  if (DANS_LES_LOGS) {
    console.log(`=====DEBUT ${nom}.jpg=====`);
    console.log(readFileSync(fichier).toString('base64').replace(/(.{120})/g, '$1\n'));
    console.log(`=====FIN ${nom}.jpg=====`);
  }
}

async function importer(page, fichier) {
  await page.setInputFiles('input[type=file]', fichier);
  await page.waitForSelector('.panel[data-panel="report"] .stats, .panel[data-panel="report"] .note--warning', { timeout: 60000 });
  await page.waitForTimeout(1500);
}

const navigateur = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const ordinateur = { viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 };
const telephone = { viewport: { width: 412, height: 915 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true, userAgent: 'Mozilla/5.0 (Linux; Android 15; Pixel 9a) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36' };

try {
  // --- 1. Ordinateur, français : carte, réseau, recherche, GPX ------------------
  {
    const { contexte, page, suivi } = await ouvrir(navigateur, ordinateur, '#10.5/44.9/6.45');
    controle('fr : langue de la page', (await page.evaluate(() => document.documentElement.lang)) === 'fr');
    controle('fr : titre', (await page.title()) === 'Carte des zones blanches', await page.title());
    if (!HORS_LIGNE) controle('fr : fond Plan IGN chargé', ok(suivi, 'data.geopf.fr') >= 4, `${ok(suivi, 'data.geopf.fr')} réponses de data.geopf.fr`);
    controle('fr : manifest et tuiles de couverture lus', suivi.manifest >= 1 && suivi.archives >= 1, `manifest lu ${suivi.manifest} fois, ${suivi.archives} lectures dans les archives PMTiles`);
    // La mention du fond est un lien vers ses conditions, ouvert dans un nouvel onglet (carte-4).
    const lienFond = await page.evaluate(() => {
      const a = document.querySelector('.attribution a[href="https://cartes.gouv.fr/cgu/"]');
      return a ? `${a.textContent} | ${a.target} | ${a.rel} | ${a.getClientRects().length > 0 ? 'visible' : 'caché'}` : 'aucun lien';
    });
    controle('fr : la mention du fond renvoie vers ses conditions d\'utilisation', lienFond === '© IGN | _blank | noopener noreferrer | visible', lienFond);
    await capture(page, '1-ordinateur-fr-carte');

    // Clavier : le focus va sur le titre du panneau ouvert, puis revient à son bouton à la fermeture.
    await page.focus('.tool[data-panel="network"]');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(300);
    const surTitre = await page.evaluate(() => document.activeElement?.classList.contains('panel__title') ?? false);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    const surBouton = await page.evaluate(() => document.activeElement?.matches('.tool[data-panel="network"]') ?? false);
    controle('fr : au clavier, le focus suit l\'ouverture et la fermeture d\'un panneau', surTitre && surBouton, `titre ${surTitre}, bouton ${surBouton}`);

    await page.click('[data-panel="network"]');
    await page.waitForSelector('.chips');
    const operateurs = await page.locator('.chips .chip').allTextContents();
    controle('fr : opérateurs lus dans le manifest', operateurs.includes('Orange') && operateurs.includes('Free'), operateurs.join(', '));
    await page.click('.chip:has-text("Orange")');
    await page.waitForTimeout(1500);
    await capture(page, '2-ordinateur-fr-reseau-orange');
    await page.click('.chip:has-text("Tous opérateurs")');

    if (!HORS_LIGNE) {
      await page.click('button[aria-label="Rechercher un lieu"]');
      await page.fill('.search__input', 'Briançon');
      const trouve = await page.waitForSelector('.search__item', { timeout: 15000 }).then(() => true, () => false);
      controle('fr : la recherche propose des lieux', trouve, trouve ? (await page.locator('.search__label').first().textContent()) ?? '' : '');
      if (trouve) {
        await capture(page, '3-ordinateur-fr-recherche');
        await page.locator('.search__item').first().click();
        await page.waitForTimeout(2500);
        const centre = await page.evaluate(() => location.hash);
        controle('fr : la carte va au lieu choisi', /#\d+(\.\d+)?\/44\.[89]\d*\/6\.[56]\d*/.test(centre), centre);
      }
    }

    await importer(page, gpx('test-alpes.gpx'));
    const texte = await page.locator('.report-text').inputValue().catch(() => '');
    controle('fr : le rapport liste les zones blanches avec leurs km', /Zones? blanches? \(\d+\)/.test(texte) && /km \d+,\d à \d+,\d/.test(texte), (texte.match(/Zones? blanches? \(\d+\)/) ?? [''])[0]);
    controle('fr : le rapport rappelle la limite des données', texte.includes('Couverture théorique, des écarts locaux sont possibles.'));
    controle('fr : le rapport texte ne garde aucune variable entre accolades', texte !== '' && !/[{}]/.test(texte), (texte.match(/.*[{}].*/) ?? [''])[0]);
    // « km 12,4 à 14,1, soit 1,7 km » : la longueur annoncée est la différence des bornes affichées.
    const nombre = (s) => Number(s.replace(',', '.'));
    const bornes = [...texte.matchAll(/km (\d+,\d) à (\d+,\d), soit (\d+,\d) km/g)];
    const discordantes = bornes.filter(([, debut, fin, longueur]) => Math.abs(nombre(fin) - nombre(debut) - nombre(longueur)) > 0.05);
    controle('fr : bornes et longueur des zones concordent', bornes.length > 0 && discordantes.length === 0, discordantes.map((m) => m[0]).join(' | ') || `${bornes.length} zone(s)`);
    console.log('--- rapport (début) ---\n' + texte.split('\n').slice(0, 22).join('\n') + '\n-----------------------');
    await capture(page, '4-ordinateur-fr-rapport');
    const zone = page.locator('.zone').first();
    if (await zone.count()) {
      // « Rapport en texte » ouvert : il le reste quand on choisit une zone blanche.
      await page.click('summary[data-focus="texte"]');
      await zone.click();
      await page.waitForTimeout(2500);
      const ouvert = await page.evaluate(() => document.querySelector('summary[data-focus="texte"]')?.parentElement?.open === true);
      controle('fr : « Rapport en texte » reste ouvert après un clic sur une zone blanche', ouvert);
      await capture(page, '5-ordinateur-fr-zone');
    }
    const [telechargement] = await Promise.all([page.waitForEvent('download', { timeout: 15000 }).catch(() => null), page.click('[data-focus="gpx-enrichi"]')]);
    controle('fr : le GPX enrichi se télécharge', telechargement !== null, telechargement?.suggestedFilename() ?? '');

    // Profil altimétrique : présent, et le survol place un repère sur la carte.
    const profil = page.locator('.profile__svg');
    if (await profil.count()) {
      await profil.scrollIntoViewIfNeeded();
      const boite = await profil.boundingBox();
      await page.mouse.move(boite.x + boite.width * 0.6, boite.y + boite.height / 2);
      await page.waitForTimeout(500);
      const lecture = (await page.locator('.profile__readout').textContent()) ?? '';
      controle('fr : le profil altimétrique situe un point', /^km \d/.test(lecture) && (await page.locator('.track-cursor').count()) === 1, lecture);
      await capture(page, '5b-ordinateur-fr-profil');
      // Au clavier : le profil prend le focus, les touches déplacent le curseur, la valeur et le résumé sont dits.
      await page.mouse.move(5, 5);
      await profil.focus();
      await page.keyboard.press('End');
      await page.keyboard.press('ArrowLeft');
      const clavier = { role: await profil.getAttribute('role'), valeur: (await profil.getAttribute('aria-valuetext')) ?? '', resume: (await profil.getAttribute('aria-label')) ?? '' };
      const repere = (await page.locator('.track-cursor').count()) === 1;
      controle('fr : le profil se parcourt au clavier et se résume', clavier.role === 'slider' && /^km \d/.test(clavier.valeur) && repere && /sans couverture\.$/.test(clavier.resume), `${clavier.valeur} | ${clavier.resume}`);
    } else {
      controle('fr : profil altimétrique', false, 'absent alors que le GPX a des altitudes');
    }

    // Appels et SMS, si le service est publié.
    await page.click('[data-panel="network"]');
    await page.waitForSelector('.chips');
    const voix = page.locator('.chip:has-text("Appels et SMS")');
    if (await voix.count()) {
      await voix.click();
      await page.waitForTimeout(1500);
      await page.click('[data-panel="report"]');
      await page.waitForSelector('.report-text', { state: 'attached' });
      const texteVoix = await page.locator('.report-text').inputValue();
      controle('fr : rapport pour les appels et SMS', texteVoix.includes('Service : Appels et SMS') && /Part du parcours/.test(texteVoix));
      await page.click('[data-panel="network"]');
      await page.click('.chip:has-text("Internet mobile")');
      await page.waitForTimeout(800);
    } else {
      console.log('INFO  le service Appels et SMS n\'est pas publié dans cette release');
    }

    // GPX « difficile » : accents, point aberrant écarté, dénivelé malgré une altitude manquante, export en UTF-8.
    // S'il était refusé, le message apparaîtrait dans le panneau GPX : on l'attend aussi, pour échouer proprement.
    await page.setInputFiles('input[type=file]', { name: 'difficile.gpx', mimeType: 'application/gpx+xml', buffer: GPX_DIFFICILE });
    await page.waitForSelector('.panel[data-panel="report"] .stats, .panel[data-panel="gpx"] .note--warning', { timeout: 60000 }).catch(() => null);
    await page.waitForTimeout(1500);
    const lu = await page.evaluate(() => ({
      nom: document.querySelector('.panel[data-panel="report"] .track-name')?.textContent ?? '',
      faits: document.querySelector('.panel[data-panel="report"] .facts')?.textContent ?? '',
      notes: [...document.querySelectorAll('.panel .note')].map((n) => n.textContent).join(' | '),
    }));
    controle('fr : GPX en ISO-8859-1, préfixé, précédé d\'un saut de ligne, lu avec ses accents', lu.nom === 'Tour du Râteau', lu.nom || lu.notes);
    controle('fr : point (0, 0) écarté et signalé', /point aberrant/.test(lu.notes) && /Distance\s*12,6\s*km/.test(lu.faits), `${lu.faits.slice(0, 18)} | ${lu.notes}`);
    controle('fr : dénivelé annoncé malgré une altitude manquante', /Dénivelé/.test(lu.faits), lu.faits.slice(0, 60));
    await capture(page, '5c-ordinateur-fr-gpx-difficile');
    const [enrichi] = await Promise.all([
      page.waitForEvent('download', { timeout: 15000 }).catch(() => null),
      page.click('[data-focus="gpx-enrichi"]', { timeout: 5000 }).catch(() => null),
    ]);
    const exporte = enrichi ? readFileSync(await enrichi.path()).toString('utf-8') : '';
    controle('fr : GPX enrichi écrit et déclaré en UTF-8', exporte.startsWith('<?xml version="1.0" encoding="UTF-8"?>') && exporte.includes('Tour du Râteau'), exporte.slice(0, 50));
    controle('fr : aucune erreur JavaScript', suivi.erreurs.length === 0, suivi.erreurs.slice(0, 3).join(' | '));
    await contexte.close();
  }

  // --- 2. Téléphone, allemand : libellés, panneaux, fond suisse -----------------
  {
    const { contexte, page, suivi } = await ouvrir(navigateur, telephone, '?lang=de#11/46.02/7.75');
    controle('de : langue de la page', (await page.evaluate(() => document.documentElement.lang)) === 'de');
    // Le bouton Rapport existe déjà, masqué tant qu'aucun tracé n'est importé.
    const outils = await page.locator('.toolbar .tool:not([hidden]) span').allTextContents();
    controle('de : barre d\'outils traduite', outils.join('|') === 'Netz|Karte|GPX importieren', outils.join('|'));
    const nomCarte = await page.locator('.maplibregl-canvas').getAttribute('aria-label');
    controle('de : la carte est nommée en allemand pour les lecteurs d\'écran', nomCarte === 'Karte', nomCarte ?? '');
    if (!HORS_LIGNE) {
      await page.click('[data-panel="basemap"]');
      await page.click('label:has-text("swisstopo")');
      await page.waitForTimeout(5000);
      controle('de : fond swisstopo chargé', ok(suivi, 'wmts.geo.admin.ch') >= 2, `${ok(suivi, 'wmts.geo.admin.ch')} réponses de wmts.geo.admin.ch`);
      await capture(page, '6-telephone-de-swisstopo');
      await page.click('.icon-btn[data-role="close"]');
    }
    await page.evaluate(() => (location.hash = '#11/44.9/6.42'));
    await page.waitForTimeout(3000);
    await importer(page, gpx('test-alpes.gpx'));
    const titre = await page.locator('.panel__title').textContent();
    controle('de : rapport en allemand', titre === 'Abdeckungsbericht', titre ?? '');
    await capture(page, '7-telephone-de-rapport');
    await page.click('button[aria-label="Einstellungen"]');
    await page.waitForSelector('#langue');
    await capture(page, '8-telephone-de-parametres');
    controle('de : aucune erreur JavaScript', suivi.erreurs.length === 0, suivi.erreurs.slice(0, 3).join(' | '));
    await contexte.close();
  }

  // --- 2b. Téléphone, français : mode hors ligne --------------------------------
  {
    const { contexte, page, suivi } = await ouvrir(navigateur, telephone, '#11/44.9/6.42');
    const controleParSw = await page.evaluate(async () => {
      if (!('serviceWorker' in navigator)) return false;
      await navigator.serviceWorker.ready;
      return true;
    });
    controle('hors ligne : Service Worker enregistré', controleParSw);
    // La coque (index.html et ses fichiers) est enregistrée en entier à l'installation, dans un seul cache versionné.
    const coque = await page.evaluate(async () => {
      const noms = (await caches.keys()).filter((nom) => nom.startsWith('czb-coque-'));
      if (noms.length !== 1) return `${noms.length} caches de coque`;
      const cache = await caches.open(noms[0]);
      const liste = await cache.match(new URL('coque.json', location.href).href);
      if (!liste) return 'coque.json absent';
      const { files } = await liste.json();
      const absents = [];
      for (const f of files) if (!(await cache.match(new URL(f, location.href).href))) absents.push(f);
      const scripts = [...document.querySelectorAll('script[src], link[rel=stylesheet]')].map((e) => new URL(e.src || e.href).pathname.split('/').pop());
      const horsListe = scripts.filter((s) => !files.some((f) => f.endsWith(s)));
      return absents.length || horsListe.length ? `manquent : ${[...absents, ...horsListe].join(', ')}` : `${noms[0]}, ${files.length} fichiers`;
    });
    controle('hors ligne : coque complète, une seule version', /^czb-coque-\w+, \d+ fichiers$/.test(coque), coque);
    await importer(page, TRACE_FRANCE);
    await page.locator('[data-focus="hors-ligne"]').scrollIntoViewIfNeeded();
    await page.click('[data-focus="hors-ligne"]');
    const pret = await page.waitForSelector('.offline-ready', { timeout: 180000 }).then(() => true, () => false);
    const bilan = pret ? ((await page.locator('.offline-ready').textContent()) ?? '') : '';
    controle('hors ligne : le tracé est enregistré', pret && /tuiles de couverture/.test(bilan), bilan);
    const fonds = (await page.locator('.offline-basemaps li').allTextContents()).join(' | ');
    if (!HORS_LIGNE) controle('hors ligne : le fond Plan IGN est enregistré', /Plan IGN classique\s*:\s*\d[\d\s\u202f]* tuiles? enregistrées?/.test(fonds), fonds);
    await capture(page, '8b-telephone-fr-hors-ligne-pret');
    // La suppression des données hors ligne demande confirmation : refusée, rien n'est effacé.
    const confirmations = [];
    page.once('dialog', async (d) => {
      confirmations.push(d.message());
      await d.dismiss();
    });
    await page.click('[data-focus="hors-ligne-effacer"]');
    await page.waitForTimeout(800);
    const garde = (await page.locator('.offline-ready').count()) === 1;
    controle('hors ligne : la suppression demande confirmation', confirmations.length === 1 && /^Supprimer le tracé/.test(confirmations[0]) && garde, confirmations[0] ?? 'aucune confirmation');

    // Coupure du réseau, puis rechargement complet de la page.
    const servies = [];
    page.on('response', (r) => {
      if (r.fromServiceWorker() && r.status() === 200) servies.push(new URL(r.url()).host);
    });
    await contexte.setOffline(true);
    await page.reload({ waitUntil: 'load' });
    const recharge = await page.waitForSelector('.panel[data-panel="report"] .stats', { timeout: 60000 }).then(() => true, () => false);
    controle('hors ligne : le site redémarre et recharge le tracé sans réseau', recharge);
    await page.waitForTimeout(4000);
    if (!HORS_LIGNE) {
      const fond = servies.filter((h) => h === 'data.geopf.fr').length;
      controle('hors ligne : le fond est servi depuis la copie locale', fond >= 3, `${fond} réponses de data.geopf.fr sans réseau`);
    }
    if (recharge) {
      const texte = await page.locator('.report-text').inputValue();
      controle('hors ligne : le rapport est recalculé', /Zones? blanches? \(\d+\)|Aucune zone blanche/.test(texte));
      await page.click('.icon-btn[data-role="close"]');
      await page.waitForTimeout(2500);
    }
    await capture(page, '8c-telephone-fr-hors-ligne-carte');
    // Sans réseau, une adresse avec ?lang (un signet par exemple) retrouve la même page, dans sa langue.
    await page.goto(`${SITE}?lang=es#11/44.9/6.42`, { waitUntil: 'load' }).catch(() => null);
    await page.waitForTimeout(1500);
    const signet = { lang: await page.evaluate(() => document.documentElement.lang).catch(() => ''), titre: await page.title().catch(() => '') };
    controle('hors ligne : ?lang=es retrouve la page sans réseau', signet.lang === 'es' && signet.titre === 'Mapa de zonas sin cobertura', `${signet.lang} | ${signet.titre}`);
    // Vue plus large que le couloir enregistré (au plus le zoom 9, quel que soit le tracé) : les tuiles
    // manquantes sont signalées, puis relues toutes seules au retour du réseau, sans recharger la page.
    await page.evaluate(() => {
      const [zoom, lat, lon] = location.hash.slice(1).split('/').map(Number);
      location.hash = `#${Math.min(zoom - 1.5, 9).toFixed(2)}/${lat}/${lon}`;
    });
    await page.waitForTimeout(3000);
    const signale = await page.locator('.coverage-alert').isVisible();
    await contexte.setOffline(false);
    const complete = signale && (await page.waitForSelector('.coverage-alert', { state: 'hidden', timeout: 30000 }).then(() => true, () => false));
    controle('hors ligne : hors du couloir, tuiles signalées puis relues au retour du réseau', complete, signale ? (complete ? '' : 'bandeau toujours affiché') : 'aucun bandeau sans réseau');
    controle('hors ligne : aucune erreur JavaScript', suivi.erreurs.length === 0, suivi.erreurs.slice(0, 3).join(' | '));
    await contexte.close();
  }

  // --- 2c. Téléphone, français : données de couverture illisibles, puis « Réessayer » --
  {
    let coupe = true;
    const { contexte, page, suivi } = await ouvrir(navigateur, telephone, '#11/44.9/6.42', (c) =>
      c.route(/\.pmtiles(\?|$)/, (route) => (coupe ? route.abort('internetdisconnected') : route.fallback())),
    );
    const bandeau = await page.locator('.coverage-alert').isVisible();
    controle('panne : un bandeau signale les données de couverture illisibles', bandeau, bandeau ? ((await page.locator('.coverage-alert').textContent()) ?? '') : 'pas de bandeau');
    await capture(page, '8d-telephone-fr-couverture-illisible');
    coupe = false;
    const lues = suivi.archives;
    if (bandeau) await page.click('.coverage-alert button');
    const repris = await page.waitForSelector('.coverage-alert', { state: 'hidden', timeout: 30000 }).then(() => true, () => false);
    await page.waitForTimeout(3000);
    const toujours = await page.locator('.coverage-alert').isVisible();
    controle('panne : « Réessayer » relit les tuiles une fois le réseau revenu', bandeau && repris && !toujours && suivi.archives > lues, `${suivi.archives - lues} lectures dans les archives après « Réessayer »`);
    controle('panne : aucune erreur JavaScript', suivi.erreurs.length === 0, suivi.erreurs.slice(0, 3).join(' | '));
    await contexte.close();
  }

  // --- 2d. Ordinateur, français : nouvelle publication des données pendant la visite --
  {
    let lus = 0;
    let nouvelles = 0;
    const { contexte, page, suivi } = await ouvrir(navigateur, ordinateur, '#11/44.9/6.42', async (c) => {
      // Le premier manifest lu est celui d'une publication précédente, dont l'archive a disparu du serveur.
      await c.route(/\/data\/manifest\.json(\?|$)/, async (route) => {
        if (++lus > 1) return route.fallback();
        const reponse = await route.fetch();
        const manifest = await reponse.json();
        manifest.generated = '2000-01-01';
        for (const archive of manifest.archives) archive.file = `ancienne-${archive.file}`;
        await route.fulfill({ response: reponse, json: manifest });
      });
      c.on('response', (r) => {
        if (r.url().endsWith('.pmtiles') && !r.url().includes('/ancienne-') && r.status() === 206) nouvelles += 1;
      });
      // Messages brefs affichés pendant le chargement (ils disparaissent au bout de quelques secondes).
      await c.addInitScript(() => {
        window.messagesVus = [];
        new MutationObserver(() => {
          const toast = document.querySelector('.toast');
          if (toast && !toast.hidden && !window.messagesVus.includes(toast.textContent)) window.messagesVus.push(toast.textContent);
        }).observe(document, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ['hidden'] });
      });
    });
    const etat = await page.evaluate(() => ({
      bandeau: document.querySelector('.coverage-alert')?.hidden === false,
      message: window.messagesVus.find((m) => /Nouvelles données/.test(m)) ?? window.messagesVus.join(' | '),
    }));
    controle('publication : l\'onglet ouvert relit le manifest et passe aux nouvelles archives', lus >= 2 && nouvelles >= 1 && !etat.bandeau, `manifest lu ${lus} fois, ${nouvelles} lectures dans les nouvelles archives${etat.bandeau ? ', bandeau affiché' : ''}`);
    controle('publication : l\'utilisateur est prévenu', /Nouvelles données de couverture publiées/.test(etat.message), etat.message);
    controle('publication : aucune erreur JavaScript', suivi.erreurs.length === 0, suivi.erreurs.slice(0, 3).join(' | '));
    await contexte.close();
  }

  // --- 2e. Téléphone : fonds enregistrés selon leur fournisseur (réponses simulées) ---
  // Photos aériennes et estompage du relief de l'IGN, servis ici par une image simulée :
  // on vérifie le plafond du fournisseur, le bilan fond par fond et l'affichage sans réseau.
  {
    const { contexte, page, suivi } = await ouvrir(navigateur, telephone, '#11/44.9/6.42');
    const image = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
    let demandes = 0;
    await contexte.route(/^https:\/\/data\.geopf\.fr\/wmts\?/, (route) => {
      demandes += 1;
      route.fulfill({ status: 200, contentType: 'image/png', body: image, headers: { 'access-control-allow-origin': '*' } });
    });
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.click('[data-panel="basemap"]');
    await page.click('label:has-text("Photos aériennes")');
    await page.click('label:has-text("Estompage du relief")');
    await page.click('.icon-btn[data-role="close"]');
    await importer(page, gpx('test-alpes.gpx'));
    await page.locator('[data-focus="hors-ligne"]').scrollIntoViewIfNeeded();
    const avant = demandes;
    await page.click('[data-focus="hors-ligne"]');
    const pret = await page.waitForSelector('.offline-ready', { timeout: 180000 }).then(() => true, () => false);
    const fonds = (await page.locator('.offline-basemaps li').allTextContents()).join(' | ');
    const prechargees = demandes - avant;
    controle('fonds : photos aériennes et estompage enregistrés, fond par fond', pret && /Photos aériennes \(IGN\)\s*:\s*\d+ tuiles enregistrées/.test(fonds) && /Estompage du relief\s*:\s*\d+ tuiles enregistrées/.test(fonds), fonds);
    controle('fonds : plafond du fournisseur respecté', prechargees > 0 && prechargees <= 600 + 600, `${prechargees} requêtes pour les deux fonds`);
    await capture(page, '8d-telephone-fr-fonds-enregistres');
    const servies = [];
    page.on('response', (r) => {
      if (r.fromServiceWorker() && r.status() === 200 && new URL(r.url()).host === 'data.geopf.fr') servies.push(r.url());
    });
    // Sans réseau, plus aucune réponse simulée : ce qui s'affiche vient de la copie locale.
    await contexte.unrouteAll();
    await contexte.route(/^https:\/\/data\.geopf\.fr\//, (route) => route.abort('internetdisconnected'));
    await contexte.setOffline(true);
    await page.reload({ waitUntil: 'load' });
    await page.waitForSelector('.panel[data-panel="report"] .stats', { timeout: 60000 }).catch(() => null);
    await page.click('.icon-btn[data-role="close"]').catch(() => null);
    await page.waitForTimeout(3000);
    controle('fonds : photos aériennes servies sans réseau depuis la copie locale', servies.length >= 3, `${servies.length} tuiles servies par le Service Worker`);
    await capture(page, '8e-telephone-fr-fonds-sans-reseau');
    await contexte.setOffline(false);
    controle('fonds : aucune erreur JavaScript', suivi.erreurs.length === 0, suivi.erreurs.slice(0, 3).join(' | '));
    await contexte.close();
  }

  // --- 2f. Téléphone, français : pied de carte, Ma position, rapport réduit, recherche, fond Auto --
  {
    // Géocodage simulé (300 ms de latence) : le contrôle ne dépend pas du service et marche sans réseau.
    const lieux = (q) => (q.startsWith('brides') ? [{ fulltext: 'Brides-les-Bains', x: 6.5675, y: 45.4531 }] : q.startsWith('bri') ? [{ fulltext: 'Briançon', x: 6.6436, y: 44.8986 }] : []);
    const position = { geolocation: { latitude: 44.9, longitude: 6.42, accuracy: 30 }, permissions: ['geolocation'] };
    const { contexte, page, suivi } = await ouvrir(navigateur, { ...telephone, ...position }, '#10/44.9/6.45', async (c) => {
      await c.route(/data\.geopf\.fr\/geocodage\/completion/, (route) => {
        const q = (new URL(route.request().url()).searchParams.get('text') ?? '').toLowerCase();
        setTimeout(() => route.fulfill({ json: { status: 'OK', results: lieux(q).map((l) => ({ ...l, kind: 'municipality' })) } }).catch(() => undefined), 300);
      });
      await c.route(/photon\.komoot\.io/, (route) => route.fulfill({ json: { type: 'FeatureCollection', features: [] } }));
    });

    // Pied de carte : mentions dépliées au chargement, repliées au premier glissé du doigt sur la carte.
    const pied = () => page.evaluate(() => ({ visible: getComputedStyle(document.querySelector('.attribution__text')).display !== 'none', bouton: Math.round(document.querySelector('.attribution__toggle').getBoundingClientRect().height) }));
    const auChargement = await pied();
    controle('interface : mentions des sources visibles au chargement, bouton « © » de 44 px', auChargement.visible && auChargement.bouton >= 44, JSON.stringify(auChargement));
    const cdp = await contexte.newCDPSession(page);
    const toucher = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
    await toucher('touchStart', 200, 400);
    for (let i = 1; i <= 8; i++) await toucher('touchMove', 200 + i * 10, 400 + i * 10);
    await toucher('touchEnd');
    await page.waitForTimeout(800);
    controle('interface : mentions repliées au premier geste sur la carte', !(await pied()).visible);

    // « Ma position » appuyé deux fois : la position reste affichée.
    await page.tap('.topbar button[aria-label="Ma position"]');
    await page.waitForSelector('.maplibregl-user-location-dot', { timeout: 20000 }).catch(() => null);
    await page.waitForTimeout(1500);
    await page.tap('.topbar button[aria-label="Ma position"]');
    await page.waitForTimeout(2500);
    controle('interface : « Ma position » appuyé deux fois garde la position affichée', (await page.locator('.maplibregl-user-location-dot').count()) === 1);

    // Rapport : le tracé reste visible au-dessus du panneau, qui se réduit à son titre pour montrer la carte.
    await importer(page, gpx('test-alpes.gpx'));
    const reperes = () =>
      page.evaluate(() => {
        const haut = document.querySelector('.panel').getBoundingClientRect().top;
        return [...document.querySelectorAll('.track-marker')].map((m) => {
          const r = m.getBoundingClientRect();
          return r.left + r.width / 2 >= 0 && r.left + r.width / 2 <= innerWidth && r.top + r.height / 2 >= 0 && r.top + r.height / 2 < haut;
        });
      });
    const visibles = await reperes();
    controle('interface : départ et arrivée du tracé visibles au-dessus du rapport', visibles.length === 2 && visibles.every(Boolean), JSON.stringify(visibles));
    await page.tap('.panel__collapse', { timeout: 5000 }).catch(() => null);
    await page.waitForTimeout(1500);
    const hauteur = await page.evaluate(() => document.querySelector('.panel').getBoundingClientRect().height);
    const reduits = await reperes();
    controle('interface : rapport réduit à son titre, tracé visible au-dessus', hauteur < 100 && reduits.length === 2 && reduits.every(Boolean), `panneau de ${Math.round(hauteur)} px`);
    await capture(page, '7b-telephone-fr-rapport-reduit');

    // Recherche : Entrée juste après avoir complété « Bri » en « Brides » choisit Brides-les-Bains, pas Briançon.
    await page.tap('button[aria-label="Rechercher un lieu"]');
    await page.type('.search__input', 'Bri');
    await page.waitForSelector('.search__item', { timeout: 10000 });
    await page.type('.search__input', 'des');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(2500);
    const [, latitude] = (await page.evaluate(() => location.hash)).slice(1).split('/').map(Number);
    controle('interface : Entrée dans la recherche choisit le lieu de la saisie complète', Math.abs(latitude - 45.45) < 0.05, `latitude ${latitude}`);

    // Après un lieu choisi dans la recherche, les cadrages suivants restent justes (carte-1) : le tracé
    // importé est au-dessus du rapport, et un appui sur une zone blanche zoome dessus.
    await importer(page, gpx('test-alpes.gpx'));
    const apresRecherche = await reperes();
    controle('interface : après une recherche, le tracé importé est cadré au-dessus du rapport', apresRecherche.length === 2 && apresRecherche.every(Boolean), JSON.stringify(apresRecherche));
    if (await page.locator('.zone').count()) {
      const zoom = (hash) => Number(hash.slice(1).split('/')[0]);
      const avantZone = await page.evaluate(() => location.hash);
      await page.locator('.zone').first().tap();
      await page.waitForTimeout(2500);
      const apresZone = await page.evaluate(() => location.hash);
      controle('interface : après une recherche, un appui sur une zone blanche zoome dessus', zoom(apresZone) > zoom(avantZone), `${avantZone} puis ${apresZone}`);
    }
    await page.tap('.icon-btn[data-role="close"]');

    // Un panneau qui s'ouvre ferme la recherche, dont les résultats le recouvriraient.
    await page.tap('button[aria-label="Rechercher un lieu"]');
    await page.type('.search__input', 'Bri');
    await page.waitForSelector('.search__item', { timeout: 10000 });
    const credits = await page.evaluate(() => [...document.querySelectorAll('.search__credits a')].map((a) => `${a.textContent} ${a.getAttribute('href')} ${a.target}`).join(' | '));
    controle('interface : les crédits de la recherche renvoient vers la licence d\'OpenStreetMap', credits === 'OpenStreetMap https://www.openstreetmap.org/copyright _blank', credits);
    await page.tap('.tool[data-panel="network"]');
    await page.waitForTimeout(500);
    controle('interface : ouvrir un panneau ferme la recherche', await page.locator('.search').isHidden());
    const petites = await page.evaluate(() =>
      [...document.querySelectorAll('.panel .link, .panel .chip, .panel .select, .panel input[type=range], .icon-btn, .attribution__toggle, .attribution .link')]
        .filter((el) => el.getClientRects().length > 0 && el.getBoundingClientRect().height < 44)
        .map((el) => `${el.textContent.trim() || el.className} (${Math.round(el.getBoundingClientRect().height)} px)`),
    );
    controle('interface : cibles tactiles d\'au moins 44 px de haut', petites.length === 0, petites.join(', '));
    await page.tap('.icon-btn[data-role="close"]');

    // Fond Auto hors des données (Milan) : le fond OpenStreetMap, puis le Plan IGN de retour en France.
    await page.evaluate(() => (location.hash = '#9/45.46/9.19'));
    await page.waitForTimeout(2500);
    await page.tap('.tool[data-panel="basemap"]');
    const auto = (await page.locator('.radio:has(input[value="auto"]) small').textContent()) ?? '';
    await page.tap('.icon-btn[data-role="close"]');
    // Mention du fond OpenStreetMap : forme courte sur téléphone, avec les liens demandés par OpenTopoMap (carte-4).
    const mentionOsm = await page.evaluate(() => {
      const courte = document.querySelector('.attribution .credit-short');
      return courte ? `${courte.textContent} | ${[...courte.querySelectorAll('a')].map((a) => a.getAttribute('href')).join(' ')}` : '';
    });
    controle('interface : mention du fond OpenStreetMap avec ses liens', mentionOsm === '© OpenStreetMap, SRTM | © OpenTopoMap (CC-BY-SA) | https://openstreetmap.org/copyright http://opentopomap.org https://creativecommons.org/licenses/by-sa/3.0/', mentionOsm);
    await page.evaluate(() => (location.hash = '#10/44.9/6.45'));
    await page.waitForTimeout(2500);
    await page.tap('.tool[data-panel="basemap"]');
    const retour = (await page.locator('.radio:has(input[value="auto"]) small').textContent()) ?? '';
    await page.tap('.icon-btn[data-role="close"]');
    controle('interface : fond Auto hors des données, fond OpenStreetMap', /OpenTopoMap/.test(auto) && /Plan IGN/.test(retour), `${auto} | ${retour}`);

    controle('interface : aucune erreur JavaScript', suivi.erreurs.length === 0, suivi.erreurs.slice(0, 3).join(' | '));
    await contexte.close();
  }

  // --- 3. Téléphone, espagnol : sources et changement de langue -----------------
  {
    const { contexte, page, suivi } = await ouvrir(navigateur, telephone, '?lang=es#9/42.6/0.9');
    controle('es : langue de la page', (await page.evaluate(() => document.documentElement.lang)) === 'es');
    await page.click('button[aria-label="Ajustes"]');
    await page.click('[data-focus="sources"]');
    await page.waitForSelector('.disclaimer--strong');
    const mention = await page.locator('.disclaimer--strong').textContent();
    controle('es : panneau des sources', mention === 'Cobertura teórica, puede haber diferencias locales.', mention ?? '');
    const credits = await page.locator('.panel .plain li').allTextContents();
    const francais = credits.find((c) => /\s[:;]/.test(c));
    controle('es : ponctuation des mentions selon la langue (pas de « : » à la française)', credits.length > 0 && !francais, francais ?? credits[0]);
    // Champs du manifest : contour de chaque pays, logo de licence en lien, mention imposée des zones estimées ;
    // tous les liens s'ouvrent dans un nouvel onglet et ne mènent qu'à des pages https (sauf l'adresse d'OpenTopoMap).
    const publies = manifest?.countries ?? [];
    const panneau = await page.evaluate(() => ({
      contours: [...document.querySelectorAll('.panel__body p.hint')].filter((p) => p.textContent.startsWith('Límites del país: ')).length,
      logos: [...document.querySelectorAll('.panel__body a img.licence-logo')].map((img) => img.closest('a').getAttribute('href')),
      avis: [...document.querySelectorAll('.panel__body small')].map((s) => s.textContent),
      douteux: [...document.querySelectorAll('.panel__body a')].filter((a) => a.target !== '_blank' || !a.rel.includes('noopener') || !(a.protocol === 'https:' || a.href === 'http://opentopomap.org/')).map((a) => a.href),
    }));
    const contoursAttendus = publies.filter((c) => c.boundary?.text).length;
    controle('es : contour de chaque pays avec sa mention', contoursAttendus > 0 && panneau.contours === contoursAttendus, `${panneau.contours} sur ${contoursAttendus}`);
    const logosAttendus = publies.flatMap((c) => c.sources.filter((s) => s.licenceLogo && s.licenceLogoUrl).map((s) => s.licenceLogoUrl));
    controle('es : logo de licence en lien vers l\'adresse du manifest', panneau.logos.join() === logosAttendus.join(), panneau.logos.join() || 'aucun');
    const avisAttendus = publies.flatMap((c) => c.sources.filter((s) => s.type === 2 && s.licenceNotice).map((s) => s.licenceNotice));
    controle('es : mention de licence imposée des zones estimées', avisAttendus.every((a) => panneau.avis.includes(a)), `${avisAttendus.length} mention(s) attendue(s)`);
    controle('es : liens des sources dans un nouvel onglet, vers des pages https', panneau.douteux.length === 0, panneau.douteux.join(', '));
    await capture(page, '9-telephone-es-sources');
    await page.click('.icon-btn[aria-label="Volver"]');
    await page.selectOption('#langue', 'ca');
    await page.waitForTimeout(600);
    controle('ca : changement de langue dans les paramètres', (await page.evaluate(() => document.documentElement.lang)) === 'ca' && (await page.title()) === 'Mapa de zones sense cobertura', await page.title());
    await page.selectOption('#langue', 'it');
    await page.waitForTimeout(600);
    controle('it : changement de langue dans les paramètres', (await page.title()) === 'Mappa delle zone senza copertura', await page.title());
    controle('es : aucune erreur JavaScript', suivi.erreurs.length === 0, suivi.erreurs.slice(0, 3).join(' | '));
    await contexte.close();
  }

  // --- 4. Ordinateur, français : les deux GPX de test, de part et d'autre d'une frontière ------
  // Chaque contrôle ne joue que si le pays étranger du tracé est publié : sinon il est annoncé comme sauté.
  {
    const cas = [
      { nom: 'test-alpes.gpx', iso: 'IT', pays: 'Italie', zoneAttendue: null },
      // Côté espagnol, l'arrivée au refuge de Góriz n'a aucun réseau 4G dans la carte du ministère.
      { nom: 'test-pyrenees.gpx', iso: 'ES', pays: 'Espagne', zoneAttendue: /km \d+,\d à \d+,\d, soit [^\n]*, Espagne/ },
    ];
    for (const { nom, iso, pays, zoneAttendue } of cas) {
      const fichier = echantillon(nom);
      if (!fichier || !paysPublies.includes('FR') || !paysPublies.includes(iso)) {
        console.log(`SAUTÉ étranger : ${nom} (${fichier ? `${pays} absente des données publiées` : 'fichier absent'})`);
        continue;
      }
      const { contexte, page, suivi } = await ouvrir(navigateur, ordinateur, '');
      await importer(page, fichier);
      const texte = await page.locator('.report-text').inputValue();
      controle(`étranger : ${nom} traverse la France et l'${pays}`, texte.includes(`Pays traversés : France, ${pays}`), (texte.match(/Pays traversés[^\n]*/) ?? [''])[0]);
      controle(`étranger : ${nom}, la couverture est lue des deux côtés`, new RegExp(`Opérateur : [^\\n]*\\(France\\)[^\\n]*\\(${pays}\\)`).test(texte) && !texte.includes('Hors de la zone couverte par les données'), (texte.match(/Opérateur[^\n]*/) ?? [''])[0]);
      controle(`étranger : ${nom}, source qui dit seulement couvert ou non`, texte.includes(`${pays} : la source indique seulement si un lieu est couvert ou non.`));
      if (zoneAttendue) controle(`étranger : ${nom}, zone blanche côté ${pays}`, zoneAttendue.test(texte), (texte.match(zoneAttendue) ?? [''])[0]);
      controle(`étranger : ${nom}, aucune erreur JavaScript`, suivi.erreurs.length === 0, suivi.erreurs.slice(0, 3).join(' | '));
      await capture(page, `10-ordinateur-fr-${nom.replace('.gpx', '')}`);
      await contexte.close();
    }
  }
} finally {
  await navigateur.close();
}

const echecs = resultats.filter((r) => !r.ok);
console.log(`\n${resultats.length - echecs.length} contrôle(s) réussi(s), ${echecs.length} échec(s) sur ${SITE}`);
process.exit(echecs.length === 0 ? 0 : 1);
