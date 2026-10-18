"""Tiny numpy-only oblique / perspective height-field renderer used for design review (no GPU, no extra packages).

    img = render(H, step, eye, target, size=(960, 540), fov=60, tex=None, ...)

H is the height field [j, i] (metres) on a grid of `step` metres covering [-2016, 2016] (index 0 = -2016). `eye` and
`target` are world (X, Y, Z) metres (X north, Y east, Z up). The image is ray-marched (fixed-step with a final
bisection), lit by a sun + sky term, with simple distance haze. `tex` is an optional [j, i, 3] uint8 colour texture on the
same grid (roads, biome colours...). Rays that leave the map or hit nothing get the sky gradient.
"""
import math

import numpy as np

from common import HALF


def _bilin(A, fi, fj):
    h, w = A.shape[:2]
    fi = np.clip(fi, 0.0, w - 1.001)
    fj = np.clip(fj, 0.0, h - 1.001)
    i0 = fi.astype(np.int32)
    j0 = fj.astype(np.int32)
    ti = (fi - i0).astype(np.float32)
    tj = (fj - j0).astype(np.float32)
    if A.ndim == 2:
        a00 = A[j0, i0]
        a01 = A[j0, i0 + 1]
        a10 = A[j0 + 1, i0]
        a11 = A[j0 + 1, i0 + 1]
        return (a00 * (1 - ti) + a01 * ti) * (1 - tj) + (a10 * (1 - ti) + a11 * ti) * tj
    ti = ti[:, None]
    tj = tj[:, None]
    a00 = A[j0, i0].astype(np.float32)
    a01 = A[j0, i0 + 1].astype(np.float32)
    a10 = A[j0 + 1, i0].astype(np.float32)
    a11 = A[j0 + 1, i0 + 1].astype(np.float32)
    return (a00 * (1 - ti) + a01 * ti) * (1 - tj) + (a10 * (1 - ti) + a11 * ti) * tj


def render(H, step, eye, target, size=(960, 540), fov=62.0, tex=None, sun_az=300.0, sun_alt=32.0, zex=1.0,
           sea_level=0.0, max_dist=7000.0, haze=0.00009, quality=1.0):
    W_, H_ = size
    eye = np.array(eye, dtype=np.float64)
    target = np.array(target, dtype=np.float64)
    fwd = target - eye
    fwd /= np.linalg.norm(fwd)
    up0 = np.array([0.0, 0.0, 1.0])
    right = np.cross(fwd, up0)
    right /= max(np.linalg.norm(right), 1e-9)
    up = np.cross(right, fwd)
    aspect = W_ / H_
    th = math.tan(math.radians(fov) / 2.0)
    xs = (np.arange(W_) + 0.5) / W_ * 2.0 - 1.0
    ys = 1.0 - (np.arange(H_) + 0.5) / H_ * 2.0
    px, py = np.meshgrid(xs * th * aspect, ys * th)
    d = fwd[None, None, :] + px[..., None] * right[None, None, :] + py[..., None] * up[None, None, :]
    d /= np.linalg.norm(d, axis=2, keepdims=True)
    d = d.reshape(-1, 3).astype(np.float32)
    n = d.shape[0]
    o = eye.astype(np.float32)
    Hh = H.astype(np.float32)
    nrow, ncol = Hh.shape
    inv = np.float32(1.0 / step)
    off = np.float32(HALF)
    t = np.full(n, 5.0, dtype=np.float32)
    hit = np.zeros(n, dtype=bool)
    alive = np.arange(n)
    t_hit = np.zeros(n, dtype=np.float32)
    dt0 = 3.0 / quality
    # march with growing step
    step_t = np.full(n, dt0, dtype=np.float32)
    tprev = t.copy()
    for it in range(4000):
        if alive.size == 0:
            break
        tt = t[alive]
        pos = o[None, :] + d[alive] * tt[:, None]
        fi = (pos[:, 0] + off) * inv
        fj = (pos[:, 1] + off) * inv
        inside = (fi >= 0) & (fi < ncol - 1) & (fj >= 0) & (fj < nrow - 1)
        hz = _bilin(Hh, fi, fj) * np.float32(zex)
        hz = np.maximum(hz, np.float32(sea_level - 0.0))
        below = (pos[:, 2] <= hz) & inside
        # rays that left the map going away or are too far
        gone = (~inside & (tt > 50.0)) | (tt > max_dist) | ((pos[:, 2] > 1100.0) & (d[alive, 2] > 0))
        if below.any():
            idx = alive[below]
            # bisection between previous and current t
            lo = tprev[idx].copy()
            hi = t[idx].copy()
            for _ in range(7):
                mid = 0.5 * (lo + hi)
                pm = o[None, :] + d[idx] * mid[:, None]
                hm = np.maximum(_bilin(Hh, (pm[:, 0] + off) * inv, (pm[:, 1] + off) * inv) * np.float32(zex), np.float32(sea_level))
                under = pm[:, 2] <= hm
                hi = np.where(under, mid, hi)
                lo = np.where(under, lo, mid)
            t_hit[idx] = 0.5 * (lo + hi)
            hit[idx] = True
        keep = ~(below | gone)
        alive = alive[keep]
        tprev[alive] = t[alive]
        # adaptive step: larger when far from the surface / far away
        step_here = np.maximum(dt0, 0.0025 * t[alive] / quality)
        step_here = np.minimum(step_here, np.maximum(0.45 * np.abs(pos[keep, 2] - hz[keep]), dt0))
        t[alive] = t[alive] + step_here
    # shading
    img = np.zeros((n, 3), dtype=np.float32)
    # sky gradient
    sky_top = np.array([0.35, 0.55, 0.85], dtype=np.float32)
    sky_hor = np.array([0.80, 0.86, 0.93], dtype=np.float32)
    dz = np.clip(d[:, 2], 0, 1)
    img[:] = sky_hor[None, :] * (1 - dz[:, None] ** 0.5) + sky_top[None, :] * (dz[:, None] ** 0.5)
    hi_idx = np.nonzero(hit)[0]
    if hi_idx.size:
        pos = o[None, :] + d[hi_idx] * t_hit[hi_idx, None]
        fi = (pos[:, 0] + off) * inv
        fj = (pos[:, 1] + off) * inv
        e = 1.0
        hxp = _bilin(Hh, fi + e, fj)
        hxm = _bilin(Hh, fi - e, fj)
        hyp = _bilin(Hh, fi, fj + e)
        hym = _bilin(Hh, fi, fj - e)
        dhdx = (hxp - hxm) / (2 * e * step) * zex
        dhdy = (hyp - hym) / (2 * e * step) * zex
        nx = -dhdx
        ny = -dhdy
        nz = np.ones_like(nx)
        nl = np.sqrt(nx * nx + ny * ny + nz * nz)
        nx, ny, nz = nx / nl, ny / nl, nz / nl
        az = math.radians(sun_az)
        al = math.radians(sun_alt)
        lx, ly, lz = math.cos(al) * math.cos(az), math.cos(al) * math.sin(az), math.sin(al)
        lam = np.clip(nx * lx + ny * ly + nz * lz, 0.0, 1.0)
        amb = 0.32 + 0.18 * nz
        if tex is not None:
            tcol = _bilin(tex, fi, fj) / 255.0
        else:
            zz = pos[:, 2]
            tcol = np.stack([np.clip(0.35 + zz / 900.0, 0, 1), np.clip(0.5 - zz / 2500.0, 0, 1), np.clip(0.30 + zz / 2500.0, 0, 1)], 1)
        wet = pos[:, 2] <= sea_level + 0.05
        col = tcol * (amb + 0.85 * lam)[:, None]
        col[wet] = np.array([0.10, 0.30, 0.45], dtype=np.float32) * (0.7 + 0.5 * lam[wet])[:, None]
        # haze
        fog = 1.0 - np.exp(-haze * t_hit[hi_idx] * 1.0)
        col = col * (1 - fog[:, None]) + sky_hor[None, :] * fog[:, None]
        img[hi_idx] = col
    img = np.clip(img, 0, 1).reshape(H_, W_, 3)
    return (img * 255).astype(np.uint8)


