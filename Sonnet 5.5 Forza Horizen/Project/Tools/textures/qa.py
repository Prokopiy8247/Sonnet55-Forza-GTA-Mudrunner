"""Quality assurance: contact sheets, tiling previews, seam metrics, range checks."""
from __future__ import annotations

import hashlib
import json
import os

import numpy as np

from . import maps
from .noise import f32
from .png import read_png, write_png

_FONT = {
    "A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
    "E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
    "I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
    "M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
    "Q": "010101101111011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
    "U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
    "Y": "101101010010010", "Z": "111001010100111", "0": "111101101101111", "1": "010110010010111",
    "2": "110001010100111", "3": "110001010001110", "4": "101101111001001", "5": "111100110001110",
    "6": "011100111101111", "7": "111001010010010", "8": "111101111101111", "9": "111101111001110",
    "_": "000000000000111", " ": "000000000000000", "-": "000000111000000", "x": "000101010101000",
}


def draw_text(img, text, x, y, scale=2, color=(1, 1, 1), shadow=(0, 0, 0)):
    """Draw label with the tiny built-in 3x5 font onto float image (H,W,3)."""
    cx = x
    for ch in text:
        g = _FONT.get(ch.upper(), _FONT[" "])
        for i, bit in enumerate(g):
            if bit == "1":
                gy, gx = divmod(i, 3)
                for (col, off) in ((shadow, 1), (color, 0)):
                    yy = y + gy * scale + off
                    xx = cx + gx * scale + off
                    if 0 <= yy and yy + scale <= img.shape[0] and 0 <= xx and xx + scale <= img.shape[1]:
                        img[yy:yy + scale, xx:xx + scale] = col
        cx += 4 * scale


