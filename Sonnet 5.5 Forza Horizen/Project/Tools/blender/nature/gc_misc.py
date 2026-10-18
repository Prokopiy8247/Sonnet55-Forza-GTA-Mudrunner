"""gc_misc.py - crops, hay, wood, beach props, sign post. exec'd by ground_cover.py"""

# ------------------------------------------------------------------------------------------------ wheat row (4 m, along +X from the origin)
def wheat_row(mb, rng, P):
    Lr, Wd = 4.0, P['W']
    nx, ny = 24, 6
    ids = []
    for i in range(nx + 1):
        row = []
        for j in range(ny + 1):
            x = Lr * i / nx; y = (j / ny - 0.5) * Wd * 1.25
            h = 0.12 * max(0.0, 1.0 - (2 * y / (Wd * 1.25)) ** 2) ** 0.7 + 0.015 * fbm((x, y, 0), 1.0, 3.0, 2)
            row.append(mb.v((x, y, h - 0.005), (0.0, 0.0, 0.5 + 0.5 * (h / 0.13), 0.5)))
        ids.append(row)
    for i in range(nx):
        for j in range(ny):
            mb.f([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]], 'M_Crop_Soil', uvs=0.5)
    for k in range(P['n']):
        x = (k + rng.uniform(0.0, 1.0)) * Lr / P['n']; y = max(-Wd / 2.2, min(Wd / 2.2, rng.gauss(0, Wd / 4.2)))
        base = Vector((x, y, 0.05))
        Hh = rng.uniform(0.78, 1.0); phi = rng.uniform(0, TAU)
        pts = blade(mb, base, phi, Hh, 0.009, 'M_Crop', seg=3, tilt0=rng.uniform(0.02, 0.18), curl=rng.uniform(0.15, 0.5), rnd=rng.random(), ao0=0.4, taper=0.1, flex=1.0)
        a = (pts[-1] - pts[-2]).normalized(); tip = pts[-1]
        eh = [tip - a * 0.012, tip + a * 0.045 + Z * 0.0, tip + a * 0.105 - Z * 0.008, tip + a * 0.15 - Z * 0.02]
        tube(mb, eh, [0.0065, 0.0105, 0.0095, 0.0015], 3, 'M_Crop_Ear', col=lambda t, kk: (1.0, 0.6 + 0.4 * t, 0.95, 0.5), caps=(False, True))
        for _ in range(2):
            blade(mb, base + Vector((0, 0, Hh * rng.uniform(0.08, 0.45))), rng.uniform(0, TAU), rng.uniform(0.28, 0.42), 0.017, 'M_Crop', seg=2, tilt0=0.75, curl=0.55, rnd=rng.random(), ao0=0.45)
    return {}

