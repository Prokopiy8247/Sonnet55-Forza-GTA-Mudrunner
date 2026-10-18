"""lane10_small_b.py - bush_b, bush_c, hedge_segment, rock_b, rock_c, rock_d, boulder_large, cliff_chunk."""
import math, random


def rock_blob(b, c, radii, seed, subdiv=2, jitter=0.2, cuts=(), rot=0.0, top="RockPale", mid="RockMid", low="RockShade", ground=0.0, top_thresh=0.55, cap=None):
    return blob(b, c, radii, mat=mid, top_mat=top, top_thresh=top_thresh, bottom_mat=low, bottom_thresh=-0.25, subdiv=subdiv, jitter=jitter,
                seed=seed, rot_z=rot, ground=ground, cuts=cuts, cap_mat=cap)


def build_bush_b():
    a = Asset("bush_b")
    b = MB("bush_b_body")
    rnd = random.Random(71)
    # dense core so the shrub reads solid from every side
    blob(b, (0.0, 0.0, 0.4), (0.4, 0.4, 0.4), mat="LeafDeep", top_mat="Leaf", subdiv=1, jitter=0.12, seed=70, ground=0.0)
    n = 17
    for i in range(n):
        yaw = i * 137.5 + rnd.uniform(-12, 12)
        tier = i % 3
        p0 = (82, 68, 52)[tier] + rnd.uniform(-5, 5)
        bend = (24, 44, 64)[tier] + rnd.uniform(-6, 6)
        ln = (1.2, 1.3, 1.1)[tier] * rnd.uniform(0.9, 1.08)
        w = (0.15, 0.17, 0.17)[tier]
        d = (math.sin(math.radians(yaw)), math.cos(math.radians(yaw)))
        m = ("Leaf", "LeafLight", "LeafDeep")[(i + tier) % 3]
        frond(b, (d[0] * 0.12, d[1] * 0.12, 0.18 + 0.12 * tier), yaw, p0, bend, ln, w, steps=3, mat=m, fold=0.5, profile=[0.55, 1.0, 0.55], sag=0.05)
    a.mesh(b, "Body")
    a.report()
    return a


def build_bush_c():
    a = Asset("bush_c")
    b = MB("bush_c_body")
    kw = dict(mat="Leaf", top_mat="LeafLight", top_thresh=0.5, bottom_mat="LeafDeep", bottom_thresh=-0.3, jitter=0.07, ground=0.0)
    blobs = [((0.0, 0.0, 0.62), (0.78, 0.7, 0.68), 2, 81), ((-0.58, 0.2, 0.42), (0.5, 0.46, 0.42), 1, 82), ((0.55, -0.18, 0.4), (0.5, 0.46, 0.42), 1, 83), ((0.05, 0.5, 0.4), (0.42, 0.4, 0.38), 1, 84)]
    for c, r, sd, sed in blobs:
        blob(b, c, r, subdiv=sd, seed=sed, **kw)
    rnd = random.Random(5)
    n = 0
    for c, r, sd, sed in blobs:
        for k in range(6):
            th = rnd.uniform(0, 2 * math.pi)
            ph = rnd.uniform(0.1, 1.15)
            d = Vector((math.sin(ph) * math.cos(th), math.sin(ph) * math.sin(th), math.cos(ph)))
            p = (c[0] + d.x * r[0] * 1.02, c[1] + d.y * r[1] * 1.02, c[2] + d.z * r[2] * 1.02)
            octa(b, p, 0.14, mat="Accent" if (n % 3) else "FlowerPink", sq=0.85, rot=rnd.uniform(0, 1.5))
            n += 1
    a.mesh(b, "Body")
    a.report()
    return a


def build_hedge_segment():
    a = Asset("hedge_segment")
    b = MB("hedge_body")
    rnd = random.Random(9)
    xs = [-1.5 + 3.0 * k / 9 for k in range(10)]
    prof = [(-0.4, 0.0), (0.4, 0.0), (0.42, 0.8), (0.3, 1.1), (-0.3, 1.1), (-0.42, 0.8)]
    rings = []
    for k, x in enumerate(xs):
        edge = 0 < k < len(xs) - 1
        dz = rnd.uniform(-0.07, 0.07) if edge else -0.05
        dy = rnd.uniform(-0.04, 0.04) if edge else -0.03
        ring = []
        for i, (py, pz) in enumerate(prof):
            zz = pz + (dz if pz > 0.5 else 0.0)
            yy = py * (1.0 + dy) + (dy if pz > 0.5 else 0.0)
            ring.append(Vector((x, yy, zz)))
        rings.append(ring)

    def mf(k, i):
        if i == 3:
            return "LeafLight"
        if i in (2, 4):
            return "LeafLight" if (k + i) % 2 == 0 else "Leaf"
        if i in (0, 5):
            return "LeafDeep"
        return "Leaf"
    loft_mats(b, rings, [mf] * (len(rings) - 1), cap_start="Leaf", cap_end="Leaf")
    a.mesh(b, "Body")
    a.report()
    return a


def build_rock_b():
    a = Asset("rock_b")
    b = MB("rock_b_body")
    rock_blob(b, (0, 0, 0.3), (0.85, 0.62, 0.42), seed=91, jitter=0.18, cuts=[((0, 0, 1), 0.33), ((1, 0.5, 0.0), 0.7)], rot=-0.3)
    rock_blob(b, (-0.8, 0.5, 0.16), (0.3, 0.28, 0.22), seed=92, subdiv=1, jitter=0.2, cuts=[((0, 0, 1), 0.17)])
    rock_blob(b, (0.55, -0.62, 0.12), (0.22, 0.2, 0.17), seed=93, subdiv=1, jitter=0.2, cuts=[((0, 0, 1), 0.12)])
    a.mesh(b, "Body")
    a.report()
    return a


