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

function gpx(nom) {
  const chemin = fileURLToPath(new URL(`../samples/${nom}`, import.meta.url));
  if (existsSync(chemin)) return { name: nom, mimeType: 'application/gpx+xml', buffer: readFileSync(chemin) };
  return { name: 'secours.gpx', mimeType: 'application/gpx+xml', buffer: Buffer.from(GPX_SECOURS) };
}

async function ouvrir(navigateur, options, chemin) {
  const contexte = await navigateur.newContext(options);
  const page = await contexte.newPage();
  const suivi = { reponses: new Map(), erreurs: [], echecs: new Map() };
  page.on('response', (r) => {
    const hote = new URL(r.url()).host;
    const cle = `${hote} ${r.status() < 400 ? 'ok' : 'ko'}`;
    suivi.reponses.set(cle, (suivi.reponses.get(cle) ?? 0) + 1);
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
const hoteSite = new URL(SITE).host;

try {
  // --- 1. Ordinateur, français : carte, réseau, recherche, GPX ------------------
  {
    const { contexte, page, suivi } = await ouvrir(navigateur, ordinateur, '#10.5/44.9/6.45');
    controle('fr : langue de la page', (await page.evaluate(() => document.documentElement.lang)) === 'fr');
    controle('fr : titre', (await page.title()) === 'Carte des zones blanches', await page.title());
    if (!HORS_LIGNE) controle('fr : fond Plan IGN chargé', ok(suivi, 'data.geopf.fr') >= 4, `${ok(suivi, 'data.geopf.fr')} réponses de data.geopf.fr`);
    controle('fr : manifest et tuiles de couverture lus', ok(suivi, hoteSite) >= 3, `${ok(suivi, hoteSite)} réponses du site`);
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
