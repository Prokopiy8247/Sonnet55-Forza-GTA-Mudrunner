"""animals_farm.py - boar (0.72 m at the shoulder, tusks), cow (1.4 m, black/white spots, horns) and horse (2.2 m long, 1.4 m shoulder; built at scale 0.85). Idempotent.
ONLY=['boar'] to build a subset.   Hierarchy: Body, [Neck >] Head > (Ear_L, Ear_R), Leg_FL/FR/BL/BR, Tail.
"""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\animals_lib.py", encoding="utf8").read(), globals())

BOAR_COLS = dict(AnimalFur=("#665240", 0.95), AnimalBelly=("#85705c", 0.95), AnimalDark=("#2c231c", 0.95), Hoof=("#1c1714", 0.7),
                 Accent=("#a07f75", 0.7), Antler=("#efe6cf", 0.6))
COW_COLS = dict(AnimalFur=("#eeeae0", 0.95), AnimalBelly=("#e8d3c8", 0.95), AnimalDark=("#211f22", 0.95), Hoof=("#2d2724", 0.7),
                Accent=("#dca59d", 0.7), Antler=("#e7dcbc", 0.7))
HORSE_COLS = dict(AnimalFur=("#8d4f2c", 0.9), AnimalBelly=("#a2623a", 0.9), AnimalDark=("#2a1b14", 0.9), Hoof=("#2a2320", 0.7),
                  Accent=("#3a2a22", 0.7), Antler=("#efe6cf", 0.6))


def build_boar(slot=4):
    A = Animal("boar", slot, "boar", sc=0.92, **BOAR_COLS)
    F, BEL, DK, HF, AC, TUSK = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("Hoof"), A.m("Accent"), A.m("Antler")
    rings = [ring_xz(-0.54, 0.11, 0.54, 0.37), ring_xz(-0.42, 0.19, 0.62, 0.31), ring_xz(-0.12, 0.225, 0.69, 0.27),
             ring_xz(0.18, 0.26, 0.78, 0.26), ring_xz(0.38, 0.23, 0.75, 0.30), ring_xz(0.54, 0.17, 0.62, 0.36)]
    b = MB("boar_body")
    skin(b, rings, belly_fn(F, BEL, belly_idx=(5,), dark=DK, dark_idx=(1,), dark_k=(1, 2, 3, 4)), cap0=F, cap1=F)
    A.part(b, "Body")

    N = Vector((0, 0.50, 0.52))
    S = Vector((0, 0.74, 0.59))
    d = dirv(-30)
    pts = [(0, 0.46, 0.56), tuple(S), tuple(S + d * 0.18), tuple(S + d * 0.35)]
    rr = [(a * 1.1, c * 1.1) for a, c in [(0.15, 0.17), (0.14, 0.15), (0.095, 0.095), (0.075, 0.07)]]
    b = MB("boar_head")
    limb(b, pts, rr, sides=6, mats=[F, F, AC], cap0=True, cap1=True, rot=math.pi / 6)
    for sx in (1, -1):
        eye(b, S + d * 0.06 + Vector((sx * 0.125, 0, 0.04)), (sx, 0.4, 0.2), r=0.016)
        tb = S + d * 0.25 + Vector((sx * 0.062, 0.0, -0.045))
        limb(b, [tuple(tb), tuple(tb + Vector((sx * 0.025, 0.05, 0.065))), tuple(tb + Vector((sx * 0.015, 0.075, 0.135)))],
             [0.020, 0.014, 0.0], sides=4, mats=TUSK, cap0=False, cap1=False, rot=math.pi / 4)
    A.part(b, "Head", pivot=tuple(N))
    for sx, nm in ((1, "Ear_R"), (-1, "Ear_L")):
        E = S + Vector((sx * 0.085, -0.075, 0.13))
        tip = (E.x + 0.045 * sx, E.y - 0.045, E.z + 0.085)
        b = MB("boar_" + nm)
        limb(b, [tuple(E), tip], [(0.050, 0.012), 0.0], sides=4, mats=DK, cap0=True, cap1=False, hint=(1, 0.2, 0))
        A.part(b, nm, pivot=tuple(E), parent="Head")

    fore = [(0.150, 0.34, 0.50), (0.140, 0.35, 0.29), (0.125, 0.36, 0.10), (0.125, 0.375, 0.012)]
    fore_r = [(0.082, 0.098), (0.056, 0.068), (0.040, 0.048), (0.046, 0.062)]
    hind = [(0.160, -0.40, 0.52), (0.150, -0.33, 0.30), (0.130, -0.43, 0.12), (0.130, -0.41, 0.012)]
    hind_r = [(0.090, 0.115), (0.060, 0.075), (0.040, 0.050), (0.046, 0.062)]
    make_legs(A, fore, fore_r, hind, hind_r, [F, F, HF], sides=5)

    tp = [(0, -0.58, 0.60), (0, -0.67, 0.58), (0, -0.71, 0.48)]
    b = MB("boar_tail")
    limb(b, tp, [(0.022, 0.022), (0.015, 0.015), (0.03, 0.03)], sides=4, mats=[F, DK], cap0=True, cap1=True, rot=math.pi / 4)
    A.part(b, "Tail", pivot=tp[0])
    return A


