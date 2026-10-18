"""gc_rocks.py - rocks (granite / jagged / mesa / coast) and cliff formations. exec'd by ground_cover.py"""
import bisect

def fit_range(mb, v0, v1, size, pos=(0.0, 0.0), zbase=0.0, yaw=0.0, shear=0.0):
    A = np.array(mb.V[v0:v1], dtype=np.float64); mn = A.min(0); mx = A.max(0); cx = (mn + mx) / 2
    sc = np.array([size[0] / max(1e-6, mx[0] - mn[0]), size[1] / max(1e-6, mx[1] - mn[1]), size[2] / max(1e-6, mx[2] - mn[2])])
    A2 = (A - np.array([cx[0], cx[1], mn[2]])) * sc
    if shear: A2[:, 0] += A2[:, 2] / size[2] * shear
    if yaw:
        c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        x = A2[:, 0] * c - A2[:, 1] * s; y = A2[:, 0] * s + A2[:, 1] * c; A2[:, 0] = x; A2[:, 1] = y
    A2 += np.array([pos[0], pos[1], zbase])
    mb.V[v0:v1] = [tuple(r) for r in A2.tolist()]

def _super_r(d, p, amp, seed, f=1.3, band=0.0):
    ax, ay, az = abs(d.x) + 1e-6, abs(d.y) + 1e-6, abs(d.z) + 1e-6
    r = (ax ** p + ay ** p + az ** p) ** (-1.0 / p)
    n = fbm(d, seed, f, 3) * amp + nz(d, seed + 3.1, 5.0) * amp * 0.3
    if band: n += band * math.sin(d.z * 9.0 + seed)
    return r * (1.0 + n)

# ------------------------------------------------------------------------------------------------ granite / coast (rounded)
def rounded_rocks(mb, rng, P):
    mat = P.get('mat', 'M_Rock')
    for bi, b in enumerate(P['blobs']):
        mb.grp = bi + 1
        seed = b.get('seed', P['seed'] + bi * 7)
        rr = random.Random(seed * 3 + 1)
        planes = []
        for (x, y, z) in fib_dirs(b.get('np', 11)):
            n = Vector((x + rr.uniform(-.3, .3), y + rr.uniform(-.3, .3), z + rr.uniform(-.3, .3))).normalized()
            planes.append((n, rr.uniform(0.78, 1.0)))
        sp = b.get('sp', 8.0)
        cr = [(rand_unit(rng), rng.uniform(-0.3, 0.3), rng.uniform(0.03, 0.07), rng.uniform(0.06, 0.13)) for _ in range(b.get('cracks', 2))]
        amp = b['amp']; band = b.get('band', 0.0)
        def rf(d, planes=planes, sp=sp, cr=cr, seed=seed, amp=amp, band=band):
            s_ = 0.0
            for (n, off) in planes:
                dd = d.dot(n)
                if dd > 0: s_ += (dd / off) ** sp
            r = s_ ** (-1.0 / sp) if s_ > 0 else 3.0
            r *= 1.0 + amp * fbm(d, seed, 1.6, 3) + amp * 0.35 * nz(d, seed + 3.1, 6.0) + band * math.sin(d.z * 9.0 + seed)
            for (n, c, w, dep) in cr:
                t = (d.dot(n) - c) / w; r *= 1.0 - dep * math.exp(-t * t)
            return r
        v0 = len(mb.V)
        radial_blob(mb, rf, sub=b.get('sub', 3), rot=rot_euler(*b.get('rot', (0, 0, 0))), mat=mat, smooth=True, zfloor=b.get('zfloor', -0.62), uvs=0.45)
        fit_range(mb, v0, len(mb.V), b['size'], pos=b['pos'], zbase=b.get('zbase', 0.0), yaw=b.get('yaw', 0.0))
    mb.grp = 0
    return {}

