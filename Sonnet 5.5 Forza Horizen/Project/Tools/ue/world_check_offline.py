"""world_check_offline - sanity check of the generator output against the orientation/encoding assumptions of the UE import (plain python + numpy).
Owner: F1-B.   "W:\\Blender\\5.2\\python\\bin\\python.exe" -I Tools/ue/world_check_offline.py [--tol 1.0]

Reads Content/Forza/World/Source/{heightmap_4033.r16, roads.json, world_meta.json, layer_*.r8} and checks
  * file sizes (4033^2 x 2 / x 1 bytes), weight maps sum to 255 per vertex (sampled),
  * orientation: the bilinear terrain height under every road sample (column = x + 2016, row = y + 2016, the layout RoamWorldBuilder imports
    without flips) equals the road z of roads.json -> max/mean deviation per road class (the heightmap is carved to the road bed),
  * sea level: fraction of vertices below 0 m, min / max height.
Exit code 1 when a check fails.
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "Content", "Forza", "World", "Source")
N = 4033
HALF = (N - 1) // 2


def main():
    tol = 1.0
    if "--tol" in sys.argv:
        tol = float(sys.argv[sys.argv.index("--tol") + 1])
    failures = 0
    meta = json.load(open(os.path.join(SRC, "world_meta.json"), "r", encoding="utf-8"))
    layers = meta["layers"]["order"]

    raw = np.fromfile(os.path.join(SRC, "heightmap_4033.r16"), dtype="<u2")
    if raw.size != N * N:
        print("FAIL heightmap has %d values, expected %d" % (raw.size, N * N))
        return 1
    h = ((raw.astype(np.float64) - 32768.0) * 300.0 / 128.0 / 100.0).reshape(N, N)   # metres, [row = Y, column = X]
    print("height range %.1f .. %.1f m, below sea level (z<0): %.1f %% of the vertices" % (h.min(), h.max(), 100.0 * float((h < 0).mean())))

    # weight maps: 8 layers sum to 255 (sampled on a stride to stay fast)
    total = None
    for name in layers:
        arr = np.fromfile(os.path.join(SRC, "layer_%s.r8" % name), dtype=np.uint8)
        if arr.size != N * N:
            print("FAIL layer %s has %d bytes, expected %d" % (name, arr.size, N * N))
            failures += 1
            continue
        a = arr.reshape(N, N)[::7, ::7].astype(np.int32)
        total = a if total is None else total + a
        print("layer %-11s mean weight %.1f / 255" % (name, a.mean()))
    if total is not None:
        bad = float((total != 255).mean())
        print("weights sum to 255 on %.2f %% of the sampled vertices (min %d max %d)" % (100.0 * (1.0 - bad), total.min(), total.max()))
        if bad > 0.01:
            print("FAIL layer weights do not sum to 255")
            failures += 1

    roads = json.load(open(os.path.join(SRC, "roads.json"), "r", encoding="utf-8"))
    per_class = {}
    for road in roads["roads"]:
        s = np.array([[row[1], row[2], row[3]] for row in road["samples"]], dtype=np.float64)
        col = s[:, 0] + HALF
        rw = s[:, 1] + HALF
        c0 = np.clip(np.floor(col).astype(int), 0, N - 2)
        r0 = np.clip(np.floor(rw).astype(int), 0, N - 2)
        fc = col - c0
        fr = rw - r0
        z = (h[r0, c0] * (1 - fc) * (1 - fr) + h[r0, c0 + 1] * fc * (1 - fr) + h[r0 + 1, c0] * (1 - fc) * fr + h[r0 + 1, c0 + 1] * fc * fr)
        d = z - s[:, 2]
        per_class.setdefault(road["class"], []).append((road["id"], float(np.abs(d).max()), float(np.abs(d).mean()), float(d.mean())))
    worst = 0.0
    for cls, rows in sorted(per_class.items()):
        mx = max(r[1] for r in rows)
        worst = max(worst, mx)
        wr = max(rows, key=lambda r: r[1])
        print("class %-9s roads=%2d  max|terrain-road| %.2f m (%s)  mean|.| %.3f m  mean signed %.3f m" % (
            cls, len(rows), mx, wr[0], sum(r[2] for r in rows) / len(rows), sum(r[3] for r in rows) / len(rows)))
    if worst > tol:
        print("FAIL terrain deviates from the road bed by up to %.2f m (> %.2f): wrong orientation/encoding or the carve is off" % (worst, tol))
        failures += 1
    else:
        print("OK  orientation/encoding: terrain follows the roads within %.2f m" % worst)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
