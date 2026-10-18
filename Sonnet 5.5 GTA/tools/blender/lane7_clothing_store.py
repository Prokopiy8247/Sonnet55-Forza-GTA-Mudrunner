"""lane7 clothing_store: 12 x 14 m fashion boutique, glass storefront with mannequins, striped awning, neon hanger sign."""
A = Asset("clothing_store", 6)
b = HB("clothing_store_body")

X0, X1, Y0, Y1 = -6.0, 6.0, -7.0, 6.0
GZ, TOP = 4.6, 8.4
CY = (Y0 + Y1) / 2
HY = (Y1 - Y0) / 2
PLUM, WHT, CORAL = "PlumDk", "TrimWhite", "AwningCoral"
F = Side(b, "F", 0, CY, 6, HY)
Bk = Side(b, "B", 0, CY, 6, HY)
Lw = Side(b, "L", 0, CY, 6, HY)
Rw = Side(b, "R", 0, CY, 6, HY)

# ---------------------------------------------------------------- front: storefront + upper floor
panes = [(-5.7, -1.5, 0.25, 3.8), (1.5, 5.7, 0.25, 3.8)]
door = (-1.3, 1.3, 0.0, 2.9)
F.wall(-6, 6, 0, GZ, panes + [door], PLUM)
for h in panes:
    F.reveal(h, 0.2, "MetalDark", "lrt")
    F.q(h[0], h[1], h[2], h[3], -0.2, "Glass")
    for k in (1, 2, 3):
        u = h[0] + (h[1] - h[0]) * k / 4
        F.q(u - 0.035, u + 0.035, h[2], h[3], -0.18, "MetalDark")
F.reveal(door, 0.3, "MetalDark", "lrt")
F.q(door[0], door[1], 0, 2.9, -0.3, "Glass")
F.q(-0.04, 0.04, 0, 2.9, -0.28, "MetalDark")
F.q(door[0], door[1], 1.0, 1.06, -0.28, "MetalDark")
F.box(0.18, 0.28, 0.9, 1.5, -0.3, -0.18, "Chrome", skip="ibt")
F.q(-6, 6, 3.85, 4.5, 0.02, PLUM)
F.q(-6, 6, 4.2, 4.28, 0.04, "LampGlow")
upper_win = [(u - 0.9, u + 0.9, 5.5, 7.6) for u in (-4.4, 4.4)]
F.wall(-6, 6, GZ, TOP, upper_win, WHT)
F.wins(upper_win, depth=0.25, frame=PLUM, sill=0.3, sill_m=CORAL)
F.q(-2.3, 2.3, 4.95, 7.85, 0.02, PLUM)
F.box(-2.4, 2.4, 4.9, 4.98, 0.0, 0.1, CORAL, skip="ib")
F.box(-2.4, 2.4, 7.85, 7.93, 0.0, 0.1, CORAL, skip="ib")
# neon hanger
hang = [((0.0, 7.05), (0.0, 6.55)), ((0.0, 6.55), (-1.55, 5.45)), ((0.0, 6.55), (1.55, 5.45)), ((-1.55, 5.45), (1.55, 5.45))]
for (p0, p1) in hang:
    F.stroke(p0, p1, 0.14, 0.07, "Neon")
prev = None
for k in range(7):
    a = math.radians(200 - k * 250 / 6)
    pt = (0.17 + 0.22 * math.cos(a), 7.27 + 0.22 * math.sin(a))
    if prev is not None:
        F.stroke(prev, pt, 0.11, 0.07, "Neon")
    prev = pt
# cornice between floors, bands
b.abox(X0 - 0.2, X1 + 0.2, Y0 - 0.2, Y1 + 0.2, GZ, GZ + 0.3, WHT)
for S in (Lw, Rw, Bk):
    S.q(-S.half, S.half, 0.0, 0.8, 0.03, PLUM)
    S.q(-S.half, S.half, 4.1, 4.5, 0.03, CORAL)
awning(b, -5.9, 5.9, Y1, GZ - 0.1, 1.0, 0.7, 10, CORAL, "AwningWhite")
b.abox(-1.6, 1.6, Y1, Y1 + 1.0, 0.0, 0.1, "Concrete", "-z -y")

# ---------------------------------------------------------------- sides + back
sh = [(u - 1.0, u + 1.0, 5.5, 7.6) for u in (-3.5, 0.0, 3.5)]
for S in (Lw, Rw):
    S.openings(-HY, HY, 0, TOP, sh + [(-4.5, -2.5, 1.0, 3.3), (2.5, 4.5, 1.0, 3.3)], WHT, depth=0.2, frame=PLUM)
