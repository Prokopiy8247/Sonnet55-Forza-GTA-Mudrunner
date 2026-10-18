"""World / FX texture recipes: noise sets, water normals, rain, particles, decals, lens dirt."""
from __future__ import annotations

import math

import numpy as np

from .. import noise as nz
from ..core import recipe
from ..maps import ramp, lerp, luminance, cavity_ao, normal_from_height_auto
from ..noise import f32, norm01, blur
from .common import C, pal, stops, S, rpick, hash01

TAU = 2 * math.pi


# ======================================================================================
# data noises
# ======================================================================================
@recipe("tileable_perlin_noise", [16.0, 16.0],
        "Four independent tileable noises (RGBA data): R perlin fBm, G perlin fBm (finer), B worley billow, A ridged. Use for macro variation, masks, material blending.",
        "fx", tileable=True, notes="Linear data (sRGB off). Suggested world tiling 16-64 m.")
def tileable_perlin_noise(ctx):
    n = ctx.n
    r = norm01(ctx.fbm(4, 6, kind="perlin"), 0.5, 99.5)
    g = norm01(ctx.fbm(9, 5, kind="perlin"), 0.5, 99.5)
    w = ctx.worley(7)
    b = norm01(0.7 * (1 - np.clip(w.f1, 0, 1.2)) + 0.3 * ctx.fbm01(20, 4), 0.5, 99.5)
    a = norm01(ctx.fbm(5, 6, kind="ridged"), 0.5, 99.5)
    data = np.stack([r, g, b, a], -1)
    return dict(files={"D": dict(arr=data, srgb=False, role="RGBA independent noises R=perlin G=perlin(fine) B=worley A=ridged")})


@recipe("blue_noise", [1.0, 1.0],
        "Tileable blue noise (4 independent channels, RGBA) for dithering / stochastic sampling; _H is the 16-bit version of channel R.",
        "fx", tileable=True, notes="Uniform histogram per channel; linear data (sRGB off).")
def blue_noise(ctx):
    n = ctx.n
    chans = [nz.blue_noise(n, seed=ctx.seed + 17 * i, iterations=12, sigma=1.5) for i in range(4)]
    data = np.stack(chans, -1)
    return dict(files={"D": dict(arr=data, srgb=False, role="RGBA independent blue-noise channels"),
                       "H": dict(arr=chans[0], srgb=False, bits=16, role="blue noise 16-bit (R channel)")})


@recipe("cloud_noise", [64.0, 64.0],
        "Tileable cloud / volumetric-style noise (RGBA data): R perlin-worley cloud shape, G/B/A worley FBM at 3 frequencies. Use for sky dome clouds, cloud shadows, fog breakup.",
        "fx", tileable=True, notes="Linear data (sRGB off). Suggested world tiling 64-256 m.")
def cloud_noise(ctx):
    n = ctx.n
    u, v = ctx.u, ctx.v
    uw, vw = ctx.warp(0.04, 3, 3)
    pf = norm01(ctx.fbm(4, 6, uv=(uw, vw)), 0.5, 99.5)
    w1 = nz.worley_fbm(uw, vw, 5, 3, seed=ctx.sd())
    w2 = nz.worley_fbm(u, v, 10, 3, seed=ctx.sd())
    w3 = nz.worley_fbm(u, v, 20, 3, seed=ctx.sd())
    w4 = nz.worley_fbm(u, v, 40, 2, seed=ctx.sd())
    shape = np.clip(pf * 0.55 + (norm01(w1) * 0.65) - 0.15, 0, 1)
    shape = norm01(shape, 1, 99)
    # remap into puffy coverage: soft threshold
    shape = S(0.18, 0.95, shape) ** 0.9
    data = np.stack([shape, norm01(w2), norm01(w3), norm01(w4)], -1)
    return dict(files={"D": dict(arr=data, srgb=False, role="RGBA R=cloud shape G/B/A=worley fbm low/mid/high"),
                       "H": dict(arr=shape, srgb=False, bits=16, role="cloud shape 16-bit")})


