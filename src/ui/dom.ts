// Petits outils pour bâtir l'interface sans bibliothèque.

export type Child = Node | string | number | null | undefined | false | Child[];

type Attrs = Record<string, unknown>;

function append(parent: Node, child: Child): void {
  if (child === null || child === undefined || child === false) return;
  if (Array.isArray(child)) {
    for (const c of child) append(parent, c);
    return;
  }
  parent.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
}

/**
 * Crée un élément. Les attributs qui commencent par « on » sont des écouteurs
 * (onclick, oninput), « class » et « dataset » sont gérés à part, et un
 * attribut à false ou null est ignoré.
 */
export function h<K extends keyof HTMLElementTagNameMap>(tag: K, attrs?: Attrs | null, ...children: Child[]): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  if (attrs) {
    for (const [name, value] of Object.entries(attrs)) {
      if (value === null || value === undefined || value === false) continue;
      if (name.startsWith('on') && typeof value === 'function') {
        el.addEventListener(name.slice(2).toLowerCase(), value as EventListener);
      } else if (name === 'class') {
        el.className = String(value);
      } else if (name === 'dataset' && typeof value === 'object') {
        for (const [k, v] of Object.entries(value as Record<string, string>)) el.dataset[k] = v;
      } else if (name === 'style' && typeof value === 'object') {
        for (const [k, v] of Object.entries(value as Record<string, string>)) el.style.setProperty(k, v);
      } else if (value === true) {
        el.setAttribute(name, '');
      } else {
        el.setAttribute(name, String(value));
      }
    }
  }
  append(el, children);
  return el;
}

/** Lien vers un autre site : il s'ouvre dans un nouvel onglet, sans accès à la page du site. */
export function externalLink(text: string, href: string): HTMLAnchorElement {
  return h('a', { href, target: '_blank', rel: 'noopener noreferrer' }, text);
}

/** Mention faite de morceaux de texte, dont certains renvoient vers une adresse. */
export function creditNodes(parts: readonly { text: string; href?: string }[]): (Node | string)[] {
  return parts.map((part) => (part.href ? externalLink(part.text, part.href) : part.text));
}

/** Texte traduit dont un nom propre (« OpenStreetMap », par exemple) devient un lien. */
export function linkName(text: string, name: string, href: string): (Node | string)[] {
  const at = text.indexOf(name);
  if (at === -1) return [text];
  return [text.slice(0, at), externalLink(name, href), text.slice(at + name.length)];
}

/** Remplace le contenu d'un élément. */
export function setChildren(parent: Element, ...children: Child[]): void {
  parent.replaceChildren();
  append(parent, children);
}

/** Élément SVG à partir d'un chemin d'icône (grille de 24 x 24). */
export function icon(path: string, size = 24): SVGSVGElement {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('width', String(size));
  svg.setAttribute('height', String(size));
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('focusable', 'false');
  svg.setAttribute('fill', 'none');
  svg.setAttribute('stroke', 'currentColor');
  svg.setAttribute('stroke-width', '2');
  svg.setAttribute('stroke-linecap', 'round');
  svg.setAttribute('stroke-linejoin', 'round');
  for (const d of path.split('|')) {
    const p = document.createElementNS(ns, 'path');
    p.setAttribute('d', d);
    svg.appendChild(p);
  }
  return svg;
}

/** Icônes au trait (plusieurs chemins séparés par « | »). */
export const ICONS = {
  search: 'M11 4a7 7 0 1 0 0 14a7 7 0 0 0 0-14z|M20 20l-3.9-3.9',
  network: 'M4 20v-3|M9 20v-7|M14 20v-11|M19 20V5',
  layers: 'M12 3l9 5-9 5-9-5 9-5z|M3 13l9 5 9-5|M3 17.5l9 5 9-5',
  upload: 'M12 16V4|M7 9l5-5 5 5|M4 16v3a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-3',
  report: 'M7 3h7l5 5v12a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z|M14 3v5h5|M9 13h6|M9 17h6',
  settings:
    'M12 9a3 3 0 1 0 0 6a3 3 0 0 0 0-6z|M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3a1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5a1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8a1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1a1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5a1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
  locate: 'M12 8a4 4 0 1 0 0 8a4 4 0 0 0 0-8z|M12 2v3|M12 19v3|M2 12h3|M19 12h3',
  close: 'M6 6l12 12|M18 6L6 18',
  back: 'M15 5l-7 7 7 7',
  copy: 'M9 9h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1V10a1 1 0 0 1 1-1z|M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1',
  download: 'M12 4v12|M7 11l5 5 5-5|M4 20h16',
  warning: 'M12 3l10 17H2L12 3z|M12 10v4|M12 17.5v.01',
  info: 'M12 3a9 9 0 1 0 0 18a9 9 0 0 0 0-18z|M12 11v6|M12 7.5v.01',
  trash: 'M4 7h16|M9 7V4h6v3|M6 7l1 13h10l1-13',
  chevron: 'M9 6l6 6-6 6',
  chevronDown: 'M6 9l6 6 6-6',
  chevronUp: 'M6 15l6-6 6 6',
};