# ------------------------------------------------------------------------------------------------ hay
def round_bale(mb, rng, P):
    R, half = P['R'], P['Wd'] / 2
    zc = R - 0.02; nth = 32; nrow = 10
    def pos(th, y, rho): return Vector((rho * math.sin(th), y, zc + rho * math.cos(th)))
    rows = []
    for j in range(nrow + 1):
        y = -half + 2 * half * j / nrow
        edge = sstep(half * 0.86, half, abs(y))
        row = []
        for k in range(nth):
            th = TAU * k / nth
            rho = R * (1 - 0.075 * edge * edge) * (1 + 0.012 * fbm((math.sin(th) * 3, y * 2.5, math.cos(th) * 3), P['seed'], 1.0, 3))
            p = pos(th, y, rho)
            row.append(mb.v(p, (0.0, 0.0, 0.62 + 0.38 * (1 - edge) * 0.8 + 0.1, 0.5)))
        rows.append(row)
    for j in range(nrow):
        for k in range(nth):
            k2 = (k + 1) % nth
            mb.f([rows[j][k], rows[j][k2], rows[j + 1][k2], rows[j + 1][k]], 'M_Hay', uv=[(k / nth, j / nrow * 1.2), ((k + 1) / nth, j / nrow * 1.2), ((k + 1) / nth, (j + 1) / nrow * 1.2), (k / nth, (j + 1) / nrow * 1.2)])
    # twine bands (raised thin strips)
    for yb in (-0.38 * half * 2, -0.14 * half * 2, 0.14 * half * 2, 0.38 * half * 2):
        r0 = []; r1 = []
        for k in range(nth):
            th = TAU * k / nth
            for lst, dy in ((r0, -0.012), (r1, 0.012)):
                lst.append(mb.v(pos(th, yb + dy, R * 1.012), (0.0, 0.0, 0.8, 0.5)))
        for k in range(nth):
            k2 = (k + 1) % nth
            mb.f([r0[k], r0[k2], r1[k2], r1[k]], 'M_Hay_Twine', smooth=True)
    # spiral-grooved end faces
    rim_r = R * (1 - 0.075)
    for sgn in (-1, 1):
        prev = rows[0] if sgn < 0 else rows[-1]
        nr = 8
        ring_prev = prev
        for m in range(1, nr + 1):
            rho = rim_r * (1 - m / nr) if m < nr else 0.0
            ring = []
            if m < nr:
                for k in range(nth):
                    th = TAU * k / nth
                    g = 0.028 * (0.5 + 0.5 * math.sin(TAU * (rho / R * 4.5) + th)) + 0.01 * fbm((rho * math.sin(th) * 4, 0, rho * math.cos(th) * 4), 3.0, 1.0, 2)
                    ring.append(mb.v(pos(th, sgn * (half - g - 0.0), rho), (0.0, 0.0, 0.55 + 0.35 * (1 - m / nr) * 0.5 + 0.2 * g * 20, 0.5)))
                for k in range(nth):
                    k2 = (k + 1) % nth
                    if sgn > 0: mb.f([ring_prev[k], ring_prev[k2], ring[k2], ring[k]], 'M_Hay', smooth=True, uvs=0.5)
                    else: mb.f([ring[k], ring[k2], ring_prev[k2], ring_prev[k]], 'M_Hay', smooth=True, uvs=0.5)
                ring_prev = ring
            else:
                cen = mb.v(pos(0, sgn * (half - 0.03), 0.0), (0.0, 0.0, 0.5, 0.5))
                for k in range(nth):
                    k2 = (k + 1) % nth
                    if sgn > 0: mb.f([cen, ring_prev[k], ring_prev[k2]], 'M_Hay', smooth=True, uvs=0.5)
                    else: mb.f([cen, ring_prev[k2], ring_prev[k]], 'M_Hay', smooth=True, uvs=0.5)
    hulls = []
    pts = [pos(TAU * k / 12, sgn * half * 0.96, R * 0.96) for sgn in (-1, 1) for k in range(12)]
    return {'hulls': [pts]}

def rbox_grid(mb, c, size, rot, mat, rng, seed, k=0.2, div=(7, 4, 3), amp=0.012):
    """rounded box built from 6 welded grids. size = full extents"""
    weld = {}
    def vid(p):
        key = (round(p.x, 5), round(p.y, 5), round(p.z, 5))
        if key in weld: return weld[key]
        # rounded-box mapping
        inner = Vector((max(-(1 - k), min(1 - k, p.x)), max(-(1 - k), min(1 - k, p.y)), max(-(1 - k), min(1 - k, p.z))))
        d = p - inner
        q = inner + (d.normalized() * k if d.length > 1e-9 else d)
        w = Vector((q.x * size[0] / 2, q.y * size[1] / 2, q.z * size[2] / 2))
        w = w + (q.normalized() * amp * fbm(w, seed, 9.0, 3) if q.length > 1e-6 else Vector())
        ao = 0.65 + 0.35 * (1 - max(abs(q.x), abs(q.y), abs(q.z)) ** 4)
        i = mb.v(c + rot @ w, (0.0, 0.0, ao, 0.5)); weld[key] = i; return i
    axes = [(0, 1, 2), (1, 2, 0), (2, 0, 1)]
    for ax, (a1, a2, a3) in enumerate(axes):
        for sgn in (-1, 1):
            n1, n2 = div[a1], div[a2]
            grid = []
            for i in range(n1 + 1):
                row = []
                for j in range(n2 + 1):
                    p = [0.0, 0.0, 0.0]; p[a1] = -1 + 2 * i / n1; p[a2] = -1 + 2 * j / n2; p[a3] = sgn
                    row.append(vid(Vector(p)))
                grid.append(row)
            nrm = [0, 0, 0]; nrm[a3] = sgn
            for i in range(n1):
                for j in range(n2):
                    q = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
                    p0, p1, p2 = [Vector(mb.V[t]) for t in q[:3]]
                    nn = (p1 - p0).cross(p2 - p0)
                    if nn.dot(rot @ Vector(nrm)) < 0: q = q[::-1]
                    mb.f(q, mat, smooth=True, uvs=1.0)

