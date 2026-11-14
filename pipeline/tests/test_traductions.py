"""Textes du manifest que le site affiche tels quels : traductions (es, ca, it, de) et textes sans langue.

Le français reste dans « name », « licence » et « credit.text » ; les traductions sont dans « name_i18n »,
« licence_i18n » et « credit.text_i18n », recopiées dans le manifest (nameI18n, licenceI18n, boundary.textI18n).
"""

from __future__ import annotations

import copy
from pathlib import Path

import pytest
import yaml

from czb.context import LANGUAGES, load_config

CONFIG = Path(__file__).resolve().parents[1] / "config.yaml"


@pytest.fixture(scope="module")
def cfg() -> dict:
    return load_config(CONFIG)


def test_french_texts_of_the_sources_are_translated(cfg: dict):
    sources = cfg["sources"]
    assert sorted(s for s, v in sources.items() if "name_i18n" in v) == ["ad_estimation", "ch_bakom", "fr_arcep", "it_agcom", "mc_estimation"]
    assert sorted(s for s, v in sources.items() if "licence_i18n" in v) == ["ad_estimation", "ch_bakom", "es_mtd", "mc_estimation"]
    assert sorted(iso for iso, c in cfg["countries"].items() if "text_i18n" in c["mask"]["credit"]) == ["FR", "IT"]
    translations = [v[key] for v in sources.values() for key in ("name_i18n", "licence_i18n") if key in v]
    translations += [c["mask"]["credit"]["text_i18n"] for c in cfg["countries"].values() if "text_i18n" in c["mask"]["credit"]]
    for item in translations:
        assert list(item) == list(LANGUAGES)
        for text in item.values():
            # Ponctuation de ces langues : pas d'espace avant les deux-points (le français en met une).
            assert " :" not in text, text


def test_proper_names_and_imposed_formulas_are_kept(cfg: dict):
    sources, countries = cfg["sources"], cfg["countries"]
    for lang in LANGUAGES:
        assert sources["fr_arcep"]["name_i18n"][lang].startswith("Arcep, Mon réseau mobile: ")
        # L'office suisse a un sigle par langue officielle : BAKOM en allemand, UFCOM en italien, OFCOM en français.
        assert sources["ch_bakom"]["name_i18n"][lang].startswith({"de": "BAKOM, ", "it": "UFCOM, "}.get(lang, "OFCOM, "))
        assert sources["it_agcom"]["name_i18n"][lang].startswith("AGCOM, Broadband Map: ")
        assert "OpenCellID" in sources["ad_estimation"]["name_i18n"][lang] and "Copernicus DEM" in sources["ad_estimation"]["name_i18n"][lang]
        assert sources["ad_estimation"]["licence_i18n"][lang].startswith("CC BY-SA 4.0 (")
        # Le titre des conditions du ministère reste en espagnol.
        assert sources["es_mtd"]["licence_i18n"][lang].startswith("Condiciones generales de reutilización del ministerio: ")
        assert countries["FR"]["mask"]["credit"]["text_i18n"][lang].startswith("Contours administratifs, data.gouv.fr (")
        assert countries["IT"]["mask"]["credit"]["text_i18n"][lang].startswith("Istat, Confini delle unità amministrative a fini statistici al 1° gennaio 2026, CC BY 4.0, ")
    # Les deux sources estimées partagent les réglages communs, traductions comprises.
    assert sources["mc_estimation"]["name_i18n"] == sources["ad_estimation"]["name_i18n"]
    # Formules imposées, noms propres : jamais traduits.
    assert "name_i18n" not in sources["es_mtd"]
    for iso, formula in (("CH", "©swisstopo, swissBOUNDARIES3D"), ("ES", "Obra derivada de BDLJE CC-BY 4.0 ign.es"), ("AD", "© OpenStreetMap contributors (ODbL 1.0)"), ("MC", "© OpenStreetMap contributors (ODbL 1.0)")):
        # Formule imposée : jamais traduite (la clé « lang » dit seulement dans quelle langue elle est écrite).
        credit = countries[iso]["mask"]["credit"]
        assert credit["text"] == formula and "text_i18n" not in credit and set(credit) <= {"text", "url", "lang"}


def test_texts_shown_as_they_are_have_no_french_word(cfg: dict):
    """Mention et technologie s'affichent sans traduction : elles ne contiennent aucun mot français."""
    for source_id in ("ad_estimation", "mc_estimation"):
        source = cfg["sources"][source_id]
        assert source["attribution"] == "OpenCellID (CC BY-SA 4.0), Copernicus DEM"
        assert source["services"]["data"]["techno"] == "4G, 5G"
    for source in cfg["sources"].values():
        assert "Estimation" not in source["attribution"]
        for service in source["services"].values():
            assert " et " not in str(service.get("techno", ""))


def test_incomplete_translation_is_refused(tmp_path: Path):
    """Toutes les langues ou aucune : une traduction incomplète, ou dans une langue inconnue, arrête la lecture de config.yaml."""
    base = yaml.safe_load(CONFIG.read_text(encoding="utf-8"))
    for broken in ({"es": "Uso libre"}, {**base["sources"]["ch_bakom"]["licence_i18n"], "en": "Free use"}, {**base["sources"]["ch_bakom"]["licence_i18n"], "de": " "}):
        cfg = copy.deepcopy(base)
        cfg["sources"]["ch_bakom"]["licence_i18n"] = broken
        path = tmp_path / "config.yaml"
        path.write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding="utf-8")
        with pytest.raises(ValueError, match="sources.ch_bakom.licence_i18n"):
            load_config(path)
    cfg = copy.deepcopy(base)
    cfg["countries"]["IT"]["mask"]["credit"]["text_i18n"].pop("ca")
    path.write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding="utf-8")
    with pytest.raises(ValueError, match="countries.IT.mask.credit.text_i18n"):
        load_config(path)


def test_imposed_mentions_carry_their_language(cfg: dict):
    """Les mentions écrites telles quelles disent leur langue : le site la donne aux lecteurs d'écran."""
    sources, countries = cfg["sources"], cfg["countries"]
    assert sources["it_agcom"]["mention_lang"] == "it"
    assert sources["es_mtd"]["mention_lang"] == "es"
    assert sources["ad_estimation"]["mention_lang"] == "en" and sources["mc_estimation"]["mention_lang"] == "en"
    assert countries["ES"]["mask"]["credit"]["lang"] == "es"
    assert countries["AD"]["mask"]["credit"]["lang"] == "en" and countries["MC"]["mask"]["credit"]["lang"] == "en"
