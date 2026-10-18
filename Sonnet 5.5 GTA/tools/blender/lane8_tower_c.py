# lane 8 - tower_c: curved/faceted cylinder tower, 24 m diameter, 75 m, rooftop restaurant ring + mast
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("tower_c", 2)
b = a.b("Body")
N = 16
ROT = math.pi / 16
SH = [(7.0, 9.9), (19.0, 9.3), (31.0, 8.6), (41.0, 8.9), (50.0, 10.2)]     # curved shaft profile (z, r)


def r_at(z):
    for (za, ra), (zb, rb) in zip(SH, SH[1:]):
        if za <= z <= zb:
            return ra + (rb - ra) * (z - za) / (zb - za)
    return SH[-1][1]


def panel(b, z0, z1, ra, rb, d0, d1, i, mat, out):
    """Planar window panel on facet i between z0 (radius ra) and z1 (radius rb); d0,d1 = fractional insets along the facet."""
    a0 = ROT + 2 * math.pi * i / N
    a1 = a0 + 2 * math.pi / N
    am = (a0 + a1) / 2
    nx, ny = math.cos(am) * out, math.sin(am) * out

    def pt(f, z, r):
        x0, y0 = math.cos(a0) * r, math.sin(a0) * r
        x1, y1 = math.cos(a1) * r, math.sin(a1) * r
        return (x0 + (x1 - x0) * f + nx, y0 + (y1 - y0) * f + ny, z)
    b.quad(pt(d0, z0, ra), pt(1 - d1, z0, ra), pt(1 - d1, z1, rb), pt(d0, z1, rb), mat)


# ---- podium (r 12, 7 m) with a glazed base
P = circ_pts(0, 0, 12.0, N, ROT)
shaft(b, inflate(P, 0.2), 0, 0.7, "Concrete", "Concrete")
shaft(b, P, 0.3, 7.0, "WallD", "Roof")
glaze(b, P, 1.6, 5.6, "Window", bay=None, edge=0.5)
belt_ring(b, P, 5.9, 7.0, 0.3, "Trim")
b.box((0, 11.8 + 1.2, 4.6), (7.0, 2.6, 0.35), "Trim")
b.box((0, 11.8 + 2.45, 4.6), (7.0, 0.22, 0.22), "NeonCyan")
for x in (-3.0, 3.0):
    b.cyl((x, 13.2, 2.3), 0.2, 4.6, 8, "Metal", caps=False)

# ---- curved shaft: core loft + window panels + bulging belts
rings = [ring3(z, r, N, ROT) for (z, r) in SH]
b.loft(rings, "WallC", cap_start=False, cap_end=False)
for (za, ra), (zb, rb) in zip(SH, SH[1:]):
    for i in range(N):
        panel(b, za + 1.0, zb - 1.0, r_at(za + 1.0), r_at(zb - 1.0), 0.14, 0.14, i, "Window", 0.07)


def bulge(z, extra=0.3, half=0.5, mat="Trim"):
    r = r_at(z)
    rr = [ring3(z - half, r_at(z - half), N, ROT), ring3(z - half + 0.18, r_at(z - half + 0.18) + extra, N, ROT),
          ring3(z + half - 0.18, r_at(z + half - 0.18) + extra, N, ROT), ring3(z + half, r_at(z + half), N, ROT)]
    b.loft(rr, mat, cap_start=False, cap_end=False)


for z in (19.0, 31.0, 41.0):
    bulge(z)
bulge(8.0, 0.35, 0.5)

# ---- restaurant ring: underside cone, glazed band, rim, roof
rr = [ring3(50.0, 10.2, N, ROT), ring3(51.8, 12.0, N, ROT)]
b.loft(rr, "WallD", cap_start=False, cap_end=False)
rr = [ring3(51.8, 12.0, N, ROT), ring3(58.0, 12.0, N, ROT)]
b.loft(rr, "Trim", cap_start=False, cap_end=False)
for i in range(N):
    panel(b, 52.4, 57.4, 12.0, 12.0, 0.06, 0.06, i, "Window", 0.08)
rr = [ring3(58.0, 12.0, N, ROT), ring3(58.4, 12.7, N, ROT), ring3(59.4, 12.7, N, ROT), ring3(59.4, 12.0, N, ROT)]
b.loft(rr, "WallD", cap_start=False, cap_end=False)
belt_ring(b, circ_pts(0, 0, 12.0, N, ROT), 51.5, 52.1, 0.35, "NeonCyan")      # glowing cyan underside lip
# roof cone + cap
rr = [ring3(59.4, 12.0, N, ROT), ring3(62.2, 5.2, N, ROT)]
b.loft(rr, "Roof", cap_start=False, cap_end=False)
b.cyl((0, 0, 63.1), 3.6, 1.8, N, "Metal", r_top=1.7)
# mast
b.beam((0, 0, 64.0), (0, 0, 74.8), 0.55, 0.1, 8, "Metal")
b.beam((-2.2, 0, 67.0), (2.2, 0, 67.0), 0.1, 0.1, 4, "Metal")
b.beam((0, -1.8, 70.0), (0, 1.8, 70.0), 0.1, 0.1, 4, "Metal")
b.sphere((0, 0, 75.0), 0.3, 6, 4, "LightRed")
# restaurant roof deck details: little vents
for ang in (0.5, 2.1, 3.7, 5.3):
    b.box((6.6 * math.cos(ang), 6.6 * math.sin(ang), 60.9), (1.0, 1.0, 1.0), "MetalDark")

a.fin(b, "Body")
a.mark("Door", (0, 11.8, 0.0))
report(a)
