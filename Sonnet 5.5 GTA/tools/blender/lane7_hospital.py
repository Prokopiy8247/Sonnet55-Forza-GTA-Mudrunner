"""lane7 hospital: 40 x 28 m, 5-floor ribbon tower + two 3-floor wings + podium, white/teal, rooftop cross sign, ambulance bay, helipad."""
A = Asset("hospital", 1)
b = HB("hospital_body")

TOWER_Z = 18.8
WING_Z = 11.6
POD_Z = 8.0
W_ = "HospWhite"
T_ = "HospTeal"
TD = "HospTealDk"

rows5 = [(1.3, 3.5), (5.2, 7.2), (8.8, 10.8), (12.4, 14.4), (16.0, 18.0)]
rows3 = rows5[:3]

# ------------------------------------------------------------------ tower (x -9..9, y -10..8)
TCY = -1.0
TF = Side(b, "F", 0, TCY, 9, 9)
TB = Side(b, "B", 0, TCY, 9, 9)
TL = Side(b, "L", 0, TCY, 9, 9)
TR = Side(b, "R", 0, TCY, 9, 9)
bay_facade(TF, -9, 9, POD_Z, TOWER_Z, 6, [(8.8, 10.8), (12.4, 14.4), (16.0, 18.0)], wall=T_, fin_mat=W_, depth=0.18)
bay_facade(TB, -9, 9, 0, TOWER_Z, 6, rows5, wall=T_, fin_mat=W_, depth=0.18, skip_glass=[(i, r) for i in (2, 3) for r in range(5)],
           wall_extra_holes=[(-3, 3, 0, TOWER_Z)])
for S in (TL, TR):
    bay_facade(S, -9, 9, WING_Z, TOWER_Z, 5, rows5[3:], wall=T_, fin_mat=W_, depth=0.18)
b.zq(TOWER_Z, -9, 9, -10, 8, 1, "Roof")
parapet(b, -9, 9, -10, 8, TOWER_Z, TOWER_Z + 0.9, 0.3, W_)
b.abox(-9.2, 9.2, -10.2, 8.2, TOWER_Z - 0.5, TOWER_Z, W_)           # crown band

# back stair / elevator core
BC = Side(b, "B", 0, -12, 3, 2)
bay_facade(BC, -3, 3, 0, 21.0, 3, [(1.3, 3.5), (5.2, 7.2), (8.8, 10.8), (12.4, 14.4), (16.0, 18.0)], wall=TD, fin_mat=W_, fin_d=0.3, depth=0.15)
for S in (Side(b, "L", 0, -12, 3, 2), Side(b, "R", 0, -12, 3, 2)):
    S.q(-2, 2, 0, 21.0, 0.0, TD)
b.zq(21.0, -3, 3, -14, -10, 1, "Roof")
parapet(b, -3, 3, -14, -10, 21.0, 21.6, 0.25, W_, "FBLR")

# ------------------------------------------------------------------ wings (3 floors)
def wing(side):
    sx = side                                  # -1 left, +1 right
    cx = sx * 14.5
    F = Side(b, "F", cx, -1, 5.5, 11)
    B_ = Side(b, "B", cx, -1, 5.5, 11)
    Out = Side(b, "L" if sx < 0 else "R", cx, -1, 5.5, 11)
    In = Side(b, "R" if sx < 0 else "L", cx, -1, 5.5, 11)
    if sx > 0:
        # ER entrance under the ambulance canopy
        door = (-2.1, 2.1, 0.0, 3.4)
        bay_facade(F, -5.5, 5.5, 0, WING_Z, 3, rows3[1:], wall=W_, fin_mat=T_, depth=0.18, wall_extra_holes=[door])
        F.reveal(door, 0.8, TD, "lrt")
        F.q(door[0], door[1], 0, 3.4, -0.8, "Window")
        F.q(-0.05, 0.05, 0, 3.4, -0.77, "Metal")
        F.q(door[0] - 0.1, door[1] + 0.1, 3.5, 3.85, 0.04, "NeonRed")
        # side-by-side signage cross over the door
    else:
        door = (-1.6, 1.6, 0.0, 3.2)
        bay_facade(F, -5.5, 5.5, 0, WING_Z, 3, rows3[1:], wall=W_, fin_mat=T_, depth=0.18, wall_extra_holes=[door])
        F.reveal(door, 0.6, TD, "lrt")
        F.q(door[0], door[1], 0, 3.2, -0.6, "Window")
        F.q(-0.05, 0.05, 0, 3.2, -0.57, "Metal")
        F.q(door[0] - 0.1, door[1] + 0.1, 3.3, 3.55, 0.04, "NeonGreen")
    bay_facade(B_, -5.5, 5.5, 0, WING_Z, 3, rows3, wall=W_, fin_mat=T_, depth=0.18)
    bay_facade(Out, -11, 11, 0, WING_Z, 6, rows3, wall=W_, fin_mat=T_, depth=0.18)
    # strip of the inner wall that is not covered by the tower (y -12..-10)
    In.wall(-11, -9, 0, WING_Z, [], W_)
    b.zq(WING_Z, cx - 5.5, cx + 5.5, -12, 10, 1, "Roof")
    sides = "FB" + ("L" if sx < 0 else "R")
    parapet(b, cx - 5.5, cx + 5.5, -12, 10, WING_Z, WING_Z + 0.9, 0.3, W_, sides)
    b.abox(cx - 5.7, cx + 5.7, -12.2, 10.2, WING_Z - 0.4, WING_Z, T_, "-z")        # teal eaves band
    return cx

