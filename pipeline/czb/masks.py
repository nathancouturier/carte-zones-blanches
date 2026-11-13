"""Masques de pays : quels pixels de la grille appartiennent à quel pays."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from osgeo import ogr

from .context import BuildContext
from .grid import Canvas
from .net import download, gunzip
from .raster import geometry_windows, transformer_to_mercator


def _load_etalab_departements(mask_cfg: dict[str, Any], scope: dict[str, Any], workdir: Path) -> list[ogr.Geometry]:
    """Contours des départements (Etalab). Champs utilisés : code, nom."""
    url = mask_cfg["url"]
    local = workdir / "departements.geojson"
    if not local.exists():
        if url.endswith(".gz"):
            gz = download(url, workdir / "departements.geojson.gz")
            gunzip(gz, local)
            gz.unlink(missing_ok=True)
        else:
            download(url, local)
    ds = ogr.Open(str(local))
    if ds is None:
        raise RuntimeError(f"impossible d'ouvrir {local}")
    layer = ds.GetLayer(0)
    names = [layer.GetLayerDefn().GetFieldDefn(i).GetName() for i in range(layer.GetLayerDefn().GetFieldCount())]
    if "code" not in names:
        raise RuntimeError(f"contours des départements : champ « code » absent (champs : {names})")
    wanted = scope.get("departements")
    to_merc = transformer_to_mercator(layer.GetSpatialRef())
    geoms: list[ogr.Geometry] = []
    found: set[str] = set()
    for feat in layer:
        code = feat.GetField("code")
        if mask_cfg.get("metropole_only") and len(code) != 2:
            continue  # outre-mer : codes à 3 caractères
        if wanted is not None and code not in wanted:
            continue
        geom = feat.GetGeometryRef().Clone()
        geom.Transform(to_merc)
        geoms.append(geom)
        found.add(code)
    if wanted is not None and set(wanted) - found:
        raise RuntimeError(f"départements introuvables : {sorted(set(wanted) - found)}")
    if not geoms:
        raise RuntimeError("aucun département retenu pour le masque de la France")
    return geoms


def _load_vector_file(mask_cfg: dict[str, Any], scope: dict[str, Any], workdir: Path) -> list[ogr.Geometry]:
    """Masque générique : un fichier vecteur (local ou distant), avec un filtre attributaire facultatif."""
    url = mask_cfg["url"]
    name = mask_cfg.get("filename") or url.rsplit("/", 1)[-1]
    local = workdir / name
    if not local.exists():
        download(url, local)
    ds = ogr.Open(str(local))
    if ds is None:
        raise RuntimeError(f"impossible d'ouvrir {local}")
    layer = ds.GetLayerByName(mask_cfg["layer"]) if mask_cfg.get("layer") else ds.GetLayer(0)
    if mask_cfg.get("where"):
        layer.SetAttributeFilter(mask_cfg["where"])
    to_merc = transformer_to_mercator(layer.GetSpatialRef())
    geoms = []
    for feat in layer:
        geom = feat.GetGeometryRef()
        if geom is None:
            continue
        geom = geom.Clone()
        geom.Transform(to_merc)
        geoms.append(geom)
    if not geoms:
        raise RuntimeError(f"masque vide pour {url}")
    return geoms


LOADERS = {
    "etalab_departements": _load_etalab_departements,
    "vector_file": _load_vector_file,
}


def load_mask_geometries(ctx: BuildContext) -> dict[str, list[ogr.Geometry]]:
    """Charge, pour chaque pays du périmètre, les polygones de son masque en EPSG:3857."""
    result: dict[str, list[ogr.Geometry]] = {}
    for iso in ctx.countries:
        mask_cfg = ctx.cfg["countries"][iso]["mask"]
        loader = LOADERS.get(mask_cfg["type"])
        if loader is None:
            raise ValueError(f"type de masque inconnu : {mask_cfg['type']}")
        result[iso] = loader(mask_cfg, ctx.scope, ctx.workdir)
        print(f"   masque {iso} : {len(result[iso])} polygone(s)", flush=True)
    return result


def canvas_for_geometries(ctx: BuildContext, geoms: dict[str, list[ogr.Geometry]]) -> Canvas:
    minx = miny = float("inf")
    maxx = maxy = float("-inf")
    for items in geoms.values():
        for g in items:
            x0, x1, y0, y1 = g.GetEnvelope()
            minx, maxx = min(minx, x0), max(maxx, x1)
            miny, maxy = min(miny, y0), max(maxy, y1)
    return ctx.grid.canvas_for_mercator_bounds(minx, miny, maxx, maxy)


def rasterize_masks(ctx: BuildContext, geoms: dict[str, list[ogr.Geometry]]) -> None:
    """Remplit le canal B : code du pays et type de source par défaut du pays."""
    assert ctx.canvas is not None and ctx.layers is not None
    for iso in ctx.countries:
        country = ctx.cfg["countries"][iso]
        default_type = int(ctx.cfg["sources"][country["sources"][-1]]["type"])
        gained = 0
        for geom in geoms[iso]:
            for win, mask in geometry_windows(geom, ctx.canvas):
                gained += ctx.layers.claim_country(win, mask, int(country["code"]), default_type)
        ctx.stats.setdefault("pixels_par_pays", {})[iso] = gained
        print(f"   {iso} : {gained:,} pixels".replace(",", " "), flush=True)
