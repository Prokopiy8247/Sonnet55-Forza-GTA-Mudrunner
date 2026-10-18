"""lane 9 - street props batch 1: traffic_light, street_lamp, stop_sign, road_cone, trash_bin, bench, fire_hydrant, bus_stop.
Run after gta_lib.py + lane9_lib.py.  Each b_<id>() is idempotent (clear_asset first) and returns the A9 asset."""
G = "PoleGreen"


# ------------------------------------------------------------------------------------------------ lamps
def lamp_unit(b, g, pole_top, arm_R, arm_len, tube_r, head_L, head_W, head_H, tube_r_end=None):
    """Curved lamp arm (towards +Y) + cobra head. b = body builder, g = glow (LampHead) builder."""
    zt = pole_top + arm_R
    pts = [(0, 0, pole_top - 0.3)]
    for a in (180, 150, 120, 90):
        pts.append((0, arm_R + arm_R * math.cos(math.radians(a)), pole_top + arm_R * math.sin(math.radians(a))))
    pts.append((0, arm_len, zt))
    sweep(b, pts, tube_r, 6, G, r_end=tube_r_end or tube_r * 0.8)
    cy = arm_len - head_L * 0.18
    z0 = zt - head_H * 0.6
    z1 = zt + head_H * 0.4
    # housing: tapered shell + roof ridge + rear cap
    b.block((0, cy), z0, z1, (head_W, head_L), (head_W * 0.72, head_L * 0.86), "PoleGrey", top_shift=(0, head_L * 0.03))
    b.block((0, cy - head_L * 0.02), z1, z1 + head_H * 0.28, (head_W * 0.72, head_L * 0.86), (head_W * 0.4, head_L * 0.6), "PoleGreen", top_shift=(0, -head_L * 0.04))
    # rim ring under housing + lens bowl
    b.block((0, cy), z0 - 0.012, z0, (head_W * 0.96, head_L * 0.96), None, "MetalDark")
    g.block((0, cy), z0 - 0.05, z0 - 0.012, (head_W * 0.6, head_L * 0.8), (head_W * 0.86, head_L * 0.92), "LampGlow")
    return (0.0, cy, z0 - 0.05)


def b_street_lamp():
    a = new_asset("street_lamp", 1)
    b, g = a.mb(), a.mb("LampHead")
    cylz(b, 0, 0, 0, 0.10, 0.25, 8, "ConcreteDark", r1=0.2, rot=22.5)
    cylz(b, 0, 0, 0.10, 0.66, 0.15, 8, G, r1=0.10, rot=22.5)
    cylz(b, 0, 0, 0.62, 0.70, 0.125, 8, "MetalDark", rot=22.5)
    cylz(b, 0, 0, 0.70, 6.75, 0.092, 8, G, r1=0.058, rot=22.5)
    for z, r in ((2.6, 0.082), (4.9, 0.07)):                                              # decorative collars
        cylz(b, 0, 0, z, z + 0.08, r + 0.018, 8, "MetalDark", rot=22.5)
    bx(b, (-0.05, 0.05), (0.118, 0.135), (0.22, 0.52), "MetalDark")                         # service hatch
    cylz(b, 0, 0, 6.75, 6.85, 0.07, 8, "MetalDark", r1=0.052, rot=22.5)
    pos = lamp_unit(b, g, 6.75, 0.62, 2.0, 0.052, 0.9, 0.36, 0.2)
    a.fin(b, "Body", smooth=None)
    a.fin(g, "LampHead")
    a.mark("LightPoint", (pos[0], pos[1], pos[2] - 0.05))
    return a


def b_street_lamp_double():
    a = new_asset("street_lamp_double", 8)
    b, g = a.mb(), a.mb("LampHead")
    with xf(b, RZ(-90)), xf(g, RZ(-90)):                   # build arm towards +Y, then swing it onto +X
        pos = lamp_unit(b, g, 6.7, 0.6, 1.9, 0.05, 0.9, 0.36, 0.2)
    b.mirror_x()
    g.mirror_x()
    cylz(b, 0, 0, 0, 0.10, 0.25, 8, "ConcreteDark", r1=0.2, rot=22.5)
    cylz(b, 0, 0, 0.10, 0.66, 0.15, 8, G, r1=0.10, rot=22.5)
    cylz(b, 0, 0, 0.62, 0.70, 0.125, 8, "MetalDark", rot=22.5)
    cylz(b, 0, 0, 0.70, 6.72, 0.092, 8, G, r1=0.06, rot=22.5)
    cylz(b, 0, 0, 6.72, 6.8, 0.075, 8, "MetalDark", r1=0.055, rot=22.5)
    a.fin(b, "Body")
    a.fin(g, "LampHead")
    a.mark("LightPointR", (pos[1], 0.0, pos[2] - 0.05))
    a.mark("LightPointL", (-pos[1], 0.0, pos[2] - 0.05))
    return a


