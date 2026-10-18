"""gc_plants.py - bushes, shrubs, tumble bush, cacti, grass tufts, flowers, reed clumps. exec'd by ground_cover.py"""

def make_lobes(rng, n, ring_r, zc, rxy, rz, centre=True):
    L = []
    if centre: L.append((0.0, 0.0, zc * 1.08, rxy * 1.1, rxy * 1.1, rz * 1.1))
    for i in range(n):
        a = TAU * (i + rng.uniform(-0.2, 0.2)) / n; r = ring_r * rng.uniform(0.7, 1.05)
        L.append((math.cos(a) * r, math.sin(a) * r, zc * rng.uniform(0.85, 1.15), rxy * rng.uniform(0.8, 1.2), rxy * rng.uniform(0.8, 1.2), rz * rng.uniform(0.85, 1.15)))
    return L

# ------------------------------------------------------------------------------------------------ bushes / shrubs
def bush(mb, rng, P):
    H, R = P['H'], P['R']; mat = P.get('mat', 'M_Bush_Leaf')
    lobes = make_lobes(rng, *P['lobegen'])
    vol = [l[3] * l[4] * l[5] for l in lobes]; tot = sum(vol)
    tw = P.get('twig', 1.0)
    for (cx, cy, cz, rx, ry, rz) in lobes:
        c = Vector((cx, cy, cz)); base = Vector((rng.uniform(-.06, .06), rng.uniform(-.06, .06), -0.05))
        pts = bez(base, base + Vector((cx * 0.2, cy * 0.2, cz * 0.7)), c + Vector((-cx * 0.1, -cy * 0.1, -rz * 0.6)), c, 4)
        tube(mb, pts, [0.035 * tw, 0.03 * tw, 0.024 * tw, 0.018 * tw, 0.012 * tw], 5, 'M_Wood_Log', col=lambda t, k: (t, 0.0, 0.55, 0.5), caps=(False, True))
        for _ in range(2):
            d = rand_unit(rng)
            tip = c + Vector((d.x * rx, d.y * ry, abs(d.z) * rz)) * 0.8
            q = bez(pts[2], pts[2].lerp(tip, 0.5) + Vector((0, 0, 0.05)), pts[2].lerp(tip, 0.8), tip, 2)
            tube(mb, q, [0.014 * tw, 0.01 * tw, 0.006 * tw], 4, 'M_Wood_Log', col=lambda t, k: (0.3 + 0.7 * t, 0.0, 0.5, 0.5), caps=(False, True))
    for _ in range(P['n']):
        r = rng.random() * tot; acc = 0.0
        for l, vv in zip(lobes, vol):
            acc += vv
            if r <= acc: break
        cx, cy, cz, rx, ry, rz = l
        d = rand_unit(rng)
        if d.z < -0.35: d.z = -d.z * 0.5; d.normalize()
        shell = 1.0 - P.get('hollow', 0.5) * rng.random() ** 2
        p = Vector((cx + d.x * rx * shell, cy + d.y * ry * shell, cz + d.z * rz * shell))
        if p.z < 0.06: p.z = 0.06 + rng.random() * 0.1
        nrm = Vector((d.x / rx, d.y / ry, d.z / rz)).normalized()
        a = (nrm * 0.55 + rand_unit(rng) * 0.75 + Vector((0, 0, P.get('up', 0.2)))).normalized()
        flex = clamp(0.35 * p.z / H + 0.65 * shell * math.hypot(p.x, p.y) / R)
        ao = clamp(0.30 + 0.70 * ((shell - 0.45) / 0.55)) * (0.6 + 0.4 * clamp(p.z / (0.5 * H)))
        L = P['leaf'][0] * rng.uniform(0.8, 1.25); W = P['leaf'][1] * rng.uniform(0.85, 1.2)
        leaf(mb, p, a, nrm, L, W, mat, fold=0.25, droop=0.3, rnd=rng.random(), flex=flex, ao=ao, diamond=P.get('diamond', False))
    for _ in range(P.get('berries', 0)):
        l = rng.choice(lobes); d = rand_unit(rng); d.z = abs(d.z) * 0.8
        c = Vector((l[0] + d.x * l[3] * 0.95, l[1] + d.y * l[4] * 0.95, l[2] + d.z * l[5] * 0.95))
        sphere_blob(mb, c, (0.025, 0.025, 0.025), 0, 'M_Bush_Berry', col=(0.5, 0.2, 1.0, 0.5))
    return {}

