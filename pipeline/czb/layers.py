"""Les trois canaux de données (R, G, B) sur la grille, stockés sur disque.

Les tableaux sont des fichiers mappés en mémoire : la France entière fait
environ 2 Go par canal, on ne les charge donc jamais en entier.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from .encoding import CHANNEL_OF_SERVICE, pack_meta
from .grid import Canvas

Window = tuple[int, int, int, int]  # col0, row0, largeur, hauteur


class Layers:
    def __init__(self, canvas: Canvas, workdir: Path, create: bool = True):
        self.canvas = canvas
        self.workdir = Path(workdir)
        self.workdir.mkdir(parents=True, exist_ok=True)
        shape = (canvas.height, canvas.width)
        mode = "w+" if create else "r+"
        self.R = np.memmap(self.workdir / "canal_R.bin", dtype=np.uint8, mode=mode, shape=shape)
        self.G = np.memmap(self.workdir / "canal_G.bin", dtype=np.uint8, mode=mode, shape=shape)
        self.B = np.memmap(self.workdir / "canal_B.bin", dtype=np.uint8, mode=mode, shape=shape)

    def channel(self, service: str) -> np.memmap:
        return getattr(self, CHANNEL_OF_SERVICE[service])

    @staticmethod
    def _slice(win: Window) -> tuple[slice, slice]:
        col0, row0, w, h = win
        return slice(row0, row0 + h), slice(col0, col0 + w)

    def claim_country(self, win: Window, mask: np.ndarray, country_code: int, source_type: int) -> int:
        """Attribue au pays les pixels du masque qui ne sont pas déjà pris. Renvoie le nombre de pixels gagnés."""
        view = self.B[self._slice(win)]
        free = mask & (view == 0)
        view[free] = pack_meta(country_code, source_type)
        return int(free.sum())

    def country_mask(self, win: Window, country_code: int) -> np.ndarray:
        return (self.B[self._slice(win)] & 0x0F) == country_code

    def merge_level(self, service: str, slot: int, win: Window, level: np.ndarray, country_code: int) -> None:
        """Écrit un niveau (0 à 3) pour un opérateur, sans jamais baisser un niveau déjà écrit.

        Si deux niveaux se chevauchent, le plus élevé gagne. Seuls les pixels du
        pays de la source sont modifiés.
        """
        if not 0 <= slot <= 3:
            raise ValueError(f"emplacement invalide : {slot}")
        view = self.channel(service)[self._slice(win)]
        inside = self.country_mask(win, country_code)
        shift = 2 * slot
        current = (view >> shift) & 0b11
        wanted = np.where(inside, level, 0).astype(np.uint8)
        merged = np.maximum(current, wanted)
        keep = np.uint8(~(0b11 << shift) & 0xFF)
        view[...] = (view & keep) | (merged << shift).astype(np.uint8)

    def set_source_type(self, win: Window, mask: np.ndarray, country_code: int, source_type: int) -> None:
        """Marque le type de source des pixels d'un pays (officielle, agrégée ou estimée)."""
        view = self.B[self._slice(win)]
        target = mask & ((view & 0x0F) == country_code)
        view[target] = pack_meta(country_code, source_type)

    def flush(self) -> None:
        for arr in (self.R, self.G, self.B):
            arr.flush()

    def cleanup(self) -> None:
        self.flush()
        for name in ("canal_R.bin", "canal_G.bin", "canal_B.bin"):
            (self.workdir / name).unlink(missing_ok=True)
