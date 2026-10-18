"""lane13 beach set: beach_umbrella, beach_towel, deck_chair, surfboard_rack, volleyball_net, campfire.
Origin = footprint centre on the ground, front +Y, flat shaded, <= ~350 tris each."""
CATP = "GTA_GODOT/StreetProps"


def build_beach_umbrella():
    A = A13("beach_umbrella", 110, CATP, spacing=8.0)
    b = HB("beach_umbrella_body")
    n, R, z0, z1 = 8, 1.15, 2.0, 2.42
    with xf(b, about((0, 0, 0), RX(-8))):
        b.cyl((0, 0, 1.2), 0.028, 2.4, 6, "WoodLight", caps="b")                          # pole
        b.cyl((0, 0, 2.43), 0.05, 0.06, 6, "Chrome", caps="t")                            # finial
        for i in range(n):
            a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
            m = "AwningCoral" if i % 2 == 0 else "AwningWhite"
            p0 = (R * math.cos(a0), R * math.sin(a0), z0)
            p1 = (R * math.cos(a1), R * math.sin(a1), z0)
            top = (0, 0, z1)
            b.pq([p0, p1, top], ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, 0.5), m)            # canopy panel (up)
            b.pq([(p0[0] * 0.985, p0[1] * 0.985, p0[2] - 0.02), (p1[0] * 0.985, p1[1] * 0.985, p1[2] - 0.02), (0, 0, z1 - 0.02)], (-(p0[0] + p1[0]) / 2, -(p0[1] + p1[1]) / 2, -0.5), "AwningWhite")   # underside (offset: no z-fight)
            v0 = (p0[0], p0[1], z0 - 0.12)
            v1 = (p1[0], p1[1], z0 - 0.12)
            mid = ((p0[0] + p1[0]) / 2 * 1.02, (p0[1] + p1[1]) / 2 * 1.02, z0 - 0.2)
            b.pq([p0, p1, v1, mid, v0], ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, 0), m)    # scalloped valance
        # ribs
        for i in range(n):
            a = 2 * math.pi * i / n
            b.beam((0, 0, z1 - 0.02), (R * 0.9 * math.cos(a), R * 0.9 * math.sin(a), z0 - 0.02), 0.01, 0.01, 3, "MetalDark", caps=False)
    # sand mound + stabilising bag
    b.cyl((0, 0, 0.09), 0.34, 0.18, 8, "Sand", r_top=0.1, caps="t")
    A.mesh(b, "Body", uv=None)
    return A


def build_beach_towel():
    A = A13("beach_towel", 111, CATP, spacing=8.0)
    b = HB("beach_towel_body")
    W, L, T = 0.85, 1.85, 0.025
    b.abox(-W / 2, W / 2, -L / 2, L / 2, 0.0, T, "AwningWhite", "-z")
    cols = ["DealerTeal", "AwningCoral", "AwningWhite", "DealerTeal", "AwningCoral"]
    n = 5
    for i in range(n):
        y0 = -L / 2 + 0.25 + i * 0.1
        b.zq(T + 0.002, -W / 2, W / 2, y0, y0 + 0.07, 1, cols[i % len(cols)])
        y1 = L / 2 - 0.25 - i * 0.1
        b.zq(T + 0.002, -W / 2, W / 2, y1 - 0.07, y1, 1, cols[(i + 2) % len(cols)])
    for i in range(10):                                                                   # fringe tassels
        x = -W / 2 + 0.04 + i * (W - 0.08) / 9
        b.zq(T * 0.5, x - 0.012, x + 0.012, -L / 2 - 0.05, -L / 2, 1, "AwningWhite")
        b.zq(T * 0.5, x - 0.012, x + 0.012, L / 2, L / 2 + 0.05, 1, "AwningWhite")
    b.cyl((0, 0.7, 0.07), 0.07, 0.45, 6, "AwningCoral", axis="X", rot=0.3)             # rolled head pillow
    A.mesh(b, "Body", uv=None)
    return A


