"""lane10_trees_a.py - palm_a, tree_oak_a, tree_pine_a (+ _lod impostors). Idempotent. Set ONLY=[...] before exec to build a subset."""
import math, random

# --------------------------------------------------------------------------------------------------------------
def build_palm_a():
    a = Asset("palm_a")
    H = 7.4
    lean = 1.2
    def tp(t):
        return (lean * t ** 1.7, 0.18 * math.sin(t * 3.1), H * t)
    ts = [0, 0.07, 0.2, 0.34, 0.5, 0.66, 0.82, 1.0]
    pts = [tp(t) for t in ts]
    pts[0] = (0, 0, -0.08)
    radii = [0.58, 0.36, 0.31, 0.285, 0.265, 0.25, 0.235, 0.225]
    b = MB("palm_a_trunk")
    tube(b, pts, radii, seg=7, mat="Bark", cap_start=True, cap_end=False, rot=0.2, jitter=0.04, seed=3,
         mats=["Bark", "BarkPale", "Bark", "BarkPale", "Bark", "BarkPale", "Bark"])
    a.mesh(b, "Trunk")

    cx, cy, cz = pts[-1]
    c = MB("palm_a_canopy")
    blob(c, (cx, cy, cz + 0.02), (0.4, 0.4, 0.34), mat="BarkDark", subdiv=1, jitter=0.1, seed=5)
    for i, ang in enumerate((20, 150, 265)):
        r = math.radians(ang)
        blob(c, (cx + math.cos(r) * 0.36, cy + math.sin(r) * 0.36, cz - 0.2 - 0.05 * i), (0.17, 0.17, 0.2), mat="LeafDeep", subdiv=1,
             jitter=0.08, seed=20 + i)
    rnd = random.Random(7)
    PL = [0.25, 0.95, 0.5, 1.0, 0.5, 0.7, 0.28]
    PR = [0.25, 0.6, 1.0, 0.55, 0.95, 0.45, 0.62]
    # (yaw, pitch0, bend, length, width, mat)
    plan = [
        (0, 52, 110, 3.6, 0.7, "PalmLeafLt"), (80, 56, 105, 3.5, 0.68, "PalmLeaf"), (160, 50, 112, 3.7, 0.7, "PalmLeafLt"),
        (240, 54, 108, 3.55, 0.68, "PalmLeaf"),
        (40, 24, 120, 4.4, 0.78, "PalmLeaf"), (118, 18, 128, 4.5, 0.8, "PalmLeafLt"), (200, 22, 122, 4.4, 0.78, "PalmLeaf"),
        (280, 16, 130, 4.5, 0.8, "PalmLeafLt"), (330, 30, 118, 4.2, 0.74, "PalmLeaf"),
    ]
    for yaw, p0, bend, ln, w, m in plan:
        y = yaw + rnd.uniform(-8, 8)
        d = (math.sin(math.radians(y)), math.cos(math.radians(y)), 0)
        base = (cx + d[0] * 0.12, cy + d[1] * 0.12, cz + 0.1)
        frond(c, base, y, p0, bend, ln, w, steps=7, mat=m, fold=0.45, profile=PL, profile_r=PR, sag=0.2)
    frond(c, (cx, cy, cz + 0.2), 20, 86, 12, 1.4, 0.26, steps=3, mat="PalmLeafLt", fold=0.3, profile=[0.4, 1.0, 0.5], profile_r=[0.4, 0.7, 0.5])
    a.mesh(c, "Canopy", pivot=(cx, cy, cz))
    a.report()
    return a


def build_palm_a_lod():
    a = lod_tree("palm_a_lod", 7.4, 0.36, 0.2, lean=(1.2, 0.0),
                 fronds=[((1.2, 0, 7.5), y, 35, 105, 3.6, 0.9, "PalmLeaf") for y in (0, 103, 206, 309)] +
                 [((1.2, 0, 7.45), y, 12, 125, 3.9, 1.0, "PalmLeafLt") for y in (51, 154, 257)])
    a.report()
    return a


