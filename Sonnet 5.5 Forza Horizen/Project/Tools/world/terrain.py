"""Terrain generator (v2).

Stage 1 - natural terrain on a coarse 8 m grid: rolling lowland (Greenvale / hub basin / coast hills), the Sunbaked
Plateau (escarpment with terraced cliff walls, mesas, canyons / washes, basins), the Highcrest massif (massif.py),
all added on one lowland base so there are no region seams. Region weights are smooth scores (no straight borders).
Stage 2 - upsampled to the 2 m macro grid: shore carving (cliffs, beaches, coves, headlands, sea), the Great Bay,
terrain-shaping road corridors, flat platforms, the meandering Silverrun and its valley, drainage-derived streams,
sea stacks and the soft border ring. `finalize_1m` then adds 1 m detail.
"""
import math
import zlib

import numpy as np

import worlddef as W
import massif as MS
import erosion as ER
from common import (HALF, N, SEA, ss, smin, smax, log, sample_bilinear, gauss_blur)
from geom import raster_dist
from noise import fbm, ridged, noise2, upsample2, warp, mountain_noise

SEED = 20260516
CS = 8.0        # coarse grid step of stage 1


def rng_for(name):
    return np.random.default_rng(SEED + zlib.crc32(name.encode()) % 100000)


def grid_axes(step):
    n = int(round(2 * HALF / step)) + 1
    xs = (np.arange(n, dtype=np.float32) * np.float32(step) - np.float32(HALF))
    return n, xs


def resize_to(A, step_in, step_out):
    """bilinear resample of a [j,i] grid defined on [-HALF, HALF] from step_in to step_out."""
    n_in = A.shape[0]
    n_out = int(round(2 * HALF / step_out)) + 1
    if n_in == n_out:
        return A
    pos = (np.arange(n_out, dtype=np.float64) * step_out) / step_in
    i0 = np.clip(np.floor(pos).astype(np.int64), 0, n_in - 2)
    t = (pos - i0).astype(np.float32)
    tmp = np.take(A, i0, axis=1) * (1 - t)[None, :] + np.take(A, i0 + 1, axis=1) * t[None, :]
    out = np.take(tmp, i0, axis=0) * (1 - t)[:, None] + np.take(tmp, i0 + 1, axis=0) * t[:, None]
    return out.astype(np.float32)


def upsample_to(A, step_in, step_out):
    """smooth (Catmull-Rom, x2 per pass) upsampling of a coarse grid to a finer one; falls back to bilinear if the ratio is odd."""
    r = step_in / step_out
    out = A
    st = step_in
    while st > step_out * 1.0001:
        out = upsample2(out, clamp=False)
        st /= 2.0
    if abs(st - step_out) > 1e-6:
        out = resize_to(out, st, step_out)
    return out.astype(np.float32)


def terrace(t, k=3.0, sharp=0.28):
    """stepped profile of t in [0,1]: k flat benches joined by steep risers."""
    t = np.clip(t, 0, 1) * k
    fl = np.floor(np.minimum(t, k - 1e-4))
    fr = t - fl
    return (fl + ss(fr, 0.5 - sharp, 0.5 + sharp)) / k


def strata(z, period, a, shift, sharp=0.30):
    """geology: bend elevation into benches and cliff bands that follow the contour lines (never axis aligned)."""
    b = (z + shift) / period
    fl = np.floor(b)
    fr = b - fl
    st = (fl + ss(fr, 0.5 - sharp, 0.5 + sharp)) * period - shift
    return z + a * (st - z)


# ---------------------------------------------------------------- polygon helpers
def polygon_inside(X, Y, poly):
    """even-odd test; poly (m,2) in (X, Y); X, Y broadcastable grids."""
    inside = np.zeros(np.broadcast(X, Y).shape, dtype=bool)
    m = len(poly)
    for k in range(m):
        x1, y1 = poly[k]
        x2, y2 = poly[(k + 1) % m]
        cond = ((y1 > Y) != (y2 > Y))
        if not cond.any():
            continue
        xin = x1 + (Y - y1) * (x2 - x1) / (y2 - y1 + 1e-12)
        inside ^= cond & (X < xin)
    return inside


def polygon_sdist(shape, step, poly, radius=900.0):
    """signed distance (positive inside) of a closed polygon on the grid (limited to +-radius)."""
    n = shape[0]
    xs = (np.arange(n, dtype=np.float32) * np.float32(step) - np.float32(HALF))
    X = xs[None, :]
    Y = xs[:, None]
    closed = np.vstack([poly, poly[:1]])
    d, _ = raster_dist(shape, step, -HALF, closed, radius)
    ins = polygon_inside(X, Y, poly)
    return np.where(ins, d, -d).astype(np.float32)


def capsule_u(X, Y, pts, hw):
    """signed 'inside' value of a variable-width ribbon around a polyline: half width - distance (m)."""
    pts = np.asarray(pts, dtype=np.float64)
    hw = np.asarray(hw, dtype=np.float64)
    shape = np.broadcast(X, Y).shape
    best = np.full(shape, -1e9, dtype=np.float32)
    for k in range(len(pts) - 1):
        a, b = pts[k], pts[k + 1]
        dx, dy = b[0] - a[0], b[1] - a[1]
        L2 = dx * dx + dy * dy
        t = np.clip(((X - a[0]) * dx + (Y - a[1]) * dy) / L2, 0.0, 1.0)
        ex = X - (a[0] + t * dx)
        ey = Y - (a[1] + t * dy)
        d = np.sqrt(ex * ex + ey * ey)
        w = hw[k] + (hw[k + 1] - hw[k]) * t
        best = np.maximum(best, (w - d).astype(np.float32))
    return best


