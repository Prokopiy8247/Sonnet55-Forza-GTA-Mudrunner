"""lane7 train_station: 28 x 24 m. Brick station building (y 0.5..11.2) with clock tower, platform A behind it, track gap,
island platform B with a faceted barrel-vault canopy, ramps, benches, lamps. Origin = footprint centre, door toward +Y."""
A = Asset("train_station", 9)
b = HB("train_station_body")
BRK, CRM, WHT, DK = "BrickRed", "Cream", "TrimWhite", "ConcreteDk"
WH, HH = 5.4, 8.2                     # wing / hall wall heights
YB, YF = 0.5, 11.2                    # building rear / front planes
CYB, HYB = (YB + YF) / 2, (YF - YB) / 2
PLAT = 0.9                            # platform height above rail level

# ---------------------------------------------------------------- wings
def wing(sx):
    cx = sx * 10.5
    F = Side(b, "F", cx, CYB, 3.5, HYB)
    Bk = Side(b, "B", cx, CYB, 3.5, HYB)
    Out = Side(b, "L" if sx < 0 else "R", cx, CYB, 3.5, HYB)
    fw = [(F.u(cx + dx) - 0.8, F.u(cx + dx) + 0.8, 1.1, 3.9) for dx in (-1.6, 1.6)]
    F.openings(-3.5, 3.5, 0, WH, fw, BRK, depth=0.25, frame=CRM, sill=0.25)
    bw = [(Bk.u(cx + dx) - 0.7, Bk.u(cx + dx) + 0.7, PLAT + 0.1, PLAT + 2.7) for dx in (-1.5, 1.5)]
    Bk.openings(-3.5, 3.5, 0, WH, bw, BRK, depth=0.2, frame=CRM)
    ow = [(u - 0.8, u + 0.8, 1.1, 3.9) for u in (-3.5, 0.0, 3.5)]
    Out.openings(-HYB, HYB, 0, WH, ow, BRK, depth=0.25, frame=CRM, sill=0.25)
    x0, x1 = cx - 3.5, cx + 3.5
    b.abox(x0 - 0.2, x1 + 0.2, YB - 0.2, YF + 0.2, WH - 0.4, WH, CRM, "-z")            # cornice
    b.abox(x0 - 0.15, x1 + 0.15, YB - 0.15, YF + 0.15, 0.0, 0.5, "ConcreteDk", "-z")    # plinth
    b.hip(x0 - 0.35, x1 + 0.35, YB - 0.35, YF + 0.35, WH, 1.7, 1.7, 2.2, "Roof", "-z")
    return cx

wing(-1)
wing(+1)

# ---------------------------------------------------------------- central hall (x -7..7)
HF = Side(b, "F", 0, CYB, 7.0, HYB)
HB_ = Side(b, "B", 0, CYB, 7.0, HYB)
tower_hole = (-2.4, 2.4, 0.0, HH)
hole_f = [(HF.u(x) - 0.9, HF.u(x) + 0.9, 1.0, 6.0) for x in (-5.0, 5.0)]
HF.wall(-7, 7, 0, HH, hole_f + [tower_hole], BRK)
HF.wins(hole_f, depth=0.25, frame=CRM, sill=0.3)
hole_b = [(HB_.u(x) - 0.7, HB_.u(x) + 0.7, PLAT + 0.1, PLAT + 3.4) for x in (-4.5, 0.0, 4.5)] + [(HB_.u(x) - 0.8, HB_.u(x) + 0.8, 5.0, 7.2) for x in (-5.0, -1.7, 1.7, 5.0)]
HB_.openings(-7, 7, 0, HH, hole_b, BRK, depth=0.22, frame=CRM)
for sx in (-7.0, 7.0):
    S = Side(b, "L" if sx < 0 else "R", 0, CYB, 7.0, HYB)
    S.q(-HYB, HYB, WH, HH, 0.0, BRK)
b.abox(-7.2, 7.2, YB - 0.25, YF + 0.25, HH - 0.4, HH, CRM, "-z")
# gable roof along X
b.ex([(YB - 0.4, HH), (YF + 0.4, HH), ((YB + YF) / 2, HH + 2.4)], -7.4, 7.4, "Roof", caps=(False, False), skip_edges=(0,))
for sx, sg in ((-7.2, -1), (7.2, 1)):
    b.pq([(sx, YB, HH), (sx, YF, HH), (sx, (YB + YF) / 2, HH + 2.2)], (sg, 0, 0), BRK)
