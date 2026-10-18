"""
lane1_common.py - car-building toolkit for Blender lane 1 (GTA_GODOT/Vehicles/Cars).
Load AFTER gta_lib.py:  exec(open(r"...\\tools\\blender\\lane1_common.py", encoding="utf8").read(), globals())

Design (all metres, +Y forward, origin = ground point at wheelbase centre, driver on the LEFT = -X):
  * body = closed shells in ONE mesh (weld disabled, so every shell keeps outward normals through recalc):
      - "tub" lofts   : closed ring lofts (nose/hood/trunk/tail), rings built from station dicts
      - "ch"  channel : U-shaped loft for the cabin section (open top, floor, inner walls -> interior visible through glass)
      - greenhouse    : closed tapered prism from a side outline (Glass sides, Paint roof slab, Trim window frames)
  * wheel arches are cut into the rings (arch stations), wheels poke slightly out
  * every car gets local Paint/Paint2 materials ("<id>__Paint") that are swapped to the shared names at export time only.
"""
import math

# --------------------------------------------------------------------------------------------------------------
# small math helpers
# --------------------------------------------------------------------------------------------------------------
def lerp(a, b, t):
    return a + (b - a) * t


def clamp(v, a, b):
    return max(a, min(b, v))


def inset_poly(pts, d):
    """Offset a convex polygon (list of (a,b)) inwards by d."""
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


def clip_poly(pts, lo=None, hi=None):
    """Clip polygon of (y,z) points to lo <= y <= hi (Sutherland-Hodgman)."""
    def clip(poly, keep, edge_y):
        out = []
        n = len(poly)
        for i in range(n):
            a, b = poly[i], poly[(i + 1) % n]
            ina, inb = keep(a[0]), keep(b[0])
            if ina:
                out.append(a)
            if ina != inb:
                t = (edge_y - a[0]) / (b[0] - a[0])
                out.append((edge_y, lerp(a[1], b[1], t)))
        return out
    p = list(pts)
    if lo is not None:
        p = clip(p, lambda y: y >= lo, lo)
    if hi is not None and p:
        p = clip(p, lambda y: y <= hi, hi)
    return p


# --------------------------------------------------------------------------------------------------------------
# stations / rings
# --------------------------------------------------------------------------------------------------------------
def key(y, ws, zb, zd, **kw):
    """Body cross-section key station. ws = half width, zb = underside z, zd = deck (shoulder top) z."""
    P = dict(y=y, ws=ws, zb=zb, zd=zd)
    P["wb"] = kw.get("wb", ws - 0.10)
    P["zl"] = kw.get("zl", zb + 0.09)
    P["zsh"] = kw.get("zsh", zd - 0.10)
    P["wt"] = kw.get("wt", ws - 0.10)
    P["zc"] = kw.get("zc", zd + 0.025)
    return P


def interp_st(keys, y):
    ks = sorted(keys, key=lambda k: k["y"])
    if y <= ks[0]["y"]:
        return dict(ks[0], y=y)
    if y >= ks[-1]["y"]:
        return dict(ks[-1], y=y)
    for a, b in zip(ks, ks[1:]):
        if a["y"] <= y <= b["y"]:
            t = 0.0 if b["y"] == a["y"] else (y - a["y"]) / (b["y"] - a["y"])
            return {k: (y if k == "y" else lerp(a[k], b[k], t)) for k in a}
    return dict(ks[-1], y=y)


ARCH_F = (-1.0, -0.8, -0.45, 0.0, 0.45, 0.8, 1.0)


def stations(keys, wheels, y0, y1, extra=()):
    """Stations between y0 and y1 (ascending y): key stations + arch stations. wheels = [(yw, zc, R, wi)]."""
    ys = {round(y0, 4), round(y1, 4)}
    for k in keys:
        if y0 <= k["y"] <= y1:
            ys.add(round(k["y"], 4))
    for e in extra:
        if y0 <= e <= y1:
            ys.add(round(e, 4))
    for w in wheels:
        yw, zc, R, wi = w[:4]
        for f in ARCH_F:
            y = yw + R * f
            if y0 <= y <= y1:
                ys.add(round(y, 4))
        for y in (yw - R - 0.014, yw + R + 0.014):
            if y0 <= y <= y1:
                ys.add(round(y, 4))
    out = []
    for y in sorted(ys):
        P = interp_st(keys, y)
        for w in wheels:
            yw, zc, R, wi = w[:4]
            fl = w[4] if len(w) > 4 else 0.0
            dy = y - yw
            if abs(dy) <= R + 1e-6:
                zA = zc + math.sqrt(max(R * R - dy * dy, 0.0))
                zA = clamp(zA, P["zb"] + 0.14, P["zsh"] - 0.05)
                P["arch"] = (wi, zA, fl)
        out.append(P)
    return out


