"""Interface commune des sources de couverture.

Chaque source remplit les canaux R et G de la grille commune, uniquement dans
les pixels de son pays, avec des niveaux de 0 à 3.
"""

from __future__ import annotations

from typing import Any

from ..context import BuildContext


class SourceUnavailable(RuntimeError):
    """La source ne peut pas être traitée cette fois-ci (clé d'accès refusée, quota atteint, pays sans donnée).

    La construction continue sans elle : le pays est laissé de côté s'il n'a pas d'autre source.
    """


class Source:
    #: identifiant du module. Une source de config.yaml désigne son module par la clé « module »,
    #: ou à défaut par son propre nom : un même module peut ainsi servir plusieurs pays.
    id: str = ""

    def __init__(self, cfg: dict[str, Any], source_id: str | None = None):
        self.cfg = cfg
        #: nom de la source dans config.yaml (clé de « sources »)
        self.source_id: str = source_id or self.id
        self.source_cfg: dict[str, Any] = cfg["sources"][self.source_id]
        self.country_iso: str = self.source_cfg["country"]
        self.country_cfg: dict[str, Any] = cfg["countries"][self.country_iso]
        self.country_code: int = int(self.country_cfg["code"])

    def available(self) -> tuple[bool, str]:
        """Dit si la source peut être traitée dans cet environnement, sinon pourquoi (clé d'accès absente, par exemple)."""
        return True, ""

    def prepare(self, ctx: BuildContext) -> None:
        """Avant de dessiner les pays : récupère ce qui peut manquer. Lève SourceUnavailable si la source est inutilisable."""

    def remote_state(self, services: list[str] | None = None) -> dict[str, Any]:
        """État de la source en ligne (version, date, fichiers). Sert à détecter une nouvelle version."""
        raise NotImplementedError

    def process(self, ctx: BuildContext) -> dict[str, Any]:
        """Remplit ctx.layers et renvoie les informations pour le manifest (au moins « date »)."""
        raise NotImplementedError
