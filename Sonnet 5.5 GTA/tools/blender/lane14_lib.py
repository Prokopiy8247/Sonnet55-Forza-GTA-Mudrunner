"""
lane14_lib.py - helper layer for Blender lane 14 (underwater wreck + sea life, helipad, vending / ATM, door pairs).
Load AFTER gta_lib.py (same exec namespace):
    exec(open(r"...\\tools\\blender\\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"...\\tools\\blender\\lane14_lib.py", encoding="utf8").read(), globals())

The geometry helpers (HB explicit-normal builder, xf transforms, rects_with_holes ...) are a verbatim copy of the lane 13 ones so
both lanes behave identically; the asset container A14 builds in workshop(14, slot, spacing) and the material table M14 only
holds lane-14 UNIQUE names (Wreck*, UW*, Coral*, Kelp*, Vend*, Atm*, Heli*, Door*) - shared names (Glass, LampGlow, Neon...) come from STD.
"""
import bpy
import bmesh
import math
import random
from mathutils import Vector, Matrix

L14 = 14
USER_PROMPT = "Build the Halcyon Bay Godot GTA game (Blender asset production)."
UPV = Vector((0, 0, 1))

M14 = {
    # ---- wreck (rust-brown / faded teal, desaturated & slightly teal-tinted so it reads under water fog)
    "WreckRust":    dict(color="#8a5238", rough=0.95),
    "WreckRustDk":  dict(color="#5a392c", rough=0.95),
    "WreckRedLead": dict(color="#7d4036", rough=0.95),
    "WreckTeal":    dict(color="#3f7f7c", rough=0.9),
    "WreckTealDk":  dict(color="#2c5c5c", rough=0.9),
    "WreckWhite":   dict(color="#a9b5ad", rough=0.9),
    "WreckBarn":    dict(color="#8c9b8a", rough=1.0),     # barnacle crust (pale grey-green)
    "WreckBarnLt":  dict(color="#b7c3b0", rough=1.0),
    "WreckAlgae":   dict(color="#4f7d59", rough=1.0),
    "WreckDeck":    dict(color="#7b6a56", rough=0.95),
    "WreckDeckDk":  dict(color="#554838", rough=0.95),
    "WreckSteel":   dict(color="#5d6a6c", rough=0.7, metal=0.4),
    "WreckBrass":   dict(color="#a8863e", rough=0.5, metal=0.7),
    "WreckCrate":   dict(color="#8a7050", rough=0.9),
    "WreckCrateDk": dict(color="#5d4a34", rough=0.9),
    "WreckTreasure": dict(color="#e0b04a", rough=0.35, metal=0.8, emit="#ffcf5a", emit_strength=0.6),
    # ---- sea life
    "UWSand":       dict(color="#c9bd98", rough=1.0),
    "UWSilt":       dict(color="#a89f80", rough=1.0),
    "UWRock":       dict(color="#6c7c7b", rough=1.0),
    "UWRockLt":     dict(color="#8a9a94", rough=1.0),
    "UWRockDk":     dict(color="#4b5a5c", rough=1.0),
    "UWAlgae":      dict(color="#4c8a5e", rough=1.0),
    "UWAlgaeDk":    dict(color="#2f6a4c", rough=1.0),
    "UWAlgaeLt":    dict(color="#78ad62", rough=1.0),
    "KelpGreen":    dict(color="#5a9a4a", rough=0.9),
    "KelpDark":     dict(color="#2f6a45", rough=0.9),
    "KelpLight":    dict(color="#9bc25a", rough=0.9),
    "KelpOlive":    dict(color="#7a8c3a", rough=0.9),
    "CoralPink":    dict(color="#f08aa8", rough=0.85),
    "CoralPinkDk":  dict(color="#c9587f", rough=0.85),
    "CoralOrange":  dict(color="#f59a58", rough=0.85),
    "CoralOrangeLt": dict(color="#ffc07a", rough=0.85),
    "CoralPurple":  dict(color="#a577cf", rough=0.85),
    "CoralPurpleDk": dict(color="#7a4fa5", rough=0.85),
    "CoralYellow":  dict(color="#ecca5c", rough=0.85),
    "CoralTeal":    dict(color="#4ec0b4", rough=0.85),
    "ClamShell":    dict(color="#d9b79c", rough=0.7),
    "ClamShellDk":  dict(color="#a6806a", rough=0.7),
    "ClamFlesh":    dict(color="#c9578c", rough=0.6),
    "Pearl":        dict(color="#f6f1ea", rough=0.15, metal=0.2, emit="#fff6e8", emit_strength=0.7),
    "StarOrange":   dict(color="#f2864a", rough=0.9),
    "StarDot":      dict(color="#ffd9a0", rough=0.9),
    "UrchinBody":   dict(color="#3b3050", rough=0.9),
    "UrchinSpine":  dict(color="#6b4f93", rough=0.8),
    "AnchorIron":   dict(color="#4a5256", rough=0.8, metal=0.5),
    "AnchorRust":   dict(color="#7e4b34", rough=0.95),
    "RopeOld":      dict(color="#a08c62", rough=1.0),
    "BarrelRed":    dict(color="#8a4538", rough=0.9),
    "BarrelBand":   dict(color="#454c50", rough=0.7, metal=0.5),
    # ---- helipad / street props
    "HeliPad":      dict(color="#4a4f57", rough=0.95),
    "HeliPadDk":    dict(color="#33373d", rough=0.95),
    "HeliYellow":   dict(color="#f2cf3a", rough=0.7),
    "HeliWhite":    dict(color="#ece8dc", rough=0.7),
    "HeliCurb":     dict(color="#b9b3a6", rough=0.9),
    "VendBody":     dict(color="#d6362f", rough=0.5),
    "VendBodyDk":   dict(color="#9c2622", rough=0.55),
    "VendBlue":     dict(color="#2f6fd6", rough=0.5),
    "VendBlueDk":   dict(color="#244f9a", rough=0.55),
    "VendPanel":    dict(color="#1e2a38", rough=0.2),
    "VendShelf":    dict(color="#c9d1d9", rough=0.4, metal=0.6),
    "VendCan1":     dict(color="#e8795f", rough=0.4, metal=0.5),
    "VendCan2":     dict(color="#34a8c8", rough=0.4, metal=0.5),
    "VendCan3":     dict(color="#e0b04a", rough=0.4, metal=0.5),
    "VendCan4":     dict(color="#7ea286", rough=0.4, metal=0.5),
    "VendSnackA":   dict(color="#ff3d9a", rough=0.6),
    "VendSnackB":   dict(color="#f2cf3a", rough=0.6),
    "VendSnackC":   dict(color="#4f9d52", rough=0.6),
    "AtmBody":      dict(color="#3a4150", rough=0.5, metal=0.3),
    "AtmBodyLt":    dict(color="#8d96a0", rough=0.45, metal=0.6),
    "AtmSlot":      dict(color="#0f1114", rough=0.6),
    "AtmKey":       dict(color="#d6dbe0", rough=0.5),
    "AtmGreen":     dict(color="#3dffa0", rough=0.3, emit="#3dffa0", emit_strength=3.0),
    "DoorFrameSteel": dict(color="#aab3bd", rough=0.4, metal=0.8),
    "DoorFrameWhite": dict(color="#e6e2d6", rough=0.6),
    "DoorFrameNavy":  dict(color="#25324d", rough=0.55, metal=0.2),
    "DoorBar":      dict(color="#c9d1d9", rough=0.25, metal=1.0),
    "DoorSensor":   dict(color="#1b1c1f", rough=0.5),
    "DoorTealStripe": dict(color="#2f9c95", rough=0.5),
    "DoorDecal":    dict(color="#f2f0ea", rough=0.5),
}
for _n, _s in M14.items():
    mat(_n, **_s)
