"""Mock crews, attendance, work orders and upkeep state for an estate made with make_mock_blocks.py.

Reads sap/mock/<CODE>_blocks.csv and simulates the last DAYS days up to END, crew by crew, as the
sample data under gis/data/synthetic does: each morning a crew takes the blocks that are due, works
as many as its attendance allows, rain cuts the day, and what is left waits. Writes, next to the
blocks file, one CSV per DataImport Kind (Estates app, DataImport: Kind, estate, upload, Load):

    <CODE>_crews.csv           CREWS       5 harvest, 3 upkeep (prune, weed), 3 spray crews
    <CODE>_attendance.csv      ATTENDANCE  roll and present per crew and working day
    <CODE>_harvest_orders.csv  ORDERS      the harvest ledger
    <CODE>_upkeep_orders.csv   ORDERS      the prune, weed and spray ledger (load it as its own file)
    <CODE>_upkeep.csv          UPKEEP      last done and interval, per block and activity

    python sap/tools/make_mock_operations.py                       # code MOCK, 45 days up to today
    python sap/tools/make_mock_operations.py --code MCK_1 --end 2026-10-05

Load BLOCKS first, then the rest. Leave the estate's "Data Ends On" blank to plan from today, or
set it to the END date printed here. Everything is made up: rates follow the sample data (about 100
bunches per harvester-day, circle weeding 1.1 ha, path upkeep 1.5 ha, spraying 2.4 ha and pruning
58 palms per man-day), attendance is 88 to 94 per cent, and a fifth of the days have rain.
"""
import argparse
import csv
import math
import random
from datetime import date, timedelta
from pathlib import Path

MOCK = Path(__file__).resolve().parents[1] / "mock"
BUNCHES_PER_MD = 100.0
ROTATION_DAYS = 10
# activity: (operation, crew type, unit, quantity per man-day, interval in days)
UPKEEP = {
    "pruning": ("prune", "upkeep", "palms", 58.0, 240),
    "circle_weeding": ("weed", "upkeep", "ha", 1.09, 75),
    "path_upkeep": ("weed", "upkeep", "ha", 1.48, 110),
    "spraying": ("spray", "spray", "ha", 2.35, 100),
}
CREWS = [  # code, type, establishment, harvesters
    ("G1-01", "harvest", 26, 14), ("G1-02", "harvest", 24, 13), ("G2-01", "harvest", 26, 14),
    ("G2-02", "harvest", 24, 13), ("G3-01", "harvest", 27, 15),
    ("U1-01", "upkeep", 19, ""), ("U2-01", "upkeep", 18, ""), ("U3-01", "upkeep", 19, ""),
    ("S1-01", "spray", 15, ""), ("S2-01", "spray", 14, ""), ("S3-01", "spray", 16, ""),
]
NAMES = {"harvest": "Harvest gang", "upkeep": "Upkeep gang", "spray": "Spray gang"}


