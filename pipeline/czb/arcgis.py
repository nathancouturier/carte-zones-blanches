"""Lecture d'une couche d'un service ArcGIS REST public (requêtes « query » en JSON).

Deux administrations (AGCOM en Italie, ministère espagnol) publient leur carte de
couverture par ce type de service. On lit la couche page par page, par
identifiant croissant : c'est la seule pagination qui fonctionne sur les deux
serveurs (sur celui de l'AGCOM, resultOffset est ignoré sans message d'erreur).
Les requêtes sont faites l'une après l'autre, avec une pause entre deux pages.
"""

from __future__ import annotations

import json
import time
import urllib.parse
from pathlib import Path
from typing import Any, Iterator

from .net import fetch_bytes


def _url(base: str, params: dict[str, Any]) -> str:
    return base + ("&" if "?" in base else "?") + urllib.parse.urlencode({k: str(v) for k, v in params.items()})


def get_json(url: str, params: dict[str, Any] | None = None, timeout: int = 180) -> dict[str, Any]:
    """Lit une réponse JSON du service. Une réponse {"error": ...} lève une erreur (le service répond alors 200)."""
    full = _url(url, {**(params or {}), "f": "json"})
    data = json.loads(fetch_bytes(full, timeout=timeout, gzip_ok=True).decode("utf-8"))
    if isinstance(data, dict) and "error" in data:
        raise RuntimeError(f"le service ArcGIS répond par une erreur à {full[:300]} : {json.dumps(data['error'], ensure_ascii=False)[:300]}")
    return data


def count(query_url: str, where: str) -> int:
    data = get_json(query_url, {"where": where, "returnCountOnly": "true"})
    if "count" not in data:
        raise RuntimeError(f"réponse sans « count » pour {query_url} ({where})")
    return int(data["count"])


def pages(
    query_url: str,
    where: str,
    out_fields: list[str],
    oid_field: str,
    page_size: int,
    workdir: Path,
    extra: dict[str, Any] | None = None,
    pause_s: float = 0.5,
    expected: int | None = None,
) -> Iterator[Path]:
    """Écrit chaque page de la couche dans un fichier JSON temporaire et donne son chemin.

    Le fichier est supprimé dès que l'appelant demande la page suivante. La boucle
    s'arrête quand une page compte moins de page_size entités. Si « expected »
    est donné, le nombre d'identifiants distincts lus doit lui être égal.
    """
    workdir.mkdir(parents=True, exist_ok=True)
    last = 0
    seen = 0
    index = 0
    while True:
        params = {
            "where": f"({where}) AND {oid_field} > {last}",
            "outFields": ",".join(out_fields),
            "returnGeometry": "true",
            "orderByFields": oid_field,
            "resultRecordCount": page_size,
            **(extra or {}),
            "f": "json",
        }
        raw = fetch_bytes(_url(query_url, params), timeout=300, gzip_ok=True)
        data = json.loads(raw.decode("utf-8"))
        if "error" in data:
            raise RuntimeError(f"le service ArcGIS répond par une erreur (page {index}, {oid_field} > {last}) : {json.dumps(data['error'], ensure_ascii=False)[:300]}")
        features = data.get("features")
        if features is None:
            raise RuntimeError(f"réponse sans « features » (page {index}, {oid_field} > {last})")
        if not features:
            break
        ids = [f["attributes"][oid_field] for f in features]
        if any(b <= a for a, b in zip([last] + ids, ids)):
            # Le serveur n'a pas respecté le tri ou le filtre : on ne peut plus paginer sans risque de trou ou de doublon.
            raise RuntimeError(f"identifiants non croissants dans la page {index} ({oid_field} > {last}) : pagination impossible")
        path = workdir / f"page-{index:05d}.json"
        path.write_bytes(raw)
        try:
            yield path
        finally:
            path.unlink(missing_ok=True)
        seen += len(ids)
        last = ids[-1]
        index += 1
        if len(ids) < page_size:
            break
        time.sleep(pause_s)
    if expected is not None and seen != expected:
        raise RuntimeError(f"{seen} entités lues, {expected} attendues ({where})")
