# -*- coding: utf-8 -*-
"""Settlements kit - castle ruin pieces: wall segment (6 m), corner tower ruin, arch. exec'd into the kit namespace."""


def _interp(prof, u):
    if u <= prof[0][0]: return prof[0][1]
    for i in range(1, len(prof)):
        if u <= prof[i][0]:
            a, b = prof[i - 1], prof[i]
            t = (u - a[0]) / max(1e-6, b[0] - a[0])
            return a[1] + (b[1] - a[1]) * t
    return prof[-1][1]


def masonry_wall(mb, P0, ang, length, thick, prof, face_depth=0.3, mat='M_Bld_Stone', seed=1, hmax=None, row=(0.34, 0.5), blen=(0.55, 1.15), skip=None):
    """Ruined masonry wall: jagged core slab + faced stone blocks on both faces. Local frame: origin P0 (ground, centreline), +u along the wall
    (angle `ang` about Z), width +-thick/2. prof = [(u, height)] defines the surviving height."""
    rng = random.Random(seed)
    M = Matrix.Translation(Vector(P0)) @ Matrix.Rotation(ang, 4, 'Z')
    R3 = M.to_3x3()
    tc = thick - 2 * face_depth + 0.06
    pl = Plane(M @ Vector((0, tc / 2, 0)), R3 @ Vector((1, 0, 0)), Vector((0, 0, 1)))
    poly = [(0.0, 0.0), (length, 0.0)] + [(u, max(0.3, h - 0.18)) for (u, h) in reversed(prof)]
    mb.prism(pl, poly, 0.0, tc, mat, col=(0.62, 0.6, 0.58, 1))
    hm = hmax or max(h for (_, h) in prof)
    for sgn in (1, -1):
        yc = sgn * (thick / 2 - face_depth / 2)
        z = 0.0
        while z < hm:
            hk = rng.uniform(*row)
            u = -rng.uniform(0.0, 0.5)
            while u < length - 0.05:
                Lb = rng.uniform(*blen)
                a = max(0.0, u); b = min(length, u + Lb)
                if b - a > 0.2:
                    uc = (a + b) / 2
                    top = z + hk
                    if top <= _interp(prof, uc) + 0.1 and not (skip and skip(uc, z, top)):
                        k = 1.0 + rng.uniform(-0.18, 0.12)
                        mb.stone(M @ Vector((uc, yc, z + hk / 2)), (b - a - 0.03, face_depth, hk - 0.03), mat, (0, 0, degrees(ang) + (0 if sgn > 0 else 180)),
                                 bevel=0.04, col=(k, k, k, 1.0))
                u += Lb
            z += hk


def rubble(mb, cx, cy, n, spread, seed=3, mat='M_Bld_Stone'):
    rng = random.Random(seed)
    for _ in range(n):
        a = rng.uniform(0, 2 * pi); d = rng.uniform(0.2, spread)
        L = rng.uniform(0.3, 0.8); H = rng.uniform(0.22, 0.45); D = rng.uniform(0.3, 0.6)
        k = 1.0 + rng.uniform(-0.2, 0.1)
        mb.stone((cx + d * cos(a), cy + d * sin(a), H / 2 - 0.03), (L, D, H), mat, (rng.uniform(-6, 6), rng.uniform(-6, 6), rng.uniform(0, 360)), bevel=0.06, col=(k, k, k, 1.0))


@asset('bld_castle_wall_6m', 'Castle ruin wall segment (6 m)', x=370.0, ext=(0.0, 6.0), group='ruins', budget=9000, collision='box', pivot='segment_start',
       tags=['ruin', 'castle', 'medieval'], scale=(0.9, 1.2), usage='Ruined curtain wall: starts at x=0 on the centreline, runs 6 m along +X, ends are full height (4.7 m) so segments chain')
def castle_wall(mb):
    prof = [(0, 4.7), (0.8, 4.7), (0.8, 4.2), (1.5, 4.2), (1.5, 3.6), (2.1, 3.9), (2.4, 3.0), (3.0, 3.4), (3.3, 2.2), (3.9, 2.9), (4.4, 3.8), (4.6, 4.2),
            (5.2, 4.2), (5.2, 4.7), (6.0, 4.7)]
    # arrow loop (slit) skip
    def skip(uc, z, top):
        return 2.9 < z < 3.5 and 1.95 < uc < 2.55 or (1.4 < z < 2.3 and 4.5 < uc < 4.9)
    masonry_wall(mb, (0, 0, 0), 0.0, 6.0, 1.2, prof, seed=11, skip=skip)
    rubble(mb, 3.0, 0.0, 9, 1.6, seed=5)
    mb.hull_box((0.0, -0.6, 0.0), (2.1, 0.6, 4.2))
    mb.hull_box((2.1, -0.6, 0.0), (4.4, 0.6, 3.0))
    mb.hull_box((4.4, -0.6, 0.0), (6.0, 0.6, 4.2))
    return dict(length=6.0, thickness=1.2, max_height=4.7)