# ------------------------------------------------------------------------------------------------ traffic light
def sig_head(b, r, am, gr, cx, cy, cz, visors=True):
    H, W, D = 1.12, 0.40, 0.28
    bx(b, (cx - W / 2, cx + W / 2), (cy - D / 2, cy + D / 2), (cz - H / 2, cz + H / 2), "PaintYellow")
    bx(b, (cx - 0.31, cx + 0.31), (cy + 0.015, cy + 0.04), (cz - 0.72, cz + 0.72), "Trim")
    for mb_, dz in ((r, 0.36), (am, 0.0), (gr, -0.36)):
        mat_name = {id(r): "SignalRed", id(am): "SignalAmber", id(gr): "SignalGreen"}[id(mb_)]
        cyly(mb_, cx, cy + 0.13, cy + 0.19, cz + dz, 0.125, 8, mat_name, r1=0.105)
        if visors:
            zl = cz + dz
            with xf(b, about((cx, cy + 0.08, zl + 0.165), RX(-12))):
                bx(b, (cx - 0.15, cx + 0.15), (cy + 0.08, cy + 0.42), (zl + 0.155, zl + 0.172), "Trim")


def b_traffic_light():
    a = new_asset("traffic_light", 0)
    b = a.mb()
    r, am, gr = a.mb("SignalRed"), a.mb("SignalAmber"), a.mb("SignalGreen")
    cylz(b, 0, 0, 0, 0.12, 0.26, 8, "ConcreteDark", r1=0.2, rot=22.5)
    cylz(b, 0, 0, 0.12, 0.75, 0.15, 8, "PoleGrey", r1=0.115, rot=22.5)
    cylz(b, 0, 0, 0.75, 5.78, 0.11, 8, "PoleGrey", r1=0.08, rot=22.5)
    cylz(b, 0, 0, 5.78, 5.9, 0.085, 8, "MetalDark", r1=0.05, rot=22.5)
    # mast arm (rises gently towards the road, +X)
    sweep(b, [(0.0, 0, 5.52), (1.6, 0, 5.66), (3.4, 0, 5.82), (5.0, 0, 5.98)], 0.075, 6, "PoleGrey", r_end=0.045)
    b.beam((0.08, 0, 4.85), (1.5, 0, 5.62), 0.028, 0.028, 4, "PoleGrey", False)         # gusset brace
    # main head hangs at x=4.2
    bx(b, (4.17, 4.23), (-0.03, 0.03), (5.66, 5.9), "MetalDark")
    sig_head(b, r, am, gr, 4.2, 0.0, 5.08)
    # pole mounted near-side head (top at ~3.5 m)
    bx(b, (-0.04, 0.04), (0.09, 0.2), (2.15, 3.35), "MetalDark")
    sig_head(b, r, am, gr, 0.0, 0.3, 2.78, visors=False)
    a.fin(b, "Body")
    a.fin(r, "SignalRed")
    a.fin(am, "SignalAmber")
    a.fin(gr, "SignalGreen")
    return a


