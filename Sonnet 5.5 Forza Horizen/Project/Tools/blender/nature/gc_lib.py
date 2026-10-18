"""
gc_lib.py - geometry core for the GROUND COVER kit (Blender 5.2, shared MCP Blender).
Exec'd into the namespace of ground_cover.py. Pure python mesh builder (MB) -> bpy mesh, materials, hulls, validation, export.
Conventions: 1 BU = 1 m, +Z up, +X = front, origin = base centre on the ground. Vertex colour 'Col': R = flex, G = flutter, B = AO, A = per-element random.
"""
import bpy, bmesh, math, random, os, json, time, io, contextlib
import numpy as np
from mathutils import Vector, Matrix, noise

PROJECT = r"W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza"
EXPORT_DIR = os.path.join(PROJECT, 'Exports', 'Nature', 'Cover')
FBX_LIB = os.path.join(PROJECT, 'Tools', 'blender', 'lib', 'fbx_export.py')
STAGE_Y = 60.0
STAGE_X0 = 1200.0
TAU = math.tau
Z = Vector((0, 0, 1))

def clamp(x, a=0.0, b=1.0): return a if x < a else (b if x > b else x)
def lerp(a, b, t): return a + (b - a) * t
def sstep(a, b, x):
    if a == b: return 0.0
    t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t)

def nz(p, seed=0.0, f=1.0):
    return noise.noise(Vector((p[0] * f + seed * 13.37, p[1] * f + seed * 7.11, p[2] * f + seed * 3.91)))
def fbm(p, seed=0.0, f=1.0, octs=4, H=0.6):
    return noise.fractal(Vector((p[0] * f + seed * 13.37, p[1] * f + seed * 7.11, p[2] * f + seed * 3.91)), H, 2.0, octs)
def ridged(p, seed=0.0, f=1.0, octs=4):
    return noise.ridged_multi_fractal(Vector((p[0] * f + seed * 13.37, p[1] * f + seed * 7.11, p[2] * f + seed * 3.91)), 1.0, 2.0, octs, 1.0, 1.0)

def rand_unit(rng):
    while True:
        v = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        l = v.length
        if 0.05 < l <= 1.0: return v / l

def fib_dirs(n):
    out = []
    ga = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        z = 1 - 2 * (i + 0.5) / n; r = math.sqrt(max(0, 1 - z * z)); a = ga * i
        out.append((r * math.cos(a), r * math.sin(a), z))
    return out

def rot_z(deg): return Matrix.Rotation(math.radians(deg), 3, 'Z')
def rot_euler(rx, ry, rz): return Matrix.Rotation(math.radians(rz), 3, 'Z') @ Matrix.Rotation(math.radians(ry), 3, 'Y') @ Matrix.Rotation(math.radians(rx), 3, 'X')

# ----------------------------------------------------------------------------------------------- mesh builder
def box_uv(P, s=0.5):
    a, b, c = Vector(P[0]), Vector(P[1]), Vector(P[2])
    n = (b - a).cross(c - a)
    ax = max(range(3), key=lambda i: abs(n[i]))
    out = []
    for p in P:
        if ax == 2: out.append((p[0] * s, p[1] * s))
        elif ax == 1: out.append((p[0] * s, p[2] * s))
        else: out.append((p[1] * s, p[2] * s))
    return out