def corridor_fields(corridors, cstep):
    """distance fields of the terrain-shaping / calming road corridors on the `cstep` grid.
    returns (list of (corridor, d, z, flat, blend), cmask) - all [j,i] float32 on the cstep grid."""
    cn = int(round(2 * HALF / cstep)) + 1
    cmask = np.zeros((cn, cn), dtype=np.float32)
    dshape = np.full((cn, cn), 9999.0, dtype=np.float32)
    out = []
    for c in corridors:
        pts = np.asarray(c["pts"], dtype=np.float64)
        zc = c.get("z")
        wc = c.get("width")
        flat0 = c.get("flat", 60.0)
        blend0 = c.get("blend", 380.0)
        seg = np.sqrt((np.diff(pts, axis=0) ** 2).sum(1))
        sv = np.concatenate([[0.0], np.cumsum(seg)])
        frac = sv / sv[-1]
        if wc is not None:
            wk = np.asarray(wc, dtype=np.float64)
            flat_v = np.interp(frac, wk[:, 0], wk[:, 1])
            blend_v = np.interp(frac, wk[:, 0], wk[:, 2])
        else:
            flat_v = np.full(len(pts), flat0)
            blend_v = np.full(len(pts), blend0)
        rad = float(np.max(flat_v + blend_v)) + 20.0
        cols = [flat_v, blend_v]
        if zc is not None:
            zk = np.asarray(zc, dtype=np.float64)
            cols.insert(0, np.interp(frac, zk[:, 0], zk[:, 1]))
        vals = np.stack(cols, 1)
        d_c, attr = raster_dist((cn, cn), cstep, -HALF, pts, rad, vals=vals)
        off = 1 if zc is not None else 0
        zz = attr[0] if zc is not None else None
        fl_a = attr[off]
        bl_a = attr[off + 1]
        out.append((c, d_c, zz, fl_a, bl_a))
        cmask = np.maximum(cmask, 1.0 - ss(d_c, fl_a, fl_a + bl_a))
        if zc is not None:
            dshape = np.minimum(dshape, d_c)
    return out, cmask, dshape


def wash_canyon(H, cs, X, Y, F):
    """cut the designed wash into H: floor z along W.WASH_PTS, terraced walls (3 benches), meandering outline (noise on the distance)."""
    D = MS._catmull(W.WASH_PTS, ds=20.0)
    seg = np.hypot(*np.diff(D[:, :2], axis=0).T)
    cn = int(round(2 * HALF / cs)) + 1
    d, at = raster_dist((cn, cn), cs, -HALF, D[:, :2], 420.0, vals=D[:, 2:3])
    zf = at[0]
    dn = d * (1.0 + 0.35 * np.clip(F("wash_w", 220.0, 2), -1.2, 1.2)) + 14.0 * F("wash_w2", 70.0, 2)
    w0, w1 = 26.0, 150.0
    u = ss(dn, w0, w0 + w1)
    ut = terrace(u, k=3.0, sharp=0.22) * 0.8 + u * 0.2
    floor = zf + 2.5 * F("wash_f", 40.0, 2)
    Hn = floor + np.maximum(H - floor, 0.0) * ut
    return np.where(d < 420.0, np.minimum(H, np.where(H > floor, Hn, H)), H).astype(np.float32)


def fit_corridor_profiles(corridors, H, cs):
    """for corridors with `auto_z = (gmax, vc_len, [pin_start, pin_end])` replace z by the grade-limited profile fitted to H."""
    import profile as PR
    out = []
    for c in corridors:
        az = c.get("auto_z")
        if not az:
            out.append(c)
            continue
        gmax, vc = az[0], az[1]
        pts = np.asarray(c["pts"], dtype=np.float64)
        seg = np.hypot(*np.diff(pts, axis=0).T)
        sv = np.concatenate([[0.0], np.cumsum(seg)])
        ds = 20.0
        n = int(sv[-1] / ds) + 2
        t = np.linspace(0.0, sv[-1], n)
        px = np.interp(t, sv, pts[:, 0])
        py = np.interp(t, sv, pts[:, 1])
        zt = sample_bilinear(H, px, py, step=cs).astype(np.float64)
        k = 4
        zs = np.convolve(np.pad(zt, (k, k), mode="edge"), np.ones(2 * k + 1) / (2 * k + 1), mode="valid")
        lam = max(1.0, (vc / (2 * math.pi * ds)) ** 4)
        pins = {}
        if len(az) > 2 and az[2] is not None:
            pins[0] = float(az[2])
        if len(az) > 3 and az[3] is not None:
            pins[n - 1] = float(az[3])
        w = np.ones(n)
        z = PR.solve_profile(zs, w, np.full(n - 1, gmax * 0.98), ds, lam, pins)
        z = PR.clamp_grades(z, np.full(n - 1, gmax * 0.98), ds, pins)
        c2 = dict(c)
        c2["z"] = list(zip(t / t[-1], z))
        c2["pts"] = np.stack([px, py], 1)
        c2.pop("auto_z")
        out.append(c2)
    return out


