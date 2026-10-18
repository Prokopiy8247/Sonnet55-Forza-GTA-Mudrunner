"""lane10_small_c.py - flower_patch, reeds, log, stump, driftwood, shell, sand_dune_patch."""
import math, random


def end_cap(b, ring, center, normal, outer="WoodCut", inner="Wood", k=0.55, lift=0.006):
    """Cut-wood end: annulus (outer mat) + raised centre disc (inner mat) -> reads as growth rings."""
    c = Vector(center)
    n = Vector(normal).normalized()
    inner_v = [b.v(c + (v.co - c) * k + n * lift) for v in ring]
    seg = len(ring)
    for i in range(seg):
        j = (i + 1) % seg
        b.face([ring[i], ring[j], inner_v[j], inner_v[i]], outer)
    b.face(inner_v if n.dot((ring[1].co - ring[0].co).cross(ring[2].co - ring[1].co)) > 0 else list(reversed(inner_v)), inner)


def build_flower_patch():
    a = Asset("flower_patch")
    b = MB("flower_patch_body")
    rnd = random.Random(141)
    blob(b, (0, 0, 0.03), (0.62, 0.58, 0.14), mat="Leaf", top_mat="LeafLight", top_thresh=0.5, subdiv=1, jitter=0.1, seed=140, ground=0.0)
    for i in range(10):
        ang = i * 36 + rnd.uniform(-10, 10)
        rr = rnd.uniform(0.1, 0.4)
        x, y = math.sin(math.radians(ang)) * rr, math.cos(math.radians(ang)) * rr
        blade(b, x, y, ang + rnd.uniform(-30, 30), rnd.uniform(0.22, 0.38), 0.03, rnd.uniform(0.06, 0.16), mat_base="Leaf", mat_tip="LeafLight", z0=0.05)
    cols = ["FlowerPink", "Accent", "FlowerWhite", "FlowerBlue", "FlowerPink", "FlowerYellow", "FlowerWhite", "FlowerPink", "Accent"]
    for i, m in enumerate(cols):
        ang = i * 40 + rnd.uniform(-12, 12)
        rr = rnd.uniform(0.08, 0.42)
        x, y = math.sin(math.radians(ang)) * rr, math.cos(math.radians(ang)) * rr
        h = rnd.uniform(0.3, 0.5)
        lean = (rnd.uniform(-0.05, 0.05), rnd.uniform(-0.05, 0.05))
        tube(b, [(x, y, 0.04), (x + lean[0] * 0.5, y + lean[1] * 0.5, h * 0.5), (x + lean[0], y + lean[1], h)], [0.013, 0.011, 0.01], seg=3,
             mat="LeafDeep", cap_start=False, cap_end=False)
        octa(b, (x + lean[0], y + lean[1], h + 0.03), 0.075, mat=m, sq=0.55, rot=rnd.uniform(0, 1.5))
    a.mesh(b, "Body")
    a.report()
    return a


def build_reeds():
    a = Asset("reeds")
    b = MB("reeds_body")
    rnd = random.Random(151)
    n = 18
    for i in range(n):
        ang = i * 137.5 + rnd.uniform(-12, 12)
        rr = 0.04 + 0.22 * math.sqrt(i / n)
        x, y = math.sin(math.radians(ang)) * rr, math.cos(math.radians(ang)) * rr
        h = rnd.uniform(1.1, 1.75)
        blade(b, x, y, ang + rnd.uniform(-20, 20), h, rnd.uniform(0.025, 0.04), rnd.uniform(0.12, 0.38), mat_base="ReedGreen", mat_tip="ReedDry", bend=0.35)
    for i, (ang, rr, h) in enumerate(((20, 0.12, 1.55), (140, 0.18, 1.35), (250, 0.1, 1.7))):
        x, y = math.sin(math.radians(ang)) * rr, math.cos(math.radians(ang)) * rr
        lx, ly = math.sin(math.radians(ang)) * 0.08, math.cos(math.radians(ang)) * 0.08
        tube(b, [(x, y, 0.0), (x + lx * 0.5, y + ly * 0.5, h * 0.55), (x + lx, y + ly, h)], [0.02, 0.016, 0.014], seg=3, mat="ReedGreen", cap_start=False, cap_end=False)
        b.cyl((x + lx, y + ly, h + 0.03), 0.036, 0.26, 5, "CattailBrown", axis="Z", r_top=0.03)
        tube(b, [(x + lx, y + ly, h + 0.16), (x + lx, y + ly, h + 0.32)], [0.008, 0.0], seg=3, mat="ReedDry", cap_start=False, cap_end=False)
    a.mesh(b, "Body")
    a.report()
    return a


