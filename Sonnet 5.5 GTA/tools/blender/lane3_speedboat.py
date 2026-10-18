"""lane3_speedboat.py - faceted V-hull speedboat with chine, raked windshield, 2 benches, outboard (vehicles/speedboat). Idempotent."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane3_common.py", encoding="utf8").read(), globals())

P, P2, T = "Paint", "Paint2", "Trim"
A = L3Asset("speedboat", 1, "GTA_GODOT/Vehicles/Boats", paint="#f2f0ea", paint2="#25324d")

# ------------------------------------------------------------------ hull: stations y, keel z, chine (x,z), sheer (x,z), floor z, rake k
ST = [
    (-2.62, -0.30, 0.84, -0.05, 1.10, 0.70, 0.56, 0.0),   # transom, rear deck
    (-2.28, -0.30, 0.90, -0.04, 1.14, 0.70, 0.56, 0.0),   # end of rear deck
    (-2.24, -0.30, 0.90, -0.04, 1.14, 0.70, 0.12, 0.0),   # cockpit starts (step down)
    (-1.20, -0.30, 0.98, -0.02, 1.20, 0.67, 0.12, 0.0),   # widest
    (0.40, -0.30, 1.00, 0.00, 1.18, 0.65, 0.12, 0.0),
    (0.84, -0.29, 0.99, 0.02, 1.16, 0.65, 0.12, 0.0),     # dash front wall
    (0.88, -0.29, 0.98, 0.03, 1.15, 0.67, 0.60, 0.0),     # step up to the foredeck
    (1.60, -0.25, 0.93, 0.08, 1.07, 0.78, 0.72, 0.06),
    (2.10, -0.14, 0.78, 0.18, 0.90, 0.92, 0.86, 0.14),
    (2.42, 0.05, 0.54, 0.34, 0.62, 1.07, 1.01, 0.24),
    (2.62, 0.28, 0.30, 0.50, 0.34, 1.18, 1.12, 0.34),
    (2.73, 0.52, 0.12, 0.66, 0.14, 1.26, 1.20, 0.40),     # bow (stem raked forward)
]


def hull_ring(y, zk, xc, zc, xs, zs, zf, k):
    xm, zm = l3_lerp(xc, xs, 0.42), l3_lerp(zc, zs, 0.42)
    xf = max(xs - 0.15, 0.04)
    xr = max(xs - 0.07, 0.03)
    R = [(xc, zc), (xm, zm), (xs, zs), (xr, zs + 0.03), (xf, zf)]
    pts = [(0.0, zk)] + R + [(-x, z) for (x, z) in reversed(R)]
    return [(x, y + k * (z - zk), z) for x, z in pts]


def _interp(lst, y):
    for a_, c_ in zip(lst, lst[1:]):
        if a_[0] <= y <= c_[0]:
            u = (y - a_[0]) / (c_[0] - a_[0])
            return [l3_lerp(a_[i], c_[i], u) for i in range(1, len(a_))]
    return list(lst[-1][1:])


DECK = [(s[0] + s[7] * (s[6] - s[1]), s[6]) for s in ST[6:]]                # (y', deck z)
SHEER = [(s[0] + s[7] * (s[5] + 0.03 - s[1]), s[4], s[5]) for s in ST[6:]]   # (y', sheer x, sheer z)


def deck_z(y):
    return _interp(DECK, y)[0]


def sheer_x(y):
    return _interp(SHEER, y)[0]


# edges: 0 keel>chineR 1 chineR>midR 2 midR>sheerR 3 sheerR>railR 4 railR>floorR 5 floor 6 floorL>railL 7 railL>sheerL 8 sheerL>midL 9 midL>chineL 10 chineL>keel
def mset(floor, wall="Paint"):
    return [P2, P2, P, T, wall, floor, wall, T, P, P2, P2]


SEG = [mset("Teak"), mset(P), mset("Teak"), mset("Teak"), mset("Teak"), mset(P), mset(P), mset(P), mset(P), mset(P), mset(P)]
b = MB("sb_body")
l3_loft(b, [hull_ring(*s) for s in ST], segmats=SEG, cap0=P, cap1=P)

# ------------------------------------------------------------------ cockpit: console, dash, seats
b.block((0, 0.60), 0.12, 0.97, (1.92, 0.54), (1.80, 0.30), P, top_shift=(0.0, 0.10))        # helm console
b.box((0, 0.74, 0.985), (1.55, 0.26, 0.035), T)                                              # dash pad
b.box((-0.40, 0.52, 1.03), (0.42, 0.04, 0.12), "Interior")                                   # instrument cluster
for k, x in enumerate((-0.52, -0.40, -0.28)):
    b.cyl((x, 0.495, 1.03), 0.035, 0.015, 6, "LampGlow" if k == 1 else "Chrome", axis="Y")
b.box((0.40, 0.72, 1.01), (0.50, 0.12, 0.03), "Interior")                                    # passenger grab panel
l3_steering(b, (-0.40, 0.50, 1.10), 48, 0.17, T, "Interior")
b.beam((0.18, 0.40, 0.98), (0.18, 0.36, 1.10), 0.02, 0.02, 4, "Chrome")                    # throttle lever
for x in (-0.40, 0.40):                                                                      # front bucket seats
    l3_seat(b, x, -0.05, 0.12, 0.62, 0.52, 0.66, 0.26, "SeatBlue", 0.10, True, "SeatBlue")
l3_seat(b, 0.0, -1.88, 0.12, 1.96, 0.56, 0.62, 0.26, "SeatBlue", 0.06, False, "SeatBlue")    # rear bench
b.box((0, -1.35, 0.16), (1.96, 0.06, 0.12), P)                                               # bench kick
for x in (-0.55, 0.55):
    b.box((x, 0.60, 0.30), (0.04, 0.04, 0.35), "Chrome")                                    # grab handles
# rear deck: engine hatch line + non-slip pads
b.box((0, -2.46, 0.5675), (1.50, 0.50, 0.015), "Concrete")
l3_seam_h(b, 0.0, -2.62, -2.25, 0.57, T, 0.02, 0.02)

# ------------------------------------------------------------------ foredeck gear: hatch, cleats, rail, lights
b.box((0, 1.62, deck_z(1.62) + 0.008), (0.74, 0.64, 0.016), T)
b.box((0, 1.62, deck_z(1.62) + 0.026), (0.62, 0.52, 0.022), "Concrete")        # foredeck hatch
for sd in (-1, 1):
    zc_ = deck_z(1.78)
    b.box((sd * (sheer_x(1.78) - 0.16), 1.78, zc_ + 0.03), (0.05, 0.16, 0.04), "Chrome")      # side cleats
    b.box((sd * (sheer_x(1.78) - 0.16), 1.78, zc_ + 0.005), (0.03, 0.05, 0.05), "Chrome")
zc_ = deck_z(2.45)
b.box((0, 2.45, zc_ + 0.03), (0.16, 0.05, 0.04), "Chrome")                  # bow cleat
b.box((0, 2.45, zc_ + 0.005), (0.04, 0.04, 0.05), "Chrome")
for sd in (-1, 1):
    b.box((sd * 1.0, -2.45, 0.60), (0.14, 0.05, 0.04), "Chrome")             # stern cleats
# bow rail (stainless): posts + top tube following the sheer
RY = [1.55, 2.05, 2.40, 2.68]
RP = [(sheer_x(y) - 0.10, y, deck_z(y)) for y in RY]
H = 0.27
for (x, y, z) in RP:
    for sd in (-1, 1):
        b.beam((sd * x, y, z), (sd * x, y, z + H), 0.014, 0.014, 4, "Chrome")
for (a_, c_) in zip(RP, RP[1:]):
    for sd in (-1, 1):
        b.beam((sd * a_[0], a_[1], a_[2] + H), (sd * c_[0], c_[1], c_[2] + H), 0.016, 0.016, 5, "Chrome")
last = RP[-1]
b.beam((-last[0], last[1], last[2] + H), (last[0], last[1], last[2] + H), 0.016, 0.016, 5, "Chrome")
# headlight pod + nav lights
zh = deck_z(2.12)
b.box((0, 2.12, zh + 0.07), (0.24, 0.16, 0.14), T)
b.box((0, 2.205, zh + 0.07), (0.17, 0.03, 0.08), "LightHead")
zn = deck_z(2.30) + 0.03
b.box((-sheer_x(2.30) + 0.12, 2.30, zn + 0.03), (0.06, 0.09, 0.06), "LightRed")
b.box((sheer_x(2.30) - 0.12, 2.30, zn + 0.03), (0.06, 0.09, 0.06), "LightGreen")
b.box((0, -2.63, 0.66), (0.14, 0.03, 0.06), "LightTail")                  # stern light

# ------------------------------------------------------------------ outboard motor (Prop is a separate node)
b.block((0, -2.88), 0.62, 1.13, (0.56, 0.60), (0.42, 0.46), P2)           # cowling
b.box((0, -2.88, 1.14), (0.30, 0.34, 0.03), T)
for sd in (-1, 1):
    b.box((sd * 0.285, -2.88, 0.88), (0.02, 0.26, 0.10), T)               # intake slots
b.block((0, -2.86), -0.10, 0.63, (0.18, 0.34), (0.30, 0.50), "MetalDark")   # drive shaft housing
b.box((0, -2.70, 0.48), (0.40, 0.08, 0.30), "MetalDark")                 # transom clamp
b.box((0, -2.66, 0.32), (0.50, 0.04, 0.05), "Metal")
l3_revolve_y(b, [(-2.74, 0.0), (-2.80, 0.09), (-2.94, 0.125), (-3.10, 0.075), (-3.17, 0.0)], 8, "Metal", c=(0, 0, -0.22))   # gearcase torpedo
b.block((0, -2.96), -0.50, -0.20, (0.035, 0.10), (0.035, 0.26), "MetalDark")                                      # skeg
A.mesh(b, "Body")

# ------------------------------------------------------------------ windshield node (origin = base centre)
W0 = (0.0, 0.92, 0.97)
w = MB("sb_windshield")
yb, zb, yt, zt, hwb, hwt = 0.92, 0.97, 0.56, 1.37, 0.95, 0.84
nrm = Vector((0, 0.42, 0.37)).normalized()
nrm = Vector((0, zt - zb, -(yt - yb))).normalized()        # perpendicular to the pane in the YZ plane
l3_bar(w, [(0, yb, zb + 0.02), (0, yt, zt - 0.02)], (1, 0, 0), nrm, [hwb * 2 - 0.08, hwt * 2 - 0.08], [0.016, 0.016], "Glass")
for sd in (-1, 1):
    w.beam((sd * hwb, yb, zb), (sd * hwt, yt, zt), 0.024, 0.022, 5, "Chrome")
w.beam((-hwt, yt, zt), (hwt, yt, zt), 0.022, 0.022, 5, "Chrome")
w.beam((-hwb, yb, zb), (hwb, yb, zb), 0.026, 0.026, 5, "Chrome")
w.beam((0, yb, zb), (0, yt, zt), 0.016, 0.016, 4, "Chrome")
A.part(w, "Windshield", W0)

# ------------------------------------------------------------------ propeller (spins about Y)
pr = MB("sb_prop")
l3_revolve_y(pr, [(0.03, 0.0), (0.0, 0.05), (-0.07, 0.045), (-0.12, 0.0)], 6, "Metal")
l3_blades(pr, 3, 0.03, 0.28, 0.11, 0.08, 0.022, 0.0, "Chrome", "Chrome", 0.08, z=0.0, a0_deg=90.0, plane="xz", twist_deg=26.0)
A.mesh(pr, "Prop", loc=(0, -3.18, -0.22))

# ------------------------------------------------------------------ anchors
A.node("SeatDriver", (-0.40, -0.05, 0.57))
A.node("SeatPassenger", (0.40, -0.05, 0.57))
A.node("SeatRearL", (-0.45, -1.85, 0.57))
A.node("SeatRearR", (0.45, -1.85, 0.57))
A.node("ExitL", (-1.40, 0.10, 0.75))
A.node("ExitR", (1.40, 0.10, 0.75))
A.node("HeadlightF", (0.0, 2.21, deck_z(2.12) + 0.07))
A.node("TaillightL", (-0.30, -2.63, 0.66))
A.node("TaillightR", (0.30, -2.63, 0.66))
A.node("Exhaust", (0.0, -3.20, -0.10))

A.mats()
bpy.context.view_layer.update()
l3_qa(A)

if globals().get("L3_EXPORT"):
    A.export()
    save_master()