ROLES_TUB = ["low", "cham", "side", "shoulder", "top", "top", "shoulder", "side", "cham", "low", "bottom"]
ROLES_CH = ["low", "cham", "side", "shoulder", "rim", "inner", "bevel", "floor", "bevel", "inner", "rim", "shoulder", "side", "cham", "low", "bottom"]


def ring_pts(P, kind, floor=0.30, wall=0.08):
    ws, wb, zb, zl, zsh, wt, zd, zc = (P[k] for k in ("ws", "wb", "zb", "zl", "zsh", "wt", "zd", "zc"))
    arch = P.get("arch")
    if arch:
        wi, zA = arch[0], arch[1]
        fl = arch[2] if len(arch) > 2 else 0.0
        p0, p1, p1b = (wi, zb), (wi, zA), (ws + fl - 0.02, zA)
        p2 = (ws + fl, zsh)
    else:
        p0, p1, p1b = (wb, zb), (ws - 0.02, zl), (ws, zl + 0.08)
        p2 = (ws, zsh)
    p3 = (wt, zd)
    if kind == "tub":
        half = [p0, p1, p1b, p2, p3]
        top = (0.0, zc)
        return half + [top] + [(-x, z) for (x, z) in reversed(half)]
    # channel (open top)
    zf = floor
    if arch:
        zf = max(zf, arch[1] + 0.045)
    q3 = (ws - wall, zd)
    q2 = (ws - wall, zf + 0.05)
    q1 = (ws - wall - 0.06, zf)
    half = [p0, p1, p1b, p2, p3, q3, q2, q1]
    return half + [(-x, z) for (x, z) in reversed(half)]


def build_section(mb, sts, kind, mat_fn, cap0=None, cap1=None, floor=0.30, wall=0.08):
    """Loft stations (ascending y) into a closed shell. mat_fn(role, ym) -> material name. cap0 = rear cap material, cap1 = front cap."""
    roles = ROLES_TUB if kind == "tub" else ROLES_CH
    V = []
    for P in sts:
        pts = ring_pts(P, kind, floor, wall)
        V.append([mb.v((x, P["y"], z)) for (x, z) in pts])
    n = len(V[0])
    assert n == len(roles), (n, len(roles))
    for k in range(len(V) - 1):
        ym = 0.5 * (sts[k]["y"] + sts[k + 1]["y"])
        for i in range(n):
            j = (i + 1) % n
            mb.face([V[k][i], V[k][j], V[k + 1][j], V[k + 1][i]], mat_fn(roles[i], ym))
    if cap0:
        mb.face(list(reversed(V[0])), cap0)
    if cap1:
        mb.face(V[-1], cap1)
    return V


# --------------------------------------------------------------------------------------------------------------
# greenhouse / slabs
# --------------------------------------------------------------------------------------------------------------
def shell_yz(mb, pts, xfn, edge_mats, side_mat):
    """Closed shell from a (y,z) outline: half width at height z = xfn(z). edge_mats[i] = material of edge pts[i]->pts[i+1]."""
    n = len(pts)
    R = [mb.v((xfn(z), y, z)) for (y, z) in pts]
    Lv = [mb.v((-xfn(z), y, z)) for (y, z) in pts]
    mb.face(R, side_mat)
    mb.face(list(reversed(Lv)), side_mat)
    for i in range(n):
        j = (i + 1) % n
        mb.face([Lv[i], Lv[j], R[j], R[i]], edge_mats[i])


def frame_slab(mb, poly, xfn, sign, width, thick, off, mat):
    """Window frame (picture-frame slab) hugging the sloped greenhouse side. poly = (y,z) polygon, outer edge = poly."""
    inner = inset_poly(poly, width)
    n = len(poly)

    def P(pt, dx):
        return (sign * (xfn(pt[1]) + dx), pt[0], pt[1])
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


def flat_slab(mb, poly, xfn, sign, thick, off, mat):
    """Solid plate over a (y,z) polygon, outer face at sign*(xfn(z)+off+thick), thickness `thick`."""
    n = len(poly)

    def P(pt, dx):
        return (sign * (xfn(pt[1]) + dx), pt[0], pt[1])
    A = [mb.v(P(p, off + thick)) for p in poly]
    B = [mb.v(P(p, off)) for p in poly]
    mb.face(A, mat)
    mb.face(list(reversed(B)), mat)
    for i in range(n):
        j = (i + 1) % n
        mb.face([B[i], B[j], A[j], A[i]], mat)


