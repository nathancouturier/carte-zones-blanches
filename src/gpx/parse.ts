// Lecture d'un fichier GPX : traces, routes et multi-segments.

import { gpx as gpxToGeoJson } from '@tmcw/togeojson';

export interface TrackPoint {
  lon: number;
  lat: number;
  /** Altitude en mètres, ou null si le GPX n'en donne pas. */
  ele: number | null;
}

export interface ParsedGpx {
  /** Nom de la trace ou de la route, s'il existe. */
  name: string | null;
  /** Segments du parcours, dans l'ordre du fichier. */
  segments: TrackPoint[][];
  /** Ce qui a servi à bâtir le parcours. */
  kind: 'track' | 'route';
  /** Vrai si tous les points ont une altitude. */
  hasElevation: boolean;
  pointCount: number;
}

export type GpxErrorCode = 'invalid' | 'empty';

export class GpxError extends Error {
  constructor(readonly code: GpxErrorCode) {
    super(code);
    this.name = 'GpxError';
  }
}

/** Analyseur XML : le DOMParser du navigateur, ou un équivalent dans les tests. */
export interface XmlParser {
  parseFromString(text: string, type: 'text/xml'): Document;
}

/**
 * Retire les blancs et la marque d'ordre des octets (BOM) qui précèdent parfois
 * la déclaration XML (sortie de certains scripts) : le navigateur refuserait le fichier.
 */
export function trimXmlStart(text: string): string {
  return text.replace(/^[\s﻿]+/, '');
}

const XMLNS_NS = 'http://www.w3.org/2000/xmlns/';

/**
 * Copie du document où les éléments GPX n'ont plus de préfixe (« gpx:trk »
 * devient « trk », dans le même espace de noms) : togeojson cherche les
 * éléments par leur nom complet et ne trouverait rien. Les extensions des
 * autres espaces de noms sont recopiées telles quelles.
 */
function withoutPrefix(doc: Document, ns: string): Document {
  const copy = doc.implementation.createDocument(ns, 'gpx', null);
  const fill = (from: Element, to: Element): void => {
    for (const attr of Array.from(from.attributes)) {
      if (attr.namespaceURI === XMLNS_NS && attr.value === ns) continue; // déclaration du préfixe, devenue inutile
      if (attr.namespaceURI) to.setAttributeNS(attr.namespaceURI, attr.name, attr.value);
      else to.setAttribute(attr.name, attr.value);
    }
    for (let child = from.firstChild; child; child = child.nextSibling) {
      if (child.nodeType === 1 && (child as Element).namespaceURI === ns) {
        const element = copy.createElementNS(ns, (child as Element).localName);
        fill(child as Element, element);
        to.appendChild(element);
      } else if (child.nodeType === 1 || child.nodeType === 3 || child.nodeType === 4) {
        to.appendChild(copy.importNode(child, true));
      }
    }
  };
  fill(doc.documentElement, copy.documentElement);
  return copy;
}

function toSegment(coords: unknown): TrackPoint[] {
  if (!Array.isArray(coords)) return [];
  const points: TrackPoint[] = [];
  for (const c of coords) {
    if (!Array.isArray(c)) continue;
    const lon = Number(c[0]);
    const lat = Number(c[1]);
    if (!Number.isFinite(lon) || !Number.isFinite(lat) || Math.abs(lat) > 90 || Math.abs(lon) > 180) continue;
    const ele = c.length > 2 && c[2] !== null && Number.isFinite(Number(c[2])) ? Number(c[2]) : null;
    points.push({ lon, lat, ele });
  }
  return points;
}

/**
 * Analyse le texte d'un GPX. S'il contient des traces, on les utilise ; sinon
 * on se rabat sur les routes. Plusieurs traces ou segments forment un seul
 * parcours, dans l'ordre du fichier.
 */
export function parseGpx(text: string, parser?: XmlParser): ParsedGpx {
  const xmlParser = parser ?? (new DOMParser() as unknown as XmlParser);
  let doc: Document;
  try {
    doc = xmlParser.parseFromString(trimXmlStart(text), 'text/xml');
  } catch {
    throw new GpxError('invalid');
  }
  if (!doc || !doc.documentElement || doc.getElementsByTagName('parsererror').length > 0) {
    throw new GpxError('invalid');
  }
  const root = doc.documentElement;
  // Le nom local ignore le préfixe : « gpx:gpx » (sorties JAXB ou XSLT) est aussi un GPX.
  if ((root.localName ?? root.nodeName).toLowerCase() !== 'gpx') throw new GpxError('invalid');
  if (root.prefix && root.namespaceURI) doc = withoutPrefix(doc, root.namespaceURI);

  let collection: ReturnType<typeof gpxToGeoJson>;
  try {
    collection = gpxToGeoJson(doc);
  } catch {
    throw new GpxError('invalid');
  }

  const tracks: TrackPoint[][] = [];
  const routes: TrackPoint[][] = [];
  let trackName: string | null = null;
  let routeName: string | null = null;
  for (const feature of collection.features) {
    const geometry = feature.geometry;
    if (!geometry) continue;
    const props = (feature.properties ?? {}) as Record<string, unknown>;
    const isRoute = props._gpxType === 'rte';
    const target = isRoute ? routes : tracks;
    const name = typeof props.name === 'string' && props.name.trim() !== '' ? props.name.trim() : null;
    if (geometry.type === 'LineString') {
      target.push(toSegment(geometry.coordinates));
    } else if (geometry.type === 'MultiLineString') {
      for (const line of geometry.coordinates) target.push(toSegment(line));
    } else {
      continue; // points de passage
    }
    if (isRoute) routeName ??= name;
    else trackName ??= name;
  }

  const usable = (segments: TrackPoint[][]): TrackPoint[][] => segments.filter((s) => s.length >= 2);
  const fromTracks = usable(tracks);
  const fromRoutes = usable(routes);
  const segments = fromTracks.length > 0 ? fromTracks : fromRoutes;
  if (segments.length === 0) throw new GpxError('empty');
  const kind = fromTracks.length > 0 ? 'track' : 'route';
  let pointCount = 0;
  let hasElevation = true;
  for (const segment of segments) {
    pointCount += segment.length;
    if (hasElevation && segment.some((p) => p.ele === null)) hasElevation = false;
  }
  return { name: kind === 'track' ? trackName : routeName, segments, kind, hasElevation, pointCount };
}
