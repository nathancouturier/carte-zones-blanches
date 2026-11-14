"""France : couvertures théoriques publiées par l'Arcep (Mon réseau mobile).

Un fichier GeoPackage par opérateur, par technologie et par usage, pour toute la
métropole (Corse comprise). Schéma vérifié avec ogrinfo sur le 2e trimestre 2026 :

- SCR : RGF93 / Lambert-93 (EPSG:2154) ;
- un multipolygone par département et par niveau ;
- champs : operateur, date, techno, usage, niveau, dept, operateur_infra,
  operateur_commercial ;
- niveau vaut TBC (très bonne couverture), BC (bonne couverture) ou
  CL (couverture limitée). L'absence de polygone vaut « pas de couverture ».
"""

from __future__ import annotations

import html
import re
from pathlib import Path
from typing import Any

from typing import TYPE_CHECKING

from ..context import BuildContext
from ..grid import mercator_to_lonlat
from ..net import download, extract_7z, fetch_text
from ..witness import draw_country_pixels
from .base import Source

if TYPE_CHECKING:  # numpy et GDAL ne sont chargés que pour construire, pas pour lire l'état des sources
    import numpy as np
    from osgeo import ogr

LISTING_RE = re.compile(
    r'<a href="([^"]+\.7z)"[^>]*>.*?data-size="(\d+)".*?datetime="([^"]+)"', re.S
)
NAME_RE = re.compile(r"^(\d{4})_T([1-4])_couv_Metropole_([A-Z0-9]+)_([0-9G]+)_([a-z]+)\.gpkg\.7z$")

# Demi-côté (en mètres) du carré testé autour de chaque point témoin : un point
# trop proche d'un bord de polygone est écarté, car le résultat dépendrait d'un
# arrondi de reprojection.
WITNESS_MARGIN_M = 0.5


def parse_listing(page: str) -> list[dict[str, Any]]:
    """Extrait la liste des fichiers de la page d'index de data.arcep.fr."""
    files = []
    for href, size, modified in LISTING_RE.findall(page):
        name = html.unescape(href).rsplit("/", 1)[-1]
        m = NAME_RE.match(name)
        if not m:
            continue
        files.append(
            {
                "name": name,
                "size": int(size),
                "modified": modified,
                "quarter": f"{m.group(1)}-T{m.group(2)}",
                "operator": m.group(3),
                "techno": m.group(4),
                "usage": m.group(5),
            }
        )
    return files


