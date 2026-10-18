"""lane1_pickup.py - builds vehicles/pickup (lane 1, index 2). 5.35 x 1.98 x 1.85, WB 3.25, wheel r 0.38. Idempotent; does not export.
Crew cab + separate open cargo bed mesh (Bed), tailgate, bull bar, roll bar with light bar."""
WS = 0.93
car = Car("pickup", 2, wheelbase=3.25, wr=0.38, ww=0.28, ws=WS, paint="#e0b04a", paint2="#2a2d33")
wheels = car.wheel_specs(inset=0.30, flare=0.035)
BELT, ROOF = 1.20, 1.78

K = [
    key(-2.68, 0.90, 0.46, 1.20, zsh=1.10, wt=0.87, wb=0.84, zl=0.56, zc=1.20),
    key(-2.60, 0.93, 0.36, 1.20, zsh=1.10, wt=0.90, zc=1.20),
    key(-1.05, 0.93, 0.34, 1.20, zsh=1.10, wt=0.90, zc=1.20),
    key(1.00, 0.93, 0.34, 1.20, zsh=1.10, wt=0.90, zc=1.205),
    key(1.50, 0.93, 0.34, 1.16, zsh=1.06, wt=0.85, zc=1.19),
    key(2.20, 0.925, 0.36, 1.12, zsh=1.03, wt=0.84, zc=1.15),
    key(2.45, 0.91, 0.40, 1.06, zsh=0.97, wt=0.82, zc=1.10),
    key(2.55, 0.88, 0.48, 0.98, zsh=0.88, wt=0.80, wb=0.80, zl=0.58, zc=1.00),
]


def top_z(y, x=0.0):
    P = interp_st(K, y)
    f = clamp(abs(x) / max(P["wt"], 1e-3), 0, 1)
    return lerp(P["zc"], P["zd"], f)


def mat_fn(role, ym):
    if role in ("low", "bottom", "cham"):
        return "Trim"
    if role in ("side", "shoulder", "rim", "top"):
        return "Paint"
    return "Interior"


# ---- Body: tailgate, cab, hood -------------------------------------------------------------------------------------
mb = MB("body")
build_section(mb, stations(K, wheels, -2.68, -2.60), "tub", mat_fn, cap0="Paint", cap1="Interior")
build_section(mb, stations(K, wheels, -1.05, 1.00), "ch", mat_fn, cap0="Trim", cap1="Trim", floor=0.38, wall=0.08)
build_section(mb, stations(K, wheels, 1.00, 2.55), "tub", mat_fn, cap0="Interior", cap1="Trim")

A, B, C, D = (1.00, BELT), (0.42, ROOF), (-0.88, ROOF), (-1.05, BELT)
G = [A, B, C, D]
WGB, WGR = 0.88, 0.74


def gx(z):
    return lerp(WGB, WGR, clamp((z - BELT) / (ROOF - BELT), 0, 1))


shell_yz(mb, G, gx, ["Glass", "Paint2", "Glass", "Interior"], "Glass")
mb.block((0, -0.23), ROOF - 0.005, ROOF + 0.045, (2 * WGR + 0.07, 1.46), (2 * WGR - 0.02, 1.34), "Paint")
wipers(mb, A, B, gx)
W1 = clip_poly(G, lo=0.10)
W2 = clip_poly(G, hi=0.04)
PB = clip_poly(G, lo=0.04, hi=0.10)
for s in (1, -1):
    frame_slab(mb, W2, gx, s, 0.05, 0.014, 0.002, "Trim")
    flat_slab(mb, PB, gx, s, 0.014, 0.002, "Paint2")
# headboard (cab rear wall) - cab side and bed side
mb.box((0, -1.03, (0.38 + BELT) / 2), (1.70, 0.02, BELT - 0.38), "Interior")
mb.box((0, -1.065, (0.40 + BELT) / 2), (1.76, 0.05, BELT - 0.40), "Paint")

# ---- panel lines, steps -----------------------------------------------------------------------------------------------
for s in (1, -1):
    x = s * (WS + 0.002)
    seam_v(mb, x, 0.07, 0.36, 1.19)
    seam_v(mb, x, -1.00, 0.36, 1.19)
    seam_h(mb, x, -1.00, 0.07, 0.362)
    mb.box((s * (WS + 0.014), -0.86, 1.00), (0.03, 0.13, 0.025), "Chrome")      # rear door handle
    mb.box((s * (WS - 0.01), 0.0, 0.33), (0.13, 1.90, 0.045), "MetalDark")       # side steps
    flat_slab(mb, bevel_rect(-1.16, 0.09, 0.34, 0.54, 0.03, 0.005), lambda z: WS, s, 0.02, 0.0, "Paint2")   # lower cladding
    for y in (-0.60, 0.60):
        mb.box((s * (WS - 0.01), y, 0.40), (0.06, 0.07, 0.14), "Trim")
