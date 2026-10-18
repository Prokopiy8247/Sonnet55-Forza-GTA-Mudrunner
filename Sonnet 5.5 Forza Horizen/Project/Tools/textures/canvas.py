"""Painter's-algorithm canvas: stamps anti-aliased primitives (blades, ovals, polygons ...)
into a tileable set of maps (colour, height, roughness, metal, optional alpha) with wrap-around,
so scattered objects (pebbles, leaves, needles, grass blades, petals) tile seamlessly."""
from __future__ import annotations

import math

import numpy as np

from .noise import f32


class Canvas:
    def __init__(self, n, color=(0.1, 0.1, 0.1), h=0.0, rough=0.8, metal=0.0, alpha=None):
        self.n = n
        self.c = np.empty((n, n, 3), f32)
        self.c[:] = np.asarray(color, f32)
        self.h = np.full((n, n), h, f32)
        self.r = np.full((n, n), rough, f32)
        self.m = np.full((n, n), metal, f32)
        self.a = None if alpha is None else np.full((n, n), alpha, f32)
        self.wrap = True
        self.clip = None          # (x0, y0, x1, y1) rectangle used when wrap is False

    # ------------------------------------------------------------------ low level
    def window(self, xmin, xmax, ymin, ymax):
        x0 = int(math.floor(xmin))
        y0 = int(math.floor(ymin))
        w = int(math.ceil(xmax)) - x0 + 1
        h = int(math.ceil(ymax)) - y0 + 1
        w = min(w, self.n)
        h = min(h, self.n)
        X = (x0 + 0.5 + np.arange(w, dtype=f32))[None, :]
        Y = (y0 + 0.5 + np.arange(h, dtype=f32))[:, None]
        return x0, y0, X, Y

    def _idx(self, x0, y0, w, h):
        n = self.n
        if self.wrap:
            ys = (np.arange(y0, y0 + h) % n)[:, None]
            xs = (np.arange(x0, x0 + w) % n)[None, :]
        else:
            ys = np.arange(max(y0, 0), min(y0 + h, n))[:, None]
            xs = np.arange(max(x0, 0), min(x0 + w, n))[None, :]
        return ys, xs

    def paint(self, x0, y0, m, col=None, h=None, rough=None, metal=None, hmode="over"):
        ph, pw = m.shape
        if self.wrap:
            ys, xs = self._idx(x0, y0, pw, ph)
            sub = None
        else:
            cx0, cy0, cx1, cy1 = self.clip if self.clip else (0, 0, self.n, self.n)
            ya, yb = max(y0, cy0), min(y0 + ph, cy1)
            xa, xb = max(x0, cx0), min(x0 + pw, cx1)
            if ya >= yb or xa >= xb:
                return
            sub = (slice(ya - y0, yb - y0), slice(xa - x0, xb - x0))
            ys = np.arange(ya, yb)[:, None]
            xs = np.arange(xa, xb)[None, :]
            m = m[sub]
        def cut(a):
            if sub is None or a is None:
                return a
            a = np.asarray(a)
            return a[sub] if a.ndim >= 2 else a
        if self.a is not None:
            old_a = self.a[ys, xs]
            new_a = old_a + m * (1 - old_a)
        if col is not None:
            col = cut(np.asarray(col, f32))
            old = self.c[ys, xs]
            if self.a is None:
                self.c[ys, xs] = old + (col - old) * m[..., None]
            else:
                # straight-alpha "over": weight by new coverage
                wnew = (m / np.maximum(new_a, 1e-6))[..., None]
                self.c[ys, xs] = old + (col - old) * wnew
        if h is not None:
            h = cut(np.asarray(h, f32))
            old = self.h[ys, xs]
            if hmode == "max":
                self.h[ys, xs] = old + (np.maximum(h, old) - old) * m
            else:
                self.h[ys, xs] = old + (h - old) * m
        if rough is not None:
            rough = cut(np.asarray(rough, f32))
            old = self.r[ys, xs]
            self.r[ys, xs] = old + (rough - old) * m
        if metal is not None:
            metal = cut(np.asarray(metal, f32))
            old = self.m[ys, xs]
            self.m[ys, xs] = old + (metal - old) * m
        if self.a is not None:
            self.a[ys, xs] = new_a

    # ------------------------------------------------------------------ primitives
    def blade(self, x, y, ang, length, w0, w1=0.0, bend=0.0, col0=None, col1=None,
              h0=None, h1=None, hround=0.0, rough=None, metal=None, wprof=None,
              colfn=None, hfn=None, aa=1.0, alpha_mul=1.0, hmode="over"):
        """Tapered, optionally bent strip starting at (x, y) pointing along `ang` (radians,
        0 = +x, pi/2 = +y/down).  w0/w1 are half-widths at base / tip (px); `wprof(t)` (0..1) may
        override the width profile as a multiplier of w0.  `bend` is the lateral offset (px) of
        the tip (quadratic curve).  Colours are linear RGB tuples."""
        ca, sa = math.cos(ang), math.sin(ang)
        wm = max(w0, w1) + 2.0
        pts = [(x + ca * length * t - sa * bend * t * t, y + sa * length * t + ca * bend * t * t)
               for t in (0.0, 0.25, 0.5, 0.75, 1.0)]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        x0, y0, X, Y = self.window(min(xs) - wm, max(xs) + wm, min(ys) - wm, max(ys) + wm)
        dx = X - x
        dy = Y - y
        along = dx * ca + dy * sa
        across = -dx * sa + dy * ca
        t = along / f32(length)
        tc = np.clip(t, 0, 1)
        lat = across - f32(bend) * tc * tc
        if wprof is not None:
            hw = f32(w0) * wprof(tc)
        else:
            hw = f32(w0) + f32(w1 - w0) * tc
        d = np.abs(lat) - hw
        m = np.clip(f32(0.5) - d / f32(aa), 0, 1)
        m = m * np.clip(along / f32(aa) + f32(0.5), 0, 1) * np.clip((f32(length) - along) / f32(aa) + f32(0.5), 0, 1)
        if alpha_mul != 1.0:
            m = m * f32(alpha_mul)
        sn = np.clip(lat / np.maximum(hw, f32(1e-3)), -1, 1)
        col = None
        if colfn is not None:
            col = colfn(tc, sn)
        elif col0 is not None:
            c0 = np.asarray(col0, f32)
            if col1 is None:
                col = c0
            else:
                col = c0 + (np.asarray(col1, f32) - c0) * tc[..., None]
        hv = None
        if hfn is not None:
            hv = hfn(tc, sn)
        elif h0 is not None:
            hv = f32(h0) + f32((h1 if h1 is not None else h0) - h0) * tc + f32(hround) * np.sqrt(np.maximum(1 - sn * sn, 0))
        self.paint(x0, y0, m, col, hv, rough, metal, hmode)

    def oval(self, cx, cy, rx, ry, ang=0.0, col=None, h0=0.0, hdome=0.0, rough=None, metal=None,
             irr=0.0, rng=None, aa=1.0, edge_dark=0.0, shade=None, colfn=None, hpow=0.5, hmode="over"):
        """Irregular ellipse with dome height profile (pebbles, clods, spots)."""
        R = max(rx, ry) * (1.0 + irr) + 2.0
        x0, y0, X, Y = self.window(cx - R, cx + R, cy - R, cy + R)
        ca, sa = math.cos(ang), math.sin(ang)
        dx = X - cx
        dy = Y - cy
        a = (dx * ca + dy * sa) / f32(rx)
        b = (-dx * sa + dy * ca) / f32(ry)
        r = np.sqrt(a * a + b * b)
        if irr > 0.0:
            rng = rng or np.random.default_rng(1)
            th = np.arctan2(b, a)
            ph = rng.random(3) * 6.2831853
            rr = (1.0 + irr * (0.55 * np.sin(2 * th + ph[0]) + 0.3 * np.sin(3 * th + ph[1])
                               + 0.25 * np.sin(5 * th + ph[2]))).astype(f32)
        else:
            rr = f32(1.0)
        d = (r - rr) * f32(min(rx, ry))
        m = np.clip(f32(0.5) - d / f32(aa), 0, 1)
        q = np.clip(r / rr, 0, 1)
        dome = np.power(np.maximum(1 - q * q, 0), f32(hpow))
        col_p = None
        if colfn is not None:
            col_p = colfn(q, a, b)
        elif col is not None:
            col_p = np.asarray(col, f32)
            if edge_dark or shade is not None:
                k = 1.0 - edge_dark * q * q
                if shade is not None:
                    # simple directional shading: light from upper-left
                    sh = np.clip((-(a * 0.6 + b * 0.6) / np.maximum(r, 1e-3)) * (q * q), -1, 1) * shade
                    k = k + sh
                col_p = col_p * k[..., None]
        hv = None
        if h0 is not None:
            hv = f32(h0) + f32(hdome) * dome
        self.paint(x0, y0, m, col_p, hv, rough, metal, hmode)

    def poly_mask(self, pts, aa=1.0):
        """Anti-aliased filled convex/concave polygon via winding of signed edge distances
        (even-odd with distance AA). pts: list of (x, y). Returns (x0, y0, mask, sd)."""
        P = np.array(pts, f32)
        x0, y0, X, Y = self.window(P[:, 0].min() - 2, P[:, 0].max() + 2, P[:, 1].min() - 2, P[:, 1].max() + 2)
        H, W = Y.shape[0], X.shape[1]
        inside = np.zeros((H, W), bool)
        dmin = np.full((H, W), 1e9, f32)
        k = len(P)
        for i in range(k):
            a = P[i]
            b = P[(i + 1) % k]
            ex, ey = b[0] - a[0], b[1] - a[1]
            px = X - a[0]
            py = Y - a[1]
            tt = np.clip((px * ex + py * ey) / max(ex * ex + ey * ey, 1e-9), 0, 1)
            dd = np.hypot(px - ex * tt, py - ey * tt)
            dmin = np.minimum(dmin, dd)
            cond = ((a[1] <= Y) != (b[1] <= Y)) & (X < (b[0] - a[0]) * (Y - a[1]) / (b[1] - a[1] + 1e-12) + a[0])
            inside ^= cond
        sd = np.where(inside, -dmin, dmin)
        return x0, y0, np.clip(f32(0.5) - sd / f32(aa), 0, 1), sd

    def polygon(self, pts, col=None, h=None, rough=None, metal=None, aa=1.0):
        x0, y0, m, sd = self.poly_mask(pts, aa)
        self.paint(x0, y0, m, col, h, rough, metal)

    # ------------------------------------------------------------------ results
    def albedo(self):
        return self.c


def tile_check_stamp_ok(n):
    return n > 0
