"""
carkit.py - shared CAR KIT for the Blender -> Unreal pipeline (Blender 5.2 / Python 3.13 / bpy).

Load it inside the verified Blender MCP session (localhost:9889) with
    KIT = r"<project>/Tools/blender/lib/carkit.py"
    exec(compile(open(KIT, encoding="utf8").read(), KIT, "exec"), globals())
Everything is plain functions/classes, no add-ons, no external assets.  Every builder is idempotent when it is used from an
idempotent car script (the script calls remove_asset(car_id) first).  See Docs/CARKIT_API.md for the recipe.

Conventions (Docs/BLENDER_CONTRACT.md): 1 unit = 1 m, +X forward, +Y left, +Z up, origin on the ground under the middle of
the wheelbase.  Geometry is always built in CAR SPACE (bmesh), objects are created with identity transform parented to the
root empty.  Material indices of every bmesh produced by this kit refer to the global slot list MAT_ORDER, the final object
gets only the used slots (see finish_object).

Sections:  1 core/math  2 materials  3 scene helpers  4 mesh builder + primitives  5 body loft  6 booleans/surface tools
           7 glass extraction  8 detail builders  9 wheel  10 interior  11 collision + UV  12 validate + export
"""
import bpy
import bmesh
import math
import os
import json
import time
from mathutils import Vector, Matrix, Euler
from mathutils.bvhtree import BVHTree

KIT_VERSION = "1.1.0"   # rev 3: blade headlights, new mirror, outline helpers, heal_nonmanifold, lamp-slot validation
TAG_COL = "kit_col"      # int face attribute: ring column + 1 of the lofted body quad (0 = untagged)
TAG_ST = "kit_st"        # int face attribute: station index + 1
_T0 = time.time()


def log(*a):
    print("[carkit %.1fs]" % (time.time() - _T0), *a)


def project_dir():
    """Project folder = folder of the master .blend (the verified file lives in the project root)."""
    return os.path.dirname(bpy.data.filepath)


# =====================================================================================================================
# 1. core / math
# =====================================================================================================================
def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def T(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """4x4 matrix: translate(loc) @ rotateXYZ(rot in DEGREES) @ scale."""
    m = Matrix.Translation(Vector(loc)) @ Euler([math.radians(a) for a in rot], 'XYZ').to_matrix().to_4x4()
    if tuple(scale) != (1, 1, 1):
        m = m @ Matrix.Diagonal(Vector((scale[0], scale[1], scale[2], 1.0)))
    return m


class Curve1D:
    """1-D function of x defined by key points.  mode: 'pchip' (monotone cubic, no overshoot, default), 'linear',
    'smooth' (smoothstep between keys).  Constant outside the key range."""

    def __init__(self, pts, mode='pchip'):
        pts = sorted((float(a), float(b)) for a, b in pts)
        clean = []
        for a, b in pts:
            if clean and abs(a - clean[-1][0]) < 1e-9:
                clean[-1] = (a, b)
            else:
                clean.append((a, b))
        self.x = [p[0] for p in clean]
        self.y = [p[1] for p in clean]
        self.mode = mode
        n = len(self.x)
        self.d = [0.0] * n
        if n >= 2 and mode == 'pchip':
            h = [self.x[i + 1] - self.x[i] for i in range(n - 1)]
            dl = [(self.y[i + 1] - self.y[i]) / h[i] for i in range(n - 1)]
            if n == 2:
                self.d = [dl[0], dl[0]]
            else:
                for i in range(1, n - 1):
                    if dl[i - 1] * dl[i] <= 0:
                        self.d[i] = 0.0
                    else:
                        w1 = 2 * h[i] + h[i - 1]
                        w2 = h[i] + 2 * h[i - 1]
                        self.d[i] = (w1 + w2) / (w1 / dl[i - 1] + w2 / dl[i])
                self.d[0] = self._end(h[0], h[1], dl[0], dl[1])
                self.d[-1] = self._end(h[-1], h[-2], dl[-1], dl[-2])

    @staticmethod
    def _end(h0, h1, d0, d1):
        d = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
        if d * d0 <= 0:
            d = 0.0
        elif d0 * d1 <= 0 and abs(d) > 3 * abs(d0):
            d = 3 * d0
        return d

    def __call__(self, x):
        xs = self.x
        if x <= xs[0]:
            return self.y[0]
        if x >= xs[-1]:
            return self.y[-1]
        lo, hi = 0, len(xs) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if xs[mid] <= x:
                lo = mid
            else:
                hi = mid
        h = xs[hi] - xs[lo]
        t = (x - xs[lo]) / h
        y0, y1 = self.y[lo], self.y[hi]
        if self.mode == 'linear':
            return y0 + (y1 - y0) * t
        if self.mode == 'smooth':
            return y0 + (y1 - y0) * (t * t * (3 - 2 * t))
        t2 = t * t
        t3 = t2 * t
        return ((2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * h * self.d[lo] +
                (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * h * self.d[hi])


class _Const:
    def __init__(self, v):
        self.v = float(v)

    def __call__(self, x):
        return self.v


def as_curve(v, mode='pchip'):
    """number -> constant, list of (x,y) -> Curve1D, callable -> itself."""
    if callable(v):
        return v
    if isinstance(v, (int, float)):
        return _Const(v)
    return Curve1D(v, mode)


def line_keys(p0, p1, n=3):
    """n interior points on the straight segment p0->p1 (use inside key lists to force a straight run)."""
    return [(p0[0] + (p1[0] - p0[0]) * (i / (n + 1.0)), p0[1] + (p1[1] - p0[1]) * (i / (n + 1.0))) for i in range(1, n + 1)]


def smooth_keys(keys, sigma=0.12, step=0.02, mode='pchip'):
    """Dense key list (feed it to as_curve / the loft) of the Gaussian-smoothed curve through `keys`.  Removes curvature
    wiggles that a hand-keyed pchip curve has between its keys (the usual source of wavy reflections), rounds corners with a
    radius of about sigma.  sigma = standard deviation in x (m).  The curve is held constant beyond the first/last key."""
    c = Curve1D(keys, mode)
    x0, x1 = c.x[0], c.x[-1]
    n = max(int(round((x1 - x0) / step)), 2)
    dx = (x1 - x0) / n
    hw = max(int(math.ceil(3.0 * sigma / dx)), 1)
    ker = [math.exp(-0.5 * ((j * dx) / sigma) ** 2) for j in range(-hw, hw + 1)]
    ks = sum(ker)
    out = []
    for i in range(n + 1):
        x = x0 + dx * i
        s = 0.0
        for j in range(-hw, hw + 1):
            s += ker[j + hw] * c(x + j * dx)
        out.append((x, s / ks))
    return out


def fillet_profile(pts, radii, step=0.01):
    """Designer-style profile: polyline `pts` [(x, z), ...] (x ascending) with a circular fillet of radius radii[i] at every
    interior vertex (radii has len(pts) entries, the first/last are ignored; 0 = sharp).  Returns a dense key list
    [(x, z), ...] - straight runs stay exactly straight, corners become tangent-continuous arcs.  Feed it to as_curve()
    (mode 'linear' or 'pchip') for the side-profile curves zt / zb ... of loft_body."""
    P = [Vector((p[0], p[1], 0.0)) for p in pts]
    n = len(P)
    out = [(P[0].x, P[0].y)]
    cur = P[0]                     # start of the next straight run
    for i in range(1, n - 1):
        A, B, C = P[i - 1], P[i], P[i + 1]
        r = radii[i]
        u1 = (A - B).normalized()
        u2 = (C - B).normalized()
        cosang = clamp(u1.dot(u2), -1.0, 1.0)
        th = math.acos(cosang)
        if r <= 1e-9 or th > math.pi - 1e-4 or th < 1e-4:
            out.append((B.x, B.y))
            continue
        t = r / math.tan(th / 2.0)
        t = min(t, 0.48 * (A - B).length, 0.48 * (C - B).length)
        r = t * math.tan(th / 2.0)
        T1, T2 = B + u1 * t, B + u2 * t
        bis = (u1 + u2).normalized()
        Cc = B + bis * (r / math.sin(th / 2.0))
        a1 = math.atan2(T1.y - Cc.y, T1.x - Cc.x)
        a2 = math.atan2(T2.y - Cc.y, T2.x - Cc.x)
        da = a2 - a1
        while da > math.pi:
            da -= 2 * math.pi
        while da < -math.pi:
            da += 2 * math.pi
        m = max(int(math.ceil(abs(da) * r / step)), 2)
        for k in range(m + 1):
            a = a1 + da * k / m
            out.append((Cc.x + r * math.cos(a), Cc.y + r * math.sin(a)))
    out.append((P[-1].x, P[-1].y))
    dense = [out[0]]
    for q in out[1:]:                                       # densify the straight runs so that pchip/linear stay straight
        p0 = dense[-1]
        d = math.hypot(q[0] - p0[0], q[1] - p0[1])
        m = int(d / (step * 4.0))
        for k in range(1, m + 1):
            dense.append((p0[0] + (q[0] - p0[0]) * k / (m + 1.0), p0[1] + (q[1] - p0[1]) * k / (m + 1.0)))
        dense.append(q)
    return dense


def end_round_stations(x_end, r, n=6, at_start=False):
    """Extra loft station positions that sample the quarter-circle rounding of radius r at an end of the loft (see
    loft_body round_x0 / round_x1).  x_end = the end station, at_start=True for the first (smallest x) end."""
    xs = []
    for i in range(1, n + 1):
        phi = math.radians(90.0 * i / n)
        d = r - r * math.sin(phi)                      # distance from the end station
        xs.append(x_end + d if at_start else x_end - d)
    return xs


def station_list(x0, x1, dx=0.06, end_dx=0.025, end_len=0.25, extra=(), min_gap=0.012):
    """Sorted station x positions from x0..x1: dx in the middle, end_dx near both ends, plus `extra` feature positions."""
    xs = [x0, x1]
    x = x0
    while x < x1:
        step = end_dx if (x < x0 + end_len or x > x1 - end_len) else dx
        x += step
        if x < x1 - 1e-6:
            xs.append(x)
    xs += list(extra)
    xs = sorted(set(round(v, 5) for v in xs if x0 <= v <= x1))
    out = [xs[0]]
    keep = set(round(v, 5) for v in extra) | {round(x0, 5), round(x1, 5)}
    for v in xs[1:]:
        if v - out[-1] < min_gap:
            if v in keep:
                if out[-1] not in keep:
                    out[-1] = v
            continue
        out.append(v)
    return out


def _cr_point(P0, P1, P2, P3, t, alpha=0.5):
    def tj(ti, a, b):
        return ti + max(math.hypot(b[0] - a[0], b[1] - a[1]), 1e-9) ** alpha

    t0 = 0.0
    t1 = tj(t0, P0, P1)
    t2 = tj(t1, P1, P2)
    t3 = tj(t2, P2, P3)
    u = t1 + (t2 - t1) * t

    def l2(a, b, ta, tb):
        w = (u - ta) / (tb - ta)
        return (a[0] * (1 - w) + b[0] * w, a[1] * (1 - w) + b[1] * w)

    A1 = l2(P0, P1, t0, t1)
    A2 = l2(P1, P2, t1, t2)
    A3 = l2(P2, P3, t2, t3)
    B1 = l2(A1, A2, t0, t2)
    B2 = l2(A2, A3, t1, t3)
    return l2(B1, B2, t1, t2)


def catmull_chain(ctrl, samples, alpha=0.5, ghost_start=None, ghost_end=None):
    """Centripetal Catmull-Rom through 2D control points. samples[i] = number of samples on span i (start inclusive,
    end exclusive); the last control point is appended.  ghost points default to the end points mirrored on the y axis."""
    n = len(ctrl)
    gs = ghost_start if ghost_start is not None else (-ctrl[1][0], ctrl[1][1])
    ge = ghost_end if ghost_end is not None else (-ctrl[n - 2][0], ctrl[n - 2][1])
    pts = []
    for i in range(n - 1):
        P0 = ctrl[i - 1] if i > 0 else gs
        P1, P2 = ctrl[i], ctrl[i + 1]
        P3 = ctrl[i + 2] if i + 2 < n else ge
        for j in range(samples[i]):
            pts.append(_cr_point(P0, P1, P2, P3, j / float(samples[i]), alpha))
    pts.append(ctrl[-1])
    return pts


# =====================================================================================================================
# 2. materials  (names fixed by BLENDER_CONTRACT.md section 4)
# =====================================================================================================================
STANDARD_MATERIALS = {
    # name:          kwargs for ensure_material (base_color is linear RGB)
    'M_Paint':      dict(base_color=(0.42, 0.012, 0.018), metallic=0.55, roughness=0.32, coat=1.0, coat_roughness=0.025),
    'M_Paint2':     dict(base_color=(0.006, 0.006, 0.007), metallic=0.0, roughness=0.5, coat=0.0, coat_roughness=0.1, specular=0.3),
    'M_Chrome':     dict(base_color=(0.86, 0.87, 0.9), metallic=1.0, roughness=0.07),
    'M_TrimBlack':  dict(base_color=(0.009, 0.009, 0.010), metallic=0.0, roughness=0.55),
    'M_TrimGrey':   dict(base_color=(0.085, 0.088, 0.095), metallic=0.0, roughness=0.55),
    'M_Rubber':     dict(base_color=(0.018, 0.018, 0.019), metallic=0.0, roughness=0.85),
    'M_Glass':      dict(base_color=(0.012, 0.02, 0.025), metallic=0.0, roughness=0.02, alpha=0.30, ior=1.5, double_sided=True),
    'M_Headlight':  dict(base_color=(0.09, 0.11, 0.13), metallic=0.0, roughness=0.03, alpha=0.22, emissive=(1.0, 0.95, 0.85),
                         emissive_strength=0.12, double_sided=True),
    'M_Taillight':  dict(base_color=(0.42, 0.006, 0.010), metallic=0.0, roughness=0.10, alpha=0.78, emissive=(1.0, 0.02, 0.03),
                         emissive_strength=0.38, double_sided=True),
    'M_Reverse':    dict(base_color=(0.85, 0.85, 0.85), metallic=0.0, roughness=0.1, emissive=(1.0, 1.0, 1.0), emissive_strength=0.15),
    'M_Indicator':  dict(base_color=(0.85, 0.40, 0.015), metallic=0.0, roughness=0.12, emissive=(1.0, 0.45, 0.02), emissive_strength=0.25),
    'M_Tyre':       dict(base_color=(0.012, 0.012, 0.013), metallic=0.0, roughness=0.9),
    'M_Rim':        dict(base_color=(0.62, 0.64, 0.68), metallic=0.95, roughness=0.30),
    'M_RimDark':    dict(base_color=(0.05, 0.05, 0.055), metallic=0.85, roughness=0.40),
    'M_BrakeDisc':  dict(base_color=(0.42, 0.42, 0.44), metallic=1.0, roughness=0.42),
    'M_Caliper':    dict(base_color=(0.70, 0.02, 0.015), metallic=0.2, roughness=0.32),
    'M_Plate':      dict(base_color=(0.88, 0.86, 0.80), metallic=0.0, roughness=0.45),
    'M_Underbody':  dict(base_color=(0.018, 0.018, 0.02), metallic=0.1, roughness=0.8),
    'M_IntDash':    dict(base_color=(0.028, 0.028, 0.032), metallic=0.0, roughness=0.6),
    'M_IntSeat':    dict(base_color=(0.06, 0.06, 0.07), metallic=0.0, roughness=0.8),
    'M_IntTrim':    dict(base_color=(0.14, 0.135, 0.13), metallic=0.0, roughness=0.5),
    'M_IntCarpet':  dict(base_color=(0.025, 0.025, 0.03), metallic=0.0, roughness=1.0),
    'M_Exhaust':    dict(base_color=(0.62, 0.62, 0.64), metallic=1.0, roughness=0.28),
}
MAT_ORDER = list(STANDARD_MATERIALS.keys())
LAMP_SLOTS = ('M_Headlight', 'M_Taillight', 'M_Reverse', 'M_Indicator')     # emissive lamp instances in UE: <id>_Body only
_MAT_INDEX = {n: i for i, n in enumerate(MAT_ORDER)}


def mi(name):
    """Global slot index of a standard material name (accepts an int and passes it through)."""
    if isinstance(name, int):
        return name
    return _MAT_INDEX[name]


def _set_input(node, name, value):
    sock = node.inputs.get(name)
    if sock is None:
        return False
    try:
        sock.default_value = value
    except Exception:
        try:
            sock.default_value = tuple(value)
        except Exception:
            return False
    return True


def ensure_material(name, base_color, metallic=0.0, roughness=0.5, emissive=None, alpha=None, coat=0.0,
                    coat_roughness=0.03, transmission=0.0, ior=1.45, emissive_strength=1.0, specular=0.5,
                    double_sided=False):
    """Create-or-update a Principled material (idempotent).  base_color/emissive are linear RGB(A) tuples.
    alpha < 1 switches the material to blended transparency (glass, lenses).  Returns the bpy Material."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is None:
        bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
        out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None) or nt.nodes.new('ShaderNodeOutputMaterial')
        nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    bc = tuple(base_color) + ((1.0,) if len(base_color) == 3 else ())
    _set_input(bsdf, 'Base Color', bc)
    _set_input(bsdf, 'Metallic', float(metallic))
    _set_input(bsdf, 'Roughness', float(roughness))
    _set_input(bsdf, 'IOR', float(ior))
    _set_input(bsdf, 'Specular IOR Level', float(specular))
    _set_input(bsdf, 'Coat Weight', float(coat))
    _set_input(bsdf, 'Coat Roughness', float(coat_roughness))
    _set_input(bsdf, 'Transmission Weight', float(transmission))
    _set_input(bsdf, 'Alpha', 1.0 if alpha is None else float(alpha))
    if emissive is not None:
        ec = tuple(emissive) + ((1.0,) if len(emissive) == 3 else ())
        _set_input(bsdf, 'Emission Color', ec)
        _set_input(bsdf, 'Emission Strength', float(emissive_strength))
    else:
        _set_input(bsdf, 'Emission Strength', 0.0)
    transparent = alpha is not None and alpha < 0.999
    try:
        mat.surface_render_method = 'BLENDED' if transparent else 'DITHERED'
    except Exception:
        pass
    try:
        mat.use_backface_culling = not (double_sided or transparent)
        mat.show_transparent_back = False if transparent else True
    except Exception:
        pass
    # viewport (solid mode) values
    mat.diffuse_color = (bc[0], bc[1], bc[2], 1.0 if alpha is None else max(0.15, float(alpha)))
    mat.metallic = float(metallic)
    mat.roughness = float(roughness)
    return mat


def build_standard_materials(paint=None, paint2=None):
    """Create/update ALL contract materials (BLENDER_CONTRACT.md section 4).  Optional paint/paint2 = linear RGB overrides
    for the preview colour (UE swaps the paint anyway).  Returns {name: Material}."""
    out = {}
    for name, kw in STANDARD_MATERIALS.items():
        kw = dict(kw)
        if name == 'M_Paint' and paint is not None:
            kw['base_color'] = tuple(paint)
        if name == 'M_Paint2' and paint2 is not None:
            kw['base_color'] = tuple(paint2)
        out[name] = ensure_material(name, **kw)
    return out


# =====================================================================================================================
# 3. scene helpers
# =====================================================================================================================
def ensure_collection(path):
    """'FORZA_UE/Cars/car01_hatch_pulse' -> nested collections under the scene collection (created when missing)."""
    parent = bpy.context.scene.collection
    for part in [p for p in path.replace('\\', '/').split('/') if p]:
        child = next((c for c in parent.children if c.name == part), None)
        if child is None:
            child = bpy.data.collections.get(part)
            if child is None:
                child = bpy.data.collections.new(part)
            if child.name not in [c.name for c in parent.children]:
                parent.children.link(child)
        parent = child
    return parent


def remove_asset(asset_id):
    """Delete all objects/meshes/collection that belong to `asset_id` (name prefix).  Never touches anything else."""
    objs = [o for o in bpy.data.objects
            if o.name.startswith(asset_id) or o.name.startswith('UCX_' + asset_id) or o.name.startswith('__tmp_' + asset_id)]
    meshes = set()
    for o in objs:
        if o.type == 'MESH' and o.data:
            meshes.add(o.data)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    for m in meshes:
        if m.users == 0:
            bpy.data.meshes.remove(m)
    for m in [m for m in bpy.data.meshes if (m.name.startswith(asset_id) or m.name.startswith('UCX_' + asset_id)) and m.users == 0]:
        bpy.data.meshes.remove(m)
    for l in [l for l in bpy.data.lights if l.name.startswith(asset_id + '_QA_') and l.users == 0]:
        bpy.data.lights.remove(l)             # QA studio lights of this asset (their objects were removed above)
    col = bpy.data.collections.get(asset_id)
    if col is not None:
        bpy.data.collections.remove(col)
    return len(objs)


# =====================================================================================================================
# 4. mesh builder + primitives (all return a NEW bmesh in the space they were built in)
# =====================================================================================================================
def bm_append(dst, src, matrix=None, mat=None, flip=False):
    """Append src bmesh geometry into dst (verts+faces, loose edges). mat: standard name/int forced on every appended face,
    None keeps the source material indices.  Returns list of new faces."""
    vmap = {}
    for v in src.verts:
        co = (matrix @ v.co) if matrix is not None else v.co.copy()
        vmap[v] = dst.verts.new(co)
    new_faces = []
    forced = mi(mat) if mat is not None else None
    for f in src.faces:
        vs = [vmap[v] for v in f.verts]
        if flip:
            vs.reverse()
        try:
            nf = dst.faces.new(vs)
        except ValueError:
            continue
        nf.material_index = forced if forced is not None else f.material_index
        nf.smooth = True
        new_faces.append(nf)
    for e in src.edges:
        if not e.link_faces:
            try:
                dst.edges.new((vmap[e.verts[0]], vmap[e.verts[1]]))
            except ValueError:
                pass
    return new_faces


class Part:
    """Accumulator of geometry that will become ONE object.  p.add(bm, mat=None, matrix=None)."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()

    def add(self, bm, mat=None, matrix=None, flip=False, free=True):
        faces = bm_append(self.bm, bm, matrix, mat, flip)
        if free:
            bm.free()
        return faces

    def free(self):
        self.bm.free()


def _set_mat(bm, mat):
    if mat is not None:
        idx = mi(mat)
        for f in bm.faces:
            f.material_index = idx
    return bm


def _smooth_all(bm):
    for f in bm.faces:
        f.smooth = True


def recalc(bm):
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def prim_box(size=(1, 1, 1), center=(0, 0, 0), mat=None, bevel=0.0, segments=2, rot=(0, 0, 0)):
    """Box (optionally with bevelled/rounded edges) centred on `center`."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.49), segments=segments, profile=0.5, material=-1,
                        affect='EDGES', clamp_overlap=True)
    bmesh.ops.transform(bm, matrix=T(center, rot), verts=bm.verts)
    recalc(bm)
    return _set_mat(bm, mat)


def prim_cylinder(radius=0.5, depth=1.0, segments=24, axis='Z', center=(0, 0, 0), mat=None, radius2=None, caps=True,
                  rot=(0, 0, 0), bevel=0.0, bevel_segments=2):
    """Cylinder/cone along `axis` ('X','Y','Z'); radius = radius at -axis end, radius2 at +axis end (default same)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segments, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=depth)
    if bevel > 0 and caps:
        cap_edges = [e for e in bm.edges if all(abs(abs(v.co.z) - depth / 2) < 1e-6 for v in e.verts)]
        bmesh.ops.bevel(bm, geom=cap_edges, offset=bevel, segments=bevel_segments, profile=0.5, material=-1, affect='EDGES', clamp_overlap=True)
    if axis == 'X':
        bmesh.ops.transform(bm, matrix=T(rot=(0, 90, 0)), verts=bm.verts)
    elif axis == 'Y':
        bmesh.ops.transform(bm, matrix=T(rot=(-90, 0, 0)), verts=bm.verts)
    bmesh.ops.transform(bm, matrix=T(center, rot), verts=bm.verts)
    recalc(bm)
    return _set_mat(bm, mat)


def prim_sphere(radius=0.5, u=24, v=12, scale=(1, 1, 1), center=(0, 0, 0), mat=None, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=radius)
    bmesh.ops.transform(bm, matrix=T(center, rot, scale), verts=bm.verts)
    recalc(bm)
    return _set_mat(bm, mat)


def prim_torus(R=0.2, r=0.02, seg_major=48, seg_minor=10, axis='Z', center=(0, 0, 0), mat=None, rz=None, arc=None):
    """Torus about `axis`. r = tube radius in the radial direction, rz = tube radius along the axis (default r). arc=(a0,a1)
    degrees makes a partial torus (open ends capped)."""
    rz = r if rz is None else rz
    bm = bmesh.new()
    a0, a1 = (0.0, 360.0) if arc is None else arc
    full = arc is None
    nmaj = seg_major if full else seg_major + 1
    ring = []
    for i in range(nmaj):
        a = math.radians(a0 + (a1 - a0) * i / float(seg_major))
        row = []
        for j in range(seg_minor):
            b = 2 * math.pi * j / seg_minor
            rr = R + r * math.cos(b)
            row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), rz * math.sin(b))))
        ring.append(row)
    last = nmaj if not full else nmaj
    for i in range(nmaj if full else nmaj - 1):
        i2 = (i + 1) % nmaj
        for j in range(seg_minor):
            j2 = (j + 1) % seg_minor
            bm.faces.new((ring[i][j], ring[i2][j], ring[i2][j2], ring[i][j2]))
    if not full:
        bm.faces.new(list(reversed(ring[0])))
        bm.faces.new(ring[-1])
    if axis == 'X':
        bmesh.ops.transform(bm, matrix=T(rot=(0, 90, 0)), verts=bm.verts)
    elif axis == 'Y':
        bmesh.ops.transform(bm, matrix=T(rot=(-90, 0, 0)), verts=bm.verts)
    bmesh.ops.transform(bm, matrix=T(center), verts=bm.verts)
    recalc(bm)
    return _set_mat(bm, mat)


