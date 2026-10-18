"""lane4_gear.py - Vest_Armor, Vest_Tactical, Jacket_Short, Jacket_Long, Backpack. Needs lane4_lib/body/head loaded.
Shells use the max envelope of the three body types (A/B/C) so they fit all of them. C4_ONLY=[...] builds a subset."""
_S = math.sin
_Q = 45.0 * math.pi / 180


def c4_env(z):
    """(z, rx, ry, cy) envelope over Body A/B/C torso at height z."""
    rx = 0.0; front = -9; back = 9
    for k in ("A", "B", "C"):
        a, b_, c = c4_interp_rings(C4_BODY[k]["torso"], z)
        rx = max(rx, a); front = max(front, c + b_); back = min(back, c - b_)
    return (z, rx, (front - back) / 2, (front + back) / 2)


def c4_shell_torso(b, zs, margin, mats, n=12, extra=None, tag=T_TORSO):
    b.cur = tag
    rings = []
    for z in zs:
        e = extra(z) if extra else None
        if e is not None:
            _, rx, ry, cy = e
        else:
            _, rx, ry, cy = c4_env(z)
        rings.append(c4_ring((0, cy, z), C4_X, C4_Y, rx + margin, ry + margin, n, 0.0, 2.3))
    return b.loft2(rings, mats)


def c4_straps(b, zfront, zback, margin, mat, wide=.058, thick=.011, xs=.115):
    b.cur = T_TORSO
    for s in (1, -1):
        x = s * xs
        path = [(x, .098 + margin, zfront), (x, .082 + margin, 1.425), (x, .045, 1.462 + margin), (x, -.045, 1.462 + margin),
                (x, -.082 - margin, 1.425), (x, -.098 - margin, zback)]
        c4_tube(b, path, [thick] * len(path), 4, mat, True, wide / thick, _Q)


def c4_neck_collar(b, r0, r1, z0, z1, mat, n=10, cy=.004):
    b.cur = T_TORSO
    rings = [c4_ring((0, cy, z0), C4_X, C4_Y, r0, r0 * .94, n), c4_ring((0, cy, z1), C4_X, C4_Y, r1, r1 * .94, n)]
    inner = [c4_ring((0, cy, z1), C4_X, C4_Y, r1 - .012, (r1 - .012) * .94, n), c4_ring((0, cy, z0), C4_X, C4_Y, r0 - .012, (r0 - .012) * .94, n)]
    b.loft2(rings + inner, mat, wrap=True)


def c4_vest_armor():
    b = CB("va")
    zs = [1.03, 1.12, 1.21, 1.30, 1.37]
    c4_shell_torso(b, zs, .012, ["Accent", "Trim", "Trim", "Accent"])
    c4_straps(b, 1.36, 1.36, .010, "Trim", .05, .008)
    e = c4_env(1.28)
    yf = e[3] + e[2] + .012
    yb = e[3] - e[2] - .012
    b.cur = T_TORSO
    b.box((0, yf + .005, 1.255), (.18, .012, .20), "Accent")
    b.box((0, yb - .005, 1.255), (.18, .012, .20), "Accent")
    return c4_finish(b, "Vest_Armor")


def c4_vest_tactical():
    b = CB("vt")
    zs = [1.00, 1.07, 1.14, 1.22, 1.30, 1.38]
    c4_shell_torso(b, zs, .026, ["Accent", "Trim", "Trim", "Trim", "Trim"])
    c4_straps(b, 1.37, 1.37, .024, "Trim", .07, .015, xs=.12)
    e = c4_env(1.12)
    yf = e[3] + e[2] + .026
    b.cur = T_TORSO
    for x in (-.085, 0.0, .085):
        b.box((x, yf + .016, 1.115), (.07, .036, .085), "Accent")
    e2 = c4_env(1.27)
    yf2 = e2[3] + e2[2] + .026
    yb2 = e2[3] - e2[2] - .026
    b.box((0, yf2 + .01, 1.27), (.22, .022, .20), "Trim")
    b.box((-.17, yf2 - .005, 1.30), (.05, .03, .09), "Accent")
    b.box((0, yb2 - .014, 1.24), (.26, .028, .30), "Trim")
    for s in (1, -1):
        b.box((s * .205, 0.0, 1.455), (.07, .13, .02), "Trim")
    c4_neck_collar(b, .075, .062, 1.455, 1.505, "Trim", 10)
    return c4_finish(b, "Vest_Tactical")


