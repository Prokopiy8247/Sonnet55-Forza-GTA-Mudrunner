# -*- coding: utf-8 -*-
"""Settlements kit - harbour hut, pier segment, rowing boat, fishing boat. exec'd into the kit namespace by settlements_kit.py"""


@asset('bld_harbour_hut', 'Harbour fisherman hut (5x4 m)', x=240.0, ext=(-4.0, 4.5), group='harbour', budget=12000, collision='box',
       tags=['coast', 'harbour', 'fishing'], scale=(0.9, 1.2), usage='Weathered timber hut with metal roof, door on +X; props (crates, barrels, rope) included')
def harbour_hut(mb):
    poly = [(-2.5, -2.0), (2.5, -2.0), (2.5, 2.0), (-2.5, 2.0)]
    eave = 2.6; t = 0.22
    opens = {1: [(0.5, 1.5, 1.1, 2.0), (2.4, 3.4, ZB, ZB + 2.0)], 0: [(2.0, 3.1, 1.2, 2.0)], 2: [(2.0, 3.1, 1.2, 2.0)], 3: [(1.5, 2.5, 1.2, 2.0)]}
    wfs, convex = house_walls(mb, poly, ZB, eave, t, opens, 'M_Bld_Wood', col=(0.82, 0.8, 0.78, 1))
    plinth(mb, poly, ZB, 0.05)
    E = wfs[1]
    window_unit(mb, E, 0.5, 1.5, 1.1, 2.0, t, frame='M_Bld_PaintBlue', shutters='M_Bld_PaintBlue', lintel=None, panes=(2, 2))
    door_unit(mb, E, 2.4, 3.4, ZB, ZB + 2.0, t, leaf='M_Bld_PaintBlue', frame='M_Bld_Wood', steps=True)
    for e in (0, 2):
        window_unit(mb, wfs[e], 2.0, 3.1, 1.2, 2.0, t, frame='M_Bld_PaintBlue', shutters=None, lintel=None, panes=(2, 2))
    window_unit(mb, wfs[3], 1.5, 2.5, 1.2, 2.0, t, frame='M_Bld_PaintBlue', shutters='M_Bld_PaintBlue', lintel=None, panes=(2, 2))
    for e, wf in enumerate(wfs):
        holes = [(a - 0.1, b + 0.1, v0 - 0.1, v1 + 0.1) for (a, b, v0, v1) in opens.get(e, [])]
        u = 0.45
        while u < wf.L - 0.3:
            if not any(h[0] < u < h[1] for h in holes):
                wf.box(mb, u - 0.04, u + 0.04, ZB, eave, 0.0, 0.03, 'M_Bld_Wood', col=(0.65, 0.62, 0.6, 1))
            u += 0.5
    # gabled corrugated roof (ridge along Y), 24 deg
    rz, _ = gable_wing(mb, -2.5, 2.5, -2.0, 2.0, eave, 24, 'y', mat='M_Bld_Metal', trim='M_Bld_Wood', ov_e=0.65, ov_g0=0.35, ov_g1=0.35, course=0.45)
    mb.hull_box((-2.5, -2.0, 0.0), (2.5, 2.0, eave))
    mb.hull_pts([(-3.15, -2.35, eave - 0.3), (3.15, -2.35, eave - 0.3), (0, -2.35, rz + 0.1), (-3.15, 2.35, eave - 0.3), (3.15, 2.35, eave - 0.3), (0, 2.35, rz + 0.1)])
    chimney(mb, -1.2, 0.8, eave - 0.2, rz + 0.9, 0.35, 0.35, 'M_Bld_Metal', cap=False)
    # props: crates, barrels, rope coil
    for (cx, cy, z0_, z1_) in ((3.3, -1.5, 0.0, 0.45), (3.3, -0.9, 0.0, 0.45), (3.35, -1.2, 0.45, 0.9)):
        mb.box((cx - 0.3, cy - 0.28, z0_), (cx + 0.3, cy + 0.28, z1_), 'M_Bld_Wood', c=0.015, col=(0.9, 0.88, 0.85, 1))
    for (bx, by) in ((3.35, 1.7), (3.95, 1.45), (3.2, 2.25)):
        mb.cyl((bx, by, 0.0), (bx, by, 0.85), 0.3, 0.3, 'M_Bld_Wood', seg=12, smooth=False)
        for hz in (0.12, 0.42, 0.72):
            mb.cyl((bx, by, hz - 0.03), (bx, by, hz + 0.03), 0.315, 0.315, 'M_Bld_Metal', seg=12, smooth=False)
    mb.torus((3.6, 0.45, 0.1), 0.3, 0.07, 'M_Bld_Wood', nmaj=14, nmin=6)
    mb.torus((3.6, 0.45, 0.22), 0.27, 0.07, 'M_Bld_Wood', nmaj=14, nmin=6)
    mb.bar((2.55, -1.95, 0.0), (2.55, -1.95, 2.4), 0.1, 0.1, 'M_Bld_Wood')
    shift_all(mb, dx=-0.6)
    return dict(footprint=[5.0, 4.0])


