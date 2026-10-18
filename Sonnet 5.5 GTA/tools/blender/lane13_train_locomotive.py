"""lane13 train_locomotive - Halcyon light-rail head car 16 x 2.8 x 3.6 m (cab + faceted raked nose + passenger saloon + pantograph).
Run after gta_lib + lane13_lib + lane13_traincommon (via lane13_run.py)."""


def nose_ring(y, hw, zs, zr, zb=ZF0):
    dz = zr - zs
    return [(-hw, y, zb), (hw, y, zb), (hw, y, zs), (hw * 0.917, y, zs + dz * 0.478), (hw * 0.564, y, zs + dz * 0.87), (0, y, zr),
            (-hw * 0.564, y, zs + dz * 0.87), (-hw * 0.917, y, zs + dz * 0.478), (-hw, y, zs)]


def partition(b, y, thick, hole, mat="TrainInner"):
    for r in rects_with_holes(-XO + WT, XO - WT, ZF, ZW, [hole]):
        b.yq(y + thick / 2, r[0], r[1], r[2], r[3], 1, mat)
        b.yq(y - thick / 2, r[0], r[1], r[2], r[3], -1, mat)
    x0, x1, z0, z1 = hole
    b.xq(x0, y - thick / 2, y + thick / 2, z0, z1, 1, mat)
    b.xq(x1, y - thick / 2, y + thick / 2, z0, z1, -1, mat)
    b.zq(z1, x0, x1, y - thick / 2, y + thick / 2, -1, mat)


def pantograph_geometry():
    b = HB("loco_pantograph")
    for sy in (-0.5, 0.5):
        for sx in (-0.4, 0.4):
            b.cyl((sx, sy, 0.07), 0.05, 0.14, 6, "PoleGrey", caps="t")            # insulators
    b.abox(-0.55, 0.55, -0.62, 0.62, 0.14, 0.2, "MetalDark")                       # base frame
    K = (0, 0, 0.50)
    for sy in (-0.5, 0.5):
        b.rbeam((0, sy, 0.2), K, 0.07, 0.05, "Metal", up=(1, 0, 0))                 # lower arms
        b.rbeam(K, (0, sy * 0.28, 0.76), 0.06, 0.045, "Metal", up=(1, 0, 0))        # upper arms
    b.abox(-0.95, 0.95, -0.2, 0.2, 0.76, 0.82, "MetalDark")                         # collector head
    b.abox(-0.92, 0.92, -0.05, 0.05, 0.82, 0.85, "Chrome", "-z")
    return b