# --------------------------------------------------------------------------------------------------------------
def build_tree_oak_a():
    a = Asset("tree_oak_a")
    b = MB("oak_a_trunk")
    tube(b, [(0, 0, -0.06), (0.06, 0.02, 1.1), (0.02, 0.1, 2.2), (-0.08, 0.12, 3.3)], [0.56, 0.36, 0.31, 0.27], seg=7, mat="Bark",
         cap_start=True, cap_end=True, rot=0.3, jitter=0.05, seed=2)
    tube(b, [(-0.05, 0.1, 2.7), (-0.7, 0.3, 3.7), (-1.5, 0.4, 4.6)], [0.2, 0.15, 0.08], seg=4, mat="Bark", cap_start=False, cap_end=True)
    tube(b, [(-0.05, 0.1, 2.9), (0.7, -0.1, 3.9), (1.4, -0.3, 4.8)], [0.18, 0.13, 0.08], seg=4, mat="Bark", cap_start=False, cap_end=True)
    tube(b, [(-0.1, 0.12, 3.2), (0.05, 0.4, 4.4), (0.3, 0.6, 5.3)], [0.2, 0.14, 0.08], seg=4, mat="Bark", cap_start=False, cap_end=True)
    for i, ang in enumerate((40, 160, 280)):
        r = math.radians(ang)
        tube(b, [(math.cos(r) * 0.8, math.sin(r) * 0.8, 0.0), (math.cos(r) * 0.42, math.sin(r) * 0.42, 0.5), (math.cos(r) * 0.2, math.sin(r) * 0.2, 1.0)],
             [0.1, 0.14, 0.2], seg=3, mat="Bark", cap_start=True, cap_end=False)
    a.mesh(b, "Trunk")

    c = MB("oak_a_canopy")
    kw = dict(mat="Leaf", top_mat="LeafLight", top_thresh=0.5, bottom_mat="LeafDeep", bottom_thresh=-0.35, jitter=0.13)
    blob(c, (0.0, 0.1, 6.0), (2.9, 2.7, 2.4), subdiv=2, seed=1, **kw)
    blob(c, (-2.2, 0.4, 4.9), (2.0, 1.9, 1.5), subdiv=2, seed=2, **kw)
    blob(c, (2.1, -0.3, 5.2), (2.1, 1.9, 1.6), subdiv=2, seed=3, **kw)
    blob(c, (0.3, 1.7, 7.0), (1.6, 1.5, 1.2), subdiv=1, seed=4, **kw)
    blob(c, (-0.7, -1.6, 6.9), (1.6, 1.5, 1.2), subdiv=1, seed=5, **kw)
    a.mesh(c, "Canopy", pivot=(0.0, 0.1, 3.0))
    a.report()
    return a


def build_tree_oak_a_lod():
    a = lod_tree("tree_oak_a_lod", 3.0, 0.5, 0.25, blobs=[((0, 0.1, 5.7), (3.4, 2.9, 2.6), "Leaf"), ((0.3, 0.3, 4.6), (3.9, 2.4, 1.4), "LeafDeep")], seg=4)
    a.report()
    return a


# --------------------------------------------------------------------------------------------------------------
def build_tree_pine_a():
    a = Asset("tree_pine_a")
    b = MB("pine_a_trunk")
    tube(b, [(0, 0, -0.06), (0.02, 0.0, 2.0), (0.0, 0.03, 6.0), (0.0, 0.0, 9.2)], [0.36, 0.26, 0.17, 0.05], seg=6, mat="Bark",
         cap_start=True, cap_end=True, jitter=0.04, seed=6)
    a.mesh(b, "Trunk")
    c = MB("pine_a_canopy")
    # (base z, radius, height)
    tiers = [(1.6, 2.35, 2.9), (3.1, 2.0, 2.7), (4.5, 1.7, 2.5), (5.8, 1.4, 2.3), (7.0, 1.1, 2.1), (8.1, 0.78, 1.9)]
    mats = ["LeafDeep", "Leaf", "LeafDeep", "Leaf", "LeafDeep", "Leaf"]
    for i, (z, r, h) in enumerate(tiers):
        cone(c, (0, 0, z), r, h, seg=8, mat=mats[i], star=0.13, jitter=0.05, seed=10 + i, rot=i * 0.5, apex_shift=((i % 3 - 1) * 0.06, 0.04 * (i % 2)))
    a.mesh(c, "Canopy", pivot=(0.0, 0.0, 1.6))
    a.report()
    return a


def build_tree_pine_a_lod():
    a = lod_tree("tree_pine_a_lod", 2.0, 0.34, 0.2, cones=[((0, 0, 1.6), 2.35, 4.6, "LeafDeep"), ((0, 0, 4.4), 1.6, 3.6, "Leaf"), ((0, 0, 6.9), 1.0, 3.2, "LeafDeep")], seg=5)
    a.report()
    return a


BUILDERS = {"palm_a": build_palm_a, "palm_a_lod": build_palm_a_lod, "tree_oak_a": build_tree_oak_a, "tree_oak_a_lod": build_tree_oak_a_lod,
            "tree_pine_a": build_tree_pine_a, "tree_pine_a_lod": build_tree_pine_a_lod}
run_builders(BUILDERS, globals().get("ONLY"))