@asset('bld_castle_tower_ruin', 'Castle corner tower ruin (round, 9.5 m, wall stubs)', x=386.0, ext=(-7.0, 3.5), group='ruins', budget=14000, collision='convex', pivot='tower_centre',
       tags=['ruin', 'castle', 'medieval'], scale=(0.9, 1.25), usage='Round corner tower ruin with doorway facing +X and two wall stubs running to -X and -Y; origin = tower centre')
def tower_ruin(mb):
    rng = random.Random(21)
    ro = 3.0; D = 0.85; n = 18; rc = ro - D / 2
    def hmax(a):
        return max(3.4, min(9.9, 6.4 + 2.6 * cos(a - radians(120)) + 1.2 * cos(2 * a + radians(40)) + rng.uniform(-0.15, 0.15)))
    prof_h = {}
    z = 0.0; k = 0
    while z < 10.0:
        hk = rng.uniform(0.4, 0.5)
        off = 0.5 * (k % 2)
        for i in range(n):
            a = 2 * pi * (i + off) / n
            ad = degrees(a) % 360
            top = z + hk
            if top > hmax(a) + 0.1:
                continue
            if (ad < 21 or ad > 339) and z < 2.7:        # doorway
                continue
            if abs(ad - 100) < 11 and 3.3 < z < 4.8:     # arrow windows
                continue
            if abs(ad - 215) < 11 and 3.3 < z < 4.8:
                continue
            if abs(ad - 300) < 11 and 5.6 < z < 7.0:
                continue
            L = 2 * rc * sin(pi / n) * 1.14
            kk = 1.0 + rng.uniform(-0.18, 0.12)
            mb.stone((rc * cos(a), rc * sin(a), z + hk / 2), (L, D, hk - 0.03), 'M_Bld_Stone', (0, 0, degrees(a) - 90), bevel=0.05, col=(kk, kk, kk, 1.0))
        z += hk; k += 1
    # doorway lintel + threshold, floor slab
    mb.box((ro - D - 0.1, -1.15, 2.68), (ro + 0.1, 1.15, 3.12), 'M_Bld_Stone', c=0.03)
    mb.box((ro - D - 0.25, -1.05, 0.0), (ro + 0.25, 1.05, 0.22), 'M_Bld_Stone', c=0.03)
    mb.cyl((0, 0, 0), (0, 0, 0.22), ro - D + 0.1, ro - D + 0.1, 'M_Bld_Stone', seg=18, smooth=False)
    # two wall stubs (to -X and -Y), jagged
    masonry_wall(mb, (-ro + 0.25, 0, 0), pi, 4.2, 1.1, [(0, 5.2), (1.0, 4.6), (1.6, 3.6), (2.6, 3.9), (3.3, 2.6), (4.2, 3.1)], face_depth=0.28, seed=33)
    masonry_wall(mb, (0, -ro + 0.25, 0), -pi / 2, 3.4, 1.1, [(0, 4.8), (0.8, 4.4), (1.5, 3.2), (2.2, 3.5), (3.4, 2.0)], face_depth=0.28, seed=44)
    rubble(mb, 2.0, 3.8, 8, 2.2, seed=7)
    rubble(mb, -1.0, -4.2, 7, 2.0, seed=9)
    # collision: annular sectors around the doorway gap + stubs
    ri = ro - D
    for i in range(6):
        a0 = radians(24 + i * 52); a1 = radians(24 + (i + 1) * 52); am = (a0 + a1) / 2
        pts = []
        for z_ in (0.0, 8.0):
            for (rr, aa) in ((ri, a0), (ri, a1), (ro, a0), (ro, a1), (ro, am)):
                pts.append((rr * cos(aa), rr * sin(aa), z_))
        mb.hull_pts(pts)
    mb.hull_pts([(-ro - 4.0 + 0.0, -0.55, 0.0), (-ro + 0.3, -0.55, 0.0), (-ro - 4.0, 0.55, 0.0), (-ro + 0.3, 0.55, 0.0),
                 (-ro - 4.0, -0.55, 3.4), (-ro + 0.3, -0.55, 5.0), (-ro - 4.0, 0.55, 3.4), (-ro + 0.3, 0.55, 5.0)])
    mb.hull_pts([(-0.55, -ro - 3.1, 0.0), (0.55, -ro - 3.1, 0.0), (-0.55, -ro + 0.3, 0.0), (0.55, -ro + 0.3, 0.0),
                 (-0.55, -ro - 3.1, 3.0), (0.55, -ro - 3.1, 3.0), (-0.55, -ro + 0.3, 4.6), (0.55, -ro + 0.3, 4.6)])
    return dict(radius=ro, height=9.9)


