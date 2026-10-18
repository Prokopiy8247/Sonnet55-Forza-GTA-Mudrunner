# weapons_smg.py - lane 5 - weapons/smg  (0.45 m, hero). Needs gta_lib + weapons_common already exec'd.
W = Wpn("smg", 1)
RK = 0.268
def gb(z): return RK * z - 0.020
def gf(z): return RK * z + 0.020
ZB, ZT = 0.030, 0.100          # receiver bottom / top
BZ = 0.067                     # bore height
YM = 0.262                     # muzzle

# ---------------- Body ----------------
b = W.mb("Body")
# receiver (dark steel) with chamfered edges
rec = [(-0.150, ZB), (0.150, ZB), (0.150, 0.092), (0.138, ZT), (-0.138, ZT), (-0.150, 0.090)]
slab(b, rec, 0.0235, 0.0045, "MetalDark")
# lower receiver seam + front seam
strips_x(b, 0.0235, -0.148, 0.148, 0.0585, 0.0605, "Trim", 0.0009)
strips_x(b, 0.0235, 0.139, 0.142, 0.032, 0.098, "Trim", 0.0009)
# bolt slot (right) and ejection port (right)
bx(b, (0.0232, 0.0242), (-0.105, 0.040), (0.069, 0.0745), "Trim")
bx(b, (0.0232, 0.0243), (0.058, 0.112), (0.062, 0.088), "Trim")
# top rail: base + teeth
bx(b, (-0.0092, 0.0092), (-0.125, 0.136), (ZT - 0.001, ZT + 0.0045), "Gun")
for k in range(8):
    y0 = -0.100 + k * 0.0290
    bx(b, (-0.0095, 0.0095), (y0, y0 + 0.0150), (ZT + 0.0035, ZT + 0.0085), "GunLight")
# rear sight (two ears) + front sight on shroud
for s in (-1, 1):
    bx(b, (s * 0.0045, s * 0.0105) if s > 0 else (-0.0105, -0.0045), (-0.130, -0.119), (ZT + 0.0045, ZT + 0.0125), "Gun")
    bx(b, (s * 0.0058 - 0.0009, s * 0.0058 + 0.0009), (-0.1316, -0.1296), (ZT + 0.0095, ZT + 0.0120), "SightDot")
# barrel shroud (octagon) + vents
rev(b, [(0.140, 0.0262, 0.0305), (0.236, 0.0262, 0.0305)], 0, BZ, 8, "GunLight", 22.5)
# lighter faceted side plates on the lower receiver
plate = [(-0.112, 0.037), (0.034, 0.037), (0.056, 0.047), (0.056, 0.0555), (-0.112, 0.0555)]
for s in (1, -1):
    b.profile_extrude(plate, 0.0006, "GunLight", s * 0.0239)
for k in range(4):
    y0 = 0.150 + k * 0.0155
    bx(b, (0.0237, 0.0252), (y0, y0 + 0.0100), (BZ - 0.012, BZ + 0.012), "Trim")
    bx(b, (-0.0252, -0.0237), (y0, y0 + 0.0100), (BZ - 0.012, BZ + 0.012), "Trim")
rev(b, [(0.208, 0.0272, 0.0315), (0.216, 0.0272, 0.0315)], 0, BZ, 8, "GunAccent", 22.5)   # accent band
# front sight (hooded post)
bx(b, (-0.0026, 0.0026), (0.221, 0.227), (BZ + 0.0265, BZ + 0.0450), "Gun")
bx(b, (-0.0100, -0.0070), (0.219, 0.229), (BZ + 0.0265, BZ + 0.0450), "Gun")
bx(b, (0.0070, 0.0100), (0.219, 0.229), (BZ + 0.0265, BZ + 0.0450), "Gun")
bx(b, (-0.0011, 0.0011), (0.2194, 0.2212), (BZ + 0.0385, BZ + 0.0445), "SightDot")
# underside rail
bx(b, (-0.0088, 0.0088), (0.150, 0.228), (0.0315, 0.0405), "Gun")
for k in range(4):
    y0 = 0.160 + k * 0.0175
    bx(b, (-0.0092, 0.0092), (y0, y0 + 0.0090), (0.0295, 0.0345), "GunLight")
# muzzle device + barrel
rev(b, [(0.232, 0.0098), (0.245, 0.0098)], 0, BZ, 8, "Metal", 22.5)
rev(b, [(0.236, 0.0125), (YM, 0.0125)], 0, BZ, 8, "Gun", 22.5)
for y in (0.247, 0.256):
    rev(b, [(y - 0.0015, 0.0145), (y + 0.0015, 0.0145)], 0, BZ, 8, "MetalDark", 22.5)
