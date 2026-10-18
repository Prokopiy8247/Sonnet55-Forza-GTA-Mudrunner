"""lane10_pickups_b.py - scuba_tank, scuba_gear, parachute_pack (worn), parachute_canopy (deployed), life_vest."""
import math, random

PROPS = VFX


def tank_body(b, cx=0.0, cy=0.0, z0=0.0):
    """Yellow scuba cylinder (8-sided, rounded shoulders, navy foot + glowing cyan band). Height 0.64, neck valve on top."""
    st = [(0.0, 0.055), (0.03, 0.09), (0.09, 0.095), (0.15, 0.095), (0.45, 0.095), (0.5, 0.095), (0.55, 0.095), (0.6, 0.068), (0.64, 0.038)]
    N = 8
    rings = []
    for z, r in st:
        rings.append([Vector((cx + math.cos(2 * math.pi * i / N + 0.2) * r, cy + math.sin(2 * math.pi * i / N + 0.2) * r, z0 + z)) for i in range(N)])
    mats = ["TankBand", "TankYellow", "TankBand", "TankYellow", "PickupCyan", "TankYellow", "TankYellow", "Brass"]
    loft_mats(b, rings, mats, cap_start="TankBand", cap_end="Brass")
    # valve block + knob
    b.box((cx, cy, z0 + 0.67), (0.05, 0.06, 0.06), "Brass")
    b.cyl((cx, cy - 0.05, z0 + 0.69), 0.034, 0.014, 8, "Metal", axis="Y")


def build_scuba_tank():
    a = Asset("scuba_tank", PROPS)
    b = MB("scuba_tank_body")
    tank_body(b)
    # first-stage regulator, hose, mouthpiece and gauge
    b.cyl((0.065, 0.0, 0.66), 0.028, 0.06, 6, "Brass", axis="X")
    tube(b, [(0.09, 0.0, 0.66), (0.15, 0.05, 0.56), (0.15, 0.1, 0.5), (0.08, 0.14, 0.58)], [0.012, 0.012, 0.012, 0.012], seg=4, mat="HoseBlack",
         cap_start=False, cap_end=False)
    b.cyl((0.08, 0.16, 0.58), 0.03, 0.05, 6, "Trim", axis="Y")
    b.cyl((-0.06, 0.03, 0.66), 0.03, 0.016, 8, "Metal", axis="Y")
    b.cyl((-0.06, 0.04, 0.66), 0.022, 0.006, 8, "PickupCyan", axis="Y")
    a.mesh(b, "Body")
    a.report()
    return a


def build_scuba_gear():
    a = Asset("scuba_gear", PROPS)
    b = MB("scuba_gear_body")
    tank_body(b, 0.0, -0.07, 0.0)
    b.cyl((0.065, -0.07, 0.66), 0.026, 0.055, 6, "Brass", axis="X")
    # mask hanging on the front of the tank
    cy, cz = 0.1, 0.34
    b.block((0, cy), cz - 0.05, cz + 0.05, (0.2, 0.07), (0.17, 0.07), mat="Silicone")                  # skirt
    b.box((0, cy + 0.035, cz), (0.19, 0.016, 0.105), "Trim")                                           # frame
    b.box((0, cy + 0.045, cz), (0.15, 0.012, 0.07), "MaskLens")                                        # glowing lens
    b.block((0, cy + 0.03), cz - 0.07, cz - 0.04, (0.05, 0.04), (0.035, 0.03), mat="Silicone")         # nose pocket
    for sx in (-1, 1):
        b.beam((sx * 0.1, cy, cz), (sx * 0.1, cy - 0.15, cz + 0.01), 0.012, 0.012, 4, "Strap", caps=False)
        b.beam((sx * 0.1, cy - 0.15, cz + 0.01), (sx * 0.0, -0.17, cz + 0.01), 0.012, 0.012, 4, "Strap", caps=False)
    # snorkel
    tube(b, [(0.14, 0.09, 0.22), (0.15, 0.1, 0.46), (0.13, 0.1, 0.6), (0.08, 0.08, 0.66)], [0.014, 0.014, 0.014, 0.014], seg=4, mat="Trim",
         cap_start=True, cap_end=False)
    b.box((0.14, 0.09, 0.2), (0.04, 0.04, 0.03), "PickupCyan")
    a.mesh(b, "Body")
    a.report()
    return a


