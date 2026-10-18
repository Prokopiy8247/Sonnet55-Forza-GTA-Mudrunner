"""animals_sea.py - fish_a (orange reef fish 0.30 m), fish_b (silver 0.50 m), shark (3.2 m), dolphin (2.0 m), sea_turtle (0.8 m). Idempotent.
ONLY=['shark'] to build a subset.  Origin = body centre (z=0 is the body centre line), forward +Y.
Fish/shark nodes: Body, Fin_Tail (pivot = tail root; rotate about Blender Z = Godot Y for the swim wiggle), Fin_Dorsal, Fin_L, Fin_R (pivot = fin base), [Jaw].
"""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\animals_lib.py", encoding="utf8").read(), globals())

FISHA_COLS = dict(AnimalFur=("#ef7a22", 0.6), AnimalBelly=("#f6efe0", 0.6), AnimalDark=("#1b1613", 0.6), Accent=("#f7a840", 0.6))
FISHB_COLS = dict(AnimalFur=("#7f9db3", 0.35), AnimalBelly=("#dfe8ee", 0.35), AnimalDark=("#3d566b", 0.45), Accent=("#b9cad6", 0.4))
SHARK_COLS = dict(AnimalFur=("#6d7f8c", 0.7), AnimalBelly=("#e6eaec", 0.7), AnimalDark=("#3b4854", 0.7), Antler=("#f4f1e6", 0.5), Accent=("#7a1f24", 0.6))
DOLPH_COLS = dict(AnimalFur=("#6f8da3", 0.55), AnimalBelly=("#e9eef0", 0.55), AnimalDark=("#415a6d", 0.6), Accent=("#d9a9a0", 0.6))
TURT_COLS = dict(AnimalFur=("#7f8c4e", 0.9), AnimalBelly=("#d9cfa0", 0.9), AnimalDark=("#4d5a35", 0.9), AnimalShell=("#8a6a3b", 0.85), Accent=("#b5a35c", 0.9))


def tail_fin_part(A, b_name, ring_a, ring_b, fin_poly, mat_ped, mat_fin, pivot, thick=0.004, ped_n=None):
    b = MB(b_name)
    skin(b, [ring_a, ring_b], mat_ped, cap1=mat_ped)
    plane_poly(b, fin_poly, "yz", -thick, thick, mat_fin)
    A.part(b, "Fin_Tail", pivot=pivot)


def build_fish_a(slot=13):
    A = Animal("fish_a", slot, "fish_a", sc=0.70, **FISHA_COLS)
    F, BEL, DK, AC = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("Accent")
    R = [ring_xz(0.16, 0.010, 0.020, -0.020), ring_xz(0.07, 0.036, 0.066, -0.060), ring_xz(0.045, 0.041, 0.082, -0.074),
         ring_xz(-0.03, 0.044, 0.090, -0.080), ring_xz(-0.065, 0.040, 0.078, -0.066), ring_xz(-0.095, 0.033, 0.062, -0.052),
         ring_xz(-0.14, 0.016, 0.032, -0.030)]
    mk = [F, BEL, F, F, BEL, F]
    b = MB("fish_a_body")
    skin(b, R, lambda k, i: mk[k], cap0=F, cap1=F)
    for sx in (1, -1):
        eye(b, (sx * 0.035, 0.105, 0.012), (sx, 0.25, 0.1), r=0.0095)
    A.part(b, "Body")
    tail_fin_part(A, "fish_a_tail", ring_xz(-0.14, 0.016, 0.032, -0.030), ring_xz(-0.175, 0.008, 0.016, -0.015),
                  [(-0.17, -0.014), (-0.265, -0.075), (-0.245, 0.0), (-0.265, 0.075), (-0.17, 0.014)], F, AC, (0, -0.14, 0))
    b = MB("fish_a_dorsal")
    plane_poly(b, [(0.07, 0.080), (0.045, 0.145), (-0.03, 0.128), (-0.095, 0.060)], "yz", -0.004, 0.004, AC)
    A.part(b, "Fin_Dorsal", pivot=(0, -0.01, 0.082))
    for sx, nm in ((1, "Fin_R"), (-1, "Fin_L")):
        b = MB("fish_a_" + nm)
        pts = [(sx * 0.040, 0.075), (sx * 0.040, 0.030), (sx * 0.115, 0.008), (sx * 0.118, 0.060)]
        plane_poly(b, pts if sx > 0 else pts[::-1], "xy", -0.014, -0.008, AC)
        A.part(b, nm, pivot=(sx * 0.040, 0.05, -0.011))
    return A


