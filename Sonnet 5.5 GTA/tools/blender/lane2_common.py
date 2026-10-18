"""
lane2_common.py - toolkit for Blender lane 2 (GTA_GODOT/Vehicles/Cars + Vehicles/Motorcycles):
motorcycle, bicycle, ambulance, truck, firetruck, police_tactical.  Load AFTER gta_lib.py:

    exec(open(r"...\\tools\\blender\\lane2_common.py", encoding="utf8").read(), globals())

All names are prefixed l2_ / L2 so they never clash with other lanes sharing the live Blender session.
Metres, +Y forward, origin = ground point at wheelbase centre, driver on the LEFT (-X).
Body meshes are built WITHOUT welding (every shell keeps its own verts) - finish() recalculates normals per closed shell.
Every asset gets local per-asset Paint/Paint2 materials ("<id>__Paint") that are swapped to the shared names at export only.
"""
import math
from mathutils import Vector


def l2_lerp(a, b, t):
    return a + (b - a) * t


def l2_clamp(v, a, b):
    return max(a, min(b, v))


# --------------------------------------------------------------------------------------------------------------
# asset wrapper
# --------------------------------------------------------------------------------------------------------------
class L2Asset:
    def __init__(self, aid, index, collection="GTA_GODOT/Vehicles/Cars", paint="#f2f0ea", paint2="#d93a3a", spacing=14.0):
        self.id = aid
        self.prefix = aid + "__"
        clear_asset(self.prefix)
        clear_asset(aid + "_lod__")
        self.coll = coll(collection)
        self.origin = workshop(2, index, spacing)
        self.root = empty(self.prefix + "root", tuple(self.origin), collection=self.coll, display="ARROWS", size=0.5)
        self.paint = paint
        self.paint2 = paint2
        self.objs = {}
        self.lod_root = None
        for n in ("Paint", "Paint2", "Glass", "Trim", "Chrome", "LightHead", "LightTail", "LightAmber", "LightBlue", "LightRed",
                  "Interior", "Plate", "Tire", "Rim", "Metal", "MetalDark", "LampGlow"):
            std_mat(n)
        # fixed-colour livery materials: Godot repaints "Paint"/"Paint2" at runtime (Paint2 defaults to DARK), these keep their colour
        std_mat("LiveryRed", color="#d93a3a", rough=0.45, metal=0.1)
        std_mat("LiveryWhite", color="#ece9e0", rough=0.5, metal=0.05)

    def local_paint(self):
        for base, col in (("Paint", self.paint), ("Paint2", self.paint2)):
            spec = dict(STD[base])
            spec["color"] = col
            mat(self.prefix + base, **spec)

    def mats(self):
        """swap shared Paint/Paint2 slot materials of all my meshes to the local per-asset ones"""
        self.local_paint()
        for o in descendants(self.root):
            if o.type != "MESH":
                continue
            for i, m in enumerate(o.data.materials):
                if m is not None and m.name in ("Paint", "Paint2"):
                    o.data.materials[i] = bpy.data.materials[self.prefix + m.name]

    def mesh(self, mb, node, loc=(0, 0, 0), parent=None, smooth=None, weld=0.0):
        obj = mb.finish(self.coll, self.prefix + node, loc=loc, smooth_angle_deg=smooth, weld=weld)
        parent_to(obj, parent or self.root)
        self.objs[node] = obj
        return obj

    def node(self, name, loc, parent=None, size=0.12, display="PLAIN_AXES"):
        o = empty(self.prefix + name, loc=loc, parent=parent or self.root, collection=self.coll, size=size, display=display)
        self.objs[name] = o
        return o

    def export(self, rel=None):
        rel = rel or ("vehicles/" + self.id)
        pairs = []
        try:
            for base in ("Paint", "Paint2"):
                loc = bpy.data.materials.get(self.prefix + base)
                sh = bpy.data.materials.get(base)
                if loc is None:
                    continue
                if sh is not None:
                    sh.name = base + "__lane2swap"
                loc.name = base
                pairs.append((base, loc, sh))
            path = export_glb(self.root, rel)
            if self.lod_root is not None:
                export_glb(self.lod_root, rel + "_lod")
        finally:
            for base, loc, sh in pairs:
                loc.name = self.prefix + base
                if sh is not None:
                    sh.name = base
        return path


