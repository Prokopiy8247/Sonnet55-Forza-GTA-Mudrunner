"""lane1_taxi.py - builds vehicles/taxi (lane 1, index 4). 4.60 x 1.82 x 1.55 (+ roof sign), WB 2.78, wheel r 0.33. Idempotent; does not export.
Mid-size hatch/estate: long roof, near-vertical hatch glass, checker stripe along the doors, roof sign mesh TaxiSign (LampGlow)."""
WS = 0.875
car = Car("taxi", 4, wheelbase=2.78, wr=0.33, ww=0.24, ws=WS, paint="#f2cf3a", paint2="#15171a")
wheels = car.wheel_specs(inset=0.26)
BELT, ROOF = 0.96, 1.455

K = [
    key(-2.34, 0.80, 0.40, 0.98, zsh=0.88, wt=0.74, wb=0.74, zl=0.48, zc=0.99),
    key(-2.27, 0.865, 0.28, 0.98, zsh=0.88, wt=0.82, zc=0.99),
    key(-2.14, 0.875, 0.25, 0.98, zsh=0.88, wt=0.84, zc=0.80),
    key(-0.95, 0.875, 0.24, 0.98, zsh=0.88, wt=0.84, zc=0.80),
    key(-0.94, 0.875, 0.24, BELT, zsh=0.87, wt=0.845, zc=BELT + 0.005),
    key(0.85, 0.875, 0.24, BELT, zsh=0.87, wt=0.845, zc=BELT + 0.005),
    key(1.30, 0.875, 0.25, 0.91, zsh=0.81, wt=0.80, zc=0.935),
    key(1.95, 0.87, 0.26, 0.86, zsh=0.77, wt=0.78, zc=0.885),
    key(2.14, 0.83, 0.29, 0.80, zsh=0.71, wt=0.72, zc=0.82),
    key(2.24, 0.74, 0.34, 0.72, zsh=0.64, wt=0.64, wb=0.66, zl=0.43, zc=0.73),
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
        return "Interior" if -2.30 < ym < 0.85 else "Paint"
    return "Interior"


mb = MB("body")
build_section(mb, stations(K, wheels, -2.34, -0.95), "tub", mat_fn, cap0="Paint", cap1="Interior")
build_section(mb, stations(K, wheels, -0.94, 0.85), "ch", mat_fn, cap0="Trim", cap1="Trim", floor=0.28, wall=0.08)
build_section(mb, stations(K, wheels, 0.85, 2.24), "tub", mat_fn, cap0="Interior", cap1="Trim")

# ---- greenhouse --------------------------------------------------------------------------------------------------
A, B, C, D = (0.85, BELT), (0.30, ROOF), (-1.82, ROOF), (-2.25, BELT + 0.005)
G = [A, B, C, D]
WGB, WGR = 0.825, 0.70


def gx(z):
    return lerp(WGB, WGR, clamp((z - BELT) / (ROOF - BELT), 0, 1))


shell_yz(mb, G, gx, ["Glass", "Paint2", "Glass", "Interior"], "Glass")
mb.block((0, -0.75), ROOF - 0.005, ROOF + 0.045, (2 * WGR + 0.06, 2.20), (2 * WGR - 0.02, 2.08), "Paint")
wipers(mb, A, B, gx)
YB = -0.18
W2 = clip_poly(G, lo=-1.00, hi=YB - 0.03)
W3 = clip_poly(G, hi=-1.06)
PB = clip_poly(G, lo=YB - 0.03, hi=YB + 0.03)
PC = clip_poly(G, lo=-1.06, hi=-1.00)
W1 = clip_poly(G, lo=YB + 0.03)
for s in (1, -1):
    for w in (W2, W3):
        frame_slab(mb, w, gx, s, 0.045, 0.014, 0.002, "Trim")
    for p in (PB, PC):
        flat_slab(mb, p, gx, s, 0.014, 0.002, "Paint2")

# ---- panel lines, handles, checker -------------------------------------------------------------------------------
for s in (1, -1):
    x = s * (WS + 0.002)
    seam_v(mb, x, YB - 0.03, 0.27, 0.955)
    seam_v(mb, x, -0.99, 0.27, 0.955)
    seam_h(mb, x, -0.99, YB - 0.03, 0.272)
    mb.box((s * (WS + 0.014), -0.80, 0.86), (0.03, 0.13, 0.025), "Chrome")
CELL = 0.15
ROWS = ((0.615, 0.705), (0.705, 0.795))


def checker(buf, y_hi, y_lo, s, off, th):
    ncols = int(round((y_hi - y_lo) / CELL))
    for c in range(ncols):
        y1 = y_hi - c * CELL
        y0 = y1 - CELL
        for r, (z0, z1) in enumerate(ROWS):
            if (c + r) % 2 == 0:
                buf.box((s * (WS + off), (y0 + y1) / 2, (z0 + z1) / 2), (th, CELL, z1 - z0), "Paint2")


for s in (1, -1):
    checker(mb, YB - 0.03 - 0.0, -0.99, s, 0.004, 0.012)
for s in (1, -1):
    mb.beam((s * 0.56, 0.95, top_z(0.95, 0.56) + 0.004), (s * 0.56, 2.08, top_z(2.08, 0.56) + 0.004), 0.007, 0.007, 4, "Trim")
mb.beam((-0.56, 0.95, top_z(0.95, 0.56) + 0.004), (0.56, 0.95, top_z(0.95, 0.56) + 0.004), 0.007, 0.007, 4, "Trim")
# hatch seams / wiper
mb.beam((-0.70, -2.365, 0.50), (0.70, -2.365, 0.50), 0.007, 0.007, 4, "Trim")
mb.beam((0.0, -2.23, 1.18), (0.34, -2.23, 1.10), 0.008, 0.008, 4, "Trim")

# ---- interior ------------------------------------------------------------------------------------------------
FZ = 0.28
mb.block((0, 0.63), 0.30, 0.90, (1.56, 0.34), (1.56, 0.26), "Interior", top_shift=(0.03, 0))
mb.box((0, 0.50, 0.84), (1.20, 0.06, 0.05), "Trim")
mb.box((0, 0.25, 0.42), (0.24, 0.80, 0.22), "Interior")
mb.box((0.0, 0.50, 0.96), (0.22, 0.10, 0.10), "LampGlow")                         # fare meter glow
steering_wheel(mb, (-0.40, 0.38, 0.84), 24, 0.18, "Trim", "Interior")
for sx in (-0.40, 0.40):
    seat(mb, sx, 0.10, FZ, 0.50, 0.50, 0.60, 0.06, "Interior")
seat(mb, 0, -0.62, FZ, 1.30, 0.50, 0.56, 0.06, "Interior", head=False)
for sx in (-0.40, 0.0, 0.40):
    mb.box((sx, -0.80, FZ + 0.82), (0.18, 0.08, 0.14), "Interior")

# ---- front end ---------------------------------------------------------------------------------------------------
bump_f = [(-0.82, 1.92), (0.82, 1.92), (0.88, 2.06), (0.85, 2.17), (0.70, 2.25), (-0.70, 2.25), (-0.85, 2.17), (-0.88, 2.06)]
mb.prism(bump_f, 0.27, 0.52, "Trim")
mb.box((0, 2.215, 0.62), (0.80, 0.05, 0.14), "Trim")
mb.box((0, 2.235, 0.62), (0.84, 0.02, 0.17), "Chrome")
mb.box((0, 2.245, 0.62), (0.74, 0.02, 0.11), "Trim")
for s in (1, -1):
    mb.cyl((s * 0.64, 2.16, 0.68), 0.105, 0.16, 8, "LightHead", axis="Y")
    mb.cyl((s * 0.64, 2.12, 0.68), 0.125, 0.06, 8, "Chrome", axis="Y")
    mb.box((s * 0.80, 2.19, 0.54), (0.10, 0.09, 0.06), "LightAmber")

# ---- rear end ---------------------------------------------------------------------------------------------------------
bump_r = [(-0.82, -2.05), (0.82, -2.05), (0.88, -2.16), (0.85, -2.28), (0.72, -2.35), (-0.72, -2.35), (-0.85, -2.28), (-0.88, -2.16)]
mb.prism(bump_r, 0.27, 0.54, "Trim")
for s in (1, -1):
    mb.box((s * 0.74, -2.31, 0.80), (0.14, 0.07, 0.30), "LightTail")
    mb.cyl((s * 0.56, -2.30, 0.26), 0.035, 0.08, 8, "Chrome", axis="Y")
mb.box((0, -2.356, 0.48), (0.50, 0.012, 0.12), "Plate")

body = car.mesh(mb, "Body")
island_report(body)

# ---- doors ----------------------------------------------------------------------------------------------------------------
YH = 0.78
for s, nm in ((-1, "DoorL"), (1, "DoorR")):
    dm = MB("door")
    flat_slab(dm, bevel_rect(-0.15, YH, 0.27, 0.955, 0.035, 0.012), lambda z: WS, s, 0.035, -0.018, "Paint")
    checker(dm, YH, -0.15, s, 0.0225, 0.012)
    frame_slab(dm, W1, gx, s, 0.045, 0.014, 0.002, "Trim")
    dm.box((s * (WS + 0.034), -0.02, 0.86), (0.03, 0.13, 0.025), "Chrome")
    dm.beam((s * (WS + 0.005), 0.66, 0.98), (s * (WS + 0.03), 0.64, 1.01), 0.012, 0.012, 4, "Trim")
    dm.block((s * (WS + 0.032), 0.62), 0.98, 1.08, (0.05, 0.15), (0.045, 0.12), "Paint", top_shift=(0, 0.01))
    dm.translate((-s * WS, -YH, -0.27))
    car.mesh(dm, nm, loc=(s * WS, YH, 0.27))

# ---- roof sign -----------------------------------------------------------------------------------------------------------
sg = MB("sign")
sg.box((0, 0, 0.012), (0.62, 0.25, 0.024), "Trim")
sg.block((0, 0), 0.024, 0.15, (0.58, 0.21), (0.50, 0.17), "LampGlow")
sg.block((0, 0), 0.15, 0.162, (0.50, 0.17), (0.44, 0.14), "Trim")
for s in (1, -1):
    for i in range(4):                                       # dark letter slots on both faces
        x = -0.15 + i * 0.10
        sg.box((x, s * 0.1, 0.085), (0.045, 0.012, 0.07), "Trim")
car.mesh(sg, "TaxiSign", loc=(0, -0.60, ROOF + 0.045))

car.wheels(rim="Rim", ws_front=WS, ws_rear=WS)
car.anchors(head=(0.64, 2.20, 0.67), tail=(0.74, -2.32, 0.80), seat_y=0.10, seat_z=0.50, rear_y=-0.58, exit_y=0.31, exit_x=1.85, exhaust=(-0.56, -2.34, 0.26))
build_lod(car, K, -2.34, 2.24, G, gx, mat_fn=mat_fn, boxes=[
    ((0.64, 2.16, 0.68), (0.20, 0.16, 0.20), "LightHead"), ((-0.64, 2.16, 0.68), (0.20, 0.16, 0.20), "LightHead"),
    ((0.74, -2.31, 0.80), (0.14, 0.07, 0.30), "LightTail"), ((-0.74, -2.31, 0.80), (0.14, 0.07, 0.30), "LightTail"),
    ((0, -0.60, ROOF + 0.045 + 0.08), (0.58, 0.21, 0.13), "LampGlow")])
car.mats()
print("tris:", tri_total(car.root))
