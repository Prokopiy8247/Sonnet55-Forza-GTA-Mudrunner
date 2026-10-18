"""
lane7_lib.py - Lane 7 (GTA_GODOT/Buildings, HERO LANDMARK buildings) helper layer on top of gta_lib.py.
Load AFTER gta_lib (already exec'd into globals()):
    exec(open(r"...\\tools\\blender\\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"...\\tools\\blender\\lane7_lib.py", encoding="utf8").read(), globals())

Conventions (Blender, metres): origin = footprint centre at ground, front door faces +Y (-> -Z in Godot).
Every face is created with an EXPLICIT outward normal (pq) so open shells never come out inside-out
(gta_lib's MB.finish() recalculates normals, which is unsafe for open shells; HB.finish_h() does not).

Side(b, face, cx, cy, hx, hy): local wall frame for face F(+Y) B(-Y) R(+X) L(-X) of a box footprint.
    u = to the RIGHT as seen from OUTSIDE (front: u = -x, back: u = +x, right wall(+X): u = +y, left wall(-X): u = -y),
    v = height z, d = distance outwards (negative = recessed).   S.u(a) converts the world coordinate along the wall to u.
"""
import bpy
import bmesh
import math
from mathutils import Vector

L7 = 7
COLL_BUILDINGS = "GTA_GODOT/Buildings"
USER_PROMPT = "Build the Halcyon Bay Godot GTA game (Blender asset production)."
UP = Vector((0, 0, 1))
FACES = {"F": Vector((0, 1, 0)), "B": Vector((0, -1, 0)), "R": Vector((1, 0, 0)), "L": Vector((-1, 0, 0))}

# Lane-7 specific materials (unique names; Godot maps unknown names to a generic colour material using these values).
# Names starting with "Neon" are emissive in Godot (colour = emission colour).
CUSTOM = {
    "TrimWhite":   dict(color="#f2f0ea", rough=0.8),
    "PoliceBlue":  dict(color="#6c8098", rough=0.9),
    "PoliceNavy":  dict(color="#25324d", rough=0.8),
    "HospWhite":   dict(color="#eef2f2", rough=0.85),
    "HospTeal":    dict(color="#2f9c95", rough=0.85),
    "HospTealDk":  dict(color="#1f6f6c", rough=0.85),
    "NeonGreen":   dict(color="#3dffa0", rough=0.3, emit="#3dffa0", emit_strength=5.0),
    "NeonAmber":   dict(color="#ffb347", rough=0.3, emit="#ffb347", emit_strength=5.0),
    "NeonRed":     dict(color="#ff2a22", rough=0.3, emit="#ff2a22", emit_strength=5.0),
    "NeonWhite":   dict(color="#f4f8ff", rough=0.3, emit="#f4f8ff", emit_strength=4.0),
    "ConcreteDk":  dict(color="#77736c", rough=0.95),
    "Bunker":      dict(color="#5b5f58", rough=0.95),
    "Hazard":      dict(color="#f2cf3a", rough=0.7),
    "SandBag":     dict(color="#b9a67a", rough=0.98),
    "ShopOrange":  dict(color="#ee8a2b", rough=0.7),
    "Stucco":      dict(color="#ecd7b3", rough=0.95),
    "StuccoDk":    dict(color="#d9b88f", rough=0.95),
    "Terracotta":  dict(color="#c4684a", rough=0.9),
    "ShutterTeal": dict(color="#2f9c95", rough=0.8),
    "GasRed":      dict(color="#d93a3a", rough=0.6),
    "AwningCoral": dict(color="#e8795f", rough=0.9),
    "AwningWhite": dict(color="#f4efe6", rough=0.9),
    "BarberRed":   dict(color="#d93a3a", rough=0.5),
    "BarberBlue":  dict(color="#2f6fd6", rough=0.5),
    "TileTeal":    dict(color="#2a7f86", rough=0.5),
    "TileDark":    dict(color="#1d4f5b", rough=0.5),
    "Mannequin":   dict(color="#e9e4da", rough=0.7),
    "PlumDk":      dict(color="#4a2f4d", rough=0.85),
    "GlassPane":   dict(color="#9ec6d8", rough=0.05, alpha=0.35),
    "RailYellow":  dict(color="#f2cf3a", rough=0.6),
    "ClockFace":   dict(color="#f7f3e8", rough=0.4, emit="#fff0c8", emit_strength=1.2),
    "BrickRed":    dict(color="#a4553f", rough=0.95),
    "Asphalt":     dict(color="#2b2e33", rough=0.95),
    "LineWhite":   dict(color="#e9e6dc", rough=0.8),
    "FlagRed":     dict(color="#c8372f", rough=0.8),
    "FlagBlue":    dict(color="#2a4f9a", rough=0.8),
    "Copper":      dict(color="#5fa98f", rough=0.6, metal=0.2),
    "Slate":       dict(color="#4f5a66", rough=0.9),
    "Cream":       dict(color="#eadfc4", rough=0.9),
}


