"""lane10_small_a.py - bush_a, rock_a, grass_tuft (first-priority small nature). Set ONLY=[...] to build a subset."""
import math, random


def rock_blob(b, c, radii, seed, subdiv=2, jitter=0.2, cuts=(), rot=0.0, top="RockPale", mid="RockMid", low="RockShade", ground=0.0, top_thresh=0.55):
    return blob(b, c, radii, mat=mid, top_mat=top, top_thresh=top_thresh, bottom_mat=low, bottom_thresh=-0.25, subdiv=subdiv, jitter=jitter,
                seed=seed, rot_z=rot, ground=ground, cuts=cuts)


def build_bush_a():
    a = Asset("bush_a")
    b = MB("bush_a_body")
    kw = dict(mat="Leaf", top_mat="LeafLight", top_thresh=0.5, bottom_mat="LeafDeep", bottom_thresh=-0.3, jitter=0.14, ground=0.0)
    blob(b, (0.0, 0.0, 0.55), (0.8, 0.72, 0.68), subdiv=2, seed=11, **kw)
    blob(b, (-0.62, 0.22, 0.4), (0.55, 0.5, 0.42), subdiv=2, seed=12, **kw)
    blob(b, (0.58, -0.2, 0.38), (0.55, 0.5, 0.4), subdiv=1, seed=13, **kw)
    blob(b, (0.1, -0.55, 0.36), (0.45, 0.42, 0.34), subdiv=1, seed=14, **kw)
    a.mesh(b, "Body")
    a.report()
    return a


def build_rock_a():
    a = Asset("rock_a")
    b = MB("rock_a_body")
    rock_blob(b, (0, 0, 0.42), (0.78, 0.64, 0.58), seed=21, jitter=0.2, cuts=[((0.35, 0.1, 1.0), 0.5), ((1.0, -0.4, 0.2), 0.62)], rot=0.4)
    rock_blob(b, (0.62, 0.38, 0.16), (0.34, 0.3, 0.26), seed=22, subdiv=1, jitter=0.2, cuts=[((0, 0, 1), 0.2)])
    a.mesh(b, "Body")
    a.report()
    return a


def build_grass_tuft():
    a = Asset("grass_tuft")
    b = MB("grass_tuft_body")
    rnd = random.Random(31)
    n = 22
    for i in range(n):
        ang = i * 137.5 + rnd.uniform(-15, 15)
        rr = 0.02 + 0.1 * math.sqrt(i / n)
        x, y = math.sin(math.radians(ang)) * rr, math.cos(math.radians(ang)) * rr
        h = rnd.uniform(0.32, 0.6) * (1.2 if i < 5 else 1.0)
        blade(b, x, y, ang + rnd.uniform(-30, 30), h, rnd.uniform(0.022, 0.034), rnd.uniform(0.1, 0.3) * (0.4 if i < 5 else 1.0),
              mat_base="Leaf" if i % 2 else "LeafLight", mat_tip="LeafLight" if i % 3 else "LeafYellow", bend=0.2)
    a.mesh(b, "Body")
    a.report()
    return a


BUILDERS = {"bush_a": build_bush_a, "rock_a": build_rock_a, "grass_tuft": build_grass_tuft}
run_builders(BUILDERS, globals().get("ONLY"))
