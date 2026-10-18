"""Helpers shared by the recipe modules."""
from __future__ import annotations

import math

import numpy as np

from ..maps import hexc, lerp, ramp, luminance, cavity_ao, lin_to_srgb, srgb_to_lin
from ..noise import f32, norm01, smoothstep, blur

C = hexc


def pal(*hexes):
    return [hexc(h) for h in hexes]


def stops(*hexes):
    """Evenly spaced colour ramp stops from hex strings."""
    k = len(hexes) - 1
    return [(i / k, hexc(h)) for i, h in enumerate(hexes)]


def S(e0, e1, x):
    return smoothstep(e0, e1, x)


def rpick(rng, palette):
    """Random colour: random blend of two random palette entries."""
    i = rng.integers(0, len(palette))
    j = rng.integers(0, len(palette))
    return palette[i] + (palette[j] - palette[i]) * f32(rng.random())


def apply_ao(alb, ao, k=0.6):
    return alb * (1 - k + k * ao)[..., None]


def tint_speckle(ctx, alb, amount=0.08, f=None):
    """Fine per-pixel luminance speckle (grain) multiplicatively."""
    g = ctx.grain(1.0)
    return alb * (1 + amount * np.clip(g, -3, 3))[..., None]


def rough_field(ctx, base, h=None, h_amp=0.0, macro_amp=0.05, macro_f=5, ao=None, ao_amp=0.0,
                fine_amp=0.0, lo=0.05, hi=1.0):
    """Roughness map with correlated variation instead of a constant:

        base  (scalar or (H,W))
      - macro_amp * tileable fbm (+-1)     : large patches of wetter / drier / dustier surface
      - h_amp * (height - 0.5) * 2         : crests / blade tips are smoother (sheen), valleys rougher
      + ao_amp * (1 - ao)                  : cavities collect dust -> rougher
      + fine_amp * per-pixel grain

    Call it LAST in a recipe so the extra noise draws do not shift the seeds of earlier layers."""
    r = np.array(np.broadcast_to(np.asarray(base, f32), (ctx.n, ctx.n)), f32)
    if macro_amp:
        r = r + f32(macro_amp) * ctx.fbm(macro_f, 4)
    if h is not None and h_amp:
        r = r - f32(h_amp) * (norm01(np.asarray(h, f32), 1, 99) - f32(0.5)) * f32(2)
    if ao is not None and ao_amp:
        r = r + f32(ao_amp) * (f32(1) - np.asarray(ao, f32))
    if fine_amp:
        r = r + ctx.grain(fine_amp)
    return np.clip(r, lo, hi).astype(f32)


def edge_px(e, s=1.0):
    """Approximate distance (pixels at 1024 scale) to the nearest Voronoi edge from e = f2 - f1.

    Worley distances live in *cell* space, so with anisotropic frequencies (fx != fy) a fixed
    threshold on e gives fissures that are several times wider in one direction than the other.
    Dividing by the gradient magnitude of e turns it into an isotropic texture-space distance."""
    e = np.asarray(e, f32)
    gx = (np.roll(e, -1, 1) - np.roll(e, 1, 1)) * f32(0.5)
    gy = (np.roll(e, -1, 0) - np.roll(e, 1, 0)) * f32(0.5)
    g = np.sqrt(gx * gx + gy * gy)
    # near cell vertices the gradient vanishes -> clamp so d stays finite there
    d = e / np.maximum(g, f32(0.35) * np.median(g[::5, ::5]) + f32(1e-9))
    return d / f32(s)


def coverage_to_rough(h, base, var, lo, hi):
    return np.clip(base + var * (h - 0.5), lo, hi)


def blend(a, b, m):
    return lerp(a, b, m)


def leaf_colfn(col, vein=0.28, lateral=6.0, edge=0.18, mid_w=0.09):
    """Colour function for blade(): midrib + lateral veins + edge darkening."""
    col = np.asarray(col, f32)

    def f(t, sn):
        mid = np.exp(-(sn / mid_w) ** 2)
        lat = np.maximum(0.0, np.cos(t * lateral * math.pi * 2 - np.abs(sn) * math.pi * 1.6)) ** 10
        lat = lat * (np.abs(sn) > mid_w)
        k = 1.0 + vein * mid + 0.55 * vein * lat - edge * np.abs(sn) ** 3 - 0.10 * t
        return col * k[..., None].astype(f32)
    return f


def leaf_prof(shape=0.75, lobes=0.0, lobe_n=3.5, power=0.8):
    def f(t):
        base = np.maximum(np.sin(np.pi * np.clip(t, 0, 1) ** shape), 0.0) ** power
        if lobes:
            base = base * (1 - lobes + lobes * (0.5 + 0.5 * np.cos(t * 2 * math.pi * lobe_n)))
        return base.astype(f32)
    return f


def sample_at(arr, x, y):
    """Sample 2D array at integer pixel positions with wrap."""
    n = arr.shape[0]
    return arr[(y.astype(np.int64) % n), (x.astype(np.int64) % n)]


