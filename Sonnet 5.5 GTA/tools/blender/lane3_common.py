"""
lane3_common.py - toolkit for Blender lane 3 (GTA_GODOT/Vehicles/Boats | Helicopters | Airplanes):
heli_civil, speedboat, plane_prop, heli_police, plane_jet.  Load AFTER gta_lib.py:

    exec(open(r"...\\tools\\blender\\lane3_common.py", encoding="utf8").read(), globals())

All names are prefixed l3_ / L3 so they never clash with other lanes sharing the live Blender session.
Metres, +Y forward, +X right, origin per ARCHITECTURE s7, pilot (driver) on the LEFT (-X).
Meshes are built WITHOUT welding (every shell keeps its own verts); finish() recalculates normals per closed shell.
Each asset gets local per-asset Paint/Paint2 materials ("<id>__Paint") that are swapped to the shared names at export only.
"""
import math
import bpy
import bmesh
from mathutils import Vector


def l3_lerp(a, b, t):
    return a + (b - a) * t


def l3_clamp(v, a, b):
    return max(a, min(b, v))


# --------------------------------------------------------------------------------------------------------------
# custom (non-replaced) materials used by the aircraft
# --------------------------------------------------------------------------------------------------------------
def l3_extra_mats():
    std_mat("LightGreen", color="#0f6b2c", rough=0.3, emit="#3dff7a", emit_strength=2.5)
    std_mat("ExhaustGlow", color="#ff7a20", rough=0.4, emit="#ff8a30", emit_strength=3.5)
    std_mat("RotorTip", color="#f2cf3a", rough=0.5)
    std_mat("RotorBlade", color="#1c1e22", rough=0.6, metal=0.3)
    std_mat("Rubber", color="#1b1c1f", rough=0.95)
    std_mat("Teak", color="#b88a55", rough=0.8)
    std_mat("Fabric", color="#3a4150", rough=0.95)
    std_mat("SeatBlue", color="#25324d", rough=0.9)
    std_mat("Searchlight", color="#fff4d6", rough=0.2, emit="#fff1c9", emit_strength=5.0)


# --------------------------------------------------------------------------------------------------------------
# asset wrapper
# --------------------------------------------------------------------------------------------------------------
class L3Asset:
    def __init__(self, aid, index, collection, paint="#f2f0ea", paint2="#2f9c95", spacing=25.0):
        self.id = aid
        self.prefix = aid + "__"
        clear_asset(self.prefix)
        self.coll = coll(collection)
        self.origin = workshop(3, index, spacing)
        self.root = empty(self.prefix + "root", tuple(self.origin), collection=self.coll, display="ARROWS", size=0.6)
        self.paint = paint
        self.paint2 = paint2
        self.objs = {}
        for n in ("Paint", "Paint2", "Glass", "Trim", "Chrome", "LightHead", "LightTail", "LightAmber", "LightBlue", "LightRed",
                  "Interior", "Plate", "Tire", "Rim", "Metal", "MetalDark", "LampGlow", "Wood", "Concrete"):
            std_mat(n)
        l3_extra_mats()

    def local_paint(self):
        for base, col in (("Paint", self.paint), ("Paint2", self.paint2)):
            spec = dict(STD[base])
            spec["color"] = col
            mat(self.prefix + base, **spec)

    def mats(self):
        """swap shared Paint/Paint2 slot materials of all my meshes to the local per-asset ones (preview colours)"""
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

    def part(self, mb, node, pivot, parent=None, smooth=None):
        """mesh built in ROOT-local coordinates, re-centred so that its object origin sits on `pivot`."""
        mb.translate((-pivot[0], -pivot[1], -pivot[2]))
        return self.mesh(mb, node, loc=pivot, parent=parent, smooth=smooth)

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
                    sh.name = base + "__lane3swap"
                loc.name = base
                pairs.append((base, loc, sh))
            path = export_glb(self.root, rel)
        finally:
            for base, loc, sh in pairs:
                loc.name = self.prefix + base
                if sh is not None:
                    sh.name = base
        return path


