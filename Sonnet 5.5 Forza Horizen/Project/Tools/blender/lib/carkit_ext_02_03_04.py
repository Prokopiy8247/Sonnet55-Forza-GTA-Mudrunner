"""
carkit_ext_02_03_04.py - extra helpers for the player cars 02 Cadence / 03 Thunderline / 04 Vesper.
Load AFTER carkit.py into the same namespace (the car scripts do this):
    exec(compile(open(EXT, encoding="utf8").read(), EXT, "exec"), globals())
Nothing here edits carkit.py; everything is built on its public functions (and a few of its private ones).
"""
import math
import time
import bpy
import bmesh
from mathutils import Vector, Matrix


# ----------------------------------------------------------------------------------------------------------------------
# build bookkeeping
# ----------------------------------------------------------------------------------------------------------------------
class Build:
    """Collects boolean cutters and add-on inserts of one car build."""

    def __init__(self, tag):
        self.tag = tag
        self.t0 = time.time()
        self.cutters = []
        self.inserts = []

    def lap(self, msg):
        print("[%s %.2fs] %s" % (self.tag, time.time() - self.t0, msg))

    def keep(self, b):
        if b is not None:
            self.inserts.append(b)
        return b

    def cut(self, b):
        if b is not None:
            self.cutters.append(b)
        return b

    def pair(self, bm_left, into=None):
        """left bmesh + its mirror image -> cutters (or `into` list)"""
        tgt = self.cutters if into is None else into
        if bm_left is None:
            return
        tgt.append(mirrored_copy(bm_left))
        tgt.append(bm_left)

    def pair_in(self, bm_left):
        self.pair(bm_left, into=self.inserts)


def ring_pt(shell, x, name):
    """(y, z) of a named ring control point at station x"""
    return dict(ring_controls(shell.cv, x))[name]


def edge_y(shell, x):
    return ring_pt(shell, x, 'edge')[0]


def bounds_obj(ob):
    vs = [v.co for v in ob.data.vertices]
    return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
            Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


# ----------------------------------------------------------------------------------------------------------------------
# 2-D helpers
# ----------------------------------------------------------------------------------------------------------------------
def rounded_poly(pts, radii, n=5):
    """Closed polygon [(x, z), ...] with a circular fillet (radius, or per-vertex list) at every vertex -> dense point list."""
    N = len(pts)
    if not isinstance(radii, (list, tuple)):
        radii = [radii] * N
    out = []
    for i in range(N):
        B = Vector((pts[i][0], pts[i][1], 0.0))
        A = Vector((pts[i - 1][0], pts[i - 1][1], 0.0))
        C = Vector((pts[(i + 1) % N][0], pts[(i + 1) % N][1], 0.0))
        u1, u2 = A - B, C - B
        l1, l2 = u1.length, u2.length
        u1.normalize()
        u2.normalize()
        th = math.acos(clamp(u1.dot(u2), -1.0, 1.0))
        r = radii[i]
        if r <= 1e-9 or th > math.pi - 1e-4 or th < 1e-4:
            out.append((B.x, B.y))
            continue
        t = min(r / math.tan(th / 2.0), 0.48 * l1, 0.48 * l2)
        r = t * math.tan(th / 2.0)
        T1, T2 = B + u1 * t, B + u2 * t
        Cc = B + (u1 + u2).normalized() * (r / math.sin(th / 2.0))
        a1 = math.atan2(T1.y - Cc.y, T1.x - Cc.x)
        a2 = math.atan2(T2.y - Cc.y, T2.x - Cc.x)
        da = a2 - a1
        while da > math.pi:
            da -= 2 * math.pi
        while da < -math.pi:
            da += 2 * math.pi
        for k in range(n + 1):
            a = a1 + da * k / n
            out.append((Cc.x + r * math.cos(a), Cc.y + r * math.sin(a)))
    return out


