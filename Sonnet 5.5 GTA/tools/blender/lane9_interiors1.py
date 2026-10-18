"""lane 9 - interiors batch 1: shop_counter, shelf_wall, weapon_rack_wall, gun_bench, clothing_rack, mannequin, wardrobe,
bed_double, nightstand, sofa.   Origin = base centre on the floor, front +Y.  Requires gta_lib.py + lane9_lib.py."""
IC = "Interiors"


def ni(aid, slot):
    return new_asset(aid, slot, IC)


# ------------------------------------------------------------------------------------------------ shop counter
def b_shop_counter():
    a = ni("shop_counter", 50)
    b = a.mb()
    bx(b, (-1.5, 1.5), (-0.34, 0.32), (0.1, 0.98), "Laminate")
    bx(b, (-1.46, 1.46), (-0.3, 0.28), (0.0, 0.1), "MetalDark")                               # plinth
    bx(b, (-1.56, 1.56), (-0.38, 0.42), (0.98, 1.04), "CounterTop")                            # worktop
    bx(b, (-1.45, 1.45), (0.32, 0.335), (0.9, 0.93), "NeonCyan")                               # glowing trim under the lip
    for x in (-1.0, 0.0, 1.0):                                                                  # raised front panels
        bx(b, (x - 0.42, x + 0.42), (0.32, 0.345), (0.2, 0.84), "WoodDark")
    # glass display case (left half)
    bx(b, (-1.42, -0.32), (-0.26, 0.24), (1.04, 1.08), "MetalDark")
    bx(b, (-1.42, -0.32), (-0.26, 0.24), (1.08, 1.34), "Glass")
    for x, m in ((-1.2, "FabricCoral"), (-0.85, "PaintYellow"), (-0.55, "PlateBlue")):
        bx(b, (x - 0.1, x + 0.1), (-0.12, 0.1), (1.08, 1.2), m)
    # cash register (right half)
    bx(b, (0.7, 1.1), (-0.15, 0.15), (1.04, 1.16), "MetalDark")
    b.block((0.9, 0.0), 1.16, 1.24, (0.4, 0.3), (0.34, 0.2), "Trim", top_shift=(0, -0.04))
    bx(b, (0.88, 0.92), (-0.12, -0.08), (1.24, 1.42), "MetalDark")                             # display stalk
    with xf(b, about((0.9, -0.1, 1.45), RX(-12))):
        bx(b, (0.72, 1.08), (-0.14, -0.08), (1.4, 1.62), "Trim")
        bx(b, (0.75, 1.05), (-0.08, -0.075), (1.43, 1.59), "NeonScreen")
    bx(b, (0.74, 1.06), (0.15, 0.17), (1.07, 1.13), "Metal")                                    # cash drawer front
    cylz(b, 0.45, 0.15, 1.04, 1.1, 0.05, 6, "Brass")                                            # service bell
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ shelf wall
def b_shelf_wall():
    a = ni("shelf_wall", 51)
    b = a.mb()
    H = 2.0
    bx(b, (-1.0, 1.0), (-0.21, -0.18), (0.0, H), "Laminate")                                    # back panel
    for sx in (-1, 1):
        bx(b, (sx * 0.98 - 0.02, sx * 0.98 + 0.02), (-0.21, 0.21), (0.0, H), "MetalDark")
    bx(b, (-1.0, 1.0), (-0.21, 0.21), (H, H + 0.04), "MetalDark")
    cols = ["FabricCoral", "FabricTeal", "PaintYellow", "PlateBlue", "FabricSand", "PlateGreen", "PlateRed", "Pillow"]
    k = 0
    for z in (0.1, 0.55, 0.95, 1.35, 1.75):
        bx(b, (-0.96, 0.96), (-0.18, 0.21), (z - 0.015, z + 0.015), "WoodLight")
        for i in range(3 if z > 0.2 else 2):
            xc = -0.62 + i * 0.62 + (0.08 if z in (0.95, 1.75) else -0.05)
            w = 0.30 + 0.06 * ((k + i) % 3)
            h = min(0.22 + 0.06 * ((k * 2 + i) % 4), 1.96 - (z + 0.015))
            bx(b, (xc - w / 2, xc + w / 2), (-0.12, 0.16), (z + 0.015, z + 0.015 + h), cols[k % len(cols)])
            k += 1
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ weapon rack wall
def sil(b, uv, ox, oz, y, mat, flip=False):
    pts = [(ox + (-u if flip else u), y, oz + v) for (u, v) in uv]
    b.poly(pts, mat)


