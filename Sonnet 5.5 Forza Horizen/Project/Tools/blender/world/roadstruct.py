"""
roadstruct.py - bridges and tunnels for "Roamline: Open Roads" (pure numpy, no bpy; see roadgeo.py for conventions).

build_bridge(plan, chunk) -> (MB, extra)   deck (slab or box girder) + parapet bases + piers + abutments (+ cable-stayed pylons)
build_tunnel(plan, chunk) -> (MB, extra)   floor with walkways, inner liner, outer shell, light strips, two portal head-walls

All dimensions in metres, Blender axes (see roadgeo).  Structure parts are quad soups (flat shaded) with metric box-projected UVs.
"""
import math

import numpy as np

from roadgeo import (MB, Soup, ribbon, _crown, BEVEL, ASPH, CONC, DIRT, GRAV, CURB, BCON, BSTL, TWAL, TLIT)

PARAPET_W = 0.45       # parapet base width (outside the shoulder)
PARAPET_H = 0.55       # parapet base height above the deck surface (guard rail / bridge rail is placed on top by the roadside kit)


# ----------------------------------------------------------------------------------------------------------------------
# helpers
def _frame(road, s):
    fr = road.at(s)
    return dict(C=np.array([fr["x"][0], fr["y"][0], fr["z"][0]]), T=np.array([fr["tx"][0], fr["ty"][0], 0.0]),
                R=np.array([fr["ty"][0], -fr["tx"][0], 0.0]), bank=float(fr["bank"][0]), s=float(s))


def _pt(fr, d, h=0.0, l=0.0):
    """World point: lateral d (right +), height h above the banked road plane, along offset l (travel direction)."""
    return fr["C"] + fr["R"] * d + fr["T"] * l + np.array([0.0, 0.0, -d * math.tan(fr["bank"]) + h])


def _terrain(plan, x, y, default):
    hm = plan.get("hm")
    if hm is None:
        return default
    return float(hm.z_bl(x, y))


def _terrain_min(plan, fr, ds, ls, default):
    hm = plan.get("hm")
    if hm is None:
        return default
    zs = []
    for d in ds:
        for l in ls:
            p = _pt(fr, d, 0.0, l)
            zs.append(float(hm.z_bl(p[0], p[1])))
    return min(zs)


def _ring(hw, hd, ch):
    c = min(ch, 0.45 * hw, 0.45 * hd)
    return [(hw - c, hd), (hw, hd - c), (hw, -(hd - c)), (hw - c, -hd), (-(hw - c), -hd), (-hw, -(hd - c)), (-hw, hd - c),
            (-(hw - c), hd)]


def prism(soup, c0, d0, c1, d1, R, T, mat, ch=0.12, top_cap=True, bottom_cap=False):
    """Tapered (optionally inclined) octagonal prism between ring centres c0/c1 with half sizes d0=(lateral, along), d1."""
    c0, c1 = np.asarray(c0, float), np.asarray(c1, float)
    r0, r1 = _ring(d0[0], d0[1], ch), _ring(d1[0], d1[1], ch)
    P0 = [c0 + R * a + T * b for (a, b) in r0]
    P1 = [c1 + R * a + T * b for (a, b) in r1]
    cm = (c0 + c1) / 2.0
    for k in range(8):
        k2 = (k + 1) % 8
        mid = (P0[k] + P0[k2] + P1[k] + P1[k2]) / 4.0 - cm
        mid[2] = 0.0
        soup.quad(P0[k], P0[k2], P1[k2], P1[k], mat, mid)
    if top_cap:
        soup.fan(P1, mat, [0, 0, 1])
    if bottom_cap:
        soup.fan(P0, mat, [0, 0, -1])


def extrude(soup, fr, poly, l0, l1, mat):
    """Extrude a convex (d, h) polygon along the travel direction from l0 to l1."""
    A = [_pt(fr, d, h, l0) for d, h in poly]
    B = [_pt(fr, d, h, l1) for d, h in poly]
    cen = (sum(A) + sum(B)) / (2.0 * len(poly))
    n = len(poly)
    for k in range(n):
        k2 = (k + 1) % n
        mid = (A[k] + A[k2] + B[k] + B[k2]) / 4.0 - cen
        soup.quad(A[k], A[k2], B[k2], B[k], mat, mid)
    soup.fan(A, mat, -fr["T"])
    soup.fan(B, mat, fr["T"])


