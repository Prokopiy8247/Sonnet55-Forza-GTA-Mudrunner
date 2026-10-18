"""lane2_firetruck.py - builds vehicles/firetruck (lane 2, index 4). 9.00 x 2.50 x 3.40, WB 5.00 (rear tandem), wheel r 0.50. Idempotent, no export.
Red crew-cab fire engine: equipment body with roller-shutter compartments (decal quads), roof ladder with rungs on posts, hose reel,
pump panel, white (fixed LiveryWhite) stripes + chevron rear (Godot repaints Paint2 dark at runtime), SirenBar (SirenBar_L red / SirenBar_R blue) on the cab roof, 6 wheels.
DoorL/DoorR hinged at the front edge of the front cab doors. Seats: driver, passenger, rear bench (SeatRearL/R)."""


def l2_build_firetruck():
    A = L2Asset("firetruck", 4, paint="#c92a2a", paint2="#f2f0ea")
    R = 0.50
    FA = 2.50
    ML, RL = -1.90, -3.10
    BZ0 = 1.10
    HW = 1.25
    BELT, ROOF = 1.95, 3.00
    FL = 1.20
    BY0, BY1 = -4.50, 0.80           # equipment body
    BZT = 2.70
    b = MB("body")

    # ================================================================ EQUIPMENT BODY
    l2_tube(b, [dict(y=BY0, hw=HW - 0.04, zb=BZ0 + 0.06, zt=BZT - 0.06, c=0.05, cb=0.08), dict(y=BY0 + 0.07, hw=HW, zb=BZ0 + 0.0, zt=BZT, c=0.05, cb=0.09),
                dict(y=BY1 - 0.05, hw=HW, zb=BZ0, zt=BZT, c=0.05, cb=0.09), dict(y=BY1, hw=HW - 0.04, zb=BZ0 + 0.04, zt=BZT - 0.05, c=0.05, cb=0.08)],
            side="Paint", top="Paint", bot="Trim", cap0="Paint", cap1="Paint")
    shutters_r = [(-4.36, -3.30), (-3.20, -2.14), (-2.04, -0.98)]
    shutters_l = [(-4.36, -3.30), (-3.20, -2.14), (-2.04, -0.98), (-0.88, 0.60)]
    for s in (-1, 1):
        x = s * (HW + 0.008)
        # white stripe band + lower diamond-plate rail
        l2_quad_x(b, x, BY0 + 0.1, BY1 - 0.05, 2.22, 2.36, "LiveryWhite")
        l2_quad_x(b, x, BY0 + 0.1, BY1 - 0.05, BZ0 + 0.02, BZ0 + 0.16, "Metal")
        # roller-shutter compartments
        for (y0, y1) in (shutters_r if s > 0 else shutters_l):
            z0, z1 = 1.38, 2.12
            l2_quad_x(b, x, y0, y1, z0, z1, "Metal")
            l2_rect_lines_x(b, x + s * 0.002, y0, y1, z0, z1, "Trim", 0.025)
            for k in range(1, 5):
                zz = z0 + (z1 - z0) * k / 5
                l2_quad_x(b, x + s * 0.002, y0 + 0.02, y1 - 0.02, zz - 0.008, zz + 0.008, "MetalDark")
            l2_quad_x(b, x + s * 0.004, (y0 + y1) / 2 - 0.15, (y0 + y1) / 2 + 0.15, z0 + 0.03, z0 + 0.07, "Chrome")
        # marker lights
        b.box((x, -4.40, 2.55), (0.016, 0.22, 0.06), "LightAmber")
        b.box((x, 0.55, 2.55), (0.016, 0.22, 0.06), "LightAmber")
        # tail lights + amber + reverse
        b.box((s * 1.02, BY0 - 0.02, 1.60), (0.18, 0.05, 0.50), "Trim")
        b.box((s * 1.02, BY0 - 0.045, 1.72), (0.13, 0.03, 0.22), "LightTail")
        b.box((s * 1.02, BY0 - 0.045, 1.44), (0.13, 0.03, 0.12), "LightAmber")
        b.box((s * 0.66, BY0 - 0.045, 1.44), (0.13, 0.03, 0.12), "LightHead")
        # rear strobes (flash with the siren)
        b.box((s * 1.06, BY0 + 0.05, 2.60), (0.22, 0.12, 0.08), "LightRed" if s < 0 else "LightBlue")
        # grab rails along the body top + mount posts
        b.beam((s * 1.12, -4.30, BZT + 0.28), (s * 1.12, 0.40, BZT + 0.28), 0.018, 0.018, 3, "Chrome", caps=False)
        for y in (-4.30, 0.40):
            b.beam((s * 1.12, y, BZT), (s * 1.12, y, BZT + 0.28), 0.018, 0.018, 3, "Chrome", caps=False)
    # top: diamond-plate walkway, ladder on posts, hose reel
    l2_quad_z(b, BZT + 0.004, -1.0, 0.25, BY0 + 0.15, BY1 - 0.1, "Metal")
    LX = -0.35
    for y in (-4.20, -2.20, -0.20):
        b.box((LX, y, (BZT + 3.20) / 2), (0.60, 0.10, 3.20 - BZT), "MetalDark")
    for sx in (-1, 1):
        b.box((LX + sx * 0.30, -1.20, 3.29), (0.07, 6.80, 0.12), "Metal")                       # ladder rails, y -4.6 .. 2.2
    for i in range(15):
        y = -4.42 + i * 0.455
        b.beam((LX - 0.30, y, 3.29), (LX + 0.30, y, 3.29), 0.014, 0.014, 3, "Chrome", caps=False)
    for sx in (-1, 1):
        b.box((LX + sx * 0.30, 1.7, 3.07), (0.12, 0.12, 0.24), "MetalDark")                     # rest on the cab roof
    # hose reel (top right)
    RXc, RYc, RZc, Rr = 0.78, -3.55, BZT + 0.34, 0.34
    b.cyl((RXc, RYc, RZc), 0.13, 0.72, 6, "Metal", axis="X")
    for dx in (-0.36, 0.36):
        b.cyl((RXc + dx, RYc, RZc), Rr, 0.04, 8, "Metal", axis="X")
    b.cyl((RXc, RYc, RZc), Rr * 0.86, 0.66, 8, "Trim", axis="X")
    b.beam((RXc + 0.38, RYc, RZc), (RXc + 0.50, RYc + 0.16, RZc + 0.10), 0.014, 0.014, 4, "Chrome")
    for dx in (-0.30, 0.30):
        b.box((RXc + dx, RYc, BZT + 0.08), (0.06, 0.40, 0.16), "MetalDark")
    # pump panel + intakes (right side, behind the cab)
    PX = HW + 0.012
    l2_quad_x(b, PX, 0.12, 0.74, 1.30, 2.10, "MetalDark")
    l2_rect_lines_x(b, PX + 0.002, 0.12, 0.74, 1.30, 2.10, "Chrome", 0.02)
    for (yy, zz) in ((0.30, 1.90), (0.56, 1.90), (0.30, 1.62), (0.56, 1.62)):
        b.cyl((PX + 0.015, yy, zz), 0.045, 0.03, 8, "Chrome", axis="X")
    for zz in (1.45, 1.85):
        b.cyl((PX, -0.20, zz), 0.07, 0.06, 8, "Chrome", axis="X")
    # rear face: hazard chevrons, plate, step bumper, handrails
    RY = BY0 - 0.01
    for i in range(7):
        x0 = -1.08 + i * 0.31
        l2_poly_y(b, RY, [(x0, 1.00), (x0 + 0.17, 1.00), (x0 + 0.27, 1.34), (x0 + 0.10, 1.34)], "LiveryWhite")
    l2_quad_y(b, RY - 0.012, -0.75, 0.75, 1.85, 2.35, "MetalDark")
    l2_quad_y(b, RY - 0.02, -0.23, 0.23, 1.59, 1.81, "Plate")
    l2_cbox(b, BY0 - 0.12, BY0 + 0.02, 1.22, 0.55, 0.88, c=0.04, side="Trim", top="Metal", bot="Trim", cap0="Trim", cap1="Trim")
    for s in (-1, 1):
        b.beam((s * 0.85, BY0 - 0.04, 1.2), (s * 0.85, BY0 - 0.04, 2.4), 0.02, 0.02, 4, "Chrome")
        b.box((s * 0.98, -4.00, 0.50), (0.60, 0.02, 0.46), "Trim")                                # mud flap

    # ================================================================ chassis
    for s in (-1, 1):
        b.box((s * 0.46, -0.30, 0.78), (0.16, 8.40, 0.26), "MetalDark")
    for y in (-3.8, -0.9, 3.4):
        b.box((0, y, 0.82), (1.0, 0.12, 0.14), "MetalDark")
    for yw in (FA, ML, RL):
        b.box((0, yw, R), (2.10, 0.17, 0.17), "MetalDark")
    b.cyl((-0.92, 0.25, 0.76), 0.30, 1.40, 8, "Metal", axis="Y")
    b.box((0.98, 0.25, 0.76), (0.46, 0.90, 0.40), "Trim")

    # ================================================================ CAB (forward crew cab)
    CY0, CY1 = 1.00, 4.34            # cab back .. front face
    for s in (-1, 1):
        l2_flat_slab(b, [(CY0 + 0.08, BZ0), (3.90, BZ0), (3.90, BELT), (CY0 + 0.08, BELT)], HW - 0.08, s, 0.08, 0.0, "Paint")
        l2_quad_x(b, s * (HW + 0.009), CY0 + 0.1, 3.88, 1.42, 1.56, "LiveryWhite")             # white belt stripe
        # crew door (static seams) + handle
        l2_rect_lines_x(b, s * (HW + 0.010), 1.14, 2.46, 1.14, 1.93, "Trim", 0.018)
        b.box((s * (HW + 0.014), 2.30, 1.62), (0.03, 0.17, 0.03), "Chrome")
    l2_box(b, -HW + 0.08, HW - 0.08, CY0 + 0.08, 3.90, BZ0, FL, "Interior")
    l2_box(b, -HW, HW, CY0, CY0 + 0.08, BZ0, ROOF, "Paint")
    l2_tube(b, [dict(y=3.90, hw=HW, zb=0.95, zt=BELT, c=0.07, cb=0.07), dict(y=4.30, hw=HW, zb=0.88, zt=BELT, c=0.07, cb=0.07),
                dict(y=CY1, hw=HW - 0.05, zb=0.92, zt=BELT - 0.03, c=0.06, cb=0.06)],
            side="Paint", top="Paint", bot="Trim", cap0="Interior", cap1="Paint")
    A_, B_, C_, D_ = (4.28, BELT), (4.17, ROOF), (CY0 + 0.08, ROOF), (CY0 + 0.08, BELT)
    GW = 1.215
    l2_shell_yz(b, [A_, B_, C_, D_], GW, ["Glass", "Paint", "Paint", "Interior"], "Glass")
    b.block((0, 2.70), ROOF - 0.005, ROOF + 0.05, (2 * GW + 0.07, 3.20), (2 * GW + 0.02, 3.10), "Paint")
    b.block((0, 4.27), ROOF - 0.04, ROOF + 0.06, (2 * GW + 0.07, 0.22), (2 * GW + 0.03, 0.24), "Paint2", top_shift=(0, 0.02))
    l2_wipers(b, A_, B_, 0.08, spans=((-0.85, -0.2), (0.1, 0.75)))
    for s in (-1, 1):
        l2_frame_slab(b, [A_, B_, C_, D_], GW, s, 0.07, 0.016, 0.002, "Trim")
        l2_flat_slab(b, [(2.46, BELT), (2.58, BELT), (2.58, ROOF), (2.46, ROOF)], GW, s, 0.018, 0.002, "Paint")      # B pillar
    b.beam((-GW, 4.28, BELT + 0.01), (GW, 4.28, BELT + 0.01), 0.025, 0.025, 4, "Trim")
    b.beam((-GW, 4.17, ROOF - 0.02), (GW, 4.17, ROOF - 0.02), 0.025, 0.025, 4, "Trim")
    b.beam((0, 4.28, BELT + 0.02), (0, 4.17, ROOF - 0.02), 0.02, 0.02, 4, "Trim")
    # interior
    b.block((0, 4.04), FL, 1.84, (2.30, 0.34), (2.30, 0.18), "Interior", top_shift=(0.05, 0))
    b.box((0, 3.92, 1.88), (2.28, 0.10, 0.05), "Trim")
    b.box((0, 3.50, 1.36), (0.34, 0.80, 0.36), "Interior")
    l2_wheel_lite(b, (-0.45, 3.58, 2.00), 58, 0.23, "Trim", "Interior")
    for sx in (-0.45, 0.45):
        l2_seat(b, sx, 2.98, FL, 0.56, 0.56, 0.78, 0.24, "Interior")
    b.box((0, 1.80, FL + 0.20), (1.50, 0.62, 0.24), "Interior")                       # crew bench
    # front face: grille, lamps, chrome bumper, turn signals
    b.box((0, 4.315, 1.45), (1.30, 0.03, 0.62), "Trim")
    for k in range(5):
        l2_quad_y(b, 4.340, -0.61, 0.61, 1.21 + k * 0.12, 1.24 + k * 0.12, "Chrome")
    b.box((0, 4.335, 1.64), (0.44, 0.02, 0.08), "LiveryWhite")
    for s in (-1, 1):
        b.box((s * 0.92, 4.30, 1.54), (0.46, 0.06, 0.30), "Trim")
        b.box((s * 0.92, 4.335, 1.54), (0.38, 0.03, 0.22), "LightHead")
        b.box((s * 0.92, 4.31, 1.26), (0.30, 0.05, 0.12), "LightAmber")
        b.box((s * 0.55, 4.40, 0.82), (0.18, 0.04, 0.12), "LightHead")
    b.prism([(-1.22, 4.12), (1.22, 4.12), (1.25, 4.25), (1.19, 4.40), (-1.19, 4.40), (-1.25, 4.25)], 0.52, 0.96, "Chrome")
    b.box((0, 4.40, 0.74), (1.20, 0.03, 0.20), "Trim")
    b.box((0, 4.41, 0.64), (0.58, 0.012, 0.20), "Plate")
    # cab steps, grab handles, exhaust stack, air horns
    for s in (-1, 1):
        b.box((s * 1.16, 3.40, 0.86), (0.26, 0.60, 0.05), "MetalDark")
        b.box((s * 1.16, 3.40, 0.58), (0.26, 0.60, 0.05), "MetalDark")
        b.beam((s * 1.06, 2.60, 1.20), (s * 1.06, 2.60, 2.7), 0.02, 0.02, 4, "Chrome")
    b.beam((1.14, 0.90, 1.00), (1.14, 0.90, 3.12), 0.06, 0.06, 8, "Chrome")
    b.cyl((1.14, 0.90, 3.17), 0.075, 0.10, 8, "Trim", axis="Z")

    # ================================================================ fenders over wheels
    for yw, xs, ww in ((FA, 1.06, 0.36), (ML, 1.00, 0.44), (RL, 1.00, 0.44)):
        for s in (-1, 1):
            xa, xb = sorted((s * (xs - ww / 2 - 0.02), s * (xs + ww / 2 + 0.02)))
            l2_arc_fender(b, yw, R, xa, xb, 0.545, 0.575, math.radians(-60), math.radians(60), 4, "Paint" if yw == FA else "Trim")

    body = A.mesh(b, "Body")
    l2_island_report(body)

    # ================================================================ doors (front cab doors)
    YH = 3.84
    Z0 = BZ0 + 0.02
    for s, nm in ((-1, "DoorL"), (1, "DoorR")):
        dm = MB("door")
        l2_flat_slab(dm, l2_rect(2.62, YH, Z0, BELT - 0.005, 0.0), HW, s, 0.04, -0.02, "Paint")
        l2_flat_slab(dm, [(2.70, 1.42), (YH - 0.04, 1.42), (YH - 0.04, 1.56), (2.70, 1.56)], HW, s, 0.012, 0.02, "LiveryWhite")
        l2_frame_slab(dm, [(2.60, BELT + 0.01), (YH, BELT + 0.01), (YH - 0.04, ROOF - 0.04), (2.60, ROOF - 0.04)], GW, s, 0.06, 0.018, 0.004, "Trim")
        dm.box((s * (HW + 0.04), 2.78, 1.62), (0.04, 0.22, 0.04), "Chrome")
        l2_mirror(dm, s, 1.13, 4.24, 2.88, size=(0.17, 0.42))
        dm.translate((-s * HW, -YH, -Z0))
        A.mesh(dm, nm, loc=(s * HW, YH, Z0))

    # ================================================================ siren bar (cab roof, front) + light meshes
    sm = MB("siren")
    sm.box((0, 0, 0.02), (1.80, 0.36, 0.04), "Trim")
    sm.box((0, 0, 0.07), (1.84, 0.40, 0.06), "Trim")
    sm.block((0, 0), 0.10, 0.19, (1.80, 0.34), (1.70, 0.24), "Chrome")
    sm.box((0, 0.18, 0.15), (1.70, 0.012, 0.09), "Glass")
    sm.box((0, -0.18, 0.15), (1.70, 0.012, 0.09), "Glass")
    for sx in (-0.9, 0.0, 0.9):
        sm.box((sx, 0, 0.09), (0.05, 0.36, 0.06), "Trim")
    bar = A.mesh(sm, "SirenBar", loc=(0, 3.60, ROOF + 0.05))
    for sn, sx, mt in (("SirenBar_L", -1, "LightRed"), ("SirenBar_R", 1, "LightBlue")):
        lm = MB("sirenl")
        lm.box((sx * 0.45, 0, 0.14), (0.78, 0.30, 0.12), mt)
        lm.box((sx * 0.45, 0, 0.22), (0.60, 0.22, 0.05), mt)
        A.mesh(lm, sn, parent=bar)

    # ================================================================ wheels
    for nm, sx, y, xs, ww in (("FL", -1, FA, 1.06, 0.34), ("FR", 1, FA, 1.06, 0.34), ("ML", -1, ML, 1.00, 0.42), ("MR", 1, ML, 1.00, 0.42),
                              ("RL", -1, RL, 1.00, 0.42), ("RR", 1, RL, 1.00, 0.42)):
        o = l2_wheel(A.prefix + "Wheel_" + nm, R, ww, sx, A.coll, seg=12, style="truck", loc=(sx * xs, y, R))
        parent_to(o, A.root)
        A.objs["Wheel_" + nm] = o

    # ================================================================ anchors
    SZ = FL + 0.37
    A.node("HeadlightL", (-0.92, 4.38, 1.54))
    A.node("HeadlightR", (0.92, 4.38, 1.54))
    A.node("TaillightL", (-1.02, BY0 - 0.07, 1.72))
    A.node("TaillightR", (1.02, BY0 - 0.07, 1.72))
    A.node("SeatDriver", (-0.45, 2.98, SZ))
    A.node("SeatPassenger", (0.45, 2.98, SZ))
    A.node("SeatRearL", (-0.45, 1.90, SZ))
    A.node("SeatRearR", (0.45, 1.90, SZ))
    A.node("ExitL", (-2.15, 3.20, 0.0), display="ARROWS", size=0.2)
    A.node("ExitR", (2.15, 3.20, 0.0), display="ARROWS", size=0.2)
    A.node("Exhaust", (1.14, 0.90, 3.22))
    A.mats()
    bpy.context.view_layer.update()
    return A


l2_A = l2_build_firetruck()
l2_info = stats(l2_A.root)
print("tris:", l2_tris(l2_A.root))
