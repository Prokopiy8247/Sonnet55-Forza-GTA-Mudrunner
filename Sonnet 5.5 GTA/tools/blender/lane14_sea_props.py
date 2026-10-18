"""lane14_sea_props.py - anchor, sunken_crates, clam_shell, starfish, sea_urchin, bubble_vent (underwater set dressing).
Origin = base / footprint centre on the sea bed, front +Y. Set ONLY=[...] before exec to build a subset."""
import random
import math
from mathutils import Vector, Matrix

CATU = "GTA_GODOT/Nature"


# ------------------------------------------------------------------------------------------------------------------------------ anchor
def build_anchor():
    A = A14("anchor", 12, CATU, spacing=12.0)
    b = HB("anchor_body")
    # --- upright admiralty anchor, crown at the origin, shank up +Z, arms along +-X, stock along Y
    with xf(b, T(0, 0, 0)):
        b.beam((0, 0, 0.0), (0, 0, 1.58), 0.105, 0.07, 6, "AnchorIron", caps=True)                                # shank
        b.ball((0, 0, 0.03), 0.21, 6, 3, "AnchorRust", sc=(1.0, 0.85, 0.9))                                         # crown
        for sg in (1, -1):
            pts = [(0.05 * sg, 0, 0.02), (0.30 * sg, 0, 0.0), (0.52 * sg, 0, 0.12), (0.66 * sg, 0, 0.34)]
            rad = [0.09, 0.08, 0.065, 0.05]
            for i in range(3):
                b.beam(pts[i], pts[i + 1], rad[i], rad[i + 1], 6, "AnchorRust" if i < 2 else "AnchorIron", caps=(i == 2))
            tip = Vector(pts[3])
            dirn = (Vector(pts[3]) - Vector(pts[2])).normalized()
            side = Vector((0, 1, 0))
            c0 = tip - dirn * 0.04
            c1 = tip + dirn * 0.38
            # fluke (palm): flat diamond plate
            b.pq([c0 - side * 0.04, c0 + dirn * 0.12 + side * 0.2, c1, c0 + dirn * 0.12 - side * 0.2], dirn.cross(side), "AnchorRust")
            b.pq([c0 - side * 0.04, c0 + dirn * 0.12 - side * 0.2, c1, c0 + dirn * 0.12 + side * 0.2], dirn.cross(-side), "AnchorRust")
        # stock (cross bar) with knobs
        b.beam((0, -0.66, 1.34), (0, 0.66, 1.34), 0.05, 0.05, 6, "AnchorIron", caps=True)
        b.ball((0, -0.68, 1.34), 0.06, 5, 2, "AnchorRust")
        b.ball((0, 0.68, 1.34), 0.06, 5, 2, "AnchorRust")
        b.cyl((0, 0, 1.34), 0.085, 0.14, 6, "AnchorRust", caps="bt")                                               # stock collar
        # ring
        b.torus((0, 0, 1.72), 0.15, 0.04, 8, 4, "AnchorIron", axis="Y")
        b.cyl((0, 0, 1.58), 0.1, 0.12, 6, "AnchorRust", caps="")
    # --- rest pose: shank leans over towards +Y, crown + stock end on the sand
    transform_all(b, RX(-62))
    zmin = vmin_z(b)
    transform_all(b, T(0, -0.2, -zmin - 0.04))
    # chain lying on the sea floor from the ring
    pr = (RX(-62) @ Vector((0, 0, 1.78)))
    cx, cy = pr.x, pr.y - 0.2
    rr = random.Random(5)
    x, y, a = cx, cy, 0.7
    for i in range(5):
        a += rr.uniform(-.35, .35)
        x += math.cos(a) * 0.15
        y += math.sin(a) * 0.15
        with xf(b, T(x, y, 0.05) @ RZ(math.degrees(a)) @ RX(90 if i % 2 else 0)):
            b.cbox((0, 0, 0), (0.19, 0.1, 0.055), "AnchorRust" if i % 3 else "AnchorIron", skip="-z")
    A.mesh(b, "Body", uv=None)
    return A


