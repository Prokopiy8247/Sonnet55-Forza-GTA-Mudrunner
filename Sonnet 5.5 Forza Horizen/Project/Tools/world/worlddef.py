"""World definition: regions, sites, river, bay, coast, plateau footprint, platforms (terrain.py / roads_def.py read this).

Coordinates: UE metres, X = north, Y = east, Z = up, origin = map centre, playable square +-2016 m.
Everything here is data; the generators (terrain.py, massif.py, roadplan.py ...) read it.
"""
import math

import numpy as np

# ------------------------------------------------------------------ regions
REGION_IDS = {"Greenvale": 0, "Highcrest": 1, "Plateau": 2, "Coast": 3, "Basin": 4}
REGION_NAMES = ["Greenvale", "Highcrest", "Sunbaked Plateau", "Saltcliff Coast", "Crossroads Basin"]
REGION_COLORS = [(92, 170, 70), (150, 150, 165), (214, 140, 70), (70, 150, 200), (200, 190, 110)]

# soil layer order used by layers.py / export.py
LAYERS = ["Grass", "ForestFloor", "Farmland", "Rock", "Sand", "RedClay", "Snow", "RoadVerge"]

# per-region parameters: roughness (fine-detail amplitude m), soil weights, tree density (0..1), scrub density, crop density
REGION_PARAMS = {
    "Greenvale": dict(base=85.0, rough=0.55, soil=dict(Grass=0.55, ForestFloor=0.20, Farmland=0.22, Rock=0.03),
                      forest=0.55, scrub=0.15, crops=0.55),
    "Highcrest": dict(base=330.0, rough=1.6, soil=dict(Grass=0.18, ForestFloor=0.28, Rock=0.46, Snow=0.08),
                      forest=0.45, scrub=0.2, crops=0.0),
    "Plateau": dict(base=240.0, rough=0.9, soil=dict(Sand=0.22, RedClay=0.52, Rock=0.2, Grass=0.06),
                    forest=0.0, scrub=0.45, crops=0.0),
    "Coast": dict(base=55.0, rough=0.6, soil=dict(Grass=0.4, Rock=0.32, Sand=0.28),
                  forest=0.05, scrub=0.3, crops=0.0),
    "Basin": dict(base=90.0, rough=0.3, soil=dict(Grass=0.5, Farmland=0.22, Sand=0.12, RedClay=0.1, Rock=0.06),
                  forest=0.1, scrub=0.3, crops=0.3),
}

# ------------------------------------------------------------------ sites / POIs
# (name, kind, X, Y)  -- kinds: hub, village, hamlet, farm, gas, diner, lighthouse, castle, windfarm,
#                              viewpoint, tunnel, bridge, rest, harbour
SITES = [
    ("Crossroads", "hub", 0.0, 0.0),
    ("Crossroads Gas", "gas", -70.0, 230.0),
    ("Crossroads Diner", "diner", 30.0, 330.0),
    ("Millbrook", "village", -900.0, -900.0),
    ("Frostholm", "hamlet", 900.0, -1020.0),
    ("Tidewick", "harbour", -1150.0, 1385.0),
    ("Summit Viewpoint", "viewpoint", 1380.0, -1180.0),
    ("Lighthouse", "lighthouse", -1700.0, 1830.0),
    ("Great Bay Bridge", "bridge", -350.0, 1300.0),
    ("Highcrest Tunnel", "tunnel", 850.0, -620.0),
    ("Silverrun Stone Bridge", "bridge", -320.0, -1450.0),
    ("Greenvale Castle Ruin", "castle", -300.0, -1000.0),
    ("Farm A", "farm", -1090.0, -1400.0),
    ("Farm B", "farm", -1340.0, 190.0),
    ("Farm C", "farm", -1470.0, -1290.0),
    ("Farm D", "farm", -700.0, -480.0),
    ("Plateau Gas", "gas", 790.0, 1085.0),
    ("Plateau Diner", "diner", 850.0, 1120.0),
    ("Harbour Gas", "gas", -710.0, 1420.0),
    ("Windfarm", "windfarm", 1450.0, 1250.0),
    ("Sunset Beach", "hamlet", -1530.0, 860.0),
    ("Canyon Rim Viewpoint", "viewpoint", 1010.0, 1330.0),
    ("Cliff Viewpoint", "viewpoint", -300.0, 1850.0),
    ("Rest Area North", "rest", 1540.0, 330.0),
    ("Rest Area South", "rest", -1000.0, 300.0),
]

