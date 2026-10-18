"""Extra test meshes for the road / surface test sheet (plain python, registers into materials_testmesh.MESHES on import).  Owner: agent M-B.

  SM_Test_RoadReg    regional 2-lane road strip with the REAL chunk UV contract of Exports/Roads/chunks.json (P=3.5, lw=3.5, shoulders to 5.2)
  SM_Test_RoadHwy    highway (2 lanes per direction, median 1.0, P=7.7, lw=3.6, shoulders to 10.2)
  SM_Test_RoadDirt   dirt road (P=2.5, shoulders to 3.6)
  SM_Test_RoadPad    junction pad (UV2 = (0, 3): no markings)
  SM_Test_Box        6 x 6 x 3 m four-wall block, metric UV0 = UV1, origin at the base centre
  SM_Test_Roof       gable roof (ridge along X, 6.4 x 6.4, rise 1.8 m), metric UV0 = UV1 along the slope
  SM_Test_Curb       10 m kerb (0.3 wide, 0.15 high) with UV1 = (lateral m, s m)
All geometry in cm in file space (UE x = file x, UE y = -file y).
"""
import math
import os
import sys

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", "materials_testmesh_surface.py")))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import materials_testmesh as TM  # noqa: E402


def road(length_m, B, P, lw, med, profile, step_m=4.0):
    """profile: list of (|d|, zone) from the centre line outwards, mirrored; (0, z) first when there is no median, else (med/2, z).
    Strips along +X; lateral d (right = +) maps to file -Y."""
    pts = []
    for ad, z in reversed(profile):          # right side (d > 0), outermost first  -> file y ascending
        pts.append((ad, z))
    for i, (ad, z) in enumerate(profile):    # left side (d < 0), innermost first
        if i == 0 and ad == 0.0:
            continue                         # no median: the centre point is shared
        pts.append((-ad, z))
    polys = []
    n = max(1, int(round(length_m / step_m)))
    for k in range(n):
        s0, s1 = k * length_m / n, (k + 1) * length_m / n
        for j in range(len(pts) - 1):
            (d0, z0), (d1, z1) = pts[j], pts[j + 1]
            if abs(d0 - d1) < 1e-6:
                continue                     # hard edge (zone jump at the same lateral position)
            y0, y1 = -d0 * 100.0, -d1 * 100.0
            v = [(s0 * 100.0, y0, 0), (s1 * 100.0, y0, 0), (s1 * 100.0, y1, 0), (s0 * 100.0, y1, 0)]
            uv0 = [((B - d0) / (2 * B), s0 / 10.0), ((B - d0) / (2 * B), s1 / 10.0), ((B - d1) / (2 * B), s1 / 10.0), ((B - d1) / (2 * B), s0 / 10.0)]
            uv1 = [(d0, s0), (d0, s1), (d1, s1), (d1, s0)]
            uv2 = [(P, lw)] * 4
            uv3 = [(med, z0), (med, z0), (med, z1), (med, z1)]
            polys.append({"v": v, "n": (0, 0, 1), "uv0": uv0, "uv1": uv1, "uv2": uv2, "uv3": uv3})
    return polys


def road_reg():
    return road(48.0, 5.2, 3.5, 3.5, 0.0, [(0.0, 1.0), (1.75, 1.0), (3.5, 1.0), (4.3, 0.83), (5.2, 0.66)])


def road_hwy():
    return road(48.0, 10.2, 7.7, 3.6, 1.0, [(0.5, 0.33), (0.5, 1.0), (2.3, 1.0), (4.1, 1.0), (5.9, 1.0), (7.7, 1.0), (9.0, 0.82), (10.2, 0.66)])


def road_dirt():
    return road(48.0, 3.6, 2.5, 2.5, 0.0, [(0.0, 1.0), (1.25, 1.0), (2.5, 1.0), (3.1, 0.83), (3.6, 0.66)])


def road_pad():
    return road(24.0, 6.0, 0.0, 3.0, 0.0, [(0.0, 1.0), (3.0, 1.0), (6.0, 0.66)])


