# -*- coding: utf-8 -*-
"""Roadside kit part 2: traffic cone, barrel, tyre stack, hay-bale roadblock."""

def _cone_r(z, r0=0.14, r1=0.032, z0=0.05, z1=0.68):
    return r0 + (r1 - r0) * (z - z0) / (z1 - z0)

@asset('rs_traffic_cone', 'Traffic cone 0.70 m (orange, reflective collars)', x=86.0, ext=(-0.25, 0.25), group='trafficfurniture', budget=700, collision='convex',
       tags=['all_biomes', 'roadworks', 'race_event'], scale=(0.9, 1.15), usage='Roadworks, event lanes, checkpoints. Dynamic physics prop candidate (convex hull).')
def b_cone(mb):
    seg = 16
    mb.box((-0.19, -0.19, 0.0), (0.19, 0.19, 0.04), 'M_RS_Rubber', c=0.016)
    mb.lathe([(0.152, 0.04), (0.152, 0.05), (0.14, 0.06), (0.0, 0.06)], 'M_RS_Rubber', seg=seg, smooth=False, cap0=True, row_smooth=[False, False, False])
    rz = [(0.145, 0.05), (_cone_r(0.30), 0.30), (_cone_r(0.50), 0.50), (0.034, 0.675), (0.03, 0.70), (0.0, 0.705)]
    mb.lathe(rz, 'M_RS_PlasticOrange', seg=seg, smooth=True, row_smooth=[True, True, True, False, True], cap0=True)
    for (z0, z1) in ((0.28, 0.40), (0.445, 0.505)):
        mb.lathe([(_cone_r(z0) + 0.003, z0), (_cone_r(z1) + 0.003, z1)], 'M_RS_ReflectorWhite', seg=seg, smooth=True, cap0=True, cap1=True)
    mb.hull_pts([Vector((x, y, 0.0)) for x in (-0.19, 0.19) for y in (-0.19, 0.19)] + [Vector((0.03 * cos(a), 0.03 * sin(a), 0.70)) for a in (0, 1.57, 3.14, 4.71)])

@asset('rs_traffic_barrel', 'Channelizer drum 0.95 m (orange/white)', x=90.0, ext=(-0.35, 0.35), group='trafficfurniture', budget=1300, collision='convex',
       tags=['all_biomes', 'roadworks', 'race_event'], scale=(0.9, 1.1), usage='Roadworks lane drum / race barrier. Convex hull collision.')
def b_barrel(mb):
    seg = 20
    prof = [(0.272, 0.0), (0.29, 0.02), (0.29, 0.07), (0.272, 0.09), (0.272, 0.22), (0.286, 0.236), (0.286, 0.262), (0.272, 0.278), (0.272, 0.70),
            (0.286, 0.716), (0.286, 0.742), (0.272, 0.758), (0.272, 0.88), (0.29, 0.90), (0.29, 0.945), (0.255, 0.945), (0.255, 0.925), (0.0, 0.925)]
    def zmat(z):
        if 0.30 <= z < 0.46 or 0.60 <= z < 0.76: return 'M_RS_ReflectorWhite'
        return 'M_RS_PlasticOrange'
    # split long rows at band edges so the white bands are exact: insert extra rings
    rz = []
    for i in range(len(prof) - 1):
        rz.append(prof[i])
        z0, z1 = prof[i][1], prof[i + 1][1]
        for zb in (0.30, 0.46, 0.60, 0.76):
            if z0 < zb < z1:
                t = (zb - z0) / (z1 - z0)
                rz.append((prof[i][0] + (prof[i + 1][0] - prof[i][0]) * t, zb))
    rz.append(prof[-1])
    rows = [zmat((rz[i][1] + rz[i + 1][1]) / 2) for i in range(len(rz) - 1)]
    sm = [not (rz[i][1] >= 0.944) and not (rz[i][1] >= 0.924 and rz[i + 1][1] <= 0.926) for i in range(len(rz) - 1)]
    mb.lathe(rz, 'M_RS_PlasticOrange', seg=seg, smooth=True, row_mats=rows, row_smooth=sm, cap0=True, cap1=False)
    # bungs
    for a in (0.6, 3.1):
        mb.cyl((0.1 * cos(a), 0.1 * sin(a), 0.925), (0.1 * cos(a), 0.1 * sin(a), 0.945), 0.03, 0.03, 'M_RS_PlasticOrange', seg=8, smooth=True)
    mb.grime(('M_RS_PlasticOrange',), 0.1, 0.0)
    mb.hull_cyl((0, 0, 0), (0, 0, 0.945), 0.29, 10)

