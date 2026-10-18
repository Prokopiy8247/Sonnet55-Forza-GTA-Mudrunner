"""Building / prop surface recipes."""
from __future__ import annotations

import math

import numpy as np

from ..core import recipe
from ..maps import ramp, lerp, luminance, cavity_ao
from ..noise import f32, norm01, blur
from .common import (C, pal, stops, S, rpick, apply_ao, tint_speckle, sample_at, hash01, masonry, rrect_sd)

TAU = 2 * math.pi


# ======================================================================================
# plaster
# ======================================================================================
def _plaster(ctx, base_stops, chip, streak_amt, crack_amt, under_cols, rough0=0.86):
    n, s = ctx.n, ctx.s
    macro = ctx.fbm01(3, 4)
    mid = ctx.fbm01(14, 4)
    trowel = ctx.fbm(5, 4, kind="ridged")
    sand = ctx.fbm(190, 2)
    h = 0.55 + 0.12 * (trowel - 0.5) + 0.05 * ctx.fbm(24, 3) + 0.03 * sand + ctx.grain(0.008)
    ridg = ctx.fbm(6, 5, kind="ridged")
    hair = S(0.955, 0.99, ridg) * S(0.3, 0.65, ctx.fbm01(2, 3)) * crack_amt
    uw, vw = ctx.warp(0.05, 6, 4)
    field = ctx.fbm01(7, 5, uv=(uw, vw)) + 0.07 * ctx.fbm(50, 3)
    thr = 1 - chip
    loss = S(thr - 0.005, thr + 0.02, field) if chip > 0 else np.zeros_like(field)
    lip = S(thr - 0.05, thr, field) * (1 - S(thr, thr + 0.02, field)) if chip > 0 else np.zeros_like(field)
    col = ramp(0.5 * macro + 0.5 * mid, base_stops)
    col = col * (0.95 + 0.10 * ctx.fbm01(120, 3))[..., None]
    streak = S(0.35, 0.85, ctx.fbm01(24, 4, fy=3, uv=(ctx.u + 0.02 * ctx.fbm(5, 3), ctx.v)))
    col = col * (1 - streak_amt * streak)[..., None]
    stain = S(0.62, 0.88, ctx.fbm01(4, 4, fy=2)) * 0.18
    col = col * (1 - stain)[..., None]
    under = ramp(ctx.fbm01(24, 4), under_cols) * (0.8 + 0.4 * ctx.fbm01(70, 3))[..., None]
    col = lerp(col, under, loss)
    col = col * (1 - 0.6 * hair)[..., None]
    h = h - 0.28 * loss + 0.06 * lip - 0.15 * hair
    ao = cavity_ao(h, radii=(1.5, 5, 16), weights=(0.4, 0.4, 0.2), gain=2.6)
    col = apply_ao(col, ao, 0.6)
    col = tint_speckle(ctx, col, 0.05)
    rough = np.clip(rough0 + 0.06 * sand - 0.05 * loss, 0.5, 1)
    return col, h, ao, rough


@recipe("plaster_white", 2.0, "Whitewashed lime plaster / stucco wall with trowel marks, hairline cracks, stains (2 m tile).",
        "building", albedo=(0.45, 0.80))
def plaster_white(ctx):
    base = stops("#cfc9bc", "#dcd6c9", "#e6e1d5", "#efeadf")
    under = stops("#8a4a36", "#a3694e", "#b9ad98")
    col, h, ao, rough = _plaster(ctx, base, 0.07, 0.10, 1.0, under)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.16)


@recipe("plaster_ochre", 2.0, "Ochre / sun-faded Mediterranean plaster with chipped patches exposing brick (2 m tile).",
        "building", albedo=(0.22, 0.50))
def plaster_ochre(ctx):
    base = stops("#b98a45", "#c99a52", "#d6a95f", "#bd8f4c")
    under = stops("#8a4a36", "#a3694e", "#c4b6a0")
    col, h, ao, rough = _plaster(ctx, base, 0.14, 0.16, 1.0, under)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.22)


# ======================================================================================
# brick
# ======================================================================================
@recipe("brick_red", 1.35, "Red clay brick wall, running bond, 6 bricks x 18 courses per tile (225x75 mm bricks, 10 mm mortar).",
        "building", albedo=(0.10, 0.30))
