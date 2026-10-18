"""lane7 weapon_shop: 14 x 12 m fortified bunker shop, shutters, reinforced door, crosshair neon sign, sandbag planters."""
A = Asset("weapon_shop", 2)
b = HB("weapon_shop_body")

X0, X1, Y0, Y1 = -7.0, 7.0, -6.0, 5.0
WH = 4.4
CY = (Y0 + Y1) / 2
HY = (Y1 - Y0) / 2
WALL = "Bunker"
F = Side(b, "F", 0, CY, 7, HY)
Bk = Side(b, "B", 0, CY, 7, HY)
Lw = Side(b, "L", 0, CY, 7, HY)
Rw = Side(b, "R", 0, CY, 7, HY)

# ---------------------------------------------------------------- front: reinforced door + two barred shutter windows
door = (-1.0, 1.0, 0.0, 2.6)
win_h = [(F.u(x) - 1.45, F.u(x) + 1.45, 1.1, 2.9) for x in (-4.8, 4.8)]
F.wall(-7, 7, 0, WH, [door] + win_h, WALL)
F.reveal(door, 0.55, "Hazard", "lrt")
F.q(door[0], door[1], 0, 2.6, -0.55, "MetalDark")
F.q(-0.06, 0.06, 0.1, 2.5, -0.52, "Trim")
for z in (0.55, 1.3, 2.05):
    F.q(-0.85, 0.85, z, z + 0.07, -0.52, "Metal")
for sx in (-0.7, 0.7):
    for z in (0.2, 2.4):
        F.box(sx - 0.06, sx + 0.06, z, z + 0.12, -0.55, -0.45, "Metal", skip="ib")
F.box(0.38, 0.5, 1.0, 1.35, -0.55, -0.42, "Chrome", skip="ib")                       # handle
F.q(-0.3, 0.3, 1.9, 2.15, -0.51, "Window")                                            # peep slot
# hazard-striped lintel
F.box(-1.7, 1.7, 2.65, 3.25, 0.0, 0.2, "ConcreteDk", skip="ib")
n = 9
for k in range(n):
    ua = -1.7 + 3.4 * k / n
    ub = ua + 3.4 / n * 0.5
    F.poly([(ua, 2.65), (ub, 2.65), (ub + 0.25, 3.25), (ua + 0.25, 3.25)], 0.21, "Hazard") if ub + 0.25 <= 1.7 else None
for h in win_h:
    F.reveal(h, 0.4, "ConcreteDk", "lrtb")
    F.q(h[0], h[1], h[2], h[3], -0.4, "Window")
    for k in range(7):
        u = h[0] + 0.2 + (h[1] - h[0] - 0.4) * k / 6
        F.box(u - 0.035, u + 0.035, h[2], h[3], -0.1, -0.03, "Metal", skip="ibt")
    F.box(h[0] - 0.15, h[1] + 0.15, 2.95, 3.5, 0.0, 0.4, "MetalDark", skip="ib")       # shutter housing
    for k in range(3):
        v = 3.05 + k * 0.15
        F.q(h[0] - 0.05, h[1] + 0.05, v, v + 0.05, 0.41, "Trim")
    F.box(h[0] - 0.15, h[1] + 0.15, 0.95, 1.1, 0.0, 0.3, "ConcreteDk", skip="ib")        # sill
b.zq(WH, X0, X1, Y0, Y1, 1, "Roof")

# back: steel door + slit windows ; sides: slit windows
bdoor = (-0.9, 0.9, 0.0, 2.4)
Bk.wall(-7, 7, 0, WH, [bdoor] + [(u - 0.6, u + 0.6, 2.7, 3.4) for u in (-4.5, -1.8, 3.0, 5.2)], WALL)
Bk.reveal(bdoor, 0.4, "Hazard", "lrt")
Bk.q(bdoor[0], bdoor[1], 0, 2.4, -0.4, "MetalDark")
for u in (-4.5, -1.8, 3.0, 5.2):
    Bk.win((u - 0.6, u + 0.6, 2.7, 3.4), depth=0.3, frame="ConcreteDk")
