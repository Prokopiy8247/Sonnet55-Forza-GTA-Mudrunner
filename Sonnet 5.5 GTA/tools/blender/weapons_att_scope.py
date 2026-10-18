# weapons_att_scope.py - lane 5 - weapons/att_scope (0.28 m; origin = rail mount point (underside centre), +Y forward). Needs gta_lib + weapons_common exec'd.
W = Wpn("att_scope", 16)
b = W.mb("Body")
SZ = 0.040                      # tube axis height above the mount
# base clamp + two ring blocks
bx(b, (-0.0125, 0.0125), (-0.030, 0.030), (0.0, 0.0090), "Gun")
for yy in (-0.045, 0.045):
    bx(b, (-0.0115, 0.0115), (yy - 0.010, yy + 0.010), (0.0090, SZ + 0.0060), "Gun")
    rev(b, [(yy - 0.0105, 0.0200), (yy + 0.0105, 0.0200)], 0, SZ, 8, "MetalDark", 22.5)
# main tube, objective bell, eyepiece
rev(b, [(-0.075, 0.0158), (0.075, 0.0158)], 0, SZ, 8, "Gun", 22.5)
rev(b, [(0.075, 0.0158), (0.108, 0.0235), (0.140, 0.0265)], 0, SZ, 8, "Gun", 22.5)
rev(b, [(-0.075, 0.0158), (-0.100, 0.0200), (-0.140, 0.0220)], 0, SZ, 8, "Gun", 22.5)
# accent ring + hood lip
rev(b, [(0.0015, 0.0166), (0.0075, 0.0166)], 0, SZ, 8, "GunAccent", 22.5)
rev(b, [(0.1330, 0.0272), (0.1405, 0.0272)], 0, SZ, 8, "MetalDark", 22.5)
# lenses (glowing)
rev(b, [(0.1402, 0.0240), (0.1414, 0.0240)], 0, SZ, 8, "ScopeLens", 22.5)
rev(b, [(-0.1412, 0.0172), (-0.1400, 0.0172)], 0, SZ, 8, "ScopeLens", 22.5)
# turrets: elevation (top) + windage (right)
b.cyl((0, 0.012, SZ + 0.0158 + 0.0100), 0.0105, 0.0200, 8, "GunLight", axis="Z")
b.cyl((0, 0.012, SZ + 0.0158 + 0.0208), 0.0112, 0.0030, 8, "GunAccent", axis="Z")
b.cyl((0.0158 + 0.0095, 0.012, SZ), 0.0095, 0.0190, 8, "GunLight", axis="X")
W.part(b, "Body")
W.mark("Eye", (0, -0.141, SZ))
W.mark("Muzzle", (0, 0.1415, SZ))
W.report()
