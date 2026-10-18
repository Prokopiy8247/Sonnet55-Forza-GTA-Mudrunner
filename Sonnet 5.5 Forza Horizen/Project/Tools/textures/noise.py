"""Tileable noise primitives implemented with numpy only.

Every lattice noise is periodic: the lattice index is taken modulo the integer frequency, so
any (u, v) in turns (1.0 == one tile) wraps seamlessly.  Domain warping stays seamless as long
as the warp offsets are themselves periodic, which is the case for all functions here.

Conventions
-----------
* coordinates u (x / columns) and v (y / rows) are float32 arrays in "turns" (tile = [0, 1)).
* perlin / value / fbm(kind=perlin|value) return signed values in roughly [-1, 1].
* ridged / billow / worley / cracks return [0, 1] (worley distances are in cell units).
* spectral() is FFT-synthesised noise (inherently periodic) with a power-law spectrum.

Performance
-----------
Arrays created by make_grid() are registered as *regular grids*.  When a noise function is called
with such a (u, v) pair it switches to a separable fast path (1D index / weight vectors,
broadcasting, axis-wise gathers); the result is bit-identical to the generic path, only 2-5x faster.
"""
from __future__ import annotations

import weakref

import numpy as np

f32 = np.float32
TAU = 6.283185307179586

_GU = weakref.WeakValueDictionary()
_GV = weakref.WeakValueDictionary()


def rng_for(*key) -> np.random.Generator:
    """Deterministic generator from an integer key tuple."""
    return np.random.default_rng([int(k) & 0xFFFFFFFF for k in key])


def make_grid(n: int):
    """u (varies along columns) and v (varies along rows) at pixel centres, in turns."""
    t = (np.arange(n, dtype=f32) + f32(0.5)) / f32(n)
    u = np.ascontiguousarray(np.broadcast_to(t[None, :], (n, n)))
    v = np.ascontiguousarray(np.broadcast_to(t[:, None], (n, n)))
    _GU[id(u)] = u
    _GV[id(v)] = v
    return u, v


def _regular(u, v):
    """Return the 1D coordinate vector if (u, v) are an untouched make_grid() pair."""
    if _GU.get(id(u)) is u and _GV.get(id(v)) is v and u.shape == v.shape:
        n = u.shape[0]
        return (np.arange(n, dtype=f32) + f32(0.5)) / f32(n)
    return None


def fade(t):
    return t * t * t * (t * (t * f32(6) - f32(15)) + f32(10))


def _axis(t, f):
    """1D lattice terms along one axis: (i0, i1, frac)."""
    x = t * f32(f)
    xf = np.floor(x)
    i0 = xf.astype(np.intp) % f
    i1 = (i0 + 1) % f
    return i0, i1, x - xf


# --------------------------------------------------------------------------------------
# lattice noises
# --------------------------------------------------------------------------------------
def perlin(u, v, fx, fy=None, seed=0, rot45=False):
    """Gradient (Perlin) noise, periodic with fx x fy cells per tile. Range ~[-1, 1].

    rot45 samples the lattice rotated by 45 degrees (integer matrix => still periodic), which
    together with the unrotated lattice removes most axis-aligned artefacts of plain Perlin
    noise (our stand-in for simplex noise, which cannot tile on a square torus)."""
    fx = int(fx)
    fy = fx if fy is None else int(fy)
    t1 = None if rot45 else _regular(u, v)
    r = rng_for(seed, fx, fy, 1)
    ang = r.random((fy, fx), dtype=f32) * f32(TAU)
    GX = np.cos(ang)
    GY = np.sin(ang)
    if t1 is not None:
        return _perlin_regular(t1, fx, fy, GX, GY)
    if rot45:
        fy = fx
        x = (u + v) * f32(fx)
        y = (v - u) * f32(fx)
    else:
        x = u * f32(fx)
        y = v * f32(fy)
    xf = np.floor(x)
    yf = np.floor(y)
    tx = x - xf
    ty = y - yf
    ix0 = xf.astype(np.intp)
    ix0 %= fx
    ix1 = ix0 + 1
    ix1[ix1 == fx] = 0
    iy0 = yf.astype(np.intp)
    iy0 %= fy
    iy1 = iy0 + 1
    iy1[iy1 == fy] = 0
    gx = GX.ravel()
    gy = GY.ravel()
    r0 = iy0 * fx
    r1 = iy1 * fx
    i00 = r0 + ix0
    i10 = r0 + ix1
    i01 = r1 + ix0
    i11 = r1 + ix1
    txm = tx - f32(1)
    tym = ty - f32(1)
    n00 = gx[i00]
    n00 *= tx
    n00 += gy[i00] * ty
    n10 = gx[i10]
    n10 *= txm
    n10 += gy[i10] * ty
    n01 = gx[i01]
    n01 *= tx
    n01 += gy[i01] * tym
    n11 = gx[i11]
    n11 *= txm
    n11 += gy[i11] * tym
    sx = fade(tx)
    sy = fade(ty)
    n10 -= n00
    n10 *= sx
    n10 += n00
    n11 -= n01
    n11 *= sx
    n11 += n01
    n11 -= n10
    n11 *= sy
    n11 += n10
    n11 *= f32(1.4142)
    return n11


