"""Shared helpers of the placement generator (agent P1): raster world access, road model, oriented rectangles, record store + writer.
Plain Python + numpy (run with  "W:\\Blender\\5.2\\python\\bin\\python.exe" -I  Tools/ue/placement_gen.py ).  All world coordinates are UE metres
(X north, Y east, Z up, origin = map centre); the writer converts to centimetres.  Yaw = compass heading in degrees (0 = +X, 90 = +Y), which is also the UE yaw.
"""
import json
import math
import os
import struct

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = ROOT + "/Content/Forza/World/Source"
OUT = ROOT + "/Content/Forza/World/Placements"
N = 4033
HALF = 2016
CELL = 256.0
GRID = 2.0                       # resolution of the distance fields (m)
GM = int(round(2 * HALF / GRID)) + 1


def u8(name):
    return np.fromfile("%s/%s" % (SRC, name), dtype=np.uint8).reshape(N, N)


class World:
    """Heightmap + masks; arrays are [j (Y), i (X)] like the raw files."""

    def __init__(self):
        h = np.fromfile(SRC + "/heightmap_4033.r16", dtype="<u2").reshape(N, N)
        self.Z = ((h.astype(np.float32) - 32768.0) * 300.0 / 128.0 / 100.0)
        self.forest = u8("density_forest.r8")
        self.scrub = u8("density_scrub.r8")
        self.crops = u8("density_crops.r8")
        self.slope = u8("slope.r8")
        self.region = u8("region_id.r8")
        self.sand = u8("layer_Sand.r8")
        self.farm = u8("layer_Farmland.r8")
        self.rock = u8("layer_Rock.r8")
        self.snow = u8("layer_Snow.r8")
        self.meta = json.load(open(SRC + "/world_meta.json", encoding="utf-8"))
        self.roads_json = json.load(open(SRC + "/roads.json", encoding="utf-8"))
        try:
            self.river = json.load(open(SRC + "/river.json", encoding="utf-8"))
        except OSError:
            self.river = {"river": {"points": []}, "streams": []}
        self.sites = {s["name"]: s for s in self.meta.get("sites", [])}

    # --- sampling --------------------------------------------------------------------------------------------------
    def zat(self, x, y):
        """Bilinear terrain height (m) at UE metres x, y (scalars or arrays)."""
        fx = np.clip(np.asarray(x, dtype=np.float64) + HALF, 0, N - 1.001)
        fy = np.clip(np.asarray(y, dtype=np.float64) + HALF, 0, N - 1.001)
        i0 = fx.astype(np.int64)
        j0 = fy.astype(np.int64)
        tx = (fx - i0).astype(np.float32)
        ty = (fy - j0).astype(np.float32)
        z = self.Z
        a = z[j0, i0] * (1 - tx) + z[j0, i0 + 1] * tx
        b = z[j0 + 1, i0] * (1 - tx) + z[j0 + 1, i0 + 1] * tx
        return a * (1 - ty) + b * ty

    def near(self, arr, x, y):
        i = np.clip(np.rint(np.asarray(x) + HALF).astype(np.int64), 0, N - 1)
        j = np.clip(np.rint(np.asarray(y) + HALF).astype(np.int64), 0, N - 1)
        return arr[j, i]

    def slope_deg(self, x, y):
        return self.near(self.slope, x, y).astype(np.float32) * 90.0 / 255.0

    def downhill_yaw(self, x, y):
        """Compass yaw (deg) of the steepest descent at (x, y) (arrays)."""
        e = 2.0
        gx = (self.zat(x + e, y) - self.zat(x - e, y)) / (2 * e)
        gy = (self.zat(x, y + e) - self.zat(x, y - e)) / (2 * e)
        return np.degrees(np.arctan2(-gy, -gx))


