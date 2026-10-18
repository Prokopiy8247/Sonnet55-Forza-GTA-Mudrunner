"""lane 9 - street props batch 2: highway_lamp, traffic_light_ped, speed_sign, street_sign, bollard, concrete_barrier,
road_barrier, dumpster, utility_box, mailbox, parking_meter, phone_booth, newspaper_box.
Requires gta_lib.py, lane9_lib.py and lane9_street1.py (lamp_unit) to be loaded first."""
G = "PoleGreen"


def b_highway_lamp():
    a = new_asset("highway_lamp", 9)
    b, g = a.mb(), a.mb("LampHead")
    cylz(b, 0, 0, 0, 0.05, 0.40, 8, "ConcreteDark", rot=22.5)                      # base plate
    cylz(b, 0, 0, 0.05, 0.62, 0.27, 8, G, r1=0.18, rot=22.5)                       # flared cover
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx(b, (sx * 0.3 - 0.03, sx * 0.3 + 0.03), (sy * 0.3 - 0.03, sy * 0.3 + 0.03), (0.05, 0.1), "Metal")
    cylz(b, 0, 0, 0.62, 0.72, 0.19, 8, "MetalDark", rot=22.5)
    cylz(b, 0, 0, 0.72, 9.55, 0.16, 8, G, r1=0.092, rot=22.5)
    cylz(b, 0, 0, 9.55, 9.67, 0.11, 8, "MetalDark", r1=0.08, rot=22.5)
    pos = lamp_unit(b, g, 9.55, 1.15, 3.3, 0.085, 1.3, 0.5, 0.3)
    b.beam((0, 0.06, 8.7), (0, 2.0, 10.62), 0.035, 0.035, 4, "MetalDark", False)    # support strut
    a.fin(b, "Body")
    a.fin(g, "LampHead")
    a.mark("LightPoint", (pos[0], pos[1], pos[2] - 0.05))
    return a


def b_traffic_light_ped():
    a = new_asset("traffic_light_ped", 10)
    b = a.mb()
    r, gr = a.mb("SignalRed"), a.mb("SignalGreen")
    cylz(b, 0, 0, 0, 0.06, 0.2, 8, "ConcreteDark", r1=0.16, rot=22.5)
    cylz(b, 0, 0, 0.06, 3.0, 0.075, 8, "PoleGrey", r1=0.06, rot=22.5)
    cylz(b, 0, 0, 3.0, 3.07, 0.07, 8, "MetalDark", r1=0.03, rot=22.5)
    # signal head (faces +Y)
    bx(b, (-0.19, 0.19), (0.03, 0.30), (2.28, 2.88), "PaintYellow")
    bx(b, (-0.21, 0.21), (0.05, 0.36), (2.86, 2.9), "Trim")                          # visor roof
    bx(b, (-0.15, 0.15), (0.30, 0.31), (2.33, 2.83), "Trim")                         # dark display plate
    bx(b, (-0.04, 0.04), (0.06, 0.12), (2.1, 2.3), "MetalDark")                       # mount stub
    # red hand (upper), green walker (lower); viewer at +Y sees +X on the left
    zc = 2.68
    y0, y1 = 0.31, 0.318
    bx(r, (-0.045, 0.045), (y0, y1), (zc - 0.07, zc - 0.005), "SignalRed")            # palm
    for fx in (-0.033, -0.011, 0.011, 0.033):
        bx(r, (fx - 0.009, fx + 0.009), (y0, y1), (zc - 0.005, zc + 0.065 - abs(fx) * 0.4), "SignalRed")
    with xf(r, about((0.045, 0, zc - 0.03), RY(-35))):
        bx(r, (0.045, 0.062), (y0, y1), (zc - 0.03, zc + 0.02), "SignalRed")          # thumb
    zw = 2.43
    bx(gr, (-0.016, 0.016), (y0, y1), (zw + 0.055, zw + 0.085), "SignalGreen")        # head
    bx(gr, (-0.022, 0.022), (y0, y1), (zw - 0.02, zw + 0.05), "SignalGreen")          # torso
    with xf(gr, about((0, 0, zw - 0.02), RY(20))):
        bx(gr, (-0.02, 0.0), (y0, y1), (zw - 0.085, zw - 0.02), "SignalGreen")        # legs
    with xf(gr, about((0, 0, zw - 0.02), RY(-20))):
        bx(gr, (0.0, 0.02), (y0, y1), (zw - 0.085, zw - 0.02), "SignalGreen")
    with xf(gr, about((0, 0, zw + 0.045), RY(28))):
        bx(gr, (-0.044, -0.022), (y0, y1), (zw - 0.005, zw + 0.045), "SignalGreen")   # arms
    with xf(gr, about((0, 0, zw + 0.045), RY(-28))):
        bx(gr, (0.022, 0.044), (y0, y1), (zw - 0.005, zw + 0.045), "SignalGreen")
    # push button + plate on the pole
    bx(b, (-0.05, 0.05), (0.055, 0.1), (1.05, 1.2), "PlateYellow")
    bx(b, (-0.02, 0.02), (0.1, 0.112), (1.1, 1.15), "Trim")
    bx(b, (-0.07, 0.07), (0.055, 0.065), (1.25, 1.4), "PlateWhite")
    a.fin(b, "Body")
    a.fin(r, "SignalRed")
    a.fin(gr, "SignalGreen")
    return a