def terrain_texture(H, step, snow_z=480.0, tree_z=420.0):
    """quick biome-ish colour texture [j,i,3] uint8 from heights and slopes (design review only)"""
    gy, gx = np.gradient(H.astype(np.float32), step)
    sl = np.sqrt(gx * gx + gy * gy)
    z = H.astype(np.float32)
    grass = np.array([0.30, 0.46, 0.20], dtype=np.float32)
    forest = np.array([0.15, 0.30, 0.15], dtype=np.float32)
    dry = np.array([0.62, 0.45, 0.28], dtype=np.float32)
    rock = np.array([0.45, 0.43, 0.42], dtype=np.float32)
    snow = np.array([0.93, 0.95, 0.98], dtype=np.float32)
    sand = np.array([0.80, 0.74, 0.55], dtype=np.float32)
    t_rock = np.clip((sl - 0.55) / 0.35, 0, 1)[..., None]
    t_snow = np.clip((z - snow_z) / 40.0, 0, 1)[..., None] * (1 - t_rock * 0.7)
    t_for = np.clip((tree_z - z) / 120.0, 0, 1)[..., None] * (1 - t_rock)
    col = grass[None, None, :] * (1 - t_for) + forest[None, None, :] * t_for
    col = col * (1 - t_rock) + rock * t_rock
    col = col * (1 - t_snow) + snow * t_snow
    col = np.where((z < 3.0)[..., None], sand[None, None, :], col)
    return (np.clip(col, 0, 1) * 255).astype(np.uint8)


def road_texture(base_rgb, roads, step, width_m=7.0, colors=None):
    """paint road polylines (list of dict with 'xy' (n,2) and 'cls') onto a copy of base_rgb [j,i,3]."""
    tex = base_rgb.copy()
    h, w = tex.shape[:2]
    cols = colors or {"HIGHWAY": (50, 50, 55), "REGIONAL": (60, 60, 64), "MOUNTAIN": (66, 62, 64), "DIRT": (150, 120, 85),
                      "SHORTCUT": (150, 120, 85), "VILLAGE": (80, 80, 84)}
    r = max(0, int(round(width_m / step / 2.0)))
    for rd in roads:
        xy = rd["xy"]
        fi = (xy[:, 0] + HALF) / step
        fj = (xy[:, 1] + HALF) / step
        # densify
        seg = np.hypot(np.diff(fi), np.diff(fj))
        cum = np.concatenate([[0], np.cumsum(seg)])
        nn = int(cum[-1] * 2) + 2
        tq = np.linspace(0, cum[-1], nn)
        ci = np.interp(tq, cum, fi)
        cj = np.interp(tq, cum, fj)
        c8 = np.array(cols.get(rd["cls"], (60, 60, 60)), dtype=np.uint8)
        for dj in range(-r, r + 1):
            for di in range(-r, r + 1):
                ii = np.clip(np.round(ci).astype(int) + di, 0, w - 1)
                jj = np.clip(np.round(cj).astype(int) + dj, 0, h - 1)
                tex[jj, ii] = c8
    return tex
