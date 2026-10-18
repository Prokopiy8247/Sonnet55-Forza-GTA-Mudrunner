"""lane7 safehouse: hero apartment block 16 x 14 m, 4 floors, warm stucco, shutters + balconies, rooftop terrace, side garage."""
A = Asset("safehouse", 4)
b = HB("safehouse_body")

X0, X1, Y0, Y1 = -8.0, 5.4, -7.0, 5.6        # body (driveway strip x 5.4..8, balconies reach y 7.0)
FZ = [0.0, 3.8, 7.2, 10.6, 14.0]
TOP = 14.0
CXB = (X0 + X1) / 2
CYB = (Y0 + Y1) / 2
HXB = (X1 - X0) / 2
HYB = (Y1 - Y0) / 2
ST, STD, TW, SH, TERRA = "Stucco", "StuccoDk", "TrimWhite", "ShutterTeal", "Terracotta"

F = Side(b, "F", CXB, CYB, HXB, HYB)
Bk = Side(b, "B", CXB, CYB, HXB, HYB)
Lw = Side(b, "L", CXB, CYB, HXB, HYB)
Rw = Side(b, "R", CXB, CYB, HXB, HYB)

COLX = [CXB - 4.4, CXB, CXB + 4.4]          # three window columns on the front
# ---------------------------------------------------------------- front facade
door = (-1.05, 1.05, 0.0, 2.6)
rows_f = []
for fl in (1, 2, 3):
    rows_f.append((FZ[fl] + 0.35, FZ[fl] + 2.75))
holes = [(F.u(x) - 0.85, F.u(x) + 0.85, v0, v1) for x in COLX for (v0, v1) in rows_f]
gl = [(F.u(x) - 0.8, F.u(x) + 0.8, 0.9, 2.7) for x in (COLX[0], COLX[2])]          # ground-floor windows beside the door
F.wall(-HXB, HXB, 0, TOP, holes + gl + [door], ST)
for h in holes:
    F.win(h, depth=0.28, frame=TW, sill=0.3, sill_m=STD)
    w_ = h[1] - h[0]
    for s_ in (-1, 1):
        uu = (h[0] - 0.42) if s_ < 0 else (h[1] + 0.42)
        F.box(uu - 0.38, uu + 0.38, h[2], h[3], 0.0, 0.08, SH, skip="ib")
        for k in range(1, 4):
            v = h[2] + (h[3] - h[2]) * k / 4
            F.q(uu - 0.38, uu + 0.38, v, v + 0.05, 0.085, "Trim")
for h in gl:
    F.win(h, depth=0.28, frame=TW, sill=0.3, sill_m=STD)
    for k in range(1, 5):                       # window grille
        u = h[0] + (h[1] - h[0]) * k / 5
        F.box(u - 0.03, u + 0.03, h[2], h[3], -0.08, -0.02, "MetalDark", skip="ibt")
# entrance
F.reveal(door, 0.5, TW, "lrt")
F.q(door[0], door[1], 0, 2.6, -0.5, "Wood")
F.q(-0.03, 0.03, 0, 2.6, -0.47, "Trim")
for s_ in (-0.5, 0.5):
    F.q(s_ - 0.3, s_ + 0.3, 1.0, 2.3, -0.47, "Window")
F.box(-1.5, 1.5, 2.65, 3.0, 0.0, 0.35, TW, skip="ib")
# awning over the door (tiled)
b.pq([(CXB - 1.7, 5.6, 3.4), (CXB + 1.7, 5.6, 3.4), (CXB + 1.7, 7.0, 2.85), (CXB - 1.7, 7.0, 2.85)], (0, 0.4, 1), TERRA)
for sx in (-1.7, 1.7):
    b.pq([(CXB + sx, 5.6, 3.4), (CXB + sx, 7.0, 2.85), (CXB + sx, 5.6, 2.85)], (sx, 0, 0), STD)
b.pq([(CXB - 1.7, 7.0, 2.85), (CXB + 1.7, 7.0, 2.85), (CXB + 1.7, 7.0, 2.6), (CXB - 1.7, 7.0, 2.6)], (0, 1, 0), STD)
b.abox(CXB - 2.2, CXB + 2.2, 5.6, 7.0, 0.0, 0.1, "Concrete", "-z -y")        # step / stoop
# plinth + floor bands
b.abox(X0 - 0.1, X1 + 0.1, Y0 - 0.1, Y1 + 0.1, 0.0, 0.7, STD, "-z")
for fl in (1, 2, 3):
    b.abox(X0 - 0.12, X1 + 0.12, Y0 - 0.12, Y1 + 0.12, FZ[fl] - 0.12, FZ[fl] + 0.12, TW)

