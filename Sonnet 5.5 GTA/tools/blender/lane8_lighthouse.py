# lane 8 - lighthouse: round tower 6 m dia, 32 m, red/white bands, gallery, glazed lantern room with emissive LampGlow
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("lighthouse", 14)
b = a.b("Body")
N = 16
ROT = math.pi / 16          # a facet centre faces +Y


def r_at(z):
    return 3.0 - (z - 1.0) * (1.05 / 25.5)


# ---- base platform (stepped) + porch
b.cyl((0, 0, 0.35), 4.3, 0.7, N, "Concrete", r_top=4.15)
b.cyl((0, 0, 0.85), 3.7, 0.3, N, "Concrete", r_top=3.55)
b.box((0, 3.6, 1.6), (2.8, 2.0, 1.8), "WhitePaint")                  # entrance porch
b.box((0, 3.6, 2.6), (3.2, 2.4, 0.3), "RedPaint")
b.box((0, 4.62, 1.2), (1.2, 0.2, 1.9), "MetalDark")                 # door
b.box((0, 4.72, 2.3), (1.6, 0.14, 0.14), "Trim")

# ---- tower bands (loft segments)
bands = [(0.7, 6.5, "WhitePaint"), (6.5, 12.0, "RedPaint"), (12.0, 17.5, "WhitePaint"), (17.5, 22.0, "RedPaint"), (22.0, 25.6, "WhitePaint")]
for (z0, z1, m) in bands:
    b.loft([ring3(z0, r_at(max(z0, 1.0)) + (0.12 if z0 < 1.0 else 0), N, ROT), ring3(z1, r_at(z1), N, ROT)], m, cap_start=False, cap_end=False)
# slit windows on the +Y and -Y facets
for z in (5.0, 10.5, 16.0, 21.0):
    for sgn in (1, -1):
        am = math.pi / 2 if sgn > 0 else -math.pi / 2
        r = r_at(z) * math.cos(math.pi / N)
        for (dz, w) in ((0.0, 0.32),):
            cx, cy = r * math.cos(am) + math.cos(am) * 0.06, r * math.sin(am) + math.sin(am) * 0.06
            t = Vector((-math.sin(am), math.cos(am), 0))
            p0 = Vector((cx, cy, z)) - t * w
            p1 = Vector((cx, cy, z)) + t * w
            b.quad((p0.x, p0.y, z - 0.7), (p1.x, p1.y, z - 0.7), (p1.x, p1.y, z + 0.7), (p0.x, p0.y, z + 0.7), "Window")
# gallery corbel + deck
b.loft([ring3(25.6, r_at(25.6), N, ROT), ring3(26.6, 3.55, N, ROT)], "Metal", cap_start=False, cap_end=False)
b.prism(circ_pts(0, 0, 3.6, N, ROT), 26.6, 27.0, "RedPaint", cap_bottom=False, cap_top=True)
b.loft([ring3(26.6, 3.6, N, ROT), ring3(27.0, 3.6, N, ROT)], "RedPaint", cap_start=False, cap_end=False)
for i in range(12):
    ang = 2 * math.pi * i / 12
    x, y = 3.35 * math.cos(ang), 3.35 * math.sin(ang)
    b.beam((x, y, 27.0), (x, y, 28.05), 0.05, 0.05, 4, "Metal", caps=False)
b.loft([ring3(27.92, 3.36, 12), ring3(28.1, 3.36, 12)], "Metal", cap_start=False, cap_end=False)
b.loft([ring3(27.4, 3.35, 12), ring3(27.52, 3.35, 12)], "Metal", cap_start=False, cap_end=False)

# ---- lantern room
LN = 12
LR = 1.7
b.cyl((0, 0, 27.3), 2.0, 0.6, LN, "RedPaint", r_top=1.8)               # lantern plinth
rb = ring3(27.6, LR, LN)
rt = ring3(30.6, LR, LN)
for i in range(LN):
    j = (i + 1) % LN
    am = 2 * math.pi * (i + 0.5) / LN
    nx, ny = math.cos(am) * 0.03, math.sin(am) * 0.03
    b.quad((rb[i].x + nx, rb[i].y + ny, 27.7), (rb[j].x + nx, rb[j].y + ny, 27.7), (rt[j].x + nx, rt[j].y + ny, 30.5), (rt[i].x + nx, rt[i].y + ny, 30.5), "Glass")
    b.beam(rb[i] + Vector((0, 0, 0.05)), rt[i], 0.07, 0.07, 4, "Trim", caps=False)
b.cyl((0, 0, 28.9), 0.55, 1.5, 10, "LampGlow", r_top=0.45)               # the lamp
b.cyl((0, 0, 28.9), 0.8, 0.14, 10, "LampGlow")
b.sphere((0, 0, 29.8), 0.4, 8, 4, "LampGlow")
b.cyl((0, 0, 27.7), 0.3, 0.2, 8, "Metal")
b.cyl((0, 0, 30.75), 2.05, 0.35, LN, "Trim", r_top=1.95)              # cornice
b.cyl((0, 0, 31.6), 1.95, 1.4, LN, "RedPaint", r_top=0.28)            # roof cone
b.sphere((0, 0, 32.4), 0.3, 6, 4, "Metal")
b.beam((0, 0, 32.6), (0, 0, 33.6), 0.05, 0.02, 4, "Metal")

# ---- rocks at the foot
for (ang, rad, sz, sq) in ((0.4, 4.9, 1.4, 0.7), (1.7, 5.0, 1.1, 0.6), (3.0, 4.8, 1.5, 0.75), (4.1, 5.0, 1.2, 0.65), (5.4, 4.9, 1.3, 0.7)):
    b.sphere((rad * math.cos(ang), rad * math.sin(ang), sz * sq * 0.8), sz, 6, 4, "Rock", scale=(1.2, 1.0, sq))

a.fin(b, "Body")
a.mark("Door", (0, 4.7, 0.0))
report(a)