def flat_window(mb, poly, xwall, s, fw=0.05):
    """Window on a flat vertical wall at |x| = xwall (side s): Trim frame + dark Interior backing + Glass pane."""
    frame_slab(mb, poly, lambda z: xwall, s, fw, 0.012, 0.0, "Trim")
    inner = inset_poly(poly, fw)
    flat_slab(mb, inner, lambda z: xwall, s, 0.006, 0.0, "Interior")
    flat_slab(mb, inner, lambda z: xwall, s, 0.006, 0.006, "Glass")


def wipers(mb, A, B, gx, spans=((-0.62, -0.12), (0.02, 0.52)), t=0.11, mat="Trim"):
    """Two wiper blades lying on the windshield (A = glass base, B = glass top, both (y,z))."""
    dy, dz = B[0] - A[0], B[1] - A[1]
    ln = math.hypot(dy, dz)
    ny, nz = dz / ln, -dy / ln
    uy, uz = dy / ln, dz / ln
    y = lerp(A[0], B[0], t) + ny * 0.012
    z = lerp(A[1], B[1], t) + nz * 0.012
    for (x0, x1) in spans:
        mb.beam((x0, y, z), (x1, y + uy * 0.06, z + uz * 0.06), 0.007, 0.007, 4, mat)


def bevel_rect(y0, y1, z0, z1, c=0.04, cb=None):
    """Rectangle (y,z) with chamfered bottom corners (c) and top corners (cb)."""
    cb = c if cb is None else cb
    return [(y0 + c, z0), (y1 - c, z0), (y1, z0 + c), (y1, z1 - cb), (y1 - cb, z1), (y0 + cb, z1), (y0, z1 - cb), (y0, z0 + c)]


# --------------------------------------------------------------------------------------------------------------
# generic details
# --------------------------------------------------------------------------------------------------------------
def revolve_x(mb, profile, seg, mat, s=1.0):
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


def lean_wheel(name, r, w, s, collection, seg=12, tire="Tire", rim="Rim", hub="Chrome", dish="Trim", loc=(0, 0, 0)):
    """~170 tri wheel. Spin axis X, origin = wheel centre, s = +1 for right wheels (outer face +X), -1 for left."""
    b = MB(name)
    revolve_x(b, [(-0.5 * w, 0.74 * r), (-0.40 * w, 0.97 * r), (0.40 * w, 0.97 * r), (0.5 * w, 0.74 * r)], seg, tire, s)
    # inner closing disc (cone) - fan to centre
    revolve_x(b, [(-0.5 * w, 0.74 * r), (-0.40 * w, 0.0)], seg, dish, s)
    # outer rim lip + dished face
    revolve_x(b, [(0.5 * w, 0.74 * r), (0.43 * w, 0.64 * r), (0.34 * w, 0.0)], seg, dish, s)
    # 5 spoke star (prism extruded along X)
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
    obj = b.finish(collection, name, loc=loc, smooth_angle_deg=45, weld=0.0)
    return obj


def seam_v(mb, x, y, z0, z1, mat="Trim", w=0.011, d=0.008):
    mb.box((x, y, (z0 + z1) / 2), (d, w, z1 - z0), mat)


def seam_h(mb, x, y0, y1, z, mat="Trim", h=0.011, d=0.008):
    mb.box((x, (y0 + y1) / 2, z), (d, y1 - y0, h), mat)


def steering_wheel(mb, center, tilt_deg=25, r=0.19, mat="Trim", hub="Interior", n=8):
    """Steering wheel ring (n beams) facing the driver (normal ~ -Y tilted up) + hub + column. center=(x,y,z)."""
    cx, cy, cz = center
    t = math.radians(tilt_deg)
    # wheel plane spanned by X axis and u = (0, -sin t... ) ; normal points toward driver (-Y, +Z a bit)
    u = Vector((0, math.sin(t), math.cos(t)))  # "up" direction in the wheel plane (normal = (0,-cos t, sin t) faces the driver)
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        pts.append(Vector((cx, cy, cz)) + Vector((1, 0, 0)) * (math.cos(a) * r) + u * (math.sin(a) * r))
    for i in range(n):
        mb.beam(pts[i], pts[(i + 1) % n], 0.017, 0.017, 4, mat, caps=True)
    mb.beam(Vector((cx, cy, cz)) + Vector((-r * 0.9, 0, 0)), Vector((cx, cy, cz)) + Vector((r * 0.9, 0, 0)), 0.014, 0.014, 4, mat)
    mb.beam(Vector((cx, cy, cz)), Vector((cx, cy, cz)) + u * (-r * 0.9), 0.014, 0.014, 4, mat)
    mb.box((cx, cy, cz), (0.12, 0.05, 0.08), hub)
    # column towards the dash (opposite of the wheel normal)
    nrm = Vector((0, -math.cos(t), math.sin(t)))
    mb.beam(Vector((cx, cy, cz)), Vector((cx, cy, cz)) - nrm * 0.30, 0.03, 0.035, 4, hub)


