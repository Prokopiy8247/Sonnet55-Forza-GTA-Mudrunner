r"""lane11_aero.py - splitter_front, bumper_front_sport, bumper_rear_diffuser, skirt_side_sport.
Load after gta_lib.py + lane11_common.py + lane11_catalog.py."""


def l11_pw(pts, x):
    """piecewise-linear lookup of [(x, v)...] (sorted), clamped."""
    if x <= pts[0][0]:
        return pts[0][1]
    for i in range(len(pts) - 1):
        if pts[i][0] <= x <= pts[i + 1][0]:
            t = (x - pts[i][0]) / max(pts[i + 1][0] - pts[i][0], 1e-9)
            return pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t
    return pts[-1][1]


def l11_panel(b, yf, x0, x1, z0, z1, off, t, mat):
    """thin closed slab lying on a surface whose plan line is y = yf(x): front face at yf(x)+off, `t` thick (towards -Y)."""
    F = [(x0, yf(x0) + off, z0), (x1, yf(x1) + off, z0), (x1, yf(x1) + off, z1), (x0, yf(x0) + off, z1)]
    V = [b.v(p) for p in F] + [b.v((p[0], p[1] - t, p[2])) for p in F]
    for idx in ((0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (3, 2, 6, 7), (0, 3, 7, 4), (1, 2, 6, 5)):
        b.face([V[i] for i in idx], mat)


def l11_splitter_front():
    P = L11Part("splitter_front", l11_idx("splitter_front"))
    b = P.mb()
    plan = [(-0.78, -0.20), (0.78, -0.20), (0.82, 0.00), (0.72, 0.13), (-0.72, 0.13), (-0.82, 0.00)]
    b.prism(plan, -0.032, 0.0, "Trim")
    lip = [(0.80, 0.0), (0.70, 0.12), (-0.70, 0.12), (-0.80, 0.0), (-0.76, 0.0), (-0.67, 0.09), (0.67, 0.09), (0.76, 0.0)]
    b.prism(lip, 0.0, 0.024, "Paint2")
    for sx in (1, -1):
        can = [(-0.10, 0.0), (0.07, 0.0), (0.07, 0.016), (-0.10, 0.072)]
        x0 = sx * 0.60
        l11_slab(b, can, min(x0, x0 + sx * 0.014), max(x0, x0 + sx * 0.014), "Paint2")
        b.bx(sx * 0.40 - 0.02, sx * 0.40 + 0.02, -0.19, -0.14, -0.026, -0.006, "MetalDark")   # mounting tabs under the plate
    P.add(b)
    return P


def l11_bumper_front_sport():
    P = L11Part("bumper_front_sport", l11_idx("bumper_front_sport"))
    b = P.mb()
    xs = [-0.86, -0.70, -0.50, -0.34, 0.34, 0.50, 0.70, 0.86]
    curve = [(0.0, 0.0), (0.34, 0.0), (0.50, -0.014), (0.70, -0.065), (0.80, -0.14), (0.88, -0.27)]

    def yf(x):
        return l11_pw(curve, abs(x))
    H = 0.275
    shell = [(-0.16, 0.0), (-0.02, 0.0), (0.0, 0.022), (0.0, 0.252), (-0.035, H), (-0.16, H)]
    l11_sweep(b, shell, xs, lambda s, y, z: (s, y + yf(s), z), "Paint")
    lip = [(-0.10, 0.0), (0.020, 0.0), (0.014, 0.036), (-0.10, 0.036)]
    l11_sweep(b, lip, xs, lambda s, y, z: (s, y + yf(s), z), "Trim")
    # intakes (black recesses sitting on the front face) + slats
    l11_panel(b, yf, -0.34, 0.34, 0.080, 0.190, 0.004, 0.020, "Trim")
    for zc in (0.105, 0.135, 0.165):
        b.bx(-0.32, 0.32, 0.0, 0.014, zc - 0.006, zc + 0.006, "Metal")
    l11_panel(b, yf, -0.34, 0.34, 0.208, 0.236, 0.004, 0.012, "Paint2")
    for sx in (1, -1):
        xa, xb = (0.50, 0.70) if sx > 0 else (-0.70, -0.50)
        l11_panel(b, yf, xa, xb, 0.052, 0.170, 0.004, 0.020, "Trim")
        xa, xb = (0.70, 0.80) if sx > 0 else (-0.80, -0.70)
        # fog lamp on the corner (follows the curve; end x clamp to the shell)
        l11_panel(b, yf, xa + (0.015 if sx > 0 else 0.0), xb - (0.0 if sx > 0 else 0.015), 0.085, 0.150, 0.006, 0.020, "LightHead")
    P.add(b)
    return P


def l11_bumper_rear_diffuser():
    P = L11Part("bumper_rear_diffuser", l11_idx("bumper_rear_diffuser"))
    b = P.mb()
    # roof of the diffuser tunnel: slopes up towards the rear (-Y); central width 0.76 at the front, 0.86 at the tail (exhaust tips live outboard)
    plate = [(-0.20, 0.050), (0.14, -0.025), (0.14, -0.005), (-0.20, 0.072)]

    def wid(s, y, z):
        t = (0.14 - y) / 0.34
        return (s * (0.38 + 0.05 * t), y, z)
    l11_sweep(b, plate, [-1.0, -0.5, 0.5, 1.0], lambda s, y, z: wid(s, y, z), "Trim")
    for k in range(5):
        x = (k - 2) * 0.145
        fin = [(-0.19, -0.032), (0.14, -0.032), (0.14, -0.024), (-0.19, 0.056)]
        l11_slab(b, fin, x - 0.009, x + 0.009, "MetalDark")
    for sx in (1, -1):
        st = [(-0.21, -0.045), (0.14, -0.045), (0.14, -0.02), (-0.21, 0.095)]
        x0 = sx * 0.43
        l11_slab(b, st, min(x0, x0 + sx * 0.016), max(x0, x0 + sx * 0.016), "Paint2")
    # body-coloured valance above the tail edge + fog lamp
    b.tbx((-0.72, 0.72), (-0.085, 0.06), (0.072, 0.165), "Paint", top_x=(-0.72, 0.72), top_y=(-0.055, 0.06))
    b.bx(-0.14, 0.14, -0.096, -0.08, 0.098, 0.124, "LightTail")
    P.add(b)
    return P


def l11_skirt_side_sport():
    P = L11Part("skirt_side_sport", l11_idx("skirt_side_sport"))
    b = P.mb()
    ys = [-1.00, -0.90, 0.90, 1.00]

    def mk(sec, mat, sx):
        rings = []
        for y in ys:
            s = 1.0 if abs(y) <= 0.90 else 0.35
            ring = []
            for (x, z) in sec:
                xx = 0.84 + (x - 0.84) * s
                zz = 0.135 - (0.135 - z) * (0.45 + 0.55 * s)
                ring.append((sx * xx, y, zz))
            rings.append(ring)
        b.loft(rings, mat, True, True, True)
    main = [(0.84, -0.035), (0.925, -0.035), (0.948, 0.0), (0.945, 0.115), (0.90, 0.135), (0.84, 0.135)]
    lipp = [(0.88, -0.058), (0.972, -0.058), (0.972, -0.036), (0.88, -0.036)]
    strip = [(0.9435, 0.048), (0.954, 0.048), (0.954, 0.078), (0.9435, 0.078)]
    for sx in (1, -1):
        mk(main, "Paint", sx)
        mk(lipp, "Trim", sx)
        mk(strip, "Paint2", sx)
    P.add(b)
    return P


def l11_build_aero():
    out = []
    for fn in (l11_splitter_front, l11_bumper_front_sport, l11_bumper_rear_diffuser, l11_skirt_side_sport):
        P = fn()
        P.report()
        out.append(P)
    return out