# ------------------------------------------------------------------------------------------------ jagged mountain rocks
def jagged_rocks(mb, rng, P):
    mat = P.get('mat', 'M_Rock_Slate')
    for bi, b in enumerate(P['blobs']):
        mb.grp = bi + 1
        rr = random.Random(b['seed'])
        N = b.get('np', 15)
        planes = []
        for (x, y, z) in fib_dirs(N):
            n = Vector((x + rr.uniform(-.32, .32), y + rr.uniform(-.32, .32), z + rr.uniform(-.32, .32))).normalized()
            off = rr.uniform(*b.get('off', (0.62, 0.95)))
            if n.z > 0.3: off *= b.get('topk', 0.88)
            planes.append((n, off))
        seed = b['seed']
        def rf(d, planes=planes, seed=seed):
            r = 3.0
            for (n, off) in planes:
                dd = d.dot(n)
                if dd > 1e-3:
                    rr_ = off / dd
                    if rr_ < r: r = rr_
            return r * (1.0 + 0.035 * ridged(d, seed, 4.0, 3) - 0.03)
        v0 = len(mb.V)
        radial_blob(mb, rf, sub=b.get('sub', 4), mat=mat, smooth=False, zfloor=b.get('zfloor', -0.75), uvs=0.4,
                    spin=rot_euler(*b.get('spin', (0, 0, 0))))
        fit_range(mb, v0, len(mb.V), b['size'], pos=b['pos'], yaw=b.get('yaw', 0.0), shear=b.get('shear', 0.0))
    mb.grp = 0
    return {}

# ------------------------------------------------------------------------------------------------ sandstone strata columns
def strata_column(mb, rng, seed, H, Rx, Ry, cx=0.0, cy=0.0, layer=0.4, flare=0.25, taper=0.10, pw=3.2, cap=1.06, lean=0.0, nang=36, matA='M_Rock_Sandstone', matB='M_Rock_SandstoneDark', soft_in=(0.08, 0.16), yaw=0.0):
    ph = [rng.uniform(0, TAU) for _ in range(4)]
    def rpoly(th):
        c, s = abs(math.cos(th)) + 1e-6, abs(math.sin(th)) + 1e-6
        r = (c ** pw + s ** pw) ** (-1.0 / pw)
        h = 1 + 0.10 * math.cos(2 * th + ph[0]) + 0.08 * math.cos(3 * th + ph[1]) + 0.05 * math.cos(5 * th + ph[2])
        return r * h / 1.18
    zs = [0.0]; hard = []
    while zs[-1] < H - 0.12:
        zs.append(min(H, zs[-1] + layer * rng.uniform(0.5, 1.5))); hard.append(not hard[-1] if (hard and rng.random() < 0.75) else rng.random() < 0.5)
    zs[-1] = H
    nl = len(hard)
    fac = []
    for k in range(nl):
        zm = (zs[k] + zs[k + 1]) / 2 / H
        f = (1.0 - (0 if hard[k] else rng.uniform(*soft_in))) * (1 + flare * (1 - zm) ** 1.6) * (1 - taper * zm)
        if k >= nl - 2: f *= cap
        fac.append(f)
    nfl = rng.choice((5, 7, 9)); ca, sa = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    def ringv(z, f, soft):
        ids = []
        for i in range(nang):
            th = TAU * i / nang
            px, py = Rx * rpoly(th) * math.cos(th), Ry * rpoly(th) * math.sin(th)
            e = 0.045 * fbm((px, py, z), seed, 0.8, 3) * (1.7 if soft else 0.8) + 0.02 * nz((px, py, z), seed + 1, 3.0)
            rad = f * (1 + e) * (1 + (0.05 if soft else 0.025) * (abs(math.sin(th * nfl + ph[3])) ** 0.7 - 0.6))
            x, y = px * rad + lean * z / H, py * rad
            X, Y = cx + x * ca - y * sa, cy + x * sa + y * ca
            ao = (0.45 + 0.55 * (z / H) ** 0.5) * (0.85 if soft else 1.0)
            ids.append(mb.v((X, Y, z), (0.0, 0.0, ao, 0.5)))
        return ids
    chain = []   # (ring ids, layer idx, rad factor)
    for k in range(nl):
        for j in range(3):
            z = zs[k] + (zs[k + 1] - zs[k]) * j / 2
            chain.append((ringv(z, fac[k] * (1 - 0.025 * j / 2), not hard[k]), k, fac[k]))
    def strip(r0, r1, mat):
        for i in range(nang):
            i2 = (i + 1) % nang
            mb.f([r0[i], r0[i2], r1[i2], r1[i]], mat, smooth=False, uvs=0.4)
    for a in range(len(chain) - 1):
        r0, k0, f0 = chain[a]; r1, k1, f1 = chain[a + 1]
        if k0 == k1: strip(r0, r1, matA if hard[k0] else matB)
        else:
            up = f1 < f0
            k = k0 if up else k1
            strip(r0, r1, matA if hard[k] else matB)
    top = chain[-1][0]
    r2 = []
    for i in range(nang):
        p = Vector(mb.V[top[i]]); c = Vector((cx + lean, cy, H))
        q = c + (p - c) * 0.6; q.z = H + 0.06 * fbm((q.x, q.y, 0), seed, 1.2, 2) + 0.04
        r2.append(mb.v(q, (0, 0, 1.0, 0.5)))
    strip(top, r2, matA)
    cen = mb.v((cx + lean, cy, H + 0.12 + 0.06 * nz((cx, cy, 0), seed, 1.0)), (0, 0, 1.0, 0.5))
    for i in range(nang):
        i2 = (i + 1) % nang
        mb.f([cen, r2[i], r2[i2]], matA, smooth=False, uvs=0.4)
    bot = chain[0][0]
    cb = mb.v((cx, cy, zs[0]), (0, 0, 0.4, 0.5))
    for i in range(nang):
        i2 = (i + 1) % nang
        mb.f([cb, bot[i2], bot[i]], matB, smooth=False, uvs=0.4)

