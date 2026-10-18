"""
lane13_lib.py - helper layer for Blender lane 13 (trains, shooting range, dealer lot, police / race / beach / park props, rocket).
Load AFTER gta_lib.py (same exec namespace):
    exec(open(r"...\\tools\\blender\\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"...\\tools\\blender\\lane13_lib.py", encoding="utf8").read(), globals())

Conventions (Blender, metres): +Y forward (-> -Z in Godot), +X right, +Z up.  Every face is created with an EXPLICIT outward
normal (HB.pq / lathe / ...), finish_h() never recalculates normals, so open shells (walls with window holes, flags, sails...)
come out right.  Objects are named "<assetid>__<Node>", root "<assetid>__root" in workshop(13, slot, spacing).
Materials: lane-13 customs live in M13 (unique names); names that other lanes also use (SandBag, Hazard ...) are redefined with
EXACTLY the same values so loading this library never changes another lane's colours.
"""
import bpy
import bmesh
import math
from mathutils import Vector, Matrix

L13 = 13
USER_PROMPT = "Build the Halcyon Bay Godot GTA game (Blender asset production)."
UPV = Vector((0, 0, 1))

M13 = {
    # ---- trains
    "TrainFloor":   dict(color="#3a3f47", rough=0.9),
    "TrainInner":   dict(color="#e6e2d6", rough=0.9),
    "TrainCeil":    dict(color="#f2f0ea", rough=0.9),
    "TrainSeat":    dict(color="#2f9c95", rough=0.95),
    "TrainSeatDk":  dict(color="#1f6f6c", rough=0.95),
    "TrainCoral":   dict(color="#e8795f", rough=0.95),
    "TrainGlow":    dict(color="#fff0c8", rough=0.3, emit="#ffe9b8", emit_strength=2.2),
    "CabConsole":   dict(color="#16222e", rough=0.4, emit="#34e0ff", emit_strength=0.8),
    # ---- shooting range / dealer / police (values identical to the lane 7 / lane 9 definitions where names overlap)
    "TargetRed":    dict(color="#d93a3a", rough=0.6),
    "TargetWhite":  dict(color="#f2f0ea", rough=0.6),
    "TargetBlack":  dict(color="#15171a", rough=0.7),
    "TargetTan":    dict(color="#c9a86a", rough=0.85),
    "SandBag":      dict(color="#b9a67a", rough=0.98),
    "Hazard":       dict(color="#f2cf3a", rough=0.7),
    "RailYellow":   dict(color="#f2cf3a", rough=0.6),
    "ConcreteDk":   dict(color="#77736c", rough=0.95),
    "PoliceNavy":   dict(color="#25324d", rough=0.8),
    "PoleGrey":     dict(color="#7d8791", rough=0.5, metal=0.6),
    "PoleGreen":    dict(color="#3b5a55", rough=0.55, metal=0.35),
    "FlagRed":      dict(color="#c8372f", rough=0.8),
    "FlagBlue":     dict(color="#2a4f9a", rough=0.8),
    "TrimWhite":    dict(color="#f2f0ea", rough=0.8),
    "Asphalt":      dict(color="#2b2e33", rough=0.95),
    "LineWhite":    dict(color="#e9e6dc", rough=0.8),
    "NeonAmber":    dict(color="#ffb347", rough=0.3, emit="#ffb347", emit_strength=5.0),
    "NeonRed":      dict(color="#ff2a22", rough=0.3, emit="#ff2a22", emit_strength=5.0),
    "NeonGreen":    dict(color="#3dffa0", rough=0.3, emit="#3dffa0", emit_strength=5.0),
    "NeonWhite":    dict(color="#f4f8ff", rough=0.3, emit="#f4f8ff", emit_strength=4.0),
    "AwningCoral":  dict(color="#e8795f", rough=0.9),
    "AwningWhite":  dict(color="#f4efe6", rough=0.9),
    "WoodLight":    dict(color="#b98a5a", rough=0.85),
    "WoodDark":     dict(color="#6b4630", rough=0.9),
    "WoodPale":     dict(color="#d6bd92", rough=0.85),
    "ConeOrange":   dict(color="#ee6a1f", rough=0.6),
    "SafetyOrange": dict(color="#ee7a1f", rough=0.55),
    "Reflector":    dict(color="#f2a21f", rough=0.3, emit="#f2a21f", emit_strength=0.4),
    "ReflectRed":   dict(color="#c82a2a", rough=0.3, emit="#c82a2a", emit_strength=0.3),
    "RopeTan":      dict(color="#c9a86a", rough=0.95),
    "PlateRed":     dict(color="#d93a3a", rough=0.45),
    "PlateWhite":   dict(color="#f2f0ea", rough=0.45),
    "PlateBlue":    dict(color="#2f6fd6", rough=0.45),
    "PlateYellow":  dict(color="#f2cf3a", rough=0.45),
    "ConcreteDark": dict(color="#9a958c", rough=0.95),
    "MetalLt":      dict(color="#b6bec7", rough=0.4, metal=0.85),
    # ---- dealer / race / beach / park (lane 13 only)
    "DealerTeal":   dict(color="#2f9c95", rough=0.6),
    "DealerNavy":   dict(color="#25324d", rough=0.6),
    "StallPaint":   dict(color="#e9e6dc", rough=0.8),
    "PavingDark":   dict(color="#3a3e45", rough=0.95),
    "PavingLight":  dict(color="#a6a196", rough=0.95),
    "ChequerWhite": dict(color="#f2f0ea", rough=0.5),
    "ChequerBlack": dict(color="#15171a", rough=0.5),
    "RingGlow":     dict(color="#34e0ff", rough=0.3, emit="#34e0ff", emit_strength=4.0, alpha=0.55),
    "Rocket":       dict(color="#2a2d33", rough=0.5, metal=0.6),
    "RocketOrange": dict(color="#ee6a1f", rough=0.5),
    "Flame":        dict(color="#ffb347", rough=0.3, emit="#ff8a2b", emit_strength=6.0),
    "Brass":        dict(color="#c9a14a", rough=0.35, metal=0.9),
}
for _n, _s in M13.items():
    mat(_n, **_s)
