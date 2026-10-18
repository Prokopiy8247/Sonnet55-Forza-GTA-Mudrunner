"""lane7 garage_shop: 24 x 18 m customization / repair garage, two open roll-up bays (drive-in), hoist, tool-wall, neon spanner + wheel sign."""
A = Asset("garage_shop", 3)
b = HB("garage_shop_body")
mat("GarageWall", color="#a8a79f", rough=0.95)
mat("GarageDark", color="#3a3f47", rough=0.8)
mat("ToolRed", color="#c8372f", rough=0.5)

X0, X1, Y0, Y1 = -12.0, 12.0, -9.0, 7.0
WH = 6.0
CY = (Y0 + Y1) / 2
HY = (Y1 - Y0) / 2
W_ = "GarageWall"
OR = "ShopOrange"
F = Side(b, "F", 0, CY, 12, HY)
Bk = Side(b, "B", 0, CY, 12, HY)
Lw = Side(b, "L", 0, CY, 12, HY)
Rw = Side(b, "R", 0, CY, 12, HY)

# ------------------------------------------------------------------ front wall: two open bays + central office
BAYS = (-8.0, 8.0)
bay_holes = [(F.u(x) - 2.8, F.u(x) + 2.8, 0.0, 4.2) for x in BAYS]
door = (-1.0, 1.0, 0.0, 2.5)
off_win = [(F.u(x) - 1.2, F.u(x) + 1.2, 0.8, 2.6) for x in (-2.7, 2.7)]
F.wall(-12, 12, 0, WH, bay_holes + [door] + off_win, W_)
for h in bay_holes:
    F.reveal(h, 0.35, "GarageDark", "lrt")
    # jambs, roll-up housing and the rolled slats
    F.box(h[0] - 0.35, h[0], 0.0, 4.9, 0.0, 0.3, OR, skip="ib")
    F.box(h[1], h[1] + 0.35, 0.0, 4.9, 0.0, 0.3, OR, skip="ib")
    F.box(h[0] - 0.35, h[1] + 0.35, 4.2, 4.9, 0.0, 0.55, "MetalDark", skip="ib")
    for k in range(4):
        F.q(h[0] - 0.3, h[1] + 0.3, 4.3 + k * 0.15, 4.36 + k * 0.15, 0.56, "Trim")
    F.q(h[0] - 0.35, h[1] + 0.35, 4.9, 5.1, 0.0, OR)
F.reveal(door, 0.4, "GarageDark", "lrt")
F.q(-1.0, 1.0, 0.0, 2.5, -0.4, "Window")
F.q(-0.05, 0.05, 0.0, 2.5, -0.37, "Metal")
for h in off_win:
    F.win(h, depth=0.25, frame="GarageDark", sill=0.3, sill_m=OR)