for s in (1, -1):
    mb.beam((s * 0.66, 1.05, top_z(1.05, 0.66) + 0.004), (s * 0.66, 2.38, top_z(2.38, 0.66) + 0.004), 0.007, 0.007, 4, "Trim")
mb.beam((-0.66, 1.05, top_z(1.05, 0.66) + 0.004), (0.66, 1.05, top_z(1.05, 0.66) + 0.004), 0.007, 0.007, 4, "Trim")
# tailgate details
mb.box((0, -2.685, 1.04), (0.50, 0.03, 0.05), "Trim")             # tailgate handle recess
mb.box((0, -2.68, 0.84), (1.60, 0.02, 0.012), "Trim")
mb.box((0, -2.68, 1.12), (1.60, 0.02, 0.012), "Trim")

# ---- interior ---------------------------------------------------------------------------------------------------------
FZ = 0.38
mb.block((0, 0.84), 0.42, 1.12, (1.70, 0.34), (1.70, 0.26), "Interior", top_shift=(0.03, 0))
mb.box((0, 0.75, 1.02), (1.40, 0.06, 0.05), "Trim")
mb.box((0, 0.42, 0.55), (0.26, 0.85, 0.30), "Interior")
steering_wheel(mb, (-0.40, 0.58, 1.10), 22, 0.19, "Trim", "Interior")
for sx in (-0.40, 0.40):
    seat(mb, sx, 0.38, FZ, 0.52, 0.52, 0.66, 0.32, "Interior")
seat(mb, 0, -0.55, FZ, 1.50, 0.50, 0.62, 0.32, "Interior", head=False)
for sx in (-0.40, 0.0, 0.40):
    mb.box((sx, -0.82, FZ + 0.88), (0.2, 0.09, 0.15), "Interior")

# ---- front end ---------------------------------------------------------------------------------------------------------
bump_f = [(-0.90, 2.30), (0.90, 2.30), (0.95, 2.42), (0.93, 2.52), (0.78, 2.58), (-0.78, 2.58), (-0.93, 2.52), (-0.95, 2.42)]
mb.prism(bump_f, 0.34, 0.64, "Trim")
mb.box((0, 2.54, 0.80), (1.10, 0.06, 0.34), "Trim")                  # big grille
mb.box((0, 2.575, 0.80), (1.14, 0.02, 0.38), "Chrome")
mb.box((0, 2.58, 0.80), (1.00, 0.02, 0.28), "Trim")
for i in range(4):
    mb.box((0, 2.595, 0.68 + i * 0.075), (0.98, 0.012, 0.02), "Chrome")
for s in (1, -1):
    mb.box((s * 0.69, 2.50, 0.86), (0.30, 0.11, 0.18), "LightHead")
    mb.box((s * 0.69, 2.48, 0.97), (0.34, 0.12, 0.035), "Trim")
    mb.box((s * 0.78, 2.55, 0.52), (0.14, 0.08, 0.07), "LightAmber")
# bull bar (reaches y = 2.65)
for s in (1, -1):
    mb.beam((s * 0.55, 2.45, 0.40), (s * 0.55, 2.62, 0.45), 0.035, 0.035, 6, "Chrome")
    mb.beam((s * 0.55, 2.62, 0.45), (s * 0.55, 2.62, 1.00), 0.035, 0.035, 6, "Chrome")
    mb.beam((s * 0.55, 2.62, 1.00), (s * 0.55, 2.40, 1.10), 0.03, 0.03, 6, "Chrome")
mb.beam((-0.55, 2.62, 1.00), (0.55, 2.62, 1.00), 0.035, 0.035, 6, "Chrome")
mb.beam((-0.55, 2.62, 0.62), (0.55, 2.62, 0.62), 0.03, 0.03, 6, "Chrome")
mb.beam((0, 2.62, 0.62), (0, 2.62, 1.00), 0.03, 0.03, 6, "Chrome")