def bale_stack(mb, rng, P):
    sx, sy, sz = 0.46, 0.9, 0.36
    layout = [(0, 3), (1, 2), (2, 1)]
    for layer, cnt in layout:
        for r in range(2):
            for i in range(cnt):
                y = (i - (cnt - 1) / 2) * (sy + 0.025)
                x = (r - 0.5) * (sx + 0.02)
                z = sz / 2 + layer * (sz + 0.005) - 0.01
                rot = rot_euler(0, 0, rng.uniform(-2.5, 2.5))
                c = Vector((x + rng.uniform(-0.015, 0.015), y + rng.uniform(-0.02, 0.02), z))
                rbox_grid(mb, c, (sx, sy, sz), rot, 'M_Hay', rng, rng.uniform(0, 50), k=0.2)
                for sy_ in (-0.2, 0.2):
                    # two twine straps around the long axis: top + both sides
                    box(mb, c + rot @ Vector((0, sy_, sz / 2 + 0.002)), (sx * 0.98, 0.028, 0.008), 'M_Hay_Twine', rot=rot, col=(0, 0, 0.8, 0.5))
                    for sx_ in (-1, 1):
                        box(mb, c + rot @ Vector((sx_ * (sx / 2 + 0.002), sy_, 0)), (0.008, 0.028, sz * 0.96), 'M_Hay_Twine', rot=rot, col=(0, 0, 0.8, 0.5))
    return {}

# ------------------------------------------------------------------------------------------------ wood
def log_obj(mb, p0, p1, r0, r1, rng, sides=10, amp=0.07, seed=0.0, mid_wobble=0.0):
    p0, p1 = Vector(p0), Vector(p1); ax = p1 - p0
    n = 3
    pts = [p0 + ax * (i / n) + (rand_unit(rng) * mid_wobble if 0 < i < n else Vector()) for i in range(n + 1)]
    radii = [lerp(r0, r1, i / n) for i in range(n + 1)]
    return tube(mb, pts, radii, sides, 'M_Wood_Log', rib=lambda k, t: 1.0 + amp * nz((k * 0.9, t * 2.0, 0), seed, 1.0) + amp * 0.5 * (1 if k % 2 else -1) * 0.3,
                col=lambda t, k: (0.0, 0.0, 0.55 + 0.4 * (1 if k % 2 == 0 else 0.6), 0.5), caps=(True, True), cap_dz=(-0.012, -0.012), mat_end='M_Wood_LogEnd', uvv=0.7)

def log_pile(mb, rng, P):
    r = 0.18; d = 2 * r * 1.03
    for row, cnt in enumerate((5, 4, 3, 2)):
        for i in range(cnt):
            x = (i - (cnt - 1) / 2) * d + rng.uniform(-0.01, 0.01); z = r + row * d * 0.866 + 0.0
            rr = rng.uniform(0.15, 0.195); ln = rng.uniform(1.85, 2.2); y0 = rng.uniform(-0.1, 0.1) - ln / 2
            log_obj(mb, (x, y0, z), (x + rng.uniform(-0.02, 0.02), y0 + ln, z + rng.uniform(-0.02, 0.02)), rr, rr * rng.uniform(0.9, 1.0), rng, seed=rng.uniform(0, 30))
    return {}

