"""lane10_pickups_a.py - pickup_cash, pickup_health, pickup_armor, pickup_ammo, pickup_weapon, pickup_parachute.
Small floating-friendly pickups (~0.3-0.5 m), origin = base centre, front = +Y, emissive Pickup* accents so they read at night."""
import math, random

PROPS = VFX


def rbox(b, c, size, rot, mat, z_extra=0.0):
    """Axis-extruded rotated rectangle (12 tris): centre c=(x,y,z), size=(sx, sy, sz), rot = degrees about Z."""
    cs, sn = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    hx, hy = size[0] / 2, size[1] / 2
    pts = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    q = [(c[0] + x * cs - y * sn, c[1] + x * sn + y * cs) for x, y in pts]
    b.prism(q, c[2] - size[2] / 2, c[2] + size[2] / 2, mat)


def dollar(b, cx, cy, z, mat="PickupGreen", s=1.0, th=0.006):
    """Emissive '$' glyph lying on a horizontal surface at height z (v axis = +Y)."""
    def bar(u0, u1, v0, v1):
        b.box((cx + (u0 + u1) / 2 * s, cy + (v0 + v1) / 2 * s, z + th / 2), ((u1 - u0) * s, (v1 - v0) * s, th), mat)
    bar(-0.035, 0.035, 0.04, 0.054)
    bar(-0.035, 0.035, -0.007, 0.007)
    bar(-0.035, 0.035, -0.054, -0.04)
    bar(-0.035, -0.021, 0.007, 0.04)
    bar(0.021, 0.035, -0.04, -0.007)
    bar(-0.006, 0.006, -0.068, -0.054)
    bar(-0.006, 0.006, 0.054, 0.068)


def build_pickup_cash():
    a = Asset("pickup_cash", PROPS)
    b = MB("pickup_cash_body")
    W, D, H = 0.34, 0.16, 0.08
    # layer 1: two bundles along Y; layer 2: two bundles shifted; layer 3: one bundle with a glowing $ band
    for y in (-0.085, 0.085):
        b.block((0, y), 0.0, H, (W, D), (W * 0.97, D * 0.96), mat="CashGreen")
        b.box((0, y, H / 2), (0.1, D * 1.03, H * 1.02), "Paper")
    for y, dx in ((-0.085, 0.035), (0.085, -0.03)):
        b.block((dx, y), H, 2 * H, (W, D), (W * 0.97, D * 0.96), mat="CashDark" if y < 0 else "CashGreen")
        b.box((dx, y, H * 1.5), (0.1, D * 1.03, H * 1.02), "Paper")
    b.block((0.0, 0.0), 2 * H, 3 * H, (W, D), (W * 0.97, D * 0.96), mat="CashGreen")
    b.box((0, 0, H * 2.5), (0.13, D * 1.03, H * 1.02), "PickupGreen")
    dollar(b, 0, 0, 3 * H, "CashDark", s=1.0, th=0.006)
    # loose notes at the base
    rbox(b, (0.2, 0.19, 0.003), (0.14, 0.07, 0.006), 25, "CashDark")
    rbox(b, (-0.2, -0.2, 0.003), (0.14, 0.07, 0.006), -18, "CashGreen")
    rbox(b, (0.2, -0.2, 0.003), (0.13, 0.065, 0.006), 70, "CashGreen")
    a.mesh(b, "Body")
    a.report()
    return a


def build_pickup_health():
    a = Asset("pickup_health", PROPS)
    b = MB("pickup_health_body")
    W, D, H = 0.38, 0.16, 0.26
    cbox(b, (0, 0, H / 2), (W, D, H), c=0.028, mat="MedWhite")
    b.block((0, 0), H * 0.62, H * 0.62 + 0.012, (W * 1.012, D * 1.03), None, mat="VestSteel")       # lid seam
    # carry handle
    for sx in (-1, 1):
        b.box((sx * 0.1, 0, H + 0.02), (0.022, 0.04, 0.05), "Metal")
    b.box((0, 0, H + 0.046), (0.222, 0.04, 0.02), "Metal")
    # latches
    for sx in (-1, 1):
        b.box((sx * 0.13, D / 2 + 0.006, H * 0.62), (0.05, 0.014, 0.05), "Metal")
    # red cross on both faces (emissive)
    cross = [(-0.025, -0.075), (0.025, -0.075), (0.025, -0.025), (0.075, -0.025), (0.075, 0.025), (0.025, 0.025),
             (0.025, 0.075), (-0.025, 0.075), (-0.025, 0.025), (-0.075, 0.025), (-0.075, -0.025), (-0.025, -0.025)]
    cz = H * 0.34
    slab(b, [(x, y + cz) for x, y in cross], "xz", D / 2 - 0.004, D / 2 + 0.01, "PickupRed")
    slab(b, [(x, y + cz) for x, y in cross], "xz", -D / 2 - 0.01, -D / 2 + 0.004, "PickupRed")
    a.mesh(b, "Body")
    a.report()
    return a


