"""lane 9 - street props batch 3: fence_chainlink, fence_wood, fence_metal_gate, utility_pole, ladder_wall, crate, barrel, pallet,
tire_stack, container (+_b/_c/_d), dock_bollard, life_ring, pier_post, billboard.
Requires gta_lib.py + lane9_lib.py."""


# ------------------------------------------------------------------------------------------------ fences
def b_fence_chainlink():
    a = new_asset("fence_chainlink", 22)
    b = a.mb()
    H = 1.9
    for sx in (-1, 1):
        cylz(b, sx * 1.5, 0, 0, H + 0.1, 0.045, 6, "Metal")
        cylz(b, sx * 1.5, 0, H + 0.1, H + 0.14, 0.05, 6, "MetalDark")
    b.beam((-1.5, 0, H), (1.5, 0, H), 0.03, 0.03, 6, "Metal", False)                 # top rail
    b.beam((-1.5, 0, 0.12), (1.5, 0, 0.12), 0.02, 0.02, 4, "Metal", False)             # bottom wire
    # diamond mesh: two families of thin diagonal strips in the XZ plane
    x0, x1, z0, z1 = -1.46, 1.46, 0.14, H - 0.04
    w, step = 0.02, 0.3
    for fam, s in ((0, 1.0), (1, -1.0)):
        y = 0.0 if fam == 0 else 0.006
        cs = [z0 - s * (x1 if s > 0 else x0), z1 - s * (x0 if s > 0 else x1)]
        c = min(cs) + 0.1 * (1 + fam)
        while c < max(cs):
            # line z = s*x + c clipped to the rectangle
            pts = []
            for xe in (x0, x1):
                z = s * xe + c
                if z0 - 1e-6 <= z <= z1 + 1e-6:
                    pts.append((xe, z))
            for ze in (z0, z1):
                xx = (ze - c) / s
                if x0 - 1e-6 < xx < x1 + 1e-6:
                    pts.append((xx, ze))
            pts = sorted(set((round(p[0], 5), round(p[1], 5)) for p in pts))
            if len(pts) >= 2:
                p0, p1 = pts[0], pts[-1]
                d = Vector((p1[0] - p0[0], p1[1] - p0[1]))
                if d.length > 0.05:
                    n = Vector((-d.y, d.x)).normalized() * (w / 2)
                    b.quad((p0[0] + n.x, y, p0[1] + n.y), (p1[0] + n.x, y, p1[1] + n.y), (p1[0] - n.x, y, p1[1] - n.y), (p0[0] - n.x, y, p0[1] - n.y), "Metal")
            c += step
    a.fin(b, "Body")
    return a


def b_fence_wood():
    a = new_asset("fence_wood", 23)
    b = a.mb()
    for sx in (-1, 1):
        x = sx * 1.46
        bx(b, (x - 0.06, x + 0.06), (-0.08, 0.06), (0.0, 1.95), "WoodDark")
        b.block((x, -0.01), 1.95, 2.03, (0.12, 0.14), (0.04, 0.05), "WoodDark")
    for z in (0.35, 1.45):
        bx(b, (-1.46, 1.46), (-0.07, -0.03), (z - 0.045, z + 0.045), "WoodDark")
    n = 12
    pw = 2.86 / n
    tops = (1.84, 1.80, 1.86, 1.82)
    for i in range(n):
        xc = -1.43 + pw * (i + 0.5)
        bx(b, (xc - pw / 2 + 0.006, xc + pw / 2 - 0.006), (-0.03, 0.012), (0.04, tops[i % 4]), "WoodLight" if i % 2 == 0 else "WoodPale")
    a.fin(b, "Body")
    return a