def prim_revolve(profile, segments=32, axis='Z', center=(0, 0, 0), mat=None, closed=False, angle=360.0, caps=False):
    """Surface of revolution.  profile = [(r, h), ...] around `axis` (r distance from the axis, h position along it).
    closed=True joins last->first (a closed solid profile such as a tyre section). A point with r~0 becomes a pole.
    Profile direction: walking the profile with the outside on the LEFT (r increasing = to the right of h)... orientation
    is fixed afterwards with recalc for closed shapes; for open shapes pass profile from axis outwards/downwards as needed."""
    bm = bmesh.new()
    full = abs(angle - 360.0) < 1e-6
    nseg = segments
    rows = []
    for (r, h) in profile:
        if r < 1e-7:
            v = bm.verts.new((0, 0, h))
            rows.append([v] * (nseg if full else nseg + 1))
        else:
            row = []
            for k in range(nseg if full else nseg + 1):
                a = math.radians(angle) * k / float(nseg)
                row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), h)))
            rows.append(row)
    npro = len(profile)
    pairs = [(i, i + 1) for i in range(npro - 1)] + ([(npro - 1, 0)] if closed else [])
    for (i, j) in pairs:
        for k in range(nseg if full else nseg):
            k2 = (k + 1) % len(rows[i]) if full else k + 1
            vs = [rows[i][k], rows[i][k2], rows[j][k2], rows[j][k]]
            uniq = []
            for v in vs:
                if v not in uniq:
                    uniq.append(v)
            if len(uniq) >= 3:
                try:
                    bm.faces.new(uniq)
                except ValueError:
                    pass
    if caps and not full:
        pass
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
    if axis == 'X':
        bmesh.ops.transform(bm, matrix=T(rot=(0, 90, 0)), verts=bm.verts)
    elif axis == 'Y':
        bmesh.ops.transform(bm, matrix=T(rot=(-90, 0, 0)), verts=bm.verts)
    bmesh.ops.transform(bm, matrix=T(center), verts=bm.verts)
    if closed:
        recalc(bm)
    return _set_mat(bm, mat)


def outline_rrect(w, h, r, n=4):
    """Rounded-rectangle outline (list of (u,v), counter-clockwise), corner radius r with n segments per corner."""
    r = min(r, w / 2 - 1e-6, h / 2 - 1e-6)
    pts = []
    corners = [(w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)]
    for cx, cy, a0 in corners:
        for i in range(n + 1):
            a = math.radians(a0 + 90.0 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def outline_ellipse(a, b, n=24):
    return [(a * math.cos(2 * math.pi * i / n), b * math.sin(2 * math.pi * i / n)) for i in range(n)]


def outline_superellipse(a, b, p=2.6, n=32):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        pts.append((a * math.copysign(abs(c) ** (2.0 / p), c), b * math.copysign(abs(s) ** (2.0 / p), s)))
    return pts


def outline_rounded_poly(pts, r=0.01, n=3):
    """(rev 3) Polygon [(u, v), ...] (counter-clockwise, convex or mildly concave) with every corner rounded by a fillet of radius
    r (n arc segments per corner; a corner whose neighbouring edges are too short gets a smaller radius).  r may be a list
    with one radius per vertex.  Use it for angular lamp / intake outlines that must stay convex for pocket_cutter()."""
    m = len(pts)
    out = []
    for i in range(m):
        ri = r[i] if isinstance(r, (list, tuple)) else r
        p0, p1, p2 = Vector((pts[i - 1][0], pts[i - 1][1], 0.0)), Vector((pts[i][0], pts[i][1], 0.0)), \
            Vector((pts[(i + 1) % m][0], pts[(i + 1) % m][1], 0.0))
        u1, u2 = (p0 - p1), (p2 - p1)
        l1, l2 = u1.length, u2.length
        if ri <= 1e-9 or l1 < 1e-9 or l2 < 1e-9:
            out.append((p1.x, p1.y))
            continue
        u1.normalize()
        u2.normalize()
        th = math.acos(clamp(u1.dot(u2), -1.0, 1.0))
        if th < 1e-3 or th > math.pi - 1e-3:
            out.append((p1.x, p1.y))
            continue
        t = min(ri / math.tan(th / 2.0), 0.45 * l1, 0.45 * l2)
        rr = t * math.tan(th / 2.0)
        bis = (u1 + u2).normalized()
        cc = p1 + bis * (rr / math.sin(th / 2.0))
        a1 = math.atan2((p1 + u1 * t).y - cc.y, (p1 + u1 * t).x - cc.x)
        a2 = math.atan2((p1 + u2 * t).y - cc.y, (p1 + u2 * t).x - cc.x)
        da = a2 - a1
        while da > math.pi:
            da -= 2 * math.pi
        while da < -math.pi:
            da += 2 * math.pi
        for k in range(n + 1):
            a = a1 + da * k / float(n)
            out.append((cc.x + rr * math.cos(a), cc.y + rr * math.sin(a)))
    return out


def densify_outline(pts, step=0.015):
    """(rev 3) Subdivide the edges of a closed polygon [(u, v), ...] so that no edge is longer than `step`.  A pocket cutter or a
    surface sweep that is projected onto a curved skin only touches the skin at its outline points; a long straight outline edge
    across a convex crest would leave a sliver of uncut skin inside the opening - densify the outline first."""
    out = []
    m = len(pts)
    for i in range(m):
        a, b = pts[i], pts[(i + 1) % m]
        n = max(int(math.ceil(math.hypot(b[0] - a[0], b[1] - a[1]) / step)), 1)
        for k in range(n):
            t = k / float(n)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def prim_prism(outline, depth, plane='XZ', center=(0, 0, 0), mat=None, scale_back=1.0):
    """Extrude a 2D outline (u,v) into a closed prism of `depth`.  plane 'XZ': u->X, v->Z, extruded along Y (centred);
    'XY': u->X, v->Y along Z; 'YZ': u->Y, v->Z along X.  scale_back scales the far outline (taper)."""
    bm = bmesh.new()

    def P(u, v, d):
        if plane == 'XZ':
            return (u, d, v)
        if plane == 'XY':
            return (u, v, d)
        return (d, u, v)

    near = [bm.verts.new(P(u, v, -depth / 2)) for (u, v) in outline]
    far = [bm.verts.new(P(u * scale_back, v * scale_back, depth / 2)) for (u, v) in outline]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((near[i], near[j], far[j], far[i]))
    bm.faces.new(near)
    bm.faces.new(list(reversed(far)))
    bmesh.ops.transform(bm, matrix=T(center), verts=bm.verts)
    recalc(bm)
    return _set_mat(bm, mat)


def ring_loft(rings, closed=True, caps=True, mat=None):
    """Quad strip between consecutive rings (lists of Vector, same length).  closed: each ring is a loop.  caps: n-gon caps."""
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for a in range(len(rings) - 1):
        for j in range(n if closed else n - 1):
            j2 = (j + 1) % n
            try:
                bm.faces.new((vr[a][j], vr[a][j2], vr[a + 1][j2], vr[a + 1][j]))
            except ValueError:
                pass
    if caps and closed:
        bm.faces.new(list(reversed(vr[0])))
        bm.faces.new(vr[-1])
    recalc(bm)
    return _set_mat(bm, mat)


def prim_tube(path, radius=0.01, sides=10, mat=None, caps=True, up=(0, 0, 1), closed=False, scale_profile=None):
    """Tube swept along a 3D polyline.  radius: float, (rx, ry) ellipse (rx along the frame normal, ry along binormal),
    or list per point of either.  closed=True makes a loop (torus-like)."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    tang = []
    for i in range(n):
        if closed:
            t = pts[(i + 1) % n] - pts[(i - 1) % n]
        else:
            t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        tang.append(t.normalized())
    upv = Vector(up)
    nrm = tang[0].cross(upv)
    if nrm.length < 1e-6:
        nrm = tang[0].cross(Vector((1, 0, 0)))
    nrm.normalize()
    rings = []
    for i in range(n):
        if i > 0:
            nrm = (nrm - tang[i] * nrm.dot(tang[i]))
            if nrm.length < 1e-8:
                nrm = tang[i].cross(Vector((0, 0, 1)))
            nrm.normalize()
        bn = tang[i].cross(nrm).normalized()
        r = radius[i] if isinstance(radius, (list,)) else radius
        rx, ry = (r, r) if isinstance(r, (int, float)) else r
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ring.append(pts[i] + nrm * (rx * math.cos(a)) + bn * (ry * math.sin(a)))
        rings.append(ring)
    if closed:
        rings.append(rings[0])
        bm = ring_loft(rings, closed=True, caps=False)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-7)
        recalc(bm)
        return _set_mat(bm, mat)
    return ring_loft(rings, closed=True, caps=caps, mat=mat)


def mirror_y(bm, weld=1e-5, free=False):
    """Return a NEW bmesh = bm + its mirror image across the y=0 plane (flipped winding).  Seam verts are welded."""
    out = bmesh.new()
    bm_append(out, bm)
    bm_append(out, bm, matrix=Matrix.Diagonal(Vector((1, -1, 1, 1))), flip=True)
    bmesh.ops.remove_doubles(out, verts=list(out.verts), dist=weld)
    if free:
        bm.free()
    return out


def mirrored_copy(bm, flip=True):
    """Return a NEW bmesh with y -> -y (winding flipped so normals stay outward), no union."""
    out = bmesh.new()
    bm_append(out, bm, matrix=Matrix.Diagonal(Vector((1, -1, 1, 1))), flip=flip)
    return out


def shade_by_angle(bm, angle_deg=38.0):
    """Smooth faces everywhere, edges sharper than angle_deg become hard (BMEdge.smooth False)."""
    ang = math.radians(angle_deg)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2:
            try:
                a = e.calc_face_angle(0.0)
            except Exception:
                a = 0.0
            e.smooth = a <= ang
        else:
            e.smooth = True


def bevel_hard_edges(bm, angle_deg=55.0, width=0.004, segments=2, edge_filter=None):
    """Bevel every edge whose dihedral angle exceeds angle_deg (panel pockets, lamp rims).  Failure-safe."""
    ang = math.radians(angle_deg)
    edges = []
    for e in bm.edges:
        if len(e.link_faces) == 2:
            try:
                a = e.calc_face_angle(0.0)
            except Exception:
                continue
            if a > ang and (edge_filter is None or edge_filter(e)):
                edges.append(e)
    if not edges:
        return 0
    try:
        bmesh.ops.bevel(bm, geom=edges, offset=width, segments=segments, profile=0.5, material=-1, affect='EDGES', clamp_overlap=True)
    except Exception as ex:
        log("bevel_hard_edges failed:", ex)
        return 0
    return len(edges)


def bm_bounds(bm):
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    return (Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs))))


def tri_count(bm_or_mesh):
    if isinstance(bm_or_mesh, bmesh.types.BMesh):
        return sum(max(len(f.verts) - 2, 0) for f in bm_or_mesh.faces)
    return sum(max(len(p.vertices) - 2, 0) for p in bm_or_mesh.polygons)


def finish_object(name, bm, collection, parent=None, location=(0, 0, 0), smooth_angle=38.0, free=True,
                  keep_tags=False, clean=True, triangulate_ngons=True):
    """bmesh -> mesh object named `name` in `collection`, parented (identity inverse) to `parent`.
    * degenerate faces dissolved, n-gons (> 4 verts, typically from booleans) triangulated with the beauty method so UE
      does not have to guess; quads stay quads
    * only the used material slots are created (from MAT_ORDER indices), faces remapped
    * smooth shading by angle, custom tag attributes removed (unless keep_tags)
    The object's transform is `location` (local to the parent) with no rotation/scale."""
    if clean:
        try:
            bmesh.ops.dissolve_degenerate(bm, dist=1e-6, edges=list(bm.edges))
        except Exception as ex:
            log("dissolve_degenerate failed:", ex)
        bm.faces.ensure_lookup_table()
        sliver = [f for f in bm.faces if f.calc_area() < 1e-10]
        if sliver:        # zero-area boolean slivers with coincident (un-merged) vertices: weld those vertices only
            bmesh.ops.remove_doubles(bm, verts=list({v for f in sliver for v in f.verts}), dist=2e-5)
            bm.faces.ensure_lookup_table()
        dead = [f for f in bm.faces if f.calc_area() < 1e-12]
        if dead:
            bmesh.ops.delete(bm, geom=dead, context='FACES')
        loose_e = [e for e in bm.edges if not e.link_faces]
        if loose_e:
            bmesh.ops.delete(bm, geom=loose_e, context='EDGES')
        loose = [v for v in bm.verts if not v.link_edges]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context='VERTS')
    if triangulate_ngons:
        ng = [f for f in bm.faces if len(f.verts) > 4]
        if ng:
            bmesh.ops.triangulate(bm, faces=ng, quad_method='BEAUTY', ngon_method='BEAUTY')
            if clean:         # the triangulation of a collinear n-gon can leave zero-area triangles: weld / drop them
                bm.faces.ensure_lookup_table()
                sliver = [f for f in bm.faces if f.calc_area() < 1e-10]
                if sliver:
                    bmesh.ops.remove_doubles(bm, verts=list({v for f in sliver for v in f.verts}), dist=2e-5)
                    bm.faces.ensure_lookup_table()
                    dead = [f for f in bm.faces if f.calc_area() < 1e-10]
                    if dead:
                        bmesh.ops.delete(bm, geom=dead, context='FACES')
    if clean:
        heal_nonmanifold(bm)
    if not keep_tags:
        for lay in (TAG_COL, TAG_ST):
            L = bm.faces.layers.int.get(lay)
            if L is not None:
                bm.faces.layers.int.remove(L)
    used = sorted(set(f.material_index for f in bm.faces))
    remap = {old: new for new, old in enumerate(used)}
    for f in bm.faces:
        f.material_index = remap[f.material_index]
    if smooth_angle is not None:
        shade_by_angle(bm, smooth_angle)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    if free:
        bm.free()
    for old in used:
        nm = MAT_ORDER[old] if old < len(MAT_ORDER) else None
        me.materials.append(bpy.data.materials.get(nm) if nm else None)
    for p in me.polygons:
        p.use_smooth = True
    me.update()
    ob = bpy.data.objects.new(name, me)
    collection.objects.link(ob)
    if parent is not None:
        ob.parent = parent
        ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.location = location
    return ob


def make_empty(name, collection, parent=None, location=(0, 0, 0), display='PLAIN_AXES', size=0.1):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = display
    e.empty_display_size = size
    collection.objects.link(e)
    if parent is not None:
        e.parent = parent
        e.matrix_parent_inverse = Matrix.Identity(4)
    e.location = location
    return e


# =====================================================================================================================
# 5. body loft: superellipse-free, control-point rings along X
# =====================================================================================================================
# Half cross-section (y>=0) control points, bottom centre -> top centre, and the number of samples on each span.
DEFAULT_RING_SPANS = [
    ('floor_c', 'floor_e', 2), ('floor_e', 'sill', 3), ('sill', 'wide', 4), ('wide', 'belt_lo', 6),
    ('belt_lo', 'belt_up', 2), ('belt_up', 'edge', 5), ('edge', 'rail', 2), ('rail', 'crown', 3), ('crown', 'top_c', 3),
]


EXT_RING_SPANS = [
    ('floor_c', 'floor_e', 2), ('floor_e', 'sill', 3), ('sill', 'wide', 4), ('wide', 'char_lo', 3), ('char_lo', 'char_up', 2),
    ('char_up', 'belt_lo', 4), ('belt_lo', 'belt_up', 2), ('belt_up', 'edge', 5), ('edge', 'rail', 2), ('rail', 'crown', 3),
    ('crown', 'top_c', 3),
]


def ring_controls(cv, x):
    """Evaluate the parameter curves at station x -> ordered list of (name, (y, z)) for the half ring.
    Required curves: zf (floor z), zt (top-centre z), hwm/zw (max half width and its height), zb (belt z), hwe (half width of
    the roof edge/hood edge).  Optional (defaults in brackets): hwb (hwm-0.03), ze (zt-0.04), hwf (0.62 hwm), hws (hwm-0.04),
    zs (zf+0.07), crease (0.02), belt_step (0.02), rail_w (0.05).
    Optional character line (selects EXT_RING_SPANS): zc = height of the line, cdepth = how far the surface above it steps
    in (0 = no visible line), cwidth = half height (m) of the transition zone (default 0.04; smaller = crisper crease)."""
    def g(k, d):
        return cv[k](x) if k in cv else d

    zf, zt = cv['zf'](x), cv['zt'](x)
    hwm, zw = cv['hwm'](x), cv['zw'](x)
    hwb, zb = g('hwb', hwm - 0.03), cv['zb'](x)
    hwe, ze = cv['hwe'](x), g('ze', zt - 0.04)
    hwf, hws, zs = g('hwf', hwm * 0.62), g('hws', hwm - 0.04), g('zs', zf + 0.07)
    crease, step, rail_w = g('crease', 0.02), g('belt_step', 0.02), g('rail_w', 0.05)
    hwb = min(hwb, hwm)
    hws = min(hws, hwm)
    hwf = min(hwf, hws)
    zs_, zw_, zbl, zbu, ze_ = zs, zw, zb - crease, zb + crease * 0.5, ze
    zl = [zs_, zw_, zbl, zbu, ze_]
    eps = 0.006
    prev = zf + eps
    for i in range(5):
        zl[i] = max(zl[i], prev)
        prev = zl[i] + eps
    zs_, zw_, zbl, zbu, ze_ = zl
    room = zt - 0.006 - zf
    span = ze_ - zf
    if span > room and span > 1e-6:
        sc = max(room, 0.01) / span
        zs_, zw_, zbl, zbu, ze_ = [zf + (z - zf) * sc for z in zl]
    hbu = hwb - step
    hwe = max(min(hwe, hbu - 0.004), 0.03)
    hwr = max(hwe - rail_w, hwe * 0.4)

    def camber(y):
        return zt - (zt - ze_) * (y / hwe) ** 2
    pts = [('floor_c', (0.0, zf)), ('floor_e', (hwf, zf)), ('sill', (hws, zs_)), ('wide', (hwm, zw_))]
    if 'zc' in cv:
        cd = cv['cdepth'](x) if 'cdepth' in cv else 0.035
        zc = clamp(cv['zc'](x), zw_ + 0.05, zbl - 0.06)
        span = max(zbl - zw_, 1e-4)
        t = (zc - zw_) / span
        dt = min(g('cwidth', 0.04) / span, 0.3)         # (rev 3) optional curve `cwidth`: half height of the crease transition

        def on_line(tt):
            return (hwm + (hwb - hwm) * tt, zw_ + span * tt)
        lo = on_line(max(t - dt, 0.05))
        up = on_line(min(t + dt, 0.95))
        pts += [('char_lo', (lo[0] + cd * 0.35, lo[1])), ('char_up', (up[0] - cd * 0.65, up[1]))]
    pts += [('belt_lo', (hwb, zbl)), ('belt_up', (hbu, zbu)), ('edge', (hwe, ze_)),
            ('rail', (hwr, camber(hwr))), ('crown', (hwr * 0.5, camber(hwr * 0.5))), ('top_c', (0.0, zt))]
    return pts