def box_down(a, size):
    """Area downsample (H,W[,C]) to ~size px using integer factor."""
    n = a.shape[0]
    f = max(1, n // size)
    h = (a.shape[0] // f) * f
    w = (a.shape[1] // f) * f
    a = a[:h, :w]
    if a.ndim == 2:
        return a.reshape(h // f, f, w // f, f).mean((1, 3))
    return a.reshape(h // f, f, w // f, f, a.shape[2]).mean((1, 3))


def load_set(root, entry):
    """Load maps of a set from disk -> dict of float arrays."""
    out = {}
    d = root
    for suffix, fi in entry["files"].items():
        raw = read_png(os.path.join(d, fi["file"]))
        scale = 65535.0 if raw.dtype == np.uint16 else 255.0
        out[suffix] = raw.astype(f32) / scale
    return out


def checker(h, w, cell=16):
    yy, xx = np.mgrid[0:h, 0:w]
    c = (((yy // cell) + (xx // cell)) % 2).astype(f32)
    return (0.28 + 0.1 * c)[..., None] * np.ones(3, f32)


def render_albedo(m):
    bc = m.get("BC")
    if bc is None:
        d = m.get("D")
        if d is None:
            return m.get("N")
        if d.ndim == 2:
            d = np.repeat(d[..., None], 3, -1)
        return d[..., :3]          # data textures: show RGB, ignore the 4th channel
    if bc.ndim == 2:
        bc = np.repeat(bc[..., None], 3, -1)
    if bc.shape[2] == 4:
        rgb, a = bc[..., :3], bc[..., 3:4]
        return rgb * a + checker(bc.shape[0], bc.shape[1], 24 * bc.shape[0] // 1024) * (1 - a)
    return bc[..., :3]


def render_lit(m):
    bc = m.get("BC")
    if bc is None or "N" not in m:
        return render_albedo(m)
    alb = maps.srgb_to_lin(bc[..., :3])
    orm = m.get("ORM")
    if orm is None:
        orm = np.stack([np.ones(alb.shape[:2], f32), np.full(alb.shape[:2], 0.7, f32), np.zeros(alb.shape[:2], f32)], -1)
    lit = maps.lit_preview(alb, m["N"], orm)
    if bc.shape[2] == 4:
        a = bc[..., 3:4]
        lit = lit * a + checker(bc.shape[0], bc.shape[1], 24 * bc.shape[0] // 1024) * (1 - a)
    return lit


def build_sheet(root, entries, cols, thumb, mode, path):
    tiles = []
    for e in entries:
        m = load_set(root, e)
        if mode == "albedo":
            img = render_albedo(m)
        elif mode == "lit":
            img = render_lit(m)
        elif mode == "normal":
            img = m.get("N")
            if img is None:
                img = render_albedo(m)
        elif mode == "orm":
            img = m.get("ORM")
            if img is None:
                img = render_albedo(m)
        else:
            raise ValueError(mode)
        if img is None:
            img = np.zeros((thumb, thumb, 3), f32)
        if mode in ("albedo", "lit") and img.ndim == 3:
            pass
        t = box_down(img, thumb)
        if t.shape[0] != thumb or t.shape[1] != thumb:
            pad = np.zeros((thumb, thumb, 3), f32)
            pad[:t.shape[0], :t.shape[1]] = t[..., :3]
            t = pad
        t = np.ascontiguousarray(t[..., :3])
        draw_text(t, e["name"], 3, thumb - 14, 2)
        tiles.append(t)
    rows = (len(tiles) + cols - 1) // cols
    g = 4
    W = cols * thumb + (cols + 1) * g
    H = rows * thumb + (rows + 1) * g
    sheet = np.full((H, W, 3), 0.08, f32)
    for i, t in enumerate(tiles):
        r, c = divmod(i, cols)
        y = g + r * (thumb + g)
        x = g + c * (thumb + g)
        sheet[y:y + thumb, x:x + thumb] = t
    u8 = np.clip(np.rint(sheet * 255), 0, 255).astype(np.uint8)
    write_png(path, u8)
    return path


def _compose(tiles, cols, thumb, path):
    rows = (len(tiles) + cols - 1) // cols
    g = 4
    W = cols * thumb + (cols + 1) * g
    H = rows * thumb + (rows + 1) * g
    sheet = np.full((H, W, 3), 0.08, f32)
    for i, t in enumerate(tiles):
        r, c = divmod(i, cols)
        y = g + r * (thumb + g)
        x = g + c * (thumb + g)
        sheet[y:y + thumb, x:x + thumb] = t
    write_png(path, np.clip(np.rint(sheet * 255), 0, 255).astype(np.uint8))
    return path


def tiling_preview(root, entry, path, out=2048, what="lit"):
    """2x2 tiled preview of one set (to inspect seams), `out` px square."""
    m = load_set(root, entry)
    img = render_lit(m) if what == "lit" else render_albedo(m)
    img = img[..., :3]
    t = box_down(img, out // 2)
    big = np.tile(t, (2, 2, 1))
    write_png(path, np.clip(np.rint(big * 255), 0, 255).astype(np.uint8))
    return path


def tiling_sheet(root, entries, cols, cell, path):
    """Contact sheet of 2x2 tiled lit previews (each cell is cell x cell px) for all given sets."""
    tiles = []
    for e in entries:
        m = load_set(root, e)
        img = render_lit(m)[..., :3]
        t = box_down(img, cell // 2)
        big = np.ascontiguousarray(np.tile(t, (2, 2, 1))[:cell, :cell])
        draw_text(big, e["name"] + " 2x2", 3, cell - 14, 2)
        tiles.append(big)
    return _compose(tiles, cols, cell, path)


# ------------------------------------------------------------------------------ verification
def seam_ratio(a):
    """Continuity test across the wrap seam, robust to features sitting exactly on the seam.

    For each axis: mean |a[0] - a[-1]| (the pair that becomes neighbours when tiled) divided by the
    mean difference of the neighbouring pairs on both sides of the seam ((0,1),(1,2) and
    (-2,-1),(-3,-2)).  ~1.0 => the texture continues across the seam exactly as it does inside the
    image; >> 1 => visible seam.  a: (H,W) or (H,W,C) float in 0..1."""
    a = a.astype(f32)
    if a.ndim == 3:
        a = a[..., :3] if a.shape[2] >= 3 else a[..., :1]
        a = a.reshape(a.shape[0], a.shape[1], -1)
    else:
        a = a[..., None]
    eps = 1.0 / 255.0

    def axis_ratio(x):          # compare along axis 0 (rows), x shape (H, W, C)
        seam = np.abs(x[0] - x[-1]).mean()
        ref = 0.25 * (np.abs(x[1] - x[0]).mean() + np.abs(x[2] - x[1]).mean()
                      + np.abs(x[-1] - x[-2]).mean() + np.abs(x[-2] - x[-3]).mean())
        return seam / (ref + eps)
    return max(axis_ratio(a), axis_ratio(np.swapaxes(a, 0, 1)))


def atlas_gutter_issues(name, e, m, gutter_px=8.0):
    """Every cell of a grid atlas must be fully transparent (alpha == 0) in the outer `gutter_px`
    ring (scaled by size/2048): artwork may never be cut by, or bleed across, a cell border."""
    grid, cp, bc = e.get("grid"), e.get("cell_px"), m.get("BC")
    if not grid or cp is None or bc is None or bc.ndim != 3 or bc.shape[2] != 4:
        return []
    a = bc[..., 3]
    n = a.shape[0]
    g = max(1, int(round(gutter_px * n / 2048.0)))
    cw, ch = (cp, cp) if not isinstance(cp, list) else cp
    cw, ch = int(round(cw)), int(round(ch))
    bad = []
    for r in range(grid[1]):
        for c in range(grid[0]):
            cell = a[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw]
            ring = np.zeros(cell.shape, bool)
            ring[:g] = True
            ring[-g:] = True
            ring[:, :g] = True
            ring[:, -g:] = True
            hit = int((cell[ring] > 0.5 / 255.0).sum())
            if hit:
                bad.append("r%dc%d(%d px)" % (r, c, hit))
    if bad:
        return ["%s: alpha inside the %d px cell gutter: %s" % (name, g, ", ".join(bad))]
    return []


def verify(root, manifest, log=print):
    issues = []
    rows = []
    for e in manifest["sets"]:
        name = e["name"]
        try:
            m = load_set(root, e)
        except Exception as ex:   # noqa
            issues.append("%s: failed to load (%s)" % (name, ex))
            continue
        worst = 0.0
        for suffix, a in m.items():
            if e.get("tileable", True):
                if suffix == "N" and "H" in m:
                    continue            # N is derived from H with a wrap-around Sobel: periodic by construction
                r = seam_ratio(a)
                worst = max(worst, r)
                if r > 1.6:
                    issues.append("%s_%s: seam ratio %.2f" % (name, suffix, r))
        if "N" in m:
            v = m["N"] * 2 - 1
            if v[..., 2].min() < -0.001:
                issues.append("%s: normal z negative" % name)
            ln = np.sqrt((v * v).sum(-1)).mean()
            if abs(ln - 1) > 0.05:
                issues.append("%s: normal length %.3f" % (name, ln))
        issues.extend(atlas_gutter_issues(name, e, m))
        lo_hi = e.get("albedo_range")
        mean = e.get("albedo_mean_linear")
        if lo_hi and mean is not None and not (lo_hi[0] <= mean <= lo_hi[1]):
            issues.append("%s: mean linear albedo %.3f outside [%.2f, %.2f]" % (name, mean, lo_hi[0], lo_hi[1]))
        rows.append((name, e["size"][0], mean, worst))
    log("%-28s %5s %8s %8s" % ("set", "size", "albedo", "seam"))
    for r in rows:
        log("%-28s %5d %8s %8.2f" % (r[0], r[1], "-" if r[2] is None else "%.3f" % r[2], r[3]))
    return issues


def tree_hash(root, names=None):
    h = hashlib.sha256()
    for dp, dn, fn in sorted(os.walk(root)):
        dn.sort()
        for f in sorted(fn):
            if not f.endswith(".png"):
                continue
            if names and os.path.basename(dp) not in names:
                continue
            with open(os.path.join(dp, f), "rb") as fh:
                h.update(f.encode())
                h.update(fh.read())
    return h.hexdigest()
