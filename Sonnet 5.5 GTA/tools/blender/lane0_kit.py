r"""
lane0_kit.py - car building kit for Blender lane 0 (GTA_GODOT/Vehicles/Cars): sedan, compact, sports, muscle.
exec AFTER gta_lib.py in the same globals():
    exec(open(r"...\tools\blender\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"...\tools\blender\lane0_kit.py", encoding="utf8").read(), globals())
All top-level names are prefixed l0_ / L0 because the Blender exec namespace is shared with other agents.

Coordinates (Blender): +Y forward, +X right, +Z up. Origin = ground point at the wheelbase centre. Driver on the LEFT (-X).

Body = lofted lower body (12-point rings, arches cut through the loft) + separate greenhouse (window grid panels).
All faces carry explicit winding (no normal recalculation), see L0B.finish2.

REBUILD / EXPORT (each script is idempotent: it starts with clear_asset(prefix) and builds <id>__root + <id>_lod__root):
    for cid in ("sedan", "compact", "sports", "muscle"):
        exec(open(r"...	oolslender\lane0_%s.py" % cid, encoding="utf8").read(), globals())
        export_glb(bpy.data.objects[cid + "__root"], "vehicles/" + cid)               # full model (Body, doors, wheels, anchors)
        export_glb(bpy.data.objects[cid + "_lod__root"], "vehicles/" + cid + "_lod")   # coarse Body only (separate file on purpose)
    save_master()
Doors: DoorL/DoorR (+DoorRearL/DoorRearR on the sedan) are hinged meshes, origin = hinge at the FRONT edge of the door; the Body has a
matching 4 cm pocket (shut gap 4 mm) so they sit flush. Open outward: right door +Y rotation, left door -Y rotation (Godot), i.e. Blender
rotation_euler.z = +angle (right) / -angle (left).
"""
import math
import bmesh
import bpy
from mathutils import Vector

L0_COLL = "GTA_GODOT/Vehicles/Cars"
L0_ROLE = ["chamfer", "bump", "side", "shoulder", "bevel", "top", "bevel", "shoulder", "side", "bump", "chamfer", "bottom"]
# ring point order: 0 R0, 1 R1, 2 R1b, 3 R2, 4 R3, 5 R4, 6 L4, 7 L3, 8 L2, 9 L1b, 10 L1, 11 L0 ; segment i = point i -> i+1


def l0_pw(pts, y):
    """piecewise-linear interpolation of [(y, value), ...] (sorted); clamps outside."""
    if y <= pts[0][0]:
        return pts[0][1]
    if y >= pts[-1][0]:
        return pts[-1][1]
    for i in range(len(pts) - 1):
        y0, v0 = pts[i]
        y1, v1 = pts[i + 1]
        if y0 <= y <= y1:
            if y1 - y0 < 1e-9:
                return v1
            return v0 + (v1 - v0) * (y - y0) / (y1 - y0)
    return pts[-1][1]


def l0_newell(p):
    n = Vector((0, 0, 0))
    for i in range(len(p)):
        a = p[i]
        c = p[(i + 1) % len(p)]
        n.x += (a.y - c.y) * (a.z + c.z)
        n.y += (a.z - c.z) * (a.x + c.x)
        n.z += (a.x - c.x) * (a.y + c.y)
    return n


class L0B(MB):
    """MB + oriented-face helpers + finish without normal recalculation."""

    def fo(self, pts, mat, out):
        """polygon whose normal is flipped (if needed) to point along `out`."""
        p = [Vector(q) for q in pts]
        if l0_newell(p).dot(Vector(out)) < 0:
            p.reverse()
        return self.face([self.v(q) for q in p], mat)

    def box6(self, x0, x1, y0, y1, z0, z1, mat="Paint"):
        return self.block(((x0 + x1) / 2, (y0 + y1) / 2), z0, z1, (abs(x1 - x0), abs(y1 - y0)), None, mat)

    def slab(self, quad, t, mat, out, mat_edge=None):
        """closed thin slab: front quad (oriented to `out`) pushed `t` inwards."""
        p = [Vector(q) for q in quad]
        if l0_newell(p).dot(Vector(out)) < 0:
            p.reverse()
        n = l0_newell(p).normalized()
        q = [x - n * t for x in p]
        self.face([self.v(x) for x in p], mat)
        self.face([self.v(x) for x in reversed(q)], mat_edge or mat)
        for i in range(len(p)):
            j = (i + 1) % len(p)
            self.face([self.v(q[i]), self.v(q[j]), self.v(p[j]), self.v(p[i])], mat_edge or mat)

    def finish2(self, collection=None, name=None, weld=0.0004, smooth_angle_deg=None):
        bm = self.bm
        if weld:
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=weld)
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
        collection = collection or bpy.context.scene.collection
        if obj.name not in collection.objects:
            collection.objects.link(obj)
        return obj