b.beam((-7.4, (YB + YF) / 2, HH + 2.4), (7.4, (YB + YF) / 2, HH + 2.4), 0.12, 0.12, 4, "Slate", caps=False)

# ---------------------------------------------------------------- clock tower (front centre)
TX0, TX1, TY0, TY1 = -2.4, 2.4, 7.2, 11.6
TCY = (TY0 + TY1) / 2
TF = Side(b, "F", 0, TCY, 2.4, (TY1 - TY0) / 2)
TL = Side(b, "L", 0, TCY, 2.4, (TY1 - TY0) / 2)
TR = Side(b, "R", 0, TCY, 2.4, (TY1 - TY0) / 2)
TB = Side(b, "B", 0, TCY, 2.4, (TY1 - TY0) / 2)
door = (-1.3, 1.3, 0.0, 3.6)
TF.wall(-2.4, 2.4, 0, 16.0, [door], CRM)
TF.reveal(door, 0.7, WHT, "lrt")
TF.q(door[0], door[1], 0, 3.6, -0.7, "Window")
for u in (-0.65, 0.0, 0.65):
    TF.q(u - 0.04, u + 0.04, 0, 3.6, -0.67, "MetalDark")
TF.q(door[0], door[1], 2.6, 2.7, -0.67, "MetalDark")
TF.box(-1.7, 1.7, 3.7, 4.0, 0.0, 0.5, WHT, skip="ib")
TF.q(-1.3, 1.3, 3.75, 3.85, 0.52, "LampGlow")
for S in (TL, TR):
    S.q(-(TY1 - TY0) / 2, (TY1 - TY0) / 2, HH, 16.0, 0.0, CRM)
TL.q(-(TY1 - TCY), -(YF - TCY), 0.0, HH, 0.0, CRM)
TR.q(YF - TCY, TY1 - TCY, 0.0, HH, 0.0, CRM)
TB.q(-2.4, 2.4, HH + 2.4, 16.0, 0.0, CRM)
# bands + belfry
for z0, z1 in ((8.2, 8.5), (10.6, 10.8)):
    b.abox(TX0 - 0.15, TX1 + 0.15, TY0 - 0.15, TY1 + 0.15, z0, z1, WHT)
for (S, sgn) in ((TF, 0), (TL, 1), (TR, 2)):
    # belfry louvre opening
    S.q(-0.8, 0.8, 14.4, 15.7, 0.03, "Window")
    S.box(-0.95, 0.95, 14.25, 14.4, 0.0, 0.2, WHT, skip="ib")
    # clock face
    cu, cv, r = 0.0, 12.3, 1.25
    for k in range(10):
        a0, a1 = 2 * math.pi * k / 10, 2 * math.pi * (k + 1) / 10
        S.poly([(cu + (r + 0.2) * math.cos(a0), cv + (r + 0.2) * math.sin(a0)), (cu + (r + 0.2) * math.cos(a1), cv + (r + 0.2) * math.sin(a1)),
                (cu + r * math.cos(a1), cv + r * math.sin(a1)), (cu + r * math.cos(a0), cv + r * math.sin(a0))], 0.07, "Copper")
    S.poly([(cu + r * math.cos(2 * math.pi * k / 10), cv + r * math.sin(2 * math.pi * k / 10)) for k in range(10)], 0.06, "ClockFace")
    for ang in (0, 90, 180, 270):
        a = math.radians(ang)
        S.stroke((cu + 0.95 * math.cos(a), cv + 0.95 * math.sin(a)), (cu + 1.15 * math.cos(a), cv + 1.15 * math.sin(a)), 0.1, 0.08, "MetalDark")
    S.stroke((cu, cv), (cu + 0.2 + 0.0, cv + 0.62), 0.12, 0.08, "MetalDark")
    S.stroke((cu, cv), (cu + 0.85, cv - 0.35), 0.08, 0.085, "MetalDark")
b.abox(TX0 - 0.3, TX1 + 0.3, TY0 - 0.3, TY1 + 0.3, 16.0, 16.35, WHT)
b.hip(TX0 - 0.3, TX1 + 0.3, TY0 - 0.3, TY1 + 0.3, 16.35, 3.5, 2.3, 2.3, "Copper", "-z")
b.cyl((0, TCY, 20.6), 0.14, 1.6, 6, "Copper", r_top=0.03, caps="")
b.ball((0, TCY, 19.9), 0.24, 6, 3, "Copper")
b.beam((0, TCY, 21.4), (0.0, TCY + 0.7, 21.4), 0.02, 0.02, 3, "MetalDark")
# entrance stoop
b.abox(-2.2, 2.2, TY1, 12.0, 0.0, 0.2, "Concrete", "-z -y")

