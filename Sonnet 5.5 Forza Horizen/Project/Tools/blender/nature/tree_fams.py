"""
tree_fams.py - family builders for the tree kit: conifer, crown-tree engine (oak/birch/poplar/olive/scrub/dead) and palms.
Exec'd (into the same namespace) by trees.py after treelib.py.  Each builder(mb, rng, P) -> dict(hulls=[[(centre, radius)...]...], ...)
"""

# --------------------------------------------------------------------------------------------- helpers
def ring_at_z(br, z, rmul=1.0, rmin=0.05):
    for i in range(br.n - 1):
        z0 = br.pts[i].z; z1 = br.pts[i + 1].z
        if (z0 <= z <= z1) or (z1 <= z <= z0):
            t = (z - z0) / (z1 - z0) if z1 != z0 else 0.0
            pos = lerp(br.pts[i], br.pts[i + 1], t); r = lerp(br.radii[i], br.radii[i + 1], t)
            return (Vector((pos.x, pos.y, z)), max(r * rmul, rmin))
    p = br.pts[-1]
    return (Vector((p.x, p.y, z)), max(br.radii[-1] * rmul, rmin))

def root_flare(amp, hz, lobes, phase):
    def f(th, z):
        zz = max(z, 0.0)
        lb = 0.5 + 0.5 * math.cos(lobes * th + phase)
        return 1.0 + amp * math.exp(-zz / hz) * (0.25 + 0.75 * lb ** 1.6) + (amp * 0.25 if z < 0 else 0.0)
    return f

def add_roots(mb, rng, mat, base_r, n, reach, c=Vector((0, 0, 0)), seed=0.0, az0=None, fat=1.0):
    """surface roots / buttresses: tapered tubes that dive into the ground. With az0 given they grow out of the
       maxima of root_flare() (lobes) so they blend into the flared trunk instead of looking like sausages stuck on."""
    aligned = az0 is not None
    a0 = az0 if aligned else rng.uniform(0, 6.283)
    for i in range(n):
        az = a0 + 6.283 * (i + (rng.uniform(-0.05, 0.05) if aligned else rng.uniform(-0.25, 0.25))) / n
        d = Vector((math.cos(az), math.sin(az), 0))
        L = reach * rng.uniform(0.75, 1.2)
        rt = base_r * rng.uniform(0.34, 0.46) * fat
        pts = []
        N = 9
        for k in range(N + 1):
            t = k / N
            dist = base_r * (0.2 if aligned else 0.5) + L * t
            side = math.sin(t * 5 + i * 2.1) * 0.10 * L * t
            sdv = Vector((-d.y, d.x, 0)) * side
            z = max(rt * (2.2 if aligned else 1.5) * (1 - t) ** 2 - rt * 1.7 * t ** 2 + 0.02, -0.22 + 0.2 * (1 - t))
            pts.append(c + d * dist + sdv + Vector((0, 0, z)))
        radii = [max(rt * ((1.35 if aligned else 1.0) - (1.05 if aligned else 0.7) * (k / N) ** 1.1), 0.02) for k in range(N + 1)]
        tube(mb, pts, radii, 8, mat, f0=0.0, f1=0.0, amp=0.1, ridged=True, kf=3.0, kz=1.0, seed=seed + i, cap0=False, cap1='apex')

def trunk_path(H, seed, sway, lean=(0.0, 0.0), n=24, z0=-0.25, sfreq=1.7, spiral=None):
    ox, oy, oz = seed_off(seed)
    pts = []
    for i in range(n + 1):
        s = i / n
        z = z0 + (H - z0) * s
        k = s ** 1.3
        x = lean[0] * s * s + sway * k * mn.noise(Vector((s * sfreq + ox, oy, 0.5)))
        y = lean[1] * s * s + sway * k * mn.noise(Vector((oy, s * sfreq + ox, 7.5)))
        if spiral:
            sa, st_ = spiral
            x += sa * (s ** 0.8) * math.sin(6.283 * st_ * s)
            y += sa * (s ** 0.8) * (1.0 - math.cos(6.283 * st_ * s))
        pts.append(Vector((x, y, z)))
    return pts

def thin_path(pts, dz_lo, dz_hi, z_lo, z_hi):
    """keep dense sampling near the ground (fine rings for bark detail / colour tongues), coarser higher up"""
    out = [pts[0]]
    for p in pts[1:-1]:
        dz = lerp(dz_lo, dz_hi, smoothstep(z_lo, z_hi, p.z))
        if p.z - out[-1].z >= dz:
            out.append(p)
    out.append(pts[-1])
    return out

def lenticel_marks(mb, br, rng, mat_i, dens=60.0, w=(0.06, 0.20), h=(0.010, 0.022), z_lo=0.0, z_hi=99.0, offset=0.005, K=7, rmin=0.0):
    """birch lenticels: thin lens-shaped horizontal dark strips lying on the real trunk surface (bilinear on the ring faces).
       dens = marks per m2 of surface. Real geometry (12 tris each) instead of quantised face colouring."""
    ring = br.ring; sides = len(ring[0]); V = mb.V
    for i in range(br.n - 1):
        za = br.pts[i].z; zb = br.pts[i + 1].z
        if zb < z_lo or za > z_hi: continue
        T = br.T[i]
        rowh = (br.pts[i + 1] - br.pts[i]).length
        if rowh < 0.02: continue
        rad = 0.5 * (br.radii[i] + br.radii[i + 1])
        if rad < rmin: continue
        circ = 6.283 * rad
        cnt = int(dens * rowh * circ + rng.random())
        for _ in range(cnt):
            c0 = rng.uniform(0, sides)
            wm = rng.uniform(*w) * (0.6 + 0.4 * clamp(rad / 0.15))
            hh_m = min(rng.uniform(*h), 0.5 * rowh)
            ncols = wm / (circ / sides)
            t0 = rng.uniform(0.28, 0.72) if rowh > 0.035 else 0.5
            tilt = rng.uniform(-0.18, 0.18)
            hh = 0.5 * hh_m / rowh
            bot = []; top = []
            for k in range(K):
                u = -1.0 + 2.0 * k / (K - 1)
                c = (c0 + u * ncols * 0.5) % sides
                j = int(c) % sides; fj = c - int(c); j2 = (j + 1) % sides
                hu = hh * max(0.0, 1.0 - u * u) ** 0.7
                tc = t0 + tilt * u
                pair = []
                for tt in ((tc - hu, tc + hu) if 0 < k < K - 1 else (tc,)):
                    tt = clamp(tt, 0.02, 0.98)
                    pa = lerp(Vector(V[ring[i][j]]), Vector(V[ring[i][j2]]), fj)
                    pb = lerp(Vector(V[ring[i + 1][j]]), Vector(V[ring[i + 1][j2]]), fj)
                    p = lerp(pa, pb, tt)
                    cen = lerp(br.pts[i], br.pts[i + 1], tt)
                    out = p - cen
                    out = out - T * out.dot(T)
                    if out.length < 1e-6: out = Vector((1, 0, 0))
                    out.normalize()
                    fl = lerp(br.f0, br.f1, (i + tt) / (br.n - 1))
                    pair.append(mb.v(p + out * offset, fl, 0.0, 1.0, out))
                if len(pair) == 1: pair = [pair[0], pair[0]]
                bot.append(pair[0]); top.append(pair[1])
            for k in range(K - 1):
                a, b, c_, d = bot[k], bot[k + 1], top[k + 1], top[k]
                uu0 = k / (K - 1); uu1 = (k + 1) / (K - 1)
                if a == d:
                    mb.f((a, b, c_), mat_i, ((uu0, 0.5), (uu1, 0), (uu1, 1)), 'mark')
                elif b == c_:
                    mb.f((a, b, d), mat_i, ((uu0, 0), (uu1, 0.5), (uu0, 1)), 'mark')
                else:
                    mb.f((a, b, c_, d), mat_i, ((uu0, 0), (uu1, 0), (uu1, 1), (uu0, 1)), 'mark')

