"""lane6_kit_office.py - kit_office (modern curtain-wall tower modules). Idempotent: rebuilds all kit_office__* objects.
Run: exec(open(r"...\\tools\\blender\\lane6_kit_office.py", encoding="utf8").read(), globals())  (gta_lib already loaded)"""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane6_kitlib.py", encoding="utf8").read(), globals())


def o_floorband(b, x0=-2.0, x1=2.0, z0=3.3, z1=3.6, p=0.10, mat="WallD"):
    b.abox(x0, x1, 0, p, z0, z1, mat, "-y -x +x -z")


def o_fins(b, z1=3.3, p=0.10, mat="WallD", w=0.10):
    b.abox(-2.0, -2.0 + w, 0, p, 0, z1, mat, "-y -x -z +z")
    b.abox(2.0 - w, 2.0, 0, p, 0, z1, mat, "-y +x -z +z")


def o_frame(b, hole, depth, w=0.05, mat="Trim"):
    """Thin dark frame hugging the glass inside the reveal."""
    x0, x1, z0, z1 = hole
    yb = -depth
    f = 0.045
    b.abox(x0, x1, yb, yb + f, z0, z0 + w, mat, "-y -x +x -z")      # bottom rail
    b.abox(x0, x1, yb, yb + f, z1 - w, z1, mat, "-y -x +x +z")      # top rail
    b.abox(x0, x0 + w, yb, yb + f, z0 + w, z1 - w, mat, "-y -x -z +z")
    b.abox(x1 - w, x1, yb, yb + f, z0 + w, z1 - w, mat, "-y +x -z +z")


def office_bay_window(b):
    g = (-1.74, 1.74, 0.95, 3.02)
    b.wall_y(0, -2, 2, 0, FH, [g], "WallA")
    b.window_y(g, 0.18, "WallD")
    o_frame(b, g, 0.18)
    for x in (-0.58, 0.58):
        b.abox(x - 0.035, x + 0.035, -0.18, 0.03, g[2], g[3], "Trim", "-y -z +z")
    b.abox(g[0], g[1], -0.18, 0.03, 2.62, 2.69, "Trim", "-y -x +x")          # transom
    b.abox(-1.86, 1.86, 0, 0.13, 0.84, 0.95, "Concrete", "-y -z")            # sill
    b.abox(-1.74, 1.74, 0, 0.045, 0.12, 0.80, "WallC", "-y -x +x -z +z")     # tinted spandrel panel
    b.strip(-1.74, 1.74, 0.46, 0.49, 0.05)
    o_floorband(b)
    o_fins(b)


def office_bay_solid(b):
    holes = [(-1.7, -0.12, 0.55, 3.0), (0.12, 1.7, 0.55, 3.0)]
    b.wall_y(0, -2, 2, 0, FH, holes, "WallA")
    for h in holes:
        b.reveal_y(h, 0, -0.07, "WallD")
        b.yq(-0.07, h[0], h[1], h[2], h[3], 1, "WallB")
    # louvre vent on the right inset
    for i in range(6):
        z = 0.75 + i * 0.13
        b.yq(-0.055, 0.45, 1.35, z, z + 0.05, 1, "Trim")
    b.strip(-1.5, -0.3, 1.78, 1.82, -0.055)
    o_floorband(b)
    o_fins(b)


def office_bay_spandrel_stripe(b):
    g = (-2.0, 2.0, 1.0, 2.6)
    b.wall_y(0, -2, 2, 0, FH, [g], "WallA")
    b.reveal_y(g, 0, -0.14, "WallD", "tb")
    b.yq(-0.14, g[0], g[1], g[2], g[3], 1, "Window")
    for x in (-1.0, 0.0, 1.0):
        b.abox(x - 0.03, x + 0.03, -0.14, 0.03, g[2], g[3], "Trim", "-y -z +z")
    b.abox(-2, 2, -0.14, 0.03, 1.0, 1.06, "Trim", "-y -x +x")
    b.abox(-2, 2, -0.14, 0.03, 2.54, 2.6, "Trim", "-y -x +x")
    b.abox(-2, 2, 0, 0.05, 0.12, 0.88, "WallC", "-y -x +x -z")               # lower spandrel stripe
    b.abox(-2, 2, 0, 0.05, 2.72, 3.22, "WallC", "-y -x +x -z")               # upper spandrel stripe
    b.abox(-2, 2, 0, 0.10, 0.88, 1.0, "WallD", "-y -x +x -z")                # sill band
    o_floorband(b)