class Shell:
    """Result of loft_body: .bm (closed quad shell), .xs stations, .rows[r][j] BMVerts, .N ring length, .H half length,
    .half_idx name -> half index, .cv curves. Methods: col(name, side) -> ring column, tagged quads via TAG_COL/TAG_ST."""
    pass


def _end_inset(x, xs, round_x0, round_x1):
    """Inset (m) of the ring at station x for the quarter-circle edge rounding at the two ends of the loft."""
    ins = 0.0
    if round_x0 > 1e-6 and x < xs[0] + round_x0:
        t = xs[0] + round_x0 - x
        ins = max(ins, round_x0 - math.sqrt(max(round_x0 * round_x0 - t * t, 0.0)))
    if round_x1 > 1e-6 and x > xs[-1] - round_x1:
        t = x - (xs[-1] - round_x1)
        ins = max(ins, round_x1 - math.sqrt(max(round_x1 * round_x1 - t * t, 0.0)))
    return ins


def loft_body(curves, xs, spans=None, caps=True, alpha=0.5, smooth_passes=2, smooth_strength=0.6, cap_rings=3, cap_bulge=0.025,
              ring_density=1.0, round_x0=0.0, round_x1=0.0):
    """Loft a closed car body shell along X.  `curves` maps parameter name -> number | [(x,v),...] | callable (see
    ring_controls); `xs` station positions (use station_list).  Ring = half cross-section Catmull-Rom through named control
    points mirrored about y=0.  Quads get int attributes TAG_COL (ring column+1) and TAG_ST (station+1).
    smooth_passes: Laplacian smoothing of the rows along X (removes key-point wiggles, rounds the cowl/hood transitions;
    the first/last 3 stations are kept).  caps: both ends are closed with `cap_rings` shrinking domed rings (cap_bulge m).
    ring_density multiplies the samples of every ring span (2.0 = twice as many columns, smoother corners).
    The result keeps a private copy of the smooth shell (shell.ref + BVH) for apply_shell_normals()."""
    cv = {k: as_curve(v) for k, v in curves.items()}
    spans = spans or (EXT_RING_SPANS if 'zc' in cv else DEFAULT_RING_SPANS)
    spans = [(a, b, max(1, int(round(n * ring_density)))) for (a, b, n) in spans]
    half_idx = {}
    acc = 0
    for (a, b, n) in spans:
        half_idx[a] = acc
        acc += n
    half_idx[spans[-1][1]] = acc
    H = acc + 1
    N = 2 * H - 2
    samples = [s[2] for s in spans]
    bm = bmesh.new()
    tag_c = bm.faces.layers.int.new(TAG_COL)
    tag_s = bm.faces.layers.int.new(TAG_ST)
    rows = []
    for x in xs:
        ctrl = ring_controls(cv, x)
        names = [c[0] for c in ctrl]
        assert names == [s[0] for s in spans] + [spans[-1][1]], "ring control names must match spans"
        ins = _end_inset(x, xs, round_x0, round_x1)
        if ins > 1e-9:       # quarter-circle edge rounding: the ring shrinks inwards by `ins` (outline offset approximation)
            z_lo, z_hi = ctrl[0][1][1], ctrl[-1][1][1]
            zc0, hz = 0.5 * (z_lo + z_hi), max(0.5 * (z_hi - z_lo), 1e-3)
            hy = max(max(c[1][0] for c in ctrl), 1e-3)
            sy, sz = max(1.0 - ins / hy, 0.05), max(1.0 - ins / hz, 0.05)
            ctrl = [(nm, (y * sy, zc0 + (z - zc0) * sz)) for (nm, (y, z)) in ctrl]
        half = catmull_chain([c[1] for c in ctrl], samples, alpha)
        row = [None] * N
        for i, (y, z) in enumerate(half):
            if i == 0 or i == H - 1:
                row[i] = bm.verts.new((x, 0.0, z))
            else:
                row[i] = bm.verts.new((x, y, z))
                row[N - i] = bm.verts.new((x, -y, z))
        rows.append(row)
    # Laplacian smoothing of rows along X (keeps x, moves y/z towards the interpolation of the neighbours)
    nr = len(rows)
    for _ in range(max(smooth_passes, 0)):
        newp = {}
        for r in range(3, nr - 3):
            if _end_inset(xs[r], xs, round_x0, round_x1) > 1e-9 or _end_inset(xs[r - 1], xs, round_x0, round_x1) > 1e-9 \
                    or _end_inset(xs[r + 1], xs, round_x0, round_x1) > 1e-9:
                continue        # keep the rounded end edge crisp
            xa, xb, xc = xs[r - 1], xs[r], xs[r + 1]
            w = (xb - xa) / (xc - xa)
            for j in range(H):                      # +y half incl. the two centre-line vertices
                a, b, c = rows[r - 1][j].co, rows[r][j].co, rows[r + 1][j].co
                ty = a.y + (c.y - a.y) * w
                tz = a.z + (c.z - a.z) * w
                newp[(r, j)] = (b.y + (ty - b.y) * smooth_strength, b.z + (tz - b.z) * smooth_strength)
        for (r, j), (y, z) in newp.items():
            v = rows[r][j]
            if j not in (0, H - 1):
                v.co.y = y
            v.co.z = z
            if j not in (0, H - 1):                 # mirror to the -y side
                m = rows[r][N - j]
                m.co.y = -y
                m.co.z = z
    for r in range(len(rows) - 1):
        for j in range(N):
            j2 = (j + 1) % N
            f = bm.faces.new((rows[r][j], rows[r][j2], rows[r + 1][j2], rows[r + 1][j]))
            f[tag_c] = j + 1
            f[tag_s] = r + 1
    if caps:
        for end, out in ((0, -1.0), (nr - 1, 1.0)):
            row = rows[end]
            zc0 = sum(v.co.z for v in row) / N
            x_end = xs[end]
            prev = row
            for k in range(1, cap_rings + 1):
                fct = 1.0 - k / (cap_rings + 1.0)
                ring = [bm.verts.new((x_end + out * cap_bulge * (1.0 - fct * fct), v.co.y * fct, zc0 + (v.co.z - zc0) * fct))
                        for v in row]
                for j in range(N):
                    j2 = (j + 1) % N
                    bm.faces.new((prev[j], prev[j2], ring[j2], ring[j]))
                prev = ring
            ctr = bm.verts.new((x_end + out * cap_bulge, 0.0, zc0))
            for j in range(N):
                bm.faces.new((prev[j], prev[(j + 1) % N], ctr))
    recalc(bm)
    sh = Shell()
    sh.bm, sh.xs, sh.rows, sh.N, sh.H, sh.half_idx, sh.cv, sh.spans = bm, list(xs), rows, N, H, half_idx, cv, spans
    sh.pos = [[Vector(v.co) for v in row] for row in rows]   # coordinates survive later booleans (used by shell_skin)
    bm.normal_update()
    sh.ref = bm.copy()                                       # smooth reference surface for apply_shell_normals()
    sh.ref.normal_update()
    sh.ref.faces.ensure_lookup_table()
    sh.ref_bvh = BVHTree.FromBMesh(sh.ref)
    return sh


def apply_shell_normals(ob, shell, tol=0.0015):
    """Give the finished body mesh the smooth shading of the lofted shell: every face whose vertices all lie on the original
    shell surface (within tol) gets custom corner normals interpolated from the shell's vertex normals, so the irregular
    re-triangulation around boolean cuts, caps and seams does not show.  Pocket walls, grooves and add-ons keep their own
    normals.  Equivalent of a Data Transfer (custom normals) modifier, done in code.  Returns the number of smoothed loops."""
    from mathutils.interpolate import poly_3d_calc
    me = ob.data
    ref, bvh = shell.ref, shell.ref_bvh
    on = {}
    for v in me.vertices:
        loc, nor, idx, dist = bvh.find_nearest(v.co)
        on[v.index] = (loc, idx) if (loc is not None and dist < tol) else None
    cn = [Vector(n.vector) for n in me.corner_normals]
    changed = 0
    cache = {}
    for p in me.polygons:
        if all(on[vi] is not None for vi in p.vertices):
            for li in p.loop_indices:
                vi = me.loops[li].vertex_index
                if vi not in cache:
                    loc, idx = on[vi]
                    f = ref.faces[idx]
                    verts = list(f.verts)
                    w = poly_3d_calc([v.co for v in verts], loc)
                    n = Vector()
                    for v, wi in zip(verts, w):
                        n += v.normal * wi
                    cache[vi] = n.normalized() if n.length > 1e-9 else Vector(cn[li])
                cn[li] = cache[vi]
                changed += 1
    me.normals_split_custom_set([tuple(n) for n in cn])
    return changed


def shell_col(shell, name, side=+1):
    """Ring column index (vertex index along the ring) of a named control point on the +Y (side=+1) or -Y side."""
    i = shell.half_idx[name]
    if i == 0 or i == shell.H - 1:
        return i
    return i if side > 0 else shell.N - i


def shell_quad_cols(shell, a_name, b_name, side=+1, frac=None):
    """Tag values (TAG_COL, i.e. column+1) of the quads lying between control points a_name and b_name on a side.
    frac=(lo, hi) restricts to that fraction (0..1) of the span, e.g. the lower 60 % of the sill->wide span."""
    ia, ib = shell.half_idx[a_name], shell.half_idx[b_name]
    if frac is not None:
        n = ib - ia
        ia, ib = ia + int(round(frac[0] * n)), ia + int(round(frac[1] * n))
    if side > 0:
        return set(j + 1 for j in range(ia, ib))
    return set((shell.N - i - 1) + 1 for i in range(ia, ib))


def face_tags(bm):
    return bm.faces.layers.int.get(TAG_COL), bm.faces.layers.int.get(TAG_ST)


# =====================================================================================================================
# 6. booleans + surface projection tools
# =====================================================================================================================
def is_manifold(bm):
    return all(len(e.link_faces) == 2 for e in bm.edges)


def bm_boolean(target, cutters, operation='DIFFERENCE', solver='MANIFOLD', free_inputs=True):
    """Boolean `target` (bmesh) with a list of cutter bmeshes through the Blender Boolean modifier, evaluated via the
    depsgraph (no operators, no selection needed).  Material indices and TAG_* face attributes are propagated (cutter faces
    keep their own material index, tag 0).  Returns a NEW bmesh; inputs are freed when free_inputs."""
    scene_col = bpy.context.scene.collection
    tmp = bpy.data.collections.new("__tmp_kit_bool")
    scene_col.children.link(tmp)
    made_obj, made_mesh = [], []

    def mk(name, bm):
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        for nm in MAT_ORDER:          # all slots present, otherwise the solver clamps material indices to slot 0
            me.materials.append(bpy.data.materials.get(nm))
        ob = bpy.data.objects.new(name, me)
        made_obj.append(ob)
        made_mesh.append(me)
        return ob

    cut_col = None
    try:
        A = mk("__tmp_kit_A", target)
        tmp.objects.link(A)
        cobs = []
        for i, c in enumerate(cutters):
            ob = mk("__tmp_kit_C%d" % i, c)
            cobs.append(ob)
        md = A.modifiers.new("kitbool", 'BOOLEAN')
        md.operation = operation
        md.solver = solver
        if len(cobs) == 1:
            tmp.objects.link(cobs[0])
            md.operand_type = 'OBJECT'
            md.object = cobs[0]
        else:
            cut_col = bpy.data.collections.new("__tmp_kit_cutters")
            scene_col.children.link(cut_col)
            for ob in cobs:
                cut_col.objects.link(ob)
            md.operand_type = 'COLLECTION'
            md.collection = cut_col
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        eo = A.evaluated_get(dg)
        nm = bpy.data.meshes.new_from_object(eo, depsgraph=dg)
        out = bmesh.new()
        out.from_mesh(nm)
        bpy.data.meshes.remove(nm)
    finally:
        for ob in made_obj:
            bpy.data.objects.remove(ob, do_unlink=True)
        for me in made_mesh:
            bpy.data.meshes.remove(me)
        for c in (cut_col, tmp):
            if c is not None:
                bpy.data.collections.remove(c)
    if free_inputs:
        target.free()
        for c in cutters:
            c.free()
    if len(out.faces) == 0:
        raise RuntimeError("bm_boolean produced an empty mesh (non-manifold input?)")
    return out


def heal_nonmanifold(bm, max_area=1e-4, passes=4):
    """(rev 3) Boolean cuts that only graze the skin (a pocket corner that just touches the surface) leave tiny sliver sheets
    glued to the mesh: coincident triangles of opposite winding, so some edges have more than two faces.  For every such edge
    keep the two largest faces and delete the others when they are smaller than `max_area` (m^2, default 1 cm^2).  Returns the
    number of deleted faces.  finish_object() calls it after its clean-up (the vertex welding there can create such edges)."""
    total = 0
    for _ in range(passes):
        dead = set()
        for e in bm.edges:
            if len(e.link_faces) > 2:
                fs = sorted(e.link_faces, key=lambda f: f.calc_area())
                for f in fs[:len(fs) - 2]:
                    if f.calc_area() < max_area:
                        dead.add(f)
        if not dead:
            break
        bmesh.ops.delete(bm, geom=list(dead), context='FACES')
        total += len(dead)
        loose_e = [e for e in bm.edges if not e.link_faces]
        if loose_e:
            bmesh.ops.delete(bm, geom=loose_e, context='EDGES')
        loose_v = [v for v in bm.verts if not v.link_edges]
        if loose_v:
            bmesh.ops.delete(bm, geom=loose_v, context='VERTS')
        bm.faces.ensure_lookup_table()
    return total


class Surface:
    """Ray-casting wrapper around a bmesh (car space)."""

    def __init__(self, bm):
        self.bvh = BVHTree.FromBMesh(bm)

    @staticmethod
    def is_radial(ray):
        return isinstance(ray, tuple) and len(ray) == 2 and ray[0] == 'radial'

    def dir_at(self, p_free, ray):
        """Unit direction of the projection ray through p_free (parallel: the ray itself, radial: from the centre)."""
        if self.is_radial(ray):
            return (Vector(p_free) - Vector(ray[1])).normalized()
        return Vector(ray).normalized()

    def hit(self, p_free, ray_dir, far=6.0):
        """Cast a ray through the point p_free and return (location, outward normal) or None.
        ray_dir: a direction vector (parallel projection, the point's component along it is ignored; the ray starts `far`
        metres in front of the surface), or ('radial', C) = point-source projection from a centre C INSIDE the body through
        p_free (use it for features that wrap around curved corners: lamps, intakes, badges)."""
        if self.is_radial(ray_dir):
            C = Vector(ray_dir[1])
            d = (Vector(p_free) - C)
            if d.length < 1e-9:
                return None
            d.normalize()
            loc, nor, idx, dist = self.bvh.ray_cast(C, d, far * 2.0)
            if loc is None:
                return None
            if nor.dot(d) < 0:
                nor = -nor
            return loc, nor.normalized()
        d = Vector(ray_dir).normalized()
        p0 = Vector(p_free) - d * Vector(p_free).dot(d)
        loc, nor, idx, dist = self.bvh.ray_cast(p0 - d * far, d, far * 2.0)
        if loc is None:
            return None
        if nor.dot(d) > 0:
            nor = -nor
        return loc, nor.normalized()

    def closest(self, p):
        loc, nor, idx, dist = self.bvh.find_nearest(Vector(p))
        return (loc, nor) if loc is not None else None


def _axes_for(ray_dir):
    d = Vector(ray_dir).normalized()
    ax = [abs(d.x), abs(d.y), abs(d.z)]
    k = ax.index(max(ax))
    if k == 1:
        return Vector((1, 0, 0)), Vector((0, 0, 1))
    if k == 2:
        return Vector((1, 0, 0)), Vector((0, 1, 0))
    return Vector((0, 1, 0)), Vector((0, 0, 1))


def groove_profile(width=0.006, depth=0.008, lift=0.03):
    """Rectangle profile (lateral, along-normal) for a cutter groove."""
    return [(-width / 2, -depth), (width / 2, -depth), (width / 2, lift), (-width / 2, lift)]


def rib_profile(width=0.03, height=0.012, sink=0.012, round_=0.004):
    """D-shaped raised strip profile (trim, arch moulding, side skirt lip, spoiler lip)."""
    w = width / 2
    r = min(round_, w * 0.9, height * 0.9)
    return [(-w, -sink), (w, -sink), (w, height - r), (w - r * 0.3, height - r * 0.3), (w - r, height),
            (-w + r, height), (-w + r * 0.3, height - r * 0.3), (-w, height - r)]


def _smooth_normals(ns, closed, passes=2):
    n = len(ns)
    for _ in range(passes):
        new = []
        for i in range(n):
            a = ns[(i - 1) % n] if (closed or i > 0) else ns[i]
            b = ns[(i + 1) % n] if (closed or i < n - 1) else ns[i]
            new.append((a + ns[i] * 2 + b).normalized())
        ns = new
    return ns


def surface_sweep(surf, pts, ray_dir, profile, closed=False, caps=True, mat=None, far=6.0, normal_mode='surface'):
    """Sweep a 2D `profile` [(lateral, along_normal), ...] along a path of points that is projected on the surface by a ray
    along ray_dir.  Used for panel-gap cutters (groove_profile), mouldings (rib_profile) and generally anything that must
    hug the body.  Returns a closed bmesh (cap_ends for open paths) or None if the path misses the surface."""
    hits = []
    for p in pts:
        h = surf.hit(Vector(p), ray_dir, far)
        if h is None:
            return None
        hits.append(h)
    n = len(hits)
    locs = [h[0] for h in hits]
    nors = _smooth_normals([h[1] for h in hits], closed)
    rings = []
    for i in range(n):
        if closed:
            t = locs[(i + 1) % n] - locs[(i - 1) % n]
        else:
            t = locs[min(i + 1, n - 1)] - locs[max(i - 1, 0)]
        t = (t - nors[i] * t.dot(nors[i]))
        if t.length < 1e-9:
            t = Vector((1, 0, 0))
        t.normalize()
        w = nors[i].cross(t).normalized()
        rings.append([locs[i] + w * a + nors[i] * b for (a, b) in profile])
    if closed:
        rings.append(rings[0])
        bm = ring_loft(rings, closed=True, caps=False)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-7)
        recalc(bm)
    else:
        bm = ring_loft(rings, closed=True, caps=caps)
    return _set_mat(bm, mat)


def pocket_cutter(surf, outline, center, ray_dir, depth=0.05, lift=0.03, taper=1.0, mat='M_Underbody', axes=None,
                  far=6.0, floor_follows=True):
    """Closed cutter solid whose top follows the surface (+lift outside) and whose floor is `depth` below it.
    outline: convex list of (u,v) in the plane axes (default derived from ray_dir); `taper` < 1 shrinks the floor (bowl).
    Returns bmesh or None."""
    U, V = axes if axes is not None else _axes_for(ray_dir)
    c0 = surf.hit(Vector(center), ray_dir, far)
    if c0 is None:
        return None
    top, bot = [], []
    for (u, v) in outline:
        pt = Vector(center) + U * u + V * v
        h = surf.hit(pt, ray_dir, far)
        if h is None:
            return None
        loc, nor = h
        d = surf.dir_at(pt, ray_dir)
        top.append(loc + nor * lift)
        b = loc - (nor if floor_follows else -d) * depth
        bot.append(c0[0] + (b - c0[0]) * taper if taper != 1.0 else b)
    bm = ring_loft([top, bot], closed=True, caps=True)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    recalc(bm)
    return _set_mat(bm, mat)


def surface_patch(surf, outline, center, ray_dir, offset=0.004, rings=3, mat=None, axes=None, far=6.0, scale=1.0, bulge=0.0):
    """Open patch of the surface bounded by `outline` (u,v) - e.g. lamp lens, glass-like inserts, badges.  Concentric rings
    from the outline to the centre, each ray-cast on the surface and moved `offset` along -normal (negative = outwards).
    bulge > 0 domes the patch outwards by up to `bulge` m in the middle (lamp lenses).
    Returns bmesh with outward-facing normals, or None."""
    U, V = axes if axes is not None else _axes_for(ray_dir)
    c0 = surf.hit(Vector(center), ray_dir, far)
    if c0 is None:
        return None
    bm = bmesh.new()
    prev = None
    n = len(outline)
    allrows = []
    for k in range(rings):
        s = scale * (1.0 - k / float(rings))
        dome = bulge * (1.0 - (1.0 - k / float(rings)) ** 2)
        row = []
        for (u, v) in outline:
            h = surf.hit(Vector(center) + U * (u * s) + V * (v * s), ray_dir, far)
            if h is None:
                bm.free()
                return None
            row.append(bm.verts.new(h[0] - h[1] * (offset - dome)))
        allrows.append(row)
    cverts = bm.verts.new(c0[0] - c0[1] * (offset - bulge))
    for k in range(rings - 1):
        for j in range(n):
            j2 = (j + 1) % n
            bm.faces.new((allrows[k][j], allrows[k][j2], allrows[k + 1][j2], allrows[k + 1][j]))
    for j in range(n):
        j2 = (j + 1) % n
        bm.faces.new((allrows[-1][j], allrows[-1][j2], cverts))
    bm.normal_update()
    avg = Vector()
    for f in bm.faces:
        avg += f.normal
    if avg.dot(c0[1]) < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    return _set_mat(bm, mat)


def anchor_frame(surf, p, ray_dir, sink=0.0, up=(0, 0, 1), far=6.0):
    """4x4 matrix at the surface point hit by a ray through p: local +X = outward surface normal, +Z = `up` made orthogonal,
    origin = hit point moved `sink` metres into the body.  Use to seat inserts that were modelled facing +X (plates, grilles,
    vents, badges).  Returns None when the ray misses."""
    h = surf.hit(Vector(p), ray_dir, far)
    if h is None:
        return None
    loc, nor = h
    up = Vector(up)
    y = up.cross(nor)
    if y.length < 1e-6:
        y = Vector((0, 1, 0))
    y.normalize()
    z = nor.cross(y).normalized()
    m = Matrix((nor, y, z)).transposed().to_4x4()
    m.translation = loc - nor * sink
    return m


def resample_poly(pts, step=0.04):
    """Densify a polyline (list of Vector) so that no segment is longer than `step` (keeps the original points)."""
    out = [Vector(pts[0])]
    for a, b in zip(pts[:-1], pts[1:]):
        a, b = Vector(a), Vector(b)
        n = max(int(math.ceil((b - a).length / step)), 1)
        for i in range(1, n + 1):
            out.append(a + (b - a) * (i / float(n)))
    return out


