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

function gpx(nom) {
  const chemin = fileURLToPath(new URL(`../samples/${nom}`, import.meta.url));
  if (existsSync(chemin)) return { name: nom, mimeType: 'application/gpx+xml', buffer: readFileSync(chemin) };
  return { name: 'secours.gpx', mimeType: 'application/gpx+xml', buffer: Buffer.from(GPX_SECOURS) };
}

async function ouvrir(navigateur, options, chemin) {
  const contexte = await navigateur.newContext(options);
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
    await capture(page, '1-ordinateur-fr-carte');

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
      await zone.click();
      await page.waitForTimeout(2500);
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
    const outils = await page.locator('.toolbar .tool span').allTextContents();
    controle('de : barre d\'outils traduite', outils.join('|') === 'Netz|Karte|GPX importieren', outils.join('|'));
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
    await importer(page, TRACE_FRANCE);
    await page.locator('[data-focus="hors-ligne"]').scrollIntoViewIfNeeded();
    await page.click('[data-focus="hors-ligne"]');
    const pret = await page.waitForSelector('.offline-ready', { timeout: 180000 }).then(() => true, () => false);
    const bilan = pret ? ((await page.locator('.offline-ready').textContent()) ?? '') : '';
    controle('hors ligne : le tracé est enregistré', pret && /tuiles de couverture/.test(bilan), bilan);
    if (!HORS_LIGNE) controle('hors ligne : le fond Plan IGN est enregistré', /et \d[\d\s\u202f]* tuiles de fond/.test(bilan), bilan);
    await capture(page, '8b-telephone-fr-hors-ligne-pret');

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
    await contexte.setOffline(false);
    controle('hors ligne : aucune erreur JavaScript', suivi.erreurs.length === 0, suivi.erreurs.slice(0, 3).join(' | '));
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
} finally {
  await navigateur.close();
}

const echecs = resultats.filter((r) => !r.ok);
console.log(`\n${resultats.length - echecs.length} contrôle(s) réussi(s), ${echecs.length} échec(s) sur ${SITE}`);
process.exit(echecs.length === 0 ? 0 : 1);
