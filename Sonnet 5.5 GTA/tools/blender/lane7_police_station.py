"""lane7 police_station: 30 x 22 m, 3 floors, blue-grey + white trim, shield emblem, helipad, garage bays, flagpole, bollards.
Run inside Blender (gta_lib + lane7_lib already exec'd):  exec(open(path, encoding="utf8").read(), globals())"""
A = Asset("police_station", 0)
b = HB("police_station_body")

X0, X1, Y0, Y1 = -15.0, 15.0, -11.0, 8.0         # main block (forecourt y 8..11 in front)
Z1 = 11.4                                           # roof deck
HX, HY = 15.0, 9.5
CY = (Y0 + Y1) / 2
WALL = "PoliceBlue"
WH, WIN_H = 1.9, 2.0

# ------------------------------------------------------------------ main block walls
F = Side(b, "F", 0, CY, HX, HY)
Bk = Side(b, "B", 0, CY, HX, HY)
Lw = Side(b, "L", 0, CY, HX, HY)
Rw = Side(b, "R", 0, CY, HX, HY)

def fx(S, xs, rows, w, h=None):
    return hgrid([S.u(x) for x in xs], rows, w, h)

rows_up = [(5.2, 2.0), (8.8, 2.0)]
wing_x = [-13.0, -10.0, -7.0, 7.0, 10.0, 13.0]
holes_F = fx(F, wing_x, [(1.3, 1.9)] + rows_up, 2.0)
# right wing ground floor: garage doors instead of windows
holes_F = [h for h in holes_F if not (abs(h[2] - 1.3) < 0.01 and (h[0] + h[1]) / 2 < 0)]
garage_x = [8.0, 12.0]
garage_holes = [(F.u(x) - 1.6, F.u(x) + 1.6, 0.0, 3.3) for x in garage_x]
pav_hole = (-5.0, 5.0, 0.0, Z1)   # covered by the entrance pavilion
F.wall(-HX, HX, 0, Z1, holes_F + garage_holes + [pav_hole], WALL)
F.wins([h for h in holes_F if h[2] > 1.2 and h[2] < 1.5], depth=0.25, frame="TrimWhite", sill=0.2)
F.wins([h for h in holes_F if h[2] > 5.0], depth=0.25, frame="TrimWhite")
for h in garage_holes:
    F.reveal(h, 0.4, "PoliceNavy", "lrt")
    F.q(h[0], h[1], h[2], h[3], -0.4, "Metal")
    for k in range(7):
        v = 0.35 + k * 0.45
        F.q(h[0] + 0.12, h[1] - 0.12, v, v + 0.07, -0.37, "MetalDark")
    F.q(h[0] + 0.5, h[1] - 0.5, 2.55, 3.05, -0.37, "Window")     # glazed vision strip
    F.box(h[0] - 0.1, h[1] + 0.1, 3.3, 3.55, 0.0, 0.3, "PoliceNavy", skip="ibl")

holes_B = fx(Bk, [-12 + 4 * i for i in range(7)], [(1.3, 1.9)] + rows_up, 1.8)
Bk.openings(-HX, HX, 0, Z1, holes_B, WALL, depth=0.2, frame="TrimWhite")
ys = [-8.0, -4.0, 0.0, 4.0]
holes_L = fx(Lw, ys, [(1.3, 1.9)] + rows_up, 1.8)
Lw.openings(-HY, HY, 0, Z1, holes_L, WALL, depth=0.2, frame="TrimWhite")
holes_R = fx(Rw, ys, [(1.3, 1.9)] + rows_up, 1.8)
Rw.openings(-HY, HY, 0, Z1, holes_R, WALL, depth=0.2, frame="TrimWhite")
b.zq(Z1, X0, X1, Y0, Y1, 1, "Roof")

# white pilasters between the window columns (front wings)
for x in (-14.5, -11.5, -8.5, -5.5, 5.5, 8.5, 11.5, 14.5):
    uu = F.u(x)
    F.box(uu - 0.16, uu + 0.16, 4.4, 10.95, 0.0, 0.17, "TrimWhite", skip="ib")