# ---------------------------------------------------------------- platforms
# A: behind the building (y -4.0..0.5), x -14..9 ; ramp down to the east end
b.abox(-14.0, 9.0, -3.5, YB, 0.0, PLAT, DK, "-z +y -x")
b.zq(PLAT + 0.01, -14.0, 9.0, -3.45, -3.15, 1, "RailYellow")
b.ey([(9.0, 0.0), (14.0, 0.0), (9.0, PLAT)], -3.2, -0.8, DK, caps=(True, True), skip_edges=(0,))
# B: island (y -13..-9), x -9..14 ; ramp down to the west end
b.abox(-9.0, 14.0, -12.0, -8.0, 0.0, PLAT, DK, "-z")
b.zq(PLAT + 0.01, -9.0, 14.0, -8.4, -8.1, 1, "RailYellow")
b.zq(PLAT + 0.01, -9.0, 14.0, -11.9, -11.6, 1, "RailYellow")
b.ey([(-9.0, PLAT), (-14.0, 0.0), (-9.0, 0.0)], -11.0, -9.0, DK, caps=(True, True), skip_edges=(2,))
# platform floor tiles (tactile strips)
for k in range(24):
    x = -13.5 + k * 1.0
    if k % 3 == 0 and x < 8.5:
        b.zq(PLAT + 0.012, x, x + 0.55, -3.4, -3.1, 1, "Hazard")

# canopy over A (lean-to from the building)
ZC0, ZC1 = 4.8, 4.3
b.pq([(-14.2, YB, ZC0), (14.2, YB, ZC0), (14.2, -3.8, ZC1), (-14.2, -3.8, ZC1)], (0, -0.1, 1), "Slate")
b.pq([(-14.2, YB, ZC0 - 0.15), (14.2, YB, ZC0 - 0.15), (14.2, -3.8, ZC1 - 0.15), (-14.2, -3.8, ZC1 - 0.15)], (0, 0.1, -1), "LampGlow")
b.abox(-14.2, 14.2, -3.8, -3.7, ZC1 - 0.45, ZC1 + 0.05, WHT)
for x in (-12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0):
    b.abox(x - 0.16, x + 0.16, -3.2 - 0.16, -3.2 + 0.16, PLAT, ZC1 - 0.45, "Cream", "-z")
    b.abox(x - 0.2, x + 0.2, -3.2 - 0.2, -3.2 + 0.2, PLAT, PLAT + 0.25, "ConcreteDk", "-z")

# barrel-vault canopy over B (faceted arc, extruded along X)
cy_, hw = -10.0, 2.2
arc_out, arc_in = [], []
N = 6
for k in range(N + 1):
    a = math.pi * (0.12 + 0.76 * k / N)
    arc_out.append((cy_ - hw * math.cos(a) * 1.0, 4.35 + 1.5 * math.sin(a)))
    arc_in.append((cy_ - (hw - 0.12) * math.cos(a), 4.35 + (1.5 - 0.12) * math.sin(a)))
prof = arc_out + list(reversed(arc_in))
b.ex(prof, -9.4, 14.4, "Slate", caps=(True, True))
for x in (-8.0, -3.0, 2.0, 7.0, 12.0):
    b.abox(x - 0.17, x + 0.17, cy_ - 0.17, cy_ + 0.17, PLAT, 5.0, "Cream", "-z")
    b.abox(x - 0.2, x + 0.2, cy_ - 0.2, cy_ + 0.2, PLAT, PLAT + 0.25, "ConcreteDk", "-z")
    b.abox(x - 0.55, x + 0.55, cy_ - 0.14, cy_ + 0.14, 4.6, 4.75, "Cream", "-z")
for x in (-6.0, 0.0, 6.0, 12.0):
    b.cbox((x, cy_ - 1.2, 4.35), (0.9, 0.35, 0.1), "LampGlow")
    b.cbox((x, cy_ + 1.2, 4.35), (0.9, 0.35, 0.1), "LampGlow")

