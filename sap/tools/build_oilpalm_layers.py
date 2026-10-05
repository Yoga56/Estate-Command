"""Oil palm layer for the UI5 map: planting-year blocks around each estate.

Reads the Zenodo record 13379129 ("Global oil palm extent and planting year", Descals et al.,
CC-BY-4.0): the 10 m extent tiles (0 none, 1 industrial, 2 smallholder) and the 30 m planting-year
tiles, both named by the id of a cell of Grid_OilPalm2016-2021. For each estate below it finds the
tile holding the estate, cuts the palm into polygons by planting year and clips them to a window
around the estate. Everything lands in one GeoJSON the app reads:

    sap/app/estatecommand/webapp/data/oilpalm-blocks-by-year.json

Run, with the four zips downloaded from https://zenodo.org/records/13379129 into one folder:

    pip install geopandas rasterio scipy
    python sap/tools/build_oilpalm_layers.py --zips "path/to/SHP file"

To add an estate, add a line to ESTATES: code, name, centre lon, centre lat. The window is the
estate's centre plus or minus WINDOW degrees (about 17 km each way).

The polygons are plantations by year of planting, not management blocks: land planted in the same
year and touching becomes one polygon. A year of 1989 means planted before 1990 (the layer starts
in 1990).
"""
import argparse
import json
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
from rasterio.features import rasterize, shapes, sieve
from scipy import ndimage as ndi
from shapely.geometry import Point, box, shape

# code: (name, centre lon, centre lat); EC from the fire posts in gis/data/ec_fire_assets.geojson,
# SMPL from the south-west corner and 10 x 4 blocks of zcl_est_seed
ESTATES = {
    "EC": ("EC, Papua", 140.874, -7.018),
    "SMPL": ("Sample Estate, Rokan Hulu, Riau", 100.2015, 1.603),
}
WINDOW = 0.08          # degrees either side of the centre
MIN_HA = 1.0           # smaller polygons are dropped
SPECK_PX = 55          # about 5 ha at 30 m: smaller same-year patches join their largest neighbour
OUT = Path(__file__).resolve().parents[1] / "app" / "estatecommand" / "webapp" / "data" / "oilpalm-blocks-by-year.json"


def mode_filter(a, mask, size=5):
    """Most common year among the palm pixels around each pixel."""
    best = np.zeros(a.shape, "float32")
    out = a.copy()
    for v in np.unique(a[mask]):
        c = ndi.uniform_filter(((a == v) & mask).astype("float32"), size=size, mode="constant")
        m = c > best
        best[m] = c[m]
        out[m] = v
    return np.where(mask, out, 0)


def tile_blocks(zips, tile):
    """Planting-year polygons of one tile: year, class, share of smallholder, hectares."""
    ext_src = rasterio.open(f"/vsizip/{zips / 'GlobalOilPalm_OP-extent.zip'}/GlobalOilPalm_OP-extent_{tile}.tif")
    yop_src = rasterio.open(f"/vsizip/{zips / 'GlobalOilPalm_OP-YoP.zip'}/GlobalOilPalm_OP-YoP_{tile}.tif")
    ext, y = ext_src.read(1), yop_src.read(1)
    h, w = y.shape
    ext = np.pad(ext, ((0, max(0, h * 3 - ext.shape[0])), (0, max(0, w * 3 - ext.shape[1]))))
    e = ext[:h * 3, :w * 3].reshape(h, 3, w, 3)           # 3 x 3 blocks of 10 m on the 30 m grid
    palm = (e > 0).sum(axis=(1, 3)) >= 5
    cls = np.where((e == 1).sum(axis=(1, 3)) >= (e == 2).sum(axis=(1, 3)), 1, 2).astype("uint8")
    yr = np.where(palm, y, 0).astype("int32")
    idx = ndi.distance_transform_edt(~(yr > 0), return_distances=False, return_indices=True)
    yr = np.where(palm, yr[tuple(idx)], 0).astype("int32")  # palm without a year takes the nearest year
    for _ in range(2):
        yr = mode_filter(yr, palm)
    yr = np.where(palm, sieve(yr.astype("int32"), SPECK_PX, connectivity=4), 0).astype("int32")
    rows = [(int(v), shape(g)) for g, v in shapes(yr, mask=yr > 0, transform=yop_src.transform, connectivity=4)]
    gdf = gpd.GeoDataFrame({"year": [v for v, _ in rows]}, geometry=[g for _, g in rows], crs="EPSG:4326")
    gdf["geometry"] = gdf.geometry.simplify(0.00015, preserve_topology=True)   # about 15 m
    ids = rasterize(zip(gdf.geometry, range(1, len(gdf) + 1)), out_shape=cls.shape, transform=yop_src.transform,
                    fill=0, dtype="int32")
    inside = ids > 0
    share = (np.bincount(ids[inside], weights=(cls[inside] == 2), minlength=len(gdf) + 1)
             / np.maximum(np.bincount(ids[inside], minlength=len(gdf) + 1), 1))
    gdf["smallholder_share"] = np.round(share[1:], 2)
    gdf["class"] = np.where(gdf.smallholder_share >= 0.5, "smallholder", "industrial")
    return gdf


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zips", required=True, help="folder with the four Zenodo zips")
    zips = Path(ap.parse_args().zips).resolve()
    grid = gpd.read_file(f"zip://{zips / 'Grid_OilPalm2016-2021.zip'}")
    parts, cache = [], {}
    for code, (name, lon, lat) in ESTATES.items():
        hit = grid[grid.contains(Point(lon, lat))]
        if hit.empty:
            print(f"{code}: no oil palm grid cell holds {lon}, {lat}; skipped")
            continue
        tile = int(hit.ID.iloc[0])
        if tile not in cache:
            cache[tile] = tile_blocks(zips, tile)
        window = box(lon - WINDOW, lat - WINDOW, lon + WINDOW, lat + WINDOW)
        part = gpd.clip(cache[tile], window)
        part = part[~part.is_empty].copy()
        part["area_ha"] = (part.to_crs(part.estimate_utm_crs()).area / 1e4).round(1)
        part = part[part.area_ha >= MIN_HA].reset_index(drop=True)
        part["estate"] = code
        part["estate_name"] = name
        part["age_2021"] = 2021 - part.year
        part["block_id"] = [f"{code}-{i + 1:03d}" for i in range(len(part))]
        print(f"{code}: tile {tile}, {len(part)} polygons, {part.area_ha.sum():.0f} ha, "
              f"palm share of window {part.area_ha.sum() / ((2 * WINDOW * 111.3) ** 2 * 100) * 100:.0f}%")
        parts.append(part)
    out = gpd.GeoDataFrame(pd.concat(parts, ignore_index=True), crs="EPSG:4326")
    out = out[["block_id", "estate", "estate_name", "year", "age_2021", "class", "smallholder_share", "area_ha", "geometry"]]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.to_file(OUT, driver="GeoJSON", COORDINATE_PRECISION=5)
    print(f"{len(out)} polygons -> {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