def mesa_rocks(mb, rng, P):
    for gi, c in enumerate(P['cols']):
        mb.grp = gi + 1
        strata_column(mb, rng, P['seed'] + gi * 5, **c)
    mb.grp = 0
    return {}

# ------------------------------------------------------------------------------------------------ cliff formations
def cliff(mb, rng, P):
    L, H, D, seed = P['L'], P['H'], P['D'], P['seed']
    nu, nv = P.get('nu', 48), P.get('nv', 30)
    mA, mB = P['mats']
    nl = P.get('nlayers', 10)
    tilt = P.get('tilt', 0.0)
    ledge = P.get('ledge', 0.30)
    bnds = sorted(rng.uniform(0.05, 0.97) for _ in range(nl - 1))
    bnds = [0.0] + bnds + [1.01]
    hard = [rng.random() < 0.5 for _ in range(nl)]
    offs = [(ledge if hard[k] else -ledge * 0.5) * rng.uniform(0.7, 1.2) for k in range(nl)]
    def lay(zf):
        return min(nl - 1, max(0, bisect.bisect_right(bnds, zf) - 1))
    def strata(zf):
        k = lay(zf); w = 0.012
        o = offs[k]
        if k + 1 < nl: o += (offs[k + 1] - offs[k]) * sstep(bnds[k + 1] - w, bnds[k + 1] + w, zf)
        return o
    def endf(u): return sstep(0.0, P.get('endr', 0.2), u) * sstep(1.0, 1.0 - P.get('endr', 0.2), u)
    spires = [(rng.uniform(0.2, 0.8), rng.uniform(0.03, 0.07), rng.uniform(0.1, 0.22) * H) for _ in range(P.get('spires', 2))]
    def Ht(u):
        x = (u - 0.5) * L
        h = H * (0.14 + 0.86 * endf(u) ** 0.5) * (1 + 0.10 * fbm((x, 0, 0), seed, 0.5, 3))
        for (u0, w, hh) in spires: h += hh * math.exp(-((u - u0) / w) ** 2) * endf(u)
        return h
    def df(u, v, x, z):
        E = endf(u) ** 0.8
        zf = z / H + tilt * (u - 0.5)
        prof = 1.0 - 0.30 * (v ** 1.3)
        d = D * 0.5 * prof + strata(zf) * (0.7 + 0.3 * v) + 0.6 * fbm((x * 0.7, 0.0, z * 0.2), seed, 1.0, 2) + 0.10 * fbm((x * 1.4, 0.0, z * 0.9), seed + 2, 1.0, 1)
        return max(0.05, d) * E
    def db(u, v, x, z):
        E = endf(u) ** 0.8
        d = D * 0.5 * (1 - 0.5 * v) + 0.45 * fbm((x * 0.5, 5.0, z * 0.4), seed + 4, 1.0, 2) + 0.4 * strata(z / H) * 0.4
        return max(0.05, d) * E
    # front sheet
    F = [[None] * (nv + 1) for _ in range(nu + 1)]
    Bk = [[None] * (nv + 1) for _ in range(nu + 1)]
    tops = [Ht(i / nu) for i in range(nu + 1)]
    for i in range(nu + 1):
        u = i / nu; x = (u - 0.5) * L
        for j in range(nv + 1):
            v = j / nv; z = v * tops[i]
            d = df(u, v, x, z)
            ao = 0.45 + 0.55 * (v ** 0.55) - 0.2 * clamp(0.5 * fbm((x * 0.7, 0.0, z * 0.2), seed, 1.0, 2))
            F[i][j] = mb.v((x, -d, z), (0.0, 0.0, clamp(ao, 0.2, 1.0), 0.5))
    for i in range(nu + 1):
        u = i / nu; x = (u - 0.5) * L
        for j in range(nv + 1):
            if i == 0 or i == nu: Bk[i][j] = F[i][j]; continue
            v = j / nv; z = v * tops[i]
            Bk[i][j] = mb.v((x, db(u, v, x, z), z), (0.0, 0.0, clamp(0.4 + 0.5 * v), 0.5))
    for i in range(nu):
        for j in range(nv):
            zf = ((j + 0.5) / nv) * tops[i] / H + tilt * ((i + 0.5) / nu - 0.5)
            m = mA if hard[lay(zf)] else mB
            mb.f([F[i][j], F[i + 1][j], F[i + 1][j + 1], F[i][j + 1]], m, smooth=True, uvs=0.3)
            mb.f([Bk[i][j], Bk[i][j + 1], Bk[i + 1][j + 1], Bk[i + 1][j]], mB if m == mA else mA, smooth=True, uvs=0.3)
    # top cap (3 strips with relief) and bottom
    rowsT = [[F[i][nv] for i in range(nu + 1)]]
    for s in (1, 2):
        t = s / 3.0; row = []
        for i in range(nu + 1):
            if i == 0 or i == nu: row.append(F[i][nv]); continue
            u = i / nu; x = (u - 0.5) * L
            a = Vector(mb.V[F[i][nv]]); b = Vector(mb.V[Bk[i][nv]])
            p = a.lerp(b, t); p.z += 0.08 * H * math.sin(math.pi * t) * (0.5 + 0.5 * endf(u)) + 0.35 * fbm((x, p.y, 0), seed + 7, 0.7, 3)
            row.append(mb.v(p, (0.0, 0.0, 1.0, 0.5)))
        rowsT.append(row)
    rowsT.append([Bk[i][nv] for i in range(nu + 1)])
    for s in range(3):
        for i in range(nu):
            mb.f([rowsT[s][i], rowsT[s][i + 1], rowsT[s + 1][i + 1], rowsT[s + 1][i]], mA, smooth=False, uvs=0.3)
    for i in range(nu):
        mb.f([F[i][0], Bk[i][0], Bk[i + 1][0], F[i + 1][0]], mB, smooth=False, uvs=0.3)
    # sea stack / extra columns share the cliff material, scree boulders on top of it
    mb.grp = 1
    for ci, c in enumerate(P.get('stacks', [])):
        mb.grp = 1 + ci
        strata_column(mb, rng, seed + 20 + ci, matA=mA, matB=mB, **c)
    g0 = 1 + len(P.get('stacks', []))
    for si in range(P.get('scree', 7)):
        mb.grp = g0 + si
        side = -1 if rng.random() < 0.6 else 1
        sx = rng.uniform(-0.45, 0.45) * L; sy = side * (D * 0.5 + rng.uniform(0.2, 1.6)) * (1.0 if side < 0 else 0.7)
        sz = rng.uniform(0.45, 1.25)
        sd = rng.uniform(0, 99)
        def rf(d, sd=sd): return _super_r(d, 2.6, 0.18, sd)
        v0 = len(mb.V)
        radial_blob(mb, rf, sub=2, mat=(mA if rng.random() < 0.5 else mB), smooth=False, zfloor=-0.6, uvs=0.4)
        fit_range(mb, v0, len(mb.V), (sz * rng.uniform(1.0, 1.5), sz * rng.uniform(0.9, 1.3), sz * rng.uniform(0.6, 0.95)), pos=(sx, sy), zbase=-0.05, yaw=rng.uniform(0, 180))
    mb.grp = 0
    return {'slabs': P.get('slabs', 4), 'hull_groups': list(range(1, 1 + len(P.get('stacks', []))))}

