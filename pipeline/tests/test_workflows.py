"""Workflow « Données » (.github/workflows/build-data.yml) : ce que les tests sur données synthétiques ne voient pas."""

from __future__ import annotations

from pathlib import Path

import yaml

WORKFLOW = Path(__file__).resolve().parents[2] / ".github" / "workflows" / "build-data.yml"


def test_site_redeploy_failure_is_not_hidden():
    """Après une release de données, le lancement de deploy.yml doit faire échouer l'étape s'il échoue."""
    workflow = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    steps = {step.get("name"): step for step in workflow["jobs"]["publier"]["steps"]}
    step = steps["Relancer le déploiement du site"]
    assert "gh workflow run deploy.yml" in step["run"]
    # Ni « || echo », ni « set +e », ni continue-on-error : l'échec doit rester visible.
    assert "||" not in step["run"] and "set +e" not in step["run"] and not step.get("continue-on-error")
