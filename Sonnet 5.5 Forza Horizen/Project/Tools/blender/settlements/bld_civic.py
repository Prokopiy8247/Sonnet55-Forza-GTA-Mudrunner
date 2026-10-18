# -*- coding: utf-8 -*-
"""Settlements kit - church, diner, gas station, chalet. exec'd into the kit namespace by settlements_kit.py"""


def strips(mb, wf, ua, ub, v0, v1, holes, mat, w0=0.0, w1=0.04, c=0.0, col=None):
    """horizontal box strip along a wall between u=ua..ub, v0..v1, interrupted by hole rects (u0,u1,hv0,hv1)."""
    segs = [(ua, ub)]
    for (hu0, hu1, hv0, hv1) in holes:
        if hv1 <= v0 or hv0 >= v1:
            continue
        ns = []
        for (a, b) in segs:
            if hu1 <= a or hu0 >= b:
                ns.append((a, b)); continue
            if hu0 > a: ns.append((a, hu0))
            if hu1 < b: ns.append((hu1, b))
        segs = ns
    for (a, b) in segs:
        if b - a > 0.05:
            wf.box(mb, a, b, v0, v1, w0, w1, mat, c=c, col=col)


def arch_poly(w, h, n=5):
    h1 = h - 0.866 * w
    pts = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h1)]
    for k in range(1, n + 1):
        th = radians(60.0 * k / n)
        pts.append((-w / 2 + w * cos(th), h1 + w * sin(th)))
    for k in range(1, n + 1):
        th = radians(120.0 + 60.0 * k / n)
        pts.append((w / 2 + w * cos(th), h1 + w * sin(th)))
    return pts


def arch_window(mb, wf, uc, v0, w, h, glass='M_Bld_Window', surround='M_Bld_Stone', tracery=True, sill=True):
    poly = [(uc + x, v0 + y) for (x, y) in arch_poly(w, h)]
    pl = wf.plane(0.0)
    mb.prism(pl, poly, 0.0, 0.05, glass)
    outer = offset_poly(poly, 0.12)
    mb.ring_prism(pl, outer, poly, 0.0, 0.1, surround)
    if tracery:
        wf.box(mb, uc - 0.03, uc + 0.03, v0, v0 + h - 0.5, 0.04, 0.09, surround)
        wf.box(mb, uc - w / 2, uc + w / 2, v0 + h * 0.42 - 0.03, v0 + h * 0.42 + 0.03, 0.04, 0.09, surround)
    if sill:
        wf.box(mb, uc - w / 2 - 0.18, uc + w / 2 + 0.18, v0 - 0.12, v0, 0.0, 0.2, surround, c=0.01)


# ---------------------------------------------------------------------------------------------------------------------
@asset('bld_church', 'Small church with bell tower', x=140.0, ext=(-10.5, 9.0), group='civic', budget=25000, collision='box',
       tags=['village', 'temperate', 'landmark'], scale=(0.9, 1.2), usage='Village church: nave along X, bell tower + door on +X, apse on -X')
