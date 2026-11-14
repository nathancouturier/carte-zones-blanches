"""Espagne : « Mapa de Servicios de Banda Ancha Móvil » du ministère (SETELECO), couverture 4G.

Source officielle par opérateur, binaire : pour chaque maille, la liste des
opérateurs dont le réseau 4G est présent, sans niveau de qualité. Vérifié par
sonde sur l'édition 2024 (situation au 30 juin 2024) :

- couche d'entités publique d'ArcGIS Online, polygones en EPSG:4258 formés de
  mailles d'une grille de 0,000346111018645788° (environ 28 m sur 38 m) ;
- champ COBERTURA : identifiants fiscaux (CIF) des opérateurs présents, séparés
  par « ; », dans un ordre quelconque ; chaîne vide = partie de la commune sans 4G ;
- champ CCOM : code de la communauté autonome (02 Aragón, 09 Cataluña,
  15 Navarra, 16 País Vasco). Les entités sans commune (CCOM vide : mer, versants
  français et andorran) ne sont pas lues ;
- 2 000 entités par page au plus, pagination par OBJECTID croissant ;
- réutilisation autorisée par les conditions générales du site du ministère, en
  citant la source et la date.

Les quatre régions comptent environ 2,1 millions de polygones, soit un bon
millier de requêtes. Pour ne pas les refaire à chaque construction, le résultat
est gardé sous la forme d'une image à la maille d'origine (« copie de travail »,
un bit par opérateur), publiée avec les données : tant que l'édition en ligne ne
change pas, la construction suivante repart de cette image.
"""

from __future__ import annotations

import json
import math
import shutil
from pathlib import Path
from typing import TYPE_CHECKING, Any

from .. import arcgis
from ..cache import cache_name, read_cache, write_cache
from ..context import BuildContext
from ..grid import mercator_to_lonlat
from ..witness import draw_country_pixels
from .base import Source

if TYPE_CHECKING:
    import numpy as np

CACHE_FORMAT = 1
NO_DATA = 255
#: Un point témoin à moins de cette fraction de maille d'un bord de maille est écarté.
WITNESS_MARGIN = 0.03
#: Contrôle de la copie de travail contre les polygones : nombre de points tirés par région et part d'écarts tolérée
#: (les mailles coupées par une limite de commune ou de région ne sont pas des carrés entiers).
CHECK_POINTS = 400
CHECK_TOLERANCE = 0.01


