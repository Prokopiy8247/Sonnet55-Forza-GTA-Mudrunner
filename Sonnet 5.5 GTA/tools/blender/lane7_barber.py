"""lane7 barber: 8 x 10 m brick barber shop, striped awning, scissors neon, separate BarberPole mesh (helical stripes), chairs inside."""
A = Asset("barber", 7)
b = HB("barber_body")

X0, X1, Y0, Y1 = -4.0, 4.0, -5.0, 4.4
TOP = 5.2
CY = (Y0 + Y1) / 2
HY = (Y1 - Y0) / 2
BR, WHT, PLUM = "BrickRed", "TrimWhite", "PlumDk"
F = Side(b, "F", 0, CY, 4, HY)
Bk = Side(b, "B", 0, CY, 4, HY)
Lw = Side(b, "L", 0, CY, 4, HY)
Rw = Side(b, "R", 0, CY, 4, HY)

# ---------------------------------------------------------------- front
win = (F.u(0.4), F.u(-3.2), 0.55, 3.4)        # large pane (x -3.2..0.4)
win = (min(win[0], win[1]), max(win[0], win[1]), win[2], win[3])
door = (F.u(2.6), F.u(1.0), 0.0, 2.6)
door = (min(door[0], door[1]), max(door[0], door[1]), 0.0, 2.6)
F.wall(-4, 4, 0, TOP, [win, door], BR)
F.reveal(win, 0.22, WHT, "lrtb")
F.q(win[0], win[1], win[2], win[3], -0.22, "Glass")
for k in (1, 2):
    u = win[0] + (win[1] - win[0]) * k / 3
    F.q(u - 0.035, u + 0.035, win[2], win[3], -0.2, "MetalDark")
F.reveal(door, 0.3, WHT, "lrt")
F.q(door[0], door[1], 0, 2.6, -0.3, "Wood")
F.q(door[0] + 0.25, door[1] - 0.25, 1.1, 2.4, -0.28, "Glass")
F.box(door[0] + 0.1, door[0] + 0.2, 0.9, 1.5, -0.32, -0.2, "Chrome", skip="ibt")
F.box(-4.1, 4.1, 0.0, 0.5, 0.0, 0.12, WHT, skip="i")                          # plinth
# sign panel with scissors
F.q(-3.7, 3.7, 3.95, 5.05, 0.03, PLUM)
F.box(-3.8, 3.8, 3.9, 3.98, 0.0, 0.1, WHT, skip="ib")
F.box(-3.8, 3.8, 5.05, 5.13, 0.0, 0.1, WHT, skip="ib")
vc = 4.5
dd = 0.07
for sg, mm in ((1, "NeonRed"), (-1, "NeonRed")):
    cu, cv = -1.15, vc + sg * 0.3
    for k in range(10):
        a0, a1 = 2 * math.pi * k / 10, 2 * math.pi * (k + 1) / 10
        F.poly([(cu + 0.26 * math.cos(a0), cv + 0.26 * math.sin(a0)), (cu + 0.26 * math.cos(a1), cv + 0.26 * math.sin(a1)),
                (cu + 0.15 * math.cos(a1), cv + 0.15 * math.sin(a1)), (cu + 0.15 * math.cos(a0), cv + 0.15 * math.sin(a0))], dd, mm)
F.stroke((-0.9, vc + 0.3 - 0.06), (1.9, vc - 0.28), 0.1, dd, "NeonCyan")
F.stroke((-0.9, vc - 0.3 + 0.06), (1.9, vc + 0.28), 0.1, dd, "NeonCyan")
F.poly([(0.55 + 0.1 * math.cos(2 * math.pi * k / 6), vc + 0.1 * math.sin(2 * math.pi * k / 6)) for k in range(6)], dd + 0.01, "NeonWhite")
# awning
awning(b, -3.8, 3.8, Y1, 3.9, 0.6, 0.45, 8, "BarberRed", "AwningWhite")
# bracket arms for the pole (pole sits right of the door)
PXW, PYW = 3.35, Y1 + 0.5
for z in (1.75, 3.0):
    b.beam((PXW, Y1, z), (PXW, PYW, z), 0.035, 0.035, 4, "Chrome")

# ---------------------------------------------------------------- sides and back
sh = [(u - 0.6, u + 0.6, 1.3, 3.5) for u in (-2.5, 1.5)]
for S in (Lw, Rw):
    S.openings(-HY, HY, 0, TOP, sh, BR, depth=0.2, frame=WHT, sill=0.25)
bdoor = (-0.8, 0.8, 0.0, 2.4)
Bk.wall(-4, 4, 0, TOP, [bdoor, (-3.2, -1.8, 1.3, 3.2), (1.8, 3.2, 1.3, 3.2)], BR)
Bk.reveal(bdoor, 0.3, WHT, "lrt")
Bk.q(-0.8, 0.8, 0, 2.4, -0.3, "MetalDark")
for h in ((-3.2, -1.8, 1.3, 3.2), (1.8, 3.2, 1.3, 3.2)):
    Bk.win(h, depth=0.2, frame=WHT)
