"""Writers for the Unreal-bound raw files and the JSON data products."""
import json
import os

import numpy as np

import worlddef as W
import roads_def as RD
import profile as PR
import align as AL
from common import (N, HALF, M_PER_UNIT, H16_ZERO, ZSCALE, SOURCE_DIR, OUT_DIR, log, sample_bilinear)

CLASS_RANK = {"HIGHWAY": 0, "REGIONAL": 1, "MOUNTAIN": 2, "VILLAGE": 3, "DIRT": 4, "SHORTCUT": 5}
FLAG_BITS = {"BRIDGE": PR.FLAG_BRIDGE, "TUNNEL": PR.FLAG_TUNNEL, "CULVERT": PR.FLAG_CULVERT, "JUNCTION": PR.FLAG_JUNCTION,
             "HAIRPIN": PR.FLAG_HAIRPIN, "PORTAL": PR.FLAG_PORTAL}


def height_to_h16(H):
    return np.clip(np.rint(H / M_PER_UNIT) + H16_ZERO, 0, 65535).astype("<u2")


def h16_to_height(h16):
    return (h16.astype(np.float32) - H16_ZERO) * np.float32(M_PER_UNIT)


def write_raw(path, arr):
    arr = np.ascontiguousarray(arr)
    arr.tofile(path)


def write_json(path, obj, indent=None):
    with open(path, "w") as f:
        json.dump(obj, f, indent=indent, separators=(",", ":") if indent is None else None)


def _r(v, n):
    return float(np.round(v, n))


def road_to_json(rd, nodes, bed_hw):
    c = RD.CLASSES[rd["cls"]]
    xy, z, s = rd["xy"], rd["z"], rd["s"]
    n = len(s)
    rows = []
    for i in range(n):
        rows.append([_r(s[i], 2), _r(xy[i, 0], 3), _r(xy[i, 1], 3), _r(z[i], 3), _r(rd["heading"][i], 2), _r(rd["kappa"][i], 5),
                     _r(np.degrees(rd["bank"][i]), 3), _r(rd["width"][i], 2), int(rd["flags"][i])])
    fl = rd["flags"]
    bridges = []
    for a, b in PR.runs((fl & PR.FLAG_BRIDGE) > 0):
        bridges.append(dict(s0=_r(s[a], 1), s1=_r(s[b], 1), length=_r(s[b] - s[a], 1),
                            deck_height_min=_r(float((z[a:b + 1] - rd["terrain"][a:b + 1]).min()), 1),
                            deck_height_max=_r(float((z[a:b + 1] - rd["terrain"][a:b + 1]).max()), 1)))
    tunnels = []
    for a, b in PR.runs((fl & PR.FLAG_TUNNEL) > 0):
        tunnels.append(dict(s0=_r(s[a], 1), s1=_r(s[b], 1), length=_r(s[b] - s[a], 1)))
    culverts = [_r(s[a], 1) for a, b in PR.runs((fl & PR.FLAG_CULVERT) > 0)]
    hairpins = []
    for a, b in PR.runs((fl & PR.FLAG_HAIRPIN) > 0):
        m = (a + b) // 2
        k = np.abs(rd["kappa"][a:b + 1])
        rmin = 1.0 / max(float(k.max()), 1e-6)
        hairpins.append(dict(s=_r(s[m], 1), x=_r(xy[m, 0], 1), y=_r(xy[m, 1], 1), min_radius=_r(rmin, 1)))
    defn = rd["defn"] if "defn" in rd else None
    return dict(id=rd["id"], name=(defn or {}).get("name", rd["id"]), **{"class": rd["cls"]},
                lanes_per_direction=c["lanes"], lane_width=c["lane_w"], shoulder_width=c["shoulder"], median_width=c["median"],
                speed_limit_kmh=c["speed"], surface=c["surface"], length_m=_r(s[-1], 2), paved_width=_r(RD.paved_width(rd["cls"]), 2),
                bed_half_width=_r(bed_hw, 2), min_radius_m=c["r_min"], max_grade=c["g_max"], sample_count=n,
                bridges=bridges, tunnels=tunnels, culverts=culverts, hairpins=hairpins, samples=rows)


