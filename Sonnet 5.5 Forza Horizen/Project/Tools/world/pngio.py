"""Minimal PNG writer (zlib + struct only) plus a tiny bitmap font for map labels.

write_png(path, img) accepts:
  * 2-D uint8 / uint16 array  -> greyscale (8 or 16 bit)
  * HxWx3 uint8               -> RGB
  * HxWx4 uint8               -> RGBA
"""
import struct
import zlib

import numpy as np


def _chunk(tag, data):
    c = struct.pack(">I", len(data)) + tag + data
    return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path, img, level=6):
    img = np.ascontiguousarray(img)
    if img.ndim == 2:
        h, w = img.shape
        ch = 1
        color_type = 0
    elif img.ndim == 3 and img.shape[2] in (3, 4):
        h, w, ch = img.shape
        color_type = 2 if ch == 3 else 6
    else:
        raise ValueError("unsupported image shape %r" % (img.shape,))
    if img.dtype == np.uint8:
        depth = 8
        rowbytes = w * ch
        data = img.reshape(h, rowbytes)
    elif img.dtype == np.uint16 and ch == 1:
        depth = 16
        data = img.astype(">u2").view(np.uint8).reshape(h, w * 2)
        rowbytes = w * 2
    else:
        raise ValueError("unsupported dtype %s" % img.dtype)
    bpp = max(1, (depth * ch) // 8)
    # PNG 'Sub' filter (type 1) compresses terrain/maps much better than none.
    raw = np.empty((h, rowbytes + 1), dtype=np.uint8)
    raw[:, 0] = 1
    sub = data.copy()
    sub[:, bpp:] = (data[:, bpp:].astype(np.int16) - data[:, :-bpp].astype(np.int16)).astype(np.uint8)
    raw[:, 1:] = sub
    comp = zlib.compress(raw.tobytes(), level)
    ihdr = struct.pack(">IIBBBBB", w, h, depth, color_type, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(_chunk(b"IHDR", ihdr))
        f.write(_chunk(b"IDAT", comp))
        f.write(_chunk(b"IEND", b""))


# ---------------------------------------------------------------- tiny font
# 5x7 glyphs, rows top->bottom, 5 bits per row (MSB = left)
_FONT = {
    "A": "01110 10001 10001 11111 10001 10001 10001",
    "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01110 10001 10000 10000 10000 10001 01110",
    "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 10000 11110 10000 10000 11111",
    "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01110 10001 10000 10111 10001 10001 01111",
    "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "01110 00100 00100 00100 00100 00100 01110",
    "J": "00111 00010 00010 00010 00010 10010 01100",
    "K": "10001 10010 10100 11000 10100 10010 10001",
    "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001",
    "N": "10001 11001 10101 10011 10001 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110",
    "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101",
    "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110",
    "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110",
    "V": "10001 10001 10001 10001 10001 01010 00100",
    "W": "10001 10001 10001 10101 10101 11011 10001",
    "X": "10001 10001 01010 00100 01010 10001 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100",
    "Z": "11111 00001 00010 00100 01000 10000 11111",
    "0": "01110 10001 10011 10101 11001 10001 01110",
    "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00010 00100 01000 11111",
    "3": "11110 00001 00001 01110 00001 00001 11110",
    "4": "00010 00110 01010 10010 11111 00010 00010",
    "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110",
    "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110",
    "9": "01110 10001 10001 01111 00001 00010 01100",
    ".": "00000 00000 00000 00000 00000 01100 01100",
    ",": "00000 00000 00000 00000 01100 00100 01000",
    ":": "00000 01100 01100 00000 01100 01100 00000",
    "-": "00000 00000 00000 11111 00000 00000 00000",
    "+": "00000 00100 00100 11111 00100 00100 00000",
    "%": "11001 11010 00010 00100 01000 01011 10011",
    "/": "00001 00010 00010 00100 01000 01000 10000",
    "(": "00010 00100 01000 01000 01000 00100 00010",
    ")": "01000 00100 00010 00010 00010 00100 01000",
    "=": "00000 00000 11111 00000 11111 00000 00000",
    "<": "00010 00100 01000 10000 01000 00100 00010",
    ">": "01000 00100 00010 00001 00010 00100 01000",
    "_": "00000 00000 00000 00000 00000 00000 11111",
    "'": "00100 00100 01000 00000 00000 00000 00000",
    " ": "00000 00000 00000 00000 00000 00000 00000",
}
_GLYPH = {}
for _k, _v in _FONT.items():
    rows = _v.split()
    _GLYPH[_k] = np.array([[int(c) for c in r] for r in rows], dtype=bool)


def text_size(s, scale=1):
    return (len(s) * 6 - 1) * scale, 7 * scale


def draw_text(img, x, y, s, color=(255, 255, 255), scale=1, shadow=None):
    """Draw text onto an HxWx3 uint8 image in place. (x, y) = top-left pixel."""
    s = s.upper()
    h, w = img.shape[:2]
    col = np.array(color, dtype=np.uint8)

    def blit(ox, oy, c):
        cx = ox
        for ch in s:
            g = _GLYPH.get(ch)
            if g is None:
                g = _GLYPH[" "]
            gg = np.kron(g, np.ones((scale, scale), dtype=bool)) if scale > 1 else g
            gh, gw = gg.shape
            x0, y0 = cx, oy
            xa, ya = max(0, x0), max(0, y0)
            xb, yb = min(w, x0 + gw), min(h, y0 + gh)
            if xa < xb and ya < yb:
                sub = gg[ya - y0:yb - y0, xa - x0:xb - x0]
                region = img[ya:yb, xa:xb]
                region[sub] = c
            cx += 6 * scale
    if shadow is not None:
        blit(x + 1, y + 1, np.array(shadow, dtype=np.uint8))
    blit(x, y, col)
