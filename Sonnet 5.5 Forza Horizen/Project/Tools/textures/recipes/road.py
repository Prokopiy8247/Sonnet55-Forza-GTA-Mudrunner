"""Road surface recipes: asphalt, concrete slabs, cobblestone, curb."""
from __future__ import annotations

import math

import numpy as np

from ..core import recipe
from ..maps import ramp, lerp, luminance, cavity_ao
from ..noise import f32, norm01, blur
from .common import (C, pal, stops, S, rpick, apply_ao, tint_speckle, sample_at, hash01, masonry, rrect_sd)

TAU = 2 * math.pi


def _aggregate(ctx, expose1, expose2, lo, hi, bit_lum, f1=300, f2=760):
    """Asphalt wearing course: bitumen matrix with exposed stone chips at two scales.
    Returns lum (linear grey), height-ish 'chip' coverage and tint arrays."""
    w1 = ctx.worley(f1)
    w2 = ctx.worley(f2)
    chip1 = S(0.62, 0.30, w1.f1)
    chip2 = S(0.55, 0.25, w2.f1)
    ex1 = (w1.rid > (1 - expose1)).astype(f32)
    ex2 = (w2.rid > (1 - expose2)).astype(f32)
    t1 = lo + (hi - lo) * hash01(w1.rid * 113.0) ** 1.4
    t2 = lo + (hi - lo) * hash01(w2.rid * 71.0) ** 1.4
    bit = bit_lum * (0.8 + 0.4 * ctx.fbm01(130, 3))
    lum = lerp(bit, t1, chip1 * ex1)
    lum = lerp(lum, t2, chip2 * ex2 * 0.8)
    tint = (hash01(w1.rid * 7.7) - 0.5) * 0.12
    return lum, chip1 * ex1, chip2 * ex2, w1, w2, tint


@recipe("asphalt_new", 3.0, "Fresh asphalt wearing course, fine aggregate, uniform dark (3 m tile). Hero road texture.",
        "road", size_mult=2, albedo=(0.035, 0.10))
def asphalt_new(ctx):
    n, s = ctx.n, ctx.s
    lum, c1, c2, w1, w2, tint = _aggregate(ctx, 0.55, 0.45, 0.045, 0.115, 0.030, 380, 900)
    macro = 0.90 + 0.20 * ctx.fbm01(3, 3)
    lane = 0.95 + 0.10 * ctx.fbm01(16, 3, fy=2)
    lum = lum * macro * lane * (1 + 0.10 * ctx.grain(1.0).clip(-3, 3) * 0.4)
    col = lum[..., None] * (1 + tint[..., None] * np.array([1.0, 0.0, -1.0], f32)) * np.array([1.0, 1.0, 1.02], f32)
    h = 0.40 + 0.34 * c1 * (0.5 + 0.5 * w1.rid) + 0.18 * c2 * (0.5 + 0.5 * w2.rid) + 0.06 * ctx.fbm(7, 3) + ctx.grain(0.02)
    ao = cavity_ao(h, radii=(1.5, 4, 12), weights=(0.45, 0.35, 0.2), gain=2.2)
    col = apply_ao(col, ao, 0.5)
    rough = np.clip(0.92 - 0.20 * (c1 + 0.5 * c2) + 0.04 * (ctx.fbm01(5, 3) - 0.5), 0.5, 1.0)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.40)


@recipe("asphalt_worn", 4.0, "Worn asphalt: exposed aggregate, crack network, alligator cracking, patches with sealant, oil stains (4 m tile). Hero road texture.",
        "road", size_mult=2, albedo=(0.05, 0.14))