def fallen_log(mb, rng, P):
    n = 10; pts = []; radii = []
    for i in range(n + 1):
        t = i / n
        pts.append(Vector((4.6 * t, 0.12 * math.sin(t * 2.4) + 0.05 * math.sin(t * 7), 0.30 + 0.04 * math.sin(t * 3.0) - 0.05 * t)))
        radii.append(0.34 - 0.08 * t + 0.02 * nz((t * 5, 0, 0), 1.0, 1.0))
    res = tube(mb, pts, radii, 18, 'M_Wood_Log', rib=lambda k, t: 1.0 + 0.09 * nz((k * 0.75, t * 4.0, 0), 5.0, 1.0) + 0.04 * (1 if k % 2 else -1),
               col=lambda t, k: (0.0, 0.0, 0.55 + 0.4 * (1 if k % 2 == 0 else 0.6), 0.5), caps=(True, False), cap_dz=(-0.02, 0), mat_end='M_Wood_LogEnd', uvv=0.6)
    # jagged broken end
    last = [Vector(p) for p in res['pos'][-1]]; T = res['T'][-1]; c = sum(last, Vector()) / len(last)
    mb.grp = 1
    tips = []
    for k in range(18):
        base_k = res['rings'][-1][k]
        tp = last[k].lerp(c, 0.35) + T * (0.05 + 0.32 * rng.random() * (1 if k % 2 == 0 else 0.4))
        tips.append(mb.v(tp, (0.2, 0.2, 0.8, 0.5)))
    for k in range(18):
        k2 = (k + 1) % 18
        mb.f([res['rings'][-1][k], res['rings'][-1][k2], tips[k2], tips[k]], 'M_Wood_LogEnd', smooth=False)
    # fan inside the broken crown (tip ring -> centre)
    cen2 = mb.v(c + T * 0.18, (0.2, 0.2, 0.7, 0.5))
    for k in range(18):
        mb.f([cen2, tips[(k + 1) % 18], tips[k]], 'M_Wood_LogEnd', smooth=False)
    # branch stubs
    for s in range(6):
        i = rng.randrange(1, n - 1); k = rng.randrange(1, 17)
        pp = Vector(res['pos'][i][k]); nn = res['norm'][i][k]
        d = (nn * 0.8 + Z * 0.5 + res['T'][i] * rng.uniform(-0.3, 0.3)).normalized()
        L = rng.uniform(0.25, 0.55)
        sp = [pp - d * 0.05, pp + d * L * 0.5, pp + d * L]
        tube(mb, sp, [0.06, 0.045, 0.03], 6, 'M_Wood_Log', col=lambda t, kk: (0.3 + 0.7 * t, 0.0, 0.7, 0.5), caps=(False, True), mat_end='M_Wood_LogEnd', cap_dz=(0, -0.01))
    mb.grp = 0
    return {'slabs': 3}

def stump(mb, rng, P):
    h = 0.55; r = 0.42; sides = 20
    zs = [-0.12, 0.0, 0.1, 0.25, 0.42, h]
    radii = [r * 1.28, r * 1.2, r * 1.08, r * 1.0, r * 0.97, r * 0.96]
    pts = [Vector((0.02 * math.sin(z * 4), 0.0, z)) for z in zs]
    ph = rng.uniform(0, TAU)
    res = tube(mb, pts, radii, sides, 'M_Wood_Log', rib=lambda k, t: 1.0 + 0.2 * (1 - t) ** 3 * (0.5 + 0.5 * math.cos(5 * TAU * k / sides + ph)) + 0.05 * nz((k * 0.7, t * 3, 0), 2.0, 1.0),
               col=lambda t, k: (0.0, 0.0, 0.5 + 0.45 * t + 0.1 * (k % 2), 0.5), caps=(True, False), cap_dz=(-0.02, 0), uvv=0.6)
    top = res['rings'][-1]
    for k, i in enumerate(top):
        x, y, z = mb.V[i]; th = TAU * k / sides
        mb.V[i] = (x, y, z + 0.035 * math.cos(th + 0.6) + 0.01 * nz((x * 6, y * 6, 0), 3.0, 1.0))
    prev = top
    for m, (sc, dz) in enumerate(((0.84, -0.012), (0.66, 0.008), (0.48, -0.010), (0.30, 0.006), (0.14, -0.008))):
        ring = []
        for k, i in enumerate(top):
            x, y, z = mb.V[i]; cx_, cy_ = pts[-1].x, pts[-1].y
            ring.append(mb.v((cx_ + (x - cx_) * sc, cy_ + (y - cy_) * sc, z + dz + 0.01 * nz((x * 5, y * 5, 0), 4.0 + m, 1.0)), (0.0, 0.0, 0.9, 0.5)))
        for k in range(sides):
            k2 = (k + 1) % sides
            mb.f([prev[k], prev[k2], ring[k2], ring[k]], 'M_Wood_LogEnd', smooth=True, uvs=1.0)
        prev = ring
    cz = sum(mb.V[i][2] for i in prev) / sides
    cen = mb.v((pts[-1].x, pts[-1].y, cz + 0.006), (0.0, 0.0, 0.9, 0.5))
    for k in range(sides):
        mb.f([cen, prev[k], prev[(k + 1) % sides]], 'M_Wood_LogEnd', smooth=True, uvs=1.0)
    return {}