# ================================================================ stage 1: natural terrain, coarse grid
def natural_coarse(verbose=True, cmask_c=None, trace_c=None, dshape_c=None):
    n, xs = grid_axes(CS)
    shape = (n, n)
    X = xs[None, :]
    Y = xs[:, None]
    F = lambda name, wl, octv, **kw: fbm(shape, wl, octv, rng_for(name), step=CS, **kw)
    out = {}
    if verbose:
        log("stage 1: natural terrain on %d x %d (%.0f m)" % (n, n, CS))

    # ---- warp for region masks (big, smooth)
    wx = 320.0 * F("warpx", 1300.0, 3)
    wy = 320.0 * F("warpy", 1300.0, 3)
    Xw, Yw = X + wx, Y + wy

    # ---- shoreline: distance inland (m), positive on land
    Yc = W.coast_Yc(X)
    Xs = W.coast_Xs(Y)
    sl = W.coast_Xs_slope(Y)
    d_east = (Yc - Y).astype(np.float32)
    d_south = ((X - Xs) / np.sqrt(1.0 + sl * sl)).astype(np.float32)
    u_sh = smin(d_east, d_south, 150.0) + 55.0 * F("shore", 420.0, 3) + 28.0 * F("shore2", 150.0, 2)
    for (pts, hw) in W.HEADLANDS:
        u_sh = smax(u_sh, capsule_u(X, Y, pts, hw) + 40.0 * F("head_%d" % int(pts[0][0]), 220.0, 2), 60.0)
    for (cx, cy, rr, dd) in W.COVES:
        u_sh = u_sh - dd * np.exp(-(((X - cx) ** 2 + (Y - cy) ** 2) / (rr * rr)))
    u_sh = u_sh.astype(np.float32)
    out["u_shore"] = u_sh

    # ---- noise fields
    n_a = F("a", 2400.0, 2)
    n_b = F("b", 900.0, 4)
    n_c = F("c", 320.0, 4)
    n_d = F("d", 95.0, 3)
    out.update(n_a=n_a, n_b=n_b, n_c=n_c, n_d=n_d)

    # ---- lowland base: Greenvale hills, hub basin, coast hills, spine valley floor
    r_hub = np.sqrt(X * X + Y * Y)
    trend = 80.0 + 0.021 * (X + 2016.0) - 30.0 * ss(Y, 150.0, 1700.0)
    hills_a = F("hillA", 1150.0, 4)
    hills_b = F("hillB", 400.0, 4)
    hill_ridge = ridged(shape, 520.0, 4, rng_for("hillR"), step=CS, gain=0.5)
    hills = 32.0 * hills_a + 13.0 * hills_b + 9.0 * (hill_ridge - 0.3)
    farm_flat = 1.0 - 0.45 * np.exp(-(((X + 900.0) ** 2 + (Y + 900.0) ** 2) / (700.0 ** 2)))
    hub_flat = 1.0 - 0.8 * np.exp(-(r_hub / 520.0) ** 2)
    calm_c = (1.0 - 0.9 * cmask_c) if cmask_c is not None else 1.0
    L = trend + hills * farm_flat * hub_flat * calm_c
    # a broad, gentle river valley: the lowland slopes down towards the Silverrun over ~1 km on either side
    river0 = W.make_river()
    cn0 = int(round(2 * HALF / CS)) + 1
    d_rc, ra0 = raster_dist((cn0, cn0), CS, -HALF, river0["pts"], 1500.0)
    z_rc = np.interp(Y, river0["pts"][:, 1], river0["z"]).astype(np.float32) + 0.0 * X
    Dv = np.maximum(L - (z_rc + 14.0), 0.0)
    L = L - Dv * ss(1250.0 - d_rc, 0.0, 1100.0) ** 1.25 * 0.95
    out["d_river_c"] = d_rc
    # the Greenvale castle hill
    L = L + 62.0 * np.exp(-(((X + 300.0) ** 2 + (Y + 1000.0) ** 2) / (150.0 ** 2)) ** 1.0) + 22.0 * np.exp(-(((X + 300.0) ** 2 + (Y + 1000.0) ** 2) / (330.0 ** 2)))
    # coastal relief: rolling cliff-top hills and the headland ridges (the cliff road needs real ups and downs)
    L = L + 36.0 * F("cH", 380.0, 3) * ss(u_sh, 40.0, 260.0) * (1.0 - ss(u_sh, 800.0, 1500.0)) * (1.0 - 0.6 * (cmask_c if cmask_c is not None else 0.0))
    for (pts, hw) in W.HEADLANDS:
        L = L + 52.0 * ss(capsule_u(X, Y, pts, hw), 0.0, 170.0) * (0.75 + 0.25 * F("hl_h", 300.0, 2))
    out["L"] = L.astype(np.float32)

    # ---- Sunbaked Plateau: tilted table land (lower in the west, rising towards the east / south-east), escarpment with
    # terraced cliff walls, mesas, buttes, wide basins, noise canyons and one designed wash
    sd = polygon_sdist(shape, CS, W.PLATEAU_POLY, radius=900.0)
    sd_w = sd + (95.0 * np.clip(F("pl_edge", 520.0, 3), -1.3, 1.3) + 32.0 * np.clip(F("pl_edge2", 170.0, 2), -1.3, 1.3)) * np.exp(-(sd / 320.0) ** 2)
    ramp = np.zeros(shape, dtype=np.float32)
    for gp in W.PLATEAU_GAPS:
        dg, _ = raster_dist(shape, CS, -HALF, np.asarray(gp, dtype=float), 900.0)
        ramp = np.maximum(ramp, np.exp(-(dg / 330.0) ** 2).astype(np.float32)) * 0.0       # (gaps disabled: the highway canyon cuts the escarpment)
    t_pl = ss(sd_w, -30.0, 210.0 + 850.0 * ramp)                    # 0 outside -> 1 inside (escarpment ~240 m wide, long ramps where the highway passes)
    t_cl = terrace(t_pl, k=3.0, sharp=0.27) * 0.7 + t_pl * 0.3           # terraced cliff walls
    top = 272.0 + 30.0 * ss(X, 300.0, 1000.0) * (1.0 - ss(Y, 500.0, 1300.0)) - 50.0 * ss(Y, 300.0, 1300.0) + 22.0 * n_b
    if dshape_c is not None:
        top = top - 10.0 * (1.0 - ss(dshape_c, 200.0, 900.0))
    inner = ss(sd_w, 130.0 + 400.0 * ramp, 360.0 + 400.0 * ramp)
    mesa_f = F("mesa", 600.0, 3) + 0.3 * F("mesa2", 260.0, 3)
    mesa = 52.0 * terrace(ss(mesa_f, 0.35, 0.95), k=2.0, sharp=0.33)
    butte_f = F("butte", 280.0, 3)
    butte = 30.0 * terrace(ss(butte_f, 0.95, 1.4), k=2.0, sharp=0.35)
    can = np.abs(F("canA", 880.0, 3) + 0.24 * F("canA2", 380.0, 3))
    canyon = 70.0 * terrace(1.0 - ss(can, 0.035, 0.17), k=3.0, sharp=0.32)
    can2 = np.abs(F("canB", 420.0, 3))
    canyon2 = 30.0 * terrace(1.0 - ss(can2, 0.03, 0.12), k=2.0, sharp=0.3)
    basin = 36.0 * ss(F("basinP", 1300.0, 2), 0.1, 0.9)
    inner_c = inner * ((1.0 - 0.5 * cmask_c) if cmask_c is not None else 1.0)
    plat_top = top + (mesa + butte - canyon - canyon2 - basin) * inner_c + 8.0 * n_c * inner_c
    plat_top = strata(plat_top, 14.0, 0.6 * inner, 6.0 * n_b, sharp=0.3)
    Hpl = L + (plat_top - L) * t_cl
    Hpl = np.where(t_pl > 0.002, Hpl, L)
    # designed wash: a winding, terraced canyon (stepped walls) that runs from the plateau interior out through the escarpment
    Hpl = wash_canyon(Hpl, CS, X, Y, F)
    out["t_pl"] = t_pl

    # ---- Highcrest massif
    Hm, env_m = MS.build(CS, n, X, Y, L, F, calm=trace_c)
    out["env_m"] = env_m

    # ---- combine: the plateau uplift and the massif uplift both stand on the lowland base
    H = L + (Hpl - L) + (Hm - L)
    H = H.astype(np.float32)
    out["H_nat"] = H

    # ---- region scores (smooth, warped) -> weights
    sc = {}
    sc["Highcrest"] = ss(env_m, 70.0, 280.0)
    sc["Plateau"] = ss(sd_w, -150.0, 260.0)
    sc["Coast"] = 1.0 - ss(u_sh + 70.0 * F("coast_w", 500.0, 2), 160.0, 1000.0)
    sc["Basin"] = np.exp(-(np.sqrt((Xw) ** 2 + (Yw) ** 2) * (1.0 + 0.32 * F("basin_m", 800.0, 2)) / 720.0) ** 2)
    sc["Greenvale"] = 0.55 * (1.0 - np.maximum.reduce([sc["Highcrest"], sc["Plateau"], sc["Coast"], sc["Basin"]])) + 0.02
    names = ("Greenvale", "Highcrest", "Plateau", "Coast", "Basin")
    stack = np.stack([np.maximum(sc[k], 0.0) ** 2.6 + 1e-4 for k in names]).astype(np.float32)
    stack /= stack.sum(axis=0, keepdims=True)
    out["wstack_c"] = stack
    return out