def l0_grid(b, A, B, C, D, ucuts, vcuts, matf, out):
    """bilinear panel A(u0,v0) B(u1,v0) C(u1,v1) D(u0,v1) cut into cells; matf(iu, iv) -> material name or None."""
    A, B, C, D = Vector(A), Vector(B), Vector(C), Vector(D)

    def P(u, v):
        return (A * (1 - u) + B * u) * (1 - v) + (D * (1 - u) + C * u) * v

    for iu in range(len(ucuts) - 1):
        for iv in range(len(vcuts) - 1):
            u0, u1, v0, v1 = ucuts[iu], ucuts[iu + 1], vcuts[iv], vcuts[iv + 1]
            m = matf(iu, iv)
            if m:
                b.fo([P(u0, v0), P(u1, v0), P(u1, v1), P(u0, v1)], m, out)


class L0Car:
    """Parametric lofted car body. spec keys: rows, arches, gh, mats, c1, k0, ins3, shoulder_h, trough, yf, yr."""

    def __init__(self, spec):
        self.s = spec
        rows = sorted(spec["rows"], key=lambda r: r[0])
        keys = ("zb", "w", "zbelt", "zd", "ins4", "zbump")
        self.cols = {k: [(r[0], r[i + 1]) for r in rows] for i, k in enumerate(keys)}
        ys = [r[0] for r in rows]
        self.gap = spec.get("door_gap", 0.004)
        self.rec = spec.get("rec", 0.04)
        for d in spec.get("doors", []):
            for yy in (d["y0"] + self.gap, d["y0"] + self.gap + 0.0015, d["y1"] - self.gap, d["y1"] - self.gap - 0.0015):
                ys.append(yy)
        for (yc, zc, Ra, fl) in spec["arches"]:
            for th in (0, 30, 60, 90, 120, 150, 180):
                ys.append(yc - Ra * math.cos(math.radians(th)))
            for e in (Ra + 0.012, -(Ra + 0.012)):
                ys.append(yc + e)
            if fl > 0:
                ys.extend([yc + Ra + 0.2, yc - Ra - 0.2])
        ys = sorted(ys)
        st = []
        for y in ys:
            if not st or y - st[-1] > 1e-4:
                st.append(y)
        lo, hi = rows[0][0], rows[-1][0]
        self.stations = [y for y in st if lo - 1e-6 <= y <= hi + 1e-6]
        self.rings = [self.ring(y) for y in self.stations]

    # ---- ring at an arbitrary station
    def rec_at(self, y):
        for d in self.s.get("doors", []):
            if d["y1"] - self.gap - 1e-9 <= y <= d["y0"] + self.gap + 1e-9:
                return self.rec
        return 0.0

    def ring(self, y, norec=False):
        s, c = self.s, self.cols
        zb = l0_pw(c["zb"], y)
        w = l0_pw(c["w"], y)
        zbelt = l0_pw(c["zbelt"], y)
        zd = l0_pw(c["zd"], y)
        ins4 = l0_pw(c["ins4"], y)
        zbump = l0_pw(c["zbump"], y)
        zbe = zb
        flare = 0.0
        for (yc, zc, Ra, fl) in s["arches"]:
            d = abs(y - yc)
            if d <= Ra + 1e-9:
                zbe = max(zbe, zc + math.sqrt(max(Ra * Ra - d * d, 0.0)))
            if fl > 0:
                if d <= Ra * 0.88:
                    f = 1.0
                elif d < Ra + 0.2:
                    f = 1.0 - (d - Ra * 0.88) / (Ra + 0.2 - Ra * 0.88)
                else:
                    f = 0.0
                flare = max(flare, fl * f)
        w += flare
        c1, k0, ins3, sh = s.get("c1", 0.08), s.get("k0", 0.10), s.get("ins3", 0.045), s.get("shoulder_h", 0.11)
        zsh = max(zbelt - sh, zbe + 0.05)
        zbelt = max(zbelt, zsh + 0.01)
        r1z = min(zbe + c1, max(zbe, zsh - 0.03))
        r1bz = max(r1z, min(zbump, zsh - 0.02))
        rec = 0.0 if norec else self.rec_at(y)
        R = [Vector((w - k0, y, zbe)), Vector((w, y, r1z)), Vector((w - rec, y, r1bz)), Vector((w - rec, y, zsh)),
             Vector((w - ins3, y, zbelt)), Vector((w - ins3 - ins4, y, zd))]
        Lf = [Vector((-p.x, p.y, p.z)) for p in reversed(R)]
        return R + Lf

    def check(self):
        bad = []
        for y, r in zip(self.stations, self.rings):
            z = [r[i].z for i in range(5)]
            if any(z[i + 1] < z[i] - 1e-6 for i in range(4)) or r[4].x < r[5].x:
                bad.append(round(y, 3))
        return bad

    def ring_at(self, y):
        st = self.stations
        if y <= st[0]:
            return [Vector(p) for p in self.rings[0]]
        if y >= st[-1]:
            return [Vector(p) for p in self.rings[-1]]
        for k in range(len(st) - 1):
            if st[k] <= y <= st[k + 1]:
                t = (y - st[k]) / (st[k + 1] - st[k])
                return [self.rings[k][i].lerp(self.rings[k + 1][i], t) for i in range(12)]

    def half_width_at(self, y, z):
        """outer surface half width x of the lower body at (y,z) (right side)."""
        r = self.ring_at(y)
        pts = [r[0], r[1], r[2], r[3], r[4], r[5]]
        for i in range(5):
            a, b = pts[i], pts[i + 1]
            if min(a.z, b.z) - 1e-6 <= z <= max(a.z, b.z) + 1e-6 and abs(b.z - a.z) > 1e-6:
                t = (z - a.z) / (b.z - a.z)
                return a.x + (b.x - a.x) * t
        return pts[3].x

    # ---- lower body loft
    def build_body(self, b):
        s = self.s
        mats = s["mats"]
        trough = s.get("trough")
        V = [[b.v(p) for p in ring] for ring in self.rings]
        n = 12
        for k in range(len(V) - 1):
            ymid = (self.stations[k] + self.stations[k + 1]) / 2
            in_trough = bool(trough) and trough[0] <= ymid <= trough[1]
            for i in range(n):
                j = (i + 1) % n
                role = L0_ROLE[i]
                if role == "bump":
                    d0 = (self.rings[k][i] - self.rings[k][j]).length
                    d1 = (self.rings[k + 1][i] - self.rings[k + 1][j]).length
                    if max(d0, d1) < 1e-4:
                        continue
                m = mats[role]
                if in_trough and role in ("bevel", "top"):
                    m = "Interior"
                if role in ("bump", "side", "shoulder") and (self.rec_at(self.stations[k]) > 0 or self.rec_at(self.stations[k + 1]) > 0):
                    m = "Interior"
                b.face([V[k][i], V[k + 1][i], V[k + 1][j], V[k][j]], m)
        # caps: lower (bumper) polygon + upper polygon
        for (idx, yy, hint) in ((0, self.stations[0], (0, -1, 0)), (-1, self.stations[-1], (0, 1, 0))):
            ring = self.rings[idx]
            lo = [ring[i] for i in (0, 1, 2, 9, 10, 11)]
            hi = [ring[i] for i in (2, 3, 4, 5, 6, 7, 8, 9)]
            b.fo(lo, mats["cap_lo"], hint)
            b.fo(hi, mats["cap_hi"], hint)

    # ---- greenhouse
    def build_greenhouse(self, b):
        g = self.s["gh"]
        rf = self.ring(g["yfb"], norec=True)[4]
        rr = self.ring(g["yrb"], norec=True)[4]
        zr = g["zr"]
        wrf, wrr = g["wrf"], g["wrr"]
        yfr, yrr = g["yfr"], g["yrr"]
        pm, rm = g.get("pillar_mat", "Paint"), g.get("roof_mat", "Paint")
        # windshield
        wu = g.get("ws_u", [0, 0.055, 0.945, 1.0])
        wv = g.get("ws_v", [0, 0.05, 0.88, 1.0])
        A, B = Vector((-rf.x, g["yfb"], rf.z)), Vector((rf.x, g["yfb"], rf.z))
        C, D = Vector((wrf, yfr, zr)), Vector((-wrf, yfr, zr))
        l0_grid(b, A, B, C, D, wu, wv, lambda iu, iv: "Glass" if (iu == 1 and iv == 1) else pm, (0, 1, 0.7))
        # rear window
        ru = g.get("rw_u", [0, 0.07, 0.93, 1.0])
        rv = g.get("rw_v", [0, 0.06, 0.85, 1.0])
        A, B = Vector((rr.x, g["yrb"], rr.z)), Vector((-rr.x, g["yrb"], rr.z))
        C, D = Vector((-wrr, yrr, zr)), Vector((wrr, yrr, zr))
        l0_grid(b, A, B, C, D, ru, rv, lambda iu, iv: "Glass" if (iu == 1 and iv == 1) else pm, (0, -1, 0.7))
        # roof
        b.fo([Vector((-wrf, yfr, zr)), Vector((wrf, yfr, zr)), Vector((wrr, yrr, zr)), Vector((-wrr, yrr, zr))], rm, (0, 0, 1))
        # sides (door cells are built into the door meshes)
        skip = set()
        for d in self.s.get("doors", []):
            skip.update(d["cells"])
        allc = set(range(len(self.side_u()) - 1))
        for sx in (1, -1):
            self.side_cells(b, sx, sorted(allc - skip))

    def side_u(self):
        g = self.s["gh"]
        if "side_y" in g:
            d = g["yfb"] - g["yrb"]
            return [0.0] + [(g["yfb"] - y) / d for y in g["side_y"]] + [1.0]
        return g["side_u"]

    def side_cells(self, b, sx, ius):
        g = self.s["gh"]
        rf = self.ring(g["yfb"], norec=True)[4]
        rr = self.ring(g["yrb"], norec=True)[4]
        zr = g["zr"]
        A = Vector((sx * rf.x, g["yfb"], rf.z))
        B = Vector((sx * rr.x, g["yrb"], rr.z))
        C = Vector((sx * g["wrr"], g["yrr"], zr))
        D = Vector((sx * g["wrf"], g["yfr"], zr))
        su = self.side_u()
        sv = g.get("side_v", [0, 0.10, 0.90, 1.0])
        wins = g["win_cells"]
        pm = g.get("pillar_mat", "Paint")
        pmats = g.get("pillar_mats", {})

        def matf(iu, iv):
            if iu not in ius:
                return None
            if iv == 1 and iu in wins:
                return "Glass"
            if iv == 1:
                return pmats.get(iu, pm)
            return pm
        l0_grid(b, A, B, C, D, su, sv, matf, (sx, 0, 0.2))

    def side_point(self, y, idx, off=0.0, sx=1):
        p = self.ring_at(y)[idx]
        return Vector((sx * (p.x + off), p.y, p.z))