# ======================================================================================
# water
# ======================================================================================
def _water(ctx, slope, kmin, kmax, ax=1.0, ay=1.0, ang=0.0):
    """Wave height field from an FFT power-law spectrum (periodic by construction), 0..1."""
    h = nz.spectral(ctx.n, slope, ctx.sd(), kmin, kmax, ax, ay, ang)
    return ((h - h.min()) / (h.max() - h.min())).astype(f32)


@recipe("water_normal_a", [8.0, 8.0], "Calm lake water normal map: broad soft swells plus fine ripples (8 m tile). Tileable, DirectX normal.",
        "fx", tileable=True, notes="Use two scrolling layers at different scales/speeds. Linear data.")
def water_normal_a(ctx):
    n = ctx.n
    sw = nz.spectral(n, 3.6, ctx.sd(), 2, 40, 1.0, 1.0, 0.0)
    rp = nz.spectral(n, 3.0, ctx.sd(), 10, 150, 1.0, 1.35, 0.8)
    h = sw + 0.55 * rp
    h = (h - h.min()) / (h.max() - h.min())
    return dict(height=h.astype(f32), slope=0.12, skip=["ORM"], write_h=True)


@recipe("water_normal_b", [4.0, 4.0], "Choppy water normal map (river / sea): sharp crests, stretched along V (4 m tile). Tileable, DirectX normal.",
        "fx", tileable=True, notes="Stretched along V so it reads as flowing water; rotate for other flow directions.")
def water_normal_b(ctx):
    n = ctx.n
    h = nz.spectral(n, 3.0, ctx.sd(), 3, 90, 1.0, 2.6, 0.0)
    h = h + 0.45 * nz.spectral(n, 2.8, ctx.sd(), 10, 200, 1.0, 2.0, 0.0)
    h = h / h.std()
    # trochoid-like profile: narrow crests, wide troughs
    h = np.where(h > 0, h * (1.0 + 0.35 * h), h * 0.7)
    rip = norm01(ctx.fbm(20, 4, kind="ridged", fy=5), 1, 99)
    h = h / h.std() + 0.35 * (rip - 0.5) / (rip.std() + 1e-6) * 0.5
    h = (h - h.min()) / (h.max() - h.min())
    return dict(height=h.astype(f32), slope=0.22, skip=["ORM"], write_h=True)


# ======================================================================================
# weather / particles / decals
# ======================================================================================
@recipe("rain_streaks", [1.0, 1.0], "Rain streak sprite sheet (RGBA): layered fine and heavy streaks, wrap-seamless in U and V; scroll along V for rain.",
        "fx", albedo=(0.5, 1.0), tileable=True, notes="Slight 6 degree slant. White-blue colour, alpha = streak coverage.")