# ---------------------------------------------------------------- balconies
def balcony(xc, z, w=3.2, d=1.3):
    ye = Y1 + d
    b.abox(xc - w / 2, xc + w / 2, Y1, ye, z - 0.28, z, STD)
    for sx in (-w / 2 + 0.05, w / 2 - 0.05):
        b.abox(xc + sx - 0.05, xc + sx + 0.05, ye - 0.1, ye, z, z + 1.0, "MetalDark", "-z +z -y")
    b.abox(xc - w / 2, xc + w / 2, ye - 0.08, ye, z + 0.96, z + 1.04, "MetalDark", "-z -y")
    b.abox(xc - w / 2, xc + w / 2, ye - 0.08, ye, z + 0.08, z + 0.14, "MetalDark", "-z -y")
    for k in range(1, 8):
        x = xc - w / 2 + w * k / 8
        b.pq([(x - 0.025, ye, z + 0.14), (x + 0.025, ye, z + 0.14), (x + 0.025, ye, z + 0.96), (x - 0.025, ye, z + 0.96)], (0, 1, 0), "MetalDark")
        b.pq([(x - 0.025, ye, z + 0.14), (x + 0.025, ye, z + 0.14), (x + 0.025, ye, z + 0.96), (x - 0.025, ye, z + 0.96)], (0, -1, 0), "MetalDark")
    for s_ in (-1, 1):
        xs = xc + s_ * (w / 2 - 0.03)
        b.abox(xs - 0.03, xs + 0.03, Y1, ye, z + 0.96, z + 1.02, "MetalDark", "-z -y +y")
        for k in (1, 2):
            y = Y1 + d * k / 3
            b.pq([(xs, y - 0.025, z + 0.14), (xs, y + 0.025, z + 0.14), (xs, y + 0.025, z + 0.96), (xs, y - 0.025, z + 0.96)], (s_, 0, 0), "MetalDark")
            b.pq([(xs, y - 0.025, z + 0.14), (xs, y + 0.025, z + 0.14), (xs, y + 0.025, z + 0.96), (xs, y - 0.025, z + 0.96)], (-s_, 0, 0), "MetalDark")

balcony(COLX[0], FZ[1] + 0.0)
balcony(COLX[2], FZ[1] + 0.0)
balcony(COLX[1], FZ[2] + 0.0)
balcony(COLX[0], FZ[3] + 0.0)
balcony(COLX[2], FZ[3] + 0.0)

# ---------------------------------------------------------------- back + sides
hb = [(u - 0.8, u + 0.8, v0, v1) for u in (-4.4, 0.0, 4.4) for (v0, v1) in [(0.9, 2.7)] + rows_f]
Bk.openings(-HXB, HXB, 0, TOP, hb, ST, depth=0.22, frame=TW)
hl = [(u - 0.7, u + 0.7, v0, v1) for u in (-4.2, 0.0, 4.2) for (v0, v1) in [(0.9, 2.7)] + rows_f]
Lw.openings(-HYB, HYB, 0, TOP, hl, ST, depth=0.22, frame=TW)
gdoor = (-1.9, 1.7, 0.0, 2.8)          # garage door on the +X side (u = y - cy)
hr = [(u - 0.7, u + 0.7, v0, v1) for u in (-4.2, 0.0, 4.2) for (v0, v1) in rows_f]
Rw.wall(-HYB, HYB, 0, TOP, hr + [gdoor] + [(u - 0.7, u + 0.7, 0.9, 2.7) for u in (-4.5, 4.4)], ST)
Rw.wins(hr + [(u - 0.7, u + 0.7, 0.9, 2.7) for u in (-4.5, 4.4)], depth=0.22, frame=TW)
Rw.reveal(gdoor, 0.35, TW, "lrt")
Rw.q(gdoor[0], gdoor[1], 0, 2.8, -0.35, "Metal")
for k in range(8):
    v = 0.3 + k * 0.33
    Rw.q(gdoor[0] + 0.1, gdoor[1] - 0.1, v, v + 0.06, -0.32, "MetalDark")
Rw.box(gdoor[0] - 0.15, gdoor[1] + 0.15, 2.85, 3.2, 0.0, 0.3, TW, skip="ib")
b.zq(TOP, X0, X1, Y0, Y1, 1, "Concrete")

# eaves + parapet with tile coping
b.abox(X0 - 0.3, X1 + 0.3, Y0 - 0.3, Y1 + 0.3, TOP - 0.45, TOP, STD, "-z")
parapet(b, X0 - 0.3, X1 + 0.3, Y0 - 0.3, Y1 + 0.3, TOP, TOP + 1.05, 0.28, ST)
parapet(b, X0 - 0.38, X1 + 0.38, Y0 - 0.38, Y1 + 0.38, TOP + 1.05, TOP + 1.2, 0.4, TERRA)

# ---------------------------------------------------------------- rooftop terrace
# pergola (front-left)
px0, px1, py0, py1 = X0 + 0.8, X0 + 5.0, Y1 - 3.8, Y1 - 0.8
for (x, y) in ((px0, py0), (px1, py0), (px0, py1), (px1, py1)):
    b.abox(x - 0.1, x + 0.1, y - 0.1, y + 0.1, TOP, TOP + 2.6, "Wood", "-z")
