"""Grade-line road tracer for mountain roads.

The road is walked uphill from its lower end at a design grade: at every step the direction is chosen so that the terrain
rises along the path at the (adaptive) design grade -> the road follows the hillside at its natural line; on gentle ground
it simply heads for the goal. When the road reaches the edge of a corridor around a guide line (a valley axis) it makes a
hairpin (circular arc, radius 18-30 m) towards the uphill side, preferably on the flattest bench found just before.
Leg lengths, hairpin radii and corridor edges vary randomly (seeded), so no two roads / legs look alike.

Coordinates: X (north), Y (east); bearings are not used here, only unit vectors (x, y).
"""
import math

import numpy as np

from common import HALF, gauss_blur, gradient_xy

CELL = 6.0


class Surface:
    """smoothed terrain + gradient on the 6 m plan grid with scalar bilinear lookups."""

    def __init__(self, Z, sigma_cells=1.6):
        self.Z = gauss_blur(Z.astype(np.float32), sigma_cells) if sigma_cells > 0 else Z.astype(np.float32)
        self.gx, self.gy = gradient_xy(self.Z, CELL)
        self.n = self.Z.shape[0]

    def _bil(self, A, x, y):
        fi = (x + HALF) / CELL
        fj = (y + HALF) / CELL
        fi = min(max(fi, 0.0), self.n - 1.001)
        fj = min(max(fj, 0.0), self.n - 1.001)
        i0 = int(fi)
        j0 = int(fj)
        ti = fi - i0
        tj = fj - j0
        a = A[j0, i0] * (1 - ti) + A[j0, i0 + 1] * ti
        b = A[j0 + 1, i0] * (1 - ti) + A[j0 + 1, i0 + 1] * ti
        return float(a * (1 - tj) + b * tj)

    def z(self, x, y):
        return self._bil(self.Z, x, y)

    def zv(self, x, y):
        """vectorised bilinear height at arrays of world coordinates"""
        fi = np.clip((np.asarray(x, dtype=np.float64) + HALF) / CELL, 0.0, self.n - 1.001)
        fj = np.clip((np.asarray(y, dtype=np.float64) + HALF) / CELL, 0.0, self.n - 1.001)
        i0 = fi.astype(np.int64)
        j0 = fj.astype(np.int64)
        ti = fi - i0
        tj = fj - j0
        A = self.Z
        return (A[j0, i0] * (1 - ti) + A[j0, i0 + 1] * ti) * (1 - tj) + (A[j0 + 1, i0] * (1 - ti) + A[j0 + 1, i0 + 1] * ti) * tj

    def grad(self, x, y):
        return self._bil(self.gx, x, y), self._bil(self.gy, x, y)


def _unit(v):
    n = math.hypot(v[0], v[1])
    return (v[0] / n, v[1] / n) if n > 1e-12 else (1.0, 0.0)


def _rot(v, a):
    c, s = math.cos(a), math.sin(a)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def _angle_between(a, b):
    """signed angle from a to b (radians, CCW positive)."""
    return math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1])


class Guide:
    def __init__(self, pts, ds=8.0):
        pts = np.asarray(pts, dtype=float)
        seg = np.hypot(*(pts[1:] - pts[:-1]).T)
        s = np.concatenate([[0.0], np.cumsum(seg)])
        n = max(2, int(s[-1] / ds) + 1)
        t = np.linspace(0, s[-1], n)
        self.P = np.stack([np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])], 1)
        self.s = t
        self.L = float(s[-1])
        d = np.gradient(self.P, t, axis=0)
        d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
        self.T = d

    def locate(self, p):
        """(signed lateral offset u (left of the guide direction positive), progress s, tangent)"""
        dx = self.P[:, 0] - p[0]
        dy = self.P[:, 1] - p[1]
        k = int(np.argmin(dx * dx + dy * dy))
        t = self.T[k]
        u = (p[0] - self.P[k, 0]) * (-t[1]) + (p[1] - self.P[k, 1]) * t[0]
        return float(u), float(self.s[k]), (float(t[0]), float(t[1]))


