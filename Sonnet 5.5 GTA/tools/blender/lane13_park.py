"""lane13 park set: tent, picnic_table, trash_can_park, swing_set (+Swing_1/2 pivots), slide, ice_cream_cart, hotdog_stand.
Origin = footprint centre on the ground, front +Y, flat shaded."""
CATP = "GTA_GODOT/StreetProps"


def panel(b, pts, n, m_out, m_in, off=0.02):
    """fabric panel with a different inner colour (inner copy pushed `off` inwards so the two layers never z-fight)."""
    nv = Vector(n).normalized()
    b.pq(pts, nv, m_out)
    b.pq([Vector(p) - nv * off for p in pts], -nv, m_in)


def build_tent():
    A = A13("tent", 120, CATP, spacing=8.0)
    b = HB("tent_body")
    HW, HL, H = 1.1, 1.4, 1.45
    A_, B_ = "DealerTeal", "TrainSeatDk"
    panel(b, [(-HW, -HL, 0.02), (-HW, HL, 0.02), (0, HL, H), (0, -HL, H)], (-H, 0, HW), A_, B_)
    panel(b, [(HW, -HL, 0.02), (HW, HL, 0.02), (0, HL, H), (0, -HL, H)], (H, 0, HW), A_, B_)
    panel(b, [(-HW, -HL, 0.02), (HW, -HL, 0.02), (0, -HL, H)], (0, -1, 0), "DealerNavy", B_)
    # front gable with a triangular doorway
    panel(b, [(-HW, HL, 0.02), (-0.5, HL, 0.02), (0, HL, 0.95), (0, HL, H)], (0, 1, 0), A_, B_)
    panel(b, [(HW, HL, 0.02), (0.5, HL, 0.02), (0, HL, 0.95), (0, HL, H)], (0, 1, 0), A_, B_)
    for sx in (-1, 1):                                                       # rolled-back door flaps (coral)
        panel(b, [(sx * 0.5, HL, 0.02), (sx * 0.52, HL + 0.32, 0.02), (sx * 0.1, HL + 0.04, 0.8)], (sx * 0.4, 1, 0.2), "AwningCoral", B_)
    b.zq(0.015, -HW, HW, -HL, HL, 1, "TargetTan")                              # groundsheet
    b.zq(0.017, -HW + 0.15, HW - 0.15, -HL + 0.2, HL - 0.1, 1, "TrainFloor")
    # poles, ridge and guy ropes
    for sx in (-1, 1):
        b.beam((sx * (HW + 0.02), HL + 0.04, 0.0), (0, HL + 0.04, H + 0.06), 0.02, 0.02, 4, "Metal", caps=False)
    b.beam((0, -HL - 0.12, H + 0.02), (0, HL + 0.12, H + 0.02), 0.022, 0.022, 4, "Metal", caps=True)
    ropes = [((0, HL + 0.12, H + 0.02), (0, HL + 1.3, 0.0)), ((0, -HL - 0.12, H + 0.02), (0, -HL - 1.3, 0.0)),
             ((-HW, 0.7, 0.1), (-HW - 0.8, 0.9, 0.0)), ((HW, 0.7, 0.1), (HW + 0.8, 0.9, 0.0)), ((-HW, -0.7, 0.1), (-HW - 0.8, -0.9, 0.0)), ((HW, -0.7, 0.1), (HW + 0.8, -0.9, 0.0))]
    for (p0, p1) in ropes:
        b.beam(p0, p1, 0.008, 0.008, 3, "RopeTan", caps=False)
        b.cyl((p1[0], p1[1], 0.05), 0.025, 0.1, 4, "MetalDark", caps="t")
    A.mesh(b, "Body", uv=None)
    A.mark("Entrance", (0, HL + 1.0, 0.0), size=0.3)
    return A


