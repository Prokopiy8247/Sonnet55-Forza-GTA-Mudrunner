# -*- coding: utf-8 -*-
"""Roadside kit part 1b: parapet (+ end pier), jersey barrier, bridge rail, delineators, bollards (uses helpers from rs_barriers.py)."""

# ----------------------------------------------------------------------------------------------------------------------
# masonry helper (courses of rock-faced stones on a wall face)
# ----------------------------------------------------------------------------------------------------------------------
_STONE_TINTS = [(1.0, 1.0, 1.0), (0.93, 0.91, 0.88), (1.04, 1.0, 0.94), (0.88, 0.88, 0.9), (1.0, 0.96, 0.9)]

def masonry_wall(mb, O, phi, u0, u1, z0, z1, depth, course_h=0.22, lenr=(0.30, 0.62), mat='M_RS_Stone', gap=0.014, c=0.02, prot=0.02,
                 yaw_j=2.0, stagger=True, hvar=0.0, style='rock', tilt=2.0):
    """Stone courses on a face. Local frame: origin O (point on face plane), tangent T at angle phi (deg), outward normal = left of T.
    Stones fill u in [u0,u1], z in [z0,z1]; each stone is `depth` thick going INTO the wall.
    style 'rock' = pillow-faced frustum stones (12 tris, chamfered front face, slight tilt); 'box' = chamfered boxes (44 tris)."""
    R = Rz(phi)
    rng = mb.rng
    n = max(1, int(round((z1 - z0) / course_h)))
    if hvar > 0:
        hs = [rng.uniform(0.8, 1.2) for _ in range(n)]
        tot = sum(hs)
        hs = [(z1 - z0) * v / tot for v in hs]
    else:
        hs = [(z1 - z0) / n] * n
    zacc = z0
    for k in range(n):
        ch = hs[k]
        zb = zacc
        zacc += ch
        u = u0 - (rng.uniform(0.0, 0.7) * lenr[0] if (k % 2 and stagger) else 0.0)
        while u < u1 - 0.02:
            L = rng.uniform(*lenr)
            if u1 - (u + L) < lenr[0] * 0.55:
                L = u1 - u
            ua = max(u, u0); ub = min(u + L, u1)
            if ub - ua > 0.06:
                h = ch * (1.0 - hvar * rng.random()) - gap - rng.uniform(0, 0.02)
                zoff = rng.uniform(0.0, max(0.0, ch - gap - h)) if hvar > 0 else 0.0
                d = depth * rng.uniform(0.85, 1.0)
                pf = rng.uniform(-prot, prot)
                w = R @ Vector(((ua + ub) / 2, pf - d / 2, 0))
                tc = _STONE_TINTS[rng.randrange(len(_STONE_TINTS))]
                col = mb.tint(0.14, tc)
                cen = Vector((O[0] + w.x, O[1] + w.y, (zb + ch / 2) if hvar <= 0 else (zb + h / 2 + zoff)))
                if style == 'rock':
                    bev = min(0.034, 0.2 * min(ub - ua - gap, h))
                    mb.stone(cen, (ub - ua - gap, d, h), mat, (rng.uniform(-tilt, tilt), rng.uniform(-tilt, tilt), phi + rng.uniform(-yaw_j, yaw_j)),
                             bevel=bev, col=col, jit=0.004)
                else:
                    mb.obox(cen, (ub - ua - gap, d, h), mat, (0, 0, phi + rng.uniform(-yaw_j, yaw_j)), c, col=col)
            u += L

# ----------------------------------------------------------------------------------------------------------------------
# 2. mountain parapet (stone-faced wall, stone piers, timber rails)  3.0 m  + closing end pier
# ----------------------------------------------------------------------------------------------------------------------
PARAPET_TH = 0.5
PARAPET_HW = 0.62
PARAPET_PH = 1.18

def _parapet_pier(mb):
    ph = PARAPET_PH
    mb.box((-0.245, -0.55, 0.0), (0.245, 0.005, ph), 'M_RS_ConcreteDark')
    masonry_wall(mb, Vector((0, 0.03, 0)), 0, -0.27, 0.27, 0.0, ph, 0.14, course_h=0.195, lenr=(0.26, 0.34))
    masonry_wall(mb, Vector((-0.27, -0.26, 0)), 90, -0.29, 0.29, 0.0, ph, 0.14, course_h=0.195, lenr=(0.26, 0.34))
    masonry_wall(mb, Vector((0.27, -0.26, 0)), -90, -0.29, 0.29, 0.0, ph, 0.14, course_h=0.195, lenr=(0.26, 0.34))
    masonry_wall(mb, Vector((0.27, -0.55 - 0.0, 0)), 180, 0.0, 0.54, 0.0, ph, 0.12, course_h=0.195, lenr=(0.26, 0.34), prot=0.01)   # back face
    mb.box((-0.34, -0.62, ph), (0.34, 0.10, ph + 0.08), 'M_RS_Stone', c=0.025, col=mb.tint(0.08))
    mb.cyl((0, -0.26, ph + 0.08), (0, -0.26, ph + 0.26), 0.31, 0.06, 'M_RS_Stone', seg=4, smooth=False, roll=radians(45), cap1=True, col=mb.tint(0.08))
    mb.hull_box((-0.34, -0.62, 0.0), (0.34, 0.10, 1.26))