# ------------------------------------------------------------------------------------------------ stop sign
def b_stop_sign():
    a = new_asset("stop_sign", 2)
    b = a.mb()
    cylz(b, 0, 0, 0, 0.05, 0.1, 6, "PoleGrey", r1=0.07)
    cylz(b, 0, 0, 0.05, 2.62, 0.035, 6, "PoleGrey")
    bx(b, (-0.025, 0.025), (0.035, 0.05), (1.85, 2.45), "PoleGrey")                      # bracket strip
    zc = 2.15
    R = 0.375 / math.cos(math.radians(22.5))
    oct_ = ngon(8, R, 0, zc, 22.5)
    ext(b, oct_, "xz", 0.05, 0.068, "PlateWhite")
    ext(b, ngon(8, R * 0.92, 0, zc, 22.5), "xz", 0.068, 0.076, "PlateRed")
    # stylised lettering "STOP" - viewer (at +Y looking -Y) sees +X on the LEFT, so letters run towards -X
    xs = (0.2, 0.065, -0.07, -0.205)
    for x in xs:
        bx(b, (x - 0.055, x + 0.055), (0.076, 0.084), (zc - 0.07, zc + 0.07), "PlateWhite")

    def notch(xc, u0, u1, z0, z1):
        bx(b, (xc + 0.055 - u1, xc + 0.055 - u0), (0.084, 0.088), (zc + z0, zc + z1), "PlateRed")
    notch(xs[0], 0.035, 0.11, 0.012, 0.04)          # S: upper right gap
    notch(xs[0], 0.0, 0.075, -0.04, -0.012)         # S: lower left gap
    notch(xs[1], 0.0, 0.037, -0.072, 0.03)          # T
    notch(xs[1], 0.073, 0.11, -0.072, 0.03)
    notch(xs[2], 0.035, 0.075, -0.035, 0.035)       # O hole
    notch(xs[3], 0.035, 0.075, -0.0, 0.035)         # P bowl hole
    notch(xs[3], 0.035, 0.11, -0.072, -0.03)        # P lower right
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ road cone
def b_road_cone():
    a = new_asset("road_cone", 3)
    b = a.mb()
    cbox(b, (-0.19, 0.19), (-0.19, 0.19), (0.0, 0.04), 0.07, "TireRubber")
    R0, R1, z0, z1 = 0.145, 0.034, 0.04, 0.70

    def rad(z):
        return R0 + (R1 - R0) * (z - z0) / (z1 - z0)
    bands = [(0.04, 0.30, "ConeOrange"), (0.30, 0.40, "PlateWhite"), (0.40, 0.48, "ConeOrange"), (0.48, 0.58, "PlateWhite"), (0.58, 0.70, "ConeOrange")]
    for lo, hi, m in bands:
        grow = 0.004 if m == "PlateWhite" else 0.0
        cylz(b, 0, 0, lo, hi, rad(lo) + grow, 8, m, r1=rad(hi) + grow, caps=(lo == 0.04), rot=22.5)
    cylz(b, 0, 0, 0.70, 0.705, 0.034, 8, "ConeOrange", rot=22.5)
    a.fin(b, "Body", smooth=40)
    return a