# --------------------------------------------------------------------------------------------------------------
# QA
# --------------------------------------------------------------------------------------------------------------
def l3_islands(obj, verbose=True):
    """Signed volume per connected shell: negative = inside-out normals (open shells report small values)."""
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


def l3_tris(root):
    bpy.context.view_layer.update()
    out = {}
    for o in descendants(root):
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            out[o.name.split("__", 1)[-1]] = len(o.data.loop_triangles)
    out["TOTAL"] = sum(out.values())
    return out


def l3_qa(A):
    """tri counts, inside-out shells and bounding box for the whole asset"""
    print("TRIS", l3_tris(A.root))
    for o in descendants(A.root):
        if o.type == "MESH":
            l3_islands(o)
    stats(A.root)


# --------------------------------------------------------------------------------------------------------------
# lofts / rings
# --------------------------------------------------------------------------------------------------------------
def l3_loft(mb, rings, mats="Paint", segmats=None, cap0=None, cap1=None):
    """Skin rings (lists of 3D points, same count) with quads. mats: str or per-edge list (point i -> i+1) used for every
    segment unless segmats (one entry per segment, str or per-edge list) is given."""
    V = [[mb.v(p) for p in r] for r in rings]
    n = len(V[0])
    for k in range(len(V) - 1):
        m = segmats[k] if segmats else mats
        for i in range(n):
            j = (i + 1) % n
            mm = m if isinstance(m, str) else m[i]
            mb.face([V[k][i], V[k][j], V[k + 1][j], V[k + 1][i]], mm)
    if cap0:
        mb.face(list(reversed(V[0])), cap0)
    if cap1:
        mb.face(V[-1], cap1)
    return V


def l3_ring_cab(y, hw, zb, zbelt, zs, zt, ht, cb=0.14, tum=0.96, xc=0.0):
    """10-point fuselage section: bottom(2), lower chamfer, belt, shoulder, roof(2), shoulder, belt, lower chamfer.
    Edge i = point i -> i+1: 0 bottom, 1 lower chamfer R, 2 lower side R, 3 upper side R (windows), 4 roof chamfer R,
    5 roof, 6 roof chamfer L, 7 upper side L, 8 lower side L, 9 lower chamfer L."""
    hs = hw * tum
    ht = min(ht, hs - 0.01)
    cb = max(0.01, min(cb, (zbelt - zb) * 0.7, hw * 0.45))
    pts = [(-(hw - cb), zb), (hw - cb, zb), (hw, zb + cb), (hw, zbelt), (hs, zs), (ht, zt), (-ht, zt), (-hs, zs), (-hw, zbelt), (-hw, zb + cb)]
    return [(xc + x, y, z) for x, z in pts]


def l3_ring_oct(y, rx, zc, rz, n=8, xc=0.0, rot_deg=22.5):
    """regular-ish n-gon section (round-ish tubes: tail booms, nacelles, nose cones)"""
    pts = []
    for i in range(n):
        a = math.radians(rot_deg) + 2 * math.pi * i / n
        pts.append((xc + rx * math.cos(a), y, zc + rz * math.sin(a)))
    return pts


def l3_bar(mb, cs, tdir, ndir, ws, hs, mats, cap0=None, cap1=None):
    """Tapered rectangular bar through centres cs (list of >=2 points). tdir/ndir: unit vectors (or lists of them, one per
    centre) for width (chord) and height (thickness); ws/hs: widths / heights per centre. mats: str or per-segment list."""
    rings = []
    for k, c in enumerate(cs):
        c = Vector(c)
        t = Vector(tdir[k] if isinstance(tdir, (list, tuple)) and isinstance(tdir[0], (list, tuple, Vector)) else tdir).normalized()
        n = Vector(ndir[k] if isinstance(ndir, (list, tuple)) and isinstance(ndir[0], (list, tuple, Vector)) else ndir).normalized()
        w, h = ws[k] / 2, hs[k] / 2
        rings.append([tuple(c - t * w - n * h), tuple(c + t * w - n * h), tuple(c + t * w + n * h), tuple(c - t * w + n * h)])
    segm = None
    if isinstance(mats, (list, tuple)):
        segm = list(mats)
        m0 = mats[0]
    else:
        m0 = mats
    return l3_loft(mb, rings, m0, segm, cap0 if cap0 else m0, cap1 if cap1 else (mats[-1] if segm else mats))