def office_bay_ground_lobby(b):
    G = (-1.8, 1.8, 0.0, 3.9)
    b.wall_y(0, -2, 2, 0, GH, [G], "WallA")
    b.reveal_y(G, 0, -0.22, "WallD", "lrt")
    b.yq(-0.22, G[0], G[1], G[2], G[3], 1, "Window")
    # plinth + riser under side lights
    b.abox(-2, 2, 0, 0.10, 0, 0.30, "Concrete", "-y -x +x -z")
    b.abox(-1.8, -0.9, -0.22, 0.0, 0.0, 0.40, "Concrete", "-y -x -z")
    b.abox(0.9, 1.8, -0.22, 0.0, 0.0, 0.40, "Concrete", "-y +x -z")
    # door frames (double leaf) + mullions + transom
    for x in (-0.9, 0.0, 0.9):
        b.abox(x - 0.035, x + 0.035, -0.22, -0.08, 0.0, 2.55, "Trim", "-y -z +z")
    b.abox(-0.9, 0.9, -0.22, -0.08, 2.5, 2.6, "Trim", "-y -x +x")
    for x in (-1.35, 1.35):
        b.abox(x - 0.03, x + 0.03, -0.22, -0.06, 0.4, 3.9, "Trim", "-y -z +z")
    b.abox(-1.8, 1.8, -0.22, -0.06, 2.6, 2.66, "Trim", "-y -x +x")
    for x in (-0.12, 0.12):
        b.abox(x - 0.015, x + 0.015, -0.12, 0.0, 1.0, 1.55, "Metal", "-y -z +z")   # pull handles
    b.abox(-1.2, 1.2, 0, 1.0, 0, 0.07, "Concrete", "-y -z")                          # entry slab
    # canopy
    b.abox(-1.95, 1.95, 0, 1.5, 4.0, 4.2, "Concrete", "-y")
    b.abox(-1.95, 1.95, 1.5, 1.56, 3.98, 4.06, "NeonCyan", "-y -x +x")
    for x in (-1.7, 1.7):
        b.beamk((x, 0.0, 4.75), (x, 1.4, 4.2), 0.022, 0.022, 4, "Metal", False)
    b.abox(-1.0, 1.0, 0, 0.06, 4.3, 4.65, "WallD", "-y -x +x -z")                    # sign plate
    o_floorband(b, z0=4.5, z1=GH)
    b.abox(-2.0, -1.9, 0, 0.10, 0, 4.5, "WallD", "-y -x -z +z")
    b.abox(1.9, 2.0, 0, 0.10, 0, 4.5, "WallD", "-y +x -z +z")


def office_bay_ground_window(b):
    G = (-1.8, 1.8, 0.55, 3.8)
    b.wall_y(0, -2, 2, 0, GH, [G], "WallA")
    b.window_y(G, 0.22, "WallD")
    o_frame(b, G, 0.22, 0.06)
    for x in (-0.9, 0.0, 0.9):
        b.abox(x - 0.035, x + 0.035, -0.22, 0.03, G[2], G[3], "Trim", "-y -z +z")
    b.abox(G[0], G[1], -0.22, 0.03, 2.9, 2.97, "Trim", "-y -x +x")
    b.abox(-2, 2, 0, 0.12, 0, 0.55, "Concrete", "-y -x +x -z")                       # stone plinth
    b.strip(-1.8, 1.8, 0.28, 0.31, 0.125, "Trim")
    b.abox(-1.9, 1.9, 0, 0.16, 0.55, 0.64, "WallD", "-y -z")                         # sill
    b.abox(-1.9, 1.9, 0, 0.10, 3.8, 3.9, "WallD", "-y -z")                           # lintel
    b.strip(-1.7, 1.7, 4.12, 4.15, 0.012)
    o_floorband(b, z0=4.5, z1=GH)
    b.abox(-2.0, -1.9, 0, 0.10, 0.55, 4.5, "WallD", "-y -x -z +z")
    b.abox(1.9, 2.0, 0, 0.10, 0.55, 4.5, "WallD", "-y +x -z +z")


