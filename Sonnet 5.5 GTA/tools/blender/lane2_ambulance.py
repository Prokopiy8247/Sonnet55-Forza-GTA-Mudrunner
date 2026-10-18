"""lane2_ambulance.py - builds vehicles/ambulance (lane 2, index 2). 5.80 x 2.15 x 2.65, WB 3.60, wheel r 0.36. Idempotent, no export.
Box-body ambulance: tall patient box (Paint = white) with fixed-colour LiveryRed stripes/star behind a lower cab (Paint2 = dark sill band). SirenBar on the cab roof (SirenBar_L blue / SirenBar_R red).
Seats: driver, passenger, rear bench in the cab. DoorL/DoorR hinged at the front edge of the cab doors."""


def l2_build_ambulance():
    A = L2Asset("ambulance", 2, paint="#f2f0ea", paint2="#2a2d33")
    R, FA, RA = 0.36, 1.80, -1.80
    RAr = 0.445                      # arch radius
    BX, CB = 1.04, 1.00              # box / cab half widths
    BELT, ROOF_C, ROOF_B = 1.36, 2.12, 2.56
    FL = 0.60                        # cab floor
    wheels = [(FA, R, RAr), (RA, R, RAr)]
    b = MB("body")

    # ---------------- patient box (rear) with rear wheel arch
    l2_tube_arch(b, -2.76, 0.30, BX, 0.52, ROOF_B, [(RA, R, RAr)], c=0.07, cb=0.15, side="Paint", top="Paint", bot="Trim", cap0=None, cap1="Paint")
    l2_tube(b, [dict(y=-2.84, hw=1.00, zb=0.60, zt=2.48, c=0.07, cb=0.12), dict(y=-2.76, hw=BX, zb=0.52, zt=ROOF_B, c=0.07, cb=0.15)],
            side="Paint", top="Paint", bot="Trim", cap0="Paint")

    # ---------------- cab: side walls (arch cut), floor, hood tube, greenhouse
    def wall_poly(y0, y1):
        pts = [(y0, 0.52)]
        for y in (1.36, 1.44, 1.52, 1.60, 1.68, 1.74, y1):
            pts.append((y, max(0.52, l2_arch_zb(y, 0.52, [(FA, R, RAr)]))))
        pts += [(y1, BELT), (y0, BELT)]
        return pts
    for s in (-1, 1):
        l2_flat_slab(b, wall_poly(0.30, 1.78), CB - 0.08, s, 0.08, 0.0, "Paint")
    l2_box(b, -CB + 0.08, CB - 0.08, 0.30, 1.78, 0.52, FL, "Interior")
    hood_zt = lambda y: BELT if y <= 1.78 else l2_lerp(BELT, 1.10, (y - 1.78) / 0.84)
    hood_hw = lambda y: CB if y <= 2.40 else l2_lerp(CB, 0.95, (y - 2.40) / 0.22)
    l2_tube_arch(b, 1.78, 2.62, hood_hw, 0.52, hood_zt, [(FA, R, RAr)], extra_ys=(2.40,), c=0.07, cb=0.10,
                 side="Paint", top="Paint", bot="Trim", cap0="Interior", cap1="Paint")
    # greenhouse (glass sides, painted roof) + frames
    A_, B_, C_, D_ = (1.78, BELT), (1.16, ROOF_C), (0.30, ROOF_C), (0.30, BELT)
    GW = 0.955
    l2_shell_yz(b, [A_, B_, C_, D_], GW, ["Glass", "Paint", "Paint", "Interior"], "Glass")
    b.block((0, 0.80), ROOF_C - 0.005, ROOF_C + 0.04, (2 * GW + 0.05, 1.04), (2 * GW + 0.0, 0.96), "Paint")
    l2_wipers(b, A_, B_, 0.10, spans=((-0.62, -0.12), (0.06, 0.56)))
    for s in (-1, 1):
        l2_frame_slab(b, [A_, B_, C_, D_], GW, s, 0.06, 0.014, 0.002, "Trim")
        l2_flat_slab(b, [(0.52, BELT), (0.64, BELT), (0.64, ROOF_C), (0.52, ROOF_C)], GW, s, 0.016, 0.002, "Paint")
    # windscreen frame lines + cowl
    b.beam((-GW, A_[0], A_[1] + 0.01), (GW, A_[0], A_[1] + 0.01), 0.02, 0.02, 4, "Trim")
    b.beam((-GW, B_[0] + 0.01, B_[1] - 0.01), (GW, B_[0] + 0.01, B_[1] - 0.01), 0.02, 0.02, 4, "Trim")
    # interior
    b.block((0, 1.66), FL, 1.12, (1.86, 0.24), (1.86, 0.16), "Interior", top_shift=(0.03, 0))
    b.box((0, 1.60, 1.14), (1.80, 0.07, 0.05), "Trim")
    b.box((0, 1.20, 0.80), (0.28, 0.60, 0.40), "Interior")
    l2_steering_wheel(b, (-0.40, 1.38, 1.18), 36, 0.19, "Trim", "Interior")
    for sx in (-0.40, 0.40):
        l2_seat(b, sx, 0.98, FL, 0.52, 0.52, 0.70, 0.22, "Interior")
        l2_seat(b, sx, 0.46, FL, 0.50, 0.38, 0.62, 0.22, "Interior")
    b.box((0, 0.32, 1.60), (1.8, 0.04, 0.9), "Interior")        # bulkhead behind the cab seats

    # ---------------- box details
    SX = BX + 0.002
    for s in (-1, 1):
        # red belt stripe (box + cab walls), thin lower pin stripe
        l2_flat_slab(b, l2_rect(-2.74, 0.29, 1.06, 1.30), BX, s, 0.012, 0.0, "LiveryRed")
        l2_flat_slab(b, l2_rect(-2.74, 0.29, 0.94, 0.99), BX, s, 0.012, 0.0, "LiveryRed")
        l2_flat_slab(b, [(0.30, 1.08), (0.62, 1.08), (0.62, 1.30), (0.30, 1.30)], CB, s, 0.012, 0.0, "LiveryRed")
        l2_flat_slab(b, [(1.52, 1.08), (1.78, 1.08), (1.78, 1.30), (1.52, 1.30)], CB, s, 0.012, 0.0, "LiveryRed")
        l2_flat_slab(b, l2_rect(-2.74, 0.29, 0.62, 0.80, 0.0), BX, s, 0.012, 0.0, "Paint2")
        # star of life emblem (red)
        l2_star(b, s * (BX + 0.012), -1.30, 1.95, 0.80, "x", "LiveryRed", 0.10)
        # rear lights, indicators
        b.box((s * 0.97, -2.85, 1.30), (0.07, 0.04, 0.62), "LightTail")
        b.box((s * 0.97, -2.85, 0.90), (0.07, 0.04, 0.12), "LightAmber")
        b.box((s * 0.80, -2.865, 0.80), (0.12, 0.03, 0.08), "LightHead")
        # roof corner strobes (flash with the siren)
        b.box((s * 0.88, -2.74, 2.50), (0.26, 0.10, 0.08), "LightBlue" if s < 0 else "LightRed")
        b.box((s * 0.88, 0.22, 2.52), (0.24, 0.08, 0.07), "LightRed" if s < 0 else "LightBlue")
        # upper side marker strip + amber marker
        b.box((s * (BX + 0.004), -2.0, 2.40), (0.01, 0.26, 0.05), "LightAmber")
        b.box((s * (BX + 0.004), -0.35, 2.40), (0.01, 0.26, 0.05), "LightAmber")
        # step under the cab door, bumper side caps
        b.box((s * 1.02, 1.07, 0.44), (0.12, 0.98, 0.04), "MetalDark")
        b.box((s * 1.0, 1.07, 0.42), (0.02, 0.98, 0.03), "Trim")
    # left side: two equipment compartments (seams) + frosted window ; right side: patient entry door
    sxl, sxr = -SX, SX
    for (y0, y1, z0, z1) in ((-2.68, -2.04, 1.00, 2.00), (-1.94, -1.28, 1.00, 2.00), (-1.10, 0.18, 1.00, 2.30)):
        l2_seam_v(b, sxl, y0, z0, z1)
        l2_seam_v(b, sxl, y1, z0, z1)
        l2_seam_h(b, sxl, y0, y1, z0)
        l2_seam_h(b, sxl, y0, y1, z1)
        b.box((sxl - 0.014, y1 - 0.12, (z0 + z1) / 2 + 0.05), (0.03, 0.14, 0.03), "Chrome")
    l2_flat_window(b, [(-1.00, 1.60), (0.02, 1.60), (0.02, 2.14), (-1.00, 2.14)], BX, -1, 0.045)
    l2_seam_v(b, sxr, -1.00, 0.96, 2.30)
    l2_seam_v(b, sxr, -0.05, 0.96, 2.30)
    l2_seam_h(b, sxr, -1.00, -0.05, 0.96)
    l2_seam_h(b, sxr, -1.00, -0.05, 2.30)
    l2_seam_h(b, sxr, -2.62, -1.20, 1.50)
    l2_seam_v(b, sxr, -2.62, 1.00, 2.00)
    l2_seam_v(b, sxr, -1.20, 1.00, 2.00)
    l2_seam_h(b, sxr, -2.62, -1.20, 2.00)
    l2_seam_h(b, sxr, -2.62, -1.20, 1.00)
    b.box((sxr + 0.014, -0.16, 1.52), (0.03, 0.14, 0.03), "Chrome")
    b.box((sxr + 0.014, -1.34, 1.50), (0.03, 0.14, 0.03), "Chrome")
    l2_flat_window(b, [(-0.86, 1.62), (-0.18, 1.62), (-0.18, 2.16), (-0.86, 2.16)], BX, 1, 0.045)
    # rear doors: seam outline, windows, handles, plate, bumper
    YR_ = -2.846
    b.box((0, YR_, 1.58), (0.012, 0.01, 1.74), "Trim")
    for z in (0.72, 2.45):
        b.box((0, YR_, z), (1.96, 0.01, 0.012), "Trim")
    for sx in (-1, 1):
        b.box((sx * 0.98, YR_, 1.58), (0.012, 0.01, 1.74), "Trim")
        b.box((sx * 0.50, -2.848, 1.80), (0.62, 0.014, 0.56), "Trim")
        b.box((sx * 0.50, -2.853, 1.80), (0.52, 0.010, 0.46), "Glass")
        b.box((sx * 0.07, -2.860, 1.62), (0.04, 0.04, 0.26), "Chrome")
        for z in (0.95, 2.20):
            b.box((sx * 0.96, -2.848, z), (0.05, 0.02, 0.10), "Chrome")
    b.box((0, -2.850, 1.18), (1.96, 0.012, 0.24), "LiveryRed")
    b.box((0, -2.850, 0.99), (1.96, 0.012, 0.05), "LiveryRed")
    b.box((0, -2.862, 0.93), (0.46, 0.014, 0.22), "Plate")
    l2_cbox(b, -2.90, -2.78, 1.0, 0.36, 0.66, c=0.04, side="Trim", top="Trim", bot="Trim", cap0="Trim", cap1="Trim")
    b.box((0, -2.85, 0.665), (1.6, 0.10, 0.02), "MetalDark")
    # roof gear (box roof): AC unit, vent hatch, aerial
    b.block((0, -1.65), ROOF_B - 0.01, ROOF_B + 0.075, (0.86, 1.00), (0.70, 0.86), "Trim")
    b.block((0, -0.40), ROOF_B - 0.01, ROOF_B + 0.05, (0.60, 0.60), (0.52, 0.52), "MetalDark")
    b.beam((0.85, -0.2, ROOF_B), (0.88, -0.28, ROOF_B + 0.09), 0.012, 0.007, 4, "Trim")

    # ---------------- front end
    b.prism([(-0.98, 2.52), (0.98, 2.52), (1.02, 2.64), (1.0, 2.82), (0.9, 2.90), (-0.9, 2.90), (-1.0, 2.82), (-1.02, 2.64)], 0.34, 0.74, "Trim")
    b.box((0, 2.915, 0.58), (0.60, 0.014, 0.24), "Plate")
    b.box((0, 2.90, 0.72), (1.84, 0.03, 0.04), "Chrome")
    b.box((0, 2.625, 0.935), (0.92, 0.03, 0.32), "Trim")
    for k in range(3):
        b.box((0, 2.64, 0.84 + k * 0.10), (0.88, 0.02, 0.022), "Chrome")
    b.box((0, 2.628, 1.12), (1.96, 0.02, 0.07), "LiveryRed")
    for s in (-1, 1):
        b.box((s * 0.74, 2.62, 0.95), (0.34, 0.05, 0.19), "Trim")
        b.box((s * 0.74, 2.645, 0.95), (0.29, 0.03, 0.14), "LightHead")
        b.box((s * 0.88, 2.58, 0.76), (0.14, 0.06, 0.08), "LightAmber")
        b.box((s * 0.45, 2.64, 0.80), (0.10, 0.03, 0.05), "LightBlue" if s < 0 else "LightRed")   # grille strobes
    # hood seams
    for s in (-1, 1):
        b.beam((s * 0.62, 1.86, 1.355), (s * 0.60, 2.30, 1.19), 0.007, 0.007, 4, "Trim")
    # underbody (chassis shadow), exhaust
    b.block((0, -0.45), 0.18, 0.54, (1.60, 4.10), (1.60, 4.10), "Trim")
    b.beam((0.72, 0.9, 0.30), (0.72, -2.80, 0.34), 0.045, 0.045, 6, "MetalDark")
    # mirrors on stalks (static copies stay on the doors)
    body = A.mesh(b, "Body")
    l2_island_report(body)

    # ---------------- doors (hinge at front edge, hinge axis vertical)
    YH = 1.52
    Z0 = 0.74
    for s, nm in ((-1, "DoorL"), (1, "DoorR")):
        dm = MB("door")
        l2_flat_slab(dm, l2_rect(0.62, YH, Z0, BELT - 0.005, 0.03), CB, s, 0.035, -0.018, "Paint")
        l2_flat_slab(dm, [(0.66, 1.08), (YH - 0.02, 1.08), (YH - 0.02, 1.30), (0.66, 1.30)], CB, s, 0.012, 0.0 + 0.017, "LiveryRed")
        l2_frame_slab(dm, [(0.64, BELT + 0.01), (YH, BELT + 0.01), (YH, 1.68), (1.20, 2.07), (0.64, 2.07)], GW, s, 0.055, 0.016, 0.004, "Trim")
        dm.box((s * (CB + 0.034), 0.78, 1.22), (0.03, 0.17, 0.03), "Chrome")
        l2_mirror(dm, s, 1.02, 1.60, 1.78)
        dm.translate((-s * CB, -YH, -Z0))
        A.mesh(dm, nm, loc=(s * CB, YH, Z0))

    # ---------------- siren bar (cab roof) + L/R light meshes
    sm = MB("siren")
    sm.box((0, 0, 0.012), (1.30, 0.34, 0.024), "Trim")
    sm.block((0, 0), 0.0, 0.05, (1.34, 0.38), (1.30, 0.34), "Trim")
    sm.box((0, 0, 0.17), (0.04, 0.30, 0.07), "Trim")
    sm.box((-0.66, 0, 0.11), (0.04, 0.34, 0.12), "Trim")
    sm.box((0.66, 0, 0.11), (0.04, 0.34, 0.12), "Trim")
    sm.block((0, 0.0), 0.172, 0.20, (1.28, 0.30), (1.20, 0.22), "Chrome")
    sm.box((0, 0.172, 0.10), (1.24, 0.012, 0.10), "Glass")
    sm.box((0, -0.172, 0.10), (1.24, 0.012, 0.10), "Glass")
    bar = A.mesh(sm, "SirenBar", loc=(0, 0.80, ROOF_C + 0.04))
    for sn, sx, mt in (("SirenBar_L", -1, "LightBlue"), ("SirenBar_R", 1, "LightRed")):
        lm = MB("sirenl")
        lm.box((sx * 0.30, 0, 0.10), (0.52, 0.28, 0.10), mt)
        lm.box((sx * 0.30, 0, 0.17), (0.40, 0.20, 0.04), mt)
        A.mesh(lm, sn, parent=bar)

    # ---------------- wheels
    xw = 0.885
    for nm, sx, y in (("FL", -1, FA), ("FR", 1, FA), ("RL", -1, RA), ("RR", 1, RA)):
        o = l2_wheel(A.prefix + "Wheel_" + nm, R, 0.26, sx, A.coll, seg=12, style="truck", loc=(sx * xw, y, R))
        parent_to(o, A.root)
        A.objs["Wheel_" + nm] = o

    # ---------------- anchors
    SZ = FL + 0.37
    A.node("HeadlightL", (-0.74, 2.66, 0.95))
    A.node("HeadlightR", (0.74, 2.66, 0.95))
    A.node("TaillightL", (-0.97, -2.87, 1.30))
    A.node("TaillightR", (0.97, -2.87, 1.30))
    A.node("SeatDriver", (-0.40, 0.98, SZ))
    A.node("SeatPassenger", (0.40, 0.98, SZ))
    A.node("SeatRearL", (-0.40, 0.46, SZ))
    A.node("SeatRearR", (0.40, 0.46, SZ))
    A.node("ExitL", (-1.95, 1.07, 0.0), display="ARROWS", size=0.2)
    A.node("ExitR", (1.95, 1.07, 0.0), display="ARROWS", size=0.2)
    A.node("Exhaust", (0.72, -2.84, 0.34))
    A.mats()
    bpy.context.view_layer.update()
    return A


l2_A = l2_build_ambulance()
l2_info = stats(l2_A.root)
print("tris:", l2_tris(l2_A.root))
