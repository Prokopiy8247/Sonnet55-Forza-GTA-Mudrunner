"""Highcrest massif generator: a designed ridge skeleton (crest polylines with crest heights, one natural pass saddle,
a cirque bench for Frostholm) turned into an irregular alpine massif with domain warping, ridged multifractal detail,
geology-following cliff bands (terraces of the elevation itself) and erosion filters.

Everything is derived from the skeleton below; there are no axis-aligned slabs or planar faces.
"""
import numpy as np

import erosion as ER
from common import HALF, ss, smax, smin, gauss_blur
from geom import raster_dist
from noise import fbm, ridged, warp

# ---------------------------------------------------------------- skeleton (X north, Y east, crest height m)
# main crest NW -> SE, passes the Hollow Peak, the Pass saddle and the Needle, then runs down to the hub as a long spur
CREST_MAIN = [(2030, -2030, 600), (1900, -1880, 690), (1760, -1700, 745), (1600, -1560, 665), (1430, -1420, 715),
              (1330, -1300, 625), (1230, -1175, 560), (1145, -1085, 640), (1070, -1010, 700), (950, -900, 625),
              (840, -790, 540), (730, -680, 470), (610, -560, 380), (490, -450, 285), (380, -350, 205), (280, -270, 150)]
# south-west wall of the ascent valley (V1)
CREST_SW = [(1430, -1420, 712), (1340, -1600, 640), (1190, -1760, 560), (1010, -1860, 470), (800, -1930, 380), (560, -1990, 300),
            (330, -2030, 230)]
# spur between the ascent valley and the Frostholm cirque valley
CREST_F = [(1070, -1010, 700), (960, -1170, 610), (820, -1290, 500), (660, -1380, 400), (500, -1430, 300), (330, -1460, 220),
           (170, -1470, 160)]
# north wing (towards the map edge)
CREST_N = [(1430, -1420, 712), (1560, -1290, 700), (1720, -1200, 710), (1880, -1180, 670), (2030, -1130, 580)]
# north-west buttress and a second parallel range inside the corner
CREST_NW = [(1760, -1700, 745), (1900, -1990, 560), (2030, -2030, 520)]
# spurs falling from the main crest towards the Spine valley (east side). One of them carries the tunnel.
CREST_E1 = [(1140, -1085, 640), (1190, -930, 520), (1210, -780, 410), (1180, -620, 300), (1120, -470, 230)]
CREST_E2 = [(950, -900, 625), (930, -740, 500), (880, -610, 380), (800, -480, 270), (700, -380, 190)]
CREST_E3 = [(730, -680, 470), (690, -560, 360), (600, -430, 250), (500, -330, 175)]
# western outlier ridges
CREST_W2 = [(1190, -1760, 560), (1020, -1640, 420), (850, -1560, 330), (640, -1540, 250)]
CREST_W3 = [(1600, -1560, 665), (1520, -1790, 560), (1380, -1960, 420)]

RIDGES = [
    # points, relief Hr (m), lambda (m)
    (CREST_MAIN, 620.0, 430.0),
    (CREST_SW, 560.0, 400.0),
    (CREST_F, 520.0, 380.0),
    (CREST_N, 560.0, 420.0),
    (CREST_NW, 560.0, 420.0),
    (CREST_E1, 500.0, 330.0),
    (CREST_E2, 500.0, 330.0),
    (CREST_E3, 440.0, 300.0),
    (CREST_W2, 480.0, 360.0),
    (CREST_W3, 520.0, 380.0),
]

# ascent valley V1 (floor polyline X, Y, z): from the foothills north-east up to the col
V1_PTS = [(-80.0, -1470.0, 108.0), (160.0, -1570.0, 124.0), (400.0, -1650.0, 156.0), (640.0, -1640.0, 205.0), (820.0, -1560.0, 262.0),
          (960.0, -1455.0, 330.0), (1075.0, -1345.0, 395.0), (1150.0, -1262.0, 460.0), (1195.0, -1214.0, 510.0), (1230.0, -1175.0, 540.0)]
# short trough across the crest (the col) and the first part of the north-east side
COL_PTS = [(1195.0, -1214.0, 515.0), (1230.0, -1175.0, 540.0), (1300.0, -1105.0, 532.0), (1385.0, -1030.0, 508.0), (1460.0, -950.0, 478.0),
           (1520.0, -860.0, 442.0), (1560.0, -760.0, 405.0)]
