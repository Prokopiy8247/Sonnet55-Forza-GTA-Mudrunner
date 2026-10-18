"""lane14_coral.py - coral_a (branching), coral_b (brain / dome), coral_c (fans + tubes). Origin = base centre on the sea bed, front +Y. <= 400 tris each.
Set ONLY=['coral_a', ...] before exec to build a subset."""
import random
import math
from mathutils import Vector, Matrix

CATU = "GTA_GODOT/Nature"


def build_coral_a():
    A = A14("coral_a", 5, CATU, spacing=12.0)
    b = HB("coral_a_body")
    rr = random.Random(5)
    blob(b, (0, 0, 0.0), (0.62, 0.55, 0.27), seed=3, subdiv=1, jitter=.14, ground=0.0)
    mats = ["CoralPinkDk", "CoralPink", "CoralOrange"]

    def grow(p, d, L, r, depth):
        q = p + d * L
        last = depth == 2
        limb(b, p, q, r, r * 0.62, 4, mats[depth], tip=last, rot=rr.uniform(0, 1.5), mat_tip="CoralOrange")
        if last:
            return
        az0 = rr.uniform(0, 360)
        for k in range(2):
            nd = rot_dir(d, rr.uniform(28, 42), az0 + k * 180 + rr.uniform(-25, 25))
            nd = (nd + Vector((0, 0, 0.3))).normalized()
            grow(q - d * L * 0.1, nd, L * 0.8, r * 0.64, depth + 1)
    for k in range(4):
        az = k * 90 + rr.uniform(-18, 18)
        d0 = rot_dir(Vector((0, 0, 1)), rr.uniform(16, 30), az)
        p0 = Vector((math.cos(math.radians(az)) * 0.16, math.sin(math.radians(az)) * 0.16, 0.12))
        grow(p0, d0, 0.62, 0.105, 0)
    grow(Vector((0, 0, 0.12)), Vector((0.05, 0.02, 1)).normalized(), 0.72, 0.115, 0)
    A.mesh(b, "Body", uv=None)
    return A


def dome(b, c, R, rings, seg, ridge, mats, seed, flat=1.0):
    rr = random.Random(seed)
    c = Vector(c)
    grid = []
    for k in range(rings + 1):
        phi = (math.pi / 2 * 0.95) * k / rings
        row = []
        for i in range(seg):
            th = 2 * math.pi * i / seg
            rad = R * (1 + (ridge if k % 2 == 1 else -ridge * 0.5) + 0.05 * math.sin(4 * th + k * 1.9) + 0.025 * math.sin(7 * th - k) + rr.uniform(-.015, .015))
            row.append(c + Vector((math.sin(phi) * math.cos(th) * rad, math.sin(phi) * math.sin(th) * rad, math.cos(phi) * rad * flat)))
        grid.append(row)
    apex = c + Vector((0, 0, R * flat * (1 + ridge * 0.6)))
    for i in range(seg):
        j = (i + 1) % seg
        b.pq([apex, grid[1][j], grid[1][i]], (0, 0, 1), mats[0])
    for k in range(1, rings):
        m = mats[1] if k % 2 == 1 else mats[0]
        for i in range(seg):
            j = (i + 1) % seg
            pts = [grid[k][i], grid[k][j], grid[k + 1][j], grid[k + 1][i]]
            cen = sum(pts, Vector()) / 4
            b.pq(pts, cen - c, m)
    # lower skirt ring closing to the ground
    for i in range(seg):
        j = (i + 1) % seg
        lo_i = Vector((grid[rings][i].x, grid[rings][i].y, c.z))
        lo_j = Vector((grid[rings][j].x, grid[rings][j].y, c.z))
        b.pq([grid[rings][i], grid[rings][j], lo_j, lo_i], grid[rings][i] - c, mats[1])


def build_coral_b():
    A = A14("coral_b", 6, CATU, spacing=12.0)
    b = HB("coral_b_body")
    blob(b, (0, 0.0, 0.0), (0.95, 0.8, 0.14), seed=21, subdiv=1, jitter=.12, ground=0.0)
    dome(b, (0.0, 0.0, 0.0), 0.72, 6, 12, 0.07, ("CoralPurple", "CoralPurpleDk"), 1, flat=0.95)
    dome(b, (0.8, 0.35, 0.0), 0.4, 4, 9, 0.08, ("CoralPink", "CoralPinkDk"), 2, flat=1.0)
    dome(b, (-0.62, -0.5, 0.0), 0.34, 4, 9, 0.08, ("CoralOrangeLt", "CoralOrange"), 3, flat=1.0)
    A.mesh(b, "Body", uv=None)
    return A