for _n in ("Paint", "Paint2", "Glass", "Chrome", "Trim", "Tire", "Rim", "Interior", "LightHead", "LightTail", "LightAmber", "LightBlue", "LightRed",
           "Plate", "Metal", "MetalDark", "Concrete", "Wood", "Neon", "NeonCyan", "LampGlow", "Window", "Roof", "WallA", "WallB", "WallC", "WallD",
           "Accent", "Leaf", "LeafLight", "Bark", "Sand", "Rock", "Skin", "Water"):
    std_mat(_n)


def _r(v):
    return round(v, 5)


def rects_with_holes(u0, u1, v0, v1, holes):
    """Axis-aligned rectangle [u0,u1]x[v0,v1] minus holes [(ua,ub,va,vb)...] -> list of merged rects [ua,ub,va,vb]."""
    holes = [(_r(h[0]), _r(h[1]), _r(h[2]), _r(h[3])) for h in holes]
    us = sorted({_r(u0), _r(u1)} | {h[0] for h in holes} | {h[1] for h in holes})
    vs = sorted({_r(v0), _r(v1)} | {h[2] for h in holes} | {h[3] for h in holes})
    us = [u for u in us if u0 - 1e-6 <= u <= u1 + 1e-6]
    vs = [v for v in vs if v0 - 1e-6 <= v <= v1 + 1e-6]
    rects = []
    open_ = {}
    for j in range(len(vs) - 1):
        va, vb = vs[j], vs[j + 1]
        vm = (va + vb) / 2
        runs = []
        cur = None
        for i in range(len(us) - 1):
            ua, ub = us[i], us[i + 1]
            um = (ua + ub) / 2
            if any(h[0] < um < h[1] and h[2] < vm < h[3] for h in holes):
                cur = None
                continue
            if cur is None:
                cur = [ua, ub]
                runs.append(cur)
            else:
                cur[1] = ub
        newopen = {}
        for ua, ub in runs:
            r = open_.get((ua, ub))
            if r is not None and abs(r[3] - va) < 1e-6:
                r[3] = vb
                newopen[(ua, ub)] = r
            else:
                r = [ua, ub, va, vb]
                rects.append(r)
                newopen[(ua, ub)] = r
        open_ = newopen
    return rects


