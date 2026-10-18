"""
animals_lib.py - helpers for Blender lane 12 (ANIMALS, collection GTA_GODOT/Animals). Load AFTER gta_lib.py:

    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\animals_lib.py", encoding="utf8").read(), globals())

Conventions (see docs/api/blender_animals.md):
  * object names "<id>__<Node>", root empty "<id>__root" in workshop(12, slot, 8). Origin = ground centre (fish: body centre), forward +Y, Z up.
  * NO skeleton. Articulated parts are separate meshes whose OBJECT ORIGIN is the joint (hip, shoulder, neck base, tail root, wing shoulder,
    fin base). Parts can be nested (Head is a child of Neck for deer, Ears/Jaw/Antlers are children of Head) so rotating a parent carries them.
  * Materials: per-species datablocks "Role__species" (e.g. "AnimalFur__deer") so every species keeps its own colours inside the master .blend.
    export_animal() renames them to the contract name (AnimalFur, AnimalBelly, AnimalDark, Antler, Hoof, Beak, Eye, Accent ...) for the export only.
"""
import bpy
import bmesh
import math
import random
from mathutils import Vector, Matrix

LANE = 12
STEP = 8.0
ANIM = "GTA_GODOT/Animals"
MSEP = "__"

ROLES = ("AnimalFur", "AnimalBelly", "AnimalDark", "Antler", "Hoof", "Beak", "Accent", "AnimalShell", "AnimalFin")


def species_mats(sp, **cols):
    """cols: role -> '#hex' or (hex, rough). Creates Blender materials '<Role>__<sp>'. Returns role->datablock name."""
    mat("Eye", color="#0c0a09", rough=0.25)
    out = {"Eye": "Eye"}
    for role, spec in cols.items():
        if isinstance(spec, (tuple, list)):
            col, rough = spec[0], spec[1]
        else:
            col, rough = spec, 0.88
        name = role + MSEP + sp
        mat(name, color=col, rough=rough)
        out[role] = name
    return out


# ---------------------------------------------------------------------------------------------------------------
# Animal asset wrapper with nested pivots
# ---------------------------------------------------------------------------------------------------------------
class Animal:
    def __init__(self, aid, slot, sp=None, sc=1.0, **cols):
        self.aid = aid
        self.sc = sc
        clear_asset(aid + "__")
        self.coll = coll(ANIM)
        self.root = empty(aid + "__root", loc=workshop(LANE, slot, STEP), collection=self.coll, size=0.3)
        self.piv = {None: Vector((0, 0, 0))}
        self.obj = {}
        self.M = species_mats(sp or aid, **cols) if cols else {"Eye": "Eye"}

    def m(self, role):
        return self.M[role]

    def name(self, node):
        return self.aid + "__" + node

    def part(self, b, node, pivot=(0, 0, 0), parent=None, flat=True, smooth_angle_deg=None):
        """b is built in ROOT space (metres, relative to the root empty). The object origin is moved to `pivot` (root space); if parent is
        given the pivot becomes relative to the parent's pivot (rest pose has no rotation, so a subtraction is exact)."""
        p = Vector(pivot) * self.sc
        if self.sc != 1.0:
            bmesh.ops.scale(b.bm, vec=Vector((self.sc, self.sc, self.sc)), verts=b.bm.verts)
        b.translate(-p)
        par = self.obj[parent] if parent else self.root
        pp = self.piv[parent] if parent else Vector((0, 0, 0))
        o = b.finish(self.coll, name=self.name(node), parent=par, loc=tuple(p - pp), flat=flat, smooth_angle_deg=smooth_angle_deg)
        self.piv[node] = p
        self.obj[node] = o
        return o

    def anchor(self, node, loc=(0, 0, 0), parent=None):
        p = Vector(loc) * self.sc
        par = self.obj[parent] if parent else self.root
        pp = self.piv[parent] if parent else Vector((0, 0, 0))
        o = empty(self.name(node), loc=tuple(p - pp), parent=par, collection=self.coll)
        self.piv[node] = p
        self.obj[node] = o
        return o

    def clamp_ground(self):
        """Flatten foot soles: any vertex below the ground plane (root z < 0) is lifted to z = 0 (leg/foot rings tilt with the limb)."""
        for node, o in self.obj.items():
            if o.type != "MESH":
                continue
            pz = self.piv[node].z
            ch = False
            for v in o.data.vertices:
                if v.co.z + pz < 0.0:
                    v.co.z = -pz
                    ch = True
            if ch:
                o.data.update()

    def report(self, budget=None, ground=True):
        if ground:
            self.clamp_ground()
        info = stats(self.root, verbose=False)
        nm = {}
        for o in descendants(self.root):
            if o.type == "MESH":
                nm[o.name.split(MSEP, 1)[1]] = (len(o.data.polygons), nonmanifold_report(o))
        flag = ""
        if budget and info["tris"] > budget:
            flag = "  !!! OVER BUDGET %d" % budget
        print(self.aid, "tris", info["tris"], "size", info["size"], "min", info["min"], "max", info["max"], flag)
        print("  parts (polys, nonmanifold):", nm)
        return info


