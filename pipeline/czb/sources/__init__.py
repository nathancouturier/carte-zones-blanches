"""Registre des sources : un module par source, tous sur la même grille."""

from __future__ import annotations

from typing import Any

from .base import Source
from .fr_arcep import FrArcep

REGISTRY: dict[str, type[Source]] = {
    FrArcep.id: FrArcep,
}


def create_source(source_id: str, cfg: dict[str, Any]) -> Source:
    if source_id not in REGISTRY:
        raise ValueError(f"source inconnue : {source_id} (modules disponibles : {sorted(REGISTRY)})")
    return REGISTRY[source_id](cfg)
