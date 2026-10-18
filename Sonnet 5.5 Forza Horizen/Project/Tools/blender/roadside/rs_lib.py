# -*- coding: utf-8 -*-
"""
Roadside kit - geometry + harness library.   (exec'd into a PRIVATE namespace by roadside_kit.py; never import directly)

Conventions (Docs/BLENDER_CONTRACT.md):  1 BU = 1 m, Z up, +X = front (sign face) / run direction of tileable segments.
Everything is built with bmesh only (no bpy.ops, no selection state) so every call is atomic and safe in the shared Blender.
Only objects/meshes/collections named after the asset id (rs_*) are ever touched.
"""
import bpy, bmesh, math, random, os, json, time, zlib
from math import pi, sin, cos, sqrt, atan2, radians, degrees, floor, ceil, tan, acos, asin
from mathutils import Vector, Matrix, Euler, Quaternion

PROJECT = r"W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza"
STAGE_Y = 80.0
EXPORT_DIR = PROJECT + r"\Exports\Roadside"
Z3 = Vector((0, 0, 1))

# ----------------------------------------------------------------------------------------------------------------------
# colours / materials
# ----------------------------------------------------------------------------------------------------------------------
def hexc(h, a=1.0):
    h = h.lstrip('#')
    r, g, b = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), a)

MATS = {
    'M_RS_GalvSteel':   dict(c='#a4a9ae', m=0.9, r=0.40),
    'M_RS_GalvDark':    dict(c='#5d6268', m=0.85, r=0.50),
    'M_RS_Concrete':    dict(c='#a29f98', m=0.0, r=0.93, tint=True),
    'M_RS_ConcreteDark': dict(c='#6f6d68', m=0.0, r=0.95, tint=True),
    'M_RS_Wood':        dict(c='#7c5532', m=0.0, r=0.82, tint=True),
    'M_RS_WoodPale':    dict(c='#b8935f', m=0.0, r=0.80, tint=True),
    'M_RS_Stone':       dict(c='#8d867b', m=0.0, r=0.95, tint=True),
    'M_RS_Mortar':      dict(c='#6e6a63', m=0.0, r=0.97),
    'M_RS_PaintWhite':  dict(c='#ecece8', m=0.0, r=0.50),
    'M_RS_PaintRed':    dict(c='#c3231c', m=0.0, r=0.45),
    'M_RS_PaintBlack':  dict(c='#1d1e20', m=0.0, r=0.55),
    'M_RS_PaintYellow': dict(c='#f0bf00', m=0.0, r=0.50),
    'M_RS_PaintGrey':   dict(c='#6c7075', m=0.1, r=0.55),
    'M_RS_PlasticOrange': dict(c='#f0580c', m=0.0, r=0.42),
    'M_RS_PlasticWhite': dict(c='#efeeea', m=0.0, r=0.40),
    'M_RS_Rubber':      dict(c='#171717', m=0.0, r=0.88),
    'M_RS_ReflectorRed': dict(c='#d4161b', m=0.0, r=0.15, e=('#ff2020', 0.6)),
    'M_RS_ReflectorWhite': dict(c='#f2f2f2', m=0.0, r=0.15, e=('#ffffff', 0.5)),
    'M_RS_ReflectorAmber': dict(c='#ffa400', m=0.0, r=0.15, e=('#ffa000', 0.6)),
    'M_RS_SignWhite':   dict(c='#f2f2ef', m=0.0, r=0.33),
    'M_RS_SignRed':     dict(c='#c9191d', m=0.0, r=0.33),
    'M_RS_SignBlack':   dict(c='#111214', m=0.0, r=0.40),
    'M_RS_SignBlue':    dict(c='#0a4aa0', m=0.0, r=0.33),
    'M_RS_SignYellow':  dict(c='#f6c500', m=0.0, r=0.33),
    'M_RS_SignGreen':   dict(c='#0a6b3b', m=0.0, r=0.33),
    'M_RS_SignBack':    dict(c='#8b9096', m=0.75, r=0.48),
    'M_RS_LampLens':    dict(c='#fff4d8', m=0.0, r=0.15, e=('#fff1cf', 6.0)),
    'M_RS_Insulator':   dict(c='#5b6b5a', m=0.0, r=0.18),
    'M_RS_Glass':       dict(c='#a9c8d0', m=0.0, r=0.05, a=0.22),
    'M_RS_Hay':         dict(c='#cfae52', m=0.0, r=0.95, tint=True),
    'M_RS_Wire':        dict(c='#2b2c2e', m=0.6, r=0.40),
    'M_RS_Rust':        dict(c='#6b3f26', m=0.5, r=0.75, tint=True),
    'M_RS_BillboardFace': dict(c='#e9e6dc', m=0.0, r=0.6),
    'M_RS_BillboardFace_B': dict(c='#e9e6dc', m=0.0, r=0.6),
    'M_RS_BillboardFace_C': dict(c='#e9e6dc', m=0.0, r=0.6),
    'M_RS_Rope':        dict(c='#8d6e3c', m=0.0, r=0.9),
    'M_RS_PlasticGrey': dict(c='#55595e', m=0.0, r=0.5),
    'M_RS_Grating':     dict(c='#4a4e53', m=0.8, r=0.55),
    'M_RS_Soil':        dict(c='#5a4631', m=0.0, r=1.0, tint=True),
    'M_RS_TyreRubber':  dict(c='#1c1c1d', m=0.0, r=0.86, tint=True),
    'M_RS_TyrePaint':   dict(c='#e7e5dd', m=0.0, r=0.72, tint=True),
}

def ensure_material(name):
    spec = MATS[name]
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    base = hexc(spec['c'])
    for n in list(nt.nodes):
        if n.type in ('VERTEX_COLOR', 'MIX'):
            nt.nodes.remove(n)
    for l in list(bsdf.inputs['Base Color'].links):
        nt.links.remove(l)
    bsdf.inputs['Base Color'].default_value = base
    if spec.get('tint'):
        vc = nt.nodes.new('ShaderNodeVertexColor')
        vc.layer_name = 'Col'
        mx = nt.nodes.new('ShaderNodeMix')
        mx.data_type = 'RGBA'
        mx.blend_type = 'MULTIPLY'
        mx.inputs[0].default_value = 1.0
        mx.inputs[6].default_value = base
        nt.links.new(vc.outputs[0], mx.inputs[7])
        nt.links.new(mx.outputs[2], bsdf.inputs['Base Color'])
        vc.location = (-600, 100)
        mx.location = (-350, 100)
    for n in list(nt.nodes):
        if n.type in ('TEX_COORD', 'SEPXYZ', 'VALTORGB', 'TEX_CHECKER', 'TEX_IMAGE', 'UVMAP'):
            nt.nodes.remove(n)
    ad_png = None
    if 'AD_MATERIALS' in globals() and name in AD_MATERIALS:
        ad_png = os.path.join(AD_DIR, AD_FILES[AD_MATERIALS[name]])
    if ad_png and os.path.exists(ad_png):
        # original ad artwork (rs_ads.py): image texture over UV 0..1 of the face; UE swaps the texture per material instance
        tex = nt.nodes.new('ShaderNodeTexImage')
        tex.image = bpy.data.images.load(ad_png, check_existing=True)
        try:
            tex.image.colorspace_settings.name = 'sRGB'
        except Exception:
            pass
        tex.location = (-500, 300)
        nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    elif name.startswith('M_RS_BillboardFace'):
        # procedural placeholder artwork (fallback when the PNGs are missing): UV gradient
        tc = nt.nodes.new('ShaderNodeTexCoord')
        sep = nt.nodes.new('ShaderNodeSeparateXYZ')
        ramp = nt.nodes.new('ShaderNodeValToRGB')
        nt.links.new(tc.outputs['UV'], sep.inputs[0])
        nt.links.new(sep.outputs['Y'], ramp.inputs['Fac'])
        nt.links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
        ramp.color_ramp.elements[0].color = hexc('#f4a63c')
        ramp.color_ramp.elements[1].color = hexc('#2b66b3')
        tc.location = (-800, 300); sep.location = (-600, 300); ramp.location = (-400, 300)
    bsdf.inputs['Metallic'].default_value = spec.get('m', 0.0)
    bsdf.inputs['Roughness'].default_value = spec.get('r', 0.6)
    if 'e' in spec:
        bsdf.inputs['Emission Color'].default_value = hexc(spec['e'][0])
        bsdf.inputs['Emission Strength'].default_value = spec['e'][1]
    else:
        bsdf.inputs['Emission Strength'].default_value = 0.0
    if 'a' in spec:
        bsdf.inputs['Alpha'].default_value = spec['a']
        try:
            mat.surface_render_method = 'BLENDED'
        except Exception:
            pass
    mat.diffuse_color = base
    mat.metallic = spec.get('m', 0.0)
    mat.roughness = spec.get('r', 0.6)
    return mat