class FrArcep(Source):
    id = "fr_arcep"

    def __init__(self, cfg: dict[str, Any], source_id: str | None = None):
        super().__init__(cfg, source_id)
        self._listing: list[dict[str, Any]] | None = None

    # -- version en ligne ---------------------------------------------------

    def listing(self) -> list[dict[str, Any]]:
        if self._listing is None:
            files = parse_listing(fetch_text(self.source_cfg["listing_url"]))
            if not files:
                raise RuntimeError("listing Arcep : aucun fichier reconnu, le format de la page a peut-être changé")
            self._listing = files
        return self._listing

    def wanted_files(self, services: list[str]) -> list[tuple[str, int, dict[str, Any]]]:
        """Fichiers à traiter : (service, emplacement, entrée du listing)."""
        wanted = []
        for service in services:
            spec = self.source_cfg["services"][service]
            for slot, operator in enumerate(self.country_cfg["slots"]):
                matches = [
                    f
                    for f in self.listing()
                    if f["operator"] == operator["arcep"] and f["techno"] == spec["techno"] and f["usage"] == spec["usage"]
                ]
                if len(matches) != 1:
                    raise RuntimeError(
                        f"listing Arcep : {len(matches)} fichier(s) pour {operator['arcep']} {spec['techno']} {spec['usage']}, 1 attendu"
                    )
                wanted.append((service, slot, matches[0]))
        return wanted

    def remote_state(self, services: list[str] | None = None) -> dict[str, Any]:
        services = services or list(self.source_cfg["services"])
        files = [entry for _, _, entry in self.wanted_files(services)]
        quarters = sorted({f["quarter"] for f in files})
        return {
            "quarter": quarters[-1],
            "files": {f["name"]: {"size": f["size"], "modified": f["modified"]} for f in files},
        }

    # -- traitement ---------------------------------------------------------

    def process(self, ctx: BuildContext) -> dict[str, Any]:
        import numpy as np

        assert ctx.canvas is not None and ctx.layers is not None
        listing_url: str = self.source_cfg["listing_url"]
        base_url = listing_url if listing_url.endswith("/") else listing_url.rsplit("/", 1)[0] + "/"
        rng = np.random.default_rng(int(ctx.cfg["verification"]["seed"]))
        dates: set[str] = set()
        quarters: set[str] = set()
        downloaded = 0
        for service, slot, entry in self.wanted_files(ctx.services):
            operator = self.country_cfg["slots"][slot]
            print(f"  - {entry['name']} ({entry['size'] / 1e6:.0f} Mo) : {operator['name']}, {service}", flush=True)
            archive = download(base_url + entry["name"], ctx.workdir / entry["name"])
            downloaded += archive.stat().st_size
            extracted = extract_7z(archive, ctx.workdir / "arcep")
            archive.unlink(missing_ok=True)  # le disque du runner est limité
            gpkgs = [p for p in extracted if p.suffix == ".gpkg"]
            if len(gpkgs) != 1:
                raise RuntimeError(f"{entry['name']} : {len(gpkgs)} fichier(s) .gpkg dans l'archive, 1 attendu")
            try:
                info = self.rasterize_file(ctx, gpkgs[0], service, slot, rng)
            finally:
                for p in extracted:
                    p.unlink(missing_ok=True)
            dates |= info["dates"]
            quarters.add(entry["quarter"])
            ctx.layers.flush()
        ctx.stats["arcep_telecharge_mo"] = round(downloaded / 1e6, 1)
        return {
            "date": sorted(quarters)[-1],
            "data_date": sorted(dates)[-1] if dates else None,
        }

    def rasterize_file(self, ctx: BuildContext, gpkg: Path, service: str, slot: int, rng: "np.random.Generator") -> dict[str, Any]:
        import numpy as np
        from osgeo import ogr

        from ..raster import geometry_windows, transformer_from_mercator, transformer_to_mercator

        canvas, layers = ctx.canvas, ctx.layers
        assert canvas is not None and layers is not None
        level_field: str = self.source_cfg["level_field"]
        level_of: dict[str, int] = {str(k): int(v) for k, v in self.source_cfg["levels"].items()}

        ds = ogr.Open(str(gpkg))
        if ds is None or ds.GetLayerCount() != 1:
            raise RuntimeError(f"{gpkg.name} : une seule couche attendue")
        layer = ds.GetLayer(0)
        defn = layer.GetLayerDefn()
        fields = [defn.GetFieldDefn(i).GetName() for i in range(defn.GetFieldCount())]
        if level_field not in fields:
            raise RuntimeError(f"{gpkg.name} : champ « {level_field} » absent (champs : {fields})")
        srs = layer.GetSpatialRef()
        if srs is None:
            raise RuntimeError(f"{gpkg.name} : SCR absent")
        to_merc = transformer_to_mercator(srs)
        from_merc = transformer_from_mercator(srs)

        # On ne lit que les entités qui touchent la grille.
        minx, miny, maxx, maxy = canvas.mercator_bounds
        ring = ogr.Geometry(ogr.wkbLinearRing)
        for x, y in ((minx, miny), (maxx, miny), (maxx, maxy), (minx, maxy), (minx, miny)):
            ring.AddPoint_2D(x, y)
        box = ogr.Geometry(ogr.wkbPolygon)
        box.AddGeometry(ring)
        box.Segmentize((maxx - minx) / 64)
        box.Transform(from_merc)
        sx0, sx1, sy0, sy1 = box.GetEnvelope()
        layer.SetSpatialFilterRect(sx0, sy0, sx1, sy1)

        witnesses = self._witness_candidates(ctx, from_merc, rng)
        dates: set[str] = set()
        count = 0
        burned = 0
        has_date = "date" in fields
        for feat in layer:
            value = feat.GetField(level_field)
            if value not in level_of:
                raise RuntimeError(f"{gpkg.name} : valeur de niveau inconnue {value!r} (attendu : {sorted(level_of)})")
            level = level_of[value]
            geom = feat.GetGeometryRef()
            if geom is None or geom.IsEmpty():
                continue
            if has_date and feat.GetField("date"):
                dates.add(str(feat.GetField("date")))
            self._update_witnesses(witnesses, geom, level)
            merc = geom.Clone()
            merc.Transform(to_merc)
            for win, mask in geometry_windows(merc, canvas):
                layers.merge_level(service, slot, win, mask.astype(np.uint8) * np.uint8(level), self.country_code)
                burned += int(mask.sum())
            count += 1
        print(f"    {count} entités rastérisées, {burned:,} pixels allumés".replace(",", " "), flush=True)
        if count == 0:
            raise RuntimeError(f"{gpkg.name} : aucune entité dans l'emprise")
        kept = self._select_witnesses(ctx, witnesses, service, slot)
        ctx.witnesses.extend(kept)
        return {"dates": dates, "features": count}

    # -- points témoins pour le test de cohérence -----------------------------

    def _witness_candidates(self, ctx: BuildContext, from_merc: Any, rng: "np.random.Generator") -> list[dict[str, Any]]:
        """Tire des pixels au hasard dans le pays et calcule la position de leur centre dans le SCR de la source."""
        import numpy as np
        from osgeo import ogr

        canvas, layers = ctx.canvas, ctx.layers
        assert canvas is not None and layers is not None
        wanted = int(ctx.cfg["verification"]["candidates_per_file"])
        candidates: list[dict[str, Any]] = []
        attempts = 0
        while len(candidates) < wanted and attempts < 400:
            attempts += 1
            for col, row in zip(*draw_country_pixels(ctx, self.country_code, rng, wanted * 4)):
                x, y = canvas.pixel_center(col, row)
                sx, sy, _ = from_merc.TransformPoint(x, y)
                points = []
                for dx, dy in ((0, 0), (-1, -1), (1, -1), (1, 1), (-1, 1)):
                    pt = ogr.Geometry(ogr.wkbPoint)
                    pt.AddPoint_2D(sx + dx * WITNESS_MARGIN_M, sy + dy * WITNESS_MARGIN_M)
                    points.append(pt)
                candidates.append({"col": col, "row": row, "x": x, "y": y, "sx": sx, "sy": sy, "points": points, "level": 0, "ambiguous": False})
                if len(candidates) >= wanted:
                    break
        return candidates

    @staticmethod
    def _update_witnesses(witnesses: list[dict[str, Any]], geom: "ogr.Geometry", level: int) -> None:
        """Met à jour le niveau attendu des points témoins situés dans cette entité (test exact, GEOS)."""
        minx, maxx, miny, maxy = geom.GetEnvelope()
        inside_env = [w for w in witnesses if minx - 1 <= w["sx"] <= maxx + 1 and miny - 1 <= w["sy"] <= maxy + 1]
        if not inside_env:
            return
        prepared = geom.CreatePreparedGeometry() if hasattr(geom, "CreatePreparedGeometry") else None
        tester = prepared if prepared is not None else geom
        for w in inside_env:
            results = [bool(tester.Contains(pt)) for pt in w["points"]]
            if any(results) and not all(results):
                w["ambiguous"] = True  # à moins de 50 cm d'un bord : on ne s'en sert pas
            if results[0] and level > w["level"]:
                w["level"] = level

    def _select_witnesses(self, ctx: BuildContext, witnesses: list[dict[str, Any]], service: str, slot: int) -> list[dict[str, Any]]:
        """Garde un échantillon équilibré entre les niveaux."""
        canvas = ctx.canvas
        assert canvas is not None
        keep_total = int(ctx.cfg["verification"]["points_per_file"])
        usable = [w for w in witnesses if not w["ambiguous"]]
        by_level: dict[int, list[dict[str, Any]]] = {}
        for w in usable:
            by_level.setdefault(w["level"], []).append(w)
        kept: list[dict[str, Any]] = []
        # Tour à tour un point de chaque niveau, jusqu'à atteindre le quota.
        while len(kept) < keep_total and any(by_level.values()):
            for level in sorted(by_level):
                if by_level[level] and len(kept) < keep_total:
                    kept.append(by_level[level].pop())
        operator = self.country_cfg["slots"][slot]
        out = []
        for w in kept:
            tx, ty, px, py = canvas.tile_and_pixel(w["col"], w["row"])
            lon, lat = mercator_to_lonlat(w["x"], w["y"])
            out.append(
                {
                    "source": self.source_id,
                    "country": self.country_iso,
                    "service": service,
                    "slot": slot,
                    "operator": operator["id"],
                    "z": canvas.grid.zoom,
                    "x": tx,
                    "y": ty,
                    "px": px,
                    "py": py,
                    "lon": round(lon, 6),
                    "lat": round(lat, 6),
                    "expected": w["level"],
                }
            )
        counts = {level: sum(1 for w in out if w["expected"] == level) for level in range(4)}
        print(f"    points témoins : {len(out)} retenus sur {len(usable)} utilisables, par niveau {counts}", flush=True)
        return out
