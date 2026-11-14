"""Copies de travail : résultat intermédiaire d'une source, gardé d'une construction à l'autre.

Certaines sources coûtent cher à relire (un millier de requêtes pour l'Espagne)
ou limitent les téléchargements (OpenCellID : deux par jour). Leur résultat,
ramené à une image compacte, est publié avec les données sous le nom
cache-<source>.tif. La construction suivante le retrouve dans work/cache/ et
s'en sert tant que sa clé (édition en ligne, emprise, paramètres) n'a pas changé.
"""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import numpy as np

KEY_ITEM = "CZB_CLE"


def cache_name(source_id: str) -> str:
    return f"cache-{source_id}.tif"


def read_cache(path: Path, key: str) -> "np.ndarray | None":
    """Tableau (bandes, lignes, colonnes) de la copie de travail si sa clé est la bonne, sinon None."""
    from osgeo import gdal

    if not path.exists():
        return None
    try:
        ds = gdal.Open(str(path))
    except RuntimeError:
        return None
    if ds is None or ds.GetMetadataItem(KEY_ITEM) != key:
        return None
    data = ds.ReadAsArray()
    return data[None, ...] if data.ndim == 2 else data


def write_cache(path: Path, bands: "np.ndarray", geotransform: tuple, epsg: int, key: str, description: str) -> None:
    """Écrit un tableau d'octets (bandes, lignes, colonnes) en GeoTIFF compressé, avec sa clé."""
    from osgeo import gdal, osr

    if bands.ndim == 2:
        bands = bands[None, ...]
    srs = osr.SpatialReference()
    srs.ImportFromEPSG(epsg)
    path.parent.mkdir(parents=True, exist_ok=True)
    ds = gdal.GetDriverByName("GTiff").Create(str(path), bands.shape[2], bands.shape[1], bands.shape[0], gdal.GDT_Byte, options=["COMPRESS=DEFLATE", "ZLEVEL=9", "TILED=YES", "BIGTIFF=IF_SAFER"])
    ds.SetGeoTransform(geotransform)
    ds.SetProjection(srs.ExportToWkt())
    ds.SetMetadataItem(KEY_ITEM, key)
    ds.SetMetadataItem("CZB_CONTENU", description)
    for index in range(bands.shape[0]):
        ds.GetRasterBand(index + 1).WriteArray(bands[index])
    ds = None


def cache_geotransform(path: Path) -> tuple[float, float, float, float, float, float]:
    """Géotransformation enregistrée dans une copie de travail (son calage exact sur le terrain)."""
    from osgeo import gdal

    ds = gdal.Open(str(path))
    return tuple(ds.GetGeoTransform())  # type: ignore[return-value]