@asset('rs_parapet_mountain_3m', 'Mountain parapet stone + timber rail 3.0 m', x=32.0, ext=(-0.35, 3.0), group='barrier', budget=2400, collision='box',
       pivot='segment_start', tags=['alpine', 'forest', 'mountain_road'], scale=(1.0, 1.0),
       usage='Hairpins and cliff-side verge in the alpine biome. Traffic face y=0, body extends to -Y (0.5 m). Stone pier at x=0; tile every 3.0 m and close the run with rs_parapet_mountain_end. Both faces are coursed stone.')
def b_parapet(mb):
    th = PARAPET_TH; hw = PARAPET_HW
    mb.box((0.26, -th, 0.0), (2.74, -0.03, hw), 'M_RS_ConcreteDark')                    # wall core (stones sit on both faces)
    masonry_wall(mb, Vector((0, 0.0, 0)), 0, 0.26, 2.74, 0.0, hw, 0.2, course_h=0.205)  # road face
    masonry_wall(mb, Vector((3.0, -th, 0)), 180, 0.26, 2.74, 0.0, hw, 0.14, course_h=0.205, prot=0.012, yaw_j=1.5)   # cliff face (relief, not a flat skin)
    # coping slabs
    x = 0.26
    while x < 2.74 - 0.05:
        L = min(mb.rng.uniform(0.42, 0.62), 2.74 - x)
        if 2.74 - (x + L) < 0.3: L = 2.74 - x
        mb.box((x + 0.008, -th - 0.045, hw), (x + L - 0.008, 0.045, hw + 0.075), 'M_RS_Stone', c=0.02, col=mb.tint(0.1, _STONE_TINTS[mb.rng.randrange(5)]))
        x += L
    _parapet_pier(mb)
    # timber: two rails + mid post + iron straps
    ymid = -0.23
    for zc in (0.83, 1.01):
        mb.box((0.27, ymid - 0.055, zc - 0.045), (2.73, ymid + 0.055, zc + 0.045), 'M_RS_Wood', c=0.012, col=mb.tint(0.2, (1.0, 0.95, 0.9)))
    mb.box((1.42, ymid - 0.06, hw + 0.07), (1.58, ymid + 0.06, 1.08), 'M_RS_Wood', c=0.012, col=mb.tint(0.2))
    for x in (0.275, 2.725):
        for zc in (0.83, 1.01):
            mb.box((x - 0.012, ymid - 0.075, zc - 0.058), (x + 0.012, ymid + 0.075, zc + 0.058), 'M_RS_GalvDark')
    for zc in (0.83, 1.01):
        mb.box((1.5 - 0.03, ymid + 0.055, zc - 0.05), (1.5 + 0.03, ymid + 0.062, zc + 0.05), 'M_RS_GalvDark')
    mb.grime(('M_RS_Stone', 'M_RS_Concrete', 'M_RS_ConcreteDark'), 0.3, 0.35)
    mb.hull_box((0.26, -0.55, 0.0), (2.74, 0.05, 0.70))
    mb.hull_box((0.27, -0.30, 0.70), (2.73, -0.16, 1.07))
    return dict(length=3.0, height=1.26, run_role='body', closes_with='rs_parapet_mountain_end')

@asset('rs_parapet_mountain_end', 'Mountain parapet closing end pier + stepped wall return', x=372.0, ext=(-0.35, 1.4), group='barrier', budget=2000, collision='box',
       pivot='segment_start', tags=['alpine', 'forest', 'mountain_road'], scale=(1.0, 1.0),
       usage='END of a parapet run: place with its origin on the far end of the last rs_parapet_mountain_3m (x=3.0 of that segment). Stone pier at x=0 (same as the segment pier) followed by a 1.0 m stepped wall return that dives into the hillside. Traffic face y=0.')