def b_speed_sign():
    a = new_asset("speed_sign", 11)
    b = a.mb()
    cylz(b, 0, 0, 0, 0.05, 0.1, 6, "PoleGrey", r1=0.07)
    cylz(b, 0, 0, 0.05, 2.7, 0.035, 6, "PoleGrey")
    zc = 2.28
    ext(b, ngon(12, 0.34, 0, zc, 15), "xz", 0.05, 0.062, "PlateWhite")
    ext(b, ngon(12, 0.31, 0, zc, 15), "xz", 0.062, 0.07, "PlateRed")
    ext(b, ngon(12, 0.235, 0, zc, 15), "xz", 0.07, 0.078, "PlateWhite")
    t = 0.028

    def digit(x0, five):
        # viewer (at +Y) sees +X on the left
        bx(b, (x0 - 0.052, x0 + 0.052), (0.078, 0.086), (zc + 0.1 - t, zc + 0.1), "Trim")      # top
        bx(b, (x0 - 0.052, x0 + 0.052), (0.078, 0.086), (zc - 0.1, zc - 0.1 + t), "Trim")      # bottom
        if five:
            bx(b, (x0 - 0.052, x0 + 0.052), (0.078, 0.086), (zc - t / 2, zc + t / 2), "Trim")   # middle
            bx(b, (x0 + 0.052 - t, x0 + 0.052), (0.078, 0.086), (zc, zc + 0.1), "Trim")        # upper left (viewer)
            bx(b, (x0 - 0.052, x0 - 0.052 + t), (0.078, 0.086), (zc - 0.1, zc), "Trim")         # lower right (viewer)
        else:
            bx(b, (x0 + 0.052 - t, x0 + 0.052), (0.078, 0.086), (zc - 0.1, zc + 0.1), "Trim")
            bx(b, (x0 - 0.052, x0 - 0.052 + t), (0.078, 0.086), (zc - 0.1, zc + 0.1), "Trim")
    digit(0.07, True)
    digit(-0.07, False)
    a.fin(b, "Body")
    return a


def b_street_sign():
    a = new_asset("street_sign", 12)
    b = a.mb()
    cylz(b, 0, 0, 0, 0.05, 0.1, 6, "PoleGrey", r1=0.07)
    cylz(b, 0, 0, 0.05, 3.0, 0.035, 6, "PoleGrey")
    cylz(b, 0, 0, 3.0, 3.06, 0.05, 6, "MetalDark", r1=0.02)
    # blade A along X (z 2.62..2.88), blade B along Y (z 2.28..2.54)
    bx(b, (-0.5, 0.5), (-0.012, 0.012), (2.62, 2.88), "PlateWhite")
    bx(b, (-0.47, 0.47), (-0.016, 0.016), (2.645, 2.855), "PlateGreen")
    bx(b, (-0.32, 0.32), (-0.018, 0.018), (2.71, 2.79), "PlateWhite")
    bx(b, (-0.012, 0.012), (-0.5, 0.5), (2.28, 2.54), "PlateWhite")
    bx(b, (-0.016, 0.016), (-0.47, 0.47), (2.305, 2.515), "PlateGreen")
    bx(b, (-0.018, 0.018), (-0.32, 0.32), (2.37, 2.45), "PlateWhite")
    a.fin(b, "Body")
    return a


