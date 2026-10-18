"""lane3_heli_civil.py - civilian bubble-canopy light helicopter (vehicles/heli_civil). Idempotent. Run via exec() after gta_lib.py."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane3_common.py", encoding="utf8").read(), globals())

P, P2, G, T = "Paint", "Paint2", "Glass", "Trim"
A = L3Asset("heli_civil", 0, "GTA_GODOT/Vehicles/Helicopters", paint="#f2f0ea", paint2="#2f9c95")
HUB_Z = 3.05          # main rotor hub height (RotorMain origin, on the mast axis x=0,y=0)

# ------------------------------------------------------------------ fuselage (one loft, material per edge per segment)
SEC = [  # y, hw, zb, zbelt, zs, zt, ht
    (3.40, 0.10, 0.95, 1.05, 1.20, 1.30, 0.06),
    (3.15, 0.52, 0.80, 1.00, 1.40, 1.62, 0.25),
    (2.65, 0.80, 0.70, 1.05, 1.75, 2.02, 0.42),
    (1.95, 0.92, 0.65, 1.10, 1.95, 2.15, 0.50),
    (1.00, 0.92, 0.65, 1.12, 1.98, 2.18, 0.55),
    (0.05, 0.90, 0.65, 1.14, 2.15, 2.40, 0.55),
    (-0.70, 0.84, 0.68, 1.18, 2.25, 2.50, 0.50),
    (-1.60, 0.62, 0.92, 1.28, 2.20, 2.44, 0.42),
    (-2.40, 0.47, 1.25, 1.55, 2.12, 2.36, 0.30),
    (-3.40, 0.33, 1.55, 1.78, 2.15, 2.30, 0.20),
    (-4.60, 0.23, 1.85, 2.00, 2.20, 2.32, 0.14),
    (-6.80, 0.11, 2.15, 2.25, 2.38, 2.46, 0.06),
]
NOSE = [P2, G, P2, G, G, G, G, G, P2, G]         # chin windows + glass bubble roof
CABIN = [P2, P2, P2, G, P, P, P, G, P2, P2]      # teal lower body, white roof, side windows
ENGINE = [P2, P2, P2, P, P, P, P, P, P2, P2]
BOOM = [P2, P2, P2, P, P, P, P, P, P2, P2]
SEGM = [NOSE, NOSE, NOSE, CABIN, CABIN, ENGINE, ENGINE, ENGINE, BOOM, BOOM, BOOM]
b = MB("hc_body")
l3_loft(b, [l3_ring_cab(*s) for s in SEC], segmats=SEGM, cap0=G, cap1=P)


def sec_at(y):
    for a, c in zip(SEC, SEC[1:]):
        if a[0] >= y >= c[0]:
            u = (a[0] - y) / (a[0] - c[0])
            return [l3_lerp(a[i], c[i], u) for i in range(7)]
    return list(SEC[-1])


def pillar(y, mat=P, r=0.03):
    """window pillar following the slanted upper side"""
    s_ = sec_at(y)
    hw, zbelt, zs = s_[1], s_[3], s_[4]
    for sd in (-1, 1):
        b.beam((sd * (hw + 0.012), y, zbelt), (sd * (hw * 0.96 + 0.012), y, zs), r, r, 4, mat)


for yy in (2.30, 0.98, -0.10):
    pillar(yy)
# door seams (lower body) + handles
for sd in (-1, 1):
    x = sd * 0.925
    for yy in (0.98, -0.10):
        l3_seam_v(b, x, yy, 0.74, 1.12, T)
    l3_seam_h(b, x, -0.10, 2.30, 0.745, T)
    b.box((sd * 0.935, 1.20, 1.00), (0.03, 0.16, 0.035), "Chrome")
    b.box((sd * 0.935, 0.10, 1.00), (0.03, 0.14, 0.035), "Chrome")
# belly skid plates / nose camera-less chin
b.box((0, 2.90, 0.76), (0.62, 0.55, 0.05), T)

# ------------------------------------------------------------------ interior
b.box((0, 0.95, 0.80), (1.62, 3.5, 0.06), "Interior")                  # floor
b.block((0, 2.55), 1.05, 1.52, (1.30, 0.34), (1.24, 0.28), "Interior", top_shift=(0.0, -0.06))   # instrument panel
b.box((0, 2.43, 1.50), (0.70, 0.10, 0.12), T)                          # hood over dials
for x in (-0.42, 0.42):
    l3_seat(b, x, 1.55, 0.80, 0.46, 0.50, 0.62, 0.20, "Fabric", 0.10)
    l3_seat(b, x, 0.40, 0.80, 0.46, 0.50, 0.62, 0.20, "Fabric", 0.10)
for x in (-0.42, 0.42):                                               # cyclic sticks
    b.beam((x * 0.55, 2.05, 0.82), (x * 0.55, 2.15, 1.12), 0.018, 0.018, 4, "MetalDark")
    b.box((x * 0.55, 2.16, 1.16), (0.05, 0.05, 0.09), T)

# ------------------------------------------------------------------ mast, cowl details
b.cyl((0, 0, 2.70), 0.095, 0.64, 8, "MetalDark", axis="Z")
b.cyl((0, 0, 2.55), 0.20, 0.07, 8, "Metal", axis="Z")
b.cyl((0, 0, 2.95), 0.14, 0.12, 8, "Metal", axis="Z")
b.box((0, -0.55, 2.55), (0.55, 0.40, 0.07), T)                        # air intake grille
b.box((0, -1.20, 2.50), (0.40, 0.55, 0.05), T)                        # engine deck vent
b.beam((0.30, -1.50, 2.40), (0.30, -2.05, 2.52), 0.07, 0.06, 6, "MetalDark")   # exhaust stub
# ------------------------------------------------------------------ tail: fin, ventral fin, stabiliser, rotor mount
l3_fin(b, [dict(z=2.28, y=-5.80, w=0.14), dict(z=2.75, y=-6.25, w=0.11), dict(z=3.17, y=-6.62, w=0.06)], -7.10, P, P, P)
l3_fin(b, [dict(z=1.85, y=-6.30, w=0.05), dict(z=2.28, y=-5.80, w=0.12)], -6.90, P2, P2, P2)
l3_bar(b, [(-1.15, -5.98, 2.30), (0, -5.90, 2.30), (1.15, -5.98, 2.30)], (0, 1, 0), (0, 0, 1), [0.40, 0.58, 0.40], [0.04, 0.07, 0.04], P2, P2, P2)
for sd in (-1, 1):
    b.box((sd * 1.17, -5.98, 2.38), (0.04, 0.34, 0.22), P)           # stabiliser end plates
b.box((0.15, -6.80, 2.50), (0.14, 0.26, 0.26), "MetalDark")            # tail rotor gearbox
b.cyl((0.0, -6.80, 2.50), 0.05, 0.28, 6, "MetalDark", axis="X")
# lights
b.box((0, 3.43, 1.02), (0.20, 0.04, 0.09), "LightHead")                 # landing light on the nose
b.box((0, -7.13, 2.45), (0.10, 0.04, 0.12), "LightTail")                # tail light
b.box((0, -6.85, 3.20), (0.10, 0.14, 0.07), "LightRed")                 # anti-collision beacon
b.box((-0.93, 2.80, 1.10), (0.03, 0.12, 0.05), "LightRed")              # nav lights (left red / right green)
b.box((0.93, 2.80, 1.10), (0.03, 0.12, 0.05), "LightGreen")

# ------------------------------------------------------------------ skids
for sd in (-1, 1):
    x = sd * 1.18
    pts = [(-1.34, 0.20), (-1.20, 0.055), (2.50, 0.055), (2.85, 0.22), (3.10, 0.50)]
    for (y0, z0), (y1, z1) in zip(pts, pts[1:]):
        b.beam((x, y0, z0), (x, y1, z1), 0.055, 0.055, 6, "MetalDark", caps=True)
    for yy in (1.60, -0.50):
        b.beam((x, yy, 0.10), (sd * 0.70, yy, 0.69), 0.045, 0.045, 6, "MetalDark")
        b.cyl((x, yy, 0.12), 0.07, 0.10, 6, "Trim", axis="Z")              # clamp
body = A.mesh(b, "Body")

# ------------------------------------------------------------------ main rotor (origin on the mast axis at hub height, spins about Z)
r = MB("hc_rotor")
r.cyl((0, 0, 0), 0.17, 0.16, 8, "MetalDark", axis="Z")
r.box((0, 0, 0.02), (0.30, 0.95, 0.09), "MetalDark")
r.cyl((0, 0, -0.14), 0.12, 0.14, 8, "Metal", axis="Z")
l3_blades(r, 2, 0.45, 5.20, 0.38, 0.30, 0.05, 2.6, "RotorBlade", "RotorTip", 0.65, z=0.05, a0_deg=90.0, plane="xy")
A.mesh(r, "RotorMain", loc=(0, 0, HUB_Z))

# ------------------------------------------------------------------ tail rotor (spins about X)
t = MB("hc_tailrotor")
t.cyl((0.035, 0, 0), 0.06, 0.12, 6, "MetalDark", axis="X")
l3_blades(t, 2, 0.05, 0.80, 0.14, 0.11, 0.025, 0.0, "RotorBlade", "RotorTip", 0.18, z=0.06, a0_deg=90.0, plane="yz")
A.mesh(t, "RotorTail", loc=(0.22, -6.80, 2.50))

# ------------------------------------------------------------------ anchors
A.node("SeatPilot", (-0.42, 1.55, 1.25))
A.node("SeatCopilot", (0.42, 1.55, 1.25))
A.node("SeatRearL", (-0.42, 0.40, 1.25))
A.node("SeatRearR", (0.42, 0.40, 1.25))
A.node("ExitL", (-1.85, 1.20, 0.0))
A.node("ExitR", (1.85, 1.20, 0.0))
A.node("HeadlightF", (0, 3.44, 1.02))
A.node("TaillightR", (0, -7.15, 2.45))

A.mats()
bpy.context.view_layer.update()
l3_qa(A)

if globals().get("L3_EXPORT"):
    A.export()
    save_master()