def row_at_z(br, z):
    """continuous ring-row coordinate of height z on a (monotonic in z) tube"""
    for i in range(br.n - 1):
        z0 = br.pts[i].z; z1 = br.pts[i + 1].z
        if z0 <= z <= z1 and z1 > z0:
            return i + (z - z0) / (z1 - z0)
    return float(br.n - 1) if z > br.pts[-1].z else 0.0

def surf_point(mb, br, r, c, offset):
    """point on the trunk surface at continuous ring row r and continuous column c, pushed out by offset (bilinear on the ring faces)"""
    ring = br.ring; sides = len(ring[0]); V = mb.V
    i = min(int(r), br.n - 2); t = r - i
    c = c % sides; j = int(c) % sides; fj = c - int(c); j2 = (j + 1) % sides
    pa = lerp(Vector(V[ring[i][j]]), Vector(V[ring[i][j2]]), fj)
    pb = lerp(Vector(V[ring[i + 1][j]]), Vector(V[ring[i + 1][j2]]), fj)
    p = lerp(pa, pb, t)
    cen = lerp(br.pts[i], br.pts[i + 1], t)
    out = p - cen
    T = br.T[i]
    out = out - T * out.dot(T)
    if out.length < 1e-6: out = Vector((1, 0, 0))
    out.normalize()
    return p + out * offset, out, lerp(br.f0, br.f1, r / (br.n - 1))

def bark_tongues(mb, br, rng, mat_i, per_ring=9, h=(0.25, 1.0), w=(0.05, 0.11), z0=0.2, offset=0.007, K=6):
    """black fissured-bark tongues rising from the trunk foot (pointed, ragged upper edge = real geometry, not face colouring)"""
    ring = br.ring; sides = len(ring[0])
    colw = 6.283 * br.radii[0] / sides
    n = max(3, int(per_ring))
    a0 = rng.uniform(0, sides)
    for k in range(n):
        c0 = a0 + sides * (k + rng.uniform(-0.3, 0.3)) / n
        hh = rng.uniform(*h) ** 1.0
        hh = h[0] + (h[1] - h[0]) * rng.random() ** 1.6
        ww = rng.uniform(*w)
        drift = rng.uniform(-0.6, 0.6)
        zb = z0 - 0.1; zt = z0 + hh
        L = []; R = []
        apex = None
        for q in range(K):
            u = q / (K - 1)
            z = zb + (zt - zb) * u
            hw = 0.5 * ww * (1.0 - u) ** 0.75 / colw
            cc = c0 + drift * u * 1.5
            if q == K - 1:
                p, o, fl = surf_point(mb, br, row_at_z(br, z), cc, offset)
                apex = mb.v(p, fl, 0.0, 1.0, o)
            else:
                pl, ol, fl = surf_point(mb, br, row_at_z(br, z), cc - hw, offset)
                pr, orr, fl2 = surf_point(mb, br, row_at_z(br, z), cc + hw, offset)
                L.append(mb.v(pl, fl, 0.0, 1.0, ol)); R.append(mb.v(pr, fl2, 0.0, 1.0, orr))
        for q in range(K - 2):
            mb.f((L[q], R[q], R[q + 1], L[q + 1]), mat_i, ((0, q / (K - 1)), (1, q / (K - 1)), (1, (q + 1) / (K - 1)), (0, (q + 1) / (K - 1))), 'mark')
        mb.f((L[K - 2], R[K - 2], apex), mat_i, ((0, 0.8), (1, 0.8), (0.5, 1)), 'mark')

def splinters(mb, rng, mat_i, centre, r, n, lmin, lmax, up=Vector((0, 0, 1)), flex=0.3):
    """jagged wood shards standing up from a snapped trunk / limb top"""
    a0 = rng.uniform(0, 6.283)
    for k in range(n):
        az = a0 + 6.283 * (k + rng.uniform(-0.3, 0.3)) / n
        out = Vector((math.cos(az), math.sin(az), 0))
        L = rng.uniform(lmin, lmax)
        base = centre + out * r * rng.uniform(0.35, 0.8) - up * 0.12
        tip = base + up * (L + 0.12) + out * rng.uniform(-0.05, 0.12) * L + Vector((rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), 0))
        mid = lerp(base, tip, 0.5)
        tube(mb, [base, mid, tip], [r * 0.22, r * 0.15, 0.012], 4, mat_i, f0=flex, f1=flex + 0.2, cap0=False, cap1='apex', amp=0.15, ridged=True, kf=3.0)

# --------------------------------------------------------------------------------------------- CONIFER
def conifer_teeth(mb, br, rng, P, mat, ctr_z):
    L = br.length
    step = P['tstep']
    s = P.get('s_start', 0.12)
    tprof = P.get('tprof', ((0.30, 1.0), (0.68, 0.60)))
    while s < 1.0:
        pos, tan, r, fx = br.at(s)
        side = tan.cross(ZUP)
        if side.length < 0.1: side = tan.cross(Vector((1, 0, 0)))
        side.normalize()
        prof = math.sin(math.pi * min(1.0, 0.12 + 0.88 * s) ** 0.85)
        tl = P['tlen'] * (0.30 + 0.70 * max(prof, 0.0)) * (1.0 - 0.25 * s) * rng.uniform(0.85, 1.15) * clamp(L / (0.55 * P['Lmax']), 0.4, 1.0)
        ctr = Vector((0, 0, pos.z - 1.2))
        # deterministic (hash, no rng) droop variation so spray tips do not all hang the same way
        tdv = 1.0 + P.get('tdroop_var', 0.0) * (2.0 * hrand(pos.x * 3.1, pos.y * 5.7, pos.z * 2.3) - 1.0)
        for sg in (1, -1):
            ang = math.radians(rng.uniform(50, 72))
            d = tan * math.cos(ang) + side * sg * math.sin(ang)
            d = (d + Vector((0, 0, -P['hang']))).normalized()
            blade(mb, pos + side * sg * r * 0.5, d, ZUP, tl, P['tw'] * rng.uniform(0.85, 1.15), mat, fx, g0=0.3, fold=0.35,
                  prof=tprof, droop=P['tdroop'] * tdv, ctr=ctr, ballw=0.45, tag='needle')
        if rng.random() < P['topchance']:
            d = (tan * 0.8 + ZUP * 0.55).normalized()
            blade(mb, pos + ZUP * r * 0.5, d, ZUP, tl * 0.75, P['tw'] * 0.9, mat, fx, g0=0.3, fold=0.3,
                  prof=tprof, droop=P['tdroop'] * 0.5, ctr=ctr, ballw=0.45, tag='needle')
        if rng.random() < P.get('belowchance', 0.0):
            d = (tan * 0.6 - ZUP * 0.7 + side * rng.uniform(-0.4, 0.4)).normalized()
            blade(mb, pos - ZUP * r * 0.5, d, ZUP, tl * 0.8, P['tw'] * 0.85, mat, fx, g0=0.3, fold=0.3,
                  prof=tprof, droop=P['tdroop'] * 0.4, ctr=ctr, ballw=0.45, tag='needle')
        s += step / max(L, 0.3) * rng.uniform(0.85, 1.15)
    pos, tan, r, fx = br.at(1.0)
    for k in range(3):
        a = rot_about(tan, ZUP, rng.uniform(-0.5, 0.5))
        a = (a + Vector((0, 0, rng.uniform(-0.1, 0.3)))).normalized()
        blade(mb, pos - tan * 0.1, a, ZUP, P['tlen'] * 0.55, P['tw'] * 0.8, mat, fx, g0=0.4, fold=0.3, prof=((0.35, 1.0),),
              ctr=Vector((0, 0, pos.z - 1.2)), ballw=0.45, tag='needle')

