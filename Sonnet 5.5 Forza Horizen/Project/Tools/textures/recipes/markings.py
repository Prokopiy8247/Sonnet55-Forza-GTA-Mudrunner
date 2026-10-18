"""Road marking atlas (RGBA decals): lines, zebra crossing, arrows, speed numbers, hatching.

Atlas is 2048 x 2048 px at 128 px / metre (16 m x 16 m).  Cell rectangles are stored in the
manifest ("cells").  Paint = white (double line = yellow), alpha = paint coverage with wear."""
from __future__ import annotations

import math

import numpy as np

from ..core import recipe
from ..maps import ramp, lerp
from ..noise import f32, blur, norm01
from .common import S, hash01

PXM = 128.0     # pixels per metre at 2048

# name: (x, y, w, h) in px at 2048 ; metres = px / 128
CELLS = {
    "solid_line":     (0, 0, 96, 1024),
    "edge_line":      (96, 0, 96, 1024),
    "dashed_line":    (192, 0, 96, 1024),
    "double_line":    (288, 0, 96, 1024),
    "dashed_short":   (384, 0, 96, 1024),
    "zebra_crossing": (480, 0, 1024, 512),
    "stop_line":      (480, 512, 1024, 128),
    "hatching":       (1536, 0, 512, 512),
    "arrow_straight": (0, 1024, 256, 640),
    "arrow_left":     (256, 1024, 256, 640),
    "arrow_right":    (512, 1024, 256, 640),
    "arrow_straight_left":  (768, 1024, 256, 640),
    "arrow_straight_right": (1024, 1024, 256, 640),
    "speed_30":       (0, 1664, 400, 384),
    "speed_50":       (400, 1664, 400, 384),
    "speed_70":       (800, 1664, 400, 384),
    "speed_90":       (1200, 1664, 400, 384),
    "speed_110":      (1600, 1664, 400, 384),
}
TILEABLE_V = {"solid_line", "edge_line", "dashed_line", "double_line", "dashed_short"}
WEAR = {"solid_line": 0.14, "edge_line": 0.24, "dashed_line": 0.17, "double_line": 0.15, "dashed_short": 0.19,
        "zebra_crossing": 0.18, "stop_line": 0.18, "hatching": 0.16}


def _seg_dist(X, Y, a, b):
    ex, ey = b[0] - a[0], b[1] - a[1]
    px, py = X - a[0], Y - a[1]
    t = np.clip((px * ex + py * ey) / max(ex * ex + ey * ey, 1e-9), 0, 1)
    return np.hypot(px - ex * t, py - ey * t)


def _poly_dist(X, Y, pts, closed=False):
    d = np.full(np.broadcast(X, Y).shape, 1e9, f32)
    k = len(pts) - (0 if closed else 1)
    for i in range(k):
        d = np.minimum(d, _seg_dist(X, Y, pts[i], pts[(i + 1) % len(pts)]))
    return d


def _arc(cx, cy, rx, ry, a0, a1, n=28):
    th = np.radians(np.linspace(a0, a1, n))
    return [(cx + rx * math.cos(t), cy + ry * math.sin(t)) for t in th]


def _digit_paths(ch, W, H, t):
    a = t / 2
    xl, xr, yt, yb, ym = a, W - a, a, H - a, H / 2
    rx = (xr - xl) / 2
    cx = W / 2
    if ch == "0":
        r = rx
        p = _arc(cx, yt + r, r, r, 180, 360) + _arc(cx, yb - r, r, r, 0, 180)
        return [(p, True)]
    if ch == "1":
        x = W * 0.60
        return [([(x, yb), (x, yt), (xl + 2, yt + H * 0.20)], False)]
    if ch == "3":
        ry = (ym - yt) / 2
        up = _arc(cx, yt + ry, rx, ry, 200, 450)
        lo = _arc(cx, yb - ry, rx, ry, 270, 520)
        return [(up, False), (lo, False)]
    if ch == "5":
        y0 = ym - 0.04 * H
        ry = (yb - y0) / 2
        cy = (yb + y0) / 2
        bowl = _arc(cx, cy, rx, ry, 245, 510)
        return [([(xr, yt), (xl, yt), (xl, y0 + 4), bowl[0]] + bowl[1:], False)]
    if ch == "7":
        return [([(xl, yt), (xr, yt), (W * 0.36, yb)], False)]
    if ch == "9":
        yl = 0.58 * H
        ry = (yl - yt) / 2
        loop = _arc(cx, yt + ry, rx, ry, 0, 360, 36)
        ryb = 0.30 * H
        tail = [(xr, yt + ry), (xr, yb - ryb)] + _arc(cx, yb - ryb, rx, ryb, 0, 150)
        return [(loop, True), (tail, False)]
    raise ValueError(ch)