def b_fence_metal_gate():
    a = new_asset("fence_metal_gate", 24)
    b = a.mb()
    G = "PoleGreen"
    for sx in (-1, 1):
        x = sx * 1.5
        bx(b, (x - 0.08, x + 0.08), (-0.08, 0.08), (0.0, 2.0), "MetalDark")
        b.block((x, 0), 2.0, 2.1, (0.2, 0.2), (0.06, 0.06), "MetalDark")
        bx(b, (x - sx * 0.1 - 0.025, x - sx * 0.1 + 0.025), (-0.03, 0.03), (0.35, 0.45), "Metal")   # hinge / catch pins
        bx(b, (x - sx * 0.1 - 0.025, x - sx * 0.1 + 0.025), (-0.03, 0.03), (1.55, 1.65), "Metal")
    bx(b, (-1.4, 1.4), (-0.025, 0.025), (0.18, 0.26), G)                                              # bottom rail
    bx(b, (-1.4, 1.4), (-0.025, 0.025), (1.72, 1.8), G)                                               # top rail
    nb = 13
    for i in range(nb):
        x = -1.32 + 2.64 * i / (nb - 1)
        b.beam((x, 0, 0.26), (x, 0, 1.72), 0.017, 0.017, 4, G, False)
        if i % 2 == 0:
            b.beam((x, 0, 1.8), (x, 0, 1.94), 0.022, 0.002, 4, G, False)                           # spear tips
    b.beam((-1.3, 0, 0.3), (1.3, 0, 1.7), 0.016, 0.016, 4, G, False)                               # diagonal brace
    bx(b, (-0.07, 0.07), (-0.05, 0.06), (0.9, 1.05), "MetalDark")                                    # lock box
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ utility pole
def b_utility_pole():
    a = new_asset("utility_pole", 25)
    b = a.mb()
    W, DK = "WoodLight", "WoodDark"
    cylz(b, 0, 0, 0, 0.5, 0.2, 6, "ConcreteDark", r1=0.18)
    cylz(b, 0, 0, 0.5, 9.0, 0.17, 6, W, r1=0.11)
    cylz(b, 0, 0, 9.0, 9.12, 0.11, 6, DK, r1=0.04)
    bx(b, (-1.2, 1.2), (-0.06, 0.06), (8.3, 8.42), DK)                                       # crossarms
    bx(b, (-0.8, 0.8), (-0.05, 0.05), (7.55, 7.65), DK)
    for sx in (-1, 1):
        b.beam((sx * 0.1, 0, 7.8), (sx * 0.85, 0, 8.32), 0.025, 0.025, 4, DK, False)          # braces
        b.beam((sx * 0.1, 0, 7.15), (sx * 0.62, 0, 7.58), 0.022, 0.022, 4, DK, False)
    ins = [(0, 9.12), (-1.0, 8.42), (0.0, 8.42), (1.0, 8.42), (-0.65, 7.65), (0.65, 7.65)]
    for i, (x, z) in enumerate(ins):
        cylz(b, x, 0, z, z + 0.15, 0.06, 6, "PlateWhite", r1=0.028)
        a.mark("Wire%d" % (i + 1), (x, 0, z + 0.15))
    cylz(b, 0.15, 0.4, 6.7, 7.35, 0.24, 6, "UtilGrey", rot=0.0)                               # transformer can (+Y side)
    cylz(b, 0.15, 0.4, 7.35, 7.5, 0.24, 6, "MetalDark", r1=0.1)
    bx(b, (0.05, 0.25), (0.05, 0.2), (7.1, 7.18), DK)
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ ladder
def b_ladder_wall():
    a = new_asset("ladder_wall", 26)
    b = a.mb()
    for sx in (-1, 1):
        bx(b, (sx * 0.25 - 0.025, sx * 0.25 + 0.025), (0.12, 0.2), (0.0, 3.6), "PaintYellow")
    for i in range(12):
        z = 0.25 + i * 0.29
        b.beam((-0.25, 0.16, z), (0.25, 0.16, z), 0.017, 0.017, 4, "Metal", False)
    for z in (0.5, 1.8, 3.1):
        for sx in (-1, 1):
            bx(b, (sx * 0.25 - 0.02, sx * 0.25 + 0.02), (0.0, 0.12), (z - 0.02, z + 0.02), "MetalDark")
            bx(b, (sx * 0.25 - 0.05, sx * 0.25 + 0.05), (-0.01, 0.0), (z - 0.06, z + 0.06), "MetalDark")
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ crate / barrel / pallet / tires
def b_crate():
    a = new_asset("crate", 27)
    b = a.mb()
    s, h = 0.45, 1.0
    bx(b, (-s, s), (-s, s), (0.0, h), "WoodDark")
    t = 0.045
    for sx in (-1, 1):                                                                       # corner posts
        for sy in (-1, 1):
            bx(b, (sx * (s + 0.01) - 0.055, sx * (s + 0.01) + 0.055), (sy * (s + 0.01) - 0.055, sy * (s + 0.01) + 0.055), (0.0, h), "WoodLight")
    for z0 in (0.0, h - 0.1):                                                                # top / bottom rim boards
        bx(b, (-s, s), (s, s + t), (z0, z0 + 0.1), "WoodLight")
        bx(b, (-s, s), (-s - t, -s), (z0, z0 + 0.1), "WoodLight")
        bx(b, (s, s + t), (-s, s), (z0, z0 + 0.1), "WoodLight")
        bx(b, (-s - t, -s), (-s, s), (z0, z0 + 0.1), "WoodLight")
    L = 0.92                                                                                 # diagonal braces on all four faces
    zc = h / 2
    ang = math.degrees(math.atan2(0.7, 0.8))
    for sy in (-1, 1):
        with xf(b, about((0, 0, zc), RY(ang if sy > 0 else -ang))):
            bx(b, (-0.05, 0.05), (sy * (s + 0.03) - 0.02, sy * (s + 0.03) + 0.02), (zc - L / 2, zc + L / 2), "WoodLight")
    for sx in (-1, 1):
        with xf(b, about((0, 0, zc), RX(ang if sx > 0 else -ang))):
            bx(b, (sx * (s + 0.03) - 0.02, sx * (s + 0.03) + 0.02), (-0.05, 0.05), (zc - L / 2, zc + L / 2), "WoodLight")
    a.fin(b, "Body")
    return a


