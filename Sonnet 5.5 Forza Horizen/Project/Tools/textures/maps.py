"""Colour helpers, height->normal, cavity AO, lit preview."""
from __future__ import annotations

import numpy as np

from .noise import blur, f32

# ---------------------------------------------------------------------------------- colour


def srgb_to_lin(c):
    c = np.asarray(c, f32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4).astype(f32)


def lin_to_srgb(c):
    c = np.clip(np.asarray(c, f32), 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055).astype(f32)


def hexc(s: str):
    """'#rrggbb' (sRGB) -> linear float32 (3,)."""
    s = s.lstrip("#")
    rgb = np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], f32) / 255.0
    return srgb_to_lin(rgb)


def lin(r, g, b):
    return np.array([r, g, b], f32)


def luminance(a):
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def lerp(a, b, t):
    """Blend arrays; t has shape (H,W) (broadcasts against colour (H,W,3) or (3,))."""
    a = np.asarray(a, f32)
    b = np.asarray(b, f32)
    t = np.asarray(t, f32)
    if t.ndim == 2:
        colour = (a.ndim >= 3 or b.ndim >= 3 or (a.ndim == 1 and a.shape[0] == 3)
                  or (b.ndim == 1 and b.shape[0] == 3))
        if colour:
            t = t[..., None]
    return a + (b - a) * t


def ramp(t, stops):
    """Piecewise-linear colour ramp. stops = [(pos, colour(3,)), ...] -> (...,3)."""
    pos = np.array([p for p, _ in stops], f32)
    cols = np.array([c for _, c in stops], f32)
    t = np.asarray(t, f32)
    return np.stack([np.interp(t, pos, cols[:, k]) for k in range(3)], -1).astype(f32)


def mulc(img, k):
    """Multiply colour image by scalar field k (H,W) or scalar."""
    k = np.asarray(k, f32)
    if k.ndim == 2:
        k = k[..., None]
    return img * k


def hsv_shift(img, dv=0.0, ds=0.0):
    """Cheap value / saturation modulation on linear colour (dv, ds scalar or (H,W))."""
    dv = np.asarray(dv, f32)
    ds = np.asarray(ds, f32)
    if dv.ndim == 2:
        dv = dv[..., None]
    if ds.ndim == 2:
        ds = ds[..., None]
    lum = luminance(img)[..., None]
    out = lum + (img - lum) * (1 + ds)
    return np.maximum(out * (1 + dv), 0)


def overlay_soft(base, layer, amount):
    return base * (1 + (layer[..., None] if layer.ndim == 2 else layer) * amount)


# ----------------------------------------------------------------------------- height maps


def sobel(h):
    """Periodic Sobel gradient (slope per pixel): returns dx (+x right), dy (+y down)."""
    h = np.asarray(h, f32)
    ax = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    dx = (np.roll(ax, -1, 0) + 2 * ax + np.roll(ax, 1, 0)) * f32(0.125)
    ay = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    dy = (np.roll(ay, -1, 1) + 2 * ay + np.roll(ay, 1, 1)) * f32(0.125)
    return dx, dy


def _soft_tilt(nx, ny, knee=5.0, mx=8.0):
    """Soft-limit the slope magnitude m = |(nx, ny)| (normal = (nx, ny, 1) / sqrt(1 + m^2)) so that
    no normal tilts beyond atan(mx) ~ 83 degrees (nz >= 0.124); slopes below `knee` are untouched."""
    m = np.sqrt(nx * nx + ny * ny)
    if float(m.max()) <= knee:
        return nx, ny
    mm = np.where(m > knee, knee + (mx - knee) * np.tanh((m - knee) / (mx - knee)), m)
    sc = (mm / np.maximum(m, f32(1e-9))).astype(f32)
    return nx * sc, ny * sc


def normal_from_height(h, strength=4.0):
    """Tangent-space normal map, DirectX / Unreal convention (+X right, +Y = image down = +V),
    so green is DOWN.  Slopes are scaled by n/1024 so a recipe looks the same at any resolution.
    Returns float32 (H,W,3) in [0,1]."""
    n = h.shape[0]
    k = f32(strength * n / 1024.0)
    dx, dy = sobel(h)
    nx, ny = _soft_tilt(-dx * k, -dy * k)
    inv = f32(1.0) / np.sqrt(nx * nx + ny * ny + f32(1.0))
    out = np.stack([nx * inv, ny * inv, inv], -1)
    return out * f32(0.5) + f32(0.5)


