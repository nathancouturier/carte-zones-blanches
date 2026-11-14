// Coque hors ligne du site : index.html et tous les fichiers qu'il charge.
//
// Ce module sert à la construction (vite.config.ts, sous Node), pas dans le
// navigateur. Une fois le site construit, il dresse la liste des fichiers de la
// coque, en tire une version (empreinte de leur contenu) et l'écrit dans
// dist/sw.js. Le Service Worker enregistre alors ces fichiers ensemble, dans un
// cache propre à cette version : index.html ne peut plus être servi sans ses
// scripts, ni avec ceux d'une autre version (voir public/sw.js).

import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';
import type { Plugin } from 'vite';

export interface ShellList {
  /** Version de la coque : empreinte du contenu de tous ses fichiers. */
  version: string;
  /** Empreinte SHA-256 d'index.html, vérifiée par le Service Worker à l'installation. */
  index: string;
  /** Fichiers à enregistrer, relatifs à la racine du site ; « ./ » est index.html. */
  files: string[];
}

/** Ligne de public/sw.js remplacée à la construction. */
const SHELL_LINE = /^const SHELL = .*;$/m;

/** Écrit la liste de la coque dans le texte du Service Worker. */
export function injectShell(source: string, shell: ShellList): string {
  if (!SHELL_LINE.test(source)) throw new Error('public/sw.js : ligne « const SHELL = ...; » introuvable');
  return source.replace(SHELL_LINE, () => `const SHELL = ${JSON.stringify(shell)};`);
}

/** Vrai pour un fichier construit qui fait partie de la coque. */
export function isShellFile(path: string): boolean {
  // Les données (manifest et archives) changent sans nouvelle version du site : elles sont
  // enregistrées tracé par tracé. Les cartes de source ne servent qu'au débogage.
  return path !== 'sw.js' && !path.startsWith('data/') && !path.endsWith('.map');
}

/** Liste de la coque pour des fichiers construits (chemins relatifs à la racine du site). */
export function shellList(files: { path: string; content: Buffer }[]): ShellList {
  const kept = files.filter((f) => isShellFile(f.path)).sort((a, b) => (a.path < b.path ? -1 : 1));
  const index = kept.find((f) => f.path === 'index.html');
  if (!index) throw new Error('coque hors ligne : index.html introuvable');
  const all = createHash('sha256');
  for (const file of kept) all.update(file.path).update('\0').update(file.content).update('\0');
  return {
    version: all.digest('hex').slice(0, 12),
    index: createHash('sha256').update(index.content).digest('hex'),
    files: kept.map((f) => (f.path === 'index.html' ? './' : f.path)),
  };
}

function listFiles(dir: string, root = dir): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    return entry.isDirectory() ? listFiles(path, root) : [relative(root, path).split(sep).join('/')];
  });
}

/** Extension de Vite : écrit la coque dans dist/sw.js à la fin de la construction. */
export function offlineShell(): Plugin {
  let outDir = 'dist';
  return {
    name: 'czb-coque-hors-ligne',
    apply: 'build',
    configResolved(config) {
      outDir = resolve(config.root, config.build.outDir);
    },
    closeBundle() {
      const files = listFiles(outDir).map((path) => ({ path, content: readFileSync(join(outDir, path)) }));
      const shell = shellList(files);
      const sw = join(outDir, 'sw.js');
      writeFileSync(sw, injectShell(readFileSync(sw, 'utf8'), shell));
      console.log(`coque hors ligne ${shell.version} : ${shell.files.length} fichiers`);
    },
  };
}