def build_fish_b(slot=14):
    A = Animal("fish_b", slot, "fish_b", sc=0.90, **FISHB_COLS)
    F, BEL, DK, AC = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("Accent")
    R = [ring_xz(0.27, 0.008, 0.018, -0.018), ring_xz(0.20, 0.040, 0.052, -0.048), ring_xz(0.08, 0.062, 0.086, -0.074),
         ring_xz(-0.05, 0.055, 0.078, -0.066), ring_xz(-0.15, 0.020, 0.030, -0.028)]
    b = MB("fish_b_body")
    skin(b, R, belly_fn(F, BEL, belly_idx=(3, 4, 5, 6, 7), dark=DK, dark_idx=(1,), dark_k=(2, 3)), cap0=F, cap1=F)
    for sx in (1, -1):
        eye(b, (sx * 0.038, 0.19, 0.012), (sx, 0.3, 0.1), r=0.0095)
    A.part(b, "Body")
    tail_fin_part(A, "fish_b_tail", ring_xz(-0.15, 0.020, 0.030, -0.028), ring_xz(-0.19, 0.008, 0.014, -0.013),
                  [(-0.18, -0.012), (-0.285, -0.105), (-0.235, 0.0), (-0.285, 0.105), (-0.18, 0.012)], DK, DK, (0, -0.15, 0), thick=0.005)
    b = MB("fish_b_dorsal")
    plane_poly(b, [(0.07, 0.080), (0.005, 0.150), (-0.06, 0.07)], "yz", -0.004, 0.004, DK)
    A.part(b, "Fin_Dorsal", pivot=(0, 0.0, 0.080))
    for sx, nm in ((1, "Fin_R"), (-1, "Fin_L")):
        b = MB("fish_b_" + nm)
        pts = [(sx * 0.050, 0.060), (sx * 0.050, 0.020), (sx * 0.150, -0.020), (sx * 0.135, 0.050)]
        plane_poly(b, pts if sx > 0 else pts[::-1], "xy", -0.016, -0.010, DK)
        A.part(b, nm, pivot=(sx * 0.050, 0.04, -0.012))
    return A