def build_deck_chair():
    A = A13("deck_chair", 112, CATP, spacing=8.0)
    b = HB("deck_chair_body")
    w = 0.30
    for sx in (-w, w):
        b.rbeam((sx, -0.52, 0.03), (sx, -0.06, 0.98), 0.045, 0.035, "WoodLight", up=(1, 0, 0))     # rear leg / backrest rail
        b.rbeam((sx, 0.46, 0.03), (sx, 0.12, 0.52), 0.045, 0.035, "WoodLight", up=(1, 0, 0))       # front leg
        b.rbeam((sx, 0.12, 0.52), (sx, -0.22, 0.3), 0.04, 0.03, "WoodDark", up=(1, 0, 0))          # seat rail
        b.rbeam((sx, 0.46, 0.2), (sx, -0.2, 0.28), 0.03, 0.025, "WoodDark", up=(1, 0, 0))          # lower brace
    b.cyl((0, -0.06, 0.98), 0.02, 2 * w + 0.1, 6, "WoodDark", axis="X")                           # top bar
    b.cyl((0, 0.12, 0.52), 0.02, 2 * w + 0.1, 6, "WoodDark", axis="X")                            # front bar
    b.cyl((0, 0.46, 0.2), 0.02, 2 * w + 0.1, 6, "WoodDark", axis="X")
    b.cyl((0, -0.52, 0.06), 0.02, 2 * w + 0.1, 6, "WoodDark", axis="X")
    # striped sling from the top bar down to the front bar and beyond (sags)
    cols = ["AwningCoral", "AwningWhite", "DealerTeal", "AwningWhite", "AwningCoral"]
    xs = [-w - 0.02 + i * (2 * w + 0.04) / 5 for i in range(6)]
    for i in range(5):
        pts = [(xs[i], -0.06, 0.97), (xs[i + 1], -0.06, 0.97), (xs[i + 1], -0.02, 0.60), (xs[i + 1], 0.22, 0.30), (xs[i], 0.22, 0.30), (xs[i], -0.02, 0.60)]
        b.pq(pts, (0, -0.4, 1), cols[i])
    A.mesh(b, "Body", uv=None)
    return A


def board(b, x, y, L, w, th, mat, stripe, tilt=0.0):
    """upright surfboard (x,z outline) extruded along y, tail at z0 """
    pts = [(-w * 0.34, 0.0), (w * 0.34, 0.0), (w * 0.5, L * 0.18), (w * 0.5, L * 0.55), (w * 0.3, L * 0.82), (0.0, L), (-w * 0.3, L * 0.82), (-w * 0.5, L * 0.55), (-w * 0.5, L * 0.18)]
    with xf(b, about((x, y, 0.28), RX(-tilt))):
        pp = [(x + p[0], 0.28 + p[1]) for p in pts]
        b.ey(pp, y - th / 2, y + th / 2, mat)
        b.pq([(x - w * 0.4, y + th / 2 + 0.002, 0.28 + L * 0.3), (x + w * 0.4, y + th / 2 + 0.002, 0.28 + L * 0.3), (x + w * 0.42, y + th / 2 + 0.002, 0.28 + L * 0.38), (x - w * 0.42, y + th / 2 + 0.002, 0.28 + L * 0.38)], (0, 1, 0), stripe)
        b.pq([(x - 0.01, y + th / 2 + 0.002, 0.28 + L * 0.5), (x + 0.01, y + th / 2 + 0.002, 0.28 + L * 0.5), (x + 0.01, y + th / 2 + 0.002, 0.28 + L * 0.9), (x - 0.01, y + th / 2 + 0.002, 0.28 + L * 0.9)], (0, 1, 0), "TargetWhite")


def build_surfboard_rack():
    A = A13("surfboard_rack", 113, CATP, spacing=8.0)
    b = HB("surfboard_rack_body")
    b.abox(-1.25, 1.25, -0.38, 0.38, 0.0, 0.1, "WoodDark", "-z")                          # base plinth
    b.abox(-1.25, 1.25, -0.38, 0.38, 0.1, 0.24, "WoodLight")                              # slotted bed
    for i in range(6):
        x = -1.1 + i * 0.44
        b.abox(x - 0.025, x + 0.025, -0.36, 0.36, 0.24, 0.36, "WoodDark")                 # slot dividers
    for sx in (-1.2, 1.2):                                                                # uprights with top arm
        b.abox(sx - 0.05, sx + 0.05, -0.34, -0.24, 0.24, 1.55, "WoodDark")
        b.abox(sx - 0.05, sx + 0.05, 0.24, 0.34, 0.24, 1.55, "WoodDark")
    b.abox(-1.25, 1.25, -0.36, -0.22, 1.35, 1.52, "WoodLight")                            # top rails (front/back)
    b.abox(-1.25, 1.25, 0.22, 0.36, 1.35, 1.52, "WoodLight")
    specs = [(-0.88, 2.0, 0.54, "DealerTeal", "AwningWhite"), (-0.44, 2.15, 0.52, "AwningCoral", "AwningWhite"), (0.0, 1.9, 0.5, "AwningWhite", "DealerNavy"),
             (0.44, 2.1, 0.53, "Hazard", "TargetBlack"), (0.88, 1.95, 0.5, "TrainCoral", "AwningWhite")]
    for (x, L, w, m, st) in specs:
        board(b, x, 0.0, min(L, 1.3 - 0.0 + 0.5), w, 0.05, m, st, tilt=0.0)
    A.mesh(b, "Body", uv=None)
    return A


