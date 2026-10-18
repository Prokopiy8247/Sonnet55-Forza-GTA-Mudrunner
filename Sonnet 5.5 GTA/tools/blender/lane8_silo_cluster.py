# lane 8 - silo_cluster: 4 tall silos + elevator tower + conveyor galleries, 18 x 18 m footprint
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("silo_cluster", 11)
b = a.b("Body")
R = 3.7
SEG = 14
H0, H1 = 1.2, 30.2
TOPBAND = {(-1, -1): "WallA", (1, -1): "WallB", (-1, 1): "WallC", (1, 1): "WallA"}
ZG = 34.0     # gallery floor

# ---- silos
for (sx, sy), band in TOPBAND.items():
    cx, cy = sx * 4.6, sy * 4.6
    b.cyl((cx, cy, 0.6), R + 0.35, 1.2, SEG, "Concrete", r_top=R + 0.1)                    # plinth
    b.cyl((cx, cy, (H0 + 26.0) / 2), R, 26.0 - H0, SEG, "WallD", caps=False)                # lower body
    b.cyl((cx, cy, (26.0 + H1) / 2), R + 0.05, H1 - 26.0, SEG, band, caps=False)            # coloured top band
    for z in (6.5, 12.0, 17.5, 22.0):
        b.cyl((cx, cy, z), R + 0.12, 0.45, SEG, "Concrete", caps=False)                     # reinforcing rings
    b.cyl((cx, cy, 26.0), R + 0.2, 0.35, SEG, "Trim", caps=False)
    b.cyl((cx, cy, H1 + 1.1), R + 0.15, 2.2, SEG, "Metal", r_top=1.0)                       # conical roof
    b.cyl((cx, cy, H1 + 2.45), 1.0, 0.5, 8, "MetalDark")                                    # hatch ring
    b.cyl((cx, cy, H1 + 3.0), 0.7, 0.6, 8, "Metal", r_top=0.35)
    # ladder on the outer side (away from the cluster centre)
    ang = math.atan2(sy, sx)
    lx, ly = cx + (R + 0.25) * math.cos(ang), cy + (R + 0.25) * math.sin(ang)
    b.box((lx, ly, 15.5), (0.18, 0.7, 29.0) if abs(math.cos(ang)) > 0.5 else (0.7, 0.18, 29.0), "MetalDark")
    for z in (3.0, 10.0, 17.0, 24.0):
        b.box((lx, ly, z), (0.3, 0.3, 0.1), "Metal")
    # level lamp
    b.box((cx + (R + 0.15) * math.cos(ang + 0.8), cy + (R + 0.15) * math.sin(ang + 0.8), 28.0), (0.25, 0.25, 0.25), "LampGlow")

# ---- elevator tower (centre) with head house
b.box((0, 0, 17.5), (3.0, 3.0, 35.0), "WallD")
for z in (8.0, 18.0, 28.0):
    b.box((0, 0, z), (3.35, 3.35, 0.4), "Trim")
glz = rect_pts(0, 0, 3.0, 3.0, 0.0)
glaze(b, glz, 11.0, 12.6, "Window", bay=None, edge=0.7)
glaze(b, glz, 21.0, 22.6, "Window", bay=None, edge=0.7)
b.box((0, 0, 36.6), (4.0, 4.0, 3.2), "WallB")
glaze(b, rect_pts(0, 0, 4.0, 4.0, 0.0), 36.0, 37.4, "Window", bay=1.4, gap=0.5, edge=0.6)
b.box((0, 0, 38.4), (4.4, 4.4, 0.4), "Roof")
b.beam((0, 0, 38.6), (0, 0, 42.0), 0.12, 0.05, 4, "Metal")
b.sphere((0, 0, 42.1), 0.2, 6, 4, "LightRed")

# ---- top galleries (H shape) over the silo hatches
def gallery(cx, cy, sx_len, sy_len):
    b.box((cx, cy, ZG + 0.9), (sx_len, sy_len, 1.7), "Metal")
    b.box((cx, cy, ZG + 1.85), (sx_len + 0.3, sy_len + 0.3, 0.22), "Roof")


gallery(0, 0, 1.6, 19.0)            # central, along Y (spills past the tower)
gallery(0, -4.6, 9.4, 1.6)          # cross galleries along X above the hatches
gallery(0, 4.6, 9.4, 1.6)
for (px, py) in ((0, -8.8), (0, 8.8)):
    b.beam((px, py, ZG - 0.1), (px, py, ZG - 3.0), 0.2, 0.2, 4, "Metal")
for sy in (-1, 1):
    for k in range(5):
        y = sy * (1.6 + 1.5 * k)
        b.box((0.82, y, ZG + 1.0), (0.06, 0.9, 0.7), "Window")
        b.box((-0.82, y, ZG + 1.0), (0.06, 0.9, 0.7), "Window")
for sx in (-1, 1):
    for k in range(3):
        x = sx * (0.9 + 1.3 * k)
        b.box((x, 5.42, ZG + 1.0), (0.9, 0.06, 0.7), "Window")
        b.box((x, -3.78, ZG + 1.0), (0.9, 0.06, 0.7), "Window")
b.cyl((0, 9.7, ZG + 0.4), 0.45, 1.2, 8, "MetalDark", r_top=0.2)                    # discharge spout

# ---- feeder conveyor from the front hopper up to the tower (corridor x = -0.9 .. 0.9)
P0 = Vector((0, 8.6, 2.6))
P1 = Vector((0, 1.6, 16.0))
d = (P1 - P0).normalized()
n = Vector((1, 0, 0)).cross(d)
mid = (P0 + P1) / 2
L = (P1 - P0).length
obox(b, mid, (1, 0, 0), d, n, 1.3, L, 0.9, "Metal")
obox(b, mid + n * 0.5, (1, 0, 0), d, n, 1.5, L, 0.12, "Roof")
for t in (0.15, 0.4, 0.65, 0.88):
    p = P0 + (P1 - P0) * t
    b.beam((0.5, p.y, 0.0), (0.5, p.y, p.z - 0.4), 0.09, 0.09, 4, "Metal")
    b.beam((-0.5, p.y, 0.0), (-0.5, p.y, p.z - 0.4), 0.09, 0.09, 4, "Metal")
    b.box((0, p.y, p.z - 0.45), (1.2, 0.2, 0.12), "Metal")
# hopper (inverted pyramid) on legs + loading platform
hexa(b, [(-0.7, 8.0, 1.3), (0.7, 8.0, 1.3), (0.7, 9.4, 1.3), (-0.7, 9.4, 1.3)],
        [(-2.2, 7.4, 3.2), (2.2, 7.4, 3.2), (2.2, 10.0, 3.2), (-2.2, 10.0, 3.2)], "WallB")
for (hx, hy) in ((-1.9, 7.7), (1.9, 7.7), (-1.9, 9.7), (1.9, 9.7)):
    b.beam((hx, hy, 0.0), (hx, hy, 3.1), 0.12, 0.12, 4, "Metal")
b.box((0, 8.7, 0.18), (5.4, 4.0, 0.36), "Concrete")                       # pad

a.fin(b, "Body")
a.mark("Door", (0, 9.0, 0.0))
report(a)
