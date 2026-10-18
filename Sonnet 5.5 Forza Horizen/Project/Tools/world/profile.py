"""Vertical profile design: grade-limited smooth elevation profile, bridge / tunnel / culvert detection,
superelevation. The profile solver is a banded (pentadiagonal) least-squares with an active-set grade limit."""
import math

import numpy as np

import roads_def as RD
from common import sample_bilinear, HALF

FLAG_BRIDGE = 1
FLAG_TUNNEL = 2
FLAG_CULVERT = 4
FLAG_JUNCTION = 8
FLAG_HAIRPIN = 16
FLAG_PORTAL = 32

FILL_BRIDGE_M = 6.5       # road more than this above the terrain over >= 24 m -> bridge (smaller fills are embankments)
FILL_BRIDGE_BY_CLASS = {"MOUNTAIN": 18.0, "DIRT": 12.0, "SHORTCUT": 12.0}
CLOSING_DEPTH_BY_CLASS = {"MOUNTAIN": 36.0, "DIRT": 28.0, "SHORTCUT": 28.0}
TUNNEL_COVER_MIN = 2.5   # m of natural terrain above the deck where a forced tunnel span really starts / ends
CUT_TUNNEL_M = 1.0e9     # geometric tunnels are disabled: tunnels exist only where a road definition forces them (tracer shoulder tunnels)


def _penta_solve(d0, d1, d2, b):
    """Solve symmetric positive definite pentadiagonal system.
    d0[i] = A[i,i], d1[i] = A[i,i-1], d2[i] = A[i,i-2]."""
    n = len(d0)
    l0 = [0.0] * n
    l1 = [0.0] * n
    l2 = [0.0] * n
    for i in range(n):
        a2 = d2[i] / l0[i - 2] if i >= 2 else 0.0
        a1 = (d1[i] - (a2 * l1[i - 1] if i >= 2 else 0.0)) / l0[i - 1] if i >= 1 else 0.0
        v = d0[i] - a2 * a2 - a1 * a1
        if v <= 1e-18:
            v = 1e-18
        l0[i] = math.sqrt(v)
        l1[i] = a1
        l2[i] = a2
    y = [0.0] * n
    for i in range(n):
        s = b[i]
        if i >= 1:
            s -= l1[i] * y[i - 1]
        if i >= 2:
            s -= l2[i] * y[i - 2]
        y[i] = s / l0[i]
    x = [0.0] * n
    for i in range(n - 1, -1, -1):
        s = y[i]
        if i + 1 < n:
            s -= l1[i + 1] * x[i + 1]
        if i + 2 < n:
            s -= l2[i + 2] * x[i + 2]
        x[i] = s / l0[i]
    return np.array(x)


def solve_profile(target, w, gmax, ds, lam, pins=None, iters=80, mu_scale=2e3):
    """target (n,), w (n,) weights, gmax (n-1,) allowed |grade| per segment, ds spacing (m).
    pins: dict idx -> z (hard). Returns z (n,)."""
    n = len(target)
    w = np.asarray(w, dtype=float).copy()
    t = np.asarray(target, dtype=float)
    pins = pins or {}
    for i, z in pins.items():
        w[i] = 1e6
        t = t.copy()
        t[i] = z
    d0 = np.zeros(n)
    d1 = np.zeros(n)
    d2 = np.zeros(n)
    if n > 2:
        d0[:-2] += lam
        d0[1:-1] += 4 * lam
        d0[2:] += lam
        d1[1:-1] += -2 * lam
        d1[2:] += -2 * lam
        d2[2:] += lam
    d0 += w
    rhs0 = w * t
    act = np.zeros(n - 1, dtype=bool)
    sig = np.zeros(n - 1)
    mu = mu_scale * max(1.0, float(np.median(w[w < 1e5])) if (w < 1e5).any() else 1.0)
    z = _penta_solve((d0).tolist(), d1.tolist(), d2.tolist(), rhs0.tolist())
    gl = np.asarray(gmax, dtype=float) * ds
    for it in range(iters):
        dz = np.diff(z)
        viol = np.abs(dz) > gl * (1.0 + 2e-4)
        newact = act | viol
        if (not viol.any()) and it > 0:
            break
        sig = np.where(viol, np.sign(dz), sig)
        act = newact
        e0 = d0.copy()
        e1 = d1.copy()
        rhs = rhs0.copy()
        m = mu * act
        e0[:-1] += m
        e0[1:] += m
        e1[1:] += -m
        tgt = m * sig * gl
        rhs[1:] += tgt
        rhs[:-1] -= tgt
        z = _penta_solve(e0.tolist(), e1.tolist(), d2.tolist(), rhs.tolist())
    return z


