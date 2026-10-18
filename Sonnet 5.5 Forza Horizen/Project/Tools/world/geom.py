"""2-D polyline geometry helpers (numpy only)."""
import math

import numpy as np


def cumlen(pts):
    d = np.sqrt(((pts[1:] - pts[:-1]) ** 2).sum(axis=1))
    return np.concatenate([[0.0], np.cumsum(d)])


def polyline_length(pts):
    return float(cumlen(pts)[-1])


def resample(pts, ds, closed=False):
    """Resample polyline at (approximately) uniform spacing <= ds. Keeps first/last point exactly."""
    pts = np.asarray(pts, dtype=np.float64)
    s = cumlen(pts)
    total = s[-1]
    n = max(2, int(math.ceil(total / ds)) + 1)
    t = np.linspace(0.0, total, n)
    x = np.interp(t, s, pts[:, 0])
    y = np.interp(t, s, pts[:, 1])
    return np.stack([x, y], axis=1), t


def interp_along(s_src, vals, s_q):
    return np.interp(s_q, s_src, vals)


def headings(pts):
    """heading angle (radians, atan2(dY, dX) i.e. 0 = +X/north, pi/2 = +Y/east) per point (central differences)."""
    d = np.empty_like(pts)
    d[1:-1] = pts[2:] - pts[:-2]
    d[0] = pts[1] - pts[0]
    d[-1] = pts[-1] - pts[-2]
    return np.arctan2(d[:, 1], d[:, 0])


def unwrap_headings(h):
    return np.unwrap(h)


def curvature_from_pts(pts, s=None, win=3):
    """signed curvature (1/m; + = turning left, i.e. towards +heading side CCW seen with X right, Y up... see docs)
    via heading derivative over +-win samples. Sign convention: kappa > 0 when heading angle increases along s
    (atan2(dY,dX) increasing). With X=north, Y=east this is a turn towards EAST->NORTH, i.e. counter-clockwise on a
    (Y right, X up) map = a LEFT turn for a driver."""
    if s is None:
        s = cumlen(pts)
    h = np.unwrap(headings(pts))
    n = len(pts)
    k = np.zeros(n)
    for i in range(n):
        a = max(0, i - win)
        b = min(n - 1, i + win)
        ds = s[b] - s[a]
        if ds > 1e-6:
            k[i] = (h[b] - h[a]) / ds
    return k


def menger_curvature(pts, s, span=6.0):
    """Radius estimate using three points ~span metres apart (robust against sampling noise). signed."""
    n = len(pts)
    k = np.zeros(n)
    idx_prev = np.searchsorted(s, s - span).clip(0, n - 1)
    idx_next = np.searchsorted(s, s + span).clip(0, n - 1)
    a = pts[idx_prev]
    b = pts
    c = pts[idx_next]
    ab = b - a
    bc = c - b
    ac = c - a
    cross = ab[:, 0] * bc[:, 1] - ab[:, 1] * bc[:, 0]
    la = np.sqrt((ab ** 2).sum(1))
    lb = np.sqrt((bc ** 2).sum(1))
    lc = np.sqrt((ac ** 2).sum(1))
    den = la * lb * lc
    ok = den > 1e-6
    k[ok] = 2.0 * cross[ok] / den[ok]
    return k


def rdp(pts, tol):
    """Ramer-Douglas-Peucker; returns indices of kept vertices."""
    n = len(pts)
    keep = np.zeros(n, dtype=bool)
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        if b <= a + 1:
            continue
        p = pts[a + 1:b]
        d = pts[b] - pts[a]
        L = math.hypot(d[0], d[1])
        if L < 1e-9:
            dist = np.sqrt(((p - pts[a]) ** 2).sum(1))
        else:
            dist = np.abs(d[0] * (p[:, 1] - pts[a][1]) - d[1] * (p[:, 0] - pts[a][0])) / L
        k = int(np.argmax(dist))
        if dist[k] > tol:
            m = a + 1 + k
            keep[m] = True
            stack.append((a, m))
            stack.append((m, b))
    return np.nonzero(keep)[0]