def normal_from_height_auto(h, slope=0.3):
    """Like normal_from_height, but the strength is chosen so that the MEDIAN surface slope
    (tan of the tilt angle) equals `slope`.  Robust to the absolute scale / amplitude of the
    height field, so every recipe can state the relief it wants directly.
    Returns (normal float32 (H,W,3) in [0,1], effective strength in normal_from_height units)."""
    dx, dy = sobel(h)
    g = np.sqrt(dx * dx + dy * dy)
    gs = g[::3, ::3]
    med = float(np.median(gs)) + 1e-9
    k = slope / med
    p995 = float(np.percentile(gs, 99.5)) + 1e-9
    k = min(k, 8.0 / p995)          # never tilt normals beyond ~83 degrees (keeps z > 0.12)
    nx, ny = _soft_tilt(-dx * f32(k), -dy * f32(k))
    inv = f32(1.0) / np.sqrt(nx * nx + ny * ny + f32(1.0))
    out = np.stack([nx * inv, ny * inv, inv], -1) * f32(0.5) + f32(0.5)
    return out, k * 1024.0 / h.shape[0]


def decode_normal(nm):
    v = nm * 2 - 1
    return v / np.maximum(np.sqrt((v * v).sum(-1, keepdims=True)), 1e-6)


def combine_normals(n_base, n_detail, k=1.0):
    """Reoriented-ish blend (UDN): add detail xy to base."""
    b = n_base * 2 - 1
    d = n_detail * 2 - 1
    xy = b[..., :2] + d[..., :2] * k
    z = b[..., 2:3]
    v = np.concatenate([xy, z], -1)
    v /= np.maximum(np.sqrt((v * v).sum(-1, keepdims=True)), 1e-6)
    return v * 0.5 + 0.5


def cavity_ao(h, radii=(2.0, 6.0, 18.0), weights=(0.5, 0.35, 0.25), gain=3.0):
    """Ambient occlusion approximation from a height field: depth below blurred height.
    radii are in pixels at 1024 (scaled to the image size). Returns [0,1] (1 = open)."""
    n = h.shape[0]
    s = n / 1024.0
    cav = 0
    for r, w in zip(radii, weights):
        cav = cav + w * np.maximum(blur(h, r * s) - h, 0)
    return np.clip(1.0 - cav * gain, 0, 1).astype(f32)


def height_norm(h, lo=0.0, hi=1.0):
    h = np.asarray(h, f32)
    a, b = float(h.min()), float(h.max())
    return ((h - a) / max(b - a, 1e-9) * (hi - lo) + lo).astype(f32)


# ------------------------------------------------------------------------------- previews


def lit_preview(albedo_lin, normal, orm, light=(-0.55, -0.55, 0.65)):
    """Cheap software lighting of a texture set for visual inspection. Returns sRGB float."""
    N = decode_normal(normal)
    L = np.array(light, f32)
    L /= np.linalg.norm(L)
    ndl = np.clip((N * L).sum(-1), 0, 1)
    H = L + np.array([0, 0, 1], f32)
    H /= np.linalg.norm(H)
    ndh = np.clip((N * H).sum(-1), 0, 1)
    rough = np.clip(orm[..., 1], 0.05, 1)
    ao = orm[..., 0]
    metal = orm[..., 2]
    p = np.clip(2.0 / (rough ** 4) - 2.0, 1.0, 600.0)
    spec = ndh ** p * (p + 8) / 25.0
    diff_col = albedo_lin * (1 - metal[..., None])
    f0 = albedo_lin * metal[..., None] + 0.04 * (1 - metal[..., None])
    col = diff_col * (0.18 * ao[..., None] + 1.15 * (ndl * (0.4 + 0.6 * ao))[..., None])
    col = col + f0 * (spec * ao)[..., None] * 0.9 * ndl[..., None]
    col = col * 1.25
    col = col / (1 + col * 0.5) * 1.5     # gentle shoulder
    return lin_to_srgb(np.clip(col, 0, 1))
