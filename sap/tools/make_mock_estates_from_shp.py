"""Mock estates cut from real plantation outlines in Indonesia.

Takes plantation polygons from the "Indonesia tree plantations by species" shapefile (oil palm
polygons, extracted to indonesia_oilpalm.gpkg), cuts each into blocks inside its real outline,
and writes the BLOCKS import file the same way make_mock_blocks.py does. The outline is real
(Landsat, 2014); everything else, the block lines and every attribute, is made up. The estates
are named by place only, never by the plantation's owner: nothing here describes a real company.

    pip install geopandas shapely
    python sap/tools/make_mock_estates_from_shp.py --gpkg path/to/indonesia_oilpalm.gpkg
    for code in MSUM MJMB MKAL MSLW MPAP; do python sap/tools/make_mock_operations.py --code $code --sweep; done

To use another plantation, add a line to ESTATES: code, name, src_id of the polygon (the
`src_id` column), and optionally a size in ha to clip a very large plantation to a square window
around its middle. Blocks are laid along the plantation's long axis, about 280 m by 150 m.
Writes sap/mock/<CODE>_blocks.csv and .geojson, and sap/mock/estates_from_shp.csv (where each estate is,
for the Estate entity: name, latitude, longitude).
"""
import argparse
import csv
import math
import random
from pathlib import Path

import geopandas as gpd
import numpy as np
import shapely
from shapely import affinity
from shapely.geometry import MultiPolygon, Point, box
from shapely.ops import voronoi_diagram

from make_mock_blocks import M_LAT, OUT, box_around, describe, summary, warp, write_outputs

ESTATES = {  # code: (name, src_id of the plantation polygon, clip to this many ha or None)
    "MSUM": ("Mock estate, Riau (Sumatra)", 1226, None),
    "MJMB": ("Mock estate, Jambi (Sumatra)", 5319, None),
    "MKAL": ("Mock estate, East Kalimantan", 1907, None),
    "MSLW": ("Mock estate, West Sulawesi", 6243, None),
    "MPAP": ("Mock estate, South Papua", 9131, 800),
}
DX, DY = 280.0, 150.0          # seed spacing: a block is about 4 ha, long east-west
SEED = 20250524


def largest(g):
    return max(g.geoms, key=lambda p: p.area) if isinstance(g, MultiPolygon) else g


def cut_blocks(outline, rng):
    """Block polygons (local metres) inside `outline`, laid along its long axis."""
    rect = outline.minimum_rotated_rectangle
    pts = list(rect.exterior.coords)
    edges = [(pts[i], pts[i + 1]) for i in range(2)]
    (x0, y0), (x1, y1) = max(edges, key=lambda e: math.dist(*e))
    angle = math.degrees(math.atan2(y1 - y0, x1 - x0))
    origin = outline.centroid
    flat = affinity.rotate(outline, -angle, origin=origin)       # long axis east-west
    minx, miny, maxx, maxy = flat.bounds
    seeds = []
    rows = int((maxy - miny) / DY) + 3
    cols = int((maxx - minx) / DX) + 3
    for i in range(-1, rows):
        for j in range(-1, cols):
            x = minx + (j + (0.5 if i % 2 else 0)) * DX + rng.uniform(-0.22, 0.22) * DX
            y = miny + i * DY + rng.uniform(-0.22, 0.22) * DY
            seeds.append((x, y))
    cells = voronoi_diagram(shapely.MultiPoint(seeds), envelope=box_around(seeds, 4000))
    blocks = []
    for cell in cells.geoms:
        piece = cell.intersection(flat)
        if piece.is_empty or piece.geom_type != "Polygon":
            continue
        piece = shapely.segmentize(piece, 25)
        piece = shapely.transform(piece, lambda c: np.column_stack(warp(c[:, 0], c[:, 1])))
        piece = piece.buffer(-2, join_style="mitre").simplify(1.5)
        if piece.is_empty:
            continue
        piece = affinity.rotate(largest(piece), angle, origin=origin)
        piece = piece.intersection(outline)                       # the warp must not leave the plantation
        if not piece.is_empty and largest(piece).area / 1e4 >= 0.8:
            blocks.append(largest(piece))
    return blocks


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gpkg", required=True, help="indonesia_oilpalm.gpkg, layer plantations_oil_palm")
    a = ap.parse_args()
    plantations = gpd.read_file(a.gpkg, layer="plantations_oil_palm")
    summary_rows, all_features = [], []
    for code, (name, src_id, clip_ha) in ESTATES.items():
        hit = plantations[plantations.src_id == src_id]
        if hit.empty:
            print(f"{code}: no plantation with src_id {src_id}; skipped")
            continue
        shape = largest(hit.geometry.iloc[0])
        lon0, lat0 = shape.centroid.x, shape.centroid.y
        m_lon = 111_320.0 * math.cos(math.radians(lat0))
        outline = largest(shapely.transform(shape, lambda c: np.column_stack(((c[:, 0] - lon0) * m_lon, (c[:, 1] - lat0) * M_LAT))))
        if clip_ha:                                               # a very large plantation: a window around a point inside it
            centre = outline.representative_point()
            half = math.sqrt(clip_ha * 1e4) / 2
            outline = largest(outline.intersection(box(centre.x - half, centre.y - half, centre.x + half, centre.y + half)))
        outline = largest(outline.simplify(8).buffer(0))
        rng = random.Random(SEED)
        blocks = cut_blocks(outline, rng)
        rows, features, counters = describe(blocks, lon0, lat0, rng, DY)
        write_outputs(code, rows, features)
        summary(code, rows, counters)
        c = outline.centroid
        summary_rows.append({"estate": code, "name": name, "latitude": round(lat0 + c.y / M_LAT, 6),
                             "longitude": round(lon0 + c.x / m_lon, 6), "blocks": len(rows),
                             "ha": round(sum(r["planted_ha"] for r in rows)), "src_id": src_id})
        for f in features:
            f["properties"]["estate"] = code
        all_features += features
    with open(OUT / "estates_from_shp.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(summary_rows[0]))
        w.writeheader()
        w.writerows(summary_rows)
    import json
    (OUT / "MOCK_ESTATES_blocks.geojson").write_text(json.dumps({"type": "FeatureCollection", "features": all_features}))
    print(f"{len(all_features)} blocks in {len(summary_rows)} estates -> {OUT}")


if __name__ == "__main__":
    main()