# ------------------------------------------------------------------------------------------------ beach props
def beach_umbrella(mb, rng, P):
    tilt = Matrix.Rotation(math.radians(7), 3, 'Y')
    def T(p): return tilt @ Vector(p)
    ptsP = [T((0, 0, -0.18 + i * (2.55 / 4))) for i in range(5)]
    resP = tube(mb, ptsP, [0.024] * 5, 8, 'M_Beach_Metal', col=lambda t, k: (0.0, 0.0, 0.85, 0.5), caps=(True, True), uvv=1.0)
    Rr, zt, zr = 1.15, 2.4, 2.02
    ng = 8; nr = 6; nc = 4
    apex = mb.v(T((0, 0, zt)), (0.1, 1.0, 1.0, 0.5))
    grid = {}
    for g in range(ng):
        for r in range(1, nr + 1):
            for s in range(nc + 1):
                a = TAU * (g + s / nc) / ng
                rf = r / nr
                sag = 0.045 * math.sin(math.pi * s / nc) * rf
                rim = 1 - 0.035 * math.sin(math.pi * s / nc) * (rf ** 4)
                rad = Rr * rf * rim
                z = zr + (zt - zr) * (1 - rf ** 2.1) - sag
                grid[(g, r, s)] = mb.v(T((rad * math.cos(a), rad * math.sin(a), z)), (rf * 0.6, rf ** 2, 1.0 - 0.25 * rf, 0.5))
    for g in range(ng):
        mat = 'M_Beach_Red' if g % 2 == 0 else 'M_Beach_White'
        for s in range(nc):
            mb.f([apex, grid[(g, 1, s)], grid[(g, 1, s + 1)]], mat, uv=[(0.5, 0), (s / nc, 1 / nr), ((s + 1) / nc, 1 / nr)])
            for r in range(1, nr):
                mb.f([grid[(g, r, s)], grid[(g, r + 1, s)], grid[(g, r + 1, s + 1)], grid[(g, r, s + 1)]], mat,
                     uv=[(s / nc, r / nr), (s / nc, (r + 1) / nr), ((s + 1) / nc, (r + 1) / nr), ((s + 1) / nc, r / nr)])
    for g in range(ng):
        a = TAU * g / ng
        rp = [T((Rr * rf * math.cos(a), Rr * rf * math.sin(a), zr + (zt - zr) * (1 - rf ** 2.1) - 0.012)) for rf in (0.0, 0.35, 0.7, 1.0)]
        tube(mb, rp, [0.007, 0.006, 0.005, 0.0045], 3, 'M_Beach_Metal', col=lambda t, k: (0.0, 0.0, 0.9, 0.5), caps=(False, True))
    sphere_blob(mb, T((0, 0, zt + 0.04)), (0.03, 0.03, 0.04), 1, 'M_Beach_Metal', col=(0, 0, 1, 0.5))
    pole_pts = [Vector(p) for p in resP['pos'][0]] + [Vector(p) for p in resP['pos'][-1]]
    return {'hulls': [pole_pts]}

def lounger(mb, rng, P):
    th = math.radians(50); rotb = Matrix.Rotation(-th, 3, 'Y')
    hinge = Vector((-0.30, 0, 0.30))
    W = 0.62
    # flat section slats
    for i in range(10):
        x = -0.27 + i * 0.125
        box(mb, Vector((x, 0, 0.30)), (0.095, W, 0.025), 'M_Wood_Plank')
    # reclined back
    along = Vector((-math.cos(th), 0, math.sin(th)))
    for i in range(6):
        c = hinge + along * (0.06 + i * 0.125)
        box(mb, c, (0.095, W, 0.025), 'M_Wood_Plank', rot=Matrix.Rotation(th, 3, 'Y'))
    for sy in (-1, 1):
        y = sy * (W / 2 + 0.02)
        box(mb, Vector((0.33, y, 0.30)), (1.28, 0.04, 0.05), 'M_Wood_Plank')
        box(mb, hinge + along * 0.37 + Vector((0, y, 0)), (0.80, 0.04, 0.05), 'M_Wood_Plank', rot=Matrix.Rotation(th, 3, 'Y'))
        for lx in (-0.22, 0.88):
            box(mb, Vector((lx, y, 0.15)), (0.05, 0.05, 0.30), 'M_Wood_Plank')
    for sy in (-1, 1):
        box(mb, Vector((-0.66, sy * (W / 2 + 0.02), 0.38)), (0.04, 0.04, 0.76), 'M_Wood_Plank')
    # cushions
    box(mb, Vector((0.33, 0, 0.352)), (1.22, W * 0.92, 0.07), 'M_Beach_Blue', col=(0, 0, 0.9, 0.5), smooth=True)
    box(mb, hinge + along * 0.37 + Vector((0, 0, 0)) + Vector((0.037 * math.sin(th), 0, 0.037 * math.cos(th))), (0.74, W * 0.92, 0.07), 'M_Beach_Blue', rot=Matrix.Rotation(th, 3, 'Y'), col=(0, 0, 0.9, 0.5), smooth=True)
    return {'hulls': [[(-0.3, -0.34, 0.0), (0.95, -0.34, 0.0), (0.95, 0.34, 0.0), (-0.3, 0.34, 0.0), (-0.3, -0.34, 0.39), (0.95, -0.34, 0.39), (0.95, 0.34, 0.39), (-0.3, 0.34, 0.39)],
                      [(-0.3, -0.34, 0.25), (-0.74, -0.34, 0.85), (-0.74, 0.34, 0.85), (-0.3, 0.34, 0.25), (-0.34, -0.34, 0.1), (-0.34, 0.34, 0.1)]]}

