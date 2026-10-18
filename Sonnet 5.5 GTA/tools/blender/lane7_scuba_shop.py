"""lane7 scuba_shop: 12 x 10 m dive shop, tiled wet-room base, portholes, rooftop scuba-tank sign, dive flag, rinse tank, wetsuit display."""
A = Asset("scuba_shop", 8)
b = HB("scuba_shop_body")

X0, X1, Y0, Y1 = -6.0, 6.0, -5.0, 4.4
TOP = 4.6
CY = (Y0 + Y1) / 2
HY = (Y1 - Y0) / 2
WHT, TL, TD = "TrimWhite", "TileTeal", "TileDark"
F = Side(b, "F", 0, CY, 6, HY)
Bk = Side(b, "B", 0, CY, 6, HY)
Lw = Side(b, "L", 0, CY, 6, HY)
Rw = Side(b, "R", 0, CY, 6, HY)

def octagon(S, cu, cv, r, d, m):
    S.poly([(cu + r * math.cos(math.pi / 8 + k * math.pi / 4), cv + r * math.sin(math.pi / 8 + k * math.pi / 4)) for k in range(8)], d, m)

def porthole(S, cu, cv, r=0.36, d=0.02):
    for k in range(8):
        a0, a1 = math.pi / 8 + k * math.pi / 4, math.pi / 8 + (k + 1) * math.pi / 4
        S.poly([((cu + (r + 0.12) * math.cos(a0)), (cv + (r + 0.12) * math.sin(a0))), ((cu + (r + 0.12) * math.cos(a1)), (cv + (r + 0.12) * math.sin(a1))),
                ((cu + r * math.cos(a1)), (cv + r * math.sin(a1))), ((cu + r * math.cos(a0)), (cv + r * math.sin(a0)))], d + 0.03, "Metal")
    octagon(S, cu, cv, r, d + 0.01, "Window")

# ---------------------------------------------------------------- front
win = (F.u(-0.6), F.u(-5.4), 1.3, 3.5)
win = (min(win[0], win[1]), max(win[0], win[1]), win[2], win[3])
door = (min(F.u(1.4), F.u(3.6)), max(F.u(1.4), F.u(3.6)), 0.0, 2.7)
F.wall(-6, 6, 0, TOP, [win, door], WHT)
F.reveal(win, 0.25, TD, "lrtb")
F.q(win[0], win[1], win[2], win[3], -0.25, "Glass")
for k in (1, 2, 3):
    u = win[0] + (win[1] - win[0]) * k / 4
    F.q(u - 0.035, u + 0.035, win[2], win[3], -0.22, "MetalDark")
F.reveal(door, 0.35, TD, "lrt")
F.q(door[0], door[1], 0, 2.7, -0.35, "Glass")
F.q((door[0] + door[1]) / 2 - 0.04, (door[0] + door[1]) / 2 + 0.04, 0, 2.7, -0.32, "MetalDark")
F.box(door[0] - 0.12, door[1] + 0.12, 2.75, 3.0, 0.0, 0.8, "Hazard", skip="i")                     # door canopy
# tiled base (wet-room look) with grid lines + darker wet base
F.q(-6, 6, 0.0, 1.2, 0.02, TL)
F.q(-6, 6, 0.0, 0.35, 0.03, TD)
for k in range(1, 16):
    u = -6 + k * 0.75
    F.q(u - 0.012, u + 0.012, 0.35, 1.2, 0.035, TD)
F.q(-6, 6, 0.78, 0.8, 0.035, TD)
F.box(-6.1, 6.1, 1.2, 1.3, 0.0, 0.12, WHT, skip="i")
# portholes on the frieze
for x in (-4.8, -2.4, 0.0, 2.4, 4.8):
    porthole(F, F.u(x), 4.05)
b.abox(X0 - 0.2, X1 + 0.2, Y0 - 0.2, Y1 + 0.2, TOP - 0.2, TOP + 0.1, TD, "-z")
parapet(b, X0 - 0.2, X1 + 0.2, Y0 - 0.2, Y1 + 0.2, TOP + 0.1, TOP + 0.9, 0.26, WHT)
# neon wave on the parapet
pts = []
for k in range(15):
    x = -5.6 + k * 0.8
    pts.append((x, TOP + 0.5 + 0.2 * (1 if k % 2 else -1)))