# ================================================================ stage 2 + 3
def build_macro(step=2.0, corridors=(), verbose=True, trace_corridors=()):
    """Returns dict with macro natural terrain and ancillary fields (all [j,i], float32) on the `step` grid."""
    n, xs = grid_axes(step)
    shape = (n, n)
    X = xs[None, :]
    Y = xs[:, None]
    F = lambda name, wl, octv, **kw: fbm(shape, wl, octv, rng_for(name), step=step, **kw)
    shaping_c, cmask_c, dshape_c = corridor_fields(corridors, CS)
    trace_c = corridor_fields(trace_corridors, CS)[1] if len(trace_corridors) else None
    nat = natural_coarse(verbose, cmask_c, trace_c, dshape_c)
    # corridors flagged auto_z: the vertical profile is fitted (grade limited, smooth) to the natural terrain of stage 1
    corridors = fit_corridor_profiles(corridors, nat["H_nat"], CS)
    shaping_c, cmask_c, dshape_c = corridor_fields(corridors, CS)
    up = lambda A: upsample_to(A, CS, step)
    H = up(nat["H_nat"])
    u_sh = up(nat["u_shore"])
    n_a, n_b, n_c, n_d = (up(nat[k]) for k in ("n_a", "n_b", "n_c", "n_d"))
    wstack = np.stack([up(nat["wstack_c"][k]) for k in range(5)])
    wstack = np.maximum(wstack, 0.0)
    wstack /= np.maximum(wstack.sum(axis=0, keepdims=True), 1e-6)
    t_pl = up(nat["t_pl"])
    if verbose:
        log("upsampled natural terrain to the %.0f m grid" % step)

    # ---------------------------------------------------------------- shore carving: cliffs, beaches, sea
    u = u_sh + 14.0 * F("shore_f", 70.0, 2) + 5.0 * F("shore_g", 26.0, 2)
    d_east = (W.coast_Yc(X) - Y).astype(np.float32)
    top = np.maximum(H, 12.0)
    bay_near = np.exp(-(((X + 350.0) / 520.0) ** 2 + ((Y - 1300.0) / 680.0) ** 2))
    top = top * (1 - 0.85 * bay_near) + (W.BAY_BANK_TOP + 4.0 * n_c) * 0.85 * bay_near
    fw = 22.0 + 26.0 * (0.5 + 0.5 * np.clip(n_d, -1.0, 1.0))
    cliff = top * ss(u, 0.0, fw)
    # beaches in the south gulf and at the coves
    d_south = ((X - W.coast_Xs(Y)) / np.sqrt(1.0 + W.coast_Xs_slope(Y) ** 2)).astype(np.float32)
    wS = ss(d_east - d_south, -80.0, 420.0)
    bn = F("beach", 520.0, 2)
    bm = np.clip(wS * ss(bn, -0.6, 0.15), 0, 1)
    for (cx, cy, rr, dd) in W.COVES:
        bm = np.maximum(bm, np.exp(-(((X - cx) ** 2 + (Y - cy) ** 2) / ((0.9 * rr) ** 2))))
    bp = np.minimum(0.06 * np.maximum(u, 0.0), 5.5) + 3.2 * ss(u, 70.0, 220.0) * (0.5 + 0.5 * n_c) + 1.5 * n_d * ss(u, 20.0, 80.0)
    bp = bp * (1 - ss(u, 60.0, 210.0)) + top * ss(u, 60.0, 210.0)
    land_c = cliff * (1 - bm) + bp * bm
    sea_c = -np.minimum(0.07 * np.maximum(-u, 0.0), 6.0) - 0.03 * np.maximum(-u - 85.0, 0.0)
    sea_c = np.maximum(sea_c, -50.0) + 0.8 * n_d * ss(-u, 5.0, 60.0)
    H = np.where(u >= 0, land_c, sea_c).astype(np.float32)
    bm_out = bm

    # ---------------------------------------------------------------- terrain shaping corridors (smooth graded approaches)
    cmask = up(cmask_c) if step < CS else cmask_c
    cmask = np.clip(cmask, 0.0, 1.0).astype(np.float32)
    for c, d_c0, zz0, fl0, bl0 in shaping_c:
        if zz0 is None:
            continue
        d_c = resize_to(d_c0, CS, step)
        zz = resize_to(zz0, CS, step)
        fl_a = resize_to(fl0, CS, step)
        bl_a = resize_to(bl0, CS, step)
        w_c = (1.0 - ss(d_c, fl_a, fl_a + bl_a))
        if c.get("terrace"):
            w_c = terrace(w_c, k=float(c["terrace"]), sharp=0.3) * 0.7 + w_c * 0.3
        w_c = w_c * c.get("strength", 0.9)
        cross = c.get("cross", 0.04)
        nz = c.get("noise", 2.5)
        surf = zz + cross * np.maximum(d_c - fl_a, 0.0) + nz * (0.6 * n_d + 0.4 * n_c)
        H = H + w_c * (surf - H)

    # ---------------------------------------------------------------- flat platforms for settlements and stations
    # the platform height is the mean terrain inside the flat radius; the blend zone is widened with the local relief so the
    # cut / fill stays at slopes of about 1:2.4 (no perched mesas with cliffs all around)
    for (pname, px, py, rf, rb, pz) in W.PLATFORMS:
        r_all = (rf + 260.0) * 1.9
        i0 = max(0, int((px + HALF - r_all) / step))
        i1 = min(n - 1, int((px + HALF + r_all) / step) + 1)
        j0 = max(0, int((py + HALF - r_all) / step))
        j1 = min(n - 1, int((py + HALF + r_all) / step) + 1)
        sub = H[j0:j1 + 1, i0:i1 + 1]
        xx = xs[i0:i1 + 1][None, :]
        yy = xs[j0:j1 + 1][:, None]
        dd = np.sqrt((xx - px) ** 2 + (yy - py) ** 2)
        dd = dd * (1.0 + 0.30 * np.clip(F("plat_%s" % pname, 140.0, 2)[j0:j1 + 1, i0:i1 + 1], -1.2, 1.2))      # irregular outline
        if pz is None:
            m = dd <= rf
            z0 = float(sub[m].mean()) if m.any() else float(sub.mean())
        else:
            z0 = float(pz)
        ring = (dd > rf) & (dd < rf + rb + 60.0)
        rel = float(np.percentile(np.abs(sub[ring] - z0), 85)) if ring.any() else 0.0
        rb_eff = float(np.clip(2.4 * rel, rb, 240.0))
        wpf = 1.0 - ss(dd, rf, rf + rb_eff)
        H[j0:j1 + 1, i0:i1 + 1] = sub + wpf * (z0 - sub)

    # ---------------------------------------------------------------- river valley and channel
    river = W.make_river()
    cstep = max(step, 8.0)
    cn = int(round(2 * HALF / cstep)) + 1
    rv = np.stack([river["z"], river["width"], river["depth"], river["s"]], 1)
    d_r, ra = raster_dist((cn, cn), cstep, -HALF, river["pts"], 520.0, vals=rv)
    d_r = resize_to(d_r, cstep, step)
    z_r = resize_to(ra[0], cstep, step)
    w_r = resize_to(ra[1], cstep, step)
    dep_r = resize_to(ra[2], cstep, step)
    s_r = resize_to(ra[3], cstep, step)
    del ra
    if step < cstep:
        d_fine, ra2 = raster_dist((n, n), step, -HALF, river["pts"], 60.0, vals=rv[:, :3])
        near = d_fine < 56.0
        d_r = np.where(near, d_fine, d_r)
        z_r = np.where(near, ra2[0], z_r)
        w_r = np.where(near, ra2[1], w_r)
        dep_r = np.where(near, ra2[2], dep_r)
        del d_fine, ra2
    z_y = (np.interp(Y, river["pts"][:, 1], river["z"]).astype(np.float32) + 0.0 * X)
    wz = ss(d_r, 30.0, 90.0)
    z_r = z_r * (1 - wz) + z_y * wz
    zf = z_r + 2.2
    fp = 38.0 + 46.0 * ss(F("fp", 700.0, 2), -0.6, 0.8)                     # flood plain half width varies along the river
    plain = zf + 0.012 * np.maximum(d_r - 20.0, 0.0) + 0.7 * n_d * ss(d_r, 30.0, 120.0)
    wv_hard = 1.0 - ss(d_r, fp, fp + 120.0)
    H = H + wv_hard * (plain - H)
    wv_soft = 1.0 - ss(d_r, fp + 60.0, fp + 460.0)
    ext = zf + 0.065 * np.maximum(d_r - fp, 0.0)
    H = np.where(d_r > fp, H + wv_soft * (np.minimum(H, ext) - H), H)
    cs = d_r / np.maximum(w_r * 0.5, 1.0)
    bed = z_r - dep_r * (1.0 - np.minimum(cs, 1.0) ** 2)
    bank = z_r + (zf - z_r) * ss(cs, 1.0, 2.4)
    chan = np.where(cs < 1.0, bed, np.where(cs < 2.4, bank, 1e9))
    H = np.minimum(H, chan)
    river_mask = (cs < 1.0)
    water_river = np.where(river_mask, z_r, np.float32(-9999.0)).astype(np.float32)
    del d_r, z_r, w_r, dep_r, cs, bed, bank, chan, plain, ext, s_r

    # ---------------------------------------------------------------- tributary streams (drainage derived)
    streams = derive_streams(H, step, river)
    for st in streams:
        hw = float(st.get("half", 3.8))
        d_s, sa = raster_dist(shape, step, -HALF, st["pts"], 2.0 * hw, vals=st["z"][:, None])
        ch = float(st.get("cut", 1.7)) * np.clip(1.0 - (d_s / hw) ** 2, 0.0, 1.0)
        ch = ch * (d_s < 2.0 * hw)
        H = H - ch

    # ---------------------------------------------------------------- Great Bay inlet
    bay_vals = np.stack([W.BAY_HALF, W.BAY_FLOOR], 1)
    bp_ = W.BAY_PTS
    seg = np.sqrt((np.diff(bp_, axis=0) ** 2).sum(1))
    sv = np.concatenate([[0.0], np.cumsum(seg)])
    dense_s = np.arange(0.0, sv[-1] + 10.0, 10.0)
    px = np.interp(dense_s, sv, bp_[:, 0])
    py = np.interp(dense_s, sv, bp_[:, 1])
    # irregular shores: lateral wobble of the centre line and of the width
    wob = 18.0 * np.sin(dense_s / 130.0 + 0.7) + 9.0 * np.sin(dense_s / 47.0 + 1.9)
    px = px + wob * 0.9
    hw = np.interp(dense_s, sv, W.BAY_HALF) + 14.0 * np.sin(dense_s / 95.0 + 2.2)
    fl = np.interp(dense_s, sv, W.BAY_FLOOR)
    d_b, ba = raster_dist((cn, cn), cstep, -HALF, np.stack([px, py], 1), 470.0, vals=np.stack([hw, fl], 1))
    d_b = resize_to(d_b, cstep, step)
    hw_b = resize_to(ba[0], cstep, step)
    fl_b = resize_to(ba[1], cstep, step)
    del ba
    ub = d_b / np.maximum(hw_b, 1.0) + 0.05 * n_c * ss(d_b, 0, 200) + 0.04 * n_d
    wall = ss(ub, 0.80, 1.0)
    floor = fl_b * (1.0 + 0.35 * (1.0 - np.minimum(ub, 1.0) ** 2)) + 1.2 * n_d
    bay_h = floor * (1 - wall) + H * wall
    H = np.where(ub < 1.0, np.minimum(H, bay_h), H)
    del d_b, hw_b, fl_b, ub, wall, floor, bay_h

    # ---------------------------------------------------------------- rocky sea stacks
    for (sx, sy, sr, sh) in W.SEA_STACKS:
        dd = np.sqrt((X - sx) ** 2 + (Y - sy) ** 2)
        peak = sh * (1.0 - ss(dd, 0.35 * sr, sr)) * (0.85 + 0.15 * n_d)
        H = np.maximum(H, np.where(dd < sr * 1.3, peak - 2.0 + 4.0 * (1.0 - ss(dd, 0.0, sr)), -1e9).astype(np.float32))

    # ---------------------------------------------------------------- border ring (steep rock on land edges)
    e = np.minimum(HALF - np.abs(X), HALF - np.abs(Y))
    ringn = 0.55 + 0.45 * ridged(shape, 260.0, 4, rng_for("ring"), step=step)
    ew = e + 80.0 * F("ring_w", 360.0, 2)
    ring = (110.0 * ss(250.0 - ew, 0.0, 250.0) ** 1.4 + 150.0 * ss(80.0 - ew, 0.0, 80.0)) * ringn
    land = H > 3.0
    H = np.where(land, H + ring * (1.0 - ss(H, 400.0, 760.0)), H)
    H = np.where(~land, H - 8.0 * ss(110.0 - e, 0.0, 110.0), H)
    H = np.clip(H, -58.0, 755.0).astype(np.float32)

    wstack_full = wstack.astype(np.float32)
    rid = np.argmax(wstack_full, axis=0).astype(np.uint8)
    return dict(step=step, n=n, H=H, wstack=wstack_full, region=rid, cmask=cmask, water_river=water_river,
                n_a=n_a, n_b=n_b, n_c=n_c, n_d=n_d, u_shore=u_sh, bm=bm_out, streams=streams, river=river, t_pl=t_pl,
                env_m=up(nat["env_m"]))


