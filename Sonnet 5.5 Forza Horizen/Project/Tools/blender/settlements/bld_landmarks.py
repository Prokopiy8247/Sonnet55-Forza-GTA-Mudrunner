# -*- coding: utf-8 -*-
"""Settlements kit - lighthouse, windmill (+ separate blades), wind turbine (+ separate rotor). exec'd into the kit namespace."""


def radial_box(mb, ang_deg, r, z, size, mat, c=0.0, col=None):
    """box on a cylinder surface: size = (radial, tangential, height); centre at radius r, angle ang_deg."""
    a = radians(ang_deg)
    mb.obox((r * cos(a), r * sin(a), z), size, mat, (0, 0, ang_deg), c, col=col)


def ring_pts(r, z, n, cx=0.0, cy=0.0, start=0.0):
    return [(cx + r * cos(start + 2 * pi * i / n), cy + r * sin(start + 2 * pi * i / n), z) for i in range(n)]


# ---------------------------------------------------------------------------------------------------------------------
@asset('bld_lighthouse', 'Lighthouse (22 m, white/red, lantern room)', x=302.0, ext=(-4.4, 4.4), group='landmark', budget=14000, collision='convex',
       tags=['coast', 'landmark', 'harbour'], scale=(0.8, 1.6), usage='Coastal lighthouse; door on +X; lantern glass uses M_Bld_Window (emissive at night, rotate a light there)')