def b_bollard():
    a = new_asset("bollard", 13)
    b = a.mb()
    cylz(b, 0, 0, 0, 0.05, 0.14, 8, "ConcreteDark", r1=0.125, rot=22.5)
    cylz(b, 0, 0, 0.05, 0.78, 0.095, 8, "MetalDark", rot=22.5)
    cylz(b, 0, 0, 0.55, 0.68, 0.1, 8, "PlateYellow", rot=22.5)
    cylz(b, 0, 0, 0.78, 0.9, 0.095, 8, "MetalDark", r1=0.045, rot=22.5)
    a.fin(b, "Body")
    return a


def b_concrete_barrier():
    a = new_asset("concrete_barrier", 14)
    b = a.mb()
    prof = [(-0.30, 0.0), (0.30, 0.0), (0.30, 0.08), (0.22, 0.30), (0.10, 0.80), (-0.10, 0.80), (-0.22, 0.30), (-0.30, 0.08)]
    b.profile_extrude(prof, 1.5, "Concrete")
    # top hazard stripes
    x = -1.5
    while x < 1.5:
        poly = clip_x([(x, -0.1), (x + 0.2, -0.1), (x + 0.4, 0.1), (x + 0.2, 0.1)], -1.5, 1.5)
        if len(poly) >= 3:
            ext(b, poly, "xy", 0.8, 0.806, "PaintYellow")
        x += 0.5
    # lifting slots (dark) on both ends of the sloped faces + side reflectors
    for sx in (-1, 1):
        bx(b, (sx * 1.2 - 0.07, sx * 1.2 + 0.07), (-0.2, 0.2), (0.3, 0.36), "ConcreteDark")
    for sy in (-1, 1):
        for sx in (-1, 1):
            xs = sx * 1.3
            with xf(b, about((xs, sy * 0.18, 0.55), RX(-sy * 15.0))):
                bx(b, (xs - 0.07, xs + 0.07), (sy * 0.178, sy * 0.186), (0.5, 0.58), "SafetyOrange")
    a.fin(b, "Body")
    return a


def b_road_barrier():
    a = new_asset("road_barrier", 15)
    b = a.mb()
    tilt = math.degrees(math.atan2(0.35, 1.0))
    # two A-frames at x = +-0.68
    for sx in (-1, 1):
        x = 0.68 * sx
        b.beam((x, 0.0, 1.0), (x, 0.35, 0.0), 0.03, 0.03, 4, "MetalDark", True)
        b.beam((x, 0.0, 1.0), (x, -0.35, 0.0), 0.03, 0.03, 4, "MetalDark", True)
        bx(b, (x - 0.035, x + 0.035), (0.28, 0.42), (0.0, 0.03), "MetalDark")
        bx(b, (x - 0.035, x + 0.035), (-0.42, -0.28), (0.0, 0.03), "MetalDark")
    bx(b, (-0.8, 0.8), (-0.035, 0.035), (0.96, 1.02), "MetalDark")                     # apex rail
    # two striped boards on the front legs
    for zc in (0.78, 0.46):
        yc = 0.35 * (1.0 - zc) + 0.04
        with xf(b, about((0, yc, zc), RX(tilt))):
            bx(b, (-0.8, 0.8), (yc - 0.018, yc + 0.018), (zc - 0.1, zc + 0.1), "PlateWhite")
            stripes_xz(b, -0.8, 0.8, zc - 0.1, zc + 0.1, yc + 0.018, yc + 0.024, 0.15, 0.3, 0.2, "PlateRed")
    # blank back panel stripes on the top board (rear side)
    a.fin(b, "Body")
    return a


def b_dumpster():
    a = new_asset("dumpster", 16)
    b = a.mb()
    D = "DumpsterGreen"
    b.block((0, 0), 0.28, 1.12, (1.7, 0.95), (1.95, 1.2), D)
    bx(b, (-1.0, 1.0), (-0.62, 0.62), (1.12, 1.2), "MetalDark")                         # top rim frame
    # lids: left closed (slightly raised), right open 40 deg
    with xf(b, about((0, -0.6, 1.2), RX(4))):
        bx(b, (-0.98, -0.01), (-0.6, 0.6), (1.2, 1.25), "MetalDark")
    with xf(b, about((0, -0.6, 1.2), RX(52))):
        bx(b, (0.01, 0.98), (-0.6, 0.6), (1.2, 1.25), "MetalDark")
    # side ribs on the front + fork pockets
    for x in (-0.55, 0.0, 0.55):
        bx(b, (x - 0.04, x + 0.04), (0.5, 0.58), (0.36, 1.1), "MetalDark")
    for x in (-0.55, 0.55):
        bx(b, (x - 0.14, x + 0.14), (0.52, 0.62), (0.3, 0.4), "Trim")
    # skids + casters
    for x in (-0.7, 0.7):
        bx(b, (x - 0.06, x + 0.06), (-0.55, 0.55), (0.06, 0.28), "MetalDark")
    for x in (-0.7, 0.7):
        for y in (-0.45, 0.45):
            bx(b, (x - 0.06, x + 0.06), (y - 0.06, y + 0.06), (0.0, 0.1), "Trim")
    a.fin(b, "Body")
    return a


