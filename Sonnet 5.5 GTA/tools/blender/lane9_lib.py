"""
lane9_lib.py - helpers for Blender lane 9 (StreetProps + Interiors). Load AFTER gta_lib.py:

    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\lane9_lib.py", encoding="utf8").read(), globals())

Conventions: asset id = lowercase, objects "<id>__<Node>", root "<id>__root" in workshop(9, 2*slot, 6) (12 m per slot).
Origin = base centre on the ground, front +Y. Meshes are built weld-free (every part its own closed shell, so
recalc_face_normals is always right); flat shaded unless smooth= is given.
"""
import bpy
import bmesh
import math
from mathutils import Vector, Matrix

LANE = 9

# --------------------------------------------------------------------------------------------------------------
# Lane-9 materials (custom names; STD names such as Metal / MetalDark / Concrete / Wood / Glass / Trim are reused)
# --------------------------------------------------------------------------------------------------------------
M9 = {
    "PoleGreen":   dict(color="#3b5a55", rough=0.55, metal=0.35),   # painted dark teal steel (lamps, bins, street poles)
    "PoleGrey":    dict(color="#7d8791", rough=0.5, metal=0.6),
    "PlateRed":     dict(color="#d93a3a", rough=0.45),
    "PlateWhite":   dict(color="#f2f0ea", rough=0.45),
    "PlateBlue":    dict(color="#2f6fd6", rough=0.45),
    "PlateYellow":  dict(color="#f2cf3a", rough=0.45),
    "PlateGreen":   dict(color="#2f7a52", rough=0.45),
    "HydrantRed":  dict(color="#d4412f", rough=0.5, metal=0.2),
    "ConeOrange":  dict(color="#ee6a1f", rough=0.6),
    "SafetyOrange": dict(color="#ee7a1f", rough=0.55),
    "PaintYellow": dict(color="#e8b92f", rough=0.55, metal=0.1),
    "WoodLight":   dict(color="#b98a5a", rough=0.85),
    "WoodDark":    dict(color="#6b4630", rough=0.9),
    "WoodPale":    dict(color="#d6bd92", rough=0.85),
    "BinGreen":    dict(color="#4a6b5c", rough=0.6, metal=0.25),
    "MailBlue":    dict(color="#2f5fa8", rough=0.45, metal=0.2),
    "BoothTeal":   dict(color="#2f9c95", rough=0.45, metal=0.25),
    "UtilGrey":    dict(color="#7d8a86", rough=0.6, metal=0.3),
    "DrumPaint":   dict(color="#5b7fa6", rough=0.5, metal=0.4),
    "DumpsterGreen": dict(color="#3f7a5c", rough=0.6, metal=0.3),
    "NeonAd":     dict(color="#dfe9ee", rough=0.4, emit="#a8c3d6", emit_strength=1.0),
    "NeonBillboard": dict(color="#eae6da", rough=0.5, emit="#8d9bb0", emit_strength=1.0),
    "TireRubber":  dict(color="#1b1c1f", rough=0.95),
    "RopeTan":     dict(color="#c9a86a", rough=0.95),
    "LifeOrange":  dict(color="#ee5a1f", rough=0.6),
    "ConcreteDark": dict(color="#9a958c", rough=0.95),
    "Reflector":   dict(color="#f2a21f", rough=0.3, emit="#f2a21f", emit_strength=0.4),
    "ReflectRed":  dict(color="#c82a2a", rough=0.3, emit="#c82a2a", emit_strength=0.3),
    # interiors
    "FabricTeal":  dict(color="#2f8c86", rough=0.95),
    "FabricCoral": dict(color="#e0715a", rough=0.95),
    "FabricGrey":  dict(color="#8a8f98", rough=0.95),
    "FabricSand":  dict(color="#d8c6a0", rough=0.95),
    "FabricNavy":  dict(color="#2f3f63", rough=0.95),
    "Leather":     dict(color="#5a3a2c", rough=0.6),
    "LeatherRed":  dict(color="#a8382f", rough=0.55),
    "Mirror":      dict(color="#b9d6e2", rough=0.04, metal=1.0),
    "NeonScreen":  dict(color="#0d1622", rough=0.1, emit="#3a7bd5", emit_strength=1.2),
    "Laminate":    dict(color="#e6e2d6", rough=0.5),
    "CounterTop":  dict(color="#3a3f47", rough=0.4),
    "Brass":       dict(color="#c9a14a", rough=0.35, metal=0.9),
    "PaintWhite":  dict(color="#e9e6dc", rough=0.5),
    "PaintRed":    dict(color="#c43a3a", rough=0.5, metal=0.2),
    "Pillow":      dict(color="#f0e4d0", rough=0.95),
    "Sheet":       dict(color="#e9eef2", rough=0.95),
    "Foam":        dict(color="#3a3f47", rough=0.95),
    "Mannequin":   dict(color="#d9d4c8", rough=0.5),
}
for _n, _s in M9.items():
    mat(_n, **_s)