def derive_streams(H, step, river, a_min_cells=2600.0, max_streams=10):
    """named tributary streams traced along the steepest-descent drainage of the natural terrain."""
    f = 4 if step < 8 else 1
    cs = step * f
    Hc = H[::f, ::f] if f > 1 else H
    fl = ER.flow(gauss_blur(Hc, 1.0).astype(np.float32), sea_level=0.0)
    return []


def add_tunnel_ridge(H1, A, B, h, half_w=70.0, taper=0.10):
    """raise a ridge (rocky shoulder) along the chord A -> B on the 1 m grid (in place). Height h at the middle, zero at the
    portals (the ends keep the natural terrain), lateral Gaussian profile of half width `half_w`."""
    A = np.asarray(A, dtype=np.float64)
    B = np.asarray(B, dtype=np.float64)
    D = float(np.hypot(*(B - A)))
    ux, uy = (B - A) / D
    R = half_w * 2.6 + 20.0
    i0 = max(0, int(min(A[0], B[0]) + HALF - R))
    i1 = min(N - 1, int(max(A[0], B[0]) + HALF + R))
    j0 = max(0, int(min(A[1], B[1]) + HALF - R))
    j1 = min(N - 1, int(max(A[1], B[1]) + HALF + R))
    xs = np.arange(i0, i1 + 1, dtype=np.float64) - HALF
    ys = np.arange(j0, j1 + 1, dtype=np.float64) - HALF
    px = xs[None, :] - A[0]
    py = ys[:, None] - A[1]
    t = (px * ux + py * uy) / D
    u = -px * uy + py * ux
    along = np.clip(np.sin(np.pi * np.clip(t, 0.0, 1.0)), 0.0, 1.0) ** 0.7 * ((t > -0.05) & (t < 1.05))
    prof = np.exp(-(u / half_w) ** 2) * along
    rng = np.random.default_rng(7)
    sub = H1[j0:j1 + 1, i0:i1 + 1]
    H1[j0:j1 + 1, i0:i1 + 1] = sub + (h * prof).astype(np.float32) * (0.9 + 0.1 * np.sin(0.09 * (px + 2.0 * py)).astype(np.float32))