def shrub_cone(mb, rng, P):
    H, R0 = P['H'], P['R']; mat = 'M_Bush_Leaf_Evergreen'
    tube(mb, bez((0, 0, -0.05), (0.02, 0, H * 0.3), (-0.02, 0.02, H * 0.6), (0, 0, H * 0.9), 5), [0.07, 0.06, 0.05, 0.04, 0.02, 0.008], 6, 'M_Wood_Log', col=lambda t, k: (t * 0.4, 0.0, 0.5, 0.5), caps=(False, True))
    for i in range(P['n']):
        z = 0.1 + (H - 0.15) * (rng.random() ** 0.85)
        t = z / H; rmax = R0 * (1 - t) ** 0.85 + 0.03
        ang = rng.uniform(0, TAU); sh = rng.uniform(0.45, 1.0); r = rmax * sh
        out = Vector((math.cos(ang), math.sin(ang), 0)); p = Vector((out.x * r, out.y * r, z))
        a = (out * 0.85 + Vector((0, 0, 0.3)) + rand_unit(rng) * 0.3 - Vector((0, 0, P.get('droop', 0.15)))).normalized()
        nrm = (out * 0.5 + Vector((0, 0, 0.9))).normalized()
        L = P['leaf'][0] * rng.uniform(0.8, 1.2); W = P['leaf'][1] * rng.uniform(0.8, 1.2)
        ao = clamp(0.3 + 0.7 * sh) * (0.7 + 0.3 * clamp(z / 0.5))
        leaf(mb, p, a, nrm, L, W, mat, fold=0.45, droop=0.12, rnd=rng.random(), flex=clamp(0.2 + 0.8 * t), ao=ao)
    return {}

def tumble(mb, rng, P):
    R = P['R']; c = Vector((0, 0, R * 0.9))
    for i in range(P['strands']):
        cp = []
        for k in range(4):
            d = rand_unit(rng); rr = R * rng.uniform(0.5, 1.0)
            cp.append(c + Vector((d.x * rr, d.y * rr, d.z * rr * 0.9)))
        pts = bez(cp[0], cp[1], cp[2], cp[3], 6)
        rad = P['tw'] * rng.uniform(0.7, 1.3)
        tube(mb, pts, [rad * (1 - 0.5 * j / 6) for j in range(7)], 3, 'M_Bush_Dry', col=lambda t, k, cc=c: (0.6, 0.3 * t, 0.35 + 0.65 * t * t, 0.5), caps=(True, True))
        if rng.random() < P.get('leafy', 0.7):
            for _ in range(2):
                q = pts[rng.randrange(1, 6)]; d = rand_unit(rng)
                leaf(mb, q, d, rand_unit(rng), 0.07, 0.025, 'M_Bush_Dry', fold=0.1, droop=0.2, rnd=rng.random(), flex=0.8, ao=0.55 + 0.4 * (q - c).length / R, diamond=True)
    return {}

# ------------------------------------------------------------------------------------------------ cacti
def spine_tuft(mb, p, n, rng, ns=5, ln=0.05, ao=0.9):
    p = Vector(p); n = Vector(n).normalized()
    t1 = n.cross(Z)
    if t1.length < 0.1: t1 = n.cross(Vector((1, 0, 0)))
    t1.normalize(); t2 = n.cross(t1)
    for s in range(ns):
        ang = TAU * s / ns + rng.uniform(0, 0.5)
        d = (n * 0.75 + (t1 * math.cos(ang) + t2 * math.sin(ang)) * 0.55).normalized()
        tip = p + d * ln * rng.uniform(0.7, 1.2); side = d.cross(n)
        side = side.normalized() * 0.0035 if side.length > 1e-6 else t1 * 0.0035
        b0 = mb.v(p + n * 0.004 - side, (0.0, 0.3, ao, 0.5)); b1 = mb.v(p + n * 0.004 + side, (0.0, 0.3, ao, 0.5)); tp = mb.v(tip, (0.0, 1.0, ao, 0.5))
        mb.f([b0, b1, tp], 'M_Cactus_Spine', uv=[(0, 0), (1, 0), (0.5, 1)], smooth=False)