def build_parachute_pack():
    a = Asset("parachute_pack", PROPS)
    b = MB("parachute_pack_body")
    W, D, H = 0.34, 0.17, 0.44
    cbox(b, (0, -D / 2, 0.0), (W, D, H), c=0.034, mat="PackOrange")
    b.block((0, -D / 2), H / 2, H / 2 + 0.03, (W * 0.96, D * 0.96), (W * 0.84, D * 0.82), mat="PackNavy")
    for sx in (-1, 1):
        b.box((sx * 0.185, -D / 2, -0.1), (0.04, 0.12, 0.14), "PackNavy")
        x = sx * 0.115
        pts = [(x, -0.03, 0.21), (x, 0.01, 0.255), (x, 0.1, 0.235), (x, 0.13, 0.0), (x, 0.12, -0.2)]
        for p0, p1 in zip(pts[:-1], pts[1:]):
            b.beam(p0, p1, 0.017, 0.017, 4, "Webbing", caps=False)
        b.box((x, -0.05 - 0.04 * 0, 0.0), (0.02, 0.0, 0.0), "Strap") if False else None
    b.box((0, 0.13, 0.02), (0.23, 0.014, 0.024), "Webbing")
    b.box((0, 0.14, 0.02), (0.05, 0.012, 0.04), "Chrome")
    b.box((0.115, 0.14, -0.08), (0.04, 0.014, 0.05), "PickupRed")      # ripcord handle
    b.box((0, -D - 0.002, 0.0), (0.02, 0.006, 0.36), "PackNavy")         # back seam
    a.anchor("Attach", (0, 0, 0))
    a.mesh(b, "Body")
    a.report()
    return a


