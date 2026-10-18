"""lane7 gas_station: canopy 16 x 10 on 4 pillars (emissive LampGlow underside), Pump_1..4 meshes, shop 12 x 8, neon price pylon."""
A = Asset("gas_station", 5)
b = HB("gas_station_body")
RED, WHT = "GasRed", "TrimWhite"

# ---------------------------------------------------------------- shop (back, x -6..6, y -11..-3)
SX0, SX1, SY0, SY1, SH = -6.0, 6.0, -11.0, -3.0, 3.8
SF = Side(b, "F", 0, -7, 6, 4)
SB = Side(b, "B", 0, -7, 6, 4)
SL = Side(b, "L", 0, -7, 6, 4)
SR = Side(b, "R", 0, -7, 6, 4)
panes = [(-5.4, -1.35, 0.35, 2.95), (1.35, 5.4, 0.35, 2.95)]
sdoor = (-1.15, 1.15, 0.0, 2.55)
SF.wall(-6, 6, 0, SH, panes + [sdoor], WHT)
for h in panes:
    SF.reveal(h, 0.22, "Metal", "lrt")
    SF.q(h[0], h[1], h[2], h[3], -0.22, "Window")
    for k in (1, 2):                                    # mullions
        u = h[0] + (h[1] - h[0]) * k / 3
        SF.q(u - 0.04, u + 0.04, h[2], h[3], -0.2, "Metal")
    SF.q(h[0], h[1], 1.2, 1.28, -0.2, "Metal")
SF.reveal(sdoor, 0.3, "Metal", "lrt")
SF.q(sdoor[0], sdoor[1], 0, 2.55, -0.3, "Window")
SF.q(-0.04, 0.04, 0, 2.55, -0.27, "Metal")
SF.box(-1.5, 1.5, 2.95, 3.15, 0.0, 1.0, RED, skip="i")                                      # door awning
SF.q(-6, 6, 0.0, 0.3, 0.03, "ConcreteDk")
# neon cup icons on the red band
for cu in (-3.6, 3.6):
    SF.poly([(cu - 0.22, 3.12), (cu + 0.22, 3.12), (cu + 0.3, 3.6), (cu - 0.3, 3.6)], 0.05, "NeonAmber")
    SF.stroke((cu + 0.3, 3.5), (cu + 0.52, 3.4), 0.05, 0.05, "NeonAmber")
    SF.stroke((cu + 0.52, 3.4), (cu + 0.48, 3.22), 0.05, 0.05, "NeonAmber")
    SF.stroke((cu + 0.48, 3.22), (cu + 0.24, 3.16), 0.05, 0.05, "NeonAmber")
# red band + glowing strip
SF.q(-6, 6, 3.0, 3.8, 0.02, RED)
SF.q(-6, 6, 3.55, 3.65, 0.04, "LampGlow")
for S in (SL, SR):
    holes = [(u - 1.0, u + 1.0, 1.0, 2.6) for u in (-2.0, 2.0)]
    S.openings(-4, 4, 0, SH, holes, WHT, depth=0.2, frame="Metal")
    S.q(-4, 4, 3.0, 3.8, 0.02, RED)
hb = [(u - 0.6, u + 0.6, 2.3, 3.0) for u in (-4.0, 4.0)] + [(2.5, 3.8, 0.0, 2.2)]
SB.wall(-6, 6, 0, SH, hb, WHT)
SB.q(-6, 6, 3.0, 3.8, 0.02, RED)
b.zq(SH, SX0, SX1, SY0, SY1, 1, "Roof")
b.abox(SX0 - 0.3, SX1 + 0.3, SY0 - 0.3, SY1 + 0.45, SH - 0.2, SH + 0.12, WHT, "-z")
parapet(b, SX0 - 0.3, SX1 + 0.3, SY0 - 0.3, SY1 + 0.45, SH + 0.12, SH + 0.6, 0.22, WHT)
# tall roof fascia at the front with glowing stripes
b.abox(SX0 - 0.3, SX1 + 0.3, SY1 + 0.45 - 0.5, SY1 + 0.45, SH + 0.6, SH + 1.7, RED, "-z")
b.yq(SY1 + 0.46, SX0 - 0.3, SX1 + 0.3, SH + 1.0, SH + 1.12, 1, "LampGlow")
b.yq(SY1 + 0.46, SX0 - 0.3, SX1 + 0.3, SH + 1.3, SH + 1.42, 1, WHT)
ac_unit(b, -2.5, -8.0, SH, 2.0, 1.6, 1.0)
ac_unit(b, 2.5, -8.0, SH, 2.0, 1.6, 1.0)
# ice box + bin + air station beside the shop
b.abox(-5.9, -4.6, SY1, SY1 + 0.85, 0.0, 1.9, WHT, "-z -y")
b.yq(SY1 + 0.86, -5.7, -4.8, 0.3, 1.6, 1, "Window")
b.cyl((5.6, SY1 + 0.5, 0.45), 0.28, 0.9, 6, "MetalDark", caps="t")
b.abox(5.0, 5.9, SY1 + 1.3, SY1 + 1.7, 0.0, 1.4, "Metal", "-z")

