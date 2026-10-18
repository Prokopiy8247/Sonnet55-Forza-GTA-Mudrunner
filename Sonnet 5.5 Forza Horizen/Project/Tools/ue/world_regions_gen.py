"""Generates Tools/ue/world_regions.json - the input of URoamWorldBuilder::CreateWorldDefinitionAsset (plain Python + numpy, no Unreal).

    "W:\\Blender\\5.2\\python\\bin\\python.exe" -I Tools/ue/world_regions_gen.py

URoamRegionDef is an axis-aligned rectangle, but the generated regions (region_id.r8) are organic. This script approximates the
region_id map with a short list of prioritised rectangles: a greedy "paint the best rectangle on top" search (2-D Kadane over a
64 m cell grid) that, in every step, adds the (region, rectangle) pair that corrects the most cells, up to MAX_RECTS rectangles.
Rectangles of one region share its id (several URoamRegionDef entries); the first entry of a region is its largest rectangle (used
as the teleport target `tp <region>`). The result also lists hand-authored data: names, subtitles, climate zones, road POIs,
the default spawn POI.  Deterministic.
"""
import json
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "Content", "Forza", "World", "Source")
OUT = os.path.join(HERE, "world_regions.json")

N = 4033
CELL = 64                       # metres per grid cell
MAX_RECTS = 16                  # total rectangles over all regions
KEYS = ["Greenvale", "Highcrest", "Plateau", "Coast", "Basin"]   # region_id.r8 values 0..4
REGIONS = {
    "Greenvale": dict(id="greenvale", name="Greenvale", subtitle="Farmland and forest valley", climate="Valley", traffic=1.0),
    "Highcrest": dict(id="highcrest", name="Highcrest", subtitle="Mountain highlands", climate="Mountain", traffic=0.55),
    "Plateau": dict(id="sunbaked", name="Sunbaked Plateau", subtitle="Canyons and long straights", climate="DryHills", traffic=0.8),
    "Coast": dict(id="saltcliff", name="Saltcliff Coast", subtitle="Cliffs, beaches and the bay", climate="Coast", traffic=0.9),
    "Basin": dict(id="crossroads", name="Crossroads Basin", subtitle="The junction hub", climate="Valley", traffic=1.3),
}


def cell_labels(region_map):
    """Majority label per CELL x CELL block (4032 m -> 63 x 63 cells). Axis 0 = Y (rows), axis 1 = X."""
    n = (N - 1) // CELL
    out = np.zeros((n, n), dtype=np.int8)
    step = 8
    for cj in range(n):
        for ci in range(n):
            block = region_map[cj * CELL:cj * CELL + CELL:step, ci * CELL:ci * CELL + CELL:step].ravel()
            out[cj, ci] = np.bincount(block, minlength=5).argmax()
    return out


def best_rectangle(matrix):
    """Maximum-sum sub-rectangle (2-D Kadane). Returns (sum, row0, row1, col0, col1) inclusive."""
    rows, cols = matrix.shape
    best = (-1e9, 0, 0, 0, 0)
    for c0 in range(cols):
        acc = np.zeros(rows, dtype=np.int64)
        for c1 in range(c0, cols):
            acc += matrix[:, c1]
            run, start = 0, 0
            for r in range(rows):
                if run <= 0:
                    run, start = int(acc[r]), r
                else:
                    run += int(acc[r])
                if run > best[0]:
                    best = (run, start, r, c0, c1)
    return best


