# lane 8 - ferris_wheel: 30 m wheel. Node `Wheel` (mesh, origin = hub, rotate about Godot local Z) carries 12 child nodes Gondola_00..11
# (origin = hang pivot at the rim; counter-rotate them by -wheel angle to keep them upright). `Base` is static (legs, axle, boarding platform).
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("ferris_wheel", 15)
R = 15.0            # rim radius (30 m diameter)
HUB = 19.4          # hub height above ground
NV = 24             # rim vertices
YR = 1.7            # half distance between the two rims


def rv(i, y, r=R):
    t = 2 * math.pi * (i % NV) / NV
    return (r * math.cos(t), y, r * math.sin(t))


# ======================================================== WHEEL (rotating) ; local origin = hub
wb = a.b("Wheel")
for y in (-YR, YR):
    for i in range(NV):
        wb.beam(rv(i, y), rv(i + 1, y), 0.27, 0.27, 4, "WhitePaint", caps=False)
    for i in range(0, NV, 2):
        wb.beam((0.0, y * 1.1, 0.0), rv(i, y, R - 0.15), 0.17, 0.12, 4, "WhitePaint", caps=False)       # spokes
for i in range(NV):
    if i % 2 == 0:
        wb.beam(rv(i, -YR), rv(i, YR), 0.13, 0.13, 4, "Metal", caps=False)                             # cross struts (gondola axles)
    # rim lights on the outside, alternating colours
    t = 2 * math.pi * i / NV
    c = Vector((math.cos(t), 0, math.sin(t)))
    rr = R + 0.38
    obox(wb, (rr * c.x, 0, rr * c.z), (c.x, 0, c.z), (0, 1, 0), (-c.z, 0, c.x), 0.34, 0.5, 0.34, "Neon" if i % 2 == 0 else "NeonCyan")
# inner ring + hub
for y in (-YR, YR):
    for i in range(0, NV, 2):
        wb.beam(rv(i, y, 6.2), rv(i + 2, y, 6.2), 0.14, 0.14, 4, "Metal", caps=False)
wb.cyl((0, 0, 0), 1.35, 4.2, 10, "RedPaint", axis="Y")
wb.cyl((0, 0, 0), 0.8, 5.0, 8, "Metal", axis="Y")
wb.cyl((0, 2.5, 0), 1.0, 0.4, 10, "NeonCyan", axis="Y")
wheel = a.fin(wb, "Wheel", loc=(0, 0, HUB))

# ---- gondolas (4 colour variants, shared mesh data)
variants = []
BODY = ["WallB", "WallC", "WallA", "WallD"]
ROOF = ["Trim", "RedPaint", "Trim", "RedPaint"]
for vi in range(4):
    g = a.b("GondolaV%d" % vi)
    g.beam((0, 0, 0.0), (0, 0, -0.95), 0.07, 0.07, 4, "Metal", caps=False)                         # hanger rod
    hexa(g, [(-1.5, -1.15, -1.25), (1.5, -1.15, -1.25), (1.5, 1.15, -1.25), (-1.5, 1.15, -1.25)],
            [(-0.6, -0.45, -0.95), (0.6, -0.45, -0.95), (0.6, 0.45, -0.95), (-0.6, 0.45, -0.95)], ROOF[vi])
    g.box((0, 0, -0.9), (0.22, 0.22, 0.14), "LampGlow")
    g.box((0, 0, -3.0), (2.6, 2.0, 0.9), BODY[vi])                                                    # skirt
    for sx in (-1, 1):
        for sy in (-1, 1):
            g.beam((sx * 1.2, sy * 0.9, -2.55), (sx * 1.2, sy * 0.9, -1.25), 0.06, 0.06, 4, "Metal", caps=False)
    for (x, y, nx, ny) in ((0, 0.93, 0, 1), (0, -0.93, 0, -1), (1.23, 0, 1, 0), (-1.23, 0, -1, 0)):
        if nx == 0:
            xa, xb = (1.15, -1.15) if ny > 0 else (-1.15, 1.15)
            g.quad((xa, y, -2.5), (xb, y, -2.5), (xb, y, -1.4), (xa, y, -1.4), "Glass")
        else:
            ya, yb = (-0.85, 0.85) if nx > 0 else (0.85, -0.85)
            g.quad((x, ya, -2.5), (x, yb, -2.5), (x, yb, -1.4), (x, ya, -1.4), "Glass")
    g.box((0, 0, -3.5), (2.7, 2.1, 0.12), "MetalDark")
    obj = a.fin(g, "GondolaV%d" % vi, loc=(0, 0, 0), parent=wheel)
    variants.append(obj)
    bpy.context.view_layer.update()

