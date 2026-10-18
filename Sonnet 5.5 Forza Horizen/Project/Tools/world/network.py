"""Road network assembly: plan + align every road, build the junction graph (named nodes, T-junctions, detected
crossings), solve vertical profiles with node constraints, derive heading / curvature / bank / flags."""
import math
import time

import numpy as np

import roads_def as RD
import roadplan as RP
import align as AL
import profile as PR
import worlddef as W
from common import log, HALF, sample_bilinear
from geom import nearest_on_polyline, seg_intersections, cumlen

JUNCTION_RADIUS = 22.0
MERGE_RADIUS = 28.0


def build_alignments(grid, nodes_xy, only=None):
    """plan + fit horizontal alignments for every road (in definition order)."""
    existing = {}
    roads = {}
    for r in RD.ROADS:
        if only and r["id"] not in only:
            continue
        t0 = time.time()
        if "trace" in r:
            plan = RP.plan_traced(grid, r, nodes_xy, existing)
            al = AL.exact_alignment(plan, r["cls"])
        else:
            plan = RP.plan_road(grid, r, nodes_xy, existing)
            al = AL.fit_alignment(plan, r["cls"])
        existing[r["id"]] = dict(xy=al["xy"], s=al["s"])
        roads[r["id"]] = dict(defn=r, al=al, plan=plan)
        log("  aligned %-16s %-9s %6.0f m  (%.1fs)" % (r["id"], r["cls"], al["s"][-1], time.time() - t0))
    return roads


def _endpoint_node(roads, rid, end, nodes):
    """resolve the node name for a road end; creates anonymous T-junction nodes."""
    r = roads[rid]["defn"]
    spec = r["start"] if end == "start" else r["end"]
    if isinstance(spec, str):
        return spec
    # ('ON', road_id, hint): the end point of this road lies on road_id
    al = roads[rid]["al"]
    p = al["xy"][0] if end == "start" else al["xy"][-1]
    name = "T_%s_%s" % (rid, end)
    nodes[name] = dict(xy=np.array(p, dtype=float), kind="T")
    return name


def build_nodes(roads):
    """returns dict name -> dict(xy, conns=[(road, s, role)])"""
    nodes = {}
    for name, xy in RD.NODES.items():
        nodes[name] = dict(xy=np.array(xy, dtype=float), kind="node")
    for rid in roads:
        for end in ("start", "end"):
            _endpoint_node(roads, rid, end, nodes)
    for name in nodes:
        nodes[name]["conns"] = []
    # terminal connections
    for rid, rr in roads.items():
        r = rr["defn"]
        L = rr["al"]["s"][-1]
        for end in ("start", "end"):
            spec = r[end]
            nm = spec if isinstance(spec, str) else "T_%s_%s" % (rid, end)
            nodes[nm]["conns"].append(dict(road=rid, s=0.0 if end == "start" else L, role=end))
    # mid-road connections: any road passing close to a node
    for name, nd in nodes.items():
        for rid, rr in roads.items():
            if any(c["road"] == rid for c in nd["conns"]):
                continue
            al = rr["al"]
            d, s_at, p, tang = nearest_on_polyline(al["xy"], al["s"], nd["xy"])
            if d < 8.0:
                nd["conns"].append(dict(road=rid, s=float(s_at), role="mid"))
    # detect plain crossings between roads that are not at a node
    ids = list(roads.keys())
    crossings = []
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            a, b = roads[ids[i]]["al"], roads[ids[j]]["al"]
            # quick bbox reject
            if (a["xy"][:, 0].max() < b["xy"][:, 0].min() - 50 or a["xy"][:, 0].min() > b["xy"][:, 0].max() + 50 or
                    a["xy"][:, 1].max() < b["xy"][:, 1].min() - 50 or a["xy"][:, 1].min() > b["xy"][:, 1].max() + 50):
                continue
            for (ia, ta, ib, tb, x, y) in seg_intersections(a["xy"], b["xy"]):
                p = np.array([x, y])
                # close to an existing node?
                near = [n for n, nd in nodes.items() if np.linalg.norm(nd["xy"] - p) < MERGE_RADIUS]
                if near:
                    continue
                crossings.append((ids[i], ids[j], p))
    created = []
    for (ra, rb, p) in crossings:
        # merge duplicate crossings (same pair, close)
        if any(np.linalg.norm(p - q) < MERGE_RADIUS for _, _, q in created):
            continue
        name = "X_%s_%s_%d" % (ra, rb, len(created))
        da, sa, _, _ = nearest_on_polyline(roads[ra]["al"]["xy"], roads[ra]["al"]["s"], p)
        db, sb, _, _ = nearest_on_polyline(roads[rb]["al"]["xy"], roads[rb]["al"]["s"], p)
        nodes[name] = dict(xy=p, kind="X", conns=[dict(road=ra, s=float(sa), role="mid"), dict(road=rb, s=float(sb), role="mid")])
        created.append((ra, rb, p))
    for name in [k for k, v in nodes.items() if not v["conns"]]:
        del nodes[name]                                  # declared but unused nodes
    return nodes, created


def smoothed_terrain(H1, xy, r=14.0):
    ang = np.linspace(0, 2 * np.pi, 8, endpoint=False)
    zs = [float(sample_bilinear(H1, xy[0], xy[1]))]
    for a in ang:
        zs.append(float(sample_bilinear(H1, xy[0] + r * math.cos(a), xy[1] + r * math.sin(a))))
    return float(np.mean(zs))


