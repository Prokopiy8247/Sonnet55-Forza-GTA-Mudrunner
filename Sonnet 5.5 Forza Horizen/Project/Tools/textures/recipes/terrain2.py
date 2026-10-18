"""Terrain texture recipes, part 2: rocks, sands, snow, gravel, mud, dirt."""
from __future__ import annotations

import math

import numpy as np

from ..core import recipe
from ..maps import ramp, lerp, luminance, cavity_ao
from ..noise import f32, norm01, smoothstep, blur
from .common import (C, pal, stops, S, rpick, apply_ao, tint_speckle, sample_at, hash01, rough_field)

TAU = 2 * math.pi


# ======================================================================================
# rocks
# ======================================================================================
def _prof_blur(a, sigma):
    """periodic 1D gaussian blur of a table"""
    n = a.shape[0]
    k = np.fft.rfftfreq(n)
    return np.fft.irfft(np.fft.rfft(a) * np.exp(-2 * np.pi ** 2 * sigma ** 2 * k * k), n).astype(f32)


@recipe("rock_cliff", 8.0, "Cliff / canyon wall: layered sedimentary rock, differential erosion, fractured blocks (8 m tile, strata run along U).",
        "terrain", size_mult=2, albedo=(0.08, 0.30))
def rock_cliff(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    rng = ctx.rng_k()
    # ---- 1D strata tables (periodic along v)
    T = 8192
    K = 52
    th = 0.10 + rng.exponential(1.0, K) ** 1.4
    th /= th.sum()
    ends = np.cumsum(th)
    ends[-1] = 1.01
    starts = ends - th
    hd = np.clip(rng.random(K) * 1.15 - 0.08, 0, 1).astype(f32)
    tone_i = rng.random(K).astype(f32)
    red_i = (rng.random(K) < 0.12).astype(f32)
    tv = (np.arange(T, dtype=np.float64) + 0.5) / T
    it = np.minimum(np.searchsorted(ends, tv), K - 1)
    frac_t = ((tv - starts[it]) / th[it]).astype(f32)
    hard_t = hd[it]
    # second stratigraphic column (independent random layering) used where the first one pinches out
    th2 = 0.10 + rng.exponential(1.0, K) ** 1.4
    th2 /= th2.sum()
    ends2 = np.cumsum(th2)
    ends2[-1] = 1.01
    starts2 = ends2 - th2
    hd2 = np.clip(rng.random(K) * 1.15 - 0.08, 0, 1).astype(f32)
    tone_i2 = rng.random(K).astype(f32)
    red_i2 = (rng.random(K) < 0.10).astype(f32)
    it2 = np.minimum(np.searchsorted(ends2, tv), K - 1)
    frac_t2 = ((tv - starts2[it2]) / th2[it2]).astype(f32)
    hard_t2 = hd2[it2]
    lip = 0.72 + 0.28 * S(0.0, 0.10, frac_t) * (1 - 0.45 * S(0.80, 1.0, frac_t))
    rec_t = _prof_blur(hard_t * lip, 2.5)
    tone_t = _prof_blur(tone_i[it], 1.5)
    red_t = _prof_blur(red_i[it], 3.0)
    lip2 = 0.72 + 0.28 * S(0.0, 0.10, frac_t2) * (1 - 0.45 * S(0.80, 1.0, frac_t2))
    rec_t2 = _prof_blur(hard_t2 * lip2, 2.5)
    tone_t2 = _prof_blur(tone_i2[it2], 1.5)
    red_t2 = _prof_blur(red_i2[it2], 3.0)
    # ---- warp the strata
    wv = ctx.fbm(2, 3, fy=3) * 0.030 + ctx.fbm(5, 3, fy=9) * 0.008 + ctx.fbm(22, 3, fy=34) * 0.0012
    vm = np.mod(v + wv + 0.008 * np.sin(TAU * u + 0.7), f32(1.0))
    ti = np.minimum((vm * T).astype(np.int32), T - 1)
    wv2 = ctx.fbm(3, 3, fy=2) * 0.045 + ctx.fbm(8, 3, fy=12) * 0.010
    vm2 = np.mod(v + 0.37 + wv2 + 0.006 * np.sin(TAU * 2 * u + 1.9), f32(1.0))
    ti2 = np.minimum((vm2 * T).astype(np.int32), T - 1)
    lat = S(0.40, 0.60, ctx.fbm01(2, 3, fy=2) + 0.10 * ctx.fbm(9, 3, fy=3))     # 0 -> column 1, 1 -> column 2
    frac = frac_t[ti] * (1 - lat) + frac_t2[ti2] * lat
    hard_l = hard_t[ti] * (1 - lat) + hard_t2[ti2] * lat
    rec = rec_t[ti] * (1 - lat) + rec_t2[ti2] * lat
    tone = tone_t[ti] * (1 - lat) + tone_t2[ti2] * lat
    redl = red_t[ti] * (1 - lat) + red_t2[ti2] * lat
    # ---- fracture blocks (large anisotropic voronoi, partially opened cracks)
    uw, vw = ctx.warp(0.02, 4, 3)
    wk = ctx.worley(5, 3, jitter=0.95, uv=(uw, vw))
    e = wk.f2 - wk.f1
    cw = 0.012 + 0.022 * ctx.fbm01(6, 3)
    open_m = S(0.30, 0.60, ctx.fbm01(3, 3))
    crack = (1 - S(0.0, cw, e)) * (0.12 + 0.50 * open_m)
    blk_h = (wk.rid - 0.5) * 0.16 - (wk.vx * (hash01(wk.rid * 71.0) - 0.5) + wk.vy * (hash01(wk.rid * 37.0) - 0.5)) * 0.25
    wk2 = ctx.worley(15, 7, jitter=0.95, uv=(uw, vw))
    e2 = wk2.f2 - wk2.f1
    crack2 = (1 - S(0.0, 0.045, e2)) * S(0.45, 0.72, ctx.fbm01(7, 3)) * 0.8
    # third, finer fracture set at a different scale / orientation (random regional mask)
    wk3 = ctx.worley(11, 3, jitter=0.95, uv=(uw, vw))
    crack3 = (1 - S(0.0, 0.030, wk3.f2 - wk3.f1)) * S(0.40, 0.70, ctx.fbm01(5, 3, fy=2)) * 0.7
    # ---- height
    uw2, vw2 = ctx.warp(0.035, 3, 3)
    ridged = norm01(ctx.fbm(6, 7, kind="ridged", fy=18, gain=0.55, uv=(uw2, vw2)))
    chips = norm01(ctx.fbm(24, 5, kind="ridged", fy=40, gain=0.6))
    h = 0.40 * rec + 0.7 * blk_h + 0.55 * (ridged - 0.5) * (0.6 + 0.8 * hard_l) + 0.20 * (chips - 0.5)
    h = h - 0.20 * crack - 0.10 * crack2 - 0.08 * crack3
    pits = ctx.worley(140)
    h -= 0.02 * (1 - S(0.0, 0.35, pits.f1))
    h = (h - h.min()) / (h.max() - h.min())
    # ---- colour
    rock_stops = stops("#5f4c3a", "#7c6248", "#98795a", "#a88c6a", "#8d8478", "#b39d7c")
    t = np.clip(tone * 0.8 + 0.25 * (ctx.fbm01(8, 4, fy=18) - 0.5) + 0.1 * ctx.fbm01(3, 3) , 0, 1)
    col = ramp(t, rock_stops)
    col = lerp(col, C("#7d4a30"), redl * 0.42)
    lam = 0.5 + 0.5 * np.sin(TAU * (vm * 170 + 2.5 * ctx.fbm(4, 3)))
    col = col * (0.96 + 0.08 * lam * ctx.fbm01(6, 3))[..., None]
    col = col * (0.62 + 0.75 * h)[..., None]
    col = col * (0.85 + 0.30 * ctx.fbm01(40, 4, fy=14))[..., None]
    col = col * (0.92 + 0.16 * wk.rid)[..., None]
    stain = S(0.35, 0.80, ctx.fbm01(7, 4, fy=2, uv=(u + 0.03 * ctx.fbm(3, 2), v)))
    col = col * (0.78 + 0.34 * stain)[..., None]
    col = lerp(col, C("#4a3a30"), S(0.70, 0.95, ctx.fbm01(11, 4, fy=1)) * 0.22)
    streak = ctx.fbm01(26, 3, fy=3, uv=(u + 0.04 * ctx.fbm(4, 2), v))
    col = col * (0.72 + 0.4 * S(0.2, 0.8, streak))[..., None]
    dust = S(0.78, 0.98, frac) * S(0.35, 0.8, hard_l) * (0.5 + 0.5 * ctx.fbm01(30, 3))
    col = lerp(col, C("#b8a47e"), dust * 0.40)
    lich = S(0.72, 0.9, ctx.fbm01(14, 5)) * S(0.45, 0.8, ctx.fbm01(80, 3)) * S(0.3, 0.8, h)
    col = lerp(col, C("#8d9250"), lich * 0.40)
    col = col * (1 - 0.62 * crack - 0.35 * crack2 - 0.30 * crack3)[..., None]
    ao = cavity_ao(h, radii=(2, 7, 22, 60), weights=(0.25, 0.3, 0.3, 0.15), gain=3.0)
    col = apply_ao(col, ao, 0.8)
    col = tint_speckle(ctx, col, 0.06)
    rough = np.clip(0.86 + 0.05 * (1 - ao) - 0.12 * lich - 0.10 * (hard_l - 0.5) * S(0.0, 1.0, h), 0.3, 1.0)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.55, ao_gain=3.0)