def _perlin_regular(t, fx, fy, GX, GY):
    ix0, ix1, tx = _axis(t, fx)
    iy0, iy1, ty = _axis(t, fy)
    sx = fade(tx)[None, :]
    sy = fade(ty)[:, None]
    txr = tx[None, :]
    tyc = ty[:, None]
    txm = (tx - f32(1))[None, :]
    tym = (ty - f32(1))[:, None]

    def g(G, iy, ix):
        return G[iy][:, ix]          # row gather then column gather: ~4x faster than take()

    n00 = g(GX, iy0, ix0)
    n00 *= txr
    n00 += g(GY, iy0, ix0) * tyc
    n10 = g(GX, iy0, ix1)
    n10 *= txm
    n10 += g(GY, iy0, ix1) * tyc
    n01 = g(GX, iy1, ix0)
    n01 *= txr
    n01 += g(GY, iy1, ix0) * tym
    n11 = g(GX, iy1, ix1)
    n11 *= txm
    n11 += g(GY, iy1, ix1) * tym
    n10 -= n00
    n10 *= sx
    n10 += n00
    n11 -= n01
    n11 *= sx
    n11 += n01
    n11 -= n10
    n11 *= sy
    n11 += n10
    n11 *= f32(1.4142)
    return n11


def value(u, v, fx, fy=None, seed=0):
    """Value noise (smooth interpolation of random lattice values). Range [-1, 1]."""
    fx = int(fx)
    fy = fx if fy is None else int(fy)
    r = rng_for(seed, fx, fy, 2)
    T = r.random((fy, fx), dtype=f32) * f32(2) - f32(1)
    t1 = _regular(u, v)
    if t1 is not None:
        ix0, ix1, tx = _axis(t1, fx)
        iy0, iy1, ty = _axis(t1, fy)
        sx = fade(tx)[None, :]
        sy = fade(ty)[:, None]
        a = T[iy0][:, ix0]
        b = T[iy0][:, ix1]
        b -= a
        b *= sx
        b += a
        c = T[iy1][:, ix0]
        d = T[iy1][:, ix1]
        d -= c
        d *= sx
        d += c
        d -= b
        d *= sy
        d += b
        return d
    tab = T.ravel()
    x = u * f32(fx)
    y = v * f32(fy)
    xf = np.floor(x)
    yf = np.floor(y)
    ix0 = xf.astype(np.intp)
    ix0 %= fx
    ix1 = ix0 + 1
    ix1[ix1 == fx] = 0
    iy0 = yf.astype(np.intp)
    iy0 %= fy
    iy1 = iy0 + 1
    iy1[iy1 == fy] = 0
    sx = fade(x - xf)
    sy = fade(y - yf)
    r0 = iy0 * fx
    r1 = iy1 * fx
    a = tab[r0 + ix0]
    b = tab[r0 + ix1]
    b -= a
    b *= sx
    b += a
    c = tab[r1 + ix0]
    d = tab[r1 + ix1]
    d -= c
    d *= sx
    d += c
    d -= b
    d *= sy
    d += b
    return d


