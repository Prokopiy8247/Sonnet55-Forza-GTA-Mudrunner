"""Nature recipes: barks, cactus, moss and the foliage / grass / flower atlases (RGBA)."""
from __future__ import annotations

import math

import numpy as np

from ..core import recipe
from ..maps import ramp, lerp, luminance, cavity_ao
from ..noise import f32, norm01, blur
from .common import (C, pal, stops, S, rpick, apply_ao, tint_speckle, sample_at, hash01, leaf_colfn,
                     bleed_colour, bezier, bezier_tangent, rough_field, edge_px)

TAU = 2 * math.pi


# ======================================================================================
# tree bark
# ======================================================================================
@recipe("tree_bark_a", [1.2, 1.2], "Oak-style bark: deep vertical fissures between thick ridged plates, lichen patches (wraps around a trunk along U).",
        "nature", albedo=(0.04, 0.16))
def tree_bark_a(ctx):
    n, s = ctx.n, ctx.s
    uw, vw = ctx.warp(0.02, 3, 3)
    uw = uw + 0.025 * ctx.fbm(4, 3, fy=1) + 0.008 * ctx.fbm(14, 3, fy=3) + 0.004 * ctx.fbm(26, 3, fy=9)
    vw = vw + 0.003 * ctx.fbm(22, 3, fy=22)
    # long vertical plates (anisotropic Voronoi) + a finer network of short cross-cracks.  Fissure widths are
    # measured as isotropic pixel distances (edge_px) so horizontal cracks are as narrow as vertical ones.
    w = ctx.worley(10, 2, jitter=0.95, uv=(uw, vw))
    w2 = ctx.worley(20, 6, jitter=0.9, uv=(uw, vw))
    w3 = ctx.worley(40, 4, jitter=0.92, uv=(uw, vw))
    d1 = edge_px(w.f2 - w.f1, s)
    d2 = edge_px(w2.f2 - w2.f1, s)
    d3 = edge_px(w3.f2 - w3.f1, s)
    wf = 3.2 + 3.5 * ctx.fbm01(5, 3, fy=2)
    fiss = (1.0 - S(0.0, wf, d1)) ** 1.4                       # deep main fissures (3..7 px)
    cross_m = S(0.40, 0.68, ctx.fbm01(6, 3)) * S(5.0, 9.0, d1)  # cross cracks live inside plates only
    cross = (1.0 - S(0.0, 2.0, d2)) * cross_m
    strip_m = S(0.30, 0.60, ctx.fbm01(9, 3, fy=3)) * S(4.0, 10.0, d1)
    strip = (1.0 - S(0.0, 1.9, d3)) * strip_m                   # fibrous sub-ridges splitting the plates
    plate = S(0.0, 22.0, d1) ** 0.8                              # rounded plate shoulders
    ridg = norm01(ctx.fbm(26, 6, kind="ridged", fy=3, gain=0.66, uv=(uw, vw)))   # vertical fibres
    fine = norm01(ctx.fbm(64, 4, kind="ridged", fy=9, gain=0.60, uv=(uw, vw)))
    scale = norm01(ctx.fbm(14, 5, kind="ridged", fy=14, gain=0.62, uv=(uw, vw)))  # flaky horizontal scales
    h = (0.30 * plate + 0.46 * (ridg - 0.5) * (0.30 + 0.70 * plate) + 0.22 * (fine - 0.5)
         + 0.16 * (scale - 0.5) * plate + 0.07 * (w.rid - 0.5)
         - 0.42 * fiss - 0.22 * cross - 0.15 * strip + ctx.grain(0.006))
    h = (h - h.min()) / (h.max() - h.min())
    base = ramp(0.5 * ctx.fbm01(4, 4) + 0.5 * ctx.fbm01(40, 4, fy=3), stops("#2e261e", "#40362b", "#54483b", "#6a5d4c", "#80725f"))
    col = base * (0.36 + 1.15 * h)[..., None]
    col = col * (0.88 + 0.24 * w.rid)[..., None]                 # plate-to-plate tone variation
    col = col * (0.82 + 0.36 * ctx.fbm01(90, 3, fy=6))[..., None]
    col = col * (1.0 - 0.88 * fiss - 0.55 * cross - 0.35 * strip)[..., None]    # near-black narrow furrows
    lich = S(0.70, 0.88, ctx.fbm01(7, 5)) * S(0.4, 0.8, ctx.fbm01(60, 3)) * S(0.4, 0.85, h)
    lc = ramp(ctx.fbm01(30, 2), [(0, C("#6f8a4a")), (1, C("#a9b48c"))])
    col = lerp(col, lc * 0.9, lich * 0.5)
    ao = cavity_ao(h, radii=(1.5, 5, 13), weights=(0.45, 0.40, 0.15), gain=3.0)
    col = apply_ao(col, ao, 0.75)
    col = tint_speckle(ctx, col, 0.07)
    rough = rough_field(ctx, 0.86 + 0.06 * (1 - ao), h, h_amp=0.06, macro_amp=0.05, macro_f=4, fine_amp=0.01)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.55)


@recipe("tree_bark_b", [1.2, 1.2], "Pine-style bark: large flat reddish-brown plates with thin dark fissures and flaky layers.",
        "nature", albedo=(0.03, 0.18))
