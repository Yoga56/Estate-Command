"""
Tests for the scheduler's route ordering: a crew's blocks are visited in a short
path from its home, the blocks and the value recovered stay as chosen.
Run with:  pytest test_scheduler_route.py
"""

import random

from gis.models import scheduler as s


def path_km(start, points, order):
    pos, total = start, 0.0
    for i in order:
        total += s._km(pos, points[i])
        pos = points[i]
    return total


def test_zigzag_becomes_a_sweep():
    # home in the middle of a row of blocks, picked by value: left, right, far left, far right
    start = (100.0, 1.0)
    points = [(99.990, 1.0), (100.010, 1.0), (99.980, 1.0), (100.020, 1.0)]
    greedy = [0, 1, 2, 3]
    routed = s._route_order(start, points)
    assert sorted(routed) == [0, 1, 2, 3]
    assert path_km(start, points, routed) < 0.6 * path_km(start, points, greedy)


def test_never_longer_than_the_nearest_neighbour_and_keeps_every_block():
    rng = random.Random(3)
    for n in (2, 3, 5, 9, 14, 25):
        start = (100.0, 1.0)
        points = [(100.0 + rng.uniform(-0.02, 0.02), 1.0 + rng.uniform(-0.02, 0.02)) for _ in range(n)]
        routed = s._route_order(start, points)
        assert sorted(routed) == list(range(n))
        # greedy pick order stands in for "by value": a shuffled order
        shuffled = list(range(n))
        rng.shuffle(shuffled)
        assert path_km(start, points, routed) <= path_km(start, points, shuffled) + 1e-9


def test_one_block_and_none():
    assert s._route_order((0.0, 0.0), []) == []
    assert s._route_order((0.0, 0.0), [(0.1, 0.1)]) == [0]


def crew_with(blocks):
    return {"crew_code": "G1-01", "present": 14, "home": (100.0, 1.0), "home_key": "H",
            "assigned": [{"block_key": f"B{i}", "division_code": "1", "centroid": c, "deferral_idr": 1e6,
                          "value_idr": 1e6, "share": 1.0, "seq": i + 1} for i, c in enumerate(blocks)]}


AV = {"man_day_cost_idr": 150000, "work_day_hours": 8, "crew_transport_km_per_hour": 15}


def test_route_renumbers_and_cuts_travel_but_not_value():
    crew = crew_with([(99.990, 1.0), (100.010, 1.0), (99.980, 1.0), (100.020, 1.0)])
    before = s._crew_objective(crew, {}, AV, "harvest", 0)
    s._route(crew, {}, AV, "harvest", 0)
    assert [a["seq"] for a in crew["assigned"]] == [1, 2, 3, 4]
    assert sorted(a["block_key"] for a in crew["assigned"]) == ["B0", "B1", "B2", "B3"]
    assert s._crew_objective(crew, {}, AV, "harvest", 0) > before


def test_route_is_kept_off_when_it_would_lose_a_contiguity_bonus():
    # greedy order B0, B1, B2: B1 sits next to B0 and earns the bonus. The shortest route would
    # visit B1 before B0 (B0 has no recorded neighbour here), losing a bonus far above the travel saved.
    adj = {"B1": {"B0"}}
    crew = crew_with([(100.060, 1.0), (100.050, 1.0), (100.010, 1.0)])
    for a in crew["assigned"]:
        a["value_idr"] = 5e8
    before = s._crew_objective(crew, adj, AV, "harvest", 15)
    s._route(crew, adj, AV, "harvest", 15)
    assert [a["block_key"] for a in crew["assigned"]] == ["B0", "B1", "B2"]
    assert [a["seq"] for a in crew["assigned"]] == [1, 2, 3]
    assert s._crew_objective(crew, adj, AV, "harvest", 15) == before


def test_dispatch_is_left_alone():
    crew = crew_with([(99.990, 1.0), (100.010, 1.0), (99.980, 1.0)])
    order = [a["block_key"] for a in crew["assigned"]]
    s._route(crew, {}, AV, "dispatch", 0)
    assert order == [a["block_key"] for a in crew["assigned"]]
