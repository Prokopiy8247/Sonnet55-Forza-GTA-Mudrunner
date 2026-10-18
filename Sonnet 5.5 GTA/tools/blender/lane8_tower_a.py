# lane 8 - tower_a: downtown glass skyscraper 28x28 m footprint, 110 m, stepped crown + spire, cyan band, helipad setback
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("tower_a", 0)
b = a.b("Body")
STRAIGHT_ONLY = (1, 3, 5, 7)     # chamfer edges stay solid piers

# --- plinth + podium (28 x 28, 14 m)
P1 = rect_pts(0, 0, 28, 28, 1.8)
shaft(b, inflate(P1, 0.25), 0, 1.0, "Concrete", "Concrete")
shaft(b, P1, 0.5, 14.0, "WallD", "Roof")
glaze(b, P1, 7.0, 13.0, "Window", bay=4.0, gap=0.8, edge=1.0, skip=STRAIGHT_ONLY)
glaze(b, P1, 1.2, 5.6, "Window", bay=4.0, gap=0.8, edge=1.0, skip=(0, 1, 3, 4, 5, 7))   # side ground glass
b.quad((8.0, 14.07, 1.2), (-8.0, 14.07, 1.2), (-8.0, 14.07, 5.8), (8.0, 14.07, 5.8), "Window")  # lobby glass front
for x in (-8.4, 8.4):
    b.box((x, 14.15, 3.5), (0.5, 0.3, 4.6), "Trim")
belt_ring(b, P1, 5.8, 6.7, 0.25, "Trim")          # podium mid band
belt_ring(b, P1, 13.0, 14.0, 0.3, "Trim")         # podium cornice
parapet(b, P1, 14.0, 14.9, 0.4, "WallD")
# lobby canopy + columns + cyan edge
b.box((0, 15.7, 6.3), (13.0, 3.0, 0.4), "Trim")
b.box((0, 17.2, 6.3), (13.0, 0.3, 0.25), "NeonCyan")
for x in (-5.5, 5.5):
    b.cyl((x, 16.8, 3.05), 0.28, 6.1, 8, "Metal", caps=False)

# --- tier 2 (z 14..54), glass with fins and belts
P2 = rect_pts(4.6, 0, 17.2, 24.0, 2.0)
shaft(b, P2, 14.0, 54.0, "WallC", "Roof")
for (z0, z1) in ((15.2, 25.4), (26.8, 37.4), (38.8, 48.6)):
    glaze(b, P2, z0, z1, "Window", bay=None, edge=0.9, skip=STRAIGHT_ONLY)
for z in (26.1, 38.1):
    belt_ring(b, P2, z - 0.55, z + 0.55, 0.28, "Trim")
fins(b, P2, 15.0, 49.0, 4.4, 0.5, 0.3, edge=1.4, skip=STRAIGHT_ONLY)
belt_ring(b, P2, 49.0, 54.0, 0.3, "WallD")        # mechanical floor
glaze(b, P2, 50.0, 53.0, "Trim", bay=1.2, gap=0.5, edge=1.2, skip=STRAIGHT_ONLY, out=0.32)   # louvre slats
belt_ring(b, P2, 53.2, 54.0, 0.45, "Trim")

# --- tier 3 (z 54..86)
P3 = rect_pts(6.0, 0, 13.4, 18.0, 1.6)
shaft(b, P3, 54.0, 86.0, "WallC", "Roof")
for (z0, z1) in ((55.4, 65.4), (66.8, 75.4), (76.8, 84.6)):
    glaze(b, P3, z0, z1, "Window", bay=None, edge=0.8, skip=STRAIGHT_ONLY)
for z in (66.1, 76.1):
    belt_ring(b, P3, z - 0.5, z + 0.5, 0.26, "Trim")
fins(b, P3, 55.0, 85.0, 4.2, 0.45, 0.28, edge=1.2, skip=STRAIGHT_ONLY)
belt_ring(b, P3, 85.0, 86.0, 0.4, "Trim")

# --- tier 4 (z 86..100) with the cyan band
P4 = rect_pts(6.0, 0, 10.0, 12.0, 1.4)
shaft(b, P4, 86.0, 100.0, "WallD", "Roof")
glaze(b, P4, 87.2, 95.4, "Window", bay=None, edge=0.7, skip=STRAIGHT_ONLY)
glaze(b, P4, 98.0, 99.4, "Window", bay=None, edge=0.7, skip=STRAIGHT_ONLY)
belt_ring(b, P4, 96.0, 97.6, 0.22, "NeonCyan")      # emissive cyan band
belt_ring(b, P4, 99.4, 100.0, 0.35, "Trim")

# --- crown: pyramid cap + spire
cx0, hx, hy = 6.0, 3.2, 4.0
hexa(b, [(cx0-hx,-hy,100.0),(cx0+hx,-hy,100.0),(cx0+hx,hy,100.0),(cx0-hx,hy,100.0)],
        [(cx0-1.3,-1.6,105.0),(cx0+1.3,-1.6,105.0),(cx0+1.3,1.6,105.0),(cx0-1.3,1.6,105.0)], "WallD")
belt_ring(b, rect_pts(6.0, 0, 6.4, 8.0, 0), 100.0, 100.7, 0.12, "NeonCyan")
b.beam((6.0, 0, 105.0), (6.0, 0, 109.7), 0.4, 0.07, 6, "Metal")
b.sphere((6.0, 0, 109.85), 0.26, 6, 4, "LightRed")
for sx in (-1, 1):
    for sy in (-1, 1):
        b.beam((6.0 + sx * 2.9, sy * 3.7, 100.0), (6.0 + sx * 0.9, sy * 1.2, 106.5), 0.15, 0.05, 4, "Metal")

# --- setback roofs: mechanical bits + helipad (podium roof, x -14..-4)
b.box((9.5, 8.0, 54.9), (3.0, 2.2, 1.8), "MetalDark")            # roof plant on tier2 ledge
b.box((9.5, -8.0, 54.8), (3.0, 2.2, 1.6), "MetalDark")
b.box((-2.4, 0, 54.7), (1.0, 6.0, 1.4), "Metal")
b.box((9.0, 0.0, 86.8), (3.4, 4.0, 1.6), "MetalDark")           # tier3 roof plant
b.cyl((-9.0, 0.0, 14.1), 4.9, 0.2, 24, "MetalDark")             # helipad disc
b.cyl((-9.0, 0.0, 14.22), 4.5, 0.06, 24, "Concrete", caps=True)
for (cx, cy, sx, sy) in ((-10.0, 0.0, 0.5, 3.4), (-8.0, 0.0, 0.5, 3.4), (-9.0, 0.0, 2.5, 0.5)):   # white H
    b.box((cx, cy, 14.3), (sx, sy, 0.1), "WallA")
for i in range(16):                                              # perimeter lights
    ang = 2 * math.pi * i / 16
    b.box((-9.0 + 4.7 * math.cos(ang), 4.7 * math.sin(ang), 14.3), (0.22, 0.22, 0.2), "LightAmber")
obj_body = a.fin(b, "Body")

a.mark("Door", (0, 14.2, 0.0), display="ARROWS")
a.mark("RoofHelipad", (-9.0, 0.0, 14.3), display="CIRCLE", size=4.0)
report(a)
