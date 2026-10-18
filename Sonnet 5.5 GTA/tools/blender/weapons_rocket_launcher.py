# weapons_rocket_launcher.py - lane 5 - weapons/rocket_launcher (1.05 m shoulder tube). Needs gta_lib + weapons_common exec'd.
W = Wpn("rocket_launcher", 9)
RK = 0.30
def gb(z): return RK * z - 0.021
def gf(z): return RK * z + 0.019
BZ = 0.085                  # tube axis height
R = 0.046                   # tube radius
YM = 0.600                  # muzzle (warhead tip)

b = W.mb("Body")
# ---- launch tube + rear venturi + front collar ----
rev(b, [(-0.300, R), (0.430, R)], 0, BZ, 12, "GunOlive", 0.0)
rev(b, [(-0.300, R + 0.001), (-0.372, 0.060), (-0.445, 0.074)], 0, BZ, 12, "MetalDark", 0.0)
rev(b, [(-0.4452, 0.062), (-0.4462, 0.062)], 0, BZ, 8, "Trim", 22.5)                         # dark bore seen from behind
rev(b, [(0.400, R + 0.003), (0.446, R + 0.008)], 0, BZ, 12, "MetalDark", 0.0)
rev(b, [(0.412, R + 0.0095), (0.424, R + 0.0095)], 0, BZ, 12, "GunAccent", 0.0)
# ---- wooden heat shield ring ----
rev(b, [(0.080, R + 0.0050), (0.300, R + 0.0050)], 0, BZ, 12, "Wood", 0.0)
# ---- shoulder cushion ----
slab(b, [(-0.300, 0.040), (-0.300, 0.020), (-0.150, 0.026), (-0.150, 0.044)], 0.0300, 0.0060, "Grip")
# ---- grip mount + pistol grip + guard ----
tbox(b, (-0.0250, 0.0250), (-0.060, 0.070), (0.030, 0.0460), "Gun", (-0.0230, 0.0230), (-0.052, 0.062))
grip = [(gb(0.040), 0.040), (gb(-0.085), -0.085), (gf(-0.085), -0.085), (gf(0.040), 0.040)]
slab(b, grip, 0.0185, 0.0030, "Grip")
grip_strips(b, gb, gf, RK, [-0.040], 0.0188)
guard = [(0.008, -0.026), (0.048, -0.026), (0.056, -0.018), (0.056, 0.034), (0.049, 0.034), (0.0485, -0.0125), (0.042, -0.0195), (0.008, -0.0195)]
slab(b, guard, 0.0115, 0.0016, "Grip")
# ---- vertical foregrip on its own mount ----
tbox(b, (-0.0250, 0.0250), (0.165, 0.255), (0.028, 0.0440), "Gun", (-0.0230, 0.0230), (0.172, 0.248))
slab(b, [(0.188, 0.034), (0.184, -0.062), (0.226, -0.066), (0.232, 0.034)], 0.0185, 0.0035, "Grip")
for z in (-0.020,):
    strips_x(b, 0.0188, 0.190, 0.226, z, z + 0.0026, "Gun", 0.0008)
# ---- iron sights: folding rear leaf + front post ----
bx(b, (-0.0050, 0.0050), (-0.170, -0.150), (BZ + R - 0.004, BZ + R + 0.0060), "Gun")
bx(b, (-0.0090, 0.0090), (-0.168, -0.152), (BZ + R + 0.0060, BZ + R + 0.0160), "Gun")
bx(b, (-0.0040, 0.0040), (0.360, 0.380), (BZ + R - 0.004, BZ + R + 0.0210), "Gun")
# ---- optic (left of the tube top) ----
OZ = BZ + R + 0.030
OX = -0.030
bx(b, (OX - 0.011, OX + 0.011), (-0.060, -0.040), (BZ + R - 0.004, OZ), "Gun")
bx(b, (OX - 0.011, OX + 0.011), (0.020, 0.040), (BZ + R - 0.004, OZ), "Gun")
rev(b, [(-0.125, 0.0200), (-0.100, 0.0160), (0.070, 0.0160), (0.100, 0.0215)], OX, OZ, 8, "Gun", 22.5)
rev(b, [(0.1001, 0.0185), (0.1012, 0.0185)], OX, OZ, 8, "ScopeLens", 22.5)
rev(b, [(-0.1262, 0.0150), (-0.1252, 0.0150)], OX, OZ, 8, "ScopeLens", 22.5)
W.part(b, "Body")

# ---- Rocket (visible warhead; hide it when the launcher is empty) ----
b = W.mb("Rocket")
rev(b, [(0.380, 0.030), (0.425, 0.042), (0.470, 0.054), (0.525, 0.054), (0.575, 0.034), (YM, 0.008)], 0, BZ, 8, "GunAccent", 22.5)
rev(b, [(0.5800, 0.0310), (0.5900, 0.0170)], 0, BZ, 8, "GunRed", 22.5)
W.part(b, "Rocket")

# ---- Trigger ----
b = W.mb("Trigger")
b.profile_extrude([(0.0270, 0.028), (0.0235, 0.010), (0.0275, -0.011), (0.0330, -0.0115), (0.0320, 0.010)], 0.0030, "MetalDark", 0.0)
W.part(b, "Trigger")

W.mark("Muzzle", (0, YM, BZ))
W.mark("Grip_L", (0, 0.208, -0.022))
W.mark("Backblast", (0, -0.445, BZ))      # back-blast VFX origin (no shell ejection)
W.mark("AttOptic", (OX, 0.0, OZ))
W.mark("AttMuzzle", (0, 0.446, BZ))
W.report()