# --------------------------------------------------------------------------------------------------------------
# QA
# --------------------------------------------------------------------------------------------------------------
def l2_island_report(obj, verbose=True):
    """Signed volume per connected shell: negative = inside-out normals."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    res = []
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
                b = e.other_vert(a)
                if b.index not in seen:
                    seen.add(b.index)
                    stack.append(b)
        faces = set(f for a in comp for f in a.link_faces)
        vol = 0.0
        for f in faces:
            vs = [lp.vert.co for lp in f.loops]
            for i in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[i].cross(vs[i + 1])) / 6.0
        res.append((len(comp), len(faces), round(vol, 5)))
    bm.free()
    bad = [r for r in res if r[2] < 0]
    if verbose:
        print(obj.name, "shells", len(res), "inside-out", len(bad), bad[:6])
    return res


def l2_tris(root):
    bpy.context.view_layer.update()
    out = {}
    for o in descendants(root):
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            out[o.name.split("__", 1)[-1]] = len(o.data.loop_triangles)
    out["TOTAL"] = sum(out.values())
    return out


# --------------------------------------------------------------------------------------------------------------
# primitives
# --------------------------------------------------------------------------------------------------------------
def l2_loft(mb, rings, edge_mats, cap0=None, cap1=None, closed=True):
    """Skin rings (lists of 3D points, same count) with quads. edge_mats: str or per-edge list (point i -> i+1)."""
    V = [[mb.v(p) for p in r] for r in rings]
    n = len(V[0])
    for k in range(len(V) - 1):
        for i in (range(n) if closed else range(n - 1)):
            j = (i + 1) % n
            m = edge_mats if isinstance(edge_mats, str) else edge_mats[i]
            mb.face([V[k][i], V[k][j], V[k + 1][j], V[k + 1][i]], m)
    if closed and cap0:
        mb.face(list(reversed(V[0])), cap0)
    if closed and cap1:
        mb.face(V[-1], cap1)
    return V


def l2_oct(hw, zb, zt, c=0.06, cb=None, xc=0.0):
    """Chamfered rectangle (x,z) going bottom-left -> bottom-right -> up the right side -> back along the top."""
    cb = c if cb is None else cb
    c = min(c, hw * 0.9, (zt - zb) * 0.45)
    cb = min(cb, hw * 0.9, (zt - zb) * 0.45)
    return [(xc - hw + c, zb), (xc + hw - c, zb), (xc + hw, zb + c), (xc + hw, zt - cb),
            (xc + hw - cb, zt), (xc - hw + cb, zt), (xc - hw, zt - cb), (xc - hw, zb + c)]


def l2_tube(mb, sts, side="Paint", top="Paint", bot="Trim", cap0=None, cap1=None, shoulder=None):
    """Loft of chamfered-rectangle sections. sts = list of dicts: y, hw, zb, zt, [c, cb, xc]. Edges: 0 bottom, 1/7 lower
    chamfers (bot), 2/6 sides, 3/5 upper chamfers (shoulder, default = top), 4 top."""
    shoulder = shoulder or top
    rings = []
    for s in sts:
        pts = l2_oct(s["hw"], s["zb"], s["zt"], s.get("c", 0.06), s.get("cb"), s.get("xc", 0.0))
        rings.append([(x, s["y"], z) for (x, z) in pts])
    return l2_loft(mb, rings, [bot, bot, side, shoulder, top, shoulder, side, bot], cap0, cap1)


def l2_cbox(mb, y0, y1, hw, zb, zt, c=0.06, cb=None, xc=0.0, side="Paint", top="Paint", bot="Trim", cap0=None, cap1=None, shoulder=None):
    return l2_tube(mb, [dict(y=y0, hw=hw, zb=zb, zt=zt, c=c, cb=cb, xc=xc), dict(y=y1, hw=hw, zb=zb, zt=zt, c=c, cb=cb, xc=xc)],
                   side, top, bot, cap0, cap1, shoulder)


def l2_obox(mb, c, ax, ay, az, hx, hy, hz, mat, taper=(1.0, 1.0)):
    """Oriented box: centre c, orthonormal axes ax/ay/az (tuples), half sizes hx/hy/hz. taper=(sx, sz) scales the +ay end."""
    c = Vector(c)
    ax, ay, az = Vector(ax), Vector(ay), Vector(az)
    pts = []
    for iy in (-1, 1):
        tx = taper[0] if iy > 0 else 1.0
        tz = taper[1] if iy > 0 else 1.0
        for (sx_, sz_) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            pts.append(c + ax * (sx_ * hx * tx) + ay * (iy * hy) + az * (sz_ * hz * tz))
    V = [mb.v(p) for p in pts]
    for idx in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        mb.face([V[i] for i in idx], mat)
    return V


def l2_box(mb, x0, x1, y0, y1, z0, z1, mat):
    mb.block(((x0 + x1) / 2, (y0 + y1) / 2), z0, z1, (abs(x1 - x0), abs(y1 - y0)), None, mat)


def l2_revolve_x(mb, profile, seg, mat, s=1.0):
    """Revolve profile [(x, radius)] about the X axis (x multiplied by s). radius 0 -> single centre vertex."""
    rings = []
    for (x, rad) in profile:
        if rad < 1e-6:
            rings.append(mb.v((x * s, 0, 0)))
        else:
            rings.append([mb.v((x * s, rad * math.cos(2 * math.pi * k / seg), rad * math.sin(2 * math.pi * k / seg))) for k in range(seg)])
    for i in range(len(profile) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(seg):
            k2 = (k + 1) % seg
            if isinstance(a, list) and isinstance(b, list):
                mb.face([a[k], a[k2], b[k2], b[k]], mat)
            elif isinstance(b, list):
                mb.face([a, b[k2], b[k]], mat)
            elif isinstance(a, list):
                mb.face([a[k], a[k2], b], mat)


def l2_seam_v(mb, x, y, z0, z1, mat="Trim", w=0.011, d=0.008):
    mb.box((x, y, (z0 + z1) / 2), (d, w, z1 - z0), mat)


def l2_seam_h(mb, x, y0, y1, z, mat="Trim", h=0.011, d=0.008):
    mb.box((x, (y0 + y1) / 2, z), (d, y1 - y0, h), mat)


def l2_seam_front(mb, y, x0, x1, z0, z1, mat="Trim", d=0.01):
    """thin plate on a Y-facing wall (front/rear panel lines)."""
    mb.box(((x0 + x1) / 2, y, (z0 + z1) / 2), (abs(x1 - x0), d, abs(z1 - z0)), mat)


def l2_inset_poly(pts, d):
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n)) / 2.0
    sgn = 1.0 if area > 0 else -1.0
    lines = []
    for i in range(n):
        p, q = pts[i], pts[(i + 1) % n]
        dx, dy = q[0] - p[0], q[1] - p[1]
        ln = math.hypot(dx, dy) or 1e-9
        nx, ny = -dy / ln * sgn, dx / ln * sgn
        lines.append((p[0] + nx * d, p[1] + ny * d, dx, dy))
    out = []
    for i in range(n):
        a, b = lines[i - 1], lines[i]
        den = a[2] * b[3] - a[3] * b[2]
        if abs(den) < 1e-9:
            out.append((b[0], b[1]))
            continue
        t = ((b[0] - a[0]) * b[3] - (b[1] - a[1]) * b[2]) / den
        out.append((a[0] + a[2] * t, a[1] + a[3] * t))
    return out


def l2_flat_slab(mb, poly, xwall, sign, thick, off, mat):
    """Plate over a (y,z) polygon on a vertical wall |x| = xwall (side sign): outer face at sign*(xwall+off+thick)."""
    n = len(poly)
    A = [mb.v((sign * (xwall + off + thick), p[0], p[1])) for p in poly]
    B = [mb.v((sign * (xwall + off), p[0], p[1])) for p in poly]
    mb.face(A, mat)
    mb.face(list(reversed(B)), mat)
    for i in range(n):
        j = (i + 1) % n
        mb.face([B[i], B[j], A[j], A[i]], mat)


def l2_frame_slab(mb, poly, xwall, sign, width, thick, off, mat):
    """Picture-frame slab (window frame) hugging a vertical wall."""
    inner = l2_inset_poly(poly, width)
    n = len(poly)

    def P(pt, dx):
        return (sign * (xwall + dx), pt[0], pt[1])
    Oo = [mb.v(P(p, off + thick)) for p in poly]
    Io = [mb.v(P(p, off + thick)) for p in inner]
    Oi = [mb.v(P(p, off)) for p in poly]
    Ii = [mb.v(P(p, off)) for p in inner]
    for i in range(n):
        j = (i + 1) % n
        mb.face([Oo[i], Oo[j], Io[j], Io[i]], mat)
        mb.face([Oi[i], Ii[i], Ii[j], Oi[j]], mat)
        mb.face([Oi[i], Oi[j], Oo[j], Oo[i]], mat)
        mb.face([Ii[i], Io[i], Io[j], Ii[j]], mat)


def l2_flat_window(mb, poly, xwall, s, fw=0.05, frame="Trim", back="Interior", glass="Glass"):
    """Window on a flat vertical wall at |x| = xwall (side s): frame + dark backing + glass pane."""
    l2_frame_slab(mb, poly, xwall, s, fw, 0.012, 0.0, frame)
    inner = l2_inset_poly(poly, fw)
    l2_flat_slab(mb, inner, xwall, s, 0.006, 0.0, back)
    l2_flat_slab(mb, inner, xwall, s, 0.006, 0.006, glass)


def l2_rect(y0, y1, z0, z1, c=0.0):
    """Rectangle polygon (y,z) with optional corner chamfer c."""
    if c <= 0:
        return [(y0, z0), (y1, z0), (y1, z1), (y0, z1)]
    return [(y0 + c, z0), (y1 - c, z0), (y1, z0 + c), (y1, z1 - c), (y1 - c, z1), (y0 + c, z1), (y0, z1 - c), (y0, z0 + c)]


def l2_seat(mb, x, y, floor_z, width=0.50, depth=0.50, back_h=0.62, cush_h=0.20, mat="Interior", recline=0.10, head=True):
    """Seat facing +Y: cushion + reclined backrest (+ headrest). y = seat centre, floor_z = floor level under the seat."""
    mb.box((x, y, floor_z + cush_h * 0.5 + 0.08), (width, depth, cush_h), mat)
    zb = floor_z + cush_h + 0.08
    mb.block((x, y - depth * 0.5 + 0.06), zb, zb + back_h, (width, 0.14), (width - 0.06, 0.10), mat, top_shift=(-recline, 0))
    if head:
        mb.box((x, y - depth * 0.5 + 0.06 - recline, zb + back_h + 0.07), (0.20, 0.09, 0.15), mat)


def l2_steering_wheel(mb, center, tilt_deg=25, r=0.19, mat="Trim", hub="Interior", n=8):
    cx, cy, cz = center
    t = math.radians(tilt_deg)
    u = Vector((0, math.sin(t), math.cos(t)))
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        pts.append(Vector((cx, cy, cz)) + Vector((1, 0, 0)) * (math.cos(a) * r) + u * (math.sin(a) * r))
    for i in range(n):
        mb.beam(pts[i], pts[(i + 1) % n], 0.017, 0.017, 4, mat, caps=True)
    mb.beam(Vector((cx, cy, cz)) + Vector((-r * 0.9, 0, 0)), Vector((cx, cy, cz)) + Vector((r * 0.9, 0, 0)), 0.014, 0.014, 4, mat)
    mb.beam(Vector((cx, cy, cz)), Vector((cx, cy, cz)) + u * (-r * 0.9), 0.014, 0.014, 4, mat)
    mb.box((cx, cy, cz), (0.12, 0.05, 0.08), hub)
    nrm = Vector((0, -math.cos(t), math.sin(t)))
    mb.beam(Vector((cx, cy, cz)), Vector((cx, cy, cz)) - nrm * 0.30, 0.03, 0.035, 4, hub)


def l2_star(mb, x, y, z, size, face, mat, bar=0.07, d=0.012):
    """Six-armed medical asterisk (three crossing bars) on a wall. face = 'x' (side wall, x is the outer face) or 'y'."""
    for k in range(3):
        a = math.pi * k / 3
        ca, sa = math.cos(a), math.sin(a)
        ln = size
        if face == "x":
            ax = Vector((0, ca, sa))
            nx = Vector((1, 0, 0))
            az = Vector((0, -sa, ca))
            l2_obox(mb, (x, y, z), nx, ax, az, d / 2, ln / 2, bar / 2, mat)
        else:
            ax = Vector((ca, 0, sa))
            ny = Vector((0, 1, 0))
            az = Vector((-sa, 0, ca))
            l2_obox(mb, (x, y, z), az, ny, ax, bar / 2, d / 2, ln / 2, mat)


def l2_revolve_loop(mb, profile, edge_mats, seg, s=1.0):
    """Revolve a CLOSED profile loop [(x, radius)...] about X (torus-like closed shell, shared verts). edge_mats[i] = mat of edge i->i+1."""
    rings = [[mb.v((x * s, rad * math.cos(2 * math.pi * k / seg), rad * math.sin(2 * math.pi * k / seg))) for k in range(seg)] for (x, rad) in profile]
    n = len(profile)
    for i in range(n):
        a, b = rings[i], rings[(i + 1) % n]
        for k in range(seg):
            k2 = (k + 1) % seg
            mb.face([a[k], a[k2], b[k2], b[k]], edge_mats[i])


# --------------------------------------------------------------------------------------------------------------
# wheels (spin axis X, origin = wheel centre, s = +1 for right wheels (outer face +X), -1 for left)
# --------------------------------------------------------------------------------------------------------------
def l2_wheel(name, r, w, s, collection, seg=12, style="car", tire="Tire", rim="Rim", hub="Chrome", dish="Trim", loc=(0, 0, 0)):
    b = MB(name)
    if style == "car":
        l2_revolve_x(b, [(-0.5 * w, 0.74 * r), (-0.40 * w, 0.97 * r), (0.40 * w, 0.97 * r), (0.5 * w, 0.74 * r)], seg, tire, s)
        l2_revolve_x(b, [(-0.5 * w, 0.74 * r), (-0.40 * w, 0.0)], seg, dish, s)
        l2_revolve_x(b, [(0.5 * w, 0.74 * r), (0.43 * w, 0.64 * r), (0.34 * w, 0.0)], seg, dish, s)
        pts = []
        for i in range(10):
            a = math.pi * 2 * i / 10 + math.pi / 10
            rr = 0.60 * r if i % 2 == 0 else 0.24 * r
            pts.append((math.cos(a) * rr, math.sin(a) * rr))
        top = [b.v((s * 0.40 * w, p[0], p[1])) for p in pts]
        bot = [b.v((s * 0.33 * w, p[0], p[1])) for p in pts]
        b.face(top, rim)
        b.face(list(reversed(bot)), rim)
        for i in range(10):
            j = (i + 1) % 10
            b.face([bot[i], bot[j], top[j], top[i]], rim)
        b.cyl((s * 0.43 * w, 0, 0), r * 0.15, 0.05, 6, hub, axis="X")
    elif style == "truck":
        # wide tyre, steel wheel with dished face + hub (no per-nut geometry: keeps the wheel under ~215 tris at seg 12)
        l2_revolve_x(b, [(-0.5 * w, 0.62 * r), (-0.40 * w, 0.95 * r), (0.0, 1.0 * r), (0.40 * w, 0.95 * r), (0.5 * w, 0.62 * r)], seg, tire, s)
        l2_revolve_x(b, [(-0.5 * w, 0.62 * r), (-0.38 * w, 0.0)], seg, dish, s)
        l2_revolve_x(b, [(0.5 * w, 0.62 * r), (0.38 * w, 0.30 * r), (0.42 * w, 0.0)], seg, rim, s)
        b.cyl((s * 0.43 * w, 0, 0), r * 0.22, 0.07, 6, hub, axis="X")
    elif style == "moto":
        l2_revolve_x(b, [(-0.5 * w, 0.62 * r), (-0.40 * w, 0.90 * r), (-0.18 * w, 0.99 * r), (0.18 * w, 0.99 * r), (0.40 * w, 0.90 * r), (0.5 * w, 0.62 * r)], seg, tire, s)
        l2_revolve_x(b, [(-0.5 * w, 0.62 * r), (-0.36 * w, 0.0)], seg, dish, s)
        l2_revolve_x(b, [(0.5 * w, 0.62 * r), (0.38 * w, 0.0)], seg, dish, s)
        pts = []
        for i in range(10):
            a = math.pi * 2 * i / 10 + math.pi / 10
            rr = 0.56 * r if i % 2 == 0 else 0.22 * r
            pts.append((math.cos(a) * rr, math.sin(a) * rr))
        top = [b.v((s * 0.46 * w, p[0], p[1])) for p in pts]
        bot = [b.v((s * 0.40 * w, p[0], p[1])) for p in pts]
        b.face(top, rim)
        b.face(list(reversed(bot)), rim)
        for i in range(10):
            j = (i + 1) % 10
            b.face([bot[i], bot[j], top[j], top[i]], rim)
        b.cyl((s * 0.47 * w, 0, 0), r * 0.13, 0.04, 6, hub, axis="X")
    elif style == "bike":
        # closed diamond tyre/rim ring + hub + spokes (spin axis X)
        l2_revolve_loop(b, [(-0.5 * w, 0.88 * r), (0.0, 0.985 * r), (0.5 * w, 0.88 * r), (0.0, 0.78 * r)], [tire, tire, rim, rim], seg, s)
        b.cyl((0, 0, 0), r * 0.075, w * 1.5, 6, hub, axis="X")
        nsp = 8
        for i in range(nsp):
            a = 2 * math.pi * i / nsp + 0.2
            sd = 1 if i % 2 == 0 else -1
            y, z = math.cos(a), math.sin(a)
            b.beam((sd * w * 0.35, y * r * 0.075, z * r * 0.075), (sd * w * 0.05, y * r * 0.80, z * r * 0.80), 0.004, 0.004, 3, "Metal", caps=False)
    obj = b.finish(collection, name, loc=loc, smooth_angle_deg=45, weld=0.0)
    return obj


# --------------------------------------------------------------------------------------------------------------
# arches / shells / misc (added for the big vehicles)
# --------------------------------------------------------------------------------------------------------------
def l2_arch_zb(y, base, wheels):
    """Underside height at y: wheels = [(yw, zc, Ra)] -> circular arch of radius Ra around each wheel centre."""
    z = base
    for (yw, zc, Ra) in wheels:
        d = abs(y - yw)
        if d < Ra:
            z = max(z, zc + math.sqrt(Ra * Ra - d * d))
    return z


def l2_arch_ys(wheels, y0, y1, n=6):
    ys = set()
    for (yw, zc, Ra) in wheels:
        for i in range(n + 1):
            y = yw - Ra * math.cos(math.pi * i / n)
            if y0 + 1e-4 < y < y1 - 1e-4:
                ys.add(round(y, 4))
    return ys


def l2_tube_arch(mb, y0, y1, hw, zb, zt, wheels, extra_ys=(), c=0.06, cb=None, **mats):
    """Chamfered-box tube from y0 to y1 with wheel arches cut into the underside. hw / zt may be callables of y."""
    ys = {round(y0, 4), round(y1, 4)} | l2_arch_ys(wheels, y0, y1) | {round(e, 4) for e in extra_ys if y0 < e < y1}
    sts = []
    for y in sorted(ys):
        h = hw(y) if callable(hw) else hw
        t = zt(y) if callable(zt) else zt
        sts.append(dict(y=y, hw=h, zb=l2_arch_zb(y, zb, wheels), zt=t, c=c, cb=cb))
    return l2_tube(mb, sts, **mats)


def l2_shell_yz(mb, pts, hw, edge_mats, side_mat, xc=0.0):
    """Closed prism from a (y,z) outline with vertical sides at |x| = hw (xc = centre). edge_mats[i] = material of edge pts[i]->pts[i+1]."""
    n = len(pts)
    R = [mb.v((xc + hw, y, z)) for (y, z) in pts]
    L = [mb.v((xc - hw, y, z)) for (y, z) in pts]
    mb.face(R, side_mat)
    mb.face(list(reversed(L)), side_mat)
    for i in range(n):
        j = (i + 1) % n
        mb.face([L[i], L[j], R[j], R[i]], edge_mats[i])


def l2_wipers(mb, A, B, t=0.10, spans=((-0.55, -0.1), (0.05, 0.6)), mat="Trim"):
    """Wiper blades lying on a windscreen (A = glass base (y,z), B = glass top (y,z))."""
    dy, dz = B[0] - A[0], B[1] - A[1]
    ln = math.hypot(dy, dz)
    ny, nz = dz / ln, -dy / ln
    uy, uz = dy / ln, dz / ln
    y = l2_lerp(A[0], B[0], t) + ny * 0.012
    z = l2_lerp(A[1], B[1], t) + nz * 0.012
    for (x0, x1) in spans:
        mb.beam((x0, y, z), (x1, y + uy * 0.07, z + uz * 0.07), 0.007, 0.007, 4, mat)


def l2_cyl_y(mb, x, y, z, r, h, seg=8, mat="Trim"):
    mb.cyl((x, y, z), r, h, seg, mat, axis="Y")


def l2_mirror(mb, sx, x, y, z, mat_frame="Trim", glass="Chrome", size=(0.10, 0.24)):
    """Truck-style mirror: two stalk beams + a plate (facing -Y) at (x*sx, y, z)."""
    w, h = size
    mb.beam((sx * (x - 0.16), y + 0.02, z - 0.06), (sx * x, y, z), 0.014, 0.014, 3, "MetalDark", caps=False)
    mb.beam((sx * (x - 0.16), y + 0.02, z - 0.28), (sx * x, y, z - 0.12), 0.014, 0.014, 3, "MetalDark", caps=False)
    mb.box((sx * x, y, z - 0.06), (w + 0.03, 0.06, h + 0.03), mat_frame)
    mb.box((sx * x, y - 0.034, z - 0.06), (w, 0.012, h), glass)


# --------------------------------------------------------------------------------------------------------------
# decal quads (2 tris each, visible from both sides because the glTF materials are double sided)
# --------------------------------------------------------------------------------------------------------------
def l2_quad_x(mb, x, y0, y1, z0, z1, mat):
    mb.face([mb.v((x, y0, z0)), mb.v((x, y1, z0)), mb.v((x, y1, z1)), mb.v((x, y0, z1))], mat)


def l2_quad_y(mb, y, x0, x1, z0, z1, mat):
    mb.face([mb.v((x0, y, z0)), mb.v((x1, y, z0)), mb.v((x1, y, z1)), mb.v((x0, y, z1))], mat)


def l2_quad_z(mb, z, x0, x1, y0, y1, mat):
    mb.face([mb.v((x0, y0, z)), mb.v((x1, y0, z)), mb.v((x1, y1, z)), mb.v((x0, y1, z))], mat)


def l2_poly_x(mb, x, pts_yz, mat):
    mb.face([mb.v((x, p[0], p[1])) for p in pts_yz], mat)


def l2_poly_y(mb, y, pts_xz, mat):
    mb.face([mb.v((p[0], y, p[1])) for p in pts_xz], mat)


def l2_rect_lines_x(mb, x, y0, y1, z0, z1, mat="Trim", w=0.018):
    """Outline of a rectangle on a side wall as four decal quads."""
    l2_quad_x(mb, x, y0, y1, z0, z0 + w, mat)
    l2_quad_x(mb, x, y0, y1, z1 - w, z1, mat)
    l2_quad_x(mb, x, y0, y0 + w, z0, z1, mat)
    l2_quad_x(mb, x, y1 - w, y1, z0, z1, mat)


def l2_arc_fender(mb, yc, zc, x0, x1, r_in, r_out, th0, th1, nst, mat):
    rings = []
    for i in range(nst + 1):
        th = th0 + (th1 - th0) * i / nst
        pr = []
        for (xx, rr) in ((x0, r_out), (x1, r_out), (x1, r_in), (x0, r_in)):
            pr.append((xx, yc + rr * math.sin(th), zc + rr * math.cos(th)))
        rings.append(pr)
    l2_loft(mb, rings, mat, mat, mat)


def l2_wheel_lite(mb, center, tilt_deg=25, r=0.19, mat="Trim", hub="Interior"):
    """Low-tri steering wheel: 6-segment ring (3-sided beams, no caps) + hub + column (~60 tris)."""
    cx, cy, cz = center
    t = math.radians(tilt_deg)
    u = Vector((0, math.sin(t), math.cos(t)))
    pts = [Vector((cx, cy, cz)) + Vector((1, 0, 0)) * (math.cos(2 * math.pi * i / 6) * r) + u * (math.sin(2 * math.pi * i / 6) * r) for i in range(6)]
    for i in range(6):
        mb.beam(pts[i], pts[(i + 1) % 6], 0.02, 0.02, 3, mat, caps=False)
    mb.beam(Vector((cx - r * 0.9, cy, cz)), Vector((cx + r * 0.9, cy, cz)), 0.016, 0.016, 3, mat, caps=False)
    mb.box((cx, cy, cz), (0.12, 0.05, 0.08), hub)
    nrm = Vector((0, -math.cos(t), math.sin(t)))
    mb.beam(Vector((cx, cy, cz)), Vector((cx, cy, cz)) - nrm * 0.30, 0.03, 0.035, 3, hub, caps=False)


def l2_ring_z(mb, c, r_out, r_in, z0, z1, seg, mat_out="Metal", mat_top="Metal", mat_in="Trim", mat_bot=None):
    """Closed ring (hollow cylinder with thick wall) around a vertical axis through c=(x,y). 4 bands."""
    cx, cy = c
    def ring(r, z):
        return [mb.v((cx + r * math.cos(2 * math.pi * k / seg), cy + r * math.sin(2 * math.pi * k / seg), z)) for k in range(seg)]
    rs = [ring(r_out, z0), ring(r_out, z1), ring(r_in, z1), ring(r_in, z0)]
    mats = [mat_out, mat_top, mat_in, mat_bot or mat_top]
    for i in range(4):
        a, b = rs[i], rs[(i + 1) % 4]
        for k in range(seg):
            k2 = (k + 1) % seg
            mb.face([a[k], a[k2], b[k2], b[k]], mats[i])


def l2_rotz(v, a):
    ca, sa = math.cos(a), math.sin(a)
    return (v[0] * ca - v[1] * sa, v[0] * sa + v[1] * ca, v[2])