# ------------------------------------------------------------------ river Silverrun (flows W -> E into the head of the Great Bay)
# control points (X, Y); the course is X(Y) = smooth spline through the controls + gentle meanders
RIVER_CTRL = [(-505.0, -2040.0), (-470.0, -1830.0), (-545.0, -1600.0), (-600.0, -1380.0), (-540.0, -1150.0),
              (-455.0, -930.0), (-425.0, -700.0), (-480.0, -470.0), (-575.0, -240.0), (-615.0, 20.0), (-590.0, 270.0),
              (-530.0, 500.0), (-455.0, 720.0), (-395.0, 900.0), (-352.0, 1010.0), (-343.0, 1068.0)]
# straight reaches at the road crossings: (Y centre, half length m)
RIVER_GATES = [(-1700.0, 120.0), (-1180.0, 130.0), (-830.0, 120.0), (-560.0, 120.0), (460.0, 130.0)]
RIVER_END = (-343.0, 1068.0)


def _cr_interp(pts, ys):
    """Catmull-Rom interpolation of X as a function of Y (pts sorted by Y)."""
    P = np.asarray(pts, dtype=float)
    yk = P[:, 1]
    xk = P[:, 0]
    out = np.empty_like(ys)
    n = len(P)
    idx = np.clip(np.searchsorted(yk, ys, side="right") - 1, 0, n - 2)
    for i in range(len(ys)):
        k = idx[i]
        p0 = max(k - 1, 0)
        p3 = min(k + 2, n - 1)
        h = yk[k + 1] - yk[k]
        t = (ys[i] - yk[k]) / h
        m1 = 0.5 * (xk[k + 1] - xk[p0]) / max(yk[k + 1] - yk[p0], 1e-6) * h
        m2 = 0.5 * (xk[p3] - xk[k]) / max(yk[p3] - yk[k], 1e-6) * h
        t2, t3 = t * t, t * t * t
        out[i] = (2 * t3 - 3 * t2 + 1) * xk[k] + (t3 - 2 * t2 + t) * m1 + (-2 * t3 + 3 * t2) * xk[k + 1] + (t3 - t2) * m2
    return out


def make_river():
    """Procedural meandering centre line of the Silverrun (W -> E). Returns dict of arrays."""
    ds = 6.0
    ys = np.arange(-2040.0, RIVER_END[1] + 0.1, ds)
    xs = _cr_interp(RIVER_CTRL, ys)
    # gentle meanders: two incommensurate waves, amplitude varying along the course, zero in the straight gates
    amp = 140.0 + 70.0 * np.sin(ys / 610.0 + 0.8) ** 2
    mean = (np.sin(2 * np.pi * ys / 880.0 + 0.6) * 0.62 + np.sin(2 * np.pi * ys / 470.0 + 2.1) * 0.30 + np.sin(2 * np.pi * ys / 1930.0 + 4.0) * 0.45
            + np.sin(2 * np.pi * ys / 230.0 + 1.3) * 0.10)
    gate = np.ones_like(ys)
    for yc, hl in RIVER_GATES:
        gate *= 1.0 - np.exp(-((ys - yc) / (0.55 * hl)) ** 4)
    end_fade = np.clip((RIVER_END[1] - ys) / 160.0, 0.0, 1.0)
    start_fade = np.clip((ys + 2040.0) / 120.0, 0.0, 1.0)
    X = xs + amp * mean * gate * end_fade * start_fade
    P = np.stack([X, ys], 1)
    seg = np.sqrt((np.diff(P, axis=0) ** 2).sum(1))
    s = np.concatenate([[0.0], np.cumsum(seg)])
    u = s / s[-1]
    zw = 2.0 + 88.0 * (1.0 - u) ** 0.58
    width = 12.0 + 18.0 * u ** 0.8 + 3.0 * np.sin(s / 170.0 + 1.0) * (0.4 + u)       # 12 .. 30 m at the water line, varied
    width = np.clip(width, 12.0, 30.0)
    depth = 1.3 + 1.2 * u
    return dict(pts=P, s=s, z=zw, width=width, depth=depth)


# ------------------------------------------------------------------ Great Bay inlet (centre line, half width)
BAY_PTS = np.array([(-330.0, 2060.0), (-338.0, 1850.0), (-350.0, 1650.0), (-352.0, 1480.0),
                    (-352.0, 1330.0), (-348.0, 1200.0), (-345.0, 1120.0), (-343.0, 1068.0)])
BAY_HALF = np.array([380.0, 315.0, 255.0, 208.0, 192.0, 140.0, 80.0, 30.0])
BAY_FLOOR = np.array([-34.0, -28.0, -22.0, -16.0, -12.0, -8.0, -4.0, -1.5])
BAY_BANK_TOP = 46.0          # cliff top height next to the bridge


