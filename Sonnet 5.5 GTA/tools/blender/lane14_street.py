"""lane14_street.py - helipad_pad, vending_machine, atm_machine (street props). Front = Blender +Y (-Z Godot).
helipad_pad: origin = centre of the TOP surface (z = 0 top, slab below).  vending_machine / atm_machine: origin = footprint centre on the ground.
Set ONLY=[...] before exec to build a subset."""
import math
from mathutils import Vector

CATS = "GTA_GODOT/StreetProps"


# ------------------------------------------------------------------------------------------------------------------------------ helipad
def build_helipad_pad():
    A = A14("helipad_pad", 18, CATS, spacing=14.0)
    b = HB("helipad_pad_body")
    S, TH = 5.0, 0.15
    b.zq(0.0, -S, S, -S, S, 1, "HeliPad")                                   # top
    for (sx, sy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):                     # sides
        if sx:
            b.xq(sx * S, -S, S, -TH, 0.0, sx, "HeliPadDk")
        else:
            b.yq(sy * S, -S, S, -TH, 0.0, sy, "HeliPadDk")
    b.zq(-TH, -S, S, -S, S, -1, "HeliPadDk")
    # painted yellow border line, inset 0.3 m
    o, w = S - 0.3, 0.22
    b.zq(0.01, -o, o, -o, -o + w, 1, "HeliYellow")
    b.zq(0.01, -o, o, o - w, o, 1, "HeliYellow")
    b.zq(0.01, -o, -o + w, -o + w, o - w, 1, "HeliYellow")
    b.zq(0.01, o - w, o, -o + w, o - w, 1, "HeliYellow")
    # yellow ring + white H (raised 3 cm so it never z-fights at range)
    b.annulus((0, 0, 0.012), 3.65, 4.1, 24, 1, "HeliYellow")
    b.abox(-0.98, -0.5, -1.5, 1.5, 0.0, 0.028, "HeliWhite", "-z")
    b.abox(0.5, 0.98, -1.5, 1.5, 0.0, 0.028, "HeliWhite", "-z")
    b.abox(-0.5, 0.5, -0.24, 0.24, 0.0, 0.028, "HeliWhite", "-z")
    # LampGlow edge lights: 4 corners + 4 edge middles (flush 12 cm high pucks)
    pos = [(sx * 4.6, sy * 4.6) for sx in (-1, 1) for sy in (-1, 1)] + [(4.6, 0), (-4.6, 0), (0, 4.6), (0, -4.6)]
    for (x, y) in pos:
        b.cyl((x, y, 0.06), 0.21, 0.12, 6, "HeliCurb", r_top=0.15, caps="")
        b.disc((x, y, 0.12), 0.15, 6, 1, "LampGlow")
    A.mesh(b, "Body", uv=None)
    A.mark("Centre", (0, 0, 0.0), size=0.5, display="PLAIN_AXES")
    for i, (sx, sy) in enumerate([(-1, -1), (1, -1), (1, 1), (-1, 1)], start=1):
        A.mark("LightPoint_%d" % i, (sx * 4.6, sy * 4.6, 0.5), size=0.2, display="SPHERE")
    return A


