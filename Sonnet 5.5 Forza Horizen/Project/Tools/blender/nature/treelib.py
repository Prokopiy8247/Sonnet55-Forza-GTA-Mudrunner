"""
treelib.py - geometry core of the procedural TREE KIT (Blender 5.2 / bpy, run inside the shared MCP session).

Exec'd by Tools/blender/nature/trees.py.  Nothing here touches objects that do not belong to a tree asset id.

Vertex colours (attribute "Col", FLOAT, exported LINEAR = raw masks):
    R = branch flex  0 (trunk base) -> 1 (twig / leaf tips)       -> UE WPO sway amount
    G = leaf flutter 0 (wood) -> 1 (free leaf tips)                -> UE WPO flutter amount
    B = baked ambient occlusion (ray cast, 1 = open sky)           -> darken in UE material
"""
import bpy, bmesh, math, random, json, os, time, struct, zlib
import numpy as np
from mathutils import Vector, Matrix, Quaternion, noise as mn
from mathutils.bvhtree import BVHTree

PROJECT = r"W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza"
EXPORT_DIR = os.path.join(PROJECT, "Exports", "Nature", "Trees")
STAGE_Y = 60.0
FAR_Y = 180.0
STAGE_X0 = 400.0
STAGE_DX = 34.0
ZUP = Vector((0.0, 0.0, 1.0))
UV_TILE = 2.0   # metres of bark per UV tile on large trunks

# --------------------------------------------------------------------------------------------- small math
def vrand(rng, a=1.0):
    return Vector((rng.uniform(-a, a), rng.uniform(-a, a), rng.uniform(-a, a)))

def perp(t):
    a = Vector((0, 0, 1)) if abs(t.z) < 0.92 else Vector((1, 0, 0))
    n = t.cross(a)
    n.normalize()
    return n

def hrand(a, b, c=0.0):
    return (math.sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453) % 1.0

def strip_uvr(p):
    """leaf/needle cards of one element share a U strip (4 tint strips, see M_Tree_Leaf* nodes)"""
    k = int(hrand(p[0] * 7.1, p[1] * 3.3, p[2] * 1.7) * 4) % 4
    return (k * 0.25, 0.0, k * 0.25 + 0.25, 1.0)

def lerp(a, b, t):
    return a + (b - a) * t

def clamp(x, a=0.0, b=1.0):
    return a if x < a else (b if x > b else x)

def smoothstep(a, b, x):
    t = clamp((x - a) / (b - a) if b != a else 0.0)
    return t * t * (3 - 2 * t)

def rot_about(v, axis, ang):
    return Matrix.Rotation(ang, 3, axis) @ v

def dir_from(az, el):
    """azimuth (rad, 0 = +X, CCW) and elevation (rad above horizontal) -> unit vector"""
    c = math.cos(el)
    return Vector((math.cos(az) * c, math.sin(az) * c, math.sin(el)))

def nz(p, ox=0.0, oy=0.0, oz=0.0):
    return mn.noise(Vector((p[0] + ox, p[1] + oy, p[2] + oz)))

def seed_off(seed):
    r = random.Random(seed * 7919 + 13)
    return r.uniform(-50, 50), r.uniform(-50, 50), r.uniform(-50, 50)

_FIB = {}
def fib_dirs(n):
    """n roughly uniform unit vectors on the sphere (cached)"""
    if n not in _FIB:
        out = []
        ga = math.pi * (3 - math.sqrt(5))
        for i in range(n):
            z = 1 - 2 * (i + 0.5) / n
            r = math.sqrt(max(0.0, 1 - z * z))
            out.append(Vector((math.cos(ga * i) * r, math.sin(ga * i) * r, z)))
        _FIB[n] = out
    return _FIB[n]