def tier_skirt(mb, c, blist, mat, nseg=16, frac=0.52, drop=0.55, top=0.12, rough=0.0):
    """dark needle skirt under a whorl: gives the tier solid mass behind the feather sprays.
       rough > 0: ragged rim (per-sector radius jitter + alternating drooping teeth / notches) instead of a smooth lampshade edge."""
    apex = mb.v(c + ZUP * top, 0.2, 0.1, 1.0, Vector((0, 0, 1)))
    su0, sv0, su1, sv1 = strip_uvr(c)
    M = nseg * (2 if rough > 0 else 1)
    r1 = []; r2 = []
    for j in range(M):
        az = 2 * math.pi * j / M
        best = min(blist, key=lambda t: abs(math.atan2(math.sin(az - t[0]), math.cos(az - t[0]))))
        h1 = ((j * 7919) % 13) / 13.0
        h2 = hrand(j * 1.7, c.z * 3.1, 2.1)
        if rough > 0:
            tooth = (j % 2 == 0)
            R = best[1] * frac * (1.0 - rough * (0.55 * h2)) * (1.0 if tooth else (1.0 - 0.38 * rough))
            dr = (drop * R + 0.1) * ((1.0 + 0.45 * rough * (h1 - 0.3)) if tooth else (1.0 - 0.35 * rough))
        else:
            R = best[1] * frac * (0.85 + 0.3 * h1)
            dr = drop * R + 0.1
        for ring, f, dz, fl in ((r1, 0.5, -0.05, 0.35), (r2, 1.0, -dr, 0.9)):
            p = c + Vector((math.cos(az) * R * f, math.sin(az) * R * f, dz))
            n = Vector((math.cos(az) * 0.55, math.sin(az) * 0.55, 0.85)).normalized()
            ring.append(mb.v(p, fl, 0.25 if f > 0.9 else 0.1, 1.0, n))
    for j in range(M):
        j2 = (j + 1) % M
        ua = su0 + 0.25 * j / M; ub = su0 + 0.25 * (j + 1) / M; um = su0 + 0.125
        mb.f((apex, r1[j], r1[j2]), mat, ((um, 1), (ua, 0.5), (ub, 0.5)), 'core')
        mb.f((r1[j], r2[j], r2[j2], r1[j2]), mat, ((ua, 0.5), (ua, 0), (ub, 0), (ub, 0.5)), 'core')

def pine_branch(mb, rng, P, bark, need, start, az, el0, L, droop, uptip, rb, seed, z, sleeve=None, wob=0.18, tooth_P=None):
    """one needle-sleeved conifer branch (curved tube whose outer part is needle material) + feather sprays (conifer_teeth)"""
    nseg = max(5, int(L / 0.55))
    bp = [start]
    for i in range(nseg):
        s = (i + 0.5) / nseg
        e = el0 - droop * s + uptip * s ** 3
        a = az + wob * math.sin(s * 5 + az * 3)
        bp.append(bp[-1] + dir_from(a, e) * (L / nseg))
    rr = taper(len(bp), rb, 0.008, power=0.9, collar=0.25)
    sl = P.get('sleeve', 0.0) if sleeve is None else sleeve
    if sl > 0:
        nn_ = len(bp)
        for ii in range(nn_):
            rr[ii] *= 1.0 + P.get('sleeve_r', 0.9) * smoothstep(sl, sl + 0.25, ii / (nn_ - 1))
        br = tube(mb, bp, rr, 6, bark, f0=0.18, f1=1.0, amp=0.05, cap0=False, cap1='apex', seed=seed,
                  matfn=(lambda i, j, _n=nn_: need if i >= int(sl * _n) else bark), leafmats={need})
    else:
        br = tube(mb, bp, rr, 6, bark, f0=0.18, f1=1.0, amp=0.05, cap0=False, cap1='apex', seed=seed)
    conifer_teeth(mb, br, rng, tooth_P or P, need, z)
    return br

def build_pine(mb, rng, P):
    bark = mb.mi('M_Tree_Bark'); need = mb.mi('M_Tree_Needle')
    H = P['H']; r0 = P['r0']
    pts = trunk_path(H, P['seed'], P['sway'], P.get('lean', (0, 0)), n=int(H / 0.3))
    radii = []
    for p in pts:
        s = clamp(p.z / H)
        radii.append(max(r0 * (1 - s) ** P['taper'], 0.03))
    fl = root_flare(P['flare'], 0.9, P.get('lobes', 5), P['seed'])
    sides_t = int(clamp(round(6.283 * r0 * 1.3 / 0.095), 16, 48))
    trunk = tube(mb, pts, radii, sides_t, bark, f0=0.0, f1=0.35, amp=0.12, kf=3.2, kz=0.7, seed=P['seed'], flare=fl, cap0=True, cap1='apex', ridged=True, lump=0.05)
    lobes_ = P.get('lobes', 5)
    add_roots(mb, rng, bark, r0 * (1 + P['flare'] * 0.6), lobes_, P.get('root_reach', 1.3) * r0 / 0.42, seed=P['seed'], az0=-P['seed'] / lobes_)
    def trunk_at_z(z):
        s = clamp((z + 0.25) / (H + 0.25))
        pos, tan, r, fx = trunk.at(s)
        return pos, r, fx
    z = 1.0
    while z < P['z0'] - 0.2:
        pos, r, fx = trunk_at_z(z)
        az = rng.uniform(0, 6.283)
        d = dir_from(az, math.radians(rng.uniform(-25, 15)))
        Ls = rng.uniform(0.18, 0.5)
        pp = [pos + d * r * 0.6, pos + d * (r * 0.6 + Ls * 0.5), pos + d * (r * 0.6 + Ls)]
        tube(mb, pp, [0.028, 0.02, 0.009], 5, bark, f0=0.1, f1=0.3, cap0=False, cap1='apex')
        z += rng.uniform(0.45, 0.9)
    z = P['z0']
    skip = P.get('skip', 0.0)
    sjit = P.get('spacing_jit', 0.15)
    nsubs = P.get('subs', 0)
    P_sub = dict(P, tstep=P['tstep'] * P.get('sub_tstep', 1.25), tlen=P['tlen'] * P.get('sub_tlen', 0.85), Lmax=P['Lmax'] * P.get('sub_len', 0.38) * 1.1)
    while z < H - 0.45:
        frac = (z - P['z0']) / (H - P['z0'])
        nb = int(round(lerp(P['nb0'], P['nb1'], frac) + rng.uniform(-0.6, 0.6)))
        az0 = rng.uniform(0, 6.283)
        wr = 1.0 + P.get('whorl_jit', 0.0) * (2.0 * hrand(z * 3.7, P['seed'], 1.3) - 1.0)     # per-whorl size variation (hash, no rng)
        blist = []
        for b in range(nb):
            if skip and rng.random() < skip: continue
            az = az0 + 6.283 * b / nb + rng.uniform(-0.3, 0.3)
            L = P['Lmax'] * (1 - frac) ** P['lp'] * rng.uniform(0.80, 1.12) * wr
            if P.get('short', 0.0) and rng.random() < P['short']:
                L *= rng.uniform(0.35, 0.6)                    # broken / stunted branch
            if P.get('lee') is not None:
                L *= lerp(1.0, 0.45 + 0.9 * (0.5 + 0.5 * math.cos(az - P['lee'])), P.get('lee_amt', 0.7))
            L = max(L, 0.5)
            el0 = math.radians(lerp(P['el_bot'], P['el_top'], frac)) + rng.uniform(-0.12, 0.12)
            pos, r, fx = trunk_at_z(z + rng.uniform(-0.1, 0.1))
            rb = clamp(L * 0.0165 + 0.012, 0.02, 0.1)
            br = pine_branch(mb, rng, P, bark, need, pos + dir_from(az, el0) * r * 0.5, az, el0, L, P['droop'], P['uptip'], rb, int(z * 10 + b), z)
            if nsubs and L > 1.0:
                # side twigs: turn the flat feather into a fuller, 3-D spray (alternating sides, shorter towards the tip)
                for k in range(nsubs):
                    s_ = lerp(P.get('sub_s0', 0.3), P.get('sub_s1', 0.8), (k + rng.uniform(0.1, 0.9)) / nsubs)
                    spos, stan, sr, sfx = br.at(s_)
                    th = math.atan2(stan.y, stan.x); el = math.asin(clamp(stan.z, -1.0, 1.0))
                    sg = 1 if (k + b) % 2 == 0 else -1
                    a_s = th + sg * math.radians(rng.uniform(*P.get('sub_ang', (32, 58))))
                    e_s = el - 0.12 + rng.uniform(-0.12, 0.12)
                    Ls = max(0.5, L * P.get('sub_len', 0.38) * (1.1 - 0.7 * s_) * rng.uniform(0.8, 1.1))
                    pine_branch(mb, rng, P, bark, need, spos + dir_from(a_s, e_s) * sr * 0.5, a_s, e_s, Ls, P['droop'] * 0.8, P['uptip'] * 0.8,
                                clamp(Ls * 0.0165 + 0.01, 0.014, 0.05), int(z * 10 + b * 7 + k), z, tooth_P=P_sub)
            blist.append((az, L))
        if blist and P.get('skirt', True):
            pos0, r0_, fx0 = trunk_at_z(z)
            tier_skirt(mb, pos0, blist, need, frac=P.get('skirt_frac', 0.52), drop=P.get('skirt_drop', 0.55), rough=P.get('skirt_rough', 0.0))
        dz_est = P['spacing'] * lerp(1.0, 0.8, frac)
        for k in range(P.get('inter', 0)):
            # short branchlets between the whorls hide the bare trunk and break up the periodic stack
            zi = z + dz_est * rng.uniform(0.3, 0.85)
            if zi > H - 0.6: continue
            azi = rng.uniform(0, 6.283)
            Li = max(0.5, P['Lmax'] * (1 - frac) ** P['lp'] * P.get('inter_len', 0.5) * rng.uniform(0.7, 1.15) * wr)
            eli = math.radians(lerp(P['el_bot'], P['el_top'], frac)) + rng.uniform(-0.1, 0.15)
            posi, ri, fxi = trunk_at_z(zi)
            pine_branch(mb, rng, P, bark, need, posi + dir_from(azi, eli) * ri * 0.5, azi, eli, Li, P['droop'], P['uptip'], clamp(Li * 0.0165 + 0.012, 0.018, 0.06),
                        int(zi * 10 + k), zi, tooth_P=P_sub if P.get('inter_fine', True) else None)
        z += P['spacing'] * rng.uniform(1.0 - sjit, 1.0 + sjit) * lerp(1.0, 0.8, frac)
    top = trunk.at(1.0)[0]
    for k in range(8):
        az = rng.uniform(0, 6.283)
        d = dir_from(az, math.radians(rng.uniform(40, 82)))
        blade(mb, top - ZUP * 0.25, d, ZUP, P['tlen'] * rng.uniform(0.5, 0.8), P['tw'] * 0.8, need, 1.0, g0=0.5, fold=0.3, prof=((0.3, 1.0), (0.7, 0.55)),
              ctr=top - ZUP * 2.0, ballw=0.5, tag='needle')
    zs = [-0.1, 0.5, 1.6, min(4.0, P['z0'] + 1.0)]
    ring = [ring_at_z(trunk, zz, rmul=0.88) for zz in zs]
    ring[0] = (ring[0][0], ring[0][1] * (1 + P['flare'] * 0.5))
    ring[1] = (ring[1][0], ring[1][1] * (1 + P['flare'] * 0.25))
    return dict(hulls=[ring], trunk=trunk, crown_w=2 * P['Lmax'] * 0.9)

