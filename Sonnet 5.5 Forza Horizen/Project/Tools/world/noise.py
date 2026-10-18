"""Numpy-only procedural noise: B-spline lattice noise, fBm, ridged multifractal, domain warping.

All functions work on arrays indexed [j, i] with a given sample spacing `step` (metres).
Wavelengths are given in metres. Every function takes a numpy Generator so results are deterministic.
The lattice interpolation is done with 4-tap gathers (no dense matmul - the bundled numpy has no fast BLAS).
"""
import numpy as np

_NORM = 151.0 / 315.0   # std of a cubic-B-spline filtered white-noise lattice in 2-D (per-axis factor)


def _axis_taps(n, wl, off):
    u = (np.arange(n, dtype=np.float64) + off) / wl
    i0 = np.floor(u).astype(np.int64)
    t = (u - i0).astype(np.float32)
    t2 = t * t
    t3 = t2 * t
    w = np.stack([(1 - t) ** 3 / 6.0,
                  (3 * t3 - 6 * t2 + 4) / 6.0,
                  (-3 * t3 + 3 * t2 + 3 * t + 1) / 6.0,
                  t3 / 6.0]).astype(np.float32)
    mn = int(i0.min())
    idx = np.stack([i0 - mn + k for k in range(4)])
    return idx, w, int(idx.max()) + 1


def noise2(shape, wl_samples, rng, off=None):
    """Unit-variance smooth noise, feature size ~wl_samples (scalar or (wy, wx))."""
    h, w = shape
    if np.isscalar(wl_samples):
        wly = wlx = float(wl_samples)
    else:
        wly, wlx = float(wl_samples[0]), float(wl_samples[1])
    if off is None:
        off = (rng.uniform(0, wly), rng.uniform(0, wlx))
    iy, wy, ny = _axis_taps(h, wly, off[0])
    ix, wx, nx = _axis_taps(w, wlx, off[1])
    L = rng.standard_normal((ny, nx)).astype(np.float32)
    T = None
    for k in range(4):
        part = L[:, ix[k]] * wx[k][None, :]
        T = part if T is None else T + part
    out = None
    for k in range(4):
        part = T[iy[k], :] * wy[k][:, None]
        out = part if out is None else out + part
    out *= np.float32(1.0 / (_NORM))
    return out


def fbm(shape, wl_m, octaves, rng, step=1.0, gain=0.5, lac=2.0, min_wl_samples=2.5):
    """Fractional Brownian motion. wl_m = wavelength of the first octave in metres. Roughly unit std."""
    out = np.zeros(shape, dtype=np.float32)
    amp = 1.0
    var = 0.0
    wl = wl_m / step
    for _ in range(octaves):
        if wl < min_wl_samples:
            break
        out += np.float32(amp) * noise2(shape, wl, rng)
        var += amp * amp
        amp *= gain
        wl /= lac
    out *= np.float32(1.0 / np.sqrt(var))
    return out


def ridged(shape, wl_m, octaves, rng, step=1.0, gain=0.5, lac=2.0, offset=1.0, min_wl_samples=2.5):
    """Ridged multifractal, result roughly in [0, 1] (peaks at ridges)."""
    out = np.zeros(shape, dtype=np.float32)
    amp = 1.0
    tot = 0.0
    weight = np.ones(shape, dtype=np.float32)
    wl = wl_m / step
    for _ in range(octaves):
        if wl < min_wl_samples:
            break
        n = noise2(shape, wl, rng) * np.float32(0.55)
        np.clip(n, -1.0, 1.0, out=n)
        r = np.float32(offset) - np.abs(n)
        r *= r
        r *= weight
        weight = np.clip(r * 2.0, 0.0, 1.0)
        out += np.float32(amp) * r
        tot += amp
        amp *= gain
        wl /= lac
    out *= np.float32(1.0 / tot)
    return out