def sweep_loop(surf, poly_xz, ray, profile, mat='M_Chrome', step=0.03, y=0.0, closed=True):
    """surface_sweep along a (closed) polyline given as [(x, z), ...] (projected with `ray`)"""
    pts = [Vector((p[0], y, p[1])) for p in poly_xz]
    if closed:
        pts = resample_poly(pts + [pts[0]], step)[:-1]
    else:
        pts = resample_poly(pts, step)
    return surface_sweep(surf, pts, ray, profile, closed=closed, mat=mat)


def sweep_xy(surf, pts_xy, ray, profile, mat='M_Chrome', step=0.03, closed=False):
    """surface_sweep along a polyline in plan [(x, y), ...] (ray normally (0, 0, -1))"""
    pts = [Vector((p[0], p[1], 0.0)) for p in pts_xy]
    if closed:
        pts = resample_poly(pts + [pts[0]], step)[:-1]
    else:
        pts = resample_poly(pts, step)
    return surface_sweep(surf, pts, ray, profile, closed=closed, mat=mat)


def sweep_yz(surf, pts_yz, x, ray, profile, mat='M_Chrome', step=0.03, closed=False):
    """polyline in the YZ plane at the (ignored) x, ray along +-X"""
    pts = [Vector((x, p[0], p[1])) for p in pts_yz]
    if closed:
        pts = resample_poly(pts + [pts[0]], step)[:-1]
    else:
        pts = resample_poly(pts, step)
    return surface_sweep(surf, pts, ray, profile, closed=closed, mat=mat)


def paint_bands(bm, tc, bands, mat, zmin=0.8, only=None):
    """Recolour bands |y| in [y0, y1] (stripes) of the lofted shell: the shell is bisected exactly at the band edges (the TAG
    attributes survive), then faces whose centre is inside a band and above zmin get `mat`.  `only(face)` optionally
    restricts the faces."""
    ys = sorted(set(round(v, 6) for (a, b) in bands for v in (a, b, -a, -b)))
    for y in ys:
        geom = set()
        for f in bm.faces:
            c = f.calc_center_median()
            if f[tc] != 0 and c.z > zmin - 0.05 and abs(c.y - y) < 0.35:
                geom.add(f)
                geom.update(f.edges)
                geom.update(f.verts)
        if geom:
            bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-6, plane_co=(0, y, 0), plane_no=(0, 1, 0))
    bm.normal_update()
    n = 0
    mm = mi(mat)
    for f in bm.faces:
        if f[tc] == 0:
            continue
        c = f.calc_center_median()
        if c.z < zmin or (only is not None and not only(f)):
            continue
        ay = abs(c.y)
        for (a, b) in bands:
            if a <= ay <= b:
                f.material_index = mm
                n += 1
                break
    return n


def height_field_solid(surf, x0, x1, y_half, nx, ny, hfun, sink=0.012, mat='M_Paint', front_mat='M_TrimBlack', y_fun=None):
    """Closed solid (bulge / scoop / power-dome) lying on the skin: the top is surf(x, y) + h(x, y) (plan projection from
    above), the base is sunk `sink` below the skin.  hfun(u, v) with u in [0,1] along x and v in [-1,1] across y returns the
    height (m); a front wall (towards +X) gets `front_mat`.  y_fun(u) -> half width at u (default y_half)."""
    bm = bmesh.new()
    top, bot = [], []
    for i in range(nx + 1):
        u = i / float(nx)
        x = x0 + (x1 - x0) * u
        yh = y_half if y_fun is None else y_fun(u)
        rt, rb_ = [], []
        for j in range(ny + 1):
            v = -1.0 + 2.0 * j / ny
            y = yh * v
            h = surf.hit(Vector((x, y, 0.0)), (0, 0, -1))
            if h is None:
                bm.free()
                return None
            z0 = h[0].z
            rt.append(bm.verts.new((x, y, z0 + hfun(u, v))))
            rb_.append(bm.verts.new((x, y, z0 - sink)))
        top.append(rt)
        bot.append(rb_)
    mt, mf = mi(mat), mi(front_mat)
    for i in range(nx):
        for j in range(ny):
            f = bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]))
            f.material_index = mt
            f.smooth = True
            f = bm.faces.new((bot[i][j], bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j]))
            f.material_index = mt
    for i in range(nx):                      # side walls
        for (j, k) in ((0, 0), (ny, ny)):
            try:
                f = bm.faces.new((top[i][j], bot[i][j], bot[i + 1][j], top[i + 1][j]) if j == 0 else
                                 (top[i][j], top[i + 1][j], bot[i + 1][j], bot[i][j]))
                f.material_index = mt
            except ValueError:
                pass
    for j in range(ny):                      # end walls (x1 = rear = open ramp, x0 = front wall)
        f = bm.faces.new((top[0][j], top[0][j + 1], bot[0][j + 1], bot[0][j]))
        f.material_index = mf
        f = bm.faces.new((top[nx][j], bot[nx][j], bot[nx][j + 1], top[nx][j + 1]))
        f.material_index = mt
    recalc(bm)
    return bm


