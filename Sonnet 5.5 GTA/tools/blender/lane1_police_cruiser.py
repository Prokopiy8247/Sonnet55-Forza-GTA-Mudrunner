"""lane1_police_cruiser.py - builds vehicles/police_cruiser (lane 1, index 0). Idempotent. 4.90 x 1.86 x 1.50, WB 2.90, wheel r 0.34.
Run: exec(open(path).read(), globals()) after loading gta_lib.py + lane1_common.py. Does NOT export (call car.export() separately)."""
WS = 0.90
car = Car("police_cruiser", 0, wheelbase=2.90, wr=0.34, ww=0.25, ws=WS, paint="#f2f0ea", paint2="#141a2b")
wheels = car.wheel_specs(inset=0.27)

K = [
    key(-2.50, 0.74, 0.40, 0.74, zsh=0.64, wt=0.66, wb=0.66, zl=0.48, zc=0.75),
    key(-2.43, 0.85, 0.30, 0.88, zsh=0.76, wt=0.76, wb=0.76, zl=0.40, zc=0.90),
    key(-2.25, 0.89, 0.25, 0.945, zsh=0.85, zc=0.965),
    key(-1.90, 0.90, 0.24, 0.975, zc=0.985),
    key(-1.42, 0.90, 0.24, 0.98, wt=0.87, zsh=0.93, zc=0.985),
    key(-1.00, 0.90, 0.24, 0.98, wt=0.87, zsh=0.93, zc=0.985),
    key(0.90, 0.90, 0.24, 0.98, wt=0.87, zsh=0.93, zc=0.985),
    key(1.30, 0.90, 0.24, 0.945, zsh=0.86, zc=0.985),
    key(1.90, 0.90, 0.24, 0.905, zsh=0.82, zc=0.950),
    key(2.14, 0.885, 0.26, 0.865, zsh=0.78, zc=0.900),
    key(2.24, 0.84, 0.29, 0.80, zsh=0.70, wt=0.74, wb=0.75, zl=0.38, zc=0.81),
    key(2.30, 0.76, 0.34, 0.73, zsh=0.64, wt=0.66, wb=0.66, zl=0.43, zc=0.735),
]


def top_z(y, x=0.0):
    P = interp_st(K, y)
    f = clamp(abs(x) / max(P["wt"], 1e-3), 0, 1)
    return lerp(P["zc"], P["zd"], f)


def mat_fn(role, ym):
    if role in ("low", "bottom", "cham"):
        return "Trim"
    if role in ("side", "shoulder", "rim"):
        return "Paint"
    if role == "top":
        return "Paint2" if (ym > 0.9 or ym < -1.42) else "Interior"
    return "Interior"


mb = MB("body")
# ---- body shells ---------------------------------------------------------------------------------------------
build_section(mb, stations(K, wheels, -2.50, -1.00), "tub", mat_fn, cap0="Paint", cap1="Interior")
build_section(mb, stations(K, wheels, -1.00, 0.90), "ch", mat_fn, cap0="Trim", cap1="Trim", floor=0.30, wall=0.08)
build_section(mb, stations(K, wheels, 0.90, 2.30), "tub", mat_fn, cap0="Interior", cap1="Trim")

# ---- greenhouse ----------------------------------------------------------------------------------------------
BELT, ROOF = 0.985, 1.36
A, B, C, D = (0.88, BELT), (0.18, ROOF), (-0.92, ROOF), (-1.42, BELT)
G = [A, B, C, D]
WGB, WGR = 0.855, 0.68


def gx(z):
    return lerp(WGB, WGR, clamp((z - BELT) / (ROOF - BELT), 0, 1))


shell_yz(mb, G, gx, ["Glass", "Paint2", "Glass", "Interior"], "Glass")
mb.block((0, -0.37), ROOF - 0.005, ROOF + 0.04, (2 * WGR + 0.06, 1.24), (2 * WGR - 0.02, 1.10), "Paint")
wipers(mb, A, B, gx)
YB = -0.15   # B pillar centre
rear_win = clip_poly(G, hi=YB - 0.03)
bpillar = clip_poly(G, lo=YB - 0.03, hi=YB + 0.03)
for s in (1, -1):
    frame_slab(mb, rear_win, gx, s, 0.05, 0.014, 0.002, "Trim")
    flat_slab(mb, bpillar, gx, s, 0.014, 0.002, "Trim")

# ---- panel lines, handles, trim ----------------------------------------------------------------------------------
for s in (1, -1):
    x = s * (WS + 0.002)
    seam_v(mb, x, YB - 0.03, 0.27, 0.975)
    seam_v(mb, x, -1.00, 0.27, 0.975)
    seam_h(mb, x, -1.00, YB - 0.03, 0.272)
    mb.box((s * (WS + 0.014), -0.20 - 0.62, 0.90), (0.03, 0.13, 0.025), "Chrome")   # rear door handle
    # fuel / rear quarter detail