def vest_outline(s=1.0):
    pts = [(-0.2, 0.0), (0.2, 0.0), (0.22, 0.06), (0.22, 0.28), (0.18, 0.34), (0.17, 0.5), (0.08, 0.5), (0.05, 0.42), (0.0, 0.36),
           (-0.05, 0.42), (-0.08, 0.5), (-0.17, 0.5), (-0.18, 0.34), (-0.22, 0.28), (-0.22, 0.06)]
    return [(x * s, z * s) for x, z in pts]


def build_pickup_armor():
    a = Asset("pickup_armor", PROPS)
    b = MB("pickup_armor_body")
    out = vest_outline()
    slab(b, out, "xz", 0.025, 0.065, "VestNavy")           # front shell
    slab(b, out, "xz", -0.065, -0.025, "VestNavy")         # back shell
    for sx in (-1, 1):
        b.box((sx * 0.125, 0, 0.485), (0.09, 0.13, 0.03), "VestNavy")           # shoulder straps joining front/back
        b.box((sx * 0.215, 0, 0.17), (0.026, 0.13, 0.22), "VestSteel")           # side cummerbund
    # chest plate + emissive shield icon
    slab(b, [(-0.1, 0.14), (0.1, 0.14), (0.12, 0.2), (0.12, 0.34), (0.06, 0.4), (-0.06, 0.4), (-0.12, 0.34), (-0.12, 0.2)], "xz", 0.065, 0.082, "VestSteel")
    slab(b, [(-0.06, 0.2), (0.06, 0.2), (0.06, 0.31), (0.0, 0.36), (-0.06, 0.31)], "xz", 0.082, 0.09, "PickupBlue")
    slab(b, [(-0.1, 0.14), (0.1, 0.14), (0.12, 0.2), (-0.12, 0.2)], "xz", -0.082, -0.065, "VestSteel")
    # glowing hem + pouches
    b.box((0, 0.07, 0.012), (0.34, 0.016, 0.014), "PickupBlue")
    b.box((0, -0.07, 0.012), (0.34, 0.016, 0.014), "PickupBlue")
    for sx in (-1, 1):
        b.box((sx * 0.1, 0.078, 0.075), (0.09, 0.03, 0.07), "VestNavy")
        b.box((sx * 0.1, 0.095, 0.1), (0.09, 0.006, 0.012), "PickupBlue")
    a.mesh(b, "Body")
    a.report()
    return a


def build_pickup_ammo():
    a = Asset("pickup_ammo", PROPS)
    b = MB("pickup_ammo_body")
    W, D, H = 0.38, 0.2, 0.2
    cbox(b, (0, 0, H / 2), (W, D, H), c=0.02, mat="Olive")
    b.block((0, 0), H, H + 0.04, (W * 1.03, D * 1.04), (W * 0.97, D * 0.95), mat="OliveDark")
    for sx in (-1, 1):
        b.box((sx * 0.075, 0, H + 0.065), (0.02, 0.04, 0.05), "Metal")
    b.box((0, 0, H + 0.09), (0.17, 0.04, 0.02), "Metal")
    for sx in (-1, 1):
        b.box((sx * 0.12, D / 2 + 0.008, H * 0.82), (0.045, 0.016, 0.055), "Metal")
    # emissive amber label + stencilled stripe
    b.box((0, D / 2 + 0.003, H * 0.4), (0.22, 0.008, 0.06), "PickupAmber")
    b.box((0, -D / 2 - 0.003, H * 0.4), (0.22, 0.008, 0.06), "PickupAmber")
    # three brass cartridges standing on the lid
    for x in (-0.09, 0.0, 0.09):
        b.cyl((x, -0.1 * 0.0 - 0.0, H + 0.04 + 0.05), 0.02, 0.1, 6, "Brass", axis="Z")
        cone(b, (x, 0.0, H + 0.04 + 0.1), 0.02, 0.05, seg=6, mat="Chrome", cap=False)
    a.mesh(b, "Body")
    a.report()
    return a


def pistol_icon(b, y0, y1, flip, zc, s=1.0, mat="PickupCyan"):
    P = [(-0.085, -0.06), (-0.045, -0.06), (-0.04, -0.012), (-0.005, -0.012), (0.01, -0.04), (0.03, -0.04), (0.025, 0.0),
         (0.10, 0.0), (0.10, 0.045), (-0.10, 0.045), (-0.10, 0.02)]
    pts = [((-x if flip else x) * s, zc + z * s) for x, z in P]
    slab(b, pts, "xz", y0, y1, mat)