# ----------------------------------------------------------------------------------------------------------------------
# wheels: own tyre (profile scaled for low-profile tyres) + new spoke styles
# ----------------------------------------------------------------------------------------------------------------------
def _tyre_ext(R, w, rb, segs, bulge=1.0, groove=0.0065, k=1.0, emboss=True, lug_depth=0.0):
    """Like carkit._tyre (symmetric 4-groove tread + embossed sidewall rings) but the sidewall key offsets are scaled by k so
    that low-profile tyres (19" with 40 % sidewalls) do not fold."""
    w2 = w / 2.0
    sw = [(rb - 0.004 * k, 0.62 * w2), (rb + 0.006 * k, 0.72 * w2), (rb + 0.020 * k, 0.90 * w2 * bulge),
          (rb + 0.052 * k, 0.992 * w2 * bulge), (R - 0.060 * k, 1.0 * w2 * bulge), (R - 0.030 * k, 0.975 * w2),
          (R - 0.014 * k, 0.915 * w2), (R - 0.0035, 0.84 * w2)]
    emb = {rb + 0.034 * k: 0.0022, R - 0.047 * k: 0.0014} if emboss else {}
    rings_at = sorted(emb.items())
    half = []
    for i, (r, y) in enumerate(sw):
        half.append((r, y))
        if i + 1 < len(sw):
            for (re, he) in rings_at:
                if r < re < sw[i + 1][0] - 0.004:
                    for (dr, dy) in ((-0.0035, 0.0), (-0.0024, he), (0.0024, he), (0.0035, 0.0)):
                        half.append((re + dr, _interp(sw, re + dr) + dy))
    g = groove
    wt = w2 / 0.1075                       # tread keys of the kit are for a 0.215 m tyre -> scale with the width
    half += [(R, 0.0865 * wt), (R, 0.0660 * wt), (R - g, 0.0640 * wt), (R - g, 0.0610 * wt), (R, 0.0590 * wt),
             (R, 0.0340 * wt), (R - g, 0.0320 * wt), (R - g, 0.0290 * wt), (R, 0.0270 * wt), (R, 0.0)]
    prof = list(half)
    for (r, y) in reversed(half[:-1]):
        prof.append((r, -y))
    bm = bmesh.new()
    rows = []
    for (r, y) in prof:
        rows.append([bm.verts.new((r * math.cos(2 * math.pi * kk / segs), y, r * math.sin(2 * math.pi * kk / segs)))
                     for kk in range(segs)])
    n = len(prof)
    for i in range(n):
        i2 = (i + 1) % n
        for kk in range(segs):
            k2 = (kk + 1) % segs
            try:
                bm.faces.new((rows[i][kk], rows[i][k2], rows[i2][k2], rows[i2][kk]))
            except ValueError:
                pass
    recalc(bm)
    for f in bm.faces:
        f.material_index = mi('M_Tyre')
    return bm


