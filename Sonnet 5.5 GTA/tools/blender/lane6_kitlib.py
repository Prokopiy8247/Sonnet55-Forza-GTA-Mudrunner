"""
lane6_kitlib.py - Lane 6 (GTA_GODOT/Buildings) helper layer on top of gta_lib.py.
Load AFTER gta_lib (which must already be exec'd into globals()):
    exec(open(r"...\\tools\\blender\\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"...\\tools\\blender\\lane6_kitlib.py", encoding="utf8").read(), globals())

Facade-module coordinate system (Blender, metres):
    origin = bottom-centre of the FRONT plane, facade faces +Y, the 0.35 m slab sits behind (-Y),
    protrusions (sills, pilasters, cornices) go to +Y, window reveals go to -Y. Module is 4.0 m wide (x -2..2).
Every face is created with an explicit OUTWARD normal (pq) so open shells never come out inside-out
(gta_lib's MB.finish() recalculates normals which is unsafe for open shells, so KB.finish_k() does not).
"""
import bpy
import bmesh
import math
from mathutils import Vector

L6 = 6                      # lane number
BAY = 4.0
FH = 3.6
GH = 4.8
SLAB = 0.35
COLL_BUILDINGS = "GTA_GODOT/Buildings"
USER_PROMPT = "Build the Halcyon Bay Godot GTA game (Blender asset production)."

for _n in ("Window", "WallA", "WallB", "WallC", "WallD", "Roof", "RoofTile", "Trim", "Metal", "MetalDark", "Concrete",
           "Neon", "NeonCyan", "Glass", "Wood", "Accent", "LampGlow", "Leaf", "LightAmber", "LightRed", "Rock", "Plate"):
    std_mat(_n)
std_mat("SolarPanel", color="#1d3a63", rough=0.3, metal=0.4)
std_mat("BillboardFace", color="#e6e2d6", rough=0.7)
std_mat("Brick", color="#a4553f", rough=0.95)
std_mat("Asphalt", color="#2b2e33", rough=0.95)


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


