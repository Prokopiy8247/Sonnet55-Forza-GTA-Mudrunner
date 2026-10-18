# lane 8 - warehouse_a: big shed 60 x 30 m with loading docks + roller doors on the +Y long side
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("warehouse_a", 6)
b = a.b("Body")
X0, X1 = -30.0, 30.0
Y0, Y1 = -15.0, 12.0          # main shed; the dock platform fills 12..15
ZE, ZR, T, OH = 8.0, 10.4, 0.3, 0.7
YM = (Y0 + Y1) / 2
M = (ZR - ZE) / (YM - Y0)

# ---- shed walls (pentagon section) + roof slab
extrude_x(b, gable_prof(Y0, Y1, ZE, ZR), X0, X1, "WallD")
extrude_x(b, roof_prof(Y0, Y1, ZE, ZR, OH, T), X0 - OH, X1 + OH, "Roof")
shaft(b, rect_pts(0, (Y0 + Y1) / 2, 60.3, Y1 - Y0 + 0.3), 0, 1.0, "Concrete", "Concrete")     # plinth
belt_ring(b, rect_pts(0, (Y0 + Y1) / 2, 60.0, Y1 - Y0), 5.6, 7.6, 0.12, "WallC")               # blue band under the eaves
belt_ring(b, rect_pts(0, (Y0 + Y1) / 2, 60.0, Y1 - Y0), 1.0, 1.4, 0.1, "Trim")


def ztop(y):
    """top surface of the roof at y (within the sloped part)"""
    return ZE + M * ((y - Y0) if y <= YM else (Y1 - y)) + T + 0.04


# ---- skylight strips on both slopes
for (xa, xb) in ((-25.0, -13.0), (-6.0, 6.0), (13.0, 25.0)):
    ya, yb = YM - 5.2, YM - 1.2
    b.quad((xa, ya, ztop(ya)), (xb, ya, ztop(ya)), (xb, yb, ztop(yb)), (xa, yb, ztop(yb)), "Glass")
    ya, yb = YM + 1.2, YM + 5.2
    b.quad((xa, ya, ztop(ya)), (xb, ya, ztop(ya)), (xb, yb, ztop(yb)), (xa, yb, ztop(yb)), "Glass")
    for yy in (YM - 5.2, YM + 5.2):
        b.box(((xa + xb) / 2, yy, ztop(yy) - 0.02), (xb - xa, 0.3, 0.14), "Metal")
for x in (-28.0, -18.0, -8.0, 8.0, 18.0, 28.0):                       # ridge vents
    b.box((x, YM, ZR + T + 0.35), (1.8, 1.2, 0.8), "Metal")

# ---- loading dock platform + seven roller-door bays on the +Y face
b.box((0, 13.5, 0.65), (59.4, 3.0, 1.3), "Concrete")
b.box((0, 14.82, 1.32), (59.4, 0.36, 0.04), "YellowPaint")
for k in range(7):
    x = -24.0 + 8.0 * k
    b.box((x, Y1 + 0.08, 3.5), (5.0, 0.2, 4.4), "Trim")                              # frame
    b.box((x, Y1 + 0.2, 3.55), (4.2, 0.12, 4.0), "Metal")                            # door leaf
    for s in range(4):
        b.box((x, Y1 + 0.28, 2.0 + s * 1.0), (4.1, 0.06, 0.12), "MetalDark")           # slat lines
    b.box((x, Y1 + 0.3, 1.3), (1.0, 0.1, 0.16), "Trim")                              # lock
    b.box((x, 13.4, 1.38), (3.2, 2.0, 0.1), "YellowPaint")                            # dock leveller
    b.box((x - 2.2, 14.85, 0.95), (0.45, 0.3, 0.6), "Trim")                           # bumpers
    b.box((x + 2.2, 14.85, 0.95), (0.45, 0.3, 0.6), "Trim")
    b.box((x, Y1 + 0.95, 5.95), (5.4, 2.0, 0.22), "Trim")                             # awning
    b.box((x - 2.5, Y1 + 1.8, 5.2), (0.12, 0.12, 1.5), "Metal")
    b.box((x + 2.5, Y1 + 1.8, 5.2), (0.12, 0.12, 1.5), "Metal")
    b.box((x, Y1 + 0.1, 6.35), (0.5, 0.2, 0.35), "LampGlow")                          # bay lamp
    n_plate = b.box((x, Y1 + 0.12, 5.55), (0.9, 0.05, 0.4), "WallB" if k % 2 == 0 else "WallC")   # bay number tab

# ---- ends: man door, high windows, lamps
for sx in (-1, 1):
    x = sx * (X1 + 0.1)
    b.box((x, 3.0, 1.15), (0.22, 1.3, 2.3), "MetalDark")
    for yy in (-11.0, -6.0, -1.0, 4.0, 9.0):
        b.box((x - sx * 0.0, yy, 6.4), (0.1, 2.2, 1.0), "Window")
    b.box((x, -1.5, 3.2), (0.25, 0.4, 0.25), "LampGlow")
# back wall windows
glaze(b, rect_pts(0, (Y0 + Y1) / 2, 60.0, Y1 - Y0), 6.0, 7.2, "Window", bay=4.5, gap=1.5, edge=3.0, skip=(1, 2, 3))
# rear loading ramp / stack of pallets & crates in front of the dock for life
for (x, y) in ((-27.5, 9.0), (-26.2, 9.0)):
    pass

a.fin(b, "Body")
a.mark("Door", (0, 15.0, 0.0))
report(a)