def soup_box(soup, c, hw, hh, hd, R, T, mat):
    """Box centred at c with half sizes: lateral (R) hw, vertical hh, along (T) hd."""
    c = np.asarray(c, float)
    up = np.array([0, 0, 1.0])
    pts = {}
    for i, sx in enumerate((-1, 1)):
        for j, sy in enumerate((-1, 1)):
            for k, sz in enumerate((-1, 1)):
                pts[(i, j, k)] = c + R * (sx * hw) + T * (sy * hd) + up * (sz * hh)
    for axis in range(3):
        for sgn in (0, 1):
            o = [x for x in range(3) if x != axis]
            q = []
            for (a, b) in ((0, 0), (0, 1), (1, 1), (1, 0)):
                key = [0, 0, 0]
                key[axis] = sgn
                key[o[0]], key[o[1]] = a, b
                q.append(pts[tuple(key)])
            soup.quad(*q, mat, sum(q) / 4.0 - c)


def cable(soup, p0, p1, r, mat, sides=6):
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    u = p1 - p0
    L = np.linalg.norm(u)
    if L < 1e-6:
        return
    u /= L
    e1 = np.cross(u, [0, 0, 1.0])
    if np.linalg.norm(e1) < 1e-6:
        e1 = np.cross(u, [1.0, 0, 0])
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(u, e1)
    ring = [(math.cos(2 * math.pi * k / sides) * e1 + math.sin(2 * math.pi * k / sides) * e2) * r for k in range(sides)]
    for k in range(sides):
        k2 = (k + 1) % sides
        soup.quad(p0 + ring[k], p0 + ring[k2], p1 + ring[k2], p1 + ring[k], mat, (ring[k] + ring[k2]) / 2.0)
    soup.fan([p0 + q for q in ring], mat, -u)
    soup.fan([p1 + q for q in ring], mat, u)


# ----------------------------------------------------------------------------------------------------------------------
# bridges
def bridge_style(road, br):
    L = br["s1"] - br["s0"]
    h = br.get("deck_height_max", 5.0)
    if road.id == "HWY_EAST" and L > 300:
        return "cable"
    if h < 5.2 and L < 70:
        return "slab"
    return "box"


