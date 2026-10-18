"""lane14_kelp_rocks.py - kelp_a (tall strands, node Blades), kelp_b (short seaweed clump), sea_rock_a, sea_rock_b (algae covered).
Origin = base centre on the sea bed. Set ONLY=[...] before exec to build a subset."""
import random
import math
from mathutils import Vector, Matrix

CATU = "GTA_GODOT/Nature"


def strand(b, base, H, rr, amp, w0, mats, nseg=7, twist=28.0, lean=(0.0, 0.0), leaves=True):
    pts, widths = [], []
    ph = rr.uniform(0, 6.28)
    ph2 = rr.uniform(0, 6.28)
    for k in range(nseg + 1):
        t = k / nseg
        z = base[2] + H * t
        x = base[0] + lean[0] * t * t * H + amp * math.sin(t * 5.0 + ph) * t
        y = base[1] + lean[1] * t * t * H + amp * 0.8 * math.sin(t * 4.2 + ph2) * t
        pts.append((x, y, z))
        wd = w0 * (0.55 + 0.55 * math.sin(min(1, t * 1.6) * math.pi * 0.5)) * (1.0 - 0.9 * t ** 2.5)
        widths.append(max(wd, 0.0) if k < nseg else 0.0)
    ms = [mats[0] if k < 2 else (mats[1] if k < nseg - 2 else mats[2]) for k in range(nseg)]
    side0 = (math.cos(ph), math.sin(ph), 0)
    ribbon(b, pts, widths, mats[1], side0=side0, twist=twist, mats=ms)
    if leaves:
        for k, sg in ((2, 1), (3, -1), (4, 1), (5, -1)):
            p = Vector(pts[k])
            nxt = Vector(pts[k + 1])
            t_ = (nxt - p).normalized()
            s_ = Vector(side0)
            s_ = Matrix.Rotation(math.radians(twist * k + 90), 3, t_) @ (s_ - t_ * s_.dot(t_))
            s_.normalize()
            tip = p + s_ * sg * (0.22 - 0.02 * k) + t_ * 0.32
            b.pq([p, p + t_ * 0.18, tip], s_.cross(t_), mats[2])


def build_kelp_a():
    A = A14("kelp_a", 8, CATU, spacing=12.0)
    rr = random.Random(11)
    # holdfast: rocks + root tendrils
    h = HB("kelp_a_hold")
    blob(h, (0, 0, 0), (0.5, 0.42, 0.2), seed=4, subdiv=1, jitter=.16, ground=0.0, mats=("UWAlgaeDk", "UWRock", "UWRockDk"))
    blob(h, (0.3, -0.18, 0), (0.22, 0.2, 0.12), seed=5, subdiv=1, jitter=.16, ground=0.0, mats=("UWAlgaeDk", "UWRock", "UWRockDk"))
    for k in range(5):
        a = 2 * math.pi * k / 5 + 0.4
        limb(h, (math.cos(a) * 0.08, math.sin(a) * 0.08, 0.2), (math.cos(a) * 0.4, math.sin(a) * 0.4, 0.04), 0.035, 0.018, 4, "KelpOlive", tip=True)
    A.mesh(h, "Body", uv=None)
    # blades (separate mesh, origin at the base so Godot can sway it with a vertex shader keyed to height)
    b = HB("kelp_a_blades")
    n = 9
    for i in range(n):
        ang = 2 * math.pi * i / n + rr.uniform(-.25, .25)
        r0 = 0.04 + 0.2 * (i % 3) / 2.0
        H = [3.0, 2.5, 2.8, 2.2, 2.9, 2.4, 2.65, 2.0, 2.75][i]
        ox, oy = math.cos(ang), math.sin(ang)
        strand(b, (ox * r0, oy * r0, 0.12), H, rr, 0.26, 0.3, ["KelpDark", "KelpGreen", "KelpLight"] if i % 2 else ["KelpDark", "KelpOlive", "KelpLight"], nseg=8,
               lean=(ox * rr.uniform(.07, .17), oy * rr.uniform(.07, .17)), twist=22)
    A.mesh(b, "Blades", uv=None)
    return A