# office awning + sign panel
F.box(-4.4, 4.4, 3.0, 3.3, 0.0, 1.2, OR, skip="i")
F.box(-4.3, 4.3, 3.8, 5.8, 0.0, 0.18, "GarageDark", skip="ib")
F.box(-4.3, 4.3, 5.8, 6.0, 0.0, 0.24, OR, skip="ib")
F.box(-4.3, 4.3, 3.6, 3.8, 0.0, 0.24, OR, skip="ib")
# neon wheel (cyan) + crossed spanner (magenta)
def neon_logo(S, cu, cv, k, d1=0.2, d2=0.25, ang_deg=35.0, L=2.0):
    for i in range(18):
        a0, a1 = 2 * math.pi * i / 18, 2 * math.pi * (i + 1) / 18
        S.poly([(cu + 0.95 * k * math.cos(a0), cv + 0.95 * k * math.sin(a0)), (cu + 0.95 * k * math.cos(a1), cv + 0.95 * k * math.sin(a1)),
                (cu + 0.78 * k * math.cos(a1), cv + 0.78 * k * math.sin(a1)), (cu + 0.78 * k * math.cos(a0), cv + 0.78 * k * math.sin(a0))], d2, "NeonCyan")
    for i in range(5):
        a = math.pi / 2 + 2 * math.pi * i / 5
        S.stroke((cu, cv), (cu + 0.78 * k * math.cos(a), cv + 0.78 * k * math.sin(a)), 0.1 * k, d2, "NeonCyan")
    S.poly([(cu + 0.2 * k * math.cos(2 * math.pi * i / 6), cv + 0.2 * k * math.sin(2 * math.pi * i / 6)) for i in range(6)], d2, "NeonCyan")
    ang = math.radians(ang_deg)
    dx, dy = math.cos(ang), math.sin(ang)
    p0 = (cu - L * dx, cv - L * dy)
    p1 = (cu + L * dx, cv + L * dy)
    S.stroke(p0, p1, 0.2 * k, d1, "Neon")
    nx_, ny_ = -dy, dx
    for sgn in (-1, 1):
        a_ = (p1[0] + nx_ * 0.38 * k * sgn, p1[1] + ny_ * 0.38 * k * sgn)
        b_ = (a_[0] + dx * 0.6 * k, a_[1] + dy * 0.6 * k)
        S.stroke(a_, b_, 0.14 * k, d1, "Neon")
    S.stroke((p1[0] + nx_ * 0.38 * k, p1[1] + ny_ * 0.38 * k), (p1[0] - nx_ * 0.38 * k, p1[1] - ny_ * 0.38 * k), 0.14 * k, d1, "Neon")
    for i in range(8):
        a0, a1 = 2 * math.pi * i / 8, 2 * math.pi * (i + 1) / 8
        S.poly([(p0[0] + 0.42 * k * math.cos(a0), p0[1] + 0.42 * k * math.sin(a0)), (p0[0] + 0.42 * k * math.cos(a1), p0[1] + 0.42 * k * math.sin(a1)),
                (p0[0] + 0.27 * k * math.cos(a1), p0[1] + 0.27 * k * math.sin(a1)), (p0[0] + 0.27 * k * math.cos(a0), p0[1] + 0.27 * k * math.sin(a0))], d1, "Neon")

neon_logo(F, 0.0, 4.8, 0.78, 0.2, 0.25, 18.0, 1.9)
# rooftop billboard (double sided)
SBY = 5.6
for sx in (-3.2, 3.2):
    b.abox(sx - 0.2, sx + 0.2, SBY - 0.2, SBY + 0.2, WH, 7.2, "MetalDark", "-z")
b.abox(-4.6, 4.6, SBY - 0.3, SBY + 0.3, 7.0, 10.6, "GarageDark")
b.abox(-4.6, 4.6, SBY - 0.3, SBY + 0.3, 10.4, 10.6, OR)
b.abox(-4.6, 4.6, SBY - 0.3, SBY + 0.3, 7.0, 7.2, OR)
for nm_, py_ in (("F", SBY + 0.3), ("B", SBY - 0.3)):
    Sb = Side(b, nm_, 0, SBY, 4.6, 0.3)
    neon_logo(Sb, 0.0, 8.8, 1.0, 0.05, 0.08, 30.0, 2.3)
    Sb.q(-4.4, -3.0, 8.75, 8.85, 0.03, "NeonAmber")
    Sb.q(3.0, 4.4, 8.75, 8.85, 0.03, "NeonAmber")
# orange band + hazard base strip along the front
F.q(-12, 12, 5.35, 5.6, 0.02, OR)

# ------------------------------------------------------------------ other outer walls
hb = [(u - 1.0, u + 1.0, 4.0, 5.1) for u in (-8.0, -3.0, 3.0, 8.0)]
Bk.openings(-12, 12, 0, WH, hb, W_, depth=0.2, frame="GarageDark")
hs = [(u - 1.0, u + 1.0, 4.0, 5.1) for u in (-5.5, -1.8, 1.8, 5.5)]
for S in (Lw, Rw):
    S.openings(-HY, HY, 0, WH, hs, W_, depth=0.2, frame="GarageDark")
b.zq(WH, X0, X1, Y0, Y1, 1, "Roof")
b.abox(X0 - 0.25, X1 + 0.25, Y0 - 0.25, Y1 + 0.25, WH - 0.3, WH + 0.05, "GarageDark", "-z")
parapet(b, X0 - 0.25, X1 + 0.25, Y0 - 0.25, Y1 + 0.25, WH + 0.05, WH + 0.85, 0.3, W_)
b.abox(X0 - 0.25, X1 + 0.25, Y1 + 0.25 - 0.32, Y1 + 0.27, WH + 0.5, WH + 0.62, OR, "-z -x +x")
# corner pylons
for sx in (X0, X1):
    for sy in (Y0, Y1):
        b.abox(sx - 0.3, sx + 0.3, sy - 0.3, sy + 0.3, 0.0, WH + 0.4, "GarageDark", "-z")