def bridge_layout(road, br):
    """Global, chunk-independent layout of one bridge: style, supports, pylons, depth parameters."""
    s0, s1 = float(br["s0"]), float(br["s1"])
    L = s1 - s0
    style = bridge_style(road, br)
    Wt = 2.0 * (road.B + PARAPET_W)
    lay = dict(style=style, s0=s0, s1=s1, L=L, Wt=Wt)
    if style == "cable":
        main = 200.0
        side = (L - main) / 2.0
        p1, p2 = s0 + side, s0 + side + main
        nap = 4
        approach = [s0 + side * k / nap for k in range(1, nap)] + [p2 + side * k / nap for k in range(1, nap)]
        lay.update(pylons=[p1, p2], piers=approach, supports=sorted([s0, s1, p1, p2] + approach), D0=2.0,
                   Wbox=min(0.5 * Wt + 1.0, 12.0), main=main)
    elif style == "slab":
        n = int(L // 22)
        piers = [s0 + L * k / (n + 1) for k in range(1, n + 1)]
        lay.update(pylons=[], piers=piers, supports=sorted([s0, s1] + piers), D0=0.6, Wbox=Wt)
    else:
        n = max(1, int(round(L / 28.0)))
        piers = [s0 + L * k / n for k in range(1, n)]
        span = L / n
        D0 = float(np.clip(0.035 * span + 0.03 * Wt, 0.75, 1.8))
        lay.update(pylons=[], piers=piers, supports=sorted([s0, s1] + piers), D0=D0, Wbox=float(np.clip(0.55 * Wt, 4.0, 12.0)))
    return lay


def _depth_fn(lay):
    """Soffit depth below the deck surface (m) as a function of s: shallow mid-span, haunched over the piers."""
    sp = np.array(lay["supports"])
    D0 = lay["D0"]
    style = lay["style"]
    gain = 0.25 if style == "cable" else 0.55

    def D(s):
        s = np.atleast_1d(np.asarray(s, float))
        if style == "slab":
            return np.full(s.shape, D0)
        i = np.clip(np.searchsorted(sp, s, "right") - 1, 0, len(sp) - 2)
        a, b = sp[i], sp[i + 1]
        fr = (s - a) / (b - a)
        wa = np.where(i > 0, 1.0, 0.25)
        wb = np.where(i < len(sp) - 2, 1.0, 0.25)
        hf = wa * (1 - fr) ** 3 + wb * fr ** 3
        out = D0 * (1.0 + gain * hf)
        if style == "cable":
            near = (s > lay["pylons"][0] - 1e-6) & (s < lay["pylons"][1] + 1e-6)
            out = np.where(near, D0, out)
        return out
    return D


def deck_profile(road, lay, D):
    """Closed deck loop with per-station soffit depth D (n_st,).  Returns the dict expected by ribbon()."""
    B = road.B
    pw, hp = PARAPET_W, PARAPET_H
    pr = road.profile()
    top = [i for i in range(len(pr["d"])) if abs(pr["d"][i]) <= B + 1e-6]
    surf = ASPH if road.surface == "asphalt" else CONC
    n_st = len(D)
    Wb = lay["Wbox"]
    style = lay["style"]
    d, h, zone, hard, mat = [], [], [], [], []
    ones = np.ones(n_st)
    low = -np.minimum(0.40, D - 0.2)

    def add(dv, hv, zn, hd, mt):
        d.append(float(dv))
        h.append(np.asarray(hv, float) * ones)
        zone.append(zn)
        hard.append(hd)
        mat.append(int(mt))

    add(-(B + pw), -D if style == "slab" else low, 0.33, True, BCON)        # outer face (edge goes up)
    add(-(B + pw), hp, 0.33, True, BCON)                                    # parapet top
    add(-B, hp, 0.33, True, BCON)                                           # parapet inner face
    for i in top:
        mt = int(pr["mat"][i])
        if mt in (GRAV, DIRT):
            mt = surf
        add(pr["d"][i], pr["h"][i], pr["zone"][i], bool(pr["hard"][i]), mt)
    mat[-1] = BCON                                                          # last top point: edge up the parapet inner face
    add(B, hp, 0.33, True, BCON)
    add(B + pw, hp, 0.33, True, BCON)
    if style == "slab":
        add(B + pw, -D, 0.33, True, BCON)            # closing edge back to the first point (-(B+pw), -D) is the soffit
    else:
        add(B + pw, low, 0.33, True, BCON)
        add(Wb / 2.0, -D, 0.0, True, BCON)
        add(-Wb / 2.0, -D, 0.0, True, BCON)
    H = np.stack(h, 1)
    return dict(d=np.array(d), h=H, zone=np.array(zone), hard=np.array(hard, bool), mat=np.array(mat, np.int16), closed=True)


def split_bridge(c):
    """Number of chunks a bridge piece is divided into (~200 m each for the long ones)."""
    L = c["s1"] - c["s0"]
    return max(1, int(math.ceil(L / 230.0)))


def build_bridge(plan, c):
    road = plan["roads"][c["road"]]
    br = c["meta"]
    lay = bridge_layout(road, br)
    a, b = c["s0"], c["s1"]
    first = abs(a - lay["s0"]) < 0.01
    last = abs(b - lay["s1"]) < 0.01
    Dfn = _depth_fn(lay)
    extra_st = [p for p in lay["piers"] + lay["pylons"] if a < p < b]
    st = road.stations(a, b, extra=extra_st, step=3.0)
    fr = road.at(st)
    D = Dfn(st)
    prof = deck_profile(road, lay, D)
    par = dict(P=road.P, lw=road.lw, med=road.med, Wt=lay["Wt"])
    mb = MB()
    ribbon(mb, fr, prof, par)
    soup = Soup()
    info = dict(piers=[], abutments=[], pylons=[], style=lay["style"], length=lay["L"], bridge_s0=lay["s0"], bridge_s1=lay["s1"])
    for sp in lay["piers"]:
        if a <= sp < b or (last and abs(sp - b) < 1e-6):
            _pier(plan, soup, road, lay, sp, float(Dfn(sp)[0]), info)
    if first:
        _abutment(plan, soup, road, lay, lay["s0"], -1, float(Dfn(lay["s0"])[0]), info)
    if last:
        _abutment(plan, soup, road, lay, lay["s1"], +1, float(Dfn(lay["s1"])[0]), info)
    for sp in lay["pylons"]:
        if a - 110.0 < sp < b + 110.0:
            _pylon(plan, soup, road, lay, sp, float(Dfn(sp)[0]), a, b, info)
    soup.into(mb)
    info["parapet"] = dict(lateral=[-(road.B + PARAPET_W / 2.0), road.B + PARAPET_W / 2.0], height=PARAPET_H)
    return mb, info


def _pier(plan, soup, road, lay, sp, Dp, info):
    fr = _frame(road, sp)
    Wt, Wb = lay["Wt"], lay["Wbox"]
    twin = Wt > 14.0
    dcols = [-0.23 * Wt, 0.23 * Wt] if twin else [0.0]
    Wc = min(Wb + 0.8, Wt - 0.5)
    cap_len = 2.2
    h_top = -(Dp + 0.12)
    cap_bot = h_top - 1.3
    poly = [(-Wc / 2, h_top), (Wc / 2, h_top), (Wc / 2, h_top - 0.65), (Wc * 0.5 - 1.2, cap_bot), (-(Wc * 0.5 - 1.2), cap_bot),
            (-Wc / 2, h_top - 0.65)]
    extrude(soup, fr, poly, -cap_len / 2, cap_len / 2, BCON)
    tops, grounds = [], []
    centres = []
    for dc in dcols:
        top_c = _pt(fr, dc, cap_bot + 0.15)
        zg = _terrain_min(plan, fr, [dc - 1.2, dc, dc + 1.2], [-1.0, 0.0, 1.0], top_c[2] - 8.0)
        H = top_c[2] - zg
        hw1, hd1 = 0.85 + 0.004 * H, 0.75 + 0.003 * H
        hw0, hd0 = hw1 + 0.55 + 0.012 * H, hd1 + 0.45 + 0.010 * H
        z_base = zg - 1.4
        fo = np.array([top_c[0], top_c[1], z_base])
        c1 = np.array([top_c[0], top_c[1], top_c[2]])
        prism(soup, fo, (hw0 + 0.7, hd0 + 0.7), fo + np.array([0, 0, 1.9]), (hw0 + 0.7, hd0 + 0.7), fr["R"], fr["T"], BCON, ch=0.0)
        prism(soup, fo + np.array([0, 0, 1.9]), (hw0, hd0), c1, (hw1, hd1), fr["R"], fr["T"], BCON, ch=0.14, top_cap=False)
        tops.append(top_c[2])
        grounds.append(zg)
        centres.append((top_c, H))
    if twin and len(centres) == 2 and min(h for _, h in centres) > 14.0:
        (ca, Ha), (cb, Hb) = centres
        zm = min(ca[2] - 0.5 * Ha, cb[2] - 0.5 * Hb)
        p0 = np.array([ca[0], ca[1], zm])
        p1 = np.array([cb[0], cb[1], zm])
        soup_box(soup, (p0 + p1) / 2.0, np.linalg.norm(p1 - p0) / 2.0, 0.55, 0.9, fr["R"], fr["T"], BCON)
    info["piers"].append(dict(s=sp, pos_ue=[float(fr["C"][0]), float(-fr["C"][1]), float(fr["C"][2])], ground=float(min(grounds)),
                              height=float(max(tops) - min(grounds))))


def _abutment(plan, soup, road, lay, sa, side, Da, info):
    """Abutment at the bridge end `sa`; side = -1 start (road continues towards -s), +1 end."""
    fr = _frame(road, sa)
    wab = lay["Wt"] / 2.0 + 0.3
    back = 2.8
    l_out = side * back
    zg = _terrain_min(plan, fr, [-wab, -wab / 2, 0, wab / 2, wab], [0.0, l_out / 2, l_out], fr["C"][2] - 6.0)
    z_bot = min(zg - 1.0, fr["C"][2] - Da - 1.2)
    l0, l1 = -0.35 * side, l_out
    lo, hi = min(l0, l1), max(l0, l1)
    top_h = -Da
    corners = {}
    for sx in (-1, 1):
        for ll in (lo, hi):
            p = _pt(fr, sx * wab, top_h, ll)
            corners[(sx, ll)] = (p, np.array([p[0], p[1], z_bot]))
    cen = sum(p for pair in corners.values() for p in pair) / 8.0
    (tA, bA), (tB, bB), (tC, bC), (tD, bD) = (corners[(-1, lo)], corners[(-1, hi)], corners[(1, lo)], corners[(1, hi)])
    for q in [(tA, tB, tD, tC), (bA, bC, bD, bB), (tA, bA, bB, tB), (tC, tD, bD, bC), (tA, tC, bC, bA), (tB, bB, bD, tD)]:
        soup.quad(*q, BCON, sum(q) / 4.0 - cen)
    # wing walls: flare outwards, retaining the embankment behind the bridge end
    for sx in (-1, 1):
        d0 = sx * (wab - 0.25)
        near = _pt(fr, d0, 0.0, l_out)
        ang = math.radians(22.0)
        far_dir = fr["T"] * side * math.cos(ang) + fr["R"] * sx * math.sin(ang)
        far = near + far_dir * 7.5
        zf = _terrain(plan, far[0], far[1], near[2] - 2.0)
        top_near = fr["C"][2] - d0 * math.tan(fr["bank"]) + PARAPET_H
        top_far = min(max(zf + 0.35, fr["C"][2] - 1.5), top_near)
        zbw = min(zg, zf) - 0.8
        th = 0.28
        nrm = np.cross(far_dir, [0, 0, 1.0])
        nrm /= np.linalg.norm(nrm)
        pts = {}
        for (nm, p, zt) in (("n", near, top_near), ("f", far, top_far)):
            for sg in (-1, 1):
                q = p + nrm * (sg * th)
                pts[(nm, sg, "t")] = np.array([q[0], q[1], zt])
                pts[(nm, sg, "b")] = np.array([q[0], q[1], zbw])
        cw = sum(pts.values()) / len(pts)
        for q in [(("n", -1, "t"), ("f", -1, "t"), ("f", -1, "b"), ("n", -1, "b")),
                  (("n", 1, "t"), ("n", 1, "b"), ("f", 1, "b"), ("f", 1, "t")),
                  (("n", -1, "t"), ("n", 1, "t"), ("f", 1, "t"), ("f", -1, "t")),
                  (("n", -1, "b"), ("f", -1, "b"), ("f", 1, "b"), ("n", 1, "b")),
                  (("f", -1, "t"), ("f", 1, "t"), ("f", 1, "b"), ("f", -1, "b")),
                  (("n", -1, "t"), ("n", -1, "b"), ("n", 1, "b"), ("n", 1, "t"))]:
            qq = [pts[k] for k in q]
            soup.quad(*qq, BCON, sum(qq) / 4.0 - cw)
    info["abutments"].append(dict(s=sa, side=side, pos_ue=[float(fr["C"][0]), float(-fr["C"][1]), float(fr["C"][2])]))


def _pylon(plan, soup, road, lay, sp, Dp, a, b, info):
    """Cable-stayed pylon: A-frame legs outside the deck, cross beams, two cable fans.  The pylon body belongs to the chunk that
    contains `sp`; every cable belongs to the chunk that contains its deck anchor."""
    fr = _frame(road, sp)
    Wt = lay["Wt"]
    Hp = 44.0
    lat0 = Wt / 2.0 + 1.7
    lat1 = lat0 * 0.60
    zdeck = fr["C"][2]
    if a - 1e-6 <= sp < b + 1e-6:
        for sx in (-1, 1):
            p_base = _pt(fr, sx * lat0, 0.0)
            zg = _terrain_min(plan, fr, [sx * lat0 - 1.5, sx * lat0, sx * lat0 + 1.5], [-1.5, 0, 1.5], zdeck - 20.0)
            c0 = np.array([p_base[0], p_base[1], zg - 1.8])
            c1 = np.array([p_base[0], p_base[1], zdeck - Dp - 0.2])
            prism(soup, c0, (3.2, 2.9), c0 + np.array([0, 0, 2.2]), (3.2, 2.9), fr["R"], fr["T"], BCON, ch=0.0)
            prism(soup, c0 + np.array([0, 0, 2.2]), (2.0, 1.8), c1, (1.2, 1.5), fr["R"], fr["T"], BCON, ch=0.2, top_cap=False)
            top_xy = _pt(fr, sx * lat1, 0.0)
            cb = np.array([top_xy[0], top_xy[1], zdeck + Hp])
            prism(soup, c1, (1.2, 1.5), cb, (0.75, 0.95), fr["R"], fr["T"], BCON, ch=0.18, top_cap=True)
        for (zr, thk, hd) in ((-(Dp + 0.85), 1.5, 2.2), (0.42 * Hp, 1.1, 1.4), (0.97 * Hp, 1.4, 1.7)):
            lat = lat0 + (lat1 - lat0) * max(0.0, zr / Hp)
            ctr = np.array([fr["C"][0], fr["C"][1], zdeck + zr])
            soup_box(soup, ctr, lat, thk / 2.0, hd / 2.0, fr["R"], fr["T"], BCON)
        info["pylons"].append(dict(s=sp, height=Hp, pos_ue=[float(fr["C"][0]), float(-fr["C"][1]), float(zdeck)]))
    N = 7
    for side_dir in (-1, 1):
        for k in range(N):
            sd = sp + side_dir * (16.0 + 14.0 * k)
            if not (a <= sd < b):
                continue
            fr_d = _frame(road, sd)
            zr = (0.50 + 0.45 * k / (N - 1)) * Hp
            r_lat = lat0 + (lat1 - lat0) * (zr / Hp)
            for sx in (-1, 1):
                p_pyl = _pt(fr, sx * r_lat, zr)
                p_deck = _pt(fr_d, sx * (road.B + PARAPET_W + 0.12), 0.35)
                cable(soup, p_pyl, p_deck, 0.11, BSTL)
                soup_box(soup, p_deck - np.array([0, 0, 0.35]), 0.28, 0.5, 0.28, fr_d["R"], fr_d["T"], BSTL)


# ----------------------------------------------------------------------------------------------------------------------
# tunnels
def _arch_points(w, hw, b, n=18):
    """Half ellipse (semi axes w lateral, b vertical) from the left springing to the right one, left -> right: [(d, h)...]."""
    return [(w * math.cos(math.pi - math.pi * k / n), hw + b * math.sin(math.pi - math.pi * k / n)) for k in range(n + 1)]


def tunnel_dims(road):
    w_in = road.B + 0.9
    return dict(w_in=w_in, w_out=w_in + 0.9, hk=0.18, hw=2.3, b=3.6, floor_bot=-0.45)


def _ray_hit(c0, u, poly):
    best = None
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        e = (q[0] - p[0], q[1] - p[1])
        den = u[0] * e[1] - u[1] * e[0]
        if abs(den) < 1e-12:
            continue
        w = (p[0] - c0[0], p[1] - c0[1])
        t = (w[0] * e[1] - w[1] * e[0]) / den
        sg = (w[0] * u[1] - w[1] * u[0]) / den
        if t > 1e-9 and -1e-9 <= sg <= 1 + 1e-9:
            if best is None or t < best:
                best = t
    return best


def build_tunnel(plan, c):
    road = plan["roads"][c["road"]]
    a, b = c["s0"], c["s1"]
    dm = tunnel_dims(road)
    w_in, w_out, hk, hw, bb, fb = dm["w_in"], dm["w_out"], dm["hk"], dm["hw"], dm["b"], dm["floor_bot"]
    st = road.stations(a, b, step=3.0)
    fr = road.at(st)
    mb = MB()
    par = dict(P=road.P, lw=road.lw, med=road.med, Wt=2.0 * w_out)
    pr = road.profile()
    top = [i for i in range(len(pr["d"])) if abs(pr["d"][i]) <= road.B + 1e-6]
    fd, fh, fz, fhard, fmat = [], [], [], [], []

    def add(dv, hv, zn, hd, mt):
        fd.append(float(dv)); fh.append(float(hv)); fz.append(zn); fhard.append(hd); fmat.append(int(mt))

    crown_B = float(_crown(road, road.B))
    add(-w_in, hk, 0.5, True, CURB)                 # walkway top
    add(-road.B, hk, 0.5, True, CURB)               # kerb face
    add(-road.B, crown_B, 0.66, True, ASPH)
    for i in top[1:-1]:
        mt = int(pr["mat"][i])
        add(pr["d"][i], pr["h"][i], pr["zone"][i], bool(pr["hard"][i]), ASPH if mt in (GRAV, DIRT) else mt)
    add(road.B, crown_B, 0.66, True, CURB)
    add(road.B, hk, 0.5, True, CURB)
    add(w_in, hk, 0.5, True, CONC)
    add(w_in, fb, 0.0, True, CONC)
    add(-w_in, fb, 0.0, True, CONC)
    floor = dict(d=np.array(fd), h=np.array(fh), zone=np.array(fz), hard=np.array(fhard, bool), mat=np.array(fmat, np.int16), closed=True)
    ribbon(mb, fr, floor, par)
    # inner liner (normals inward -> traverse right to left)
    arch = [(-w_in, hk), (-w_in, hw)] + _arch_points(w_in, hw, bb)[1:-1] + [(w_in, hw), (w_in, hk)]
    inner = arch[::-1]
    prof_in = dict(d=np.array([p[0] for p in inner]), h=np.array([p[1] for p in inner]), zone=np.zeros(len(inner)),
                   hard=np.zeros(len(inner), bool), mat=np.full(len(inner), TWAL, np.int16), closed=False)
    ribbon(mb, fr, prof_in, par)
    # outer shell + bottom (closed loop, outward normals)
    outer = [(-w_out, fb), (-w_out, hw)] + _arch_points(w_out, hw, bb + 0.9)[1:-1] + [(w_out, hw), (w_out, fb)]
    prof_out = dict(d=np.array([p[0] for p in outer]), h=np.array([p[1] for p in outer]), zone=np.zeros(len(outer)),
                    hard=np.zeros(len(outer), bool), mat=np.full(len(outer), TWAL, np.int16), closed=True)
    ribbon(mb, fr, prof_out, par)
    # light strips: two emissive bands on the vault, facing the road
    lamps = []
    for sgn in (-1, 1):
        th = math.radians(90.0 + sgn * 36.0)
        cx, cy = w_in * math.cos(th), hw + bb * math.sin(th)
        tx, ty = -w_in * math.sin(th), bb * math.cos(th)
        ln = math.hypot(tx, ty)
        tx, ty = tx / ln, ty / ln
        nx, ny = -math.cos(th) / w_in, -math.sin(th) / bb
        nl = math.hypot(nx, ny)
        nx, ny = nx / nl, ny / nl
        off = 0.045
        pts = [(cx + tx * 0.2 + nx * off, cy + ty * 0.2 + ny * off), (cx - tx * 0.2 + nx * off, cy - ty * 0.2 + ny * off)]
        pts.sort(key=lambda p: -p[0])                       # d decreasing -> the strip faces down / inwards
        lp = dict(d=np.array([p[0] for p in pts]), h=np.array([p[1] for p in pts]), zone=np.zeros(2), hard=np.zeros(2, bool),
                  mat=np.full(2, TLIT, np.int16), closed=False)
        ribbon(mb, fr, lp, par)
        lamps.append((cx + nx * 0.12, cy + ny * 0.12))
    lamp_list = []
    s_l = a + 6.0
    while s_l < b - 5.0:
        f = _frame(road, s_l)
        for (ld, lh) in lamps:
            p = _pt(f, ld, lh)
            lamp_list.append([float(p[0]), float(-p[1]), float(p[2])])
        s_l += 12.0
    soup = Soup()
    info = dict(length=b - a, lights_ue=lamp_list, portals=[], inner_half_width=w_in, crown_height=hw + bb, tunnel_s0=a, tunnel_s1=b)
    for (sp, face) in ((a, -1), (b, +1)):
        _portal(plan, soup, road, dm, sp, face, info)
    soup.into(mb)
    return mb, info


def _portal(plan, soup, road, dm, sp, face, info):
    """Head-wall block at the foot of the portal cutting, facing `face` * T (-1 looks towards -T at the start portal, +1 at the end).

    The heightmap closes the road with a 1:0.6 slope; the Landscape is a surface (no hole), so the wall stands IN FRONT of the slope:
    a vertical front face with the arch opening, a horizontal ledge on top and a body that runs back until it is buried in the hill.
    The Landscape needs a visibility hole where its surface crosses the tube mouth (`holes` in the chunk record)."""
    fr = _frame(road, sp)
    w_in, w_out, hk, hw, bb, fb = dm["w_in"], dm["w_out"], dm["hk"], dm["hw"], dm["b"], dm["floor_bot"]
    H_top = hw + bb + 0.9 + 1.4
    zc = fr["C"][2]
    Tn = fr["T"] * (-face)                         # direction INTO the hill
    # lateral half width: until the trench side slope reaches the wall top (plus margin), sampled on the wall plane
    Wh = w_out + 1.5
    for dd in np.arange(w_out, 18.0, 0.5):
        zl = _terrain(plan, *(_pt(fr, -dd, 0.0)[:2]), zc + 99.0) - (zc + dd * math.tan(fr["bank"]))
        zr = _terrain(plan, *(_pt(fr, dd, 0.0)[:2]), zc + 99.0) - (zc - dd * math.tan(fr["bank"]))
        if min(zl, zr) >= H_top:
            Wh = dd + 0.6
            break
        Wh = dd + 0.6
    # depth: until the centre line of the hill reaches the wall top
    thick = 12.0
    for l in np.arange(1.0, 14.0, 0.5):
        p = _pt(fr, 0.0, 0.0, 0.0) + Tn * l
        if _terrain(plan, p[0], p[1], zc + 99.0) - zc >= H_top + 0.3:
            thick = l + 1.0
            break
    thick = float(min(max(thick, 3.0), 12.0))
    # extent of the Landscape surface crossing the tube mouth (for the visibility hole)
    l_hole = 6.0
    for l in np.arange(0.5, 14.0, 0.5):
        p = _pt(fr, 0.0, 0.0, 0.0) + Tn * l
        if _terrain(plan, p[0], p[1], zc + 99.0) - zc >= hw + bb + 0.9 + 0.6:
            l_hole = l + 1.0
            break
    arch = [(-w_in, hk), (-w_in, hw)] + _arch_points(w_in, hw, bb)[1:-1] + [(w_in, hw), (w_in, hk)]
    opening = list(arch)
    for k in range(1, 6):
        opening.append((w_in - (2 * w_in) * k / 6.0, hk))              # floor line, back to the left (closed, clockwise)
    outline = [(-Wh, fb), (-Wh, H_top), (Wh, H_top), (Wh, fb)]
    c0 = (0.0, hk + 1.2)
    angs = sorted(set(round(math.atan2(p[1] - c0[1], p[0] - c0[0]), 9) for p in opening + outline), reverse=True)
    ring = []
    for ang in angs:
        u = (math.cos(ang), math.sin(ang))
        t_in = _ray_hit(c0, u, opening)
        t_out = _ray_hit(c0, u, outline)
        if t_in is None or t_out is None:
            continue
        ring.append(((c0[0] + u[0] * t_in, c0[1] + u[1] * t_in), (c0[0] + u[0] * t_out, c0[1] + u[1] * t_out)))
    n = len(ring)
    nrm = fr["T"] * face
    for i in range(n):
        (o0, q0), (o1, q1) = ring[i], ring[(i + 1) % n]
        soup.quad(_pt(fr, o0[0], o0[1]), _pt(fr, q0[0], q0[1]), _pt(fr, q1[0], q1[1]), _pt(fr, o1[0], o1[1]), TWAL, nrm)
    # stone voussoir ring: separate blocks around the arch and the springings (varying width / projection, 4 cm joints),
    # a wider keystone pair at the crown; nothing across the floor line
    def hsh(i, k):
        return (math.sin(i * 12.9898 + k * 78.233 + sp * 0.37) * 43758.5453) % 1.0

    na = len(arch) - 1
    fwdv = fr["T"] * face
    crown_v = min(range(1, na), key=lambda k: abs(arch[k][0]) + (0.0 if arch[k][1] > hw + 0.5 else 99.0))    # crown vertex
    for i in range(na):
        o0, o1 = arch[i], arch[i + 1]
        ln = math.hypot(o1[0] - o0[0], o1[1] - o0[1])
        if ln < 1e-6:
            continue
        ux, uy = (o1[0] - o0[0]) / ln, (o1[1] - o0[1]) / ln
        gap = 0.02
        a0 = (o0[0] + ux * gap, o0[1] + uy * gap)
        a1 = (o1[0] - ux * gap, o1[1] - uy * gap)
        keystone = i in (crown_v - 1, crown_v)
        wdt = 1.25 if keystone else 0.72 + 0.26 * hsh(i, 0)
        prj = 0.42 if keystone else 0.16 + 0.15 * hsh(i, 1)
        corners = []
        for (pp, oo) in ((a0, o0), (a1, o1)):
            vx, vy = oo[0] - c0[0], oo[1] - c0[1]
            vl = math.hypot(vx, vy)
            corners.append((pp, (pp[0] + vx / vl * wdt, pp[1] + vy / vl * wdt)))
        (A0, B0), (A1, B1) = corners
        base = [_pt(fr, A0[0], A0[1]), _pt(fr, A1[0], A1[1]), _pt(fr, B1[0], B1[1]), _pt(fr, B0[0], B0[1])]
        topq = [p + fwdv * prj for p in base]
        cen_b = (sum(base) + sum(topq)) / 8.0
        for q in ([topq[0], topq[1], topq[2], topq[3]],                    # front
                  [base[0], base[1], topq[1], topq[0]],                    # inner reveal
                  [base[3], base[2], topq[2], topq[3]],                    # outer rim
                  [base[0], base[3], topq[3], topq[0]],                    # side joint 0
                  [base[1], base[2], topq[2], topq[1]]):                   # side joint 1
            soup.quad(*q, TWAL, sum(q) / 4.0 - cen_b)
    # body of the block: the outline extruded into the hill (top ledge + both sides + bottom), buried by the hillside further in
    back = Tn * thick
    cen = _pt(fr, 0.0, hk + 1.5) + Tn * (thick / 2.0)
    m = len(outline)
    for i in range(m - 1):                           # no bottom face: it would cut through the tube / floor on a graded road
        p0, p1 = outline[i], outline[(i + 1) % m]
        A0, A1 = _pt(fr, p0[0], p0[1]), _pt(fr, p1[0], p1[1])
        soup.quad(A0, A1, A1 + back, A0 + back, TWAL, (A0 + A1 + A0 + back + A1 + back) / 4.0 - cen)
    p_c = _pt(fr, 0.0, 0.0)
    ang = math.degrees(math.atan2(-fr["T"][1], fr["T"][0])) % 360.0
    hole_c = p_c + Tn * (l_hole / 2.0)
    info["portals"].append(dict(s=sp, face=face, pos_ue=[float(fr["C"][0]), float(-fr["C"][1]), float(fr["C"][2])],
                                heading_deg=float(ang), wall_half_width=float(Wh), wall_height=float(H_top),
                                body_depth=float(thick)))
    info.setdefault("landscape_holes", []).append(
        dict(centre_ue_m=[float(hole_c[0]), float(-hole_c[1]), float(zc + 3.0)], heading_deg=float(ang),
             length_m=float(l_hole), width_m=float(2 * (w_in + 0.6)), note="Landscape visibility hole: surface crosses the tunnel mouth"))