# --------------------------------------------------------------------------------------------- SCOTS PINE (layered plates)
def tuft_pad(mb, rng, c, R, P, flat=None):
    """needle-tuft pad: flattened clump = dark core mass + short fat needle-pair cards radiating mostly sideways/up (underside culled)"""
    sx = rng.uniform(0.85, 1.3) if P.get('pad_irreg', True) else 1.0
    sy = rng.uniform(0.85, 1.3) if P.get('pad_irreg', True) else 1.0
    fz = flat if flat is not None else P.get('pad_flat', 0.45) * rng.uniform(0.85, 1.2)
    clump(mb, c, R, rng, mb.mi('M_Tree_Needle'), flex=0.9, squash=(sx, sy, fz), leaf=P['leaf_size'],
          cover=P['cover'], core=P['core'], core_sub=1, shape=P.get('leaf_shape', ((0.5, 1.0),)), fold=P.get('fold', 0.2), curl=P.get('curl', -0.1),
          ctr=c - ZUP * P.get('pad_ctr', 1.6), ballw=0.5, droop=P.get('ldroop', 0.25), outward=P.get('outward', 1.4), seed=rng.uniform(0, 99),
          cull_in=P.get('cull_in', 0.5), g_base=0.3, uvr=strip_uvr(c), jitter=0.2, up_bias=P.get('up_bias_leaf', 0.45))

