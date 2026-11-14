"""Suisse : atlas de la large bande de l'OFCOM (disponibilité des réseaux mobiles).

Source officielle agrégée : pour chaque carré de 100 m, le nombre d'opérateurs
(Swisscom, Sunrise, Salt) qui annoncent une couverture extérieure. Vérifié par
sonde (gdalinfo et lisez-moi de l'OFCOM) sur l'édition du 30 avril 2026 :

- catalogue STAC : https://data.geo.admin.ch/api/stac/v0.9/collections/ch.bakom.mobilnetz-4g/items ;
- un item, un GeoTIFF « mobilnetz-4g_2056.tif » : EPSG:2056 (CH1903+ / LV95),
  pixels de 100 m, Float32, NoData = NaN (hors de Suisse), bande « TECH4GOP » ;
- valeurs : 0 = pas de couverture, 2 = couvert par moins de 3 opérateurs,
  3 = couvert par les 3 opérateurs.

La source ne dit pas QUEL opérateur couvre. Les emplacements portent donc des
seuils : « au moins un opérateur » et « les trois opérateurs ». Il n'y a pas de
niveau de qualité : un carré est couvert ou non.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import TYPE_CHECKING, Any

from ..context import BuildContext
from ..grid import mercator_to_lonlat
from ..net import download, fetch_text
from ..witness import draw_country_pixels
from .base import Source

if TYPE_CHECKING:
    import numpy as np

# Un point témoin à moins de cette distance (en mètres) d'un bord de carré de la source est écarté :
# le résultat dépendrait d'un arrondi de reprojection.
WITNESS_MARGIN_M = 1.0
# Nombre de passes de comblement des carrés sans donnée collés à la frontière (une passe = 100 m).
FILL_PASSES = 2
NO_DATA = 255


class ChBakom(Source):
    id = "ch_bakom"

    def __init__(self, cfg: dict[str, Any], source_id: str | None = None):
        super().__init__(cfg, source_id)
        self._items: dict[str, dict[str, Any]] = {}

    # -- version en ligne ---------------------------------------------------

    def _item(self, collection: str) -> dict[str, Any]:
        """L'unique item de la collection STAC, avec son GeoTIFF."""
        if collection not in self._items:
            url = self.source_cfg["stac_url"].format(collection=collection)
            features = json.loads(fetch_text(url)).get("features", [])
            if len(features) != 1:
                raise RuntimeError(f"{collection} : {len(features)} item(s) STAC, 1 attendu")
            item = features[0]
            tiffs = [a for a in item.get("assets", {}).values() if str(a.get("href", "")).endswith(".tif")]
            if len(tiffs) != 1:
                raise RuntimeError(f"{collection} : {len(tiffs)} GeoTIFF dans l'item, 1 attendu")
            self._items[collection] = {
                "datetime": item["properties"].get("datetime"),
                "href": tiffs[0]["href"],
                "updated": tiffs[0].get("updated"),
                "epsg": tiffs[0].get("proj:epsg"),
            }
        return self._items[collection]

    def remote_state(self, services: list[str] | None = None) -> dict[str, Any]:
        services = services or list(self.source_cfg["services"])
        state = {}
        for service in services:
            collection = self.source_cfg["services"][service]["collection"]
            item = self._item(collection)
            state[collection] = {"datetime": item["datetime"], "updated": item["updated"]}
        return state

    # -- traitement ---------------------------------------------------------

    def process(self, ctx: BuildContext) -> dict[str, Any]:
        import numpy as np

        dates = []
        rng = np.random.default_rng(int(ctx.cfg["verification"]["seed"]) + self.country_code)
        for service in ctx.services:
            if service not in self.source_cfg["services"]:
                continue
            collection = self.source_cfg["services"][service]["collection"]
            item = self._item(collection)
            name = item["href"].rsplit("/", 1)[-1]
            print(f"  - {name} : {collection}, {service}", flush=True)
            tif = download(item["href"], ctx.workdir / name)
            try:
                self.rasterize_file(ctx, tif, service, rng)
            finally:
                tif.unlink(missing_ok=True)
            if item["datetime"]:
                dates.append(str(item["datetime"])[:10])
            ctx.layers.flush()
        if not dates:
            raise RuntimeError("ch_bakom : aucun service demandé n'est fourni par cette source")
        return {"date": max(dates)[:7], "data_date": max(dates)}

    def rasterize_file(self, ctx: BuildContext, tif: Path, service: str, rng: "np.random.Generator") -> None:
        import numpy as np
        from osgeo import gdal, osr

        from ..raster import split_window, warp_to_window

        canvas, layers = ctx.canvas, ctx.layers
        assert canvas is not None and layers is not None
        slots: list[dict[str, Any]] = self.country_cfg["slots"]
        value_to_count = {float(k): int(v) for k, v in self.source_cfg["values"].items()}
        covered_level = int(self.source_cfg["covered_level"])

        ds = gdal.Open(str(tif))
        if ds is None or ds.RasterCount != 1:
            raise RuntimeError(f"{tif.name} : un GeoTIFF à une bande est attendu")
        srs = osr.SpatialReference(wkt=ds.GetProjection())
        if srs.GetAuthorityCode(None) != "2056":
            raise RuntimeError(f"{tif.name} : SCR inattendu ({srs.GetAuthorityName(None)}:{srs.GetAuthorityCode(None)}), EPSG:2056 attendu")
        gt = ds.GetGeoTransform()
        if gt[2] != 0 or gt[4] != 0 or gt[5] >= 0:
            raise RuntimeError(f"{tif.name} : géotransformation inattendue {gt}")
        values = ds.GetRasterBand(1).ReadAsArray().astype(np.float32)
        valid = np.isfinite(values)
        found = sorted(set(np.unique(values[valid]).tolist()))
        unknown = [v for v in found if v not in value_to_count]
        if unknown:
            # On ne devine pas le sens d'une valeur nouvelle : on s'arrête.
            raise RuntimeError(f"{tif.name} : valeur(s) inconnue(s) {unknown} (attendu : {sorted(value_to_count)})")

        # Nombre minimal d'opérateurs par carré, NO_DATA hors de Suisse.
        count = np.full(values.shape, NO_DATA, dtype=np.uint8)
        for value, n in value_to_count.items():
            count[valid & (values == value)] = n
        count = _fill_edges(count, FILL_PASSES)
        print(f"    {int(valid.sum()):,} carrés de {abs(gt[1]):.0f} m, valeurs {found}".replace(",", " "), flush=True)

        # Fenêtre de la grille qui couvre le raster source.
        to_merc = osr.CoordinateTransformation(_gis(srs), _gis_epsg(3857))
        h, w = count.shape
        xs, ys = [], []
        for cx, cy in ((0, 0), (w, 0), (w, h), (0, h), (w / 2, 0), (w / 2, h), (0, h / 2), (w, h / 2)):
            x, y, _ = to_merc.TransformPoint(gt[0] + cx * gt[1], gt[3] + cy * gt[5])
            xs.append(x)
            ys.append(y)
        full = canvas.window_for_envelope(min(xs), max(xs), min(ys), max(ys))
        if full is None:
            print("    hors de la grille : rien à faire", flush=True)
            return

        witnesses = self._witness_candidates(ctx, srs, gt, count.shape, rng)
        missing = 0
        for slot_index, slot in enumerate(slots):
            threshold = int(slot["min_operators"])
            level = np.where(count == NO_DATA, NO_DATA, np.where(count >= threshold, covered_level, 0)).astype(np.uint8)
            for win in split_window(full):
                inside = layers.country_mask(win, self.country_code)
                if not inside.any():
                    continue
                warped = warp_to_window(level, gt, ds.GetProjection(), canvas, win, NO_DATA)
                if slot_index == 0:
                    missing += int((inside & (warped == NO_DATA)).sum())
                warped[warped == NO_DATA] = 0
                layers.merge_level(service, slot_index, win, warped, self.country_code)
            self._collect_witnesses(ctx, witnesses, level, service, slot_index, slot)
        ctx.stats.setdefault("pixels_sans_donnee", {})[f"{self.source_id}:{service}"] = missing
        if missing:
            print(f"    {missing:,} pixels du pays sans donnée dans la source (comptés comme non couverts)".replace(",", " "), flush=True)

    # -- points témoins -------------------------------------------------------

    def _witness_candidates(self, ctx: BuildContext, srs: Any, gt: tuple, shape: tuple[int, int], rng: "np.random.Generator") -> list[dict[str, Any]]:
        """Pixels tirés au hasard dans le pays, avec le carré de la source qui contient leur centre."""
        import numpy as np

        from ..raster import transformer_from_mercator

        canvas, layers = ctx.canvas, ctx.layers
        assert canvas is not None and layers is not None
        from_merc = transformer_from_mercator(srs)
        wanted = int(ctx.cfg["verification"]["candidates_per_file"])
        h, w = shape
        out: list[dict[str, Any]] = []
        attempts = 0
        while len(out) < wanted and attempts < 400:
            attempts += 1
            for col, row in zip(*draw_country_pixels(ctx, self.country_code, rng, wanted * 4)):
                x, y = canvas.pixel_center(col, row)
                sx, sy, _ = from_merc.TransformPoint(x, y)
                fc = (sx - gt[0]) / gt[1]
                fr = (sy - gt[3]) / gt[5]
                c, r = int(np.floor(fc)), int(np.floor(fr))
                if not (0 <= c < w and 0 <= r < h):
                    continue
                margin = WITNESS_MARGIN_M / abs(gt[1])
                if min(fc - c, c + 1 - fc, fr - r, r + 1 - fr) < margin:
                    continue  # trop près d'un bord de carré
                out.append({"col": col, "row": row, "x": x, "y": y, "c": c, "r": r})
                if len(out) >= wanted:
                    break
        return out

    def _collect_witnesses(self, ctx: BuildContext, candidates: list[dict[str, Any]], level: "np.ndarray", service: str, slot_index: int, slot: dict[str, Any]) -> None:
        """Niveau attendu lu directement dans la grille de la source, puis échantillon équilibré."""
        canvas = ctx.canvas
        assert canvas is not None
        keep_total = int(ctx.cfg["verification"]["points_per_file"])
        by_level: dict[int, list[dict[str, Any]]] = {}
        for cand in candidates:
            value = int(level[cand["r"], cand["c"]])
            if value == NO_DATA:
                continue
            by_level.setdefault(value, []).append(cand)
        kept: list[tuple[int, dict[str, Any]]] = []
        while len(kept) < keep_total and any(by_level.values()):
            for value in sorted(by_level):
                if by_level[value] and len(kept) < keep_total:
                    kept.append((value, by_level[value].pop()))
        for value, cand in kept:
            tx, ty, px, py = canvas.tile_and_pixel(cand["col"], cand["row"])
            lon, lat = mercator_to_lonlat(cand["x"], cand["y"])
            ctx.witnesses.append(
                {
                    "source": self.source_id,
                    "country": self.country_iso,
                    "service": service,
                    "slot": slot_index,
                    "operator": slot["id"],
                    "z": canvas.grid.zoom,
                    "x": tx,
                    "y": ty,
                    "px": px,
                    "py": py,
                    "lon": round(lon, 6),
                    "lat": round(lat, 6),
                    "expected": value,
                }
            )
        counts = {v: sum(1 for value, _ in kept if value == v) for v in sorted({value for value, _ in kept})}
        print(f"    points témoins ({slot['id']}) : {len(kept)} retenus, par niveau {counts}", flush=True)


def _gis(srs: Any) -> Any:
    out = srs.Clone()
    from osgeo import osr

    out.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return out


def _gis_epsg(code: int) -> Any:
    from osgeo import osr

    srs = osr.SpatialReference()
    srs.ImportFromEPSG(code)
    srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return srs


def _fill_edges(count: "np.ndarray", passes: int) -> "np.ndarray":
    """Comble les carrés sans donnée collés à des carrés renseignés (bord de frontière).

    Chaque passe donne à un carré vide la plus PETITE valeur de ses 8 voisins
    renseignés : dans le doute, on annonce le moins de couverture.
    """
    import numpy as np

    out = count.copy()
    for _ in range(passes):
        padded = np.pad(out, 1, constant_values=NO_DATA)
        best = np.full(out.shape, NO_DATA, dtype=np.uint8)
        h, w = out.shape
        for dy in (0, 1, 2):
            for dx in (0, 1, 2):
                if dy == 1 and dx == 1:
                    continue
                best = np.minimum(best, padded[dy : dy + h, dx : dx + w])
        fill = (out == NO_DATA) & (best != NO_DATA)
        out[fill] = best[fill]
    return out
