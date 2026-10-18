# weapons_att_suppressor.py - lane 5 - weapons/att_suppressor (0.20 m; origin = muzzle thread mount, +Y forward). Needs gta_lib + weapons_common exec'd.
W = Wpn("att_suppressor", 15)
b = W.mb("Body")
# thread adapter + can
rev(b, [(0.000, 0.0100), (0.016, 0.0100)], 0, 0, 8, "Metal", 22.5)
rev(b, [(0.014, 0.0165), (0.022, 0.0225), (0.060, 0.0235), (0.176, 0.0235), (0.192, 0.0220), (0.200, 0.0215)], 0, 0, 8, "Gun", 22.5)
# baffle seam rings + accent band + front cap ring
for y in (0.052, 0.088, 0.124, 0.160):
    rev(b, [(y - 0.0022, 0.0242), (y + 0.0022, 0.0242)], 0, 0, 8, "MetalDark", 22.5)
rev(b, [(0.026, 0.0242), (0.036, 0.0242)], 0, 0, 8, "GunAccent", 22.5)
rev(b, [(0.1925, 0.0225), (0.2003, 0.0225)], 0, 0, 8, "GunLight", 22.5)
rev(b, [(0.1999, 0.0098), (0.2007, 0.0098)], 0, 0, 8, "Trim", 22.5)
# heat-vent slots (decor) on the side
for k in range(3):
    y0 = 0.100 + k * 0.022
    bx(b, (0.0230, 0.0243), (y0, y0 + 0.012), (-0.008, 0.008), "Trim")
W.part(b, "Body")
W.mark("Muzzle", (0, 0.2005, 0))
W.report()
