"""lane14_shipwreck.py - sunken 28 m coastal freighter wreck (props/shipwreck.glb), hero asset, <= 2500 tris.

Built in an upright SHIP frame (+X starboard, +Y bow, +Z up, keel at z=0, deck ZD) then rolled ROLL deg onto its starboard bilge and
dropped so the lowest point sits ~0.2 m into the seabed (z=0 = seabed).  Debris that lies on the seabed is added in WORLD frame after the roll.
Single `Body` mesh (double sided materials: one skin shows from both sides) + empties TreasureSpot_1..3, DiverEntry.
Run:  exec(open(<this file>).read(), globals())   (gta_lib.py + lane14_lib.py loaded first)
"""
import random
import math
from mathutils import Vector, Matrix

ROLL = 38.0
B = 3.55           # half beam
ZD = 2.9           # main deck
ZF = 4.7           # forecastle deck
rng = random.Random(1407)

# y, half-width factor, keel lift, gunwale z, rake (forward lean of the top at the bow)
ST = [(-14.0, .60, .60, 3.2, 0.0),
      (-12.5, .80, .25, 3.3, 0.0),
      (-10.0, .96, .00, 3.4, 0.0),
      (-7.0, 1.0, .0, 3.4, 0.0),
      (-3.5, 1.0, .0, 3.4, 0.0),
      (0.5, 1.0, .0, 3.4, 0.0),
      (3.5, 1.0, .0, 3.4, 0.0),
      (6.2, .98, .0, 3.5, 0.0),
      (9.0, .84, .2, 4.9, 0.1),
      (11.0, .62, .7, 5.3, 0.3),
      (12.6, .38, 1.3, 5.6, 0.6),
      (13.7, .16, 1.9, 5.9, 1.0)]
SEC = [(-1, 1), (-1, .82), (-1, .5), (-.85, .18), (-.5, .02), (0, 0), (.5, .02), (.85, .18), (1, .5), (1, .82), (1, 1)]
NS = len(SEC)
SEGMAT = ["WreckWhite", "WreckTeal", "WreckBarn", "WreckRedLead", "WreckRedLead", "WreckRedLead", "WreckRedLead", "WreckBarn", "WreckTeal", "WreckWhite"]
HOLES = {(4, 2), (4, 1), (5, 1), (5, 2), (5, 3), (6, 1), (6, 2), (1, 1), (2, 2), (2, 1)}     # (gap, segment) hull plates that are torn away
SW = {"WreckTeal": "WreckRust", "WreckWhite": "WreckRust", "WreckBarn": "WreckAlgae", "WreckRedLead": "WreckBarn"}