# ------------------------------------------------------------------------------------------------------------------------------ sunken crates
def dome_silt(b, cx, cy, rx, ry, h, seg=7, seed=1, mat="UWSilt"):
    rr = random.Random(seed)
    ring = [(cx + rx * math.cos(2 * math.pi * i / seg) * rr.uniform(.8, 1.1), cy + ry * math.sin(2 * math.pi * i / seg) * rr.uniform(.8, 1.1)) for i in range(seg)]
    apex = (cx + rr.uniform(-.1, .1), cy + rr.uniform(-.1, .1), h)
    for i in range(seg):
        j = (i + 1) % seg
        b.pq([(ring[i][0], ring[i][1], 0.0), (ring[j][0], ring[j][1], 0.0), apex], (0, 0, 1), mat)


def build_sunken_crates():
    A = A14("sunken_crates", 13, CATU, spacing=12.0)
    b = HB("sunken_crates_body")
    dome_silt(b, 0.0, 0.0, 1.15, 1.0, 0.16, 8, 2)
    crate(b, (-0.3, 0.0, 0.34), 0.78, math.radians(12), math.radians(3), math.radians(-4), style="brace")
    crate(b, (0.55, 0.28, 0.3), 0.7, math.radians(-28), math.radians(-6), math.radians(5), style="brace")
    crate(b, (-0.12, -0.05, 0.9), 0.7, math.radians(36), math.radians(10), math.radians(-9), style="brace")               # stacked on top, slipping
    crate(b, (0.4, -0.62, 0.28), 0.66, math.radians(70), math.radians(0), math.radians(14), h=0.6, style="brace")          # tipped
    barrel(b, (-0.74, 0.62, 0.3), 0.3, 0.88, axis="X")
    # algae mats on the crate tops + a loose plank
    for (x, y, z, w, l, yaw) in ((-0.3, 0.0, 0.79, 0.5, 0.5, 12), (0.55, 0.28, 0.66, 0.4, 0.45, -28), (-0.12, -0.05, 1.27, 0.45, 0.4, 36)):
        with xf(b, T(x, y, z) @ RZ(yaw)):
            b.pq([(-w / 2, -l / 2, 0), (w / 2, -l / 2, 0), (w / 2, l / 2, 0), (-w / 2, l / 2, 0)], (0, 0, 1), "UWAlgae")
    with xf(b, T(0.9, -0.4, 0.07) @ RZ(35)):
        b.abox(-0.6, 0.6, -0.07, 0.07, 0.0, 0.05, "WreckCrateDk", "-z")
    A.mesh(b, "Body", uv=None)
    return A


# ------------------------------------------------------------------------------------------------------------------------------ clam
def shell_surface(b, rx, ry, rim_z, depth_z, segs, rings, mat_a, mat_b, rib=0.07, seed=1, up=True, c=(0, 0, 0), off=0.0, rib_phase=0.0):
    """bowl (up=True: opens upwards, centre low) with radial corrugation; returns rim points"""
    rr = random.Random(seed)
    cv = Vector(c)
    grid = []
    for k in range(rings + 1):
        t = k / rings
        row = []
        for i in range(segs):
            th = 2 * math.pi * i / segs
            wob = 1 + (rib if (i % 2 == 0) else -rib * 0.4) * (0.35 + 0.65 * t)
            x = math.cos(th) * rx * t * wob
            y = math.sin(th) * ry * t * wob
            z = depth_z + (rim_z - depth_z) * (t ** 1.7) + off
            row.append(cv + Vector((x, y, z)))
        grid.append(row)
    for k in range(rings):
        for i in range(segs):
            j = (i + 1) % segs
            m = mat_a if (i % 2 == 0) else mat_b
            if k == 0:
                pts = [grid[0][0], grid[1][j], grid[1][i]]
            else:
                pts = [grid[k][i], grid[k][j], grid[k + 1][j], grid[k + 1][i]]
            n = Vector((0, 0, 1 if up else -1))
            b.pq(pts, n + (sum(pts, Vector()) / len(pts) - cv - Vector((0, 0, depth_z))).normalized() * (0.0 if k == 0 else (-0.5 if up else 0.5)), m)
    return grid[rings]


