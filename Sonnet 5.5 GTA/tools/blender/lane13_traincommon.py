"""
lane13_traincommon.py - shared pieces of the Halcyon light-rail train (train_car + train_locomotive).
Load after gta_lib.py + lane13_lib.py.

Train frame (Blender, metres): +Y = driving direction (nose), origin = ground point under the car centre on the RAIL HEAD (z = 0 is the
rail top / tyre bottom), x = 0 on the track centre line.  Gauge 1.435 m (wheel tread centres at x = +-0.7175), wheel radius 0.45,
floor top at z = 1.0, ceiling 3.0, roof apex 3.46, body half width 1.33 (doors slide outside it up to x = +-1.40 -> 2.8 m overall).
Bogies are separate meshes `Bogie_F` (+5.0 m) / `Bogie_R` (-5.0 m) whose origin is the bogie centre ON the rail head (rotate them about
their local Z (up) for curves).
"""
import math

XO, WT = 1.33, 0.10                  # outer half width, wall thickness
ZF0, ZF, ZW = 0.88, 1.00, 3.00       # underframe bottom, floor top, wall top (roof springing line)
ROOF_PTS = [(1.33, 3.0), (1.22, 3.22), (0.75, 3.40), (0.0, 3.46)]       # right half of the roof arch (x, z)
ROOF_MATS = ["Paint", "Paint2", "Paint"]
GAUGE = 1.435
WR = 0.45
BAND = 1.50                          # top of the Paint2 lower body band
WIN_Z = (1.70, 2.75)
DOOR_Z = (1.00, 2.95)


def win(ya, yb):
    return (ya, yb, WIN_Z[0], WIN_Z[1])


def door(ya, yb):
    return (ya, yb, DOOR_Z[0], DOOR_Z[1])


# ------------------------------------------------------------------------------------------------ bogie
def bogie_geometry(name="bogie"):
    """one bogie in local coordinates (origin = bogie centre on the rail head). Returns the HB."""
    b = HB(name)
    sg = 10
    wy = (-1.1, 1.1)
    gx = GAUGE / 2
    prof = [(0.07, 0.0), (0.07, 0.45), (-0.03, 0.45), (-0.045, 0.495), (-0.07, 0.50), (-0.07, 0.0)]
    for s in (-1, 1):
        for y in wy:
            # right wheel (s=+1): a>0 is OUTWARD (+x). left wheel: flip the axial coordinate.
            b.lathe(prof, (s * gx, y, WR), sg, "MetalDark", axis="X", flip=s, rot=0.2, mats=["Metal", "MetalDark", "MetalDark", "MetalDark", "MetalDark"])
            b.cyl((s * (gx + 0.085), y, WR), 0.15, 0.04, 8, "Chrome", axis="X", caps="t" if s > 0 else "b")
            b.abox(s * 0.80, s * 0.96, y - 0.15, y + 0.15, 0.30, 0.58, "MetalDark", "-z")      # axle box
    for y in wy:
        b.beam((-gx, y, WR), (gx, y, WR), 0.055, 0.055, 6, "Metal", caps=False)                     # axle
        b.cyl((0, y * 0.58, 0.48), 0.17, 0.78, 8, "MetalDark", axis="X")                            # traction motor
    for s in (-1, 1):
        b.abox(s * 1.02 - 0.07, s * 1.02 + 0.07, -1.55, 1.55, 0.62, 0.74, "MetalDark")           # side frame beam
        b.abox(s * 1.02 - 0.07, s * 1.02 + 0.07, -1.55, -1.20, 0.62, 0.80, "MetalDark", "-z")      # upturned ends
        b.abox(s * 1.02 - 0.07, s * 1.02 + 0.07, 1.20, 1.55, 0.62, 0.80, "MetalDark", "-z")
        for y in wy:
            b.cyl((s * 1.02, y, 0.80), 0.085, 0.12, 6, "Chrome", caps="t")                          # primary spring pot
    b.abox(-0.96, 0.96, -0.22, 0.22, 0.64, 0.80, "Metal", "-z")                                     # cross transom
    b.cyl((0, 0, 0.82), 0.34, 0.06, 10, "MetalDark", caps="t")                                      # bolster plate
    return b


def add_bogies(A, y_f=5.0, y_r=-5.0):
    """Bogie_F / Bogie_R meshes (origin = bogie centre on the rail head)."""
    for nm, y in (("Bogie_F", y_f), ("Bogie_R", y_r)):
        A.mesh(bogie_geometry(A.id + "_" + nm), nm, loc=(0, y, 0), uv=None)