def clamp_grades(z, gmax, ds, pins=None):
    """forward/backward sweeps to remove residual grade violations (tiny after the solver)."""
    z = z.copy()
    gl = np.asarray(gmax) * ds
    n = len(z)
    fixed = set((pins or {}).keys())
    for _ in range(3):
        for i in range(n - 1):
            if i + 1 in fixed:
                continue
            lo, hi = z[i] - gl[i], z[i] + gl[i]
            if z[i + 1] > hi:
                z[i + 1] = hi
            elif z[i + 1] < lo:
                z[i + 1] = lo
        for i in range(n - 2, -1, -1):
            if i in fixed:
                continue
            lo, hi = z[i + 1] - gl[i], z[i + 1] + gl[i]
            if z[i] > hi:
                z[i] = hi
            elif z[i] < lo:
                z[i] = lo
    return z


def cubic_resample(s_nodes, z_nodes, s_q):
    """Catmull-Rom interpolation of nodal values to query positions."""
    n = len(s_nodes)
    h = s_nodes[1] - s_nodes[0]
    u = np.clip((s_q - s_nodes[0]) / h, 0, n - 1 - 1e-9)
    i = np.floor(u).astype(int)
    t = u - i
    zm1 = z_nodes[np.clip(i - 1, 0, n - 1)]
    z0 = z_nodes[i]
    z1 = z_nodes[np.clip(i + 1, 0, n - 1)]
    z2 = z_nodes[np.clip(i + 2, 0, n - 1)]
    return 0.5 * ((2 * z0) + (-zm1 + z1) * t + (2 * zm1 - 5 * z0 + 4 * z1 - z2) * t * t + (-zm1 + 3 * z0 - 3 * z1 + z2) * t ** 3)


def runs(mask):
    """list of (start, end_inclusive) of True runs"""
    out = []
    n = len(mask)
    i = 0
    while i < n:
        if mask[i]:
            j = i
            while j + 1 < n and mask[j + 1]:
                j += 1
            out.append((i, j))
            i = j + 1
        else:
            i += 1
    return out


def sliding(a, win, fn):
    """windowed max / min with odd-reflection padding (a monotone profile is its own closing, ends are not biased)"""
    from numpy.lib.stride_tricks import sliding_window_view
    n = len(a)
    if n > win + 1:
        left = 2 * a[0] - a[1:win + 1][::-1]
        right = 2 * a[-1] - a[-win - 1:-1][::-1]
        pad = np.concatenate([left, a, right])
    else:
        pad = np.pad(a, (win, win), mode="edge")
    v = sliding_window_view(pad, 2 * win + 1)
    return fn(v, axis=1)[:n]