def b_parapet_end(mb):
    th = PARAPET_TH
    _parapet_pier(mb)
    ch = 0.205
    steps = [(1.30, 0.0), (0.95, ch), (0.62, 2 * ch)]
    xs0 = 0.26
    for k, (xe, z0) in enumerate(steps):
        z1 = z0 + ch
        mb.box((xs0, -th, z0), (xe, -0.03, z1), 'M_RS_ConcreteDark')
        masonry_wall(mb, Vector((0, 0.0, 0)), 0, xs0, xe, z0, z1, 0.2, course_h=ch, lenr=(0.30, 0.55))
        masonry_wall(mb, Vector((xe, -th, 0)), 180, 0.0, xe - xs0, z0, z1, 0.14, course_h=ch, prot=0.012, yaw_j=1.5, lenr=(0.30, 0.55))
        masonry_wall(mb, Vector((xe, -0.03, 0)), -90, 0.0, th - 0.03, z0, z1, 0.12, course_h=ch, lenr=(0.22, 0.34), prot=0.01)
        xc0 = steps[k + 1][0] - 0.02 if k + 1 < len(steps) else xs0       # coping only on the exposed part of each step
        mb.box((xc0, -th - 0.04, z1), (xe + 0.045, 0.045, z1 + 0.06), 'M_RS_Stone', c=0.02, col=mb.tint(0.1, _STONE_TINTS[mb.rng.randrange(5)]))
    mb.grime(('M_RS_Stone', 'M_RS_Concrete', 'M_RS_ConcreteDark'), 0.3, 0.35)
    mb.hull_box((0.26, -0.55, 0.0), (1.35, 0.05, 0.215))
    mb.hull_box((0.26, -0.55, 0.0), (1.0, 0.05, 0.42))
    mb.hull_box((0.26, -0.55, 0.0), (0.67, 0.05, 0.63))
    return dict(length=1.3, height=1.26, run_role='end')

# ----------------------------------------------------------------------------------------------------------------------
# 3. concrete jersey barrier 3.0 m
# ----------------------------------------------------------------------------------------------------------------------
JERSEY = [(-0.305, 0.0), (0.305, 0.0), (0.305, 0.073), (0.127, 0.32), (0.078, 0.757), (0.062, 0.781), (-0.062, 0.781), (-0.078, 0.757), (-0.127, 0.32), (-0.305, 0.073)]

def _jersey_y_at(z):
    (y0, z0), (y1, z1) = (0.127, 0.32), (0.078, 0.757)
    return y0 + (y1 - y0) * (z - z0) / (z1 - z0)

@asset('rs_barrier_jersey_3m', 'Concrete jersey barrier 3.0 m', x=44.0, ext=(0.0, 3.0), group='barrier', budget=1400, collision='box',
       pivot='segment_start', tags=['all_biomes', 'highway', 'roadworks'], scale=(1.0, 1.0),
       usage='Median / bridge-edge barrier, 0.78 m profile (0.82 m with lifting loops). Centreline y=0 (symmetric profile), runs +X, tile every 3.0 m (gap 0.02 m already modelled as end chamfer).')
def b_jersey(mb):
    L = 3.0
    xs = [0.0, 0.03, 0.985, 1.0, 1.015, 1.985, 2.0, 2.015, L - 0.03, L]
    path = [Vector((x, 0, 0)) for x in xs]
    scl = [(0.95, 0.985), (1, 1), (1, 1), (0.975, 0.99), (1, 1), (1, 1), (0.975, 0.99), (1, 1), (1, 1), (0.95, 0.985)]
    sc = lambda t: scl[min(len(scl) - 1, int(round(t * (len(scl) - 1))))]
    sm = [False] * len(JERSEY)
    mb.sweep(JERSEY, path, 'M_RS_Concrete', True, sm, scale=sc, cap0=True, cap1=True)
    # steel lifting loops (bent bars) on top near both ends
    for x in (0.42, L - 0.42):
        arc = [Vector((x + 0.055 * cos(a), 0.0, 0.768 + 0.05 * sin(a))) for a in [pi * i / 8 for i in range(9)]]
        mb.tube(arc, 0.011, 'M_RS_GalvDark', seg=6, smooth=True, up=(0, 1, 0), caps=True)
    # amber reflectors on both slopes
    for sy in (-1, 1):
        yf = sy * _jersey_y_at(0.55)
        mb.box((L / 2 - 0.09, yf - 0.006, 0.52), (L / 2 + 0.09, yf + 0.006, 0.58), 'M_RS_ReflectorAmber')
    # steel pin-and-loop connectors at mid height on both ends
    for x0, sg in ((0.0, -1), (L, 1)):
        mb.box((x0 - 0.015 if sg < 0 else x0 - 0.005, -0.045, 0.40), (x0 + 0.005 if sg < 0 else x0 + 0.015, 0.045, 0.44), 'M_RS_GalvDark')
    # drain slots near the foot (on the 73 mm vertical lip)
    for sy in (-1, 1):
        for x in (0.75, 2.25):
            y0 = sy * 0.305
            mb.box((x - 0.12, min(y0, y0 + 0.004 * sy), 0.02), (x + 0.12, max(y0, y0 + 0.004 * sy), 0.06), 'M_RS_ConcreteDark')
    mb.grime(('M_RS_Concrete',), 0.35, 0.45)
    mb.hull_pts([Vector((x, y, z)) for x in (0.0, L) for (y, z) in [(-0.305, 0.0), (0.305, 0.0), (0.305, 0.073), (0.078, 0.781), (-0.078, 0.781), (-0.305, 0.073)]])
    return dict(length=L, height=0.781, height_with_loops=0.82)