def tree_bark_b(ctx):
    n, s = ctx.n, ctx.s
    uw, vw = ctx.warp(0.035, 3, 3)
    w = ctx.worley(7, 3, jitter=0.92, uv=(uw, vw))
    e = w.f2 - w.f1
    fiss = 1 - S(0.0, 0.06 + 0.05 * ctx.fbm01(6, 3), e)
    plate = S(0.0, 0.30, e) ** 0.5
    flake = 0.5 + 0.5 * np.sin(TAU * (vw * 40 + 3.0 * ctx.fbm(6, 3) + 5 * w.rid))
    flake = flake ** 2
    ridg = norm01(ctx.fbm(14, 6, kind="ridged", fy=5, gain=0.6, uv=(uw, vw)))
    h = 0.40 * plate + 0.30 * (w.rid - 0.5) + 0.12 * flake * plate + 0.32 * (ridg - 0.5) - 0.45 * fiss + ctx.grain(0.006)
    h = (h - h.min()) / (h.max() - h.min())
    pc = np.array(pal("#4a3a30", "#56443a", "#3a2d26", "#645044", "#4f3d33", "#2d231e", "#6e5242", "#7a4a34"), f32)
    ci = np.minimum((w.rid * len(pc)).astype(np.int32), len(pc) - 1)
    ci2 = np.minimum((hash01(w.cid * 1.0 + 0.3) * len(pc)).astype(np.int32), len(pc) - 1)
    col = pc[ci] * 0.65 + pc[ci2] * 0.35
    col = col * (0.72 + 0.5 * ctx.fbm01(40, 4, fy=5))[..., None]
    col = col * (0.82 + 0.34 * flake)[..., None]
    col = col * (0.6 + 0.8 * h)[..., None]
    edge_l = S(0.05, 0.2, e) * (1 - S(0.2, 0.5, e))
    col = lerp(col, C("#8a6040"), edge_l * 0.10)
    resin = S(0.80, 0.92, ctx.fbm01(24, 3)) * S(0.5, 0.9, ctx.fbm01(70, 3))
    col = lerp(col, C("#c9a15a"), resin * 0.35)
    lich = S(0.74, 0.9, ctx.fbm01(8, 5)) * S(0.4, 0.8, ctx.fbm01(60, 3))
    col = lerp(col, C("#8a9468"), lich * 0.35)
    col = col * (1 - 0.88 * fiss)[..., None]
    ao = cavity_ao(h, radii=(2, 7, 20), weights=(0.3, 0.4, 0.3), gain=3.0)
    col = apply_ao(col, ao, 0.8)
    col = tint_speckle(ctx, col, 0.06)
    return dict(albedo=col, height=h, ao=ao, rough=0.84 + 0.08 * (1 - ao) - 0.2 * resin, slope=0.50)


@recipe("birch_bark", [1.0, 1.0], "Birch bark: cream-white papery bark with black horizontal lenticels, scars and peeling curls.",
        "nature", albedo=(0.30, 0.65))