def build_cow(slot=5):
    A = Animal("cow", slot, "cow", **COW_COLS)
    F, BEL, DK, HF, AC, HORN = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("Hoof"), A.m("Accent"), A.m("Antler")
    rings = [ring_xz(-0.98, 0.17, 1.27, 0.80), ring_xz(-0.82, 0.30, 1.38, 0.66), ring_xz(-0.50, 0.33, 1.35, 0.58), ring_xz(-0.15, 0.335, 1.33, 0.55),
             ring_xz(0.20, 0.34, 1.35, 0.55), ring_xz(0.55, 0.32, 1.40, 0.62), ring_xz(0.80, 0.26, 1.36, 0.72), ring_xz(0.96, 0.19, 1.28, 0.80)]
    seeds = [(1, 1), (2, 3), (3, 0), (4, 2), (5, 1), (3, 6), (6, 2), (2, 7)]
    rnd = random.Random(11)
    spots = set()
    for (k, i) in seeds:
        spots.add((k, i))
        cur = (k, i)
        for _ in range(2):
            nk, ni = (cur[0] + rnd.choice((-1, 0, 0, 1)), (cur[1] + rnd.choice((-1, 0, 1))) % 8)
            if 0 <= nk <= 6 and ni not in (5,):
                spots.add((nk, ni))
                cur = (nk, ni)
    def cmat(k, i):
        if (k, i) in spots:
            return DK
        return BEL if i in (5,) else F
    b = MB("cow_body")
    skin(b, rings, cmat, cap0=F, cap1=F)
    # udder
    b.block((0, -0.42), 0.44, 0.60, (0.17, 0.22), (0.12, 0.16), AC)
    A.part(b, "Body")

    N = Vector((0, 0.82, 1.22))
    S = Vector((0, 1.30, 1.22))
    d = dirv(-58)
    pts = [(0, 0.76, 1.20), (0, 1.04, 1.30), tuple(S), tuple(S + d * 0.22), tuple(S + d * 0.40)]
    rr = [(0.23, 0.27), (0.18, 0.21), (0.135, 0.165), (0.112, 0.125), (0.100, 0.092)]
    b = MB("cow_head")
    limb(b, pts, rr, sides=6, mats=[F, F, DK, AC] if False else [F, F, F, AC], cap0=True, cap1=True, rot=math.pi / 6)
    for sx in (1, -1):
        eye(b, S + d * 0.05 + Vector((sx * 0.125, 0, 0.05)), (sx, 0.4, 0.2), r=0.022)
        hb = S + Vector((sx * 0.09, -0.07, 0.12))
        limb(b, [tuple(hb), tuple(hb + Vector((sx * 0.07, -0.02, 0.06))), tuple(hb + Vector((sx * 0.10, 0.0, 0.17)))],
             [0.034, 0.026, 0.0], sides=4, mats=[HORN, HORN], cap0=True, cap1=False, rot=math.pi / 4)
    A.part(b, "Head", pivot=tuple(N))
    for sx, nm in ((1, "Ear_R"), (-1, "Ear_L")):
        E = S + Vector((sx * 0.125, -0.06, 0.07))
        tip = (E.x + 0.20 * sx, E.y - 0.02, E.z - 0.03)
        b = MB("cow_" + nm)
        limb(b, [tuple(E), tip], [(0.050, 0.014), 0.0], sides=4, mats=DK, cap0=True, cap1=False, hint=(0, 1, 0))
        A.part(b, nm, pivot=tuple(E), parent="Head")

    fore = [(0.205, 0.62, 1.02), (0.195, 0.63, 0.66), (0.170, 0.64, 0.32), (0.170, 0.65, 0.10), (0.170, 0.665, 0.012)]
    fore_r = [(0.115, 0.145), (0.082, 0.098), (0.062, 0.072), (0.056, 0.064), (0.064, 0.082)]
    hind = [(0.225, -0.76, 1.06), (0.225, -0.62, 0.72), (0.200, -0.82, 0.44), (0.190, -0.78, 0.11), (0.190, -0.76, 0.012)]
    hind_r = [(0.145, 0.18), (0.100, 0.125), (0.064, 0.074), (0.056, 0.064), (0.064, 0.082)]
    make_legs(A, fore, fore_r, hind, hind_r, [F, F, F, HF], sides=5)

    tp = [(0, -0.97, 1.28), (0, -1.03, 1.00), (0, -1.05, 0.62), (0, -1.05, 0.48), (0, -1.05, 0.30)]
    b = MB("cow_tail")
    limb(b, tp, [(0.03, 0.03), (0.024, 0.024), (0.02, 0.02), (0.05, 0.05), 0.0], sides=4, mats=[F, F, DK, DK], cap0=True, cap1=False, rot=math.pi / 4)
    A.part(b, "Tail", pivot=tp[0])
    return A


