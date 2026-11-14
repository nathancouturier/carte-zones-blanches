"""Détection des nouvelles versions (commande « changed ») : état des sources en ligne contre celui de la dernière release.

Deux pays fictifs, chacun avec une source lue dans un catalogue STAC local (module de l'OFCOM) : aucun réseau.
La dernière release de données est simulée : son étiquette et son état des sources sont donnés par le test.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml

from czb import cli, release_state
from czb.context import load_config

TAG = "data-2026-11-14"


def _items(path: Path, datetime: str, updated: str) -> None:
    path.write_text(json.dumps({"features": [{"id": "x", "properties": {"datetime": datetime}, "assets": {"carte.tif": {"href": "file:///absent/carte.tif", "updated": updated, "proj:epsg": 2056}}}]}), encoding="utf-8")


def _source(country: str, items: Path) -> dict:
    return {
        "module": "ch_bakom",
        "country": country,
        "type": 1,
        "name": f"Source {country}",
        "attribution": "Test",
        "licence": "Utilisation libre",
        "stac_url": items.as_uri(),
        "services": {"data": {"techno": "4G", "collection": f"collection-{country.lower()}"}},
        "values": {0: 0, 2: 1, 3: 3},
        "covered_level": 2,
        "levels_kind": "binary",
    }


@pytest.fixture()
def setup(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> dict:
    base = yaml.safe_load((Path(__file__).resolve().parent.parent / "config.yaml").read_text(encoding="utf-8"))
    items = {"CH": tmp_path / "ch.json", "IT": tmp_path / "it.json"}
    _items(items["CH"], "2026-04-30T00:00:00Z", "2026-10-26T15:00:38Z")
    _items(items["IT"], "2026-01-27T00:00:00Z", "2026-02-01T08:00:00Z")
    slots = [{"id": "un", "min_operators": 1}]
    cfg = {
        "grid": base["grid"],
        "limits": base["limits"],
        "verification": base["verification"],
        "countries": {
            "CH": {"code": 2, "eu_roaming": False, "mask": {"type": "vector_file", "url": "file:///absent.gpkg"}, "slots": slots, "sources": ["src_ch"]},
            "IT": {"code": 3, "eu_roaming": True, "mask": {"type": "vector_file", "url": "file:///absent.gpkg"}, "slots": slots, "sources": ["src_it"]},
        },
        "sources": {"src_ch": _source("CH", items["CH"]), "src_it": _source("IT", items["IT"])},
        "scopes": {"tout": {"countries": ["CH", "IT"]}},
    }
    config = tmp_path / "config.yaml"
    config.write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding="utf-8")
    output = tmp_path / "github-output.txt"
    monkeypatch.setenv("GITHUB_OUTPUT", str(output))
    release: dict = {"tag": TAG, "state": None}
    monkeypatch.setattr(release_state, "latest_release_state", lambda repo: (release["tag"], release["state"]))
    return {"config": config, "items": items, "output": output, "release": release}


def _changed(setup: dict, *extra: str) -> tuple[str, str]:
    """Lance la commande et renvoie les deux valeurs écrites pour GitHub Actions (changed, reason)."""
    setup["output"].unlink(missing_ok=True)
    assert cli.main(["--config", str(setup["config"]), "changed", "--scope", "tout", "--services", "data", "--repo", "proprietaire/depot", *extra]) == 0
    values = dict(line.split("=", 1) for line in setup["output"].read_text(encoding="utf-8").splitlines())
    assert set(values) == {"changed", "reason"}
    return values["changed"], values["reason"]


def _current(setup: dict) -> dict:
    return json.loads(json.dumps(cli.remote_state(load_config(setup["config"]), "tout", ["data"])))


def test_nothing_changed(setup: dict, capsys: pytest.CaptureFixture[str]):
    setup["release"]["state"] = _current(setup)
    assert _changed(setup) == ("false", f"sources inchangées depuis {TAG}")
    assert f"changed=false (sources inchangées depuis {TAG})" in capsys.readouterr().out


def test_one_source_changed(setup: dict):
    previous = _current(setup)
    setup["release"]["state"] = previous
    # Nouvelle édition de la source italienne seulement : la construction se déclenche.
    _items(setup["items"]["IT"], "2026-07-31T00:00:00Z", "2026-08-05T08:00:00Z")
    current = _current(setup)
    assert current["sources"]["src_ch"] == previous["sources"]["src_ch"]
    assert current["sources"]["src_it"] != previous["sources"]["src_it"]
    assert _changed(setup) == ("true", f"changement depuis {TAG} : sources")


def test_pipeline_version_changed(setup: dict):
    previous = _current(setup)
    previous["pipeline"] = "0.0.9"  # la release a été construite par une autre version du pipeline
    setup["release"]["state"] = previous
    assert _changed(setup) == ("true", f"changement depuis {TAG} : pipeline")


def test_no_release(setup: dict):
    setup["release"].update(tag=None, state=None)
    assert _changed(setup) == ("true", "aucune release de données")
    # Une release sans état des sources (construite avant qu'il existe) : on reconstruit aussi.
    setup["release"].update(tag=TAG, state=None)
    assert _changed(setup) == ("true", f"la release {TAG} n'a pas d'état des sources")


def test_force(setup: dict):
    setup["release"]["state"] = _current(setup)
    assert _changed(setup, "--force") == ("true", "reconstruction forcée")
    # Sans l'option, la même situation ne reconstruit rien.
    assert _changed(setup)[0] == "false"