def main():
    region_map = np.fromfile(os.path.join(SRC, "region_id.r8"), dtype=np.uint8).reshape(N, N)
    labels = cell_labels(region_map)
    n = labels.shape[0]
    pred = np.full((n, n), -1, dtype=np.int8)
    rects = []   # (region_index, r0, r1, c0, c1, priority)
    for step in range(MAX_RECTS):
        best = None
        for k in range(5):
            gain_matrix = (labels == k).astype(np.int64) - (labels == pred).astype(np.int64)
            gain, r0, r1, c0, c1 = best_rectangle(gain_matrix)
            if best is None or gain > best[0]:
                best = (gain, k, r0, r1, c0, c1)
        gain, k, r0, r1, c0, c1 = best
        if gain <= 3:
            break
        pred[r0:r1 + 1, c0:c1 + 1] = k
        rects.append((k, r0, r1, c0, c1, step + 1))
    accuracy_cells = float((pred == labels).mean())

    # full resolution accuracy
    ys, xs = np.mgrid[0:N:4, 0:N:4]
    predicted = np.full(ys.shape, -1, dtype=np.int8)
    for k, r0, r1, c0, c1, prio in rects:
        x0, x1 = c0 * CELL, (c1 + 1) * CELL
        y0, y1 = r0 * CELL, (r1 + 1) * CELL
        predicted[(xs >= x0) & (xs <= x1) & (ys >= y0) & (ys <= y1)] = k
    accuracy_full = float((predicted == region_map[::4, ::4]).mean())

    # output: metres relative to the map centre (vertex 2016); the grid starts at vertex 0 = -2016 m
    def metre(v):
        return int(v - 2016)

    out_regions = []
    for k, key in enumerate(KEYS):
        mine = [r for r in rects if r[0] == k]
        if not mine:
            continue
        mine.sort(key=lambda r: -((r[2] - r[1] + 1) * (r[4] - r[3] + 1)))   # largest first = tp target
        rect_list = []
        for _, r0, r1, c0, c1, prio in mine:
            rect_list.append([metre(c0 * CELL), metre(r0 * CELL), metre((c1 + 1) * CELL), metre((r1 + 1) * CELL), prio])
        info = dict(REGIONS[key])
        info["key"] = key
        info["rects"] = rect_list
        out_regions.append(info)

    # `tp <region>` targets: a road point inside the region that is closest to the region's centre of mass (land only)
    roads = json.load(open(os.path.join(SRC, "roads.json"), "r", encoding="utf-8"))["roads"]
    cand = []   # (x, y, road id, s)
    for road in roads:
        for row in road["samples"][::10]:   # every 20 m is plenty
            cand.append((row[1], row[2], road["id"], row[0]))
    cx = np.array([c[0] for c in cand])
    cy = np.array([c[1] for c in cand])
    cregion = region_map[np.clip(np.round(cy).astype(int) + 2016, 0, N - 1), np.clip(np.round(cx).astype(int) + 2016, 0, N - 1)]
    region_pois = []
    meta = json.load(open(os.path.join(SRC, "world_meta.json"), "r", encoding="utf-8"))
    site_slugs = set()
    for site in meta.get("sites", []):      # same slug rule as RoamWorldBuilder.cpp MakeSlug
        slug = ""
        for ch in site["name"]:
            if ch.isalnum():
                slug += ch.lower()
            elif slug and not slug.endswith("_"):
                slug += "_"
        site_slugs.add(slug.rstrip("_"))
    for k, key in enumerate(KEYS):
        mask = region_map == k
        jj, ii = np.nonzero(mask[::4, ::4])
        centre_x, centre_y = ii.mean() * 4 - 2016, jj.mean() * 4 - 2016
        inside = np.nonzero(cregion == k)[0]
        if len(inside) == 0:
            continue
        d = (cx[inside] - centre_x) ** 2 + (cy[inside] - centre_y) ** 2
        best = cand[int(inside[int(d.argmin())])]
        poi_id = REGIONS[key]["id"]
        if poi_id in site_slugs:        # a world_meta site with the same slug (e.g. the hub "Crossroads"): keep the POI ids unique
            poi_id += "_region"
        region_pois.append({"id": poi_id, "name": REGIONS[key]["name"], "road": best[2], "s": round(best[3], 1), "type": "RoadStart"})

    data = {
        "_comment": "Generated by Tools/ue/world_regions_gen.py (region rectangles) + hand-authored POI data. X north, Y east, metres. rects = [xmin, ymin, xmax, ymax, priority].",
        "map": {"min_m": [-2016, -2016], "max_m": [2016, 2016], "sea_level_m": 0, "latitude_deg": 36},
        "default_spawn_poi": "loop_start",
        "site_snap_distance_m": 150,
        "site_kind_to_poi_type": {
            "hub": "Landmark", "village": "Settlement", "hamlet": "Settlement", "harbour": "Settlement", "farm": "Settlement",
            "gas": "GasStation", "diner": "Diner", "lighthouse": "Landmark", "castle": "Landmark", "windfarm": "Landmark",
            "viewpoint": "Viewpoint", "tunnel": "Tunnel", "bridge": "Bridge", "rest": "Other"
        },
        "regions": out_regions,
        # road POIs: data road ids (roads.json), s in metres along that road, right-hand lane, driving in the road direction
        "road_pois": region_pois + [
            {"id": "loop_start", "name": "Loop Start (Crossroads highway)", "road": "HWY_EAST", "s": 220, "type": "RoadStart"},
            {"id": "highway_plateau", "name": "Plateau Highway", "road": "HWY_EAST", "s": 3300, "type": "RoadStart"},
            {"id": "highway_east_end", "name": "Highway East End", "road": "HWY_EAST", "s": 5300, "type": "RoadStart"},
            {"id": "coast_road", "name": "Coast Road", "road": "LOOP_COAST", "s": 300, "type": "RoadStart"},
            {"id": "south_road", "name": "Southern Road", "road": "LOOP_SOUTH", "s": 1400, "type": "RoadStart"},
            {"id": "valley_road", "name": "Silverrun Valley Road", "road": "LOOP_VALLEY", "s": 1000, "type": "RoadStart"},
            {"id": "pass_foot", "name": "Highcrest Pass Foot", "road": "LOOP_PASS", "s": 200, "type": "RoadStart"},
            {"id": "pass_switchbacks", "name": "Highcrest Switchbacks", "road": "LOOP_PASS", "s": 2600, "type": "RoadStart"},
            {"id": "pass_summit_road", "name": "Highcrest Summit Road", "road": "LOOP_PASS", "s": 4900, "type": "RoadStart"},
            {"id": "pass_descent", "name": "Highcrest Descent", "road": "LOOP_DESC", "s": 2500, "type": "RoadStart"},
            {"id": "desc_tunnel", "name": "Highcrest Tunnel (west portal)", "road": "LOOP_DESC", "s": 2840, "type": "Tunnel"},
            {"id": "pass_spur_start", "name": "Frostholm Spur", "road": "PASS_SPUR", "s": 400, "type": "RoadStart"},
            {"id": "coast_spur_start", "name": "Lighthouse Spur", "road": "COAST_SPUR", "s": 60, "type": "RoadStart"},
            {"id": "dirt_wash_start", "name": "Dust Wash Track", "road": "DIRT_WASH", "s": 300, "type": "RoadStart"},
            {"id": "dirt_log_start", "name": "Logging Track", "road": "DIRT_LOG", "s": 200, "type": "RoadStart"},
            {"id": "basin_road_start", "name": "Basin Road", "road": "BASIN_ROAD", "s": 500, "type": "RoadStart"}
        ]
    }
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1)
    print("world_regions.json written: %d rectangles, cell accuracy %.1f%%, full-res accuracy %.1f%%" % (len(rects), 100 * accuracy_cells, 100 * accuracy_full))
    for reg in out_regions:
        print("  %-10s %s" % (reg["id"], reg["rects"]))


main()