def lighthouse(mb):
    z0 = 0.8; z1 = 16.4; r0 = 3.4; r1 = 2.15
    rt = lambda z: r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    mb.cyl((0, 0, 0), (0, 0, 0.5), 4.3, 4.2, 'M_Bld_Stone', seg=28, smooth=False)
    mb.cyl((0, 0, 0.5), (0, 0, z0), 3.85, 3.7, 'M_Bld_Stone', seg=28, smooth=False)
    nb = 6
    zs = [z0 + (z1 - z0) * i / nb for i in range(nb + 1)]
    mats = ['M_Bld_PaintWhite' if i % 2 == 0 else 'M_Bld_PaintRed' for i in range(nb)]
    mb.lathe([(rt(z), z) for z in zs], 'M_Bld_PaintWhite', seg=28, smooth=True, row_mats=mats)
    for z in zs[1:-1]:
        mb.cyl((0, 0, z - 0.06), (0, 0, z + 0.06), rt(z) + 0.07, rt(z) + 0.07, 'M_Bld_Stone', seg=28, smooth=False)
    # windows spiralling up the shaft
    for k, ang in enumerate((40, 100, 160, 220, 280, 340)):
        zw = 4.0 + 2.1 * k
        r = rt(zw)
        radial_box(mb, ang, r, zw, (0.14, 0.78, 1.28), 'M_Bld_Stone', c=0.012)
        radial_box(mb, ang, r + 0.045, zw, (0.1, 0.52, 0.98), 'M_Bld_Window')
        radial_box(mb, ang, r + 0.1, zw, (0.03, 0.04, 0.98), 'M_Bld_Stone')
        radial_box(mb, ang, r + 0.08, zw - 0.5, (0.12, 0.92, 0.1), 'M_Bld_Stone')
    # entrance (+X)
    r = rt(2.3)
    radial_box(mb, 0, r, 2.3, (0.3, 2.0, 3.0), 'M_Bld_Stone', c=0.02)
    radial_box(mb, 0, r + 0.05, 2.15, (0.16, 1.45, 2.5), 'M_Bld_Wood', c=0.01)
    radial_box(mb, 0, r + 0.12, 2.15, (0.05, 0.08, 2.45), 'M_Bld_Metal')
    radial_box(mb, 0, r + 0.2, 1.45, (0.7, 2.4, 0.3), 'M_Bld_Stone', c=0.02)
    radial_box(mb, 0, r + 0.55, 1.15, (0.7, 2.8, 0.3), 'M_Bld_Stone', c=0.02)
    # gallery slab with corbels + railing
    mb.lathe([(2.1, z1 - 0.75), (3.25, z1 - 0.25), (3.4, z1 - 0.05), (3.4, z1 + 0.15), (0.0, z1 + 0.15)], 'M_Bld_Stone', seg=28, smooth=False)
    for k in range(28):
        a = 2 * pi * k / 28
        mb.cyl((3.18 * cos(a), 3.18 * sin(a), z1 + 0.15), (3.18 * cos(a), 3.18 * sin(a), z1 + 1.15), 0.03, 0.03, 'M_Bld_Metal', seg=6)
    for zz in (z1 + 1.15, z1 + 0.7):
        mb.torus((0, 0, zz), 3.18, 0.03, 'M_Bld_Metal', nmaj=28, nmin=5)
    # lantern room
    mb.cyl((0, 0, z1 + 0.15), (0, 0, z1 + 0.65), 1.85, 1.8, 'M_Bld_PaintRed', seg=16, smooth=False)
    mb.cyl((0, 0, z1 + 0.65), (0, 0, z1 + 3.0), 1.55, 1.55, 'M_Bld_Window', seg=16, smooth=False)
    for k in range(16):
        a = 360.0 * k / 16
        radial_box(mb, a, 1.58, z1 + 1.82, (0.1, 0.1, 2.38), 'M_Bld_Metal')
    mb.torus((0, 0, z1 + 1.9), 1.56, 0.035, 'M_Bld_Metal', nmaj=16, nmin=5)
    mb.cyl((0, 0, z1 + 1.1), (0, 0, z1 + 2.5), 0.45, 0.45, 'M_Bld_PaintWhite', seg=12)
    mb.cyl((0, 0, z1 + 3.0), (0, 0, z1 + 3.14), 1.98, 1.98, 'M_Bld_Metal', seg=16, smooth=False)
    mb.lathe([(1.9, z1 + 3.14), (1.85, z1 + 3.25), (1.55, z1 + 3.6), (1.1, z1 + 3.95), (0.55, z1 + 4.2), (0.22, z1 + 4.36), (0.0, z1 + 4.42)],
             'M_Bld_PaintRed', seg=16, smooth=True)
    mb.cyl((0, 0, z1 + 4.35), (0, 0, 22.0), 0.05, 0.03, 'M_Bld_Metal', seg=6)
    mb.dome((0, 0, z1 + 4.35), 0.16, 'M_Bld_Metal', seg=8, rings=3, hemi=False, cap=False) if False else None
    mb.cyl((0, 0, 21.5), (0, 0, 21.62), 0.14, 0.14, 'M_Bld_Metal', seg=8)
    mb.hull_pts(ring_pts(4.2, 0.0, 12) + ring_pts(2.25, z1, 12))
    mb.hull_pts(ring_pts(3.4, z1 - 0.3, 12) + ring_pts(1.95, z1 + 3.2, 12) + [(0.0, 0.0, z1 + 4.42)])
    return dict(height=22.0, tower_radius=r0, lantern_z=z1 + 1.8)


# ---------------------------------------------------------------------------------------------------------------------
@asset('bld_windmill', 'Windmill (stone tower + cap, blades separate)', x=320.0, ext=(-4.6, 4.0), group='landmark', budget=14000, collision='convex',
       tags=['rural', 'landmark', 'temperate'], scale=(0.85, 1.4), usage='Stone tower windmill; blades are bld_windmill_blades (pivot at hub, rotate about X); socket blades_hub')
