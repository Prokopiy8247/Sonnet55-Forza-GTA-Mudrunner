"""Slope-limited least-cost road path planner on a coarse grid (6 m cells, 16-neighbour moves).

cost(edge) = length * terrain multiplier * (1 + grade penalty) + side-slope penalty + turn penalty,
hard cap on grade at 1.4 x class limit. Switchbacks emerge naturally where the terrain is steeper than the limit.
"""
import heapq
import math

import numpy as np

import roads_def as RD
from common import HALF, N, box_blur_axis, gradient_xy, log
from geom import raster_dist

CELL = 6.0
NC = int(round(2 * HALF / CELL)) + 1            # 673


class PlanGrid:
    def __init__(self, Z, river):
        """Z: terrain on the 6 m plan grid [j,i] (673x673). river: bool array same shape (wet cells)."""
        self.cell = CELL
        n = NC
        assert Z.shape == (n, n), Z.shape
        Zs = box_blur_axis(box_blur_axis(np.ascontiguousarray(Z).astype(np.float32), 1, 0), 1, 1)
        self.Z = Zs
        self.n = n
        gx, gy = gradient_xy(self.Z, CELL)                                       # d/dX (axis1), d/dY (axis0)
        self.gx = gx
        self.gy = gy
        self.slope = np.sqrt(gx * gx + gy * gy)
        self.river = river
        ax = np.abs(np.arange(n) * CELL - HALF)
        e = HALF - np.maximum(ax[None, :], ax[:, None])
        self.border = e < 28.0            # keep roads off the map edge (|X|,|Y| < 1988)
        self.sea = self.Z < 1.2
        self.sea_buffer = box_blur_axis(box_blur_axis(self.sea.astype(np.float32), 2, 0), 2, 1) > 0.01
        # distance to the sea in metres (capped at 360 m): chebyshev-ish growth, 60 iterations of a 3x3 dilation
        sd = np.full(self.sea.shape, 360.0, dtype=np.float32)
        cur = self.sea.copy()
        sd[cur] = 0.0
        for it in range(1, 61):
            p_ = np.pad(cur, 1, mode="constant")
            nxt = (p_[1:-1, 1:-1] | p_[:-2, 1:-1] | p_[2:, 1:-1] | p_[1:-1, :-2] | p_[1:-1, 2:] | p_[:-2, :-2] | p_[:-2, 2:] | p_[2:, :-2] | p_[2:, 2:])
            new = nxt & ~cur
            sd[new] = it * CELL * 1.08
            cur = nxt
        self.sea_dist = sd

    @staticmethod
    def from_h1(H1, water_z):
        Hb = box_blur_axis(box_blur_axis(H1.astype(np.float32), 3, 0), 3, 1)
        Z = Hb[::6, ::6]
        wet = (water_z[::6, ::6] > -9000)
        return PlanGrid(Z, wet)

    @staticmethod
    def from_macro(M):
        from terrain import resize_to
        Z = resize_to(M["H"], M["step"], CELL)
        wet = resize_to((M["water_river"] > -9000).astype(np.float32), M["step"], CELL) > 0.2
        return PlanGrid(Z, wet)

    def idx(self, X, Y):
        return int(round((X + HALF) / CELL)), int(round((Y + HALF) / CELL))

    def xy(self, i, j):
        return i * CELL - HALF, j * CELL - HALF


# 16 neighbour moves
_MOVES = []
for di in (-2, -1, 0, 1, 2):
    for dj in (-2, -1, 0, 1, 2):
        if (di, dj) == (0, 0):
            continue
        if abs(di) == 2 and abs(dj) in (0, 2):
            continue
        if abs(dj) == 2 and di == 0:
            continue
        _MOVES.append((di, dj))
assert len(_MOVES) == 16
_DIRANG = [math.atan2(dj, di) for di, dj in _MOVES]


