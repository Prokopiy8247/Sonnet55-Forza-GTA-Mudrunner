"""lane2_bicycle.py - builds vehicles/bicycle (lane 2, index 1). 1.75 x 0.62 x 1.10, wheel r 0.34, wheelbase 1.05. Idempotent, no export.
City cruiser: diamond frame, swept-back bars, saddle, rear rack, fenders, chain guard, dynamo lamp.
Fork = front fork + stem + handlebar + lamp + front fender (origin at the head tube top). Pedals = cranks + chainring + pedals (origin at the bottom bracket)."""


def l2_build_bicycle():
    A = L2Asset("bicycle", 1, collection="GTA_GODOT/Vehicles/Motorcycles", paint="#2f9c95", paint2="#e6e2d6")
    R, WB = 0.34, 1.05
    YF, YR = WB / 2, -WB / 2
    rake = math.radians(18)
    U = Vector((0, -math.sin(rake), math.cos(rake)))
    N = Vector((0, math.cos(rake), math.sin(rake)))

    def P(t, dx=0.0):
        return Vector((dx, YF, R)) + U * t

    BB = Vector((0, -0.08, 0.29))
    HT_TOP, HT_BOT = P(0.62), P(0.46)
    SEAT_TOP = Vector((0, -0.225, 0.86))

    # ---------------------------------------------------------------- FORK
    FO = HT_TOP
    f = MB("fork")
    for sx in (-1, 1):
        f.beam(P(0.0, sx * 0.045), P(0.50, sx * 0.045), 0.0145, 0.016, 6, "Paint2")
        f.cyl((sx * 0.05, YF, R), 0.02, 0.04, 6, "Metal", axis="X")
        # swept-back handlebar
        p1 = Vector((sx * 0.18, 0.285, 1.04))
        p2 = Vector((sx * 0.265, 0.215, 1.05))
        p3 = Vector((sx * 0.285, 0.115, 1.05))
        f.beam((sx * 0.0, 0.30, 1.035), p1, 0.0105, 0.0105, 6, "Chrome")
        f.beam(p1, p2, 0.0105, 0.0105, 6, "Chrome")
        f.beam(p2 + Vector((0, -0.01, 0)), p3, 0.021, 0.021, 6, "Trim")
        f.beam(p2, p2 + Vector((sx * -0.02, 0.10, -0.012)), 0.005, 0.005, 4, "Metal")           # brake lever
    f.beam(P(0.50, -0.045), P(0.50, 0.045), 0.016, 0.016, 6, "Paint2")                          # crown
    f.beam(P(0.45), P(0.70), 0.0135, 0.0135, 6, "Chrome")                                         # steerer
    f.beam(Vector((0, 0.322, 0.985)), Vector((0, 0.30, 1.035)), 0.0165, 0.0165, 6, "Chrome")      # stem
    # dynamo lamp on the crown
    lc = P(0.52) + N * 0.075
    f.cyl(tuple(lc), 0.044, 0.07, 8, "Trim", axis="Y")
    f.cyl(tuple(lc + Vector((0, 0.037, 0))), 0.036, 0.012, 8, "LightHead", axis="Y")
    f.beam(P(0.52), lc, 0.008, 0.008, 4, "Metal")
    # front fender
    rings = []
    th0, th1, nst = math.radians(-34), math.radians(70), 7
    for i in range(nst + 1):
        th = th0 + (th1 - th0) * i / nst
        pr = []
        for (xx, rr) in ((-0.038, 0.372), (0.038, 0.372), (0.038, 0.358), (-0.038, 0.358)):
            pr.append((xx, YF + rr * math.sin(th), R + rr * math.cos(th)))
        rings.append(pr)
    l2_loft(f, rings, "Paint2", "Paint2", "Paint2")
    for sx in (-1, 1):
        f.beam((sx * 0.03, YF + 0.372 * math.sin(math.radians(28)), R + 0.372 * math.cos(math.radians(28))), P(0.30, sx * 0.045), 0.006, 0.006, 4, "Metal")
    f.translate(-FO)
    A.mesh(f, "Fork", loc=tuple(FO))

    # ---------------------------------------------------------------- BODY (frame, saddle, rack, fender, chain)
    b = MB("body")
    FR = "Paint"
    b.beam(HT_BOT, HT_TOP + U * 0.04, 0.0235, 0.0235, 6, FR)                                      # head tube
    b.beam(P(0.50) + Vector((0, 0.0, 0.0)), BB, 0.0245, 0.0245, 6, FR)                           # down tube
    b.beam(HT_TOP - U * 0.02 + Vector((0, -0.005, 0)), SEAT_TOP - Vector((0, 0, 0.02)), 0.021, 0.021, 6, FR)   # top tube
    b.beam(BB, SEAT_TOP, 0.021, 0.021, 6, FR)                                                    # seat tube
    b.beam((0, -0.24, 0.89), (0, -0.255, 0.935), 0.0145, 0.0145, 6, "Chrome")                    # seat post
    for sx in (-1, 1):
        b.beam(SEAT_TOP - Vector((0, 0, 0.03)), Vector((sx * 0.055, YR, R)), 0.0125, 0.0125, 5, FR)          # seat stays
        b.beam(BB, Vector((sx * 0.055, YR, R)), 0.0135, 0.0135, 5, FR)                                       # chain stays
        b.cyl((sx * 0.055, YR, R), 0.02, 0.04, 6, "Metal", axis="X")
    b.cyl((0, BB.y, BB.z), 0.03, 0.14, 6, "MetalDark", axis="X")                                # bottom bracket shell
    # saddle (tapered, with rails)
    b.block((0, -0.245), 0.915, 0.965, (0.155, 0.12), (0.09, 0.16), "Trim", top_shift=(0, -0.02))
    b.block((0, -0.32), 0.905, 0.955, (0.15, 0.14), (0.15, 0.14), "Interior", top_shift=(0, 0))
    b.beam((0, -0.22, 0.915), (0, -0.30, 0.912), 0.01, 0.01, 4, "Metal")
    # rear fender (arc) + tail light + rack
    rings = []
    th0, th1, nst = math.radians(-96), math.radians(48), 8
    for i in range(nst + 1):
        th = th0 + (th1 - th0) * i / nst
        pr = []
        for (xx, rr) in ((-0.04, 0.373), (0.04, 0.373), (0.04, 0.359), (-0.04, 0.359)):
            pr.append((xx, YR + rr * math.sin(th), R + rr * math.cos(th)))
        rings.append(pr)
    l2_loft(b, rings, "Paint2", "Paint2", "Paint2")
    l2_box(b, -0.035, 0.035, -0.89, -0.875, 0.50, 0.545, "LightTail")
    l2_box(b, -0.075, 0.075, -0.875, -0.43, 0.745, 0.76, "Metal")                                 # rack deck
    for sx in (-1, 1):
        b.beam((sx * 0.07, -0.45, 0.752), (sx * 0.055, YR, R), 0.005, 0.005, 4, "Metal")
        b.beam((sx * 0.07, -0.86, 0.752), (sx * 0.06, -0.80, 0.55), 0.005, 0.005, 4, "Metal")
    b.beam((0, -0.43, 0.752), (0, -0.40, 0.84), 0.006, 0.006, 4, "Metal")
    # chain (right side), cog, chain guard
    b.cyl((0.062, YR, R), 0.036, 0.012, 8, "Metal", axis="X")
    b.beam((0.062, BB.y - 0.005, BB.z + 0.082), (0.062, YR + 0.005, R + 0.034), 0.004, 0.004, 3, "MetalDark")
    b.beam((0.062, BB.y - 0.005, BB.z - 0.082), (0.062, YR + 0.005, R - 0.034), 0.004, 0.004, 3, "MetalDark")
    l2_flat_slab(b, [(YR + 0.04, R + 0.03), (BB.y - 0.04, BB.z + 0.075), (BB.y - 0.04, BB.z + 0.105), (YR + 0.04, R + 0.062)], 0.086, 1, 0.005, 0.0, "Paint2")
    # kickstand
    b.beam((0.0, -0.33, 0.25), (0.0, -0.41, 0.0), 0.007, 0.007, 4, "Metal")
    # bell on the bar clamp
    b.cyl((0, 0.30, 1.07), 0.022, 0.026, 6, "Chrome", axis="Z")

    body = A.mesh(b, "Body")
    l2_island_report(body)

    # ---------------------------------------------------------------- PEDALS (origin at the crank)
    pm = MB("pedals")
    pm.cyl((0.062, 0, 0), 0.085, 0.01, 10, "Metal", axis="X")
    pm.cyl((0.062, 0, 0), 0.03, 0.014, 6, "MetalDark", axis="X")
    pm.beam((0.075, 0, 0), (0.075, 0, -0.17), 0.012, 0.012, 5, "Metal")
    pm.beam((-0.075, 0, 0), (-0.075, 0, 0.17), 0.012, 0.012, 5, "Metal")
    pm.beam((0.075, 0, -0.17), (0.12, 0, -0.17), 0.007, 0.007, 4, "Metal")
    pm.beam((-0.075, 0, 0.17), (-0.12, 0, 0.17), 0.007, 0.007, 4, "Metal")
    pm.box((0.14, 0, -0.17), (0.095, 0.06, 0.016), "Trim")
    pm.box((-0.14, 0, 0.17), (0.095, 0.06, 0.016), "Trim")
    A.mesh(pm, "Pedals", loc=tuple(BB))

    # ---------------------------------------------------------------- wheels
    wf = l2_wheel(A.prefix + "Wheel_F", R, 0.05, 1, A.coll, seg=16, style="bike", loc=(0, YF, R))
    wr = l2_wheel(A.prefix + "Wheel_R", R, 0.05, 1, A.coll, seg=16, style="bike", loc=(0, YR, R))
    parent_to(wf, A.root)
    parent_to(wr, A.root)
    A.objs["Wheel_F"], A.objs["Wheel_R"] = wf, wr

    A.node("SeatDriver", (0, -0.25, 1.04))
    A.node("HeadlightF", tuple(P(0.52) + N * 0.11))
    A.node("TaillightR", (0, -0.89, 0.52))
    A.node("ExitL", (-0.9, 0.0, 0.0), display="ARROWS", size=0.2)
    A.node("ExitR", (0.9, 0.0, 0.0), display="ARROWS", size=0.2)
    A.mats()
    bpy.context.view_layer.update()
    return A


l2_A = l2_build_bicycle()
l2_info = stats(l2_A.root)
print("tris:", l2_tris(l2_A.root))
print("culling:", [(m.name, m.use_backface_culling) for m in bpy.data.materials if m.name in ("Tire", "Rim", "Paint", "Glass")])
