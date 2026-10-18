# lane 8 - pier_hut: small dock building 8 x 6 m on a timber deck with piles, porch, BAIT neon sign
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("pier_hut", 16)
b = a.b("Body")
DZ = 0.3                     # deck top height

# ---- deck, planks, piles
b.box((0, 0, DZ / 2), (8.0, 6.0, DZ), "Wood")
for k in range(11):
    b.box((0, -2.75 + k * 0.55, DZ + 0.01), (7.9, 0.04, 0.03), "Bark")
for (x, y) in ((-3.7, -2.7), (0.0, -2.7), (3.7, -2.7), (-3.7, 2.7), (0.0, 2.7), (3.7, 2.7), (-3.7, 0.0), (3.7, 0.0)):
    b.cyl((x, y, -0.55), 0.22, 1.75, 6, "Bark", r_top=0.2)
    b.cyl((x, y, DZ + 0.05), 0.3, 0.1, 6, "MetalDark")
b.box((0, 0, -0.1), (7.6, 0.25, 0.25), "Bark")       # cross beam under the deck

# ---- hut body (walls + gable infill as one profile) + roof over body and porch
YW0, YW1 = -2.4, 1.6
ZE, ZR = 2.8, 4.2
YR1 = 3.0
YM = (YW0 + YR1) / 2
m = (ZR - ZE) / (YM - YW0)
zr_at = lambda y: ZR - m * (y - YM)
extrude_x(b, [(YW0, DZ), (YW1, DZ), (YW1, zr_at(YW1)), (YM, ZR), (YW0, ZE)], -3.4, 3.4, "WallC")
extrude_x(b, roof_prof(YW0, YR1, ZE, ZR, 0.55, 0.22), -4.0, 4.0, "RoofTile")
b.box((0, YM, ZR + 0.25), (8.0, 0.3, 0.14), "Wood")        # ridge cap
# corner posts + base board
for sx in (-1, 1):
    for sy, yy in ((-1, YW0), (1, YW1)):
        b.box((sx * 3.4, yy, (DZ + ZE) / 2 + 0.05), (0.22, 0.22, ZE - DZ), "Wood")
b.box((0, YW1 + 0.03, DZ + 0.25), (6.8, 0.08, 0.5), "WallA")
# board lines on the front wall
for k in (0, 2, 4):
    b.box((0, YW1 + 0.03, 0.9 + k * 0.3), (6.7, 0.03, 0.05), "Trim")

# ---- door, windows, shutters, sign
b.box((0, YW1 + 0.04, DZ + 1.0), (1.1, 0.1, 2.0), "Wood")
b.box((0, YW1 + 0.07, DZ + 2.05), (1.4, 0.14, 0.14), "Trim")
b.box((0.35, YW1 + 0.12, DZ + 1.0), (0.08, 0.08, 0.14), "MetalDark")
for x in (-2.3, 2.3):
    b.quad((x + 0.55, YW1 + 0.04, 1.2), (x - 0.55, YW1 + 0.04, 1.2), (x - 0.55, YW1 + 0.04, 2.2), (x + 0.55, YW1 + 0.04, 2.2), "Window")
    b.box((x, YW1 + 0.06, 1.2 - 0.05), (1.3, 0.1, 0.1), "Wood")
    b.box((x - 0.78, YW1 + 0.08, 1.7), (0.3, 0.06, 1.2), "WallB")
    b.box((x + 0.78, YW1 + 0.08, 1.7), (0.3, 0.06, 1.2), "WallB")
for sx in (-1, 1):
    b.quad((sx * 3.41, -0.2 if sx > 0 else 1.0, 1.2), (sx * 3.41, 1.0 if sx > 0 else -0.2, 1.2), (sx * 3.41, 1.0 if sx > 0 else -0.2, 2.2), (sx * 3.41, -0.2 if sx > 0 else 1.0, 2.2), "Window")
b.box((0, 3.12, 2.2), (1.9, 0.1, 0.55), "Trim")
b.beam((-0.8, 3.1, 2.48), (-0.8, 3.1, 2.62), 0.02, 0.02, 4, "Metal")
b.beam((0.8, 3.1, 2.48), (0.8, 3.1, 2.62), 0.02, 0.02, 4, "Metal")
txt = "BAIT"
h = 0.38
lw = 3 * h / 5
gx = 0.14
tot = 4 * lw + 3 * gx
x_cur = tot / 2
for ch in txt:
    letter(b, ch, (x_cur, 3.17, 2.2 - h / 2), (-1, 0, 0), (0, 0, 1), (0, 1, 0), h, 0.1, "NeonCyan")
    x_cur -= lw + gx

# ---- porch posts, lantern, rope rail
for sx in (-1, 1):
    b.box((sx * 3.5, 2.8, (DZ + 2.8) / 2), (0.2, 0.2, 2.5), "Wood")
    b.box((sx * 3.5, 2.8, 1.1), (0.12, 0.12, 0.1), "Wood")
b.beam((-3.5, 2.8, 1.0), (-0.9, 2.8, 0.85), 0.04, 0.04, 4, "Wood")
b.beam((3.5, 2.8, 1.0), (0.9, 2.8, 0.85), 0.04, 0.04, 4, "Wood")
b.beam((-1.6, 2.7, 2.8), (-1.6, 2.7, 2.35), 0.02, 0.02, 4, "Metal")
b.sphere((-1.6, 2.7, 2.22), 0.16, 6, 4, "LampGlow")
b.beam((1.6, 2.7, 2.8), (1.6, 2.7, 2.35), 0.02, 0.02, 4, "Metal")
b.sphere((1.6, 2.7, 2.22), 0.16, 6, 4, "LampGlow")

# ---- props on the deck: crates, barrels, bollards, coiled rope, ladder to the water
for (x, y, z, s) in ((-3.0, 2.2, DZ + 0.3, 0.6), (-2.3, 2.3, DZ + 0.3, 0.55), (-2.7, 2.2, DZ + 0.9, 0.5)):
    b.box((x, y, z), (s, s, s), "Wood")
    b.box((x, y, z), (s + 0.03, s + 0.03, 0.06), "Trim")
for (x, y) in ((3.0, 2.2), (2.45, 2.55)):
    b.cyl((x, y, DZ + 0.4), 0.3, 0.8, 8, "CranePaint", r_top=0.28)
    b.cyl((x, y, DZ + 0.6), 0.31, 0.06, 8, "Metal")
for (x, y) in ((-3.7, 2.7), (3.7, 2.7)):
    b.cyl((x, y, DZ + 0.3), 0.14, 0.6, 6, "Metal")
    b.cyl((x, y, DZ + 0.62), 0.2, 0.1, 6, "Metal")
b.cyl((2.2, -2.2, DZ + 0.1), 0.4, 0.2, 10, "Bark")                    # rope coil
b.cyl((2.2, -2.2, DZ + 0.2), 0.42, 0.04, 10, "Trim")
for sx in (-0.3, 0.3):
    b.beam((3.95 + 0.0, -1.2 + sx, DZ), (3.95, -1.2 + sx, -1.6), 0.04, 0.04, 4, "Metal")
for z in (0.0, -0.5, -1.0):
    b.beam((3.95, -1.5, z), (3.95, -0.9, z), 0.03, 0.03, 4, "Metal")

a.fin(b, "Body")
a.mark("Door", (0, YW1 + 0.2, DZ))
report(a)