def b_barrel():
    a = new_asset("barrel", 28)
    b = a.mb()
    P = "DrumPaint"
    R, H = 0.29, 0.88
    cylz(b, 0, 0, 0.0, 0.04, 0.27, 10, "MetalDark", r1=R, caps=True)
    cylz(b, 0, 0, 0.04, H - 0.04, R, 10, P, caps=False)
    for z in (0.28, 0.59):
        cylz(b, 0, 0, z, z + 0.06, R + 0.012, 10, P, caps=False)
    cylz(b, 0, 0, H - 0.04, H, R, 10, "MetalDark", r1=R - 0.02)
    cylz(b, 0, 0, H, H + 0.012, R - 0.04, 10, "Metal")
    cylz(b, 0.12, 0.08, H + 0.012, H + 0.04, 0.035, 6, "MetalDark")
    cylz(b, -0.1, -0.1, H + 0.012, H + 0.032, 0.03, 6, "Brass")
    a.fin(b, "Body", smooth=35)
    return a


def b_pallet():
    a = new_asset("pallet", 29)
    b = a.mb()
    L, Wd = 1.2, 0.8
    for y in (-0.36, 0.0, 0.36):
        bx(b, (-L / 2, L / 2), (y - 0.045, y + 0.045), (0.022, 0.1), "WoodLight")
    for x in (-0.53, 0.0, 0.53):
        bx(b, (x - 0.06, x + 0.06), (-Wd / 2, Wd / 2), (0.0, 0.022), "WoodPale")
    for i in range(7):
        x = -0.54 + 0.18 * i
        bx(b, (x - 0.055, x + 0.055), (-Wd / 2, Wd / 2), (0.1, 0.125), "WoodPale" if i % 2 == 0 else "WoodLight")
    a.fin(b, "Body")
    return a


def b_tire_stack():
    a = new_asset("tire_stack", 30)
    b = a.mb()
    sec = [(0.20, -0.10), (0.30, -0.11), (0.34, -0.05), (0.34, 0.05), (0.30, 0.11), (0.20, 0.10)]
    for i, (dx, dy, rot) in enumerate(((0.0, 0.0, 0.0), (0.02, -0.015, 22.5), (-0.015, 0.02, 10.0))):
        lathe(b, sec, (dx, dy, 0.11 + 0.22 * i), 8, "TireRubber", "Z", rot)
    a.fin(b, "Body", smooth=50)
    return a