def l3_blades(mb, n, r0, r1, chord0, chord1, thick, cone_deg, mat, tip_mat, tip_len, z=0.0, a0_deg=0.0, plane="xy", twist_deg=0.0):
    """n blades radiating from the origin. plane 'xy' = rotor disc horizontal (spins about Z), 'xz' = disc in X/Z (spins about Y),
    'yz' = disc in Y/Z (spins about X). cone_deg lifts the tips out of the disc plane (towards +Z / +Y / +X)."""
    cone = math.tan(math.radians(cone_deg))
    for k in range(n):
        a = math.radians(a0_deg) + 2 * math.pi * k / n
        ca, sa = math.cos(a), math.sin(a)
        if plane == "xy":
            d, t0, nrm, up = Vector((ca, sa, 0)), Vector((-sa, ca, 0)), Vector((0, 0, 1)), Vector((0, 0, 1))
            base = Vector((0, 0, z))
        elif plane == "xz":
            d, t0, nrm, up = Vector((ca, 0, sa)), Vector((0, 1, 0)), Vector((-sa, 0, ca)), Vector((0, 1, 0))
            base = Vector((0, z, 0))
        else:
            d, t0, nrm, up = Vector((0, ca, sa)), Vector((1, 0, 0)), Vector((0, -sa, ca)), Vector((1, 0, 0))
            base = Vector((z, 0, 0))
        rt = r1 - tip_len
        rs = [r0, rt, r1]
        cs = [base + d * r + up * (r * cone) for r in rs]
        chs = [l3_lerp(chord0, chord1, (r - r0) / (r1 - r0)) for r in rs]
        tw = [l3_lerp(0.0, twist_deg, (r - r0) / (r1 - r0)) for r in rs]
        tdirs = []
        ndirs = []
        for ang in tw:
            c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
            tdirs.append(t0 * c + nrm * s)
            ndirs.append(nrm * c - t0 * s)
        l3_bar(mb, cs, tdirs, ndirs, chs, [thick] * 3, [mat, tip_mat], mat, tip_mat)


# --------------------------------------------------------------------------------------------------------------
# wings: stations are dicts(x, y (leading edge y), z (leading edge z), c (chord), t (thickness)); x >= 0 (mirrored by side)
# --------------------------------------------------------------------------------------------------------------
L3_TH = [(0.0, 0.0), (0.10, 0.80), (0.38, 1.0), (0.75, 0.45), (1.0, 0.0)]


def l3_thk(s):
    for (s0, t0), (s1, t1) in zip(L3_TH, L3_TH[1:]):
        if s <= s1:
            return t0 + (t1 - t0) * (s - s0) / (s1 - s0)
    return 0.0


def l3_st_at(sts, x):
    for a, b in zip(sts, sts[1:]):
        if a["x"] - 1e-6 <= x <= b["x"] + 1e-6:
            u = (x - a["x"]) / (b["x"] - a["x"]) if b["x"] > a["x"] else 0.0
            return {k: l3_lerp(a[k], b[k], u) for k in ("x", "y", "z", "c", "t")}
    return dict(sts[-1])


def l3_af(st, s, up, side=1.0, asym=0.6):
    """point of the aerofoil at chord fraction s (0 = leading edge) on the upper / lower surface"""
    y = st["y"] - s * st["c"]
    th = l3_thk(s) * st["t"]
    z = st["z"] + (th * asym if up else -th * (1.0 - asym))
    return (side * st["x"], y, z)