def build_log():
    a = Asset("log")
    b = MB("log_body")
    R = 0.34
    pts = [(0, -1.15, R * 0.95), (0.02, -0.4, R * 0.98), (-0.02, 0.5, R * 0.96), (0.0, 1.15, R * 0.9)]
    V = tube(b, pts, [R * 0.95, R, R * 0.97, R * 0.9], seg=8, mat="Bark", cap_start=False, cap_end=False, rot=0.2, jitter=0.04, seed=14,
             mats=["Bark", "Bark", "BarkDark"])
    end_cap(b, V[0], pts[0], (0, -1, 0))
    end_cap(b, V[-1], pts[-1], (0, 1, 0))
    # branch stubs
    s1 = tube(b, [(0.1, -0.2, R * 1.0), (0.45, -0.3, R * 1.5), (0.7, -0.35, R * 1.7)], [0.1, 0.075, 0.07], seg=5, mat="Bark", cap_start=False, cap_end=False)
    end_cap(b, s1[-1], (0.7, -0.35, R * 1.7), (0.5, -0.1, 0.4), k=0.5)
    s2 = tube(b, [(-0.1, 0.45, R * 1.0), (-0.45, 0.55, R * 1.35), (-0.62, 0.6, R * 1.5)], [0.08, 0.06, 0.055], seg=5, mat="Bark", cap_start=False, cap_end=False)
    end_cap(b, s2[-1], (-0.62, 0.6, R * 1.5), (-0.5, 0.1, 0.3), k=0.5)
    # moss patches
    blob(b, (0.0, 0.2, R * 1.7), (0.2, 0.42, 0.07), mat="Leaf", top_mat="LeafLight", top_thresh=0.5, subdiv=1, jitter=0.12, seed=15)
    blob(b, (0.02, -0.75, R * 1.78), (0.17, 0.26, 0.06), mat="Leaf", top_mat="LeafLight", top_thresh=0.5, subdiv=1, jitter=0.12, seed=16)
    a.mesh(b, "Body")
    a.report()
    return a


def build_stump():
    a = Asset("stump")
    b = MB("stump_body")
    rings = []
    rnd = random.Random(161)
    prof = [(0.0, 0.56), (0.16, 0.44), (0.5, 0.38), (0.6, 0.36)]
    N = 9
    for z, r in prof:
        rings.append([Vector((math.cos(2 * math.pi * i / N) * r * (1 + rnd.uniform(-0.06, 0.06)), math.sin(2 * math.pi * i / N) * r * (1 + rnd.uniform(-0.06, 0.06)),
                              z + (rnd.uniform(-0.02, 0.05) if z > 0.55 else 0))) for i in range(N)])
    V = loft_mats(b, rings, ["Bark", "Bark", "BarkDark"], cap_start="BarkDark")
    end_cap(b, V[-1], (0, 0, 0.6), (0, 0, 1), outer="WoodCut", inner="Wood", k=0.5, lift=0.012)
    for i, ang in enumerate((20, 110, 200, 290)):
        r = math.radians(ang)
        tube(b, [(math.cos(r) * 0.75, math.sin(r) * 0.75, 0.0), (math.cos(r) * 0.46, math.sin(r) * 0.46, 0.12), (math.cos(r) * 0.3, math.sin(r) * 0.3, 0.3)],
             [0.07, 0.09, 0.12], seg=3, mat="Bark", cap_start=True, cap_end=False)
    # shelf fungus on the side
    octa(b, (0.34, -0.2, 0.3), 0.1, mat="FlowerWhite", sq=0.4, rot=0.5)
    octa(b, (0.37, -0.12, 0.38), 0.07, mat="FlowerWhite", sq=0.4, rot=0.2)
    a.mesh(b, "Body")
    a.report()
    return a


