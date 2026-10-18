"""Deterministic PLACEMENT GENERATOR (agent P1 'props'): terrain masks + road network -> instance lists for Unreal.

Run (plain Python 3 + numpy, no Unreal):
    "W:\\Blender\\5.2\\python\\bin\\python.exe" -I Tools/ue/placement_gen.py [--out Content/Forza/World/Placements] [--tree-budget 105000] [--seed 20261017] [--only trees,cover,furniture,settlements]
Inputs  (Content/Forza/World/Source/, regenerate with Tools/world/build_world.py --no-previews if missing):
    heightmap_4033.r16, layer_{Sand,Farmland,Rock,Snow}.r8, density_{forest,scrub,crops}.r8, slope.r8, region_id.r8, world_meta.json, roads.json, river.json
Outputs (Content/Forza/World/Placements/, git-ignored raw data), read by Tools/ue/props_apply.py:
    placements_index.json   assets per group, per-group counts + per-cell (256 m grid, key "cx,cy") [start, count] ranges, buildings, rotors, summary, notes
    trees.f32  cover.f32  furniture.f32   float32 records, 10 per instance: asset index (into index.groups[g].assets), x, y, z (cm, UE), yaw, pitch, roll (deg), sx, sy, sz
Deterministic: every random stream is seeded from --seed; rerunning on identical inputs gives byte-identical output.
Rules: trees keep >= 6 m from road bed edges (thinning to 22 m), no instances in water (z < 0.5 m / river channel), slope/altitude/biome driven species
(Docs/Tech/PROPS_PIPELINE.md), settlements are placed FIRST so vegetation avoids their footprints.
"""
import argparse
import json
import math
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import placement_lib as P  # noqa: E402
import props_catalog as C  # noqa: E402

SEED = 20261017
DEG = math.degrees


class Ctx:
    def __init__(self, seed):
        t = time.time()
        self.seed = seed
        self.w = P.World()
        self.cat = C.load_catalog()
        self.roads = {d["id"]: P.Road(d) for d in self.w.roads_json["roads"]}
        self.store = P.Store()
        self.road_edge = P.Field(64.0)
        self.bridge_edge = P.Field(40.0)
        self.river_edge = P.Field(90.0)
        self.bld_edge = P.Field(40.0)
        ax, ay, ab, ai, asv = [], [], [], [], []
        for r in self.roads.values():
            self.road_edge.splat(r.X, r.Y, r.bed)
            m = (r.F & 1) != 0
            if m.any():
                self.bridge_edge.splat(r.X[m], r.Y[m], r.bed)
            ax.append(r.X)
            ay.append(r.Y)
            ab.append(np.full(r.n, r.bed))
            ai.append(np.full(r.n, list(self.roads).index(r.id)))
            asv.append(r.S)
        self.allx, self.ally, self.allbed, self.allri, self.alls = [np.concatenate(v) for v in (ax, ay, ab, ai, asv)]
        rv = self.w.river
        pts = np.array(rv["river"]["points"], dtype=float).reshape(-1, 5) if rv["river"]["points"] else np.zeros((0, 5))
        self.river_pts = pts
        if len(pts):
            self.river_edge.splat(pts[:, 0], pts[:, 1], pts[:, 3] * 0.5)
        for st in rv.get("streams", []):
            sp = np.array(st["points"], dtype=float).reshape(-1, 4)
            if len(sp):
                self.river_edge.splat(sp[:, 0], sp[:, 1], sp[:, 3] * 0.5)
        print("[ctx] world + fields in %.1fs; %d roads, %d road samples, %d river points" % (time.time() - t, len(self.roads), len(self.allx), len(pts)))

    def rng_for(self, k):
        return np.random.default_rng(self.seed * 1009 + k)

    def nearest_road(self, x, y):
        d = np.hypot(self.allx - x, self.ally - y)
        i = int(np.argmin(d))
        return float(self.allx[i]), float(self.ally[i]), float(d[i] - self.allbed[i]), list(self.roads)[int(self.allri[i])]


def need(ctx, ids):
    miss = [i for i in ids if i not in ctx.cat]
    if miss:
        raise SystemExit("catalog is missing assets: %s" % miss)