def circle_pts(cx, cz, r, n=32, y=0.0, axis='XZ'):
    """Points of a circle as 3D positions on the plane axis ('XZ' -> (x, y, z)) to feed surface_sweep."""
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        if axis == 'XZ':
            out.append(Vector((cx + r * math.cos(a), y, cz + r * math.sin(a))))
        elif axis == 'XY':
            out.append(Vector((cx + r * math.cos(a), cz + r * math.sin(a), y)))
        else:
            out.append(Vector((y, cx + r * math.cos(a), cz + r * math.sin(a))))
    return out


def arc_pts(cx, cz, r, a0, a1, n=24, y=0.0):
    """Arc on the XZ plane (angles in degrees, 0 = +X, 90 = +Z)."""
    return [Vector((cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / float(n))), y,
                    cz + r * math.sin(math.radians(a0 + (a1 - a0) * i / float(n))))) for i in range(n + 1)]


def poly_pts(xz_pts, y=0.0, subdiv=0):
    """List of (x,z) -> Vector(x,y,z), optionally subdivided `subdiv` times (midpoints) so surface rays follow curvature."""
    pts = [Vector((p[0], y, p[1])) for p in xz_pts]
    for _ in range(subdiv):
        new = []
        for i in range(len(pts) - 1):
            new += [pts[i], (pts[i] + pts[i + 1]) * 0.5]
        new.append(pts[-1])
        pts = new
    return pts


def wheel_arch_cutter(x, z, radius, side, inner_y=0.30, outer_y=1.3, segments=56, mat='M_Underbody', stretch_up=1.0):
    """Cylinder cutter for one wheel arch (axis along Y). side=+1 left / -1 right. stretch_up>1 makes the top of the arch
    taller (elliptical) for flared arches."""
    L = outer_y - inner_y
    bm = prim_cylinder(radius=radius, depth=L, segments=segments, axis='Y', center=(x, side * (inner_y + L / 2), z), mat=mat)
    if stretch_up != 1.0:
        for v in bm.verts:
            if v.co.z > z:
                v.co.z = z + (v.co.z - z) * stretch_up
    return bm


def carve_wheel_arches(bm, wheels, pad=0.045, inner_y=0.30, mat='M_Underbody', stretch_up=1.0):
    """Boolean-subtract all wheel arches. wheels: dict name -> dict(center=(x,y,z), radius=r)."""
    cutters = []
    for name, w in wheels.items():
        cx, cy, cz = w['center']
        cutters.append(wheel_arch_cutter(cx, cz, w['radius'] + pad, 1 if cy > 0 else -1, inner_y=inner_y, mat=mat,
                                         stretch_up=stretch_up))
    return bm_boolean(bm, cutters)


def bevel_circle_edges(bm, center, radius, axis='Y', tol=3e-4, width=0.012, segments=2, y_min=0.0):
    """Bevel the edges of a boolean wheel-arch hole: edges whose two vertices sit on the cylinder of the given radius."""
    c = Vector(center)
    sel = []
    for e in bm.edges:
        ok = True
        for v in e.verts:
            r = math.hypot(v.co.x - c.x, v.co.z - c.z)
            if abs(r - radius) > tol or abs(v.co.y) < y_min:
                ok = False
                break
        if ok and len(e.link_faces) == 2:
            sel.append(e)
    if not sel:
        return 0
    try:
        bmesh.ops.bevel(bm, geom=sel, offset=width, segments=segments, profile=0.5, material=-1, affect='EDGES', clamp_overlap=True)
    except Exception as ex:
        log("bevel_circle_edges failed:", ex)
        return 0
    return len(sel)


# =====================================================================================================================
# 7. greenhouse: windows cut out of the body shell as thin separate glass shells
# =====================================================================================================================
def face_center_xyz(f):
    return f.calc_center_median()


def inner_trim_from_faces(bm, pred, offset=0.03, mat='M_IntTrim'):
    """Interior trim = copy of the body faces accepted by pred(face), pushed `offset` metres inwards along their (smoothed)
    vertex normals with reversed winding so that they face the cabin.  Single-sided body faces are invisible from inside in
    the engine, so pillars, roof rails and the roof lining are generated this way (they follow the window cut-outs exactly).
    Returns a NEW bmesh (append it to the interior)."""
    sel = [f for f in bm.faces if pred(f)]
    bm.normal_update()
    vn = {}
    for f in sel:
        for v in f.verts:
            vn[v] = vn.get(v, Vector()) + f.normal
    out = bmesh.new()
    vm = {v: out.verts.new(v.co - vn[v].normalized() * offset) for v in vn if vn[v].length > 1e-9}
    m = mi(mat)
    for f in sel:
        try:
            vs = [vm[v] for v in f.verts]
        except KeyError:
            continue
        vs.reverse()
        try:
            nf = out.faces.new(vs)
            nf.material_index = m
            nf.smooth = True
        except ValueError:
            pass
    return out


def extract_glass(bm, windows, offset=0.012, glass_mat='M_Glass', reveal_mat='M_TrimBlack'):
    """Cut windows out of `bm` (modified in place) and return a NEW bmesh with the glass sheets.
    windows: list of dicts
        'pred'  : callable(face)->bool  faces that become glass (after plane cuts)
        'planes': optional list of (point, normal) - the shell is bisected exactly along these planes first (limited to the
                  faces accepted by 'zone') so window edges are straight lines (A/C pillar edges)
        'zone'  : callable(face)->bool  coarse region for the bisect (default = pred)
    The glass sheet is pushed `offset` inwards along the vertex normals; the body gets a reveal strip (reveal_mat) from the
    window edge to the glass edge, so the opening shows a black gasket and no light leaks."""
    glass = bmesh.new()
    gm = mi(glass_mat)
    rm = mi(reveal_mat)
    total = 0
    for w in windows:
        pred = w['pred']
        zone = w.get('zone', pred)
        for (co, no) in w.get('planes', []):
            zf = [f for f in bm.faces if zone(f)]
            geom = set(zf)
            for f in zf:
                geom.update(f.edges)
                geom.update(f.verts)
            if geom:
                bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-6, plane_co=co, plane_no=no)
        bm.normal_update()
        sel = [f for f in bm.faces if pred(f)]
        if not sel:
            log("extract_glass: window", w.get('name', '?'), "selected nothing")
            continue
        sel_set = set(sel)
        vn = {}
        for f in sel:
            for v in f.verts:
                vn[v] = vn.get(v, Vector()) + f.normal
        for v in vn:
            vn[v] = vn[v].normalized()
        gmap = {v: glass.verts.new(v.co - vn[v] * offset) for v in vn}
        for f in sel:
            nf = glass.faces.new([gmap[v] for v in f.verts])
            nf.material_index = gm
            nf.smooth = True
        bedges = set()
        for f in sel:
            for e in f.edges:
                if sum(1 for lf in e.link_faces if lf in sel_set) == 1:
                    bedges.add(e)
        inner = {}
        quads = []
        for e in bedges:
            other = [lf for lf in e.link_faces if lf not in sel_set]
            if not other:
                continue
            f2 = other[0]
            for lp in f2.loops:
                if lp.edge is e:
                    va, vb = lp.vert, lp.link_loop_next.vert
                    break
            for v in (va, vb):
                if v not in inner:
                    inner[v] = bm.verts.new(v.co - vn[v] * offset)
            quads.append((vb, va, inner[va], inner[vb]))
        bmesh.ops.delete(bm, geom=sel, context='FACES')
        for q in quads:
            try:
                nf = bm.faces.new(q)
                nf.material_index = rm
                nf.smooth = False
            except ValueError:
                pass
        total += len(sel)
    bmesh.ops.remove_doubles(glass, verts=list(glass.verts), dist=1e-6)
    log("extract_glass: %d glass faces" % total)
    return glass


# =====================================================================================================================
# 8. detail builders (lamps, grille, mirrors, handles, exhaust, wings, wipers, antenna, plates)
# =====================================================================================================================
def point_in_poly(pt, poly):
    x, y = pt
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi):
            inside = not inside
        j = i
    return inside


def _hex_ring(bm, cx, cz, R, bar, depth, mat):
    """One honeycomb cell: front ring (6 quads) + inner wall (6 quads); the cell faces +X; (cx, cz) in (y, z)."""
    ro, ri = R, max(R - bar, R * 0.3)
    ov, iv, ib = [], [], []
    for k in range(6):
        a = math.radians(60 * k + 30)
        ov.append(bm.verts.new((depth / 2, cx + ro * math.cos(a), cz + ro * math.sin(a))))
        iv.append(bm.verts.new((depth / 2, cx + ri * math.cos(a), cz + ri * math.sin(a))))
        ib.append(bm.verts.new((-depth / 2, cx + ri * math.cos(a), cz + ri * math.sin(a))))
    for k in range(6):
        k2 = (k + 1) % 6
        for quad in ((ov[k], ov[k2], iv[k2], iv[k]), (iv[k], iv[k2], ib[k2], ib[k])):
            try:
                f = bm.faces.new(quad)
                f.material_index = mi(mat)
            except ValueError:
                pass