def build_picnic_table():
    A = A13("picnic_table", 121, CATP, spacing=8.0)
    b = HB("picnic_table_body")
    L = 1.9
    for (y0, y1) in ((-0.36, -0.13), (-0.11, 0.11), (0.13, 0.36)):                  # table top planks
        b.abox(-L / 2, L / 2, y0, y1, 0.70, 0.75, "WoodLight")
    for sy in (-1, 1):
        b.abox(-L / 2 + 0.02, L / 2 - 0.02, sy * 0.52, sy * 0.78, 0.41, 0.46, "WoodLight")   # bench planks
    for sx in (-0.7, 0.7):                                                           # A frames
        for sy in (-1, 1):
            b.rbeam((sx, sy * 0.82, 0.0), (sx, sy * 0.22, 0.72), 0.075, 0.05, "WoodDark", up=(1, 0, 0))
        b.abox(sx - 0.04, sx + 0.04, -0.68, 0.68, 0.36, 0.41, "WoodDark", "+z")         # bench support beam
        b.abox(sx - 0.04, sx + 0.04, -0.3, 0.3, 0.64, 0.70, "WoodDark", "+z")           # table support
    A.mesh(b, "Body", uv=None)
    A.mark("SeatPoint_1", (-0.5, 0.65, 0.46), rot=(0, 0, 180), size=0.15)
    A.mark("SeatPoint_2", (0.5, 0.65, 0.46), rot=(0, 0, 180), size=0.15)
    A.mark("SeatPoint_3", (-0.5, -0.65, 0.46), size=0.15)
    A.mark("SeatPoint_4", (0.5, -0.65, 0.46), size=0.15)
    return A


def build_trash_can_park():
    A = A13("trash_can_park", 122, CATP, spacing=8.0)
    b = HB("trash_can_park_body")
    r, h = 0.29, 0.86
    b.cyl((0, 0, 0.04), 0.33, 0.08, 8, "ConcreteDk", caps="t", rot=0.39)                  # base
    nsl = 8
    for i in range(nsl):                                                                   # slats
        a0, a1 = 2 * math.pi * i / nsl + 0.39, 2 * math.pi * (i + 1) / nsl + 0.39
        m = "WoodLight" if i % 2 == 0 else "WoodDark"
        b.pq([(r * math.cos(a0), r * math.sin(a0), 0.08), (r * math.cos(a1), r * math.sin(a1), 0.08), (r * math.cos(a1), r * math.sin(a1), h), (r * math.cos(a0), r * math.sin(a0), h)],
             (math.cos((a0 + a1) / 2), math.sin((a0 + a1) / 2), 0), m)
        b.pq([(r * 0.9 * math.cos(a0), r * 0.9 * math.sin(a0), 0.1), (r * 0.9 * math.cos(a1), r * 0.9 * math.sin(a1), 0.1), (r * 0.9 * math.cos(a1), r * 0.9 * math.sin(a1), h), (r * 0.9 * math.cos(a0), r * 0.9 * math.sin(a0), h)],
             (-math.cos((a0 + a1) / 2), -math.sin((a0 + a1) / 2), 0), "Trim")                # dark inner liner
    for z in (0.22, 0.62):
        b.cyl((0, 0, z), r + 0.012, 0.05, 8, "MetalDark", caps="", rot=0.39)                  # steel bands
    b.annulus((0, 0, h), r * 0.9, r + 0.04, 8, 1, "MetalDark", rot=0.39)                        # top rim
    b.ball((0.02, 0.0, h - 0.08), 0.2, 6, 3, "TargetBlack", sc=(1, 1, 0.6))                      # bag mound
    b.cyl((0, 0, h + 0.03), r + 0.04, 0.06, 8, "MetalDark", caps="", rot=0.39)
    A.mesh(b, "Body", uv=None)
    A.mark("UsePoint", (0, 0.8, 0.0), size=0.15)
    return A