def b_utility_box():
    a = new_asset("utility_box", 17)
    b = a.mb()
    U = "UtilGrey"
    bx(b, (-0.5, 0.5), (-0.28, 0.28), (0.0, 0.14), "ConcreteDark")
    b.block((0, 0), 0.14, 1.2, (0.9, 0.46), (0.88, 0.44), U)
    b.block((0, 0), 1.2, 1.26, (0.96, 0.52), (0.84, 0.42), "MetalDark")
    bx(b, (-0.006, 0.006), (0.225, 0.236), (0.2, 1.15), "Trim")                          # door seam
    for sx in (-1, 1):
        for z in (0.32, 0.4, 0.48, 0.56):
            bx(b, (sx * 0.22 - 0.15, sx * 0.22 + 0.15), (0.226, 0.232), (z, z + 0.035), "Trim")  # louvres
        bx(b, (sx * 0.06 - 0.012, sx * 0.06 + 0.012), (0.226, 0.25), (0.62, 0.78), "Metal")      # handle
    bx(b, (-0.38, -0.2), (0.226, 0.232), (0.85, 1.0), "PlateYellow")                          # warning plate
    bx(b, (-0.32, -0.26), (0.232, 0.236), (0.88, 0.96), "Trim")
    a.fin(b, "Body")
    return a


def b_mailbox():
    a = new_asset("mailbox", 18)
    b = a.mb()
    for sx in (-1, 1):
        b.beam((sx * 0.17, 0, 0.0), (sx * 0.17, 0, 0.58), 0.032, 0.032, 4, "MetalDark", True)
        bx(b, (sx * 0.17 - 0.06, sx * 0.17 + 0.06), (-0.12, 0.12), (0.0, 0.03), "MetalDark")
    prof = [(-0.30, 0.56), (0.30, 0.56), (0.30, 0.95), (0.21, 1.06), (0.0, 1.10), (-0.21, 1.06), (-0.30, 0.95)]
    b.profile_extrude(prof, 0.225, "MailBlue")
    bx(b, (-0.2, 0.2), (0.3, 0.315), (0.60, 0.80), "PoleGrey")                           # pull-down door
    bx(b, (-0.09, 0.09), (0.315, 0.335), (0.74, 0.77), "Metal")                          # handle
    bx(b, (-0.17, 0.17), (0.2, 0.31), (1.02, 1.05), "Trim")                              # mail slot
    bx(b, (-0.15, 0.15), (0.3, 0.31), (0.84, 0.92), "PlateWhite")                         # label plate
    bx(b, (0.225, 0.24), (-0.18, 0.18), (0.62, 0.92), "PlateWhite")                       # side stripe
    a.fin(b, "Body")
    return a


def b_parking_meter():
    a = new_asset("parking_meter", 19)
    b = a.mb()
    cylz(b, 0, 0, 0, 0.04, 0.1, 6, "MetalDark", r1=0.07)
    cylz(b, 0, 0, 0.04, 1.08, 0.035, 6, "PoleGrey")
    b.block((0, 0), 1.06, 1.34, (0.24, 0.17), (0.2, 0.15), "PoleGreen")
    b.block((0, 0), 1.34, 1.44, (0.2, 0.15), (0.11, 0.09), "MetalDark")
    cyly(b, 0, 0.075, 0.092, 1.255, 0.07, 8, "PlateWhite")                                  # dial face
    cyly(b, 0, 0.092, 0.098, 1.255, 0.06, 8, "Glass")
    bx(b, (-0.012, 0.012), (0.092, 0.1), (1.255, 1.3), "Trim")                             # needle
    bx(b, (-0.07, 0.07), (0.076, 0.086), (1.15, 1.18), "Trim")                             # coin slot
    bx(b, (-0.08, 0.08), (0.076, 0.085), (1.09, 1.13), "PlateYellow")                       # button strip
    bx(b, (-0.11, 0.11), (0.07, 0.074), (1.335, 1.355), "PlateBlue")
    a.fin(b, "Body")
    return a


