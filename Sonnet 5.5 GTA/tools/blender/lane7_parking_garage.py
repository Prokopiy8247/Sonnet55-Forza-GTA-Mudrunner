"""lane7 parking_garage: open-deck split-level garage 36 x 24 m, 4 storeys (ground + 3 decks), three ramps (R01 east on the ground,
R12 west on deck 1, R23 east on deck 2), pillars, edge barriers, stair tower with a neon P sign in a notch of the front facade."""
A = Asset("parking_garage", 10)
b = HB("parking_garage_body")
T = 0.35
Z1, Z2, Z3 = 3.2, 6.4, 9.6
CONC, CDK, SLATE = "Concrete", "ConcreteDk", "Slate"

S1 = [(-18, -12), (18, -12), (18, -8), (10, -8), (10, 12), (4, 12), (4, 9), (-4, 9), (-4, 12), (-18, 12)]
S2 = [(-10, -12), (18, -12), (18, 12), (4, 12), (4, 9), (-4, 9), (-4, 12), (-18, 12), (-18, 8), (-10, 8)]
S3 = S1
SKIP1 = {2, 5, 6, 7}
SKIP2 = {3, 4, 5, 8}


def inside(poly, x, y):
    n = len(poly)
    c = False
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            c = not c
        j = i
    return c


def slab(builder, poly, ztop):
    builder.ez(poly, ztop - T, ztop, CONC, caps=(True, False))
    builder.pq([(p[0], p[1], ztop) for p in poly], (0, 0, 1), CDK)


def barrier(builder, poly, skip, ztop, h=0.95, t=0.25, detail=True):
    n = len(poly)
    for i in range(n):
        if i in skip:
            continue
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % n]
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy)
        nx, ny = -dy / L, dx / L
        xs = [x0, x1, x0 + nx * t, x1 + nx * t]
        ys = [y0, y1, y0 + ny * t, y1 + ny * t]
        bx0, bx1, by0, by1 = min(xs), max(xs), min(ys), max(ys)
        builder.abox(bx0, bx1, by0, by1, ztop, ztop + h, CONC, "-z")
        if detail:
            # dark slot band on the outer face = open deck look
            if abs(dy) < 1e-6:
                oy = y0 - ny * 0.005
                builder.yq(oy, bx0 + 0.3, bx1 - 0.3, ztop + 0.4, ztop + 0.72, -1 if ny > 0 else 1, "Trim")
            else:
                ox = x0 - nx * 0.005
                builder.xq(ox, by0 + 0.3, by1 - 0.3, ztop + 0.4, ztop + 0.72, -1 if nx > 0 else 1, "Trim")


# ---------------------------------------------------------------- decks + barriers
slab(b, S1, Z1)
slab(b, S2, Z2)
slab(b, S3, Z3)
barrier(b, S1, SKIP1, Z1)
barrier(b, S2, SKIP2, Z2)
barrier(b, S3, SKIP1, Z3)

# ---------------------------------------------------------------- ramps (solid wedges with asphalt tops)
def wedge(builder, x0, x1, ya, za, yb, zb, base):
    """wedge between planes x0..x1, top surface from (ya,za) to (yb,zb), resting on z=base"""
    builder.ex([(ya, base), (yb, base), (yb, zb), (ya, za)] if za != base else [(ya, base), (yb, base), (yb, zb)], x0, x1, CONC, caps=(True, True))
    builder.pq([(x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)], (0, 0.05, 1) if zb > za else (0, -0.05, 1), CDK)
    # lane arrows (chevron strokes) down the middle
    for k in range(4):
        t_ = (k + 0.5) / 4
        yy = ya + (yb - ya) * t_
        zz = za + (zb - za) * t_ + 0.02
        d = 1 if yb > ya else -1
        xm = (x0 + x1) / 2
        builder.pq([(xm - 0.9, yy - 0.5 * d, zz), (xm, yy + 0.4 * d, zz), (xm + 0.9, yy - 0.5 * d, zz), (xm + 0.9, yy - 0.8 * d, zz), (xm, yy + 0.1 * d, zz), (xm - 0.9, yy - 0.8 * d, zz)], (0, 0, 1), "LineWhite")


wedge(b, 10.0, 18.0, 8.0, 0.0, -8.0, Z1, 0.0)              # R01 ground -> deck 1 (climbs to the back)
wedge(b, -18.0, -10.0, -8.0, Z1, 8.0, Z2, Z1)              # R12 deck 1 -> deck 2 (climbs to the front)
wedge(b, 10.0, 18.0, 8.0, Z2, -8.0, Z3, Z2)                # R23 deck 2 -> deck 3
# sloped side rails on the outer edges of the ramps
def rail(builder, x0, x1, ya, za, yb, zb, h=0.95):
    builder.ex([(ya, za), (yb, zb), (yb, zb + h), (ya, za + h)], x0, x1, CONC, caps=(True, True))