def ribbed(nribs, depth):
    return lambda k, t: 1.0 if k % 2 == 0 else (1.0 - depth)

def flower_head(mb, pos, a, er, size, n_pet, mat_p, mat_c, rng, cup=0.25, ao=0.95, wscale=1.5):
    pos = Vector(pos); a = Vector(a).normalized(); er = Vector(er); er = (er - a * er.dot(a))
    if er.length < 1e-4: er = a.cross(Vector((0.3, 0.8, 0.5)))
    er.normalize(); et = a.cross(er)
    cen = mb.v(pos + a * size * 0.14, (0.3, 0.8, ao, 0.5)); ring = []
    for k in range(6):
        th = TAU * k / 6; ring.append(mb.v(pos + (er * math.cos(th) + et * math.sin(th)) * size * 0.16, (0.3, 0.8, ao, 0.5)))
    for k in range(6): mb.f([cen, ring[k], ring[(k + 1) % 6]], mat_c, uv=[(0.5, 0.5), (0.4, 0.4), (0.6, 0.4)], smooth=False)
    for p in range(n_pet):
        th = TAU * p / n_pet + rng.uniform(-0.1, 0.1)
        dr = er * math.cos(th) + et * math.sin(th); dt = a.cross(dr)
        w = size * 0.5 * math.sin(math.pi / n_pet) * wscale
        inner = pos + dr * size * 0.12 + a * size * 0.05
        mid = pos + dr * size * 0.55 + a * size * cup * 0.3; tip = pos + dr * size + a * size * cup
        col = (0.3, 0.9, ao, rng.random())
        mb.f([mb.v(inner, col), mb.v(mid - dt * w, col), mb.v(tip, col), mb.v(mid + dt * w, col)], mat_p, uv=[(0.5, 0), (0, 0.5), (0.5, 1), (1, 0.5)], smooth=False)

def saguaro(mb, rng, P):
    H, r0 = P['H'], P['r']
    nrib = 12; sides = nrib * 2
    # trunk
    n = 12; pts = []; radii = []
    Hb = H - r0 * 0.95
    for i in range(n + 1):
        t = i / n; sw = P.get('sway', 0.12)
        pts.append(Vector((sw * math.sin(t * 2.3 + P['ph']) * t, sw * 0.5 * math.sin(t * 3.1 + 1.0) * t, -0.1 + (Hb + 0.1) * t)))
        radii.append(r0 * (1.14 - 0.14 * t))
    top = pts[-1]; rt = radii[-1]
    for a_ in (0.4, 0.8, 1.15, 1.4):
        pts.append(top + Vector((0, 0, rt * math.sin(a_)))); radii.append(rt * math.cos(a_))
    res = tube(mb, pts, radii, sides, 'M_Cactus', rib=ribbed(nrib, 0.17), col=lambda t, k: (t * 0.5, 0.0, 0.95 if k % 2 == 0 else 0.5, 0.5), uvv=0.4, caps=(True, True))
    for i in range(1, len(pts) - 4, 2):
        for k in range(0, sides, 2):
            spine_tuft(mb, res['pos'][i][k], res['norm'][i][k], rng, ns=4, ln=0.05)
    for (az, za, out, up, r) in P['arms']:
        Rz = rot_z(az); zz = za
        path = bez(Vector((0, 0, zz)), Vector((out * 0.5, 0, zz + 0.02)), Vector((out, 0, zz + up * 0.2)), Vector((out, 0, zz + up * 0.5)), 9)
        path = [Rz @ p for p in path]
        path += [path[-1] + Vector((0, 0, up * 0.5 * (j + 1) / 3)) for j in range(3)]
        tipp = path[-1]
        for a_ in (0.4, 0.8, 1.15, 1.4): path.append(tipp + Vector((0, 0, r * math.sin(a_))))
        radii_a = [r] * (len(path) - 4) + [r * math.cos(a_) for a_ in (0.4, 0.8, 1.15, 1.4)]
        radii_a[0] = r * 0.9
        ra = tube(mb, path, radii_a, 16, 'M_Cactus', rib=ribbed(8, 0.17), col=lambda t, k: (0.5 + t * 0.5, 0.0, 0.95 if k % 2 == 0 else 0.5, 0.5), uvv=0.4, caps=(False, True))
        for i in range(3, len(path) - 4, 2):
            for k in range(0, 16, 2): spine_tuft(mb, ra['pos'][i][k], ra['norm'][i][k], rng, ns=4, ln=0.045)
    return {}

