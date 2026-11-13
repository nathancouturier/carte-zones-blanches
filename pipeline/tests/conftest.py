"""Jeu de données synthétique : de faux fichiers Arcep et de faux départements.

Il permet de tester tout le pipeline sans réseau, y compris le téléchargement
(URL file://), la décompression 7z, la rastérisation et le découpage en archives.
"""

from __future__ import annotations

import json
import math
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml
from osgeo import ogr, osr

OPERATORS = [("OF", 20801), ("SFR0", 20810), ("BOUY", 20820), ("FREE", 20815)]
# Centre de la zone de test, en Lambert-93 (vers Gap, Hautes-Alpes).
CX, CY = 945000.0, 6390000.0


def _srs(epsg: int) -> osr.SpatialReference:
    srs = osr.SpatialReference()
    srs.ImportFromEPSG(epsg)
    srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return srs


def _disk(cx: float, cy: float, radius: float, n: int = 96) -> ogr.Geometry:
    ring = ogr.Geometry(ogr.wkbLinearRing)
    for i in range(n + 1):
        a = 2 * math.pi * (i % n) / n
        ring.AddPoint_2D(cx + radius * math.cos(a), cy + radius * math.sin(a))
    poly = ogr.Geometry(ogr.wkbPolygon)
    poly.AddGeometry(ring)
    return poly


def _box(x0: float, y0: float, x1: float, y1: float) -> ogr.Geometry:
    ring = ogr.Geometry(ogr.wkbLinearRing)
    for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)):
        ring.AddPoint_2D(x, y)
    poly = ogr.Geometry(ogr.wkbPolygon)
    poly.AddGeometry(ring)
    return poly


def _multi(*polys: ogr.Geometry) -> ogr.Geometry:
    multi = ogr.Geometry(ogr.wkbMultiPolygon)
    for p in polys:
        multi.AddGeometry(p)
    return multi


def coverage_shapes(index: int) -> dict[str, ogr.Geometry]:
    """Formes de couverture d'un opérateur fictif, en Lambert-93.

    Les niveaux se chevauchent volontairement (le disque TBC est inclus dans le
    disque BC, lui-même inclus dans le disque CL) : le pipeline doit garder le
    plus élevé.
    """
    dx = index * 4000.0
    return {
        "CL": _multi(_disk(CX + dx, CY, 14000), _box(CX - 30000, CY + 20000, CX - 20000, CY + 26000)),
        "BC": _multi(_disk(CX + dx, CY, 9000)),
        "TBC": _multi(_disk(CX + dx, CY, 4000), _disk(CX + dx - 6000, CY - 5000, 1500)),
    }


def _write_gpkg(path: Path, layer_name: str, operator: tuple[str, int], index: int, techno: str, usage: str) -> None:
    ds = ogr.GetDriverByName("GPKG").CreateDataSource(str(path))
    layer = ds.CreateLayer(layer_name, _srs(2154), ogr.wkbUnknown)
    for name, kind in (("operateur", ogr.OFTInteger64), ("date", ogr.OFTString), ("techno", ogr.OFTString), ("usage", ogr.OFTString), ("niveau", ogr.OFTString), ("dept", ogr.OFTString), ("operateur_infra", ogr.OFTString), ("operateur_commercial", ogr.OFTString)):
        layer.CreateField(ogr.FieldDefn(name, kind))
    for niveau, geom in coverage_shapes(index).items():
        feat = ogr.Feature(layer.GetLayerDefn())
        feat.SetField("operateur", operator[1])
        feat.SetField("date", "2026-06-30")
        feat.SetField("techno", techno)
        feat.SetField("usage", usage)
        feat.SetField("niveau", niveau)
        feat.SetField("dept", "05")
        feat.SetField("operateur_infra", operator[0])
        feat.SetField("operateur_commercial", operator[0])
        feat.SetGeometry(geom)
        layer.CreateFeature(feat)
    ds = None


def _departements(path: Path) -> None:
    """Deux départements voisins et un département d'outre-mer, en WGS 84."""
    to_wgs = osr.CoordinateTransformation(_srs(2154), _srs(4326))
    features = []
    for code, nom, box in (
        ("05", "Hautes-Alpes", (CX - 40000, CY - 30000, CX + 30000, CY + 30000)),
        ("38", "Isère", (CX - 80000, CY - 30000, CX - 40000, CY + 30000)),
        ("971", "Guadeloupe", (CX + 200000, CY, CX + 210000, CY + 10000)),
    ):
        geom = _box(*box)
        geom.Segmentize(2000)
        geom.Transform(to_wgs)
        features.append({"type": "Feature", "properties": {"code": code, "nom": nom, "region": "93"}, "geometry": json.loads(geom.ExportToJson())})
    path.write_text(json.dumps({"type": "FeatureCollection", "features": features}), encoding="utf-8")


@pytest.fixture(scope="session")
def synthetic(tmp_path_factory: pytest.TempPathFactory) -> dict:
    if shutil.which("7z") is None:
        pytest.skip("7z absent")
    root = tmp_path_factory.mktemp("synthetique")
    remote = root / "distant"
    remote.mkdir()
    items = []
    for index, operator in enumerate(OPERATORS):
        for techno, usage in (("4G", "data"), ("2G3G", "voix")):
            stem = f"2026_T2_couv_Metropole_{operator[0]}_{techno}_{usage}"
            gpkg = remote / f"{stem}.gpkg"
            _write_gpkg(gpkg, stem, operator, index if usage == "data" else index + 1, techno, usage)
            subprocess.run(["7z", "a", "-y", str(remote / f"{stem}.gpkg.7z"), str(gpkg)], check=True, stdout=subprocess.DEVNULL)
            gpkg.unlink()
            size = (remote / f"{stem}.gpkg.7z").stat().st_size
            items.append(
                f'<li class="list-group-item d-flex flex-wrap file"><span class="flex-grow-1"><a href="{stem}.gpkg.7z" class="matomo_download">{stem}.gpkg.7z</a></span>'
                f'<span data-size="{size}" class="size">1 Mo</span><time datetime="2026-09-24T15:35:09+00:00" class="last-modified">24 sept. 2026</time></li>'
            )
    (remote / "index.html").write_text("<html><body><ul>" + "\n".join(items) + "</ul></body></html>", encoding="utf-8")
    _departements(remote / "departements.geojson")

    base = yaml.safe_load((Path(__file__).resolve().parent.parent / "config.yaml").read_text(encoding="utf-8"))
    base["countries"]["FR"]["mask"]["url"] = (remote / "departements.geojson").as_uri()
    base["sources"]["fr_arcep"]["listing_url"] = (remote / "index.html").as_uri()
    base["verification"] = {"candidates_per_file": 160, "points_per_file": 40, "seed": 7}
    config = root / "config.yaml"
    config.write_text(yaml.safe_dump(base, allow_unicode=True), encoding="utf-8")
    return {"root": root, "config": config, "base": base}