rail(b, 17.75, 18.0, 8.0, 0.0, -8.0, Z1)
rail(b, -18.0, -17.75, -8.0, Z1, 8.0, Z2)
rail(b, 17.75, 18.0, 8.0, Z2, -8.0, Z3)

# ---------------------------------------------------------------- pillars
cols = []
for x in (-15.5, -9.0, -3.0, 3.0, 9.0, 15.5):
    for y in (-9.0, -3.0, 3.0, 8.5):
        if inside(S1, x, y):
            u = Z1 - T
            if inside(S2, x, y):
                u = Z2 - T
                if inside(S3, x, y):
                    u = Z3 - T
        else:
            continue
        if abs(x) < 4.5 and y > 8.8:
            continue
        cols.append((x, y, u))
for (x, y, u) in cols:
    b.abox(x - 0.28, x + 0.28, y - 0.28, y + 0.28, 0.0, u, CONC, "-z")
    b.abox(x - 0.34, x + 0.34, y - 0.34, y + 0.34, 0.0, 0.3, CDK, "-z")

# ---------------------------------------------------------------- parking stall lines on the decks
def stalls(poly, z, xr, y0, y1, skip_fn=None):
    x = xr[0]
    while x <= xr[1] + 1e-6:
        ym = (y0 + y1) / 2
        if inside(poly, x, ym) and (skip_fn is None or not skip_fn(x, ym)):
            b.zq(z + 0.012, x - 0.05, x + 0.05, y0, y1, 1, "LineWhite")
        x += 3.0

stalls(S1, Z1, (-8.0, 8.0), -11.8, -8.0)
stalls(S1, Z1, (-8.0, 8.0), 8.0, 11.8, lambda x, y: abs(x) < 5.0)
stalls(S2, Z2, (-8.0, 17.0), -11.8, -8.0)
stalls(S2, Z2, (-8.0, 3.0), 8.0, 11.8, lambda x, y: abs(x) < 5.0)
stalls(S3, Z3, (-17.0, 9.0), -11.8, -8.0, lambda x, y: x > 9.5)
stalls(S3, Z3, (-17.0, 3.0), 8.0, 11.8, lambda x, y: abs(x) < 5.0)

# lamps under the slabs
for (z, xs) in ((Z1, (-12.0, -3.0, 5.0)), (Z2, (-6.0, 3.0, 12.0)), (Z3, (-12.0, -3.0, 5.0))):
    for x in xs:
        b.zq(z - T - 0.02, x - 0.7, x + 0.7, -1.0, 1.0, -1, "LampGlow")

# ---------------------------------------------------------------- stair tower (front notch x -4..4, y 9..12)
TW0, TW1, TY0, TY1, TZ = -4.0, 4.0, 9.0, 12.0, 13.4
TF = Side(b, "F", 0, 10.5, 4.0, 1.5)
TL = Side(b, "L", 0, 10.5, 4.0, 1.5)
TR = Side(b, "R", 0, 10.5, 4.0, 1.5)
TBk = Side(b, "B", 0, 10.5, 4.0, 1.5)
door = (-1.1, 1.1, 0.0, 2.7)
rows = [(0.9, 2.7), (4.1, 6.1), (7.3, 9.3), (10.5, 12.5)]
tw = [(u - 0.55, u + 0.55, v0, v1) for u in (-3.0, 3.0) for (v0, v1) in rows]
TF.wall(-4, 4, 0, TZ, [door] + tw, SLATE)
TF.wins(tw, depth=0.2, frame="TrimWhite")
TF.reveal(door, 0.5, "Hazard", "lrt")
TF.q(door[0], door[1], 0, 2.7, -0.5, "Window")
TF.q(-0.04, 0.04, 0, 2.7, -0.47, "MetalDark")
TF.box(-1.5, 1.5, 2.75, 3.1, 0.0, 0.6, "Hazard", skip="ib")
# neon P sign on a dark panel
TF.q(-1.8, 1.8, 4.6, 11.8, 0.04, "Trim")
TF.q(-1.8, 1.8, 4.6, 4.75, 0.05, "NeonCyan")
TF.q(-1.8, 1.8, 11.65, 11.8, 0.05, "NeonCyan")
Pp = [((-0.75, 6.0), (-0.75, 10.4)), ((-0.75, 10.4), (0.35, 10.4)), ((0.35, 10.4), (0.9, 9.9)), ((0.9, 9.9), (0.9, 9.0)), ((0.9, 9.0), (0.35, 8.5)), ((0.35, 8.5), (-0.75, 8.5))]
for (p0, p1) in Pp:
    TF.stroke(p0, p1, 0.34, 0.09, "NeonCyan")