def brick_red(ctx):
    n, s = ctx.n, ctx.s
    uw = ctx.u + ctx.fbm(5, 3) * 0.0012
    vw = ctx.v + ctx.fbm(5, 3) * 0.0012
    m = masonry(ctx, 18, (6, 6), 0.0, 0.0, "half", uv=(uw, vw))
    g = 0.0034
    sd = rrect_sd(m.lx, m.ly, m.wt, m.ht, 0.0045) + 0.0006 * ctx.fbm(70, 3)
    inside = -sd
    brick = S(g, g + 0.0016, inside)
    dome = S(g, g + 0.012, inside) ** 0.6
    bc = np.array(pal("#8c3f2b", "#9a4a33", "#7d3624", "#a55a3e", "#6e3224", "#b0694a", "#8a4a38", "#5a2a20"), f32)
    ci = np.minimum((m.rnd * len(bc)).astype(np.int32), len(bc) - 1)
    ci2 = np.minimum((m.rnd2 * len(bc)).astype(np.int32), len(bc) - 1)
    col = bc[ci] * 0.65 + bc[ci2] * 0.35
    col = col * (0.82 + 0.36 * m.rnd2)[..., None]
    col = col * (0.82 + 0.36 * ctx.fbm01(40, 4))[..., None]
    col = col * (0.92 + 0.16 * ctx.fbm01(160, 3))[..., None]
    col = col * (1 + 0.28 * (1 - dome))[..., None] * (1 - 0.12 * (m.ly - 0.5))[..., None]
    pits = S(0.82, 0.95, ctx.fbm01(220, 2))
    col = col * (1 - 0.35 * pits)[..., None]
    eff = S(0.7, 0.9, ctx.fbm01(10, 4, fy=3)) * S(0.6, 0.9, m.rnd2) * 0.5
    col = lerp(col, C("#cfc8bb"), eff * 0.5)
    soot = S(0.4, 0.85, ctx.fbm01(30, 4, fy=3)) * 0.30
    col = col * (1 - soot)[..., None]
    mortar = ramp(ctx.fbm01(150, 3), stops("#8d857a", "#a39b8d", "#b5ad9f"))
    mortar = mortar * (0.85 + 0.30 * ctx.fbm01(40, 3))[..., None]
    col = lerp(mortar, col, brick)
    h = 0.12 + brick * (0.55 + 0.30 * dome + 0.04 * ctx.fbm(60, 3) + 0.10 * (m.rnd - 0.5)) - 0.07 * pits * brick
    h = h + ctx.grain(0.010) + 0.02 * ctx.fbm(150, 2)
    ao = cavity_ao(h, radii=(1.5, 5, 14), weights=(0.4, 0.4, 0.2), gain=3.0)
    col = apply_ao(col, ao, 0.75)
    col = tint_speckle(ctx, col, 0.06)
    rough = np.clip(0.80 + 0.10 * (1 - brick) + 0.08 * pits, 0.5, 1)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.40)


# ======================================================================================
# roofs
# ======================================================================================
@recipe("roof_tile_terracotta", 2.0, "Terracotta barrel (Mediterranean) roof tiles, 9 columns x 5 courses per tile; courses run along U.",
        "building", albedo=(0.10, 0.32))
def roof_tile_terracotta(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    cols_n, rows_n = 9, 5
    uw = u + 0.0035 * ctx.fbm(6, 3)
    vw = v + 0.0025 * ctx.fbm(5, 3)
    wave = np.sin(TAU * cols_n * uw)
    cover = wave > 0
    vrow = vw * rows_n + 0.11 * np.where(cover, -wave, wave * 0.5)     # rounded lower lip follows the tile curvature
    fv = np.mod(vrow, f32(1.0))
    row = np.mod(np.floor(vrow), rows_n)              # wrap tile ids so the hash is periodic
    half = np.mod(np.floor(uw * cols_n * 2), 2 * cols_n)
    rnd = hash01(half * 1.0 + row * 17.3)
    rnd2 = hash01(half * 3.1 + row * 5.7)
    taper = 1 - 0.28 * fv
    prof = np.where(cover, np.abs(wave) ** 0.65, -np.abs(wave) ** 0.9 * 0.8)
    saw = 1 - 0.85 * fv - 0.20 * S(0.90, 1.0, fv)
    h = 0.34 + 0.34 * prof * taper + 0.30 * saw + 0.05 * (rnd - 0.5) + 0.03 * ctx.fbm(40, 3)
    h = h + 0.02 * ctx.fbm(150, 2) + ctx.grain(0.006)
    h = (h - h.min()) / (h.max() - h.min())
    tc = np.array(pal("#a6523a", "#b5654a", "#9a4a34", "#c47a58", "#8a4632", "#b9836a", "#a85a3a"), f32)
    ci = np.minimum((rnd * len(tc)).astype(np.int32), len(tc) - 1)
    ci2 = np.minimum((rnd2 * len(tc)).astype(np.int32), len(tc) - 1)
    col = tc[ci] * 0.6 + tc[ci2] * 0.4
    col = col * (0.78 + 0.42 * rnd2)[..., None]
    col = col * (0.80 + 0.40 * ctx.fbm01(22, 4))[..., None]
    col = col * (0.88 + 0.24 * ctx.fbm01(130, 3))[..., None]
    col = col * (1 + 0.18 * np.clip(prof, 0, 1) * (1 - fv) - 0.12 * np.clip(-prof, 0, 1))[..., None]
    groove = np.exp(-((wave / 0.10) ** 2))
    col = col * (1 - 0.55 * groove)[..., None]
    lime = S(0.70, 0.9, ctx.fbm01(7, 4)) * 0.4
    col = lerp(col, C("#bfa58c"), lime * S(0.3, 0.8, ctx.fbm01(60, 3)))
    soot = S(0.45, 0.9, ctx.fbm01(28, 4, fy=3)) * 0.35
    col = col * (1 - soot)[..., None]
    gap = S(0.86, 1.0, fv)
    col = col * (1 - 0.62 * gap)[..., None]
    shade = S(0.3, 0.9, -wave)
    lich = S(0.62, 0.85, ctx.fbm01(9, 5)) * S(0.45, 0.8, ctx.fbm01(90, 3)) * (0.4 + 0.6 * shade)
    lc = ramp(ctx.fbm01(40, 2), [(0, C("#4f6a3a")), (1, C("#8d9a6b"))])
    col = lerp(col, lc, lich * 0.55)
    ao = cavity_ao(h, radii=(2, 7, 20), weights=(0.3, 0.4, 0.3), gain=2.6)
    col = apply_ao(col, ao, 0.75)
    col = tint_speckle(ctx, col, 0.06)
    rough = np.clip(0.72 + 0.12 * (1 - ao) + 0.1 * lich, 0.4, 1)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.38)


