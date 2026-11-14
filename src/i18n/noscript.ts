// Message de la page sans JavaScript (<noscript>), dans chaque langue du site.
//
// Ce module sert à la construction (vite.config.ts, sous Node), pas dans le
// navigateur. Sans JavaScript, la page ne peut pas choisir sa langue : elle donne
// la phrase « app.noscript » de chaque fichier de langue, chacune avec son
// attribut lang. Une langue ajoutée dans src/i18n/locales y figure d'elle-même.

import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import type { Plugin } from 'vite';

export interface NoscriptLine {
  /** Code de la langue, nom de son fichier (« fr », « de »...). */
  lang: string;
  text: string;
}

const NOSCRIPT = /<noscript>[\s\S]*?<\/noscript>/;

const escapeHtml = (text: string): string => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** Phrases « app.noscript » des fichiers de langue d'un dossier : le français d'abord, puis par code. */
export function noscriptLines(dir: string): NoscriptLine[] {
  return readdirSync(dir)
    .filter((name) => /^[A-Za-z-]+\.json$/.test(name))
    .map((name) => ({ lang: name.slice(0, -'.json'.length), text: (JSON.parse(readFileSync(join(dir, name), 'utf8')) as Record<string, unknown>)['app.noscript'] }))
    .filter((line): line is NoscriptLine => typeof line.text === 'string' && line.text.trim() !== '')
    .sort((a, b) => Number(b.lang === 'fr') - Number(a.lang === 'fr') || a.lang.localeCompare(b.lang));
}

/** Remplace le contenu de l'élément <noscript> de la page : une phrase par langue. */
export function injectNoscript(html: string, lines: readonly NoscriptLine[]): string {
  if (!NOSCRIPT.test(html)) throw new Error('index.html : élément <noscript> introuvable');
  const paragraphs = lines.map((line) => `<p lang="${line.lang}">${escapeHtml(line.text)}</p>`).join('');
  return html.replace(NOSCRIPT, () => `<noscript>${paragraphs}</noscript>`);
}

/** Extension de Vite : écrit le message <noscript> dans chaque langue, en construction comme en développement. */
export function noscriptMessages(): Plugin {
  let dir = resolve('src/i18n/locales');
  return {
    name: 'czb-noscript',
    configResolved(config) {
      dir = resolve(config.root, 'src/i18n/locales');
    },
    transformIndexHtml(html) {
      return injectNoscript(html, noscriptLines(dir));
    },
  };
}