def seat(mb, x, y, floor_z, width=0.50, depth=0.50, back_h=0.62, cush_h=0.20, mat="Interior", head=True, recline=0.10, headrest_mat=None):
    """Seat facing +Y: cushion + reclined backrest (+ headrest). y = seat centre. floor_z = floor level under the seat."""
    hm = headrest_mat or mat
    mb.box((x, y, floor_z + cush_h * 0.5 + 0.08), (width, depth, cush_h), mat)
    zb = floor_z + cush_h + 0.08
    mb.block((x, y - depth * 0.5 + 0.06), zb, zb + back_h, (width, 0.14), (width - 0.06, 0.10), mat, top_shift=(-recline, 0))
    if head:
        mb.box((x, y - depth * 0.5 + 0.06 - recline, zb + back_h + 0.07), (0.20, 0.09, 0.15), hm)


# --------------------------------------------------------------------------------------------------------------
# Car wrapper
# --------------------------------------------------------------------------------------------------------------
class Car:
    def __init__(self, cid, index, wheelbase, wr, ww=0.24, ws=0.9, paint="#f2f0ea", paint2="#161b2b"):
        self.id = cid
        self.prefix = cid + "__"
        self.index = index
        self.wbase = wheelbase
        self.wr = wr
        self.ww = ww
        self.ws = ws
        clear_asset(self.prefix)
        self.coll = coll("GTA_GODOT/Vehicles/Cars")
        self.origin = workshop(1, index, 12.0)
        self.root = empty(self.prefix + "root", tuple(self.origin), collection=self.coll, size=0.4)
        self.paint = paint
        self.paint2 = paint2
        self.objs = {}
        self.lod_root = None

    # materials -------------------------------------------------------------------------------------------------
    def local_paint(self):
        for base, col in (("Paint", self.paint), ("Paint2", self.paint2)):
            spec = dict(STD[base])
            spec["color"] = col
            mat(self.prefix + base, **spec)

    def mats(self):
        """swap shared Paint/Paint2 slot materials of all my meshes to the local per-car ones"""
        self.local_paint()
        roots = [self.root] + ([self.lod_root] if getattr(self, "lod_root", None) is not None else [])
        for o in [d for r in roots for d in descendants(r)]:
            if o.type != "MESH":
                continue
            for i, m in enumerate(o.data.materials):
                if m is not None and m.name in ("Paint", "Paint2"):
                    o.data.materials[i] = bpy.data.materials[self.prefix + m.name]

    # objects -------------------------------------------------------------------------------------------------
    def mesh(self, mb, node, loc=(0, 0, 0), parent=None, smooth=None, weld=0.0):
        obj = mb.finish(self.coll, self.prefix + node, loc=loc, smooth_angle_deg=smooth, weld=weld)
        parent_to(obj, parent or self.root)
        self.objs[node] = obj
        return obj

    def node(self, name, loc, parent=None, size=0.12, display="PLAIN_AXES"):
        o = empty(self.prefix + name, loc=loc, parent=parent or self.root, collection=self.coll, size=size, display=display)
        self.objs[name] = o
        return o

    def wheel_specs(self, ws_axle=None, inset=0.26, flare=0.0):
        ws = ws_axle or self.ws
        R = self.wr + 0.07
        h = self.wbase / 2
        # only the right-hand wheel of each axle is listed (rings are symmetric); flare = fender flare width (m)
        return [(h, self.wr, R, ws - inset, flare), (-h, self.wr, R, ws - inset, flare)]

    def wheels(self, ws_front=None, ws_rear=None, segs=12, track_out=0.02, rim="Rim"):
        h = self.wbase / 2
        wf = ws_front or self.ws
        wr_ = ws_rear or self.ws
        for nm, sx, y, wsx in (("Wheel_FL", -1, h, wf), ("Wheel_FR", 1, h, wf), ("Wheel_RL", -1, -h, wr_), ("Wheel_RR", 1, -h, wr_)):
            x = sx * (wsx + track_out - self.ww * 0.5)
            o = lean_wheel(self.prefix + nm, self.wr, self.ww, sx, self.coll, seg=segs, rim=rim, loc=(x, y, self.wr))
            parent_to(o, self.root)
            self.objs[nm] = o

    def anchors(self, head=(0.62, 2.32, 0.66), tail=(0.66, -2.45, 0.74), seat_y=0.0, seat_z=0.70, rear_y=None, exit_y=None, exit_x=1.85, exhaust=(0.55, -2.5, 0.30), rear_seats=True):
        self.node("HeadlightL", (-head[0], head[1], head[2]))
        self.node("HeadlightR", (head[0], head[1], head[2]))
        self.node("TaillightL", (-tail[0], tail[1], tail[2]))
        self.node("TaillightR", (tail[0], tail[1], tail[2]))
        self.node("SeatDriver", (-0.40, seat_y, seat_z))
        self.node("SeatPassenger", (0.40, seat_y, seat_z))
        if rear_seats and rear_y is not None:
            self.node("SeatRearL", (-0.40, rear_y, seat_z))
            self.node("SeatRearR", (0.40, rear_y, seat_z))
        ey = seat_y if exit_y is None else exit_y
        self.node("ExitL", (-exit_x, ey, 0.0), display="ARROWS", size=0.2)
        self.node("ExitR", (exit_x, ey, 0.0), display="ARROWS", size=0.2)
        self.node("Exhaust", exhaust)

    def export(self, rel=None):
        """Swap local Paint/Paint2 to the shared names, export GLB, restore (atomic inside one execute call)."""
        rel = rel or ("vehicles/" + self.id)
        pairs = []
        try:
            for base in ("Paint", "Paint2"):
                loc = bpy.data.materials.get(self.prefix + base)
                sh = bpy.data.materials.get(base)
                if loc is None:
                    continue
                if sh is not None:
                    sh.name = base + "__lane1swap"
                loc.name = base
                pairs.append((base, loc, sh))
            path = export_glb(self.root, rel)
            if getattr(self, "lod_root", None) is not None:
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
def island_report(obj, verbose=True):
    """Signed volume per connected shell: negative = inside-out normals. Returns list of (verts, faces, volume)."""
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


