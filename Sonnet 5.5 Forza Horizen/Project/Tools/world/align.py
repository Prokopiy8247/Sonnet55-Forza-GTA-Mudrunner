"""Horizontal alignment fitting: planner polyline -> RDP vertices (PIs) -> tangent-arc fillets honouring the
class minimum radius -> uniform <= 2 m samples -> light clothoid-like smoothing.

Heading convention: bearing = atan2(dY, dX) (0 = +X = north, +90 deg = +Y = east); curvature > 0 = turning right
(bearing increasing, clockwise seen from above).
"""
import math

import numpy as np

import roads_def as RD
from geom import cumlen, rdp, nearest_on_polyline

DS = 2.0
HAIRPIN_ANGLE = math.radians(112.0)


def _wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def rdp_keep(pts, tol, keep):
    keep = sorted(set(int(k) for k in keep) | {0, len(pts) - 1})
    out = [keep[0]]
    for a, b in zip(keep[:-1], keep[1:]):
        if b - a < 2:
            out.append(b)
            continue
        idx = rdp(pts[a:b + 1], tol)
        for k in idx[1:]:
            out.append(a + int(k))
    return np.array(sorted(set(out)), dtype=int)


def fit_pi(V, locked, c, leg_trim=None):
    """V (m,2) vertices -> (V, T, R, theta, hair) after removing vertices that cannot host the minimum radius."""
    V = np.array(V, dtype=float)
    locked = set(locked)             # indices into the ORIGINAL vertex array; tracked through removals
    ids = list(range(len(V)))
    leg_trim = leg_trim or {}
    ignored = set()
    for _ in range(600):
        m = len(V)
        d = V[1:] - V[:-1]
        L = np.sqrt((d ** 2).sum(1))
        ang = np.arctan2(d[:, 1], d[:, 0])
        theta = np.zeros(m)
        for i in range(1, m - 1):
            theta[i] = _wrap(ang[i] - ang[i - 1])
        hair = np.abs(theta) >= HAIRPIN_ANGLE
        rmin = np.where(hair, c["r_hair"] * 1.05, c["r_min"] * 1.05)
        Tmin = rmin * np.tan(np.abs(theta) / 2.0)
        Tmin[np.abs(theta) < math.radians(0.3)] = 0.0
        Tmin[0] = Tmin[-1] = 0.0
        Leff = L.copy()
        for k in range(m - 1):
            tr = leg_trim.get((ids[k], ids[k + 1]), 0.0)
            Leff[k] -= tr
        need = Tmin[:-1] + Tmin[1:]
        over = need - Leff + 0.5
        for k in range(m - 1):
            if (ids[k], ids[k + 1]) in ignored:
                over[k] = -1.0
        if (over <= 0).all():
            break
        k = int(np.argmax(over))
        cand = [i for i in (k, k + 1) if 0 < i < m - 1 and ids[i] not in locked]
        if not cand:
            ignored.add((ids[k], ids[k + 1]))
            continue
        i = min(cand, key=lambda q: abs(theta[q]))
        V = np.delete(V, i, axis=0)
        del ids[i]
    m = len(V)
    d = V[1:] - V[:-1]
    L = np.sqrt((d ** 2).sum(1))
    ang = np.arctan2(d[:, 1], d[:, 0])
    theta = np.zeros(m)
    for i in range(1, m - 1):
        theta[i] = _wrap(ang[i] - ang[i - 1])
    hair = np.abs(theta) >= HAIRPIN_ANGLE
    rmin = np.where(hair, c["r_hair"] * 1.05, c["r_min"] * 1.05)
    tn = np.tan(np.abs(theta) / 2.0)
    Tmin = rmin * tn
    Tmin[np.abs(theta) < math.radians(0.3)] = 0.0
    Tmin[0] = Tmin[-1] = 0.0
    Leff = L.copy()
    for k in range(m - 1):
        Leff[k] -= leg_trim.get((ids[k], ids[k + 1]), 0.0)
    slack = np.maximum(Leff - Tmin[:-1] - Tmin[1:], 0.0)
    T = np.zeros(m)
    R = np.zeros(m)
    for i in range(1, m - 1):
        if Tmin[i] == 0.0:
            continue
        Tmax = min(Tmin[i] + 0.5 * slack[i - 1], Tmin[i] + 0.5 * slack[i])
        Tpref = (c["r_hair"] * 1.17 if hair[i] else c["r_pref"]) * tn[i]
        T[i] = min(Tmax, Tpref)
        R[i] = T[i] / tn[i]
    return V, T, R, theta, hair, ids


