"""
roadbuild.py - planning + chunk geometry orchestration (pure numpy, no bpy).  Shared by build_roads.py (Blender) and the standalone
tests / validators, so the Blender script only has to create objects.

    plan = make_plan(only=None, kinds=None)      # network, junctions, heightmap, chunk descriptors
    data, extra = chunk_data(plan, chunk)        # geometry arrays + structure metadata
    rec = chunk_record(chunk, data, extra)       # JSON-ready record (centre, bounds, tris, material slots ...)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ROADS_JSON = os.path.join(ROOT, "Tools", "world", "out", "roads.json")
HEIGHTMAP = os.path.join(ROOT, "Content", "Forza", "World", "Source", "heightmap_4033.r16")

if HERE not in sys.path:
    sys.path.insert(0, HERE)
import roadgeo as rg
import roadstruct as rs

CHUNK_PREFIX = {"road": "RC", "bridge": "RB", "tunnel": "RT", "junction": "RJ"}


def make_plan(only=None, kinds=None, roads_json=None, heightmap=None):
    net, roads = rg.load_network(roads_json or ROADS_JSON)
    jns = rg.plan_junctions(net, roads)
    hp = heightmap or HEIGHTMAP
    hm = rg.Heightmap(hp) if os.path.exists(hp) else None
    chunks = []
    for rid, r in roads.items():
        counts = {}
        for p in rg.plan_chunks(r, hm):
            k = p["kind"]
            counts[k] = counts.get(k, 0) + 1
            p.update(id="%s_%s_%02d" % (CHUNK_PREFIX[k], rid, counts[k]), road=rid, cls=r.cls)
            chunks.append(p)
    for jn in jns:
        chunks.append(dict(kind="junction", id="RJ_" + jn["id"], road=None, cls="JUNCTION", s0=0.0, s1=0.0, jn=jn))
    sel = []
    for c in chunks:
        if kinds and c["kind"] not in kinds:
            continue
        if only:
            keys = [o.lower() for o in only]
            hit = (c["road"] or "").lower() in keys or c["id"].lower() in keys
            if c["kind"] == "junction":
                hit = hit or any(a["road"].lower() in keys for a in c["jn"]["arms"]) or c["jn"]["id"].lower() in keys
            if not hit:
                continue
        sel.append(c)
    return dict(net=net, roads=roads, jns=jns, hm=hm, chunks=sel, all_chunks=chunks)


def chunk_data(plan, c):
    """Geometry dict (V, F, M, UV) + extra metadata for one chunk descriptor."""
    roads = plan["roads"]
    extra = {}
    if c["kind"] == "road":
        mb = rg.build_road_chunk(roads[c["road"]], c["s0"], c["s1"], c["cap0"], c["cap1"])
        bur = terrain_above_road(plan, c)
        if bur:
            extra["terrain_above_road"] = bur
    elif c["kind"] == "junction":
        mb, _ = rg.build_junction(c["jn"], roads, hm=plan["hm"])
        jn = c["jn"]
        extra["junction"] = dict(id=jn["id"], nodes=jn["nodes"], centre_ue_m=[jn["x"], -jn["y"], jn["z"]],
                                 arms=[dict(road=a["road"], dir=a["dir"], s_node=round(a["s_node"], 2), trim_m=round(a["t"], 2),
                                            control=a.get("control")) for a in jn["arms"]])
    elif c["kind"] == "bridge":
        mb, extra = rs.build_bridge(plan, c)
        bur = bridge_buried(plan, c)
        extra["deck_buried"] = dict(threshold_m=BURIED_THR, ranges=bur["ranges"], landscape_vertices=int(len(bur["vertices"])),
                                    note="natural terrain (not carved under bridge runs) stands above the deck surface over these s "
                                         "ranges: needs a Landscape visibility hole or a carve fix (see ROADS_PIPELINE.md)")
    elif c["kind"] == "tunnel":
        mb, extra = rs.build_tunnel(plan, c)
    else:
        raise ValueError(c["kind"])
    return mb.finish(), extra


BURIED_THR = 0.03


def bridge_buried(plan, c, thr=BURIED_THR):
    """Where does the NATURAL terrain (the world builder does not carve under bridge runs) stand above the deck surface?
    Returns dict(ranges=[{s0, s1, max_m}], vertices=(n, 2) int array of heightmap vertices (i, j) = (X + 2016, Y + 2016) of the quads
    that contain such samples).  Typically the first / last 3-12 m of a bridge, where the carve of the road bed ends."""
    hm = plan["hm"]
    out = dict(ranges=[], vertices=np.zeros((0, 2), int))
    if hm is None:
        return out
    road = plan["roads"][c["road"]]
    s = np.arange(c["s0"], c["s1"] + 0.01, 0.5)
    fr = road.at(s)
    hw = road.B + 0.45 + 0.5
    ds = np.arange(-hw, hw + 0.01, 0.5)
    X = fr["x"][:, None] + fr["ty"][:, None] * ds[None, :]
    Y = fr["y"][:, None] - fr["tx"][:, None] * ds[None, :]
    Zs = fr["z"][:, None] - ds[None, :] * np.tan(fr["bank"])[:, None]
    depth = hm.z_bl(X, Y) - Zs
    bad = depth > thr
    if not bad.any():
        return out
    rows = np.where(bad.any(1))[0]
    groups, start, prev = [], rows[0], rows[0]
    for r_ in rows[1:]:
        if r_ - prev > 4:                          # > 2 m apart: new range
            groups.append((start, prev))
            start = r_
        prev = r_
    groups.append((start, prev))
    for a, b in groups:
        out["ranges"].append(dict(s0=round(float(s[a]), 1), s1=round(float(s[b]), 1), max_m=round(float(depth[a:b + 1].max()), 2)))
    xu, yu = X[bad], -Y[bad]
    i0, j0 = np.floor(xu + 2016.0).astype(int), np.floor(yu + 2016.0).astype(int)
    v = np.concatenate([np.stack([i0 + a, j0 + b], -1) for a in (0, 1) for b in (0, 1)])
    out["vertices"] = np.unique(v, axis=0)
    return out


def terrain_above_road(plan, c, thr=0.10):
    """Ranges of a surface chunk where the carved terrain stands more than `thr` m above the road surface somewhere across the bed
    (the carve deviates there: hairpin apexes, cut banks starting at the shoulder).  Informational: [{s0, s1, max_m}]."""
    hm = plan["hm"]
    if hm is None:
        return []
    road = plan["roads"][c["road"]]
    s = np.arange(c["s0"], c["s1"] + 0.01, 1.0)
    fr = road.at(s)
    ds = np.linspace(-0.9 * road.B, 0.9 * road.B, 9)
    X = fr["x"][:, None] + fr["ty"][:, None] * ds[None, :]
    Y = fr["y"][:, None] - fr["tx"][:, None] * ds[None, :]
    Zs = fr["z"][:, None] - ds[None, :] * np.tan(fr["bank"])[:, None] + rg._crown(road, np.abs(ds))[None, :]
    depth = (hm.z_bl(X, Y) - Zs).max(1)
    rows = np.where(depth > thr)[0]
    if not len(rows):
        return []
    out, start, prev = [], rows[0], rows[0]
    for r_ in rows[1:]:
        if r_ - prev > 3:
            out.append((start, prev))
            start = r_
        prev = r_
    out.append((start, prev))
    return [dict(s0=round(float(s[a]), 1), s1=round(float(s[b]), 1), max_m=round(float(depth[a:b + 1].max()), 2)) for a, b in out]


def centre_of(V):
    lo, hi = V.min(0), V.max(0)
    return np.round((lo + hi) / 2.0, 2), lo, hi


def chunk_record(c, data, extra):
    V = data["V"]
    centre, lo, hi = centre_of(V)
    used = sorted(set(data["M"].tolist()))
    rec = dict(id=c["id"], kind=c["kind"], road=c["road"], class_=c["cls"], s0=round(float(c["s0"]), 3), s1=round(float(c["s1"]), 3),
               centre_ue_m=[float(centre[0]), float(-centre[1]), float(centre[2])],
               bounds_ue_m=dict(min=[float(lo[0]), float(-hi[1]), float(lo[2])], max=[float(hi[0]), float(-lo[1]), float(hi[2])]),
               size_m=[float(x) for x in (hi - lo)], tris=int(len(data["F"])), verts=int(len(V)),
               material_slots=[rg.MATS[m] for m in used])
    rec["class"] = rec.pop("class_")
    rec.update(extra)
    return rec