def build_kelp_b():
    A = A14("kelp_b", 9, CATU, spacing=12.0)
    rr = random.Random(23)
    b = HB("kelp_b_body")
    blob(b, (0, 0, 0), (0.3, 0.26, 0.1), seed=8, subdiv=1, jitter=.16, ground=0.0, mats=("UWAlgaeDk", "UWRock", "UWRockDk"))
    n = 15
    for i in range(n):
        a = 2 * math.pi * i / n + rr.uniform(-.2, .2)
        r = 0.06 + 0.13 * rr.random()
        H = rr.uniform(0.42, 0.85)
        lean = (math.cos(a) * 0.35, math.sin(a) * 0.35)
        col = ["KelpOlive", "KelpGreen", "KelpLight"] if i % 2 else ["KelpDark", "KelpOlive", "KelpGreen"]
        strand(b, (math.cos(a) * r, math.sin(a) * r, 0.05), H, rr, 0.05, 0.1, col, nseg=3, twist=40, lean=(lean[0] * 0.6, lean[1] * 0.6), leaves=False)
    A.mesh(b, "Body", uv=None)
    return A


def tufts(b, centre, n, h, spread, seed, cols=("UWAlgaeDk", "UWAlgae", "UWAlgaeLt"), top_z=None):
    rr = random.Random(seed)
    for i in range(n):
        a = rr.uniform(0, 6.28)
        r = spread * rr.random()
        x, y = centre[0] + math.cos(a) * r, centre[1] + math.sin(a) * r
        z = centre[2]
        H = h * rr.uniform(0.6, 1.0)
        lean = rr.uniform(0.1, 0.3)
        ribbon(b, [(x, y, z), (x + math.cos(a) * lean * 0.4, y + math.sin(a) * lean * 0.4, z + H * 0.55), (x + math.cos(a) * lean, y + math.sin(a) * lean, z + H)],
               [0.07, 0.065, 0.0], cols[1], side0=(-math.sin(a), math.cos(a), 0), twist=10, mats=[cols[0], cols[2]])


def build_sea_rock_a():
    A = A14("sea_rock_a", 10, CATU, spacing=12.0)
    b = HB("sea_rock_a_body")
    M = ("UWAlgae", "UWRock", "UWRockDk")
    blob(b, (0, 0, 0), (0.95, 0.78, 0.7), seed=41, subdiv=1, jitter=.22, ground=0.0, mats=M, rot=0.5, top=0.45, squash_top=0.12)
    blob(b, (0.82, 0.38, 0), (0.45, 0.4, 0.34), seed=42, subdiv=1, jitter=.2, ground=0.0, mats=M, rot=1.2)
    blob(b, (-0.7, -0.45, 0), (0.4, 0.34, 0.28), seed=43, subdiv=1, jitter=.22, ground=0.0, mats=M, rot=2.0)
    blob(b, (0.0, -0.78, 0), (0.28, 0.24, 0.18), seed=44, subdiv=0, jitter=.2, ground=0.0, mats=("UWAlgaeLt", "UWRock", "UWRockDk"))
    tufts(b, (0.1, 0.1, 0.6), 10, 0.6, 0.5, 2)
    tufts(b, (0.78, 0.4, 0.3), 5, 0.4, 0.22, 3)
    tufts(b, (-0.7, -0.45, 0.25), 4, 0.35, 0.2, 4)
    A.mesh(b, "Body", uv=None)
    return A


def build_sea_rock_b():
    A = A14("sea_rock_b", 11, CATU, spacing=12.0)
    b = HB("sea_rock_b_body")
    M = ("UWAlgae", "UWRock", "UWRockDk")
    blob(b, (-0.55, 0.0, 0), (1.05, 0.9, 0.5), seed=51, subdiv=1, jitter=.2, ground=0.0, mats=M, rot=0.2, top=0.4, squash_top=0.4)
    blob(b, (0.85, 0.15, 0), (0.7, 0.62, 0.38), seed=52, subdiv=1, jitter=.2, ground=0.0, mats=M, rot=0.9, top=0.4, squash_top=0.35)
    blob(b, (0.1, -0.55, 0), (0.28, 0.26, 1.0), seed=53, subdiv=1, jitter=.2, ground=0.0, mats=("UWAlgaeLt", "UWRock", "UWRockDk"), rot=0.3, top=0.7)
    tufts(b, (-0.5, 0.1, 0.3), 11, 0.55, 0.65, 5)
    tufts(b, (0.85, 0.2, 0.28), 6, 0.4, 0.38, 6)
    tufts(b, (0.1, -0.55, 0.9), 3, 0.3, 0.12, 7, cols=("UWAlgaeDk", "KelpGreen", "KelpLight"))
    A.mesh(b, "Body", uv=None)
    return A


BUILD = {"kelp_a": (build_kelp_a, 400), "kelp_b": (build_kelp_b, 400), "sea_rock_a": (build_sea_rock_a, 400), "sea_rock_b": (build_sea_rock_b, 400)}
for _id, (_fn, _bud) in BUILD.items():
    if globals().get("ONLY") and _id not in ONLY:
        continue
    _fn().report(_bud)
