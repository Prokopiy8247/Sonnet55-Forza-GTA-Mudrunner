"""lane13 train_car - Halcyon light-rail passenger car 16 x 2.8 x 3.6 m. Run after gta_lib + lane13_lib + lane13_traincommon (see build_all)."""


def build_train_car():
    A = A13("train_car", 0, "GTA_GODOT/Vehicles", spacing=40.0, paint="#ece8dc", paint2="#2f9c95")
    b = HB("train_car_body")
    YB = 7.8
    wins = [win(-7.5, -6.35), win(-3.0, -1.3), win(-0.85, 0.85), win(1.3, 3.0), win(6.35, 7.5)]
    doors = [door(-4.7, -3.3), door(3.3, 4.7)]
    side_walls(b, -YB, YB, wins, doors, pockets=[-1, 1])
    roof_arch(b, -YB, YB)
    end_wall(b, 1, YB)
    end_wall(b, -1, YB)
    floor_and_ceiling(b, -YB, YB)
    # ------------------------------------------------------------- underframe
    b.abox(-1.2, 1.2, -YB, YB, ZF0 - 0.02, ZF0, "Trim", "+z -z")                   # frame edge
    for s in (-1, 1):
        b.abox(s * 1.18, s * 1.22, -3.6, 3.6, 0.58, ZF0, "Trim", "+z -z")           # side skirt
        b.abox(s * 0.50, s * 1.12, -3.3, 3.3, 0.50, ZF0, "MetalDark", "+z")        # equipment boxes
        b.abox(s * 0.50, s * 1.12, -3.35, -2.4, 0.46, 0.50, "Metal", "+z")
    b.abox(-0.3, 0.3, -3.5, 3.5, 0.58, ZF0, "Metal", "+z")                          # centre duct
    # ------------------------------------------------------------- seats, poles, rails
    for s in (-1, 1):
        for yc, ln, cm in ((-6.9, 1.2, "TrainCoral"), (-2.15, 1.7, "TrainSeat"), (0.0, 1.7, "TrainSeat"), (2.15, 1.7, "TrainSeat"), (6.9, 1.2, "TrainCoral")):
            bench(b, s, yc, ln, cm)
    for s in (-1, 1):
        for yc, d in ((-4.0, 1), (4.0, -1)):
            pole(b, s * 0.95, yc + d * 0.85)                                         # door grab poles
        b.beam((s * 0.62, -3.0, 2.58), (s * 0.62, 3.0, 2.58), 0.02, 0.02, 5, "Chrome")
        for y in (-3.0, 3.0):
            b.beam((s * 0.62, y, 2.58), (s * 0.62, y, ZW - 0.01), 0.016, 0.016, 4, "Chrome", caps=False)
    # ------------------------------------------------------------- roof gear
    for y in (-2.9, 2.9):
        b.tbox((-0.55, 0.55, y - 1.0, y + 1.0, 3.40), (-0.45, 0.45, y - 0.9, y + 0.9, 3.58), "Metal", "-z")
        b.cyl((0, y - 0.45, 3.585), 0.28, 0.03, 8, "MetalDark", caps="t")
        b.cyl((0, y + 0.45, 3.585), 0.28, 0.03, 8, "MetalDark", caps="t")
    b.abox(-0.12, 0.12, -1.3, 1.3, 3.455, 3.53, "MetalDark", "-z")                  # roof vent trunk
    # ------------------------------------------------------------- marker lights
    lights_ends(b, YB, -YB)
    A.mesh(b, "Body")
    for nm, s, yc, d in (("Door_L1", -1, -4.0, -1), ("Door_L2", -1, 4.0, 1), ("Door_R1", 1, -4.0, -1), ("Door_R2", 1, 4.0, 1)):
        door_leaf(A, nm, s, yc, d)
    add_bogies(A)
    # ------------------------------------------------------------- empties
    seat_ys = (-2.15, 0.0, 2.15)
    for i, y in enumerate(seat_ys):
        A.mark("SeatPoint_%d" % (i + 1), (-0.98, y, 1.68), rot=(0, 0, -90))     # left bench faces +X
    for i, y in enumerate(seat_ys):
        A.mark("SeatPoint_%d" % (i + 4), (0.98, y, 1.68), rot=(0, 0, 90))       # right bench faces -X
    A.mark("ExitL1", (-2.25, -4.0, 0.0), size=0.3)
    A.mark("ExitL2", (-2.25, 4.0, 0.0), size=0.3)
    A.mark("ExitR1", (2.25, -4.0, 0.0), size=0.3)
    A.mark("ExitR2", (2.25, 4.0, 0.0), size=0.3)
    A.mark("CoupleF", (0, 8.0, 0.7))
    A.mark("CoupleR", (0, -8.0, 0.7))
    A.mark("InteriorLight", (0, 0, 2.85))
    A.apply_local_paint()
    return A


A = build_train_car()
rep = A.report(3500)
