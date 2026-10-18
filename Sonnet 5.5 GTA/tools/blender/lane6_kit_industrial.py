"""lane6_kit_industrial.py - kit_industrial (sheds / warehouses / silos). Idempotent.
Wall bays are 4.0 m wide x 6.0 m tall (IH). Roof modules sit on top of the wall (z=0 = eave line)."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane6_kitlib.py", encoding="utf8").read(), globals())
from mathutils import Matrix

IH = 6.0
PL = 0.6          # concrete plinth height


def corr(b, x0, x1, z0, z1, mat="WallA", pitch=0.25, amp=0.07, y=0.0):
    """Corrugated sheet: zig-zag ribs in plan, extruded between z0..z1, facing +Y."""
    n = int(round((x1 - x0) / pitch))
    if n % 2:
        n += 1
    xs = [x0 + (x1 - x0) * i / n for i in range(n + 1)]
    for i in range(n):
        ya = y + (amp if i % 2 else 0.0)
        yb = y + (0.0 if i % 2 else amp)
        b.pq([(xs[i], ya, z0), (xs[i + 1], yb, z0), (xs[i + 1], yb, z1), (xs[i], ya, z1)], (0, 1, 0), mat)


def i_plinth(b, x0=-2.0, x1=2.0, h=PL):
    b.abox(x0, x1, 0, 0.12, 0, h, "Concrete", "-y -x +x -z")


def i_columns(b, z1=IH - 0.3, left=True, right=True):
    if left:
        b.abox(-2.0, -1.88, 0, 0.13, PL, z1, "MetalDark", "-y -x -z")
    if right:
        b.abox(1.88, 2.0, 0, 0.13, PL, z1, "MetalDark", "-y +x -z")


def i_top(b, x0=-2.0, x1=2.0):
    b.abox(x0, x1, 0, 0.16, IH - 0.3, IH, "Metal", "-y -x +x -z")


def ind_wall_corrugated(b):
    i_plinth(b)
    corr(b, -2.0, 2.0, PL, IH - 0.3)
    i_columns(b)
    i_top(b)
    for z in (2.2, 4.2):
        b.abox(-2.0, 2.0, 0.07, 0.12, z, z + 0.08, "MetalDark", "-y -x +x -z")           # girt lines


def ind_wall_windows_band(b):
    i_plinth(b)
    corr(b, -2.0, 2.0, PL, 3.4)
    b.abox(-2.0, 2.0, -0.12, 0.11, 3.38, 3.48, "Metal", "-y -x +x -z")
    b.abox(-2.0, 2.0, -0.12, 0.11, 5.12, 5.22, "Metal", "-y -x +x")
    b.yq(-0.12, -2.0, 2.0, 3.48, 5.12, 1, "Window")
    b.reveal_y((-2.0, 2.0, 3.48, 5.12), 0.11, -0.12, "MetalDark", "")
    for x in (-1.5, -0.5, 0.5, 1.5):
        b.abox(x - 0.03, x + 0.03, -0.12, 0.02, 3.48, 5.12, "Trim", "-y -z +z")
    b.abox(-2.0, 2.0, -0.12, 0.02, 4.28, 4.33, "Trim", "-y -x +x")
    corr(b, -2.0, 2.0, 5.22, IH - 0.3)
    i_columns(b)
    i_top(b)


def ind_door_roller(b):
    DW0, DW1, DH = -1.6, 1.6, 4.5
    i_plinth(b, -2.0, -1.6)
    i_plinth(b, 1.6, 2.0)
    corr(b, -2.0, -1.6, PL, IH - 0.3, pitch=0.2)
    corr(b, 1.6, 2.0, PL, IH - 0.3, pitch=0.2)
    corr(b, -1.6, 1.6, DH + 0.35, IH - 0.3)
    # door frame / guides + coil box
    b.abox(DW0 - 0.2, DW0, -0.02, 0.2, 0, DH + 0.35, "MetalDark", "-y -z")
    b.abox(DW1, DW1 + 0.2, -0.02, 0.2, 0, DH + 0.35, "MetalDark", "-y -z")
    b.cylk((0, 0.02, DH + 0.2), 0.28, 3.4, 10, "Metal", axis="X", caps=True)
    b.abox(-1.65, 1.65, -0.02, 0.22, DH, DH + 0.06, "MetalDark", "-y")
    # shutter leaf
    b.yq(-0.12, DW0, DW1, 0.0, DH, 1, "WallD")
    for k in range(1, 22):
        z = k * 0.2
        b.yq(-0.11, DW0, DW1, z, z + 0.025, 1, "MetalDark")
    b.abox(DW0, DW1, -0.18, -0.05, 0.0, 0.18, "Accent", "-y")
    b.abox(-0.4, 0.4, -0.16, -0.08, 0.5, 0.65, "Metal", "")                      # handle bar
    # bollards + lamp + control box
    for x in (-1.85, 1.85):
        b.cylk((x, 0.5, 0.55), 0.13, 1.1, 8, "Accent", axis="Z")
    b.abox(1.65, 1.8, 0.22, 0.32, 1.2, 1.6, "Trim", "-y")
    b.abox(-0.2, 0.2, 0.0, 0.25, 5.05, 5.25, "LampGlow", "-y")
    i_top(b)


def ind_door_man(b):
    i_plinth(b)
    corr(b, -2.0, -0.85, PL, IH - 0.3)
    corr(b, 0.85, 2.0, PL, IH - 0.3)
    corr(b, -0.85, 0.85, 2.9, IH - 0.3)
    # flat door surround
    D = (-0.5, 0.5, 0.0, 2.2)
    b.abox(-0.85, -0.5, -0.05, 0.1, 0.0, 2.9, "WallD", "-y -z")
    b.abox(0.5, 0.85, -0.05, 0.1, 0.0, 2.9, "WallD", "-y -z")
    b.abox(-0.5, 0.5, -0.05, 0.1, 2.2, 2.9, "WallD", "-y -x +x -z")
    b.xq(-0.5, -0.05, 0.1, 0.0, 2.2, 1, "MetalDark")
    b.xq(0.5, -0.05, 0.1, 0.0, 2.2, -1, "MetalDark")
    b.zq(2.2, -0.5, 0.5, -0.05, 0.1, -1, "MetalDark")
    b.yq(-0.05, -0.5, 0.5, 0.0, 2.2, 1, "WallC")
    b.yq(-0.045, -0.3, 0.3, 1.35, 1.9, 1, "Window")
    b.abox(-0.5, 0.5, -0.05, -0.01, 0.0, 0.3, "MetalDark", "-y")
    b.abox(0.3, 0.34, -0.05, 0.03, 0.95, 1.1, "Metal", "-y")
    b.abox(-0.8, 0.8, 0, 0.9, 0.0, 0.1, "Concrete", "-y -z")
    # canopy + lamp + number plate
    b.pq([(-0.8, 0.0, 2.75), (0.8, 0.0, 2.75), (0.8, 0.8, 2.55), (-0.8, 0.8, 2.55)], (0, 0.2, 1), "Metal")
    b.pq([(-0.8, 0.0, 2.7), (0.8, 0.0, 2.7), (0.8, 0.8, 2.5), (-0.8, 0.8, 2.5)], (0, -0.2, -1), "MetalDark")
    b.abox(-0.8, 0.8, 0.78, 0.82, 2.5, 2.58, "Metal", "-y")
    b.abox(0.6, 0.9, 0.0, 0.14, 2.9, 3.1, "LampGlow", "-y")
    b.abox(-0.2, 0.2, 0.09, 0.12, 3.2, 3.4, "Plate", "-y")
    i_columns(b)
    i_top(b)


def ind_loading_dock(b):
    DK = (-1.4, 1.4, 1.2, 4.2)
    b.abox(-2.0, 2.0, 0, 0.14, 0, 1.2, "Concrete", "-y -x +x -z")
    corr(b, -2.0, -1.6, 1.2, IH - 0.3, pitch=0.2)
    corr(b, 1.6, 2.0, 1.2, IH - 0.3, pitch=0.2)
    corr(b, -1.6, 1.6, 4.55, IH - 0.3)
    # dock shelter (rubber seal) around the opening
    b.abox(-1.6, -1.4, -0.02, 0.4, 1.2, 4.35, "Trim", "-y -z")
    b.abox(1.4, 1.6, -0.02, 0.4, 1.2, 4.35, "Trim", "-y -z")
    b.abox(-1.6, 1.6, -0.02, 0.4, 4.2, 4.4, "Trim", "-y -z")
    # sectional door
    b.yq(-0.14, DK[0], DK[1], DK[2], DK[3], 1, "WallD")
    for k in range(1, 6):
        z = DK[2] + k * 0.5
        b.yq(-0.13, DK[0], DK[1], z, z + 0.03, 1, "MetalDark")
    for k in range(4):
        x = -1.05 + k * 0.7
        b.yq(-0.125, x, x + 0.45, 3.1, 3.5, 1, "Window")
    b.reveal_y(DK, 0.0, -0.14, "MetalDark", "lrt")
    # leveler plate + bumpers + guard posts
    b.abox(-1.2, 1.2, -0.12, 0.55, 1.12, 1.2, "Metal", "-y")
    for x in (-1.7, 1.7):
        b.abox(x - 0.14, x + 0.14, 0.4, 0.62, 0.95, 1.55, "Trim", "-y")
    for x in (-1.0, 1.0):
        b.cylk((x, 1.5, 0.55), 0.11, 1.1, 8, "Accent", axis="Z")
    b.abox(-0.2, 0.2, 0.0, 0.25, 4.95, 5.2, "LampGlow", "-y")
    b.abox(1.65, 1.85, 0.4, 0.5, 2.6, 3.0, "Trim", "-y")
    i_top(b)


def ind_corner(b):
    i_plinth(b, -2.0, 2.0)
    corr(b, -2.0, 1.5, PL, IH - 0.3)
    pts = [(1.5, 0.0), (2.0, 0.0), (2.0, -1.0), (2.14, -1.0), (2.14, 0.14), (1.5, 0.14)]
    b.ez(pts, PL, IH - 0.3, "MetalDark", caps=(False, False), skip_edges=(0, 1))
    b.abox(2.0, 2.12, -1.0, 0.12, 0, PL, "Concrete", "-y -z")
    b.abox(-2.0, 2.14, 0, 0.16, IH - 0.3, IH, "Metal", "-y -x -z")
    b.abox(2.0, 2.16, -1.0, 0.0, IH - 0.3, IH, "Metal", "-y -x -z")
    b.abox(-2.0, -1.88, 0, 0.13, PL, IH - 0.3, "MetalDark", "-y -x -z")
    b.cylk((-1.6, 0.18, 3.0), 0.05, 6.0, 6, "Metal", axis="Z", caps=False)               # downspout
    for z in (1.0, 3.0, 5.0):
        b.abox(-1.68, -1.52, 0.0, 0.2, z - 0.03, z + 0.03, "Trim", "-y")


def ind_roof_sawtooth_bay(b):
    P = [(-12.0, -0.3), (0.0, -0.3), (0.0, 0.0), (-0.9, 0.0), (-0.9, 1.5), (-4.0, 0.0), (-4.9, 0.0), (-4.9, 1.5), (-8.0, 0.0),
         (-8.9, 0.0), (-8.9, 1.5), (-12.0, 0.0)]
    mats = {0: "WallA", 1: "Trim", 2: "Roof", 3: "Window", 4: "Roof", 5: "Roof", 6: "Window", 7: "Roof", 8: "Roof", 9: "Window",
            10: "Roof", 11: "WallA"}
    b.ex(P, -2, 2, "Roof", skip_edges=(0,), mats=mats)
    for yg in (-0.9, -4.9, -8.9):
        for x in (-1.5, -0.5, 0.5, 1.5):
            b.abox(x - 0.03, x + 0.03, yg, yg + 0.04, 0.0, 1.5, "Trim", "-y -z +z")
        b.abox(-2, 2, yg, yg + 0.05, 1.42, 1.5, "Trim", "-y -x +x")
        b.abox(-2, 2, yg, yg + 0.05, 0.0, 0.08, "Trim", "-y -x +x -z")
        b.abox(-2, 2, yg - 0.05, yg + 0.1, 1.5, 1.58, "Metal", "-y -x +x -z")           # ridge flashing


def ind_roof_flat_edge(b):
    P = [(-4.0, -0.2), (0.1, -0.2), (0.1, 0.55), (0.18, 0.55), (0.18, 0.66), (-0.15, 0.66), (-0.15, 0.0), (-4.0, 0.0)]
    mats = {1: "WallA", 2: "WallD", 3: "WallD", 4: "WallD", 5: "WallA", 6: "Roof", 7: "WallA", 0: "Trim"}
    b.ex(P, -2, 2, "Roof", skip_edges=(0,), mats=mats)
    # skylight, vents, drain, scupper + downspout
    b.abox(-1.2, 0.0, -2.8, -1.6, 0.0, 0.25, "Trim", "-z +z")
    b.abox(-1.1, -0.1, -2.7, -1.7, 0.25, 0.3, "Window", "-z")
    b.cylk((1.0, -1.0, 0.22), 0.16, 0.44, 8, "Metal", axis="Z", caps=False)
    b.cylk((1.0, -1.0, 0.46), 0.28, 0.06, 8, "MetalDark", axis="Z", r_top=0.05)
    b.cylk((1.2, -2.6, 0.06), 0.25, 0.12, 8, "MetalDark", axis="Z")
    b.abox(1.4, 1.95, 0.02, 0.2, 0.4, 0.6, "Metal", "-y -z")
    b.cylk((1.7, 0.24, -1.4), 0.07, 3.3, 6, "Metal", axis="Z", caps=False)
    for z in (-2.8, -0.2):
        b.abox(1.62, 1.78, 0.1, 0.26, z - 0.03, z + 0.03, "Trim", "-y")


def ind_pipe_run(b):
    for x in (-1.7, -0.5, 0.7, 1.7):
        b.abox(x - 0.06, x + 0.06, 0.0, 0.5, 2.78, 3.5, "Trim", "-y")
    b.cylk((0, 0.28, 3.0), 0.14, 4.0, 8, "Accent", axis="X")
    b.cylk((0, 0.28, 3.4), 0.09, 4.0, 8, "Metal", axis="X")
    for x in (-1.0, 0.3, 1.4):
        b.cylk((x, 0.28, 3.0), 0.19, 0.05, 8, "MetalDark", axis="X")
    for x in (-1.5, 1.2):
        b.cylk((x, 0.28, 3.4), 0.14, 0.05, 8, "MetalDark", axis="X")
    # riser
    b.cylk((1.7, 0.28, 4.4), 0.09, 2.2, 8, "Metal", axis="Z", caps=False)
    b.cylk((1.7, 0.28, 3.6), 0.14, 0.05, 8, "MetalDark", axis="Z")
    # valve wheel
    b.cylk((-0.2, 0.28, 3.34), 0.06, 0.2, 6, "MetalDark", axis="Z")
    b.cylk((-0.2, 0.28, 3.5), 0.15, 0.03, 8, "Accent", axis="Z")


def ind_silo_small(b):
    R, H0, H1 = 1.55, 1.7, 7.5
    SG = 12
    b.cylk((0, 0, (H0 + H1) / 2), R, H1 - H0, SG, "WallD", axis="Z", caps=False)
    for z in (3.6, 5.8):
        b.cylk((0, 0, z), R + 0.04, 0.08, SG, "Metal", axis="Z", caps=False)
    b.cylk((0, 0, H0 - 0.5), 0.28, 1.0, SG, "WallD", axis="Z", r_top=R, caps=False)     # hopper (narrow at bottom)
    b.cylk((0, 0, H1 + 0.55), R, 1.1, SG, "Roof", axis="Z", r_top=0.2, caps=False)
    b.cylk((0, 0, H1 + 1.2), 0.2, 0.3, 8, "Metal", axis="Z")
    # legs + bracing
    for k in range(4):
        a = math.radians(45 + 90 * k)
        b.beamk((math.cos(a) * 1.3, math.sin(a) * 1.3, 0.0), (math.cos(a) * 1.2, math.sin(a) * 1.2, H0), 0.07, 0.06, 4, "MetalDark", False)
        b.abox(math.cos(a) * 1.3 - 0.15, math.cos(a) * 1.3 + 0.15, math.sin(a) * 1.3 - 0.15, math.sin(a) * 1.3 + 0.15, 0, 0.08, "Concrete", "-z")
    for k in range(4):
        a0, a1 = math.radians(45 + 90 * k), math.radians(45 + 90 * (k + 1))
        b.beamk((math.cos(a0) * 1.3, math.sin(a0) * 1.3, 0.1), (math.cos(a1) * 1.2, math.sin(a1) * 1.2, H0 - 0.1), 0.02, 0.02, 3, "Metal", False)
    # ladder with cage, front (+Y)
    for sx in (-0.2, 0.2):
        b.beamk((sx, R + 0.15, 0.4), (sx, R + 0.15, H1 + 0.4), 0.02, 0.02, 3, "Metal", False)
    for k in range(10):
        z = 0.6 + k * 0.72
        b.beamk((-0.2, R + 0.15, z), (0.2, R + 0.15, z), 0.014, 0.014, 3, "Metal", False)
    for z in (4.4, 6.4):
        b.cylk((0, R + 0.15, z), 0.33, 0.04, 6, "MetalDark", axis="Z", caps=False)
    # top catwalk ring + rail
    b.abox(-0.3, 0.3, R, R + 0.25, 1.9, 2.3, "Trim", "-z")                                  # outlet box


def ind_tank(b):
    R, H = 2.4, 5.0
    b.cylk((0, 0, H / 2 + 0.3), R, H, 12, "WallD", axis="Z", caps=False)
    b.cylk((0, 0, 0.15), R + 0.2, 0.3, 12, "Concrete", axis="Z")
    for z in (1.8, 4.2):
        b.cylk((0, 0, z), R + 0.04, 0.1, 12, "Metal", axis="Z", caps=False)
    b.cylk((0, 0, H + 0.3 + 0.18), R, 0.36, 12, "Roof", axis="Z", r_top=R * 0.55, caps=True)
    b.cylk((0, 0, H + 0.3 + 0.45), 0.5, 0.16, 6, "MetalDark", axis="Z")
    # top rail
    n = 6
    for k in range(n):
        a = 2 * math.pi * k / n
        x, y = math.cos(a) * (R * 0.98), math.sin(a) * (R * 0.98)
        b.beamk((x, y, H + 0.3), (x, y, H + 1.2), 0.025, 0.025, 3, "Metal", False)
        a2 = 2 * math.pi * (k + 1) / n
        x2, y2 = math.cos(a2) * (R * 0.98), math.sin(a2) * (R * 0.98)
        b.beamk((x, y, H + 1.2), (x2, y2, H + 1.2), 0.02, 0.02, 3, "Metal", False)
    # ladder front
    for sx in (-0.25, 0.25):
        b.beamk((sx, R + 0.15, 0.3), (sx, R + 0.15, H + 0.5), 0.02, 0.02, 3, "Metal", False)
    for k in range(6):
        z = 0.6 + k * 0.85
        b.beamk((-0.25, R + 0.15, z), (0.25, R + 0.15, z), 0.014, 0.014, 3, "Metal", False)
    # base pipework + manhole
    b.cylk((R + 0.4, 0.0, 0.8), 0.12, 1.0, 6, "Accent", axis="Z", caps=False)
    b.cylk((R + 0.1, 0.0, 1.25), 0.12, 0.5, 6, "Accent", axis="X", caps=False)
    b.cylk((R + 0.5, 0.0, 0.3), 0.2, 0.1, 6, "MetalDark", axis="Z")
    b.cylk((-R - 0.06, 0.0, 1.2), 0.38, 0.12, 6, "Metal", axis="X")


K = Kit("kit_industrial", 4)
K.add("Ind_Wall_Corrugated", ind_wall_corrugated)
K.add("Ind_Wall_Windows_Band", ind_wall_windows_band)
K.add("Ind_Door_Roller", ind_door_roller)
K.add("Ind_Door_Man", ind_door_man)
K.add("Ind_Loading_Dock", ind_loading_dock)
K.add("Ind_Corner", ind_corner)
K.add("Ind_Roof_Sawtooth_Bay", ind_roof_sawtooth_bay)
K.add("Ind_Roof_Flat_Edge", ind_roof_flat_edge)
K.add("Ind_Pipe_Run", ind_pipe_run)
K.add("Ind_Silo_Small", ind_silo_small, width=4.0, smooth=32)
K.add("Ind_Tank", ind_tank, width=6.0, smooth=32)
K.report()

if globals().get("EXPORT_KITS", False):
    K.export("buildings/kit_industrial")
