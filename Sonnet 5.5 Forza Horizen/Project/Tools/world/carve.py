"""Terrain carving around the road network.

Every road segment contributes a road bed (profile z - 0.05 m, with banking, flat across road + shoulders) and two
slope cones: a cut cone rising at 1:2 and a fill cone falling at 1:3 beyond the bed edge. The carved terrain is
    h = max( max_k F_k ,  min( h_natural , min_k C_k ) )
which is continuous, never buries another road and gives exact bed heights. Cones fade out over the last 30 % of their
adaptive reach so they blend into the natural terrain with a smoothstep. Segments flagged BRIDGE are not carved (natural
terrain stays below the deck); TUNNEL segments are not carved except for short steep portal cuttings. The first / last 15 m of every bridge run get a terrain
ceiling 0.3 m below the deck (the Blender road builder would otherwise need a landscape hole for the hump of natural terrain there).
The flat bed is BED_BAND wider than RD.bed_half_width (cones start beyond it).
"""
import math

import numpy as np

import roads_def as RD
import profile as PR
from common import HALF, N, ss, sample_bilinear, log, gauss_blur

CUT_SLOPE = 0.5          # 1:2
FILL_SLOPE = 1.0 / 3.0   # 1:3
# steep ground (mountain / dirt roads): rock cuttings and steeper embankments. (cut slope, fill slope, max reach m)
SLOPES = {"MOUNTAIN": (1.0, 0.9, 60.0), "DIRT": (0.8, 0.7, 50.0), "SHORTCUT": (0.8, 0.7, 50.0)}
PORTAL_CUT_SLOPE = 1.6   # steep rock cutting at tunnel portals
PORTAL_LEN = 36.0
BED_OFFSET = 0.05
BED_BAND = 1.3           # m: the flat bed (paved + shoulder) is carved this much wider than the shoulder edge, so that a retaining wall /
#                          embankment of a neighbouring leg never starts exactly at the shoulder edge (bilinear samples stay on the bed)
BRIDGE_END_LEN = 15.0    # m: first / last stretch of every bridge run where the terrain is kept below the deck
BRIDGE_CLEAR = 0.3       # m: ... at least this far below the deck surface (no hump of natural terrain through the deck ends)
MAX_REACH = 46.0
CLASS_ID = {"HIGHWAY": 1, "REGIONAL": 2, "MOUNTAIN": 3, "DIRT": 4, "SHORTCUT": 5, "VILLAGE": 6}


def adaptive_reach(H1, xy, z, d0, bank_tan, hd_x, hd_y, cut_slope=CUT_SLOPE, fill_slope=FILL_SLOPE, max_reach=MAX_REACH):
    """for every sample: distance beyond the bed edge at which the cut / fill cones meet the natural terrain
    (max over both sides), capped at MAX_REACH."""
    n = len(z)
    rx = -hd_y
    ry = hd_x
    offs = d0 + np.arange(1.0, max_reach + 1.0, 3.0)         # lateral sample distances from the centre line
    reach = np.zeros(n)
    for side in (+1.0, -1.0):
        px = xy[:, 0:1] + side * rx[:, None] * offs[None, :]
        py = xy[:, 1:2] + side * ry[:, None] * offs[None, :]
        h = sample_bilinear(H1, px, py)
        bed_e = (z - BED_OFFSET - bank_tan * side * d0)[:, None]
        e = (offs - d0)[None, :]
        C = bed_e + cut_slope * e
        F = bed_e - fill_slope * e
        inside = (h <= C + 0.05) & (h >= F - 0.05)        # daylight reached
        first = np.where(inside.any(1), np.argmax(inside, axis=1), len(offs) - 1)
        e_need = (offs - d0)[first]
        reach = np.maximum(reach, e_need)
    return np.clip(reach + 5.0, 8.0, max_reach)