def barrel(mb, rng, P):
    prof = [(0.0, 0.10), (0.04, 0.20), (0.12, 0.28), (0.24, 0.31), (0.36, 0.29), (0.45, 0.23), (0.51, 0.14), (0.545, 0.06)]
    s = P.get('s', 1.0)
    pts = [Vector((0, 0, z * s)) for z, r in prof]; radii = [r * s for z, r in prof]
    sides = 32
    res = tube(mb, pts, radii, sides, 'M_Cactus', rib=ribbed(16, 0.14), col=lambda t, k: (0.1, 0.0, (0.95 if k % 2 == 0 else 0.55) * (0.5 + 0.5 * t), 0.5), uvv=1.5, caps=(True, True), cap_dz=(0.0, -0.05 * s))
    for i in range(2, 7):
        for k in range(0, sides, 2): spine_tuft(mb, res['pos'][i][k], res['norm'][i][k], rng, ns=6, ln=0.07 * s)
    for f in range(P.get('flowers', 5)):
        ang = TAU * f / P.get('flowers', 5) + rng.uniform(-0.3, 0.3); rr = 0.075 * s
        flower_head(mb, (math.cos(ang) * rr, math.sin(ang) * rr, 0.52 * s), (math.cos(ang) * 0.3, math.sin(ang) * 0.3, 1.0), (math.cos(ang), math.sin(ang), 0), 0.07 * s, 7, 'M_Flower_Center', 'M_Cactus_Fruit', rng, cup=0.3)
    return {}