def fbm(u, v, f=4, octaves=5, lacunarity=2.0, gain=0.5, seed=0, fy=None, kind="perlin",
        rot=True):
    """Fractal Brownian motion. kind: perlin | value | ridged | billow.
    perlin/value -> signed ~[-1,1]; ridged/billow -> [0,1].  fy gives anisotropic frequency.
    Octaves 1 (and 3 for 6+ octaves) use the 45-degree rotated lattice to hide axis alignment."""
    tot = None
    amp = 1.0
    norm = 0.0
    ridge_w = None
    rot_octaves = (1, 3) if octaves >= 6 else (1,)
    for o in range(octaves):
        fo = max(1, int(round(f * lacunarity ** o)))
        foy = None if fy is None else max(1, int(round(fy * lacunarity ** o)))
        s = seed * 131 + o * 17
        r45 = bool(rot and (o in rot_octaves) and foy is None)
        if kind == "value":
            n = value(u, v, fo, foy, s)
        else:
            n = perlin(u, v, fo, foy, s, rot45=r45)
        if kind == "ridged":
            np.abs(n, out=n)
            np.subtract(f32(1), n, out=n)
            n *= n
            if ridge_w is not None:
                n *= (f32(0.35) + f32(0.65) * ridge_w)
            ridge_w = np.clip(n, 0, 1)
        elif kind == "billow":
            np.abs(n, out=n)
        n *= f32(amp)
        if tot is None:
            tot = n
        else:
            tot += n
        norm += amp
        amp *= gain
    tot /= f32(norm)
    return tot


def ridged(u, v, f=4, octaves=5, seed=0, **kw):
    return fbm(u, v, f, octaves, seed=seed, kind="ridged", **kw)


def warp(u, v, amp=0.05, f=3, seed=0, octaves=3):
    """Domain warp: returns (u', v') displaced by fbm noise; amp in turns."""
    wx = fbm(u, v, f, octaves, seed=seed * 3 + 1)
    wy = fbm(u, v, f, octaves, seed=seed * 3 + 2)
    return u + wx * f32(amp), v + wy * f32(amp)


class Worley:
    """Cellular noise result: f1, f2 distances (cell units), rid (random id of nearest cell),
    vx, vy (vector from pixel to nearest feature point, cell units), cid (int cell index)."""
    __slots__ = ("f1", "f2", "rid", "vx", "vy", "cid")


def worley(u, v, fx, fy=None, seed=0, jitter=1.0):
    fx = int(fx)
    fy = fx if fy is None else int(fy)
    r = rng_for(seed, fx, fy, 3)
    px = (r.random((fy, fx), dtype=f32) - f32(0.5)) * f32(jitter) + f32(0.5)
    py = (r.random((fy, fx), dtype=f32) - f32(0.5)) * f32(jitter) + f32(0.5)
    rid = r.random((fy, fx), dtype=f32)
    t1 = _regular(u, v)
    w = Worley()
    if t1 is not None:
        _worley_regular(w, t1, fx, fy, px, py, rid)
        return w
    pxf, pyf, ridf = px.ravel(), py.ravel(), rid.ravel()
    x = u * f32(fx)
    y = v * f32(fy)
    ix = np.floor(x)
    iy = np.floor(y)
    tx = x - ix
    ty = y - iy
    ixi = ix.astype(np.intp)
    iyi = iy.astype(np.intp)
    big = f32(1e9)
    d1 = np.full(x.shape, big, f32)
    d2 = np.full(x.shape, big, f32)
    best_id = np.zeros(x.shape, np.intp)
    bvx = np.zeros(x.shape, f32)
    bvy = np.zeros(x.shape, f32)
    for oy in (-1, 0, 1):
        cy = (iyi + oy) % fy
        for ox in (-1, 0, 1):
            cx = (ixi + ox) % fx
            idx = cy * fx + cx
            dx = pxf[idx]
            dx += f32(ox)
            dx -= tx
            dy = pyf[idx]
            dy += f32(oy)
            dy -= ty
            d = dx * dx
            d += dy * dy
            closer = d < d1
            d2 = np.where(closer, d1, np.minimum(d2, d))
            d1 = np.where(closer, d, d1)
            best_id = np.where(closer, idx, best_id)
            bvx = np.where(closer, dx, bvx)
            bvy = np.where(closer, dy, bvy)
    w.f1 = np.sqrt(d1)
    w.f2 = np.sqrt(d2)
    w.rid = ridf[best_id]
    w.vx = bvx
    w.vy = bvy
    w.cid = best_id
    return w


