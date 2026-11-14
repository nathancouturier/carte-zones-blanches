// Export d'un GPX enrichi : le fichier d'origine, plus un point de passage au
// début et à la fin de chaque zone blanche, pour les voir sur une montre ou
// une application GPS.

import { trimXmlStart } from './parse';

export interface ExtraWaypoint {
  lon: number;
  lat: number;
  ele: number | null;
  name: string;
  desc: string;
  /** Nom de symbole (convention Garmin), ignoré par les applications qui ne le connaissent pas. */
  sym: string;
}

export interface XmlTools {
  parse(text: string): Document;
  serialize(doc: Document): string;
}

export function browserXmlTools(): XmlTools {
  return {
    parse: (text) => new DOMParser().parseFromString(text, 'text/xml'),
    serialize: (doc) => new XMLSerializer().serializeToString(doc),
  };
}

/** Type marquant les points ajoutés, pour pouvoir les retirer si le fichier est réimporté. */
export const WAYPOINT_TYPE = 'zone-blanche';

function elementChildren(node: Element): Element[] {
  const out: Element[] = [];
  for (let child = node.firstChild; child; child = child.nextSibling) {
    if (child.nodeType === 1) out.push(child as Element);
  }
  return out;
}

function localName(el: Element): string {
  return (el.localName || el.nodeName).replace(/^.*:/, '').toLowerCase();
}

/**
 * Ajoute les points de passage au GPX. Le reste du fichier (trace, routes,
 * extensions) est conservé tel quel. Les points déjà ajoutés par un export
 * précédent sont remplacés.
 */
export function enrichGpx(xml: string, waypoints: readonly ExtraWaypoint[], tools: XmlTools = browserXmlTools()): string {
  const doc = tools.parse(trimXmlStart(xml));
  const root = doc.documentElement;
  if (!root || localName(root) !== 'gpx') throw new Error('GPX invalide');
  const ns = root.namespaceURI;
  const create = (name: string): Element => (ns ? doc.createElementNS(ns, name) : doc.createElement(name));
  const withText = (name: string, text: string): Element => {
    const el = create(name);
    el.appendChild(doc.createTextNode(text));
    return el;
  };

  // Retire les points d'un export précédent.
  for (const child of elementChildren(root)) {
    if (localName(child) !== 'wpt') continue;
    const type = elementChildren(child).find((c) => localName(c) === 'type');
    if (type && (type.textContent ?? '').trim() === WAYPOINT_TYPE) root.removeChild(child);
  }

  // Le schéma GPX impose l'ordre : metadata, wpt, rte, trk, extensions.
  const children = elementChildren(root);
  let anchor: Element | null = null;
  for (const child of children) {
    const name = localName(child);
    if (name === 'rte' || name === 'trk' || name === 'extensions') {
      anchor = child;
      break;
    }
  }

  for (const w of waypoints) {
    const wpt = create('wpt');
    wpt.setAttribute('lat', w.lat.toFixed(6));
    wpt.setAttribute('lon', w.lon.toFixed(6));
    // Ordre imposé dans un point : ele, name, desc, sym, type.
    if (w.ele !== null && Number.isFinite(w.ele)) wpt.appendChild(withText('ele', w.ele.toFixed(1)));
    wpt.appendChild(withText('name', w.name));
    wpt.appendChild(withText('desc', w.desc));
    wpt.appendChild(withText('sym', w.sym));
    wpt.appendChild(withText('type', WAYPOINT_TYPE));
    if (anchor) root.insertBefore(wpt, anchor);
    else root.appendChild(wpt);
  }

  let text = tools.serialize(doc);
  if (!/^\s*<\?xml/.test(text)) text = `<?xml version="1.0" encoding="UTF-8"?>\n${text}`;
  return text;
}

/** Nom du fichier exporté : « rando.gpx » devient « rando-zones-blanches.gpx ». */
export function enrichedFileName(original: string | null, suffix: string): string {
  const base = (original ?? 'trace').replace(/\.gpx$/i, '').replace(/[\\/:*?"<>|]+/g, '-').trim() || 'trace';
  return `${base}-${suffix}.gpx`;
}
