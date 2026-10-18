# -*- coding: utf-8 -*-
"""Settlements kit - farmhouse, barn, grain silo. exec'd into the kit namespace by settlements_kit.py"""


@asset('bld_farmhouse', 'Farmhouse (9x11 m, two-storey, veranda)', x=76.0, ext=(-5.0, 8.0), group='farm', budget=22000, collision='box',
       tags=['farm', 'rural', 'temperate'], scale=(0.9, 1.15), usage='Two-storey farmhouse with front veranda, door on +X, ridge along Y')
def farmhouse(mb):
    cfg = dict(poly=[(-3.5, -5.5), (3.5, -5.5), (3.5, 5.5), (-3.5, 5.5)], floors=2, tint=(1.0, 1.0, 0.97, 1),
               open={1: [('w', 1.8, 1.0, 1.25, 0), ('w', 3.6, 1.0, 1.25, 0), ('d', 5.5, 1.1, 2.1, dict(steps=False)), ('w', 7.4, 1.0, 1.25, 0), ('w', 9.2, 1.0, 1.25, 0),
                         ('w', 1.8, 1.0, 1.25, 1), ('w', 3.6, 1.0, 1.25, 1), ('w', 5.5, 1.0, 1.25, 1), ('w', 7.4, 1.0, 1.25, 1), ('w', 9.2, 1.0, 1.25, 1)],
                     0: [('w', 3.5, 1.0, 1.25, 0), ('w', 3.5, 1.0, 1.25, 1)],
                     2: [('w', 3.5, 1.0, 1.25, 0), ('w', 3.5, 1.0, 1.25, 1)],
                     3: [('w', 2.2, 1.0, 1.25, 0), ('w', 5.5, 1.0, 1.25, 0), ('w', 8.8, 1.0, 1.25, 0),
                         ('w', 2.2, 1.0, 1.25, 1), ('w', 5.5, 1.0, 1.25, 1), ('w', 8.8, 1.0, 1.25, 1)]},
               gables=[(0, 0.0, 7.0, 40), (2, 0.0, 7.0, 40)],
               roofs=[dict(x0=-3.5, x1=3.5, y0=-5.5, y1=5.5, axis='y', pitch=40, ov_e=0.6)],
               chimneys=[(0.0, 4.4, 9.9, 0.85, 1.0, 'M_Bld_Stone'), (0.0, -4.4, 9.9, 0.85, 1.0, 'M_Bld_Stone')], pipes=[(3.62, 5.38), (-3.62, 5.38)])
    eave, rz = build_house(mb, cfg)
    # veranda
    px = 3.5; pw = 2.0
    mb.box((px, -5.2, 0.0), (px + pw + 0.1, 5.2, 0.3), 'M_Bld_Stone', c=0.02)
    for sy in (-4.9, -2.45, 0.0 - 0.0, 2.45, 4.9):
        if abs(sy) < 0.1:
            continue
        mb.box((px + pw - 0.16, sy - 0.07, 0.3), (px + pw - 0.02, sy + 0.07, 2.95), 'M_Bld_Wood', c=0.008)
    for sy in (-0.85, 0.85):
        mb.box((px + pw - 0.16, sy - 0.07, 0.3), (px + pw - 0.02, sy + 0.07, 2.95), 'M_Bld_Wood', c=0.008)
    mb.box((px + pw - 0.2, -5.1, 2.8), (px + pw + 0.02, 5.1, 2.98), 'M_Bld_Wood', c=0.01)
    # railing between posts (gap at the stairs)
    for rng_ in ((-4.9, -0.85), (0.85, 4.9)):
        a, b = rng_
        mb.box((px + pw - 0.12, a, 0.95), (px + pw - 0.04, b, 1.04), 'M_Bld_Wood')
        mb.box((px + pw - 0.12, a, 0.4), (px + pw - 0.04, b, 0.46), 'M_Bld_Wood')
        y = a + 0.25
        while y < b - 0.1:
            mb.box((px + pw - 0.11, y - 0.025, 0.46), (px + pw - 0.05, y + 0.025, 0.95), 'M_Bld_Wood')
            y += 0.28
    # steps
    mb.box((px + pw - 0.05, -0.85, 0.0), (px + pw + 0.7, 0.85, 0.15), 'M_Bld_Stone', c=0.01)
    # porch roof
    roof_slope(mb, (px + pw + 0.25, -5.4, 2.9), (px - 0.02, -5.4, 2.9 + (pw + 0.27) * tan(radians(15))), (0, 1, 0), 10.8, 'M_Bld_RoofTile', 'M_Bld_Wood', course=0.28)
    mb.hull_box((px, -5.3, 0.0), (px + pw + 0.3, 5.3, 3.3))
    shift_all(mb, dx=-0.9)
    return dict(footprint=[9.0, 11.0], floors=2, veranda=True)


