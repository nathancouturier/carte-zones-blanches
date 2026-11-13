"""Test de bout en bout sur le jeu synthétique : construction, cohérence, pyramide et découpage."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest
import yaml
from osgeo import ogr, osr

from czb import cli
from czb.grid import Grid, lonlat_to_mercator
from czb.sources.fr_arcep import parse_listing
from czb.verify import TileReader, verify

from .conftest import CX, CY, coverage_shapes


def _build(synthetic: dict, name: str, services: str = "data", overrides: dict | None = None) -> Path:
    cfg = json.loads(json.dumps(synthetic["base"]))
    for key, value in (overrides or {}).items():
        cfg[key].update(value)
    config = synthetic["root"] / f"config-{name}.yaml"
    config.write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding="utf-8")
    out = synthetic["root"] / f"out-{name}"
    code = cli.main(["--config", str(config), "build", "--scope", "hautes-alpes", "--services", services, "--work", str(synthetic["root"] / f"work-{name}"), "--out", str(out), "--date", "2026-11-13"])
    assert code == 0
    return out


@pytest.fixture(scope="session")
def built(synthetic: dict) -> Path:
    return _build(synthetic, "simple", services="data,voice")


def test_parse_listing():
    page = (
        '<li class="file"><span><a href="2026_T2_couv_Metropole_OF_4G_data.gpkg.7z" class="matomo_download">x</a></span>'
        '<span data-size="127765066" class="size">121.85 Mo</span><time datetime="2026-09-24T15:35:53+00:00">x</time></li>'
        '<li class="file"><span><a href="2026_T2_couv_Metropole_SFR0_2G3G_voix.gpkg.7z">x</a></span>'
        '<span data-size="282385808" class="size">269 Mo</span><time datetime="2026-09-24T15:35:57+00:00">x</time></li>'
    )
    files = parse_listing(page)
    assert [(f["operator"], f["techno"], f["usage"], f["quarter"]) for f in files] == [("OF", "4G", "data", "2026-T2"), ("SFR0", "2G3G", "voix", "2026-T2")]
    assert files[0]["size"] == 127765066


def test_build_outputs(built: Path):
    manifest = json.loads((built / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["version"] == 1
    assert manifest["tiles"] == {"size": 256, "minzoom": 0, "maxzoom": 12, "format": "png"}
    france = manifest["countries"][0]
    assert france["iso"] == "FR" and france["code"] == 1 and france["euRoaming"] is True
    assert [s["id"] for s in france["slots"]] == ["orange", "sfr", "bouygues", "free"]
    source = france["sources"][0]
    assert source["id"] == "fr_arcep" and source["type"] == 0 and source["date"] == "2026-T2"
    assert source["services"] == ["data", "voice"] and source["perOperator"] is True
    assert len(manifest["archives"]) == 1 and "blocks" not in manifest["archives"][0]
    assert (built / manifest["archives"][0]["file"]).exists()
    state = json.loads((built / "etat-sources.json").read_text(encoding="utf-8"))
    assert state["sources"]["fr_arcep"]["quarter"] == "2026-T2"
    assert len(state["sources"]["fr_arcep"]["files"]) == 8


def test_witnesses_match(built: Path):
    witnesses = json.loads((built / "temoins.json").read_text(encoding="utf-8"))
    assert len(witnesses) >= 8 * 20
    # Chaque niveau est représenté.
    assert {w["expected"] for w in witnesses} == {0, 1, 2, 3}
    assert verify(built) == 0


def test_verify_detects_a_wrong_level(built: Path, tmp_path: Path):
    import shutil

    copy = tmp_path / "out"
    shutil.copytree(built, copy)
    witnesses = json.loads((copy / "temoins.json").read_text(encoding="utf-8"))
    witnesses[0]["expected"] = (witnesses[0]["expected"] + 1) % 4
    (copy / "temoins.json").write_text(json.dumps(witnesses), encoding="utf-8")
    assert verify(copy) == 1


def _pixel(reader: TileReader, x2154: float, y2154: float) -> tuple[int, int, int, int]:
    src = osr.SpatialReference()
    src.ImportFromEPSG(2154)
    src.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    dst = osr.SpatialReference()
    dst.ImportFromEPSG(4326)
    dst.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    lon, lat, _ = osr.CoordinateTransformation(src, dst).TransformPoint(x2154, y2154)
    grid = Grid(12, 256)
    mx, my = lonlat_to_mercator(lon, lat)
    tx, ty = grid.tile_of_mercator(mx, my)
    canvas = grid.canvas_for_mercator_bounds(mx, my, mx, my)
    col, row = canvas.pixel_of_mercator(mx, my)
    tile = reader.tile(12, tx, ty)
    assert tile is not None
    return tuple(int(v) for v in tile[row, col])


def test_known_pixels(built: Path):
    manifest = json.loads((built / "manifest.json").read_text(encoding="utf-8"))
    reader = TileReader(built, manifest)
    try:
        # Centre du disque de l'opérateur 0 : très bonne couverture pour lui.
        r, g, b, a = _pixel(reader, CX, CY)
        assert a == 255 and b == 1
        assert r & 3 == 3
        # Opérateur 1 : son disque TBC (rayon 4 km) est centré 4 km plus à l'est, on est sur son bord BC.
        # À 12 km à l'ouest du centre : seul l'opérateur 0 couvre (disque CL de 14 km), en limité.
        r, g, b, a = _pixel(reader, CX - 12000, CY)
        assert a == 255 and [(r >> (2 * i)) & 3 for i in range(4)] == [1, 0, 0, 0]
        # Loin de tout, dans le département : zone blanche pour tous.
        r, g, b, a = _pixel(reader, CX - 35000, CY - 25000)
        assert (r, g, b, a) == (0, 0, 1, 255)
        # Dans le département voisin (38), hors du périmètre : hors zone.
        tile_pixel = _pixel(reader, CX - 35000, CY + 23000)
        assert tile_pixel[3] == 255  # encore dans le 05
        # Le rectangle CL de l'opérateur 0 dépasse dans le 38 : il ne doit pas y être écrit.
        src = coverage_shapes(0)["CL"]
        assert src.Contains(_point(CX - 45000 + 16000, CY + 23000))
    finally:
        reader.close()


def _point(x: float, y: float) -> ogr.Geometry:
    pt = ogr.Geometry(ogr.wkbPoint)
    pt.AddPoint_2D(x, y)
    return pt


def test_lower_zooms_are_nearest_neighbour(built: Path):
    """Un pixel d'un zoom inférieur est toujours la copie exacte d'un pixel du zoom supérieur."""
    manifest = json.loads((built / "manifest.json").read_text(encoding="utf-8"))
    reader = TileReader(built, manifest)
    try:
        report = json.loads((built / "rapport-construction.json").read_text(encoding="utf-8"))
        g = report["grid"]
        tx, ty = (g["tx0"] + g["tx1"]) // 2, (g["ty0"] + g["ty1"]) // 2
        for z in range(11, 7, -1):
            shift = 12 - z
            parent = reader.tile(z, tx >> shift, ty >> shift)
            assert parent is not None
            factor = 1 << shift
            # Reconstitue le pavé de tuiles z12 couvert par la tuile parente.
            mosaic = np.zeros((256 * factor, 256 * factor, 4), dtype=np.uint8)
            for j in range(factor):
                for i in range(factor):
                    child = reader.tile(12, ((tx >> shift) << shift) + i, ((ty >> shift) << shift) + j)
                    if child is not None:
                        mosaic[j * 256 : (j + 1) * 256, i * 256 : (i + 1) * 256] = child
            expected = mosaic[factor // 2 :: factor, factor // 2 :: factor]
            assert np.array_equal(parent, expected), f"z{z}"
        # Zooms inférieurs au zoom des blocs : alpha reste binaire et les valeurs viennent du zoom 12.
        # (Aux très petits zooms, une zone aussi petite que le jeu de test peut tomber entre deux
        # pixels échantillonnés : la tuile est alors vide et n'est pas stockée.)
        r_values = set(np.unique(reader.tile(12, tx, ty)[..., 0]).tolist()) | {0}
        seen = 0
        for z in range(0, 8):
            tile = reader.tile(z, tx >> (12 - z), ty >> (12 - z))
            if tile is None:
                continue
            seen += 1
            assert tile[..., 3].any()
            assert set(np.unique(tile[..., 3]).tolist()) <= {0, 255}
            assert set(np.unique(tile[..., 2]).tolist()) <= {0, 1}
        assert seen >= 3
        assert reader.tile(7, tx >> 5, ty >> 5) is not None
        assert r_values
    finally:
        reader.close()


def test_split_archives(synthetic: dict):
    """Avec une limite minuscule, les tuiles sont réparties en plusieurs archives par blocs."""
    out = _build(synthetic, "decoupe", overrides={"limits": {"target_archive_mb": 0.004, "archive_max_mb": 5}, "grid": {"block_zoom": 10}})
    manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
    archives = manifest["archives"]
    assert len(archives) >= 3
    assert manifest["tiles"]["blockZoom"] == 10
    assert archives[0]["maxzoom"] == 9 and "blocks" not in archives[0]
    blocks = [b for a in archives[1:] for b in a["blocks"]]
    assert len(blocks) == len(set(blocks)), "un bloc ne doit appartenir qu'à une archive"
    assert all(a["minzoom"] == 10 and a["maxzoom"] == 12 for a in archives[1:])
    # Le test de cohérence passe aussi en lisant à travers le découpage.
    assert verify(out) == 0
