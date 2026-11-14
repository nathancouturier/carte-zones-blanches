"""Le fichier SOURCES.md, qui accompagne les tuiles dans la release de données."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from czb.notices import PUBLIC_DIR, copy_licence_logos, sources_markdown

CONFIG = Path(__file__).resolve().parents[1] / "config.yaml"

MANIFEST = {
    "generated": "2026-11-14",
    "scope": "complet",
    "tiles": {"size": 256, "minzoom": 0, "maxzoom": 12, "format": "png"},
    "countries": [
        {
            "iso": "IT",
            "boundary": {"text": "Istat, CC BY 4.0", "url": "https://example.org/istat"},
            "slots": [{"id": "it_1", "minOperators": 1}, {"id": "it_2", "minOperators": 2}],
            "sources": [
                {
                    "type": 1,
                    "id": "it_agcom",
                    "name": "AGCOM, Broadband Map",
                    "url": "https://example.org/agcom",
                    "date": "2026-01",
                    "dataDate": "2026-01-27",
                    "licence": "CC BY 4.0",
                    "licenceUrl": "https://example.org/licence",
                    "attribution": "BroadbandMap di Agcom (CC BY 4.0)",
                    "licenceNotice": "BroadbandMap di Agcom è distribuito con Licenza CC BY 4.0.",
                    "licenceLogo": "licences/logo-test.jpg",
                    "licenceLogoUrl": "https://example.org/portail",
                    "levels": "binary",
                }
            ],
        },
        {
            "iso": "ES",
            "slots": [{"id": "movistar", "name": "Movistar"}],
            "sources": [{"type": 0, "id": "es_mtd", "name": "Mapa", "date": "2024-06", "licence": "Condiciones", "attribution": "Ministerio", "levels": "binary"}],
        },
        {
            "iso": "FR",
            "slots": [{"id": "orange", "name": "Orange"}],
            "sources": [{"type": 0, "id": "fr_arcep", "name": "Arcep", "date": "2026-T2", "licence": "Licence Ouverte", "attribution": "Arcep", "levels": "four"}],
        },
        {
            "iso": "AD",
            "boundary": {"text": "© OpenStreetMap contributors (ODbL 1.0)"},
            "sources": [{"type": 2, "id": "ad_estimation", "name": "Estimation", "date": "2026-11", "licence": "CC BY-SA 4.0", "attribution": "OpenCellID", "levels": "three"}],
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


def test_sources_markdown_cites_the_logo_and_says_the_data_were_modified():
    """Licences CC BY : le logo exigé par l'AGCOM est cité avec son lien, et chaque source dit ce qui a été modifié."""
    text = sources_markdown(MANIFEST, {"IT": "Italie", "AD": "Andorre"})
    assert "  - Logo exigé par la licence dans toute œuvre dérivée : logo-test.jpg, joint à ces données (lien du logo : https://example.org/portail)" in text
    grid = "la grille commune des tuiles (EPSG:3857, pixels du zoom 12)"
    assert f"  - Modifications : données rastérisées sur {grid}, puis ramenées à des seuils de nombre d'opérateurs (au moins 1, 2)." in text
    assert f"  - Modifications : données rastérisées sur {grid}, puis ramenées, pour chaque opérateur, à couvert ou non couvert." in text
    assert f"  - Modifications : données rastérisées sur {grid}, puis ramenées à quatre niveaux de couverture." in text
    assert f"  - Modifications : couverture estimée à partir de ces données (antennes regroupées en sites, visibilité calculée sur le relief) sur {grid}, en trois niveaux de couverture." in text
    assert text.count("  - Modifications : ") == sum(len(c["sources"]) for c in MANIFEST["countries"])


def test_licence_logos_are_copied_with_the_data(tmp_path: Path):
    public, out = tmp_path / "public", tmp_path / "out"
    (public / "licences").mkdir(parents=True)
    out.mkdir()
    (public / "licences" / "logo-test.jpg").write_bytes(b"\xff\xd8logo")
    assert copy_licence_logos(MANIFEST, out, public) == ["logo-test.jpg"]
    assert (out / "logo-test.jpg").read_bytes() == b"\xff\xd8logo"
    # Sans le fichier, la construction s'arrête : des données de l'AGCOM sans son logo ne respectent pas la licence.
    (public / "licences" / "logo-test.jpg").unlink()
    with pytest.raises(RuntimeError, match="logo de licence introuvable"):
        copy_licence_logos(MANIFEST, tmp_path / "out2", public)


def test_every_licence_logo_of_the_configuration_exists():
    """Chaque licence_logo de config.yaml désigne un fichier du site (public/) : sinon la construction échouerait à la fin."""
    cfg = yaml.safe_load(CONFIG.read_text(encoding="utf-8"))
    logos = [s["licence_logo"] for s in cfg["sources"].values() if s.get("licence_logo")]
    assert logos == ["licences/agcom-bbmap.jpg"]
    assert all((PUBLIC_DIR / logo).is_file() for logo in logos)


def test_texts_have_no_long_dash():
    """Règle du projet : ni tiret cadratin ni tiret demi-cadratin dans les textes publiés."""
    for text in (CONFIG.read_text(encoding="utf-8"), sources_markdown(MANIFEST)):
        assert chr(0x2014) not in text and chr(0x2013) not in text