def _turn_table():
    t = []
    for a in _DIRANG:
        row = []
        for b in _DIRANG:
            d = abs(b - a)
            d = min(d, 2 * math.pi - d)
            row.append((d / (math.pi / 2)) ** 2)
        t.append(row)
    return t


_TURN = _turn_table()


def corridor_dist(grid, pts, radius):
    """distance (m) from each plan cell to polyline pts (X,Y), limited to radius; returns [j,i] float32 array."""
    d, _ = raster_dist((grid.n, grid.n), CELL, -HALF, np.asarray(pts, dtype=np.float64), radius)
    return d


def astar(grid, start, goal, cls_name, cdist, cw, window, extra_block=None, mult_extra=None,
          water_ok=False, turn_scale=1.0, max_exp=1_500_000, cap_mult=1.4):
    """A* between plan cells start=(i,j) and goal=(i,j) inside window (i0,i1,j0,j1) inclusive.
    Returns list of (i, j) or None."""
    c = RD.CLASSES[cls_name]
    gmax = c["g_max"]
    cap = cap_mult * gmax
    i0, i1, j0, j1 = window
    W = i1 - i0 + 1
    Hh = j1 - j0 + 1
    sub = (slice(j0, j1 + 1), slice(i0, i1 + 1))
    Z = grid.Z[sub].ravel().tolist()
    gxl = grid.gx[sub].ravel().tolist()
    gyl = grid.gy[sub].ravel().tolist()
    cd = cdist[sub]
    blocked = (grid.border[sub] | grid.sea[sub])
    if extra_block is not None:
        blocked = blocked | extra_block[sub]
    # terrain multiplier: river crossing penalty, steep rock, near sea, corridor bias
    mult = np.ones(cd.shape, dtype=np.float32)
    river = grid.river[sub]
    if not water_ok:
        mult += np.where(river, 22.0, 0.0).astype(np.float32)
    mult += np.where(grid.sea_buffer[sub], 0.7, 0.0).astype(np.float32)
    mult += (np.clip(cd / max(cw, 1.0), 0, 2.0) ** 2 * 0.25).astype(np.float32)
    blocked = blocked | (cd > cw * 1.0)
    if mult_extra is not None:
        mult = mult + mult_extra[sub]
    mult = mult.ravel().tolist()
    blockl = blocked.ravel().tolist()
    si = (start[1] - j0) * W + (start[0] - i0)
    gi = (goal[1] - j0) * W + (goal[0] - i0)
    if blockl[si]:
        blockl[si] = False
    if blockl[gi]:
        blockl[gi] = False
    gi_i, gi_j = goal[0] - i0, goal[1] - j0
    cell = CELL
    moves = []
    for k, (di, dj) in enumerate(_MOVES):
        L = cell * math.hypot(di, dj)
        ux, uy = di / math.hypot(di, dj), dj / math.hypot(di, dj)
        moves.append((di, dj, L, ux, uy, dj * W + di, k))
    inf = float("inf")
    g = [inf] * (W * Hh)
    par = [-1] * (W * Hh)
    pdir = [-1] * (W * Hh)
    g[si] = 0.0
    inv_gmax = 1.0 / (0.93 * gmax)
    turn_w = c["turn"] * turn_scale * cell
    cs0 = 0.18
    kc = 5.0
    heap = [(math.hypot(start[0] - goal[0], start[1] - goal[1]) * cell, 0.0, si)]
    exp = 0
    push = heapq.heappush
    pop = heapq.heappop
    turn = _TURN
    while heap:
        f, gc, u = pop(heap)
        if gc > g[u]:
            continue
        if u == gi:
            break
        exp += 1
        if exp > max_exp:
            return None
        uj, ui = divmod(u, W)
        pd = pdir[u]
        zu = Z[u]
        mu = mult[u]
        gxu = gxl[u]
        gyu = gyl[u]
        trow = turn[pd] if pd >= 0 else None
        for di, dj, L, ux, uy, off, k in moves:
            vi = ui + di
            vj = uj + dj
            if vi < 0 or vj < 0 or vi >= W or vj >= Hh:
                continue
            v = u + off
            if blockl[v]:
                continue
            dz = Z[v] - zu
            grade = (dz if dz >= 0 else -dz) / L
            if grade > cap:
                continue
            r = grade * inv_gmax
            r2 = r * r
            ex = r - 1.0
            cst = L * 0.5 * (mu + mult[v]) * (1.0 + 0.9 * r2 * r2 + (60.0 * ex * ex if ex > 0 else 0.0))
            ax = 0.5 * (gxu + gxl[v])
            ay = 0.5 * (gyu + gyl[v])
            cr = -ax * uy + ay * ux
            if cr < 0:
                cr = -cr
            if cr > cs0:
                cst += L * kc * (cr - cs0) * (cr - cs0)
            if trow is not None:
                cst += turn_w * trow[k]
            ng = gc + cst
            if ng < g[v]:
                g[v] = ng
                par[v] = u
                pdir[v] = k
                h = math.hypot(vi - gi_i, vj - gi_j) * cell
                push(heap, (ng + h, ng, v))
    if g[gi] == inf:
        return None
    path = []
    u = gi
    while u != -1:
        uj, ui = divmod(u, W)
        path.append((ui + i0, uj + j0))
        u = par[u]
    path.reverse()
    return path