# turn the 4 template objects into real gondolas: build 12 objects that share the variant meshes
tmpl = [(o.data) for o in variants]
for o in variants:
    bpy.data.objects.remove(o, do_unlink=True)
for i in range(12):
    t = 2 * math.pi * i / 12
    ob = bpy.data.objects.new("ferris_wheel__Gondola_%02d" % i, tmpl[i % 4])
    ob.location = Vector((R * math.cos(t), 0.0, R * math.sin(t)))
    a.c.objects.link(ob)
    ob.parent = wheel

# ======================================================== BASE (static) ; origin = footprint centre on the ground
bb = a.b("Base")
for sy in (-1, 1):
    y = sy * 2.6
    yf = sy * 5.4
    for sx in (-1, 1):
        bb.beam((sx * 9.6, yf, 0.45), (sx * 0.9, y, HUB - 0.7), 0.55, 0.42, 6, "WhitePaint", caps=False)    # main legs (A-frame, splayed in Y)
        bb.box((sx * 9.6, yf, 0.25), (2.0, 2.0, 0.5), "Concrete")
    bb.beam((-5.2, yf * 0.8 + y * 0.2, 7.0), (5.2, yf * 0.8 + y * 0.2, 7.0), 0.22, 0.22, 4, "Metal", caps=False)  # cross braces
    bb.beam((-9.0, yf, 1.2), (4.4, y + (yf - y) * 0.5, 9.5), 0.14, 0.14, 4, "Metal", caps=False)
    bb.beam((9.0, yf, 1.2), (-4.4, y + (yf - y) * 0.5, 9.5), 0.14, 0.14, 4, "Metal", caps=False)
    bb.box((0, y * 1.15, HUB), (1.9, 1.0, 2.2), "MetalDark")                                                # bearing blocks
bb.cyl((0, 0, HUB), 0.5, 6.4, 8, "Metal", axis="Y")
bb.beam((-9.6, -5.4, 0.45), (-9.6, 5.4, 0.45), 0.2, 0.2, 4, "Metal", caps=False)
bb.beam((9.6, -5.4, 0.45), (9.6, 5.4, 0.45), 0.2, 0.2, 4, "Metal", caps=False)
# boarding platform in front of the lowest gondola + stairs + ticket booth + queue rails
bb.box((0, 5.0, 0.5), (8.0, 5.4, 1.0), "Concrete")
bb.box((0, 8.2, 0.2), (5.0, 1.0, 0.4), "Concrete")
bb.box((0, 7.9, 0.6), (5.0, 0.6, 0.2), "Concrete")
bb.box((-8.0, 6.0, 1.4), (2.6, 2.4, 2.8), "WallB")
bb.box((-8.0, 6.0, 2.95), (3.2, 3.0, 0.3), "Trim")
bb.quad((-6.69, 5.3, 1.2), (-6.69, 6.7, 1.2), (-6.69, 6.7, 2.2), (-6.69, 5.3, 2.2), "Window")
bb.box((-8.0, 7.25, 0.9), (2.0, 0.1, 0.1), "Wood")
for x in (-3.5, 3.5):
    for y in (2.8, 5.0, 7.2):
        bb.beam((x, y, 1.0), (x, y, 2.0), 0.05, 0.05, 4, "Metal", caps=False)
    bb.beam((x, 2.8, 1.9), (x, 7.2, 1.9), 0.04, 0.04, 4, "Metal", caps=False)
bb.box((0, 8.6, 3.2), (5.4, 0.15, 0.7), "Trim")
bb.box((0, 8.7, 3.2), (5.0, 0.1, 0.12), "NeonCyan")
base = a.fin(bb, "Base")

a.mark("Hub", (0, 0, 0), parent=wheel, size=1.0)
a.mark("Door", (0, 9.2, 0.0))
report(a)