def build_scots(mb, rng, P):
    """Scots pine: slender curved trunk, clear lower trunk with dead stubs and two long drooping needle-sleeved arms, then an irregular crown of
       SEPARATE horizontal plates: each plate = one thick limb (distinct fork height, diverging outward, collar at the trunk) with side twigs and
       flattened needle-tuft pads at the end / along it. No single dome, no bundle of parallel ropes."""
    bark = mb.mi('M_Tree_Bark'); need = mb.mi('M_Tree_Needle')
    H = P['H']; r0 = P['r0']
    pts = trunk_path(H, P['seed'], P['sway'], P.get('lean', (0, 0)), n=int(H / 0.3))
    radii = [max(r0 * (1 - clamp(p.z / H)) ** P['taper'], 0.04) for p in pts]
    fl = root_flare(P['flare'], 0.9, P.get('lobes', 5), P['seed'])
    sides_t = int(clamp(round(6.283 * r0 * 1.3 / 0.095), 16, 48))
    trunk = tube(mb, pts, radii, sides_t, bark, f0=0.0, f1=0.35, amp=0.11, kf=3.2, kz=0.7, seed=P['seed'], flare=fl, cap0=True, cap1='apex', ridged=True, lump=0.05)
    lobes_ = P.get('lobes', 5)
    add_roots(mb, rng, bark, r0 * (1 + P['flare'] * 0.6), lobes_, P.get('root_reach', 1.3) * r0 / 0.42, seed=P['seed'], az0=-P['seed'] / lobes_)
    def trunk_at_z(z):
        pos, tan, r, fx = trunk.at(clamp((z + 0.25) / (H + 0.25)))
        return pos, r, fx
    # dead branch stubs on the clear trunk
    for k in range(P.get('stubs', 8)):
        z = rng.uniform(0.9, P['limb_z'][0] - 0.2)
        pos, r, fx = trunk_at_z(z)
        d = dir_from(rng.uniform(0, 6.283), math.radians(rng.uniform(-20, 20)))
        Ls = rng.uniform(0.16, 0.42)
        tube(mb, [pos + d * r * 0.6, pos + d * (r * 0.6 + Ls * 0.5), pos + d * (r * 0.6 + Ls)], [0.04, 0.03, 0.014], 5, bark, f0=0.1, f1=0.3, cap0=False, cap1='apex', amp=0.12, ridged=True)
    zlo, zhi = P['limb_z']
    def plate_limb(z, az, L, el_t, f, k):
        """one thick limb (collar at the trunk, diverges outward) ending in an irregular plate of needle-tuft pads + side twigs with pads"""
        pos, r, fx = trunk_at_z(z)
        dh = Vector((math.cos(az), math.sin(az), 0))
        p0 = pos + dh * r * 0.55
        tip = p0 + dh * L + Vector((0, 0, L * math.tan(el_t)))
        rise = 0.22 if el_t > -0.2 else 0.10
        p1 = p0 + dh * L * 0.30 + Vector((0, 0, L * rise)) + vrand(rng, L * 0.05)
        p2 = tip - dh * L * 0.30 + Vector((0, 0, -L * 0.02 if el_t > -0.2 else L * 0.10)) + vrand(rng, L * 0.06)
        nseg = int(clamp(L / 0.42, 6, 12))
        pl = bezier_pts(p0, p1, p2, tip, nseg)
        rb = P['limb_r'] * lerp(1.0, 0.6, f) * rng.uniform(0.9, 1.1)
        rad = taper(nseg + 1, rb, rb * 0.26, power=0.8)
        kk = max(2, int(nseg * 0.32))
        for ii in range(min(kk, nseg + 1)):
            rad[ii] *= 1.0 + 0.7 * (1.0 - ii / kk) ** 2
        br = tube(mb, pl, rad, 8 if rb > 0.1 else 6, bark, f0=0.2, f1=0.6, amp=0.08, kf=2.6, kz=0.5, seed=int(z * 10 + k), cap0=False, cap1='apex', ridged=True)
        R0 = P['padR'] * rng.uniform(0.9, 1.15) * lerp(1.1, 0.85, f)
        # plate: terminal pad + several irregular pads spread along the outer half of the limb (different sizes / heights = a ragged layer)
        pe, te, re_, fe = br.at(1.0)
        sidev = te.cross(ZUP)
        sidev = sidev.normalized() if sidev.length > 1e-4 else Vector((-dh.y, dh.x, 0))
        tuft_pad(mb, rng, pe + Vector((0, 0, 0.12)), R0, P)
        npad = P.get('plate_pads', 5)
        for q in range(npad):
            s_ = lerp(0.4, 0.94, (q + rng.uniform(0.1, 0.9)) / npad)
            pf, tf, rf, ff = br.at(s_)
            off = sidev * rng.choice((-1, 1)) * R0 * rng.uniform(0.35, 1.0)
            tuft_pad(mb, rng, pf + off + Vector((0, 0, rng.uniform(-0.05, 0.3))), R0 * rng.uniform(0.55, 0.85), P)
        # side twigs with their own pad
        nsb = 2 if L > 2.2 else 1
        for q in range(nsb):
            s_ = lerp(0.34, 0.8, (q + rng.uniform(0.15, 0.85)) / nsb)
            sp, st_, sr_, sfx = br.at(s_)
            th = math.atan2(st_.y, st_.x)
            sg = 1 if (q + k) % 2 == 0 else -1
            a_s = th + sg * math.radians(rng.uniform(38, 66))
            Ls = L * rng.uniform(0.26, 0.38) * (1.1 - 0.5 * s_)
            ds = dir_from(a_s, math.radians(rng.uniform(4, 24) if el_t > -0.2 else rng.uniform(-25, -5)))
            s0 = sp + ds * sr_ * 0.5
            s3 = s0 + ds * Ls + Vector((0, 0, rng.uniform(-0.1, 0.25)))
            sb = bezier_pts(s0, s0 + ds * Ls * 0.35 + Vector((0, 0, Ls * 0.1)), s3 - ds * Ls * 0.3, s3, 5)
            tube(mb, sb, taper(6, sr_ * 0.5, 0.012, power=0.9), 5, bark, f0=0.3, f1=0.8, amp=0.06, cap0=False, cap1='apex')
            tuft_pad(mb, rng, s3 + Vector((0, 0, 0.1)), R0 * rng.uniform(0.6, 0.78), P)
    # long drooping lower limbs: sweep out and hang, carrying pads on the drooping ends
    for ki, (za, aza, La, ela) in enumerate(P.get('droop_limbs', [])):
        plate_limb(za, math.radians(aza), La, math.radians(ela), 0.0, 100 + ki)
    # plate limbs (distinct fork heights, golden-angle azimuths, shorter + more upturned towards the top)
    nl = P['nlimbs']
    az0 = rng.uniform(0, 6.283)
    for k in range(nl):
        f = clamp((k + rng.uniform(-0.22, 0.22)) / max(nl - 1, 1))
        z = lerp(zlo, zhi, f)
        az = az0 + k * 2.39996 + rng.uniform(-0.3, 0.3)
        L = lerp(P['L_lo'], P['L_hi'], f ** 0.85) * rng.uniform(0.85, 1.15)
        if P.get('lee') is not None:
            L *= lerp(1.0, 0.5 + 0.9 * (0.5 + 0.5 * math.cos(az - P['lee'])), P.get('lee_amt', 0.5))
        el_t = math.radians(lerp(P['el_lo'], P['el_hi'], f) + rng.uniform(-6, 6))
        plate_limb(z, az, L, el_t, f, k)
    # short side branches carrying small pads down the upper trunk
    for k in range(P.get('side_pads', 5)):
        z = rng.uniform(zlo - 1.6, zlo + 0.3)
        pos, r, fx = trunk_at_z(z)
        az = rng.uniform(0, 6.283)
        d = dir_from(az, math.radians(rng.uniform(-14, 10)))
        Ls = rng.uniform(0.9, 1.7)
        p0 = pos + d * r * 0.6
        p3 = p0 + d * Ls + Vector((0, 0, rng.uniform(-0.15, 0.2)))
        sb = bezier_pts(p0, p0 + d * Ls * 0.35 + Vector((0, 0, 0.1)), p3 - d * Ls * 0.3, p3, 6)
        tube(mb, sb, taper(7, 0.055, 0.014, power=0.9, collar=0.4), 6, bark, f0=0.3, f1=0.8, amp=0.06, cap0=False, cap1='apex')
        tuft_pad(mb, rng, p3 + Vector((0, 0, 0.08)), P['padR'] * rng.uniform(0.5, 0.66), P)
    # pads close to the trunk inside the crown (no see-through hole around the stem)
    for k in range(P.get('core_pads', 5)):
        z = rng.uniform(zlo + 0.8, zhi + 1.0)
        pp, rp, fp = trunk_at_z(z)
        az = rng.uniform(0, 6.283)
        tuft_pad(mb, rng, pp + Vector((math.cos(az), math.sin(az), 0)) * rng.uniform(0.4, 0.9) + Vector((0, 0, 0.1)), P['padR'] * rng.uniform(0.55, 0.75), P)
    # leader: a few pads around the top of the trunk
    top = trunk.at(1.0)[0]
    tuft_pad(mb, rng, top + Vector((0.05, 0.0, -0.1)), P['padR'] * 0.7, P, flat=0.8)
    for k in range(P.get('top_pads', 4)):
        az = rng.uniform(0, 6.283); dz = rng.uniform(0.6, 2.2)
        pp, rp, fp = trunk_at_z(top.z - dz)
        tuft_pad(mb, rng, pp + Vector((math.cos(az), math.sin(az), 0)) * rng.uniform(0.6, 1.0) + Vector((0, 0, 0.1)), P['padR'] * rng.uniform(0.55, 0.7), P)
    zs = [-0.1, 0.5, 1.6, min(4.0, P['limb_z'][0] - 0.4)]
    ring = [ring_at_z(trunk, zz, rmul=0.88) for zz in zs]
    ring[0] = (ring[0][0], ring[0][1] * (1 + P['flare'] * 0.5))
    ring[1] = (ring[1][0], ring[1][1] * (1 + P['flare'] * 0.25))
    return dict(hulls=[ring], trunk=trunk, crown_w=2 * P['L_lo'])