def _corner_pier(b, z1=FH):
    # L pier in plan: front arm x 0.55..2.0 and return arm along -Y, protruding 0.14 beyond both faces
    pts = [(0.55, 0.0), (2.0, 0.0), (2.0, -1.0), (2.14, -1.0), (2.14, 0.09), (2.09, 0.14), (0.55, 0.14)]
    b.ez(pts, 0, z1, "WallD", caps=(False, True), skip_edges=(0, 1))
    b.strip(0.62, 0.68, 0.0, z1 - 0.3, 0.145)


def office_corner_out(b):
    g = (-1.58, 0.28, 0.95, 3.02)
    b.wall_y(0, -2, 2, 0, FH, [g], "WallA")
    b.window_y(g, 0.18, "WallD")
    o_frame(b, g, 0.18)
    b.abox(-0.65, -0.58, -0.18, 0.03, g[2], g[3], "Trim", "-y -z +z")
    b.abox(g[0], g[1], -0.18, 0.03, 2.62, 2.69, "Trim", "-y -x +x")
    b.abox(-1.7, 0.42, 0, 0.13, 0.84, 0.95, "Concrete", "-y -z")
    b.abox(-1.58, 0.28, 0, 0.045, 0.12, 0.80, "WallC", "-y -x +x -z +z")
    _corner_pier(b)
    o_floorband(b, -2.0, 0.55)
    b.abox(-2.0, 2.14, 0, 0.10, 3.3, 3.6, "WallD", "-y -x -z")
    b.abox(2.0, 2.14, -1.0, 0.0, 3.3, 3.6, "WallD", "-y -x -z")
    b.abox(-2.0, -1.9, 0, 0.10, 0, 3.3, "WallD", "-y -x -z +z")


def office_corner_in(b):
    g = (-1.15, 1.78, 0.95, 3.02)
    b.wall_y(0, -2, 2, 0, FH, [g], "WallA")
    b.window_y(g, 0.18, "WallD")
    o_frame(b, g, 0.18)
    for x in (-0.2, 0.7):
        b.abox(x - 0.035, x + 0.035, -0.18, 0.03, g[2], g[3], "Trim", "-y -z +z")
    b.abox(g[0], g[1], -0.18, 0.03, 2.62, 2.69, "Trim", "-y -x +x")
    b.abox(-1.28, 1.86, 0, 0.13, 0.84, 0.95, "Concrete", "-y -z")
    b.abox(-1.15, 1.74, 0, 0.045, 0.12, 0.80, "WallC", "-y -x +x -z +z")
    pts = [(-2.0, 0.0), (-1.45, 0.0), (-1.45, 0.45), (-1.55, 0.55), (-2.0, 0.55)]
    b.ez(pts, 0, FH, "WallD", caps=(False, True), skip_edges=(0, 4))
    b.strip(-1.5, -1.46, 0.0, FH - 0.3, 0.556)
    o_floorband(b, -1.45, 2.0)
    b.abox(1.9, 2.0, 0, 0.10, 0, 3.3, "WallD", "-y +x -z +z")


def office_pilaster(b):
    w = 0.4
    pts = [(-w, -0.35), (w, -0.35), (w, 0.10), (w - 0.12, 0.28), (-w + 0.12, 0.28), (-w, 0.10)]
    b.ez(pts, 0.28, FH - 0.28, "WallD", caps=(False, False), skip_edges=(0,))
    # base and capital blocks
    b.abox(-w - 0.05, w + 0.05, -0.1, 0.34, 0, 0.28, "Concrete", "-y -z")
    b.abox(-w - 0.05, w + 0.05, -0.1, 0.34, FH - 0.28, FH, "Concrete", "-y -z")
    b.strip(-0.04, 0.04, 0.5, FH - 0.5, 0.285, "NeonCyan")
    b.strip(-0.25, -0.2, 0.5, FH - 0.5, 0.285, "Trim")
    b.strip(0.2, 0.25, 0.5, FH - 0.5, 0.285, "Trim")