def build_wheel_ext(radius, width, rim_radius, rim_width, style='ten', spokes=5, brake_disc_radius=0.15, caliper_angle=35.0,
                    side=+1, segments=56, tyre_segments=64, hub_radius=0.058, lugs=5, dish=0.04, bulge=1.0, rim_mat='M_Rim',
                    center_cap_mat='M_RimDark', cap_chrome=False, curl=0.0, groove=0.0065):
    """Wheel in the car-kit frame (axle = Y, origin at the axle, outer face +Y for side=+1; side=-1 is mirror-built).
    Same parts / materials as carkit.build_wheel (M_Tyre M_Rim M_RimDark M_BrakeDisc M_Caliper M_Chrome M_Underbody) with
    three extra spoke styles:  'ten' (10 slim swept spokes, Cadence), 'mag' (5 wide flat spokes, deep dish, Thunderline),
    'five' (5 broad concave spokes that widen into the rim, Vesper)."""
    rb = rim_radius - 0.0127
    k = min(1.0, (radius - rb) / 0.112)
    bm = _tyre_ext(radius, width, rb, tyre_segments, bulge=bulge, k=k, groove=groove)
    y_out = rim_width / 2.0
    O = [(rim_radius, -y_out), (rb, -(y_out - 0.015)), (rb - 0.012, -(y_out - 0.03)), (rb - 0.030, -(y_out - 0.045)),
         (rb - 0.030, (y_out - 0.045)), (rb - 0.012, (y_out - 0.03)), (rb, (y_out - 0.015)), (rim_radius, y_out)]
    I = [(r - 0.009, y) for (r, y) in reversed(O)]
    barrel = prim_revolve(O + I, segments=segments, axis='Y', closed=True, mat=rim_mat)
    for f in barrel.faces:
        c = f.calc_center_median()
        if math.hypot(c.x, c.z) < rb - 0.012 and abs(c.y) < y_out - 0.02:
            f.material_index = mi('M_RimDark')
    bm_append(bm, barrel)
    barrel.free()
    y_rim = y_out - 0.018
    y_hub = y_out - dish
    r0, r1 = hub_radius * 0.9, rb - 0.010
    ring = prim_revolve([(rb - 0.034, y_rim - 0.016), (rb - 0.034, y_rim + 0.0035), (rb - 0.028, y_rim + 0.0085),
                         (rb - 0.002, y_rim + 0.0085), (rb + 0.0005, y_rim + 0.0045), (rb + 0.0005, y_rim - 0.016)],
                        segments=segments, axis='Y', closed=True, mat=rim_mat)
    bm_append(bm, ring)
    ring.free()
    lip = prim_torus(R=rim_radius - 0.0016, r=0.0036, seg_major=segments, seg_minor=8, axis='Y', center=(0, y_out - 0.0036, 0),
                     mat='M_Chrome')
    bm_append(bm, lip)
    lip.free()
    sc = (rb - 0.010) / 0.2159                    # spoke widths are designed for a 17" rim -> scale with the rim
    if style == 'ten':
        for i in range(10):
            phi = 2 * math.pi * i / 10 + math.radians(90.0)
            _spoke(bm, phi, r0, r1, 0.021 * sc, 0.027 * sc, y_hub, y_rim + 0.004, 0.026, n=8, curl=math.radians(curl or 13.0),
                   mat=rim_mat, chamfer=0.0045, flare=0.007 * sc)
    elif style == 'mag':
        for i in range(spokes):
            phi = 2 * math.pi * i / spokes + math.radians(90.0)
            _spoke(bm, phi, r0, r1, 0.078 * sc, 0.108 * sc, y_hub, y_rim + 0.004, 0.030, n=8, curl=math.radians(curl),
                   mat=rim_mat, chamfer=0.006, dish_pow=1.6)
    elif style == 'five':
        for i in range(spokes):
            phi = 2 * math.pi * i / spokes + math.radians(90.0)
            _spoke(bm, phi, r0, r1, 0.040 * sc, 0.074 * sc, y_hub, y_rim + 0.004, 0.032, n=10, curl=math.radians(curl or 10.0),
                   mat=rim_mat, chamfer=0.006, flare=0.020 * sc, dish_pow=2.3)
    hub = prim_cylinder(radius=hub_radius, depth=0.03, segments=28, axis='Y', center=(0, y_hub - 0.004, 0), mat=rim_mat,
                        bevel=0.005, bevel_segments=2)
    bm_append(bm, hub)
    hub.free()
    for i in range(lugs):
        a = 2 * math.pi * i / lugs + math.radians(90.0)
        lg = _hexnut(0.0098, 0.017, 'M_BrakeDisc', (0.0445 * math.cos(a), y_hub + 0.0165, 0.0445 * math.sin(a)))
        bm_append(bm, lg)
        lg.free()
    cap = prim_cylinder(radius=0.026 if not cap_chrome else 0.034, depth=0.010, segments=24, axis='Y',
                        center=(0, y_hub + 0.014, 0), mat='M_Chrome' if cap_chrome else center_cap_mat, bevel=0.003,
                        bevel_segments=1)
    bm_append(bm, cap)
    cap.free()
    capr = prim_torus(R=0.0215 if not cap_chrome else 0.030, r=0.0022, seg_major=24, seg_minor=6, axis='Y',
                      center=(0, y_hub + 0.0192, 0), mat='M_Chrome')
    bm_append(bm, capr)
    capr.free()
    ry = 0.020
    dr = brake_disc_radius
    disc = prim_revolve([(0.082, ry - 0.012), (dr, ry - 0.012), (dr, ry + 0.012), (0.082, ry + 0.012)], segments=segments,
                        axis='Y', closed=True, mat='M_BrakeDisc')
    bm_append(bm, disc)
    disc.free()
    for i in range(24):
        a = 2 * math.pi * i / 24.0
        rr = (0.082 + dr) / 2.0 + 0.004
        sl = prim_box((0.040, 0.0012, 0.0045), (0, 0, 0), mat='M_Underbody')
        bmesh.ops.transform(sl, matrix=T((rr * math.cos(a), ry + 0.0122, rr * math.sin(a)), (0, -math.degrees(a), 0)),
                            verts=sl.verts)
        bm_append(bm, sl)
        sl.free()
    hat = prim_cylinder(radius=0.085, depth=y_hub - ry + 0.01, segments=28, axis='Y', center=(0, (y_hub + ry) / 2, 0),
                        mat='M_BrakeDisc', caps=True)
    bm_append(bm, hat)
    hat.free()
    cal = _caliper(ry, dr - 0.022, dr)
    bmesh.ops.transform(cal, matrix=T(rot=(0, -caliper_angle, 0)), verts=cal.verts)
    bm_append(bm, cal)
    cal.free()
    if side < 0:
        m = mirrored_copy(bm)
        bm.free()
        bm = m
    return bm


