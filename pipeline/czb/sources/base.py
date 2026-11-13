"""Interface commune des sources de couverture.

Chaque source remplit les canaux R et G de la grille commune, uniquement dans
les pixels de son pays, avec des niveaux de 0 à 3.
"""

from __future__ import annotations

from typing import Any

from ..context import BuildContext


class Source:
    #: identifiant du module, identique à la clé de config.yaml
    id: str = ""

    def __init__(self, cfg: dict[str, Any]):
        self.cfg = cfg
        self.source_cfg: dict[str, Any] = cfg["sources"][self.id]
        self.country_iso: str = self.source_cfg["country"]
        self.country_cfg: dict[str, Any] = cfg["countries"][self.country_iso]
        self.country_code: int = int(self.country_cfg["code"])

    def remote_state(self) -> dict[str, Any]:
        """État de la source en ligne (version, date, fichiers). Sert à détecter une nouvelle version."""
        raise NotImplementedError

    def process(self, ctx: BuildContext) -> dict[str, Any]:
        """Remplit ctx.layers et renvoie les informations pour le manifest (au moins « date »)."""
        raise NotImplementedError
