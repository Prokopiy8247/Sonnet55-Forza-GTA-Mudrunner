# weapons_pistol.py - lane 5 - weapons/pistol  (0.21 m, hero). Needs gta_lib + weapons_common already exec'd.
W = Wpn("pistol", 0)
RAKE = 0.2126            # tan(12 deg): grip leans back, butt rearward
def back(z):  return RAKE * z - 0.0225
def front(z): return RAKE * z + 0.0235
ZT = 0.061               # slide top
ZS = 0.026               # slide bottom
YF = 0.159               # slide front
YM = 0.168               # muzzle tip

# ---------------- Body (polymer frame) ----------------
b = W.mb("Body")
frame = [(-0.030, 0.031), (-0.0275, 0.021), (back(0.008), 0.008), (back(-0.074), -0.074), (front(-0.074), -0.074),
         (front(-0.013), -0.013), (front(0.014), 0.014), (0.045, 0.014), (0.045, 0.008), (0.082, 0.008),
         (0.082, 0.020), (0.080, 0.031)]
slab(b, frame, 0.0125, 0.0025, "Grip")
# trigger guard (open U band)
guard = [(0.0165, -0.021), (0.049, -0.021), (0.060, -0.013), (0.061, 0.012), (0.054, 0.012), (0.0535, -0.0105),
         (0.047, -0.0148), (0.0165, -0.0148)]
slab(b, guard, 0.0115, 0.0016, "Grip")
# grip texture strips (perpendicular to grip axis), both sides
for k in range(5):
    z = -0.012 - k * 0.0125
    yb, yf = back(z) + 0.0045, front(z) - 0.0045
    dz = RAKE * (yf - yb)
    st = [(yb, z), (yf, z - dz), (yf, z - dz + 0.0021), (yb, z + 0.0021)]
    b.profile_extrude(st, 0.0003, "Gun", 0.0128)
    b.profile_extrude(st, 0.0003, "Gun", -0.0128)
# accessory-rail slots (dark) on the dust cover
for y in (0.050, 0.059, 0.068):
    strips_x(b, 0.0125, y, y + 0.0035, 0.0105, 0.0185, "Gun", 0.0007)
# magazine release stud (accent)
bx(b, (0.0125, 0.0145), (0.011, 0.022), (-0.0085, -0.0045), "GunAccent")
# slide-stop lever (left) + takedown pin (right)
bx(b, (-0.0150, -0.0123), (0.020, 0.046), (0.0215, 0.0265), "GunLight")
W.part(b, "Body")

# ---------------- Slide ----------------
b = W.mb("Slide")
prof = [(-0.030, ZS), (YF, ZS), (YF, 0.052), (YF - 0.008, ZT), (-0.024, ZT), (-0.030, 0.0535)]
slab(b, prof, 0.0145, 0.0035, "GunLight")
# rear serrations (4 per side)
for k in range(4):
    y = -0.0255 + k * 0.0060
    strips_x(b, 0.0145, y, y + 0.0026, 0.0275, 0.0545, "Gun", 0.0008)
# front serrations (3 per side)
for k in range(3):
    y = 0.126 + k * 0.0060
    strips_x(b, 0.0145, y, y + 0.0024, 0.0275, 0.0505, "Gun", 0.0008)
# ejection port (right) + accent stripe (both sides)
bx(b, (0.0143, 0.0152), (0.018, 0.066), (0.0385, 0.0535), "Trim")
strips_x(b, 0.0145, 0.078, 0.120, 0.0295, 0.0335, "GunAccent", 0.0007)
# front sight + dot, rear sight posts
tbox(b, (-0.0028, 0.0028), (YF - 0.022, YF - 0.010), (ZT - 0.001, 0.0690), "Gun", (-0.0022, 0.0022), (YF - 0.020, YF - 0.011))
bx(b, (-0.0013, 0.0013), (YF - 0.0226, YF - 0.0208), (0.0625, 0.0665), "SightDot")
bx(b, (-0.0095, -0.0043), (-0.0215, -0.0125), (ZT - 0.001, 0.0665), "Gun")
bx(b, (0.0043, 0.0095), (-0.0215, -0.0125), (ZT - 0.001, 0.0665), "Gun")
# barrel tip + bore
rev(b, [(YF - 0.010, 0.0088), (YM, 0.0088)], 0, 0.0435, 8, "Metal", 22.5)
rev(b, [(YM - 0.0004, 0.0050), (YM + 0.0002, 0.0050)], 0, 0.0435, 8, "Trim", 22.5)
W.part(b, "Slide")

# ---------------- Magazine ----------------
b = W.mb("Magazine")
mag = [(back(0.010) + 0.0038, 0.010), (back(-0.0795) + 0.0038, -0.0795), (front(-0.0795) - 0.0038, -0.0795), (front(0.010) - 0.0038, 0.010)]
b.profile_extrude(mag, 0.0105, "Gun", 0.0)
fp = [(back(-0.0795) - 0.0008, -0.0795), (back(-0.088) - 0.0008, -0.088), (front(-0.088) + 0.0008, -0.088), (front(-0.0795) + 0.0008, -0.0795)]
slab(b, fp, 0.0137, 0.0012, "Metal")
bx(b, (-0.0141, 0.0141), (back(-0.0836) + 0.002, front(-0.0836) - 0.002), (-0.0852, -0.0826), "GunAccent")
W.part(b, "Magazine")

# ---------------- Trigger ----------------
b = W.mb("Trigger")
b.profile_extrude([(0.0275, 0.013), (0.0245, 0.0), (0.028, -0.011), (0.0345, -0.0115), (0.0335, 0.0)], 0.0035, "MetalDark", 0.0)
b.profile_extrude([(0.0335, 0.0), (0.0345, -0.0115), (0.0365, -0.0112), (0.0360, 0.0)], 0.0036, "Gun", 0.0)
W.part(b, "Trigger")

# ---------------- anchors ----------------
W.mark("Muzzle", (0, YM, 0.0435))
W.mark("Grip_L", (-0.017, 0.010, -0.040))
W.mark("Eject", (0.0152, 0.042, 0.046))
W.mark("AttMuzzle", (0, YM, 0.0435))
W.mark("AttOptic", (0, 0.000, ZT))
W.mark("AttRail", (0, 0.062, 0.008))
W.mark("AttGrip", (0, 0.062, 0.008))
W.mark("AttMag", (0, front(0.010) - 0.023, 0.010), (-12, 0, 0))
W.report()