def design_profile(road, al, H1, water_z, pins, flat_zones, streams, log=None):
    """road: road dict, al: alignment dict (xy, s, kappa, spans). H1: natural terrain at 1 m. water_z at 1 m.
    pins: dict sample_index -> z (hard). flat_zones: list of (s0, s1) where grade <= 3.5%.
    Returns dict(z, terrain, grade, flags, bank, bridge_spans, tunnel_spans, ...)."""
    c = RD.CLASSES[road["cls"]]
    xy = al["xy"]
    s = al["s"]
    n = len(s)
    ds = s[1] - s[0]
    t = sample_bilinear(H1, xy[:, 0], xy[:, 1]).astype(float)
    # light de-noising of the target (1 m detail noise)
    k = max(1, int(round(3.0 / ds)))
    ker = np.ones(2 * k + 1) / (2 * k + 1)
    tp = np.pad(t, (k, k), mode="edge")
    t_s = np.convolve(tp, ker, mode="valid")
    wet = np.zeros(n, dtype=bool)
    if water_z is not None:
        ii = np.clip(np.round(xy[:, 0] + HALF).astype(int), 0, H1.shape[1] - 1)
        jj = np.clip(np.round(xy[:, 1] + HALF).astype(int), 0, H1.shape[0] - 1)
        wz = water_z[jj, ii]
        wet = wz > -9000
        water_level = np.where(wet, wz, -1e9)
    else:
        water_level = np.full(n, -1e9)
    sea = t_s < 0.4
    # hairpin arcs: tight curves turning >= 100 deg. They sit on benches cut into the slope: low weight, no geometric flags
    kap0 = al["kappa"]
    hair = np.zeros(n, dtype=bool)
    tight = np.abs(kap0) > 1.0 / 70.0
    for a, b in runs(tight):
        turn = abs(float(np.sum(kap0[a:b + 1])) * ds)
        if turn >= math.radians(100.0):
            hair[max(0, a - int(18 / ds)):min(n, b + 1 + int(18 / ds))] = True
    # ---- forced spans
    bridge = np.zeros(n, dtype=bool)
    tunnel = np.zeros(n, dtype=bool)
    forced_b = []
    forced_t = []
    for kind, sa, sb in al["spans"]:
        ia = int(np.searchsorted(s, sa))
        ib = int(np.searchsorted(s, sb))
        if kind == "bridge":
            bridge[ia:ib + 1] = True
            forced_b.append((ia, ib))
        elif kind == "tunnel":
            tunnel[ia:ib + 1] = True
            forced_t.append((ia, ib))
    reasons = {"forced": bridge.copy()}
    # ---- wet crossings (river) -> bridge
    wet_x = wet | sea
    for a, b in runs(wet_x):
        a2 = max(0, int(a - 12 / ds))
        b2 = min(n - 1, int(b + 12 / ds))
        bridge[a2:b2 + 1] = True
    reasons["wet"] = bridge & ~reasons["forced"]
    # ---- narrow deep gaps (canyons / gullies) -> bridge via morphological closing
    win = int(150.0 / ds)
    closed = sliding(sliding(t_s, win, np.max), win, np.min)
    depth = closed - t_s
    for a, b in runs(depth > CLOSING_DEPTH_BY_CLASS.get(road["cls"], 22.0)):
        if (b - a) * ds > 14.0 and (b - a) * ds < 290.0 and not tunnel[a:b + 1].any() and not hair[a:b + 1].all():
            a2 = max(0, a - 3)
            b2 = min(n - 1, b + 3)
            bridge[a2:b2 + 1] = True
    reasons["closing"] = bridge & ~reasons["forced"] & ~reasons["wet"]
    # target
    tgt = t_s.copy()
    w = np.ones(n)
    w[hair] = 0.12
    for a, b in runs(bridge):
        a0 = max(0, a - 1)
        b0 = min(n - 1, b + 1)
        za, zb = t_s[a0], t_s[b0]
        chord = za + (zb - za) * (np.arange(a, b + 1) - a0) / max(b0 - a0, 1)
        clos = closed[a:b + 1]
        tt = np.maximum(chord, clos * 0.0 + chord)
        # keep the deck well above water
        lvl = np.maximum(water_level[a:b + 1] + 5.0, np.where(t_s[a:b + 1] < 0.4, 5.0, -1e9))
        tgt[a:b + 1] = np.maximum(tt, lvl)
        w[a:b + 1] = 0.006
    for a, b in runs(tunnel):
        za, zb = t_s[a] - 0.3, t_s[b] - 0.3
        tgt[a:b + 1] = za + (zb - za) * (np.arange(a, b + 1) - a) / max(b - a, 1)
        w[a:b + 1] = 1.0
    # ---- solve on a 6 m grid
    dsp = 6.0
    npn = int(math.ceil(s[-1] / dsp)) + 1
    sp = np.linspace(0, s[-1], npn)
    dsp = sp[1] - sp[0]
    tp = np.interp(sp, s, tgt)
    wp = np.interp(sp, s, w)
    gmax = np.full(npn - 1, c["g_max"])
    for (a, b) in forced_t:
        sa_, sb_ = s[a], s[b]
        m = (0.5 * (sp[:-1] + sp[1:]) >= sa_) & (0.5 * (sp[:-1] + sp[1:]) <= sb_)
        gmax[m] = min(c["g_max"], c.get("g_tunnel", 0.075))
    for (z0, z1) in flat_zones:
        m = (0.5 * (sp[:-1] + sp[1:]) >= z0) & (0.5 * (sp[:-1] + sp[1:]) <= z1)
        gmax[m] = np.minimum(gmax[m], 0.035)
    # reduce the design limit slightly so the cubic interpolation to 2 m stays below the hard limit
    gdes = gmax * 0.985
    pp = {}
    for i, z in pins.items():
        k2 = int(round(s[i] / dsp))
        pp[min(k2, npn - 1)] = z
    lam = max(1.0, (c["vc_len"] / (2 * math.pi * dsp)) ** 4)
    zp = solve_profile(tp, wp, gdes, dsp, lam, pp)
    # re-weight where the profile strays from the terrain (cuts / fills that the grade limit allows us to avoid)
    for _ in range(3):
        dev = np.abs(zp - tp)
        wr = wp * (1.0 + 3.0 * np.clip((dev - 1.5) / 3.0, 0.0, 1.0))
        zp = solve_profile(tp, wr, gdes, dsp, lam, pp)
    zp = clamp_grades(zp, gdes, dsp, pp)
    z = cubic_resample(sp, zp, s)
    # exact pins on the 2 m samples
    for i, zv in pins.items():
        z[i] = zv
    gm2 = np.interp(0.5 * (s[:-1] + s[1:]), 0.5 * (sp[:-1] + sp[1:]), gmax)
    # hard grade limit on the final 2 m samples (removes the tiny overshoot of the cubic interpolation)
    z = clamp_grades(z, gm2 * 0.998, ds, pins)
    # ---- tunnel ends: the bore starts where the hillside covers it. An uncovered stretch at an end of a forced tunnel (the straight
    # chord leaves the ridge shoulder before the profile reaches the ground) is plain road / bridge, not tunnel.
    for a, b in runs(tunnel):
        i, j = a, b
        while i < j and t_s[i] - z[i] < TUNNEL_COVER_MIN:
            i += 1
        while j > i and t_s[j] - z[j] < TUNNEL_COVER_MIN:
            j -= 1
        if (j - i + 1) * ds >= 100.0:
            tunnel[a:i] = False
            tunnel[j + 1:b + 1] = False
    # ---- geometric flags
    fill = z - t_s
    cut = t_s - z
    fb = FILL_BRIDGE_BY_CLASS.get(road["cls"], FILL_BRIDGE_M)
    for a, b in runs((fill > fb) & ~hair):
        if (b - a + 1) * ds >= 30.0 and not tunnel[a:b + 1].any():
            a2 = max(0, a - int(4 / ds))
            b2 = min(n - 1, b + int(4 / ds))
            bridge[a2:b2 + 1] = True
    bridge &= ~tunnel
    reasons["fill"] = bridge & ~reasons["forced"] & ~reasons["wet"] & ~reasons["closing"]
    geo_tunnel = np.zeros(n, dtype=bool)
    for a, b in runs((cut > CUT_TUNNEL_M) & ~hair):
        if (b - a + 1) * ds > 100.0 and not bridge[a:b + 1].any():
            geo_tunnel[a:b + 1] = True
    tunnel |= geo_tunnel
    # ---- culverts
    culvert = np.zeros(n, dtype=bool)
    from geom import raster_dist
    for st in streams:
        sp_ = st["pts"]
        # point-to-polyline distance for the alignment samples (brute force over segments)
        a = sp_[:-1]
        b = sp_[1:]
        dvec = b - a
        L2 = (dvec ** 2).sum(1)
        for i0 in range(0, n, 400):
            q = xy[i0:i0 + 400]
            tt = np.clip(((q[:, None, :] - a[None]) * dvec[None]).sum(2) / L2[None], 0, 1)
            p = a[None] + dvec[None] * tt[..., None]
            dd = np.sqrt(((p - q[:, None, :]) ** 2).sum(2)).min(1)
            culvert[i0:i0 + 400] |= dd < 4.0
    culvert &= ~bridge & ~tunnel
    # ---- banking (positive = right edge lower, i.e. for right turns)
    kap = al["kappa"]
    from align import gauss_smooth_open
    e = c["bank_max"] * np.minimum(1.0, np.abs(kap) * c["bank_ref"])
    bank_tan = np.sign(kap) * e
    # smooth the banking along the road (and ramp it out inside tunnels/bridges is not needed)
    bt = np.stack([bank_tan, bank_tan], 1)
    bt = gauss_smooth_open(bt, 14.0, ds)
    bank_tan = bt[:, 0]
    grade = np.gradient(z, s)
    return dict(z=z, terrain=t_s, grade=grade, bridge=bridge, tunnel=tunnel, culvert=culvert, bank_tan=bank_tan,
                gmax2=gm2, depth_closing=depth, hairpin=hair, reasons=reasons, forced_b=forced_b, forced_t=forced_t)
