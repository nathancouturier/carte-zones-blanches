"""Tests de non-régression issus de la relecture critique du coeur du pipeline.

Chacun échoue quand on réintroduit le défaut qu'il garde : points témoins tirés sur toute la grille au lieu de
la fenêtre du pays (un petit pays n'en recevait aucun), comblement des interstices dépendant du découpage en
fenêtres, PNG en palette avec ou sans transparence.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from czb.context import BuildContext
from czb.encoding import decode_png, encode_png
from czb.grid import Canvas, Grid
from czb.layers import Layers
from czb.witness import VectorWitnesses


def test_witness_candidates_are_drawn_inside_the_country_window(tmp_path: Path):
    """Un petit pays dans une grande grille reçoit tous ses candidats : le tirage se fait dans sa fenêtre."""
    grid = Grid(12, 256)
    canvas = Canvas(grid, 2000, 1400, 2019, 1419)  # 20 x 20 tuiles : 26 millions de pixels
    layers = Layers(canvas, tmp_path)
    # Un pays de la taille de Monaco : 2 700 pixels.
    assert layers.claim_country((2500, 3000, 60, 45), np.ones((45, 60), dtype=bool), 6, 2) == 2700
    cfg = {"verification": {"candidates_per_file": 240, "points_per_file": 60, "seed": 1}, "countries": {}, "scopes": {"x": {"countries": []}}}
    ctx = BuildContext(cfg=cfg, scope_name="x", services=["data"], workdir=tmp_path, outdir=tmp_path, grid=grid, canvas=canvas, layers=layers)
    candidates = VectorWitnesses(ctx, 6, None, np.random.default_rng(1)).candidates
    assert len(candidates) == 240
    assert all(2500 <= c["col"] < 2560 and 3000 <= c["row"] < 3045 for c in candidates)
    layers.cleanup()


def test_extrapolate_marked_does_not_depend_on_the_windows(tmp_path: Path):
    """Un même interstice donné en une fenêtre, en deux fenêtres voisines ou dans l'ordre inverse : mêmes niveaux, mêmes compteurs."""
    canvas = Canvas(Grid(12, 256), 2100, 1400, 2100, 1400)
    results = []
    for index, windows in enumerate(([(30, 20, 20, 100)], [(30, 20, 20, 50), (30, 70, 20, 50)], [(30, 70, 20, 50), (30, 20, 20, 50)])):
        layers = Layers(canvas, tmp_path / str(index))
        country = np.zeros((256, 256), dtype=bool)
        country[20:120, 50:80] = True
        layers.claim_country((0, 0, 256, 256), country, 3, 1)
        gap = np.zeros((256, 256), dtype=bool)
        gap[20:120, 30:50] = True
        assert layers.claim_country((0, 0, 256, 256), gap, 3, 1, marked=True) == 2000
        level = np.full((100, 30), 3, dtype=np.uint8)
        level[48:52, :] = 0  # une zone blanche à cheval sur la jonction des deux fenêtres
        layers.merge_level("data", 0, (50, 20, 30, 100), level, 3)
        stats = layers.extrapolate_marked(windows)
        results.append((stats, np.array(layers.R[20:120, 30:50])))
        layers.cleanup()
    assert results[0][0] == results[1][0] == results[2][0] == {"marques": 2000, "extrapoles": 1600, "sans_voisin": 400}
    assert np.array_equal(results[0][1], results[1][1]) and np.array_equal(results[1][1], results[2][1])


def test_png_palette_branches_are_lossless():
    """Tuiles de peu de couleurs, avec des pixels hors zone : PNG en palette (type de couleur 3), relu à l'identique."""
    rng = np.random.default_rng(1)
    for colours in (2, 4, 16, 28, 200):
        index = rng.integers(0, colours, size=(256, 256))
        tile = np.zeros((256, 256, 4), dtype=np.uint8)
        tile[..., 0] = index  # canal R : une valeur par couleur
        tile[..., 2] = 1
        tile[..., 3] = 255
        tile[index == 0] = 0  # la couleur 0 est « hors zone » : pixel nul, transparent
        data = encode_png(tile)
        assert data[25] == 3, f"{colours} couleurs : la tuile doit être écrite en palette"
        assert np.array_equal(decode_png(data), tile), f"{colours} couleurs"
    # Au-delà de 256 couleurs : RGBA (type de couleur 6).
    many = rng.integers(0, 256, size=(256, 256, 4), dtype=np.uint8)
    many[..., 3] = 255
    assert encode_png(many)[25] == 6
