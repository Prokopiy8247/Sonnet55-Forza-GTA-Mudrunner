"""Recipe registry, per-recipe context and map writer."""
from __future__ import annotations

import os
import time
import zlib

import numpy as np

from . import noise as nz
from . import maps
from .canvas import Canvas
from .noise import f32
from .png import write_png

REGISTRY: dict = {}


def recipe(name, tile_m, usage, category, size_mult=1, albedo=None, tileable=True,
           notes="", non_uniform=None):
    """Register a texture recipe.

    tile_m   : real-world size in metres of ONE tile (float, or [width, height]).
    albedo   : (lo, hi) plausible range for mean linear albedo luminance (checked by verify).
    size_mult: 2 for the 2048 hero textures / atlases when base size is 1024.
    """
    def deco(fn):
        REGISTRY[name] = dict(fn=fn, name=name, tile_m=tile_m, usage=usage, category=category,
                              size_mult=size_mult, albedo=albedo, tileable=tileable, notes=notes)
        return fn
    return deco


class Ctx:
    """Everything a recipe needs: size, deterministic seeds, bound noise helpers."""

    def __init__(self, name, n):
        self.name = name
        self.n = n
        self.seed = zlib.crc32(name.encode()) & 0x7FFFFFFF
        self.rng = nz.rng_for(self.seed, 99)
        self.u, self.v = nz.make_grid(n)
        self._k = 0
        self.s = n / 1024.0       # pixel scale relative to 1024

    # --- seeds / rngs
    def sd(self):
        self._k += 1
        return (self.seed % 99991) + self._k * 13

    def rng_k(self, tag=0):
        self._k += 1
        return nz.rng_for(self.seed, 1000 + self._k, tag)

    def px(self, v):
        """Convert pixels-at-1024 to pixels at the current size."""
        return v * self.s

    # --- noise bound to the ctx grid
    def perlin(self, f, fy=None, uv=None, rot45=False):
        u, v = uv or (self.u, self.v)
        return nz.perlin(u, v, f, fy, self.sd(), rot45)

    def value(self, f, fy=None, uv=None):
        u, v = uv or (self.u, self.v)
        return nz.value(u, v, f, fy, self.sd())

    def fbm(self, f=4, octaves=5, kind="perlin", fy=None, uv=None, gain=0.5, lacunarity=2.0):
        u, v = uv or (self.u, self.v)
        return nz.fbm(u, v, f, octaves, lacunarity, gain, self.sd(), fy, kind)

    def fbm01(self, f=4, octaves=5, kind="perlin", fy=None, uv=None, gain=0.5, lo=1, hi=99):
        return nz.norm01(self.fbm(f, octaves, kind, fy, uv, gain), lo, hi)

    def ridged(self, f=4, octaves=5, fy=None, uv=None):
        return self.fbm(f, octaves, "ridged", fy, uv)

    def worley(self, fx, fy=None, jitter=1.0, uv=None):
        u, v = uv or (self.u, self.v)
        return nz.worley(u, v, fx, fy, self.sd(), jitter)

    def warp(self, amp=0.05, f=3, octaves=3):
        return nz.warp(self.u, self.v, amp, f, self.sd(), octaves)

    def cracks(self, f=6, width=0.06, jitter=1.0, fy=None, wobble=0.0, uv=None):
        u, v = uv or (self.u, self.v)
        if wobble:
            u, v = nz.warp(u, v, wobble, max(2, f // 2), self.sd(), 3)
        w = nz.worley(u, v, f, fy, self.sd(), jitter)
        e = w.f2 - w.f1
        m = f32(1) - np.clip(e / f32(width), 0, 1)
        return m * m * (f32(3) - f32(2) * m), w.rid, e

    def spectral(self, slope=2.0, kmin=1.0, kmax=None, ax=1.0, ay=1.0, angle=0.0):
        return nz.spectral(self.n, slope, self.sd(), kmin, kmax, ax, ay, angle)

    def blur(self, a, sigma_1024, sy_1024=None):
        sy = sigma_1024 if sy_1024 is None else sy_1024
        return nz.blur(a, sigma_1024 * self.s, sy * self.s)

    def canvas(self, **kw):
        return Canvas(self.n, **kw)

    def grain(self, strength=1.0, f=None):
        """Per-pixel white noise (zero mean, unit variance-ish) for fine speckle."""
        return (self.rng.standard_normal((self.n, self.n), dtype=f32) * f32(strength))


# --------------------------------------------------------------------------- file writing
def _tpdf(rng, shape):
    return (rng.random(shape, dtype=f32) + rng.random(shape, dtype=f32) - f32(1.0))


def to_u8(x, rng, dither=True):
    x = np.nan_to_num(np.asarray(x, f32), nan=0.0, posinf=1.0, neginf=0.0) * f32(255.0)
    if dither:
        x = x + _tpdf(rng, x.shape) * f32(0.75)
    return np.clip(np.rint(x), 0, 255).astype(np.uint8)


def to_u16(x):
    x = np.nan_to_num(np.asarray(x, f32), nan=0.0, posinf=1.0, neginf=0.0)
    return np.clip(np.rint(x * f32(65535.0)), 0, 65535).astype(np.uint16)


def emit(ctx: Ctx, res: dict, out_root: str) -> dict:
    """Write all maps of one recipe, return its manifest entry."""
    name = ctx.name
    n = ctx.n
    d = os.path.join(out_root, name)
    os.makedirs(d, exist_ok=True)
    rng = nz.rng_for(ctx.seed, 4242)
    files = {}
    skip = set(res.get("skip", ()))
    text = {"Software": "Roamline procedural texture generator", "Source": name}

    def put(suffix, arr, srgb, kind, chans):
        path = os.path.join(d, "%s_%s.png" % (name, suffix))
        size = write_png(path, arr, text=text)
        files[suffix] = dict(file="%s/%s_%s.png" % (name, name, suffix), srgb=srgb,
                             bits=16 if arr.dtype == np.uint16 else 8, channels=chans,
                             role=kind, bytes=size)

    stats = {}
    alb = res.get("albedo")
    alpha = res.get("alpha")
    if alb is not None and "BC" not in skip:
        a = np.clip(alb, 0, 1)
        s = maps.lin_to_srgb(a)
        u8 = to_u8(s, rng)
        if alpha is not None:
            u8 = np.concatenate([u8, to_u8(alpha, rng, dither=False)[..., None]], -1)
            put("BC", u8, True, "base_colour_alpha", "RGBA")
        else:
            put("BC", u8, True, "base_colour", "RGB")
        lum = maps.luminance(a)
        sel = (alpha > 0.5) if alpha is not None and (alpha > 0.5).any() else np.ones(lum.shape, bool)
        stats["albedo_mean_linear"] = round(float(lum[sel].mean()), 4)
        stats["albedo_p5_p95_linear"] = [round(float(np.percentile(lum[sel][::5], 5)), 4),
                                         round(float(np.percentile(lum[sel][::5], 95)), 4)]
        stats["albedo_mean_srgb_rgb"] = [int(round(float(x))) for x in
                                         (maps.lin_to_srgb(a[sel].reshape(-1, 3)[::7].mean(0)) * 255)]
    h = res.get("height")
    nm = res.get("normal")
    if nm is None and h is not None:
        if res.get("slope") is not None:
            nm, k_eff = maps.normal_from_height_auto(h, res["slope"])
            res["nstr"] = round(float(k_eff), 2)
            stats["median_slope"] = res["slope"]
        else:
            nm = maps.normal_from_height(h, res.get("nstr", 4.0))
    if nm is not None and "N" not in skip:
        put("N", to_u8(nm, rng), False, "normal_directx_green_down", "RGB")
    if "ORM" not in skip and (h is not None or res.get("ao") is not None or res.get("rough") is not None):
        ao = res.get("ao")
        if ao is None:
            ao = maps.cavity_ao(h, gain=res.get("ao_gain", 3.0)) if h is not None else np.ones((n, n), f32)
        rough = np.broadcast_to(np.asarray(res.get("rough", 0.8), f32), (n, n))
        metal = np.broadcast_to(np.asarray(res.get("metal", 0.0), f32), (n, n))
        orm = np.stack([ao, rough, metal], -1)
        put("ORM", to_u8(orm, rng), False, "R=AO G=Roughness B=Metallic", "RGB")
        stats["rough_mean"] = round(float(rough.mean()), 3)
    if h is not None and res.get("write_h", True) and "H" not in skip:
        put("H", to_u16(h), False, "height_16bit", "L")
    for suffix, spec in res.get("files", {}).items():
        arr = spec["arr"]
        bits = spec.get("bits", 8)
        if arr.dtype in (np.uint8, np.uint16):
            out = arr
        elif bits == 16:
            out = to_u16(arr)
        else:
            out = to_u8(arr, rng, dither=spec.get("dither", False))
        chans = "L" if out.ndim == 2 else {1: "L", 2: "LA", 3: "RGB", 4: "RGBA"}[out.shape[2]]
        put(suffix, out, spec.get("srgb", False), spec.get("role", "data"), chans)
    entry = dict(
        name=name, category=ctx.meta["category"], size=[n, n], files=files,
        tile_metres=ctx.meta["tile_m"], usage=ctx.meta["usage"], tileable=ctx.meta["tileable"],
        normal_strength=res.get("nstr"), **stats)
    if ctx.meta.get("notes"):
        entry["notes"] = ctx.meta["notes"]
    for k, v in res.get("meta", {}).items():
        entry[k] = v
    return entry


def run_recipe(name: str, base_size: int, out_root: str):
    """Execute one recipe -> manifest entry (also returns timing)."""
    meta = REGISTRY[name]
    t0 = time.time()
    n = base_size * meta["size_mult"]
    ctx = Ctx(name, n)
    ctx.meta = meta
    res = meta["fn"](ctx)
    entry = emit(ctx, res, out_root)
    entry["gen_seconds"] = round(time.time() - t0, 2)
    return entry