# ----------------------------------------------------------------------------------------------------------------
# transforms applied to everything built inside a `with xf(b, M):` block
# ----------------------------------------------------------------------------------------------------------------
def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def RX(d):
    return Matrix.Rotation(math.radians(d), 4, "X")


def RY(d):
    return Matrix.Rotation(math.radians(d), 4, "Y")


def RZ(d):
    return Matrix.Rotation(math.radians(d), 4, "Z")


def about(pivot, R):
    p = Vector(pivot)
    return T(*p) @ R @ T(*(-p))


class xf:
    """with xf(b, matrix): <build anything>  -> everything built inside is transformed by `matrix` (rotations/translations only)."""

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


def _ax(axis, a, u, v):
    if axis == "X":
        return Vector((a, u, v))
    if axis == "Y":
        return Vector((v, a, u))
    return Vector((u, v, a))


class HB(MB):
    """MB + explicit-normal primitives (every face has a caller-defined outward normal; nothing is recalculated)."""

    def pq(self, pts, n, m="Trim"):
        p = [Vector(q) for q in pts]
        nn = Vector((0, 0, 0))
        for i in range(len(p)):
            a, b = p[i], p[(i + 1) % len(p)]
            nn.x += (a.y - b.y) * (a.z + b.z)
            nn.y += (a.z - b.z) * (a.x + b.x)
            nn.z += (a.x - b.x) * (a.y + b.y)
        if nn.dot(Vector(n)) < 0:
            p.reverse()
        return self.face([self.v(q) for q in p], m)

    def po(self, pts, c, m="Trim"):
        """polygon whose normal points away from the point c"""
        fc = sum((Vector(q) for q in pts), Vector()) / len(pts)
        return self.pq(pts, fc - Vector(c), m)

    def xq(self, x, y0, y1, z0, z1, s, m="Trim"):
        if abs(y1 - y0) < 1e-6 or abs(z1 - z0) < 1e-6:
            return None
        return self.pq([(x, y0, z0), (x, y1, z0), (x, y1, z1), (x, y0, z1)], (s, 0, 0), m)

    def yq(self, y, x0, x1, z0, z1, s, m="Trim"):
        if abs(x1 - x0) < 1e-6 or abs(z1 - z0) < 1e-6:
            return None
        return self.pq([(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], (0, s, 0), m)

    def zq(self, z, x0, x1, y0, y1, s, m="Trim"):
        if abs(x1 - x0) < 1e-6 or abs(y1 - y0) < 1e-6:
            return None
        return self.pq([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], (0, 0, s), m)

    def abox(self, x0, x1, y0, y1, z0, z1, m="Trim", skip=""):
        """Axis-aligned box by bounds. skip = space separated outward faces to omit, e.g. '-z +y'."""
        x0, x1 = min(x0, x1), max(x0, x1)
        y0, y1 = min(y0, y1), max(y0, y1)
        z0, z1 = min(z0, z1), max(z0, z1)
        sk = skip.split()
        if "+x" not in sk: self.xq(x1, y0, y1, z0, z1, 1, m)
        if "-x" not in sk: self.xq(x0, y0, y1, z0, z1, -1, m)
        if "+y" not in sk: self.yq(y1, x0, x1, z0, z1, 1, m)
        if "-y" not in sk: self.yq(y0, x0, x1, z0, z1, -1, m)
        if "+z" not in sk: self.zq(z1, x0, x1, y0, y1, 1, m)
        if "-z" not in sk: self.zq(z0, x0, x1, y0, y1, -1, m)

    def cbox(self, c, size, m="Trim", skip=""):
        self.abox(c[0] - size[0] / 2, c[0] + size[0] / 2, c[1] - size[1] / 2, c[1] + size[1] / 2, c[2] - size[2] / 2, c[2] + size[2] / 2, m, skip)

    def tbox(self, bot, top, m="Trim", skip="", shift=(0, 0)):
        """Tapered box: bot=(x0,x1,y0,y1,z) rectangle at the bottom, top=(x0,x1,y0,y1,z) rectangle on top."""
        a = [(bot[0], bot[2], bot[4]), (bot[1], bot[2], bot[4]), (bot[1], bot[3], bot[4]), (bot[0], bot[3], bot[4])]
        t = [(top[0], top[2], top[4]), (top[1], top[2], top[4]), (top[1], top[3], top[4]), (top[0], top[3], top[4])]
        c = (sum(p[0] for p in a + t) / 8, sum(p[1] for p in a + t) / 8, sum(p[2] for p in a + t) / 8)
        sk = skip.split()
        sides = {"-y": (a[0], a[1], t[1], t[0]), "+x": (a[1], a[2], t[2], t[1]), "+y": (a[2], a[3], t[3], t[2]), "-x": (a[3], a[0], t[0], t[3])}
        for k, f in sides.items():
            if k not in sk:
                self.po(f, c, m)
        if "+z" not in sk: self.pq(t, (0, 0, 1), m)
        if "-z" not in sk: self.pq(a, (0, 0, -1), m)

    def hip(self, x0, x1, y0, y1, z, h, inset_x, inset_y, m="Roof", skip=""):
        self.tbox((x0, x1, y0, y1, z), (x0 + inset_x, x1 - inset_x, y0 + inset_y, y1 - inset_y, z + h), m, skip)

    # ---------- extruded profiles ----------
    def _prism(self, pts, lo, hi, axis, mat, caps=(True, True), skip_edges=()):
        pts = [tuple(p) for p in pts]
        area = 0.0
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            area += a[0] * b[1] - b[0] * a[1]
        if area < 0:
            pts.reverse()

        def p3(u, v, t):
            if axis == "x": return (t, u, v)
            if axis == "y": return (u, t, v)
            return (u, v, t)

        def n3(nu, nv):
            if axis == "x": return (0, nu, nv)
            if axis == "y": return (nu, 0, nv)
            return (nu, nv, 0)

        n = len(pts)
        for i in range(n):
            if i in skip_edges:
                continue
            a, b = pts[i], pts[(i + 1) % n]
            du, dv = b[0] - a[0], b[1] - a[1]
            if abs(du) + abs(dv) < 1e-9:
                continue
            self.pq([p3(a[0], a[1], lo), p3(b[0], b[1], lo), p3(b[0], b[1], hi), p3(a[0], a[1], hi)], n3(dv, -du), mat)
        ax = {"x": (1, 0, 0), "y": (0, 1, 0), "z": (0, 0, 1)}[axis]
        if caps[1]:
            self.pq([p3(p[0], p[1], hi) for p in pts], ax, mat)
        if caps[0]:
            self.pq([p3(p[0], p[1], lo) for p in pts], tuple(-c for c in ax), mat)

    def ex(self, prof_yz, x0, x1, m="Trim", **kw):
        """extrude a (y,z) polygon across x0..x1"""
        self._prism(prof_yz, min(x0, x1), max(x0, x1), "x", m, **kw)

    def ey(self, prof_xz, y0, y1, m="Trim", **kw):
        """extrude an (x,z) polygon along y0..y1"""
        self._prism(prof_xz, min(y0, y1), max(y0, y1), "y", m, **kw)

    def ez(self, prof_xy, z0, z1, m="Trim", **kw):
        """extrude an (x,y) polygon up z0..z1"""
        self._prism(prof_xy, min(z0, z1), max(z0, z1), "z", m, **kw)

    # ---------- round things ----------
    def cyl(self, center, r, h, seg=8, m="Metal", axis="Z", r_top=None, caps="bt", rot=0.0, sc=(1.0, 1.0)):
        r_top = r if r_top is None else r_top
        c = Vector(center)
        B, T_ = [], []
        for i in range(seg):
            a = rot + 2 * math.pi * i / seg
            ca, sa = math.cos(a) * sc[0], math.sin(a) * sc[1]
            B.append(c + _ax(axis, -h / 2, ca * r, sa * r))
            T_.append(c + _ax(axis, h / 2, ca * r_top, sa * r_top))
        slope = (r - r_top) / h if h > 1e-9 else 0.0
        for i in range(seg):
            j = (i + 1) % seg
            am = rot + 2 * math.pi * (i + 0.5) / seg
            self.pq([B[i], B[j], T_[j], T_[i]], _ax(axis, slope, math.cos(am), math.sin(am)), m)
        if "b" in caps and r > 1e-6:
            self.pq(B, _ax(axis, -1, 0, 0), m)
        if "t" in caps and r_top > 1e-6:
            self.pq(T_, _ax(axis, 1, 0, 0), m)

    def beam(self, p0, p1, r0, r1=None, seg=6, m="Metal", caps=True):
        r1 = r0 if r1 is None else r1
        a, b = Vector(p0), Vector(p1)
        d = b - a
        if d.length < 1e-6:
            return
        z = d.normalized()
        up = Vector((0, 0, 1)) if abs(z.z) < 0.95 else Vector((1, 0, 0))
        x = up.cross(z).normalized()
        y = z.cross(x)
        R0, R1 = [], []
        for i in range(seg):
            ang = 2 * math.pi * i / seg
            off = x * math.cos(ang) + y * math.sin(ang)
            R0.append(a + off * r0)
            R1.append(a + d + off * r1)
        for i in range(seg):
            j = (i + 1) % seg
            am = 2 * math.pi * (i + 0.5) / seg
            n = x * math.cos(am) + y * math.sin(am)
            self.pq([R0[i], R0[j], R1[j], R1[i]], n, m)
        if caps:
            self.pq(R0, -z, m)
            self.pq(R1, z, m)

    def rbeam(self, p0, p1, w, h, m="Metal", up=(0, 0, 1)):
        """rectangular bar between two points (w across, h along the `up` reference) - rails, struts, slats"""
        a, b = Vector(p0), Vector(p1)
        d = b - a
        if d.length < 1e-6:
            return
        z = d.normalized()
        ref = Vector(up)
        if abs(z.dot(ref)) > 0.95:
            ref = Vector((1, 0, 0))
        x = ref.cross(z).normalized()
        y = z.cross(x)
        c = []
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            off = x * (w / 2 * sx) + y * (h / 2 * sy)
            c.append((a + off, b + off))
        for i in range(4):
            j = (i + 1) % 4
            mid = (c[i][0] + c[j][0]) / 2 - a
            mid -= z * mid.dot(z)
            self.pq([c[i][0], c[j][0], c[j][1], c[i][1]], mid, m)
        self.pq([k[0] for k in c], -z, m)
        self.pq([k[1] for k in c], z, m)

    def ball(self, center, r, seg=6, rings=3, m="Trim", sc=(1.0, 1.0, 1.0)):
        c = Vector(center)
        grid = []
        for k in range(rings + 1):
            phi = math.pi * k / rings
            row = []
            for i in range(seg):
                th = 2 * math.pi * i / seg
                row.append(c + Vector((math.sin(phi) * math.cos(th) * sc[0], math.sin(phi) * math.sin(th) * sc[1], math.cos(phi) * sc[2])) * r)
            grid.append(row)
        for k in range(rings):
            for i in range(seg):
                j = (i + 1) % seg
                if k == 0:
                    pts = [grid[0][0], grid[1][j], grid[1][i]]
                elif k == rings - 1:
                    pts = [grid[k][i], grid[k][j], grid[rings][0]]
                else:
                    pts = [grid[k][i], grid[k + 1][i], grid[k + 1][j], grid[k][j]]
                mid = sum((Vector(p) for p in pts), Vector()) / len(pts)
                self.pq(pts, mid - c, m)

    def disc(self, center, r, seg, normal, m, rot=0.0, axis="Z", sc=(1.0, 1.0)):
        """Flat filled polygon in the plane perpendicular to `axis`; normal = +1 / -1 along that axis."""
        c = Vector(center)
        pts = [c + _ax(axis, 0, math.cos(rot + 2 * math.pi * i / seg) * r * sc[0], math.sin(rot + 2 * math.pi * i / seg) * r * sc[1]) for i in range(seg)]
        self.pq(pts, _ax(axis, normal, 0, 0), m)

    def annulus(self, center, r0, r1, seg, normal, m, rot=0.0, axis="Z"):
        c = Vector(center)
        for i in range(seg):
            a0 = rot + 2 * math.pi * i / seg
            a1 = rot + 2 * math.pi * (i + 1) / seg
            pts = [c + _ax(axis, 0, math.cos(a0) * r0, math.sin(a0) * r0), c + _ax(axis, 0, math.cos(a1) * r0, math.sin(a1) * r0),
                   c + _ax(axis, 0, math.cos(a1) * r1, math.sin(a1) * r1), c + _ax(axis, 0, math.cos(a0) * r1, math.sin(a0) * r1)]
            self.pq(pts, _ax(axis, normal, 0, 0), m)

    def lathe(self, prof, center=(0, 0, 0), seg=10, m="Metal", axis="Z", rot=0.0, flip=1.0, mats=None):
        """Revolve an OPEN outline [(a, r), ...] (a = position along `axis`, r = radius) about the axis through `center`.
        The outline must run so that the solid is on its LEFT (a up, r right = ccw looking at the a-r plane); outward normal is
        computed from the segment direction. flip=-1 mirrors a along the axis (and the winding is kept right). mats: list of
        materials per profile segment."""
        c = Vector(center)
        n = len(prof)
        for k in range(n - 1):
            a0, r0 = prof[k]
            a1, r1 = prof[k + 1]
            da, dr = (a1 - a0), r1 - r0
            if abs(da) + abs(dr) < 1e-9:
                continue
            nax, nrad = dr * flip, -da   # outward normal in (axial, radial) world coordinates
            mk = mats[k] if mats else m
            for i in range(seg):
                t0 = rot + 2 * math.pi * i / seg
                t1 = rot + 2 * math.pi * (i + 1) / seg
                tm = (t0 + t1) / 2
                P00 = c + _ax(axis, a0 * flip, math.cos(t0) * r0, math.sin(t0) * r0)
                P01 = c + _ax(axis, a0 * flip, math.cos(t1) * r0, math.sin(t1) * r0)
                P11 = c + _ax(axis, a1 * flip, math.cos(t1) * r1, math.sin(t1) * r1)
                P10 = c + _ax(axis, a1 * flip, math.cos(t0) * r1, math.sin(t0) * r1)
                nrm = _ax(axis, nax, math.cos(tm) * nrad, math.sin(tm) * nrad)
                if r0 < 1e-7:
                    self.pq([P00, P11, P10], nrm, mk)
                elif r1 < 1e-7:
                    self.pq([P00, P01, P11], nrm, mk)
                else:
                    self.pq([P00, P01, P11, P10], nrm, mk)

    def torus(self, c, R, r, seg=12, tseg=4, m="NeonCyan", axis="Y", rot=0.0, tphase=0.0):
        """Torus ring around `axis` through c (major radius R, tube radius r)."""
        cc = Vector(c)
        rings = []
        for i in range(seg):
            th = math.radians(rot) + 2 * math.pi * i / seg
            ring = []
            for k in range(tseg):
                ph = tphase + 2 * math.pi * k / tseg
                rr = R + r * math.cos(ph)
                ring.append(cc + _ax(axis, r * math.sin(ph), rr * math.cos(th), rr * math.sin(th)))
            rings.append(ring)
        for i in range(seg):
            j = (i + 1) % seg
            thm = math.radians(rot) + 2 * math.pi * (i + 0.5) / seg
            for k in range(tseg):
                kk = (k + 1) % tseg
                pts = [rings[i][k], rings[j][k], rings[j][kk], rings[i][kk]]
                tc = cc + _ax(axis, 0, R * math.cos(thm), R * math.sin(thm))
                self.po(pts, tc, m)

    def loft(self, rings, centre, m="Paint", cap0=None, cap1=None, mats=None):
        """Skin rings (lists of 3D points, same count, closed). Faces point away from `centre(k)` (a point or a function of ring index)."""
        n = len(rings[0])
        for k in range(len(rings) - 1):
            ck = centre(k) if callable(centre) else centre
            for i in range(n):
                j = (i + 1) % n
                mk = mats[i % len(mats)] if mats else m
                self.po([rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]], ck, mk)
        if cap0:
            self.pq(rings[0], (rings[0][0] - rings[1][0]), cap0)
        if cap1:
            self.pq(rings[-1], (rings[-1][0] - rings[-2][0]), cap1)

    def finish_h(self, collection=None, name=None, loc=(0, 0, 0), parent=None, weld=0.0, uv="box"):
        bm = self.bm
        if weld:
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=weld)
        bm.normal_update()
        if uv == "box":
            uv_box(bm)
        me = bpy.data.meshes.new((name or self.name) + "_mesh")
        bm.to_mesh(me)
        bm.free()
        for mn in self.mats:
            me.materials.append(bpy.data.materials[mn])
        try:
            me.shade_flat()
        except Exception:
            for p in me.polygons:
                p.use_smooth = False
        obj = bpy.data.objects.new(name or self.name, me)
        obj.location = Vector(loc)
        if collection is not None and obj.name not in collection.objects:
            collection.objects.link(obj)
        if parent is not None:
            obj.parent = parent
        return obj


