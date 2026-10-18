"""lane2_motorcycle.py - builds vehicles/motorcycle (lane 2, index 0). 2.15 x 0.85 x 1.25, WB 1.45, wheel r 0.31. Idempotent, no export.
Sporty naked bike with belly pan: tank, stepped seat, tail unit, twin shorty exhausts, fat rear tyre.
Fork = steering assembly (bars, grips, mirrors, fork legs, headlight + flyscreen, front fender); origin at the steering head."""


def l2_build_motorcycle():
    A = L2Asset("motorcycle", 0, collection="GTA_GODOT/Vehicles/Motorcycles", paint="#d93a3a", paint2="#e6e2d6")
    R, WB = 0.31, 1.45
    YF, YR = WB / 2, -WB / 2
    rake = math.radians(25)
    U = Vector((0, -math.sin(rake), math.cos(rake)))
    N = Vector((0, math.cos(rake), math.sin(rake)))
    Xv = Vector((1, 0, 0))

    def P(t, dx=0.0):
        return Vector((dx, YF, R)) + U * t

    # ---------------------------------------------------------------- FORK (steering assembly)
    FO = P(0.64)
    f = MB("fork")
    for sx in (-1, 1):
        f.beam(P(0.02, sx * 0.108), P(0.30, sx * 0.108), 0.024, 0.024, 6, "Metal")
        f.beam(P(0.30, sx * 0.108), P(0.66, sx * 0.108), 0.019, 0.019, 6, "Chrome")
        f.cyl((sx * 0.118, YF, R), 0.032, 0.05, 6, "Metal", axis="X")
        l2_obox(f, P(0.14, sx * 0.108) + N * 0.045, (1, 0, 0), tuple(N), tuple(U), 0.016, 0.03, 0.05, "Trim")   # brake caliper
        # handlebar (swept back) + grips + lever + mirror
        g_in = P(0.74, sx * 0.07)
        g_out = Vector((sx * 0.35, 0.385, 1.01))
        f.beam(g_in, g_out, 0.0115, 0.0115, 6, "Metal")
        f.cyl((sx * 0.31, 0.389, 1.008), 0.018, 0.105, 6, "Trim", axis="X")
        f.beam((sx * 0.28, 0.405, 1.012), (sx * 0.32, 0.545, 0.985), 0.006, 0.005, 4, "Metal")
        f.beam((sx * 0.325, 0.41, 1.025), (sx * 0.372, 0.385, 1.165), 0.007, 0.007, 4, "Metal")
        mc = Vector((sx * 0.378, 0.375, 1.19))
        l2_obox(f, mc, (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.046, 0.013, 0.036, "Paint2", taper=(0.9, 0.9))
        l2_obox(f, mc + Vector((0, -0.014, 0)), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.038, 0.004, 0.028, "Chrome")
    # yokes
    l2_obox(f, P(0.64), (1, 0, 0), tuple(N), tuple(U), 0.13, 0.04, 0.02, "MetalDark")
    l2_obox(f, P(0.50), (1, 0, 0), tuple(N), tuple(U), 0.13, 0.035, 0.018, "MetalDark")
    f.beam(P(0.50), P(0.66), 0.03, 0.03, 6, "MetalDark")
    # headlight: housing, lens, cowl, flyscreen
    ch = P(0.70) + N * 0.075
    l2_obox(f, ch, (1, 0, 0), tuple(N), tuple(U), 0.125, 0.05, 0.085, "Trim", taper=(0.82, 0.88))
    l2_obox(f, ch + N * 0.053, (1, 0, 0), tuple(N), tuple(U), 0.108, 0.011, 0.066, "LightHead")
    l2_obox(f, ch + U * 0.102 + N * 0.02, (1, 0, 0), tuple(N), tuple(U), 0.12, 0.046, 0.022, "Paint2", taper=(0.7, 1.0))
    sn = Vector((0, 0.80, 0.60)).normalized()
    su = Vector((0, -0.60, 0.80)).normalized()
    cs = ch + U * 0.20 + N * 0.0
    l2_obox(f, cs, (1, 0, 0), tuple(sn), tuple(su), 0.10, 0.006, 0.085, "Glass", taper=(0.85, 0.7))
    l2_obox(f, P(0.74) + Vector((0, 0.0, 0.0)) + U * 0.06 - N * 0.02, (1, 0, 0), tuple(N), tuple(U), 0.06, 0.03, 0.03, "Trim")   # dash
    # front fender: arc over the front wheel
    rings = []
    th0, th1, nst = math.radians(-22), math.radians(72), 8
    for i in range(nst + 1):
        th = th0 + (th1 - th0) * i / nst
        pr = []
        for (xx, rr) in ((-0.075, 0.356), (0.075, 0.356), (0.075, 0.332), (-0.075, 0.332)):
            pr.append((xx, YF + rr * math.sin(th), R + rr * math.cos(th)))
        rings.append(pr)
    l2_loft(f, rings, "Paint2", "Paint2", "Paint2")
    f.translate(-FO)
    A.mesh(f, "Fork", loc=tuple(FO))

    # ---------------------------------------------------------------- BODY
    b = MB("body")
    # frame
    b.beam(P(0.46), P(0.76), 0.036, 0.036, 6, "MetalDark")
    for sx in (-1, 1):
        b.beam((sx * 0.10, 0.43, 0.90), (sx * 0.125, -0.06, 0.83), 0.024, 0.024, 5, "MetalDark")
        b.beam((sx * 0.125, -0.06, 0.83), (sx * 0.125, -0.40, 0.58), 0.024, 0.024, 5, "MetalDark")
        b.beam((sx * 0.10, -0.06, 0.80), (sx * 0.075, -0.66, 0.78), 0.017, 0.017, 5, "MetalDark")
        b.beam((sx * 0.125, -0.40, 0.55), (sx * 0.12, 0.02, 0.36), 0.02, 0.02, 5, "MetalDark")
        # pivot plate, swingarm, axle, footpeg
        l2_box(b, sx * 0.135 - 0.011, sx * 0.135 + 0.011, -0.47, -0.33, 0.36, 0.64, "MetalDark")
        b.beam((sx * 0.125, -0.40, 0.47), (sx * 0.125, YR, R), 0.027, 0.022, 5, "Metal")
        b.cyl((sx * 0.14, YR, R), 0.032, 0.05, 6, "Metal", axis="X")
        b.beam((sx * 0.145, -0.13, 0.37), (sx * 0.27, -0.13, 0.37), 0.013, 0.013, 5, "Metal")
        b.beam((sx * 0.16, -0.16, 0.37), (sx * 0.16, -0.16, 0.50), 0.012, 0.012, 4, "Metal")
        # engine side covers
        b.cyl((sx * 0.155, -0.27, 0.44), 0.07, 0.035, 8, "Metal", axis="X")
        b.cyl((sx * 0.15, -0.14, 0.40), 0.05, 0.03, 8, "MetalDark", axis="X")
    # engine
    b.block((0, -0.12), 0.29, 0.56, (0.26, 0.54), (0.24, 0.48), "Metal")
    b.block((0, 0.10), 0.54, 0.80, (0.24, 0.26), (0.24, 0.24), "Metal", top_shift=(0.05, 0))
    for k, z in enumerate((0.62, 0.69, 0.76)):
        b.block((0, 0.145 + 0.006 * k), z, z + 0.014, (0.30, 0.34), None, "Metal", top_shift=(0, 0))
    b.block((0, -0.10), 0.22, 0.30, (0.22, 0.34), (0.20, 0.30), "MetalDark")
    l2_obox(b, (0, 0.285, 0.56), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.105, 0.025, 0.13, "Trim")           # radiator
    for k in range(3):
        l2_box(b, -0.09, 0.09, 0.309, 0.316, 0.48 + k * 0.07, 0.495 + k * 0.07, "Chrome")
    # belly pan (lower fairing)
    l2_tube(b, [dict(y=0.34, hw=0.095, zb=0.30, zt=0.47, c=0.04), dict(y=0.16, hw=0.168, zb=0.265, zt=0.54, c=0.05),
                dict(y=-0.14, hw=0.168, zb=0.265, zt=0.54, c=0.05), dict(y=-0.40, hw=0.13, zb=0.33, zt=0.52, c=0.04)],
            side="Paint2", top="Paint2", bot="Paint2", cap0="Paint2", cap1="Paint2")
    # tank
    l2_tube(b, [dict(y=0.41, hw=0.075, zb=0.89, zt=0.99, c=0.04, cb=0.05), dict(y=0.30, hw=0.122, zb=0.84, zt=1.035, c=0.05, cb=0.07),
                dict(y=0.12, hw=0.150, zb=0.80, zt=1.06, c=0.06, cb=0.09), dict(y=-0.06, hw=0.142, zb=0.78, zt=1.04, c=0.06, cb=0.09),
                dict(y=-0.20, hw=0.112, zb=0.77, zt=0.985, c=0.05, cb=0.07)],
            side="Paint", top="Paint", bot="Trim", cap0="Paint", cap1="Trim")
    for sx in (-1, 1):
        l2_tube(b, [dict(y=-0.10, hw=0.012, zb=0.58, zt=0.74, xc=sx * 0.125, c=0.006), dict(y=-0.40, hw=0.012, zb=0.60, zt=0.78, xc=sx * 0.125, c=0.006),
                    dict(y=-0.62, hw=0.012, zb=0.64, zt=0.80, xc=sx * 0.105, c=0.006)], side="Paint", top="Paint", bot="Paint", cap0="Paint", cap1="Paint")
    # rider seat + tail unit
    l2_tube(b, [dict(y=-0.02, hw=0.100, zb=0.72, zt=0.80, c=0.03), dict(y=-0.28, hw=0.128, zb=0.71, zt=0.83, c=0.04),
                dict(y=-0.54, hw=0.118, zb=0.72, zt=0.85, c=0.04)], side="Trim", top="Interior", bot="Trim", cap0="Trim", cap1="Trim")
    l2_tube(b, [dict(y=-0.50, hw=0.112, zb=0.70, zt=0.86, c=0.04), dict(y=-0.72, hw=0.100, zb=0.72, zt=0.935, c=0.04),
                dict(y=-0.95, hw=0.075, zb=0.78, zt=0.965, c=0.03), dict(y=-1.05, hw=0.058, zb=0.80, zt=0.955, c=0.02)],
            side="Paint", top="Paint", bot="Paint2", cap0="Paint2", cap1="Paint2")
    l2_box(b, -0.075, 0.075, -1.066, -1.05, 0.875, 0.925, "LightTail")
    for sx in (-1, 1):
        l2_box(b, sx * 0.055 - 0.02, sx * 0.055 + 0.02, -1.058, -1.04, 0.83, 0.855, "LightAmber")
    b.beam((0, -0.80, 0.70), (0, -1.03, 0.69), 0.014, 0.014, 4, "MetalDark")
    l2_box(b, -0.095, 0.095, -1.083, -1.07, 0.66, 0.77, "Plate")
    # rear hugger over the rear wheel
    rings = []
    th0, th1 = math.radians(-70), math.radians(8)
    for i in range(7):
        th = th0 + (th1 - th0) * i / 6
        pr = []
        for (xx, rr) in ((-0.105, 0.352), (0.105, 0.352), (0.105, 0.334), (-0.105, 0.334)):
            pr.append((xx, YR + rr * math.sin(th), R + rr * math.cos(th)))
        rings.append(pr)
    l2_loft(b, rings, "Paint2", "Paint2", "Paint2")
    # rear shock + spring
    b.beam((0, -0.29, 0.80), (0, -0.52, 0.47), 0.014, 0.014, 5, "Metal")
    b.beam((0, -0.31, 0.77), (0, -0.46, 0.57), 0.028, 0.028, 6, "Paint")
    # chain + sprockets
    b.cyl((-0.108, YR, R), 0.085, 0.012, 8, "Metal", axis="X")
    b.cyl((-0.145, -0.40, 0.40), 0.04, 0.012, 8, "Metal", axis="X")
    b.beam((-0.108, YR + 0.01, R + 0.085), (-0.145, -0.40, 0.44), 0.005, 0.005, 3, "MetalDark")
    b.beam((-0.108, YR + 0.01, R - 0.085), (-0.145, -0.40, 0.36), 0.005, 0.005, 3, "MetalDark")
    # exhaust: 4 headers -> collector -> belly pipe -> twin shorty cans
    for xi in (-0.075, -0.025, 0.025, 0.075):
        b.beam((xi, 0.21, 0.62), (xi, 0.235, 0.46), 0.014, 0.014, 5, "Chrome")
        b.beam((xi, 0.235, 0.46), (xi * 0.3, 0.12, 0.29), 0.014, 0.014, 5, "Chrome")
    b.beam((0, 0.12, 0.28), (0, -0.20, 0.265), 0.04, 0.04, 6, "Chrome")
    for sx in (-1, 1):
        b.beam((0, -0.20, 0.265), (sx * 0.17, -0.48, 0.34), 0.034, 0.034, 6, "Chrome")
        b.beam((sx * 0.17, -0.44, 0.36), (sx * 0.19, -0.99, 0.54), 0.056, 0.05, 8, "Chrome")
        b.cyl((sx * 0.19, -1.0, 0.545), 0.042, 0.03, 8, "Trim", axis="Y")
        b.beam((sx * 0.176, -0.62, 0.43), (sx * 0.178, -0.66, 0.435), 0.064, 0.064, 8, "MetalDark")   # band

    body = A.mesh(b, "Body")
    l2_island_report(body)

    # ---------------------------------------------------------------- wheels
    wf = l2_wheel(A.prefix + "Wheel_F", R, 0.13, 1, A.coll, seg=12, style="moto", loc=(0, YF, R))
    wr = l2_wheel(A.prefix + "Wheel_R", R, 0.20, 1, A.coll, seg=12, style="moto", loc=(0, YR, R))
    parent_to(wf, A.root)
    parent_to(wr, A.root)
    A.objs["Wheel_F"], A.objs["Wheel_R"] = wf, wr

    # ---------------------------------------------------------------- anchors
    A.node("HeadlightF", tuple(ch + N * 0.06))
    A.node("TaillightR", (0, -1.07, 0.90))
    A.node("SeatDriver", (0, -0.27, 0.925))
    A.node("SeatPassenger", (0, -0.70, 0.95))
    A.node("ExitL", (-1.0, 0.0, 0.0), display="ARROWS", size=0.2)
    A.node("ExitR", (1.0, 0.0, 0.0), display="ARROWS", size=0.2)
    A.node("Exhaust", (0.19, -1.02, 0.545))
    A.mats()
    bpy.context.view_layer.update()
    return A


l2_A = l2_build_motorcycle()
l2_info = stats(l2_A.root)
print("tris:", l2_tris(l2_A.root))
