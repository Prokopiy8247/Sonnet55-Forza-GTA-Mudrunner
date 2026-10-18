"""
make_hole_mask.py - Landscape visibility holes needed by the road geometry (tunnel mouths + bridge ends).

    "W:\\Blender\\5.2\\python\\bin\\python.exe" -I Tools\\blender\\world\\make_hole_mask.py [out.r8]

Two situations need the Landscape (a surface without thickness) to be hidden:

1. TUNNEL MOUTHS.  The carved terrain rises through the tube cross-section at a portal (the heightmap closes the road with a
   1:0.6 cutting), so the surface would block the view into the tunnel.  Each tunnel chunk lists oriented rectangles
   (`landscape_holes` in Exports/Roads/chunks.json: centre in UE metres, heading of the road, length along the road, width across).
2. BRIDGE ENDS.  The world builder does not carve under bridge runs, so at the first / last 3-12 m of most bridges the natural
   terrain stands up to 0.7 m ABOVE the deck surface (a hump across the carriageway; measured, see ROADS_PIPELINE.md).  The deck
   chunks list the affected s ranges (`deck_buried`); this script derives the heightmap quads that contain such samples.
   (The clean fix is a carve change in Tools/world/carve.py: keep the terrain >= 0.3 m below the deck over the first / last 15 m
   of every bridge run; the holes make the geometry work without it.)

Output: raw uint8, row-major, same layout as the other world rasters (vertex (i, j) at X = i - 2016, Y = j - 2016, array[j, i]);
255 = hole (Landscape visibility layer weight 1.0), 0 = visible.  Default output Exports/Roads/landscape_holes.r8 (16 MB, not tracked
by git by default rules of this project: do not commit it, it is regenerated in seconds).  The same vertex list is stored in
chunks.json (`landscape_hole_vertices`, [[i, j], ...]) so the editor module can apply it without the raster.
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
N = 4033
MARGIN = 0.8       # metres added on every side of a tunnel rectangle (heightmap vertices are 1 m apart)


def rect_vertices(h):
    """Heightmap vertices (i, j) inside one oriented rectangle of a tunnel mouth."""
    cx, cy = h["centre_ue_m"][0], h["centre_ue_m"][1]
    a = math.radians(h["heading_deg"])
    ax, ay = math.cos(a), math.sin(a)                 # UE compass heading: 0 = +X, 90 = +Y
    half_l = h["length_m"] / 2.0 + MARGIN
    half_w = h["width_m"] / 2.0 + MARGIN
    r = half_l + half_w
    i0, i1 = int(max(0, math.floor(cx + 2016 - r))), int(min(N - 1, math.ceil(cx + 2016 + r)))
    j0, j1 = int(max(0, math.floor(cy + 2016 - r))), int(min(N - 1, math.ceil(cy + 2016 + r)))
    ii, jj = np.meshgrid(np.arange(i0, i1 + 1), np.arange(j0, j1 + 1))
    dx, dy = ii - 2016 - cx, jj - 2016 - cy
    along = dx * ax + dy * ay
    lat = -dx * ay + dy * ax
    inside = (np.abs(along) <= half_l) & (np.abs(lat) <= half_w)
    return np.stack([ii[inside], jj[inside]], -1)


def hole_vertices(holes=None, plan=None):
    """All hole vertices: tunnel rectangles + bridge-end quads.  Returns (n, 2) int array (i, j), unique, sorted."""
    sys.path.insert(0, HERE)
    import roadbuild as rb
    parts = []
    if holes is None:
        man = json.load(open(os.path.join(ROOT, "Exports", "Roads", "chunks.json"), "r", encoding="utf8"))
        holes = man.get("landscape_holes", [])
    for h in holes:
        parts.append(rect_vertices(h))
    plan = plan or rb.make_plan(kinds=["bridge"])
    for c in plan["chunks"]:
        if c["kind"] != "bridge":
            continue
        v = rb.bridge_buried(plan, c)["vertices"]
        if len(v):
            parts.append(v[(v[:, 0] >= 0) & (v[:, 0] < N) & (v[:, 1] >= 0) & (v[:, 1] < N)])
    if not parts:
        return np.zeros((0, 2), int)
    return np.unique(np.concatenate(parts), axis=0)


def main(out=None):
    v = hole_vertices()
    mask = np.zeros((N, N), np.uint8)
    mask[v[:, 1], v[:, 0]] = 255
    out = out or os.path.join(ROOT, "Exports", "Roads", "landscape_holes.r8")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    mask.tofile(out)
    print("landscape holes: %d vertices -> %s" % (len(v), out))
    return mask


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
