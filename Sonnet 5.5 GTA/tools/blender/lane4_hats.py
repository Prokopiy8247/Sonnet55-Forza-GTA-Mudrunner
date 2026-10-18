"""lane4_hats.py - Hat_Cap, Hat_Beanie, Hat_Police, Helmet_Tactical, Glasses_Round, Glasses_Shades (rigid to Head).
Set C4_ONLY=[...] to build a subset. Needs lane4_head.py loaded."""
_S = math.sin
_fy = lambda x, z: c4_front_y(C4_HEAD_REF, x, z)


def c4_brim(b, pts, z_top0, slope, thick, mat, y0):
    """flat tilted visor plate: pts=[(x,y)] CCW, top surface z = z_top0 - slope*(y-y0)."""
    top = [Vector((x, y, z_top0 - slope * (y - y0))) for (x, y) in pts]
    bot = [Vector((x, y, z_top0 - slope * (y - y0) - thick)) for (x, y) in pts]
    b.loft2([bot, top], mat, cap0=mat, cap1=mat)


def c4_cap():
    b = c4_new("cap")
    zb = lambda a: 1.695 + 0.03 * _S(a)
    c4_hshell(b, zb, [(0, .020), (.3, .030), (.65, .031), (.88, .023), (1, .010)], zt=1.826, mat="Accent")
    c4_brim(b, [(-.072, .105), (.072, .105), (.094, .155), (.072, .212), (-.072, .212), (-.094, .155)], 1.730, 0.10, .007, "Trim", .10)
    b.cur = T_HEAD
    b.cyl((0, -.002, 1.829), .014, .010, 6, "Trim")
    return c4_finish(b, "Hat_Cap", rigid="Head")


def c4_beanie():
    b = c4_new("beanie")
    zb = lambda a: 1.625 + 0.07 * max(0.0, _S(a)) + 0.04 * min(0.0, _S(a))
    c4_hshell(b, zb, [(0, .031), (.1, .037), (.11, .035), (.45, .038), (.7, .034), (.9, .024), (1, .010)], zt=1.832,
              mat=["Trim", "Trim", "Accent", "Accent", "Accent", "Accent"])
    b.sphere((0, -.004, 1.842), .026, 8, 4, "Trim")
    return c4_finish(b, "Hat_Beanie", rigid="Head")


def c4_police():
    b = c4_new("police")
    rings = []
    for z, off in ((1.706, .026), (1.742, .030), (1.776, .046), (1.792, .060), (1.798, .052)):
        rings.append([c4_hp(2 * math.pi * i / 12, z, off) for i in range(12)])
    b.loft2(rings, ["Trim", "Accent", "Accent", "Accent"], cap1="Accent")
    c4_brim(b, [(-.062, .115), (.062, .115), (.088, .168), (.074, .222), (-.074, .222), (-.088, .168)], 1.716, 0.05, .006, "Trim", .115)
    yb = c4_hp(math.pi / 2, 1.748, .031).y
    b.box((0, yb + .004, 1.752), (.040, .010, .044), "Chrome")
    b.cur = T_HEAD
    return c4_finish(b, "Hat_Police", rigid="Head")


def c4_helmet():
    b = c4_new("helmet")
    zb = lambda a: 1.62 + 0.115 * max(0.0, _S(a)) ** 0.6 + 0.02 * min(0.0, _S(a))
    c4_hshell(b, zb, [(0, .030), (.25, .040), (.6, .041), (.85, .031), (1, .012)], zt=1.832, mat="Gun")
    # side ear guards / rails / NVG mount
    for s in (1, -1):
        b.box((s * (c4_interp_rings(C4_HEAD_REF, 1.655)[0] + .046), .0, 1.66), (.014, .085, .06), "Trim")
        b.box((s * .02, .0, 1.846), (.012, .21, .010), "Trim")
    b.box((0, .115, 1.795), (.05, .03, .028), "Trim")
    # visor
    c4_hshell(b, lambda a: 1.628, [(0, .054), (.5, .058), (1, .052)], zt=1.722, mat="Glass", n=8, arc=(math.radians(32), math.radians(148)))
    return c4_finish(b, "Helmet_Tactical", rigid="Head")


def c4_circle_rim(b, c, r, thick=.0035, seg=10, mat="Trim"):
    rings = []
    for i in range(seg):
        th = 2 * math.pi * i / seg
        rad = Vector((math.cos(th), 0, math.sin(th)))
        ctr = Vector(c) + rad * r
        ring = [ctr + rad * (dr * thick) + C4_Y * (dy * thick) for (dr, dy) in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
        rings.append(ring)
    b.loft2(rings, mat, wrap=True)


def c4_glasses_round():
    b = c4_new("gr")
    for s in (1, -1):
        x = s * .040
        y = _fy(x, 1.670) + .012
        c4_circle_rim(b, (x, y, 1.670), .028, seg=10)
        # lens
        pts = [Vector((x + .026 * math.cos(2 * math.pi * i / 10), y, 1.670 + .026 * math.sin(2 * math.pi * i / 10))) for i in range(10)]
        b.face([b.v(p) for p in pts], "Glass")
        b.face([b.v(p) for p in reversed(pts)], "Glass")
        # temple arm
        b.beam((x + s * .028, y, 1.672), (s * .106, .015, 1.672), .0032, .0032, 4, "Trim")
    b.box((0, _fy(0, 1.674) + .014, 1.676), (.030, .006, .006), "Trim")
    return c4_finish(b, "Glasses_Round", rigid="Head")


def c4_glasses_shades():
    b = c4_new("gs")
    for s in (1, -1):
        x = s * .040
        y = _fy(x, 1.670) + .013
        b.block((x, y), 1.652, 1.690, (.056, .010), (.062, .010), "Glass")
        b.beam((x + s * .031, y, 1.676), (s * .106, .015, 1.676), .0035, .0035, 4, "Trim")
        b.box((x, y + .0005, 1.6925), (.066, .013, .008), "Trim")
        b.box((x, y + .0005, 1.6505), (.060, .013, .004), "Trim")
    b.box((0, _fy(0, 1.676) + .014, 1.678), (.030, .010, .010), "Trim")
    b.box((0, _fy(0, 1.690) + .013, 1.6925), (.030, .013, .008), "Trim")
    return c4_finish(b, "Glasses_Shades", rigid="Head")


_all = dict(Hat_Cap=c4_cap, Hat_Beanie=c4_beanie, Hat_Police=c4_police, Helmet_Tactical=c4_helmet,
            Glasses_Round=c4_glasses_round, Glasses_Shades=c4_glasses_shades)
for _n in globals().get("C4_ONLY", list(_all.keys())):
    _o = _all[_n]()
    print(_n, "tris", c4_tris(_o), "inv", sum(1 for (_f, _v, _e) in c4_islands(_o) if _v < 0), "open_e", sum(_e for (_f, _v, _e) in c4_islands(_o)))