def ngon(n, r, cx=0.0, cy=0.0, rot=0.0):
    return [(cx + r * math.cos(math.radians(rot) + 2 * math.pi * i / n), cy + r * math.sin(math.radians(rot) + 2 * math.pi * i / n)) for i in range(n)]


def lerp(a, b, t):
    return a + (b - a) * t


# ----------------------------------------------------------------------------------------------------------------
# wall with holes (thick wall on a constant-X plane, used for train sides) - outer / inner quads + reveals
# ----------------------------------------------------------------------------------------------------------------
def wall_x(b, s, x_out, thick, y0, y1, z0, z1, holes, m_out, m_in, reveal="TrainInner", rects=None):
    """Thick wall on the side s (+1 right / -1 left): outer face at |x|=x_out, inner at x_out-thick. holes=[(ya,yb,za,zb)] (y along the
    car, z up). Emits outer quads (m_out), inner quads (m_in) and the 4 reveal faces of every hole (reveal material)."""
    xo, xi = s * x_out, s * (x_out - thick)
    for r in rects_with_holes(y0, y1, z0, z1, holes):
        b.xq(xo, r[0], r[1], r[2], r[3], s, m_out)
        b.xq(xi, r[0], r[1], r[2], r[3], -s, m_in)
    return


def reveals_x(b, s, x_out, thick, holes, m="TrainInner"):
    xo, xi = s * x_out, s * (x_out - thick)
    xa, xb = min(xo, xi), max(xo, xi)
    for (ya, yb, za, zb) in holes:
        b.yq(ya, xa, xb, za, zb, 1, m)       # jamb at the low-y edge faces +y (into the opening)
        b.yq(yb, xa, xb, za, zb, -1, m)
        b.zq(za, xa, xb, ya, yb, 1, m)       # sill faces up
        b.zq(zb, xa, xb, ya, yb, -1, m)      # head faces down


