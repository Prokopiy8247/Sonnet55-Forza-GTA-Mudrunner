r"""
lane11_common.py - helpers for Blender lane 11: modular vehicle customisation parts (collection GTA_GODOT/Vehicles/Parts).
Load AFTER gta_lib.py (same exec namespace):
    exec(open(r"...\tools\blender\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"...\tools\blender\lane11_common.py", encoding="utf8").read(), globals())
Every top-level name is prefixed l11_ / L11 because the Blender exec namespace is shared with other agents.

PART FRAME (Blender, metres): +Y forward (front of the car), +Z up, +X right, centred on X. The part ORIGIN is the part's mount point
(see lane11_catalog.py: L11_MOUNT gives the recommended transform on the sedan). A `Mount` empty sits at the origin.
Object naming: <partid>__Body (+ <partid>__Mount, <partid>__root); export_glb() strips the prefix.
Meshes are built from closed primitives (weld=0); open decal faces keep their explicit winding (L11B.finish only recalculates
closed shells).
"""
import math
import bmesh
import bpy
from mathutils import Vector

L11_LANE = 11
L11_COLL = "GTA_GODOT/Vehicles/Parts"
L11_SPACE = 4.0
L11_MATS_USED = ["Paint", "Paint2", "Trim", "Chrome", "Metal", "MetalDark", "Glass", "LightHead", "LightTail", "NeonCyan", "Neon",
                 "LampGlow", "Tire", "Rim"]


def l11_mats():
    ensure_std_mats(L11_MATS_USED)


# ----------------------------------------------------------------------------------------------------------------
# normals: recalc only closed islands, keep explicit winding on open decals
# ----------------------------------------------------------------------------------------------------------------
def l11_fix(bm):
    bm.faces.index_update()
    seen = set()
    for f in list(bm.faces):
        if f.index in seen:
            continue
        stack = [f]
        island = []
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            island.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        closed = all(len(e.link_faces) == 2 for fc in island for e in fc.edges)
        if closed:
            # signed volume decides (Blender's recalc misjudges thin chamfered slabs): flip the island only when it is inside-out
            vol = 0.0
            for fc in island:
                vs = [v.co for v in fc.verts]
                for k in range(1, len(vs) - 1):
                    vol += vs[0].dot(vs[k].cross(vs[k + 1])) / 6.0
            if vol < 0:
                for fc in island:
                    fc.normal_flip()


def l11_newell(p):
    n = Vector((0, 0, 0))
    for i in range(len(p)):
        a = p[i]
        c = p[(i + 1) % len(p)]
        n.x += (a.y - c.y) * (a.z + c.z)
        n.y += (a.z - c.z) * (a.x + c.x)
        n.z += (a.x - c.x) * (a.y + c.y)
    return n


class L11B(MB):
    """MB + range boxes, oriented open faces and a finish that only fixes the normals of closed shells."""

    def fo(self, pts, mat, out):
        """polygon whose winding is flipped (if needed) so its normal points along `out`."""
        p = [Vector(q) for q in pts]
        if l11_newell(p).dot(Vector(out)) < 0:
            p.reverse()
        return self.face([self.v(q) for q in p], mat)

    def bx(self, x0, x1, y0, y1, z0, z1, mat="Paint"):
        """box from ranges."""
        return self.block(((x0 + x1) / 2, (y0 + y1) / 2), min(z0, z1), max(z0, z1), (abs(x1 - x0), abs(y1 - y0)), None, mat)

    def tbx(self, x, y, z, mat="Paint", top_x=None, top_y=None):
        """tapered box: bottom ranges x,y at z0; top ranges top_x/top_y at z1 (default: same)."""
        cx, cy = (x[0] + x[1]) / 2, (y[0] + y[1]) / 2
        bs = (abs(x[1] - x[0]), abs(y[1] - y[0]))
        tx = top_x if top_x is not None else x
        ty = top_y if top_y is not None else y
        ts = (abs(tx[1] - tx[0]), abs(ty[1] - ty[0]))
        sh = ((tx[0] + tx[1]) / 2 - cx, (ty[0] + ty[1]) / 2 - cy)
        return self.block((cx, cy), z[0], z[1], bs, ts, mat, top_shift=sh)

    def finish(self, collection=None, name=None, loc=(0, 0, 0), flat=True, smooth_angle_deg=None, uv=None, parent=None, weld=0.0):
        bm = self.bm
        if weld:
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=weld)
        l11_fix(bm)
        me = bpy.data.meshes.new((name or self.name) + "_mesh")
        bm.to_mesh(me)
        bm.free()
        for mn in self.mats:
            me.materials.append(bpy.data.materials[mn])
        if smooth_angle_deg is not None:
            try:
                me.shade_smooth()
                me.set_sharp_from_angle(angle=math.radians(smooth_angle_deg))
            except Exception:
                for p in me.polygons:
                    p.use_smooth = True
        else:
            try:
                me.shade_flat()
            except Exception:
                for p in me.polygons:
                    p.use_smooth = False
        obj = bpy.data.objects.new(name or self.name, me)
        obj.location = Vector(loc)
        c = collection or bpy.context.scene.collection
        if obj.name not in c.objects:
            c.objects.link(obj)
        if parent is not None:
            obj.parent = parent
        return obj