def build_clam_shell():
    A = A14("clam_shell", 14, CATU, spacing=12.0)
    # lower valve + mantle (Body)
    b = HB("clam_body")
    shell_surface(b, 0.46, 0.34, 0.26, 0.04, 10, 4, "ClamShell", "ClamShellDk", seed=1)                         # outer
    shell_surface(b, 0.43, 0.32, 0.25, 0.08, 10, 4, "ClamFlesh", "ClamFlesh", rib=0.05, seed=2, up=True, off=0.015)   # inner mantle (shows from above)
    A.mesh(b, "Body", uv=None)
    # upper valve (Lid): origin on the hinge (back edge), modelled OPEN by 55 deg
    hinge = Vector((0, -0.34, 0.27))
    lid = HB("clam_lid")
    # closed pose: dome lying over the lower valve, then rotated about the hinge
    segs, rings = 10, 4
    cx, cy = 0.0, 0.34       # centre of the lid relative to hinge (hinge at the back)
    grid = []
    for k in range(rings + 1):
        t = k / rings
        row = []
        for i in range(segs):
            th = 2 * math.pi * i / segs
            wob = 1 + (0.07 if i % 2 == 0 else -0.03) * (0.35 + 0.65 * t)
            x = math.cos(th) * 0.46 * t * wob
            y = cy + math.sin(th) * 0.34 * t * wob
            z = 0.2 * (1 - t ** 1.9) + 0.012
            row.append(Vector((x, y, z)))
        grid.append(row)
    # outer surface faces up (ClamShell), inner surface (nacre) faces down
    for side, up_ in (("o", True), ("i", False)):
        for k in range(rings):
            for i in range(segs):
                j = (i + 1) % segs
                if k == 0:
                    pts = [grid[0][0], grid[1][j], grid[1][i]]
                else:
                    pts = [grid[k][i], grid[k][j], grid[k + 1][j], grid[k + 1][i]]
                if side == "o":
                    lid.pq([p + Vector((0, 0, 0.012)) for p in pts], Vector((0, 0, 1)), "ClamShell" if i % 2 == 0 else "ClamShellDk")
                else:
                    lid.pq(pts, Vector((0, 0, -1)), "ClamShellDk" if i % 2 else "ClamFlesh")
    # rotate about hinge: hinge is origin of the lid object; mesh built relative to hinge -> open it
    transform_all(lid, RX(55))
    L = A.mesh(lid, "Lid", loc=tuple(hinge), uv=None)
    # pearl
    p = HB("clam_pearl")
    p.ball((0, 0, 0), 0.085, 8, 4, "Pearl")
    A.mesh(p, "Pearl", loc=(0.0, 0.02, 0.2), uv=None)
    A.mark("PearlPoint", (0.0, 0.02, 0.2), size=0.1, display="SPHERE")
    return A


# ------------------------------------------------------------------------------------------------------------------------------ starfish
def build_starfish():
    A = A14("starfish", 15, CATU, spacing=12.0)
    b = HB("starfish_body")
    R, r = 0.19, 0.055
    C = Vector((0, 0, 0.075))
    T_, V_, G_ = [], [], []
    for k in range(5):
        a = math.radians(90 + 72 * k)
        T_.append(Vector((math.cos(a) * R, math.sin(a) * R, 0.012)))
        G_.append(Vector((math.cos(a) * R * 0.55, math.sin(a) * R * 0.55, 0.062)))
        av = a + math.radians(36)
        V_.append(Vector((math.cos(av) * r, math.sin(av) * r, 0.03)))
    for k in range(5):
        vp = V_[(k - 1) % 5]
        vn = V_[k]
        m1 = "StarOrange"
        b.pq([C, vp, G_[k]], (0, 0, 1), m1)
        b.pq([C, G_[k], vn], (0, 0, 1), "StarOrange")
        b.pq([G_[k], vp, T_[k]], (0, 0, 1), "StarOrange" if k % 2 else "CoralOrange")
        b.pq([G_[k], T_[k], vn], (0, 0, 1), "CoralOrange" if k % 2 else "StarOrange")
        # skirts to the ground
        for (p0, p1) in ((vp, T_[k]), (T_[k], vn)):
            b.pq([p0, p1, Vector((p1.x, p1.y, 0)), Vector((p0.x, p0.y, 0))], (p0 + p1) / 2 - Vector((0, 0, 0.03)), "StarOrange")
        # tubercles along the ridge
        for f in (0.28, 0.5, 0.75):
            pc = C + (T_[k] - C) * f
            pc.z = 0.085 - 0.05 * f + 0.012
            rr_ = 0.011
            tri = [pc + Vector((math.cos(q) * rr_, math.sin(q) * rr_, -0.01)) for q in (0.2, 2.3, 4.4)]
            apex = pc + Vector((0, 0, 0.018))
            for i in range(3):
                b.pq([tri[i], tri[(i + 1) % 3], apex], Vector((0, 0, 1)) + (tri[i] - pc), "StarDot")
    A.mesh(b, "Body", uv=None)
    return A