cxL = wing(-1)
cxR = wing(+1)

# ------------------------------------------------------------------ podium (x -9..9, y 8..12.8)
PCY = 10.4
PF = Side(b, "F", 0, PCY, 9, 2.4)
ground_edges = [-9.0, -5.8, -2.2, 2.2, 5.8, 9.0]
door_hole = (-2.2, 2.2, 0.0, 3.5)
bay_facade(PF, -9, 9, 0, 4.4, 5, [(0.0, 3.5)], wall=W_, fin_mat=W_, depth=0.2, edges=ground_edges, skip_glass=[(2, 0)], wall_extra_holes=[door_hole], fin_d=0.3)
PF.reveal(door_hole, 0.9, TD, "lrt")
PF.q(-2.2, 2.2, 0.0, 3.5, -0.9, "Window")
for uu in (-1.1, 0.0, 1.1):
    PF.q(uu - 0.04, uu + 0.04, 0.0, 3.5, -0.87, "Metal")
PF.q(-2.2, 2.2, 2.4, 2.5, -0.87, "Metal")
bay_facade(PF, -9, 9, 4.4, POD_Z, 6, [(5.0, 7.2)], wall=T_, fin_mat=W_, depth=0.2, fin_d=0.3)
# podium sides (visible part y 10..12.8) + terrace
for S, sgn in ((Side(b, "L", 0, PCY, 9, 2.4), -1), (Side(b, "R", 0, PCY, 9, 2.4), 1)):
    u0, u1 = (-2.4, 0.4) if sgn < 0 else (-0.4, 2.4)
    S.q(u0, u1, 0, POD_Z, 0.0, W_)
b.zq(POD_Z, -9, 9, 8, 12.8, 1, "Concrete")
parapet(b, -9, 9, 8, 12.8, POD_Z, POD_Z + 1.0, 0.3, W_, "FLR")
for px in (-6.5, 6.5):
    b.abox(px - 1.1, px + 1.1, 11.2, 12.3, POD_Z, POD_Z + 0.6, "Concrete")
    b.abox(px - 0.95, px + 0.95, 11.35, 12.15, POD_Z + 0.6, POD_Z + 0.85, "Leaf", "-z")
    b.ball((px - 0.2, 11.75, POD_Z + 1.2), 0.65, 6, 3, "LeafLight", sc=(1, 1, 0.9))
# entrance canopy + columns
b.abox(-4.8, 4.8, 12.8, 14.0, 4.55, 4.9, T_)
b.zq(4.54, -4.8, 4.8, 12.8, 14.0, -1, "LampGlow")
b.yq(14.01, -4.8, 4.8, 4.62, 4.82, 1, "NeonGreen")
for sx in (-4.4, 4.4):
    b.abox(sx - 0.22, sx + 0.22, 13.5, 13.94, 0, 4.55, W_, "-z")
b.abox(-5.0, 5.0, 12.8, 14.0, 0.0, 0.12, "Concrete", "-z -y")          # forecourt step

# ------------------------------------------------------------------ ambulance bay canopy (right wing front)
b.abox(10.2, 19.8, 10.0, 14.0, 4.5, 4.85, T_)
b.zq(4.49, 10.2, 19.8, 10.0, 14.0, -1, "LampGlow")
b.yq(14.01, 10.2, 19.8, 4.58, 4.78, 1, "LightRed")
for cxx in (10.6, 19.4):
    b.abox(cxx - 0.22, cxx + 0.22, 13.5, 13.94, 0, 4.5, W_, "-z")
b.abox(10.0, 20.0, 10.0, 14.0, 0.0, 0.05, "ConcreteDk", "-z")
for k in range(6):
    x0s = 11.0 + k * 1.5
    b.pq([(x0s, 10.4, 0.07), (x0s + 0.5, 10.4, 0.07), (x0s + 3.0, 13.2, 0.07), (x0s + 2.5, 13.2, 0.07)], (0, 0, 1), "RailYellow") if x0s + 3.0 <= 19.6 else None