def _stroke_cov(X, Y, paths, hw):
    d = np.full(np.broadcast(X, Y).shape, 1e9, f32)
    for pts, closed in paths:
        d = np.minimum(d, _poly_dist(X, Y, pts, closed))
    return d - hw


def _tri(X, Y, tip, dirv, length, half):
    """signed distance-ish coverage of a triangle head (tip, direction unit vector)."""
    dx, dy = dirv
    nx, ny = -dy, dx
    bx, by = tip[0] - dx * length, tip[1] - dy * length
    pts = [tip, (bx + nx * half, by + ny * half), (bx - nx * half, by - ny * half)]
    return pts


def _poly_sd(X, Y, pts):
    P = np.array(pts, f32)
    inside = np.zeros(np.broadcast(X, Y).shape, bool)
    dmin = np.full(inside.shape, 1e9, f32)
    k = len(P)
    for i in range(k):
        a, b = P[i], P[(i + 1) % k]
        dmin = np.minimum(dmin, _seg_dist(X, Y, a, b))
        cond = ((a[1] <= Y) != (b[1] <= Y)) & (X < (b[0] - a[0]) * (Y - a[1]) / (b[1] - a[1] + 1e-12) + a[0])
        inside ^= cond
    return np.where(inside, -dmin, dmin)


@recipe("road_markings_atlas", [16.0, 16.0],
        "Road paint decal atlas (RGBA): solid/edge/dashed/double lines, zebra crossing, stop line, hatching, arrows, speed numbers 30/50/70/90/110. "
        "See 'cells' for pixel rects and real-world sizes.", "road", size_mult=2, albedo=(0.5, 0.95),
        tileable=False, notes="128 px per metre. Line cells tile along V. Decal: alpha = paint coverage.")