EROSION_ITERS = 0
CALM_STRENGTH = 0.0
PASS_SADDLE = (1230.0, -1175.0, 540.0)
USE_V1 = False
CIRQUE = (905.0, -1015.0, 425.0, 70.0)     # Frostholm cirque floor: X, Y, z, flat radius


def _catmull(pts, ds=35.0):
    P = np.asarray(pts, dtype=np.float64)
    out = []
    n = len(P)
    for i in range(n - 1):
        p0 = P[max(i - 1, 0)]
        p1 = P[i]
        p2 = P[i + 1]
        p3 = P[min(i + 2, n - 1)]
        L = float(np.hypot(*(p2[:2] - p1[:2])))
        m = max(2, int(L / ds))
        for t in np.linspace(0, 1, m, endpoint=False):
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-1])
    return np.array(out)


def ridge_cones(step, n, L, cstep=8.0, ridges=RIDGES):
    """smooth-max of the ridge flank fields: every ridge polyline carries a crest height z_c(s); the terrain falls from the
    crest to the lowland base L with an exponential flank  L + (z_c - L) * exp(-(d / lambda)^0.9)  (steep under the crest,
    gentle foot, no cut-offs). Returns float32 [n, n] (absolute metres, >= L)."""
    cn = int(round(2 * HALF / cstep)) + 1
    from terrain import resize_to
    Lc = L if L.shape[0] == cn else resize_to(L, step, cstep)
    acc = Lc.copy()
    for pts, Hr, lam in ridges:
        D = _catmull(pts)
        d, at = raster_dist((cn, cn), cstep, -HALF, D[:, :2], 2600.0, vals=D[:, 2:3])
        zc = at[0]
        f = Lc + np.maximum(zc - Lc, 0.0) * np.exp(-(d / (lam * 0.95)) ** 1.3)
        acc = smax(acc, f, 28.0)
    return resize_to(acc.astype(np.float32), cstep, step)


def trough(H, cs, pts, w0, c2, s1=0.22, k=22.0, fac=None, noise=None, radius=700.0, fade=(0.55, 1.0)):
    """U-shaped valley cut along a polyline pts (X, Y, floor z): T = z_floor + wall(d) * fac, smooth-min with H.
    `fac` (>0, ~1) modulates the wall height with the same noise as the massif so the valley walls carry its ridges and gullies.
    The cut fades out along the last part of the polyline (fade = arc-fraction range) so it has no round end cap."""
    D = _catmull(pts, ds=25.0)
    seg = np.hypot(*np.diff(D[:, :2], axis=0).T)
    sv = np.concatenate([[0.0], np.cumsum(seg)])
    cn = int(round(2 * HALF / cs)) + 1
    d, at = raster_dist((cn, cn), cs, -HALF, D[:, :2], radius, vals=np.stack([D[:, 2], sv / sv[-1]], 1))
    zf = at[0]
    t_al = at[1]
    xx = np.maximum(d - w0, 0.0)
    wall = s1 * xx + c2 * xx * xx
    if fac is not None:
        wall = wall * fac
    T = zf + wall
    if noise is not None:
        T = T + noise * np.clip((d - w0) / 200.0, 0.0, 1.0)
    keep = 1.0 - ss(t_al, fade[0], fade[1])
    T = np.where(d < radius, T + (1.0 - keep) * 400.0, 1e5)
    return smin(H, T, k)


def cirque(H, X, Y, F, fac=None):
    """Frostholm cirque: a bench with an irregular, elongated outline and a steep headwall."""
    cx, cy, cz, cr = CIRQUE
    ang = np.radians(25.0)
    u = (X - cx) * np.cos(ang) + (Y - cy) * np.sin(ang)
    v = -(X - cx) * np.sin(ang) + (Y - cy) * np.cos(ang)
    d = np.sqrt((u / 1.45) ** 2 + (v / 0.8) ** 2)
    dw = d * (1.0 + 0.38 * np.clip(F("cirq", 240.0, 2), -1.2, 1.2))
    wall = 0.20 * np.maximum(dw - cr, 0.0) + 0.0013 * np.maximum(dw - cr, 0.0) ** 2
    if fac is not None:
        wall = wall * fac
    T = cz + wall + 4.0 * F("cirq2", 60.0, 2) * ss(dw, 0.0, cr) + 6.0 * ss(dw, cr * 0.6, cr) * F("cirq3", 30.0, 2)
    T = np.where(d < 900.0, T, 1e5)
    return smin(H, T, 14.0)