def hash01(a, b=0.0):
    """Deterministic float64 hash -> [0,1) (shader style); works on integer-valued arrays."""
    x = np.sin(np.asarray(a, np.float64) * 12.9898 + np.asarray(b, np.float64) * 78.233) * 43758.5453
    return (x - np.floor(x)).astype(f32)


def bleed_colour(col, alpha, sigma=3.0, iters=4):
    """Extend opaque colours into fully transparent texels (avoids dark/white halos when the
    atlas is filtered or mip-mapped). col (H,W,3), alpha (H,W)."""
    known = (alpha > 0.04).astype(f32)
    c = col * known[..., None]
    w = known.copy()
    for k in range(iters):
        sg = sigma * (2 ** k)
        cb = blur(c, sg)
        wb = blur(w, sg)
        fill = (w < 0.5) & (wb > 1e-4)
        newc = cb / np.maximum(wb, 1e-4)[..., None]
        c = np.where(fill[..., None], newc, c)
        w = np.where(fill, 1.0, w).astype(f32)
    return np.where((alpha > 0.04)[..., None], col, c).astype(f32)


def bezier(p0, p1, p2, n=24):
    t = np.linspace(0, 1, n)[:, None]
    p0, p1, p2 = np.array(p0, float), np.array(p1, float), np.array(p2, float)
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t ** 2 * p2


def bezier_tangent(p0, p1, p2, t):
    p0, p1, p2 = np.array(p0, float), np.array(p1, float), np.array(p2, float)
    d = 2 * (1 - t) * (p1 - p0) + 2 * t * (p2 - p1)
    return d / (np.linalg.norm(d) + 1e-9)


class Masonry:
    """Result of masonry(): per-pixel layout of courses (rows) of blocks of random width."""
    pass


def masonry(ctx, rows, per_row=(8, 10), width_var=0.25, row_h_var=0.0, offsets="random",
            uv=None, rng=None):
    """Row-banded block layout that tiles seamlessly (every row's widths sum to exactly 1 tile).

    Returns Masonry with arrays: row (int), lx, ly (0..1 inside the block), wt, ht (block size in
    turns), rnd, rnd2 (per-block random 0..1), sid (global block id)."""
    rng = rng or ctx.rng_k()
    u, v = uv or (ctx.u, ctx.v)
    m = Masonry()
    vm = np.mod(v, f32(1.0))
    if row_h_var > 0:
        hh = 1 + (rng.random(rows) - 0.5) * 2 * row_h_var
        hh /= hh.sum()
        vb = np.concatenate([[0.0], np.cumsum(hh)])
        vb[-1] = 1.0 + 1e-6
        r = np.clip(np.searchsorted(vb, vm.ravel(), side="right") - 1, 0, rows - 1).reshape(vm.shape)
        hh32 = hh.astype(f32)
        ly = (vm - vb[:-1].astype(f32)[r]) / hh32[r]
        ht = hh32[r]
    else:
        t = vm * f32(rows)
        r = np.minimum(np.floor(t).astype(np.int32), rows - 1)
        ly = t - r
        ht = np.full(vm.shape, 1.0 / rows, f32)
    K = rng.integers(per_row[0], per_row[1] + 1, rows)
    Bs, Ws, Rs = [], [], []
    for i in range(rows):
        w = 1 + (rng.random(K[i]) - 0.5) * 2 * width_var
        w /= w.sum()
        Bs.append(i + np.cumsum(w))
        Ws.append(w)
        Rs.append(rng.random(K[i]))
    B = np.concatenate(Bs)
    W = np.concatenate(Ws)
    R = np.concatenate(Rs)
    if offsets == "random":
        off = rng.random(rows)
    elif offsets == "half":
        off = np.where(np.arange(rows) % 2 == 0, 0.0, 0.5 / np.maximum(K, 1))
    else:
        off = np.zeros(rows)
    xr = u - off.astype(f32)[r]
    xr = xr - np.floor(xr)
    key = r.astype(f32) + xr
    sid = np.minimum(np.searchsorted(B, key.ravel(), side="right"), len(B) - 1).reshape(key.shape)
    start = (B - W).astype(f32)
    lx = (key - start[sid]) / W.astype(f32)[sid]
    m.row = r
    m.lx = lx
    m.ly = ly
    m.wt = W.astype(f32)[sid]
    m.ht = ht
    m.rnd = R.astype(f32)[sid]
    m.rnd2 = hash01(sid * 1.0 + 0.37)
    m.sid = sid
    return m


def rrect_sd(lx, ly, wt, ht, rad):
    """Signed distance (turns) to a rounded rectangle block (negative inside)."""
    qx = np.abs(lx - 0.5) * wt - (wt * 0.5 - rad)
    qy = np.abs(ly - 0.5) * ht - (ht * 0.5 - rad)
    return np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - rad


def periodic_profile(table, x):
    """Look up a periodic 1D table (len T) at x in turns (nearest)."""
    T = table.shape[0]
    return table[np.minimum((np.mod(x, f32(1.0)) * T).astype(np.intp), T - 1)]
