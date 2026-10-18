"""animals_deer.py - deer (doe) + deer_buck (antlers). 1.4 m at the shoulder. Idempotent.
Run:  exec(open(r"...\\animals_deer.py", encoding="utf8").read(), globals())      # builds both; set ONLY=['deer'] first to build one.
Hierarchy:  Body, Neck > Head > (Ear_L, Ear_R, [Antlers]), Leg_FL/FR/BL/BR, Tail.   Origin = ground centre under the body middle.
"""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\animals_lib.py", encoding="utf8").read(), globals())

DEER_COLS = dict(AnimalFur=("#a56b45", 0.9), AnimalBelly=("#eadfc9", 0.9), AnimalDark=("#5a3a28", 0.9), Hoof=("#2a211b", 0.6),
                 Antler=("#dccba0", 0.75), Accent=("#2b1f1a", 0.5))


def build_deer(aid="deer", buck=False, slot=0):
    A = Animal(aid, slot, "deer", **DEER_COLS)
    F, BEL, DK, HF, ANT = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("Hoof"), A.m("Antler")

    # ---------------- Body (rump -> chest) ----------------
    rings = [
        ring_xz(-0.80, 0.12, 1.24, 0.97),
        ring_xz(-0.72, 0.17, 1.31, 0.92),
        ring_xz(-0.58, 0.215, 1.34, 0.84),
        ring_xz(-0.20, 0.19, 1.31, 0.76),
        ring_xz(0.20, 0.215, 1.36, 0.69),
        ring_xz(0.52, 0.22, 1.42, 0.70),
        ring_xz(0.80, 0.155, 1.37, 0.87),
    ]
    b = MB(aid + "_body")
    skin(b, rings, belly_fn(F, BEL, belly_idx=(5,), first=BEL, dark=DK, dark_idx=()), cap0=BEL, cap1=F)
    A.part(b, "Body")

    # ---------------- Neck (pivot at the withers) + Head (pivot at the poll) ----------------
    N0 = Vector((0, 0.60, 1.30))
    N1 = Vector((0, 1.02, 1.72))
    b = MB(aid + "_neck")
    limb(b, [(0, 0.52, 1.22), (0, 0.80, 1.50), tuple(N1)], [(0.125, 0.17), (0.095, 0.125), (0.075, 0.085)], sides=6, mats=[F, F],
         cap0=False, cap1=True, rot=math.pi / 6)
    A.part(b, "Neck", pivot=N0)

    d = dirv(-32)
    b = MB(aid + "_head")
    sv = [(-0.07, 0.072, 0.09), (0.07, 0.086, 0.098), (0.22, 0.060, 0.066), (0.35, 0.049, 0.054), (0.43, 0.044, 0.046)]
    pts = [tuple(N1 + d * s) for s, _, _ in sv]
    limb(b, pts, [(rx, ry) for _, rx, ry in sv], sides=6, mats=[F, F, F, DK], cap0=True, cap1=True, rot=math.pi / 6)
    for sx in (1, -1):
        e = N1 + d * 0.11 + Vector((sx * 0.072, 0, 0.026))
        eye(b, e, (sx, 0.35, 0.15), r=0.017)
    A.part(b, "Head", pivot=tuple(N1), parent="Neck")

    # ears: leaf shaped, pivot at the base on the skull
    for sx, nm in ((1, "Ear_R"), (-1, "Ear_L")):
        E = N1 + Vector((sx * 0.062, -0.03, 0.075))
        tip = (0.21, -0.02, 0.10)
        pts = [(0.0, 0.0, 0.0), (tip[0] * 0.5, tip[1] * 0.5 - 0.01, tip[2] * 0.5), tip]
        pts = [(E.x + p[0] * sx, E.y + p[1], E.z + p[2]) for p in pts]
        b = MB(aid + "_" + nm)
        limb(b, pts, [(0.030, 0.009), (0.060, 0.011), 0.0], sides=4, mats=[F, F], sx=1.0, cap0=True, cap1=False, rot=0.0, hint=(0.35, 0.9, 0.0))
        A.part(b, nm, pivot=tuple(E), parent="Head")

    # ---------------- Antlers (buck only), child of Head ----------------
    if buck:
        b = MB(aid + "_antlers")
        for sx in (1, -1):
            beam = [(0.045, 0.98, 1.80), (0.115, 0.92, 1.97), (0.20, 0.86, 2.14), (0.24, 0.91, 2.33), (0.21, 1.04, 2.48)]
            limb(b, beam, [0.020, 0.017, 0.014, 0.011, 0.0], sides=4, mats=ANT, sx=sx, cap0=True, cap1=False, rot=math.pi / 4)
            limb(b, [(0.065, 0.96, 1.86), (0.10, 1.12, 1.98)], [0.011, 0.0], sides=4, mats=ANT, sx=sx, cap0=False, cap1=False, rot=math.pi / 4)
            limb(b, [(0.16, 0.89, 2.05), (0.26, 1.00, 2.20)], [0.012, 0.0], sides=4, mats=ANT, sx=sx, cap0=False, cap1=False, rot=math.pi / 4)
            limb(b, [(0.225, 0.90, 2.27), (0.34, 0.86, 2.47)], [0.011, 0.0], sides=4, mats=ANT, sx=sx, cap0=False, cap1=False, rot=math.pi / 4)
        A.part(b, "Antlers", pivot=(0, 0.97, 1.80), parent="Head")

    # ---------------- Legs (pivot = shoulder / hip joint, inside the body) ----------------
    fore = [(0.150, 0.46, 1.14), (0.135, 0.48, 0.84), (0.125, 0.52, 0.44), (0.120, 0.50, 0.10), (0.120, 0.515, 0.012)]
    fore_r = [(0.09, 0.115), (0.058, 0.074), (0.040, 0.050), (0.033, 0.040), (0.040, 0.052)]
    hind = [(0.150, -0.60, 1.12), (0.130, -0.47, 0.84), (0.115, -0.70, 0.50), (0.112, -0.66, 0.10), (0.112, -0.65, 0.012)]
    hind_r = [(0.105, 0.14), (0.065, 0.085), (0.042, 0.055), (0.033, 0.040), (0.040, 0.052)]
    for nm, pts, rr, sx in (("Leg_FR", fore, fore_r, 1), ("Leg_FL", fore, fore_r, -1), ("Leg_BR", hind, hind_r, 1), ("Leg_BL", hind, hind_r, -1)):
        b = MB(aid + "_" + nm)
        limb(b, pts, rr, sides=5, mats=[F, F, DK, HF], sx=sx, cap0=True, cap1=True)
        A.part(b, nm, pivot=(pts[0][0] * sx, pts[0][1], pts[0][2]))

    # ---------------- Tail ----------------
    b = MB(aid + "_tail")
    limb(b, [(0, -0.77, 1.27), (0, -0.88, 1.24), (0, -0.95, 1.12)], [(0.05, 0.04), (0.042, 0.036), 0.0], sides=4, mats=[F, BEL], cap0=True, cap1=False, rot=math.pi / 4)
    A.part(b, "Tail", pivot=(0, -0.77, 1.27))
    return A


def run(only=None):
    out = {}
    for aid, buck, slot in (("deer", False, 0), ("deer_buck", True, 1)):
        if only and aid not in only:
            continue
        A = build_deer(aid, buck, slot)
        A.report(600)
        out[aid] = A
    return out


run(globals().get("ONLY"))
