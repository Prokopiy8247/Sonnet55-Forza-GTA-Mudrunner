"""lane6_kit_shop.py - kit_shop (1-2 storey commercial strip modules). Idempotent."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane6_kitlib.py", encoding="utf8").read(), globals())

SH = 3.6


def s_frame(b, hole, depth, front=True, w=0.06):
    """Dark metal frame: around the opening on the wall face (front=True) + glass rails inside."""
    x0, x1, z0, z1 = hole
    if front:
        b.abox(x0 - w, x1 + w, 0, 0.05, z1, z1 + w, "Trim", "-y -z")
        b.abox(x0 - w, x0, 0, 0.05, z0, z1, "Trim", "-y -z +z")
        b.abox(x1, x1 + w, 0, 0.05, z0, z1, "Trim", "-y -z +z")
    yb = -depth
    b.abox(x0, x1, yb, yb + 0.04, z1 - 0.05, z1, "Trim", "-y -x +x +z")
    b.abox(x0, x0 + 0.05, yb, yb + 0.04, z0, z1 - 0.05, "Trim", "-y -x -z +z")
    b.abox(x1 - 0.05, x1, yb, yb + 0.04, z0, z1 - 0.05, "Trim", "-y +x -z +z")


def s_fascia(b, x0=-2.0, x1=2.0, z0=2.95, z1=SH, p=0.09):
    b.abox(x0, x1, 0, p, z0, z1, "WallB", "-y -x +x -z")
    b.abox(x0, x1, 0, p + 0.05, z1 - 0.07, z1, "WallD", "-y -x +x -z")
    # blank sign panel border
    for (xa, xb, za, zb) in ((x0 + 0.15, x1 - 0.15, z0 + 0.1, z0 + 0.14), (x0 + 0.15, x1 - 0.15, z1 - 0.2, z1 - 0.16)):
        b.yq(p + 0.004, xa, xb, za, zb, 1, "Trim")


def shop_front_glass(b):
    G = (-1.7, 1.7, 0.6, 2.8)
    b.wall_y(0, -2, 2, 0, SH, [G], "WallA")
    b.window_y(G, 0.25, "WallD")
    s_frame(b, G, 0.25)
    for x in (-0.6, 0.6):
        b.abox(x - 0.03, x + 0.03, -0.25, 0.02, G[2], G[3], "Trim", "-y -z +z")
    b.abox(G[0], G[1], -0.25, 0.02, 1.9, 1.95, "Trim", "-y -x +x")
    b.abox(-2, 2, 0, 0.10, 0, 0.6, "WallD", "-y -x +x -z")
    b.abox(-1.7, 1.7, 0.10, 0.13, 0.1, 0.5, "WallA", "-y -x +x -z +z")
    b.abox(-1.8, 1.8, 0, 0.14, 0.6, 0.68, "Concrete", "-y -z")
    b.abox(-2.0, -1.82, 0, 0.12, 0, 2.95, "WallB", "-y -x -z +z")
    b.abox(1.82, 2.0, 0, 0.12, 0, 2.95, "WallB", "-y +x -z +z")
    s_fascia(b)


def shop_front_door(b):
    D = (-0.6, 0.6, 0.0, 2.8)
    S1 = (-1.7, -0.85, 0.6, 2.8)
    S2 = (0.85, 1.7, 0.6, 2.8)
    b.wall_y(0, -2, 2, 0, SH, [D, S1, S2], "WallA")
    b.reveal_y(D, 0, -0.25, "WallD", "lrt")
    b.yq(-0.25, D[0], D[1], D[2], D[3], 1, "Window")
    for S in (S1, S2):
        b.window_y(S, 0.25, "WallD")
        s_frame(b, S, 0.25)
    s_frame(b, D, 0.25)
    b.abox(-0.6, 0.6, -0.25, -0.2, 2.35, 2.42, "Trim", "-y -x +x")
    b.abox(-0.025, 0.025, -0.25, -0.2, 0.0, 2.35, "Trim", "-y -z +z")
    for x in (-0.12, 0.12):
        b.abox(x - 0.015, x + 0.015, -0.15, -0.02, 1.0, 1.45, "Metal", "-y -z +z")
    b.abox(-0.7, 0.7, 0, 0.8, 0, 0.08, "Concrete", "-y -z")
    for (xa, xb) in ((-1.9, -0.85), (0.85, 1.9)):
        b.abox(xa, xb, 0, 0.10, 0, 0.6, "WallD", "-y -z")
    b.abox(-2.0, -1.82, 0, 0.12, 0, 2.95, "WallB", "-y -x -z +z")
    b.abox(1.82, 2.0, 0, 0.12, 0, 2.95, "WallB", "-y +x -z +z")
    s_fascia(b)


def shop_front_wide(b):
    W1 = (-3.8, -0.9, 0.6, 2.8)
    W2 = (0.9, 3.8, 0.6, 2.8)
    D = (-0.55, 0.55, 0.0, 2.8)
    b.wall_y(0, -4, 4, 0, SH, [W1, W2, D], "WallA")
    for W in (W1, W2):
        b.window_y(W, 0.25, "WallD")
        s_frame(b, W, 0.25)
    b.reveal_y(D, 0, -0.25, "WallD", "lrt")
    b.yq(-0.25, D[0], D[1], D[2], D[3], 1, "Window")
    s_frame(b, D, 0.25)
    for x in (-2.85, -1.9, 1.9, 2.85):
        b.abox(x - 0.03, x + 0.03, -0.25, 0.02, 0.6, 2.8, "Trim", "-y -z +z")
    for W in (W1, W2):
        b.abox(W[0], W[1], -0.25, 0.02, 1.9, 1.95, "Trim", "-y -x +x")
    b.abox(-0.025, 0.025, -0.25, -0.2, 0.0, 2.4, "Trim", "-y -z +z")
    b.abox(-0.55, 0.55, -0.25, -0.2, 2.4, 2.46, "Trim", "-y -x +x")
    for (xa, xb) in ((-3.9, -0.9), (0.9, 3.9)):
        b.abox(xa, xb, 0, 0.10, 0, 0.6, "WallD", "-y -z")
    b.abox(-0.65, 0.65, 0, 0.8, 0, 0.08, "Concrete", "-y -z")
    for (xa, xb) in ((-4.0, -3.86), (-1.0, -0.8), (0.8, 1.0), (3.86, 4.0)):
        b.abox(xa, xb, 0, 0.12, 0, 2.95, "WallB", "-y -z +z")
    s_fascia(b, -4.0, 4.0)


def _awning_stripes(b, n, x0, x1, ya, za, yb, zb, mats=("WallB", "WallD")):
    xs = [x0 + (x1 - x0) * i / n for i in range(n + 1)]
    for i in range(n):
        m = mats[i % 2]
        # sloped top (outward normal up/out)
        b.pq([(xs[i], ya, za), (xs[i + 1], ya, za), (xs[i + 1], yb, zb), (xs[i], yb, zb)], (0, 0.5, 1.0), m)
    return xs


def shop_awning_a(b):
    n = 8
    x0, x1 = -1.95, 1.95
    xs = _awning_stripes(b, n, x0, x1, 0.0, 3.0, 1.55, 2.45)
    # scalloped valance (front, facing +Y)
    for i in range(n):
        m = ("WallB", "WallD")[i % 2]
        xm = (xs[i] + xs[i + 1]) / 2
        b.pq([(xs[i], 1.55, 2.45), (xs[i + 1], 1.55, 2.45), (xs[i + 1], 1.58, 2.2), (xm, 1.6, 2.08), (xs[i], 1.58, 2.2)], (0, 1, 0), m)
    # underside + side triangles + back strip
    b.pq([(x0, 0.0, 3.0), (x1, 0.0, 3.0), (x1, 1.55, 2.45), (x0, 1.55, 2.45)], (0, -0.5, -1), "WallD")
    for sx in (-1, 1):
        x = x1 if sx > 0 else x0
        b.pq([(x, 0.0, 3.0), (x, 1.55, 2.45), (x, 1.58, 2.2), (x, 1.55, 2.2), (x, 0.0, 2.9)], (sx, 0, 0), "WallB")
    b.abox(x0, x1, 1.55, 1.6, 2.4, 2.47, "Trim", "-y -x +x")
    for sx in (-1, 1):
        b.beamk((sx * 1.7, 0.0, 2.35), (sx * 1.7, 1.5, 2.42), 0.022, 0.022, 4, "Metal", False)
        b.beamk((sx * 1.7, 0.0, 2.75), (sx * 1.7, 1.2, 2.5), 0.015, 0.015, 4, "Metal", False)
    b.abox(x0, x1, 0.0, 0.05, 2.9, 3.05, "Trim", "-y -x +x")


def shop_awning_b(b):
    n = 8
    x0, x1 = -1.95, 1.95
    R = 1.1
    cz = 2.0
    pts = []
    for k in range(6):                       # quarter circle: (y, z) from top (0, cz+R) to front (R, cz)
        a = math.radians(90 - 90 * k / 5.0)
        pts.append((R * math.cos(a) * 1.15 if k else 0.0, cz + R * math.sin(a)))
    pts[0] = (0.0, cz + R)
    xs = [x0 + (x1 - x0) * i / n for i in range(n + 1)]
    for i in range(n):
        m = ("WallC", "WallD")[i % 2]
        for k in range(len(pts) - 1):
            ya, za = pts[k]
            yb, zb = pts[k + 1]
            mid = ((ya + yb) / 2, (za + zb) / 2 - cz)
            b.pq([(xs[i], ya, za), (xs[i + 1], ya, za), (xs[i + 1], yb, zb), (xs[i], yb, zb)], (0, mid[0], mid[1]), m)
    # underside + pie caps
    b.pq([(x0, 0.0, cz), (x1, 0.0, cz), (x1, pts[-1][0], cz), (x0, pts[-1][0], cz)], (0, 0, -1), "WallD")
    for sx in (-1, 1):
        x = x1 if sx > 0 else x0
        b.pq([(x, 0.0, cz)] + [(x, p[0], p[1]) for p in pts], (sx, 0, 0), "WallD")
    b.abox(x0, x1, pts[-1][0] - 0.02, pts[-1][0] + 0.03, cz - 0.1, cz + 0.02, "Trim", "-y -x +x")
    for sx in (-1, 1):
        b.beamk((sx * 1.7, 0.0, cz), (sx * 1.7, pts[-1][0], cz), 0.02, 0.02, 4, "Metal", False)


def shop_sign_board(b):
    b.abox(-1.8, 1.8, 0.0, 0.2, 3.0, 3.75, "Trim", "-y")
    b.yq(0.205, -1.7, 1.7, 3.08, 3.67, 1, "Neon")
    for sx in (-1, 1):
        b.abox(sx * 1.55 - 0.05, sx * 1.55 + 0.05, -0.1, 0.0, 3.1, 3.6, "Metal", "-y")
    for x in (-1.1, 0.0, 1.1):
        b.beamk((x, 0.2, 3.72), (x, 0.55, 3.98), 0.014, 0.014, 4, "Metal", False)
        b.abox(x - 0.07, x + 0.07, 0.5, 0.64, 3.95, 4.05, "LampGlow", "")


def shop_sign_blade(b):
    # wall bracket + hanging double-sided board, perpendicular to the facade
    b.abox(-0.05, 0.05, -0.03, 0.04, 2.8, 4.0, "Trim", "-y")
    b.beamk((0, 0.0, 3.92), (0, 1.25, 3.92), 0.03, 0.03, 4, "Metal", True)
    b.beamk((0, 0.0, 3.35), (0, 1.15, 3.9), 0.02, 0.02, 4, "Metal", False)
    for y in (0.3, 1.0):
        b.beamk((0, y, 3.92), (0, y, 3.66), 0.008, 0.008, 4, "Metal", False)
    b.abox(-0.07, 0.07, 0.12, 1.18, 2.85, 3.66, "Trim", "")
    for s in (-1, 1):
        b.xq(s * 0.0725, 0.18, 1.12, 2.91, 3.6, s, "Neon")
    b.abox(-0.05, 0.05, 0.62, 0.68, 2.7, 2.85, "Metal", "")


def shop_upper_window(b):
    G = (-0.95, 0.95, 0.95, 2.75)
    b.wall_y(0, -2, 2, 0, SH, [G], "WallA")
    b.window_y(G, 0.24, "WallD")
    s_frame(b, G, 0.24)
    b.abox(-0.03, 0.03, -0.24, 0.02, G[2], G[3], "Trim", "-y -z +z")
    b.abox(G[0], G[1], -0.24, 0.02, 2.1, 2.15, "Trim", "-y -x +x")
    b.abox(-1.2, 1.2, 0, 0.17, 0.86, 0.95, "Concrete", "-y -z")
    b.abox(-1.1, 1.1, 0.0, 0.3, 0.5, 0.86, "Wood", "-y -z")
    b.abox(-1.05, 1.05, 0.04, 0.26, 0.86, 1.1, "Leaf", "-y -z")
    for x in (-0.7, -0.2, 0.35, 0.8):
        b.abox(x - 0.06, x + 0.06, 0.1, 0.2, 1.1, 1.22, "Accent" if x < 0 else "Neon", "-y -z")
    for (xa, xb) in ((-1.55, -1.1), (1.1, 1.55)):
        b.abox(xa, xb, 0, 0.045, 0.85, 2.85, "WallC", "-y -z +z")
        for k in range(1, 8):
            z = 0.85 + k * 0.25
            b.yq(0.05, xa + 0.04, xb - 0.04, z, z + 0.02, 1, "Trim")
    b.abox(-1.2, 1.2, 0, 0.10, 2.75, 2.9, "WallD", "-y -z")
    b.abox(-0.12, 0.12, 0, 0.14, 2.9, 3.05, "WallD", "-y -z")
    b.abox(-2.0, -1.85, 0, 0.1, 0, 3.3, "WallB", "-y -x -z +z")
    b.abox(1.85, 2.0, 0, 0.1, 0, 3.3, "WallB", "-y +x -z +z")
    b.abox(-2, 2, 0, 0.14, 3.3, 3.6, "WallD", "-y -x +x -z")


def shop_parapet(b):
    pts = [(-2.0, 0.0), (2.0, 0.0), (2.0, 1.1), (1.5, 1.1), (1.2, 1.55), (-1.2, 1.55), (-1.5, 1.1), (-2.0, 1.1)]
    b.ey(pts, -0.25, 0.0, "WallA", caps=(True, True), skip_edges=(0,))
    b.abox(-2.0, 2.0, 0, 0.12, 0.0, 0.22, "WallD", "-y -x +x -z")
    b.abox(-2.0, 2.0, 0, 0.14, 0.82, 0.95, "WallD", "-y -x +x -z")
    b.abox(-2.0, -1.5, -0.3, 0.1, 1.1, 1.18, "WallD", "-x -z")
    b.abox(1.5, 2.0, -0.3, 0.1, 1.1, 1.18, "WallD", "+x -z")
    # coping on the raised centre
    b.abox(-1.28, 1.28, -0.3, 0.1, 1.55, 1.63, "WallD", "-z")
    # panel inset on the raised part
    b.yq(0.004, -1.0, 1.0, 1.15, 1.2, 1, "Trim")
    b.yq(0.004, -1.0, 1.0, 1.42, 1.47, 1, "Trim")
    b.yq(0.004, -1.0, -0.96, 1.15, 1.47, 1, "Trim")
    b.yq(0.004, 0.96, 1.0, 1.15, 1.47, 1, "Trim")
    for x in (-1.85, 1.85):
        b.blockk((x, -0.1), 1.1, 1.55, (0.3, 0.3), (0.04, 0.04), "WallD")


def shop_corner(b):
    G = (-1.75, 0.65, 0.6, 2.8)
    b.wall_y(0, -2, 2, 0, SH, [G], "WallA")
    b.window_y(G, 0.25, "WallD")
    s_frame(b, G, 0.25)
    b.abox(-0.55, -0.49, -0.25, 0.02, G[2], G[3], "Trim", "-y -z +z")
    b.abox(G[0], G[1], -0.25, 0.02, 1.9, 1.95, "Trim", "-y -x +x")
    b.abox(-2, 0.9, 0, 0.10, 0, 0.6, "WallD", "-y -x -z")
    b.abox(-1.85, 0.7, 0, 0.14, 0.6, 0.68, "Concrete", "-y -z")
    pts = [(0.9, 0.0), (2.0, 0.0), (2.0, -1.1), (2.13, -1.1), (2.13, 0.08), (2.07, 0.14), (0.9, 0.14)]
    b.ez(pts, 0, 2.95, "WallB", caps=(False, True), skip_edges=(0, 1))
    b.abox(-2.0, -1.82, 0, 0.12, 0, 2.95, "WallB", "-y -x -z +z")
    # fascia wraps around the corner
    b.abox(-2.0, 2.13, 0, 0.09, 2.95, SH, "WallB", "-y -x -z")
    b.abox(2.0, 2.13, -1.1, 0.0, 2.95, SH, "WallB", "-y -x -z")
    b.abox(-2.0, 2.18, 0, 0.14, SH - 0.07, SH, "WallD", "-y -x -z")
    b.abox(2.0, 2.18, -1.1, 0.0, SH - 0.07, SH, "WallD", "-y -x -z")
    # corner lamp
    b.beamk((2.05, 0.12, 2.5), (2.05, 0.12, 2.9), 0.02, 0.02, 4, "Metal", False)
    b.spherek((2.05, 0.12, 2.9), 0.09, 6, 3, "LampGlow")
    b.yq(0.09 + 0.004, -1.85, 0.78, 3.05, 3.09, 1, "Trim")
    b.yq(0.09 + 0.004, -1.85, 0.78, 3.42, 3.46, 1, "Trim")


K = Kit("kit_shop", 2)
K.add("Shop_Front_Glass", shop_front_glass)
K.add("Shop_Front_Door", shop_front_door)
K.add("Shop_Front_Wide", shop_front_wide, width=8.0)
K.add("Shop_Awning_A", shop_awning_a)
K.add("Shop_Awning_B", shop_awning_b)
K.add("Shop_Sign_Board", shop_sign_board)
K.add("Shop_Sign_Blade", shop_sign_blade, width=1.5)
K.add("Shop_Upper_Window", shop_upper_window)
K.add("Shop_Parapet", shop_parapet)
K.add("Shop_Corner", shop_corner)
K.report()

if globals().get("EXPORT_KITS", False):
    K.export("buildings/kit_shop")