# hood seams
for s in (1, -1):
    mb.beam((s * 0.62, 0.95, top_z(0.95, 0.62) + 0.004), (s * 0.62, 2.12, top_z(2.12, 0.62) + 0.004), 0.007, 0.007, 4, "Trim")
mb.beam((-0.62, 0.95, top_z(0.95, 0.62) + 0.004), (0.62, 0.95, top_z(0.95, 0.62) + 0.004), 0.007, 0.007, 4, "Trim")
# trunk seam
mb.beam((-0.70, -1.46, 0.985), (0.70, -1.46, 0.985), 0.007, 0.007, 4, "Trim")

# ---- interior ------------------------------------------------------------------------------------------------
FZ = 0.30
mb.block((0, 0.73), 0.34, 0.93, (1.60, 0.34), (1.60, 0.26), "Interior", top_shift=(0.03, 0))     # dashboard
mb.box((0, 0.64, 0.86), (1.30, 0.06, 0.05), "Trim")                                               # dash vents strip
mb.box((0, 0.30, 0.44), (0.24, 0.80, 0.24), "Interior")                                          # centre console
steering_wheel(mb, (-0.40, 0.47, 0.83), 24, 0.18, "Trim", "Interior")
for sx in (-0.40, 0.40):
    seat(mb, sx, -0.05, FZ, 0.50, 0.50, 0.64, 0.04, "Interior")
seat(mb, 0, -0.78, FZ, 1.42, 0.50, 0.60, 0.04, "Trim", head=False, recline=0.08)                    # rear bench (hard plastic)
# prisoner cage behind the front seats
CZ0, CZ1, CY = 0.62, 1.30, -0.36
for x in (-0.76, -0.38, 0.0, 0.38, 0.76):
    mb.box((x, CY, (CZ0 + CZ1) / 2), (0.025, 0.025, CZ1 - CZ0), "Trim")
mb.box((0, CY, CZ1), (1.56, 0.03, 0.03), "Trim")
mb.box((0, CY, CZ0 + 0.28), (1.56, 0.03, 0.03), "Trim")

# ---- front end -----------------------------------------------------------------------------------------------------
bump_f = [(-0.86, 2.00), (0.86, 2.00), (0.915, 2.14), (0.89, 2.25), (0.73, 2.335), (-0.73, 2.335), (-0.89, 2.25), (-0.915, 2.14)]
mb.prism(bump_f, 0.27, 0.55, "Trim")
mb.box((0, 2.30, 0.62), (1.02, 0.05, 0.14), "Trim")                          # grille surround
for i in range(3):
    mb.box((0, 2.33, 0.57 + i * 0.045), (0.98, 0.012, 0.014), "Chrome")      # grille bars
for s in (1, -1):
    mb.box((s * 0.69, 2.215, 0.665), (0.26, 0.13, 0.095), "LightHead")   # headlights
    mb.box((s * 0.69, 2.205, 0.735), (0.30, 0.15, 0.03), "Trim")
    mb.box((s * 0.80, 2.265, 0.50), (0.12, 0.11, 0.05), "LightAmber")        # corner lamps (turn signals)
mb.box((-0.34, 2.318, 0.69), (0.16, 0.03, 0.035), "LightBlue")             # grille LEDs (flash with the siren)
mb.box((0.34, 2.318, 0.69), (0.16, 0.03, 0.035), "LightRed")
# push bar (extends to y=2.40)
for s in (1, -1):
    mb.beam((s * 0.55, 2.28, 0.30), (s * 0.55, 2.38, 0.34), 0.035, 0.035, 4, "MetalDark")
    mb.beam((s * 0.55, 2.38, 0.34), (s * 0.55, 2.38, 0.74), 0.035, 0.035, 4, "MetalDark")
    mb.beam((s * 0.22, 2.38, 0.36), (s * 0.22, 2.38, 0.72), 0.03, 0.03, 4, "MetalDark")
mb.beam((-0.55, 2.38, 0.74), (0.55, 2.38, 0.74), 0.035, 0.035, 4, "MetalDark")
mb.beam((-0.55, 2.38, 0.36), (0.55, 2.38, 0.36), 0.035, 0.035, 4, "MetalDark")
mb.beam((-0.55, 2.38, 0.55), (0.55, 2.38, 0.55), 0.03, 0.03, 4, "MetalDark")

# ---- rear end ------------------------------------------------------------------------------------------------------
bump_r = [(-0.86, -2.05), (0.86, -2.05), (0.905, -2.20), (0.88, -2.38), (0.74, -2.52), (-0.74, -2.52), (-0.88, -2.38), (-0.905, -2.20)]
mb.prism(bump_r, 0.28, 0.58, "Trim")
for s in (1, -1):
    mb.box((s * 0.52, -2.485, 0.72), (0.46, 0.05, 0.11), "LightTail")
    mb.box((s * 0.80, -2.40, 0.72), (0.10, 0.14, 0.11), "LightTail")