# ------------------------------------------------------------------------------------------------ container
def container(aid, slot, shell):
    a = new_asset(aid, slot)
    b = a.mb()
    Lh, Wh, H = 6.04, 1.12, 2.6
    bx(b, (-Wh + 0.02, Wh - 0.02), (-Lh, Lh), (0.12, H - 0.08), shell)                       # core (roof/floor/ends)
    # corrugated long sides: zig-zag strips
    n = 12                                                                                   # periods
    z0, z1 = 0.16, H - 0.1
    for sx in (-1, 1):
        for i in range(2 * n):
            y0 = -Lh + (2 * Lh) * i / (2 * n)
            y1 = -Lh + (2 * Lh) * (i + 1) / (2 * n)
            xa = Wh + (0.07 if i % 2 else 0.0)
            xb = Wh + (0.07 if (i + 1) % 2 else 0.0)
            b.quad((sx * xa, y0, z0), (sx * xb, y1, z0), (sx * xb, y1, z1), (sx * xa, y0, z1), shell)
    # frame: corner posts + long rails
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx(b, (sx * (Wh - 0.01) - 0.085, sx * (Wh - 0.01) + 0.085), (sy * (Lh - 0.02) - 0.085, sy * (Lh - 0.02) + 0.085), (0.0, H), "MetalDark")
        bx(b, (sx * (Wh + 0.01) - 0.06, sx * (Wh + 0.01) + 0.06), (-Lh, Lh), (H - 0.12, H), "MetalDark")
        bx(b, (sx * (Wh + 0.01) - 0.06, sx * (Wh + 0.01) + 0.06), (-Lh, Lh), (0.0, 0.14), "MetalDark")
    # door end (+Y): two leaves, locking rods, centre seam
    yd = Lh - 0.02
    for sx in (-1, 1):
        bx(b, (sx * 0.02 if sx > 0 else -1.12, 1.12 if sx > 0 else -0.02), (yd, yd + 0.04), (0.16, H - 0.14), shell)
        for rx in (0.3, 0.8):
            xr = sx * rx
            b.beam((xr, yd + 0.065, 0.2), (xr, yd + 0.065, H - 0.18), 0.022, 0.022, 4, "Metal", False)
    bx(b, (-0.015, 0.015), (yd + 0.04, yd + 0.05), (0.16, H - 0.14), "Trim")
    for sx in (-1, 1):
        bx(b, (sx * 0.55 - 0.05, sx * 0.55 + 0.05), (yd + 0.055, yd + 0.085), (1.0, 1.1), "MetalDark")  # lock cams
    a.fin(b, "Body")
    return a


def b_container():
    return container("container", 36, "WallA")


def b_container_b():
    return container("container_b", 37, "WallB")


def b_container_c():
    return container("container_c", 38, "WallC")


def b_container_d():
    return container("container_d", 39, "WallD")


# ------------------------------------------------------------------------------------------------ harbour props
def b_dock_bollard():
    a = new_asset("dock_bollard", 31)
    b = a.mb()
    cylz(b, 0, 0, 0.0, 0.05, 0.27, 8, "ConcreteDark", rot=22.5)
    cylz(b, 0, 0, 0.05, 0.42, 0.17, 8, "MetalDark", r1=0.135, rot=22.5)
    cylz(b, 0, 0, 0.42, 0.52, 0.135, 8, "MetalDark", r1=0.215, rot=22.5)
    cylz(b, 0, 0, 0.52, 0.6, 0.215, 8, "Metal", r1=0.18, rot=22.5)
    cylz(b, 0, 0, 0.6, 0.64, 0.12, 8, "MetalDark", r1=0.11, rot=22.5)
    for k in range(4):
        ang = math.radians(45 + 90 * k)
        cylz(b, 0.2 * math.cos(ang), 0.2 * math.sin(ang), 0.05, 0.085, 0.032, 6, "Metal")           # anchor bolts
    a.fin(b, "Body")
    return a


def b_life_ring():
    a = new_asset("life_ring", 32)
    b = a.mb()
    cylz(b, 0, 0, 0.0, 0.05, 0.16, 8, "ConcreteDark", rot=22.5)
    cylz(b, 0, 0, 0.05, 1.45, 0.05, 6, "WoodDark")
    bx(b, (-0.38, 0.38), (-0.03, 0.03), (1.38, 1.46), "WoodDark")                                # cross arm
    bx(b, (-0.045, 0.045), (0.03, 0.17), (1.1, 1.14), "MetalDark")                                 # hook arms
    bx(b, (-0.045, 0.045), (0.03, 0.17), (0.86, 0.9), "MetalDark")
    sec = [(0.0, -0.07), (0.07, 0.0), (0.0, 0.07), (-0.07, 0.0)]                                    # (radial offset, axial offset)
    prof = [(0.27 + ro, ao) for ro, ao in sec]
    lathe(b, prof, (0, 0.2, 1.0), 16, "LifeOrange", "Y", 0.0, mats=["LifeOrange", "PlateWhite", "LifeOrange", "LifeOrange"])
    bx(b, (-0.3, 0.3), (0.1, 0.13), (1.46, 1.5), "PlateRed")                                          # hanging sign
    a.fin(b, "Body", smooth=40)
    return a


