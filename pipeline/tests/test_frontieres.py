"""Frontières entre deux pays : priorité, interstices comblés, source indisponible.

Deux pays voisins fictifs, chacun avec sa source (le module de l'OFCOM sert aux deux, grâce à la clé « module »).
Le contour du second pays s'écarte de celui du premier sur 4 km : l'interstice fait jusqu'à 300 m de large.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pytest
import yaml
from osgeo import gdal, ogr, osr

from czb import cli
from czb.grid import Canvas, Grid
from czb.layers import MARK, Layers
from czb.masks import fill_gaps
from czb.verify import TileReader, verify

# Coin nord-ouest des rasters de test, en LV95 (vers Berne).
X0, Y0 = 2_590_000.0, 1_210_000.0
COLS, ROWS = 220, 120
BORDER_COL = 110  # la frontière suit le bord ouest de cette colonne
GAP_ROWS = (40, 80)  # l'interstice s'étend de la ligne 40 à la ligne 80 (4 km)
GAP_DEPTH_M = 300.0


def _srs(epsg: int) -> osr.SpatialReference:
    srs = osr.SpatialReference()
    srs.ImportFromEPSG(epsg)
    srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return srs


def _polygon(points: list[tuple[float, float]], *holes: list[tuple[float, float]]) -> ogr.Geometry:
    poly = ogr.Geometry(ogr.wkbPolygon)
    for ring_points in [points, *holes]:
        ring = ogr.Geometry(ogr.wkbLinearRing)
        for x, y in ring_points + [ring_points[0]]:
            ring.AddPoint_2D(x, y)
        poly.AddGeometry(ring)
    return poly


def _x(col: float) -> float:
    return X0 + col * 100.0


def _y(row: float) -> float:
    return Y0 - row * 100.0


def west_country() -> ogr.Geometry:
    """Pays prioritaire, à l'ouest, avec deux enclaves qui doivent rester vides : l'une de 2 km de côté (400 ha),
    l'autre de 300 m de côté (9 ha) : petite, mais bordée par ce seul pays, ce n'est pas un interstice."""
    outer = [(_x(10), _y(110)), (_x(BORDER_COL), _y(110)), (_x(BORDER_COL), _y(10)), (_x(10), _y(10))]
    enclave = [(_x(40), _y(70)), (_x(40), _y(50)), (_x(60), _y(50)), (_x(60), _y(70))]
    small = [(_x(75), _y(91)), (_x(75), _y(88)), (_x(78), _y(88)), (_x(78), _y(91))]
    return _polygon(outer, enclave, small)


def east_country() -> ogr.Geometry:
    """Pays voisin, à l'est : son contour s'écarte de la frontière entre les lignes 40 et 80."""
    middle = (GAP_ROWS[0] + GAP_ROWS[1]) / 2
    return _polygon(
        [
            (_x(BORDER_COL), _y(110)),
            (_x(210), _y(110)),
            (_x(210), _y(10)),
            (_x(BORDER_COL), _y(10)),
            (_x(BORDER_COL), _y(GAP_ROWS[0])),
            (_x(BORDER_COL) + GAP_DEPTH_M, _y(middle)),
            (_x(BORDER_COL), _y(GAP_ROWS[1])),
        ]
    )


def _write_mask(path: Path, geom: ogr.Geometry) -> None:
    ds = ogr.GetDriverByName("GPKG").CreateDataSource(str(path))
    layer = ds.CreateLayer("pays", _srs(2056), ogr.wkbPolygon)
    feat = ogr.Feature(layer.GetLayerDefn())
    geom = geom.Clone()
    geom.Segmentize(500)
    feat.SetGeometry(geom)
    layer.CreateFeature(feat)
    ds = None


def _write_raster(path: Path, values: np.ndarray) -> None:
    ds = gdal.GetDriverByName("GTiff").Create(str(path), COLS, ROWS, 1, gdal.GDT_Float32, options=["COMPRESS=LZW"])
    ds.SetGeoTransform((X0, 100.0, 0.0, Y0, 0.0, -100.0))
    ds.SetProjection(_srs(2056).ExportToWkt())
    band = ds.GetRasterBand(1)
    band.SetNoDataValue(float("nan"))
    band.WriteArray(values)
    ds = None


def _items(path: Path, tif: Path) -> None:
    path.write_text(
        json.dumps({"features": [{"id": "x", "properties": {"datetime": "2026-04-30T00:00:00Z"}, "assets": {tif.name: {"href": tif.as_uri(), "updated": "2026-10-26T15:00:38Z", "proj:epsg": 2056}}}]}),
        encoding="utf-8",
    )


def _source(country: str, items: Path) -> dict:
    return {
        "module": "ch_bakom",
        "country": country,
        "type": 1,
        "name": f"Source de test {country}",
        "attribution": "Test",
        "licence": "Utilisation libre",
        "stac_url": items.as_uri(),
        "services": {"data": {"techno": "4G", "collection": "c"}},
        "values": {0: 0, 2: 1, 3: 3},
        "covered_level": 2,
        "levels_kind": "binary",
        "per_operator": True,
    }


@pytest.fixture(scope="module")
def border(tmp_path_factory: pytest.TempPathFactory) -> dict:
    root = tmp_path_factory.mktemp("frontiere")
    remote = root / "distant"
    remote.mkdir()
    _write_mask(remote / "ouest.gpkg", west_country())
    _write_mask(remote / "est.gpkg", east_country())

    # Source de l'ouest : tout le pays couvert par les 3 opérateurs, sauf un rectangle sans couverture.
    # Elle déborde chez le voisin (couvert par les 3 opérateurs jusqu'à 3 km au-delà de la frontière) :
    # rien ne doit en être écrit hors de son pays.
    west = np.full((ROWS, COLS), np.nan, dtype=np.float32)
    west[:, : BORDER_COL + 30] = 3
    west[20:30, 20:40] = 0
    _write_raster(remote / "ouest.tif", west)
    _items(remote / "ouest.json", remote / "ouest.tif")

    # Source de l'est : couverte par les 3 opérateurs, découpée au contour du pays (rien dans l'interstice).
    east = np.full((ROWS, COLS), np.nan, dtype=np.float32)
    east[:, BORDER_COL:] = 3
    east[90:100, BORDER_COL + 5 : BORDER_COL + 25] = 0  # zone sans couverture, là où la source voisine déborde
    middle = (GAP_ROWS[0] + GAP_ROWS[1]) / 2
    for row in range(GAP_ROWS[0], GAP_ROWS[1]):
        depth_m = GAP_DEPTH_M * (1 - abs(row + 0.5 - middle) / (middle - GAP_ROWS[0]))
        for col in range(BORDER_COL, BORDER_COL + 4):
            if (col + 0.5 - BORDER_COL) * 100 < depth_m:
                east[row, col] = np.nan
    _write_raster(remote / "est.tif", east)
    _items(remote / "est.json", remote / "est.tif")

    base = yaml.safe_load((Path(__file__).resolve().parent.parent / "config.yaml").read_text(encoding="utf-8"))
    slots = [{"id": "un", "min_operators": 1}, {"id": "tous", "min_operators": 3}]
    cfg = {
        "grid": base["grid"],
        "limits": base["limits"],
        "verification": {"candidates_per_file": 400, "points_per_file": 60, "seed": 5},
        "countries": {
            "CH": {"code": 2, "eu_roaming": False, "mask": {"type": "vector_file", "url": (remote / "ouest.gpkg").as_uri(), "filename": "ouest.gpkg"}, "slots": slots, "sources": ["ouest"]},
            "IT": {"code": 3, "eu_roaming": True, "mask": {"type": "vector_file", "urls": [{"url": (remote / "est.gpkg").as_uri(), "filename": "est.gpkg"}], "expect": 1}, "slots": slots, "sources": ["est"]},
            # Pays dont la seule source demande une clé d'accès absente : il doit être laissé de côté sans faire échouer la construction.
            "AD": {"code": 5, "eu_roaming": False, "mask": {"type": "vector_file", "url": (remote / "inexistant.gpkg").as_uri()}, "slots": [{"id": "x", "name": "X", "mnc": [3]}], "sources": ["sans_cle"]},
        },
        "sources": {
            "ouest": _source("CH", remote / "ouest.json"),
            "est": _source("IT", remote / "est.json"),
            "sans_cle": {
                "module": "estimation_opencellid",
                "country": "AD",
                "type": 2,
                "name": "Estimation",
                "attribution": "OpenCelliD",
                "licence": "CC BY-SA 4.0",
                "cells_url": "https://exemple.invalid/cells?token={token}&mcc={mcc}",
                "mcc": [213],
                "services": {"data": {"radios": ["LTE"]}},
                "levels_kind": "three",
            },
        },
        "scopes": {"tout": {"countries": ["CH", "IT", "AD"]}},
    }
    config = root / "config.yaml"
    config.write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding="utf-8")
    out = root / "out"
    return {"root": root, "config": config, "out": out, "cfg": cfg}


@pytest.fixture(scope="module")
def built(border: dict, monkeypatch_module: pytest.MonkeyPatch) -> dict:
    monkeypatch_module.delenv("OPENCELLID_TOKEN", raising=False)
    code = cli.main(["--config", str(border["config"]), "build", "--scope", "tout", "--services", "data", "--work", str(border["root"] / "work"), "--out", str(border["out"]), "--date", "2026-11-14"])
    assert code == 0
    return border


@pytest.fixture(scope="module")
def monkeypatch_module():
    patch = pytest.MonkeyPatch()
    yield patch
    patch.undo()


def _to_mercator(geom: ogr.Geometry) -> ogr.Geometry:
    out = geom.Clone()
    out.Transform(osr.CoordinateTransformation(_srs(2056), _srs(3857)))
    return out


def _ground_ha(geom: ogr.Geometry) -> float:
    x0, x1, y0, y1 = geom.GetEnvelope()
    lat = 2 * math.atan(math.exp((y0 + y1) / 2 / 6378137.0)) - math.pi / 2
    return geom.GetArea() * math.cos(lat) ** 2 / 1e4


def test_fill_gaps_gives_small_holes_to_the_lower_priority_country():
    geoms = {"CH": [_to_mercator(west_country())], "IT": [_to_mercator(east_country())]}
    holes = fill_gaps(geoms, ["CH", "IT"])
    # L'interstice de 60 ha va au pays le moins prioritaire ; les enclaves de 400 et 9 ha restent vides.
    assert len(holes["IT"]) == 1 and holes["CH"] == []
    assert 55 < _ground_ha(holes["IT"][0]) < 65
    # Avec un seuil plus bas, l'interstice n'est plus comblé. Avec un seuil très haut, les enclaves restent vides :
    # une seule entité les borde.
    assert fill_gaps(geoms, ["CH", "IT"], max_ha=50)["IT"] == []
    high = fill_gaps(geoms, ["CH", "IT"], max_ha=1000)
    assert high["CH"] == [] and len(high["IT"]) == 1
    # L'ordre de priorité décide du bénéficiaire.
    assert len(fill_gaps(geoms, ["IT", "CH"])["CH"]) == 1


def test_fill_gaps_needs_two_mask_entities():
    """Un trou bordé par une seule entité de contour reste vide, même petit (zone-03 : deux morceaux de Lombardie
    enclavés dans le Piémont). Entre deux entités d'un même pays (deux régions, deux communautés), il est comblé."""
    outer = [(_x(10), _y(110)), (_x(110), _y(110)), (_x(110), _y(10)), (_x(10), _y(10))]
    # Une région percée d'un trou de 400 m de côté (16 ha) : l'enclave d'une région hors du périmètre.
    region = _polygon(outer, [(_x(48), _y(52)), (_x(48), _y(48)), (_x(52), _y(48)), (_x(52), _y(52))])
    assert fill_gaps({"IT": [_to_mercator(region)]}, ["IT"]) == {"IT": []}
    # Deux régions voisines qui laissent entre elles le même trou, à cheval sur leur limite : c'est un interstice.
    west = _polygon([(_x(10), _y(110)), (_x(50), _y(110)), (_x(50), _y(52)), (_x(48), _y(52)), (_x(48), _y(48)), (_x(50), _y(48)), (_x(50), _y(10)), (_x(10), _y(10))])
    east = _polygon([(_x(50), _y(110)), (_x(110), _y(110)), (_x(110), _y(10)), (_x(50), _y(10)), (_x(50), _y(48)), (_x(52), _y(48)), (_x(52), _y(52)), (_x(50), _y(52))])
    two = {"ES": [_to_mercator(west), _to_mercator(east)]}
    holes = fill_gaps(two, ["ES"])
    assert len(holes["ES"]) == 1 and 15 < _ground_ha(holes["ES"][0]) < 17
    assert fill_gaps(two, ["ES"], max_ha=10) == {"ES": []}  # le seuil de taille vaut toujours
    # Les deux mêmes régions en une seule entité (un multipolygone) : une seule entité borde le trou, il reste vide.
    single = ogr.Geometry(ogr.wkbMultiPolygon)
    single.AddGeometry(west)
    single.AddGeometry(east)
    assert fill_gaps({"ES": [_to_mercator(single)]}, ["ES"]) == {"ES": []}
    # Un pays voisin qui touche le trou suffit : deux pays, deux entités.
    holes = fill_gaps({"FR": [_to_mercator(region)], "ES": [_to_mercator(_polygon([(_x(50), _y(52)), (_x(50), _y(48)), (_x(52), _y(48)), (_x(52), _y(52))]))]}, ["FR", "ES"])
    assert holes["FR"] == [] and len(holes["ES"]) == 1 and 7 < _ground_ha(holes["ES"][0]) < 9