def build(cs, n, X, Y, L, F, calm=None):
    """massif height field (absolute metres, equals L far from the mountains) and the uplift envelope (m above L)."""
    from noise import mountain_noise, warp as _warp
    from common import gauss_blur
    from terrain import rng_for, strata
    shape = (n, n)
    cone = ridge_cones(cs, n, L, cstep=cs)
    env = np.maximum(cone - L, 0.0)
    envb = gauss_blur(env.astype(np.float32), 140.0 / cs)
    mn_s = mountain_noise(shape, 900.0, 8, rng_for("mridge"), step=cs, gain=0.58, h_scale=500.0, k_erode=1.0, power=2.0)
    mn_h = mountain_noise(shape, 900.0, 8, rng_for("mridge"), step=cs, gain=0.62, h_scale=500.0, k_erode=0.4, power=3.0)
    wdx = 140.0 * F("mwx", 800.0, 3)
    wdy = 140.0 * F("mwy", 800.0, 3)
    mn_s = _warp(mn_s.astype(np.float32), wdx, wdy, cs)
    mn_h = _warp(mn_h.astype(np.float32), wdx, wdy, cs)
    wh = ss(envb, 100.0, 380.0)
    mn = mn_s * (1 - wh) + mn_h * wh
    mnn = np.clip(mn / np.percentile(mn, 92), 0, 1.3)
    sx, sy, sz = PASS_SADDLE
    wcol = np.exp(-(((X - sx) ** 2 + (Y - sy) ** 2) / (330.0 ** 2)) ** 1.0)
    mnn = mnn * (1 - wcol) + 0.80 * wcol
    if calm is not None:
        cm = np.clip(calm, 0.0, 1.0) * CALM_STRENGTH
        mnn = mnn * (1 - cm) + 0.80 * cm
    Hm = L + envb * (0.10 + 1.2 * mnn)
    # geology: benches and cliff bands following the contours, strongest on the mid / upper slopes
    lith = F("lith", 420.0, 2)
    a_st = 0.30 * ss(envb, 120.0, 300.0) * (1.0 - ss(envb, 520.0, 640.0))
    Hm = strata(Hm, 34.0, a_st, 14.0 * lith, sharp=0.30)
    # designed valleys: the ascent valley V1 and the short pass trough across the col (the saddle is where they meet)
    rn = ridged(shape, 110.0, 4, rng_for("v1r"), step=cs, gain=0.55) - 0.3
    fac = np.clip(0.35 + 1.1 * mnn, 0.3, 1.5)
    if USE_V1:
        Hm = trough(Hm, cs, V1_PTS, 26.0, 0.0011, s1=0.30, fac=fac, noise=10.0 * F("v1n", 130.0, 2))
    Hm = trough(Hm, cs, COL_PTS, 34.0, 0.0012, s1=0.28, fac=fac, noise=8.0 * F("v2n", 120.0, 2))
    Hm = cirque(Hm, X, Y, F, fac=fac)
    Hm = ER.thermal(Hm.astype(np.float32), cs, talus=0.95, iters=8)
    # drainage gullies: a few iterations of stream-power incision on the mountain window (restoring towards the design)
    j1 = int((-150.0 + HALF) / cs)
    i0 = int((0.0 + HALF) / cs)
    sub = (slice(0, j1), slice(i0, n))
    kmask = (0.6 + 0.8 * ss(F("kmask", 500.0, 2), -0.5, 0.8)) * ss(envb, 40.0, 160.0)
    if EROSION_ITERS > 0:
      zc = ER.landscape(Hm[sub], Hm[sub], cs, iters=EROSION_ITERS, K=0.016, kappa=0.006, Kmask=kmask[sub], talus=0.9, thermal_iters=2)
      wj = np.ones(zc.shape, dtype=np.float32)
      ramp = 14
      wj[-ramp:, :] *= np.linspace(1, 0, ramp)[:, None]
      wj[:, :ramp] *= np.linspace(0, 1, ramp)[None, :]
      Hm[sub] = Hm[sub] + wj * (zc - Hm[sub])
    return Hm.astype(np.float32), np.maximum(Hm - L, 0.0).astype(np.float32)
