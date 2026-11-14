"""Suisse (OFCOM) sur un jeu synthétique : GeoTIFF de 100 m en EPSG:2056, valeurs 0, 2 et 3, NaN hors du pays."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest
import yaml
from osgeo import gdal, ogr, osr

from czb import cli
from czb.sources.ch_bakom import NO_DATA, _fill_edges
from czb.verify import TileReader, verify

# Coin nord-ouest du raster de test, en LV95 (vers Berne).
X0, Y0 = 2_590_000.0, 1_210_000.0
COLS, ROWS = 220, 160


def _srs(epsg: int) -> osr.SpatialReference:
    srs = osr.SpatialReference()
    srs.ImportFromEPSG(epsg)
    srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return srs


def _values() -> np.ndarray:
    """0 = pas de couverture, 2 = moins de 3 opérateurs, 3 = les 3 opérateurs, NaN = hors du pays."""
    values = np.full((ROWS, COLS), np.nan, dtype=np.float32)
    values[10:150, 10:210] = 3
    values[40:90, 30:120] = 2
    values[55:75, 50:90] = 0
    values[100:140, 150:200] = 0
    return values


@pytest.fixture(scope="module")
def swiss(tmp_path_factory: pytest.TempPathFactory) -> dict:
    root = tmp_path_factory.mktemp("suisse")
    remote = root / "distant"
    remote.mkdir()
    tif = remote / "mobilnetz-4g_2056.tif"
    ds = gdal.GetDriverByName("GTiff").Create(str(tif), COLS, ROWS, 1, gdal.GDT_Float32, options=["COMPRESS=LZW"])
    ds.SetGeoTransform((X0, 100.0, 0.0, Y0, 0.0, -100.0))
    ds.SetProjection(_srs(2056).ExportToWkt())
    band = ds.GetRasterBand(1)
    band.SetNoDataValue(float("nan"))
    band.WriteArray(_values())
    ds = None
    (remote / "items.json").write_text(
        json.dumps(
            {
                "features": [
                    {
                        "id": "mobilnetz-4g",
                        "properties": {"datetime": "2026-04-30T00:00:00Z"},
                        "assets": {
                            "mobilnetz-4g_2056.tif": {"href": tif.as_uri(), "updated": "2026-10-26T15:00:38Z", "proj:epsg": 2056},
                            "mobilnetz-4g.zip": {"href": (remote / "x.zip").as_uri(), "updated": "2025-12-03T15:48:54Z"},
                        },
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    # Masque du pays : un peu plus large que les données (150 m de chaque côté), pour exercer le comblement des bords.
    ring = ogr.Geometry(ogr.wkbLinearRing)
    x_min, x_max = X0 + 10 * 100 - 150, X0 + 210 * 100 + 150
    y_max, y_min = Y0 - 10 * 100 + 150, Y0 - 150 * 100 - 150
    for x, y in ((x_min, y_min), (x_max, y_min), (x_max, y_max), (x_min, y_max), (x_min, y_min)):
        ring.AddPoint_2D(x, y)
    poly = ogr.Geometry(ogr.wkbPolygon)
    poly.AddGeometry(ring)
    poly.Segmentize(500)
    mask = remote / "pays.gpkg"
    vds = ogr.GetDriverByName("GPKG").CreateDataSource(str(mask))
    layer = vds.CreateLayer("pays", _srs(2056), ogr.wkbPolygon)
    layer.CreateField(ogr.FieldDefn("NAME", ogr.OFTString))
    feat = ogr.Feature(layer.GetLayerDefn())
    feat.SetField("NAME", "Schweiz")
    feat.SetGeometry(poly)
    layer.CreateFeature(feat)
    other = ogr.Feature(layer.GetLayerDefn())
    other.SetField("NAME", "Liechtenstein")
    far = ogr.Geometry(ogr.wkbPolygon)
    far_ring = ogr.Geometry(ogr.wkbLinearRing)
    for x, y in ((2_750_000, 1_220_000), (2_760_000, 1_220_000), (2_760_000, 1_230_000), (2_750_000, 1_230_000), (2_750_000, 1_220_000)):
        far_ring.AddPoint_2D(x, y)
    far.AddGeometry(far_ring)
    other.SetGeometry(far)
    layer.CreateFeature(other)
    vds = None

    base = yaml.safe_load((Path(__file__).resolve().parent.parent / "config.yaml").read_text(encoding="utf-8"))
    cfg = {
        "grid": base["grid"],
        "limits": base["limits"],
        "verification": {"candidates_per_file": 400, "points_per_file": 60, "seed": 3},
        "countries": {
            "CH": {
                "code": 2,
                "eu_roaming": False,
                "operators": ["Swisscom", "Sunrise", "Salt"],
                "mask": {"type": "vector_file", "url": mask.as_uri(), "layer": "pays", "where": "NAME = 'Schweiz'"},
                "slots": [{"id": "un", "min_operators": 1}, {"id": "tous", "min_operators": 3}],
                "sources": ["ch_bakom"],
            }
        },
        "sources": {
            "ch_bakom": {
                "country": "CH",
                "type": 1,
                "name": "OFCOM, atlas de la large bande",
                "attribution": "OFCOM",
                "licence": "Utilisation libre",
                "stac_url": (remote / "items.json").as_uri(),
                "services": {"data": {"techno": "4G", "collection": "ch.bakom.mobilnetz-4g"}},
                "values": {0: 0, 2: 1, 3: 3},
                "covered_level": 2,
                "levels_kind": "binary",
                "per_operator": True,
                "resolution_m": 100,
            }
        },
        "scopes": {"suisse": {"countries": ["CH"]}},
    }
    config = root / "config.yaml"
    config.write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding="utf-8")
    out = root / "out"
    code = cli.main(["--config", str(config), "build", "--scope", "suisse", "--services", "data", "--work", str(root / "work"), "--out", str(out), "--date", "2026-11-14"])
    assert code == 0
    return {"out": out, "root": root}


def test_fill_edges_is_pessimistic():
    grid = np.full((5, 5), NO_DATA, dtype=np.uint8)
    grid[2, 2] = 3
    grid[2, 3] = 1
    filled = _fill_edges(grid, 1)
    assert filled[2, 2] == 3 and filled[2, 3] == 1
    assert filled[1, 1] == 3  # un seul voisin renseigné
    assert filled[1, 2] == 1  # deux voisins : on garde le plus petit
    assert filled[0, 0] == NO_DATA  # trop loin pour une seule passe
    assert _fill_edges(grid, 2)[0, 0] == 3


def test_manifest_describes_an_aggregated_source(swiss: dict):
    manifest = json.loads((swiss["out"] / "manifest.json").read_text(encoding="utf-8"))
    country = manifest["countries"][0]
    assert country["iso"] == "CH" and country["code"] == 2 and country["euRoaming"] is False
    assert country["operators"] == ["Swisscom", "Sunrise", "Salt"]
    assert country["slots"] == [{"id": "un", "minOperators": 1}, {"id": "tous", "minOperators": 3}]
    source = country["sources"][0]
    assert source["type"] == 1 and source["levels"] == "binary" and source["perOperator"] is True
    assert source["date"] == "2026-04" and source["dataDate"] == "2026-04-30"
    state = json.loads((swiss["out"] / "etat-sources.json").read_text(encoding="utf-8"))
    assert state["sources"]["ch_bakom"]["ch.bakom.mobilnetz-4g"]["datetime"] == "2026-04-30T00:00:00Z"


def test_swiss_witnesses_match(swiss: dict):
    witnesses = json.loads((swiss["out"] / "temoins.json").read_text(encoding="utf-8"))
    assert len(witnesses) >= 80
    assert {w["operator"] for w in witnesses} == {"un", "tous"}
    assert {w["expected"] for w in witnesses} == {0, 2}
    assert verify(swiss["out"]) == 0


def test_swiss_known_cells(swiss: dict):
    """Lecture directe de quelques carrés : seuils « au moins un » et « les trois », type de source agrégée."""
    manifest = json.loads((swiss["out"] / "manifest.json").read_text(encoding="utf-8"))
    report = json.loads((swiss["out"] / "rapport-construction.json").read_text(encoding="utf-8"))
    from czb.grid import Canvas, Grid

    g = report["grid"]
    canvas = Canvas(Grid(12, 256), g["tx0"], g["ty0"], g["tx1"], g["ty1"])
    to_merc = osr.CoordinateTransformation(_srs(2056), _srs(3857))
    reader = TileReader(swiss["out"], manifest)

    def pixel(col_cell: float, row_cell: float) -> tuple[int, int, int, int]:
        x, y, _ = to_merc.TransformPoint(X0 + col_cell * 100, Y0 - row_cell * 100)
        col, row = canvas.pixel_of_mercator(x, y)
        tx, ty, px, py = canvas.tile_and_pixel(col, row)
        tile = reader.tile(12, tx, ty)
        assert tile is not None
        return tuple(int(v) for v in tile[py, px])

    try:
        # Les 3 opérateurs : les deux seuils sont atteints. B = pays 2, type de source 1 (officielle agrégée).
        assert pixel(180.5, 30.5) == (0b1010, 0, (1 << 4) | 2, 255)
        # Moins de 3 opérateurs : seul le seuil « au moins un » est atteint.
        assert pixel(100.5, 50.5) == (0b0010, 0, (1 << 4) | 2, 255)
        # Pas de couverture.
        assert pixel(70.5, 65.5) == (0, 0, (1 << 4) | 2, 255)
        # Bord du pays, 100 m au-delà des données : comblé avec la valeur voisine (les 3 opérateurs).
        assert pixel(9.5, 80.5) == (0b1010, 0, (1 << 4) | 2, 255)
        # Hors du pays.
        assert pixel(5.5, 80.5)[3] == 0
    finally:
        reader.close()
    assert report["stats"]["pixels_sans_donnee"]["ch_bakom:data"] == 0
