r"""lane11_spoilers.py - spoiler_lip, spoiler_ducktail, spoiler_wing_low, spoiler_wing_high (origin = centre of the footprint ON the deck,
z=0 = deck surface, feet/underside sink ~2 cm below z=0). Load after gta_lib.py + lane11_common.py + lane11_catalog.py."""


def l11_spoiler_lip():
    P = L11Part("spoiler_lip", l11_idx("spoiler_lip"))
    b = P.mb()
    prof = [(-0.09, -0.02), (0.10, -0.02), (0.10, 0.006), (-0.03, 0.056), (-0.075, 0.075), (-0.09, 0.075)]
    xs = [-0.68, -0.52, -0.30, 0.30, 0.52, 0.68]

    def f(x, y, z):
        ax = abs(x)
        s = 1.0 if ax <= 0.52 else 1.0 - 0.55 * (ax - 0.52) / 0.16          # chord shrinks towards the ends
        droop = 0.05 * max(0.0, (ax - 0.30) / 0.38) ** 1.5                   # follows the crowned trunk lid
        yy = -0.09 + (y + 0.09) * s
        zz = (z * (0.55 + 0.45 * s) if z > 0 else z) - droop
        return (x, yy, zz)
    l11_sweep(b, prof, xs, f, "Paint")
    b.bx(-0.58, 0.58, -0.0945, -0.089, -0.012, 0.034, "Trim")                # black lower band on the rear face
    P.add(b)
    return P


def l11_spoiler_ducktail():
    P = L11Part("spoiler_ducktail", l11_idx("spoiler_ducktail"))
    b = P.mb()
    prof = [(-0.19, -0.03), (0.15, -0.03), (0.15, 0.005), (0.04, 0.010), (-0.06, 0.030), (-0.13, 0.075), (-0.18, 0.135),
            (-0.20, 0.165), (-0.22, 0.14), (-0.20, 0.03)]
    xs = [-0.76, -0.64, -0.36, 0.36, 0.64, 0.76]

    def f(x, y, z):
        t = max(0.0, min(1.0, (0.15 - y) / 0.37))                              # 0 front .. 1 rear
        sx = 0.80 + 0.20 * t                                                   # plan view: wider at the tail
        end = max(0.0, (abs(x) - 0.60) / 0.16)
        zz = z * (1.0 - 0.30 * end) - 0.05 * end * end
        return (x * sx, y, zz)
    l11_sweep(b, prof, xs, f, "Paint")
    # black band on the rear (under-lip) face + Paint2 centre insert on the tail top
    b.bx(-0.52, 0.52, -0.2295, -0.2185, 0.035, 0.115, "Trim")
    insert = [(-0.185, 0.139), (-0.13, 0.0765), (-0.075, 0.0405), (-0.075, 0.0465), (-0.13, 0.0825), (-0.19, 0.147)]
    l11_slab(b, [(y, z + 0.0025) for (y, z) in insert], -0.30, 0.30, "Paint2")
    P.add(b)
    return P


def l11_wing_blade(scale=1.0):
    base = [(-0.15, 0.004), (-0.05, -0.014), (0.08, -0.016), (0.14, -0.006), (0.155, 0.006), (0.12, 0.022), (0.0, 0.030),
            (-0.10, 0.022), (-0.15, 0.012)]
    return [(y * scale, z * scale) for (y, z) in base]


def l11_spoiler_wing_low():
    P = L11Part("spoiler_wing_low", l11_idx("spoiler_wing_low"))
    b = P.mb()
    zc, tilt, hw = 0.20, 8.0, 0.75
    blade = [(y, z + zc) for (y, z) in l11_rot(l11_wing_blade(1.0), -tilt, (0, 0))]
    l11_slab(b, blade, -hw, hw, "Paint2", bev=0.008)
    gur = [(y, z + zc) for (y, z) in l11_rot([(-0.158, 0.006), (-0.146, 0.006), (-0.146, 0.044), (-0.158, 0.044)], -tilt, (0, 0))]
    l11_slab(b, gur, -hw + 0.01, hw - 0.01, "Trim")
    plate = [(-0.19, zc - 0.05), (0.17, zc - 0.062), (0.19, zc - 0.012), (0.12, zc + 0.05), (-0.19, zc + 0.085)]
    for sx in (1, -1):
        l11_slab(b, plate, sx * hw if sx > 0 else -hw - 0.014, sx * hw + 0.014 if sx > 0 else -hw, "Paint")
        # strut (swept back blade) + foot plate
        strut = [(-0.07, -0.012), (0.07, -0.012), (0.035, zc - 0.004), (-0.05, zc - 0.004)]
        xc = sx * 0.46
        l11_slab(b, strut, xc - 0.015, xc + 0.015, "Trim")
        b.bx(xc - 0.055, xc + 0.055, -0.09, 0.09, -0.022, 0.0, "MetalDark")
    P.add(b)
    P.mark("Wing", (0, 0, zc))
    return P


def l11_spoiler_wing_high():
    P = L11Part("spoiler_wing_high", l11_idx("spoiler_wing_high"))
    b = P.mb()
    zc, hw = 0.40, 0.86
    main = [(y, z + zc) for (y, z) in l11_rot(l11_wing_blade(1.13), -10.0, (0, 0))]
    l11_slab(b, main, -hw, hw, "Paint2", bev=0.01)
    flap = [(y - 0.15, z + zc + 0.055) for (y, z) in l11_rot(l11_wing_blade(0.62), 6.0, (0, 0))]
    l11_slab(b, flap, -hw + 0.02, hw - 0.02, "Paint2")
    gur = [(y - 0.15, z + zc + 0.055) for (y, z) in l11_rot([(-0.100, 0.008), (-0.090, 0.008), (-0.090, 0.050), (-0.100, 0.050)], 6.0, (0, 0))]
    l11_slab(b, gur, -hw + 0.03, hw - 0.03, "Trim")
    plate = [(-0.22, zc - 0.11), (0.20, zc - 0.10), (0.225, zc - 0.02), (0.10, zc + 0.095), (-0.14, zc + 0.15), (-0.22, zc + 0.15)]
    for sx in (1, -1):
        l11_slab(b, plate, hw + 0.002 if sx > 0 else -hw - 0.016, hw + 0.016 if sx > 0 else -hw - 0.002, "Paint")
        # accent stripe on the end plate
        l11_slab(b, [(-0.20, zc + 0.115), (0.0, zc + 0.04), (0.0, zc + 0.065), (-0.20, zc + 0.14)],
                 hw + 0.016 if sx > 0 else -hw - 0.020, hw + 0.020 if sx > 0 else -hw - 0.016, "Paint2")
        # swan-neck strut
        neck = [(-0.03, -0.012), (0.085, -0.012), (0.08, 0.20), (0.04, zc - 0.045), (-0.075, zc - 0.045), (-0.015, 0.20)]
        xc = sx * 0.32
        l11_slab(b, neck, xc - 0.018, xc + 0.018, "Trim")
        b.bx(xc - 0.07, xc + 0.07, -0.08, 0.12, -0.022, 0.0, "MetalDark")
    P.add(b)
    P.mark("Wing", (0, 0, zc))
    return P


def l11_build_spoilers():
    out = []
    for fn in (l11_spoiler_lip, l11_spoiler_ducktail, l11_spoiler_wing_low, l11_spoiler_wing_high):
        P = fn()
        P.report()
        out.append(P)
    return out