# ----------------------------------------------------------------------------------------------------------------------
# small geometry helpers
# ----------------------------------------------------------------------------------------------------------------------
def v3(p):
    return p.copy() if isinstance(p, Vector) else Vector(p)

def lerp(a, b, t):
    return a + (b - a) * t

def arc_pts(cx, cy, rx, ry, a0, a1, n):
    """2D points along an ellipse arc, a0..a1 degrees, n segments (n+1 points)."""
    return [(cx + rx * cos(radians(a0 + (a1 - a0) * i / n)), cy + ry * sin(radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]

def ellipse_pts(cx, cy, rx, ry, n, start=0.0):
    return [(cx + rx * cos(radians(start + 360.0 * i / n)), cy + ry * sin(radians(start + 360.0 * i / n))) for i in range(n)]

def poly_area(p):
    a = 0.0
    for i in range(len(p)):
        x0, y0 = p[i]
        x1, y1 = p[(i + 1) % len(p)]
        a += x0 * y1 - x1 * y0
    return a * 0.5

def ccw(p):
    return list(p) if poly_area(p) >= 0 else list(reversed(p))

def clean_poly(p, eps=2e-5):
    """drop coincident and collinear (straight-through) points so triangulation never yields zero-area slivers"""
    out = [tuple(q) for q in p]
    changed = True
    while changed and len(out) > 3:
        changed = False
        n = len(out)
        for i in range(n):
            a = out[i - 1]; b = out[i]; c = out[(i + 1) % n]
            abx, aby = b[0] - a[0], b[1] - a[1]
            bcx, bcy = c[0] - b[0], c[1] - b[1]
            la = (abx * abx + aby * aby) ** 0.5; lb = (bcx * bcx + bcy * bcy) ** 0.5
            if la < 1e-6 or lb < 1e-6:
                del out[i]; changed = True; break
            cr = (abx * bcy - aby * bcx) / (la * lb)
            dt = (abx * bcx + aby * bcy)
            if abs(cr) < eps and dt > 0:
                del out[i]; changed = True; break
    return out

def is_convex(p):
    n = len(p)
    sgn = 0
    for i in range(n):
        a, b, c = p[i], p[(i + 1) % n], p[(i + 2) % n]
        cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if abs(cr) < 1e-12:
            continue
        s = 1 if cr > 0 else -1
        if sgn == 0:
            sgn = s
        elif s != sgn:
            return False
    return True

def offset_poly(p, d, miter_cap=3.0):
    """Offset a closed polygon by d (positive = grow outward). Same point count. Works for convex / gently curved."""
    p = ccw(p)
    n = len(p)
    out = []
    for i in range(n):
        a = Vector(p[i - 1]); b = Vector(p[i]); c = Vector(p[(i + 1) % n])
        e0 = (b - a); e1 = (c - b)
        if e0.length < 1e-9: e0 = e1
        if e1.length < 1e-9: e1 = e0
        n0 = Vector((e0.y, -e0.x)).normalized(); n1 = Vector((e1.y, -e1.x)).normalized()
        m = n0 + n1
        if m.length < 1e-9:
            m = n0
        m.normalize()
        k = d / max(m.dot(n0), 1.0 / miter_cap)
        q = b + m * k
        out.append((q.x, q.y))
    return out

def rounded_poly(corners, r, n=6):
    """Polygon with filleted corners (corners given CCW or CW). Returns list of 2D points."""
    pts = ccw(corners)
    m = len(pts)
    out = []
    for i in range(m):
        P = Vector(pts[i]); A = Vector(pts[i - 1]); B = Vector(pts[(i + 1) % m])
        d1 = (A - P).normalized(); d2 = (B - P).normalized()
        th = acos(max(-1.0, min(1.0, d1.dot(d2))))
        t = r / tan(th / 2.0)
        T1 = P + d1 * t; T2 = P + d2 * t
        bis = (d1 + d2).normalized()
        C = P + bis * (r / sin(th / 2.0))
        a1 = atan2(T1.y - C.y, T1.x - C.x); a2 = atan2(T2.y - C.y, T2.x - C.x)
        da = a2 - a1
        while da > pi: da -= 2 * pi
        while da < -pi: da += 2 * pi
        for k in range(n + 1):
            a = a1 + da * k / n
            out.append((C.x + r * cos(a), C.y + r * sin(a)))
    return out

def bezier(p0, p1, p2, p3, n):
    p0, p1, p2, p3 = map(v3, (p0, p1, p2, p3))
    out = []
    for i in range(n + 1):
        t = i / n; u = 1 - t
        out.append(u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3)
    return out

def perp2(d):
    return Vector((-d.y, d.x))

def stroke_poly(pts, w, miter_cap=2.2):
    """Open polyline (2D) -> thick polygon outline (list of 2D tuples), flat caps."""
    P = [Vector(p) for p in pts]
    n = len(P)
    L = []; R = []
    for i in range(n):
        if i == 0:
            d = (P[1] - P[0]).normalized(); m = perp2(d); k = w / 2
        elif i == n - 1:
            d = (P[-1] - P[-2]).normalized(); m = perp2(d); k = w / 2
        else:
            d0 = (P[i] - P[i - 1]).normalized(); d1 = (P[i + 1] - P[i]).normalized()
            n0 = perp2(d0); n1 = perp2(d1)
            m = n0 + n1
            if m.length < 1e-6:
                m = n0
            m.normalize()
            k = (w / 2) / max(m.dot(n0), 1.0 / miter_cap)
        L.append(P[i] + m * k); R.append(P[i] - m * k)
    poly = L + R[::-1]
    return [(q.x, q.y) for q in poly]

def stroke_ring(pts, w, miter_cap=2.2):
    """Closed polyline -> (outer, inner) polygons with equal point counts."""
    P = [Vector(p) for p in pts]
    n = len(P)
    cen = sum(P, Vector((0, 0))) / n
    A = []; B = []
    for i in range(n):
        d0 = (P[i] - P[i - 1]).normalized(); d1 = (P[(i + 1) % n] - P[i]).normalized()
        n0 = perp2(d0); n1 = perp2(d1)
        m = n0 + n1
        if m.length < 1e-6: m = n0
        m.normalize()
        k = (w / 2) / max(m.dot(n0), 1.0 / miter_cap)
        A.append(P[i] + m * k); B.append(P[i] - m * k)
    da = sum((q - cen).length for q in A); db = sum((q - cen).length for q in B)
    outer, inner = (A, B) if da > db else (B, A)
    return [(q.x, q.y) for q in outer], [(q.x, q.y) for q in inner]

def clip_rect(poly, u0, v0, u1, v1):
    """Sutherland-Hodgman clip of a 2D polygon against an axis-aligned rectangle."""
    def clip(pts, inside, inter):
        out = []
        for i in range(len(pts)):
            a = pts[i - 1]; b = pts[i]
            ia, ib = inside(a), inside(b)
            if ib:
                if not ia: out.append(inter(a, b))
                out.append(b)
            elif ia:
                out.append(inter(a, b))
        return out
    def ix(x):
        return lambda a, b: (x, a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0]))
    def iy(y):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]), y)
    p = list(poly)
    for ins, it in ((lambda q: q[0] >= u0, ix(u0)), (lambda q: q[0] <= u1, ix(u1)), (lambda q: q[1] >= v0, iy(v0)), (lambda q: q[1] <= v1, iy(v1))):
        if not p: break
        p = clip(p, ins, it)
    out = []
    for q in p:
        if not out or abs(q[0] - out[-1][0]) > 1e-6 or abs(q[1] - out[-1][1]) > 1e-6:
            out.append(q)
    if len(out) > 1 and abs(out[0][0] - out[-1][0]) < 1e-6 and abs(out[0][1] - out[-1][1]) < 1e-6:
        out.pop()
    return out

