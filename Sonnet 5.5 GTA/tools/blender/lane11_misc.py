r"""lane11_misc.py - exhaust_tip_single/dual/quad, underglow_strip, grille_mesh, mirror_sport, antenna.
Load after gta_lib.py + lane11_common.py + lane11_catalog.py."""


def l11_tip(b, cx, cz, r=0.045, seg=10, cut=14.0, clamp=True, stub=0.12):
    """One exhaust tip: outlet at y=0 pointing towards -Y, pipe body runs towards +Y. Chrome flared tube (open), dark inner disc, pipe stub."""
    tn = math.tan(math.radians(cut))
    rings = []
    for (y, rr, k) in ((0.0, r * 1.12, 1.0), (0.032, r, 0.0), (0.17, r, 0.0)):
        ring = []
        for i in range(seg - 1, -1, -1):          # reversed so the open tube's faces point OUTWARD
            a = 2 * math.pi * i / seg
            ring.append((cx + math.cos(a) * rr, y + math.sin(a) * rr * tn * k, cz + math.sin(a) * rr))
        rings.append(ring)
    b.loft(rings, "Chrome", True, False, False)
    disc = [(cx + math.cos(2 * math.pi * i / seg) * r * 0.9, 0.05, cz + math.sin(2 * math.pi * i / seg) * r * 0.9) for i in range(seg)]
    b.fo(disc, "Trim", (0, -1, 0))
    if stub > 0:
        b.cyl((cx, 0.17 + stub / 2, cz), r * 0.8, stub, max(6, seg - 2), "MetalDark", axis="Y")
    if clamp:
        rg = [[(cx + math.cos(2 * math.pi * i / 8) * rr, y, cz + math.sin(2 * math.pi * i / 8) * rr) for i in range(7, -1, -1)]
              for (y, rr) in ((0.15, r * 1.1), (0.19, r * 1.1))]
        b.loft(rg, "Metal", True, False, False)


def l11_exhaust_tip_single():
    P = L11Part("exhaust_tip_single", l11_idx("exhaust_tip_single"))
    b = P.mb()
    l11_tip(b, 0.0, 0.0, r=0.050, seg=12, cut=14.0)
    P.add(b, smooth=35)
    return P


def l11_exhaust_tip_dual():
    P = L11Part("exhaust_tip_dual", l11_idx("exhaust_tip_dual"))
    b = P.mb()
    for sx in (1, -1):
        l11_tip(b, sx * 0.54, 0.0, r=0.046, seg=10, cut=12.0)
    b.bx(-0.56, 0.56, 0.27, 0.285, -0.012, 0.012, "MetalDark")     # cross pipe (hidden under the car)
    P.add(b, smooth=35)
    return P


def l11_exhaust_tip_quad():
    P = L11Part("exhaust_tip_quad", l11_idx("exhaust_tip_quad"))
    b = P.mb()
    for sx in (1, -1):
        for dx in (-0.075, 0.075):
            l11_tip(b, sx * 0.535 + dx, 0.0, r=0.034, seg=8, cut=10.0, clamp=False, stub=0.09)
        b.bx(sx * 0.535 - 0.115, sx * 0.535 + 0.115, 0.17, 0.20, -0.016, 0.016, "Metal")
    P.add(b, smooth=35)
    return P


def l11_underglow_strip():
    P = L11Part("underglow_strip", l11_idx("underglow_strip"))
    b = P.mb()
    hx, hy, c = 0.74, 1.90, 0.34
    path = [(-hx + c, -hy), (hx - c, -hy), (hx, -hy + c), (hx, hy - c), (hx - c, hy), (-hx + c, hy), (-hx, hy - c), (-hx, -hy + c)]
    n = len(path)
    P2 = [Vector((p[0], p[1])) for p in path]
    r, sides = 0.022, 6
    rings = []
    for i in range(n):
        a, cc, e = P2[i - 1], P2[i], P2[(i + 1) % n]
        t1 = (cc - a).normalized()
        t2 = (e - cc).normalized()
        n1, n2 = Vector((t1.y, -t1.x)), Vector((t2.y, -t2.x))
        k = 1.0 + n1.dot(n2)
        mm = (n1 + n2) / max(k, 0.5)
        ring = []
        for j in range(sides):
            ang = 2 * math.pi * j / sides + math.pi / sides
            h = mm * (math.cos(ang) * r)
            ring.append((cc.x + h.x, cc.y + h.y, math.sin(ang) * r))
        rings.append(ring)
    V = [[b.v(p) for p in ring] for ring in rings]
    for i in range(n):
        j = (i + 1) % n
        for s in range(sides):
            t = (s + 1) % sides
            b.face([V[i][s], V[j][s], V[j][t], V[i][t]], "NeonCyan")
    # four small black mounting clips under the sill line (give the strip something to hang on)
    for sx in (1, -1):
        for y in (-1.2, 1.2):
            b.bx(sx * hx - 0.02, sx * hx + 0.02, y - 0.05, y + 0.05, 0.016, 0.075, "Trim")
    P.add(b)
    return P


