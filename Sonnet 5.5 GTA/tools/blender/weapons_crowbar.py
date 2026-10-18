# weapons_crowbar.py - lane 5 - weapons/crowbar (0.65 m; origin = grip centre; claw toward +Y/up). Needs gta_lib + weapons_common exec'd.
W = Wpn("crowbar", 13)
b = W.mb("Body")
R = 0.0120
path = [(0, -0.300, 0), (0, -0.100, 0), (0, 0.100, 0), (0, 0.190, 0), (0, 0.235, 0.008), (0, 0.272, 0.030), (0, 0.290, 0.062),
        (0, 0.282, 0.096), (0, 0.258, 0.118)]
rad = [R, R, R, R, R * 0.98, R * 0.92, R * 0.84, R * 0.74, R * 0.58]
sweep(b, path, rad, 6, "MetalDark", 0.0)
# flat chisel end
slab(b, [(-0.346, -0.0020), (-0.294, -0.0098), (-0.294, 0.0098), (-0.346, 0.0020)], 0.0145, 0.0012, "Metal")
# red grip sleeve + accent rings
rev(b, [(-0.130, 0.0130), (0.090, 0.0130)], 0, 0, 6, "GunRed", 0.0)
rev(b, [(-0.134, 0.0142), (-0.128, 0.0142)], 0, 0, 6, "GunAccent", 0.0)
rev(b, [(0.088, 0.0142), (0.094, 0.0142)], 0, 0, 6, "GunAccent", 0.0)
# claw: V-notch cheeks + nail slot block at the tip
slab(b, [(0.2660, 0.1020), (0.2420, 0.1260), (0.2290, 0.1180), (0.2460, 0.0960)], 0.0070, 0.0014, "Metal")
bx(b, (-0.0030, 0.0030), (0.2400, 0.2520), (0.1060, 0.1290), "Trim")
W.part(b, "Body")
W.mark("Muzzle", (0, 0.250, 0.122))
W.mark("Tip", (0, 0.250, 0.122))
W.mark("Grip_L", (0, 0.0, 0))
W.report()