def prickly(mb, rng, P):
    def pad(c, right, up, n, a, b, th=0.045):
        c = Vector(c); nseg = 14; rings = []
        for lv, (off, sc) in enumerate(((-th * 0.5, 0.9), (0.0, 1.0), (th * 0.5, 0.9))):
            ids = []
            for k in range(nseg):
                tt = TAU * k / nseg
                px = a * sc * math.cos(tt) * (1.0 + 0.04 * math.sin(3 * tt + c.x * 5)); py = b * sc * math.sin(tt)
                p = c + right * px + up * (py * 1.0) + n * off
                ids.append(mb.v(p, (0.2, 0.0, 0.9 if lv else 0.6, 0.5)))
            rings.append(ids)
        cb = mb.v(c - n * th * 0.62, (0.2, 0, 0.7, 0.5)); ct = mb.v(c + n * th * 0.62, (0.2, 0, 0.9, 0.5))
        for k in range(nseg):
            k2 = (k + 1) % nseg
            mb.f([cb, rings[0][k2], rings[0][k]], 'M_Cactus', smooth=True)
            mb.f([rings[0][k], rings[0][k2], rings[1][k2], rings[1][k]], 'M_Cactus', smooth=True)
            mb.f([rings[1][k], rings[1][k2], rings[2][k2], rings[2][k]], 'M_Cactus', smooth=True)
            mb.f([ct, rings[2][k], rings[2][k2]], 'M_Cactus', smooth=True)
        for _ in range(int(10 * a / 0.2)):
            x = rng.uniform(-0.8, 0.8); y = rng.uniform(-0.8, 0.8)
            if x * x + y * y > 0.85: continue
            sgn = 1 if rng.random() < 0.5 else -1
            spine_tuft(mb, c + right * (x * a) + up * (y * b) + n * (sgn * th * 0.62), n * sgn, rng, ns=3, ln=0.04)
    def frame(az, tilt):
        n = Vector((math.cos(az), math.sin(az), 0)); up = Z * math.cos(tilt) + n.cross(Z) * math.sin(tilt)
        up = (up - n * up.dot(n)).normalized(); right = up.cross(n); return right, up, n
    pads = []
    right, up, n = frame(0.3, 0.0)
    root = (Vector((0, 0, 0.22)), right, up, n, 0.2 * P['s'], 0.26 * P['s'])
    pads.append(root); queue = [(root, 1)]
    while queue:
        (c, right, up, n, a, b), lvl = queue.pop(0)
        pad(c, right, up, n, a, b)
        if lvl >= P['levels']: continue
        nch = rng.choice((3, 3, 4)) if lvl == 1 else rng.choice((1, 2))
        for j in range(nch):
            ang = (j - (nch - 1) / 2.0) * (0.95 if lvl == 1 else 0.8) + rng.uniform(-0.2, 0.2)
            R1 = Matrix.Rotation(rng.uniform(0.35, 0.9) * (1 if rng.random() < 0.5 else -1), 3, up)
            n2 = (R1 @ n).normalized()
            up2 = Matrix.Rotation(ang, 3, n2) @ up; up2 = (up2 - n2 * up2.dot(n2)).normalized()
            right2 = up2.cross(n2)
            a2, b2 = a * 0.9, b * 0.9
            c2 = c + up * b * 0.82 + up2 * b2 * 0.72 + right * rng.uniform(-0.25, 0.25) * a
            queue.append(((c2, right2, up2, n2, a2, b2), lvl + 1))
            if lvl + 1 >= P['levels']:
                for _f in range(rng.choice((1, 2, 3))):
                    fc = c2 + up2 * b2 * 0.92 + right2 * rng.uniform(-0.6, 0.6) * a2 + n2 * 0.02
                    sphere_blob(mb, fc, (0.035, 0.035, 0.055), 1, 'M_Cactus_Fruit', col=(0.2, 0.2, 0.95, 0.5), rot=Matrix.Rotation(0.5, 3, 'X'))
    return {}

# ------------------------------------------------------------------------------------------------ grass / flowers / reeds
def grass(mb, rng, P):
    mat = P['mat']; R = P['R']
    for i in range(P['n']):
        r = R * (rng.random() ** 0.6); ang = rng.uniform(0, TAU)
        base = Vector((math.cos(ang) * r, math.sin(ang) * r, -0.01))
        phi = ang + rng.gauss(0, 0.6)
        L = rng.uniform(*P['L']) * (1 - 0.3 * r / R); W = rng.uniform(*P['W'])
        blade(mb, base, phi, L, W, mat, seg=P['seg'], tilt0=rng.uniform(*P['tilt0']) * (0.4 + r / R), curl=rng.uniform(*P['curl']), rnd=rng.random(), twist=rng.uniform(-0.6, 0.6))
    for i in range(P.get('plumes', 0)):
        ang = rng.uniform(0, TAU); r = R * 0.5 * rng.random()
        base = Vector((math.cos(ang) * r, math.sin(ang) * r, -0.01))
        pts = blade(mb, base, ang, P['plume_h'] * rng.uniform(0.9, 1.05), 0.012, P['mat'], seg=5, tilt0=0.05, curl=0.35, rnd=rng.random(), taper=0.2)
        tip = pts[-1]; a = (pts[-1] - pts[-2]).normalized()
        for s in range(4):
            q = tip - a * (0.06 * s)
            d = (a * 1.0 + Vector((math.cos(s * 1.9), math.sin(s * 1.9), 0)) * 0.5).normalized()
            leaf(mb, q, d, Z.cross(d) if abs(d.z) < 0.9 else Vector((1, 0, 0)), 0.09, 0.02, P.get('plume_mat', mat), fold=0.1, droop=0.1, rnd=rng.random(), flex=1.0, ao=0.9, diamond=True)
    return {}