# --------------------------------------------------------------------------------------------------------------
# Transform context + shape helpers (all take the MB builder `b` first)
# --------------------------------------------------------------------------------------------------------------
def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def RX(d):
    return Matrix.Rotation(math.radians(d), 4, "X")


def RY(d):
    return Matrix.Rotation(math.radians(d), 4, "Y")


def RZ(d):
    return Matrix.Rotation(math.radians(d), 4, "Z")


def about(pivot, R):
    """Rotation matrix R applied around a pivot point."""
    p = Vector(pivot)
    return T(*p) @ R @ T(*(-p))


class xf:
    """with xf(b, matrix): <build anything>  -> everything built inside is transformed by matrix (nestable)."""

    def __init__(self, b, M):
        self.b = b
        self.M = M

    def __enter__(self):
        self.n = len(self.b.bm.verts)
        return self

    def __exit__(self, *a):
        bm = self.b.bm
        bm.verts.ensure_lookup_table()
        vs = [bm.verts[i] for i in range(self.n, len(bm.verts))]
        bmesh.ops.transform(bm, matrix=self.M, verts=vs)


def bx(b, X, Y, Z, mat="Metal"):
    """Axis-aligned box from ranges: X=(x0,x1) Y=(y0,y1) Z=(z0,z1)."""
    return b.block(((X[0] + X[1]) / 2, (Y[0] + Y[1]) / 2), Z[0], Z[1], (abs(X[1] - X[0]), abs(Y[1] - Y[0])), None, mat)


def cbox(b, X, Y, Z, ch=0.03, mat="Metal"):
    """Box whose 4 vertical edges are chamfered by ch (octagon prism)."""
    x0, x1 = X
    y0, y1 = Y
    c = ch
    pts = [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]
    return b.prism(pts, Z[0], Z[1], mat)


def ngon(n, r, cx=0.0, cy=0.0, rot=0.0):
    return [(cx + r * math.cos(math.radians(rot) + 2 * math.pi * i / n), cy + r * math.sin(math.radians(rot) + 2 * math.pi * i / n)) for i in range(n)]


def ext(b, pts, plane, a0, a1, mat="Metal", caps=True):
    """Extrude a 2D polygon. plane 'xy' -> pts=(x,y), extruded z a0..a1;  'xz' -> pts=(x,z), extruded along y;  'yz' -> pts=(y,z), along x."""
    def P(p, a):
        if plane == "xy":
            return (p[0], p[1], a)
        if plane == "xz":
            return (p[0], a, p[1])
        return (a, p[0], p[1])
    A = [b.v(P(p, a0)) for p in pts]
    B = [b.v(P(p, a1)) for p in pts]
    n = len(pts)
    if caps:
        b.face(A, mat)
        b.face(list(reversed(B)), mat)
    for i in range(n):
        j = (i + 1) % n
        b.face([A[i], A[j], B[j], B[i]], mat)
    return A, B


def cylz(b, x, y, z0, z1, r, seg=8, mat="Metal", r1=None, caps=True, smooth=False, rot=0.0):
    """Vertical cylinder/frustum from z0 (radius r) to z1 (radius r1)."""
    if rot:
        with xf(b, about((x, y, 0), RZ(rot))):
            return b.cyl((x, y, (z0 + z1) / 2), r, z1 - z0, seg, mat, "Z", r_top=r1, caps=caps, smooth=smooth)
    return b.cyl((x, y, (z0 + z1) / 2), r, z1 - z0, seg, mat, "Z", r_top=r1, caps=caps, smooth=smooth)


def cyly(b, x, y0, y1, z, r, seg=8, mat="Metal", r1=None, caps=True):
    """Cylinder along Y from y0 (radius r) to y1 (radius r1) at (x, z)."""
    return b.beam((x, y0, z), (x, y1, z), r, r1, seg, mat, caps)


def cylx(b, x0, x1, y, z, r, seg=8, mat="Metal", r1=None, caps=True):
    return b.beam((x0, y, z), (x1, y, z), r, r1, seg, mat, caps)