def build_rock_c():
    a = Asset("rock_c")
    b = MB("rock_c_body")
    rock_blob(b, (0, 0, 0.62), (0.58, 0.5, 0.78), seed=101, jitter=0.2, rot=0.7,
              cuts=[((0.6, 0.3, 1.0), 0.8), ((-1.0, 0.2, 0.3), 0.5), ((0.3, -1.0, 0.2), 0.45), ((1.0, 0.5, -0.1), 0.52)])
    rock_blob(b, (0.62, 0.2, 0.28), (0.34, 0.3, 0.36), seed=102, subdiv=1, jitter=0.22, rot=0.3, cuts=[((0.3, 0.2, 1.0), 0.33)])
    a.mesh(b, "Body")
    a.report()
    return a


def build_rock_d():
    a = Asset("rock_d")
    b = MB("rock_d_body")
    rock_blob(b, (-0.3, 0.05, 0.28), (0.5, 0.45, 0.36), seed=111, jitter=0.2, cuts=[((0.2, 0.1, 1.0), 0.34)], rot=0.2)
    rock_blob(b, (0.4, 0.22, 0.22), (0.38, 0.34, 0.3), seed=112, jitter=0.2, cuts=[((-0.3, 0.1, 1.0), 0.27)], rot=1.0)
    rock_blob(b, (0.1, -0.45, 0.16), (0.3, 0.27, 0.22), seed=113, subdiv=1, jitter=0.2, cuts=[((0, 0, 1), 0.2)], rot=2.0)
    rock_blob(b, (-0.62, -0.38, 0.1), (0.2, 0.18, 0.14), seed=114, subdiv=1, jitter=0.2, cuts=[((0, 0, 1), 0.12)])
    a.mesh(b, "Body")
    a.report()
    return a


def build_boulder_large():
    a = Asset("boulder_large")
    b = MB("boulder_body")
    rock_blob(b, (0, 0, 1.1), (1.95, 1.7, 1.75), seed=123, jitter=0.24, rot=0.5, cap="Leaf", top_thresh=0.5,
              cuts=[((1.0, -0.5, 0.2), 1.75), ((-1.0, 0.3, 0.1), 1.8), ((0.1, 1.0, 0.3), 1.55)])
    rock_blob(b, (1.9, 0.9, 0.5), (0.8, 0.7, 0.62), seed=122, subdiv=2, jitter=0.2, rot=1.0, cuts=[((0.2, 0.1, 1.0), 0.6)])
    rock_blob(b, (-1.7, -0.9, 0.38), (0.6, 0.55, 0.48), seed=123, subdiv=1, jitter=0.2, rot=2.0, cuts=[((0, 0, 1), 0.45)])
    a.mesh(b, "Body")
    a.report()
    return a


def build_cliff_chunk():
    a = Asset("cliff_chunk")
    b = MB("cliff_body")
    rnd = random.Random(131)
    N = 12
    st = [(0.0, 1.1, 0.0), (1.3, 1.0, 0.05), (1.55, 0.9, 0.1), (2.8, 0.86, 0.2), (3.05, 0.76, 0.3), (4.0, 0.72, 0.4), (4.3, 0.62, 0.5), (5.2, 0.58, 0.55)]
    base = [(2 * math.pi * i / N + 0.2, 1.0 + rnd.uniform(-0.1, 0.1)) for i in range(N)]
    rings = []
    ledge_w = [[rnd.uniform(0.2, 1.4) for _ in range(N)] for _ in st]
    for si, (z, sc0, drift) in enumerate(st):
        ring = []
        for i, (ang, k) in enumerate(base):
            sc = sc0
            if si in (2, 4, 6):
                sc = st[si - 1][1] + (sc0 - st[si - 1][1]) * ledge_w[si][i]
            kk = k * (1.0 + 0.06 * (-1) ** i) * (1.0 + rnd.uniform(-0.07, 0.07))
            x = 3.0 * math.cos(ang) * sc * kk + drift * 0.5
            y = 1.9 * math.sin(ang) * sc * kk - drift * 0.1
            if y > 1.1 * sc:
                y = 1.1 * sc
            zz = z + (rnd.uniform(-0.12, 0.12) if 0 < si < len(st) - 1 else 0)
            if si == len(st) - 1:
                zz = z + 0.35 * math.sin(ang + 0.6) + rnd.uniform(-0.1, 0.1)
            ring.append(Vector((x, y, zz)))
        rings.append(ring)
    mats = ["RockMid", "RockPale", "RockShade", "RockPale", "RockMid", "RockPale", "RockMid"]
    loft_mats(b, rings, mats, cap_start="RockShade", cap_end="Leaf")
    rock_blob(b, (2.9, 1.0, 0.45), (0.9, 0.75, 0.6), seed=132, subdiv=1, jitter=0.2, cuts=[((0, 0, 1), 0.5)])
    rock_blob(b, (-2.6, 1.1, 0.35), (0.7, 0.6, 0.5), seed=133, subdiv=1, jitter=0.2, cuts=[((0, 0, 1), 0.4)])
    a.mesh(b, "Body")
    a.report()
    return a


BUILDERS = {"bush_b": build_bush_b, "bush_c": build_bush_c, "hedge_segment": build_hedge_segment, "rock_b": build_rock_b, "rock_c": build_rock_c,
            "rock_d": build_rock_d, "boulder_large": build_boulder_large, "cliff_chunk": build_cliff_chunk}
run_builders(BUILDERS, globals().get("ONLY"))
