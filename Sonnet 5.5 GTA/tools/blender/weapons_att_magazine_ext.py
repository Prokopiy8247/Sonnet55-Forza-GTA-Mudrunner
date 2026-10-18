# weapons_att_magazine_ext.py - lane 5 - weapons/att_magazine_ext (0.14 m extended pistol/SMG magazine; origin = top of the mag (mount), hangs down). Needs gta_lib + weapons_common exec'd.
W = Wpn("att_magazine_ext", 19)
b = W.mb("Body")
mag = [(-0.0250, 0.000), (-0.0262, -0.070), (-0.0270, -0.1320), (0.0262, -0.1320), (0.0262, -0.070), (0.0250, 0.000)]
slab(b, mag, 0.0150, 0.0024, "Gun")
# feed lips at the top
slab(b, [(-0.0230, 0.0050), (-0.0235, 0.0000), (0.0235, 0.0000), (0.0235, 0.0050)], 0.0130, 0.0010, "GunLight")
# witness ribs
for z in (-0.020, -0.045, -0.070, -0.095):
    strips_x(b, 0.0150, -0.018, 0.018, z, z + 0.0028, "MetalDark", 0.0008)
# base plate + accent
slab(b, [(-0.0285, -0.1320), (-0.0295, -0.1410), (0.0290, -0.1410), (0.0280, -0.1320)], 0.0168, 0.0014, "GunAccent")
bx(b, (-0.0100, 0.0100), (0.0268, 0.0282), (-0.1380, -0.1340), "MetalDark")
W.part(b, "Body")
W.report()