class Field:
    """Min-distance raster (GRID m): value = min over splatted points of (distance to point - radius_of_point)."""

    def __init__(self, reach):
        self.v = np.full((GM, GM), 999.0, dtype=np.float32)
        self.reach = reach
        self.axis = (np.arange(GM, dtype=np.float32) * GRID - HALF)

    def splat(self, px, py, sub):
        r = int(math.ceil(self.reach / GRID))
        sub = np.broadcast_to(np.asarray(sub, dtype=np.float32), np.shape(px))
        ax = self.axis
        v = self.v
        for x, y, s in zip(px, py, sub):
            ci = int(round((x + HALF) / GRID))
            cj = int(round((y + HALF) / GRID))
            i0, i1 = max(ci - r, 0), min(ci + r + 1, GM)
            j0, j1 = max(cj - r, 0), min(cj + r + 1, GM)
            if i0 >= i1 or j0 >= j1:
                continue
            d = np.hypot(ax[i0:i1][None, :] - x, ax[j0:j1][:, None] - y) - s
            np.minimum(v[j0:j1, i0:i1], d, out=v[j0:j1, i0:i1])

    def at(self, x, y):
        i = np.clip(np.rint((np.asarray(x) + HALF) / GRID).astype(np.int64), 0, GM - 1)
        j = np.clip(np.rint((np.asarray(y) + HALF) / GRID).astype(np.int64), 0, GM - 1)
        return self.v[j, i]


# ---------------------------------------------------------------------------------------------------------------------
class Road:
    def __init__(self, d):
        a = np.array(d["samples"], dtype=np.float64)
        self.d = d
        self.id = d["id"]
        self.cls = d["class"]
        self.bed = float(d["bed_half_width"])
        self.paved = float(d["paved_width"])
        self.speed = int(d["speed_limit_kmh"])
        self.surface = d.get("surface", "asphalt")
        self.length = float(d["length_m"])
        self.S, self.X, self.Y, self.Zc = a[:, 0], a[:, 1], a[:, 2], a[:, 3]
        self.K, self.B, self.F = a[:, 5], a[:, 6], a[:, 8].astype(np.int64)
        self.n = len(a)
        dx, dy = np.gradient(self.X), np.gradient(self.Y)
        self.TH = np.arctan2(dy, dx)
        self.idx = np.arange(self.n, dtype=np.float64)
        self.grade = np.gradient(self.Zc) / np.maximum(np.gradient(self.S), 1e-6)

    def fi(self, s):
        return np.interp(s, self.S, self.idx)

    def pos(self, s, lat=0.0):
        """(x, y, z_bed, th_rad) at arc length s (array ok), lateral offset lat (m, right of travel > 0)."""
        f = self.fi(s)
        x0 = np.interp(f, self.idx, self.X)
        y0 = np.interp(f, self.idx, self.Y)
        zc = np.interp(f, self.idx, self.Zc)
        bank = np.interp(f, self.idx, self.B)
        th = np.arctan2(np.interp(f, self.idx, np.sin(self.TH)), np.interp(f, self.idx, np.cos(self.TH)))
        x = x0 - lat * np.sin(th)
        y = y0 + lat * np.cos(th)
        z = zc - 0.05 - np.tan(np.radians(bank)) * lat
        return x, y, z, th

    def flag_at(self, s, bit):
        return (self.F[np.clip(np.rint(self.fi(s)).astype(np.int64), 0, self.n - 1)] & bit) != 0


def runs(mask, gap=0, minlen=1):
    """Contiguous True runs of a boolean array as (i0, i1) inclusive, gaps <= gap merged, runs shorter than minlen dropped."""
    idx = np.flatnonzero(mask)
    out = []
    if len(idx) == 0:
        return out
    a = b = idx[0]
    for i in idx[1:]:
        if i - b <= gap + 1:
            b = i
        else:
            out.append((a, b))
            a = b = i
    out.append((a, b))
    return [(a, b) for a, b in out if b - a + 1 >= minlen]


# ---------------------------------------------------------------------------------------------------------------------
def rot(yaw_deg, lx, ly):
    c, s = math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))
    return lx * c - ly * s, lx * s + ly * c


