"""Estimation (OpenCellID et relief) sur un jeu synthétique : une crête cache une antenne à la moitié du pays."""

from __future__ import annotations

import gzip
import json
import shutil
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np
import pytest
import yaml
from osgeo import gdal, osr

from czb import cli
from czb.context import load_config
from czb.grid import Canvas, Grid, lonlat_to_mercator
from czb.sources import create_source
from czb.sources.base import SourceUnavailable
from czb.sources.estimation_opencellid import cluster_sites
from czb.verify import TileReader, verify

SITE = (1.50, 42.55)  # antenne, à l'ouest de la crête
RIDGE_LON = 1.55  # crête nord-sud de 2 500 m au milieu d'une plaine à 1 000 m
HEADER = "radio,mcc,net,area,cell,unit,lon,lat,range,samples,changeable,created,updated,averageSignal"


def _dem(path: Path) -> None:
    """Dalle de 1 degré au pas de 3 secondes d'arc, comme une dalle Copernicus allégée."""
    size = 1200
    lons = 1.0 + (np.arange(size) + 0.5) / size
    relief = np.full((size, size), 1000.0, dtype=np.float32)
    relief[:, np.abs(lons - RIDGE_LON) < 0.004] = 2500.0
    ds = gdal.GetDriverByName("GTiff").Create(str(path), size, size, 1, gdal.GDT_Float32, options=["COMPRESS=DEFLATE"])
    ds.SetGeoTransform((1.0, 1.0 / size, 0.0, 43.0, 0.0, -1.0 / size))
    srs = osr.SpatialReference()
    srs.ImportFromEPSG(4326)
    ds.SetProjection(srs.ExportToWkt())
    ds.GetRasterBand(1).WriteArray(relief)
    ds = None


def _cells(with_header: bool = True) -> bytes:
    lon, lat = SITE
    rows = [
        # Station 1000 : trois secteurs autour du pylône, à 150 m environ.
        f"LTE,213,3,100,{1000 * 256 + 1},1,{lon + 0.0018},{lat},1000,40,1,1700000000,1760000000,0",
        f"LTE,213,3,100,{1000 * 256 + 2},2,{lon - 0.0009},{lat + 0.0012},1000,25,1,1700000000,1760000000,0",
        f"LTE,213,3,100,{1000 * 256 + 3},3,{lon - 0.0009},{lat - 0.0012},1000,31,1,1700000000,1760000000,0",
        # Une cellule 5G à 100 m : même site.
        f"NR,213,3,100,9000000001,4,{lon + 0.0008},{lat + 0.0004},1000,5,1,1700000000,1760000000,0",
        # Ignorées : 2G, autre pays, hors de l'emprise, ligne abîmée.
        f"GSM,213,3,100,77,,{lon + 0.05},{lat},1000,90,1,1700000000,1760000000,0",
        f"LTE,214,7,100,{2000 * 256 + 1},1,{lon + 0.06},{lat},1000,90,1,1700000000,1760000000,0",
        f"LTE,213,3,100,{3000 * 256 + 1},1,3.20,{lat},1000,90,1,1700000000,1760000000,0",
        "LTE,213,3,abc",
    ]
    text = "\n".join(([HEADER] if with_header else []) + rows) + "\n"
    return gzip.compress(text.encode("utf-8"))