# ------------------------------------------------------------------------------------------------------------------------------ vending machine
def build_vending_machine():
    A = A14("vending_machine", 19, CATS, spacing=14.0)
    b = HB("vending_machine_body")
    W, D, H = 0.9, 0.774, 1.9
    hx, hy = W / 2, D / 2
    z0, z1 = 0.1, 1.9
    b.abox(-hx + 0.04, hx - 0.04, -hy + 0.04, hy - 0.04, 0.0, z0, "VendBlueDk", "-z")                   # plinth
    # cabinet shell: sides + back + roof; front plane built with holes
    b.xq(hx, -hy, hy, z0, z1, 1, "VendBlue")
    b.xq(-hx, -hy, hy, z0, z1, -1, "VendBlue")
    b.yq(-hy, -hx, hx, z0, z1, -1, "VendBlue")
    b.zq(z1, -hx, hx, -hy, hy, 1, "VendBlueDk")
    win = (-0.40, 0.11, 0.62, 1.56)                                        # x0 x1 z0 z1 product window
    flap = (-0.36, 0.11, 0.16, 0.46)                                       # dispense pocket
    for r in rects_with_holes(-hx, hx, z0, z1, [win, flap]):
        b.yq(hy, r[0], r[1], r[2], r[3], 1, "VendBlue")
    # recesses
    dep = 0.12
    for (h_, back_m) in ((win, "VendPanel"), (flap, "AtmSlot")):
        x0, x1, za, zb = h_
        b.yq(hy - dep, x0, x1, za, zb, 1, back_m)
        b.xq(x0, hy - dep, hy, za, zb, 1, "VendBlueDk")
        b.xq(x1, hy - dep, hy, za, zb, -1, "VendBlueDk")
        b.zq(za, x0, x1, hy - dep, hy, 1, "VendBlueDk")
        b.zq(zb, x0, x1, hy - dep, hy, -1, "VendBlueDk")
    b.yq(hy + 0.006, win[0], win[1], win[2], win[3], 1, "Glass")           # glass pane
    # shelves + products (front-facing blocks, 4 shelves x 5 items)
    cols = ["VendCan1", "VendCan2", "VendCan3", "VendCan4", "VendSnackA", "VendSnackB", "VendSnackC"]
    xs = [win[0] + 0.065 + i * 0.1 for i in range(5)]
    for si, zs in enumerate((0.68, 0.94, 1.2, 1.46)):
        b.abox(win[0], win[1], hy - dep, hy - 0.02, zs - 0.015, zs + 0.01, "VendShelf")
        for ii, xc in enumerate(xs):
            m = cols[(si * 3 + ii * 2) % len(cols)]
            ht = 0.2 if (si + ii) % 2 == 0 else 0.17
            b.abox(xc - 0.042, xc + 0.042, hy - 0.085, hy - 0.04, zs + 0.01, zs + 0.01 + ht, m, "-x +x -y -z")
    # control column
    cx0, cx1 = 0.19, 0.4
    b.abox(cx0, cx1, hy, hy + 0.025, 0.74, 1.56, "VendPanel", "-y")
    b.yq(hy + 0.0262, cx0 + 0.02, cx1 - 0.02, 1.42, 1.51, 1, "NeonCyan")                                  # glowing display
    for r_ in range(4):
        for c_ in range(3):
            xb = cx0 + 0.03 + c_ * 0.05
            zb = 1.26 - r_ * 0.07
            b.yq(hy + 0.0262, xb, xb + 0.038, zb, zb + 0.045, 1, "VendShelf" if (r_ + c_) % 4 else "Neon")
    b.yq(hy + 0.0262, cx0 + 0.04, cx1 - 0.04, 0.82, 0.86, 1, "AtmSlot")                                  # coin slot
    b.yq(hy + 0.0262, cx0 + 0.05, cx1 - 0.05, 0.9, 0.93, 1, "NeonCyan")
    # header: glowing front panel + magenta underline + side stripes
    b.abox(-0.41, 0.41, hy, hy + 0.02, 1.68, 1.88, "VendBlueDk", "-y")
    b.yq(hy + 0.0212, -0.37, 0.37, 1.71, 1.85, 1, "NeonCyan")
    b.yq(hy + 0.0212, -0.41, 0.41, 1.645, 1.665, 1, "Neon")
    for sx in (-1, 1):
        b.xq(sx * (hx + 0.004), 0.1, 0.16, 0.25, 1.62, sx, "Neon")
    # coin return + pickup flap hinge bar
    b.yq(hy + 0.006, 0.2, 0.37, 0.4, 0.5, 1, "AtmSlot")
    b.yq(hy + 0.006, 0.2, 0.37, 0.28, 0.3, 1, "VendShelf")
    A.mesh(b, "Body", uv=None)
    A.mark("UsePoint", (0.0, hy + 0.55, 0.0), size=0.25, display="PLAIN_AXES")
    return A