class MB:
    def __init__(self):
        self.V = []; self.C = []; self.G = []; self.F = []; self.FM = []; self.UV = []; self.SM = []; self.mats = []; self.grp = 0
    def mi(self, name):
        if name not in self.mats: self.mats.append(name)
        return self.mats.index(name)
    def v(self, p, c=(0.0, 0.0, 1.0, 0.5)):
        self.V.append((float(p[0]), float(p[1]), float(p[2]))); self.C.append(tuple(c)); self.G.append(self.grp)
        return len(self.V) - 1
    def f(self, idx, mat, uv=None, smooth=True, uvs=0.5):
        idx = list(idx)
        keep = [k for k in range(len(idx)) if idx[k] != idx[k - 1]]       # drop consecutive duplicate indices (welded edges)
        if len(keep) != len(idx):
            idx = [idx[k] for k in keep]
            if uv is not None: uv = [uv[k] for k in keep]
            if len(idx) < 3 or len(set(idx)) != len(idx): return
        self.F.append(idx); self.FM.append(self.mi(mat) if isinstance(mat, str) else mat); self.SM.append(bool(smooth))
        if uv is None: uv = box_uv([self.V[i] for i in idx], uvs)
        self.UV.append(uv)
    def tris(self): return sum(len(f) - 2 for f in self.F)
    def ground(self, sink=0.0):
        zmin = min(v[2] for v in self.V)
        self.V = [(x, y, z - zmin - sink) for (x, y, z) in self.V]
    def bounds(self):
        a = np.array(self.V); return a.min(0), a.max(0)

_ICO = {}
def ico(sub):
    if sub not in _ICO:
        bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=sub + 1, radius=1.0)   # sub 1=80 tris, 2=320, 3=1280, 4=5120
        bm.verts.index_update(); bm.faces.ensure_lookup_table()
        V = [tuple(v.co) for v in bm.verts]; F = [[v.index for v in f.verts] for f in bm.faces]; bm.free()
        _ICO[sub] = (V, F)
    return _ICO[sub]

def radial_blob(mb, rfun, sub=3, scale=(1, 1, 1), rot=None, spin=None, offset=(0, 0, 0), mat='M_Rock', smooth=True, zfloor=None, aoz=True, matfn=None, uvs=0.5):
    """sphere of directions -> radius function. returns (first vertex, count). zfloor = flat base clamp (in final coordinates)."""
    V, F = ico(sub)
    pts = []
    for d in V:
        dv = Vector(d)
        if spin is not None: dv = spin @ dv
        r = rfun(dv)
        p = Vector((dv.x * scale[0], dv.y * scale[1], dv.z * scale[2])) * r
        if rot is not None: p = rot @ p
        p = p + Vector(offset)
        if zfloor is not None and p.z < zfloor: p.z = zfloor
        pts.append(p)
    zs = [p.z for p in pts]; z0, z1 = min(zs), max(zs)
    base = len(mb.V)
    for p in pts:
        t = (p.z - z0) / max(1e-6, z1 - z0)
        ao = 0.42 + 0.58 * (t ** 0.6) if aoz else 1.0
        mb.v(p, (0.0, 0.0, ao, 0.5))
    for f in F:
        idx = [base + i for i in f]
        m = mat
        if matfn is not None:
            m = matfn(sum((Vector(mb.V[i]) for i in idx), Vector()) / 3.0)
        mb.f(idx, m, smooth=smooth, uvs=uvs)
    return base, len(V)

def frames_along(pts):
    n = len(pts); T = []
    for i in range(n):
        a = pts[max(0, i - 1)]; b = pts[min(n - 1, i + 1)]
        t = (b - a)
        if t.length < 1e-9: t = Vector((0, 0, 1))
        T.append(t.normalized())
    N0 = T[0].cross(Vector((1, 0, 0)))
    if N0.length < 0.2: N0 = T[0].cross(Vector((0, 1, 0)))
    N = [N0.normalized()]
    for i in range(1, n):
        v = N[-1] - T[i] * N[-1].dot(T[i])
        if v.length < 1e-6: v = T[i].cross(Vector((1, 0, 0)))
        N.append(v.normalized())
    B = [T[i].cross(N[i]) for i in range(n)]
    return T, N, B

