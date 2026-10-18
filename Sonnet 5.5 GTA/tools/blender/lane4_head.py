"""lane4_head.py - shared head-fitting helpers for hair / hats / glasses / beards (exec after lane4_lib.py + lane4_body.py defs).
The reference head is Body_A's; B/C cranium rings are identical above z=1.66 and within ~1 cm below, so one shell fits all."""
import math
from mathutils import Vector

C4_HEAD_REF = [(1.520, .042, .054, .050), (1.552, .076, .090, .028), (1.600, .096, .110, .014), (1.660, .103, .118, .008),
               (1.725, .100, .118, .004), (1.775, .080, .100, 0.0), (1.800, .044, .064, -.004)]
C4_HP = 2.2


def c4_dirs(a):
    ca, sa = math.cos(a), math.sin(a)
    return (math.copysign(abs(ca) ** (2.0 / C4_HP), ca), math.copysign(abs(sa) ** (2.0 / C4_HP), sa))


def c4_hp(a, z, off=0.0, dy=0.0, dx=0.0):
    """point on the reference head surface at angle a (0=+X right, 90=+Y front) and height z, pushed out by off."""
    rx, ry, cy = c4_interp_rings(C4_HEAD_REF, z)
    ca, sa = c4_dirs(a)
    return Vector(((rx + off) * ca + dx, cy + (ry + off) * sa + dy, z))


def c4_hshell(b, zb, offs, zt=1.808, mat="Hair", n=12, arc=None, cap=True, shift=None, jit=0.0, a0=0.0):
    """Shell hugging the head. zb(a)-> bottom height at angle a. offs: [(t, off)] with t in 0..1 from the bottom edge up to zt.
    arc=(a_start, a_end) builds an open strip (beards); otherwise a closed dome (cap=True adds the crown cap)."""
    if arc is None:
        angs = [a0 + 2 * math.pi * i / n for i in range(n)]
    else:
        angs = [arc[0] + (arc[1] - arc[0]) * i / (n - 1) for i in range(n)]
    rings = []
    for t, off in offs:
        pts = []
        for ia, a in enumerate(angs):
            z0 = zb(a)
            z = z0 + (zt - z0) * t
            dx = dy = 0.0
            if shift:
                dx, dy = shift[0] * t * t, shift[1] * t * t
            pts.append(c4_hp(a, z, off + (jit * (1 if ia % 2 else -1) * math.sin(math.pi * t) if jit else 0.0), dy, dx))
        rings.append(pts)
    if arc is None:
        capm = (mat[-1] if isinstance(mat, (list, tuple)) else mat)
        return b.loft2(rings, mat, cap0=None, cap1=(capm if cap else None))
    return b.loft2(rings, mat, closed=False)


def c4_tube(b, path, radii, n=6, mat="Hair", caps=True, squash=1.0, ang0=0.0):
    """Round tapered tube along a polyline (3D points) with per-point radii."""
    rings = []
    for i, c in enumerate(path):
        c = Vector(c)
        a = Vector(path[max(0, i - 1)]); d = Vector(path[min(len(path) - 1, i + 1)])
        T = (d - a).normalized()
        N = C4_X.cross(T)
        if N.length < 1e-4:
            N = C4_Y.cross(T)
        N.normalize()
        B = T.cross(N)
        rings.append(c4_ring(c, N, B, radii[i], radii[i] * squash, n, ang0))
    return b.loft2(rings, mat, cap0=(mat if caps else None), cap1=(mat if caps else None))


def c4_new(name):
    b = CB(name)
    b.cur = T_HEAD
    return b


def c4_head_only(obj_builder_name, b):
    return c4_finish(b, obj_builder_name, rigid="Head")