@asset('bld_castle_arch', 'Castle ruin arch (7.6 m wide, 6.9 m high)', x=406.0, ext=(-4.6, 4.6), group='ruins', budget=14000, collision='box', pivot='ground_centre',
       tags=['ruin', 'castle', 'medieval'], scale=(0.9, 1.3), usage='Free-standing ruined arch; opening 4.4 m wide, passable; axis through the arch = Y')
def castle_arch(mb):
    rng = random.Random(5)
    cz = 3.2; ri = 2.2; ro = 3.0; Dp = 1.2
    # piers (masonry walls along X, thickness along Y)
    masonry_wall(mb, (-3.8, 0, 0), 0.0, 1.6, Dp, [(0, 3.2), (1.6, 3.2)], face_depth=0.3, seed=2, hmax=3.2)
    masonry_wall(mb, (2.2, 0, 0), 0.0, 1.6, Dp, [(0, 3.2), (1.6, 3.2)], face_depth=0.3, seed=3, hmax=3.2)
    # voussoirs (full-depth blocks), some missing on the right
    nv = 13
    for i in range(nv):
        beta = pi * (i + 0.5) / nv
        bd = degrees(beta)
        if 22 < bd < 52:
            continue
        rc = (ri + ro) / 2
        tang = Vector((-sin(beta), 0, cos(beta))); rad = Vector((cos(beta), 0, sin(beta))); dep = tang.cross(rad)
        R = Matrix((tang, rad, dep)).transposed()
        L = 2 * rc * sin(pi / nv / 1.0) * 1.1
        k = 1.0 + rng.uniform(-0.1, 0.1)
        mb.stone((rc * cos(beta), 0, cz + rc * sin(beta)), (L, ro - ri, Dp - 0.04), 'M_Bld_Stone', R, bevel=0.04, col=(k, k, k, 1.0))
    # keystone (proud)
    mb.stone((0, 0, cz + (ri + ro) / 2 + 0.02), (0.62, ro - ri + 0.22, Dp + 0.1), 'M_Bld_Stone', Matrix.Identity(3), bevel=0.05)
    # spandrel / upper wall: broken top (higher on the left)
    heights = lambda x: 6.9 if x < -1.0 else (6.2 if x < 1.4 else 4.9)
    z = 3.2
    while z < 6.9:
        hk = rng.uniform(0.38, 0.5)
        x = -3.9 - rng.uniform(0, 0.4)
        while x < 3.9:
            Lb = rng.uniform(0.6, 1.15)
            a = max(-3.8, x); b = min(3.8, x + Lb)
            if b - a > 0.25:
                xc = (a + b) / 2; top = z + hk
                dist = sqrt(xc ** 2 + (z + hk / 2 - cz) ** 2)
                if top <= heights(xc) + 0.05 and (dist > ro + 0.12 or (z < cz + 0.05 and abs(xc) > 2.2)) :
                    k = 1.0 + rng.uniform(-0.18, 0.12)
                    mb.stone((xc, 0, z + hk / 2), (b - a - 0.03, Dp, hk - 0.03), 'M_Bld_Stone', Matrix.Rotation(radians(0), 3, 'Z'), bevel=0.04, col=(k, k, k, 1.0)) if False else \
                        mb.stone((xc, 0, z + hk / 2), (b - a - 0.03, Dp - 0.04, hk - 0.03), 'M_Bld_Stone', (0, 0, 0), bevel=0.04, col=(k, k, k, 1.0))
            x += Lb
        z += hk
    rubble(mb, 0.0, 1.1, 9, 1.3, seed=8)
    rubble(mb, -2.8, -1.1, 6, 1.0, seed=6)
    mb.hull_box((-3.8, -0.6, 0.0), (-2.2, 0.6, 6.9))
    mb.hull_box((2.2, -0.6, 0.0), (3.8, 0.6, 4.9))
    mb.hull_box((-1.4, -0.6, 5.35), (1.4, 0.6, 6.3))
    return dict(opening_width=2 * ri, opening_height=cz + ri, height=6.9)