class Plane:
    """Local 2D frame in 3D: p(u,v,w) = O + U*u + V*v + N*w   (N = U x V)."""
    def __init__(s, O, U, V):
        s.O = v3(O); s.U = v3(U).normalized(); s.V = v3(V).normalized(); s.N = s.U.cross(s.V).normalized()
    def p(s, u, v, w=0.0):
        return s.O + s.U * u + s.V * v + s.N * w

# front-facing sign plane helper: normal +X, screen-right = +Y, up = +Z
def sign_plane(x=0.0, zc=0.0, yc=0.0):
    return Plane((x, yc, zc), (0, 1, 0), (0, 0, 1))

def path_frames(path, up=(0, 0, 1)):
    n = len(path)
    up = v3(up)
    fr = []
    prevS = Vector((0, 1, 0))
    for i in range(n):
        a = path[max(i - 1, 0)]; b = path[min(i + 1, n - 1)]
        t = (b - a).normalized()
        S = up.cross(t)
        if S.length < 1e-4:
            S = prevS.copy()
        S.normalize(); prevS = S
        U = t.cross(S).normalized()
        fr.append((t, S, U))
    return fr

# ----------------------------------------------------------------------------------------------------------------------
# mesh builder
# ----------------------------------------------------------------------------------------------------------------------
class MB:
    def __init__(s, name):
        s.name = name
        s.bm = bmesh.new()
        s.mats = []
        s.uvl = s.bm.loops.layers.uv.new('UVMap')
        s.coll = s.bm.loops.layers.color.new('Col')
        s.decal = s.bm.faces.layers.int.new('decal')     # 1 = flat single-sided graphic card (text / pictogram): open by design
        s.hulls = []
        s.rng = random.Random(zlib.crc32(name.encode()))
        s.sockets = {}

    # ---- materials / faces
    def mi(s, m):
        if m not in s.mats:
            s.mats.append(m)
        return s.mats.index(m)

    def vert(s, p):
        return s.bm.verts.new(v3(p))

    def _auto_uv(s, ps, scale=1.0):
        n = Vector((0, 0, 0))
        m = len(ps)
        for i in range(m):
            a = ps[i]; b = ps[(i + 1) % m]
            n.x += (a.y - b.y) * (a.z + b.z); n.y += (a.z - b.z) * (a.x + b.x); n.z += (a.x - b.x) * (a.y + b.y)
        ax = max(range(3), key=lambda i: abs(n[i]))
        if ax == 0: return [(p.y * scale, p.z * scale) for p in ps]
        if ax == 1: return [(p.x * scale, p.z * scale) for p in ps]
        return [(p.x * scale, p.y * scale) for p in ps]

    def face(s, vs, mat, smooth=False, uvs=None, col=None, tri=False, decal=False):
        try:
            f = s.bm.faces.new(vs)
        except ValueError:
            return None
        f.material_index = s.mi(mat)
        f.smooth = bool(smooth)
        if decal:
            f[s.decal] = 1
        if uvs is None:
            uvs = s._auto_uv([v.co for v in vs])
        for l, uv in zip(f.loops, uvs):
            l[s.uvl].uv = uv
        c = col if col is not None else (1.0, 1.0, 1.0, 1.0)
        if len(c) == 3: c = (c[0], c[1], c[2], 1.0)
        for l in f.loops:
            l[s.coll] = c
        if tri and len(vs) > 3:
            f.normal_update()
            bmesh.ops.triangulate(s.bm, faces=[f], quad_method='BEAUTY', ngon_method='EAR_CLIP')
        return f

    def tint(s, amt=0.12, base=(1, 1, 1)):
        """random per-island-ish tint value around 1.0 (used as vertex colour on tinted materials)"""
        k = 1.0 + s.rng.uniform(-amt, amt)
        return (min(1, base[0] * k), min(1, base[1] * k), min(1, base[2] * k), 1.0)

    # ---- boxes
    def obox(s, center, size, mat, rot=None, c=0.0, smooth=False, col=None):
        """Oriented (optionally chamfered) box. mat: str or dict {'+x','-x','+y','-y','+z','-z','edge','all'}.
        rot: Matrix(3x3/4x4), Euler, or (rx,ry,rz) degrees."""
        if rot is None:
            R = Matrix.Identity(4)
        elif isinstance(rot, Matrix):
            R = rot.to_4x4()
        elif isinstance(rot, Euler):
            R = rot.to_matrix().to_4x4()
        else:
            R = Euler((radians(rot[0]), radians(rot[1]), radians(rot[2])), 'XYZ').to_matrix().to_4x4()
        M = Matrix.Translation(v3(center)) @ R
        hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
        def mm(key):
            if isinstance(mat, str): return mat
            return mat.get(key, mat.get('all'))
        c = min(c, hx * 0.98, hy * 0.98, hz * 0.98)
        if c <= 1e-6:
            V = {}
            for i in (-1, 1):
                for j in (-1, 1):
                    for k in (-1, 1):
                        V[(i, j, k)] = s.vert(M @ Vector((i * hx, j * hy, k * hz)))
            def F(keys, m, key):
                s.face([V[k] for k in keys], m, smooth, col=col)
            F([(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)], mm('+x'), '+x')
            F([(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)], mm('-x'), '-x')
            F([(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)], mm('+y'), '+y')
            F([(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)], mm('-y'), '-y')
            F([(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)], mm('+z'), '+z')
            F([(-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1)], mm('-z'), '-z')
            return
        V = {}
        for i in (-1, 1):
            for j in (-1, 1):
                for k in (-1, 1):
                    V[(i, j, k, 0)] = s.vert(M @ Vector((i * hx, j * (hy - c), k * (hz - c))))
                    V[(i, j, k, 1)] = s.vert(M @ Vector((i * (hx - c), j * hy, k * (hz - c))))
                    V[(i, j, k, 2)] = s.vert(M @ Vector((i * (hx - c), j * (hy - c), k * hz)))
        em = mm('edge')
        # faces
        for t, nm in ((0, 'x'), (1, 'y'), (2, 'z')):
            for sg in (-1, 1):
                ring = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
                keys = []
                for a, b in ring:
                    if t == 0: keys.append((sg, a, b, 0))
                    elif t == 1: keys.append((a, sg, b, 1))
                    else: keys.append((a, b, sg, 2))
                s.face([V[k] for k in keys], mm(('+' if sg > 0 else '-') + nm), False, col=col)
        # edges
        for (t1, t2) in ((0, 1), (0, 2), (1, 2)):
            for a in (-1, 1):
                for b in (-1, 1):
                    tr = 3 - t1 - t2
                    ks = []
                    for e in (-1, 1):
                        key = [0, 0, 0]; key[t1] = a; key[t2] = b; key[tr] = e
                        ks.append((key[0], key[1], key[2]))
                    s.face([V[ks[0] + (t1,)], V[ks[0] + (t2,)], V[ks[1] + (t2,)], V[ks[1] + (t1,)]], em, False, col=col)
        # corners
        for i in (-1, 1):
            for j in (-1, 1):
                for k in (-1, 1):
                    s.face([V[(i, j, k, 0)], V[(i, j, k, 1)], V[(i, j, k, 2)]], em, False, col=col)

    def box(s, mn, mx, mat, c=0.0, smooth=False, col=None):
        mn = v3(mn); mx = v3(mx)
        s.obox((mn + mx) / 2.0, (mx - mn), mat, None, c, smooth, col)

    # ---- generic loft between rings
    def loft(s, rings, mat, closed=True, smooth=True, cap0=False, cap1=False, uscale=1.0, matcap=None,
             cap_tri=False, ring_loop=False, col=None, flip=False, strip_caps=False, row_smooth=None, row_mats=None, col_mats=None, vcoords=None,
             face_mat=None):
        """rings: list of rings; each ring = list of 3D points (same count) or a single point (apex).
        smooth: bool or list(len = edges of ring)."""
        verts = []
        for r in rings:
            if isinstance(r, (list, tuple)) and len(r) and not isinstance(r[0], (int, float)):
                verts.append([s.vert(p) for p in r])
            else:
                verts.append([s.vert(r)])
        # u,v coordinates
        ref = [v.co.copy() for v in max(verts, key=len)]
        n = len(ref)
        us = [0.0]
        for i in range(1, n + 1):
            us.append(us[-1] + (ref[i % n] - ref[i - 1]).length * uscale)
        vs = [0.0]
        cen = []
        for ring in verts:
            cc = sum((v.co for v in ring), Vector()) / len(ring)
            cen.append(cc)
        for i in range(1, len(verts)):
            vs.append(vs[-1] + (cen[i] - cen[i - 1]).length * uscale)
        if ring_loop:
            vs.append(vs[-1] + (cen[0] - cen[-1]).length * uscale)
        if vcoords is not None:
            vs = list(vcoords)
        nr = len(verts)
        last = nr if ring_loop else nr - 1
        nseg = n if closed else n - 1
        for i in range(last):
            a = verts[i]; b = verts[(i + 1) % nr]
            for j in range(nseg):
                j2 = (j + 1) % n
                if row_smooth is not None: sm = row_smooth[i]
                else: sm = smooth[j] if isinstance(smooth, (list, tuple)) else smooth
                mt_ = row_mats[i] if row_mats is not None else (col_mats[j] if col_mats is not None else mat)
                if face_mat is not None: mt_ = face_mat(i, j)
                if len(a) == 1:
                    vv = [a[0], b[j2], b[j]]
                    uv = [(us[j], vs[i]), (us[j + 1], vs[i + 1]), (us[j], vs[i + 1])]
                elif len(b) == 1:
                    vv = [a[j], a[j2], b[0]]
                    uv = [(us[j], vs[i]), (us[j + 1], vs[i]), (us[j], vs[i + 1])]
                else:
                    vv = [a[j], a[j2], b[j2], b[j]]
                    uv = [(us[j], vs[i]), (us[j + 1], vs[i]), (us[j + 1], vs[i + 1]), (us[j], vs[i + 1])]
                if flip:
                    vv = vv[::-1]; uv = uv[::-1]
                s.face(vv, mt_, sm, uvs=uv, col=col)
        mc = matcap or mat
        if strip_caps and (cap0 or cap1):
            for ri, cp in ((0, cap0), (len(verts) - 1, cap1)):
                if not cp: continue
                ring = verts[ri]
                L2 = len(ring) // 2
                for i in range(L2 - 1):
                    q = [ring[i], ring[i + 1], ring[2 * L2 - 2 - i], ring[2 * L2 - 1 - i]]
                    s.face(q, mc, False, uvs=s._auto_uv([v.co for v in q]), col=col)
            cap0 = cap1 = False
        if cap0 and len(verts[0]) > 2:
            s.face(verts[0][::-1], mc, False, uvs=s._auto_uv([v.co for v in verts[0][::-1]]), col=col, tri=cap_tri or not is_convex_3d(verts[0]))
        if cap1 and len(verts[-1]) > 2:
            s.face(verts[-1], mc, False, uvs=s._auto_uv([v.co for v in verts[-1]]), col=col, tri=cap_tri or not is_convex_3d(verts[-1]))
        return verts

    def cyl(s, p0, p1, r0, r1, mat, seg=12, cap0=True, cap1=True, smooth=True, matcap=None, roll=0.0, col=None, squash=1.0):
        p0 = v3(p0); p1 = v3(p1)
        ax = (p1 - p0)
        z = ax.normalized()
        ref = Vector((0, 0, 1)) if abs(z.z) < 0.99 else Vector((1, 0, 0))
        xa = ref.cross(z).normalized(); ya = z.cross(xa)
        def ring(c, r):
            if r < 1e-6: return c
            return [c + (xa * cos(roll + 2 * pi * i / seg) + ya * sin(roll + 2 * pi * i / seg) * squash) * r for i in range(seg)]
        return s.loft([ring(p0, r0), ring(p1, r1)], mat, True, smooth, cap0 and r0 > 1e-6, cap1 and r1 > 1e-6, matcap=matcap, col=col)

    def dome(s, center, r, mat, seg=12, rings=4, zscale=1.0, hemi=True, smooth=True, cap=True, col=None, xyscale=(1, 1)):
        c = v3(center)
        a_end = 90.0
        a_start = 0.0 if hemi else -90.0
        # latitudes
        lat = []
        if hemi:
            for k in range(rings):
                lat.append(radians(a_start + (a_end - a_start) * k / rings))
        else:
            for k in range(1, rings * 2):
                lat.append(radians(-90 + 180 * k / (rings * 2)))
        ringlist = []
        if not hemi:
            ringlist.append(c + Vector((0, 0, -r * zscale)))
        for a in lat:
            rr = r * cos(a)
            ringlist.append([c + Vector((rr * cos(2 * pi * i / seg) * xyscale[0], rr * sin(2 * pi * i / seg) * xyscale[1], r * sin(a) * zscale)) for i in range(seg)])
        ringlist.append(c + Vector((0, 0, r * zscale)))
        return s.loft(ringlist, mat, True, smooth, cap0=(hemi and cap), col=col)

    def torus(s, center, R, r, mat, nmaj=16, nmin=8, axis='Z', smooth=True, col=None, squash=1.0):
        c = v3(center)
        rings = []
        for i in range(nmaj):
            a = 2 * pi * i / nmaj
            d = Vector((cos(a), sin(a), 0))
            ring = []
            for j in range(nmin):
                b = 2 * pi * j / nmin
                q = d * (R + r * cos(b)) + Vector((0, 0, r * sin(b) * squash))
                if axis == 'X': q = Vector((q.z, q.y, q.x))
                elif axis == 'Y': q = Vector((q.x, q.z, q.y))
                ring.append(c + q)
            rings.append(ring)
        s.loft(rings, mat, True, smooth, ring_loop=True, col=col)

    def sweep(s, prof, path, mat, closed=True, smooth=True, up=(0, 0, 1), cap0=True, cap1=True, scale=None, tri_caps=False,
              matcap=None, col=None, uscale=1.0, frames=None, strip_caps=False):
        """prof: list of (a,b) 2D profile points (a = side/left, b = up); path: list of Vectors."""
        path = [v3(p) for p in path]
        fr = frames or path_frames(path, up)
        rings = []
        for i, p in enumerate(path):
            t, S, U = fr[i]
            sc = scale(i / max(1, len(path) - 1)) if scale else 1.0
            if isinstance(sc, (int, float)): sc = (sc, sc)
            rings.append([p + S * (a * sc[0]) + U * (b * sc[1]) for (a, b) in prof])
        return s.loft(rings, mat, closed, smooth, cap0, cap1, matcap=matcap, cap_tri=tri_caps, col=col, uscale=uscale, strip_caps=strip_caps)

    def tube(s, path, r, mat, seg=8, smooth=True, caps=True, up=(0, 0, 1), scale=None, col=None, roll=0.0):
        prof = [(r * cos(roll + 2 * pi * i / seg), r * sin(roll + 2 * pi * i / seg)) for i in range(seg)]
        return s.sweep(prof, path, mat, True, smooth, up, caps, caps, scale, col=col)

    def lathe(s, rz, mat, seg=16, center=(0, 0), smooth=True, cap0=True, cap1=True, matcap=None, roll=0.0, row_smooth=None,
              row_mats=None, col=None, squash=(1.0, 1.0)):
        """Surface of revolution about the vertical axis through `center`. rz = [(r, z), ...] bottom->top (r=0 -> apex).
        row_mats/row_smooth: optional per-row lists (len(rz)-1)."""
        cx, cy = center
        rings = []
        for (r, z) in rz:
            if r < 1e-6:
                rings.append(Vector((cx, cy, z)))
            else:
                rings.append([Vector((cx + r * cos(roll + 2 * pi * i / seg) * squash[0], cy + r * sin(roll + 2 * pi * i / seg) * squash[1], z)) for i in range(seg)])
        vc = [0.0]
        for i in range(1, len(rz)):
            vc.append(vc[-1] + sqrt((rz[i][0] - rz[i - 1][0]) ** 2 + (rz[i][1] - rz[i - 1][1]) ** 2))
        return s.loft(rings, mat, True, smooth, cap0 and rz[0][0] > 1e-6, cap1 and rz[-1][0] > 1e-6, matcap=matcap,
                      row_smooth=row_smooth, row_mats=row_mats, col=col, vcoords=vc)

    def revolve(s, prof, mat, seg=24, center=(0, 0, 0), smooth=True, col_mats=None, rfn=None, col=None):
        """Revolve a CLOSED (r,z) profile about the vertical axis (tyres, rings). smooth: bool or per-profile-edge list.
        rfn(i, j, r) -> modified radius (used for tread blocks)."""
        c = v3(center)
        rings = []
        for i in range(seg):
            a = 2 * pi * i / seg
            ring = []
            for j, (r, z) in enumerate(prof):
                rr = rfn(i, j, r) if rfn else r
                ring.append(c + Vector((rr * cos(a), rr * sin(a), z)))
            rings.append(ring)
        return s.loft(rings, mat, True, smooth, ring_loop=True, col_mats=col_mats, col=col)

    def vsweep(s, prof, zs, mat, center=(0, 0), scale=None, smooth=True, cap0=True, cap1=True, matcap=None, col=None, rot=0.0,
               tri_caps=False):
        """Extrude a 2D profile (x,y offsets, closed) up the Z axis through the heights zs, optional scale(t)->(sx,sy)."""
        path = [Vector((center[0], center[1], z)) for z in zs]
        ca, sa = cos(radians(rot)), sin(radians(rot))
        X = Vector((ca, sa, 0)); Y = Vector((-sa, ca, 0))
        fr = [(Z3.copy(), X.copy(), Y.copy()) for _ in path]
        return s.sweep(prof, path, mat, True, smooth, cap0=cap0, cap1=cap1, scale=scale, matcap=matcap, col=col, frames=fr, tri_caps=tri_caps)

    def grime(s, mats, z_dark=0.25, amt=0.4):
        """vertex-colour dirt gradient near the ground on tinted materials"""
        for f in s.bm.faces:
            if s.mats[f.material_index] in mats:
                for l in f.loops:
                    k = 1.0 - amt * max(0.0, 1.0 - max(0.0, l.vert.co.z) / z_dark)
                    c = l[s.coll]
                    l[s.coll] = (c[0] * k, c[1] * k, c[2] * k, 1.0)

    def jitter(s, verts, amt):
        for v in verts:
            v.co += Vector((s.rng.uniform(-amt, amt), s.rng.uniform(-amt, amt), s.rng.uniform(-amt, amt)))

    def bar(s, p0, p1, w, d, mat, c=0.0, col=None, roll=0.0):
        """Oriented rectangular bar from p0 to p1 with cross-section w x d (w along the 'side' axis, d along the 'up' axis)."""
        p0 = v3(p0); p1 = v3(p1)
        z = (p1 - p0)
        L = z.length
        z.normalize()
        ref = Vector((0, 0, 1)) if abs(z.z) < 0.97 else Vector((1, 0, 0))
        x = ref.cross(z).normalized()
        y = z.cross(x)
        if roll:
            R = Matrix.Rotation(roll, 3, z)
            x = R @ x; y = R @ y
        M = Matrix((x, y, z)).transposed()
        s.obox((p0 + p1) / 2.0, (w, d, L), mat, M, c, col=col)

    # ---- planar prisms
    def prism(s, plane, poly, w0, w1, mt, ms=None, mb=None, smooth_side=False, col=None, tri=None, flipped=False, flat=False):
        """Extruded polygon. flat=True -> only the top face at w1 is emitted (single-sided decal card, tagged 'decal')."""
        poly = clean_poly(ccw(poly))
        ms = ms or mt; mb = mb or ms
        top = [s.vert(plane.p(u, v, w1)) for (u, v) in poly]
        n = len(poly)
        if tri is None:
            tri = not is_convex(poly)
        if flat:
            s.face(top, mt, False, uvs=[(u, v) for (u, v) in poly], col=col, tri=tri, decal=True)
            return
        bot = [s.vert(plane.p(u, v, w0)) for (u, v) in poly]
        s.face(top, mt, False, uvs=[(u, v) for (u, v) in poly], col=col, tri=tri)
        s.face(bot[::-1], mb, False, uvs=[(u, v) for (u, v) in poly][::-1], col=col, tri=tri)
        for i in range(n):
            j = (i + 1) % n
            s.face([bot[i], bot[j], top[j], top[i]], ms, smooth_side, col=col)

    def ring_prism(s, plane, outer, inner, w0, w1, mt, ms=None, mb=None, smooth_side=False, col=None, flat=False):
        outer = ccw(outer); inner = ccw(inner)
        ms = ms or mt; mb = mb or ms
        n = len(outer)
        assert len(inner) == n
        if flat:
            ot = [s.vert(plane.p(u, v, w1)) for (u, v) in outer]
            it = [s.vert(plane.p(u, v, w1)) for (u, v) in inner]
            for i in range(n):
                j = (i + 1) % n
                s.face([ot[i], ot[j], it[j], it[i]], mt, False, uvs=[outer[i], outer[j], inner[j], inner[i]], col=col, decal=True)
            return
        ot = [s.vert(plane.p(u, v, w1)) for (u, v) in outer]
        ob = [s.vert(plane.p(u, v, w0)) for (u, v) in outer]
        it = [s.vert(plane.p(u, v, w1)) for (u, v) in inner]
        ib = [s.vert(plane.p(u, v, w0)) for (u, v) in inner]
        for i in range(n):
            j = (i + 1) % n
            s.face([ot[i], ot[j], it[j], it[i]], mt, False, uvs=[outer[i], outer[j], inner[j], inner[i]], col=col)
            s.face([ib[i], ib[j], ob[j], ob[i]], mb, False, uvs=[inner[i], inner[j], outer[j], outer[i]], col=col)
            s.face([ob[i], ob[j], ot[j], ot[i]], ms, smooth_side, col=col)
            s.face([it[i], it[j], ib[j], ib[i]], ms, smooth_side, col=col)

    def disc(s, plane, cx, cy, r, w0, w1, mt, ms=None, seg=24, mb=None):
        s.prism(plane, ellipse_pts(cx, cy, r, r, seg), w0, w1, mt, ms, mb, smooth_side=True)

    # ---- collision hull definitions (convex hulls in asset-local space)
    def hull_box(s, mn, mx):
        mn = v3(mn); mx = v3(mx)
        s.hulls.append([Vector((x, y, z)) for x in (mn.x, mx.x) for y in (mn.y, mx.y) for z in (mn.z, mx.z)])

    def hull_cyl(s, p0, p1, r, seg=8):
        p0 = v3(p0); p1 = v3(p1)
        z = (p1 - p0).normalized()
        ref = Vector((0, 0, 1)) if abs(z.z) < 0.99 else Vector((1, 0, 0))
        xa = ref.cross(z).normalized(); ya = z.cross(xa)
        pts = []
        for c in (p0, p1):
            for i in range(seg):
                a = 2 * pi * i / seg
                pts.append(c + (xa * cos(a) + ya * sin(a)) * r)
        s.hulls.append(pts)

    def hull_pts(s, pts):
        s.hulls.append([v3(p) for p in pts])

    def hull_prism(s, plane, poly, w0, w1):
        """Convex hull of a planar polygon extruded from w0 to w1 (always a closed volume, unlike hull_pts on coplanar points)."""
        s.hulls.append([plane.p(u, v, w) for (u, v) in poly for w in (w0, w1)])

    # ---- pillow-faced masonry block: closed 6-face frustum, 12 tris (chamfered front face, plain back)
    def stone(s, center, size, mat, rot=None, bevel=0.03, col=None, jit=0.0):
        """size = (L along local x, D depth along local y (front/outward = +y), H along z). The back face (-y) has full size,
        the front face (+y) is inset by `bevel` on all four sides => rock-faced stone with chamfered edges in only 12 tris."""
        if rot is None:
            R = Matrix.Identity(4)
        elif isinstance(rot, Matrix):
            R = rot.to_4x4()
        else:
            R = Euler((radians(rot[0]), radians(rot[1]), radians(rot[2])), 'XYZ').to_matrix().to_4x4()
        M = Matrix.Translation(v3(center)) @ R
        L, D, H = size
        b = min(bevel, L * 0.3, H * 0.3)
        rng = s.rng
        def jv(a):
            return a + (rng.uniform(-jit, jit) if jit else 0.0)
        back = {}
        front = {}
        for sx in (-1, 1):
            for sz in (-1, 1):
                back[(sx, sz)] = s.vert(M @ Vector((sx * L / 2, -D / 2, sz * H / 2)))
                front[(sx, sz)] = s.vert(M @ Vector((sx * (L / 2 - b), D / 2 + jv(0.0), sz * (H / 2 - b))))
        order = [(-1, -1), (1, -1), (1, 1), (-1, 1)]       # winding is fixed by finalize_normals (closed island -> outward)
        fr = [front[k] for k in order]
        bk = [back[k] for k in order]
        s.face(fr, mat, False, col=col)
        s.face(bk[::-1], mat, False, col=col)
        for i in range(4):
            j = (i + 1) % 4
            s.face([bk[i], bk[j], fr[j], fr[i]], mat, False, col=col)

    def speckle(s, mats, amt=0.1, lo=0.0, hi=1e9, start=0):
        """per-face random brightness on vertex colour (straw strands, paint scuffs, stone variation) for faces from index `start`."""
        s.bm.faces.ensure_lookup_table()
        rng = s.rng
        for fi in range(start, len(s.bm.faces)):
            f = s.bm.faces[fi]
            if s.mats[f.material_index] not in mats:
                continue
            k = 1.0 + rng.uniform(-amt, amt)
            for l in f.loops:
                c = l[s.coll]
                l[s.coll] = (min(1.0, c[0] * k), min(1.0, c[1] * k), min(1.0, c[2] * k), 1.0)

    def pyramid(s, base_center, base_dir_u, base_dir_v, hw, apex, mat, col=None):
        """closed 4-face tetra (triangular base) - straw tufts / chips. base is an equilateral-ish triangle in the (u,v) plane."""
        c = v3(base_center); u = v3(base_dir_u).normalized(); v = v3(base_dir_v).normalized()
        p0 = c + u * hw; p1 = c - u * hw * 0.5 + v * hw * 0.866; p2 = c - u * hw * 0.5 - v * hw * 0.866
        a = v3(apex)
        V0, V1, V2, A = s.vert(p0), s.vert(p1), s.vert(p2), s.vert(a)
        s.face([V0, V2, V1], mat, False, col=col)
        s.face([V0, V1, A], mat, False, col=col)
        s.face([V1, V2, A], mat, False, col=col)
        s.face([V2, V0, A], mat, False, col=col)