def asphalt_worn(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    rng = ctx.rng_k()
    lum, c1, c2, w1, w2, tint = _aggregate(ctx, 0.85, 0.75, 0.07, 0.20, 0.050)
    macro = 0.80 + 0.40 * ctx.fbm01(3, 4)
    lane = 0.92 + 0.16 * ctx.fbm01(14, 3, fy=2)
    lum = lum * macro * lane
    # --- cracks
    uw, vw = ctx.warp(0.03, 5, 4)
    wk = ctx.worley(5, jitter=0.92, uv=(uw, vw))
    e = wk.f2 - wk.f1
    big = (1 - S(0.0, 0.010 + 0.012 * ctx.fbm01(9, 3), e)) * S(0.46, 0.62, ctx.fbm01(3, 3))
    wa = ctx.worley(30, jitter=0.9, uv=(uw, vw))
    ea = wa.f2 - wa.f1
    alli = (1 - S(0.0, 0.05, ea)) * S(0.60, 0.74, ctx.fbm01(4, 4))
    ridg = ctx.fbm(7, 5, kind="ridged", uv=(uw, vw))
    hair = S(0.955, 0.99, ridg) * S(0.35, 0.65, ctx.fbm01(2, 3))
    crack = np.clip(big + 0.7 * alli + 0.8 * hair, 0, 1)
    # --- repairs: narrow utility trenches, small pothole fills and one irregular blob instead of
    # three big rectangles (which read as a repeating motif).  Every patch gets wobbly, individually
    # warped edges, its own tone and a sealed rim; shapes are (kind, cx, cy, w, h, rotation, tone).
    patch = np.zeros_like(u)
    seal = np.zeros_like(u)
    ptone = np.zeros_like(u)
    for kind, cx, cy, pw, ph_, rot, tone in [
            ("box", 0.17, 0.33, 0.034, 0.30, 0.04, 0.80),      # long thin trench along the road
            ("box", 0.60, 0.67, 0.21, 0.030, -0.03, 0.70),     # cross trench
            ("box", 0.86, 0.15, 0.062, 0.052, 0.10, 0.62),     # small square repair
            ("box", 0.40, 0.90, 0.050, 0.040, -0.12, 0.74),    # small pothole fill
            ("blob", 0.58, 0.20, 0.042, 0.030, 0.30, 0.66)]:   # irregular rounded patch
        edge_n = 0.012 * ctx.fbm(9, 3) + 0.004 * ctx.fbm(34, 2)
        du, dv = u - cx, v - cy
        du = du - np.round(du)
        dv = dv - np.round(dv)
        cr, sr = math.cos(rot), math.sin(rot)
        ru, rv = du * cr + dv * sr, -du * sr + dv * cr
        if kind == "box":
            sd = np.maximum(np.abs(ru) - pw / 2, np.abs(rv) - ph_ / 2) + edge_n
        else:
            sd = np.sqrt((ru / pw) ** 2 + (rv / ph_) ** 2) * min(pw, ph_) - min(pw, ph_) + edge_n * 1.5
        m = S(0.0006, -0.0006, sd)
        patch = np.maximum(patch, m)
        ptone = np.maximum(ptone, m * tone)
        seal = np.maximum(seal, 1 - S(0.0, 0.0040, np.abs(sd)))
    # --- stains
    oil = S(0.66, 0.78, ctx.fbm01(5, 5)) * S(0.35, 0.8, ctx.fbm01(28, 3))
    # compose lum
    lum = lerp(lum, 0.040 + (0.40 + 0.5 * ptone) * (lum - 0.040), patch * 0.9)
    lum = lum * (1 - 0.55 * oil)
    lum = lum * (1 - 0.85 * crack) * (1 - 0.8 * seal) + 0.0
    col = lum[..., None] * (1 + tint[..., None] * np.array([1.0, 0.0, -1.0], f32)) * np.array([1.0, 1.0, 1.02], f32)
    tar = np.clip(big * 0.6 + seal, 0, 1)
    h = 0.40 + 0.30 * c1 * (0.5 + 0.5 * w1.rid) + 0.16 * c2 * (0.5 + 0.5 * w2.rid) + 0.08 * ctx.fbm(6, 4) + ctx.grain(0.02)
    h = h + 0.05 * patch - 0.45 * big - 0.25 * alli - 0.25 * hair - 0.30 * seal * 0.4
    ao = cavity_ao(h, radii=(1.5, 4, 12), weights=(0.45, 0.35, 0.2), gain=2.4)
    col = apply_ao(col, ao, 0.55)
    rough = np.clip(0.90 - 0.22 * (c1 + 0.5 * c2) - 0.55 * tar - 0.35 * oil - 0.10 * patch, 0.12, 1.0)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.45)


@recipe("concrete_road", 6.0, "Concrete road slabs with sealed expansion joints, 3 m slabs, 2x2 per tile (6 m).",
        "road", albedo=(0.18, 0.42))