def windmill(mb):
    zb = 0.5; zt = 7.2; r0 = 3.25; r1 = 2.2
    rt = lambda z: r0 + (r1 - r0) * (z - zb) / (zt - zb)
    mb.cyl((0, 0, 0), (0, 0, zb), 3.6, 3.5, 'M_Bld_Stone', seg=24, smooth=False)
    n = 16; dz = (zt - zb) / n
    rz = []
    for i in range(n):
        z = zb + i * dz
        rz += [(rt(z) + 0.02, z), (rt(z + dz) + 0.02, z + dz - 0.05), (rt(z + dz) - 0.01, z + dz - 0.05)]
    rz.append((rt(zt), zt))
    st = len(mb.bm.faces)
    mb.lathe(rz, 'M_Bld_Stone', seg=24, smooth=False)
    mb.speckle(['M_Bld_Stone'], 0.16, start=st)
    # door (+X), windows
    r = rt(1.9)
    radial_box(mb, 0, r, 1.75, (0.3, 1.7, 2.5), 'M_Bld_Stone', c=0.02)
    radial_box(mb, 0, r + 0.05, 1.7, (0.16, 1.2, 2.2), 'M_Bld_Wood', c=0.01)
    radial_box(mb, 0, r + 0.12, 1.7, (0.05, 0.07, 2.15), 'M_Bld_Metal')
    radial_box(mb, 0, r + 0.5, 0.3, (0.9, 2.2, 0.3), 'M_Bld_Stone', c=0.02)
    for ang, zw in ((100, 4.6), (180, 3.9), (260, 4.6), (140, 6.0), (220, 6.0)):
        r = rt(zw)
        radial_box(mb, ang, r, zw, (0.14, 0.7, 1.0), 'M_Bld_Stone', c=0.012)
        radial_box(mb, ang, r + 0.05, zw, (0.1, 0.46, 0.76), 'M_Bld_Window')
        radial_box(mb, ang, r + 0.1, zw, (0.03, 0.03, 0.76), 'M_Bld_Wood')
    # timber gallery
    mb.lathe([(2.7, 3.15), (3.95, 3.15), (3.95, 3.38), (2.7, 3.38)], 'M_Bld_Wood', seg=24, smooth=False)
    for k in range(24):
        a = 2 * pi * k / 24
        mb.cyl((3.8 * cos(a), 3.8 * sin(a), 3.38), (3.8 * cos(a), 3.8 * sin(a), 4.35), 0.04, 0.04, 'M_Bld_Wood', seg=6)
    for zz in (4.35, 3.85):
        mb.torus((0, 0, zz), 3.8, 0.035, 'M_Bld_Wood', nmaj=24, nmin=5)
    for k in range(8):
        a = 2 * pi * (k + 0.5) / 8
        mb.bar((r0 * 0.78 * cos(a), r0 * 0.78 * sin(a), 2.2), (3.75 * cos(a), 3.75 * sin(a), 3.15), 0.12, 0.1, 'M_Bld_Wood')
    # cap (boat-shaped dome) with shingles
    st = len(mb.bm.faces)
    mb.lathe([(2.55, zt - 0.05), (2.5, zt + 0.12), (2.3, zt + 0.85), (1.85, zt + 1.55), (1.2, zt + 2.1), (0.5, zt + 2.38), (0.0, zt + 2.45)], 'M_Bld_RoofTile', seg=16,
             smooth=False, col=PAL['dark'])
    mb.speckle(['M_Bld_RoofTile'], 0.15, start=st)
    mb.torus((0, 0, zt + 0.1), 2.52, 0.07, 'M_Bld_Wood', nmaj=24, nmin=5)
    # hub / shaft stub at the front and tail pole at the back
    H = (2.8, 0.0, 8.15)
    mb.cyl((1.4, 0, H[2]), (2.95, 0, H[2]), 0.17, 0.17, 'M_Bld_Metal', seg=10)
    mb.cyl((2.3, 0, H[2] - 0.45), (2.3, 0, H[2] + 0.45), 0.06, 0.06, 'M_Bld_Wood', seg=6) if False else None
    mb.bar((-2.0, 0.0, 8.05), (-4.6, 0.0, 0.45), 0.2, 0.2, 'M_Bld_Wood')
    for k in range(8):
        t_ = 0.12 + k * 0.105
        px = -2.0 + (-4.6 + 2.0) * t_ ; pz = 8.05 + (0.45 - 8.05) * t_
        mb.box((px - 0.07, -0.34, pz - 0.03), (px + 0.07, 0.34, pz + 0.03), 'M_Bld_Wood')
    mb.sockets['blades_hub'] = H
    mb.hull_pts(ring_pts(3.55, 0.0, 12) + ring_pts(2.3, zt, 12))
    mb.hull_pts(ring_pts(2.55, zt, 12) + [(0, 0, zt + 2.45)])
    return dict(height=zt + 2.45, hub=list(H), blade_radius=4.2)


