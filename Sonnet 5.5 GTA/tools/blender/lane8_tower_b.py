# lane 8 - tower_b: twin-slab 'bridge' tower 36 x 24 m, 90 m, sky-bridge, magenta neon edge strips
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("tower_b", 1)
b = a.b("Body")

# --- base podium spanning both slabs (36 x 24 x 5)
PB = rect_pts(0, 0, 36, 24, 0.0)
shaft(b, inflate(PB, 0.2), 0, 0.8, "Concrete", "Concrete")
shaft(b, PB, 0.4, 5.0, "WallD", "Concrete")
glaze(b, PB, 1.0, 4.0, "Window", bay=4.2, gap=0.9, edge=1.2)
belt_ring(b, PB, 4.4, 5.0, 0.3, "Trim")
# front canopy over the gap
b.box((0, 13.4, 4.3), (12.0, 2.6, 0.35), "Trim")
b.box((0, 14.65, 4.3), (12.0, 0.25, 0.25), "Neon")
for x in (-5.4, 5.4):
    b.cyl((x, 14.0, 2.15), 0.22, 4.3, 8, "Metal", caps=False)

SLABS = ((-1, -12.0), (1, 12.0))     # (side, cx)
for side, cx in SLABS:
    PS = rect_pts(cx, 0, 12.0, 24.0, 0.0)
    shaft(b, PS, 5.0, 82.0, "WallC", None)
    # sloped crown wedge (A leans to the front, B to the back)
    x0, x1 = cx - 6.0, cx + 6.0
    hi_front = side < 0
    zf, zb = (88.0, 82.6) if hi_front else (82.6, 88.0)
    hexa(b, [(x0, -12, 82), (x1, -12, 82), (x1, 12, 82), (x0, 12, 82)],
         [(x0, -12, zb), (x1, -12, zb), (x1, 12, zf), (x0, 12, zf)], "WallD")
    # windows: ribbon pattern in three runs
    for (z0, z1) in ((6.5, 29.3), (30.8, 55.3), (56.8, 81.4)):
        glaze(b, PS, z0, z1, "Window", bay=3.0, gap=0.7, edge=0.8)
    for z in (30.0, 56.0):
        belt_ring(b, PS, z - 0.55, z + 0.55, 0.28, "Trim")
    belt_ring(b, PS, 81.4, 82.0, 0.3, "Trim")
    # magenta corner strips (all 4 vertical edges)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((cx + sx * 6.0, sy * 12.0, 44.2), (0.55, 0.55, 78.5), "Neon")
    b.box((cx, 12.0 if hi_front else -12.0, 88.0 + 0.1), (12.3, 0.35, 0.35), "Neon")      # glowing high edge of the wedge
    # roof plant + antenna on the lower end of the wedge
    ylow = -8.0 if hi_front else 8.0
    b.box((cx, ylow, 84.0), (5.0, 4.0, 2.4), "MetalDark")
    b.beam((cx, ylow, 85.0), (cx, ylow, 89.8), 0.2, 0.05, 4, "Metal")

# --- sky bridge (z 58..70) between the slabs
b.box((0, 0, 64.0), (12.6, 16.0, 12.0), "WallD")
glaze(b, rect_pts(0, 0, 12.6, 16.0), 59.6, 68.4, "Window", bay=2.6, gap=0.6, edge=0.7, skip=(1, 3))
belt_ring(b, rect_pts(0, 0, 12.6, 16.0), 69.2, 70.0, 0.3, "Trim")
belt_ring(b, rect_pts(0, 0, 12.6, 16.0), 58.0, 58.8, 0.3, "Trim")
# neon frame on the bridge faces + underside
for sy in (-1, 1):
    y = sy * 8.0
    b.box((0, y + sy * 0.2, 69.9), (12.2, 0.3, 0.35), "Neon")
    b.box((0, y + sy * 0.2, 58.2), (12.2, 0.3, 0.35), "Neon")
# knee braces under the bridge (arch look)
for sy in (-1, 1):
    y = sy * 7.4
    b.beam((-6.0, y, 47.0), (-1.0, y, 58.0), 0.38, 0.38, 4, "MetalDark")
    b.beam((6.0, y, 47.0), (1.0, y, 58.0), 0.38, 0.38, 4, "MetalDark")
b.box((0, 0, 57.6), (12.6, 2.0, 0.8), "MetalDark")

a.fin(b, "Body")
a.mark("Door", (0, 12.0, 0.0))
report(a)