def trace(surf, start, goal, spec, log=None):
    """returns dict(path (n,2), hairpins [(x, y, R)], z_end, ok, info)"""
    rng = np.random.default_rng(spec.get("seed", 1))
    guide = Guide(spec["guide"])
    ds = spec.get("ds", 5.0)
    g_lo = spec.get("g_lo", 0.045)
    g_hi = spec.get("g_hi", 0.105)
    r_leg = spec.get("r_leg", 55.0)
    r_h = spec.get("r_hair", (20.0, 30.0))
    min_leg = spec.get("min_leg", 160.0)
    max_leg = spec.get("max_leg", 950.0)
    kf = spec.get("kf", 0.012)
    w_spec = spec.get("half_width", 220.0)
    z_goal = surf.z(*goal)
    g_arc = spec.get("g_arc", 0.05)
    bound = spec.get("bound", 1940.0)
    min_z = spec.get("min_z", 2.5)
    max_steps = spec.get("max_steps", 3600)
    clear = spec.get("self_clear", 30.0)
    max_hair = spec.get("max_hairpins", 24)
    avoid = spec.get("avoid") or []
    avoid_clear = spec.get("avoid_clear", 55.0)
    av_pts = np.vstack([np.asarray(a, dtype=float)[::2] for a in avoid]) if len(avoid) else np.zeros((0, 2))
    av_cell = 80.0
    av_hash = {}
    for q_ in av_pts:
        av_hash.setdefault((int((q_[0] + HALF) // av_cell), int((q_[1] + HALF) // av_cell)), []).append(q_)

    def near_avoid(q):
        if not len(av_pts):
            return False
        kx, ky = int((q[0] + HALF) // av_cell), int((q[1] + HALF) // av_cell)
        for dx_ in (-1, 0, 1):
            for dy_ in (-1, 0, 1):
                for qq in av_hash.get((kx + dx_, ky + dy_), ()):
                    if (qq[0] - q[0]) ** 2 + (qq[1] - q[1]) ** 2 < avoid_clear * avoid_clear:
                        return True
        return False

    def width_at(sg):
        if np.isscalar(w_spec):
            return float(w_spec)
        ws = np.asarray(w_spec, dtype=float)
        return float(np.interp(sg / guide.L, ws[:, 0], ws[:, 1]))

    hcell = 40.0
    hashed = {}

    def hkey(q):
        return (int((q[0] + HALF) // hcell), int((q[1] + HALF) // hcell))

    p = (float(start[0]), float(start[1]))
    z_r = surf.z(*p)
    u0, s0, t0 = guide.locate(p)
    H = spec.get("heading0")
    H = _unit(H) if H is not None else t0
    path = [p]
    hashed.setdefault(hkey(p), []).append(0)

    def near_old(q, idx_limit):
        kx, ky = hkey(q)
        for dx_ in (-1, 0, 1):
            for dy_ in (-1, 0, 1):
                for j_ in hashed.get((kx + dx_, ky + dy_), ()):
                    if j_ < idx_limit:
                        qq = path[j_]
                        if (qq[0] - q[0]) ** 2 + (qq[1] - q[1]) ** 2 < clear * clear:
                            return True
        return False

    def rebuild_hash():
        hashed.clear()
        for i_, q_ in enumerate(path):
            hashed.setdefault(hkey(q_), []).append(i_)

    side = spec.get("first_side", None)          # +1: uphill on the left of travel; None = pick by continuity
    prev_steep = False
    leg_start = 0
    leg_len = 0.0
    hairpins = []
    U_target = width_at(s0) * rng.uniform(0.75, 1.1)
    traveled = 0.0
    arrived = False
    info = dict(flips=0)
    last_flip_step = -999
    approach_steps = 0
    wob_amp = float(spec.get("wobble", 0.10))
    wob_len = float(rng.uniform(*spec.get("wobble_len", (260.0, 480.0))))
    wob_ph = float(rng.uniform(0.0, 6.283))
    tun = spec.get("tunnel")
    tunnel_spans = []
    step_i = 0
    for step_i in range(max_steps):
        px, py = p
        zt = surf.z(px, py)
        gxv, gyv = surf.grad(px, py)
        sl = math.hypot(gxv, gyv)
        u, sg, tg = guide.locate(p)
        dgoal = math.hypot(goal[0] - px, goal[1] - py)
        rem_h = z_goal - z_r
        # ---- adaptive design grade
        prog = max(sg - s0, 40.0)
        rho = min(max(traveled / prog, 1.3), 7.0) if traveled > 250.0 else 3.0
        rem_len = max(guide.L - sg, dgoal * 0.8, 60.0) * rho * 0.82
        gd = min(max(rem_h / rem_len, g_lo), g_hi) if rem_h > 0 else 0.0
        # ---- arrival: steer smoothly into the goal (turn-rate limited) and snap the last few metres
        if dgoal < 100.0 and rem_h <= max(gd, 0.05) * dgoal * 1.3 + 3.0:
            d_goal = _unit((goal[0] - px, goal[1] - py))
            ang = _angle_between(H, d_goal)
            if dgoal <= ds * 1.1 or approach_steps > 60:
                arrived = True
                break
            approach_steps += 1
            lim = ds / r_leg
            H = _rot(H, max(-lim, min(lim, ang)))
            pn = (px + H[0] * min(ds, dgoal), py + H[1] * min(ds, dgoal))
            path.append(pn)
            hashed.setdefault(hkey(pn), []).append(len(path) - 1)
            traveled += ds
            p = pn
            z_r = min(z_r + 0.05 * ds, z_goal)
            continue
        e = z_r - zt
        gd_eff = min(max(gd + kf * e, 0.0), 0.30)
        steep = sl > max(gd_eff, 1e-4) * 1.05 and rem_h > 0.5
        # ---- desired direction
        k_look = min(int(min(sg + 90.0, guide.L) / 8.0), len(guide.P) - 1)
        lp = guide.P[k_look]
        d_look = _unit((lp[0] - px, lp[1] - py))
        if dgoal < 160.0 and rem_h <= max(gd, 0.05) * dgoal * 1.3 + 3.0:
            d_look = _unit((goal[0] - px, goal[1] - py))
        if not steep:
            d_des = d_look
            z_r = min(max(surf.z(px + H[0] * ds, py + H[1] * ds), z_r - 0.10 * ds), z_r + max(gd, 0.02) * ds)
        else:
            ug = (gxv / sl, gyv / sl)
            if (not prev_steep) or side is None:
                # pick the side by continuity with the current heading (uphill on the left if it is on the left of H)
                side = 1.0 if (H[0] * ug[1] - H[1] * ug[0]) > 0 else -1.0
            phi = math.asin(min(gd_eff / sl, 0.97))
            c = (ug[1], -ug[0]) if side > 0 else (-ug[1], ug[0])
            d_des = (math.cos(phi) * c[0] + math.sin(phi) * ug[0], math.cos(phi) * c[1] + math.sin(phi) * ug[1])
            z_r += gd * ds
        prev_steep = steep
        # ---- gentle S-bends: slowly varying heading wobble (random wavelength / phase per road)
        if wob_amp > 0.0:
            wa = wob_amp * math.sin(2.0 * math.pi * traveled / wob_len + wob_ph)
            d_des = _rot(d_des, wa)
        # ---- tunnel through a ridge shoulder straight ahead (once per road, inside a zone of the guide)
        if tun and not tunnel_spans and steep and leg_len > 50.0 and step_i % 3 == 0:
            f0, f1 = tun.get("zone", (0.0, 1.0))
            if f0 <= sg / guide.L <= f1:
                gt = tun.get("grade", 0.09)
                Lmin, Lmax = tun.get("len", (160.0, 340.0))
                cmin = tun.get("cover", 7.0)
                best_t = None
                for Lc in range(int(Lmin), int(Lmax) + 1, 20):
                    ok_t = True
                    cov_max = -1e9
                    for sk in range(20, Lc + 1, 20):
                        zq = surf.z(px + H[0] * sk, py + H[1] * sk)
                        cv = zq - (z_r + gt * sk)
                        if 40 <= sk <= Lc - 40:
                            if cv < cmin:
                                ok_t = False
                                break
                            cov_max = max(cov_max, cv)
                    if not ok_t or cov_max < tun.get("cover_peak", 14.0):
                        continue
                    zend = surf.z(px + H[0] * Lc, py + H[1] * Lc)
                    if abs(zend - (z_r + gt * Lc)) > tun.get("exit_tol", 7.0):
                        continue
                    q_end = (px + H[0] * Lc, py + H[1] * Lc)
                    if abs(q_end[0]) > bound or abs(q_end[1]) > bound:
                        continue
                    if best_t is None or cov_max > best_t[0]:
                        best_t = (cov_max, Lc)
                if best_t is not None:
                    Lc = best_t[1]
                    ia = len(path) - 1
                    for k_ in range(1, int(Lc / ds) + 1):
                        pt_ = (px + H[0] * ds * k_, py + H[1] * ds * k_)
                        path.append(pt_)
                        hashed.setdefault(hkey(pt_), []).append(len(path) - 1)
                    tunnel_spans.append(("tunnel", ia, len(path) - 1))
                    z_r += gt * Lc
                    traveled += Lc
                    leg_len += Lc
                    p = path[-1]
                    prev_steep = False
                    side = None
                    continue
        # ---- turn-rate limited heading update
        ang = _angle_between(H, d_des)
        lim = ds / r_leg
        H = _rot(H, max(-lim, min(lim, ang)))
        pn = (px + H[0] * ds, py + H[1] * ds)
        path.append(pn)
        hashed.setdefault(hkey(pn), []).append(len(path) - 1)
        traveled += ds
        leg_len += ds
        p = pn
        # ---- hairpin decision (only on steep ground, or when forced)
        out_of_bounds = abs(pn[0]) > bound or abs(pn[1]) > bound or surf.z(*pn) < min_z
        hit_self = near_old(pn, len(path) - 1 - int(150.0 / ds)) or near_avoid(pn)
        un, sgn, tgn = guide.locate(pn)
        du = un - u
        want = steep and leg_len >= min_leg and abs(un) >= U_target and du * un > 0
        forced = out_of_bounds or hit_self
        if steep and (want or leg_len >= max_leg or (forced and leg_len >= 40.0)) and step_i - last_flip_step > 6 and len(hairpins) < max_hair:
            kmin = max(leg_start + int(min(min_leg, 80.0) / ds), len(path) - 1 - int(140.0 / ds))
            best = None
            for k in range(len(path) - 1, max(kmin, 1) - 1, -1):
                qx, qy = path[k]
                uk, sk, _ = guide.locate((qx, qy))
                if abs(uk) < 0.55 * U_target and not forced:
                    continue
                slk = math.hypot(*surf.grad(qx, qy))
                cost = slk + 0.0006 * (len(path) - 1 - k) * ds
                if best is None or cost < best[0]:
                    best = (cost, k)
            k = best[1] if best is not None else len(path) - 1
            del path[k + 1:]
            qx, qy = path[k]
            Hk = _unit((path[k][0] - path[max(k - 3, 0)][0], path[k][1] - path[max(k - 3, 0)][1]))
            R = float(rng.uniform(r_h[0], r_h[1]))
            turn = 1.0 if side > 0 else -1.0                    # towards the uphill side
            ctr = (qx + (-Hk[1]) * turn * R, qy + Hk[0] * turn * R)
            a0 = math.atan2(qy - ctr[1], qx - ctr[0])
            arc_len = math.pi * R
            na = max(6, int(arc_len / 3.0))
            for ia in range(1, na + 1):
                aa = a0 + turn * math.pi * ia / na
                path.append((ctr[0] + R * math.cos(aa), ctr[1] + R * math.sin(aa)))
            rebuild_hash()
            H = _unit((-Hk[0], -Hk[1]))
            hairpins.append((float(qx), float(qy), R))
            z_r += g_arc * arc_len
            side = -side
            p = path[-1]
            leg_start = len(path) - 1
            leg_len = 0.0
            last_flip_step = step_i
            u2, s2, _ = guide.locate(p)
            U_target = width_at(s2) * rng.uniform(0.75, 1.15)
            info["flips"] += 1
        elif forced and not steep:
            # blocked on gentle ground (sea / border / own road): steer away from the obstacle by turning towards the guide
            pass
    if arrived:
        path.append((float(goal[0]), float(goal[1])))
    info.update(z_end=z_r, z_goal=z_goal, arrived=arrived, steps=step_i, length=traveled, tunnels=len(tunnel_spans))
    return dict(path=np.array(path, dtype=float), hairpins=hairpins, ok=arrived, info=info, spans=tunnel_spans)


def valley_guide(surf, p0, z_stop, sigma_m=160.0, max_len=9000.0, sink_dir=None, ds_out=40.0):
    """Follow the drainage (steepest descent on the depression-filled terrain) from `p0` down to elevation `z_stop`.
    Returns the smoothed polyline (n, 2), ordered DOWNHILL. Used as the corridor axis of the switchback designer: the road
    zig-zags across the natural valley, the way real alpine roads do."""
    import erosion as ER
    Z = surf.Z
    # coarse 12 m grid for the flow (the plan grid is 6 m)
    Zc = Z[::2, ::2].copy()
    fl = ER.flow(Zc, sea_level=-1e9)
    recv = fl["recv"]
    n = Zc.shape[0]
    cell = CELL * 2.0
    fi = int(round((p0[0] + HALF) / cell))
    fj = int(round((p0[1] + HALF) / cell))
    c = fj * n + fi
    pts = []
    total = 0.0
    last = None
    for _ in range(4000):
        j, i = divmod(c, n)
        q = (i * cell - HALF, j * cell - HALF)
        pts.append(q)
        if Zc[j, i] <= z_stop:
            break
        r = int(recv[j, i])
        if r < 0:
            break
        c = r
    P = np.array(pts, dtype=float)
    seg = np.hypot(*np.diff(P, axis=0).T)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    m = max(3, int(s[-1] / 12.0))
    t = np.linspace(0, s[-1], m)
    x = np.interp(t, s, P[:, 0])
    y = np.interp(t, s, P[:, 1])
    sg = sigma_m / (t[1] - t[0])
    k = int(min(3 * sg, m - 2))
    ker = np.exp(-0.5 * (np.arange(-k, k + 1) / max(sg, 0.5)) ** 2)
    ker /= ker.sum()
    out = []
    for v in (x, y):
        ext = np.concatenate([2 * v[0] - v[1:k + 1][::-1], v, 2 * v[-1] - v[-k - 1:-1][::-1]])
        out.append(np.convolve(ext, ker, mode="valid"))
    G = np.stack(out, 1)
    seg = np.hypot(*np.diff(G, axis=0).T)
    s2 = np.concatenate([[0.0], np.cumsum(seg)])
    n2 = max(3, int(s2[-1] / ds_out))
    tt = np.linspace(0, s2[-1], n2)
    return np.stack([np.interp(tt, s2, G[:, 0]), np.interp(tt, s2, G[:, 1])], 1)
