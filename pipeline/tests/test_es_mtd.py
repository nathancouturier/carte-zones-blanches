"""Espagne (ministère) contre un faux service ArcGIS : opérateurs par polygone, grille d'origine, copie de travail."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest
import yaml

from czb import cli
from czb.grid import Canvas, Grid, lonlat_to_mercator
from czb.verify import TileReader, verify

from .fake_arcgis import FakeArcgis, Layer, box_ring

STEP = 0.000346111018645788
MOVISTAR, ORANGE, VODAFONE, XFERA = "A78923125", "A82009812", "A80907397", "A82528548"
# Maille de référence de la zone de test (vers Benasque), comptée depuis l'origine de la grille (-180, 90).
COL0 = round((0.50 + 180) / STEP)
ROW0 = round((90 - 42.70) / STEP)


def lon(col: float) -> float:
    return -180 + (COL0 + col) * STEP


def lat(row: float) -> float:
    return 90 - (ROW0 + row) * STEP


def cells(col: int, row: int, width: int, height: int) -> list[list[float]]:
    """Anneau d'un rectangle de mailles : colonnes col à col + width, lignes row à row + height."""
    return box_ring(lon(col), lat(row + height), lon(col + width), lat(row))


def _features() -> list[dict]:
    def feature(oid: int, coverage: str, rings: list, region: str = "02") -> dict:
        return {"attributes": {"OBJECTID": oid, "COBERTURA": coverage, "CCOM": region, "Municipio": "Benasque"}, "rings": rings}

    return [
        feature(5, f"{MOVISTAR};{ORANGE};{VODAFONE};{XFERA}", [cells(10, 10, 60, 40)]),
        feature(6, f"{VODAFONE};{MOVISTAR}", [cells(70, 10, 40, 40)]),  # ordre inversé, comme dans les données réelles
        feature(9, ORANGE, [cells(110, 10, 30, 40)]),
        feature(12, "", [cells(140, 10, 60, 40)]),  # partie de la commune sans 4G
        feature(15, XFERA, [cells(10, 60, 20, 20), cells(40, 60, 20, 20)]),
        feature(20, MOVISTAR, [cells(70, 60, 1, 1)]),  # une seule maille
        feature(21, f"{ORANGE};{VODAFONE}", [cells(100, 60, 50, 30)], region="09"),  # Catalogne
        feature(30, MOVISTAR, [cells(160, 60, 30, 30)], region=""),  # sans commune (mer, versant français) : ignorée
        feature(31, VODAFONE, [cells(10, 90, 30, 20)], region="13"),  # Madrid : hors du périmètre
    ]


def _config(root: Path, server_url: str, mask: Path) -> Path:
    base = yaml.safe_load((Path(__file__).resolve().parent.parent / "config.yaml").read_text(encoding="utf-8"))
    cfg = {
        "grid": base["grid"],
        "limits": base["limits"],
        "verification": {"candidates_per_file": 400, "points_per_file": 60, "seed": 13},
        "countries": {
            "ES": {
                "code": 4,
                "eu_roaming": True,
                "mask": {"type": "vector_file", "urls": [{"url": mask.as_uri(), "filename": "es-test.geojson"}]},
                "slots": [
                    {"id": "movistar", "name": "Movistar", "cif": MOVISTAR},
                    {"id": "orange", "name": "Orange", "cif": ORANGE},
                    {"id": "vodafone", "name": "Vodafone", "cif": VODAFONE},
                    {"id": "xfera", "name": "Xfera Móviles", "cif": XFERA},
                ],
                "sources": ["es_mtd"],
            }
        },
        "sources": {
            "es_mtd": {
                "country": "ES",
                "type": 0,
                "name": "Mapa de Servicios de Banda Ancha Móvil 2024",
                "attribution": "Origen de los datos: Ministerio para la Transformación Digital y de la Función Pública",
                "licence": "Condiciones generales de reutilización",
                "item_url": f"{server_url}/sharing/rest/content/items/abc",
                "layer_url": f"{server_url}/arcgis/rest/services/InfoCob4G_2024/FeatureServer/0",
                "region_field": "CCOM",
                "regions": ["02", "09"],
                "operator_field": "COBERTURA",
                "operator_separator": ";",
                "oid_field": "OBJECTID",
                "page_size": 2,
                "pause_s": 0,
                "grid_step_deg": STEP,
                "grid_origin": [-180, 90],
                "services": {"data": {"techno": "4G"}},
                "covered_level": 2,
                "levels_kind": "binary",
                "data_date": "2024-06-30",
            }
        },
        "scopes": {"espagne": {"countries": ["ES"]}},
    }
    config = root / "config.yaml"
    config.write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding="utf-8")
    return config