@recipe("roof_slate", 1.8, "Slate roof tiles in half-lapped courses, 6 slates x 12 courses per tile; courses run along U.",
        "building", albedo=(0.04, 0.16))
def roof_slate(ctx):
    n, s = ctx.n, ctx.s
    uw = ctx.u + 0.0015 * ctx.fbm(6, 3)
    vw = ctx.v + 0.0010 * ctx.fbm(5, 3)
    rows = 12
    m = masonry(ctx, rows, (6, 6), 0.06, 0.0, "half", uv=(uw, vw))
    g = 0.0022
    sd = rrect_sd(m.lx, m.ly, m.wt, m.ht, 0.0020) + 0.0007 * ctx.fbm(50, 3)
    corner_chip = S(0.93, 0.99, hash01(m.sid * 1.0 + 0.1)) * S(0.8, 1.0, m.lx) * S(0.6, 1.0, m.ly)
    inside = -sd - 0.004 * corner_chip
    slate = S(g, g + 0.0012, inside)
    fv = m.ly
    lapshade = 1 - S(0.0, 0.16, fv)
    h = 0.10 + slate * (0.30 + 0.35 * fv - 0.10 * S(0.96, 1.0, fv) + 0.10 * (m.rnd - 0.5) + 0.05 * (m.lx - 0.5) * (m.rnd2 - 0.5))
    h = h + 0.015 * ctx.fbm(80, 3) + ctx.grain(0.006)
    sc = np.array(pal("#3a4048", "#444b54", "#2f353c", "#4d555e", "#383c42", "#3e4640", "#4a4450"), f32)
    ci = np.minimum((m.rnd * len(sc)).astype(np.int32), len(sc) - 1)
    ci2 = np.minimum((m.rnd2 * len(sc)).astype(np.int32), len(sc) - 1)
    col = sc[ci] * 0.7 + sc[ci2] * 0.3
    col = col * (0.75 + 0.5 * m.rnd2)[..., None]
    cleave = ctx.fbm01(40, 4, fy=3)
    col = col * (0.82 + 0.36 * cleave)[..., None]
    col = col * (0.90 + 0.20 * ctx.fbm01(160, 3))[..., None]
    col = col * (1 + 0.30 * S(0.9, 1.0, fv) - 0.35 * lapshade)[..., None]
    lich = S(0.62, 0.85, ctx.fbm01(8, 5)) * S(0.5, 0.8, ctx.fbm01(100, 3))
    lc = ramp(ctx.fbm01(40, 2), [(0, C("#6a7a48")), (1, C("#a9ae7a"))])
    col = lerp(col, lc, lich * 0.45)
    col = col * (0.15 + 0.85 * slate)[..., None]
    ao = cavity_ao(h, radii=(1.5, 5, 14), weights=(0.4, 0.4, 0.2), gain=2.6)
    col = apply_ao(col, ao, 0.7)
    col = tint_speckle(ctx, col, 0.05)
    rough = np.clip(0.55 + 0.25 * (1 - slate) + 0.2 * lich + 0.1 * cleave, 0.3, 1)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.38)