def pane_x(b, s, x, ya, yb, za, zb, m="Glass"):
    """two-sided translucent pane on the plane |x| = x"""
    b.xq(s * x, ya, yb, za, zb, s, m)          # materials are double sided in Godot (glTF doubleSided), one quad is enough


# ----------------------------------------------------------------------------------------------------------------
# Asset container
# ----------------------------------------------------------------------------------------------------------------
class A13:
    def __init__(self, aid, slot, cat="GTA_GODOT/StreetProps", spacing=30.0, paint=None, paint2=None):
        self.id = aid
        self.prefix = aid + "__"
        clear_asset(self.prefix)
        self.coll = coll(cat)
        self.origin = workshop(L13, slot, spacing)
        self.root = empty(self.prefix + "root", loc=self.origin, collection=self.coll, display="CUBE", size=0.3)
        self.objs = []
        self.paint = paint
        self.paint2 = paint2

    def mesh(self, b, name="Body", loc=(0, 0, 0), parent=None, uv="box", weld=0.0):
        o = b.finish_h(self.coll, self.prefix + name, loc=loc, parent=parent or self.root, uv=uv, weld=weld)
        if name.startswith("Collision") or name.startswith("Col_"):
            o.display_type = "WIRE"          # exportable but never hides the visual mesh in previews
            o.hide_render = True
        self.objs.append(o)
        return o

    def mark(self, name, loc, rot=(0, 0, 0), size=0.25, parent=None, display="ARROWS"):
        return empty(self.prefix + name, loc=loc, rot_deg=rot, parent=parent or self.root, collection=self.coll, display=display, size=size)

    # ---- local Paint / Paint2 so the preview shows the livery; swapped to the shared names at export only ----
    def local_paint(self):
        for base, col in (("Paint", self.paint), ("Paint2", self.paint2)):
            if col is None:
                continue
            spec = dict(STD[base])
            spec["color"] = col
            mat(self.prefix + base, **spec)

    def apply_local_paint(self):
        self.local_paint()
        for o in descendants(self.root):
            if o.type != "MESH":
                continue
            for i, m in enumerate(o.data.materials):
                if m is not None and m.name in ("Paint", "Paint2") and bpy.data.materials.get(self.prefix + m.name) is not None:
                    o.data.materials[i] = bpy.data.materials[self.prefix + m.name]

    def report(self, budget=3000):
        bpy.context.view_layer.update()
        info = stats(self.root, verbose=False)
        per = []
        for o in descendants(self.root):
            if o.type == "MESH":
                o.data.calc_loop_triangles()
                per.append((o.name.split("__", 1)[1], len(o.data.loop_triangles)))
        print("ASSET", self.id, "tris", info["tris"], "/", budget, "OVER" if info["tris"] > budget else "ok", "size", info["size"], "min", info["min"], "max", info["max"])
        print("  parts:", per)
        print("  materials:", info["materials"])
        print("  empties:", info["empties"])
        return info

    def export(self, rel):
        pairs = []
        try:
            for base in ("Paint", "Paint2"):
                loc = bpy.data.materials.get(self.prefix + base)
                sh = bpy.data.materials.get(base)
                if loc is None:
                    continue
                if sh is not None:
                    sh.name = base + "__lane13swap"
                loc.name = base
                pairs.append((base, loc, sh))
            path = export_glb(self.root, rel)
        finally:
            for base, loc, sh in pairs:
                loc.name = self.prefix + base
                if sh is not None:
                    sh.name = base
        return path


def island_check(obj):
    """signed volume per connected island of an object's mesh: islands with negative volume are inside-out (open shells give noise)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    neg = 0
    tot = 0
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        comp = []
        seen.add(v.index)
        while stack:
            a = stack.pop()
            comp.append(a)
            for e in a.link_edges:
                o = e.other_vert(a)
                if o.index not in seen:
                    seen.add(o.index)
                    stack.append(o)
        faces = set(f for a in comp for f in a.link_faces)
        closed = all(len(e.link_faces) == 2 for a in comp for e in a.link_edges)
        vol = 0.0
        for f in faces:
            vs = [lp.vert.co for lp in f.loops]
            for i in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[i].cross(vs[i + 1])) / 6.0
        tot += 1
        if closed and vol < -1e-9:
            neg += 1
    bm.free()
    return tot, neg