def build_pickup_weapon():
    a = Asset("pickup_weapon", PROPS)
    b = MB("pickup_weapon_body")
    W, D, H = 0.5, 0.28, 0.2
    cbox(b, (0, 0, H / 2), (W, D, H), c=0.024, mat="CrateGrey")
    for sx in (-1, 1):
        b.box((sx * 0.16, 0, H / 2), (0.045, D * 1.03, H * 1.03), "MetalDark")        # steel straps
    b.block((0, 0), H, H + 0.02, (W * 1.02, D * 1.03), (W * 0.98, D * 0.98), mat="MetalDark")
    for sx in (-1, 1):
        b.box((sx * 0.07, 0, H + 0.04), (0.02, 0.05, 0.04), "Metal")
    b.box((0, 0, H + 0.06), (0.164, 0.05, 0.02), "Metal")
    for sx in (-1, 1):
        b.box((sx * 0.07, D / 2 + 0.008, H * 0.8), (0.045, 0.016, 0.05), "Metal")
    # emissive pistol badge on dark plates, front and back
    b.box((0, D / 2 + 0.002, H * 0.45), (0.26, 0.004, 0.13), "Trim")
    b.box((0, -D / 2 - 0.002, H * 0.45), (0.26, 0.004, 0.13), "Trim")
    pistol_icon(b, D / 2 + 0.004, D / 2 + 0.011, False, H * 0.45 - 0.003, 0.85)
    pistol_icon(b, -D / 2 - 0.011, -D / 2 - 0.004, True, H * 0.45 - 0.003, 0.85)
    a.mesh(b, "Body")
    a.report()
    return a


def build_pickup_parachute():
    a = Asset("pickup_parachute", PROPS)
    b = MB("pickup_parachute_body")
    W, D, H = 0.34, 0.16, 0.4
    cbox(b, (0, 0, 0.06 + H / 2), (W, D, H), c=0.034, mat="PackOrange")
    b.block((0, 0), 0.06 + H, 0.06 + H + 0.03, (W * 0.96, D * 0.96), (W * 0.84, D * 0.82), mat="PackNavy")
    # shoulder straps looping over the top and down the front
    for sx in (-1, 1):
        x = sx * 0.1
        b.beam((x, 0.02, 0.5), (x, 0.0, 0.54), 0.017, 0.017, 4, "Strap")
        b.beam((x, 0.0, 0.54), (x, -0.1, 0.5), 0.017, 0.017, 4, "Strap")
        b.beam((x, -0.1, 0.5), (x, -0.11, 0.18), 0.017, 0.017, 4, "Strap")
        b.box((sx * 0.13, D / 2 + 0.004, 0.26), (0.012, 0.008, 0.3), "PickupAmber")
    b.box((0, -0.112, 0.34), (0.2, 0.02, 0.022), "Strap")
    b.box((0, -0.124, 0.34), (0.05, 0.012, 0.04), "Chrome")
    # glowing parachute emblem on the pack front
    slab(b, [(-0.075, 0.33), (-0.06, 0.375), (-0.03, 0.4), (0.03, 0.4), (0.06, 0.375), (0.075, 0.33), (0.045, 0.34), (0.0, 0.325), (-0.045, 0.34)], "xz",
         D / 2 - 0.002, D / 2 + 0.008, "PickupAmber")
    for x in (-0.05, 0.0, 0.05):
        b.beam((x * 0.9, D / 2 + 0.002, 0.33), (0, D / 2 + 0.002, 0.2), 0.006, 0.006, 3, "PickupAmber", caps=False)
    # ripcord handle (emissive red) on the lower front
    b.box((0.1, D / 2 + 0.012, 0.16), (0.05, 0.016, 0.045), "PickupRed")
    b.beam((0.1, D / 2 + 0.01, 0.18), (0.1, D / 2 + 0.01, 0.3), 0.006, 0.006, 3, "Strap", caps=False)
    b.translate((0, 0, -0.06))        # pack sits on the ground plane (origin = base centre)
    a.mesh(b, "Body")
    a.report()
    return a


BUILDERS = {"pickup_cash": build_pickup_cash, "pickup_health": build_pickup_health, "pickup_armor": build_pickup_armor,
            "pickup_ammo": build_pickup_ammo, "pickup_weapon": build_pickup_weapon, "pickup_parachute": build_pickup_parachute}
run_builders(BUILDERS, globals().get("ONLY"))
