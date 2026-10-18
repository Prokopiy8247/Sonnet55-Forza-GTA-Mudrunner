"""
lane10_lib.py - helpers for Blender lane 10 (Nature + pickups + parachute/scuba items). Load AFTER gta_lib.py:

    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\lane10_lib.py", encoding="utf8").read(), globals())

Conventions: asset id = lowercase ("palm_a"); objects "<id>__<Node>", root "<id>__root" in workshop(10, slot, 14).
Origin = base centre on the ground, front +Y. Meshes are flat shaded, deterministic (seeded) and idempotent.
"""
import bpy
import bmesh
import math
import random
from mathutils import Vector

LANE = 10
STEP = 14.0
NAT = "GTA_GODOT/Nature"
VFX = "GTA_GODOT/VFX_HelperMeshes"

# slot index per asset (big trees get 28 m gaps so look() renders stay uncluttered)
SLOT = {
    "palm_a": 0, "tree_oak_a": 2, "tree_pine_a": 4, "palm_b": 6, "tree_oak_b": 8, "tree_pine_b": 10, "tree_birch": 12,
    "tree_dead": 14,
    "bush_a": 16, "bush_b": 17, "bush_c": 18, "hedge_segment": 19, "rock_a": 20, "rock_b": 21, "rock_c": 22, "rock_d": 23,
    "boulder_large": 24, "cliff_chunk": 26, "grass_tuft": 28, "flower_patch": 29, "reeds": 30, "log": 31, "stump": 32,
    "driftwood": 33, "shell": 34, "sand_dune_patch": 35,
    "palm_a_lod": 40, "tree_oak_a_lod": 41, "tree_pine_a_lod": 42, "palm_b_lod": 43, "tree_oak_b_lod": 44,
    "tree_pine_b_lod": 45, "tree_birch_lod": 46,
    "pickup_cash": 50, "pickup_health": 51, "pickup_armor": 52, "pickup_ammo": 53, "pickup_weapon": 54,
    "pickup_parachute": 55, "scuba_tank": 56, "scuba_gear": 57, "parachute_pack": 58, "parachute_canopy": 60, "life_vest": 62,
}