# ------------------------------------------------------------------------------------------------------------------------------ sea urchin
def build_sea_urchin():
    A = A14("sea_urchin", 16, CATU, spacing=12.0)
    b = HB("urchin_body")
    c = Vector((0, 0, 0.12))
    V, F = ico(1)
    rr = random.Random(9)
    body_r = 0.095
    for (i0, i1, i2) in F:
        p = [c + V[i] * body_r * Vector((1, 1, 0.9)) for i in (i0, i1, i2)]
        n = (p[1] - p[0]).cross(p[2] - p[0])
        cen = (p[0] + p[1] + p[2]) / 3
        if n.dot(cen - c) < 0:
            n = -n
        b.pq(p, n, "UrchinBody")
    for v in V:
        if v.z < -0.55:
            continue
        L = rr.uniform(0.12, 0.18) * (0.8 if v.z < 0.0 else 1.0)
        base = c + v * body_r * 0.95
        tip = c + v * (body_r + L)
        x, y, z = perp_basis(v)
        r0 = 0.014
        ring = [base + (x * math.cos(a) + y * math.sin(a)) * r0 for a in (0.0, 2.094, 4.189)]
        for i in range(3):
            b.pq([ring[i], ring[(i + 1) % 3], tip], (ring[i] + ring[(i + 1) % 3]) / 2 - base, "UrchinSpine" if (i + int(v.x * 7)) % 2 else "UrchinBody")
    A.mesh(b, "Body", uv=None)
    return A


# ------------------------------------------------------------------------------------------------------------------------------ bubble vent
def chimney(b, c, r0, r1, h, seg, seed, mats):
    rr = random.Random(seed)
    c = Vector(c)
    levels = [0.0, 0.38, 0.72, 1.0]
    radii = [r0, r0 * 0.82 + r1 * 0.18, r0 * 0.5 + r1 * 0.5, r1]
    rings = []
    for lv, rad in zip(levels, radii):
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            k = 1 + rr.uniform(-.14, .14)
            ring.append(c + Vector((math.cos(a) * rad * k + rr.uniform(-.03, .03), math.sin(a) * rad * k + rr.uniform(-.03, .03), h * lv + rr.uniform(-.02, .02))))
        rings.append(ring)
    for k in range(3):
        for i in range(seg):
            j = (i + 1) % seg
            pts = [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]]
            m = mats[0] if k == 0 else (mats[1] if k == 1 else mats[2])
            if (i + k) % 5 == 0:
                m = mats[3]
            b.po(pts, c + Vector((0, 0, h * (levels[k] + 0.1))), m)
    top = rings[3]
    inner = [c + Vector((p.x - c.x, p.y - c.y, 0)) * 0.5 + Vector((0, 0, h - 0.12)) for p in top]
    for i in range(seg):
        j = (i + 1) % seg
        b.pq([top[i], top[j], inner[j], inner[i]], (0, 0, 1), mats[2])                                              # rim
    b.pq(inner, (0, 0, 1), "UrchinBody")                                                                         # dark mouth
    return rings[3]


def build_bubble_vent():
    A = A14("bubble_vent", 17, CATU, spacing=12.0)
    b = HB("bubble_vent_body")
    blob(b, (0, 0, 0), (0.85, 0.75, 0.22), seed=61, subdiv=1, jitter=.16, ground=0.0, mats=("UWRock", "UWRockDk", "UWRockDk"))
    mats = ("UWRockDk", "UWRock", "WreckRust", "UWRockLt")
    chimney(b, (0.0, 0.0, 0.1), 0.38, 0.22, 1.15, 7, 3, mats)
    chimney(b, (0.5, 0.26, 0.05), 0.2, 0.12, 0.55, 6, 5, mats)
    chimney(b, (-0.46, -0.2, 0.05), 0.18, 0.1, 0.42, 6, 6, mats)
    A.mesh(b, "Body", uv=None)
    A.mark("Vent", (0.0, 0.0, 1.25), size=0.25, display="SINGLE_ARROW")
    return A


BUILD = {"anchor": (build_anchor, 400), "sunken_crates": (build_sunken_crates, 400), "clam_shell": (build_clam_shell, 400), "starfish": (build_starfish, 400),
         "sea_urchin": (build_sea_urchin, 400), "bubble_vent": (build_bubble_vent, 400)}
for _id, (_fn, _bud) in BUILD.items():
    if globals().get("ONLY") and _id not in ONLY:
        continue
    _fn().report(_bud)