# ----------------------------------------------------------------------------------------------------------------------
# 4. bridge railing 2.0 m (steel tubular)
# ----------------------------------------------------------------------------------------------------------------------
@asset('rs_bridge_rail_2m', 'Bridge railing steel tubular 2.0 m', x=56.0, ext=(-0.12, 2.0), group='barrier', budget=1800, collision='box',
       pivot='segment_start', tags=['bridge', 'all_biomes'], scale=(1.0, 1.0),
       usage='Bridge deck edge. Post on the origin, rails run +X to the next post at 2.0 m. Centreline y=0; traffic side +Y.')
def b_bridge_rail(mb):
    H = 1.08
    mb.box((-0.11, -0.11, 0.0), (0.11, 0.11, 0.016), 'M_RS_GalvDark', c=0.003)
    for sx in (-1, 1):
        for sy in (-1, 1):
            hexbolt(mb, (sx * 0.08, sy * 0.08, 0.016), (0, 0, 1), r=0.011, ln=0.014, wash=0.02, wash_t=0.003)
    mb.box((-0.05, -0.05, 0.016), (0.05, 0.05, H), 'M_RS_PaintGrey', c=0.008)
    mb.dome((0, 0, H), 0.058, 'M_RS_PaintGrey', seg=10, rings=3, zscale=0.6)
    for (z, r) in ((H - 0.02, 0.046), (0.72, 0.03), (0.36, 0.03)):
        mb.tube([Vector((0, 0, z)), Vector((2.0, 0, z))], r, 'M_RS_GalvSteel', seg=10, smooth=True, up=(0, 0, 1), caps=True)
    n = 7
    for i in range(n):
        x = 0.25 + i * (2.0 - 0.5) / (n - 1)
        mb.cyl((x, 0, 0.05), (x, 0, H - 0.05), 0.012, 0.012, 'M_RS_GalvSteel', seg=6, smooth=True)
    mb.box((0.05, -0.012, 0.0), (2.0, 0.012, 0.11), 'M_RS_GalvDark')
    mb.cyl((0.96, 0, H - 0.02), (1.04, 0, H - 0.02), 0.052, 0.052, 'M_RS_GalvDark', seg=10, smooth=True)
    mb.hull_box((-0.11, -0.11, 0.0), (2.0, 0.11, 1.16))
    return dict(length=2.0, height=1.16)

# ----------------------------------------------------------------------------------------------------------------------
# 5. delineator posts
# ----------------------------------------------------------------------------------------------------------------------
def _rrect(w, d, r, n=3):
    return rounded_poly([(-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)], r, n)

def _delineator(mb, refl, band='M_RS_PaintBlack'):
    W, D = 0.065, 0.14      # depth along X, width along Y
    prof = _rrect(W, D, 0.022, 3)
    zs = [0.0, 0.62, 0.95, 0.985, 1.0]
    scl = [(1, 1), (1, 1), (0.93, 0.95), (0.8, 0.85), (0.6, 0.7)]
    mb.vsweep(prof, list(zs), 'M_RS_PlasticWhite', scale=lambda t: scl[min(len(scl) - 1, int(round(t * (len(scl) - 1))))], smooth=True)
    bprof = _rrect(W + 0.006, D + 0.006, 0.024, 3)
    mb.vsweep(bprof, [0.70, 0.93], band, smooth=True)
    mb.box((W / 2 + 0.003 - 0.002, -0.045, 0.78), (W / 2 + 0.003 + 0.004, 0.045, 0.87), refl, c=0.0015)
    mb.box((W / 2 + 0.003 - 0.002, -0.054, 0.773), (W / 2 + 0.003 + 0.001, 0.054, 0.877), band, c=0.0015)
    mb.lathe([(0.115, 0.0), (0.115, 0.012), (0.095, 0.022), (0.06, 0.05), (0.0, 0.05)], 'M_RS_Rubber', seg=10, smooth=False, row_smooth=[False, False, True, False])

