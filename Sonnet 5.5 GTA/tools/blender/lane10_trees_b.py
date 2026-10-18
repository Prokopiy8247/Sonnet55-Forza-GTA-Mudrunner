"""lane10_trees_b.py - palm_b, tree_oak_b, tree_pine_b, tree_birch, tree_dead (+ _lod impostors)."""
import math, random


def build_palm_b():
    a = Asset("palm_b")
    H = 6.4

    def tp(t):
        return (0.35 * math.sin(t * 2.2), 0.45 * t * t, H * t)
    ts = [0, 0.1, 0.26, 0.44, 0.62, 0.8, 1.0]
    pts = [tp(t) for t in ts]
    pts[0] = (0, 0, -0.1)
    radii = [0.62, 0.4, 0.34, 0.31, 0.29, 0.27, 0.26]
    b = MB("palm_b_trunk")
    tube(b, pts, radii, seg=7, mat="BarkPale", cap_start=True, cap_end=False, rot=0.1, jitter=0.03, seed=8,
         mats=["BarkPale", "BarkMid", "BarkPale", "BarkMid", "BarkPale", "BarkMid"])
    top = pts[-1]
    cs = [(top[0], top[1], top[2] - 0.05), (top[0], top[1] + 0.02, top[2] + 0.55), (top[0], top[1] + 0.03, top[2] + 1.0)]
    tube(b, cs, [0.3, 0.27, 0.2], seg=7, mat="PalmLeaf", cap_start=False, cap_end=True, rot=0.1)
    a.mesh(b, "Trunk")

    cx, cy, cz = top[0], top[1] + 0.03, top[2] + 0.95
    c = MB("palm_b_canopy")
    for i, ang in enumerate((30, 160, 280)):
        r = math.radians(ang)
        for k in range(2):
            blob(c, (cx + math.cos(r) * (0.3 + 0.08 * k), cy + math.sin(r) * (0.3 + 0.08 * k), cz - 0.35 - 0.2 * k), (0.13, 0.13, 0.16),
                 mat="Accent", subdiv=1, jitter=0.08, seed=40 + i * 3 + k)
    rnd = random.Random(17)
    PL = [0.3, 0.9, 0.45, 0.95, 0.45, 0.6]
    PR = [0.3, 0.55, 1.0, 0.5, 0.9, 0.4]
    plan = [
        (0, 62, 70, 3.3, 0.55, "PalmLeaf"), (72, 58, 74, 3.4, 0.56, "PalmLeafLt"), (144, 64, 68, 3.3, 0.55, "PalmLeaf"),
        (216, 60, 72, 3.4, 0.56, "PalmLeafLt"), (288, 62, 70, 3.3, 0.55, "PalmLeaf"),
        (36, 36, 92, 3.6, 0.6, "PalmLeafLt"), (108, 32, 96, 3.7, 0.62, "PalmLeaf"), (180, 38, 90, 3.6, 0.6, "PalmLeafLt"),
        (252, 30, 98, 3.7, 0.62, "PalmLeaf"), (324, 34, 94, 3.6, 0.6, "PalmLeafLt"),
    ]
    for yaw, p0, bend, ln, w, m in plan:
        y = yaw + rnd.uniform(-7, 7)
        d = (math.sin(math.radians(y)), math.cos(math.radians(y)), 0)
        frond(c, (cx + d[0] * 0.14, cy + d[1] * 0.14, cz), y, p0, bend, ln * 1.12, w * 1.1, steps=5, mat=m, fold=0.4,
              profile=[0.3, 0.9, 1.0, 0.7, 0.4], profile_r=[0.3, 0.6, 0.95, 0.8, 0.45], sag=0.15)
    a.mesh(c, "Canopy", pivot=(cx, cy, cz))
    a.report()
    return a


def build_palm_b_lod():
    a = lod_tree("palm_b_lod", 7.4, 0.5, 0.28, lean=(0.3, 0.3), trunk_mat="BarkPale",
                 fronds=[((0.3, 0.33, 7.4), y, 50, 80, 3.5, 0.8, "PalmLeaf") for y in (0, 90, 180, 270)] +
                 [((0.3, 0.33, 7.35), y, 25, 100, 3.7, 0.9, "PalmLeafLt") for y in (45, 135, 225)])
    a.report()
    return a