# ---------------------------------------------------------------------------------------------------------------------
@asset('bld_barn', 'Barn (18x12 m, gambrel roof, red boards)', x=100.0, ext=(-10.0, 10.5), group='farm', budget=22000, collision='box',
       tags=['farm', 'rural', 'temperate'], scale=(0.85, 1.2), usage='Gambrel barn; sliding doors on the +X gable end; ridge along X')
def barn(mb):
    x0, x1, y0, y1 = -9.0, 9.0, -6.0, 6.0
    poly = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    eave = 4.2; zb = 0.5; t = 0.3
    dz1 = zb + 3.7
    opens = {1: [(3.6, 8.4, zb, dz1)],
             0: [(u - 0.5, u + 0.5, 2.2, 3.1) for u in (3.0, 9.0, 15.0)],
             2: [(u - 0.5, u + 0.5, 2.2, 3.1) for u in (3.0, 9.0, 15.0)],
             3: [(5.0, 7.0, 1.6, 2.5)]}
    wfs, convex = house_walls(mb, poly, zb, eave, t, opens, 'M_Bld_PaintRed', col=(0.95, 0.95, 0.95, 1))
    plinth(mb, poly, zb, 0.06)
    # gambrel gable fills (E and W)
    prof = [(0.0, eave), (12.0, eave), (10.0, 6.6), (6.0, 8.3), (2.0, 6.6)]
    for e in (1, 3):
        pl = Plane(wfs[e].p(0, 0, -t), wfs[e].d, Z3)
        mb.prism(pl, prof, 0.0, t, 'M_Bld_PaintRed', col=(0.95, 0.95, 0.95, 1))
    # battens
    for e, wf in enumerate(wfs):
        ops = opens.get(e, [])
        u = 0.75
        while u < wf.L - 0.5:
            if not any(o[0] - 0.15 < u < o[1] + 0.15 for o in ops):
                wf.box(mb, u - 0.045, u + 0.045, zb, eave, 0.0, 0.035, 'M_Bld_PaintRed', col=(0.82, 0.82, 0.82, 1))
            u += 0.75
    # corner boards + base board
    for (cx, cy) in poly:
        mb.box((cx - 0.1, cy - 0.1, zb), (cx + 0.1, cy + 0.1, eave + 0.02), 'M_Bld_PaintWhite', c=0.01)
    # windows (white trim)
    for e in (0, 2):
        for u in (3.0, 9.0, 15.0):
            window_unit(mb, wfs[e], u - 0.5, u + 0.5, 2.2, 3.1, t, frame='M_Bld_PaintWhite', shutters=None, lintel=None, panes=(2, 1))
    window_unit(mb, wfs[3], 5.0, 7.0, 1.6, 2.5, t, frame='M_Bld_PaintWhite', shutters=None, lintel=None, panes=(3, 1))
    # sliding doors (E): two leaves, white frame + X braces, track beam
    E = wfs[1]
    for (a0, a1) in ((3.4, 6.05), (5.95, 8.6)):
        E.box(mb, a0, a1, zb, dz1 + 0.05, 0.02, 0.16, 'M_Bld_PaintRed', col=(0.9, 0.9, 0.9, 1))
        fw = 0.14
        E.box(mb, a0, a0 + fw, zb, dz1 + 0.05, 0.16, 0.22, 'M_Bld_PaintWhite')
        E.box(mb, a1 - fw, a1, zb, dz1 + 0.05, 0.16, 0.22, 'M_Bld_PaintWhite')
        E.box(mb, a0, a1, zb, zb + fw, 0.16, 0.22, 'M_Bld_PaintWhite')
        E.box(mb, a0, a1, dz1 + 0.05 - fw, dz1 + 0.05, 0.16, 0.22, 'M_Bld_PaintWhite')
        E.box(mb, a0, a1, (zb + dz1) / 2 - 0.07, (zb + dz1) / 2 + 0.07, 0.16, 0.22, 'M_Bld_PaintWhite')
        # diagonal braces
        pa = E.p(a0 + fw, zb + fw, 0.19); pb = E.p(a1 - fw, (zb + dz1) / 2, 0.19)
        mb.bar(pa, pb, 0.1, 0.05, 'M_Bld_PaintWhite')
        pa = E.p(a0 + fw, (zb + dz1) / 2, 0.19); pb = E.p(a1 - fw, dz1 - 0.1, 0.19)
        mb.bar(pa, pb, 0.1, 0.05, 'M_Bld_PaintWhite')
    E.box(mb, 3.2, 8.8, dz1 + 0.12, dz1 + 0.24, 0.1, 0.34, 'M_Bld_Metal')       # track
    E.box(mb, 3.3, 8.7, dz1 + 0.24, dz1 + 0.34, 0.12, 0.2, 'M_Bld_PaintWhite')
    # hayloft hatch on the gable face + hoist beam
    E.box(mb, 5.0, 7.0, 5.3, 6.6, 0.0, 0.06, 'M_Bld_PaintWhite')
    E.box(mb, 5.15, 6.85, 5.45, 6.45, 0.06, 0.1, 'M_Bld_Window')
    E.box(mb, 5.95, 6.05, 5.45, 6.45, 0.09, 0.13, 'M_Bld_PaintWhite')
    E.box(mb, 5.8, 6.2, 7.55, 7.65, 0.0, 1.1, 'M_Bld_PaintWhite')
    mb.cyl(E.p(6.0, 7.45, 0.9), E.p(6.0, 7.45, 1.0), 0.1, 0.1, 'M_Bld_Metal', seg=8)
    # stone steps / ramp
    E.box(mb, 3.0, 9.0, 0.0, zb - 0.05, 0.0, 1.4, 'M_Bld_Stone', c=0.015)
    # roof (gambrel)
    xa, xb = x0 - 0.35, x1 + 0.45
    for sg in (1, -1):
        P0 = Vector((xa, sg * 6.26, 3.89)); P1 = Vector((xa, sg * 4.0, 6.6)); P2 = Vector((xa, 0.0, 8.3))
        roof_slope(mb, P0, P1, (1, 0, 0), xb - xa, 'M_Bld_Metal', 'M_Bld_PaintWhite', course=0.55, nose=0.045, seg=1.5)
        roof_slope(mb, P1, P2, (1, 0, 0), xb - xa, 'M_Bld_Metal', 'M_Bld_PaintWhite', course=0.55, nose=0.045, seg=1.5)
    ridge_cap(mb, (xa, 0, 8.3), (xb, 0, 8.3), (0, 1, 0), 0.425, 'M_Bld_Metal', half=0.4, h=0.12)
    # cupola
    cx = -2.0
    mb.box((cx - 0.55, -0.55, 8.2), (cx + 0.55, 0.55, 9.0), 'M_Bld_PaintWhite', c=0.01)
    for k in range(4):
        zz = 8.35 + k * 0.17
        for (ax, ay, sx, sy) in ((1, 0, 0.02, 0.4), (-1, 0, 0.02, 0.4), (0, 1, 0.4, 0.02), (0, -1, 0.4, 0.02)):
            mb.box((cx + ax * 0.56 - sx, ay * 0.56 - sy, zz), (cx + ax * 0.56 + sx + 0.03 * abs(ax), ay * 0.56 + sy + 0.03 * abs(ay), zz + 0.09), 'M_Bld_Window')
    mb.lathe([(0.95, 9.0), (0.0, 9.7)], 'M_Bld_Metal', seg=4, center=(cx, 0), roll=pi / 4, cap0=True)
    # collision
    mb.hull_box((x0, y0, 0.0), (x1, y1, eave))
    mb.hull_pts([(x0 - 0.3, -6.3, 3.9), (x0 - 0.3, 6.3, 3.9), (x0 - 0.3, -4.0, 6.6), (x0 - 0.3, 4.0, 6.6), (x0 - 0.3, 0, 8.4),
                 (x1 + 0.4, -6.3, 3.9), (x1 + 0.4, 6.3, 3.9), (x1 + 0.4, -4.0, 6.6), (x1 + 0.4, 4.0, 6.6), (x1 + 0.4, 0, 8.4)])
    return dict(footprint=[18.0, 12.0], roof='gambrel')