def grille_mesh(outline, kind='hex', pitch=0.032, bar=0.006, depth=0.02, frame=0.012, mat='M_TrimBlack',
                frame_mat='M_TrimBlack', center_bar=False):
    """Grille / air-intake insert in the YZ plane, front face looks to +X, centred at the origin.
    outline: polygon [(y,z),...] (use outline_rrect/outline_superellipse).  kind: 'hex' honeycomb, 'bars' horizontal slats,
    'grid' square lattice.  A frame tube follows the outline.  Returns bmesh (apply T(...) to place it on the car)."""
    bm = bmesh.new()
    ys = [p[0] for p in outline]
    zs = [p[1] for p in outline]
    y0, y1, z0, z1 = min(ys), max(ys), min(zs), max(zs)
    inset = frame * 0.8
    if kind == 'hex':
        R = pitch / math.sqrt(3.0)
        rowh = pitch * 0.8660254
        nz = int((z1 - z0) / rowh) + 2
        for r in range(-nz, nz + 1):
            z = (z0 + z1) / 2 + r * rowh
            off = (pitch / 2) if (r % 2) else 0.0
            ny = int((y1 - y0) / pitch) + 2
            for c in range(-ny, ny + 1):
                y = (y0 + y1) / 2 + c * pitch + off
                ok = all(point_in_poly((y + dy * R * 0.9, z + dz * R * 0.9), outline)
                         for dy, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                if ok:
                    _hex_ring(bm, y, z, R * 0.97, bar, depth, mat)
    elif kind == 'bars':
        n = max(2, int((z1 - z0) / pitch))
        for i in range(n):
            z = z0 + (i + 0.5) * (z1 - z0) / n
            yy = [p[0] for p in outline if abs(p[1] - z) < (z1 - z0) / n]
            if not yy:
                yy = [y0, y1]
            wy = (max(yy) - min(yy)) - inset * 2
            if wy <= 0.02:
                continue
            b = prim_box(size=(depth, wy, bar), center=(0, (max(yy) + min(yy)) / 2, z), mat=mat, bevel=bar * 0.3, segments=1)
            bm_append(bm, b)
            b.free()
    else:  # grid
        ny = max(2, int((y1 - y0) / pitch))
        nz = max(2, int((z1 - z0) / pitch))
        for i in range(1, nz):
            z = z0 + i * (z1 - z0) / nz
            b = prim_box(size=(depth * 0.7, (y1 - y0) - inset, bar), center=(0, (y0 + y1) / 2, z), mat=mat)
            bm_append(bm, b)
            b.free()
        for i in range(1, ny):
            y = y0 + i * (y1 - y0) / ny
            b = prim_box(size=(depth * 0.7, bar, (z1 - z0) - inset), center=(0, y, (z0 + z1) / 2), mat=mat)
            bm_append(bm, b)
            b.free()
    if center_bar:
        b = prim_box(size=(depth * 1.1, (y1 - y0) - inset, bar * 2.2), center=(0, (y0 + y1) / 2, (z0 + z1) / 2), mat=frame_mat, bevel=bar * 0.5)
        bm_append(bm, b)
        b.free()
    # frame
    path = [(0.0, p[0], p[1]) for p in outline]
    fr = prim_tube(path, radius=(depth * 0.5 + 0.002, frame * 0.5), sides=6, mat=frame_mat, closed=True, up=(1, 0, 0))
    bm_append(bm, fr)
    fr.free()
    return bm


def build_mirror(side=+1, length=0.17, width=0.095, height=0.115, mat_shell='M_Paint2', mat_glass='M_TrimBlack',
                 mat_arm='M_TrimBlack', arm_len=0.07, repeater=True, mat_rim='M_Chrome'):
    """Door mirror in its own local frame: attachment point at the origin, the cap sits at +y*side outwards, glass faces -X
    (to the driver).  rev 3: the cap is a lofted rounded-rectangle shell with a FLAT rear face (rev 2: a pill-shaped bevelled
    box whose square glass plate poked out of the rounded outline), body-colour upper shell + black lower shell, dark neutral
    mirror glass (`mat_glass`) inside a thin chrome rim (`mat_rim`), sturdy arm and wide base block.  Returns bmesh."""
    bm = bmesh.new()
    s = side
    cy = s * (arm_len + width * 0.5)
    zc0 = 0.03
    cut_x = -length * 0.5
    # (t along the cap from the glass side, width scale, height scale, z shift as a fraction of the height)
    prof = [(0.0, 1.00, 1.00, 0.0), (0.03, 1.02, 1.01, 0.0), (0.30, 1.00, 1.00, 0.0), (0.60, 0.88, 0.92, 0.01), (0.82, 0.68, 0.78, 0.03),
            (0.95, 0.42, 0.55, 0.06), (1.0, 0.24, 0.36, 0.08)]
    rings = []
    for (t, sy, sz, dz) in prof:
        rr = max(min(0.030, 0.40 * width * sy, 0.40 * height * sz), 0.004)
        outl = outline_rrect(width * sy, height * sz, rr, 4)
        rings.append([Vector((cut_x + length * t, cy + u, zc0 + height * dz + v)) for (u, v) in outl])
    shell = ring_loft(rings, closed=True, caps=True, mat=mat_shell)
    for f in shell.faces:                              # black lower shell (reads as the mirror's underside housing)
        if f.calc_center_median().z < zc0 - 0.20 * height:
            f.material_index = mi(mat_arm)
    bm_append(bm, shell)
    shell.free()
    rim = prim_prism(outline_rrect(width * 0.90, height * 0.82, 0.026, 4), 0.004, plane='YZ', center=(cut_x + 0.0012, cy, zc0), mat=mat_rim)
    bm_append(bm, rim)
    rim.free()
    gl = prim_prism(outline_rrect(width * 0.84, height * 0.74, 0.022, 4), 0.004, plane='YZ', center=(cut_x - 0.0003, cy, zc0), mat=mat_glass)
    bm_append(bm, gl)
    gl.free()
    arm = prim_tube([(0.03, s * 0.004, -0.012), (0.02, s * arm_len * 0.55, -0.004), (0.0, s * (arm_len + 0.012), 0.016)],
                    radius=(0.026, 0.016), sides=8, mat=mat_arm)
    bm_append(bm, arm)
    arm.free()
    base = prim_box(size=(0.105, 0.050, 0.062), center=(0.022, s * 0.010, -0.008), mat=mat_arm, bevel=0.014)
    bm_append(bm, base)
    base.free()
    if repeater:
        rp = prim_box(size=(0.03, 0.012, 0.012), center=(cut_x + length * 0.66, cy + s * (width * 0.5 * 0.84 - 0.001), zc0 + height * 0.012),
                      mat='M_Indicator', bevel=0.003)
        bm_append(bm, rp)
        rp.free()
    return bm


def build_exhaust_tip(radius=0.034, length=0.11, lip=0.004, segments=24, mat='M_Exhaust', inner_mat='M_Underbody'):
    """Round exhaust tip along X pointing to -X (rearwards), centred at the pipe end at the origin; length goes into +X."""
    prof = [(radius + lip, 0.0), (radius + lip * 1.6, -0.0 + length * 0.04), (radius + lip, length * 0.08),
            (radius, length), (radius - 0.004, length), (radius - 0.004 - lip * 0.5, length * 0.08), (radius - lip * 0.5, 0.0)]
    bm = prim_revolve([(r, h) for (r, h) in prof], segments=segments, axis='X', closed=True, mat=mat)
    # dark inner liner
    liner = prim_cylinder(radius=radius - 0.007, depth=length * 0.9, segments=segments, axis='X', center=(length * 0.5, 0, 0),
                          caps=False, mat=inner_mat)
    bmesh.ops.reverse_faces(liner, faces=list(liner.faces))
    bm_append(bm, liner)
    liner.free()
    return bm


def build_wing(span=1.2, chord=0.24, thick=0.03, mat='M_Paint2', endplate=True, stands=2, stand_h=0.12, rake=-6.0,
               mat_stand='M_TrimBlack', center=(0, 0, 0)):
    """Airfoil-section wing (extruded along Y) with end plates and stands.  Local frame: wing centre at `center`, leading edge
    towards +X.  Returns bmesh."""
    bm = bmesh.new()
    pts = []
    n = 14
    for i in range(n + 1):  # upper surface, LE (+x) to TE (-x)
        t = i / float(n)
        x = chord * (0.5 - t)
        z = thick * 0.5 * (1 - (2 * t - 1) ** 2) ** 0.7 + thick * 0.2 * (1 - t) * 0.0
        pts.append((x, z + thick * 0.15 * (1 - t)))
    for i in range(n - 1, 0, -1):
        t = i / float(n)
        x = chord * (0.5 - t)
        pts.append((x, -thick * 0.35 * (1 - (2 * t - 1) ** 2) ** 0.7))
    prof = prim_prism(pts, span, plane='XZ', mat=mat)
    bmesh.ops.transform(prof, matrix=T(rot=(0, rake, 0)), verts=prof.verts)
    bm_append(bm, prof)
    prof.free()
    if endplate:
        for s in (-1, 1):
            ep = prim_box(size=(chord * 1.05, 0.012, chord * 0.38), center=(-0.01, s * (span / 2 + 0.006), 0.0), mat=mat, bevel=0.004)
            bm_append(bm, ep)
            ep.free()
    for i in range(stands):
        y = (-1 + 2 * (i + 0.5) / stands) * span * 0.32
        st = prim_box(size=(chord * 0.28, 0.022, stand_h), center=(0.0, y, -stand_h / 2 - thick * 0.3), mat=mat_stand, bevel=0.005)
        bm_append(bm, st)
        st.free()
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def build_wiper(pivot, tip, mat='M_TrimBlack', width=0.012, blade_len=0.5, lift=0.012):
    """Wiper arm + blade resting on the glass: pivot/tip are 3D points (already on the glass surface offset by lift)."""
    bm = bmesh.new()
    p0, p1 = Vector(pivot), Vector(tip)
    d = (p1 - p0)
    L = d.length
    d.normalize()
    arm = prim_tube([p0, p0 + d * L * 0.5, p0 + d * L * 0.97], radius=[(0.007, 0.004)] * 3, sides=6, mat=mat, up=(0, 0, 1))
    bm_append(bm, arm)
    arm.free()
    side = d.cross(Vector((0, 0, 1))).normalized()
    # blade: a thin box along the blade direction (tilted ~ along the glass), perpendicular to the arm tip
    bl = prim_box(size=(0.012, blade_len, 0.008), center=(0, 0, 0), mat=mat, bevel=0.002, segments=1)
    ang = math.atan2(side.y, side.x)
    bmesh.ops.transform(bl, matrix=T(loc=p1 - d * 0.02) @ Matrix.Rotation(ang - math.pi / 2, 4, 'Z'), verts=bl.verts)
    bm_append(bm, bl)
    bl.free()
    return bm


def build_shark_fin(length=0.16, height=0.055, width=0.026, mat='M_Paint2', rake=22.0):
    """Roof antenna 'shark fin' in the XZ plane (origin = front-bottom centre).  Returns bmesh (extend slightly below z=0
    so it can be sunk into the roof)."""
    out = [(0.0, -0.01), (length, -0.01), (length * 0.96, 0.012), (length * 0.62, height * 0.86), (length * 0.40, height),
           (length * 0.12, height * 0.55), (0.0, 0.01)]
    bm = prim_prism(out, width, plane='XZ', mat=mat, scale_back=1.0)
    for v in bm.verts:  # taper the top sideways
        f = clamp((v.co.z) / height, 0.0, 1.0)
        v.co.y *= (1.0 - 0.45 * f)
    return bm


def build_plate(width=0.52, height=0.11, thick=0.004, mat='M_Plate'):
    """Number plate (blank) lying in the YZ plane, facing +X."""
    bm = prim_box(size=(thick, width, height), center=(0, 0, 0), mat=mat, bevel=0.004, segments=2)
    return bm


def lamp_unit(surf, center, ray_dir, outline, depth=0.05, lens_inset=0.003, lens_scale=0.96, axes=None, lens_mat='M_Headlight',
              housing_mat='M_TrimBlack', floor_mat='M_Chrome', taper=0.85, lift=0.03, rings=3, extra_ring=None):
    """Generic lamp: returns (cutter_bm, lens_bm).  The cutter (pocket following the surface, floor `depth` below) is
    subtracted from the body; the lens patch (surface-hugging, `lens_inset` below the skin) is added afterwards.  Both are
    computed on the UNCUT surface `surf`.  Floor faces use floor_mat (reflector bowl look), walls housing_mat."""
    cut = pocket_cutter(surf, outline, center, ray_dir, depth=depth, lift=lift, taper=taper, mat=housing_mat, axes=axes)
    if cut is None:
        return None, None
    # floor = faces whose centre is deepest along the ray
    c0 = surf.hit(Vector(center), ray_dir)
    for f in cut.faces:
        if (f.calc_center_median() - c0[0]).dot(c0[1]) < -depth * 0.8:
            f.material_index = mi(floor_mat)
    lens = surface_patch(surf, outline, center, ray_dir, offset=lens_inset, rings=rings, mat=lens_mat, axes=axes, scale=lens_scale)
    return cut, lens


# ---- ring-station helpers for skins, trims, pillars ------------------------------------------------------------------
def shell_skin(shell, name_a, name_b, x0, x1, offset=0.03, side=+1, mat='M_IntTrim', wrap=False, flip=False):
    """Surface offset `offset` INWARDS from a region of the lofted shell: ring columns from control point name_a to name_b
    (on `side`), stations with x in [x0,x1].  wrap=True walks from name_a on +side over the top to name_a on -side (headliner:
    name_a='edge', name_b ignored).  Uses the coordinates stored at loft time.  Returns bmesh (inner trims: headliner, door
    cards, pillar trims).  Normals point INTO the cabin (towards the shell axis) unless flip."""
    pos = shell.pos
    N, H = shell.N, shell.H
    ia, ib = shell.half_idx[name_a], shell.half_idx[name_b]
    if wrap:
        cols = list(range(ia, N - ia + 1))  # edge(+) ... top ... edge(-)
    elif side > 0:
        cols = list(range(ia, ib + 1))
    else:
        cols = list(range(N - ia, N - ib - 1, -1))
    rows = [r for r, x in enumerate(shell.xs) if x0 - 1e-6 <= x <= x1 + 1e-6]
    if len(rows) < 2 or len(cols) < 2:
        return bmesh.new()
    bm = bmesh.new()
    grid = []
    for r in rows:
        line = []
        for ci, j in enumerate(cols):
            p = pos[r][j % N]
            pa = pos[r][cols[max(ci - 1, 0)] % N]
            pb = pos[r][cols[min(ci + 1, len(cols) - 1)] % N]
            tang = Vector((0, pb.y - pa.y, pb.z - pa.z))
            if tang.length < 1e-9:
                line.append(bm.verts.new(p))
                continue
            tang.normalize()
            n = Vector((0, tang.z, -tang.y))  # perpendicular in the YZ plane
            # make n point outward (away from ring centroid axis)
            mid = Vector((p.x, 0, 0.7 * p.z))
            if n.dot(p - mid) < 0:
                n = -n
            line.append(bm.verts.new(p - n * offset))
        grid.append(line)
    for a in range(len(rows) - 1):
        for b in range(len(cols) - 1):
            try:
                f = bm.faces.new((grid[a][b], grid[a][b + 1], grid[a + 1][b + 1], grid[a + 1][b]))
                f.material_index = mi(mat)
            except ValueError:
                pass
    bm.normal_update()
    # orient so that normals look into the cabin (towards y=0 axis)
    flipc = 0
    for f in bm.faces:
        c = f.calc_center_median()
        to_axis = Vector((0, -c.y, 0.7 * (0.8 - c.z)))
        if f.normal.dot(to_axis) < 0:
            flipc += 1
    if flipc > len(bm.faces) / 2:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    if flip:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    return bm


# =====================================================================================================================
# 9. wheel: tyre + rim + brake disc + caliper, axle along Y, origin at the axle centre, outward = +Y (left) / -Y (right)
# =====================================================================================================================
def _interp(keys, r):
    """Piecewise-linear y(r) through ascending (r, y) keys."""
    if r <= keys[0][0]:
        return keys[0][1]
    for (r0, y0), (r1, y1) in zip(keys[:-1], keys[1:]):
        if r <= r1:
            return y0 + (y1 - y0) * (r - r0) / max(r1 - r0, 1e-9)
    return keys[-1][1]


def _tyre(R, w, rb, segs, bulge=1.0, tread=True, lateral=True, groove=0.0065, sipe_pitch=3, emboss=True):
    """Tyre as a closed revolve.  Sidewall with bead + two embossed rings, rounded shoulder, 4 circumferential grooves
    (two per half, symmetric) and slanted lateral sipes cut into the shoulder / inner ribs (V pattern: the two halves slant in
    opposite directions).  Everything is regular and symmetric - no random noise."""
    w2 = w / 2.0
    sw = [(rb - 0.004, 0.62 * w2), (rb + 0.006, 0.72 * w2), (rb + 0.020, 0.90 * w2 * bulge), (rb + 0.052, 0.992 * w2 * bulge),
          (R - 0.060, 1.0 * w2 * bulge), (R - 0.030, 0.975 * w2), (R - 0.014, 0.915 * w2), (R - 0.0035, 0.84 * w2)]
    half = []                                   # (r, y, lane)  lane 0 smooth, 1 shoulder rib, 2 inner rib
    emb = {rb + 0.034: 0.0022, R - 0.047: 0.0014} if emboss else {}
    rings_at = sorted(emb.items())
    for i, (r, y) in enumerate(sw):
        half.append((r, y, 0))
        if i + 1 < len(sw):
            for (re, he) in rings_at:
                if r < re < sw[i + 1][0] - 0.004:
                    for (dr, dy) in ((-0.0035, 0.0), (-0.0024, he), (0.0024, he), (0.0035, 0.0)):
                        half.append((re + dr, _interp(sw, re + dr) + dy, 0))
    if tread:
        g = groove
        half += [(R, 0.0865 * 1.0, 1), (R, 0.0660, 1),
                 (R - g, 0.0640, 0), (R - g, 0.0610, 0), (R, 0.0590, 2),
                 (R, 0.0340, 2), (R - g, 0.0320, 0), (R - g, 0.0290, 0), (R, 0.0270, 0),
                 (R, 0.0, 0)]
    else:
        half += [(R, 0.0865, 0), (R, 0.0, 0)]
    prof = list(half)
    for (r, y, lane) in reversed(half[:-1]):
        prof.append((r, -y, lane))
    bm = bmesh.new()
    n = len(prof)
    npos = len(half)
    rows = []
    for idx, (r, y, lane) in enumerate(prof):
        slant = 1 if idx < npos else -1
        # the two rows that bound a rib get shifted notch phases so that the sipe is slanted across the rib
        row = []
        for k in range(segs):
            rr = r
            if lateral and tread and lane:
                ph = 0 if lane == 1 else 1
                if lane == 1:
                    notch = ((k - (0 if idx in (npos - 10, npos + 8) else slant)) % sipe_pitch) == ph
                else:
                    notch = ((k - (0 if idx in (npos - 6, npos + 4) else slant)) % sipe_pitch) == ph
                if notch:
                    rr = r - groove * 0.62
            a = 2 * math.pi * k / segs
            row.append(bm.verts.new((rr * math.cos(a), y, rr * math.sin(a))))
        rows.append(row)
    for i in range(n):
        i2 = (i + 1) % n
        for k in range(segs):
            k2 = (k + 1) % segs
            try:
                bm.faces.new((rows[i][k], rows[i][k2], rows[i2][k2], rows[i2][k]))
            except ValueError:
                pass
    recalc(bm)
    for f in bm.faces:
        f.material_index = mi('M_Tyre')
    return bm


def _spoke(bm, phi, r0, r1, w0, w1, y_hub, y_rim, th, n=9, curl=0.0, mat='M_Rim', dphi0=0.0, dphi1=0.0, chamfer=0.0045,
           dish_pow=2.0, flare=0.0):
    """One tapered, dished (concave) spoke from hub radius r0 to rim radius r1 at base angle phi (radians, in the XZ plane).
    Chamfered face edges (hexagonal section) so the spokes catch light.  dphi0/dphi1: angular offset (rad) at the hub / rim end
    (twin-spoke fan-out), flare: extra width added over the last 25 % (the spoke melts into the rim face)."""
    rings = []
    for i in range(n):
        t = i / float(n - 1)
        r = lerp(r0, r1, t)
        ph = phi + lerp(dphi0, dphi1, t) + curl * t
        y = y_rim + (y_hub - y_rim) * (1 - t) ** dish_pow
        w = lerp(w0, w1, t) + flare * smoothstep(0.72, 1.0, t)
        e = Vector((math.cos(ph), 0, math.sin(ph)))
        tg = Vector((-math.sin(ph), 0, math.cos(ph)))
        c = e * r + Vector((0, y, 0))
        hth = th * (1.0 - 0.30 * t) / 2
        ch = min(chamfer, w * 0.3, hth * 0.9)
        pts = [(-w / 2, -hth), (w / 2, -hth), (w / 2, hth - ch), (w / 2 - ch, hth), (-w / 2 + ch, hth), (-w / 2, hth - ch)]
        rings.append([c + tg * a + Vector((0, b, 0)) for (a, b) in pts])
    sp = ring_loft(rings, closed=True, caps=True, mat=mat)
    bm_append(bm, sp)
    sp.free()


def _hexnut(r, depth, mat, center, axis='Y'):
    return prim_cylinder(radius=r, depth=depth, segments=6, axis=axis, center=center, mat=mat, bevel=0.0012, bevel_segments=1)


def _caliper(ry, rc, disc_r):
    """Brake caliper in the wheel frame at the 12 o'clock position (rotate it afterwards): outboard + inboard body (rounded
    boxes), bridge over the disc rim, two piston rings, two bolts and a bleed nipple.  ry = axial position of the disc.
    The outboard face stays at ry + 0.032 so that it never touches the spokes.  Returns a bmesh (M_Caliper + M_Chrome)."""
    bm = bmesh.new()
    _add(bm, prim_box((0.112, 0.018, 0.066), (0, ry + 0.023, rc), mat='M_Caliper', bevel=0.007, segments=2))          # outboard
    _add(bm, prim_box((0.112, 0.018, 0.060), (0, ry - 0.023, rc - 0.003), mat='M_Caliper', bevel=0.007, segments=2))  # inboard
    _add(bm, prim_box((0.112, 0.064, 0.016), (0, ry, disc_r + 0.0075), mat='M_Caliper', bevel=0.005, segments=1))      # bridge
    for dx in (-0.028, 0.028):                                                                                       # pistons
        _add(bm, prim_cylinder(radius=0.0165, depth=0.004, segments=14, axis='Y', center=(dx, ry + 0.0315, rc - 0.004),
                               mat='M_BrakeDisc'))
    for dx in (-0.044, 0.044):                                                                                       # bolts
        _add(bm, _hexnut(0.0052, 0.008, 'M_Chrome', (dx, ry + 0.035, rc + 0.020)))
    _add(bm, prim_cylinder(radius=0.0035, depth=0.014, segments=8, axis='Z', center=(0.0, ry + 0.023, disc_r + 0.020), mat='M_Chrome'))
    return bm


def build_wheel(name='wheel', radius=0.32, width=0.215, rim_radius=0.2286, rim_width=0.185, spokes=5, style='multi',
                brake_disc_radius=0.155, caliper=True, side=+1, segments=80, bulge=1.0, hub_radius=0.058, lugs=5,
                caliper_angle=35.0, dish=0.04, tread=True, rim_mat='M_Rim', center_cap_mat='M_RimDark', tyre_segments=None,
                tread_sipes=False):
    """Complete wheel as ONE bmesh (material indices: M_Tyre, M_Rim, M_RimDark, M_BrakeDisc, M_Caliper, M_Chrome).
    Local frame: origin = axle centre, axle = Y, the visible face looks to +Y when side=+1 (left wheels FL/RL); side=-1 returns
    a mirror-built copy (right wheels).  radius = outer tyre radius, rim_radius = rim flange radius, style:
    'multi' (5 twin-spoke pairs = 10 chamfered concave spokes, rim face ring, polished lip), 'star' (single tapered spokes),
    'steel' (pressed steel disc + holes), 'wire' (thin wire spokes).  The tyre has a symmetric 4-groove tread and embossed
    sidewall rings (tread_sipes=True adds slanted lateral notches, only sensible with tyre_segments >= 120); the brake has a
    slotted disc and a body-shaped caliper with bolts.  tyre_segments overrides `segments` for the tyre only."""
    bm = _tyre(radius, width, rim_radius - 0.0127, tyre_segments or segments, bulge=bulge, tread=tread, lateral=tread_sipes)
    rb = rim_radius - 0.0127
    y_out = rim_width / 2.0
    # ---- barrel (closed thin shell profile around Y)
    O = [(rim_radius, -y_out), (rb, -(y_out - 0.015)), (rb - 0.012, -(y_out - 0.03)), (rb - 0.030, -(y_out - 0.045)),
         (rb - 0.030, (y_out - 0.045)), (rb - 0.012, (y_out - 0.03)), (rb, (y_out - 0.015)), (rim_radius, y_out)]
    I = [(r - 0.009, y) for (r, y) in reversed(O)]
    barrel = prim_revolve(O + I, segments=segments, axis='Y', closed=True, mat=rim_mat)
    for f in barrel.faces:   # the well (inner, deep part) reads dark
        c = f.calc_center_median()
        r = math.hypot(c.x, c.z)
        if r < rb - 0.012 and abs(c.y) < y_out - 0.02:
            f.material_index = mi('M_RimDark')
    bm_append(bm, barrel)
    barrel.free()
    # ---- spokes
    y_rim = y_out - 0.018
    y_hub = y_out - dish
    r0, r1 = hub_radius * 0.9, rb - 0.010
    if style in ('multi', 'star'):
        # rim face ring (the spokes melt into it) + polished lip
        ring = prim_revolve([(rb - 0.034, y_rim - 0.016), (rb - 0.034, y_rim + 0.0035), (rb - 0.028, y_rim + 0.0085),
                             (rb - 0.002, y_rim + 0.0085), (rb + 0.0005, y_rim + 0.0045), (rb + 0.0005, y_rim - 0.016)],
                            segments=segments, axis='Y', closed=True, mat=rim_mat)
        bm_append(bm, ring)
        ring.free()
        lip = prim_torus(R=rim_radius - 0.0016, r=0.0036, seg_major=segments, seg_minor=8, axis='Y', center=(0, y_out - 0.0036, 0),
                         mat='M_Chrome')
        bm_append(bm, lip)
        lip.free()
    if style == 'multi':
        for i in range(spokes):
            phi = 2 * math.pi * i / spokes + math.radians(90.0)
            for s in (-1, 1):
                _spoke(bm, phi, r0, r1, 0.025, 0.034, y_hub, y_rim + 0.004, 0.028, n=9, dphi0=s * math.radians(2.6),
                       dphi1=s * math.radians(8.6), mat=rim_mat, chamfer=0.005, flare=0.010)
    elif style == 'star':
        for i in range(spokes):
            phi = 2 * math.pi * i / spokes + math.radians(90.0)
            _spoke(bm, phi, r0, r1, 0.030, 0.040, y_hub, y_rim + 0.004, 0.026, curl=math.radians(8.0), mat=rim_mat, chamfer=0.005,
                   flare=0.012)
    elif style == 'wire':
        for i in range(spokes):
            phi = 2 * math.pi * i / spokes
            for s in (-1, 1):
                _spoke(bm, phi, r0, r1, 0.005, 0.006, y_hub * 0.5, y_rim * 0.5, 0.005, n=3, curl=0.0, dphi0=s * math.radians(2.0),
                       dphi1=s * math.radians(2.0 + 360.0 / spokes * 0.5), mat=rim_mat, chamfer=0.0008)
    else:  # steel disc with holes
        disc = prim_revolve([(0.0, y_hub), (rb - 0.04, y_hub), (rb - 0.015, y_rim), (rb - 0.015, y_rim - 0.012), (rb - 0.04, y_hub - 0.012), (0.0, y_hub - 0.012)],
                            segments=segments, axis='Y', closed=True, mat=rim_mat)
        bm_append(bm, disc)
        disc.free()
    # ---- hub plate, lug nuts, centre cap
    hub = prim_cylinder(radius=hub_radius, depth=0.03, segments=28, axis='Y', center=(0, y_hub - 0.004, 0), mat=rim_mat, bevel=0.005, bevel_segments=2)
    bm_append(bm, hub)
    hub.free()
    for i in range(lugs):
        a = 2 * math.pi * i / lugs + math.radians(90.0)
        lg = _hexnut(0.0098, 0.017, 'M_BrakeDisc', (0.0445 * math.cos(a), y_hub + 0.0165, 0.0445 * math.sin(a)))
        bm_append(bm, lg)
        lg.free()
    cap = prim_cylinder(radius=0.026, depth=0.010, segments=24, axis='Y', center=(0, y_hub + 0.014, 0), mat=center_cap_mat, bevel=0.003, bevel_segments=1)
    bm_append(bm, cap)
    cap.free()
    capr = prim_torus(R=0.0215, r=0.0022, seg_major=24, seg_minor=6, axis='Y', center=(0, y_hub + 0.0192, 0), mat='M_Chrome')
    bm_append(bm, capr)
    capr.free()
    # ---- brake disc (slotted) + hat + caliper
    ry = 0.020
    disc = prim_revolve([(0.082, ry - 0.012), (brake_disc_radius, ry - 0.012), (brake_disc_radius, ry + 0.012), (0.082, ry + 0.012)],
                        segments=segments, axis='Y', closed=True, mat='M_BrakeDisc')
    bm_append(bm, disc)
    disc.free()
    for i in range(24):                      # shallow slots on the outboard face (dark inserts)
        a = 2 * math.pi * i / 24.0
        rr = (0.082 + brake_disc_radius) / 2.0 + 0.004
        sl = prim_box((0.040, 0.0012, 0.0045), (0, 0, 0), mat='M_Underbody')
        bmesh.ops.transform(sl, matrix=T((rr * math.cos(a), ry + 0.0122, rr * math.sin(a)), (0, -math.degrees(a), 0)), verts=sl.verts)
        bm_append(bm, sl)
        sl.free()
    hat = prim_cylinder(radius=0.085, depth=y_hub - ry + 0.01, segments=28, axis='Y', center=(0, (y_hub + ry) / 2 - 0.0, 0), mat='M_BrakeDisc', caps=True)
    bm_append(bm, hat)
    hat.free()
    if caliper:
        cal = _caliper(ry, brake_disc_radius - 0.022, brake_disc_radius)
        bmesh.ops.transform(cal, matrix=T(rot=(0, -caliper_angle, 0)), verts=cal.verts)
        bm_append(bm, cal)
        cal.free()
    if side < 0:
        mirrored = mirrored_copy(bm)
        bm.free()
        bm = mirrored
    return bm


# =====================================================================================================================
# 10. interior + steering wheel
# =====================================================================================================================
def _add(bm, sub, matrix=None, mat=None):
    bm_append(bm, sub, matrix=matrix, mat=mat)
    sub.free()


def build_seat(width=0.50, sport=True, headrest=True, mat='M_IntSeat', mat_shell='M_TrimBlack', mat_trim='M_TrimGrey',
               recline=22.0, back_h=0.60, cushion_len=0.50, bench=False):
    """Seat in its own frame: origin = centre of the cushion bottom on the floor, x forward, z up.  Rounded bolsters, head
    rest, hard shell.  bench=True makes a wide 2-3 person rear bench (width = total)."""
    bm = bmesh.new()
    w = width
    # cushion with raised side bolsters
    _add(bm, prim_box((cushion_len, w, 0.12), (0.0, 0, 0.17), mat=mat, bevel=0.045, segments=3, rot=(0, -4, 0)))
    if sport:   # contrasting centre panel on the cushion
        _add(bm, prim_box((cushion_len * 0.78, w * 0.40, 0.012), (0.0, 0, 0.232), mat=mat_trim, bevel=0.004, segments=1, rot=(0, -4, 0)))
    for s in (-1, 1) if sport else ():
        _add(bm, prim_box((cushion_len * 0.86, 0.075, 0.075), (-0.01, s * (w / 2 - 0.045), 0.225), mat=mat, bevel=0.03, segments=2, rot=(0, -4, 0)))
    _add(bm, prim_box((cushion_len * 0.96, w * 0.86, 0.10), (-0.005, 0, 0.09), mat=mat_shell, bevel=0.02, segments=1))
    # rails / base
    for s in (-1, 1):
        _add(bm, prim_box((cushion_len * 0.8, 0.03, 0.05), (0.0, s * w * 0.32, 0.03), mat=mat_shell, bevel=0.008, segments=1))
    # backrest pivoting at the cushion rear
    back = bmesh.new()
    _add(back, prim_box((0.115, w, back_h), (0.0, 0, back_h / 2), mat=mat, bevel=0.045, segments=3))
    if sport:
        for s in (-1, 1):
            _add(back, prim_box((0.14, 0.075, back_h * 0.70), (0.035, s * (w / 2 - 0.045), back_h * 0.50), mat=mat, bevel=0.03, segments=2))
    _add(back, prim_box((0.02, w * 0.82, back_h * 0.86), (-0.062, 0, back_h * 0.5), mat=mat_shell, bevel=0.01, segments=1))
    if sport:   # contrasting centre panel on the backrest
        _add(back, prim_box((0.012, w * 0.40, back_h * 0.62), (0.058, 0, back_h * 0.52), mat=mat_trim, bevel=0.004, segments=1))
    if headrest:
        _add(back, prim_box((0.085, w * 0.50, 0.15), (0.0, 0, back_h + 0.085), mat=mat, bevel=0.035, segments=3))
        for s in (-1, 1):
            _add(back, prim_cylinder(radius=0.007, depth=0.09, segments=8, axis='Z', center=(0, s * w * 0.14, back_h - 0.01), mat='M_Chrome'))
    bm_append(bm, back, matrix=T((-cushion_len * 0.5 + 0.03, 0, 0.16), (0, -recline, 0)))
    back.free()
    return bm


def build_steering_wheel(rim_radius=0.185, tube=0.0175, tilt=24.0, flat_bottom=True, mat_rim='M_IntDash', mat_trim='M_TrimGrey',
                         mat_hub='M_IntDash', spokes=3, segments=40):
    """Steering wheel with its HUB at the origin, rim plane tilted by `tilt` degrees (baked into the vertices, no object
    rotation).  Returns (bmesh, axis) where axis is the unit normal of the rim plane pointing to the driver (-x, up)."""
    bm = bmesh.new()
    rim = prim_torus(R=rim_radius, r=tube, seg_major=segments, seg_minor=12, axis='X', mat=mat_rim, rz=tube * 1.0)
    if flat_bottom:
        for v in rim.verts:
            if v.co.z < -rim_radius * 0.78:
                v.co.z = -rim_radius * 0.78 - (v.co.z + rim_radius * 0.78) * 0.0
    _add(bm, rim)
    # chrome inlay at 12 o'clock + two thumb rests
    _add(bm, prim_box((tube * 2.2, 0.016, 0.04), (0, 0, rim_radius + tube * 0.4), mat=mat_trim, bevel=0.003, segments=1))
    # spokes (hub to rim)
    for a in ([190.0, 350.0, 270.0] if spokes == 3 else [0, 90, 180, 270]):
        ar = math.radians(a)
        L = rim_radius * 0.86
        c = (0, math.cos(ar) * L * 0.5, math.sin(ar) * L * 0.5)
        sp = prim_box((0.014, L, 0.032 if a != 270.0 else 0.04), (0, 0, 0), mat=mat_hub, bevel=0.005, segments=1)
        # the box lies along Y; rotate about X by `a` so it points to angle a in the YZ plane, then move to its centre
        bmesh.ops.transform(sp, matrix=T(c, (a, 0, 0)), verts=sp.verts)
        _add(bm, sp)
    _add(bm, prim_cylinder(radius=0.05, depth=0.045, segments=24, axis='X', center=(0.0, 0, 0), mat=mat_hub, bevel=0.01, bevel_segments=2))
    _add(bm, prim_cylinder(radius=0.022, depth=0.006, segments=20, axis='X', center=(-0.026, 0, 0), mat=mat_trim))
    bmesh.ops.transform(bm, matrix=T(rot=(0, tilt, 0)), verts=bm.verts)
    a = math.radians(tilt)
    axis = Vector((-math.cos(a), 0.0, math.sin(a)))
    return bm, axis


def build_pedals(x=0.62, y=0.36, z=0.30, manual=True, mat='M_TrimBlack', mat_pad='M_Chrome'):
    """Pedal set (brake, throttle, optional clutch) + dead pedal at the foot well.  Returns bmesh in car space."""
    bm = bmesh.new()
    ys = [-0.10, 0.0, 0.11] if manual else [0.0, 0.11]
    for i, dy in enumerate(ys):
        wid = 0.085 if (manual and i == 2 or (not manual and i == 1)) else 0.075
        arm = prim_box((0.014, 0.014, 0.17), (x + 0.03, y + dy, z + 0.14), mat=mat, bevel=0.003, segments=1, rot=(0, -26, 0))
        pad = prim_box((0.012, wid, 0.095), (x + 0.0, y + dy, z + 0.055), mat=mat, bevel=0.004, segments=1, rot=(0, -26, 0))
        _add(bm, arm)
        _add(bm, pad)
    _add(bm, prim_box((0.03, 0.10, 0.12), (x + 0.02, y - 0.22, z + 0.02), mat=mat, bevel=0.006, segments=1, rot=(0, -26, 0)))
    return bm


def build_shifter(x=0.10, y=0.0, z=0.46, mat='M_IntDash', mat_knob='M_IntSeat', mat_trim='M_Chrome', stick_h=0.12):
    """Gear lever with boot + handbrake lever.  Origin at the centre-console top."""
    bm = bmesh.new()
    _add(bm, prim_cylinder(radius=0.042, depth=0.03, radius2=0.03, segments=16, axis='Z', center=(x, y, z + 0.015), mat='M_IntTrim'))
    _add(bm, prim_cylinder(radius=0.0085, depth=stick_h, segments=10, axis='Z', center=(x, y, z + 0.03 + stick_h / 2), mat=mat_trim))
    _add(bm, prim_sphere(radius=0.03, u=16, v=10, scale=(1, 1, 1.15), center=(x, y, z + 0.03 + stick_h + 0.02), mat=mat_knob))
    _add(bm, prim_box((0.22, 0.026, 0.028), (x - 0.19, y + 0.075, z + 0.015), mat=mat, bevel=0.008, segments=1, rot=(0, 8, 0)))
    return bm


def build_dash(x_back=0.46, x_front=0.82, z_top=0.93, z_low=0.52, half_width=0.70, driver_y=0.36, mat='M_IntDash',
               mat_trim='M_IntTrim', mat_screen='M_IntDash', mat_vent='M_TrimGrey', screen=True, binnacle=True):
    """Instrument panel + binnacle + centre stack + vents.  The pad is an extruded side profile with rounded edges; the
    driver binnacle sits at driver_y (signed). Returns bmesh in car space."""
    bm = bmesh.new()
    prof = [(x_front, z_top + 0.005), (x_back + 0.06, z_top - 0.005), (x_back, z_top - 0.05), (x_back - 0.005, z_top - 0.19),
            (x_back + 0.07, z_low + 0.12), (x_back + 0.18, z_low), (x_front, z_low)]
    pad = prim_prism(prof, half_width * 2, plane='XZ', center=(0, 0, 0), mat=mat)
    bevel_edges = [e for e in pad.edges if abs(e.verts[0].co.y) > half_width * 0.99 and abs(e.verts[1].co.y) > half_width * 0.99]
    try:
        bmesh.ops.bevel(pad, geom=bevel_edges, offset=0.05, segments=3, profile=0.5, material=-1, affect='EDGES', clamp_overlap=True)
    except Exception:
        pass
    _add(bm, pad)
    sgn = 1 if driver_y >= 0 else -1
    def on_face(sub, base, tilt, local, rot=(0, 0, 0)):
        """place a sub-bmesh built around the origin on a tilted dash face: base = face centre, local = offset in the face frame"""
        bmesh.ops.transform(sub, matrix=T(base, (0, -tilt, 0)) @ T(local) @ T(rot=rot), verts=sub.verts)
        _add(bm, sub)

    if binnacle:
        _add(bm, prim_box((0.20, 0.54, 0.115), (x_back + 0.065, driver_y, z_top + 0.045), mat=mat, bevel=0.045, segments=3))
        for dy in (-0.14, 0.14):
            base = (x_back - 0.049, driver_y + dy, z_top + 0.02)
            _add(bm, prim_cylinder(radius=0.075, depth=0.01, segments=28, axis='X', center=(x_back - 0.047, driver_y + dy, z_top + 0.02), mat='M_IntTrim', rot=(0, -12, 0)))
            # dial face: opaque dark plastic (the old M_Glass lens made the Interior mesh translucent -> not Nanite friendly)
            # rev 3: ticks / needles / UI bars use M_Chrome / M_IntTrim - never the lamp slots M_Reverse / M_Indicator (UE maps those to
            # emissive lamp instances, the dash would flash with the reverse light and the indicators)
            _add(bm, prim_cylinder(radius=0.062, depth=0.012, segments=28, axis='X', center=(x_back - 0.049, driver_y + dy, z_top + 0.02), mat='M_TrimBlack', rot=(0, -12, 0)))
            for k in range(11):                                   # scale ticks (emissive white) + needle (emissive amber)
                ang = math.radians(-120.0 + 24.0 * k)
                tk = prim_box((0.0010, 0.0020, 0.0085 if k % 5 == 0 else 0.0055), (0, 0, 0), mat='M_Chrome')
                on_face(tk, base, 12.0, (-0.0068, math.sin(ang) * 0.050, math.cos(ang) * 0.050), rot=(math.degrees(ang) * -1.0, 0, 0))
            nd = prim_box((0.0010, 0.0034, 0.046), (0, 0, 0.023), mat='M_Chrome')
            on_face(nd, base, 12.0, (-0.0072, 0, 0), rot=(-40.0 if dy < 0 else -75.0, 0, 0))
        _add(bm, prim_box((0.012, 0.11, 0.07), (x_back - 0.045, driver_y, z_top + 0.02), mat='M_TrimBlack', bevel=0.004, segments=1, rot=(0, -12, 0)))
        for k, (w_, dz_) in enumerate(((0.080, 0.018), (0.056, 0.004), (0.070, -0.012), (0.040, -0.026))):
            ln = prim_box((0.0010, w_, 0.0040), (0, 0, 0), mat='M_Chrome' if k != 2 else 'M_IntTrim')
            on_face(ln, (x_back - 0.045, driver_y, z_top + 0.02), 12.0, (-0.0065, -(0.11 - w_) * 0.35, dz_))
    cy = 0.0
    if screen:
        _add(bm, prim_box((0.022, 0.28, 0.155), (x_back + 0.045, cy, z_top + 0.035), mat=mat_screen, bevel=0.01, segments=2, rot=(0, -14, 0)))
        # screen: dark opaque face + a few emissive UI elements (kept opaque on purpose, see above)
        _add(bm, prim_box((0.004, 0.25, 0.13), (x_back + 0.033, cy, z_top + 0.035), mat='M_TrimBlack', bevel=0.002, segments=1, rot=(0, -14, 0)))
        sb = (x_back + 0.033, cy, z_top + 0.035)
        hdr = prim_box((0.0010, 0.21, 0.010), (0, 0, 0), mat='M_Chrome')
        on_face(hdr, sb, 14.0, (-0.0026, 0.0, 0.048))
        for k, hh in enumerate((0.030, 0.052, 0.040, 0.066, 0.046)):
            bar = prim_box((0.0010, 0.016, hh), (0, 0, 0), mat='M_IntTrim')
            on_face(bar, sb, 14.0, (-0.0026, -0.075 + 0.036 * k, -0.050 + hh / 2.0))
        mp = prim_box((0.0010, 0.070, 0.050), (0, 0, 0), mat='M_IntTrim')
        on_face(mp, sb, 14.0, (-0.0026, 0.075, -0.026))
    for (yy, zz) in ((cy - 0.19, z_top - 0.07), (cy + 0.19, z_top - 0.07), (cy - 0.085, z_top - 0.095), (cy + 0.085, z_top - 0.095)):
        _add(bm, prim_box((0.008, 0.08, 0.034), (x_back - 0.004, yy, zz), mat=mat_vent, bevel=0.006, segments=1))
    # centre stack / console face
    _add(bm, prim_box((0.10, 0.24, 0.34), (x_back + 0.11, cy, z_top - 0.22), mat=mat_trim, bevel=0.03, segments=2))
    for i in range(3):
        _add(bm, prim_cylinder(radius=0.022, depth=0.012, segments=14, axis='X', center=(x_back + 0.055, cy - 0.07 + i * 0.07, z_top - 0.19), mat='M_Chrome'))
    return bm


def build_console(x0=-0.45, x1=0.42, z_floor=0.22, z_top=0.56, width=0.22, mat='M_IntDash', mat_trim='M_IntTrim'):
    """Transmission tunnel / centre console with armrest and cup-holder recess (visual only)."""
    bm = bmesh.new()
    L = x1 - x0
    _add(bm, prim_box((L, width, z_top - z_floor), ((x0 + x1) / 2, 0, (z_top + z_floor) / 2), mat=mat, bevel=0.05, segments=3))
    _add(bm, prim_box((0.34, width * 0.9, 0.06), (x0 + 0.20, 0, z_top + 0.03), mat=mat_trim, bevel=0.02, segments=2))
    for dx in (0.0, 0.11):
        _add(bm, prim_cylinder(radius=0.033, depth=0.01, segments=18, axis='Z', center=(x1 - 0.25 - dx, 0, z_top + 0.001), mat='M_Underbody'))
    return bm


def build_interior(shell=None, spec=None):
    """Complete cockpit as ONE bmesh in car space (cockpit camera quality): carpet floor + tunnel, door cards / quarter trims /
    headliner derived from the body shell (shell_skin), 2 front + rear seats, dash with binnacle, console, pedals, shifter,
    column shroud, rear-view mirror.  The steering wheel is a separate object (build_steering_wheel).
    spec overrides (defaults for a compact 3-door hatch, left-hand drive):
      floor_z, front_x (seat cushion centre x), driver_y, rear_x, rear_width, dash_x_back, dash_z_top, hw (cabin half width),
      x_front_floor, x_rear_floor, door_x=(x0,x1), quarter_x, roof_x=(x0,x1), roof_z (for the rear shelf), seats_rear (bool)."""
    S = dict(floor_z=0.22, front_x=-0.12, driver_y=0.36, rear_x=-0.98, rear_width=1.22, dash_x_back=0.46, dash_z_top=0.93,
             hw=0.74, x_front_floor=0.80, x_rear_floor=-1.72, door_x=(-0.58, 0.64), quarter_x=(-1.72, -0.58),
             roof_x=(-1.72, 0.12), seats_rear=True, rear_z=0.26, front_z=0.27, back_h=0.62, sport=True)
    if spec:
        S.update(spec)
    bm = bmesh.new()
    fz = S['floor_z']
    # floor carpet + footwell
    _add(bm, prim_box((S['x_front_floor'] - S['x_rear_floor'], S['hw'] * 2 - 0.1, 0.03),
                      ((S['x_front_floor'] + S['x_rear_floor']) / 2, 0, fz - 0.015), mat='M_IntCarpet', bevel=0.01, segments=1))
    _add(bm, build_console(x0=-0.40, x1=0.46, z_floor=fz, z_top=fz + 0.30))
    # seats
    dy = S['driver_y']
    for yy in (dy, -dy):
        _add(bm, build_seat(width=0.50, sport=S['sport'], back_h=S['back_h']), matrix=T((S['front_x'], yy, S['front_z'])))
    if S['seats_rear']:
        _add(bm, build_seat(width=S['rear_width'], sport=False, back_h=0.56, cushion_len=0.46, recline=18.0, bench=True),
             matrix=T((S['rear_x'], 0, S['rear_z'])))
    # dash + pedals + shifter + column
    _add(bm, build_dash(x_back=S['dash_x_back'], z_top=S['dash_z_top'], half_width=S['hw'] - 0.03, driver_y=dy))
    _add(bm, build_pedals(x=S['dash_x_back'] + 0.16, y=dy, z=fz + 0.07))
    _add(bm, build_shifter(x=0.10, y=0.0, z=fz + 0.30))
    col_hub = Vector((S['dash_x_back'] - 0.06, dy, S['dash_z_top'] - 0.04))
    _add(bm, prim_cylinder(radius=0.048, depth=0.2, segments=16, axis='X', center=(col_hub.x + 0.09, col_hub.y, col_hub.z - 0.03), mat='M_IntDash', rot=(0, -20, 0), bevel=0.01))
    # rear-view mirror
    _add(bm, prim_box((0.03, 0.22, 0.065), (0.30, 0.0, S['dash_z_top'] + 0.37), mat='M_IntDash', bevel=0.012, segments=2))
    _add(bm, prim_cylinder(radius=0.008, depth=0.07, segments=8, axis='Z', center=(0.33, 0, S['dash_z_top'] + 0.405), mat='M_IntDash'))
    # skins derived from the shell (door cards, quarter trims, headliner)
    if shell is not None:
        x0, x1 = S['door_x']
        for sd in (1, -1):
            _add(bm, shell_skin(shell, 'sill', 'belt_up', x0, x1, offset=0.045, side=sd, mat='M_IntTrim'))
            q0, q1 = S['quarter_x']
            _add(bm, shell_skin(shell, 'sill', 'belt_up', q0, q1, offset=0.045, side=sd, mat='M_IntTrim'))
        if S.get('headliner', True):
            r0, r1 = S['roof_x']
            _add(bm, shell_skin(shell, 'edge', 'edge', r0, r1, offset=0.04, wrap=True, mat='M_IntTrim'))
        # door armrests + pulls
        for sd in (1, -1):
            _add(bm, prim_box((0.34, 0.05, 0.05), (0.06, sd * (S['hw'] - 0.08), 0.70), mat='M_IntDash', bevel=0.02, segments=2))
            _add(bm, prim_box((0.20, 0.03, 0.03), (-0.10, sd * (S['hw'] - 0.07), 0.58), mat='M_Chrome', bevel=0.008, segments=1))
    return bm


# =====================================================================================================================
# 11. collision hulls + UV
# =====================================================================================================================
def hull_points_from_shell(shell, x_list, names, z_clip=(None, None), shrink=0.0):
    """Points (car space) for a convex hull: at every station x in x_list take the ring control points `names` (both sides),
    optionally clamp z into z_clip=(zmin,zmax) and pull the points `shrink` m towards the centre line."""
    pts = []
    for x in x_list:
        ctrl = dict(ring_controls(shell.cv, x))
        for n in names:
            y, z = ctrl[n]
            if z_clip[0] is not None:
                z = max(z, z_clip[0])
            if z_clip[1] is not None:
                z = min(z, z_clip[1])
            y = max(y - shrink, 0.0)
            pts.append(Vector((x, y, z)))
            if y > 1e-6:
                pts.append(Vector((x, -y, z)))
    return pts


def hull_bmesh(points, merge_dist=1e-4, dissolve_deg=0.0):
    """Convex hull of a point cloud as a triangulated bmesh (dissolve_deg > 0 merges near-coplanar faces, which can make the
    hull very slightly non-convex, so it is off by default). Returns (bm, vertex_count)."""
    bm = bmesh.new()
    for p in points:
        bm.verts.new(p)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=merge_dist)
    res = bmesh.ops.convex_hull(bm, input=list(bm.verts), use_existing_faces=False)
    dead = list(set(g for g in (res.get('geom_interior', []) + res.get('geom_unused', [])) if isinstance(g, bmesh.types.BMVert)))
    if dead:
        bmesh.ops.delete(bm, geom=dead, context='VERTS')
    if dissolve_deg > 0:
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(dissolve_deg), verts=list(bm.verts), edges=list(bm.edges))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm, len(bm.verts)