@asset('bld_windmill_blades', 'Windmill blades (4 lattice sails, pivot at hub)', x=322.8, z=8.15, ext=(-0.8, 0.5), group='landmark', budget=6000, collision='none', pivot='hub',
       tags=['rural', 'landmark', 'rotor'], scale=(0.85, 1.4), usage='Rotate about local X (rotor axis +X). Attach at windmill socket blades_hub = (2.8, 0, 8.15)', nanite=True)
def windmill_blades(mb):
    mb.cyl((-0.55, 0, 0), (0.45, 0, 0), 0.26, 0.2, 'M_Bld_Wood', seg=12)
    mb.cyl((0.4, 0, 0), (0.62, 0, 0), 0.12, 0.05, 'M_Bld_Metal', seg=10)
    mb.cyl((-0.62, 0, 0), (-0.5, 0, 0), 0.32, 0.32, 'M_Bld_Metal', seg=12)
    R = 4.3
    for k in range(4):
        th = radians(90 * k + 15.0)
        M = Matrix.Rotation(th, 4, 'X') @ Matrix.Rotation(radians(-14.0), 4, 'Z')   # blade built along +Z, chord along +Y, normal X; twist about Z
        def B(c, sz, mat='M_Bld_Wood', cc=0.0):
            rbox(mb, M, c, sz, mat, None, cc)
        # stock (spar) from hub to tip
        B((0.0, 0.0, 2.4), (0.14, 0.2, 4.2), 'M_Bld_Wood', 0.012)
        B((0.0, 0.0, R + 0.02), (0.1, 0.12, 0.12), 'M_Bld_Wood')
        # lattice frame on the +chord side
        c0, c1 = 0.12, 1.32
        r0_, r1_ = 1.0, 4.25
        B((0.0, c1, (r0_ + r1_) / 2), (0.08, 0.07, r1_ - r0_), 'M_Bld_Wood')           # outer edge
        B((0.0, (c0 + c1) / 2, r0_), (0.08, c1 - c0, 0.07), 'M_Bld_Wood')               # root bar
        B((0.0, (c0 + c1) / 2, r1_), (0.08, c1 - c0, 0.07), 'M_Bld_Wood')               # tip bar
        nrung = 12
        for j in range(1, nrung):
            rr = r0_ + (r1_ - r0_) * j / nrung
            B((0.0, (c0 + c1) / 2, rr), (0.05, c1 - c0, 0.035), 'M_Bld_Wood')
        B((0.0, (c0 + c1) / 2, (r0_ + r1_) / 2), (0.05, 0.035, r1_ - r0_), 'M_Bld_Wood')
        # whip strip along the stock
        B((0.0, 0.0, 2.4), (0.17, 0.05, 4.1), 'M_Bld_Metal') if False else None
    return dict(blades=4, radius=R)


# ---------------------------------------------------------------------------------------------------------------------
def _superellipse(y_half, z_half, zc, x, n=14, p=3.0):
    pts = []
    for i in range(n):
        t = 2 * pi * i / n
        c, s = cos(t), sin(t)
        pts.append(Vector((x, y_half * (1 if c >= 0 else -1) * abs(c) ** (2.0 / p), zc + z_half * (1 if s >= 0 else -1) * abs(s) ** (2.0 / p))))
    return pts


@asset('bld_wind_turbine', 'Wind turbine tower + nacelle (60 m tower, rotor separate)', x=346.0, ext=(-6.5, 7.0), group='landmark', budget=14000, collision='convex',
       tags=['energy', 'landmark', 'highland', 'coast'], scale=(0.7, 1.4), usage='Tower 60 m + nacelle; rotor is bld_wind_turbine_rotor (pivot at hub; rotate about X); socket rotor_hub')