rev(b, [(YM - 0.0004, 0.0062), (YM + 0.0003, 0.0062)], 0, BZ, 8, "Trim", 22.5)
# skeletal stock: top strut, bottom strut, butt plate
slab(b, [(-0.186, 0.078), (-0.140, 0.080), (-0.140, 0.094), (-0.186, 0.098)], 0.0140, 0.0030, "Grip")
slab(b, [(-0.186, 0.014), (-0.140, 0.026), (-0.140, 0.040), (-0.186, 0.030)], 0.0140, 0.0030, "Grip")
slab(b, [(-0.1905, 0.0125), (-0.184, 0.0125), (-0.184, 0.0985), (-0.1905, 0.0975)], 0.0190, 0.0012, "Trim")
# pistol grip + texture
grip = [(gb(0.050), 0.050), (gb(-0.095), -0.095), (gf(-0.095), -0.095), (gf(0.050), 0.050)]
slab(b, grip, 0.0185, 0.0030, "Grip")
for k in range(4):
    z = -0.014 - k * 0.0195
    yb, yf = gb(z) + 0.0050, gf(z) - 0.0050
    dz = RK * (yf - yb)
    st = [(yb, z), (yf, z - dz), (yf, z - dz + 0.0022), (yb, z + 0.0022)]
    b.profile_extrude(st, 0.0003, "Gun", 0.0188)
    b.profile_extrude(st, 0.0003, "Gun", -0.0188)
# trigger guard
guard = [(0.009, -0.026), (0.048, -0.026), (0.058, -0.017), (0.058, 0.034), (0.051, 0.034), (0.0505, -0.0125), (0.044, -0.0195), (0.009, -0.0195)]
slab(b, guard, 0.0115, 0.0016, "Grip")
# magazine well flare
tbox(b, (-0.0185, 0.0185), (0.050, 0.100), (0.022, 0.0405), "Gun", (-0.0165, 0.0165), (0.052, 0.098))
# selector (left, accent)
bx(b, (-0.0262, -0.0233), (-0.020, -0.004), (0.040, 0.046), "GunAccent")
W.part(b, "Body")

# ---------------- Magazine (curved 32 rd box) ----------------
b = W.mb("Magazine")
mag = [(0.061, 0.050), (0.059, -0.030), (0.066, -0.082), (0.095, -0.082), (0.087, -0.030), (0.089, 0.050)]
slab(b, mag, 0.0125, 0.0018, "Gun")
for z, ya, yb2 in ((-0.016, 0.0655, 0.0825), (-0.046, 0.0655, 0.0825)):
    strips_x(b, 0.0125, ya, yb2, z, z + 0.0028, "MetalDark", 0.0008)
slab(b, [(0.0645, -0.082), (0.0655, -0.0905), (0.0975, -0.0905), (0.0965, -0.082)], 0.0145, 0.0014, "GunAccent")
W.part(b, "Magazine")

# ---------------- Bolt (charging handle rides in the slot) ----------------
b = W.mb("Bolt")
slab(b, [(-0.046, 0.0675), (-0.020, 0.0675), (-0.020, 0.0760), (-0.046, 0.0760)], 0.0060, 0.0016, "GunLight", xc=0.0300)
bx(b, (0.0236, 0.0300), (-0.044, -0.022), (0.0690, 0.0745), "Gun")
W.part(b, "Bolt")

# ---------------- Trigger ----------------
b = W.mb("Trigger")
b.profile_extrude([(0.0285, 0.020), (0.0250, 0.006), (0.0290, -0.012), (0.0345, -0.0125), (0.0335, 0.006)], 0.0033, "MetalDark", 0.0)
W.part(b, "Trigger")

# ---------------- anchors ----------------
W.mark("Muzzle", (0, YM, BZ))
W.mark("Grip_L", (0, 0.176, 0.030))
W.mark("Eject", (0.0245, 0.085, 0.075))
W.mark("AttMuzzle", (0, YM, BZ))
W.mark("AttOptic", (0, 0.020, ZT + 0.0045))
W.mark("AttRail", (0, 0.190, 0.0295))
W.mark("AttGrip", (0, 0.172, 0.0295))
W.mark("AttMag", (0, 0.076, 0.020))
W.report()