def church(mb):
    t = 0.45; eave = 5.6
    slate = (0.46, 0.50, 0.58, 1)
    npoly = [(-7.0, -3.75), (3.0, -3.75), (3.0, 3.75), (-7.0, 3.75)]
    nfr, nconv = house_walls(mb, npoly, ZB, eave, t, {}, 'M_Bld_Plaster')
    plinth(mb, npoly, ZB, 0.07)
    quoins(mb, nfr, nconv, ZB, eave)
    mb.hull_box((-7.0, -3.75, 0.0), (3.0, 3.75, eave))
    # nave windows (applied lancets) + buttresses
    S, N, W = nfr[0], nfr[2], nfr[3]
    for u in (1.5, 4.0, 6.5):
        arch_window(mb, S, u, 1.7, 1.0, 3.1)
    for u in (3.5, 6.0, 8.5):
        arch_window(mb, N, u, 1.7, 1.0, 3.1)
    for wf, us in ((S, (2.75, 5.25)), (N, (4.75, 7.25))):
        for u in us:
            wf.box(mb, u - 0.28, u + 0.28, ZB, ZB + 3.9, 0.0, 0.6, 'M_Bld_Stone', c=0.02)
            wf.box(mb, u - 0.22, u + 0.22, ZB + 3.9, ZB + 4.7, 0.0, 0.36, 'M_Bld_Stone', c=0.02)
            roof_slope(mb, wf.p(u - 0.3, ZB + 3.85, 0.64), wf.p(u - 0.3, ZB + 3.85, 0.0), (wf.d.x, wf.d.y, 0), 0.6, 'M_Bld_Stone', 'M_Bld_Stone', course=0.2, nose=0.0, thick=0.04) if False else None
    # west gable (apse side): fill + rose window + small cross
    pitch = 42
    rise = 3.75 * tan(radians(pitch))
    gable_fill(mb, W, 0.0, 7.5, eave, rise, t, 'M_Bld_Plaster')
    pl = W.plane(0.0)
    c0 = (3.75, eave + 1.9)
    mb.prism(pl, ellipse_pts(c0[0], c0[1], 0.62, 0.62, 16), 0.0, 0.05, 'M_Bld_Window')
    o = ellipse_pts(c0[0], c0[1], 0.62 + 0.14, 0.62 + 0.14, 16); i_ = ellipse_pts(c0[0], c0[1], 0.62, 0.62, 16)
    mb.ring_prism(pl, o, i_, 0.0, 0.1, 'M_Bld_Stone')
    W.box(mb, c0[0] - 0.03, c0[0] + 0.03, c0[1] - 0.62, c0[1] + 0.62, 0.04, 0.09, 'M_Bld_Stone')
    W.box(mb, c0[0] - 0.62, c0[0] + 0.62, c0[1] - 0.03, c0[1] + 0.03, 0.04, 0.09, 'M_Bld_Stone')
    # nave roof (ridge along X), east end buried in the tower
    rz, _ = gable_wing(mb, -7.0, 3.0, -3.75, 3.75, eave, pitch, 'x', ov_e=0.55, ov_g0=0.4, ov_g1=1.2, col=slate)
    mb.hull_pts([(-7.4, -4.3, eave - 0.4), (-7.4, 4.3, eave - 0.4), (-7.4, 0, rz + 0.1), (4.2, -4.3, eave - 0.4), (4.2, 4.3, eave - 0.4), (4.2, 0, rz + 0.1)])
    # cross on the west gable
    mb.box((-7.55, -0.05, rz + 0.05), (-7.45, 0.05, rz + 0.95), 'M_Bld_Metal')
    mb.box((-7.55, -0.3, rz + 0.55), (-7.45, 0.3, rz + 0.65), 'M_Bld_Metal')
    # apse (half octagon) ------------------------------------------------------------------------------------------------
    ra = 2.7
    ap = [(-7.0, ra * sin(radians(112.5))), (-7.0 + ra * cos(radians(112.5)), ra * sin(radians(112.5))), (-7.0 + ra * cos(radians(157.5)), ra * sin(radians(157.5))),
          (-7.0 + ra * cos(radians(202.5)), ra * sin(radians(202.5))), (-7.0 + ra * cos(radians(247.5)), ra * sin(radians(247.5))), (-7.0, ra * sin(radians(247.5)))]
    aeave = 3.9
    afr, aconv = house_walls(mb, ap, ZB, aeave, 0.4, {}, 'M_Bld_Plaster')
    plinth(mb, ap, ZB, 0.07)
    for k in (1, 2, 3):
        arch_window(mb, afr[k], afr[k].L / 2, 1.5, 0.6, 1.9, sill=False)
    mb.lathe([(2.95, aeave - 0.05), (2.75, aeave + 0.08), (0.0, 6.5)], 'M_Bld_RoofTile', seg=8, center=(-7.0, 0.0), roll=pi / 8, smooth=False, cap0=True)
    mb.hull_pts([(x, y, z) for (x, y) in ap for z in (0.0, aeave)])
    # bell tower ---------------------------------------------------------------------------------------------------------
    tpoly = [(3.0, -2.5), (8.0, -2.5), (8.0, 2.5), (3.0, 2.5)]
    th = 12.5
    tdoor = (1.5, 3.5, ZB, ZB + 3.1)
    tfr, tconv = house_walls(mb, tpoly, ZB, th, 0.55, {1: [tdoor]}, 'M_Bld_Plaster')
    plinth(mb, tpoly, ZB, 0.08)
    quoins(mb, tfr, tconv, ZB, th)
    band(mb, tpoly, 9.4, 0.22, 0.1)
    band(mb, tpoly, th - 0.2, 0.22, 0.14)
    E = tfr[1]
    door_unit(mb, E, tdoor[0], tdoor[1], tdoor[2], tdoor[3], 0.55, steps=True)
    E.box(mb, 1.2, 3.8, ZB + 3.3, ZB + 3.5, 0.0, 0.3, 'M_Bld_Stone', c=0.02)
    for k, wf in enumerate(tfr):
        # belfry openings
        arch_window(mb, wf, 2.5, 9.9, 1.3, 2.4)
        for j in range(5):
            vv = 10.15 + j * 0.3
            wf.box(mb, 2.5 - 0.6, 2.5 + 0.6, vv, vv + 0.07, 0.04, 0.14, 'M_Bld_Stone') if False else None
    # lancets + clock
    for wf in (tfr[0], tfr[2]):
        arch_window(mb, wf, 2.5, 4.5, 0.5, 1.6, sill=False)
    for wf in (tfr[1], tfr[0], tfr[2]):
        cc = (2.5, 7.7)
        pl2 = wf.plane(0.0)
        mb.prism(pl2, ellipse_pts(cc[0], cc[1], 0.85, 0.85, 24), 0.0, 0.07, 'M_Bld_Plaster')
        mb.ring_prism(pl2, ellipse_pts(cc[0], cc[1], 0.98, 0.98, 24), ellipse_pts(cc[0], cc[1], 0.85, 0.85, 24), 0.0, 0.11, 'M_Bld_Metal')
        for hr in (0, 3, 6, 9):
            a = radians(30 * hr)
            wf.box(mb, cc[0] + 0.72 * sin(a) - 0.025, cc[0] + 0.72 * sin(a) + 0.025, cc[1] + 0.72 * cos(a) - 0.025, cc[1] + 0.72 * cos(a) + 0.025, 0.07, 0.1, 'M_Bld_Metal')
        wf.box(mb, cc[0] - 0.03, cc[0] + 0.03, cc[1], cc[1] + 0.55, 0.07, 0.12, 'M_Bld_Metal')
        mb.bar(wf.p(cc[0], cc[1], 0.1), wf.p(cc[0] + 0.4, cc[1] - 0.15, 0.1), 0.05, 0.03, 'M_Bld_Metal')
    # spire (square pyramid on the tower) + cross
    mb.lathe([(3.95, th - 0.02), (3.62, th + 0.2), (0.35, 18.0), (0.0, 18.25)], 'M_Bld_RoofTile', seg=4, center=(5.5, 0.0), roll=pi / 4, smooth=False, cap0=True)
    for k in range(4):   # spire courses (stepped rings) for silhouette interest
        pass
    mb.box((5.45, -0.05, 18.2), (5.55, 0.05, 19.4), 'M_Bld_Metal')
    mb.box((5.45, -0.3, 18.9), (5.55, 0.3, 19.0), 'M_Bld_Metal')
    mb.hull_box((3.0, -2.5, 0.0), (8.1, 2.5, th))
    mb.hull_pts([(5.5 + 3.62 * cos(pi / 4 + k * pi / 2), 3.62 * sin(pi / 4 + k * pi / 2), th + 0.2) for k in range(4)] + [(5.5, 0, 18.3)])
    shift_all(mb, dx=0.85)
    return dict(footprint=[18.0, 7.5], tower_height=19.4)