# ---------------------------------------------------------------- platform furniture
def bench(x, y, ang90=False):
    b.abox(x - 0.9, x + 0.9, y - 0.22, y + 0.22, PLAT + 0.42, PLAT + 0.5, "Wood", "-z")
    b.abox(x - 0.9, x + 0.9, y + 0.18, y + 0.24, PLAT + 0.5, PLAT + 0.95, "Wood", "-z")
    for sx in (-0.75, 0.75):
        b.abox(x + sx - 0.04, x + sx + 0.04, y - 0.2, y + 0.2, PLAT, PLAT + 0.42, "MetalDark", "-z")

for x in (-10.5, -4.5, 4.5):
    bench(x, -1.0)
for x in (-5.0, 5.0, 9.0):
    bench(x, -11.2)
# platform marker signs (one bar = A, two bars = B) on lamp posts
for (sx, sy, nbars, face) in ((-6.5, -2.9, 1, 1), (-6.5, -8.7, 2, -1), (7.0, -2.9, 1, 1), (11.0, -8.7, 2, -1)):
    b.abox(sx - 0.06, sx + 0.06, sy - 0.06, sy + 0.06, PLAT, PLAT + 3.0, "MetalDark", "-z")
    b.abox(sx - 0.9, sx + 0.9, sy - 0.06, sy + 0.06, PLAT + 2.4, PLAT + 3.3, "MetalDark")
    for k in range(nbars):
        bx = sx + (k - (nbars - 1) / 2.0) * 0.5
        b.yq(sy + 0.062, bx - 0.14, bx + 0.14, PLAT + 2.55, PLAT + 3.15, 1, "NeonCyan")
        b.yq(sy - 0.062, bx - 0.14, bx + 0.14, PLAT + 2.55, PLAT + 3.15, -1, "NeonCyan")
# info board and clock on the building rear wall
b.abox(-1.2, 1.2, YB - 0.15, YB, 4.0, 4.9, "Slate", "-z +y")
b.yq(YB - 0.151, -1.0, 1.0, 4.15, 4.75, -1, "LightBlue")

# station sign band over the entrance (non-text: three emissive bars)
TF.q(-2.0, 2.0, 5.1, 6.4, 0.04, "Slate")
TF.q(-1.9, 1.9, 5.2, 5.3, 0.06, "NeonCyan")
TF.q(-1.9, 1.9, 6.2, 6.3, 0.06, "NeonCyan")
TF.poly([(-0.9, 5.75), (0.9, 5.75), (0.9, 5.9), (-0.9, 5.9)], 0.06, "NeonWhite")
TF.stroke((-1.7, 5.75), (-1.1, 5.75), 0.18, 0.07, "NeonAmber")
TF.stroke((1.1, 5.75), (1.7, 5.75), 0.18, 0.07, "NeonAmber")

A.mesh(b, "Body")

# ---------------------------------------------------------------- collision (platforms walkable, canopies not solid)
c = HB("train_station_col")
c.abox(-14, 14, YB, YF, 0, HH + 0.0, "Concrete", "-z")
c.abox(TX0, TX1, TY0, TY1, 0, 16.0, "Concrete", "-z")
c.abox(-14.0, 9.0, -3.5, YB, 0.0, PLAT, "Concrete", "-z -y")
c.abox(-9.0, 14.0, -12.0, -8.0, 0.0, PLAT, "Concrete", "-z")
c.ey([(9.0, 0.0), (14.0, 0.0), (9.0, PLAT)], -3.2, -0.8, "Concrete", caps=(True, True), skip_edges=(0,))
c.ey([(-9.0, PLAT), (-14.0, 0.0), (-9.0, 0.0)], -11.0, -9.0, "Concrete", caps=(True, True), skip_edges=(2,))
for x in (-12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0):
    c.abox(x - 0.16, x + 0.16, -3.36, -3.04, PLAT, ZC1, "Concrete", "-z")
for x in (-8.0, -3.0, 2.0, 7.0, 12.0):
    c.abox(x - 0.17, x + 0.17, cy_ - 0.17, cy_ + 0.17, PLAT, 5.0, "Concrete", "-z")
A.mesh(c, "Collision", uv=None, winuv=False)

A.mark("Door", (0.0, 12.3, 0.0))
A.mark("PlatformA", (0.0, -1.5, PLAT))
A.mark("PlatformB", (2.5, -10.0, PLAT))
rep = A.report()
