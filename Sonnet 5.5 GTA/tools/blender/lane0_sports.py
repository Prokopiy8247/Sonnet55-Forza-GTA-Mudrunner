"""lane0_sports.py - builds vehicles/sports (lane 0, workshop slot 2): low wedge, long tail, rear wing, side intakes, 2 seats."""


def l0_build_sports():
    ID = "sports"
    PFX = ID + "__"
    clear_asset(PFX)
    C = coll(L0_COLL)
    for n in ("Paint", "Paint2", "Glass", "Trim", "Chrome", "LightHead", "LightTail", "Interior", "Plate", "Tire", "Rim"):
        std_mat(n)
    root = empty(PFX + "root", loc=tuple(workshop(0, 2, 12)), collection=C, display="ARROWS", size=0.5)

    YF, YR = 2.150, -2.150
    FA, RA = 1.30, -1.30
    RF, RR = 0.34, 0.35
    spec = dict(
        rows=[  # y, zb, w, zbelt, zd, ins4, zbump
            (-2.150, 0.26, 0.860, 0.76, 0.82, 0.22, 0.50),
            (-2.090, 0.22, 0.915, 0.78, 0.83, 0.22, 0.48),
            (-1.980, 0.17, 0.940, 0.81, 0.85, 0.22, 0.46),
            (-1.940, 0.17, 0.940, 0.82, 0.86, 0.22, 0.0),
            (-1.602, 0.17, 0.940, 0.82, 0.86, 0.22, 0.0),
            (-1.598, 0.17, 0.940, 0.82, 0.22, 0.40, 0.0),
            (0.558, 0.15, 0.940, 0.76, 0.22, 0.40, 0.0),
            (0.562, 0.15, 0.940, 0.76, 0.79, 0.22, 0.0),
            (1.000, 0.15, 0.940, 0.80, 0.83, 0.22, 0.0),
            (1.300, 0.15, 0.940, 0.80, 0.83, 0.22, 0.0),
            (1.600, 0.17, 0.932, 0.78, 0.81, 0.22, 0.0),
            (1.720, 0.19, 0.925, 0.70, 0.73, 0.22, 0.0),
            (2.000, 0.20, 0.900, 0.56, 0.59, 0.22, 0.0),
            (2.040, 0.20, 0.895, 0.55, 0.58, 0.22, 0.0),
            (2.060, 0.20, 0.895, 0.55, 0.58, 0.22, 0.40),
            (2.110, 0.22, 0.870, 0.52, 0.55, 0.22, 0.41),
            (2.150, 0.24, 0.830, 0.50, 0.53, 0.22, 0.42),
        ],
        arches=[(FA, RF, 0.38, 0.015), (RA, RR, 0.40, 0.025)],
        mats=dict(chamfer="Trim", bump="Trim", side="Paint", shoulder="Paint", bevel="Paint", top="Paint", bottom="Trim",
                  cap_lo="Trim", cap_hi="Paint"),
        trough=(-1.60, 0.56),
        gh=dict(yfb=0.56, yfr=-0.30, yrr=-1.00, yrb=-1.60, zr=1.20, wrf=0.70, wrr=0.60,
                roof_mat="Paint", pillar_mat="Paint", side_y=[0.46, -0.50, -0.58, -1.15], win_cells=[1, 3], pillar_mats={2: "Trim"},
                ws_v=[0, 0.05, 0.88, 1.0], rw_v=[0, 0.06, 0.84, 1.0], rw_u=[0, 0.06, 0.94, 1.0]),
        doors=[dict(y0=0.46, y1=-0.50, cells=[1], handle=(-0.34, -0.20, 0.64, 0.675), zh=0.50)],
        c1=0.07, k0=0.10, ins3=0.06, shoulder_h=0.07,
    )
    car = L0Car(spec)
    print('RING CHECK', car.check())
    b = L0B(ID + "_body")
    car.build_body(b)
    car.build_greenhouse(b)

    for sx in (1, -1):
        l0_strip_side(car, b, -0.80, 0.85, 0, 1, 0.006, "Trim", sx)
        # side intake behind the door (dark recess with three fins)
        yi0, yi1 = -0.56, -0.86
        for k, (za, zb_) in enumerate(((0.34, 0.40), (0.43, 0.49), (0.52, 0.58))):
            ya = yi0 + (yi1 - yi0) * 0.0
            xa0 = car.half_width_at(yi0, (za + zb_) / 2)
            xa1 = car.half_width_at(yi1, (za + zb_) / 2)
            b.fo([Vector((sx * (xa0 + 0.004), yi0, za)), Vector((sx * (xa1 + 0.004), yi1, za + 0.02)),
                  Vector((sx * (xa1 + 0.004), yi1, zb_ + 0.02)), Vector((sx * (xa0 + 0.004), yi0, zb_))], "Trim", (sx, 0, 0.1))
        # front lights: slim wedge strips with chrome surround
        b.box6(sx * 0.27, sx * 0.80, YF - 0.05, YF + 0.012, 0.392, 0.482, "Trim")
        b.box6(sx * 0.29, sx * 0.78, YF - 0.05, YF + 0.024, 0.408, 0.462, "LightHead")
        # rear: full-width-ish light bars with surround, twin exhaust tips
        b.box6(sx * 0.12, sx * 0.84, YR - 0.012, YR + 0.05, 0.585, 0.715, "Trim")
        b.box6(sx * 0.14, sx * 0.82, YR - 0.026, YR + 0.05, 0.607, 0.693, "LightTail")
        b.cyl((sx * 0.46, YR + 0.07, 0.31), 0.048, 0.20, 8, "Chrome", axis="Y")
        # wing end plates + struts
        b.box6(sx * 0.80, sx * 0.83, -2.14, -1.84, 0.96, 1.16, "Paint2")
        b.box6(sx * 0.40, sx * 0.46, -2.00, -1.94, 0.80, 1.09, "Trim")
        # hood vents
        for xo in (0.28, 0.40):
            pa = car.ring_at(1.55)[5]
            pb = car.ring_at(1.25)[5]
            b.fo([Vector((sx * xo, 1.25, pb.z + 0.004)), Vector((sx * (xo + 0.06), 1.25, pb.z + 0.004)),
                  Vector((sx * (xo + 0.06), 1.55, pa.z + 0.004)), Vector((sx * xo, 1.55, pa.z + 0.004))], "Trim", (0, 0, 1))
    # nose: low wide intake + chrome blade + plate; splitter
    b.box6(-0.62, 0.62, YF - 0.06, YF + 0.01, 0.255, 0.355, "Trim")
    b.box6(-0.58, 0.58, YF - 0.06, YF + 0.02, 0.365, 0.378, "Chrome")
    b.box6(-0.24, 0.24, YF - 0.04, YF + 0.012, 0.255, 0.345, "Plate")
    b.box6(-0.80, 0.80, YF - 0.20, YF + 0.04, 0.215, 0.235, "Trim")
    # rear: diffuser band, plate, centre brake light, wing blade
    b.box6(-0.70, 0.70, YR - 0.03, YR + 0.06, 0.30, 0.34, "Chrome")
    b.box6(-0.24, 0.24, YR - 0.016, YR + 0.04, 0.38, 0.475, "Plate")
    b.box6(-0.10, 0.10, YR - 0.02, YR + 0.05, 0.625, 0.675, "LightTail")
    b.block((0, -1.99), 1.085, 1.125, (1.66, 0.26), (1.66, 0.20), "Paint2", top_shift=(0, -0.03))
    # hood front lip / centre crease
    pa = car.ring_at(0.62)[5]
    b.fo([Vector((-pa.x, 0.62, pa.z + 0.004)), Vector((pa.x, 0.62, pa.z + 0.004)), Vector((pa.x, 0.632, pa.z + 0.004)), Vector((-pa.x, 0.632, pa.z + 0.004))], "Trim", (0, 0, 1))

    # ---------------- interior (trough floor 0.30)
    FL = 0.22
    b.block((0, 0.32), FL, 0.68, (1.60, 0.34), (1.60, 0.20), "Interior", top_shift=(0, 0.05))
    b.block((-0.42, 0.26), 0.66, 0.76, (0.54, 0.20), (0.48, 0.16), "Interior")
    b.block((0, -0.30), FL, 0.44, (0.30, 1.50), (0.24, 1.46), "Interior")
    l0_seat(b, -0.40, -0.36, FL, 0.46, 0.60, 0.62, lean=0.20, cush_h=0.07)
    l0_seat(b, 0.40, -0.36, FL, 0.46, 0.60, 0.62, lean=0.20, cush_h=0.07)
    b.block((0, -1.30), FL, 0.80, (1.50, 0.50), (1.50, 0.40), "Interior")
    l0_steering_wheel(b, (-0.42, 0.14, 0.74), radius=0.145, tilt_deg=30)

    body = b.finish2(C, PFX + "Body")
    parent_to(body, root)
    clear_asset(ID + "_lod__")
    lroot = empty(ID + "_lod__root", loc=(root.location.x, root.location.y + 10.0, 0.0), collection=C, display="ARROWS", size=0.5)
    l0_build_lod(car, lroot, C, ID + "_lod__Body")

    def mirror_extra(bb, sx):
        bb.box6(sx * 0.80, sx * 0.88, 0.36, 0.40, 0.78, 0.81, "Trim")
        bb.block((sx * 0.90, 0.38), 0.78, 0.86, (0.07, 0.17), (0.05, 0.12), "Paint")
    for sx, sn in ((-1, "L"), (1, "R")):
        l0_door(car, root, C, PFX + "Door" + sn, sx, car.s["doors"][0], mirror_extra)

    for nm, sx, y, r, wd, xw in (("FL", -1, FA, RF, 0.24, 0.835), ("FR", 1, FA, RF, 0.24, 0.835),
                                 ("RL", -1, RA, RR, 0.30, 0.805), ("RR", 1, RA, RR, 0.30, 0.805)):
        l0_wheel(PFX + "Wheel_" + nm, r, wd, sx, C, sx * xw, y, r, seg=14, parent=root)

    E = dict(
        HeadlightL=(-0.55, YF + 0.03, 0.435), HeadlightR=(0.55, YF + 0.03, 0.435),
        TaillightL=(-0.50, YR - 0.03, 0.65), TaillightR=(0.50, YR - 0.03, 0.65),
        SeatDriver=(-0.40, -0.40, 0.34), SeatPassenger=(0.40, -0.40, 0.34),
        ExitL=(-1.80, -0.20, 0.0), ExitR=(1.80, -0.20, 0.0), Exhaust=(0.46, YR - 0.03, 0.31),
        Hood=(0.0, 1.40, 0.82), Trunk=(0.0, -1.90, 0.86),
    )
    for nm, loc in E.items():
        empty(PFX + nm, loc=loc, parent=root, collection=C)
    bpy.context.view_layer.update()
    return root, car


l0_root, l0_car = l0_build_sports()
l0_info = stats(l0_root)