# ---------------------------------------------------------------------------------------------------------------------
def wall_boxes(mb, wf, segs, v0, v1, mat, w1=0.04, c=0.0):
    for (a, b) in segs:
        wf.box(mb, a, b, v0, v1, 0.0, w1, mat, c=c)


@asset('bld_diner', 'Roadside diner (16x7 m, flat roof, neon sign)', x=166.0, ext=(-5.5, 6.5), group='roadside', budget=16000, collision='box',
       tags=['roadside', 'usa', 'town'], scale=(0.9, 1.15), usage='Roadside diner, glazed front on +X, rooftop neon sign board')
def diner(mb):
    x0, x1, y0, y1 = -3.5, 3.5, -8.0, 8.0
    zb = 0.3; eave = 3.5; t = 0.28
    poly = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    wv0, wv1 = 0.95, 2.55
    left = [(0.8, 2.8), (3.1, 5.1), (5.4, 6.7)]
    right = [(16.0 - b, 16.0 - a) for (a, b) in left][::-1]
    door = (7.2, 8.8)
    opens = {1: [(a, b, wv0, wv1) for (a, b) in left + right] + [(door[0], door[1], zb, zb + 2.25)],
             0: [(1.2, 2.8, wv0, wv1), (4.2, 5.8, wv0, wv1)], 2: [(1.2, 2.8, wv0, wv1), (4.2, 5.8, wv0, wv1)],
             3: [(2.5, 3.7, zb, zb + 2.1), (9.0, 10.6, wv0, wv1), (12.4, 14.0, wv0, wv1)]}
    wfs, convex = house_walls(mb, poly, zb, eave, t, opens, 'M_Bld_PaintWhite')
    plinth(mb, poly, zb, 0.04, mat='M_Bld_Stone')
    E = wfs[1]
    for (a, b) in left + right:
        window_unit(mb, E, a, b, wv0, wv1, t, frame='M_Bld_Metal', shutters=None, sill=False, lintel=None, panes=(3, 1))
    for e in (0, 2):
        for (a, b) in ((1.2, 2.8), (4.2, 5.8)):
            window_unit(mb, wfs[e], a, b, wv0, wv1, t, frame='M_Bld_Metal', shutters=None, sill=False, lintel=None, panes=(2, 1))
    for (a, b) in ((9.0, 10.6), (12.4, 14.0)):
        window_unit(mb, wfs[3], a, b, wv0, wv1, t, frame='M_Bld_Metal', shutters=None, sill=False, lintel=None, panes=(2, 1))
    # double glass door
    dl = -t * 0.45
    for (a, b) in ((door[0] + 0.03, 8.0 - 0.02), (8.0 + 0.02, door[1] - 0.03)):
        E.box(mb, a, b, zb, zb + 2.22, dl, dl + 0.05, 'M_Bld_Metal')
        E.box(mb, a + 0.08, b - 0.08, zb + 0.2, zb + 2.1, dl + 0.02, dl + 0.06, 'M_Bld_Window')
        E.box(mb, b - 0.18 if a < 8 else a + 0.1, b - 0.14 if a < 8 else a + 0.14, zb + 0.9, zb + 1.5, dl + 0.05, dl + 0.12, 'M_Bld_Metal')
    # red apron + steel trim bands per wall (door gap kept free)
    for e, wf in enumerate(wfs):
        ua = t if convex[e] else 0.0
        segs = [(ua, wf.L)]
        if e == 1:
            segs = [(t, door[0]), (door[1], wf.L)]
        elif e == 3:
            segs = [(ua, 2.5), (3.7, wf.L)]
        wall_boxes(mb, wf, segs, zb, wv0 - 0.12, 'M_Bld_PaintRed', 0.05, c=0.008)
        wall_boxes(mb, wf, [(ua, wf.L)], wv0 - 0.12, wv0 - 0.06, 'M_Bld_Metal', 0.06)
        wall_boxes(mb, wf, [(ua, wf.L)], eave - 0.5, eave - 0.44, 'M_Bld_Metal', 0.06)
        wall_boxes(mb, wf, [(ua, wf.L)], eave - 0.42, eave - 0.14, 'M_Bld_PaintRed', 0.05)
    for (cx, cy) in poly:
        mb.box((cx - 0.12, cy - 0.12, zb), (cx + 0.12, cy + 0.12, eave), 'M_Bld_Metal', c=0.03)
    # roof slab + parapet
    mb.box((x0 - 0.45, y0 - 0.45, eave), (x1 + 0.45, y1 + 0.45, eave + 0.2), 'M_Bld_PaintWhite', c=0.03)
    pl = Plane((0, 0, 0), (1, 0, 0), (0, 1, 0))
    mb.ring_prism(pl, offset_poly(poly, 0.45), offset_poly(poly, 0.27), eave + 0.2, eave + 0.55, 'M_Bld_PaintRed')
    # striped awning over the front
    k = 0
    y = y0 + 0.2
    while y < y1 - 0.2:
        w_ = min(0.8, y1 - 0.2 - y)
        m_ = 'M_Bld_PaintRed' if k % 2 == 0 else 'M_Bld_PaintWhite'
        mb.bar((x1 + 0.0, y + w_ / 2, 3.05), (x1 + 1.35, y + w_ / 2, 2.62), w_, 0.05, m_)
        mb.box((x1 + 1.3, y, 2.52), (x1 + 1.38, y + w_, 2.64), m_)
        y += 0.8; k += 1
    for sy in (y0 + 0.3, y1 - 0.3):
        mb.bar((x1 + 1.3, sy, 0.0), (x1 + 1.3, sy, 2.62), 0.07, 0.07, 'M_Bld_Metal')
    # entrance slab
    mb.box((x1, -2.0, 0.0), (x1 + 1.6, 2.0, 0.14), 'M_Bld_Stone', c=0.015)
    # rooftop equipment
    for (ax, ay) in ((-1.5, -5.0), (-1.5, 4.0)):
        mb.box((ax - 0.9, ay - 0.7, eave + 0.2), (ax + 0.9, ay + 0.7, eave + 1.05), 'M_Bld_Metal', c=0.03)
        mb.cyl((ax, ay, eave + 1.05), (ax, ay, eave + 1.1), 0.5, 0.5, 'M_Bld_Rubber', seg=14, smooth=False) if False else None
        mb.lathe([(0.55, eave + 1.05), (0.55, eave + 1.12), (0.0, eave + 1.12)], 'M_Bld_Window', seg=14, center=(ax, ay), smooth=False)
    mb.cyl((-2.5, 0.0, eave + 0.2), (-2.5, 0.0, eave + 1.2), 0.1, 0.1, 'M_Bld_Metal', seg=8)
    mb.cyl((-2.5, 0.0, eave + 1.2), (-2.5, 0.0, eave + 1.45), 0.18, 0.18, 'M_Bld_Metal', seg=8)
    # neon sign board on two posts
    sx = 1.2
    for sy in (-1.9, 1.9):
        mb.box((sx - 0.1, sy - 0.1, eave + 0.2), (sx + 0.1, sy + 0.1, eave + 1.9), 'M_Bld_Metal', c=0.015)
    mb.box((sx - 0.15, -2.6, eave + 1.5), (sx + 0.15, 2.6, eave + 3.5), 'M_Bld_PaintWhite', c=0.03)
    for (a0, a1, b0, b1) in ((-2.7, -2.5, 1.45, 3.55), (2.5, 2.7, 1.45, 3.55)):
        mb.box((sx - 0.2, a0, eave + b0), (sx + 0.2, a1, eave + b1), 'M_Bld_PaintRed', c=0.02)
    for (a0, a1, b0, b1) in ((-2.7, 2.7, 1.4, 1.62), (-2.7, 2.7, 3.38, 3.6)):
        mb.box((sx - 0.2, a0, eave + b0), (sx + 0.2, a1, eave + b1), 'M_Bld_PaintRed', c=0.02)
    # neon border + letters on both faces
    for sgn, ux in ((1, sx + 0.15), (-1, sx - 0.15)):
        plS = Plane((ux, 0, 0), (0, sgn, 0), (0, 0, 1))
        draw_text(mb, plS, 'DINER', 0.0, eave + 2.75, 0.85, 'M_Bld_Neon', w0=0.0, w1=0.06, flat=False, gap=0.14)
        draw_text(mb, plS, 'OPEN 24H', 0.0, eave + 1.95, 0.38, 'M_Bld_Window', w0=0.0, w1=0.04, flat=False, gap=0.14)
        for (a0, a1, b0, b1) in ((-2.35, 2.35, 3.15, 3.2), (-2.35, 2.35, 1.8, 1.85)):
            mb.box((ux * 1.0 - (0.0 if sgn > 0 else 0.05), a0, eave + b0), (ux + (0.05 if sgn > 0 else 0.0), a1, eave + b1), 'M_Bld_Neon')
    # side lamp posts at the entrance
    mb.hull_box((x0, y0, 0.0), (x1, y1, eave + 0.5))
    mb.hull_box((x1, y0, 0.0), (x1 + 1.4, y1, 2.7))
    mb.hull_box((sx - 0.2, -2.7, eave + 0.2), (sx + 0.2, 2.7, eave + 3.55))
    return dict(footprint=[7.0, 16.0], sign='DINER / OPEN 24H (neon relief M_Bld_Neon)')