# ------------------------------------------------------------------ coastline
def coast_Yc(X):
    """east coast line (m): land where Y < Yc(X)."""
    return (1885.0 + 60.0 * np.sin(2 * np.pi * X / 1700.0 + 0.7) + 32.0 * np.sin(2 * np.pi * X / 610.0 + 2.1)
            + 16.0 * np.sin(2 * np.pi * X / 233.0 + 0.2))


def coast_Xs(Y):
    """south/south-east gulf shore (m): land where X > Xs(Y)."""
    t = np.clip((Y - 380.0) / (1580.0 - 380.0), 0, 1)
    t = t * t * (3 - 2 * t)
    return -1905.0 + 775.0 * t + 46.0 * np.sin(2 * np.pi * Y / 720.0 + 1.1) + 22.0 * np.sin(2 * np.pi * Y / 260.0)


def coast_Xs_slope(Y):
    e = 1.0
    return (coast_Xs(Y + e) - coast_Xs(Y - e)) / (2 * e)


# land added to the coast: headlands as capsules (polyline, half width at each vertex); coves cut into the shore
HEADLANDS = [([(-1060.0, 1520.0), (-1230.0, 1680.0), (-1470.0, 1760.0), (-1790.0, 1850.0)], [330.0, 330.0, 280.0, 160.0])]
COVES = []

# ------------------------------------------------------------------ plateau footprint (rounded polygon, X north / Y east)
PLATEAU_POLY = np.array([(330.0, -40.0), (700.0, -200.0), (1100.0, -210.0), (1500.0, -140.0), (1850.0, 40.0), (1960.0, 420.0),
                         (1975.0, 820.0), (1920.0, 1130.0), (1720.0, 1290.0), (1360.0, 1340.0), (960.0, 1300.0), (620.0, 1210.0),
                         (440.0, 950.0), (330.0, 560.0)])

# gaps in the escarpment (long gentle ramps) where the Spine Highway climbs onto / leaves the plateau
PLATEAU_GAPS = [[(250.0, 120.0), (720.0, 440.0)], [(1640.0, 1060.0), (1800.0, 1420.0)]]

# designed desert wash (canyon) cut into the plateau and its western apron: (X, Y, floor z). The DIRT_WASH road follows it.
WASH_PTS = [(1010.0, 1330.0, 236.0), (1090.0, 1170.0, 232.0), (960.0, 1020.0, 226.0), (800.0, 950.0, 214.0), (700.0, 1060.0, 202.0),
            (560.0, 1000.0, 190.0), (450.0, 940.0, 176.0)]


# ------------------------------------------------------------------ flat building platforms (name, X, Y, flat radius, blend width, z or None = local mean)
PLATFORMS = [
    ("Crossroads", 0.0, 0.0, 120.0, 170.0, None),
    ("Millbrook", -900.0, -900.0, 130.0, 170.0, None),
    ("Frostholm", 900.0, -1015.0, 50.0, 70.0, None),
    ("Tidewick", -1150.0, 1385.0, 90.0, 90.0, 3.0),
    ("Lighthouse", -1700.0, 1830.0, 42.0, 60.0, None),
    ("Farm A", -1090.0, -1400.0, 45.0, 60.0, None),
    ("Farm B", -1340.0, 190.0, 45.0, 60.0, None),
    ("Farm C", -1470.0, -1290.0, 45.0, 60.0, None),
    ("Farm D", -700.0, -480.0, 45.0, 60.0, None),
    ("Crossroads Gas", -70.0, 230.0, 40.0, 50.0, None),
    ("Plateau Gas", 790.0, 1085.0, 40.0, 50.0, None),
    ("Plateau Diner", 850.0, 1120.0, 26.0, 36.0, None),
    ("Harbour Gas", -710.0, 1420.0, 40.0, 50.0, None),
    ("Crossroads Diner", 30.0, 330.0, 32.0, 40.0, None),
    ("Sunset Beach", -1530.0, 860.0, 50.0, 60.0, None),
    ("Windfarm Pad", 1450.0, 1250.0, 40.0, 50.0, None),
    ("Canyon Rim", 1010.0, 1330.0, 45.0, 55.0, None),
]


# rocky sea stacks / islets off the coast: (X, Y, radius, height above sea)
SEA_STACKS = [(-120.0, 1950.0, 38.0, 30.0), (-430.0, 1968.0, 26.0, 24.0), (270.0, 1940.0, 44.0, 36.0), (-910.0, 1912.0, 30.0, 22.0),
              (700.0, 1925.0, 30.0, 26.0), (1180.0, 1950.0, 36.0, 30.0), (-1250.0, 1790.0, 28.0, 20.0)]
