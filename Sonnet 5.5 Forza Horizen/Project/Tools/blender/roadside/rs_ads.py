# -*- coding: utf-8 -*-
"""Roadside kit: three original, generic billboard artworks (geometric layouts rendered with numpy, no external assets).
Written as 2048x1024 PNGs to Exports/Roadside/Textures/ and wired into the billboard preview material (UV 0..1 over the whole face).
Names are fictional (SUNPEAK FUEL, LAKEVIEW INN, ROADSIDE DINER); lettering uses the kit's own stroke font (rs_font.py).
Exec'd into the kit namespace after rs_lib.py / rs_font.py."""
import numpy as np, struct, zlib

AD_DIR = EXPORT_DIR + r"\Textures"
AD_FILES = {'A': 'T_RS_BillboardAd_A.png', 'B': 'T_RS_BillboardAd_B.png', 'C': 'T_RS_BillboardAd_C.png'}
AD_MATERIALS = {'M_RS_BillboardFace': 'A', 'M_RS_BillboardFace_B': 'B', 'M_RS_BillboardFace_C': 'C'}
AD_SIZE = (2048, 1024)

def _hx(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)

class Canvas:
    """unit space: x in [0, 2], y in [0, 1] (y up); rendered with 2x2 supersampling"""
    def __init__(s, W, H, ss=2):
        s.W, s.H, s.ss = W, H, ss
        s.w, s.h = W * ss, H * ss
        s.k = float(H * ss)
        s.a = np.zeros((s.h, s.w, 3), np.float32)

    def fill(s, c):
        s.a[:] = _hx(c)

    def rect(s, x0, y0, x1, y1, c, alpha=1.0):
        px0 = max(0, int(round(x0 * s.k))); px1 = min(s.w, int(round(x1 * s.k)))
        py0 = max(0, int(round(y0 * s.k))); py1 = min(s.h, int(round(y1 * s.k)))
        if px1 <= px0 or py1 <= py0:
            return
        sub = s.a[s.h - py1:s.h - py0, px0:px1]
        sub[:] = sub * (1 - alpha) + _hx(c) * alpha

    def vgrad(s, y0, y1, c0, c1):
        py0 = max(0, int(round(y0 * s.k))); py1 = min(s.h, int(round(y1 * s.k)))
        t = np.linspace(0.0, 1.0, py1 - py0, dtype=np.float32)[:, None, None]
        col = _hx(c0)[None, None, :] * (1 - t) + _hx(c1)[None, None, :] * t
        s.a[s.h - py1:s.h - py0] = np.broadcast_to(col[::-1], (py1 - py0, s.w, 3))

    def poly(s, polys, c, alpha=1.0):
        """even-odd fill of one or more closed polygons given in unit coords"""
        P = [np.array([(x * s.k, y * s.k) for (x, y) in pl], np.float64) for pl in polys]
        allp = np.concatenate(P)
        x0 = max(0, int(np.floor(allp[:, 0].min()))); x1 = min(s.w, int(np.ceil(allp[:, 0].max())) + 1)
        y0 = max(0, int(np.floor(allp[:, 1].min()))); y1 = min(s.h, int(np.ceil(allp[:, 1].max())) + 1)
        if x1 <= x0 or y1 <= y0:
            return
        xs = np.arange(x0, x1)[None, :] + 0.5
        ys = np.arange(y0, y1)[:, None] + 0.5
        inside = np.zeros((y1 - y0, x1 - x0), bool)
        for pts in P:
            n = len(pts)
            for i in range(n):
                xa, ya = pts[i]; xb, yb = pts[(i + 1) % n]
                if ya == yb:
                    continue
                cond = ((ya > ys) != (yb > ys))
                xi = xa + (ys - ya) * (xb - xa) / (yb - ya)
                inside ^= cond & (xs < xi)
        sub = s.a[s.h - y1:s.h - y0, x0:x1]
        m = inside[::-1]
        sub[m] = sub[m] * (1 - alpha) + _hx(c) * alpha

    def circle(s, cx, cy, r, c, alpha=1.0, n=96):
        s.poly([[(cx + r * cos(2 * pi * i / n), cy + r * sin(2 * pi * i / n)) for i in range(n)]], c, alpha)

    def ring(s, cx, cy, r0, r1, c, n=96):
        s.poly([[(cx + r1 * cos(2 * pi * i / n), cy + r1 * sin(2 * pi * i / n)) for i in range(n)],
                [(cx + r0 * cos(2 * pi * i / n), cy + r0 * sin(2 * pi * i / n)) for i in range(n)]], c)

    def text(s, txt, xc, yc, h, c, sw=None, align='center', gap=0.15, maxw=None):
        if maxw is not None:
            h = min(h, maxw / max(1e-6, text_width(txt, 1.0, gap)))
        sw = min(sw or h * 0.13, h * 0.16)
        tw = text_width(txt, h, gap)
        x = xc - tw / 2 if align == 'center' else (xc if align == 'left' else xc - tw)
        y0 = yc - h / 2
        for ch in txt.upper():
            gw, strokes = GLYPHS.get(ch, GLYPHS[' '])
            Wg = gw * h * WSCALE
            for kind, pts in strokes:
                q = [(x + sw / 2 + px * (Wg - sw), y0 + sw / 2 + py * (h - sw)) for (px, py) in pts]
                if kind == 'o':
                    for piece in _split_sharp(q, sw / 2):
                        s.poly([stroke_poly(piece, sw, 1.5)], c)
                else:
                    o, i = stroke_ring(q, sw, 1.5)
                    s.poly([o, i], c)
            x += Wg + gap * h
        return h

    def shadow_text(s, txt, xc, yc, h, c, shadow, off=0.012, **kw):
        h2 = s.text(txt, xc + off, yc - off, h, shadow, **kw)
        s.text(txt, xc, yc, h2, c, **kw)

    def to_rgb8(s):
        a = s.a.reshape(s.H, s.ss, s.W, s.ss, 3).mean(axis=(1, 3))
        return np.clip(a + 0.5, 0, 255).astype(np.uint8)

