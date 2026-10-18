# lane 8 - hangar_a: barrel-vault hangar 40 x 30 m, 12 m tall, big sliding door toward +Y, skylight strips, HangarDoor empty
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("hangar_a", 4)
b = a.b("Body")
HW, HD = 20.0, 15.0          # half width (x), half depth (y)
ZW, RISE = 4.0, 8.0          # wall height, vault rise
XS = [20.0, 17.5, 15.0, 10.0, 5.0, 0.0, -5.0, -10.0, -15.0, -17.5, -20.0]


def zarch(x):
    return ZW + RISE * math.sqrt(max(0.0, 1.0 - (x / HW) ** 2))


ARCH = [(x, zarch(x)) for x in XS]                       # right -> left
PROF = [(-HW, 0.0), (HW, 0.0)] + ARCH + [(-HW, ZW)][0:0]   # (kept for reference)
POLY = [(-HW, 0.0), (HW, 0.0)] + ARCH[0:-1] + [(-HW, ZW)]   # CCW seen from -Y (x right, z up): bottom, right wall, arch right->left, left wall

# ---- plinth
shaft(b, rect_pts(0, 0, 40.5, 30.5), 0, 0.5, "Concrete", "Concrete")

# ---- rear wall (faces -Y) and side walls
y0, y1 = -HD, HD
b.face([b.v((p[0], y0, p[1])) for p in POLY], "WallD")
b.quad((HW, y0, 0.5), (HW, y1, 0.5), (HW, y1, ZW), (HW, y0, ZW), "WallD")
b.quad((-HW, y1, 0.5), (-HW, y0, 0.5), (-HW, y0, ZW), (-HW, y1, ZW), "WallD")

# ---- front wall with a 30 x 8.5 door opening (faces +Y): left/right pillars + header
def front_poly(pts_xz):
    b.face([b.v((p[0], y1, p[1])) for p in reversed(pts_xz)], "WallD")

front_poly([(-HW, 0.5), (-15.0, 0.5), (-15.0, zarch(-15.0)), (-17.5, zarch(-17.5)), (-HW, ZW)])
front_poly([(15.0, 0.5), (HW, 0.5), (HW, ZW), (17.5, zarch(17.5)), (15.0, zarch(15.0))])
front_poly([(-15.0, 8.5), (15.0, 8.5), (15.0, zarch(15.0)), (10.0, zarch(10.0)), (5.0, zarch(5.0)), (0.0, zarch(0.0)),
            (-5.0, zarch(5.0)), (-10.0, zarch(10.0)), (-15.0, zarch(15.0))])
# door reveal (the opening is closed by the door leaves; a dark recess shows at the edges)
b.quad((15.0, y1, 0.5), (15.0, y1 - 0.5, 0.5), (15.0, y1 - 0.5, 8.5), (15.0, y1, 8.5), "Trim")
b.quad((-15.0, y1 - 0.5, 0.5), (-15.0, y1, 0.5), (-15.0, y1, 8.5), (-15.0, y1 - 0.5, 8.5), "Trim")
b.quad((-15.0, y1, 8.5), (15.0, y1, 8.5), (15.0, y1 - 0.5, 8.5), (-15.0, y1 - 0.5, 8.5), "Trim")
b.quad((-15.0, y1 - 0.5, 8.5), (15.0, y1 - 0.5, 8.5), (15.0, y1 - 0.5, 0.5), (-15.0, y1 - 0.5, 0.5), "Trim")
# door frame
b.box((-15.6, y1 + 0.2, 4.5), (1.0, 0.6, 8.6), "Trim")
b.box((15.6, y1 + 0.2, 4.5), (1.0, 0.6, 8.6), "Trim")
b.box((0, y1 + 0.2, 8.9), (32.2, 0.6, 0.8), "Trim")
# two sliding leaves on separate tracks, with ribs and hazard stripe
for (cx, yy, lo) in ((-7.4, y1 + 0.35, 0), (7.4, y1 + 0.8, 1)):
    b.box((cx, yy, 4.4), (15.2, 0.3, 8.0), "MetalDark")
    for k in range(5):
        b.box((cx, yy + 0.18, 1.4 + k * 1.55), (15.0, 0.1, 0.22), "Metal")
    b.box((cx, yy + 0.18, 0.55), (15.2, 0.1, 0.6), "YellowPaint")
    b.box((cx + (-6.8 if lo == 0 else 6.8), yy + 0.2, 4.2), (0.3, 0.14, 7.6), "Metal")      # edge stile