# --------------------------------------------------------------------------------------------------------------
def build_tree_oak_b():
    a = Asset("tree_oak_b")
    b = MB("oak_b_trunk")
    tube(b, [(0, 0, -0.06), (-0.05, 0.05, 1.3), (-0.12, 0.08, 2.6), (-0.1, 0.1, 3.8)], [0.7, 0.45, 0.38, 0.34], seg=7, mat="Bark",
         cap_start=True, cap_end=True, rot=0.1, jitter=0.05, seed=4)
    tube(b, [(-0.1, 0.1, 3.0), (-1.1, 0.4, 4.3), (-2.0, 0.6, 5.4)], [0.26, 0.19, 0.1], seg=4, mat="Bark", cap_start=False, cap_end=True)
    tube(b, [(-0.1, 0.1, 3.2), (0.9, -0.2, 4.5), (1.9, -0.4, 5.6)], [0.24, 0.17, 0.1], seg=4, mat="Bark", cap_start=False, cap_end=True)
    tube(b, [(-0.1, 0.12, 3.6), (-0.2, 0.5, 5.0), (0.1, 0.7, 6.2)], [0.24, 0.16, 0.09], seg=4, mat="Bark", cap_start=False, cap_end=True)
    for i, ang in enumerate((20, 110, 200, 290)):
        r = math.radians(ang)
        tube(b, [(math.cos(r) * 0.95, math.sin(r) * 0.95, 0.0), (math.cos(r) * 0.5, math.sin(r) * 0.5, 0.55), (math.cos(r) * 0.25, math.sin(r) * 0.25, 1.2)],
             [0.12, 0.17, 0.26], seg=3, mat="Bark", cap_start=True, cap_end=False)
    a.mesh(b, "Trunk")
    c = MB("oak_b_canopy")
    kw = dict(mat="Leaf", top_mat="LeafLight", top_thresh=0.5, bottom_mat="LeafDeep", bottom_thresh=-0.3, jitter=0.12)
    blob(c, (-0.1, 0.2, 7.4), (3.3, 3.1, 2.7), subdiv=2, seed=31, **kw)
    blob(c, (-2.6, 0.5, 5.9), (2.3, 2.1, 1.7), subdiv=2, seed=32, **kw)
    blob(c, (2.5, -0.4, 6.2), (2.4, 2.2, 1.8), subdiv=2, seed=33, **kw)
    blob(c, (0.5, -2.3, 6.5), (1.9, 1.7, 1.4), subdiv=1, seed=34, **kw)
    blob(c, (-0.4, 2.4, 6.7), (1.9, 1.7, 1.4), subdiv=1, seed=35, **kw)
    a.mesh(c, "Canopy", pivot=(-0.1, 0.1, 3.4))
    a.report()
    return a


def build_tree_oak_b_lod():
    a = lod_tree("tree_oak_b_lod", 4.0, 0.6, 0.32, blobs=[((-0.1, 0.2, 7.3), (3.6, 3.2, 2.9), "Leaf"), ((0, 0.2, 5.8), (4.6, 2.9, 1.8), "LeafDeep")], seg=4)
    a.report()
    return a


