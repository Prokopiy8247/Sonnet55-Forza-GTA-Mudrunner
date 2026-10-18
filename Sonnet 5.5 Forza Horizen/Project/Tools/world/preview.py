"""Preview rendering (hillshade, region colours, road overlays, profile strips, histograms) -> PNG via pngio."""
import math

import numpy as np

import worlddef as W
from common import HALF, ss
from pngio import write_png, draw_text, text_size


def to_map(A):
    """[j,i] (or [j,i,c]) array -> north-up map image array (rows = X descending, cols = Y ascending)."""
    if A.ndim == 3:
        return np.transpose(A, (1, 0, 2))[::-1]
    return A.T[::-1]


def hillshade(Hmap, step, az=315.0, alt=42.0, zex=1.0):
    gy_, gx_ = np.gradient(Hmap.astype(np.float32), step)    # gy_ = d/d(row) , gx_ = d/d(col)
    # row index increases towards -X (south), col towards +Y (east)
    dzdX = -gy_
    dzdY = gx_
    nx = -dzdX * zex
    ny = -dzdY * zex
    nz = np.ones_like(nx)
    nrm = np.sqrt(nx * nx + ny * ny + nz * nz)
    a = math.radians(alt)
    azr = math.radians(az)
    # azimuth is compass bearing of the light: 0 = north (+X), 90 = east (+Y)
    lx = math.cos(a) * math.cos(azr)
    ly = math.cos(a) * math.sin(azr)
    lz = math.sin(a)
    sh = (nx * lx + ny * ly + nz * lz) / nrm
    return np.clip(sh, 0.0, 1.0)


def hypso(Hmap):
    """hypsometric tint, returns HxWx3 float 0..1"""
    stops = [(-60, (0.04, 0.16, 0.38)), (-1, (0.12, 0.40, 0.62)), (0.0, (0.86, 0.80, 0.60)), (3, (0.55, 0.72, 0.36)),
             (60, (0.40, 0.62, 0.28)), (140, (0.52, 0.62, 0.32)), (230, (0.78, 0.62, 0.40)), (330, (0.66, 0.52, 0.40)),
             (480, (0.55, 0.52, 0.50)), (600, (0.80, 0.80, 0.82)), (760, (1.0, 1.0, 1.0))]
    zs = np.array([s[0] for s in stops], dtype=np.float32)
    out = np.empty(Hmap.shape + (3,), dtype=np.float32)
    for c in range(3):
        out[..., c] = np.interp(Hmap, zs, np.array([s[1][c] for s in stops], dtype=np.float32))
    return out


def render_map(H, step, region=None, shade_strength=1.0, tint_region=0.35, zex=1.0, sea_alpha=True):
    """H [j,i] on `step` grid -> RGB uint8 north-up. Returns img, and (px per metre)."""
    Hm = to_map(H)
    sh = hillshade(Hm, step, zex=zex)
    col = hypso(Hm)
    if region is not None and tint_region > 0:
        rm = to_map(region)
        pal = np.array(W.REGION_COLORS, dtype=np.float32) / 255.0
        rc = pal[np.clip(rm, 0, len(pal) - 1)]
        land = (Hm > 0.5)[..., None]
        col = np.where(land, col * (1 - tint_region) + rc * tint_region, col)
    shade = (0.42 + 0.78 * sh)[..., None]
    shade = 1.0 + (shade - 1.0) * shade_strength
    img = np.clip(col * shade, 0, 1)
    # sea: darker with depth
    sea = Hm <= 0.0
    depth = np.clip(-Hm / 50.0, 0, 1)[..., None]
    seac = np.array([0.20, 0.52, 0.72], dtype=np.float32) * (1 - depth) + np.array([0.04, 0.20, 0.42], dtype=np.float32) * depth
    img = np.where(sea[..., None], seac * (0.9 + 0.1 * sh[..., None]), img)
    return (img * 255).astype(np.uint8)


def w2px(X, Y, scale, n_rows):
    """world -> pixel (col,row) in a north-up map where `scale` = pixels per metre and n_rows image height."""
    col = (np.asarray(Y) + HALF) * scale
    row = (HALF - np.asarray(X)) * scale
    return col, row


def draw_polyline(img, pts, color, scale, width=1.0, dash=None):
    """pts (m,2) world X,Y."""
    pts = np.asarray(pts, dtype=np.float64)
    if len(pts) < 2:
        return
    h, w = img.shape[:2]
    col, row = w2px(pts[:, 0], pts[:, 1], scale, h)
    seg = np.sqrt(np.diff(col) ** 2 + np.diff(row) ** 2)
    cum = np.concatenate([[0], np.cumsum(seg)])
    if cum[-1] < 1e-6:
        return
    nsamp = int(cum[-1] * 2) + 2
    t = np.linspace(0, cum[-1], nsamp)
    cx = np.interp(t, cum, col)
    cy = np.interp(t, cum, row)
    if dash:
        keep = (np.floor(t / dash[0]) % 2 == 0)
        cx, cy = cx[keep], cy[keep]
    r = max(0, int(round(width / 2.0 - 0.01)))
    c8 = np.array(color, dtype=np.uint8)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            xi = np.round(cx).astype(np.int64) + dx
            yi = np.round(cy).astype(np.int64) + dy
            ok = (xi >= 0) & (xi < w) & (yi >= 0) & (yi < h)
            img[yi[ok], xi[ok]] = c8


