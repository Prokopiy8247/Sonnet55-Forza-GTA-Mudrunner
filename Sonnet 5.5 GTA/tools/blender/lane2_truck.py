"""lane2_truck.py - builds vehicles/truck (lane 2, index 3). 8.00 x 2.50 x 3.60, WB 4.60 (rear tandem), wheel r 0.50. Idempotent, no export.
Cab-over box truck: flat-face cab (Paint) + white cargo box (fixed LiveryWhite so it stays white when Godot repaints) with Paint belt stripe, roof deflector, exhaust stack, big mirrors.
6 wheels: Wheel_FL/FR (front), Wheel_ML/MR + Wheel_RL/RR (tandem). DoorL/DoorR hinged at the front edge. Seats: driver, passenger."""


def l2_build_truck():
    A = L2Asset("truck", 3, paint="#3a5ea8", paint2="#e6e2d6")
    R = 0.50
    FA = 2.30
    ML, RL = -1.70, -2.90
    BZ0 = 1.10                       # box floor / cab bottom
    HW_B, HW_C = 1.25, 1.20
    BELT, ROOF = 1.85, 3.05
    FL = 1.20                        # cab floor top
    b = MB("body")

    # ================================================================ CARGO BOX
    l2_tube(b, [dict(y=-4.00, hw=HW_B - 0.04, zb=BZ0 + 0.04, zt=3.46, c=0.05, cb=0.09), dict(y=-3.93, hw=HW_B, zb=BZ0, zt=3.52, c=0.05, cb=0.11),
                dict(y=1.45, hw=HW_B, zb=BZ0, zt=3.52, c=0.05, cb=0.11), dict(y=1.52, hw=HW_B - 0.03, zb=BZ0 + 0.02, zt=3.48, c=0.05, cb=0.10)],
            side="LiveryWhite", top="LiveryWhite", bot="Trim", cap0="LiveryWhite", cap1="LiveryWhite")
    for s in (-1, 1):
        x = s * (HW_B + 0.004)
        # belt stripe in cab colour + thin pin stripe
        l2_flat_slab(b, l2_rect(-3.92, 1.44, 1.42, 1.98), HW_B, s, 0.012, 0.0, "Paint")
        l2_flat_slab(b, l2_rect(-3.92, 1.44, 2.06, 2.12), HW_B, s, 0.012, 0.0, "Paint")
        # vertical ribs + top / bottom rails
        for y in (-3.30, -2.20, -1.10, 0.0, 1.0):
            l2_seam_v(b, x, y, BZ0 + 0.08, 3.46, w=0.035, d=0.014)
        l2_seam_h(b, x, -3.93, 1.45, 3.45, mat="MetalDark", h=0.06, d=0.02)
        l2_seam_h(b, x, -3.93, 1.45, BZ0 + 0.07, mat="MetalDark", h=0.07, d=0.02)
        # marker lights along the top rail
        for y in (-3.2, 0.9):
            b.box((x + s * 0.004, y, 3.30), (0.014, 0.22, 0.06), "LightAmber")
        # corner posts
        b.box((s * (HW_B + 0.004), -3.94, 2.30), (0.04, 0.05, 2.34), "Metal")
        b.box((s * (HW_B + 0.004), 1.46, 2.30), (0.04, 0.05, 2.34), "Metal")
        # tail light clusters + reverse light
        b.box((s * 1.10, -4.015, 1.46), (0.16, 0.05, 0.50), "Trim")
        b.box((s * 1.10, -4.04, 1.58), (0.12, 0.03, 0.18), "LightTail")
        b.box((s * 1.10, -4.04, 1.34), (0.12, 0.03, 0.12), "LightAmber")
        b.box((s * 1.10, -4.04, 1.20), (0.12, 0.03, 0.08), "LightHead")
    # rear roll-up door: frame + ribs + lock bar
    b.box((0, -3.95, 2.30), (2.24, 0.02, 2.10), "Trim")
    for z in (1.60, 2.00, 2.40, 2.80):
        b.box((0, -3.962, z), (2.18, 0.02, 0.025), "MetalDark")
    b.box((0, -3.975, 1.30), (2.0, 0.03, 0.07), "Metal")
    b.box((0.7, -3.99, 1.22), (0.04, 0.04, 0.22), "Chrome")
    # rear bumper (ICC bar) + plate + mud flaps
    l2_cbox(b, -4.05, -3.90, 1.18, 0.60, 0.92, c=0.05, side="Trim", top="Trim", bot="Trim", cap0="Trim", cap1="Trim")
    b.box((0, -4.056, 0.93), (0.60, 0.012, 0.22), "Plate")
    for s in (-1, 1):
        b.box((s * 0.98, -3.45, 0.50), (0.60, 0.02, 0.46), "Trim")
    # under-box: chassis rails, cross members, tank, battery box, axle beams, springs
    for s in (-1, 1):
        b.box((s * 0.46, -0.25, 0.78), (0.16, 7.60, 0.26), "MetalDark")
    for y in (-3.5, -2.3, -0.8, 1.0, 3.2):
        b.box((0, y, 0.82), (1.0, 0.12, 0.14), "MetalDark")
    b.cyl((-0.92, 0.20, 0.76), 0.30, 1.50, 10, "Metal", axis="Y")
    b.box((1.00, 0.30, 0.76), (0.46, 0.90, 0.40), "Trim")
    for yw in (FA, ML, RL):
        b.cyl((0, yw, R), 0.085, 2.10, 6, "MetalDark", axis="X")
    for s in (-1, 1):
        b.box((s * 0.98, (ML + RL) / 2, 0.74), (0.12, 2.00, 0.07), "MetalDark")     # tandem leaf-spring pack

    # ================================================================ CAB (cab-over, flat face)
    for s in (-1, 1):
        l2_flat_slab(b, [(1.78, BZ0), (3.50, BZ0), (3.50, BELT), (1.78, BELT)], HW_C - 0.08, s, 0.08, 0.0, "Paint")
    l2_box(b, -HW_C + 0.08, HW_C - 0.08, 1.78, 3.50, BZ0, FL, "Interior")
    l2_box(b, -HW_C, HW_C, 1.70, 1.78, BZ0, ROOF, "Paint")                           # cab back wall
    l2_tube(b, [dict(y=3.50, hw=HW_C, zb=0.95, zt=BELT, c=0.07, cb=0.07), dict(y=3.90, hw=HW_C, zb=0.88, zt=BELT, c=0.07, cb=0.07),
                dict(y=3.96, hw=HW_C - 0.05, zb=0.92, zt=BELT - 0.03, c=0.06, cb=0.06)],
            side="Paint", top="Paint", bot="Trim", cap0="Interior", cap1="Paint")
    # greenhouse
    A_, B_, C_, D_ = (3.92, BELT), (3.80, ROOF), (1.78, ROOF), (1.78, BELT)
    GW = 1.165
    l2_shell_yz(b, [A_, B_, C_, D_], GW, ["Glass", "Paint", "Paint", "Interior"], "Glass")
    b.block((0, 2.80), ROOF - 0.005, ROOF + 0.05, (2 * GW + 0.07, 2.10), (2 * GW + 0.02, 2.0), "Paint")
    b.block((0, 3.90), ROOF - 0.04, ROOF + 0.06, (2 * GW + 0.07, 0.22), (2 * GW + 0.03, 0.24), "Paint2", top_shift=(0, 0.02))      # sun visor
    l2_wipers(b, A_, B_, 0.08, spans=((-0.85, -0.2), (0.1, 0.75)))
    for s in (-1, 1):
        l2_frame_slab(b, [A_, B_, C_, D_], GW, s, 0.07, 0.016, 0.002, "Trim")
        l2_flat_slab(b, [(2.00, BELT), (2.10, BELT), (2.10, ROOF), (2.00, ROOF)], GW, s, 0.018, 0.002, "Trim")       # door/quarter pillar
    b.beam((-GW, 3.92, BELT + 0.01), (GW, 3.92, BELT + 0.01), 0.025, 0.025, 4, "Trim")
    b.beam((-GW, 3.80, ROOF - 0.02), (GW, 3.80, ROOF - 0.02), 0.025, 0.025, 4, "Trim")
    b.beam((0, 3.92, BELT + 0.02), (0, 3.80, ROOF - 0.02), 0.02, 0.02, 4, "Trim")                                             # centre post
    # roof deflector (wedge) + roof marker lights
    l2_shell_yz(b, [(1.80, ROOF + 0.04), (1.80, 3.44), (2.70, ROOF + 0.04)], 1.08, ["Paint2", "Paint2", "Trim"], "Paint2")
    for x in (-0.8, -0.4, 0.0, 0.4, 0.8):
        b.box((x, 3.95, ROOF + 0.02), (0.16, 0.05, 0.07), "LightAmber")
    # interior
    b.block((0, 3.62), FL, 1.84, (2.20, 0.34), (2.20, 0.18), "Interior", top_shift=(0.05, 0))
    b.box((0, 3.50, 1.88), (2.18, 0.10, 0.05), "Trim")
    b.box((0, 3.10, 1.36), (0.34, 0.80, 0.36), "Interior")
    l2_steering_wheel(b, (-0.45, 3.18, 2.00), 58, 0.23, "Trim", "Interior")
    for sx in (-0.45, 0.45):
        l2_seat(b, sx, 2.50, FL, 0.56, 0.56, 0.78, 0.24, "Interior")
    b.box((0, 1.82, 2.10), (2.2, 0.04, 1.0), "Interior")
    # front face: grille, lamps, bumper
    b.box((0, 3.965, 1.45), (1.24, 0.03, 0.62), "Trim")
    for k in range(5):
        b.box((0, 3.985, 1.22 + k * 0.12), (1.16, 0.02, 0.03), "Chrome")
    b.box((0, 3.985, 1.62), (0.40, 0.02, 0.08), "Paint2")
    for s in (-1, 1):
        b.box((s * 0.88, 3.95, 1.52), (0.46, 0.06, 0.30), "Trim")
        b.box((s * 0.88, 3.985, 1.52), (0.38, 0.03, 0.22), "LightHead")
        b.box((s * 0.88, 3.96, 1.24), (0.30, 0.05, 0.12), "LightAmber")
        b.box((s * 0.55, 4.0, 0.80), (0.18, 0.04, 0.12), "LightHead")
    b.prism([(-1.20, 3.80), (1.20, 3.80), (1.24, 3.90), (1.18, 3.99), (-1.18, 3.99), (-1.24, 3.90)], 0.50, 0.95, "Trim")
    b.box((0, 3.995, 0.72), (1.60, 0.02, 0.04), "Chrome")
    b.box((0, 4.0, 0.62), (0.58, 0.012, 0.20), "Plate")
    # cab steps, grab handles, air intake, exhaust stack
    for s in (-1, 1):
        b.box((s * 1.14, 3.12, 0.84), (0.26, 0.50, 0.05), "MetalDark")
        b.box((s * 1.14, 3.12, 0.55), (0.26, 0.50, 0.05), "MetalDark")
        b.beam((s * 1.0, 1.98, 1.20), (s * 1.0, 1.98, 2.7), 0.02, 0.02, 4, "Chrome")
    b.beam((1.08, 1.64, 1.00), (1.08, 1.64, 3.46), 0.065, 0.065, 8, "Chrome")
    b.cyl((1.08, 1.64, 3.53), 0.08, 0.12, 8, "Trim", axis="Z")
    b.box((1.08, 1.60, 1.60), (0.04, 0.16, 0.8), "MetalDark")
    b.beam((-1.08, 1.64, 2.0), (-1.08, 1.64, 3.30), 0.05, 0.05, 6, "MetalDark")         # air intake pipe

    # ================================================================ fenders over wheels
    for yw, xs, ww in ((FA, 1.05, 0.34), (ML, 0.98, 0.42), (RL, 0.98, 0.42)):
        for s in (-1, 1):
            xa, xb = sorted((s * (xs - ww / 2 - 0.02), s * (xs + ww / 2 + 0.04)))
            l2_arc_fender(b, yw, R, xa, xb, 0.545, 0.575, math.radians(-60), math.radians(60), 4, "Paint2" if yw == FA else "Trim")

    body = A.mesh(b, "Body")
    l2_island_report(body)

    # ================================================================ doors
    YH = 3.38
    Z0 = BZ0 + 0.02
    for s, nm in ((-1, "DoorL"), (1, "DoorR")):
        dm = MB("door")
        l2_flat_slab(dm, l2_rect(2.14, YH, Z0, BELT - 0.005, 0.04), HW_C, s, 0.04, -0.02, "Paint")
        l2_flat_slab(dm, [(2.2, 1.40), (YH - 0.04, 1.40), (YH - 0.04, 1.58), (2.2, 1.58)], HW_C, s, 0.012, 0.02, "Paint2")
        l2_frame_slab(dm, [(2.12, BELT + 0.01), (YH + 0.0, BELT + 0.01), (YH - 0.04, ROOF - 0.04), (2.12, ROOF - 0.04)], GW, s, 0.06, 0.018, 0.004, "Trim")
        dm.box((s * (HW_C + 0.04), 2.28, 1.62), (0.04, 0.22, 0.04), "Chrome")
        l2_mirror(dm, s, 1.13, 3.78, 2.88, size=(0.17, 0.42))
        dm.translate((-s * HW_C, -YH, -Z0))
        A.mesh(dm, nm, loc=(s * HW_C, YH, Z0))

    # ================================================================ wheels
    for nm, sx, y, xs, ww in (("FL", -1, FA, 1.05, 0.32), ("FR", 1, FA, 1.05, 0.32), ("ML", -1, ML, 0.98, 0.40), ("MR", 1, ML, 0.98, 0.40),
                              ("RL", -1, RL, 0.98, 0.40), ("RR", 1, RL, 0.98, 0.40)):
        o = l2_wheel(A.prefix + "Wheel_" + nm, R, ww, sx, A.coll, seg=12, style="truck", loc=(sx * xs, y, R))
        parent_to(o, A.root)
        A.objs["Wheel_" + nm] = o

    # ================================================================ anchors
    SZ = FL + 0.37
    A.node("HeadlightL", (-0.88, 3.99, 1.52))
    A.node("HeadlightR", (0.88, 3.99, 1.52))
    A.node("TaillightL", (-1.10, -4.04, 1.58))
    A.node("TaillightR", (1.10, -4.04, 1.58))
    A.node("SeatDriver", (-0.45, 2.50, SZ))
    A.node("SeatPassenger", (0.45, 2.50, SZ))
    A.node("ExitL", (-2.15, 2.75, 0.0), display="ARROWS", size=0.2)
    A.node("ExitR", (2.15, 2.75, 0.0), display="ARROWS", size=0.2)
    A.node("Exhaust", (1.08, 1.64, 3.59))
    A.mats()
    bpy.context.view_layer.update()
    return A


l2_A = l2_build_truck()
l2_info = stats(l2_A.root)
print("tris:", l2_tris(l2_A.root))