def build_swing_set():
    A = A13("swing_set", 123, CATP, spacing=8.0)
    b = HB("swing_set_body")
    HX, TZ = 1.65, 2.2
    b.beam((-HX - 0.1, 0, TZ), (HX + 0.1, 0, TZ), 0.05, 0.05, 8, "PlateBlue", caps=True)       # top bar
    for sx in (-HX, HX):
        for sy in (-1, 1):
            b.beam((sx, sy * 1.0, 0.0), (sx, sy * 0.04, TZ + 0.02), 0.045, 0.045, 6, "PlateRed", caps=False)
            b.cyl((sx, sy * 1.0, 0.025), 0.1, 0.05, 6, "ConcreteDk", caps="t")                  # foot plates
        b.beam((sx, -0.55, 0.9), (sx, 0.55, 0.9), 0.025, 0.025, 4, "PlateRed", caps=False)       # cross tie
    b.beam((-HX, -0.62, 0.3), (HX, -0.62, 0.3), 0.022, 0.022, 4, "MetalDark", caps=False)       # ground stretcher
    b.beam((-HX, 0.62, 0.3), (HX, 0.62, 0.3), 0.022, 0.022, 4, "MetalDark", caps=False)
    A.mesh(b, "Body", uv=None)
    for i, x in enumerate((-0.6, 0.6)):
        s = HB("swing_set_swing%d" % (i + 1))
        for cx in (-0.22, 0.22):
            s.beam((cx, 0, -0.03), (cx, 0, -1.62), 0.012, 0.012, 4, "MetalLt", caps=False)       # chains
            s.cyl((cx, 0, -0.03), 0.035, 0.06, 6, "Metal", axis="X", caps="")
        s.abox(-0.27, 0.27, -0.1, 0.1, -1.7, -1.64, "TargetBlack")                               # rubber seat
        s.abox(-0.27, 0.27, -0.1, -0.075, -1.64, -1.6, "ConeOrange")
        s.abox(-0.27, 0.27, 0.075, 0.1, -1.64, -1.6, "ConeOrange")
        A.mesh(s, "Swing_%d" % (i + 1), loc=(x, 0, TZ), uv=None)
        A.mark("SeatPoint_%d" % (i + 1), (x, 0.0, TZ - 1.5), size=0.12)
    return A


def build_slide():
    A = A13("slide", 124, CATP, spacing=8.0)
    b = HB("slide_body")
    PZ = 1.3
    b.abox(-0.45, 0.45, -0.45, 0.45, PZ - 0.05, PZ, "WoodLight")                              # platform deck
    for sx in (-0.42, 0.42):
        for sy in (-0.42, 0.42):
            b.abox(sx - 0.035, sx + 0.035, sy - 0.035, sy + 0.035, 0.0, PZ + 0.85, "PlateRed", "-z")
    for sx in (-0.42, 0.42):                                                                    # side rails + back rail
        b.abox(sx - 0.02, sx + 0.02, -0.42, 0.42, PZ + 0.8, PZ + 0.84, "PlateRed")
        b.abox(sx - 0.015, sx + 0.015, -0.42, 0.42, PZ + 0.3, PZ + 0.33, "PlateRed")
    b.abox(-0.42, 0.42, -0.44, -0.40, PZ + 0.8, PZ + 0.84, "PlateRed")
    b.abox(-0.42, 0.42, -0.425, -0.405, PZ + 0.3, PZ + 0.33, "PlateRed")
    # ladder on the back (-Y)
    for sx in (-0.3, 0.3):
        b.rbeam((sx, -1.15, 0.0), (sx, -0.5, PZ - 0.02), 0.06, 0.04, "PlateRed", up=(1, 0, 0))
    for k in range(1, 6):
        t = k / 6.0
        y = -1.15 + 0.65 * t
        z = 0.0 + (PZ - 0.02) * t
        b.abox(-0.3, 0.3, y - 0.025, y + 0.025, z - 0.015, z + 0.015, "MetalLt")
    # chute: steel bed + coloured side walls
    prof = [(0.45, PZ - 0.04), (2.45, 0.40), (2.95, 0.32), (2.95, 0.28), (2.45, 0.36), (0.45, PZ - 0.08)]
    b.ex(prof, -0.26, 0.26, "Chrome")
    wall = [(0.45, PZ - 0.08), (0.45, PZ + 0.13), (2.45, 0.53), (2.95, 0.45), (2.95, 0.28), (2.45, 0.36)]
    for sx in (-0.30, 0.26):
        b.ex(wall, sx, sx + 0.04, "PlateBlue")
    for sx in (-0.2, 0.2):                                                                      # chute support legs
        b.rbeam((sx, 2.3, 0.0), (sx, 1.6, 0.67), 0.05, 0.04, "PlateRed", up=(1, 0, 0))
    A.mesh(b, "Body", uv=None)
    A.mark("LadderPoint", (0, -1.4, 0.0), size=0.15)
    A.mark("SlideStart", (0, 0.5, PZ + 0.05), size=0.15)
    A.mark("SlideEnd", (0, 2.9, 0.3), size=0.15)
    return A