def rand_rot(rng):
    q = Quaternion((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
    q.normalize()
    return q.to_matrix()

# --------------------------------------------------------------------------------------------- mesh builder
class MB:
    """Accumulates verts / faces / uv / colour / custom normals / material indices."""
    def __init__(self):
        self.V = []; self.C = []; self.N = []
        self.F = []; self.FM = []; self.UV = []
        self.mats = []
        self.tag = []        # per-face tag string (statistics / far-card colouring)
        self.open_faces = 0  # faces that belong to open (blade) pieces
        self.groups = []     # (v_start, v_end) vertex ranges that share one AO sample (leaf cards)

    def mi(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def v(self, p, r=0.0, g=0.0, b=1.0, n=None):
        self.V.append((p[0], p[1], p[2]))
        self.C.append((r, g, b))
        self.N.append(None if n is None else (n[0], n[1], n[2]))
        return len(self.V) - 1

    def f(self, idx, m, uvs, tag=''):
        self.F.append(tuple(idx)); self.FM.append(m); self.UV.append(uvs); self.tag.append(tag)

    def tris(self):
        n = 0
        for f in self.F:
            n += len(f) - 2
        return n

# --------------------------------------------------------------------------------------------- branch / tube
class Br:
    """a finished tube: remembers its centre line for attaching children"""
    def __init__(self, pts, radii, T, f0, f1):
        self.pts = pts; self.radii = radii; self.T = T; self.f0 = f0; self.f1 = f1
        self.n = len(pts)

    def at(self, s):
        s = clamp(s)
        x = s * (self.n - 1)
        i = min(int(x), self.n - 2)
        t = x - i
        pos = lerp(self.pts[i], self.pts[i + 1], t)
        tan = lerp(self.T[i], self.T[i + 1], t)
        tan.normalize()
        r = lerp(self.radii[i], self.radii[i + 1], t)
        return pos, tan, r, lerp(self.f0, self.f1, s)

    @property
    def length(self):
        return sum((self.pts[i + 1] - self.pts[i]).length for i in range(self.n - 1))

def frames(pts):
    n = len(pts)
    T = []
    for i in range(n):
        if i == 0: t = pts[1] - pts[0]
        elif i == n - 1: t = pts[-1] - pts[-2]
        else: t = pts[i + 1] - pts[i - 1]
        if t.length < 1e-9: t = Vector((0, 0, 1))
        t.normalize(); T.append(t)
    N = [perp(T[0])]
    for i in range(1, n):
        q = T[i - 1].rotation_difference(T[i])
        nn = q @ N[-1]
        nn = nn - T[i] * nn.dot(T[i]); nn.normalize()
        N.append(nn)
    return T, N

def tube(mb, pts, radii, sides, mat, f0=0.0, f1=1.0, uvu=None, uvv=None, amp=0.0, kf=2.2, kz=0.35, seed=0,
         flare=None, cap0=True, cap1='apex', matfn=None, g=0.0, tag='wood', nz2=0.35, ridged=False, lump=0.0,
         ampfn=None, twist=0.0, peel=0.0, clefts=None, leafmats=None, ridge_w=0.17):
    """closed tube along pts (list[Vector]) with per-point radii. Returns Br (with .ring = vertex ids per ring).
       ampfn(z) -> (amp, ridged) overrides amp/ridged per ring; twist = spiral of the relief per metre (rad);
       peel = depth of shallow 'peeled bark' patches; clefts = [(theta, half_width, z0, z1, depth)] narrow vertical splits;
       leafmats = set of material indices that are foliage (UV mapped into the 4-strip leaf tint layout)."""
    n = len(pts)
    T, Nn = frames(pts)
    cum = [0.0]
    for i in range(1, n):
        cum.append(cum[-1] + (pts[i] - pts[i - 1]).length)
    if uvu is None or uvv is None:
        # consistent texel density: ~1 bark tile (2 m) around big trunks, exactly 1 tile around thin twigs, square texels
        circ = 2 * math.pi * max(sum(radii) / len(radii), 0.01)
        nu = max(1, int(round(circ / UV_TILE)))
        uvu = float(nu); uvv = nu / circ
    ox, oy, oz = seed_off(seed)
    ring = []
    for i in range(n):
        t = T[i]; nn = Nn[i]; bb = t.cross(nn)
        fl = f0 + (f1 - f0) * (i / (n - 1))
        r = radii[i]
        row = []
        for j in range(sides):
            th = 2 * math.pi * j / sides
            ct, st = math.cos(th), math.sin(th)
            d = nn * ct + bb * st
            rr = r
            a_i, rg_i = amp, ridged
            if ampfn is not None:
                a_i, rg_i = ampfn(pts[i].z)
            if a_i > 0 and r > 0.012:
                if twist:
                    tw = th + twist * cum[i]
                    cq, sq_ = math.cos(tw), math.sin(tw)
                else:
                    cq, sq_ = ct, st
                q = Vector((cq * kf + ox, sq_ * kf + oy, cum[i] * kz + oz))
                n1 = mn.noise(q)
                if rg_i:
                    # fissured bark: narrow valleys along the n=0 contours (long vertical cracks) + plate relief
                    fz = math.exp(-(n1 / ridge_w) ** 2)
                    n2 = mn.noise(q * 2.7 + Vector((5.0, 5.0, 5.0)))
                    disp = 0.30 - 1.0 * fz + 0.35 * n2
                else:
                    disp = n1 * (1 - nz2) + mn.noise(q * 2.9) * nz2
                rr = r * (1 + a_i * disp)
            if peel > 0 and r > 0.05:
                pq = Vector((ct * 1.3 + oy, st * 1.3 + ox, cum[i] * 0.9 + oz * 0.5))
                rr *= 1.0 - peel * smoothstep(0.12, 0.34, mn.noise(pq))
            if clefts:
                for (c_th, c_hw, c_z0, c_z1, c_d) in clefts:
                    dth = math.atan2(math.sin(th - c_th), math.cos(th - c_th))
                    zz = pts[i].z
                    if c_z0 - 0.3 < zz < c_z1 + 0.3:
                        zf = smoothstep(c_z0 - 0.3, c_z0 + 0.1, zz) * (1.0 - smoothstep(c_z1 - 0.15, c_z1 + 0.3, zz))
                        rr *= 1.0 - c_d * zf * math.exp(-(dth / c_hw) ** 2)
            if lump:
                rr *= 1.0 + lump * mn.noise(Vector((ct * 0.9 + oy, st * 0.9 + ox, cum[i] * 0.5 + oz)))
            if flare is not None:
                rr *= flare(th, pts[i].z)
            row.append(mb.v(pts[i] + d * rr, fl, g, 1.0))
        ring.append(row)
    for i in range(n - 1):
        for j in range(sides):
            j2 = (j + 1) % sides
            a = ring[i][j]; b = ring[i][j2]; c = ring[i + 1][j2]; d = ring[i + 1][j]
            u0 = j / sides * uvu; u1 = (j + 1) / sides * uvu
            v0 = cum[i] * uvv; v1 = cum[i + 1] * uvv
            m = matfn(i, j) if matfn else mat
            if leafmats and m in leafmats:
                su0, sv0, su1, sv1 = strip_uvr(pts[i])
                fu0 = su0 + (su1 - su0) * (j / sides); fu1 = su0 + (su1 - su0) * ((j + 1) / sides)
                fv0 = i / (n - 1); fv1 = (i + 1) / (n - 1)
                mb.f((a, b, c, d), m, ((fu0, fv0), (fu1, fv0), (fu1, fv1), (fu0, fv1)), 'core')
            else:
                mb.f((a, b, c, d), m, ((u0, v0), (u1, v0), (u1, v1), (u0, v1)), tag)
    if cap0:
        c0 = mb.v(pts[0] - T[0] * radii[0] * 0.25, f0, g, 1.0)
        for j in range(sides):
            j2 = (j + 1) % sides
            mb.f((c0, ring[0][j2], ring[0][j]), mat if matfn is None else matfn(0, j), ((0.5, 0), (1, 0), (0, 0)), tag)
    if cap1 == 'apex':
        ap = mb.v(pts[-1] + T[-1] * max(radii[-1], 0.01) * 1.6, f1, g, 1.0)
        for j in range(sides):
            j2 = (j + 1) % sides
            mb.f((ap, ring[-1][j], ring[-1][j2]), mat if matfn is None else matfn(n - 2, j), ((0.5, 1), (0, 1), (1, 1)), tag)
    elif cap1 == 'flat':
        ap = mb.v(pts[-1], f1, g, 1.0)
        for j in range(sides):
            j2 = (j + 1) % sides
            mb.f((ap, ring[-1][j], ring[-1][j2]), mat if matfn is None else matfn(n - 2, j), ((0.5, 1), (0, 1), (1, 1)), tag)
    br = Br(pts, radii, T, f0, f1)
    br.ring = ring
    return br

def curve_pts(p0, d0, length, nseg, rng, wobble=0.12, trop=0.0, twist=0.0, nseed=0, nscale=0.0):
    """walk a polyline: initial direction d0, wobble (random), trop = z pull per segment (+up / -droop)"""
    pts = [Vector(p0)]
    d = Vector(d0).normalized()
    seg = length / nseg
    ox, oy, oz = seed_off(nseed)
    for i in range(nseg):
        d = d + vrand(rng, wobble) + Vector((0, 0, trop))
        if nscale:
            q = pts[-1]
            d += Vector((mn.noise(Vector((q.x * .4 + ox, q.y * .4 + oy, q.z * .4 + oz))),
                         mn.noise(Vector((q.x * .4 + oy, q.y * .4 + oz, q.z * .4 + ox))), 0.0)) * nscale
        d.normalize()
        pts.append(pts[-1] + d * seg)
    return pts

def bezier_pts(p0, p1, p2, p3, n):
    out = []
    for i in range(n + 1):
        t = i / n; u = 1 - t
        out.append(p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t))
    return out

def taper(n, r0, r1, power=1.0, collar=0.0):
    out = []
    for i in range(n):
        s = i / (n - 1)
        r = r0 + (r1 - r0) * (s ** power)
        if collar > 0 and i == 0:
            r *= (1 + collar)
        out.append(max(r, 0.006))
    return out

# --------------------------------------------------------------------------------------------- leaf blades & clumps
def blade(mb, base, axis, up, L, W, mat, flex, g0=0.35, g1=1.0, fold=0.2, curl=0.0, prof=((0.42, 1.0),),
          ctr=None, ballw=0.0, uvr=None, tag='leaf', droop=0.0, nup=None, split=0.0):
    """single-sided folded leaf / needle card. prof = ((t, widthfactor), ...) rows between base and tip.
       normal ~ up; if ctr given the vertex normals are blended with the ball direction (soft crown shading)."""
    g0_ = len(mb.V)
    if uvr is None:
        uvr = strip_uvr(base)
    a = axis.normalized()
    side = a.cross(up)
    if side.length < 1e-5:
        side = a.cross(ZUP) if abs(a.z) < 0.95 else a.cross(Vector((1, 0, 0)))
    side.normalize()
    upp = side.cross(a)
    npos = len(prof)
    def P(t, w, s):
        p = base + a * (L * t) + upp * (curl * L * t * t) + Vector((0, 0, -droop * L * t * t))
        return p + side * (s * w * W * 0.5) + upp * (fold * w * W * 0.5)
    def mkn(p):
        if ctr is None:
            return upp
        bn = (p - ctr)
        if bn.length < 1e-6: return upp
        bn.normalize()
        n = upp * (1 - ballw) + bn * ballw
        n.normalize(); return n
    u0, v0, u1, v1 = uvr
    def uv(u, v): return (u0 + (u1 - u0) * u, v0 + (v1 - v0) * v)
    ib = mb.v(base, flex, g0, 1.0, mkn(base))
    rows = []
    for k, (t, w) in enumerate(prof):
        gg = lerp(g0, g1, t)
        pl = P(t, w, 1); pr = P(t, w, -1)
        rows.append((mb.v(pl, flex, gg, 1.0, mkn(pl)), mb.v(pr, flex, gg, 1.0, mkn(pr)), t, w))
    tp = base + a * L + upp * (curl * L) + Vector((0, 0, -droop * L))
    l1, r1, t1, w1 = rows[0]
    mb.f((ib, l1, r1), mat, (uv(.5, 0), uv(.5 + w1 * .5, t1), uv(.5 - w1 * .5, t1)), tag)
    for k in range(npos - 1):
        la, ra, ta, wa = rows[k]; lb, rb, tb, wb = rows[k + 1]
        mb.f((la, lb, rb, ra), mat, (uv(.5 + wa * .5, ta), uv(.5 + wb * .5, tb), uv(.5 - wb * .5, tb), uv(.5 - wa * .5, ta)), tag)
    ll, rl, tl, wl = rows[-1]
    if split > 0.0:
        # forked tip (leaflet fringe): V notch between two points
        tn = 1.0 - 0.5 * split
        pn = P(tn, 0.0, 0)
        pL = tp + side * (wl * W * 0.5 * 0.8) + upp * (fold * wl * W * 0.5)
        pR = tp - side * (wl * W * 0.5 * 0.8) + upp * (fold * wl * W * 0.5)
        iN = mb.v(pn, flex, lerp(g0, g1, tn), 1.0, mkn(pn))
        iL = mb.v(pL, flex, g1, 1.0, mkn(pL)); iR = mb.v(pR, flex, g1, 1.0, mkn(pR))
        mb.f((ll, iL, iN), mat, (uv(.5 + wl * .5, tl), uv(.5 + .4, 1), uv(.5, tn)), tag)
        mb.f((iN, iR, rl), mat, (uv(.5, tn), uv(.5 - .4, 1), uv(.5 - wl * .5, tl)), tag)
        mb.f((ll, iN, rl), mat, (uv(.5 + wl * .5, tl), uv(.5, tn), uv(.5 - wl * .5, tl)), tag)
        mb.open_faces += 3 + 2 * (npos - 1) + 2
    else:
        it = mb.v(tp, flex, g1, 1.0, mkn(tp))
        mb.f((ll, it, rl), mat, (uv(.5 + wl * .5, tl), uv(.5, 1), uv(.5 - wl * .5, tl)), tag)
        mb.open_faces += 2 + 2 * (npos - 1)
    mb.groups.append((g0_, len(mb.V)))

_ICO = {}
def ico_unit(sub):
    if sub not in _ICO:
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
        vs = [v.co.copy() for v in bm.verts]
        idx = {v: i for i, v in enumerate(bm.verts)}
        fs = [tuple(idx[v] for v in f.verts) for f in bm.faces]
        bm.free()
        _ICO[sub] = (vs, fs)
    return _ICO[sub]

def blob(mb, c, radii, rng, mat, sub=2, jit=0.14, rot=None, flex=0.8, g=0.15, tag='core', nsc=1.1, seed=0.0,
         ctr=None, ballw=1.0, ghi=None, uvr=None):
    """closed lumpy ellipsoid ('leaf mass core' / ball normals). ghi = optional flutter at top"""
    vs, fs = ico_unit(sub)
    if uvr is None:
        uvr = strip_uvr(c)
    rot = rot if rot is not None else Matrix.Identity(3)
    ox, oy, oz = seed_off(seed)
    ids = []
    for u in vs:
        k = 1.0 + jit * (rng.uniform(-1, 1) * 0.5 + mn.noise(Vector((u.x * nsc + ox, u.y * nsc + oy, u.z * nsc + oz))))
        p = c + rot @ Vector((u.x * radii[0], u.y * radii[1], u.z * radii[2])) * k
        cc = ctr if ctr is not None else c
        nrm = (p - cc)
        nrm = nrm.normalized() if nrm.length > 1e-6 else Vector((0, 0, 1))
        ids.append(mb.v(p, flex, g, 1.0, nrm))
    for f in fs:
        a, b, cc_ = f
        mb.f((ids[a], ids[b], ids[cc_]), mat,
             tuple((uvr[0] + (uvr[2] - uvr[0]) * (0.5 + 0.5 * vs[i].x), uvr[1] + (uvr[3] - uvr[1]) * (0.5 + 0.5 * vs[i].z)) for i in f), tag)
    return ids

def clump(mb, c, R, rng, mat, flex=0.85, squash=(1.0, 1.0, 0.8), leaf=(0.35, 0.22), cover=1.0, core=0.72,
          core_sub=1, core_mat=None, up_bias=0.35, droop=0.15, ballw=0.6, shape=((0.42, 1.0),), fold=0.25, curl=-0.12,
          ctr=None, min_blades=6, max_blades=900, cut_below=None, seed=0.0, outward=0.6, uvr=None, tag='leaf',
          jitter=0.15, g_base=0.25, cull_in=0.5):
    """leaf clump = lumpy core (ball normals) + shell of folded leaf cards pointing outward."""
    rot = rand_rot(rng)
    c = Vector(c)
    if uvr is None:
        uvr = strip_uvr(c)
    ctrn = ctr if ctr is not None else c
    inw = None
    if ctr is not None and (ctr - c).length > R * 0.6:
        inw = (ctr - c).normalized()
        ctrn = c + (ctr - c) * 0.5          # normals: half clump-local lumps, half crown-radial
    sq = Vector(squash)
    if core > 0:
        blob(mb, c, (R * core * sq.x, R * core * sq.y, R * core * sq.z), rng, core_mat if core_mat is not None else mat, sub=core_sub,
             jit=0.18, rot=rot, flex=flex, g=0.12, seed=seed, ctr=ctrn, ballw=1.0, tag='core', uvr=uvr)
    area = 4 * math.pi * (R * (sq.x * sq.y * sq.z) ** (1 / 3)) ** 2
    nb = int(clamp(cover * area / (leaf[0] * leaf[1] * 0.5), min_blades, max_blades))
    dirs = fib_dirs(nb)
    for d0 in dirs:
        d = rot @ d0
        if cut_below is not None and d.z < cut_below:
            continue
        if inw is not None and d.dot(inw) > cull_in:
            continue
        pos = c + Vector((d.x * R * sq.x, d.y * R * sq.y, d.z * R * sq.z)) * rng.uniform(0.82, 1.02)
        nrm = Vector((d.x / sq.x, d.y / sq.y, d.z / sq.z)).normalized()
        ax = nrm * outward + vrand(rng, 0.7) + Vector((0, 0, -droop))
        if ax.length < 1e-4: ax = nrm
        ax.normalize()
        upv = (nrm + Vector((0, 0, up_bias))).normalized()
        L = leaf[0] * rng.uniform(1 - jitter, 1 + jitter * 1.4)
        W = leaf[1] * rng.uniform(1 - jitter, 1 + jitter)
        blade(mb, pos - nrm * (L * 0.12), ax, upv, L, W, mat, flex, g0=g_base, g1=1.0, fold=fold, curl=curl, prof=shape,
              ctr=ctrn, ballw=ballw, uvr=uvr, tag=tag)

# --------------------------------------------------------------------------------------------- ambient occlusion bake
def bake_ao(mb, rays=8, dist=3.2, strength=0.85, seed=11, floor=0.16, sample_cap=70000, tag_mul=None):
    """real ray-cast AO into the B channel of the vertex colours (no render settings touched)."""
    t0 = time.time()
    V = np.array(mb.V, dtype=np.float64)
    nv = len(V)
    fn = np.zeros((nv, 3))
    polys = []
    for f in mb.F:
        polys.append(f)
        # fan triangulate for the vertex-normal accumulation
        for k in range(1, len(f) - 1):
            a, b, c = V[f[0]], V[f[k]], V[f[k + 1]]
            n = np.cross(b - a, c - a)
            fn[f[0]] += n; fn[f[k]] += n; fn[f[k + 1]] += n
    ln = np.linalg.norm(fn, axis=1)
    ln[ln < 1e-12] = 1.0
    fn = fn / ln[:, None]
    verts = [Vector(v) for v in V]
    bvh = BVHTree.FromPolygons(verts, polys)
    rng = random.Random(seed)
    # one AO sample per leaf card (group of vertices), per-vertex for everything else
    gid = np.arange(nv)
    pos = V.copy()
    for (ga, gb) in mb.groups:
        gid[ga:gb] = ga
        pos[ga] = V[ga:gb].mean(axis=0)
        gn = fn[ga:gb].sum(axis=0)
        gl = np.linalg.norm(gn)
        fn[ga] = gn / gl if gl > 1e-9 else fn[ga]
    reps = np.unique(gid)
    base = []
    for k in range(rays):
        u1 = (k + 0.5) / rays; u2 = (k * 0.618034) % 1.0
        r = math.sqrt(u1); th = 2 * math.pi * u2
        base.append((r * math.cos(th), r * math.sin(th), math.sqrt(max(0.0, 1 - u1))))
    ao_r = np.ones(nv)
    for i in reps:
        n = Vector(fn[i])
        if n.length < 0.5:
            continue
        t = perp(n); b = n.cross(t)
        sp = rng.uniform(0, 6.283)
        cs, sn = math.cos(sp), math.sin(sp)
        o = Vector(pos[i]) + n * 0.03
        acc = 0.0
        for (x, y, z) in base:
            xx = x * cs - y * sn; yy = x * sn + y * cs
            d = t * xx + b * yy + n * z
            hit = bvh.ray_cast(o, d, dist)
            if hit[0] is not None:
                acc += 1.0 - (hit[3] / dist) * 0.6
        ao_r[i] = 1.0 - strength * acc / rays
    ao = ao_r[gid]
    # sky bonus for upward-facing vertices (long distance up ray handled by the sample set), then normalise
    hi = np.percentile(ao, 92)
    ao = np.clip(ao / max(hi, 0.2), floor, 1.0)
    if tag_mul:
        for tg, mul in tag_mul.items():
            vs = set()
            for f, t_ in zip(mb.F, mb.tag):
                if t_ == tg:
                    vs.update(f)
            for vi in vs:
                ao[vi] = max(floor, ao[vi] * mul)
    for i in range(nv):
        r, g, _ = mb.C[i]
        mb.C[i] = (r, g, float(ao[i]))
    return time.time() - t0

# --------------------------------------------------------------------------------------------- materials
MAT_DEFS = {
    # col = linear base colour; tint = noise ramp multipliers; cracks = (voronoi scale xy, z stretch, darkness) fissure pattern (bark kinds)
    'M_Tree_Bark':       dict(col=(0.078, 0.060, 0.048), rough=0.95, kind='bark',  tint=(0.70, 1.30), cracks=(6.0, 0.30, 0.55)),
    'M_Tree_Bark_Birch': dict(col=(0.76, 0.75, 0.70),    rough=0.82, kind='bark',  tint=(0.82, 1.08), cracks=None),
    'M_Tree_Bark_Dark':  dict(col=(0.026, 0.023, 0.021), rough=0.95, kind='bark',  tint=(0.7, 1.4),  cracks=(8.0, 0.40, 0.5)),
    'M_Tree_Leaf':       dict(col=(0.075, 0.190, 0.028), rough=0.70, kind='leaf', tint=(0.70, 1.35)),
    'M_Tree_LeafLight':  dict(col=(0.20, 0.36, 0.060), rough=0.70, kind='leaf',  tint=(0.75, 1.30)),
    'M_Tree_LeafDry':    dict(col=(0.30, 0.31, 0.150), rough=0.78, kind='leaf',  tint=(0.75, 1.25)),
    'M_Tree_Needle':     dict(col=(0.028, 0.090, 0.026), rough=0.65, kind='leaf', tint=(0.75, 1.40)),
    'M_Tree_Palm':       dict(col=(0.11, 0.27, 0.045), rough=0.55, kind='leaf',  tint=(0.80, 1.30)),
    'M_Tree_Dead':       dict(col=(0.30, 0.265, 0.225),  rough=0.92, kind='bark', tint=(0.55, 1.25), cracks=(5.0, 0.28, 0.45)),
}
MAT_VER = 9

def _new(nt, typ, x, y):
    n = nt.nodes.new(typ); n.location = (x, y); return n

def ensure_tree_materials():
    out = {}
    for name, d in MAT_DEFS.items():
        m = bpy.data.materials.get(name)
        if m is None:
            m = bpy.data.materials.new(name)
        out[name] = m
        c = d['col']
        m.diffuse_color = (min(1, c[0] * 1.2), min(1, c[1] * 1.2), min(1, c[2] * 1.2), 1.0)
        m.roughness = d['rough']
        try:
            if m.get('tree_ver') == MAT_VER and m.node_tree and len(m.node_tree.nodes) > 3:
                continue
        except Exception:
            pass
        try: m.use_nodes = True
        except Exception: pass
        nt = m.node_tree
        nt.nodes.clear()
        o = _new(nt, 'ShaderNodeOutputMaterial', 900, 0)
        bs = _new(nt, 'ShaderNodeBsdfPrincipled', 640, 0)
        nt.links.new(bs.outputs['BSDF'], o.inputs['Surface'])
        bs.inputs['Roughness'].default_value = d['rough']
        try: bs.inputs['Specular IOR Level'].default_value = 0.0 if d['kind'] == 'leaf' else 0.18
        except Exception: pass
        vc = _new(nt, 'ShaderNodeVertexColor', -600, 200)
        vc.layer_name = 'Col'
        sp = _new(nt, 'ShaderNodeSeparateColor', -400, 200)
        nt.links.new(vc.outputs['Color'], sp.inputs[0])
        ao = _new(nt, 'ShaderNodeMath', -200, 260); ao.operation = 'MULTIPLY_ADD'
        nt.links.new(sp.outputs[2], ao.inputs[0]); ao.inputs[1].default_value = 0.85; ao.inputs[2].default_value = 0.15
        tc = _new(nt, 'ShaderNodeTexCoord', -900, -100)
        noi = _new(nt, 'ShaderNodeTexNoise', -650, -100)
        noi.inputs['Scale'].default_value = 1.6 if d['kind'] == 'leaf' else 3.0
        nt.links.new(tc.outputs['Object'], noi.inputs['Vector'])
        ramp = _new(nt, 'ShaderNodeValToRGB', -420, -100)
        lo, hi = d['tint']
        ramp.color_ramp.elements[0].color = (c[0] * lo, c[1] * lo, c[2] * lo, 1)
        ramp.color_ramp.elements[1].color = (min(1, c[0] * hi), min(1, c[1] * hi), min(1, c[2] * hi), 1)
        nt.links.new(noi.outputs['Fac'], ramp.inputs['Fac'])
        mix = _new(nt, 'ShaderNodeMix', 300, 100)
        mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'
        mix.inputs[0].default_value = 1.0
        nt.links.new(ramp.outputs['Color'], mix.inputs[6])
        # AO factor -> grey colour
        ao_c = _new(nt, 'ShaderNodeCombineColor', 100, 260)
        for k in range(3): nt.links.new(ao.outputs[0], ao_c.inputs[k])
        nt.links.new(ao_c.outputs[0], mix.inputs[7])
        last = mix.outputs[2]
        if d['kind'] == 'leaf':
            # per-clump tint variant: leaf cards of one clump share a U strip (4 strips) -> constant colour ramp
            uvn = _new(nt, 'ShaderNodeUVMap', -900, -300)
            sx = _new(nt, 'ShaderNodeSeparateXYZ', -700, -300)
            nt.links.new(uvn.outputs['UV'], sx.inputs[0])
            rp = _new(nt, 'ShaderNodeValToRGB', -500, -300)
            rp.color_ramp.interpolation = 'CONSTANT'
            els = rp.color_ramp.elements
            els[0].position = 0.0; els[0].color = (1.0, 1.0, 1.0, 1)
            els[1].position = 0.25; els[1].color = (0.93, 1.0, 0.78, 1)
            e2 = els.new(0.5); e2.color = (0.80, 0.92, 0.84, 1)
            e3 = els.new(0.75); e3.color = (0.90, 0.96, 0.68, 1)
            nt.links.new(sx.outputs['X'], rp.inputs['Fac'])
            mixu = _new(nt, 'ShaderNodeMix', 400, 300); mixu.data_type = 'RGBA'; mixu.blend_type = 'MULTIPLY'
            mixu.inputs[0].default_value = 1.0
            nt.links.new(mix.outputs[2], mixu.inputs[6]); nt.links.new(rp.outputs['Color'], mixu.inputs[7])
            mix = mixu
            # tips (G flutter) slightly brighter / yellower
            gm = _new(nt, 'ShaderNodeMath', 100, 20); gm.operation = 'MULTIPLY_ADD'
            nt.links.new(sp.outputs[1], gm.inputs[0]); gm.inputs[1].default_value = 0.35; gm.inputs[2].default_value = 0.82
            gc = _new(nt, 'ShaderNodeCombineColor', 250, 20)
            for k in range(3): nt.links.new(gm.outputs[0], gc.inputs[k])
            mix2 = _new(nt, 'ShaderNodeMix', 470, 100); mix2.data_type = 'RGBA'; mix2.blend_type = 'MULTIPLY'
            mix2.inputs[0].default_value = 1.0
            nt.links.new(mix.outputs[2], mix2.inputs[6]); nt.links.new(gc.outputs[0], mix2.inputs[7])
            last = mix2.outputs[2]
        crk = d.get('cracks')
        if d['kind'] == 'bark' and crk:
            # vertical fissure pattern: stretched voronoi distance-to-edge -> dark cracks (preview only; UE supplies bark textures)
            mp = _new(nt, 'ShaderNodeMapping', -900, -560)
            try:
                mp.inputs['Scale'].default_value = (crk[0], crk[0], crk[1])
            except Exception: pass
            nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
            vr = _new(nt, 'ShaderNodeTexVoronoi', -700, -560)
            try: vr.feature = 'DISTANCE_TO_EDGE'
            except Exception: pass
            nt.links.new(mp.outputs['Vector'], vr.inputs['Vector'])
            cr = _new(nt, 'ShaderNodeValToRGB', -480, -560)
            cr.color_ramp.elements[0].position = 0.0; cr.color_ramp.elements[0].color = (1 - crk[2], 1 - crk[2], 1 - crk[2], 1)
            cr.color_ramp.elements[1].position = 0.12; cr.color_ramp.elements[1].color = (1, 1, 1, 1)
            try: nt.links.new(vr.outputs['Distance'], cr.inputs['Fac'])
            except Exception: nt.links.new(vr.outputs[0], cr.inputs['Fac'])
            mixc = _new(nt, 'ShaderNodeMix', 520, 100); mixc.data_type = 'RGBA'; mixc.blend_type = 'MULTIPLY'
            mixc.inputs[0].default_value = 1.0
            nt.links.new(last, mixc.inputs[6]); nt.links.new(cr.outputs['Color'], mixc.inputs[7])
            last = mixc.outputs[2]
        nt.links.new(last, bs.inputs['Base Color'])
        if d['kind'] == 'bark':
            nb = _new(nt, 'ShaderNodeTexNoise', -650, -400)
            nb.inputs['Scale'].default_value = 14.0; nb.inputs['Detail'].default_value = 6.0
            nt.links.new(tc.outputs['Object'], nb.inputs['Vector'])
            bump = _new(nt, 'ShaderNodeBump', 300, -300)
            bump.inputs['Strength'].default_value = 0.45
            if crk:
                hm = _new(nt, 'ShaderNodeMath', -200, -420); hm.operation = 'MULTIPLY'
                nt.links.new(nb.outputs['Fac'], hm.inputs[0]); nt.links.new(cr.outputs['Color'], hm.inputs[1])
                nt.links.new(hm.outputs[0], bump.inputs['Height'])
            else:
                nt.links.new(nb.outputs['Fac'], bump.inputs['Height'])
            nt.links.new(bump.outputs['Normal'], bs.inputs['Normal'])
        m['tree_ver'] = MAT_VER
    return out

# --------------------------------------------------------------------------------------------- collections / objects
def get_trees_collection():
    fz = bpy.data.collections.get('FORZA_UE')
    if fz is None:
        fz = bpy.data.collections.new('FORZA_UE')
        bpy.context.scene.collection.children.link(fz)
    nat = bpy.data.collections.get('Nature')
    if nat is None:
        nat = bpy.data.collections.new('Nature'); fz.children.link(nat)
    elif nat.name not in [c.name for c in fz.children]:
        fz.children.link(nat)
    col = bpy.data.collections.get('Trees')
    if col is None:
        col = bpy.data.collections.new('Trees')
    if col.name not in [c.name for c in nat.children]:
        nat.children.link(col)
    return col

def remove_asset(aid):
    """remove ONLY this asset's objects (id, UCX_id_NN, id_Far) and their mesh data"""
    for o in list(bpy.data.objects):
        n = o.name
        if n == aid or n == aid + '_Far' or (n.startswith('UCX_' + aid + '_') and n[len('UCX_' + aid + '_'):].isdigit()):
            me = o.data if o.type == 'MESH' else None
            bpy.data.objects.remove(o, do_unlink=True)
            if me is not None and me.users == 0:
                bpy.data.meshes.remove(me)

def mb_to_mesh(mb, name, mats):
    V = np.array(mb.V, dtype=np.float32)
    me = bpy.data.meshes.new(name)
    me.from_pydata(V.tolist(), [], mb.F)
    me.update(calc_edges=True)
    for mn_ in mb.mats:
        me.materials.append(mats[mn_])
    me.polygons.foreach_set('material_index', np.array(mb.FM, dtype=np.int32))
    uvl = me.uv_layers.new(name='UVMap')
    uvs = np.array([uv for f in mb.UV for uv in f], dtype=np.float32).ravel()
    uvl.data.foreach_set('uv', uvs)
    lv = np.empty(len(me.loops), dtype=np.int32)
    me.loops.foreach_get('vertex_index', lv)
    C = np.array(mb.C, dtype=np.float32)
    rgba = np.ones((len(lv), 4), dtype=np.float32)
    rgba[:, :3] = C[lv]
    ca = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
    ca.data.foreach_set('color', rgba.ravel())
    try: me.color_attributes.active_color = ca
    except Exception: pass
    me.shade_smooth()
    # custom (ball) normals: auto normals for vertices without an override
    vn = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertex_normals.foreach_get('vector', vn)
    vn = vn.reshape(-1, 3)
    for i, n in enumerate(mb.N):
        if n is not None:
            vn[i] = n
    me.normals_split_custom_set_from_vertices(vn.tolist())
    me.update()
    return me

def make_object(aid, me, col, x, y):
    o = bpy.data.objects.new(aid, me)
    col.objects.link(o)
    o.location = (x, y, 0.0)
    return o

# --------------------------------------------------------------------------------------------- collision
def make_ucx(aid, parent, hulls, col, sides=8):
    """hulls = list of lists[(centre Vector (local), radius)] - each list becomes one convex hull (<=32 verts)"""
    names = []
    for k, rings in enumerate(hulls, 1):
        bm = bmesh.new()
        for (c, r) in rings:
            for j in range(sides):
                th = 2 * math.pi * (j + 0.5) / sides
                bm.verts.new(Vector((c.x + math.cos(th) * r, c.y + math.sin(th) * r, c.z)))
        bm.verts.ensure_lookup_table()
        res = bmesh.ops.convex_hull(bm, input=bm.verts[:], use_existing_faces=False)
        dead = [g for g in set(res['geom_interior'] + res['geom_unused']) if isinstance(g, bmesh.types.BMVert)]
        if dead:
            bmesh.ops.delete(bm, geom=dead, context='VERTS')
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        name = 'UCX_%s_%02d' % (aid, k)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me); bm.free()
        o = bpy.data.objects.new(name, me)
        col.objects.link(o)
        o.parent = parent
        o.location = (0, 0, 0)
        o.display_type = 'WIRE'
        o.hide_render = True
        names.append(name)
    return names

# --------------------------------------------------------------------------------------------- png writer / far card raster
def write_png(path, rgba):
    h, w, _ = rgba.shape
    raw = b''.join(b'\x00' + rgba[y].astype(np.uint8).tobytes() for y in range(h - 1, -1, -1))
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b'')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(png)

