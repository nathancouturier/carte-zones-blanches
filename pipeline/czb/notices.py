"""Mentions des sources et des licences, en clair, pour accompagner les tuiles publiées.

Les tuiles sont des données dérivées : chaque licence demande que la source, sa date et, parfois, une
phrase précise suivent les données là où elles sont redistribuées. Le manifest les contient déjà pour le
site ; ce fichier les redit pour une personne qui ouvre la release de données.
"""

from __future__ import annotations

from typing import Any

SOURCE_TYPES = {0: "officielle, par opérateur", 1: "officielle, agrégée", 2: "estimée"}


def _link(text: str | None, url: str | None) -> str:
    if text and url:
        return f"{text} ({url})"
    return text or url or ""


def sources_markdown(manifest: dict[str, Any], names: dict[str, str] | None = None) -> str:
    """Le texte de SOURCES.md, tiré du manifest (`names` : nom des pays, à défaut le code ISO)."""
    names = names or {}
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
        boundary = country.get("boundary")
        if boundary:
            lines.append(f"- Contour du pays : {_link(boundary.get('text'), boundary.get('url'))}")
        lines.append("")
    missing = manifest.get("missing") or []
    if missing:
        listed = ", ".join(names.get(m["iso"], m["iso"]) for m in missing)
        lines += [f"Pays du périmètre sans données dans cette édition (source indisponible) : {listed}.", ""]
    return "\n".join(lines)