# ----------------------------------------------------------------------------------------------------------------
# decals / details
# ----------------------------------------------------------------------------------------------------------------
def l0_strip_side(car, b, y0, y1, i0, i1, off, mat, sx=1, zmin=None, zmax=None):
    """thin vertical strip following ring points i0..i1 (right side indices 0..5) between y0 and y1, offset outwards."""
    r0, r1 = car.ring_at(y0), car.ring_at(y1)

    def pts(r):
        out = []
        for i in range(i0, i1 + 1):
            p = r[i]
            out.append(Vector((sx * (p.x + off), p.y, p.z)))
        return out
    P0, P1 = pts(r0), pts(r1)
    for i in range(len(P0) - 1):
        a, c = P0[i], P0[i + 1]
        if zmin is not None and c.z < zmin:
            continue
        b.fo([a, c, P1[i + 1], P1[i]], mat, (sx, 0, 0.1))


def l0_side_quad(car, b, y0, y1, z0, z1, off, mat, sx=1, hint=None):
    """flat quad on the near-vertical side wall between heights z0..z1 (uses the actual surface x at those heights)."""
    pts = []
    for (y, z) in ((y0, z0), (y1, z0), (y1, z1), (y0, z1)):
        x = car.half_width_at(y, z) + off
        pts.append(Vector((sx * x, y, z)))
    b.fo(pts, mat, hint or (sx, 0, 0.1))