def build_shark(slot=15):
    A = Animal("shark", slot, "shark", sc=0.95, **SHARK_COLS)
    F, BEL, DK, TH, MO = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("Antler"), A.m("Accent")
    R = [ring_xz(1.55, 0.05, 0.06, -0.06), ring_xz(1.34, 0.17, 0.215, -0.17), ring_xz(0.95, 0.27, 0.34, -0.28), ring_xz(0.35, 0.31, 0.385, -0.31),
         ring_xz(-0.35, 0.24, 0.30, -0.25), ring_xz(-0.95, 0.125, 0.155, -0.13), ring_xz(-1.22, 0.07, 0.09, -0.08)]
    b = MB("shark_body")
    skin(b, R, belly_fn(F, BEL, belly_idx=(4, 5, 6)), cap0=F, cap1=F)
    # eyes + upper teeth row on the underside of the snout
    for sx in (1, -1):
        eye(b, (sx * 0.185, 1.24, 0.08), (sx, 0.45, 0.15), r=0.040)
    for sx in (1, -1):
        for ty in (1.14, 1.24, 1.34, 1.44):
            tx = sx * (0.085 - (ty - 1.14) * 0.15)
            limb(b, [(abs(tx), ty, -0.145 - (0.0 if ty < 1.4 else 0.01)), (abs(tx), ty + 0.012, -0.235)], [0.020, 0.0], sides=3, mats=TH, sx=sx, cap0=False, cap1=False, rot=math.pi / 2)
    A.part(b, "Body")

    # tail: heterocercal caudal fin
    tail_fin_part(A, "shark_tail", ring_xz(-1.22, 0.07, 0.09, -0.08), ring_xz(-1.42, 0.035, 0.05, -0.045),
                  [(-1.35, 0.04), (-1.82, 0.70), (-1.60, 0.18), (-1.64, -0.12), (-1.66, -0.44), (-1.35, -0.04)], F, DK, (0, -1.22, 0), thick=0.022)
    # dorsal
    b = MB("shark_dorsal")
    plane_poly(b, [(0.45, 0.35), (0.13, 0.95), (0.02, 0.64), (-0.16, 0.34)], "yz", -0.016, 0.016, F)
    A.part(b, "Fin_Dorsal", pivot=(0, 0.15, 0.36))
    # pectorals (swept blades)
    for sx, nm in ((1, "Fin_R"), (-1, "Fin_L")):
        b = MB("shark_" + nm)
        root = (0.27, 0.80, -0.20)
        limb(b, [root, (0.50, 0.55, -0.34), (0.82, 0.18, -0.50)], [(0.21, 0.030), (0.13, 0.022), 0.0], sides=4, mats=[F, DK], sx=sx, cap0=True, cap1=False, rot=0.0, hint=(0, 1, 0))
        A.part(b, nm, pivot=(sx * root[0], root[1], root[2]))
    # lower jaw
    b = MB("shark_jaw")
    limb(b, [(0, 0.98, -0.20), (0, 1.22, -0.235), (0, 1.40, -0.20), (0, 1.47, -0.17)], [(0.20, 0.060), (0.15, 0.052), (0.09, 0.042), (0.03, 0.03)],
         sides=6, mats=[BEL, BEL, BEL], cap0=True, cap1=True, rot=math.pi / 6)
    for sx in (1, -1):
        for ty in (1.12, 1.22, 1.32, 1.41):
            tx = 0.11 - (ty - 1.12) * 0.22
            limb(b, [(tx, ty, -0.19), (tx, ty - 0.012, -0.115)], [0.020, 0.0], sides=3, mats=TH, sx=sx, cap0=False, cap1=False, rot=math.pi / 2)
    shell_rotate(b, 0, "X", -13.0, (0, 0.98, -0.20))
    A.part(b, "Jaw", pivot=(0, 0.98, -0.20))
    return A


def build_dolphin(slot=16):
    A = Animal("dolphin", slot, "dolphin", sc=0.90, **DOLPH_COLS)
    F, BEL, DK, AC = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("Accent")
    R = [ring_xz(1.00, 0.025, 0.05, -0.045), ring_xz(0.82, 0.055, 0.10, -0.07), ring_xz(0.62, 0.13, 0.185, -0.12), ring_xz(0.30, 0.20, 0.26, -0.20),
         ring_xz(-0.20, 0.18, 0.235, -0.19), ring_xz(-0.60, 0.10, 0.13, -0.11), ring_xz(-0.82, 0.05, 0.07, -0.06)]
    b = MB("dolphin_body")
    skin(b, R, belly_fn(F, BEL, belly_idx=(4, 5, 6)), cap0=DK, cap1=F)
    for sx in (1, -1):
        eye(b, (sx * 0.12, 0.60, 0.07), (sx, 0.4, 0.15), r=0.030)
    A.part(b, "Body")
    # tail stock + horizontal flukes (rotate about X for the swim wiggle)
    b = MB("dolphin_tail")
    skin(b, [ring_xz(-0.82, 0.05, 0.07, -0.06), ring_xz(-0.98, 0.028, 0.04, -0.035)], F, cap1=F)
    plane_poly(b, [(0.03, -0.95), (0.20, -1.06), (0.36, -1.22), (0.12, -1.16), (0.0, -1.19), (-0.12, -1.16), (-0.36, -1.22), (-0.20, -1.06), (-0.03, -0.95)], "xy", -0.010, 0.010, DK)
    A.part(b, "Fin_Tail", pivot=(0, -0.82, 0.0))
    b = MB("dolphin_dorsal")
    plane_poly(b, [(0.14, 0.255), (-0.10, 0.50), (-0.30, 0.22)], "yz", -0.016, 0.016, F)
    A.part(b, "Fin_Dorsal", pivot=(0, -0.05, 0.24))
    for sx, nm in ((1, "Fin_R"), (-1, "Fin_L")):
        b = MB("dolphin_" + nm)
        root = (0.17, 0.42, -0.16)
        limb(b, [root, (0.38, 0.27, -0.27), (0.50, 0.12, -0.36)], [(0.12, 0.022), (0.075, 0.016), 0.0], sides=4, mats=[F, DK], sx=sx, cap0=True, cap1=False, rot=0.0, hint=(0, 1, 0))
        A.part(b, nm, pivot=(sx * root[0], root[1], root[2]))
    return A