def tube(mb, pts, radii, sides, mat, rib=None, col=None, uvv=0.5, caps=(True, True), cap_dz=(0.0, 0.0), smooth=True, mat_end=None, twist=0.0, ring_mat=None, flip=False):
    """swept tube; rib(k, t) multiplies radius per ring vertex; col(t, k) -> (r,g,b,a). returns ring positions + normals for decorations."""
    pts = [Vector(p) for p in pts]; n = len(pts)
    T, N, B = frames_along(pts)
    rings = []; rnorm = []
    length = 0.0; vcoord = [0.0]
    for i in range(1, n):
        length += (pts[i] - pts[i - 1]).length; vcoord.append(length)
    for i in range(n):
        t = i / max(1, n - 1)
        ring = []; rn = []; idx = []
        for k in range(sides):
            th = TAU * k / sides + twist * t
            m = rib(k, t) if rib else 1.0
            nv = N[i] * math.cos(th) + B[i] * math.sin(th)
            p = pts[i] + nv * (radii[i] * m)
            c = col(t, k) if col else (t, t * t, 0.6 + 0.4 * t, 0.5)
            idx.append(mb.v(p, c)); ring.append(p); rn.append(nv)
        rings.append(idx); rnorm.append(rn)
    m_side = mat
    for i in range(n - 1):
        mm = ring_mat(i) if ring_mat else m_side
        for k in range(sides):
            k2 = (k + 1) % sides
            a, b, c, d = rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]
            uv = [(k / sides, vcoord[i] * uvv), ((k + 1) / sides, vcoord[i] * uvv), ((k + 1) / sides, vcoord[i + 1] * uvv), (k / sides, vcoord[i + 1] * uvv)]
            if flip: mb.f([d, c, b, a], mm, uv=uv[::-1], smooth=smooth)
            else: mb.f([a, b, c, d], mm, uv=uv, smooth=smooth)
    me_ = mat_end or mat
    if caps[0]:
        cen = mb.v(pts[0] - T[0] * cap_dz[0], col(0.0, 0) if col else (0, 0, 0.6, 0.5))
        for k in range(sides):
            k2 = (k + 1) % sides
            mb.f([cen, rings[0][k2], rings[0][k]], me_, uv=[(0.5, 0.5), (0.5 + 0.5 * math.cos(TAU * (k + 1) / sides), 0.5 + 0.5 * math.sin(TAU * (k + 1) / sides)), (0.5 + 0.5 * math.cos(TAU * k / sides), 0.5 + 0.5 * math.sin(TAU * k / sides))], smooth=smooth)
    if caps[1]:
        cen = mb.v(pts[-1] + T[-1] * cap_dz[1], col(1.0, 0) if col else (1, 1, 0.9, 0.5))
        for k in range(sides):
            k2 = (k + 1) % sides
            mb.f([cen, rings[-1][k], rings[-1][k2]], me_, uv=[(0.5, 0.5), (0.5 + 0.5 * math.cos(TAU * k / sides), 0.5 + 0.5 * math.sin(TAU * k / sides)), (0.5 + 0.5 * math.cos(TAU * (k + 1) / sides), 0.5 + 0.5 * math.sin(TAU * (k + 1) / sides))], smooth=smooth)
    return dict(rings=rings, pos=[[mb.V[i] for i in r] for r in rings], norm=rnorm, T=T, N=N, B=B, pts=pts)

def bez(p0, p1, p2, p3, n):
    out = []
    for i in range(n + 1):
        t = i / n; u = 1 - t
        out.append(u * u * u * Vector(p0) + 3 * u * u * t * Vector(p1) + 3 * u * t * t * Vector(p2) + t * t * t * Vector(p3))
    return out