for S in (TL, TR):
    hs = [(-0.5, 0.5, v0, v1) for (v0, v1) in rows]
    S.openings(-1.5, 1.5, 0, TZ, hs, SLATE, depth=0.2, frame="TrimWhite")
TBk.wall(-4, 4, 0, TZ, [], SLATE)
for z in (Z1, Z2, Z3):
    TBk.q(-0.7, 0.7, z, z + 2.4, 0.03, "MetalDark")
    TBk.q(-0.7, 0.7, z + 2.4, z + 2.6, 0.03, "Hazard")
b.zq(TZ, TW0, TW1, TY0, TY1, 1, "Roof")
b.abox(TW0 - 0.2, TW1 + 0.2, TY0 - 0.2, TY1 + 0.0, TZ - 0.25, TZ + 0.12, CONC, "-z")
parapet(b, TW0 - 0.2, TW1 + 0.2, TY0 - 0.2, TY1, TZ + 0.12, TZ + 0.8, 0.25, CONC, "FLRB")

# ---------------------------------------------------------------- entrance gantry + booth (ground, east side)
for x in (10.6, 17.4):
    b.abox(x - 0.18, x + 0.18, 10.0, 10.36, 0.0, 3.2, "MetalDark", "-z")
b.abox(10.6, 17.4, 10.05, 10.31, 2.7, 3.2, "Hazard")
for k in range(9):
    xa = 10.8 + k * 0.7
    b.pq([(xa, 10.32, 2.7), (xa + 0.3, 10.32, 2.7), (xa + 0.5, 10.32, 3.2), (xa + 0.2, 10.32, 3.2)], (0, 1, 0), "Trim")
b.abox(11.2, 12.7, 10.9, 11.8, 0.0, 2.4, CONC, "-z")
b.yq(11.81, 11.45, 12.45, 1.1, 2.0, 1, "Window")
b.abox(11.0, 12.9, 10.7, 12.0, 2.4, 2.55, "ShopOrange")
b.beam((12.7, 10.9 - 0.0, 1.2), (15.6, 10.9, 1.2), 0.05, 0.05, 4, "Hazard", caps=True)

# ---------------------------------------------------------------- rooftop of deck 3: light poles + small shelter
for x in (-13.0, -4.0, 5.0):
    b.beam((x, -10.0, Z3), (x, -10.0, Z3 + 4.5), 0.07, 0.05, 5, "MetalDark")
    b.abox(x - 0.45, x + 0.45, -10.2, -9.8, Z3 + 4.5, Z3 + 4.62, "LampGlow")
b.abox(-14.0, -9.0, 1.0, 4.5, Z3, Z3 + 2.6, CDK, "-z")             # stair/lift head house
b.yq(4.51, -12.8, -10.2, Z3, Z3 + 2.0, 1, "MetalDark")

A.mesh(b, "Body")

# ---------------------------------------------------------------- collision: slabs, ramps, columns, barriers, tower
c = HB("parking_garage_col")
for poly, z in ((S1, Z1), (S2, Z2), (S3, Z3)):
    c.ez(poly, z - T, z, CONC, caps=(True, True))
barrier(c, S1, SKIP1, Z1, detail=False)
barrier(c, S2, SKIP2, Z2, detail=False)
barrier(c, S3, SKIP1, Z3, detail=False)
wedge_c = lambda x0, x1, ya, za, yb, zb, base: c.ex([(ya, base), (yb, base), (yb, zb), (ya, za)] if za != base else [(ya, base), (yb, base), (yb, zb)], x0, x1, CONC, caps=(True, True))
wedge_c(10.0, 18.0, 8.0, 0.0, -8.0, Z1, 0.0)
wedge_c(-18.0, -10.0, -8.0, Z1, 8.0, Z2, Z1)
wedge_c(10.0, 18.0, 8.0, Z2, -8.0, Z3, Z2)
for (x, y, u) in cols:
    c.abox(x - 0.28, x + 0.28, y - 0.28, y + 0.28, 0.0, u, CONC, "-z")
c.abox(TW0, TW1, TY0, TY1, 0.0, TZ, CONC, "-z")
A.mesh(c, "Collision", uv=None, winuv=False)
A.mark("Door", (0.0, 12.7, 0.0))
rep = A.report()
