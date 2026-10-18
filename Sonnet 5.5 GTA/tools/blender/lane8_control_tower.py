# lane 8 - control_tower: airport control tower, 8x8 m base, shaft to 28 m, wide glazed cab, rotating radar (own mesh)
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("control_tower", 3)
b = a.b("Body")
N = 8
ROT = -math.pi / 8     # facet centres on the axes

# ---- base building 8 x 8 x 4.4
P = rect_pts(0, 0, 8.0, 8.0, 0.0)
shaft(b, inflate(P, 0.15), 0, 0.5, "Concrete", "Concrete")
shaft(b, P, 0.3, 4.4, "WallD", "Roof")
glaze(b, P, 1.5, 3.3, "Window", bay=2.0, gap=0.5, edge=0.6, skip=(2,))
belt_ring(b, P, 3.9, 4.4, 0.2, "RedPaint")
parapet(b, P, 4.4, 5.0, 0.3, "WallD")
b.box((0, 4.35, 1.2), (1.4, 0.25, 2.4), "MetalDark")           # door leaf
b.box((0, 4.9, 2.7), (2.6, 1.6, 0.25), "Trim")                 # door canopy
b.box((-2.6, 2.0, 5.3), (1.6, 1.4, 0.9), "MetalDark")          # roof AC
b.box((2.4, -1.5, 5.3), (1.2, 1.2, 0.9), "MetalDark")

# ---- shaft: 4.4 .. 28, red/white bands, tapered
def rs(z):
    return 2.55 - (z - 4.4) * (0.75 / 23.6)

bands = [(4.4, 8.4, "WallD"), (8.4, 12.4, "RedPaint"), (12.4, 16.4, "WallD"), (16.4, 20.4, "RedPaint"), (20.4, 24.4, "WallD"), (24.4, 28.0, "RedPaint")]
for (z0, z1, m) in bands:
    b.loft([ring3(z0, rs(z0), N, ROT), ring3(z1, rs(z1), N, ROT)], m, cap_start=False, cap_end=False)
# slit windows on the 4 axis facets
for z0, z1 in ((6.0, 7.4), (13.8, 15.2), (21.6, 23.0)):
    for k in range(4):
        ang = ROT + math.pi / N + k * math.pi / 2
        # facet index k*2 (centres at 0, 90, ...)
        i = k * 2
        a0 = ROT + 2 * math.pi * i / N
        a1 = a0 + 2 * math.pi / N
        am = (a0 + a1) / 2
        for (zz0, zz1) in ((z0, z1),):
            def pt(f, z):
                r = rs(z)
                x0, y0 = math.cos(a0) * r, math.sin(a0) * r
                x1, y1 = math.cos(a1) * r, math.sin(a1) * r
                return (x0 + (x1 - x0) * f + math.cos(am) * 0.06, y0 + (y1 - y0) * f + math.sin(am) * 0.06, z)
            b.quad(pt(0.3, zz0), pt(0.7, zz0), pt(0.7, zz1), pt(0.3, zz1), "Window")
# base collar ring
b.loft([ring3(4.4, 2.9, N, ROT), ring3(4.8, 2.55, N, ROT)], "Concrete", cap_start=False, cap_end=False)

# ---- flare to the cab deck
b.loft([ring3(28.0, rs(28.0), N, ROT), ring3(29.0, 3.3, N, ROT)], "WallD", cap_start=False, cap_end=False)
b.loft([ring3(29.0, 3.3, N, ROT), ring3(29.0, 4.2, N, ROT)], "Trim", cap_start=False, cap_end=False)      # deck underside lip (flat ring)
# deck slab
b.prism(circ_pts(0, 0, 4.2, N, ROT), 29.0, 29.35, "Trim", cap_bottom=True, cap_top=True)
# railing
for i in range(N):
    ang = ROT + 2 * math.pi * i / N
    x, y = 4.12 * math.cos(ang), 4.12 * math.sin(ang)
    b.beam((x, y, 29.35), (x, y, 30.45), 0.05, 0.05, 4, "Metal", caps=False)