# ---------------------------------------------------------------------------------------------------------------
# Lane-10 materials (custom names; STD names Leaf / LeafLight / Bark / Rock / Sand / Accent / Trim ... are reused)
# ---------------------------------------------------------------------------------------------------------------
M10 = {
    "RockPale":    dict(color="#948f82", rough=0.95),
    "RockMid":     dict(color="#78736a", rough=0.95),
    "DuneSand":    dict(color="#d4c090", rough=0.98),
    "RockShade":   dict(color="#57534c", rough=0.95),
    "BarkPale":    dict(color="#9d8668", rough=0.9),       # palm trunk rings / sun-bleached wood
    "BirchWhite":  dict(color="#e4dfd2", rough=0.85),
    "BarkMid":     dict(color="#7a6650", rough=0.92),
    "BarkDark":    dict(color="#3f2d21", rough=0.95),
    "WoodCut":     dict(color="#d2a672", rough=0.85),      # cut log faces
    "LeafDeep":    dict(color="#2f6a3e", rough=0.9),
    "LeafYellow":  dict(color="#b8b84a", rough=0.9),
    "PalmLeaf":    dict(color="#5c9a4a", rough=0.85),
    "PalmLeafLt":  dict(color="#93bf58", rough=0.85),
    "FlowerPink":  dict(color="#ff6fae", rough=0.8),
    "FlowerWhite": dict(color="#f4f0e4", rough=0.8),
    "FlowerYellow": dict(color="#f5cf3f", rough=0.8),
    "FlowerBlue":  dict(color="#6f8cff", rough=0.8),
    "ReedGreen":   dict(color="#8aa656", rough=0.9),
    "ReedDry":     dict(color="#c4b273", rough=0.9),
    "CattailBrown": dict(color="#6b4a30", rough=0.9),
    "ShellPink":   dict(color="#f2c4b4", rough=0.5),
    "ShellWhite":  dict(color="#f2eadb", rough=0.5),
    "SandWet":     dict(color="#b09b70", rough=0.98),
    # pickups / items
    "CashGreen":   dict(color="#5aa56a", rough=0.7),
    "CashDark":    dict(color="#3a7a4c", rough=0.7),
    "Paper":       dict(color="#eee8d2", rough=0.8),
    "MedWhite":    dict(color="#f2f0ea", rough=0.45),
    "PickupGreen": dict(color="#4fff8a", rough=0.3, emit="#4fff8a", emit_strength=3.0),
    "PickupRed":   dict(color="#ff3b3b", rough=0.3, emit="#ff3b3b", emit_strength=3.5),
    "PickupBlue":  dict(color="#34a8ff", rough=0.3, emit="#34a8ff", emit_strength=3.5),
    "PickupAmber": dict(color="#ffb347", rough=0.3, emit="#ffb347", emit_strength=3.5),
    "PickupMagenta": dict(color="#ff3d9a", rough=0.3, emit="#ff3d9a", emit_strength=3.5),
    "PickupCyan":  dict(color="#34e0ff", rough=0.3, emit="#34e0ff", emit_strength=3.5),
    "Olive":       dict(color="#59693a", rough=0.7, metal=0.2),
    "OliveDark":   dict(color="#3b4727", rough=0.75, metal=0.2),
    "Brass":       dict(color="#d4a443", rough=0.35, metal=0.9),
    "VestNavy":    dict(color="#27385c", rough=0.8),
    "VestSteel":   dict(color="#5a6574", rough=0.6, metal=0.4),
    "CrateGrey":   dict(color="#3a3f48", rough=0.6, metal=0.5),
    "PackOrange":  dict(color="#ee6a2b", rough=0.8),
    "PackNavy":    dict(color="#26324d", rough=0.85),
    "Strap":       dict(color="#22252b", rough=0.9),
    "Webbing":     dict(color="#d9d2bd", rough=0.9),
    "TankYellow":  dict(color="#f2c52a", rough=0.5, metal=0.08),
    "TankBand":    dict(color="#25324d", rough=0.5, metal=0.3),
    "HoseBlack":   dict(color="#16181b", rough=0.7),
    "Silicone":    dict(color="#1c3a52", rough=0.6),
    "MaskLens":    dict(color="#9fe8f5", rough=0.05, alpha=0.5, emit="#34e0ff", emit_strength=0.6),
    "LifeVestOrange": dict(color="#f26a21", rough=0.75),
    "Reflective":  dict(color="#e9ecef", rough=0.3, emit="#e9ecef", emit_strength=0.5),
    "CanopyA":     dict(color="#f0603c", rough=0.7),
    "CanopyB":     dict(color="#f2eee2", rough=0.7),
    "CanopyC":     dict(color="#34c9d8", rough=0.7),
    "LineCord":    dict(color="#1c1e22", rough=0.8),
}


def ensure_m10():
    for n, s in M10.items():
        mat(n, **s)
    for n in ("Leaf", "LeafLight", "Bark", "Rock", "Sand", "Accent", "Trim", "Metal", "MetalDark", "Chrome", "Wood", "Glass",
              "Plate", "Neon", "NeonCyan", "LightAmber", "LightRed", "LampGlow"):
        std_mat(n)


ensure_m10()


# ---------------------------------------------------------------------------------------------------------------
# Asset wrapper
# ---------------------------------------------------------------------------------------------------------------
def slot_pos(aid):
    return workshop(LANE, SLOT[aid], STEP)


class Asset:
    def __init__(self, aid, cpath=NAT):
        self.aid = aid
        clear_asset(aid + "__")
        self.coll = coll(cpath)
        self.root = empty(aid + "__root", loc=slot_pos(aid), collection=self.coll, size=0.3)

    def name(self, node):
        return self.aid + "__" + node

    def mesh(self, b, node, pivot=None, **kw):
        """pivot=(x,y,z): put the mesh object's origin there (vertices are shifted back) so Godot can rotate the node about it (wind sway)."""
        if pivot is not None:
            b.translate((-pivot[0], -pivot[1], -pivot[2]))
            return b.finish(self.coll, name=self.name(node), parent=self.root, loc=tuple(pivot), **kw)
        return b.finish(self.coll, name=self.name(node), parent=self.root, **kw)

    def anchor(self, node, loc=(0, 0, 0), rot=(0, 0, 0)):
        return empty(self.name(node), loc=loc, rot_deg=rot, parent=self.root, collection=self.coll)

    def report(self):
        info = stats(self.root, verbose=False)
        nm = {o.name: nonmanifold_report(o) for o in descendants(self.root) if o.type == "MESH"}
        print(self.aid, "tris", info["tris"], "size", info["size"], "min", info["min"], "max", info["max"],
              "mats", info["materials"], "nonmanifold", nm)
        return info