# ------------------------------------------------------------------------------------------------ registry
G_COL = dict(biome=['temperate', 'forest', 'highland', 'farmland', 'meadow'], scale=(0.7, 1.5))
reg('nat_rock_granite_a', 'rocks', fn=rounded_rocks, seed=1101, name='Granite boulder - single rounded', biome=['temperate', 'forest', 'highland', 'meadow'], scale=(0.7, 1.6), w=4, coll='groups', closed=True, sink=0.04, budget=(800, 9000),
    P=dict(seed=11, blobs=[dict(size=(2.3, 2.0, 1.7), pos=(0, 0), amp=0.07, np=12, sp=9, rot=(0, 0, 20), yaw=15)]))
reg('nat_rock_granite_b', 'rocks', fn=rounded_rocks, seed=1102, name='Granite boulder - cluster of three', biome=['temperate', 'forest', 'highland', 'meadow'], scale=(0.7, 1.4), w=5, coll='groups', closed=True, sink=0.04, budget=(800, 9000),
    P=dict(seed=21, blobs=[dict(size=(2.6, 2.2, 2.2), pos=(0, 0), amp=0.07, np=11, sp=9, rot=(0, 5, 40), yaw=20),
                           dict(size=(1.5, 1.3, 1.1), pos=(1.9, 1.0), amp=0.08, np=10, sp=8, rot=(0, 0, 70), sub=3, yaw=-30),
                           dict(size=(1.0, 0.9, 0.8), pos=(-1.6, -1.2), amp=0.09, np=9, sp=7, rot=(0, 0, 10), sub=2)]))