# ---------------------------------------------------------------- canopy (x -8..8, y 0.5..10.5, z 5.0..5.5)
CY0, CY1, CZ = 0.5, 10.5, 5.0
b.abox(-8.0, 8.0, CY0, CY1, CZ, CZ + 0.5, WHT, "-z")
b.zq(CZ - 0.01, -7.9, 7.9, CY0 + 0.1, CY1 - 0.1, -1, "LampGlow")                         # emissive underside
# fascia ring (taller edge) with coloured stripes
t = 0.25
b.abox(-8.0, 8.0, CY1 - t, CY1, CZ + 0.5, CZ + 1.1, WHT, "-z -y")
b.abox(-8.0, 8.0, CY0, CY0 + t, CZ + 0.5, CZ + 1.1, WHT, "-z +y")
b.abox(-8.0, -8.0 + t, CY0 + t, CY1 - t, CZ + 0.5, CZ + 1.1, WHT, "-z +x -y +y")
b.abox(8.0 - t, 8.0, CY0 + t, CY1 - t, CZ + 0.5, CZ + 1.1, WHT, "-z -x -y +y")
b.yq(CY1 + 0.01, -8.0, 8.0, CZ + 0.15, CZ + 0.4, 1, RED)
b.yq(CY1 + 0.01, -8.0, 8.0, CZ + 0.65, CZ + 0.9, 1, RED)
b.xq(8.01, CY0, CY1, CZ + 0.15, CZ + 0.4, 1, RED)
b.xq(-8.01, CY0, CY1, CZ + 0.15, CZ + 0.4, -1, RED)
b.yq(CY1 + 0.01, -8.0, 8.0, CZ + 0.42, CZ + 0.62, 1, "NeonCyan")
b.yq(CY0 - 0.01, -8.0, 8.0, CZ + 0.42, CZ + 0.62, -1, "NeonCyan")
# raised crown with the droplet logo (both faces)
b.abox(-3.4, 3.4, CY1 - 0.3, CY1, CZ + 1.1, CZ + 2.5, "MetalDark", "-z")
b.abox(-3.5, 3.5, CY1 - 0.32, CY1 + 0.02, CZ + 2.5, CZ + 2.62, RED, "-z")
for nm_, dsgn in (("F", 1), ("B", -1)):
    Sc = Side(b, nm_, 0, CY1 - 0.15, 3.4, 0.15)
    cu, cv = 0.0, CZ + 1.8
    Sc.poly([(0.0, cv + 0.55), (0.34, cv + 0.08), (0.44, cv - 0.18), (0.34, cv - 0.42), (0.0, cv - 0.5), (-0.34, cv - 0.42), (-0.44, cv - 0.18), (-0.34, cv + 0.08)], 0.04, "NeonRed")
    Sc.poly([(0.0, cv + 0.38), (0.22, cv + 0.02), (0.3, cv - 0.18), (0.2, cv - 0.34), (0.0, cv - 0.38), (-0.2, cv - 0.34), (-0.3, cv - 0.18), (-0.22, cv + 0.02)], 0.06, "NeonAmber")
    for sg in (-1, 1):
        Sc.q(sg * 1.0, sg * 3.0, cv - 0.12, cv + 0.12, 0.04, "NeonCyan" if sg > 0 else "NeonAmber")
PIL = [(-5.5, 2.5), (5.5, 2.5), (-5.5, 8.5), (5.5, 8.5)]
for (px, py) in PIL:
    b.abox(px - 0.25, px + 0.25, py - 0.25, py + 0.25, 0.0, CZ, WHT, "-z")
    b.abox(px - 0.28, px + 0.28, py - 0.28, py + 0.28, 0.0, 0.9, RED, "-z")
    b.abox(px - 0.28, px + 0.28, py - 0.28, py + 0.28, CZ - 0.5, CZ - 0.35, RED, "-z +z")
# forecourt slab with painted lines
b.abox(-8.0, 8.0, -3.0, 11.0, 0.0, 0.08, "Concrete", "-z -x +x -y")
for (px, py) in ((-3.5, 3.2), (3.5, 3.2), (-3.5, 7.8), (3.5, 7.8)):
    for sx in (-0.9, 0.9):
        b.zq(0.09, px + sx - 0.05, px + sx + 0.05, py - 1.8, py + 1.8, 1, "RailYellow")
b.zq(0.09, -8.0, 8.0, 10.45, 10.6, 1, "RailYellow")