def export_asset(aid, rel=None, cat="nature"):
    root = bpy.data.objects[aid + "__root"]
    return export_glb(root, rel or (cat + "/" + aid))


def run_builders(builders, only=None):
    out = {}
    for aid, fn in builders.items():
        if only is not None and aid not in only:
            continue
        out[aid] = fn()
    return out


# ---------------------------------------------------------------------------------------------------------------
# Geometry helpers (all operate on an MB instance)
# ---------------------------------------------------------------------------------------------------------------
def _faces_of(verts):
    fs = set()
    for v in verts:
        for f in v.link_faces:
            fs.add(f)
    return fs


def blob(b, center, radii, mat="Leaf", subdiv=2, jitter=0.12, seed=1, top_mat=None, top_thresh=0.45, rot_z=0.0,
         flat_bottom=None, bottom_mat=None, bottom_thresh=-0.55, axis_jitter=0.0, ground=None, cuts=(), cap_mat=None, cap_thresh=0.85):
    """Jittered icosphere (subdiv 1 = 20 tris, 2 = 80 tris) scaled to `radii`. Faces whose normal.z > top_thresh get
    top_mat (sun-lit tuft), normal.z < bottom_thresh get bottom_mat. flat_bottom=z (relative to centre) clamps the base."""
    bm = b.bm
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    verts = res["verts"]
    rnd = random.Random(seed)
    cx, cy, cz = center
    cs, sn = math.cos(rot_z), math.sin(rot_z)
    for v in verts:
        p = v.co.copy()
        k = 1.0 + rnd.uniform(-jitter, jitter)
        ax = 1.0 + rnd.uniform(-axis_jitter, axis_jitter)
        x, y, z = p.x * radii[0] * k * ax, p.y * radii[1] * k, p.z * radii[2] * k
        if flat_bottom is not None and z < flat_bottom:
            z = flat_bottom
        for (nx_, ny_, nz_), dd in cuts:
            nn = Vector((nx_, ny_, nz_)).normalized()
            q = Vector((x, y, z))
            ex = q.dot(nn) - dd
            if ex > 0:
                q = q - nn * ex
                x, y, z = q.x, q.y, q.z
        x, y = x * cs - y * sn, x * sn + y * cs
        zz = cz + z
        if ground is not None and zz < ground:
            zz = ground
        v.co = Vector((cx + x, cy + y, zz))
    faces = _faces_of(verts)
    mi = b._mi(mat)
    mt = b._mi(top_mat) if top_mat else mi
    mb = b._mi(bottom_mat) if bottom_mat else mi
    for f in faces:
        f.smooth = False
        f.normal_update()
        f.material_index = mi
        if top_mat and f.normal.z > top_thresh:
            f.material_index = mt
        elif bottom_mat and f.normal.z < bottom_thresh:
            f.material_index = mb
        if cap_mat and f.normal.z > cap_thresh:
            f.material_index = b._mi(cap_mat)
    return verts