def build_path(V, T, R, theta):
    """sample the line/arc alignment. returns pts (n,2), kappa (n,) signed (+ = right)"""
    m = len(V)
    pts = []
    kap = []
    cur = V[0].copy()
    d = V[1:] - V[:-1]
    L = np.sqrt((d ** 2).sum(1))
    u = d / np.maximum(L[:, None], 1e-9)

    def add_line(a, b):
        ln = np.linalg.norm(b - a)
        n = max(1, int(math.ceil(ln / DS)))
        for t in np.linspace(0, 1, n + 1)[:-1]:
            pts.append(a + (b - a) * t)
            kap.append(0.0)

    for i in range(1, m - 1):
        if T[i] <= 0:
            continue
        P1 = V[i] - u[i - 1] * T[i]
        P2 = V[i] + u[i] * T[i]
        add_line(cur, P1)
        sgn = 1.0 if theta[i] > 0 else -1.0            # bearing increasing = right turn
        # normal pointing to the inside of the turn: right of heading = (-dy, dx) ... in (X,Y) with bearing atan2(dY,dX)
        # rotating the heading by +theta (bearing increasing) turns towards  n_in = (-u_y, u_x)   [90 deg rotation]
        n_in = np.array([-u[i - 1][1], u[i - 1][0]]) * sgn
        C = P1 + n_in * R[i]
        a1 = math.atan2(P1[1] - C[1], P1[0] - C[0])
        # moving along the arc with the bearing changing by theta: the position angle changes by +theta (same sense)
        arc_len = R[i] * abs(theta[i])
        n = max(2, int(math.ceil(arc_len / DS)))
        for t in np.linspace(0, 1, n + 1)[:-1]:
            a = a1 + theta[i] * t
            pts.append(np.array([C[0] + R[i] * math.cos(a), C[1] + R[i] * math.sin(a)]))
            kap.append(sgn / R[i])
        cur = P2
    add_line(cur, V[-1])
    pts.append(V[-1].copy())
    kap.append(0.0)
    return np.array(pts), np.array(kap)


def resample_uniform(pts, ds=DS):
    s = cumlen(pts)
    L = s[-1]
    n = max(2, int(math.ceil(L / ds)) + 1)
    t = np.linspace(0, L, n)
    x = np.interp(t, s, pts[:, 0])
    y = np.interp(t, s, pts[:, 1])
    return np.stack([x, y], 1), t


def gauss_smooth_open(pts, sigma_m, ds):
    """Gaussian smoothing along the path with odd reflection at both ends (end points stay fixed)."""
    if sigma_m < 0.5:
        return pts
    sig = sigma_m / ds
    r = int(math.ceil(3.5 * sig))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sig) ** 2)
    k /= k.sum()
    out = np.empty_like(pts)
    n = len(pts)
    r = min(r, n - 2)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sig) ** 2)
    k /= k.sum()
    for c in range(2):
        x = pts[:, c]
        left = 2 * x[0] - x[1:r + 1][::-1]
        right = 2 * x[-1] - x[-r - 1:-1][::-1]
        ext = np.concatenate([left, x, right])
        out[:, c] = np.convolve(ext, k, mode="valid")
    return out


def bearings(pts):
    d = np.empty_like(pts)
    d[1:-1] = pts[2:] - pts[:-2]
    d[0] = pts[1] - pts[0]
    d[-1] = pts[-1] - pts[-2]
    return np.arctan2(d[:, 1], d[:, 0])


def curvature(pts, s, span=6.0):
    """signed curvature from three points `span` m apart (Menger); + = right turn (bearing increasing)."""
    n = len(pts)
    ia = np.clip(np.searchsorted(s, s - span), 0, n - 1)
    ib = np.clip(np.searchsorted(s, s + span), 0, n - 1)
    a, b, c = pts[ia], pts, pts[ib]
    ab = b - a
    bc = c - b
    ac = c - a
    cross = ab[:, 0] * bc[:, 1] - ab[:, 1] * bc[:, 0]        # >0: counter-clockwise in (X,Y) = bearing increasing
    den = np.sqrt((ab ** 2).sum(1)) * np.sqrt((bc ** 2).sum(1)) * np.sqrt((ac ** 2).sum(1))
    k = np.zeros(n)
    ok = den > 1e-9
    k[ok] = 2.0 * cross[ok] / den[ok]
    return k