# ----------------------------------------------------------------------------------------------------------------------
# scene helpers
# ----------------------------------------------------------------------------------------------------------------------
def add_anchors(car, col, root, items):
    """items: {suffix: (loc, display, size)} -> empties named <car>_<suffix> parented to root"""
    out = {}
    for suffix, (loc, disp, size) in items.items():
        out[suffix] = make_empty("%s_%s" % (car, suffix), col, parent=root, location=loc, display=disp, size=size)
    return out


def unwrap_parts(car, parts, livery_body=True):
    t0 = time.time()
    for suf in parts:
        o = bpy.data.objects.get("%s_%s" % (car, suf))
        if o is not None:
            uv_unwrap(o)
            if suf == 'Body' and livery_body:
                uv_livery_layer(o)
            print("[%s] uv %s %.1fs" % (car, suf, time.time() - t0))


def lamp_bezel(surf, center, ray, axes, length, height, rot=0.0, mat='M_TrimBlack', width=0.0115, hgt=0.0026, p=3.2, n=48,
               scale=1.0):
    """Raised thin bezel strip on the cut edge of a lamp pocket (same outline as build_headlight / build_taillight): hides the
    ragged boolean edge of the coarse loft.  Left side, mirror with mirrored_copy."""
    U, V = Vector(axes[0]), Vector(axes[1])
    cr, sr = math.cos(rot), math.sin(rot)
    outline = [(u * cr - v * sr, u * sr + v * cr) for (u, v) in outline_superellipse(length * scale, height * scale, p, n)]
    c = Vector(center)
    pts = [c + U * q[0] + V * q[1] for q in outline]
    return surface_sweep(surf, pts, ray, rib_profile(width, hgt, 0.006, 0.0011), closed=True, mat=mat)


