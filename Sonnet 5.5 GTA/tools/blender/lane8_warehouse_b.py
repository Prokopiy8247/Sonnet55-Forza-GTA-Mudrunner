# lane 8 - warehouse_b: 40 x 25 m with a sawtooth roof (8 teeth, glazed faces toward +X), roller doors on +Y
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("warehouse_b", 10)
b = a.b("Body")
X0, X1, Y0, Y1 = -20.0, 20.0, -12.5, 12.5
ZW, ZT = 6.5, 9.2
PITCH = 5.0
BP = rect_pts(0, 0, 40.0, 25.0, 0.0)

shaft(b, rect_pts(0, 0, 40.4, 25.4), 0, 0.6, "Concrete", "Concrete")
extrude_y(b, [(X0, 0.0), (X1, 0.0), (X1, ZW), (X0, ZW)], Y0, Y1, "WallC")
belt_ring(b, BP, 0.6, 1.0, 0.1, "Trim")
belt_ring(b, BP, ZW - 0.5, ZW, 0.14, "WallD")

# ---- sawtooth: slope (Roof) + vertical glazed face (WallD + window quads + mullions) + end triangles
for k in range(8):
    xa = X0 + PITCH * k
    xb = xa + PITCH
    b.quad((xa, Y1 + 0.2, ZW - 0.05), (xa, Y0 - 0.2, ZW - 0.05), (xb, Y0 - 0.2, ZT), (xb, Y1 + 0.2, ZT), "Roof")
    b.quad((xb, Y0, ZW), (xb, Y1, ZW), (xb, Y1, ZT), (xb, Y0, ZT), "WallD")
    b.tri((xa, Y0, ZW), (xb, Y0, ZW), (xb, Y0, ZT), "WallD")
    b.tri((xb, Y1, ZT), (xb, Y1, ZW), (xa, Y1, ZW), "WallD")
    # window ribbon on the vertical face
    b.quad((xb + 0.06, Y0 + 0.8, ZW + 0.3), (xb + 0.06, Y1 - 0.8, ZW + 0.3), (xb + 0.06, Y1 - 0.8, ZT - 0.25), (xb + 0.06, Y0 + 0.8, ZT - 0.25), "Window")
    for yy in (-8.0, -4.0, 0.0, 4.0, 8.0):
        b.box((xb + 0.1, yy, (ZW + ZT) / 2), (0.14, 0.3, ZT - ZW), "Trim")
    b.box((xb + 0.1, 0, ZT + 0.05), (0.2, 25.4, 0.14), "Metal")                  # ridge flashing
# roof ventilation turbines on the first/last slope
for (x, y) in ((-17.5, -6.0), (-17.5, 6.0), (17.5, -6.0), (17.5, 6.0)):
    za = ZW + (ZT - ZW) * ((x - (X0 + PITCH * int((x - X0) // PITCH))) / PITCH)
    b.cyl((x, y, za + 0.35), 0.5, 0.8, 8, "Metal", r_top=0.35)

# ---- +Y face: four roller doors, lamps, awnings, bay numbers, yard markings
for k, x in enumerate((-15.0, -5.0, 5.0, 15.0)):
    b.box((x, Y1 + 0.1, 2.4), (5.2, 0.2, 4.8), "Trim")
    b.box((x, Y1 + 0.22, 2.4), (4.5, 0.14, 4.4), "Metal")
    for s in range(5):
        b.box((x, Y1 + 0.3, 0.8 + s * 0.85), (4.4, 0.06, 0.12), "MetalDark")
    b.box((x, Y1 + 1.0, 5.15), (5.6, 1.9, 0.22), "WallB")
    b.box((x - 2.6, Y1 + 1.8, 4.3), (0.12, 0.12, 1.7), "Metal")
    b.box((x + 2.6, Y1 + 1.8, 4.3), (0.12, 0.12, 1.7), "Metal")
    b.box((x, Y1 + 0.12, 5.9), (0.5, 0.25, 0.3), "LampGlow")
    b.box((x, Y1 + 0.5, 0.02), (4.8, 1.6, 0.04), "YellowPaint")
    for dx in (-2.8, 2.8):
        b.cyl((x + dx, Y1 + 1.2, 0.5), 0.15, 1.0, 6, "YellowPaint")
# man door + window row on the +X end
b.box((X1 + 0.1, -4.0, 1.1), (0.22, 1.2, 2.2), "MetalDark")
glaze(b, BP, 3.2, 4.8, "Window", bay=3.0, gap=2.0, edge=2.5, skip=(0, 2, 3))
b.box((X0 - 0.1, 6.0, 1.1), (0.22, 1.2, 2.2), "MetalDark")
# painted sign band
b.box((0, Y1 + 0.06, 5.55), (8.0, 0.1, 0.7), "WallA")
b.box((0, Y1 + 0.12, 5.55), (7.4, 0.06, 0.14), "NeonCyan")

a.fin(b, "Body")
a.mark("Door", (0, Y1 + 0.2, 0.0))
report(a)
