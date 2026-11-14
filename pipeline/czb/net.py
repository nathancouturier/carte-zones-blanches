"""Téléchargements et décompression."""

from __future__ import annotations

import gzip
import http.client
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

USER_AGENT = "carte-zones-blanches/1.0 (+https://github.com/nathancouturier/carte-zones-blanches)"


#: Erreurs qui méritent un nouvel essai : coupure, délai dépassé, réponse incomplète.
RETRYABLE = (urllib.error.URLError, TimeoutError, ConnectionError, OSError, EOFError, http.client.HTTPException)


class IncompleteDownload(OSError):
    """Le serveur a fermé la connexion avant d'avoir tout envoyé."""


def _check_length(resp: object, received: int) -> None:
    """Compare le nombre d'octets reçus à celui que le serveur avait annoncé (Content-Length)."""
    headers = getattr(resp, "headers", None)
    announced = headers.get("Content-Length") if headers is not None else None
    if announced is not None and announced.strip().isdigit() and int(announced) != received:
        raise IncompleteDownload(f"réponse incomplète : {received} octets reçus sur {announced} annoncés")


def _request(url: str, gzip_ok: bool = False) -> urllib.request.Request:
    headers = {"User-Agent": USER_AGENT}
    if gzip_ok:
        headers["Accept-Encoding"] = "gzip"
    return urllib.request.Request(url, headers=headers)


def fetch_text(url: str, tries: int = 4, timeout: int = 120) -> str:
    return fetch_bytes(url, tries, timeout).decode("utf-8", errors="replace")


def fetch_bytes(url: str, tries: int = 4, timeout: int = 120, gzip_ok: bool = False) -> bytes:
    """Lit une URL en mémoire. Avec gzip_ok, demande une réponse compressée et la décompresse."""
    last: Exception | None = None
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(_request(url, gzip_ok), timeout=timeout) as resp:
                data = resp.read()
                _check_length(resp, len(data))
                if gzip_ok and (resp.headers.get("Content-Encoding") or "").lower() == "gzip":
                    data = gzip.decompress(data)
                return data
        except RETRYABLE as exc:
            last = exc
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"échec du téléchargement de {url} : {last}")


def download(url: str, dest: Path, tries: int = 4, timeout: int = 300, missing_ok: bool = False) -> Path | None:
    """Télécharge un fichier (éventuellement une URL file://) vers dest.

    Avec missing_ok, un fichier absent (erreur 404, ou fichier local inexistant) renvoie None sans nouvel essai.
    """
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    last: Exception | None = None
    for attempt in range(tries):
        try:
            t0 = time.time()
            with urllib.request.urlopen(_request(url), timeout=timeout) as resp, open(tmp, "wb") as out:
                shutil.copyfileobj(resp, out, length=4 * 1024 * 1024)
                out.flush()
                _check_length(resp, out.tell())
            tmp.replace(dest)
            size = dest.stat().st_size
            print(f"    téléchargé {dest.name} : {size / 1e6:.1f} Mo en {time.time() - t0:.0f} s", flush=True)
            return dest
        except RETRYABLE as exc:
            last = exc
            tmp.unlink(missing_ok=True)
            absent = (isinstance(exc, urllib.error.HTTPError) and exc.code == 404) or isinstance(getattr(exc, "reason", None), FileNotFoundError)
            if missing_ok and absent:
                return None
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