@recipe("rock_grey", 4.0, "Mountain / granite rock: fractured blocks with weathering, mineral speckle and lichen (4 m tile).",
        "terrain", albedo=(0.08, 0.32))
def rock_grey(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    uw, vw = ctx.warp(0.06, 3, 4)
    w = ctx.worley(4, jitter=0.98, uv=(uw, vw))
    rid = w.rid
    gx = (hash01(rid * 97.0) - 0.5) * 1.8
    gy = (hash01(rid * 131.0) - 0.5) * 1.8
    plane = -(gx * w.vx + gy * w.vy)
    e = w.f2 - w.f1
    open_m = S(0.25, 0.55, ctx.fbm01(4, 3))
    crack = (1 - S(0.0, 0.03 + 0.03 * ctx.fbm01(7, 3), e)) * (0.3 + 0.7 * open_m)
    w3 = ctx.worley(9, 4, jitter=0.95, uv=(uw, vw))
    crack3 = (1 - S(0.0, 0.04, w3.f2 - w3.f1)) * S(0.45, 0.7, ctx.fbm01(5, 3)) * 0.8
    chamfer = S(0.0, 0.25, e) ** 0.6
    uw2, vw2 = ctx.warp(0.04, 4, 3)
    ridg = norm01(ctx.fbm(5, 7, kind="ridged", gain=0.58, uv=(uw2, vw2)))
    chips = norm01(ctx.fbm(26, 4, kind="ridged", gain=0.6))
    h = 0.40 * plane + 0.18 * (rid - 0.5) + 0.10 * chamfer - 0.28 * crack - 0.12 * crack3
    h += 0.45 * (ridg - 0.5) + 0.16 * (chips - 0.5) + ctx.grain(0.006)
    h = (h - h.min()) / (h.max() - h.min())
    base = ramp(0.5 * ctx.fbm01(3, 4) + 0.5 * ctx.fbm01(18, 5), stops("#4a494b", "#6a696a", "#888689", "#a8a5a0"))
    tintc = (hash01(rid * 53.0) - 0.5)
    col = base * (1 + 0.28 * tintc)[..., None]
    col = col * np.array([1.03, 1.0, 0.97], f32)
    col = col * (0.62 + 0.8 * h)[..., None]
    wu = u + 0.05 * ctx.fbm(3, 3)
    streak = ctx.fbm01(18, 4, fy=2, uv=(wu, v))
    col = col * (0.68 + 0.42 * S(0.2, 0.8, streak))[..., None]
    w2 = ctx.worley(300)
    m = w2.rid
    spec = S(0.55, 0.30, w2.f1)
    quartz = spec * (m > 0.82)
    biot = spec * (m < 0.18)
    feld = spec * ((m > 0.45) & (m < 0.60))
    col = col * (1 + 0.30 * quartz)[..., None] * (1 - 0.40 * biot)[..., None]
    col = lerp(col, C("#b08a7a"), feld * 0.30)
    lich = S(0.70, 0.88, ctx.fbm01(9, 5)) * S(0.3, 0.7, ctx.fbm01(60, 3)) * S(0.35, 0.8, h)
    lc = ramp(ctx.fbm01(30, 2), [(0, C("#9ba04a")), (1, C("#c4a43c"))])
    col = lerp(col, lc * 0.9, lich * 0.5)
    col = col * (1 - 0.65 * crack - 0.4 * crack3)[..., None]
    ao = cavity_ao(h, radii=(2, 7, 22), weights=(0.3, 0.4, 0.3), gain=3.0)
    col = apply_ao(col, ao, 0.7)
    col = tint_speckle(ctx, col, 0.06)
    return dict(albedo=col, height=h, ao=ao, rough=0.80 + 0.1 * (1 - ao) - 0.12 * quartz, slope=0.50)


@recipe("red_clay", 4.0, "Canyon floor: dried cracked red clay plates (4 m tile).", "terrain", albedo=(0.06, 0.24))
def red_clay(ctx):
    n, s = ctx.n, ctx.s
    uw, vw = ctx.warp(0.03, 4, 3)
    w = ctx.worley(7, jitter=0.92, uv=(uw, vw))
    e = w.f2 - w.f1
    wmod = 0.05 + 0.05 * ctx.fbm01(8, 3)
    crack = 1 - S(0.0, wmod, e)
    plate = S(0.0, 0.5, e) ** 0.6
    curl = np.clip(1 - w.f1 / 0.8, 0, 1)
    uw2, vw2 = ctx.warp(0.02, 9, 3)
    w2 = ctx.worley(27, jitter=0.9, uv=(uw2, vw2))
    e2 = w2.f2 - w2.f1
    regions = S(0.35, 0.65, ctx.fbm01(5, 3))
    crack2 = (1 - S(0.0, 0.05, e2)) * regions * S(0.05, 0.3, e)
    h = 0.55 * plate * (0.75 + 0.25 * w.rid) + 0.15 * curl - 0.05 * crack2 + 0.05 * ctx.fbm01(40, 4)
    h = h - 0.4 * crack
    h += ctx.grain(0.008)
    h = (h - h.min()) / (h.max() - h.min())
    tone = 0.5 * w.rid + 0.5 * ctx.fbm01(10, 4)
    col = ramp(tone, stops("#82371f", "#a04d2b", "#b8613a", "#c9784a"))
    dust = S(0.5, 1.0, e) * 0.45 * (0.4 + 0.6 * ctx.fbm01(12, 4))
    col = lerp(col, C("#d9ac84"), dust)
    col = col * (0.85 + 0.30 * ctx.fbm01(50, 4))[..., None]
    col = lerp(col, C("#2a1209"), np.clip(crack * 0.95 + crack2 * 0.5, 0, 1))
    ao = cavity_ao(h, radii=(2, 7, 20), weights=(0.3, 0.4, 0.3), gain=3.0)
    col = apply_ao(col, ao, 0.7)
    col = tint_speckle(ctx, col, 0.07)
    return dict(albedo=col, height=h, ao=ao, rough=0.9 - 0.08 * plate, slope=0.35)


# ======================================================================================
# sands, snow
# ======================================================================================
@recipe("desert_sand", 4.0, "Desert dunes: wind ripples, mineral streaks (4 m tile).", "terrain", albedo=(0.28, 0.55))
def desert_sand(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    wob = ctx.fbm(3, 3) * 1.0 + 0.35 * ctx.fbm(9, 3) + 0.12 * ctx.fbm(24, 2)
    p = 22 * u + 5 * v + wob
    rip = np.sin(TAU * p) + 0.30 * np.sin(2 * TAU * p + 0.9)
    amp = 0.30 + 0.70 * S(0.25, 0.7, ctx.fbm01(2, 3))
    big = ctx.fbm01(2, 3)
    h = 0.5 + 0.28 * rip * amp + 0.25 * (big - 0.5)
    h += 0.04 * ctx.fbm(60, 3) + ctx.grain(0.010)
    h = (h - h.min()) / (h.max() - h.min())
    t = np.clip(0.55 * (rip * amp * 0.5 + 0.5) + 0.25 * ctx.fbm01(30, 3) + 0.2 * big, 0, 1)
    col = ramp(t, stops("#a8834f", "#c9a76f", "#dfc48c", "#ead6a4"))
    streak = S(0.68, 0.9, ctx.fbm01(70, 3, fy=9)) * S(0.55, 0.2, rip * amp * 0.5 + 0.5)
    col = lerp(col, C("#4a3a2c"), streak * 0.30)
    col = col * (0.94 + 0.12 * ctx.fbm01(100, 2))[..., None]
    ao = cavity_ao(h, radii=(2, 8, 24), weights=(0.3, 0.4, 0.3), gain=1.8)
    col = apply_ao(col, ao, 0.45)
    col = tint_speckle(ctx, col, 0.09)
    # wind-polished ripple crests are a little smoother than the troughs, damp / crusted patches vary
    rough = rough_field(ctx, 0.90, h, h_amp=0.06, macro_amp=0.05, macro_f=3, ao=ao, ao_amp=0.08, fine_amp=0.012)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.16)


@recipe("snow", 4.0, "Fresh snow: wind-sculpted drifts with sparkle (4 m tile).", "terrain", albedo=(0.65, 0.95))
def snow(ctx):
    n, s = ctx.n, ctx.s
    uw, vw = ctx.warp(0.12, 2, 3)
    drift = ctx.fbm01(3, 4, uv=(uw, vw))
    sast = ctx.fbm(9, 4, kind="ridged", fy=3, uv=(uw, vw))
    h = 0.55 * drift + 0.25 * sast + 0.08 * ctx.fbm01(40, 3) + ctx.grain(0.012)
    h = (h - h.min()) / (h.max() - h.min())
    ao = cavity_ao(h, radii=(3, 10, 30), weights=(0.3, 0.4, 0.3), gain=1.3)
    col = np.broadcast_to(np.array([0.86, 0.88, 0.92], f32), (n, n, 3)).copy()
    col = col * (0.97 + 0.04 * ctx.fbm01(20, 3))[..., None]
    shade = np.clip(1 - ao, 0, 1) * 2.0
    col = lerp(col, np.array([0.55, 0.66, 0.86], f32), np.clip(shade, 0, 1) * 0.7)
    sp = (ctx.rng.random((n, n), dtype=f32) > 0.9975).astype(f32)
    sp = blur(sp, 0.7 * s) * 6
    rough = np.clip(0.68 - 0.55 * np.clip(sp, 0, 1) + 0.05 * (1 - ao), 0.1, 1)
    col = col + 0.12 * np.clip(sp, 0, 1)[..., None]
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.10, ao_gain=1.3)