def make_ucx_hulls(car_id, hulls, collection, parent, max_verts=32):
    """Create UCX_<car_id>_Body_NN convex collision objects from `hulls` (list of point lists).  Objects get the car origin as
    pivot, no materials, display as wire.  Returns the list of objects."""
    out = []
    for i, pts in enumerate(hulls, start=1):
        bm, n = hull_bmesh(pts)
        if n > max_verts:
            log("WARNING hull %d has %d verts (> %d)" % (i, n, max_verts))
        name = "UCX_%s_Body_%02d" % (car_id, i)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        ob.display_type = 'WIRE'
        collection.objects.link(ob)
        ob.parent = parent
        ob.matrix_parent_inverse = Matrix.Identity(4)
        out.append(ob)
    return out


def uv_unwrap(ob, angle=66.0, margin=0.004, layer_name="UVMap"):
    """Non-overlapping UVMap: smart project + island packing (operators, edit mode round-trip).  Selection/active object are
    restored afterwards."""
    vl = bpy.context.view_layer
    prev_active = vl.objects.active
    prev_sel = [o for o in vl.objects if o.select_get()]
    try:
        for o in prev_sel:
            o.select_set(False)
        ob.select_set(True)
        vl.objects.active = ob
        if ob.data.uv_layers:
            for l in list(ob.data.uv_layers):
                ob.data.uv_layers.remove(l)
        ob.data.uv_layers.new(name=layer_name)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin, area_weight=0.0, correct_aspect=True,
                                 scale_to_bounds=False)
        try:
            bpy.ops.uv.pack_islands(margin=margin, rotate=True)
        except Exception:
            bpy.ops.uv.pack_islands(margin=margin)
        bpy.ops.object.mode_set(mode='OBJECT')
    finally:
        try:
            if bpy.context.mode != 'OBJECT':
                bpy.ops.object.mode_set(mode='OBJECT')
        except Exception:
            pass
        ob.select_set(False)
        for o in prev_sel:
            try:
                o.select_set(True)
            except Exception:
                pass
        vl.objects.active = prev_active
    if ob.data.uv_layers and ob.data.uv_layers[0].name != layer_name:
        ob.data.uv_layers[0].name = layer_name
    return ob


def uv_livery_layer(ob, layer_name="UVLivery", margin=0.006, ref=None):
    """Second UV channel for stripes / liveries / decals.  The whole mesh is projected on 5 big planar islands (box mapping):
    top (hood, roof, deck, underside), left side, right side, front, rear - each one a single coherent rectangle in 0..1, so a
    stripe that runs over the roof or hood is one straight texture stripe.  Scale is uniform (about 0.17 uv per metre).
    Orientation: every island is seen from OUTSIDE (text reads correctly).  The primary channel 'UVMap' is untouched and stays
    first.  Islands of different projection planes overlap nothing (each has its own rectangle); mirrored faces inside one plane
    overlap by design (this channel is for paint decals, never for baked lighting)."""
    import numpy as np
    me = ob.data
    uvl = me.uv_layers.get(layer_name) or me.uv_layers.new(name=layer_name)
    nl, nv, npoly = len(me.loops), len(me.vertices), len(me.polygons)
    co = np.empty(nv * 3, dtype=np.float32)
    me.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    lv = np.empty(nl, dtype=np.int32)
    me.loops.foreach_get('vertex_index', lv)
    pn = np.empty(npoly * 3, dtype=np.float32)
    me.polygons.foreach_get('normal', pn)
    pn = pn.reshape(-1, 3)
    tot = np.empty(npoly, dtype=np.int32)
    me.polygons.foreach_get('loop_total', tot)
    ax = np.abs(pn)
    cls = np.where((ax[:, 2] >= ax[:, 0]) & (ax[:, 2] >= ax[:, 1]), 0,
                   np.where(ax[:, 1] >= ax[:, 0], np.where(pn[:, 1] > 0, 1, 2), np.where(pn[:, 0] > 0, 3, 4)))
    cl = np.repeat(cls, tot)
    P = co[lv]
    xmin, xmax = float(co[:, 0].min()), float(co[:, 0].max())
    ymin, ymax = float(co[:, 1].min()), float(co[:, 1].max())
    zmin, zmax = float(co[:, 2].min()), float(co[:, 2].max())
    L, W, H = xmax - xmin, ymax - ymin, zmax - zmin
    m = margin
    s = (1.0 - 3.0 * m) / (L + W)
    s = min(s, (1.0 - 4.0 * m) / (W + 2.0 * H))
    colB = m + L * s + m                       # x of the front/rear column
    uv = np.zeros((nl, 2), dtype=np.float32)
    sel = cl == 0                              # top: u = x, v = y (seen from above, nose to the right)
    uv[sel, 0] = m + (P[sel, 0] - xmin) * s
    uv[sel, 1] = m + (P[sel, 1] - ymin) * s
    v1 = m + W * s + m
    sel = cl == 1                              # left side seen from +Y: nose on the left
    uv[sel, 0] = m + (xmax - P[sel, 0]) * s
    uv[sel, 1] = v1 + (P[sel, 2] - zmin) * s
    v2 = v1 + H * s + m
    sel = cl == 2                              # right side seen from -Y
    uv[sel, 0] = m + (P[sel, 0] - xmin) * s
    uv[sel, 1] = v2 + (P[sel, 2] - zmin) * s
    sel = cl == 3                              # front seen from +X
    uv[sel, 0] = colB + (P[sel, 1] - ymin) * s
    uv[sel, 1] = m + (P[sel, 2] - zmin) * s
    sel = cl == 4                              # rear seen from -X
    uv[sel, 0] = colB + (ymax - P[sel, 1]) * s
    uv[sel, 1] = m + H * s + m + (P[sel, 2] - zmin) * s
    uvl.data.foreach_set('uv', uv.ravel())
    try:
        me.uv_layers.active_index = 0
        me.uv_layers[0].active_render = True
    except Exception:
        pass
    me.update()
    return ob