def l0_wheel(name, r, width, side, coll, x, y, z, seg=14, tire="Tire", rim="Rim", hub="Chrome", parent=None):
    """Wheel: spin axis X, origin = centre, rim face toward +X when side=+1 / -X when side=-1 (geometry mirrored, node rotation identity)."""
    b = L0B(name)
    hw = width / 2.0
    ph = 0.0 if seg % 4 == 0 else 0.5   # a vertex exactly at the bottom (tyre touches Z=0)
    prof = [(-hw, r * 0.76), (-hw + 0.022, r * 0.94), (-hw + 0.06, r), (hw - 0.06, r), (hw - 0.022, r * 0.94), (hw, r * 0.80)]
    rings = []
    for (px, rr) in prof:
        ring = []
        for i in range(seg):
            a = 2 * math.pi * (i + ph) / seg
            ring.append(Vector((side * px, rr * math.cos(a), rr * math.sin(a))))
        rings.append(ring)
    V = [[b.v(p) for p in ring] for ring in rings]
    flip = side < 0
    for k in range(len(V) - 1):
        for i in range(seg):
            j = (i + 1) % seg
            q = [V[k][i], V[k][j], V[k + 1][j], V[k + 1][i]]
            b.face(q[::-1] if flip else q, tire)
    # rim lip + dark disc + star + hub on the outer face
    xo = side * hw
    xd = side * (hw - 0.045)
    lip_o = [Vector((xo, r * 0.80 * math.cos(2 * math.pi * (i + ph) / seg), r * 0.80 * math.sin(2 * math.pi * (i + ph) / seg))) for i in range(seg)]
    lip_i = [Vector((xd, r * 0.60 * math.cos(2 * math.pi * (i + ph) / seg), r * 0.60 * math.sin(2 * math.pi * (i + ph) / seg))) for i in range(seg)]
    for i in range(seg):
        j = (i + 1) % seg
        b.fo([lip_o[i], lip_o[j], lip_i[j], lip_i[i]], rim, (side, 0, 0))
    b.fo(lip_i, tire, (side, 0, 0))
    star = []
    n5 = 5
    for i in range(n5 * 2):
        a = 2 * math.pi * i / (n5 * 2) + 0.1
        rr = r * (0.57 if i % 2 == 0 else 0.22)
        star.append(Vector((xd + side * 0.006, rr * math.cos(a), rr * math.sin(a))))
    b.fo(star, rim, (side, 0, 0))
    b.cyl((xd + side * 0.02, 0, 0), r * 0.15, 0.04, 6, hub, axis="X")
    obj = b.finish2(coll, name, smooth_angle_deg=40)
    obj.location = Vector((x, y, z))
    if parent is not None:
        parent_to(obj, parent)
    return obj