def c4_sleeve(b, sx, u0, u1, extra, mats, nseg=4, sc=1.30):
    b.cur = T_ARM_R if sx > 0 else T_ARM_L
    S = Vector((0.19 * sx, 0, 1.40)); E = Vector((0.30 * sx, 0, 1.12))
    W = Vector((0.40 * sx, 0, 0.87))
    L0 = (E - S).length; L1 = (W - E).length
    d0 = (E - S) / L0; d1 = (W - E) / L1
    prof = [(u, r) for (u, r, m) in C4_ARM_PROF]

    def rad(u):
        if u <= prof[0][0]:
            return prof[0][1]
        for i in range(len(prof) - 1):
            if prof[i][0] <= u <= prof[i + 1][0]:
                t = (u - prof[i][0]) / max(1e-9, prof[i + 1][0] - prof[i][0])
                return prof[i][1] + (prof[i + 1][1] - prof[i][1]) * t
        return prof[-1][1]
    us = [u0 + (u1 - u0) * i / nseg for i in range(nseg + 1)]
    rings = []
    for u in us:
        if u <= L0:
            c = S + d0 * u; d = d0
        else:
            c = E + d1 * (u - L0); d = d1
        uv = C4_Y.cross(d).normalized()
        r = rad(u) * sc + extra
        rings.append(c4_ring(c, uv, C4_Y, r * .97, r, 8))
    b.loft2(rings, mats)


def c4_coat_weights(part, p):
    w = c4_weights(part, p)
    if part == T_TORSO and p.z < 0.97:
        f = c4_sm((0.97 - p.z) / 0.22) * c4_sm(abs(p.x) / 0.12)
        s = "_R" if p.x >= 0 else "_L"
        return {"Hips": 1.0 - f, "UpperLeg" + s: f}
    return w


def c4_jacket(long=False):
    b = CB("jl" if long else "js")
    mats_s = ["Shirt", "Shirt", "Shirt", "Accent"]
    if long:
        rows = {0.66: (0.66, .236, .152, .0), 0.78: (0.78, .228, .146, .0), 0.92: (0.92, .214, .140, .0)}
        zs = [0.66, 0.78, 0.92, 1.10, 1.25, 1.385, 1.466]
        c4_shell_torso(b, zs, .024, ["Accent", "Shirt", "Shirt", "Shirt", "Shirt", "Shirt"], extra=lambda z: rows.get(z))
        wfn = c4_coat_weights
        ez = 1.10
    else:
        zs = [0.98, 1.06, 1.16, 1.27, 1.385, 1.466]
        c4_shell_torso(b, zs, .022, ["Accent", "Shirt", "Shirt", "Shirt", "Shirt"])
        wfn = None
        ez = 1.17
    c4_sleeve(b, 1, 0.0, 0.50, .016, mats_s)
    c4_sleeve(b, -1, 0.0, 0.50, .016, mats_s)
    c4_neck_collar(b, .11, .088, 1.45, 1.52, "Accent", 10)
    e = c4_env(1.10)
    b.cur = T_TORSO
    b.box((0, e[3] + e[2] + .027, ez), (.03, .008, .42), "Accent")
    if long:
        b.box((0, e[3] + e[2] + .031, 0.82), (.03, .008, .28), "Accent")
    return c4_finish(b, "Jacket_Long" if long else "Jacket_Short", wfn=wfn)


def c4_backpack():
    b = CB("bp")
    b.cur = T_TORSO
    b.block((0, -.225), 0.99, 1.40, (.31, .17), (.27, .14), "Accent", top_shift=(0, -.004))
    b.block((0, -.215), 1.36, 1.43, (.25, .13), (.21, .10), "Accent")
    b.box((0, -.318, 1.08), (.22, .05, .20), "Trim")
    b.box((0, -.30, 1.30), (.24, .014, .16), "Trim")
    for s in (1, -1):
        c4_tube(b, [(s * .105, -.16, 1.40), (s * .105, -.10, 1.482), (s * .11, .0, 1.482), (s * .115, .085, 1.44), (s * .12, .115, 1.33),
                    (s * .12, .125, 1.20)], [.010] * 6, 4, "Trim", True, 5.0, _Q)
        c4_tube(b, [(s * .17, -.15, 1.16), (s * .21, -.0, 1.18), (s * .17, .105, 1.20)], [.009] * 3, 4, "Trim", True, 4.0, _Q)
    b.box((0, .128, 1.28), (.23, .008, .03), "Trim")
    return c4_finish(b, "Backpack", rigid="Chest")


_all = dict(Vest_Armor=c4_vest_armor, Vest_Tactical=c4_vest_tactical, Jacket_Short=lambda: c4_jacket(False),
            Jacket_Long=lambda: c4_jacket(True), Backpack=c4_backpack)
for _n in globals().get("C4_ONLY", list(_all.keys())):
    _o = _all[_n]()
    print(_n, "tris", c4_tris(_o), "inv", sum(1 for (_f, _v, _e) in c4_islands(_o) if _v < 0), "open_e", sum(_e for (_f, _v, _e) in c4_islands(_o)))
