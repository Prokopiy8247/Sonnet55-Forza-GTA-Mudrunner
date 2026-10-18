"""lane2_police_tactical.py - builds vehicles/police_tactical (lane 2, index 5). 5.90 x 2.45 x 2.60, WB 3.60, wheel r 0.45. Idempotent, no export.
Armoured tactical truck: slab hull with V-chamfered belly and sloped shoulders, small slit windows, ram bumper + brush bars, roof turret ring with
shield plates, floodlights, SirenBar (L blue / R red), spare wheel on the rear door. Dark Paint, off-white (fixed LiveryWhite) stripes, Paint2 (dark) visor.
Seats (hidden inside the armour): driver, passenger, SeatRearL/R. DoorL/DoorR hinged at the front edge."""


def l2_build_police_tactical():
    A = L2Asset("police_tactical", 5, paint="#1c2026", paint2="#e6e2d6")
    R = 0.45
    FA, RA = 1.80, -1.80
    RAr = 0.585
    HW = 1.225
    BY0, BY1 = -2.70, 2.86
    ROOF = 2.10
    DZ = ROOF - 1.62
    b = MB("body")

    # ---------------------------------------------------------------- lower hull (arches cut for both axles)
    def hull_zt(y):
        if y <= 1.40:
            return 1.45
        if y <= 1.74:
            return l2_lerp(1.45, 1.62, (y - 1.40) / 0.34)
        return l2_lerp(1.62, 1.46, (y - 1.74) / (BY1 - 1.74))
    hull_hw = lambda y: HW if y <= 2.62 else l2_lerp(HW, HW - 0.08, (y - 2.62) / (BY1 - 2.62))
    l2_tube_arch(b, BY0, BY1, hull_hw, 0.55, hull_zt, [(FA, R, RAr), (RA, R, RAr)], extra_ys=(1.40, 1.74, 2.62), c=0.20, cb=0.06,
                 side="Paint", top="Paint", bot="Trim", cap0="Paint", cap1="Paint")
    # ---------------------------------------------------------------- upper cabin (sloped shoulders, steep windscreen)
    l2_tube(b, [dict(y=BY0, hw=HW, zb=1.40, zt=ROOF, c=0.02, cb=0.26), dict(y=1.22, hw=HW, zb=1.40, zt=ROOF, c=0.02, cb=0.26),
                dict(y=1.74, hw=HW, zb=1.40, zt=1.62, c=0.02, cb=0.14)],
            side="Paint", top="Paint", bot="Trim", shoulder="Paint", cap0="Paint")
    # windscreen: two tinted panes with frames on the sloped face
    nrm = Vector((0, DZ, 0.52)).normalized()

    def slope_pt(t, x, off):
        return (x, 1.22 + 0.52 * t, ROOF - DZ * t)

    def slope_quad(x0, x1, t0, t1, off, mat):
        pts = []
        for (x, t) in ((x0, t0), (x1, t0), (x1, t1), (x0, t1)):
            p = Vector(slope_pt(t, x, 0)) + nrm * off
            pts.append(p)
        b.face([b.v(p) for p in pts], mat)
    for (x0, x1) in ((-0.88, -0.05), (0.05, 0.88)):
        slope_quad(x0 - 0.05, x1 + 0.05, 0.04, 0.96, 0.010, "Trim")
        slope_quad(x0, x1, 0.12, 0.88, 0.018, "Glass")
    # visor over the windscreen + roof panel lines
    l2_obox(b, (0, 1.20, ROOF + 0.015), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.98, 0.12, 0.03, "Paint2", taper=(1.0, 1.0))
    for y in (-0.6, -1.8):
        l2_quad_z(b, ROOF + 0.004, -0.92, 0.92, y - 0.012, y + 0.012, "Trim")
    # ---------------------------------------------------------------- sides: slits, plates, stripes, steps
    for s in (-1, 1):
        x = s * (HW + 0.010)
        for (y0, y1) in ((-2.42, -1.82), (-1.58, -0.98), (-0.72, -0.36)):
            l2_quad_x(b, x, y0 - 0.03, y1 + 0.03, 1.55, 1.82, "Trim")
            l2_quad_x(b, x + s * 0.004, y0, y1, 1.58, 1.79, "Glass")
        l2_quad_x(b, x + s * 0.002, -0.12, 1.10, 1.58, 1.88, "Interior")            # door window backing (door frame sits in front)
        l2_quad_x(b, x + s * 0.004, -0.10, 1.08, 1.60, 1.86, "Glass")
        # lower hull: bolted armour plate lines, white stripe, steps
        l2_quad_x(b, x + s * 0.002, -2.62, 1.12, 1.18, 1.26, "LiveryWhite")
        for y in (-1.20, -0.30, 1.12):
            l2_quad_x(b, x + s * 0.002, y - 0.012, y + 0.012, 0.74, 1.40, "Trim")
        for y in (-2.30, -0.80, 0.50):
            for z in (0.86, 1.30):
                b.box((s * (HW + 0.012), y, z), (0.03, 0.07, 0.07), "MetalDark")        # bolt heads
        b.box((s * 1.18, 0.50, 0.55), (0.20, 1.60, 0.05), "MetalDark")                  # side step
        b.beam((s * 1.255, -0.30, 1.22), (s * 1.255, -0.30, 1.90), 0.018, 0.018, 3, "Chrome", caps=False)   # grab handle
        b.beam((s * 1.255, 0.10, 1.22), (s * 1.255, 0.10, 1.90), 0.018, 0.018, 3, "Chrome", caps=False)
        b.beam((s * 1.255, -0.30, 1.90), (s * 1.255, 0.10, 1.90), 0.018, 0.018, 3, "Chrome", caps=False)
        # wheel liners / flares
        for yw in (FA, RA):
            xa, xb = sorted((s * 0.80, s * 1.215))
            l2_arc_fender(b, yw, R, xa, xb, 0.52, 0.56, math.radians(-72), math.radians(72), 5, "Trim")
    # ---------------------------------------------------------------- front end: hood details, grille, ram bumper, brush bars
    FY = BY1 + 0.005
    b.box((0, FY + 0.01, 1.12), (1.10, 0.03, 0.46), "Trim")
    for k in range(4):
        l2_quad_y(b, FY + 0.036, -0.50, 0.50, 0.96 + k * 0.10, 0.99 + k * 0.10, "Metal")
    l2_quad_y(b, FY + 0.02, -0.12, 0.12, 1.40, 1.52, "LiveryWhite")
    for s in (-1, 1):
        b.box((s * 0.88, FY + 0.01, 1.12), (0.46, 0.06, 0.30), "Trim")
        b.box((s * 0.88, FY + 0.045, 1.12), (0.36, 0.03, 0.20), "LightHead")
        for k in range(3):
            l2_quad_y(b, FY + 0.072, s * 0.88 - 0.19, s * 0.88 + 0.19, 1.04 + k * 0.08, 1.06 + k * 0.08, "Trim")     # protective slats
        b.box((s * 0.88, FY + 0.005, 1.40), (0.30, 0.05, 0.08), "LightAmber")
    # ram bumper (heavy), bull bars
    b.prism([(-1.20, 2.62), (1.20, 2.62), (1.26, 2.74), (1.23, 2.93), (1.0, 2.94), (-1.0, 2.94), (-1.23, 2.93), (-1.26, 2.74)], 0.40, 0.84, "MetalDark")
    b.box((0, 2.945, 0.62), (1.30, 0.03, 0.14), "Metal")
    b.box((0, 2.95, 0.84), (1.66, 0.05, 0.05), "Chrome")
    for xx in (-0.78, -0.26, 0.26, 0.78):
        b.beam((xx, 2.90, 0.84), (xx, 2.93, 1.50), 0.03, 0.03, 4, "MetalDark")
    b.beam((-0.78, 2.93, 1.50), (0.78, 2.93, 1.50), 0.03, 0.03, 4, "MetalDark")
    b.box((0, 2.955, 0.30), (0.50, 0.02, 0.14), "Plate")
    # ---------------------------------------------------------------- rear: double doors, spare wheel, step, lights
    RY = BY0 - 0.010
    l2_quad_y(b, RY, -0.012, 0.012, 0.66, 2.00, "Trim")
    l2_quad_y(b, RY, -1.10, 1.10, 0.66, 0.686, "Trim")
    l2_quad_y(b, RY, -1.10, 1.10, 2.00, 2.026, "Trim")
    for s in (-1, 1):
        l2_quad_y(b, RY, s * 1.10 - 0.012, s * 1.10 + 0.012, 0.66, 2.02, "Trim")
        b.box((s * 1.06, RY - 0.02, 0.96), (0.16, 0.05, 0.40), "Trim")
        b.box((s * 1.06, RY - 0.045, 0.96), (0.12, 0.03, 0.34), "LightTail")
        b.box((s * 1.06, RY - 0.03, 1.28), (0.12, 0.03, 0.10), "LightAmber")
        b.box((s * 0.30, RY - 0.02, 1.00), (0.04, 0.04, 0.22), "Chrome")
    l2_cbox(b, BY0 - 0.16, BY0 + 0.02, 1.14, 0.40, 0.66, c=0.05, side="MetalDark", top="Metal", bot="Trim", cap0="MetalDark", cap1="MetalDark")
    b.cyl((0, BY0 - 0.14, 1.52), 0.40, 0.22, 10, "Tire", axis="Y")
    b.cyl((0, BY0 - 0.256, 1.52), 0.25, 0.03, 8, "Rim", axis="Y")
    b.cyl((0, BY0 - 0.275, 1.52), 0.07, 0.03, 6, "Chrome", axis="Y")
    b.box((0, BY0 - 0.012, 0.82), (0.44, 0.012, 0.20), "Plate")
    # ---------------------------------------------------------------- roof: turret ring + shield plates, floodlights
    TC = (0.0, -1.20)
    l2_ring_z(b, TC, 0.60, 0.48, ROOF - 0.01, ROOF + 0.20, 10, "Metal", "Metal", "Trim", "Trim")
    b.cyl((TC[0], TC[1], ROOF + 0.02), 0.50, 0.03, 10, "Trim", axis="Z")
    c15, s15 = math.cos(math.radians(15)), math.sin(math.radians(15))
    l2_obox(b, (0, TC[1] + 0.60, ROOF + 0.34), (1, 0, 0), (0, c15, s15), (0, -s15, c15), 0.56, 0.03, 0.17, "Metal", taper=(0.94, 1.0))
    for s in (-1, 1):
        a = s * math.radians(50)
        ax = l2_rotz((1, 0, 0), a)
        ay = l2_rotz((0, 1, 0), a)
        px, py, _ = l2_rotz((s * 0.50, 0.38, 0), 0)
        l2_obox(b, (TC[0] + s * 0.56, TC[1] + 0.34, ROOF + 0.33), ax, ay, (0, 0, 1), 0.26, 0.03, 0.17, "Metal")
        l2_obox(b, (TC[0] + s * 0.20, TC[1] - 0.72, ROOF + 0.10), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.06, 0.06, 0.10, "Trim")   # rear handrail posts
    # roof floodlights (front corners) + antenna
    for s in (-1, 1):
        fx = s * 0.92
        b.box((fx, 0.40, ROOF + 0.07), (0.10, 0.12, 0.14), "MetalDark")
        l2_obox(b, (fx, 0.52, ROOF + 0.24), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.17, 0.10, 0.11, "Trim", taper=(0.95, 1.0))
        l2_quad_y(b, 0.625, fx - 0.14, fx + 0.14, ROOF + 0.15, ROOF + 0.33, "LightHead")
        b.box((s * 0.95, -2.40, ROOF + 0.09), (0.28, 0.12, 0.10), "LightRed" if s < 0 else "LightBlue")        # rear roof strobes
    b.beam((-0.95, -2.20, ROOF), (-0.99, -2.28, ROOF + 0.30), 0.012, 0.007, 3, "Trim", caps=False)
    # hood louvres + panel seams + tow hooks + roof spotlight
    for k in range(3):
        for sx in (-1, 1):
            l2_quad_z(b, 1.56 + 0.0 * k, sx * 0.30 - 0.20, sx * 0.30 + 0.20, 2.02 + k * 0.12, 2.04 + k * 0.12, "Trim")
    for s in (-1, 1):
        for y in (-2.0, -0.2):
            l2_quad_x(b, s * (HW + 0.009), y - 0.01, y + 0.01, 1.84, 2.0 - 0.0, "Trim")
        b.beam((s * 0.45, 2.86, 0.62), (s * 0.45, 3.00, 0.62), 0.03, 0.03, 4, "Metal")
        b.beam((s * 0.45, BY0 + 0.02, 0.50), (s * 0.45, BY0 - 0.16, 0.50), 0.03, 0.03, 4, "Metal")
    b.box((0.75, -0.25, ROOF + 0.06), (0.16, 0.20, 0.12), "MetalDark")
    b.cyl((0.75, -0.18, ROOF + 0.20), 0.12, 0.34, 8, "Trim", axis="Y")
    b.cyl((0.75, -0.005, ROOF + 0.20), 0.10, 0.02, 8, "LightHead", axis="Y")
    # underbody + axles + exhaust
    b.block((0, 0.0), 0.28, 0.58, (1.5, 5.0), (1.5, 5.0), "Trim")
    for yw in (FA, RA):
        b.box((0, yw, R), (2.04, 0.20, 0.20), "MetalDark")
        b.box((0, yw, R + 0.12), (0.34, 0.34, 0.26), "MetalDark")                         # differential
    b.beam((0.70, 0.5, 0.40), (0.70, BY0 - 0.12, 0.44), 0.04, 0.04, 4, "MetalDark")

    body = A.mesh(b, "Body")
    l2_island_report(body)

    # ---------------------------------------------------------------- doors (front, hinge at front edge y=1.22)
    YH = 1.22
    Z0 = 0.72
    for s, nm in ((-1, "DoorL"), (1, "DoorR")):
        dm = MB("door")
        xw = HW
        l2_flat_slab(dm, l2_rect(-0.26, YH, Z0, 1.56, 0.03), xw, s, 0.05, -0.02, "Paint")
        l2_flat_slab(dm, l2_rect(-0.26, YH, 1.90, 2.04, 0.0), xw, s, 0.05, -0.02, "Paint")
        l2_flat_slab(dm, l2_rect(-0.26, -0.12, 1.56, 1.90, 0.0), xw, s, 0.05, -0.02, "Paint")
        l2_flat_slab(dm, l2_rect(1.10, YH, 1.56, 1.90, 0.0), xw, s, 0.05, -0.02, "Paint")
        l2_flat_slab(dm, l2_rect(-0.20, 1.16, 1.15, 1.23, 0.0), xw, s, 0.014, 0.03, "LiveryWhite")
        dm.box((s * (xw + 0.04), -0.10, 1.34), (0.04, 0.20, 0.04), "Chrome")
        l2_mirror(dm, s, 1.15, 1.34, 1.84, size=(0.15, 0.30))
        dm.translate((-s * xw, -YH, -Z0))
        A.mesh(dm, nm, loc=(s * xw, YH, Z0))

    # ---------------------------------------------------------------- siren bar (roof, over the windscreen)
    sm = MB("siren")
    sm.box((0, 0, 0.02), (1.20, 0.30, 0.04), "Trim")
    sm.block((0, 0), 0.04, 0.16, (1.18, 0.28), (1.10, 0.20), "Chrome")
    sm.box((0, 0.15, 0.10), (1.10, 0.012, 0.09), "Glass")
    sm.box((0, -0.15, 0.10), (1.10, 0.012, 0.09), "Glass")
    bar = A.mesh(sm, "SirenBar", loc=(0, 0.72, ROOF + 0.04))
    for sn, sx, mt in (("SirenBar_L", -1, "LightBlue"), ("SirenBar_R", 1, "LightRed")):
        lm = MB("sirenl")
        lm.box((sx * 0.30, 0, 0.10), (0.46, 0.24, 0.09), mt)
        lm.box((sx * 0.30, 0, 0.16), (0.34, 0.16, 0.04), mt)
        A.mesh(lm, sn, parent=bar)

    # ---------------------------------------------------------------- wheels
    for nm, sx, y in (("FL", -1, FA), ("FR", 1, FA), ("RL", -1, RA), ("RR", 1, RA)):
        o = l2_wheel(A.prefix + "Wheel_" + nm, R, 0.36, sx, A.coll, seg=12, style="truck", loc=(sx * 1.00, y, R))
        parent_to(o, A.root)
        A.objs["Wheel_" + nm] = o

    # ---------------------------------------------------------------- anchors
    SZ = 1.20
    A.node("HeadlightL", (-0.88, FY + 0.07, 1.12))
    A.node("HeadlightR", (0.88, FY + 0.07, 1.12))
    A.node("TaillightL", (-1.06, RY - 0.07, 0.96))
    A.node("TaillightR", (1.06, RY - 0.07, 0.96))
    A.node("SeatDriver", (-0.45, 0.55, SZ))
    A.node("SeatPassenger", (0.45, 0.55, SZ))
    A.node("SeatRearL", (-0.45, -0.85, SZ))
    A.node("SeatRearR", (0.45, -0.85, SZ))
    A.node("ExitL", (-2.05, 0.50, 0.0), display="ARROWS", size=0.2)
    A.node("ExitR", (2.05, 0.50, 0.0), display="ARROWS", size=0.2)
    A.node("Exhaust", (0.70, BY0 - 0.12, 0.44))
    A.mats()
    bpy.context.view_layer.update()
    return A


l2_A = l2_build_police_tactical()
l2_info = stats(l2_A.root)
print("tris:", l2_tris(l2_A.root))