def prep_mats(names):
    for n in names:
        if n in CUSTOM:
            mat(n, **CUSTOM[n])
        else:
            std_mat(n)


prep_mats(list(CUSTOM.keys()))
for _n in ("Window", "WallA", "WallB", "WallC", "WallD", "Roof", "RoofTile", "Trim", "Metal", "MetalDark", "Concrete", "Neon",
           "NeonCyan", "Glass", "Wood", "Accent", "LampGlow", "Leaf", "LeafLight", "LightAmber", "LightRed", "LightBlue", "Rock", "Plate",
           "Chrome", "Paint", "Paint2", "Interior", "SignalRed", "SignalGreen", "SignalAmber"):
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


def hgrid(u_cs, rows, w, h=None):
    """Window holes: u_cs = list of u centres; rows = list of v0 (with common h) or (v0, h) tuples."""
    out = []
    for r in rows:
        v0, hh = (r, h) if not isinstance(r, (tuple, list)) else (r[0], r[1])
        for u in u_cs:
            out.append((u - w / 2.0, u + w / 2.0, v0, v0 + hh))
    return out


def spread(a, b, n):
    """n evenly spaced centres between a and b (inclusive of half-cell margins): the centres of n equal cells of [a,b]."""
    return [a + (b - a) * (i + 0.5) / n for i in range(n)]