for i in range(N):
    a0 = ROT + 2 * math.pi * i / N
    a1 = a0 + 2 * math.pi / N
    b.beam((4.12 * math.cos(a0), 4.12 * math.sin(a0), 30.4), (4.12 * math.cos(a1), 4.12 * math.sin(a1), 30.4), 0.05, 0.05, 4, "Metal", caps=False)

# ---- cab: leaning glass walls, mullions, sill, roof
CB, CT = 3.1, 3.95
zc0, zc1 = 29.5, 33.0
ringb = ring3(zc0, CB, N, ROT)
ringt = ring3(zc1, CT, N, ROT)
b.loft([ring3(zc0, CB, N, ROT), ring3(zc0 + 0.9, CB + 0.18, N, ROT)], "WallD", cap_start=False, cap_end=False)      # sill wall
for i in range(N):
    j = (i + 1) % N
    p0 = lerp(ringb[i], ringt[i], 0.25)
    p1 = lerp(ringb[j], ringt[j], 0.25)
    q0, q1 = ringt[i], ringt[j]
    # glass panel from sill top to cab top (inset 0.03 outward-free: sits on the facet plane + 0.04)
    am = ROT + 2 * math.pi * (i + 0.5) / N
    nx, ny = math.cos(am) * 0.04, math.sin(am) * 0.04
    b.quad((p0.x + nx, p0.y + ny, p0.z), (p1.x + nx, p1.y + ny, p1.z), (q1.x + nx, q1.y + ny, q1.z), (q0.x + nx, q0.y + ny, q0.z), "Glass")
    b.beam(ringb[i] + Vector((0, 0, 0.9)), ringt[i], 0.09, 0.09, 4, "Trim", caps=False)
# top frame ring + roof
b.loft([ring3(zc1 - 0.25, CT - 0.02, N, ROT), ring3(zc1 + 0.1, 4.25, N, ROT)], "Trim", cap_start=False, cap_end=False)
b.loft([ring3(zc1 + 0.1, 4.25, N, ROT), ring3(zc1 + 0.5, 4.35, N, ROT), ring3(zc1 + 0.5, 3.0, N, ROT), ring3(zc1 + 1.2, 1.6, N, ROT)], "WallD", cap_start=False, cap_end=True)
b.cyl((0, 0, zc1 + 1.9), 0.38, 1.4, 8, "Metal")
# interior console ring + screens (seen through the glass)
b.prism(circ_pts(0, 0, 2.5, N, ROT), 29.4, 30.3, "Interior", cap_bottom=False, cap_top=True)
for k in range(4):
    ang = math.pi / 4 + k * math.pi / 2
    b.box((2.35 * math.cos(ang), 2.35 * math.sin(ang), 30.55), (0.5, 0.5, 0.5), "LightBlue")
# roof beacon + small lights
b.sphere((0, 0, zc1 + 2.75), 0.26, 6, 4, "LightRed")
for i in range(4):
    ang = i * math.pi / 2
    b.box((3.9 * math.cos(ang), 3.9 * math.sin(ang), zc1 + 0.7), (0.3, 0.3, 0.3), "LightAmber")

a.fin(b, "Body")

# ---- radar: separate rotating mesh, origin on the mast axis
rb = a.b("Radar")
rb.cyl((0, 0, 0.35), 0.28, 0.7, 8, "MetalDark")
rb.box((0, 0, 1.0), (0.7, 0.45, 0.5), "Metal")
rb.box((0, 0, 1.6), (3.8, 0.22, 1.1), "Metal")                 # antenna reflector
rb.box((0, 0.25, 1.6), (3.5, 0.12, 0.2), "Trim")
rb.box((0, 0.25, 2.0), (3.5, 0.12, 0.12), "Trim")
rb.box((0, 0.25, 1.2), (3.5, 0.12, 0.12), "Trim")
rb.box((0, 0.5, 1.6), (0.35, 0.6, 0.35), "MetalDark")           # feed horn
a.fin(rb, "Radar", loc=(0, 0, zc1 + 2.6))

a.mark("Door", (0, 4.4, 0.0))
report(a)