def mountain_noise(shape, wl_m, octaves, rng, step=1.0, gain=0.5, lac=2.0, h_scale=450.0, k_erode=2.5, ridge=1.0, power=2.0,
                   min_wl_samples=2.5):
    """Eroded ridged multifractal ('slope-damped'): every octave is damped by the slope accumulated by the coarser octaves,
    giving smooth steep flanks with ridges and detail concentrated on gentler ground (the look of eroded alpine relief).
    h_scale = metres of height the field is going to be multiplied by (needed to estimate slopes); result ~[0,1]."""
    out = np.zeros(shape, dtype=np.float32)
    gxa = np.zeros(shape, dtype=np.float32)
    gya = np.zeros(shape, dtype=np.float32)
    amp = 1.0
    tot = 0.0
    wl = wl_m / step
    for _ in range(octaves):
        if wl < min_wl_samples:
            break
        n = noise2(shape, wl, rng) * np.float32(0.55)
        np.clip(n, -1.0, 1.0, out=n)
        r = np.float32(1.0 - ridge) * (n * np.float32(0.5) + np.float32(0.5)) + np.float32(ridge) * (1.0 - np.abs(n)) ** power
        gy, gx = np.gradient(r, step)
        den = 1.0 + k_erode * (h_scale * h_scale) * (gxa * gxa + gya * gya)
        out += np.float32(amp) * r / den.astype(np.float32)
        gxa += np.float32(amp) * gx
        gya += np.float32(amp) * gy
        tot += amp
        amp *= gain
        wl /= lac
    return out * np.float32(1.0 / tot)


def sample_index(A, fj, fi):
    """Bilinear sample of A at fractional indices (fj rows, fi cols)."""
    h, w = A.shape
    fi = np.clip(fi, 0, w - 1.001)
    fj = np.clip(fj, 0, h - 1.001)
    i0 = fi.astype(np.int32)
    j0 = fj.astype(np.int32)
    ti = (fi - i0).astype(np.float32)
    tj = (fj - j0).astype(np.float32)
    flat = A.ravel()
    k = j0 * w + i0
    a00 = flat[k]
    a01 = flat[k + 1]
    a10 = flat[k + w]
    a11 = flat[k + w + 1]
    return (a00 * (1 - ti) + a01 * ti) * (1 - tj) + (a10 * (1 - ti) + a11 * ti) * tj


def warp(A, dx_m, dy_m, step=1.0):
    """Resample A displaced by (dx_m along +i, dy_m along +j) metres (domain warping)."""
    h, w = A.shape
    jj, ii = np.mgrid[0:h, 0:w].astype(np.float32)
    return sample_index(A, jj + dy_m / step, ii + dx_m / step)


def upsample2(A, clamp=True):
    """Upsample [N, N] -> [2N-1, 2N-1] with Catmull-Rom (gather based) and optional local min/max clamp."""
    def ax(arr, axis):
        n = arr.shape[axis]
        a = np.take(arr, np.clip(np.arange(-1, n + 2), 0, n - 1), axis=axis)   # padded by 1

        def s(lo, hi):
            idx = [slice(None)] * arr.ndim
            idx[axis] = slice(lo, hi)
            return a[tuple(idx)]
        p0, p1, p2, p3 = s(0, n - 1), s(1, n), s(2, n + 1), s(3, n + 2)
        mid = (-p0 + 9 * p1 + 9 * p2 - p3) / 16.0   # Catmull-Rom at t = 0.5
        if clamp:
            mid = np.minimum(np.maximum(mid, np.minimum(p1, p2)), np.maximum(p1, p2))
        out_shape = list(arr.shape)
        out_shape[axis] = 2 * n - 1
        out = np.empty(out_shape, dtype=arr.dtype)
        i1 = [slice(None)] * arr.ndim
        i2 = [slice(None)] * arr.ndim
        i1[axis] = slice(0, 2 * n - 1, 2)
        i2[axis] = slice(1, 2 * n - 1, 2)
        out[tuple(i1)] = arr
        out[tuple(i2)] = mid
        return out
    return ax(ax(A.astype(np.float32), 0), 1)