class HB(MB):
    """MB + explicit-normal primitives (open shells, no hidden-face waste)."""

    def __init__(self, name):
        MB.__init__(self, name)
        self.win_names = {"Window"}

    # ---------- orientation-safe polygon ----------
    def pq(self, pts, n, m="WallA"):
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

    def xq(self, x, y0, y1, z0, z1, s, m="WallA"):
        if abs(y1 - y0) < 1e-6 or abs(z1 - z0) < 1e-6:
            return None
        return self.pq([(x, y0, z0), (x, y1, z0), (x, y1, z1), (x, y0, z1)], (s, 0, 0), m)

    def yq(self, y, x0, x1, z0, z1, s, m="WallA"):
        if abs(x1 - x0) < 1e-6 or abs(z1 - z0) < 1e-6:
            return None
        return self.pq([(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], (0, s, 0), m)

    def zq(self, z, x0, x1, y0, y1, s, m="WallA"):
        if abs(x1 - x0) < 1e-6 or abs(y1 - y0) < 1e-6:
            return None
        return self.pq([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], (0, 0, s), m)

    def abox(self, x0, x1, y0, y1, z0, z1, m="WallA", skip=""):
        """Axis-aligned box by bounds. skip = space separated outward faces to omit, e.g. '-y -x +z'."""
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

    def cbox(self, c, size, m="WallA", skip=""):
        self.abox(c[0] - size[0] / 2, c[0] + size[0] / 2, c[1] - size[1] / 2, c[1] + size[1] / 2, c[2] - size[2] / 2, c[2] + size[2] / 2, m, skip)

    def hip(self, x0, x1, y0, y1, z, h, inset_x, inset_y, m="Roof", skip=""):
        """Tapered block (frustum) whose bottom is the rectangle at z and top rectangle is inset by inset_x/inset_y."""
        a = [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
        t = [(x0 + inset_x, y0 + inset_y, z + h), (x1 - inset_x, y0 + inset_y, z + h), (x1 - inset_x, y1 - inset_y, z + h), (x0 + inset_x, y1 - inset_y, z + h)]
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        sk = skip.split()
        faces = {"-y": (a[0], a[1], t[1], t[0]), "+x": (a[1], a[2], t[2], t[1]), "+y": (a[2], a[3], t[3], t[2]), "-x": (a[3], a[0], t[0], t[3])}
        for k, f in faces.items():
            if k in sk:
                continue
            mid = sum((Vector(p) for p in f), Vector()) / 4
            n = Vector((mid.x - cx, mid.y - cy, 0.3 * h + 0.01))
            self.pq(f, n, m)
        if "+z" not in sk:
            self.pq(t, (0, 0, 1), m)
        if "-z" not in sk:
            self.pq(a, (0, 0, -1), m)

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

    def ex(self, prof_yz, x0, x1, m="WallA", **kw):
        self._prism(prof_yz, min(x0, x1), max(x0, x1), "x", m, **kw)

    def ey(self, prof_xz, y0, y1, m="WallA", **kw):
        self._prism(prof_xz, min(y0, y1), max(y0, y1), "y", m, **kw)

    def ez(self, prof_xy, z0, z1, m="WallA", **kw):
        self._prism(prof_xy, min(z0, z1), max(z0, z1), "z", m, **kw)

    # ---------- round things with explicit normals ----------
    def cyl(self, center, r, h, seg=8, m="Metal", axis="Z", r_top=None, caps="bt", rot=0.0, sc=(1.0, 1.0)):
        r_top = r if r_top is None else r_top
        c = Vector(center)

        def tr(x, y, z):
            if axis == "Z": return Vector((x, y, z))
            if axis == "X": return Vector((z, x, y))
            return Vector((y, z, x))

        B, T = [], []
        for i in range(seg):
            a = rot + 2 * math.pi * i / seg
            ca, sa = math.cos(a) * sc[0], math.sin(a) * sc[1]
            B.append(c + tr(ca * r, sa * r, -h / 2))
            T.append(c + tr(ca * r_top, sa * r_top, h / 2))
        slope = (r - r_top) / h if h > 1e-9 else 0.0
        for i in range(seg):
            j = (i + 1) % seg
            am = rot + 2 * math.pi * (i + 0.5) / seg
            n = tr(math.cos(am), math.sin(am), slope)
            self.pq([B[i], B[j], T[j], T[i]], n, m)
        if "b" in caps and r > 1e-6:
            self.pq(B, tr(0, 0, -1), m)
        if "t" in caps and r_top > 1e-6:
            self.pq(T, tr(0, 0, 1), m)

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

    def ball(self, center, r, seg=6, rings=3, m="Mannequin", sc=(1.0, 1.0, 1.0)):
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

    def disc(self, center, r, seg, z_normal, m, rot=0.0, axis="Z", sc=(1.0, 1.0)):
        """Flat filled polygon facing +axis (z_normal=+1) or -axis (-1)."""
        c = Vector(center)

        def tr(x, y, z):
            if axis == "Z": return Vector((x, y, z))
            if axis == "X": return Vector((z, x, y))
            return Vector((y, z, x))

        pts = [c + tr(math.cos(rot + 2 * math.pi * i / seg) * r * sc[0], math.sin(rot + 2 * math.pi * i / seg) * r * sc[1], 0) for i in range(seg)]
        self.pq(pts, tr(0, 0, z_normal), m)

    def annulus(self, center, r0, r1, seg, z_normal, m, rot=0.0, axis="Z"):
        c = Vector(center)

        def tr(x, y, z):
            if axis == "Z": return Vector((x, y, z))
            if axis == "X": return Vector((z, x, y))
            return Vector((y, z, x))

        for i in range(seg):
            a0 = rot + 2 * math.pi * i / seg
            a1 = rot + 2 * math.pi * (i + 1) / seg
            pts = [c + tr(math.cos(a0) * r0, math.sin(a0) * r0, 0), c + tr(math.cos(a1) * r0, math.sin(a1) * r0, 0),
                   c + tr(math.cos(a1) * r1, math.sin(a1) * r1, 0), c + tr(math.cos(a0) * r1, math.sin(a0) * r1, 0)]
            self.pq(pts, tr(0, 0, z_normal), m)

    # ---------- finish ----------
    def finish_h(self, collection=None, name=None, loc=(0, 0, 0), parent=None, weld=0.0004, uv="box", winuv=True):
        bm = self.bm
        if weld:
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=weld)
        bm.normal_update()
        if uv == "box":
            uv_box(bm)
        if winuv:
            self._window_uv(bm)
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

    def _window_uv(self, bm):
        """Window faces: map each vertical window quad onto ONE cell of Godot's window shader pane grid
        (u: 2.0 m cells with offset 2.0, v: 0..3.6) so every window lights up independently and gets the glass gradient."""
        if "Window" not in self.mats:
            return
        wi = self.mats.index("Window")
        layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
        k = 0
        for f in bm.faces:
            if f.material_index != wi:
                continue
            n = f.normal
            if abs(n.z) > 0.7:
                continue
            t = UP.cross(n)
            if t.length < 1e-6:
                continue
            t.normalize()
            ss = [l.vert.co.dot(t) for l in f.loops]
            zs = [l.vert.co.z for l in f.loops]
            s0, s1 = min(ss), max(ss)
            z0, z1 = min(zs), max(zs)
            k += 1
            ub = 2.0 * (k % 997) - 2.0
            for l in f.loops:
                s = l.vert.co.dot(t)
                zz = l.vert.co.z
                uu = ub + 2.0 * (s - s0) / max(s1 - s0, 1e-6)
                vv = 3.6 * (zz - z0) / max(z1 - z0, 1e-6)
                l[layer].uv = (uu, vv)


class Side:
    """Wall frame of a box footprint centred (cx,cy) with half sizes (hx,hy): face F(+Y) B(-Y) R(+X) L(-X)."""

    def __init__(self, b, face, cx, cy, hx, hy):
        self.b = b
        self.face = face
        self.N = FACES[face]
        self.U = UP.cross(self.N)
        self.half = hx if face in "FB" else hy
        px, py = {"F": (cx, cy + hy), "B": (cx, cy - hy), "R": (cx + hx, cy), "L": (cx - hx, cy)}[face]
        self.P0 = Vector((px, py, 0.0))
        self.cx, self.cy = cx, cy

    def u(self, a):
        """world coordinate along the wall (x for F/B, y for L/R) -> u"""
        if self.face in "FB":
            return self.U.x * (a - self.P0.x)
        return self.U.y * (a - self.P0.y)

    def P(self, u, v, d=0.0):
        return self.P0 + self.U * u + UP * v + self.N * d

    def q(self, u0, u1, v0, v1, d=0.0, m="WallA", back=False):
        if abs(u1 - u0) < 1e-6 or abs(v1 - v0) < 1e-6:
            return None
        n = -self.N if back else self.N
        return self.b.pq([self.P(u0, v0, d), self.P(u1, v0, d), self.P(u1, v1, d), self.P(u0, v1, d)], n, m)

    def poly(self, uv, d=0.0, m="WallA", both=False):
        pts = [self.P(p[0], p[1], d) for p in uv]
        self.b.pq(pts, self.N, m)
        if both:
            self.b.pq(pts, -self.N, m)

    def stroke(self, p0, p1, w, d=0.0, m="Neon", both=False):
        """thin rectangle between two (u,v) points with width w"""
        a, b2 = Vector((p0[0], p0[1])), Vector((p1[0], p1[1]))
        dv = b2 - a
        if dv.length < 1e-6:
            return
        nrm = Vector((-dv.y, dv.x)).normalized() * (w / 2)
        pts = [a - nrm, b2 - nrm, b2 + nrm, a + nrm]
        self.poly([(p.x, p.y) for p in pts], d, m, both)

    def box(self, u0, u1, v0, v1, d0, d1, m="WallA", skip="i"):
        """Box in wall frame. skip letters: i=inner(d0) o=outer(d1) l=u0 side r=u1 side b=bottom t=top."""
        u0, u1 = min(u0, u1), max(u0, u1)
        v0, v1 = min(v0, v1), max(v0, v1)
        d0, d1 = min(d0, d1), max(d0, d1)
        P, b = self.P, self.b
        if "o" not in skip: b.pq([P(u0, v0, d1), P(u1, v0, d1), P(u1, v1, d1), P(u0, v1, d1)], self.N, m)
        if "i" not in skip: b.pq([P(u0, v0, d0), P(u1, v0, d0), P(u1, v1, d0), P(u0, v1, d0)], -self.N, m)
        if "l" not in skip: b.pq([P(u0, v0, d0), P(u0, v0, d1), P(u0, v1, d1), P(u0, v1, d0)], -self.U, m)
        if "r" not in skip: b.pq([P(u1, v0, d0), P(u1, v0, d1), P(u1, v1, d1), P(u1, v1, d0)], self.U, m)
        if "b" not in skip: b.pq([P(u0, v0, d0), P(u1, v0, d0), P(u1, v0, d1), P(u0, v0, d1)], -UP, m)
        if "t" not in skip: b.pq([P(u0, v1, d0), P(u1, v1, d0), P(u1, v1, d1), P(u0, v1, d1)], UP, m)

    def wall(self, u0, u1, v0, v1, holes=(), m="WallA", d=0.0):
        for r in rects_with_holes(u0, u1, v0, v1, holes):
            self.q(r[0], r[1], r[2], r[3], d, m)

    def reveal(self, hole, depth, m="TrimWhite", sides="lrt"):
        u0, u1, v0, v1 = hole
        P, b = self.P, self.b
        if "l" in sides: b.pq([P(u0, v0, 0), P(u0, v0, -depth), P(u0, v1, -depth), P(u0, v1, 0)], self.U, m)
        if "r" in sides: b.pq([P(u1, v0, 0), P(u1, v0, -depth), P(u1, v1, -depth), P(u1, v1, 0)], -self.U, m)
        if "t" in sides: b.pq([P(u0, v1, 0), P(u0, v1, -depth), P(u1, v1, -depth), P(u1, v1, 0)], -UP, m)
        if "b" in sides: b.pq([P(u0, v0, 0), P(u0, v0, -depth), P(u1, v0, -depth), P(u1, v0, 0)], UP, m)

    def win(self, hole, depth=0.22, frame="TrimWhite", glass="Window", sill=0.0, sill_m=None, sides="lrt"):
        u0, u1, v0, v1 = hole
        self.reveal(hole, depth, frame, sides)
        self.q(u0, u1, v0, v1, -depth, glass)
        if sill > 0:
            self.box(u0 - 0.12, u1 + 0.12, v0 - 0.14, v0, 0.0, sill, sill_m or frame, skip="ilr")

    def wins(self, holes, **kw):
        for h in holes:
            self.win(h, **kw)

    def openings(self, u0, u1, v0, v1, holes, wall="WallA", **kw):
        """wall with holes + window units"""
        self.wall(u0, u1, v0, v1, holes, wall)
        self.wins(holes, **kw)


def shell(b, x0, x1, y0, y1, z0, z1, holes=None, wall="WallA", faces="FBLR", roof=None, win_kw=None, wall_by_face=None):
    """Box shell (open bottom): walls on the chosen faces with `holes[face]` window openings; roof=material name or None."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2, (y1 - y0) / 2
    sides = {}
    for f in faces:
        S = Side(b, f, cx, cy, hx, hy)
        sides[f] = S
        hl = (holes or {}).get(f, [])
        wm = (wall_by_face or {}).get(f, wall)
        S.openings(-S.half, S.half, z0, z1, hl, wm, **(win_kw or {}))
    if roof:
        b.zq(z1, x0, x1, y0, y1, 1, roof)
    return sides


class Asset:
    """One landmark asset: root empty in the workshop, meshes + empties parented to it, report/export helpers."""

    def __init__(self, aid, index):
        self.id = aid
        self.prefix = aid + "__"
        clear_asset(self.prefix)
        self.coll = coll(COLL_BUILDINGS)
        self.origin = workshop(L7, index, 60.0)
        self.root = empty(self.prefix + "root", loc=self.origin, collection=self.coll, display="CUBE", size=0.3)
        self.objs = []

    def mesh(self, b, name="Body", loc=(0, 0, 0), **kw):
        o = b.finish_h(self.coll, self.prefix + name, loc=loc, parent=self.root, **kw)
        if name.startswith("Collision") or name.startswith("Col_"):
            o.display_type = "WIRE"      # keep it exportable (selectable) but never z-fight with the visual mesh in previews
            o.hide_render = True
        self.objs.append(o)
        return o

    def mark(self, name, loc, rot=(0, 0, 0), size=0.6):
        e = empty(self.prefix + name, loc=loc, rot_deg=rot, parent=self.root, collection=self.coll, display="ARROWS", size=size)
        return e

    def report(self, budget=2500):
        bpy.context.view_layer.update()
        info = stats(self.root, verbose=False)
        per = []
        for o in self.objs:
            me = o.data
            me.calc_loop_triangles()
            per.append((o.name.split("__", 1)[1], len(me.loop_triangles)))
        print("ASSET", self.id, "tris", info["tris"], "/", budget, "OVER" if info["tris"] > budget else "ok", "size", info["size"], "min", info["min"], "max", info["max"])
        print("  parts:", per)
        print("  materials:", info["materials"])
        print("  empties:", info["empties"])
        return info

    def export(self, rel=None):
        return export_glb(self.root, rel or ("buildings/" + self.id))


def collision_boxes(b, boxes):
    """boxes = list of (x0,x1,y0,y1,z0,z1[, skip]) -> plain boxes for the Collision mesh (no UV needed)."""
    for bx in boxes:
        b.abox(bx[0], bx[1], bx[2], bx[3], bx[4], bx[5], "Concrete", bx[6] if len(bx) > 6 else "-z")


# ----------------------------------------------------------------------------------------------------------------
# Higher-level facade helpers
# ----------------------------------------------------------------------------------------------------------------
def bay_facade(S, u0, u1, z0, z1, nbays, rows, wall="WallA", fin_mat="TrimWhite", fin_w=0.5, fin_d=0.35, depth=0.15,
               glass="Window", frame=None, edges=None, fin_z1=None, skip_glass=(), wall_extra_holes=()):
    """Modern ribbon facade: wall (spandrels) with one glass bay per (bay,row) + protruding fins on the bay boundaries.
    rows = [(v0,v1),...]; edges = explicit bay boundary list (else nbays equal bays)."""
    if edges is None:
        edges = [u0 + (u1 - u0) * i / nbays for i in range(nbays + 1)]
    holes = []
    for i in range(len(edges) - 1):
        for ri, (v0, v1) in enumerate(rows):
            if (i, ri) in skip_glass:
                continue
            holes.append((edges[i], edges[i + 1], v0, v1))
    S.wall(u0, u1, z0, z1, holes + list(wall_extra_holes), wall)
    for h in holes:
        S.reveal(h, depth, frame or fin_mat, "t")
        S.q(h[0], h[1], h[2], h[3], -depth, glass)
    if fin_w > 0:
        for e in edges:
            S.box(e - fin_w / 2, e + fin_w / 2, z0, fin_z1 if fin_z1 is not None else z1, 0.0, fin_d, fin_mat, skip="ib")
    return holes


def parapet(b, x0, x1, y0, y1, z0, z1, t=0.3, mat="TrimWhite", sides="FBLR"):
    """Roof-edge parapet (outer face, inner face, top) along the chosen sides of the rectangle."""
    if "F" in sides:
        b.abox(x0, x1, y1 - t, y1, z0, z1, mat, "-z -x +x")
    if "B" in sides:
        b.abox(x0, x1, y0, y0 + t, z0, z1, mat, "-z -x +x")
    if "L" in sides:
        b.abox(x0, x0 + t, y0 + (t if "B" in sides else 0), y1 - (t if "F" in sides else 0), z0, z1, mat, "-z -y +y")
    if "R" in sides:
        b.abox(x1 - t, x1, y0 + (t if "B" in sides else 0), y1 - (t if "F" in sides else 0), z0, z1, mat, "-z -y +y")


def helipad(b, cx, cy, z, r=5.0, pad_mat="ConcreteDk", h_mat="TrimWhite", ring_mat="RailYellow", seg=16, lights=True):
    """Round roof helipad: raised disc, ring, H, perimeter lights. Returns the pad top z."""
    b.cyl((cx, cy, z + 0.14), r, 0.28, seg, pad_mat, caps="t")
    zt = z + 0.28
    b.annulus((cx, cy, zt + 0.01), r * 0.82, r * 0.88, seg, 1, ring_mat)
    s = r * 0.5
    for (px, py, sx, sy) in ((cx - s * 0.42, cy, s * 0.14, s * 1.15), (cx + s * 0.42, cy, s * 0.14, s * 1.15), (cx, cy, s * 0.86, s * 0.14)):
        b.zq(zt + 0.012, px - sx / 2, px + sx / 2, py - sy / 2, py + sy / 2, 1, h_mat)
    if lights:
        for k in range(8):
            a = k * math.pi / 4 + math.pi / 8
            b.cyl((cx + (r + 0.12) * math.cos(a), cy + (r + 0.12) * math.sin(a), z + 0.3), 0.1, 0.12, 4, "LightAmber", caps="t")
    return zt


def ac_unit(b, x, y, z, w=2.0, d=1.6, h=1.1):
    b.abox(x - w / 2, x + w / 2, y - d / 2, y + d / 2, z, z + h, "Metal", "-z")
    b.cyl((x - w * 0.18, y, z + h + 0.03), min(w, d) * 0.3, 0.06, 6, "MetalDark", caps="t")
    b.cyl((x + w * 0.2, y, z + h + 0.03), min(w, d) * 0.3, 0.06, 6, "MetalDark", caps="t")


def awning(b, x0, x1, y_wall, z_top, depth, drop, stripes, mat_a, mat_b, scallop=True, sides=True):
    """Sloped striped awning in front of a +Y facade: top edge at the wall (z_top), outer edge lower by `drop`, valance triangles."""
    n = stripes
    w = (x1 - x0) / n
    yo = y_wall + depth
    zo = z_top - drop
    for i in range(n):
        m = mat_a if i % 2 == 0 else mat_b
        xa, xb = x0 + i * w, x0 + (i + 1) * w
        b.pq([(xa, y_wall, z_top), (xb, y_wall, z_top), (xb, yo, zo), (xa, yo, zo)], (0, drop, depth), m)
        b.pq([(xa, y_wall, z_top - 0.02), (xb, y_wall, z_top - 0.02), (xb, yo, zo - 0.02), (xa, yo, zo - 0.02)], (0, -drop, -depth), m)
        if scallop:
            b.pq([(xa, yo, zo), (xb, yo, zo), ((xa + xb) / 2, yo, zo - 0.28)], (0, 1, 0), m)
        else:
            b.yq(yo, xa, xb, zo - 0.25, zo, 1, m)
    if sides:
        for xs, sg in ((x0, -1), (x1, 1)):
            b.pq([(xs, y_wall, z_top), (xs, yo, zo), (xs, y_wall, zo)], (sg, 0, 0), mat_a)


def mannequin(b, x, y, z=0.0, scale=1.0, shirt="AwningCoral", pants="PlumDk", facing=1):
    """Low-poly shop mannequin (~1.75 m * scale), base at z. facing=+1 looks towards +Y."""
    s = scale
    b.cyl((x, y, z + 0.02 * s), 0.28 * s, 0.04 * s, 8, "MetalDark", caps="t")
    b.beam((x, y - 0.0, z + 0.04 * s), (x, y, z + 0.9 * s), 0.025 * s, 0.025 * s, 4, "Metal", caps=False)
    for sx in (-0.1, 0.1):
        b.hip(x + sx * s - 0.075 * s, x + sx * s + 0.075 * s, y - 0.09 * s, y + 0.09 * s, z + 0.08 * s, 0.82 * s, 0.01 * s, 0.01 * s, pants, "-z")
    b.hip(x - 0.2 * s, x + 0.2 * s, y - 0.11 * s, y + 0.11 * s, z + 0.88 * s, 0.66 * s, -0.04 * s, -0.01 * s, shirt, "-z")
    for sx in (-1, 1):
        b.beam((x + sx * 0.25 * s, y, z + 1.5 * s), (x + sx * 0.33 * s, y + 0.04 * facing * s, z + 0.98 * s), 0.045 * s, 0.035 * s, 4, "Mannequin", caps=True)
    b.cyl((x, y, z + 1.57 * s), 0.05 * s, 0.1 * s, 5, "Mannequin", caps="")
    b.ball((x, y, z + 1.68 * s), 0.1 * s, 6, 3, "Mannequin", sc=(0.9, 1.0, 1.2))
