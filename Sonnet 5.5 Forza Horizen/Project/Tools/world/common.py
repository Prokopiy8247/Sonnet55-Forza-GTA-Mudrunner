"""Shared constants and small numeric helpers for the world generator.

Coordinate system (UE metres): X = north, Y = east, Z = up, origin = map centre.
Height arrays are stored H[j, i]:  i -> +X (column), j -> +Y (row), 1 m spacing,
vertex (i, j) sits at X = i - 2016, Y = j - 2016.
"""
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(HERE, "out")
SOURCE_DIR = os.path.join(PROJECT, "Content", "Forza", "World", "Source")
CACHE_DIR = os.path.join(OUT_DIR, "cache")
PREVIEW_DIR = os.path.join(OUT_DIR, "previews")

N = 4033                # landscape vertices per side
HALF = 2016.0           # half extent (m)
SEA = 0.0               # sea level (m)
ZSCALE = 300.0          # UE landscape Scale.Z
M_PER_UNIT = ZSCALE / 128.0 / 100.0    # metres per uint16 step = 0.0234375
H16_ZERO = 32768


def ensure_dirs():
    for d in (OUT_DIR, SOURCE_DIR, CACHE_DIR, PREVIEW_DIR):
        os.makedirs(d, exist_ok=True)


_T0 = time.time()


def mem_mb():
    """(current, peak) working set of this process in MiB (Windows only, 0 elsewhere)."""
    try:
        import ctypes
        from ctypes import wintypes

        class PMC(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                        ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                        ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t)]
        pmc = PMC()
        pmc.cb = ctypes.sizeof(PMC)
        k32 = ctypes.windll.kernel32
        k32.GetCurrentProcess.restype = wintypes.HANDLE
        ctypes.windll.psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(PMC), wintypes.DWORD]
        ctypes.windll.psapi.GetProcessMemoryInfo(k32.GetCurrentProcess(), ctypes.byref(pmc), pmc.cb)
        return pmc.WorkingSetSize / 1048576.0, pmc.PeakWorkingSetSize / 1048576.0
    except Exception:
        return 0.0, 0.0


def log(*a):
    print("[%7.1fs]" % (time.time() - _T0), *a)
    sys.stdout.flush()


def log_mem(tag):
    cur, peak = mem_mb()
    log("   [mem] %-24s current %5.0f MiB  peak %5.0f MiB" % (tag, cur, peak))


def ss(x, a, b):
    """smoothstep from a (0) to b (1); works with a > b (inverted)."""
    den = np.asarray(b - a, dtype=np.float32) if np.ndim(b - a) else np.float32(b - a)
    den = np.where(np.abs(den) < 1e-6, np.float32(1e-6), den)
    t = np.clip((x - a) / den, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def smin(a, b, k):
    """smooth minimum (polynomial)."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def world_to_index(X, Y):
    """world metres -> float (i, j) index into a 1 m height array."""
    return X + HALF, Y + HALF


def index_to_world(i, j):
    return i - HALF, j - HALF


def sample_bilinear(A, X, Y, step=1.0, origin=-HALF):
    """Bilinear sample of A[j, i] at world (X, Y). A spans origin + step*idx."""
    fi = (np.asarray(X, dtype=np.float64) - origin) / step
    fj = (np.asarray(Y, dtype=np.float64) - origin) / step
    h, w = A.shape
    fi = np.clip(fi, 0, w - 1.0001)
    fj = np.clip(fj, 0, h - 1.0001)
    i0 = np.floor(fi).astype(np.int64)
    j0 = np.floor(fj).astype(np.int64)
    ti = (fi - i0).astype(np.float32)
    tj = (fj - j0).astype(np.float32)
    a00 = A[j0, i0]
    a01 = A[j0, i0 + 1]
    a10 = A[j0 + 1, i0]
    a11 = A[j0 + 1, i0 + 1]
    return (a00 * (1 - ti) + a01 * ti) * (1 - tj) + (a10 * (1 - ti) + a11 * ti) * tj


def gradient_xy(A, step=1.0):
    """central differences. returns (dA/dX, dA/dY) with the same shape as A."""
    gx = np.empty_like(A, dtype=np.float32)
    gy = np.empty_like(A, dtype=np.float32)
    gx[:, 1:-1] = (A[:, 2:] - A[:, :-2]) / (2 * step)
    gx[:, 0] = (A[:, 1] - A[:, 0]) / step
    gx[:, -1] = (A[:, -1] - A[:, -2]) / step
    gy[1:-1, :] = (A[2:, :] - A[:-2, :]) / (2 * step)
    gy[0, :] = (A[1, :] - A[0, :]) / step
    gy[-1, :] = (A[-1, :] - A[-2, :]) / step
    return gx, gy


def box_blur_axis(a, r, axis):
    """edge-replicating box blur of radius r (width 2r+1) along one axis, float64 accumulation."""
    if r <= 0:
        return a
    n = a.shape[axis]
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    p = np.pad(a, pad, mode="edge")
    c = np.cumsum(p, axis=axis, dtype=np.float64)
    hi = [slice(None)] * a.ndim
    lo = [slice(None)] * a.ndim
    hi[axis] = slice(2 * r + 1, 2 * r + 1 + n)
    lo[axis] = slice(0, n)
    out = (c[tuple(hi)] - c[tuple(lo)]) / (2 * r + 1)
    return out.astype(a.dtype if a.dtype != np.float64 else np.float64)


def gauss_blur(a, sigma):
    """~Gaussian blur (3 box passes per axis) of a 2-D float array. sigma in samples."""
    if sigma < 0.5:
        return a
    # three box blurs with total variance sigma^2: each box (2r+1) has var (w^2-1)/12
    w = np.sqrt(12.0 * sigma * sigma / 3.0 + 1.0)
    r = max(1, int(round((w - 1) / 2)))
    out = a.astype(np.float32, copy=True)
    for _ in range(3):
        out = box_blur_axis(out, r, 0)
        out = box_blur_axis(out, r, 1)
    return out


def block_mean(a, f):
    """downsample by integer factor f using block means (crops remainder)."""
    h, w = a.shape[:2]
    h2, w2 = (h // f) * f, (w // f) * f
    b = a[:h2, :w2].astype(np.float32)
    if a.ndim == 2:
        return b.reshape(h2 // f, f, w2 // f, f).mean(axis=(1, 3))
    return b.reshape(h2 // f, f, w2 // f, f, -1).mean(axis=(1, 3))
