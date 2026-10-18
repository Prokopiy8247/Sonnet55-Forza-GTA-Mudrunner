"""Terrain texture recipes."""
from __future__ import annotations

import math

import numpy as np

from ..core import recipe
from ..maps import ramp, lerp, luminance, cavity_ao
from ..noise import f32, norm01, smoothstep, blur
from .common import (C, pal, stops, S, rpick, apply_ao, tint_speckle, sample_at, hash01,
                     leaf_colfn, leaf_prof, rough_field)

TAU = 2 * math.pi


# ======================================================================================
# grass family
# ======================================================================================
def _grass(ctx, base_stops, blade_stops, nblades, len_rng, hw_rng, clump_f=22, spread=0.5,
           bend=0.25, extra=None):
    """Three painted layers of blades: dense dark undergrowth, the main sward and a few bright
    long tips on top.  Blades radiate away from clump centres (worley), like grass seen from above."""
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    macro = ctx.fbm01(3, 4)
    meso = ctx.fbm01(13, 4)
    fine = ctx.fbm01(70, 3)
    t = 0.5 * macro + 0.3 * meso + 0.2 * fine
    cv = ctx.canvas(rough=0.9)
    cv.c[:] = ramp(t, base_stops) * 0.8
    cv.h[:] = 0.04 + 0.08 * meso
    w = ctx.worley(clump_f)
    layers = [  # count factor, length factor, width factor, z0, z1, dark, light, spread factor
        (1.15, 0.55, 0.75, 0.05, 0.30, 0.38, 0.80, 1.4),
        (1.00, 1.00, 1.00, 0.30, 0.80, 0.55, 1.12, 1.0),
        (0.22, 1.35, 0.70, 0.82, 0.98, 0.80, 1.30, 0.8),
    ]
    for cf, lf, wf, z0, z1, dark, light, sp in layers:
        N = int(nblades * cf * s * s)
        x = rng.random(N) * n
        y = rng.random(N) * n
        ix, iy = x.astype(int), y.astype(int)
        vx, vy = w.vx[iy, ix], w.vy[iy, ix]
        cl = w.rid[iy, ix]
        ang = np.arctan2(-vy, -vx) + rng.normal(0, spread * sp, N)
        L = (len_rng[0] + (len_rng[1] - len_rng[0]) * rng.random(N) ** 1.4) * lf * s
        hw = (hw_rng[0] + (hw_rng[1] - hw_rng[0]) * rng.random(N)) * wf * s
        bnd = L * rng.normal(0, bend, N)
        tcol = np.clip(0.45 + 0.9 * (cl - 0.5) + 0.7 * (macro[iy, ix] - 0.5) + rng.normal(0, 0.16, N), 0, 1)
        cols = ramp(tcol, blade_stops)
        z = z0 + (z1 - z0) * np.arange(N) / N
        for i in range(N):
            c = cols[i]
            cv.blade(x[i], y[i], ang[i], L[i], hw[i], 0.0, bnd[i], c * dark, c * light,
                     z[i], z[i] + 0.04, rough=0.85)
    if extra:
        extra(cv, rng)
    h = blur(cv.h, 1.0 * s)
    alb = cv.c
    ao = cavity_ao(h, radii=(1.5, 5, 14), weights=(0.4, 0.35, 0.25), gain=2.0)
    alb = apply_ao(alb, ao, 0.60)
    mott = ctx.fbm01(48, 4)
    alb = alb * (0.82 + 0.36 * mott)[..., None]
    alb = tint_speckle(ctx, alb, 0.06)
    return alb, h, ao, cv


@recipe("grass_lush", 4.0, "Landscape layer: lush green grass / meadow (4 m tile).", "terrain",
        albedo=(0.05, 0.22))
def grass_lush(ctx):
    base = stops("#1a3410", "#2a5016", "#3f6a1c", "#557f26")
    blades = [(0.0, C("#1f4010")), (0.35, C("#37631a")), (0.7, C("#538a26")), (1.0, C("#8aab3c"))]
    alb, h, ao, cv = _grass(ctx, base, blades, 20000, (9, 26), (0.6, 1.2), spread=0.85)
    # blade tips catch the light (smoother), the undergrowth is rough; patchy dry / damp areas
    rough = rough_field(ctx, 0.84 + 0.06 * (1 - ao), h, h_amp=0.07, macro_amp=0.07, macro_f=4, fine_amp=0.012)
    return dict(albedo=alb, height=h, ao=ao, rough=rough, slope=0.18)


