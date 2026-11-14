// « Ma position » : suivi continu sans verrou de la carte, recentrage à l'appui, arrêt quand la page
// est cachée, un message par cause d'échec (carte-5).

import { describe, expect, it } from 'vitest';
import { accuracyBounds, Locator, metersPerPixel, type LocateProblem, type UserPosition } from '../src/map/locator';

/** Fausse géolocalisation : on lui fait envoyer des positions et des erreurs. */
function fausseGeolocalisation() {
  const suivis = new Map<number, { succes: PositionCallback; erreur?: PositionErrorCallback | null }>();
  let numero = 0;
  let demandes = 0;
  return {
    api: {
      watchPosition(succes: PositionCallback, erreur?: PositionErrorCallback | null): number {
        demandes += 1;
        suivis.set(++numero, { succes, erreur });
        return numero;
      },
      clearWatch(id: number): void {
        suivis.delete(id);
      },
    },
    position(lat: number, lon: number, accuracy = 20): void {
      for (const { succes } of suivis.values()) succes({ coords: { latitude: lat, longitude: lon, accuracy } } as GeolocationPosition);
    },
    erreur(code: number): void {
      for (const { erreur } of suivis.values()) erreur?.({ code, message: 'simulée' } as GeolocationPositionError);
    },
    actifs: () => suivis.size,
    demandes: () => demandes,
  };
}

function creer(slowAfterMs = 10_000) {
  const geo = fausseGeolocalisation();
  const vu: { position: UserPosition | null; ancienne: boolean }[] = [];
  const centres: UserPosition[] = [];
  const problemes: LocateProblem[] = [];
  const locator = new Locator({
    geolocation: geo.api,
    show: (position, ancienne) => vu.push({ position, ancienne }),
    center: (position) => centres.push(position),
    onProblem: (probleme) => problemes.push(probleme),
    slowAfterMs,
  });
  return { geo, locator, vu, centres, problemes };
}

describe('Ma position', () => {
  it('le point suit la marche sans déplacer la carte ; chaque appui recentre, sans jamais couper le suivi', async () => {
    const { geo, locator, vu, centres } = creer();
    const appui = locator.locate();
    expect(geo.actifs()).toBe(1);
    geo.position(44.9, 6.42);
    await appui;
    expect(centres).toHaveLength(1); // la carte se centre une fois, pour cet appui
    geo.position(44.901, 6.421);
    geo.position(44.902, 6.422);
    expect(vu.at(-1)?.position).toMatchObject({ lat: 44.902, lon: 6.422 }); // le point suit
    expect(centres).toHaveLength(1); // la carte, elle, ne bouge pas
    await locator.locate(); // second appui : recentrage immédiat sur la dernière position
    expect(centres).toHaveLength(2);
    expect(centres[1]).toMatchObject({ lat: 44.902, lon: 6.422 });
    expect(geo.actifs()).toBe(1); // le suivi continue, un seul
    expect(geo.demandes()).toBe(1);
  });

  it('un cadrage commandé par le site avant le premier point l\'emporte : la position ne recentre pas la carte', async () => {
    const { geo, locator, vu, centres } = creer();
    const appui = locator.locate();
    locator.cancelCenter(); // import d'un GPX, zone du rapport, recherche, ou geste sur la carte
    geo.position(44.9, 6.42);
    await appui;
    expect(vu.at(-1)?.position).toMatchObject({ lat: 44.9 }); // le point s'affiche
    expect(centres).toHaveLength(0);
  });

  it('page cachée : le suivi s\'arrête et le point devient ancien ; au retour, il reprend sans bouger la carte', async () => {
    const { geo, locator, vu, centres } = creer();
    const appui = locator.locate();
    geo.position(44.9, 6.42);
    await appui;
    locator.setVisible(false);
    expect(geo.actifs()).toBe(0);
    expect(vu.at(-1)).toMatchObject({ ancienne: true });
    locator.setVisible(true);
    expect(geo.actifs()).toBe(1);
    geo.position(44.95, 6.5);
    expect(vu.at(-1)).toMatchObject({ ancienne: false, position: { lat: 44.95 } });
    expect(centres).toHaveLength(1);
  });

  it('sans appui, la page qui revient ne démarre aucun suivi', () => {
    const { geo, locator } = creer();
    locator.setVisible(false);
    locator.setVisible(true);
    expect(geo.demandes()).toBe(0);
  });

  it('un message par cause : refus (suivi arrêté), position indisponible et délai dépassé (suivi qui continue)', async () => {
    const { geo, locator, vu, problemes } = creer();
    let appui = locator.locate();
    geo.erreur(1); // PERMISSION_DENIED
    await appui;
    expect(problemes).toEqual(['denied']);
    expect(geo.actifs()).toBe(0);
    expect(vu.at(-1)?.position).toBeNull();

    appui = locator.locate();
    geo.erreur(2); // POSITION_UNAVAILABLE
    await appui;
    expect(problemes).toEqual(['denied', 'unavailable']);
    expect(geo.actifs()).toBe(1);
    geo.erreur(2); // répété par le navigateur : dit une seule fois par appui
    geo.erreur(3); // TIMEOUT
    expect(problemes).toEqual(['denied', 'unavailable', 'timeout']);
  });

  it('signal perdu en marchant, après un premier point : pas de message, le point devient gris jusqu\'au suivant', async () => {
    const { geo, locator, vu, problemes } = creer();
    const appui = locator.locate();
    geo.position(44.9, 6.42);
    await appui;
    geo.erreur(2);
    geo.erreur(3);
    expect(problemes).toEqual([]);
    expect(vu.at(-1)).toMatchObject({ ancienne: true, position: { lat: 44.9 } });
    geo.position(44.901, 6.42);
    expect(vu.at(-1)).toMatchObject({ ancienne: false, position: { lat: 44.901 } });
  });

  it('GPS lent : on prévient qu\'il cherche encore, le bouton cesse d\'attendre, et le point recentre la carte à son arrivée', async () => {
    const { geo, locator, centres, problemes } = creer(30);
    await locator.locate(); // se termine au bout du délai, sans position
    expect(problemes).toEqual(['timeout']);
    geo.position(44.9, 6.42);
    expect(centres).toHaveLength(1);
  });

  it('sans géolocalisation dans le navigateur : position indisponible', async () => {
    const problemes: LocateProblem[] = [];
    const locator = new Locator({ geolocation: undefined, show: () => undefined, center: () => undefined, onProblem: (p) => problemes.push(p) });
    await locator.locate();
    expect(problemes).toEqual(['unavailable']);
  });

  it('taille du cercle de précision', () => {
    // Équateur, zoom 0 : 40 075 km sur 512 px.
    expect(metersPerPixel(0, 0)).toBeCloseTo(78271.5, 0);
    expect(metersPerPixel(60, 1)).toBeCloseTo(78271.5 / 4, 0);
    const [ouest, sud, est, nord] = accuracyBounds({ lon: 6.42, lat: 44.9, accuracy: 1113.2 });
    expect(nord - sud).toBeCloseTo(0.02, 4);
    expect(est - ouest).toBeCloseTo(0.02 / Math.cos((44.9 * Math.PI) / 180), 4);
  });
});