for (a, c_) in zip(pts[:-1], pts[1:]):
    b.pq([(a[0], Y1 + 0.2 + 0.01, a[1] - 0.05), (c_[0], Y1 + 0.2 + 0.01, c_[1] - 0.05), (c_[0], Y1 + 0.2 + 0.01, c_[1] + 0.05), (a[0], Y1 + 0.2 + 0.01, a[1] + 0.05)], (0, 1, 0), "NeonCyan")
b.yq(Y1 + 0.2 + 0.005, X0 + 0.3, X1 - 0.3, TOP + 0.2, TOP + 0.8, 1, TD)

# ---------------------------------------------------------------- sides + back
for S in (Lw, Rw):
    S.wall(-HY, HY, 0, TOP, [], WHT)
    S.q(-HY, HY, 0.0, 1.2, 0.02, TL)
    S.q(-HY, HY, 0.0, 0.35, 0.03, TD)
    S.q(-HY, HY, 0.78, 0.8, 0.035, TD)
    for u in (-3.0, -0.6, 1.8):
        porthole(S, u, 2.6, 0.4)
bdoor = (-0.9, 0.9, 0.0, 2.5)
Bk.wall(-6, 6, 0, TOP, [bdoor], WHT)
Bk.reveal(bdoor, 0.3, TD, "lrt")
Bk.q(-0.9, 0.9, 0, 2.5, -0.3, "MetalDark")
Bk.q(-6, 6, 0.0, 1.2, 0.02, TL)
for u in (-3.5, 3.5):
    porthole(Bk, u, 2.6, 0.4)
b.zq(TOP, X0, X1, Y0, Y1, 1, "Roof")

# ---------------------------------------------------------------- rooftop scuba tank sign
TX, TY = -3.2, 3.2
b.cyl((TX, TY, TOP + 0.5), 0.55, 0.4, 8, "MetalDark", caps="t")                          # cradle base
b.cyl((TX, TY, TOP + 2.7), 0.62, 4.0, 8, "Hazard", caps="")
b.cyl((TX, TY, TOP + 1.2), 0.64, 0.14, 8, "Trim", caps="")
b.cyl((TX, TY, TOP + 3.9), 0.64, 0.14, 8, "NeonCyan", caps="")
b.cyl((TX, TY, TOP + 3.9 + 0.3), 0.62, 0.45, 8, "Hazard", r_top=0.34, caps="")
b.cyl((TX, TY, TOP + 4.6), 0.2, 0.2, 6, "Chrome", caps="t")
b.cyl((TX, TY, TOP + 4.85), 0.09, 0.3, 5, "Chrome", caps="t")
b.cyl((TX, TY, TOP + 5.05), 0.32, 0.05, 8, "Chrome", axis="Y", caps="t")                  # valve wheel
for k, (dx, dz, r_) in enumerate(((0.9, 5.2, 0.16), (1.35, 5.9, 0.12), (0.8, 6.5, 0.1))):
    b.ball((TX + dx, TY, TOP + dz), r_, 6, 3, "NeonCyan")                                  # bubbles
for sx in (-0.35, 0.35):
    b.beam((TX + sx, TY, TOP), (TX + sx, TY, TOP + 0.55), 0.06, 0.06, 4, "MetalDark", caps=False)

# dive flag on a pole (double sided: red with white diagonal)
FPX, FPY = 4.6, 3.3
b.beam((FPX, FPY, TOP), (FPX, FPY, TOP + 6.2), 0.06, 0.045, 6, "Metal")
b.ball((FPX, FPY, TOP + 6.3), 0.1, 5, 2, "Chrome")
fz0, fz1 = TOP + 4.4, TOP + 6.0
for sg in (1, -1):
    off = 0.0 if sg > 0 else -0.01
    b.pq([(FPX + 0.07, FPY + off, fz0), (FPX + 1.7, FPY + 0.15 + off, fz0 - 0.08), (FPX + 1.7, FPY + 0.15 + off, fz1 - 0.08), (FPX + 0.07, FPY + off, fz1)], (0, sg, 0), "FlagRed")
    b.pq([(FPX + 0.07, FPY + 0.01 * sg + off, fz0 + 0.0), (FPX + 0.55, FPY + 0.045 * sg + off, fz0 - 0.02), (FPX + 1.7, FPY + 0.15 * 1 * sg + 0.01 * sg + off, fz1 - 0.08), (FPX + 1.2, FPY + 0.12 * sg + off, fz1 - 0.06)], (0, sg, 0), "TrimWhite")