# ======================================================================================
# wood
# ======================================================================================
def _planks(ctx, nplank, boards, width_var, len_var, pal_stops, weather, gloss, knots_n, rings_k, grain_amp):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    rng = ctx.rng_k()
    m = masonry(ctx, nplank, (boards, boards), len_var, width_var, "random", uv=(v, u))
    across = m.ly
    along = m.lx
    d_edge = np.minimum(across, 1 - across) * m.ht
    d_end = np.minimum(along, 1 - along) * m.wt
    gap_w = 0.0012 if gloss else 0.0020
    gap = 1 - S(gap_w * 0.4, gap_w * 1.4, np.minimum(d_edge, d_end))
    bevel = S(gap_w, gap_w + 0.0035, np.minimum(d_edge, d_end))
    warp = ctx.fbm(34, 3, fy=3)
    ph = across * rings_k + 1.3 * warp + m.rnd * 11
    # knots: periodic elliptical distance, rings bend around them
    kd = np.full(u.shape, 9.0, f32)
    for k in range(knots_n):
        ku, kv = rng.random(), rng.random()
        ru, rv = 0.012 + 0.01 * rng.random(), 0.020 + 0.02 * rng.random()
        du = np.abs(u - ku)
        du = np.minimum(du, 1 - du) / ru
        dv = np.abs(v - kv)
        dv = np.minimum(dv, 1 - dv) / rv
        d = np.sqrt(du * du + dv * dv)
        kd = np.minimum(kd, d)
        ph = ph + 2.2 * np.exp(-d * d * 0.5) * np.sign(du * 0 + 1)
    rings = 0.5 + 0.5 * np.sin(TAU * ph)
    rings = rings ** 1.5
    fibre = ctx.fbm01(260, 2, fy=7)
    knot = np.exp(-(kd * 1.2) ** 2)
    tone = np.clip(0.55 * rings * grain_amp + 0.35 * fibre + 0.25 * ctx.fbm01(8, 3), 0, 1)
    col = ramp(tone, pal_stops)
    col = col * (0.80 + 0.40 * m.rnd2)[..., None]
    col = col * (1 - 0.55 * knot)[..., None]
    ridg = ctx.fbm(48, 4, kind="ridged", fy=3)
    crack = S(0.93, 0.985, ridg) * S(0.4, 0.7, ctx.fbm01(5, 3)) * weather
    col = col * (1 - 0.7 * crack)[..., None]
    col = col * (1 - 0.65 * gap)[..., None]
    h = 0.55 + 0.05 * rings * grain_amp + 0.03 * fibre + 0.10 * bevel - 0.55 * gap - 0.35 * crack - 0.06 * knot
    h = h + ctx.grain(0.004) + 0.03 * (m.rnd - 0.5)
    return m, col, h, rings, gap, crack, knot, d_end, across


@recipe("wood_planks_weathered", 2.0, "Weathered silver-grey timber planks with cracks, knots and nails (2 m tile, planks run along V; rotate 90 deg for horizontal).",
        "building", albedo=(0.08, 0.28))
def wood_planks_weathered(ctx):
    n, s = ctx.n, ctx.s
    st = stops("#4e4439", "#6f6558", "#8a7e6e", "#a1968a", "#b8aea0")
    m, col, h, rings, gap, crack, knot, d_end, across = _planks(ctx, 8, 2, 0.20, 0.35, st, 1.0, False, 7, 7, 1.0)
    nail = np.zeros_like(h)
    for ya in (0.27, 0.73):
        dd = np.sqrt((d_end - 0.014) ** 2 + ((across - ya) * m.ht) ** 2)
        nail = np.maximum(nail, S(0.0030, 0.0014, dd))
    col = lerp(col, np.array([0.03, 0.028, 0.026], f32), nail * 0.9)
    h = h + 0.08 * nail
    ao = cavity_ao(h, radii=(1.5, 5, 14), weights=(0.4, 0.4, 0.2), gain=2.8)
    col = apply_ao(col, ao, 0.7)
    col = tint_speckle(ctx, col, 0.06)
    rough = np.clip(0.84 + 0.08 * (1 - rings) - 0.4 * nail, 0.3, 1)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.28)


@recipe("wood_dark", 2.0, "Dark stained / varnished hardwood planks (2 m tile, planks run along V).", "building", albedo=(0.02, 0.10))
def wood_dark(ctx):
    # lifted from the first version (mean linear luminance 0.024) so the planks do not crush to black in shadow
    st = stops("#2b180d", "#3e2415", "#53331f", "#684229", "#7f5435")
    m, col, h, rings, gap, crack, knot, d_end, across = _planks(ctx, 14, 2, 0.12, 0.30, st, 0.15, True, 3, 9, 1.0)
    ao = cavity_ao(h, radii=(1.5, 5, 14), weights=(0.4, 0.4, 0.2), gain=2.4)
    col = apply_ao(col, ao, 0.6)
    col = tint_speckle(ctx, col, 0.04)
    rough = np.clip(0.42 + 0.10 * (1 - rings) + 0.4 * gap + 0.1 * ctx.fbm01(30, 3), 0.25, 1)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.14)