mb.box((0, -2.51, 0.72), (0.54, 0.02, 0.10), "Trim")
mb.box((0, -2.515, 0.50), (0.54, 0.012, 0.13), "Trim")
mb.box((0, -2.522, 0.50), (0.46, 0.012, 0.10), "Plate")
# rear light bar (inside the rear window)
mb.box((-0.34, -1.20, 1.04), (0.62, 0.07, 0.05), "LightBlue")
mb.box((0.34, -1.20, 1.04), (0.62, 0.07, 0.05), "LightRed")
# exhaust tips
for s in (1, -1):
    mb.cyl((s * 0.55, -2.47, 0.265), 0.04, 0.10, 8, "Chrome", axis="Y")

body = car.mesh(mb, "Body")
print("body shells:", len(island_report(body, False)))

# ---- doors (hinged, origin at hinge) ---------------------------------------------------------------------------
YH = 0.86
for s, nm in ((-1, "DoorL"), (1, "DoorR")):
    dm = MB("door")
    skin = bevel_rect(-0.12, YH, 0.27, 0.975, 0.035, 0.012)
    flat_slab(dm, skin, lambda z: WS, s, 0.035, -0.018, "Paint2")
    fw = clip_poly(G, lo=-0.12)
    frame_slab(dm, fw, gx, s, 0.05, 0.014, 0.002, "Trim")
    dm.box((s * (WS + 0.034), -0.02, 0.90), (0.03, 0.13, 0.025), "Chrome")      # handle
    star = []                                                                       # badge on the dark door
    for i in range(10):
        ang = math.pi / 2 + math.pi * 2 * i / 10
        rr = 0.105 if i % 2 == 0 else 0.046
        star.append((0.40 + math.cos(ang) * rr, 0.62 + math.sin(ang) * rr))
    flat_slab(dm, star, lambda z: WS, s, 0.005, 0.0165, "Paint")
    # mirror (on the door, near the A pillar)
    dm.beam((s * (WS + 0.005), 0.66, 1.00), (s * (WS + 0.03), 0.64, 1.035), 0.012, 0.012, 4, "Trim")
    dm.block((s * (WS + 0.035), 0.62), 0.99, 1.09, (0.06, 0.15), (0.05, 0.12), "Paint2", top_shift=(0, 0.01))
    dm.translate((-s * WS, -YH, -0.27))
    car.mesh(dm, nm, loc=(s * WS, YH, 0.27))

# ---- wheels, anchors --------------------------------------------------------------------------------------------
car.wheels(rim="Metal")
car.anchors(head=(0.66, 2.30, 0.67), tail=(0.52, -2.50, 0.72), seat_y=-0.05, seat_z=0.48, rear_y=-0.74, exit_y=0.37, exit_x=1.95, exhaust=(-0.55, -2.55, 0.27))

# ---- roof light bar ----------------------------------------------------------------------------------------------
BARY, BARZ = -0.37, ROOF + 0.04
bar = MB("bar")
bar.box((0, 0, 0.012), (1.26, 0.30, 0.024), "Trim")                                     # base plate
bar.box((0, 0, 0.05), (0.14, 0.24, 0.07), "Trim")                                       # centre mount
for s in (1, -1):
    bar.box((s * 0.62, 0, 0.05), (0.04, 0.30, 0.07), "Trim")                               # end caps
bar_obj = car.mesh(bar, "SirenBar", loc=(0, BARY, BARZ))
for s, nm, m in ((-1, "SirenBar_L", "LightBlue"), (1, "SirenBar_R", "LightRed")):
    lm = MB(nm)
    lm.block((s * 0.34, 0), 0.024, 0.088, (0.50, 0.28), (0.44, 0.20), m)
    lm.block((s * 0.34, 0), 0.088, 0.100, (0.44, 0.20), (0.36, 0.14), m)
    car.mesh(lm, nm, loc=(0, 0, 0), parent=bar_obj)
# A-pillar spotlight (driver side)
sp = MB("spot")
sp.beam((0, 0, 0), (0, 0.20, 0.0), 0.05, 0.05, 6, "MetalDark")
sp.cyl((0, 0.205, 0), 0.04, 0.02, 6, "LightHead", axis="Y")
sp.box((0.0, -0.01, -0.06), (0.03, 0.05, 0.10), "Trim")
car.mesh(sp, "Spotlight", loc=(-0.875, 0.42, 1.05))

build_lod(car, K, -2.50, 2.30, G, gx, mat_fn=mat_fn, boxes=[
    ((0.69, 2.215, 0.665), (0.26, 0.13, 0.095), "LightHead"), ((-0.69, 2.215, 0.665), (0.26, 0.13, 0.095), "LightHead"),
    ((0.52, -2.485, 0.72), (0.46, 0.05, 0.11), "LightTail"), ((-0.52, -2.485, 0.72), (0.46, 0.05, 0.11), "LightTail"),
    ((-0.34, BARY, BARZ + 0.06), (0.50, 0.28, 0.08), "LightBlue"), ((0.34, BARY, BARZ + 0.06), (0.50, 0.28, 0.08), "LightRed"),
    ((0, BARY, BARZ + 0.03), (1.26, 0.30, 0.05), "Trim")])
car.mats()
print("tris:", tri_total(car.root))