def towel_ball(mb, rng, P):
    nx, ny = 26, 12; Lx, Wy = 1.8, 0.8
    ids = []
    for i in range(nx + 1):
        row = []
        for j in range(ny + 1):
            x = -Lx / 2 + Lx * i / nx; y = -Wy / 2 + Wy * j / ny
            z = 0.012 + 0.014 * fbm((x * 2.5, y * 2.5, 0), 5.0, 1.0, 3) + 0.01 * sstep(0.45, 0.5, abs(y / Wy) + 0.0) * 0
            edge = 1 - sstep(0.88, 1.0, abs(x) / (Lx / 2))
            row.append(mb.v((x, y, max(0.004, z * (0.6 + 0.4 * edge))), (0.0, 0.0, 0.85, 0.5)))
        ids.append(row)
    stripe = ['M_Beach_Red', 'M_Beach_White', 'M_Beach_Blue', 'M_Beach_White', 'M_Beach_Red']
    for i in range(nx):
        for j in range(ny):
            m = stripe[min(4, int(5 * (j + 0.5) / ny))]
            mb.f([ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j]][::-1], m, uvs=1.0)
    mb.grp = 1
    def mf(c):
        ang = math.atan2(c.y - 0.12, c.x - 1.3) % TAU
        k = int(ang / (TAU / 6))
        if c.z > 0.2 * 2 - 0.045 or c.z < 0.045: return 'M_Beach_White'
        return ('M_Beach_Red', 'M_Beach_White', 'M_Beach_Blue')[k % 3]
    radial_blob(mb, lambda d: 1.0, sub=2, scale=(0.2, 0.2, 0.2), offset=(1.3, 0.12, 0.2), mat='M_Beach_Red', matfn=mf, smooth=True, zfloor=0.0, uvs=2.0)
    mb.grp = 0
    return {}