def build_driftwood():
    a = Asset("driftwood")
    b = MB("driftwood_body")
    pts = [(-0.9, -0.3, 0.1), (-0.4, 0.0, 0.16), (0.1, 0.25, 0.28), (0.55, 0.15, 0.2), (0.95, -0.1, 0.12)]
    V = tube(b, pts, [0.1, 0.13, 0.12, 0.09, 0.05], seg=6, mat="BarkPale", cap_start=False, cap_end=True, rot=0.3, jitter=0.1, seed=17,
             mats=["BarkPale", "BarkMid", "BarkPale", "BarkMid"])
    end_cap(b, V[0], pts[0], (-1, -0.3, 0), outer="BarkPale", inner="WoodCut", k=0.5)
    fork = tube(b, [(0.1, 0.25, 0.3), (0.2, 0.55, 0.55), (0.3, 0.75, 0.82), (0.5, 0.85, 1.0)], [0.075, 0.06, 0.045, 0.02], seg=5, mat="BarkPale", cap_start=False, cap_end=True,
                jitter=0.08, seed=18)
    tube(b, [(-0.3, 0.0, 0.18), (-0.45, 0.35, 0.3), (-0.5, 0.6, 0.42)], [0.06, 0.04, 0.0], seg=4, mat="BarkPale", cap_start=False, cap_end=False)
    a.mesh(b, "Body")
    a.report()
    return a


def build_shell():
    a = Asset("shell")
    b = MB("shell_body")

    def scallop(cx, cy, rot, r, h, mat1, mat2, seg=7):
        apex = (cx, cy, 0.01)
        pts = []
        for i in range(seg * 2):
            ang = rot + math.radians(-80 + 160 * i / (seg * 2 - 1))
            ridge = i % 2 == 0
            rr = r * (1.0 if ridge else 0.9)
            pts.append((cx + math.sin(ang) * rr, cy + math.cos(ang) * rr, (h if ridge else h * 0.7) * 0.0 + 0.012))
        mid = [(cx + (p[0] - cx) * 0.45, cy + (p[1] - cy) * 0.45, h * (0.95 if i % 2 == 0 else 0.8)) for i, p in enumerate(pts)]
        A = b.v(apex)
        P = [b.v(p) for p in pts]
        Mv = [b.v(p) for p in mid]
        for i in range(len(P) - 1):
            m = mat1 if i % 2 == 0 else mat2
            b.face([P[i], P[i + 1], Mv[i + 1], Mv[i]], m)
            b.face([A, Mv[i], Mv[i + 1]], m)
        b.face([A, P[-1], Mv[-1]], mat1) if False else None
        b.face([A, Mv[-1], P[-1]], mat1)
        b.face([A, P[0], Mv[0]], mat1)
        b.face([A] + list(reversed(P)), mat2)

    scallop(0.0, -0.02, 0.0, 0.16, 0.06, "ShellPink", "ShellWhite")
    scallop(0.22, 0.14, 2.2, 0.1, 0.045, "ShellWhite", "ShellPink", seg=6)
    blob(b, (-0.2, 0.17, 0.035), (0.07, 0.1, 0.05), mat="ShellWhite", subdiv=1, jitter=0.1, seed=19, ground=0.0)
    a.mesh(b, "Body")
    a.report()
    return a


def build_sand_dune_patch():
    a = Asset("sand_dune_patch")
    b = MB("dune_body")
    blob(b, (0, 0, 0.0), (2.4, 1.6, 0.5), mat="SandWet", top_mat="DuneSand", top_thresh=0.3, subdiv=2, jitter=0.07, seed=171, ground=0.0, rot_z=0.2)
    blob(b, (1.3, 0.7, 0.0), (1.3, 1.0, 0.32), mat="SandWet", top_mat="DuneSand", top_thresh=0.3, subdiv=1, jitter=0.07, seed=172, ground=0.0)
    rnd = random.Random(173)
    for i in range(7):
        x, y = rnd.uniform(-1.0, 0.5), rnd.uniform(-0.5, 0.5)
        blade(b, x, y, rnd.uniform(0, 360), rnd.uniform(0.35, 0.6), 0.03, rnd.uniform(0.1, 0.25), mat_base="LeafLight", mat_tip="LeafYellow", z0=0.3)
    a.mesh(b, "Body")
    a.report()
    return a


BUILDERS = {"flower_patch": build_flower_patch, "reeds": build_reeds, "log": build_log, "stump": build_stump, "driftwood": build_driftwood,
            "shell": build_shell, "sand_dune_patch": build_sand_dune_patch}
run_builders(BUILDERS, globals().get("ONLY"))