def l0_steering_wheel(b, center, radius=0.17, tilt_deg=28, mat="Interior", hub_mat="Trim"):
    """octagonal steering wheel ring (annulus with thickness) facing the driver; tilt about X (top leans forward)."""
    seg = 8
    ro, ri = radius, radius * 0.80
    th = 0.03
    c = Vector(center)
    ang = math.radians(tilt_deg)
    ca, sa = math.cos(ang), math.sin(ang)

    def T(x, yy, zz):
        # local plane = XZ (normal -Y toward driver), then pitch about X so that the wheel face tilts up/back
        y2 = yy * ca + zz * sa
        z2 = -yy * sa + zz * ca
        return c + Vector((x, y2, z2))
    outer, inner = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        outer.append((ro * math.cos(a), ro * math.sin(a)))
        inner.append((ri * math.cos(a), ri * math.sin(a)))
    hint = Vector((0, -ca, sa))   # face direction toward the driver
    for i in range(seg):
        j = (i + 1) % seg
        # front face of rim (toward driver, local -y) : plane y = -th/2
        b.fo([T(outer[i][0], -th / 2, outer[i][1]), T(outer[j][0], -th / 2, outer[j][1]), T(inner[j][0], -th / 2, inner[j][1]), T(inner[i][0], -th / 2, inner[i][1])], mat, hint)
        b.fo([T(outer[i][0], th / 2, outer[i][1]), T(outer[j][0], th / 2, outer[j][1]), T(inner[j][0], th / 2, inner[j][1]), T(inner[i][0], th / 2, inner[i][1])], mat, -hint)
        # outer wall
        b.fo([T(outer[i][0], -th / 2, outer[i][1]), T(outer[j][0], -th / 2, outer[j][1]), T(outer[j][0], th / 2, outer[j][1]), T(outer[i][0], th / 2, outer[i][1])], mat,
             (T(outer[i][0], 0, outer[i][1]) + T(outer[j][0], 0, outer[j][1]) - 2 * c))
    # hub + two spokes
    hub = []
    for i in range(6):
        a = 2 * math.pi * i / 6
        hub.append(T(0.05 * math.cos(a), -th / 2 - 0.012, 0.05 * math.sin(a)))
    b.fo(hub, hub_mat, hint)
    for sgn in (1, -1):
        b.fo([T(sgn * 0.04, -th / 2 - 0.005, 0.02), T(sgn * ri, -th / 2 - 0.005, 0.02), T(sgn * ri, -th / 2 - 0.005, -0.02), T(sgn * 0.04, -th / 2 - 0.005, -0.02)], hub_mat, hint)