class EsMtd(Source):
    id = "es_mtd"

    def __init__(self, cfg: dict[str, Any], source_id: str | None = None):
        super().__init__(cfg, source_id)
        self._layer_info: dict[str, Any] | None = None
        self.bit_of_cif: dict[str, int] = {}
        for index, slot in enumerate(self.country_cfg["slots"]):
            if "cif" not in slot:
                raise ValueError(f"{self.source_id} : l'opérateur {slot.get('id')} n'a pas d'identifiant « cif » dans config.yaml")
            self.bit_of_cif[str(slot["cif"])] = 1 << index

    # -- version en ligne ---------------------------------------------------

    @property
    def query_url(self) -> str:
        return self.source_cfg["layer_url"].rstrip("/") + "/query"

    def where(self, region: str) -> str:
        cfg = self.source_cfg
        return f"{cfg['region_field']}='{region}' AND {cfg['operator_field']}<>''"

    def layer_info(self) -> dict[str, Any]:
        """Description de la couche. On vérifie le schéma : s'il a changé, on s'arrête plutôt que de deviner."""
        if self._layer_info is None:
            cfg = self.source_cfg
            info = arcgis.get_json(cfg["layer_url"])
            fields = {f.get("name") for f in info.get("fields") or []}
            needed = {cfg["oid_field"], cfg["operator_field"], cfg["region_field"]}
            if not needed <= fields:
                raise RuntimeError(f"{self.source_id} : champs absents de la couche : {sorted(needed - fields)} (champs : {sorted(f for f in fields if f)})")
            # Le SCR annoncé par la couche, s'il est présent (celui de chaque réponse est de toute façon vérifié à la lecture).
            for holder in ((info.get("extent") or {}).get("spatialReference"), info.get("sourceSpatialReference"), info.get("spatialReference")):
                if holder and (holder.get("latestWkid") or holder.get("wkid")) not in (None, 4258):
                    raise RuntimeError(f"{self.source_id} : SCR inattendu de la couche ({holder}), EPSG:4258 attendu")
            self._layer_info = info
        return self._layer_info

    def remote_state(self, services: list[str] | None = None) -> dict[str, Any]:
        info = self.layer_info()
        editing = info.get("editingInfo") or {}
        state: dict[str, Any] = {
            "couche": info.get("name"),
            "dataLastEditDate": editing.get("dataLastEditDate"),
            "regions": {str(r): arcgis.count(self.query_url, self.where(str(r))) for r in self.source_cfg["regions"]},
        }
        if self.source_cfg.get("item_url"):
            state["modified"] = arcgis.get_json(self.source_cfg["item_url"]).get("modified")
        return state

    # -- grille d'origine ---------------------------------------------------

    def native_window(self, ctx: BuildContext) -> tuple[int, int, int, int]:
        """Fenêtre (col0, row0, colonnes, lignes) de la grille de la source qui couvre le pays."""
        assert ctx.layers is not None
        extent = ctx.layers.country_extent(self.country_code)
        if extent is None:
            raise RuntimeError(f"{self.source_id} : le pays {self.country_iso} n'a aucun pixel sur la grille")
        step = float(self.source_cfg["grid_step_deg"])
        x0, y0 = (float(v) for v in self.source_cfg["grid_origin"])
        west, south = mercator_to_lonlat(extent[0], extent[1])
        east, north = mercator_to_lonlat(extent[2], extent[3])
        col0 = math.floor((west - x0) / step) - 2
        col1 = math.ceil((east - x0) / step) + 2
        row0 = math.floor((y0 - north) / step) - 2
        row1 = math.ceil((y0 - south) / step) + 2
        return col0, row0, col1 - col0, row1 - row0

    def geotransform(self, window: tuple[int, int, int, int]) -> tuple[float, float, float, float, float, float]:
        step = float(self.source_cfg["grid_step_deg"])
        x0, y0 = (float(v) for v in self.source_cfg["grid_origin"])
        return (x0 + window[0] * step, step, 0.0, y0 - window[1] * step, 0.0, -step)

    # -- copie de travail ----------------------------------------------------

    def cache_key(self, state: dict[str, Any], window: tuple[int, int, int, int]) -> str:
        """Tout ce dont dépend la copie de travail : l'édition en ligne, la fenêtre, les opérateurs."""
        cfg = self.source_cfg
        return json.dumps(
            {
                "format": CACHE_FORMAT,
                "etat": state,
                "fenetre": list(window),
                "grille": [cfg["grid_step_deg"], list(cfg["grid_origin"])],
                "operateurs": self.bit_of_cif,
            },
            sort_keys=True,
            ensure_ascii=False,
        )

    # -- téléchargement ------------------------------------------------------

    def bits_of(self, coverage: str) -> int:
        bits = 0
        for cif in str(coverage).split(self.source_cfg.get("operator_separator", ";")):
            cif = cif.strip()
            if not cif:
                continue
            if cif not in self.bit_of_cif:
                # Un opérateur inconnu : on ne devine pas dans quel emplacement le ranger.
                raise RuntimeError(f"{self.source_id} : identifiant d'opérateur inconnu « {cif} » (connus : {sorted(self.bit_of_cif)})")
            bits |= self.bit_of_cif[cif]
        return bits

    def download(self, ctx: BuildContext, window: tuple[int, int, int, int], state: dict[str, Any]) -> "np.ndarray":
        """Lit les polygones région par région et les rastérise à la maille d'origine."""
        import numpy as np
        from osgeo import gdal, ogr, osr

        from ..raster import polygonal

        cfg = self.source_cfg
        oid_field, operator_field = cfg["oid_field"], cfg["operator_field"]
        step = float(cfg["grid_step_deg"])
        gt = self.geotransform(window)
        srs = osr.SpatialReference()
        srs.ImportFromEPSG(4258)
        srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
        bits = np.zeros((window[3], window[2]), dtype=np.uint8)
        workdir = ctx.workdir / self.source_id
        workdir.mkdir(parents=True, exist_ok=True)
        rng = np.random.default_rng(int(ctx.cfg["verification"]["seed"]) + 40)
        for region in (str(r) for r in cfg["regions"]):
            expected = int(state["regions"][region])
            print(f"  - région {region} : {expected:,} polygones attendus".replace(",", " "), flush=True)
            gpkg = workdir / f"region-{region}.gpkg"
            gpkg.unlink(missing_ok=True)
            vds = ogr.GetDriverByName("GPKG").CreateDataSource(str(gpkg))
            layer = vds.CreateLayer("couverture", srs, ogr.wkbMultiPolygon)
            layer.CreateField(ogr.FieldDefn("bits", ogr.OFTInteger))
            defn = layer.GetLayerDefn()
            count = page_index = 0
            minx = miny = float("inf")
            maxx = maxy = float("-inf")
            pages = arcgis.pages(self.query_url, self.where(region), [oid_field, operator_field], oid_field, int(cfg.get("page_size", 2000)), workdir, pause_s=float(cfg.get("pause_s", 0.5)), expected=expected)
            for page in pages:
                ds = ogr.Open(str(page))
                if ds is None:
                    raise RuntimeError(f"{self.source_id} : page illisible ({page.name})")
                src = ds.GetLayer(0)
                page_srs = src.GetSpatialRef()
                if page_srs is None or page_srs.GetAuthorityCode(None) != "4258":
                    raise RuntimeError(f"{self.source_id} : SCR inattendu dans la réponse ({page_srs.GetAuthorityCode(None) if page_srs else None}), EPSG:4258 attendu")
                layer.StartTransaction()
                for feat in src:
                    value = self.bits_of(feat.GetField(operator_field) or "")
                    geom = polygonal(feat.GetGeometryRef())
                    if value == 0 or geom is None:
                        continue
                    out = ogr.Feature(defn)
                    out.SetField("bits", value)
                    out.SetGeometry(ogr.ForceToMultiPolygon(geom.Clone()))
                    layer.CreateFeature(out)
                    x0, x1, y0, y1 = geom.GetEnvelope()
                    minx, maxx, miny, maxy = min(minx, x0), max(maxx, x1), min(miny, y0), max(maxy, y1)
                    count += 1
                layer.CommitTransaction()
                ds = None
                page_index += 1
                if page_index % 100 == 0:
                    print(f"    {page_index} pages lues, {count:,} polygones".replace(",", " "), flush=True)
            if count == 0:
                raise RuntimeError(f"{self.source_id} : aucun polygone pour la région {region}")
            # Fenêtre de la région dans la grille d'origine, limitée à la fenêtre du pays.
            c0 = max(0, math.floor((minx - gt[0]) / step) - 1)
            c1 = min(window[2], math.ceil((maxx - gt[0]) / step) + 1)
            r0 = max(0, math.floor((gt[3] - maxy) / step) - 1)
            r1 = min(window[3], math.ceil((gt[3] - miny) / step) + 1)
            if c1 <= c0 or r1 <= r0:
                raise RuntimeError(f"{self.source_id} : la région {region} est hors de l'emprise du pays")
            region_bits = np.zeros((r1 - r0, c1 - c0), dtype=np.uint8)
            region_gt = (gt[0] + c0 * step, step, 0.0, gt[3] - r0 * step, 0.0, -step)
            for bit in sorted(set(self.bit_of_cif.values())):
                # Un passage par opérateur : si deux polygones se recouvrent, aucun opérateur n'est perdu.
                layer.SetAttributeFilter(f"(bits & {bit}) <> 0")
                target = gdal.GetDriverByName("MEM").Create("", c1 - c0, r1 - r0, 1, gdal.GDT_Byte)
                target.SetGeoTransform(region_gt)
                target.SetProjection(srs.ExportToWkt())
                gdal.RasterizeLayer(target, [1], layer, burn_values=[1])
                region_bits |= (target.GetRasterBand(1).ReadAsArray() * np.uint8(bit)).astype(np.uint8)
                target = None
            layer.SetAttributeFilter(None)
            self._check_region(layer, region_bits, region_gt, rng, region)
            bits[r0:r1, c0:c1] |= region_bits
            print(f"    région {region} : {count:,} polygones, {int((region_bits != 0).sum()):,} mailles couvertes par au moins un réseau".replace(",", " "), flush=True)
            vds = None
            gpkg.unlink(missing_ok=True)
        shutil.rmtree(workdir, ignore_errors=True)
        return bits

    def _check_region(self, layer: Any, region_bits: "np.ndarray", gt: tuple, rng: "np.random.Generator", region: str) -> None:
        """Compare la copie de travail aux polygones en des points tirés au hasard (test géométrique exact)."""
        import numpy as np
        from osgeo import ogr

        # Moitié des points dans des mailles couvertes, moitié n'importe où dans la fenêtre.
        cells: list[tuple[int, int]] = []
        for _ in range(40):
            rows = rng.integers(0, region_bits.shape[0], size=CHECK_POINTS * 4)
            cols = rng.integers(0, region_bits.shape[1], size=CHECK_POINTS * 4)
            hit = region_bits[rows, cols] != 0
            cells += list(zip(rows[hit].tolist(), cols[hit].tolist()))
            if len(cells) >= CHECK_POINTS // 2:
                break
        if not cells:
            raise RuntimeError(f"{self.source_id} : région {region}, aucune maille couverte après rastérisation")
        cells = cells[: CHECK_POINTS // 2]
        cells += list(zip(rng.integers(0, region_bits.shape[0], size=CHECK_POINTS // 2).tolist(), rng.integers(0, region_bits.shape[1], size=CHECK_POINTS // 2).tolist()))
        offsets = rng.uniform(0.05, 0.95, size=(len(cells), 2))
        compared = mismatches = 0
        for (row, col), (fx, fy) in zip(cells, offsets.tolist()):
            x = gt[0] + (col + fx) * gt[1]
            y = gt[3] + (row + fy) * gt[5]
            point = ogr.Geometry(ogr.wkbPoint)
            point.AddPoint_2D(x, y)
            layer.SetSpatialFilter(point)
            expected = 0
            for feat in layer:
                if feat.GetGeometryRef().Contains(point):
                    expected |= int(feat.GetField("bits"))
            got = int(region_bits[row, col])
            if expected or got:
                compared += 1
                if expected != got:
                    mismatches += 1
        layer.SetSpatialFilter(None)
        print(f"    contrôle des polygones contre la grille d'origine : {compared} points couverts comparés, {mismatches} écart(s)", flush=True)
        if compared < min(CHECK_POINTS // 4, len(cells) // 4) or mismatches > max(1, int(CHECK_TOLERANCE * compared)):
            raise RuntimeError(f"{self.source_id} : région {region}, la grille d'origine ne correspond pas aux polygones ({mismatches} écarts sur {compared} points) : le pas ou l'origine de la grille ont changé")

    # -- traitement ---------------------------------------------------------

    def process(self, ctx: BuildContext) -> dict[str, Any]:
        import numpy as np
        from osgeo import osr

        from ..raster import split_window, warp_to_window

        canvas, layers = ctx.canvas, ctx.layers
        assert canvas is not None and layers is not None
        cfg = self.source_cfg
        services = [s for s in ctx.services if s in cfg["services"]]
        if not services:
            raise RuntimeError(f"{self.source_id} : aucun service demandé n'est fourni par cette source")
        service = services[0]
        covered = int(cfg["covered_level"])
        slots: list[dict[str, Any]] = self.country_cfg["slots"]

        state = self.remote_state()
        window = self.native_window(ctx)
        key = self.cache_key(state, window)
        cached = ctx.workdir / "cache" / cache_name(self.source_id)
        stored = read_cache(cached, key)
        bits = stored[0] if stored is not None else None
        reused = bits is not None
        if bits is not None:
            print(f"  - édition inchangée : copie de travail reprise ({cached.name}, {bits.shape[1]} x {bits.shape[0]} mailles)", flush=True)
        else:
            reason = "absente" if not cached.exists() else "d'une autre édition"
            print(f"  - copie de travail {reason} : lecture du service du ministère", flush=True)
            bits = self.download(ctx, window, state)
        # La copie de travail part avec les données publiées : la prochaine construction la reprendra.
        write_cache(ctx.outdir / cache_name(self.source_id), bits, self.geotransform(window), 4258, key, "bit i = opérateur de l'emplacement i présent en 4G ; 0 = aucun réseau ou hors des régions")
        ctx.stats.setdefault("copie_de_travail", {})[self.source_id] = "reprise" if reused else "reconstruite"

        gt = self.geotransform(window)
        srs = osr.SpatialReference()
        srs.ImportFromEPSG(4258)
        srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
        extent = layers.country_extent(self.country_code)
        assert extent is not None
        full = canvas.window_for_envelope(extent[0], extent[2], extent[1], extent[3])
        rng = np.random.default_rng(int(ctx.cfg["verification"]["seed"]) + self.country_code)
        candidates = self._witness_candidates(ctx, srs, gt, bits.shape, rng)
        for slot_index, slot in enumerate(slots):
            level = np.where((bits & (1 << slot_index)) != 0, covered, 0).astype(np.uint8)
            if full is not None:
                for win in split_window(full):
                    if not layers.country_mask(win, self.country_code).any():
                        continue
                    warped = warp_to_window(level, gt, srs.ExportToWkt(), canvas, win, NO_DATA)
                    warped[warped == NO_DATA] = 0
                    layers.merge_level(service, slot_index, win, warped, self.country_code)
            share = float((level != 0).mean()) * 100
            print(f"    {slot['name']} : présent sur {share:.1f} % des mailles de l'emprise", flush=True)
            self._collect_witnesses(ctx, candidates, level, service, slot_index, slot)
        layers.flush()
        data_date = str(cfg["data_date"])
        return {"date": data_date[:7], "data_date": data_date}

    # -- points témoins -------------------------------------------------------

    def _witness_candidates(self, ctx: BuildContext, srs: Any, gt: tuple, shape: tuple[int, int], rng: "np.random.Generator") -> list[dict[str, Any]]:
        """Pixels tirés au hasard dans le pays, avec la maille de la source qui contient leur centre."""
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
                c, r = math.floor(fc), math.floor(fr)
                if not (0 <= c < w and 0 <= r < h):
                    continue
                if min(fc - c, c + 1 - fc, fr - r, r + 1 - fr) < WITNESS_MARGIN:
                    continue  # trop près d'un bord de maille
                out.append({"col": col, "row": row, "x": x, "y": y, "c": c, "r": r})
                if len(out) >= wanted:
                    break
        return out

    def _collect_witnesses(self, ctx: BuildContext, candidates: list[dict[str, Any]], level: "np.ndarray", service: str, slot_index: int, slot: dict[str, Any]) -> None:
        canvas = ctx.canvas
        assert canvas is not None
        keep_total = int(ctx.cfg["verification"]["points_per_file"])
        by_level: dict[int, list[dict[str, Any]]] = {}
        for cand in candidates:
            by_level.setdefault(int(level[cand["r"], cand["c"]]), []).append(cand)
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
