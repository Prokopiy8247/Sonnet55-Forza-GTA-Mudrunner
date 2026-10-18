# lane 8 - hangar_b: gable hangar 30 x 24 m with a two-storey side office annex, big sliding door toward +Y
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("hangar_b", 9)
b = a.b("Body")
MX0, MX1, Y0, Y1 = -15.0, 9.0, -12.0, 12.0
ZE, ZR, T, OH = 7.5, 10.8, 0.3, 0.6
XM = (MX0 + MX1) / 2
MP = rect_pts(XM, 0, MX1 - MX0, Y1 - Y0, 0.0)

# ---- main hall + roof + plinth
shaft(b, rect_pts(0, 0, 30.4, 24.4), 0, 0.5, "Concrete", "Concrete")
extrude_y(b, gable_prof(MX0, MX1, ZE, ZR), Y0, Y1, "WallD")
extrude_y(b, roof_prof(MX0, MX1, ZE, ZR, OH, T), Y0 - OH, Y1 + OH, "Roof")
belt_ring(b, MP, 5.4, 7.2, 0.12, "WallC")
belt_ring(b, MP, 0.5, 0.9, 0.1, "Trim")
glaze(b, MP, 4.2, 5.2, "Window", bay=3.2, gap=1.4, edge=2.0, skip=(1, 2))
# roof ribs along the slopes
m = (ZR - ZE) / (XM - MX0)
for y in (-10.0, -6.0, -2.0, 2.0, 6.0, 10.0):
    b.beam((MX0 - OH * 0.5, y, ZE - m * OH * 0.5 + T + 0.12), (XM, y, ZR + T + 0.12), 0.12, 0.12, 4, "Metal")
    b.beam((MX1 + OH * 0.5, y, ZE - m * OH * 0.5 + T + 0.12), (XM, y, ZR + T + 0.12), 0.12, 0.12, 4, "Metal")
for y in (-8.0, 0.0, 8.0):
    b.box((XM, y, ZR + T + 0.35), (1.6, 1.8, 0.7), "Metal")        # ridge vents
# skylight patches on the slopes
for (ya, yb) in ((-9.0, -3.0), (3.0, 9.0)):
    xa, xb = MX0 + 3.5, XM - 0.8
    za, zb = ZE + m * (xa - MX0) + T + 0.03, ZE + m * (xb - MX0) + T + 0.03
    b.quad((xa, yb, za), (xa, ya, za), (xb, ya, zb), (xb, yb, zb), "Glass")
    xa, xb = XM + 0.8, MX1 - 3.5
    za, zb = ZR - m * (xa - XM) + T + 0.03, ZR - m * (xb - XM) + T + 0.03
    b.quad((xa, ya, za), (xa, yb, za), (xb, yb, zb), (xb, ya, zb), "Glass")

# ---- big sliding door on +Y (painted opening + two leaves + frame + track)
DC, DW, DH = -3.0, 20.0, 7.0
b.box((DC - DW / 2 - 0.5, Y1 + 0.2, DH / 2 + 0.1), (0.9, 0.6, DH + 0.2), "Trim")
b.box((DC + DW / 2 + 0.5, Y1 + 0.2, DH / 2 + 0.1), (0.9, 0.6, DH + 0.2), "Trim")
b.box((DC, Y1 + 0.2, DH + 0.5), (DW + 1.9, 0.6, 0.9), "Trim")
for (cx, yy) in ((DC - DW / 4, Y1 + 0.35), (DC + DW / 4, Y1 + 0.75)):
    b.box((cx, yy, DH / 2), (DW / 2 + 0.2, 0.28, DH - 0.1), "MetalDark")
    for k in range(4):
        b.box((cx, yy + 0.16, 1.2 + k * 1.5), (DW / 2 - 0.1, 0.1, 0.2), "Metal")
    b.box((cx, yy + 0.16, 0.45), (DW / 2 + 0.1, 0.1, 0.5), "YellowPaint")
b.box((DC, Y1 + 1.2, DH + 1.15), (DW + 3.0, 0.5, 0.4), "MetalDark")
b.box((DC, Y1 + 0.12, 9.1), (7.0, 0.2, 0.7), "WallB")
b.box((DC, Y1 + 0.22, 9.1), (6.2, 0.1, 0.14), "NeonCyan")
for x in (DC - DW / 2 - 1.8, DC + DW / 2 + 1.8):
    b.box((x, Y1 + 0.2, 7.3), (0.3, 0.3, 0.3), "LampGlow")

# ---- office annex (x 9..15, y -4..12), two floors
AP = rect_pts(12.0, 4.0, 6.0, 16.0, 0.0)
shaft(b, AP, 0.0, 6.6, "WallA", "Roof")
parapet(b, AP, 6.6, 7.3, 0.25, "WallD")
glaze(b, AP, 1.0, 2.7, "Window", bay=1.9, gap=0.9, edge=0.7, skip=(3,))
glaze(b, AP, 4.0, 5.7, "Window", bay=1.9, gap=0.9, edge=0.7, skip=(3,))
belt_ring(b, AP, 3.0, 3.5, 0.12, "WallC")
b.box((12.0, Y1 + 0.1, 1.05), (1.2, 0.2, 2.1), "MetalDark")         # annex door
b.box((12.0, Y1 + 1.0, 2.6), (2.6, 2.0, 0.22), "Trim")              # canopy
b.box((11.4, Y1 + 1.9, 1.3), (0.12, 0.12, 2.6), "Metal")
b.box((12.6, Y1 + 1.9, 1.3), (0.12, 0.12, 2.6), "Metal")
b.box((13.0, 2.0, 7.9), (1.8, 1.8, 1.2), "MetalDark")                # roof AC
# windsock on the annex roof
b.beam((12.0, 7.0, 7.3), (12.0, 7.0, 11.8), 0.09, 0.09, 4, "Metal")
for k, (r0, r1, m_) in enumerate(((0.45, 0.38, "RedPaint"), (0.38, 0.3, "WhitePaint"), (0.3, 0.22, "RedPaint"), (0.22, 0.14, "WhitePaint"))):
    b.cyl((12.0 + 0.2 + 0.35 + k * 0.5, 7.0, 11.55), r0, 0.5, 6, m_, axis="X", r_top=r1, caps=False)
b.beam((12.0, 7.0, 11.8), (12.15, 7.0, 11.55), 0.05, 0.05, 4, "Metal")

a.fin(b, "Body")
a.mark("HangarDoor", (DC, Y1 + 0.1, 0.0))
a.mark("Door", (12.0, Y1 + 0.3, 0.0))
report(a)