b.abox(px0 - 0.2, px1 + 0.2, py0 - 0.1, py0 + 0.1, TOP + 2.6, TOP + 2.8, "Wood", "-z")
b.abox(px0 - 0.2, px1 + 0.2, py1 - 0.1, py1 + 0.1, TOP + 2.6, TOP + 2.8, "Wood", "-z")
for k in range(8):
    x = px0 + (px1 - px0) * k / 7
    b.abox(x - 0.06, x + 0.06, py0, py1, TOP + 2.8, TOP + 2.88, "Wood", "-z")
for k in range(5):
    x = px0 + (px1 - px0) * (k + 0.5) / 5
    b.cbox((x, py1 - 0.0, TOP + 2.5), (0.12, 0.12, 0.12), "LampGlow")
# lounge chairs + table + planters
for (x, y) in ((px0 + 1.0, py0 + 1.2), (px0 + 2.4, py0 + 1.2)):
    b.abox(x - 0.4, x + 0.4, y - 0.9, y + 0.9, TOP, TOP + 0.35, "AwningCoral", "-z")
    b.pq([(x - 0.4, y + 0.3, TOP + 0.35), (x + 0.4, y + 0.3, TOP + 0.35), (x + 0.4, y + 0.9, TOP + 0.9), (x - 0.4, y + 0.9, TOP + 0.9)], (0, -0.5, 1), "AwningCoral")
b.cyl((px1 - 0.9, py0 + 1.2, TOP + 0.3), 0.5, 0.6, 6, "Metal", caps="t")
for (x, y, s_) in ((X1 - 1.2, Y1 - 1.0, 1.0), (X0 + 1.0, Y0 + 1.0, 0.9), (X1 - 1.0, Y0 + 1.2, 1.0)):
    b.abox(x - 0.5 * s_, x + 0.5 * s_, y - 0.5 * s_, y + 0.5 * s_, TOP, TOP + 0.5, "Terracotta", "-z")
    b.ball((x, y, TOP + 0.95), 0.62 * s_, 6, 3, "Leaf", sc=(1, 1, 1.0))
# stair house + water tank
b.abox(0.5, 4.5, Y0 + 0.8, Y0 + 3.8, TOP, TOP + 2.7, ST, "-z")
b.hip(0.2, 4.8, Y0 + 0.5, Y0 + 4.1, TOP + 2.7, 0.9, 0.4, 0.3, TERRA, "-z")
b.yq(Y0 + 3.82, 1.6, 3.0, TOP, TOP + 2.1, 1, "Wood")
for sx in (-0.9, 0.9):
    for sy in (-0.9, 0.9):
        b.beam((-3.5 + sx, Y0 + 2.4 + sy, TOP), (-3.5 + sx, Y0 + 2.4 + sy, TOP + 1.3), 0.07, 0.07, 4, "Metal", caps=False)
b.cyl((-3.5, Y0 + 2.4, TOP + 2.0), 1.2, 1.5, 8, "MetalDark", caps="t")
b.cyl((-3.5, Y0 + 2.4, TOP + 2.85), 1.2, 0.2, 8, "Metal", r_top=0.3, caps="t")
# solar / sat dish
b.cyl((X1 - 3.0, Y1 - 3.5, TOP + 0.8), 0.7, 0.12, 8, "TrimWhite", axis="Y", r_top=0.3, caps="t")
b.beam((X1 - 3.0, Y1 - 3.45, TOP), (X1 - 3.0, Y1 - 3.45, TOP + 0.8), 0.04, 0.04, 4, "Metal")

# ---------------------------------------------------------------- driveway + gate pillars + hedge
b.abox(X1, 8.0, -4.5, 2.0, 0.0, 0.06, "ConcreteDk", "-z -x")
for yy in (-4.6, 2.1):
    b.abox(7.5, 8.0, yy - 0.25, yy + 0.25, 0.0, 1.5, STD, "-z")
    b.cbox((7.75, yy, 1.62), (0.7, 0.7, 0.12), TERRA, "-z")
    b.cbox((7.75, yy, 1.78), (0.2, 0.2, 0.2), "LampGlow")
b.abox(5.55, 7.5, Y0, Y0 + 0.4, 0.0, 1.1, STD, "-z")
for x in (-6.5, -2.5, 1.5, 4.5):
    b.abox(x - 0.8, x + 0.8, Y1 + 0.2, Y1 + 0.8, 0.0, 0.55, "Leaf", "-z") if abs(x - CXB) > 2.3 else None

A.mesh(b, "Body")

c = HB("safehouse_col")
c.abox(X0, X1, Y0, Y1, 0, TOP + 1.2, "Concrete", "-z")
c.abox(X1, 8.0, Y0, Y0 + 0.4, 0, 1.1, "Concrete", "-z")
for yy in (-4.6, 2.1):
    c.abox(7.5, 8.0, yy - 0.25, yy + 0.25, 0, 1.5, "Concrete", "-z")
A.mesh(c, "Collision", uv=None, winuv=False)

A.mark("Door", (CXB, 6.5, 0.0))
A.mark("GarageDoor", (6.7, -0.1, 0.0))
rep = A.report()