# ------------------------------------------------------------------------------------------------ body shell pieces
def side_walls(b, y0, y1, win_holes, door_holes, pockets=None):
    """thick side walls both sides: Paint2 lower band + Paint upper, windows with Glass and black frames, door openings.
    pockets[i] = -1 / +1: direction in which door i slides open (the door rail is drawn over the opening + 1.65 m pocket)."""
    holes = list(win_holes) + list(door_holes)
    for s in (-1, 1):
        wall_x(b, s, XO, WT, y0, y1, ZF0, BAND, door_holes, "Paint2", "TrainInner")
        wall_x(b, s, XO, WT, y0, y1, BAND, ZW, holes, "Paint", "TrainInner")
        reveals_x(b, s, XO, WT, holes)
        for (ya, yb, za, zb) in win_holes:
            pane_x(b, s, XO - WT / 2, ya, yb, za, zb, "Glass")
            fw, xf_ = 0.055, s * (XO + 0.010)
            b.xq(xf_, ya - fw, ya, za - fw, zb + fw, s, "Trim")
            b.xq(xf_, yb, yb + fw, za - fw, zb + fw, s, "Trim")
            b.xq(xf_, ya, yb, za - fw, za, s, "Trim")
            b.xq(xf_, ya, yb, zb, zb + fw, s, "Trim")
        # neon accent line on the body band edge (skips the door openings)
        cuts = sorted([(h[0], h[1]) for h in door_holes])
        segs = []
        cur = y0 + 0.02
        for (da, db) in cuts:
            segs.append((cur, da - 0.02))
            cur = db + 0.02
        segs.append((cur, y1 - 0.02))
        for (sa, sb) in segs:
            if sb - sa > 0.05:
                b.xq(s * (XO + 0.010), sa, sb, BAND - 0.035, BAND + 0.035, s, "Neon")
        # door rails (outside, above each door, running to the pocket)
        for i, (da, db, _za, _zb) in enumerate(door_holes):
            pd = pockets[i] if pockets else (-1 if (da + db) < 0 else 1)
            ra, rb = (da - 1.65, db + 0.05) if pd < 0 else (da - 0.05, db + 1.65)
            b.abox(s * XO, s * (XO + 0.07), ra, rb, 2.96, 3.04, "MetalDark", "-x" if s > 0 else "+x")


def roof_arch(b, y0, y1, c_z=2.2):
    """lofted roof arch (both halves), Paint with Paint2 shoulder stripes"""
    for s in (-1, 1):
        for k in range(len(ROOF_PTS) - 1):
            (xa, za), (xb, zb) = ROOF_PTS[k], ROOF_PTS[k + 1]
            b.po([(s * xa, y0, za), (s * xb, y0, zb), (s * xb, y1, zb), (s * xa, y1, za)], (0, (y0 + y1) / 2, c_z), ROOF_MATS[k])


def arch_polygon(s_y):
    """outline (x,z) of the roof cap above the wall line (for the end walls)"""
    pts = [(ROOF_PTS[0][0], ZW)]
    pts += [(x, z) for (x, z) in ROOF_PTS[1:]]
    pts += [(-x, z) for (x, z) in reversed(ROOF_PTS[1:-1])]
    pts += [(-ROOF_PTS[0][0], ZW)]
    return pts


def end_wall(b, sy, y_out, thick=0.14, doorway=True, outer_mat="Paint"):
    """closed end wall at +y (sy=+1) or -y (sy=-1): outer face at |y|=y_out. Doorway (gangway) hole 1.1 x 1.6."""
    yo, yi = sy * y_out, sy * (y_out - thick)
    hole = [(-0.55, 0.55, 1.0, 2.6)] if doorway else []
    for r in rects_with_holes(-XO + WT, XO - WT, ZF, ZW, hole):
        b.yq(yi, r[0], r[1], r[2], r[3], -sy, "TrainInner")
    for r in rects_with_holes(-XO, XO, ZF0, BAND, hole):
        b.yq(yo, r[0], r[1], r[2], r[3], sy, "Paint2")
    for r in rects_with_holes(-XO, XO, BAND, ZW, hole):
        b.yq(yo, r[0], r[1], r[2], r[3], sy, outer_mat)
    ya, yb = min(yo, yi), max(yo, yi)
    if doorway:
        b.xq(-0.55, ya, yb, 1.0, 2.6, 1, "TrainInner")
        b.xq(0.55, ya, yb, 1.0, 2.6, -1, "TrainInner")
        b.zq(1.0, -0.55, 0.55, ya, yb, 1, "TrainFloor")
        b.zq(2.6, -0.55, 0.55, ya, yb, -1, "TrainInner")
        # rubber gangway frame (bellows collar) sticking out 0.2 m
        yc0, yc1 = (yo, yo + sy * 0.2) if sy > 0 else (yo - 0.2, yo)
        for (x0, x1, z0, z1) in ((-0.80, -0.55, 0.95, 2.75), (0.55, 0.80, 0.95, 2.75), (-0.55, 0.55, 2.6, 2.75), (-0.55, 0.55, 0.95, 1.0)):
            b.abox(x0, x1, yc0, yc1, z0, z1, "Trim", "-y" if sy > 0 else "+y")
    # arch cap above the wall line (outer face only)
    pts = [(x, y_out * sy, z) for (x, z) in arch_polygon(sy)]
    b.pq(pts, (0, sy, 0), outer_mat)


