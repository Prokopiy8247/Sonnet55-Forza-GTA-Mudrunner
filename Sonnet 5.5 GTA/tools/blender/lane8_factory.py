# lane 8 - factory: 50 x 40 m, sawtooth main hall + boiler house + two 35 m smokestacks + pipe racks + tanks
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("factory", 7)
b = a.b("Body")

# ---------------- main hall (x -25..25, y -20..-2), sawtooth roof
HX0, HX1, HY0, HY1 = -25.0, 25.0, -20.0, -2.0
HZ = 9.0
shaft(b, rect_pts(0, (HY0 + HY1) / 2, 50.6, 18.6), 0, 0.8, "Concrete", "Concrete")
extrude_x(b, [(HY0, 0.0), (HY1, 0.0), (HY1, HZ), (HY0, HZ)], HX0, HX1, "WallD")
TOOTH = 6.0
for k in range(3):
    ya = HY0 + TOOTH * k
    yb = ya + TOOTH
    extrude_x(b, [(ya, HZ), (yb, HZ), (yb, HZ + 2.7)], HX0 - 0.2, HX1 + 0.2, "Roof")
    # glazed vertical face of the tooth (faces +Y) with mullions
    for (xa, xb) in ((-24.4, -12.4), (-11.8, 0.2), (0.8, 12.8), (13.4, 24.4)):
        b.quad((xb, yb + 0.05, HZ + 0.3), (xa, yb + 0.05, HZ + 0.3), (xa, yb + 0.05, HZ + 2.45), (xb, yb + 0.05, HZ + 2.45), "Window")
    for x in (-24.4, -12.1, 0.5, 13.1, 24.4):
        b.box((x, yb + 0.1, HZ + 1.4), (0.35, 0.2, 2.3), "Trim")
# end walls slit windows + hall front (+Y) windows & big door
for sx in (-1, 1):
    for k in range(3):
        b.box((sx * (HX1 + 0.05), HY0 + 3.0 + k * 6.0, 5.8), (0.1, 2.6, 1.6), "Window")
for i in range(7):
    x = -23.0 + i * 4.2
    b.quad((x + 3.0, HY1 + 0.06, 5.0), (x, HY1 + 0.06, 5.0), (x, HY1 + 0.06, 7.2), (x + 3.0, HY1 + 0.06, 7.2), "Window")
b.box((-15.0, HY1 + 0.15, 2.6), (6.2, 0.3, 5.2), "Trim")
b.box((-15.0, HY1 + 0.3, 2.5), (5.6, 0.12, 4.9), "MetalDark")
for s in range(5):
    b.box((-15.0, HY1 + 0.38, 0.9 + s * 0.95), (5.5, 0.06, 0.12), "Metal")
b.box((-15.0, HY1 + 0.2, 5.55), (0.5, 0.25, 0.3), "LampGlow")
belt_ring(b, rect_pts(0, (HY0 + HY1) / 2, 50.0, 18.0), 8.4, 9.0, 0.2, "Trim")

# ---------------- boiler house (x 8..24, y -2..11), 14 m, brick colour
BX0, BX1, BY0, BY1, BZ = 8.0, 24.0, -2.0, 11.0, 14.0
BP = rect_pts((BX0 + BX1) / 2, (BY0 + BY1) / 2, BX1 - BX0, BY1 - BY0, 0.0)
shaft(b, BP, 0.0, BZ, "WallB", "Roof")
parapet(b, BP, BZ, BZ + 0.9, 0.35, "WallD")
belt_ring(b, BP, BZ - 0.8, BZ, 0.25, "Trim")
glaze(b, BP, 5.0, 11.0, "Window", bay=1.6, gap=1.6, edge=1.5, skip=(0, 3))
belt_ring(b, BP, 0.0, 1.0, 0.18, "Concrete")
b.box((16.0, BY1 + 0.2, 1.8), (3.6, 0.3, 3.6), "MetalDark")           # boiler house doors
b.box((16.0, BY1 + 0.9, 3.8), (4.2, 1.6, 0.25), "Trim")
b.box((11.0, 2.0, BZ + 1.6), (2.6, 2.6, 1.6), "MetalDark")             # roof plant
b.box((20.0, 6.0, BZ + 1.4), (3.4, 2.2, 1.2), "MetalDark")
b.cyl((21.0, 0.5, BZ + 1.6), 0.8, 1.6, 10, "Metal")