# ---- rear end ---------------------------------------------------------------------------------------------------------
bump_r = [(-0.90, -2.55), (0.90, -2.55), (0.95, -2.62), (0.93, -2.68), (0.80, -2.70), (-0.80, -2.70), (-0.93, -2.68), (-0.95, -2.62)]
mb.prism(bump_r, 0.40, 0.66, "Chrome")
for s in (1, -1):
    mb.box((s * 0.86, -2.665, 1.06), (0.12, 0.05, 0.20), "LightTail")
    mb.cyl((s * 0.62, -2.62, 0.34), 0.04, 0.10, 8, "Chrome", axis="Y")          # exhaust tips (under the bumper)
mb.box((0, -2.70, 0.54), (0.50, 0.015, 0.12), "Plate")
# roll bar + light bar behind the cab
for s in (1, -1):
    mb.beam((s * 0.76, -1.16, 1.20), (s * 0.76, -1.16, 1.82), 0.03, 0.03, 6, "MetalDark")
    mb.beam((s * 0.76, -1.16, 1.82), (s * 0.76, -1.05, 1.82), 0.028, 0.028, 6, "MetalDark")
mb.beam((-0.76, -1.16, 1.82), (0.76, -1.16, 1.82), 0.03, 0.03, 6, "MetalDark")
mb.box((0, -1.17, 1.74), (1.10, 0.11, 0.11), "Trim")
mb.box((0, -1.225, 1.74), (1.00, 0.015, 0.075), "LightHead")
for s in (1, -1):
    mb.box((s * 0.45, -1.225, 1.74), (0.02, 0.018, 0.08), "Trim")

body = car.mesh(mb, "Body")
island_report(body)

# ---- cargo bed (separate mesh) --------------------------------------------------------------------------------------
bm_ = MB("bed")
build_section(bm_, stations(K, wheels, -2.60, -1.05), "ch", mat_fn, cap0="Interior", cap1="Trim", floor=0.90, wall=0.10)
for y in (-1.35, -1.75, -2.15, -2.45):
    bm_.box((0, y, 0.915), (1.40, 0.07, 0.025), "Trim")                 # floor ribs
for s in (1, -1):
    bm_.box((s * 0.83, -1.82, 1.215), (0.10, 1.0, 0.02), "Trim")          # side rail caps hint
car.mesh(bm_, "Bed")
island_report(car.objs["Bed"])

# ---- doors ----------------------------------------------------------------------------------------------------------------
YH = 0.98
for s, nm in ((-1, "DoorL"), (1, "DoorR")):
    dm = MB("door")
    flat_slab(dm, bevel_rect(0.10, YH, 0.54, 1.195, 0.005, 0.012), lambda z: WS, s, 0.035, -0.018, "Paint")
    flat_slab(dm, bevel_rect(0.10, YH, 0.36, 0.54, 0.035, 0.005), lambda z: WS, s, 0.036, -0.018, "Paint2")
    frame_slab(dm, W1, gx, s, 0.05, 0.014, 0.002, "Trim")
    dm.box((s * (WS + 0.034), 0.19, 1.00), (0.03, 0.13, 0.025), "Chrome")
    dm.beam((s * (WS + 0.005), 0.86, 1.08), (s * (WS + 0.035), 0.84, 1.14), 0.014, 0.014, 4, "Trim")
    dm.block((s * (WS + 0.04), 0.80), 1.08, 1.27, (0.05, 0.19), (0.045, 0.16), "Trim", top_shift=(0, 0.015))
    dm.translate((-s * WS, -YH, -0.36))
    car.mesh(dm, nm, loc=(s * WS, YH, 0.36))

car.wheels(rim="Rim", ws_front=WS, ws_rear=WS)
car.anchors(head=(0.69, 2.52, 0.86), tail=(0.86, -2.66, 1.06), seat_y=0.38, seat_z=0.86, rear_y=-0.55, exit_y=0.54, exit_x=2.0, exhaust=(-0.62, -2.67, 0.34))
build_lod(car, K, -2.68, 2.55, G, gx, mat_fn=mat_fn, boxes=[
    ((0.69, 2.52, 0.86), (0.30, 0.11, 0.18), "LightHead"), ((-0.69, 2.52, 0.86), (0.30, 0.11, 0.18), "LightHead"),
    ((0.86, -2.665, 1.06), (0.12, 0.05, 0.20), "LightTail"), ((-0.86, -2.665, 1.06), (0.12, 0.05, 0.20), "LightTail")])
car.mats()
print("tris:", tri_total(car.root))
