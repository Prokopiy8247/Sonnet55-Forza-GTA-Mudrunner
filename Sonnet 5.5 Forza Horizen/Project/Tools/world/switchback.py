"""Mountain road designer (v3): dynamic-programming hairpin placement + constructive hairpin / tangent-leg geometry.

1. `plan_apexes` - along a guide polyline (valley axis / flank line) with a lateral corridor (half width profile) the hairpin
   apexes (outermost points of the hairpin arcs) are chosen by dynamic programming over candidate points on the two corridor
   edges. A leg from hairpin a to hairpin b is feasible when the design grade (rise on the REAL terrain / road length)
   lies in a window; the cost prefers legs of an irregular preferred length (smooth random field along the guide, so legs
   differ), smooth terrain under the leg, moderate side slopes at the apexes, few hairpins, clearance from other roads.
2. `construct` - the alignment is built exactly: every hairpin is a circular arc (R 20..30 m, random), legs are internal
   tangents between consecutive arcs, bent sideways with a smooth lateral bump profile that follows the hillside
   (the bump amplitudes are optimised so the terrain under the leg matches the design grade line) -> legs are gentle S-curves,
   not straight rungs of a ladder; tangent / curvature continuity at the arcs is kept.

Coordinates are UE metres (X north, Y east). Roads are designed from the LOW end upwards (`reverse` handled by the caller).
"""
import math

import numpy as np

from common import HALF, ss
from tracer import Guide, Surface


def _unit(v):
    n = math.hypot(v[0], v[1])
    return (v[0] / n, v[1] / n) if n > 1e-12 else (1.0, 0.0)


def _smooth_noise(n, rng, wl_samples):
    """smooth random field in [-1, 1] over n samples"""
    k = max(4, int(n / wl_samples) + 3)
    v = rng.standard_normal(k)
    x = np.linspace(0, k - 1.001, n)
    i = x.astype(int)
    t = x - i
    t = t * t * (3 - 2 * t)
    out = v[i] * (1 - t) + v[i + 1] * t
    return out / max(np.abs(out).max(), 1e-6)


def _tip_height(surf, x, y, r=26.0):
    zz = [surf.z(x, y)]
    for a in range(6):
        zz.append(surf.z(x + r * math.cos(a * 1.0472), y + r * math.sin(a * 1.0472)))
    return float(np.mean(zz))