def _mask(path: Path) -> None:
    west, east, south, north = 1.42, 1.66, 42.49, 42.61
    ring = [[west, south], [east, south], [east, north], [west, north], [west, south]]
    path.write_text(json.dumps({"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {}, "geometry": {"type": "Polygon", "coordinates": [ring]}}]}), encoding="utf-8")


def _config(root: Path, remote: Path, cells_url: str) -> Path:
    base = yaml.safe_load((Path(__file__).resolve().parent.parent / "config.yaml").read_text(encoding="utf-8"))
    cfg = {
        "grid": base["grid"],
        "limits": base["limits"],
        "verification": {"candidates_per_file": 400, "points_per_file": 60, "seed": 17},
        "countries": {
            "AD": {"code": 5, "eu_roaming": False, "mask": {"type": "vector_file", "url": (remote / "ad.geojson").as_uri()}, "slots": [{"id": "reseaux", "min_operators": 1}], "sources": ["ad_estimation"]},
        },
        "sources": {
            "ad_estimation": {
                "module": "estimation_opencellid",
                "country": "AD",
                "type": 2,
                "name": "Estimation : antennes OpenCellID et relief Copernicus",
                "attribution": "OpenCellID, Copernicus",
                "licence": "CC BY-SA 4.0",
                "cells_url": cells_url,
                "dem_url": (remote / "mnt").as_uri() + "/dem_{ns}{lat:02d}_{ew}{lon:03d}.tif",
                "mcc": [213],
                "services": {"data": {"techno": "4G/5G", "radios": ["LTE", "NR"]}},
                "levels_kind": "three",
                "antenna_height_m": 30,
                "mobile_height_m": 1.5,
                "curvature": 0.75,
                "near_miss_m": 30,
                "site_merge_m": 300,
                "station_spread_max_m": 2000,
                "good": {"visible_km": 5, "near_km": 1, "any_km": 0.5},
                "limited": {"visible_km": 15, "near_km": 7.5, "any_km": 2},
            }
        },
        "scopes": {"andorre": {"countries": ["AD"]}},
    }
    config = root / "config.yaml"
    config.write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding="utf-8")
    return config


@pytest.fixture(scope="module")
def andorra(tmp_path_factory: pytest.TempPathFactory) -> dict:
    root = tmp_path_factory.mktemp("estimation")
    remote = root / "distant"
    (remote / "mnt").mkdir(parents=True)
    _dem(remote / "mnt" / "dem_N42_E001.tif")
    (remote / "213.csv.gz").write_bytes(_cells())
    _mask(remote / "ad.geojson")
    config = _config(root, remote, (remote / "{mcc}.csv.gz").as_uri().replace("%7B", "{").replace("%7D", "}"))
    out = root / "out"
    code = cli.main(["--config", str(config), "build", "--scope", "andorre", "--services", "data", "--work", str(root / "work"), "--out", str(out), "--date", "2026-11-14"])
    assert code == 0
    return {"root": root, "remote": remote, "config": config, "out": out}


def _pixel_reader(out: Path):
    manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
    report = json.loads((out / "rapport-construction.json").read_text(encoding="utf-8"))
    g = report["grid"]
    canvas = Canvas(Grid(12, 256), g["tx0"], g["ty0"], g["tx1"], g["ty1"])
    reader = TileReader(out, manifest)

    def pixel(lon: float, lat: float) -> tuple[int, int, int, int]:
        col, row = canvas.pixel_of_mercator(*lonlat_to_mercator(lon, lat))
        tx, ty, px, py = canvas.tile_and_pixel(col, row)
        tile = reader.tile(12, tx, ty)
        return (0, 0, 0, 0) if tile is None else tuple(int(v) for v in tile[py, px])

    return reader, pixel, report, manifest


def test_estimated_levels_follow_the_terrain(andorra: dict):
    reader, pixel, report, manifest = _pixel_reader(andorra["out"])
    meta = (2 << 4) | 5  # pays 5, source estimée
    lon, lat = SITE
    try:
        assert pixel(lon + 0.02, lat) == (2, 0, meta, 255)  # à 1,6 km, en vue directe : bonne
        assert pixel(lon - 0.07, lat) == (1, 0, meta, 255)  # à 5,7 km, en vue directe : limitée
        assert pixel(RIDGE_LON + 0.05, lat) == (0, 0, meta, 255)  # derrière la crête : pas de couverture
        assert pixel(RIDGE_LON + 0.05, lat + 0.04) == (0, 0, meta, 255)
        assert pixel(1.70, lat)[3] == 0  # hors du pays
    finally:
        reader.close()
    country = manifest["countries"][0]
    assert country["iso"] == "AD" and country["euRoaming"] is False
    source = country["sources"][0]
    assert source["type"] == 2 and source["levels"] == "three" and source["id"] == "ad_estimation"
    stats = report["stats"]
    assert stats["estimation_cellules"]["ad_estimation"] == {"lues": 7, "retenues": 4, "par_code_reseau": {"3": 4}}
    assert stats["estimation_sites"]["ad_estimation"]["reseaux"] == {"stations": 1, "stations_dispersees": 0, "sites": 1, "cellules": 4}
    shares = stats["estimation_parts"]["ad_estimation:reseaux"]
    assert shares["0"] > 30 and shares["2"] > 10 and abs(sum(shares.values()) - 100) < 0.5
    assert stats["copie_de_travail"]["ad_estimation"] == "reconstruite"
    assert verify(andorra["out"]) == 0
    witnesses = json.loads((andorra["out"] / "temoins.json").read_text(encoding="utf-8"))
    assert {w["expected"] for w in witnesses} == {0, 1, 2}
    # Les fichiers intermédiaires sont supprimés.
    assert not list((andorra["root"] / "work" / "opencellid").glob("*"))
    assert not list((andorra["root"] / "work" / "mnt").glob("*"))


def test_working_copy_avoids_a_second_download(andorra: dict):
    root = andorra["root"]
    work = root / "work2"
    (work / "cache").mkdir(parents=True)
    shutil.copy(andorra["out"] / "cache-ad_estimation.tif", work / "cache")
    # Le fichier des cellules a disparu : la copie de travail du mois suffit.
    hidden = andorra["remote"] / "213.csv.gz"
    hidden.rename(hidden.with_suffix(".absent"))
    try:
        out2 = root / "out2"
        code = cli.main(["--config", str(andorra["config"]), "build", "--scope", "andorre", "--services", "data", "--work", str(work), "--out", str(out2), "--date", "2026-11-15"])
        assert code == 0
        report = json.loads((out2 / "rapport-construction.json").read_text(encoding="utf-8"))
        assert report["stats"]["copie_de_travail"]["ad_estimation"] == "reprise"
        assert verify(out2) == 0
        reader, pixel, _, _ = _pixel_reader(out2)
        try:
            assert pixel(SITE[0] + 0.02, SITE[1]) == (2, 0, (2 << 4) | 5, 255)
        finally:
            reader.close()

        # Sans copie de travail ni cellules : le pays est laissé de côté, la construction échoue faute de pays.
        code = cli.main(["--config", str(andorra["config"]), "build", "--scope", "andorre", "--services", "data", "--work", str(root / "work3"), "--out", str(root / "out3"), "--date", "2026-11-15"])
        assert code == 1
    finally:
        hidden.with_suffix(".absent").rename(hidden)


def test_cells_without_header_and_empty_country(andorra: dict, tmp_path: Path):
    remote = tmp_path / "distant"
    shutil.copytree(andorra["remote"], remote)
    (remote / "213.csv.gz").write_bytes(_cells(with_header=False))
    config = _config(tmp_path, remote, (remote / "{mcc}.csv.gz").as_uri().replace("%7B", "{").replace("%7D", "}"))
    out = tmp_path / "out"
    assert cli.main(["--config", str(config), "build", "--scope", "andorre", "--services", "data", "--work", str(tmp_path / "work"), "--out", str(out), "--date", "2026-11-14"]) == 0
    report = json.loads((out / "rapport-construction.json").read_text(encoding="utf-8"))
    assert report["stats"]["estimation_cellules"]["ad_estimation"]["retenues"] == 4

    # Un fichier valide mais sans cellule 4G ou 5G dans le pays : la source est inutilisable, le pays est retiré.
    (remote / "213.csv.gz").write_bytes(gzip.compress((HEADER + "\nGSM,213,3,100,77,,1.5,42.55,1000,90,1,1,1,0\n").encode()))
    assert cli.main(["--config", str(config), "build", "--scope", "andorre", "--services", "data", "--work", str(tmp_path / "work-b"), "--out", str(tmp_path / "out-b"), "--date", "2026-11-14"]) == 1


def test_sites_from_cells(andorra: dict):
    source = create_source("ad_estimation", load_config(andorra["config"]))
    lon, lat = SITE
    cells = [
        {"radio": "LTE", "net": 3, "cell": 1000 * 256 + 1, "lon": lon + 0.002, "lat": lat},
        {"radio": "LTE", "net": 3, "cell": 1000 * 256 + 2, "lon": lon - 0.002, "lat": lat},
        {"radio": "LTE", "net": 3, "cell": 1000 * 256 + 3, "lon": lon, "lat": lat + 0.004},
        # Station incohérente : deux « secteurs » à 8 km l'un de l'autre, traités séparément.
        {"radio": "LTE", "net": 3, "cell": 2000 * 256 + 1, "lon": lon + 0.05, "lat": lat},
        {"radio": "LTE", "net": 3, "cell": 2000 * 256 + 2, "lon": lon + 0.15, "lat": lat},
        # Petit identifiant : pas de station déductible.
        {"radio": "LTE", "net": 3, "cell": 17, "lon": lon, "lat": lat + 0.05},
    ]
    sites, stats = source.build_sites(cells)
    assert stats == {"stations": 2, "stations_dispersees": 1, "sites": 4}
    assert abs(sites[0][0] - lon) < 1e-9 and abs(sites[0][1] - lat) < 1e-9  # médiane des trois secteurs
    assert source.build_sites([]) == ([], {"stations": 0, "stations_dispersees": 0, "sites": 0})
    assert cluster_sites([(0, 0), (100, 0), (1000, 0), (1100, 50)], 300) == [(50.0, 0.0), (1050.0, 25.0)]


def test_download_link_is_read_from_the_page_and_the_token_never_leaks(andorra: dict, monkeypatch: pytest.MonkeyPatch):
    seen: dict[str, object] = {}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args: object) -> None:
            return

        def do_POST(self) -> None:
            seen["body"] = self.rfile.read(int(self.headers.get("Content-Length", "0"))).decode()
            page = '<a href="/ocid/downloads?token=SECRET123&amp;type=mcc&amp;file=213.csv.gz">Andorra</a> <a href="/ocid/downloads?token=SECRET123&amp;type=mcc&amp;file=2213.csv.gz">x</a>'
            self._send(page.encode(), "text/html")

        def do_GET(self) -> None:
            seen["get"] = self.path
            if "file=213.csv.gz" in self.path:
                self._send(_cells(), "application/gzip")
            else:
                self._send(b'{"status":"error","message":"INVALID_DATA"}', "application/json")

        def _send(self, raw: bytes, kind: str) -> None:
            self.send_response(200)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    monkeypatch.setenv("no_proxy", "127.0.0.1,localhost")
    monkeypatch.setenv("NO_PROXY", "127.0.0.1,localhost")
    monkeypatch.setenv("OPENCELLID_TOKEN", "SECRET123")
    base = f"http://127.0.0.1:{server.server_address[1]}"
    try:
        cfg = load_config(andorra["config"])
        del cfg["sources"]["ad_estimation"]["cells_url"]
        cfg["sources"]["ad_estimation"]["downloads_page"] = f"{base}/downloads.php"
        source = create_source("ad_estimation", cfg)
        assert source.available() == (True, "")
        assert source.cells_url(213) == f"{base}/ocid/downloads?token=SECRET123&type=mcc&file=213.csv.gz"
        assert seen["body"] == "token=SECRET123"
        with pytest.raises(SourceUnavailable) as failure:
            source.cells_url(999)
        assert "SECRET123" not in str(failure.value) and "token=***" in str(failure.value)
        assert source.mask("https://x/y?token=SECRET123&a=1 SECRET123") == "https://x/y?token=***&a=1 ***"

        # Réponse « 200 » qui n'est pas un fichier : la source est indisponible, sans que la clé apparaisse.
        cfg["sources"]["ad_estimation"]["cells_url"] = base + "/ocid/downloads?token={token}&type=mcc&file=bad{mcc}.csv.gz"
        from czb.context import BuildContext, grid_from_config

        ctx = BuildContext(cfg=cfg, scope_name="andorre", services=["data"], workdir=andorra["root"] / "work-lien", outdir=andorra["root"] / "out-lien", grid=grid_from_config(cfg))
        with pytest.raises(SourceUnavailable) as failure:
            create_source("ad_estimation", cfg).fetch_cells(ctx, 213)
        assert "INVALID_DATA" in str(failure.value) and "SECRET123" not in str(failure.value)

        monkeypatch.delenv("OPENCELLID_TOKEN")
        assert create_source("ad_estimation", cfg).available() == (False, "le secret OPENCELLID_TOKEN n'est pas défini")
    finally:
        server.shutdown()
        server.server_close()