def build_node_table(roads_by_id, nodes):
    out = []
    for name, nd in nodes.items():
        arms = []
        conns = nd["conns"]
        for c in conns:
            rd = roads_by_id[c["road"]]
            s = rd["s"]
            i = int(np.clip(np.searchsorted(s, c["s"]), 0, len(s) - 1))
            hf = float(rd["heading"][i])
            if c["role"] == "start":
                arms.append(dict(road=c["road"], s=_r(c["s"], 2), role="start", heading=_r(hf, 1)))
            elif c["role"] == "end":
                arms.append(dict(road=c["road"], s=_r(c["s"], 2), role="end", heading=_r((hf + 180.0) % 360.0, 1)))
            else:
                arms.append(dict(road=c["road"], s=_r(c["s"], 2), role="mid", heading=_r(hf, 1)))
                arms.append(dict(road=c["road"], s=_r(c["s"], 2), role="mid", heading=_r((hf + 180.0) % 360.0, 1)))
        # control: best class wins priority; mid-road passes always have priority over terminal arms of lower rank
        best = min(CLASS_RANK[roads_by_id[c["road"]]["cls"]] for c in conns)
        controls = []
        for c in conns:
            rank = CLASS_RANK[roads_by_id[c["road"]]["cls"]]
            if c["role"] == "mid" or rank == best:
                ctl = "priority" if len(conns) > 2 or c["role"] == "mid" else "free"
            else:
                ctl = "yield" if rank <= 2 else "stop"
            controls.append(ctl)
        for a_i, c in enumerate(conns):
            pass
        out.append(dict(id=name, kind=nd["kind"], x=_r(nd["xy"][0], 3), y=_r(nd["xy"][1], 3), z=_r(nd.get("z", 0.0), 3),
                        arm_count=len(arms), connections=[dict(road=c["road"], s=_r(c["s"], 2), role=c["role"], control=ctl)
                                                          for c, ctl in zip(conns, controls)], arms=arms))
    return out


def build_edges(roads_by_id, nodes):
    edges = []
    per_road = {}
    for name, nd in nodes.items():
        for c in nd["conns"]:
            per_road.setdefault(c["road"], []).append((c["s"], name))
    for rid, lst in per_road.items():
        lst.sort()
        # merge nodes closer than 1 m along the road
        merged = []
        for s, nm in lst:
            if merged and abs(merged[-1][0] - s) < 1.0 and merged[-1][1] == nm:
                continue
            merged.append((s, nm))
        for k in range(len(merged) - 1):
            (s0, n0), (s1, n1) = merged[k], merged[k + 1]
            if s1 - s0 < 1.0:
                continue
            edges.append(dict(id="%s#%d" % (rid, k), road=rid, from_node=n0, to_node=n1, s0=_r(s0, 2), s1=_r(s1, 2), length=_r(s1 - s0, 2)))
    return edges


LOOP_CHAIN = ["HWY_EAST", "LOOP_COAST", "LOOP_SOUTH", "LOOP_VALLEY", "LOOP_PASS", "LOOP_DESC"]


def build_routes(roads_by_id, nodes):
    routes = {}
    # LOOP: ordered chain of whole roads, driven start -> end
    seq = []
    for rid in LOOP_CHAIN:
        rd = roads_by_id[rid]
        seq.append(dict(road=rid, direction=1, s0=0.0, s1=_r(rd["s"][-1], 2), start_node=rd["defn"]["start"], end_node=rd["defn"]["end"]))
    closed = all(seq[i]["end_node"] == seq[(i + 1) % len(seq)]["start_node"] for i in range(len(seq)))
    routes["LOOP"] = dict(segments=seq, closed=bool(closed), length_m=_r(sum(x["s1"] for x in seq), 1))
    for rid, nm in (("HWY_EAST", "HWY_EAST"), ("PASS_SPUR", "PASS_SPUR"), ("COAST_SPUR", "COAST_SPUR")):
        rd = roads_by_id[rid]
        routes[nm] = dict(segments=[dict(road=rid, direction=1, s0=0.0, s1=_r(rd["s"][-1], 2))], closed=False, length_m=_r(rd["s"][-1], 1))
    for prefix in ("DIRT_", "LOCAL_"):
        ids = [rid for rid in roads_by_id if rid.startswith(prefix)]
        routes[prefix + "*"] = dict(segments=[dict(road=rid, direction=1, s0=0.0, s1=_r(roads_by_id[rid]["s"][-1], 2)) for rid in ids],
                                    closed=False, length_m=_r(sum(roads_by_id[rid]["s"][-1] for rid in ids), 1))
    return routes