def road_markings_atlas(ctx):
    n = ctx.n
    s = n / 2048.0
    cov = np.zeros((n, n), f32)
    yellow = np.zeros((n, n), f32)
    wearmap = np.zeros((n, n), f32)
    cell_info = {}

    def put(name, fn):
        x, y, w, h = [int(round(c * s)) for c in CELLS[name]]
        X = (np.arange(w, dtype=f32) + 0.5)[None, :] / s
        Y = (np.arange(h, dtype=f32) + 0.5)[:, None] / s
        sd = fn(X, Y, w / s, h / s)          # signed distance in 2048-px units (negative inside)
        c = np.clip(0.5 - sd * s, 0, 1).astype(f32)
        cov[y:y + h, x:x + w] = np.maximum(cov[y:y + h, x:x + w], c)
        wearmap[y:y + h, x:x + w] = WEAR.get(name, 0.12)
        cell_info[name] = dict(px=[x, y, w, h], uv=[x / n, y / n, w / n, h / n],
                               metres=[round(w / s / PXM, 3), round(h / s / PXM, 3)],
                               tileable_v=name in TILEABLE_V)
        return (x, y, w, h)

    def line(wm, y0=None, y1=None):
        hwp = wm * PXM / 2

        def f(X, Y, W, H):
            d = np.abs(X - W / 2) - hwp
            if y0 is not None:
                d = np.maximum(d, np.maximum(y0 - Y, Y - y1))
            return d
        return f

    put("solid_line", line(0.15))
    put("edge_line", line(0.12))
    put("dashed_line", line(0.15, 64, 64 + 3 * PXM))
    x, y, w, h = put("double_line", lambda X, Y, W, H: np.minimum(np.abs(X - W / 2 - 0.12 * PXM) - 0.06 * PXM,
                                                                  np.abs(X - W / 2 + 0.12 * PXM) - 0.06 * PXM))
    yellow[y:y + h, x:x + w] = 1.0
    def dashes(X, Y, W, H):
        ph = (Y - 64) % 256
        sy = np.maximum(-ph, ph - 128)
        return np.maximum(np.abs(X - W / 2) - 0.075 * PXM, sy + 0 * X)
    put("dashed_short", dashes)

    def zebra(X, Y, W, H):
        # 8 bars across width, pitch 1 m
        px = (X % PXM) - PXM / 2
        return np.maximum(np.abs(px) - 0.25 * PXM, np.abs(Y - H / 2) - (H / 2 - 6))
    put("zebra_crossing", zebra)
    put("stop_line", lambda X, Y, W, H: np.maximum(np.abs(Y - H / 2) - 0.25 * PXM, np.abs(X - W / 2) - (W / 2 - 8)))

    def hatch(X, Y, W, H):
        d = ((X + Y) % 130) - 65
        return np.maximum(np.abs(d) * 0.7071 - 0.16 * PXM * 0.5 * 1.1, np.maximum(np.abs(X - W / 2) - (W / 2 - 4), np.abs(Y - H / 2) - (H / 2 - 4)))
    put("hatching", hatch)

    # ---- arrows (cell 256 x 640 px = 2 m x 5 m)
    def arrow(paths, heads):
        def f(X, Y, W, H):
            d = _stroke_cov(X, Y, paths, 0.30 * PXM / 2)
            for tip, dirv, L, half in heads:
                d = np.minimum(d, _poly_sd(X, Y, _tri(X, Y, tip, dirv, L, half)))
            return d
        return f

    def unit(dx, dy):
        m = math.hypot(dx, dy)
        return (dx / m, dy / m)

    cx = 128.0
    up = unit(0, -1)
    dl = unit(-0.5, -0.866)
    dr = unit(0.5, -0.866)
    put("arrow_straight", arrow([([(cx, 600), (cx, 150)], False)], [((cx, 36), up, 170.0, 66.0)]))
    put("arrow_left", arrow([([(158, 604), (158, 400), (128, 325)], False)], [((58, 176), dl, 140.0, 56.0)]))
    put("arrow_right", arrow([([(98, 604), (98, 400), (128, 325)], False)], [((198, 176), dr, 140.0, 56.0)]))
    put("arrow_straight_left", arrow([([(158, 604), (158, 140)], False), ([(158, 480), (150, 420), (120, 385)], False)],
                                     [((158, 28), up, 150.0, 56.0), ((70, 300), dl, 118.0, 46.0)]))
    put("arrow_straight_right", arrow([([(98, 604), (98, 140)], False), ([(98, 480), (106, 420), (136, 385)], False)],
                                      [((98, 28), up, 150.0, 56.0), ((186, 300), dr, 118.0, 46.0)]))

    # ---- speed numbers (bold geometric digits, original design)
    DW, DH, T, GAP = 118.0, 300.0, 40.0, 14.0

    def number(txt):
        def f(X, Y, W, H):
            tw = len(txt) * DW + (len(txt) - 1) * GAP
            x0 = (W - tw) / 2
            y0 = (H - DH) / 2
            d = np.full(np.broadcast(X, Y).shape, 1e9, f32)
            for i, ch in enumerate(txt):
                paths = _digit_paths(ch, DW, DH, T)
                shifted = [([(px + x0 + i * (DW + GAP), py + y0) for px, py in pts], cl) for pts, cl in paths]
                d = np.minimum(d, _stroke_cov(X, Y, shifted, T / 2))
            return d
        return f
    for sp in (30, 50, 70, 90, 110):
        put("speed_%d" % sp, number(str(sp)))

    # ---- wear: speckled paint loss, rough edges
    n_big = ctx.fbm01(7, 4)
    n_mid = ctx.fbm01(40, 4)
    n_fine = ctx.fbm01(220, 3)
    wf = norm01(0.30 * n_big + 0.30 * n_mid + 0.40 * n_fine)
    thr = 1.0 - wearmap * 1.6
    remove = S(thr - 0.02, thr + 0.07, wf) * (wearmap > 0)
    alpha = np.where(cov > 0.02, cov * (1 - 0.92 * remove) * (0.94 + 0.06 * n_fine), 0).astype(f32)
    keep = 1 - remove
    edge = (cov > 0.02) & (cov < 0.98)
    alpha = np.clip(alpha + (n_fine - 0.5) * 0.30 * edge, 0, 1) * (cov > 0.02)
    paint = np.array([0.80, 0.80, 0.77], f32)
    ypaint = np.array([0.72, 0.52, 0.04], f32)
    col = lerp(paint, ypaint, yellow)
    col = col * (0.9 + 0.1 * ctx.fbm01(60, 3))[..., None]
    # dirt/tyre darkening on paint
    col = col * (0.78 + 0.22 * keep)[..., None]
    # colour bleed under transparent area (avoids dark halos on filtering)
    col_b = col
    # height & normal data: paint film slightly raised
    h = blur(alpha, 0.8 * s) * 0.5 + 0.1 * ctx.grain(0.12) * alpha
    rough = np.where(alpha > 0.1, 0.62 - 0.12 * keep, 0.88).astype(f32)
    meta = dict(cells=cell_info, pixels_per_metre=PXM * s, atlas_metres=16.0)
    return dict(albedo=col_b, alpha=alpha, height=np.clip(h, 0, 1), rough=rough, slope=0.15,
                ao=np.ones((n, n), f32), meta=meta, write_h=False)