# ------------------------------------------------------------------ interior (seen through the open bays)
b.abox(X0 + 0.3, X1 - 0.3, Y0 + 0.3, Y1 - 0.5, 0.0, 0.03, "ConcreteDk", "-z -x +x -y +y")
b.zq(0.035, X0 + 0.3, X1 - 0.3, Y0 + 0.3, Y1 - 0.5, 1, "ConcreteDk")
# inner walls (facing inwards)
b.yq(Y0 + 0.3, X0 + 0.3, X1 - 0.3, 0.03, WH, 1, "GarageWall")
b.xq(X0 + 0.3, Y0 + 0.3, Y1 - 0.4, 0.03, WH, 1, "GarageWall")
b.xq(X1 - 0.3, Y0 + 0.3, Y1 - 0.4, 0.03, WH, -1, "GarageWall")
b.zq(WH - 0.02, X0 + 0.3, X1 - 0.3, Y0 + 0.3, Y1 - 0.4, -1, "GarageDark")
for yb in (-6.5, -2.0, 2.5):
    b.abox(X0 + 0.3, X1 - 0.3, yb - 0.18, yb + 0.18, WH - 0.55, WH - 0.02, "MetalDark", "+z")
    b.zq(WH - 0.56, X0 + 0.3, X1 - 0.3, yb - 0.1, yb + 0.1, -1, "LampGlow")
# office room (solid mass behind the front windows)
b.abox(-4.4, 4.4, 2.8, Y1 - 0.4, 0.0, WH - 0.02, "GarageWall", "-z +y")
# tool wall on the back
b.abox(-10.5, 10.5, Y0 + 0.31, Y0 + 0.4, 0.9, 3.5, "MetalDark", "-z -x +x -y")
tool_cols = ["ToolRed", "Hazard", "Chrome", OR, "Metal", "ToolRed", "Hazard", "Chrome"]
for k in range(20):
    x = -9.6 + k * 1.0
    tm = tool_cols[k % len(tool_cols)]
    b.abox(x - 0.07, x + 0.07, Y0 + 0.4, Y0 + 0.5, 1.7 + (k * 7 % 5) * 0.28, 2.9 + (k * 3 % 4) * 0.12, tm, "-z -y")
for z in (1.35, 3.1):
    b.abox(-10.5, 10.5, Y0 + 0.4, Y0 + 0.65, z, z + 0.08, "Metal", "-z")
# workbench + toolbox
b.abox(-9.5, -4.5, Y0 + 0.5, Y0 + 1.5, 0.0, 0.95, "Wood", "-z")
b.abox(-9.55, -4.45, Y0 + 0.45, Y0 + 1.55, 0.95, 1.02, "Metal", "-z")
b.abox(-3.6, -2.6, Y0 + 0.6, Y0 + 1.3, 0.0, 1.0, "ToolRed", "-z")
# drums + tyre stack
for k, (dx_, dy_) in enumerate(((3.0, Y0 + 1.0), (3.8, Y0 + 1.0), (3.4, Y0 + 1.8))):
    b.cyl((dx_, dy_, 0.45), 0.3, 0.9, 6, "GasRed" if k != 1 else "Hazard", caps="t")
for k in range(4):
    b.cyl((-1.2, Y0 + 1.1, 0.12 + k * 0.23), 0.42, 0.22, 8, "Tire", caps="t")
b.cyl((-1.2, Y0 + 1.1, 1.0), 0.28, 0.02, 6, "Rim", caps="t")
# two-post hoist in bay B + overhead beam + pit lines in bay A
HX = BAYS[1]
for sx in (-1, 1):
    px = HX + sx * 2.25
    b.abox(px - 0.2, px + 0.2, -3.3, -2.7, 0.0, 3.7, "MetalDark", "-z")
    b.abox(px - 0.23, px + 0.23, -3.1, -2.9, 0.3, 0.7, OR, "-z")
    b.beam((px - sx * 0.2, -3.0, 0.6), (px - sx * 1.5, -3.0, 0.5), 0.07, 0.07, 4, "Metal", caps=True)
b.abox(HX - 2.5, HX + 2.5, -3.2, -2.8, 3.7, 4.0, OR, "-z")
for sx in (-1, 1):
    b.abox(HX + sx * 1.2 - 0.08, HX + sx * 1.2 + 0.08, -4.0, 1.5, 0.45, 0.55, "Metal", "-z")      # lift rails
