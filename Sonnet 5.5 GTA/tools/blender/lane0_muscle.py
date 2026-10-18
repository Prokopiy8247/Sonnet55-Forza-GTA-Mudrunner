"""lane0_muscle.py - builds vehicles/muscle (lane 0, workshop slot 3): 2-door fastback coupe, very long hood with scoop, wide haunches, twin stripes."""


def l0_hexa(b, bot, top, mats, default="Paint"):
    """closed hexahedron from two quads (same corner order); faces get mats.get('bot'|'top'|'back'|'right'|'front'|'left')."""
    P = [Vector(p) for p in list(bot) + list(top)]
    c = sum(P, Vector((0, 0, 0))) / 8.0
    for (a, bb, cc, d, key) in ((0, 1, 2, 3, "bot"), (4, 5, 6, 7, "top"), (0, 1, 5, 4, "back"), (1, 2, 6, 5, "right"), (2, 3, 7, 6, "front"), (3, 0, 4, 7, "left")):
        pts = [P[a], P[bb], P[cc], P[d]]
        ctr = sum(pts, Vector((0, 0, 0))) / 4.0
        b.fo(pts, mats.get(key, default), ctr - c)


def l0_stripe(car, b, x0, x1, ys, mat, idx=5, dz=0.004):
    """flat decal strip along the deck centreline surface (ring point idx 5 = deck top) between x0..x1 for the y samples."""
    prev = None
    for y in ys:
        z = car.ring_at(y)[idx].z + dz
        cur = (Vector((x0, y, z)), Vector((x1, y, z)))
        if prev is not None:
            b.fo([prev[0], prev[1], cur[1], cur[0]], mat, (0, 0, 1))
        prev = cur