# ---------------------------------------------------------------------------------------------------------------------
@asset('bld_pier_4m', 'Pier segment (4 m, tileable along +X)', x=256.0, ext=(0.0, 4.0), group='harbour', budget=7000, collision='box', pivot='water_start',
       tags=['coast', 'harbour', 'tileable'], scale=(1.0, 1.0), usage='Tileable pier segment: starts at x=0 on the centreline, runs 4 m along +X; z=0 = water surface, deck top at z=1.25')
def pier(mb):
    L = 4.0; hw = 1.2; zd = 1.25
    for sy in (-hw + 0.2, 0.0, hw - 0.2):
        mb.box((0.0, sy - 0.09, zd - 0.42), (L, sy + 0.09, zd - 0.05), 'M_Bld_Wood', c=0.012)
    n = 20
    for k in range(n):
        x = k * L / n
        mb.box((x + 0.01, -hw, zd - 0.05), (x + L / n - 0.01, hw, zd), 'M_Bld_Wood', c=0.01, col=mb.tint(0.18))
    for sy in (-hw - 0.05, hw + 0.05):
        mb.box((0.0, sy - 0.07, zd - 0.28), (L, sy + 0.07, zd + 0.06), 'M_Bld_Wood', c=0.015)
    for px in (1.0, 3.0):
        for sy in (-hw + 0.1, hw - 0.1):
            mb.cyl((px, sy, -1.8), (px, sy, zd + 0.95), 0.17, 0.15, 'M_Bld_Wood', seg=10, smooth=True)
            mb.cyl((px, sy, zd + 0.93), (px, sy, zd + 0.98), 0.17, 0.17, 'M_Bld_Metal', seg=10)
            mb.hull_cyl((px, sy, -1.8), (px, sy, zd + 0.95), 0.17, seg=6)
        mb.bar((px, -hw + 0.1, 0.55), (px, hw - 0.1, 0.55), 0.14, 0.1, 'M_Bld_Wood')
        mb.bar((px, -hw + 0.1, -0.2), (px, hw - 0.1, 0.55), 0.1, 0.08, 'M_Bld_Wood')
        mb.bar((px, hw - 0.1, -0.2), (px, -hw + 0.1, 0.55), 0.1, 0.08, 'M_Bld_Wood')
    for sy in (-hw + 0.25, hw - 0.25):
        mb.cyl((2.0, sy, zd), (2.0, sy, zd + 0.38), 0.11, 0.11, 'M_Bld_Metal', seg=10)
        mb.cyl((2.0, sy, zd + 0.34), (2.0, sy, zd + 0.46), 0.17, 0.17, 'M_Bld_Metal', seg=10)
    rope = [(0.0, 1.95), (0.5, 1.85), (1.0, 2.05), (1.5, 1.9), (2.0, 1.86), (2.5, 1.9), (3.0, 2.05), (3.5, 1.85), (4.0, 1.95)]
    for sy in (-hw + 0.1, hw - 0.1):
        mb.tube([Vector((x, sy, z)) for (x, z) in rope], 0.025, 'M_Bld_Wood', seg=6, caps=True)
    mb.hull_box((0.0, -hw - 0.1, zd - 0.45), (L, hw + 0.1, zd + 0.06))
    return dict(length=L, width=2 * hw, deck_z=zd, water_z=0.0)


# ---------------------------------------------------------------------------------------------------------------------
def _sec_half(b, zk, zs, m, lap=0.0):
    pts = []
    for k in range(m + 1):
        a = (pi / 2) * k / m
        y = b * sin(a)
        if lap and 0 < k < m and k % 2 == 1:
            y += lap
        pts.append((y, zk + (zs - zk) * (1 - cos(a))))
    return pts      # keel -> sheer (y >= 0)


