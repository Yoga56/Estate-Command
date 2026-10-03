"""Writes the CSV files the SAP edition imports (Data Import app, ZCL_EST_IMPORT).

    python sap/tools/export_sap_seed.py            # estate EC -> sap/seed/EC/*.csv
    python sap/tools/export_sap_seed.py --estate EC --out sap/seed

One file per import kind:

    blocks.csv          BLOCKS      block register: area, palms, planting year, bunch weight,
                                    round, road, bunches per day, centroid, polygon
    crews.csv           CREWS       ec_crews.csv
    attendance.csv      ATTENDANCE  ec_attendance.csv
    harvest_orders.csv  ORDERS      ec_harvest_orders.csv
    upkeep_orders.csv   ORDERS      ec_upkeep_orders.csv
    upkeep.csv          UPKEEP      ec_upkeep.csv
    mm.csv              MM          the six SAP MM extracts as ZEST_MM_MOCK rows

The polygons come from the estate's ArcGIS export through gis.ontology when it is present
(it is not in the repository); without it a block is placed at the midpoint of its road
segment and planned on centroids. MM dates are written as days from the day after the
export ends, so in SAP "today" is that day and the history keeps its shape.

The estate row is created by the BLOCKS import; set its DataEnd to the export's last day
(2025-05-23 for EC) in the Estates app so tomorrow is the day after it.
"""

import argparse
import csv
import sys
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FEEDS = ROOT / "gis" / "data" / "synthetic"
WINDOW_START = date(2025, 1, 1)
WINDOW_END = date(2025, 5, 23)
ANCHOR = WINDOW_END + timedelta(days=1)


def read(name: str) -> list[dict]:
    with open(FEEDS / name, encoding="utf-8") as f:
        return list(csv.DictReader(line for line in f if not line.startswith("#")))


