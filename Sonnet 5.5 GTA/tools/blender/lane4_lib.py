"""lane4_lib.py - helpers for the Halcyon Bay human (characters/human.glb). exec AFTER gta_lib.py.
All names are prefixed c4_/C4_/T_ to avoid clashing with other agents sharing the Blender globals."""
import math, bpy, bmesh
from mathutils import Vector, Matrix

C4_PFX = "human__"
C4_COLL = "GTA_GODOT/Characters"
C4_X = Vector((1, 0, 0)); C4_Y = Vector((0, 1, 0)); C4_Z = Vector((0, 0, 1))
(T_TORSO, T_NECK, T_HEAD, T_ARM_R, T_ARM_L, T_HAND_R, T_HAND_L, T_LEG_R, T_LEG_L, T_SHOE_R, T_SHOE_L) = range(1, 12)

# ----- skeleton (ARCHITECTURE s12, R side; L mirrored) -----
C4_BONE_TABLE = [
    ("Hips", None, (0, 0, 0.95), (0, 0, 1.02)),
    ("Spine", "Hips", (0, 0, 1.02), (0, 0, 1.18)),
    ("Chest", "Spine", (0, 0, 1.18), (0, 0, 1.40)),
    ("Neck", "Chest", (0, 0, 1.40), (0, 0, 1.52)),
    ("Head", "Neck", (0, 0, 1.52), (0, 0, 1.80)),
    ("Shoulder", "Chest", (0.03, 0, 1.40), (0.17, 0, 1.42)),
    ("UpperArm", "Shoulder", (0.19, 0, 1.40), (0.30, 0, 1.12)),
    ("LowerArm", "UpperArm", (0.30, 0, 1.12), (0.40, 0, 0.87)),
    ("Hand", "LowerArm", (0.40, 0, 0.87), (0.44, 0, 0.76)),
    ("UpperLeg", "Hips", (0.09, 0, 0.92), (0.10, 0, 0.50)),
    ("LowerLeg", "UpperLeg", (0.10, 0, 0.50), (0.10, 0, 0.09)),
    ("Foot", "LowerLeg", (0.10, 0, 0.09), (0.10, 0.14, 0.03)),
    ("Toe", "Foot", (0.10, 0.14, 0.03), (0.10, 0.24, 0.02)),
]
C4_SIDE = {"Shoulder", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot", "Toe"}


def c4_bone_list():
    out = []
    for n, par, h, t in C4_BONE_TABLE:
        if n not in C4_SIDE:
            out.append(dict(name=n, parent=par, head=h, tail=t))
    for suf, sx in (("_R", 1), ("_L", -1)):
        for n, par, h, t in C4_BONE_TABLE:
            if n in C4_SIDE:
                out.append(dict(name=n + suf, parent=(par + suf if par in C4_SIDE else par),
                                head=(h[0] * sx, h[1], h[2]), tail=(t[0] * sx, t[1], t[2])))
    return out


def c4_rig():
    return bpy.data.objects.get(C4_PFX + "Armature")


def c4_root():
    return bpy.data.objects.get(C4_PFX + "root")


# ----- mesh builder with per-vertex part tags (used for skin weights) -----
class CB(MB):
    def __init__(self, name):
        MB.__init__(self, name)
        self.layer = self.bm.verts.layers.int.new("part")
        self.cur = 0

    def v(self, p):
        vt = self.bm.verts.new(Vector(p))
        vt[self.layer] = self.cur
        return vt

    def loft2(self, rings, seg_mats, cap0=None, cap1=None, wrap=False, closed=True):
        """rings: list of point lists. seg_mats: str or list (per segment) whose entries are str or list (per edge).
        closed=False -> open strips (no edge from the last point back to the first, no caps)."""
        V = [[self.v(p) for p in r] for r in rings]
        n = len(rings[0])
        nseg = len(V) - 1 + (1 if wrap else 0)
        for k in range(nseg):
            k2 = (k + 1) % len(V)
            m = seg_mats[k] if isinstance(seg_mats, (list, tuple)) else seg_mats
            for i in range(n if closed else n - 1):
                j = (i + 1) % n
                mm = m[i] if isinstance(m, (list, tuple)) else m
                self.face([V[k][i], V[k][j], V[k2][j], V[k2][i]], mm)
        if closed and cap0:
            self.face(list(reversed(V[0])), cap0)
        if closed and cap1:
            self.face(V[-1], cap1)
        return V


def c4_ring(c, u, v, rx, ry, n=8, ang0=0.0, p=2.0):
    out = []
    c = Vector(c)
    for i in range(n):
        a = ang0 + 2 * math.pi * i / n
        ca, sa = math.cos(a), math.sin(a)
        if p != 2.0:
            ca = math.copysign(abs(ca) ** (2.0 / p), ca)
            sa = math.copysign(abs(sa) ** (2.0 / p), sa)
        out.append(c + u * (rx * ca) + v * (ry * sa))
    return out


def c4_lerp(a, b, t):
    return a + (b - a) * t


def c4_interp_rings(rings, z):
    """rings: list of tuples (z, rx, ry, cy, ...) ascending z -> interpolated (rx, ry, cy) at z (clamped)."""
    if z <= rings[0][0]:
        r = rings[0]
        return r[1], r[2], r[3]
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        if a[0] <= z <= b[0]:
            t = (z - a[0]) / max(1e-9, b[0] - a[0])
            return c4_lerp(a[1], b[1], t), c4_lerp(a[2], b[2], t), c4_lerp(a[3], b[3], t)
    r = rings[-1]
    return r[1], r[2], r[3]


def c4_front_y(rings, x, z, n=12, ang0=0.0, p=2.2):
    """y of the head surface in front (+Y side) at lateral x and height z."""
    rx, ry, cy = c4_interp_rings(rings, z)
    pts = []
    for i in range(n):
        a = ang0 + 2 * math.pi * i / n
        ca, sa = math.cos(a), math.sin(a)
        ca = math.copysign(abs(ca) ** (2.0 / p), ca)
        sa = math.copysign(abs(sa) ** (2.0 / p), sa)
        pts.append((rx * ca, cy + ry * sa))
    best = None
    for i in range(n):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
        if abs(x1 - x0) < 1e-9:
            continue
        if (x0 - x) * (x1 - x) <= 0:
            t = (x - x0) / (x1 - x0)
            y = y0 + (y1 - y0) * t
            if y > cy and (best is None or y > best):
                best = y
    return best if best is not None else cy + ry


# ----- skin weights by part tag -----
def c4_sm(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def c4_chain_w(u, joints, bones):
    """joints: ascending [(u_j, half_width)], bones: len(joints)+1 names -> {bone: weight} (smooth joint blends)."""
    w = {}
    rem = 1.0
    for k, (uj, h) in enumerate(joints):
        f = c4_sm((u - (uj - h)) / (2 * h))
        w[bones[k]] = w.get(bones[k], 0.0) + rem * (1 - f)
        rem *= f
    w[bones[-1]] = w.get(bones[-1], 0.0) + rem
    return w


C4_ARM_PATH = [Vector((0.19, 0, 1.40)), Vector((0.30, 0, 1.12)), Vector((0.40, 0, 0.87)), Vector((0.44, 0, 0.76))]


def c4_arm_u(p, sx):
    """arc-length parameter of p along the shoulder->elbow->wrist polyline (negative above the shoulder)."""
    pts = [Vector((q.x * sx, q.y, q.z)) for q in C4_ARM_PATH]
    cum = [0.0]
    for i in range(len(pts) - 1):
        cum.append(cum[-1] + (pts[i + 1] - pts[i]).length)
    best = None
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        d = b - a
        L = d.length
        t = (p - a).dot(d) / L
        tmin = -0.2 if i == 0 else 0.0
        tc = max(tmin, min(L, t))
        dist = (p - (a + d / L * tc)).length
        if best is None or dist < best[0]:
            best = (dist, cum[i] + tc)
    return best[1], cum


def c4_weights(part, p):
    x, y, z = p.x, p.y, p.z
    if part == T_TORSO:
        return c4_chain_w(z, [(1.02, 0.07), (1.18, 0.08), (1.45, 0.05)], ["Hips", "Spine", "Chest", "Neck"])
    if part == T_NECK:
        return c4_chain_w(z, [(1.40, 0.03), (1.52, 0.04)], ["Chest", "Neck", "Head"])
    if part == T_HEAD:
        return {"Head": 1.0}
    if part in (T_ARM_R, T_ARM_L):
        s = "_R" if part == T_ARM_R else "_L"
        sx = 1 if part == T_ARM_R else -1
        u, cum = c4_arm_u(p, sx)
        return c4_chain_w(u, [(0.0, 0.06), (cum[1], 0.075), (cum[2], 0.04)],
                          ["Shoulder" + s, "UpperArm" + s, "LowerArm" + s, "Hand" + s])
    if part in (T_HAND_R, T_HAND_L):
        s = "_R" if part == T_HAND_R else "_L"
        sx = 1 if part == T_HAND_R else -1
        W = Vector((0.40 * sx, 0, 0.87)); T = Vector((0.44 * sx, 0, 0.76))
        d = (T - W).normalized()
        sp = (p - W).dot(d)
        return c4_chain_w(sp, [(0.0, 0.03)], ["LowerArm" + s, "Hand" + s])
    if part in (T_LEG_R, T_LEG_L):
        s = "_R" if part == T_LEG_R else "_L"
        return c4_chain_w(-z, [(-0.93, 0.06), (-0.50, 0.07), (-0.09, 0.04)], ["Hips", "UpperLeg" + s, "LowerLeg" + s, "Foot" + s])
    if part in (T_SHOE_R, T_SHOE_L):
        s = "_R" if part == T_SHOE_R else "_L"
        return c4_chain_w(y, [(0.15, 0.035)], ["Foot" + s, "Toe" + s])
    return {"Hips": 1.0}


def c4_attach(obj, arm):
    """Armature modifier + parent to the armature with identity parent-inverse (everything is in character space)."""
    if not any(m.type == "ARMATURE" for m in obj.modifiers):
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
    obj.parent = arm
    obj.matrix_parent_inverse = Matrix.Identity(4)


def c4_apply_weights(obj, arm, wfn=None):
    """Weight every vertex by its 'part' tag with c4_weights (or a custom wfn(part, p)). Removes the tag attribute."""
    wfn = wfn or c4_weights
    me = obj.data
    attr = me.attributes.get("part")
    bone_names = {b.name for b in arm.data.bones}
    groups = {}
    for v in me.vertices:
        part = attr.data[v.index].value if attr is not None else 0
        w = wfn(part, v.co)
        items = sorted([(n, x) for n, x in w.items() if x > 0.01 and n in bone_names], key=lambda t: -t[1])[:4]
        tot = sum(x for _, x in items) or 1.0
        for n, x in items:
            if n not in groups:
                groups[n] = obj.vertex_groups.new(name=n)
            groups[n].add([v.index], x / tot, "REPLACE")
    if attr is not None:
        me.attributes.remove(attr)
    c4_attach(obj, arm)


def c4_rigid(obj, arm, bone):
    me = obj.data
    attr = me.attributes.get("part")
    if attr is not None:
        me.attributes.remove(attr)
    vg = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
    vg.add([v.index for v in me.vertices], 1.0, "REPLACE")
    c4_attach(obj, arm)


def c4_finish(b, name, arm=None, rigid=None, wfn=None):
    """Create object human__<name> in GTA_GODOT/Characters, remove an old one first, skin it. rigid='Head' -> 100% one bone."""
    clear_asset(C4_PFX + name)
    obj = b.finish(coll(C4_COLL), name=C4_PFX + name)
    arm = arm or c4_rig()
    if rigid:
        c4_rigid(obj, arm, rigid)
    else:
        c4_apply_weights(obj, arm, wfn)
    return obj


def c4_tris(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def c4_check_normals(obj):
    """Fraction of faces whose normal points away from the mesh centre."""
    me = obj.data
    c = sum((v.co for v in me.vertices), Vector()) / max(1, len(me.vertices))
    out = sum(1 for p in me.polygons if (p.center - c).dot(p.normal) > 0)
    return out / max(1, len(me.polygons))


def c4_islands(obj):
    """Per connected island: (face_count, signed_volume). Negative volume on a closed shell = inside-out faces."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    seen = set()
    out = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        faces = []
        while stack:
            cur = stack.pop()
            faces.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        vol = 0.0
        open_edges = 0
        for fc in faces:
            vs = [v.co for v in fc.verts]
            for i in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[i].cross(vs[i + 1])) / 6.0
            open_edges += sum(1 for e in fc.edges if len(e.link_faces) < 2)
        out.append((len(faces), round(vol, 6), open_edges))
    bm.free()
    return out