def raster_view(mb, mat_cols, axis, x0, x1, z0, z1, W, H, light=(0.4, -0.5, 0.75)):
    """vectorised orthographic software raster (barycentric point splatting + depth sort) into a W x H canvas that
       maps exactly x0..x1 (horizontal) and z0..z1 (vertical) -> power-of-two canvases give POT textures.
       axis 'Y': looks along +Y (screen x = world X); axis 'X': looks along -X (screen x = world Y)."""
    ppx = W / (x1 - x0); ppy = H / (z1 - z0); ppm = 0.5 * (ppx + ppy)
    V = np.array(mb.V, dtype=np.float64)
    tri = []; tmat = []
    for fi, f in enumerate(mb.F):
        m = mb.FM[fi]
        for k in range(1, len(f) - 1):
            tri.append((f[0], f[k], f[k + 1])); tmat.append(m)
    tri = np.array(tri, dtype=np.int64); tmat = np.array(tmat, dtype=np.int64)
    A = V[tri[:, 0]]; B = V[tri[:, 1]]; C = V[tri[:, 2]]
    n = np.cross(B - A, C - A); nl = np.linalg.norm(n, axis=1); ok = nl > 1e-12
    n = n / np.where(ok, nl, 1.0)[:, None]
    L = np.array(light, dtype=np.float64); L /= np.linalg.norm(L)
    shade = 0.45 + 0.55 * np.abs(n @ L)
    Cb = np.array([c[2] for c in mb.C], dtype=np.float64)
    ao = (Cb[tri[:, 0]] + Cb[tri[:, 1]] + Cb[tri[:, 2]]) / 3.0
    matc = np.array([mat_cols[nm] for nm in mb.mats], dtype=np.float64)
    rgb = matc[tmat] * (shade * (0.45 + 0.55 * ao))[:, None]
    if axis == 'Y':
        sx = (V[:, 0] - x0) * ppx; dd = V[:, 1]
    else:
        sx = (V[:, 1] - x0) * ppx; dd = -V[:, 0]
    sy = (V[:, 2] - z0) * ppy
    P0 = np.stack([sx[tri[:, 0]], sy[tri[:, 0]]], 1); P1 = np.stack([sx[tri[:, 1]], sy[tri[:, 1]]], 1); P2 = np.stack([sx[tri[:, 2]], sy[tri[:, 2]]], 1)
    D = (dd[tri[:, 0]] + dd[tri[:, 1]] + dd[tri[:, 2]]) / 3.0
    area = 0.5 * np.abs((P1[:, 0] - P0[:, 0]) * (P2[:, 1] - P0[:, 1]) - (P2[:, 0] - P0[:, 0]) * (P1[:, 1] - P0[:, 1]))
    K = np.clip(np.ceil(np.sqrt(area) * 1.7), 1, 40).astype(np.int64)
    xs_all = []; ys_all = []; d_all = []; c_all = []
    for k in np.unique(K[ok]):
        sel = np.where((K == k) & ok)[0]
        if len(sel) == 0: continue
        # barycentric lattice with (k+1)(k+2)/2 samples
        bw = []
        for i in range(k + 1):
            for j in range(k + 1 - i):
                bw.append((i / k, j / k, 1 - i / k - j / k))
        bw = np.array(bw)                                   # (S,3)
        px = (P0[sel][:, None, 0] * bw[None, :, 0] + P1[sel][:, None, 0] * bw[None, :, 1] + P2[sel][:, None, 0] * bw[None, :, 2])
        py = (P0[sel][:, None, 1] * bw[None, :, 0] + P1[sel][:, None, 1] * bw[None, :, 1] + P2[sel][:, None, 1] * bw[None, :, 2])
        S = bw.shape[0]
        xs_all.append(px.ravel()); ys_all.append(py.ravel())
        d_all.append(np.repeat(D[sel], S)); c_all.append(np.repeat(rgb[sel], S, axis=0))
    xs = np.concatenate(xs_all); ys = np.concatenate(ys_all); ds = np.concatenate(d_all); cs = np.concatenate(c_all)
    ix = np.floor(xs).astype(np.int64); iy = np.floor(ys).astype(np.int64)
    m = (ix >= 0) & (ix < W) & (iy >= 0) & (iy < H)
    ix = ix[m]; iy = iy[m]; ds = ds[m]; cs = cs[m]
    order = np.argsort(-ds, kind='stable')                  # far first, near last (last write wins)
    ix = ix[order]; iy = iy[order]; cs = cs[order]
    col = np.zeros((H, W, 4), dtype=np.float32)
    col[iy, ix, :3] = cs
    col[iy, ix, 3] = 1.0
    # slight dilation so thin foliage reads as a masked mass, colours bled from neighbours
    a = col[:, :, 3]
    cnt = np.zeros((H, W), dtype=np.float32); acc = np.zeros((H, W, 3), dtype=np.float32)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ys_ = slice(max(dy, 0), H + min(dy, 0)); xs_ = slice(max(dx, 0), W + min(dx, 0))
        yd = slice(max(-dy, 0), H + min(-dy, 0)); xd = slice(max(-dx, 0), W + min(-dx, 0))
        cnt[ys_, xs_] += a[yd, xd]; acc[ys_, xs_] += col[yd, xd, :3] * a[yd, xd][:, :, None]
    fill = (a == 0) & (cnt >= 2)
    col[fill, :3] = (acc / np.maximum(cnt, 1)[:, :, None])[fill]
    col[fill, 3] = 1.0
    # edge bleed: transparent texels next to opaque ones keep the neighbour colour (no dark halo when mip-mapped / alpha-clipped)
    a2 = col[:, :, 3]
    cnt = np.zeros((H, W), dtype=np.float32); acc = np.zeros((H, W, 3), dtype=np.float32)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
        ys_ = slice(max(dy, 0), H + min(dy, 0)); xs_ = slice(max(dx, 0), W + min(dx, 0))
        yd = slice(max(-dy, 0), H + min(-dy, 0)); xd = slice(max(-dx, 0), W + min(-dx, 0))
        cnt[ys_, xs_] += a2[yd, xd]; acc[ys_, xs_] += col[yd, xd, :3] * a2[yd, xd][:, :, None]
    bleed = (a2 == 0) & (cnt > 0)
    col[bleed, :3] = (acc / np.maximum(cnt, 1)[:, :, None])[bleed]
    return col

