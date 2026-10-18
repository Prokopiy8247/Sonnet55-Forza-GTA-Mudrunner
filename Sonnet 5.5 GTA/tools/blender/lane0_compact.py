"""lane0_compact.py - builds vehicles/compact (lane 0, workshop slot 1): cute 3-door hatchback, two-tone roof, round headlights."""


def l0_build_compact():
    ID = "compact"
    PFX = ID + "__"
    clear_asset(PFX)
    C = coll(L0_COLL)
    for n in ("Paint", "Paint2", "Glass", "Trim", "Chrome", "LightHead", "LightTail", "Interior", "Plate", "Tire", "Rim"):
        std_mat(n)
    root = empty(PFX + "root", loc=tuple(workshop(0, 1, 12)), collection=C, display="ARROWS", size=0.5)

    YF, YR = 1.840, -1.860
    FA, RA = 1.20, -1.20
    R = 0.30
    spec = dict(
        rows=[  # y, zb, w, zbelt, zd, ins4, zbump
            (-1.860, 0.30, 0.770, 0.80, 0.86, 0.18, 0.50),
            (-1.800, 0.26, 0.820, 0.85, 0.89, 0.18, 0.48),
            (-1.745, 0.22, 0.840, 0.86, 0.90, 0.18, 0.46),
            (-1.738, 0.22, 0.840, 0.86, 0.38, 0.30, 0.46),
            (-1.600, 0.22, 0.840, 0.86, 0.38, 0.30, 0.46),
            (-1.580, 0.22, 0.840, 0.86, 0.38, 0.30, 0.0),
            (0.618, 0.22, 0.840, 0.86, 0.38, 0.30, 0.0),
            (0.626, 0.22, 0.840, 0.86, 0.90, 0.18, 0.0),
            (1.000, 0.22, 0.836, 0.84, 0.86, 0.18, 0.0),
            (1.500, 0.24, 0.830, 0.77, 0.80, 0.18, 0.0),
            (1.640, 0.26, 0.822, 0.72, 0.76, 0.18, 0.0),
            (1.660, 0.26, 0.822, 0.72, 0.76, 0.18, 0.46),
            (1.760, 0.30, 0.795, 0.68, 0.72, 0.18, 0.48),
            (1.840, 0.33, 0.745, 0.64, 0.69, 0.18, 0.50),
        ],
        arches=[(FA, R, 0.365, 0.012), (RA, R, 0.365, 0.012)],
        mats=dict(chamfer="Trim", bump="Trim", side="Paint", shoulder="Paint", bevel="Paint", top="Paint", bottom="Trim",
                  cap_lo="Trim", cap_hi="Paint"),
        trough=(-1.745, 0.622),
        gh=dict(yfb=0.62, yfr=0.00, yrr=-1.30, yrb=-1.74, zr=1.50, wrf=0.640, wrr=0.640,
                roof_mat="Paint2", pillar_mat="Paint2",
                side_y=[0.52, -0.62, -0.70, -1.30], win_cells=[1, 3], pillar_mats={},
                ws_v=[0, 0.05, 0.90, 1.0], rw_v=[0, 0.06, 0.88, 1.0]),
        doors=[dict(y0=0.52, y1=-0.62, cells=[1], handle=(-0.50, -0.34, 0.74, 0.78), zh=0.55)],
        c1=0.07, k0=0.09, ins3=0.045, shoulder_h=0.10,
    )
    car = L0Car(spec)
    b = L0B(ID + "_body")
    car.build_body(b)
    car.build_greenhouse(b)

    for sx in (1, -1):
        l0_strip_side(car, b, -0.78, 0.76, 0, 1, 0.006, "Trim", sx)
        # round headlights with chrome ring
        b.cyl((sx * 0.50, YF - 0.012, 0.572), 0.112, 0.07, 10, "Chrome", axis="Y")
        b.cyl((sx * 0.50, YF + 0.004, 0.572), 0.092, 0.07, 10, "LightHead", axis="Y")
        # taillights: tall rectangles at the corners
        b.box6(sx * 0.46, sx * 0.80, YR - 0.012, YR + 0.05, 0.50, 0.84, "Trim")
        b.box6(sx * 0.48, sx * 0.77, YR - 0.026, YR + 0.05, 0.52, 0.82, "LightTail")
    # grille slot + chrome badge strip
    b.box6(-0.22, 0.22, YF - 0.05, YF + 0.014, 0.515, 0.615, "Chrome")
    b.box6(-0.20, 0.20, YF - 0.05, YF + 0.026, 0.53, 0.60, "Trim")
    b.box6(-0.62, 0.62, YF - 0.05, YF + 0.03, 0.43, 0.47, "Chrome")
    b.box6(-0.25, 0.25, YF - 0.04, YF + 0.016, 0.335, 0.430, "Plate")
    # rear: bumper bar, plate, hatch handle
    b.box6(-0.62, 0.62, YR - 0.03, YR + 0.06, 0.43, 0.47, "Chrome")
    b.box6(-0.25, 0.25, YR - 0.016, YR + 0.04, 0.50, 0.605, "Plate")
    b.box6(-0.10, 0.10, YR - 0.02, YR + 0.05, 0.69, 0.73, "Chrome")
    b.cyl((0.45, YR + 0.06, 0.27), 0.035, 0.18, 8, "Chrome", axis="Y")
    # hood seam lines
    for sx in (1, -1):
        pa, pb = car.ring_at(0.70)[5], car.ring_at(1.62)[5]
        xa, xb = pa.x - 0.02, pb.x - 0.02
        b.fo([Vector((sx * xa, 0.70, pa.z + 0.004)), Vector((sx * (xa - 0.012), 0.70, pa.z + 0.004)),
              Vector((sx * (xb - 0.012), 1.62, pb.z + 0.004)), Vector((sx * xb, 1.62, pb.z + 0.004))], "Trim", (0, 0, 1))
    pa = car.ring_at(0.70)[5]
    b.fo([Vector((-pa.x, 0.70, pa.z + 0.004)), Vector((pa.x, 0.70, pa.z + 0.004)), Vector((pa.x, 0.712, pa.z + 0.004)), Vector((-pa.x, 0.712, pa.z + 0.004))], "Trim", (0, 0, 1))

    # ---------------- interior (trough floor 0.55)
    FL = 0.38
    b.block((0, 0.46), FL, 0.84, (1.44, 0.30), (1.44, 0.20), "Interior", top_shift=(0, 0.02))
    b.block((-0.40, 0.38), 0.80, 0.90, (0.50, 0.18), (0.44, 0.14), "Interior")
    b.block((0, -0.15), FL, 0.56, (0.24, 0.70), (0.18, 0.66), "Interior")
    l0_seat(b, -0.40, -0.05, FL, 0.44, 0.46, 0.62)
    l0_seat(b, 0.40, -0.05, FL, 0.44, 0.46, 0.62)
    b.block((0, -0.92), FL, FL + 0.10, (1.40, 0.46), (1.36, 0.42), "Interior")
    b.block((0, -1.22), FL, 0.96, (1.40, 0.14), (1.36, 0.10), "Interior", top_shift=(0, -0.08))
    for x in (-0.38, 0.38):
        b.block((x, -1.30), 0.96, 1.08, (0.20, 0.08), (0.18, 0.07), "Interior")
    b.block((0, -1.50), FL, 0.86, (1.44, 0.40), (1.44, 0.30), "Interior")
    l0_steering_wheel(b, (-0.40, 0.25, 0.97), radius=0.15, tilt_deg=26)

    body = b.finish2(C, PFX + "Body")
    parent_to(body, root)
    clear_asset(ID + "_lod__")
    lroot = empty(ID + "_lod__root", loc=(root.location.x, root.location.y + 10.0, 0.0), collection=C, display="ARROWS", size=0.5)
    l0_build_lod(car, lroot, C, ID + "_lod__Body")

    def mirror_extra(bb, sx):
        bb.box6(sx * 0.76, sx * 0.82, 0.46, 0.50, 0.89, 0.925, "Trim")
        bb.block((sx * 0.828, 0.48), 0.90, 0.99, (0.06, 0.15), (0.05, 0.11), "Paint")
    for sx, sn in ((-1, "L"), (1, "R")):
        l0_door(car, root, C, PFX + "Door" + sn, sx, car.s["doors"][0], mirror_extra)

    xw = 0.745
    for nm, sx, y in (("FL", -1, FA), ("FR", 1, FA), ("RL", -1, RA), ("RR", 1, RA)):
        l0_wheel(PFX + "Wheel_" + nm, R, 0.20, sx, C, sx * xw, y, R, seg=12, parent=root)

    E = dict(
        HeadlightL=(-0.50, YF + 0.03, 0.572), HeadlightR=(0.50, YF + 0.03, 0.572),
        TaillightL=(-0.62, YR - 0.03, 0.67), TaillightR=(0.62, YR - 0.03, 0.67),
        SeatDriver=(-0.40, -0.08, 0.60), SeatPassenger=(0.40, -0.08, 0.60),
        SeatRearL=(-0.40, -0.92, 0.60), SeatRearR=(0.40, -0.92, 0.60),
        ExitL=(-1.65, -0.08, 0.0), ExitR=(1.65, -0.08, 0.0), Exhaust=(0.45, YR - 0.03, 0.27),
        Hood=(0.0, 1.25, 0.82), Trunk=(0.0, -1.82, 0.88),
    )
    for nm, loc in E.items():
        empty(PFX + nm, loc=loc, parent=root, collection=C)
    bpy.context.view_layer.update()
    return root, car


l0_root, l0_car = l0_build_compact()
l0_info = stats(l0_root)
