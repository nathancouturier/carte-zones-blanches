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

#: Bit 7 du canal B pendant la construction : pixel d'un interstice de frontière comblé, qu'aucune source ne décrit.
#: Il est retiré avant le découpage en tuiles.
MARK = 0x80


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

    def claim_country(self, win: Window, mask: np.ndarray, country_code: int, source_type: int, marked: bool = False) -> int:
        """Attribue au pays les pixels du masque qui ne sont pas déjà pris. Renvoie le nombre de pixels gagnés.

        « marked » signale des pixels qu'aucune source ne décrit (interstices de frontière comblés) :
        leur niveau sera recopié depuis leurs voisins par extrapolate_marked.
        """
        view = self.B[self._slice(win)]
        free = mask & (view == 0)
        view[free] = pack_meta(country_code, source_type) | (MARK if marked else 0)
        return int(free.sum())

    def country_mask(self, win: Window, country_code: int) -> np.ndarray:
        return (self.B[self._slice(win)] & 0x0F) == country_code

    def country_extent(self, country_code: int) -> tuple[float, float, float, float] | None:
        """Emprise (minx, miny, maxx, maxy, en EPSG:3857) des pixels du pays sur la grille, ou None s'il n'en a pas."""
        height, width = self.B.shape
        rows_any = np.zeros(height, dtype=bool)
        cols_any = np.zeros(width, dtype=bool)
        step = 2048
        for r0 in range(0, height, step):
            block = (np.asarray(self.B[r0 : r0 + step]) & 0x0F) == country_code
            if block.any():
                rows_any[r0 : r0 + step] = block.any(axis=1)
                cols_any |= block.any(axis=0)
        if not rows_any.any():
            return None
        rows = np.flatnonzero(rows_any)
        cols = np.flatnonzero(cols_any)
        res = self.canvas.grid.resolution
        minx = self.canvas.origin_x + cols[0] * res
        maxx = self.canvas.origin_x + (cols[-1] + 1) * res
        maxy = self.canvas.origin_y - rows[0] * res
        miny = self.canvas.origin_y - (rows[-1] + 1) * res
        return float(minx), float(miny), float(maxx), float(maxy)

    def release_country(self, country_code: int) -> int:
        """Retire un pays de la grille (ses pixels redeviennent « hors zone »). Renvoie le nombre de pixels libérés.

        Sert quand la seule source d'un pays se révèle inutilisable en cours de construction : mieux vaut
        un pays absent qu'un pays entièrement annoncé sans couverture.
        """
        freed = 0
        step = 2048
        for r0 in range(0, self.B.shape[0], step):
            block = self.B[r0 : r0 + step]
            mine = (np.asarray(block) & 0x0F) == country_code
            if mine.any():
                freed += int(mine.sum())
                block[mine] = 0
                self.R[r0 : r0 + step][mine] = 0
                self.G[r0 : r0 + step][mine] = 0
        return freed

    def described(self, rows: np.ndarray, cols: np.ndarray, country_code: int) -> np.ndarray:
        """Vrai pour les pixels du pays que les sources décrivent (donc pas les interstices comblés)."""
        return (np.asarray(self.B[rows, cols]) & (MARK | 0x0F)) == country_code

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
        view[target] = (view[target] & MARK) | pack_meta(country_code, source_type)

    def extrapolate_marked(self, windows: list[Window], passes: int = 16) -> dict[str, int]:
        """Donne un niveau aux pixels marqués (interstices de frontière) à partir de leurs voisins, puis retire la marque.

        À chaque passe, tous les pixels marqués qui touchent un pixel connu du même pays prennent, pour
        chaque opérateur, le plus PETIT niveau de leurs voisins connus (dans le doute, on annonce le
        moins de couverture), sans jamais baisser un niveau qu'une source aurait écrit. Un pixel
        traité compte comme connu à la passe suivante. « passes » est donc la distance maximale, en
        pixels, à laquelle un niveau se propage ; au-delà, le pixel reste à 0.

        Le calcul porte sur la liste des pixels marqués, pas sur des fenêtres : le résultat ne
        dépend pas de la façon dont les interstices ont été découpés.
        """
        height, width = self.B.shape
        keys: list[np.ndarray] = []
        for col0, row0, w, h in windows:
            rr, cc = np.nonzero((np.asarray(self.B[row0 : row0 + h, col0 : col0 + w]) & MARK) != 0)
            if rr.size:
                keys.append((rr.astype(np.int64) + row0) * width + cc + col0)
        if not keys:
            return {"marques": 0, "extrapoles": 0, "sans_voisin": 0}
        key = np.unique(np.concatenate(keys))  # trié : sert aussi à retrouver un voisin marqué
        rows, cols = key // width, key % width
        country = np.asarray(self.B[rows, cols]) & 0x0F
        values = [np.asarray(self.R[rows, cols]).copy(), np.asarray(self.G[rows, cols]).copy()]
        done = np.zeros(key.size, dtype=bool)
        for _ in range(passes):
            if done.all():
                break
            best = [np.full((key.size, 4), 255, dtype=np.uint8) for _ in values]
            reachable = np.zeros(key.size, dtype=bool)
            for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nr, nc = rows + dr, cols + dc
                inside = (nr >= 0) & (nr < height) & (nc >= 0) & (nc < width)
                nr, nc = np.where(inside, nr, 0), np.where(inside, nc, 0)
                nkey = nr * width + nc
                pos = np.minimum(np.searchsorted(key, nkey), key.size - 1)
                is_marked = key[pos] == nkey
                same = inside & ((np.asarray(self.B[nr, nc]) & 0x0F) == country)
                # Un voisin est connu s'il n'était pas marqué, ou s'il a été traité à une passe précédente.
                usable = same & ~done & (~is_marked | done[pos])
                if not usable.any():
                    continue
                reachable |= usable
                for channel, mine, low in zip((self.R, self.G), values, best):
                    neighbour = np.where(is_marked, mine[pos], np.asarray(channel[nr, nc]))
                    for slot in range(4):
                        level = (neighbour >> (2 * slot)) & 0b11
                        np.minimum(low[:, slot], np.where(usable, level, np.uint8(255)), out=low[:, slot])
            if not reachable.any():
                break
            for mine, low in zip(values, best):
                for slot in range(4):
                    shift = 2 * slot
                    current = (mine >> shift) & 0b11
                    merged = np.where(reachable, np.maximum(current, np.where(low[:, slot] == 255, np.uint8(0), low[:, slot])), current)
                    mine[...] = (mine & np.uint8(~(0b11 << shift) & 0xFF)) | (merged << shift).astype(np.uint8)
            done |= reachable
        self.R[rows, cols] = values[0]
        self.G[rows, cols] = values[1]
        # La marque ne doit pas partir dans les tuiles ; les pixels restés sans voisin connu gardent le niveau 0.
        self.B[rows, cols] = np.asarray(self.B[rows, cols]) & np.uint8(~MARK & 0xFF)
        return {"marques": int(key.size), "extrapoles": int(done.sum()), "sans_voisin": int((~done).sum())}

    def flush(self) -> None:
        for arr in (self.R, self.G, self.B):
            arr.flush()

    def cleanup(self) -> None:
        self.flush()
        for name in ("canal_R.bin", "canal_G.bin", "canal_B.bin"):
            (self.workdir / name).unlink(missing_ok=True)
