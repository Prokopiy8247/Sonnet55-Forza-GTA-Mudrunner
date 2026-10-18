"""lane13 misc A: rocket (weapons/rocket), shell_casing, race_checkpoint (ring), finish_line_banner (gate), stunt_ramp_sign."""


def build_rocket():
    A = A13("rocket", 104, "GTA_GODOT/Weapons", spacing=8.0)
    b = HB("rocket_body")
    # (axial y, radius) outline front -> rear ; segments: nose cone, collar, hazard ring, body, taper, bell, rim, nozzle interior
    prof = [(0.50, 0.0), (0.29, 0.058), (0.24, 0.058), (0.20, 0.058), (-0.36, 0.058), (-0.38, 0.049), (-0.50, 0.070), (-0.50, 0.046), (-0.44, 0.0)]
    mats = ["RocketOrange", "RocketOrange", "Hazard", "Rocket", "Rocket", "MetalDark", "MetalDark", "Trim"]
    b.lathe(prof, (0, 0, 0), 8, "Rocket", axis="Y", rot=math.radians(22.5), mats=mats)
    b.cyl((0, 0.50, 0), 0.012, 0.03, 6, "Chrome", axis="Y", caps="t")                       # nose tip probe
    for ang in (0, 90, 180, 270):                                                           # main fins
        with xf(b, RY(ang)):
            b.ex([(-0.17, 0.052), (-0.47, 0.052), (-0.51, 0.19), (-0.34, 0.19)], -0.008, 0.008, "RocketOrange")
    for ang in (45, 135, 225, 315):                                                         # small canards near the nose
        with xf(b, RY(ang)):
            b.ex([(0.17, 0.056), (0.09, 0.056), (0.11, 0.115), (0.16, 0.115)], -0.006, 0.006, "Rocket")
    A.mesh(b, "Body", uv=None)
    f = HB("rocket_flame")
    f.lathe([(-0.49, 0.046), (-0.60, 0.064), (-0.93, 0.0)], (0, 0, 0), 8, "Flame", axis="Y", rot=math.radians(22.5))
    f.lathe([(-0.49, 0.026), (-0.66, 0.036), (-1.02, 0.0)], (0, 0, 0), 6, "Flame", axis="Y")
    A.mesh(f, "Flame", uv=None)
    A.mark("Exhaust", (0, -0.5, 0), rot=(0, 0, 0), size=0.06)
    A.mark("Tip", (0, 0.5, 0), size=0.05)
    return A


def build_shell_casing():
    A = A13("shell_casing", 105, "GTA_GODOT/StreetProps", spacing=8.0)
    b = HB("shell_casing_body")
    # 9 mm brass case lying along +Y (mouth towards +Y), 19 mm long, 9.9 mm wide
    prof = [(0.0095, 0.0), (0.0095, 0.0049), (0.0075, 0.0049), (-0.0075, 0.0048), (-0.0095, 0.0053), (-0.0095, 0.0), (-0.0095, 0.0)]
    b.lathe(prof[:-1], (0, 0, 0.0051), 8, "Brass", axis="Y", mats=["Trim", "Brass", "Brass", "Brass", "Metal"])
    b.cyl((0, -0.0096, 0.0051), 0.0022, 0.0006, 6, "Chrome", axis="Y", caps="b")
    A.mesh(b, "Body", uv=None)
    return A


def build_race_checkpoint():
    A = A13("race_checkpoint", 106, "GTA_GODOT/StreetProps", spacing=10.0)
    R, r = 3.0, 0.12
    zc = R + r
    ring = HB("race_checkpoint_ring")
    ring.torus((0, 0, zc), R, r, seg=28, tseg=4, m="RingGlow", axis="Y", rot=0.0, tphase=math.pi / 4)
    # tick marks at the cardinal points + four chevron arrows pointing along the driving direction (+Y)
    for ang in range(0, 360, 45):
        ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        ring.cyl((ca * (R - 0.35), 0.0, zc + sa * (R - 0.35)), 0.03, 0.4, 4, "RingGlow", axis="Y")
    A.mesh(ring, "Ring", uv=None)
    b = HB("race_checkpoint_base")
    for sx in (-1, 1):
        b.abox(sx * R - 0.35, sx * R + 0.35, -0.3, 0.3, 0.0, 0.08, "MetalDark")
        b.abox(sx * R - 0.18, sx * R + 0.18, -0.12, 0.12, 0.08, 0.16, "Metal")
        b.zq(0.081, sx * R - 0.3, sx * R + 0.3, -0.25, -0.2, 1, "NeonCyan")
        b.zq(0.081, sx * R - 0.3, sx * R + 0.3, 0.2, 0.25, 1, "NeonCyan")
    A.mesh(b, "Body", uv=None)
    A.mark("Centre", (0, 0, zc), size=0.3)
    return A


