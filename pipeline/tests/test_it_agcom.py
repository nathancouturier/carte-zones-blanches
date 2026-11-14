"""Italie (AGCOM) contre un faux service ArcGIS : pagination par identifiant, seuils, polygones invalides."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml
from osgeo import ogr, osr

from czb import cli
from czb.grid import Canvas, Grid, lonlat_to_mercator
from czb.raster import polygonal
from czb.verify import TileReader, verify

from .fake_arcgis import FakeArcgis, Layer, box_ring

# Coin sud-ouest de la zone de test, en EPSG:3857 (vers Aoste).
X0, Y0 = lonlat_to_mercator(7.30, 45.70)
KM = 1000.0


def _features() -> list[dict]:
    """Huit entités réparties sur trois pages de 3. Valeurs 1 à 4, une autre région, un polygone « en papillon »."""
    def feature(fid: int, n: int, rings: list, region: float = 2.0) -> dict:
        return {"attributes": {"fid": fid, "n_infrastrutture_totali": n, "COD_REG": region, "PRO_COM_T": "007003"}, "rings": rings}

    bowtie = [box_ring(X0 + 20 * KM, Y0 + 2 * KM, X0 + 22 * KM, Y0 + 4 * KM)[:-1] + box_ring(X0 + 22 * KM, Y0 + 4 * KM, X0 + 24 * KM, Y0 + 6 * KM)]
    # Un seul anneau qui passe deux fois par le coin commun : invalide pour GEOS, courant dans les données réelles.
    bowtie = [[[X0 + 20 * KM, Y0 + 2 * KM], [X0 + 20 * KM, Y0 + 4 * KM], [X0 + 22 * KM, Y0 + 4 * KM], [X0 + 22 * KM, Y0 + 6 * KM], [X0 + 24 * KM, Y0 + 6 * KM], [X0 + 24 * KM, Y0 + 4 * KM], [X0 + 22 * KM, Y0 + 4 * KM], [X0 + 22 * KM, Y0 + 2 * KM], [X0 + 20 * KM, Y0 + 2 * KM]]]
    return [
        feature(11, 1, [box_ring(X0 + 2 * KM, Y0 + 2 * KM, X0 + 8 * KM, Y0 + 8 * KM)]),
        feature(12, 2, [box_ring(X0 + 8 * KM, Y0 + 2 * KM, X0 + 12 * KM, Y0 + 8 * KM)]),
        feature(25, 3, [box_ring(X0 + 12 * KM, Y0 + 2 * KM, X0 + 16 * KM, Y0 + 8 * KM)]),
        feature(31, 4, [box_ring(X0 + 16 * KM, Y0 + 2 * KM, X0 + 19 * KM, Y0 + 8 * KM)]),
        feature(40, 2, bowtie),
        feature(41, 4, [box_ring(X0 + 2 * KM, Y0 + 10 * KM, X0 + 6 * KM, Y0 + 14 * KM)], region=3.0),  # Lombardie : hors du filtre
        feature(57, 3, [box_ring(X0 + 8 * KM, Y0 + 10 * KM, X0 + 12 * KM, Y0 + 14 * KM), box_ring(X0 + 14 * KM, Y0 + 10 * KM, X0 + 18 * KM, Y0 + 14 * KM)]),
        feature(58, 1, [box_ring(X0 + 27 * KM, Y0 + 2 * KM, X0 + 40 * KM, Y0 + 8 * KM)]),  # déborde du pays
        feature(60, 1, [box_ring(X0 + 20 * KM, Y0 + 10 * KM, X0 + 24 * KM, Y0 + 14 * KM)]),
    ]


@pytest.fixture(scope="module")
def italy(tmp_path_factory: pytest.TempPathFactory):
    patch = pytest.MonkeyPatch()
    patch.setenv("no_proxy", "127.0.0.1,localhost")
    patch.setenv("NO_PROXY", "127.0.0.1,localhost")
    root = tmp_path_factory.mktemp("italie")
    layer = Layer("fid", 3857, _features(), max_records=1000)
    server = FakeArcgis(
        {
            "/rest/services/Grid100/mobile_4G/MapServer": {"serviceDescription": "mobile_4G_20260127", "layers": [{"id": 0, "name": "mobile_4G_260127_260205"}]},
            "/rest/services/Grid100/mobile_4G/MapServer/0": layer,
            "/rest/services/Grid100/data_pubblicazione/FeatureServer/0/query": {"features": [{"attributes": {"fid": 1, "commento": "Dati del 27 gennaio 2026 - Pubblicazione del 2 feb 2026"}}]},
        }
    )
    # Masque du pays : un rectangle de 30 km sur 16 km, en EPSG:32632 comme les limites de l'ISTAT, rangé dans un zip.
    srs = osr.SpatialReference()
    srs.ImportFromEPSG(32632)
    srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    merc = osr.SpatialReference()
    merc.ImportFromEPSG(3857)
    merc.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    ring = ogr.Geometry(ogr.wkbLinearRing)
    for x, y in ((X0, Y0), (X0 + 30 * KM, Y0), (X0 + 30 * KM, Y0 + 16 * KM), (X0, Y0 + 16 * KM), (X0, Y0)):
        ring.AddPoint_2D(x, y)
    poly = ogr.Geometry(ogr.wkbPolygon)
    poly.AddGeometry(ring)
    poly.Segmentize(500)
    poly.Transform(osr.CoordinateTransformation(merc, srs))
    shp_dir = root / "Reg01012026"
    shp_dir.mkdir()
    ds = ogr.GetDriverByName("ESRI Shapefile").CreateDataSource(str(shp_dir / "Reg01012026_WGS84.shp"))
    lyr = ds.CreateLayer("Reg01012026_WGS84", srs, ogr.wkbPolygon)
    lyr.CreateField(ogr.FieldDefn("COD_REG", ogr.OFTInteger64))
    for code, geom in ((2, poly), (3, poly.Buffer(-5000))):
        feat = ogr.Feature(lyr.GetLayerDefn())
        feat.SetField("COD_REG", code)
        feat.SetGeometry(geom)
        lyr.CreateFeature(feat)
    ds = None
    import zipfile

    archive = root / "Limiti01012026.zip"
    with zipfile.ZipFile(archive, "w") as z:
        for path in sorted(shp_dir.iterdir()):
            z.write(path, f"Reg01012026/{path.name}")

    base = yaml.safe_load((Path(__file__).resolve().parent.parent / "config.yaml").read_text(encoding="utf-8"))
    services = server.url + "/rest/services"
    cfg = {
        "grid": base["grid"],
        "limits": base["limits"],
        "verification": {"candidates_per_file": 400, "points_per_file": 60, "seed": 11},
        "countries": {
            "IT": {
                "code": 3,
                "eu_roaming": True,
                "mask": {"type": "vector_file", "url": archive.as_uri(), "member": "Reg01012026/Reg01012026_WGS84.shp", "where": "COD_REG IN (1, 2, 7)", "expect": 1, "delete_after": True},
                "slots": [{"id": f"it_{n}", "min_operators": n} for n in (1, 2, 3, 4)],
                "sources": ["it_agcom"],
            }
        },
        "sources": {
            "it_agcom": {
                "country": "IT",
                "type": 1,
                "name": "AGCOM, Broadband Map",
                "attribution": "BroadbandMap di Agcom",
                "licence": "CC BY 4.0",
                "service_url": f"{services}/Grid100/mobile_4G/MapServer",
                "query_url": f"{services}/Grid100/mobile_4G/MapServer/0/query",
                "date_url": f"{services}/Grid100/data_pubblicazione/FeatureServer/0/query",
                "region_field": "COD_REG",
                "regions": [1, 2, 7],
                "page_size": 3,
                "pause_s": 0,
                "services": {"data": {"techno": "4G"}},
                "count_field": "n_infrastrutture_totali",
                "values": {1: 1, 2: 2, 3: 3, 4: 4},
                "covered_level": 2,
                "levels_kind": "binary",
                "per_operator": True,
                "resolution_m": 100,
            }
        },
        "scopes": {"italie": {"countries": ["IT"]}},
    }
    config = root / "config.yaml"
    config.write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding="utf-8")
    out = root / "out"
    try:
        code = cli.main(["--config", str(config), "build", "--scope", "italie", "--services", "data,voice", "--work", str(root / "work"), "--out", str(out), "--date", "2026-11-14"])
        assert code == 0
        yield {"out": out, "root": root, "layer": layer, "archive": archive}
    finally:
        server.close()
        patch.undo()


def test_polygonal_repairs_grid_polygons():
    wkt = "POLYGON ((0 0,0 2,2 2,2 4,4 4,4 2,2 2,2 0,0 0))"  # deux carrés qui se touchent par un coin
    geom = ogr.CreateGeometryFromWkt(wkt)
    assert not geom.IsValid()
    fixed = polygonal(geom)
    assert fixed is not None and fixed.IsValid() and fixed.GetGeometryName() == "MULTIPOLYGON"
    assert abs(fixed.GetArea() - 8.0) < 1e-9
    # Deux parties qui se recouvrent : la partie commune reste couverte (réunion), elle ne devient pas un trou.
    overlapping = ogr.CreateGeometryFromWkt("MULTIPOLYGON (((0 0,0 50,50 50,50 0,0 0)),((25 25,25 75,75 75,75 25,25 25)))")
    assert not overlapping.IsValid()
    union = polygonal(overlapping)
    assert union is not None and union.IsValid() and abs(union.GetArea() - 4375.0) < 1e-9
    assert union.Contains(ogr.CreateGeometryFromWkt("POINT (40 40)"))
    assert polygonal(ogr.CreateGeometryFromWkt("POLYGON EMPTY")) is None
    assert polygonal(ogr.CreateGeometryFromWkt("LINESTRING (0 0,1 1)")) is None


def test_italy_manifest_and_state(italy: dict):
    manifest = json.loads((italy["out"] / "manifest.json").read_text(encoding="utf-8"))
    country = manifest["countries"][0]
    assert country["iso"] == "IT" and country["code"] == 3 and country["euRoaming"] is True
    assert country["slots"] == [{"id": f"it_{n}", "minOperators": n} for n in (1, 2, 3, 4)]
    source = country["sources"][0]
    assert source["type"] == 1 and source["levels"] == "binary" and source["services"] == ["data"]
    assert source["date"] == "2026-01" and source["dataDate"] == "2026-01-27"
    state = json.loads((italy["out"] / "etat-sources.json").read_text(encoding="utf-8"))
    assert state["sources"]["it_agcom"] == {
        "service": "mobile_4G_20260127",
        "couche": "mobile_4G_260127_260205",
        "publication": "Dati del 27 gennaio 2026 - Pubblicazione del 2 feb 2026",
        "entites": 8,
    }
    # Le masque est lu dans l'archive zip, qui est ensuite supprimée du dossier de travail.
    assert not (italy["root"] / "work" / "Limiti01012026.zip").exists()
    assert italy["archive"].exists()


def test_italy_pixels(italy: dict):
    manifest = json.loads((italy["out"] / "manifest.json").read_text(encoding="utf-8"))
    report = json.loads((italy["out"] / "rapport-construction.json").read_text(encoding="utf-8"))
    g = report["grid"]
    canvas = Canvas(Grid(12, 256), g["tx0"], g["ty0"], g["tx1"], g["ty1"])
    reader = TileReader(italy["out"], manifest)

    def pixel(dx_km: float, dy_km: float) -> tuple[int, int, int, int]:
        col, row = canvas.pixel_of_mercator(X0 + dx_km * KM, Y0 + dy_km * KM)
        tx, ty, px, py = canvas.tile_and_pixel(col, row)
        tile = reader.tile(12, tx, ty)
        return (0, 0, 0, 0) if tile is None else tuple(int(v) for v in tile[py, px])

    meta = (1 << 4) | 3  # pays 3, source officielle agrégée
    try:
        assert pixel(5, 5) == (0b00000010, 0, meta, 255)  # 1 réseau : seul le premier seuil
        assert pixel(10, 5) == (0b00001010, 0, meta, 255)  # 2 réseaux
        assert pixel(14, 5) == (0b00101010, 0, meta, 255)  # 3 réseaux
        assert pixel(17.5, 5) == (0b10101010, 0, meta, 255)  # les 4 réseaux
        assert pixel(21, 3) == (0b00001010, 0, meta, 255) and pixel(23, 5) == (0b00001010, 0, meta, 255)  # les deux ailes du papillon
        assert pixel(21, 5) == (0, 0, meta, 255) and pixel(23, 3) == (0, 0, meta, 255)  # entre les ailes : rien
        assert pixel(10, 12) == (0b00101010, 0, meta, 255) and pixel(16, 12) == (0b00101010, 0, meta, 255)  # deux anneaux
        assert pixel(13, 12) == (0, 0, meta, 255)
        assert pixel(4, 12) == (0, 0, meta, 255)  # entité d'une autre région : ignorée
        assert pixel(28, 5) == (0b00000010, 0, meta, 255)  # entité qui déborde : gardée dans le pays
        assert pixel(31, 5)[3] == 0  # et coupée à la frontière
        assert pixel(1, 1) == (0, 0, meta, 255)
    finally:
        reader.close()
    assert report["stats"]["pixels_hors_pays"]["it_agcom"] > 1000
    # 8 entités par pages de 3 : 3 pages, plus 2 comptages et 2 lectures d'état.
    assert italy["layer"].requests >= 5


def test_italy_witnesses(italy: dict):
    witnesses = json.loads((italy["out"] / "temoins.json").read_text(encoding="utf-8"))
    assert {w["operator"] for w in witnesses} == {"it_1", "it_2", "it_3", "it_4"}
    assert {w["expected"] for w in witnesses} == {0, 2}
    assert {w["service"] for w in witnesses} == {"data"}
    assert len(witnesses) == 240
    assert verify(italy["out"]) == 0