def sweep(b, pts, r, seg=6, mat="Metal", r_end=None, caps=True, rot0=0.0):
    """Mitred tube along a polyline `pts` (bent pipes, lamp arms). Radius r -> r_end."""
    P = [Vector(p) for p in pts]
    n = len(P)
    tans = []
    for i in range(n):
        if i == 0:
            t = P[1] - P[0]
        elif i == n - 1:
            t = P[-1] - P[-2]
        else:
            t = (P[i] - P[i - 1]).normalized() + (P[i + 1] - P[i]).normalized()
        tans.append(t.normalized())
    ref = Vector((0, 0, 1)) if abs(tans[0].z) < 0.9 else Vector((1, 0, 0))
    x = ref.cross(tans[0]).normalized()
    y = tans[0].cross(x)
    prev = tans[0]
    rings = []
    for i in range(n):
        t = tans[i]
        if i > 0:
            q = prev.rotation_difference(t)
            x = q @ x
            y = q @ y
        prev = t
        bd = None
        s = 1.0
        if 0 < i < n - 1:
            a = (P[i] - P[i - 1]).normalized()
            c = (P[i + 1] - P[i]).normalized()
            bdv = c - a
            if bdv.length > 1e-6:
                bd = bdv.normalized()
                s = 1.0 / max(0.35, a.dot(t))
        rr = r if r_end is None else r + (r_end - r) * i / (n - 1)
        ring = []
        for k in range(seg):
            ang = 2 * math.pi * k / seg + rot0
            off = x * math.cos(ang) + y * math.sin(ang)
            if bd is not None:
                off = off + bd * (off.dot(bd) * (s - 1.0))
            ring.append(P[i] + off * rr)
        rings.append(ring)
    return b.loft(rings, mat, True, caps, caps)


def arc(c, r, a0, a1, n, plane="xz", extra=0.0):
    """Points on an arc (degrees a0->a1) around centre c in 'xz' (x right, z up, angle from +X) / 'yz' / 'xy' plane."""
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        u, v = math.cos(a) * r, math.sin(a) * r
        if plane == "xz":
            out.append((c[0] + u, c[1] + extra, c[2] + v))
        elif plane == "yz":
            out.append((c[0] + extra, c[1] + u, c[2] + v))
        else:
            out.append((c[0] + u, c[1] + v, c[2] + extra))
    return out


def torus(b, c, R, r, seg=12, tseg=4, mat="Metal", axis="Y", mats=None, rot=0.0):
    """Ring/torus around `axis` through c. mats: optional list cycled per outer segment (colour bands)."""
    rings = []
    for i in range(seg):
        th = 2 * math.pi * i / seg + math.radians(rot)
        ring = []
        for k in range(tseg):
            ph = 2 * math.pi * k / tseg + (math.pi / tseg if tseg % 2 == 0 and False else 0)
            rr = R + r * math.cos(ph)
            zz = r * math.sin(ph)
            ring.append((rr * math.cos(th), rr * math.sin(th), zz))
        rings.append(ring)
    V = [[b.v(_axis_pt(p, axis, c)) for p in ring] for ring in rings]
    for i in range(seg):
        j = (i + 1) % seg
        m = mats[i % len(mats)] if mats else mat
        for k in range(tseg):
            kk = (k + 1) % tseg
            b.face([V[i][k], V[j][k], V[j][kk], V[i][kk]], m)


def _axis_pt(p, axis, c):
    x, y, z = p
    if axis == "Z":
        q = (x, y, z)
    elif axis == "Y":      # ring plane = XZ, hole along Y
        q = (x, z, y)
    else:                  # X: ring plane = YZ
        q = (z, x, y)
    return (q[0] + c[0], q[1] + c[1], q[2] + c[2])


def wedge(b, X, Y, Z, mat="Metal", slope="front"):
    """Triangular wedge (ramp). slope='front' -> high at -Y (back), low at +Y; 'back' reverse; 'left'/'right' along X."""
    x0, x1 = X
    y0, y1 = Y
    z0, z1 = Z
    if slope in ("front", "back"):
        pts = [(y0, z0), (y1, z0), (y1, z1) if slope == "back" else (y0, z1)]
        if slope == "front":
            pts = [(y0, z0), (y1, z0), (y0, z1)]
        ext(b, pts, "yz", x0, x1, mat)
    else:
        pts = [(x0, z0), (x1, z0), (x1, z1) if slope == "left" else (x0, z1)]
        if slope == "right":
            pts = [(x0, z0), (x1, z0), (x0, z1)]
        ext(b, pts, "xz", y0, y1, mat)


def slab_tilt(b, X, Y, Z, rx=0.0, mat="Metal", pivot=None):
    """Box rotated about X (degrees) around pivot (default box centre)."""
    c = pivot or ((X[0] + X[1]) / 2, (Y[0] + Y[1]) / 2, (Z[0] + Z[1]) / 2)
    with xf(b, about(c, RX(rx))):
        bx(b, X, Y, Z, mat)


