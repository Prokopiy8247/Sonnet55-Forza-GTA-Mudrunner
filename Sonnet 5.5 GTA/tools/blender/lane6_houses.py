"""lane6_houses.py - complete houses / small buildings (bld_house_a..d, bld_duplex, bld_apartment_small). Idempotent.
Each is its own GLB under buildings/<id>: origin = footprint centre at ground, front door toward +Y,
nodes: Body (one mesh, WallA/B/C + RoofTile/Roof + Window + trim materials) and empty Door (entrance).
Set ONLY_HOUSES = ["bld_house_a", ...] before exec to build a subset, EXPORT_HOUSES = True to export."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane6_houselib.py", encoding="utf8").read(), globals())


def _walls4(b, hx, hy):
    return (WallRef(b, "y", hy, 1), WallRef(b, "y", -hy, -1), WallRef(b, "x", -hx, -1), WallRef(b, "x", hx, 1))


# ----------------------------------------------------------------------------------------------------------------
def house_a(b):
    """Classic gable house with cross-gable porch and brick chimney. 10 x 8.5 m."""
    hx, hy, Hw = 5.0, 4.25, 2.9
    b.abox(-hx - 0.08, hx + 0.08, -hy - 0.08, hy + 0.08, 0, 0.4, "Concrete", "-z")
    F, Bk, L, R = _walls4(b, hx, hy)
    door = (-0.6, 0.6, 0.5, 2.55)
    wl, wr = (-4.1, -2.3, 0.95, 2.35), (2.3, 4.1, 0.95, 2.35)
    F.wall(-hx, hx, 0.4, Hw, [door, wl, wr], "WallA")
    F.door(door)
    for w in (wl, wr):
        F.window(w, cross=1, shutters="WallC", lintel=True)
    bd = (-0.5, 0.5, 0.4, 2.45)
    bw = [(-3.9, -2.3, 0.95, 2.35), (2.3, 3.9, 0.95, 2.35)]
    Bk.wall(-hx, hx, 0.4, Hw, [bd] + bw, "WallA")
    Bk.door(bd, leaf="WallB")
    for w in bw:
        Bk.window(w, cross=1, lintel=True)
    Bk.box(-0.8, 0.8, 0, 0.9, 0, 0.4, "Concrete", "-d -z")
    sw = [(-2.9, -1.3, 0.95, 2.35), (1.3, 2.9, 0.95, 2.35)]
    for S in (L, R):
        S.wall(-hy, hy, 0.4, Hw, sw, "WallA")
        for w in sw:
            S.window(w, cross=1, lintel=True)
    # main gable roof (ridge along X) + attic windows on the gable ends
    gable_x(b, -hx, hx, hy, 0.6, 2.75, 5.3)
    for sx in (-1, 1):
        G = WallRef(b, "x", sx * hx, sx)
        G.rect(0.006, -0.5, 0.5, 3.45, 4.2, "Window", 1)
        for (u0, u1, z0, z1) in ((-0.58, 0.58, 4.2, 4.28), (-0.58, 0.58, 3.37, 3.45), (-0.58, -0.5, 3.45, 4.2), (0.5, 0.58, 3.45, 4.2), (-0.03, 0.03, 3.45, 4.2)):
            G.rect(0.01, u0, u1, z0, z1, "Trim", 1)
    b.abox(-hx - 0.04, hx + 0.04, hy + 0.57, hy + 0.65, 2.6, 2.8, "Trim", "-y -z")
    b.abox(-hx - 0.04, hx + 0.04, -hy - 0.65, -hy - 0.57, 2.6, 2.8, "Trim", "-y -z")
    # porch with cross gable, posts, steps
    b.abox(-2.0, 2.0, hy, hy + 2.5, 0, 0.5, "Concrete", "-y -z")
    b.abox(-1.1, 1.1, hy + 2.5, hy + 2.95, 0, 0.25, "Concrete", "-y -z")
    for sx in (-1, 1):
        b.abox(sx * 1.75 - 0.1, sx * 1.75 + 0.1, hy + 2.3, hy + 2.5, 0.5, 2.55, "WallD", "-z +z")
        b.abox(sx * 1.75 - 0.15, sx * 1.75 + 0.15, hy + 2.25, hy + 2.55, 0.5, 0.7, "WallD", "-z")
    gable_y(b, hy - 1.0, hy + 2.75, 2.0, 0.4, 2.55, 3.95, caps=(False, True))
    b.abox(-2.0, 2.0, hy + 2.5, hy + 2.6, 2.45, 2.58, "Trim", "-y")
    P = WallRef(b, "y", hy + 2.76, 1)
    P.rect(0.004, -0.3, 0.3, 2.95, 3.35, "Window", 1)
    for (u0, u1, z0, z1) in ((-0.36, 0.36, 3.35, 3.4), (-0.36, 0.36, 2.9, 2.95), (-0.36, -0.3, 2.95, 3.35), (0.3, 0.36, 2.95, 3.35)):
        P.rect(0.008, u0, u1, z0, z1, "Trim", 1)
    # brick chimney against the right gable
    chimney(b, hx + 0.4, 0.0, 0.0, 6.0, 0.8, 1.0)


# ----------------------------------------------------------------------------------------------------------------
def house_b(b):
    """Modern flat-roof house: ground box + cantilevered upper box, big glazing, terrace with glass rail. ~11 x 9 m."""
    gx0, gx1, gy0, gy1, gh = -5.5, 5.5, -4.5, 3.5, 3.2
    ux0, ux1, uy0, uy1, uh = -1.0, 5.5, -4.0, 4.5, 6.2
    F = WallRef(b, "y", gy1, 1)
    Bk = WallRef(b, "y", gy0, -1)
    L = WallRef(b, "x", gx0, -1)
    R = WallRef(b, "x", gx1, 1)
    door = (-4.7, -3.5, 0.12, 2.5)
    slider = (-2.4, 4.8, 0.12, 2.95)
    F.wall(gx0, gx1, 0, gh, [door, slider], "WallA")
    F.door(door, leaf="WallB")
    F.window(slider, depth=0.22, cross=3, sill=False, bar=False)
    bw = [(-4.5, -2.5, 0.9, 2.5), (-0.5, 2.0, 0.9, 2.5), (3.0, 5.0, 0.9, 2.5)]
    Bk.wall(gx0, gx1, 0, gh, bw, "WallA")
    for w in bw:
        Bk.window(w, cross=1, sill=False, bar=False)
    lw = [(-3.0, -1.0, 0.9, 2.5), (0.5, 2.5, 0.9, 2.5)]
    L.wall(gy0, gy1, 0, gh, lw, "WallA")
    for w in lw:
        L.window(w, sill=False, bar=False)
    rw = [(-3.0, -1.0, 0.9, 2.5), (0.5, 2.0, 0.9, 2.5)]
    R.wall(gy0, gy1, 0, gh, rw, "WallA")
    for w in rw:
        R.window(w, sill=False, bar=False)
    # ground roof slab / terrace
    b.abox(gx0 - 0.1, gx1 + 0.1, gy0 - 0.1, gy1 + 0.1, gh, gh + 0.22, "WallD", "-z")
    b.zq(gh + 0.225, -5.3, -1.2, -4.3, 3.3, 1, "Wood")
    # glass rail around the terrace
    for z0 in (gh + 0.22,):
        b.yq(gy1 + 0.0, -5.4, -1.2, z0 + 0.1, z0 + 1.0, 1, "Glass")
        b.yq(gy0 + 0.0, -5.4, -1.2, z0 + 0.1, z0 + 1.0, -1, "Glass")
        b.xq(gx0 - 0.0, gy0, gy1, z0 + 0.1, z0 + 1.0, -1, "Glass")
    b.abox(gx0 - 0.04, -1.1, gy1 - 0.03, gy1 + 0.03, gh + 1.2, gh + 1.26, "Metal", "")
    b.abox(gx0 - 0.04, -1.1, gy0 - 0.03, gy0 + 0.03, gh + 1.2, gh + 1.26, "Metal", "")
    b.abox(gx0 - 0.03, gx0 + 0.03, gy0, gy1, gh + 1.2, gh + 1.26, "Metal", "")
    for (x, y) in ((-5.45, 3.5), (-3.3, 3.5), (-1.15, 3.5), (-5.45, -4.5), (-3.3, -4.5), (-1.15, -4.5), (-5.45, -0.5)):
        b.abox(x - 0.04, x + 0.04, y - 0.04, y + 0.04, gh + 0.22, gh + 1.22, "Metal", "-z")
    # upper volume
    U = WallRef(b, "y", uy1, 1)
    UB = WallRef(b, "y", uy0, -1)
    UL = WallRef(b, "x", ux0, -1)
    UR = WallRef(b, "x", ux1, 1)
    uf = (0.3, 4.9, 3.85, 5.6)
    U.wall(ux0, ux1, gh, uh, [uf], "WallC")
    U.window(uf, depth=0.2, cross=3, sill=False, bar=False)
    UB.wall(ux0, ux1, gh, uh, [(-0.5, 1.5, 3.9, 5.5), (2.5, 4.8, 3.9, 5.5)], "WallC")
    for w in ((-0.5, 1.5, 3.9, 5.5), (2.5, 4.8, 3.9, 5.5)):
        UB.window(w, sill=False, bar=False)
    ulh = (-3.0, 2.2, 3.45, 5.95)
    UL.wall(uy0, uy1, gh, uh, [ulh], "WallC")
    UL.window(ulh, depth=0.2, cross=2, sill=False, bar=False)
    UR.wall(uy0, uy1, gh, uh, [(-2.5, -0.8, 4.0, 5.4), (1.0, 3.0, 4.0, 5.4)], "WallC")
    for w in ((-2.5, -0.8, 4.0, 5.4), (1.0, 3.0, 4.0, 5.4)):
        UR.window(w, sill=False, bar=False)
    # cantilever soffit, wood fins, column, roof slab
    b.zq(gh, ux0, ux1, gy1, uy1, -1, "Wood")
    for x in (-0.75, 5.15):
        U.box(x - 0.12, x + 0.12, 0, 0.07, gh + 0.1, uh - 0.1, "Wood", "-d -z +z")
    b.abox(5.2, 5.4, 4.3, 4.5, 0, gh, "Metal", "-z +z")
    b.abox(ux0 - 0.25, ux1 + 0.25, uy0 - 0.25, uy1 + 0.25, uh, uh + 0.25, "WallD", "-z")
    b.zq(uh + 0.255, ux0 - 0.05, ux1 + 0.05, uy0 - 0.05, uy1 + 0.05, 1, "Roof")
    b.abox(1.2, 2.6, -3.0, -2.0, uh + 0.255, uh + 0.75, "Plate", "-z")                    # rooftop unit
    # rooftop PV array (4 tilted panels facing the front)
    tl = math.radians(14)
    for i in range(4):
        xc = 0.9 + i * 1.15
        y0, zb = -0.2, uh + 0.3
        c = [(xc - 0.5, y0 + 1.5 * math.cos(tl), zb), (xc + 0.5, y0 + 1.5 * math.cos(tl), zb), (xc + 0.5, y0, zb + 1.5 * math.sin(tl)), (xc - 0.5, y0, zb + 1.5 * math.sin(tl))]
        b.pq(c, (0, math.sin(tl), math.cos(tl)), "SolarPanel")
        lo = [(p[0], p[1], p[2] - 0.05) for p in c]
        b.pq([c[3], c[2], lo[2], lo[3]], (0, -math.cos(tl), math.sin(tl)), "Metal")
        b.pq([c[0], c[1], lo[1], lo[0]], (0, math.cos(tl), -math.sin(tl)), "Metal")
        b.pq([c[0], c[3], lo[3], lo[0]], (-1, 0, 0), "Metal")
        b.pq([c[1], c[2], lo[2], lo[1]], (1, 0, 0), "Metal")
        b.beamk((xc - 0.4, y0 + 1.5 * math.cos(tl) * 0.5, uh + 0.255), (xc - 0.4, y0 + 1.5 * math.cos(tl) * 0.5, zb + 0.75 * math.sin(tl) - 0.05), 0.02, 0.02, 3, "Metal", False)
    # courtyard screen wall beside the entrance, planters, address plate
    b.abox(-5.5, -5.3, gy1, gy1 + 3.2, 0, 2.3, "Wood", "-z")
    for k in range(1, 7):
        b.yq(gy1 + 3.205, -5.5, -5.3, k * 0.32, k * 0.32 + 0.03, 1, "Trim")
    b.abox(-3.1, -2.4, gy1 + 0.0, gy1 + 0.8, 0, 0.5, "Concrete", "-y -z")
    b.abox(-3.05, -2.45, gy1 + 0.04, gy1 + 0.76, 0.5, 0.9, "Leaf", "-y -z")
    b.abox(-0.9, -0.2, gy1 + 0.0, gy1 + 0.8, 0, 0.5, "Concrete", "-y -z")
    b.abox(-0.85, -0.25, gy1 + 0.04, gy1 + 0.76, 0.5, 1.0, "Leaf", "-y -z")
    b.abox(-3.4, -3.0, gy1, gy1 + 0.05, 1.5, 1.75, "Plate", "-y")
    # entry canopy + stoop
    b.abox(-5.35, -2.95, gy1, gy1 + 1.5, 2.72, 2.88, "Concrete", "-y")
    b.abox(-4.1, -3.9, gy1 + 1.3, gy1 + 1.45, 2.4, 2.72, "LampGlow", "")
    b.abox(-5.0, -3.2, gy1, gy1 + 1.5, 0, 0.12, "Concrete", "-y -z")
    b.abox(-4.8, -3.4, gy1 + 1.5, gy1 + 1.9, 0, 0.06, "Concrete", "-y -z")


# ----------------------------------------------------------------------------------------------------------------
def house_c(b):
    """Two-storey family house, full-width porch, bay window, gable roof ridge along Y. 9.5 x 8.5 (+2 m porch)."""
    hx, hy = 4.75, 4.25
    H1, H2 = 2.9, 5.6
    b.abox(-hx - 0.08, hx + 0.08, -hy - 0.08, hy + 0.08, 0, 0.4, "Concrete", "-z")
    F, Bk, L, R = _walls4(b, hx, hy)
    door = (-0.6, 0.6, 0.5, 2.55)
    gr = (2.0, 3.9, 0.95, 2.35)
    uw = [(-3.9, -2.3, 3.7, 5.0), (-0.8, 0.8, 3.7, 5.0), (2.3, 3.9, 3.7, 5.0)]
    F.wall(-hx, hx, 0.4, H2, [door, gr] + uw, "WallA")
    F.door(door)
    F.window(gr, cross=1, shutters="WallC", lintel=True)
    for w in uw:
        F.window(w, cross=1, lintel=True, shutters="WallC" if w[0] < -1 or w[0] > 1 else None)
    # bay window (ground floor, left)
    B2 = WallRef(b, "y", hy + 0.8, 1)
    bw = (-3.7, -1.7, 0.95, 2.35)
    B2.wall(-4.1, -1.3, 0.5, 2.7, [bw], "WallA")
    B2.window(bw, cross=1, sill=True, lintel=False)
    B2.uface(-4.1, -0.8, 0, 0.5, 2.7, "WallA", -1)
    B2.uface(-1.3, -0.8, 0, 0.5, 2.7, "WallA", 1)
    b.abox(-4.3, -1.1, hy, hy + 1.0, 2.7, 2.86, "WallD", "-y")
    b.zq(2.87, -4.25, -1.15, hy + 0.05, hy + 0.95, 1, "Roof")
    b.abox(-4.1, -1.3, hy, hy + 0.8, 0, 0.5, "Concrete", "-y -z")
    # sides + back
    sw = [(-2.9, -1.3, 0.95, 2.35), (1.3, 2.9, 0.95, 2.35), (-2.9, -1.3, 3.7, 5.0), (1.3, 2.9, 3.7, 5.0)]
    for S in (L, R):
        S.wall(-hy, hy, 0.4, H2, sw, "WallA")
        for w in sw:
            S.window(w, cross=1, lintel=True)
    bd = (-0.5, 0.5, 0.4, 2.45)
    bwn = [(-3.7, -2.1, 0.95, 2.35), (2.1, 3.7, 0.95, 2.35), (-3.7, -2.1, 3.7, 5.0), (-0.8, 0.8, 3.7, 5.0), (2.1, 3.7, 3.7, 5.0)]
    Bk.wall(-hx, hx, 0.4, H2, [bd] + bwn, "WallA")
    Bk.door(bd, leaf="WallB")
    for w in bwn:
        Bk.window(w, cross=1, lintel=False)
    Bk.box(-0.8, 0.8, 0, 0.9, 0, 0.4, "Concrete", "-d -z")
    # floor band
    for (W_, lo, hi) in ((F, -hx, hx), (Bk, -hx, hx), (L, -hy, hy), (R, -hy, hy)):
        W_.box(lo - 0.05, hi + 0.05, 0, 0.09, H1 + 0.0, H1 + 0.22, "WallD", "-d -z")
    # roof: ridge along Y, gable ends front/back
    gable_y(b, -hy, hy, hx, 0.65, 5.45, 8.0)
    G = WallRef(b, "y", hy, 1)
    G.rect(0.006, -0.5, 0.5, 6.3, 7.1, "Window", 1)
    for (u0, u1, z0, z1) in ((-0.58, 0.58, 7.1, 7.18), (-0.58, 0.58, 6.22, 6.3), (-0.58, -0.5, 6.3, 7.1), (0.5, 0.58, 6.3, 7.1), (-0.03, 0.03, 6.3, 7.1)):
        G.rect(0.01, u0, u1, z0, z1, "Trim", 1)
    # full-width porch + shed roof + posts + rails
    b.abox(-hx, hx, hy, hy + 2.0, 0, 0.5, "Concrete", "-y -z")
    b.abox(-1.2, 1.2, hy + 2.0, hy + 2.45, 0, 0.25, "Concrete", "-y -z")
    for x in (-4.5, -1.6, 1.6, 4.5):
        b.abox(x - 0.1, x + 0.1, hy + 1.75, hy + 1.95, 0.5, 3.0, "WallD", "-z +z")
    x0, x1 = -hx - 0.3, hx + 0.3
    b.pq([(x0, hy, 3.55), (x1, hy, 3.55), (x1, hy + 2.3, 3.05), (x0, hy + 2.3, 3.05)], (0, 0.22, 1), "RoofTile")
    b.pq([(x0, hy, 3.4), (x1, hy, 3.4), (x1, hy + 2.3, 2.9), (x0, hy + 2.3, 2.9)], (0, -0.22, -1), "WallD")
    b.yq(hy + 2.3, x0, x1, 2.9, 3.06, 1, "Trim")
    for sx in (-1, 1):
        x = x1 if sx > 0 else x0
        b.pq([(x, hy, 3.55), (x, hy + 2.3, 3.05), (x, hy + 2.3, 2.9), (x, hy, 3.4)], (sx, 0, 0), "Trim")
    for (xa, xb) in ((-4.5, -1.6), (1.6, 4.5)):
        for z in (0.55 + 0.95, 0.55 + 0.45):
            b.abox(xa, xb, hy + 1.82, hy + 1.88, z - 0.03, z + 0.03, "WallD", "")
        for k in range(1, 4):
            x = xa + (xb - xa) * k / 4
            b.abox(x - 0.025, x + 0.025, hy + 1.83, hy + 1.87, 0.55, 1.5, "WallD", "-z +z")
    chimney(b, -2.7, -1.6, 4.0, 8.4, 0.9, 1.0)


# ----------------------------------------------------------------------------------------------------------------
def house_d(b):
    """Single-storey bungalow with attached garage (left), covered entry (right), hip roofs. 12.5 x 8 m."""
    mx0, mx1, gx0, y0, y1 = -1.0, 6.5, -6.0, -4.0, 4.0
    b.abox(mx0 - 0.08, mx1 + 0.08, y0 - 0.08, y1 + 0.08, 0, 0.35, "Concrete", "-z")
    gar = (-5.4, -1.6, 0.0, 2.3)
    door = (3.0, 4.0, 0.35, 2.4)
    w1 = (0.0, 1.8, 0.95, 2.2)
    w2 = (5.0, 6.2, 0.95, 2.2)
    Fg = WallRef(b, "y", y1, 1)
    Fg.wall(gx0, mx0, 0, 2.7, [gar], "WallB")
    Fg.wall(mx0, mx1, 0.35, 2.7, [door, w1, w2], "WallA")
    Fg.door(door)
    for w in (w1, w2):
        Fg.window(w, cross=1, shutters="WallC", lintel=True)
    # garage door: sectional panels + window row + frame
    Fg.uface(gar[0], -0.18, 0, gar[2], gar[3], "WallD", 1)
    Fg.uface(gar[1], -0.18, 0, gar[2], gar[3], "WallD", -1)
    Fg.zface(gar[3], gar[0], gar[1], -0.18, 0, "WallD", -1)
    Fg.rect(-0.18, gar[0], gar[1], gar[2], gar[3], "WallD", 1)
    for k in range(1, 5):
        z = k * 0.46
        Fg.rect(-0.17, gar[0], gar[1], z, z + 0.04, "MetalDark", 1)
    for k in range(5):
        x = gar[0] + 0.25 + k * 0.72
        Fg.rect(-0.17, x, x + 0.5, 1.7, 2.05, "Window", 1)
    Fg.box(gar[0] - 0.12, gar[1] + 0.12, 0, 0.07, gar[3], gar[3] + 0.14, "WallD", "-d -z")
    Fg.box(gar[0] - 0.12, gar[0], 0, 0.07, 0, gar[3], "WallD", "-d -z +z")
    Fg.box(gar[1], gar[1] + 0.12, 0, 0.07, 0, gar[3], "WallD", "-d -z +z")
    # sides + back
    Bk = WallRef(b, "y", y0, -1)
    bwn = [(-5.0, -3.4, 1.0, 2.2), (-2.6, -1.4, 1.0, 2.2), (0.2, 1.8, 1.0, 2.2), (3.0, 4.6, 1.0, 2.2), (5.2, 6.2, 1.0, 2.2)]
    Bk.wall(gx0, mx1, 0, 2.7, bwn, "WallA")
    for w in bwn:
        Bk.window(w, cross=1, lintel=True)
    Lw = WallRef(b, "x", gx0, -1)
    lw = [(-1.3, 0.3, 1.1, 2.2)]
    Lw.wall(y0, y1, 0, 2.7, lw, "WallB")
    Lw.window(lw[0], cross=1)
    Rw = WallRef(b, "x", mx1, 1)
    rw = [(-2.6, -1.0, 1.0, 2.2), (1.0, 2.6, 1.0, 2.2)]
    Rw.wall(y0, y1, 0.35, 2.7, rw, "WallA")
    for w in rw:
        Rw.window(w, cross=1, lintel=True)
    # covered entry: slab, canopy with posts
    b.abox(2.3, 4.9, y1, y1 + 1.8, 0, 0.35, "Concrete", "-y -z")
    b.abox(3.0, 4.0, y1 + 1.8, y1 + 2.2, 0, 0.17, "Concrete", "-y -z")
    for x in (2.5, 4.7):
        b.abox(x - 0.09, x + 0.09, y1 + 1.5, y1 + 1.68, 0.35, 2.55, "WallD", "-z +z")
    b.abox(2.2, 5.0, y1, y1 + 1.8, 2.55, 2.72, "WallD", "-y")
    b.pq([(2.1, y1, 3.15), (5.1, y1, 3.15), (5.1, y1 + 1.95, 2.72), (2.1, y1 + 1.95, 2.72)], (0, 0.2, 1), "RoofTile")
    b.pq([(2.1, y1, 2.72), (5.1, y1, 2.72), (5.1, y1 + 1.95, 2.72), (2.1, y1 + 1.95, 2.72)], (0, 0, -1), "WallD")
    for sx, x in ((-1, 2.1), (1, 5.1)):
        b.pq([(x, y1, 3.15), (x, y1 + 1.95, 2.72), (x, y1, 2.72)], (sx, 0, 0), "Trim")
    # roofs
    hip_roof(b, 2.75, 0.0, mx1 - mx0, y1 - y0, 0.6, 2.66, 4.5)
    hip_roof(b, -3.5, 0.0, mx0 - gx0, y1 - y0, 0.55, 2.66, 3.95)
    chimney(b, 5.1, -1.4, 3.0, 5.4, 0.8, 0.9)
    # driveway apron
    b.abox(-5.6, -1.4, y1, y1 + 2.2, 0, 0.05, "Concrete", "-z -y")


# ----------------------------------------------------------------------------------------------------------------
def duplex_unit(b, acc):
    """One unit of the duplex on the +X side: x 0..7, y -4.5..4.5, two storeys, front gable. acc = accent wall material."""
    hy = 4.5
    H1, H2 = 2.9, 5.6
    b.abox(0.0, 7.08, -hy - 0.08, hy + 0.08, 0, 0.4, "Concrete", "-z -x")
    F = WallRef(b, "y", hy, 1)
    Bk = WallRef(b, "y", -hy, -1)
    R = WallRef(b, "x", 7.0, 1)
    door = (0.9, 1.9, 0.5, 2.55)
    gw = (3.3, 5.7, 0.95, 2.35)
    uw = [(0.7, 2.3, 3.7, 5.0), (3.5, 5.5, 3.7, 5.0)]
    F.wall(0.0, 7.0, 0.4, H2, [door, gw] + uw, "WallA")
    F.door(door, leaf=acc)
    F.window(gw, cross=2, lintel=True)
    for w in uw:
        F.window(w, cross=1, lintel=True)
    # accent bay band + planter
    F.box(2.6, 6.2, 0, 0.1, 0.4, 0.95, acc, "-d -z")
    F.box(0.0, 7.0, 0, 0.09, H1 + 0.0, H1 + 0.2, "WallD", "-d -z -u")
    bw = [(1.0, 2.2, 0.95, 2.35), (4.2, 5.8, 0.95, 2.35), (0.8, 2.4, 3.7, 5.0), (4.0, 5.8, 3.7, 5.0)]
    Bk.wall(0.0, 7.0, 0.4, H2, bw, "WallA")
    for w in bw:
        Bk.window(w, cross=1, bar=False, sill=False)
    sw = [(-3.0, -1.4, 0.95, 2.35), (1.4, 3.0, 0.95, 2.35), (-3.0, -1.4, 3.7, 5.0), (1.4, 3.0, 3.7, 5.0)]
    R.wall(-hy, hy, 0.4, H2, sw, "WallA")
    for w in sw:
        R.window(w, cross=1, lintel=False, bar=False)
    # porch canopy over the door + step + posts
    b.abox(0.5, 2.7, hy, hy + 1.3, 2.62, 2.78, acc, "-y")
    b.abox(0.6, 2.4, hy, hy + 1.2, 0, 0.5, "Concrete", "-y -z -x")
    b.abox(0.9, 1.9, hy + 1.2, hy + 1.6, 0, 0.25, "Concrete", "-y -z")
    b.abox(2.45, 2.65, hy + 1.1, hy + 1.3, 0.5, 2.62, "WallD", "-z +z")
    b.abox(0.55, 0.75, hy + 1.1, hy + 1.3, 0.5, 2.62, "WallD", "-z +z")
    # roof (front gable), ridge along Y at x=3.5
    gable_y(b, -hy, hy, 3.5, 0.5, 5.45, 7.7, xc=3.5)
    G = WallRef(b, "y", hy, 1)
    G.rect(0.006, 3.0, 4.0, 6.1, 6.85, "Window", 1)
    for (u0, u1, z0, z1) in ((2.92, 4.08, 6.85, 6.93), (2.92, 4.08, 6.02, 6.1), (2.92, 3.0, 6.1, 6.85), (4.0, 4.08, 6.1, 6.85)):
        G.rect(0.01, u0, u1, z0, z1, "Trim", 1)
    chimney(b, 6.3, -2.5, 4.9, 8.2, 0.7, 0.8)


def house_duplex(b):
    """Two-unit townhouse 14 x 9 m: unit built on +X, mirrored to -X (different accent colour)."""
    before = set(b.bm.faces)
    duplex_unit(b, "WallB")
    mirror_new(b, before, {"WallB": "WallC"})


# ----------------------------------------------------------------------------------------------------------------
def house_apartment_small(b):
    """4-storey walk-up 20 x 14 m with stoop, balconies, parapet and stair bulkhead (single mesh, kit-style bays)."""
    hx, hy = 10.0, 7.0
    G, FL = 3.6, 3.3
    top = G + 3 * FL
    b.abox(-hx - 0.1, hx + 0.1, -hy - 0.1, hy + 0.1, 0, 0.5, "Concrete", "-z")
    F, Bk, L, R = _walls4(b, hx, hy)
    bays = [-8, -4, 0, 4, 8]
    front_holes, back_holes = [], []
    door = (-0.8, 0.8, 0.55, 2.95)
    front_holes.append(door)
    wins = []
    for cx in bays:
        if cx != 0:
            wins.append((cx - 0.9, cx + 0.9, 1.1, 2.7))
    for f in range(3):
        z0 = G + f * FL
        for cx in bays:
            if cx == 0:
                continue
            if f >= 1 and cx in (-4, 4):
                wins.append(("bal", cx, z0))
            else:
                wins.append((cx - 0.9, cx + 0.9, z0 + 0.85, z0 + 2.35))
    stair = (-0.9, 0.9, G + 0.5, top - 0.6)
    holes = [door, stair]
    for w in wins:
        if w[0] == "bal":
            holes.append((w[1] - 0.75, w[1] + 0.75, w[2] + 0.18, w[2] + 2.5))
        else:
            holes.append(w)
    F.wall(-hx, hx, 0.5, top, holes, "WallA")
    F.door(door, leaf="WallC")
    F.window(stair, depth=0.16, frame=False, sill=False, reveal="lrt")
    for k in range(1, 3):
        zb = G + k * FL - 0.05
        F.box(stair[0], stair[1], -0.16, -0.1, zb, zb + 0.1, "WallD", "-d -u +u")
    F.box(stair[0] - 0.18, stair[0] - 0.02, 0, 0.06, stair[2], stair[3], "WallC", "-d -z +z")
    F.box(stair[1] + 0.02, stair[1] + 0.18, 0, 0.06, stair[2], stair[3], "WallC", "-d -z +z")
    for w in wins:
        if w[0] == "bal":
            hh = (w[1] - 0.75, w[1] + 0.75, w[2] + 0.18, w[2] + 2.5)
            F.window(hh, depth=0.18, frame=False, sill=False, reveal="lrt")
            F.box(hh[0] + 0.7, hh[0] + 0.76, -0.18, -0.12, hh[2], hh[3], "Trim", "-d -z +z")
            cx = w[1]
            z0 = w[2]
            F.box(cx - 1.8, cx + 1.8, 0, 1.3, z0, z0 + 0.17, "Concrete", "-d")
            F.rect(1.29, cx - 1.75, cx + 1.75, z0 + 0.2, z0 + 1.0, "Glass", 1)
            F.uface(cx - 1.75, 0.05, 1.27, z0 + 0.2, z0 + 1.0, "Glass", -1)
            F.uface(cx + 1.75, 0.05, 1.27, z0 + 0.2, z0 + 1.0, "Glass", 1)
            F.box(cx - 1.78, cx + 1.78, 1.25, 1.33, z0 + 1.0, z0 + 1.07, "Metal", "")
        else:
            F.window(w, depth=0.14, frame=False, sill=True, reveal="lrt", sillmat="WallD")
    # brick base + bands + corner pilasters
    F.box(-hx, hx, 0, 0.1, 0.5, 1.0, "WallB", "-d -z")
    for (W_, lo, hi) in ((F, -hx, hx), (Bk, -hx, hx), (L, -hy, hy), (R, -hy, hy)):
        for z in (G - 0.1, G + FL - 0.1, G + 2 * FL - 0.1):
            W_.box(lo, hi, 0, 0.08, z, z + 0.18, "WallD", "-d -z")
    # back / sides: cheap windows
    bh = []
    for f in range(4):
        z0 = 0.9 if f == 0 else G + (f - 1) * FL + 0.85
        for cx in bays:
            bh.append((cx - 0.8, cx + 0.8, z0 + (0.25 if f == 0 else 0.0), z0 + 1.5 + (0.25 if f == 0 else 0.0)))
    bk_door = (-0.7, 0.7, 0.55, 2.8)
    bh = [h for h in bh if not (abs((h[0] + h[1]) / 2) < 0.1 and h[2] < 2.0)]
    Bk.wall(-hx, hx, 0.5, top, bh + [bk_door], "WallA")
    for h in bh:
        Bk.window(h, depth=0.1, frame=False, sill=False, reveal="lrt")
    Bk.door(bk_door, leaf="WallB", glassy=False)
    Bk.box(-1.2, 1.2, 0, 1.0, 0, 0.5, "Concrete", "-d -z")
    sh = []
    for f in range(4):
        z0 = 1.1 if f == 0 else G + (f - 1) * FL + 0.85
        for cy in (-4.2, 0.0, 4.2):
            sh.append((cy - 0.7, cy + 0.7, z0, z0 + 1.5))
    for S in (L, R):
        S.wall(-hy, hy, 0.5, top, sh, "WallA")
        for h in sh:
            S.window(h, depth=0.1, frame=False, sill=False, reveal="lrt")
    # stoop, canopy, address plate
    b.abox(-1.6, 1.6, hy, hy + 1.6, 0, 0.55, "Concrete", "-y -z")
    b.abox(-1.0, 1.0, hy + 1.6, hy + 2.0, 0, 0.28, "Concrete", "-y -z")
    b.abox(-1.7, 1.7, hy, hy + 1.5, 3.05, 3.22, "Concrete", "-y")
    b.abox(-1.7, 1.7, hy + 1.5, hy + 1.56, 3.0, 3.25, "NeonCyan", "-y -x +x -z")
    for sx in (-1, 1):
        b.beamk((sx * 1.55, hy, 3.8), (sx * 1.55, hy + 1.4, 3.22), 0.025, 0.025, 4, "Metal", False)
    # parapet + cornice + stair bulkhead + roof stuff
    for (W_, lo, hi) in ((F, -hx, hx), (Bk, -hx, hx), (L, -hy, hy), (R, -hy, hy)):
        W_.box(lo - 0.15, hi + 0.15, 0, 0.3, top - 0.05, top + 0.2, "WallD", "-d -z")
        W_.box(lo, hi, -0.3, 0.02, top + 0.2, top + 0.95, "WallA", "-z")
        W_.box(lo - 0.1, hi + 0.1, -0.35, 0.12, top + 0.95, top + 1.08, "WallD", "-z")
    b.zq(top + 0.21, -hx + 0.3, hx - 0.3, -hy + 0.3, hy - 0.3, 1, "Roof")
    b.abox(-1.8, 1.8, -1.6, 1.0, top + 0.2, top + 2.6, "WallA", "-z")
    b.abox(-1.95, 1.95, -1.75, 1.15, top + 2.6, top + 2.75, "WallD", "-z")
    b.cylk((6.0, -3.0, top + 0.6), 0.5, 0.8, 6, "Metal", axis="Z", caps=True)
    b.abox(-7.5, -5.0, 2.0, 3.5, top + 0.2, top + 1.0, "Plate", "-z")
    # corner brick pilasters
    for sx in (-1, 1):
        b.abox(sx * hx - 0.12, sx * hx + 0.12, hy - 0.0, hy + 0.12, 0.5, top, "WallB", "-z +z -y")
        b.abox(sx * hx - 0.12, sx * hx + 0.12, -hy - 0.12, -hy + 0.0, 0.5, top, "WallB", "-z +z +y")


HOUSES = [
    ("bld_house_a", 5, house_a, (0.0, 7.45, 0.0), []),
    ("bld_house_b", 6, house_b, (-4.1, 5.9, 0.0), []),
    ("bld_house_c", 7, house_c, (0.0, 6.9, 0.0), []),
    ("bld_house_d", 8, house_d, (3.5, 6.4, 0.0), [("Garage", (-3.5, 6.2, 0.0))]),
    ("bld_duplex", 9, house_duplex, (1.4, 6.3, 0.0), [("Door_B", (-1.4, 6.3, 0.0))]),
    ("bld_apartment_small", 10, house_apartment_small, (0.0, 9.2, 0.0), []),
]

_only = globals().get("ONLY_HOUSES")
_built = []
for (hid, idx, fn, dloc, extras) in HOUSES:
    if _only and hid not in _only:
        continue
    root, body = make_house(hid, idx, fn, dloc, extra_empties=extras)
    st = stats(root, verbose=False)
    print("%-22s tris=%4d size=%s materials=%s" % (hid, st["tris"], st["size"], st["materials"]))
    _built.append((hid, root))
if globals().get("EXPORT_HOUSES", False):
    for hid, root in _built:
        export_glb(root, "buildings/" + hid)
