# lane 8 - hotel: neon hotel 22 x 18 m, 14 floors, big vertical HOTEL neon signs, porte-cochere, empty Door
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("hotel", 8)
b = a.b("Body")
YF, YB = 5.0, -9.0            # body front/back
ZG, FH, NF = 5.0, 3.5, 13     # ground floor height, floor height, upper floors
ZT = ZG + FH * NF             # 50.5
BP = rect_pts(0, (YF + YB) / 2, 22.0, YF - YB, 0.0)

# ---- plinth + body
shaft(b, inflate(BP, 0.25), 0, 0.5, "Concrete", "Concrete")
shaft(b, BP, 0.3, ZT, "WallB", "Roof")
# ground floor: darker podium wall + lobby glass
belt_ring(b, BP, 0.3, ZG, 0.12, "WallD")
b.quad((9.5, YF + 0.15, 0.6), (-9.5, YF + 0.15, 0.6), (-9.5, YF + 0.15, 4.2), (9.5, YF + 0.15, 4.2), "Window")
for x in (-9.5, -4.8, 0.0, 4.8, 9.5):
    b.box((x, YF + 0.2, 2.4), (0.35, 0.3, 3.8), "Trim")
b.box((0, YF + 0.2, 4.3), (19.4, 0.3, 0.3), "Trim")
b.box((-1.0, YF + 0.22, 1.5), (1.8, 0.1, 2.3), "Glass")
b.box((1.0, YF + 0.22, 1.5), (1.8, 0.1, 2.3), "Glass")
# side/back ground glazing
glaze(b, BP, 0.9, 3.8, "Window", bay=4.0, gap=1.0, edge=1.5, skip=(2,))
# floors: window rows + balcony slabs on the front
for f in range(NF):
    zf = ZG + FH * f
    glaze(b, BP, zf + 0.9, zf + 2.7, "Window", bay=2.6, gap=0.9, edge=1.1)
for f in range(1, NF + 1):
    zf = ZG + FH * f
    b.box((0, YF + 0.35, zf - 0.1), (22.4, 0.8, 0.2), "WallA")
    if f < NF:
        b.box((0, YF + 0.7, zf + 0.35), (22.0, 0.08, 0.7), "Glass")     # glass balustrade
b.box((0, YF + 0.35, ZG - 0.1), (22.4, 0.8, 0.2), "WallA")
# crown: neon outline + parapet + roof kit
parapet(b, BP, ZT, ZT + 1.1, 0.4, "WallA")
belt_ring(b, BP, ZT + 0.6, ZT + 0.95, 0.12, "NeonCyan")
for sx in (-1, 1):
    b.box((sx * 11.0, YF, ZT / 2 + 0.2), (0.5, 0.5, ZT - 0.6), "Neon")             # magenta front corner strips
    b.box((sx * 11.0, YB, ZT / 2 + 0.2), (0.5, 0.5, ZT - 0.6), "NeonCyan")          # cyan back corner strips
b.box((-4.0, -4.0, ZT + 2.0), (5.0, 4.5, 2.6), "MetalDark")                           # lift motor room
b.box((5.0, -6.0, ZT + 1.5), (3.6, 3.0, 1.6), "MetalDark")
b.cyl((6.0, 0.0, ZT + 2.6), 1.9, 3.0, 10, "Metal")                                      # water tank
b.cyl((6.0, 0.0, ZT + 4.5), 1.95, 0.4, 10, "Trim", r_top=0.3)
b.beam((-4.0, -4.0, ZT + 3.3), (-4.0, -4.0, ZT + 9.0), 0.25, 0.05, 4, "Metal")
b.sphere((-4.0, -4.0, ZT + 9.1), 0.22, 6, 4, "LightRed")

# ---- porte-cochere (canopy + columns + lights)
b.box((0, 7.2, 5.0), (11.6, 4.4, 0.45), "Trim")
b.box((0, 9.4, 5.0), (11.6, 0.2, 0.3), "NeonCyan")
b.box((0, 7.2, 4.74), (9.0, 3.2, 0.08), "Neon")
for x in (-5.2, 5.2):
    b.cyl((x, 8.9, 2.5), 0.28, 5.0, 8, "Chrome", caps=False)
for x in (-3.0, 0.0, 3.0):
    b.sphere((x, 7.2, 4.5), 0.22, 6, 4, "LampGlow")
b.box((0, 7.2, 0.1), (12.0, 4.6, 0.2), "Concrete")                                   # forecourt pad

# ---- vertical neon sign 1: facade-mounted, facing +Y (front-left of the facade)
SX = -7.6
sign_z0, sign_z1 = 24.0, 47.5
b.box((SX, YF + 0.75, (sign_z0 + sign_z1) / 2), (3.7, 0.5, sign_z1 - sign_z0), "Trim")
for dx in (-1.9, 1.9):
    b.box((SX + dx, YF + 1.05, (sign_z0 + sign_z1) / 2), (0.16, 0.14, sign_z1 - sign_z0 + 0.16), "NeonCyan")
for dz in (sign_z0 - 0.08, sign_z1 + 0.08):
    b.box((SX, YF + 1.05, dz), (3.7 + 0.16, 0.14, 0.16), "NeonCyan")
LH, LG = 3.0, 0.8
text_v(b, "HOTEL", (SX + 3 * LH / 5 / 2, YF + 1.0, sign_z1 - 0.9 - LH), (-1, 0, 0), (0, 0, 1), (0, 1, 0), LH, LG, 0.3, "Neon")

# ---- vertical neon sign 2: perpendicular blade, readable from both sides (front-right)
BX = 9.2
bz0, bz1 = 18.0, 41.5
b.box((BX, YF + 2.4, (bz0 + bz1) / 2), (0.5, 4.6, bz1 - bz0), "Trim")
b.box((BX, YF + 0.4, bz1 - 1.0), (0.7, 1.0, 0.4), "Metal")
b.box((BX, YF + 0.4, bz0 + 1.0), (0.7, 1.0, 0.4), "Metal")
b.beam((BX, YF + 0.3, bz0 - 1.2), (BX, YF + 3.2, bz0), 0.12, 0.12, 4, "Metal")
for dy in (0.15, 4.65):
    b.box((BX, YF + dy, (bz0 + bz1) / 2), (0.6, 0.14, bz1 - bz0 + 0.14), "NeonCyan")
for dz in (bz0 - 0.07, bz1 + 0.07):
    b.box((BX, YF + 2.4, dz), (0.6, 4.6, 0.14), "NeonCyan")
text_v(b, "HOTEL", (BX + 0.25, YF + 2.4 - 3 * LH / 5 / 2, bz1 - 0.8 - LH), (0, 1, 0), (0, 0, 1), (1, 0, 0), LH, LG, 0.25, "Neon")
text_v(b, "HOTEL", (BX - 0.25, YF + 2.4 + 3 * LH / 5 / 2, bz1 - 0.8 - LH), (0, -1, 0), (0, 0, 1), (-1, 0, 0), LH, LG, 0.25, "Neon")

a.fin(b, "Body")
a.mark("Door", (0, YF + 0.3, 0.0))
report(a)