def write_roads_json(path, roads, nodes):
    roads_by_id = {r["id"]: r for r in roads}
    obj = dict(
        version=1,
        coordinate_system="UE metres: X north, Y east, Z up, origin = map centre; playable square +-2016 m",
        units="metres, degrees, 1/metres",
        sample_fields=["s", "x", "y", "z", "heading_deg", "curvature", "bank_deg", "width", "flags"],
        sample_notes=dict(
            s="arc length from the road start (m)",
            heading_deg="compass bearing of travel: 0 = +X (north), 90 = +Y (east), clockwise seen from above",
            curvature="signed 1/R; positive = turning right (bearing increasing)",
            bank_deg="superelevation; positive = right edge lower than the left edge (rolls into right-hand curves)",
            width="paved width = lanes + median (m); shoulders are separate (road.shoulder_width)",
            z="finished road surface height on the centre line (m); the carved terrain bed is z - 0.05 m",
            flags="bit mask, see flag_bits"),
        flag_bits=FLAG_BITS,
        roads=[road_to_json(r, nodes, RD.bed_half_width(r["cls"])) for r in roads],
        nodes=build_node_table(roads_by_id, nodes),
        edges=build_edges(roads_by_id, nodes),
        routes=build_routes(roads_by_id, nodes),
    )
    write_json(path, obj)
    return obj


def write_river_json(path, M):
    river = M["river"]
    streams = M["streams"]
    obj = dict(
        version=1,
        sea_level_m=0.0,
        river=dict(name="Silverrun", points=[[_r(p[0], 2), _r(p[1], 2), _r(z, 3), _r(w, 2), _r(d, 2)] for p, z, w, d in
                                              zip(river["pts"], river["z"], river["width"], river["depth"])],
                   fields=["x", "y", "water_z", "width", "water_depth"], length_m=_r(river["s"][-1], 1)),
        streams=[dict(name=s["name"], points=[[_r(p[0], 2), _r(p[1], 2), _r(z, 3), _r(w, 2)] for p, z, w in zip(s["pts"], s["z"], s["width"])],
                      fields=["x", "y", "water_z", "width"]) for s in streams],
        great_bay=dict(centre_line=[[_r(p[0], 1), _r(p[1], 1)] for p in W.BAY_PTS], half_width=[_r(v, 1) for v in W.BAY_HALF],
                       floor_z=[_r(v, 1) for v in W.BAY_FLOOR], water_z=0.0),
    )
    write_json(path, obj)


def write_world_meta(path, files, extra):
    comps = 32
    obj = dict(
        version=1, name="Roamline: Open Roads - procedural world",
        coordinate_system=dict(axes="UE metres: X north, Y east, Z up", origin="map centre", extent_m=[-HALF, HALF]),
        heightmap=dict(file="heightmap_4033.r16", width=N, height=N, vertex_spacing_m=1.0, encoding="uint16 little endian",
                       layout="row-major; row j = +Y direction (vertex Y = j - 2016), column i = +X direction (vertex X = i - 2016)",
                       z_scale_ue=ZSCALE, metres_per_unit=M_PER_UNIT, zero_level=H16_ZERO,
                       formula="Z_m = (h16 - 32768) * 300 / 128 / 100", z_range_m=[(0 - H16_ZERO) * M_PER_UNIT, (65535 - H16_ZERO) * M_PER_UNIT],
                       sea_level_m=0.0),
        landscape=dict(components=[comps, comps], quads_per_component=127, sections_per_component=[2, 2], quads_per_section=63,
                       scale_ue_units=[100.0, 100.0, ZSCALE],
                       location_ue_units=[-HALF * 100.0, -HALF * 100.0, 0.0],
                       note="Landscape actor at X=Y=-201600 cm so that vertex (2016,2016) is the world origin; Z origin 0"),
        layers=dict(order=W.LAYERS, files=["layer_%s.r8" % L for L in W.LAYERS], encoding="uint8, 4033x4033, row-major like the heightmap, "
                                                                                                "weights of the 8 layers sum to 255 per vertex"),
        density_maps=dict(files=["density_forest.r8", "density_scrub.r8", "density_crops.r8"], encoding="uint8 0..255 per vertex"),
        other_maps=dict(slope="slope.r8 (uint8, slope angle in degrees * 255/90)", region_id="region_id.r8 (uint8 region index)"),
        regions=[dict(id=W.REGION_IDS[k], key=k, name=n, color=list(c)) for (k, n, c) in zip(W.REGION_IDS.keys(), W.REGION_NAMES, W.REGION_COLORS)],
        sites=[dict(name=n, kind=k, x=round(float(x), 2), y=round(float(y), 2), z=round(float(z), 3)) for (n, k, x, y), z in zip(extra.get("sites", W.SITES), extra["site_z"])],
        files=files, build=extra.get("build", {}),
    )
    write_json(path, obj, indent=1)