def uv_overlap_ratio(mesh, res=512, layer="UVMap"):
    """Approximate fraction of covered UV pixels that are covered by more than one triangle (0 = clean)."""
    import numpy as np
    uvl = mesh.uv_layers.get(layer)
    if uvl is None:
        return None
    mesh.calc_loop_triangles()
    cover = np.zeros((res, res), dtype=np.int16)
    uv = uvl.data
    for tri in mesh.loop_triangles:
        a, b, c = [uv[l].uv for l in tri.loops]
        xs = (a.x, b.x, c.x)
        ys = (a.y, b.y, c.y)
        x0, x1 = int(max(min(xs) * res - 0.5, 0)), int(min(max(xs) * res + 0.5, res - 1))
        y0, y1 = int(max(min(ys) * res - 0.5, 0)), int(min(max(ys) * res + 0.5, res - 1))
        if x1 < x0 or y1 < y0:
            continue
        px = (np.arange(x0, x1 + 1) + 0.5) / res
        py = (np.arange(y0, y1 + 1) + 0.5) / res
        X, Y = np.meshgrid(px, py)
        d = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
        if abs(d) < 1e-14:
            continue
        w1 = ((b.y - c.y) * (X - c.x) + (c.x - b.x) * (Y - c.y)) / d
        w2 = ((c.y - a.y) * (X - c.x) + (a.x - c.x) * (Y - c.y)) / d
        w3 = 1.0 - w1 - w2
        m = (w1 > 1e-6) & (w2 > 1e-6) & (w3 > 1e-6)
        cover[y0:y1 + 1, x0:x1 + 1] += m.astype(np.int16)
    covered = int((cover > 0).sum())
    return float((cover > 1).sum()) / covered if covered else 0.0


# =====================================================================================================================
# 12. root props, validation, export
# =====================================================================================================================
ROOT_PROPS = ['wheelbase', 'track_front', 'track_rear', 'wheel_radius_front', 'wheel_radius_rear', 'wheel_width_front',
              'wheel_width_rear', 'ride_height', 'length', 'width', 'height']
CONTRACT_MATERIALS = set(MAT_ORDER)
PART_SUFFIXES = ['Body', 'Glass', 'Interior', 'SteeringWheel', 'Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR']
EMPTY_SUFFIXES = ['LP_HeadL', 'LP_HeadR', 'LP_TailL', 'LP_TailR', 'LP_Reverse', 'CAM_Hood', 'CAM_Cockpit', 'CAM_Bumper',
                  'EXHAUST_L', 'EXHAUST_R']


def set_root_props(root, **props):
    for k, v in props.items():
        root[k] = v