def pocket_cutter_flat(surf, outline, center, ray_dir, depth=0.06, extra=0.03, taper=1.0, mat='M_TrimBlack', axes=None, far=6.0,
                       min_wall=0.012):
    """Pocket with a FLAT top (beyond the outermost skin point) and a FLAT floor (a plane perpendicular to the ray): for wide
    openings on a slightly domed fascia (full-width grille / lamp panel), where carkit.pocket_cutter's skin-following top cap
    would leave the bulge of the skin uncut.  Straight walls along the ray.  Returns (bmesh, info) with info = dict(s_floor,
    smax, d, c0) where s = -d . p is the outward coordinate along the ray (for ray (-1,0,0): s = x)."""
    U, V = axes if axes is not None else _axes_for(ray_dir)
    d = Vector(ray_dir).normalized()
    c = Vector(center)
    c0 = surf.hit(c, ray_dir, far)
    if c0 is None:
        return None, None
    locs = []
    for (u, v) in outline:
        h = surf.hit(c + U * u + V * v, ray_dir, far)
        if h is None:
            return None, None
        locs.append(h[0])
    S = lambda p: -d.dot(p)
    us = [u for (u, v) in outline]
    vs_ = [v for (u, v) in outline]
    extra_hits = [c0[0]]
    for fu in (-0.5, 0.0, 0.5):                      # interior samples: the dome of the skin can be higher than its rim
        for fv in (-0.5, 0.0, 0.5):
            h = surf.hit(c + U * (fu * max(us)) + V * (fv * max(vs_)), ray_dir, far)
            if h is not None:
                extra_hits.append(h[0])
    smax = max(max(S(p) for p in locs), max(S(p) for p in extra_hits))
    s_floor = min(S(c0[0]) - depth, min(S(p) for p in locs) - min_wall)
    top = [p + (-d) * (smax + extra - S(p)) for p in locs]
    bot = [p + (-d) * (s_floor - S(p)) for p in locs]
    if taper != 1.0:
        cb = c0[0] + (-d) * (s_floor - S(c0[0]))
        bot = [cb + (b - cb) * taper for b in bot]
    bm = ring_loft([top, bot], closed=True, caps=True)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    recalc(bm)
    _set_mat(bm, mat)
    return bm, dict(s_floor=s_floor, smax=smax, d=d, c0=c0[0], s_center=S(c0[0]))


def delete_verts_where(bm, pred):
    vs = [v for v in bm.verts if pred(v.co)]
    if vs:
        bmesh.ops.delete(bm, geom=vs, context='VERTS')
    return len(vs)


def build_rv_mirror(x, z, width=0.20):
    """Interior rear-view mirror (car space) hanging from the headliner at the windscreen"""
    bm = bmesh.new()
    _add(bm, prim_box((0.028, width, 0.058), (x, 0, z), mat='M_IntDash', bevel=0.012, segments=2))
    _add(bm, prim_cylinder(radius=0.008, depth=0.07, segments=8, axis='Z', center=(x + 0.02, 0, z + 0.05), mat='M_IntDash'))
    return bm


def focus_meshes(car, base_x, specs=None, on=True):
    """QA helper: edge-only meshes named <car>_FOC_<name> (invisible in shaded views) so that look(target=[...]) frames a part of
    the car at a sensible distance (an Empty gives a 0-size bbox -> wrong clipping).  specs {name: ((x0,y0,z0), (x1,y1,z1))} in
    car space.  Removed with on=False (and by remove_asset)."""
    for o in [o for o in bpy.data.objects if o.name.startswith(car + "_FOC_")]:
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me is not None and me.users == 0:
            bpy.data.meshes.remove(me)
    if not on:
        return
    col = bpy.data.collections.get(car) or bpy.context.scene.collection
    specs = specs or {}
    for name, (p0, p1) in specs.items():
        n = "%s_FOC_%s" % (car, name)
        me = bpy.data.meshes.new(n)
        me.from_pydata([(base_x + p0[0], p0[1], p0[2]), (base_x + p1[0], p1[1], p1[2])], [(0, 1)], [])
        o = bpy.data.objects.new(n, me)
        col.objects.link(o)


