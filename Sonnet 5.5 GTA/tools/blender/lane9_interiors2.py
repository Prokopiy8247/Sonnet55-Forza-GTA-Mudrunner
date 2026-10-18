"""lane 9 - interiors batch 2: tv_stand_tv, table_round, chair, kitchen_unit, barber_chair, mirror_wall, scuba_rack,
repair_lift, tool_chest, neon_sign_blank.  Requires gta_lib.py + lane9_lib.py + lane9_interiors1.py (ni())."""


# ------------------------------------------------------------------------------------------------ tv stand + tv
def b_tv_stand_tv():
    a = ni("tv_stand_tv", 60)
    b = a.mb()
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.block((sx * 0.68, sy * 0.16), 0.0, 0.12, (0.05, 0.05), (0.04, 0.04), "MetalDark")
    bx(b, (-0.75, 0.75), (-0.22, 0.22), (0.12, 0.46), "WoodDark")
    bx(b, (-0.78, 0.78), (-0.24, 0.25), (0.46, 0.5), "WoodLight")
    for sx in (-1, 1):
        cx = sx * 0.37
        bx(b, (cx - 0.34, cx + 0.34), (0.22, 0.235), (0.15, 0.43), "WoodLight")
        bx(b, (sx * 0.04 - 0.01, sx * 0.04 + 0.01), (0.235, 0.255), (0.26, 0.36), "Brass")
    bx(b, (-0.2, 0.2), (-0.1, 0.1), (0.5, 0.515), "MetalDark")                                       # TV foot
    bx(b, (-0.04, 0.04), (-0.03, 0.03), (0.515, 0.62), "MetalDark")                                   # neck
    bx(b, (-0.6, 0.6), (-0.035, 0.035), (0.6, 1.27), "Trim")                                          # panel
    bx(b, (-0.57, 0.57), (0.035, 0.042), (0.63, 1.24), "NeonScreen")
    bx(b, (-0.03, 0.03), (0.035, 0.045), (0.605, 0.62), "NeonCyan")                                  # standby light
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ round table
def b_table_round():
    a = ni("table_round", 61)
    b = a.mb()
    cylz(b, 0, 0, 0.71, 0.75, 0.56, 12, "WoodLight")
    cylz(b, 0, 0, 0.66, 0.71, 0.4, 12, "WoodDark", r1=0.5, caps=False)
    cylz(b, 0, 0, 0.1, 0.7, 0.07, 8, "WoodDark")
    cylz(b, 0, 0, 0.0, 0.1, 0.33, 8, "MetalDark", r1=0.2, rot=22.5)
    cylz(b, 0.0, 0.0, 0.75, 0.85, 0.05, 6, "Glass", r1=0.07)                                         # vase
    for dx, dy, h in ((0.0, 0.0, 0.2), (0.03, 0.02, 0.15), (-0.03, 0.01, 0.17)):
        b.beam((0, 0, 0.8), (dx, dy, 0.75 + h + 0.1), 0.006, 0.006, 4, "Leaf", False)
        bx(b, (dx - 0.025, dx + 0.025), (dy - 0.025, dy + 0.025), (0.75 + h + 0.1, 0.75 + h + 0.15), "FabricCoral")
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ chair
def b_chair():
    a = ni("chair", 62)
    b = a.mb()
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 0.19, sy * 0.19
            b.block((x, y), 0.0, 0.44, (0.045, 0.045), (0.035, 0.035), "WoodDark")
    for sx in (-1, 1):                                                                             # rear posts up to the back
        bx(b, (sx * 0.19 - 0.02, sx * 0.19 + 0.02), (-0.21, -0.17), (0.44, 0.92), "WoodDark")
    bx(b, (-0.23, 0.23), (-0.22, -0.16), (0.82, 0.92), "WoodDark")                                   # top rail
    bx(b, (-0.17, 0.17), (-0.2, -0.18), (0.58, 0.64), "WoodLight")                                   # slats
    bx(b, (-0.17, 0.17), (-0.2, -0.18), (0.68, 0.74), "WoodLight")
    cbox(b, (-0.23, 0.23), (-0.22, 0.24), (0.44, 0.49), 0.03, "WoodLight")                            # seat board
    cbox(b, (-0.2, 0.2), (-0.19, 0.21), (0.49, 0.53), 0.03, "FabricCoral")                            # cushion
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ kitchen
def b_kitchen_unit():
    a = ni("kitchen_unit", 63)
    b = a.mb()
    bx(b, (-0.9, 0.9), (-0.31, 0.31), (0.0, 0.88), "Laminate")
    bx(b, (-0.93, 0.93), (-0.33, 0.34), (0.88, 0.92), "CounterTop")
    D = "WoodPale"
    for x0, x1 in ((-0.89, -0.61), (-0.59, -0.31), (0.31, 0.59), (0.61, 0.89)):                     # 4 base doors
        bx(b, (x0, x1), (0.31, 0.325), (0.1, 0.84), D)
    bx(b, (-0.28, 0.28), (0.31, 0.325), (0.1, 0.84), "Metal")                                        # oven front
    bx(b, (-0.2, 0.2), (0.325, 0.33), (0.2, 0.58), "Trim")                                            # oven window
    b.beam((-0.22, 0.36, 0.68), (0.22, 0.36, 0.68), 0.012, 0.012, 4, "Chrome", False)
    bx(b, (-0.27, 0.27), (-0.26, 0.26), (0.92, 0.925), "Trim")                                       # hob plate
    for dx, dy in ((-0.13, -0.1), (0.13, -0.1), (-0.13, 0.12), (0.13, 0.12)):
        bx(b, (dx - 0.07, dx + 0.07), (dy - 0.07, dy + 0.07), (0.925, 0.94), "MetalDark")
    bx(b, (0.35, 0.85), (-0.22, 0.2), (0.92, 0.93), "Metal")                                          # sink
    cylz(b, 0.6, 0.0, 0.92, 0.935, 0.06, 6, "Trim")
    cylz(b, 0.6, -0.24, 0.93, 1.0, 0.02, 6, "Chrome")
    b.beam((0.6, -0.24, 1.0), (0.6, -0.09, 1.0), 0.014, 0.014, 4, "Chrome", False)
    bx(b, (-0.93, 0.93), (-0.345, -0.31), (0.92, 2.2), "Laminate")                                   # back wall strip
    bx(b, (-0.9, -0.1), (-0.31, 0.04), (1.5, 2.15), D)                                                # wall cabinet
    bx(b, (-0.505, -0.495), (0.04, 0.05), (1.5, 2.15), "Trim")
    for x in (-0.54, -0.46):
        bx(b, (x - 0.008, x + 0.008), (0.04, 0.06), (1.55, 1.7), "Chrome")
    b.block((0, -0.13), 1.55, 1.8, (0.6, 0.36), (0.22, 0.2), "Metal")                                 # hood
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ barber chair
def b_barber_chair():
    a = ni("barber_chair", 64)
    b = a.mb()
    L = "LeatherRed"
    cylz(b, 0, 0, 0.0, 0.08, 0.38, 8, "MetalDark", r1=0.3, rot=22.5)
    cylz(b, 0, 0, 0.08, 0.2, 0.2, 8, "PoleGrey", r1=0.1, rot=22.5)
    cylz(b, 0, 0, 0.2, 0.5, 0.09, 8, "PoleGrey", rot=22.5)
    bx(b, (-0.16, 0.16), (-0.08, 0.3), (0.5, 0.56), "MetalDark")                                       # seat pan
    cbox(b, (-0.3, 0.3), (-0.26, 0.3), (0.56, 0.7), 0.05, L)                                           # seat
    with xf(b, about((0, -0.3, 0.66), RX(14))):
        cbox(b, (-0.28, 0.28), (-0.42, -0.24), (0.66, 1.34), 0.05, L)                                  # backrest
        cbox(b, (-0.14, 0.14), (-0.4, -0.26), (1.38, 1.62), 0.04, L)                                   # headrest
    for sx in (-1, 1):
        x = sx * 0.34
        cbox(b, (x - 0.045, x + 0.045), (-0.12, 0.3), (0.78, 0.84), 0.015, L)                           # arm pads
        b.beam((x, 0.0, 0.7), (x, 0.0, 0.78), 0.02, 0.02, 4, "Chrome", False)
    b.beam((0, 0.08, 0.3), (0, 0.4, 0.26), 0.035, 0.035, 4, "PoleGrey", True)                            # footrest arm
    with xf(b, about((0, 0.5, 0.26), RX(-14))):
        cbox(b, (-0.2, 0.2), (0.36, 0.62), (0.22, 0.27), 0.03, "PoleGrey")                              # footplate
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ wall mirror
def b_mirror_wall():
    a = ni("mirror_wall", 65)
    b = a.mb()
    bx(b, (-0.8, 0.8), (-0.04, 0.0), (0.95, 2.15), "Trim")                                            # backing
    for z0, z1 in ((0.95, 1.01), (2.09, 2.15)):
        bx(b, (-0.84, 0.84), (-0.05, 0.03), (z0, z1), "Brass")
    for sx in (-1, 1):
        bx(b, ((0.77 if sx > 0 else -0.83), (0.83 if sx > 0 else -0.77)), (-0.05, 0.03), (0.95, 2.15), "Brass")
    bx(b, (-0.77, 0.77), (0.0, 0.01), (1.01, 2.09), "Mirror")
    bx(b, (-0.7, 0.7), (0.0, 0.1), (2.17, 2.22), "LampGlow")                                         # vanity strip light
    bx(b, (-0.85, 0.85), (-0.02, 0.28), (0.82, 0.88), "Laminate")                                     # shelf
    for x, h, m in ((-0.55, 0.2, "PlateBlue"), (-0.4, 0.14, "FabricCoral"), (0.45, 0.17, "PlateGreen")):
        cylz(b, x, 0.12, 0.88, 0.88 + h, 0.04, 6, m)
    bx(b, (0.1, 0.35), (0.06, 0.18), (0.88, 0.92), "Trim")                                            # tray
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ scuba rack
def b_scuba_rack():
    a = ni("scuba_rack", 66)
    b = a.mb()
    bx(b, (-0.85, 0.85), (-0.2, 0.25), (0.0, 0.08), "MetalDark")
    for sx in (-1, 1):
        bx(b, (sx * 0.82 - 0.03, sx * 0.82 + 0.03), (-0.22, -0.16), (0.0, 1.45), "MetalDark")
    for z in (0.3, 0.62):
        bx(b, (-0.85, 0.85), (-0.22, -0.15), (z, z + 0.05), "MetalDark")
    cols = ["PaintYellow", "PlateBlue", "PaintYellow", "PlateGreen"]
    for i, x in enumerate((-0.57, -0.19, 0.19, 0.57)):
        cylz(b, x, 0.0, 0.08, 0.7, 0.09, 6, cols[i], caps=True)
        cylz(b, x, 0.0, 0.7, 0.8, 0.09, 6, "Metal", r1=0.035)
    bx(b, (-0.85, 0.85), (-0.22, -0.1), (1.42, 1.5), "WoodDark")                                      # top shelf
    for x, rot in ((-0.4, 8), (0.2, -6)):                                                           # two fins on the shelf
        with xf(b, about((x, 0.0, 1.5), RZ(rot))):
            ext(b, [(x - 0.07, -0.22), (x + 0.07, -0.22), (x + 0.13, 0.12), (x, 0.22), (x - 0.13, 0.12)], "xy", 1.5, 1.53, "PlateBlue")
    bx(b, (0.55, 0.8), (-0.2, -0.1), (1.5, 1.62), "Trim")                                             # mask
    bx(b, (0.58, 0.77), (-0.1, -0.09), (1.52, 1.6), "Glass")
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ repair lift
def b_repair_lift():
    a = ni("repair_lift", 67)
    b = a.mb()
    Y = "PaintYellow"
    for sx in (-1, 1):
        cx = sx * 0.78
        bx(b, (cx - 0.28, cx + 0.28), (-1.7, 1.7), (0.34, 0.42), "MetalDark")                         # runway
        for ex in (cx - 0.28, cx + 0.28 - 0.04):
            bx(b, (ex, ex + 0.04), (-1.7, 1.7), (0.42, 0.45), Y)                                       # yellow edge rails
        wedge(b, (cx - 0.28, cx + 0.28), (1.7, 2.2), (0.0, 0.42), "MetalDark", "front")                # ramps
        wedge(b, (cx - 0.28, cx + 0.28), (-2.2, -1.7), (0.0, 0.42), "MetalDark", "back")
        bx(b, (cx - 0.3, cx + 0.3), (-1.2, 1.2), (0.0, 0.05), "MetalDark")                              # base rail
        # scissor arms
        b.beam((cx, -1.15, 0.06), (cx, 1.15, 0.33), 0.035, 0.035, 4, Y, False)
        b.beam((cx, -1.15, 0.33), (cx, 1.15, 0.06), 0.035, 0.035, 4, Y, False)
        cylx(b, cx - 0.1, cx + 0.1, 0.0, 0.195, 0.04, 6, "Metal")                                      # centre pivot
    bx(b, (-0.5, 0.5), (-0.1, 0.1), (0.14, 0.2), "MetalDark")                                          # cross brace
    # control pedestal
    bx(b, (1.3, 1.6), (-0.15, 0.15), (0.0, 1.1), Y)
    bx(b, (1.32, 1.58), (0.15, 0.17), (0.7, 1.0), "Trim")
    for z, m in ((0.9, "PlateGreen"), (0.82, "PlateRed"), (0.74, "Metal")):
        bx(b, (1.4, 1.5), (0.17, 0.2), (z - 0.025, z + 0.025), m)
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ tool chest
def b_tool_chest():
    a = ni("tool_chest", 68)
    b = a.mb()
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx(b, (sx * 0.28 - 0.04, sx * 0.28 + 0.04), (sy * 0.17 - 0.03, sy * 0.17 + 0.03), (0.0, 0.1), "Trim")
    bx(b, (-0.35, 0.35), (-0.25, 0.25), (0.1, 1.0), "MetalDark")
    bx(b, (-0.37, 0.37), (-0.27, 0.27), (1.0, 1.05), "MetalDark")
    zs = [(0.14, 0.28), (0.3, 0.44), (0.46, 0.6), (0.62, 0.76), (0.78, 0.9), (0.92, 0.99)]
    for i, (z0, z1) in enumerate(zs):
        bx(b, (-0.33, 0.33), (0.25, 0.27), (z0, z1), "PaintRed")
        bx(b, (-0.15, 0.15), (0.27, 0.3), (z1 - 0.05, z1 - 0.02), "Chrome")
    for sy in (-1, 1):                                                                              # side handle
        bx(b, (0.35, 0.42), (sy * 0.2 - 0.02, sy * 0.2 + 0.02), (0.82, 0.9), "Metal")
    bx(b, (0.4, 0.44), (-0.22, 0.22), (0.82, 0.86), "Metal")
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ neon sign
def b_neon_sign_blank():
    a = ni("neon_sign_blank", 69)
    b = a.mb()
    pn = a.mb("Panel")
    bx(b, (-0.8, 0.8), (-0.05, -0.02), (0.0, 0.6), "Trim")
    for z0, z1 in ((0.0, 0.04), (0.56, 0.6)):
        bx(b, (-0.8, 0.8), (-0.05, 0.015), (z0, z1), "MetalDark")
    for sx in (-1, 1):
        bx(b, (sx * 0.78 - 0.02, sx * 0.78 + 0.02), (-0.05, 0.015), (0.04, 0.56), "MetalDark")
    for x in (-0.55, 0.55):
        b.beam((x, -0.05, 0.25), (x, -0.12, 0.25), 0.012, 0.012, 4, "Metal", True)                   # standoffs
    bx(pn, (-0.74, 0.74), (-0.02, 0.0), (0.06, 0.54), "Neon")
    a.fin(b, "Body")
    p = a.fin(pn, "Panel")
    uv_unit(p, ("x", "z"), flip=True)
    return a