def _worley_regular(w, t, fx, fy, px, py, rid):
    N = len(t)
    x = t * f32(fx)
    y = t * f32(fy)
    ixf = np.floor(x)
    iyf = np.floor(y)
    tx = (x - ixf)[None, :]
    ty = (y - iyf)[:, None]
    ix = ixf.astype(np.intp)
    iy = iyf.astype(np.intp)
    d1 = np.full((N, N), 1e9, f32)
    d2 = np.full((N, N), 1e9, f32)
    kbest = np.zeros((N, N), np.int8)
    dx = np.empty((N, N), f32)
    dy = np.empty((N, N), f32)
    d = np.empty((N, N), f32)
    tmp = np.empty((N, N), f32)
    closer = np.empty((N, N), bool)
    offs = []
    k = 0
    for oy in (-1, 0, 1):
        cy = (iy + oy) % fy
        pxr = px[cy]
        pyr = py[cy]
        for ox in (-1, 0, 1):
            cx = (ix + ox) % fx
            np.add(pxr[:, cx], f32(ox), out=dx)
            dx -= tx
            np.add(pyr[:, cx], f32(oy), out=dy)
            dy -= ty
            np.multiply(dx, dx, out=d)
            np.multiply(dy, dy, out=tmp)
            d += tmp
            np.less(d, d1, out=closer)
            np.maximum(d1, d, out=tmp)
            np.minimum(d2, tmp, out=d2)
            np.minimum(d1, d, out=d1)
            np.copyto(kbest, np.int8(k), where=closer)
            offs.append((ox, oy))
            k += 1
    offs = np.array(offs, np.intp)
    ox_k = offs[:, 0][kbest]
    oy_k = offs[:, 1][kbest]
    idx = ((iy[:, None] + oy_k) % fy) * fx + ((ix[None, :] + ox_k) % fx)
    pxo = px.ravel()[idx]
    pyo = py.ravel()[idx]
    w.f1 = np.sqrt(d1)
    w.f2 = np.sqrt(d2)
    w.rid = rid.ravel()[idx]
    w.vx = (pxo + ox_k.astype(f32)) - tx
    w.vy = (pyo + oy_k.astype(f32)) - ty
    w.cid = idx


def worley_fbm(u, v, f=4, octaves=3, seed=0, gain=0.5, invert=True):
    """Sum of F1 worley octaves, [0,1] (inverted => bright blobs)."""
    tot = 0
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        w = worley(u, v, f * 2 ** o, seed=seed * 7 + o)
        d = np.clip(w.f1, 0, 1)
        if invert:
            d = f32(1) - d
        tot = tot + d * f32(amp)
        norm += amp
        amp *= gain
    return tot / f32(norm)


