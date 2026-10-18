"""lane13 police props: spike_strip (4 m), police_barrier (3 m, with LightBar), police_tape (2 m on stands), roadblock_sign (detour sign).
All: origin = footprint centre on the ground, front +Y, run along X, flat shaded."""

CAT = "GTA_GODOT/StreetProps"


def build_spike_strip():
    A = A13("spike_strip", 100, CAT, spacing=8.0)
    b = HB("spike_strip_body")
    n = 8
    seg = 4.0 / n
    b.abox(-2.0, 2.0, -0.12, 0.12, 0.0, 0.012, "Trim")                                          # dark underlay shows through the hinge gaps
    for i in range(n):
        x0 = -2.0 + i * seg
        xc = x0 + seg / 2
        b.abox(x0 + 0.014, x0 + seg - 0.014, -0.14, 0.14, 0.012, 0.045, "MetalDark", "-z")      # hinged plate
        b.zq(0.0455, x0 + 0.014, x0 + seg - 0.014, -0.14, -0.115, 1, "Hazard")                   # hazard edge strips
        b.zq(0.0455, x0 + 0.014, x0 + seg - 0.014, 0.115, 0.14, 1, "Hazard")
        for (dx, dy) in ((-0.15, -0.05), (0.0, -0.05), (0.15, -0.05), (-0.075, 0.05), (0.075, 0.05)):
            px, py = xc + dx, dy
            r = 0.022
            apex = (px, py, 0.135)
            base = [(px - r, py - r, 0.045), (px + r, py - r, 0.045), (px, py + r * 1.1, 0.045)]
            for k in range(3):
                b.pq([base[k], base[(k + 1) % 3], apex], ((base[k][0] + base[(k + 1) % 3][0]) / 2 - px, (base[k][1] + base[(k + 1) % 3][1]) / 2 - py, 0.3), "Chrome")
    for sx in (-1, 1):                                                                          # end handles
        b.abox(sx * 2.0 - (0.0 if sx > 0 else 0.07), sx * 2.0 + (0.07 if sx > 0 else 0.0), -0.16, 0.16, 0.0, 0.07, "Hazard", "-z")
        b.cyl((sx * 2.1, 0.0, 0.025), 0.02, 0.2, 4, "Hazard", axis="X")
    A.mesh(b, "Body", uv=None)
    return A


def build_police_barrier():
    A = A13("police_barrier", 101, CAT, spacing=8.0)
    b = HB("police_barrier_body")
    L = 3.0
    zb0, zb1 = 0.72, 1.0
    # A-frame legs
    for sx in (-1.15, 1.15):
        for sy in (-1, 1):
            b.rbeam((sx, sy * 0.40, 0.04), (sx, sy * 0.02, 0.95), 0.07, 0.05, "Metal", up=(1, 0, 0))
        b.abox(sx - 0.05, sx + 0.05, -0.50, 0.50, 0.0, 0.06, "MetalDark")                       # skids
        b.abox(sx - 0.06, sx + 0.06, -0.06, 0.06, 0.88, 0.99, "MetalDark")                      # top joint
    # boards: upper (stripes) + lower (navy)
    b.abox(-L / 2, L / 2, -0.04, 0.04, 0.72, 1.0, "PoliceNavy")
    b.abox(-L / 2, L / 2, -0.035, 0.035, 0.38, 0.62, "PoliceNavy")
    # white diagonal stripes on both faces (upper board)
    k = 11
    w = L / k
    for i in range(0, k, 2):
        xa = -L / 2 + i * w
        for (yf, s) in ((0.041, 1), (-0.041, -1)):
            cl = lambda x: max(-L / 2 + 0.005, min(L / 2 - 0.005, x))
            b.pq([(cl(xa), yf, 0.72), (cl(xa + w * 0.7), yf, 0.72), (cl(xa + w * 0.7 + 0.2), yf, 1.0), (cl(xa + 0.2), yf, 1.0)], (0, s, 0), "PlateWhite")
    for (yf, s) in ((0.036, 1), (-0.036, -1)):
        b.yq(yf, -L / 2 + 0.05, L / 2 - 0.05, 0.47, 0.53, s, "Reflector")                       # reflective band
    b.abox(-L / 2 - 0.04, -L / 2, -0.05, 0.05, 0.36, 1.02, "MetalDark")                         # end caps
    b.abox(L / 2, L / 2 + 0.04, -0.05, 0.05, 0.36, 1.02, "MetalDark")
    A.mesh(b, "Body", uv=None)
    # light bar (separate mesh, origin = bottom centre) with flashing Blue / Red halves
    lb = HB("police_barrier_lightbar")
    lb.abox(-0.50, 0.50, -0.10, 0.10, 0.0, 0.05, "MetalDark")
    lb.abox(-0.46, -0.02, -0.075, 0.075, 0.05, 0.17, "LightBlue", "-z")
    lb.abox(0.02, 0.46, -0.075, 0.075, 0.05, 0.17, "LightRed", "-z")
    lb.abox(-0.03, 0.03, -0.075, 0.075, 0.05, 0.17, "Trim", "-z")
    lb.abox(-0.50, 0.50, -0.10, 0.10, 0.17, 0.2, "Trim", "-z")
    A.mesh(lb, "LightBar", loc=(0, 0, 1.0), uv=None)
    A.mark("LightPoint", (0, 0, 1.12), size=0.15)
    return A