# ------------------------------------------------------------------------------------------------ trash bin
def b_trash_bin():
    a = new_asset("trash_bin", 4)
    b = a.mb()
    cylz(b, 0, 0, 0.0, 0.07, 0.25, 8, "MetalDark", r1=0.24, rot=22.5)
    cylz(b, 0, 0, 0.07, 0.86, 0.235, 8, "BinGreen", r1=0.265, rot=22.5)
    for z0 in (0.20, 0.66):
        cylz(b, 0, 0, z0, z0 + 0.045, 0.248 + (z0 - 0.07) * 0.038, 8, "MetalDark", r1=0.252 + (z0 - 0.07) * 0.038, rot=22.5)
    cylz(b, 0, 0, 0.86, 0.90, 0.285, 8, "PoleGrey", rot=22.5)
    cylz(b, 0, 0, 0.90, 1.0, 0.27, 8, "PoleGrey", r1=0.16, rot=22.5)
    # dark opening on the lid top (+Y half) and a vertical label strip on the front
    bx(b, (-0.10, 0.10), (0.01, 0.13), (1.0, 1.012), "Trim")
    bx(b, (-0.12, 0.12), (0.262, 0.272), (0.50, 0.60), "Trim")
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ bench
def b_bench():
    a = new_asset("bench", 5)
    b = a.mb()
    tilt = math.radians(8)
    for sx in (-1, 1):
        x = 0.78 * sx
        b.beam((x, 0.21, 0.0), (x, 0.21, 0.46), 0.03, 0.03, 4, "MetalDark", True)                # front leg
        b.beam((x, -0.24, 0.0), (x, -0.26, 0.46), 0.03, 0.03, 4, "MetalDark", True)               # rear leg
        b.beam((x, -0.26, 0.45), (x, -0.26 - 0.42 * math.tan(tilt), 0.87), 0.03, 0.03, 4, "MetalDark", True)   # back post
        b.beam((x, -0.26, 0.44), (x, 0.24, 0.44), 0.026, 0.026, 4, "MetalDark", True)              # seat rail
        b.beam((x, 0.19, 0.46), (x, 0.19, 0.64), 0.025, 0.025, 4, "MetalDark", True)               # arm post
        bx(b, (x - 0.035, x + 0.035), (-0.27, 0.26), (0.63, 0.67), "PoleGreen")                    # armrest
        bx(b, (x - 0.04, x + 0.04), (0.17, 0.25), (0.0, 0.02), "MetalDark")                        # feet
        bx(b, (x - 0.04, x + 0.04), (-0.28, -0.20), (0.0, 0.02), "MetalDark")
    b.beam((0, 0.21, 0.0), (0, 0.21, 0.44), 0.025, 0.025, 4, "MetalDark", True)
    b.beam((0, -0.24, 0.0), (0, -0.25, 0.44), 0.025, 0.025, 4, "MetalDark", True)
    for i, y in enumerate((0.18, 0.06, -0.06, -0.18)):
        bx(b, (-0.86, 0.86), (y - 0.05, y + 0.05), (0.465, 0.5), "WoodLight" if i % 2 == 0 else "WoodPale")
    with xf(b, about((0, -0.26, 0.45), RX(-8))):
        for i, z in enumerate((0.56, 0.69, 0.82)):
            bx(b, (-0.86, 0.86), (-0.325, -0.292), (z - 0.055, z + 0.055), "WoodLight" if i % 2 == 0 else "WoodPale")
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ fire hydrant
def b_fire_hydrant():
    a = new_asset("fire_hydrant", 6)
    b = a.mb()
    H, Y = "HydrantRed", "PaintYellow"
    cylz(b, 0, 0, 0.0, 0.07, 0.17, 8, "MetalDark", rot=22.5)
    cylz(b, 0, 0, 0.07, 0.50, 0.13, 8, H, r1=0.115, caps=False, rot=22.5)
    cylz(b, 0, 0, 0.47, 0.55, 0.15, 8, H, r1=0.15, rot=22.5)                           # collar ring
    cylz(b, 0, 0, 0.55, 0.64, 0.12, 8, H, r1=0.11, caps=False, rot=22.5)
    cylz(b, 0, 0, 0.64, 0.78, 0.115, 8, H, r1=0.045, caps=False, rot=22.5)                         # dome
    cylz(b, 0, 0, 0.78, 0.84, 0.06, 6, Y, r1=0.05)
    cylz(b, 0, 0, 0.84, 0.89, 0.04, 6, "MetalDark", caps=True)
    for sx in (-1, 1):                                                                 # side nozzles
        cylx(b, sx * 0.08, sx * 0.24, 0, 0.49, 0.055, 6, H)
        cylx(b, sx * 0.24, sx * 0.275, 0, 0.49, 0.068, 6, Y)
    cyly(b, 0, 0.08, 0.27, 0.40, 0.08, 8, H)                                           # pumper nozzle
    cyly(b, 0, 0.27, 0.315, 0.40, 0.095, 8, Y)
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ bus stop
def b_bus_stop():
    a = new_asset("bus_stop", 7)
    b = a.mb()
    F = "PoleGreen"
    # posts (back x4, front x2)
    for x in (-2.0, -0.67, 0.67, 2.0):
        bx(b, (x - 0.045, x + 0.045), (-0.78, -0.69), (0.0, 2.5), F)
    for x in (-1.95, 1.95):
        bx(b, (x - 0.05, x + 0.05), (0.62, 0.72), (0.0, 2.5), F)
    # back glass (3 panels) + rail strips
    bx(b, (-1.96, 1.96), (-0.74, -0.72), (0.3, 2.42), "Glass")
    bx(b, (-2.0, 2.0), (-0.79, -0.68), (0.0, 0.3), F)                                   # kick panel
    # left end glass
    bx(b, (-1.98, -1.96), (-0.68, 0.62), (0.3, 2.42), "Glass")
    # right end: advert light box (double sided)
    bx(b, (1.94, 2.06), (-0.62, 0.52), (0.35, 2.4), "MetalDark")
    bx(b, (2.06, 2.075), (-0.56, 0.46), (0.45, 2.3), "NeonAd")
    bx(b, (1.925, 1.94), (-0.56, 0.46), (0.45, 2.3), "NeonAd")
    # roof: slight slope to the back, front fascia band
    with xf(b, about((0, 0, 2.55), RX(2.5))):
        bx(b, (-2.25, 2.25), (-0.95, 0.98), (2.5, 2.6), "Roof")
    bx(b, (-2.27, 2.27), (0.93, 1.0), (2.46, 2.66), "PlateBlue")
    # bench against the back glass
    bx(b, (-1.2, 1.2), (-0.58, -0.2), (0.45, 0.5), "WoodLight")
    for x in (-1.1, 1.1):
        bx(b, (x - 0.04, x + 0.04), (-0.56, -0.24), (0.0, 0.45), "MetalDark")
    bx(b, (-1.2, 1.2), (-0.66, -0.62), (0.52, 0.85), "WoodPale")
    # route sign pole with blue plate + white bus pictogram, outside the shelter
    cylz(b, 2.75, 0.2, 0.0, 3.05, 0.03, 6, "PoleGrey")
    bx(b, (2.55, 2.95), (0.17, 0.2), (2.55, 2.95), "PlateBlue")
    bx(b, (2.62, 2.88), (0.2, 0.208), (2.64, 2.8), "PlateWhite")
    for wx in (2.68, 2.82):
        bx(b, (wx - 0.025, wx + 0.025), (0.2, 0.214), (2.6, 2.65), "Trim")
    a.fin(b, "Body")
    return a
