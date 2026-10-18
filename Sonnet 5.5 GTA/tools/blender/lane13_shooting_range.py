"""lane13 shooting_range - outdoor pistol/rifle range ~40 x 34 m: firing-line booth (5 lanes, counters, roof, dividers), 25 m of range with
lane markings and target gantry rail, stepped sandbag backstop berm, side safety walls, flags, warning signs and a small office hut.
Origin = footprint centre at ground; the booth BACK WALL and the hut face +Y (street side, Blender) = -Z in Godot; shooters look down range = -Y (Blender) = +Z (Godot).
Empties: Door (hut), Lane_1..5 (firing positions, forward = down range), Target_1..5 (25 m down range, front +Y facing the shooters)."""

LANE_X = [-10.4, -7.2, -4.0, -0.8, 2.4]
Y_LINE = 13.3                 # shooter standing line
Y_TGT = Y_LINE - 25.0         # -11.7
BX0, BX1 = -12.0, 4.0         # booth x extent between the outer dividers


def flag(b, x0, z0, y, length, height, m, n=5, wave=0.14, phase=0.0):
    """wavy double sided flag attached to a pole at x0 flying towards +x"""
    top = []
    bot = []
    for i in range(n + 1):
        t = i / n
        dy = wave * t * math.sin(phase + t * 5.0)
        dz = -0.05 * t * t
        top.append((x0 + length * t, y + dy, z0 + height + dz))
        bot.append((x0 + length * t, y + dy, z0 + dz))
    for i in range(n):
        q = [bot[i], bot[i + 1], top[i + 1], top[i]]
        b.pq(q, (0, 1, 0), m)


def warn_sign(b, x, y, z, s=1, w=0.9):
    """triangular hazard sign on a post, facing +Y (s=1) or -Y (s=-1): black rim, yellow face, black exclamation mark."""
    h = w * 0.87
    def tri(off, k, m):
        i = k
        pts = [(x - w / 2 + i, y + s * off, z), (x + w / 2 - i, y + s * off, z), (x, y + s * off, z + h - i * 1.7)]
        b.pq(pts, (0, s, 0), m)
    tri(0.025, 0.0, "TargetBlack")
    tri(0.03, 0.07, "Hazard")
    b.pq([(x - 0.035, y + s * 0.035, z + 0.34), (x + 0.035, y + s * 0.035, z + 0.34), (x + 0.03, y + s * 0.035, z + 0.6), (x - 0.03, y + s * 0.035, z + 0.6)], (0, s, 0), "TargetBlack")
    b.pq([(x - 0.035, y + s * 0.035, z + 0.2), (x + 0.035, y + s * 0.035, z + 0.2), (x + 0.035, y + s * 0.035, z + 0.28), (x - 0.035, y + s * 0.035, z + 0.28)], (0, s, 0), "TargetBlack")
    b.pq([(x - w / 2, y, z), (x + w / 2, y, z), (x, y, z + h)], (0, -s, 0), "MetalDark")
    b.beam((x, y - s * 0.03, 0.0), (x, y - s * 0.03, z + 0.2), 0.035, 0.035, 6, "MetalDark")


def target_emblem(b, x, y, z, r, s=1):
    """neon bullseye emblem facing +Y (s=1) / -Y (s=-1)"""
    b.disc((x, y, z), r, 16, s, "TargetBlack", axis="Y")
    b.annulus((x, y + s * 0.01, z), r * 0.72, r * 0.9, 16, s, "NeonRed", axis="Y")
    b.annulus((x, y + s * 0.01, z), r * 0.40, r * 0.58, 16, s, "NeonAmber", axis="Y")
    b.disc((x, y + s * 0.01, z), r * 0.2, 12, s, "NeonRed", axis="Y")
    for a in (0, 90, 180, 270):
        c, sn = math.cos(math.radians(a)), math.sin(math.radians(a))
        b.pq([(x + c * r * 0.93 - sn * 0.03, y + s * 0.012, z + sn * r * 0.93 + c * 0.03), (x + c * r * 1.18 - sn * 0.03, y + s * 0.012, z + sn * r * 1.18 + c * 0.03),
              (x + c * r * 1.18 + sn * 0.03, y + s * 0.012, z + sn * r * 1.18 - c * 0.03), (x + c * r * 0.93 + sn * 0.03, y + s * 0.012, z + sn * r * 0.93 - c * 0.03)], (0, s, 0), "NeonWhite")