# =====================================================================================================================
# TREES
# =====================================================================================================================
SP = ["oak", "birch", "pine", "poplar", "olive", "palm", "dead"]
# region weights: Greenvale, Highcrest, Plateau, Coast, Basin
SPW = np.array([
    [0.42, 0.22, 0.16, 0.10, 0.06, 0.00, 0.04],
    [0.03, 0.12, 0.72, 0.00, 0.00, 0.00, 0.13],
    [0.02, 0.00, 0.08, 0.00, 0.25, 0.00, 0.65],
    [0.10, 0.00, 0.20, 0.00, 0.25, 0.10, 0.35],
    [0.30, 0.15, 0.15, 0.15, 0.25, 0.00, 0.00]])
BIN = {"oak": 8.0, "birch": 4.5, "pine": 5.0, "poplar": 4.0, "olive": 5.0, "palm": 5.0, "dead": 4.5}


def tree_ids(sp):
    return ["tree_%s_%s" % (sp, v) for v in "abc"]


def gen_trees(ctx, budget, step=4.0):
    w, rng, store = ctx.w, ctx.rng_for(1), ctx.store
    need(ctx, [i for sp in SP for i in tree_ids(sp)])
    ax = np.arange(-P.HALF + step / 2, P.HALF, step)
    X0, Y0 = np.meshgrid(ax, ax)
    X = X0.ravel() + rng.uniform(-0.475, 0.475, X0.size) * step
    Y = Y0.ravel() + rng.uniform(-0.475, 0.475, X0.size) * step
    d = w.near(w.forest, X, Y).astype(np.float32) / 255.0
    k = d > 0.02
    X, Y, d = X[k], Y[k], d[k]
    z = w.zat(X, Y)
    sl = w.slope_deg(X, Y)
    reg = w.near(w.region, X, Y).astype(np.int64)
    sand = w.near(w.sand, X, Y).astype(np.float32)
    re = ctx.road_edge.at(X, Y)
    be = ctx.bridge_edge.at(X, Y)
    rv = ctx.river_edge.at(X, Y)
    bl = ctx.bld_edge.at(X, Y)
    p = d.copy()
    p *= np.clip(1.0 - (sl - 28.0) / 14.0, 0.0, 1.0)
    p *= np.clip((500.0 - z) / 80.0, 0.0, 1.0)
    p *= np.clip((re - 6.0) / 16.0, 0.0, 1.0) * (re >= 6.0)
    p *= (be > 12.0) * (rv > 3.0) * (bl > 7.0) * (z > 0.8)
    p *= 1.0 - 0.85 * np.exp(-np.clip(bl, 0, 80) / 25.0) * (bl < 60)      # sparser around settlements
    exp = float(p.sum())
    gain = min(1.0, budget / max(exp, 1.0))
    sel = rng.uniform(size=p.size) < p * gain
    X, Y, z, sl, reg, sand, rv = X[sel], Y[sel], z[sel], sl[sel], reg[sel], sand[sel], rv[sel]
    # species
    wt = SPW[np.clip(reg, 0, 4)].copy()
    riverside = rv < 70.0
    wt[:, 3] *= np.where(riverside, 4.0, 1.0)
    wt[:, 1] *= np.where(riverside, 2.0, 1.0)
    wt[:, 5] += np.where((reg == 3) & (sand > 60), 3.0, 0.0)
    high = z > 350.0
    wt[:, 2] *= np.where(high, 2.5, 1.0)
    wt[:, 0] *= np.where(high, 0.1, 1.0)
    wt[:, 4] *= np.where(high, 0.0, 1.0)
    wt[:, 6] *= np.where(z > 430.0, 2.5, 1.0)
    wt /= wt.sum(axis=1, keepdims=True)
    sp = (rng.uniform(size=len(X))[:, None] > np.cumsum(wt, axis=1)).sum(axis=1).clip(0, 6)
    var = rng.integers(0, 3, size=len(X))
    pri = rng.uniform(size=len(X))
    keep = np.zeros(len(X), dtype=bool)
    for si, name in enumerate(SP):
        ii = np.flatnonzero(sp == si)
        if len(ii) == 0:
            continue
        bs = BIN[name]
        key = (np.floor((X[ii] + 2100) / bs).astype(np.int64) << 20) | np.floor((Y[ii] + 2100) / bs).astype(np.int64)
        order = np.argsort(pri[ii])
        _u, first = np.unique(key[order], return_index=True)
        keep[ii[order[first]]] = True
    n_main = int(keep.sum())
    for si, name in enumerate(SP):
        for v in range(3):
            ii = np.flatnonzero(keep & (sp == si) & (var == v))
            if len(ii) == 0:
                continue
            aid = "tree_%s_%s" % (name, "abc"[v])
            lo, hi = ctx.cat[aid]["scale"]
            sc = rng.uniform(lo, hi, len(ii))
            store.add_many("trees", aid, X[ii], Y[ii], z[ii] - 0.1, rng.uniform(0, 360, len(ii)), sc)
    print("[trees] candidates %d, expected %.0f, gain %.3f -> %d forest trees" % (len(d), exp, gain, n_main))
    return n_main