@recipe("beach_sand", 3.0, "Fine beach sand with shell fragments and damp patches (3 m tile).", "terrain", albedo=(0.30, 0.55))
def beach_sand(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    u, v = ctx.u, ctx.v
    wob = ctx.fbm(3, 3) * 0.8
    rip = np.sin(TAU * (13 * u + 2 * v + wob))
    macro = ctx.fbm01(2, 3)
    damp = S(0.55, 0.78, ctx.fbm01(3, 4))
    base = ramp(0.5 * macro + 0.3 * ctx.fbm01(16, 4) + 0.2 * ctx.fbm01(60, 3),
                stops("#ab9972", "#c0b089", "#cfc2a2", "#d8ccb0"))
    base = base * (1 - 0.30 * damp)[..., None]
    cv = ctx.canvas()
    cv.c = base
    cv.h[:] = 0.5 + 0.05 * rip + 0.12 * ctx.fbm(14, 4) + ctx.grain(0.012)
    shells = pal("#e8dccb", "#d9a89a", "#f2ece0", "#c9b9a6")
    for i in range(int(70 * s * s)):
        r = (5 + 12 * rng.random()) * s
        c = rpick(rng, shells)
        a = rng.random() * TAU
        cv.oval(rng.random() * n, rng.random() * n, r, r * (0.35 + 0.35 * rng.random()), a, col=c, h0=0.56, hdome=0.1,
                irr=0.25, rng=rng, shade=0.3)
    pebbles = pal("#7a746a", "#a39a8a", "#5c564f")
    for i in range(int(120 * s * s)):
        r = (2 + 4 * rng.random()) * s
        cv.oval(rng.random() * n, rng.random() * n, r, r * (0.7 + 0.3 * rng.random()), rng.random() * TAU,
                col=rpick(rng, pebbles), h0=0.55, hdome=0.1, irr=0.2, rng=rng, shade=0.3)
    for i in range(int(900 * s * s)):
        r = (0.8 + 1.4 * rng.random()) * s
        cv.oval(rng.random() * n, rng.random() * n, r, r, 0, col=C("#2e2a25"), h0=0.52, hdome=0.03)
    h = cv.h
    col = cv.c * (0.92 + 0.16 * ctx.fbm01(150, 2))[..., None]
    ao = cavity_ao(h, radii=(2, 6, 18), weights=(0.3, 0.4, 0.3), gain=1.6)
    col = apply_ao(col, ao, 0.4)
    col = tint_speckle(ctx, col, 0.10)
    return dict(albedo=col, height=h, ao=ao, rough=0.9 - 0.2 * damp, slope=0.10)


# ======================================================================================
# stones, mud, dirt
# ======================================================================================
@recipe("gravel", 2.0, "Loose gravel / crushed stone with dust fill (2 m tile).", "terrain", albedo=(0.12, 0.40))
def gravel(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    base = ramp(ctx.fbm01(60, 3), stops("#2e2922", "#463e33", "#5c5244"))
    cv = ctx.canvas(rough=0.9)
    cv.c = base
    cv.h[:] = 0.05
    pcol = pal("#8a8478", "#a39a88", "#6d675d", "#b8ae9a", "#5a554d", "#c4b8a0", "#7d6f5c", "#9a8f7e", "#d2cbbb",
               "#4d4a46", "#8f7f66", "#a58f78")
    passes = [(9500, 5, 9, 0.18, 0.30), (3800, 9, 15, 0.32, 0.50), (1250, 15, 25, 0.52, 0.80)]
    for count, r0, r1, z0, z1 in passes:
        N = int(count * s * s)
        xs, ys = rng.random(N) * n, rng.random(N) * n
        for i in range(N):
            r = (r0 + (r1 - r0) * rng.random()) * s
            c = rpick(rng, pcol) * f32(0.8 + 0.4 * rng.random())
            z = z0 + (z1 - z0) * rng.random()
            cv.oval(xs[i], ys[i], r, r * (0.6 + 0.4 * rng.random()), rng.random() * TAU, col=c, h0=z, hdome=0.22,
                    irr=0.22, rng=rng, shade=0.45, edge_dark=0.30, rough=0.75)
    h = blur(cv.h, 0.5 * s)
    col = cv.c
    col = col * (0.75 + 0.5 * ctx.fbm01(90, 3))[..., None]
    ao = cavity_ao(h, radii=(2, 6, 18), weights=(0.35, 0.4, 0.25), gain=3.2)
    col = apply_ao(col, ao, 0.8)
    col = tint_speckle(ctx, col, 0.12)
    return dict(albedo=col, height=h, ao=ao, rough=np.clip(0.9 - 0.15 * (h - 0.2), 0.4, 1), slope=0.50)


@recipe("mud", 3.0, "Churned wet mud with puddles (3 m tile).", "terrain", albedo=(0.03, 0.14))
def mud(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    uw, vw = ctx.warp(0.06, 3, 3)
    low = ctx.fbm01(3, 4, uv=(uw, vw))
    ridgeh = ctx.fbm(7, 5, kind="ridged", uv=(uw, vw))
    h = 0.45 * low + 0.35 * ridgeh + 0.12 * ctx.fbm01(30, 4) + ctx.grain(0.01)
    h = (h - h.min()) / (h.max() - h.min())
    pud = S(0.42, 0.30, blur(h, 3 * s))
    lvl = 0.30
    h2 = lerp(h, np.full_like(h, lvl) + 0.01 * ctx.fbm(5, 2), pud)
    cv = ctx.canvas()
    base = ramp(0.5 * ctx.fbm01(5, 4) + 0.5 * h2, stops("#2a1e15", "#42301f", "#5a4430", "#70563d"))
    base = base * (1 - 0.45 * pud)[..., None]
    cv.c = base
    cv.h = h2
    stones = pal("#6d655a", "#524b42", "#8a8070")
    for i in range(int(40 * s * s)):
        r = (4 + 9 * rng.random()) * s
        cv.oval(rng.random() * n, rng.random() * n, r, r * (0.6 + 0.4 * rng.random()), rng.random() * TAU,
                col=rpick(rng, stones), h0=0.62, hdome=0.14, irr=0.2, rng=rng, shade=0.3, rough=0.4)
    straw = pal("#8a7340", "#6d5a30")
    for i in range(int(90 * s * s)):
        L = (14 + 26 * rng.random()) * s
        cv.blade(rng.random() * n, rng.random() * n, rng.random() * TAU, L, 1.1 * s, 0.8 * s, L * 0.1 * rng.normal(),
                 rpick(rng, straw) * 0.8, rpick(rng, straw), 0.66, 0.68, rough=0.5)
    h = cv.h
    col = cv.c
    ao = cavity_ao(h, radii=(2, 7, 20), weights=(0.3, 0.4, 0.3), gain=2.4)
    col = apply_ao(col, ao, 0.7)
    col = tint_speckle(ctx, col, 0.05)
    rough = np.clip(0.55 - 0.15 * ctx.fbm01(10, 3), 0.2, 0.8)
    rough = lerp(rough, np.full_like(rough, 0.06), pud)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.25)


def _dirt_base(ctx, rng, stone_count=700, keep=None):
    n, s = ctx.n, ctx.s
    macro = ctx.fbm01(3, 4)
    base = ramp(0.35 * macro + 0.4 * ctx.fbm01(14, 4) + 0.25 * ctx.fbm01(60, 3),
                stops("#60482f", "#7a5e40", "#917455", "#a68c6c"))
    cv = ctx.canvas(rough=0.92)
    cv.c = base
    cv.h[:] = 0.35 + 0.18 * ctx.fbm(12, 4) + 0.06 * ctx.fbm(48, 3) + ctx.grain(0.01)
    stones = pal("#9a8f7c", "#b3a791", "#7d7364", "#c4b8a0", "#6b6256")
    for i in range(int(stone_count * s * s)):
        r = (2 + 6 * rng.random()) * s
        x, y = rng.random() * n, rng.random() * n
        if keep is not None and not keep(x / n):
            continue
        cv.oval(x, y, r, r * (0.6 + 0.4 * rng.random()), rng.random() * TAU,
                col=rpick(rng, stones) * f32(0.8 + 0.3 * rng.random()), h0=0.44, hdome=0.15, irr=0.22, rng=rng,
                shade=0.35, edge_dark=0.2, rough=0.8)
    return cv, macro


@recipe("dirt_road", 4.0, "Compacted dirt / gravel track surface (4 m tile).", "terrain", albedo=(0.10, 0.32))
def dirt_road(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    cv, macro = _dirt_base(ctx, rng, 900)
    wb = ctx.fbm(2, 3)
    cv.h += 0.03 * np.sin(TAU * (16 * ctx.v + 0.9 * wb)) * S(0.45, 0.7, ctx.fbm01(3, 3))
    h = blur(cv.h, 0.5 * s)
    col = cv.c * (0.88 + 0.24 * ctx.fbm01(40, 4))[..., None]
    dust = S(0.55, 0.85, ctx.fbm01(4, 4))
    col = lerp(col, C("#b9a384"), dust * 0.25)
    ao = cavity_ao(h, radii=(2, 7, 20), weights=(0.3, 0.4, 0.3), gain=2.4)
    col = apply_ao(col, ao, 0.6)
    col = tint_speckle(ctx, col, 0.08)
    return dict(albedo=col, height=h, ao=ao, rough=0.9 - 0.1 * dust, slope=0.25)


@recipe("dirt_road_rut", [4.0, 4.0], "Dirt road with two tyre ruts, centre hump with weeds, grassy shoulders (U across the road, 4 m wide).",
        "terrain", albedo=(0.06, 0.25),
        notes="Ruts at U=0.31 and 0.69 (1.5 m track width). Tiles along V.")
def dirt_road_rut(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    u, v = ctx.u, ctx.v
    cv, macro = _dirt_base(ctx, rng, 900, keep=lambda x: abs(x - 0.31) > 0.075 and abs(x - 0.69) > 0.075)
    wob = ctx.fbm(2, 3, fy=3) * 0.014 + ctx.fbm(7, 3) * 0.004
    ut = u + wob
    g1 = np.exp(-(((ut - 0.31) / 0.055) ** 2))
    g2 = np.exp(-(((ut - 0.69) / 0.055) ** 2))
    rut = np.maximum(g1, g2)
    rut_w = np.exp(-(((ut - 0.31) / 0.11) ** 2)) + np.exp(-(((ut - 0.69) / 0.11) ** 2))
    hump = np.exp(-(((ut - 0.5) / 0.055) ** 2))
    berm = (np.exp(-(((ut - 0.31) / 0.017 - 3.2) ** 2)) + np.exp(-(((ut - 0.69) / 0.017 + 3.2) ** 2))
            + np.exp(-(((ut - 0.31) / 0.017 + 3.2) ** 2)) + np.exp(-(((ut - 0.69) / 0.017 - 3.2) ** 2)))
    h = cv.h - 0.38 * rut + 0.12 * hump + 0.08 * berm
    pud = S(0.60, 0.75, ctx.fbm01(5, 4, fy=3)) * rut
    h = lerp(h, np.full_like(h, 0.12), pud)
    # tread blocks pressed into the rut
    tread = np.sin(TAU * (u * 180 + 0.4 * np.sin(TAU * v * 24))) * 0.5 + 0.5
    cv.h = h + 0.03 * tread * rut
    rut_c = np.clip(rut_w, 0, 1)
    cv.c = cv.c * (1 - 0.50 * rut_c)[..., None] * (1 - 0.12 * tread * rut_c)[..., None]
    cv.c = lerp(cv.c, cv.c * 0.5, pud)
    cv.r = (0.92 - 0.25 * rut_w).astype(f32)
    cv.r = lerp(cv.r, np.full_like(cv.r, 0.06), pud)
    gcols = [(0, C("#2e4a14")), (0.5, C("#4c6f1e")), (1, C("#8a9a3a"))]
    NG = int(5200 * s * s)
    for i in range(NG):
        r = rng.random()
        if r < 0.5:
            x = (0.5 + rng.normal(0, 0.022)) * n
        elif r < 0.75:
            x = (rng.normal(0, 0.035)) * n
        else:
            x = (1 + rng.normal(0, 0.035)) * n
        y = rng.random() * n
        L = (8 + 24 * rng.random()) * s
        c = ramp(np.array(rng.random(), f32), gcols)
        a = -math.pi / 2 + rng.normal(0, 0.9)
        cv.blade(x, y, a, L, 0.9 * s, 0.0, L * rng.normal(0, 0.25), c * 0.55, c * 1.1, 0.7, 0.78, rough=0.85)
    h = blur(cv.h, 0.5 * s)
    col = cv.c * (0.88 + 0.24 * ctx.fbm01(40, 4))[..., None]
    ao = cavity_ao(h, radii=(2, 7, 20), weights=(0.3, 0.4, 0.3), gain=2.4)
    col = apply_ao(col, ao, 0.6)
    col = tint_speckle(ctx, col, 0.08)
    return dict(albedo=col, height=h, ao=ao, rough=cv.r, slope=0.30)
