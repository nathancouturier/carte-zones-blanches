// Libellé d'un emplacement : le nom de l'opérateur, ou la formule d'un seuil.

import { t } from '../i18n';
import type { ManifestCountry, ManifestSlot } from './manifest';

/**
 * Nombre de réseaux que la source d'un pays à seuils sait compter : le nombre
 * d'opérateurs nommés, ou à défaut le seuil le plus élevé. 0 si le pays n'a pas de seuils.
 */
export function networkCount(country: ManifestCountry): number {
  const highest = Math.max(0, ...country.slots.map((slot) => slot.minOperators ?? 0));
  return country.operators?.length ?? highest;
}

/** « Orange », « Au moins 2 réseaux » ou « Les 3 réseaux à la fois ». */
export function slotLabel(slot: ManifestSlot, country: ManifestCountry): string {
  if (slot.name) return slot.name;
  const count = slot.minOperators ?? 1;
  const total = networkCount(country);
  if (total > 1 && count >= total) return t('network.allNOperators', { count: total });
  return t('network.atLeastOperators', { count });
}

/** Vrai si le pays propose des seuils plutôt que des opérateurs nommés. */
export function hasThresholdSlots(country: ManifestCountry): boolean {
  return country.slots.some((slot) => slot.minOperators !== undefined);
}