def flower_patch(mb, rng, P):
    R = P['R']
    for i in range(P['tuft']):
        r = R * 0.9 * rng.random() ** 0.7; ang = rng.uniform(0, TAU)
        blade(mb, Vector((math.cos(ang) * r, math.sin(ang) * r, -0.01)), ang + rng.gauss(0, .6), rng.uniform(0.12, 0.26), rng.uniform(0.012, 0.022), 'M_Grass_Blade', seg=3, tilt0=0.3, curl=0.6, rnd=rng.random())
    for i in range(P['n']):
        r = R * math.sqrt(rng.random()); ang = rng.uniform(0, TAU)
        base = Vector((math.cos(ang) * r, math.sin(ang) * r, -0.01))
        Hh = rng.uniform(*P['h']); phi = rng.uniform(0, TAU)
        pts = blade(mb, base, phi, Hh, 0.012, 'M_Grass_Blade', seg=4, tilt0=rng.uniform(0.05, 0.25), curl=rng.uniform(0.1, 0.4), rnd=rng.random(), taper=0.2, flex=1.0)
        a = (pts[-1] - pts[-2]).normalized()
        face = (Z * 0.75 + a * 0.35).normalized()
        flower_head(mb, pts[-1], face, rand_unit(rng), P['size'] * rng.uniform(0.85, 1.15), P['npet'], P['petal'], P['center'], rng, cup=P.get('cup', 0.25), wscale=P.get('wscale', 1.5))
        for _ in range(2):
            blade(mb, base + Vector((0, 0, Hh * rng.uniform(0.1, 0.35))), rng.uniform(0, TAU), rng.uniform(0.07, 0.12), 0.018, 'M_Grass_Blade', seg=2, tilt0=0.8, curl=0.4, rnd=rng.random())
    return {}

def reeds(mb, rng, P):
    R = P['R']
    for i in range(P['n']):
        r = R * rng.random() ** 0.7; ang = rng.uniform(0, TAU)
        blade(mb, Vector((math.cos(ang) * r, math.sin(ang) * r, -0.02)), ang + rng.gauss(0, 0.5), rng.uniform(*P['L']), rng.uniform(*P['W']), 'M_Reed', seg=5,
              tilt0=rng.uniform(*P['tilt0']) * (0.5 + r / R), curl=rng.uniform(*P['curl']), rnd=rng.random(), taper=0.7, twist=rng.uniform(-0.5, 0.5))
    for i in range(P['stalks']):
        ang = rng.uniform(0, TAU); r = R * 0.6 * rng.random()
        h = rng.uniform(*P['stalk_h']); lean = Vector((math.cos(ang), math.sin(ang), 0)) * rng.uniform(0.05, 0.28) * h
        p0 = Vector((math.cos(ang) * r, math.sin(ang) * r, -0.02))
        pts = bez(p0, p0 + Vector((0, 0, h * 0.4)), p0 + lean * 0.6 + Vector((0, 0, h * 0.8)), p0 + lean + Vector((0, 0, h)), 6)
        tube(mb, pts, [0.007 - 0.002 * j / 6 for j in range(7)], 3, 'M_Reed', col=lambda t, k: (t, 0.2 * t, 0.5 + 0.5 * t, 0.5), caps=(False, True))
        if P['head'] == 'cattail':
            hp = [pts[4].lerp(pts[5], 0.3), pts[4].lerp(pts[5], 0.45), pts[4].lerp(pts[5], 1.0) .lerp(pts[6], 0.0), pts[5].lerp(pts[6], 0.4)]
            tube(mb, hp, [0.003, 0.018, 0.018, 0.003], 6, 'M_Reed_Head', col=lambda t, k: (1.0, 0.8, 0.9, 0.5), caps=(True, True))
        else:
            tip = pts[-1]; a = (pts[-1] - pts[-2]).normalized()
            for s in range(5):
                d = (a + Vector((math.cos(s * 1.26), math.sin(s * 1.26), 0)) * 0.55).normalized()
                leaf(mb, tip - a * 0.04 * s, d, Z.cross(d) if abs(d.z) < 0.9 else Vector((1, 0, 0)), 0.16, 0.035, 'M_Reed_Head', fold=0.1, droop=0.3, rnd=rng.random(), flex=1.0, ao=0.9, diamond=True)
    return {}