def build_finish_line_banner():
    A = A13("finish_line_banner", 107, "GTA_GODOT/StreetProps", spacing=16.0)
    b = HB("finish_line_banner_body")
    H = 6.0
    # posts (square tubes) with hazard base bands and footing plates
    for sx in (-6.0, 6.0):
        b.abox(sx - 0.7, sx + 0.7, -0.6, 0.6, 0.0, 0.12, "ConcreteDk", "-z")
        b.abox(sx - 0.2, sx + 0.2, -0.2, 0.2, 0.12, H + 0.9, "MetalDark")
        b.abox(sx - 0.22, sx + 0.22, -0.22, 0.22, 0.12, 0.9, "Hazard", "-z +z")
        b.abox(sx - 0.26, sx + 0.26, -0.26, 0.26, H + 0.9, H + 1.0, "Metal")
        # diagonal braces
        s = -1 if sx > 0 else 1
        b.rbeam((sx + s * 0.2, 0.0, H - 1.0), (sx + s * 1.5, 0.0, H + 0.05), 0.14, 0.07, "MetalDark", up=(0, 1, 0))
    # banner box + chequered cells (both faces) + neon lines
    zb0, zb1 = H + 0.05, H + 0.95
    b.abox(-6.2, 6.2, -0.12, 0.12, zb0, zb1, "ChequerBlack")
    cells, rows = 24, 2
    cw = 12.4 / cells
    ch = (zb1 - zb0) / rows
    for r_ in range(rows):
        for c_ in range(cells):
            if (r_ + c_) % 2 == 0:
                x0 = -6.2 + c_ * cw
                z0 = zb0 + r_ * ch
                b.yq(0.122, x0, x0 + cw, z0, z0 + ch, 1, "ChequerWhite")
                b.yq(-0.122, x0, x0 + cw, z0, z0 + ch, -1, "ChequerWhite")
    for (z0, z1, m) in ((zb1 + 0.03, zb1 + 0.1, "NeonCyan"), (zb0 - 0.1, zb0 - 0.03, "Neon")):
        b.abox(-6.25, 6.25, -0.14, 0.14, z0, z1, m)
    b.abox(-6.3, 6.3, -0.16, 0.16, zb1 + 0.1, zb1 + 0.16, "MetalDark")
    # neon arch above the banner (12 m chord, 1.4 m rise) with struts down to the banner
    Rr = (6.0 ** 2 + 1.4 ** 2) / (2 * 1.4)
    pts = []
    for i in range(11):
        x = -6.0 + 12.0 * i / 10
        pts.append((x, 0.0, zb1 + 0.16 + math.sqrt(max(Rr * Rr - x * x, 0.0)) - (Rr - 1.4)))
    for i in range(10):
        b.beam(pts[i], pts[i + 1], 0.07, 0.07, 4, "NeonCyan", caps=False)
    for i in (1, 3, 5, 7, 9):
        b.beam((pts[i][0], 0.0, zb1 + 0.16), pts[i], 0.035, 0.035, 4, "MetalDark", caps=False)
    for sx in (-6.0, 6.0):
        b.beam((sx, 0.0, zb1 + 0.16), (sx, 0.0, pts[0][2]), 0.09, 0.09, 4, "MetalDark", caps=False)
    # gantry lamps under the banner
    for i in range(7):
        x = -5.1 + i * 1.7
        b.abox(x - 0.12, x + 0.12, -0.1, 0.1, zb0 - 0.22, zb0 - 0.1, "LampGlow", "+z")
    # start-light pods on the posts (red / amber / green)
    for sx in (-6.0, 6.0):
        for k, m in enumerate(("SignalRed", "SignalAmber", "SignalGreen")):
            b.yq(0.205, sx - 0.12, sx + 0.12, H - 2.5 + k * 0.45, H - 2.2 + k * 0.45, 1, m)
            b.yq(-0.205, sx - 0.12, sx + 0.12, H - 2.5 + k * 0.45, H - 2.2 + k * 0.45, -1, m)
    A.mesh(b, "Body", uv=None)
    A.mark("Line", (0, 0, 0.02), size=0.4)
    return A


def build_stunt_ramp_sign():
    A = A13("stunt_ramp_sign", 108, "GTA_GODOT/StreetProps", spacing=8.0)
    b = HB("stunt_ramp_sign_body")
    for sx in (-0.65, 0.65):
        b.abox(sx - 0.04, sx + 0.04, -0.14, -0.06, 0.0, 1.5, "MetalDark", "-z")
        b.abox(sx - 0.2, sx + 0.2, -0.4, 0.2, 0.0, 0.06, "ConcreteDk", "-z")
    b.abox(-0.69, 0.69, -0.075, -0.04, 0.78, 0.86, "MetalDark")                            # mounting rail behind the board
    b.abox(-0.69, 0.69, -0.075, -0.04, 1.58, 1.66, "MetalDark")
    b.abox(-0.95, 0.95, -0.04, 0.04, 0.7, 1.75, "Hazard")                                    # yellow board
    b.abox(-0.99, 0.99, -0.045, 0.045, 0.66, 0.7, "TargetBlack")
    b.abox(-0.99, 0.99, -0.045, 0.045, 1.75, 1.79, "TargetBlack")
    b.abox(-0.99, -0.95, -0.045, 0.045, 0.7, 1.75, "TargetBlack")
    b.abox(0.95, 0.99, -0.045, 0.045, 0.7, 1.75, "TargetBlack")
    for k in range(3):
        z0 = 0.80 + k * 0.30
        for (yf, s) in ((0.042, 1), (-0.042, -1)):
            pts = [(-0.55, yf, z0), (0.0, yf, z0 + 0.20), (0.55, yf, z0), (0.55, yf, z0 + 0.12), (0.0, yf, z0 + 0.32), (-0.55, yf, z0 + 0.12)]
            b.pq(pts, (0, s, 0), "TargetBlack")
    for sx in (-0.85, 0.85):                                                                   # corner reflectors / neon studs
        for z in (0.78, 1.67):
            b.cyl((sx, 0.045, z), 0.035, 0.012, 6, "NeonAmber", axis="Y", caps="t")
    A.mesh(b, "Body", uv=None)
    return A


A1 = build_rocket();           A1.report(300)
A2 = build_shell_casing();     A2.report(120)
A3 = build_race_checkpoint();  A3.report(400)
A4 = build_finish_line_banner(); A4.report(500)
A5 = build_stunt_ramp_sign();  A5.report(300)