def cone(b, base, r, h, seg=8, mat="Leaf", star=0.0, jitter=0.0, seed=0, rot=0.0, apex_shift=(0.0, 0.0), cap=True, r_apex=0.0):
    """Cone/frustum with a pointed (r_apex=0) or flat top. base = centre of the bottom. star alternates ring radii."""
    rnd = random.Random(seed)
    cx, cy, cz = base
    ring = []
    for i in range(seg):
        a = rot + 2 * math.pi * i / seg
        rr = r * (1.0 + (star if i % 2 else -star)) * (1.0 + rnd.uniform(-jitter, jitter))
        ring.append(b.v((cx + math.cos(a) * rr, cy + math.sin(a) * rr, cz)))
    if r_apex <= 0:
        apex = b.v((cx + apex_shift[0], cy + apex_shift[1], cz + h))
        for i in range(seg):
            b.face([ring[i], ring[(i + 1) % seg], apex], mat)
    else:
        top = []
        for i in range(seg):
            a = rot + 2 * math.pi * i / seg
            top.append(b.v((cx + apex_shift[0] + math.cos(a) * r_apex, cy + apex_shift[1] + math.sin(a) * r_apex, cz + h)))
        for i in range(seg):
            j = (i + 1) % seg
            b.face([ring[i], ring[j], top[j], top[i]], mat)
        b.face(top, mat)
    if cap:
        b.face(list(reversed(ring)), mat)


def tube(b, pts, radii, seg=6, mat="Bark", cap_start=True, cap_end=True, rot=0.0, jitter=0.0, seed=0, mats=None):
    """Tapered tube along a polyline with per-point radii (<=0 on the last point = pointed tip). Fixed reference frame."""
    P = [Vector(p) for p in pts]
    d = (P[-1] - P[0])
    d = d.normalized() if d.length > 1e-6 else Vector((0, 0, 1))
    ref = Vector((1, 0, 0)) if abs(d.x) < 0.9 else Vector((0, 1, 0))
    rnd = random.Random(seed)
    tip = radii[-1] <= 0
    n_rings = len(P) - 1 if tip else len(P)
    rings = []
    for k in range(n_rings):
        if k == 0:
            t = P[1] - P[0]
        elif k == len(P) - 1:
            t = P[-1] - P[-2]
        else:
            t = P[k + 1] - P[k - 1]
        t = t.normalized()
        n = (ref - t * ref.dot(t)).normalized()
        bb = t.cross(n)
        ring = []
        for i in range(seg):
            a = rot + 2 * math.pi * i / seg
            rr = radii[k] * (1.0 + rnd.uniform(-jitter, jitter))
            ring.append(P[k] + (n * math.cos(a) + bb * math.sin(a)) * rr)
        rings.append(ring)
    V = [[b.v(p) for p in ring] for ring in rings]
    m = (mats[0] if mats else mat)
    for k in range(len(V) - 1):
        mm = mats[min(k, len(mats) - 1)] if mats else mat
        for i in range(seg):
            j = (i + 1) % seg
            b.face([V[k][i], V[k][j], V[k + 1][j], V[k + 1][i]], mm)
    if cap_start:
        b.face(list(reversed(V[0])), mat if not mats else mats[0])
    if tip:
        apex = b.v(P[-1])
        for i in range(seg):
            b.face([V[-1][i], V[-1][(i + 1) % seg], apex], mats[-1] if mats else mat)
    elif cap_end:
        b.face(V[-1], mats[-1] if mats else mat)
    return V


def frond(b, base, yaw, pitch0, bend, length, width, steps=5, mat="PalmLeaf", fold=0.3, profile=None, sag=0.0, profile_r=None):
    """Palm/grass leaf: a folded ribbon along a gravity-bent spine. yaw = degrees around Z (0 = +Y), pitch0 = start elevation
    angle in degrees, bend = degrees the spine turns downwards over its length. width = max half-width."""
    prof = profile or [0.25, 0.75, 1.0, 0.8, 0.5, 0.25]
    prof_r = profile_r or prof
    yaw_r = math.radians(yaw)
    d = Vector((math.sin(yaw_r), math.cos(yaw_r), 0.0))
    s = Vector((math.cos(yaw_r), -math.sin(yaw_r), 0.0))
    up = Vector((0, 0, 1))
    p = Vector(base)
    seg_len = length / steps
    rows = []
    for i in range(steps):
        t = i / max(1, steps - 1)
        wl = width * prof[min(i, len(prof) - 1)]
        wr = width * prof_r[min(i, len(prof_r) - 1)]
        c = b.v(p)
        l = b.v(p - s * wl + up * (-fold * wl))
        r = b.v(p + s * wr + up * (-fold * wr))
        rows.append((l, c, r))
        ang = math.radians(pitch0 - bend * ((i + 0.5) / steps) ** 1.25)
        p = p + (d * math.cos(ang) + up * math.sin(ang)) * seg_len
    tip = b.v(p + up * (-sag))
    for i in range(steps - 1):
        l0, c0, r0 = rows[i]
        l1, c1, r1 = rows[i + 1]
        b.face([l0, c0, c1, l1], mat)
        b.face([c0, r0, r1, c1], mat)
    l, c, r = rows[-1]
    b.face([l, c, tip], mat)
    b.face([c, r, tip], mat)
    return p


