# weapons_bat.py - lane 5 - weapons/bat (0.85 m wooden bat; origin = handle grip). Needs gta_lib + weapons_common exec'd.
W = Wpn("bat", 12)
b = W.mb("Body")
prof = [(-0.150, 0.0125), (-0.1465, 0.0240), (-0.137, 0.0250), (-0.120, 0.0165), (-0.060, 0.0142), (0.000, 0.0148), (0.080, 0.0168),
        (0.170, 0.0225), (0.280, 0.0295), (0.400, 0.0340), (0.520, 0.0362), (0.620, 0.0362), (0.680, 0.0335), (0.700, 0.0255)]
rev(b, prof, 0, 0, 10, "Wood", 18.0)
# grip tape (accent) spiral-less wrap, brand band, end band
rev(b, [(-0.112, 0.0172), (-0.060, 0.0153), (0.000, 0.0158), (0.060, 0.0172)], 0, 0, 10, "GunAccent", 18.0)
rev(b, [(0.322, 0.0328), (0.346, 0.0338)], 0, 0, 10, "GunRed", 18.0)
rev(b, [(0.640, 0.0368), (0.662, 0.0366)], 0, 0, 10, "GunAccent", 18.0)
# scuffs: two dark nail marks (flat strips) on the barrel
for y in (0.46, 0.52):
    bx(b, (0.0350, 0.0368), (y, y + 0.012), (-0.004, 0.004), "WoodDark")
W.part(b, "Body")
W.mark("Muzzle", (0, 0.700, 0))
W.mark("Tip", (0, 0.700, 0))
W.mark("Grip_L", (0, 0.060, 0))
W.report()
