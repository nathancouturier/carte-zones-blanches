"""Estimation de la couverture là où aucune carte officielle n'est exploitable (Andorre, Monaco).

Méthode, calée sur la France où la vérité officielle existe (sites et cartes de l'Arcep,
21,7 millions de pixels, voir docs/sources.md) :

1. les cellules 4G et 5G d'OpenCellID (positions estimées par des téléphones de bénévoles,
   pas des positions de pylônes) sont regroupées par station, puis par site ;
2. pour chaque site, gdal.ViewshedGenerate calcule sur le relief (Copernicus DEM GLO-30,
   ramené sur la grille du projet) la hauteur qu'il faudrait pour voir l'antenne depuis
   chaque pixel ;
3. trois distances en découlent pour chaque pixel : au site visible le plus proche, au
   site « presque visible » le plus proche (il manque moins de 30 m), au site le plus proche ;
4. une règle à trois niveaux les transforme en « bonne », « limitée » ou « pas de
   couverture ». Le niveau « très bonne » n'est jamais attribué : l'estimation ne sait pas
   faire cette distinction.

C'est une estimation : une antenne absente de la base crée une fausse zone blanche, une
antenne mal placée déplace les limites de plusieurs centaines de mètres. Ces zones sont
marquées « estimées » partout.

Le téléchargement d'OpenCellID demande une clé gratuite, lue dans la variable
d'environnement OPENCELLID_TOKEN. Sans clé, la source est indisponible et le pays est
laissé de côté. Le résultat est gardé en copie de travail (czb/cache.py) : OpenCellID
limite chaque fichier à deux téléchargements par jour.
"""

from __future__ import annotations

import csv
import datetime as dt
import gzip
import html
import json
import math
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import TYPE_CHECKING, Any

from ..cache import cache_name, read_cache, write_cache
from ..context import BuildContext
from ..grid import lonlat_to_mercator, mercator_to_lonlat
from ..net import USER_AGENT, download
from ..witness import draw_country_pixels
from .base import Source, SourceUnavailable

if TYPE_CHECKING:
    import numpy as np

#: Colonnes des fichiers d'OpenCellID, dans l'ordre de la documentation officielle (une ligne par cellule).
CELL_COLUMNS = ["radio", "mcc", "net", "area", "cell", "unit", "lon", "lat", "range", "samples", "changeable", "created", "updated", "averageSignal"]
KNOWN_RADIOS = {"GSM", "UMTS", "LTE", "NR", "CDMA"}
CACHE_FORMAT = 1
MONTH_ITEM = "CZB_MOIS"
#: Marge autour du pays pour retenir une cellule, en mètres : un fichier de pays peut contenir des cellules voisines.
CELL_MARGIN_M = 2000.0
#: Les bords de la fenêtre de calcul tombent sur des multiples de ce nombre de pixels (environ 1,7 km).
WINDOW_SNAP = 64