# ======================================================================================
# stone wall
# ======================================================================================
@recipe("stone_wall", 2.0, "Dry/lime-mortar rubble stone masonry, irregular coursed blocks (2 m tile).", "building", albedo=(0.12, 0.34))
def stone_wall(ctx):
    n, s = ctx.n, ctx.s
    uw = ctx.u + ctx.fbm(5, 3) * 0.004
    vw = ctx.v + ctx.fbm(4, 3) * 0.004
    m = masonry(ctx, 7, (3, 5), 0.38, 0.38, "random", uv=(uw, vw))
    g = 0.0075
    sd = rrect_sd(m.lx, m.ly, m.wt, m.ht, 0.022) + ctx.fbm(26, 4) * 0.0045
    inside = -sd
    stone = S(g, g + 0.004, inside)
    dome = S(g, g + 0.03, inside) ** 0.6
    chis = ctx.fbm(14, 5, kind="ridged")
    h = 0.10 + stone * (0.45 + 0.20 * dome + 0.12 * (chis - 0.5) + 0.12 * (m.rnd - 0.5)) + 0.03 * ctx.fbm(70, 3) + ctx.grain(0.008)
    sc = np.array(pal("#a09580", "#b3a68d", "#8e8672", "#9c8b72", "#7f7869", "#b8ab94", "#8a7d68"), f32)
    ci = np.minimum((m.rnd * len(sc)).astype(np.int32), len(sc) - 1)
    ci2 = np.minimum((m.rnd2 * len(sc)).astype(np.int32), len(sc) - 1)
    col = sc[ci] * 0.6 + sc[ci2] * 0.4
    col = col * (0.8 + 0.4 * m.rnd2)[..., None]
    col = col * (0.82 + 0.36 * ctx.fbm01(18, 4))[..., None] * (0.9 + 0.2 * ctx.fbm01(110, 3))[..., None]
    col = col * (0.75 + 0.35 * dome)[..., None]
    streak = S(0.4, 0.9, ctx.fbm01(30, 4, fy=3)) * 0.25
    col = col * (1 - streak)[..., None]
    mortar = ramp(ctx.fbm01(90, 3), stops("#6e6657", "#8a8170", "#9c9380"))
    moss = S(0.62, 0.8, ctx.fbm01(8, 4)) * S(0.3, 0.7, ctx.fbm01(70, 3))
    mortar = lerp(mortar, C("#4c6428"), moss * 0.5)
    lich = S(0.7, 0.88, ctx.fbm01(12, 5)) * S(0.45, 0.8, ctx.fbm01(80, 3)) * stone
    col = lerp(col, C("#a3a860"), lich * 0.35)
    col = lerp(mortar, col, stone)
    ao = cavity_ao(h, radii=(2, 7, 20), weights=(0.3, 0.4, 0.3), gain=3.0)
    col = apply_ao(col, ao, 0.8)
    col = tint_speckle(ctx, col, 0.06)
    rough = np.clip(0.80 + 0.10 * (1 - stone), 0.5, 1)
    return dict(albedo=col, height=h, ao=ao, rough=rough, slope=0.45)


# ======================================================================================
# metals
# ======================================================================================
def _rust_blotches(ctx, amount, bias=None):
    """rust coverage mask [0,1] and pits."""
    uw, vw = ctx.warp(0.05, 3, 3)
    field = 0.55 * ctx.fbm01(5, 5, uv=(uw, vw)) + 0.45 * ctx.fbm01(22, 4)
    if bias is not None:
        field = field + bias
    thr = 1 - amount
    field = field + 0.10 * ctx.fbm01(80, 4)
    mask = S(thr - 0.02, thr + 0.06, field)
    return mask


@recipe("metal_corrugated", [1.0, 1.0], "Weathered galvanised corrugated sheet with rust, dents and screws (1 m tile, ridges run along V).",
        "building", albedo=(0.12, 0.50),
        notes="13 corrugations per metre (77 mm pitch). Metallic = 1 on bare zinc, 0 on rust.")