def bucket_set(mb, rng, P):
    sd = 16
    zs = [0.0, 0.07, 0.14, 0.21]; ro = [0.085, 0.0975, 0.11, 0.12]
    mb.grp = 1
    out = tube(mb, [Vector((0.0, 0.0, z)) for z in zs], ro, sd, 'M_Beach_Blue', col=lambda t, k: (0, 0, 0.8 + 0.2 * t, 0.5), caps=(True, False), uvv=2.0)
    inn = tube(mb, [Vector((0.0, 0.0, z)) for z in zs[1:]], [r - 0.007 for r in ro[1:]], sd, 'M_Beach_Blue', col=lambda t, k: (0, 0, 0.5, 0.5), caps=(False, False), flip=True)
    ot, it = out['rings'][-1], inn['rings'][-1]
    for k in range(sd):
        k2 = (k + 1) % sd
        mb.f([ot[k], ot[k2], it[k2], it[k]], 'M_Beach_Blue', smooth=True)
    cen = mb.v((0, 0, 0.14), (0, 0, 0.6, 0.5)); rg = [mb.v(mb.V[i], (0, 0, 0.6, 0.5)) for i in inn['rings'][1]]
    for k in range(sd): mb.f([cen, rg[k], rg[(k + 1) % sd]], 'M_Sand', smooth=True, uvs=3.0)
    hp = [Vector((0.118 * math.cos(al), 0.0, 0.205 + 0.115 * math.sin(al))) for al in [math.pi * i / 8 for i in range(9)]][::-1]
    tube(mb, hp, [0.005] * 9, 4, 'M_Beach_Metal', col=lambda t, k: (0, 0, 0.9, 0.5), caps=(True, True))
    mb.grp = 2
    cx, cy = -0.30, 0.05
    radial_blob(mb, lambda d: 1.0, sub=2, scale=(0.30, 0.26, 0.08), offset=(cx, cy, 0.0), mat='M_Sand', smooth=True, zfloor=0.0, uvs=3.0)
    for (dx, dy, h) in ((-0.15, -0.12, 0.17), (0.15, -0.12, 0.13), (0.15, 0.12, 0.19), (-0.15, 0.12, 0.14)):
        tube(mb, [Vector((cx + dx, cy + dy, 0.02)), Vector((cx + dx, cy + dy, 0.02 + h * 0.5)), Vector((cx + dx, cy + dy, 0.02 + h))], [0.048, 0.044, 0.04], 10, 'M_Sand',
             col=lambda t, k: (0, 0, 0.7 + 0.3 * t, 0.5), caps=(True, True), cap_dz=(0.0, 0.075), uvv=3.0)
    for (px, py, ang) in ((0.0, -0.12, 0.0), (0.0, 0.12, 0.0), (-0.15, 0.0, 90.0), (0.15, 0.0, 90.0)):
        box(mb, Vector((cx + px, cy + py, 0.075)), (0.22 if ang == 0.0 else 0.16, 0.035, 0.08), 'M_Sand', rot=rot_euler(0, 0, ang), col=(0, 0, 0.8, 0.5))
    mb.grp = 0
    sp = [Vector((0.34, -0.10, 0.34)), Vector((0.30, -0.14, 0.18)), Vector((0.285, -0.16, 0.10))]
    tube(mb, sp, [0.013, 0.013, 0.013], 6, 'M_Beach_Red', col=lambda t, k: (0, 0, 0.9, 0.5), caps=(True, True))
    box(mb, Vector((0.28, -0.17, 0.06)), (0.10, 0.012, 0.13), 'M_Beach_Red', rot=rot_euler(0, 12, 35), col=(0, 0, 0.9, 0.5))
    return {}

# ------------------------------------------------------------------------------------------------ sign post
def sign_arrow(mb, rng, P):
    box(mb, Vector((0, 0, 0.95)), (0.12, 0.12, 2.1), 'M_Wood_Plank')
    ptop = [Vector((-0.06, -0.06, 2.0)), Vector((0.06, -0.06, 2.0)), Vector((0.06, 0.06, 2.0)), Vector((-0.06, 0.06, 2.0))]
    ids = [mb.v(p, (0, 0, 0.9, 0.5)) for p in ptop]; ap = mb.v((0, 0, 2.06), (0, 0, 1.0, 0.5))
    for k in range(4): mb.f([ids[k], ids[(k + 1) % 4], ap], 'M_Wood_Plank', smooth=False)
    poly = [(-0.46, -0.125), (0.33, -0.125), (0.54, 0.0), (0.33, 0.125), (-0.46, 0.125)]
    z0 = 1.68; xb, xf = 0.062, 0.094
    fr = [mb.v((xf, y, z0 + z), (0, 0, 0.95, 0.5)) for y, z in poly]
    bk = [mb.v((xb, y, z0 + z), (0, 0, 0.7, 0.5)) for y, z in poly]
    mb.f(fr, 'M_Sign_Paint', smooth=False, uv=[((y + 0.46), (z + 0.125)) for y, z in poly])
    mb.f(bk[::-1], 'M_Wood_Plank', smooth=False)
    for k in range(5):
        k2 = (k + 1) % 5
        mb.f([bk[k], bk[k2], fr[k2], fr[k]], 'M_Wood_Plank', smooth=False, uvs=2.0)
    gl = [(-0.34, -0.035), (0.20, -0.035), (0.20, -0.075), (0.42, 0.0), (0.20, 0.075), (0.20, 0.035), (-0.34, 0.035)]
    gi = [mb.v((xf + 0.003, y, z0 + z), (0, 0, 0.95, 0.5)) for y, z in gl]
    mb.f(gi, 'M_Wood_Plank', smooth=False, uv=[((y + 0.34), (z + 0.1)) for y, z in gl])
    for yy in (-0.38, 0.0):
        tube(mb, [Vector((xf + 0.003, yy, z0 + 0.09)), Vector((xf + 0.016, yy, z0 + 0.09))], [0.011, 0.011], 6, 'M_Metal_Galv', col=lambda t, k: (0, 0, 1.0, 0.5), caps=(True, True))
    return {'hulls': [[(-0.06, -0.06, -0.1), (0.06, -0.06, -0.1), (0.06, 0.06, -0.1), (-0.06, 0.06, -0.1), (-0.06, -0.06, 2.0), (0.06, -0.06, 2.0), (0.06, 0.06, 2.0), (-0.06, 0.06, 2.0)]]}

