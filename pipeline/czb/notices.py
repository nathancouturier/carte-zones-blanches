"""Mentions des sources et des licences, en clair, pour accompagner les tuiles publiées.

Les tuiles sont des données dérivées : chaque licence demande que la source, sa date et, parfois, une
phrase précise suivent les données là où elles sont redistribuées. Le manifest les contient déjà pour le
site ; ce fichier les redit pour une personne qui ouvre la release de données. Il dit aussi ce que le
pipeline a fait des données (l'indication de modification que demandent les licences CC BY), et les
logos que certaines licences exigent dans toute œuvre dérivée partent avec les données.
"""

from __future__ import annotations

import shutil
from pathlib import Path
from typing import Any

SOURCE_TYPES = {0: "officielle, par opérateur", 1: "officielle, agrégée", 2: "estimée"}
LEVELS = {"four": "quatre niveaux de couverture", "three": "trois niveaux de couverture"}

#: Fichiers statiques du site : les logos de licence y sont rangés (clé licence_logo de config.yaml, chemin relatif).
PUBLIC_DIR = Path(__file__).resolve().parents[2] / "public"


def _link(text: str | None, url: str | None) -> str:
    if text and url:
        return f"{text} ({url})"
    return text or url or ""


def _changes(source: dict[str, Any], country: dict[str, Any], zoom: int | None) -> str:
    """Ce que le pipeline a fait des données de la source, en une phrase."""
    grid = f"la grille commune des tuiles (EPSG:3857, pixels du zoom {zoom})" if zoom is not None else "la grille commune des tuiles (EPSG:3857)"
    levels = LEVELS.get(source.get("levels"), "niveaux de couverture")
    if int(source["type"]) == 2:
        return f"couverture estimée à partir de ces données (antennes regroupées en sites, visibilité calculée sur le relief) sur {grid}, en {levels}"
    thresholds = [str(slot["minOperators"]) for slot in country.get("slots", []) if "minOperators" in slot]
    if thresholds:
        result = f"ramenées à des seuils de nombre d'opérateurs (au moins {', '.join(thresholds)})"
    elif source.get("levels") == "binary":
        result = "ramenées, pour chaque opérateur, à couvert ou non couvert"
    else:
        result = f"ramenées à {levels}"
    return f"données rastérisées sur {grid}, puis {result}"


def sources_markdown(manifest: dict[str, Any], names: dict[str, str] | None = None) -> str:
    """Le texte de SOURCES.md, tiré du manifest (`names` : nom des pays, à défaut le code ISO)."""
    names = names or {}
    zoom = (manifest.get("tiles") or {}).get("maxzoom")
    lines = [
        "# Sources et licences des données de couverture",
        "",
        f"Tuiles générées le {manifest['generated']}, périmètre « {manifest['scope']} ».",
        "",
        "Ces tuiles sont des données dérivées des sources ci-dessous. Chaque pays garde la licence de sa source :",
        "toute réutilisation doit reprendre la mention de la source, sa date et les phrases imposées.",
        "",
    ]
    for country in manifest["countries"]:
        iso = country["iso"]
        lines += [f"## {names.get(iso, iso)} ({iso})", ""]
        for source in country["sources"]:
            kind = SOURCE_TYPES.get(int(source["type"]), str(source["type"]))
            lines.append(f"- Source ({kind}) : {_link(source['name'], source.get('url'))}")
            date = source.get("dataDate") or source.get("date")
            if date:
                lines.append(f"  - Date des données : {date}")
            lines.append(f"  - Licence : {_link(source['licence'], source.get('licenceUrl'))}")
            lines.append(f"  - Mention : {source['attribution']}")
            if source.get("licenceNotice"):
                lines.append(f"  - Phrase imposée par la licence : {source['licenceNotice']}")
            if source.get("licenceLogo"):
                logo = Path(source["licenceLogo"]).name
                link = f" (lien du logo : {source['licenceLogoUrl']})" if source.get("licenceLogoUrl") else ""
                lines.append(f"  - Logo exigé par la licence dans toute œuvre dérivée : {logo}, joint à ces données{link}")
            lines.append(f"  - Modifications : {_changes(source, country, zoom)}.")
        boundary = country.get("boundary")
        if boundary:
            lines.append(f"- Contour du pays : {_link(boundary.get('text'), boundary.get('url'))}")
        lines.append("")
    missing = manifest.get("missing") or []
    if missing:
        listed = ", ".join(names.get(m["iso"], m["iso"]) for m in missing)
        lines += [f"Pays du périmètre sans données dans cette édition (source indisponible) : {listed}.", ""]
    return "\n".join(lines)


def copy_licence_logos(manifest: dict[str, Any], outdir: Path, public_dir: Path = PUBLIC_DIR) -> list[str]:
    """Copie dans outdir, sous son nom de fichier, le logo de chaque source qui en a un. Renvoie les noms copiés.

    La licence de l'AGCOM exige son logo dans toute œuvre dérivée : il part avec les données publiées. Un logo
    introuvable arrête la construction plutôt que de publier des données sans lui.
    """
    copied: dict[str, str] = {}
    for country in manifest["countries"]:
        for source in country["sources"]:
            logo = source.get("licenceLogo")
            if not logo:
                continue
            name = Path(logo).name
            if copied.get(name, logo) != logo:
                raise RuntimeError(f"deux logos de licence portent le même nom de fichier : {copied[name]} et {logo}")
            path = public_dir / logo
            if not path.is_file():
                raise RuntimeError(f"logo de licence introuvable : {path} (licence_logo de la source {source['id']})")
            shutil.copyfile(path, outdir / name)
            copied[name] = logo
    return list(copied)