# floor-line bands + cornice rings (white)
for z0, z1, o in ((4.0, 4.4, 0.22), (7.6, 8.0, 0.22)):
    b.abox(X0 - o, X1 + o, Y0 - o, Y1 + o, z0, z1, "TrimWhite")
b.abox(X0 - 0.45, X1 + 0.45, Y0 - 0.45, Y1 + 0.45, 11.0, 11.6, "TrimWhite")
# navy + emissive stripe under the cornice (front + sides)
for S in (F, Lw, Rw, Bk):
    S.q(-S.half, S.half, 10.62, 10.9, 0.02, "PoliceNavy")
# parapet (white) on top of the cornice
t = 0.3
pz0, pz1 = 11.6, 12.3
b.abox(X0 - 0.45, X1 + 0.45, Y1 + 0.45 - t, Y1 + 0.45, pz0, pz1, "TrimWhite", "-z")
b.abox(X0 - 0.45, X1 + 0.45, Y0 - 0.45, Y0 - 0.45 + t, pz0, pz1, "TrimWhite", "-z")
b.abox(X0 - 0.45, X0 - 0.45 + t, Y0 - 0.45 + t, Y1 + 0.45 - t, pz0, pz1, "TrimWhite", "-z")
b.abox(X1 + 0.45 - t, X1 + 0.45, Y0 - 0.45 + t, Y1 + 0.45 - t, pz0, pz1, "TrimWhite", "-z")
b.zq(11.6, X0 - 0.45, X1 + 0.45, Y0 - 0.45, Y1 + 0.45, 1, "Roof")

# ------------------------------------------------------------------ entrance pavilion (white tower with the shield emblem)
PY0, PY1, PZ = 8.0, 9.6, 13.4
P = Side(b, "F", 0, (PY0 + PY1) / 2, 5.0, (PY1 - PY0) / 2)
Pl = Side(b, "L", 0, (PY0 + PY1) / 2, 5.0, (PY1 - PY0) / 2)
Pr = Side(b, "R", 0, (PY0 + PY1) / 2, 5.0, (PY1 - PY0) / 2)
door_hole = (-1.95, 1.95, 0.0, 3.3)
slit_holes = [(-4.7, -3.9, 4.8, 11.6), (3.9, 4.7, 4.8, 11.6)]
P.wall(-5.0, 5.0, 0, PZ, [door_hole] + slit_holes, "TrimWhite")
P.reveal(door_hole, 0.8, "PoliceNavy", "lrt")
P.q(door_hole[0], door_hole[1], 0, 3.3, -0.8, "Window")
P.q(-0.05, 0.05, 0, 3.3, -0.77, "Metal")
P.q(door_hole[0], door_hole[1], 2.55, 2.65, -0.77, "Metal")
for s in (-1, 1):
    P.box(s * 0.35 - 0.04, s * 0.35 + 0.04, 1.0, 1.9, -0.8, -0.65, "Chrome", skip="ibt")
for h in slit_holes:
    P.win(h, depth=0.3, frame="PoliceNavy")
Pl.wall(-0.8, 0.8, 0, PZ, [], "TrimWhite")
Pr.wall(-0.8, 0.8, 0, PZ, [], "TrimWhite")
b.zq(PZ, -5.0, 5.0, PY0, PY1, 1, "Roof")
b.abox(-5.3, 5.3, PY0, PY1 + 0.3, PZ, PZ + 0.5, "PoliceNavy", "-y")      # pavilion crown
b.yq(PY1 + 0.31, -5.3, 5.3, PZ + 0.15, PZ + 0.35, 1, "LightBlue")
b.abox(-3.0, 3.0, PY0 + 0.4, PY1 - 0.1, PZ + 0.5, PZ + 0.95, "TrimWhite", "-y")
# shield emblem on a navy panel flanked by white fins
P.q(-2.7, 2.7, 4.4, 11.8, 0.03, "PoliceNavy")
for sgn in (-1, 1):
    P.box(sgn * 3.05 - 0.2, sgn * 3.05 + 0.2, 4.4, 12.4, 0.0, 0.35, "TrimWhite", skip="ib")