def raster_dist(shape, step, origin, pts, radius, vals=None, dist=None, attr=None):
    """Distance from each grid node to a polyline, limited to `radius` (nodes farther keep the init value).
    Grid arrays are [j, i] with X = origin + step*i, Y = origin + step*j.
    vals: optional (m, k) per-vertex attributes interpolated at the nearest point.
    Returns dist (float32) and attr (k, h, w) or None."""
    h, w = shape
    pts = np.asarray(pts, dtype=np.float64)
    if dist is None:
        dist = np.full(shape, np.float32(radius * 2.0 + 1.0), dtype=np.float32)
    k = 0
    if vals is not None:
        vals = np.asarray(vals, dtype=np.float64)
        if vals.ndim == 1:
            vals = vals[:, None]
        k = vals.shape[1]
        if attr is None:
            attr = np.zeros((k, h, w), dtype=np.float32)
    for s in range(len(pts) - 1):
        A = pts[s]
        B = pts[s + 1]
        lo = np.minimum(A, B) - radius
        hi = np.maximum(A, B) + radius
        i0 = max(0, int(math.floor((lo[0] - origin) / step)))
        i1 = min(w - 1, int(math.ceil((hi[0] - origin) / step)))
        j0 = max(0, int(math.floor((lo[1] - origin) / step)))
        j1 = min(h - 1, int(math.ceil((hi[1] - origin) / step)))
        if i1 < i0 or j1 < j0:
            continue
        xs = origin + step * np.arange(i0, i1 + 1, dtype=np.float64)
        ys = origin + step * np.arange(j0, j1 + 1, dtype=np.float64)
        px = xs[None, :] - A[0]
        py = ys[:, None] - A[1]
        dx, dy = B[0] - A[0], B[1] - A[1]
        L2 = dx * dx + dy * dy
        if L2 < 1e-12:
            t = np.zeros_like(px + py)
        else:
            t = np.clip((px * dx + py * dy) / L2, 0.0, 1.0)
        ex = px - t * dx
        ey = py - t * dy
        dd = np.sqrt(ex * ex + ey * ey).astype(np.float32)
        sub = dist[j0:j1 + 1, i0:i1 + 1]
        m = dd < sub
        if not m.any():
            continue
        sub[m] = dd[m]
        if k:
            tt = t.astype(np.float32)
            for q in range(k):
                v = (vals[s, q] * (1.0 - tt) + vals[s + 1, q] * tt).astype(np.float32)
                asub = attr[q, j0:j1 + 1, i0:i1 + 1]
                asub[m] = v[m]
    return dist, attr


def seg_intersections(P, Q):
    """All proper intersections between polylines P (n,2) and Q (m,2).
    Returns list of (iP, tP, iQ, tQ, x, y). Brute force with bbox rejection (fine for few thousand segments)."""
    out = []
    if len(P) < 2 or len(Q) < 2:
        return out
    p0 = P[:-1]
    p1 = P[1:]
    q0 = Q[:-1]
    q1 = Q[1:]
    pmin = np.minimum(p0, p1)
    pmax = np.maximum(p0, p1)
    qmin = np.minimum(q0, q1)
    qmax = np.maximum(q0, q1)
    for i in range(len(p0)):
        cand = np.nonzero((qmin[:, 0] <= pmax[i, 0]) & (qmax[:, 0] >= pmin[i, 0]) &
                          (qmin[:, 1] <= pmax[i, 1]) & (qmax[:, 1] >= pmin[i, 1]))[0]
        if len(cand) == 0:
            continue
        r = p1[i] - p0[i]
        s = q1[cand] - q0[cand]
        den = r[0] * s[:, 1] - r[1] * s[:, 0]
        ok = np.abs(den) > 1e-12
        if not ok.any():
            continue
        cand = cand[ok]
        den = den[ok]
        s = s[ok]
        qp = q0[cand] - p0[i]
        t = (qp[:, 0] * s[:, 1] - qp[:, 1] * s[:, 0]) / den
        u = (qp[:, 0] * r[1] - qp[:, 1] * r[0]) / den
        hit = (t >= 0) & (t <= 1) & (u >= 0) & (u <= 1)
        for c, tt, uu in zip(cand[hit], t[hit], u[hit]):
            pt = p0[i] + tt * r
            out.append((i, float(tt), int(c), float(uu), float(pt[0]), float(pt[1])))
    return out


def nearest_on_polyline(pts, s, q):
    """nearest point on polyline pts (cumulative length s) to q. returns (dist, s_at, point, tangent)"""
    a = pts[:-1]
    b = pts[1:]
    d = b - a
    L2 = (d ** 2).sum(1)
    L2[L2 < 1e-12] = 1e-12
    t = np.clip(((q - a) * d).sum(1) / L2, 0, 1)
    p = a + d * t[:, None]
    dist = np.sqrt(((p - q) ** 2).sum(1))
    k = int(np.argmin(dist))
    seglen = math.sqrt(L2[k])
    tang = d[k] / seglen
    return float(dist[k]), float(s[k] + t[k] * seglen), p[k], tang


def close_runs(A, B, tol, ignore_pts=(), ignore_r=100.0):
    """number of separate runs of samples of polyline A that come within `tol` of polyline B (both (n,2) point arrays),
    ignoring samples within ignore_r of the points in ignore_pts (junction ends where roads are meant to meet)."""
    A = np.asarray(A, dtype=float)
    B = np.asarray(B, dtype=float)
    if len(A) == 0 or len(B) == 0:
        return 0
    near = np.zeros(len(A), dtype=bool)
    for i0 in range(0, len(A), 300):
        a = A[i0:i0 + 300]
        d2 = ((a[:, None, :] - B[None, :, :]) ** 2).sum(2).min(1)
        near[i0:i0 + 300] = d2 < tol * tol
    for p in ignore_pts:
        p = np.asarray(p, dtype=float)
        near &= ((A[:, 0] - p[0]) ** 2 + (A[:, 1] - p[1]) ** 2) > ignore_r * ignore_r
    runs = 0
    prev = False
    for v in near:
        if v and not prev:
            runs += 1
        prev = bool(v)
    return runs