class Rect:
    """Oriented rectangle: centre (cx, cy), half sizes (hx along local X, hy along local Y), yaw degrees."""

    def __init__(self, cx, cy, hx, hy, yaw):
        self.cx, self.cy, self.hx, self.hy, self.yaw = cx, cy, hx, hy, yaw
        self.ux = (math.cos(math.radians(yaw)), math.sin(math.radians(yaw)))
        self.uy = (-self.ux[1], self.ux[0])

    def corners(self, grow=0.0):
        out = []
        for sx, sy in ((1, 1), (1, -1), (-1, -1), (-1, 1)):
            lx, ly = sx * (self.hx + grow), sy * (self.hy + grow)
            out.append((self.cx + lx * self.ux[0] + ly * self.uy[0], self.cy + lx * self.ux[1] + ly * self.uy[1]))
        return out

    def radius(self):
        return math.hypot(self.hx, self.hy)

    def overlaps(self, o, margin=0.0):
        if math.hypot(self.cx - o.cx, self.cy - o.cy) > self.radius() + o.radius() + margin:
            return False
        for r in (self, o):
            for ax in (r.ux, r.uy):
                a = [c[0] * ax[0] + c[1] * ax[1] for c in self.corners(margin * 0.5)]
                b = [c[0] * ax[0] + c[1] * ax[1] for c in o.corners(margin * 0.5)]
                if max(a) < min(b) or max(b) < min(a):
                    return False
        return True

    def grid(self, step=2.5, grow=0.0):
        nx = max(int((self.hx + grow) * 2 / step), 1)
        ny = max(int((self.hy + grow) * 2 / step), 1)
        lx = np.linspace(-(self.hx + grow), self.hx + grow, nx + 1)
        ly = np.linspace(-(self.hy + grow), self.hy + grow, ny + 1)
        LX, LY = np.meshgrid(lx, ly)
        X = self.cx + LX * self.ux[0] + LY * self.uy[0]
        Y = self.cy + LX * self.ux[1] + LY * self.uy[1]
        return X.ravel(), Y.ravel()

    def boundary(self, step=3.0, grow=0.0):
        pts = []
        cs = self.corners(grow)
        for a, b in zip(cs, cs[1:] + cs[:1]):
            n = max(int(math.hypot(b[0] - a[0], b[1] - a[1]) / step), 1)
            for k in range(n):
                t = k / n
                pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        pts.append((self.cx, self.cy))
        arr = np.array(pts)
        return arr[:, 0], arr[:, 1]


# ---------------------------------------------------------------------------------------------------------------------
class Store:
    """Collects instances per group: (asset, x, y, z, yaw, pitch, roll, sx, sy, sz) in metres / degrees."""

    def __init__(self):
        self.g = {}

    def add(self, group, asset, x, y, z, yaw=0.0, pitch=0.0, roll=0.0, sx=1.0, sy=None, sz=None):
        sy = sx if sy is None else sy
        sz = sx if sz is None else sz
        self.g.setdefault(group, []).append((asset, float(x), float(y), float(z), float(yaw), float(pitch), float(roll), float(sx), float(sy), float(sz)))

    def add_many(self, group, asset, x, y, z, yaw, scale, pitch=None, roll=None):
        lst = self.g.setdefault(group, [])
        x, y, z, yaw, scale = [np.asarray(v, dtype=np.float64).ravel() for v in (x, y, z, yaw, scale)]
        pitch = np.zeros_like(x) if pitch is None else pitch
        roll = np.zeros_like(x) if roll is None else roll
        for k in range(len(x)):
            lst.append((asset, x[k], y[k], z[k], yaw[k], pitch[k], roll[k], scale[k], scale[k], scale[k]))

    def count(self, group=None):
        return len(self.g.get(group, [])) if group else sum(len(v) for v in self.g.values())


def write_group(outdir, name, rows, assets):
    """Binary file <name>.f32 (10 float32 per instance: asset index, x/y/z in cm, yaw, pitch, roll, sx, sy, sz), sorted by (cell, asset).
    Returns the index dict entry (count, per-cell [start, count], per-asset counts)."""
    ai = {a: i for i, a in enumerate(assets)}
    if not rows:
        open("%s/%s.f32" % (outdir, name), "wb").close()
        return {"file": name + ".f32", "count": 0, "record": 10, "cells": {}, "assets": {}}
    arr = np.array([(ai[r[0]],) + tuple(r[1:]) for r in rows], dtype=np.float64)
    cx = np.clip(((arr[:, 1] + HALF) // CELL).astype(np.int64), 0, 15)
    cy = np.clip(((arr[:, 2] + HALF) // CELL).astype(np.int64), 0, 15)
    cell = cx * 16 + cy
    order = np.lexsort((arr[:, 0], cell))
    arr, cell = arr[order], cell[order]
    out = arr.copy()
    out[:, 1:4] *= 100.0                       # metres -> cm
    out.astype("<f4").tofile("%s/%s.f32" % (outdir, name))
    cells = {}
    uc, st, ct = np.unique(cell, return_index=True, return_counts=True)
    for c, s, n in zip(uc, st, ct):
        cells["%d,%d" % (c // 16, c % 16)] = [int(s), int(n)]
    per_asset = {assets[int(a)]: int(n) for a, n in zip(*np.unique(arr[:, 0], return_counts=True))}
    return {"file": name + ".f32", "count": int(len(arr)), "record": 10, "cells": cells, "assets": per_asset}
