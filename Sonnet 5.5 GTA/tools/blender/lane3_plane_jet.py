"""lane3_plane_jet.py - sleek two-seat jet: swept wings, twin rear engines, T-tail, bubble canopy (vehicles/plane_jet). Idempotent."""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\lane3_common.py", encoding="utf8").read(), globals())

P, P2, G, T = "Paint", "Paint2", "Glass", "Trim"
A = L3Asset("plane_jet", 4, "GTA_GODOT/Vehicles/Airplanes", paint="#f2f0ea", paint2="#2f6fd6")
AS = 0.5   # symmetric-ish aerofoils

# ------------------------------------------------------------------ fuselage loft (canopy = glass part of the same loft)
SEC = [  # y, hw, zb, zbelt, zs, zt, ht
    (6.85, 0.04, 1.35, 1.40, 1.50, 1.55, 0.02),
    (6.30, 0.30, 1.20, 1.38, 1.66, 1.80, 0.16),
    (5.35, 0.50, 1.02, 1.35, 1.95, 2.12, 0.28),
    (4.65, 0.60, 0.94, 1.45, 2.20, 2.40, 0.30),
    (4.10, 0.66, 0.90, 1.55, 2.50, 2.72, 0.34),
    (2.40, 0.68, 0.88, 1.60, 2.52, 2.76, 0.36),
    (0.90, 0.68, 0.88, 1.55, 2.40, 2.58, 0.36),
    (-0.40, 0.68, 0.88, 1.40, 2.20, 2.34, 0.38),
    (-2.40, 0.64, 0.90, 1.35, 2.08, 2.22, 0.36),
    (-4.00, 0.50, 0.98, 1.35, 2.00, 2.14, 0.26),
    (-5.50, 0.30, 1.10, 1.40, 1.95, 2.08, 0.16),
    (-5.95, 0.20, 1.20, 1.46, 1.86, 1.98, 0.11),
]
RAD = [P2] * 10
FWD = [P2, P2, P, P, P, P, P, P, P, P2]
SCR = [P2, P2, P, G, G, G, G, G, P, P2]       # windscreen / canopy glazing
REAR = [P2, P2, P, G, P, P, P, G, P, P2]      # canopy rear taper
BODY = [P2, P2, P, P, P, P, P, P, P, P2]
SEGM = [RAD, RAD, FWD, SCR, SCR, SCR, REAR, BODY, BODY, BODY, BODY]
b = MB("pj_body")
l3_loft(b, [l3_ring_cab(*s, cb=0.16, tum=0.93) for s in SEC], segmats=SEGM, cap0=P2, cap1="MetalDark")


def sec_at(y):
    for a, c in zip(SEC, SEC[1:]):
        if a[0] >= y >= c[0]:
            u = (a[0] - y) / (a[0] - c[0])
            return [l3_lerp(a[i], c[i], u) for i in range(7)]
    return list(SEC[-1])


# canopy frame: arches, spine, sills
for yy in (4.15, 2.45, 0.95):
    s_ = sec_at(yy)
    ring = l3_ring_cab(yy, s_[1], s_[2], s_[3], s_[4], s_[5], s_[6], cb=0.16, tum=0.93)
    up = [Vector(ring[i]) for i in (3, 4, 5, 6, 7, 8)]
    for p0, p1 in zip(up, up[1:]):
        b.beam(p0 * 1.0 + Vector((0, 0, 0.012)), p1 + Vector((0, 0, 0.012)), 0.028, 0.028, 4, T)
s5 = sec_at(2.4)
for (ya, yb_) in ((4.10, 2.40), (2.40, 0.90)):
    b.beam((0, ya, sec_at(ya)[5] + 0.014), (0, yb_, sec_at(yb_)[5] + 0.014), 0.026, 0.026, 4, T)
for sd in (-1, 1):
    for (ya, yb_) in ((4.65, 4.10), (4.10, 2.40), (2.40, 0.90), (0.90, -0.40)):
        b.beam((sd * (sec_at(ya)[1] + 0.012), ya, sec_at(ya)[3]), (sd * (sec_at(yb_)[1] + 0.012), yb_, sec_at(yb_)[3]), 0.03, 0.03, 4, T)
    # intakes beside the cockpit rear / wing root, panel lines, gear door seam
    b.box((sd * 0.78, 1.55, 1.12), (0.20, 1.30, 0.50), T)
    b.box((sd * 0.81, 2.22, 1.12), (0.16, 0.06, 0.54), "Chrome")
    b.box((sd * 0.73, 4.05, 1.05), (0.03, 0.30, 0.28), T)                    # vent
    l3_seam_v(b, sd * 0.69, 0.50, 0.95, 1.40, T, 0.02, 0.012)
    l3_seam_h(b, sd * 0.70, 4.10, 0.50, 1.00, T, 0.018, 0.012)