def mirror_x(mb, x0):
    """Mirror everything built so far about the plane x = x0/2  (x -> x0 - x). Winding is reversed so normals stay outward.
    Used to derive the handed variants (_R) of end terminals without negative scale."""
    for v in mb.bm.verts:
        v.co.x = x0 - v.co.x
    bmesh.ops.reverse_faces(mb.bm, faces=mb.bm.faces[:])
    mb.hulls = [[Vector((x0 - p.x, p.y, p.z)) for p in h] for h in mb.hulls]
    mb.sockets = {k: (x0 - p[0], p[1], p[2]) for k, p in mb.sockets.items()}


def is_convex_3d(vs):
    ps = [v.co for v in vs]
    if len(ps) <= 3: return True
    n = Vector()
    m = len(ps)
    for i in range(m):
        a = ps[i]; b = ps[(i + 1) % m]
        n.x += (a.y - b.y) * (a.z + b.z); n.y += (a.z - b.z) * (a.x + b.x); n.z += (a.x - b.x) * (a.y + b.y)
    if n.length < 1e-12: return True
    n.normalize()
    sgn = 0
    for i in range(m):
        a, b, c = ps[i], ps[(i + 1) % m], ps[(i + 2) % m]
        cr = (b - a).cross(c - b).dot(n)
        if abs(cr) < 1e-10: continue
        sg = 1 if cr > 0 else -1
        if sgn == 0: sgn = sg
        elif sg != sgn: return False
    return True

