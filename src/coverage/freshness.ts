// Nouvelle publication des données pendant qu'une page est ouverte.
//
// Les archives portent la date de leur construction et le déploiement ne garde
// que la dernière publication : un onglet resté ouvert demande alors des
// archives qui n'existent plus. Le serveur répond 404 (GitHub Pages), ou une
// page qui n'est pas une archive (serveur de développement). Sur une erreur de
// lecture, on relit donc manifest.json, et on repart sur les nouvelles données
// si elles ont changé.

import { isAbortError } from './abort';
import type { Manifest } from './manifest';

/** Vrai si deux manifests décrivent les mêmes données (même génération, mêmes archives). */
export function sameData(a: Manifest, b: Manifest): boolean {
  const files = (m: Manifest): string => m.archives.map((archive) => archive.file).join('\n');
  return a.generated === b.generated && files(a) === files(b);
}

/** Intervalle minimal entre deux relectures du manifest qui n'ont rien trouvé de nouveau, en millisecondes. */
export const MANIFEST_RECHECK_MS = 60_000;

export class NewDataWatcher {
  private checking: Promise<void> | null = null;
  private lastCheck = -Infinity;

  constructor(
    private current: Manifest,
    /** Relit manifest.json sans passer par le cache. */
    private readonly fetchManifest: () => Promise<Manifest>,
    /** Appelé avec le nouveau manifest quand les données ont changé. */
    private readonly onNewData: (manifest: Manifest) => void,
    private readonly minIntervalMs = MANIFEST_RECHECK_MS,
    private readonly now: () => number = () => Date.now(),
  ) {}

  /**
   * À appeler sur chaque erreur de lecture d'une archive. Relit le manifest à la
   * première erreur, une seule fois pour des erreurs simultanées, puis au plus
   * une fois par intervalle tant que rien ne change. Les annulations sont ignorées.
   */
  report(error: unknown): Promise<void> {
    if (isAbortError(error)) return Promise.resolve();
    if (this.checking) return this.checking;
    if (this.now() - this.lastCheck < this.minIntervalMs) return Promise.resolve();
    this.lastCheck = this.now();
    this.checking = this.fetchManifest()
      .then((manifest) => {
        if (sameData(manifest, this.current)) return;
        this.current = manifest;
        this.onNewData(manifest);
      })
      .catch((reason: unknown) => console.warn('Relecture de manifest.json :', reason))
      .finally(() => {
        this.checking = null;
      });
    return this.checking;
  }
}