def l11_grille_mesh():
    P = L11Part("grille_mesh", l11_idx("grille_mesh"))
    b = P.mb()
    hw, hh = 0.34, 0.082
    for sx in (1, -1):
        b.bx(sx * hw - (0.02 if sx > 0 else 0.0), sx * hw + (0.0 if sx > 0 else 0.02), -0.01, 0.026, -hh, hh, "Chrome")
    for sz in (1, -1):
        b.bx(-hw, hw, -0.01, 0.026, sz * hh - (0.016 if sz > 0 else 0.0), sz * hh + (0.0 if sz > 0 else 0.016), "Chrome")
    b.bx(-hw + 0.02, hw - 0.02, -0.012, 0.004, -hh + 0.016, hh - 0.016, "Trim")
    ix, iz = hw - 0.02, hh - 0.016
    for s in (1, -1):
        a = -ix - 0.2
        while a < ix + 0.2:
            # line x = a + s*z  for z in [-iz, iz], clipped to |x| <= ix
            lo, hi = -iz, iz
            if s > 0:
                lo = max(lo, -ix - a)
                hi = min(hi, ix - a)
            else:
                lo = max(lo, (a - ix))
                hi = min(hi, (a + ix))
            if hi - lo > 0.03:
                p0 = (a + s * lo, 0.010, lo)
                p1 = (a + s * hi, 0.010, hi)
                l11_bar(b, p0, p1, 0.0105, 0.016, "MetalDark" if s > 0 else "Metal", up=(0, 1, 0))
            a += 0.115
    P.add(b)
    return P


def l11_mirror_sport():
    P = L11Part("mirror_sport", l11_idx("mirror_sport"))
    b = P.mb()
    for sx in (1, -1):
        hs = [(-0.040, -0.048), (0.025, -0.052), (0.050, -0.010), (0.040, 0.050), (-0.020, 0.052), (-0.040, 0.030)]
        x0, x1 = (0.95, 1.12) if sx > 0 else (-1.12, -0.95)
        l11_slab(b, hs, x0, x1, "Paint", bev=0.012)
        gx0, gx1 = (0.955, 1.10) if sx > 0 else (-1.10, -0.955)
        b.bx(gx0, gx1, -0.0445, -0.0395, -0.034, 0.038, "Chrome")
        l11_bar(b, (sx * 0.86, 0.035, -0.040), (sx * 1.00, 0.012, -0.022), 0.034, 0.030, "Trim", up=(0, 0, 1), w1=0.03, t1=0.026)
        # Paint2 top fin
        fin = [(-0.030, 0.050), (0.030, 0.050), (0.030, 0.060), (-0.030, 0.056)]
        fx0, fx1 = (0.99, 1.10) if sx > 0 else (-1.10, -0.99)
        l11_slab(b, [(-0.030, 0.051), (0.036, 0.047), (0.034, 0.058), (-0.030, 0.058)][::1], fx0, fx1, "Paint2")
    P.add(b)
    return P


def l11_antenna():
    P = L11Part("antenna", l11_idx("antenna"))
    b = P.mb()
    tilt = math.radians(11.0)
    d = Vector((0.0, -math.sin(tilt), math.cos(tilt)))
    b.cyl((0, 0, 0.017), 0.026, 0.034, 8, "Trim", axis="Z", r_top=0.015)
    b.cyl((0, 0, 0.056), 0.0095, 0.044, 6, "MetalDark", axis="Z")
    p = Vector((0, 0, 0.07))
    segs = [(0.22, 0.0068, 0.0062), (0.18, 0.0056, 0.0050), (0.17, 0.0042, 0.0036)]
    for (L, r0, r1) in segs:
        q = p + d * L
        b.beam(tuple(p), tuple(q), r0, r1, 6, "Metal")
        p = q
    tip = [(0.0, 0.0008), (0.009, 0.0085), (0.018, 0.0008)]
    l11_rev(b, [(p.z - 0.002 + s, r) for (s, r) in tip], "Z", (p.x, p.y), 6, "Chrome")
    P.add(b)
    return P


def l11_build_misc():
    out = []
    for fn in (l11_exhaust_tip_single, l11_exhaust_tip_dual, l11_exhaust_tip_quad, l11_underglow_strip, l11_grille_mesh,
               l11_mirror_sport, l11_antenna):
        P = fn()
        P.report()
        out.append(P)
    return out