# ---------------------------------------------------------------------------------------------------------------------
@asset('bld_gas_station', 'Gas station (canopy with 4 pump islands + shop)', x=192.0, ext=(-9.0, 10.5), group='roadside', budget=18000, collision='box',
       tags=['roadside', 'usa', 'highway'], scale=(0.9, 1.15), usage='Canopy over 4 pump islands + small shop (back), price pole at the front-left')
def gas_station(mb):
    # shop (back, -X)
    sx0, sx1, sy0, sy1 = -8.0, -1.5, -4.5, 4.5
    zb = 0.3; eave = 3.4; t = 0.28
    poly = [(sx0, sy0), (sx1, sy0), (sx1, sy1), (sx0, sy1)]
    fv0, fv1 = 0.95, 2.6
    opens = {1: [(0.7, 3.4, fv0, fv1), (3.9, 5.1, zb, zb + 2.25), (5.6, 8.3, fv0, fv1)],
             0: [(1.5, 3.1, 1.2, 2.5), (3.9, 5.5, 1.2, 2.5)], 2: [(1.5, 3.1, 1.2, 2.5), (3.9, 5.5, 1.2, 2.5)],
             3: [(3.8, 5.2, zb, zb + 2.1)]}
    wfs, convex = house_walls(mb, poly, zb, eave, t, opens, 'M_Bld_PaintWhite')
    plinth(mb, poly, zb, 0.04, mat='M_Bld_Stone')
    E = wfs[1]
    for (a, b) in ((0.7, 3.4), (5.6, 8.3)):
        window_unit(mb, E, a, b, fv0, fv1, t, frame='M_Bld_Metal', shutters=None, sill=False, lintel=None, panes=(3, 1))
    for e in (0, 2):
        for (a, b) in ((1.5, 3.1), (3.9, 5.5)):
            window_unit(mb, wfs[e], a, b, 1.2, 2.5, t, frame='M_Bld_Metal', shutters=None, sill=False, lintel=None, panes=(2, 1))
    dl = -t * 0.45
    for (a, b) in ((3.93, 4.5), (4.5, 5.07)):
        E.box(mb, a, b - 0.01, zb, zb + 2.22, dl, dl + 0.05, 'M_Bld_Metal')
        E.box(mb, a + 0.07, b - 0.08, zb + 0.2, zb + 2.1, dl + 0.02, dl + 0.06, 'M_Bld_Window')
    # back door
    wfs[3].box(mb, 3.83, 5.17, zb, zb + 2.05, dl, dl + 0.06, 'M_Bld_Metal')
    for e, wf in enumerate(wfs):
        ua = t if convex[e] else 0.0
        segs = [(ua, wf.L)]
        if e == 1: segs = [(t, 3.9), (5.1, wf.L)]
        elif e == 3: segs = [(ua, 3.8), (5.2, wf.L)]
        wall_boxes(mb, wf, segs, zb, 0.62, 'M_Bld_PaintRed', 0.05, c=0.008)
    mb.box((sx0 - 0.4, sy0 - 0.4, eave), (sx1 + 0.5, sy1 + 0.4, eave + 0.22), 'M_Bld_PaintWhite', c=0.03)
    pl = Plane((0, 0, 0), (1, 0, 0), (0, 1, 0))
    mb.ring_prism(pl, offset_poly([(sx0 - 0.4, sy0 - 0.4), (sx1 + 0.5, sy0 - 0.4), (sx1 + 0.5, sy1 + 0.4), (sx0 - 0.4, sy1 + 0.4)], 0.0),
                  offset_poly([(sx0 - 0.4, sy0 - 0.4), (sx1 + 0.5, sy0 - 0.4), (sx1 + 0.5, sy1 + 0.4), (sx0 - 0.4, sy1 + 0.4)], -0.2), eave + 0.22, eave + 0.6, 'M_Bld_PaintRed')
    # sign on the shop front
    plS = E.plane(0.0)
    draw_text(mb, plS, 'SHOP', 4.5, eave - 0.5, 0.5, 'M_Bld_Neon', w0=0.0, w1=0.05, flat=False, gap=0.14)
    # canopy
    cx0, cx1, cy0, cy1 = 0.2, 8.2, -7.2, 7.2
    ch = 5.0
    mb.box((cx0, cy0, ch), (cx1, cy1, ch + 0.8), 'M_Bld_PaintWhite', c=0.05)
    for (a, b) in ((cy0 - 0.01, cy1 + 0.01),):
        mb.box((cx0 - 0.02, a, ch + 0.28), (cx1 + 0.02, b, ch + 0.5), 'M_Bld_PaintRed')
    mb.box((cx0 + 0.15, cy0 + 0.15, ch + 0.8), (cx1 - 0.15, cy1 - 0.15, ch + 0.88), 'M_Bld_Metal')
    # under-canopy lights (4 strips)
    for yy in (-5.4, -1.8, 1.8, 5.4):
        mb.box((cx0 + 0.9, yy - 0.35, ch - 0.06), (cx1 - 0.9, yy + 0.35, ch), 'M_Bld_Window')
    # columns (4)
    cols = [(1.6, -3.6), (1.6, 3.6), (6.8, -3.6), (6.8, 3.6)]
    for (cx, cy) in cols:
        mb.cyl((cx, cy, 0.0), (cx, cy, ch), 0.3, 0.3, 'M_Bld_PaintWhite', seg=16, smooth=True)
        mb.cyl((cx, cy, 0.0), (cx, cy, 0.25), 0.4, 0.4, 'M_Bld_Stone', seg=16)
        mb.cyl((cx, cy, 1.1), (cx, cy, 1.5), 0.32, 0.32, 'M_Bld_PaintRed', seg=16)
        mb.hull_cyl((cx, cy, 0.0), (cx, cy, ch), 0.32, seg=8)
    # pump islands (4) with 2 pumps each
    for yy in (-5.4, -1.8, 1.8, 5.4):
        mb.box((2.0, yy - 0.5, 0.0), (6.6, yy + 0.5, 0.2), 'M_Bld_Stone', c=0.04)
        for px in (3.2, 5.4):
            mb.box((px - 0.32, yy - 0.2, 0.2), (px + 0.32, yy + 0.2, 1.55), 'M_Bld_PaintWhite', c=0.03)
            mb.box((px - 0.34, yy - 0.22, 1.45), (px + 0.34, yy + 0.22, 1.68), 'M_Bld_PaintRed', c=0.03)
            mb.box((px - 0.36, yy - 0.2, 0.2), (px + 0.36, yy + 0.2, 0.36), 'M_Bld_Metal', c=0.01)
            for sd in (-1, 1):
                mb.box((px - 0.24, yy + sd * 0.205 - (0.0 if sd > 0 else 0.015), 1.05), (px + 0.24, yy + sd * 0.205 + (0.015 if sd > 0 else 0.0), 1.38), 'M_Bld_Window')
                mb.box((px - 0.2, yy + sd * 0.205 - (0.0 if sd > 0 else 0.03), 0.62), (px + 0.2, yy + sd * 0.205 + (0.03 if sd > 0 else 0.0), 0.9), 'M_Bld_Metal')
                mb.tube([Vector((px + 0.2, yy + sd * 0.25, 1.0)), Vector((px + 0.35, yy + sd * 0.42, 0.75)), Vector((px + 0.2, yy + sd * 0.55, 0.45)), Vector((px - 0.05, yy + sd * 0.62, 0.38))],
                        0.022, 'M_Bld_Metal', seg=6)
        for ex in (2.1, 6.5):
            mb.cyl((ex, yy, 0.2), (ex, yy, 0.95), 0.1, 0.1, 'M_Bld_Metal', seg=8)
            mb.cyl((ex, yy, 0.65), (ex, yy, 0.8), 0.105, 0.105, 'M_Bld_PaintRed', seg=8)
    # price pole sign (front-left)
    px, py = 10.0, -8.0
    mb.cyl((px, py, 0.0), (px, py, 7.0), 0.18, 0.18, 'M_Bld_Metal', seg=10)
    mb.box((px - 0.2, py - 1.3, 5.0), (px + 0.2, py + 1.3, 7.4), 'M_Bld_PaintWhite', c=0.04)
    mb.box((px - 0.24, py - 1.36, 6.5), (px + 0.24, py + 1.36, 7.46), 'M_Bld_PaintRed', c=0.03)
    for sgn, ux in ((1, px + 0.24), (-1, px - 0.24)):
        plS = Plane((ux, py, 0), (0, sgn, 0), (0, 0, 1))
        draw_text(mb, plS, 'GAS', 0.0, 6.98, 0.7, 'M_Bld_PaintWhite', w0=0.0, w1=0.05, flat=False, gap=0.14)
    for k in range(3):
        b0 = 5.1 + k * 0.45
        mb.box((px + 0.2, py - 1.0, b0), (px + 0.27, py + 1.0, b0 + 0.34), 'M_Bld_Window')
        mb.box((px - 0.27, py - 1.0, b0), (px - 0.2, py + 1.0, b0 + 0.34), 'M_Bld_Window')
    # collision
    mb.hull_box((sx0, sy0, 0.0), (sx1, sy1, eave + 0.3))
    mb.hull_box((cx0, cy0, ch), (cx1, cy1, ch + 0.9))
    mb.hull_cyl((px, py, 0.0), (px, py, 7.4), 0.25, seg=8)
    shift_all(mb, dx=-0.9, dy=0.45)
    return dict(footprint=[16.0, 14.4], pumps=8, islands=4)