# ---------------------------------------------------------------------------------------------------------------------
@asset('bld_silo', 'Grain silo (5.6 m dia, 15.4 m)', x=124.0, ext=(-3.5, 4.5), group='farm', budget=9000, collision='convex',
       tags=['farm', 'rural', 'industrial'], scale=(0.9, 1.2), usage='Corrugated grain silo with cone roof, ladder and fill pipe on +X')
def silo(mb):
    R = 2.8; H0 = 0.8; H1 = 13.2; n = 32
    # foundation
    mb.cyl((0, 0, 0), (0, 0, H0), R + 0.3, R + 0.25, 'M_Bld_Stone', seg=24, smooth=False)
    mb.cyl((0, 0, H0), (0, 0, H0 + 0.08), R + 0.08, R + 0.08, 'M_Bld_Metal', seg=32, smooth=False)
    # corrugated body in panels
    zs = [H0 + 0.08 + i * (H1 - H0 - 0.08) / 6.0 for i in range(7)]
    for i in range(6):
        rings = []
        for z in (zs[i] + 0.02, zs[i + 1] - 0.02):
            rings.append([Vector(((R + (0.035 if k % 2 else -0.035)) * cos(2 * pi * k / n), (R + (0.035 if k % 2 else -0.035)) * sin(2 * pi * k / n), z)) for k in range(n)])
        mb.loft(rings, 'M_Bld_Metal', True, False, cap0=True, cap1=True, cap_tri=True)
    # hoops
    for z in zs[1:-1] + [H1 - 0.05]:
        mb.cyl((0, 0, z - 0.07), (0, 0, z + 0.07), R + 0.075, R + 0.075, 'M_Bld_Metal', seg=32, smooth=False)
    # roof cone with eave lip
    mb.lathe([(R + 0.35, H1 - 0.05), (R + 0.3, H1 + 0.12), (R * 0.2, H1 + 2.05), (0.0, H1 + 2.15)], 'M_Bld_Metal', seg=32, smooth=False, cap0=True)
    mb.cyl((0, 0, H1 + 2.0), (0, 0, H1 + 2.45), 0.32, 0.32, 'M_Bld_Metal', seg=12)
    mb.lathe([(0.55, H1 + 2.4), (0.0, H1 + 2.85)], 'M_Bld_Metal', seg=12, smooth=False, cap0=True)
    # door hatch at base (+X)
    mb.box((R - 0.1, -0.5, H0 + 0.25), (R + 0.17, 0.5, H0 + 1.45), 'M_Bld_Metal', c=0.02)
    mb.box((R + 0.12, -0.42, H0 + 0.32), (R + 0.2, 0.42, H0 + 1.38), 'M_Bld_Stone', c=0.02)
    mb.box((R + 0.19, 0.28, H0 + 0.8), (R + 0.27, 0.36, H0 + 0.95), 'M_Bld_Metal')
    # ladder (+X side, offset in Y) : rails + rungs + cage hoops
    ly = -1.1; lx = R + 0.25
    for sy in (-0.22, 0.22):
        mb.box((lx - 0.04, ly + sy - 0.03, H0), (lx + 0.04, ly + sy + 0.03, H1 + 0.7), 'M_Bld_Metal')
    z = H0 + 0.4
    while z < H1 + 0.6:
        mb.box((lx - 0.03, ly - 0.22, z - 0.02), (lx + 0.03, ly + 0.22, z + 0.02), 'M_Bld_Metal')
        z += 0.32
    for z in [3.5 + 1.4 * k for k in range(7)]:
        mb.box((lx + 0.34, ly - 0.38, z - 0.02), (lx + 0.42, ly + 0.38, z + 0.02), 'M_Bld_Metal')
        mb.box((lx - 0.04, ly - 0.38, z - 0.02), (lx + 0.42, ly - 0.30, z + 0.02), 'M_Bld_Metal')
        mb.box((lx - 0.04, ly + 0.30, z - 0.02), (lx + 0.42, ly + 0.38, z + 0.02), 'M_Bld_Metal')
    for sy in (-0.38, 0.38):
        mb.box((lx + 0.34, ly + sy - 0.02, 3.5), (lx + 0.42, ly + sy + 0.02, H1 - 0.5), 'M_Bld_Metal')
    # fill pipe (+X, opposite side of ladder) with elbow into the roof
    py = 1.2; px = R + 0.3
    mb.cyl((px, py, 0.2), (px, py, H1 + 0.5), 0.11, 0.11, 'M_Bld_Metal', seg=10)
    mb.cyl((px, py, H1 + 0.5), (R * 0.45, 0.3, H1 + 1.55), 0.11, 0.11, 'M_Bld_Metal', seg=10)
    mb.cyl((px - 0.08, py - 0.08, 0.0), (px + 0.08, py + 0.08, 0.2), 0.2, 0.2, 'M_Bld_Stone', seg=8)
    # unloading spout at the base on -X
    mb.cyl((-R + 0.1, 0.0, 1.5), (-R - 0.9, 0.0, 0.7), 0.17, 0.2, 'M_Bld_Metal', seg=10)
    # collision
    mb.hull_cyl((0, 0, 0), (0, 0, H1), R + 0.3, seg=12)
    mb.hull_pts([(R * cos(2 * pi * k / 12), R * sin(2 * pi * k / 12), H1) for k in range(12)] + [(0, 0, H1 + 2.2)])
    return dict(diameter=2 * R, height=H1 + 2.85)