def concrete_road(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    rng = ctx.rng_k()
    ju = ctx.fbm(24, 2) * 0.0015
    jv = ctx.fbm(24, 2) * 0.0015
    su = np.mod((u + jv) * 2, f32(1.0))
    sv = np.mod((v + ju) * 2, f32(1.0))
    slab = np.mod(np.floor((u + jv) * 2), 2) + 2 * np.mod(np.floor((v + ju) * 2), 2)
    du = np.minimum(su, 1 - su) * 0.5
    dv = np.minimum(sv, 1 - sv) * 0.5
    d = np.minimum(du, dv)
    seal = 1 - S(0.0, 0.0030, d)
    groove = 1 - S(0.0, 0.0065, d)
    rs = hash01(slab * 1.0 + 3.0)
    rs2 = hash01(slab * 1.0 + 11.0)
    tone = 0.27 + 0.065 * (rs - 0.5) * 2
    macro = 0.92 + 0.16 * ctx.fbm01(3, 4)
    mid = 0.90 + 0.20 * ctx.fbm01(14, 4)
    fine = 0.93 + 0.14 * ctx.fbm01(90, 3)
    pores = S(0.80, 0.93, ctx.fbm01(260, 2))
    wheel = np.exp(-(((su - 0.27) / 0.09) ** 2)) + np.exp(-(((su - 0.73) / 0.09) ** 2))
    broom = ctx.fbm01(150, 2, fy=5)
    stain = 1 - 0.22 * S(0.55, 0.9, ctx.fbm01(4, 5))
    lum = tone * stain * macro * mid * fine * (1 - 0.45 * pores) * (1 - 0.22 * np.clip(wheel, 0, 1)) * (0.96 + 0.08 * broom)
    oil = S(0.72, 0.82, ctx.fbm01(6, 4)) * np.clip(wheel, 0, 1) * S(0.4, 0.8, ctx.fbm01(36, 3))
    lum = lum * (1 - 0.5 * oil)
    ridg = ctx.fbm(5, 5, kind="ridged")
    hair = S(0.96, 0.99, ridg) * S(0.4, 0.7, ctx.fbm01(2, 3))
    lum = lum * (1 - 0.7 * hair)
    spall = S(0.35, 0.8, ctx.fbm01(70, 3)) * (1 - S(0.0, 0.010, d)) * (1 - seal)
    lum = lum * (1 - 0.35 * spall)
    lum = lum * (1 - 0.15 * groove) * (1 - 0.8 * seal)
    col = lum[..., None] * np.array([1.0, 0.985, 0.95], f32)
    tilt = ((su - 0.5) * (rs - 0.5) + (sv - 0.5) * (rs2 - 0.5)) * 0.06
    h = 0.6 + tilt + 0.05 * ctx.fbm(10, 3) + 0.03 * ctx.fbm(60, 3) - 0.04 * pores
    h = h - 0.40 * groove - 0.25 * seal - 0.12 * hair - 0.06 * spall + ctx.grain(0.006)
    ao = cavity_ao(h, radii=(1.5, 5, 14), weights=(0.4, 0.4, 0.2), gain=2.4)
    col = apply_ao(col, ao, 0.5)
    rough = np.clip(0.78 - 0.22 * np.clip(wheel, 0, 1) + 0.06 * pores - 0.35 * seal - 0.3 * oil, 0.2, 1.0)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.20)


@recipe("cobblestone", 2.0, "Granite cobblestone / sett paving with dirty joints (2 m tile).", "road", albedo=(0.08, 0.28))
def cobblestone(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    uw = u + ctx.fbm(4, 3) * 0.006
    vw = v + ctx.fbm(5, 3) * 0.004
    m = masonry(ctx, 16, (9, 11), 0.22, 0.12, "random", uv=(uw, vw))
    rad = 0.014
    sd = rrect_sd(m.lx, m.ly, m.wt, m.ht, rad) + ctx.fbm(60, 3) * 0.0016
    inside = -sd
    stone = S(0.0016, 0.0032, inside)
    dome = S(0.0, 0.026, inside) ** 0.7
    tilt = ((m.lx - 0.5) * (m.rnd - 0.5) * 0.5 + (m.ly - 0.5) * (m.rnd2 - 0.5) * 0.5)
    chips = ctx.fbm(110, 3)
    h = 0.12 + stone * (0.40 + 0.20 * m.rnd2 + 0.35 * dome + tilt * 0.35) + 0.03 * chips * stone + ctx.grain(0.008)
    grn = pal("#6f6e72", "#8a8680", "#77767b", "#9a8f86", "#6a6a6e", "#837d79", "#8d8a8c", "#5f5d61")
    cols = np.array(grn, f32)
    ci = np.minimum((m.rnd * len(grn)).astype(np.int32), len(grn) - 1)
    ci2 = np.minimum((m.rnd2 * len(grn)).astype(np.int32), len(grn) - 1)
    sc = cols[ci] * 0.6 + cols[ci2] * 0.4
    sc = sc * (0.78 + 0.5 * m.rnd2)[..., None]
    sc = sc * (0.85 + 0.30 * ctx.fbm01(60, 4))[..., None]
    spec = S(0.62, 0.8, ctx.fbm01(250, 2))
    sc = sc * (1 + 0.45 * spec - 0.2 * (1 - spec))[..., None]
    sc = sc * (0.72 + 0.35 * dome)[..., None]
    joint = ramp(ctx.fbm01(70, 3), stops("#25211b", "#3a332a", "#4a4236"))
    moss = S(0.62, 0.8, ctx.fbm01(8, 4)) * S(0.3, 0.7, ctx.fbm01(80, 3))
    joint = lerp(joint, C("#3e5a22"), moss * 0.5)
    col = lerp(joint, sc, stone)
    ao = cavity_ao(h, radii=(2, 6, 16), weights=(0.4, 0.4, 0.2), gain=3.2)
    col = apply_ao(col, ao, 0.8)
    col = tint_speckle(ctx, col, 0.06)
    rough = np.clip(0.55 + 0.30 * (1 - stone) + 0.10 * (1 - spec) - 0.1 * dome, 0.3, 1.0)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.45)