b.zq(TOP, X0, X1, Y0, Y1, 1, "Roof")
b.abox(X0 - 0.2, X1 + 0.2, Y0 - 0.2, Y1 + 0.2, TOP - 0.28, TOP + 0.08, WHT, "-z")
parapet(b, X0 - 0.2, X1 + 0.2, Y0 - 0.2, Y1 + 0.2, TOP + 0.08, TOP + 0.8, 0.26, WHT)
# faceted pediment on the front
b.ey([(-2.4, TOP + 0.8), (2.4, TOP + 0.8), (2.4, TOP + 1.2), (1.5, TOP + 1.9), (-1.5, TOP + 1.9), (-2.4, TOP + 1.2)], Y1 + 0.2 - 0.28, Y1 + 0.2, BR, caps=(False, True))
b.yq(Y1 + 0.21, -1.6, 1.6, TOP + 1.25, TOP + 1.33, 1, "NeonRed")
b.yq(Y1 + 0.21, -1.0, 1.0, TOP + 1.5, TOP + 1.58, 1, "NeonCyan")
ac_unit(b, -1.5, -2.5, TOP, 2.0, 1.5, 1.0)
b.cyl((2.0, -3.0, TOP + 0.7), 0.35, 1.4, 6, "Metal", caps="t")

# ---------------------------------------------------------------- interior (through the glass)
IY = 0.6
b.zq(0.1, X0 + 0.3, X1 - 0.3, IY, Y1 - 0.3, 1, "Trim")
for i in range(6):
    for j in range(3):
        if (i + j) % 2 == 0:
            b.zq(0.11, X0 + 0.3 + i * (7.4 / 6), X0 + 0.3 + (i + 1) * (7.4 / 6), IY + j * ((Y1 - 0.3 - IY) / 3), IY + (j + 1) * ((Y1 - 0.3 - IY) / 3), 1, WHT)
b.yq(IY, X0 + 0.3, X1 - 0.3, 0.1, 3.5, 1, "TileTeal")
b.zq(3.5, X0 + 0.3, X1 - 0.3, IY, Y1 - 0.3, -1, WHT)
b.zq(3.49, -3.0, 3.0, 1.6, 3.2, -1, "LampGlow")
for mx in (-1.9, 0.9):                      # mirrors
    b.abox(mx - 1.0, mx + 1.0, IY, IY + 0.08, 1.1, 2.8, "Wood", "-z -y")
    b.yq(IY + 0.09, mx - 0.88, mx + 0.88, 1.22, 2.68, 1, "Chrome")
b.abox(X0 + 0.3, X1 - 0.3, IY, IY + 0.4, 0.95, 1.05, "Wood", "-z")            # counter
for k in range(7):
    x = -3.2 + k * 0.5
    b.cyl((x, IY + 0.2, 1.2), 0.07, 0.3, 5, "BarberBlue" if k % 2 else "Hazard", caps="t")

def chair(cx, cy):
    b.cyl((cx, cy, 0.07), 0.3, 0.14, 6, "MetalDark", caps="t")
    b.cyl((cx, cy, 0.4), 0.07, 0.5, 5, "Chrome", caps="")
    b.abox(cx - 0.32, cx + 0.32, cy - 0.32, cy + 0.32, 0.62, 0.78, "BarberRed", "-z")
    b.abox(cx - 0.3, cx + 0.3, cy + 0.2, cy + 0.34, 0.78, 1.5, "BarberRed", "-z")
    for sx in (-0.38, 0.38):
        b.abox(cx + sx - 0.04, cx + sx + 0.04, cy - 0.25, cy + 0.2, 0.78, 0.92, "Chrome", "-z")
    b.abox(cx - 0.25, cx + 0.25, cy - 0.5, cy - 0.3, 0.3, 0.38, "Chrome", "-z")

chair(-1.9, 2.0)
chair(0.9, 2.0)
for x in (-1.9, 0.9, 2.6):
    b.cbox((x, 2.2, 3.15), (0.25, 0.25, 0.3), "LampGlow")
    b.beam((x, 2.2, 3.3), (x, 2.2, 3.5), 0.012, 0.012, 3, "Metal")

A.mesh(b, "Body")

# ---------------------------------------------------------------- barber pole (separate mesh, origin = pole centre, axis Z)
pb = HB("barber_pole")
R_ = 0.17
H_ = 1.25
pb.cyl((0, 0, 0), R_, H_, 8, WHT, caps="")
turns = 1.5
for s_ in range(6):
    base = s_ * (2 * math.pi / 6)
    mname = "BarberRed" if s_ % 3 == 0 else ("BarberBlue" if s_ % 3 == 1 else None)
    if mname is None:
        continue
    K = 10
    for k in range(K):
        t0, t1 = k / K, (k + 1) / K
        a0, a1 = base + t0 * turns * 2 * math.pi, base + t1 * turns * 2 * math.pi
        w = 0.55
        z0, z1 = -H_ / 2 + t0 * H_, -H_ / 2 + t1 * H_
        rr = R_ + 0.006
        pts = [(rr * math.cos(a0), rr * math.sin(a0), z0), (rr * math.cos(a0 + w), rr * math.sin(a0 + w), z0),
               (rr * math.cos(a1 + w), rr * math.sin(a1 + w), z1), (rr * math.cos(a1), rr * math.sin(a1), z1)]
        mid = (pts[0][0] + pts[2][0], pts[0][1] + pts[2][1], 0.0)
        pb.pq(pts, mid, mname)
for z, sg in ((H_ / 2 + 0.05, 1), (-H_ / 2 - 0.05, -1)):
    pb.cyl((0, 0, z), R_ + 0.05, 0.1, 8, "Accent", caps="t" if sg > 0 else "b")
pb.cyl((0, 0, H_ / 2 + 0.16), 0.07, 0.12, 6, "Chrome", caps="t")
pb.ball((0, 0, H_ / 2 + 0.26), 0.09, 6, 3, "Accent")
pole = A.mesh(pb, "BarberPole", loc=(PXW, PYW, 2.4), winuv=False)

c = HB("barber_col")
c.abox(X0, X1, Y0, Y1, 0, TOP + 0.8, "Concrete", "-z")
A.mesh(c, "Collision", uv=None, winuv=False)
A.mark("Door", (1.8, 4.8, 0.0))
rep = A.report()
