"""lane6_kit_apartment.py - kit_apartment (brick / stucco mid-rise modules). Idempotent."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane6_kitlib.py", encoding="utf8").read(), globals())


def a_band(b, x0=-2.0, x1=2.0, z0=3.4, z1=3.6, p=0.08, mat="WallD"):
    b.abox(x0, x1, 0, p, z0, z1, mat, "-y -x +x -z")


def a_window(b, hole, depth=0.22, cross=True, shutters=True, lintel=True, sill=True):
    x0, x1, z0, z1 = hole
    b.window_y(hole, depth, "WallA")
    xm = (x0 + x1) / 2
    f = 0.045
    yb = -depth
    b.abox(x0, x1, yb, yb + f, z0, z0 + 0.05, "Trim", "-y -x +x -z")
    b.abox(x0, x1, yb, yb + f, z1 - 0.05, z1, "Trim", "-y -x +x +z")
    b.abox(x0, x0 + 0.05, yb, yb + f, z0 + 0.05, z1 - 0.05, "Trim", "-y -x -z +z")
    b.abox(x1 - 0.05, x1, yb, yb + f, z0 + 0.05, z1 - 0.05, "Trim", "-y +x -z +z")
    if cross:
        b.abox(xm - 0.025, xm + 0.025, yb, yb + f, z0, z1, "Trim", "-y -z +z")
        zm = z0 + (z1 - z0) * 0.62
        b.abox(x0, x1, yb, yb + f, zm - 0.025, zm + 0.025, "Trim", "-y -x +x")
    if sill:
        b.abox(x0 - 0.12, x1 + 0.12, 0, 0.17, z0 - 0.09, z0, "Concrete", "-y -z")
    if lintel:
        b.abox(x0 - 0.12, x1 + 0.12, 0, 0.10, z1, z1 + 0.15, "WallD", "-y -z")
    if shutters:
        for (xa, xb) in ((x0 - 0.40, x0 - 0.10), (x1 + 0.10, x1 + 0.40)):
            b.abox(xa, xb, 0, 0.045, z0 - 0.05, z1 + 0.1, "WallC", "-y -z +z")
            for k in range(1, 5):
                zz = z0 + (z1 - z0 + 0.15) * k / 5.0
                b.yq(0.052, xa + 0.03, xb - 0.03, zz, zz + 0.025, 1, "Trim")


def apt_bay_window(b):
    h1 = (-1.45, -0.50, 0.95, 2.65)
    h2 = (0.50, 1.45, 0.95, 2.65)
    b.wall_y(0, -2, 2, 0, FH, [h1, h2], "WallA")
    a_window(b, h1, shutters=False)
    a_window(b, h2, shutters=False)
    b.abox(-1.75, 1.75, 0, 0.05, 0.12, 0.80, "WallB", "-y -x +x -z +z")      # brick spandrel
    b.abox(-0.28, 0.28, 0, 0.05, 1.25, 2.4, "WallB", "-y -z +z")              # brick pier between windows
    for z in (0.35, 0.55):
        b.yq(0.056, -1.75, 1.75, z, z + 0.02, 1, "Trim")
    a_band(b)
    b.abox(-2.0, -1.88, 0, 0.07, 0, 3.4, "WallD", "-y -x -z +z")
    b.abox(1.88, 2.0, 0, 0.07, 0, 3.4, "WallD", "-y +x -z +z")


def apt_bay_balcony(b):
    d = (-1.05, 1.05, 0.18, 2.55)
    b.wall_y(0, -2, 2, 0, FH, [d], "WallA")
    b.window_y(d, 0.2, "WallA")
    # French doors
    for x in (-0.35, 0.35):
        b.abox(x - 0.03, x + 0.03, -0.2, -0.155, d[2], d[3], "Trim", "-y -z +z")
    b.abox(d[0], d[1], -0.2, -0.155, 2.1, 2.16, "Trim", "-y -x +x")
    b.abox(d[0], d[1], -0.2, -0.155, d[2], d[2] + 0.05, "Trim", "-y -x +x")
    b.abox(d[0] - 0.1, d[1] + 0.1, 0, 0.1, d[3], d[3] + 0.14, "WallD", "-y -z")
    # balcony slab with front fascia
    b.abox(-1.8, 1.8, 0, 1.4, 0.0, 0.18, "Concrete", "-y")
    b.abox(-1.8, 1.8, 1.4, 1.43, 0.0, 0.18, "WallD", "-y -x +x")
    # glass rail + posts + top rail
    for sx in (-1, 1):
        b.beamk((sx * 1.75, 1.36, 0.18), (sx * 1.75, 1.36, 1.08), 0.03, 0.03, 4, "Metal", True)
        b.beamk((sx * 1.75, 0.08, 0.18), (sx * 1.75, 0.08, 1.08), 0.03, 0.03, 4, "Metal", True)
    b.abox(-1.78, 1.78, 1.33, 1.39, 1.05, 1.1, "Metal", "-y")
    for sx in (-1, 1):
        b.abox(sx * 1.78 - 0.03, sx * 1.78 + 0.03, 0.05, 1.39, 1.05, 1.1, "Metal", "-z")
    b.yq(1.38, -1.72, 1.72, 0.22, 1.04, 1, "Glass")
    b.xq(-1.74, 0.1, 1.36, 0.22, 1.04, -1, "Glass")
    b.xq(1.74, 0.1, 1.36, 0.22, 1.04, 1, "Glass")
    b.abox(-1.72, 1.72, 1.32, 1.4, 0.18, 0.25, "Metal", "-y -x +x -z")
    # wall details
    b.abox(-2.0, -1.88, 0, 0.07, 0, 3.4, "WallD", "-y -x -z +z")
    b.abox(1.88, 2.0, 0, 0.07, 0, 3.4, "WallD", "-y +x -z +z")
    b.abox(-1.75, -1.2, 0, 0.05, 0.9, 2.5, "WallB", "-y -z +z")
    b.abox(1.2, 1.75, 0, 0.05, 0.9, 2.5, "WallB", "-y -z +z")
    a_band(b)


def apt_bay_solid(b):
    b.wall_y(0, -2, 2, 0, FH, [], "WallA")
    for (xa, xb) in ((-1.7, -0.25), (0.25, 1.4)):
        b.abox(xa, xb, 0, 0.05, 0.3, 3.1, "WallB", "-y")
        for k in range(1, 9):
            b.yq(0.056, xa, xb, 0.3 + k * 0.31, 0.3 + k * 0.31 + 0.02, 1, "Trim")
    b.cylk((1.75, 0.12, 1.8), 0.045, 3.6, 6, "Metal", axis="Z")
    for z in (0.3, 1.8, 3.2):
        b.abox(1.7, 1.8, 0.0, 0.1, z - 0.03, z + 0.03, "Trim", "-y")
    b.abox(-0.1, 0.1, 0, 0.04, 0.35, 0.55, "Trim", "-y")                      # small vent
    a_band(b)
    b.abox(-2.0, -1.88, 0, 0.07, 0, 3.4, "WallD", "-y -x -z +z")
    b.abox(1.88, 2.0, 0, 0.07, 0, 3.4, "WallD", "-y +x -z +z")


def apt_bay_door_stoop(b):
    door = (-0.6, 0.6, 0.54, 3.45)
    w1 = (-1.75, -0.95, 1.15, 3.0)
    w2 = (0.95, 1.75, 1.15, 3.0)
    b.wall_y(0, -2, 2, 0, GH, [door, w1, w2], "WallA")
    b.window_y(door, 0.28, "WallA", glass="Window")
    # door leaf (WallC) recessed, glazed upper part
    b.yq(-0.2, -0.55, 0.55, 0.54, 2.62, 1, "WallC")
    b.yq(-0.19, -0.38, 0.38, 1.45, 2.5, 1, "Window")
    for (xa, xb, za, zb) in ((-0.42, 0.42, 1.41, 1.45), (-0.42, 0.42, 2.5, 2.54), (-0.42, -0.38, 1.45, 2.5), (0.38, 0.42, 1.45, 2.5)):
        b.yq(-0.185, xa, xb, za, zb, 1, "Trim")
    b.abox(0.3, 0.34, -0.2, -0.1, 1.2, 1.5, "Metal", "-y -z +z")
    b.abox(-0.6, 0.6, -0.24, -0.1, 2.62, 2.72, "Trim", "-y -x +x")               # door head
    for w in (w1, w2):
        a_window(b, w, 0.22, cross=True, shutters=False)
    # brick base + plinth
    b.abox(-2, 2, 0, 0.06, 0, 0.54, "WallB", "-y -x +x -z")
    b.abox(-2, 2, 0, 0.12, 0, 0.18, "Concrete", "-y -x +x -z")
    # stoop steps
    b.abox(-1.0, 1.0, 0, 1.5, 0.0, 0.18, "Concrete", "-y")
    b.abox(-0.9, 0.9, 0, 1.1, 0.18, 0.36, "Concrete", "-y")
    b.abox(-0.8, 0.8, 0, 0.7, 0.36, 0.54, "Concrete", "-y")
    # stair rails
    for sx in (-1, 1):
        xx = sx * 0.88
        b.beamk((xx, 1.4, 0.24), (xx, 1.4, 0.9), 0.025, 0.025, 4, "Metal", False)
        b.beamk((xx, 0.7, 0.58), (xx, 0.7, 1.15), 0.025, 0.025, 4, "Metal", False)
        b.beamk((xx, 1.4, 0.9), (xx, 0.7, 1.15), 0.025, 0.025, 4, "Metal", True)
        b.beamk((xx, 0.7, 1.15), (xx, 0.05, 1.15), 0.025, 0.025, 4, "Metal", True)
    # canopy
    b.abox(-1.25, 1.25, 0, 1.2, 3.62, 3.76, "Concrete", "-y")
    b.abox(-1.25, 1.25, 1.2, 1.24, 3.5, 3.62, "WallD", "-y")
    for sx in (-1, 1):
        b.beamk((sx * 1.15, 0.0, 4.35), (sx * 1.15, 1.1, 3.62), 0.022, 0.022, 4, "Metal", False)
    b.abox(1.05, 1.25, 0, 0.12, 2.3, 2.6, "LampGlow", "-y")                   # wall lamp
    b.abox(-1.0, 1.0, 0, 0.05, 4.05, 4.4, "WallD", "-y -z")                   # house-number plate
    a_band(b, z0=4.55, z1=4.8)
    b.abox(-2.0, -1.88, 0, 0.07, 0.54, 4.55, "WallD", "-y -x -z +z")
    b.abox(1.88, 2.0, 0, 0.07, 0.54, 4.55, "WallD", "-y +x -z +z")


def apt_bay_shop_ground(b):
    win = (-1.8, 0.55, 0.6, 3.25)
    door = (0.8, 1.75, 0.0, 3.25)
    b.wall_y(0, -2, 2, 0, GH, [win, door], "WallA")
    b.window_y(win, 0.22, "WallD")
    b.reveal_y(door, 0, -0.22, "WallD", "lrt")
    b.yq(-0.22, door[0], door[1], door[2], door[3], 1, "Window")
    # frames
    for h in (win, door):
        x0, x1, z0, z1 = h
        b.abox(x0, x1, -0.22, -0.16, z1 - 0.06, z1, "Trim", "-y -x +x +z")
        b.abox(x0, x0 + 0.06, -0.22, -0.16, z0, z1 - 0.06, "Trim", "-y -x -z +z")
        b.abox(x1 - 0.06, x1, -0.22, -0.16, z0, z1 - 0.06, "Trim", "-y +x -z +z")
    b.abox(win[0], win[1], -0.22, -0.16, win[2], win[2] + 0.06, "Trim", "-y -x +x -z")
    b.abox(-0.65, -0.59, -0.22, -0.16, win[2], win[3], "Trim", "-y -z +z")
    b.abox(door[0], door[1], -0.22, -0.16, 2.55, 2.62, "Trim", "-y -x +x")
    b.abox(1.28, 1.32, -0.22, -0.16, 0.0, 2.55, "Trim", "-y -z +z")
    b.abox(1.55, 1.59, -0.1, 0.0, 1.0, 1.5, "Metal", "-y -z +z")
    b.abox(-2.0, 0.65, 0, 0.12, 0, 0.6, "Concrete", "-y -x -z")               # stall riser
    b.abox(-1.9, 0.65, 0, 0.17, 0.6, 0.68, "WallD", "-y -z")
    # sign fascia
    b.abox(-2, 2, 0, 0.12, 3.4, 4.35, "WallC", "-y -x +x")
    b.abox(-1.8, 1.8, 0.12, 0.14, 3.55, 4.2, "WallD", "-y -x +x -z +z")
    b.strip(-1.7, 1.7, 3.62, 3.65, 0.145)
    b.strip(-1.7, 1.7, 4.1, 4.13, 0.145)
    # brick pilasters
    b.abox(-2.0, -1.8, 0, 0.14, 0.0, 3.4, "WallB", "-y -x -z +z")
    b.abox(1.8, 2.0, 0, 0.14, 0.0, 3.4, "WallB", "-y +x -z +z")
    a_band(b, z0=4.45, z1=4.8, p=0.12)


def _quoin_blocks(b, kind):
    zs = [0.0, 0.62, 1.2, 1.82, 2.4, 3.02, 3.4]
    for k in range(len(zs) - 1):
        z0, z1 = zs[k], zs[k + 1]
        long_ = (k % 2 == 0)
        if kind == "out":
            xa = 0.8 if long_ else 1.3
            yb = 1.2 if not long_ else 0.7
            pts = [(xa, 0.0), (2.0, 0.0), (2.0, -yb), (2.06, -yb), (2.06, 0.06), (xa, 0.06)]
        else:
            xa = -0.8 if long_ else -1.3
            yb = 0.7 if long_ else 1.2
            pts = [(-2.0, 0.0), (xa, 0.0), (xa, 0.06), (-1.94, 0.06), (-1.94, yb), (-2.0, yb)]
        b.ez(pts, z0 + 0.015, z1 - 0.015, "WallB", caps=(False, True))


def apt_corner_out(b):
    h = (-1.45, -0.35, 0.95, 2.65)
    b.wall_y(0, -2, 2, 0, FH, [h], "WallA")
    a_window(b, h, shutters=True)
    _quoin_blocks(b, "out")
    a_band(b, -2.0, 2.1, 3.4, 3.6)
    b.abox(2.0, 2.1, -1.2, 0.0, 3.4, 3.6, "WallD", "-y -x -z")
    b.abox(-2.0, -1.88, 0, 0.07, 0, 3.4, "WallD", "-y -x -z +z")


def apt_corner_in(b):
    h = (-0.55, 0.55, 0.95, 2.65)
    h2 = (0.95, 1.7, 0.95, 2.65)
    b.wall_y(0, -2, 2, 0, FH, [h, h2], "WallA")
    a_window(b, h, shutters=False)
    a_window(b, h2, shutters=False, lintel=True)
    _quoin_blocks(b, "in")
    a_band(b, -2.0, 2.0, 3.4, 3.6)
    b.abox(1.88, 2.0, 0, 0.07, 0, 3.4, "WallD", "-y +x -z +z")


_CORNICE = [(-0.35, 0.0), (0.0, 0.0), (0.0, 0.3), (0.08, 0.3), (0.08, 0.4), (0.0, 0.4), (0.0, 1.0), (0.14, 1.0), (0.14, 1.12),
            (0.30, 1.12), (0.30, 1.30), (0.38, 1.30), (0.38, 1.48), (-0.35, 1.48)]
_CORNICE_MATS = {1: "WallA", 5: "WallB", 13: "WallA"}


def apt_cornice(b):
    b.ex(_CORNICE, -2, 2, "WallD", skip_edges=(0,), mats=_CORNICE_MATS)
    for i in range(10):
        x = -1.8 + i * 0.4
        b.abox(x - 0.08, x + 0.08, 0.0, 0.10, 0.86, 1.0, "WallD", "-y -z +z")
    for x in (-1.0, 1.0):
        b.yq(0.012, x - 0.02, x + 0.02, 0.45, 0.82, 1, "Trim")


def apt_cornice_corner(b):
    b.ex(_CORNICE, -2, 2, "WallD", skip_edges=(0,), mats=_CORNICE_MATS, caps=(True, False))
    for i in range(10):
        x = -1.8 + i * 0.4
        b.abox(x - 0.08, x + 0.08, 0.0, 0.10, 0.86, 1.0, "WallD", "-y -z +z")
    for (z0, z1, p) in ((0.3, 0.4, 0.08), (1.0, 1.12, 0.14), (1.12, 1.30, 0.30), (1.30, 1.48, 0.38)):
        b.abox(2.0, 2.0 + p, 0.0, p, z0, z1, "WallD", "-x -y")
    b.abox(2.0, 2.1, 0.0, 0.1, 0.86, 1.0, "WallD", "-x -y -z +z")


def apt_fire_escape_bay(b):
    d = (-0.7, 0.7, 0.07, 2.55)
    b.wall_y(0, -2, 2, 0, FH, [d, (-1.75, -1.0, 0.95, 2.55), (1.0, 1.75, 0.95, 2.55)], "WallA")
    b.window_y(d, 0.2, "WallA")
    b.abox(d[0], d[1], -0.2, -0.155, 1.3, 1.34, "Trim", "-y -x +x")
    b.abox(-0.025, 0.025, -0.2, -0.155, d[2], d[3], "Trim", "-y -z +z")
    for w in ((-1.75, -1.0, 0.95, 2.55), (1.0, 1.75, 0.95, 2.55)):
        a_window(b, w, 0.2, cross=False, shutters=False, sill=True)
    a_band(b)
    b.abox(-2.0, -1.88, 0, 0.07, 0, 3.4, "WallD", "-y -x -z +z")
    b.abox(1.88, 2.0, 0, 0.07, 0, 3.4, "WallD", "-y +x -z +z")
    # platform (grating) at floor level, stair flight rising to the next platform
    b.abox(-1.7, 1.7, 0.0, 1.2, 0.0, 0.07, "MetalDark", "")
    for k in range(7):
        b.yq(1.201, -1.7 + 0.5 * k + 0.05, -1.7 + 0.5 * k + 0.45, 0.012, 0.055, 1, "Trim")
    # rail (front + right end), balusters, posts
    for z in (0.55, 1.05):
        b.beamk((-1.7, 1.2, z), (1.7, 1.2, z), 0.022, 0.022, 4, "Metal", False)
    b.beamk((1.7, 0.0, 1.05), (1.7, 1.2, 1.05), 0.022, 0.022, 4, "Metal", False)
    for i in range(8):
        x = -1.4 + i * 0.42
        b.beamk((x, 1.2, 0.07), (x, 1.2, 1.05), 0.014, 0.014, 4, "Metal", False)
    for (x, y) in ((-1.7, 1.2), (1.7, 1.2), (1.7, 0.0), (0.0, 1.2)):
        b.beamk((x, y, 0.07), (x, y, 1.08), 0.03, 0.03, 4, "Metal", True)
    # stair flight (left -> right) in front of the platform
    n = 10
    for i in range(n):
        t = i / (n - 1)
        x = -1.35 + t * 2.5
        z = 0.32 + t * 3.0
        b.abox(x - 0.12, x + 0.12, 0.5, 1.1, z - 0.025, z + 0.025, "MetalDark", "-y -z")
    for y in (0.5, 1.1):
        b.beamk((-1.5, y, 0.07), (1.25, y, 3.45), 0.025, 0.025, 4, "Metal", False)


K = Kit("kit_apartment", 1)
K.add("Apt_Bay_Window", apt_bay_window)
K.add("Apt_Bay_Balcony", apt_bay_balcony)
K.add("Apt_Bay_Solid", apt_bay_solid)
K.add("Apt_Bay_Door_Stoop", apt_bay_door_stoop)
K.add("Apt_Bay_Shop_Ground", apt_bay_shop_ground)
K.add("Apt_Corner_Out", apt_corner_out)
K.add("Apt_Corner_In", apt_corner_in)
K.add("Apt_Cornice", apt_cornice)
K.add("Apt_Cornice_Corner", apt_cornice_corner, width=4.5)
K.add("Apt_FireEscape_Bay", apt_fire_escape_bay)
K.report()

if globals().get("EXPORT_KITS", False):
    K.export("buildings/kit_apartment")
