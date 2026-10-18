"""Valley switchback generator (v2): hairpin apex waypoints for a road climbing along a guide (a valley axis) on REAL terrain.

Legs run across the valley, alternately to its two sides; every hairpin apex sits where the terrain at the corridor edge
is high enough for the leg to arrive at the design grade (so the along-valley spacing follows the real slopes), is moved to
the flattest nearby bench, and gets its own random lateral offset, grade and radius. The planner then routes each leg over
the terrain between consecutive apexes (legs bend with the hillside, they are not straight ladders).

`apexes(surf, guide_pts, start, goal, spec, rng)` -> list of (x, y)  (start ... apexes ... goal) and info.
"""
import math

import numpy as np

from tracer import Guide, Surface


def _eff_len(L, a, b, r_h):
    """effective road length of a leg whose end tip is rounded by an arc of radius r_h (wedge half angle from along / across parts)"""
    if a < 1e-6 or b < 1e-6:
        return L
    alpha = 2.0 * math.atan2(a, b)
    T = r_h / math.tan(alpha / 2.0)
    if T > 0.30 * L:
        return None
    return L - 2.0 * T + r_h * (math.pi - alpha)


def apexes(surf, guide_pts, start, goal, spec, rng):
    G = Guide(guide_pts, ds=6.0)
    grade = spec.get("grade", 0.08)
    jit = spec.get("grade_jitter", 0.14)
    w_spec = spec.get("half_width", 180.0)
    w_var = spec.get("width_var", (0.72, 1.2))
    r_h = spec.get("r_hair", 24.0)
    min_leg = spec.get("min_leg", 150.0)
    max_adv = spec.get("max_advance", 900.0)
    first_side = spec.get("first_side", 1.0)
    max_apex = spec.get("max_apex", 30)
    final_grade = spec.get("final_grade", 0.085)

    def width_at(sg):
        if np.isscalar(w_spec):
            return float(w_spec)
        ws = np.asarray(w_spec, dtype=float)
        return float(np.interp(sg / G.L, ws[:, 0], ws[:, 1]))

    cur = (float(start[0]), float(start[1]))
    z_cur = surf.z(*cur)
    u0, s_cur, _ = G.locate(cur)
    zgoal = surf.z(*goal)
    out = [cur]
    side = first_side
    kinfo = []
    for it in range(max_apex):
        dE = math.hypot(goal[0] - cur[0], goal[1] - cur[1])
        # can the goal be reached directly at a reasonable grade?
        if (zgoal - z_cur) <= final_grade * dE and dE > spec.get("min_final", 90.0):
            break
        g_leg = grade * (1.0 + rng.uniform(-jit, jit))
        wfac = rng.uniform(*w_var)
        found = None
        s = s_cur + 12.0
        while s <= min(G.L, s_cur + max_adv):
            k = min(int(s / 6.0), len(G.P) - 1)
            t = G.T[k]
            nrm = (-t[1], t[0])
            w = width_at(s) * wfac
            P = (G.P[k, 0] + side * w * nrm[0], G.P[k, 1] + side * w * nrm[1])
            vx, vy = P[0] - cur[0], P[1] - cur[1]
            L = math.hypot(vx, vy)
            if L >= min_leg:
                a = abs(vx * t[0] + vy * t[1])
                b = abs(vx * nrm[0] + vy * nrm[1])
                le = _eff_len(L, a, b, r_h)
                if le is not None:
                    zP = surf.z(*P)
                    if zP - z_cur >= g_leg * le:
                        found = (s, P, zP)
                        break
            s += 6.0
        if found is None:
            break
        s_f, P, zP = found
        # slide the apex along the corridor edge to the flattest nearby bench (the climb condition stays approximately true)
        best = None
        for ds_ in np.arange(-36.0, 37.0, 6.0):
            ss_ = s_f + ds_
            if ss_ <= s_cur or ss_ > G.L:
                continue
            k = min(int(ss_ / 6.0), len(G.P) - 1)
            t = G.T[k]
            nrm = (-t[1], t[0])
            w = width_at(ss_) * wfac
            Q = (G.P[k, 0] + side * w * nrm[0], G.P[k, 1] + side * w * nrm[1])
            gq = surf.grad(*Q)
            sl = math.hypot(*gq)
            zq = surf.z(*Q)
            vx, vy = Q[0] - cur[0], Q[1] - cur[1]
            Lq = math.hypot(vx, vy)
            a = abs(vx * t[0] + vy * t[1])
            b = abs(vx * nrm[0] + vy * nrm[1])
            leq = _eff_len(Lq, a, b, r_h)
            if leq is None or Lq < min_leg:
                continue
            ratio = (zq - z_cur) / max(leq, 1.0)
            if ratio < g_leg * 0.8 or ratio > g_leg * 1.35:
                continue
            cost = sl + 0.0004 * abs(ds_)
            if best is None or cost < best[0]:
                best = (cost, Q, zq, ss_)
        if best is not None:
            _, P, zP, s_f = best
        out.append((float(P[0]), float(P[1])))
        kinfo.append(dict(s=s_f, side=side, w=width_at(s_f) * wfac, z=zP, grade=g_leg))
        cur = P
        z_cur = zP
        s_cur = s_f
        side = -side
    out.append((float(goal[0]), float(goal[1])))
    return out, kinfo