# ------------------------------------------------------------------------------------------------------------------------------ ATM
def build_atm_machine():
    A = A14("atm_machine", 20, CATS, spacing=14.0)
    b = HB("atm_machine_body")
    hx = 0.3
    # side profile (y, z): plinth, safe body, keypad ledge, slanted screen fascia, head
    prof = [(-0.27, 0.0), (0.25, 0.0), (0.25, 0.93), (0.31, 0.98), (0.31, 1.04), (0.25, 1.07), (0.2, 1.07), (0.14, 1.52), (0.14, 1.58), (-0.27, 1.58)]
    b.ex(prof, -hx, hx, "AtmBody")
    b.abox(-hx - 0.015, hx + 0.015, -0.29, 0.27, 0.0, 0.1, "AtmBodyLt", "-z")                                      # plinth
    b.abox(-hx - 0.012, hx + 0.012, 0.248, 0.262, 0.5, 0.93, "AtmBodyLt")                                           # steel fascia plate on the safe
    # slanted screen: plane from (y 0.2, z 1.07) to (y 0.14, z 1.52); n = (0, .99, .13)
    def sp(t, x):
        return (x, 0.2 - 0.06 * t, 1.07 + 0.45 * t)
    nrm = (0, 0.99, 0.13)
    off = 0.003
    def sq(t0, t1, x0, x1, m, o):
        b.pq([(sp(t0, x0)[0], sp(t0, x0)[1] + nrm[1] * o, sp(t0, x0)[2] + nrm[2] * o), (sp(t0, x1)[0], sp(t0, x1)[1] + nrm[1] * o, sp(t0, x1)[2] + nrm[2] * o),
              (sp(t1, x1)[0], sp(t1, x1)[1] + nrm[1] * o, sp(t1, x1)[2] + nrm[2] * o), (sp(t1, x0)[0], sp(t1, x0)[1] + nrm[1] * o, sp(t1, x0)[2] + nrm[2] * o)], nrm, m)
    sq(0.06, 0.95, -0.25, 0.25, "AtmSlot", off)                                                                   # bezel
    sq(0.14, 0.9, -0.215, 0.215, "NeonScreen", off * 2)                                                           # glowing screen
    sq(0.08, 0.11, -0.2, 0.2, "AtmGreen", off * 2)                                                               # status strip under the screen
    # keypad on the ledge
    for c_ in range(3):
        for r_ in range(2):
            xk = -0.075 + c_ * 0.055
            yk = 0.268 + r_ * 0.028
            b.zq(1.0405, xk - 0.02, xk + 0.02, yk, yk + 0.022, 1, "AtmKey")
    b.zq(1.0405, 0.1, 0.2, 0.268, 0.29, 1, "AtmGreen")
    b.zq(1.0405, -0.2, -0.12, 0.268, 0.29, 1, "NeonCyan")
    # card slot, cash slot, receipt slot on the safe front
    b.yq(0.2625, -0.11, 0.11, 0.84, 0.865, 1, "AtmSlot")
    b.yq(0.2625, -0.11, 0.11, 0.872, 0.88, 1, "AtmGreen")
    b.yq(0.2625, -0.18, 0.18, 0.62, 0.7, 1, "AtmSlot")
    b.yq(0.2625, -0.18, 0.18, 0.603, 0.612, 1, "NeonCyan")
    b.yq(0.2625, 0.06, 0.2, 0.74, 0.77, 1, "AtmSlot")
    # canopy sign with blocky A T M glyphs on a glowing panel
    b.abox(-hx - 0.02, hx + 0.02, -0.28, 0.3, 1.58, 1.82, "AtmBodyLt", "-y")
    b.yq(0.3 + 0.002, -hx + 0.01, hx - 0.01, 1.61, 1.79, 1, "NeonCyan")
    g0, g1 = 1.65, 1.75
    ys = 0.3 + 0.0035

    def gl(pts):
        """glyph polygon given as (x, z) points; x is mirrored because the sign is read from +Y (the front)"""
        b.pq([(-x, ys, z) for (x, z) in pts], (0, 1, 0), "VendPanel")
    # A
    gl([(-0.25, g0), (-0.215, g0), (-0.185, g1), (-0.215, g1)])
    gl([(-0.115, g0), (-0.15, g0), (-0.185, g1), (-0.155, g1)])
    gl([(-0.225, 1.675), (-0.14, 1.675), (-0.14, 1.70), (-0.225, 1.70)])
    # T
    gl([(-0.07, 1.72), (0.07, 1.72), (0.07, g1), (-0.07, g1)])
    gl([(-0.017, g0), (0.017, g0), (0.017, 1.72), (-0.017, 1.72)])
    # M
    gl([(0.115, g0), (0.14, g0), (0.14, g1), (0.115, g1)])
    gl([(0.225, g0), (0.25, g0), (0.25, g1), (0.225, g1)])
    gl([(0.14, g1), (0.168, g1), (0.1825, 1.70), (0.1825, 1.672)])
    gl([(0.225, g1), (0.197, g1), (0.1825, 1.70), (0.1825, 1.672)])
    # light strips on the sides of the head
    for sx in (-1, 1):
        b.xq(sx * (hx + 0.001), -0.1, 0.14, 1.2, 1.5, sx, "AtmBodyLt")
    A.mesh(b, "Body", uv=None)
    A.mark("UsePoint", (0.0, 0.8, 0.0), size=0.25, display="PLAIN_AXES")
    return A


BUILD = {"helipad_pad": (build_helipad_pad, 400), "vending_machine": (build_vending_machine, 400), "atm_machine": (build_atm_machine, 400)}
for _id, (_fn, _bud) in BUILD.items():
    if globals().get("ONLY") and _id not in ONLY:
        continue
    _fn().report(_bud)
