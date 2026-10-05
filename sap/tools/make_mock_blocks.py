"""Mock estate blocks around a point, for the BLOCKS import and the map.

Generated, not surveyed: a jittered brick of seed points becomes a Voronoi partition, is clipped to
an estate outline, tilted a few degrees, its edges bent a little (a smooth warp, so neighbouring
blocks still share their boundary) and pulled in 2 m for the road between blocks. Blocks come out
at 2 to 6 ha, long east-west, like the strip of blocks in a real estate.

    pip install shapely
    python sap/tools/make_mock_blocks.py                        # 1.604312, 100.189290 -> sap/mock/
    python sap/tools/make_mock_blocks.py --lat 1.6 --lon 100.2 --code MOCK2 --seed 7

Writes sap/mock/<CODE>_blocks.csv, in the columns of the BLOCKS import (Estates app, DataImport:
Kind BLOCKS, estate <CODE>, upload, Load), and sap/mock/<CODE>_blocks.geojson to look at in any GIS
viewer. Area, palms, age, bunches and road condition are made up; gang_code is left empty because
no crews exist for a mock estate.
"""
import argparse
import csv
import json
import math
import random
from pathlib import Path

import numpy as np
import shapely
from shapely.geometry import MultiPolygon, Point, Polygon, mapping
from shapely.ops import voronoi_diagram
from shapely import affinity

OUT = Path(__file__).resolve().parents[1] / "mock"
M_LAT = 110_574.0          # metres per degree of latitude near the equator
DATA_YEAR = 2025


def warp(x, y):
    """A smooth displacement of up to about 12 m: edges bend, shared boundaries stay shared."""
    dx = 8 * np.sin(y / 190.0 + 0.7) + 4 * np.cos((x + y) / 130.0)
    dy = 8 * np.cos(x / 230.0 + 1.9) + 4 * np.sin((x - y) / 150.0)
    return x + dx, y + dy


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lat", type=float, default=1.604312)
    ap.add_argument("--lon", type=float, default=100.189290)
    ap.add_argument("--code", default="MOCK")
    ap.add_argument("--seed", type=int, default=20250524)
    ap.add_argument("--cols", type=int, default=9)
    ap.add_argument("--rows", type=int, default=16)
    a = ap.parse_args()
    rng = random.Random(a.seed)

    # seed points: a brick (odd rows shifted half a cell), each moved by up to a fifth of the spacing
    dx, dy = 280.0, 150.0
    seeds = []
    for i in range(-1, a.rows + 1):
        for j in range(-1, a.cols + 1):
            x = (j - (a.cols - 1) / 2 + (0.5 if i % 2 else 0)) * dx + rng.uniform(-0.22, 0.22) * dx
            y = (i - (a.rows - 1) / 2) * dy + rng.uniform(-0.22, 0.22) * dy
            seeds.append((x, y))
    cells = voronoi_diagram(shapely.MultiPoint(seeds), envelope=box_around(seeds, 4000))
    # the estate outline: the brick's rectangle with its corners moved a little
    hw, hh = a.cols * dx / 2, a.rows * dy / 2
    corners = [(-hw + rng.uniform(-50, 50), -hh + rng.uniform(-50, 50)), (hw + rng.uniform(-50, 50), -hh + rng.uniform(-50, 50)),
               (hw + rng.uniform(-50, 50), hh + rng.uniform(-50, 50)), (-hw + rng.uniform(-50, 50), hh + rng.uniform(-50, 50))]
    outline = Polygon(corners)

    blocks = []
    for cell in cells.geoms:
        piece = cell.intersection(outline)
        if piece.is_empty or piece.geom_type != "Polygon":
            continue
        piece = shapely.segmentize(piece, 25)
        piece = shapely.transform(piece, lambda c: np.column_stack(warp(c[:, 0], c[:, 1])))
        piece = affinity.rotate(piece, -3, origin=(0, 0))
        piece = piece.buffer(-2, join_style="mitre").simplify(1.5)
        if piece.is_empty:
            continue
        if isinstance(piece, MultiPolygon):
            piece = max(piece.geoms, key=lambda g: g.area)
        if piece.area / 1e4 >= 0.8:
            blocks.append(piece)

    rows, features, counters = describe(blocks, a.lon, a.lat, rng, dy)
    write_outputs(a.code, rows, features)
    summary(a.code, rows, counters)


