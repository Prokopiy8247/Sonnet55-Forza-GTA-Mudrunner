# weapons_att_grip.py - lane 5 - weapons/att_grip (0.12 m vertical foregrip; origin = underside rail mount contact, hangs down). Needs gta_lib + weapons_common exec'd.
W = Wpn("att_grip", 18)
b = W.mb("Body")
# rail clamp
bx(b, (-0.0145, 0.0145), (-0.024, 0.024), (-0.0140, 0.0), "Gun")
bx(b, (-0.0100, 0.0100), (-0.030, 0.030), (-0.0200, -0.0140), "MetalDark")
# grip body (faceted, oval), finger grooves, flared base cap
st = [(-0.0200, 0.0150, 0.0170), (-0.0300, 0.0172, 0.0198), (-0.0480, 0.0160, 0.0182), (-0.0560, 0.0178, 0.0204), (-0.0720, 0.0160, 0.0184),
      (-0.0800, 0.0178, 0.0204), (-0.0960, 0.0166, 0.0190), (-0.1080, 0.0190, 0.0215), (-0.1160, 0.0160, 0.0182)]
revz(b, st, 0, 0, 8, "Grip", 22.5)
revz(b, [(-0.1160, 0.0160, 0.0182), (-0.1200, 0.0150, 0.0170)], 0, 0, 8, "MetalDark", 22.5)
for z in (-0.0640, -0.0880):
    revz(b, [(z - 0.0016, 0.0170, 0.0196), (z + 0.0016, 0.0170, 0.0196)], 0, 0, 8, "Gun", 22.5)
revz(b, [(-0.1030, 0.0198, 0.0223), (-0.1000, 0.0198, 0.0223)], 0, 0, 8, "GunAccent", 22.5)
W.part(b, "Body")
W.report()