def wind_turbine(mb):
    H = 60.0
    r0, r1 = 2.15, 1.5
    rt = lambda z: r0 + (r1 - r0) * z / H
    mb.cyl((0, 0, 0), (0, 0, 0.9), 6.0, 5.8, 'M_Bld_Stone', seg=28, smooth=False)
    mb.cyl((0, 0, 0.9), (0, 0, 1.25), 2.75, 2.7, 'M_Bld_Metal', seg=24, smooth=False)
    nsec = 6
    zs = [1.25 + (H - 1.25) * i / nsec for i in range(nsec + 1)]
    mb.lathe([(rt(z), z) for z in zs], 'M_Bld_PaintWhite', seg=24, smooth=True)
    for z in zs[1:-1]:
        mb.cyl((0, 0, z - 0.12), (0, 0, z + 0.12), rt(z) + 0.06, rt(z) + 0.06, 'M_Bld_Metal', seg=24, smooth=False)
    mb.cyl((0, 0, H - 0.1), (0, 0, H + 0.1), r1 + 0.12, r1 + 0.12, 'M_Bld_Metal', seg=24, smooth=False)
    # service door (+X) + step + base ring bolts
    radial_box(mb, 0, rt(2.0), 2.45, (0.22, 1.25, 2.5), 'M_Bld_Metal', c=0.02)
    radial_box(mb, 0, rt(2.0) + 0.1, 2.4, (0.08, 1.0, 2.2), 'M_Bld_PaintWhite', c=0.01)
    radial_box(mb, 0, rt(2.0) + 0.45, 1.0, (0.8, 1.6, 0.25), 'M_Bld_Metal')
    for k in range(24):
        a = 360.0 * k / 24
        radial_box(mb, a, 2.5, 1.34, (0.14, 0.14, 0.18), 'M_Bld_Metal')
    # nacelle (loft of superellipse sections)
    zc = 61.85
    stn = [(-4.9, 2.2, 2.5), (-4.0, 2.8, 3.1), (-1.8, 3.3, 3.55), (1.5, 3.4, 3.6), (4.0, 3.3, 3.5), (4.8, 2.9, 3.15)]
    rings = [_superellipse(w / 2, h / 2, zc - (0.15 if x < 0 else 0.0), x) for (x, w, h) in stn]
    mb.loft(rings, 'M_Bld_PaintWhite', True, True, cap0=True, cap1=True, cap_tri=True)
    mb.cyl((4.75, 0, zc), (5.0, 0, zc), 1.42, 1.42, 'M_Bld_Metal', seg=20, smooth=False)
    for k in range(7):
        xx = -1.2 + k * 0.3
        mb.box((xx, -1.0, zc + 1.74), (xx + 0.12, 1.0, zc + 1.9), 'M_Bld_Metal')
    for sg in (-1, 1):
        for k in range(5):
            mb.box((-1.4 + k * 0.5, min(sg * 1.6, sg * 1.75), zc - 0.7), (-1.4 + k * 0.5 + 0.2, max(sg * 1.6, sg * 1.75), zc + 0.7), 'M_Bld_Metal')
    mb.cyl((-3.4, 0.0, zc + 1.7), (-3.4, 0.0, zc + 2.9), 0.035, 0.035, 'M_Bld_Metal', seg=6)
    for sg in (-1, 1):
        mb.cyl((-3.4, sg * 0.18, zc + 2.9), (-3.4, sg * 0.18, zc + 2.98), 0.1, 0.1, 'M_Bld_Metal', seg=8)
    mb.cyl((-4.3, 0.0, zc + 1.2), (-4.3, 0.0, zc + 1.55), 0.1, 0.1, 'M_Bld_PaintRed', seg=8)
    mb.sockets['rotor_hub'] = (5.6, 0.0, zc)
    mb.hull_pts(ring_pts(6.0, 0.0, 12) + ring_pts(r1 + 0.05, H, 12))
    mb.hull_box((-4.9, -1.75, zc - 1.8), (4.9, 1.75, zc + 1.9))
    return dict(tower_height=H, hub_height=zc, hub=[5.6, 0.0, zc], rotor_diameter=73.0)