# ------------------------------------------------------------------ helipad on the right wing roof
HPX, HPY = 14.5, -3.5
zt = helipad(b, HPX, HPY, WING_Z, 4.7, "ConcreteDk", W_, "RailYellow", 16, True)

# ------------------------------------------------------------------ roof equipment
b.abox(-5.5, 0.0, -8.0, -3.0, TOWER_Z, TOWER_Z + 3.0, W_, "-z")
b.abox(-5.7, 0.2, -8.2, -2.8, TOWER_Z + 3.0, TOWER_Z + 3.25, T_, "-z")
b.yq(-3.0 + 0.02, -4.0, -2.2, TOWER_Z, TOWER_Z + 2.2, 1, "Metal")
ac_unit(b, 4.5, -4.0, TOWER_Z, 2.2, 1.8, 1.1)
ac_unit(b, 6.0, 1.5, TOWER_Z, 2.2, 1.8, 1.1)
for sx in (-1.0, 1.0):
    for sy in (-1.0, 1.0):
        b.beam((4.5 + sx * 1.0, -7.0 + sy * 1.0, TOWER_Z), (4.5 + sx * 1.0, -7.0 + sy * 1.0, TOWER_Z + 1.6), 0.08, 0.08, 4, "Metal", caps=False)
b.cyl((4.5, -7.0, TOWER_Z + 2.9), 1.4, 2.6, 8, "Metal", caps="t")
b.cyl((4.5, -7.0, TOWER_Z + 4.4), 1.4, 0.5, 8, "MetalDark", r_top=0.2, caps="")
for (ax_, ay_) in ((cxL - 2.0, -6.0), (cxL + 1.5, 2.0), (cxL - 2.5, 5.0)):
    ac_unit(b, ax_, ay_, WING_Z, 2.2, 1.7, 1.1)

# ------------------------------------------------------------------ rooftop cross sign (double sided, emissive)
def cross_poly(cu, cv, e, t):
    return [(cu - t, cv + e), (cu + t, cv + e), (cu + t, cv + t), (cu + e, cv + t), (cu + e, cv - t), (cu + t, cv - t),
            (cu + t, cv - e), (cu - t, cv - e), (cu - t, cv - t), (cu - e, cv - t), (cu - e, cv + t), (cu - t, cv + t)]

SZ0, SZ1 = 20.2, 27.6
for sx in (-2.6, 2.6):
    b.abox(sx - 0.25, sx + 0.25, 6.6, 7.0, TOWER_Z, SZ0, "MetalDark", "-z")
b.abox(-4.2, 4.2, 6.5, 7.1, SZ0, SZ1, TD)
for face, py in (("F", 7.1), ("B", 6.5)):
    S = Side(b, face, 0, 6.8, 4.2, 0.3)
    S.q(-3.8, 3.8, SZ0 + 0.4, SZ1 - 0.4, 0.02, W_)
    S.q(-3.5, 3.5, SZ0 + 0.7, SZ1 - 0.7, 0.04, T_)
    S.poly(cross_poly(0, (SZ0 + SZ1) / 2, 2.85, 1.0), 0.07, "NeonWhite")
    S.poly(cross_poly(0, (SZ0 + SZ1) / 2, 2.6, 0.78), 0.10, "NeonGreen")
b.abox(-4.4, 4.4, 6.4, 7.2, SZ1, SZ1 + 0.3, W_, "-z")

A.mesh(b, "Body")

# ------------------------------------------------------------------ collision
c = HB("hospital_col")
c.abox(-9, 9, -10, 8, 0, TOWER_Z, "Concrete", "-z")
c.abox(-20, -9, -12, 10, 0, WING_Z, "Concrete", "-z")
c.abox(9, 20, -12, 10, 0, WING_Z, "Concrete", "-z")
c.abox(-9, 9, 8, 12.8, 0, POD_Z, "Concrete", "-z")
c.abox(-3, 3, -14, -10, 0, 21.0, "Concrete", "-z")
for sx in (-4.4, 4.4):
    c.abox(sx - 0.22, sx + 0.22, 13.5, 13.94, 0, 4.55, "Concrete", "-z")
for cxx in (10.6, 19.4):
    c.abox(cxx - 0.22, cxx + 0.22, 13.5, 13.94, 0, 4.5, "Concrete", "-z")
A.mesh(c, "Collision", uv=None, winuv=False)

A.mark("Door", (0.0, 13.4, 0.0))
A.mark("AmbulanceBay", (15.0, 12.0, 0.0))
A.mark("RoofHelipad", (HPX, HPY, zt))
rep = A.report()