# ------------------------------------------------------------------------------------------------ registry
FARM = ['farmland', 'temperate', 'meadow']
reg('nat_crop_wheat_row', 'misc', fn=wheat_row, seed=5101, name='Wheat crop row segment 4 m', biome=FARM, scale=(0.9, 1.2), w=5.0, wind=True, budget=(2000, 9000), sink=None,
    origin='start of the row on its centreline at ground level; row runs 4.0 m along +X (tileable end to end)',
    P=dict(W=0.7, n=150))
reg('nat_hay_round', 'misc', fn=round_bale, seed=5201, name='Round hay bale', biome=FARM, scale=(0.8, 1.3), w=2.2, coll='custom', closed=True, budget=(800, 5000), sink=None,
    coll_note='UCX_01 12-sided cylinder hull. UE: Simple As Complex', P=dict(R=0.85, Wd=1.2, seed=5))
reg('nat_hay_stack', 'misc', fn=bale_stack, seed=5202, name='Stacked square hay bales (pyramid 3-2-1, two deep)', biome=FARM, scale=(0.8, 1.3), w=3.2, coll='all', ndir=24, budget=(2000, 9000), sink=None,
    coll_note='UCX_01 single hull around the stack', P={})
reg('nat_logpile', 'misc', fn=log_pile, seed=5301, name='Log pile (14 logs)', biome=['forest', 'temperate', 'farmland', 'highland'], scale=(0.8, 1.3), w=2.6, coll='all', ndir=24, budget=(500, 5000), sink=None,
    coll_note='UCX_01 single hull around the pile', P={})
reg('nat_log_fallen', 'misc', fn=fallen_log, seed=5302, name='Fallen log with broken end', biome=['forest', 'temperate', 'highland', 'wetland'], scale=(0.7, 1.4), w=5.2, coll='slabs', ndir=20, budget=(500, 5000), sink=None,
    coll_note='UCX_01..03 three hulls along the trunk (stubs ignored)', P={})
reg('nat_stump', 'misc', fn=stump, seed=5303, name='Tree stump with growth rings', biome=['forest', 'temperate', 'highland', 'farmland'], scale=(0.7, 1.5), w=1.4, coll='all', ndir=24, budget=(300, 4000), sink=None,
    coll_note='UCX_01 single hull', P={})
reg('nat_beach_umbrella', 'misc', fn=beach_umbrella, seed=5401, name='Beach umbrella (striped, tilted)', biome=['coast', 'beach'], scale=(0.9, 1.2), w=2.8, coll='custom', budget=(300, 3000), sink=None,
    coll_note='UCX_01 pole only (canopy has no collision)', P={})
reg('nat_beach_lounger', 'misc', fn=lounger, seed=5402, name='Wooden sun lounger', biome=['coast', 'beach'], scale=(0.9, 1.2), w=2.4, coll='custom', budget=(200, 3000), sink=None,
    coll_note='UCX_01 seat, UCX_02 backrest', P={})
reg('nat_beach_bucket', 'misc', fn=bucket_set, seed=5404, name='Beach bucket, spade and sandcastle', biome=['coast', 'beach'], scale=(0.9, 1.3), w=1.6, coll='groups', budget=(300, 4000), sink=None,
    coll_note='UCX_01 bucket, UCX_02 sandcastle', P={})
reg('nat_beach_towel_ball', 'misc', fn=towel_ball, seed=5403, name='Beach towel and ball', biome=['coast', 'beach'], scale=(0.9, 1.2), w=2.6, coll='groups', budget=(200, 3000), sink=None,
    coll_note='UCX_01 ball only (towel is walkable decoration)', P={})
reg('nat_sign_arrow', 'misc', fn=sign_arrow, seed=5601, name='Wooden arrow sign post 2 m', biome=['temperate', 'farmland', 'forest', 'highland', 'coast'], scale=(0.8, 1.3), w=1.6, coll='custom', closed=False, budget=(40, 2000), sink=None,
    origin='post base centre at ground (post foot buried 0.1 m); sign face and arrow board toward +X, arrow points +Y',
    coll_note='UCX_01 post box (board has no collision)', P={})