def cracks(u, v, f=6, seed=0, width=0.06, jitter=1.0, fy=None, wobble=0.0):
    """Voronoi crack network. Returns (crack_mask 0..1, cell_random_id, edge_distance)."""
    if wobble:
        u, v = warp(u, v, wobble, f=max(2, f // 2), seed=seed + 11, octaves=3)
    w = worley(u, v, f, fy, seed, jitter)
    e = w.f2 - w.f1
    m = f32(1) - np.clip(e / f32(width), 0, 1)
    return m * m * (f32(3) - f32(2) * m), w.rid, e


# --------------------------------------------------------------------------------------
# FFT based tools (periodic by construction)
# --------------------------------------------------------------------------------------
_TF_CACHE: dict = {}


def _gauss_tf(h, w, sx, sy):
    key = (h, w, round(sx, 3), round(sy, 3))
    tf = _TF_CACHE.get(key)
    if tf is None:
        fy = np.fft.fftfreq(h).astype(f32)
        fx = np.fft.rfftfreq(w).astype(f32)
        tf = np.exp(-2.0 * np.pi ** 2 * ((sy * fy[:, None]) ** 2 + (sx * fx[None, :]) ** 2)).astype(f32)
        if len(_TF_CACHE) > 24:
            _TF_CACHE.clear()
        _TF_CACHE[key] = tf
    return tf


def blur(a, sx, sy=None):
    """Periodic gaussian blur (FFT). sx, sy are sigmas in pixels."""
    sy = sx if sy is None else sy
    a = np.asarray(a, f32)
    if sx <= 0.05 and sy <= 0.05:
        return a
    if a.ndim == 3:
        return np.stack([blur(a[..., c], sx, sy) for c in range(a.shape[2])], -1)
    h, w = a.shape
    tf = _gauss_tf(h, w, float(sx), float(sy))
    return np.fft.irfft2(np.fft.rfft2(a) * tf, s=(h, w)).astype(f32)


def spectral(n, slope=2.0, seed=0, kmin=1.0, kmax=None, ax=1.0, ay=1.0, angle=0.0):
    """FFT-synthesised periodic noise with power spectrum ~ k^-slope, unit variance.
    The effective wave number is k_eff = sqrt((kx*ax)^2 + (ky*ay)^2); a larger ay (or smaller ax)
    removes high-ky power, i.e. features get elongated along V.  angle rotates the axes (radians)."""
    r = rng_for(seed, n, 5)
    shape = (n, n // 2 + 1)
    spec = (r.standard_normal(shape, dtype=f32) + 1j * r.standard_normal(shape, dtype=f32)).astype(np.complex64)
    ky = (np.fft.fftfreq(n) * n).astype(f32)[:, None]
    kx = (np.fft.rfftfreq(n) * n).astype(f32)[None, :]
    if angle:
        c, s = np.cos(angle), np.sin(angle)
        kx2 = kx * c + ky * s
        ky2 = -kx * s + ky * c
    else:
        kx2, ky2 = kx, ky
    k = np.sqrt((kx2 * ax) ** 2 + (ky2 * ay) ** 2)
    k = np.maximum(k, f32(1e-3))
    amp = k ** f32(-slope / 2.0)
    amp[k < kmin] = 0
    if kmax is not None:
        amp[k > kmax] = 0
    amp[0, 0] = 0
    out = np.fft.irfft2(spec * amp, s=(n, n)).astype(f32)
    out -= out.mean()
    out /= (out.std() + f32(1e-9))
    return out


def equalize(x):
    """Histogram-equalise to a uniform [0,1] distribution (rank transform)."""
    flat = x.ravel()
    order = np.argsort(flat, kind="stable")
    out = np.empty(flat.shape, f32)
    out[order] = np.linspace(0, 1, flat.size, dtype=f32)
    return out.reshape(x.shape)


def norm01(x, lo=1.0, hi=99.0):
    """Robust normalisation to [0,1] using percentiles of a subsample."""
    s = x.ravel()[::7]
    a, b = np.percentile(s, [lo, hi])
    return np.clip((x - a) / max(float(b - a), 1e-9), 0, 1).astype(f32)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (f32(3) - f32(2) * t)


def blue_noise(n, seed=0, iterations=14, sigma=1.5):
    """Approximate tileable blue noise (uniform histogram) via iterated spectral shaping:
    keep the phase of the current image, push the magnitude towards a blue (high-pass) target
    spectrum, rank-equalise; repeated.  Low frequencies end up ~500x weaker than white noise."""
    r = rng_for(seed, n, 9)
    x = equalize(r.random((n, n), dtype=f32))
    ky = np.fft.fftfreq(n).astype(f32)[:, None]
    kx = np.fft.rfftfreq(n).astype(f32)[None, :]
    k = np.sqrt(kx * kx + ky * ky)
    kc = 0.5 / sigma / 1.8
    shape = (1.0 - np.exp(-(k / kc) ** 2)).astype(f32)
    shape = shape * np.exp(-(k / 0.62) ** 4).astype(f32)
    for i in range(iterations):
        spec = np.fft.rfft2(x - 0.5)
        mag = np.abs(spec) + f32(1e-9)
        blend = 0.35 if i < iterations - 1 else 1.0
        mixed = spec / mag * (mag * (1 - blend) + shape * mag.mean() * blend)
        y = np.fft.irfft2(mixed, s=(n, n)).astype(f32)
        x = equalize(y)
    return x