# nose details
b.beam((0, 6.80, 1.50), (0, 7.00, 1.50), 0.016, 0.01, 5, "Chrome")           # pitot tube
b.box((0, 5.60, 1.62), (0.16, 0.16, 0.05), T)                                  # radome-side sensor
for sd in (-1, 1):
    b.box((sd * 0.46, 5.35, 1.20), (0.05, 0.22, 0.09), "LightHead")
b.beam((0, -1.0, 2.34), (0, -1.2, 2.58), 0.012, 0.012, 4, T)                  # antenna

# ------------------------------------------------------------------ cockpit interior (visible through the glass loft)
b.box((0, 3.00, 1.20), (1.14, 3.9, 0.05), "Interior")                           # floor
b.block((0, 4.50), 1.28, 1.80, (1.20, 0.50), (1.12, 0.36), "Interior", top_shift=(0.0, 0.04))   # coaming + panel
b.box((-0.30, 4.30, 1.83), (0.34, 0.04, 0.22), "LightBlue")                    # HUD glow
b.box((0.30, 4.35, 1.74), (0.34, 0.03, 0.18), "LightBlue")
b.box((0, 3.10, 1.42), (0.16, 1.2, 0.32), "Interior")                           # centre console
for x in (-0.30, 0.30):
    l3_seat(b, x, 3.20, 1.22, 0.46, 0.50, 0.90, 0.20, "Fabric", 0.06, True, "SeatBlue")
    b.beam((x, 3.95, 1.25), (x, 3.78, 1.62), 0.018, 0.018, 4, "MetalDark")        # control stick
    b.box((x, 3.76, 1.66), (0.05, 0.05, 0.10), T)
    b.box((x, 2.78, 2.28), (0.30, 0.10, 0.18), "Interior")                         # headrest / ejection box

# ------------------------------------------------------------------ wings (swept, straight hinge line at y = YH)
DIH = math.tan(math.radians(2.0))


def wst(x, y_le, c, t):
    return dict(x=x, y=y_le, z=1.25 + x * DIH, c=c, t=t)


W = [wst(0.55, 1.60, 3.20, 0.40), wst(4.75, -0.50, 1.10, 0.13)]
YH = -1.05
for sd in (-1, 1):
    l3_wing(b, W, YH, sd, mats=(P, P, P, T, P, P, P), asym=AS, cap_root=P, cap_tip=P2)
    l3_wedge(b, W, YH, 0.55, 2.80, sd, P, P, AS)         # flaps
    l3_wedge(b, W, YH, 4.60, 4.75, sd, P2, P2, AS)       # tip filler
    b.box((sd * 4.80, -1.02, 1.25 + 4.75 * DIH), (0.05, 0.24, 0.07), "LightRed" if sd < 0 else "LightGreen")
    # wing fence + pylon stub
    st_ = l3_st_at(W, 3.0)
    b.box((sd * 3.0, st_["y"] - 0.9, st_["z"] + 0.10), (0.02, 1.00, 0.18), P)

# ------------------------------------------------------------------ engines (twin rear nacelles + nozzles)
NAC = [(-0.30, 0.34), (-1.20, 0.45), (-2.60, 0.50), (-4.20, 0.50), (-5.50, 0.44), (-6.00, 0.43)]
for sd in (-1, 1):
    rings = [l3_ring_oct(y, r, 1.36, r, 8, xc=sd * 0.56, rot_deg=22.5) for (y, r) in NAC]
    l3_loft(b, rings, segmats=[P, P, P, P, "MetalDark"], cap0=P, cap1="MetalDark")
    l3_revolve_y(b, [(-6.00, 0.43), (-6.50, 0.34), (-6.50, 0.27), (-6.00, 0.36), (-6.00, 0.43)], 10, "MetalDark", c=(sd * 0.56, 0, 1.36))   # nozzle shell
    b.cyl((sd * 0.56, -6.38, 1.36), 0.30, 0.03, 10, "ExhaustGlow", axis="Y")                          # glow disc
    b.cyl((sd * 0.56, -6.24, 1.36), 0.12, 0.30, 6, "MetalDark", axis="Y", r_top=0.02)                 # centre cone