def _mesh_stats(me):
    """Health statistics of a mesh datablock."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.edges.ensure_lookup_table()
    st = dict(verts=len(bm.verts), faces=len(bm.faces), tris=tri_count(bm))
    st['loose_verts'] = sum(1 for v in bm.verts if not v.link_edges)
    st['loose_edges'] = sum(1 for e in bm.edges if not e.link_faces)
    st['boundary_edges'] = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    st['nonmanifold_edges'] = sum(1 for e in bm.edges if len(e.link_faces) > 2)
    st['ngons'] = sum(1 for f in bm.faces if len(f.verts) > 4)
    st['degenerate'] = sum(1 for f in bm.faces if f.calc_area() < 1e-10)
    # flipped islands: signed volume of closed islands
    seen = set()
    flipped = 0
    closed_islands = 0
    open_islands = 0
    for f0 in bm.faces:
        if f0 in seen:
            continue
        stack = [f0]
        seen.add(f0)
        isl = []
        closed = True
        while stack:
            f = stack.pop()
            isl.append(f)
            for e in f.edges:
                if len(e.link_faces) != 2:
                    closed = False
                for nf in e.link_faces:
                    if nf not in seen:
                        seen.add(nf)
                        stack.append(nf)
        if closed:
            closed_islands += 1
            vol = 0.0
            for f in isl:
                c = f.calc_center_median()
                vol += f.calc_area() * f.normal.dot(c)
            if vol < 0:
                flipped += 1
        else:
            open_islands += 1
    st['flipped_islands'] = flipped
    st['closed_islands'] = closed_islands
    st['open_islands'] = open_islands
    bm.free()
    return st


def _is_convex(me, tol=1e-4):
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    ok = True
    for f in bm.faces:
        c = f.calc_center_median()
        for v in bm.verts:
            if f.normal.dot(v.co - c) > tol:
                ok = False
                break
        if not ok:
            break
    bm.free()
    return ok


def validate_car(root_name, targets=None, verbose=True):
    """Check one car against the contract.  Returns dict(ok, errors, warnings, stats).  `targets` optional dict of expected
    values e.g. {'length':3.95,'width':1.78,'height':1.44,'wheelbase':2.52}.  Prints a compact report."""
    errors, warnings, stats = [], [], {}
    root = bpy.data.objects.get(root_name)
    if root is None:
        return dict(ok=False, errors=["root %s missing" % root_name], warnings=[], stats={})
    car = root_name[:-5] if root_name.endswith('_ROOT') else root_name
    for p in ROOT_PROPS:
        if p not in root.keys():
            errors.append("root custom property missing: " + p)
    objs = {}
    for suf in PART_SUFFIXES:
        o = bpy.data.objects.get("%s_%s" % (car, suf))
        if o is None:
            errors.append("missing object %s_%s" % (car, suf))
        else:
            objs[suf] = o
    for suf in EMPTY_SUFFIXES:
        if bpy.data.objects.get("%s_%s" % (car, suf)) is None:
            errors.append("missing empty %s_%s" % (car, suf))
    ucx = sorted([o for o in bpy.data.objects if o.name.startswith("UCX_%s_Body_" % car)], key=lambda o: o.name)
    if not (2 <= len(ucx) <= 6):
        errors.append("UCX hull count %d not in 2..6" % len(ucx))
    total = 0
    uv_info = {}
    mats = {}
    for suf, o in objs.items():
        me = o.data
        if o.type != 'MESH':
            errors.append(o.name + " is not a mesh")
            continue
        if o.parent is not root:
            errors.append(o.name + " is not parented to the root")
        if any(abs(a) > 1e-6 for a in o.rotation_euler) or any(abs(s - 1.0) > 1e-6 for s in o.scale):
            errors.append(o.name + " has rotation/scale not applied")
        mpi = o.matrix_parent_inverse
        if max(abs(mpi[i][j] - (1.0 if i == j else 0.0)) for i in range(4) for j in range(4)) > 1e-6:
            warnings.append(o.name + " parent inverse is not identity")
        if len(o.modifiers):
            errors.append(o.name + " still has modifiers")
        st = _mesh_stats(me)
        stats[suf] = st
        total += st['tris']
        if st['loose_verts'] or st['loose_edges']:
            errors.append("%s loose geometry: %d verts %d edges" % (o.name, st['loose_verts'], st['loose_edges']))
        if st['nonmanifold_edges']:
            errors.append("%s non-manifold edges (>2 faces): %d" % (o.name, st['nonmanifold_edges']))
        if st['flipped_islands']:
            errors.append("%s has %d closed islands with inverted normals" % (o.name, st['flipped_islands']))
        if st['degenerate']:
            warnings.append("%s degenerate faces: %d" % (o.name, st['degenerate']))
        if suf in ('Body',) and st['boundary_edges']:
            warnings.append("%s open boundary edges (window reveals, lens patches, liners - by design): %d" % (o.name, st['boundary_edges']))
        names = [m.name if m else None for m in me.materials]
        mats[suf] = names
        for n in names:
            if n is None or n not in CONTRACT_MATERIALS:
                errors.append("%s material slot '%s' not in contract" % (o.name, n))
        if suf == 'Body' and 'M_Paint' not in names:
            errors.append("Body has no M_Paint slot")
        if suf == 'Glass' and names != ['M_Glass']:
            warnings.append("Glass slots %s (expected only M_Glass)" % names)
        if suf != 'Glass' and 'M_Glass' in names:
            errors.append("%s uses the translucent M_Glass slot (only <id>_Glass may; it breaks Nanite eligibility in UE)" % o.name)
        if suf != 'Body':           # rev 3: the lamp slots drive emissive lamp instances in UE (reverse light, indicators, brake ...)
            bad = [n for n in names if n in LAMP_SLOTS]
            if bad:
                errors.append("%s uses lamp slots %s (only <id>_Body may: UE lights them with the reverse / indicator / brake state)" % (o.name, bad))
        uvl = me.uv_layers.get('UVMap')
        if uvl is None:
            errors.append(o.name + " has no UVMap")
        else:
            ov = uv_overlap_ratio(me, res=384) if st['tris'] < 120000 else None
            uv_info[suf] = ov
            if ov is not None and ov > 0.02:
                errors.append("%s UV overlap %.1f%%" % (o.name, ov * 100))
            if me.uv_layers and any(not (-1e-4 <= u.uv.x <= 1 + 1e-4 and -1e-4 <= u.uv.y <= 1 + 1e-4) for u in uvl.data):
                errors.append(o.name + " UVs outside 0..1")
    stats['uv_overlap'] = uv_info
    stats['materials'] = mats
    # origins / wheels
    Wp = {}
    for k in ('FL', 'FR', 'RL', 'RR'):
        w = objs.get('Wheel_' + k)
        if w is None:
            continue
        vs = [v.co for v in w.data.vertices]
        mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        c = (mn + mx) / 2
        rad = (mx.z - mn.z) / 2
        wid = mx.y - mn.y
        Wp[k] = dict(center=tuple(round(v, 4) for v in w.location), radius=round(rad, 4), width=round(wid, 4))
        if abs(c.x) > 0.004 or abs(c.z) > 0.004:
            errors.append("%s pivot not at axle centre (bbox centre %.4f,%.4f)" % (w.name, c.x, c.z))
        if abs(w.location.z - rad) > 0.004:
            errors.append("%s axle height %.4f != radius %.4f (tyre does not touch z=0)" % (w.name, w.location.z, rad))
        if (k.endswith('L') and w.location.y <= 0) or (k.endswith('R') and w.location.y >= 0):
            errors.append("%s on the wrong side" % w.name)
    stats['wheels'] = Wp
    for suf in ('Body', 'Glass', 'Interior'):
        o = objs.get(suf)
        if o is not None and o.location.length > 1e-6:
            errors.append("%s origin is not the car origin: %s" % (o.name, tuple(o.location)))
    sw = objs.get('SteeringWheel')
    if sw is not None:
        vs = [v.co for v in sw.data.vertices]
        c = (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))) +
             Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))) / 2
        if abs(c.y) > 0.006:
            warnings.append("steering wheel hub off-centre in y by %.3f" % c.y)
    # dimensions
    body = objs.get('Body')
    if body is not None:
        vs = [v.co for v in body.data.vertices]
        mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        dims = dict(length=mx.x - mn.x, width_with_mirrors=mx.y - mn.y, height=mx.z, min_z=mn.z)
        stats['dims'] = {k: round(v, 3) for k, v in dims.items()}
        if mn.z < 0.02:
            errors.append("Body dips to z=%.3f (too close to the ground)" % mn.z)
        if targets:
            for k, tv in targets.items():
                have = root.get(k)
                if have is not None and abs(have - tv) > max(0.05, tv * 0.03):
                    warnings.append("%s = %.3f differs from target %.3f" % (k, have, tv))
    # UCX
    for h in ucx:
        st = _mesh_stats(h.data)
        if len(h.data.vertices) > 32:
            errors.append("%s has %d verts (> 32)" % (h.name, len(h.data.vertices)))
        if not _is_convex(h.data):
            errors.append("%s is not convex" % h.name)
        if h.parent is not root:
            errors.append(h.name + " not parented to root")
    stats['ucx'] = [(h.name, len(h.data.vertices)) for h in ucx]
    stats['total_tris'] = total
    if not (60000 <= total <= 150000):
        warnings.append("total triangles %d outside the 60k-150k budget" % total)
    ok = not errors
    if verbose:
        print("=== validate_car(%s): %s | tris %d ===" % (car, "OK" if ok else "FAILED", total))
        for k, st in stats.items():
            if k in ('Body', 'Glass', 'Interior', 'SteeringWheel', 'Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'):
                print("  %-14s tris %6d  verts %6d  open-edges %4d  ngons %5d  islands closed/open %d/%d  uv-overlap %s" % (
                    k, st['tris'], st['verts'], st['boundary_edges'], st['ngons'], st['closed_islands'], st['open_islands'],
                    ("%.2f%%" % (uv_info.get(k, 0) * 100)) if uv_info.get(k) is not None else "n/a"))
        print("  dims:", stats.get('dims'), "| wheels:", Wp)
        print("  ucx:", stats['ucx'])
        for e in errors:
            print("  ERROR  ", e)
        for w in warnings:
            print("  warning", w)
    return dict(ok=ok, errors=errors, warnings=warnings, stats=stats)


_FBX = {}


def _fbx_export_fn():
    if 'fn' not in _FBX:
        path = os.path.join(project_dir(), 'Tools', 'blender', 'lib', 'fbx_export.py')
        ns = {'__name__': 'fbx_export'}
        exec(compile(open(path, encoding='utf8').read(), path, 'exec'), ns)
        _FBX['fn'] = ns['export_fbx']
    return _FBX['fn']


def export_car(root_name, out_dir=None, display_name=None):
    """Write the per-part FBX files + sidecar JSON of BLENDER_CONTRACT.md section 5 into Exports/Cars/<id>/.
    Everything in the JSON is read from the scene (wheel centres, empties, dimensions, triangle counts)."""
    export_fbx = _fbx_export_fn()
    root = bpy.data.objects[root_name]
    car = root_name[:-5]
    out_dir = out_dir or os.path.join(project_dir(), 'Exports', 'Cars', car)
    os.makedirs(out_dir, exist_ok=True)
    bpy.context.view_layer.update()
    ucx = sorted([o for o in bpy.data.objects if o.name.startswith("UCX_%s_Body_" % car)], key=lambda o: o.name)
    written = {}

    def out(part):
        return os.path.join(out_dir, "%s_%s.fbx" % (car, part))

    jobs = [('Body', [car + '_Body'] + [h.name for h in ucx], root),
            ('Glass', [car + '_Glass'], root),
            ('Interior', [car + '_Interior'], root),
            ('SteeringWheel', [car + '_SteeringWheel'], 'self')]
    for k in ('FL', 'FR', 'RL', 'RR'):
        jobs.append(('Wheel_' + k, ['%s_Wheel_%s' % (car, k)], 'self'))
    hid = [(h, h.hide_get()) for h in ucx]
    vl = bpy.context.view_layer
    prev_active = vl.objects.active
    prev_sel = [o for o in vl.objects if o.select_get()]
    for h, _ in hid:
        h.hide_set(False)          # hidden objects cannot be selected for the export
    try:
        for part, names, center in jobs:
            p = export_fbx(names, out(part), center_on=center)
            written[part] = p
            if p is None or not os.path.exists(p):
                raise RuntimeError("FBX export failed for " + part)
    finally:
        for h, was in hid:
            h.hide_set(was)
        for o in [o for o in vl.objects if o.select_get()]:      # restore the caller's selection / active object
            o.select_set(False)
        for o in prev_sel:
            try:
                o.select_set(True)
            except Exception:
                pass
        vl.objects.active = prev_active

    def P(name):
        o = bpy.data.objects.get(name)
        return [round(c, 5) for c in o.location] if o is not None else None

    body = bpy.data.objects[car + '_Body']
    vs = [v.co for v in body.data.vertices]
    wheels = {}
    for k in ('FL', 'FR', 'RL', 'RR'):
        w = bpy.data.objects["%s_Wheel_%s" % (car, k)]
        ws = [v.co for v in w.data.vertices]
        wheels[k] = dict(center=[round(c, 5) for c in w.location],
                         radius=round((max(v.z for v in ws) - min(v.z for v in ws)) / 2, 5),
                         width=round(max(v.y for v in ws) - min(v.y for v in ws), 5))
    sw = bpy.data.objects[car + '_SteeringWheel']
    axis = list(sw.get('rim_axis', [-1.0, 0.0, 0.0]))
    data = {
        "id": car, "display_name": display_name or root.get('display_name', car), "units": "m",
        "dimensions": {"length": round(float(root['length']), 4), "width": round(float(root['width']), 4),
                       "height": round(float(root['height']), 4),
                       "width_with_mirrors": round(max(v.y for v in vs) - min(v.y for v in vs), 4)},
        "wheelbase": round(float(root['wheelbase']), 4), "track_front": round(float(root['track_front']), 4),
        "track_rear": round(float(root['track_rear']), 4), "ride_height": round(float(root['ride_height']), 4),
        "wheels": wheels,
        "steering_wheel": {"center": [round(c, 5) for c in sw.location], "axis": [round(a, 5) for a in axis]},
        "cameras": {"hood": P(car + '_CAM_Hood'), "cockpit": P(car + '_CAM_Cockpit'), "bumper": P(car + '_CAM_Bumper')},
        "lights": {"head_l": P(car + '_LP_HeadL'), "head_r": P(car + '_LP_HeadR'), "tail_l": P(car + '_LP_TailL'),
                   "tail_r": P(car + '_LP_TailR'), "reverse": P(car + '_LP_Reverse')},
        "exhaust": [P(car + '_EXHAUST_L'), P(car + '_EXHAUST_R')],
        "exhaust_l": P(car + '_EXHAUST_L'), "exhaust_r": P(car + '_EXHAUST_R'),
        "material_slots": {}, "tri_counts": {}, "ucx": [h.name for h in ucx],
        "files": {k: os.path.basename(v) for k, v in written.items()},
    }
    for suf in PART_SUFFIXES:
        o = bpy.data.objects[car + '_' + suf]
        data['material_slots'][suf] = [m.name for m in o.data.materials if m]
        data['tri_counts'][suf] = tri_count(o.data)
    data['tri_counts']['UCX'] = sum(tri_count(h.data) for h in ucx)
    data['tri_counts']['total_visual'] = sum(v for k, v in data['tri_counts'].items() if k not in ('UCX', 'total_visual'))
    jp = os.path.join(out_dir, car + '.json')
    with open(jp, 'w', encoding='utf8') as fh:
        json.dump(data, fh, indent=2)
    written['json'] = jp
    res = {k: (v, os.path.getsize(v)) for k, v in written.items()}
    for k, (v, sz) in res.items():
        print("  %-14s %9d bytes  %s" % (k, sz, v))
    return res


# =====================================================================================================================
# 13. QA helpers
# =====================================================================================================================
def qa_studio(car_id, on=True, center=None, power=1.0):
    """Temporary 4-light studio around the car (objects named <car_id>_QA_*, removed again with on=False) so that
    look(shading='rendered') is lit: the shared scene world is black.  Never exported (not part of the asset)."""
    for o in [o for o in bpy.data.objects if o.name.startswith(car_id + "_QA_") and o.type == 'LIGHT']:
        d = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if d is not None and d.users == 0:
            bpy.data.lights.remove(d)
    if not on:
        return
    root = bpy.data.objects[car_id + "_ROOT"]
    col = bpy.data.collections.get(car_id) or bpy.context.scene.collection
    c = Vector(center) if center is not None else root.location + Vector((0, 0, 0.7))
    specs = [("key", (4.5, -3.5, 4.0), 900.0 * power, 5.0, (1.0, 0.96, 0.9)),
             ("fill", (-4.0, 3.5, 2.5), 350.0 * power, 6.0, (0.85, 0.92, 1.0)),
             ("rim", (-5.0, -4.0, 3.0), 500.0 * power, 4.0, (1.0, 1.0, 1.0)),
             ("top", (0.0, 0.0, 6.0), 500.0 * power, 6.0, (1.0, 1.0, 1.0)),
             ("front", (7.0, 0.5, 1.2), 450.0 * power, 5.0, (1.0, 1.0, 1.0))]
    for name, off, energy, size, colr in specs:
        ld = bpy.data.lights.new("%s_QA_%s" % (car_id, name), 'AREA')
        ld.energy, ld.size, ld.color = energy, size, colr
        lo = bpy.data.objects.new("%s_QA_%s" % (car_id, name), ld)
        col.objects.link(lo)
        lo.location = c + Vector(off)
        direction = c - lo.location
        lo.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()


# =====================================================================================================================
# 14. composite details (built from the surface tools; left-hand versions, mirror with mirrored_copy())
# =====================================================================================================================
def mark_shell_creases(shell, names, crease=1.0, bevel=1.0):
    """Subdivision-ready marking of the lofted shell: edges running along the named ring control points (e.g. 'belt_up',
    'edge', 'char_lo') get a crease and a bevel weight (float edge attributes crease_edge / bevel_weight_edge), so the shell
    can be fed to a Subdivision Surface or Bevel modifier without losing its character lines.  Call before the booleans."""
    bm = shell.bm
    lc = bm.edges.layers.float.get('crease_edge') or bm.edges.layers.float.new('crease_edge')
    lb = bm.edges.layers.float.get('bevel_weight_edge') or bm.edges.layers.float.new('bevel_weight_edge')
    cols = set()
    for n in names:
        for side in (1, -1):
            cols.add(shell_col(shell, n, side) % shell.N)
    count = 0
    for r in range(len(shell.rows) - 1):
        for j in cols:
            v0, v1 = shell.rows[r][j], shell.rows[r + 1][j]
            e = bm.edges.get((v0, v1))
            if e is not None:
                e[lc] = crease
                e[lb] = bevel
                count += 1
    return count


def build_headlight(surf, center, ray, axes, length=0.225, height=0.048, rot=0.17, depth=0.06, scale=0.97, n=48, rings=7,
                    floor_mat='M_TrimBlack', projector=True, drl=True, indicator=True, lens_mat='M_Headlight'):
    """Headlight unit on the (uncut) surface: slim superellipse lens that follows the body, black housing pocket, round
    projector with chrome ring, white DRL bar, amber indicator line.  Returns (cutter_bm, [insert_bms]) for the LEFT side;
    subtract the cutter in the body boolean and append the inserts afterwards (mirror both for the right side).
    ray: parallel direction or ('radial', C); axes=(U,V) tangent-plane axes (U along the lamp length)."""
    U, V = Vector(axes[0]), Vector(axes[1])
    outline = [(u * math.cos(rot) - v * math.sin(rot), u * math.sin(rot) + v * math.cos(rot))
               for (u, v) in outline_superellipse(length, height, 3.2, n)]
    cut, lens = lamp_unit(surf, center, ray, outline, depth=depth, lens_inset=0.004, axes=(U, V), taper=0.86, lens_scale=scale,
                          lens_mat=lens_mat, floor_mat=floor_mat, rings=rings)
    if cut is None:
        return None, []
    c = Vector(center)
    ins = [lens]
    if projector:
        k = length * 0.333
        ins += [surface_patch(surf, outline_ellipse(0.032, 0.032, 22), c + U * k + V * 0.004, ray, offset=depth * 0.67, rings=2, mat='M_Chrome', axes=(U, V)),
                surface_patch(surf, outline_ellipse(0.020, 0.020, 18), c + U * k + V * 0.004, ray, offset=depth * 0.69, rings=2, mat='M_TrimBlack', axes=(U, V)),
                surface_patch(surf, outline_ellipse(0.026, 0.020, 18), c - U * k * 1.13 - V * 0.005, ray, offset=depth * 0.63, rings=2, mat='M_Chrome', axes=(U, V)),
                surface_patch(surf, outline_ellipse(0.015, 0.011, 14), c - U * k * 1.13 - V * 0.005, ray, offset=depth * 0.66, rings=2, mat='M_TrimBlack', axes=(U, V))]
    if indicator:
        ins.append(surface_patch(surf, outline_rrect(length * 0.44, 0.006, 0.003, 2), c - U * 0.005 - V * height * 0.75, ray,
                                 offset=depth * 0.5, rings=2, mat='M_Indicator', axes=(U, V)))
    if drl:
        pts = [c + U * u + V * (height * 0.56 + 0.006 * (u / length)) for u in [-length * 0.76 + length * 0.152 * i for i in range(11)]]
        ins.append(surface_sweep(surf, pts, ray, [(-0.0035, -depth * 0.43), (0.0035, -depth * 0.43), (0.0035, -depth * 0.32),
                                                  (-0.0035, -depth * 0.32)], mat='M_Reverse'))
    return cut, [b for b in ins if b is not None]


def _blade_raw(L, H):
    """Raw (uncentred) vertices of the blade headlight and their area centroid."""
    raw = [(L, -0.45 * H), (0.98 * L, 0.62 * H), (0.10 * L, 1.0 * H), (-L, 1.14 * H), (-1.03 * L, 0.60 * H), (-0.55 * L, -0.50 * H)]
    return raw, poly_centroid(raw)


def headlight_blade_outline(length=0.27, height=0.078, corner=0.011, n=3):
    """(rev 3) Angular 'blade' headlight outline (lamp-local u along the lamp, +u = inner end, v up): tall squared-off inner end,
    the top edge sweeps up to a pointed outer tip that climbs onto the fender, short lower edge.  Convex, centred on its area
    centroid, corners rounded with `corner` m.  Returns [(u, v), ...] counter-clockwise."""
    raw, (ca, cb) = _blade_raw(length, height)
    poly = [(p[0] - ca, p[1] - cb) for p in raw]
    return densify_outline(outline_rounded_poly(poly, [corner * 0.8, corner * 0.8, corner, corner * 0.5, corner * 0.7, corner], n), 0.016)


def build_headlight_blade(surf, center, ray, axes, length=0.27, height=0.078, depth=0.06, scale=0.97, rings=7, corner=0.011,
                          floor_mat='M_TrimGrey', lens_mat='M_Headlight', drl=True, indicator=True, lift=0.16, taper=1.0):
    """(rev 3) Modern angular headlight on the (uncut) surface - same contract as build_headlight (returns (cutter_bm,
    [insert_bms]) for the LEFT side).  A black bezel strip rims the pocket, the lens carries two projector eyes (big one at the
    inner end, small one at the outer end), a black 'eyelid' band along the sweeping top edge carries the white DRL light bar,
    and an amber indicator strip runs along the lower edge.  ray: parallel direction or ('radial', C); axes = (U, V) with +U
    pointing to the INNER end of the lamp."""
    U, V = Vector(axes[0]), Vector(axes[1])
    L, H = length, height
    outline = headlight_blade_outline(L, H, corner)
    cut, lens = lamp_unit(surf, center, ray, outline, depth=depth, lens_inset=0.004, axes=(U, V), taper=taper, lens_scale=scale,
                          lens_mat=lens_mat, floor_mat=floor_mat, rings=rings, lift=lift)   # big lift: the chord of the cutter top must clear a convex corner (taper=1: straight walls, so the opening equals the outline)
    if cut is None:
        return None, []
    c = Vector(center)
    ins = [lens]
    pts = [c + U * p[0] + V * p[1] for p in outline]
    bz = surface_sweep(surf, pts, ray, rib_profile(0.0105, 0.0022, 0.006, 0.001), closed=True, mat='M_TrimBlack')
    if bz is not None:
        ins.append(bz)
    # lamp-local (centred) coordinates of the sweeping top edge  T0 (outer tip) -> T1 (inner shoulder)
    raw, (ca, cb) = _blade_raw(L, H)
    T0 = (raw[3][0] - ca, raw[3][1] - cb)
    T1 = (raw[2][0] - ca, raw[2][1] - cb)
    sl = (T1[1] - T0[1]) / (T1[0] - T0[0])

    def top_v(u):
        return T1[1] + sl * (u - T1[0])
    # black eyelid band = the part of the outline above "top edge shifted down by 0.42 H"
    band = clip_poly(outline, -sl, 1.0, -(T1[1] - sl * T1[0]) + 0.42 * H)
    if len(band) >= 3:
        bc = poly_centroid(band)
        rel = [(p[0] - bc[0], p[1] - bc[1]) for p in band]
        eyelid = surface_patch(surf, rel, c + U * bc[0] + V * bc[1], ray, offset=0.0028, rings=2, mat='M_TrimBlack', axes=(U, V),
                               scale=0.985)
        if eyelid is not None:
            ins.append(eyelid)
    k = L * 0.50
    for (pu, pv, rc, rb) in ((+k, -0.16 * H, 0.040, 0.026), (-k * 0.66, 0.02 * H, 0.027, 0.017)):
        ins += [surface_patch(surf, outline_ellipse(rc, rc, 22), c + U * pu + V * pv, ray, offset=depth * 0.62, rings=2, mat='M_Rim', axes=(U, V)),
                surface_patch(surf, outline_ellipse(rb, rb, 18), c + U * pu + V * pv, ray, offset=depth * 0.66, rings=2, mat='M_TrimBlack', axes=(U, V))]
    if drl:
        n = 11
        pts = []
        for i in range(n):
            u = T0[0] * 0.90 + (T1[0] * 0.92 - T0[0] * 0.90) * i / (n - 1.0)
            pts.append(c + U * u + V * (top_v(u) - 0.50 * H))
        ins.append(surface_sweep(surf, pts, ray, [(-0.0035, -depth * 0.38), (0.0035, -depth * 0.38), (0.0035, -depth * 0.26),
                                                  (-0.0035, -depth * 0.26)], mat='M_Reverse'))
    if indicator:
        pts = [c + U * (-0.62 * L + 1.2 * L * i / 6.0) + V * (-0.40 * H) for i in range(7)]
        ins.append(surface_sweep(surf, pts, ray, [(-0.0032, -depth * 0.40), (0.0032, -depth * 0.40), (0.0032, -depth * 0.30),
                                                  (-0.0032, -depth * 0.30)], mat='M_Indicator'))
    return cut, [b for b in ins if b is not None]


def clip_poly(poly, a, b, c):
    """Clip a convex polygon [(x, y), ...] with the half plane a*x + b*y + c >= 0 (Sutherland-Hodgman)."""
    out = []
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        dp = a * p[0] + b * p[1] + c
        dq = a * q[0] + b * q[1] + c
        if dp >= 0:
            out.append(p)
        if (dp >= 0) != (dq >= 0):
            t = dp / (dp - dq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def poly_centroid(poly):
    """Area centroid of a simple polygon [(x, y), ...]."""
    a = cx = cy = 0.0
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        w = x0 * y1 - x1 * y0
        a += w
        cx += (x0 + x1) * w
        cy += (y0 + y1) * w
    if abs(a) < 1e-12:
        return (sum(p[0] for p in poly) / n, sum(p[1] for p in poly) / n)
    return (cx / (3.0 * a), cy / (3.0 * a))


def build_taillight(surf, center, ray, axes, length=0.195, height=0.075, rot=-0.12, depth=0.034, n=48, rings=7,
                    lens_mat='M_Taillight', reverse=True, indicator=True, light_bar=True, segmented=True, rib=0.0065,
                    bulge=0.003, lens_inset=0.0045, bezel=True):
    """Wrap-around tail light cluster.  Returns (cutter_bm, [insert_bms]) for the LEFT side (see build_headlight).
    segmented=True (default, "v2"): recessed housing (`depth` m deep, black walls, grey reflector floor) with a clean symmetric
    superellipse outline; the lens is split by thin black ribs into a large red brake/tail segment (top) and two lower
    windows - amber indicator (outer, +U) and white reverse (inner, -U); every lens segment is domed by `bulge`, sits
    `lens_inset` below the skin, and behind the red lens there are three emissive LED bars and a chrome separator, so that the
    cluster reads as a real lamp unit with depth, not a decal.  segmented=False keeps the old single flat lens."""
    U, V = Vector(axes[0]), Vector(axes[1])
    cr, sr = math.cos(rot), math.sin(rot)

    def Rot(p):
        return (p[0] * cr - p[1] * sr, p[0] * sr + p[1] * cr)
    outline = [Rot(p) for p in outline_superellipse(length, height, 3.2, n)]
    c = Vector(center)
    if not segmented:
        cut, lens = lamp_unit(surf, center, ray, outline, depth=depth, lens_inset=0.004, axes=(U, V), lens_mat=lens_mat,
                              housing_mat='M_TrimBlack', floor_mat='M_TrimBlack', taper=0.85, rings=rings)
        if cut is None:
            return None, []
        ins = [lens]
        if indicator:
            ins.append(surface_patch(surf, outline_rrect(0.10, 0.024, 0.01, 3), c + U * (length * 0.36) + V * (height * 0.6), ray,
                                     offset=0.0025, rings=2, mat='M_Indicator', axes=(U, V)))
        if reverse:
            ins.append(surface_patch(surf, outline_rrect(0.06, 0.024, 0.01, 3), c - U * (length * 0.51) - V * (height * 0.4), ray,
                                     offset=0.0025, rings=2, mat='M_Reverse', axes=(U, V)))
        return cut, [b for b in ins if b is not None]
    # ---- housing pocket: black walls, grey reflector floor -------------------------------------------------------------
    cut = pocket_cutter(surf, outline, center, ray, depth=depth, lift=0.03, taper=0.90, mat='M_TrimBlack', axes=(U, V))
    if cut is None:
        return None, []
    c0 = surf.hit(c, ray)
    for f in cut.faces:
        if (f.calc_center_median() - c0[0]).dot(c0[1]) < -depth * 0.85:
            f.material_index = mi('M_TrimGrey')
    ins = []
    if bezel:           # raised black bezel strip right on the cut edge: hides the ragged boolean edge, reads as the lens rim
        pts = [c + U * p[0] + V * p[1] for p in outline]
        bz = surface_sweep(surf, pts, ray, rib_profile(0.0115, 0.0024, 0.006, 0.0011), closed=True, mat='M_TrimBlack')
        if bz is not None:
            ins.append(bz)
    # ---- lens segments (lamp-local coordinates a along the lamp, b up; rotated into the (U, V) plane afterwards) ----------
    Lg, Hg = length - 0.0075, height - 0.0065
    lens_o = outline_superellipse(Lg, Hg, 3.2, n)
    b_s = -0.30 * Hg                         # split between the big top segment (~65 %) and the lower row
    a_s = -0.18 * Lg                         # inner (reverse) | outer (indicator)
    top = clip_poly(lens_o, 0.0, 1.0, -(b_s + rib / 2))
    low = clip_poly(lens_o, 0.0, -1.0, (b_s - rib / 2))
    segs = [(top, lens_mat)]
    if indicator:
        segs.append((clip_poly(low, 1.0, 0.0, -(a_s + rib / 2)), 'M_Indicator'))
    if reverse:
        segs.append((clip_poly(low, -1.0, 0.0, (a_s - rib / 2)), 'M_Reverse'))
    for poly, mat in segs:
        if len(poly) < 3:
            continue
        ca, cb = poly_centroid(poly)
        rel = [Rot((p[0] - ca, p[1] - cb)) for p in poly]
        cu, cv = Rot((ca, cb))
        ins.append(surface_patch(surf, rel, c + U * cu + V * cv, ray, offset=lens_inset, rings=3, mat=mat, axes=(U, V),
                                 bulge=bulge))
    # ---- behind the lens: three emissive LED bars + chrome separator (visible through the translucent lens) ---------------
    if light_bar:
        def lamp_line(b, a0, a1, m=9):
            return [c + U * Rot((a0 + (a1 - a0) * i / (m - 1.0), b))[0] + V * Rot((a0 + (a1 - a0) * i / (m - 1.0), b))[1]
                    for i in range(m)]

        def half_len(b):
            t = min(abs(b) / Hg, 0.999)
            return Lg * (1.0 - t ** 3.2) ** (1.0 / 3.2)
        b_top = Hg * 0.98
        for k in range(3):
            b = b_s + rib + (b_top - b_s - rib) * (0.20 + 0.30 * k)
            hl = half_len(b) * 0.86
            bar = surface_sweep(surf, lamp_line(b, -hl, hl), ray, [(-0.0042, -depth * 0.52), (0.0042, -depth * 0.52),
                                                                    (0.0042, -depth * 0.36), (-0.0042, -depth * 0.36)], mat=lens_mat)
            if bar is not None:
                ins.append(bar)
        hl = half_len(b_s) * 0.93
        sep = surface_sweep(surf, lamp_line(b_s, -hl, hl), ray, [(-0.0025, -depth * 0.55), (0.0025, -depth * 0.55),
                                                                  (0.0025, -depth * 0.40), (-0.0025, -depth * 0.40)], mat='M_Chrome')
        if sep is not None:
            ins.append(sep)
    return cut, [b for b in ins if b is not None]


def build_roof_spoiler(surf, x_lead, chord=0.17, half_span=0.60, thick=0.038, lip_h=0.026, mat='M_Paint2', plates=True,
                       brake_strip=True, n_y=25, n_s=10, plan_taper=0.34, brake_w=0.50):
    """Roof-edge spoiler for a hatchback: a wedge / aerofoil section whose leading edge is sunk into the roof at x = x_lead and
    follows the roof camber across the span (ray cast on the uncut `surf`), the trailing edge kicks up by `thick` and ends in
    a `lip_h` tall lip over the rear glass.  The plan view is rounded at the ends (`plan_taper`), end plates run down to the
    skin (rear glass / roof) so that nothing floats, and a thin M_Taillight third brake light is inset into the trailing lip.
    Returns bmesh (car space)."""
    bm = bmesh.new()
    rings = []
    for k in range(n_y):
        y = -half_span + 2.0 * half_span * k / (n_y - 1.0)
        yn = abs(y) / half_span
        h = surf.hit(Vector((x_lead, y, 0.0)), (0, 0, -1))
        if h is None:
            bm.free()
            return None
        z0 = h[0].z
        cy = chord * (1.0 - plan_taper * yn ** 4)
        th = thick * (1.0 - 0.18 * yn ** 4)
        ring = []
        for i in range(n_s + 1):                      # upper surface, LE -> TE
            s = i / float(n_s)
            top = 0.004 + (th - 0.004) * (1.0 - (1.0 - s) ** 2.0)
            ring.append(Vector((x_lead + 0.004 - s * cy, y, z0 + top)))
        for i in range(n_s, -1, -1):                  # lower surface, TE -> LE
            s = i / float(n_s)
            top = 0.004 + (th - 0.004) * (1.0 - (1.0 - s) ** 2.0)
            lip = (0.0045 + (lip_h - 0.0045) * math.sin(min(s * 1.25, 1.0) * math.pi / 2.0)) * (1.0 - 0.15 * yn ** 4)
            ring.append(Vector((x_lead + 0.004 - s * cy, y, z0 + max(top - lip, -0.003))))
        rings.append(ring)
    sp = ring_loft(rings, closed=True, caps=True, mat=mat)
    bm_append(bm, sp)
    sp.free()
    if plates:
        for sg in (-1, 1):
            y_in = sg * (half_span - 0.007)
            y_out = sg * half_span
            ring_top = rings[-1 if sg > 0 else 0][:n_s + 1]
            pts = []
            for q in ring_top[2:]:                    # top edge, LE-ish -> TE
                pts.append((q.x, q.z))
            xs_bot = [q.x for q in ring_top[2:]]
            bot = []
            for x in reversed(xs_bot):                # bottom edge: follows the skin below, TE -> LE
                hh = surf.hit(Vector((x, y_in, 0.0)), (0, 0, -1))
                zb_ = hh[0].z - 0.004 if hh is not None else pts[0][1] - 0.03
                bot.append((x, zb_))
            outline = pts + bot
            pl = prim_prism(outline, 0.0075, plane='XZ', center=(0, sg * (half_span - 0.0035), 0), mat=mat)
            bm_append(bm, pl)
            pl.free()
    if brake_strip:
        yc = 0.0
        z0 = surf.hit(Vector((x_lead, 0.0, 0.0)), (0, 0, -1))[0].z
        x_te = x_lead + 0.004 - chord
        z_mid = z0 + (0.004 + (thick - 0.004)) - lip_h * 0.52
        strip = prim_box((0.0035, brake_w, min(0.011, lip_h * 0.55)), (x_te - 0.0004, yc, z_mid), mat='M_Taillight', bevel=0.0025,
                         segments=1)
        bm_append(bm, strip)
        strip.free()
    return bm


def plate_recess(surf, center, ray, width=0.54, height=0.125, depth=0.02, sink=0.011, plate_w=0.52, plate_h=0.112):
    """Number-plate recess: pocket cutter + blank plate seated in it (aligned to the surface normal).
    Returns (cutter_bm, plate_bm) or (None, None)."""
    cut = pocket_cutter(surf, outline_rrect(width, height, 0.012, 3), Vector(center), ray, depth=depth, taper=1.0,
                        mat='M_TrimBlack', floor_follows=False)
    fm = anchor_frame(surf, center, ray, sink=sink)
    if cut is None or fm is None:
        return None, None
    plate = build_plate(plate_w, plate_h)
    bmesh.ops.transform(plate, matrix=fm, verts=plate.verts)
    return cut, plate


def door_handle(surf, x, z, ray, length=0.15, width=0.026, height=0.014, mat='M_TrimBlack'):
    """Door handle bar hugging the door skin (LEFT side ray, e.g. (0,-1,0)); mirror for the right door."""
    pts = poly_pts([(x - length / 2, z), (x, z + 0.004), (x + length / 2, z)], subdiv=3)
    return surface_sweep(surf, pts, ray, rib_profile(width, height, 0.008, 0.005), mat=mat)


def arch_moulding(surf, cx, cz, radius, ray, a0=12.0, a1=168.0, n=30, width=0.05, height=0.016, mat='M_TrimBlack'):
    """Black fender-flare strip following a wheel-arch lip (arc on the XZ plane, projected on the side surface)."""
    return surface_sweep(surf, arc_pts(cx, cz, radius, a0, a1, n=n), ray, rib_profile(width, height, 0.012, 0.005), mat=mat)


def build_splitter(surf, ray_front, z=0.215, y_max=0.66, step=0.06, out=0.028, inn=0.05, z_top=0.222, z_bot=0.196, mat='M_TrimBlack'):
    """Flat front splitter lip (left half, y >= 0; mirror it): follows the bumper's lower edge in plan view (ray hits at
    height z), `out` m in front of it and `inn` m behind it.  Returns bmesh or None."""
    pts = []
    for i in range(int(y_max / step) + 1):
        y = i * step
        h = surf.hit(Vector((0, y, z)), ray_front)
        if h is not None:
            pts.append((h[0].x, y))
    if len(pts) < 4:
        return None
    sgn = 1.0 if ray_front[0] < 0 else -1.0       # -X ray = nose (x grows forward); +X ray = tail
    ymax = max(y for (_, y) in pts) or 1.0
    # the lip protrudes fully at the centre and fades out flush with the bumper at its ends
    outer = [(x + sgn * out * (1.0 - 0.9 * (y / ymax) ** 3), y * 1.012) for (x, y) in pts]
    inner = [(x - sgn * inn * (1.0 - 0.6 * (y / ymax) ** 3), y * 0.99) for (x, y) in pts]
    sb = bmesh.new()
    top_o = [sb.verts.new((x, y, z_top)) for (x, y) in outer]
    top_i = [sb.verts.new((x, y, z_top)) for (x, y) in inner]
    bot_o = [sb.verts.new((x, y, z_bot)) for (x, y) in outer]
    bot_i = [sb.verts.new((x, y, z_bot)) for (x, y) in inner]
    n = len(outer)
    for i in range(n - 1):
        for quad in ((top_i[i], top_o[i], top_o[i + 1], top_i[i + 1]), (bot_i[i], bot_i[i + 1], bot_o[i + 1], bot_o[i]),
                     (top_o[i], bot_o[i], bot_o[i + 1], top_o[i + 1]), (top_i[i], top_i[i + 1], bot_i[i + 1], bot_i[i])):
            sb.faces.new(quad)
    for end in (0, n - 1):
        sb.faces.new((top_i[end], top_o[end], bot_o[end], bot_i[end]))
    recalc(sb)
    return _set_mat(sb, mat)


def build_diffuser(surf, center, ray, width=0.92, height=0.088, fins=5, fin_h=0.07, depth=0.07, mat='M_TrimBlack'):
    """Rear (or front) diffuser/valance insert: black pocket with vertical fins.  Returns (cutter_bm, [fin_bms])."""
    cut = pocket_cutter(surf, outline_rrect(width, height, 0.03, 4), Vector(center), ray, depth=depth, taper=1.0, mat=mat,
                        floor_follows=False)
    if cut is None:
        return None, []
    ins = []
    c = Vector(center)
    for i in range(fins):
        y = (i - (fins - 1) / 2.0) * (width * 0.205)
        fm = anchor_frame(surf, (c.x, c.y + y, c.z), ray, sink=depth * 0.64)
        if fm is None:
            continue
        fin = prim_box((0.06, 0.008, fin_h), (0, 0, 0), mat=mat, bevel=0.002, segments=1)
        bmesh.ops.transform(fin, matrix=fm, verts=fin.verts)
        ins.append(fin)
    return cut, ins


def build_lip_spoiler(outline_xz, span=1.10, droop=0.010, fins=None, mat='M_Paint2'):
    """Tailgate/roof lip spoiler: side-profile outline [(x,z),...] extruded over `span` with a slight droop at the ends and
    optional end fins (fin outline [(x,z),...]).  Returns bmesh."""
    sp = prim_prism(outline_xz, span, plane='XZ', mat=mat)
    for v in sp.verts:
        f = min(abs(v.co.y) / (span / 2), 1.0)
        v.co.z -= droop * f * f
    if fins:
        for sdy in (1, -1):
            ef = prim_prism(fins, 0.012, plane='XZ', center=(0, sdy * (span / 2 + 0.005), -droop * 0.8), mat=mat)
            bm_append(sp, ef)
            ef.free()
    return sp


uv_unwrap_body = uv_unwrap       # alias used by the docs ("uv_unwrap_body(obj)")


# @@END@@