# ---------------------------------------------------------------------------------------------------------------------
@asset('bld_chalet', 'Mountain chalet / ski lodge (10x9 m, timber, steep roof)', x=218.0, ext=(-8.0, 8.5), group='alpine', budget=22000, collision='box',
       tags=['alpine', 'snow', 'mountain'], scale=(0.9, 1.2), usage='Timber chalet, gable and balcony face +X, stone ground floor')
def chalet(mb):
    poly = [(-5.0, -4.5), (5.0, -4.5), (5.0, 4.5), (-5.0, 4.5)]
    z1 = 2.9; eave = 5.6
    shingle = (0.55, 0.5, 0.46, 1)
    opens_lo = {1: [(3.75, 5.25, ZB, ZB + 2.2)], 0: [(2.0, 3.2, 1.1, 2.1), (6.8, 8.0, 1.1, 2.1)], 2: [(2.0, 3.2, 1.1, 2.1), (6.8, 8.0, 1.1, 2.1)],
                3: [(3.4, 4.6, 1.1, 2.1)]}
    wfl, cvl = house_walls(mb, poly, ZB, z1, 0.45, opens_lo, 'M_Bld_Stone')
    plinth(mb, poly, ZB, 0.07)
    door_unit(mb, wfl[1], 3.75, 5.25, ZB, ZB + 2.2, 0.45, steps=True, frame='M_Bld_Wood')
    for e, lst in opens_lo.items():
        if e == 1: continue
        for (a, b, v0, v1) in lst:
            window_unit(mb, wfl[e], a, b, v0, v1, 0.45, frame='M_Bld_Wood', shutters=None, panes=(2, 2))
    # timber upper floor
    opens_up = {1: [(0.9, 2.2, z1 + 0.95, z1 + 2.15), (6.8, 8.1, z1 + 0.95, z1 + 2.15), (3.6, 5.4, z1 + 0.15, z1 + 2.3)],
                0: [(1.8, 3.1, z1 + 0.95, z1 + 2.1), (6.9, 8.2, z1 + 0.95, z1 + 2.1)], 2: [(1.8, 3.1, z1 + 0.95, z1 + 2.1), (6.9, 8.2, z1 + 0.95, z1 + 2.1)],
                3: [(3.4, 4.6, z1 + 0.95, z1 + 2.1)]}
    wfu, cvu = house_walls(mb, poly, z1, eave, 0.35, opens_up, 'M_Bld_Wood', col=(0.9, 0.9, 0.9, 1))
    band(mb, poly, z1 - 0.12, 0.24, 0.1, mat='M_Bld_Wood')
    for e, lst in opens_up.items():
        for (a, b, v0, v1) in lst:
            if e == 1 and b - a > 1.5:
                window_unit(mb, wfu[e], a, b, v0, v1, 0.35, frame='M_Bld_Wood', shutters=None, sill=False, lintel=None, panes=(2, 3))
            else:
                window_unit(mb, wfu[e], a, b, v0, v1, 0.35, frame='M_Bld_Wood', shutters='M_Bld_Wood', panes=(2, 2), lintel=None)
    # log courses
    for e, wf in enumerate(wfu):
        holes = [(a - 0.2, b + 0.2, v0 - 0.2, v1 + 0.2) for (a, b, v0, v1) in opens_up.get(e, [])]
        v = z1 + 0.18
        k = 0
        while v + 0.12 < eave:
            strips(mb, wf, 0.45 if cvu[e] else 0.1, wf.L - 0.1, v, v + 0.12, holes, 'M_Bld_Wood', 0.0, 0.05, c=0.02, col=(0.78, 0.72, 0.7, 1))
            v += 0.3; k += 1
    # corner log ends
    for i, (cx, cy) in enumerate(poly):
        v = z1 + 0.25; k = 0
        while v < eave - 0.15:
            sx = 1 if cx > 0 else -1; sy = 1 if cy > 0 else -1
            if k % 2 == 0:
                mb.cyl((cx - sx * 0.35, cy, v), (cx + sx * 0.14, cy, v), 0.12, 0.12, 'M_Bld_Wood', seg=8)
            else:
                mb.cyl((cx, cy - sy * 0.35, v), (cx, cy + sy * 0.14, v), 0.12, 0.12, 'M_Bld_Wood', seg=8)
            v += 0.3; k += 1
    # gable end (front, +X) timber with vertical boards + attic window; rear gable plain
    pitch = 48
    rise = 4.5 * tan(radians(pitch))
    gable_fill(mb, wfu[1], 0.0, 9.0, eave, rise, 0.35, 'M_Bld_Wood', col=(0.9, 0.9, 0.9, 1))
    gable_fill(mb, wfu[3], 0.0, 9.0, eave, rise, 0.35, 'M_Bld_Wood', col=(0.9, 0.9, 0.9, 1))
    for wf in (wfu[1], wfu[3]):
        u = 0.35
        while u < 8.7:
            hgt = rise * (1 - abs(u - 4.5) / 4.5) - 0.12
            if hgt > 0.3:
                wf.box(mb, u - 0.03, u + 0.03, eave, eave + hgt, 0.0, 0.03, 'M_Bld_Wood', col=(0.75, 0.7, 0.68, 1))
            u += 0.4
    gable_window(mb, wfu[1], 4.5, eave + 1.6, 1.0, 1.2)
    gable_window(mb, wfu[3], 4.5, eave + 1.6, 0.8, 1.0)
    # balcony on the front (+X) at upper floor level
    bx = 5.0
    mb.box((bx, -4.9, z1 - 0.12), (bx + 1.7, 4.9, z1 + 0.08), 'M_Bld_Wood', c=0.02)
    for k in range(10):
        mb.box((bx + 0.02, -4.7 + k * 0.94, z1 + 0.08), (bx + 1.66, -4.7 + k * 0.94 + 0.88, z1 + 0.11), 'M_Bld_Wood', col=(0.9, 0.85, 0.8, 1))
    for sy in (-4.75, 4.75):
        mb.box((bx + 1.5, sy - 0.07, z1 + 0.08), (bx + 1.64, sy + 0.07, z1 + 1.15), 'M_Bld_Wood')
    mb.box((bx + 1.46, -4.85, z1 + 1.05), (bx + 1.68, 4.85, z1 + 1.15), 'M_Bld_Wood', c=0.02)
    mb.box((bx + 1.52, -4.8, z1 + 0.15), (bx + 1.62, 4.8, z1 + 0.22), 'M_Bld_Wood')
    for sx_ in (bx, bx + 1.7 - 0.0):
        pass
    for side in (-1, 1):
        y = 0.0
        yy = 0.3
        while yy < 4.8:
            mb.box((bx + 1.54, side * yy - 0.025, z1 + 0.22), (bx + 1.6, side * yy + 0.025, z1 + 1.05), 'M_Bld_Wood')
            yy += 0.26
    mb.box((bx + 1.46, -0.3, z1 + 0.15), (bx + 1.66, 0.3, z1 + 0.22), 'M_Bld_Wood') if False else None
    for sy in (-4.7, 0.0, 4.7):
        mb.box((bx + 1.55 - 0.1, sy - 0.1, 0.0), (bx + 1.55 + 0.1, sy + 0.1, z1 - 0.12), 'M_Bld_Wood', c=0.01)
        mb.box((bx + 1.55 - 0.15, sy - 0.15, 0.0), (bx + 1.55 + 0.15, sy + 0.15, 0.25), 'M_Bld_Stone')
        mb.bar((bx + 1.5, sy, z1 - 0.9), (bx + 0.35, sy, z1 - 0.12), 0.1, 0.08, 'M_Bld_Wood')
    # roof (steep, deep overhang over the balcony)
    rz, _ = gable_wing(mb, -5.0, 5.0, -4.5, 4.5, eave, pitch, 'x', ov_e=1.2, ov_g0=0.9, ov_g1=2.3, col=shingle, course=0.28)
    for sy in (-4.75, 4.75):
        mb.box((bx + 1.55 - 0.08, sy - 0.08, z1 + 0.08), (bx + 1.55 + 0.08, sy + 0.08, eave - 0.3), 'M_Bld_Wood')
    chimney(mb, -2.4, 0.0, eave + 1.0, rz + 1.1, 0.9, 1.0, 'M_Bld_Stone')
    # collision
    mb.hull_box((-5.0, -4.5, 0.0), (5.0, 4.5, z1))
    mb.hull_box((-5.0, -4.5, z1), (5.0, 4.5, eave))
    ov = 1.2; tn = tan(radians(pitch))
    mb.hull_pts([(-5.9, -4.5 - ov, eave - ov * tn), (-5.9, 4.5 + ov, eave - ov * tn), (-5.9, 0, rz + 0.1), (7.3, -4.5 - ov, eave - ov * tn), (7.3, 4.5 + ov, eave - ov * tn), (7.3, 0, rz + 0.1)])
    mb.hull_box((bx, -4.9, 0.0), (bx + 1.7, 4.9, z1 + 0.1))
    shift_all(mb, dx=-0.9)
    return dict(footprint=[10.0, 9.0], balcony=True)