def _row_shape(s, B, D):
    a = abs(s)
    if s >= 0:
        b = max(0.045, B / 2 * max(0.0, 1 - a ** 2.3) ** 0.55)
    else:
        b = B / 2 * (0.5 + 0.5 * max(0.0, 1 - a ** 2.2) ** 0.7)
    zs = D * (0.88 + 0.42 * s * s)
    zk = D * 0.5 * max(0.0, (a - 0.4) / 0.6) ** 2 * (1.0 if s > 0 else 0.55)
    return b, zk, zs


@asset('bld_boat_row', 'Rowing boat (3.8 m, clinker)', x=270.0, ext=(-2.2, 2.2), group='harbour', budget=9000, collision='convex', pivot='ground_centre',
       tags=['coast', 'lake', 'harbour'], scale=(0.9, 1.2), usage='Clinker rowing boat, bow on +X, keel at z=0 (waterline ~ z=0.15)')
def boat_row(mb):
    L = 3.8; B = 1.42; D = 0.55; N = 18; m = 8; th = 0.028
    rings = []
    for i in range(N + 1):
        s = -1 + 2.0 * i / N
        x = s * L / 2
        b, zk, zs = _row_shape(s, B, D)
        ho = _sec_half(b, zk, zs, m, lap=0.011)
        hi = _sec_half(max(b - th, 0.004), zk + th, zs, m)
        out = [Vector((x, y, z)) for (y, z) in reversed(ho)] + [Vector((x, -y, z)) for (y, z) in ho[1:]]
        inn = [Vector((x, -y, z)) for (y, z) in reversed(hi)] + [Vector((x, y, z)) for (y, z) in hi[1:]]
        rings.append(out + inn)
    nout = 2 * m + 1
    cm = ['M_Bld_PaintBlue'] * (nout - 1) + ['M_Bld_Wood'] * (len(rings[0]) - (nout - 1))
    mb.loft(rings, 'M_Bld_Wood', True, False, cap0=True, cap1=True, cap_tri=True, col_mats=cm)
    for sg in (1, -1):
        path = []
        for i in range(N + 1):
            s = -1 + 2.0 * i / N
            b, zk, zs = _row_shape(s, B, D)
            path.append(Vector((s * L / 2, sg * (b - th * 0.5), zs + 0.015)))
        mb.sweep([(-0.03, 0.0), (0.03, 0.0), (0.03, 0.035), (-0.03, 0.035)], path, 'M_Bld_Wood', True, False, cap0=True, cap1=True)
    for xt, wdt in ((-0.95, 0.30), (-0.05, 0.26), (0.85, 0.26)):
        b, zk, zs = _row_shape(xt / (L / 2), B, D)
        bb = b - th - 0.015
        zt = zs - 0.17
        mb.box((xt - wdt / 2, -bb, zt), (xt + wdt / 2, bb, zt + 0.035), 'M_Bld_Wood', c=0.008)
        for sg in (-1, 1):
            mb.box((xt - 0.04, min(sg * bb, sg * (bb - 0.07)), zt - 0.12), (xt + 0.04, max(sg * bb, sg * (bb - 0.07)), zt), 'M_Bld_Wood')
    for k in range(5):
        xf = -0.9 + k * 0.42
        mb.box((xf, -0.2, th + 0.005), (xf + 0.38, 0.2, th + 0.035), 'M_Bld_Wood', c=0.006)
    b, zk, zs = _row_shape(-0.92, B, D)
    mb.box((-1.72, -(b - th - 0.02), zs - 0.2), (-1.45, (b - th - 0.02), zs - 0.15), 'M_Bld_Wood', c=0.008)
    for sg in (-1, 1):
        b, zk, zs = _row_shape(-0.05 / (L / 2), B, D)
        mb.cyl((-0.1, sg * (b - th * 0.5), zs), (-0.1, sg * (b - th * 0.5), zs + 0.16), 0.014, 0.014, 'M_Bld_Metal', seg=6)
        mb.cyl((-0.1, sg * (b - th * 0.5 - 0.07), zs), (-0.1, sg * (b - th * 0.5 - 0.07), zs + 0.16), 0.014, 0.014, 'M_Bld_Metal', seg=6)
        y0_ = sg * 0.26
        mb.cyl((-1.3, y0_, zs - 0.11), (0.95, y0_ * 0.9, zs - 0.13), 0.022, 0.022, 'M_Bld_Wood', seg=8)
        mb.box((0.95, y0_ * 0.9 - 0.07, zs - 0.15), (1.55, y0_ * 0.9 + 0.07, zs - 0.12), 'M_Bld_Wood', c=0.01)
    mb.torus((1.93, 0.0, 0.48), 0.04, 0.012, 'M_Bld_Metal', nmaj=10, nmin=5, axis='X')
    pts = []
    for i in range(0, N + 1, 2):
        s = -1 + 2.0 * i / N
        b, zk, zs = _row_shape(s, B, D)
        pts += [(s * L / 2, b, zs), (s * L / 2, -b, zs), (s * L / 2, b * 0.6, zk), (s * L / 2, -b * 0.6, zk)]
    mb.hull_pts(pts[:32])
    return dict(length=L, beam=B, waterline_z=0.16)