for _n in ("Glass", "Chrome", "Trim", "Metal", "MetalDark", "Concrete", "Wood", "Neon", "NeonCyan", "LampGlow", "Rock", "Sand", "Leaf", "LeafLight"):
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
# Asset container
# ----------------------------------------------------------------------------------------------------------------
class A14:
    def __init__(self, aid, slot, cat="GTA_GODOT/StreetProps", spacing=40.0):
        self.id = aid
        self.prefix = aid + "__"
        clear_asset(self.prefix)
        self.coll = coll(cat)
        self.origin = workshop(L14, slot, spacing)
        self.root = empty(self.prefix + "root", loc=self.origin, collection=self.coll, display="CUBE", size=0.3)
        self.objs = []

    def mesh(self, b, name="Body", loc=(0, 0, 0), parent=None, uv="box", weld=0.0):
        o = b.finish_h(self.coll, self.prefix + name, loc=loc, parent=parent or self.root, uv=uv, weld=weld)
        self.objs.append(o)
        return o

    def mark(self, name, loc, rot=(0, 0, 0), size=0.25, parent=None, display="ARROWS"):
        return empty(self.prefix + name, loc=loc, rot_deg=rot, parent=parent or self.root, collection=self.coll, display=display, size=size)

    def report(self, budget=400):
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
        return export_glb(self.root, rel)