def l3_wing(mb, sts, y_h, side, mats=("Paint", "Paint", "Paint", "Trim", "Paint", "Paint", "Paint"), ss=(0.10, 0.36), asym=0.6, cap_root=None, cap_tip="Paint"):
    """Main wing loft with a blunt trailing edge at the hinge line y = y_h (fixed for the whole span so that control
    surfaces hinge about the X axis). Edge mats: LE>U1, U1>U2, U2>hinge-top, blunt TE, hinge>L2, L2>L1, L1>LE."""
    rings = []
    for st in sts:
        sc = (st["y"] - y_h) / st["c"]
        assert sc > ss[-1] + 0.05, "wing too thin at the hinge: %s" % sc
        pts = [l3_af(st, 0.0, True, side, asym)]
        for s in ss:
            pts.append(l3_af(st, s, True, side, asym))
        pts.append(l3_af(st, sc, True, side, asym))
        pts.append(l3_af(st, sc, False, side, asym))
        for s in reversed(ss):
            pts.append(l3_af(st, s, False, side, asym))
        rings.append(pts)
    return l3_loft(mb, rings, list(mats[:len(rings[0])]), None, cap_root, cap_tip)


def l3_wedge(mb, sts, y_h, x0, x1, side, mats="Paint", cap="Paint", asym=0.6):
    """Trailing-edge wedge (aileron / flap / elevator) between the hinge line and the trailing edge, from span x0 to x1."""
    rings = []
    for x in (x0, x1):
        st = l3_st_at(sts, x)
        sc = (st["y"] - y_h) / st["c"]
        rings.append([l3_af(st, sc, True, side, asym), l3_af(st, 1.0, True, side, asym), l3_af(st, sc, False, side, asym)])
    return l3_loft(mb, rings, mats, None, cap, cap)


def l3_hinge_pt(sts, y_h, xm, side=1.0, asym=0.6):
    st = l3_st_at(sts, xm)
    sc = (st["y"] - y_h) / st["c"]
    u = l3_af(st, sc, True, side, asym)
    lo = l3_af(st, sc, False, side, asym)
    return ((u[0] + lo[0]) / 2, y_h, (u[2] + lo[2]) / 2)


def l3_fin(mb, sts, y_h, mats="Paint", cap_top="Paint", cap_bot=None):
    """Vertical fin/rudder-post: sts = list of dicts(z, y (leading edge y), w (thickness), [xc]) from low z to high z;
    the trailing edge is blunt at the hinge line y = y_h."""
    rings = []
    for s in sts:
        yf = s["y"] - 0.35 * (s["y"] - y_h)
        xc = s.get("xc", 0.0)
        w = s["w"] / 2
        rings.append([(xc, s["y"], s["z"]), (xc + w, yf, s["z"]), (xc + w, y_h, s["z"]), (xc - w, y_h, s["z"]), (xc - w, yf, s["z"])])
    return l3_loft(mb, rings, mats, None, cap_bot, cap_top)


def l3_rudder(mb, y_h, y_te0, y_te1, z0, z1, w0, w1, mats="Paint2", xc=0.0):
    """Rudder wedge: hinge line vertical at y = y_h, trailing edge at y_te0 (bottom) / y_te1 (top)."""
    r0 = [(xc - w0 / 2, y_h, z0), (xc, y_te0, z0), (xc + w0 / 2, y_h, z0)]
    r1 = [(xc - w1 / 2, y_h, z1), (xc, y_te1, z1), (xc + w1 / 2, y_h, z1)]
    return l3_loft(mb, [r0, r1], mats, None, mats, mats)


# --------------------------------------------------------------------------------------------------------------
# misc primitives
# --------------------------------------------------------------------------------------------------------------
def l3_seam_v(mb, x, y, z0, z1, mat="Trim", w=0.014, d=0.010):
    mb.box((x, y, (z0 + z1) / 2), (d, w, z1 - z0), mat)


