# lane 8 - crane_dock: ship-to-shore container gantry crane. Rail gauge (sea-side legs to land-side legs) = 30 m along Y,
# portal width 14 m along X, 42 m tall. Boom (outreach over the water) points to +Y (front). Separate mesh `Trolley` (origin on the
# trolley girder level) can slide along Y; `Body` is static.
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("crane_dock", 12)
b = a.b("Body")
DY = -5.5                     # shift so the footprint centre (bbox centre) sits at the origin
GY = 15.0                     # half gauge (legs at y = +/-15 -> 30 m span)
PX = 7.0                      # half portal width
ZP = 24.4                     # top of portal beams
ZT0, ZT1 = 24.4, 27.0         # trolley girder (truss) levels
Y_REAR, Y_TIP = -22.0, 34.0
APEX = Vector((0.0, 9.0, 39.8))


def y(v):
    return v + DY


def truss(x, ya, yb, z0, z1, panel=3.0, chord="CranePaint", diag="Metal"):
    b.box((x, y((ya + yb) / 2), z1 - 0.2), (1.1, yb - ya, 0.4), chord)
    b.box((x, y((ya + yb) / 2), z0 + 0.2), (1.1, yb - ya, 0.4), chord)
    n = int(round((yb - ya) / panel))
    for i in range(n):
        y0_ = ya + (yb - ya) * i / n
        y1_ = ya + (yb - ya) * (i + 1) / n
        b.beam((x, y(y0_), z0 + 0.3), (x, y(y1_), z1 - 0.3), 0.12, 0.12, 4, diag, caps=False) if i % 2 == 0 else \
            b.beam((x, y(y0_), z1 - 0.3), (x, y(y1_), z0 + 0.3), 0.12, 0.12, 4, diag, caps=False)
    for i in range(n + 1):
        yy = ya + (yb - ya) * i / n
        b.beam((x, y(yy), z0 + 0.3), (x, y(yy), z1 - 0.3), 0.1, 0.1, 4, diag, caps=False)


# ---- legs (4), tapered box columns on bogies + rails
for sx in (-1, 1):
    for sy in (-1, 1):
        cx, cy = sx * PX, y(sy * GY)
        hexa(b, [(cx - 1.0, cy - 1.0, 0.9), (cx + 1.0, cy - 1.0, 0.9), (cx + 1.0, cy + 1.0, 0.9), (cx - 1.0, cy + 1.0, 0.9)],
                [(cx - 0.75, cy - 0.75, ZP), (cx + 0.75, cy - 0.75, ZP), (cx + 0.75, cy + 0.75, ZP), (cx - 0.75, cy + 0.75, ZP)], "CranePaint")
        b.box((cx, cy, 0.55), (2.2, 3.4, 1.1), "MetalDark")                                            # bogie
        for dy in (-1.3, 1.3):
            b.box((cx, cy + dy, 0.45), (2.4, 0.5, 0.9), "Metal")                                         # wheel blocks
for sy in (-1, 1):                                                                                      # rails + concrete beams
    b.box((0, y(sy * GY), 0.12), (27.0, 1.6, 0.24), "Concrete")
    b.box((0, y(sy * GY), 0.3), (27.0, 0.3, 0.14), "MetalDark")

# ---- portal beams, ties, braces
for sx in (-1, 1):
    b.box((sx * PX, y(0), ZP - 1.1), (1.7, 2 * GY + 1.2, 2.2), "CranePaint")                         # side girders (along Y)
    b.box((sx * PX, y(0), ZP - 2.4), (0.5, 2 * GY, 0.3), "MetalDark")
for sy in (-1, 1):
    b.box((0, y(sy * GY), ZP - 1.0), (2 * PX + 1.0, 1.7, 2.0), "CranePaint")                        # cross girders (along X)
    b.box((0, y(sy * GY), 9.0), (2 * PX - 1.0, 1.0, 0.9), "CranePaint")                             # lower ties
    b.beam((-PX, y(sy * GY), 3.0), (PX, y(sy * GY), ZP - 2.5), 0.28, 0.28, 4, "Metal", caps=False)      # X braces
    b.beam((PX, y(sy * GY), 3.0), (-PX, y(sy * GY), ZP - 2.5), 0.28, 0.28, 4, "Metal", caps=False)
for sx in (-1, 1):
    b.beam((sx * PX, y(-GY), 3.0), (sx * PX, y(GY), ZP - 2.5), 0.3, 0.3, 4, "Metal", caps=False)     # side X braces in the YZ plane
    b.beam((sx * PX, y(GY), 3.0), (sx * PX, y(-GY), ZP - 2.5), 0.3, 0.3, 4, "Metal", caps=False)

# ---- boom / trolley girders (two trusses)
for sx in (-1, 1):
    truss(sx * 2.7, Y_REAR, Y_TIP, ZT0, ZT1, 3.0)
    b.box((sx * 2.7, y((Y_REAR + Y_TIP) / 2), ZT1 + 0.12), (0.5, Y_TIP - Y_REAR, 0.2), "MetalDark")  # trolley rail
for yy in range(-21, 34, 6):
    b.box((0, y(yy), ZT0 + 0.2), (5.4, 0.45, 0.4), "CranePaint")                                     # cross ties
b.box((0, y(Y_TIP), ZT0 + 1.3), (6.2, 0.8, 2.6), "CranePaint")                                      # boom tip head
b.box((0, y(Y_REAR), ZT0 + 1.3), (6.2, 0.8, 2.6), "CranePaint")

