"""
sectionplot.py - tiny numpy-only 2D line plotter (writes a PNG through a temporary Blender image datablock).
Used to inspect the cross sections / side profiles of the lofted car shell without touching the scene.

    exec(compile(open(SP, encoding='utf8').read(), SP, 'exec'), globals())
    plot_lines([ (pts, (r,g,b)), ... ], bounds=(xmin, xmax, zmin, zmax), size=(900, 600), out=path, grid=0.1)
"""
import bpy
import numpy as np


def plot_lines(lines, bounds, size=(900, 600), out=None, grid=0.1, equal=True):
    W, H = size
    x0, x1, z0, z1 = bounds
    if equal:
        sx = W / (x1 - x0)
        sz = H / (z1 - z0)
        s = min(sx, sz)
        ox = (W - (x1 - x0) * s) / 2.0
        oz = (H - (z1 - z0) * s) / 2.0
    else:
        s = None
    img = np.full((H, W, 3), 0.97, dtype=np.float32)

    def to_px(p):
        if equal:
            return ((p[0] - x0) * s + ox, (p[1] - z0) * s + oz)
        return ((p[0] - x0) / (x1 - x0) * W, (p[1] - z0) / (z1 - z0) * H)

    def seg(a, b, col, w=1):
        n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1]))) + 2
        t = np.linspace(0.0, 1.0, n)
        xs = (a[0] + (b[0] - a[0]) * t).astype(np.int32)
        ys = (a[1] + (b[1] - a[1]) * t).astype(np.int32)
        for dx in range(-(w // 2), w // 2 + 1):
            for dy in range(-(w // 2), w // 2 + 1):
                xx, yy = xs + dx, ys + dy
                m = (xx >= 0) & (xx < W) & (yy >= 0) & (yy < H)
                img[yy[m], xx[m]] = col

    if grid:
        g = np.floor(x0 / grid) * grid
        while g <= x1:
            px = to_px((g, z0))
            seg(px, to_px((g, z1)), (0.86, 0.86, 0.9) if abs(g / grid - round(g / grid)) > 1e-6 or round(g / grid) % 5 else (0.7, 0.7, 0.78))
            g += grid
        g = np.floor(z0 / grid) * grid
        while g <= z1:
            seg(to_px((x0, g)), to_px((x1, g)), (0.86, 0.86, 0.9) if round(g / grid) % 5 else (0.7, 0.7, 0.78))
            g += grid
    for pts, col in lines:
        P = [to_px(p) for p in pts]
        for a, b in zip(P[:-1], P[1:]):
            seg(a, b, col, 2)
    if out is None:
        return img
    rgba = np.ones((H, W, 4), dtype=np.float32)
    rgba[..., :3] = img ** (1.0 / 2.2)
    im = bpy.data.images.new("__plot_tmp", W, H, alpha=False, float_buffer=False)
    try:
        im.pixels.foreach_set(rgba.ravel())
        im.filepath_raw = out
        im.file_format = 'PNG'
        im.save()
    finally:
        bpy.data.images.remove(im)
    return out