for S in (Lw, Rw):
    holes = [(u - 0.6, u + 0.6, 2.7, 3.4) for u in (-3.5, 0.0, 3.5)]
    S.wall(-HY, HY, 0, WH, holes, WALL)
    S.wins(holes, depth=0.3, frame="ConcreteDk")

# buttresses, plinth, cornice and parapet
for sx in (-7.0, 7.0):
    for sy in (Y0, Y1):
        b.abox(sx - 0.45, sx + 0.45, sy - 0.45, sy + 0.45, 0.0, WH + 0.15, "ConcreteDk", "-z")
b.abox(X0 - 0.12, X1 + 0.12, Y0 - 0.12, Y1 + 0.12, 0.0, 0.55, "ConcreteDk", "-z")
b.abox(X0 - 0.2, X1 + 0.2, Y0 - 0.2, Y1 + 0.2, WH - 0.35, WH + 0.05, "ConcreteDk", "-z")
parapet(b, X0 - 0.2, X1 + 0.2, Y0 - 0.2, Y1 + 0.2, WH + 0.05, WH + 1.0, 0.35, WALL)
# merlons along the front/back parapet
for x in (-5.5, -2.8, 0.0, 2.8, 5.5):
    b.abox(x - 0.55, x + 0.55, Y1 - 0.2, Y1 + 0.2, WH + 1.0, WH + 1.45, "ConcreteDk", "-z")
for x in (-5.5, -2.8, 0.0, 2.8, 5.5):
    b.abox(x - 0.55, x + 0.55, Y0 - 0.2, Y0 + 0.2, WH + 1.0, WH + 1.45, "ConcreteDk", "-z")
# barbed wire (zig-zag along the front parapet)
for k in range(14):
    x_a = -6.6 + k * 1.0
    b.beam((x_a, Y1 + 0.1, WH + 1.55), (x_a + 0.5, Y1 + 0.1, WH + 1.85), 0.02, 0.02, 3, "MetalDark", caps=False)
    b.beam((x_a + 0.5, Y1 + 0.1, WH + 1.85), (x_a + 1.0, Y1 + 0.1, WH + 1.55), 0.02, 0.02, 3, "MetalDark", caps=False)
b.beam((-6.6, Y1 + 0.1, WH + 1.55), (7.4, Y1 + 0.1, WH + 1.55), 0.025, 0.025, 4, "Metal", caps=False)

# ---------------------------------------------------------------- crosshair neon sign on the roof
SCZ = WH + 1.0 + 2.45
SX0, SY0 = 0.0, Y1 - 0.9
for sx in (-1.7, 1.7):
    b.beam((sx, SY0, WH + 1.0), (sx * 0.55, SY0, SCZ - 1.2), 0.07, 0.05, 4, "MetalDark", caps=False)