def build_train_locomotive():
    A = A13("train_locomotive", 1, "GTA_GODOT/Vehicles", spacing=40.0, paint="#ece8dc", paint2="#2f9c95")
    b = HB("train_locomotive_body")
    YR, YN = 7.8, 5.6
    wins = [win(-7.5, -6.35), win(-5.85, -4.15), win(-3.65, -1.95), win(-1.45, 0.2), win(3.95, 5.35)]
    doors = [door(1.9, 3.3)]
    side_walls(b, -YR, YN, wins, doors, pockets=[-1])
    roof_arch(b, -YR, YN)
    end_wall(b, -1, YR)
    floor_and_ceiling(b, -YR, YN)
    # ------------------------------------------------------------- faceted nose (loft)
    sts = [(5.6, 1.33, 3.00, 3.46), (6.45, 1.20, 2.55, 3.10), (7.15, 1.02, 1.95, 2.40), (7.75, 0.88, 1.55, 1.80), (8.0, 0.80, 1.40, 1.50)]
    rings = [nose_ring(*s) for s in sts]
    for k in range(len(rings) - 1):
        yc = (sts[k][0] + sts[k + 1][0]) / 2
        for i in range(9):
            j = (i + 1) % 9
            if i == 0:
                m = "Trim"
            elif i in (1, 8):
                m = "Paint"
            elif k in (1, 2):
                m = "Glass"                        # raked wrap-around windscreen
            elif i in (3, 6):
                m = "Paint2"                       # roof shoulder stripe continues over the cab
            else:
                m = "Paint"
            b.po([rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]], (0, yc, 1.9), m)
    b.pq(rings[-1], (0, 1, 0), "Paint")                                                   # front face
    # windscreen frames (black A pillars + header) on the shoulders
    for s in (-1, 1):
        b.po([(s * 1.21, 6.43, 2.50), (s * 1.01, 7.13, 1.90), (s * 1.01, 7.13, 1.99), (s * 1.21, 6.43, 2.59)], (0, 6.8, 1.9), "Trim")
    # cab floor, dash and seats
    b.pq([(-1.23, 5.6, ZF), (1.23, 5.6, ZF), (0.78, 7.95, ZF), (-0.78, 7.95, ZF)], (0, 0, 1), "TrainFloor")
    b.pq([(-1.23, 5.6, ZF0), (1.23, 5.6, ZF0), (0.78, 7.95, ZF0), (-0.78, 7.95, ZF0)], (0, 0, -1), "Trim")
    b.tbox((-0.78, 0.78, 6.55, 7.5, ZF), (-0.74, 0.74, 7.05, 7.5, 1.42), "Interior", "-z")
    b.po([(-0.7, 6.72, 1.31), (0.7, 6.72, 1.31), (0.7, 7.02, 1.42), (-0.7, 7.02, 1.42)], (0, 6.8, 1.0), "CabConsole")
    b.abox(-0.07, 0.07, 6.7, 6.8, 1.42, 1.52, "MetalDark")                                  # master controller
    for sx, mm in ((-0.55, "TrainSeatDk"), (0.55, "TrainSeat")):
        b.abox(sx - 0.25, sx + 0.25, 4.65, 5.15, ZF, 1.38, "Trim", "-z")
        b.abox(sx - 0.25, sx + 0.25, 4.65, 5.15, 1.38, 1.48, mm, "-z")
        b.abox(sx - 0.25, sx + 0.25, 4.55, 4.65, 1.48, 2.0, mm, "-z")
    # ------------------------------------------------------------- bulkhead between cab and saloon
    partition(b, 3.62, 0.12, (-0.55, 0.55, 1.0, 2.55))
    # ------------------------------------------------------------- underframe
    b.abox(-1.2, 1.2, -YR, YN, ZF0 - 0.02, ZF0, "Trim", "+z -z")
    for s in (-1, 1):
        b.abox(s * 1.18, s * 1.22, -3.6, 3.6, 0.58, ZF0, "Trim", "+z -z")
        b.abox(s * 0.50, s * 1.12, -3.3, 2.0, 0.48, ZF0, "MetalDark", "+z")
    b.abox(-0.3, 0.3, -3.5, 3.5, 0.58, ZF0, "Metal", "+z")
    # pilot / bumper skirt + front lights
    b.tbox((-0.78, 0.78, 7.15, 8.0, 0.52), (-0.80, 0.80, 7.15, 8.03, ZF0), "Trim", "-z")
    b.yq(8.004, -0.7, 0.7, 1.12, 1.30, 1, "Trim")
    for sx in (-1, 1):
        b.abox(sx * 0.50 - 0.15, sx * 0.50 + 0.15, 8.0, 8.035, 1.14, 1.28, "LightHead", "-y")
        b.abox(sx * 0.72 - 0.05, sx * 0.72 + 0.05, 8.0, 8.025, 1.34, 1.38, "LightAmber", "-y")
    b.abox(-0.12, 0.12, 7.88, 7.97, 1.50, 1.56, "LightHead", "-y")                       # top centre beacon
    b.yq(8.006, -0.78, 0.78, 1.38, 1.42, 1, "Neon")
    # rear marker lights
    for sx in (-1, 1):
        b.abox(sx * 1.0 - 0.11, sx * 1.0 + 0.11, -YR - 0.03, -YR, 1.24, 1.36, "LightTail", "+y")
    # ------------------------------------------------------------- roof gear
    for y in (-5.7, 0.9):
        b.tbox((-0.55, 0.55, y - 1.0, y + 1.0, 3.40), (-0.45, 0.45, y - 0.9, y + 0.9, 3.58), "Metal", "-z")
        b.cyl((0, y - 0.45, 3.585), 0.28, 0.03, 8, "MetalDark", caps="t")
        b.cyl((0, y + 0.45, 3.585), 0.28, 0.03, 8, "MetalDark", caps="t")
    b.tbox((-0.5, 0.5, 4.0, 5.2, 3.43), (-0.42, 0.42, 4.1, 5.1, 3.56), "MetalDark", "-z")       # resistor box behind the cab
    for sx in (-0.2, 0.2):
        b.cyl((sx, 5.45, 3.56), 0.045, 0.34, 6, "Chrome", axis="Y", r_top=0.11)               # air horns
    # ------------------------------------------------------------- saloon seats + poles
    for s in (-1, 1):
        for yc, ln, cm in ((-6.9, 1.2, "TrainCoral"), (-5.0, 1.7, "TrainSeat"), (-2.8, 1.7, "TrainSeat"), (-0.62, 1.65, "TrainSeat")):
            bench(b, s, yc, ln, cm)
        pole(b, s * 0.95, 1.05)
        pole(b, s * 0.95, 3.95)
        b.beam((s * 0.62, -4.5, 2.58), (s * 0.62, 0.0, 2.58), 0.02, 0.02, 5, "Chrome")
    A.mesh(b, "Body")
    door_leaf(A, "DoorL1", -1, 2.6, -1)
    door_leaf(A, "DoorR1", 1, 2.6, -1)
    A.mesh(pantograph_geometry(), "Pantograph", loc=(0, -3.0, 3.46), uv=None)
    add_bogies(A)
    # ------------------------------------------------------------- empties
    A.mark("HeadlightL", (-0.50, 8.06, 1.21))
    A.mark("HeadlightR", (0.50, 8.06, 1.21))
    A.mark("TaillightL", (-1.0, -7.85, 1.30))
    A.mark("TaillightR", (1.0, -7.85, 1.30))
    A.mark("SeatDriver", (-0.55, 4.9, 1.68))
    A.mark("SeatPassenger", (0.55, 4.9, 1.68))
    for i, y in enumerate((-5.0, -2.8, -0.62)):
        A.mark("SeatPoint_%d" % (i + 1), (-0.98, y, 1.68), rot=(0, 0, -90))
        A.mark("SeatPoint_%d" % (i + 4), (0.98, y, 1.68), rot=(0, 0, 90))
    A.mark("ExitL", (-2.25, 2.6, 0.0), size=0.3)
    A.mark("ExitR", (2.25, 2.6, 0.0), size=0.3)
    A.mark("CoupleF", (0, 8.05, 0.7))
    A.mark("CoupleR", (0, -8.0, 0.7))
    A.mark("Horn", (0, 5.5, 3.65))
    A.mark("PantographTip", (0, -3.0, 4.31))
    A.mark("InteriorLight", (0, -2.0, 2.85))
    A.apply_local_paint()
    return A


A = build_train_locomotive()
rep = A.report(4200)