def fan(b, c, yaw, R, spread, spokes, m_a, m_b, tilt=8.0, seed=1):
    """vertical lattice fan (gorgonian) in a plane, stalk at c; spokes radiate in the local XZ plane"""
    rr = random.Random(seed)
    with xf(b, T(*c) @ RZ(yaw) @ RY(tilt)):
        up = math.radians(90)
        ang = [math.radians(90 - spread / 2 + spread * i / (spokes - 1)) for i in range(spokes)]
        rad = [R * rr.uniform(.82, 1.0) for _ in range(spokes)]

        def pt(a, r):
            return Vector((math.cos(a) * r, 0, math.sin(a) * r + 0.12))
        w = 0.05
        for i in range(spokes):
            p0, p1 = pt(ang[i], 0.05), pt(ang[i], rad[i])
            b.pq([p0 + Vector((-w, 0, 0)), p0 + Vector((w, 0, 0)), p1 + Vector((w * 0.6, 0, 0)), p1 + Vector((-w * 0.6, 0, 0))], (0, 1, 0), m_a)
        for (fr, mm) in ((0.32, m_a), (0.55, m_b), (0.78, m_a)):
            for i in range(spokes - 1):
                a0, a1 = pt(ang[i], rad[i] * fr), pt(ang[i + 1], rad[i + 1] * fr)
                b.pq([a0 + Vector((0, 0, -w)), a1 + Vector((0, 0, -w)), a1 + Vector((0, 0, w)), a0 + Vector((0, 0, w))], (0, 1, 0), mm)
        b.cyl((0, 0, 0.06), 0.045, 0.14, 4, m_a, caps="t")                          # stalk


def tube(b, c, r, h, seg, m_out, m_in, rot=0.0):
    c = Vector(c)
    lo = [c + Vector((math.cos(rot + 2 * math.pi * i / seg) * r, math.sin(rot + 2 * math.pi * i / seg) * r, 0)) for i in range(seg)]
    hi = [c + Vector((math.cos(rot + 2 * math.pi * i / seg) * r * 0.86, math.sin(rot + 2 * math.pi * i / seg) * r * 0.86, h)) for i in range(seg)]
    for i in range(seg):
        j = (i + 1) % seg
        am = rot + 2 * math.pi * (i + 0.5) / seg
        b.pq([lo[i], lo[j], hi[j], hi[i]], (math.cos(am), math.sin(am), 0.15), m_out)
    b.pq([p + Vector((0, 0, -0.06)) for p in hi], (0, 0, 1), m_in)                    # dark mouth


def build_coral_c():
    A = A14("coral_c", 7, CATU, spacing=12.0)
    b = HB("coral_c_body")
    blob(b, (0, 0, 0), (0.78, 0.62, 0.17), seed=33, subdiv=1, jitter=.14, ground=0.0)
    fan(b, (-0.25, 0.05, 0.1), 15, 0.95, 150, 8, "CoralOrange", "CoralOrangeLt", 6, 1)
    fan(b, (0.3, -0.12, 0.1), -50, 0.75, 130, 7, "CoralPink", "CoralPinkDk", 10, 2)
    fan(b, (0.1, 0.4, 0.1), 80, 0.6, 120, 6, "CoralPurple", "CoralPurpleDk", 8, 3)
    for (x, y, h, r, mo, mi, rot) in ((0.55, 0.3, 0.55, 0.08, "CoralYellow", "UrchinBody", 0.2), (0.7, 0.1, 0.38, 0.07, "CoralYellow", "UrchinBody", 0.5), (0.62, 0.48, 0.3, 0.06, "CoralTeal", "UrchinBody", 0.1),
                                      (-0.62, -0.32, 0.5, 0.085, "CoralTeal", "UrchinBody", 0.3), (-0.45, -0.5, 0.34, 0.07, "CoralYellow", "UrchinBody", 0.7), (-0.75, -0.1, 0.28, 0.06, "CoralTeal", "UrchinBody", 0.0)):
        tube(b, (x, y, 0.08), r, h, 5, mo, mi, rot)
    A.mesh(b, "Body", uv=None)
    return A


BUILD = {"coral_a": (build_coral_a, 400), "coral_b": (build_coral_b, 400), "coral_c": (build_coral_c, 400)}
for _id, (_fn, _bud) in BUILD.items():
    if globals().get("ONLY") and _id not in ONLY:
        continue
    _fn().report(_bud)