def leaf(mb, base, a, nrm, L, W, mat, fold=0.2, droop=0.25, rnd=0.5, flex=0.5, ao=0.8, diamond=False, tipg=1.0):
    """pointed leaf: axis a (base->tip), normal nrm (upper face). 5 verts / 4 tris (or 4 verts / 2 tris diamond)."""
    a = Vector(a).normalized(); nrm = Vector(nrm)
    nrm = (nrm - a * nrm.dot(a))
    if nrm.length < 1e-4: nrm = a.cross(Vector((0.3, 0.7, 0.2)))
    nrm.normalize()
    w = a.cross(nrm)
    base = Vector(base)
    c = base + a * (0.42 * L)
    pl = c - w * (W * 0.5) + nrm * (fold * W * 0.5)
    pr = c + w * (W * 0.5) + nrm * (fold * W * 0.5)
    pt = base + a * L - nrm * (droop * L * 0.3)
    cb = (flex * 0.55, 0.15, ao * 0.85, rnd); cm = (flex * 0.8, 0.55, ao, rnd); ct = (flex, tipg, ao, rnd)
    i0 = mb.v(base, cb)
    il = mb.v(pl, cm); ir = mb.v(pr, cm); it = mb.v(pt, ct)
    if diamond:
        mb.f([i0, ir, it, il], mat, uv=[(0.5, 0), (1, 0.42), (0.5, 1), (0, 0.42)])
    else:
        im = mb.v(c + nrm * (fold * W * 0.05), (flex * 0.8, 0.5, ao, rnd))
        mb.f([i0, ir, im], mat, uv=[(0.5, 0), (1, 0.42), (0.5, 0.42)])
        mb.f([i0, im, il], mat, uv=[(0.5, 0), (0.5, 0.42), (0, 0.42)])
        mb.f([il, im, it], mat, uv=[(0, 0.42), (0.5, 0.42), (0.5, 1)])
        mb.f([im, ir, it], mat, uv=[(0.5, 0.42), (1, 0.42), (0.5, 1)])

def blade(mb, base, phi, L, W, mat, seg=3, tilt0=0.15, curl=0.6, rnd=0.5, ao0=0.35, flex=1.0, taper=0.6, tipw=0.0, twist=0.0):
    """grass blade strip, leaning toward azimuth phi, tilt from vertical = tilt0 + curl*t^1.3 (radians)."""
    base = Vector(base)
    h = Vector((math.cos(phi), math.sin(phi), 0)); wd0 = Vector((math.sin(phi), -math.cos(phi), 0))
    p = base.copy(); pts = [p.copy()]
    for i in range(1, seg + 1):
        t = i / seg; th = tilt0 + curl * (t ** 1.3)
        p = p + Vector((h.x * math.sin(th), h.y * math.sin(th), math.cos(th))) * (L / seg); pts.append(p.copy())
    rows = []
    for i in range(seg):
        t = i / seg
        w = W * (1.0 - taper * (t ** 1.5))
        wd = wd0 * math.cos(twist * t) + Z * math.sin(twist * t)
        c = (flex * (t ** 1.2), t * t, ao0 + (1 - ao0) * t, rnd)
        rows.append((mb.v(pts[i] - wd * (w * 0.5), c), mb.v(pts[i] + wd * (w * 0.5), c)))
    tip = mb.v(pts[seg], (flex, 1.0, 1.0, rnd))
    for i in range(seg - 1):
        t0 = i / seg; t1 = (i + 1) / seg
        mb.f([rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]], mat, uv=[(0, t0), (1, t0), (1, t1), (0, t1)])
    t0 = (seg - 1) / seg
    mb.f([rows[seg - 1][0], rows[seg - 1][1], tip], mat, uv=[(0, t0), (1, t0), (0.5, 1)])
    return pts

def sphere_blob(mb, c, radii, sub, mat, rng=None, jit=0.0, col=(0, 0, 0.8, 0.5), smooth=True, rot=None):
    V, F = ico(sub); base = len(mb.V)
    for d in V:
        p = Vector((d[0] * radii[0], d[1] * radii[1], d[2] * radii[2]))
        if jit and rng: p = p * (1 + jit * rng.uniform(-1, 1))
        if rot is not None: p = rot @ p
        mb.v(Vector(c) + p, col)
    for f in F: mb.f([base + i for i in f], mat, smooth=smooth)
    return base

def box(mb, c, size, mat, rot=None, col=(0, 0, 0.8, 0.5), smooth=False, uvs=1.0):
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
    P = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz), (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]
    ids = []
    for p in P:
        q = Vector(p)
        if rot is not None: q = rot @ q
        ids.append(mb.v(Vector(c) + q, col))
    for f in ([0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]):
        mb.f([ids[i] for i in f], mat, smooth=smooth, uvs=uvs)

