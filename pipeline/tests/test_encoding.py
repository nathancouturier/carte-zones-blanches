import numpy as np
import pytest

from czb.encoding import (
    compose_rgba,
    decode_png,
    encode_png,
    pack_meta,
    pack_slots,
    unpack_country,
    unpack_slot,
    unpack_source_type,
)


def test_pack_slots_roundtrip():
    for levels in ([0, 0, 0, 0], [3, 3, 3, 3], [1, 2, 3, 0], [3, 0, 1, 2]):
        byte = pack_slots(levels)
        assert [unpack_slot(byte, i) for i in range(4)] == levels
    assert pack_slots([1, 2, 3, 0]) == 0b00_11_10_01
    with pytest.raises(ValueError):
        pack_slots([4, 0, 0, 0])


def test_pack_meta_roundtrip():
    for country in range(16):
        for source_type in range(3):
            b = pack_meta(country, source_type)
            assert unpack_country(b) == country
            assert unpack_source_type(b) == source_type
    assert pack_meta(1, 0) == 1
    assert pack_meta(3, 2) == 0b10_0011


def test_png_is_lossless_palette_and_rgba():
    rng = np.random.default_rng(1)
    # Peu de valeurs distinctes : PNG en palette.
    few = rng.integers(0, 6, size=(256, 256, 4), dtype=np.uint8) * 40
    few[..., 3] = np.where(few[..., 3] > 100, 255, 0)
    assert np.array_equal(decode_png(encode_png(few)), few)
    # Beaucoup de valeurs distinctes : PNG RGBA.
    many = rng.integers(0, 256, size=(256, 256, 4), dtype=np.uint8)
    many[..., 3] = 255
    assert np.array_equal(decode_png(encode_png(many)), many)
    # Tuile uniforme : très petite.
    flat = np.zeros((256, 256, 4), dtype=np.uint8)
    flat[...] = (255, 0, 1, 255)
    data = encode_png(flat)
    assert len(data) < 200
    assert np.array_equal(decode_png(data), flat)


def test_compose_rgba_masks_outside():
    r = np.full((4, 4), 200, dtype=np.uint8)
    g = np.full((4, 4), 100, dtype=np.uint8)
    b = np.zeros((4, 4), dtype=np.uint8)
    b[1:3, 1:3] = pack_meta(1, 0)
    rgba = compose_rgba(r, g, b)
    assert (rgba[0, 0] == (0, 0, 0, 0)).all()
    assert (rgba[1, 1] == (200, 100, 1, 255)).all()
