"""animals_canines.py - dog (shepherd type, 0.62 m at the shoulder) and coyote (0.58 m, lean, bushy tail). Idempotent.
Hierarchy: Body, Head > (Ear_L, Ear_R, Jaw), Leg_FL/FR/BL/BR, Tail.  Head pivot = neck base on the shoulders.   ONLY=['dog'] to build one.
"""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\animals_lib.py", encoding="utf8").read(), globals())

DOG_COLS = dict(AnimalFur=("#b98a4e", 0.9), AnimalBelly=("#dcc596", 0.9), AnimalDark=("#2a2522", 0.9), Hoof=("#2a2522", 0.7),
                Accent=("#d98f86", 0.7), Antler=("#efe9d8", 0.6))
COY_COLS = dict(AnimalFur=("#a58d6e", 0.92), AnimalBelly=("#e2d7bf", 0.9), AnimalDark=("#3d342c", 0.9), Hoof=("#2a2522", 0.7),
                Accent=("#1b1814", 0.7), Antler=("#efe9d8", 0.6))


def build_canine(kind="dog", slot=2):
    dog = kind == "dog"
    A = Animal(kind, slot, kind, **(DOG_COLS if dog else COY_COLS))
    F, BEL, DK, HF, AC = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("Hoof"), A.m("Accent")
    if dog:
        rings = [ring_xz(-0.38, 0.075, 0.50, 0.37), ring_xz(-0.29, 0.12, 0.56, 0.31), ring_xz(-0.08, 0.108, 0.56, 0.27),
                 ring_xz(0.10, 0.135, 0.60, 0.21), ring_xz(0.26, 0.14, 0.63, 0.23), ring_xz(0.38, 0.105, 0.58, 0.33)]
    else:
        rings = [ring_xz(-0.42, 0.065, 0.49, 0.38), ring_xz(-0.32, 0.10, 0.55, 0.33), ring_xz(-0.09, 0.09, 0.54, 0.29),
                 ring_xz(0.12, 0.11, 0.58, 0.23), ring_xz(0.29, 0.115, 0.61, 0.25), ring_xz(0.41, 0.085, 0.56, 0.34)]
    b = MB(kind + "_body")
    skin(b, rings, belly_fn(F, BEL, belly_idx=(5, 4, 6), dark=DK, dark_idx=(0, 1, 2) if dog else (1,), dark_k=(2, 3, 4) if dog else (1, 2, 3, 4)),
         cap0=F, cap1=F)
    A.part(b, "Body")

    # ---------------- Head (neck included), pivot at neck base ----------------
    if dog:
        N = Vector((0, 0.34, 0.52))
        S = Vector((0, 0.52, 0.67))
        dm = dirv(-20)
        pts = [(0, 0.30, 0.46), (0, 0.42, 0.58), tuple(S), tuple(S + dm * 0.09), tuple(S + dm * 0.18), tuple(S + dm * 0.255)]
        rr = [(0.10, 0.11), (0.09, 0.10), (0.078, 0.082), (0.066, 0.068), (0.046, 0.048), (0.038, 0.039)]
        mt = [F, F, F, DK, DK]
        ear_off, ear_tip, ear_w = Vector((0.054, -0.03, 0.062)), (0.03, -0.05, 0.175), 0.054
        jdz, jl = (0.0, 0.024, 0.030), 0.19
        jr = [(0.044, 0.022), (0.034, 0.018), (0.024, 0.013)]
    else:
        N = Vector((0, 0.36, 0.52))
        S = Vector((0, 0.56, 0.645))
        dm = dirv(-17)
        pts = [(0, 0.31, 0.46), (0, 0.44, 0.565), tuple(S), tuple(S + dm * 0.11), tuple(S + dm * 0.22), tuple(S + dm * 0.315)]
        rr = [(0.084, 0.100), (0.078, 0.094), (0.068, 0.074), (0.052, 0.058), (0.036, 0.040), (0.028, 0.030)]
        mt = [F, F, F, F, DK]
        ear_off, ear_tip, ear_w = Vector((0.050, -0.035, 0.052)), (0.034, -0.035, 0.150), 0.062
        jdz, jl = (0.0, 0.026, 0.034), 0.27
        jr = [(0.038, 0.021), (0.028, 0.017), (0.018, 0.012)]
    rr = [(a * 1.12, c * 1.12) for a, c in rr]
    b = MB(kind + "_head")
    limb(b, pts, rr, sides=6, mats=mt, cap0=True, cap1=True, rot=math.pi / 6)
    for sx in (1, -1):
        e = S + dm * 0.07 + Vector((sx * (0.060 if dog else 0.050), 0, 0.022))
        eye(b, e, (sx, 0.45, 0.2), r=0.014 if dog else 0.012)
    A.part(b, "Head", pivot=tuple(N))
    for sx, nm in ((1, "Ear_R"), (-1, "Ear_L")):
        E = S + Vector((ear_off.x * sx, ear_off.y, ear_off.z))
        tip = (E.x + ear_tip[0] * sx, E.y + ear_tip[1], E.z + ear_tip[2])
        b = MB(kind + "_" + nm)
        if dog:
            limb(b, [tuple(E), tip], [(ear_w, 0.012), 0.0], sides=4, mats=DK, cap0=True, cap1=False, rot=0.0, hint=(1, 0, 0))
        else:  # coyote: broad tan ear with a dark tip (reads as an ear, not a horn)
            mid = (E.x + ear_tip[0] * sx * 0.55, E.y + ear_tip[1] * 0.55, E.z + ear_tip[2] * 0.55)
            limb(b, [tuple(E), mid, tip], [(ear_w, 0.013), (ear_w * 0.62, 0.010), 0.0], sides=4, mats=[F, DK], cap0=True, cap1=False,
                 rot=0.0, hint=(1, 0, 0))
        A.part(b, nm, pivot=tuple(E), parent="Head")
    # lower jaw, hinge under the skull
    J = S + Vector((0, -0.01, -0.05))
    b = MB(kind + "_jaw")
    jp = [tuple(J + dm * (jl * f) + Vector((0, 0, -jdz[k]))) for k, f in enumerate((0.0, 0.5, 1.0))]
    limb(b, jp, jr, sides=4, mats=[BEL, DK], cap0=True, cap1=True, rot=math.pi / 4)
    A.part(b, "Jaw", pivot=tuple(J), parent="Head")

    # ---------------- Legs ----------------
    if dog:
        fore = [(0.090, 0.27, 0.50), (0.086, 0.255, 0.30), (0.080, 0.270, 0.10), (0.080, 0.28, 0.035), (0.080, 0.305, 0.012)]
        fore_r = [(0.058, 0.075), (0.044, 0.056), (0.030, 0.038), (0.031, 0.038), (0.035, 0.052)]
        hind = [(0.092, -0.27, 0.47), (0.098, -0.19, 0.28), (0.082, -0.31, 0.15), (0.082, -0.30, 0.04), (0.082, -0.27, 0.012)]
        hind_r = [(0.070, 0.096), (0.050, 0.066), (0.032, 0.042), (0.030, 0.036), (0.034, 0.050)]
    else:
        fore = [(0.078, 0.29, 0.50), (0.074, 0.28, 0.31), (0.070, 0.295, 0.11), (0.070, 0.305, 0.035), (0.070, 0.325, 0.012)]
        fore_r = [(0.046, 0.062), (0.035, 0.046), (0.023, 0.030), (0.024, 0.030), (0.028, 0.042)]
        hind = [(0.082, -0.29, 0.46), (0.088, -0.20, 0.29), (0.072, -0.34, 0.16), (0.072, -0.33, 0.04), (0.072, -0.30, 0.012)]
        hind_r = [(0.058, 0.082), (0.042, 0.056), (0.026, 0.036), (0.024, 0.030), (0.028, 0.042)]
    make_legs(A, fore, fore_r, hind, hind_r, [F, F, F, DK] if dog else [F, F, DK, DK])

    # ---------------- Tail ----------------
    if dog:
        tp = [(0, -0.37, 0.50), (0, -0.47, 0.44), (0, -0.55, 0.31), (0, -0.57, 0.16)]
        tr = [(0.03, 0.03), (0.050, 0.054), (0.052, 0.056), 0.0]
    else:
        tp = [(0, -0.41, 0.49), (0, -0.51, 0.44), (0, -0.57, 0.31), (0, -0.585, 0.15)]
        tr = [(0.03, 0.03), (0.050, 0.056), (0.052, 0.058), 0.0]
    b = MB(kind + "_tail")
    limb(b, tp, tr, sides=5, mats=[F, F, DK], cap0=True, cap1=False)
    A.part(b, "Tail", pivot=tp[0])
    return A


def run(only=None):
    out = {}
    for kind, slot in (("dog", 2), ("coyote", 6)):
        if only and kind not in only:
            continue
        A = build_canine(kind, slot)
        A.report(600)
        out[kind] = A
    return out


run(globals().get("ONLY"))