def window_loop_pts(fa, fb, zbu, zed, z_bot=0.985, inset=0.012, n_top=6, zmax=1.6):
    """Outline (x, z) of a side window for a chrome / black trim sweep: bottom edge on the belt (z = zbu(x)), the front edge
    along the line x = fa(z), the rear edge along x = fb(z) and the top along the roof edge (z = zed(x) - inset).  The top
    corners are found where the two lines meet the roof edge."""
    def top_on(fn):
        lo, hi = z_bot, zmax
        g = lambda z: z - (zed(fn(z)) - inset)
        if g(lo) >= 0:
            return lo
        for _ in range(40):
            mid = 0.5 * (lo + hi)
            if g(mid) < 0:
                lo = mid
            else:
                hi = mid
        return 0.5 * (lo + hi)
    za, zb_ = top_on(fa), top_on(fb)
    xa0, xb0 = fa(z_bot), fb(z_bot)
    xta, xtb = fa(za), fb(zb_)
    pts = [(xa0, zbu(xa0) + 0.001), (xb0, zbu(xb0) + 0.001), (xtb, zb_)]
    for i in range(1, n_top):
        x = xtb + (xta - xtb) * i / float(n_top)
        pts.append((x, zed(x) - inset))
    pts.append((xta, za))
    return pts


def hood_loop_xy(shell, x0, xf, r=0.15, margin=0.012, n_side=9, y_front=None):
    """Closed plan-view outline [(x, y), ...] of a bonnet / boot lid for a shut-line groove: side lines along the 'edge' ring point
    of the shell (minus `margin`), a filleted front corner (radius r) and a straight front edge at x = xf.  x0 = rear (cowl) edge."""
    left = []
    for i in range(n_side + 1):
        x = x0 + (xf - 0.02 - x0) * i / n_side
        left.append((x, edge_y(shell, x) - margin))
    yb = (edge_y(shell, xf - 0.02) - margin) if y_front is None else y_front
    pts = left[:-1] + [(xf, yb), (xf, 0.0), (xf, -yb)] + [(x, -y) for (x, y) in reversed(left[:-1])]
    radii = [0.0] * len(pts)
    radii[len(left) - 1] = r
    radii[len(left) + 1] = r
    # rounded_poly works in the (x, z) naming but is plain 2-D
    return rounded_poly(pts, radii, n=6)


def wheel_clearance(car, pad_hint=0.04, samples=19):
    """QA: for every wheel ray-cast (from outside, along -/+Y) at the arch lip (radius R + pad_hint + 10 mm, upper half) and report
    min(body half-width - tyre outer half-width).  Negative = the tyre sticks out beyond the fender lip."""
    from mathutils.bvhtree import BVHTree
    body = bpy.data.objects[car + '_Body']
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bvh = BVHTree.FromBMesh(bm)
    out = {}
    for k in ('FL', 'FR', 'RL', 'RR'):
        w = bpy.data.objects['%s_Wheel_%s' % (car, k)]
        ws = [v.co for v in w.data.vertices]
        wid = (max(v.y for v in ws) - min(v.y for v in ws)) / 2.0
        R = (max(v.z for v in ws) - min(v.z for v in ws)) / 2.0
        c = Vector(w.location)
        sd = 1.0 if c.y > 0 else -1.0
        y_t = abs(c.y) + wid                                  # outermost tyre face
        worst = 9.0
        for i in range(samples):
            a = math.radians(20.0 + 140.0 * i / (samples - 1))   # 20..160 deg above the axle
            x = c.x + (R + pad_hint + 0.010) * math.cos(a)
            z = c.z + (R + pad_hint + 0.010) * math.sin(a)
            loc, nor, idx, dist = bvh.ray_cast(Vector((x, sd * 3.0, z)), Vector((0, -sd, 0)), 6.0)
            if loc is not None:
                worst = min(worst, abs(loc.y) - y_t)
        out[k] = round(worst, 4)
    bm.free()
    return out