# ------------------------------------------------------------------------------------------------ registry
TEMP = ['temperate', 'forest', 'meadow', 'farmland', 'park']
reg('nat_bush_leafy_a', 'bushes', fn=bush, seed=2101, name='Leafy bush - round mound', biome=TEMP, scale=(0.8, 1.4), w=3.0, wind=True, budget=(2500, 8000), sink=None,
    P=dict(H=1.25, R=0.85, lobegen=(5, 0.38, 0.62, 0.42, 0.45), n=1250, leaf=(0.14, 0.08), hollow=0.5, up=0.2))
reg('nat_bush_leafy_b', 'bushes', fn=bush, seed=2102, name='Leafy bush - tall vase shrub', biome=TEMP, scale=(0.8, 1.3), w=2.6, wind=True, budget=(2500, 8000), sink=None,
    P=dict(H=1.6, R=0.6, lobegen=(4, 0.22, 0.9, 0.3, 0.68), n=1300, leaf=(0.16, 0.045), hollow=0.7, up=0.45, twig=1.2))
reg('nat_bush_leafy_c', 'bushes', fn=bush, seed=2103, name='Leafy bush - low spreading with berries', biome=TEMP, scale=(0.8, 1.4), w=3.4, wind=True, budget=(2500, 8000), sink=None,
    P=dict(H=1.0, R=1.05, lobegen=(6, 0.62, 0.45, 0.42, 0.38), n=1100, leaf=(0.13, 0.075), hollow=0.5, up=0.15, berries=16))
reg('nat_shrub_evergreen_a', 'bushes', fn=bush, seed=2201, name='Evergreen shrub - dense dome (boxwood)', biome=['temperate', 'mediterranean', 'urban', 'park'], scale=(0.8, 1.4), w=2.8, wind=True, budget=(2500, 8000), sink=None,
    P=dict(H=1.0, R=0.8, mat='M_Bush_Leaf_Evergreen', lobegen=(3, 0.3, 0.5, 0.45, 0.42), n=2000, leaf=(0.075, 0.05), diamond=True, hollow=0.35, up=0.1, twig=0.8))
reg('nat_shrub_evergreen_b', 'bushes', fn=shrub_cone, seed=2202, name='Evergreen shrub - conical juniper', biome=['alpine', 'highland', 'mediterranean', 'park'], scale=(0.8, 1.5), w=2.0, wind=True, budget=(2000, 8000), sink=None,
    P=dict(H=1.7, R=0.55, n=720, leaf=(0.27, 0.08), droop=0.15))
reg('nat_bush_tumble', 'bushes', fn=tumble, seed=2301, name='Dry tumble scrub bush', biome=['desert', 'steppe', 'badlands', 'savanna'], scale=(0.7, 1.5), w=2.0, wind=True, budget=(1500, 8000), sink=0.0,
    P=dict(R=0.55, strands=85, tw=0.0095, leafy=0.7))

DES = ['desert', 'canyon', 'badlands', 'savanna']
reg('nat_cactus_saguaro_a', 'cacti', fn=saguaro, seed=3101, name='Saguaro cactus - two arms', biome=DES, scale=(0.8, 1.3), w=4.0, coll='all', ndir=24, budget=(1500, 9000), sink=None,
    coll_note='UCX_01: single convex hull around the trunk + arm roots (arms/tips have no collision). UE: Simple As Complex',
    P=dict(H=4.8, r=0.30, ph=0.5, sway=0.12, arms=[(75, 2.5, 1.0, 1.9, 0.19), (250, 3.3, 0.85, 1.2, 0.17)]))
reg('nat_cactus_saguaro_b', 'cacti', fn=saguaro, seed=3102, name='Saguaro cactus - tall three arms', biome=DES, scale=(0.8, 1.3), w=4.0, coll='all', ndir=24, budget=(2500, 9000), sink=None,
    coll_note='UCX_01: single convex hull around the trunk + arm roots (arms/tips have no collision). UE: Simple As Complex',
    P=dict(H=5.9, r=0.34, ph=2.0, sway=0.18, arms=[(30, 2.2, 1.2, 2.5, 0.21), (200, 3.0, 1.0, 2.0, 0.19), (115, 4.1, 0.7, 0.9, 0.14)]))