def export_animal(aid, rel=None):
    """Export <aid>__root to animals/<aid>.glb; material datablocks 'Role__species' are exported as 'Role' (restored afterwards)."""
    root = bpy.data.objects[aid + "__root"]
    used = []
    for o in descendants(root):
        if o.type == "MESH":
            for m in o.data.materials:
                if m is not None and m not in used:
                    used.append(m)
    ren = []
    stash = []
    for m in used:
        if MSEP in m.name:
            new = m.name.split(MSEP, 1)[0]
            other = bpy.data.materials.get(new)
            if other is not None and other not in used and all(other is not s[0] for s in stash):
                stash.append((other, other.name))
            ren.append((m, m.name, new))
    try:
        for i, (o, old) in enumerate(stash):
            o.name = "_stash%d_%s" % (i, old)
        for m, old, new in ren:
            m.name = new
        path = export_glb(root, rel or ("animals/" + aid))
    finally:
        for m, old, new in ren:
            try:
                m.name = old
            except Exception:
                pass
        for o, old in stash:
            try:
                o.name = old
            except Exception:
                pass
    return path


# ---------------------------------------------------------------------------------------------------------------
# Geometry primitives (all take an MB instance b)
# ---------------------------------------------------------------------------------------------------------------
def ring_xz(y, hw, zt, zb, n=8, cx=0.0, rot=None):
    """Cross-section ring in the XZ plane at height y: half width hw, top z=zt, bottom z=zb. rot=None -> flat top/sides (chamfered box)."""
    rot = math.pi / n if rot is None else rot
    k = 1.0 / math.cos(math.pi / n) if rot != 0.0 else 1.0
    zc = (zt + zb) / 2.0
    hu, hd = zt - zc, zc - zb
    pts = []
    for i in range(n):
        a = rot + 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        pts.append(Vector((cx + hw * k * c, y, zc + (hu if s > 0 else hd) * k * s)))
    return pts


def skin(b, rings, mats="AnimalFur", cap0=None, cap1=None):
    """Quads between consecutive rings (same point count). mats: name | list per segment | callable(k, i)."""
    V = [[b.v(p) for p in r] for r in rings]
    n = len(rings[0])
    for k in range(len(V) - 1):
        for i in range(n):
            j = (i + 1) % n
            if callable(mats):
                m = mats(k, i)
            elif isinstance(mats, (list, tuple)):
                m = mats[min(k, len(mats) - 1)]
            else:
                m = mats
            b.face([V[k][i], V[k][j], V[k + 1][j], V[k + 1][i]], m)
    if cap0:
        b.face(list(reversed(V[0])), cap0)
    if cap1:
        b.face(V[-1], cap1)
    return V


def belly_fn(fur, belly, belly_idx=(4, 5, 6), dark=None, dark_idx=(), dark_k=None, first=None, last=None):
    """mats callable for an 8-sided flat-top ring: belly colour on the lower facets, optional dark facets (dark_idx, only in segments dark_k),
    optional first-segment colour (rump patch) / last=(k, mat)."""
    def f(k, i):
        if first is not None and k == 0:
            return first
        if last is not None and k == last[0]:
            return last[1]
        if dark is not None and i in dark_idx and (dark_k is None or k in dark_k):
            return dark
        return belly if i in belly_idx else fur
    return f