def _quad(p0, p1, p2, p3, n, w_m, h_m):
    """Wall/roof quad with metric UV (u along p0->p1, v along p0->p3 measured downward from p3 so textures stand up)."""
    return {"v": [p0, p1, p2, p3], "n": n, "uv0": [(0.0, h_m), (w_m, h_m), (w_m, 0.0), (0.0, 0.0)], "uv1": [(0.0, h_m), (w_m, h_m), (w_m, 0.0), (0.0, 0.0)]}


def box_walls(a=6.0, b=6.0, h=3.0):
    A, B_, H = a * 50.0, b * 50.0, h * 100.0
    polys = [
        _quad((-A, -B_, 0), (A, -B_, 0), (A, -B_, H), (-A, -B_, H), (0, -1, 0), a, h),   # -Y wall (UE +Y side)
        _quad((A, -B_, 0), (A, B_, 0), (A, B_, H), (A, -B_, H), (1, 0, 0), b, h),         # +X wall
        _quad((A, B_, 0), (-A, B_, 0), (-A, B_, H), (A, B_, H), (0, 1, 0), a, h),         # +Y wall
        _quad((-A, B_, 0), (-A, -B_, 0), (-A, -B_, H), (-A, B_, H), (-1, 0, 0), b, h),    # -X wall
    ]
    return polys


def roof(a=6.4, b=6.4, rise=1.8):
    A, B_, R = a * 50.0, b * 50.0, rise * 100.0
    slope = math.sqrt((b / 2.0) ** 2 + rise ** 2)
    nx = rise / slope
    nz = (b / 2.0) / slope
    polys = [
        # south slope (towards -Y): from eave (y=-B) up to ridge (y=0); texture courses run along U (x)
        {"v": [(-A, -B_, 0), (A, -B_, 0), (A, 0, R), (-A, 0, R)], "n": (0, -nx, nz), "uv0": [(0.0, slope), (a, slope), (a, 0.0), (0.0, 0.0)],
         "uv1": [(0.0, slope), (a, slope), (a, 0.0), (0.0, 0.0)]},
        {"v": [(A, B_, 0), (-A, B_, 0), (-A, 0, R), (A, 0, R)], "n": (0, nx, nz), "uv0": [(0.0, slope), (a, slope), (a, 0.0), (0.0, 0.0)],
         "uv1": [(0.0, slope), (a, slope), (a, 0.0), (0.0, 0.0)]},
    ]
    return polys


def curb(length_m=10.0, width_m=0.3, height_m=0.15):
    L, W, H = length_m * 100.0, width_m * 50.0, height_m * 100.0
    # top face + front face (road side, -Y) + back face; UV1 = (lateral m, s m)
    top = {"v": [(0, -W, H), (L, -W, H), (L, W, H), (0, W, H)], "n": (0, 0, 1), "uv0": [(0, 0), (0, length_m), (width_m, length_m), (width_m, 0)],
           "uv1": [(0, 0), (0, length_m), (width_m, length_m), (width_m, 0)]}
    side = {"v": [(0, -W, 0), (L, -W, 0), (L, -W, H), (0, -W, H)], "n": (0, -1, 0), "uv0": [(width_m, 0), (width_m, length_m), (width_m + height_m, length_m), (width_m + height_m, 0)],
            "uv1": [(width_m, 0), (width_m, length_m), (width_m + height_m, length_m), (width_m + height_m, 0)]}
    side2 = {"v": [(L, W, 0), (0, W, 0), (0, W, H), (L, W, H)], "n": (0, 1, 0), "uv0": [(width_m, length_m), (width_m, 0), (width_m + height_m, 0), (width_m + height_m, length_m)],
             "uv1": [(width_m, length_m), (width_m, 0), (width_m + height_m, 0), (width_m + height_m, length_m)]}
    return [top, side, side2]


TM.MESHES["SM_Test_RoadReg"] = (road_reg, False)
TM.MESHES["SM_Test_RoadHwy"] = (road_hwy, False)
TM.MESHES["SM_Test_RoadDirt"] = (road_dirt, False)
TM.MESHES["SM_Test_RoadPad"] = (road_pad, False)
TM.MESHES["SM_Test_Box"] = (lambda: box_walls(), False)
TM.MESHES["SM_Test_Roof"] = (lambda: roof(), False)
TM.MESHES["SM_Test_Curb"] = (lambda: curb(), False)
