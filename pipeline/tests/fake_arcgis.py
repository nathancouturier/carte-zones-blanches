"""Faux serveur ArcGIS REST pour les tests : il répond comme les services de l'AGCOM et du ministère espagnol.

Il ne comprend que ce que les modules envoient : returnCountOnly, un filtre « CHAMP IN (...) » ou
« CHAMP='valeur' », « CHAMP<>'' », « OID > n », orderByFields, resultRecordCount. Comme le serveur de
l'AGCOM, il ignore resultOffset. Il compresse ses réponses en gzip quand le client l'accepte.
"""

from __future__ import annotations

import gzip
import json
import re
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


class Layer:
    def __init__(self, oid_field: str, wkid: int, features: list[dict[str, Any]], max_records: int = 1000, info: dict[str, Any] | None = None):
        #: description de la couche, servie à l'adresse de la couche elle-même (sans /query)
        self.info = info
        self.oid_field = oid_field
        self.wkid = wkid
        self.features = sorted(features, key=lambda f: f["attributes"][oid_field])
        self.max_records = max_records
        self.requests = 0

    def select(self, where: str) -> list[dict[str, Any]]:
        out = self.features
        for field, values in re.findall(r"(\w+)\s+IN\s*\(([^)]*)\)", where):
            wanted = {v.strip().strip("'") for v in values.split(",")}
            out = [f for f in out if str(f["attributes"].get(field)).removesuffix(".0") in wanted]
        for field, value in re.findall(r"(\w+)\s*=\s*'([^']*)'", where):
            out = [f for f in out if str(f["attributes"].get(field)) == value]
        for field in re.findall(r"(\w+)\s*<>\s*''", where):
            out = [f for f in out if f["attributes"].get(field)]
        for field, value in re.findall(r"(\w+)\s*>\s*(\d+)", where):
            out = [f for f in out if f["attributes"][field] > int(value)]
        return out

    def query(self, params: dict[str, str]) -> dict[str, Any]:
        self.requests += 1
        where = params.get("where", "1=1")
        rows = self.select(where)
        if params.get("returnCountOnly") == "true":
            return {"count": len(rows)}
        limit = min(int(params.get("resultRecordCount", self.max_records)), self.max_records)
        rows = rows[:limit]
        fields = [f.strip() for f in params.get("outFields", "*").split(",")]
        features = []
        for row in rows:
            attributes = row["attributes"] if fields == ["*"] else {k: v for k, v in row["attributes"].items() if k in fields}
            feature: dict[str, Any] = {"attributes": attributes}
            if params.get("returnGeometry", "true") != "false" and "rings" in row:
                feature["geometry"] = {"rings": row["rings"]}
            features.append(feature)
        return {
            "objectIdFieldName": self.oid_field,
            "geometryType": "esriGeometryPolygon",
            "spatialReference": {"wkid": self.wkid, "latestWkid": self.wkid},
            "fields": [{"name": self.oid_field, "type": "esriFieldTypeOID", "alias": self.oid_field}]
            + [{"name": k, "type": "esriFieldTypeString" if isinstance(v, str) else "esriFieldTypeInteger", "alias": k} for k, v in (rows[0]["attributes"].items() if rows else []) if k != self.oid_field and (fields == ["*"] or k in fields)],
            "features": features,
        }


class FakeArcgis:
    """Serveur local. routes : chemin -> Layer (répond sur <chemin>/query) ou dict (réponse JSON fixe)."""

    def __init__(self, routes: dict[str, Any]):
        self.routes = routes
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args: Any) -> None:  # silence
                return

            def do_GET(self) -> None:
                parsed = urllib.parse.urlparse(self.path)
                params = {k: v[0] for k, v in urllib.parse.parse_qs(parsed.query, keep_blank_values=True).items()}
                path = parsed.path.rstrip("/")
                body: Any = None
                if path.endswith("/query") and isinstance(fake.routes.get(path[: -len("/query")]), Layer):
                    body = fake.routes[path[: -len("/query")]].query(params)
                elif isinstance(fake.routes.get(path), Layer):
                    body = fake.routes[path].info
                elif path in fake.routes:
                    body = fake.routes[path]
                if body is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                raw = json.dumps(body).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                if "gzip" in (self.headers.get("Accept-Encoding") or ""):
                    raw = gzip.compress(raw)
                    self.send_header("Content-Encoding", "gzip")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.server.server_address[1]}"

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()


def box_ring(x0: float, y0: float, x1: float, y1: float) -> list[list[float]]:
    """Anneau extérieur d'un rectangle, dans le sens des aiguilles d'une montre (convention ESRI)."""
    return [[x0, y0], [x0, y1], [x1, y1], [x1, y0], [x0, y0]]