reg('nat_rock_granite_c', 'rocks', fn=rounded_rocks, seed=1103, name='Granite slab - flat topped', biome=['temperate', 'highland', 'meadow', 'coast'], scale=(0.7, 1.5), w=5, coll='groups', closed=True, sink=0.04, budget=(800, 9000),
    P=dict(seed=31, blobs=[dict(size=(3.0, 2.2, 1.1), pos=(0, 0), amp=0.06, np=12, sp=11, rot=(0, 0, -15), yaw=-10),
                           dict(size=(0.9, 0.8, 0.55), pos=(1.9, -1.3), amp=0.08, np=9, sp=7, rot=(0, 0, 0), sub=2)]))

reg('nat_rock_jagged_a', 'rocks', fn=jagged_rocks, seed=1201, name='Mountain rock - tall spire', biome=['alpine', 'highland', 'mountain'], scale=(0.7, 1.5), w=5, coll='groups', closed=True, sink=0.05, budget=(1500, 10000),
    P=dict(blobs=[dict(seed=71, size=(2.4, 1.9, 3.8), pos=(0, 0), np=15, shear=0.4, yaw=10)]))
reg('nat_rock_jagged_b', 'rocks', fn=jagged_rocks, seed=1202, name='Mountain rock - broad outcrop with satellites', biome=['alpine', 'highland', 'mountain'], scale=(0.7, 1.4), w=7, coll='groups', closed=True, sink=0.05, budget=(1500, 10000),
    P=dict(blobs=[dict(seed=72, size=(4.0, 3.0, 2.6), pos=(0, 0), np=17, yaw=30),
                  dict(seed=73, size=(1.8, 1.5, 1.7), pos=(2.8, 1.3), np=13, sub=3, yaw=-20),
                  dict(seed=74, size=(1.3, 1.2, 1.5), pos=(-2.4, -1.7), np=12, sub=3, yaw=50)]))