def _pot(v, lo=64, hi=1024):
    p = lo
    while p < v and p < hi:
        p *= 2
    return p

def make_far(aid, mb, mats_defs, col, x, y, width, height, ppm=None, write_tex=True):
    """two crossed vertical quads <aid>_Far + baked colour/alpha texture T_<aid>_Far.png (view along Y | view along X).
       The atlas is power-of-two (each view canvas POT: width_px x height_px, atlas = 2*width_px x height_px) so UE mips / streams it."""
    ppm_t = ppm or clamp(420.0 / max(height, 1.0), 12.0, 26.0)       # target texel density (px / m)
    mat_cols = {k: tuple(min(1.0, (v ** (1 / 2.2)) * 1.0) for v in mats_defs[k]['col']) for k in mb.mats}
    hw = width * 0.5
    zlo, zhi = -0.1, height + 0.05
    Wp = _pot(width * ppm_t, 64, 512)
    Hp = _pot((zhi - zlo) * ppm_t, 128, 1024)
    imgs = [raster_view(mb, mat_cols, axis, -hw, hw, zlo, zhi, Wp, Hp) for axis in ('Y', 'X')]
    atlas = np.zeros((Hp, Wp * 2, 4), dtype=np.float32)
    atlas[:, :Wp] = imgs[0]
    atlas[:, Wp:] = imgs[1]
    out = (np.clip(atlas, 0, 1) * 255).astype(np.uint8)
    texpath = os.path.join(EXPORT_DIR, 'Textures', 'T_%s_Far.png' % aid)
    if write_tex:
        write_png(texpath, out)
    fm = MB()
    mname = 'M_Tree_Far_' + aid
    mi = fm.mi(mname)
    # quad A in the XZ plane (atlas u 0..0.5), quad B in the YZ plane (u 0.5..1)
    q = [[(-hw, 0, zlo), (hw, 0, zlo), (hw, 0, zhi), (-hw, 0, zhi)],
         [(0, -hw, zlo), (0, hw, zlo), (0, hw, zhi), (0, -hw, zhi)]]
    for k, qd in enumerate(q):
        u0 = 0.0 if k == 0 else 0.5
        u1 = 0.5 if k == 0 else 1.0
        ids = [fm.v(Vector(p), 0.0, 0.0, 1.0, Vector((0, -1, 0)) if k == 0 else Vector((1, 0, 0))) for p in qd]
        fm.f(ids, mi, ((u0, 0), (u1, 0), (u1, 1), (u0, 1)), 'far')
    mat = bpy.data.materials.get(mname) or bpy.data.materials.new(mname)
    _setup_far_material(mat, texpath, 'T_%s_Far' % aid)
    me = mb_to_mesh(fm, aid + '_Far', {mname: mat})
    o = bpy.data.objects.new(aid + '_Far', me)
    col.objects.link(o)
    o.location = (x, y, 0.0)
    return o, texpath, (width, height)