def tree_lines(ctx):
    """Poplar / oak rows along farmland roads, olive orchards on ORCHARD_ROAD and around the farms."""
    w, rng, store = ctx.w, ctx.rng_for(2), ctx.store
    n = 0
    for r in ctx.roads.values():
        if r.cls not in ("REGIONAL", "VILLAGE", "DIRT"):
            continue
        for side in (1, -1):
            s = float(rng.uniform(0, 40))
            on, until = False, 0.0
            while s < r.length - 5:
                if s >= until:
                    on = rng.uniform() < 0.5
                    until = s + float(rng.uniform(80, 260))
                if on and not r.flag_at(s, 1 | 2 | 8 | 32):
                    x, y, _z, th = r.pos(s, side * (r.bed + 7.5 + float(rng.uniform(-0.8, 0.8))))
                    reg = int(w.near(w.region, x, y))
                    if reg in (0, 4) and w.near(w.farm, x, y) > 80 and ctx.road_edge.at(x, y) > 6.0 and ctx.river_edge.at(x, y) > 3 and ctx.bld_edge.at(x, y) > 8 \
                            and 0.8 < w.zat(x, y) and w.slope_deg(x, y) < 20:
                        sp = "poplar" if rng.uniform() < 0.6 else "oak"
                        aid = "tree_%s_%s" % (sp, "abc"[int(rng.integers(0, 3))])
                        lo, hi = ctx.cat[aid]["scale"]
                        store.add("trees", aid, x, y, float(w.zat(x, y)) - 0.1, float(rng.uniform(0, 360)), sx=float(rng.uniform(lo, hi)))
                        n += 1
                s += 13.0 + float(rng.uniform(-2, 3))
    # orchards: rows of olives, aligned with the road heading, beside ORCHARD_ROAD and near each farm node
    spots = []
    r = ctx.roads.get("ORCHARD_ROAD")
    if r is not None:
        for side in (1, -1):
            for s in np.arange(30.0, r.length - 30.0, 7.0):
                if r.flag_at(s, 1 | 2 | 8 | 32):
                    continue
                for row in (0, 1, 2):
                    x, y, _z, th = r.pos(s, side * (r.bed + 9.0 + row * 6.0))
                    spots.append((x, y))
    for nid in ("FARM_A", "FARM_B", "FARM_C", "FARM_D"):
        nd = next((q for q in ctx.w.roads_json["nodes"] if q["id"] == nid), None)
        if not nd:
            continue
        hd = math.radians(nd["arms"][0]["heading"] + 180.0)
        for a in range(-3, 4):
            for b in range(0, 9):
                u, v = 60.0 + b * 6.5, 70.0 + a * 6.0
                spots.append((nd["x"] + u * math.cos(hd) - v * math.sin(hd), nd["y"] + u * math.sin(hd) + v * math.cos(hd)))
    for x, y in spots:
        x += float(rng.uniform(-0.4, 0.4))
        y += float(rng.uniform(-0.4, 0.4))
        if ctx.road_edge.at(x, y) > 6.0 and ctx.bld_edge.at(x, y) > 8 and ctx.river_edge.at(x, y) > 3 and w.zat(x, y) > 0.8 and w.slope_deg(x, y) < 14:
            aid = "tree_olive_%s" % "abc"[int(rng.integers(0, 3))]
            lo, hi = ctx.cat[aid]["scale"]
            store.add("trees", aid, x, y, float(w.zat(x, y)) - 0.1, float(rng.uniform(0, 360)), sx=float(rng.uniform(lo, hi)))
            n += 1
    print("[trees] rows + orchards: %d" % n)
    return n