RIFLE = [(0, 0.05), (0.05, 0.14), (0.28, 0.13), (0.54, 0.15), (0.56, 0.17), (0.63, 0.17), (0.64, 0.145), (0.88, 0.145), (0.9, 0.16), (1.0, 0.16),
         (1.0, 0.12), (0.9, 0.115), (0.66, 0.105), (0.62, 0.09), (0.6, 0.0), (0.5, 0.0), (0.48, 0.085), (0.42, 0.085), (0.39, 0.0), (0.32, 0.0),
         (0.33, 0.09), (0.28, 0.085), (0.06, 0.01)]
SHOTGUN = [(0, 0.05), (0.05, 0.14), (0.3, 0.13), (0.55, 0.15), (0.62, 0.15), (0.64, 0.125), (1.08, 0.125), (1.08, 0.105), (0.84, 0.105), (0.84, 0.07),
           (0.7, 0.07), (0.7, 0.105), (0.62, 0.1), (0.58, 0.0), (0.5, 0.0), (0.5, 0.09), (0.42, 0.085), (0.38, 0.0), (0.32, 0.0), (0.33, 0.09),
           (0.28, 0.085), (0.06, 0.01)]
SMG = [(0, 0.1), (0.06, 0.14), (0.14, 0.14), (0.14, 0.17), (0.44, 0.17), (0.44, 0.13), (0.52, 0.13), (0.52, 0.1), (0.44, 0.1), (0.42, 0.0), (0.34, 0.0),
       (0.34, 0.1), (0.27, 0.09), (0.26, 0.0), (0.19, 0.0), (0.2, 0.09), (0.14, 0.085)]
PISTOL = [(0.03, 0.1), (0.04, 0.15), (0.26, 0.15), (0.26, 0.1), (0.2, 0.1), (0.19, 0.07), (0.14, 0.07), (0.12, 0.0), (0.04, 0.0), (0.06, 0.1)]


