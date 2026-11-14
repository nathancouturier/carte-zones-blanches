"""Configuration et contexte d'une construction."""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from typing import TYPE_CHECKING

import yaml

from .grid import Canvas, Grid

if TYPE_CHECKING:
    from .layers import Layers

CONFIG_PATH = Path(__file__).resolve().parent.parent / "config.yaml"


def load_config(path: Path | None = None) -> dict[str, Any]:
    with open(path or CONFIG_PATH, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    for key in ("grid", "limits", "countries", "sources", "scopes"):
        if key not in cfg:
            raise ValueError(f"config.yaml : section « {key} » manquante")
    codes = [c["code"] for c in cfg["countries"].values()]
    if len(set(codes)) != len(codes) or any(not 1 <= c <= 15 for c in codes):
        raise ValueError("config.yaml : les codes pays doivent être uniques et compris entre 1 et 15")
    for iso, country in cfg["countries"].items():
        if len(country.get("slots", [])) > 4:
            raise ValueError(f"config.yaml : {iso} déclare plus de 4 opérateurs")
        for name in country.get("sources", []):
            if name not in cfg["sources"]:
                raise ValueError(f"config.yaml : source inconnue « {name} » pour {iso}")
    return cfg


def grid_from_config(cfg: dict[str, Any]) -> Grid:
    return Grid(zoom=int(cfg["grid"]["max_zoom"]), tile_size=int(cfg["grid"]["tile_size"]))


@dataclass
class BuildContext:
    cfg: dict[str, Any]
    scope_name: str
    services: list[str]
    workdir: Path
    outdir: Path
    grid: Grid
    canvas: Canvas | None = None
    layers: "Layers | None" = None
    witnesses: list[dict[str, Any]] = field(default_factory=list)
    #: points témoins des contours : pays attendu d'un pixel, d'après les polygones eux-mêmes
    mask_witnesses: list[dict[str, Any]] = field(default_factory=list)
    source_info: dict[str, dict[str, Any]] = field(default_factory=dict)
    timings: dict[str, float] = field(default_factory=dict)
    stats: dict[str, Any] = field(default_factory=dict)
    #: sources qui ne peuvent pas être traitées dans cet environnement, avec la raison (clé d'accès absente)
    unavailable: dict[str, str] = field(default_factory=dict)
    #: fenêtres de la grille qui contiennent des pixels d'interstices de frontière comblés
    gap_windows: list[tuple[int, int, int, int]] = field(default_factory=list)
    #: fenêtre englobante de chaque pays sur la grille (col0, row0, largeur, hauteur), calculée à la demande
    country_windows: dict[int, tuple[int, int, int, int] | None] = field(default_factory=dict)

    @property
    def scope(self) -> dict[str, Any]:
        return self.cfg["scopes"][self.scope_name]

    def country_sources(self, iso: str) -> list[str]:
        """Sources du pays qui peuvent être traitées, dans l'ordre de config.yaml."""
        return [s for s in self.cfg["countries"][iso]["sources"] if s not in self.unavailable]

    @property
    def countries(self) -> list[str]:
        """Pays du périmètre qui ont au moins une source disponible, dans l'ordre de priorité de config.yaml."""
        wanted = set(self.scope["countries"])
        return [iso for iso in self.cfg["countries"] if iso in wanted and self.country_sources(iso)]


class Timer:
    """Mesure et affiche la durée d'une étape."""

    def __init__(self, ctx: BuildContext, name: str):
        self.ctx, self.name = ctx, name

    def __enter__(self) -> "Timer":
        self.t0 = time.time()
        print(f"== {self.name}", flush=True)
        return self

    def __exit__(self, *exc: object) -> None:
        dt = time.time() - self.t0
        self.ctx.timings[self.name] = round(self.ctx.timings.get(self.name, 0.0) + dt, 1)
        print(f"   {self.name} : {dt:.1f} s", flush=True)
