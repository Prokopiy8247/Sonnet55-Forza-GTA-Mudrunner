"""lane1_van.py - builds vehicles/van (lane 1, index 3). 5.20 x 2.05 x 2.25, WB 3.30, wheel r 0.34. Idempotent; does not export.
Boxy panel van: cab + solid cargo box, sliding door (right), rear double doors, roof vent. Seats: driver, passenger, one extra (rear)."""
WS = 0.97
car = Car("van", 3, wheelbase=3.30, wr=0.34, ww=0.25, ws=WS, paint="#e6e2d6", paint2="#4b525b")
wheels = car.wheel_specs(inset=0.27)
BELT, ROOF = 1.35, 2.16

K = [
    key(-2.62, 0.93, 0.42, 2.12, zsh=1.95, wt=0.90, wb=0.88, zl=0.52, zc=2.14),
    key(-2.54, 0.97, 0.30, 2.20, zsh=2.05, wt=0.93, zc=2.22),
    key(0.34, 0.97, 0.30, 2.20, zsh=2.05, wt=0.93, zc=2.22),
    key(0.35, 0.97, 0.30, BELT, zsh=1.26, wt=0.94, zc=BELT + 0.005),
    key(1.90, 0.97, 0.30, BELT, zsh=1.26, wt=0.94, zc=BELT + 0.005),
    key(2.20, 0.965, 0.32, 1.22, zsh=1.12, wt=0.88, zc=1.25),
    key(2.41, 0.95, 0.38, 1.10, zsh=1.00, wt=0.84, zc=1.14),
    key(2.51, 0.90, 0.48, 0.99, zsh=0.89, wt=0.80, wb=0.80, zl=0.58, zc=1.01),
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


mb = MB("body")
build_section(mb, stations(K, wheels, -2.62, 0.34), "tub", mat_fn, cap0="Paint", cap1="Interior")
build_section(mb, stations(K, wheels, 0.35, 1.90), "ch", mat_fn, cap0="Trim", cap1="Trim", floor=0.80, wall=0.08)
build_section(mb, stations(K, wheels, 1.90, 2.51), "tub", mat_fn, cap0="Interior", cap1="Trim")

# ---- cab greenhouse ------------------------------------------------------------------------------------------------
A, B, C, D = (1.90, BELT), (1.44, ROOF), (0.42, ROOF), (0.36, BELT)
G = [A, B, C, D]
WGB, WGR = 0.92, 0.84


def gx(z):
    return lerp(WGB, WGR, clamp((z - BELT) / (ROOF - BELT), 0, 1))


shell_yz(mb, G, gx, ["Glass", "Paint2", "Glass", "Interior"], "Glass")
mb.block((0, 0.93), ROOF - 0.005, ROOF + 0.045, (2 * WGR + 0.12, 1.12), (2 * WGR + 0.05, 1.04), "Paint")
wipers(mb, A, B, gx, spans=((-0.70, -0.14), (0.02, 0.58)), t=0.10)
W1 = clip_poly(G, lo=0.93)
W2 = clip_poly(G, hi=0.87)
PB = clip_poly(G, lo=0.87, hi=0.93)
for s in (1, -1):
    frame_slab(mb, W2, gx, s, 0.05, 0.014, 0.002, "Trim")
    flat_slab(mb, PB, gx, s, 0.014, 0.002, "Paint2")

# ---- panel lines ----------------------------------------------------------------------------------------------------------
for s in (1, -1):
    x = s * (WS + 0.002)
    seam_h(mb, x, -2.50, 0.30, 1.02, h=0.016)                               # beltline crease
    flat_slab(mb, bevel_rect(-1.22, 0.30, 0.30, 0.54, 0.03, 0.005), lambda z: WS, s, 0.02, 0.0, "Paint2")   # lower cladding
    mb.box((s * (WS - 0.01), 1.07, 0.38), (0.12, 0.30, 0.04), "MetalDark")  # cab step
# sliding door (right side)
x = WS + 0.002
seam_v(mb, x, 0.22, 0.42, 2.08)
seam_v(mb, x, -1.20, 0.42, 2.08)
seam_h(mb, x, -1.20, 0.22, 2.08)
seam_h(mb, x, -1.20, 0.22, 0.43)
seam_h(mb, x, -2.30, 0.22, 1.26, mat="MetalDark", h=0.03)                 # slide rail
mb.box((WS + 0.014, -1.04, 1.06), (0.03, 0.14, 0.03), "Chrome")             # slide door handle
mb.box((WS - 0.005, 0.02, 0.37), (0.10, 0.35, 0.04), "MetalDark")           # slide step
# fuel flap (left)
mb.box((-WS - 0.006, -1.45, 1.20), (0.012, 0.16, 0.18), "Trim")
# rear double doors
for xx in (-0.001, ):
    mb.box((0, -2.625, 1.32), (0.012, 0.01, 1.72), "Trim")
for z in (0.50, 2.12):
    mb.box((0, -2.625, z), (1.78, 0.01, 0.012), "Trim")
for s in (1, -1):
    mb.box((s * 0.90, -2.625, 1.32), (0.012, 0.01, 1.62), "Trim")
    for z in (0.80, 1.85):
        mb.box((s * 0.88, -2.632, z), (0.05, 0.02, 0.10), "Chrome")             # hinges
mb.box((0.10, -2.636, 1.22), (0.05, 0.03, 0.20), "Chrome")                    # handle
mb.box((-0.10, -2.634, 1.22), (0.03, 0.02, 0.12), "Trim")
for s in (1, -1):
    mb.box((s * 0.88, -2.61, 0.95), (0.10, 0.07, 0.52), "LightTail")                    # tail lights
    mb.box((s * 0.65, -2.63, 0.38), (0.12, 0.05, 0.06), "LightAmber")
# sliding door window (right) + rear door windows
flat_window(mb, [(-0.95, 1.38), (-0.12, 1.38), (-0.12, 1.98), (-0.95, 1.98)], WS, 1, 0.045)
for sx in (-1, 1):
    mb.box((sx * 0.45, -2.622, 1.68), (0.60, 0.01, 0.46), "Trim")
    mb.box((sx * 0.45, -2.628, 1.68), (0.50, 0.01, 0.36), "Interior")
    mb.box((sx * 0.45, -2.634, 1.68), (0.50, 0.008, 0.36), "Glass")
# hood seams
for s in (1, -1):
    mb.beam((s * 0.56, 1.95, top_z(1.95, 0.56) + 0.004), (s * 0.56, 2.45, top_z(2.45, 0.56) + 0.004), 0.007, 0.007, 4, "Trim")
mb.beam((-0.56, 1.95, top_z(1.95, 0.56) + 0.004), (0.56, 1.95, top_z(1.95, 0.56) + 0.004), 0.007, 0.007, 4, "Trim")
# roof vent
mb.block((0, -0.90), 2.22, 2.25, (0.72, 0.58), (0.60, 0.44), "Trim")
mb.block((0, -0.90), 2.24, 2.25, (0.56, 0.40), (0.50, 0.34), "MetalDark")

# ---- interior ---------------------------------------------------------------------------------------------------------
FZ = 0.80
mb.block((0, 1.74), 0.86, 1.28, (1.80, 0.34), (1.80, 0.26), "Interior", top_shift=(0.03, 0))
mb.box((0, 1.64, 1.18), (1.50, 0.06, 0.05), "Trim")
mb.box((0, 1.30, 0.98), (0.30, 0.50, 0.24), "Interior")
steering_wheel(mb, (-0.40, 1.50, 1.36), 38, 0.20, "Trim", "Interior")
for sx in (-0.40, 0.40):
    seat(mb, sx, 1.12, FZ, 0.54, 0.52, 0.66, 0.22, "Interior")
seat(mb, -0.36, 0.60, FZ, 0.54, 0.50, 0.62, 0.22, "Interior")                      # extra seat (rear)
mb.box((0.35, 0.60, FZ + 0.18), (0.60, 0.50, 0.20), "Interior")                      # fold-up bench stub

# ---- front end ----------------------------------------------------------------------------------------------------------
bump_f = [(-0.94, 2.24), (0.94, 2.24), (0.99, 2.36), (0.96, 2.46), (0.82, 2.52), (-0.82, 2.52), (-0.96, 2.46), (-0.99, 2.36)]
mb.prism(bump_f, 0.34, 0.62, "Trim")
mb.box((0, 2.495, 0.80), (0.96, 0.06, 0.26), "Trim")
mb.box((0, 2.528, 0.80), (1.00, 0.02, 0.30), "Chrome")
mb.box((0, 2.535, 0.80), (0.88, 0.02, 0.22), "Trim")
for i in range(3):
    mb.box((0, 2.545, 0.73 + i * 0.07), (0.86, 0.012, 0.02), "Chrome")
for s in (1, -1):
    mb.box((s * 0.74, 2.43, 0.84), (0.30, 0.11, 0.17), "LightHead")
    mb.box((s * 0.74, 2.415, 0.95), (0.34, 0.12, 0.03), "Trim")
    mb.box((s * 0.84, 2.465, 0.55), (0.14, 0.08, 0.07), "LightAmber")
# rear bumper
bump_r = [(-0.94, -2.50), (0.94, -2.50), (0.99, -2.55), (0.96, -2.60), (0.82, -2.64), (-0.82, -2.64), (-0.96, -2.60), (-0.99, -2.55)]
mb.prism(bump_r, 0.34, 0.60, "Trim")
mb.box((0, -2.646, 0.47), (0.52, 0.012, 0.12), "Plate")
for s in (1, -1):
    mb.cyl((s * 0.62, -2.57, 0.28), 0.04, 0.10, 8, "Chrome", axis="Y")

body = car.mesh(mb, "Body")
island_report(body)

# ---- doors --------------------------------------------------------------------------------------------------------------
YH = 1.88


def arch_door_poly(y_rear, y_front, z0, z1, yw, zc, R, mg=0.035, c=0.012):
    pts = [(y_rear + 0.03, z0), (yw - R - 0.02, z0)]
    n = 8
    for i in range(n + 1):
        y = lerp(yw - R, y_front, i / n)
        dy = y - yw
        z = zc + math.sqrt(max(R * R - dy * dy, 0.0)) + mg
        pts.append((y, max(z, z0)))
    pts += [(y_front, z1 - c), (y_front - c, z1), (y_rear + c, z1), (y_rear, z1 - c), (y_rear, z0 + 0.03)]
    return pts


for s, nm in ((-1, "DoorL"), (1, "DoorR")):
    dm = MB("door")
    flat_slab(dm, arch_door_poly(0.93, YH, 0.40, 1.345, 1.65, 0.34, 0.41), lambda z: WS, s, 0.035, -0.018, "Paint")
    frame_slab(dm, W1, gx, s, 0.05, 0.014, 0.002, "Trim")
    dm.box((s * (WS + 0.034), 1.00, 1.14), (0.03, 0.13, 0.025), "Chrome")
    dm.beam((s * (WS + 0.005), 1.74, 1.40), (s * (WS + 0.03), 1.72, 1.52), 0.014, 0.014, 4, "Trim")
    dm.block((s * (WS + 0.032), 1.70), 1.38, 1.70, (0.045, 0.15), (0.04, 0.13), "Trim", top_shift=(0, 0.01))
    dm.translate((-s * WS, -YH, -0.40))
    car.mesh(dm, nm, loc=(s * WS, YH, 0.40))

car.wheels(rim="Rim", ws_front=WS, ws_rear=WS)
car.anchors(head=(0.74, 2.46, 0.84), tail=(0.88, -2.61, 0.95), seat_y=1.12, seat_z=1.20, rear_y=0.60, exit_y=1.40, exit_x=2.05, exhaust=(-0.62, -2.60, 0.28))
bpy.data.objects.remove(car.objs.pop("SeatRearR"), do_unlink=True)    # van: three seats only (driver, passenger, one extra)
build_lod(car, K, -2.62, 2.51, G, gx, mat_fn=mat_fn, boxes=[
    ((0.74, 2.43, 0.84), (0.30, 0.11, 0.17), "LightHead"), ((-0.74, 2.43, 0.84), (0.30, 0.11, 0.17), "LightHead"),
    ((0.88, -2.61, 0.95), (0.10, 0.07, 0.52), "LightTail"), ((-0.88, -2.61, 0.95), (0.10, 0.07, 0.52), "LightTail")])
car.mats()
print("tris:", tri_total(car.root))