def office_cornice(b):
    P = [(-0.35, 0.0), (0.0, 0.0), (0.0, 0.30), (0.12, 0.30), (0.12, 0.42), (0.0, 0.42), (0.0, 1.10), (0.16, 1.10),
         (0.34, 1.24), (0.34, 1.45), (-0.35, 1.45)]
    mats = {1: "WallA", 5: "WallA", 10: "WallA"}
    b.ex(P, -2, 2, "WallD", skip_edges=(0,), mats=mats)
    for x in (-1.2, 0.0, 1.2):
        b.strip(x - 0.02, x + 0.02, 0.46, 1.06, 0.012)
    b.strip(-2.0, 2.0, 0.70, 0.73, 0.012)


def office_crown_a(b):
    P = [(-2.7, 0.0), (0.0, 0.0), (0.0, 1.2), (-0.9, 1.2), (-0.9, 2.3), (-1.8, 2.3), (-1.8, 3.2), (-2.7, 3.2)]
    mats = {1: "WallA", 3: "WallA", 5: "WallA", 7: "WallA", 2: "WallD", 4: "WallD", 6: "WallD"}
    b.ex(P, -2, 2, "WallD", skip_edges=(0,), mats=mats)
    for (y, z0, z1) in ((0.0, 0.35, 0.95), (-0.9, 1.45, 2.05), (-1.8, 2.5, 3.0)):
        b.yq(y + 0.012, -1.6, 1.6, z0, z1, 1, "Window")
        b.yq(y + 0.016, -1.6, 1.6, z0, z0 + 0.05, 1, "Trim")
        b.yq(y + 0.016, -1.6, 1.6, z1 - 0.05, z1, 1, "Trim")
        b.yq(y + 0.016, -1.6, -1.55, z0, z1, 1, "Trim")
        b.yq(y + 0.016, 1.55, 1.6, z0, z1, 1, "Trim")
        for x in (-0.8, 0.0, 0.8):
            b.yq(y + 0.016, x - 0.02, x + 0.02, z0, z1, 1, "Trim")
    for (y, zt) in ((0.0, 1.2), (-0.9, 2.3), (-1.8, 3.2)):
        b.yq(y + 0.013, -2.0, 2.0, zt - 0.17, zt - 0.11, 1, "NeonCyan")


def office_podium_base(b):
    holes = [(-0.35, 0.35, 1.2, 3.7), (-1.55, -0.95, 1.2, 3.7), (0.95, 1.55, 1.2, 3.7)]
    b.wall_y(0, -2, 2, 0, GH, holes, "WallD")
    for h in holes:
        b.window_y(h, 0.32, "WallA")
    b.abox(-2, 2, 0, 0.22, 0, 0.55, "Concrete", "-y -x +x -z")
    b.abox(-2, 2, 0, 0.10, 0.55, 0.85, "Concrete", "-y -x +x -z")
    for z in (1.1, 2.0, 2.9, 3.8):
        b.strip(-2.0, 2.0, z, z + 0.03, 0.013)
    P = [(-0.35, 4.25), (0.0, 4.25), (0.0, 4.4), (0.22, 4.4), (0.22, 4.52), (0.3, 4.52), (0.3, 4.8), (-0.35, 4.8)]
    b.ex(P, -2, 2, "WallA", skip_edges=(0,))


K = Kit("kit_office", 0)
K.add("Office_Bay_Window", office_bay_window)
K.add("Office_Bay_Solid", office_bay_solid)
K.add("Office_Bay_Spandrel_Stripe", office_bay_spandrel_stripe)
K.add("Office_Bay_Ground_Lobby", office_bay_ground_lobby)
K.add("Office_Bay_Ground_Window", office_bay_ground_window)
K.add("Office_Corner_Out", office_corner_out)
K.add("Office_Corner_In", office_corner_in)
K.add("Office_Pilaster", office_pilaster, width=0.8)
K.add("Office_Cornice", office_cornice)
K.add("Office_Crown_A", office_crown_a)
K.add("Office_Podium_Base", office_podium_base)
K.report()

if globals().get("EXPORT_KITS", False):
    K.export("buildings/kit_office")