def transform_all(b, M):
    """apply matrix M to every vertex of builder b (rotation/translation)"""
    bmesh.ops.transform(b.bm, matrix=M, verts=list(b.bm.verts))


def vmin_z(b):
    return min(v.co.z for v in b.bm.verts)


# ----------------------------------------------------------------------------------------------------------------
# shared props
# ----------------------------------------------------------------------------------------------------------------
def crate(b, c, s=0.8, yaw=0.0, tx=0.0, ty=0.0, m0="WreckCrate", m1="WreckCrateDk", h=None, style="band"):
    """wooden shipping crate (sides s x s x h, centred at c, h defaults to 0.9 s). style 'band' = one belt, 'brace' = corner battens + Z brace on every side"""
    h = h or s * 0.9
    M = T(*c) @ RZ(yaw) @ RX(tx) @ RY(ty)
    with xf(b, M):
        b.cbox((0, 0, 0), (s, s, h), m0, skip="-z")
        k = s / 2 + 0.012
        for (sx, sy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if style == "band":
                if sx:
                    b.xq(sx * k, -s / 2, s / 2, -0.05, 0.1, sx, m1)
                else:
                    b.yq(sy * k, -s / 2, s / 2, -0.05, 0.1, sy, m1)
                continue
            # brace style: two vertical battens + a diagonal
            u0, u1 = -s / 2, s / 2
            bw = s * 0.11
            z0, z1 = -h / 2, h / 2
            def Q(u, z):
                return (sx * k, u, z) if sx else (u, sy * k, z)
            nrm = (sx, 0, 0) if sx else (0, sy, 0)
            for (ua, ub) in ((u0, u0 + bw), (u1 - bw, u1)):
                b.pq([Q(ua, z0), Q(ub, z0), Q(ub, z1), Q(ua, z1)], nrm, m1)
            d = bw * 0.55
            b.pq([Q(u0 + bw, z0), Q(u0 + bw + d * 2, z0), Q(u1 - bw, z1), Q(u1 - bw - d * 2, z1)], nrm, m1)


def barrel(b, c, r=0.28, hgt=0.85, axis="Z", m0="BarrelRed", m1="BarrelBand"):
    b.cyl(c, r, hgt, 8, m0, axis=axis, caps="bt", r_top=r)
    b.cyl(c, r * 1.03, 0.07, 8, m1, axis=axis, caps="")


# ----------------------------------------------------------------------------------------------------------------
# organic helpers (sea life, rocks)
# ----------------------------------------------------------------------------------------------------------------
_ICO = {}


def ico(subdiv=1):
    """unit icosphere (list of Vector verts, list of index triples), cached"""
    if subdiv in _ICO:
        return _ICO[subdiv]
    t = (1 + 5 ** 0.5) / 2
    V = [Vector(v).normalized() for v in ((-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1))]
    F = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
         (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    for _ in range(subdiv):
        cache = {}
        nf = []

        def mid(i, j):
            k = (min(i, j), max(i, j))
            if k not in cache:
                V.append(((V[i] + V[j]) / 2).normalized())
                cache[k] = len(V) - 1
            return cache[k]
        for (a, b_, c_) in F:
            ab, bc, ca = mid(a, b_), mid(b_, c_), mid(c_, a)
            nf += [(a, ab, ca), (b_, bc, ab), (c_, ca, bc), (ab, bc, ca)]
        F = nf
    _ICO[subdiv] = (V, F)
    return V, F


def blob(b, c, radii, seed=1, subdiv=1, jitter=0.15, mats=("UWRockLt", "UWRock", "UWRockDk"), top=0.55, low=-0.25, ground=None, rot=0.0,
         hide_under=False, squash_top=0.0):
    """faceted lumpy ellipsoid centred at c. mats = (top, side, bottom) chosen by face normal z (> top / < low).
    ground: z plane - vertices below are clamped to it and faces lying on it are dropped (no hidden underside).
    squash_top: flatten the top cap (0..1)."""
    V, F = ico(subdiv)
    rr = random.Random(seed)
    cv = Vector(c)
    R = Matrix.Rotation(rot, 3, "Z")
    pts = []
    for v in V:
        k = 1 + rr.uniform(-jitter, jitter)
        z = v.z * radii[2] * k
        if squash_top and z > 0:
            z *= (1 - squash_top)
        p = R @ Vector((v.x * radii[0] * k, v.y * radii[1] * k, z))
        pts.append(cv + p)
    if ground is not None:
        for p in pts:
            if p.z < ground:
                p.z = ground
    for f in F:
        a, b_, c_ = (pts[i] for i in f)
        n = (b_ - a).cross(c_ - a)
        if n.length < 1e-9:
            continue
        n.normalize()
        cen = (a + b_ + c_) / 3
        if (cen - cv).dot(n) < 0:
            n = -n
        if ground is not None and max(a.z, b_.z, c_.z) <= ground + 1e-4:
            continue
        if hide_under and n.z < -0.55:
            continue
        m = mats[0] if n.z > top else (mats[2] if n.z < low else mats[1])
        b.pq([a, b_, c_], n, m)


def perp_basis(d):
    d = Vector(d).normalized()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((1, 0, 0))
    x = up.cross(d).normalized()
    y = d.cross(x)
    return x, y, d


def limb(b, p, q, r0, r1, seg=4, mat="CoralPink", tip=True, rot=0.0, mat_tip=None):
    """tapered prism p->q (no bottom cap - it hides in the parent); tip=True closes the far end"""
    a, e = Vector(p), Vector(q)
    x, y, z = perp_basis(e - a)
    R0, R1 = [], []
    for i in range(seg):
        ang = rot + 2 * math.pi * i / seg
        off = x * math.cos(ang) + y * math.sin(ang)
        R0.append(a + off * r0)
        R1.append(e + off * r1)
    for i in range(seg):
        j = (i + 1) % seg
        am = rot + 2 * math.pi * (i + 0.5) / seg
        n = x * math.cos(am) + y * math.sin(am)
        b.pq([R0[i], R0[j], R1[j], R1[i]], n, mat)
    if tip:
        b.pq(R1, z, mat_tip or mat)
    return e


def rot_dir(d, ang_deg, az_deg):
    """direction d tilted by ang_deg towards azimuth az_deg (around d)"""
    x, y, z = perp_basis(d)
    a, w = math.radians(ang_deg), math.radians(az_deg)
    return (z * math.cos(a) + (x * math.cos(w) + y * math.sin(w)) * math.sin(a)).normalized()


def ribbon(b, pts, widths, mat="KelpGreen", side0=(1, 0, 0), twist=0.0, mats=None):
    """strip along the polyline pts with per-point width; `side0` = initial side direction, twist = deg of roll per point (about the tangent)"""
    n = len(pts)
    P = [Vector(p) for p in pts]
    rows = []
    side = Vector(side0)
    for i in range(n):
        t = (P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized()
        s = (side - t * side.dot(t))
        if s.length < 1e-6:
            s = t.cross(Vector((0, 0, 1)))
        s = s.normalized()
        s = Matrix.Rotation(math.radians(twist * i), 3, t) @ s
        rows.append((P[i] - s * widths[i] / 2, P[i] + s * widths[i] / 2, t, s))
    for i in range(n - 1):
        l0, r0, t0, s0 = rows[i]
        l1, r1, t1, s1 = rows[i + 1]
        nn = (r0 - l0).cross(l1 - l0)
        if widths[i + 1] < 1e-4:
            b.pq([l0, r0, P[i + 1]], nn, mats[i] if mats else mat)
        else:
            b.pq([l0, r0, r1, l1], nn, mats[i] if mats else mat)
