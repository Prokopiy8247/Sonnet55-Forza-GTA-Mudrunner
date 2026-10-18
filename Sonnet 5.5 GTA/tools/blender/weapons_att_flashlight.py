# weapons_att_flashlight.py - lane 5 - weapons/att_flashlight (0.12 m; origin = underside rail mount contact, hangs below; +Y forward). Needs gta_lib + weapons_common exec'd.
W = Wpn("att_flashlight", 17)
b = W.mb("Body")
FZ = -0.0235                    # body axis height below the mount
# rail clamp (top) + clip arms
bx(b, (-0.0125, 0.0125), (0.012, 0.060), (-0.0100, 0.0), "Gun")
bx(b, (-0.0125, 0.0125), (0.012, 0.060), (-0.0170, -0.0100), "MetalDark")
# body tube + tail cap + head (reflector) + bezel
rev(b, [(0.000, 0.0120), (0.006, 0.0152), (0.080, 0.0152)], 0, FZ, 8, "Gun", 22.5)
rev(b, [(0.080, 0.0152), (0.086, 0.0215), (0.116, 0.0225)], 0, FZ, 8, "Gun", 22.5)
rev(b, [(0.1120, 0.0238), (0.1198, 0.0238)], 0, FZ, 8, "GunLight", 22.5)
rev(b, [(0.1196, 0.0198), (0.1206, 0.0198)], 0, FZ, 8, "LampGlow", 22.5)       # emissive lens
# grip bands + accent
for y in (0.022, 0.034, 0.046, 0.058):
    rev(b, [(y - 0.0025, 0.0160), (y + 0.0025, 0.0160)], 0, FZ, 8, "MetalDark", 22.5)
rev(b, [(0.0900, 0.0222), (0.0960, 0.0222)], 0, FZ, 8, "GunAccent", 22.5)
# tail switch + side button
bx(b, (-0.0050, 0.0050), (0.0, 0.0050), (FZ - 0.0050, FZ + 0.0050), "GunAccent")
bx(b, (0.0152, 0.0185), (0.062, 0.076), (FZ - 0.0035, FZ + 0.0035), "GunAccent")
W.part(b, "Body")
W.mark("LightPoint", (0, 0.1206, FZ))
W.report()
