"""
zebra.py - side-effect-free surface-quality inspector (reflection stripes) for the Blender -> Unreal car pipeline.

Casts camera rays with a BVH tree against the CURRENT mesh of an object (including custom split normals), reflects them with
the interpolated corner normals and colours the pixel by a stripe pattern of the reflected direction - exactly what a "zebra
analysis" in an automotive modeller does.  Wavy / pinched / kinked surfaces show up as wavy or broken stripes.  Nothing in the
scene is touched (no render settings, no selection): the picture is computed with numpy and written to a PNG with a temporary
image datablock that is removed again.

    exec(compile(open(ZEBRA, encoding='utf8').read(), ZEBRA, 'exec'), globals())
    zebra('car01_hatch_pulse_Body', eye_dir=(-1, -1, 0.3), target=(10.0, 0, 0.8), dist=5.5, fov=28, size=(640, 400),
          out=r'C:/tmp/z.png', pattern='h')

pattern: 'h' horizontal bands (reflection elevation), 'v' vertical bands (azimuth), 'd' diagonal, 'c' checker.
"""
import bpy
import math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def _mesh_arrays(ob):
    me = ob.data
    me.calc_loop_triangles()
    nv, nl, nt = len(me.vertices), len(me.loops), len(me.loop_triangles)
    co = np.empty(nv * 3, dtype=np.float32)
    me.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    tv = np.empty(nt * 3, dtype=np.int32)
    me.loop_triangles.foreach_get('vertices', tv)
    tv = tv.reshape(-1, 3)
    tl = np.empty(nt * 3, dtype=np.int32)
    me.loop_triangles.foreach_get('loops', tl)
    tl = tl.reshape(-1, 3)
    cn = np.empty(nl * 3, dtype=np.float32)
    try:
        me.corner_normals.foreach_get('vector', cn)
    except Exception:
        me.calc_normals_split()
        me.loops.foreach_get('normal', cn)
    cn = cn.reshape(-1, 3)
    mw = np.array(ob.matrix_world, dtype=np.float32)
    co_w = co @ mw[:3, :3].T + mw[:3, 3]
    nm = mw[:3, :3]
    cn_w = cn @ np.linalg.inv(nm).T
    cn_w /= np.maximum(np.linalg.norm(cn_w, axis=1, keepdims=True), 1e-9)
    return co_w, tv, tl, cn_w