def solve_profiles(roads, nodes, H1, water_z, streams):
    """vertical profiles with node constraints. Mutates roads[rid]['prof']. Node z assigned in road order."""
    for rid, rr in roads.items():
        r = rr["defn"]
        al = rr["al"]
        s = al["s"]
        n = len(s)
        ds = s[1] - s[0]
        pins = {}
        flat = []
        node_hits = []
        for name, nd in nodes.items():
            for c in nd["conns"]:
                if c["road"] == rid:
                    node_hits.append((name, nd, c))
        for name, nd, c in node_hits:
            i = int(round(c["s"] / ds))
            i = min(max(i, 0), n - 1)
            terminal = c["role"] in ("start", "end")
            if "z" not in nd:
                if terminal and len(nd["conns"]) == 1:
                    # dead end (station, farm, pier ...): the road end floats; the node takes the finished road height
                    nd.setdefault("pending_mid", []).append((rid, i))
                    fz = min(28.0, 0.14 * s[-1])
                    flat.append((max(0.0, c["s"] - fz), min(s[-1], c["s"] + fz)))
                    continue
                if terminal:
                    nd["z"] = smoothed_terrain(H1, nd["xy"])
                    nd["z_by"] = rid
                else:
                    nd.setdefault("pending_mid", []).append((rid, i))
                    continue
            if terminal:
                pins[i] = nd["z"]
                fz = min(28.0, 0.14 * s[-1])
                flat.append((max(0.0, c["s"] - fz), min(s[-1], c["s"] + fz)))
            else:
                pins[i] = nd["z"]
        prof = PR.design_profile(r, al, H1, water_z, pins, flat, streams)
        rr["prof"] = prof
        # assign z for nodes first touched mid-road
        for name, nd, c in node_hits:
            if "z" not in nd:
                i = int(round(c["s"] / ds))
                nd["z"] = float(prof["z"][min(max(i, 0), n - 1)])
                nd["z_by"] = rid
    return roads


def finalize_roads(roads, nodes, created):
    """derive per-sample attributes and flags; returns list of road dicts ready for export."""
    out = []
    for rid, rr in roads.items():
        r = rr["defn"]
        c = RD.CLASSES[r["cls"]]
        al = rr["al"]
        prof = rr["prof"]
        xy = al["xy"]
        s = al["s"]
        n = len(s)
        head = np.degrees(AL.bearings(xy)) % 360.0
        kap = al["kappa"]
        flags = np.zeros(n, dtype=np.int32)
        flags[prof["bridge"]] |= PR.FLAG_BRIDGE
        flags[prof["tunnel"]] |= PR.FLAG_TUNNEL
        flags[prof["culvert"]] |= PR.FLAG_CULVERT
        flags[prof["hairpin"]] |= PR.FLAG_HAIRPIN
        # portals: first/last sample of tunnels
        for a, b in PR.runs(prof["tunnel"]):
            flags[max(0, a - 1):a + 1] |= PR.FLAG_PORTAL
            flags[b:min(n, b + 2)] |= PR.FLAG_PORTAL
        junc = []
        for name, nd in nodes.items():
            for cc in nd["conns"]:
                if cc["road"] == rid:
                    m = np.abs(s - cc["s"]) <= JUNCTION_RADIUS
                    flags[m] |= PR.FLAG_JUNCTION
        out.append(dict(id=rid, defn=r, cls=r["cls"], xy=xy, s=s, z=prof["z"], terrain=prof["terrain"],
                        heading=head, kappa=kap, bank=np.arctan(prof["bank_tan"]), width=np.full(n, RD.paved_width(r["cls"])),
                        flags=flags, grade=prof["grade"]))
    _flag_merge_zones(out, nodes)
    return out


MERGE_REACH = 150.0      # m along a road from a shared node within which a bed overlap counts as part of the junction
MERGE_DZ = 3.0           # m: the two decks differ by less than this where they overlap (a merge, not an embankment above a road)


def _flag_merge_zones(out, nodes):
    """a branch that leaves its parent road at a shallow angle shares bed width with it for a few tens of metres beyond the
    22 m junction radius. Where the beds of two roads that meet at a node overlap (centre lines closer than the sum of the bed
    half widths + 1.5 m) at nearly the same height, the samples are junction zone too (FLAG_JUNCTION): the carve cannot give
    both roads their own bed there, which is why the acceptance statistic reports junction zones separately. Overlaps with a
    larger height difference (an embankment on top of another road) stay ordinary samples and show up as defects."""
    byid = {o["id"]: o for o in out}
    for name, nd in nodes.items():
        conns = nd["conns"]
        ids = sorted(set(c["road"] for c in conns))
        if len(ids) < 2:
            continue
        for ra in ids:
            A = byid[ra]
            sA = [c["s"] for c in conns if c["road"] == ra]
            near = np.zeros(len(A["s"]), dtype=bool)
            for s0 in sA:
                near |= np.abs(A["s"] - s0) <= MERGE_REACH
            idx = np.nonzero(near)[0]
            if not len(idx):
                continue
            d0a = RD.bed_half_width(A["cls"])
            for rb in ids:
                if rb == ra:
                    continue
                B = byid[rb]
                lim = d0a + RD.bed_half_width(B["cls"]) + 1.5
                dx = A["xy"][idx, None, 0] - B["xy"][None, :, 0]
                dy = A["xy"][idx, None, 1] - B["xy"][None, :, 1]
                d2 = dx * dx + dy * dy
                kb = np.argmin(d2, axis=1)
                dmin = np.sqrt(d2[np.arange(len(idx)), kb])
                dz = np.abs(A["z"][idx] - B["z"][kb])
                m = (dmin < lim) & (dz < MERGE_DZ)
                A["flags"][idx[m]] |= PR.FLAG_JUNCTION
