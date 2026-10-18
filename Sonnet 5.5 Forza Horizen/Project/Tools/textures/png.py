"""Minimal PNG writer / reader (zlib + struct + numpy only).

Writer: 8-bit and 16-bit, grey / grey+alpha / RGB / RGBA.  Per-row adaptive filtering
(None / Sub / Up, chosen by minimum sum of absolute values) keeps files small while staying
fully vectorised.  Output is byte-for-byte deterministic (no timestamps).

Reader: only what this project writes (non-interlaced, filters 0/1/2, 8 or 16 bit); it is used
for the verification pass and for building contact sheets from the files on disk.
"""
from __future__ import annotations

import struct
import zlib

import numpy as np

_SIG = b"\x89PNG\r\n\x1a\n"
_CT = {1: 0, 2: 4, 3: 2, 4: 6}          # channels -> PNG colour type
_CH = {0: 1, 4: 2, 2: 3, 6: 4}          # PNG colour type -> channels


def _chunk(tag: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def _score(a: np.ndarray) -> np.ndarray:
    return np.abs(a.view(np.int8).astype(np.int16)).sum(axis=1, dtype=np.int64)


def write_png(path, arr: np.ndarray, level: int = 4, text: dict | None = None) -> int:
    """Write uint8 / uint16 array (H,W) or (H,W,C) as PNG. Returns file size in bytes."""
    arr = np.asarray(arr)
    if arr.dtype not in (np.uint8, np.uint16):
        raise TypeError("write_png expects uint8 or uint16, got %s" % arr.dtype)
    if arr.ndim == 2:
        arr = arr[:, :, None]
    h, w, c = arr.shape
    if c not in _CT:
        raise ValueError("channels must be 1..4")
    bits = 8 if arr.dtype == np.uint8 else 16
    if bits == 16:
        raw = np.ascontiguousarray(arr.astype(">u2")).view(np.uint8).reshape(h, w * c * 2)
    else:
        raw = np.ascontiguousarray(arr).reshape(h, w * c)
    bpp = c * (bits // 8)

    sub = raw.copy()
    sub[:, bpp:] = raw[:, bpp:] - raw[:, :-bpp]
    up = raw.copy()
    up[1:] = raw[1:] - raw[:-1]
    scores = np.stack([_score(raw), _score(sub), _score(up)], axis=0)
    ft = np.argmin(scores, axis=0).astype(np.uint8)
    out = np.empty((h, raw.shape[1] + 1), np.uint8)
    out[:, 0] = ft
    ftc = ft[:, None]
    out[:, 1:] = np.where(ftc == 0, raw, np.where(ftc == 1, sub, up))

    ihdr = struct.pack(">IIBBBBB", w, h, bits, _CT[c], 0, 0, 0)
    data = _SIG + _chunk(b"IHDR", ihdr)
    if text:
        for k, v in text.items():
            data += _chunk(b"tEXt", k.encode("latin-1") + b"\x00" + v.encode("latin-1"))
    data += _chunk(b"IDAT", zlib.compress(out.tobytes(), level))
    data += _chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)
    return len(data)


def read_png(path) -> np.ndarray:
    """Read a PNG written by write_png. Returns uint8/uint16 array (H,W) or (H,W,C)."""
    with open(path, "rb") as f:
        buf = f.read()
    if buf[:8] != _SIG:
        raise ValueError("not a PNG")
    pos = 8
    idat = []
    w = h = bits = ct = None
    while pos < len(buf):
        ln, = struct.unpack(">I", buf[pos:pos + 4])
        tag = buf[pos + 4:pos + 8]
        body = buf[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if tag == b"IHDR":
            w, h, bits, ct, _, _, il = struct.unpack(">IIBBBBB", body)
            if il != 0:
                raise NotImplementedError("interlaced PNG")
        elif tag == b"IDAT":
            idat.append(body)
        elif tag == b"IEND":
            break
    c = _CH[ct]
    bpp = c * (bits // 8)
    rb = w * bpp
    raw = np.frombuffer(zlib.decompress(b"".join(idat)), np.uint8).reshape(h, rb + 1)
    out = np.empty((h, rb), np.uint8)
    prev = np.zeros(rb, np.uint8)
    for y in range(h):
        f = raw[y, 0]
        row = raw[y, 1:]
        if f == 0:
            cur = row
        elif f == 1:
            cur = np.cumsum(row.reshape(-1, bpp), axis=0, dtype=np.uint8).reshape(-1)
        elif f == 2:
            cur = row + prev
        else:
            raise NotImplementedError("PNG filter %d" % f)
        out[y] = cur
        prev = cur
    if bits == 16:
        arr = out.view(">u2").astype(np.uint16).reshape(h, w, c)
    else:
        arr = out.reshape(h, w, c)
    return arr[:, :, 0] if c == 1 else arr
