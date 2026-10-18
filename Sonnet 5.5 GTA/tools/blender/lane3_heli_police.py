"""lane3_heli_police.py - police patrol helicopter: enclosed cabin, sliding doors, searchlight, camera ball, light pods (vehicles/heli_police). Idempotent."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane3_common.py", encoding="utf8").read(), globals())

P, P2, G, T = "Paint", "Paint2", "Glass", "Trim"
A = L3Asset("heli_police", 3, "GTA_GODOT/Vehicles/Helicopters", paint="#f2f0ea", paint2="#25324d")
HUB_Z = 3.20          # main rotor hub height (RotorMain origin, on the mast axis x=0,y=0)

# ------------------------------------------------------------------ fuselage loft
SEC = [  # y, hw, zb, zbelt, zs, zt, ht
    (3.80, 0.30, 0.85, 1.05, 1.35, 1.50, 0.15),
    (3.50, 0.70, 0.76, 1.05, 1.60, 1.80, 0.35),
    (2.90, 0.98, 0.70, 1.10, 1.90, 2.15, 0.50),
    (2.10, 1.04, 0.68, 1.14, 2.10, 2.32, 0.60),
    (0.70, 1.04, 0.68, 1.14, 2.12, 2.36, 0.66),
    (-0.60, 1.02, 0.68, 1.16, 2.20, 2.50, 0.64),
    (-1.60, 0.90, 0.75, 1.25, 2.30, 2.58, 0.56),
    (-2.50, 0.66, 1.05, 1.50, 2.28, 2.52, 0.40),
    (-3.50, 0.45, 1.45, 1.70, 2.15, 2.38, 0.28),
    (-5.00, 0.28, 1.78, 1.95, 2.18, 2.32, 0.17),
    (-6.60, 0.18, 2.00, 2.10, 2.28, 2.36, 0.11),
    (-7.60, 0.12, 2.12, 2.20, 2.34, 2.40, 0.07),
]
NOSE = [P2, P2, P2, G, G, G, G, G, P2, P2]       # wrap-around windscreen
DOORF = [P2, P2, P2, G, P, P, P, G, P2, P2]      # front door windows
CABIN = [P2, P2, P2, P, P, P, P, P, P2, P2]      # white upper, navy lower
SLIDE = [P2, P2, P2, G, P, P, P, G, P2, P2]      # sliding-door glazing (door skin bands are overlaid below)
BOOM = [P2, P2, P2, P, P, P, P, P, P2, P2]
SEGM = [NOSE, NOSE, DOORF, SLIDE, SLIDE, CABIN, CABIN, BOOM, BOOM, BOOM, BOOM]
b = MB("hp_body")
l3_loft(b, [l3_ring_cab(*s, tum=1.0) for s in SEC], segmats=SEGM, cap0=P2, cap1=P)


def sec_at(y):
    for a, c in zip(SEC, SEC[1:]):
        if a[0] >= y >= c[0]:
            u = (a[0] - y) / (a[0] - c[0])
            return [l3_lerp(a[i], c[i], u) for i in range(7)]
    return list(SEC[-1])


def pillar(y, r=0.032):
    s_ = sec_at(y)
    for sd in (-1, 1):
        b.beam((sd * (s_[1] + 0.012), y, s_[3]), (sd * (s_[1] + 0.012), y, s_[4]), r, r, 4, P)


def flat_window(y0, y1, z0, z1, sd, fw=0.05):
    """flat window on the vertical cabin side wall: frame (Trim) + dark glass"""
    x = sd * (sec_at((y0 + y1) / 2)[1] + 0.004)
    b.box((x + sd * 0.006, (y0 + y1) / 2, (z0 + z1) / 2), (0.012, y0 - y1 - 2 * fw, z1 - z0 - 2 * fw), G)
    b.box((x + sd * 0.008, (y0 + y1) / 2, z1 - fw / 2), (0.016, y0 - y1, fw), T)
    b.box((x + sd * 0.008, (y0 + y1) / 2, z0 + fw / 2), (0.016, y0 - y1, fw), T)
    b.box((x + sd * 0.008, y0 - fw / 2, (z0 + z1) / 2), (0.016, fw, z1 - z0), T)
    b.box((x + sd * 0.008, y1 + fw / 2, (z0 + z1) / 2), (0.016, fw, z1 - z0), T)


pillar(2.10)
pillar(3.15)
for sd in (-1, 1):
    xw = sd * 1.054
    # sliding door: outline, window, handle, rails
    xs_ = sd * (1.04 + 0.012)
    b.box((xs_, 0.675, 1.26), (0.024, 2.50, 0.24), P)                  # door skin: lower band
    b.box((xs_, 0.675, 2.04), (0.024, 2.50, 0.12), P)                  # upper band
    for yy, wd in ((1.95, 0.10), (-0.50, 0.12)):
        b.box((xs_, yy, 1.62), (0.024, wd, 0.96), P)                   # door pillars
    for (ya, yb_) in ((1.90, -0.45),):
        l3_seam_h(b, sd * 1.058, yb_, ya, 1.385, T, 0.025, 0.012)       # window frame (bottom / top)
        l3_seam_h(b, sd * 1.058, yb_, ya, 1.98, T, 0.025, 0.012)
    for yy in (1.92, -0.40):
        l3_seam_v(b, xw, yy, 0.78, 1.14, T, 0.02, 0.014)
    l3_seam_h(b, xw, -0.40, 1.92, 0.78, T, 0.02, 0.014)
    b.box((sd * 1.07, 1.65, 1.05), (0.04, 0.22, 0.04), "Chrome")
    l3_seam_h(b, sd * 1.075, -0.40, 1.92, 2.17, "MetalDark", 0.05, 0.05)   # upper sliding rail
    l3_seam_h(b, sd * 1.075, -0.40, 1.92, 0.74, "MetalDark", 0.05, 0.05)   # lower sliding rail
    # front door seam + handle, nav light
    l3_seam_v(b, sd * 0.995, 2.98, 0.76, 1.12, T, 0.02, 0.014)
    b.box((sd * 1.06, 2.35, 1.05), (0.04, 0.20, 0.04), "Chrome")
    b.box((sd * (sec_at(3.2)[1] + 0.01), 3.2, 1.20), (0.04, 0.12, 0.06), "LightRed" if sd < 0 else "LightGreen")
# equipment: nose camera ball (FLIR) on a bracket under the nose
b.beam((0, 3.62, 0.84), (0, 3.62, 0.66), 0.07, 0.07, 6, T)
b.sphere((0, 3.62, 0.52), 0.21, 10, 6, "MetalDark")
b.cyl((0, 3.78, 0.54), 0.12, 0.10, 8, G, axis="Y")
b.cyl((0, 3.70, 0.42), 0.06, 0.12, 6, "Chrome", axis="Y")
# landing lights, belly details
for sd in (-1, 1):
    b.box((sd * 0.16, 3.815, 1.12), (0.16, 0.03, 0.08), "LightHead")
b.box((0, 1.0, 0.655), (1.4, 2.6, 0.04), "MetalDark")                        # belly skid plate
# searchlight mount pylon (Searchlight itself is a separate node)
b.box((0.55, 2.62, 0.70), (0.14, 0.14, 0.12), T)

# ------------------------------------------------------------------ interior
b.box((0, 0.90, 0.80), (1.90, 3.7, 0.06), "Interior")                        # floor
b.block((0, 3.05), 1.05, 1.60, (1.60, 0.40), (1.50, 0.30), "Interior", top_shift=(0.0, -0.08))   # instrument panel
b.box((0, 2.85, 1.62), (0.95, 0.10, 0.12), T)
b.box((0, 2.50, 1.12), (0.30, 0.60, 0.36), "Interior")                        # centre console
b.box((0, 2.30, 1.30), (0.26, 0.22, 0.02), "LightBlue")                       # console screen glow
b.box((0, -0.52, 1.30), (1.10, 0.08, 0.62), "Interior")                       # rear bulkhead / equipment rack
b.box((0.32, -0.46, 1.45), (0.46, 0.02, 0.28), "LightBlue")                   # operator display
for x in (-0.46, 0.46):
    l3_seat(b, x, 2.15, 0.83, 0.50, 0.52, 0.66, 0.20, "Fabric", 0.10)
for x in (-0.66, 0.0, 0.66):
    l3_seat(b, x, 0.55, 0.83, 0.52, 0.50, 0.62, 0.20, "Fabric", 0.10)
for x in (-0.46, 0.46):
    b.beam((x * 0.55, 2.62, 0.86), (x * 0.55, 2.72, 1.18), 0.018, 0.018, 4, "MetalDark")

# ------------------------------------------------------------------ mast, intakes, exhausts, antennas
b.cyl((0, 0, 2.78), 0.30, 0.62, 8, P2, axis="Z", r_top=0.13)                  # mast fairing
b.cyl((0, 0, 3.02), 0.12, 0.34, 8, "MetalDark", axis="Z")
b.cyl((0, 0, 2.62), 0.22, 0.06, 8, "Metal", axis="Z")
for sd in (-1, 1):
    b.box((sd * 0.52, -1.10, 2.64), (0.40, 0.55, 0.10), T)                   # engine air intakes
    b.box((sd * 0.52, -1.10, 2.575), (0.44, 0.60, 0.05), "MetalDark")
    b.beam((sd * 0.42, -1.95, 2.50), (sd * 0.42, -2.55, 2.60), 0.09, 0.075, 6, "MetalDark")   # exhaust stubs
b.beam((0.0, -1.5, 2.56), (0.0, -1.5, 2.86), 0.014, 0.014, 4, T)              # blade antennas
b.beam((0.0, 1.5, 0.64), (0.0, 1.5, 0.45), 0.014, 0.014, 4, T)
b.box((0, -0.8, 2.62), (0.30, 0.12, 0.04), "LightRed")                        # tail strobe on the engine deck

# ------------------------------------------------------------------ tail: fin, ventral fin, stabiliser
l3_fin(b, [dict(z=2.30, y=-6.50, w=0.16), dict(z=2.90, y=-7.10, w=0.12), dict(z=3.35, y=-7.45, w=0.07)], -8.25, P, P2, P)
l3_fin(b, [dict(z=1.78, y=-7.20, w=0.06), dict(z=2.30, y=-6.70, w=0.14)], -8.00, P2, P2, P2)
l3_bar(b, [(-1.30, -6.78, 2.36), (0, -6.68, 2.36), (1.30, -6.78, 2.36)], (0, 1, 0), (0, 0, 1), [0.46, 0.72, 0.46], [0.045, 0.08, 0.045], P2, P2, P2)
for sd in (-1, 1):
    b.box((sd * 1.33, -6.78, 2.46), (0.04, 0.42, 0.32), P)
b.box((0.16, -8.00, 2.56), (0.14, 0.28, 0.28), "MetalDark")                  # tail rotor gearbox
b.cyl((0.0, -8.00, 2.56), 0.05, 0.30, 6, "MetalDark", axis="X")
b.box((0, -8.27, 2.40), (0.10, 0.04, 0.14), "LightTail")
b.box((0, -7.45, 3.40), (0.10, 0.16, 0.07), "LightRed")                       # beacon

# ------------------------------------------------------------------ skids (wide, tall stance)
for sd in (-1, 1):
    x = sd * 1.30
    pts = [(-1.95, 0.22), (-1.80, 0.06), (2.95, 0.06), (3.30, 0.24), (3.55, 0.54)]
    for (y0, z0), (y1, z1) in zip(pts, pts[1:]):
        b.beam((x, y0, z0), (x, y1, z1), 0.06, 0.06, 6, "MetalDark")
    for yy in (1.75, -0.55):
        b.beam((x, yy, 0.10), (sd * 0.86, yy, 0.69), 0.05, 0.05, 6, "MetalDark")
        b.cyl((x, yy, 0.13), 0.08, 0.10, 6, T, axis="Z")
        b.cyl((sd * 0.86, yy, 0.67), 0.09, 0.07, 6, "Metal", axis="Z")
A.mesh(b, "Body")

# ------------------------------------------------------------------ main rotor (4 blades, origin on the mast axis at hub height, spins about Z)
r = MB("hp_rotor")
r.cyl((0, 0, 0), 0.26, 0.22, 8, "MetalDark", axis="Z")
r.box((0, 0, 0.02), (0.30, 1.30, 0.10), "MetalDark")
r.box((0, 0, 0.02), (1.30, 0.30, 0.10), "MetalDark")
r.cyl((0, 0, -0.18), 0.17, 0.16, 8, "Metal", axis="Z")
l3_blades(r, 4, 0.55, 5.60, 0.40, 0.28, 0.05, 2.4, "RotorBlade", "RotorTip", 0.60, z=0.05, a0_deg=45.0, plane="xy")
A.mesh(r, "RotorMain", loc=(0, 0, HUB_Z))

# ------------------------------------------------------------------ tail rotor (spins about X)
t = MB("hp_tailrotor")
t.cyl((0.04, 0, 0), 0.07, 0.14, 6, "MetalDark", axis="X")
l3_blades(t, 4, 0.06, 0.82, 0.15, 0.11, 0.025, 0.0, "RotorBlade", "RotorTip", 0.18, z=0.07, a0_deg=45.0, plane="yz")
A.mesh(t, "RotorTail", loc=(0.24, -8.00, 2.56))

# ------------------------------------------------------------------ belly searchlight (pivot = mount, lens faces +Y)
s_ = MB("hp_search")
s_.cyl((0, 0.0, -0.20), 0.17, 0.34, 10, T, axis="Y")
s_.cyl((0, 0.18, -0.20), 0.145, 0.04, 10, "LightHead", axis="Y")
s_.cyl((0, 0.0, -0.02), 0.05, 0.10, 6, "MetalDark", axis="Z")
A.mesh(s_, "Searchlight", loc=(0.55, 2.62, 0.64))

# ------------------------------------------------------------------ light pods (blue left / red right), flash by material name
for sd, nm, lens in ((-1, "SirenBar_L", "LightBlue"), (1, "SirenBar_R", "LightRed")):
    pm = MB("hp_" + nm)
    pm.block((0, 0), -0.08, 0.02, (0.22, 0.54), (0.20, 0.50), T)
    pm.block((0, 0), 0.02, 0.12, (0.20, 0.50), (0.14, 0.40), lens)
    pm.box((0, 0.27, 0.04), (0.14, 0.02, 0.07), lens)
    pm.box((0, -0.27, 0.04), (0.14, 0.02, 0.07), lens)
    A.mesh(pm, nm, loc=(sd * 0.50, 2.35, 2.36))

# ------------------------------------------------------------------ anchors
A.node("SeatPilot", (-0.46, 2.15, 1.28))
A.node("SeatCopilot", (0.46, 2.15, 1.28))
A.node("SeatRearL", (-0.66, 0.55, 1.28))
A.node("SeatRearR", (0.66, 0.55, 1.28))
A.node("SeatRearC", (0.0, 0.55, 1.28))
A.node("ExitL", (-2.05, 1.00, 0.0))
A.node("ExitR", (2.05, 1.00, 0.0))
A.node("HeadlightF", (0, 3.83, 1.12))
A.node("TaillightR", (0, -8.29, 2.40))

A.mats()
bpy.context.view_layer.update()
l3_qa(A)

if globals().get("L3_EXPORT"):
    A.export()
    save_master()