def l0_build_muscle():
    ID = "muscle"
    PFX = ID + "__"
    clear_asset(PFX)
    C = coll(L0_COLL)
    for n in ("Paint", "Paint2", "Glass", "Trim", "Chrome", "LightHead", "LightTail", "Interior", "Plate", "Tire", "Rim"):
        std_mat(n)
    root = empty(PFX + "root", loc=tuple(workshop(0, 3, 12)), collection=C, display="ARROWS", size=0.5)

    YF, YR = 2.420, -2.400
    FA, RA = 1.45, -1.45
    R = 0.35
    spec = dict(
        rows=[  # y, zb, w, zbelt, zd, ins4, zbump
            (-2.400, 0.34, 0.890, 0.84, 0.90, 0.22, 0.58),
            (-2.345, 0.30, 0.940, 0.90, 0.96, 0.22, 0.56),
            (-2.205, 0.24, 0.958, 0.94, 0.99, 0.22, 0.54),
            (-2.160, 0.24, 0.960, 0.96, 1.00, 0.22, 0.0),
            (-1.805, 0.22, 0.960, 0.96, 1.00, 0.22, 0.0),
            (-1.795, 0.22, 0.960, 0.96, 0.30, 0.40, 0.0),
            (-1.200, 0.20, 0.958, 0.96, 0.30, 0.40, 0.0),
            (-0.600, 0.20, 0.940, 0.96, 0.30, 0.40, 0.0),
            (0.595, 0.20, 0.935, 0.96, 0.30, 0.40, 0.0),
            (0.605, 0.20, 0.935, 0.96, 1.00, 0.24, 0.0),
            (1.450, 0.20, 0.930, 0.94, 0.975, 0.24, 0.0),
            (2.000, 0.22, 0.925, 0.90, 0.94, 0.24, 0.0),
            (2.225, 0.25, 0.915, 0.85, 0.90, 0.24, 0.0),
            (2.265, 0.25, 0.912, 0.84, 0.89, 0.24, 0.55),
            (2.350, 0.30, 0.890, 0.82, 0.86, 0.24, 0.57),
            (2.420, 0.33, 0.850, 0.79, 0.83, 0.24, 0.58),
        ],
        arches=[(FA, R, 0.42, 0.03), (RA, R, 0.43, 0.015)],
        mats=dict(chamfer="Trim", bump="Trim", side="Paint", shoulder="Paint", bevel="Paint", top="Paint", bottom="Trim",
                  cap_lo="Trim", cap_hi="Paint"),
        trough=(-1.80, 0.60),
        gh=dict(yfb=0.60, yfr=-0.20, yrr=-0.95, yrb=-1.80, zr=1.38, wrf=0.64, wrr=0.60,
                roof_mat="Paint", pillar_mat="Paint", side_y=[0.50, -0.70, -0.78, -1.30], win_cells=[1, 3], pillar_mats={2: "Trim"},
                ws_v=[0, 0.05, 0.90, 1.0], rw_v=[0, 0.07, 0.86, 1.0], rw_u=[0, 0.07, 0.93, 1.0]),
        doors=[dict(y0=0.50, y1=-0.70, cells=[1], handle=(-0.52, -0.36, 0.80, 0.84), zh=0.60)],
        c1=0.08, k0=0.11, ins3=0.05, shoulder_h=0.11,
    )
    car = L0Car(spec)
    print("RING CHECK", car.check())
    b = L0B(ID + "_body")
    car.build_body(b)
    car.build_greenhouse(b)

    S2 = "Paint2"
    # ---- twin racing stripes: hood, roof, trunk
    for sx in (1, -1):
        for (x0, x1) in ((0.20, 0.38),):
            xa, xb = (sx * x0, sx * x1)
            l0_stripe(car, b, min(xa, xb), max(xa, xb), [0.62, 1.00, 1.45, 2.00, 2.25, 2.40], S2)
            l0_stripe(car, b, min(xa, xb), max(xa, xb), [-1.82, -2.00, -2.20, -2.40], S2)
            zr = spec["gh"]["zr"] + 0.004
            b.fo([Vector((xa, -0.17, zr)), Vector((xb, -0.17, zr)), Vector((xb, -0.97, zr)), Vector((xa, -0.97, zr))], S2, (0, 0, 1))

    for sx in (1, -1):
        l0_strip_side(car, b, -0.92, 0.95, 0, 1, 0.006, "Trim", sx)
        # rear haunch strake / quarter vent behind the door (dark slats)
        for (za, zb_) in ((0.58, 0.64), (0.67, 0.73)):
            x0 = car.half_width_at(-0.80, (za + zb_) / 2)
            x1 = car.half_width_at(-1.00, (za + zb_) / 2)
            b.fo([Vector((sx * (x0 + 0.004), -0.80, za)), Vector((sx * (x1 + 0.004), -1.00, za)),
                  Vector((sx * (x1 + 0.004), -1.00, zb_)), Vector((sx * (x0 + 0.004), -0.80, zb_))], "Trim", (sx, 0, 0.1))
        # quad round headlights with chrome rims
        for xc in (0.36, 0.64):
            b.cyl((sx * xc, YF - 0.03, 0.695), 0.098, 0.08, 10, "Chrome", axis="Y")
            b.cyl((sx * xc, YF - 0.012, 0.695), 0.078, 0.08, 10, "LightHead", axis="Y")
        # tail lights: long bars
        b.box6(sx * 0.30, sx * 0.90, YR - 0.012, YR + 0.05, 0.64, 0.82, "Chrome")
        b.box6(sx * 0.33, sx * 0.87, YR - 0.026, YR + 0.05, 0.665, 0.795, "LightTail")
        # dual exhaust tips
        b.cyl((sx * 0.62, YR + 0.12, 0.28), 0.052, 0.24, 8, "Chrome", axis="Y")
        # side marker (small amber-ish trim dot as dark insert)
    # grille
    b.box6(-0.25, 0.25, YF - 0.06, YF + 0.016, 0.605, 0.80, "Chrome")
    b.box6(-0.225, 0.225, YF - 0.06, YF + 0.03, 0.62, 0.785, "Trim")
    for zc in (0.665, 0.705, 0.745):
        b.box6(-0.225, 0.225, YF - 0.06, YF + 0.038, zc - 0.006, zc + 0.006, "Chrome")
    # chrome bumper bar (full width, wraps the corners) + plate + lower valance
    b.box6(-0.88, 0.88, YF - 0.10, YF + 0.04, 0.40, 0.50, "Chrome")
    b.box6(-0.26, 0.26, YF - 0.04, YF + 0.047, 0.405, 0.495, "Plate")
    b.box6(-0.70, 0.70, YF - 0.08, YF + 0.02, 0.33, 0.395, "Trim")
    b.box6(-0.88, 0.88, YR - 0.04, YR + 0.10, 0.40, 0.50, "Chrome")
    b.box6(-0.26, 0.26, YR - 0.047, YR + 0.04, 0.405, 0.495, "Plate")
    # hood scoop: wedge with dark intake opening at the front
    l0_hexa(b,
            [(-0.17, 1.00, car.ring_at(1.00)[5].z - 0.01), (0.17, 1.00, car.ring_at(1.00)[5].z - 0.01),
             (0.17, 1.74, car.ring_at(1.74)[5].z - 0.01), (-0.17, 1.74, car.ring_at(1.74)[5].z - 0.01)],
            [(-0.13, 1.06, car.ring_at(1.00)[5].z + 0.025), (0.13, 1.06, car.ring_at(1.00)[5].z + 0.025),
             (0.13, 1.72, car.ring_at(1.74)[5].z + 0.135), (-0.13, 1.72, car.ring_at(1.74)[5].z + 0.135)],
            dict(front="Trim", top="Paint"))
    # ducktail on the trunk lid
    zt = car.ring_at(-2.2)[5].z
    l0_hexa(b, [(-0.62, -2.34, zt - 0.02), (0.62, -2.34, zt - 0.02), (0.62, -2.08, zt - 0.02), (-0.62, -2.08, zt - 0.02)],
            [(-0.62, -2.37, zt + 0.07), (0.62, -2.37, zt + 0.07), (0.62, -2.12, zt + 0.015), (-0.62, -2.12, zt + 0.015)], dict(default="Paint"))

    # ---------------- interior (trough floor 0.38)
    FL = 0.30
    b.block((0, 0.46), FL, 0.96, (1.66, 0.36), (1.66, 0.22), "Interior", top_shift=(0, 0.03))
    b.block((-0.42, 0.34), 0.94, 1.04, (0.54, 0.20), (0.48, 0.16), "Interior")
    b.block((0, -0.45), FL, 0.56, (0.28, 1.60), (0.22, 1.56), "Interior")
    l0_seat(b, -0.42, -0.18, FL, 0.50, 0.54, 0.64, lean=0.12, cush_h=0.10)
    l0_seat(b, 0.42, -0.18, FL, 0.50, 0.54, 0.64, lean=0.12, cush_h=0.10)
    b.block((0, -1.05), FL, FL + 0.10, (1.60, 0.52), (1.56, 0.48), "Interior")
    b.block((0, -1.40), FL, 0.94, (1.60, 0.16), (1.56, 0.12), "Interior", top_shift=(0, -0.10))
    b.block((0, -1.55), FL, 0.94, (1.60, 0.20), (1.60, 0.18), "Interior")
    l0_steering_wheel(b, (-0.42, 0.30, 0.98), radius=0.17, tilt_deg=26)

    body = b.finish2(C, PFX + "Body")
    parent_to(body, root)
    clear_asset(ID + "_lod__")
    lroot = empty(ID + "_lod__root", loc=(root.location.x, root.location.y + 10.0, 0.0), collection=C, display="ARROWS", size=0.5)
    l0_build_lod(car, lroot, C, ID + "_lod__Body")

    def mirror_extra(bb, sx):
        bb.box6(sx * 0.84, sx * 0.915, 0.46, 0.50, 1.00, 1.035, "Trim")
        bb.block((sx * 0.925, 0.48), 1.00, 1.09, (0.065, 0.16), (0.05, 0.12), "Chrome")
    for sx, sn in ((-1, "L"), (1, "R")):
        l0_door(car, root, C, PFX + "Door" + sn, sx, car.s["doors"][0], mirror_extra)

    for nm, sx, y, wd, xw in (("FL", -1, FA, 0.26, 0.83), ("FR", 1, FA, 0.26, 0.83),
                              ("RL", -1, RA, 0.30, 0.825), ("RR", 1, RA, 0.30, 0.825)):
        l0_wheel(PFX + "Wheel_" + nm, R, wd, sx, C, sx * xw, y, R, seg=14, parent=root)

    E = dict(
        HeadlightL=(-0.50, YF + 0.03, 0.695), HeadlightR=(0.50, YF + 0.03, 0.695),
        TaillightL=(-0.60, YR - 0.03, 0.73), TaillightR=(0.60, YR - 0.03, 0.73),
        SeatDriver=(-0.40, -0.22, 0.52), SeatPassenger=(0.40, -0.22, 0.52),
        SeatRearL=(-0.40, -1.05, 0.52), SeatRearR=(0.40, -1.05, 0.52),
        ExitL=(-1.80, -0.20, 0.0), ExitR=(1.80, -0.20, 0.0), Exhaust=(0.62, YR - 0.05, 0.28),
        Hood=(0.0, 1.55, 0.97), Trunk=(0.0, -2.00, 1.00),
    )
    for nm, loc in E.items():
        empty(PFX + nm, loc=loc, parent=root, collection=C)
    bpy.context.view_layer.update()
    return root, car


l0_root, l0_car = l0_build_muscle()
l0_info = stats(l0_root)