def build_parachute_canopy():
    a = Asset("parachute_canopy", PROPS)
    R, HZ, DOME = 3.5, 4.6, 2.9
    NG = 10
    phis = [90, 66, 42, 18, 6]
    rings = []
    for k, ph in enumerate(phis):
        rr = R * math.sin(math.radians(ph))
        zz = HZ + DOME * math.cos(math.radians(ph))
        ring = []
        for i in range(NG):
            for half in (0, 1):
                ang = 2 * math.pi * (i + 0.5 * half) / NG
                bulge = 1.0 + (0.07 * math.sin(math.radians(ph)) * (1 if half else 0))
                lift = 0.12 * math.sin(math.radians(ph)) * (1 if half else 0)
                ring.append(Vector((math.cos(ang) * rr * bulge, math.sin(ang) * rr * bulge, zz + lift)))
        rings.append(ring)
    b = MB("parachute_canopy_body")
    V = [[b.v(p) for p in ring] for ring in rings]
    n = NG * 2
    for k in range(len(V) - 1):
        for j in range(n):
            j2 = (j + 1) % n
            gore = (j // 2) if True else 0
            # gore boundaries sit on even indices: quad j belongs to gore (j+1)//2 so each gore spans [boundary, mid, boundary]
            g = ((j + 1) // 2) % NG
            b.face([V[k][j], V[k][j2], V[k + 1][j2], V[k + 1][j]], "CanopyA" if g % 2 == 0 else "CanopyB")
    # dark hem skirt
    hem = rings[0]
    low = [Vector((p.x * 0.965, p.y * 0.965, p.z - 0.3)) for p in hem]
    H0 = V[0]
    H1 = [b.v(p) for p in low]
    for j in range(n):
        j2 = (j + 1) % n
        b.face([H0[j], H0[j2], H1[j2], H1[j]], "Trim")
    # vent ring (small cap so the apex isn't a hole in silhouette)
    b.face(list(reversed(V[-1])), "Trim")
    a.mesh(b, "Body")

    L = MB("parachute_canopy_lines")
    Q = {(sx, sy): Vector((sx * 0.3, sy * 0.15, 1.0)) for sx in (-1, 1) for sy in (-1, 1)}
    for i in range(NG):
        ang = 2 * math.pi * i / NG
        p = low[2 * i]
        sx = 1 if math.cos(ang) >= 0 else -1
        sy = 1 if math.sin(ang) >= 0 else -1
        L.beam(tuple(p), tuple(Q[(sx, sy)]), 0.018, 0.018, 3, "LineCord", caps=False)
    for (sx, sy), q in Q.items():
        d = Vector((sx * 0.2, sy * 0.07, 0.0))
        L.beam(tuple(q), tuple(d), 0.024, 0.024, 4, "Strap", caps=False)
        L.box(tuple(d), (0.045, 0.03, 0.035), "Chrome")
    L.box((0, 0, -0.02), (0.46, 0.05, 0.03), "Webbing")
    a.mesh(L, "Lines")
    a.anchor("Attach", (0, 0, 0))
    a.report()
    return a


def build_life_vest():
    a = Asset("life_vest", PROPS)
    b = MB("life_vest_body")
    right = [(0.012, 0.0), (0.2, 0.0), (0.225, 0.06), (0.225, 0.3), (0.185, 0.36), (0.17, 0.5), (0.08, 0.5), (0.05, 0.44), (0.012, 0.4)]
    left = [(-x, z) for x, z in reversed(right)]
    slab(b, right, "xz", 0.02, 0.095, "LifeVestOrange")
    slab(b, left, "xz", 0.02, 0.095, "LifeVestOrange")
    slab(b, vest_outline_lv(), "xz", -0.095, -0.02, "LifeVestOrange")
    for sx in (-1, 1):
        b.box((sx * 0.125, 0, 0.485), (0.09, 0.14, 0.03), "LifeVestOrange")
        b.box((sx * 0.11, 0.098, 0.2), (0.09, 0.008, 0.035), "Reflective")
        b.box((sx * 0.11, -0.098, 0.2), (0.09, 0.008, 0.035), "Reflective")
    # horse-collar around the neck (open at the front)
    pts = []
    for ang in (60, 100, 140, 180, 220, 260, 300):
        t = math.radians(ang)
        pts.append((0.105 * math.sin(t) * -1, 0.095 * math.cos(t), 0.54))
    tube(b, pts, [0.042] * len(pts), seg=5, mat="LifeVestOrange", cap_start=True, cap_end=True, rot=0.3)
    # waist belt + buckle + whistle
    b.box((0, 0.1, 0.08), (0.4, 0.012, 0.03), "Strap")
    b.box((0.0, 0.108, 0.08), (0.05, 0.012, 0.04), "Chrome")
    b.box((0.13, 0.1, 0.42), (0.02, 0.02, 0.045), "Accent")
    a.mesh(b, "Body")
    a.report()
    return a


def vest_outline_lv():
    return [(-0.2, 0.0), (0.2, 0.0), (0.225, 0.06), (0.225, 0.3), (0.185, 0.36), (0.17, 0.5), (0.08, 0.5), (0.0, 0.46), (-0.08, 0.5), (-0.17, 0.5), (-0.185, 0.36),
            (-0.225, 0.3), (-0.225, 0.06)]


BUILDERS = {"scuba_tank": build_scuba_tank, "scuba_gear": build_scuba_gear, "parachute_pack": build_parachute_pack,
            "parachute_canopy": build_parachute_canopy, "life_vest": build_life_vest}
run_builders(BUILDERS, globals().get("ONLY"))