# ----------------------------------------------------------------------------------------------- materials
MAT_VER = 5
MAT_DEFS = {
    'M_Rock':               dict(col=(0.24, 0.23, 0.21), rough=0.90, tint=(0.6, 1.3), ns=2.2, bump=0.6, kind='rock'),
    'M_Rock_Slate':         dict(col=(0.16, 0.17, 0.19), rough=0.85, tint=(0.65, 1.3), ns=2.8, bump=0.6, kind='rock'),
    'M_Rock_Sandstone':     dict(col=(0.40, 0.20, 0.10), rough=0.95, tint=(0.7, 1.2), ns=3.5, bump=0.4, kind='rock'),
    'M_Rock_SandstoneDark': dict(col=(0.22, 0.09, 0.05), rough=0.95, tint=(0.7, 1.2), ns=3.5, bump=0.4, kind='rock'),
    'M_Rock_Beach':         dict(col=(0.33, 0.30, 0.26), rough=0.80, tint=(0.6, 1.25), ns=3.0, bump=0.5, kind='rock'),
    'M_Bush_Leaf':          dict(col=(0.09, 0.28, 0.05), rough=0.55, tint=(0.7, 1.4), ns=1.6, kind='leaf'),
    'M_Bush_Leaf_Evergreen': dict(col=(0.03, 0.13, 0.06), rough=0.45, tint=(0.7, 1.4), ns=1.8, kind='leaf'),
    'M_Bush_Dry':           dict(col=(0.42, 0.30, 0.13), rough=0.85, tint=(0.6, 1.2), ns=2.0, kind='leaf'),
    'M_Bush_Berry':         dict(col=(0.40, 0.02, 0.03), rough=0.35, tint=(0.8, 1.1), ns=4.0, kind='plain'),
    'M_Wood_Log':           dict(col=(0.16, 0.10, 0.06), rough=0.9, tint=(0.55, 1.3), ns=6.0, bump=0.8, kind='wood'),
    'M_Wood_LogEnd':        dict(col=(0.50, 0.34, 0.19), rough=0.85, tint=(0.7, 1.2), ns=9.0, bump=0.2, kind='wood'),
    'M_Wood_Plank':         dict(col=(0.36, 0.25, 0.15), rough=0.85, tint=(0.65, 1.2), ns=5.0, bump=0.3, kind='wood'),
    'M_Cactus':             dict(col=(0.08, 0.26, 0.11), rough=0.6, tint=(0.75, 1.25), ns=3.0, bump=0.2, kind='plain'),
    'M_Cactus_Spine':       dict(col=(0.70, 0.60, 0.40), rough=0.7, tint=(0.8, 1.1), ns=8.0, kind='plain'),
    'M_Cactus_Fruit':       dict(col=(0.50, 0.04, 0.10), rough=0.4, tint=(0.8, 1.2), ns=5.0, kind='plain'),
    'M_Grass_Blade':        dict(col=(0.10, 0.30, 0.05), rough=0.6, tint=(0.7, 1.4), ns=1.5, kind='leaf'),
    'M_Grass_Dry':          dict(col=(0.50, 0.40, 0.17), rough=0.75, tint=(0.65, 1.25), ns=1.8, kind='leaf'),
    'M_Reed':               dict(col=(0.17, 0.30, 0.08), rough=0.55, tint=(0.7, 1.35), ns=1.5, kind='leaf'),
    'M_Reed_Head':          dict(col=(0.22, 0.10, 0.05), rough=0.8, tint=(0.7, 1.2), ns=6.0, kind='plain'),
    'M_Flower':             dict(col=(0.85, 0.83, 0.80), rough=0.5, tint=(0.85, 1.05), ns=4.0, kind='plain'),
    'M_Flower_B':           dict(col=(0.40, 0.08, 0.50), rough=0.5, tint=(0.8, 1.2), ns=4.0, kind='plain'),
    'M_Flower_Center':      dict(col=(0.85, 0.58, 0.04), rough=0.6, tint=(0.8, 1.1), ns=6.0, kind='plain'),
    'M_Crop':               dict(col=(0.30, 0.34, 0.10), rough=0.6, tint=(0.7, 1.35), ns=1.8, kind='leaf'),
    'M_Crop_Ear':           dict(col=(0.58, 0.42, 0.14), rough=0.6, tint=(0.75, 1.2), ns=3.0, kind='leaf'),
    'M_Crop_Soil':          dict(col=(0.13, 0.08, 0.05), rough=0.95, tint=(0.6, 1.3), ns=5.0, bump=0.6, kind='rock'),
    'M_Hay':                dict(col=(0.60, 0.47, 0.20), rough=0.9, tint=(0.65, 1.25), ns=14.0, bump=0.7, kind='wood'),
    'M_Hay_Twine':          dict(col=(0.30, 0.22, 0.09), rough=0.9, tint=(0.8, 1.1), ns=10.0, kind='plain'),
    'M_Beach_Red':          dict(col=(0.55, 0.04, 0.03), rough=0.55, tint=(0.85, 1.1), ns=3.0, kind='plain'),
    'M_Beach_White':        dict(col=(0.78, 0.76, 0.70), rough=0.55, tint=(0.85, 1.05), ns=3.0, kind='plain'),
    'M_Beach_Blue':         dict(col=(0.04, 0.18, 0.50), rough=0.55, tint=(0.85, 1.1), ns=3.0, kind='plain'),
    'M_Beach_Metal':        dict(col=(0.55, 0.55, 0.57), rough=0.35, tint=(0.9, 1.05), ns=3.0, metal=0.9, kind='plain'),
    'M_Sand':               dict(col=(0.58, 0.47, 0.30), rough=1.0, tint=(0.75, 1.2), ns=20.0, bump=0.5, kind='rock'),
    'M_Sign_Paint':         dict(col=(0.72, 0.69, 0.58), rough=0.6, tint=(0.8, 1.1), ns=6.0, kind='plain'),
    'M_Metal_Galv':         dict(col=(0.45, 0.47, 0.50), rough=0.4, tint=(0.9, 1.05), ns=5.0, metal=0.85, kind='plain'),
}