# ---------------- smokestacks
def stack(cx, cy, h=35.0, r0=1.85, r1=1.2):
    n = 5
    for k in range(n):
        z0 = h * k / n
        z1 = h * (k + 1) / n
        ra = r0 + (r1 - r0) * z0 / h
        rb = r0 + (r1 - r0) * z1 / h
        b.cyl((cx, cy, (z0 + z1) / 2), ra, z1 - z0, 12, "RedPaint" if k % 2 == 1 else "WhitePaint", r_top=rb, caps=False)
    b.cyl((cx, cy, h + 0.25), r1 + 0.3, 0.7, 12, "Trim", r_top=r1 + 0.1)            # flared top ring
    b.cyl((cx, cy, 0.4), r0 + 0.35, 0.8, 12, "Concrete", r_top=r0 + 0.1)             # base plinth
    b.sphere((cx, cy, h + 0.9), 0.22, 6, 4, "LightRed")


for cx in (15.5, 21.5):
    stack(cx, 16.0)
    b.beam((cx, BY1, 9.0), (cx, 14.3, 9.0), 0.8, 0.8, 8, "MetalDark")              # flue duct
    b.beam((cx, 14.3, 9.0), (cx, 14.6, 9.0), 1.0, 1.0, 8, "Metal")
for cx in (15.5, 21.5):
    for yy in (BY1 + 0.2,):
        b.box((cx, yy + 0.3, 9.0), (1.9, 0.5, 1.9), "MetalDark")

# ---------------- pipe rack along the hall front (x -24.5..6)
for x in range(-24, 8, 6):
    for yy in (7.0, 9.0):
        b.box((x, yy, 2.6), (0.34, 0.34, 5.2), "Metal")
    b.box((x, 8.0, 5.2), (0.4, 2.7, 0.3), "Metal")
    b.box((x, 8.0, 3.0), (0.25, 2.4, 0.2), "Metal")
for (yy, rr, zz, m) in ((7.4, 0.42, 5.7, "Metal"), (8.1, 0.28, 5.55, "WhitePaint"), (8.7, 0.25, 5.5, "RedPaint")):
    b.beam((-24.6, yy, zz), (6.5, yy, zz), rr, rr, 8, m)
for x in (-18.0, -4.0):                                                              # risers into the hall + tank links
    b.beam((x, 7.4, 5.7), (x, HY1 - 0.1, 5.7), 0.3, 0.3, 6, "Metal")
    b.sphere((x, 7.4, 5.7), 0.5, 6, 4, "Metal")
for x in (-12.0, 0.0):
    b.beam((x, 7.4, 5.7), (x, 7.4, 8.4), 0.26, 0.26, 6, "Metal")
    b.box((x, 7.4, 8.6), (0.8, 0.8, 0.4), "Trim")
    b.sphere((x, 7.4, 5.7), 0.45, 6, 4, "Metal")
b.beam((6.5, 7.4, 5.7), (6.5, 7.4, 10.0), 0.42, 0.42, 8, "Metal")
b.beam((6.5, 7.4, 10.0), (BX0 + 0.1, 7.4, 10.0), 0.42, 0.42, 8, "Metal")

# ---------------- storage tanks
for (cx, cy, r, h) in ((-17.0, 14.0, 3.6, 7.5), (-6.5, 15.0, 2.7, 5.5)):
    b.cyl((cx, cy, h / 2), r, h, 14, "WhitePaint", caps=False)
    b.cyl((cx, cy, h + 0.45), r + 0.15, 0.9, 14, "Metal", r_top=r * 0.35)
    b.cyl((cx, cy, h + 1.05), r * 0.35, 0.3, 8, "MetalDark")
    b.cyl((cx, cy, 0.25), r + 0.2, 0.5, 14, "Concrete")
    b.cyl((cx, cy, h * 0.55), r + 0.06, 0.3, 14, "RedPaint", caps=False)
    ang = -1.1
    b.beam((cx + (r + 0.1) * math.cos(ang), cy + (r + 0.1) * math.sin(ang), 0.5), (cx + (r + 0.1) * math.cos(ang), cy + (r + 0.1) * math.sin(ang), h + 0.2), 0.08, 0.08, 4, "Metal")
b.beam((-17.0, 10.4, 3.0), (-17.0, 8.1, 3.0), 0.3, 0.3, 6, "Metal")
b.beam((-6.5, 12.3, 3.0), (-6.5, 8.1, 3.0), 0.3, 0.3, 6, "Metal")

a.fin(b, "Body")
a.mark("Door", (-15.0, HY1 + 0.4, 0.0))
report(a)
