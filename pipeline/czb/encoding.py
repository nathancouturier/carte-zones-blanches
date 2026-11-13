"""Encodage des tuiles : les canaux portent des données, pas des couleurs.

  R : internet mobile, 2 bits par emplacement d'opérateur (4 emplacements)
  G : appels et SMS, même encodage
  B : bits 0 à 3 = pays, bits 4 et 5 = type de source
  A : 255 dans la zone couverte par les données, 0 ailleurs

Ce module est le pendant de src/coverage/codec.ts côté front.
"""

from __future__ import annotations

import io

import numpy as np
from PIL import Image

SLOT_COUNT = 4
LEVEL_NONE, LEVEL_LIMITED, LEVEL_GOOD, LEVEL_VERY_GOOD = 0, 1, 2, 3
SOURCE_OFFICIAL_OPERATOR, SOURCE_OFFICIAL_AGGREGATED, SOURCE_ESTIMATED = 0, 1, 2
CHANNEL_OF_SERVICE = {"data": "R", "voice": "G"}


def pack_slots(levels: list[int]) -> int:
    byte = 0
    for i in range(SLOT_COUNT):
        level = levels[i] if i < len(levels) else 0
        if not 0 <= level <= 3:
            raise ValueError(f"niveau invalide pour l'emplacement {i} : {level}")
        byte |= level << (2 * i)
    return byte


def unpack_slot(byte: int, slot: int) -> int:
    return (byte >> (2 * slot)) & 0b11


def pack_meta(country: int, source_type: int) -> int:
    if not 0 <= country <= 15:
        raise ValueError(f"code pays invalide : {country}")
    if not 0 <= source_type <= 3:
        raise ValueError(f"type de source invalide : {source_type}")
    return (source_type << 4) | country


def unpack_country(b: int) -> int:
    return b & 0x0F


def unpack_source_type(b: int) -> int:
    return (b >> 4) & 0b11


def compose_rgba(r: np.ndarray, g: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Assemble les trois canaux en image RGBA. Alpha vaut 255 là où un pays est défini."""
    inside = (b & 0x0F) != 0
    rgba = np.zeros(r.shape + (4,), dtype=np.uint8)
    rgba[..., 0] = np.where(inside, r, 0)
    rgba[..., 1] = np.where(inside, g, 0)
    rgba[..., 2] = np.where(inside, b, 0)
    rgba[..., 3] = np.where(inside, 255, 0)
    return rgba


def encode_png(rgba: np.ndarray) -> bytes:
    """Encode une tuile RGBA en PNG sans perte, en palette quand c'est possible (plus léger)."""
    rgba = np.ascontiguousarray(rgba, dtype=np.uint8)
    h, w, _ = rgba.shape
    flat = rgba.reshape(-1, 4).view(np.uint32).ravel()
    values, inverse = np.unique(flat, return_inverse=True)
    buf = io.BytesIO()
    if len(values) <= 256:
        palette = values.view(np.uint8).reshape(-1, 4)
        img = Image.fromarray(inverse.astype(np.uint8).reshape(h, w), mode="P")
        img.putpalette(palette[:, :3].tobytes())
        params: dict = {"optimize": True}
        if (palette[:, 3] != 255).any():
            params["transparency"] = bytes(palette[:, 3].tolist())
        n = len(values)
        if n <= 2:
            params["bits"] = 1
        elif n <= 4:
            params["bits"] = 2
        elif n <= 16:
            params["bits"] = 4
        img.save(buf, format="PNG", **params)
    else:
        Image.fromarray(rgba, mode="RGBA").save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def decode_png(data: bytes) -> np.ndarray:
    """Décode une tuile PNG en tableau RGBA (hauteur, largeur, 4)."""
    with Image.open(io.BytesIO(data)) as img:
        return np.asarray(img.convert("RGBA"), dtype=np.uint8)