# --------------------------------------------------------------------------------------------------------------
# Asset container
# --------------------------------------------------------------------------------------------------------------
class A9:
    def __init__(self, aid, root, c):
        self.id = aid
        self.root = root
        self.c = c
        self.parts = {}

    def mb(self, node="Body"):
        return MB(self.id + SEP + node)

    def fin(self, b, node="Body", smooth=None, uv=None, weld=0.0):
        o = b.finish(self.c, name=self.id + SEP + node, parent=self.root, smooth_angle_deg=smooth, uv=uv, weld=weld)
        self.parts[node] = o
        return o

    def mark(self, node, loc, rot=(0, 0, 0)):
        return empty(self.id + SEP + node, loc, rot, parent=self.root, collection=self.c)

    def done(self):
        return stats(self.root)


# Anchor empties exported as plain Node3D children (use points / seats / weapon slots). id -> [(name, (x,y,z), (rx,ry,rz) deg)]
MARKS = {
    "traffic_light": [("HeadMain", (4.2, 0.0, 5.08), (0, 0, 0)), ("HeadPole", (0.0, 0.3, 2.78), (0, 0, 0))],
    "bench": [("SeatPoint", (0.0, 0.05, 0.5), (0, 0, 0))],
    "bus_stop": [("SeatPoint", (0.0, -0.38, 0.5), (0, 0, 0)), ("UsePoint", (0.0, 1.0, 0.0), (0, 0, 0))],
    "phone_booth": [("UsePoint", (0.0, 0.8, 0.0), (0, 0, 0))],
    "newspaper_box": [("UsePoint", (0.0, 0.7, 0.0), (0, 0, 0))],
    "mailbox": [("UsePoint", (0.0, 0.7, 0.0), (0, 0, 0))],
    "parking_meter": [("UsePoint", (0.0, 0.6, 0.0), (0, 0, 0))],
    "shop_counter": [("ClerkPoint", (0.0, -0.9, 0.0), (0, 0, 0)), ("CustomerPoint", (0.0, 0.9, 0.0), (0, 0, 0)), ("RegisterPoint", (0.9, 0.0, 1.04), (0, 0, 0))],
    "weapon_rack_wall": [("UsePoint", (0.0, 0.9, 0.0), (0, 0, 0)),
                         ("SlotLong1", (-0.62, 0.1, 1.92), (0, 0, -90)), ("SlotLong2", (0.58, 0.1, 1.92), (0, 0, -90)),
                         ("SlotLong3", (-0.62, 0.1, 1.52), (0, 0, -90)), ("SlotLong4", (0.6, 0.1, 1.52), (0, 0, -90)),
                         ("SlotPistol1", (-1.02, 0.08, 1.17), (0, 0, -90)), ("SlotPistol2", (-0.72, 0.08, 1.17), (0, 0, -90)),
                         ("SlotPistol3", (-0.42, 0.08, 1.17), (0, 0, -90)), ("SlotPistol4", (-0.12, 0.08, 1.17), (0, 0, -90)),
                         ("SlotSmg1", (0.40, 0.08, 1.12), (0, 0, -90)), ("SlotSmg2", (0.92, 0.08, 1.12), (0, 0, -90))],
    "gun_bench": [("UsePoint", (0.0, 0.8, 0.0), (0, 0, 0))],
    "clothing_rack": [("UsePoint", (0.0, 0.9, 0.0), (0, 0, 0))],
    "wardrobe": [("UsePoint", (0.0, 0.9, 0.0), (0, 0, 0))],
    "bed_double": [("SleepPoint", (0.0, 0.0, 0.62), (0, 0, 0)), ("GetUpPointL", (-1.3, 0.3, 0.0), (0, 0, 0)), ("GetUpPointR", (1.3, 0.3, 0.0), (0, 0, 0))],
    "sofa": [("SeatPointL", (-0.53, 0.05, 0.48), (0, 0, 0)), ("SeatPointC", (0.0, 0.05, 0.48), (0, 0, 0)), ("SeatPointR", (0.53, 0.05, 0.48), (0, 0, 0))],
    "chair": [("SeatPoint", (0.0, 0.02, 0.5), (0, 0, 0))],
    "kitchen_unit": [("UsePoint", (0.0, 0.9, 0.0), (0, 0, 0))],
    "barber_chair": [("SeatPoint", (0.0, 0.0, 0.66), (0, 0, 0)), ("UsePoint", (0.0, 1.0, 0.0), (0, 0, 0))],
    "mirror_wall": [("UsePoint", (0.0, 0.9, 0.0), (0, 0, 0))],
    "scuba_rack": [("UsePoint", (0.0, 0.9, 0.0), (0, 0, 0))],
    "repair_lift": [("CarPoint", (0.0, 0.0, 0.45), (0, 0, 0)), ("UsePoint", (1.2, 0.6, 0.0), (0, 0, 0))],
    "tool_chest": [("UsePoint", (0.0, 0.8, 0.0), (0, 0, 0))],
}


