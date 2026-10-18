"""lane13 range_target + range_target_round - pop-up shooting range targets (props/range_target.glb, props/range_target_round.glb).
Nodes: Body (stand + hinge housing), Plate (hit mesh, ORIGIN = hinge bottom centre, plate stands up along +Z, thin along Y, front +Y),
empty Hinge (same point). Flip the plate by rotating `Plate` about its local X axis (-90 deg lies it down towards the shooter... see docs)."""

HINGE_Z = 0.30


def stand_geometry(name, wide=0.80):
    b = HB(name)
    b.abox(-wide / 2, wide / 2, -0.30, 0.30, 0.0, 0.05, "MetalDark")                         # base plate
    for sx in (-1, 1):                                                                       # corner feet bolts
        for sy in (-1, 1):
            b.cyl((sx * (wide / 2 - 0.07), sy * 0.22, 0.06), 0.035, 0.02, 6, "Chrome", caps="t")
    b.abox(-wide / 2 + 0.04, wide / 2 - 0.04, -0.22, 0.22, 0.05, 0.255, "PoleGrey")          # hinge housing / pneumatic box
    b.abox(-wide / 2 + 0.04, wide / 2 - 0.04, 0.22, 0.226, 0.07, 0.235, "Hazard", "-y")        # hazard stripe on the front
    b.yq(0.2265, -0.25, 0.25, 0.115, 0.19, 1, "TargetBlack")
    b.abox(-0.05, 0.05, 0.226, 0.25, 0.17, 0.215, "LightRed")                                 # status lamp
    for sx in (-1, 1):                                                                       # hinge brackets
        b.abox(sx * (wide / 2 - 0.10) - 0.025, sx * (wide / 2 - 0.10) + 0.025, -0.07, 0.07, 0.255, HINGE_Z + 0.05, "Metal")
    b.cyl((0, 0, HINGE_Z), 0.022, wide - 0.14, 6, "Chrome", axis="X")                         # hinge pin
    # air cylinder + rod
    b.cyl((0, -0.12, 0.28), 0.03, 0.12, 6, "MetalDark", axis="Y")
    return b


def silhouette_plate():
    """faceted human silhouette plate (x, z), bottom edge at z = 0, 1.55 m tall, 0.30 m shoulder half width."""
    half = [(0.16, 0.0), (0.18, 0.50), (0.23, 0.75), (0.28, 0.98), (0.30, 1.12), (0.22, 1.20), (0.09, 1.23), (0.08, 1.28), (0.12, 1.34),
            (0.12, 1.44), (0.08, 1.52), (0.0, 1.55)]
    pts = half + [(-x, z) for (x, z) in reversed(half[1:-1])] + [(-0.16, 0.0)]
    return pts


def build_range_target():
    A = A13("range_target", 40, "GTA_GODOT/StreetProps", spacing=6.0)
    A.mesh(stand_geometry("range_target_stand"), "Body", uv=None)
    b = HB("range_target_plate")
    T = 0.03
    pts = silhouette_plate()
    b.ey(pts, -T / 2, T / 2, "TargetBlack")
    yf = T / 2
    def zone(cx, cz, r, m, k, seg=8):
        b.pq([(cx + r * math.cos(math.radians(22.5) + 2 * math.pi * i / seg), yf + 0.002 + 0.0028 * k, cz + r * math.sin(math.radians(22.5) + 2 * math.pi * i / seg)) for i in range(seg)], (0, 1, 0), m)
    for k, (r, m) in enumerate(((0.235, "TargetRed"), (0.17, "TargetWhite"), (0.105, "TargetRed"), (0.04, "TargetWhite"))):
        zone(0.0, 0.88, r, m, k)
    for k, (r, m) in enumerate(((0.105, "TargetRed"), (0.052, "TargetWhite"))):
        zone(0.0, 1.39, r, m, k)
    # white outline strip down the legs for readability
    b.pq([(-0.12, yf + 0.002, 0.04), (0.12, yf + 0.002, 0.04), (0.12, yf + 0.002, 0.10), (-0.12, yf + 0.002, 0.10)], (0, 1, 0), "TargetWhite")
    A.mesh(b, "Plate", loc=(0, 0, HINGE_Z), uv=None)
    A.mark("Hinge", (0, 0, HINGE_Z), size=0.1)
    return A


def build_range_target_round():
    A = A13("range_target_round", 41, "GTA_GODOT/StreetProps", spacing=6.0)
    A.mesh(stand_geometry("range_target_round_stand", wide=0.80), "Body", uv=None)
    b = HB("range_target_round_plate")
    R, T = 0.45, 0.03
    seg = 16
    rim = [(R * math.cos(2 * math.pi * i / seg), R * math.sin(2 * math.pi * i / seg) + R) for i in range(seg)]
    b.ey(rim, -T / 2, T / 2, "TargetWhite")
    yf = T / 2
    layers = [(0.40, "TargetBlack"), (0.32, "TargetWhite"), (0.24, "TargetBlack"), (0.17, "TargetRed"), (0.10, "TargetWhite"), (0.045, "TargetRed")]
    for k, (r, m) in enumerate(layers):
        b.pq([(r * math.cos(2 * math.pi * i / seg), yf + 0.002 + 0.0028 * k, r * math.sin(2 * math.pi * i / seg) + R) for i in range(seg)], (0, 1, 0), m)
    A.mesh(b, "Plate", loc=(0, 0, HINGE_Z), uv=None)
    A.mark("Hinge", (0, 0, HINGE_Z), size=0.1)
    return A


A1 = build_range_target()
A1.report(400)
A2 = build_range_target_round()
A2.report(400)