# ---------------------------------------------------------------- front yard: rinse tank, tank rack, hose, puddles, shower
b.abox(-5.9, -3.6, 4.55, 5.0, 0.0, 0.9, TD, "-z")
b.yq(5.01, -5.9, -3.6, 0.0, 0.9, 1, TL)
b.zq(0.72, -5.8, -3.7, 4.6, 4.95, 1, "Water")
for sx in (4.2, 4.65, 5.1, 5.55):
    b.cyl((sx, 4.3, 0.6), 0.18, 1.2, 6, "Hazard" if sx < 5 else "Metal", caps="")
    b.ball((sx, 4.3, 1.2), 0.18, 6, 2, "Hazard" if sx < 5 else "Metal", sc=(1, 1, 0.7))
b.abox(4.0, 5.8, 4.25, 4.4, 0.35, 0.4, "MetalDark", "-z")
b.cyl((2.0, 4.5, 1.7), 0.35, 0.15, 8, "MetalDark", axis="Y", caps="t")                      # hose reel
b.cyl((2.0, 4.5, 1.7), 0.5, 0.05, 8, "Metal", axis="Y", caps="t")
b.beam((0.3, Y1, 2.3), (0.3, Y1 + 0.3, 2.3), 0.04, 0.04, 4, "Chrome")
b.beam((0.3, Y1 + 0.3, 2.3), (0.3, Y1 + 0.3, 2.0), 0.04, 0.04, 4, "Chrome")
b.cyl((0.3, Y1 + 0.3, 1.95), 0.2, 0.06, 6, "Chrome", caps="b")
for (px, py, w, d) in ((-1.3, 4.9, 1.6, 0.6), (3.0, 4.95, 1.4, 0.5), (0.2, 4.7, 0.9, 0.5)):
    b.zq(0.095, px - w / 2, px + w / 2, py - d / 2, py + d / 2, 1, "Water")
b.abox(X0, X1, Y1, 5.0, 0.0, 0.09, "ConcreteDk", "-z -x +x -y")
for x in (-2.5, 1.5):
    b.abox(x - 0.4, x + 0.4, 4.55, 4.9, 0.09, 0.12, "MetalDark", "-z")                    # drain grates

# ---------------------------------------------------------------- interior through the glass
IY = 1.2
b.zq(0.15, X0 + 0.3, 0.0, IY, Y1 - 0.2, 1, TL)
b.yq(IY, X0 + 0.3, 0.0, 0.15, TOP - 0.3, 1, TD)
b.zq(TOP - 0.3, X0 + 0.3, 0.0, IY, Y1 - 0.2, -1, WHT)
b.zq(TOP - 0.31, -5.0, -1.0, 2.2, 3.4, -1, "LampGlow")
for z in (1.3, 2.3):
    b.abox(X0 + 0.5, -0.4, IY, IY + 0.4, z, z + 0.06, "Metal", "-z")
cols = ["NeonCyan", "Hazard", "BarberRed", "TileTeal", "BarberBlue", "Hazard"]
for k in range(9):
    x = X0 + 0.9 + k * 0.55
    b.abox(x - 0.18, x + 0.18, IY + 0.05, IY + 0.35, 1.36, 1.5 + (k % 3) * 0.08, cols[k % 6], "-z")
    b.abox(x - 0.16, x + 0.16, IY + 0.05, IY + 0.35, 2.36, 2.52, "Trim", "-z")
for k, mx in enumerate((-4.6, -3.4, -2.2)):
    mannequin(b, mx, 3.2, 0.15, 1.0, "Trim", "Trim")
    b.abox(mx - 0.2, mx + 0.2, 3.07, 3.33, 1.0, 1.06, "NeonCyan", "-z")
for k in range(3):
    b.cyl((-0.9, 2.2 + k * 0.5, 0.4), 0.14, 0.8, 6, "Hazard", caps="t")

A.mesh(b, "Body")
c = HB("scuba_shop_col")
c.abox(X0, X1, Y0, Y1, 0, TOP + 0.9, "Concrete", "-z")
c.abox(-5.9, -3.6, 4.55, 5.0, 0.0, 0.9, "Concrete", "-z")
A.mesh(c, "Collision", uv=None, winuv=False)
A.mark("Door", (2.5, 5.0, 0.0))
rep = A.report()
