"""lane13 dealer_lot - open-air used-car dealership 60 x 40 m: glass sales office under a big canopy with a neon car sign, 12 marked stalls (3.2 x 5.5 m)
facing the street, string-light poles with LampGlow bulbs + pennants, price board, flag poles, low wall / fence frame, showcase ramp.
Origin = footprint centre at ground; street / front = +Y (-> -Z in Godot). Empties: Door, Stall_1..12 (stall centre, forward +Y = nose to the street), Showroom (ramp top)."""

ZL = 0.06
STALL_X = [-21.1 + 3.2 * i for i in range(6)] + [5.1 + 3.2 * i for i in range(6)]
STALL_Y = 10.75


def car_icon(b, x, y, z, k=1.0, face=1, mat="NeonCyan"):
    """flat neon car silhouette (side view) in the XZ plane facing +Y (face=1) or -Y, scale k, ~3 m long"""
    pts = [(-1.5, 0.25), (-1.5, 0.7), (-1.0, 0.85), (-0.55, 1.3), (0.5, 1.3), (1.0, 0.85), (1.5, 0.72), (1.5, 0.25)]
    pts = [(x + p[0] * k, z + p[1] * k) for p in pts]
    b.ey(pts, y, y + 0.06 * face, mat)
    for wx in (-0.9, 0.9):
        b.disc((x + wx * k, y + 0.07 * face if face > 0 else y + 0.07 * face, z + 0.22 * k), 0.26 * k, 8, face, "NeonWhite", axis="Y")


def wire(b, pts, w=0.03):
    """thin double-sided vertical ribbon along a polyline (cheap wire)"""
    for i in range(len(pts) - 1):
        a, c = pts[i], pts[i + 1]
        q = [a, c, (c[0], c[1], c[2] - w), (a[0], a[1], a[2] - w)]
        b.pq(q, (0, 1, 0), "MetalDark")


def string_span(b, p0, p1, sag, n, bulb_mat="LampGlow"):
    """wire with n bulbs between p0 and p1 (sagging by `sag` at the middle)"""
    pts = []
    for i in range(n + 1):
        t = i / n
        p = [p0[k] + (p1[k] - p0[k]) * t for k in range(3)]
        p[2] -= sag * math.sin(math.pi * t)
        pts.append(p)
    wire(b, pts)
    for p in pts[1:-1]:
        b.ball((p[0], p[1], p[2] - 0.1), 0.09, 4, 2, bulb_mat)


def pennants(b, p0, p1, sag, n, mats):
    pts = []
    for i in range(n + 1):
        t = i / n
        p = [p0[k] + (p1[k] - p0[k]) * t for k in range(3)]
        p[2] -= sag * math.sin(math.pi * t)
        pts.append(p)
    for i in range(n):
        a, c = Vector(pts[i]), Vector(pts[i + 1])
        m = Vector(((a + c) / 2))
        w = (c - a).length * 0.42
        tip = (m.x, m.y, m.z - 0.5)
        l = (m.x - (c.x - a.x) * 0.42 / 2 * 1.0, m.y - (c.y - a.y) * 0.21, m.z - (c.z - a.z) * 0.21)
        r = (m.x + (c.x - a.x) * 0.42 / 2 * 1.0, m.y + (c.y - a.y) * 0.21, m.z + (c.z - a.z) * 0.21)
        mm = mats[i % len(mats)]
        b.pq([l, r, tip], (0, 1, 0), mm)
    wire(b, pts)