def test_mask_area_guard(border: dict, tmp_path: Path):
    """Un contour dont la surface sort de l'intervalle attendu arrête la construction (contours tirés d'OpenStreetMap)."""
    import copy

    from czb.context import BuildContext, grid_from_config
    from czb.masks import ground_area_km2, load_mask_geometries

    cfg = copy.deepcopy(border["cfg"])
    cfg["scopes"]["ouest"] = {"countries": ["CH"]}
    ctx = BuildContext(cfg=cfg, scope_name="ouest", services=["data"], workdir=tmp_path, outdir=tmp_path / "out", grid=grid_from_config(cfg))
    geoms = load_mask_geometries(ctx)
    # Le pays de l'ouest : 10 km sur 10 km, moins une enclave de 2 km de côté et une autre de 300 m.
    assert abs(ground_area_km2(geoms["CH"]) - 95.91) < 0.5
    cfg["countries"]["CH"]["mask"]["expect_area_km2"] = [90, 100]
    assert len(load_mask_geometries(ctx)["CH"]) == 1
    cfg["countries"]["CH"]["mask"]["expect_area_km2"] = [150, 200]
    with pytest.raises(RuntimeError, match="hors de l'intervalle attendu"):
        load_mask_geometries(ctx)


OSM_LAND_AREA = """<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6" generator="test">
 <node id="1" lat="43.70" lon="7.40" version="1"/>
 <node id="2" lat="43.70" lon="7.42" version="1"/>
 <node id="3" lat="43.72" lon="7.42" version="1"/>
 <node id="4" lat="43.72" lon="7.40" version="1"/>
 <way id="10" version="1"><nd ref="1"/><nd ref="2"/><nd ref="3"/></way>
 <way id="11" version="1"><nd ref="3"/><nd ref="4"/><nd ref="1"/></way>
 <relation id="36990" version="1"><member type="way" ref="10" role="outer"/><member type="way" ref="11" role="outer"/><tag k="type" v="land_area"/></relation>
</osm>
"""


