"""
lane8_lib.py - helpers for lane 8 (hero landmarks & large structures, collection GTA_GODOT/Buildings).
Load AFTER gta_lib:   exec(open(r"...\\tools\\blender\\lane8_lib.py", encoding="utf8").read(), globals())

Winding rules used everywhere: every face is wound counter-clockwise seen from OUTSIDE and NO normal recalculation is done
(finish8), so inside-out faces would show up in check_obj() (closed islands) - keep the meshes un-welded (one island per primitive).
"""
import bpy, bmesh, math
from mathutils import Vector

L8_COLL = "GTA_GODOT/Buildings"
L8_LANE = 8
Z3 = Vector((0, 0, 1))

# lane specific plain colours (no Godot name swap): red/white lighthouse, crane paint, safety yellow
for _n, _kw in (("RedPaint", dict(color="#d93a3a", rough=0.75)), ("WhitePaint", dict(color="#f2f0ea", rough=0.8)),
                ("CranePaint", dict(color="#2f9c95", rough=0.55, metal=0.25)), ("YellowPaint", dict(color="#f2cf3a", rough=0.7))):
    std_mat(_n, **_kw)
ensure_std_mats()


# ------------------------------------------------------------------------------------------------ asset context
class A8:
    def __init__(self, aid, idx):
        self.aid = aid
        clear_asset(aid + "__")
        self.c = coll(L8_COLL)
        self.root = empty(aid + "__root", loc=workshop(L8_LANE, idx, 80), collection=self.c, size=1.0)

    def b(self, node):
        return MB(self.aid + "__" + node)

    def fin(self, b, node, loc=(0, 0, 0), parent=None, smooth=None, uv="box"):
        return finish8(b, self.c, self.aid + "__" + node, loc, parent or self.root, smooth, uv)

    def mark(self, node, loc, rot=(0, 0, 0), parent=None, size=0.6, display="ARROWS"):
        return empty(self.aid + "__" + node, loc=loc, rot_deg=rot, parent=parent or self.root, collection=self.c, display=display, size=size)

    def report(self):
        return report(self)