def _n(nt, typ, x, y):
    n = nt.nodes.new(typ); n.location = (x, y); return n

def ensure_materials(names):
    out = {}
    for name in names:
        d = MAT_DEFS[name]
        m = bpy.data.materials.get(name)
        if m is None:
            m = bpy.data.materials.new(name)
        elif m.get('gc_ver') is None:
            out[name] = m; continue          # somebody else's material of the same name: leave untouched
        out[name] = m
        c = d['col']
        m.diffuse_color = (min(1, c[0] * 1.5), min(1, c[1] * 1.5), min(1, c[2] * 1.5), 1.0)
        m.roughness = d['rough']
        if m.get('gc_ver') == MAT_VER and m.node_tree and len(m.node_tree.nodes) > 3:
            continue
        m.use_nodes = True
        nt = m.node_tree; nt.nodes.clear()
        o = _n(nt, 'ShaderNodeOutputMaterial', 900, 0)
        bs = _n(nt, 'ShaderNodeBsdfPrincipled', 640, 0)
        nt.links.new(bs.outputs['BSDF'], o.inputs['Surface'])
        bs.inputs['Roughness'].default_value = d['rough']
        try: bs.inputs['Metallic'].default_value = d.get('metal', 0.0)
        except Exception: pass
        try: bs.inputs['Specular IOR Level'].default_value = 0.1 if d['kind'] == 'leaf' else 0.25
        except Exception: pass
        vc = _n(nt, 'ShaderNodeVertexColor', -700, 250); vc.layer_name = 'Col'
        sp = _n(nt, 'ShaderNodeSeparateColor', -500, 250)
        nt.links.new(vc.outputs['Color'], sp.inputs[0])
        ao = _n(nt, 'ShaderNodeMath', -300, 280); ao.operation = 'MULTIPLY_ADD'
        nt.links.new(sp.outputs[2], ao.inputs[0]); ao.inputs[1].default_value = 0.8; ao.inputs[2].default_value = 0.2
        tc = _n(nt, 'ShaderNodeTexCoord', -900, -100)
        noi = _n(nt, 'ShaderNodeTexNoise', -650, -100)
        noi.inputs['Scale'].default_value = d['ns']; noi.inputs['Detail'].default_value = 4.0
        nt.links.new(tc.outputs['Object'], noi.inputs['Vector'])
        ramp = _n(nt, 'ShaderNodeValToRGB', -420, -100)
        lo, hi = d['tint']
        ramp.color_ramp.elements[0].color = (c[0] * lo, c[1] * lo, c[2] * lo, 1)
        ramp.color_ramp.elements[1].color = (min(1, c[0] * hi), min(1, c[1] * hi), min(1, c[2] * hi), 1)
        nt.links.new(noi.outputs['Fac'], ramp.inputs['Fac'])
        mix = _n(nt, 'ShaderNodeMix', 300, 100); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'
        mix.inputs[0].default_value = 1.0
        nt.links.new(ramp.outputs['Color'], mix.inputs[6])
        ao_c = _n(nt, 'ShaderNodeCombineColor', 100, 280)
        for k in range(3): nt.links.new(ao.outputs[0], ao_c.inputs[k])
        nt.links.new(ao_c.outputs[0], mix.inputs[7])
        last = mix.outputs[2]
        if d['kind'] == 'leaf':
            gm = _n(nt, 'ShaderNodeMath', 100, 20); gm.operation = 'MULTIPLY_ADD'
            nt.links.new(sp.outputs[1], gm.inputs[0]); gm.inputs[1].default_value = 0.35; gm.inputs[2].default_value = 0.85
            gc = _n(nt, 'ShaderNodeCombineColor', 250, 20)
            for k in range(3): nt.links.new(gm.outputs[0], gc.inputs[k])
            mix2 = _n(nt, 'ShaderNodeMix', 470, 100); mix2.data_type = 'RGBA'; mix2.blend_type = 'MULTIPLY'
            mix2.inputs[0].default_value = 1.0
            nt.links.new(last, mix2.inputs[6]); nt.links.new(gc.outputs[0], mix2.inputs[7])
            last = mix2.outputs[2]
        nt.links.new(last, bs.inputs['Base Color'])
        if d.get('bump'):
            nb = _n(nt, 'ShaderNodeTexNoise', -650, -400)
            nb.inputs['Scale'].default_value = d['ns'] * 3.0; nb.inputs['Detail'].default_value = 6.0
            nt.links.new(tc.outputs['Object'], nb.inputs['Vector'])
            bump = _n(nt, 'ShaderNodeBump', 300, -300); bump.inputs['Strength'].default_value = d['bump']
            nt.links.new(nb.outputs['Fac'], bump.inputs['Height'])
            nt.links.new(bump.outputs['Normal'], bs.inputs['Normal'])
        m['gc_ver'] = MAT_VER
    return out

