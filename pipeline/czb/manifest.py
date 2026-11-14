"""Écriture du manifest.json : il décrit les tuiles pour le décodeur du front."""

from __future__ import annotations

from typing import Any

from .context import BuildContext, check_translations


def _boundary(credit: dict[str, Any], iso: str) -> dict[str, Any]:
    """Mention du contour d'un pays (texte, lien), avec la traduction du texte s'il contient du français (textI18n)."""
    out = {k: v for k, v in credit.items() if k != "text_i18n"}
    if "text_i18n" in credit:
        out["textI18n"] = check_translations(credit["text_i18n"], f"countries.{iso}.mask.credit.text_i18n")
    return out


def _slot(slot: dict[str, Any]) -> dict[str, Any]:
    """Un emplacement : un opérateur nommé, ou un seuil « au moins N opérateurs » pour une source agrégée."""
    out: dict[str, Any] = {"id": slot["id"]}
    if "name" in slot:
        out["name"] = slot["name"]
    if "min_operators" in slot:
        out["minOperators"] = int(slot["min_operators"])
    if "name" not in out and "minOperators" not in out:
        raise ValueError(f"emplacement {slot['id']} : il faut un nom d'opérateur ou un seuil min_operators")
    return out


def build_manifest(ctx: BuildContext, archives: list[dict[str, Any]], generated: str) -> dict[str, Any]:
    assert ctx.canvas is not None
    grid_cfg = ctx.cfg["grid"]
    west, south, east, north = ctx.canvas.lonlat_bounds
    countries = []
    for iso in ctx.countries:
        country = ctx.cfg["countries"][iso]
        sources = []
        for source_id in ctx.country_sources(iso):
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
                # Vrai si les emplacements se choisissent un par un (opérateurs, ou seuils d'une source agrégée).
                "perOperator": bool(scfg.get("per_operator", int(scfg["type"]) != 1)),
                "technology": {s: scfg["services"][s]["techno"] for s in services if "techno" in scfg["services"][s]},
            }
            # Traductions du nom et de la licence (es, ca, it, de) ; le site prend le français s'il n'y en a pas.
            for key, field in (("name_i18n", "nameI18n"), ("licence_i18n", "licenceI18n")):
                if key in scfg:
                    entry[field] = check_translations(scfg[key], f"sources.{source_id}.{key}")
            if info.get("data_date"):
                entry["dataDate"] = info["data_date"]
            # Source estimée : nombre de sites et de cellules sur lesquels repose l'estimation (absent s'il n'est pas connu).
            if info.get("estimation"):
                entry["estimation"] = {"sites": int(info["estimation"]["sites"]), "cells": int(info["estimation"]["cells"])}
            # Mentions que certaines licences demandent d'afficher telles quelles (logo de l'AGCOM, formule d'OpenCellID).
            if scfg.get("licence_notice"):
                entry["licenceNotice"] = scfg["licence_notice"]
            if scfg.get("licence_logo"):
                entry["licenceLogo"] = scfg["licence_logo"]
                if scfg.get("licence_logo_url"):
                    entry["licenceLogoUrl"] = scfg["licence_logo_url"]
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
                # Opérateurs du pays, pour l'affichage quand la source ne les distingue pas.
                **({"operators": list(country["operators"])} if country.get("operators") else {}),
                # Mention du contour du pays (source et licence), à afficher avec les sources.
                **({"boundary": _boundary(country["mask"]["credit"], iso)} if country.get("mask", {}).get("credit") else {}),
                "slots": [_slot(s) for s in country.get("slots", [])],
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
            # Un pays peut déclarer moins de 4 emplacements (la Suisse 2, l'Andorre et Monaco 1) : on dit ce que valent les autres.
            "slots": "l'emplacement i (à partir de 0) est le i-ème élément de la liste « slots » du pays ; au-delà de cette liste, l'emplacement est inutilisé et vaut toujours 0",
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
    # Pays du périmètre laissés de côté faute de source disponible (clé d'accès absente) : le site peut le dire.
    missing = [iso for iso in ctx.scope["countries"] if iso not in ctx.countries]
    if missing:
        manifest["missing"] = [{"iso": iso, "code": int(ctx.cfg["countries"][iso]["code"])} for iso in ctx.cfg["countries"] if iso in missing]
    if any("blocks" in a for a in archives):
        manifest["tiles"]["blockZoom"] = min(int(grid_cfg["block_zoom"]), int(grid_cfg["max_zoom"]))
    return manifest