def l0_seat(b, x, y, z_floor, w=0.46, depth=0.50, back_h=0.52, mat="Interior", head=True, lean=0.10, cush_h=0.09):
    """car seat: cushion + leaning backrest (+ headrest). y = seat centre (backrest at y - depth/2)."""
    b.block((x, y), z_floor, z_floor + cush_h, (w, depth), (w - 0.04, depth - 0.04), mat)
    yb = y - depth / 2 + 0.05
    b.block((x, yb), z_floor + cush_h * 0.8, z_floor + back_h, (w, 0.13), (w - 0.06, 0.10), mat, top_shift=(0, -lean))
    if head:
        b.block((x, yb - lean), z_floor + back_h, z_floor + back_h + 0.13, (0.20, 0.09), (0.18, 0.08), mat)


def l0_add_empties(root, coll, specs):
    out = {}
    for nm, loc in specs.items():
        out[nm] = empty(root.name.replace("__root", "") + "__" + nm, loc=loc, parent=root, collection=coll)
    return out


def l0_door(car, root, coll, name, sx, d, extra=None):
    """Hinged door mesh (origin at the hinge = front edge of the door, on the body side). d: dict(y0,y1,cells,zh,handle=(ya,yb,z0,z1))."""
    t = car.rec
    b = L0B(name)
    y0, y1 = d["y0"], d["y1"]
    r0, r1 = car.ring(y0, norec=True), car.ring(y1, norec=True)
    idx = (2, 3, 4)
    O0 = [Vector((sx * r0[i].x, y0, r0[i].z)) for i in idx]
    O1 = [Vector((sx * r1[i].x, y1, r1[i].z)) for i in idx]
    I0 = [Vector((sx * (r0[i].x - t), y0, r0[i].z)) for i in idx]
    I1 = [Vector((sx * (r1[i].x - t), y1, r1[i].z)) for i in idx]
    for k in range(2):
        b.fo([O0[k], O0[k + 1], O1[k + 1], O1[k]], d.get("mat", "Paint"), (sx, 0, 0.1))
        b.fo([I0[k], I0[k + 1], I1[k + 1], I1[k]], "Interior", (-sx, 0, 0))
    b.fo([O0[0], O1[0], I1[0], I0[0]], "Interior", (0, 0, -1))
    b.fo([O0[0], O0[1], O0[2], I0[2], I0[1], I0[0]], "Interior", (0, 1, 0))
    b.fo([O1[0], O1[1], O1[2], I1[2], I1[1], I1[0]], "Interior", (0, -1, 0))
    car.side_cells(b, sx, d["cells"])
    if d.get("handle"):
        ya, yb, z0, z1 = d["handle"]
        xs = car.half_width_at((ya + yb) / 2, (z0 + z1) / 2) if False else r0[3].x
        b.box6(sx * (xs - 0.008), sx * (xs + 0.024), ya, yb, z0, z1, "Chrome")
    if extra:
        extra(b, sx)
    hinge = Vector((sx * r0[3].x, y0, d.get("zh", 0.60)))
    b.translate(-hinge)
    obj = b.finish2(coll, name)
    obj.location = hinge
    parent_to(obj, root)
    return obj


