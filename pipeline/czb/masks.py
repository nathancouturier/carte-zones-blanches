"""Masques de pays : quels pixels de la grille appartiennent à quel pays.

Chaque pays a son contour officiel (ou, à défaut, celui d'OpenStreetMap). Ces
contours viennent de producteurs différents et ne coïncident pas exactement le
long des frontières :

- là où deux contours se recouvrent, le pays le plus haut dans config.yaml garde le pixel ;
- les petits interstices fermés entre deux contours sont donnés au pays le moins
  prioritaire qui les touche (fonction fill_gaps), sinon un tracé qui passe la
  frontière traverserait quelques mètres « hors zone ».
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Any

from osgeo import ogr

from .context import BuildContext
from .grid import EARTH_RADIUS, Canvas, mercator_to_lonlat
from .net import download, gunzip
from .raster import geometry_windows, make_valid, transformer_to_mercator

#: Les trous fermés plus grands que ce seuil (en hectares au sol) sont de vraies enclaves ou des lacs : ils restent vides.
#: Mesuré sur les contours réels : le plus grand interstice fait 28,5 ha, la plus petite enclave 264 ha.
GAP_MAX_HA = 100.0
GAP_TOUCH_M = 0.01


def _load_etalab_departements(mask_cfg: dict[str, Any], scope: dict[str, Any], workdir: Path) -> list[ogr.Geometry]:
    """Contours des départements (Etalab). Champs utilisés : code, nom."""
    url = mask_cfg["url"]
    local = workdir / "departements.geojson"
    if not local.exists():
        if url.endswith(".gz"):
            gz = download(url, workdir / "departements.geojson.gz")
            gunzip(gz, local)
            gz.unlink(missing_ok=True)
        else:
            download(url, local)
    ds = ogr.Open(str(local))
    if ds is None:
        raise RuntimeError(f"impossible d'ouvrir {local}")
    layer = ds.GetLayer(0)
    names = [layer.GetLayerDefn().GetFieldDefn(i).GetName() for i in range(layer.GetLayerDefn().GetFieldCount())]
    if "code" not in names:
        raise RuntimeError(f"contours des départements : champ « code » absent (champs : {names})")
    wanted = scope.get("departements")
    to_merc = transformer_to_mercator(layer.GetSpatialRef())
    geoms: list[ogr.Geometry] = []
    found: set[str] = set()
    for feat in layer:
        code = feat.GetField("code")
        if mask_cfg.get("metropole_only") and len(code) != 2:
            continue  # outre-mer : codes à 3 caractères
        if wanted is not None and code not in wanted:
            continue
        geom = feat.GetGeometryRef().Clone()
        geom.Transform(to_merc)
        geoms.append(geom)
        found.add(code)
    if wanted is not None and set(wanted) - found:
        raise RuntimeError(f"départements introuvables : {sorted(set(wanted) - found)}")
    if not geoms:
        raise RuntimeError("aucun département retenu pour le masque de la France")
    return geoms


def _fetch(url: str, filename: str | None, workdir: Path) -> Path:
    local = workdir / (filename or url.rsplit("/", 1)[-1])
    if not local.exists():
        download(url, local)
    return local


def _load_vector_file(mask_cfg: dict[str, Any], scope: dict[str, Any], workdir: Path) -> list[ogr.Geometry]:
    """Masque générique : un ou plusieurs fichiers vecteur, avec couche et filtre attributaire facultatifs.

    Clés : « url » (ou « urls », liste de {url, filename}), « filename » quand la fin de l'URL n'est pas un nom
    de fichier, « member » pour un fichier rangé dans une archive zip, « layer », « where », et « expect »
    (nombre d'entités attendu, pour s'arrêter si le filtre ne trouve plus ce qu'il doit).
    """
    entries = mask_cfg.get("urls") or [{"url": mask_cfg["url"], "filename": mask_cfg.get("filename")}]
    geoms: list[ogr.Geometry] = []
    for entry in entries:
        local = _fetch(entry["url"], entry.get("filename"), workdir)
        member = entry.get("member", mask_cfg.get("member"))
        path = f"/vsizip/{local}/{member}" if member else str(local)
        ds = ogr.Open(path)
        if ds is None:
            raise RuntimeError(f"impossible d'ouvrir {path}")
        layer_name = entry.get("layer", mask_cfg.get("layer"))
        layer = ds.GetLayerByName(layer_name) if layer_name else ds.GetLayer(0)
        if layer is None:
            raise RuntimeError(f"{path} : couche « {layer_name} » absente")
        where = entry.get("where", mask_cfg.get("where"))
        if where:
            layer.SetAttributeFilter(where)
        to_merc = transformer_to_mercator(layer.GetSpatialRef())
        count = 0
        for feat in layer:
            geom = feat.GetGeometryRef()
            if geom is None:
                continue
            geom = geom.Clone()
            geom.FlattenTo2D()  # certains contours (swisstopo) sont en 3D
            geom.Transform(to_merc)
            geoms.append(geom)
            count += 1
        expect = entry.get("expect", mask_cfg.get("expect") if len(entries) == 1 else None)
        if expect is not None and count != int(expect):
            raise RuntimeError(f"{path} : {count} entité(s) retenue(s), {expect} attendue(s) (couche {layer_name}, filtre {where})")
        ds = None
        if entry.get("delete_after", mask_cfg.get("delete_after")):
            local.unlink(missing_ok=True)
    if len(entries) > 1 and mask_cfg.get("expect") is not None and len(geoms) != int(mask_cfg["expect"]):
        raise RuntimeError(f"masque : {len(geoms)} entité(s) retenue(s), {mask_cfg['expect']} attendue(s)")
    if not geoms:
        raise RuntimeError(f"masque vide pour {[e['url'] for e in entries]}")
    return geoms


def _collect_lines(geom: ogr.Geometry, lines: ogr.Geometry) -> None:
    name = geom.GetGeometryName()
    if name in ("LINESTRING", "LINEARRING"):
        line = ogr.Geometry(ogr.wkbLineString)
        for i in range(geom.GetPointCount()):
            x, y = geom.GetPoint_2D(i)
            line.AddPoint_2D(x, y)
        lines.AddGeometry(line)
    else:
        for i in range(geom.GetGeometryCount()):
            _collect_lines(geom.GetGeometryRef(i), lines)


def _load_osm_land_area(mask_cfg: dict[str, Any], scope: dict[str, Any], workdir: Path) -> list[ogr.Geometry]:
    """Terre ferme d'un pays dans un extrait OpenStreetMap : relation de type land_area.

    Le pilote OSM de GDAL range ces relations dans la couche « other_relations », sous forme de
    lignes : on les assemble en polygones.
    """
    local = _fetch(mask_cfg["url"], mask_cfg.get("filename"), workdir)
    ds = ogr.Open(str(local))
    if ds is None:
        raise RuntimeError(f"impossible d'ouvrir {local}")
    layer = ds.GetLayerByName("other_relations")
    if layer is None:
        raise RuntimeError(f"{local.name} : couche « other_relations » absente")
    layer.SetAttributeFilter(f"osm_id = '{int(mask_cfg['relation'])}'")
    feat = layer.GetNextFeature()
    if feat is None:
        raise RuntimeError(f"{local.name} : relation {mask_cfg['relation']} introuvable")
    lines = ogr.Geometry(ogr.wkbMultiLineString)
    _collect_lines(feat.GetGeometryRef(), lines)
    faces = lines.Polygonize()
    to_merc = transformer_to_mercator(layer.GetSpatialRef())
    geoms = []
    for i in range(faces.GetGeometryCount() if faces is not None else 0):
        geom = faces.GetGeometryRef(i).Clone()
        geom.Transform(to_merc)
        geoms.append(geom)
    if not geoms:
        raise RuntimeError(f"{local.name} : la relation {mask_cfg['relation']} ne forme aucun polygone")
    return geoms


LOADERS = {
    "etalab_departements": _load_etalab_departements,
    "vector_file": _load_vector_file,
    "osm_land_area": _load_osm_land_area,
}


def ground_area_km2(geoms: list[ogr.Geometry]) -> float:
    """Surface au sol de polygones en EPSG:3857 (en Mercator, les surfaces sont dilatées de 1 / cos²(latitude))."""
    total = 0.0
    for geom in geoms:
        for poly in _polygons(geom):
            _, _, y0, y1 = poly.GetEnvelope()
            lat = 2 * math.atan(math.exp((y0 + y1) / 2 / EARTH_RADIUS)) - math.pi / 2
            total += poly.GetArea() * math.cos(lat) ** 2
    return total / 1e6


def load_mask_geometries(ctx: BuildContext) -> dict[str, list[ogr.Geometry]]:
    """Charge, pour chaque pays du périmètre, les polygones de son masque en EPSG:3857."""
    result: dict[str, list[ogr.Geometry]] = {}
    for iso in ctx.countries:
        mask_cfg = ctx.cfg["countries"][iso]["mask"]
        loader = LOADERS.get(mask_cfg["type"])
        if loader is None:
            raise ValueError(f"type de masque inconnu : {mask_cfg['type']}")
        result[iso] = loader(mask_cfg, ctx.scope, ctx.workdir)
        area = ground_area_km2(result[iso])
        print(f"   masque {iso} : {len(result[iso])} polygone(s), {area:,.1f} km2".replace(",", " "), flush=True)
        # Garde-fou pour les contours tirés d'une base modifiable par tous (OpenStreetMap) : la surface attendue.
        expected = mask_cfg.get("expect_area_km2")
        if expected is not None and not float(expected[0]) <= area <= float(expected[1]):
            raise RuntimeError(f"masque {iso} : surface de {area:.2f} km2, hors de l'intervalle attendu {list(expected)} : le contour a changé, à vérifier avant de construire")
    return result


# -- interstices entre contours voisins ------------------------------------------


def _polygons(geom: ogr.Geometry) -> list[ogr.Geometry]:
    if geom.GetGeometryName() == "POLYGON":
        return [geom]
    out: list[ogr.Geometry] = []
    for i in range(geom.GetGeometryCount()):
        out.extend(_polygons(geom.GetGeometryRef(i)))
    return out


def _union(geoms: list[ogr.Geometry]) -> ogr.Geometry:
    collection = ogr.Geometry(ogr.wkbGeometryCollection)
    for geom in geoms:
        collection.AddGeometry(geom if geom.IsValid() else make_valid(geom))
    if hasattr(collection, "UnaryUnion"):  # absent des liaisons Python avant GDAL 3.9
        return collection.UnaryUnion()
    out: ogr.Geometry | None = None
    for i in range(collection.GetGeometryCount()):
        part = collection.GetGeometryRef(i)
        out = part.Clone() if out is None else out.Union(part)
    assert out is not None
    return out


def country_unions(geoms: dict[str, list[ogr.Geometry]], order: list[str]) -> dict[str, ogr.Geometry]:
    """Réunion des polygones de chaque pays (EPSG:3857)."""
    return {iso: _union(geoms[iso]) for iso in order if geoms.get(iso)}


def fill_gaps(geoms: dict[str, list[ogr.Geometry]], order: list[str], max_ha: float = GAP_MAX_HA, unions: dict[str, ogr.Geometry] | None = None) -> dict[str, list[ogr.Geometry]]:
    """Trouve les trous fermés de moins de max_ha (surface au sol) dans l'union des masques.

    geoms : polygones en EPSG:3857 par pays ; order : pays par priorité décroissante.
    Chaque trou va au pays le moins prioritaire qui le touche : le contour du pays
    prioritaire fait foi, c'est donc l'autre qui s'étend jusqu'à lui.
    Renvoie les trous par pays, sans modifier geoms.
    """
    holes: dict[str, list[ogr.Geometry]] = {iso: [] for iso in order}
    per_country = unions if unions is not None else country_unions(geoms, order)
    if not per_country:
        return holes
    prepared = {iso: (g.GetEnvelope(), g.CreatePreparedGeometry()) for iso, g in per_country.items()}
    everything = _union(list(per_country.values()))
    for poly in _polygons(everything):
        for i in range(1, poly.GetGeometryCount()):
            hole = ogr.Geometry(ogr.wkbPolygon)
            hole.AddGeometry(poly.GetGeometryRef(i).Clone())
            x0, x1, y0, y1 = hole.GetEnvelope()
            # Surface au sol : en Mercator, les longueurs sont dilatées de 1 / cos(latitude).
            lat = 2 * math.atan(math.exp((y0 + y1) / 2 / EARTH_RADIUS)) - math.pi / 2
            if hole.GetArea() * math.cos(lat) ** 2 / 1e4 >= max_ha:
                continue
            # Le bord d'un trou est calculé par l'union : il peut être à un milliardième de mètre du contour
            # d'origine. On teste donc le contact avec le trou épaissi d'un centimètre.
            probe = hole.Buffer(GAP_TOUCH_M)
            for iso in reversed(order):
                if iso not in prepared:
                    continue
                (m0, m1, n0, n1), prep = prepared[iso]
                if x1 + GAP_TOUCH_M < m0 or x0 - GAP_TOUCH_M > m1 or y1 + GAP_TOUCH_M < n0 or y0 - GAP_TOUCH_M > n1:
                    continue
                if prep.Intersects(probe):
                    holes[iso].append(hole)
                    break
    return holes


def canvas_for_geometries(ctx: BuildContext, geoms: dict[str, list[ogr.Geometry]]) -> Canvas:
    minx = miny = float("inf")
    maxx = maxy = float("-inf")
    for items in geoms.values():
        for g in items:
            x0, x1, y0, y1 = g.GetEnvelope()
            minx, maxx = min(minx, x0), max(maxx, x1)
            miny, maxy = min(miny, y0), max(maxy, y1)
    return ctx.grid.canvas_for_mercator_bounds(minx, miny, maxx, maxy)


def rasterize_masks(ctx: BuildContext, geoms: dict[str, list[ogr.Geometry]]) -> None:
    """Remplit le canal B : code du pays et type de source par défaut du pays.

    Les pixels des interstices comblés sont marqués : aucune source ne les décrit, leur
    niveau sera recopié depuis les pixels voisins du même pays (Layers.extrapolate_marked).
    """
    assert ctx.canvas is not None and ctx.layers is not None
    for iso in ctx.countries:
        country = ctx.cfg["countries"][iso]
        default_type = int(ctx.cfg["sources"][ctx.country_sources(iso)[-1]]["type"])
        gained = 0
        for geom in geoms[iso]:
            for win, mask in geometry_windows(geom, ctx.canvas):
                gained += ctx.layers.claim_country(win, mask, int(country["code"]), default_type)
        ctx.stats.setdefault("pixels_par_pays", {})[iso] = gained
        print(f"   {iso} : {gained:,} pixels".replace(",", " "), flush=True)
    unions = country_unions(geoms, ctx.countries)
    holes = fill_gaps(geoms, ctx.countries, unions=unions)
    mask_witnesses(ctx, unions, holes)
    for iso in ctx.countries:
        country = ctx.cfg["countries"][iso]
        default_type = int(ctx.cfg["sources"][ctx.country_sources(iso)[-1]]["type"])
        gained = 0
        for hole in holes[iso]:
            for win, mask in geometry_windows(hole, ctx.canvas):
                n = ctx.layers.claim_country(win, mask, int(country["code"]), default_type, marked=True)
                if n:
                    gained += n
                    ctx.gap_windows.append(win)
        if holes[iso]:
            ctx.stats.setdefault("pixels_interstices", {})[iso] = gained
            print(f"   {iso} : {len(holes[iso])} interstice(s) de frontière comblé(s), {gained:,} pixels".replace(",", " "), flush=True)


#: Un point témoin à moins de cette distance (mètres Mercator) d'un contour est écarté : le résultat dépendrait d'un arrondi.
MASK_WITNESS_MARGIN_M = 0.5


def mask_witnesses(ctx: BuildContext, unions: dict[str, ogr.Geometry], holes: dict[str, list[ogr.Geometry]]) -> None:
    """Points témoins du canal B : à quel pays appartient un pixel, d'après les contours eux-mêmes (test géométrique exact).

    Des pixels sont tirés au hasard sur toute la grille et dans la fenêtre de chaque pays. Pour chacun, le pays
    attendu est le premier, dans l'ordre de priorité, dont le contour contient le centre du pixel ; aucun si le
    point est hors de tous les contours. Le test de cohérence relit ensuite ces pixels dans les tuiles.
    """
    import numpy as np

    canvas = ctx.canvas
    assert canvas is not None
    verification = ctx.cfg["verification"]
    per_area = int(verification.get("mask_points", 60))
    if per_area <= 0 or not unions:
        return
    rng = np.random.default_rng(int(verification["seed"]) + 900)
    order = [iso for iso in ctx.countries if iso in unions]
    prepared = {iso: (unions[iso].GetEnvelope(), unions[iso].CreatePreparedGeometry()) for iso in order}
    gap_holes = [(h.GetEnvelope(), h) for items in holes.values() for h in items]
    res = canvas.grid.resolution

    def window_of(envelope: tuple[float, float, float, float]) -> tuple[int, int, int, int] | None:
        return canvas.window_for_envelope(envelope[0], envelope[1], envelope[2], envelope[3])

    areas: list[tuple[str, tuple[int, int, int, int]]] = [("grille", (0, 0, canvas.width, canvas.height))]
    for iso in order:
        win = window_of(prepared[iso][0])
        if win is not None:
            # La fenêtre du pays, élargie d'un dixième : on veut aussi des points juste au-dehors.
            pad_c, pad_r = max(4, win[2] // 10), max(4, win[3] // 10)
            c0, r0 = max(0, win[0] - pad_c), max(0, win[1] - pad_r)
            c1, r1 = min(canvas.width, win[0] + win[2] + pad_c), min(canvas.height, win[1] + win[3] + pad_r)
            areas.append((iso, (c0, r0, c1 - c0, r1 - r0)))
    added: dict[str, int] = {}
    for label, (c0, r0, w, h) in areas:
        kept = 0
        cols = rng.integers(c0, c0 + w, size=per_area * 3).tolist()
        rows = rng.integers(r0, r0 + h, size=per_area * 3).tolist()
        for col, row in zip(cols, rows):
            if kept >= per_area:
                break
            x, y = canvas.pixel_center(col, row)
            # Dans un interstice comblé, le pays vient de la règle de comblement, pas d'un contour : pas de témoin ici.
            if any(e[0] - res <= x <= e[1] + res and e[2] - res <= y <= e[3] + res for e, _ in gap_holes):
                continue
            points = []
            for dx, dy in ((0, 0), (-1, -1), (1, -1), (1, 1), (-1, 1)):
                pt = ogr.Geometry(ogr.wkbPoint)
                pt.AddPoint_2D(x + dx * MASK_WITNESS_MARGIN_M, y + dy * MASK_WITNESS_MARGIN_M)
                points.append(pt)
            expected = None
            ambiguous = False
            for iso in order:
                (x0, x1, y0, y1), prep = prepared[iso]
                if x < x0 - 1 or x > x1 + 1 or y < y0 - 1 or y > y1 + 1:
                    continue
                results = [bool(prep.Contains(pt)) for pt in points]
                if any(results) and not all(results):
                    ambiguous = True
                    break
                if results[0]:
                    expected = iso
                    break
            if ambiguous:
                continue
            tx, ty, px, py = canvas.tile_and_pixel(col, row)
            lon, lat = mercator_to_lonlat(x, y)
            ctx.mask_witnesses.append(
                {
                    "country": expected,
                    "z": canvas.grid.zoom,
                    "x": tx,
                    "y": ty,
                    "px": px,
                    "py": py,
                    "lon": round(lon, 6),
                    "lat": round(lat, 6),
                }
            )
            kept += 1
        added[label] = kept
    ctx.stats["temoins_contours"] = added
    print(f"   points témoins des contours : {added}", flush=True)
