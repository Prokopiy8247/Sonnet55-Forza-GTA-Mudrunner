# lane 8 - terminal: small airport terminal 50 x 20 m, curved swooping canopy, glass front (+Y), apron side (-Y)
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("terminal", 5)
b = a.b("Body")
_LETTERS["P"] = [(0, 0, 1, 5), (1, 2, 3, 3), (1, 4, 3, 5), (2, 3, 3, 4)]

TOP = [(-10.0, 7.2), (-6.0, 8.4), (-2.0, 9.0), (2.0, 8.7), (6.0, 7.6), (10.0, 5.9)]


def zt(y):
    for (y0, z0), (y1, z1) in zip(TOP, TOP[1:]):
        if y0 <= y <= y1:
            return z0 + (z1 - z0) * (y - y0) / (y1 - y0)
    return TOP[-1][1]


def th(y):
    return 0.65 - 0.3 * (y + 10.0) / 20.0


def zb(y):
    return zt(y) - th(y)


YS = [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]
# ---- curved canopy (closed solid, extruded along X)
poly = [(y, zb(y)) for y in YS] + [(y, zt(y)) for y in reversed(YS)]
extrude_x(b, poly, -25.0, 25.0, "Roof")
b.box((0, 9.92, zb(10.0) - 0.08), (50.0, 0.2, 0.22), "NeonCyan")      # glowing front lip
b.box((0, -9.92, zb(-10.0) - 0.08), (50.0, 0.2, 0.2), "NeonCyan")

# ---- hall body under the canopy
HX = 23.8
yb = -9.4
hall = [(yb, 0.0), (2.0, 0.0), (2.0, zb(2.0)), (-2.0, zb(-2.0)), (-6.0, zb(-6.0)), (yb, zb(yb))]
extrude_x(b, hall, -HX, HX, "WallD")
# plinth
b.box((0, -3.7, 0.2), (HX * 2 + 0.4, 12.0, 0.4), "Concrete")

# ---- glass front wall: window bays + mullions + doors
zg = zb(2.0) - 0.35
bays = 11
w = (2 * 22.0) / bays
for i in range(bays):
    x1 = -22.0 + i * w
    x0 = x1 + w
    b.quad((x0 - 0.12, 2.07, 0.6), (x1 + 0.12, 2.07, 0.6), (x1 + 0.12, 2.07, zg), (x0 - 0.12, 2.07, zg), "Window")
for i in range(bays + 1):
    x = -22.0 + i * w
    b.box((x, 2.12, zg / 2 + 0.3), (0.26, 0.28, zg - 0.5), "Trim")
b.box((0, 2.12, zg), (44.4, 0.3, 0.3), "Trim")
b.box((0, 2.12, 0.6), (44.4, 0.3, 0.2), "Trim")
# entrance portal (two sliding doors)
b.box((-1.1, 2.2, 1.35), (1.9, 0.14, 2.5), "Glass")
b.box((1.1, 2.2, 1.35), (1.9, 0.14, 2.5), "Glass")
b.box((0, 2.35, 3.0), (4.6, 0.7, 0.18), "Trim")

# ---- terminal end walls: slit windows + signage band
for sx in (-1, 1):
    x = sx * (HX + 0.06)
    for k in range(3):
        yy = -6.0 + k * 3.5
        b.box((x, yy, 3.2), (0.1, 1.4, 3.2), "Window")

# ---- apron side (-Y): glazing band, gate doors, boarding stairs
rear = rect_pts(0, -3.7, HX * 2, 11.4, 0.0)
glaze(b, rear, 1.2, 4.6, "Window", bay=3.6, gap=0.9, edge=1.5, skip=(1, 2, 3))     # edge 0 is the -Y face
for gx in (-15.0, 0.0, 15.0):
    b.box((gx, yb - 0.4, 2.55), (3.6, 0.3, 0.3), "Trim")
    b.box((gx, yb - 0.02, 1.1), (1.8, 0.14, 2.1), "MetalDark")
    # boarding stair unit: wedge + rails + landing
    b.box((gx, yb - 0.7, 1.0), (2.4, 1.3, 2.0), "Metal")             # landing
    for s in range(4):
        b.box((gx, yb - 1.8 - s * 0.45, 0.8 - s * 0.2), (2.0, 0.45, 1.6 - s * 0.4), "Metal")
# baggage handling shed on the apron side
b.box((19.0, yb - 1.6, 1.6), (8.0, 3.4, 3.2), "WallC")
b.box((19.0, yb - 3.35, 1.0), (6.5, 0.2, 1.4), "Trim")
b.box((19.0, yb - 1.6, 3.35), (8.4, 3.8, 0.3), "Roof")

# ---- forecourt slab + columns
b.box((0, 6.0, 0.1), (50.0, 8.0, 0.2), "Concrete")
for k in range(7):
    x = -22.5 + 7.5 * k
    b.beam((x, 8.6, 0.2), (x, 8.6, zb(8.6) + 0.05), 0.34, 0.22, 8, "Metal")
    b.box((x, 8.6, 0.28), (0.9, 0.9, 0.16), "Concrete")
# curb-side bollards in front of the doors
for x in (-6.0, -3.0, 3.0, 6.0):
    b.cyl((x, 9.4, 0.6), 0.14, 0.8, 6, "Trim")

# ---- roof signage: AIRPORT in cyan block letters standing on the canopy
txt = "AIRPORT"
h = 1.7
lw = 3 * h / 5.0
gapx = 0.5
total = len(txt) * lw + (len(txt) - 1) * gapx
xs = total / 2.0                       # letters are written along -X when seen from +Y
x_cur = xs
y_s = 6.3
for ch in txt:
    letter(b, ch, (x_cur, y_s, zt(y_s) + 0.55), (-1, 0, 0), (0, 0, 1), (0, 1, 0), h, 0.28, "NeonCyan")
    x_cur -= lw + gapx
for x in (-total / 2 + 0.6, 0, total / 2 - 0.6):
    b.box((x, y_s - 0.2, zt(y_s) + 0.3), (0.25, 0.25, 0.9), "Metal")
b.box((0, y_s - 0.22, zt(y_s) + 0.62), (total + 0.6, 0.2, 0.14), "Trim")

# ---- rooftop kit on the high part of the canopy
for (x, y) in ((-16.0, -6.0), (-8.0, -6.0), (14.0, -5.0), (20.0, -6.0)):
    b.box((x, y, zt(y) + 0.6), (2.6, 2.2, 1.2), "MetalDark")
b.beam((22.0, -8.0, zt(-8.0)), (22.0, -8.0, zt(-8.0) + 6.0), 0.1, 0.05, 4, "Metal")

a.fin(b, "Body")
a.mark("Door", (0, 2.6, 0.0))
report(a)