# =====================================================================================================================
# GROUND COVER
# =====================================================================================================================
def lattice(step, rng, jit=0.45):
    ax = np.arange(-P.HALF + step / 2, P.HALF, step)
    X0, Y0 = np.meshgrid(ax, ax)
    return (X0.ravel() + rng.uniform(-jit, jit, X0.size) * step, Y0.ravel() + rng.uniform(-jit, jit, X0.size) * step)


def gen_cover(ctx):
    w, store = ctx.w, ctx.store
    ids = ["nat_bush_leafy_%s" % v for v in "abc"] + ["nat_bush_tumble", "nat_shrub_evergreen_a", "nat_shrub_evergreen_b"] + \
          ["nat_rock_%s_%s" % (k, v) for k in ("granite", "jagged", "mesa", "coast") for v in "abc"] + \
          ["nat_cactus_saguaro_a", "nat_cactus_saguaro_b", "nat_cactus_barrel", "nat_cactus_pricklypear", "nat_cliff_canyon_a", "nat_cliff_coast_b",
           "nat_reeds_a", "nat_reeds_b", "nat_grass_reeds_tall", "nat_crop_wheat_row", "nat_hay_round", "nat_hay_stack", "nat_logpile", "nat_log_fallen", "nat_stump",
           "nat_beach_umbrella", "nat_beach_lounger", "nat_beach_towel_ball", "nat_beach_bucket"]
    need(ctx, ids)
    counts = {}

    def common(X, Y, re_min=3.0, bl_min=2.5, zmin=0.6):
        z = w.zat(X, Y)
        ok = (ctx.road_edge.at(X, Y) >= re_min) & (ctx.bld_edge.at(X, Y) >= bl_min) & (ctx.river_edge.at(X, Y) >= 1.0) & (ctx.bridge_edge.at(X, Y) > 6.0) & (z >= zmin)
        return ok, z

    def emit(aid, X, Y, z, rng, embed=0.1, tilt=0.0, scale_mul=1.0):
        if len(X) == 0:
            return
        lo, hi = ctx.cat[aid]["scale"]
        sc = rng.uniform(lo, hi, len(X)) * scale_mul
        pitch = rng.uniform(-tilt, tilt, len(X)) if tilt else None
        roll = rng.uniform(-tilt, tilt, len(X)) if tilt else None
        store.add_many("cover", aid, X, Y, z - embed * sc, rng.uniform(0, 360, len(X)), sc, pitch, roll)
        counts[aid] = counts.get(aid, 0) + len(X)

    # --- bushes (scrub density + undergrowth in forests)
    rng = ctx.rng_for(11)
    X, Y = lattice(3.5, rng)
    dens = np.maximum(w.near(w.scrub, X, Y), (0.4 * w.near(w.forest, X, Y)).astype(np.uint8)).astype(np.float32) / 255.0
    k = dens > 0.03
    X, Y, dens = X[k], Y[k], dens[k]
    ok, z = common(X, Y)
    sl = w.slope_deg(X, Y)
    p = dens * ok * np.clip(1 - (sl - 25) / 15.0, 0, 1) * np.clip((520 - z) / 100.0, 0, 1)
    gain = min(1.0, 55000 / max(float(p.sum()), 1.0))
    sel = rng.uniform(size=len(p)) < p * gain
    X, Y, z, reg = X[sel], Y[sel], z[sel], w.near(w.region, X[sel], Y[sel]).astype(int)
    u = rng.uniform(size=len(X))
    kind = np.zeros(len(X), dtype=int)        # 0 leafy, 1 evergreen, 2 tumble
    kind[(reg == 2)] = np.where(u[reg == 2] < 0.85, 2, 1)
    kind[(reg == 1)] = np.where((u[reg == 1] < 0.6) | (z[reg == 1] > 350), 1, 0)
    kind[(reg == 3)] = np.where(u[reg == 3] < 0.5, 1, 0)
    kind[np.isin(reg, (0, 4))] = np.where(u[np.isin(reg, (0, 4))] < 0.3, 1, 0)
    var = rng.integers(0, 3, len(X))
    for kd, names in ((0, ["nat_bush_leafy_a", "nat_bush_leafy_b", "nat_bush_leafy_c"]), (1, ["nat_shrub_evergreen_a", "nat_shrub_evergreen_b", "nat_shrub_evergreen_a"]),
                      (2, ["nat_bush_tumble"] * 3)):
        for v in range(3):
            ii = np.flatnonzero((kind == kd) & (var == v))
            emit(names[v], X[ii], Y[ii], z[ii], rng)
    print("[cover] bushes", sum(v for a, v in counts.items() if "bush" in a or "shrub" in a))

    # --- cacti (desert plateau)
    rng = ctx.rng_for(12)
    X, Y = lattice(5.0, rng)
    reg = w.near(w.region, X, Y)
    k = (reg == 2) & (w.near(w.scrub, X, Y) > 40)
    X, Y = X[k], Y[k]
    dens = w.near(w.scrub, X, Y).astype(np.float32) / 255.0
    ok, z = common(X, Y)
    p = (dens ** 1.3) * ok * (w.slope_deg(X, Y) < 30)
    gain = min(1.0, 9000 / max(float(p.sum()), 1.0))
    sel = rng.uniform(size=len(p)) < p * gain
    X, Y, z = X[sel], Y[sel], z[sel]
    u = rng.uniform(size=len(X))
    for lo_, hi_, aid in ((0, 0.15, "nat_cactus_saguaro_a"), (0.15, 0.30, "nat_cactus_saguaro_b"), (0.30, 0.65, "nat_cactus_barrel"), (0.65, 1.01, "nat_cactus_pricklypear")):
        ii = np.flatnonzero((u >= lo_) & (u < hi_))
        emit(aid, X[ii], Y[ii], z[ii], rng)

    # --- rocks (slope driven, denser in canyon / mountains)
    rng = ctx.rng_for(13)
    X, Y = lattice(6.0, rng)
    sl = w.slope_deg(X, Y)
    rockw = w.near(w.rock, X, Y).astype(np.float32) / 255.0
    reg = w.near(w.region, X, Y).astype(int)
    p = np.clip((sl - 14.0) / 26.0, 0, 1) ** 1.2 * 0.6 + rockw * 0.10 + 0.010
    p *= np.where(reg == 2, 1.3, 1.0) * np.where(w.near(w.farm, X, Y) > 120, 0.15, 1.0)
    ok, z = common(X, Y, re_min=2.5)
    p *= ok
    gain = min(1.0, 24000 / max(float(p.sum()), 1.0))
    sel = rng.uniform(size=len(p)) < p * gain
    X, Y, z, sl, reg = X[sel], Y[sel], z[sel], sl[sel], reg[sel]
    u = rng.uniform(size=len(X))
    fam = np.where(reg == 1, np.where((sl > 24) | (z > 300), 1, 0), np.where(reg == 2, 2, np.where((reg == 3) & (z < 25), 3, 0)))
    big = sl > 28
    var = np.where(big, rng.integers(1, 3, len(X)), np.where(u < 0.7, 0, rng.integers(0, 3, len(X))))
    for fi, fname in enumerate(("granite", "jagged", "mesa", "coast")):
        for v in range(3):
            ii = np.flatnonzero((fam == fi) & (var == v))
            emit("nat_rock_%s_%s" % (fname, "abc"[v]), X[ii], Y[ii], z[ii], rng, embed=0.18, tilt=6.0)

    # --- big cliff pieces on very steep ground (canyon + coast)
    rng = ctx.rng_for(14)
    X, Y = lattice(22.0, rng)
    sl = w.slope_deg(X, Y)
    reg = w.near(w.region, X, Y)
    k = (sl > 38) & np.isin(reg, (2, 3))
    X, Y, reg = X[k], Y[k], reg[k]
    ok, z = common(X, Y, re_min=6.0, bl_min=10.0, zmin=3.0)
    sel = ok & (rng.uniform(size=len(X)) < 0.45)
    X, Y, z, reg = X[sel], Y[sel], z[sel], reg[sel]
    face = w.downhill_yaw(X, Y)
    for rid, aid in ((2, "nat_cliff_canyon_a"), (3, "nat_cliff_coast_b")):
        ii = np.flatnonzero(reg == rid)
        if len(ii):
            lo, hi = ctx.cat[aid]["scale"]
            sc = rng.uniform(lo, hi, len(ii))
            store.add_many("cover", aid, X[ii], Y[ii], z[ii] - 1.0 * sc, face[ii] + rng.uniform(-15, 15, len(ii)), sc)
            counts[aid] = counts.get(aid, 0) + len(ii)

    # --- reeds along the river banks
    rng = ctx.rng_for(15)
    pts = ctx.river_pts
    n_reed = 0
    names = ["nat_reeds_a", "nat_reeds_b", "nat_grass_reeds_tall"]
    for i in range(1, len(pts) - 1):
        x, y, wz, wd = pts[i, 0], pts[i, 1], pts[i, 2], pts[i, 3]
        tx, ty = pts[i + 1, 0] - pts[i - 1, 0], pts[i + 1, 1] - pts[i - 1, 1]
        tl = math.hypot(tx, ty) or 1.0
        tx, ty = tx / tl, ty / tl
        for side in (1, -1):
            for _ in range(int(rng.integers(0, 4))):
                lat = wd * 0.5 + float(rng.uniform(0.5, 6.0))
                al = float(rng.uniform(-6, 6))
                px, py = x - ty * lat * side + tx * al, y + tx * lat * side + ty * al
                zz = float(w.zat(px, py))
                if zz < wz - 0.25 or zz > wz + 2.0 or ctx.road_edge.at(px, py) < 3.0 or ctx.bld_edge.at(px, py) < 3:
                    continue
                aid = names[int(rng.integers(0, 3))]
                lo, hi = ctx.cat[aid]["scale"]
                store.add("cover", aid, px, py, zz - 0.1, float(rng.uniform(0, 360)), sx=float(rng.uniform(lo, hi)))
                n_reed += 1
    counts["reeds"] = n_reed

    # --- crop rows (field aligned blocks), hay bales, logs and stumps
    rng = ctx.rng_for(16)
    cmask = (w.crops[::4, ::4] > 90)
    area = float(cmask.sum()) * 16.0
    along = 5.2
    across = max(2.8, area / 38000.0 / along)
    BL = 128.0
    n_crop = 0
    for bx in np.arange(-P.HALF, P.HALF, BL):
        for by in np.arange(-P.HALF, P.HALF, BL):
            i0, j0 = int(bx + P.HALF), int(by + P.HALF)
            if not (w.crops[j0:j0 + int(BL):6, i0:i0 + int(BL):6] > 90).any():
                continue
            yaw = float(rng.uniform(0, 180))
            u_ = np.arange(-95.0, 95.0, along)
            v_ = np.arange(-95.0, 95.0, across)
            U, V = np.meshgrid(u_, v_)
            U = U.ravel() + rng.uniform(-0.35, 0.35, U.size)
            V = V.ravel() + rng.uniform(-0.2, 0.2, V.size) * across
            cx_, cy_ = bx + BL / 2, by + BL / 2
            c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
            X = cx_ + U * c - V * s_
            Y = cy_ + U * s_ + V * c
            k = (X >= bx) & (X < bx + BL) & (Y >= by) & (Y < by + BL)
            X, Y = X[k], Y[k]
            if len(X) == 0:
                continue
            ok, z = common(X, Y, re_min=5.0, bl_min=5.0, zmin=0.8)
            ok &= (w.near(w.crops, X, Y) > 90) & (w.slope_deg(X, Y) < 12.0) & (ctx.river_edge.at(X, Y) > 3.0)
            X, Y, z = X[ok], Y[ok], z[ok]
            if len(X) == 0:
                continue
            flip = np.where(rng.uniform(size=len(X)) < 0.5, 0.0, 180.0)
            lo, hi = ctx.cat["nat_crop_wheat_row"]["scale"]
            sc = rng.uniform(lo, hi, len(X))
            store.add_many("cover", "nat_crop_wheat_row", X, Y, z - 0.02, yaw + flip + rng.uniform(-2, 2, len(X)), sc)
            n_crop += len(X)
    counts["nat_crop_wheat_row"] = n_crop
    X, Y = lattice(30.0, rng)
    dens = w.near(w.crops, X, Y).astype(np.float32) / 255.0
    k = (dens > 0.35) & (rng.uniform(size=len(X)) < 0.45)
    X, Y = X[k], Y[k]
    ok, z = common(X, Y, re_min=6.0, bl_min=6.0)
    X, Y, z = X[ok], Y[ok], z[ok]
    u = rng.uniform(size=len(X))
    emit("nat_hay_round", X[u < 0.65], Y[u < 0.65], z[u < 0.65], rng)
    emit("nat_hay_stack", X[u >= 0.65], Y[u >= 0.65], z[u >= 0.65], rng)
    X, Y = lattice(20.0, rng)
    dens = w.near(w.forest, X, Y).astype(np.float32) / 255.0
    k = (dens > 0.3) & (rng.uniform(size=len(X)) < 0.06)
    X, Y = X[k], Y[k]
    ok, z = common(X, Y, re_min=6.0, bl_min=6.0)
    X, Y, z = X[ok], Y[ok], z[ok]
    u = rng.uniform(size=len(X))
    emit("nat_stump", X[u < 0.5], Y[u < 0.5], z[u < 0.5], rng)
    emit("nat_log_fallen", X[(u >= 0.5) & (u < 0.85)], Y[(u >= 0.5) & (u < 0.85)], z[(u >= 0.5) & (u < 0.85)], rng)
    emit("nat_logpile", X[u >= 0.85], Y[u >= 0.85], z[u >= 0.85], rng)

    # --- beach props (Sunset Beach + a few spots on sandy shores of the coast region)
    rng = ctx.rng_for(17)
    s = w.sites.get("Sunset Beach")
    centres = []
    if s:
        for _ in range(3000):
            x, y = s["x"] + float(rng.uniform(-160, 160)), s["y"] + float(rng.uniform(-160, 160))
            zz = float(w.zat(x, y))
            if w.near(w.sand, x, y) > 100 and 0.8 < zz < 9.0 and ctx.road_edge.at(x, y) > 8 and ctx.bld_edge.at(x, y) > 6:
                if all(math.hypot(x - a, y - b) > 12 for a, b in centres):
                    centres.append((x, y))
            if len(centres) >= 16:
                break
    for x, y in centres:
        face = float(rng.uniform(0, 360))
        for aid, off, nn in (("nat_beach_umbrella", (0, 0), 1), ("nat_beach_lounger", (2.2, 0.8), 2), ("nat_beach_towel_ball", (-2.0, 1.2), 1), ("nat_beach_bucket", (1.0, -2.0), 1)):
            for q in range(nn):
                ox, oy = P.rot(face, off[0] + q * 1.4, off[1] + q * 0.6)
                zz = float(w.zat(x + ox, y + oy))
                store.add("cover", aid, x + ox, y + oy, zz, face + float(rng.uniform(-25, 25)), sx=float(rng.uniform(*ctx.cat[aid]["scale"])))
                counts[aid] = counts.get(aid, 0) + 1
    return counts