A_x = BAYS[0]
for yb in (-4.4, 4.0):
    b.zq(0.04, A_x - 2.6, A_x + 2.6, yb - 0.07, yb + 0.07, 1, "RailYellow")
for sx in (-2.6, 2.6):
    b.zq(0.04, A_x + sx - 0.07, A_x + sx + 0.07, -4.4, 4.0, 1, "RailYellow")
for x in (BAYS[1],):
    for yb in (4.6,):
        b.zq(0.04, x - 2.6, x + 2.6, yb - 0.07, yb + 0.07, 1, "RailYellow")

# ------------------------------------------------------------------ apron
b.abox(X0, X1, Y1, 9.0, 0.0, 0.08, "ConcreteDk", "-z -x +x -y")
for x in BAYS:
    for k in range(6):
        xs = x - 2.5 + k * 0.9
        b.pq([(xs, Y1 + 0.2, 0.09), (xs + 0.4, Y1 + 0.2, 0.09), (xs + 0.8, 1.8 + Y1, 0.09), (xs + 0.4, 1.8 + Y1, 0.09)], (0, 0, 1), "RailYellow") if xs + 0.8 < x + 2.8 else None
# roof stuff
for xs in (-7.0, 0.0, 7.0):
    b.abox(xs - 1.4, xs + 1.4, -7.5, -3.8, WH, WH + 0.25, "GarageDark", "-z")
    b.zq(WH + 0.26, xs - 1.15, xs + 1.15, -7.25, -4.05, 1, "Window")
ac_unit(b, -6.0, 2.0, WH, 2.4, 1.8, 1.2)
ac_unit(b, 4.0, -5.5, WH, 2.4, 1.8, 1.2)
b.cyl((9.5, -4.0, WH + 0.6), 0.55, 1.2, 8, "Metal", caps="t")
b.cyl((9.5, -4.0, WH + 1.3), 0.7, 0.2, 8, "MetalDark", caps="t")
b.abox(-1.0, 1.4, -2.0, 0.8, WH, WH + 1.4, W_, "-z")
b.abox(-1.2, 1.6, -2.2, 1.0, WH + 1.4, WH + 1.6, OR, "-z")

A.mesh(b, "Body")

# ------------------------------------------------------------------ collision (bays stay open!)
c = HB("garage_shop_col")
t_ = 0.4
c.abox(X0, X0 + t_, Y0, Y1, 0, WH, "Concrete", "-z")                    # left wall
c.abox(X1 - t_, X1, Y0, Y1, 0, WH, "Concrete", "-z")                    # right wall
c.abox(X0 + t_, X1 - t_, Y0, Y0 + t_, 0, WH, "Concrete", "-z")          # back wall
c.abox(X0 + t_, -10.8, Y1 - t_, Y1, 0, WH, "Concrete", "-z")            # front piers
c.abox(-5.2, -4.4, Y1 - t_, Y1, 0, WH, "Concrete", "-z")
c.abox(4.4, 5.2, Y1 - t_, Y1, 0, WH, "Concrete", "-z")
c.abox(10.8, X1 - t_, Y1 - t_, Y1, 0, WH, "Concrete", "-z")
c.abox(-4.4, 4.4, 2.8, Y1, 0, WH, "Concrete", "-z")                      # office
for x in BAYS:
    c.abox(x - 2.8, x + 2.8, Y1 - t_, Y1, 4.2, WH, "Concrete", "-z")     # lintels
c.abox(X0, X1, Y0, Y1, WH, WH + 0.3, "Concrete", "-z")                    # roof slab
for sx in (-1, 1):
    px = HX + sx * 2.25
    c.abox(px - 0.2, px + 0.2, -3.3, -2.7, 0, 3.7, "Concrete", "-z")
A.mesh(c, "Collision", uv=None, winuv=False)

A.mark("Door", (0.0, 8.0, 0.0))
A.mark("BayEntry", (BAYS[0], Y1, 0.0))
A.mark("BayInside", (BAYS[0], -1.5, 0.0))
A.mark("BayEntry_B", (BAYS[1], Y1, 0.0))
A.mark("BayInside_B", (BAYS[1], -1.5, 0.0))
rep = A.report()