def _setup_far_material(mat, texpath, imgname):
    mat.diffuse_color = (0.2, 0.3, 0.1, 1)
    try: mat.use_nodes = True
    except Exception: pass
    nt = mat.node_tree
    nt.nodes.clear()
    o = _new(nt, 'ShaderNodeOutputMaterial', 600, 0)
    bs = _new(nt, 'ShaderNodeBsdfPrincipled', 300, 0)
    bs.inputs['Roughness'].default_value = 0.7
    nt.links.new(bs.outputs['BSDF'], o.inputs['Surface'])
    img = bpy.data.images.get(imgname)
    if img is not None and os.path.exists(texpath):
        img.filepath = texpath
        img.reload()
    elif os.path.exists(texpath):
        img = bpy.data.images.load(texpath, check_existing=True)
        img.name = imgname
    if img is not None:
        tx = _new(nt, 'ShaderNodeTexImage', 0, 0)
        tx.image = img
        tx.interpolation = 'Linear'
        nt.links.new(tx.outputs['Color'], bs.inputs['Base Color'])
        nt.links.new(tx.outputs['Alpha'], bs.inputs['Alpha'])
    try: mat.blend_method = 'HASHED'
    except Exception: pass
    try: mat.surface_render_method = 'DITHERED'
    except Exception: pass