def slab(b, pts, plane, d0, d1, mat="Paint"):
    """Extrude a 2D polygon (CCW) in the given plane: 'xy' (depth = z), 'xz' (depth = y) or 'yz' (depth = x)."""
    def P(q, d):
        if plane == "xy":
            return (q[0], q[1], d)
        if plane == "xz":
            return (q[0], d, q[1])
        return (d, q[0], q[1])
    A = [b.v(P(q, d0)) for q in pts]
    B = [b.v(P(q, d1)) for q in pts]
    n = len(pts)
    b.face(list(reversed(A)), mat)
    b.face(B, mat)
    for i in range(n):
        j = (i + 1) % n
        b.face([A[i], A[j], B[j], B[i]], mat)
    return A, B


def cbox(b, center, size, c=0.02, mat="Paint", cz=None, top_mat=None, rot_z=0.0):
    """Chamfered box: 8-point rings (corner cut) with bottom/top edges chamfered. size=(sx, sy, sz), c = chamfer in metres."""
    cx, cy, cz0 = center
    sx, sy, sz = size
    cz = c if cz is None else cz
    hx, hy = sx / 2, sy / 2
    rings = []
    cs, sn = math.cos(rot_z), math.sin(rot_z)

    def ring(inset, z):
        hx2, hy2 = hx - inset, hy - inset
        cc = max(0.0, c - inset * 0.0)
        pts = [(hx2 - cc, -hy2), (hx2, -hy2 + cc), (hx2, hy2 - cc), (hx2 - cc, hy2),
               (-hx2 + cc, hy2), (-hx2, hy2 - cc), (-hx2, -hy2 + cc), (-hx2 + cc, -hy2)]
        return [Vector((cx + x * cs - y * sn, cy + x * sn + y * cs, cz0 + z)) for x, y in pts]

    rings.append(ring(c, -sz / 2))
    rings.append(ring(0, -sz / 2 + cz))
    rings.append(ring(0, sz / 2 - cz))
    rings.append(ring(c, sz / 2))
    V = [[b.v(p) for p in r] for r in rings]
    n = 8
    for k in range(3):
        for i in range(n):
            j = (i + 1) % n
            b.face([V[k][i], V[k][j], V[k + 1][j], V[k + 1][i]], mat)
    b.face(list(reversed(V[0])), mat)
    b.face(V[-1], top_mat or mat)
    return V


def tilt_all(b, verts_start, axis, deg, pivot=(0, 0, 0)):
    """Rotate bmesh verts created since index `verts_start` (use len(b.bm.verts) before building) around axis X|Y|Z."""
    b.bm.verts.ensure_lookup_table()
    vs = [b.bm.verts[i] for i in range(verts_start, len(b.bm.verts))]
    from mathutils import Matrix
    M = Matrix.Rotation(math.radians(deg), 4, axis)
    pv = Vector(pivot)
    for v in vs:
        v.co = pv + M @ (v.co - pv)


def lod_tree(aid, trunk_h, trunk_r0, trunk_r1, blobs=(), cones=(), seg=4, trunk_mat="Bark", lean=(0, 0), fronds=()):
    """~60 tri impostor: one mesh node 'Body' (tapered trunk + a few chunky blobs/cones)."""
    a = Asset(aid)
    b = MB(aid + "_body")
    tube(b, [(0, 0, -0.05), (lean[0] * 0.5, lean[1] * 0.5, trunk_h * 0.5), (lean[0], lean[1], trunk_h)], [trunk_r0, (trunk_r0 + trunk_r1) / 2, trunk_r1],
         seg=seg, mat=trunk_mat, cap_start=False, cap_end=True)
    for i, (c, r, m) in enumerate(blobs):
        blob(b, c, r, mat=m, subdiv=1, jitter=0.1, seed=11 + i)
    for i, (c, r, h, m) in enumerate(cones):
        cone(b, c, r, h, seg=6, mat=m, cap=(i == 0), star=0.0)
    for i, (base, yaw, pitch, bend, ln, w, m) in enumerate(fronds):
        frond(b, base, yaw, pitch, bend, ln, w, steps=2, mat=m, fold=0.3, profile=[0.6, 1.0])
    a.mesh(b, "Body")
    return a