reg('nat_rock_jagged_c', 'rocks', fn=jagged_rocks, seed=1203, name='Mountain rock - leaning wedge', biome=['alpine', 'highland', 'mountain'], scale=(0.7, 1.5), w=5, coll='groups', closed=True, sink=0.05, budget=(1500, 10000),
    P=dict(blobs=[dict(seed=75, size=(3.2, 1.6, 2.4), pos=(0, 0), np=14, shear=-1.0, yaw=-25, off=(0.55, 0.9)),
                  dict(seed=76, size=(1.0, 0.9, 1.1), pos=(1.8, 1.5), np=11, sub=3)]))

reg('nat_rock_mesa_a', 'rocks', fn=mesa_rocks, seed=1301, name='Sandstone mesa chunk - blocky', biome=['desert', 'canyon', 'badlands'], scale=(0.8, 1.5), w=7, coll='groups', closed=True, sink=0.0, budget=(1500, 10000),
    P=dict(seed=301, cols=[dict(H=3.6, Rx=2.5, Ry=2.0, layer=0.38, flare=0.25, taper=0.10, pw=3.4)]))
reg('nat_rock_mesa_b', 'rocks', fn=mesa_rocks, seed=1302, name='Sandstone butte - caprock spire', biome=['desert', 'canyon', 'badlands'], scale=(0.8, 1.4), w=5, coll='groups', closed=True, sink=0.0, budget=(1500, 10000),
    P=dict(seed=302, cols=[dict(H=6.0, Rx=1.7, Ry=1.5, layer=0.42, flare=0.12, taper=0.14, pw=2.6, cap=1.14, nang=32, lean=0.3)]))
reg('nat_rock_mesa_c', 'rocks', fn=mesa_rocks, seed=1303, name='Sandstone terrace cluster - stepped', biome=['desert', 'canyon', 'badlands'], scale=(0.8, 1.4), w=9, coll='groups', closed=True, sink=0.0, budget=(1500, 10000),
    P=dict(seed=303, cols=[dict(H=2.4, Rx=3.0, Ry=2.3, layer=0.32, flare=0.55, taper=0.05, pw=3.0, cap=1.02),
                           dict(H=3.4, Rx=1.3, Ry=1.2, cx=2.3, cy=-1.6, layer=0.34, flare=0.2, taper=0.12, pw=2.8, nang=28),
                           dict(H=1.5, Rx=1.0, Ry=0.9, cx=-2.4, cy=1.7, layer=0.3, flare=0.3, taper=0.05, pw=3.0, nang=24)]))

reg('nat_rock_coast_a', 'rocks', fn=rounded_rocks, seed=1401, name='Coast rocks - pebble trio', biome=['coast', 'beach', 'riverside'], scale=(0.7, 1.6), w=3, coll='groups', closed=True, sink=0.03, budget=(300, 6000),
    P=dict(seed=41, mat='M_Rock_Beach', blobs=[dict(size=(1.4, 1.1, 0.8), pos=(0, 0), amp=0.06, np=9, sp=5, rot=(0, 0, 30), band=0.025, cracks=1, yaw=20),
                                                dict(size=(0.8, 0.65, 0.5), pos=(0.95, 0.7), amp=0.06, np=9, sp=5, sub=2, cracks=0),
                                                dict(size=(0.55, 0.5, 0.38), pos=(-0.9, 0.5), amp=0.06, np=9, sp=5, sub=2, cracks=0)]))