@asset('bld_wind_turbine_rotor', 'Wind turbine rotor (3 blades x 35 m, pivot at hub)', x=351.6, z=61.85, ext=(-1.0, 3.5), group='landmark', budget=8000, collision='none', pivot='hub',
       tags=['energy', 'landmark', 'rotor'], scale=(0.7, 1.4), usage='Rotate about local X. Attach to the turbine at socket rotor_hub = (5.6, 0, 61.85). Blade length 35 m from hub radius 1.5 m')
def wind_rotor(mb):
    # spinner
    prof = [(-0.9, 1.5), (0.0, 1.72), (0.9, 1.65), (1.9, 1.3), (2.7, 0.7), (3.25, 0.25), (3.45, 0.0)]
    rings = []
    for (x, r) in prof:
        if r < 1e-6:
            rings.append(Vector((x, 0, 0)))
        else:
            rings.append([Vector((x, r * cos(2 * pi * i / 24), r * sin(2 * pi * i / 24))) for i in range(24)])
    mb.loft(rings, 'M_Bld_PaintWhite', True, True, cap0=True)
    K = 8
    af = []
    for i in range(K + 1):
        x = (1 - cos(pi * i / K)) / 2
        yt = 5 * (0.2969 * sqrt(x) - 0.1260 * x - 0.3516 * x * x + 0.2843 * x ** 3 - 0.1036 * x ** 4)
        af.append((x, yt))
    foil = [(x, yt) for (x, yt) in af] + [(x, -yt) for (x, yt) in reversed(af[1:-1])]      # 16 points: LE -> TE (upper) -> back (lower)
    nf = len(foil)
    fs = [0.0, 0.012, 0.04, 0.08, 0.13, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.97, 1.0]
    R0 = 1.5; Lb = 35.0
    for k in range(3):
        th = radians(90 + 120 * k)
        rho = Vector((0, cos(th), sin(th))); tau = Vector((0, -sin(th), cos(th))); xh = Vector((1, 0, 0))
        rings = []
        for f in fs:
            r = R0 + Lb * f
            ch = 0.4 + 3.2 * (1 - max(0.0, (f - 0.12) / 0.88) ** 0.8) if f > 0.12 else 2.2 + (3.6 - 2.2) * f / 0.12
            tr = 0.1 + 0.24 * max(0.0, 1 - f / 0.4) ** 1.3
            tw = radians(14.0 * (1 - f) ** 1.5)
            c_d = tau * cos(tw) + xh * sin(tw); n_d = -tau * sin(tw) + xh * cos(tw)
            wcirc = max(0.0, 1 - f / 0.05)
            ring = []
            for i, (xa, ya) in enumerate(foil):
                pa = ((xa - 0.3) * ch, ya * tr / 0.2 * ch * 0.2 * 1.0)
                pa = ((xa - 0.3) * ch, ya * ch * tr / 0.2 * 0.2)
                phi = 2 * pi * i / nf
                pc = (1.1 * cos(phi), 1.1 * sin(phi))
                px = pa[0] * (1 - wcirc) + pc[0] * wcirc
                py = pa[1] * (1 - wcirc) + pc[1] * wcirc
                ring.append(rho * r + c_d * px + n_d * py)
            rings.append(ring)
        mb.loft(rings, 'M_Bld_PaintWhite', True, True, cap0=True, cap1=True, cap_tri=True,
                face_mat=lambda i, j: 'M_Bld_PaintRed' if i >= len(fs) - 3 else 'M_Bld_PaintWhite')
    mb.cyl((-1.0, 0, 0), (-0.85, 0, 0), 1.55, 1.55, 'M_Bld_Metal', seg=24, smooth=False)
    return dict(blades=3, blade_length=Lb, hub_radius=R0)