def b_weapon_rack_wall():
    a = ni("weapon_rack_wall", 52)
    b = a.mb()
    bx(b, (-1.2, 1.2), (-0.04, 0.0), (0.5, 2.2), "Trim")                                        # shadow board
    for z0, z1 in ((0.5, 0.56), (2.14, 2.2)):
        bx(b, (-1.25, 1.25), (-0.05, 0.03), (z0, z1), "WoodDark")
    for sx in (-1, 1):
        bx(b, (sx * 1.22 - 0.03, sx * 1.22 + 0.03), (-0.05, 0.03), (0.5, 2.2), "WoodDark")
    S = "Concrete"
    rows = [(1.85, [(RIFLE, -1.12), (RIFLE, 0.08)]), (1.45, [(RIFLE, -1.12), (SHOTGUN, 0.08)])]
    for z, items in rows:
        for shape, x0 in items:
            sil(b, shape, x0, z, 0.006, S)
            b.beam((x0 + 0.45, 0.0, z + 0.0), (x0 + 0.45, 0.1, z + 0.0), 0.012, 0.012, 4, "Metal", False)   # peg
    for i, x in enumerate((-1.15, -0.85, -0.55, -0.25)):
        sil(b, PISTOL, x, 1.1, 0.006, S)
    sil(b, SMG, 0.14, 1.04, 0.006, S)
    sil(b, SMG, 0.66, 1.04, 0.006, S)
    bx(b, (-1.2, 1.2), (0.0, 0.2), (0.56, 0.6), "WoodDark")                                      # shelf
    for x, m in ((-0.8, "PaintYellow"), (-0.4, "Brass")):                                           # ammo boxes
        bx(b, (x - 0.12, x + 0.12), (0.04, 0.16), (0.6, 0.72), m)
    bx(b, (-1.1, 1.1), (0.0, 0.05), (2.08, 2.12), "LampGlow")                                     # strip light
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ gun bench
def b_gun_bench():
    a = ni("gun_bench", 53)
    b = a.mb()
    bx(b, (-0.9, 0.9), (-0.4, 0.4), (0.88, 0.95), "WoodLight")
    bx(b, (-0.84, 0.84), (-0.34, 0.34), (0.8, 0.88), "WoodDark")
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx(b, (sx * 0.8 - 0.04, sx * 0.8 + 0.04), (sy * 0.3 - 0.04, sy * 0.3 + 0.04), (0.0, 0.8), "MetalDark")
    bx(b, (-0.84, 0.84), (-0.34, 0.34), (0.22, 0.27), "WoodDark")                                # lower shelf
    bx(b, (-0.9, 0.9), (-0.42, -0.4), (0.95, 1.6), "Trim")                                        # pegboard
    for x in (-0.5, -0.1):                                                                          # hanging tools
        bx(b, (x - 0.02, x + 0.02), (-0.4, -0.37), (1.05, 1.4), "Metal")
    # bench vise (front-left)
    bx(b, (-0.75, -0.55), (0.18, 0.36), (0.95, 0.99), "MetalDark")
    bx(b, (-0.72, -0.58), (0.2, 0.34), (0.99, 1.07), "PaintRed")
    bx(b, (-0.73, -0.57), (0.34, 0.37), (0.99, 1.09), "Metal")                                    # fixed jaw
    bx(b, (-0.71, -0.59), (0.28, 0.31), (0.99, 1.09), "Metal")                                    # movable jaw
    b.beam((-0.65, 0.12, 1.03), (-0.65, 0.28, 1.03), 0.012, 0.012, 4, "Metal", True)              # screw
    b.beam((-0.74, 0.12, 1.03), (-0.56, 0.12, 1.03), 0.01, 0.01, 4, "Metal", True)                # handle
    # task lamp (back-right)
    cylz(b, 0.7, -0.28, 0.95, 0.98, 0.07, 6, "MetalDark")
    b.beam((0.7, -0.28, 0.98), (0.62, -0.2, 1.3), 0.012, 0.012, 4, "Metal", False)
    b.beam((0.62, -0.2, 1.3), (0.56, -0.02, 1.34), 0.012, 0.012, 4, "Metal", False)
    cylz(b, 0.56, -0.02, 1.2, 1.34, 0.02, 6, "PaintYellow", r1=0.08)
    cylz(b, 0.56, -0.02, 1.185, 1.2, 0.06, 6, "LampGlow")
    # parts tray + gun case
    bx(b, (0.15, 0.45), (0.1, 0.3), (0.95, 0.99), "MetalDark")
    bx(b, (0.15, 0.7), (-0.2, 0.0), (0.95, 1.05), "Trim")
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ clothing rack
def b_clothing_rack():
    a = ni("clothing_rack", 54)
    b = a.mb()
    for sx in (-1, 1):
        x = sx * 0.75
        bx(b, (x - 0.03, x + 0.03), (-0.3, 0.3), (0.0, 0.04), "MetalDark")
        b.beam((x, 0, 0.04), (x, 0, 1.68), 0.022, 0.022, 5, "Metal", True)
    b.beam((-0.75, 0, 1.6), (0.75, 0, 1.6), 0.018, 0.018, 5, "Chrome", False)
    # (x, kind, colour): shirt = torso + two sleeves, coat = longer, dress = tapered long block
    items = [(-0.56, "shirt", "FabricTeal"), (-0.37, "coat", "FabricNavy"), (-0.18, "shirt", "FabricCoral"), (0.02, "dress", "PaintYellow"),
             (0.22, "shirt", "FabricSand"), (0.4, "coat", "FabricGrey"), (0.58, "shirt", "PlateRed")]
    for i, (x, kind, col) in enumerate(items):
        yo = 0.05 if i % 2 else -0.05                                     # alternate depth so neighbouring garments never share a plane
        if kind == "dress":
            b.block((x, yo), 0.82, 1.57, (0.34, 0.07), (0.2, 0.05), col)
            continue
        h = 0.62 if kind == "shirt" else 0.95
        b.block((x, yo), 1.57 - h, 1.57, (0.3, 0.07), (0.24, 0.06), col)
        for sx in (-1, 1):
            sl = 0.3 if kind == "shirt" else 0.5
            bx(b, (x + sx * 0.18 - 0.03, x + sx * 0.18 + 0.03), (yo - 0.035, yo + 0.035), (1.57 - sl, 1.57), col)
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ mannequin
def b_mannequin():
    a = ni("mannequin", 55)
    b = a.mb()
    M = "Mannequin"
    cylz(b, 0, 0, 0.0, 0.03, 0.24, 8, "MetalDark", rot=22.5)
    for sx in (-1, 1):
        x = sx * 0.09
        b.beam((x, 0.03, 0.04), (x * 1.1, 0, 0.5), 0.05, 0.062, 5, "Pants", True)                # shin
        b.beam((x * 1.1, 0, 0.5), (x, 0, 0.93), 0.062, 0.085, 5, "Pants", True)                  # thigh
    b.block((0, 0), 0.88, 1.04, (0.32, 0.2), (0.3, 0.19), "Pants")
    b.block((0, 0), 1.04, 1.2, (0.28, 0.18), (0.30, 0.19), "Shirt")
    b.block((0, 0), 1.2, 1.42, (0.30, 0.19), (0.40, 0.21), "Shirt")
    bx(b, (-0.22, 0.22), (-0.07, 0.07), (1.4, 1.47), "Shirt")                                      # shoulders
    cylz(b, 0, 0, 1.47, 1.56, 0.045, 6, M)                                                         # neck
    cylz(b, 0, 0.01, 1.56, 1.62, 0.055, 6, M, r1=0.085)                                            # head (faceted egg)
    cylz(b, 0, 0.01, 1.62, 1.70, 0.085, 6, M, r1=0.095)
    cylz(b, 0, 0.01, 1.70, 1.77, 0.095, 6, M, r1=0.05)
    for sx in (-1, 1):
        b.beam((sx * 0.21, 0, 1.42), (sx * 0.3, 0, 1.15), 0.045, 0.038, 5, "Shirt", True)        # upper arm
        b.beam((sx * 0.3, 0, 1.15), (sx * 0.36, 0.05, 0.92), 0.036, 0.028, 5, M, True)           # forearm
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ wardrobe
def b_wardrobe():
    a = ni("wardrobe", 56)
    b = a.mb()
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx(b, (sx * 0.52 - 0.04, sx * 0.52 + 0.04), (sy * 0.22 - 0.04, sy * 0.22 + 0.04), (0.0, 0.1), "WoodDark")
    bx(b, (-0.6, 0.6), (-0.3, 0.3), (0.1, 1.98), "WoodLight")
    bx(b, (-0.64, 0.64), (-0.33, 0.35), (1.98, 2.06), "WoodDark")                                  # cornice
    bx(b, (-0.62, 0.62), (-0.31, 0.33), (0.1, 0.16), "WoodDark")                                   # base moulding
    for sx in (-1, 1):                                                                              # two doors
        cx = sx * 0.295
        bx(b, (cx - 0.28, cx + 0.28), (0.3, 0.325), (0.17, 1.95), "WoodLight")
        bx(b, (cx - 0.2, cx + 0.2), (0.325, 0.34), (1.1, 1.85), "Mirror" if sx > 0 else "WoodPale")   # upper panel (mirror on right)
        bx(b, (cx - 0.2, cx + 0.2), (0.325, 0.34), (0.3, 1.0), "WoodPale")                           # lower panel
        bx(b, (sx * 0.05 - 0.012, sx * 0.05 + 0.012), (0.325, 0.36), (0.95, 1.15), "Brass")          # handles
    bx(b, (-0.005, 0.005), (0.325, 0.33), (0.17, 1.95), "Trim")                                    # door seam
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ bed
def b_bed_double():
    a = ni("bed_double", 57)
    b = a.mb()
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx(b, (sx * 0.8 - 0.05, sx * 0.8 + 0.05), (sy * 1.0 - 0.05, sy * 1.0 + 0.05), (0.0, 0.12), "WoodDark")
    bx(b, (-0.87, 0.87), (-1.07, 1.07), (0.12, 0.36), "WoodDark")                                  # frame
    b.block((0, 0), 0.36, 0.56, (1.62, 2.0), (1.56, 1.94), "Sheet")                                # mattress
    b.block((0, 0.5), 0.56, 0.62, (1.68, 1.05), (1.64, 1.0), "FabricTeal")                         # duvet
    bx(b, (-0.84, 0.84), (-0.04, 0.06), (0.56, 0.64), "FabricNavy")                                  # folded band
    for sx in (-1, 1):                                                                              # duvet drape on the sides
        bx(b, (sx * 0.83 - 0.015 + (0.0), sx * 0.83 + 0.015), (-0.05, 1.0), (0.3, 0.58), "FabricTeal")
    for cx in (-0.4, 0.4):
        cbox(b, (cx - 0.3, cx + 0.3), (-0.95, -0.52), (0.56, 0.68), 0.06, "Pillow")
    bx(b, (-0.9, 0.9), (-1.14, -1.04), (0.12, 1.25), "WoodDark")                                   # headboard
    bx(b, (-0.74, 0.74), (-1.04, -1.0), (0.55, 1.15), "WoodLight")
    bx(b, (-0.94, 0.94), (-1.17, -1.02), (1.25, 1.31), "WoodLight")
    bx(b, (-0.9, 0.9), (1.04, 1.12), (0.12, 0.55), "WoodDark")                                      # footboard
    bx(b, (-0.72, 0.72), (1.12, 1.15), (0.2, 0.47), "WoodLight")
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ nightstand
def b_nightstand():
    a = ni("nightstand", 58)
    b = a.mb()
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.block((sx * 0.19, sy * 0.16), 0.0, 0.16, (0.045, 0.045), (0.035, 0.035), "WoodDark")
    bx(b, (-0.22, 0.22), (-0.2, 0.2), (0.16, 0.5), "WoodLight")
    bx(b, (-0.25, 0.25), (-0.23, 0.23), (0.5, 0.54), "WoodDark")                                    # top
    bx(b, (-0.18, 0.18), (0.2, 0.215), (0.32, 0.46), "WoodPale")                                    # drawer face
    bx(b, (-0.18, 0.18), (0.2, 0.21), (0.19, 0.29), "Trim")                                         # open cubby
    cylz(b, 0, 0.22, 0.4, 0.43, 0.015, 6, "Brass")                                                  # knob
    cylz(b, -0.1, -0.05, 0.54, 0.56, 0.07, 8, "MetalDark", rot=22.5)                                # lamp base
    cylz(b, -0.1, -0.05, 0.56, 0.7, 0.012, 6, "Brass")
    cylz(b, -0.1, -0.05, 0.68, 0.84, 0.11, 8, "LampGlow", r1=0.07, rot=22.5)                        # shade
    bx(b, (0.06, 0.16), (-0.1, 0.0), (0.54, 0.58), "FabricCoral")                                   # book
    a.fin(b, "Body")
    return a