# (stroke font lives in rs_font.py)

# ----------------------------------------------------------------------------------------------------------------------
# asset registry + harness
# ----------------------------------------------------------------------------------------------------------------------
REG = {}      # id -> spec (ordered)

def asset(aid, name, x=0.0, ext=(0.0, 1.0), group='misc', budget=2000, collision='box', tags=(), scale=(0.9, 1.1), pivot='ground_centre',
          usage='', nanite=True):
    """Register an asset builder. x = fixed staging X (world, y=80). ext = local x-extent (min,max) used for layout checks."""
    def deco(fn):
        REG[aid] = dict(id=aid, name=name, fn=fn, x=x, ext=ext, group=group, budget=budget, collision=collision, tags=list(tags),
                        scale=scale, pivot=pivot, usage=usage, nanite=nanite)
        return fn
    return deco

def stage_pos(aid):
    return Vector((REG[aid]['x'], STAGE_Y, 0.0))

def layout_check():
    items = sorted(((sp['x'] + sp['ext'][0], sp['x'] + sp['ext'][1], k) for k, sp in REG.items()))
    bad = []
    for i in range(1, len(items)):
        if items[i][0] < items[i - 1][1] + 1.0:
            bad.append((items[i - 1][2], items[i][2]))
    return bad

def _roadside_parent():
    root = bpy.data.collections.get('FORZA_UE')
    if root is None:
        root = bpy.data.collections.new('FORZA_UE')
        bpy.context.scene.collection.children.link(root)
    rs = None
    for ch in root.children:
        if ch.name == 'Roadside':
            rs = ch
    if rs is None:
        rs = bpy.data.collections.get('Roadside')
        if rs is None:
            rs = bpy.data.collections.new('Roadside')
        if rs.name not in [c.name for c in root.children]:
            root.children.link(rs)
    return rs