b.box((0, y1 + 1.35, 9.35), (34.0, 0.5, 0.45), "MetalDark")      # track beam
for x in (-12.0, -4.0, 4.0, 12.0):
    b.box((x, y1 + 1.05, 9.0), (0.4, 0.8, 0.5), "Metal")

# ---- vault roof shell (Roof) with two glass skylight strips; strips run y -12..12
SK = {(10.0, 5.0), (-5.0, -10.0)}
for i in range(len(ARCH) - 1):
    (xa, za), (xb, zb) = ARCH[i], ARCH[i + 1]
    glass = (xa, xb) in SK
    if glass:
        for (ya, yb, m) in ((y0, -12.0, "Roof"), (-12.0, 12.0, "Glass"), (12.0, y1, "Roof")):
            b.quad((xa, ya, za), (xa, yb, za), (xb, yb, zb), (xb, ya, zb), m)
    else:
        b.quad((xa, y0, za), (xa, y1, za), (xb, y1, zb), (xb, y0, zb), "Roof")

# ---- roof ribs (mitred ribbon following the arch)
pts = [Vector((x, z)) for (x, z) in ARCH]
nor = []
for i, p in enumerate(pts):
    segs = []
    if i > 0:
        t = (p - pts[i - 1]).normalized()
        segs.append(Vector((-t.y, t.x)) * -1)     # outward normal of a right->left traversal
    if i < len(pts) - 1:
        t = (pts[i + 1] - p).normalized()
        segs.append(Vector((-t.y, t.x)) * -1)
    nn = sum(segs, Vector((0, 0))).normalized()
    nor.append(nn)
for yc in (-14.5, -9.0, -3.0, 3.0, 9.0, 14.5):
    ya, yb = yc - 0.25, yc + 0.25
    for i in range(len(pts) - 1):
        p0, p1 = pts[i], pts[i + 1]
        q0, q1 = p0 + nor[i] * 0.32, p1 + nor[i + 1] * 0.32
        b.quad((q0.x, ya, q0.y), (q0.x, yb, q0.y), (q1.x, yb, q1.y), (q1.x, ya, q1.y), "Metal")       # top
        b.quad((p0.x, ya, p0.y), (q0.x, ya, q0.y), (q1.x, ya, q1.y), (p1.x, ya, p1.y), "Metal")        # -Y side
        b.quad((p1.x, yb, p1.y), (q1.x, yb, q1.y), (q0.x, yb, q0.y), (p0.x, yb, p0.y), "Metal")        # +Y side
# front/back eave fascia
for (yy, s) in ((y1 + 0.05, 1), (y0 - 0.05, -1)):
    pass

# ---- details: man door + lights + louvres on the side walls, coloured base stripe
b.box((-HW - 0.12, 7.0, 1.2), (0.25, 1.3, 2.3), "MetalDark")
b.box((HW + 0.12, -6.0, 1.2), (0.25, 1.3, 2.3), "MetalDark")
for yy in (-10.0, -2.0, 6.0, 12.0):
    b.box((-HW - 0.15, yy, 3.0), (0.3, 0.5, 0.25), "LampGlow")
    b.box((HW + 0.15, yy, 3.0), (0.3, 0.5, 0.25), "LampGlow")
for yy in (-11.0, -4.0, 3.0, 10.0):
    b.box((HW + 0.1, yy, 3.3), (0.2, 1.6, 0.6), "Trim")
    b.box((-HW - 0.1, yy, 3.3), (0.2, 1.6, 0.6), "Trim")
b.box((0, y1 + 0.12, 10.9), (11.0, 0.2, 0.9), "WallB")              # coral sign band above the door
b.box((0, y1 + 0.24, 10.9), (10.0, 0.1, 0.18), "NeonCyan")

a.fin(b, "Body")
a.mark("HangarDoor", (0, y1 + 0.05, 0.0))
report(a)