# ---------------------------------------------------------------- price pylon with neon sign
PX, PY = -7.1, 10.3
b.abox(PX - 0.18, PX + 0.18, PY - 0.18, PY + 0.18, 0.0, 6.4, "MetalDark", "-z")
b.abox(PX - 0.5, PX + 0.5, PY - 0.5, PY + 0.5, 0.0, 0.5, "Concrete", "-z")
b.abox(PX - 1.3, PX + 1.3, PY - 0.25, PY + 0.25, 5.6, 9.6, "MetalDark")
b.abox(PX - 1.35, PX + 1.35, PY - 0.3, PY + 0.3, 9.6, 9.8, RED)
b.abox(PX - 1.35, PX + 1.35, PY - 0.3, PY + 0.3, 5.5, 5.6, RED)
for nm_ in ("F", "B"):
    S = Side(b, nm_, PX, PY, 1.3, 0.25)
    # fuel droplet symbol
    cu, cv = 0.0, 8.5
    ring = [(0.0, cv + 1.0), (0.6, cv + 0.15), (0.78, cv - 0.3), (0.6, cv - 0.75), (0.0, cv - 0.9), (-0.6, cv - 0.75), (-0.78, cv - 0.3), (-0.6, cv + 0.15)]
    S.poly(ring, 0.28, "NeonRed")
    inner = [(0.0, cv + 0.75), (0.42, cv + 0.05), (0.52, cv - 0.3), (0.38, cv - 0.6), (0.0, cv - 0.68), (-0.38, cv - 0.6), (-0.52, cv - 0.3), (-0.42, cv + 0.05)]
    S.poly(inner, 0.31, "NeonAmber")
    for k, mm in enumerate(("NeonCyan", "NeonAmber", "NeonGreen")):
        v = 7.2 - k * 0.55
        S.q(-0.95, 0.95, v, v + 0.34, 0.28, mm)
        S.q(-1.15, -1.0, v + 0.05, v + 0.29, 0.28, "NeonWhite")

# ---------------------------------------------------------------- roof of the lot: bins, tyre stand
b.cyl((7.0, -1.0, 0.45), 0.3, 0.9, 6, "MetalDark", caps="t")
b.abox(-7.8, -6.6, -2.8, -1.6, 0.0, 1.1, "Metal", "-z")                 # air + water station
b.abox(-7.7, -6.7, -2.7, -1.7, 1.1, 1.5, RED, "-z")

A.mesh(b, "Body")

# ---------------------------------------------------------------- pumps (separate meshes, origin = base centre)
PUMPS = [(-3.5, 3.2), (3.5, 3.2), (-3.5, 7.8), (3.5, 7.8)]
for i, (px, py) in enumerate(PUMPS, start=1):
    pb = HB("gas_station_pump%d" % i)
    pb.abox(-0.6, 0.6, -1.5, 1.5, 0.0, 0.22, "Concrete", "-z")
    for sy in (-1.32, 1.32):
        pb.cyl((0, sy, 0.62), 0.11, 0.8, 6, "Hazard", caps="t")
    pb.abox(-0.3, 0.3, -0.5, 0.5, 0.22, 1.1, RED, "-z +z")
    pb.abox(-0.28, 0.28, -0.48, 0.48, 1.1, 1.72, WHT, "-z +z")
    pb.abox(-0.36, 0.36, -0.56, 0.56, 1.72, 1.9, "MetalDark")
    for sx in (-1, 1):
        pb.xq(sx * 0.285, -0.3, 0.3, 1.32, 1.62, sx, "LightAmber")
        pb.xq(sx * 0.285, -0.3, 0.3, 1.2, 1.28, sx, "MetalDark")
        pb.abox(0.3 if sx > 0 else -0.37, 0.37 if sx > 0 else -0.3, 0.12, 0.32, 0.75, 1.0, "Metal", "-z")
        pb.beam((sx * 0.32, 0.25, 0.9), (sx * 0.5, 0.42, 0.35), 0.03, 0.03, 4, "Trim", caps=False)
    A.mesh(pb, "Pump_%d" % i, loc=(px, py, 0.0), winuv=False)
    A.mark("PumpPoint_%d" % i, (px + (2.0 if px < 0 else -2.0), py, 0.0))

# ---------------------------------------------------------------- collision
c = HB("gas_station_col")
c.abox(SX0, SX1, SY0, SY1, 0, SH + 1.0, "Concrete", "-z")
for (px, py) in PIL:
    c.abox(px - 0.28, px + 0.28, py - 0.28, py + 0.28, 0, CZ, "Concrete", "-z")
for (px, py) in PUMPS:
    c.abox(px - 0.6, px + 0.6, py - 1.5, py + 1.5, 0, 1.2, "Concrete", "-z")
c.abox(PX - 0.2, PX + 0.2, PY - 0.2, PY + 0.2, 0, 6.4, "Concrete", "-z")
A.mesh(c, "Collision", uv=None, winuv=False)
A.mark("Door", (0.0, -1.9, 0.0))
rep = A.report()
