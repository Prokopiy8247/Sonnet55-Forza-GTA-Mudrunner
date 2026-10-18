# lane 8 - container_stack: 2 x 3 x 2 shipping containers (12.2 x 7.5 m), colour-varied via WallA..WallD
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane8_lib.py", encoding="utf8").read(), globals())

a = A8("container_stack", 13)
b = a.b("Body")
CL, CW, CH = 6.0, 2.42, 2.55          # body length (x), width (y), height (z)
GX, GY = 6.06, 2.49                   # grid pitch
ZBASE = 0.1                           # containers sit on small concrete sleepers
LAYERS = [
    {(0, 0): "WallB", (1, 0): "WallC", (0, 1): "WallA", (1, 1): "WallD", (0, 2): "WallC", (1, 2): "WallB"},
    {(0, 0): "WallD", (1, 0): "WallA", (0, 1): "WallB", (1, 2): "WallC"},
]


def rib(x, yf, z0, z1, s, w=0.11, d=0.07, mat="WallA"):
    yt = yf + s * d
    q1 = [(x, yt, z0), (x - w, yf, z0), (x - w, yf, z1), (x, yt, z1)]
    q2 = [(x + w, yf, z0), (x, yt, z0), (x, yt, z1), (x + w, yf, z1)]
    for q in (q1, q2):
        if s < 0:
            q = [q[0], q[3], q[2], q[1]]
        b.quad(q[0], q[1], q[2], q[3], mat)


def door_end(cx, cy, z0, nx):
    x = cx + nx * (CL / 2)
    h = CH - 0.3
    zc = z0 + CH / 2
    for yy in (-0.85, -0.45, 0.45, 0.85):
        b.box((x + nx * 0.03, cy + yy, zc), (0.06, 0.07, h), "Metal")
    b.box((x + nx * 0.03, cy, zc), (0.05, 0.05, h + 0.05), "Trim")
    b.box((x + nx * 0.03, cy, z0 + 0.22), (0.05, CW - 0.2, 0.1), "Trim")
    b.box((x + nx * 0.03, cy, z0 + CH - 0.22), (0.05, CW - 0.2, 0.1), "Trim")
    b.box((x + nx * 0.07, cy + 0.45, zc), (0.1, 0.1, 0.18), "MetalDark")


for li, layer in enumerate(LAYERS):
    z0 = ZBASE + li * CH
    for (c, r), mat in layer.items():
        cx = (c - 0.5) * GX
        cy = (r - 1) * GY
        b.box((cx, cy, z0 + CH / 2), (CL, CW, CH), mat)
        # corner castings on the top corners
        for sx in (-1, 1):
            for sy in (-1, 1):
                b.box((cx + sx * (CL / 2 - 0.1), cy + sy * (CW / 2 - 0.1), z0 + CH - 0.07), (0.28, 0.28, 0.16), "Trim")
        # bottom / top side rails (reads as the frame)
        b.box((cx, cy, z0 + 0.07), (CL + 0.04, CW + 0.04, 0.14), "MetalDark")
        # exposed long sides get corrugation ribs
        for s in (-1, 1):
            nr = r + s
            exposed = (li == 0 and (nr < 0 or nr > 2)) or (li == 1 and (c, nr) not in layer) or (li == 0 and (c, nr) not in layer)
            if exposed:
                yf = cy + s * (CW / 2)
                for k in range(11):
                    rib(cx - CL / 2 + 0.3 + k * 0.54, yf, z0 + 0.25, z0 + CH - 0.25, s, mat=mat)
        # exposed ends get door gear
        for nx in (-1, 1):
            nc = c + nx
            if (nc, r) not in layer:
                door_end(cx, cy, z0, nx)
        # sleepers under the bottom layer
        if li == 0:
            for dx in (-2.2, 2.2):
                b.box((cx + dx, cy, ZBASE / 2), (0.5, CW, ZBASE), "Concrete")

a.fin(b, "Body")
a.mark("Door", (0, 3.9, 0.0))
report(a)
