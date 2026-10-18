"""
weapons_common.py - helpers for lane 5 (Weapons) of the Halcyon Bay Blender pipeline.
Load AFTER gta_lib.py (same exec namespace):
    exec(open(r"...\tools\blender\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"...\tools\blender\weapons_common.py", encoding="utf8").read(), globals())

Weapon coordinates (Blender, metres): origin = primary grip (palm), barrel toward +Y, Z up, +X = weapon's right side.
Every part is built in weapon space; part objects keep origin (0,0,0) unless a pivot is passed (Cylinder, Hammer...).
Each primitive is its own closed shell (finish(weld=0)) so overlapping primitives never corrupt face orientation.
"""
import math
from mathutils import Vector

LANE = 5
WSPACE = 3.0
WCOLL = "GTA_GODOT/Weapons"

WMATS = {
    "GunAccent":   dict(color="#ee8a2b", rough=0.6),
    "GunAccent2":  dict(color="#34e0ff", rough=0.5),
    "GunRed":      dict(color="#d93a3a", rough=0.6),
    "GunGreen":    dict(color="#4f9d52", rough=0.6),
    "SightDot":    dict(color="#a8ff80", rough=0.4, emit="#6dff3a", emit_strength=2.0),
    "ScopeLens":   dict(color="#12304f", rough=0.05, emit="#2f9cff", emit_strength=0.9),
    "GrenadeBody": dict(color="#4d5a3a", rough=0.7, metal=0.2),
    "GunTan":      dict(color="#b59a6b", rough=0.8),
    "WoodDark":    dict(color="#5a3a26", rough=0.85),
    "GunOlive":    dict(color="#5d6a4a", rough=0.85),
}


def wmats():
    ensure_std_mats(["Gun", "GunLight", "Grip", "Wood", "Metal", "MetalDark", "Trim", "LampGlow", "Chrome"])
    for n, s in WMATS.items():
        mat(n, **s)


# ---------------------------------------------------------------------------------------------------------------
# geometry helpers
# ---------------------------------------------------------------------------------------------------------------
def inset_poly(pts, d):
    """Inset a CCW polygon [(y,z)...] by distance d (miter). Works for mild concavity."""
    n = len(pts)
    out = []
    for i in range(n):
        p0 = Vector(pts[i - 1])
        p1 = Vector(pts[i])
        p2 = Vector(pts[(i + 1) % n])
        e1 = p1 - p0
        e2 = p2 - p1
        if e1.length < 1e-9 or e2.length < 1e-9:
            out.append(tuple(p1))
            continue
        e1.normalize()
        e2.normalize()
        n1 = Vector((-e1.y, e1.x))
        n2 = Vector((-e2.y, e2.x))
        k = 1.0 + n1.dot(n2)
        m = n1 + n2
        if k < 0.35:
            m = n1
            k = 1.0
        q = p1 + m * (d / k)
        out.append((q.x, q.y))
    return out


def slab(b, prof, hw, bev=0.0, mat="Gun", xc=0.0):
    """Side-profile extrusion (profile = [(y,z)...] CCW seen from +X) across x in [xc-hw, xc+hw] with chamfered
    edges (bev = chamfer size). bev=0 -> plain profile_extrude."""
    if bev <= 0:
        return b.profile_extrude(prof, hw, mat, xc)
    inner = inset_poly(prof, bev)
    n = len(prof)
    rings = [(xc - hw, inner), (xc - hw + bev, prof), (xc + hw - bev, prof), (xc + hw, inner)]
    V = [[b.v((x, p[0], p[1])) for p in poly] for x, poly in rings]
    b.face(list(reversed(V[0])), mat)
    b.face(V[3], mat)
    for k in range(3):
        for i in range(n):
            j = (i + 1) % n
            b.face([V[k][i], V[k][j], V[k + 1][j], V[k + 1][i]], mat)
    return V


def bx(b, x, y, z, mat="Gun"):
    """Axis-aligned box from ranges: x=(x0,x1), y=(y0,y1), z=(z0,z1)."""
    b.box(((x[0] + x[1]) / 2, (y[0] + y[1]) / 2, (z[0] + z[1]) / 2),
          (abs(x[1] - x[0]), abs(y[1] - y[0]), abs(z[1] - z[0])), mat)