def draw_marker(img, X, Y, scale, color=(255, 255, 255), r=3, filled=True):
    h, w = img.shape[:2]
    col, row = w2px(X, Y, scale, h)
    cx, cy = int(round(float(col))), int(round(float(row)))
    c8 = np.array(color, dtype=np.uint8)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            d = math.hypot(dx, dy)
            if (filled and d <= r + 0.3) or (not filled and abs(d - r) < 0.9):
                x, y = cx + dx, cy + dy
                if 0 <= x < w and 0 <= y < h:
                    img[y, x] = c8


def label(img, X, Y, scale, s, color=(255, 255, 255), dx=5, dy=-4, size=1):
    h, w = img.shape[:2]
    col, row = w2px(X, Y, scale, h)
    draw_text(img, int(col) + dx, int(row) + dy, s, color=color, scale=size, shadow=(0, 0, 0))


def save(path, img):
    write_png(path, img)


def add_contours(img, Hmap, step, interval=50.0, major=250.0, color=(40, 30, 20), alpha=0.35, max_level=None):
    """overlay contour lines (north-up map array Hmap at `step` m/px; img same pixel grid)."""
    lv = np.floor(Hmap / interval).astype(np.int32)
    edge = np.zeros(Hmap.shape, dtype=bool)
    edge[:, :-1] |= lv[:, :-1] != lv[:, 1:]
    edge[:-1, :] |= lv[:-1, :] != lv[1:, :]
    edge &= Hmap > 0.5
    maj = np.zeros(Hmap.shape, dtype=bool)
    lm = np.floor(Hmap / major).astype(np.int32)
    maj[:, :-1] |= lm[:, :-1] != lm[:, 1:]
    maj[:-1, :] |= lm[:-1, :] != lm[1:, :]
    maj &= Hmap > 0.5
    c = np.array(color, dtype=np.float32)
    a = np.where(maj, alpha * 1.8, np.where(edge, alpha, 0.0))[..., None]
    out = img.astype(np.float32) * (1 - a) + c * a
    return out.astype(np.uint8)


def crop_view(H, step, region, box, upscale=1, shade=1.0, contour=25.0, zex=1.0, tint=0.25):
    """Render only world box (xmin,xmax,ymin,ymax) at native macro resolution; returns img and a function w2p.
    Output image is north-up; pixel size = step/upscale metres."""
    xmin, xmax, ymin, ymax = box
    i0 = int(max(0, np.floor((xmin + HALF) / step)))
    i1 = int(min(H.shape[1] - 1, np.ceil((xmax + HALF) / step)))
    j0 = int(max(0, np.floor((ymin + HALF) / step)))
    j1 = int(min(H.shape[0] - 1, np.ceil((ymax + HALF) / step)))
    sub = H[j0:j1 + 1, i0:i1 + 1]
    sreg = region[j0:j1 + 1, i0:i1 + 1] if region is not None else None
    img = render_map(sub, step, sreg, tint_region=tint, zex=zex)
    Hm = to_map(sub)
    if contour:
        img = add_contours(img, Hm, step, interval=contour, major=contour * 4)
    if upscale > 1:
        img = np.repeat(np.repeat(img, upscale, axis=0), upscale, axis=1)
    px = step / upscale
    x_top = -HALF + i1 * step      # world X at the top row
    y_left = -HALF + j0 * step     # world Y at the left col

    def w2p(X, Y):
        return (np.asarray(Y) - y_left) / px, (x_top - np.asarray(X)) / px
    return img, w2p, px


def draw_polyline_px(img, cols, rows, color, width=1.0, dash=None):
    h, w = img.shape[:2]
    cols = np.asarray(cols, dtype=np.float64)
    rows = np.asarray(rows, dtype=np.float64)
    seg = np.sqrt(np.diff(cols) ** 2 + np.diff(rows) ** 2)
    cum = np.concatenate([[0], np.cumsum(seg)])
    if len(cum) < 2 or cum[-1] < 1e-6:
        return
    nsamp = int(cum[-1] * 2) + 2
    t = np.linspace(0, cum[-1], nsamp)
    cx = np.interp(t, cum, cols)
    cy = np.interp(t, cum, rows)
    if dash:
        keep = (np.floor(t / dash[0]) % 2 == 0)
        cx, cy = cx[keep], cy[keep]
    r = max(0, int(round(width / 2.0 - 0.01)))
    c8 = np.array(color, dtype=np.uint8)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            xi = np.round(cx).astype(np.int64) + dx
            yi = np.round(cy).astype(np.int64) + dy
            ok = (xi >= 0) & (xi < w) & (yi >= 0) & (yi < h)
            img[yi[ok], xi[ok]] = c8