def window_for(grid, a, b, margin_cells, bbox=None):
    i0 = max(0, min(a[0], b[0]) - margin_cells)
    i1 = min(grid.n - 1, max(a[0], b[0]) + margin_cells)
    j0 = max(0, min(a[1], b[1]) - margin_cells)
    j1 = min(grid.n - 1, max(a[1], b[1]) + margin_cells)
    if bbox is not None:
        i0, i1 = max(i0, bbox[0]), min(i1, bbox[1])
        j0, j1 = max(j0, bbox[2]), min(j1, bbox[3])
    return (i0, i1, j0, j1)


def straight_cells(a, b):
    """cells along a straight link (6 m spacing)"""
    n = max(2, int(math.ceil(math.hypot(b[0] - a[0], b[1] - a[1]))) + 1)
    out = []
    for t in np.linspace(0, 1, n):
        out.append((int(round(a[0] + (b[0] - a[0]) * t)), int(round(a[1] + (b[1] - a[1]) * t))))
    return out


def plan_road(grid, road, node_xy, existing, log_=True):
    """Plan the dense path for one road definition.
    node_xy: dict node->(X,Y). existing: dict road_id -> dict(xy=Nx2 array, s=cumlen) for 'ON' endpoints.
    Returns dict(path=Nx2 array world XY, keep=indices that must survive simplification, spans=list of forced spans
    (kind, i_start, i_end in path indexes), start_xy, end_xy)."""
    c = RD.CLASSES[road["cls"]]
    cw = road.get("corridor", c["cw"])

    def resolve(spec, other_hint):
        if isinstance(spec, str):
            return np.array(node_xy[spec], dtype=float), None
        # ("ON", road_id, hint)
        _, rid, hint = spec
        ex = existing[rid]
        from geom import nearest_on_polyline
        dist, s_at, p, tang = nearest_on_polyline(ex["xy"], ex["s"], np.array(hint, dtype=float))
        return p, tang

    start_p, start_t = resolve(road["start"], None)
    end_p, end_t = resolve(road["end"], None)
    wps = []         # list of ("pt", xy, straight) / ("link", kind, a, b)
    raw = road["wp"]
    sidx = road.get("straight_idx", set())
    for k, w in enumerate(raw):
        if isinstance(w[0], str) and w[0] == "via":
            wps.append(("via", np.array(w[1], float), False))
        elif isinstance(w[0], str):
            wps.append(("link", w[0], np.array(w[1], float), np.array(w[2], float)))
        else:
            wps.append(("pt", np.array(w, dtype=float), k in sidx))
    # keep the intermediate waypoints off the shore (cliff edges are not drivable): push them inland until 150 m clear of the sea
    margin = float(road.get("coast_margin", 230.0))
    for k_ in range(1, len(wps) - 1):
        if wps[k_][0] == "pt" and not wps[k_][2]:
            q = np.array(wps[k_][1], dtype=float)
            for _it in range(14):
                i_, j_ = grid.idx(q[0], q[1])
                i_ = min(max(i_, 1), grid.n - 2)
                j_ = min(max(j_, 1), grid.n - 2)
                d_ = float(grid.sea_dist[j_, i_])
                if d_ >= margin:
                    break
                gx_ = float(grid.sea_dist[j_, i_ + 1] - grid.sea_dist[j_, i_ - 1])
                gy_ = float(grid.sea_dist[j_ + 1, i_] - grid.sea_dist[j_ - 1, i_])
                gn = math.hypot(gx_, gy_)
                if gn < 1e-6:
                    break
                q = q + np.array([gx_, gy_]) / gn * 36.0
            wps[k_] = ("pt", q, wps[k_][2])
    # first/last point replaced with the exact node positions
    if wps[0][0] == "pt":
        wps[0] = ("pt", start_p, False)
    else:
        wps.insert(0, ("pt", start_p, False))
    if wps[-1][0] == "pt":
        wps[-1] = ("pt", end_p, wps[-1][2])
    else:
        wps.append(("pt", end_p, False))
    # T-junction approach: end perpendicular to the main road
    def approach(p, tang, prev_xy, dist=62.0):
        if tang is None:
            return None
        nrm = np.array([-tang[1], tang[0]])
        if np.dot(nrm, prev_xy - p) < 0:
            nrm = -nrm
        return p + nrm * dist
    if road["end"] != "" and not isinstance(road["end"], str) and end_t is not None:
        prev = wps[-2][1] if wps[-2][0] in ("pt", "via") else wps[-2][3]
        ap = approach(end_p, end_t, prev)
        wps.insert(len(wps) - 1, ("pt", ap, False))
        wps[-1] = ("pt", end_p, True)
    if not isinstance(road["start"], str) and start_t is not None:
        nxt = wps[1][1] if wps[1][0] in ("pt", "via") else wps[1][2]
        ap = approach(start_p, start_t, nxt)
        wps.insert(1, ("pt", ap, True))
    # expand forced links with runways (straight extension before/after along the axis)
    seq = []     # list of ("pt", xy, straight) | ("link", kind, a, b, run)
    for w in wps:
        if w[0] == "pt":
            seq.append(("pt", w[1], w[2]))
        elif w[0] == "via":
            seq.append(("via", w[1], False))
        else:
            _, kind, a, b = w
            ax = (b - a) / np.linalg.norm(b - a)
            run = 70.0
            seq.append(("pt", a - ax * run, True))
            seq.append(("link", kind, a, b, run))
            seq.append(("pt", b + ax * run, True))
    # polyline of waypoints for the corridor distance field
    guide = []
    for w in seq:
        if w[0] in ("pt", "via"):
            guide.append(w[1])
        else:
            guide.append(w[2])
            guide.append(w[3])
    guide = np.array(guide)
    cd = corridor_dist(grid, guide, cw * 2.6 + 30.0)
    if road.get("free"):
        # intermediate plain waypoints are only guides: plan directly between hard points (ends and forced links)
        hard = []
        for k, w in enumerate(seq):
            if w[0] == "via":
                continue
            if w[0] == "link" or k == 0 or k == len(seq) - 1 or seq[k - 1][0] == "link" or seq[k + 1][0] == "link":
                hard.append(w)
        seq = hard
    pts = []
    spans = []

    def add_straight(p, q):
        n = max(1, int(math.ceil(float(np.linalg.norm(q - p)) / CELL)))
        for t in np.linspace(0.0, 1.0, n + 1)[1:]:
            pts.append(p + (q - p) * t)

    # walk through the sequence: pts connected by A*, ladder legs / forced links by exact straight lines
    cur_xy = None
    for k, w in enumerate(seq):
        if w[0] == "via":
            continue
        if w[0] == "pt":
            xyw = np.array(w[1], dtype=float)
            if cur_xy is None:
                pts.append(xyw)
                cur_xy = xyw
                continue
            if (k > 0 and seq[k - 1][0] == "link") or w[2]:
                add_straight(cur_xy, xyw)
                cur_xy = xyw
                continue
            cur = grid.idx(cur_xy[0], cur_xy[1])
            cell = grid.idx(xyw[0], xyw[1])
            margin = int(max(cw, 160.0) / CELL) + 12
            win = window_for(grid, cur, cell, margin)
            res = None
            for attempt, (wmul, capm) in enumerate([(1.0, 1.06), (1.5, 1.12), (2.2, 1.3), (3.0, 1.7), (3.6, 2.6)]):
                res = astar(grid, cur, cell, road["cls"], cd, cw * wmul, win,
                            turn_scale=road.get("turn_scale", 1.0), water_ok=road.get("water_ok", False), cap_mult=capm)
                if res is not None:
                    if attempt >= 2 and log_:
                        log("  WARNING road %s: leg planned with relaxed constraints (attempt %d)" % (road["id"], attempt))
                    break
                margin = int(margin * 1.5)
                win = window_for(grid, cur, cell, margin)
            if res is None:
                raise RuntimeError("road %s: no path between %s and %s" % (road["id"], grid.xy(*cur), grid.xy(*cell)))
            rxy = np.array([(i * CELL - HALF, j * CELL - HALF) for i, j in res], dtype=float)
            rxy[0] = cur_xy
            rxy[-1] = xyw
            pts.extend(list(rxy[1:]))
            cur_xy = xyw
        else:
            _, kind, a_, b_, run = w
            add_straight(cur_xy, a_)
            i_start = len(pts) - 1
            add_straight(a_, b_)
            i_end = len(pts) - 1
            spans.append((kind, i_start, i_end))
            cur_xy = b_
    xy = np.array(pts, dtype=float)
    xy[0] = start_p
    xy[-1] = end_p
    return dict(path=xy, spans=spans, start_xy=start_p, end_xy=end_p)