# ----------------------------------------------------------------------------------------------------------------------
# tyre barrier stack: 4 real-looking tyres (flat tread band with ribs + lug slots, chamfered shoulders, sidewall with raised
# lettering ring and bead lip on the visible top tyre, bore), different sizes / yaw / tilt, 2 ratchet straps with buckles.
# ----------------------------------------------------------------------------------------------------------------------
def _tyre_profile(R, top_detail):
    """closed (r, z) profile of a lying tyre (axis Z, centre z=0, half width 0.1). tuple = (r, z, smooth_edge, edge_key, tag)
    where the edge runs from this point to the next one. The bottom sidewall is always the simple (hidden by the next tyre) one.
    edge keys: bore / side / tread / rib_top / groove / letter ; tags drive the lug slots (rib, corner, shoulder) and lettering (L)."""
    P = [(0.197, -0.070, True, 'bore', None), (0.205, -0.100, False, 'side', None), (0.268, -0.100, True, 'side', None),
         (0.296, -0.089, True, 'side', 'shoulder'),
         (R - 0.003, -0.074, True, 'tread', 'corner'), (R, -0.066, True, 'rib_top', 'rib'), (R, -0.020, False, 'groove', 'rib'),
         (R - 0.011, -0.012, False, 'groove', None), (R - 0.011, 0.012, False, 'groove', None), (R, 0.020, True, 'rib_top', 'rib'),
         (R, 0.066, True, 'rib_top', 'rib'), (R - 0.003, 0.074, True, 'tread', 'corner'),
         (0.296, 0.089, True, 'side', 'shoulder')]
    if top_detail:
        P += [(0.280, 0.0975, True, 'side', None), (0.262, 0.100, False, 'side', None), (0.256, 0.100, False, 'side', None),
              (0.254, 0.1045, False, 'letter', 'L'), (0.232, 0.1045, False, 'letter', 'L'), (0.230, 0.100, False, 'side', None),
              (0.214, 0.1035, True, 'bore', None), (0.202, 0.1005, True, 'bore', None), (0.197, 0.070, True, 'bore', None)]
    else:
        P += [(0.268, 0.100, False, 'side', None), (0.205, 0.100, True, 'bore', None), (0.197, 0.070, True, 'bore', None)]
    return P

def _run_bits(rng, n, on=(2, 4), off=(1, 2)):
    """ON/OFF run pattern around n rings (lettering ring: blocks of 'letters' separated by gaps)"""
    bits = []
    state = True
    while len(bits) < n:
        k = rng.randint(*(on if state else off))
        bits += [state] * k
        state = not state
    return bits[:n]