def birch_bark(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    u, v = ctx.u, ctx.v
    uw = u + 0.01 * ctx.fbm(3, 3)
    macro = ctx.fbm01(3, 4)
    base = ramp(0.5 * macro + 0.5 * ctx.fbm01(24, 4, fy=6), stops("#c9c0ac", "#d9d2c0", "#e6e0d1", "#efe9dc"))
    # lenticels: short horizontal dashes in horizontal bands
    dash = ctx.fbm01(9, 4, fy=52, uv=(uw, v))
    band = S(0.30, 0.7, ctx.fbm01(2, 3, fy=5))
    marks = S(0.66, 0.80, dash) * (0.35 + 0.65 * band)
    big = S(0.90, 0.97, ctx.fbm01(5, 4, fy=22, uv=(uw, v)))
    marks = np.clip(marks + big, 0, 1)
    thin = S(0.72, 0.9, ctx.fbm01(8, 3, fy=90, uv=(uw, v))) * 0.5
    col = lerp(base, C("#1c1a18"), np.clip(marks * 0.92 + thin * 0.4, 0, 1))
    grey = S(0.55, 0.85, ctx.fbm01(5, 5, fy=2)) * 0.35
    col = lerp(col, C("#9c9588"), grey)
    cv = ctx.canvas()
    cv.c = col
    cv.h[:] = 0.5 + 0.10 * marks + 0.04 * ctx.fbm(20, 3, fy=6) + 0.02 * ctx.fbm(100, 2, fy=30) + ctx.grain(0.006)
    cv.r[:] = 0.55 + 0.3 * marks
    curl_c = pal("#d9ccb2", "#c9b79a", "#e0d6c0")
    for i in range(int(26 * s * s)):
        L = (40 + 110 * rng.random()) * s
        hw = (3 + 6 * rng.random()) * s
        x, y = rng.random() * n, rng.random() * n
        a = rng.normal(0, 0.1) + (math.pi if rng.random() < 0.5 else 0)
        c = rpick(rng, curl_c)
        cv.blade(x, y + hw * 1.1, a, L, hw * 1.05, hw * 0.7, 0, c * 0.30, c * 0.35, 0.5, 0.45, rough=0.8, alpha_mul=0.45)
        cv.blade(x, y, a, L, hw, hw * 0.55, L * rng.normal(0, 0.05), c * 0.85, c * 1.05, 0.62, 0.78, hround=0.12, rough=0.5)
    h = cv.h
    col = cv.c * (0.92 + 0.12 * ctx.fbm01(110, 3))[..., None]
    ao = cavity_ao(h, radii=(1.5, 5, 14), weights=(0.4, 0.4, 0.2), gain=2.6)
    col = apply_ao(col, ao, 0.6)
    col = tint_speckle(ctx, col, 0.05)
    return dict(albedo=col, height=h, ao=ao, rough=cv.r, slope=0.22)


# ======================================================================================
# cactus, moss
# ======================================================================================
@recipe("cactus_skin", [0.6, 0.6], "Saguaro / columnar cactus skin: 14 ribs wrapping around U, spine clusters on the crests, waxy bloom.",
        "nature", albedo=(0.05, 0.20))
def cactus_skin(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    u, v = ctx.u, ctx.v
    ribs = 14
    uw = u + 0.004 * ctx.fbm(6, 3, fy=3)
    rib = (0.5 + 0.5 * np.cos(TAU * ribs * uw)) ** 0.8
    groove = 1 - rib
    base = ramp(0.5 * ctx.fbm01(3, 4) + 0.5 * ctx.fbm01(40, 4, fy=3), stops("#2f5a3c", "#3f6b4a", "#52805a", "#6a9470"))
    bloom = S(0.55, 0.85, ctx.fbm01(8, 4)) * 0.20
    col = lerp(base, C("#9cb4a0"), bloom)
    col = col * (0.55 + 0.45 * rib)[..., None]
    scar = S(0.80, 0.94, ctx.fbm01(70, 3, fy=3)) * 0.3
    col = lerp(col, C("#8b7a52"), scar * 0.5)
    cv = ctx.canvas()
    cv.c = col
    cv.h[:] = 0.3 + 0.45 * rib + 0.02 * ctx.fbm(60, 3) + ctx.grain(0.005)
    cv.r[:] = 0.5 + 0.15 * ctx.fbm01(20, 3)
    spine_c = pal("#e9dfc0", "#d6c9a0", "#f3ecd6", "#bdae85")
    rows = 9
    for k in range(ribs):
        for j in range(rows):
            x = (k + rng.normal(0, 0.01)) / ribs * n
            y = (j + 0.5 + rng.normal(0, 0.06)) / rows * n
            cv.oval(x, y, 9 * s, 12 * s, 0, col=C("#cbbf9a") * 0.9, h0=0.8, hdome=0.1, irr=0.1, rng=rng, rough=0.8)
            cv.oval(x, y, 5.5 * s, 7.5 * s, 0, col=C("#5a4a30"), h0=0.85, hdome=0.05, rough=0.9)
            for q in range(9):
                a = TAU * q / 9 + rng.normal(0, 0.25)
                L = (20 + 22 * rng.random()) * s
                cv.blade(x, y, a, L, 1.1 * s, 0.2 * s, 0, rpick(rng, spine_c) * 0.8, rpick(rng, spine_c), 0.95, 0.95, rough=0.4)
            a0 = rng.normal(0, 0.3) - math.pi / 2
            cv.blade(x, y, a0, 52 * s, 1.5 * s, 0.3 * s, 6 * s * rng.normal(), spine_c[0] * 0.8, spine_c[0], 0.97, 0.97, rough=0.4)
    h = cv.h
    col = cv.c
    ao = cavity_ao(h, radii=(2, 7, 20), weights=(0.3, 0.4, 0.3), gain=2.4)
    col = apply_ao(col, ao, 0.7)
    col = tint_speckle(ctx, col, 0.05)
    return dict(albedo=col, height=h, ao=ao, rough=cv.r, slope=0.32)


@recipe("moss", [1.0, 1.0], "Dense cushion moss carpet: bright saturated greens, rounded clumps with fine upright leaflets (1 m tile).",
        "nature", albedo=(0.04, 0.22))
def moss(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    w = ctx.worley(34)
    w2 = ctx.worley(90)
    dome = np.clip(1 - w.f1 / 0.9, 0, 1) ** 0.6
    dome2 = np.clip(1 - w2.f1 / 0.9, 0, 1) ** 0.6
    h0 = 0.45 * dome + 0.2 * dome2 + 0.15 * w.rid + 0.1 * ctx.fbm01(10, 4)
    base = ramp(0.5 * w.rid + 0.5 * ctx.fbm01(30, 4), stops("#1d3a10", "#2f5a1a", "#477d24", "#69a032", "#8cb847"))
    cv = ctx.canvas()
    cv.c = base * (0.7 + 0.5 * dome)[..., None]
    cv.h = h0.astype(f32)
    cv.r[:] = 0.85
    N = int(22000 * s * s)
    xs, ys = rng.random(N) * n, rng.random(N) * n
    ix, iy = xs.astype(int), ys.astype(int)
    tcol = np.clip(0.4 + 0.8 * (w.rid[iy, ix] - 0.5) + rng.normal(0, 0.18, N), 0, 1)
    cols = ramp(tcol, stops("#2a5014", "#3f7020", "#5c9430", "#84b645", "#a6cc5e"))
    for i in range(N):
        L = (7 + 11 * rng.random()) * s
        a = -math.pi / 2 + rng.normal(0, 1.0)
        c = cols[i]
        cv.blade(xs[i], ys[i], a, L, 0.9 * s, 0.1 * s, L * rng.normal(0, 0.2), c * 0.55, c * 1.15, 0.5 + 0.4 * rng.random(), 0.7, rough=0.8)
    h = blur(cv.h, 0.6 * s)
    col = cv.c * (0.85 + 0.30 * ctx.fbm01(50, 3))[..., None]
    ao = cavity_ao(h, radii=(1.5, 5, 14), weights=(0.4, 0.4, 0.2), gain=2.2)
    col = apply_ao(col, ao, 0.7)
    col = tint_speckle(ctx, col, 0.05)
    # leaflet tips are drier / smoother, the shaded cushion base and damp patches are rougher
    rough = rough_field(ctx, 0.84, h, h_amp=0.07, macro_amp=0.06, macro_f=4, ao=ao, ao_amp=0.08, fine_amp=0.012)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.28)


# ======================================================================================
# atlas helpers
# ======================================================================================
def _leaf_hfn(t, sn):
    mid = np.exp(-(sn / 0.08) ** 2)
    return (0.5 + 0.10 * (1 - sn * sn) + 0.08 * mid * (1 - 0.5 * t) - 0.05 * t).astype(f32)


def _sn(x):
    return np.maximum(np.sin(x), 0.0)


def _wprof(kind, serr=0.0, K=22.0):
    def base(t):
        t = np.clip(t, 0, 1)
        if kind == "ovate":
            return _sn(np.pi * t ** 0.75) ** 0.85
        if kind == "elliptic":
            return _sn(np.pi * t) ** 0.7
        if kind == "obovate":
            return _sn(np.pi * t ** 1.45) ** 0.8
        if kind == "lance":
            return 0.78 * _sn(np.pi * t ** 0.9) ** 1.2
        if kind == "cordate":
            return _sn(np.pi * t ** 0.7) ** 0.8 + 0.55 * np.exp(-(t / 0.10) ** 2)
        if kind == "lobed":
            b = _sn(np.pi * t ** 0.8) ** 0.8
            return b * (0.55 + 0.45 * (0.5 + 0.5 * np.cos(t * TAU * 4.5 + 1.2)))
        if kind == "round":
            return _sn(np.pi * t ** 0.9) ** 0.5
        raise ValueError(kind)

    def f(t):
        w = base(t)
        if serr:
            w = w * (1 - serr * np.mod(t * K, 1.0))
        return w.astype(f32)
    return f


def draw_leaf(cv, x, y, ang, L, Wd, kind, col, rng, k, serr=0.0, vein=0.30, bendf=0.06, petiole=True):
    ca, sa = math.cos(ang), math.sin(ang)
    if petiole:
        pl = L * 0.16
        pc = C("#5f7a38") * 0.9
        cv.blade(x - ca * pl, y - sa * pl, ang, pl + 2 * k, 2.0 * k, 1.3 * k, 0, pc * 0.9, pc, 0.52, 0.52, rough=0.6)
    cv.blade(x, y, ang, L, Wd / 2, 0.0, L * rng.normal(0, bendf), colfn=leaf_colfn(col, vein, 7, 0.22, 0.07),
             wprof=_wprof(kind, serr), hfn=_leaf_hfn, rough=0.55)


def draw_maple(cv, x, y, R, col, rng, k, rot=0.0):
    pts = []
    for i in range(160):
        th = TAU * i / 160 + rot - math.pi / 2
        r = R * (0.28 + 0.72 * abs(math.cos(2.5 * (th - rot + math.pi / 2))) ** 1.4)
        r *= 1 + 0.05 * math.sin(th * 26) * (1 if r > 0.5 * R else 0)
        pts.append((x + r * math.cos(th), y + r * math.sin(th)))
    cv.polygon(pts, col=col, h=0.55, rough=0.55)
    for q in range(5):
        th = rot - math.pi / 2 + TAU * q / 5
        cv.blade(x, y, th, R * 0.9, 1.8 * k, 0.5 * k, 0, col * 1.35, col * 1.2, 0.58, 0.56, rough=0.55)
        for side in (-1, 1):
            cv.blade(x + math.cos(th) * R * 0.35, y + math.sin(th) * R * 0.35, th + side * 0.6, R * 0.35, 1.0 * k, 0.3 * k, 0,
                     col * 1.2, col * 1.15, 0.56, 0.55, rough=0.55)
    cv.blade(x, y, math.pi / 2 + rot * 0.2, R * 0.55, 2.2 * k, 1.5 * k, 0, C("#6a7a3a"), C("#6a7a3a"), 0.52, 0.52)


# Atlas cell hygiene (all values in pixels of a 2048 atlas, scaled by n/2048):
#   GUTTER_PX  required fully transparent ring around every cell -> verified by qa.verify
#   SAFE_PX    margin the artwork is *designed* to stay inside (tips are shortened, never cut)
#   CLIP_PX    hard safety clip inset; if it ever bites, the gutter check fails loudly
GUTTER_PX = 8
SAFE_PX = 16
CLIP_PX = 6


def _clip(cv, ox, oy, w, h):
    g = CLIP_PX * cv.n / 2048.0
    cv.wrap = False
    cv.clip = (int(round(ox + g)), int(round(oy + g)), int(round(ox + w - g)), int(round(oy + h - g)))


def _safe(cv, ox, oy, w, h, margin=SAFE_PX):
    """Design rectangle of one atlas cell (x0, y0, x1, y1): artwork must stay inside."""
    g = margin * cv.n / 2048.0
    return (ox + g, oy + g, ox + w - g, oy + h - g)


def _room(rect, x, y, ang):
    """Distance from (x, y) along `ang` to the border of rect (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = rect
    dx, dy = math.cos(ang), math.sin(ang)
    t = 1e9
    if dx > 1e-9:
        t = min(t, (x1 - x) / dx)
    elif dx < -1e-9:
        t = min(t, (x0 - x) / dx)
    if dy > 1e-9:
        t = min(t, (y1 - y) / dy)
    elif dy < -1e-9:
        t = min(t, (y0 - y) / dy)
    return max(t, 0.0)


def _finish_atlas(ctx, cv, mott_f=26, nstr=3.0, rough=0.55, extra=None):
    col = cv.c * (0.84 + 0.32 * ctx.fbm01(mott_f, 4))[..., None]
    col = col * (0.92 + 0.16 * ctx.fbm01(120, 3))[..., None]
    col = bleed_colour(col, cv.a)
    h = cv.h
    n = ctx.n
    ao = np.ones((n, n), f32)
    r = np.full((n, n), rough, f32)
    res = dict(albedo=col, alpha=cv.a, height=h, ao=ao, rough=r, nstr=nstr, write_h=False)
    meta = dict(extra or {})
    meta["gutter_px"] = round(GUTTER_PX * n / 2048.0, 2)      # alpha is exactly 0 in this ring of every cell
    res["meta"] = meta
    return res


LEAF_GREENS = pal("#2f5a1e", "#3f7226", "#4f8a2c", "#36682a", "#5a9a34", "#2c5424")
AUTUMN = pal("#c9a227", "#d8b23a", "#c46a1c", "#a63a16", "#8a5a22", "#b98a2e")


@recipe("leaf_atlas_broadleaf", [2.0, 2.0],
        "Broadleaf foliage atlas (RGBA), 4x4 cells of 512 px: 12 single leaves (ovate, elliptic, obovate, lanceolate, cordate, serrate, oak-lobed, maple, 4 autumn) and 4 leafy twig cards.",
        "nature", size_mult=2, albedo=(0.03, 0.20),
        tileable=False,
        notes="Cell (r,c) at [c*512, r*512, 512, 512] px (2048 atlas). Straight alpha with colour bleed under transparent texels.")
def leaf_atlas_broadleaf(ctx):
    n = ctx.n
    k = n / 2048.0
    cs = 512 * k
    rng = ctx.rng_k()
    cv = ctx.canvas(color=(0, 0, 0), h=0.5, alpha=0.0)
    singles = [("ovate", 0, 0, 0.0), ("elliptic", 0, 1, 0.0), ("obovate", 0, 2, 0.0), ("lance", 0, 3, 0.0),
               ("cordate", 1, 0, 0.0), ("ovate", 1, 1, 0.07), ("lobed", 1, 2, 0.0), ("maple", 1, 3, 0.0),
               ("ovate", 2, 0, 0.0), ("lobed", 2, 1, 0.0), ("maple", 2, 2, 0.0), ("elliptic", 2, 3, 0.04)]
    for kind, r, c, serr in singles:
        ox, oy = c * cs, r * cs
        _clip(cv, ox, oy, cs, cs)
        if r == 2:
            col = rpick(rng, [C("#c9a227"), C("#c46a1c"), C("#a63a16"), C("#b98a2e")])
            if c == 3:
                col = C("#7a5a28")
        else:
            col = LEAF_GREENS[(r * 4 + c) % len(LEAF_GREENS)]
        ang = -math.pi / 2 + rng.normal(0, 0.06)
        if kind == "maple":
            draw_maple(cv, ox + cs * 0.5, oy + cs * 0.53, cs * 0.42, col, rng, k, rng.normal(0, 0.05))
        else:
            Wd = {"ovate": 0.50, "elliptic": 0.40, "obovate": 0.50, "lance": 0.28, "cordate": 0.62, "lobed": 0.50}[kind] * cs * 0.86
            # leaf blade + petiole (0.16 L) fit inside the safe rectangle: top gap ~36 px, bottom gap ~16 px
            draw_leaf(cv, ox + cs * 0.5, oy + cs * 0.845, ang, cs * 0.775, Wd, kind, col, rng, k, serr, vein=0.30)
    # twig cards
    twig_kinds = [("ovate", 0.0, 0.34, 9), ("elliptic", 0.04, 0.30, 11), ("obovate", 0.07, 0.32, 8), ("lobed", 0.0, 0.30, 8)]
    for ci, (kind, serr, size, nl) in enumerate(twig_kinds):
        ox, oy = ci * cs, 3 * cs
        _clip(cv, ox, oy, cs, cs)
        rect = _safe(cv, ox, oy, cs, cs)
        p0 = (ox + cs * 0.5, oy + cs * 0.955)
        p1 = (ox + cs * (0.5 + rng.uniform(-0.18, 0.18)), oy + cs * 0.62)
        p2 = (ox + cs * (0.5 + rng.uniform(-0.22, 0.22)), oy + cs * 0.27)
        pts = bezier(p0, p1, p2, 40)
        tw = C("#5a4630")
        for i in range(len(pts) - 1):
            dx, dy = pts[i + 1] - pts[i]
            ln = math.hypot(dx, dy) + 1.5
            cv.blade(pts[i][0], pts[i][1], math.atan2(dy, dx), ln, (3.6 - 2.0 * i / 40) * k, (3.6 - 2.0 * (i + 1) / 40) * k, 0,
                     tw * 0.8, tw, 0.52, 0.55, rough=0.8)
        cols = [LEAF_GREENS[(ci + j) % len(LEAF_GREENS)] for j in range(nl)]
        for j in range(nl):
            t = 0.20 + 0.72 * j / max(nl - 1, 1)
            pos = bezier(p0, p1, p2, 41)[int(t * 40)]
            tg = bezier_tangent(p0, p1, p2, t)
            side = 1 if j % 2 == 0 else -1
            ang = math.atan2(tg[1], tg[0]) + side * rng.uniform(0.75, 1.1)
            sz = size * cs * (1.05 - 0.45 * t)
            # leaves that would reach past the cell's safe rectangle are made smaller (never cut)
            sz *= min(1.0, 0.86 * _room(rect, pos[0], pos[1], ang) / sz)
            if kind == "lobed":
                draw_leaf(cv, pos[0], pos[1], ang, sz, sz * 0.62, kind, cols[j], rng, k, serr, 0.28, 0.08)
            else:
                draw_leaf(cv, pos[0], pos[1], ang, sz, sz * 0.52, kind, cols[j], rng, k, serr, 0.28, 0.08)
        tip = bezier(p0, p1, p2, 41)[-1]
        tg = bezier_tangent(p0, p1, p2, 1.0)
        tang = math.atan2(tg[1], tg[0])
        tsz = size * cs * 0.65
        tsz *= min(1.0, 0.86 * _room(rect, tip[0], tip[1], tang) / tsz)
        draw_leaf(cv, tip[0], tip[1], tang, tsz, tsz * 0.52, kind, cols[0], rng, k, serr, 0.28, 0.05)
    cells = {"cell_px": 512 * k, "grid": [4, 4]}
    return _finish_atlas(ctx, cv, 26, 3.0, 0.55, cells)


@recipe("needle_atlas", [1.0, 1.0],
        "Conifer foliage atlas (RGBA), 4x4 cells: row0 spruce twigs, row1 pine needle bunches, row2 fir flat sprays, row3 dry/brown and young tips.",
        "nature", size_mult=2, albedo=(0.02, 0.15),
        tileable=False,
        notes="Cell (r,c) at [c*512, r*512, 512, 512] px (2048 atlas).")
def needle_atlas(ctx):
    n = ctx.n
    k = n / 2048.0
    cs = 512 * k
    rng = ctx.rng_k()
    cv = ctx.canvas(color=(0, 0, 0), h=0.5, alpha=0.0)
    spruce = pal("#1f3d22", "#2b5230", "#35633a", "#46783f")
    pine = pal("#3f6f2e", "#4f8236", "#5f9340", "#365f2a")
    fir = pal("#244a2c", "#2f5c36", "#3b6e3e", "#1c3d24")
    dry = pal("#8a6a3a", "#a07a44", "#6a4a28", "#b08a50")
    young = pal("#6ea03e", "#83b44a", "#5a8a34", "#96c455")
    brown = C("#5a4430")

    def twig(ox, oy, bend):
        p0 = (ox + cs * 0.5, oy + cs * 0.962)
        p1 = (ox + cs * (0.5 + bend * 0.7), oy + cs * 0.56)
        p2 = (ox + cs * (0.5 + bend), oy + cs * 0.09)
        pts = bezier(p0, p1, p2, 48)
        for i in range(len(pts) - 1):
            dx, dy = pts[i + 1] - pts[i]
            cv.blade(pts[i][0], pts[i][1], math.atan2(dy, dx), math.hypot(dx, dy) + 1.5,
                     (3.2 - 1.6 * i / 48) * k, (3.2 - 1.6 * (i + 1) / 48) * k, 0, brown * 0.8, brown, 0.52, 0.55, rough=0.8)
        return p0, p1, p2

    def needles(p0, p1, p2, palette, M, per, Lmax, ang_rng, taper, width, drop=0.0, flat=False):
        for j in range(M):
            t = 0.07 + 0.90 * j / (M - 1)
            pos = bezier(p0, p1, p2, 49)[int(t * 48)]
            tg = bezier_tangent(p0, p1, p2, t)
            base = math.atan2(tg[1], tg[0])
            for q in range(per):
                if rng.random() < drop:
                    continue
                side = 1 if (q + j) % 2 == 0 else -1
                a = base + side * rng.uniform(*ang_rng)
                if not flat and rng.random() < 0.25:
                    a = base + rng.normal(0, 0.5)
                L = Lmax * k * (0.45 + 0.55 * math.sin(math.pi * min(1.0, t * 1.05) ** taper)) * rng.uniform(0.75, 1.1)
                L = min(L, 0.86 * _room(cell_rect[0], pos[0], pos[1], a))     # shorten, never cut
                if L < 6 * k:
                    continue
                c = rpick(rng, palette)
                cv.blade(pos[0], pos[1], a, L, width * k, 0.25 * k, L * rng.normal(0, 0.06), c * 0.65, c * 1.15,
                         0.52 + 0.05 * rng.random(), 0.56, rough=0.5)

    cell_rect = [None]

    def begin(c, r):
        ox, oy = c * cs, r * cs
        _clip(cv, ox, oy, cs, cs)
        cell_rect[0] = _safe(cv, ox, oy, cs, cs)
        return ox, oy

    # row 0: spruce twigs (needles all around)
    for c in range(4):
        ox, oy = begin(c, 0)
        p0, p1, p2 = twig(ox, oy, rng.uniform(-0.22, 0.22))
        needles(p0, p1, p2, spruce, 70, 4, 92, (0.75, 1.35), 0.6, 2.6, 0.0)
    # row 1: pine bunches of 2-3 long needles
    for c in range(4):
        ox, oy = begin(c, 1)
        p0, p1, p2 = twig(ox, oy, rng.uniform(-0.2, 0.2))
        for j in range(20):
            t = 0.10 + 0.85 * j / 19
            pos = bezier(p0, p1, p2, 49)[int(t * 48)]
            tg = bezier_tangent(p0, p1, p2, t)
            base = math.atan2(tg[1], tg[0])
            side = 1 if j % 2 == 0 else -1
            a0 = base + side * rng.uniform(0.7, 1.2)
            for q in range(int(rng.integers(2, 4))):
                a = a0 + rng.normal(0, 0.10)
                L = (150 + 100 * rng.random()) * k * (1.05 - 0.35 * t)
                L = min(L, 0.86 * _room(cell_rect[0], pos[0], pos[1], a))     # shorten, never cut
                if L < 20 * k:
                    continue
                cc = rpick(rng, pine)
                cv.blade(pos[0], pos[1], a, L, 3.0 * k, 0.3 * k, L * rng.normal(0, 0.07) * (1 if side > 0 else -1), cc * 0.7, cc * 1.15, 0.52, 0.56, rough=0.5)
            cv.oval(pos[0], pos[1], 4.5 * k, 3.5 * k, a0, col=C("#7a5a38"), h0=0.58, hdome=0.05)
    # row 2: fir flat sprays
    for c in range(4):
        ox, oy = begin(c, 2)
        p0, p1, p2 = twig(ox, oy, rng.uniform(-0.15, 0.15))
        needles(p0, p1, p2, fir, 44, 2, 112, (1.25, 1.50), 0.8, 2.6, 0.04, True)
    # row 3: dry / brown + young tips
    for c in range(4):
        ox, oy = begin(c, 3)
        p0, p1, p2 = twig(ox, oy, rng.uniform(-0.25, 0.25))
        if c < 2:
            needles(p0, p1, p2, dry, 58, 4, 70, (0.75, 1.35), 0.7, 1.7, 0.30)
        else:
            needles(p0, p1, p2, spruce, 40, 3, 66, (0.75, 1.3), 0.6, 1.8, 0.1)
            needles(p0, p1, p2, young, 24, 3, 46, (0.6, 1.1), 0.5, 2.0, 0.1)
    return _finish_atlas(ctx, cv, 30, 3.0, 0.5, {"cell_px": 512 * k, "grid": [4, 4]})


@recipe("palm_frond_atlas", [2.0, 2.0],
        "Palm foliage atlas (RGBA), 2x2 cells of 1024 px: coconut-style arching frond, date-style stiff frond, fan palm leaf, dry frond.",
        "nature", size_mult=2, albedo=(0.02, 0.18),
        tileable=False,
        notes="Cell (r,c) at [c*1024, r*1024, 1024, 1024] px (2048 atlas).")
def palm_frond_atlas(ctx):
    n = ctx.n
    k = n / 2048.0
    cs = 1024 * k
    rng = ctx.rng_k()
    cv = ctx.canvas(color=(0, 0, 0), h=0.5, alpha=0.0)
    greens = pal("#2c5a24", "#3c7230", "#4f8a38", "#2f6428")
    drys = pal("#8a6a38", "#a8843f", "#6e5230", "#b8964a")
    mid_c = C("#9fbd62")
    rach_c = C("#6e8a3c")

    def rachis(pts, w0, w1, col):
        m = len(pts) - 1
        for i in range(m):
            dx, dy = pts[i + 1] - pts[i]
            cv.blade(pts[i][0], pts[i][1], math.atan2(dy, dx), math.hypot(dx, dy) + 1.5,
                     (w0 + (w1 - w0) * i / m) * k, (w0 + (w1 - w0) * (i + 1) / m) * k, 0, col * 0.8, col * 1.05, 0.58, 0.6, hround=0.05, rough=0.6)

    def leaflet(pos, ang, L, w, palette, droop, taper_col=True):
        ca = math.cos(ang)
        bend = L * droop * (1 if ca >= 0 else -1)
        c = rpick(rng, palette)
        cv.blade(pos[0], pos[1], ang, L, w * k, 0.2 * k, bend, colfn=leaf_colfn(c, 0.35, 0, 0.10, 0.12), hfn=_leaf_hfn, rough=0.5)

    def feather(cell_r, cell_c, p0, p1, p2, N, Lmax, w, ang_rng, droop, palette, gaps=0.0, break_p=0.0):
        ox, oy = cell_c * cs, cell_r * cs
        _clip(cv, ox, oy, cs, cs)
        P0 = (ox + p0[0] * cs, oy + p0[1] * cs)
        P1 = (ox + p1[0] * cs, oy + p1[1] * cs)
        P2 = (ox + p2[0] * cs, oy + p2[1] * cs)
        pts = bezier(P0, P1, P2, 60)
        for j in range(N):
            t = 0.10 + 0.88 * j / (N - 1)
            pos = bezier(P0, P1, P2, 61)[int(t * 60)]
            tg = bezier_tangent(P0, P1, P2, t)
            base = math.atan2(tg[1], tg[0])
            for side in (-1, 1):
                if rng.random() < gaps:
                    continue
                a = base + side * rng.uniform(*ang_rng)
                L = Lmax * k * (0.30 + 0.70 * math.sin(math.pi * (0.18 + 0.82 * t) ** 0.9)) * rng.uniform(0.85, 1.1)
                if rng.random() < break_p:
                    L *= rng.uniform(0.25, 0.6)
                leaflet(pos, a, L, w, palette, droop)
        rachis(pts, 7.0, 2.2, rach_c if palette is greens else C("#7a5a30"))

    # coconut-style arching frond (top-left)
    feather(0, 0, (0.22, 0.94), (0.40, 0.10), (0.84, 0.50), 52, 270, 7.0, (0.85, 1.15), 0.30, greens)
    # date palm (top-right): stiffer, more upright leaflets
    feather(0, 1, (0.50, 0.97), (0.46, 0.57), (0.54, 0.095), 64, 250, 5.0, (0.30, 0.55), 0.04, greens)
    # fan palm (bottom-left)
    ox, oy = 0 * cs, 1 * cs
    _clip(cv, ox, oy, cs, cs)
    cx, cy = ox + cs * 0.5, oy + cs * 0.60
    pet = bezier((cx, oy + cs * 0.962), (cx - 8 * k, oy + cs * 0.80), (cx, cy), 20)
    nseg = 25
    for i in range(nseg):
        th = math.radians(-195 + 210 * i / (nseg - 1))
        L = cs * rng.uniform(0.36, 0.46)
        c = rpick(rng, greens)
        for sub in (-1, 0, 1):
            a = th + sub * 0.035
            cv.blade(cx, cy, a, L * (0.92 if sub else 1.0), 15 * k, 0.5 * k, L * 0.10 * (1 if math.cos(a) >= 0 else -1),
                     colfn=leaf_colfn(c, 0.3, 0, 0.12, 0.10), hfn=_leaf_hfn, rough=0.5)
    rachis(pet, 8.0, 5.0, C("#6a7a3a"))
    # dry frond (bottom-right)
    feather(1, 1, (0.22, 0.94), (0.40, 0.12), (0.84, 0.54), 46, 260, 6.0, (0.80, 1.20), 0.35, drys, gaps=0.15, break_p=0.35)
    return _finish_atlas(ctx, cv, 22, 3.0, 0.5, {"cell_px": 1024 * k, "grid": [2, 2]})


@recipe("grass_blade_atlas", [1.0, 2.0],
        "Grass tuft card atlas (RGBA), 4x2 cells of 512x1024 px: top row green tufts, bottom row dry/straw tufts. Blades grow from the bottom centre of each cell.",
        "nature", size_mult=2, albedo=(0.04, 0.30),
        tileable=False,
        notes="Cell (r,c) at [c*512, r*1024, 512, 1024] px (2048 atlas).")
def grass_blade_atlas(ctx):
    n = ctx.n
    k = n / 2048.0
    cw, ch = 512 * k, 1024 * k
    rng = ctx.rng_k()
    cv = ctx.canvas(color=(0, 0, 0), h=0.5, alpha=0.0)
    for r in range(2):
        for c in range(4):
            ox, oy = c * cw, r * ch
            _clip(cv, ox, oy, cw, ch)
            nb = int(rng.integers(30, 46))
            lean_amp = [0.11, 0.16, 0.22, 0.14][c]
            half = cw / 2 - 34 * k          # lateral reach limit (tip / blade edge) from the cell centre line
            for i in range(nb):
                jx = float(np.clip(rng.normal(0, 0.035), -0.045, 0.045))
                x = ox + cw * (0.5 + jx)
                y = oy + ch * 0.978
                lean = rng.normal(0, lean_amp)
                L = ch * rng.uniform(0.40, 0.86) * (0.9 if c == 1 else 1.0)
                w0 = rng.uniform(4.5, 8.0) * k
                bf = rng.uniform(0.05, 0.20)
                # Soft-limit how far the tip may splay sideways so every blade stays inside the cell's
                # gutter: tall blades stand more upright, short ones may fan out (no flat cuts, no overlap
                # with the neighbouring tuft).
                lim = half - abs(jx * cw) - w0

                def reach(ln, bb):
                    return L * (abs(math.sin(ln)) + math.cos(ln) * bb)
                off = reach(lean, bf)
                knee = 0.55 * lim
                if off > knee:
                    tgt = knee + (lim - knee) * math.tanh((off - knee) / (lim - knee))
                    sc = tgt / off
                    for _ in range(4):
                        if reach(lean * sc, bf * sc) <= tgt:
                            break
                        sc *= 0.97
                    lean, bf = lean * sc, bf * sc
                ang = -math.pi / 2 + lean
                bend = L * np.sign(lean + 1e-6) * bf
                if r == 0:
                    base = [C("#1f3f12"), C("#2f5a1a"), C("#254c14")][int(rng.integers(0, 3))]
                    tip = [C("#7aa63a"), C("#6c9a34"), C("#9ab84a")][int(rng.integers(0, 3))]
                else:
                    base = [C("#6e5a2a"), C("#7d6632"), C("#5e4c24")][int(rng.integers(0, 3))]
                    tip = [C("#cbb36a"), C("#d6c27a"), C("#b8a05a")][int(rng.integers(0, 3))]

                def colfn(t, sn, base=base, tip=tip):
                    cc = base + (tip - base) * np.clip(t * 1.1, 0, 1)[..., None]
                    mid = np.exp(-(sn / 0.12) ** 2) * 0.25
                    return (cc * (1 + mid[..., None] - 0.15 * np.abs(sn)[..., None] ** 3)).astype(f32)
                cv.blade(x, y, ang, L, w0, 0.0, bend, colfn=colfn, wprof=lambda t: np.clip(1 - np.clip(t, 0, 1) ** 1.35, 0, 1) ** 0.9,
                         hfn=lambda t, sn: (0.5 + 0.14 * (1 - sn * sn) + 0.04 * np.exp(-(sn / 0.12) ** 2)).astype(f32), rough=0.55)
    return _finish_atlas(ctx, cv, 20, 3.0, 0.55, {"cell_px": [512 * k, 1024 * k], "grid": [4, 2]})


@recipe("flower_atlas", [1.0, 1.0],
        "Wildflower atlas (RGBA), 2x2 cells of 1024 px: daisies, poppies, lavender spikes, buttercups; each plant has stem and leaves, base at bottom centre.",
        "nature", size_mult=2, albedo=(0.04, 0.35),
        tileable=False,
        notes="Cell (r,c) at [c*1024, r*1024, 1024, 1024] px (2048 atlas).")
def flower_atlas(ctx):
    n = ctx.n
    k = n / 2048.0
    cs = 1024 * k
    rng = ctx.rng_k()
    cv = ctx.canvas(color=(0, 0, 0), h=0.5, alpha=0.0)
    stem_c = C("#4a6e2c")
    leaf_c = [C("#3a6428"), C("#4a7a30"), C("#2f5a22")]

    def stem(p0, p1, p2, w0=5.0, w1=3.0, col=stem_c):
        pts = bezier(p0, p1, p2, 36)
        for i in range(len(pts) - 1):
            dx, dy = pts[i + 1] - pts[i]
            cv.blade(pts[i][0], pts[i][1], math.atan2(dy, dx), math.hypot(dx, dy) + 1.2,
                     (w0 + (w1 - w0) * i / 35) * k, (w0 + (w1 - w0) * (i + 1) / 35) * k, 0, col * 0.8, col * 1.1, 0.52, 0.56, hround=0.04, rough=0.6)
        return pts

    def leaf(x, y, ang, L, W, col, kind="lance"):
        draw_leaf(cv, x, y, ang, L, W, kind, col, rng, k, 0.0, 0.3, 0.1, petiole=False)

    def petal(cx, cy, ang, L, W, col, hole=False, vein=0.12):
        def colfn(t, sn):
            kk = 0.82 + 0.28 * t[..., None] - 0.16 * np.abs(sn)[..., None] ** 2 + vein * np.exp(-(sn[..., None] / 0.10) ** 2) * 0
            return (col * kk).astype(f32)
        cv.blade(cx, cy, ang, L, W / 2, 0.0, 0, colfn=colfn, wprof=lambda t: _sn(np.pi * np.clip(t, 0, 1) ** 0.65) ** 0.7,
                 hfn=lambda t, sn: (0.55 + 0.1 * (1 - sn * sn) - 0.04 * t).astype(f32), rough=0.5)

    def daisy(cx, cy, R, rot):
        for i in range(21):
            a = rot + TAU * i / 21 + rng.normal(0, 0.03)
            petal(cx, cy, a, R * rng.uniform(0.92, 1.05), R * 0.20, C("#f3f1ea") * f32(rng.uniform(0.93, 1.0)))
        cv.oval(cx, cy, R * 0.30, R * 0.30, 0, col=C("#e2b422"), h0=0.6, hdome=0.12, irr=0.04, rng=rng, edge_dark=0.25)
        for i in range(70):
            a = rng.random() * TAU
            r_ = R * 0.27 * math.sqrt(rng.random())
            cv.oval(cx + r_ * math.cos(a), cy + r_ * math.sin(a), 2.6 * k, 2.6 * k, 0, col=C("#f5cf3a") * f32(0.8 + 0.3 * rng.random()), h0=0.7, hdome=0.05)

    def poppy(cx, cy, R, rot):
        for i in range(5):
            a = rot + TAU * i / 5 + rng.normal(0, 0.12)
            ox_, oy_ = cx + math.cos(a) * R * 0.30, cy + math.sin(a) * R * 0.30
            petal(ox_, oy_, a, R * 0.78, R * 0.95, C("#cf2a1c") * f32(rng.uniform(0.85, 1.05)))
        cv.oval(cx, cy, R * 0.20, R * 0.20, 0, col=C("#16100e"), h0=0.65, hdome=0.1, edge_dark=0.2)
        cv.oval(cx, cy, R * 0.10, R * 0.10, 0, col=C("#6a7a3a"), h0=0.7, hdome=0.1)
        for i in range(34):
            a = rng.random() * TAU
            r_ = R * rng.uniform(0.14, 0.24)
            cv.blade(cx, cy, a, r_, 1.3 * k, 1.8 * k, 0, C("#1a1412"), C("#2a2420"), 0.7, 0.72)

    def buttercup(cx, cy, R, rot):
        for i in range(5):
            a = rot + TAU * i / 5
            ox_, oy_ = cx + math.cos(a) * R * 0.45, cy + math.sin(a) * R * 0.45
            cv.oval(ox_, oy_, R * 0.55, R * 0.50, a, col=C("#f4c919") * f32(rng.uniform(0.9, 1.05)), h0=0.58, hdome=0.12,
                    irr=0.05, rng=rng, edge_dark=0.15, rough=0.35)
        cv.oval(cx, cy, R * 0.22, R * 0.22, 0, col=C("#b8860b"), h0=0.7, hdome=0.1)
        for i in range(24):
            a = rng.random() * TAU
            r_ = R * rng.uniform(0.04, 0.2)
            cv.oval(cx + r_ * math.cos(a), cy + r_ * math.sin(a), 2.2 * k, 2.2 * k, 0, col=C("#e0a010"), h0=0.76, hdome=0.04)

    def plant(ci, rj, head_fn, n_heads, R, leaves=3):
        ox, oy = ci * cs, rj * cs
        _clip(cv, ox, oy, cs, cs)
        for hI in range(n_heads):
            bx = ox + cs * (0.5 + rng.uniform(-0.12, 0.12) * (hI > 0))
            by = oy + cs * 0.972
            hx = ox + cs * (0.5 + (hI - (n_heads - 1) / 2) * rng.uniform(0.20, 0.27) + rng.normal(0, 0.03))
            hy = oy + cs * (0.26 + 0.12 * hI + rng.normal(0, 0.03))
            sc = stem((bx, by), (bx + rng.normal(0, 0.12) * cs, oy + cs * 0.6), (hx, hy))
            for j in range(leaves):
                t = 0.15 + 0.5 * rng.random()
                p = sc[int(t * 35)]
                side = rng.choice([-1, 1])
                leaf(p[0], p[1], -math.pi / 2 + side * rng.uniform(0.55, 1.0), cs * rng.uniform(0.16, 0.26), cs * rng.uniform(0.05, 0.08),
                     leaf_c[int(rng.integers(0, 3))])
            head_fn(hx, hy, R * rng.uniform(0.85, 1.1), rng.random() * TAU)

    plant(0, 0, daisy, 3, cs * 0.17)
    plant(1, 0, poppy, 3, cs * 0.14)
    plant(1, 1, buttercup, 3, cs * 0.10)
    # lavender (cell 0,1)
    ox, oy = 0 * cs, 1 * cs
    _clip(cv, ox, oy, cs, cs)
    for sI in range(5):
        bx = ox + cs * (0.5 + rng.normal(0, 0.10))
        by = oy + cs * 0.972
        tip = (bx + rng.normal(0, 0.07) * cs, oy + cs * rng.uniform(0.07, 0.20))
        sc = stem((bx, by), (bx + rng.normal(0, 0.05) * cs, oy + cs * 0.6), tip, 3.5, 2.2, C("#6c8250"))
        for j in range(6):
            t = rng.uniform(0.05, 0.4)
            p = sc[int(t * 35)]
            side = rng.choice([-1, 1])
            leaf(p[0], p[1], -math.pi / 2 + side * rng.uniform(0.2, 0.6), cs * rng.uniform(0.18, 0.30), cs * 0.025, C("#6a8a58"))
        # florets: whorls along the top 40% of the stem
        for j in range(120):
            t = 0.58 + 0.42 * (j / 119)
            p = sc[int(min(t, 0.999) * 35)]
            tg = sc[min(int(t * 35) + 1, 35)] - sc[int(t * 35)]
            a0 = math.atan2(tg[1], tg[0])
            for q in range(2):
                a = a0 + rng.normal(0, 1.2) + (math.pi / 2 if q else -math.pi / 2)
                r_ = rng.uniform(4, 11) * k
                cv.oval(p[0] + math.cos(a) * r_, p[1] + math.sin(a) * r_, 9 * k, 5.5 * k, a, col=rpick(rng, [C("#6a4a9a"), C("#7e5db0"), C("#5a3e8a"), C("#9a7fc4")]),
                        h0=0.58, hdome=0.1, irr=0.1, rng=rng)
    return _finish_atlas(ctx, cv, 24, 3.0, 0.5, {"cell_px": 1024 * k, "grid": [2, 2],
                                                   "cells": {"daisy": [0, 0], "poppy": [1, 0], "lavender": [0, 1], "buttercup": [1, 1]}})
