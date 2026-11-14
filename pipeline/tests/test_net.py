"""Téléchargements : une réponse coupée en route doit être refusée, pas acceptée en silence."""

from __future__ import annotations

import socket
import threading
from pathlib import Path

import pytest

from czb import net


def _serve(responses: list[bytes]) -> tuple[str, threading.Thread]:
    """Serveur minimal : répond à chaque connexion par la réponse brute suivante, puis ferme."""
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    sock.listen(8)

    def run() -> None:
        for raw in responses:
            conn, _ = sock.accept()
            conn.recv(65536)
            conn.sendall(raw)
            conn.close()
        sock.close()

    thread = threading.Thread(target=run, daemon=True)
    thread.start()
    return f"http://127.0.0.1:{sock.getsockname()[1]}/fichier", thread


def _response(body: bytes, announced: int | None = None, status: str = "200 OK") -> bytes:
    length = len(body) if announced is None else announced
    return f"HTTP/1.1 {status}\r\nContent-Length: {length}\r\nConnection: close\r\n\r\n".encode() + body


@pytest.fixture(autouse=True)
def _local(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("no_proxy", "127.0.0.1,localhost")
    monkeypatch.setenv("NO_PROXY", "127.0.0.1,localhost")
    monkeypatch.setattr(net.time, "sleep", lambda s: None)


def test_truncated_download_is_retried(tmp_path: Path):
    body = b"x" * 5000
    url, _ = _serve([_response(body[:1000], announced=5000), _response(body)])
    dest = net.download(url, tmp_path / "f.bin", tries=2)
    assert dest is not None and dest.read_bytes() == body


def test_truncated_download_fails_when_every_try_is_cut(tmp_path: Path):
    url, _ = _serve([_response(b"abc", announced=10)] * 2)
    with pytest.raises(RuntimeError, match="échec du téléchargement"):
        net.download(url, tmp_path / "f.bin", tries=2)
    assert not (tmp_path / "f.bin").exists() and not (tmp_path / "f.bin.part").exists()


def test_fetch_bytes_retries_a_truncated_answer():
    url, _ = _serve([_response(b"abc", announced=10), _response(b"complet")])
    assert net.fetch_bytes(url, tries=2) == b"complet"


def test_missing_file_is_not_an_error_when_allowed(tmp_path: Path):
    url, _ = _serve([_response(b"", status="404 Not Found")])
    assert net.download(url, tmp_path / "f.bin", missing_ok=True) is None
    assert net.download((tmp_path / "absent.tif").as_uri(), tmp_path / "g.bin", missing_ok=True) is None
    # Sans cette option, un fichier absent reste une erreur ; une autre erreur aussi, même avec l'option.
    url, _ = _serve([_response(b"", status="503 Service Unavailable")] * 2)
    with pytest.raises(RuntimeError):
        net.download(url, tmp_path / "h.bin", tries=2, missing_ok=True)