# --------------------------------------------------------------------------------------------- CROWN TREE ENGINE
def crown_tree(mb, rng, P):
    wood = mb.mi(P['wood'])
    leafm = mb.mi(P['leaf']) if P.get('leaf') else None
    cen = Vector(P['cen']); rad = Vector(P['rad']); bot = P.get('bot', 0.75)
    def qenv(p):
        d = p - cen
        dz = d.z / (bot if d.z < 0 else 1.0)
        return math.sqrt((d.x / rad.x) ** 2 + (d.y / rad.y) ** 2 + (dz / rad.z) ** 2)
    def inside(p, qmax=0.97):
        q = qenv(p)
        if q > qmax:
            return cen + (p - cen) * (qmax / q)
        return p
    stems = P.get('stems') or [dict(base=(0, 0), lean=P.get('lean', (0, 0)), h=P['trunk_h'], r0=P['r0'], rf=P['r_fork'])]
    node_pts = []
    nclump = [0]
    def put_clump(c, scale=1.0):
        if leafm is None: return
        q = qenv(c)
        R = P['clumpR'] * scale * rng.uniform(0.82, 1.18) * (1.0 - P.get('edge_shrink', 0.3) * smoothstep(0.65, 1.0, q))
        clump(mb, c, R, rng, leafm, flex=0.9, squash=P.get('squash', (1, 1, 0.8)), leaf=P['leaf_size'], cover=P.get('cover', 0.9),
              core=P.get('core', 0.72), core_sub=P.get('core_sub', 1), shape=P.get('leaf_shape', ((0.42, 1.0),)), fold=P.get('fold', 0.3),
              curl=P.get('curl', -0.12), ctr=cen, ballw=P.get('ballw', 0.55), droop=P.get('ldroop', 0.2), outward=P.get('outward', 0.6),
              seed=rng.uniform(0, 99), cull_in=P.get('cull_in', 0.35), g_base=0.3, uvr=strip_uvr(c),
              jitter=P.get('leaf_jit', 0.15), up_bias=P.get('up_bias_leaf', 0.35))
        nclump[0] += 1
    def branch(level, p0, d0, target, r0, f0, maxl=None):
        Lv = (target - p0).length
        if Lv < 0.2: return None
        p1 = p0 + d0 * Lv * 0.38 + vrand(rng, Lv * P.get('wig', 0.07) * 0.8)
        endt = ((target - p0).normalized() * 0.7 + Vector((0, 0, P.get('end_up', 0.3)))).normalized()
        p2 = target - endt * Lv * 0.30 + vrand(rng, Lv * P.get('wig', 0.07))
        nseg = int(clamp(Lv / P['seglen'][min(level, len(P['seglen']) - 1)], 4, 18))
        pts = bezier_pts(p0, p1, p2, target, nseg)
        L_ = min(level, len(P['r_end']) - 1)
        radii = taper(nseg + 1, r0, max(r0 * P['r_end'][L_], 0.010), power=P['tpow'], collar=0.12 if level else 0.0)
        cl = P.get('collar', 0.5) if level == 0 else P.get('collar2', 0.22)
        if cl > 0:
            kk = max(2, int(nseg * 0.35))
            for ii in range(min(kk, nseg + 1)):
                radii[ii] *= 1.0 + cl * (1.0 - ii / kk) ** 2
        gain = P['flex_gain'][min(level, len(P['flex_gain']) - 1)]
        last = level >= (len(P['nsub']) if maxl is None else maxl)
        wm = mb.mi(P['wood_lv'][min(level, len(P['wood_lv']) - 1)]) if P.get('wood_lv') else wood
        br = tube(mb, pts, radii, P['sides'][min(level, len(P['sides']) - 1)], wm, f0=f0, f1=f0 + (1 - f0) * gain,
                  amp=P['bark_amp'][min(level, len(P['bark_amp']) - 1)], kf=2.6, kz=0.5, seed=rng.randint(0, 999), cap0=(level == 0),
                  cap1=('flat' if (last and P.get('broken') and rng.random() < 0.6) else 'apex'))
        for s_ in (0.4, 0.7, 1.0):
            node_pts.append(br.at(s_)[0])
        if level == 0 and P.get('marks_limb'):
            lenticel_marks(mb, br, rng, mb.mi('M_Tree_Bark_Dark'), **P['marks_limb'])
        if not last:
            n = P['nsub'][level]
            for k in range(n):
                s = lerp(P['s0'][level], P['s1'][level], (k + rng.uniform(0.1, 0.9)) / n)
                pos, tan, rr, fx = br.at(s)
                sd = perp(tan)
                sd = rot_about(sd, tan, rng.uniform(0, 6.283))
                a = math.radians(rng.uniform(*P['ang'][level]))
                cd = tan * math.cos(a) + sd * math.sin(a)
                cd.z += P.get('up_bias', 0.25)
                cd.normalize()
                Lc = P['len_ratio'][level] * Lv * (1.15 - 0.7 * s) * rng.uniform(0.75, 1.15)
                tgt = inside(pos + cd * Lc)
                tgt.z = max(tgt.z, P.get('min_z', 2.0))
                branch(level + 1, pos + cd * rr * 0.5, cd, tgt, rr * P['r_ratio'][level], fx, maxl)
        else:
            if rng.random() >= P.get('bare', 0.0):
                put_clump(target)
            if Lv > P.get('mid_clump_len', 1e9) and rng.random() >= P.get('bare', 0.0):
                pos, tan, rr, fx = br.at(0.55)
                put_clump(pos + vrand(rng, 0.25), 0.8)
        return br
    trunks = []
    for st in stems:
        bx, by = st['base']
        h = st['h']
        nseg_t = int(h / P['trunk_ring']) if P.get('trunk_ring') else P.get('trunk_seg', 18)
        tseed = rng.randint(0, 999)
        pts = trunk_path(h, tseed, P.get('sway', 0.15), st['lean'], n=max(nseg_t, 6), spiral=P.get('spiral'))
        if P.get('trunk_dz'):
            dz0, dz1, za, zb = P['trunk_dz']
            dense = trunk_path(h, tseed, P.get('sway', 0.15), st['lean'], n=max(int(h / dz0), 8), spiral=P.get('spiral'))
            pts = thin_path(dense, dz0, dz1, za, zb)
        pts = [p + Vector((bx, by, 0)) for p in pts]
        radii = []
        for p in pts:
            s = clamp(p.z / h)
            radii.append(max(lerp(st['r0'], st['r0'] * st['rf'], s ** P.get('trunk_pow', 0.8)), 0.03))
        sides_t = P.get('trunk_sides', 18)
        if P.get('bark_cell'):
            sides_t = int(clamp(round(6.283 * st['r0'] * 1.2 / P['bark_cell']), 12, 72))
        lobes_ = P.get('lobes', 6)
        phase_ = rng.uniform(0, 6)
        fl = root_flare(P.get('flare', 0.4), P.get('flare_h', 0.9), lobes_, phase_)
        mfn = P.get('trunk_matfn')
        tr = tube(mb, pts, radii, sides_t, wood, f0=0.0, f1=0.18, amp=P.get('trunk_amp', 0.12), kf=P.get('trunk_kf', 2.4),
                  kz=P.get('trunk_kz', 0.3), seed=rng.randint(0, 999), flare=fl, cap0=True, cap1='apex',
                  matfn=(mfn(mb, pts) if mfn else None), ridged=P.get('ridged', False), lump=P.get('lump', 0.0),
                  ampfn=P.get('trunk_ampfn'), twist=P.get('twist', 0.0), peel=P.get('peel', 0.0), clefts=P.get('clefts'),
                  ridge_w=P.get('ridge_w', 0.17))
        trunks.append(tr)
        if P.get('marks'):
            lenticel_marks(mb, tr, rng, mb.mi('M_Tree_Bark_Dark'), **P['marks'])
        if P.get('tongues'):
            bark_tongues(mb, tr, rng, mb.mi('M_Tree_Bark_Dark'), **P['tongues'])
        if P.get('roots'):
            ol = P.get('roots_on_lobes', True)
            nr = lobes_ if ol else P['roots'][0]
            add_roots(mb, rng, wood, st['r0'] * (1 + P.get('flare', 0.4) * 0.6), nr, P['roots'][1], c=Vector((bx, by, 0)), seed=rng.uniform(0, 99),
                      az0=((-phase_ / lobes_) if ol else None), fat=P.get('root_fat', 1.0))
        for k in range(P.get('stubs', 0)):
            z = rng.uniform(0.7, max(1.0, h * 0.92))
            pos_s, tan_s, r_s, fx_s = tr.at(clamp((z + 0.25) / (h + 0.25)))
            d_s = dir_from(rng.uniform(0, 6.283), math.radians(rng.uniform(35, 70)))
            Ls = rng.uniform(0.18, 0.45)
            pp_ = [pos_s + d_s * r_s * 0.5, pos_s + d_s * (r_s * 0.5 + Ls * 0.5) + vrand(rng, 0.03), pos_s + d_s * (r_s * 0.5 + Ls) + vrand(rng, 0.05)]
            tube(mb, pp_, [0.085, 0.065, 0.04], 7, wood, f0=0.1, f1=0.3, cap0=False, cap1='apex', amp=0.15, ridged=True)
        fork = tr.pts[-1]
        nl = P.get('nlimbs', 5)
        a0 = rng.uniform(0, 6.283)
        for i in range(nl):
            az = a0 + i * 2.39996 + rng.uniform(-0.25, 0.25)
            phi = math.radians(rng.uniform(*P['limb_phi']))
            q = rng.uniform(*P['limb_q'])
            tgt = cen + Vector((rad.x * math.sin(phi) * math.cos(az), rad.y * math.sin(phi) * math.sin(az), rad.z * math.cos(phi))) * q
            tgt += Vector((bx, by, 0)) * 0.5
            tgt.z = max(tgt.z, fork.z + 0.8)
            outv = Vector((math.cos(az), math.sin(az), 0))
            d0 = (outv * P.get('limb_out', 0.6) + ZUP).normalized()
            rl = st['r0'] * st['rf'] * P.get('limb_r', 0.62) * rng.uniform(0.85, 1.1)
            if P.get('limb_r_list'): rl *= P['limb_r_list'][i % len(P['limb_r_list'])]      # per-limb thickness (no rng)
            zoff = rng.uniform(0.0, P.get('limb_stagger', 0.0)) if i > 0 else 0.0
            if zoff > 0.05:
                pos_s, tan_s, r_s, fx_s = tr.at(clamp((fork.z - zoff + 0.25) / (h + 0.25)))
                start = pos_s + outv * r_s * 0.28
            else:
                start = fork - ZUP * 0.1
            branch(0, start, d0, tgt, rl, 0.18)
        if P.get('leader'):
            tgt = Vector((bx, by, cen.z + rad.z * P.get('leader_q', 0.8)))
            branch(0, fork - ZUP * 0.1, ZUP, tgt, st['r0'] * st['rf'] * 0.7, 0.18)
        for sd in P.get('side', []):
            (zlo, zhi, nsb, ang, rratio, lmul) = sd[:6]
            drop = sd[6] if len(sd) > 6 else 0.0
            ga = rng.uniform(0, 6.283)
            for k in range(nsb):
                z = lerp(zlo, zhi, (k + rng.uniform(0.15, 0.85)) / nsb)
                pos, tan, rr, fx = tr.at(clamp((z + 0.25) / (h + 0.25)))
                az = ga + k * 2.39996
                a = math.radians(rng.uniform(*ang))
                cd = Vector((math.sin(a) * math.cos(az), math.sin(a) * math.sin(az), math.cos(a)))
                Ls = lmul(z) * rng.uniform(0.8, 1.15)
                tgt = inside(pos + cd * Ls)
                if drop:
                    tgt.z = max(tgt.z - drop * rng.uniform(0.7, 1.2), P.get('min_z', 2.0))
                branch(0, pos + Vector((cd.x, cd.y, 0)).normalized() * rr * 0.5, cd, tgt, rr * rratio, fx, (sd[7] if len(sd) > 7 else None))
    for k in range(P.get('fill', 0)):
        if not node_pts or leafm is None: break
        bp = rng.choice(node_pts)
        off = vrand(rng, 1.0) * P.get('fill_r', 1.4) + (bp - cen).normalized() * P.get('fill_out', 0.8)
        c = inside(bp + off, 0.96)
        if c.z < P.get('fill_min_z', P.get('min_z', 2.0)): continue
        put_clump(c, 0.85)
    af = P.get('axis_fill')
    if af:
        trk = trunks[0]; hh_ = stems[0]['h']
        zf = af['z0']
        while zf <= af['z1']:
            pos_a = trk.at(clamp((zf + 0.25) / (hh_ + 0.25)))[0]
            pr_ = af['prof'](zf)
            jx = (hrand(zf * 3.1, 1.7, 0.3) - 0.5) * af.get('jit', 0.0) * pr_          # lateral jitter breaks the stacked-lump banding (hash, no rng)
            jy = (hrand(zf * 2.3, 4.1, 0.9) - 0.5) * af.get('jit', 0.0) * pr_
            put_clump(Vector((pos_a.x + jx, pos_a.y + jy, zf)), pr_ / P['clumpR'])
            zf += af['step']
    for (ex, ey, ez, esc) in P.get('extra_clumps', []):
        put_clump(Vector((ex, ey, ez)), esc)
    if P.get('splinters'):
        n_, l0_, l1_ = P['splinters']
        for tr_ in trunks:
            splinters(mb, rng, wood, tr_.pts[-1], tr_.radii[-1], n_, l0_, l1_)
    zs = P.get('hull_z', [-0.1, 0.6, 1.8, 3.2])
    hulls = []
    for tr in trunks:        # one convex hull per stem (every stem is collidable)
        ring = [ring_at_z(tr, z, rmul=0.9) for z in zs]
        ring[0] = (ring[0][0], ring[0][1] * (1 + P.get('flare', 0.4) * 0.45))
        hulls.append(ring)
    return dict(hulls=hulls, trunk=trunks[0], crown_w=2 * max(rad.x, rad.y), clumps=nclump[0])