def build_turtle(slot=17):
    A = Animal("sea_turtle", slot, "sea_turtle", sc=0.80, **TURT_COLS)
    F, BEL, DK, SH, AC = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("AnimalShell"), A.m("Accent")
    R = [ring_xz(-0.40, 0.05, 0.10, -0.02), ring_xz(-0.28, 0.22, 0.20, -0.04), ring_xz(-0.04, 0.34, 0.26, -0.05), ring_xz(0.20, 0.27, 0.215, -0.045),
         ring_xz(0.34, 0.10, 0.12, -0.03)]
    def tmat(k, i):
        if i in (4, 5, 6):
            return BEL
        return SH if (k + i) % 2 == 0 else DK
    b = MB("turtle_body")
    skin(b, R, tmat, cap0=SH, cap1=SH)
    A.part(b, "Body")
    # head + neck (pivot at neck base)
    N = Vector((0, 0.30, 0.06))
    b = MB("turtle_head")
    limb(b, [(0, 0.26, 0.07), (0, 0.38, 0.10), (0, 0.46, 0.11), (0, 0.55, 0.095)], [(0.07, 0.075), (0.055, 0.06), (0.058, 0.06), (0.04, 0.04)], sides=6, mats=[F, F, F], cap0=True, cap1=True, rot=math.pi / 6)
    for sx in (1, -1):
        eye(b, (sx * 0.050, 0.49, 0.125), (sx, 0.3, 0.2), r=0.015)
    A.part(b, "Head", pivot=tuple(N))
    # flippers: pivot at the shoulder, long front pair, short hind pair
    for sx, nm in ((1, "Flipper_FR"), (-1, "Flipper_FL")):
        b = MB("turtle_" + nm)
        root = (0.25, 0.18, 0.0)
        limb(b, [root, (0.50, 0.28, -0.04), (0.78, 0.13, -0.09)], [(0.095, 0.022), (0.075, 0.016), 0.0], sides=4, mats=[F, F], sx=sx, cap0=True, cap1=False, rot=0.0, hint=(0, 1, 0))
        A.part(b, nm, pivot=(sx * root[0], root[1], root[2]))
    for sx, nm in ((1, "Flipper_BR"), (-1, "Flipper_BL")):
        b = MB("turtle_" + nm)
        root = (0.16, -0.30, 0.0)
        limb(b, [root, (0.28, -0.40, -0.03), (0.40, -0.52, -0.05)], [(0.07, 0.018), (0.052, 0.014), 0.0], sides=4, mats=[F, F], sx=sx, cap0=True, cap1=False, rot=0.0, hint=(0, 1, 0))
        A.part(b, nm, pivot=(sx * root[0], root[1], root[2]))
    b = MB("turtle_tail")
    limb(b, [(0, -0.37, 0.04), (0, -0.50, 0.03)], [(0.035, 0.03), 0.0], sides=4, mats=F, cap0=True, cap1=False, rot=math.pi / 4)
    A.part(b, "Tail", pivot=(0, -0.37, 0.04))
    return A


def run(only=None):
    out = {}
    for aid, fn, bud in (("fish_a", build_fish_a, 200), ("fish_b", build_fish_b, 200), ("shark", build_shark, 600),
                         ("dolphin", build_dolphin, 600), ("sea_turtle", build_turtle, 600)):
        if only and aid not in only:
            continue
        A = fn()
        A.report(bud, ground=False)
        out[aid] = A
    return out


run(globals().get("ONLY"))
