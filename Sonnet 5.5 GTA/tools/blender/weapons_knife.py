# weapons_knife.py - lane 5 - weapons/knife (0.26 m, fixed blade; origin = handle centre). Needs gta_lib + weapons_common exec'd.
W = Wpn("knife", 11)
b = W.mb("Body")
# ---- handle (rubber, oval, with finger grooves) ----
st = [(-0.058, 0.0105, 0.0115), (-0.054, 0.0138, 0.0160), (-0.040, 0.0150, 0.0175), (-0.032, 0.0128, 0.0150), (-0.022, 0.0152, 0.0178),
      (-0.010, 0.0128, 0.0152), (0.000, 0.0152, 0.0178), (0.012, 0.0128, 0.0152), (0.022, 0.0152, 0.0178), (0.036, 0.0148, 0.0172),
      (0.052, 0.0130, 0.0150), (0.058, 0.0120, 0.0140)]
rev(b, st, 0, 0, 8, "Grip", 22.5)
# pommel cap + accent ring + lanyard hole block
rev(b, [(-0.0665, 0.0110, 0.0120), (-0.058, 0.0120, 0.0132)], 0, 0, 8, "Metal", 22.5)
rev(b, [(-0.0475, 0.0158, 0.0182), (-0.0435, 0.0158, 0.0182)], 0, 0, 8, "GunAccent", 22.5)
# ---- guard ----
bx(b, (-0.0060, 0.0060), (0.058, 0.0665), (-0.0215, 0.0215), "Metal")
# ---- blade (drop point, edge down) ----
blade = [(0.066, -0.0135), (0.132, -0.0145), (0.170, -0.0100), (0.196, 0.0020), (0.178, 0.0120), (0.146, 0.0170), (0.066, 0.0170)]
slab(b, blade, 0.0030, 0.0023, "GunLight")
# fuller + spine saw-teeth accent
strips_x(b, 0.0030, 0.078, 0.156, 0.0070, 0.0100, "MetalDark", 0.0006)
for k in range(4):
    y0 = 0.080 + k * 0.013
    bx(b, (-0.0021, 0.0021), (y0, y0 + 0.006), (0.0168, 0.0192), "MetalDark")
W.part(b, "Body")
W.mark("Muzzle", (0, 0.196, 0.002))
W.mark("Tip", (0, 0.196, 0.002))
W.mark("Grip_L", (0, 0.0, 0.0))
W.report()