# --------------------------------------------------------------------------------------------- PALMS
def palm_frond(mb, rng, base, az, e0, Lf, droop, mat, rmat, P, ctr, flex0=0.55):
    nseg = 12
    pts = [base]
    for i in range(nseg):
        s = (i + 0.5) / nseg
        e = e0 - droop * s ** 1.25
        d = dir_from(az + 0.12 * math.sin(s * 4 + az * 2), e)
        pts.append(pts[-1] + d * (Lf / nseg))
    radii = taper(nseg + 1, P['rach_r'], 0.007, power=0.9)
    br = tube(mb, pts, radii, 5, rmat, f0=flex0, f1=1.0, cap0=False, cap1='apex', tag='wood')
    s = P.get('lf_s0', 0.14)
    ds = P['lf_step'] / Lf
    hang = math.radians(P['lf_hang'])
    prof = P.get('lf_prof', ((0.25, 0.92), (0.55, 0.85), (0.82, 0.5)))
    while s < 0.985:
        pos, tan, r, fx = br.at(s)
        side = tan.cross(ZUP)
        if side.length < 0.05: side = tan.cross(Vector((1, 0, 0)))
        side.normalize()
        upv = side.cross(tan)
        ell = P['lf_len'] * (math.sin(math.pi * (0.06 + 0.94 * min(1.0, s))) ** 0.55) * rng.uniform(0.88, 1.1)
        for sg in (1, -1):
            hg = hang + rng.uniform(-0.12, 0.12)
            lat = side * sg * math.cos(hg) - upv * math.sin(hg)
            d = (tan * P['lf_fwd'] + lat * (1 - P['lf_fwd'])).normalized()
            # leaflets droop more towards the frond tip (curved, hanging leaflets)
            blade(mb, pos, d, upv, ell, P['lf_w'], mat, fx, g0=0.4, g1=1.0, fold=0.5, curl=-0.12, prof=prof,
                  ctr=ctr, ballw=0.35, droop=P.get('lf_droop', 0.18) * (0.6 + 0.9 * s) * rng.uniform(0.8, 1.2), tag='leaf')
        s += ds * rng.uniform(0.9, 1.1)
    return br

def palm_fan(mb, rng, base, az, e0, Lp, droop, mat, rmat, P, ctr, fan_n=None, fan_len=None, fan_w=None, hang=None):
    nseg = 8
    pts = [base]
    for i in range(nseg):
        s = (i + 0.5) / nseg
        e = e0 - droop * s ** 1.4
        pts.append(pts[-1] + dir_from(az, e) * (Lp / nseg))
    radii = taper(nseg + 1, P['rach_r'], 0.02, power=0.8)
    br = tube(mb, pts, radii, 5, rmat, f0=0.5, f1=0.9, cap0=False, cap1='apex', tag='wood')
    pos, tan, r, fx = br.at(1.0)
    side = tan.cross(ZUP)
    if side.length < 0.05: side = tan.cross(Vector((1, 0, 0)))
    side.normalize()
    upv = side.cross(tan)
    n = fan_n or P['fan_n']
    flen = fan_len or P['fan_len']; fw = fan_w or P['fan_w']
    fh = hang if hang is not None else P['fan_hang']
    spread = math.radians(P['fan_spread'])
    for k in range(n):
        t = (k + 0.5) / n - 0.5
        phi = t * 2 * spread
        d = tan * math.cos(phi) + side * math.sin(phi)
        d = (d + upv * P.get('fan_lift', 0.05) + Vector((0, 0, -fh * abs(t) * 2))).normalized()
        ell = flen * (1.0 - 0.28 * abs(t) * 2) * rng.uniform(0.92, 1.08)
        blade(mb, pos - tan * 0.1, d, upv, ell, fw, mat, fx, g0=0.4, g1=1.0, fold=0.55, curl=-0.2, prof=((0.3, 0.9), (0.6, 0.8), (0.82, 0.55)),
              ctr=ctr, ballw=0.35, droop=P.get('fan_droop', 0.25) * rng.uniform(0.8, 1.25), tag='leaf', split=P.get('fan_split', 0.0))