@recipe("grass_dry", 4.0, "Landscape layer: dry / summer / savanna grass (4 m tile).", "terrain",
        albedo=(0.08, 0.30))
def grass_dry(ctx):
    base = stops("#4a3a1c", "#6a5428", "#8a7238", "#a58a4a")
    blades = [(0.0, C("#5a4622")), (0.3, C("#8a7035")), (0.65, C("#b49a52")), (0.85, C("#cdb870")),
              (1.0, C("#7d8a38"))]
    alb, h, ao, cv = _grass(ctx, base, blades, 22000, (10, 30), (0.5, 1.1), clump_f=18, spread=0.9, bend=0.34)
    rough = rough_field(ctx, 0.88 + 0.05 * (1 - ao), h, h_amp=0.06, macro_amp=0.06, macro_f=4, fine_amp=0.012)
    return dict(albedo=alb, height=h, ao=ao, rough=rough, slope=0.20)


# ======================================================================================
@recipe("forest_floor", 3.0, "Landscape layer: forest floor with needles, leaf litter, twigs, moss.",
        "terrain", albedo=(0.04, 0.16))
def forest_floor(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    macro = ctx.fbm01(3, 4)
    meso = ctx.fbm01(12, 4)
    fine = ctx.fbm01(60, 3)
    soil = ramp(0.5 * macro + 0.3 * meso + 0.2 * fine,
                stops("#1d1510", "#2b1e14", "#3a2a1b", "#4a3724"))
    cv = ctx.canvas(rough=0.9)
    cv.c[:] = soil
    cv.h[:] = 0.10 + 0.12 * meso
    # moss patches
    moss_m = S(0.58, 0.8, ctx.fbm01(5, 5)) * S(0.25, 0.6, ctx.fbm01(30, 3))
    moss_c = ramp(ctx.fbm01(40, 3), stops("#1f3a12", "#35591a", "#4f7a24"))
    cv.c[:] = lerp(cv.c, moss_c, moss_m * 0.9)
    cv.h[:] += moss_m * 0.07 * (0.5 + ctx.fbm01(90, 2))
    # pine needles (pairs)
    needle_cols = pal("#6b3f1c", "#8a5426", "#5a3418", "#a06a30", "#4a2c14")
    N = int(7000 * s * s)
    x, y = rng.random(N) * n, rng.random(N) * n
    flow = ctx.fbm(4, 2)
    ang0 = sample_at(flow, x, y) * 2.2 + rng.random(N) * TAU * 0.6
    z0 = 0.18
    for i in range(N):
        c = rpick(rng, needle_cols)
        L = (13 + 14 * rng.random()) * s
        for d in (0.0, rng.normal(0, 0.07)):
            cv.blade(x[i], y[i], ang0[i] + d, L, 0.75 * s, 0.4 * s, L * rng.normal(0, 0.05), c * 0.8, c * 1.1,
                     z0 + 0.0001 * i * 0 + 0.02 * rng.random(), z0 + 0.04, rough=0.8)
    # leaf litter
    leaf_cols = pal("#6e3b14", "#8a4d1a", "#a8651f", "#5b4a1c", "#7a6a2a", "#4a2c12", "#9b7a34", "#3f3a1c")
    NL = int(420 * s * s)
    x, y = rng.random(NL) * n, rng.random(NL) * n
    for i in range(NL):
        c = rpick(rng, leaf_cols) * f32(0.38 + 0.4 * rng.random())
        L = (34 + 46 * rng.random()) * s
        lobes = 0.35 if rng.random() < 0.5 else 0.0
        zz = 0.3 + 0.5 * i / NL
        cv.blade(x[i], y[i], rng.random() * TAU, L, L * (0.22 + 0.1 * rng.random()), 0.0,
                 L * rng.normal(0, 0.12), colfn=leaf_colfn(c, 0.22, 5, 0.25),
                 wprof=leaf_prof(0.8, lobes, 3.5), h0=zz, h1=zz + 0.05, hround=0.10, rough=0.7)
    # more needles on top
    N2 = int(1800 * s * s)
    x, y = rng.random(N2) * n, rng.random(N2) * n
    for i in range(N2):
        c = rpick(rng, needle_cols)
        L = (13 + 14 * rng.random()) * s
        a = rng.random() * TAU
        cv.blade(x[i], y[i], a, L, 0.75 * s, 0.4 * s, L * rng.normal(0, 0.05), c * 0.85, c * 1.15,
                 0.72, 0.76, rough=0.8)
    # twigs
    twig_cols = pal("#3a2a1c", "#4d3a28", "#5a4a38", "#2c2018")
    NT = int(90 * s * s)
    x, y = rng.random(NT) * n, rng.random(NT) * n
    for i in range(NT):
        c = rpick(rng, twig_cols)
        L = (70 + 140 * rng.random()) * s
        hw = (1.6 + 2.2 * rng.random()) * s
        a = rng.random() * TAU
        cv.blade(x[i], y[i], a, L, hw, hw * 0.7, L * rng.normal(0, 0.06), c * 0.9, c * 1.2,
                 0.6, 0.6, hround=0.14, rough=0.75)
        if rng.random() < 0.5:   # side branch
            f = 0.3 + 0.5 * rng.random()
            bx, by = x[i] + math.cos(a) * L * f, y[i] + math.sin(a) * L * f
            cv.blade(bx, by, a + rng.choice([-1, 1]) * (0.5 + 0.5 * rng.random()), L * 0.35, hw * 0.55, hw * 0.3, 0,
                     c * 0.9, c * 1.2, 0.62, 0.62, hround=0.1, rough=0.75)
    # a few stones
    stone_cols = pal("#5b5650", "#6e665a", "#463f38")
    for i in range(int(40 * s * s)):
        r = (6 + 12 * rng.random()) * s
        cv.oval(rng.random() * n, rng.random() * n, r, r * (0.6 + 0.4 * rng.random()), rng.random() * TAU,
                col=rpick(rng, stone_cols), h0=0.4, hdome=0.2, irr=0.2, rng=rng, shade=0.25, rough=0.8)
    h = blur(cv.h, 0.6 * s)
    alb = cv.c
    ao = cavity_ao(h, radii=(1.5, 5, 16), weights=(0.4, 0.35, 0.25), gain=2.4)
    alb = apply_ao(alb, ao, 0.7)
    mott = 0.7 * ctx.fbm01(36, 4) + 0.3 * ctx.fbm01(110, 3)
    alb = alb * (0.7 + 0.6 * mott)[..., None]
    alb = tint_speckle(ctx, alb, 0.07)
    return dict(albedo=alb, height=h, ao=ao, rough=0.85 + 0.1 * (1 - ao), slope=0.38)


# ======================================================================================
@recipe("farmland_soil", 6.0, "Ploughed field with furrows (6 m tile, furrows run along V).", "terrain",
        albedo=(0.04, 0.18))
def farmland_soil(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    u, v = ctx.u, ctx.v
    meander = ctx.fbm(2, 3, fy=3) * 0.012 + ctx.fbm(9, 3) * 0.004
    phase = 8 * (u + meander)
    ridge = 0.5 - 0.5 * np.cos(phase * TAU)                  # 0 furrow bottom, 1 crest
    ridge = ridge ** 0.8
    # crest breakup (some ridges collapsed)
    var = 0.75 + 0.25 * ctx.fbm01(5, 3, fy=2)
    clod1 = ctx.worley(34)
    clod2 = ctx.worley(75)
    c1 = np.clip(1 - clod1.f1 * 1.15, 0, 1) ** 1.2
    c2 = np.clip(1 - clod2.f1 * 1.2, 0, 1) ** 1.2
    rid = ctx.fbm01(18, 4)
    h = 0.45 * ridge * var + 0.20 * c1 * (0.4 + 0.6 * ridge) + 0.10 * c2 + 0.10 * rid
    crumbs = ctx.grain(0.012)
    h = h + crumbs
    h = (h - h.min()) / (h.max() - h.min())
    dry = S(0.2, 0.9, ridge * var + 0.25 * c1 + 0.2 * (ctx.fbm01(4, 3) - 0.5))
    stops_soil = [(0, C("#2a1c12")), (0.35, C("#4a3322")), (0.7, C("#6e5238")), (1, C("#8d7050"))]
    alb = ramp(dry * 0.75 + 0.25 * c1 * c1 + 0.15 * (rid - 0.5), stops_soil)
    # straw / residue and stones
    cv = ctx.canvas()
    cv.c = alb.copy()
    cv.h = h.copy()
    straw = pal("#b79d55", "#9c8441", "#c9b472")
    for i in range(int(260 * s * s)):
        c = rpick(rng, straw)
        L = (14 + 30 * rng.random()) * s
        cv.blade(rng.random() * n, rng.random() * n, rng.random() * TAU, L, 1.1 * s, 0.8 * s,
                 L * rng.normal(0, 0.1), c * 0.8, c, 0.78, 0.8, hround=0.05)
    stone = pal("#8d8579", "#a09584", "#6f685d")
    for i in range(int(150 * s * s)):
        r = (3 + 8 * rng.random()) * s
        cv.oval(rng.random() * n, rng.random() * n, r, r * (0.6 + 0.4 * rng.random()), rng.random() * TAU,
                col=rpick(rng, stone), h0=h.mean(), hdome=0.12, irr=0.2, rng=rng, shade=0.2)
    h = cv.h
    alb = cv.c
    ao = cavity_ao(h, radii=(2, 8, 24), weights=(0.3, 0.4, 0.3), gain=2.6)
    alb = apply_ao(alb, ao, 0.75)
    alb = tint_speckle(ctx, alb, 0.10)
    return dict(albedo=alb, height=h, ao=ao, rough=0.9 - 0.12 * (1 - dry), slope=0.40)


# ======================================================================================
@recipe("field_wheat", 4.0, "Crop field seen from above: golden wheat in rows with a tramline (4 m tile, rows along V).",
        "terrain", albedo=(0.12, 0.30))
def field_wheat(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    u, v = ctx.u, ctx.v
    rows = 22
    meander = ctx.fbm(3, 3, fy=2) * 0.006
    ph = rows * (u + meander)
    rowp = 0.5 + 0.5 * np.cos(ph * TAU)                       # 1 at row centre
    soil = ramp(ctx.fbm01(40, 3), stops("#2e2216", "#4a3824", "#5e4930"))
    macro = ctx.fbm01(3, 4)
    wind = ctx.fbm(4, 3)
    # tramline: attenuate crop at u ~ 0.5 over 2 rows
    tram = np.exp(-(((u - 0.5) * rows / 1.1) ** 2))
    cv = ctx.canvas(rough=0.85)
    cv.c[:] = soil
    cv.h[:] = 0.04 + 0.05 * ctx.fbm01(30, 3)
    pitch = n / rows
    NS = int(34000 * s * s)
    row_i = rng.integers(0, rows, NS)
    xc = (row_i + 0.5) * pitch
    xoff = rng.normal(0, 0.24 * pitch, NS)
    x = xc + xoff
    y = rng.random(NS) * n
    keep = rng.random(NS) > 0.75 * np.exp(-(((x / n - 0.5) * rows) / 1.1) ** 2)
    x, y = x[keep], y[keep]
    NS = len(x)
    wv = sample_at(wind, x, y)
    ang = math.pi / 2 + rng.normal(0, 0.55, NS) + wv * 0.6 + np.where(rng.random(NS) < 0.5, 0.0, math.pi)
    mac = sample_at(macro, x, y)
    cols = ramp(np.clip(mac * 0.6 + rng.random(NS) * 0.5, 0, 1),
                [(0, C("#a3802f")), (0.4, C("#c19a3e")), (0.75, C("#d9b95a")), (1, C("#e6cf84"))])
    z = 0.15 + 0.8 * np.arange(NS) / NS
    for i in range(NS):
        L = (11 + 14 * rng.random()) * s
        c = cols[i]
        cv.blade(x[i], y[i], ang[i], L, 1.2 * s, 0.5 * s, L * rng.normal(0, 0.12), c * 0.72, c * 1.1,
                 z[i], z[i] + 0.06, rough=0.8)
    # ears: small oriented ovals with darker awns
    NE = int(2600 * s * s)
    for i in range(NE):
        j = rng.integers(0, NS)
        c = cols[j] * f32(0.9)
        cv.oval(x[j] + rng.normal(0, 3) * s, y[j] + rng.normal(0, 3) * s, 7 * s, 2.3 * s, ang[j], col=c,
                h0=0.9, hdome=0.08, irr=0.1, rng=rng, shade=0.2)
    h = cv.h
    alb = cv.c
    ao = cavity_ao(h, radii=(1.5, 5, 14), weights=(0.35, 0.4, 0.25), gain=2.0)
    alb = apply_ao(alb, ao, 0.7)
    alb = tint_speckle(ctx, alb, 0.05)
    # ears / stalk tips smoother, soil between the rows and the tramline rougher
    rough = rough_field(ctx, 0.82, h, h_amp=0.10, macro_amp=0.06, macro_f=3, ao=ao, ao_amp=0.10, fine_amp=0.01)
    return dict(albedo=alb, height=h, ao=ao, rough=rough, slope=0.32)