def tbox(b, x, y, z, mat="Gun", top_x=None, top_y=None, shift_y=0.0):
    """Tapered box: bottom ranges x,y at z0; top face scaled to top_x/top_y (ranges) at z1."""
    cx, cy = (x[0] + x[1]) / 2, (y[0] + y[1]) / 2
    bs = (abs(x[1] - x[0]), abs(y[1] - y[0]))
    tx = top_x if top_x is not None else x
    ty = top_y if top_y is not None else y
    ts = (abs(tx[1] - tx[0]), abs(ty[1] - ty[0]))
    sh = ((tx[0] + tx[1]) / 2 - cx, (ty[0] + ty[1]) / 2 - cy)
    b.block((cx, cy), z[0], z[1], bs, ts, mat, top_shift=sh)


def rev(b, st, cx=0.0, cz=0.0, seg=8, mat="Gun", rot=0.0, caps=(True, True)):
    """Solid of revolution about an axis parallel to Y through (cx, cz). st = [(y, r) | (y, rx, rz), ...] rear->front.
    Stations with a tiny radius work as cone tips. rot = angular offset in degrees."""
    rings = []
    r0 = math.radians(rot)
    for s in st:
        y = s[0]
        rx = s[1]
        rz = s[2] if len(s) > 2 else s[1]
        rings.append([(cx + rx * math.cos(2 * math.pi * i / seg + r0), y, cz + rz * math.sin(2 * math.pi * i / seg + r0))
                      for i in range(seg)])
    return b.loft(rings, mat, True, caps[0], caps[1])


def revz(b, st, cx=0.0, cy=0.0, seg=8, mat="Gun", rot=0.0, caps=(True, True)):
    """Solid of revolution about a vertical (Z) axis through (cx, cy). st = [(z, r) | (z, rx, ry), ...] bottom->top."""
    rings = []
    r0 = math.radians(rot)
    for s_ in st:
        z = s_[0]
        rx = s_[1]
        ry = s_[2] if len(s_) > 2 else s_[1]
        rings.append([(cx + rx * math.cos(2 * math.pi * i / seg + r0), cy + ry * math.sin(2 * math.pi * i / seg + r0), z) for i in range(seg)])
    return b.loft(rings, mat, True, caps[0], caps[1])


def oct_ring(y, cx, cz, hw, hh, ch):
    """Chamfered-rectangle cross-section ring (8 points) in the XZ plane at height y."""
    return [(cx + hw - ch, y, cz - hh), (cx + hw, y, cz - hh + ch), (cx + hw, y, cz + hh - ch), (cx + hw - ch, y, cz + hh),
            (cx - hw + ch, y, cz + hh), (cx - hw, y, cz + hh - ch), (cx - hw, y, cz - hh + ch), (cx - hw + ch, y, cz - hh)]


def octy(b, st, cx=0.0, cz=0.0, ch=0.01, mat="Gun", caps=(True, True)):
    """Chamfered-rectangle tube along Y. st = [(y, half_width, half_height), ...] rear->front."""
    rings = [oct_ring(y, cx, cz, hw, hh, ch) for (y, hw, hh) in st]
    return b.loft(rings, mat, True, caps[0], caps[1])


def grip_strips(b, back_fn, front_fn, rake, zs, hx, mat="Gun", inset=0.005, th=0.0021, hw=0.0003):
    """Texture strips perpendicular to a raked grip axis on both sides (x = +-hx)."""
    for z in zs:
        yb, yf = back_fn(z) + inset, front_fn(z) - inset
        dz = rake * (yf - yb)
        st = [(yb, z), (yf, z - dz), (yf, z - dz + th), (yb, z + th)]
        b.profile_extrude(st, hw, mat, hx)
        b.profile_extrude(st, hw, mat, -hx)


def rail_teeth(b, y0, y1, n, z0, z1, hw, tooth=0.5, mat="GunLight"):
    """n raised rail blocks between y0..y1 (tooth = fraction of the pitch that is raised)."""
    pitch = (y1 - y0) / n
    for k in range(n):
        ya = y0 + k * pitch
        bx(b, (-hw, hw), (ya, ya + pitch * tooth), (z0, z1), mat)