# ------------------------------------------------------------------------------------------------ sofa
def b_sofa():
    a = ni("sofa", 59)
    b = a.mb()
    F = "FabricTeal"
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.block((sx * 0.9, sy * 0.35), 0.0, 0.12, (0.07, 0.07), (0.05, 0.05), "WoodDark")
    bx(b, (-0.98, 0.98), (-0.42, 0.42), (0.12, 0.3), "WoodDark")
    for sx in (-1, 1):
        cbox(b, (sx * 0.8 if sx > 0 else -1.0, 1.0 if sx > 0 else -0.8), (-0.44, 0.44), (0.3, 0.62), 0.05, F)   # arms
    bx(b, (-0.8, 0.8), (-0.44, -0.26), (0.3, 0.82), F)                                              # back
    for i, cx in enumerate((-0.53, 0.0, 0.53)):
        cbox(b, (cx - 0.265, cx + 0.265), (-0.27, 0.43), (0.3, 0.48), 0.04, F)                      # seat cushions
        with xf(b, about((cx, -0.26, 0.5), RX(-10))):
            bx(b, (cx - 0.255, cx + 0.255), (-0.26, -0.1), (0.48, 0.78), F)                          # back cushions
    with xf(b, about((0.55, 0.0, 0.62), RX(-18))):
        cbox(b, (0.42, 0.78), (-0.1, 0.02), (0.5, 0.82), 0.04, "FabricCoral")                       # accent pillow
    a.fin(b, "Body")
    return a