def get_collection(aid):
    col = bpy.data.collections.get(aid)
    if col is None:
        col = bpy.data.collections.new(aid)
    par = _roadside_parent()
    if col.name not in [c.name for c in par.children]:
        par.children.link(col)
    return col

def clear_asset(aid):
    col = bpy.data.collections.get(aid)
    if col is None:
        return
    for o in list(col.objects):
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data is not None and data.users == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)

def _islands(bm):
    seen = set(); res = []
    for f in bm.faces:
        if f in seen: continue
        stack = [f]; seen.add(f); comp = []
        while stack:
            x = stack.pop(); comp.append(x)
            for e in x.edges:
                for g in e.link_faces:
                    if g not in seen:
                        seen.add(g); stack.append(g)
        res.append(comp)
    return res

def _signed_volume(faces):
    vol = 0.0
    for f in faces:
        vs = [l.vert.co for l in f.loops]
        for i in range(1, len(vs) - 1):
            vol += vs[0].dot(vs[i].cross(vs[i + 1]))
    return vol / 6.0

def finalize_normals(bm):
    bm.normal_update()
    dl = bm.faces.layers.int.get('decal')
    solid = [f for f in bm.faces if not (dl is not None and f[dl])]
    bmesh.ops.recalc_face_normals(bm, faces=solid)          # decal cards keep their authored winding (+plane normal)
    flipped = 0
    open_isl = 0
    for comp in _islands(bm):
        if dl is not None and comp[0][dl]:
            continue
        boundary = any(len(e.link_faces) != 2 for f in comp for e in f.edges)
        if boundary:
            open_isl += 1
            continue
        if _signed_volume(comp) < 0:
            for f in comp:
                f.normal_flip()
            flipped += 1
    bm.normal_update()
    return flipped, open_isl