# ---------------------------------------------------------------------------------------------------------------------
def _fish_shape(s, B, D):
    a = abs(s)
    if s >= 0:
        b = max(0.06, B / 2 * max(0.0, 1 - a ** 2.4) ** 0.6)
    else:
        b = B / 2 * (0.80 + 0.20 * max(0.0, 1 - a ** 2.2) ** 0.8)
    zs = D * (0.86 + 0.34 * s * s)
    zk = D * 0.55 * max(0.0, (s - 0.35) / 0.65) ** 2 if s > 0 else D * 0.16 * max(0.0, (a - 0.5) / 0.5) ** 2
    return b, zk, zs


@asset('bld_boat_fishing_8m', 'Fishing boat (8 m)', x=284.0, ext=(-5.0, 5.0), group='harbour', budget=16000, collision='convex', pivot='ground_centre',
       tags=['coast', 'harbour', 'fishing'], scale=(0.9, 1.25), usage='Small trawler, bow on +X, keel at z=0 (waterline ~ z=0.75)')
def boat_fishing(mb):
    L = 8.2; B = 2.9; D = 1.55; N = 20; m = 8
    rings = []
    for i in range(N + 1):
        s = -1 + 2.0 * i / N
        x = s * L / 2
        b, zk, zs = _fish_shape(s, B, D)
        h = _sec_half(b, zk, zs, m)
        out = [Vector((x, y, z)) for (y, z) in reversed(h)] + [Vector((x, -y, z)) for (y, z) in h[1:]]
        rings.append(out)
    n = len(rings[0])
    cm = []
    for e in range(n):
        if e == 2 * m:
            cm.append('M_Bld_Wood')
        else:
            k = min(e, 2 * m - 1 - e)
            cm.append('M_Bld_PaintWhite' if k < 2 else ('M_Bld_PaintRed' if k == 2 else 'M_Bld_PaintBlue'))
    mb.loft(rings, 'M_Bld_PaintBlue', True, False, cap0=True, cap1=True, cap_tri=True, col_mats=cm)

    def dz(x):
        return _fish_shape(x / (L / 2), B, D)[2]

    for sg in (1, -1):
        path = []
        for i in range(N + 1):
            s = -1 + 2.0 * i / N
            b, zk, zs = _fish_shape(s, B, D)
            path.append(Vector((s * L / 2, sg * (b - 0.04), zs - 0.02)))
        mb.sweep([(-0.045, 0.0), (0.045, 0.0), (0.045, 0.5), (-0.045, 0.5)], path, 'M_Bld_PaintWhite', True, False, cap0=True, cap1=True)
        mb.sweep([(-0.06, 0.5), (0.06, 0.5), (0.06, 0.56), (-0.06, 0.56)], path, 'M_Bld_Wood', True, False, cap0=True, cap1=True)
    b, zk, zs = _fish_shape(-1.0, B, D)
    mb.box((-L / 2 - 0.04, -b, zs - 0.02), (-L / 2 + 0.06, b, zs + 0.5), 'M_Bld_PaintWhite')
    mb.box((-L / 2 - 0.06, -b, zs + 0.5), (-L / 2 + 0.08, b, zs + 0.56), 'M_Bld_Wood')
    # wheelhouse
    zc = dz(1.3)
    mb.obox((1.3, 0.0, zc + 1.05), (2.2, 2.1, 2.1), 'M_Bld_PaintWhite', None, 0.05)
    mb.obox((1.3, 0.0, zc + 2.16), (2.5, 2.35, 0.12), 'M_Bld_PaintRed', None, 0.03)
    for k in range(3):
        yy = -0.72 + k * 0.72
        mb.box((2.4, yy - 0.29, zc + 1.2), (2.44, yy + 0.29, zc + 1.95), 'M_Bld_Window')
    for sg in (-1, 1):
        for xx in (0.8, 1.55):
            mb.box((xx - 0.3, min(sg * 1.05, sg * 1.09), zc + 1.2), (xx + 0.3, max(sg * 1.05, sg * 1.09), zc + 1.95), 'M_Bld_Window')
    mb.box((0.15, -0.4, zc + 0.05), (0.22, 0.4, zc + 1.8), 'M_Bld_PaintRed')
    mb.cyl((0.55, 0.0, zc + 2.2), (0.55, 0.0, zc + 3.2), 0.22, 0.2, 'M_Bld_PaintWhite', seg=12)
    mb.cyl((0.55, 0.0, zc + 3.0), (0.55, 0.0, zc + 3.25), 0.225, 0.225, 'M_Bld_PaintRed', seg=12)
    mb.cyl((1.7, 0.0, zc + 2.2), (1.7, 0.0, zc + 4.9), 0.06, 0.04, 'M_Bld_Metal', seg=8)
    mb.box((1.62, -0.55, zc + 4.2), (1.78, 0.55, zc + 4.26), 'M_Bld_Metal')
    mb.cyl((1.7, 0.0, zc + 4.9), (1.7, 0.0, zc + 5.4), 0.012, 0.01, 'M_Bld_Metal', seg=5)
    # stern gantry + winch
    zg = dz(-3.0)
    for sg in (-1, 1):
        mb.bar((-3.35, sg * 0.95, zg), (-3.0, sg * 0.5, zg + 3.1), 0.12, 0.12, 'M_Bld_Metal')
    mb.bar((-3.0, -0.55, zg + 3.08), (-3.0, 0.55, zg + 3.08), 0.14, 0.14, 'M_Bld_Metal')
    zw = dz(-1.7)
    mb.box((-2.3, -0.7, zw), (-1.1, 0.7, zw + 0.35), 'M_Bld_Metal', c=0.02)
    mb.cyl((-1.7, -0.62, zw + 0.7), (-1.7, 0.62, zw + 0.7), 0.4, 0.4, 'M_Bld_Metal', seg=14)
    for yy in (-0.66, 0.66):
        mb.cyl((-1.7, yy - 0.03, zw + 0.7), (-1.7, yy + 0.03, zw + 0.7), 0.5, 0.5, 'M_Bld_PaintRed', seg=14)
    for (cx, cy, zl) in ((-3.4, -0.95, 0), (-3.4, -0.25, 0), (-3.4, 0.45, 0), (-3.4, -0.6, 1), (-3.4, 0.1, 1)):
        zb_ = dz(cx) + zl * 0.34
        mb.box((cx - 0.3, cy - 0.28, zb_), (cx + 0.3, cy + 0.28, zb_ + 0.32), 'M_Bld_Wood', c=0.015, col=(0.9, 0.88, 0.85, 1))
    for sg in (-1, 1):
        for bx in (-3.8, 3.0):
            b, zk, zs = _fish_shape(bx / (L / 2), B, D)
            mb.cyl((bx, sg * (b - 0.25), zs), (bx, sg * (b - 0.25), zs + 0.26), 0.07, 0.07, 'M_Bld_Metal', seg=8)
    mb.torus((1.3, 1.06, zc + 1.6), 0.26, 0.06, 'M_Bld_PaintRed', nmaj=14, nmin=6, axis='Y')
    mb.box((3.9, -0.05, dz(3.9) - 0.1), (4.2, 0.05, dz(3.9) + 0.65), 'M_Bld_Wood')
    pts = []
    for i in range(0, N + 1, 2):
        s = -1 + 2.0 * i / N
        b, zk, zs = _fish_shape(s, B, D)
        pts += [(s * L / 2, b, zs), (s * L / 2, -b, zs), (s * L / 2, b * 0.55, zk + 0.05), (s * L / 2, -b * 0.55, zk + 0.05)]
    mb.hull_pts(pts[:32])
    mb.hull_box((0.2, -1.0, zc), (2.4, 1.0, zc + 2.2))
    return dict(length=L, beam=B, waterline_z=0.75)