def describe(blocks, lon0, lat0, rng, dy):
    """Rows for the BLOCKS import (and GeoJSON features) from block polygons in local metres east and
    north of (lon0, lat0): three divisions north to south, numbered west to east along each strip
    of rows (dy metres tall), with made-up area, palms, age, bunches and road condition."""
    m_lon = 111_320.0 * math.cos(math.radians(lat0))
    ys = sorted(b.centroid.y for b in blocks)
    cuts = [ys[len(ys) // 3], ys[2 * len(ys) // 3]]

    def division(b):
        return 1 if b.centroid.y >= cuts[1] else 2 if b.centroid.y >= cuts[0] else 3

    blocks = sorted(blocks, key=lambda b: (division(b), -round(b.centroid.y / dy), b.centroid.x))

    def lonlat(x, y):
        return lon0 + x / m_lon, lat0 + y / M_LAT

    rows, features, counters = [], [], {}
    for b in blocks:
        d = division(b)
        counters[d] = counters.get(d, 0) + 1
        code = counters[d]
        ha = round(b.area / 1e4, 2)
        c = b.centroid
        # planting year: a smooth field over the estate, 2008 to 2018, so neighbours are of an age
        field = math.sin(c.x / 700) + math.cos(c.y / 520) + 0.5 * math.sin((c.x + c.y) / 310)
        year = int(round(2008 + (field + 2.5) / 5 * 10 + rng.uniform(-0.6, 0.6)))
        year = max(2008, min(2018, year))
        age = DATA_YEAR - year
        palms = round(ha * 136 * rng.uniform(0.96, 1.02))
        ring = [lonlat(x, y) for x, y in b.exterior.coords]
        clon, clat = lonlat(c.x, c.y)
        rows.append({
            "division_code": d, "block_code": code, "block_label": f"{d}-{code}", "planted_ha": ha, "palms": palms,
            "planted_year": year, "abw_kg": round(min(22.0, 8 + 1.4 * age) + rng.uniform(-0.6, 0.6), 1),
            "rotation_target_days": 10, "gang_code": "", "road_condition": rng.choices(["good", "fair", "poor"], [5, 4, 1])[0],
            "bunches_per_day": round(ha * rng.uniform(4.4, 5.4) * (0.55 if age < 5 else 1), 1),
            "centroid_lon": round(clon, 6), "centroid_lat": round(clat, 6),
            "geometry": ",".join(f"{x:.6f} {y:.6f}" for x, y in ring)})
        features.append({"type": "Feature", "properties": {k: v for k, v in rows[-1].items() if k != "geometry"},
                         "geometry": {"type": "Polygon", "coordinates": [[[round(x, 6), round(y, 6)] for x, y in ring]]}})
    return rows, features, counters


def write_outputs(code, rows, features):
    OUT.mkdir(parents=True, exist_ok=True)
    with open(OUT / f"{code}_blocks.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    (OUT / f"{code}_blocks.geojson").write_text(json.dumps({"type": "FeatureCollection", "features": features}))


def summary(code, rows, counters):
    ha = [r["planted_ha"] for r in rows]
    print(f"{code}: {len(rows)} blocks, {sum(ha):.0f} ha (block {min(ha):.1f} to {max(ha):.1f} ha, median {sorted(ha)[len(ha) // 2]:.1f})"
          f", divisions {counters}, planted {min(r['planted_year'] for r in rows)}-{max(r['planted_year'] for r in rows)}")


def box_around(points, margin):
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    return shapely.box(min(xs) - margin, min(ys) - margin, max(xs) + margin, max(ys) + margin)


if __name__ == "__main__":
    main()
