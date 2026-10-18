"""lane3_plane_prop.py - high-wing 4-seat light plane (vehicles/plane_prop). Idempotent. Run via exec() after gta_lib.py."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane3_common.py", encoding="utf8").read(), globals())

P, P2, G, T = "Paint", "Paint2", "Glass", "Trim"
A = L3Asset("plane_prop", 2, "GTA_GODOT/Vehicles/Airplanes", paint="#f2f0ea", paint2="#e8795f")

# ------------------------------------------------------------------ fuselage loft
SEC = [  # y, hw, zb, zbelt, zs, zt, ht
    (2.58, 0.44, 0.82, 1.02, 1.30, 1.42, 0.30),     # cowl front
    (2.30, 0.56, 0.74, 1.02, 1.38, 1.52, 0.40),
    (1.35, 0.68, 0.66, 1.06, 1.45, 1.60, 0.48),     # firewall
    (0.65, 0.72, 0.64, 1.10, 1.88, 2.02, 0.62),     # windshield top
    (-0.80, 0.72, 0.64, 1.10, 1.88, 2.02, 0.62),
    (-1.60, 0.66, 0.68, 1.12, 1.76, 1.86, 0.52),    # rear window start
    (-2.40, 0.50, 0.78, 1.12, 1.52, 1.62, 0.34),
    (-3.40, 0.36, 0.92, 1.18, 1.48, 1.56, 0.26),
    (-4.40, 0.20, 1.10, 1.25, 1.46, 1.52, 0.14),
    (-5.05, 0.10, 1.22, 1.30, 1.42, 1.46, 0.06),
]
COWL = [P2, P2, P2, P, P, P, P, P, P2, P2]
WSHLD = [P2, P2, P2, G, G, G, G, G, P2, P2]
CABIN = [P2, P2, P2, G, P, P, P, G, P2, P2]
REARW = [P2, P2, P2, G, G, G, G, G, P2, P2]
TAIL = [P2, P2, P2, P, P, P, P, P, P2, P2]
SEGM = [COWL, COWL, WSHLD, CABIN, CABIN, REARW, TAIL, TAIL, TAIL]
b = MB("pp_body")
l3_loft(b, [l3_ring_cab(*s) for s in SEC], segmats=SEGM, cap0=T, cap1=P)


def sec_at(y):
    for a, c in zip(SEC, SEC[1:]):
        if a[0] >= y >= c[0]:
            u = (a[0] - y) / (a[0] - c[0])
            return [l3_lerp(a[i], c[i], u) for i in range(7)]
    return list(SEC[-1])


for yy in (0.10, -0.95):                 # window pillars
    s_ = sec_at(yy)
    for sd in (-1, 1):
        b.beam((sd * (s_[1] + 0.012), yy, s_[3]), (sd * (s_[1] * 0.96 + 0.012), yy, s_[4]), 0.03, 0.03, 4, P)
for sd in (-1, 1):                       # door seams, handles, cowl split line
    for yy in (0.62, -0.50):
        l3_seam_v(b, sd * 0.725, yy, 0.70, 1.10, T)
    l3_seam_h(b, sd * 0.725, -0.50, 0.62, 0.70, T)
    b.box((sd * 0.735, 0.50, 1.00), (0.03, 0.14, 0.035), "Chrome")
    l3_seam_v(b, sd * 0.60, 1.95, 0.80, 1.40, T, 0.016, 0.012)
b.box((0, 2.585, 0.87), (0.30, 0.02, 0.07), "LightHead")                     # landing light below the spinner
b.box((0, 2.56, 1.12), (0.50, 0.02, 0.30), T)                                # dark intake behind the spinner
for sd in (-1, 1):
    b.box((sd * 0.27, 2.57, 1.00), (0.20, 0.02, 0.16), T)
b.beam((0.22, 2.00, 0.74), (0.22, 1.35, 0.70), 0.05, 0.05, 6, "MetalDark")   # exhaust pipe
b.beam((0.22, 1.35, 0.70), (0.22, 1.20, 0.66), 0.05, 0.04, 6, "MetalDark")

# ------------------------------------------------------------------ interior
b.box((0, -0.05, 0.77), (1.30, 2.9, 0.05), "Interior")                        # floor
b.block((0, 1.22), 1.02, 1.52, (1.30, 0.30), (1.24, 0.22), "Interior", top_shift=(0.0, 0.0))   # instrument panel
b.box((0, 1.07, 1.52), (1.20, 0.10, 0.05), T)                                  # glare shield
for x in (-0.35, 0.35):
    l3_seat(b, x, 0.20, 0.79, 0.50, 0.50, 0.62, 0.20, "Fabric", 0.10)
    l3_seat(b, x, -0.85, 0.79, 0.50, 0.50, 0.62, 0.20, "Fabric", 0.10)
    b.beam((x, 0.95, 0.90), (x, 0.80, 1.12), 0.02, 0.02, 4, "MetalDark")       # yoke column
    b.beam((x - 0.13, 0.78, 1.14), (x + 0.13, 0.78, 1.14), 0.018, 0.018, 4, T)
    b.beam((x - 0.13, 0.78, 1.14), (x - 0.13, 0.78, 1.04), 0.016, 0.016, 4, T)
    b.beam((x + 0.13, 0.78, 1.14), (x + 0.13, 0.78, 1.04), 0.016, 0.016, 4, T)

# ------------------------------------------------------------------ wings (high wing, straight trailing edge, hinge line at y = YH)
DIH = math.tan(math.radians(1.7))


def wst(x, c, t, y_te=-0.85):
    return dict(x=x, y=y_te + c, z=2.12 + x * DIH, c=c, t=t)


W = [wst(0.55, 1.70, 0.22), wst(3.05, 1.45, 0.17), wst(5.40, 1.05, 0.11)]
YH = -0.55
for sd in (-1, 1):
    l3_wing(b, W, YH, sd, cap_root=P, cap_tip=P2)
    l3_wedge(b, W, YH, 0.55, 3.0, sd, P, P)             # flaps (fixed part of the trailing edge)
    l3_wedge(b, W, YH, 5.2, 5.4, sd, P2, P2)            # tip filler
    # strut brace (fuselage -> wing)
    p0 = Vector((sd * 0.74, 0.12, 0.80))
    st_ = l3_st_at(W, 2.65)
    p1 = Vector((sd * 2.65, st_["y"] - 0.38 * st_["c"], st_["z"] - 0.075))
    dirv = (p1 - p0).normalized()
    nv = Vector((dirv.z, 0, -dirv.x)) * (1 if sd > 0 else -1)
    l3_bar(b, [p0, p1], (0, 1, 0), nv, [0.11, 0.09], [0.035, 0.035], P)
    # jury strut
    pm = p0.lerp(p1, 0.55)
    b.beam((pm.x, pm.y - 0.02, pm.z), (sd * 3.35, st_["y"] - 0.55 - 0.15, st_["z"] - 0.07 + 0.05), 0.016, 0.016, 4, P)
# nav lights + wing-tip details
b.box((-5.43, -0.30, 2.12 + 5.4 * DIH), (0.05, 0.16, 0.08), "LightRed")
b.box((5.43, -0.30, 2.12 + 5.4 * DIH), (0.05, 0.16, 0.08), "LightGreen")

# ------------------------------------------------------------------ tail: fin, tailplane
l3_fin(b, [dict(z=1.40, y=-3.80, w=0.16), dict(z=2.10, y=-4.30, w=0.11), dict(z=2.80, y=-4.80, w=0.06)], -4.95, P, P2, P)
TS = [dict(x=0.0, y=-4.10, z=1.34, c=0.85, t=0.07), dict(x=1.75, y=-4.45, z=1.34, c=0.50, t=0.05)]
YH2 = -4.69
for sd in (-1, 1):
    l3_wing(b, TS, YH2, sd, cap_root=P, cap_tip=P2)
b.box((0, -5.335, 2.58), (0.06, 0.04, 0.10), "LightTail")                      # tail light
b.box((0, -4.96, 2.84), (0.06, 0.20, 0.04), "LightRed")                      # beacon on the fin tip

# ------------------------------------------------------------------ landing gear (tricycle)
for sd in (-1, 1):
    b.beam((sd * 0.56, -0.30, 0.82), (sd * 1.00, -0.30, 0.34), 0.05, 0.04, 6, "MetalDark")     # spring-steel leg
    b.beam((sd * 0.93, -0.30, 0.34), (sd * 1.10, -0.30, 0.30), 0.03, 0.03, 4, "MetalDark")     # axle stub
    b.beam((sd * 0.62, -0.14, 0.86), (sd * 0.94, -0.28, 0.58), 0.022, 0.022, 4, "MetalDark")   # brake line / brace
b.beam((0, 1.50, 0.72), (0, 1.70, 0.40), 0.06, 0.05, 6, "MetalDark")                        # nose gear oleo
b.beam((0, 1.70, 0.40), (0, 1.72, 0.30), 0.04, 0.03, 6, "Chrome")
for sd in (-1, 1):
    b.beam((sd * 0.10, 1.72, 0.40), (sd * 0.10, 1.72, 0.26), 0.02, 0.02, 4, "MetalDark")     # fork
b.box((0, 1.72, 0.40), (0.24, 0.06, 0.05), "MetalDark")
A.mesh(b, "Body")

# ------------------------------------------------------------------ control surfaces (origin on the hinge line)
for sd, nm in ((-1, "Aileron_L"), (1, "Aileron_R")):
    ab = MB("pp_" + nm)
    l3_wedge(ab, W, YH, 3.1, 5.15, sd, P2, P2)
    A.part(ab, nm, l3_hinge_pt(W, YH, 4.12, sd))
eb = MB("pp_elev")
for sd in (-1, 1):
    l3_wedge(eb, TS, YH2, 0.0, 1.75, sd, P2, P2)
hz = l3_hinge_pt(TS, YH2, 0.9, 1)[2]
A.part(eb, "Elevator", (0.0, YH2, hz))
rb = MB("pp_rudder")
l3_rudder(rb, -4.95, -5.38, -5.30, 1.55, 2.80, 0.151, 0.06, P2)
A.part(rb, "Rudder", (0.0, -4.95, 1.55))

# ------------------------------------------------------------------ propeller (origin on the shaft axis, spins about Y)
pr = MB("pp_prop")
l3_revolve_y(pr, [(0.42, 0.0), (0.30, 0.10), (0.12, 0.17), (0.0, 0.18), (-0.04, 0.17), (-0.04, 0.0)], 10, P2)
l3_blades(pr, 2, 0.14, 0.95, 0.17, 0.10, 0.03, 0.0, "RotorBlade", "RotorTip", 0.15, z=0.0, a0_deg=90.0, plane="xz", twist_deg=22.0)
A.mesh(pr, "Prop", loc=(0, 2.62, 1.12))

# ------------------------------------------------------------------ wheels
for nm, x, y, r, w_, s in (("Wheel_RL", -1.04, -0.30, 0.30, 0.17, -1), ("Wheel_RR", 1.04, -0.30, 0.30, 0.17, 1), ("Wheel_F", 0.0, 1.72, 0.26, 0.14, 1)):
    wh = l3_wheel(A.prefix + nm, r, w_, s, A.coll, 12, loc=(x, y, r))
    parent_to(wh, A.root)
    A.objs[nm] = wh

# ------------------------------------------------------------------ anchors
A.node("SeatPilot", (-0.35, 0.20, 1.23))
A.node("SeatCopilot", (0.35, 0.20, 1.23))
A.node("SeatRearL", (-0.35, -0.85, 1.23))
A.node("SeatRearR", (0.35, -0.85, 1.23))
A.node("ExitL", (-1.70, 0.05, 0.0))
A.node("ExitR", (1.70, 0.05, 0.0))
A.node("NavLightL", (-5.43, -0.30, 2.12 + 5.4 * DIH))
A.node("NavLightR", (5.43, -0.30, 2.12 + 5.4 * DIH))
A.node("HeadlightF", (0.0, 2.60, 0.87))
A.node("TaillightR", (0.0, -5.35, 2.58))
A.node("Exhaust", (0.22, 1.18, 0.66))

A.mats()
bpy.context.view_layer.update()
l3_qa(A)

if globals().get("L3_EXPORT"):
    A.export()
    save_master()