def _tyre(mb, c, R, seg, yaw, tilt, painted, top_detail, phase, col):
    prof = _tyre_profile(R, top_detail)
    Rt = Euler((radians(tilt[0]), radians(tilt[1]), 0.0), 'XYZ').to_matrix()
    RUB, PNT = 'M_RS_TyreRubber', 'M_RS_TyrePaint'
    base_mat = PNT if painted else RUB
    bits = _run_bits(mb.rng, seg)
    drop = {k: mb.rng.random() < 0.22 for k in range((seg + phase) // 3 + 2)}      # a few missing lugs -> irregular, hand-worn pattern
    lowf = lambda i: ((i % seg) + phase) % 3 == 2 and not drop[((i % seg) + phase) // 3]     # one lug slot every third ring
    rings = []
    for i in range(seg):
        a = yaw + 2 * pi * i / seg
        low = lowf(i)
        ring = []
        for (r, z, sm, mk, tag) in prof:
            rr, zz = r, z
            if low:
                if tag == 'rib': rr -= 0.0125
                elif tag == 'corner': rr -= 0.009
                elif tag == 'shoulder': rr -= 0.004
            if tag == 'L' and not bits[i]:
                zz = 0.1005
            q = Rt @ Vector((rr * cos(a), rr * sin(a), zz))
            ring.append(c + q)
        rings.append(ring)
    def fmat(i, j):
        mk = prof[j][3]
        if mk == 'bore' or mk == 'groove': return RUB
        if mk == 'rib_top': return RUB if (not painted or lowf(i)) else PNT
        if mk == 'letter': return PNT if (not painted and bits[i]) else RUB
        return base_mat
    mb.loft(rings, base_mat, True, [p[2] for p in prof], ring_loop=True, face_mat=fmat, col=col)

def _strap(mb, zc, cx, cy, rs, ang, seg=24):
    """ratchet strap sitting in the seam between two tyres: band ring + buckle + a folded tail that follows the tyre curvature"""
    pl = Plane((cx, cy, zc), (1, 0, 0), (0, 1, 0))
    mb.ring_prism(pl, ellipse_pts(0, 0, rs + 0.0045, rs + 0.0045, seg), ellipse_pts(0, 0, rs, rs, seg), -0.018, 0.018,
                  'M_RS_PlasticOrange', 'M_RS_PlasticOrange', 'M_RS_PlasticOrange', smooth_side=True)
    ca, sa = cos(ang), sin(ang)
    rad = Vector((ca, sa, 0)); tan = Vector((-sa, ca, 0))
    cen = Vector((cx, cy, zc)) + rad * (rs + 0.0045 + 0.012)
    mb.obox(cen, (0.024, 0.075, 0.05), 'M_RS_GalvDark', Euler((0, 0, ang), 'XYZ'), c=0.004)
    mb.obox(cen + rad * 0.010 + tan * 0.012, (0.006, 0.05, 0.034), 'M_RS_GalvSteel', Euler((0, 0, ang), 'XYZ'))
    # tail: a flat band lying on top of the strap, curved around the stack
    rt = rs + 0.0045 + 0.002
    path = [Vector((cx + rt * cos(ang + 0.14 + 0.07 * k), cy + rt * sin(ang + 0.14 + 0.07 * k), zc)) for k in range(7)]
    mb.sweep([(-0.002, -0.0165), (0.002, -0.0165), (0.002, 0.0165), (-0.002, 0.0165)], path, 'M_RS_PlasticOrange', True, False, up=(0, 0, 1), cap0=True, cap1=True)

@asset('rs_tyre_stack', 'Tyre barrier stack (4 tyres, strapped)', x=94.0, ext=(-0.4, 0.4), group='trafficfurniture', budget=5200, collision='convex',
       tags=['race_event', 'all_biomes', 'track_side'], scale=(0.9, 1.1),
       usage='Corner outsides / event tracks. Stack of 4 tyres (0.79 m, alternating white-painted / black, bottom tyre white), the top tyre carries the sidewall lettering ring, two ratchet straps in the tyre seams. Convex hull collision.')
def b_tyres(mb):
    rng = mb.rng
    painted = [True, False, True, False]
    Rs = [0.309, 0.313, 0.306, 0.311]
    segs = [30, 30, 30, 36]
    pitch = 0.196
    cens = []
    for i in range(4):
        cx = rng.uniform(-0.007, 0.007); cy = rng.uniform(-0.007, 0.007)
        cz = 0.100 + i * pitch
        cens.append((cx, cy, cz))
        n0 = len(mb.bm.faces)
        col = mb.tint(0.07, (1.0, 0.98, 0.95))
        _tyre(mb, Vector((cx, cy, cz)), Rs[i], segs[i], rng.uniform(0, 6.28), (rng.uniform(-0.7, 0.7), rng.uniform(-0.7, 0.7)), painted[i], i == 3, rng.randrange(3), col)
        mb.speckle(('M_RS_TyrePaint',), 0.04, start=n0)
    for k, ang in ((0, 0.5), (2, 3.6)):
        a, b = cens[k], cens[k + 1]
        _strap(mb, (a[2] + b[2]) / 2 + 0.0, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.2985, ang)
    mb.grime(('M_RS_TyreRubber', 'M_RS_TyrePaint'), 0.35, 0.5)
    mb.hull_cyl((0, 0, 0.0), (0, 0, 0.795), 0.318, 12)
    return dict(tyres=4, height=0.795, outer_diameter=0.62)

# ----------------------------------------------------------------------------------------------------------------------
# hay bale roadblock
# ----------------------------------------------------------------------------------------------------------------------
def _bale(mb, c, L, W, H, yaw, rng):
    """lumpy rounded straw bale, long axis along local X, then rotated by yaw about Z and moved to c (c.z = base).
    Straw strands = per-face vertex-colour streaks along the bale, straw clumps = small tufts poking out of the faces and cut ends."""
    R = Rz(yaw)
    n0 = len(mb.bm.faces)
    prof = rounded_poly([(-W / 2, 0.0), (W / 2, 0.0), (W / 2, H), (-W / 2, H)], 0.07, 2)
    n = 7
    rings = []
    for k in range(n):
        x = -L / 2 + L * k / (n - 1)
        bulge = 1.0 + 0.035 * sin(pi * k / (n - 1))
        ring = []
        for (yy, zz) in prof:
            jy = rng.uniform(-0.012, 0.012); jz = rng.uniform(-0.012, 0.012)
            p = Vector((x, (yy) * bulge + jy, (zz - H / 2) * bulge + H / 2 + jz))
            ring.append(Vector(c) + R @ p)
        rings.append(ring)
    mb.loft(rings, 'M_RS_Hay', True, False, cap0=True, cap1=True, col=mb.tint(0.06, (1.0, 0.97, 0.9)))
    mb.speckle(('M_RS_Hay',), 0.16, start=n0)
    # twine bands
    for fx in (-0.27, 0.27):
        O = Vector(c) + R @ Vector((fx * L, 0, 0))
        pl = Plane(O, R @ Vector((0, 1, 0)), Vector((0, 0, 1)))
        inner = offset_poly(prof, -0.012)
        outer = offset_poly(prof, 0.012)
        mb.ring_prism(pl, outer, inner, -0.015, 0.015, 'M_RS_Rope', 'M_RS_Rope', 'M_RS_Rope')
    # straw tufts: little pointed clumps on the cut ends (x = +-L/2), the top and both long sides
    for t in range(30):
        face = rng.random()
        if face < 0.38:                 # cut ends
            sx = 1 if rng.random() < 0.5 else -1
            lp = Vector((sx * L / 2 * 1.02, rng.uniform(-W / 2 * 0.85, W / 2 * 0.85), rng.uniform(0.05, H - 0.04)))
            nl = Vector((sx, 0, 0))
        elif face < 0.62:               # top
            lp = Vector((rng.uniform(-L / 2 * 0.9, L / 2 * 0.9), rng.uniform(-W / 2 * 0.8, W / 2 * 0.8), H * 1.0))
            nl = Vector((0, 0, 1))
        else:                           # long sides
            sy = 1 if rng.random() < 0.5 else -1
            lp = Vector((rng.uniform(-L / 2 * 0.9, L / 2 * 0.9), sy * W / 2 * 1.01, rng.uniform(0.04, H - 0.05)))
            nl = Vector((0, sy, 0))
        tl = rng.uniform(0.045, 0.105)
        lean = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 0.35
        dirv = (nl + lean).normalized()
        ref = Vector((0, 0, 1)) if abs(dirv.z) < 0.9 else Vector((1, 0, 0))
        u = ref.cross(dirv).normalized(); v = dirv.cross(u)
        base = Vector(c) + R @ (lp - nl * 0.006)
        apex = Vector(c) + R @ (lp + dirv * tl)
        mb.pyramid(base, R @ u, R @ v, rng.uniform(0.007, 0.012), apex, 'M_RS_Hay', col=mb.tint(0.18, (1.08, 1.04, 0.9)))

@asset('rs_hay_bale_roadblock', 'Hay bale roadblock (5 bales + warning board)', x=100.0, ext=(-0.6, 0.6), group='trafficfurniture', budget=3400, collision='box',
       tags=['rural', 'race_event', 'farmland'], scale=(0.9, 1.1), usage='Rally stage / closed-road barrier. Spans Y (2.8 m); front +X.')
def b_hay(mb):
    rng = mb.rng
    L, W, H = 0.92, 0.46, 0.36
    for yy in (-0.96, 0.0, 0.96):
        _bale(mb, (rng.uniform(-0.02, 0.02), yy + rng.uniform(-0.02, 0.02), 0.0), L, W, H, 90 + rng.uniform(-3, 3), rng)
    for yy in (-0.48, 0.48):
        _bale(mb, (rng.uniform(-0.02, 0.02), yy + rng.uniform(-0.02, 0.02), H - 0.01), L, W, H, 90 + rng.uniform(-3, 3), rng)
    # warning board on two stakes in front of the top row
    xf = W / 2 + 0.05
    for yy in (-0.9, 0.9):
        mb.box((xf - 0.03, yy - 0.03, 0.0), (xf + 0.03, yy + 0.03, 1.0), 'M_RS_Wood', c=0.005, col=mb.tint(0.15))
    pl = Plane((xf + 0.03, 0.0, 0.0), (0, 1, 0), (0, 0, 1))
    mb.prism(pl, [(-1.2, 0.72), (1.2, 0.72), (1.2, 0.96), (-1.2, 0.96)], 0.0, 0.02, 'M_RS_PaintWhite', 'M_RS_PaintWhite')
    k = 0.2
    for n in range(0, 15):
        a = -1.5 + n * k
        st = [(a, 0.72), (a + k * 0.5, 0.72), (a + k * 0.5 + 0.24, 0.96), (a + 0.24, 0.96)]
        cl = clip_rect(st, -1.2, 0.72, 1.2, 0.96)
        if len(cl) >= 3 and abs(poly_area(cl)) > 6e-4:
            mb.prism(pl, cl, 0.02, 0.026, 'M_RS_PaintRed', 'M_RS_PaintRed')
    mb.hull_box((-0.3, -1.45, 0.0), (0.3, 1.45, 0.72))
