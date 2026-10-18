"""lane1_suv.py - builds vehicles/suv (lane 1, index 1). 4.85 x 1.98 x 1.82, WB 2.90, wheel r 0.38. Idempotent; does not export."""
WS = 0.94
car = Car("suv", 1, wheelbase=2.90, wr=0.38, ww=0.27, ws=WS, paint="#2f6fd6", paint2="#2a2d33")
wheels = car.wheel_specs(inset=0.29, flare=0.035)

K = [
    key(-2.25, 0.91, 0.42, 1.15, zsh=1.05, wt=0.86, wb=0.84, zl=0.52, zc=1.15),
    key(-2.10, 0.93, 0.32, 1.15, zsh=1.05, wt=0.89, zc=1.15),
    key(-1.92, 0.94, 0.30, 1.15, zsh=1.05, wt=0.91, zc=0.93),
    key(-0.95, 0.94, 0.30, 1.15, zsh=1.05, wt=0.91, zc=0.93),
    key(0.95, 0.94, 0.30, 1.15, zsh=1.05, wt=0.91, zc=1.155),
    key(1.40, 0.94, 0.30, 1.10, zsh=1.00, wt=0.86, zc=1.14),
    key(2.10, 0.935, 0.34, 1.06, zsh=0.97, wt=0.85, zc=1.10),
    key(2.28, 0.92, 0.38, 1.02, zsh=0.93, wt=0.83, zc=1.05),
    key(2.38, 0.86, 0.46, 0.95, zsh=0.86, wt=0.78, wb=0.78, zl=0.54, zc=0.97),
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
        return "Paint" if (ym > 0.9 or ym < -2.2) else "Interior"
    return "Interior"


mb = MB("body")
build_section(mb, stations(K, wheels, -2.25, -0.95), "tub", mat_fn, cap0="Paint", cap1="Interior")
build_section(mb, stations(K, wheels, -0.95, 0.95), "ch", mat_fn, cap0="Trim", cap1="Trim", floor=0.40, wall=0.08)
build_section(mb, stations(K, wheels, 0.95, 2.38), "tub", mat_fn, cap0="Interior", cap1="Trim")

# ---- greenhouse --------------------------------------------------------------------------------------------------
BELT, ROOF = 1.16, 1.72
A, B, C, D = (0.95, BELT), (0.35, ROOF), (-2.03, ROOF), (-2.22, BELT)
G = [A, B, C, D]
WGB, WGR = 0.89, 0.745


def gx(z):
    return lerp(WGB, WGR, clamp((z - BELT) / (ROOF - BELT), 0, 1))


shell_yz(mb, G, gx, ["Glass", "Paint2", "Glass", "Interior"], "Glass")
mb.block((0, -0.80), ROOF - 0.005, ROOF + 0.045, (2 * WGR + 0.07, 2.52), (2 * WGR - 0.02, 2.40), "Paint")
wipers(mb, A, B, gx)
wins = [clip_poly(G, lo=-0.06), clip_poly(G, lo=-0.97, hi=-0.14), clip_poly(G, hi=-1.04)]
pillars = [clip_poly(G, lo=-0.14, hi=-0.06), clip_poly(G, lo=-1.04, hi=-0.97)]
for s in (1, -1):
    for w in wins[1:]:
        frame_slab(mb, w, gx, s, 0.05, 0.014, 0.002, "Trim")
    for p in pillars:
        flat_slab(mb, p, gx, s, 0.014, 0.002, "Paint2")
# roof rails
for s in (1, -1):
    mb.box((s * 0.66, -0.82, ROOF + 0.075), (0.045, 2.15, 0.035), "Chrome")
    for y in (0.15, -0.85, -1.80):
        mb.box((s * 0.66, y, ROOF + 0.057), (0.05, 0.07, 0.03), "Trim")

# ---- panel lines, cladding, steps -------------------------------------------------------------------------------
for s in (1, -1):
    x = s * (WS + 0.002)
    seam_v(mb, x, -0.10, 0.31, 1.14)
    seam_v(mb, x, -0.98, 0.31, 1.14)
    seam_h(mb, x, -0.98, -0.10, 0.312)
    mb.box((s * (WS + 0.014), -0.84, 0.97), (0.03, 0.13, 0.025), "Chrome")      # rear door handle
    # lower cladding between the wheel arches (dark plastic)
    flat_slab(mb, bevel_rect(-0.98, -0.07, 0.30, 0.50, 0.03, 0.005), lambda z: WS, s, 0.02, 0.0, "Paint2")
    # side steps
    mb.box((s * (WS - 0.01), 0.0, 0.31), (0.12, 1.50, 0.045), "MetalDark")
    for y in (-0.55, 0.55):
        mb.box((s * (WS - 0.01), y, 0.37), (0.06, 0.07, 0.14), "Trim")
# hood seams
for s in (1, -1):
    mb.beam((s * 0.66, 1.00, top_z(1.00, 0.66) + 0.004), (s * 0.66, 2.20, top_z(2.20, 0.66) + 0.004), 0.007, 0.007, 4, "Trim")
mb.beam((-0.66, 1.00, top_z(1.00, 0.66) + 0.004), (0.66, 1.00, top_z(1.00, 0.66) + 0.004), 0.007, 0.007, 4, "Trim")
# tailgate seams
for s in (1, -1):
    mb.beam((s * 0.80, -2.255, 0.55), (s * 0.80, -2.255, 1.14), 0.007, 0.007, 4, "Trim")
mb.beam((-0.80, -2.255, 0.55), (0.80, -2.255, 0.55), 0.007, 0.007, 4, "Trim")

# ---- interior ------------------------------------------------------------------------------------------------
FZ = 0.40
mb.block((0, 0.75), 0.42, 1.08, (1.70, 0.36), (1.70, 0.28), "Interior", top_shift=(0.03, 0))
mb.box((0, 0.66, 0.98), (1.40, 0.06, 0.05), "Trim")
mb.box((0, 0.30, 0.56), (0.26, 0.85, 0.30), "Interior")
steering_wheel(mb, (-0.40, 0.46, 1.10), 22, 0.19, "Trim", "Interior")
for sx in (-0.40, 0.40):
    seat(mb, sx, 0.15, FZ, 0.52, 0.52, 0.66, 0.29, "Interior")
    seat(mb, sx * 1.12, -0.62, FZ, 0.52, 0.50, 0.62, 0.29, "Interior")
seat(mb, 0, -0.62, FZ, 0.46, 0.50, 0.62, 0.29, "Interior", head=True)

# ---- front end ----------------------------------------------------------------------------------------------------
bump_f = [(-0.90, 2.08), (0.90, 2.08), (0.955, 2.22), (0.93, 2.34), (0.78, 2.40), (-0.78, 2.40), (-0.93, 2.34), (-0.955, 2.22)]
mb.prism(bump_f, 0.30, 0.62, "Trim")
mb.box((0, 2.39, 0.60), (0.70, 0.04, 0.12), "MetalDark")          # skid plate
mb.box((0, 2.365, 0.78), (1.06, 0.05, 0.28), "Trim")                  # grille
for i in range(4):
    mb.box((0, 2.388, 0.68 + i * 0.065), (1.02, 0.014, 0.02), "Chrome")
for s in (1, -1):
    mb.box((s * 0.66, 2.32, 0.84), (0.30, 0.12, 0.17), "LightHead")
    mb.box((s * 0.66, 2.31, 0.95), (0.34, 0.14, 0.035), "Trim")
    mb.box((s * 0.74, 2.35, 0.56), (0.14, 0.09, 0.07), "LightAmber")   # fog / indicator

# ---- rear end -------------------------------------------------------------------------------------------------------
bump_r = [(-0.90, -2.05), (0.90, -2.05), (0.955, -2.15), (0.93, -2.28), (0.78, -2.33), (-0.78, -2.33), (-0.93, -2.28), (-0.955, -2.15)]
mb.prism(bump_r, 0.30, 0.64, "Trim")
for s in (1, -1):
    mb.box((s * 0.84, -2.24, 0.90), (0.14, 0.07, 0.40), "LightTail")
    mb.box((s * 0.55, -2.34, 0.34), (0.08, 0.04, 0.05), "LightAmber")      # reflectors
mb.box((0, -2.335, 0.50), (0.54, 0.014, 0.13), "Trim")
mb.box((0, -2.343, 0.50), (0.46, 0.012, 0.10), "Plate")
# spare tyre on the tailgate (tyre + rim disc + hub), mount bracket
SY, SZ = -2.32, 0.98
mb.cyl((0, SY, SZ), 0.36, 0.20, 14, "Tire", axis="Y", smooth=True)
mb.cyl((0, SY - 0.105, SZ), 0.20, 0.03, 10, "Rim", axis="Y")
mb.cyl((0, SY - 0.12, SZ), 0.07, 0.03, 6, "Chrome", axis="Y")
mb.box((0, -2.275, SZ), (0.20, 0.06, 0.20), "Trim")
for s in (1, -1):
    mb.cyl((s * 0.62, -2.38, 0.38), 0.035, 0.10, 8, "Chrome", axis="Y")      # exhaust tips

body = car.mesh(mb, "Body")
island_report(body)

# ---- doors --------------------------------------------------------------------------------------------------------
YH = 0.92
for s, nm in ((-1, "DoorL"), (1, "DoorR")):
    dm = MB("door")
    flat_slab(dm, bevel_rect(-0.06, YH, 0.52, 1.145, 0.005, 0.012), lambda z: WS, s, 0.035, -0.018, "Paint")
    flat_slab(dm, bevel_rect(-0.06, YH, 0.31, 0.52, 0.035, 0.005), lambda z: WS, s, 0.036, -0.018, "Paint2")
    frame_slab(dm, wins[0], gx, s, 0.05, 0.014, 0.002, "Trim")
    dm.box((s * (WS + 0.034), -0.02, 0.97), (0.03, 0.13, 0.025), "Chrome")
    dm.beam((s * (WS + 0.005), 0.78, 1.05), (s * (WS + 0.03), 0.76, 1.10), 0.012, 0.012, 4, "Trim")
    dm.block((s * (WS + 0.04), 0.74), 1.06, 1.20, (0.05, 0.17), (0.045, 0.14), "Paint2", top_shift=(0, 0.01))
    dm.translate((-s * WS, -YH, -0.31))
    car.mesh(dm, nm, loc=(s * WS, YH, 0.31))

car.wheels(rim="Rim", ws_front=WS, ws_rear=WS)
car.anchors(head=(0.66, 2.34, 0.84), tail=(0.84, -2.25, 0.90), seat_y=0.15, seat_z=0.85, rear_y=-0.62, exit_y=0.43, exit_x=2.0, exhaust=(-0.62, -2.40, 0.38))
build_lod(car, K, -2.25, 2.38, G, gx, mat_fn=mat_fn, boxes=[
    ((0.66, 2.32, 0.84), (0.30, 0.12, 0.17), "LightHead"), ((-0.66, 2.32, 0.84), (0.30, 0.12, 0.17), "LightHead"),
    ((0.84, -2.24, 0.90), (0.14, 0.07, 0.40), "LightTail"), ((-0.84, -2.24, 0.90), (0.14, 0.07, 0.40), "LightTail")])
car.mats()
print("tris:", tri_total(car.root))