def bench_slopes(H1, polylines, s_t=0.38, full=10.0, fade=95.0, stride=4):
    """gentle road shoulders: where the natural cross slope near a (mountain / dirt) road is steeper than s_t, the terrain is
    relaxed towards a plane through the road's (smoothed) ground height with cross slope s_t (uphill side higher). The result is
    a graded shoulder of ~50-90 m instead of a vertical cut; steeper natural ground (cliffs, scree) starts beyond it. In place."""
    n = H1.shape[0]
    XS = (np.arange(N, dtype=np.float32) - np.float32(HALF))
    Dm = np.full(H1.shape, np.float32(1e4))
    ZS = np.zeros(H1.shape, dtype=np.float32)
    SG = np.zeros(H1.shape, dtype=np.float32)
    UU = np.zeros(H1.shape, dtype=np.float32)
    for P in polylines:
        P = np.asarray(P, dtype=np.float64)
        zr = sample_bilinear(H1, P[:, 0], P[:, 1]).astype(np.float64)
        k = 7
        zs = np.convolve(np.pad(zr, (k, k), mode="edge"), np.ones(2 * k + 1) / (2 * k + 1), mode="valid")
        t = np.gradient(P, axis=0)
        t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-9)
        nrm = np.stack([-t[:, 1], t[:, 0]], 1)
        zl = sample_bilinear(H1, P[:, 0] + nrm[:, 0] * 25.0, P[:, 1] + nrm[:, 1] * 25.0)
        zq = sample_bilinear(H1, P[:, 0] - nrm[:, 0] * 25.0, P[:, 1] - nrm[:, 1] * 25.0)
        sg = np.sign(zl - zq)
        sg = np.convolve(np.pad(sg, (k, k), mode="edge"), np.ones(2 * k + 1) / (2 * k + 1), mode="valid")
        idx = list(range(0, len(P) - 1, stride))
        for a_i, b_i in zip(idx[:-1] + [idx[-1]], idx[1:] + [len(P) - 1]):
            if b_i <= a_i:
                continue
            A, B = P[a_i], P[b_i]
            R = fade + 6.0
            i0 = max(0, int(math.floor(min(A[0], B[0]) - R + HALF)))
            i1 = min(N - 1, int(math.ceil(max(A[0], B[0]) + R + HALF)))
            j0 = max(0, int(math.floor(min(A[1], B[1]) - R + HALF)))
            j1 = min(N - 1, int(math.ceil(max(A[1], B[1]) + R + HALF)))
            if i1 < i0 or j1 < j0:
                continue
            px = XS[i0:i1 + 1][None, :] - np.float32(A[0])
            py = XS[j0:j1 + 1][:, None] - np.float32(A[1])
            dx, dy = float(B[0] - A[0]), float(B[1] - A[1])
            L2 = dx * dx + dy * dy
            tt = np.clip((px * np.float32(dx) + py * np.float32(dy)) / np.float32(L2), 0.0, 1.0)
            ex = px - tt * np.float32(dx)
            ey = py - tt * np.float32(dy)
            dist = np.sqrt(ex * ex + ey * ey)
            Lh = math.sqrt(L2)
            off = ey * np.float32(dx / Lh) - ex * np.float32(dy / Lh)           # signed lateral offset (right positive)
            sub = Dm[j0:j1 + 1, i0:i1 + 1]
            better = dist < sub
            if not better.any():
                continue
            sub[better] = dist[better]
            zA = np.float32(0.5 * (zs[a_i] + zs[b_i]))
            sgn = np.float32(0.5 * (sg[a_i] + sg[b_i]))
            ZS[j0:j1 + 1, i0:i1 + 1][better] = zA
            SG[j0:j1 + 1, i0:i1 + 1][better] = sgn
            UU[j0:j1 + 1, i0:i1 + 1][better] = off[better]                          # positive on the +normal side (same side as sg)
    w = (1.0 - ss(Dm, full, fade)).astype(np.float32)
    target = ZS + np.float32(s_t) * SG * UU
    # relax only where the natural ground is steeper than the target plane (further from z_s on the same side)
    steeper = np.abs(H1 - ZS) > np.abs(target - ZS)
    steeper &= (np.sign(H1 - ZS) == np.sign(target - ZS)) | (np.abs(target - ZS) < 0.5)
    w = w * steeper
    del steeper
    H1 += w * (target - H1)