# ----------------------------------------------------------------------------------------------------------------
# geometry helpers
# ----------------------------------------------------------------------------------------------------------------
def l11_inset(pts, d):
    """Inset a CCW polygon [(a,b)...] by distance d (miter)."""
    n = len(pts)
    out = []
    for i in range(n):
        p0 = Vector(pts[i - 1])
        p1 = Vector(pts[i])
        p2 = Vector(pts[(i + 1) % n])
        e1 = p1 - p0
        e2 = p2 - p1
        if e1.length < 1e-9 or e2.length < 1e-9:
            out.append(tuple(p1))
            continue
        e1.normalize()
        e2.normalize()
        n1 = Vector((-e1.y, e1.x))
        n2 = Vector((-e2.y, e2.x))
        k = 1.0 + n1.dot(n2)
        m = n1 + n2
        if k < 0.35:
            m = n1
            k = 1.0
        q = p1 + m * (d / k)
        out.append((q.x, q.y))
    return out


def l11_slab(b, prof, x0, x1, mat="Paint", bev=0.0):
    """(y,z) profile (CCW seen from +X) extruded between x0..x1; bev>0 chamfers both end caps."""
    xc, hw = (x0 + x1) / 2, abs(x1 - x0) / 2
    if bev <= 0:
        return b.profile_extrude(prof, hw, mat, xc)
    inner = l11_inset(prof, bev)
    n = len(prof)
    rings = [(xc - hw, inner), (xc - hw + bev, prof), (xc + hw - bev, prof), (xc + hw, inner)]
    V = [[b.v((x, p[0], p[1])) for p in poly] for x, poly in rings]
    b.face(list(reversed(V[0])), mat)
    b.face(V[3], mat)
    for k in range(3):
        for i in range(n):
            j = (i + 1) % n
            b.face([V[k][i], V[k][j], V[k + 1][j], V[k + 1][i]], mat)
    return V


def l11_sweep(b, prof, stations, f, mat="Paint", caps=True):
    """Loft a (y,z) profile through `stations`; f(s, y, z) -> (x, y, z). Closed shell with end caps."""
    rings = [[tuple(f(s, y, z)) for (y, z) in prof] for s in stations]
    return b.loft(rings, mat, True, caps, caps)