def build_volleyball_net():
    A = A13("volleyball_net", 114, CATP, spacing=14.0)
    b = HB("volleyball_net_body")
    HW, ZT, ZB = 4.75, 2.43, 1.43
    for sx in (-HW - 0.12, HW + 0.12):
        b.cyl((sx, 0, 1.25), 0.045, 2.5, 8, "PoleGrey", caps="t")
        b.cyl((sx, 0, 0.12), 0.18, 0.24, 8, "ConcreteDk", r_top=0.1, caps="t")
        b.cyl((sx, 0, 1.0), 0.052, 0.5, 8, "ConeOrange", caps="")                       # safety pad
        b.ball((sx, 0, 2.52), 0.05, 6, 3, "Chrome")
        # guy line + sand stake
        sgn = -1 if sx < 0 else 1
        b.beam((sx, 0, 2.3), (sx + sgn * 1.3, 0.0, 0.0), 0.008, 0.008, 3, "RopeTan", caps=False)
        b.cyl((sx + sgn * 1.3, 0, 0.06), 0.03, 0.14, 4, "MetalDark", caps="t")
    b.abox(-HW, HW, -0.012, 0.012, ZT - 0.1, ZT, "AwningWhite")                                 # top tape
    b.abox(-HW, HW, -0.01, 0.01, ZB, ZB + 0.05, "AwningWhite")                                  # bottom tape
    n = 24
    for i in range(n + 1):                                                                       # vertical net strands (double sided ribbons)
        x = -HW + i * (2 * HW) / n
        b.pq([(x - 0.006, 0, ZB + 0.05), (x + 0.006, 0, ZB + 0.05), (x + 0.006, 0, ZT - 0.1), (x - 0.006, 0, ZT - 0.1)], (0, 1, 0), "Trim")
    for k in range(1, 4):                                                                        # horizontal strands
        z = ZB + 0.05 + k * (ZT - 0.1 - ZB - 0.05) / 4
        b.pq([(-HW, 0, z - 0.006), (HW, 0, z - 0.006), (HW, 0, z + 0.006), (-HW, 0, z + 0.006)], (0, 1, 0), "Trim")
    for sx in (-HW, HW):                                                                         # antennas (red / white bands)
        for k in range(4):
            b.cyl((sx, 0, ZT + 0.1 + k * 0.2), 0.012, 0.2, 4, "TargetRed" if k % 2 == 0 else "TargetWhite", caps="t")
    A.mesh(b, "Body", uv=None)
    return A


def build_campfire():
    A = A13("campfire", 115, CATP, spacing=8.0)
    b = HB("campfire_body")
    b.disc((0, 0, 0.012), 0.62, 10, 1, "Trim")                                                # ash / burnt ground
    for i in range(8):                                                                         # stone ring
        a = 2 * math.pi * i / 8 + 0.2
        r = 0.55 + 0.04 * ((i * 7) % 3)
        c = (r * math.cos(a), r * math.sin(a), 0.1)
        b.ball(c, 0.16 + 0.025 * ((i * 5) % 3), 5, 2, "Rock" if i % 2 == 0 else "ConcreteDk", sc=(1.0, 0.9, 0.7))
    for i in range(4):                                                                         # crossed logs
        a = math.pi * i / 4 + 0.35
        d = (math.cos(a), math.sin(a), 0)
        b.beam((-d[0] * 0.5, -d[1] * 0.5, 0.1 + 0.05 * (i % 2)), (d[0] * 0.5, d[1] * 0.5, 0.28 + 0.08 * (i % 2)), 0.07, 0.065, 6, "Bark" if i % 2 == 0 else "Wood", caps=True)
    A.mesh(b, "Body", uv=None)
    f = HB("campfire_flame")
    tongues = [(0.0, 0.0, 0.95, 0.15, 0.0), (0.2, 0.06, 0.6, 0.1, 0.4), (-0.18, 0.1, 0.55, 0.1, 1.4), (0.03, -0.19, 0.62, 0.1, 2.4), (-0.05, 0.2, 0.42, 0.08, 0.9)]
    for (tx, ty, h, r, ph) in tongues:
        z0 = 0.2
        ring0 = [(tx + r * math.cos(ph + 2 * math.pi * k / 5), ty + r * math.sin(ph + 2 * math.pi * k / 5), z0) for k in range(5)]
        mid = [(tx + r * 0.75 * math.cos(ph + 2 * math.pi * k / 5 + 0.3) + 0.04, ty + r * 0.75 * math.sin(ph + 2 * math.pi * k / 5 + 0.3), z0 + h * 0.55) for k in range(5)]
        top = (tx + 0.05, ty, z0 + h)
        for k in range(5):
            j = (k + 1) % 5
            f.po([ring0[k], ring0[j], mid[j], mid[k]], (tx, ty, z0), "Flame")
            f.po([mid[k], mid[j], top], (tx, ty, z0), "NeonAmber" if h > 0.7 else "Flame")
    A.mesh(f, "Flame", uv=None)
    A.mark("LightPoint", (0, 0, 0.5), size=0.2)
    return A


A1 = build_beach_umbrella();   A1.report(250)
A2 = build_beach_towel();      A2.report(150)
A3 = build_deck_chair();       A3.report(250)
A4 = build_surfboard_rack();   A4.report(450)
A5 = build_volleyball_net();   A5.report(450)
A6 = build_campfire();         A6.report(350)