reg('nat_cactus_barrel', 'cacti', fn=barrel, seed=3201, name='Barrel cactus with crown flowers', biome=DES, scale=(0.7, 1.6), w=1.6, coll='all', ndir=24, budget=(800, 5000), sink=None,
    coll_note='UCX_01 single hull', P=dict(s=1.0, flowers=5))
reg('nat_cactus_pricklypear', 'cacti', fn=prickly, seed=3301, name='Prickly pear cactus cluster', biome=DES + ['mediterranean'], scale=(0.7, 1.5), w=2.4, coll='all', ndir=20, budget=(800, 6000), sink=None,
    coll_note='UCX_01 single hull', P=dict(s=1.0, levels=3))

reg('nat_grass_lush', 'grass', fn=grass, seed=4101, name='Grass tuft - lush', biome=TEMP + ['riverside'], scale=(0.7, 1.6), w=1.2, wind=True, budget=(150, 2000), sink=None,
    P=dict(mat='M_Grass_Blade', n=110, R=0.28, L=(0.30, 0.55), W=(0.016, 0.028), seg=3, tilt0=(0.05, 0.3), curl=(0.35, 1.0)))
reg('nat_grass_dry', 'grass', fn=grass, seed=4102, name='Grass tuft - dry', biome=['desert', 'steppe', 'savanna', 'badlands'], scale=(0.7, 1.6), w=1.2, wind=True, budget=(150, 2000), sink=None,
    P=dict(mat='M_Grass_Dry', n=90, R=0.28, L=(0.25, 0.5), W=(0.012, 0.022), seg=3, tilt0=(0.1, 0.4), curl=(0.5, 1.3), plumes=7, plume_h=0.62))
reg('nat_grass_reeds_tall', 'grass', fn=grass, seed=4103, name='Tall reed grass 1.5 m', biome=['riverside', 'wetland', 'meadow', 'coast'], scale=(0.7, 1.4), w=1.6, wind=True, budget=(150, 2500), sink=None,
    P=dict(mat='M_Reed', n=46, R=0.38, L=(1.1, 1.55), W=(0.018, 0.034), seg=5, tilt0=(0.02, 0.12), curl=(0.15, 0.55), plumes=8, plume_h=1.5, plume_mat='M_Grass_Dry'))

reg('nat_flowers_a', 'grass', fn=flower_patch, seed=4201, name='Flower patch - white daisies', biome=TEMP, scale=(0.8, 1.6), w=1.6, wind=True, budget=(300, 2500), sink=None,
    P=dict(R=0.55, n=13, tuft=32, h=(0.26, 0.45), size=0.055, npet=9, petal='M_Flower', center='M_Flower_Center', cup=0.2, wscale=1.4))
reg('nat_flowers_b', 'grass', fn=flower_patch, seed=4202, name='Flower patch - purple wildflowers', biome=TEMP + ['highland'], scale=(0.8, 1.6), w=1.6, wind=True, budget=(300, 2500), sink=None,
    P=dict(R=0.55, n=11, tuft=32, h=(0.28, 0.5), size=0.07, npet=5, petal='M_Flower_B', center='M_Flower_Center', cup=0.5, wscale=1.9))

reg('nat_reeds_a', 'grass', fn=reeds, seed=4301, name='Reed clump - cattails', biome=['riverside', 'wetland', 'coast'], scale=(0.8, 1.5), w=1.8, wind=True, budget=(300, 3000), sink=None,
    P=dict(R=0.4, n=26, L=(0.9, 1.5), W=(0.025, 0.042), tilt0=(0.03, 0.2), curl=(0.2, 0.7), stalks=7, stalk_h=(1.35, 1.8), head='cattail'))
reg('nat_reeds_b', 'grass', fn=reeds, seed=4302, name='Reed clump - sedge with plumes', biome=['riverside', 'wetland', 'coast'], scale=(0.8, 1.5), w=1.8, wind=True, budget=(300, 3000), sink=None,
    P=dict(R=0.4, n=30, L=(0.8, 1.25), W=(0.035, 0.055), tilt0=(0.05, 0.3), curl=(0.5, 1.1), stalks=6, stalk_h=(1.2, 1.55), head='plume'))