class EstimationOpenCellId(Source):
    id = "estimation_opencellid"

    def __init__(self, cfg: dict[str, Any], source_id: str | None = None):
        super().__init__(cfg, source_id)
        self._cells_error: str | None = None

    # -- disponibilité et version -------------------------------------------

    def token(self) -> str | None:
        return os.environ.get("OPENCELLID_TOKEN") or None

    def needs_token(self) -> bool:
        template = self.source_cfg.get("cells_url")
        return template is None or "{token}" in template

    def mask(self, text: str) -> str:
        """Retire la clé d'un texte destiné aux journaux."""
        token = self.token()
        text = re.sub(r"(?i)((?:token|key)=)[^&\s\"']+", r"\1***", text)
        return text.replace(token, "***") if token else text

    def available(self) -> tuple[bool, str]:
        if self.needs_token() and not self.token():
            return False, "le secret OPENCELLID_TOKEN n'est pas défini"
        return True, ""

    def parameters(self) -> dict[str, Any]:
        keys = ("mcc", "antenna_height_m", "mobile_height_m", "curvature", "near_miss_m", "site_merge_m", "station_spread_max_m", "min_samples", "good", "limited")
        return {k: self.source_cfg.get(k) for k in keys} | {"radios": {s: v.get("radios") for s, v in self.source_cfg["services"].items()}}

    def remote_state(self, services: list[str] | None = None) -> dict[str, Any]:
        # Pas de date ici : OpenCellID change tous les jours, et ce n'est pas une raison de tout reconstruire.
        # L'estimation est rafraîchie quand une autre source déclenche une construction (au plus une fois par mois).
        return {"parametres": self.parameters()}

    # -- cellules ------------------------------------------------------------

    def cells_path(self, ctx: BuildContext, mcc: int) -> Path:
        return ctx.workdir / "opencellid" / f"{int(mcc)}.csv.gz"

    def _fetch(self, url: str, data: dict[str, str] | None = None, timeout: int = 600) -> bytes:
        body = urllib.parse.urlencode(data).encode() if data else None
        headers = {"User-Agent": USER_AGENT}
        if body:
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=headers), timeout=timeout) as resp:
                return resp.read()
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError, ValueError) as exc:
            raise SourceUnavailable(f"OpenCellID injoignable ({self.mask(url)[:120]}) : {self.mask(str(exc))[:200]}") from None

    def cells_url(self, mcc: int) -> str:
        """Adresse du fichier d'un pays.

        Soit un gabarit donné dans config.yaml (« cells_url »), soit le lien lu dans la page des
        téléchargements d'OpenCellID, qui ne montre ses liens qu'après l'envoi de la clé.
        """
        template = self.source_cfg.get("cells_url")
        if template:
            return template.format(token=self.token() or "", mcc=int(mcc))
        page_url = self.source_cfg["downloads_page"]
        page = self._fetch(page_url, {"token": self.token() or ""}, timeout=120).decode("utf-8", errors="replace")
        links = [urllib.parse.urljoin(page_url, html.unescape(h)) for h in re.findall(r"""href\s*=\s*["']([^"']+)["']""", page)]
        wanted = [link for link in links if re.search(rf"(?<!\d){int(mcc)}\.csv\.gz", link)]
        if not wanted:
            shapes = sorted({re.sub(r"\d+", "N", self.mask(link))[:100] for link in links if ".csv" in link})[:6]
            raise SourceUnavailable(f"aucun lien pour le fichier {int(mcc)}.csv.gz dans la page des téléchargements d'OpenCellID ({len(links)} liens lus ; formes des liens de fichiers : {shapes})")
        return wanted[0]

    def fetch_cells(self, ctx: BuildContext, mcc: int) -> Path:
        """Télécharge le fichier des cellules d'un pays, une seule fois, et vérifie que c'en est bien un."""
        dest = self.cells_path(ctx, mcc)
        if dest.exists():
            return dest
        raw = self._fetch(self.cells_url(mcc))
        if raw[:2] != b"\x1f\x8b":
            # Le service répond 200 avec un message (clé refusée, quota atteint) à la place du fichier.
            raise SourceUnavailable(f"OpenCellID n'a pas renvoyé le fichier du MCC {int(mcc)} : {self.mask(raw[:200].decode('utf-8', errors='replace'))!r}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(raw)
        print(f"    OpenCellID : fichier du MCC {int(mcc)} téléchargé, {len(raw) / 1e6:.2f} Mo", flush=True)
        return dest

    def prepare(self, ctx: BuildContext) -> None:
        """Télécharge les cellules avant que les pays soient dessinés.

        Si le téléchargement échoue mais qu'une copie de travail d'une construction précédente existe,
        elle servira encore (ses données datent alors d'un mois précédent).
        """
        cached = ctx.workdir / "cache" / cache_name(self.source_id)
        if self._cached_month(cached) == self.month():
            return  # la copie de travail est du mois : rien à télécharger
        try:
            for mcc in self.source_cfg["mcc"]:
                self.fetch_cells(ctx, int(mcc))
        except SourceUnavailable as exc:
            self._cells_error = str(exc)
            if not cached.exists():
                raise
            print(f"ATTENTION : {self.source_id} : {exc}. La copie de travail précédente sera reprise si elle convient.", flush=True)

    def read_cells(self, ctx: BuildContext, radios: set[str], bbox: tuple[float, float, float, float]) -> list[list[dict[str, Any]]]:
        """Cellules retenues, par emplacement : technologie demandée, pays, emprise."""
        slots = self.country_cfg["slots"]
        slot_of_mnc: dict[int, int] = {}
        for index, slot in enumerate(slots):
            for mnc in slot.get("mnc", []):
                slot_of_mnc[int(mnc)] = index
        # Sans liste de codes réseau, toutes les cellules du pays vont dans le premier emplacement.
        everything = not slot_of_mnc
        min_samples = int(self.source_cfg.get("min_samples") or 1)
        west, south, east, north = bbox
        out: list[list[dict[str, Any]]] = [[] for _ in slots]
        seen = kept = 0
        nets: dict[int, int] = {}
        for mcc in (int(m) for m in self.source_cfg["mcc"]):
            path = self.fetch_cells(ctx, mcc)
            with gzip.open(path, "rt", encoding="utf-8", errors="replace", newline="") as f:
                reader = csv.reader(f)
                first = next(reader, None)
                if first is None:
                    continue
                rows: Any
                if first[0].strip().lower() == "radio":
                    header = [c.strip() for c in first]
                    if header[:10] != CELL_COLUMNS[:10]:
                        raise SourceUnavailable(f"colonnes inattendues dans le fichier d'OpenCellID : {header} (attendu : {CELL_COLUMNS})")
                    rows = reader
                else:
                    # Pas de ligne d'en-tête : la documentation donne l'ordre des colonnes, on vérifie la première ligne.
                    if len(first) < 10 or first[0] not in KNOWN_RADIOS:
                        raise SourceUnavailable(f"première ligne inattendue dans le fichier d'OpenCellID : {first[:14]}")
                    rows = _chain(first, reader)
                for row in rows:
                    if len(row) < 10:
                        continue
                    seen += 1
                    try:
                        if row[0] not in radios or int(row[1]) != mcc:
                            continue
                        net, cell = int(row[2]), int(row[4])
                        lon, lat, samples = float(row[6]), float(row[7]), int(float(row[9]))
                    except ValueError:
                        continue
                    if samples < min_samples or not (west <= lon <= east and south <= lat <= north):
                        continue
                    slot = 0 if everything else slot_of_mnc.get(net)
                    if slot is None:
                        continue
                    out[slot].append({"radio": row[0], "net": net, "cell": cell, "lon": lon, "lat": lat})
                    nets[net] = nets.get(net, 0) + 1
                    kept += 1
        ctx.stats.setdefault("estimation_cellules", {})[self.source_id] = {"lues": seen, "retenues": kept, "par_code_reseau": {str(k): v for k, v in sorted(nets.items())}}
        print(f"    {seen} cellules lues, {kept} retenues ({', '.join(sorted(radios))}), par code réseau : {dict(sorted(nets.items()))}", flush=True)
        return out

    def build_sites(self, cells: list[dict[str, Any]]) -> tuple[list[tuple[float, float]], dict[str, int]]:
        """Regroupe les cellules d'un opérateur en sites (longitude, latitude).

        Les cellules 4G d'une même station (même code réseau et même identifiant de cellule divisé
        par 256) sont réunies et placées à la médiane de leurs positions : les secteurs entourent le
        pylône. Si elles sont trop dispersées pour former une station, elles sont traitées une à une.
        Puis les points à moins de site_merge_m les uns des autres sont fusionnés.
        """
        cfg = self.source_cfg
        merge_m = float(cfg.get("site_merge_m", 300))
        spread_max = float(cfg.get("station_spread_max_m", 2000))
        if not cells:
            return [], {"stations": 0, "stations_dispersees": 0, "sites": 0}
        lat0 = sum(c["lat"] for c in cells) / len(cells)
        kx = 111_320.0 * math.cos(math.radians(lat0))  # mètres par degré de longitude
        ky = 110_540.0  # mètres par degré de latitude

        def local(c: dict[str, Any]) -> tuple[float, float]:
            return c["lon"] * kx, c["lat"] * ky

        stations: dict[tuple[int, int], list[tuple[float, float]]] = {}
        loose: list[tuple[float, float]] = []
        for c in cells:
            if c["radio"] == "LTE" and c["cell"] > 255:
                stations.setdefault((c["net"], c["cell"] // 256), []).append(local(c))
            else:
                loose.append(local(c))
        points: list[tuple[float, float]] = []
        scattered = 0
        for members in stations.values():
            mx = _median([p[0] for p in members])
            my = _median([p[1] for p in members])
            if max(math.hypot(p[0] - mx, p[1] - my) for p in members) <= spread_max:
                points.append((mx, my))
            else:
                scattered += 1
                loose.extend(members)
        sites = cluster_sites(points + loose, merge_m)
        stats = {"stations": len(stations), "stations_dispersees": scattered, "sites": len(sites)}
        return [(x / kx, y / ky) for x, y in sites], stats

    # -- relief --------------------------------------------------------------

    def load_dem(self, ctx: BuildContext, bounds: tuple[float, float, float, float], width: int, height: int) -> Any:
        """Relief sur la grille du projet (EPSG:3857, même pixel que les tuiles), la mer à 0, sans valeur manquante."""
        from osgeo import gdal

        minx, miny, maxx, maxy = bounds
        west, south = mercator_to_lonlat(minx, miny)
        east, north = mercator_to_lonlat(maxx, maxy)
        folder = ctx.workdir / "mnt"
        tiles: list[str] = []
        for lat in range(math.floor(south), math.floor(north) + 1):
            for lon in range(math.floor(west), math.floor(east) + 1):
                url = self.source_cfg["dem_url"].format(ns="N" if lat >= 0 else "S", lat=abs(lat), ew="E" if lon >= 0 else "W", lon=abs(lon))
                dest = folder / url.rsplit("/", 1)[-1]
                if not dest.exists() and download(url, dest, missing_ok=True) is None:
                    print(f"    pas de dalle de relief pour {lat}, {lon} (mer)", flush=True)
                    continue
                tiles.append(str(dest))
        if not tiles:
            raise RuntimeError(f"{self.source_id} : aucune dalle de relief pour l'emprise {west:.2f}, {south:.2f}, {east:.2f}, {north:.2f}")
        vrt = gdal.BuildVRT("", tiles)
        dem = gdal.Warp("", vrt, format="MEM", dstSRS="EPSG:3857", outputBounds=bounds, width=width, height=height, resampleAlg="bilinear", outputType=gdal.GDT_Float32, warpOptions=["INIT_DEST=0"])
        vrt = None
        for path in tiles:
            Path(path).unlink(missing_ok=True)
        if dem is None or dem.RasterXSize != width or dem.RasterYSize != height:
            raise RuntimeError(f"{self.source_id} : relief illisible")
        print(f"    relief : {len(tiles)} dalle(s) Copernicus, {width} x {height} px", flush=True)
        return dem

    # -- calcul --------------------------------------------------------------

    def estimate(self, dem: Any, sites: list[tuple[float, float]]) -> "np.ndarray":
        """Niveau estimé (0, 1 ou 2) de chaque pixel du relief pour un ensemble de sites (x, y en EPSG:3857)."""
        import numpy as np
        from osgeo import gdal

        cfg = self.source_cfg
        band = dem.GetRasterBand(1)
        gt = dem.GetGeoTransform()
        res = gt[1]
        shape = (dem.RasterYSize, dem.RasterXSize)
        antenna, mobile = float(cfg["antenna_height_m"]), float(cfg["mobile_height_m"])
        curvature, near_miss = float(cfg["curvature"]), float(cfg["near_miss_m"])
        good, limited = cfg["good"], cfg["limited"]
        reach_km = max(float(limited["visible_km"]), float(limited["near_km"]), float(limited["any_km"]), float(good["visible_km"]))
        d_visible = np.full(shape, np.inf, np.float32)
        d_near = np.full(shape, np.inf, np.float32)
        d_any = np.full(shape, np.inf, np.float32)
        for x, y in sites:
            col, row = (x - gt[0]) / res, (gt[3] - y) / res
            if not (0 <= col < shape[1] and 0 <= row < shape[0]):
                continue
            # La projection de Mercator dilate les distances de k = 1 / cos(latitude) : on corrige la portée
            # et la courbure, le calcul de visibilité (qui compare des pentes) reste juste.
            k = 1.0 / math.cos(math.radians(mercator_to_lonlat(x, y)[1]))
            view = gdal.ViewshedGenerate(band, "MEM", "", [], x, y, antenna, mobile, 255, 1, 0, -1.0, curvature / (k * k), gdal.GVM_Edge, reach_km * 1000.0 * k, heightMode=gdal.GVOT_MIN_TARGET_HEIGHT_FROM_GROUND)
            if view is None:
                continue
            needed = view.ReadAsArray()  # hauteur au-dessus du sol qu'il faudrait pour voir l'antenne
            vgt = view.GetGeoTransform()
            vh, vw = needed.shape
            c0 = int(round((vgt[0] - gt[0]) / res))
            r0 = int(round((gt[3] - vgt[3]) / res))
            xs = ((vgt[0] + (np.arange(vw) + 0.5) * res - x) / k / 1000.0).astype(np.float32)
            ys = ((vgt[3] - (np.arange(vh) + 0.5) * res - y) / k / 1000.0).astype(np.float32)
            dist = np.sqrt(xs[None, :] ** 2 + ys[:, None] ** 2)
            # Au-delà de la portée, GDAL ne calcule rien (la valeur 0 se lirait « visible ») : on écarte ces pixels,
            # avec deux pixels de marge pour ne pas dépendre d'un arrondi à la limite du disque.
            dist[dist > reach_km - 2 * res / k / 1000.0] = np.inf
            sl = (slice(r0, r0 + vh), slice(c0, c0 + vw))
            np.minimum(d_any[sl], dist, out=d_any[sl])
            np.minimum(d_near[sl], np.where(needed <= near_miss, dist, np.inf), out=d_near[sl])
            np.minimum(d_visible[sl], np.where(needed <= mobile, dist, np.inf), out=d_visible[sl])
        level = np.zeros(shape, dtype=np.uint8)
        level[(d_visible <= float(limited["visible_km"])) | (d_near <= float(limited["near_km"])) | (d_any <= float(limited["any_km"]))] = 1
        level[(d_visible <= float(good["visible_km"])) | (d_near <= float(good["near_km"])) | (d_any <= float(good["any_km"]))] = 2
        return level

    # -- traitement ---------------------------------------------------------

    def month(self) -> str:
        return dt.date.today().strftime("%Y-%m")

    @staticmethod
    def _cached_month(path: Path) -> str | None:
        from osgeo import gdal

        if not path.exists():
            return None
        try:
            ds = gdal.Open(str(path))
        except RuntimeError:
            return None
        return ds.GetMetadataItem(MONTH_ITEM) if ds is not None else None

    def window(self, ctx: BuildContext) -> tuple[int, int, int, int]:
        """Fenêtre de calcul (col0, row0, largeur, hauteur) sur la grille : le pays, élargi de la portée des antennes."""
        canvas, layers = ctx.canvas, ctx.layers
        assert canvas is not None and layers is not None
        extent = layers.country_extent(self.country_code)
        if extent is None:
            raise RuntimeError(f"{self.source_id} : le pays {self.country_iso} n'a aucun pixel sur la grille")
        res = canvas.grid.resolution
        limited = self.source_cfg["limited"]
        reach_m = 1000.0 * max(float(limited["visible_km"]), float(limited["near_km"]), float(limited["any_km"]))
        k = 1.0 / math.cos(math.radians(mercator_to_lonlat(extent[2], extent[3])[1]))
        margin = reach_m * k + 20 * res
        # Fenêtre repérée depuis l'origine du monde (et non depuis le coin de la grille, qui dépend du périmètre),
        # élargie à des multiples de WINDOW_SNAP pixels : la copie de travail reste valable si le contour du pays
        # bouge de quelques pixels ou si d'autres pays s'ajoutent à la construction.
        world_col0 = canvas.tx0 * canvas.grid.tile_size
        world_row0 = canvas.ty0 * canvas.grid.tile_size
        col0 = math.floor((world_col0 + (extent[0] - margin - canvas.origin_x) / res) / WINDOW_SNAP) * WINDOW_SNAP
        col1 = math.ceil((world_col0 + (extent[2] + margin - canvas.origin_x) / res) / WINDOW_SNAP) * WINDOW_SNAP
        row0 = math.floor((world_row0 + (canvas.origin_y - extent[3] - margin) / res) / WINDOW_SNAP) * WINDOW_SNAP
        row1 = math.ceil((world_row0 + (canvas.origin_y - extent[1] + margin) / res) / WINDOW_SNAP) * WINDOW_SNAP
        return col0 - world_col0, row0 - world_row0, col1 - col0, row1 - row0

    def world_window(self, ctx: BuildContext, window: tuple[int, int, int, int]) -> list[int]:
        """La même fenêtre, comptée en pixels depuis l'origine du monde : c'est elle qui entre dans la clé de la copie de travail."""
        canvas = ctx.canvas
        assert canvas is not None
        return [window[0] + canvas.tx0 * canvas.grid.tile_size, window[1] + canvas.ty0 * canvas.grid.tile_size, window[2], window[3]]

    def compute(self, ctx: BuildContext, window: tuple[int, int, int, int], services: list[str]) -> "np.ndarray":
        """Niveaux estimés : un tableau (lignes, colonnes) par emplacement d'opérateur."""
        import numpy as np

        canvas, layers = ctx.canvas, ctx.layers
        assert canvas is not None and layers is not None
        res = canvas.grid.resolution
        col0, row0, width, height = window
        bounds = (canvas.origin_x + col0 * res, canvas.origin_y - (row0 + height) * res, canvas.origin_x + (col0 + width) * res, canvas.origin_y - row0 * res)
        extent = layers.country_extent(self.country_code)
        assert extent is not None
        west, south = mercator_to_lonlat(extent[0], extent[1])
        east, north = mercator_to_lonlat(extent[2], extent[3])
        dlat = CELL_MARGIN_M / 110_540.0
        dlon = CELL_MARGIN_M / (111_320.0 * math.cos(math.radians(north)))
        radios = set(self.source_cfg["services"][services[0]]["radios"])
        cells = self.read_cells(ctx, radios, (west - dlon, south - dlat, east + dlon, north + dlat))
        if not any(cells):
            raise SourceUnavailable(f"aucune cellule {', '.join(sorted(radios))} dans le pays {self.country_iso} dans les fichiers d'OpenCellID (MCC {self.source_cfg['mcc']})")
        try:
            dem = self.load_dem(ctx, bounds, width, height)
        except RuntimeError as exc:
            # Une dalle absente (mer) est normale ; toute autre erreur rend l'estimation impossible cette fois-ci.
            raise SourceUnavailable(f"relief Copernicus indisponible : {exc}") from None
        slots = self.country_cfg["slots"]
        levels = np.zeros((len(slots), height, width), dtype=np.uint8)
        site_stats: dict[str, Any] = {}
        for index, slot in enumerate(slots):
            sites, stats = self.build_sites(cells[index])
            site_stats[slot["id"]] = stats | {"cellules": len(cells[index])}
            levels[index] = self.estimate(dem, [lonlat_to_mercator(lon, lat) for lon, lat in sites])
            print(f"    {slot['id']} : {len(cells[index])} cellules, {stats['stations']} stations dont {stats['stations_dispersees']} trop dispersées, {stats['sites']} sites", flush=True)
        ctx.stats.setdefault("estimation_sites", {})[self.source_id] = site_stats
        dem = None
        for mcc in self.source_cfg["mcc"]:
            self.cells_path(ctx, int(mcc)).unlink(missing_ok=True)
        return levels

    def process(self, ctx: BuildContext) -> dict[str, Any]:
        import numpy as np
        from osgeo import gdal

        canvas, layers = ctx.canvas, ctx.layers
        assert canvas is not None and layers is not None
        cfg = self.source_cfg
        services = [s for s in ctx.services if s in cfg["services"]]
        if not services:
            raise RuntimeError(f"{self.source_id} : aucun service demandé n'est fourni par cette source")
        service = services[0]
        slots = self.country_cfg["slots"]
        window = self.window(ctx)
        col0, row0, width, height = window
        res = canvas.grid.resolution
        gt = (canvas.origin_x + col0 * res, res, 0.0, canvas.origin_y - row0 * res, 0.0, -res)
        key = json.dumps({"format": CACHE_FORMAT, "parametres": self.parameters(), "fenetre": self.world_window(ctx, window), "zoom": canvas.grid.zoom, "emplacements": [s["id"] for s in slots]}, sort_keys=True, ensure_ascii=False)
        cached = ctx.workdir / "cache" / cache_name(self.source_id)
        stored = read_cache(cached, key)
        stored_month = self._cached_month(cached) if stored is not None else None
        month = self.month()
        levels = None
        problem = self._cells_error
        if stored is not None and stored_month == month:
            levels = stored
            print(f"  - copie de travail du mois reprise ({cached.name})", flush=True)
            origin = "reprise"
        elif problem is None:
            try:
                levels = self.compute(ctx, window, services)
                origin = "reconstruite"
            except SourceUnavailable as exc:
                problem = str(exc)
        if levels is None:
            if stored is None or not stored_month:
                raise SourceUnavailable(problem or "estimation impossible")
            # Mieux vaut l'estimation d'un mois précédent que pas de pays du tout.
            levels, month = stored, stored_month
            print(f"  - estimation impossible cette fois-ci ({problem}) : copie de travail de {stored_month} reprise", flush=True)
            origin = "reprise, ancienne"
        ctx.stats.setdefault("copie_de_travail", {})[self.source_id] = origin
        out_path = ctx.outdir / cache_name(self.source_id)
        write_cache(out_path, levels, gt, 3857, key, "une bande par emplacement d'opérateur ; niveau estimé 0 (pas de couverture), 1 (limitée) ou 2 (bonne)")
        ds = gdal.Open(str(out_path), gdal.GA_Update)
        ds.SetMetadataItem(MONTH_ITEM, month)
        ds = None

        # La fenêtre de calcul est alignée sur la grille : on recopie sa partie commune avec la grille, sans rééchantillonner.
        c0, r0 = max(0, col0), max(0, row0)
        c1, r1 = min(canvas.width, col0 + width), min(canvas.height, row0 + height)
        rng = np.random.default_rng(int(ctx.cfg["verification"]["seed"]) + self.country_code)
        for index, slot in enumerate(slots):
            level = levels[index]
            common = (c0, r0, c1 - c0, r1 - r0)
            part = level[r0 - row0 : r1 - row0, c0 - col0 : c1 - col0]
            layers.merge_level(service, index, common, part, self.country_code)
            inside = part[layers.country_mask(common, self.country_code)]
            shares = {str(v): round(float((inside == v).mean()) * 100, 1) for v in (0, 1, 2)} if inside.size else {}
            print(f"    {slot['id']} : part du pays par niveau estimé {shares}", flush=True)
            ctx.stats.setdefault("estimation_parts", {})[f"{self.source_id}:{slot['id']}"] = shares
            self._witnesses(ctx, level, window, service, index, slot, rng)
        layers.flush()
        return {"date": month}

    # -- points témoins -------------------------------------------------------

    def _witnesses(self, ctx: BuildContext, level: "np.ndarray", window: tuple[int, int, int, int], service: str, slot_index: int, slot: dict[str, Any], rng: "np.random.Generator") -> None:
        """Niveau attendu lu dans le tableau de l'estimation, pour des pixels du pays tirés au hasard."""
        canvas, layers = ctx.canvas, ctx.layers
        assert canvas is not None and layers is not None
        col0, row0, width, height = window
        wanted = int(ctx.cfg["verification"]["candidates_per_file"])
        keep_total = int(ctx.cfg["verification"]["points_per_file"])
        by_level: dict[int, list[tuple[int, int]]] = {}
        found = attempts = 0
        while found < wanted and attempts < 400:
            attempts += 1
            for col, row in zip(*draw_country_pixels(ctx, self.country_code, rng, wanted * 4)):
                by_level.setdefault(int(level[row - row0, col - col0]), []).append((col, row))
                found += 1
                if found >= wanted:
                    break
        kept: list[tuple[int, tuple[int, int]]] = []
        while len(kept) < keep_total and any(by_level.values()):
            for value in sorted(by_level):
                if by_level[value] and len(kept) < keep_total:
                    kept.append((value, by_level[value].pop()))
        for value, (col, row) in kept:
            tx, ty, px, py = canvas.tile_and_pixel(col, row)
            lon, lat = mercator_to_lonlat(*canvas.pixel_center(col, row))
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


def _chain(first: list[str], rest: Any) -> Any:
    yield first
    yield from rest


def _median(values: list[float]) -> float:
    ordered = sorted(values)
    mid = len(ordered) // 2
    return ordered[mid] if len(ordered) % 2 else (ordered[mid - 1] + ordered[mid]) / 2


def cluster_sites(points: list[tuple[float, float]], radius: float) -> list[tuple[float, float]]:
    """Fusionne les points proches les uns des autres (coordonnées en mètres).

    Un point rejoint le premier site situé à moins de « radius » mètres, dont la position
    devient la moyenne de ses points ; sinon il fonde un nouveau site. L'ordre d'arrivée
    compte : les stations (positions les plus sûres) sont passées en premier.
    """
    if radius <= 0:
        return list(points)
    sites: list[list[float]] = []  # x, y, nombre de points
    grid: dict[tuple[int, int], list[int]] = {}
    for x, y in points:
        cx, cy = math.floor(x / radius), math.floor(y / radius)
        chosen = -1
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for index in grid.get((cx + dx, cy + dy), ()):
                    sx, sy, _ = sites[index]
                    if (sx - x) ** 2 + (sy - y) ** 2 <= radius * radius:
                        chosen = index
                        break
                if chosen >= 0:
                    break
            if chosen >= 0:
                break
        if chosen >= 0:
            sx, sy, n = sites[chosen]
            sites[chosen] = [(sx * n + x) / (n + 1), (sy * n + y) / (n + 1), n + 1]
        else:
            sites.append([x, y, 1])
            grid.setdefault((cx, cy), []).append(len(sites) - 1)
    return [(s[0], s[1]) for s in sites]