def test_mask_files_are_deleted_once_read(built: dict, tmp_path: Path):
    """Chaque fichier de contour téléchargé est supprimé dès que ses géométries sont lues, avec les trois chargeurs ;
    une nouvelle lecture le télécharge de nouveau, et « delete_after: false » le garde."""
    import gzip
    import zipfile

    from czb.masks import LOADERS

    # La construction à deux pays ne laisse aucun contour dans son dossier de travail.
    assert not (built["root"] / "work" / "ouest.gpkg").exists() and not (built["root"] / "work" / "est.gpkg").exists()

    remote, work = tmp_path / "distant", tmp_path / "travail"
    remote.mkdir()
    _write_mask(remote / "ouest.gpkg", west_country())
    _write_mask(remote / "est.gpkg", east_country())
    with zipfile.ZipFile(remote / "est.zip", "w") as archive:
        archive.write(remote / "est.gpkg", "dossier/est.gpkg")
    vector = {"type": "vector_file", "expect": 2, "urls": [{"url": (remote / "ouest.gpkg").as_uri(), "filename": "ouest.gpkg"}, {"url": (remote / "est.zip").as_uri(), "filename": "est.zip", "member": "dossier/est.gpkg"}]}
    for _ in range(2):  # la seconde lecture retélécharge les fichiers supprimés
        assert len(LOADERS["vector_file"](vector, {}, work)) == 2
        assert list(work.iterdir()) == []

    departements = {"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {"code": code}, "geometry": {"type": "Polygon", "coordinates": [[[lon, 45.0], [lon + 0.1, 45.0], [lon + 0.1, 45.1], [lon, 45.1], [lon, 45.0]]]}} for code, lon in (("05", 6.0), ("38", 5.9), ("971", -61.5))]}
    (remote / "departements.geojson.gz").write_bytes(gzip.compress(json.dumps(departements).encode("utf-8")))
    etalab = {"type": "etalab_departements", "url": (remote / "departements.geojson.gz").as_uri(), "metropole_only": True}
    assert len(LOADERS["etalab_departements"](etalab, {}, work)) == 2
    assert list(work.iterdir()) == []

    (remote / "terre.osm").write_text(OSM_LAND_AREA, encoding="utf-8")
    land = {"type": "osm_land_area", "url": (remote / "terre.osm").as_uri(), "relation": 36990}
    assert len(LOADERS["osm_land_area"](land, {}, work)) == 1
    assert list(work.iterdir()) == []

    kept = {"type": "vector_file", "url": (remote / "ouest.gpkg").as_uri(), "filename": "ouest.gpkg", "delete_after": False}
    assert len(LOADERS["vector_file"](kept, {}, work)) == 1
    assert [p.name for p in work.iterdir()] == ["ouest.gpkg"]


def test_extrapolate_marked_takes_the_lowest_known_neighbour(tmp_path: Path):
    canvas = Canvas(Grid(12, 256), 2100, 1400, 2100, 1400)
    layers = Layers(canvas, tmp_path)
    inside = np.zeros((256, 256), dtype=bool)
    inside[10:20, 10:40] = True
    layers.claim_country((0, 0, 256, 256), inside, 3, 1)
    gap = np.zeros((256, 256), dtype=bool)
    gap[10:20, 40:46] = True  # six colonnes d'interstice à l'est du pays
    assert layers.claim_country((0, 0, 256, 256), gap, 3, 1, marked=True) == 60
    other = np.zeros((256, 256), dtype=bool)
    other[10:20, 46:60] = True  # un autre pays, très bien couvert, ne doit pas déteindre
    layers.claim_country((0, 0, 256, 256), other, 2, 0)
    layers.merge_level("data", 0, (46, 10, 14, 10), np.full((10, 14), 3, dtype=np.uint8), 2)
    # Le pays : niveau 2 pour l'opérateur 0, sauf deux lignes à 1 ; niveau 3 pour l'opérateur 2 en voix.
    level = np.full((10, 30), 2, dtype=np.uint8)
    level[4:6, :] = 1
    layers.merge_level("data", 0, (10, 10, 30, 10), level, 3)
    layers.merge_level("voice", 2, (10, 10, 30, 10), np.full((10, 30), 3, dtype=np.uint8), 3)
    # Une source a écrit un niveau dans un pixel de l'interstice : il ne doit pas baisser.
    layers.merge_level("data", 0, (41, 12, 1, 1), np.full((1, 1), 3, dtype=np.uint8), 3)
    assert (np.asarray(layers.B[10:20, 40:46]) & MARK).all()
    assert not layers.described(np.array([12]), np.array([42]), 3)[0]
    assert layers.described(np.array([12]), np.array([30]), 3)[0]

    stats = layers.extrapolate_marked([(40, 10, 6, 10)], passes=4)
    r = np.asarray(layers.R)
    g = np.asarray(layers.G)
    b = np.asarray(layers.B)
    assert stats == {"marques": 60, "extrapoles": 40, "sans_voisin": 20}  # 4 passes : 4 colonnes sur 6
    assert not (b & MARK).any()
    assert (b[10:20, 40:46] == ((1 << 4) | 3)).all()
    assert (r[10:14, 40] & 0b11 == 2).all() and (r[14:16, 40] & 0b11 == 1).all()
    assert r[12, 41] & 0b11 == 3  # niveau écrit par la source : conservé
    assert r[12, 42] & 0b11 == 3  # son seul voisin connu à cette passe est ce pixel
    assert r[11, 42] & 0b11 == 2 and r[11, 41] & 0b11 == 2  # les lignes voisines gardent le niveau du pays
    assert ((g[10:20, 40:44] >> 4) & 0b11 == 3).all()
    assert (r[10:20, 44:46] == 0).all() and (g[10:20, 44:46] == 0).all()  # trop loin : reste à 0
    assert (r[10:20, 46:60] & 0b11 == 3).all()  # le pays voisin n'a pas bougé


def test_border_build_skips_the_unavailable_country(built: dict):
    manifest = json.loads((built["out"] / "manifest.json").read_text(encoding="utf-8"))
    assert [c["iso"] for c in manifest["countries"]] == ["CH", "IT"]
    assert manifest["missing"] == [{"iso": "AD", "code": 5}]
    report = json.loads((built["out"] / "rapport-construction.json").read_text(encoding="utf-8"))
    assert report["skipped_countries"] == ["AD"]
    assert "OPENCELLID_TOKEN" in report["unavailable_sources"]["sans_cle"]
    state = json.loads((built["out"] / "etat-sources.json").read_text(encoding="utf-8"))
    assert "indisponible" in state["sources"]["sans_cle"]
    assert set(state["sources"]) == {"ouest", "est", "sans_cle"}


def test_undeclared_slots_are_always_zero(built: dict):
    """Les deux pays ne déclarent que 2 emplacements : le manifest dit que les emplacements 2 et 3 valent 0, et c'est vrai dans chaque pixel."""
    manifest = json.loads((built["out"] / "manifest.json").read_text(encoding="utf-8"))
    assert [len(c["slots"]) for c in manifest["countries"]] == [2, 2]
    assert "au-delà de cette liste, l'emplacement est inutilisé et vaut toujours 0" in manifest["encoding"]["slots"]
    report = json.loads((built["out"] / "rapport-construction.json").read_text(encoding="utf-8"))
    g = report["grid"]
    reader = TileReader(built["out"], manifest)
    try:
        covered = 0
        for ty in range(g["ty0"], g["ty1"] + 1):
            for tx in range(g["tx0"], g["tx1"] + 1):
                tile = reader.tile(12, tx, ty)
                if tile is None:
                    continue
                covered += int((tile[..., 0] != 0).sum())
                # Bits 4 à 7 des canaux R et G : emplacements 2 et 3, jamais déclarés.
                assert not (tile[..., 0] >> 4).any() and not (tile[..., 1] >> 4).any(), f"tuile 12/{tx}/{ty}"
        assert covered > 10_000  # les emplacements déclarés, eux, portent des niveaux
    finally:
        reader.close()


def test_border_gap_is_filled_and_extrapolated(built: dict):
    manifest = json.loads((built["out"] / "manifest.json").read_text(encoding="utf-8"))
    report = json.loads((built["out"] / "rapport-construction.json").read_text(encoding="utf-8"))
    assert report["stats"]["pixels_interstices"]["IT"] > 500
    assert report["stats"]["interstices"]["sans_voisin"] == 0
    g = report["grid"]
    canvas = Canvas(Grid(12, 256), g["tx0"], g["ty0"], g["tx1"], g["ty1"])
    to_merc = osr.CoordinateTransformation(_srs(2056), _srs(3857))
    reader = TileReader(built["out"], manifest)

    def pixel(x: float, y: float) -> tuple[int, int, int, int]:
        mx, my, _ = to_merc.TransformPoint(x, y)
        col, row = canvas.pixel_of_mercator(mx, my)
        tx, ty, px, py = canvas.tile_and_pixel(col, row)
        tile = reader.tile(12, tx, ty)
        return (0, 0, 0, 0) if tile is None else tuple(int(v) for v in tile[py, px])

    try:
        middle = (GAP_ROWS[0] + GAP_ROWS[1]) / 2
        covered_ch = (0b1010, 0, (1 << 4) | 2, 255)
        covered_it = (0b1010, 0, (1 << 4) | 3, 255)
        # De part et d'autre de la frontière, loin de l'interstice.
        assert pixel(_x(BORDER_COL) - 150, _y(20)) == covered_ch
        assert pixel(_x(BORDER_COL) + 150, _y(20)) == covered_it
        # Dans l'interstice, tout près du pays prioritaire : le pixel est au voisin, avec le niveau de ses voisins.
        for depth in (30, 90, 150, 210, 270):
            assert pixel(_x(BORDER_COL) + depth, _y(middle) + 10) == covered_it, depth
        assert pixel(_x(BORDER_COL) - 30, _y(middle) + 10) == covered_ch
        # La source de l'ouest déborde ici, chez le voisin : la zone sans couverture du voisin le reste.
        assert pixel(_x(BORDER_COL + 15), _y(95)) == (0, 0, (1 << 4) | 3, 255)
        # L'enclave du pays prioritaire reste hors zone, la zone sans couverture reste sans couverture.
        assert pixel(_x(50), _y(60))[3] == 0
        assert pixel(_x(30), _y(25)) == (0, 0, (1 << 4) | 2, 255)
        # La petite enclave (9 ha) n'est pas un interstice : une seule entité la borde, elle reste hors zone.
        assert pixel(_x(76.5), _y(89.5))[3] == 0
        assert pixel(_x(73), _y(89.5)) == covered_ch and pixel(_x(80), _y(89.5)) == covered_ch
    finally:
        reader.close()
    assert verify(built["out"]) == 0
