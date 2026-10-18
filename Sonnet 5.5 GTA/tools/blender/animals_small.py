"""animals_small.py - cat (0.25 m at the shoulder) and rabbit (0.25 m body height, ears to 0.42). Idempotent.  ONLY=['cat'] to build one.
Hierarchy: Body, Head > (Ear_L, Ear_R), Leg_FL/FR/BL/BR, Tail.
"""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\animals_lib.py", encoding="utf8").read(), globals())

CAT_COLS = dict(AnimalFur=("#df8a3d", 0.9), AnimalBelly=("#f4e6cb", 0.9), AnimalDark=("#a85c27", 0.9), Hoof=("#f4e6cb", 0.9),
                Accent=("#ee9aa0", 0.7))
RAB_COLS = dict(AnimalFur=("#9d8872", 0.95), AnimalBelly=("#efe7d9", 0.95), AnimalDark=("#5d4b3d", 0.95), Hoof=("#efe7d9", 0.9),
                Accent=("#e9a6a4", 0.8))


def build_cat(slot=3):
    A = Animal("cat", slot, "cat", **CAT_COLS)
    F, BEL, DK, AC = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("Accent")
    rings = [ring_xz(-0.19, 0.040, 0.225, 0.155), ring_xz(-0.14, 0.064, 0.255, 0.115), ring_xz(-0.04, 0.058, 0.25, 0.10),
             ring_xz(0.06, 0.066, 0.265, 0.095), ring_xz(0.13, 0.068, 0.275, 0.105), ring_xz(0.19, 0.052, 0.245, 0.135)]
    b = MB("cat_body")
    skin(b, rings, belly_fn(F, BEL, belly_idx=(5,), dark=DK, dark_idx=(0, 1, 2), dark_k=(1, 3)), cap0=F, cap1=F)
    A.part(b, "Body")

    N = Vector((0, 0.16, 0.21))
    S = Vector((0, 0.235, 0.29))
    dm = dirv(-8)
    pts = [(0, 0.13, 0.19), tuple(S), tuple(S + dm * 0.06), tuple(S + dm * 0.10)]
    rr = [(0.066, 0.07), (0.066, 0.062), (0.049, 0.044), (0.022, 0.019)]
    b = MB("cat_head")
    limb(b, pts, rr, sides=6, mats=[F, F, AC], cap0=True, cap1=True, rot=math.pi / 6)
    for sx in (1, -1):
        eye(b, S + dm * 0.04 + Vector((sx * 0.046, 0, 0.012)), (sx, 0.5, 0.15), r=0.0125)
    A.part(b, "Head", pivot=tuple(N))
    for sx, nm in ((1, "Ear_R"), (-1, "Ear_L")):
        E = S + Vector((sx * 0.036, -0.014, 0.046))
        tip = (E.x + 0.014 * sx, E.y - 0.014, E.z + 0.080)
        b = MB("cat_" + nm)
        limb(b, [tuple(E), tip], [(0.038, 0.009), 0.0], sides=4, mats=F, cap0=True, cap1=False, hint=(1, 0, 0))
        A.part(b, nm, pivot=tuple(E), parent="Head")

    fore = [(0.050, 0.125, 0.215), (0.048, 0.120, 0.105), (0.044, 0.128, 0.030), (0.044, 0.145, 0.008)]
    fore_r = [(0.036, 0.046), (0.024, 0.030), (0.021, 0.027), (0.026, 0.036)]
    hind = [(0.054, -0.125, 0.215), (0.062, -0.075, 0.125), (0.050, -0.150, 0.065), (0.048, -0.130, 0.008)]
    hind_r = [(0.046, 0.062), (0.030, 0.040), (0.021, 0.027), (0.026, 0.036)]
    make_legs(A, fore, fore_r, hind, hind_r, [F, F, BEL], sides=5)

    tp = [(0, -0.185, 0.195), (0, -0.28, 0.20), (0, -0.345, 0.275), (0, -0.35, 0.375), (0, -0.31, 0.445)]
    b = MB("cat_tail")
    limb(b, tp, [(0.022, 0.022), (0.022, 0.023), (0.020, 0.020), (0.018, 0.018), 0.0], sides=4, mats=[F, DK, F, DK], cap0=True, cap1=False, rot=math.pi / 4)
    A.part(b, "Tail", pivot=tp[0])
    return A


def build_rabbit(slot=7):
    A = Animal("rabbit", slot, "rabbit", **RAB_COLS)
    F, BEL, DK, AC = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("Accent")
    rings = [ring_xz(-0.20, 0.050, 0.185, 0.055), ring_xz(-0.12, 0.092, 0.255, 0.045), ring_xz(0.00, 0.088, 0.245, 0.045),
             ring_xz(0.10, 0.068, 0.215, 0.055), ring_xz(0.17, 0.048, 0.17, 0.075)]
    b = MB("rabbit_body")
    skin(b, rings, belly_fn(F, BEL, belly_idx=(4, 5, 6), dark=DK, dark_idx=(1,), dark_k=(1, 2)), cap0=F, cap1=F)
    A.part(b, "Body")

    N = Vector((0, 0.14, 0.15))
    S = Vector((0, 0.205, 0.195))
    dm = dirv(-18)
    pts = [(0, 0.12, 0.14), tuple(S), tuple(S + dm * 0.05), tuple(S + dm * 0.09)]
    rr = [(0.062, 0.070), (0.054, 0.058), (0.040, 0.040), (0.020, 0.019)]
    b = MB("rabbit_head")
    limb(b, pts, rr, sides=6, mats=[F, F, AC], cap0=True, cap1=True, rot=math.pi / 6)
    for sx in (1, -1):
        eye(b, S + dm * 0.03 + Vector((sx * 0.045, 0, 0.015)), (sx, 0.4, 0.2), r=0.0115)
    A.part(b, "Head", pivot=tuple(N))
    for sx, nm in ((1, "Ear_R"), (-1, "Ear_L")):
        E = S + Vector((sx * 0.028, -0.025, 0.045))
        tip = (E.x + 0.025 * sx, E.y - 0.045, E.z + 0.185)
        mid = (E.x + 0.014 * sx, E.y - 0.014, E.z + 0.10)
        b = MB("rabbit_" + nm)
        limb(b, [tuple(E), mid, tip], [(0.020, 0.008), (0.032, 0.010), 0.0], sides=4, mats=[F, F], cap0=True, cap1=False, hint=(1, 0.0, 0))
        A.part(b, nm, pivot=tuple(E), parent="Head")

    fore = [(0.038, 0.115, 0.135), (0.036, 0.125, 0.06), (0.034, 0.145, 0.006)]
    fore_r = [(0.026, 0.030), (0.018, 0.022), (0.020, 0.030)]
    hind = [(0.066, -0.115, 0.185), (0.070, -0.045, 0.085), (0.054, -0.150, 0.040), (0.050, -0.040, 0.006)]
    hind_r = [(0.052, 0.062), (0.030, 0.040), (0.020, 0.026), (0.022, 0.032)]
    make_legs(A, fore, fore_r, hind, hind_r, [F, BEL, BEL][:2] if False else [F, F], sides=5)

    b = MB("rabbit_tail")
    ico(b, (0, -0.225, 0.150), (0.04, 0.04, 0.04), mat=BEL, subdiv=1)
    A.part(b, "Tail", pivot=(0, -0.205, 0.15))
    return A


def run(only=None):
    out = {}
    for kind, fn in (("cat", build_cat), ("rabbit", build_rabbit)):
        if only and kind not in only:
            continue
        A = fn()
        A.report(600)
        out[kind] = A
    return out


run(globals().get("ONLY"))
