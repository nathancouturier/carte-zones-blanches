// Annulation et délai des lectures de tuiles.

/** Erreur d'une requête annulée, du même nom que celle du navigateur. */
export function abortError(): Error {
  const error = new Error('Requête annulée');
  error.name = 'AbortError';
  return error;
}

/** Vrai pour une requête annulée par celui qui l'a lancée (ce n'est pas une panne). */
export function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === 'AbortError';
}

/**
 * Attend « promise », mais rend la main dès que « signal » est déclenché, en
 * rejetant avec sa raison (annulation, ou TimeoutError pour un délai dépassé).
 * Utile quand celui qui exécute la promesse n'écoute pas le signal, ou mal.
 */
export function untilAborted<T>(promise: Promise<T>, signal?: AbortSignal): Promise<T> {
  if (!signal) return promise;
  if (signal.aborted) return Promise.reject(signal.reason ?? abortError());
  return new Promise<T>((resolve, reject) => {
    const onAbort = (): void => reject(signal.reason ?? abortError());
    signal.addEventListener('abort', onAbort, { once: true });
    promise.then(resolve, reject).finally(() => signal.removeEventListener('abort', onAbort));
  });
}