def octa(b, c, r, mat="Accent", sq=0.7, rot=0.0):
    """Tiny 8-tri octahedron (flower head / crystal / bead). sq squashes it vertically."""
    cx, cy, cz = c
    cs, sn = math.cos(rot), math.sin(rot)
    def P(x, y, z):
        return b.v((cx + x * cs - y * sn, cy + x * sn + y * cs, cz + z))
    px, nx, py, ny, pz, nz = P(r, 0, 0), P(-r, 0, 0), P(0, r, 0), P(0, -r, 0), P(0, 0, r * sq), P(0, 0, -r * sq)
    for e in ((px, py), (py, nx), (nx, ny), (ny, px)):
        b.face([e[0], e[1], pz], mat)
        b.face([e[1], e[0], nz], mat)


def blade(b, x, y, yaw, h, w, lean, mat_base="Leaf", mat_tip="LeafLight", bend=0.35, z0=0.0):
    """Grass blade: kite-shaped ribbon (3 tris) rising from (x,y) leaning along yaw (degrees, 0 = +Y)."""
    yr = math.radians(yaw)
    d = Vector((math.sin(yr), math.cos(yr), 0.0))
    s = Vector((math.cos(yr), -math.sin(yr), 0.0))
    p0 = Vector((x, y, z0))
    pm = p0 + d * (lean * (1.0 - bend) * 0.45) + Vector((0, 0, h * 0.55))
    pt = p0 + d * lean + Vector((0, 0, h))
    l0, r0 = b.v(p0 - s * w), b.v(p0 + s * w)
    lm, rm = b.v(pm - s * w * 0.6), b.v(pm + s * w * 0.6)
    t = b.v(pt)
    b.face([l0, r0, rm, lm], mat_base)
    b.face([lm, rm, t], mat_tip)


def bell(b, base, r, h, seg=7, mat="Leaf", mid_r=0.45, mid_h=0.4, star=0.1, jitter=0.04, seed=0, rot=0.0, cap=True, apex_shift=(0.0, 0.0)):
    """Concave spruce tier: wide skirt ring -> narrow mid ring -> apex (faceted, droopy look)."""
    rnd = random.Random(seed)
    cx, cy, cz = base

    def ring(rr, z, off):
        out = []
        for i in range(seg):
            a = rot + off + 2 * math.pi * i / seg
            q = rr * (1.0 + (star if i % 2 else -star)) * (1.0 + rnd.uniform(-jitter, jitter))
            out.append(b.v((cx + math.cos(a) * q, cy + math.sin(a) * q, z)))
        return out
    r0 = ring(r, cz, 0.0)
    r1 = ring(r * mid_r, cz + h * mid_h, 0.0)
    apex = b.v((cx + apex_shift[0], cy + apex_shift[1], cz + h))
    for i in range(seg):
        j = (i + 1) % seg
        b.face([r0[i], r0[j], r1[j], r1[i]], mat)
        b.face([r1[i], r1[j], apex], mat)
    if cap:
        b.face(list(reversed(r0)), mat)


def loft_mats(b, rings, mats, cap_start=None, cap_end=None):
    """Closed loft with a material per segment: mats = list (len = rings-1) of material names OR callables(k, i) -> name."""
    V = [[b.v(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for k in range(len(V) - 1):
        for i in range(n):
            j = (i + 1) % n
            m = mats[k] if not callable(mats[k]) else mats[k](k, i)
            b.face([V[k][i], V[k][j], V[k + 1][j], V[k + 1][i]], m)
    if cap_start:
        b.face(list(reversed(V[0])), cap_start)
    if cap_end:
        b.face(V[-1], cap_end)
    return V