def make_hull(name, pts):
    bm = bmesh.new()
    seen = set(); uniq = []
    for p in pts:
        k = (round(p[0], 5), round(p[1], 5), round(p[2], 5))
        if k not in seen:
            seen.add(k); uniq.append(p)
    vs = [bm.verts.new(p) for p in uniq]
    res = bmesh.ops.convex_hull(bm, input=vs)
    junk = list(set(g for g in res.get('geom_interior', []) + res.get('geom_unused', []) if isinstance(g, bmesh.types.BMVert)))
    if junk:
        bmesh.ops.delete(bm, geom=junk, context='VERTS')
    try:
        bmesh.ops.dissolve_limit(bm, angle_limit=radians(0.25), verts=bm.verts[:], edges=bm.edges[:])
    except Exception:
        pass
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    nv = len(bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    return mesh, nv

def build_one(aid):
    sp = REG[aid]
    t0 = time.time()
    clear_asset(aid)
    col = get_collection(aid)
    mb = MB(aid)
    info = sp['fn'](mb) or {}
    flipped, open_isl = finalize_normals(mb.bm)
    mesh = bpy.data.meshes.new(aid)
    mb.bm.to_mesh(mesh)
    mb.bm.free()
    for m in mb.mats:
        mesh.materials.append(ensure_material(m))
    mesh.update()
    pos = stage_pos(aid)
    obj = bpy.data.objects.new(aid, mesh)
    col.objects.link(obj)
    obj.location = pos
    obj['rs_asset'] = aid
    n = 0
    hull_report = []
    for i, pts in enumerate(mb.hulls, 1):
        hn = 'UCX_%s_%02d' % (aid, i)
        hm, nv = make_hull(hn, pts)
        ho = bpy.data.objects.new(hn, hm)
        col.objects.link(ho)
        ho.location = pos
        ho.display_type = 'WIRE'
        ho.hide_render = True
        hull_report.append(nv)
        try:
            ho.hide_set(True)
        except Exception:
            pass
    obj['rs_sockets'] = json.dumps({k: [round(c, 4) for c in v] for k, v in mb.sockets.items()})
    obj['rs_info'] = json.dumps({k: v for k, v in info.items() if isinstance(v, (str, int, float, list, tuple, dict))}, default=str)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    return dict(id=aid, tris=tris, verts=len(mesh.vertices), flipped=flipped, open_islands=open_isl, hulls=hull_report, secs=round(time.time() - t0, 2))

def build(ids=None):
    ids = ids or list(REG.keys())
    if isinstance(ids, str): ids = [ids]
    out = []
    for a in ids:
        r = build_one(a)
        out.append(r)
        print('BUILT %-34s tris=%5d verts=%5d flipped=%d open_isl=%d hulls=%s %.2fs' % (r['id'], r['tris'], r['verts'], r['flipped'], r['open_islands'], r['hulls'], r['secs']))
    return out

# ---- visibility helpers (own objects only)
def isolate(aid=None):
    """Hide all other rs_ assets (view layer) so `look` shows only aid. aid=None -> show all rs_ assets (UCX stay hidden)."""
    for k in REG:
        col = bpy.data.collections.get(k)
        if not col: continue
        for o in col.objects:
            try:
                if o.name.startswith('UCX_'):
                    o.hide_set(True)
                else:
                    o.hide_set(aid is not None and k != aid and not (isinstance(aid, (list, tuple)) and k in aid))
            except Exception:
                pass

def focus(aid=None, off=(0, 0, 0), size=0.5):
    """Place/move the helper empty `rs__focus` at the asset origin + off (world offset relative to asset). aid=None removes it.
    Use look(target=['rs__focus'], distance=..) to frame a detail of an asset."""
    o = bpy.data.objects.get('rs__focus')
    if aid is None:
        if o: bpy.data.objects.remove(o, do_unlink=True)
        return
    if o is None:
        o = bpy.data.objects.new('rs__focus', None)
        o.empty_display_type = 'PLAIN_AXES'
        o.empty_display_size = size
        _roadside_parent().objects.link(o)
    base = stage_pos(aid) if aid in REG else Vector((0, STAGE_Y, 0))
    o.location = base + Vector(off)
    o.empty_display_size = size

def show_ucx(aid, on=True):
    col = bpy.data.collections.get(aid)
    for o in col.objects:
        if o.name.startswith('UCX_'):
            o.hide_set(not on)

# ----------------------------------------------------------------------------------------------------------------------
# validation
# ----------------------------------------------------------------------------------------------------------------------
def local_bbox(obj):
    vs = [v.co for v in obj.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return mn, mx

def validate(aid, verbose=True):
    sp = REG[aid]
    issues = []
    o = bpy.data.objects.get(aid)
    if o is None:
        return dict(id=aid, ok=False, issues=['missing object'])
    me = o.data
    col = bpy.data.collections.get(aid)
    # names
    ucx = [x for x in col.objects if x.name.startswith('UCX_')]
    for i, x in enumerate(sorted(ucx, key=lambda q: q.name), 1):
        if x.name != 'UCX_%s_%02d' % (aid, i): issues.append('bad UCX name ' + x.name)
    if sp['collision'] in ('box', 'convex') and not ucx:
        issues.append('no UCX hulls')
    if sp['collision'] == 'none' and ucx:
        issues.append('collision=none but UCX hulls present')
    # transforms
    if any(abs(a) > 1e-6 for a in o.rotation_euler) or any(abs(s - 1) > 1e-6 for s in o.scale):
        issues.append('transform not applied')
    if o.parent is not None: issues.append('has parent')
    pos = stage_pos(aid)
    if (o.location - pos).length > 1e-4: issues.append('not at staging pos')
    # bbox / pivot
    mn, mx = local_bbox(o)
    if sp['pivot'] == 'ground_centre':
        if mn.z < -0.25 or mn.z > 0.03: issues.append('min z %.3f not at ground' % mn.z)
        cx = (mn.x + mx.x) / 2; cy = (mn.y + mx.y) / 2
        if abs(cx) > 0.08 * max(1.0, mx.x - mn.x) + 0.15 or abs(cy) > 0.08 * max(1.0, mx.y - mn.y) + 0.15:
            issues.append('pivot off-centre (%.2f, %.2f)' % (cx, cy))
    elif sp['pivot'] == 'segment_start':
        if abs(mn.x) > 0.4: issues.append('segment does not start at x=0 (min x %.3f)' % mn.x)
        if mn.z < -0.25 or mn.z > 0.03: issues.append('min z %.3f not at ground' % mn.z)
    elif sp['pivot'] == 'ground_base':
        if mn.z < -0.25 or mn.z > 0.03: issues.append('min z %.3f not at ground' % mn.z)
        if abs(mn.x) > 3.5 or abs(mn.y) > 3.5: issues.append('base point off (%.2f,%.2f)' % (mn.x, mn.y))
    elif sp['pivot'] == 'attach_point':
        if abs(mn.x) > 0.2: issues.append('span does not start at x=0')
    # materials
    used = set(p.material_index for p in me.polygons)
    if len(me.materials) > 8: issues.append('%d material slots (>8)' % len(me.materials))
    for i, m in enumerate(me.materials):
        if m is None or not m.name.startswith('M_RS_'): issues.append('bad material slot %d' % i)
        if i not in used: issues.append('unused slot %d' % i)
    # uv
    if 'UVMap' not in me.uv_layers: issues.append('no UVMap')
    else:
        uvl = me.uv_layers['UVMap'].data
        bad = 0
        for p in me.polygons:
            pts = [uvl[li].uv for li in p.loop_indices]
            if len(pts) < 3: continue
            a = 0.0
            for i in range(len(pts)):
                a += pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
            if abs(a) < 1e-10 and p.area > 1e-8: bad += 1
        if bad > 0: issues.append('%d faces with degenerate UVs' % bad)
    # topology
    bm = bmesh.new(); bm.from_mesh(me)
    dl = bm.faces.layers.int.get('decal')
    isd = lambda f: dl is not None and f[dl] == 1
    nm = sum(1 for e in bm.edges if len(e.link_faces) != 2 and not all(isd(f) for f in e.link_faces))
    ndec = sum(1 for f in bm.faces if isd(f))
    loose = sum(1 for v in bm.verts if not v.link_faces)
    zero = sum(1 for f in bm.faces if f.calc_area() < 1e-9)
    neg = 0
    for comp in _islands(bm):
        if isd(comp[0]):
            # decal card: normal must point along its plane normal (+X for signs) - checked only for being consistent within island
            continue
        if not any(len(e.link_faces) != 2 for f in comp for e in f.edges):
            if _signed_volume(comp) < -1e-9: neg += 1
    nisl = len(_islands(bm))
    bm.free()
    if nm: issues.append('%d open/non-manifold edges' % nm)
    if loose: issues.append('%d loose verts' % loose)
    if zero: issues.append('%d zero-area faces' % zero)
    if neg: issues.append('%d inverted islands' % neg)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if tris > sp['budget']: issues.append('tris %d > budget %d' % (tris, sp['budget']))
    for x in ucx:
        if len(x.data.vertices) > 32: issues.append('%s has %d verts (>32)' % (x.name, len(x.data.vertices)))
        issues.extend(_check_hull(x))
    res = dict(id=aid, ok=not issues, issues=issues, tris=tris, dims=tuple(round(v, 3) for v in (mx - mn)), islands=nisl,
               mats=[m.name for m in me.materials], nm_edges=nm, hulls=len(ucx), decal_faces=ndec)
    if verbose:
        print('%s %-32s tris=%5d dims=%s mats=%d hulls=%d decal=%d %s' % ('OK ' if res['ok'] else 'BAD', aid, tris, res['dims'], len(me.materials), len(ucx), ndec, '; '.join(issues)))
    return res

def _check_hull(x):
    """UCX hull must be a closed, convex, positive-volume mesh (UE rejects flat quads / open shells)."""
    out = []
    me = x.data
    bm = bmesh.new(); bm.from_mesh(me)
    bm.normal_update()
    nv = len(bm.verts); nf = len(bm.faces)
    if nv < 4 or nf < 4:
        out.append('%s: degenerate hull (%d verts, %d faces)' % (x.name, nv, nf))
        bm.free(); return out
    open_e = sum(1 for e in bm.edges if len(e.link_faces) != 2)
    if open_e: out.append('%s: %d open edges' % (x.name, open_e))
    vol = _signed_volume(list(bm.faces))
    if vol < 1e-4: out.append('%s: volume %.5f (flat / inverted)' % (x.name, vol))
    # convexity (on the triangulated hull): every vertex must be on or behind every face plane (1 mm tolerance)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    bad = 0
    for f in bm.faces:
        n = f.normal; d = n.dot(f.verts[0].co)
        for v in bm.verts:
            if n.dot(v.co) > d + 1e-3:
                bad += 1; break
    if bad: out.append('%s: not convex (%d faces)' % (x.name, bad))
    bm.free()
    return out

def validate_all(ids=None):
    ids = ids or [k for k in REG if bpy.data.objects.get(k)]
    return [validate(a) for a in ids]

# ----------------------------------------------------------------------------------------------------------------------
# export  (one FBX per asset + JSON sidecar)
# ----------------------------------------------------------------------------------------------------------------------
_FBX = None
def _fbx():
    global _FBX
    if _FBX is None:
        p = PROJECT + r"\Tools\blender\lib\fbx_export.py"
        g = {'__name__': 'fbx_export'}
        exec(compile(open(p, encoding='utf8').read(), p, 'exec'), g)
        _FBX = g
    return _FBX

def export(aid):
    sp = REG[aid]
    o = bpy.data.objects[aid]
    col = bpy.data.collections[aid]
    ucx = sorted([x for x in col.objects if x.name.startswith('UCX_')], key=lambda q: q.name)
    # make everything selectable
    prev_hide = {}
    for x in [o] + ucx:
        prev_hide[x.name] = x.hide_get()
        x.hide_set(False)
        x.hide_viewport = False
    path = os.path.join(EXPORT_DIR, aid + '.fbx')
    res = _fbx()['export_fbx']([o] + ucx, path, center_on='self', extra_kwargs={'use_triangles': True})
    for x in [o] + ucx:
        try:
            x.hide_set(True if x.name.startswith('UCX_') else prev_hide[x.name])
        except Exception:
            pass
    me = o.data
    mn, mx = local_bbox(o)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    info = json.loads(o.get('rs_info', '{}'))
    sockets = json.loads(o.get('rs_sockets', '{}'))
    slots = {}
    for i, m in enumerate(me.materials):
        slots[m.name] = sum(1 for p in me.polygons if p.material_index == i)
    ucx_tris = {x.name: sum(len(p.vertices) - 2 for p in x.data.polygons) for x in ucx}
    dattr = me.attributes.get('decal')
    ndec = sum(1 for d in dattr.data if d.value == 1) if dattr is not None else 0
    data = dict(
        id=aid, display_name=sp['name'], category='Roadside', group=sp['group'], units='m',
        pivot=sp['pivot'], axes=dict(forward='+X', up='+Z', note='Blender axes; FBX recipe maps +Y(left) -> UE -Y'),
        dimensions=dict(x=round(mx.x - mn.x, 4), y=round(mx.y - mn.y, 4), z=round(mx.z - mn.z, 4)),
        bounds_min=[round(c, 4) for c in mn], bounds_max=[round(c, 4) for c in mx],
        tri_counts=dict(lod0=tris, collision=ucx_tris),
        material_slots=[m.name for m in me.materials],
        material_slot_tris=slots,
        collision=dict(type=sp['collision'], hulls=[x.name for x in ucx]),
        biome_tags=sp['tags'], scale_range=list(sp['scale']), nanite=sp['nanite'],
        lod_info='Nanite-ready opaque mesh; no manual LODs (UE auto)' if sp['nanite'] else 'translucent parts present: use standard LODs',
        wind='none', sockets=sockets, usage=sp['usage'], uv='UVMap = metric box projection (1 UV unit = 1 m) for tiling materials; vertex colour Col = per-part tint (white default)',
        extra={k: v for k, v in info.items() if k not in ('hulls',)},
        decal_faces=ndec,
        fbx=aid + '.fbx',
    )
    jp = os.path.join(EXPORT_DIR, aid + '.json')
    with open(jp, 'w', encoding='utf8') as f:
        json.dump(data, f, indent=1)
    size = os.path.getsize(path) if res and os.path.exists(path) else -1
    print('EXPORT %-32s fbx=%s bytes=%d tris=%d' % (aid, 'ok' if res else 'FAIL', size, tris))
    return res is not None

def export_many(ids):
    return [export(a) for a in ids]

def write_manifest():
    """Exports/Roadside/_manifest.json : one summary row per exported asset (read from the sidecars) + kit conventions."""
    rows = []
    for aid in REG:
        jp = os.path.join(EXPORT_DIR, aid + '.json')
        if not os.path.exists(jp):
            continue
        d = json.load(open(jp, encoding='utf8'))
        rows.append(dict(id=aid, fbx=d['fbx'], group=d['group'], dimensions=d['dimensions'], tris=d['tri_counts']['lod0'],
                         materials=d['material_slots'], collision=d['collision']['type'], pivot=d['pivot'],
                         scale_range=d['scale_range'], nanite=d['nanite'], tags=d['biome_tags']))
    man = dict(kit='roadside', version=1, units='m', blender='5.2.2', staging='y=80', axes='Blender +X forward/+Z up (FBX recipe: axis_forward -Y, axis_up Z, apply_scale FBX_SCALE_ALL)',
               traffic_side='+Y for rails/barriers/fences (road lies to the +Y side when walking +X)', assets=rows,
               materials=sorted(set(m for r in rows for m in r['materials'])))
    with open(os.path.join(EXPORT_DIR, '_manifest.json'), 'w', encoding='utf8') as f:
        json.dump(man, f, indent=1)
    print('MANIFEST', len(rows), 'assets', len(man['materials']), 'materials')
    return man