@pytest.fixture(scope="module")
def spain(tmp_path_factory: pytest.TempPathFactory):
    patch = pytest.MonkeyPatch()
    patch.setenv("no_proxy", "127.0.0.1,localhost")
    patch.setenv("NO_PROXY", "127.0.0.1,localhost")
    root = tmp_path_factory.mktemp("espagne")
    info = {
        "name": "InfoCob4G_2025_Muni",
        "fields": [{"name": n} for n in ("OBJECTID", "COBERTURA", "CCOM", "Municipio")],
        "extent": {"xmin": -18.2, "ymin": 27.5, "xmax": 4.5, "ymax": 43.8, "spatialReference": {"wkid": 4258, "latestWkid": 4258}},
        "editingInfo": {"dataLastEditDate": 1778025600000},
    }
    layer = Layer("OBJECTID", 4258, _features(), max_records=2000, info=info)
    server = FakeArcgis(
        {
            "/arcgis/rest/services/InfoCob4G_2024/FeatureServer/0": layer,
            "/sharing/rest/content/items/abc": {"id": "abc", "modified": 1778716800000},
        }
    )
    # Masque : un rectangle qui déborde un peu des données, sauf à l'est où il coupe l'entité 9.
    mask = root / "es-test.geojson"
    ring = [[lon(0), lat(120)], [lon(125), lat(120)], [lon(125), lat(0)], [lon(0), lat(0)], [lon(0), lat(120)]]
    mask.write_text(json.dumps({"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {"nameunit": "Test"}, "geometry": {"type": "MultiPolygon", "coordinates": [[ring]]}}]}), encoding="utf-8")
    config = _config(root, server.url, mask)
    out = root / "out"
    try:
        code = cli.main(["--config", str(config), "build", "--scope", "espagne", "--services", "data", "--work", str(root / "work"), "--out", str(out), "--date", "2026-11-14"])
        assert code == 0
        yield {"out": out, "root": root, "layer": layer, "config": config, "info": info}
    finally:
        server.close()
        patch.undo()


def _pixel_reader(out: Path):
    manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
    report = json.loads((out / "rapport-construction.json").read_text(encoding="utf-8"))
    g = report["grid"]
    canvas = Canvas(Grid(12, 256), g["tx0"], g["ty0"], g["tx1"], g["ty1"])
    reader = TileReader(out, manifest)

    def pixel(col: float, row: float) -> tuple[int, int, int, int]:
        x, y = lonlat_to_mercator(lon(col), lat(row))
        c, r = canvas.pixel_of_mercator(x, y)
        tx, ty, px, py = canvas.tile_and_pixel(c, r)
        tile = reader.tile(12, tx, ty)
        return (0, 0, 0, 0) if tile is None else tuple(int(v) for v in tile[py, px])

    return reader, pixel, report


def test_spain_manifest(spain: dict):
    manifest = json.loads((spain["out"] / "manifest.json").read_text(encoding="utf-8"))
    country = manifest["countries"][0]
    assert country["iso"] == "ES" and country["code"] == 4
    assert [s["name"] for s in country["slots"]] == ["Movistar", "Orange", "Vodafone", "Xfera Móviles"]
    source = country["sources"][0]
    assert source["type"] == 0 and source["levels"] == "binary" and source["perOperator"] is True
    assert source["date"] == "2024-06" and source["dataDate"] == "2024-06-30"
    state = json.loads((spain["out"] / "etat-sources.json").read_text(encoding="utf-8"))
    assert state["sources"]["es_mtd"] == {"couche": "InfoCob4G_2025_Muni", "dataLastEditDate": 1778025600000, "modified": 1778716800000, "regions": {"02": 5, "09": 1}}


def test_spain_pixels(spain: dict):
    reader, pixel, report = _pixel_reader(spain["out"])
    meta = 4  # pays 4, source officielle par opérateur
    try:
        assert pixel(40, 30) == (0b10101010, 0, meta, 255)  # les quatre opérateurs
        assert pixel(90, 30) == (0b00100010, 0, meta, 255)  # Movistar et Vodafone
        assert pixel(118, 30) == (0b00001000, 0, meta, 255)  # Orange seul
        assert pixel(130, 30)[3] == 0  # même entité, au-delà de la frontière
        assert pixel(20, 70) == (0b10000000, 0, meta, 255) and pixel(50, 70) == (0b10000000, 0, meta, 255)  # Xfera, deux anneaux
        assert pixel(35, 70) == (0, 0, meta, 255)
        assert pixel(70.5, 60.5) == (0b00000010, 0, meta, 255)  # une seule maille
        assert pixel(72.5, 60.5) == (0, 0, meta, 255)
        assert pixel(110, 75) == (0b00101000, 0, meta, 255)  # Catalogne : Orange et Vodafone
        assert pixel(20, 100) == (0, 0, meta, 255)  # région hors périmètre : ignorée
        assert pixel(5, 5) == (0, 0, meta, 255)
    finally:
        reader.close()
    assert report["stats"]["copie_de_travail"]["es_mtd"] == "reconstruite"
    assert verify(spain["out"]) == 0
    witnesses = json.loads((spain["out"] / "temoins.json").read_text(encoding="utf-8"))
    assert {w["operator"] for w in witnesses} == {"movistar", "orange", "vodafone", "xfera"}
    assert {w["expected"] for w in witnesses} == {0, 2}


def test_spain_working_copy_is_reused_until_the_edition_changes(spain: dict):
    root = spain["root"]
    cache = spain["out"] / "cache-es_mtd.tif"
    assert cache.exists()
    work = root / "work2"
    (work / "cache").mkdir(parents=True)
    shutil.copy(cache, work / "cache" / cache.name)
    out2 = root / "out2"
    before = spain["layer"].requests
    code = cli.main(["--config", str(spain["config"]), "build", "--scope", "espagne", "--services", "data", "--work", str(work), "--out", str(out2), "--date", "2026-11-15"])
    assert code == 0
    report = json.loads((out2 / "rapport-construction.json").read_text(encoding="utf-8"))
    assert report["stats"]["copie_de_travail"]["es_mtd"] == "reprise"
    # Seuls les comptages d'entités ont interrogé la couche : aucune page de polygones.
    assert spain["layer"].requests - before == 4
    assert (out2 / "cache-es_mtd.tif").exists()
    reader, pixel, _ = _pixel_reader(out2)
    try:
        assert pixel(40, 30) == (0b10101010, 0, 4, 255) and pixel(110, 75) == (0b00101000, 0, 4, 255)
    finally:
        reader.close()
    assert verify(out2) == 0

    # Nouvelle édition en ligne : la copie de travail ne sert plus, tout est relu.
    spain["info"]["editingInfo"]["dataLastEditDate"] += 86_400_000
    out3 = root / "out3"
    before = spain["layer"].requests
    code = cli.main(["--config", str(spain["config"]), "build", "--scope", "espagne", "--services", "data", "--work", str(work), "--out", str(out3), "--date", "2026-11-16"])
    assert code == 0
    report = json.loads((out3 / "rapport-construction.json").read_text(encoding="utf-8"))
    assert report["stats"]["copie_de_travail"]["es_mtd"] == "reconstruite"
    assert spain["layer"].requests - before > 6


def test_spain_unknown_operator_stops_the_build(spain: dict):
    from czb.context import load_config
    from czb.sources import create_source

    source = create_source("es_mtd", load_config(spain["config"]))
    assert source.bits_of(f"{VODAFONE};{MOVISTAR}") == 0b0101
    assert source.bits_of("") == 0
    with pytest.raises(RuntimeError, match="inconnu"):
        source.bits_of(f"{MOVISTAR};B12345678")