def _cap_segment(Cap, XS, A, B, za, zb, ba, bb, d0):
    """lower the ceiling `Cap` (in place) to the deck-minus-clearance surface over the strip of half width d0 around segment A-B"""
    R = d0 + 1.0
    i0 = max(0, int(math.floor(min(A[0], B[0]) - R + HALF)))
    i1 = min(N - 1, int(math.ceil(max(A[0], B[0]) + R + HALF)))
    j0 = max(0, int(math.floor(min(A[1], B[1]) - R + HALF)))
    j1 = min(N - 1, int(math.ceil(max(A[1], B[1]) + R + HALF)))
    if i1 < i0 or j1 < j0:
        return
    px = XS[i0:i1 + 1][None, :] - np.float32(A[0])
    py = XS[j0:j1 + 1][:, None] - np.float32(A[1])
    dx, dy = float(B[0] - A[0]), float(B[1] - A[1])
    L2 = dx * dx + dy * dy
    if L2 < 1e-9:
        return
    t_raw = (px * np.float32(dx) + py * np.float32(dy)) / np.float32(L2)
    t = np.clip(t_raw, 0.0, 1.0)
    ex = px - t * np.float32(dx)
    ey = py - t * np.float32(dy)
    dist = np.sqrt(ex * ex + ey * ey)
    Lh = math.sqrt(L2)
    o = (ey * np.float32(dx / Lh) - ex * np.float32(dy / Lh))
    zc = np.float32(za) + t * np.float32(zb - za)
    bt = np.float32(ba) + t * np.float32(bb - ba)
    # a strip, not a capsule: nothing is lowered behind the first / beyond the last deck segment (the approach road keeps its bed)
    inside = (dist <= np.float32(d0 + 0.5)) & (t_raw >= 0.0) & (t_raw <= 1.0)
    ceil_ = np.where(inside, zc - bt * np.clip(o, -d0, d0), np.float32(np.inf))
    np.minimum(Cap[j0:j1 + 1, i0:i1 + 1], ceil_, out=Cap[j0:j1 + 1, i0:i1 + 1])