def new_asset(aid, slot, cat="StreetProps"):
    """Start (or rebuild) an asset: clears previous objects, creates the root empty in workshop slot `slot`
    plus the anchor empties listed in MARKS."""
    clear_asset(aid + SEP)
    c = coll("GTA_GODOT/" + cat)
    root = empty(aid + SEP + "root", workshop(LANE, 2 * slot, 6), parent=None, collection=c, display="ARROWS", size=0.4)
    a = A9(aid, root, c)
    for name, loc, rot in MARKS.get(aid, []):
        a.mark(name, loc, rot)
    return a


def ship(aid, rel_cat="props"):
    """stats + export one asset to res://gta/generated/models/<rel_cat>/<aid>.glb"""
    root = bpy.data.objects[aid + SEP + "root"]
    info = stats(root)
    export_glb(root, rel_cat + "/" + aid)
    return info


def uv_unit(obj, axes=("x", "z"), flip=False):
    """Give a flat-ish panel object 0..1 UVs across its bounding box in the given world/local axes (for swapped textures)."""
    me = obj.data
    idx = {"x": 0, "y": 1, "z": 2}
    a, bb = idx[axes[0]], idx[axes[1]]
    co = [v.co for v in me.vertices]
    mn = [min(c[i] for c in co) for i in range(3)]
    mx = [max(c[i] for c in co) for i in range(3)]
    layer = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co
            u = (p[a] - mn[a]) / max(1e-6, mx[a] - mn[a])
            v = (p[bb] - mn[bb]) / max(1e-6, mx[bb] - mn[bb])
            layer.data[li].uv = (1.0 - u if flip else u, v)


def clip_x(pts, xmin, xmax):
    """Clip a convex 2D polygon [(x,v),...] against xmin<=x<=xmax (Sutherland-Hodgman). Returns the clipped polygon."""
    def clip(poly, keep, inter):
        out = []
        for i in range(len(poly)):
            a, b = poly[i], poly[(i + 1) % len(poly)]
            ka, kb = keep(a), keep(b)
            if ka:
                out.append(a)
            if ka != kb:
                out.append(inter(a, b))
        return out

    def ix(xc):
        return lambda a, b: (xc, a[1] + (b[1] - a[1]) * (xc - a[0]) / (b[0] - a[0]))
    p = clip(list(pts), lambda q: q[0] >= xmin, ix(xmin))
    if p:
        p = clip(p, lambda q: q[0] <= xmax, ix(xmax))
    return p


def stripes_xz(b, x0, x1, z0, z1, y0, y1, w, period, slant, mat, phase=0.0):
    """Diagonal stripes on a rectangle in the XZ plane (extruded y0..y1): width w, spacing `period`, slant = x shift over the height."""
    x = x0 - slant + phase
    n = 0
    while x < x1 and n < 200:
        poly = [(x, z0), (x + w, z0), (x + w + slant, z1), (x + slant, z1)]
        c = clip_x(poly, x0, x1)
        if len(c) >= 3:
            ext(b, c, "xz", y0, y1, mat)
        x += period
        n += 1


def lathe(b, prof, c=(0.0, 0.0, 0.0), seg=12, mat="Metal", axis="Z", rot=0.0, mats=None, closed=True):
    """Revolve a profile [(r, h), ...] around `axis` (X|Y|Z) through c. closed=True: the profile is a closed loop (tyres, rings),
    verts are shared and wrap in both directions. mats: optional material list cycled per angular segment (colour bands)."""
    n = len(prof)
    V = []
    for i in range(seg):
        th = 2 * math.pi * i / seg + math.radians(rot)
        V.append([b.v(_axis_pt((r * math.cos(th), r * math.sin(th), h), axis, c)) for (r, h) in prof])
    for i in range(seg):
        j = (i + 1) % seg
        m = mats[i % len(mats)] if mats else mat
        for k in (range(n) if closed else range(n - 1)):
            kk = (k + 1) % n
            b.face([V[i][k], V[j][k], V[j][kk], V[i][kk]], m)
    return V