@recipe("curb_concrete", 2.0, "Concrete kerb with expansion joint, rubber scuffs and chipped edges (2 m tile, kerb runs along V).",
        "road", albedo=(0.18, 0.40))
def curb_concrete(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    rng = ctx.rng_k()
    macro = 0.90 + 0.20 * ctx.fbm01(3, 4)
    mid = 0.88 + 0.24 * ctx.fbm01(16, 4)
    fine = 0.92 + 0.16 * ctx.fbm01(100, 3)
    pores = S(0.78, 0.92, ctx.fbm01(280, 2))
    dirt = S(0.45, 0.85, ctx.fbm01(40, 3, fy=5)) * 0.25
    lum = 0.31 * macro * mid * fine * (1 - 0.45 * pores) * (1 - dirt)
    d = np.abs(v - 0.0)
    d = np.minimum(d, 1 - d)
    seal = 1 - S(0.0, 0.0035, d)
    groove = 1 - S(0.0, 0.008, d)
    lum = lum * (1 - 0.8 * seal) * (1 - 0.12 * groove)
    col = lum[..., None] * np.array([1.0, 0.985, 0.95], f32)
    cv = ctx.canvas()
    cv.c = col
    cv.h[:] = 0.6 + 0.05 * ctx.fbm(10, 3) + 0.03 * ctx.fbm(60, 3) - 0.04 * pores - 0.4 * groove
    cv.r[:] = 0.80 - 0.4 * seal
    # rubber scuffs (soft diagonal smears from tyre contact)
    sc = ctx.canvas(color=(0, 0, 0))
    one = np.array([1.0, 1.0, 1.0], f32)
    for i in range(int(26 * s * s)):
        L = (40 + 110 * rng.random()) * s
        hw = (4 + 9 * rng.random()) * s
        a = -math.pi / 2 + rng.normal(0, 0.45)
        sc.blade(rng.random() * n, rng.random() * n, a, L, hw, hw * 0.5, L * rng.normal(0, 0.06), one, one,
                 alpha_mul=0.35 + 0.4 * rng.random())
    scuff = blur(sc.c[..., 0], 2.2 * s) * (0.4 + 0.9 * ctx.fbm01(70, 3))
    cv.c = cv.c * (1 - 0.62 * np.clip(scuff, 0, 1))[..., None]
    cv.r = cv.r - 0.2 * np.clip(scuff, 0, 1)
    # chips along the upper edge (random notches)
    for i in range(int(40 * s * s)):
        r = (4 + 10 * rng.random()) * s
        cv.oval(rng.random() * n, rng.random() * n, r, r * 0.7, rng.random() * TAU, col=np.array([0.38, 0.37, 0.35], f32),
                h0=0.35, hdome=-0.15 + 0.2, irr=0.35, rng=rng, rough=0.9)
    h = cv.h
    col = cv.c
    ao = cavity_ao(h, radii=(1.5, 5, 14), weights=(0.4, 0.4, 0.2), gain=2.6)
    col = apply_ao(col, ao, 0.5)
    col = tint_speckle(ctx, col, 0.06)
    return dict(albedo=col, height=h, ao=ao, rough=cv.r, slope=0.20)