# --------------------------------------------------------------------------------------------------------------
def build_tree_pine_b():
    a = Asset("tree_pine_b")
    b = MB("pine_b_trunk")
    tube(b, [(0, 0, -0.06), (0.03, 0.0, 2.5), (0.0, 0.03, 7.5), (0.0, 0.0, 11.3)], [0.4, 0.28, 0.17, 0.05], seg=6, mat="Bark",
         cap_start=True, cap_end=True, jitter=0.04, seed=9)
    a.mesh(b, "Trunk")
    c = MB("pine_b_canopy")
    tiers = [(1.8, 2.1, 3.3), (3.4, 1.9, 3.0), (4.9, 1.7, 2.8), (6.3, 1.45, 2.6), (7.6, 1.2, 2.4), (8.8, 0.95, 2.2), (9.8, 0.68, 2.2)]
    mats = ["Leaf", "LeafDeep", "Leaf", "LeafDeep", "Leaf", "LeafDeep", "Leaf"]
    for i, (z, r, h) in enumerate(tiers):
        bell(c, (0, 0, z), r, h, seg=7, mat=mats[i], mid_r=0.5, mid_h=0.38, star=0.14, jitter=0.05, seed=50 + i, rot=i * 0.7,
             apex_shift=((i % 3 - 1) * 0.05, 0.04 * (i % 2)))
    a.mesh(c, "Canopy", pivot=(0.0, 0.0, 1.8))
    a.report()
    return a


def build_tree_pine_b_lod():
    a = lod_tree("tree_pine_b_lod", 2.0, 0.38, 0.22, cones=[((0, 0, 1.8), 2.1, 5.2, "Leaf"), ((0, 0, 5.2), 1.5, 4.2, "LeafDeep"), ((0, 0, 8.5), 0.95, 3.6, "Leaf")], seg=5)
    a.report()
    return a


# --------------------------------------------------------------------------------------------------------------
def build_tree_birch():
    a = Asset("tree_birch")
    b = MB("birch_trunk")
    zs = [-0.05, 0.7, 0.82, 1.7, 1.82, 2.8, 2.92, 4.0, 4.1, 5.2]
    pts = [(0.25 * math.sin(z * 0.45), 0.12 * math.sin(z * 0.9 + 1), z) for z in zs]
    radii = [0.26, 0.21, 0.21, 0.18, 0.18, 0.155, 0.155, 0.13, 0.13, 0.1]
    mats = ["BirchWhite", "BarkDark", "BirchWhite", "BarkDark", "BirchWhite", "BarkDark", "BirchWhite", "BarkDark", "BirchWhite"]
    tube(b, pts, radii, seg=6, mat="BirchWhite", cap_start=True, cap_end=True, rot=0.2, jitter=0.03, seed=12, mats=mats)
    p4 = pts[7]
    tube(b, [(p4[0], p4[1], 3.9), (p4[0] - 0.5, p4[1] + 0.1, 4.8), (p4[0] - 0.9, p4[1] + 0.1, 5.7)], [0.1, 0.07, 0.04], seg=4, mat="BirchWhite",
         cap_start=False, cap_end=True)
    tube(b, [(p4[0], p4[1], 4.3), (p4[0] + 0.5, p4[1] - 0.1, 5.3), (p4[0] + 0.8, p4[1], 6.2)], [0.09, 0.06, 0.04], seg=4, mat="BirchWhite",
         cap_start=False, cap_end=True)
    a.mesh(b, "Trunk")
    c = MB("birch_canopy")
    kw = dict(mat="LeafLight", top_mat="LeafYellow", top_thresh=0.55, bottom_mat="Leaf", bottom_thresh=-0.3, jitter=0.14, subdiv=1)
    blobs = [((0.0, 0.0, 6.9), (1.1, 1.0, 1.3)), ((-0.9, 0.2, 5.6), (1.0, 0.9, 1.0)), ((0.9, -0.3, 6.0), (1.0, 0.95, 1.1)),
             ((0.2, 0.9, 5.6), (0.9, 0.85, 0.9)), ((-0.3, -0.9, 6.5), (0.95, 0.9, 1.0)), ((-0.7, 0.4, 7.6), (0.8, 0.75, 0.9)),
             ((0.7, 0.3, 7.5), (0.8, 0.8, 0.9)), ((0.0, 0.0, 8.3), (0.65, 0.65, 0.7))]
    for i, (cc, rr) in enumerate(blobs):
        blob(c, (cc[0] + 0.15, cc[1], cc[2]), rr, seed=60 + i, **kw)
    a.mesh(c, "Canopy", pivot=(0.1, 0.0, 4.0))
    a.report()
    return a