class KB(MB):
    """MB + explicit-normal primitives for open facade shells."""

    # ---------- orientation-safe polygon ----------
    def pq(self, pts, n, mat="WallA"):
        p = [Vector(q) for q in pts]
        nn = Vector((0, 0, 0))
        for i in range(len(p)):
            a, b = p[i], p[(i + 1) % len(p)]
            nn.x += (a.y - b.y) * (a.z + b.z)
            nn.y += (a.z - b.z) * (a.x + b.x)
            nn.z += (a.x - b.x) * (a.y + b.y)
        if nn.dot(Vector(n)) < 0:
            p.reverse()
        return self.face([self.v(q) for q in p], mat)

    def xq(self, x, y0, y1, z0, z1, s, mat="WallA"):
        if abs(y1 - y0) < 1e-6 or abs(z1 - z0) < 1e-6:
            return None
        return self.pq([(x, y0, z0), (x, y1, z0), (x, y1, z1), (x, y0, z1)], (s, 0, 0), mat)

    def yq(self, y, x0, x1, z0, z1, s, mat="WallA"):
        if abs(x1 - x0) < 1e-6 or abs(z1 - z0) < 1e-6:
            return None
        return self.pq([(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], (0, s, 0), mat)

    def zq(self, z, x0, x1, y0, y1, s, mat="WallA"):
        if abs(x1 - x0) < 1e-6 or abs(y1 - y0) < 1e-6:
            return None
        return self.pq([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], (0, 0, s), mat)

    def abox(self, x0, x1, y0, y1, z0, z1, mat="WallA", skip=""):
        """Axis-aligned box by bounds. skip = space separated outward faces to omit, e.g. '-y -x +x'."""
        x0, x1 = min(x0, x1), max(x0, x1)
        y0, y1 = min(y0, y1), max(y0, y1)
        z0, z1 = min(z0, z1), max(z0, z1)
        sk = skip.split()
        if "+x" not in sk: self.xq(x1, y0, y1, z0, z1, 1, mat)
        if "-x" not in sk: self.xq(x0, y0, y1, z0, z1, -1, mat)
        if "+y" not in sk: self.yq(y1, x0, x1, z0, z1, 1, mat)
        if "-y" not in sk: self.yq(y0, x0, x1, z0, z1, -1, mat)
        if "+z" not in sk: self.zq(z1, x0, x1, y0, y1, 1, mat)
        if "-z" not in sk: self.zq(z0, x0, x1, y0, y1, -1, mat)

    # ---------- walls with rectangular holes ----------
    def wall_y(self, y, x0, x1, z0, z1, holes=(), mat="WallA", s=1):
        for r in rects_with_holes(x0, x1, z0, z1, holes):
            self.yq(y, r[0], r[1], r[2], r[3], s, mat)

    def wall_x(self, x, y0, y1, z0, z1, holes=(), mat="WallA", s=1):
        for r in rects_with_holes(y0, y1, z0, z1, holes):
            self.xq(x, r[0], r[1], r[2], r[3], s, mat)

    def reveal_y(self, hole, y_front, y_back, mat="WallA", sides="lrtb"):
        """Inner faces of a rectangular opening (x0,x1,z0,z1) in a wall plane facing +/-Y."""
        x0, x1, z0, z1 = hole
        ya, yb = min(y_front, y_back), max(y_front, y_back)
        if "l" in sides: self.xq(x0, ya, yb, z0, z1, 1, mat)
        if "r" in sides: self.xq(x1, ya, yb, z0, z1, -1, mat)
        if "b" in sides: self.zq(z0, x0, x1, ya, yb, 1, mat)
        if "t" in sides: self.zq(z1, x0, x1, ya, yb, -1, mat)

    def reveal_x(self, hole, x_front, x_back, mat="WallA", sides="lrtb"):
        """Inner faces of an opening (y0,y1,z0,z1) in a wall plane facing +/-X."""
        y0, y1, z0, z1 = hole
        xa, xb = min(x_front, x_back), max(x_front, x_back)
        if "l" in sides: self.yq(y0, xa, xb, z0, z1, 1, mat)
        if "r" in sides: self.yq(y1, xa, xb, z0, z1, -1, mat)
        if "b" in sides: self.zq(z0, xa, xb, y0, y1, 1, mat)
        if "t" in sides: self.zq(z1, xa, xb, y0, y1, -1, mat)

    def window_y(self, hole, depth=0.16, wall_mat="WallA", glass="Window", y=0.0, s=1):
        """Reveals + recessed glass for an opening already cut in a +Y (s=1) or -Y (s=-1) wall at plane y."""
        yb = y - s * depth
        self.reveal_y(hole, y, yb, wall_mat)
        self.yq(yb, hole[0], hole[1], hole[2], hole[3], s, glass)

    def window_x(self, hole, depth=0.16, wall_mat="WallA", glass="Window", x=0.0, s=1):
        xb = x - s * depth
        self.reveal_x(hole, x, xb, wall_mat)
        self.xq(xb, hole[0], hole[1], hole[2], hole[3], s, glass)

    # ---------- extruded profiles ----------
    def _prism(self, pts, lo, hi, axis, mat, caps=(True, True), skip_edges=(), mats=None):
        """Extrude a 2D polygon along axis ('x','y','z'). 2D coords (u,v) map: x->(y,z), y->(x,z), z->(x,y).
        Polygon may be given either way round (auto CCW). mats: dict edge->material (else mat)."""
        pts = [tuple(p) for p in pts]
        area = 0.0
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            area += a[0] * b[1] - b[0] * a[1]
        if area < 0:
            pts.reverse()
            # keep edge-index semantics for skip_edges/mats relative to the ORIGINAL order is not possible; document: give CCW
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
            m = (mats or {}).get(i, mat)
            if m is None:
                continue
            self.pq([p3(a[0], a[1], lo), p3(b[0], b[1], lo), p3(b[0], b[1], hi), p3(a[0], a[1], hi)], n3(dv, -du), m)
        ax = {"x": (1, 0, 0), "y": (0, 1, 0), "z": (0, 0, 1)}[axis]
        if caps[1]:
            self.pq([p3(p[0], p[1], hi) for p in pts], ax, mat)
        if caps[0]:
            self.pq([p3(p[0], p[1], lo) for p in pts], tuple(-c for c in ax), mat)

    def ex(self, prof_yz, x0, x1, mat="WallA", **kw):
        self._prism(prof_yz, min(x0, x1), max(x0, x1), "x", mat, **kw)

    def ey(self, prof_xz, y0, y1, mat="WallA", **kw):
        self._prism(prof_xz, min(y0, y1), max(y0, y1), "y", mat, **kw)

    def ez(self, prof_xy, z0, z1, mat="WallA", **kw):
        self._prism(prof_xy, min(z0, z1), max(z0, z1), "z", mat, **kw)

    # ---------- convex solids from MB with centroid-based orientation ----------
    def _orient_new(self, before):
        new = [f for f in self.bm.faces if f not in before]
        if not new:
            return
        c = Vector((0, 0, 0))
        n = 0
        for f in new:
            for vv in f.verts:
                c += vv.co
                n += 1
        c /= max(n, 1)
        for f in new:
            f.normal_update()
            if f.normal.dot(f.calc_center_median() - c) < 0:
                f.normal_flip()

    def cylk(self, *a, **k):
        before = set(self.bm.faces)
        r = MB.cyl(self, *a, **k)
        self._orient_new(before)
        return r

    def beamk(self, *a, **k):
        before = set(self.bm.faces)
        r = MB.beam(self, *a, **k)
        self._orient_new(before)
        return r

    def blockk(self, *a, **k):
        before = set(self.bm.faces)
        r = MB.block(self, *a, **k)
        self._orient_new(before)
        return r

    def spherek(self, *a, **k):
        before = set(self.bm.faces)
        r = MB.sphere(self, *a, **k)
        self._orient_new(before)
        return r

    def strip(self, x0, x1, z0, z1, y=0.012, mat="Trim"):
        """Thin dark panel-line strip lying on the facade (single quad facing +Y)."""
        return self.yq(y, x0, x1, z0, z1, 1, mat)

    # ---------- finish ----------
    def finish_k(self, collection=None, name=None, loc=(0, 0, 0), parent=None, smooth=None, weld=0.0004, uv="box"):
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
        if smooth is not None:
            try:
                me.shade_smooth()
                me.set_sharp_from_angle(angle=math.radians(smooth))
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
        if collection is not None and obj.name not in collection.objects:
            collection.objects.link(obj)
        if parent is not None:
            obj.parent = parent
        return obj


# ----------------------------------------------------------------------------------------------------------------
# Kit (one GLB family with many named module meshes laid out in the workshop)
# ----------------------------------------------------------------------------------------------------------------
class Kit:
    def __init__(self, fam, index, gap=2.0, spacing=100.0):
        self.fam = fam
        self.prefix = fam + "__"
        self.coll = coll(COLL_BUILDINGS)
        clear_asset(self.prefix)
        self.origin = workshop(L6, index, spacing)
        self.root = empty(self.prefix + "root", loc=self.origin, collection=self.coll)
        self.cursor = 0.0
        self.gap = gap
        self.mods = []
        self.index = index

    def add(self, name, fn, width=BAY, smooth=None):
        b = KB(self.prefix + name)
        fn(b)
        x = self.cursor + width / 2.0
        obj = b.finish_k(self.coll, self.prefix + name, loc=(x, 0, 0), parent=self.root, smooth=smooth)
        self.cursor += width + self.gap
        self.mods.append(obj)
        return obj

    def report(self, budget=400):
        bpy.context.view_layer.update()
        rows = []
        tot = 0
        for o in self.mods:
            me = o.data
            me.calc_loop_triangles()
            t = len(me.loop_triangles)
            tot += t
            xs = [v.co.x for v in me.vertices]
            ys = [v.co.y for v in me.vertices]
            zs = [v.co.z for v in me.vertices]
            bb = (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)) if xs else (0,) * 6
            flag = " OVER-BUDGET" if t > budget else ""
            rows.append("%-34s tris=%4d  x[%6.2f,%6.2f] y[%6.2f,%6.2f] z[%6.2f,%6.2f]%s" % ((o.name.split("__", 1)[1],) + (t,) + bb + (flag,)))
        print("\n".join(rows))
        print("TOTAL modules=%d tris=%d" % (len(self.mods), tot))

    def export(self, rel):
        """Export with every module at identity (origin = module origin), restore the workshop layout afterwards."""
        saved = [(o, o.location.copy()) for o in self.mods]
        try:
            for o in self.mods:
                o.location = Vector((0, 0, 0))
            bpy.context.view_layer.update()
            p = export_glb(self.root, rel)
        finally:
            for o, loc in saved:
                o.location = loc
            bpy.context.view_layer.update()
        return p