def l11_rot(pts, deg, c=(0.0, 0.0)):
    """Rotate 2D (y,z) points by deg (positive = counter-clockwise seen from +X = nose up) about centre c."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    out = []
    for (y, z) in pts:
        dy, dz = y - c[0], z - c[1]
        out.append((c[0] + dy * ca - dz * sa, c[1] + dy * sa + dz * ca))
    return out


def l11_bar(b, p0, p1, w, t, mat="Metal", up=(0, 0, 1), w1=None, t1=None, caps=True):
    """Rectangular bar between two points: w across (perpendicular to up), t thick; optional taper to w1/t1 at p1."""
    a, c = Vector(p0), Vector(p1)
    d = c - a
    if d.length < 1e-6:
        return None
    z = d.normalized()
    u = Vector(up)
    if abs(u.dot(z)) > 0.98:
        u = Vector((1, 0, 0))
    x = u.cross(z).normalized()
    y = z.cross(x)
    w1 = w if w1 is None else w1
    t1 = t if t1 is None else t1

    def ring(p, ww, tt):
        return [p + x * (ww / 2) + y * (tt / 2), p - x * (ww / 2) + y * (tt / 2), p - x * (ww / 2) - y * (tt / 2), p + x * (ww / 2) - y * (tt / 2)]
    return b.loft([ring(a, w, t), ring(c, w1, t1)], mat, True, caps, caps)


def l11_ring_strip(b, path, z_top, w, t, mat="NeonCyan"):
    """Closed strip following a closed XY polyline (CCW from above): width w (horizontal), thickness t, top face at z_top."""
    n = len(path)
    P = [Vector((p[0], p[1])) for p in path]
    OT, IT, OB, IB = [], [], [], []
    for i in range(n):
        a, c, e = P[i - 1], P[i], P[(i + 1) % n]
        t1 = (c - a).normalized()
        t2 = (e - c).normalized()
        n1 = Vector((t1.y, -t1.x))
        n2 = Vector((t2.y, -t2.x))
        k = 1.0 + n1.dot(n2)
        mm = (n1 + n2) / max(k, 0.5)
        o = c + mm * (w / 2)
        q = c - mm * (w / 2)
        OT.append(b.v((o.x, o.y, z_top)))
        IT.append(b.v((q.x, q.y, z_top)))
        OB.append(b.v((o.x, o.y, z_top - t)))
        IB.append(b.v((q.x, q.y, z_top - t)))
    for i in range(n):
        j = (i + 1) % n
        b.face([OT[i], OT[j], IT[j], IT[i]], mat)
        b.face([OB[i], IB[i], IB[j], OB[j]], mat)
        b.face([OB[i], OB[j], OT[j], OT[i]], mat)
        b.face([IB[i], IT[i], IT[j], IB[j]], mat)


def l11_rev(b, st, axis="X", c=(0.0, 0.0), seg=10, mat="Metal", rot=0.0, caps=(True, True)):
    """Solid of revolution. axis X: st=[(x, r)...] about the line (y,z)=c ; axis Y: st=[(y, r)...] about (x,z)=c ; axis Z: st=[(z, r)...] about (x,y)=c."""
    rings = []
    r0 = math.radians(rot)
    for (s, r) in st:
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg + r0
            ca, sa = math.cos(a) * r, math.sin(a) * r
            if axis == "X":
                ring.append((s, c[0] + ca, c[1] + sa))
            elif axis == "Y":
                ring.append((c[0] + ca, s, c[1] + sa))
            else:
                ring.append((c[0] + ca, c[1] + sa, s))
        rings.append(ring)
    return b.loft(rings, mat, True, caps[0], caps[1])


def l11_ball(b, center, r, mat="Metal", seg=6):
    """Low-poly ball (closed): stack of rings with tiny polar caps."""
    st = []
    for k in range(5):
        a = math.pi * (k + 0.0) / 4.0
        st.append((center[2] - r * math.cos(a), max(r * math.sin(a), 0.0008)))
    return l11_rev(b, st, "Z", (center[0], center[1]), seg, mat)


def l11_tube_cut(b, cx, cz, y0, y1, r0, r1, seg, mat, cut_deg=0.0, rot=0.0):
    """Tube along Y from y0 (rear/outlet end) to y1 (front). The y0 end can be cut at an angle (cut_deg, sloped top-back)."""
    rings = []
    r_ = math.radians(rot)
    tn = math.tan(math.radians(cut_deg))
    for (y, r, cutk) in ((y0, r0, 1.0), (y1, r1, 0.0)):
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg + r_
            ca, sa = math.cos(a) * r, math.sin(a) * r
            dy = sa * tn * cutk / max(r, 1e-6) * r      # = sin(a)*r*tan(cut): top of the outlet set forward, bottom reaches further back
            ring.append((cx + ca, y + dy, cz + sa))
        rings.append(ring)
    return b.loft(rings, mat, True, True, True)


# ----------------------------------------------------------------------------------------------------------------
# part context
# ----------------------------------------------------------------------------------------------------------------
class L11Part:
    def __init__(self, pid, index, budget=400):
        self.pid = pid
        self.pre = pid + SEP
        self.budget = budget
        clear_asset(self.pre)
        l11_mats()
        self.col = coll(L11_COLL)
        loc = workshop(L11_LANE, index, L11_SPACE)
        self.root = empty(self.pre + "root", tuple(loc), collection=self.col, display="ARROWS", size=0.15)
        self.mount = empty(self.pre + "Mount", (0, 0, 0), parent=self.root, collection=self.col, size=0.06)
        self.nodes = {}

    def mb(self):
        return L11B(self.pre + "mb")

    def add(self, b, node="Body", smooth=None, loc=(0, 0, 0)):
        o = b.finish(self.col, self.pre + node, loc=loc, parent=self.root, smooth_angle_deg=smooth)
        self.nodes[node] = o
        return o

    def mark(self, node, loc, rot=(0, 0, 0)):
        return empty(self.pre + node, tuple(loc), tuple(rot), parent=self.root, collection=self.col, size=0.04)

    def report(self):
        info = stats(self.root, verbose=False)
        bad = 0
        for o in self.nodes.values():
            bad += l11_neg_islands(o)
        flag = "" if info["tris"] <= self.budget else "  **OVER BUDGET %d**" % self.budget
        print("%-22s tris %4d  size %s  min %s  max %s  mats %s%s%s" % (
            self.pid, info["tris"], info["size"], info["min"], info["max"], info["materials"], flag,
            ("  **INVERTED ISLANDS %d**" % bad) if bad else ""))
        return info

    def export(self):
        return export_glb(self.root, "vehicle_parts/" + self.pid)


def l11_neg_islands(obj):
    """number of closed islands with negative signed volume (= inside-out)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.index_update()
    seen = set()
    neg = 0
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        island = []
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            island.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        if not all(len(e.link_faces) == 2 for fc in island for e in fc.edges):
            continue
        vol = 0.0
        for fc in island:
            vs = [v.co for v in fc.verts]
            for k in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[k].cross(vs[k + 1])) / 6.0
        if vol < -1e-9:
            neg += 1
    bm.free()
    return neg
