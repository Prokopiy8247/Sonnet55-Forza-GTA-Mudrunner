"""Numpy-only erosion-like terrain filters.

* thermal(): talus-angle relaxation (8 neighbours) -> scree skirts below cliffs, softened ridges
* flow(): priority-flood depression filling + flow routing + drainage area (pure python heap, used on ~8 m grids)
* stream_power(): a few iterations of  incision ~ K * A^m * S  followed by thermal relaxation -> branching gully /
  valley networks that follow the drainage of the terrain (V shaped, widened to the talus angle)

All functions take / return float32 [j, i] arrays; `step` is the grid spacing in metres.
"""
import heapq

import numpy as np

_DIRS8 = [(0, 1, 1.0), (0, -1, 1.0), (1, 0, 1.0), (-1, 0, 1.0),
          (1, 1, 1.41421356), (1, -1, 1.41421356), (-1, 1, 1.41421356), (-1, -1, 1.41421356)]


def thermal(H, step, talus=0.75, iters=30, k=1.0, mask=None):
    """talus (rise/run) relaxation. `mask` (0..1, optional) scales the transfer per cell (0 = untouched)."""
    H = np.ascontiguousarray(H, dtype=np.float32).copy()
    n0, n1 = H.shape
    for _ in range(iters):
        P = np.pad(H, 1, mode="edge")
        acc = np.zeros((n0 + 2, n1 + 2), dtype=np.float32)
        out = np.zeros_like(H)
        for dj, di, dist in _DIRS8:
            Hn = P[1 + dj:1 + dj + n0, 1 + di:1 + di + n1]
            e = np.maximum(H - Hn - np.float32(talus * step * dist), 0.0)
            a = e * np.float32(k / 16.0)
            if mask is not None:
                a = a * mask
            out += a
            acc[1 + dj:1 + dj + n0, 1 + di:1 + di + n1] += a
        H = H - out + acc[1:-1, 1:-1]
    return H


def flow(H, sea_level=0.0, eps=2e-3):
    """Priority-flood fill + flow routing.

    Returns dict(filled, recv (flat index of the receiver, -1 for outlets), order (flat indices, outlets first),
    area (number of upstream cells incl. itself)). Cells at or below `sea_level` and the map border are outlets.
    """
    h, w = H.shape
    Z = H.astype(np.float64).ravel()
    zl = Z.tolist()
    filled = zl[:]
    recv = [-1] * (h * w)
    closed = bytearray(h * w)
    heap = []
    push = heapq.heappush
    pop = heapq.heappop
    seeds = np.zeros((h, w), dtype=bool)
    seeds[0, :] = seeds[-1, :] = True
    seeds[:, 0] = seeds[:, -1] = True
    seeds |= (H <= sea_level)
    for c in np.nonzero(seeds.ravel())[0].tolist():
        closed[c] = 1
        push(heap, (zl[c], c))
    order = []
    nb = [(-w - 1), (-w), (-w + 1), (-1), (1), (w - 1), (w), (w + 1)]
    while heap:
        z, c = pop(heap)
        order.append(c)
        cj, ci = divmod(c, w)
        for k in range(8):
            if (ci == 0 and k in (0, 3, 5)) or (ci == w - 1 and k in (2, 4, 7)) or (cj == 0 and k in (0, 1, 2)) or (cj == h - 1 and k in (5, 6, 7)):
                continue
            q = c + nb[k]
            if closed[q]:
                continue
            closed[q] = 1
            nz = zl[q]
            if nz <= z:
                nz = z + eps
            filled[q] = nz
            recv[q] = c
            push(heap, (nz, q))
    area = [1.0] * (h * w)
    for c in reversed(order):
        r = recv[c]
        if r >= 0:
            area[r] += area[c]
    return dict(filled=np.array(filled, dtype=np.float32).reshape(h, w), recv=np.array(recv, dtype=np.int64).reshape(h, w),
                order=np.array(order, dtype=np.int64), area=np.array(area, dtype=np.float32).reshape(h, w))