def build_horse(slot=12):
    A = Animal("horse", slot, "horse", sc=0.85, **HORSE_COLS)
    F, BEL, DK, HF, AC = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("Hoof"), A.m("Accent")
    rings = [ring_xz(-0.80, 0.18, 1.44, 0.97), ring_xz(-0.64, 0.275, 1.54, 0.87), ring_xz(-0.22, 0.25, 1.52, 0.78),
             ring_xz(0.24, 0.265, 1.55, 0.74), ring_xz(0.60, 0.255, 1.60, 0.80), ring_xz(0.84, 0.19, 1.52, 0.93)]
    b = MB("horse_body")
    skin(b, rings, belly_fn(F, BEL, belly_idx=(5,)), cap0=F, cap1=F)
    A.part(b, "Body")

    N0 = Vector((0, 0.66, 1.47))
    N1 = Vector((0, 1.10, 2.00))
    b = MB("horse_neck")
    limb(b, [(0, 0.55, 1.40), (0, 0.86, 1.74), tuple(N1)], [(0.20, 0.26), (0.145, 0.20), (0.105, 0.14)], sides=6, mats=[F, F], cap0=False, cap1=True, rot=math.pi / 6)
    # mane: dark crest ribbon along the top of the neck
    limb(b, [(0, 0.52, 1.60), (0, 0.80, 1.88), (0, 1.00, 2.10), (0, 1.08, 2.12)], [(0.02, 0.06), (0.024, 0.10), (0.022, 0.10), (0.012, 0.06)],
         sides=4, mats=DK, cap0=True, cap1=True, rot=0.0, hint=(1, 0, 0))
    A.part(b, "Neck", pivot=tuple(N0))
    d = dirv(-48)
    b = MB("horse_head")
    sv = [(-0.08, 0.105, 0.14), (0.10, 0.125, 0.18), (0.32, 0.085, 0.118), (0.55, 0.072, 0.085)]
    limb(b, [tuple(N1 + d * s) for s, _, _ in sv], [(a, c) for _, a, c in sv], sides=6, mats=[F, F, AC], cap0=True, cap1=True, rot=math.pi / 6)
    for sx in (1, -1):
        eye(b, N1 + d * 0.12 + Vector((sx * 0.095, 0, 0.05)), (sx, 0.35, 0.2), r=0.02)
    A.part(b, "Head", pivot=tuple(N1), parent="Neck")
    for sx, nm in ((1, "Ear_R"), (-1, "Ear_L")):
        E = N1 + Vector((sx * 0.055, -0.05, 0.10))
        tip = (E.x + 0.015 * sx, E.y - 0.01, E.z + 0.17)
        b = MB("horse_" + nm)
        limb(b, [tuple(E), tip], [(0.032, 0.012), 0.0], sides=4, mats=F, cap0=True, cap1=False, hint=(1, 0, 0))
        A.part(b, nm, pivot=tuple(E), parent="Head")

    fore = [(0.175, 0.60, 1.32), (0.165, 0.62, 0.96), (0.150, 0.64, 0.52), (0.150, 0.63, 0.12), (0.150, 0.65, 0.012)]
    fore_r = [(0.115, 0.145), (0.078, 0.10), (0.052, 0.070), (0.040, 0.050), (0.052, 0.072)]
    hind = [(0.180, -0.62, 1.30), (0.175, -0.46, 0.96), (0.150, -0.76, 0.58), (0.145, -0.72, 0.12), (0.145, -0.70, 0.012)]
    hind_r = [(0.135, 0.17), (0.092, 0.115), (0.056, 0.074), (0.040, 0.050), (0.052, 0.072)]
    make_legs(A, fore, fore_r, hind, hind_r, [F, F, F, HF], sides=5)

    tp = [(0, -0.80, 1.42), (0, -0.92, 1.30), (0, -0.98, 0.98), (0, -0.98, 0.62)]
    b = MB("horse_tail")
    limb(b, tp, [(0.06, 0.07), (0.10, 0.11), (0.095, 0.11), 0.0], sides=5, mats=DK, cap0=True, cap1=False)
    A.part(b, "Tail", pivot=tp[0])
    return A


def run(only=None):
    out = {}
    for aid, fn in (("boar", build_boar), ("cow", build_cow), ("horse", build_horse)):
        if only and aid not in only:
            continue
        A = fn()
        A.report(600)
        out[aid] = A
    return out


run(globals().get("ONLY"))