# ------------------------------------------------------------------ tail: fin + T-tail stabiliser
l3_fin(b, [dict(z=1.95, y=-3.10, w=0.34), dict(z=3.00, y=-4.35, w=0.20), dict(z=4.00, y=-5.15, w=0.12)], -5.70, P, P2, P)
TS = [dict(x=0.0, y=-5.00, z=4.04, c=1.35, t=0.10), dict(x=1.90, y=-5.73, z=4.04, c=0.62, t=0.06)]
YH2 = -6.00
for sd in (-1, 1):
    l3_wing(b, TS, YH2, sd, mats=(P, P, P, T, P, P, P), asym=AS, cap_root=P, cap_tip=P2)
b.box((0, -6.09, 3.88), (0.06, 0.04, 0.16), "LightTail")
b.box((0, -5.20, 4.10), (0.08, 0.30, 0.05), "LightRed")                         # beacon on the stabiliser
b.box((0, -3.40, 2.19), (0.12, 1.6, 0.07), P2)                                  # dorsal fillet / spine stripe

# ------------------------------------------------------------------ landing gear (down)
b.beam((0, 4.00, 0.95), (0, 4.12, 0.42), 0.06, 0.05, 6, "MetalDark")           # nose strut
b.cyl((0, 4.05, 0.70), 0.075, 0.30, 6, "Chrome", axis="Z")
for sd in (-1, 1):
    b.beam((sd * 0.12, 4.12, 0.42), (sd * 0.12, 4.12, 0.27), 0.022, 0.022, 4, "MetalDark")
    b.beam((sd * 1.05, -0.30, 1.10), (sd * 1.32, -0.45, 0.42), 0.075, 0.06, 6, "MetalDark")  # main leg
    b.cyl((sd * 1.18, -0.38, 0.78), 0.085, 0.34, 6, "Chrome", axis="Z")
    b.beam((sd * 0.70, -1.10, 1.05), (sd * 1.24, -0.50, 0.60), 0.032, 0.032, 4, "MetalDark")  # side brace
    b.beam((sd * 1.30, -0.45, 0.35), (sd * 1.46, -0.45, 0.34), 0.04, 0.04, 4, "MetalDark")    # axle stub
    b.box((sd * 0.98, -0.20, 1.02), (0.03, 0.9, 0.34), P2)                    # wheel-well door
b.box((0, 4.17, 0.62), (0.14, 0.03, 0.09), "LightHead")                         # landing light
A.mesh(b, "Body")

# ------------------------------------------------------------------ control surfaces (origin on the hinge line)
for sd, nm in ((-1, "Aileron_L"), (1, "Aileron_R")):
    ab = MB("pj_" + nm)
    l3_wedge(ab, W, YH, 2.90, 4.55, sd, P2, P2, AS)
    A.part(ab, nm, l3_hinge_pt(W, YH, 3.72, sd, AS))
eb = MB("pj_elev")
for sd in (-1, 1):
    l3_wedge(eb, TS, YH2, 0.0, 1.90, sd, P2, P2, AS)
A.part(eb, "Elevator", (0.0, YH2, l3_hinge_pt(TS, YH2, 0.9, 1, AS)[2]))
rb = MB("pj_rudder")
l3_rudder(rb, -5.70, -6.25, -6.05, 2.25, 3.95, 0.30, 0.13, P2)
A.part(rb, "Rudder", (0.0, -5.70, 2.25))

# ------------------------------------------------------------------ wheels
for nm, x, y, r, w_, s in (("Wheel_RL", -1.40, -0.45, 0.34, 0.20, -1), ("Wheel_RR", 1.40, -0.45, 0.34, 0.20, 1), ("Wheel_F", 0.0, 4.12, 0.26, 0.14, 1)):
    wh = l3_wheel(A.prefix + nm, r, w_, s, A.coll, 12, loc=(x, y, r))
    parent_to(wh, A.root)
    A.objs[nm] = wh

# ------------------------------------------------------------------ anchors
A.node("SeatPilot", (-0.30, 3.20, 1.67))
A.node("SeatCopilot", (0.30, 3.20, 1.67))
A.node("ExitL", (-1.60, 3.20, 0.0))
A.node("ExitR", (1.60, 3.20, 0.0))
A.node("NavLightL", (-4.80, -1.02, 1.25 + 4.75 * DIH))
A.node("NavLightR", (4.80, -1.02, 1.25 + 4.75 * DIH))
A.node("HeadlightF", (0.0, 4.18, 0.62))
A.node("TaillightR", (0.0, -6.10, 3.88))
A.node("Exhaust", (0.0, -6.55, 1.36))
A.node("ExhaustL", (-0.56, -6.55, 1.36))
A.node("ExhaustR", (0.56, -6.55, 1.36))

A.mats()
bpy.context.view_layer.update()
l3_qa(A)

if globals().get("L3_EXPORT"):
    A.export()
    save_master()
