"""Le fichier SOURCES.md, qui accompagne les tuiles dans la release de données."""

from __future__ import annotations

from pathlib import Path

from czb.notices import sources_markdown

CONFIG = Path(__file__).resolve().parents[1] / "config.yaml"

MANIFEST = {
    "generated": "2026-11-14",
    "scope": "complet",
    "countries": [
        {
            "iso": "IT",
            "boundary": {"text": "Istat, CC BY 4.0", "url": "https://example.org/istat"},
            "sources": [
                {
                    "type": 1,
                    "name": "AGCOM, Broadband Map",
                    "url": "https://example.org/agcom",
                    "date": "2026-01",
                    "dataDate": "2026-01-27",
                    "licence": "CC BY 4.0",
                    "licenceUrl": "https://example.org/licence",
                    "attribution": "BroadbandMap di Agcom (CC BY 4.0)",
                    "licenceNotice": "BroadbandMap di Agcom è distribuito con Licenza CC BY 4.0.",
                }
            ],
        },
        {
            "iso": "AD",
            "boundary": {"text": "© OpenStreetMap contributors (ODbL 1.0)"},
            "sources": [{"type": 2, "name": "Estimation", "date": "2026-11", "licence": "CC BY-SA 4.0", "attribution": "OpenCellID"}],
        },
    ],
    "missing": [{"iso": "MC", "code": 6}],
}


def test_sources_markdown_carries_every_mention():
    text = sources_markdown(MANIFEST, {"IT": "Italie", "AD": "Andorre"})
    assert "## Italie (IT)" in text and "## Andorre (AD)" in text
    assert "- Source (officielle, agrégée) : AGCOM, Broadband Map (https://example.org/agcom)" in text
    # La date des données prime sur la date d'édition de la source.
    assert "  - Date des données : 2026-01-27" in text and "  - Date des données : 2026-11" in text
    assert "  - Licence : CC BY 4.0 (https://example.org/licence)" in text
    assert "  - Phrase imposée par la licence : BroadbandMap di Agcom è distribuito con Licenza CC BY 4.0." in text
    assert "- Contour du pays : Istat, CC BY 4.0 (https://example.org/istat)" in text
    assert "- Contour du pays : © OpenStreetMap contributors (ODbL 1.0)" in text
    assert "- Source (estimée) : Estimation" in text
    # Un pays sans nom connu garde son code, et un pays sans données est signalé.
    assert "source indisponible) : MC." in text


def test_texts_have_no_long_dash():
    """Règle du projet : ni tiret cadratin ni tiret demi-cadratin dans les textes publiés."""
    for text in (CONFIG.read_text(encoding="utf-8"), sources_markdown(MANIFEST)):
        assert chr(0x2014) not in text and chr(0x2013) not in text