def finish8(b, collection, name, loc=(0, 0, 0), parent=None, smooth=None, uv="box"):
    bm = b.bm
    bm.normal_update()
    if uv == "box":
        uv_box(bm)
    me = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(me)
    bm.free()
    for mn in b.mats:
        me.materials.append(bpy.data.materials[mn])
    if smooth is not None:
        try:
            me.shade_smooth()
            me.set_sharp_from_angle(angle=math.radians(smooth))
        except Exception:
            pass
    else:
        try:
            me.shade_flat()
        except Exception:
            pass
    obj = bpy.data.objects.new(name, me)
    obj.location = Vector(loc)
    collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def check_obj(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    parent = list(range(len(bm.verts)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for f in bm.faces:
        vs = [v.index for v in f.verts]
        for v in vs[1:]:
            a, c = find(vs[0]), find(v)
            if a != c:
                parent[a] = c
    vol, opn = {}, {}
    for e in bm.edges:
        if len(e.link_faces) != 2:
            opn[find(e.verts[0].index)] = True
    for f in bm.faces:
        r = find(f.verts[0].index)
        vs = [v.co.copy() for v in f.verts]
        for i in range(1, len(vs) - 1):
            vol[r] = vol.get(r, 0.0) + vs[0].dot(vs[i].cross(vs[i + 1])) / 6.0
    neg = [r for r, v in vol.items() if v < -1e-4 and not opn.get(r)]
    out = dict(islands=len(vol), neg=len(neg), open=sum(1 for r in vol if opn.get(r)))
    bm.free()
    return out


def report(a):
    info = stats(a.root, verbose=False)
    bad = []
    for o in descendants(a.root):
        if o.type == "MESH":
            r = check_obj(o)
            if r["neg"]:
                bad.append((o.name, r))
    print("STATS", info["name"], "meshes", info["meshes"], "tris", info["tris"], "size", info["size"])
    print("MIN", info["min"], "MAX", info["max"])
    print("MATS", info["materials"])
    print("EMPTIES", info["empties"])
    print("INVERTED", bad)
    return info


# ------------------------------------------------------------------------------------------------ 2D polygons
def rect_pts(cx, cy, w, d, ch=0.0):
    hx, hy = w / 2.0, d / 2.0
    if ch <= 0:
        return [(cx - hx, cy - hy), (cx + hx, cy - hy), (cx + hx, cy + hy), (cx - hx, cy + hy)]
    c = ch
    return [(cx - hx + c, cy - hy), (cx + hx - c, cy - hy), (cx + hx, cy - hy + c), (cx + hx, cy + hy - c),
            (cx + hx - c, cy + hy), (cx - hx + c, cy + hy), (cx - hx, cy + hy - c), (cx - hx, cy - hy + c)]


def circ_pts(cx, cy, r, n, rot=0.0):
    return [(cx + r * math.cos(rot + 2 * math.pi * i / n), cy + r * math.sin(rot + 2 * math.pi * i / n)) for i in range(n)]


def inflate(pts, d):
    n = len(pts)
    out = []
    for i in range(n):
        p0 = Vector(pts[i - 1])
        p1 = Vector(pts[i])
        p2 = Vector(pts[(i + 1) % n])
        e1 = (p1 - p0).normalized()
        e2 = (p2 - p1).normalized()
        n1 = Vector((e1.y, -e1.x))
        n2 = Vector((e2.y, -e2.x))
        k = 1.0 + n1.dot(n2)
        q = p1 + (n1 + n2) * (d / max(k, 0.2))
        out.append((q.x, q.y))
    return out


# ------------------------------------------------------------------------------------------------ solids
def obox(b, c, ax, ay, az, sx, sy, sz, mat="Trim"):
    """Oriented box. (ax, ay, az) must be a right-handed orthonormal frame."""
    c = Vector(c)
    X = Vector(ax) * (sx / 2)
    Y = Vector(ay) * (sy / 2)
    Z = Vector(az) * (sz / 2)
    P = [c - X - Y - Z, c + X - Y - Z, c + X + Y - Z, c - X + Y - Z, c - X - Y + Z, c + X - Y + Z, c + X + Y + Z, c - X + Y + Z]
    V = [b.v(p) for p in P]
    for idx in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        b.face([V[i] for i in idx], mat)
    return V


def hexa(b, bot, top, mat="Trim"):
    """Arbitrary hexahedron from 4 bottom points (CCW from above) and 4 top points."""
    V = [b.v(p) for p in list(bot) + list(top)]
    for idx in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        b.face([V[i] for i in idx], mat)
    return V


def shaft(b, pts, z0, z1, wall, roof=None, cap_bottom=False):
    b.prism(pts, z0, z1, wall, cap_bottom=cap_bottom, cap_top=False)
    if roof:
        b.poly([(p[0], p[1], z1) for p in pts], roof)


def extrude_y(b, prof_xz, y0, y1, mat):
    """Extrude a profile given as (x, z) points, CCW as seen from -Y (standard x right / z up), along Y from y0 to y1."""
    n = len(prof_xz)
    F = [b.v((p[0], y0, p[1])) for p in prof_xz]
    B = [b.v((p[0], y1, p[1])) for p in prof_xz]
    b.face(F, mat)
    b.face(list(reversed(B)), mat)
    for i in range(n):
        j = (i + 1) % n
        b.face([F[i], B[i], B[j], F[j]], mat)


def extrude_x(b, prof_yz, x0, x1, mat):
    """Extrude a profile given as (y, z) points, CCW as seen from +X (y right / z up), along X from x0 to x1."""
    n = len(prof_yz)
    L = [b.v((x0, p[0], p[1])) for p in prof_yz]
    R = [b.v((x1, p[0], p[1])) for p in prof_yz]
    b.face(R, mat)
    b.face(list(reversed(L)), mat)
    for i in range(n):
        j = (i + 1) % n
        b.face([L[i], L[j], R[j], R[i]], mat)


def gable_prof(w0, w1, ze, zr):
    """(u, z) pentagon of a gable wall section between u=w0..w1, eave height ze, ridge zr (centred)."""
    um = (w0 + w1) / 2.0
    return [(w0, 0.0), (w1, 0.0), (w1, ze), (um, zr), (w0, ze)]


def roof_prof(w0, w1, ze, zr, oh=0.5, t=0.25):
    """Closed thick gable roof slab section (u, z), CCW. Underside follows the slope; overhang oh; vertical thickness t."""
    um = (w0 + w1) / 2.0
    m = (zr - ze) / (um - w0)
    zl = ze - m * oh
    return [(w0 - oh, zl), (um, zr), (w1 + oh, zl), (w1 + oh, zl + t), (um, zr + t), (w0 - oh, zl + t)]


def parapet(b, pts, z0, z1, t, mat):
    n = len(pts)
    inner = inflate(pts, -t)
    for i in range(n):
        j = (i + 1) % n
        o0, o1, i0, i1 = pts[i], pts[j], inner[i], inner[j]
        b.quad((o0[0], o0[1], z1), (o1[0], o1[1], z1), (i1[0], i1[1], z1), (i0[0], i0[1], z1), mat)
        b.quad((o0[0], o0[1], z0), (o1[0], o1[1], z0), (o1[0], o1[1], z1), (o0[0], o0[1], z1), mat)
        b.quad((i1[0], i1[1], z0), (i0[0], i0[1], z0), (i0[0], i0[1], z1), (i1[0], i1[1], z1), mat)


def glaze(b, pts, z0, z1, mat="Window", out=0.07, bay=None, gap=0.0, edge=0.5, skip=(), min_len=1.0):
    """Window quads floating `out` m in front of every polygon edge (CCW polygon). bay=None -> one panel per edge."""
    n = len(pts)
    for i in range(n):
        if i in skip:
            continue
        p0 = Vector(pts[i])
        p1 = Vector(pts[(i + 1) % n])
        e = p1 - p0
        L = e.length
        if L - 2 * edge < min_len:
            continue
        u = e / L
        nr = Vector((u.y, -u.x))
        a = p0 + u * edge
        use = L - 2 * edge
        if bay:
            k = max(1, int(round((use + gap) / (bay + gap))))
            w = (use - gap * (k - 1)) / k
        else:
            k, w = 1, use
        for j in range(k):
            s = a + u * (j * (w + gap)) + nr * out
            t = s + u * w
            b.quad((s.x, s.y, z0), (t.x, t.y, z0), (t.x, t.y, z1), (s.x, s.y, z1), mat)


def fin(b, base, u, nr, w, d, z0, z1, mat="Trim"):
    """Vertical rib standing on a wall: centre `base` (2D), tangent u, outward normal nr, w wide, d deep (4 visible faces)."""
    base, u, nr = Vector(base), Vector(u), Vector(nr)
    A = base - u * (w / 2)
    B = base + u * (w / 2)
    A2 = A + nr * d
    B2 = B + nr * d
    P = lambda v, z: (v.x, v.y, z)
    b.quad(P(A2, z0), P(B2, z0), P(B2, z1), P(A2, z1), mat)
    b.quad(P(A, z0), P(A2, z0), P(A2, z1), P(A, z1), mat)
    b.quad(P(B2, z0), P(B, z0), P(B, z1), P(B2, z1), mat)
    b.quad(P(A, z1), P(A2, z1), P(B2, z1), P(B, z1), mat)


def fins(b, pts, z0, z1, spacing, w=0.45, d=0.3, edge=1.2, skip=(), mat="Trim", min_len=2.5):
    n = len(pts)
    for i in range(n):
        if i in skip:
            continue
        p0 = Vector(pts[i])
        p1 = Vector(pts[(i + 1) % n])
        e = p1 - p0
        L = e.length
        if L < min_len + 2 * edge:
            continue
        u = e / L
        nr = Vector((u.y, -u.x))
        use = L - 2 * edge
        k = max(1, int(round(use / spacing)))
        for j in range(k + 1):
            t = edge + use * j / k
            fin(b, p0 + u * t, u, nr, w, d, z0, z1, mat)


def belt(b, pts, z0, z1, out=0.25, mat="Trim", bottom=True):
    """Solid band (closed prism) around a polygon, protruding `out` m. Top cap omitted when the shaft continues above."""
    P = inflate(pts, out)
    b.prism(P, z0, z1, mat, cap_bottom=bottom, cap_top=False)


def belt_ring(b, pts, z0, z1, out, mat="Trim"):
    """Band as a ring (outer wall, top and bottom flanges) - no filled top cap."""
    O = inflate(pts, out)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        o0, o1, w0, w1 = O[i], O[j], pts[i], pts[j]
        b.quad((o0[0], o0[1], z0), (o1[0], o1[1], z0), (o1[0], o1[1], z1), (o0[0], o0[1], z1), mat)       # outer
        b.quad((o0[0], o0[1], z1), (o1[0], o1[1], z1), (w1[0], w1[1], z1), (w0[0], w0[1], z1), mat)        # top flange
        b.quad((w0[0], w0[1], z0), (w1[0], w1[1], z0), (o1[0], o1[1], z0), (o0[0], o0[1], z0), mat)        # bottom flange


# ------------------------------------------------------------------------------------------------ letters (block neon letters)
_LETTERS = {
    "H": [(0, 0, 1, 5), (2, 0, 3, 5), (1, 2, 2, 3)],
    "O": [(0, 0, 3, 1), (0, 4, 3, 5), (0, 1, 1, 4), (2, 1, 3, 4)],
    "T": [(0, 4, 3, 5), (1, 0, 2, 4)],
    "E": [(0, 0, 1, 5), (1, 0, 3, 1), (1, 2, 3, 3), (1, 4, 3, 5)],
    "L": [(0, 0, 1, 5), (1, 0, 3, 1)],
    "A": [(0, 0, 1, 4), (2, 0, 3, 4), (0, 4, 3, 5), (1, 2, 2, 3)],
    "R": [(0, 0, 1, 5), (1, 4, 3, 5), (2, 2, 3, 4), (1, 2, 3, 3), (2, 0, 3, 2)],
    "M": [(0, 0, 1, 5), (2, 0, 3, 5), (1, 3, 2, 5)],
    "I": [(1, 0, 2, 5), (0, 0, 3, 1), (0, 4, 3, 5)],
    "N": [(0, 0, 1, 5), (2, 0, 3, 5), (1, 3, 2, 4)],
    "B": [(0, 0, 1, 5), (1, 0, 3, 1), (1, 2, 3, 3), (1, 4, 3, 5), (2, 1, 3, 2), (2, 3, 3, 4)],
    "Y": [(0, 3, 1, 5), (2, 3, 3, 5), (1, 0, 2, 3)],
}


def letter(b, ch, origin, right, up, nrm, h, depth=0.3, mat="Neon"):
    """Block letter ch with its lower-left corner at `origin`, height h, written along `right`, facing `nrm`.
    (nrm, right, up) must be right-handed."""
    s = h / 5.0
    o = Vector(origin)
    right, up, nrm = Vector(right), Vector(up), Vector(nrm)
    for (x0, y0, x1, y1) in _LETTERS[ch]:
        c = o + right * ((x0 + x1) / 2 * s) + up * ((y0 + y1) / 2 * s) + nrm * (depth / 2)
        obox(b, c, nrm, right, up, depth, (x1 - x0) * s, (y1 - y0) * s, mat)
    return 3 * s


def text_v(b, text, top_origin, right, up, nrm, h, gap, depth=0.3, mat="Neon"):
    """Stack letters vertically (reading downwards). top_origin = lower-left corner of the first (top) letter."""
    o = Vector(top_origin)
    for ch in text:
        letter(b, ch, o, right, up, nrm, h, depth, mat)
        o = o - Vector(up) * (h + gap)


# ------------------------------------------------------------------------------------------------ misc
def ring3(z, r, n, rot=0.0, cx=0.0, cy=0.0):
    return [Vector((cx + r * math.cos(rot + 2 * math.pi * i / n), cy + r * math.sin(rot + 2 * math.pi * i / n), z)) for i in range(n)]


def lerp(a, b, t):
    return a + (b - a) * t