def shield(sc, d, mat, cu=0.0, cv=8.4):
    pts = [(-1.7, 2.3), (1.7, 2.3), (1.7, -0.2), (0.95, -1.3), (0.0, -2.0), (-0.95, -1.3), (-1.7, -0.2)]
    P.poly([(cu + p[0] * sc, cv + p[1] * sc) for p in pts], d, mat)
shield(1.1, 0.06, "TrimWhite")
shield(0.93, 0.09, "LightBlue")
star = []
for i in range(10):
    r = 1.05 if i % 2 == 0 else 0.46
    a = math.pi / 2 + i * math.pi / 5
    star.append((r * math.cos(a), 8.55 + r * math.sin(a)))
P.poly(star, 0.12, "NeonWhite")
P.q(-2.7, 2.7, 4.4, 4.6, 0.05, "LightBlue")
P.q(-2.7, 2.7, 11.6, 11.8, 0.05, "LightBlue")
# canopy over the entrance
b.abox(-4.9, 4.9, PY1, 10.95, 3.55, 3.9, "TrimWhite")
b.zq(3.54, -4.9, 4.9, PY1, 10.95, -1, "LampGlow")
b.yq(10.96, -4.9, 4.9, 3.6, 3.7, 1, "LightBlue")
for sx in (-4.4, 4.4):
    b.cyl((sx, 10.6, 1.775), 0.17, 3.55, 6, "TrimWhite", caps="t")
b.abox(-4.5, 4.5, PY1, 11.0, 0.0, 0.14, "Concrete", "-z -y")          # entrance steps / landing

# ------------------------------------------------------------------ forecourt, bollards, flag
b.abox(X0, X1, 8.0, 11.0, 0.0, 0.1, "Concrete", "-z -x +x -y")
for z0 in (0.0,):
    for x in (-6.2, -7.8, -9.4, -11.0, -12.6, -14.2, 6.2, 7.8, 9.4, 11.0, 12.6, 14.2):
        b.cyl((x, 10.7, 0.45), 0.13, 0.9, 6, "Metal", caps="t")
        b.cyl((x, 10.7, 0.8), 0.135, 0.1, 6, "Hazard", caps="t")
# parking-bay lines in front of the garage doors
for x in (6.4, 10.0, 13.6):
    b.zq(0.11, x - 0.06, x + 0.06, 8.4, 10.3, 1, "RailYellow")
# flagpole
FPX, FPY = -9.0, 9.9
b.beam((FPX, FPY, 0.1), (FPX, FPY, 10.0), 0.09, 0.06, 6, "Metal")
b.ball((FPX, FPY, 10.1), 0.16, 5, 2, "Hazard")
fz0, fz1 = 7.7, 9.5
fp = lambda x0f, x1f, za, zb, w0, w1: [(x0f, FPY + w0, za), (x1f, FPY + w1, za - 0.05 * (x1f - x0f)), (x1f, FPY + w1, zb - 0.05 * (x1f - x0f)), (x0f, FPY + w0, zb)]
for pts, mname in ((fp(FPX + 0.1, FPX + 2.3, fz0 + 0.5, fz1, 0.0, 0.2), "FlagBlue"), (fp(FPX + 0.1, FPX + 2.3, fz0, fz0 + 0.5, 0.0, 0.2), "Hazard")):
    b.pq(pts, (0, 1, 0), mname)
    b.pq(pts, (0, -1, 0), mname)
sp = [(FPX + 0.9 + 0.32 * math.cos(i * math.pi / 3), 8.85 + 0.32 * math.sin(i * math.pi / 3)) for i in range(6)]
for sgn, off in ((1, 0.02), (-1, -0.02)):
    pts = [(x, FPY + 0.06 + off, z) for x, z in sp]
    b.pq(pts, (0, sgn, 0), "TrimWhite")