# ---- A-frame, apex, stays
APX = Vector((APEX.x, y(APEX.y), APEX.z))
for sx in (-1, 1):
    top = Vector((sx * 2.4, y(APEX.y), APEX.z))
    b.beam((sx * PX, y(GY), ZP), top, 0.55, 0.4, 6, "CranePaint", caps=False)
    b.beam((sx * PX, y(-GY), ZP), top, 0.55, 0.4, 6, "CranePaint", caps=False)
    b.beam((sx * 2.7, y(Y_TIP), ZT1), top, 0.17, 0.17, 4, "Metal", caps=False)                       # forestay
    b.beam((sx * 2.7, y(24.0), ZT1), top, 0.14, 0.14, 4, "Metal", caps=False)
    b.beam((sx * 2.7, y(Y_REAR), ZT1), top, 0.17, 0.17, 4, "Metal", caps=False)                      # backstay
    b.beam((sx * 2.7, y(-8.0), ZT1), top, 0.14, 0.14, 4, "Metal", caps=False)
b.box((0, y(APEX.y), APEX.z), (5.6, 2.4, 2.2), "CranePaint")
b.box((0, y(APEX.y), APEX.z + 1.5), (2.0, 1.6, 0.8), "MetalDark")
b.sphere((0, y(APEX.y), APEX.z + 2.15), 0.35, 6, 4, "LightRed")
b.box((0, y(Y_TIP + 0.5), ZT1 + 2.9), (0.5, 0.5, 0.5), "LightRed")
for sx in (-1, 1):
    b.box((sx * 2.9, y(APEX.y + 1.4), APEX.z + 0.4), (0.4, 0.3, 0.3), "LampGlow")

# ---- machinery house on the rear of the portal
b.box((0, y(-8.0), ZP + 2.7), (11.0, 8.0, 5.4), "CranePaint")
b.box((0, y(-8.0), ZP + 5.55), (11.6, 8.6, 0.3), "Roof")
for (xx, yy, nx, ny) in ((0, -12.02, 0, -1), (0, -3.98, 0, 1)):
    for k in range(4):
        x0 = -4.0 + k * 2.4
        if ny > 0:
            b.quad((x0 + 1.7, y(yy), ZP + 2.6), (x0, y(yy), ZP + 2.6), (x0, y(yy), ZP + 4.0), (x0 + 1.7, y(yy), ZP + 4.0), "Window")
        else:
            b.quad((x0, y(yy), ZP + 2.6), (x0 + 1.7, y(yy), ZP + 2.6), (x0 + 1.7, y(yy), ZP + 4.0), (x0, y(yy), ZP + 4.0), "Window")
b.box((0, y(-8.0), ZP + 0.1), (11.4, 8.4, 0.2), "MetalDark")
b.box((3.0, y(-4.0), ZP + 5.8), (0.5, 0.5, 0.6), "LampGlow")
b.box((-3.0, y(-12.0), ZP + 5.8), (0.5, 0.5, 0.6), "LampGlow")
# walkway + ladder along the sea-side leg
for sx in (-1, 1):
    b.box((sx * (PX + 1.1), y(GY), 1.0), (0.12, 0.7, 2.0), "Metal")
    b.box((sx * (PX + 1.1), y(GY), 12.0), (0.12, 0.7, 22.0), "Metal")
b.box((0, y(GY + 0.7), ZP - 2.2), (2 * PX + 1.0, 0.25, 0.25), "NeonCyan")
b.box((0, y(-GY - 0.7), ZP - 2.2), (2 * PX + 1.0, 0.25, 0.25), "NeonCyan")

b.translate((0, 0, 0))
body = a.fin(b, "Body")

# ======================================================== TROLLEY (separate mesh; origin on the trolley rail level, y = 24)
TY = 24.0
tb = a.b("Trolley")
tb.box((0, 0, 1.0), (6.4, 3.2, 1.8), "RedPaint")                    # trolley frame sits on the rails
tb.box((0, 0, 0.0), (6.8, 1.4, 0.35), "MetalDark")
for sx in (-1, 1):
    for dy in (-1.2, 1.2):
        tb.box((sx * 2.7, dy, 0.1), (0.7, 0.5, 0.5), "Metal")
tb.box((0, 0, 2.15), (3.0, 2.0, 0.5), "MetalDark")
# operator cab hanging below the girders
tb.box((3.9, 0.0, -2.1), (2.2, 2.4, 2.2), "YellowPaint")
tb.quad((3.9 + 1.12, -0.9, -2.5), (3.9 + 1.12, 0.9, -2.5), (3.9 + 1.12, 0.9, -1.4), (3.9 + 1.12, -0.9, -1.4), "Window")
tb.box((3.9, 0.0, -0.75), (0.3, 0.3, 0.5), "Metal")
# hoist ropes, spreader, hanging container
zs = -12.4
for sx in (-1, 1):
    for sy in (-1, 1):
        tb.beam((sx * 2.0, sy * 0.9, -0.1), (sx * 2.9, sy * 1.0, zs + 0.3), 0.05, 0.05, 3, "Trim", caps=False)
tb.box((0, 0, zs), (6.2, 2.5, 0.5), "MetalDark")
for sx in (-1, 1):
    for sy in (-1, 1):
        tb.box((sx * 2.9, sy * 1.1, zs - 0.35), (0.35, 0.35, 0.3), "Metal")
tb.box((0, 0, zs - 1.9), (6.0, 2.4, 2.5), "WallB")
for sx in (-1, 1):
    for sy in (-1, 1):
        tb.box((sx * 2.9, sy * 1.1, zs - 0.75), (0.3, 0.3, 0.12), "Trim")
a.fin(tb, "Trolley", loc=(0, y(TY), ZT1 + 0.25))

a.mark("Spreader", (0, y(TY), ZT1 + 0.25 + zs), size=1.0)
report(a)
