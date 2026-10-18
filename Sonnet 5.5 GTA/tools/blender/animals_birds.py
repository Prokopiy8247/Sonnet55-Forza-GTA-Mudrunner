"""animals_birds.py - seagull (0.45 m long, 0.9 m span) and bird_small (dark small bird, 0.23 m long, 0.45 m span), each in a FLYING
variant (wings spread, <id>) and a PERCHED variant (wings folded, <id>_perched). Idempotent.   ONLY=['seagull'] to build a subset.
Hierarchy: Body, Head (beak included), Wing_L/Wing_R (pivot = shoulder), Tail (pivot = root), Leg_L/Leg_R (pivot = hip).
Built at design scale 1.0 and scaled by `sc` when each part is created (pivots scale with it).
"""
exec(open(r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender\animals_lib.py", encoding="utf8").read(), globals())

GULL_COLS = dict(AnimalFur=("#98a6b3", 0.9), AnimalBelly=("#f4f2ec", 0.9), AnimalDark=("#1d2024", 0.9), Beak=("#f2b52e", 0.6),
                 Accent=("#ec9a78", 0.7), Hoof=("#ec9a78", 0.7), Antler=("#e0443a", 0.6))
SMALL_COLS = dict(AnimalFur=("#2a303a", 0.9), AnimalBelly=("#454c58", 0.9), AnimalDark=("#14171b", 0.9), Beak=("#d9a63a", 0.6),
                  Accent=("#6b4a3c", 0.7), Hoof=("#6b4a3c", 0.7), Antler=("#14171b", 0.6))


def build_bird(aid, kind, folded, slot):
    gull = kind == "seagull"
    sc = 0.72 if gull else 0.36
    A = Animal(aid, slot, aid, sc=sc, **(GULL_COLS if gull else SMALL_COLS))
    TOP, BEL, DK, BK, AC = A.m("AnimalFur"), A.m("AnimalBelly"), A.m("AnimalDark"), A.m("Beak"), A.m("Accent")
    HEAD, TAILM = (BEL, BEL) if gull else (TOP, TOP)
    UND = BEL
    er = 0.011 if gull else 0.020          # eye radius (bigger on the small bird so it still reads)
    # ---- Body (tail end -> neck base), 6 sided
    rings = [ring_xz(-0.20, 0.026, 0.19, 0.165, n=6), ring_xz(-0.12, 0.076, 0.245, 0.13, n=6), ring_xz(0.00, 0.094, 0.274, 0.108, n=6),
             ring_xz(0.10, 0.080, 0.268, 0.118, n=6), ring_xz(0.165, 0.048, 0.24, 0.15, n=6)]
    b = MB(aid + "_body")
    # n=6, rot=30deg: facets 0..5; top facets are 0,1,2 (angles 60..120 -> i=1 top), lower facets 3,4,5
    skin(b, rings, lambda k, i: (TOP if (i in (0, 1, 2) and k in (0, 1, 2, 3)) else UND) if gull else (TOP if i in (0, 1, 2) else UND), cap0=TAILM, cap1=HEAD)
    A.part(b, "Body")
    # ---- Head + beak, pivot at neck base
    H = Vector((0, 0.215, 0.315))
    b = MB(aid + "_head")
    limb(b, [(0, 0.15, 0.225), tuple(H - Vector((0, 0.01, 0.03))), tuple(H), (0, 0.245, 0.315)],
         [(0.048, 0.052), (0.046, 0.05), (0.044, 0.044), (0.034, 0.033)], sides=6, mats=[HEAD, HEAD, HEAD], cap0=True, cap1=True, rot=math.pi / 6)
    beak_len = 0.08 if gull else 0.07
    limb(b, [(0, 0.24, 0.31), (0, 0.24 + beak_len * 0.7, 0.304), (0, 0.24 + beak_len, 0.288)],
         [(0.019, 0.019), (0.012, 0.014), 0.0], sides=4, mats=[BK, BK], cap0=True, cap1=False, rot=math.pi / 4)
    for sx in (1, -1):
        eye(b, H + Vector((sx * 0.040, 0.02, 0.012)), (sx, 0.5, 0.1), r=er)
    A.part(b, "Head", pivot=(0, 0.15, 0.24))
    # ---- Tail (flat fan)
    b = MB(aid + "_tail")
    limb(b, [(0, -0.17, 0.19), (0, -0.30, 0.172)], [(0.040, 0.012), (0.082, 0.007)], sides=4, mats=TAILM if gull else DK, cap0=True, cap1=True, rot=math.pi / 4, hint=(1, 0, 0))
    A.part(b, "Tail", pivot=(0, -0.17, 0.19))
    # ---- Wings (pivot at the shoulder)
    for sx, nm in ((1, "Wing_R"), (-1, "Wing_L")):
        b = MB(aid + "_" + nm)
        sh = (0.055, 0.045, 0.225)
        if not folded:
            pts = [(0.0, 0.0, 0.0), (0.17, 0.0, 0.015), (0.31, -0.03, 0.035), (0.45, -0.085, 0.045), (0.58, -0.16, 0.040)]
            rr = [(0.070, 0.016), (0.092, 0.013), (0.078, 0.011), (0.056, 0.008), 0.0]
            pts = [(sh[0] + p[0], sh[1] + p[1], sh[2] + p[2]) for p in pts]
            limb(b, pts, rr, sides=4, mats=[TOP, TOP, TOP, DK], sx=sx, cap0=True, cap1=False, rot=0.0, hint=(0, 1, 0))
        else:
            pts = [(0.0, 0.0, 0.0), (0.012, -0.10, -0.012), (0.0, -0.22, -0.03), (-0.005, -0.34, -0.045)]
            rr = [(0.055, 0.020), (0.060, 0.018), (0.050, 0.014), 0.0]
            pts = [(sh[0] + p[0], sh[1] + p[1], sh[2] + p[2]) for p in pts]
            limb(b, pts, rr, sides=4, mats=[TOP, TOP, DK], sx=sx, cap0=True, cap1=False, rot=0.0, hint=(0, 0, 1))
        A.part(b, nm, pivot=(sx * sh[0], sh[1], sh[2]))
    # ---- Legs (pivot at the hip) + webbed foot
    for sx, nm in ((1, "Leg_R"), (-1, "Leg_L")):
        b = MB(aid + "_" + nm)
        hx = 0.035
        limb(b, [(hx, 0.0, 0.14), (hx, 0.005, 0.075), (hx, 0.012, 0.012)], [0.016, 0.0095, 0.0095], sides=4, mats=AC, sx=sx, cap0=True, cap1=False, rot=math.pi / 4)
        fx = hx * sx
        plane_poly(b, [(fx, 0.0), (fx + 0.030 * sx, 0.062), (fx - 0.030 * sx, 0.062)][::(1 if sx > 0 else -1)], "xy", 0.001, 0.008, AC)
        A.part(b, nm, pivot=(hx * sx, 0.0, 0.14))
    return A


def run(only=None):
    out = {}
    for aid, kind, folded, slot in (("seagull", "seagull", False, 3 + 5), ("seagull_perched", "seagull", True, 9),
                                    ("bird_small", "small", False, 10), ("bird_small_perched", "small", True, 11)):
        if only and aid not in only:
            continue
        A = build_bird(aid, kind, folded, slot)
        A.report(250)
        out[aid] = A
    return out


run(globals().get("ONLY"))