def rain_streaks(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    cv = ctx.canvas(color=(1, 1, 1), h=0.0, alpha=0.0)
    slant = math.radians(6.0)
    for layer, (count, lmin, lmax, w, amul) in enumerate([(900, 90, 260, 0.7, 0.35), (420, 160, 420, 1.1, 0.6), (120, 300, 600, 1.9, 0.85)]):
        N = int(count * s)
        for i in range(N):
            L = rng.uniform(lmin, lmax) * s
            x, y = rng.random() * n, rng.random() * n
            a = math.pi / 2 - slant + rng.normal(0, 0.02)
            wid = w * s * rng.uniform(0.8, 1.2)
            col = np.array([0.80, 0.88, 1.0], f32) * f32(rng.uniform(0.85, 1.0))
            cv.blade(x, y, a, L, wid, wid * 0.5, 0, col, col, alpha_mul=amul * rng.uniform(0.5, 1.0),
                     wprof=lambda t: 1 - 0.7 * np.clip(t, 0, 1) ** 2)
    alpha = np.clip(cv.a, 0, 1)
    alpha = np.clip(blur(alpha, 0.6 * s), 0, 1)
    return dict(albedo=cv.c, alpha=alpha, skip=["ORM", "N", "H"])


def _sprite_grid(ctx):
    n = ctx.n
    x = (np.arange(n, dtype=f32) + 0.5) / n * 2 - 1
    xx, yy = np.meshgrid(x, x)
    return xx, yy, np.sqrt(xx * xx + yy * yy)


def _puff(ctx, radius, wob1, wob2, detail_amp, core_pow, smooth=False):
    """Shared volumetric-puff density: warped radial falloff times billowy detail."""
    n, s = ctx.n, ctx.s
    xx, yy, r = _sprite_grid(ctx)
    t1 = ctx.fbm(2, 3)
    t2 = ctx.fbm(5, 4)
    rw = r * (1 + wob1 * t1 + wob2 * t2)
    core = np.clip(1 - rw / radius, 0, 1) ** core_pow
    det = norm01(ctx.fbm(4, 3)) if smooth else norm01(ctx.fbm(6, 5, kind="billow"))
    dens = np.clip(core * (1 - detail_amp + detail_amp * 1.6 * det), 0, 1)
    fade = 1 - S(0.80, 0.98, r)
    return dens * fade, xx, yy, r


def _light(dens, s, k=22.0, blur_px=9.0):
    """Cheap self-lighting from upper-left using the blurred density gradient."""
    d = blur(dens, blur_px * s)
    gx = np.roll(d, -3, 1) - np.roll(d, 3, 1)
    gy = np.roll(d, -3, 0) - np.roll(d, 3, 0)
    return np.clip(0.55 - (gx + gy) * k * 0.5, 0.0, 1.2)


@recipe("dust_puff_sprite", [1.0, 1.0], "Soft dust puff particle sprite (RGBA): tan, fluffy turbulent edge, fades to zero alpha before the border.",
        "fx", albedo=(0.2, 0.7), tileable=False, notes="Single sprite; wraps trivially (alpha 0 at borders). Colour fills the whole tile (no halos).")
def dust_puff_sprite(ctx):
    n, s = ctx.n, ctx.s
    dens, xx, yy, r = _puff(ctx, 0.92, 0.30, 0.16, 0.55, 1.1)
    alpha = np.clip(dens * 1.35, 0, 1) ** 1.1
    lit = _light(dens, s)
    base = np.array([0.62, 0.52, 0.40], f32)
    col = base * (0.62 + 0.55 * lit)[..., None] * (0.92 + 0.16 * norm01(ctx.fbm(14, 4)))[..., None]
    return dict(albedo=col, alpha=alpha, skip=["ORM", "N", "H"])


@recipe("smoke_puff_sprite", [1.0, 1.0], "Smoke / exhaust puff sprite (RGBA): billowy grey volume with self-shadowing, soft edge.",
        "fx", albedo=(0.04, 0.6), tileable=False, notes="Single sprite; wraps trivially (alpha 0 at borders).")
def smoke_puff_sprite(ctx):
    n, s = ctx.n, ctx.s
    dens, xx, yy, r = _puff(ctx, 0.95, 0.34, 0.20, 0.45, 0.9, smooth=True)
    alpha = np.clip(dens * 1.9, 0, 1) ** 1.1
    lit = _light(dens, s, 12.0, 12.0)
    thick = blur(dens, 24 * s)
    base = (0.10 + 0.50 * np.clip(lit, 0, 1) ** 1.3) * (1.0 - 0.45 * np.clip(thick * 1.6, 0, 1))
    base = base * (0.88 + 0.24 * norm01(ctx.fbm(12, 4)))
    col = np.stack([base, base, base * 1.03], -1).astype(f32)
    return dict(albedo=col, alpha=alpha, skip=["ORM", "N", "H"])


@recipe("tire_mark", [0.40, 3.0], "Tyre skid mark decal strip (RGBA): black rubber with tread streaks, ragged edges; tiles along V (0.4 m wide x 3 m long).",
        "fx", albedo=(0.01, 0.12), tileable=True,
        notes="Non-uniform scale: U spans 0.4 m, V spans 3 m. Stamp along the path; alpha fades via vertex colour.")
def tire_mark(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    rng = ctx.rng_k()
    edge_n = ctx.fbm(10, 4, fy=2) * 0.045 + ctx.fbm(40, 3, fy=3) * 0.018
    d = np.abs(u - 0.5 + 0.02 * ctx.fbm(2, 2, fy=1))
    band = 1 - S(0.34 + edge_n, 0.42 + edge_n + 0.03, d)
    # tread grooves (lighter streaks along V)
    tread = 0.5 + 0.5 * np.cos(TAU * (u - 0.5) * 9 + 0.5 * np.sin(TAU * v * 3))
    groove = S(0.78, 0.95, tread) * 0.35
    streak = ctx.fbm01(70, 3, fy=2)
    mott = ctx.fbm01(30, 4, fy=4)
    density = band * (0.78 + 0.22 * S(0.2, 0.9, streak)) * (1 - groove) * (0.80 + 0.30 * mott)
    # intermittent lightening along length (skip / lift)
    lift = S(0.55, 0.85, ctx.fbm01(3, 3, fy=2)) * 0.45
    alpha = np.clip(density * (1 - lift) * 1.1, 0, 1)
    soft = ctx.fbm01(150, 2, fy=6)
    alpha = np.clip(alpha * (0.85 + 0.30 * soft), 0, 1)
    col = np.broadcast_to(np.array([0.016, 0.015, 0.014], f32), (n, n, 3)).copy()
    col = col * (0.8 + 0.5 * ctx.fbm01(40, 3, fy=3))[..., None]
    h = 0.5 + 0.10 * alpha + 0.03 * ctx.fbm(60, 3, fy=5) - 0.03 * groove
    rough = np.clip(0.55 + 0.35 * (1 - alpha) - 0.1 * soft, 0.2, 1)
    return dict(albedo=col, alpha=alpha, height=h, rough=rough, ao=np.ones((n, n), f32), slope=0.10, write_h=False)


@recipe("skid_dirt", [0.8, 4.0], "Dirt / gravel skid and drift mark decal strip (RGBA): scraped groove with side berms; tiles along V (0.8 m wide x 4 m long).",
        "fx", albedo=(0.02, 0.18), tileable=True,
        notes="Non-uniform scale: U spans 0.8 m, V spans 4 m. The normal map is derived from an internal height field "
              "(groove = depression, side berms raised); it is deliberately NOT the alpha mask, so alpha is high where "
              "the surface is lowest. No separate _H file is written.")
def skid_dirt(ctx):
    n, s = ctx.n, ctx.s
    u, v = ctx.u, ctx.v
    rng = ctx.rng_k()
    wob = ctx.fbm(2, 3, fy=1) * 0.03 + ctx.fbm(9, 3, fy=2) * 0.008
    x = u - 0.5 + wob
    rn = ctx.fbm(14, 4, fy=2) * 0.03
    groove = np.exp(-((x / (0.13 + rn)) ** 2))
    berm_l = np.exp(-(((x + 0.20 + rn) / 0.045) ** 2))
    berm_r = np.exp(-(((x - 0.20 - rn) / 0.045) ** 2))
    berm = np.clip(berm_l + berm_r, 0, 1)
    inner = ctx.fbm01(60, 4, fy=3)
    h = 0.45 - 0.35 * groove * (0.8 + 0.2 * inner) + 0.28 * berm * (0.7 + 0.3 * ctx.fbm01(30, 3, fy=3)) + 0.04 * ctx.fbm(90, 3, fy=6)
    h = np.clip(h, 0, 1)
    cover = np.clip(groove + 0.8 * berm, 0, 1)
    edge = 1 - S(0.20, 0.50, np.abs(x) + 0.04 * ctx.fbm(12, 3, fy=2))
    alpha = np.clip(edge * (0.55 + 0.45 * cover) * (0.82 + 0.25 * inner), 0, 1)
    stone = S(0.88, 0.97, ctx.fbm01(160, 2))
    col = ramp(0.5 * inner + 0.5 * ctx.fbm01(24, 4), stops("#2c2018", "#46362a", "#5e4a38"))
    col = col * (0.7 + 0.5 * berm)[..., None] * (0.55 + 0.45 * (1 - groove))[..., None]
    col = lerp(col, C("#a89880"), stone * 0.5)
    rough = np.clip(0.88 - 0.15 * groove, 0.4, 1)
    ao = cavity_ao(h, radii=(2, 8, 20), weights=(0.3, 0.4, 0.3), gain=2.4)
    return dict(albedo=col, alpha=alpha, height=h, ao=ao, rough=rough, slope=0.35, write_h=False)


@recipe("lens_dirt", [1.0, 1.0], "Lens dirt / dust mask for bloom & post-process (RGB data): smudges, bokeh rings, specks, hairs, scratches on black.",
        "fx", tileable=True,
        notes="Linear data (sRGB off). Stored as an 8-bit 3-channel grey RGB file (R=G=B, no alpha channel): use any channel as the mask. "
              "Mean value is low; multiply with bloom/flare. Periodic (wraps without a seam), so it may also tile.")
def lens_dirt(ctx):
    n, s = ctx.n, ctx.s
    rng = ctx.rng_k()
    cv = ctx.canvas(color=(0, 0, 0))
    one = np.array([1.0, 1.0, 1.0], f32)
    # smudges
    sm = S(0.55, 0.9, ctx.fbm01(3, 5)) * 0.10 + S(0.62, 0.9, ctx.fbm01(8, 5)) * 0.07
    # bokeh discs / rings
    ring = ctx.canvas(color=(0, 0, 0))
    for i in range(int(90 * s * s)):
        x, y = rng.random() * n, rng.random() * n
        r = (10 + 70 * rng.random() ** 2.0) * s
        a = rng.uniform(0.05, 0.45)
        ring.oval(x, y, r, r, 0, col=one * a * 0.5, h0=None, irr=0.0)
        ring.oval(x, y, r * 0.93, r * 0.93, 0, col=one * a * 0.28, h0=None)
    ringc = ring.c[..., 0]
    # specks
    sp = ctx.canvas(color=(0, 0, 0))
    for i in range(int(1600 * s * s)):
        x, y = rng.random() * n, rng.random() * n
        r = (0.8 + 4.0 * rng.random() ** 3) * s
        sp.oval(x, y, r, r, 0, col=one * rng.uniform(0.2, 1.0), h0=None)
    # hairs and scratches
    hr = ctx.canvas(color=(0, 0, 0))
    for i in range(int(14 * s)):
        x, y = rng.random() * n, rng.random() * n
        L = (120 + 400 * rng.random()) * s
        a = rng.random() * TAU
        pts_n = 10
        px, py = x, y
        for q in range(pts_n):
            da = rng.normal(0, 0.35)
            a += da
            seg = L / pts_n
            hr.blade(px, py, a, seg + 1, 0.9 * s, 0.9 * s, 0, one * 0.8, one * 0.8)
            px += math.cos(a) * seg
            py += math.sin(a) * seg
    for i in range(int(22 * s)):
        x, y = rng.random() * n, rng.random() * n
        L = (60 + 300 * rng.random()) * s
        hr.blade(x, y, rng.random() * TAU, L, 0.6 * s, 0.4 * s, 0, one * 0.5, one * 0.5)
    mask = (0.35 * sm + 0.9 * ringc + 0.85 * sp.c[..., 0] + 0.7 * hr.c[..., 0])
    mask = blur(mask, 0.8 * s)
    mask = np.clip(mask * (0.75 + 0.5 * ctx.fbm01(5, 4)), 0, 1)
    data = np.stack([mask, mask, mask], -1)
    return dict(files={"D": dict(arr=data, srgb=False, role="lens dirt mask (RGB equal)")})
