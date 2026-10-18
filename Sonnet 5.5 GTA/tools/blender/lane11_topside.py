r"""lane11_topside.py - hood_scoop_a, hood_vents_b, roof_scoop, roof_rack, roof_light_bar.
Origin = centre of the footprint on the panel (z=0 = panel surface, the base sinks ~4 cm below). Load after gta_lib.py + lane11_common.py + lane11_catalog.py."""


def l11_cs6(y, hb, ht, z0, z1, zm):
    """6-point cross-section ring in X/Z (chamfered trapezoid) at station y."""
    return [(hb, y, z0), (hb, y, zm), (ht, y, z1), (-ht, y, z1), (-hb, y, zm), (-hb, y, z0)]


def l11_hood_scoop_a():
    P = L11Part("hood_scoop_a", l11_idx("hood_scoop_a"))
    b = P.mb()
    st = [(-0.31, 0.20, 0.10, 0.004), (-0.12, 0.235, 0.14, 0.060), (0.12, 0.265, 0.185, 0.105), (0.30, 0.28, 0.205, 0.120)]
    rings = [l11_cs6(y, hb, ht, -0.04, z1, z1 - 0.025 * min(1.0, z1 / 0.06)) for (y, hb, ht, z1) in st]
    b.loft(rings, "Paint", True, True, True)
    # black intake + vanes on the front face
    b.bx(-0.185, 0.185, 0.296, 0.312, 0.014, 0.092, "Trim")
    for zc in (0.040, 0.066):
        b.bx(-0.185, 0.185, 0.290, 0.318, zc - 0.005, zc + 0.005, "Metal")
    # Paint2 centre stripe following the top
    stripe = [(-0.20, 0.0374), (-0.12, 0.0610), (0.12, 0.1060), (0.26, 0.1157), (0.26, 0.1217), (0.12, 0.1120), (-0.12, 0.0670), (-0.20, 0.0434)]
    l11_slab(b, stripe, -0.055, 0.055, "Paint2")
    P.add(b)
    return P


def l11_hood_vents_b():
    P = L11Part("hood_vents_b", l11_idx("hood_vents_b"))
    b = P.mb()
    for sx in (1, -1):
        plan = [(0.10, -0.26), (0.50, -0.26), (0.46, 0.24), (0.10, 0.24)]
        if sx < 0:
            plan = [(-p[0], p[1]) for p in reversed(plan)]
        b.prism(plan, -0.012, 0.0015, "Trim")
        for k in range(5):
            y0 = 0.17 - 0.09 * k
            xo = 0.50 + (0.46 - 0.50) * (y0 + 0.26) / 0.50 - 0.02
            blade = [(y0 - 0.07, -0.012), (y0, -0.012), (y0, 0.003), (y0 - 0.07, 0.036)]
            if sx > 0:
                l11_slab(b, blade, 0.12, xo, "Paint")
            else:
                l11_slab(b, blade, -xo, -0.12, "Paint")
    P.add(b)
    return P


def l11_roof_scoop():
    P = L11Part("roof_scoop", l11_idx("roof_scoop"))
    b = P.mb()
    st = [(-0.30, 0.20, 0.15, 0.004), (-0.18, 0.22, 0.17, 0.060), (0.06, 0.23, 0.19, 0.130), (0.28, 0.23, 0.19, 0.140)]
    rings = [l11_cs6(y, hb, ht, -0.04, z1, z1 - 0.03 * min(1.0, z1 / 0.06)) for (y, hb, ht, z1) in st]
    b.loft(rings, "Paint2", True, True, True)
    for sx in (1, -1):
        x0, x1 = (0.025, 0.175) if sx > 0 else (-0.175, -0.025)
        b.bx(x0, x1, 0.276, 0.292, 0.020, 0.108, "Trim")
        b.bx(x0, x1, 0.270, 0.298, 0.062, 0.072, "Chrome")
    stripe = [(-0.22, 0.0500), (-0.18, 0.0630), (0.06, 0.1330), (0.24, 0.1430), (0.24, 0.1490), (0.06, 0.1390), (-0.18, 0.0690), (-0.22, 0.0560)]
    l11_slab(b, stripe, -0.012, 0.012, "Paint")
    P.add(b)
    return P


def l11_roof_rack():
    P = L11Part("roof_rack", l11_idx("roof_rack"))
    b = P.mb()
    for sx in (1, -1):
        l11_bar(b, (sx * 0.52, -0.52, 0.063), (sx * 0.52, 0.52, 0.063), 0.034, 0.024, "Metal", up=(0, 0, 1))
        for y in (-0.44, 0.44):
            b.bx(sx * 0.52 - 0.027, sx * 0.52 + 0.027, y - 0.035, y + 0.035, -0.008, 0.052, "Trim")
    for y in (-0.40, 0.0, 0.40):
        b.cyl((0, y, 0.0765), 0.014, 1.14, 6, "MetalDark", axis="X")
        for sx in (1, -1):
            b.bx(sx * 0.565 - 0.012, sx * 0.565 + 0.012, y - 0.016, y + 0.016, 0.062, 0.092, "Trim")
    P.add(b)
    return P


def l11_roof_light_bar():
    P = L11Part("roof_light_bar", l11_idx("roof_light_bar"))
    b = P.mb()
    b.tbx((-0.50, 0.50), (-0.05, 0.05), (0.030, 0.108), "Trim", top_x=(-0.49, 0.49), top_y=(-0.045, 0.03))
    for k in range(6):
        xc = -0.425 + 0.17 * k
        b.bx(xc - 0.07, xc + 0.07, 0.044, 0.0575, 0.046, 0.094, "LampGlow")
    for sx in (1, -1):
        b.bx(sx * 0.50 - (0.0 if sx > 0 else 0.012), sx * 0.50 + (0.012 if sx > 0 else 0.0), -0.03, 0.03, 0.048, 0.090, "LampGlow")
        b.bx(sx * 0.34 - 0.035, sx * 0.34 + 0.035, -0.045, 0.045, -0.006, 0.032, "MetalDark")
    # thin Paint2 top cap
    b.bx(-0.48, 0.48, -0.044, 0.026, 0.108, 0.116, "Paint2")
    P.add(b)
    return P


def l11_build_topside():
    out = []
    for fn in (l11_hood_scoop_a, l11_hood_vents_b, l11_roof_scoop, l11_roof_rack, l11_roof_light_bar):
        P = fn()
        P.report()
        out.append(P)
    return out