# --------------------------------------------------------------------------------------------- stats / validation
def mesh_stats(obj):
    me = obj.data
    bm = bmesh.new(); bm.from_mesh(me)
    tris = sum(len(f.verts) - 2 for f in bm.faces)
    nm = 0; boundary = 0
    for e in bm.edges:
        lf = len(e.link_faces)
        if lf > 2: nm += 1
        elif lf == 1: boundary += 1
    loose = sum(1 for v in bm.verts if not v.link_edges)
    bm.free()
    co = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    mn_ = co.min(axis=0); mx_ = co.max(axis=0)
    return dict(tris=tris, verts=len(me.vertices), faces=len(me.polygons), nonmanifold_edges=nm, boundary_edges=boundary, loose_verts=loose,
                bbox_min=tuple(round(float(x), 3) for x in mn_), bbox_max=tuple(round(float(x), 3) for x in mx_))

def outward_ratio(mb, tags=('wood', 'core')):
    """fraction of closed-piece faces whose normal points away from the centroid of their piece (sanity check on winding)"""
    ok = tot = 0
    V = mb.V
    for fi, f in enumerate(mb.F):
        if mb.tag[fi] not in tags or len(f) < 3: continue
        p = [Vector(V[i]) for i in f[:3]]
        n = (p[1] - p[0]).cross(p[2] - p[0])
        c = (p[0] + p[1] + p[2]) / 3
        # reference = nearest point of the face's own piece is unknown; use vertex normal custom (ball) when available else skip
        nn = mb.N[f[0]]
        if nn is None: continue
        tot += 1
        if n.dot(Vector(nn)) > 0: ok += 1
    return (ok, tot)