def landscape(zt, z0, step, iters=30, K=0.02, m=0.5, kappa=0.02, Kmask=None, kappa_mask=None, talus=0.8, thermal_iters=3,
              sea_level=0.0, uplift_noise=None, log_fn=None):
    """implicit stream-power landscape evolution (Braun & Willett 2013, n = 1) with a restoring uplift towards the
    designed surface `zt`:   dz/dt = kappa * (zt - z) - K * A^m * dz/dx   (+ thermal relaxation).
    Returns the eroded surface (starts from z0). Channels cut into the designed massif; hillslopes keep its macro form."""
    z = np.ascontiguousarray(z0, dtype=np.float32).copy()
    zt = np.ascontiguousarray(zt, dtype=np.float32)
    h, w = z.shape
    jj, ii = np.mgrid[0:h, 0:w]
    flat_idx = jj * w + ii
    kap = np.full(z.shape, np.float32(kappa)) if kappa_mask is None else (kappa * kappa_mask).astype(np.float32)
    ktr = np.ones(z.shape, dtype=np.float32) if Kmask is None else Kmask.astype(np.float32)
    for it in range(iters):
        fl = flow(z, sea_level=sea_level)
        recv = fl["recv"]
        r = np.where(recv >= 0, recv, flat_idx)
        rj = r // w
        ri = r % w
        dist = np.sqrt((rj - jj) ** 2 + (ri - ii) ** 2)
        dist = np.where(dist > 0, dist, 1.0)
        F = (K * ktr * np.power(fl["area"], m) / dist).astype(np.float64)
        up = kap.astype(np.float64)
        zf = z.astype(np.float64).ravel().tolist()
        zt_l = (zt.astype(np.float64) * up).ravel().tolist()
        Fl = F.ravel().tolist()
        ul = up.ravel().tolist()
        rl = recv.ravel().tolist()
        for c in fl["order"].tolist():
            rc = rl[c]
            if rc < 0:
                continue
            f = Fl[c]
            zf[c] = (zf[c] + zt_l[c] + f * zf[rc]) / (1.0 + ul[c] + f)
        z = np.array(zf, dtype=np.float32).reshape(h, w)
        if thermal_iters:
            z = thermal(z, step, talus=talus, iters=thermal_iters)
        if log_fn and (it % 5 == 0):
            log_fn("   erosion iter %d  z %.0f..%.0f" % (it, float(z.min()), float(z.max())))
    return z


def stream_power(H, step, iters=6, K=0.012, m=0.5, a_min=25.0, max_cut=6.0, talus=0.62, thermal_iters=12, mask=None, sea_level=0.0,
                 cut_scale=None):
    """gully / valley incision. `mask` (0..1) scales the incision per cell (0 = none: farmland, sea ...).
    K is in metres per iteration per (cell_area^m * slope). Returns the new height field."""
    H = np.ascontiguousarray(H, dtype=np.float32).copy()
    h, w = H.shape
    for it in range(iters):
        fl = flow(H, sea_level=sea_level)
        recv = fl["recv"]
        area = fl["area"]
        filled = fl["filled"]
        jj, ii = np.mgrid[0:h, 0:w]
        r = np.where(recv >= 0, recv, jj * w + ii)
        rj = r // w
        ri = r % w
        dist = step * np.sqrt((rj - jj) ** 2 + (ri - ii) ** 2)
        dist = np.where(dist > 0, dist, step)
        drop = np.maximum(H - H[rj, ri], 0.0)
        slope = np.maximum(drop / dist, 0.002)
        a = np.maximum(area - a_min, 0.0)
        cut = K * np.power(a, m) * slope * 4.0
        if cut_scale is not None:
            cut = cut * cut_scale
        if mask is not None:
            cut = cut * mask
        cut = np.minimum(cut, max_cut)
        cut = np.minimum(cut, 0.5 * drop)            # never below the receiver
        cut = np.where(H > sea_level + 0.5, cut, 0.0)
        H = H - cut.astype(np.float32)
        H = thermal(H, step, talus=talus, iters=thermal_iters, mask=None)
    return H