def tri_total(root):
    bpy.context.view_layer.update()
    out = {}
    for o in descendants(root):
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            out[o.name.split("__", 1)[-1]] = len(o.data.loop_triangles)
    return out


# --------------------------------------------------------------------------------------------------------------
# LOD: separate GLB vehicles/<id>_lod.glb (same convention as lane 0): one mesh `Body`, exact outer dimensions, no interior/arches/doors.
# --------------------------------------------------------------------------------------------------------------
def lod_keys(K, y0, y1):
    out = []
    for k in sorted(K, key=lambda k: k["y"]):
        if y0 - 1e-6 <= k["y"] <= y1 + 1e-6:
            out.append(dict(k))
    return out


def build_lod(car, K, y0, y1, G, gx, boxes=(), roof_lift=0.045, glass_edges=("Glass", "Paint", "Glass", "Interior"), mat_fn=None):
    """Creates the LOD root `<id>_lod__root` (+10 m in Y of the car workshop slot) with mesh `Body`.
    boxes = [(center, size, mat)] for lights etc. (same positions as in the full Body)."""
    clear_asset(car.id + "_lod__")
    lroot = empty(car.id + "_lod__root", loc=(car.origin.x, car.origin.y + 10.0, 0.0), collection=car.coll, display="ARROWS", size=0.4)
    car.lod_root = lroot
    mb = MB("lod")
    ks = lod_keys(K, y0, y1)
    cab = (min(p[0] for p in G), max(p[0] for p in G)) if G else (9, -9)

    def mf(role, ym):
        if role in ("low", "bottom", "cham"):
            return "Trim"
        if role == "top" and cab[0] < ym < cab[1]:
            return "Interior"          # what you see through the glass instead of a painted plane
        return mat_fn(role, ym) if mat_fn else "Paint"
    sts = stations(ks, [], y0, y1)
    build_section(mb, sts, "tub", mf, cap0="Paint", cap1="Trim")
    if G:
        zmax = max(p[1] for p in G)
        G2 = [(y, z + roof_lift if z > zmax - 0.05 else z) for (y, z) in G]
        shell_yz(mb, G2, gx, list(glass_edges), "Glass")
    for (c, sz, m) in boxes:
        mb.box(c, sz, m)
    obj = mb.finish(car.coll, car.id + "_lod__Body", weld=0.0)
    parent_to(obj, lroot)
    return obj