reg('nat_rock_coast_b', 'rocks', fn=rounded_rocks, seed=1402, name='Coast rocks - tilted slab with stones', biome=['coast', 'beach', 'riverside'], scale=(0.7, 1.6), w=3.5, coll='groups', closed=True, sink=0.03, budget=(300, 6000),
    P=dict(seed=42, mat='M_Rock_Beach', blobs=[dict(size=(1.6, 1.0, 0.55), pos=(0, 0), amp=0.05, np=10, sp=9, rot=(0, 12, 10), band=0.03, cracks=1, yaw=-15),
                                                dict(size=(0.6, 0.55, 0.45), pos=(1.0, -0.5), amp=0.06, np=9, sp=5, sub=2, cracks=0),
                                                dict(size=(0.45, 0.4, 0.3), pos=(-0.6, 0.85), amp=0.06, np=9, sp=5, sub=2, cracks=0)]))
reg('nat_rock_coast_c', 'rocks', fn=rounded_rocks, seed=1403, name='Coast rocks - tidal fragments', biome=['coast', 'beach', 'riverside'], scale=(0.7, 1.6), w=4, coll='groups', closed=True, sink=0.03, budget=(300, 6000),
    P=dict(seed=43, mat='M_Rock_Beach', blobs=[dict(size=(0.9, 0.8, 0.7), pos=(0, 0), amp=0.06, np=9, sp=5, sub=3, band=0.02, cracks=1),
                                                dict(size=(0.7, 0.9, 0.5), pos=(0.9, 0.5), amp=0.06, np=9, sp=5, sub=2, cracks=0, yaw=40),
                                                dict(size=(0.55, 0.5, 0.4), pos=(-0.2, 1.0), amp=0.06, np=9, sp=5, sub=2, cracks=0),
                                                dict(size=(0.5, 0.45, 0.35), pos=(0.6, -0.8), amp=0.06, np=9, sp=5, sub=2, cracks=0),
                                                dict(size=(0.4, 0.4, 0.3), pos=(-0.9, -0.5), amp=0.06, np=9, sp=5, sub=2, cracks=0)]))

reg('nat_cliff_canyon_a', 'cliffs', fn=cliff, seed=1501, name='Canyon cliff wall - layered sandstone', biome=['desert', 'canyon', 'badlands'], scale=(0.8, 1.3), w=16, coll='slabs', closed=True, sink=None, budget=(3000, 14000), ndir=24,
    origin='centre of the wall footprint on the ground (z=0); wall runs along X, front (cliff face) toward -Y, back toward +Y',
    P=dict(seed=501, L=14.0, H=10.0, D=5.0, mats=('M_Rock_Sandstone', 'M_Rock_SandstoneDark'), nlayers=11, spires=2, ledge=0.32, scree=7, slabs=4))
reg('nat_cliff_coast_b', 'cliffs', fn=cliff, seed=1502, name='Coastal cliff - tilted strata with sea stack', biome=['coast', 'beach', 'highland'], scale=(0.8, 1.3), w=17, coll='slabs', closed=True, sink=None, budget=(3000, 14000), ndir=24,
    origin='centre of the wall footprint on the ground (z=0); wall runs along X, front (sea face) toward -Y, back toward +Y',
    P=dict(seed=502, L=11.0, H=8.0, D=4.2, mats=('M_Rock_Beach', 'M_Rock'), nlayers=8, spires=1, ledge=0.22, tilt=0.22, endr=0.26, scree=6, slabs=4,
           stacks=[dict(H=5.2, Rx=1.3, Ry=1.1, cx=-5.2, cy=-3.6, layer=0.5, flare=0.2, taper=0.12, pw=2.4, nang=28)]))