def check_open_edges(obj, max_report=3):
    """Debug helper: count boundary edges (open shells are normal for facade modules) and tiny/degenerate faces."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bad = sum(1 for f in bm.faces if f.calc_area() < 1e-7)
    bnd = sum(1 for e in bm.edges if e.is_boundary)
    nm = sum(1 for e in bm.edges if not e.is_manifold and not e.is_boundary)
    bm.free()
    return dict(degenerate=bad, boundary_edges=bnd, nonmanifold=nm)


# ----------------------------------------------------------------------------------------------------------------
# Test assembly (validates joins). Footprint x[-W*2, W*2], y[-D*4, 0]; faces walk clockwise, one chiral corner module.
# ----------------------------------------------------------------------------------------------------------------
def assemble_block(prefix, slot, W, D, ground, upper, floors, ground_h, floor_h, cornice=None, cornice_corner=None,
                   cornice_h=0.0, extra=None):
    """ground(face,i,corner)->object name | None ; upper(face,i,f,corner)->name ; extra(put, W, D, top_z) optional."""
    clear_asset(prefix)
    cl = coll(COLL_BUILDINGS)
    root = empty(prefix + "root", loc=workshop(L6, slot, 100.0), collection=cl)
    cnt = [0]

    def put(src_name, x, y, z, rotz):
        src = bpy.data.objects[src_name]
        cnt[0] += 1
        o = bpy.data.objects.new(prefix + "%03d" % cnt[0], src.data)
        o.location = Vector((x, y, z))
        o.rotation_euler = (0, 0, math.radians(rotz))
        cl.objects.link(o)
        o.parent = root
        return o

    hw, hd = W * 2.0, D * 4.0

    def face_pos(face, i):
        if face == 0: return (-hw + 2 + 4 * i, 0.0, 0)
        if face == 1: return (hw, -2 - 4 * i, -90)
        if face == 2: return (hw - 2 - 4 * i, -hd, 180)
        return (-hw, -hd + 2 + 4 * i, 90)

    top = ground_h + floors * floor_h
    for face in range(4):
        n = W if face in (0, 2) else D
        for i in range(n):
            x, y, r = face_pos(face, i)
            corner = (i == n - 1)
            g = ground(face, i, corner)
            if g:
                put(g, x, y, 0.0, r)
            zf = ground_h
            for f in range(floors):
                m = upper(face, i, f, corner)
                if m:
                    put(m, x, y, zf, r)
                zf += floor_h
            cm = (cornice_corner if corner and cornice_corner else cornice)
            if cm:
                put(cm, x, y, top, r)
    if extra:
        extra(put, W, D, top + cornice_h)
    print("assembled", cnt[0], "pieces ->", prefix + "root")
    return root
