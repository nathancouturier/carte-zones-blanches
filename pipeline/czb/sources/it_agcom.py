"""Italie : Broadband Map de l'AGCOM, couverture mobile 4G.

Source officielle agrégée. Pour chaque carré de 100 m, la carte donne le nombre
de réseaux mobiles 4G qui le couvrent (1 à 4), sans dire lesquels et sans
niveau de qualité. Un carré sans polygone n'est couvert par aucun réseau.
Vérifié par sonde sur l'édition du 27 janvier 2026 :

- service ArcGIS REST public du portail open data de l'AGCOM, couche 0 de
  https://geo3.agcom.it/MapET-SFS/rest/services/Grid100/mobile_4G/MapServer ;
- polygones en EPSG:3857, un par commune et par valeur ; champs fid,
  n_infrastrutture_totali (1 à 4), COD_REG (1 Piemonte, 2 Valle d'Aosta, 7 Liguria) ;
- format ESRI JSON seulement, 250 entités par page au plus ; ce serveur ignore
  resultOffset, on pagine donc par fid croissant (czb/arcgis.py) ;
- licence CC BY 4.0, avec le logo et l'adresse du portail à afficher.

Comme pour la Suisse, les emplacements portent des seuils : « au moins 1 réseau »,
« au moins 2 », « au moins 3 », « les 4 ». Il n'y a ni 2G ni 3G dans cette carte :
rien pour les appels et SMS.
"""

from __future__ import annotations

import re
from typing import TYPE_CHECKING, Any

from .. import arcgis
from ..context import BuildContext
from .base import Source

if TYPE_CHECKING:
    pass


class ItAgcom(Source):
    id = "it_agcom"

    def __init__(self, cfg: dict[str, Any], source_id: str | None = None):
        super().__init__(cfg, source_id)
        self._service: dict[str, Any] | None = None

    # -- version en ligne ---------------------------------------------------

    def where(self) -> str:
        regions = ",".join(str(int(r)) for r in self.source_cfg["regions"])
        return f"{self.source_cfg['region_field']} IN ({regions})"

    def service(self) -> dict[str, Any]:
        if self._service is None:
            info = arcgis.get_json(self.source_cfg["service_url"])
            layers = info.get("layers") or []
            if len(layers) != 1:
                raise RuntimeError(f"{self.source_id} : {len(layers)} couche(s) dans le service, 1 attendue")
            self._service = {"description": info.get("serviceDescription") or "", "layer": layers[0].get("name") or ""}
        return self._service

    def publication(self) -> str | None:
        """Phrase de l'AGCOM sur la date des données (« Dati del 27 gennaio 2026 - Pubblicazione del 2 feb 2026 »)."""
        url = self.source_cfg.get("date_url")
        if not url:
            return None
        data = arcgis.get_json(url, {"where": "1=1", "outFields": "*", "returnGeometry": "false"})
        features = data.get("features") or []
        return str(features[0]["attributes"].get(self.source_cfg.get("date_field", "commento"))) if features else None

    def data_date(self) -> str:
        """Date des données, lue dans le nom du service (« mobile_4G_20260127 »)."""
        match = re.search(r"(20\d{2})(\d{2})(\d{2})$", self.service()["description"])
        if not match:
            raise RuntimeError(f"{self.source_id} : date introuvable dans le nom du service « {self.service()['description']} »")
        return "-".join(match.groups())

    def remote_state(self, services: list[str] | None = None) -> dict[str, Any]:
        return {
            "service": self.service()["description"],
            "couche": self.service()["layer"],
            "publication": self.publication(),
            "entites": arcgis.count(self.source_cfg["query_url"], self.where()),
        }

    # -- traitement ---------------------------------------------------------

    def process(self, ctx: BuildContext) -> dict[str, Any]:
        import numpy as np
        from osgeo import ogr

        from ..raster import geometry_windows, polygonal
        from ..witness import VectorWitnesses

        canvas, layers = ctx.canvas, ctx.layers
        assert canvas is not None and layers is not None
        cfg = self.source_cfg
        slots: list[dict[str, Any]] = self.country_cfg["slots"]
        thresholds = [int(slot["min_operators"]) for slot in slots]
        allowed = {int(k): int(v) for k, v in cfg["values"].items()}
        covered = int(cfg["covered_level"])
        count_field: str = cfg["count_field"]
        oid_field: str = cfg.get("oid_field", "fid")
        services = [s for s in ctx.services if s in cfg["services"]]
        if not services:
            raise RuntimeError(f"{self.source_id} : aucun service demandé n'est fourni par cette source")
        service = services[0]

        expected = arcgis.count(cfg["query_url"], self.where())
        print(f"  - {self.service()['description']} : {expected} entités attendues pour les régions {cfg['regions']}", flush=True)
        rng = np.random.default_rng(int(ctx.cfg["verification"]["seed"]) + self.country_code)
        witnesses = VectorWitnesses(ctx, self.country_code, None, rng)
        features = burned = outside = 0
        by_value: dict[int, int] = {}
        pages = arcgis.pages(
            cfg["query_url"],
            self.where(),
            [oid_field, count_field, cfg["region_field"]],
            oid_field,
            int(cfg.get("page_size", 250)),
            ctx.workdir / self.source_id,
            extra={"outSR": 3857},
            pause_s=float(cfg.get("pause_s", 1.0)),
            expected=expected,
        )
        for page in pages:
            ds = ogr.Open(str(page))
            if ds is None:
                raise RuntimeError(f"{self.source_id} : page illisible ({page.name})")
            layer = ds.GetLayer(0)
            srs = layer.GetSpatialRef()
            if srs is None or srs.GetAuthorityCode(None) != "3857":
                raise RuntimeError(f"{self.source_id} : SCR inattendu dans la réponse ({srs.GetAuthorityCode(None) if srs else None}), EPSG:3857 attendu")
            for feat in layer:
                raw = feat.GetField(count_field)
                if raw is None or int(raw) not in allowed:
                    # On ne devine pas le sens d'une valeur nouvelle : on s'arrête.
                    raise RuntimeError(f"{self.source_id} : valeur inconnue {raw!r} dans {count_field} (attendu : {sorted(allowed)})")
                n = allowed[int(raw)]
                geom = polygonal(feat.GetGeometryRef())
                if geom is None:
                    continue
                witnesses.update(geom, n)
                for win, mask in geometry_windows(geom, canvas):
                    level = mask.astype(np.uint8) * np.uint8(covered)
                    for slot_index, threshold in enumerate(thresholds):
                        if n >= threshold:
                            layers.merge_level(service, slot_index, win, level, self.country_code)
                    burned += int(mask.sum())
                    outside += int((mask & ~layers.country_mask(win, self.country_code)).sum())
                features += 1
                by_value[n] = by_value.get(n, 0) + 1
            ds = None
        print(f"    {features} entités rastérisées, {burned:,} pixels allumés dont {outside:,} hors du pays, par valeur {dict(sorted(by_value.items()))}".replace(",", " "), flush=True)
        if features == 0:
            raise RuntimeError(f"{self.source_id} : aucune entité rastérisée")
        ctx.stats.setdefault("pixels_hors_pays", {})[self.source_id] = outside
        for slot_index, (slot, threshold) in enumerate(zip(slots, thresholds)):
            witnesses.select(ctx, self.source_id, self.country_iso, service, slot_index, slot["id"], expected_of=lambda n, t=threshold: covered if n >= t else 0)
        layers.flush()
        date = self.data_date()
        return {"date": date[:7], "data_date": date}