def plan_apexes(surf, guide_pts, start, goal, spec, rng, avoid=None):
    """returns (apex list [(x, y, side, tx, ty)] in travel order, info) or (None, info).
    Candidates sit on 3 lateral levels per side of the guide (a fraction of the corridor half width)."""
    G = Guide(guide_pts, ds=5.0)
    ds_c = spec.get("cand_ds", 12.0)
    ns = int(G.L / ds_c) + 1
    sc = np.linspace(0.0, G.L, ns)
    kk = np.minimum((sc / 5.0).astype(int), len(G.P) - 1)
    T = G.T[kk]
    N = np.stack([-T[:, 1], T[:, 0]], 1)
    hw = spec.get("half_width", 200.0)
    if np.isscalar(hw):
        wprof = np.full(ns, float(hw))
    else:
        wk = np.asarray(hw, dtype=float)
        wprof = np.interp(sc / G.L, wk[:, 0], wk[:, 1])
    levels = spec.get("levels", (0.55, 0.78, 1.0))
    nl = len(levels)
    jit = np.stack([1.0 + 0.16 * _smooth_noise(ns, rng, 14) + rng.uniform(-0.05, 0.05, ns),
                    1.0 + 0.16 * _smooth_noise(ns, rng, 14) + rng.uniform(-0.05, 0.05, ns)])
    R_nom = 0.5 * sum(spec.get("r_hair", (20.0, 30.0)))
    ctr = np.zeros((2, nl, ns, 2))
    lat = np.zeros((2, nl, ns))
    cand = np.zeros((2, nl, ns, 2))
    zc = np.zeros((2, nl, ns))
    slc = np.zeros((2, nl, ns))
    for si, side in enumerate((1.0, -1.0)):
        for li, lf in enumerate(levels):
            lat[si, li] = side * wprof * jit[si] * lf
            cand[si, li] = G.P[kk] + side * (wprof * jit[si] * lf)[:, None] * N
            ctr[si, li] = cand[si, li] + R_nom * T
            for i in range(ns):
                zc[si, li, i] = _tip_height(surf, ctr[si, li, i, 0], ctr[si, li, i, 1])
                slc[si, li, i] = math.hypot(*surf.grad(ctr[si, li, i, 0], ctr[si, li, i, 1]))
    z_start = surf.z(*start)
    z_goal = surf.z(*goal)
    g_lo = spec.get("g_lo", 0.045)
    g_hi = spec.get("g_hi", 0.085)
    g_t = spec.get("grade", 0.5 * (g_lo + g_hi))
    kappa = spec.get("path_factor", 1.06)
    Lmin = spec.get("min_leg", 200.0)
    Lmax = spec.get("max_leg", 1400.0)
    c_h = spec.get("hairpin_cost", 2.5)
    Lpref = spec.get("pref_leg", (330.0, 650.0))
    pref = Lpref[0] + (Lpref[1] - Lpref[0]) * (0.5 + 0.5 * _smooth_noise(ns, rng, 10))
    w_len = spec.get("w_len", 1.2)
    w_rough = spec.get("w_rough", 0.9)
    w_tip = spec.get("w_tip", 1.2)
    w_grade = spec.get("w_grade", 3.0)
    w_sep = spec.get("w_sep", 30.0)
    sep_min = spec.get("sep_min", 200.0)
    gmin_s, gmax_s = (g_lo * 0.8, g_hi * 1.18)
    arc_len = math.pi * R_nom
    bad = np.zeros((2, nl, ns), dtype=bool)
    if avoid is not None and len(avoid):
        A = np.vstack([np.asarray(a, dtype=float)[::2] for a in avoid])
        far = (np.hypot(A[:, 0] - start[0], A[:, 1] - start[1]) > 260.0) & (np.hypot(A[:, 0] - goal[0], A[:, 1] - goal[1]) > 200.0)
        A = A[far]
        ac = spec.get("avoid_clear", 60.0)
        for si in range(2):
            for li in range(nl):
                for i in range(ns):
                    if len(A) and np.min(((A - cand[si, li, i]) ** 2).sum(1)) < ac * ac:
                        bad[si, li, i] = True

    tt5 = np.linspace(0.0, 1.0, 6)

    def transect_rough(p, q):
        zs = np.array([surf.z(p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t) for t in tt5])
        chord = zs[0] + (zs[-1] - zs[0]) * tt5
        return float(np.sqrt(np.mean((zs - chord) ** 2)))

    def grade_terms(D, dz, first=False):
        Lt = np.sqrt(np.maximum(D * D - (2.0 * R_nom) ** 2, 1.0))
        Lroad = Lt + (0.0 if first else arc_len)
        gr = dz / (kappa * Lroad)
        return Lt, gr

    INF = 1e18
    best = np.full((2, nl, ns), INF)
    prev = np.full((2, nl, ns, 3), -1, dtype=int)
    # first legs from the road start
    for si in range(2):
        for li in range(nl):
            D = np.hypot(ctr[si, li, :, 0] - start[0], ctr[si, li, :, 1] - start[1])
            Lt, gr = grade_terms(D, zc[si, li] - z_start, first=True)
            ok = (D >= Lmin) & (D <= Lmax) & (gr >= gmin_s) & (gr <= gmax_s) & ~bad[si, li]
            for i in np.nonzero(ok)[0]:
                c = w_grade * ((gr[i] - g_t) / 0.02) ** 2 + (6.0 if (gr[i] < g_lo or gr[i] > g_hi) else 0.0)
                c += w_len * ((Lt[i] - pref[i]) / 250.0) ** 2 + w_tip * ss(slc[si, li, i], 0.20, 0.55) + c_h
                c += w_rough * transect_rough(start, ctr[si, li, i]) / 8.0
                best[si, li, i] = c
    min_adv = spec.get("min_advance", 45.0)
    for j in range(ns):
        for sj in range(2):
            si = 1 - sj
            for lj in range(nl):
                if bad[sj, lj, j]:
                    continue
                pj = ctr[sj, lj, j]
                zj = zc[sj, lj, j]
                jmax = int(np.searchsorted(sc, sc[j] - min_adv))
                if jmax <= 0:
                    continue
                dxp = ctr[si, :, :jmax, 0] - pj[0]
                dyp = ctr[si, :, :jmax, 1] - pj[1]
                D = np.hypot(dxp, dyp)
                Lt, gr = grade_terms(D, zj - zc[si, :, :jmax])
                ok = (D >= Lmin) & (D <= Lmax) & (gr >= gmin_s) & (gr <= gmax_s) & (best[si, :, :jmax] < INF) & ~bad[si, :, :jmax]
                li_s, i_s = np.nonzero(ok)
                if len(li_s) == 0:
                    continue
                dlat = np.abs(lat[si, :, :jmax] - lat[sj, lj, j])
                for li, i in zip(li_s, i_s):
                    c = w_grade * ((gr[li, i] - g_t) / 0.02) ** 2 + (6.0 if (gr[li, i] < g_lo or gr[li, i] > g_hi) else 0.0)
                    c += w_len * ((Lt[li, i] - pref[(i + j) // 2]) / 250.0) ** 2 + c_h
                    c += w_sep * max(0.0, 1.0 - dlat[li, i] / sep_min) ** 1.5
                    v0 = best[si, li, i] + c
                    if v0 >= best[sj, lj, j]:
                        continue
                    v = v0 + w_rough * transect_rough(ctr[si, li, i], pj) / 8.0 + w_tip * ss(slc[sj, lj, j], 0.20, 0.55)
                    if v < best[sj, lj, j]:
                        best[sj, lj, j] = v
                        prev[sj, lj, j] = (si, li, i)
    fin = (INF, None)
    for relax in (1.0, 1.35, 1.8):
        for si in range(2):
            for li in range(nl):
                Dg = np.hypot(goal[0] - ctr[si, li, :, 0], goal[1] - ctr[si, li, :, 1])
                gr = (z_goal - zc[si, li]) / (kappa * (Dg + 0.5 * arc_len))
                ok = (best[si, li] < INF) & ~bad[si, li] & (Dg >= spec.get("min_final", 50.0)) & (Dg <= Lmax * relax) &                      (gr >= -spec.get("final_down", 0.04) * relax) & (gr <= gmax_s * 1.15 * relax)
                for i in np.nonzero(ok)[0]:
                    c = best[si, li, i] + w_grade * ((gr[i] - g_t) / 0.025) ** 2 * 0.3 + w_len * ((Dg[i] - 450.0) / 300.0) ** 2 * 0.3 + 8.0 * (relax - 1.0)
                    if c < fin[0]:
                        fin = (c, (si, li, i))
        if fin[1] is not None:
            break
    if fin[1] is None:
        reach = [sc[i] for si in range(2) for li in range(nl) for i in range(ns) if best[si, li, i] < INF]
        return None, dict(reason="no feasible chain", max_s=(max(reach) if reach else 0.0), guide_len=float(G.L), n_reach=len(reach))
    out = []
    si, li, i = fin[1]
    while si >= 0 and i >= 0:
        out.append((float(cand[si, li, i, 0]), float(cand[si, li, i, 1]), 1.0 if si == 0 else -1.0, float(T[i, 0]), float(T[i, 1])))
        pv = prev[si, li, i]
        si, li, i = int(pv[0]), int(pv[1]), int(pv[2])
    out.reverse()
    return out, dict(cost=fin[0], n=len(out))


# ---------------------------------------------------------------------------------------------------------------- geometry
def _tangent_leg(Ca, Ra, ta, Cb, Rb):
    """internal tangent between circle a (turn direction ta = +1 left / -1 right) and circle b (opposite turn).
    returns (theta, E, F): direction angle, exit point on a, entry point on b."""
    dx, dy = Cb[0] - Ca[0], Cb[1] - Ca[1]
    d = math.hypot(dx, dy)
    beta = math.atan2(dy, dx)
    a = math.asin(min(0.999, (Ra + Rb) / d))
    theta = beta + ta * a
    left = (-math.sin(theta), math.cos(theta))
    E = (Ca[0] - ta * Ra * left[0], Ca[1] - ta * Ra * left[1])
    F = (Cb[0] + ta * Rb * left[0], Cb[1] + ta * Rb * left[1])
    return theta, E, F


def _wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def construct(surf, start, goal, apexes, spec, rng):
    """build the dense alignment from the apex list. returns dict(path, hairpins, info)."""
    r_h = spec.get("r_hair", (20.0, 30.0))
    ds = 3.0
    hairpins = []
    n = len(apexes)
    S = (float(start[0]), float(start[1]))
    G = (float(goal[0]), float(goal[1]))
    if n == 0:
        return dict(path=np.array([S, G], dtype=float), hairpins=[], info={})
    Rs = [float(rng.uniform(*r_h)) for _ in range(n)]
    taus = [(-1.0 if a_[2] > 0 else 1.0) for a_ in apexes]          # left-edge apex -> right turn (tau = -1)
    R_wide = float(spec.get("r_wide", 46.0))

    def build_legs(Rs):
        C = [(a_[0] + Rs[i] * a_[3], a_[1] + Rs[i] * a_[4]) for i, a_ in enumerate(apexes)]
        legs = []
        D = (C[0][0] - S[0], C[0][1] - S[1])
        dl = math.hypot(*D)
        th0 = math.atan2(D[1], D[0]) - taus[0] * math.asin(min(0.999, Rs[0] / dl))
        u0 = (math.cos(th0), math.sin(th0))
        left0 = (-u0[1], u0[0])
        F0 = (C[0][0] - taus[0] * Rs[0] * left0[0], C[0][1] - taus[0] * Rs[0] * left0[1])
        legs.append((th0, S, F0))
        for i in range(n - 1):
            legs.append(_tangent_leg(C[i], Rs[i], taus[i], C[i + 1], Rs[i + 1]))
        Dg = (G[0] - C[-1][0], G[1] - C[-1][1])
        dg = math.hypot(*Dg)
        thg = math.atan2(Dg[1], Dg[0]) + taus[-1] * math.asin(min(0.999, Rs[-1] / dg))
        ug = (math.cos(thg), math.sin(thg))
        leftg = (-ug[1], ug[0])
        Eg = (C[-1][0] - taus[-1] * Rs[-1] * leftg[0], C[-1][1] - taus[-1] * Rs[-1] * leftg[1])
        legs.append((thg, Eg, G))
        return C, legs

    def turns_of(legs):
        out = []
        for k in range(n):
            tu = _wrap(legs[k + 1][0] - legs[k][0])
            if taus[k] > 0 and tu < 0:
                tu += 2 * math.pi
            if taus[k] < 0 and tu > 0:
                tu -= 2 * math.pi
            out.append(abs(tu))
        return out

    C, legs = build_legs(Rs)
    for _it in range(3):
        tr = turns_of(legs)
        changed = False
        for k in range(n):
            if tr[k] < math.radians(118.0) and Rs[k] < R_wide:
                Rs[k] = R_wide + float(rng.uniform(0.0, 14.0))          # a turn that is not a real hairpin gets a normal curve radius
                changed = True
        if not changed:
            break
        C, legs = build_legs(Rs)

    def leg_curve_k(E, F, th, offs, nsamp=None):
        """polyline E -> F with lateral offsets `offs` (metres, at equally spaced knots incl. both ends = 0) interpolated with a
        smoothstep hat basis and a sin^2 end window (zero offset and zero slope at the tangent points)."""
        L = math.hypot(F[0] - E[0], F[1] - E[1])
        m = nsamp or max(2, int(L / ds))
        t = np.linspace(0.0, 1.0, m + 1)
        nk = len(offs)
        u = t * (nk - 1)
        i0 = np.minimum(u.astype(int), nk - 2)
        f = u - i0
        mk = np.zeros(nk)
        mk[1:-1] = 0.5 * (offs[2:] - offs[:-2])                     # Catmull-Rom slopes (per knot interval), zero at both ends
        h00 = 2 * f ** 3 - 3 * f ** 2 + 1
        h10 = f ** 3 - 2 * f ** 2 + f
        h01 = -2 * f ** 3 + 3 * f ** 2
        h11 = f ** 3 - f ** 2
        off = h00 * offs[i0] + h10 * mk[i0] + h01 * offs[i0 + 1] + h11 * mk[i0 + 1]
        nx, ny = -math.sin(th), math.cos(th)
        X = E[0] + (F[0] - E[0]) * t + nx * off
        Y = E[1] + (F[1] - E[1]) * t + ny * off
        return np.stack([X, Y], 1)

    nk_leg = 11
    max_off = spec.get("max_bend", 140.0)
    max_d2 = spec.get("max_d2", 16.0)

    def bend_leg(E, F, th, z_lo, z_hi):
        L = math.hypot(F[0] - E[0], F[1] - E[1])
        if L < 110.0:
            return leg_curve_k(E, F, th, np.zeros(nk_leg))
        nk = max(6, min(nk_leg, int(L / 45.0)))
        offs = np.zeros(nk)
        # a gentle random meander as the starting point (roads in a valley do not run ruler-straight)
        ph = float(rng.uniform(0, 6.283))
        am = float(rng.uniform(10.0, 30.0))
        offs = am * np.sin(np.linspace(0, 1, nk) * math.pi * float(rng.uniform(1.6, 3.2)) + ph) * np.sin(np.linspace(0, 1, nk) * math.pi) ** 0.8
        step_m = L / (nk - 1)
        m = max(8, int(L / 12.0))
        tq = np.linspace(0, 1, m + 1)
        line = z_lo + (z_hi - z_lo) * tq
        wgt = np.sin(math.pi * tq) ** 0.35

        def cost(o):
            cur = leg_curve_k(E, F, th, o, nsamp=m)
            zs = surf.zv(cur[:, 0], cur[:, 1])
            dev = zs - line
            # asymmetric: road above the ground (fill / bridge) is worse than below (cut)
            dv = np.where(dev < 0, -dev, dev * 1.6)
            c = float(np.mean(dv * wgt))
            d2 = o[:-2] - 2 * o[1:-1] + o[2:] if len(o) > 2 else np.zeros(1)
            c += 0.012 * float(np.mean(np.maximum(np.abs(d2) - max_d2, 0.0) ** 2)) + 0.0006 * float(np.mean(o * o)) ** 0.5
            return c
        cur_c = cost(offs)
        kk_ = np.arange(nk)
        lim_k = max_off * (np.minimum(kk_, nk - 1 - kk_) / (0.5 * (nk - 1))) ** 1.6
        for sweep, stp in enumerate((24.0, 12.0, 6.0, 3.0)):
            improved = True
            it = 0
            while improved and it < 4:
                improved = False
                it += 1
                for k in range(1, nk - 1):
                    for dlt in (stp, -stp):
                        o2 = offs.copy()
                        o2[k] = float(np.clip(o2[k] + dlt, -lim_k[k], lim_k[k]))
                        if o2[k] == offs[k]:
                            continue
                        c2 = cost(o2)
                        if c2 < cur_c - 1e-6:
                            offs, cur_c = o2, c2
                            improved = True
        # curvature check: shrink the bends until the leg is gentler than R = 55 m everywhere
        for _ in range(10):
            cur = leg_curve_k(E, F, th, offs, nsamp=max(8, int(L / 8.0)))
            a_, b_, c_ = cur[:-2], cur[1:-1], cur[2:]
            ab = b_ - a_
            bc = c_ - b_
            cr = np.abs(ab[:, 0] * bc[:, 1] - ab[:, 1] * bc[:, 0])
            den = np.hypot(*ab.T) * np.hypot(*bc.T) * np.hypot(*(c_ - a_).T)
            kap = 2.0 * cr / np.maximum(den, 1e-9)
            if kap.max() < 1.0 / 55.0:
                break
            offs = offs * 0.8
        return leg_curve_k(E, F, th, offs)

    out = []
    for k in range(n + 1):
        th, E, F = legs[k]
        zE = surf.z(*E)
        zF = surf.z(*F)
        out.append(bend_leg(E, F, th, zE, zF))
        if k < n:
            th_in = th
            th_out = legs[k + 1][0]
            tau = taus[k]
            turn = _wrap(th_out - th_in)
            if tau > 0 and turn < 0:
                turn += 2 * math.pi
            if tau < 0 and turn > 0:
                turn -= 2 * math.pi
            R = Rs[k]
            a0 = math.atan2(F[1] - C[k][1], F[0] - C[k][0])
            na = max(8, int(abs(turn) * R / 2.5))
            arc = []
            for ia in range(1, na):
                aa = a0 + turn * ia / na
                arc.append((C[k][0] + R * math.cos(aa), C[k][1] + R * math.sin(aa)))
            out.append(np.array(arc))
            mid = a0 + turn * 0.5
            hairpins.append((float(C[k][0] + R * math.cos(mid)), float(C[k][1] + R * math.sin(mid)), R))
    path = np.vstack(out)
    return dict(path=path, hairpins=hairpins, info=dict(radii=Rs))


def find_tunnel(surf, path, spec, rng=None):
    """look for a straight chord through a ridge shoulder along `path` (low -> high order): the road leaves the contour-following
    line, bores straight through the nose (cover >= `cover_min` m over the whole inner part, a peak of >= `cover_peak` m) and
    re-joins the same line. Returns (path2, (i_start, i_end)) or (path, None). The chord must be shorter than the road it replaces
    by a good margin, free of hairpins and nearly tangent to the path at both portals."""
    P = np.asarray(path, dtype=float)
    n = len(P)
    seg = np.hypot(*np.diff(P, axis=0).T)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    Lmin, Lmax = spec.get("len", (150.0, 380.0))
    cover_min = spec.get("cover", 6.0)
    cover_peak = spec.get("cover_peak", 16.0)
    gmax = spec.get("grade", 0.09)
    save_min = spec.get("save_min", 1.25)            # replaced road length / chord length
    ang_max = math.radians(spec.get("angle", 11.0))
    zone = spec.get("zone", (0.1, 0.9))
    # unit tangents of the path
    T = np.zeros_like(P)
    T[1:-1] = P[2:] - P[:-2]
    T[0] = P[1] - P[0]
    T[-1] = P[-1] - P[-2]
    T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)
    # curvature of the path (hairpins excluded)
    dth = np.zeros(n)
    dth[1:] = np.abs(np.unwrap(np.arctan2(T[:, 1], T[:, 0])))[1:] - 0
    heading = np.unwrap(np.arctan2(T[:, 1], T[:, 0]))
    best = None
    step_i = 2
    for i in range(int(zone[0] * n), int(zone[1] * n), step_i):
        for j in range(i + 8, min(n, i + 200), step_i):
            Ls = s[j] - s[i]
            if Ls < Lmin * save_min:
                continue
            if Ls > Lmax * 2.6:
                break
            A, B = P[i], P[j]
            D = math.hypot(B[0] - A[0], B[1] - A[1])
            if D < Lmin or D > Lmax or Ls / D < save_min:
                continue
            if np.abs(heading[i:j + 1] - heading[i]).max() > math.radians(260.0):
                continue
            if abs(heading[j] - heading[i]) > math.radians(150.0) and Ls / D < 1.8:
                continue
            ch = ((B[0] - A[0]) / D, (B[1] - A[1]) / D)
            a1 = abs(math.atan2(T[i, 0] * ch[1] - T[i, 1] * ch[0], T[i, 0] * ch[0] + T[i, 1] * ch[1]))
            a2 = abs(math.atan2(T[j, 0] * ch[1] - T[j, 1] * ch[0], T[j, 0] * ch[0] + T[j, 1] * ch[1]))
            if a1 > ang_max or a2 > ang_max:
                continue
            zA, zB = surf.z(*A), surf.z(*B)
            if abs(zB - zA) / D > gmax:
                continue
            ok = True
            cmax = -1e9
            for t in np.linspace(0.12, 0.88, 9):
                q = (A[0] + (B[0] - A[0]) * t, A[1] + (B[1] - A[1]) * t)
                cv = surf.z(*q) - (zA + (zB - zA) * t)
                if cv < cover_min:
                    ok = False
                    break
                cmax = max(cmax, cv)
            if not ok or cmax < cover_peak:
                continue
            score = cmax + 0.04 * (Ls - D)
            if best is None or score > best[0]:
                best = (score, i, j)
    if best is None:
        return P, None, None
    _, i, j = best[0], best[1], best[2]
    best_score = best[0]
    A, B = P[i], P[j]
    m = max(2, int(math.hypot(B[0] - A[0], B[1] - A[1]) / 3.0))
    tt = np.linspace(0, 1, m + 1)
    chord = np.stack([A[0] + (B[0] - A[0]) * tt, A[1] + (B[1] - A[1]) * tt], 1)
    P2 = np.vstack([P[:i], chord, P[j + 1:]])
    i2, j2 = i, i + len(chord) - 1
    # uniform 3 m resampling, then blend the two portal kinks with a heavy Gaussian (sigma 14 m) inside +-45 m windows
    sg = np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(P2, axis=0).T))])
    n2 = int(sg[-1] / 3.0) + 1
    tq = np.linspace(0, sg[-1], n2)
    Q = np.stack([np.interp(tq, sg, P2[:, 0]), np.interp(tq, sg, P2[:, 1])], 1)
    sA, sB = sg[i2], sg[j2]
    ia, ib = int(round(sA / (tq[1] - tq[0]))), int(round(sB / (tq[1] - tq[0])))
    sig = 22.0 / (tq[1] - tq[0])
    r = int(3.5 * sig)
    ker = np.exp(-0.5 * (np.arange(-r, r + 1) / sig) ** 2)
    ker /= ker.sum()
    Qs = np.empty_like(Q)
    for c in range(2):
        ext = np.concatenate([2 * Q[0, c] - Q[1:r + 1, c][::-1], Q[:, c], 2 * Q[-1, c] - Q[-r - 1:-1, c][::-1]])
        Qs[:, c] = np.convolve(ext, ker, mode="valid")
    w = np.zeros(len(Q))
    for k0 in (ia, ib):
        w = np.maximum(w, np.exp(-(((np.arange(len(Q)) - k0) * (tq[1] - tq[0]) / 70.0) ** 2)))
    P3 = Q + (Qs - Q) * w[:, None]
    P3[0] = Q[0]
    P3[-1] = Q[-1]
    return P3, (ia, ib), (tuple(A), tuple(B), float(best_score))
