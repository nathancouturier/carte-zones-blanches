"""Écriture du manifest.json : il décrit les tuiles pour le décodeur du front."""

from __future__ import annotations

from typing import Any

from .context import BuildContext


def build_manifest(ctx: BuildContext, archives: list[dict[str, Any]], generated: str) -> dict[str, Any]:
    assert ctx.canvas is not None
    grid_cfg = ctx.cfg["grid"]
    west, south, east, north = ctx.canvas.lonlat_bounds
    countries = []
    for iso in ctx.countries:
        country = ctx.cfg["countries"][iso]
        sources = []
        for source_id in country["sources"]:
            scfg = ctx.cfg["sources"][source_id]
            info = ctx.source_info.get(source_id)
            if info is None:
                continue
            services = [s for s in ctx.services if s in scfg["services"]]
            entry: dict[str, Any] = {
                "type": int(scfg["type"]),
                "id": source_id,
                "name": scfg["name"],
                "url": scfg.get("url"),
                "date": info["date"],
                "licence": scfg["licence"],
                "licenceUrl": scfg.get("licence_url"),
                "attribution": scfg["attribution"],
                "services": services,
                "levels": scfg["levels_kind"],
                "levelMap": scfg.get("level_map", [0, 1, 2, 3]),
                "perOperator": int(scfg["type"]) != 1 and bool(scfg.get("per_operator", True)),
                "technology": {s: scfg["services"][s]["techno"] for s in services if "techno" in scfg["services"][s]},
            }
            if info.get("data_date"):
                entry["dataDate"] = info["data_date"]
            if scfg.get("resolution_m"):
                entry["resolutionM"] = scfg["resolution_m"]
            sources.append({k: v for k, v in entry.items() if v is not None})
        if not sources:
            continue
        countries.append(
            {
                "code": int(country["code"]),
                "iso": iso,
                "euRoaming": bool(country["eu_roaming"]),
                "slots": [{"id": s["id"], "name": s["name"]} for s in country.get("slots", [])],
                "sources": sources,
            }
        )
    manifest: dict[str, Any] = {
        "version": 1,
        "generated": generated,
        "scope": ctx.scope_name,
        "encoding": {
            "R": "internet mobile : 2 bits par emplacement d'opérateur (emplacement i sur les bits 2i et 2i+1)",
            "G": "appels et SMS : même encodage",
            "B": "bits 0 à 3 : code du pays ; bits 4 et 5 : type de source (0 officielle par opérateur, 1 officielle agrégée, 2 estimée)",
            "A": "255 dans la zone couverte par les données, 0 ailleurs",
            "levels": "0 pas de couverture, 1 couverture limitée, 2 bonne couverture, 3 très bonne couverture",
        },
        "tiles": {
            "size": int(grid_cfg["tile_size"]),
            "minzoom": int(grid_cfg["min_zoom"]),
            "maxzoom": int(grid_cfg["max_zoom"]),
            "format": "png",
        },
        "bounds": [round(west, 6), round(south, 6), round(east, 6), round(north, 6)],
        "archives": archives,
        "countries": countries,
    }
    if any("blocks" in a for a in archives):
        manifest["tiles"]["blockZoom"] = min(int(grid_cfg["block_zoom"]), int(grid_cfg["max_zoom"]))
    return manifest