def canopy(b, x0, x1, yb, yf, zb, zf, stripes, ma, mb, val=0.17):
    n = stripes
    w = (x1 - x0) / n
    drop, run = zb - zf, yf - yb
    for i in range(n):
        m = ma if i % 2 == 0 else mb
        xa, xc = x0 + i * w, x0 + (i + 1) * w
        b.pq([(xa, yb, zb), (xc, yb, zb), (xc, yf, zf), (xa, yf, zf)], (0, drop, run), m)
        b.pq([(xa, yf, zf), (xc, yf, zf), ((xa + xc) / 2, yf, zf - val)], (0, 1, 0), m)
    b.pq([(x0, yb, zb - 0.025), (x1, yb, zb - 0.025), (x1, yf, zf - 0.025), (x0, yf, zf - 0.025)], (0, -drop, -run), "AwningWhite")      # one underside
    for sx, sg in ((x0, -1), (x1, 1)):
        b.pq([(sx, yb, zb), (sx, yf, zf), (sx, yb, zb - 0.1)], (sg, 0, 0), ma)


def vendor_cart(A, kind):
    b = HB(A.id + "_body")
    if kind == "ice":
        body, trim, ca, cb, top = "DealerTeal", "AwningWhite", "AwningCoral", "AwningWhite", "ice"
    else:
        body, trim, ca, cb, top = "PlateRed", "AwningWhite", "Hazard", "AwningWhite", "dog"
    # counter box (x +-0.75, y -0.4..0.4, z 0.3..0.95)
    b.abox(-0.75, 0.75, -0.40, 0.40, 0.30, 0.92, body, "-z")
    b.abox(-0.78, 0.78, -0.43, 0.43, 0.92, 0.98, "MetalLt")                                    # counter top
    b.abox(-0.74, 0.74, -0.405, 0.405, 0.3, 0.38, "MetalDark")                                 # skirt
    b.yq(0.402, -0.62, 0.62, 0.45, 0.84, 1, trim)                                              # front panel inset
    b.yq(0.404, -0.58, -0.05, 0.50, 0.80, 1, body)
    b.yq(0.404, 0.05, 0.58, 0.50, 0.80, 1, body)
    for i in range(3):                                                                         # menu chips
        z = 0.78 - i * 0.08
        b.yq(0.406, -0.5, -0.12, z - 0.025, z + 0.025, 1, "TargetBlack")
        b.yq(0.406, 0.1, 0.48, z - 0.025, z + 0.025, 1, "NeonAmber" if i != 1 else "NeonGreen")
    if kind == "ice":
        b.tbox((-0.5, 0.5, -0.3, 0.3, 0.98), (-0.44, 0.44, -0.25, 0.1, 1.2), "Glass", "-z")       # sloped glass freezer lid
        b.abox(-0.5, 0.5, -0.31, -0.29, 0.98, 1.12, "MetalLt")
        for sx in (-0.2, 0.2):
            b.cyl((sx, 0.15, 1.04), 0.075, 0.12, 6, "TargetTan", r_top=0.03, caps="b")         # cone stack
    else:
        b.tbox((-0.55, 0.55, -0.3, 0.2, 0.98), (-0.5, 0.5, -0.25, 0.12, 1.16), "MetalLt", "-z")   # steamer hood
        b.abox(-0.35, 0.35, 0.2, 0.33, 0.98, 1.06, "MetalDark")                                 # roller grill
        b.cyl((0.5, -0.2, 1.3), 0.06, 0.28, 6, "Metal", caps="t")                               # chimney
        b.yq(0.205, -0.4, 0.4, 1.0, 1.1, 1, "Glass")
        for sx in (-0.2, 0.0, 0.2):
            b.beam((sx - 0.08, 0.27, 1.05), (sx + 0.08, 0.27, 1.05), 0.022, 0.022, 5, "TargetRed", caps=True)
    # wheels (axle along x at the back), front stand, handle
    for sx in (-1, 1):
        b.lathe([(0.06, 0.0), (0.06, 0.30), (-0.02, 0.30), (-0.06, 0.26), (-0.06, 0.0)], (sx * 0.84, -0.12, 0.31), 8, "Tire", axis="X", flip=sx, mats=["MetalLt", "Tire", "Tire", "MetalDark"])
        b.beam((sx * 0.5, -0.4, 0.9), (sx * 0.5, -1.0, 1.0), 0.022, 0.022, 4, "MetalLt", caps=True)   # handle bars
        b.abox(sx * 0.5 - 0.03, sx * 0.5 + 0.03, 0.3, 0.38, 0.0, 0.3, "MetalDark", "-z")           # front stand leg
    b.beam((-0.5, -1.0, 1.0), (0.5, -1.0, 1.0), 0.022, 0.022, 4, "MetalLt", caps=True)
    b.beam((-0.84, -0.12, 0.31), (0.84, -0.12, 0.31), 0.03, 0.03, 4, "MetalDark", caps=False)
    # canopy poles + awning
    for sx in (-0.88, 0.88):
        b.beam((sx, -0.34, 0.98), (sx, -0.34, 2.18), 0.025, 0.025, 5, "MetalLt", caps=True)
        b.beam((sx, 0.38, 0.98), (sx, 0.38, 1.9), 0.02, 0.02, 5, "MetalLt", caps=True)
    canopy(b, -1.0, 1.0, -0.5, 0.62, 2.2, 1.9, 8, ca, cb)
    b.abox(-1.02, 1.02, -0.52, -0.48, 2.1, 2.2, "MetalDark", "+y -y")
    # roof sign
    if top == "ice":
        b.cyl((0, -0.1, 2.58), 0.0001, 0.34, 6, "TargetTan", r_top=0.13, caps="t")             # cone pointing down
        b.ball((0, -0.1, 2.82), 0.15, 6, 3, "AwningCoral")
        b.ball((0, -0.1, 3.0), 0.12, 6, 3, "AwningWhite")
        b.ball((0, -0.1, 3.14), 0.04, 5, 2, "TargetRed")
        b.cyl((0, -0.1, 2.3), 0.02, 0.3, 4, "MetalLt", caps="")
    else:
        b.cyl((0, -0.1, 2.3), 0.02, 0.3, 4, "MetalLt", caps="")
        b.ball((0, -0.1, 2.63), 0.2, 8, 4, "TargetTan", sc=(2.4, 0.9, 0.75))                  # bun
        b.ball((0, -0.1, 2.68), 0.19, 8, 4, "TargetRed", sc=(2.5, 0.55, 0.5))                 # sausage
        for k in range(7):
            x = -0.36 + k * 0.12
            b.pq([(x, 0.09, 2.7 + (0.02 if k % 2 else -0.01)), (x + 0.07, 0.09, 2.7 + (-0.01 if k % 2 else 0.02)), (x + 0.07, 0.09, 2.74), (x, 0.09, 2.74)], (0, 1, 0), "Hazard")
    A.mesh(b, "Body", uv=None)


def build_ice_cream_cart():
    A = A13("ice_cream_cart", 125, CATP, spacing=8.0)
    vendor_cart(A, "ice")
    A.mark("ServePoint", (0, 1.1, 0.0), size=0.2)
    A.mark("VendorPoint", (0, -0.9, 0.0), size=0.2)
    return A


def build_hotdog_stand():
    A = A13("hotdog_stand", 126, CATP, spacing=8.0)
    vendor_cart(A, "dog")
    A.mark("ServePoint", (0, 1.1, 0.0), size=0.2)
    A.mark("VendorPoint", (0, -0.9, 0.0), size=0.2)
    return A


A1 = build_tent();            A1.report(250)
A2 = build_picnic_table();    A2.report(250)
A3 = build_trash_can_park();  A3.report(200)
A4 = build_swing_set();       A4.report(350)
A5 = build_slide();           A5.report(350)
A6 = build_ice_cream_cart();  A6.report(450)
A7 = build_hotdog_stand();    A7.report(450)
