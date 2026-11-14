"""État des sources enregistré dans la dernière release de données (GitHub)."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any

from .net import USER_AGENT

API = "https://api.github.com"
RELEASE_PREFIX = "data-"
STATE_ASSET = "etat-sources.json"


def _get(url: str, accept: str = "application/vnd.github+json") -> bytes:
    headers = {"User-Agent": USER_AGENT, "Accept": accept}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as resp:
        return resp.read()


def latest_data_release(repo: str) -> dict[str, Any] | None:
    """Release de données la plus récente (étiquette data-AAAA-MM-JJ), ou None."""
    try:
        releases = json.loads(_get(f"{API}/repos/{repo}/releases?per_page=50"))
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        raise
    candidates = [r for r in releases if r["tag_name"].startswith(RELEASE_PREFIX) and not r["draft"]]
    if not candidates:
        return None
    # Par date de publication : « created_at » est la date du commit étiqueté, pas celle de la release.
    return max(candidates, key=lambda r: r.get("published_at") or "")


def latest_release_state(repo: str) -> tuple[str | None, dict[str, Any] | None]:
    release = latest_data_release(repo)
    if release is None:
        return None, None
    for asset in release.get("assets", []):
        if asset["name"] == STATE_ASSET:
            data = _get(asset["url"], accept="application/octet-stream")
            return release["tag_name"], json.loads(data)
    return release["tag_name"], None


def write_github_output(values: dict[str, str]) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as f:
        for key, value in values.items():
            f.write(f"{key}={value}\n")