hb = sh + [(u - 0.7, u + 0.7, 1.2, 3.2) for u in (-3.5, 3.5)]
bdoor = (-0.8, 0.8, 0.0, 2.4)
Bk.wall(-6, 6, 0, TOP, hb + [bdoor], WHT)
Bk.wins(hb, depth=0.2, frame=PLUM)
Bk.reveal(bdoor, 0.3, PLUM, "lrt")
Bk.q(-0.8, 0.8, 0, 2.4, -0.3, "MetalDark")
b.zq(TOP, X0, X1, Y0, Y1, 1, "Roof")
b.abox(X0 - 0.2, X1 + 0.2, Y0 - 0.2, Y1 + 0.2, TOP - 0.3, TOP + 0.08, WHT, "-z")
parapet(b, X0 - 0.2, X1 + 0.2, Y0 - 0.2, Y1 + 0.2, TOP + 0.08, TOP + 0.9, 0.28, WHT)
# stepped pediment on the front parapet
b.abox(-3.2, 3.2, Y1 + 0.2 - 0.3, Y1 + 0.2, TOP + 0.9, TOP + 1.7, CORAL, "-z")
b.abox(-1.8, 1.8, Y1 + 0.2 - 0.3, Y1 + 0.2, TOP + 1.7, TOP + 2.3, CORAL, "-z")
b.yq(Y1 + 0.21, -3.0, 3.0, TOP + 1.2, TOP + 1.3, 1, "Neon")
b.yq(Y1 + 0.21, -1.6, 1.6, TOP + 1.9, TOP + 2.0, 1, "Neon")
ac_unit(b, -3.0, -3.0, TOP, 2.2, 1.6, 1.1)
ac_unit(b, 3.0, -4.5, TOP, 2.2, 1.6, 1.1)

# ---------------------------------------------------------------- interior seen through the glass
SY = 2.6
b.zq(0.15, X0 + 0.3, X1 - 0.3, SY, Y1 - 0.2, 1, "Wood")
b.yq(SY, X0 + 0.3, X1 - 0.3, 0.15, GZ - 0.1, 1, PLUM)
b.zq(GZ - 0.1, X0 + 0.3, X1 - 0.3, SY, Y1 - 0.2, -1, WHT)
for y in (3.6, 5.0):
    b.zq(GZ - 0.11, X0 + 1.0, X1 - 1.0, y - 0.15, y + 0.15, -1, "LampGlow")
for z in (1.25, 2.35):
    b.abox(X0 + 0.5, X1 - 0.5, SY, SY + 0.45, z, z + 0.06, "Wood", "-z")
cols = [CORAL, "TileTeal", "Hazard", "AwningWhite", PLUM, "BarberBlue"]
for k in range(14):
    x = X0 + 0.9 + k * 0.78
    z = 1.25 if k % 2 == 0 else 2.35
    b.abox(x - 0.25, x + 0.25, SY + 0.05, SY + 0.4, z + 0.06, z + 0.3 + (k % 3) * 0.05, cols[k % 6], "-z")
outfits = [(-4.4, CORAL, PLUM), (-2.7, "TileTeal", "TrimWhite"), (2.7, "Hazard", "BarberBlue"), (4.4, "AwningWhite", CORAL)]
for (mx, sh_c, pn_c) in outfits:
    mannequin(b, mx, 4.3, 0.15, 1.0, sh_c, pn_c)
# clothes rack
b.beam((-1.0, 3.3, 1.5), (1.0, 3.3, 1.5), 0.02, 0.02, 4, "Metal")
for k in range(7):
    x = -0.85 + k * 0.28
    b.abox(x - 0.04, x + 0.04, 3.22, 3.38, 0.7, 1.45, cols[(k + 2) % 6], "-z")
for sx in (-1.0, 1.0):
    b.beam((sx, 3.3, 0.15), (sx, 3.3, 1.5), 0.025, 0.025, 4, "Metal")

A.mesh(b, "Body")
c = HB("clothing_store_col")
c.abox(X0, X1, Y0, Y1, 0, TOP + 0.9, "Concrete", "-z")
A.mesh(c, "Collision", uv=None, winuv=False)
A.mark("Door", (0.0, 6.8, 0.0))
rep = A.report()