def write_png(path, rgb):
    h, w, _ = rgb.shape
    raw = b''.join(b'\x00' + rgb[r].tobytes() for r in range(h))
    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) +
           chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(png)

def _star(cx, cy, r0, r1, n=5, rot=90.0):
    pts = []
    for i in range(2 * n):
        r = r1 if i % 2 == 0 else r0
        a = radians(rot + 180.0 * i / n)
        pts.append((cx + r * cos(a), cy + r * sin(a)))
    return pts

def _flame(cx, cy0, cy1, w, n=24):
    right = []; left = []
    for i in range(n + 1):
        t = i / n
        y = cy0 + (cy1 - cy0) * t
        ww = w * sin(pi * min(1.0, t ** 0.75)) * (1.0 - 0.25 * t)
        right.append((cx + ww, y)); left.append((cx - ww * 0.92, y))
    pts = right + left[::-1][1:]
    # lean the tip slightly to the left
    return [(x - 0.05 * ((y - cy0) / (cy1 - cy0)) ** 2, y) for (x, y) in pts]

def _mountain(x0, x1, base, peaks):
    pts = [(x0, base)]
    for (x, y) in peaks:
        pts.append((x, y))
    pts.append((x1, base))
    return pts

def ad_a(W, H):
    """SUNPEAK FUEL: white board, red header, navy footer, flame roundel"""
    c = Canvas(W, H)
    c.fill('#f3efe4')
    c.rect(0, 0.80, 2, 1.0, '#c7202b')
    c.text('OPEN 24 HOURS', 1.0, 0.90, 0.10, '#f3efe4', sw=0.014, maxw=1.5)
    c.rect(0, 0, 2, 0.17, '#14213d')
    c.text('COFFEE / SNACKS / TYRE AIR', 1.0, 0.085, 0.07, '#f3efe4', sw=0.011, maxw=1.7)
    c.circle(0.52, 0.485, 0.31, '#14213d')
    c.circle(0.52, 0.485, 0.27, '#f3efe4')
    c.poly([_flame(0.52, 0.27, 0.73, 0.15)], '#c7202b')
    c.poly([_flame(0.525, 0.30, 0.55, 0.075)], '#f6b21b')
    c.text('SUNPEAK', 1.42, 0.575, 0.24, '#14213d', sw=0.05, maxw=1.0)
    c.text('FUEL', 1.42, 0.34, 0.2, '#c7202b', sw=0.045, maxw=0.8)
    c.rect(0.95, 0.455, 1.89, 0.47, '#14213d')
    return c.to_rgb8()