def limb(b, pts, radii, sides=5, mats="AnimalFur", sx=1.0, cap0=True, cap1=True, rot=0.0, hint=(1, 0, 0)):
    """Tapered faceted tube along a polyline. radii[k] = r | (rx, ry): rx along the side axis (X*sx), ry along the in-plane perpendicular.
    pts are given for the +X side; sx=-1 mirrors them. mats: name | list per segment | callable(k, i)."""
    P = [Vector((p[0] * sx, p[1], p[2])) for p in pts]
    n = len(P)
    rings = []
    for k in range(n):
        if k == 0:
            t = P[1] - P[0]
        elif k == n - 1:
            t = P[-1] - P[-2]
        else:
            t = (P[k + 1] - P[k]).normalized() + (P[k] - P[k - 1]).normalized()
        t = t.normalized()
        u = Vector((hint[0] * sx, hint[1], hint[2]))
        if abs(t.dot(u.normalized())) > 0.93:
            u = Vector((0, 1, 0))
        v = t.cross(u).normalized()
        u = v.cross(t).normalized()
        r = radii[k]
        rx, ry = (r, r) if not isinstance(r, (tuple, list)) else (r[0], r[1])
        ring = []
        for i in range(sides):
            a = rot + 2 * math.pi * i / sides
            ring.append(P[k] + u * (rx * math.cos(a)) + v * (ry * math.sin(a)))
        rings.append(ring)
    m0 = mats if isinstance(mats, str) else (mats[0] if isinstance(mats, (list, tuple)) else mats(0, 0))
    m1 = mats if isinstance(mats, str) else (mats[-1] if isinstance(mats, (list, tuple)) else mats(n - 2, 0))
    r0 = radii[0] if not isinstance(radii[0], (tuple, list)) else max(radii[0])
    r1 = radii[-1] if not isinstance(radii[-1], (tuple, list)) else max(radii[-1])
    return skin(b, rings, mats, cap0=m0 if (cap0 and r0 > 1e-5) else None, cap1=m1 if (cap1 and r1 > 1e-5) else None)


def ico(b, center, radii, mat="AnimalFur", subdiv=1, rot_z=0.0, jitter=0.0, seed=1, cut_z=None, mat_top=None, top_thresh=0.5, mat_bot=None, bot_thresh=-0.5):
    """Faceted ellipsoid (icosphere subdiv 1 = 20 tris, 2 = 80 tris). cut_z: clamp z below this (flat base)."""
    res = bmesh.ops.create_icosphere(b.bm, subdivisions=subdiv, radius=1.0)
    rnd = random.Random(seed)
    cs, sn = math.cos(rot_z), math.sin(rot_z)
    cx, cy, cz = center
    for v in res["verts"]:
        p = v.co.copy()
        k = 1.0 + rnd.uniform(-jitter, jitter)
        x, y, z = p.x * radii[0] * k, p.y * radii[1] * k, p.z * radii[2] * k
        if cut_z is not None and cz + z < cut_z:
            z = cut_z - cz
        x, y = x * cs - y * sn, x * sn + y * cs
        v.co = Vector((cx + x, cy + y, cz + z))
    faces = set()
    for v in res["verts"]:
        for f in v.link_faces:
            faces.add(f)
    mi = b._mi(mat)
    for f in faces:
        f.smooth = False
        f.normal_update()
        f.material_index = mi
        if mat_top and f.normal.z > top_thresh:
            f.material_index = b._mi(mat_top)
        elif mat_bot and f.normal.z < bot_thresh:
            f.material_index = b._mi(mat_bot)
    return res["verts"]