def fit_alignment(plan, cls_name, log=None):
    """plan: output of roadplan.plan_road. returns dict(xy, s, kappa, spans[(kind, s_a, s_b)], hairpins, ...)"""
    c = RD.CLASSES[cls_name]
    P = plan["path"]
    s0 = cumlen(P)
    keep = set()
    leg_trim = {}
    locked = set()
    for kind, ia, ib in plan["spans"]:
        run = 70.0
        sa, sb = s0[ia], s0[ib]
        ira = int(np.searchsorted(s0, sa - run + 1.0))
        irb = int(min(len(P) - 1, np.searchsorted(s0, sb + run - 1.0)))
        keep.update([ira, ia, ib, irb])
        locked.update([ira, ia, ib, irb])
        leg_trim[(ira, ia)] = 10.0
        leg_trim[(ib, irb)] = 10.0
    idx = rdp_keep(P, c["rdp_tol"], keep)
    V0 = P[idx]
    locked_v = [k for k, i in enumerate(idx) if int(i) in locked]
    # remap trim keys from path-index space to vertex-index space
    pos = {int(i): k for k, i in enumerate(idx)}
    lt = {}
    for (a, b), v in leg_trim.items():
        if a in pos and b in pos:
            lt[(pos[a], pos[b])] = v
    V, T, R, theta, hair, ids = fit_pi(V0, locked_v, c, lt)
    pts, kap = build_path(V, T, R, theta)
    pts, s = resample_uniform(pts, DS)
    pts = gauss_smooth_open(pts, c["smooth"], s[1] - s[0])
    s = cumlen(pts)
    pts2, s2 = resample_uniform(pts, DS)
    k2 = curvature(pts2, s2, 6.0)
    # map forced spans onto the final alignment
    spans = []
    for kind, ia, ib in plan["spans"]:
        d1, sa_f, _, _ = nearest_on_polyline(pts2, s2, P[ia])
        d2, sb_f, _, _ = nearest_on_polyline(pts2, s2, P[ib])
        spans.append((kind, float(min(sa_f, sb_f)), float(max(sa_f, sb_f))))
    hp = [(V[i][0], V[i][1], float(R[i])) for i in range(len(V)) if hair[i] and R[i] > 0]
    return dict(xy=pts2, s=s2, kappa=k2, spans=spans, pi=V, pi_R=R, pi_theta=theta, hair_pi=hp)


def exact_alignment(plan, cls_name, smooth=None):
    """alignment from a path that already has the right geometry (grade-line tracer: legs with limited turn rate + hairpin
    arcs of known radius): no vertex fitting, only uniform 2 m resampling and a light smoothing."""
    c = RD.CLASSES[cls_name]
    P = np.asarray(plan["path"], dtype=float)
    # drop (near) duplicate points
    keep = np.concatenate([[True], np.hypot(*np.diff(P, axis=0).T) > 0.05])
    P = P[keep]
    pts, s = resample_uniform(P, DS)
    sm = c["smooth"] if smooth is None else smooth
    pts = gauss_smooth_open(pts, sm, s[1] - s[0])
    pts2, s2 = resample_uniform(pts, DS)
    k2 = curvature(pts2, s2, 6.0)
    spans = []
    for kind, ia, ib in plan["spans"]:
        d1, sa_f, _, _ = nearest_on_polyline(pts2, s2, P[ia])
        d2, sb_f, _, _ = nearest_on_polyline(pts2, s2, P[ib])
        spans.append((kind, float(min(sa_f, sb_f)), float(max(sa_f, sb_f))))
    hp = [(float(x), float(y), float(r)) for (x, y, r) in plan.get("hairpins", [])]
    return dict(xy=pts2, s=s2, kappa=k2, spans=spans, pi=np.zeros((0, 2)), pi_R=np.zeros(0), pi_theta=np.zeros(0), hair_pi=hp)