def ad_b(W, H):
    """LAKEVIEW INN: sky, sun, two mountain ranges, lake, white lettering"""
    c = Canvas(W, H)
    c.vgrad(0.0, 1.0, '#a9dcf2', '#2b66ad')
    c.circle(1.55, 0.60, 0.20, '#ffe9a6', alpha=0.45)
    c.circle(1.55, 0.60, 0.125, '#ffd54a')
    c.poly([_mountain(0, 2, 0.30, [(0.0, 0.42), (0.28, 0.56), (0.55, 0.40), (0.85, 0.62), (1.18, 0.42), (1.42, 0.50), (1.7, 0.38), (2.0, 0.47)])], '#6c8fb4')
    c.poly([_mountain(0, 2, 0.30, [(0.0, 0.34), (0.35, 0.46), (0.7, 0.33), (1.05, 0.44), (1.4, 0.32), (1.75, 0.42), (2.0, 0.35)])], '#2f5576')
    c.vgrad(0.0, 0.30, '#2a7ab0', '#1a517f')
    for k, y in enumerate((0.24, 0.185, 0.14)):
        for j in range(5):
            x = 0.2 + 0.38 * j + (0.12 if k % 2 else 0.0)
            c.rect(x, y, x + 0.16 - 0.02 * k, y + 0.008, '#cfe9f7', alpha=0.55)
    c.shadow_text('LAKEVIEW INN', 1.0, 0.76, 0.21, '#ffffff', '#12283d', off=0.012, sw=0.036, maxw=1.75)
    c.rect(0, 0, 2, 0.115, '#12283d')
    c.text('ROOMS / FOOD / VIEWS', 1.0, 0.057, 0.06, '#ffffff', sw=0.01, maxw=1.5)
    return c.to_rgb8()

def ad_c(W, H):
    """ROADSIDE DINER: yellow board, black frame, burger icon, arrow"""
    c = Canvas(W, H)
    c.fill('#f5c518')
    for i in range(14):
        x = -0.1 + i * 0.16
        c.poly([[(x, 0.0), (x + 0.08, 0.0), (x + 0.16, 0.10), (x + 0.08, 0.10)]], '#15151a')
        c.poly([[(x, 0.90), (x + 0.08, 0.90), (x + 0.16, 1.0), (x + 0.08, 1.0)]], '#15151a')
    # burger icon
    bx, by = 0.50, 0.50
    bun_top = [(bx + 0.27 * cos(radians(a)), by + 0.07 + 0.18 * sin(radians(a))) for a in range(0, 181, 6)]
    c.poly([bun_top], '#d9822b')
    for (dx, dy) in ((-0.12, 0.17), (0.0, 0.215), (0.12, 0.17), (-0.05, 0.14), (0.07, 0.125)):
        c.poly([[(bx + dx + 0.025 * cos(2 * pi * i / 10), by + dy + 0.013 * sin(2 * pi * i / 10)) for i in range(10)]], '#f7e3b0')
    lett = [(bx - 0.29 + 0.58 * i / 24, by + 0.02 + (0.025 if i % 2 else -0.005)) for i in range(25)]
    c.poly([lett + [(bx + 0.29, by - 0.04), (bx - 0.29, by - 0.04)]], '#3f9b3a')
    c.rect(bx - 0.27, by - 0.10, bx + 0.27, by - 0.04, '#c7202b')
    c.rect(bx - 0.28, by - 0.19, bx + 0.28, by - 0.10, '#5b2f1a')
    c.rect(bx - 0.26, by - 0.27, bx + 0.26, by - 0.19, '#d9822b')
    c.text('EAT HERE', 1.36, 0.63, 0.26, '#15151a', sw=0.055, maxw=1.05)
    c.text('ROADSIDE DINER', 1.36, 0.40, 0.09, '#15151a', sw=0.016, maxw=1.0)
    c.poly([[(0.98, 0.165), (1.34, 0.165), (1.34, 0.115), (1.50, 0.215), (1.34, 0.315), (1.34, 0.265), (0.98, 0.265)]], '#15151a')
    c.text('2 KM', 1.72, 0.215, 0.11, '#15151a', sw=0.02, maxw=0.4)
    return c.to_rgb8()

_AD_FN = {'A': ad_a, 'B': ad_b, 'C': ad_c}

def ensure_ad_textures(force=False, only=None):
    """(re)generate the three ad PNGs when missing or older than this script; returns {key: path}"""
    out = {}
    src = os.path.join(_here, 'rs_ads.py') if '_here' in globals() else None
    src_t = os.path.getmtime(src) if src and os.path.exists(src) else 0
    for k, fn in AD_FILES.items():
        if only is not None and k not in only:
            out[k] = os.path.join(AD_DIR, fn)
            continue
        p = os.path.join(AD_DIR, fn)
        if force or not os.path.exists(p) or os.path.getmtime(p) < src_t:
            t0 = time.time()
            write_png(p, _AD_FN[k](*AD_SIZE))
            print('AD texture', fn, '%.1fs' % (time.time() - t0))
        out[k] = p
    return out
