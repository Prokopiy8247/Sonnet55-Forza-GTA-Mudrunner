# weapons_shotgun_auto.py - lane 5 - weapons/shotgun_auto (0.95 m, drum magazine). Needs gta_lib + weapons_common exec'd.
W = Wpn("shotgun_auto", 8)
RK = 0.30
def gb(z): return RK * z - 0.022
def gf(z): return RK * z + 0.019
BZ = 0.072
YM = 0.650
DY, DZ, DR = 0.108, -0.014, 0.062      # drum centre / radius

b = W.mb("Body")
# ---- receiver + top rail ----
rec = [(-0.120, 0.040), (0.145, 0.036), (0.145, 0.100), (0.135, 0.108), (-0.110, 0.108), (-0.120, 0.100)]
slab(b, rec, 0.0265, 0.0050, "MetalDark")
bx(b, (0.0263, 0.0274), (0.000, 0.078), (0.068, 0.098), "Trim")                         # ejection port
bx(b, (-0.0090, 0.0090), (-0.105, 0.135), (0.1075, 0.1125), "Gun")
rail_teeth(b, -0.100, 0.130, 3, 0.1120, 0.1170, 0.0098, 0.5, "GunLight")
# rear sight (flip) on the rail
bx(b, (-0.0090, 0.0090), (-0.104, -0.090), (0.1170, 0.1340), "Gun")
# ---- vented barrel shroud ----
rev(b, [(0.140, 0.0305), (0.505, 0.0305)], 0, BZ, 8, "MetalDark", 22.5)
for k in range(3):
    y0 = 0.200 + k * 0.095
    bx(b, (0.0282, 0.0296), (y0, y0 + 0.048), (BZ - 0.011, BZ + 0.011), "Trim")
    bx(b, (-0.0296, -0.0282), (y0, y0 + 0.048), (BZ - 0.011, BZ + 0.011), "Trim")
# front sight tower on the shroud
bx(b, (-0.0045, 0.0045), (0.472, 0.490), (BZ + 0.0280, BZ + 0.0560), "Gun")
bx(b, (-0.0011, 0.0011), (0.4705, 0.4722), (BZ + 0.0470, BZ + 0.0525), "SightDot")
# ---- barrel + choke ----
rev(b, [(0.500, 0.0165), (YM, 0.0165)], 0, BZ, 8, "Metal", 22.5)
rev(b, [(0.612, 0.0205), (YM, 0.0205)], 0, BZ, 8, "Gun", 22.5)
for y in (0.630,):
    rev(b, [(y - 0.004, 0.0222), (y + 0.004, 0.0222)], 0, BZ, 8, "GunAccent", 22.5)
rev(b, [(YM - 0.0004, 0.0110), (YM + 0.0003, 0.0110)], 0, BZ, 8, "Trim", 22.5)
# ---- polymer stock ----
slab(b, [(-0.290, 0.030), (-0.200, 0.048), (-0.110, 0.056), (-0.110, 0.108), (-0.200, 0.112), (-0.290, 0.104)], 0.0200, 0.0050, "Grip")
slab(b, [(-0.302, 0.0265), (-0.290, 0.030), (-0.290, 0.104), (-0.302, 0.1015)], 0.0210, 0.0014, "Trim")
# ---- pistol grip + guard ----
grip = [(gb(0.040), 0.040), (gb(-0.090), -0.090), (gf(-0.090), -0.090), (gf(0.040), 0.040)]
slab(b, grip, 0.0190, 0.0032, "Grip")
grip_strips(b, gb, gf, RK, [-0.040], 0.0194)
guard = [(0.008, -0.026), (0.040, -0.026), (0.047, -0.018), (0.047, 0.036), (0.041, 0.036), (0.0405, -0.0125), (0.035, -0.0195), (0.008, -0.0195)]
slab(b, guard, 0.0115, 0.0016, "Grip")
# drum mount (under the shroud, behind the drum)
tbox(b, (-0.0210, 0.0210), (0.056, 0.156), (0.032, 0.046), "Gun", (-0.0190, 0.0190), (0.066, 0.146))
W.part(b, "Body")

# ---- Drum magazine (axis X) ----
b = W.mb("Magazine")
b.cyl((0, DY, DZ), DR, 0.050, 12, "Gun", axis="X")
b.cyl((0, DY, DZ), DR + 0.0018, 0.014, 12, "GunAccent", axis="X")
for s in (1, -1):
    b.cyl((s * 0.0262, DY, DZ), 0.034, 0.004, 8, "GunLight", axis="X")
    b.cyl((s * 0.0290, DY, DZ), 0.012, 0.004, 8, "MetalDark", axis="X")
W.part(b, "Magazine")

# ---- Bolt (charging handle, right) ----
b = W.mb("Bolt")
slab(b, [(0.016, 0.0830), (0.054, 0.0830), (0.054, 0.0925), (0.016, 0.0925)], 0.0062, 0.0016, "GunLight", xc=0.0335)
W.part(b, "Bolt")

# ---- Trigger ----
b = W.mb("Trigger")
b.profile_extrude([(0.0255, 0.026), (0.0225, 0.008), (0.0260, -0.012), (0.0310, -0.0125), (0.0300, 0.008)], 0.0030, "MetalDark", 0.0)
W.part(b, "Trigger")

W.mark("Muzzle", (0, YM, BZ))
W.mark("Grip_L", (0, 0.290, BZ - 0.034))
W.mark("Eject", (0.0275, 0.040, 0.083))
W.mark("AttMuzzle", (0, YM, BZ))
W.mark("AttOptic", (0, 0.020, 0.1170))
W.mark("AttRail", (0, 0.300, BZ - 0.0305))
W.mark("AttGrip", (0, 0.280, BZ - 0.0305))
W.mark("AttMag", (0, DY, DZ - DR))
W.report()