def build_dealer_lot():
    A = A13("dealer_lot", 5, "GTA_GODOT/Buildings", spacing=100.0)
    b = HB("dealer_lot_body")
    # ------------------------------------------------------------ ground, kerbs, stall markings
    b.abox(-30.0, 30.0, -20.0, 20.0, 0.0, ZL, "PavingDark", "-z")
    kh = 0.16
    for (x0, x1, y0, y1) in ((-30.0, -6.0, 19.6, 20.0), (6.0, 30.0, 19.6, 20.0)):                    # front kerb with a 12 m gate gap
        b.abox(x0, x1, y0, y1, 0.0, kh, "PavingLight", "-z")
    b.abox(-30.0, -29.6, -20.0, 19.6, 0.0, kh, "PavingLight", "-z")
    b.abox(29.6, 30.0, -20.0, 19.6, 0.0, kh, "PavingLight", "-z")
    b.abox(-29.6, 29.6, -20.0, -19.6, 0.0, kh, "PavingLight", "-z")
    b.abox(-6.0, 6.0, 17.5, 20.0, 0.0, ZL + 0.01, "PavingLight", "-z")                                 # gate apron
    for g in (0, 1):
        x0 = STALL_X[g * 6] - 1.6
        for k in range(7):                                                                            # stall separators
            x = x0 + 3.2 * k
            b.zq(ZL + 0.004, x - 0.05, x + 0.05, STALL_Y - 2.75, STALL_Y + 2.75, 1, "StallPaint")
        b.zq(ZL + 0.004, x0, x0 + 19.2, STALL_Y - 2.75 - 0.05, STALL_Y - 2.75 + 0.05, 1, "StallPaint")   # rear line
    # driving arrows on the aisle
    for xa in (-12.0, 12.0):
        b.pq([(xa - 0.18, 3.2, ZL + 0.004), (xa + 0.18, 3.2, ZL + 0.004), (xa + 0.18, 4.6, ZL + 0.004), (xa + 0.5, 4.6, ZL + 0.004), (xa, 5.5, ZL + 0.004), (xa - 0.5, 4.6, ZL + 0.004), (xa - 0.18, 4.6, ZL + 0.004)], (0, 0, 1), "StallPaint")
    # ------------------------------------------------------------ sales office (x -9..9, y -19.3..-10)
    ox0, ox1, oy0, oy1, oh = -9.0, 9.0, -19.3, -10.0, 3.7
    b.abox(ox0 - 0.3, ox1 + 0.3, oy0 - 0.3, oy1 + 0.2, ZL, 0.25, "ConcreteDk", "-z")               # plinth
    b.abox(ox0, ox1, oy0, oy0 + 0.25, 0.25, oh, "WallD", "-z")                                     # back wall
    b.abox(ox0, ox0 + 0.25, oy0, oy1, 0.25, oh, "WallD", "-z")                                     # side walls
    b.abox(ox1 - 0.25, ox1, oy0, oy1, 0.25, oh, "WallD", "-z")
    b.zq(0.25, ox0 + 0.25, ox1 - 0.25, oy0 + 0.25, oy1, 1, "TrainFloor")                           # floor
    b.abox(ox0 - 0.2, ox1 + 0.2, oy0 - 0.2, oy1 + 0.1, oh, oh + 0.3, "Trim")                       # office roof slab (flat)
    b.zq(oh + 0.31, ox0 - 0.2, ox1 + 0.2, oy0 - 0.2, oy1 + 0.1, 1, "Roof")
    # front curtain wall: glass between mullions, plinth, double door
    b.abox(ox0, ox1, oy1 - 0.2, oy1, 0.25, 0.7, "DealerNavy")
    for i in range(10):
        x = ox0 + 0.1 + i * 1.8
        b.abox(x - 0.06, x + 0.06, oy1 - 0.12, oy1 + 0.04, 0.7, oh, "Metal")
    for (xa, xb) in ((ox0 + 0.1, -1.0), (1.0, ox1 - 0.1)):
        b.yq(oy1 - 0.06, xa, xb, 0.7, oh - 0.1, 1, "Glass")
    b.yq(oy1 - 0.06, -1.0, 1.0, 2.4, oh - 0.1, 1, "Glass")
    b.abox(-1.0, 1.0, oy1 - 0.1, oy1 + 0.06, 2.2, 2.4, "Metal")                                   # door header
    for sx in (-1, 1):                                                                            # glass double door leaves
        b.abox(sx * 0.5 - 0.46 if sx < 0 else 0.04, sx * 0.5 + 0.46 if sx > 0 else -0.04, oy1 - 0.1, oy1 - 0.05, 0.25, 2.2, "Metal", "-y +y")
        b.yq(oy1 - 0.04, (-0.9 if sx < 0 else 0.1), (-0.1 if sx < 0 else 0.9), 0.4, 2.1, 1, "Glass")
    b.abox(-0.03, 0.03, oy1 - 0.12, oy1 + 0.0, 0.25, 2.2, "TargetBlack")
    # interior: reception desk, chairs, plant, ceiling lights, back-wall display
    b.abox(-4.5, -1.0, -16.0, -15.0, 0.25, 1.1, "WoodLight")
    b.abox(-4.6, -0.9, -16.1, -14.9, 1.1, 1.17, "CounterTop") if "CounterTop" in bpy.data.materials else b.abox(-4.6, -0.9, -16.1, -14.9, 1.1, 1.17, "Trim")
    for cx in (-3.5, -2.0):
        b.abox(cx - 0.25, cx + 0.25, -14.7, -14.2, 0.25, 0.5, "TrainSeat", "-z")
        b.abox(cx - 0.25, cx + 0.25, -14.25, -14.2, 0.5, 1.0, "TrainSeatDk", "-z")
    for cx in (4.0, 6.0):
        b.abox(cx - 0.3, cx + 0.3, -13.2, -12.6, 0.25, 0.5, "TrainCoral", "-z")
        b.abox(cx - 0.3, cx + 0.3, -12.65, -12.6, 0.5, 1.05, "TrainCoral", "-z")
    b.abox(3.8, 6.2, -13.0, -11.6, 0.25, 0.42, "WoodDark")                                          # waiting table
    b.cyl((7.8, -11.0, 0.45), 0.25, 0.4, 6, "TargetTan", caps="t")                                  # pot
    b.ball((7.8, -11.0, 1.15), 0.5, 5, 3, "Leaf")
    for (lx, ly) in ((-5.0, -14.0), (5.0, -14.0), (-5.0, -17.5), (5.0, -17.5), (0.0, -14.0), (0.0, -17.5)):
        b.zq(oh - 0.01, lx - 0.6, lx + 0.6, ly - 0.3, ly + 0.3, -1, "LampGlow")
    b.zq(oh - 0.015, ox0 + 0.25, ox1 - 0.25, oy0 + 0.25, oy1, -1, "TrainCeil")
    b.abox(-8.5, -5.5, oy0 + 0.25, oy0 + 0.4, 0.8, 2.6, "DealerTeal", "-y")                         # back wall panel
    b.abox(5.5, 8.5, oy0 + 0.25, oy0 + 0.4, 0.8, 2.6, "DealerNavy", "-y")
    # canopy (x -10.5..10.5, y -19.3..-5.5) on 4 round columns, emissive underside, fascia with neon
    cy0, cy1, cz = oy0 - 0.2, -5.5, 3.95
    b.abox(-10.5, 10.5, cy0, cy1, cz, cz + 0.3, "Trim")
    b.zq(cz - 0.01, ox0 - 0.2, ox1 + 0.2, oy1 + 0.1, cy1 - 0.15, -1, "LampGlow")
    b.abox(-10.5, 10.5, cy1 - 0.05, cy1 + 0.1, cz - 0.3, cz + 0.55, "DealerNavy")
    b.yq(cy1 + 0.11, -10.5, 10.5, cz + 0.1, cz + 0.2, 1, "NeonCyan")
    b.yq(cy1 + 0.11, -10.5, 10.5, cz - 0.15, cz - 0.05, 1, "NeonAmber")
    b.zq(cz + 0.31, -10.5, 10.5, cy0, cy1, 1, "Roof")
    for cx in (-9.0, -3.2, 3.2, 9.0):
        b.lathe([(cz, 0.0), (cz, 0.22), (cz - 0.1, 0.22), (cz - 0.1, 0.16), (0.3, 0.16), (0.3, 0.2), (0.0, 0.2), (0.0, 0.0)], (cx, cy1 - 0.4, 0.0), 8, "WallD", axis="Z", rot=0.4)
        b.cyl((cx, cy1 - 0.4, 0.65), 0.215, 0.07, 8, "NeonCyan", caps="", rot=0.4)
    # roof sign tower with the neon car icon (faces the street), two-sided
    b.abox(-4.6, 4.6, -18.8, -18.2, cz + 0.3, cz + 3.2, "DealerNavy")
    b.abox(-4.7, 4.7, -18.82, -18.18, cz + 3.15, cz + 3.3, "DealerTeal")
    b.abox(-4.7, 4.7, -18.82, -18.18, cz + 0.3, cz + 0.45, "DealerTeal")
    car_icon(b, 0.0, -17.88, cz + 1.0, 1.0, 1)
    car_icon(b, 0.0, -19.12, cz + 1.0, 1.0, -1)
    for sx in (-1, 1):
        b.yq(-17.88, sx * 3.7, sx * 4.3, cz + 0.8, cz + 2.9, 1, "NeonAmber") if sx > 0 else b.yq(-17.88, sx * 4.3, sx * 3.7, cz + 0.8, cz + 2.9, 1, "NeonAmber")
    # ------------------------------------------------------------ showcase ramp (x 14..23, y -7..-1.5)
    b.ex([(-7.0, 0.0), (-1.5, 0.0), (-1.5, 0.35), (-6.0, 0.9), (-7.0, 0.9)], 14.0, 23.0, "Concrete")
    b.zq(0.905, 14.0, 23.0, -7.0, -6.0, 1, "TargetWhite")
    b.yq(-1.49, 14.0, 23.0, 0.0, 0.35, 1, "NeonAmber")
    b.pq([(14.0, -6.0, 0.9), (14.0, -1.5, 0.35), (14.0, -1.5, 0.37), (14.0, -6.0, 0.92)], (-1, 0, 0), "NeonCyan")
    b.pq([(23.0, -6.0, 0.9), (23.0, -1.5, 0.35), (23.0, -1.5, 0.37), (23.0, -6.0, 0.92)], (1, 0, 0), "NeonCyan")
    # ------------------------------------------------------------ fence frame on the sides + back (rails, posts), low wall
    for x in (-29.6, 29.6):
        b.abox(x - 0.05, x + 0.05, -19.6, 19.6, 1.05, 1.12, "MetalDark")
        b.abox(x - 0.04, x + 0.04, -19.6, 19.6, 0.35, 0.40, "MetalDark")
    b.abox(-29.6, 29.6, -19.65, -19.55, 1.05, 1.12, "MetalDark")
    b.abox(-29.6, 29.6, -19.65, -19.55, 0.35, 0.40, "MetalDark")
    for k in range(0, 7):
        yy = -19.6 + k * (39.2 / 6)
        for x in (-29.6, 29.6):
            b.abox(x - 0.07, x + 0.07, yy - 0.07, yy + 0.07, kh, 1.25, "Metal", "-z")
    for k in range(1, 9):
        xx = -29.6 + k * (59.2 / 9)
        b.abox(xx - 0.07, xx + 0.07, -19.72, -19.58, kh, 1.25, "Metal", "-z")
    # gate posts + small planters flanking the entrance
    for gx in (-6.0, 6.0):
        b.abox(gx - 0.25, gx + 0.25, 19.5, 20.1, 0.0, 2.6, "DealerNavy", "-z")
        b.abox(gx - 0.3, gx + 0.3, 19.45, 20.15, 2.6, 2.75, "DealerTeal")
        b.cbox((gx, 19.8, 3.0), (0.3, 0.3, 0.3), "LampGlow")
    # ------------------------------------------------------------ price board (x -13..-8.4, y 16.6)
    px, py = -10.5, 16.2
    for sx in (-2.1, 2.1):
        b.abox(px + sx - 0.07, px + sx + 0.07, py - 0.07, py + 0.07, 0.0, 2.6, "MetalDark", "-z")
    b.abox(px - 2.4, px + 2.4, py - 0.1, py + 0.1, 1.0, 2.75, "DealerNavy")
    b.abox(px - 2.5, px + 2.5, py - 0.12, py + 0.12, 2.75, 2.88, "DealerTeal")
    b.abox(px - 2.5, px + 2.5, py - 0.12, py + 0.12, 0.94, 1.0, "DealerTeal")
    for r in range(3):
        z0 = 1.15 + r * 0.55
        b.yq(py + 0.105, px - 2.2, px - 0.4, z0, z0 + 0.34, 1, "PlateWhite")
        b.yq(py + 0.105, px - 0.2, px + 1.1, z0, z0 + 0.34, 1, "TargetBlack")
        b.yq(py + 0.11, px + 1.25, px + 2.2, z0, z0 + 0.34, 1, "NeonAmber" if r != 1 else "NeonGreen")
        for i in range(3):
            b.yq(py + 0.11, px - 2.1 + i * 0.5, px - 1.75 + i * 0.5, z0 + 0.06, z0 + 0.28, 1, "TargetBlack")
    b.yq(py + 0.105, px - 2.2, px + 2.2, 2.2, 2.62, 1, "DealerTeal")
    car_icon(b, px, py + 0.11, 2.2, 0.38, 1, "NeonWhite")
    b.yq(py - 0.105, px - 2.4, px + 2.4, 1.0, 2.75, -1, "MetalDark")
    # ------------------------------------------------------------ string lights + pennants + flag poles
    pole_x = [-28.8, -14.4, 0.0, 14.4, 28.8]
    for xp in pole_x:
        b.lathe([(5.6, 0.0), (5.6, 0.04), (0.25, 0.07), (0.25, 0.14), (0.0, 0.14), (0.0, 0.0)], (xp, 18.0, 0.0), 6, "PoleGrey", axis="Z")
        b.cbox((xp, 18.0, 5.65), (0.2, 0.2, 0.12), "MetalDark")
    for i in range(4):
        string_span(b, (pole_x[i], 18.0, 5.55), (pole_x[i + 1], 18.0, 5.55), 0.8, 7)
        pennants(b, (pole_x[i], 18.0, 4.6), (pole_x[i + 1], 18.0, 4.6), 0.5, 8, ["FlagRed", "AwningWhite", "FlagBlue", "Hazard", "DealerTeal"])
    for xs in (-6.9, 6.9):
        b.lathe([(8.2, 0.0), (8.2, 0.03), (0.4, 0.06), (0.4, 0.12), (0.0, 0.12), (0.0, 0.0)], (xs, 18.9, 0.0), 6, "Metal", axis="Z")
        b.ball((xs, 18.9, 8.28), 0.09, 6, 3, "Brass")
    flag(b, -6.9, 6.5, 18.9, 2.6, 1.5, "FlagRed", n=6, wave=0.28, phase=0.6)
    flag(b, 6.9, 6.5, 18.9, 2.6, 1.5, "FlagBlue", n=6, wave=0.28, phase=2.0)
    A.mesh(b, "Body")
    # ------------------------------------------------------------ collision proxy
    c = HB("dealer_lot_col")
    c.abox(ox0, ox1, oy0, oy1, 0.0, oh + 0.3, "Concrete", "-z")
    for cx in (-9.0, -3.2, 3.2, 9.0):
        c.abox(cx - 0.25, cx + 0.25, cy1 - 0.65, cy1 - 0.15, 0.0, cz, "Concrete", "-z")
    c.abox(-10.5, 10.5, cy0, cy1, cz, cz + 0.3, "Concrete", "-z")
    c.abox(-4.6, 4.6, -18.8, -18.2, cz + 0.3, cz + 3.3, "Concrete", "-z")
    c.ex([(-7.0, 0.0), (-1.5, 0.0), (-1.5, 0.35), (-6.0, 0.9), (-7.0, 0.9)], 14.0, 23.0, "Concrete")
    c.abox(-30.0, -29.6, -20.0, 19.6, 0.0, 1.1, "Concrete", "-z")
    c.abox(29.6, 30.0, -20.0, 19.6, 0.0, 1.1, "Concrete", "-z")
    c.abox(-30.0, 30.0, -20.0, -19.6, 0.0, 1.1, "Concrete", "-z")
    for gx in (-6.0, 6.0):
        c.abox(gx - 0.25, gx + 0.25, 19.5, 20.1, 0.0, 2.75, "Concrete", "-z")
    A.mesh(c, "Collision", uv=None)
    # ------------------------------------------------------------ anchors
    for i, xs in enumerate(STALL_X):
        A.mark("Stall_%d" % (i + 1), (xs, STALL_Y, ZL), size=0.5)
    A.mark("Door", (0.0, oy1 + 1.6, 0.25), size=0.5)
    A.mark("Showroom", (18.5, -4.0, 0.9), size=0.5)
    A.mark("PriceBoard", (px, py + 0.2, 1.8), size=0.3)
    return A


exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane13_shooting_range.py", encoding="utf8").read().split("def build_shooting_range")[0], globals())     # reuse flag()
A = build_dealer_lot()
rep = A.report(3200)