def build_tree_birch_lod():
    a = lod_tree("tree_birch_lod", 6.0, 0.24, 0.11, trunk_mat="BirchWhite",
                 blobs=[((0.15, 0, 6.8), (1.6, 1.4, 1.9), "LeafLight"), ((0.15, 0.2, 5.6), (1.4, 1.3, 1.0), "Leaf")], seg=4)
    a.report()
    return a


# --------------------------------------------------------------------------------------------------------------
def build_tree_dead():
    a = Asset("tree_dead")
    rnd = random.Random(77)
    b = MB("dead_trunk")
    pts = [(0, 0, -0.06), (0.1, 0.05, 1.2), (-0.15, 0.1, 2.5), (0.05, -0.05, 3.8), (0.25, 0.0, 4.9)]
    tube(b, pts, [0.48, 0.34, 0.27, 0.19, 0.05], seg=6, mat="BarkPale", cap_start=True, cap_end=False, rot=0.3, jitter=0.07, seed=5,
         mats=["BarkPale", "BarkPale", "BarkMid", "BarkPale"])
    for i, ang in enumerate((60, 190, 300)):
        r = math.radians(ang)
        tube(b, [(math.cos(r) * 0.8, math.sin(r) * 0.8, 0.0), (math.cos(r) * 0.42, math.sin(r) * 0.42, 0.35), (math.cos(r) * 0.2, math.sin(r) * 0.2, 0.8)],
             [0.1, 0.13, 0.2], seg=3, mat="BarkMid", cap_start=True, cap_end=False)
    limbs = [((-0.1, 0.1, 2.2), (-1.0, 0.5, 2.9), (-1.9, 0.5, 4.0), 0.19),
             ((0.0, 0.05, 2.9), (1.0, -0.3, 3.3), (1.9, -0.6, 4.6), 0.18),
             ((0.0, -0.05, 3.8), (-0.5, -0.7, 4.7), (-0.9, -1.2, 5.6), 0.11),
             ((0.1, 0.0, 4.2), (0.7, 0.5, 5.1), (1.0, 0.9, 6.1), 0.1)]
    ends = []
    for p0, p1, p2, r0 in limbs:
        tube(b, [p0, p1, p2], [r0, r0 * 0.62, 0.0], seg=4, mat="BarkPale", cap_start=False, cap_end=False)
        ends.append((p1, p2))
    tube(b, [(0.15, 0.1, 1.0), (0.7, 0.2, 1.4)], [0.1, 0.06], seg=4, mat="BarkDark", cap_start=False, cap_end=True)
    a.mesh(b, "Trunk")
    c = MB("dead_twigs")
    twig_seeds = [(1, 0.5), (1, 0.8), (1, 1.0), (0, 0.9), (0, 0.9), (3, 0.9), (3, 1.0), (2, 0.9), (2, 1.0), (2, 0.6), (3, 0.6), (0, 0.9)]
    for i, (li, f) in enumerate(twig_seeds):
        p1, p2 = ends[li]
        base = Vector(p1).lerp(Vector(p2), f)
        d = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(0.2, 1.0))).normalized()
        L = rnd.uniform(0.9, 1.5)
        mid = base + d * (L * 0.5) + Vector((rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15), 0))
        tip = base + d * L + Vector((0, 0, rnd.uniform(-0.1, 0.25)))
        tube(c, [tuple(base), tuple(mid), tuple(tip)], [0.055, 0.032, 0.0], seg=3, mat="BarkDark" if i % 3 == 0 else "BarkPale", cap_start=False, cap_end=False)
    a.mesh(c, "Canopy", pivot=(0.1, 0.0, 3.5))
    a.report()
    return a


BUILDERS = {"palm_b": build_palm_b, "palm_b_lod": build_palm_b_lod, "tree_oak_b": build_tree_oak_b, "tree_oak_b_lod": build_tree_oak_b_lod,
            "tree_pine_b": build_tree_pine_b, "tree_pine_b_lod": build_tree_pine_b_lod, "tree_birch": build_tree_birch,
            "tree_birch_lod": build_tree_birch_lod, "tree_dead": build_tree_dead}
run_builders(BUILDERS, globals().get("ONLY"))