def plan_traced(grid, road, node_xy, existing, log_=True):  # noqa: C901
    """plan a mountain road with the switchback designer (switchback.py): hairpin apexes by dynamic programming along a guide
    (a drainage line of the natural terrain or an authored polyline), then exact arc / tangent geometry.
    The road is designed from its LOW end upwards; trace['reverse'] says the road's END is the low end."""
    import tracer as TR
    import switchback as SB
    from geom import nearest_on_polyline, close_runs
    spec = dict(road["trace"])
    sig = float(spec.pop("surf_sigma", 1.6))
    cache = getattr(grid, "surf_cache", None)
    if cache is None:
        cache = grid.surf_cache = {}
    if sig not in cache:
        cache[sig] = TR.Surface(grid.Z, sigma_cells=sig)
    surf = cache[sig]

    def resolve(spec_):
        if isinstance(spec_, str):
            return np.array(node_xy[spec_], dtype=float), None
        _, rid, hint = spec_
        ex = existing[rid]
        dist, s_at, p, tang = nearest_on_polyline(ex["xy"], ex["s"], np.array(hint, dtype=float))
        return p, tang

    start_p, start_t = resolve(road["start"])
    end_p, end_t = resolve(road["end"])
    rev = bool(spec.pop("reverse", False))
    lo, hi = (end_p, start_p) if rev else (start_p, end_p)
    tail = spec.pop("tail", None)
    lo_dp = np.array(tail["point"], dtype=float) if tail is not None else lo
    seeds = spec.pop("seeds", [1])
    want = spec.pop("want", None)
    # ---- guide (low -> high)
    if "valley" in spec:
        v = spec.pop("valley")
        G = TR.valley_guide(surf, v["src"], v.get("z_stop", 120.0), sigma_m=v.get("sigma", 140.0))
        G = G[::-1]
        k0 = int(np.argmin(np.hypot(G[:, 0] - lo_dp[0], G[:, 1] - lo_dp[1])))
        G = G[k0:]                                       # no hook: the guide starts where the valley passes the road start
        keep = np.hypot(G[:, 0] - lo_dp[0], G[:, 1] - lo_dp[1]) > v.get("lo_clear", 220.0)
        keep &= np.hypot(G[:, 0] - hi[0], G[:, 1] - hi[1]) > 80.0
        mid = [tuple(q) for q in G[keep]]
        guide = np.array([tuple(lo_dp)] + list(spec.pop("lo_via", [])) + mid + [tuple(hi)], dtype=float)
    else:
        guide = np.asarray(spec["guide"], dtype=float)
    spec["guide"] = guide
    avoid = [ex_["xy"] for ex_ in existing.values()]
    best = None
    tries = []
    info = {}
    base_spec = dict(spec)
    close_w = float(spec.get("close_w", 1.6))
    sep_k = float(spec.get("sep_k", 1.0))
    for stage in range(4):
        if stage == 0:
            spec = dict(base_spec)
            av = avoid
        else:
            spec = dict(base_spec)
            f = (0.0, 0.25, 0.45, 0.7)[stage]
            spec["min_leg"] = base_spec.get("min_leg", 200.0) * (1.0 - 0.25 * stage)
            spec["g_lo"] = base_spec.get("g_lo", 0.045) * (1.0 - f)
            spec["g_hi"] = base_spec.get("g_hi", 0.085) * (1.0 + f)
            spec["max_leg"] = base_spec.get("max_leg", 1400.0) * (1.0 + 0.4 * stage)
            spec["levels"] = (0.4, 0.55, 0.7, 0.85, 1.0)
            av = avoid if stage == 1 else []
            if log_:
                log("  %s: relaxing the switchback design (stage %d)" % (road["id"], stage))
        for sd in seeds:
            rng = np.random.default_rng(sd)
            apx, info = SB.plan_apexes(surf, guide, lo_dp, hi, spec, rng, avoid=av)
            if apx is None:
                tries.append((1e9, sd, 0, 0.0, 0, 0, 0))
                continue
            rr = SB.construct(surf, lo_dp, hi, apx, spec, rng)
            tun_span = None
            if spec.get("tunnel"):
                p2, tun_span, tun_info = SB.find_tunnel(surf, rr["path"], spec["tunnel"])
                if tun_span is not None:
                    rr = dict(rr)
                    rr["path"] = p2
                    rr["spans"] = [("tunnel", tun_span[0], tun_span[1])]
                    rr["ridge"] = dict(A=tun_info[0], B=tun_info[1], h=float(spec["tunnel"].get("ridge_h", 30.0)))
            path = rr["path"]
            n_h = len(rr["hairpins"])
            L = float(np.sum(np.hypot(*np.diff(path, axis=0).T)))
            score = info["cost"]
            if want:
                h0, h1 = want.get("hairpins", (0, 99))
                l0, l1 = want.get("length", (0, 1e9))
                score += 40.0 * (max(h0 - n_h, 0) + max(n_h - h1, 0)) + 0.02 * (max(l0 - L, 0) + max(L - l1, 0))
            n_cross = 0
            for rid_, ex_ in existing.items():
                xyo = ex_["xy"]
                bb = (xyo[:, 0].min() - 80, xyo[:, 0].max() + 80, xyo[:, 1].min() - 80, xyo[:, 1].max() + 80)
                sel = (path[:, 0] > bb[0]) & (path[:, 0] < bb[1]) & (path[:, 1] > bb[2]) & (path[:, 1] < bb[3])
                if sel.sum() < 3:
                    continue
                n_cross += close_runs(path[sel][::2], xyo[::2], 30.0, ignore_pts=(start_p, end_p), ignore_r=110.0)
            score += float(spec.get("cross_w", 25.0)) * n_cross
            # legs of the same road that run closer than ~80 m (cut / fill cones would collide): penalise per 6 m sample
            q = path[::2]
            sq = np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(q, axis=0).T))])
            n_close = 0
            n_hard = 0
            zq_ = surf.zv(q[:, 0], q[:, 1])
            for i0_ in range(0, len(q), 300):
                a_ = q[i0_:i0_ + 300]
                d2_ = ((a_[:, None, :] - q[None, :, :]) ** 2).sum(2)
                far_ = np.abs(sq[i0_:i0_ + 300, None] - sq[None, :]) > 140.0
                n_close += int((((d2_ < 80.0 ** 2) & far_).any(1)).sum())
                # two beds at different heights need a cut / fill wall between them: separation >= 12 m + |dz| (slopes ~1:1)
                dreq = 12.0 + sep_k * np.abs(zq_[i0_:i0_ + 300, None] - zq_[None, :])
                n_hard += int((((d2_ < dreq ** 2) & far_).any(1)).sum())
            score += close_w * n_close + float(spec.get("hard_w", 40.0)) * n_hard
            if spec.get("tunnel") and tun_span is None:
                score += float(spec.get("tunnel_miss", 60.0))
            tries.append((score, sd, n_h, L, n_cross, n_close, n_hard))
            if best is None or score < best[0]:
                best = (score, rr, sd, apx)
        if best is not None:
            break
    if best is None:
        raise RuntimeError("road %s: no switchback design found (%s)" % (road["id"], info))
    bt = min(tries, key=lambda t: t[0])
    if log_:
        log("  designed %-12s %d seeds -> seed %d: %d hairpins, %.0f m, %d crossings, %d close / %d overlapping samples" % (road["id"], len(tries), best[2], bt[2], bt[3], bt[4], bt[5], bt[6]))
    res = best[1]
    path = res["path"].copy()
    hp = list(res["hairpins"])
    path[0] = lo_dp
    path[-1] = hi
    spans = list(res.get("spans", []))
    if tail is not None:
        # A* tail from the real low end to the DP start; it arrives along the first DP leg direction (no kink at the joint)
        import align as AL
        d0 = path[min(8, len(path) - 1)] - path[0]
        d0 = d0 / max(np.hypot(*d0), 1e-9)
        v_end = path[0] - 170.0 * d0
        node_xy2 = dict(node_xy)
        node_xy2["_TL_LO"] = tuple(lo)
        node_xy2["_TL_HI"] = tuple(lo_dp)
        wps = [tuple(lo)] + [tuple(q) for q in tail.get("via", [])] + [tuple(v_end), tuple(lo_dp)]
        troad = dict(id=road["id"] + "_tail", cls=road["cls"], start="_TL_LO", end="_TL_HI", wp=wps, corridor=tail.get("corridor", 150.0),
                     turn_scale=tail.get("turn_scale", 3.0))
        tplan = plan_road(grid, troad, node_xy2, {}, log_=False)
        tal = AL.fit_alignment(tplan, road["cls"])
        txy = tal["xy"]
        n_t = len(txy)
        path = np.vstack([txy[:-1], path])
        spans = [(k, ia + n_t - 1, ib + n_t - 1) for (k, ia, ib) in spans]
        hp = [(x, y, r_) for (x, y, r_) in tal.get("hair_pi", [])] + hp
    if rev:
        n_ = len(path)
        spans = [(k, n_ - 1 - ib, n_ - 1 - ia) for (k, ia, ib) in spans]
        path = path[::-1].copy()
    path[0] = start_p
    path[-1] = end_p
    ridges = [res["ridge"]] if res.get("ridge") else []
    return dict(path=path, spans=spans, start_xy=start_p, end_xy=end_p, hairpins=hp, ridges=ridges)