def build_shooting_range():
    A = A13("shooting_range", 3, "GTA_GODOT/Buildings", spacing=100.0)
    b = HB("shooting_range_body")
    # ------------------------------------------------------------ ground: apron + range strips + path
    b.abox(-12.8, 4.8, 10.0, 16.6, 0.0, 0.10, "Concrete", "-z")                    # firing apron
    b.abox(-12.4, 4.4, -13.3, 10.0, 0.0, 0.04, "PavingDark", "-z")                 # range floor
    b.abox(-13.6, 5.6, -13.3, -12.5, 0.0, 0.05, "PavingLight", "-z")               # target deck strip
    b.abox(11.8, 14.2, 13.9, 17.0, 0.0, 0.06, "PavingLight", "-z")                 # entrance path
    b.abox(4.8, 12.0, 13.2, 14.4, 0.0, 0.06, "PavingLight", "-z")                  # path booth <-> hut
    # lane lines + distance bars + firing-line markers
    for k in range(1, 5):
        x = BX0 + 3.2 * k
        b.zq(0.045, x - 0.04, x + 0.04, -12.3, 10.0, 1, "LineWhite")
    for d in (5, 10, 15, 20, 25):
        y = Y_LINE - d
        for xl in LANE_X:
            b.zq(0.046, xl - 1.25, xl + 1.25, y - 0.07, y + 0.07, 1, "LineWhite" if d != 25 else "Hazard")
    for xl in LANE_X:
        b.zq(0.105, xl - 0.5, xl + 0.5, Y_LINE - 0.55, Y_LINE - 0.47, 1, "Hazard")      # shooter stance bars
        b.zq(0.105, xl - 0.5, xl + 0.5, Y_LINE + 0.47, Y_LINE + 0.55, 1, "Hazard")
        b.zq(0.105, xl - 0.5, xl - 0.42, Y_LINE - 0.47, Y_LINE + 0.47, 1, "Hazard")
        b.zq(0.105, xl + 0.42, xl + 0.5, Y_LINE - 0.47, Y_LINE + 0.47, 1, "Hazard")
    # ------------------------------------------------------------ booth: back wall, dividers, roof, counters
    b.abox(-12.2, 4.2, 15.6, 16.0, 0.10, 3.1, "WallD", "-z")                         # back wall (street side)
    b.abox(-12.3, 4.3, 15.6, 16.05, 0.0, 0.5, "ConcreteDk", "-z")                   # plinth band
    b.yq(16.06, -12.3, 4.3, 2.45, 2.65, 1, "Hazard")                                 # amber band on the street side
    target_emblem(b, -4.0, 16.05, 1.45, 0.72, 1)
    for k in range(6):
        x = BX0 + 3.2 * k
        b.ex([(11.6, 0.1), (15.7, 0.1), (15.7, 3.1), (11.6, 1.95)], x - 0.12, x + 0.12, "Concrete")      # lane divider panels
        b.abox(x - 0.13, x + 0.13, 11.55, 11.62, 0.1, 1.95, "Hazard", "-y +y -z")                          # hazard front edge
        b.abox(x - 0.07, x + 0.07, 11.3, 11.5, 0.1, 3.1, "Metal")                                          # roof post
    # roof slab + fascia + lamps
    b.abox(-12.6, 4.6, 11.0, 16.4, 3.1, 3.32, "ConcreteDk")
    b.abox(-12.6, 4.6, 10.9, 11.0, 2.78, 3.4, "PoliceNavy")
    b.yq(10.89, -12.6, 4.6, 3.0, 3.1, -1, "Hazard")
    for xl in LANE_X:
        b.zq(3.095, xl - 0.9, xl + 0.9, 12.6, 12.85, -1, "LampGlow")
        b.abox(xl - 0.95, xl + 0.95, 12.55, 12.9, 3.07, 3.1, "MetalDark", "-z")
        # lane number plate (tally marks) on the fascia facing the range
        k = LANE_X.index(xl) + 1
        b.yq(10.88, xl - 0.3, xl + 0.3, 2.84, 3.28, -1, "PlateWhite")
        for i in range(k):
            tx = xl + (i - (k - 1) / 2.0) * 0.1
            b.yq(10.875, tx - 0.025, tx + 0.025, 2.92, 3.20, -1, "TargetBlack")
    # counters (shooting benches)
    for xl in LANE_X:
        b.abox(xl - 1.46, xl + 1.46, 11.95, 12.55, 0.1, 1.0, "PoleGreen", "-z")
        b.abox(xl - 1.48, xl + 1.48, 11.88, 12.6, 1.0, 1.07, "WoodDark")
        b.abox(xl - 0.55, xl + 0.55, 12.02, 12.42, 1.07, 1.16, "SandBag", "-z")                # rest bag
        b.abox(xl + 1.00, xl + 1.30, 12.1, 12.35, 1.07, 1.19, "MetalDark", "-z")               # target controller
        b.abox(xl + 1.08, xl + 1.14, 11.99, 12.03, 1.12, 1.16, "LightRed", "-y")
        b.abox(xl + 1.18, xl + 1.24, 11.99, 12.03, 1.12, 1.16, "NeonGreen", "-y")
        b.yq(11.949, xl - 1.4, xl + 1.4, 0.55, 0.7, -1, "Hazard")
        # hearing-protection hook board on the back wall
        b.abox(xl - 0.4, xl + 0.4, 15.45, 15.6, 1.35, 1.75, "WoodLight", "-y")
        for dx in (-0.2, 0.2):
            b.abox(xl + dx - 0.07, xl + dx + 0.07, 15.3, 15.45, 1.4, 1.58, "TargetRed", "-y")
    # status beacons on the roof (range hot / cold)
    b.cyl((-12.0, 11.3, 3.5), 0.1, 0.36, 8, "MetalDark", caps="t")
    b.cyl((-12.0, 11.3, 3.78), 0.14, 0.22, 8, "LightRed", caps="t")
    b.cyl((4.0, 11.3, 3.5), 0.1, 0.36, 8, "MetalDark", caps="t")
    b.cyl((4.0, 11.3, 3.78), 0.14, 0.22, 8, "NeonGreen", caps="t")
    # ------------------------------------------------------------ down range
    # side safety walls (sandbag courses) + hazard caps
    for x in (-12.7, 4.7):
        b.abox(x - 0.25, x + 0.25, -14.0, 10.0, 0.0, 1.15, "SandBag", "-z")
        b.abox(x - 0.27, x + 0.27, -14.0, 10.0, 1.15, 1.22, "ConcreteDk")
        for yy in range(-13, 10, 4):
            b.abox(x - 0.28, x + 0.28, yy, yy + 0.4, 1.0, 1.24, "Hazard", "-z")
        for yy in range(-14, 10, 1):
            pass
    # backstop berm - stepped sandbag courses facing +Y
    prof = [(-17.2, 0.0), (-13.8, 0.0), (-13.8, 0.85), (-14.2, 0.85), (-14.2, 1.7), (-14.6, 1.7), (-14.6, 2.55), (-15.0, 2.55), (-15.0, 3.4), (-17.2, 3.4)]
    b.ex(prof, -14.0, 6.0, "SandBag")
    for zt in (0.85, 1.7, 2.55, 3.4):
        pass
    b.abox(-14.0, 6.0, -15.0, -14.6, 3.4, 3.46, "ConcreteDk", "-z")
    # target gantry rail: 2 posts + 4 pairs of struts, I-beam at 2.9 m, trolleys
    zr = 2.95
    for x in (-13.3, 5.3):
        b.abox(x - 0.1, x + 0.1, Y_TGT - 0.1, Y_TGT + 0.1, 0.05, zr, "Metal", "-z")
        b.abox(x - 0.22, x + 0.22, Y_TGT - 0.22, Y_TGT + 0.22, 0.0, 0.12, "ConcreteDk", "-z")
    for k in range(1, 5):
        x = BX0 + 3.2 * k
        b.abox(x - 0.05, x + 0.05, Y_TGT - 0.05, Y_TGT + 0.05, zr - 0.7, zr, "Metal", "-z")
    b.abox(-13.5, 5.5, Y_TGT - 0.12, Y_TGT + 0.12, zr, zr + 0.08, "MetalDark")
    b.abox(-13.5, 5.5, Y_TGT - 0.04, Y_TGT + 0.04, zr - 0.18, zr, "MetalDark")
    b.abox(-13.5, 5.5, Y_TGT - 0.12, Y_TGT + 0.12, zr - 0.2, zr - 0.18, "MetalDark")
    for xl in LANE_X:
        b.abox(xl - 0.18, xl + 0.18, Y_TGT - 0.15, Y_TGT + 0.15, zr - 0.3, zr - 0.18, "Hazard", "+z")
        b.abox(xl - 0.5, xl + 0.5, Y_TGT - 0.35, Y_TGT + 0.35, 0.05, 0.1, "Concrete", "-z")         # target pad
        for sx in (-1, 1):
            for sy in (-1, 1):
                b.abox(xl + sx * 0.5 - 0.04, xl + sx * 0.5 + 0.04 - (0.08 if sx > 0 else 0) * 0, Y_TGT + sy * 0.35 - 0.04, Y_TGT + sy * 0.35 + 0.04, 0.1, 0.13, "Hazard", "-z")
    # ------------------------------------------------------------ flags / signs
    b.cyl((-12.0, 10.9, 4.0), 0.035, 3.2, 6, "Metal", caps="t")
    flag(b, -12.0, 4.3, 10.9, 1.5, 0.9, "FlagRed", phase=0.4)                         # RANGE flag on the roof (red = live fire)
    for (px, py) in ((18.4, 15.8),):
        b.lathe([(6.6, 0.0), (6.6, 0.025), (0.35, 0.05), (0.35, 0.09), (0.22, 0.09), (0.22, 0.22), (0.0, 0.22), (0.0, 0.0)], (px, py, 0.0), 8, "Metal", axis="Z")
        b.ball((px, py, 6.7), 0.07, 6, 3, "Brass")
        flag(b, px, 4.7, py, 1.9, 1.15, "FlagBlue", wave=0.2, phase=1.3)
    for (px, py, ss) in ((-12.7, 11.0, 1), (4.7, 11.0, 1), (-4.0, -13.9, 1), (8.0, 15.5, 1), (18.2, 12.5, 1)):
        warn_sign(b, px, py, 1.55, ss)
    # danger entry: red roundel on a post at the range side entrance
    b.beam((7.6, 9.2, 0.0), (7.6, 9.2, 1.9), 0.04, 0.04, 6, "MetalDark")
    b.disc((7.6, 9.26, 1.95), 0.3, 16, 1, "PlateRed", axis="Y")
    b.pq([(7.6 - 0.2, 9.265, 1.92), (7.6 + 0.2, 9.265, 1.92), (7.6 + 0.2, 9.265, 1.98), (7.6 - 0.2, 9.265, 1.98)], (0, 1, 0), "PlateWhite")
    # roadside pylon sign (street side, left) with a big neon bullseye
    b.abox(-15.4, -14.8, 16.2, 16.8, 0.0, 0.5, "ConcreteDk", "-z")
    b.abox(-15.25, -14.95, 16.35, 16.65, 0.5, 4.6, "MetalDark", "-z")
    b.abox(-16.9, -13.3, 16.3, 16.7, 4.2, 7.0, "PoliceNavy")
    b.abox(-16.95, -13.25, 16.28, 16.72, 6.95, 7.1, "Hazard")
    b.abox(-16.95, -13.25, 16.28, 16.72, 4.1, 4.25, "Hazard")
    target_emblem(b, -15.1, 16.71, 5.6, 1.1, 1)
    target_emblem(b, -15.1, 16.29, 5.6, 1.1, -1)
    # ------------------------------------------------------------ office hut x 9..17, y 6..14, h 3.2
    hx0, hx1, hy0, hy1, hh = 9.0, 17.0, 6.0, 14.0, 3.2
    b.abox(hx0, hx1, hy0, hy1, 0.0, hh, "WallA", "-z")
    b.abox(hx0 - 0.1, hx1 + 0.1, hy0 - 0.1, hy1 + 0.1, 0.0, 0.35, "ConcreteDk", "-z")        # plinth
    b.abox(hx0 - 0.3, hx1 + 0.3, hy0 - 0.3, hy1 + 0.4, hh, hh + 0.18, "Trim")                  # roof slab
    b.abox(hx0 - 0.3, hx1 + 0.3, hy1 + 0.38, hy1 + 0.42, hh - 0.5, hh + 0.4, "PoliceNavy", "-z")   # front sign fascia
    b.zq(hh + 0.19, hx0 - 0.3, hx1 + 0.3, hy0 - 0.3, hy1 + 0.4, 1, "Roof")
    b.yq(hy1 + 0.43, hx0 - 0.3, hx1 + 0.3, hh - 0.5, hh - 0.35, 1, "Hazard")
    def hwin(face, c, w, z0, z1):
        t = 0.05
        if face == "F":
            b.abox(c - w / 2 - 0.07, c + w / 2 + 0.07, hy1, hy1 + t, z0 - 0.07, z1 + 0.07, "Trim", "-y")
            b.yq(hy1 + t + 0.004, c - w / 2, c + w / 2, z0, z1, 1, "Glass")
            b.yq(hy1 + t + 0.01, c - 0.02, c + 0.02, z0, z1, 1, "Trim")
        elif face == "L":
            b.abox(hx0 - t, hx0, c - w / 2 - 0.07, c + w / 2 + 0.07, z0 - 0.07, z1 + 0.07, "Trim", "+x")
            b.xq(hx0 - t - 0.004, c - w / 2, c + w / 2, z0, z1, -1, "Glass")
        else:
            b.abox(hx1, hx1 + t, c - w / 2 - 0.07, c + w / 2 + 0.07, z0 - 0.07, z1 + 0.07, "Trim", "-x")
            b.xq(hx1 + t + 0.004, c - w / 2, c + w / 2, z0, z1, 1, "Glass")
    hwin("F", 10.8, 1.5, 1.0, 2.5)
    hwin("F", 15.2, 1.5, 1.0, 2.5)
    hwin("L", 10.0, 2.0, 1.0, 2.4)
    hwin("L", 13.0, 1.4, 1.0, 2.4)
    hwin("R", 10.0, 2.0, 1.0, 2.4)
    hwin("R", 13.0, 1.4, 1.0, 2.4)
    # door + step + canopy (door centre x = 13.0)
    b.abox(12.4, 13.6, hy1, hy1 + 0.07, 0.0, 2.2, "Trim", "-y")                            # door frame
    b.abox(12.5, 13.5, hy1 + 0.07, hy1 + 0.1, 0.05, 2.15, "DealerTeal", "-y")              # door leaf
    b.yq(hy1 + 0.105, 12.62, 13.38, 1.2, 1.9, 1, "Glass")
    b.abox(13.3, 13.34, hy1 + 0.1, hy1 + 0.14, 1.0, 1.1, "Chrome")
    b.abox(12.0, 14.0, hy1, hy1 + 1.2, 0.0, 0.18, "Concrete", "-z")                         # step
    b.abox(11.8, 14.2, hy1, hy1 + 1.5, 2.55, 2.65, "DealerTeal")                             # small canopy over the door
    for sx in (11.9, 14.1):
        b.abox(sx - 0.04, sx + 0.04, hy1 + 1.4, hy1 + 1.48, 0.0, 2.55, "Metal", "-z")
    target_emblem(b, 13.0, hy1 + 0.43, 2.95, 0.34, 1)
    # lamp on hut + small AC + bin
    b.abox(10.0, 11.2, 9.0, 10.0, hh + 0.19, hh + 0.9, "Metal")
    b.abox(hx1 + 0.1, hx1 + 0.6, 7.0, 8.0, 0.0, 0.75, "MetalDark", "-z")
    b.cyl((16.2, hy1 + 1.0, 0.45), 0.28, 0.9, 6, "PoleGreen", caps="t")
    # bench by the path
    b.abox(14.8, 16.6, hy1 + 1.3, hy1 + 1.75, 0.45, 0.52, "WoodLight")
    for sx in (15.0, 16.4):
        b.abox(sx - 0.05, sx + 0.05, hy1 + 1.35, hy1 + 1.7, 0.0, 0.45, "MetalDark", "-z")
    A.mesh(b, "Body")
    # ------------------------------------------------------------ collision proxy
    c = HB("shooting_range_col")
    c.abox(-12.2, 4.2, 15.6, 16.0, 0.0, 3.1, "Concrete", "-z")
    for k in range(6):
        x = BX0 + 3.2 * k
        c.abox(x - 0.12, x + 0.12, 11.6, 15.7, 0.0, 3.1, "Concrete", "-z")
    for xl in LANE_X:
        c.abox(xl - 1.46, xl + 1.46, 11.9, 12.6, 0.0, 1.07, "Concrete", "-z")
    c.abox(-12.6, 4.6, 11.0, 16.4, 2.8, 3.4, "Concrete", "-z")
    for x in (-12.7, 4.7):
        c.abox(x - 0.25, x + 0.25, -14.0, 10.0, 0.0, 1.22, "Concrete", "-z")
    c.abox(-14.0, 6.0, -17.2, -13.8, 0.0, 3.46, "Concrete", "-z")
    c.abox(hx0, hx1, hy0, hy1, 0.0, hh + 0.2, "Concrete", "-z")
    A.mesh(c, "Collision", uv=None)
    # ------------------------------------------------------------ anchors
    for i, xl in enumerate(LANE_X):
        A.mark("Lane_%d" % (i + 1), (xl, Y_LINE, 0.10), rot=(0, 0, 180), size=0.4)
        A.mark("Target_%d" % (i + 1), (xl, Y_TGT, 0.05), size=0.4)
    A.mark("Door", (13.0, hy1 + 1.9, 0.0), size=0.5)
    A.mark("FiringLine", (-4.0, Y_LINE, 0.10), rot=(0, 0, 180), size=0.3)
    A.mark("RangeBeacon", (-12.0, 11.3, 3.9), size=0.2)
    return A


A = build_shooting_range()
rep = A.report(3000)