def zebra(obj_names, eye_dir=(-1, -1, 0.3), target=(0, 0, 0.7), dist=6.0, fov=30.0, size=(640, 400), out=None,
          pattern='h', freq=9.0, aspect_fix=True, background=(0.16, 0.16, 0.17)):
    """Render a zebra-reflection picture of one or several mesh objects.  Returns the written path (or the numpy image)."""
    if isinstance(obj_names, str):
        obj_names = [obj_names]
    bpy.context.view_layer.update()            # freshly built objects have stale world matrices otherwise
    obs = [bpy.data.objects[n] for n in obj_names]
    cos, tvs, tls, cns = [], [], [], []
    base = 0
    base_l = 0
    for ob in obs:
        co, tv, tl, cn = _mesh_arrays(ob)
        cos.append(co)
        tvs.append(tv + base)
        tls.append(tl + base_l)
        cns.append(cn)
        base += len(co)
        base_l += len(cn)
    co = np.concatenate(cos)
    tv = np.concatenate(tvs)
    tl = np.concatenate(tls)
    cn = np.concatenate(cns)
    bvh = BVHTree.FromPolygons([tuple(map(float, c)) for c in co], [tuple(map(int, t)) for t in tv], all_triangles=True)
    W, H = size
    tgt = Vector(target)
    ed = Vector(eye_dir).normalized()
    eye = tgt + ed * dist
    fwd = (tgt - eye).normalized()
    right = fwd.cross(Vector((0, 0, 1)))
    if right.length < 1e-6:
        right = Vector((1, 0, 0))
    right.normalize()
    up = right.cross(fwd).normalized()
    th = math.tan(math.radians(fov) / 2.0)
    rays = []
    for j in range(H):
        for i in range(W):
            sx = ((i + 0.5) / W * 2 - 1) * th * (W / H)
            sy = (1 - (j + 0.5) / H * 2) * th
            rays.append((fwd + right * sx + up * sy).normalized())
    img = np.empty((H * W, 3), dtype=np.float32)
    img[:] = background
    hit_idx = np.full(H * W, -1, dtype=np.int64)
    hit_loc = np.zeros((H * W, 3), dtype=np.float32)
    dirs = np.zeros((H * W, 3), dtype=np.float32)
    ray_cast = bvh.ray_cast
    for k, d in enumerate(rays):
        loc, nor, idx, dd = ray_cast(eye, d)
        dirs[k] = (d.x, d.y, d.z)
        if loc is not None:
            hit_idx[k] = idx
            hit_loc[k] = (loc.x, loc.y, loc.z)
    m = hit_idx >= 0
    if m.any():
        ti = hit_idx[m]
        p = hit_loc[m]
        a, b, c = co[tv[ti, 0]], co[tv[ti, 1]], co[tv[ti, 2]]
        v0, v1, v2 = b - a, c - a, p - a
        d00 = (v0 * v0).sum(1)
        d01 = (v0 * v1).sum(1)
        d11 = (v1 * v1).sum(1)
        d20 = (v2 * v0).sum(1)
        d21 = (v2 * v1).sum(1)
        den = np.maximum(d00 * d11 - d01 * d01, 1e-18)
        wv = (d11 * d20 - d01 * d21) / den
        ww = (d00 * d21 - d01 * d20) / den
        wu = 1.0 - wv - ww
        n = cn[tl[ti, 0]] * wu[:, None] + cn[tl[ti, 1]] * wv[:, None] + cn[tl[ti, 2]] * ww[:, None]
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        d = dirs[m]
        facing = -(d * n).sum(1)
        n = np.where((facing < 0)[:, None], -n, n)
        r = d - 2.0 * (d * n).sum(1, keepdims=True) * n
        if pattern == 'h':
            t = np.arcsin(np.clip(r[:, 2], -1, 1)) * freq / math.pi * 2.0
            s = (np.floor(t) % 2.0)
        elif pattern == 'v':
            t = np.arctan2(r[:, 1], r[:, 0]) * freq / math.pi
            s = (np.floor(t) % 2.0)
        elif pattern == 'd':
            t = (r[:, 0] * 0.7 + r[:, 1] * 0.5 + r[:, 2] * 1.0) * freq
            s = (np.floor(t) % 2.0)
        else:
            t1 = np.arcsin(np.clip(r[:, 2], -1, 1)) * freq / math.pi * 2.0
            t2 = np.arctan2(r[:, 1], r[:, 0]) * freq / math.pi
            s = (np.floor(t1) + np.floor(t2)) % 2.0
        shade = 0.25 + 0.75 * np.clip(facing, 0, 1) ** 0.4
        col = np.where(s[:, None] > 0.5, 0.93, 0.06) * shade[:, None]
        img[m] = col
    img = img.reshape(H, W, 3)[::-1]          # image rows start at the bottom
    if out is None:
        return img
    rgba = np.ones((H, W, 4), dtype=np.float32)
    rgba[..., :3] = img ** (1.0 / 2.2)         # the image is saved as sRGB-ish
    im = bpy.data.images.new("__zebra_tmp", W, H, alpha=False, float_buffer=False)
    try:
        im.pixels.foreach_set(rgba.ravel())
        im.filepath_raw = out
        im.file_format = 'PNG'
        im.save()
    finally:
        bpy.data.images.remove(im)
    return out


def zebra_car(root_name, out_dir, views=('rear34', 'rearclose', 'side', 'front34', 'top'), size=(720, 450), freq=11, tag='', pattern='h'):
    """Standard zebra picture set of a car (all views are expressed relative to the root empty).  Returns the written paths."""
    import os
    bpy.context.view_layer.update()
    root = bpy.data.objects[root_name]
    body = root_name[:-5] + '_Body'
    c = root.matrix_world.translation
    V = {
        'rear34': ((-1, -0.9, 0.35), (-0.7, -0.1, 0.85), 5.2, 32),
        'rear34L': ((-1, 0.9, 0.35), (-0.7, 0.1, 0.85), 5.2, 32),
        'rearclose': ((-1, -0.75, 0.3), (-1.5, -0.55, 0.9), 2.3, 34),
        'tailview': ((-1, 0, 0.12), (-1.9, 0, 0.75), 4.0, 30),
        'side': ((0, -1, 0.04), (0, 0, 0.75), 7.0, 28),
        'front34': ((1, -0.9, 0.35), (0.8, -0.1, 0.8), 5.2, 32),
        'frontclose': ((1, -0.7, 0.3), (1.4, -0.4, 0.75), 2.4, 34),
        'top': ((0.001, 0, 1), (0, 0, 0.8), 6.0, 34),
        'cowl': ((0.2, -1, 0.5), (0.9, -0.7, 0.9), 2.4, 34),
    }
    out = []
    for v in views:
        ed, tg, d, fv = V[v]
        p = os.path.join(out_dir, "zb%s_%s.png" % (tag, v))
        zebra(body, eye_dir=ed, target=(c.x + tg[0], c.y + tg[1], c.z + tg[2]), dist=d, fov=fv, size=size, out=p, pattern=pattern, freq=freq)
        out.append(p)
    return out