# =====================================================================================================================
# MAIN
# =====================================================================================================================
def preview(ctx, st, path):
    """North-up overview: hill-shade, roads (white), trees (green), cover (olive / rock grey), furniture (yellow), buildings (red)."""
    sys.path.insert(0, os.path.join(P.ROOT, "Tools", "world"))
    import pngio
    w = ctx.w
    z = w.Z[:4032:4, :4032:4]
    gx = np.gradient(z, axis=1)
    gy = np.gradient(z, axis=0)
    shade = np.clip(0.55 + 0.35 * (gx - gy) / 4.0, 0.15, 1.0)
    base = np.where(z[..., None] < 0.5, np.array([40, 80, 140]), (np.array([120, 125, 105]) * shade[..., None]))
    img = np.zeros((1008, 1008, 3), dtype=np.uint8)
    img[:] = base.clip(0, 255).astype(np.uint8)          # img[j(Y east), i(X north)]
    def dot(rows, col, r=0):
        a = np.array([(q[1], q[2]) for q in rows]) if rows else np.zeros((0, 2))
        if len(a) == 0:
            return
        i = np.clip(((a[:, 0] + P.HALF) / 4.0).astype(int), 1, 1006)
        j = np.clip(((a[:, 1] + P.HALF) / 4.0).astype(int), 1, 1006)
        for dj in range(-r, r + 1):
            for di in range(-r, r + 1):
                img[np.clip(j + dj, 0, 1007), np.clip(i + di, 0, 1007)] = col
    dot(ctx.store.g.get("cover", []), (150, 150, 60))
    dot(ctx.store.g.get("trees", []), (30, 120, 40))
    dot(ctx.store.g.get("furniture", []), (255, 220, 40))
    for rd in ctx.roads.values():
        dot([(0, x, y) for x, y in zip(rd.X[::2], rd.Y[::2])], (240, 240, 240))
    dot([(0, b["x"], b["y"]) for b in st.buildings], (255, 40, 40), 1)
    pngio.write_png(path, np.flipud(np.transpose(img, (1, 0, 2))))          # north up (X up), east right (Y right)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=P.OUT)
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--tree-budget", type=int, default=105000, help="forest trees; rows + orchards come on top (total target <= 120k)")
    ap.add_argument("--tree-step", type=float, default=4.0, help="candidate lattice spacing in m (3.0 ~ doubles the forest density cap)")
    ap.add_argument("--preview", type=int, default=1, help="write preview_placements.png (1008 px, north up) next to the data")
    ap.add_argument("--only", default="settlements,trees,cover,furniture")
    a = ap.parse_args(argv)
    only = set(a.only.split(","))
    t0 = time.time()
    os.makedirs(a.out, exist_ok=True)
    ctx = Ctx(a.seed)
    import placement_roadside as RS
    import placement_settle as ST
    notes = []
    st = ST.Settle(ctx)
    if "settlements" in only:
        st.build()
        for rc in st.rects:
            ctx.bld_edge.splat([rc.cx], [rc.cy], rc.radius())
        notes += st.notes
        print("[settlements] %d building actors, %d rotors" % (len(st.buildings), len(st.rotors)))
        for n in st.notes:
            print("   ", n)
    summary = {}
    if "trees" in only:
        n_main = gen_trees(ctx, a.tree_budget, a.tree_step)
        n_rows = tree_lines(ctx)
        summary["trees_forest"], summary["trees_rows_orchards"] = n_main, n_rows
    if "cover" in only:
        summary["cover"] = gen_cover(ctx)
    if "furniture" in only:
        fu = RS.Furn(ctx)
        summary["furniture"] = fu.run_all()
        fu.site_lamps([(b["group"], st.rects[i]) for i, b in enumerate(st.buildings) if ("Gas" in b["group"] or "Diner" in b["group"]) and i < len(st.rects)
                       and b["asset"] in ("bld_gas_station", "bld_diner")])
    # write
    index = {"version": 1, "seed": a.seed, "units": "cm (UE), degrees", "record": ["asset", "x", "y", "z", "yaw", "pitch", "roll", "sx", "sy", "sz"], "cell_m": 256, "groups": {},
             "notes": notes}
    for g in ("trees", "cover", "furniture"):
        rows = ctx.store.g.get(g, [])
        assets = sorted({r[0] for r in rows})
        e = P.write_group(a.out, g, rows, assets)
        e["assets"] = {"list": assets, "counts": e["assets"]}
        index["groups"][g] = e
    index["buildings"] = [{**b, "x": b["x"] * 100.0, "y": b["y"] * 100.0, "z": b["z"] * 100.0, "mesh": ctx.cat[b["asset"]]["mesh"]} for b in st.buildings]
    index["rotors"] = [{**b, "x": b["x"] * 100.0, "y": b["y"] * 100.0, "z": b["z"] * 100.0, "mesh": ctx.cat[b["asset"]]["mesh"]} for b in st.rotors]
    index["summary"] = {k: v for k, v in summary.items()}
    index["summary"]["counts"] = {g: index["groups"][g]["count"] for g in index["groups"]}
    index["summary"]["buildings"] = len(st.buildings)
    index["summary"]["rotors"] = len(st.rotors)
    index["generated_seconds"] = round(time.time() - t0, 1)
    json.dump(index, open(a.out + "/placements_index.json", "w"), indent=1)
    if a.preview:
        preview(ctx, st, a.out + "/preview_placements.png")
    print("[done] %.1fs  counts: %s  buildings %d rotors %d -> %s" % (time.time() - t0, index["summary"]["counts"], len(st.buildings), len(st.rotors), a.out))
    return index


if __name__ == "__main__":
    main()
