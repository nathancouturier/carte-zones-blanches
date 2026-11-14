// Libellé d'un emplacement : le nom de l'opérateur, ou la formule d'un seuil.

import { t } from '../i18n';
import type { ManifestCountry, ManifestSlot } from './manifest';

/** « Orange », « Au moins 2 opérateurs » ou « Les 3 opérateurs à la fois ». */
export function slotLabel(slot: ManifestSlot, country: ManifestCountry): string {
  if (slot.name) return slot.name;
  const count = slot.minOperators ?? 1;
  const total = country.operators?.length ?? 0;
  if (total > 0 && count >= total) return t('network.allNOperators', { count: total });
  return t('network.atLeastOperators', { count });
}

/** Vrai si le pays propose des seuils plutôt que des opérateurs nommés. */
export function hasThresholdSlots(country: ManifestCountry): boolean {
  return country.slots.some((slot) => slot.minOperators !== undefined);
}