def l3_seam_h(mb, x, y0, y1, z, mat="Trim", h=0.014, d=0.010):
    mb.box((x, (y0 + y1) / 2, z), (d, y1 - y0, h), mat)


def l3_seat(mb, x, y, floor_z, width=0.50, depth=0.50, back_h=0.62, cush_h=0.20, mat="Interior", recline=0.10, head=True, trim=None):
    """Seat facing +Y: cushion + reclined backrest (+ headrest). y = seat centre, floor_z = floor level under the seat."""
    mb.box((x, y, floor_z + cush_h * 0.5 + 0.08), (width, depth, cush_h), mat)
    zb = floor_z + cush_h + 0.08
    mb.block((x, y - depth * 0.5 + 0.06), zb, zb + back_h, (width, 0.14), (width - 0.06, 0.10), trim or mat, top_shift=(-recline, 0))
    if head:
        mb.box((x, y - depth * 0.5 + 0.06 - recline, zb + back_h + 0.07), (0.20, 0.09, 0.15), mat)


def l3_revolve_x(mb, profile, seg, mat, s=1.0):
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


def l3_revolve_y(mb, profile, seg, mat, c=(0, 0, 0)):
    """Revolve profile [(y, radius)] about the Y axis through point c."""
    rings = []
    for (y, rad) in profile:
        if rad < 1e-6:
            rings.append(mb.v((c[0], c[1] + y, c[2])))
        else:
            rings.append([mb.v((c[0] + rad * math.cos(2 * math.pi * k / seg), c[1] + y, c[2] + rad * math.sin(2 * math.pi * k / seg))) for k in range(seg)])
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


def l3_wheel(name, r, w, s, collection, seg=12, tire="Tire", rim="Rim", hub="Chrome", dish="MetalDark", loc=(0, 0, 0)):
    """wheel, spin axis X, origin = wheel centre; s=+1 outer face towards +X, s=-1 towards -X"""
    b = MB(name)
    l3_revolve_x(b, [(-0.5 * w, 0.70 * r), (-0.44 * w, 0.93 * r), (-0.20 * w, 1.0 * r), (0.20 * w, 1.0 * r), (0.44 * w, 0.93 * r), (0.5 * w, 0.70 * r)], seg, tire, s)
    l3_revolve_x(b, [(-0.5 * w, 0.70 * r), (-0.40 * w, 0.0)], seg, dish, s)
    l3_revolve_x(b, [(0.5 * w, 0.70 * r), (0.40 * w, 0.52 * r), (0.30 * w, 0.0)], seg, rim, s)
    b.cyl((s * 0.40 * w, 0, 0), r * 0.22, 0.05, 6, hub, axis="X")
    return b.finish(collection, name, loc=loc, smooth_angle_deg=40, weld=0.0)


def l3_steering(mb, center, tilt_deg=25, r=0.17, mat="Trim", hub="Interior", n=8):
    """steering wheel facing +Y-back (towards the driver sitting behind it); tilt 0 = wheel plane vertical"""
    cx, cy, cz = center
    t = math.radians(tilt_deg)
    u = Vector((0, math.sin(t), math.cos(t)))
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        pts.append(Vector((cx, cy, cz)) + Vector((1, 0, 0)) * (math.cos(a) * r) + u * (math.sin(a) * r))
    for i in range(n):
        mb.beam(pts[i], pts[(i + 1) % n], 0.016, 0.016, 4, mat, caps=True)
    mb.beam(Vector((cx, cy, cz)) + Vector((-r * 0.9, 0, 0)), Vector((cx, cy, cz)) + Vector((r * 0.9, 0, 0)), 0.013, 0.013, 4, mat)
    mb.box((cx, cy, cz), (0.10, 0.05, 0.07), hub)
    nrm = Vector((0, -math.cos(t), math.sin(t)))
    mb.beam(Vector((cx, cy, cz)), Vector((cx, cy, cz)) - nrm * 0.26, 0.028, 0.032, 4, hub)