@asset('rs_delineator_post', 'Delineator post white / red reflector', x=70.0, ext=(-0.2, 0.2), group='barrier', budget=900, collision='none',
       tags=['all_biomes', 'road_verge'], scale=(1.0, 1.0), usage='Right-hand verge, spacing 25-50 m. Reflector faces +X.')
def b_delin_red(mb):
    _delineator(mb, 'M_RS_ReflectorRed')

@asset('rs_delineator_post_white', 'Delineator post white / white reflector', x=72.0, ext=(-0.2, 0.2), group='barrier', budget=900, collision='none',
       tags=['all_biomes', 'road_verge'], scale=(1.0, 1.0), usage='Left-hand verge variant. Reflector faces +X.')
def b_delin_white(mb):
    _delineator(mb, 'M_RS_ReflectorWhite')

@asset('rs_delineator_post_amber', 'Delineator post white / amber reflector', x=74.0, ext=(-0.2, 0.2), group='barrier', budget=900, collision='none',
       tags=['all_biomes', 'tunnel', 'roadworks'], scale=(1.0, 1.0), usage='Tunnel / hazard variant. Reflector faces +X.')
def b_delin_amber(mb):
    _delineator(mb, 'M_RS_ReflectorAmber')

# ----------------------------------------------------------------------------------------------------------------------
# 9. bollards
# ----------------------------------------------------------------------------------------------------------------------
@asset('rs_bollard_stone', 'Bollard stone (granite, painted band)', x=78.0, ext=(-0.25, 0.25), group='barrier', budget=900, collision='convex',
       tags=['village', 'all_biomes', 'mountain'], scale=(0.9, 1.15), usage='Village streets, parking edges, hairpin apexes.')
def b_bollard_stone(mb):
    seg = 20
    rz = [(0.185, 0.0), (0.185, 0.07), (0.15, 0.10), (0.145, 0.60), (0.168, 0.62), (0.168, 0.70), (0.15, 0.72), (0.135, 0.78), (0.09, 0.83), (0.0, 0.85)]
    sm = [True, False, True, False, True, False, True, True, True]
    mb.lathe(rz, 'M_RS_Stone', seg=seg, smooth=True, row_smooth=sm, col=mb.tint(0.08), roll=0.2)
    mb.lathe([(0.1475, 0.40), (0.1475, 0.52)], 'M_RS_PaintWhite', seg=seg, smooth=True, cap0=True, cap1=True, roll=0.2)
    mb.lathe([(0.1485, 0.455), (0.1485, 0.47)], 'M_RS_ReflectorRed', seg=seg, smooth=True, cap0=True, cap1=True, roll=0.2)
    mb.grime(('M_RS_Stone',), 0.25, 0.4)
    mb.hull_cyl((0, 0, 0), (0, 0, 0.85), 0.18, 10)

@asset('rs_bollard_plastic', 'Bollard flexible plastic (white/orange, reflective bands)', x=80.0, ext=(-0.2, 0.2), group='barrier', budget=900, collision='none',
       tags=['all_biomes', 'roadworks', 'junction'], scale=(0.9, 1.1), usage='Junction islands, lane splitters. Flexible; use no collision.')
def b_bollard_plastic(mb):
    seg = 16
    mb.lathe([(0.13, 0.0), (0.13, 0.014), (0.1, 0.024), (0.052, 0.055), (0.0, 0.055)], 'M_RS_Rubber', seg=20, smooth=False, row_smooth=[True, False, True, False])
    rz = [(0.05, 0.05), (0.047, 0.20), (0.045, 0.60), (0.045, 0.80), (0.046, 0.87), (0.04, 0.93), (0.0, 0.96)]
    mats = ['M_RS_PlasticWhite', 'M_RS_PlasticWhite', 'M_RS_PlasticOrange', 'M_RS_PlasticOrange', 'M_RS_PlasticOrange', 'M_RS_PlasticOrange']
    mb.lathe(rz, 'M_RS_PlasticWhite', seg=seg, smooth=True, row_mats=mats, cap0=True)
    for (z0, z1) in ((0.25, 0.33), (0.40, 0.48)):
        mb.lathe([(0.0481, z0), (0.0481, z1)], 'M_RS_ReflectorWhite', seg=seg, smooth=True, cap0=True, cap1=True)