def seg_mat(si, seg):
    """coherent colour bands: red-lead bottom, barnacle belt, teal topsides, white gunwale strake; big patches of rust / algae"""
    base = SEGMAT[seg]
    side = 0 if seg < 5 else 1
    k = min(seg, NS - 2 - seg)
    r = random.Random((si // 2) * 53 + k * 17 + side * 7 + 3).random()
    if base == "WreckTeal" and r < .34: return "WreckRust"
    if base == "WreckWhite" and r < .30: return "WreckRust"
    if base == "WreckBarn" and r < .30: return "WreckAlgae"
    if base == "WreckRedLead" and r < .18: return "WreckBarn"
    return base


JIT = {}
for _si in range(len(ST)):
    for _pi in range(NS):
        j = Vector((rng.uniform(-.07, .07), rng.uniform(-.05, .05), rng.uniform(-.06, .06)))
        if _pi == 5:
            j.x = 0.0
        JIT[(_si, _pi)] = j


def hull_ring(si):
    y, wf, kz, gz, rk = ST[si]
    out = []
    for pi, (px, hz) in enumerate(SEC):
        p = Vector((px * B * wf, y + hz * rk, kz + hz * (gz - kz))) + JIT[(si, pi)]
        out.append(p)
    return out


def wf_at(y):
    for i in range(len(ST) - 1):
        if ST[i][0] <= y <= ST[i + 1][0]:
            t = (y - ST[i][0]) / (ST[i + 1][0] - ST[i][0])
            return ST[i][1] * (1 - t) + ST[i + 1][1] * t
    return ST[-1][1]


def wall_x(b, x, s, y0, y1, bands, holes, t=0.12, rev="WreckRustDk"):
    """wall on the plane x (outer side s=+1/-1), u = y, bands = [(z0, z1, mat)]; holes (ya, yb, za, zb) with reveals"""
    for (za, zb, m) in bands:
        hs = [(h[0], h[1], max(h[2], za), min(h[3], zb)) for h in holes if h[3] > za and h[2] < zb]
        for r in rects_with_holes(y0, y1, za, zb, hs):
            b.xq(x, r[0], r[1], r[2], r[3], s, m)
    xi = x - s * t
    xa, xb = min(x, xi), max(x, xi)
    for (ya, yb, za, zb) in holes:
        b.yq(ya, xa, xb, za, zb, 1, rev)
        b.yq(yb, xa, xb, za, zb, -1, rev)
        b.zq(za, xa, xb, ya, yb, 1, rev)
        b.zq(zb, xa, xb, ya, yb, -1, rev)


def wall_y(b, y, s, x0, x1, bands, holes, t=0.12, rev="WreckRustDk"):
    for (za, zb, m) in bands:
        hs = [(h[0], h[1], max(h[2], za), min(h[3], zb)) for h in holes if h[3] > za and h[2] < zb]
        for r in rects_with_holes(x0, x1, za, zb, hs):
            b.yq(y, r[0], r[1], r[2], r[3], s, m)
    yi = y - s * t
    ya_, yb_ = min(y, yi), max(y, yi)
    for (xa, xb, za, zb) in holes:
        b.xq(xa, ya_, yb_, za, zb, 1, rev)
        b.xq(xb, ya_, yb_, za, zb, -1, rev)
        b.zq(za, xa, xb, ya_, yb_, 1, rev)
        b.zq(zb, xa, xb, ya_, yb_, -1, rev)


def bent_plate(b, p, q, d, ang, mat, back=False):
    """flat plate hinged on edge p->q, extending along direction d (unit, roughly perpendicular to the edge), bent by ang deg about the edge"""
    p, q, d = Vector(p), Vector(q), Vector(d)
    ax = (q - p).normalized()
    R = Matrix.Rotation(math.radians(ang), 3, ax)
    d2 = R @ d
    b.pq([p, q, q + d2, p + d2], d2.cross(ax), mat)
    return q + d2


def post_run(b, pts, h=0.8, post="WreckSteel", rail="WreckRustDk"):
    for p in pts:
        b.cyl((p[0], p[1], p[2] + h / 2), 0.035, h, 3, post, caps="t")
    for a, c in zip(pts[:-1], pts[1:]):
        for hh in (h, h * 0.5):
            A = Vector((a[0], a[1], a[2] + hh)); C = Vector((c[0], c[1], c[2] + hh))
            side = (C - A).cross(Vector((0, 0, 1)))
            b.pq([A, C, C + Vector((0, 0, -0.045)), A + Vector((0, 0, -0.045))], side, rail)
            hs = (C - A).cross(side).normalized() * 0.0
            sd = side.normalized() * 0.03
            b.pq([A - sd, C - sd, C + sd, A + sd], (0, 0, 1), rail)


def build():
    A = A14("shipwreck", 0, "GTA_GODOT/Nature", spacing=60.0)
    b = HB("shipwreck_body")

    # ======================================================= hull shell =======================================================
    rings = [hull_ring(si) for si in range(len(ST))]
    # dents / collapsed gunwale around the breach
    for si, dx, dz in ((4, 0.30, -0.10), (5, 0.45, -0.25), (6, 0.35, -0.15), (7, 0.18, -0.05)):
        for pi in (1, 2, 3):
            rings[si][pi] += Vector((dx * (1.0 if pi != 3 else 0.5), 0, dz * (1.2 if pi == 1 else 0.6)))
    rings[5][0] += Vector((0.9, 0.0, -0.9))
    rings[6][0] += Vector((0.5, 0.0, -0.55))
    rings[4][0] += Vector((0.35, 0.0, -0.3))
    rings[1][1] += Vector((0.2, 0, -0.1))
    for si in range(len(ST) - 1):
        cen = sum(rings[si] + rings[si + 1], Vector()) / (2 * NS)
        for seg in range(NS - 1):
            if (si, seg) in HOLES:
                continue
            pts = [rings[si][seg], rings[si][seg + 1], rings[si + 1][seg + 1], rings[si + 1][seg]]
            b.po(pts, cen, seg_mat(si, seg))
    # barnacle crust: tiny 3-sided cones scattered on the port belt / bilge
    brng = random.Random(77)
    for si in range(len(ST) - 1):
        cen = sum(rings[si] + rings[si + 1], Vector()) / (2 * NS)
        for seg in (2, 3, 1):
            if (si, seg) in HOLES or brng.random() > (0.62 if seg != 1 else 0.28):
                continue
            q = [rings[si][seg], rings[si][seg + 1], rings[si + 1][seg + 1], rings[si + 1][seg]]
            for _k in range(2 if seg != 1 else 1):
                u, v = brng.uniform(.2, .8), brng.uniform(.2, .8)
                pt = (q[0] * (1 - u) + q[1] * u) * (1 - v) + (q[3] * (1 - u) + q[2] * u) * v
                nrm = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
                if nrm.dot(pt - cen) < 0:
                    nrm = -nrm
                t1 = (q[1] - q[0]).normalized()
                t2 = nrm.cross(t1)
                rr = brng.uniform(.10, .17)
                base = [pt + (t1 * math.cos(a) + t2 * math.sin(a)) * rr for a in (0.3, 0.3 + 2.094, 0.3 + 4.189)]
                apex = pt + nrm * rr * 1.1
                for i in range(3):
                    b.pq([base[i], base[(i + 1) % 3], apex], nrm + (pt - cen).normalized() * 0.2, "WreckBarnLt")
    b.pq(rings[0], (0, -1, 0), "WreckTealDk")                  # transom
    b.pq(rings[-1], (0, 1, 0), "WreckTealDk")                  # stem plate

    # ribs (frames) where the plating is gone: flanges standing inward from the hull skin
    def rib(r, segs, depth=0.2, th=0.07, mat="WreckRustDk"):
        cz = sum(p.z for p in r) / len(r)
        for sg in segs:
            a, c = r[sg], r[sg + 1]
            mid = (a + c) / 2
            inn = Vector((-mid.x, 0, cz - mid.z))
            inn.normalize()
            a2, c2 = a + inn * depth, c + inn * depth
            yv = Vector((0, th, 0))
            b.pq([a, c, c2, a2], Vector((0, 1, 0)), mat)
            b.pq([a2, c2, c2 + yv, a2 + yv], inn, mat)
    for si in (3, 4, 5, 6, 7):
        r = rings[si]
        rib(r, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] if si in (4, 6) else [0, 1, 2, 3, 4, 5, 8, 9] if si == 5 else [2, 3, 4] if si == 3 else [0, 1, 2, 3, 4])
    for si in (4, 5, 6):
        r = [(rings[si][k] + rings[si + 1][k]) / 2 for k in range(NS)]
        rib(r, [1, 2, 3, 4] if si != 5 else [0, 1, 2, 3, 4, 5])
    # keel + stringers
    for si in range(len(ST) - 2):
        b.pq([rings[si][5] + Vector((-0.08, 0, 0.02)), rings[si + 1][5] + Vector((-0.08, 0, 0.02)), rings[si + 1][5] + Vector((-0.08, 0, 0.35)), rings[si][5] + Vector((-0.08, 0, 0.35))], (1, 0, 0), "WreckRustDk")

    # curled / hanging hull plates at the breach edge
    bent_plate(b, rings[4][2], rings[4][3], (0, 1, 0), -52, "WreckBarn")
    pp = bent_plate(b, rings[7][1], rings[7][2], (0, -1, 0), 48, "WreckTeal")
    bent_plate(b, rings[3][1] + Vector((0.0, 0, 0.0)), rings[3][2], (0, 1, 0), -34, "WreckTeal")
    bent_plate(b, rings[2][2], rings[2][3], (0, 1, 0), -40, "WreckBarn")

    # ======================================================= decks ============================================================
    def deck(ys, z, skip, planks, hx=2.1):
        for gi in range(len(ys) - 1):
            y0, y1 = ys[gi], ys[gi + 1]
            h0, h1 = B * wf_at(y0) - 0.05, B * wf_at(y1) - 0.05
            strips = [(-1, -h0, -hx, -h1, -hx), (0, -hx, hx, -hx, hx), (1, hx, h0, hx, h1)]
            for (si_, xa0, xa1, xb0, xb1) in strips:
                if skip(y0, si_):
                    continue
                # xa0->xa1 at y0, xb0->xb1 at y1
                m = planks[(gi + si_ + 1) % len(planks)]
                b.pq([(xa0, y0, z), (xa1, y0, z), (xb1, y1, z), (xb0, y1, z)], (0, 0, 1), m)
    ysA = [-13.9, -12.5, -10.5, -7.0, -3.5, 0.5, 6.2, 8.6]

    def skip_main(y0, s):
        if y0 == -12.5 and s in (0, 1):
            return True                       # engine room open
        if y0 == 0.5 and s in (0, 1):
            return True                       # hold open (+ torn port strip)
        if y0 == -3.5 and s == 1:
            return True
        return False
    deck(ysA, ZD, skip_main, ["WreckDeck", "WreckDeckDk", "WreckDeck", "WreckAlgae"])
    ysF = [8.6, 11.0, 13.2]
    deck(ysF, ZF, lambda y0, s: (y0 == 11.0 and s == -1), ["WreckDeckDk", "WreckDeck"], hx=1.2)

    # forecastle bulkhead (y = 8.6) with a doorway, front face of the hold
    wall_y(b, 8.6, -1, -B * wf_at(8.6) + .05, B * wf_at(8.6) - .05, [(ZD, ZF, "WreckTeal")], [(-0.5, 0.5, ZD, ZD + 1.65)])
    # windlass + bitts on the forecastle
    b.cyl((0.0, 11.4, ZF + 0.42), 0.26, 1.3, 6, "WreckSteel", axis="X", caps="bt")
    b.cyl((-0.55, 11.4, ZF + 0.18), 0.16, 0.36, 6, "WreckRustDk", caps="t")
    b.cyl((0.55, 11.4, ZF + 0.18), 0.16, 0.36, 6, "WreckRustDk", caps="t")
    for sx in (-1.0, 1.0):
        b.cyl((sx * 0.6, 12.4, ZF + 0.3), 0.1, 0.6, 5, "WreckSteel", caps="t")

    # ======================================================= cargo hold =========================================================
    HY0, HY1, HX = 0.5, 6.2, 2.1
    hf = 0.75                                                    # hold floor
    fw = B * 0.82
    b.pq([(-fw, HY0, hf), (fw, HY0, hf), (fw, HY1, hf), (-fw, HY1, hf)], (0, 0, 1), "WreckDeckDk")
    for yy, sg in ((HY0, 1), (HY1, -1)):                          # athwartships bulkheads, hold side
        b.pq([(-B * .96, yy, hf), (B * .96, yy, hf), (B * .96, yy, ZD), (-B * .96, yy, ZD)], (0, sg, 0), "WreckTealDk")
    # hatch coaming round the opening
    ch = 0.42
    b.abox(-HX - .1, -HX, HY0, HY1, ZD, ZD + ch, "WreckRust", "-z")
    b.abox(HX, HX + .1, HY0, HY1, ZD, ZD + ch, "WreckRust", "-z")
    b.abox(-HX, HX, HY1, HY1 + .1, ZD, ZD + ch, "WreckRust", "-z")
    b.abox(-HX, HX, HY0 - .1, HY0, ZD, ZD + ch - 0.12, "WreckRust", "-z")
    # hatch boards: one collapsed into the hold, one leaning on the coaming
    with xf(b, about((HX + 0.1, 4.6, ZD + ch), RY(-14)) @ T(0, 0, 0)):
        b.abox(-HX - 0.1, HX + 0.1, 4.3, 5.1, ZD + ch, ZD + ch + 0.07, "WreckDeckDk")
    with xf(b, about((0, 2.6, ZD + ch - 0.4), RX(24))):
        b.abox(-0.8, 1.1, 2.0, 3.6, ZD + ch - 0.45, ZD + ch - 0.38, "WreckDeck")

    # cargo that slid to the low (starboard) side of the hold
    crates = [((1.15, 1.3, hf + 0.36), .72, 12, 0, 0), ((1.30, 2.35, hf + 0.4), .8, -8, 0, 0), ((1.0, 3.45, hf + 0.36), .72, 20, 0, 0),
              ((1.35, 4.5, hf + 0.4), .8, 4, 0, 0), ((0.45, 1.6, hf + 0.33), .66, 30, 0, 0), ((0.3, 3.0, hf + 0.34), .68, -18, 0, 0),
              ((1.2, 1.8, hf + 1.08), .66, 25, 0, 0), ((1.25, 4.0, hf + 1.1), .7, -10, 0, 0)]
    for (c, s, yw, tx, ty) in crates:
        crate(b, c, s, math.radians(yw), math.radians(tx), math.radians(ty))
    barrel(b, (-0.9, 5.2, hf + 0.45), 0.3, 0.9)
    barrel(b, (-1.35, 5.45, hf + 0.2), 0.28, 0.85, axis="Y")

    # ======================================================= deckhouse + wheelhouse ===================================================
    DX, DY0, DY1, DZ1 = 2.55, -10.5, -4.5, 5.5
    bandsD = [(ZD, 3.5, "WreckBarn"), (3.5, 5.0, "WreckWhite"), (5.0, DZ1, "WreckRust")]
    wall_x(b, -DX, -1, DY0, DY1, bandsD, [(-7.4, -6.4, ZD, 4.8), (-9.9, -8.7, 3.8, 4.8), (-5.8, -4.9, 3.8, 4.8)])
    wall_x(b, DX, 1, DY0, DY1, bandsD, [(-8.9, -7.9, ZD, 4.8), (-6.6, -5.5, 3.8, 4.8), (-10.0, -9.4, 3.8, 4.8)])
    wall_y(b, DY1, 1, -DX, DX, bandsD, [(-1.7, -0.5, 3.8, 4.8), (0.5, 1.7, 3.8, 4.8)])
    wall_y(b, DY0, -1, -DX, DX, bandsD, [(-0.5, 0.5, ZD, 4.8), (1.0, 1.9, 3.8, 4.8)])
    # roof slab (broken at the port-aft corner)
    for r in rects_with_holes(-DX, DX, DY0, DY1, [(-DX, -0.9, DY0, -8.9)]):
        b.zq(DZ1, r[0], r[1], r[2], r[3], 1, "WreckRustDk")
    bent_plate(b, (-0.9, -8.9, DZ1), (-0.9, -10.5, DZ1), (-1, 0, 0), 62, "WreckRust")
    # interior: bunk + strongbox
    b.abox(-2.45, -1.5, -9.9, -8.1, ZD, ZD + 0.5, "WreckRustDk")
    b.abox(-2.45, -1.5, -9.9, -8.1, ZD + 0.5, ZD + 0.58, "WreckAlgae")
    b.cbox((1.45, -8.5, ZD + 0.36), (0.72, 0.72, 0.72), "WreckSteel")
    # swung-open door leaf on the port door
    b.pq([(-DX, -6.4, ZD), (-DX, -6.4, 4.8), (-DX - 0.55, -5.5, 4.8), (-DX - 0.55, -5.5, ZD)], (-1, -0.5, 0), "WreckWhite")

    WX, WY0, WY1, WZ0, WZ1 = 2.1, -9.0, -5.2, 5.5, 7.5
    bandsW = [(WZ0, 6.1, "WreckTeal"), (6.1, WZ1, "WreckWhite")]
    wall_x(b, -WX, -1, WY0, WY1, bandsW, [(-8.7, -7.5, 6.1, 7.1), (-7.2, -6.0, 6.1, 7.1)])
    wall_x(b, WX, 1, WY0, WY1, bandsW, [(-8.7, -7.5, 6.1, 7.1), (-7.2, -6.0, 6.1, 7.1)])
    wall_y(b, WY1, 1, -WX, WX, bandsW, [(-1.6, -0.3, 6.1, 7.1), (0.3, 1.6, 6.1, 7.1)])
    wall_y(b, WY0, -1, -WX, WX, bandsW, [(-0.6, 0.6, 6.1, 7.1)])
    for r in rects_with_holes(-2.35, 2.35, -9.25, -4.95, [(0.4, 2.35, -7.3, -4.95)]):
        b.zq(WZ1 + 0.1, r[0], r[1], r[2], r[3], 1, "WreckDeck")
    bent_plate(b, (0.4, -7.3, WZ1 + 0.1), (2.35, -7.3, WZ1 + 0.1), (0, 1, 0), 58, "WreckDeck")
    # console inside the wheelhouse
    b.abox(-1.2, 1.2, -6.1, -5.55, WZ0, WZ0 + 0.85, "WreckRustDk")
    b.cyl((0.0, -6.4, WZ0 + 0.55), 0.22, 0.12, 6, "WreckBrass", caps="bt")                      # helm
    # radar mast stub + funnel (broken)
    b.beam((-1.1, -7.0, WZ1 + 0.1), (-1.0, -7.1, WZ1 + 1.15), 0.05, 0.04, 4, "WreckSteel")
    b.rbeam((-1.6, -7.05, WZ1 + 1.0), (-0.45, -7.15, WZ1 + 1.12), 0.5, 0.05, "WreckSteel")
    fy = -9.85
    top = [WZ0 + 2.55, WZ0 + 2.35, WZ0 + 2.7, WZ0 + 2.2, WZ0 + 2.6, WZ0 + 2.45, WZ0 + 2.75, WZ0 + 2.3]
    for k in range(8):
        a0, a1 = 2 * math.pi * k / 8, 2 * math.pi * (k + 1) / 8
        p0 = Vector((0.55 * math.cos(a0), fy + 0.5 * math.sin(a0), DZ1))
        p1 = Vector((0.55 * math.cos(a1), fy + 0.5 * math.sin(a1), DZ1))
        q0 = Vector((0.42 * math.cos(a0), fy + 0.4 * math.sin(a0), top[k]))
        q1 = Vector((0.42 * math.cos(a1), fy + 0.4 * math.sin(a1), top[(k + 1) % 8]))
        mm = "WreckRust" if k % 3 == 0 else "WreckTeal"
        b.po([p0, p1, q1, q0], (0, fy, DZ1 + 1.0), mm)
    b.cyl((0, fy, DZ1 + 1.0), 0.47, 0.18, 8, "WreckSteel", caps="", sc=(1.3, 1.1))                 # funnel band

    # ======================================================= mast, boom, rigging ==================================================
    b.cyl((0, 7.5, ZD + 0.15), 0.3, 0.3, 6, "WreckSteel", caps="t")
    b.beam((0, 7.5, ZD), (0, 7.5, 6.3), 0.17, 0.12, 6, "WreckSteel")
    b.beam((0, 7.5, 6.3), (0.35, 7.55, 7.2), 0.12, 0.04, 6, "WreckRustDk")                         # snapped stump leaning over
    b.beam((-1.15, 7.5, 5.5), (1.3, 7.55, 5.75), 0.05, 0.045, 4, "WreckSteel")                    # yard
    b.beam((0.0, 7.52, 3.4), (-4.6, 5.7, 5.5), 0.085, 0.07, 5, "WreckRustDk")                     # boom swung over the port side
    for (tx_, ty_, tz_) in ((-2.9, 8.8, 3.1), (2.9, 8.6, 3.1)):
        b.pq([(0, 7.5, 6.0), (tx_, ty_, tz_), (tx_ + 0.03, ty_, tz_), (0.03, 7.5, 6.0)], (0, 1, 0), "RopeOld")
    b.pq([(0, 7.5, 6.0), (-0.1, 4.9, 3.6), (-0.07, 4.9, 3.6), (0.03, 7.5, 6.0)], (1, 0, 0), "RopeOld")

    # ======================================================= rails =============================================================
    xr = B * 0.96
    post_run(b, [(-xr, -13.0 + i * 0.5, 3.15) for i in range(0, 3)], 0.85)
    post_run(b, [(xr, -13.0 + i * 0.55, 3.15) for i in range(0, 4)], 0.85)
    post_run(b, [(xr * 0.98, 7.0 + i * 0.8, 3.45) for i in range(0, 3)], 0.8)
    post_run(b, [(-2.45, -6.2 - 0.9 * i, DZ1) for i in range(0, 3)], 0.8)
    post_run(b, [(2.45, -5.0 - 1.0 * i, DZ1) for i in range(0, 4)], 0.8)
    post_run(b, [(-1.1, 12.9, ZF + 0.0), (-0.5, 13.15, ZF), (0.5, 13.15, ZF), (1.1, 12.9, ZF)], 0.8)

    # ======================================================= engine room, shaft, propeller, rudder ==================================
    b.abox(-0.9, 0.9, -12.4, -10.9, 0.5, 2.0, "WreckRustDk")
    b.abox(-0.7, 0.7, -12.2, -11.1, 2.0, 2.35, "WreckSteel")
    b.cyl((-1.55, -11.9, 1.0), 0.5, 1.5, 8, "WreckRust", caps="t")                               # boiler / tank
    b.beam((0, -12.4, 0.95), (0, -14.5, 0.8), 0.1, 0.1, 6, "WreckSteel", caps=False)
    b.cyl((0, -14.55, 0.78), 0.2, 0.3, 6, "WreckBrass", axis="Y", caps="bt")
    for k in range(3):
        a = math.radians(90 + 120 * k)
        ux, uz = math.cos(a), math.sin(a)
        vx, vz = -uz, ux

        def P(u, v, y):
            return (ux * u + vx * v, y, 0.78 + uz * u + vz * v)
        b.pq([P(0.15, -0.1, -14.5), P(0.3, 0.2, -14.62), P(1.2, 0.26, -14.7), P(1.28, -0.05, -14.52)], (0, -1, 0), "WreckBrass")
    b.abox(0.05, 0.2, -15.0, -14.45, 0.0, 2.6, "WreckRustDk")                                    # rudder blade (bent)

    # ======================================================= place on the sea bed =====================================================
    Mroll = RY(ROLL)
    transform_all(b, Mroll)
    zmin = vmin_z(b)
    xs = [v.co.x for v in b.bm.verts]
    xshift = -(max(xs) + min(xs)) / 2
    Msh = T(xshift, 0, -0.2 - zmin)
    transform_all(b, Msh)
    W = lambda p: (Msh @ Mroll @ Vector(p))

    # ---- debris on the sea floor (world frame) ----
    sand = lambda x, y: (x, y)
    crate(b, (-6.6, 1.6, 0.34), .8, math.radians(35), math.radians(12), math.radians(-8))
    crate(b, (-7.3, 3.3, 0.3), .7, math.radians(-20), math.radians(0), math.radians(18))
    crate(b, (-5.9, 4.2, 0.32), .72, math.radians(70), math.radians(-10), 0)
    barrel(b, (-7.6, -1.4, 0.3), 0.3, 0.88, axis="X")
    for (x, y, z, w_, l_, tilt, yaw, m) in ((-8.6, 6.0, 0.35, 1.4, 1.1, 24, 30, "WreckBarn"), (-5.5, -6.6, 0.28, 1.2, 0.9, 16, -40, "WreckTeal"),
                                         (7.9, -3.0, 0.3, 1.5, 1.0, 20, 110, "WreckRust"), (-6.9, 9.8, 0.22, 1.0, 0.8, 12, 70, "WreckTeal")):
        with xf(b, T(x, y, z) @ RZ(yaw) @ RX(tilt)):
            b.pq([(-w_ / 2, -l_ / 2, 0), (w_ / 2, -l_ / 2, 0.0), (w_ / 2 - 0.1, l_ / 2, 0.12), (-w_ / 2, l_ / 2, 0.05)], (0, 0, 1), m)
    with xf(b, T(-5.2, -9.6, 0.25) @ RZ(25)):                                                     # fallen spar
        b.beam((0, 0, 0), (0.1, 2.9, 0.2), 0.09, 0.08, 5, "WreckRustDk")

    # silt drifts banked against the buried starboard side (low irregular domes, no hidden underside)
    def dome(cx, cy, rx, ry, h, seg=7, seed=1, mat="UWSilt"):
        rr = random.Random(seed)
        ring = [(cx + rx * math.cos(2 * math.pi * i / seg) * rr.uniform(.8, 1.1), cy + ry * math.sin(2 * math.pi * i / seg) * rr.uniform(.8, 1.1)) for i in range(seg)]
        apex = (cx + rr.uniform(-.2, .2), cy + rr.uniform(-.2, .2), h)
        for i in range(seg):
            j = (i + 1) % seg
            b.pq([(ring[i][0], ring[i][1], -0.2), (ring[j][0], ring[j][1], -0.2), apex], (0, 0, 1), mat)
    dome(W((3.4, -4.0, 0.2)).x + 1.0, -4.0, 2.4, 3.6, 0.7, 8, 3)
    dome(W((3.4, 7.5, 0.2)).x + 0.8, 7.5, 1.9, 2.6, 0.55, 7, 4)
    dome(-0.8, -14.6, 2.0, 1.6, 0.5, 7, 5)

    # ---- anchor points (empties) in WORLD frame ----
    A.mark("TreasureSpot_1", W((0.0, 3.9, hf + 0.3)), size=0.35, display="SPHERE")             # hold, among the crates
    A.mark("TreasureSpot_2", W((-0.3, -8.2, ZD + 0.4)), size=0.35, display="SPHERE")            # captain's cabin
    A.mark("TreasureSpot_3", W((1.3, -13.2, 0.8)), size=0.35, display="SPHERE")                 # engine room
    A.mark("DiverEntry", W((-5.4, 2.4, 3.6)) + Vector((0, 0, 0.0)), size=0.5, display="CUBE")     # open water beside the breach
    for _o in descendants(A.root):
        if _o.type == 'EMPTY' and _o is not A.root:
            print('  empty', _o.name.split('__')[1], tuple(round(c, 2) for c in (A.root.matrix_world.inverted() @ _o.matrix_world.translation)))
    A.mesh(b, "Body", uv=None)
    return A


A_ship = build()
A_ship.report(2500)