# ----------------------------------------------------------------------------------------------- scene objects
def get_cover_collection():
    fz = bpy.data.collections.get('FORZA_UE')
    if fz is None:
        fz = bpy.data.collections.new('FORZA_UE'); bpy.context.scene.collection.children.link(fz)
    nat = bpy.data.collections.get('Nature')
    if nat is None:
        nat = bpy.data.collections.new('Nature'); fz.children.link(nat)
    elif nat.name not in [c.name for c in fz.children]:
        fz.children.link(nat)
    col = bpy.data.collections.get('Cover')
    if col is None: col = bpy.data.collections.new('Cover')
    if col.name not in [c.name for c in nat.children]: nat.children.link(col)
    return col

def remove_asset(aid):
    for o in list(bpy.data.objects):
        n = o.name
        if n == aid or (n.startswith('UCX_' + aid + '_') and n[len('UCX_' + aid + '_'):].isdigit()):
            me = o.data if o.type == 'MESH' else None
            bpy.data.objects.remove(o, do_unlink=True)
            if me is not None and me.users == 0: bpy.data.meshes.remove(me)

def mb_to_mesh(mb, name, mats):
    me = bpy.data.meshes.new(name)
    me.from_pydata(mb.V, [], mb.F)
    me.update(calc_edges=True)
    for mn_ in mb.mats: me.materials.append(mats[mn_])
    me.polygons.foreach_set('material_index', np.array(mb.FM, dtype=np.int32))
    sm = np.array(mb.SM, dtype=bool)
    try: me.polygons.foreach_set('use_smooth', sm)
    except Exception:
        if sm.all(): me.shade_smooth()
    uvl = me.uv_layers.new(name='UVMap')
    uvl.data.foreach_set('uv', np.array([c for f in mb.UV for uv in f for c in uv], dtype=np.float32))
    lv = np.empty(len(me.loops), dtype=np.int32); me.loops.foreach_get('vertex_index', lv)
    C = np.array(mb.C, dtype=np.float32)
    ca = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
    ca.data.foreach_set('color', C[lv].ravel())
    try: me.color_attributes.active_color = ca
    except Exception: pass
    me.update()
    return me