def b_pier_post():
    a = new_asset("pier_post", 33)
    b = a.mb()
    cylz(b, 0, 0, 0.0, 2.7, 0.16, 8, "WoodDark", r1=0.145, rot=22.5)
    cylz(b, 0, 0, 2.7, 2.78, 0.15, 8, "WoodLight", r1=0.1, rot=22.5)
    for z in (0.35, 2.35):
        cylz(b, 0, 0, z, z + 0.1, 0.168, 8, "MetalDark", rot=22.5)
    # rope coil around the neck
    lathe(b, [(0.185 + ro, 2.05 + ao) for ro, ao in ((0.0, -0.05), (0.035, 0.0), (0.0, 0.05), (-0.035, 0.0))], (0, 0, 0), 8, "RopeTan", "Z", 0.0)
    lathe(b, [(0.185 + ro, 1.93 + ao) for ro, ao in ((0.0, -0.05), (0.035, 0.0), (0.0, 0.05), (-0.035, 0.0))], (0, 0, 0), 8, "RopeTan", "Z", 22.5)
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ billboard
def b_billboard():
    a = new_asset("billboard", 34)
    b = a.mb()
    pn = a.mb("Panel")
    F = "MetalDark"
    zc = 8.5
    for sx in (-1, 1):
        x = sx * 3.6
        bx(b, (x - 0.55, x + 0.55), (-1.05, 0.05), (0.0, 0.5), "ConcreteDark")
        cylz(b, x, -0.5, 0.5, 9.6, 0.24, 8, "PoleGrey", r1=0.2, rot=22.5)
    # frame ring around the 12 x 5 panel
    bx(b, (-6.0, 6.0), (-0.1, 0.35), (zc + 2.3, zc + 2.5), F)
    bx(b, (-6.0, 6.0), (-0.1, 0.35), (zc - 2.5, zc - 2.3), F)
    for sx in (-1, 1):
        bx(b, (sx * 5.9 - 0.1, sx * 5.9 + 0.1), (-0.1, 0.35), (zc - 2.3, zc + 2.3), F)
    # backing board (inside the frame) + panel mesh (UV 0..1)
    bx(pn, (-5.8, 5.8), (0.02, 0.07), (zc - 2.3, zc + 2.3), "NeonBillboard")
    # rear bracing
    for z in (zc - 1.4, zc + 1.4):
        bx(b, (-3.7, 3.7), (-0.3, -0.1), (z - 0.06, z + 0.06), "PoleGrey")
    for sx in (-1, 1):
        b.beam((sx * 3.6, -0.4, 6.9), (sx * 1.6, -0.2, zc + 1.4), 0.05, 0.05, 4, "PoleGrey", False)
    # catwalk with rail
    bx(b, (-5.9, 5.9), (0.35, 1.1), (zc - 2.9, zc - 2.84), "MetalDark")
    bx(b, (-5.9, 5.9), (1.05, 1.1), (zc - 1.88, zc - 1.83), "Metal")
    for x in (-5.9, 0.0, 5.9):
        b.beam((x, 1.075, zc - 2.84), (x, 1.075, zc - 1.85), 0.025, 0.025, 4, "Metal", False)
    # three floodlights on the top edge
    for x in (-4.0, 0.0, 4.0):
        b.beam((x, 0.15, zc + 2.5), (x, 1.3, zc + 3.0), 0.035, 0.035, 4, "Metal", False)
        b.block((x, 1.35), zc + 2.86, zc + 3.1, (0.4, 0.24), (0.5, 0.3), "MetalDark")
    a.fin(b, "Body")
    p = a.fin(pn, "Panel")
    uv_unit(p, ("x", "z"), flip=True)
    return a