def ribbon_xz(b, pts, width_y, thick, mat="Metal", y0=0.0):
    """Thin strip following a polyline of (x, z) points (side-on plate bent in the XZ plane), width along Y."""
    P = [Vector(p) for p in pts]
    n = len(P)
    rings = []
    for i in range(n):
        if i == 0:
            t = P[1] - P[0]
        elif i == n - 1:
            t = P[-1] - P[-2]
        else:
            t = (P[i] - P[i - 1]).normalized() + (P[i + 1] - P[i]).normalized()
        t.normalize()
        nrm = Vector((-t.y, t.x))      # in-plane normal (x,z)
        a = P[i] + nrm * (thick / 2)
        c = P[i] - nrm * (thick / 2)
        w = width_y / 2
        rings.append([(a.x, y0 - w, a.y), (a.x, y0 + w, a.y), (c.x, y0 + w, c.y), (c.x, y0 - w, c.y)])
    return b.loft(rings, mat, True, True, True)


def sweep(b, path, radii, seg=6, mat="Metal", rot=0.0, caps=(True, True), squash=1.0):
    """Tube along a polyline `path` (list of 3D points) with per-point radius (float or list). squash scales the
    second axis of the ring (flat bars)."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    if not isinstance(radii, (list, tuple)):
        radii = [radii] * n
    tans = []
    for i in range(n):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == n - 1:
            t = pts[-1] - pts[-2]
        else:
            t = (pts[i] - pts[i - 1]).normalized() + (pts[i + 1] - pts[i]).normalized()
        tans.append(t.normalized())
    ref = Vector((1, 0, 0))
    u = ref - tans[0] * ref.dot(tans[0])
    u.normalize()
    rings = []
    r0 = math.radians(rot)
    for i in range(n):
        u = u - tans[i] * u.dot(tans[i])
        u.normalize()
        w = tans[i].cross(u)
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg + r0
            ring.append(pts[i] + u * (math.cos(a) * radii[i]) + w * (math.sin(a) * radii[i] * squash))
        rings.append(ring)
    return b.loft(rings, mat, True, caps[0], caps[1])


def strips_x(b, xs, y0, y1, z0, z1, mat="MetalDark", t=0.0012):
    """Thin panel-line strips proud of the side faces at |x| = xs (both sides), spanning y0..y1 and z0..z1."""
    for sgn in (1, -1):
        bx(b, (sgn * xs, sgn * (xs + t)) if sgn > 0 else (-xs - t, -xs), (y0, y1), (z0, z1), mat)


def ring_grooves(b, ys, r, w=0.004, cx=0.0, cz=0.0, seg=8, mat="MetalDark", rot=0.0):
    """Raised bands around a Y-axis tube at the given y positions."""
    for y in ys:
        rev(b, [(y - w / 2, r), (y + w / 2, r)], cx, cz, seg, mat, rot)


# ---------------------------------------------------------------------------------------------------------------
# weapon context
# ---------------------------------------------------------------------------------------------------------------
class Wpn:
    def __init__(self, aid, index):
        self.aid = aid
        self.pre = aid + SEP
        self.index = index
        clear_asset(self.pre)
        wmats()
        self.col = coll(WCOLL)
        loc = workshop(LANE, index, WSPACE)
        self.root = empty(self.pre + "root", tuple(loc), collection=self.col, size=0.03)
        self.parts = {}

    def mb(self, node="Body"):
        return MB(self.pre + node)

    def part(self, b, node="Body", loc=(0, 0, 0), smooth=None):
        o = b.finish(self.col, self.pre + node, loc=loc, parent=self.root, weld=0, smooth_angle_deg=smooth)
        self.parts[node] = o
        return o

    def mark(self, node, loc, rot=(0, 0, 0)):
        return empty(self.pre + node, tuple(loc), tuple(rot), parent=self.root, collection=self.col, size=0.02)

    def report(self):
        info = stats(self.root, verbose=False)
        print(self.aid, "tris", info["tris"], "size", info["size"], "min", info["min"], "max", info["max"],
              "mats", info["materials"], "empties", len(info["empties"]))
        return info


def ref_palm(name="wpnref__palm", loc=(-0.045, 0.0, -0.01), size=(0.02, 0.10, 0.09)):
    """Hand-sized reference (palm block ~9 cm wide) for grip scale checks; not part of any asset. Remove with clear_asset('wpnref__')."""
    clear_asset("wpnref__")
    ensure_std_mats(["Skin"])
    b = MB(name)
    b.box((0, 0, 0), size, "Skin")
    o = b.finish(coll(WCOLL), name, loc=loc, weld=0)
    return o
