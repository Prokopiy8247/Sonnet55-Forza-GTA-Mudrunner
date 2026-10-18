"""lane0_sedan.py - builds vehicles/sedan (lane 0, workshop slot 0). Run after gta_lib.py + lane0_kit.py."""


def l0_build_sedan():
    ID = "sedan"
    PFX = ID + "__"
    clear_asset(PFX)
    C = coll(L0_COLL)
    for n in ("Paint", "Paint2", "Glass", "Trim", "Chrome", "LightHead", "LightTail", "Interior", "Plate", "Tire", "Rim"):
        std_mat(n)
    root = empty(PFX + "root", loc=tuple(workshop(0, 0, 12)), collection=C, display="ARROWS", size=0.5)

    YF, YR = 2.335, -2.360
    FA, RA = 1.415, -1.415          # axle y
    R = 0.33
    spec = dict(
        rows=[  # y, zb, w, zbelt, zd, ins4, zbump
            (-2.360, 0.34, 0.800, 0.83, 0.90, 0.20, 0.54),
            (-2.295, 0.30, 0.850, 0.88, 0.94, 0.20, 0.52),
            (-2.160, 0.24, 0.882, 0.91, 0.96, 0.20, 0.50),
            (-1.980, 0.20, 0.885, 0.92, 0.97, 0.20, 0.48),
            (-1.960, 0.20, 0.885, 0.92, 0.97, 0.20, 0.0),
            (-1.502, 0.20, 0.885, 0.92, 0.98, 0.20, 0.0),
            (-1.498, 0.20, 0.885, 0.92, 0.40, 0.32, 0.0),
            (0.878, 0.20, 0.885, 0.92, 0.40, 0.32, 0.0),
            (0.882, 0.20, 0.885, 0.92, 0.94, 0.20, 0.0),
            (1.600, 0.20, 0.885, 0.86, 0.89, 0.20, 0.0),
            (2.100, 0.21, 0.880, 0.80, 0.83, 0.20, 0.0),
            (2.160, 0.23, 0.874, 0.77, 0.80, 0.20, 0.0),
            (2.180, 0.23, 0.874, 0.77, 0.80, 0.20, 0.50),
            (2.270, 0.28, 0.850, 0.73, 0.77, 0.20, 0.52),
            (2.335, 0.31, 0.800, 0.70, 0.74, 0.20, 0.54),
        ],
        arches=[(FA, R, 0.40, 0.015), (RA, R, 0.40, 0.015)],
        mats=dict(chamfer="Trim", bump="Trim", side="Paint", shoulder="Paint", bevel="Paint", top="Paint", bottom="Trim",
                  cap_lo="Trim", cap_hi="Paint"),
        trough=(-1.51, 0.89),
        gh=dict(yfb=0.88, yfr=0.25, yrr=-0.95, yrb=-1.50, zr=1.45, wrf=0.66, wrr=0.62,
                side_y=[0.80, -0.22, -0.30, -0.97, -1.04, -1.30], win_cells=[1, 3, 5], pillar_mats={2: "Trim"}),
        doors=[dict(y0=0.80, y1=-0.22, cells=[1], handle=(-0.14, 0.02, 0.80, 0.84), zh=0.60),
               dict(y0=-0.30, y1=-0.97, cells=[3], handle=(-0.88, -0.74, 0.80, 0.84), zh=0.60)],
        c1=0.08, k0=0.10, ins3=0.045, shoulder_h=0.11,
    )
    car = L0Car(spec)
    b = L0B(ID + "_body")
    car.build_body(b)
    car.build_greenhouse(b)

    # ------------------------------------------------------------------ details (both sides)
    for sx in (1, -1):
        # side skirt trim strip along the sill (between the arches)
        l0_strip_side(car, b, -0.99, 0.99, 0, 1, 0.006, "Trim", sx)
        # headlights (front) / taillights (rear)
        b.box6(sx * 0.36, sx * 0.79, YF - 0.05, YF + 0.012, 0.55, 0.715, "Trim")
        b.box6(sx * 0.385, sx * 0.765, YF - 0.05, YF + 0.026, 0.572, 0.695, "LightHead")
        b.box6(sx * 0.40, sx * 0.80, YR - 0.012, YR + 0.05, 0.60, 0.81, "Trim")
        b.box6(sx * 0.425, sx * 0.775, YR - 0.026, YR + 0.05, 0.622, 0.79, "LightTail")
        # wheel-arch chrome lip is the loft itself; rear light inner strip
    # grille
    b.box6(-0.33, 0.33, YF - 0.05, YF + 0.014, 0.555, 0.71, "Chrome")
    b.box6(-0.30, 0.30, YF - 0.05, YF + 0.028, 0.572, 0.694, "Trim")
    for zc in (0.612, 0.648):
        b.box6(-0.30, 0.30, YF - 0.05, YF + 0.036, zc - 0.006, zc + 0.006, "Chrome")
    # front bumper bar, valance intake, plate
    b.box6(-0.72, 0.72, YF - 0.06, YF + 0.034, 0.455, 0.505, "Chrome")
    b.box6(-0.26, 0.26, YF - 0.04, YF + 0.016, 0.335, 0.440, "Plate")
    b.box6(-0.55, 0.55, YF - 0.04, YF + 0.01, 0.315, 0.335, "Trim")
    # rear bumper bar, plate, trunk seam
    b.box6(-0.72, 0.72, YR - 0.034, YR + 0.06, 0.455, 0.505, "Chrome")
    b.box6(-0.26, 0.26, YR - 0.016, YR + 0.04, 0.585, 0.695, "Plate")
    b.box6(-0.08, 0.08, YR - 0.02, YR + 0.05, 0.705, 0.74, "Chrome")
    # exhaust pipe (visible under the rear bumper, right side)
    b.cyl((0.56, YR + 0.08, 0.265), 0.04, 0.20, 8, "Chrome", axis="Y")
    # hood / trunk panel lines (thin dark strips on the deck)
    for sx in (1, -1):
        for (ya, yb_) in ((0.95, 2.18),):
            pa, pb = car.ring_at(ya)[5], car.ring_at(yb_)[5]
            xa, xb = pa.x - 0.02, pb.x - 0.02
            b.fo([Vector((sx * xa, ya, pa.z + 0.004)), Vector((sx * (xa - 0.012), ya, pa.z + 0.004)),
                  Vector((sx * (xb - 0.012), yb_, pb.z + 0.004)), Vector((sx * xb, yb_, pb.z + 0.004))], "Trim", (0, 0, 1))
    pa = car.ring_at(0.95)[5]
    b.fo([Vector((-pa.x, 0.95, pa.z + 0.004)), Vector((pa.x, 0.95, pa.z + 0.004)), Vector((pa.x, 0.962, pa.z + 0.004)), Vector((-pa.x, 0.962, pa.z + 0.004))], "Trim", (0, 0, 1))
    pa = car.ring_at(-1.45)[5]
    b.fo([Vector((-pa.x, -1.55, pa.z + 0.004)), Vector((pa.x, -1.55, pa.z + 0.004)), Vector((pa.x, -1.538, pa.z + 0.004)), Vector((-pa.x, -1.538, pa.z + 0.004))], "Trim", (0, 0, 1))

    # ------------------------------------------------------------------ interior (trough floor z = 0.62)
    FL = 0.40
    b.block((0, 0.74), FL, 0.92, (1.50, 0.30), (1.50, 0.20), "Interior", top_shift=(0, 0.02))
    b.block((-0.40, 0.64), 0.88, 0.98, (0.52, 0.20), (0.46, 0.16), "Interior")
    b.block((0, -0.05), FL, 0.62, (0.26, 0.85), (0.20, 0.80), "Interior")
    l0_seat(b, -0.40, -0.10, FL, 0.46, 0.52, 0.64)
    l0_seat(b, 0.40, -0.10, FL, 0.46, 0.52, 0.64)
    b.block((0, -0.98), FL, FL + 0.10, (1.50, 0.55), (1.46, 0.51), "Interior")
    b.block((0, -1.30), FL, 1.00, (1.50, 0.16), (1.46, 0.12), "Interior", top_shift=(0, -0.08))
    for x in (-0.40, 0.40):
        b.block((x, -1.37), 1.00, 1.12, (0.22, 0.09), (0.20, 0.08), "Interior")
    b.block((0, -1.42), FL, 0.93, (1.52, 0.20), (1.52, 0.18), "Interior")
    l0_steering_wheel(b, (-0.40, 0.40, 1.02), radius=0.165, tilt_deg=24)

    body = b.finish2(C, PFX + "Body")
    parent_to(body, root)
    clear_asset(ID + "_lod__")
    lroot = empty(ID + "_lod__root", loc=(root.location.x, root.location.y + 10.0, 0.0), collection=C, display="ARROWS", size=0.5)
    l0_build_lod(car, lroot, C, ID + "_lod__Body")

    def mirror_extra(bb, sx):
        bb.box6(sx * 0.80, sx * 0.865, 0.60, 0.64, 0.94, 0.975, "Trim")
        bb.block((sx * 0.872, 0.62), 0.95, 1.04, (0.07, 0.16), (0.055, 0.12), "Paint")
    for sx, sn in ((-1, "L"), (1, "R")):
        l0_door(car, root, C, PFX + "Door" + sn, sx, car.s["doors"][0], mirror_extra)
        l0_door(car, root, C, PFX + "DoorRear" + sn, sx, car.s["doors"][1])

    # ------------------------------------------------------------------ wheels
    xw = 0.785
    for nm, sx, y in (("FL", -1, FA), ("FR", 1, FA), ("RL", -1, RA), ("RR", 1, RA)):
        l0_wheel(PFX + "Wheel_" + nm, R, 0.23, sx, C, sx * xw, y, R, seg=14, parent=root)

    # ------------------------------------------------------------------ anchors
    E = dict(
        HeadlightL=(-0.58, YF + 0.03, 0.635), HeadlightR=(0.58, YF + 0.03, 0.635),
        TaillightL=(-0.60, YR - 0.03, 0.70), TaillightR=(0.60, YR - 0.03, 0.70),
        SeatDriver=(-0.40, -0.10, 0.56), SeatPassenger=(0.40, -0.10, 0.56),
        SeatRearL=(-0.40, -1.00, 0.56), SeatRearR=(0.40, -1.00, 0.56),
        ExitL=(-1.75, -0.10, 0.0), ExitR=(1.75, -0.10, 0.0), Exhaust=(0.56, YR - 0.12, 0.265),
        Hood=(0.0, 1.55, 0.88), Trunk=(0.0, -1.95, 0.98),
    )
    for nm, loc in E.items():
        empty(PFX + nm, loc=loc, parent=root, collection=C)
    bpy.context.view_layer.update()
    return root, car


l0_root, l0_car = l0_build_sedan()
l0_info = stats(l0_root)
