"""lane6_kit_roof.py - kit_roof (rooftop props, origin = footprint centre on the roof surface, z=0). Idempotent."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane6_kitlib.py", encoding="utf8").read(), globals())
from mathutils import Matrix


def fan(b, cx, cy, z, r=0.44):
    b.cylk((cx, cy, z + 0.02), r, 0.04, 10, "MetalDark", axis="Z")
    b.cylk((cx, cy, z + 0.07), r * 1.04, 0.1, 10, "Plate", axis="Z", caps=False)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        b.beamk((cx, cy, z + 0.05), (cx + math.cos(a) * r, cy + math.sin(a) * r, z + 0.05), 0.022, 0.012, 3, "Metal", False)
    b.cylk((cx, cy, z + 0.09), 0.07, 0.08, 5, "Metal", axis="Z")


def roof_ac_a(b):
    for sy in (-1, 1):
        b.abox(-0.95, 0.95, sy * 0.5 - 0.1, sy * 0.5 + 0.1, 0, 0.15, "Concrete", "-z -x +x")
    b.blockk((0, 0), 0.15, 0.98, (2.0, 1.4), (1.92, 1.32), "Plate")
    b.abox(-0.96, 0.96, -0.66, 0.66, 0.98, 1.0, "Plate", "-z")
    fan(b, -0.5, 0.0, 1.0)
    fan(b, 0.5, 0.0, 1.0)
    b.abox(-0.88, 0.88, 0.665, 0.69, 0.25, 0.82, "MetalDark", "-y -z")
    for i in range(7):
        z = 0.28 + i * 0.08
        b.yq(0.692, -0.88, 0.88, z, z + 0.03, 1, "Metal")
    b.abox(0.98, 1.04, -0.5, 0.1, 0.35, 0.8, "MetalDark", "-y -z")                # service panel
    b.beamk((1.0, -0.3, 0.3), (1.35, -0.3, 0.3), 0.04, 0.04, 5, "Metal", False)
    b.beamk((1.35, -0.3, 0.3), (1.35, -0.3, 0.02), 0.04, 0.04, 5, "Metal", False)
    b.beamk((1.0, -0.15, 0.3), (1.5, -0.15, 0.3), 0.025, 0.025, 5, "Accent", False)
    b.beamk((1.5, -0.15, 0.3), (1.5, -0.15, 0.02), 0.025, 0.025, 5, "Accent", False)


def roof_ac_b(b):
    b.abox(-1.2, 1.2, -0.5, 0.5, 0.0, 0.12, "Concrete", "-z")
    b.blockk((0, 0), 0.12, 1.3, (2.7, 1.4), (2.6, 1.3), "Plate")
    b.abox(-1.3, 1.3, -0.65, 0.65, 1.3, 1.36, "Metal", "-z")
    # front intake with louvres
    b.abox(-1.0, 0.2, 0.7, 0.75, 0.25, 1.1, "MetalDark", "-y")
    for i in range(7):
        z = 0.33 + i * 0.11
        b.abox(-0.95, 0.15, 0.74, 0.79, z, z + 0.04, "Metal", "-y -z")
    b.abox(0.4, 1.1, 0.7, 0.74, 0.3, 1.0, "Metal", "-y")                          # access door
    b.abox(0.98, 1.02, 0.74, 0.8, 0.6, 0.72, "MetalDark", "-y")
    # exhaust stack with rain cap
    b.cylk((0.7, -0.1, 1.7), 0.2, 0.7, 10, "Metal", axis="Z", caps=False)
    b.cylk((0.7, -0.1, 2.12), 0.32, 0.05, 10, "MetalDark", axis="Z", r_top=0.06)
    # duct run up and over
    b.abox(-1.0, -0.55, -0.25, 0.25, 1.36, 2.3, "Metal", "-z")
    b.abox(-1.0, -0.2, -0.25, 0.25, 2.3, 2.7, "Metal", "-z")
    b.abox(-0.9, -0.65, -0.3, 0.3, 1.9, 1.95, "MetalDark", "")                    # duct band
    b.beamk((1.25, 0.3, 0.9), (1.8, 0.3, 0.9), 0.05, 0.05, 6, "Metal", True)
    b.beamk((1.8, 0.3, 0.9), (1.8, 0.3, 0.0), 0.05, 0.05, 6, "Metal", True)


def roof_tank(b):
    # steel tower
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.beamk((sx * 1.15, sy * 1.15, 0.0), (sx * 0.95, sy * 0.95, 2.0), 0.07, 0.06, 4, "MetalDark", False)
    for z in (0.7, 1.4):
        for (a, c) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
            s = 1.0 - (z / 2.0) * 0.17
            b.beamk((a[0] * 1.15 * s, a[1] * 1.15 * s, z), (c[0] * 1.15 * s, c[1] * 1.15 * s, z), 0.035, 0.035, 4, "MetalDark", False)
    b.beamk((-1.1, -1.1, 0.1), (0.95, -0.95, 1.9), 0.02, 0.02, 4, "Metal", False)
    b.beamk((1.1, -1.1, 0.1), (-0.95, -0.95, 1.9), 0.02, 0.02, 4, "Metal", False)
    b.abox(-1.15, 1.15, -1.15, 1.15, 2.0, 2.1, "MetalDark", "")
    # tank
    b.cylk((0, 0, 3.2), 1.2, 2.2, 12, "Wood", axis="Z")
    for z in (2.4, 3.2, 4.0):
        b.cylk((0, 0, z), 1.235, 0.07, 12, "MetalDark", axis="Z", caps=False)
    b.cylk((0, 0, 4.75), 1.3, 0.9, 12, "Roof", axis="Z", r_top=0.06, caps=False)
    b.cylk((0, 0, 5.25), 0.1, 0.1, 6, "Metal", axis="Z")
    # pipe + ladder on the front
    b.cylk((0.5, 0.0, 1.0), 0.06, 2.0, 6, "Metal", axis="Z", caps=False)
    b.beamk((0.5, 0.0, 2.0), (0.5, 0.95, 2.0), 0.06, 0.06, 6, "Metal", False)
    for sx in (-0.2, 0.2):
        b.beamk((sx - 0.4, 1.2, 0.0), (sx - 0.4, 1.2, 4.1), 0.025, 0.025, 4, "Metal", False)
    for k in range(9):
        z = 0.4 + k * 0.42
        b.beamk((-0.6, 1.2, z), (-0.2, 1.2, z), 0.018, 0.018, 4, "Metal", False)


def roof_antenna_a(b):
    def rr(z):
        return 0.6 - 0.05 * z
    ang = [math.radians(90 + 120 * k) for k in range(3)]
    def P(k, z):
        return (math.cos(ang[k]) * rr(z), math.sin(ang[k]) * rr(z), z)
    levels = [0, 2, 4, 6, 8]
    for k in range(3):
        for i in range(len(levels) - 1):
            b.beamk(P(k, levels[i]), P(k, levels[i + 1]), 0.04, 0.035, 3, "Metal", False)
    for z in levels[1:]:
        for k in range(3):
            b.beamk(P(k, z), P((k + 1) % 3, z), 0.025, 0.025, 3, "Metal", False)
    for i in range(len(levels) - 1):
        for k in range(3):
            b.beamk(P(k, levels[i]), P((k + 1) % 3, levels[i + 1]), 0.02, 0.02, 3, "Metal", False)
    b.abox(-0.7, 0.7, -0.7, 0.7, 0.0, 0.12, "Concrete", "-z")
    b.cylk((0, 0, 8.4), 0.04, 0.9, 6, "Metal", axis="Z")
    b.spherek((0, 0, 8.9), 0.11, 6, 3, "LightRed")
    # cross arm + panel antennas
    b.beamk((-0.6, 0, 7.2), (0.6, 0, 7.2), 0.03, 0.03, 4, "Metal", True)
    for x in (-0.55, 0.55):
        b.abox(x - 0.07, x + 0.07, 0.04, 0.12, 6.6, 7.6, "Plate", "-y")
    b.abox(-0.2, 0.2, 0.3, 0.38, 5.5, 5.9, "MetalDark", "-y")


def roof_antenna_b(b):
    b.abox(-0.4, 0.4, -0.4, 0.4, 0.0, 0.14, "Concrete", "-z")
    b.cylk((0, 0, 2.6), 0.07, 5.0, 8, "Metal", axis="Z", caps=False)
    b.cylk((0, 0, 0.35), 0.16, 0.45, 8, "MetalDark", axis="Z", caps=False)
    for k in range(3):
        a = math.radians(90 + 120 * k)
        b.beamk((0, 0, 4.2), (math.cos(a) * 2.2, math.sin(a) * 2.2, 0.05), 0.01, 0.01, 3, "Metal", False)
        b.abox(math.cos(a) * 2.2 - 0.08, math.cos(a) * 2.2 + 0.08, math.sin(a) * 2.2 - 0.08, math.sin(a) * 2.2 + 0.08, 0, 0.08, "Concrete", "-z")
    # dish
    e = math.radians(30.0)
    R = Matrix.Rotation(e - math.pi / 2, 3, "X")
    c = Vector((0, 0.55, 4.1))
    def dp(r, a, z):
        return tuple(c + R @ Vector((r * math.cos(a), r * math.sin(a), z)))
    rings = [0.0, 0.45, 0.85, 1.15, 1.35]
    f = 1.0
    seg = 10
    def zz(r):
        return r * r / (4 * f)
    for k in range(len(rings) - 1):
        for i in range(seg):
            a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
            r0, r1 = rings[k], rings[k + 1]
            nloc = R @ Vector((0, 0, 1))
            if k == 0:
                b.pq([dp(0, 0, 0), dp(r1, a0, zz(r1)), dp(r1, a1, zz(r1))], tuple(nloc), "Plate")
                b.pq([dp(0, 0, -0.05), dp(r1, a1, zz(r1) - 0.05), dp(r1, a0, zz(r1) - 0.05)], tuple(-nloc), "Plate")
            else:
                b.pq([dp(r0, a0, zz(r0)), dp(r0, a1, zz(r0)), dp(r1, a1, zz(r1)), dp(r1, a0, zz(r1))], tuple(nloc), "Plate")
                b.pq([dp(r0, a0, zz(r0) - 0.05), dp(r0, a1, zz(r0) - 0.05), dp(r1, a1, zz(r1) - 0.05), dp(r1, a0, zz(r1) - 0.05)], tuple(-nloc), "Plate")
    rim = rings[-1]
    for i in range(seg):
        a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        b.pq([dp(rim, a0, zz(rim)), dp(rim, a1, zz(rim)), dp(rim, a1, zz(rim) - 0.05), dp(rim, a0, zz(rim) - 0.05)], tuple(R @ Vector((math.cos((a0 + a1) / 2), math.sin((a0 + a1) / 2), 0))), "Plate")
    feed = dp(0, 0, f * 0.98)
    for k in range(3):
        a = 2 * math.pi * (k + 0.25) / 3
        b.beamk(dp(rim * 0.98, a, zz(rim)), feed, 0.018, 0.012, 3, "Metal", False)
    b.beamk(dp(0, 0, 0), feed, 0.02, 0.02, 4, "Metal", False)
    b.cylk(feed, 0.045, 0.14, 6, "MetalDark", axis="Z")
    b.beamk((0, 0.07, 3.9), tuple(c + R @ Vector((0, 0, -0.05))), 0.04, 0.04, 4, "Metal", True)
    b.beamk((0, 0.07, 3.3), tuple(c + R @ Vector((0.0, -0.6, -0.05))), 0.03, 0.03, 4, "Metal", True)
    b.spherek((0, 0, 5.15), 0.08, 6, 3, "LightRed")


def roof_stairs_box(b):
    W, D, H = 3.2, 2.6, 2.6
    door = (-0.5, 0.5, 0.0, 2.05)
    b.abox(-W / 2, W / 2, -D / 2, D / 2, 0, 0.12, "Concrete", "-z")
    b.wall_y(D / 2, -W / 2, W / 2, 0.12, H, [door], "WallA")
    b.reveal_y(door, D / 2, D / 2 - 0.15, "WallD", "lrt")
    b.yq(D / 2 - 0.15, door[0], door[1], door[2], door[3], 1, "WallC")
    b.yq(D / 2 - 0.145, -0.38, 0.38, 1.35, 1.8, 1, "Window")
    b.abox(0.3, 0.34, D / 2 - 0.15, D / 2 - 0.08, 0.9, 1.1, "Metal", "-y")
    b.abox(-0.6, 0.6, D / 2, D / 2 + 0.7, 0.0, 0.1, "Concrete", "-y -z")
    b.abox(0.7, 1.0, D / 2, D / 2 + 0.1, 1.9, 2.1, "LampGlow", "-y")
    b.wall_y(-D / 2, -W / 2, W / 2, 0.12, H, [], "WallA", s=-1)
    b.wall_x(W / 2, -D / 2, D / 2, 0.12, H, [(-0.5, 0.5, 1.4, 2.0)], "WallA", s=1)
    b.reveal_x((-0.5, 0.5, 1.4, 2.0), W / 2, W / 2 - 0.08, "WallD")
    for k in range(5):
        z = 1.45 + k * 0.11
        b.xq(W / 2 - 0.075, -0.45, 0.45, z, z + 0.05, 1, "Trim")
    b.wall_x(-W / 2, -D / 2, D / 2, 0.12, H, [], "WallA", s=-1)
    # slab roof with overhang + edge, small hatch
    b.abox(-W / 2 - 0.2, W / 2 + 0.2, -D / 2 - 0.2, D / 2 + 0.25, H, H + 0.14, "WallD", "")
    b.abox(-W / 2 - 0.1, W / 2 + 0.1, -D / 2 - 0.1, D / 2 + 0.15, H + 0.14, H + 0.2, "Roof", "-z")
    b.abox(-0.5, 0.4, -0.3, 0.3, H + 0.2, H + 0.55, "Metal", "-z")
    b.cylk((-1.0, -0.6, H + 0.55), 0.14, 0.7, 8, "Metal", axis="Z", caps=False)
    b.cylk((-1.0, -0.6, H + 0.93), 0.24, 0.06, 8, "MetalDark", axis="Z", r_top=0.04)


def roof_vent_row(b):
    b.abox(-2.0, 2.0, -0.3, 0.3, 0, 0.1, "Concrete", "-z")
    b.beamk((-1.8, -0.2, 0.2), (1.8, -0.2, 0.2), 0.08, 0.08, 6, "Metal", True)
    for x in (-1.5, -0.5):
        b.cylk((x, 0.05, 0.4), 0.17, 0.6, 6, "Metal", axis="Z", caps=False)
        b.cylk((x, 0.05, 0.75), 0.2, 0.1, 6, "MetalDark", axis="Z")
        b.spherek((x, 0.05, 0.9), 0.3, 6, 3, "Metal", scale=(1, 1, 0.8))
        b.beamk((x + 0.29, 0.05, 0.9), (x - 0.29, 0.05, 0.9), 0.012, 0.012, 3, "MetalDark", False)
    for x in (0.5, 1.5):
        b.cylk((x, 0.05, 0.5), 0.12, 0.8, 6, "Metal", axis="Z", caps=False)
        b.cylk((x, 0.05, 1.0), 0.32, 0.18, 6, "Metal", axis="Z", r_top=0.1, caps=True)
    b.abox(-0.2, 0.2, 0.15, 0.55, 0.1, 0.45, "Plate", "-z")
    b.beamk((-0.05, 0.35, 0.45), (-0.05, 0.35, 0.75), 0.03, 0.03, 4, "Metal", False)


def roof_solar_panels(b):
    tilt = math.radians(25)
    pw, pl, th = 1.55, 1.0, 0.05
    for row in range(2):
        y0 = -1.9 + row * 2.3
        for col in range(3):
            xc = -1.7 + col * 1.7
            # panel corners (tilted: higher at the back / -y side so it faces +Y)
            zlo, zhi = 0.55, 0.55 + pl * math.sin(tilt)
            yd = pl * math.cos(tilt)
            c = [(xc - pw / 2, y0 + yd, zlo), (xc + pw / 2, y0 + yd, zlo), (xc + pw / 2, y0, zhi), (xc - pw / 2, y0, zhi)]
            # top face (faces up/forward)
            b.pq(c, (0, math.sin(tilt), math.cos(tilt)), "SolarPanel")
            # frame sides + back
            lo = [(p[0], p[1], p[2] - th) for p in c]
            b.pq([c[3], c[2], lo[2], lo[3]], (0, -math.cos(tilt), math.sin(tilt)), "Metal")
            b.pq([c[0], c[1], lo[1], lo[0]], (0, math.cos(tilt), -math.sin(tilt)), "Metal")
            b.pq([c[0], c[3], lo[3], lo[0]], (-1, 0, 0), "Metal")
            b.pq([c[1], c[2], lo[2], lo[1]], (1, 0, 0), "Metal")
            b.pq([lo[0], lo[1], lo[2], lo[3]], (0, -math.sin(tilt), -math.cos(tilt)), "MetalDark")
            # cell grid lines (thin dark quads just above the glass)
            nrm = Vector((0, math.sin(tilt), math.cos(tilt))) * 0.003
            def pt(u, v):
                base = Vector(c[0]) + (Vector(c[1]) - Vector(c[0])) * u + (Vector(c[3]) - Vector(c[0])) * v
                return tuple(base + nrm)
            for k in (1, 2, 3):
                v = k / 4.0
                b.pq([pt(0, v), pt(1, v), pt(1, v + 0.018), pt(0, v + 0.018)], (0, math.sin(tilt), math.cos(tilt)), "Trim")
            for k in (1, 2, 3, 4, 5):
                u = k / 6.0
                b.pq([pt(u, 0), pt(u + 0.012, 0), pt(u + 0.012, 1), pt(u, 1)], (0, math.sin(tilt), math.cos(tilt)), "Trim")
        # supports per row
        for xs_ in (-2.3, -0.6, 1.1, 2.4):
            b.beamk((xs_, y0 + yd, 0.0), (xs_, y0 + yd, zlo - th), 0.03, 0.03, 4, "Metal", False)
            b.beamk((xs_, y0, 0.0), (xs_, y0, zhi - th), 0.03, 0.03, 4, "Metal", False)


def roof_helipad_pad(b):
    s = 6.0
    b.abox(-s, s, -s, s, 0.0, 0.3, "Concrete", "-z +z")
    # concrete border ring top (4 quads) + dark pad
    inner = 5.4
    b.zq(0.3, -s, s, inner, s, 1, "Concrete")
    b.zq(0.3, -s, s, -s, -inner, 1, "Concrete")
    b.zq(0.3, -s, -inner, -inner, inner, 1, "Concrete")
    b.zq(0.3, inner, s, -inner, inner, 1, "Concrete")
    b.zq(0.3, -inner, inner, -inner, inner, 1, "Asphalt")
    # painted ring (24 segments) + H
    n = 20
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        r0, r1 = 4.5, 4.95
        b.pq([(r0 * math.cos(a0), r0 * math.sin(a0), 0.303), (r1 * math.cos(a0), r1 * math.sin(a0), 0.303), (r1 * math.cos(a1), r1 * math.sin(a1), 0.303), (r0 * math.cos(a1), r0 * math.sin(a1), 0.303)], (0, 0, 1), "Accent")
    for (x0, x1, y0, y1) in ((-1.5, -0.95, -2.2, 2.2), (0.95, 1.5, -2.2, 2.2), (-0.95, 0.95, -0.28, 0.28)):
        b.zq(0.304, x0, x1, y0, y1, 1, "Plate")
    # perimeter lights (glow at night) + corner posts
    pos = []
    for t in (-4.0, 0.0, 4.0):
        pos += [(t, s - 0.25), (t, -s + 0.25), (s - 0.25, t), (-s + 0.25, t)]
    for p in sorted(set(pos)):
        b.abox(p[0] - 0.14, p[0] + 0.14, p[1] - 0.14, p[1] + 0.14, 0.3, 0.4, "NeonCyan", "-z")
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.cylk((sx * (s - 0.25), sy * (s - 0.25), 0.8), 0.05, 1.0, 6, "Metal", axis="Z", caps=False)
            b.spherek((sx * (s - 0.25), sy * (s - 0.25), 1.33), 0.12, 6, 3, "LightRed")


def roof_billboard_frame(b):
    Wd, Ht, z0 = 8.0, 3.6, 3.2
    for sx in (-1, 1):
        x = sx * 3.0
        b.abox(x - 0.4, x + 0.4, -0.4, 0.4, 0, 0.2, "Concrete", "-z")
        b.abox(x - 0.15, x + 0.15, -0.15, 0.15, 0.2, z0 + 0.4, "MetalDark", "-z")
    b.beamk((-3.0, 0.0, 0.3), (3.0, 0.0, z0), 0.04, 0.04, 4, "Metal", False)
    b.beamk((3.0, 0.0, 0.3), (-3.0, 0.0, z0), 0.04, 0.04, 4, "Metal", False)
    # board: back box + face + border
    b.abox(-Wd / 2, Wd / 2, -0.3, 0.0, z0, z0 + Ht, "MetalDark", "+y")
    b.yq(0.002, -Wd / 2 + 0.2, Wd / 2 - 0.2, z0 + 0.2, z0 + Ht - 0.2, 1, "BillboardFace")
    b.abox(-Wd / 2, Wd / 2, 0.0, 0.14, z0, z0 + 0.2, "Trim", "-y")
    b.abox(-Wd / 2, Wd / 2, 0.0, 0.14, z0 + Ht - 0.2, z0 + Ht, "Trim", "-y")
    b.abox(-Wd / 2, -Wd / 2 + 0.2, 0.0, 0.14, z0 + 0.2, z0 + Ht - 0.2, "Trim", "-y")
    b.abox(Wd / 2 - 0.2, Wd / 2, 0.0, 0.14, z0 + 0.2, z0 + Ht - 0.2, "Trim", "-y")
    # catwalk + rail
    b.abox(-Wd / 2, Wd / 2, 0.14, 0.85, z0 - 0.06, z0, "Metal", "")
    b.beamk((-Wd / 2, 0.85, z0 + 0.95), (Wd / 2, 0.85, z0 + 0.95), 0.025, 0.025, 4, "Metal", True)
    b.beamk((-Wd / 2, 0.85, z0 + 0.5), (Wd / 2, 0.85, z0 + 0.5), 0.02, 0.02, 4, "Metal", True)
    for x in (-3.9, -2.0, 0.0, 2.0, 3.9):
        b.beamk((x, 0.85, z0), (x, 0.85, z0 + 0.95), 0.025, 0.025, 4, "Metal", False)
    # flood lights along the top
    for x in (-3.0, -1.0, 1.0, 3.0):
        b.beamk((x, 0.0, z0 + Ht), (x, 0.9, z0 + Ht + 0.45), 0.02, 0.02, 4, "Metal", False)
        b.abox(x - 0.18, x + 0.18, 0.78, 1.0, z0 + Ht + 0.35, z0 + Ht + 0.55, "LampGlow", "")
    b.abox(-0.25, 0.25, 0.0, 0.22, z0 - 0.5, z0 - 0.06, "MetalDark", "-z")                     # power box


def roof_chimney(b):
    b.abox(-0.6, 0.6, -0.6, 0.6, 0.0, 0.3, "Concrete", "-z")
    b.blockk((0, 0), 0.3, 2.6, (0.95, 0.95), (0.85, 0.85), "WallB")
    for z in (1.0, 1.9):
        b.blockk((0, 0), z, z + 0.14, (0.99, 0.99), (0.99, 0.99), "WallD")
    b.blockk((0, 0), 2.6, 2.78, (1.1, 1.1), (1.25, 1.25), "WallD")
    b.abox(-0.5, 0.5, -0.5, 0.5, 2.78, 2.9, "Concrete", "-z")
    for x in (-0.22, 0.22):
        b.cylk((x, 0.0, 3.15), 0.14, 0.5, 8, "MetalDark", axis="Z", r_top=0.11)
    b.abox(-0.2, 0.2, 0.4, 0.5, 0.4, 0.7, "Metal", "-y")                                       # flashing
    b.beamk((0.45, 0.4, 0.5), (0.45, 0.4, 2.5), 0.02, 0.02, 4, "Metal", False)               # lightning rod


K = Kit("kit_roof", 3)
K.add("Roof_AC_A", roof_ac_a, width=3.0)
K.add("Roof_AC_B", roof_ac_b, width=4.0)
K.add("Roof_Tank", roof_tank, width=3.0, smooth=32)
K.add("Roof_Antenna_A", roof_antenna_a, width=2.0)
K.add("Roof_Antenna_B", roof_antenna_b, width=5.0, smooth=32)
K.add("Roof_Stairs_Box", roof_stairs_box, width=4.0)
K.add("Roof_Vent_Row", roof_vent_row, width=4.0, smooth=32)
K.add("Roof_Solar_Panels", roof_solar_panels, width=6.0)
K.add("Roof_Helipad_Pad", roof_helipad_pad, width=12.0)
K.add("Roof_Billboard_Frame", roof_billboard_frame, width=8.0)
K.add("Roof_Chimney", roof_chimney, width=2.0, smooth=32)
K.report()

if globals().get("EXPORT_KITS", False):
    K.export("buildings/kit_roof")