def eye(b, c, outward, r=0.012, mat="Eye", depth=0.7):
    """Closed little square pyramid (6 tris): base sunk inside the head, apex pokes out - a small dark facet."""
    c = Vector(c)
    n = Vector(outward).normalized()
    u = n.cross(Vector((0, 0, 1)))
    if u.length < 0.2:
        u = n.cross(Vector((0, 1, 0)))
    u = u.normalized()
    v = n.cross(u).normalized()
    pts = [c + (u + v) * r, c + (-u + v) * r, c + (-u - v) * r, c + (u - v) * r]
    ap = c + n * (r * depth)
    V = [b.v(p) for p in pts]
    A = b.v(ap)
    for i in range(4):
        b.face([V[i], V[(i + 1) % 4], A], mat)
    b.face(list(reversed(V)), mat)


def horn_cone(b, base, tip, r, sides=4, mat="Antler", sx=1.0, cap=True):
    """Simple cone from base to tip (thorn/tusk/tine)."""
    limb(b, [base, tip], [r, 0.0], sides=sides, mats=mat, sx=sx, cap0=cap, cap1=False)


def wedge(b, c, size, taper_top=(1.0, 1.0), mat="AnimalFur", top_shift=(0, 0)):
    """Box-like block centred at c=(x,y,z) with size (sx, sy, sz); the top face is scaled by taper_top (x, y)."""
    return b.block((c[0], c[1]), c[2] - size[2] / 2, c[2] + size[2] / 2, (size[0], size[1]),
                   (size[0] * taper_top[0], size[1] * taper_top[1]), mat, top_shift)


def dirv(pitch_deg, yaw_deg=0.0):
    """Unit direction: pitch measured from +Y (forward) upwards, yaw about Z (positive = to the left, -X)."""
    p, y = math.radians(pitch_deg), math.radians(yaw_deg)
    return Vector((-math.sin(y) * math.cos(p), math.cos(y) * math.cos(p), math.sin(p)))


def along(origin, d, s, up=0.0):
    o = Vector(origin)
    return o + d * s + Vector((0, 0, up))


def mirror_pts(pts):
    return [(-p[0], p[1], p[2]) for p in pts]


def plane_poly(b, pts_xy_or_xz, plane, d0, d1, mat="AnimalFur"):
    """Extrude a CCW 2D polygon: plane 'xz' (depth along Y), 'yz' (depth along X), 'xy' (depth along Z)."""
    def P(q, d):
        if plane == "xy":
            return (q[0], q[1], d)
        if plane == "xz":
            return (q[0], d, q[1])
        return (d, q[0], q[1])
    A = [b.v(P(q, d0)) for q in pts_xy_or_xz]
    B = [b.v(P(q, d1)) for q in pts_xy_or_xz]
    n = len(pts_xy_or_xz)
    b.face(list(reversed(A)), mat)
    b.face(B, mat)
    for i in range(n):
        j = (i + 1) % n
        b.face([A[i], A[j], B[j], B[i]], mat)


def shell_rotate(b, start_index, axis, deg, pivot):
    """Rotate bmesh verts created since index start_index (len(b.bm.verts) before building)."""
    b.bm.verts.ensure_lookup_table()
    M = Matrix.Rotation(math.radians(deg), 4, axis)
    pv = Vector(pivot)
    for i in range(start_index, len(b.bm.verts)):
        v = b.bm.verts[i]
        v.co = pv + M @ (v.co - pv)


def nverts(b):
    return len(b.bm.verts)


def make_legs(A, fore, fore_r, hind, hind_r, mats_f, mats_h=None, sides=5, parent=None, names=("Leg_FR", "Leg_FL", "Leg_BR", "Leg_BL")):
    """Four legs from +X-side polylines (pivot = first point, inside the body). _R = +X side (animal's right), _L = -X side."""
    mats_h = mats_h or mats_f
    for nm, pts, rr, mm, sx in ((names[0], fore, fore_r, mats_f, 1), (names[1], fore, fore_r, mats_f, -1),
                                (names[2], hind, hind_r, mats_h, 1), (names[3], hind, hind_r, mats_h, -1)):
        b = MB(A.aid + "_" + nm)
        limb(b, pts, rr, sides=sides, mats=mm, sx=sx)
        A.part(b, nm, pivot=(pts[0][0] * sx, pts[0][1], pts[0][2]), parent=parent)