def build_police_tape():
    A = A13("police_tape", 102, CAT, spacing=8.0)
    b = HB("police_tape_body")
    for sx in (-1.0, 1.0):
        b.lathe([(1.1, 0.0), (1.1, 0.03), (0.16, 0.03), (0.16, 0.2), (0.0, 0.2), (0.0, 0.0)], (sx, 0.0, 0.0), 8, "Hazard", axis="Z")
        b.cyl((sx, 0.0, 0.08), 0.21, 0.16, 8, "TargetBlack", r_top=0.06, caps="b")                      # weighted foot
        b.ball((sx, 0.0, 1.12), 0.045, 6, 3, "TargetBlack")
    for z, wv in ((0.95, 0.0), (0.7, 0.0)):
        n = 12
        w = 2.0 / n
        for i in range(n):
            xa = -1.0 + i * w
            sag0 = 0.05 * math.sin(math.pi * i / n)
            sag1 = 0.05 * math.sin(math.pi * (i + 1) / n)
            q = [(xa, 0.0, z - sag0), (xa + w, 0.0, z - sag1), (xa + w, 0.0, z - sag1 + 0.075), (xa, 0.0, z - sag0 + 0.075)]
            m = "Hazard" if i % 2 == 0 else "TargetBlack"
            b.pq(q, (0, 1, 0), m)
    A.mesh(b, "Body", uv=None)
    return A


def build_roadblock_sign():
    A = A13("roadblock_sign", 103, CAT, spacing=8.0)
    b = HB("roadblock_sign_body")
    # stand: base cross + post + two ballast bags
    b.abox(-0.45, 0.45, -0.07, 0.07, 0.0, 0.06, "MetalDark")
    b.abox(-0.07, 0.07, -0.40, 0.40, 0.0, 0.06, "MetalDark")
    b.abox(-0.45, -0.20, -0.14, 0.14, 0.06, 0.2, "SandBag")
    b.abox(0.20, 0.45, -0.14, 0.14, 0.06, 0.2, "SandBag")
    b.abox(-0.035, 0.035, -0.035, 0.035, 0.06, 1.28, "Metal")
    # orange diamond sign (centre z 1.65), black rim, black bent arrow
    cz, R = 1.65, 0.50
    dia = lambda r, yy: [(-r, yy, cz), (0, yy, cz - r), (r, yy, cz), (0, yy, cz + r)]
    b.ey([(-R, cz), (0, cz - R), (R, cz), (0, cz + R)], -0.02, 0.03, "TargetBlack")
    b.pq(dia(R * 0.9, 0.032), (0, 1, 0), "SafetyOrange")
    b.pq(dia(R * 0.9, 0.032 - 0.065), (0, -1, 0), "SafetyOrange")
    ay = 0.036
    # detour arrow: up then bending right (all black)
    b.pq([(-0.07, ay, cz - 0.30), (0.07, ay, cz - 0.30), (0.07, ay, cz - 0.02), (-0.07, ay, cz - 0.02)], (0, 1, 0), "TargetBlack")
    b.pq([(-0.07, ay, cz - 0.02), (0.30, ay, cz + 0.12), (0.30, ay, cz + 0.26), (-0.07, ay, cz + 0.12)], (0, 1, 0), "TargetBlack")
    b.pq([(0.22, ay, cz + 0.36), (0.44, ay, cz + 0.12), (0.12, ay, cz + 0.06)], (0, 1, 0), "TargetBlack")
    # reflective corner studs
    for (dx, dz) in ((0.0, 0.42), (0.42, 0.0), (-0.42, 0.0), (0.0, -0.42)):
        b.cyl((dx * 0.97, 0.038, cz + dz * 0.97), 0.025, 0.014, 6, "Reflector", axis="Y", caps="t")
    # DETOUR plaque (non-text: chevrons) under the diamond
    pz = 0.98
    b.abox(-0.45, 0.45, -0.025, 0.025, pz, pz + 0.30, "SafetyOrange")
    b.abox(-0.47, 0.47, -0.03, 0.03, pz - 0.02, pz, "TargetBlack")
    b.abox(-0.47, 0.47, -0.03, 0.03, pz + 0.30, pz + 0.32, "TargetBlack")
    for i in range(5):
        x = -0.32 + i * 0.16
        b.pq([(x - 0.05, 0.027, pz + 0.05), (x + 0.02, 0.027, pz + 0.15), (x - 0.05, 0.027, pz + 0.25), (x - 0.01, 0.027, pz + 0.25), (x + 0.06, 0.027, pz + 0.15), (x - 0.01, 0.027, pz + 0.05)], (0, 1, 0), "TargetBlack")
    # amber warning lamp on top
    b.cyl((0, 0.0, 2.17), 0.07, 0.04, 8, "MetalDark", caps="t")
    b.cyl((0, 0.0, 2.24), 0.09, 0.12, 8, "LightAmber", caps="t")
    b.cyl((0, 0.0, 2.31), 0.095, 0.02, 8, "MetalDark", caps="t")
    A.mesh(b, "Body", uv=None)
    A.mark("LightPoint", (0, 0.0, 2.24), size=0.12)
    return A


A1 = build_spike_strip()
A1.report(400)
A2 = build_police_barrier()
A2.report(500)
A3 = build_police_tape()
A3.report(350)
A4 = build_roadblock_sign()
A4.report(450)