def b_phone_booth():
    a = new_asset("phone_booth", 20)
    b = a.mb()
    F, H = "BoothTeal", 2.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx(b, (sx * 0.43 - 0.035, sx * 0.43 + 0.035), (sy * 0.43 - 0.035, sy * 0.43 + 0.035), (0.0, H), F)
    # kick panels + glass on back and sides
    bx(b, (-0.4, 0.4), (-0.455, -0.41), (0.0, 0.34), F)
    bx(b, (-0.455, -0.41), (-0.4, 0.4), (0.0, 0.34), F)
    bx(b, (0.41, 0.455), (-0.4, 0.4), (0.0, 0.34), F)
    bx(b, (-0.4, 0.4), (-0.44, -0.43), (0.34, H - 0.1), "Glass")
    bx(b, (-0.44, -0.43), (-0.4, 0.4), (0.34, H - 0.1), "Glass")
    bx(b, (0.43, 0.44), (-0.4, 0.4), (0.34, H - 0.1), "Glass")
    # top rail + roof + light box
    bx(b, (-0.46, 0.46), (-0.46, 0.46), (H - 0.1, H), F)
    b.block((0, 0), H, H + 0.1, (1.0, 1.0), (0.9, 0.9), "MetalDark")
    bx(b, (-0.4, 0.4), (-0.1, 0.1), (H + 0.1, H + 0.4), "PlateBlue")
    bx(b, (-0.22, 0.22), (0.1, 0.112), (H + 0.18, H + 0.32), "PlateWhite")
    bx(b, (-0.22, 0.22), (-0.112, -0.1), (H + 0.18, H + 0.32), "PlateWhite")
    # phone unit on the back wall
    bx(b, (-0.16, 0.16), (-0.41, -0.33), (1.15, 1.6), "MetalDark")
    bx(b, (-0.12, 0.12), (-0.33, -0.31), (1.2, 1.32), "Trim")
    bx(b, (-0.2, -0.14), (-0.33, -0.28), (1.3, 1.52), "Trim")                             # handset
    bx(b, (-0.15, 0.15), (-0.43, -0.2), (0.95, 0.99), "WoodDark")                         # shelf
    # closed glass door (front): frame ring + glass + pull handle
    with xf(b, about((-0.43, 0.43, 0), RZ(0))):
        bx(b, (-0.40, 0.40), (0.425, 0.465), (0.0, 0.1), F)
        bx(b, (-0.40, 0.40), (0.425, 0.465), (1.92, 2.02), F)
        bx(b, (-0.40, -0.31), (0.425, 0.465), (0.1, 1.92), F)
        bx(b, (0.31, 0.40), (0.425, 0.465), (0.1, 1.92), F)
        bx(b, (-0.31, 0.31), (0.438, 0.452), (0.1, 1.92), "Glass")
        bx(b, (0.22, 0.26), (0.465, 0.5), (0.95, 1.25), "Metal")                          # pull handle
    a.fin(b, "Body")
    return a


def b_newspaper_box():
    a = new_asset("newspaper_box", 21)
    b = a.mb()
    Y = "PaintYellow"
    bx(b, (-0.24, 0.24), (-0.2, 0.2), (0.0, 0.05), "MetalDark")
    bx(b, (-0.1, 0.1), (-0.1, 0.1), (0.05, 0.34), "MetalDark")                           # pedestal
    b.block((0, 0), 0.34, 1.0, (0.5, 0.42), (0.5, 0.42), Y)
    with xf(b, about((0, 0.0, 1.02), RX(-6))):
        bx(b, (-0.27, 0.27), (-0.25, 0.25), (1.0, 1.06), "MetalDark")                    # lid
    bx(b, (-0.19, 0.19), (0.21, 0.225), (0.62, 0.9), "Glass")                              # window
    bx(b, (-0.17, 0.17), (0.205, 0.212), (0.64, 0.88), "PlateWhite")                         # papers
    bx(b, (-0.17, 0.17), (0.21, 0.23), (0.38, 0.56), "PoleGrey")                           # coin plate
    bx(b, (-0.04, 0.04), (0.23, 0.245), (0.46, 0.5), "Trim")                               # slot
    bx(b, (-0.07, 0.07), (0.23, 0.26), (0.41, 0.44), "Metal")                              # pull handle
    a.fin(b, "Body")
    return a