# ------------------------------------------------------------------ roof: helipad, mast, AC, stair house
HPX, HPY = 8.0, -4.5
b.cyl((HPX, HPY, Z1 + 0.15), 5.4, 0.3, 16, "ConcreteDk", caps="t")
b.annulus((HPX, HPY, Z1 + 0.31), 4.45, 4.75, 16, 1, "RailYellow")
for (cx_, cy_, sx_, sy_) in ((HPX - 1.15, HPY, 0.42, 3.3), (HPX + 1.15, HPY, 0.42, 3.3), (HPX, HPY, 2.3, 0.42)):
    b.zq(Z1 + 0.32, cx_ - sx_ / 2, cx_ + sx_ / 2, cy_ - sy_ / 2, cy_ + sy_ / 2, 1, "TrimWhite")
for k in range(8):
    a = k * math.pi / 4 + math.pi / 8
    b.cyl((HPX + 5.55 * math.cos(a), HPY + 5.55 * math.sin(a), Z1 + 0.34), 0.1, 0.12, 4, "LightAmber", caps="t")
# stair/elevator house
b.abox(-4.0, 0.5, -9.5, -5.5, Z1, Z1 + 2.8, "PoliceBlue", "-z")
b.abox(-4.3, 0.8, -9.8, -5.2, Z1 + 2.8, Z1 + 3.0, "TrimWhite", "-z")
b.yq(-5.5 + 0.02, -3.0, -1.4, Z1, Z1 + 2.1, 1, "Metal")
# AC units
for (ax_, ay_) in ((-12.0, -4.0), (-12.0, -8.5), (-7.0, 3.0), (-1.5, 3.5)):
    b.abox(ax_ - 1.0, ax_ + 1.0, ay_ - 0.8, ay_ + 0.8, Z1, Z1 + 1.1, "Metal", "-z")
    b.cyl((ax_, ay_, Z1 + 1.12), 0.55, 0.06, 6, "MetalDark", caps="t")
# antenna mast with beacon
MX, MY = -2.5, -8.0
b.beam((MX, MY, Z1), (MX, MY, Z1 + 9.0), 0.12, 0.05, 6, "Metal")
b.abox(MX - 0.9, MX + 0.9, MY - 0.03, MY + 0.03, Z1 + 6.2, Z1 + 6.3, "Metal")
b.abox(MX - 0.6, MX + 0.6, MY - 0.03, MY + 0.03, Z1 + 7.4, Z1 + 7.5, "Metal")
b.cbox((MX, MY, Z1 + 9.1), (0.22, 0.22, 0.22), "LightRed")
# blue strobe housings at roof corners
for (sx_, sy_) in ((X0 + 0.5, Y1 - 0.5), (X1 - 0.5, Y1 - 0.5)):
    b.cbox((sx_, sy_, 12.6), (0.4, 0.4, 0.5), "LightBlue", "-z")

A.mesh(b, "Body")

# ------------------------------------------------------------------ collision
c = HB("police_station_col")
c.abox(X0, X1, Y0, Y1, 0, Z1, "Concrete", "-z")
c.abox(-5, 5, 8.0, 9.6, 0, PZ, "Concrete", "-z -y")
for sx in (-4.4, 4.4):
    c.abox(sx - 0.18, sx + 0.18, 10.42, 10.78, 0, 3.55, "Concrete", "-z")
for x in (-6.2, -7.8, -9.4, -11.0, -12.6, -14.2, 6.2, 7.8, 9.4, 11.0, 12.6, 14.2):
    c.abox(x - 0.14, x + 0.14, 10.56, 10.84, 0, 0.9, "Concrete", "-z -y -x")
c.abox(FPX - 0.1, FPX + 0.1, FPY - 0.1, FPY + 0.1, 0, 3.0, "Concrete", "-z -y -x")
A.mesh(c, "Collision", uv=None, winuv=False)

A.mark("Door", (0.0, 10.4, 0.0))
A.mark("GarageDoor", (10.0, 9.6, 0.0))
A.mark("RoofHelipad", (HPX, HPY, Z1 + 0.32))
rep = A.report()
