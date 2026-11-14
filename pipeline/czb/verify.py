"""Test de cohérence : la source contre les pixels décodés du PMTiles.

Pendant la construction, des points sont tirés au hasard et leur niveau est lu
directement dans la source (test géométrique exact). Ici on relit ces mêmes
points dans les archives PMTiles finales. Le moindre écart fait échouer le job.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from pmtiles.reader import MmapSource, Reader

from .encoding import decode_png, unpack_country, unpack_slot

CHANNEL_INDEX = {"data": 0, "voice": 1}


def archive_for_tile(manifest: dict[str, Any], z: int, x: int, y: int) -> dict[str, Any] | None:
    """Même règle que src/coverage/manifest.ts : le protocole choisit l'archive selon z, x et y."""
    block_zoom = manifest["tiles"].get("blockZoom")
    for archive in manifest["archives"]:
        if not archive["minzoom"] <= z <= archive["maxzoom"]:
            continue
        if "blocks" not in archive:
            return archive
        if block_zoom is None or z < block_zoom:
            continue
        shift = z - block_zoom
        if f"{x >> shift}/{y >> shift}" in archive["blocks"]:
            return archive
    return None


class TileReader:
    def __init__(self, outdir: Path, manifest: dict[str, Any]):
        self.outdir, self.manifest = Path(outdir), manifest
        self._readers: dict[str, tuple[Any, Reader]] = {}
        self._tiles: dict[tuple[int, int, int], Any] = {}

    def _reader(self, name: str) -> Reader:
        if name not in self._readers:
            f = open(self.outdir / name, "rb")
            self._readers[name] = (f, Reader(MmapSource(f)))
        return self._readers[name][1]

    def tile(self, z: int, x: int, y: int) -> Any:
        key = (z, x, y)
        if key not in self._tiles:
            archive = archive_for_tile(self.manifest, z, x, y)
            data = self._reader(archive["file"]).get(z, x, y) if archive else None
            self._tiles[key] = decode_png(data) if data else None
        return self._tiles[key]

    def close(self) -> None:
        for f, _ in self._readers.values():
            f.close()


def verify(outdir: Path) -> int:
    outdir = Path(outdir)
    manifest = json.loads((outdir / "manifest.json").read_text(encoding="utf-8"))
    witnesses = json.loads((outdir / "temoins.json").read_text(encoding="utf-8"))
    codes = {c["iso"]: c["code"] for c in manifest["countries"]}
    reader = TileReader(outdir, manifest)
    errors: list[str] = []
    checked: dict[tuple[str, str, int], int] = {}
    try:
        for w in witnesses:
            tile = reader.tile(w["z"], w["x"], w["y"])
            where = f"{w['source']} {w['service']} {w['operator']} tuile {w['z']}/{w['x']}/{w['y']} pixel ({w['px']}, {w['py']}) lon {w['lon']} lat {w['lat']}"
            if tile is None:
                errors.append(f"tuile absente : {where}")
                continue
            r, g, b, a = (int(v) for v in tile[w["py"], w["px"]])
            if a != 255 or unpack_country(b) != codes[w["country"]]:
                errors.append(f"pixel hors du pays attendu (B={b}, A={a}) : {where}")
                continue
            got = unpack_slot((r, g)[CHANNEL_INDEX[w["service"]]], w["slot"])
            if got != w["expected"]:
                errors.append(f"niveau lu {got}, attendu {w['expected']} : {where}")
            key = (w["source"], w["service"], w["expected"])
            checked[key] = checked.get(key, 0) + 1
    finally:
        reader.close()
    print(f"Test de cohérence : {len(witnesses)} points comparés entre les sources et les pixels décodés du PMTiles")
    for (source, service, level), n in sorted(checked.items()):
        print(f"   {source} {service} niveau {level} : {n} points")
    if not witnesses:
        print("ÉCHEC : aucun point témoin")
        return 1
    expected_path = outdir / "temoins-attendus.json"
    if expected_path.exists():
        counts: dict[tuple[str, str, int], int] = {}
        for w in witnesses:
            key = (w["source"], w["service"], int(w["slot"]))
            counts[key] = counts.get(key, 0) + 1
        for item in json.loads(expected_path.read_text(encoding="utf-8")):
            got = counts.get((item["source"], item["service"], int(item["slot"])), 0)
            if got < int(item["minimum"]):
                errors.append(f"trop peu de points témoins pour {item['source']} {item['service']} {item['operator']} : {got}, {item['minimum']} attendus au moins")
    if errors:
        print(f"ÉCHEC : {len(errors)} écart(s)")
        for line in errors[:50]:
            print("   " + line)
        return 1
    print("OK : aucun écart")
    return 0