def palm_roots(mb, rng, mat, c, r, n, lmin=0.35, lmax=0.7):
    """exposed adventitious root mass around the swollen palm foot"""
    a0 = rng.uniform(0, 6.283)
    for k in range(n):
        az = a0 + 6.283 * (k + rng.uniform(-0.3, 0.3)) / n
        d = Vector((math.cos(az), math.sin(az), 0))
        L = rng.uniform(lmin, lmax)
        p0 = c + d * r * 0.75 + Vector((0, 0, rng.uniform(0.18, 0.4)))
        pts = [p0, p0 + d * L * 0.45 + Vector((0, 0, -0.08)), p0 + d * L * 0.85 + Vector((0, 0, -0.30)), p0 + d * L + Vector((0, 0, -0.5))]
        tube(mb, pts, [0.055, 0.042, 0.03, 0.014], 5, mat, f0=0.0, f1=0.1, cap0=False, cap1='apex', amp=0.12, ridged=True, kf=3.0)

def build_palm(mb, rng, P):
    bark = mb.mi(P['bark']); leaf = mb.mi('M_Tree_Palm'); dead = bark
    dry = mb.mi('M_Tree_LeafDry') if P.get('dry_skirt') else bark
    H = P['H']
    lx, ly = P['lean']
    p0 = Vector((0, 0, -0.25)); p3 = Vector((lx, ly, H))
    p1 = Vector((lx * 0.02, ly * 0.02, H * 0.42)); p2 = Vector((lx * P.get('bend', 0.3), ly * P.get('bend', 0.3), H * 0.78))
    n = int(H / P['ring'])
    pts = bezier_pts(p0, p1, p2, p3, n)
    radii = [lerp(P['r0'], P['r1'], (i / n) ** 0.7) for i in range(n + 1)]
    sc = P['scar']; pitch = P['pitch']; fib = P.get('fiber', 0.0); dia = P.get('diamond', 0.0); bh = P.get('bulb_h', 0.8)
    def fl(th, z):
        zz = max(z, 0.0)
        bulb = P['bulb'] * math.exp(-zz / bh)
        ph = (zz / pitch) % 1.0
        ringm = sc * (0.5 - 0.5 * math.cos(6.283 * ph)) ** 2.2
        f = 1.0 + bulb + ringm + 0.03 * math.sin(th * 3 + zz)
        if fib:
            f += fib * math.sin(th * P.get('fib_n', 9) + 1.7 * math.sin(zz * 2.1))
        if dia:
            f += dia * math.sin(th * 7 + zz * 14.0) * math.sin(th * 7 - zz * 14.0)
        return f
    trunk = tube(mb, pts, radii, P.get('sides', 16), bark, f0=0.0, f1=0.4, amp=P.get('amp', 0.05), kf=2.0, kz=0.4, seed=P['seed'], flare=fl, cap0=True, cap1='flat')
    top = trunk.pts[-1]
    ctr = top - ZUP * 2.5
    if P.get('roots', 0):
        palm_roots(mb, rng, bark, Vector((0, 0, 0)), P['r0'] * (1 + P['bulb']), P['roots'])
    span = P.get('boot_span', 0.6)
    for k in range(P.get('boots', 10)):
        az = rng.uniform(0, 6.283)
        d = dir_from(az, math.radians(rng.uniform(-35, 15)))
        dz = rng.uniform(0.2, span)
        pos_b, tan_b, r_b, fx_b = trunk.at(clamp((top.z - dz + 0.25) / (H + 0.25)))
        p_a = pos_b + d * r_b * 0.7
        tube(mb, [p_a, p_a + d * 0.30 - ZUP * 0.12], [0.075, 0.05], 5, dead, f0=0.5, f1=0.7, cap0=False, cap1='flat')
    nf = P['nf']
    a0 = rng.uniform(0, 6.283)
    for k in range(nf):
        f = k / max(nf - 1, 1)
        az = a0 + k * 2.39996 + rng.uniform(-0.15, 0.15)
        e0 = math.radians(lerp(P['e_top'], P['e_bot'], f)) + rng.uniform(-0.08, 0.08)
        Lf = P['Lf'] * rng.uniform(*P.get('lf_var', (0.85, 1.1))) * lerp(0.8, 1.0, f)
        base = top + dir_from(az, 0.3) * P['r1'] * 0.6 - ZUP * 0.1
        if k == 0 and not P.get('fan'):
            pts_s = [base, base + ZUP * (Lf * 0.22), base + ZUP * (Lf * 0.45) + dir_from(az, 0.1) * 0.12, base + ZUP * (Lf * 0.62) + dir_from(az, 0.1) * 0.3]
            tube(mb, pts_s, [0.06, 0.05, 0.035, 0.012], 6, leaf, f0=0.6, f1=1.0, cap0=False, cap1='apex', tag='wood')
            continue
        if P.get('fan'):
            palm_fan(mb, rng, base, az, e0, Lf, P['droop'], leaf, leaf, P, ctr)
        else:
            dmul = 1.0
            up = P.get('upright')
            if up and k <= up[0]:
                e0 = max(e0, math.radians(up[1])); dmul = up[2]            # young, more upright central fronds
            palm_frond(mb, rng, base, az, e0, Lf, P['droop'] * rng.uniform(*P.get('droop_var', (0.85, 1.15))) * dmul, leaf, leaf, P, ctr)
    for k in range(P.get('skirt', 0)):
        az = rng.uniform(0, 6.283)
        pos = top - ZUP * rng.uniform(0.3, 0.9) + dir_from(az, 0) * P['r1'] * 0.8
        if P.get('dry_skirt'):
            # hanging dead fan fronds (straw coloured) = the shaggy skirt of Washingtonia
            palm_fan(mb, rng, pos, az, math.radians(-62 + rng.uniform(-8, 8)), P['skirt_len'] * 0.7, 0.45, dry, dry, P, ctr,
                     fan_n=11, fan_len=P['skirt_len'], fan_w=0.2, hang=0.25)
        else:
            d = (dir_from(az, 0) * 0.5 - ZUP * 1.0).normalized()
            blade(mb, pos, d, ZUP, P['skirt_len'] * rng.uniform(0.7, 1.1), 0.5, dead, 0.7, g0=0.3, fold=0.4, prof=((0.3, 1.0), (0.7, 0.7)), ctr=ctr, ballw=0.2, droop=0.2, tag='leaf')
    for k in range(P.get('nuts', 0)):
        az = rng.uniform(0, 6.283)
        c = top - ZUP * 0.5 + dir_from(az, 0) * (P['r1'] + 0.16 + rng.uniform(0, 0.14)) - ZUP * rng.uniform(0, 0.25)
        blob(mb, c, (0.12, 0.12, 0.17), rng, dead if P.get('nut_dead') else leaf, sub=2, jit=0.03, flex=0.8, g=0.2, ctr=c, ballw=1.0, tag='nut',
             rot=Matrix.Rotation(rng.uniform(-0.5, 0.5), 3, 'X') @ Matrix.Rotation(rng.uniform(0, 3.14), 3, 'Z'))
        tube(mb, [top - ZUP * 0.25 + dir_from(az, 0) * P['r1'] * 0.8, c + Vector((0, 0, 0.1))], [0.02, 0.016], 4, leaf, f0=0.6, f1=0.8, cap0=False, cap1='flat')
    zz = [[-0.1, 0.5, 1.8, 3.4], [3.4, 4.6, 5.8, 7.0]] if H > 8 else [[-0.1, 0.5, 1.6, 3.0], [3.0, 3.8, 4.6, 5.2]]
    hulls = [[ring_at_z(trunk, z, rmul=0.95, rmin=0.1) for z in zl] for zl in zz]
    hulls[0][0] = (hulls[0][0][0], hulls[0][0][1] * (1 + P['bulb'] * 0.8))
    return dict(hulls=hulls, trunk=trunk, crown_w=2 * P['Lf'] * 0.8)