def hull_points(P, ndir=24):
    P = np.asarray(P, dtype=np.float64)
    D = np.array(fib_dirs(ndir))
    idx = np.unique(np.argmax(P @ D.T, axis=0))
    return P[idx]

def make_hull(name, pts, parent, col):
    bm = bmesh.new()
    for p in pts: bm.verts.new((float(p[0]), float(p[1]), float(p[2])))
    bm.verts.ensure_lookup_table()
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:], use_existing_faces=False)
    dead = [g for g in set(res['geom_interior'] + res['geom_unused']) if isinstance(g, bmesh.types.BMVert)]
    if dead: bmesh.ops.delete(bm, geom=dead, context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); col.objects.link(o)
    o.parent = parent; o.display_type = 'WIRE'; o.hide_render = True
    return o

def island_check(obj):
    bm = bmesh.new(); bm.from_mesh(obj.data); bm.faces.ensure_lookup_table()
    seen = set(); closed = inverted = opened = 0
    for f in bm.faces:
        if f.index in seen: continue
        stack = [f]; seen.add(f.index); faces = []; boundary = False
        while stack:
            cur = stack.pop(); faces.append(cur)
            for e in cur.edges:
                lf = e.link_faces
                if len(lf) == 1: boundary = True
                for g in lf:
                    if g.index not in seen: seen.add(g.index); stack.append(g)
        if boundary: opened += 1; continue
        closed += 1; vol = 0.0
        for fc in faces:
            vs = [v.co for v in fc.verts]
            for k in range(1, len(vs) - 1): vol += vs[0].dot(vs[k].cross(vs[k + 1])) / 6.0
        if vol < 0: inverted += 1
    bm.free()
    return dict(closed_pieces=closed, open_pieces=opened, inverted_closed_pieces=inverted)

def mesh_stats(obj):
    me = obj.data
    bm = bmesh.new(); bm.from_mesh(me)
    tris = sum(len(f.verts) - 2 for f in bm.faces)
    nm = sum(1 for e in bm.edges if len(e.link_faces) > 2); bd = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    loose = sum(1 for v in bm.verts if not v.link_edges)
    bm.free()
    co = np.empty(len(me.vertices) * 3, dtype=np.float32); me.vertices.foreach_get('co', co); co = co.reshape(-1, 3)
    return dict(tris=tris, verts=len(me.vertices), nonmanifold_edges=nm, boundary_edges=bd, loose_verts=loose,
                bbox_min=[round(float(x), 3) for x in co.min(0)], bbox_max=[round(float(x), 3) for x in co.max(0)])

_FBXL = [False]
def fbx_lib():
    if not _FBXL[0]:
        exec(compile(open(FBX_LIB, encoding='utf8').read(), FBX_LIB, 'exec'), globals()); _FBXL[0] = True