def floor_and_ceiling(b, y0, y1):
    b.zq(ZF, -XO + WT, XO - WT, y0, y1, 1, "TrainFloor")
    b.zq(ZF0, -XO + WT, XO - WT, y0, y1, -1, "Trim")
    b.zq(ZW - 0.005, -XO + WT, XO - WT, y0, y1, -1, "TrainCeil")
    for sx in (-0.55, 0.55):
        b.zq(ZW - 0.012, sx - 0.09, sx + 0.09, y0 + 0.5, y1 - 0.5, -1, "TrainGlow")
        b.abox(sx - 0.13, sx + 0.13, y0 + 0.45, y1 - 0.45, ZW - 0.03, ZW - 0.012, "TrainInner", "+z -z")


def bench(b, s, yc, length, cushion="TrainSeat", back="TrainSeatDk", hi=0.50):
    """longitudinal bench against the inner wall on side s."""
    xw = XO - WT
    lo_x, hi_x = (xw - hi, xw) if s > 0 else (-xw, -xw + hi)
    y0, y1 = yc - length / 2, yc + length / 2
    wall_face = "+x" if s > 0 else "-x"
    px0, px1 = (lo_x + 0.10, hi_x) if s > 0 else (lo_x, hi_x - 0.10)
    b.abox(px0, px1, y0 + 0.06, y1 - 0.06, ZF, 1.38, "Trim", "-z " + wall_face)
    b.abox(lo_x, hi_x, y0, y1, 1.38, 1.48, cushion, "-z " + wall_face)
    bx0, bx1 = (hi_x - 0.09, hi_x) if s > 0 else (lo_x, lo_x + 0.09)
    b.abox(bx0, bx1, y0, y1, 1.48, 1.90, back, "-z " + wall_face)


def pole(b, x, y, z0=ZF, z1=ZW - 0.01, r=0.022):
    b.beam((x, y, z0), (x, y, z1), r, r, 5, "Chrome", caps=False)


def door_leaf(A, name, s, yc, slide_dir):
    """door leaf mesh, origin = bottom centre of the closed leaf on the wall plane. The leaf hangs OUTSIDE the wall (x from |x|=1.335 to 1.40)
    and slides along Y (slide_dir = -1 towards the rear, +1 towards the nose) by about 1.45 m into the blank pocket."""
    b = HB(A.id + "_" + name)
    w, h = 1.50, 1.98
    xi, xo_ = s * 0.005, s * 0.067
    hole = (-0.38, 0.38, 0.85, 1.80)
    for r in rects_with_holes(-w / 2, w / 2, 0.0, h, [hole]):
        b.xq(xo_, r[0], r[1], r[2], r[3], s, "Paint2")
        b.xq(xi, r[0], r[1], r[2], r[3], -s, "TrainInner")
    xa, xb = min(xi, xo_), max(xi, xo_)
    ya, yb, za, zb = hole
    b.yq(ya, xa, xb, za, zb, 1, "Trim")
    b.yq(yb, xa, xb, za, zb, -1, "Trim")
    b.zq(za, xa, xb, ya, yb, 1, "Trim")
    b.zq(zb, xa, xb, ya, yb, -1, "Trim")
    b.xq((xi + xo_) / 2, ya, yb, za, zb, s, "Glass")
    # perimeter
    b.yq(-w / 2, xa, xb, 0, h, -1, "Trim")
    b.yq(w / 2, xa, xb, 0, h, 1, "Trim")
    b.zq(h, xa, xb, -w / 2, w / 2, 1, "Trim")
    b.zq(0, xa, xb, -w / 2, w / 2, -1, "Trim")
    # soft black edge strip on the leading edge
    ye = slide_dir * -1 * (w / 2)           # the edge facing the opposite door half
    b.xq(xo_ + s * 0.004, ye - 0.04, ye + 0.04, 0.05, h - 0.05, s, "Trim")
    return A.mesh(b, name, loc=(s * XO, yc, ZF), uv=None)


def lights_ends(b, y_front, y_rear, z=1.3):
    for sx in (-1, 1):
        b.abox(sx * 1.0 - 0.11, sx * 1.0 + 0.11, y_front, y_front + 0.03, z - 0.06, z + 0.06, "LightHead", "-y")
        b.abox(sx * 1.0 - 0.11, sx * 1.0 + 0.11, y_rear - 0.03, y_rear, z - 0.06, z + 0.06, "LightTail", "+y")
