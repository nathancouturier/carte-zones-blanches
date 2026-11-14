"""Rastérisation de géométries sur la grille (GDAL)."""

from __future__ import annotations

from typing import Iterator

import numpy as np
from osgeo import gdal, ogr, osr

from .grid import Canvas
from .layers import Window

gdal.UseExceptions()
ogr.UseExceptions()
osr.UseExceptions()

MAX_CHUNK = 8192  # côté maximal d'une fenêtre rastérisée d'un coup, en pixels


def srs_from_epsg(epsg: int) -> osr.SpatialReference:
    srs = osr.SpatialReference()
    srs.ImportFromEPSG(epsg)
    # Ordre des axes « SIG » (x = est ou longitude, y = nord ou latitude) quel que soit le SCR.
    srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return srs


_MERCATOR: osr.SpatialReference | None = None


def mercator_srs() -> osr.SpatialReference:
    global _MERCATOR
    if _MERCATOR is None:
        _MERCATOR = srs_from_epsg(3857)
    return _MERCATOR


def transformer_to_mercator(source_srs: osr.SpatialReference) -> osr.CoordinateTransformation:
    src = source_srs.Clone()
    src.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return osr.CoordinateTransformation(src, mercator_srs())


def transformer_from_mercator(target_srs: osr.SpatialReference) -> osr.CoordinateTransformation:
    dst = target_srs.Clone()
    dst.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return osr.CoordinateTransformation(mercator_srs(), dst)


def _memory_vector() -> ogr.DataSource:
    # « Memory » jusqu'à GDAL 3.10, « MEM » ensuite.
    for name in ("Memory", "MEM"):
        driver = ogr.GetDriverByName(name)
        if driver is None:
            continue
        try:
            ds = driver.CreateDataSource("")
        except RuntimeError:
            continue
        if ds is not None:
            return ds
    raise RuntimeError("aucun pilote vecteur en mémoire disponible dans GDAL")


def split_window(win: Window, max_side: int = MAX_CHUNK) -> Iterator[Window]:
    col0, row0, w, h = win
    for r in range(row0, row0 + h, max_side):
        for c in range(col0, col0 + w, max_side):
            yield c, r, min(max_side, col0 + w - c), min(max_side, row0 + h - r)


def rasterize_geometry(geom: ogr.Geometry, canvas: Canvas, win: Window) -> np.ndarray:
    """Rastérise une géométrie (déjà en EPSG:3857) dans une fenêtre de la grille.

    Un pixel est allumé si son centre est dans la géométrie (règle par défaut de GDAL).
    """
    col0, row0, w, h = win
    raster = gdal.GetDriverByName("MEM").Create("", w, h, 1, gdal.GDT_Byte)
    raster.SetGeoTransform(canvas.geotransform(col0, row0))
    raster.SetProjection(mercator_srs().ExportToWkt())
    vector = _memory_vector()
    layer = vector.CreateLayer("g", mercator_srs(), ogr.wkbUnknown)
    feature = ogr.Feature(layer.GetLayerDefn())
    feature.SetGeometry(geom)
    layer.CreateFeature(feature)
    gdal.RasterizeLayer(raster, [1], layer, burn_values=[1])
    return raster.GetRasterBand(1).ReadAsArray().astype(bool)


def geometry_windows(geom: ogr.Geometry, canvas: Canvas) -> Iterator[tuple[Window, np.ndarray]]:
    """Découpe l'emprise de la géométrie en fenêtres et renvoie le masque rastérisé de chacune."""
    minx, maxx, miny, maxy = geom.GetEnvelope()
    full = canvas.window_for_envelope(minx, maxx, miny, maxy)
    if full is None:
        return
    for win in split_window(full):
        mask = rasterize_geometry(geom, canvas, win)
        if mask.any():
            yield win, mask


def warp_to_window(
    array: np.ndarray,
    geotransform: tuple[float, float, float, float, float, float],
    projection_wkt: str,
    canvas: Canvas,
    win: Window,
    nodata: int,
) -> np.ndarray:
    """Ramène un raster d'octets (dans son SCR d'origine) sur une fenêtre de la grille, en plus proche voisin.

    Chaque pixel de la grille prend la valeur du pixel source qui contient son centre.
    Les pixels sans correspondance valent « nodata ».
    """
    h, w = array.shape
    source = gdal.GetDriverByName("MEM").Create("", w, h, 1, gdal.GDT_Byte)
    source.SetGeoTransform(geotransform)
    source.SetProjection(projection_wkt)
    band = source.GetRasterBand(1)
    band.WriteArray(np.ascontiguousarray(array, dtype=np.uint8))
    band.SetNoDataValue(nodata)
    col0, row0, ww, hh = win
    target = gdal.GetDriverByName("MEM").Create("", ww, hh, 1, gdal.GDT_Byte)
    target.SetGeoTransform(canvas.geotransform(col0, row0))
    target.SetProjection(mercator_srs().ExportToWkt())
    out_band = target.GetRasterBand(1)
    out_band.SetNoDataValue(nodata)
    out_band.Fill(nodata)
    gdal.Warp(target, source, resampleAlg="near")
    return target.GetRasterBand(1).ReadAsArray()