def smooth_road_corridors(H1, polylines, sigma_m=22.0, full=32.0, fade=120.0, step=4.0):
    """road builders fill gullies and shave spurs: blend H1 towards a heavily blurred copy near the given road polylines
    (list of (n,2) arrays). In place. Works through a coarse distance field (step m) interpolated to 1 m."""
    cn = int(round(2 * HALF / step)) + 1
    dist = None
    for P in polylines:
        d, _ = raster_dist((cn, cn), step, -HALF, np.asarray(P, dtype=np.float64)[::3], fade + 10.0, dist=dist)
        dist = d
    if dist is None:
        return
    w = (1.0 - ss(dist, full, fade)).astype(np.float32)
    w1 = resize_to(w, step, 1.0)
    del dist, w
    if float(w1.max()) <= 0.0:
        return
    bl = gauss_blur(H1.astype(np.float32), sigma_m)
    H1 += w1 * (bl - H1)


# ================================================================ 1 m detail
def finalize_1m(M, verbose=True):
    """Upsample macro terrain to the 4033 grid and add 1 m detail. Returns H1 [j,i] float32."""
    step = M["step"]
    H = M["H"]
    if abs(step - 2.0) < 1e-6:
        H1 = upsample2(H)
    else:
        H1 = resize_to(H, step, 1.0)
    assert H1.shape == (N, N), H1.shape
    if verbose:
        log("upsampled to %s" % (H1.shape,))
    rough_by_region = np.array([W.REGION_PARAMS[k]["rough"] for k in ("Greenvale", "Highcrest", "Plateau", "Coast", "Basin")],
                               dtype=np.float32)
    rough = np.tensordot(rough_by_region, M["wstack"], axes=(0, 0))
    gy, gx = np.gradient(M["H"], step)
    slope = np.sqrt(gx * gx + gy * gy)
    rough = rough * (0.7 + 1.8 * ss(slope, 0.25, 0.9)) * (1.0 - 0.75 * M["cmask"])
    rough1 = resize_to(rough.astype(np.float32), step, 1.0)
    rng = rng_for("detail")
    d = fbm((N, N), 46.0, 5, rng, step=1.0, gain=0.55)
    land1 = H1 > 0.3
    H1 = H1 + d * rough1 * np.where(land1, 1.0, 0.25).astype(np.float32)
    steep1 = resize_to(ss(slope, 0.35, 1.0).astype(np.float32), step, 1.0)
    rd = ridged((N, N), 28.0, 4, rng_for("rockdetail"), step=1.0)
    H1 = H1 + (rd - 0.3) * 2.2 * steep1 * (1.0 - 0.8 * resize_to(M["cmask"], step, 1.0))
    H1 = np.clip(H1, -58.0, 757.0).astype(np.float32)
    return H1
