"""Téléchargements et décompression."""

from __future__ import annotations

import gzip
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

USER_AGENT = "carte-zones-blanches/1.0 (+https://github.com/nathancouturier/carte-zones-blanches)"


def _request(url: str) -> urllib.request.Request:
    return urllib.request.Request(url, headers={"User-Agent": USER_AGENT})


def fetch_text(url: str, tries: int = 4, timeout: int = 120) -> str:
    return fetch_bytes(url, tries, timeout).decode("utf-8", errors="replace")


def fetch_bytes(url: str, tries: int = 4, timeout: int = 120) -> bytes:
    last: Exception | None = None
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(_request(url), timeout=timeout) as resp:
                return resp.read()
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            last = exc
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"échec du téléchargement de {url} : {last}")


def download(url: str, dest: Path, tries: int = 4, timeout: int = 300) -> Path:
    """Télécharge un fichier (éventuellement une URL file://) vers dest."""
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    last: Exception | None = None
    for attempt in range(tries):
        try:
            t0 = time.time()
            with urllib.request.urlopen(_request(url), timeout=timeout) as resp, open(tmp, "wb") as out:
                shutil.copyfileobj(resp, out, length=4 * 1024 * 1024)
            tmp.replace(dest)
            size = dest.stat().st_size
            print(f"    téléchargé {dest.name} : {size / 1e6:.1f} Mo en {time.time() - t0:.0f} s", flush=True)
            return dest
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as exc:
            last = exc
            tmp.unlink(missing_ok=True)
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"échec du téléchargement de {url} : {last}")


def extract_7z(archive: Path, dest_dir: Path) -> list[Path]:
    """Décompresse une archive 7z avec l'outil en ligne de commande et renvoie les fichiers extraits."""
    dest_dir = Path(dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)
    before = set(dest_dir.rglob("*"))
    exe = shutil.which("7z") or shutil.which("7zz") or shutil.which("7za")
    if exe is None:
        raise RuntimeError("7z est introuvable (paquet p7zip-full)")
    subprocess.run([exe, "x", "-y", f"-o{dest_dir}", str(archive)], check=True, stdout=subprocess.DEVNULL)
    return sorted(p for p in set(dest_dir.rglob("*")) - before if p.is_file())


def gunzip(src: Path, dest: Path) -> Path:
    with gzip.open(src, "rb") as fin, open(dest, "wb") as fout:
        shutil.copyfileobj(fin, fout, length=4 * 1024 * 1024)
    return dest
