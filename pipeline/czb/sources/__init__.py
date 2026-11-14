"""Registre des sources : un module par type de source, tous sur la même grille."""

from __future__ import annotations

from typing import Any

from .base import Source
from .ch_bakom import ChBakom
from .es_mtd import EsMtd
from .estimation_opencellid import EstimationOpenCellId
from .fr_arcep import FrArcep
from .it_agcom import ItAgcom

REGISTRY: dict[str, type[Source]] = {
    FrArcep.id: FrArcep,
    ChBakom.id: ChBakom,
    ItAgcom.id: ItAgcom,
    EsMtd.id: EsMtd,
    EstimationOpenCellId.id: EstimationOpenCellId,
}


def create_source(source_id: str, cfg: dict[str, Any]) -> Source:
    """Crée la source « source_id » de config.yaml avec le module qu'elle désigne."""
    module = cfg["sources"][source_id].get("module", source_id)
    if module not in REGISTRY:
        raise ValueError(f"source {source_id} : module inconnu « {module} » (modules disponibles : {sorted(REGISTRY)})")
    return REGISTRY[module](cfg, source_id)