def write(path, rows):
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--code", default="MOCK", help="file prefix, as given to make_mock_blocks.py")
    ap.add_argument("--end", default=date.today().isoformat(), help="last day of data, YYYY-MM-DD")
    ap.add_argument("--days", type=int, default=45)
    ap.add_argument("--seed", type=int, default=20250524)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    end = date.fromisoformat(a.end)
    start = end - timedelta(days=a.days - 1)

    blocks = list(csv.DictReader(open(MOCK / f"{a.code}_blocks.csv")))
    for b in blocks:
        b["div"], b["code"] = int(b["division_code"]), int(b["block_code"])
        b["ha"], b["palms"], b["bpd"] = float(b["planted_ha"]), int(b["palms"]), float(b["bunches_per_day"])
    by_div = {}
    for b in blocks:
        by_div.setdefault(b["div"], []).append(b)

    # crews, their home block near the middle of the division (the 25th or 75th percentile east-west)
    crews = []
    for code, kind, roll, harvesters in CREWS:
        div = int(code[1])
        row = sorted(by_div[div], key=lambda b: float(b["centroid_lon"]))
        home = row[len(row) * (1 if code.endswith("01") else 3) // 4 - 1]["block_label"]
        crews.append({"crew_code": code, "crew_type": kind, "name": f"{NAMES[kind]} {code[1]}-{code[3:]}",
                      "division_code": div, "establishment": roll, "harvesters": harvesters, "home_block": home})

    days = [start + timedelta(days=i) for i in range(a.days)]
    rain = {d: rng.random() < 0.2 for d in days}
    attendance, present_on = [], {}
    for c in crews:
        for d in days:
            if d.weekday() == 6:                       # Sunday: rest day, no row
                continue
            roll = c["establishment"]
            present = sum(rng.random() > rng.uniform(0.06, 0.12) for _ in range(roll))
            attendance.append({"crew_code": c["crew_code"], "date": d.isoformat(), "on_roll": roll, "present": present})
            present_on[(c["crew_code"], d)] = present

    # harvest ledger: blocks come due ROTATION_DAYS after their last cut; stagger the first cuts
    last = {(b["div"], b["code"]): start - timedelta(days=rng.randint(1, ROTATION_DAYS)) for b in blocks}
    harvest, n = [], 0
    for d in days:
        if d.weekday() == 6:
            continue
        for div in sorted(by_div):
            team = [c for c in crews if c["crew_type"] == "harvest" and c["division_code"] == div]
            room = {c["crew_code"]: present_on[(c["crew_code"], d)] * (c["harvesters"] / c["establishment"]) *
                    (0.6 if rain[d] else 1.0) for c in team}
            due = sorted((b for b in by_div[div] if (d - last[(div, b["code"])]).days >= ROTATION_DAYS),
                         key=lambda b: last[(div, b["code"])])
            for b in due:
                crew = max(team, key=lambda c: room[c["crew_code"]])["crew_code"]
                since = (d - last[(div, b["code"])]).days
                qty = round(b["bpd"] * since)
                md = max(1.0, round(qty / BUNCHES_PER_MD))
                if room[crew] < 1:
                    continue
                done = min(1.0, room[crew] / md)
                room[crew] -= md * done
                n += 1
                full = done >= 0.999
                status = "completed" if full else "partial"
                if rain[d] and rng.random() < 0.15:
                    status, done = "weathered_off", 0.0
                actual = round(qty * done * rng.uniform(0.93, 1.02))
                if status == "completed":
                    last[(div, b["code"])] = d
                harvest.append({
                    "order_id": f"WO-{d:%Y-%m%d}-H-{n:03d}", "date": d.isoformat(), "operation": "harvest", "activity": "harvest",
                    "division_code": div, "block_code": b["code"], "crew_code": crew, "headcount_plan": int(md),
                    "headcount_actual": max(1, int(round(md * done * rng.uniform(0.85, 1.0)))) if done else 0,
                    "planned_qty": qty, "actual_qty": actual, "unit": "bunches", "man_days_plan": float(md),
                    "man_days_actual": float(max(1, round(md * done))) if done else 0.0, "status": status, "carried_to": ""})

    # upkeep: each crew takes the jobs due within 5 days, most overdue first
    done_on = {(b["div"], b["code"], act): start - timedelta(days=rng.randint(0, UPKEEP[act][4] + 20))
               for b in blocks for act in UPKEEP}
    upkeep, m = [], 0
    for d in days:
        if d.weekday() == 6:
            continue
        for c in (c for c in crews if c["crew_type"] != "harvest"):
            div = c["division_code"]
            acts = [x for x in UPKEEP if UPKEEP[x][1] == c["crew_type"]]
            # upkeep gangs also carry ad-hoc jobs, so 60 per cent of a day goes to the rotation
            room = present_on[(c["crew_code"], d)] * 0.6 * (0.5 if rain[d] else 1.0)
            jobs = sorted(((b, x) for b in by_div[div] for x in acts
                           if (d - done_on[(div, b["code"], x)]).days - UPKEEP[x][4] >= -5),
                          key=lambda j: 0)
            jobs.sort(key=lambda j: UPKEEP[j[1]][4] - (d - done_on[(div, j[0]["code"], j[1])]).days)   # most overdue first
            for b, act in jobs:
                if room < 1:
                    break
                op, _, unit, rate, _ = UPKEEP[act]
                qty = b["palms"] if unit == "palms" else b["ha"]
                md = max(1.0, round(qty / rate))
                share = min(1.0, room / md)
                room -= md * share
                m += 1
                status = "completed" if share >= 0.999 else "partial"
                if rain[d] and rng.random() < 0.3:
                    status, share = "weathered_off", 0.0
                if status == "completed":
                    done_on[(div, b["code"], act)] = d
                upkeep.append({
                    "order_id": f"WO-{d:%Y-%m%d}-U-{m:03d}", "date": d.isoformat(), "operation": op, "activity": act,
                    "division_code": div, "block_code": b["code"], "crew_code": c["crew_code"], "headcount_plan": int(md),
                    "headcount_actual": int(round(md * share)) if share else 0, "planned_qty": round(qty, 2),
                    "actual_qty": round(qty * share, 2), "unit": unit, "man_days_plan": float(md),
                    "man_days_actual": float(round(md * share)) if share else 0.0, "status": status, "carried_to": ""})

    state = [{"division_code": b["div"], "block_code": b["code"], "activity": act,
              "last_done": done_on[(b["div"], b["code"], act)].isoformat(), "interval_days": UPKEEP[act][4]}
             for b in blocks for act in UPKEEP]

    write(MOCK / f"{a.code}_crews.csv", crews)
    write(MOCK / f"{a.code}_attendance.csv", attendance)
    write(MOCK / f"{a.code}_harvest_orders.csv", harvest)
    write(MOCK / f"{a.code}_upkeep_orders.csv", upkeep)
    write(MOCK / f"{a.code}_upkeep.csv", state)
    tomorrow = end + timedelta(days=1)
    due_h = sum(1 for k, v in last.items() if (tomorrow - v).days >= ROTATION_DAYS)
    over = sum(1 for (dv, bc, act), v in done_on.items() if (tomorrow - v).days >= UPKEEP[act][4])
    print(f"{a.code}: {start} to {end}: {len(crews)} crews, {len(attendance)} attendance rows, {len(harvest)} harvest orders, "
          f"{len(upkeep)} upkeep orders, {len(state)} upkeep rows")
    print(f"on {tomorrow}: {due_h} of {len(blocks)} blocks due for harvest, {over} upkeep jobs due or overdue; "
          f"rain on {sum(rain.values())} of {len(days)} days")


if __name__ == "__main__":
    main()