b.abox(-1.85, 1.85, SY0 - 0.1, SY0 + 0.1, WH + 1.0, WH + 1.25, "MetalDark")
sgn = Side(b, "F", 0, SY0, 3, 0.05)
sgb = Side(b, "B", 0, SY0, 3, 0.05)
for S in (sgn, sgb):
    d0 = 0.05
    # outer ring (magenta), inner ring (amber), crosshair, centre dot
    cu, cv = 0.0, SCZ
    for k in range(20):
        a0, a1 = 2 * math.pi * k / 20, 2 * math.pi * (k + 1) / 20
        S.poly([(cu + 1.72 * math.cos(a0), cv + 1.72 * math.sin(a0)), (cu + 1.72 * math.cos(a1), cv + 1.72 * math.sin(a1)),
                (cu + 1.5 * math.cos(a1), cv + 1.5 * math.sin(a1)), (cu + 1.5 * math.cos(a0), cv + 1.5 * math.sin(a0))], d0, "Neon")
    for k in range(12):
        a0, a1 = 2 * math.pi * k / 12, 2 * math.pi * (k + 1) / 12
        S.poly([(cu + 0.85 * math.cos(a0), cv + 0.85 * math.sin(a0)), (cu + 0.85 * math.cos(a1), cv + 0.85 * math.sin(a1)),
                (cu + 0.68 * math.cos(a1), cv + 0.68 * math.sin(a1)), (cu + 0.68 * math.cos(a0), cv + 0.68 * math.sin(a0))], d0, "NeonAmber")
    S.stroke((cu - 2.15, cv), (cu - 0.45, cv), 0.12, d0, "NeonAmber")
    S.stroke((cu + 0.45, cv), (cu + 2.15, cv), 0.12, d0, "NeonAmber")
    S.stroke((cu, cv - 2.15), (cu, cv - 0.45), 0.12, d0, "NeonAmber")
    S.stroke((cu, cv + 0.45), (cu, cv + 2.15), 0.12, d0, "NeonAmber")
    S.poly([(cu + 0.2 * math.cos(2 * math.pi * k / 6), cv + 0.2 * math.sin(2 * math.pi * k / 6)) for k in range(6)], d0, "NeonRed")

# floodlights on the front corners
for sx in (-6.3, 6.3):
    b.beam((sx, Y1 + 0.1, WH - 0.1), (sx, Y1 + 0.75, WH + 0.5), 0.05, 0.05, 4, "MetalDark", caps=False)
    b.abox(sx - 0.28, sx + 0.28, Y1 + 0.6, Y1 + 0.95, WH + 0.35, WH + 0.7, "MetalDark", "-z")
    b.yq(Y1 + 0.96, sx - 0.22, sx + 0.22, WH + 0.4, WH + 0.65, 1, "LampGlow")
ac_unit(b, -4.0, -2.5, WH, 2.0, 1.6, 1.0)
ac_unit(b, 3.5, -3.5, WH, 1.8, 1.4, 0.9)

# ---------------------------------------------------------------- sandbag planters + step
def sandbag(cx, cy, z, rot90=False):
    w, d, h = (0.78, 0.42, 0.24) if not rot90 else (0.42, 0.78, 0.24)
    b.hip(cx - w / 2, cx + w / 2, cy - d / 2, cy + d / 2, z, h, 0.06, 0.06, "SandBag", "-z")

for sx in (-4.8, 4.8):
    layers = [(4, 0.0), (4, 0.39), (3, 0.0)]
    for li, (cnt, off) in enumerate(layers):
        z = li * 0.25
        x_start = sx - (cnt - 1) * 0.8 / 2 + (off * 0 if li != 1 else 0.0)
        for k in range(cnt):
            sandbag(x_start + k * 0.8, Y1 + 0.55, z)
    b.ball((sx - 0.7, Y1 + 0.55, 0.78 + 0.28), 0.42, 5, 2, "Leaf", sc=(1, 1, 0.85))
    b.ball((sx + 0.55, Y1 + 0.55, 0.78 + 0.22), 0.36, 5, 2, "LeafLight", sc=(1, 1, 0.85))
b.abox(-1.6, 1.6, Y1, Y1 + 0.95, 0.0, 0.12, "Concrete", "-z -y")                 # door step

A.mesh(b, "Body")

c = HB("weapon_shop_col")
c.abox(X0, X1, Y0, Y1, 0, WH + 1.0, "Concrete", "-z")
for sx in (-4.8, 4.8):
    c.abox(sx - 1.6, sx + 1.6, Y1, Y1 + 0.9, 0, 0.75, "Concrete", "-z -y -x -z")
A.mesh(c, "Collision", uv=None, winuv=False)

A.mark("Door", (0.0, 5.75, 0.0))
rep = A.report()