# ----------------------------------------------------------------------------------------------------------------
# LOD body (<= 25% of Body tris) exported as its OWN file vehicles/<id>_lod.glb (node 'Body') - it must never be a child of the car root,
# because it would show through the wheel arches / windows of the full model
# ----------------------------------------------------------------------------------------------------------------
def l0_lod_spec(spec):
    s = dict(spec)
    rows = []
    for r in sorted(spec["rows"], key=lambda r: r[0]):
        y, zb, w, zbelt, zd, ins4, zbump = r
        if zd < zbelt - 0.1:
            zd, ins4 = zbelt, 0.30
        rows.append((y, zb, w, zbelt, zd, ins4, 0.0))
    out = []
    for r in rows:
        if out and r[0] - out[-1][0] < 0.12 and r is not rows[-1]:
            continue
        out.append(r)
    if out[-1] is not rows[-1]:
        out[-1] = rows[-1]
    s.update(rows=out, arches=[], doors=[], trough=None, ins3=spec.get("ins3", 0.045))
    return s


def l0_build_lod(car, root, coll, name):
    spec = l0_lod_spec(car.s)
    lc = L0Car(spec)
    b = L0B(name)
    lc.build_body(b)
    g = spec["gh"]
    rf = lc.ring(g["yfb"], norec=True)[4]
    rr = lc.ring(g["yrb"], norec=True)[4]
    zr = g["zr"]
    wrf, wrr = g["wrf"], g["wrr"]
    yfr, yrr = g["yfr"], g["yrr"]
    rm = g.get("roof_mat", "Paint")
    b.fo([Vector((-rf.x, g["yfb"], rf.z)), Vector((rf.x, g["yfb"], rf.z)), Vector((wrf, yfr, zr)), Vector((-wrf, yfr, zr))], "Glass", (0, 1, 0.7))
    b.fo([Vector((rr.x, g["yrb"], rr.z)), Vector((-rr.x, g["yrb"], rr.z)), Vector((-wrr, yrr, zr)), Vector((wrr, yrr, zr))], "Glass", (0, -1, 0.7))
    b.fo([Vector((-wrf, yfr, zr)), Vector((wrf, yfr, zr)), Vector((wrr, yrr, zr)), Vector((-wrr, yrr, zr))], rm, (0, 0, 1))
    for sx in (1, -1):
        A = Vector((sx * rf.x, g["yfb"], rf.z))
        B = Vector((sx * rr.x, g["yrb"], rr.z))
        C = Vector((sx * wrr, yrr, zr))
        D = Vector((sx * wrf, yfr, zr))
        l0_grid(b, A, B, C, D, [0, 1], [0, 0.10, 0.90, 1.0], lambda iu, iv: "Glass" if iv == 1 else g.get("pillar_mat", "Paint"), (sx, 0, 0.2))
    # dark wheel-arch patches on the flanks
    for (yc, zc, Ra, fl) in car.s["arches"]:
        for sx in (1, -1):
            pts = []
            for k in range(7):
                th = math.pi * k / 6.0
                y = yc - Ra * math.cos(th)
                z = zc + Ra * math.sin(th)
                x = lc.half_width_at(y, min(z, lc.ring_at(y)[3].z - 0.01))
                pts.append(Vector((sx * (x + 0.004), y, z)))
            zlow = lc.ring_at(yc)[1].z
            pts.insert(0, Vector((pts[0].x, yc - Ra, zlow)))
            pts.append(Vector((pts[-1].x, yc + Ra, zlow)))
            b.fo(pts, "Trim", (sx, 0, 0.1))
    obj = b.finish2(coll, name)
    parent_to(obj, root)
    return obj