def write(path: Path, header: list[str], rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=header, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    print(f"{path}: {len(rows)} rows")


def key(division, block) -> str:
    return f"{int(float(division))}-{int(float(block))}"


def num(v, default=0.0) -> float:
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def blocks(estate: str) -> list[dict]:
    rot = {key(r["division_code"], r["block_code"]): r for r in read("ec_rotation.csv")}
    abw = {key(r["division_code"], r["block_code"]): r for r in read("ec_abw.csv")}
    roads = {key(r["division_code"], r["block_code"]): r for r in read("ec_roads.csv")}

    geo = None
    try:
        sys.path.insert(0, str(ROOT))
        from gis import ontology
        geo = ontology.blocks_geojson(estate, synthetic_world=True)
    except Exception as exc:  # the ArcGIS export is not in the repository
        print(f"no block polygons ({exc}); placing blocks on their road segments")

    out = {}
    days = (WINDOW_END - WINDOW_START).days + 1
    for f in (geo or {}).get("features") or []:
        p = f["properties"]
        k = key(p["division_code"], p["block_code"])
        ring = f["geometry"]["coordinates"][0]
        n = max(len(ring) - 1, 1)
        out[k] = {
            "division_code": p["division_code"], "block_code": p["block_code"],
            "block_label": p.get("block_label") or k,
            "planted_ha": p.get("planted_ha") or 0, "palms": p.get("palms") or 0,
            "planted_year": p.get("planted_year") or "",
            "bunches_per_day": round((p.get("bunches_total") or 0) / days, 3),
            "centroid_lon": round(sum(x[0] for x in ring[:n]) / n, 6),
            "centroid_lat": round(sum(x[1] for x in ring[:n]) / n, 6),
            "geometry": ",".join(f"{x[0]:.6f} {x[1]:.6f}" for x in ring),
        }
    # without the polygons: area and age from the harvest history, palms from the census,
    # bunches per day from the ledger's own window
    area, age, palms, cut = {}, {}, {}, defaultdict(float)
    for r in read("ec_harvest_history.csv"):
        k = key(r["division_code"], r["block_code"])
        area[k] = r["planted_ha"]
        age[k] = r["palm_age_years"]
    for r in read("ec_pest_census.csv"):
        palms[key(r["division_code"], r["block_code"])] = r["palms_planted"]
    for r in read("ec_harvest_orders.csv"):
        if WINDOW_START.isoformat() <= r["date"] <= WINDOW_END.isoformat():
            cut[key(r["division_code"], r["block_code"])] += num(r["actual_qty"])
    for k in set(rot) | set(abw):
        if k in out:
            continue
        r = roads.get(k) or {}
        division, block = k.split("-")
        out[k] = {"division_code": division, "block_code": block, "block_label": k,
                  "planted_ha": area.get(k, ""), "palms": palms.get(k, ""),
                  "planted_year": (2025 - int(num(age[k]))) if age.get(k) else "",
                  "bunches_per_day": round(cut.get(k, 0.0) / days, 3),
                  "centroid_lon": round((num(r.get("lon_a")) + num(r.get("lon_b"))) / 2, 6) if r else "",
                  "centroid_lat": round((num(r.get("lat_a")) + num(r.get("lat_b"))) / 2, 6) if r else ""}
    for k, b in out.items():
        b["abw_kg"] = (abw.get(k) or {}).get("abw_kg", "")
        b["rotation_target_days"] = (rot.get(k) or {}).get("rotation_target_days", "")
        b["gang_code"] = (rot.get(k) or {}).get("gang_code", "")
        b["road_condition"] = (roads.get(k) or {}).get("condition", "")
    return sorted(out.values(), key=lambda b: (int(float(b["division_code"])), int(float(b["block_code"]))))


def offset(d: str) -> int:
    return (date.fromisoformat(d) - ANCHOR).days


def mm() -> list[dict]:
    vendors = {v["lifnr"]: v for v in read("ec_mm_vendors.csv")}
    rows = []
    for m in read("ec_mm_materials.csv"):
        v = vendors.get(m["primary_lifnr"]) or {}
        rows.append({"kind": "M", "material": m["matnr"], "material_name": m["maktx"],
                     "material_group": m["matkl"], "qty_unit": m["meins"],
                     "supplier": m["primary_lifnr"], "supplier_name": v.get("name", ""),
                     "quoted_days": m["plifz"], "reorder_point": m["minbe"], "safety_stock": m["eisbe"],
                     "rounding": m["bstrf"], "price": m["verpr"]})
    for s in read("ec_mm_stock.csv"):
        rows.append({"kind": "S", "material": s["matnr"], "quantity": s["labst"], "qty_unit": s["meins"]})

    receipts = {}
    issues = defaultdict(float)
    for mv in read("ec_mm_movements.csv"):
        if mv["bwart"] == "101" and mv["ebeln"]:
            k = (mv["ebeln"], mv["ebelp"])
            receipts[k] = max(receipts.get(k, mv["budat"]), mv["budat"])
        elif mv["bwart"] in ("201", "261"):
            issues[(mv["matnr"], mv["budat"], mv["meins"])] += num(mv["menge"])
        elif mv["bwart"] in ("202", "262"):
            issues[(mv["matnr"], mv["budat"], mv["meins"])] -= num(mv["menge"])

    for po in read("ec_mm_purchase_orders.csv"):        # delay_cause is the answer key: never exported
        v = vendors.get(po["lifnr"]) or {}
        got = receipts.get((po["ebeln"], po["ebelp"]))
        is_open = po["status"] != "closed" or not got
        rows.append({"kind": "O" if is_open else "P", "material": po["matnr"], "supplier": po["lifnr"],
                     "supplier_name": v.get("name", ""), "document": po["ebeln"],
                     "date_offset": offset(po["bedat"]), "date2_offset": offset(po["eindt"] if is_open else got),
                     "quantity": po["menge"], "qty_unit": po["meins"], "price": po["netpr"]})
    for (matnr, day, unit), qty in sorted(issues.items()):
        rows.append({"kind": "I", "material": matnr, "date_offset": offset(day), "quantity": round(qty, 3),
                     "qty_unit": unit})
    return rows


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--estate", default="EC")
    ap.add_argument("--out", default=str(ROOT / "sap" / "seed"))
    a = ap.parse_args()
    out = Path(a.out) / a.estate

    write(out / "blocks.csv", ["division_code", "block_code", "block_label", "planted_ha", "palms", "planted_year",
                               "abw_kg", "rotation_target_days", "gang_code", "road_condition", "bunches_per_day",
                               "centroid_lon", "centroid_lat", "geometry"], blocks(a.estate))
    write(out / "crews.csv", ["crew_code", "crew_type", "name", "division_code", "establishment", "harvesters",
                              "home_block"], read("ec_crews.csv"))
    write(out / "attendance.csv", ["crew_code", "date", "on_roll", "present"], read("ec_attendance.csv"))
    order_cols = ["order_id", "date", "operation", "activity", "division_code", "block_code", "crew_code",
                  "headcount_plan", "headcount_actual", "planned_qty", "actual_qty", "unit", "man_days_plan",
                  "man_days_actual", "status", "carried_to"]
    write(out / "harvest_orders.csv", order_cols, read("ec_harvest_orders.csv"))
    write(out / "upkeep_orders.csv", order_cols, read("ec_upkeep_orders.csv"))
    write(out / "upkeep.csv", ["division_code", "block_code", "activity", "last_done", "interval_days"],
          read("ec_upkeep.csv"))
    write(out / "mm.csv", ["kind", "material", "material_name", "material_group", "supplier", "supplier_name",
                           "document", "date_offset", "date2_offset", "quantity", "qty_unit", "quoted_days",
                           "reorder_point", "safety_stock", "rounding", "price"], mm())


if __name__ == "__main__":
    main()