def carve(H1, roads, verbose=True):
    """returns dict(H=carved heights, emin=distance beyond bed edge (0 on the bed), cls=class id of the nearest bed,
    d0=half bed width at nearest bed)"""
    H = H1.astype(np.float32).copy()
    Cmin = np.full(H.shape, np.inf, dtype=np.float32)
    Fmax = np.full(H.shape, -np.inf, dtype=np.float32)
    Emin = np.full(H.shape, 1e4, dtype=np.float32)
    Dmin = np.full(H.shape, 1e4, dtype=np.float32)
    Bed = np.zeros(H.shape, dtype=np.float32)
    Cls = np.zeros(H.shape, dtype=np.uint8)
    D0 = np.zeros(H.shape, dtype=np.float32)
    XS = (np.arange(N, dtype=np.float32) - np.float32(HALF))
    Cap = np.full(H.shape, np.inf, dtype=np.float32)       # terrain ceiling under the bridge ends (deck - BRIDGE_CLEAR)
    nseg_total = 0
    for rd in roads:
        cls = rd["cls"]
        d0 = RD.bed_half_width(cls) + BED_BAND
        xy = rd["xy"]
        z = rd["z"].astype(np.float64)
        bank = np.tan(rd["bank"])
        fl = rd["flags"]
        n = len(z)
        # tangent for reach estimation
        hd = np.empty_like(xy)
        hd[1:-1] = xy[2:] - xy[:-2]
        hd[0] = xy[1] - xy[0]
        hd[-1] = xy[-1] - xy[-2]
        hd /= np.maximum(np.linalg.norm(hd, axis=1, keepdims=True), 1e-9)
        cut_s0, fill_s0, max_r0 = SLOPES.get(cls, (CUT_SLOPE, FILL_SLOPE, MAX_REACH))
        reach = adaptive_reach(H1, xy, z, d0, bank, hd[:, 0], hd[:, 1], cut_s0, fill_s0, max_r0)
        bridge = (fl & PR.FLAG_BRIDGE) > 0
        tunnel = (fl & PR.FLAG_TUNNEL) > 0
        # portal zones inside tunnels
        s = rd["s"]
        portal = np.zeros(n, dtype=bool)
        for a, b in PR.runs(tunnel):
            m = (s >= s[a]) & (s <= s[a] + PORTAL_LEN)
            portal |= m
            m = (s >= s[b] - PORTAL_LEN) & (s <= s[b])
            portal |= m
        # bridge ends: the first / last BRIDGE_END_LEN m of every bridge run (whole run when it is shorter than twice that)
        endz = np.zeros(n, dtype=bool)
        for a, b in PR.runs(bridge):
            endz |= bridge & (((s >= s[a]) & (s <= s[a] + BRIDGE_END_LEN)) | ((s >= s[b] - BRIDGE_END_LEN) & (s <= s[b])))
        stride = 2
        idx = list(range(0, n - 1, stride))
        if idx[-1] != n - 2 and n - 1 not in idx:
            idx.append(n - 1)
        cid = CLASS_ID[cls]
        for kk in range(len(idx) - 1):
            i, j = idx[kk], idx[kk + 1]
            seg_bridge = bridge[i] and bridge[j]
            seg_tunnel = tunnel[i] and tunnel[j]
            if seg_bridge:
                if endz[i] or endz[j]:
                    _cap_segment(Cap, XS, xy[i], xy[j], z[i] - BRIDGE_CLEAR, z[j] - BRIDGE_CLEAR, bank[i], bank[j], d0)
                continue
            cutS = cut_s0
            if seg_tunnel:
                if not (portal[i] or portal[j]):
                    continue
                cutS = PORTAL_CUT_SLOPE
            A = xy[i]
            B = xy[j]
            za, zb = z[i] - BED_OFFSET, z[j] - BED_OFFSET
            ba, bb = bank[i], bank[j]
            R_e = float(max(reach[i:j + 1]))
            R = d0 + R_e
            i0 = max(0, int(math.floor(min(A[0], B[0]) - R + HALF)))
            i1 = min(N - 1, int(math.ceil(max(A[0], B[0]) + R + HALF)))
            j0 = max(0, int(math.floor(min(A[1], B[1]) - R + HALF)))
            j1 = min(N - 1, int(math.ceil(max(A[1], B[1]) + R + HALF)))
            if i1 < i0 or j1 < j0:
                continue
            px = XS[i0:i1 + 1][None, :] - np.float32(A[0])
            py = XS[j0:j1 + 1][:, None] - np.float32(A[1])
            dx, dy = float(B[0] - A[0]), float(B[1] - A[1])
            L2 = dx * dx + dy * dy
            t = np.clip((px * np.float32(dx) + py * np.float32(dy)) / np.float32(L2), 0.0, 1.0)
            ex = px - t * np.float32(dx)
            ey = py - t * np.float32(dy)
            dist = np.sqrt(ex * ex + ey * ey)
            Lh = math.sqrt(L2)
            o = (ey * np.float32(dx / Lh) - ex * np.float32(dy / Lh))          # signed lateral offset (right positive)
            zc = np.float32(za) + t * np.float32(zb - za)
            bt = np.float32(ba) + t * np.float32(bb - ba)
            oc = np.clip(o, -d0, d0)
            bed = zc - bt * oc
            e = np.maximum(dist - np.float32(d0), 0.0)
            hn = H[j0:j1 + 1, i0:i1 + 1]
            wf = 1.0 - ss(e, np.float32(0.68 * R_e), np.float32(R_e))
            C = bed + np.float32(cutS) * e
            F = bed - np.float32(fill_s0) * e
            C = C + (1.0 - wf) * np.maximum(hn - C, 0.0)
            F = F - (1.0 - wf) * np.maximum(F - hn, 0.0)
            far = e > np.float32(R_e)
            C = np.where(far, np.float32(np.inf), C)
            F = np.where(far, np.float32(-np.inf), F)
            np.minimum(Cmin[j0:j1 + 1, i0:i1 + 1], C, out=Cmin[j0:j1 + 1, i0:i1 + 1])
            np.maximum(Fmax[j0:j1 + 1, i0:i1 + 1], F, out=Fmax[j0:j1 + 1, i0:i1 + 1])
            es = Emin[j0:j1 + 1, i0:i1 + 1]
            np.minimum(es, e, out=es)
            dm = Dmin[j0:j1 + 1, i0:i1 + 1]
            better = dist < dm
            dm[better] = dist[better]
            Bed[j0:j1 + 1, i0:i1 + 1][better] = bed[better]
            Cls[j0:j1 + 1, i0:i1 + 1][better] = cid
            D0[j0:j1 + 1, i0:i1 + 1][better] = d0
            nseg_total += 1
        if verbose:
            log("  carved %-16s (%d segments)" % (rd["id"], len(idx) - 1))
    import os as _os
    if _os.environ.get("CARVE_DBG"):
        qx, qy = [float(v) for v in _os.environ["CARVE_DBG"].split(",")]
        ii, jj = int(round(qx + HALF)), int(round(qy + HALF))
        log("CARVE_DBG pixel (%.0f,%.0f): Dmin %.2f D0 %.2f Bed %.2f Cmin %.2f Fmax %.2f Hnat %.2f Emin %.2f" % (qx, qy, Dmin[jj, ii], D0[jj, ii], Bed[jj, ii], Cmin[jj, ii], Fmax[jj, ii], H[jj, ii], Emin[jj, ii]))
    touched = np.isfinite(Cmin) | np.isfinite(Fmax)
    Cm = np.where(np.isfinite(Cmin), Cmin, np.float32(1e6))
    Fm = np.where(np.isfinite(Fmax), Fmax, np.float32(-1e6))
    new = np.maximum(Fm, np.minimum(H, Cm))
    # the road bed itself comes from the nearest segment only (exact values, no leakage between neighbours)
    bed_mask = touched & (Dmin <= D0 + 1e-3)
    new = np.where(bed_mask, Bed, new)
    # light smoothing of the slope blends (never on / right next to the road bed)
    soft = touched & ~bed_mask
    if soft.any():
        bl = gauss_blur(new, 1.4)
        w = np.where(soft, np.float32(0.55), np.float32(0.0)) * ss(Emin, 0.4, 2.5)
        new = new + w * (bl - new)
    new = np.minimum(new, Cap)                     # bridge ends: the terrain (also the spill-over of the approach bed) stays below the deck
    return dict(H=new.astype(np.float32), emin=Emin, cls=Cls, d0=D0, touched=touched, bed_mask=bed_mask)