def metal_corrugated(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    rng = ctx.rng_k()
    ridges = 13
    wave = np.sin(TAU * ridges * (u + 0.0006 * ctx.fbm(8, 3)))
    dents = ctx.fbm(3, 4) * 0.5 + ctx.fbm(9, 3) * 0.25
    h = 0.5 + 0.30 * wave + 0.10 * dents + 0.01 * ctx.fbm(80, 3)
    rust_m = _rust_blotches(ctx, 0.28, bias=0.12 * (1 - 0.5 * (wave + 1)) + 0.15 * ctx.fbm(40, 2, fy=3))
    base = ramp(0.5 * ctx.fbm01(4, 4) + 0.5 * ctx.fbm01(60, 3, fy=5), stops("#7a7e80", "#92979a", "#a9aeb0", "#b9bdbe"))
    spang = ctx.worley(36)
    base = base * (0.92 + 0.16 * spang.rid)[..., None]
    bloom = S(0.55, 0.85, ctx.fbm01(9, 4)) * 0.22
    base = lerp(base, C("#c4c3be"), bloom)
    rust_c = ramp(ctx.fbm01(50, 4), stops("#34170c", "#5a2a12", "#7e3c18", "#965326"))
    col = lerp(base, rust_c, rust_m * 0.92)
    dirt = S(0.4, 0.9, ctx.fbm01(30, 4, fy=3)) * 0.28
    col = col * (1 - dirt)[..., None]
    pits = S(0.8, 0.95, ctx.fbm01(110, 3)) * rust_m
    h = h - 0.06 * rust_m - 0.05 * pits
    # screws on ridge crests
    cv = ctx.canvas()
    cv.c = col
    cv.h = h
    rustcol = np.array([0.04, 0.035, 0.03], f32)
    for rr in range(4):
        y = (rr + 0.5) / 4 * n
        for k in range(0, ridges, 2):
            x = (k + 0.25 + 0.0) / ridges * n
            r = 6 * s
            cv.oval(x, y, r, r, 0, col=np.array([0.30, 0.31, 0.32], f32), h0=0.9, hdome=0.12, rough=0.35, metal=0.9, edge_dark=0.3)
    h = cv.h
    col = cv.c
    ao = cavity_ao(h, radii=(2, 7, 20), weights=(0.3, 0.4, 0.3), gain=2.4)
    col = apply_ao(col, ao, 0.7)
    col = tint_speckle(ctx, col, 0.05)
    metal = np.clip(0.95 - 0.95 * rust_m - 0.3 * dirt, 0, 1)
    rough = np.clip(0.38 + 0.50 * rust_m + 0.25 * dirt + 0.1 * (1 - spang.rid) * (1 - rust_m), 0.25, 1)
    return dict(albedo=col, height=h, ao=ao, rough=rough, metal=metal, slope=0.30)


@recipe("metal_painted_galvanized", [1.0, 1.0], "Painted galvanised steel panels with standing seams, screws, scratches exposing zinc spangle and rust (1 m tile).",
        "building", albedo=(0.06, 0.30),
        notes="Metallic = 0 on paint, 1 where paint is scratched off.")
def metal_painted_galvanized(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    rng = ctx.rng_k()
    seam_d = np.minimum(np.mod(u * 2, 1), 1 - np.mod(u * 2, 1)) / 2
    seam = np.exp(-((seam_d / 0.006) ** 2))
    seam2 = np.exp(-(((seam_d - 0.012) / 0.003) ** 2))
    h = 0.45 + 0.35 * seam + 0.05 * ctx.fbm(3, 3) + 0.01 * ctx.fbm(70, 3)
    paint = ramp(0.5 * ctx.fbm01(3, 4) + 0.5 * ctx.fbm01(20, 4), stops("#41636a", "#4a6f77", "#547c85", "#3c5c63"))
    paint = paint * (0.92 + 0.16 * ctx.fbm01(150, 2))[..., None]
    fade = S(0.5, 0.9, ctx.fbm01(5, 4)) * 0.25
    paint = lerp(paint, C("#7d8c8c"), fade)
    # scratches / chips
    scr = np.zeros_like(h)
    cv = ctx.canvas(color=(0, 0, 0))
    one = np.array([1.0, 1.0, 1.0], f32)
    for i in range(int(70 * s * s)):
        L = (30 + 160 * rng.random()) * s
        a = -math.pi / 2 + rng.normal(0, 0.25) if rng.random() < 0.7 else rng.random() * TAU
        cv.blade(rng.random() * n, rng.random() * n, a, L, 0.9 * s, 0.4 * s, L * rng.normal(0, 0.04), one, one)
    for i in range(int(35 * s * s)):
        r = (3 + 8 * rng.random()) * s
        cv.oval(rng.random() * n, rng.random() * n, r, r * (0.5 + 0.5 * rng.random()), rng.random() * TAU, col=one, irr=0.4, rng=rng)
    scr = np.clip(cv.c[..., 0], 0, 1)
    edge = seam * 0.5 + S(0.7, 0.95, ctx.fbm01(7, 4)) * S(0.4, 0.8, ctx.fbm01(50, 3))
    worn = np.clip(scr + S(0.8, 0.95, edge + 0.4 * ctx.fbm01(25, 3)) * 0.8, 0, 1)
    sp = ctx.worley(34)
    zinc = ramp(sp.rid, stops("#8e9294", "#a8acae", "#b9bdbf", "#9a9ea0"))
    zinc = zinc * (0.9 + 0.2 * (1 - sp.f1))[..., None]
    rust = S(0.55, 0.9, ctx.fbm01(14, 4)) * worn
    rust_c = ramp(ctx.fbm01(60, 3), stops("#5a2812", "#8a4018", "#b4602a"))
    col = lerp(paint, zinc, worn)
    col = lerp(col, rust_c, rust * 0.8)
    # screws on seams
    cv2 = ctx.canvas()
    cv2.c = col
    cv2.h = h
    for rr in range(5):
        y = (rr + 0.5) / 5 * n
        for x in (0.0, 0.5, 1.0):
            r = 5.5 * s
            cv2.oval(x * n + 0.035 * n, y, r, r, 0, col=np.array([0.22, 0.23, 0.24], f32), h0=0.9, hdome=0.1,
                     rough=0.35, metal=0.9, edge_dark=0.3)
    h = cv2.h
    col = cv2.c
    h = h - 0.05 * worn
    ao = cavity_ao(h, radii=(2, 7, 18), weights=(0.3, 0.4, 0.3), gain=2.4)
    col = apply_ao(col, ao, 0.6)
    col = tint_speckle(ctx, col, 0.04)
    metal = np.clip(worn * (1 - 0.8 * rust) + (cv2.m * (1 - worn)), 0, 1)
    rough = np.clip(0.38 + 0.20 * ctx.fbm01(30, 3) * (1 - worn) + 0.35 * worn * 0.4 + 0.5 * rust, 0.2, 1)
    return dict(albedo=col, height=h, ao=ao, rough=rough, metal=metal, slope=0.22)


# ======================================================================================
# concrete
# ======================================================================================
@recipe("concrete_rough", 2.0, "Board-formed rough concrete wall with tie holes, air voids, efflorescence and rust drips (2 m tile).",
        "building", albedo=(0.16, 0.42))
def concrete_rough(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    rng = ctx.rng_k()
    boards = 14
    bi = np.floor(v * boards)
    bf = np.mod(v * boards, f32(1.0))
    rb = hash01(bi * 1.0 + 5.0)
    # each board has a small horizontal offset of its grain
    gr = ctx.fbm(8, 3, fy=70)
    seam = np.exp(-((np.minimum(bf, 1 - bf) / 0.035) ** 2))
    tone = 0.30 * (0.88 + 0.24 * rb) * (0.90 + 0.20 * ctx.fbm01(3, 4)) * (0.88 + 0.24 * ctx.fbm01(18, 4))
    fine = 0.92 + 0.16 * ctx.fbm01(100, 3)
    voids = ctx.worley(110)
    bug = S(0.30, 0.12, voids.f1) * (voids.rid > 0.82)
    bug2 = ctx.worley(260)
    bugs = np.clip(bug + S(0.26, 0.10, bug2.f1) * (bug2.rid > 0.9), 0, 1)
    lum = tone * fine * (1 - 0.55 * bugs) * (1 - 0.18 * seam) * (0.94 + 0.12 * gr)
    eff = S(0.60, 0.9, ctx.fbm01(7, 4, fy=2)) * 0.25 * S(0.3, 0.8, ctx.fbm01(40, 3))
    col = lum[..., None] * np.array([1.0, 0.985, 0.96], f32)
    col = lerp(col, C("#d8d6cf"), eff)
    # form-tie holes grid 4 x 4 at 0.5 m
    cv = ctx.canvas()
    cv.c = col
    cv.h[:] = 0.55 + 0.06 * gr + 0.04 * ctx.fbm(14, 3) + 0.02 * ctx.fbm(70, 3) - 0.08 * bugs - 0.10 * seam
    dark = np.array([0.04, 0.04, 0.04], f32)
    for iy in range(4):
        for ix in range(4):
            x = (ix + 0.5) / 4 * n
            y = (iy + 0.25) / 4 * n
            r = 13 * s
            cv.oval(x, y, r, r, 0, col=np.array([0.17, 0.165, 0.16], f32), h0=0.1, hdome=0.2, rough=0.9, hpow=0.5)
            cv.oval(x, y, r * 0.5, r * 0.5, 0, col=dark, h0=0.05, hdome=0.0)
            # rust drip below
            L = (60 + 150 * rng.random()) * s
            cv.blade(x, y + r * 0.6, math.pi / 2, L, 3.5 * s, 1.5 * s, 0, np.array([0.12, 0.05, 0.025], f32),
                     np.array([0.30, 0.14, 0.07], f32), None, None, alpha_mul=0.45)
    h = cv.h
    col = cv.c
    ao = cavity_ao(h, radii=(1.5, 5, 16), weights=(0.4, 0.4, 0.2), gain=3.0)
    col = apply_ao(col, ao, 0.7)
    col = tint_speckle(ctx, col, 0.07)
    return dict(albedo=col, height=h, ao=ao, rough=np.clip(0.86 + 0.08 * bugs, 0, 1), slope=0.26)


# ======================================================================================
# overlays
# ======================================================================================
@recipe("glass_dirt_overlay", 1.0, "Window dirt overlay (RGBA): dust haze, rain-run streaks, dried water spots (1 m tile). Alpha = dirt opacity.",
        "building", albedo=(0.04, 0.30),
        notes="Alpha-blend over glass. ORM roughness is high where dirt is opaque.")
def glass_dirt_overlay(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    one = np.array([1.0, 1.0, 1.0], f32)
    haze = ctx.fbm01(3, 5)
    fine = ctx.fbm01(70, 3)
    dust = 0.24 + 0.26 * haze + 0.12 * S(0.5, 0.95, fine)
    # rain runs: thin clean channels with dirty rims, ending in a bead
    clean = ctx.canvas(color=(0, 0, 0))
    rim = ctx.canvas(color=(0, 0, 0))
    for i in range(int(70 * s * s)):
        x = rng.random() * n
        y = rng.random() * n
        L = (80 + 420 * rng.random()) * s
        wd = (2.0 + 4.5 * rng.random()) * s
        bend = L * rng.normal(0, 0.015)
        clean.blade(x, y, math.pi / 2, L, wd, wd * 0.8, bend, one, one, alpha_mul=0.9)
        clean.oval(x + bend, y + L, wd * 1.9, wd * 2.4, 0, col=one, h0=None, irr=0.0)
        for sd in (-1, 1):
            rim.blade(x + sd * wd * 1.6, y, math.pi / 2, L, wd * 0.7, wd * 0.5, bend, one, one, alpha_mul=0.55,
                      wprof=lambda t: np.clip(1.4 - 1.4 * np.clip(t, 0, 1) ** 2, 0, 1))
    cl = np.clip(blur(clean.c[..., 0], 0.8 * s), 0, 1)
    rm = np.clip(blur(rim.c[..., 0], 1.0 * s), 0, 1)
    # dried water spots: bright rim ring + clear centre
    spot = ctx.canvas(color=(0, 0, 0))
    hgt = ctx.canvas(color=(0, 0, 0), h=0.5)
    for i in range(int(650 * s * s)):
        x, y = rng.random() * n, rng.random() * n
        r = (2 + 9 * rng.random() ** 2.2) * s
        spot.oval(x, y, r, r, 0, col=one * 0.9, h0=None, irr=0.12, rng=rng)
        hgt.oval(x, y, r, r, 0, col=one, h0=0.5, hdome=0.30, hpow=0.35, irr=0.12, rng=rng)
    sp = np.clip(spot.c[..., 0], 0, 1)
    spb = blur(sp, 0.7 * s)
    ringm = np.clip(np.abs(sp - blur(sp, 2.2 * s)) * 4.5, 0, 1)
    inner = np.clip(blur(sp, 2.0 * s) - 0.5, 0, 1)
    alpha = dust * (1 - 0.82 * cl) + 0.30 * rm + 0.35 * ringm + 0.14 * spb * (1 - 0.7 * cl) - 0.10 * inner
    alpha = alpha * (0.88 + 0.14 * ctx.fbm01(10, 3))
    alpha = np.clip(alpha, 0, 0.85)
    col = np.broadcast_to(ramp(ctx.fbm01(12, 3), stops("#3a352f", "#4a443b", "#5b5347")), (n, n, 3)).copy()
    col = col * (1 - 0.25 * cl)[..., None]
    hh = hgt.h
    hgt_out = 0.5 + 0.5 * (hh - 0.5) + 0.05 * rm + 0.02 * ctx.fbm(120, 2)
    rough = np.clip(0.06 + 0.9 * alpha, 0.05, 1)
    return dict(albedo=col, alpha=alpha, height=hgt_out, rough=rough, ao=np.ones((n, n), f32), slope=0.18)


@recipe("rust_overlay", 1.0, "Rust overlay (RGBA): corrosion colour with alpha coverage, pitting height, bleeding streaks (1 m tile).",
        "building", albedo=(0.04, 0.22),
        notes="Blend onto any metal; alpha = rust coverage; metallic 0 under rust.")
def rust_overlay(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    u, v = ctx.u, ctx.v
    cover = _rust_blotches(ctx, 0.66)
    streak = S(0.55, 0.9, ctx.fbm01(70, 3, fy=2)) * S(0.3, 0.7, ctx.fbm01(7, 3))
    cover = np.clip(cover + 0.55 * streak * (1 - cover), 0, 1)
    pits_w = ctx.worley(70)
    pits = S(0.45, 0.15, pits_w.f1) * (pits_w.rid > 0.55)
    blister = ctx.fbm(26, 4, kind="ridged")
    depth = ctx.fbm01(14, 5)
    h = 0.55 + 0.20 * (blister - 0.5) * cover - 0.22 * pits * cover + 0.10 * (depth - 0.5) + 0.02 * ctx.fbm(150, 2)
    h = h - 0.10 * (1 - cover)
    rust = ramp(0.5 * depth + 0.5 * ctx.fbm01(40, 4), [(0, C("#2e140b")), (0.35, C("#55260f")), (0.65, C("#7e3a16")),
                                                       (0.85, C("#9a5224")), (1.0, C("#b88036"))])
    edge = S(0.45, 0.8, cover) * (1 - S(0.8, 1.0, cover))
    rust = lerp(rust, C("#d2691f"), edge * 0.35)
    rust = rust * (1 - 0.35 * pits)[..., None]
    alpha = np.clip(cover * (0.9 + 0.1 * blister), 0, 1)
    ao = cavity_ao(h, radii=(1.5, 5, 14), weights=(0.4, 0.4, 0.2), gain=2.6)
    col = apply_ao(rust, ao, 0.6)
    rough = np.clip(0.80 + 0.15 * (1 - ao) - 0.2 * edge, 0.5, 1)
    return dict(albedo=col, alpha=alpha, height=h, ao=ao, rough=rough, slope=0.35)
