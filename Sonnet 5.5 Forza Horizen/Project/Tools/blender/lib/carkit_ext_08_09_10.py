"""
carkit_ext_08_09_10.py - extra helpers for car08 Ranger (SUV), car09 Mule (pickup) and car10 Brisa (vintage roadster).
Load AFTER carkit.py (it uses the kit's globals: prim_*, ring_loft, surface_sweep, mi, bm_append, _add ... ):
    exec(compile(open(KIT, encoding="utf8").read(), KIT, "exec"), globals())
    exec(compile(open(EXT, encoding="utf8").read(), EXT, "exec"), globals())
Never edits carkit.py.  Everything is plain bmesh code, no add-ons.
"""
import math
import random
import bmesh
from mathutils import Vector, Matrix

EXT_VERSION = "1.1"      # 1.1 (fix round 2): block_tyre, window_seal, utility dash / interior, wire-wheel / tyre refinements


# ======================================================================================================================
# small geometry helpers
# ======================================================================================================================
def fillet_path3(pts, radii, n=6):
    """3-D polyline with a circular fillet (radius radii[i]) at every interior vertex (first/last radii ignored).
    Returns a list of Vectors (dense) - feed it to prim_tube for rounded tubular frames (bull bar, rack, snorkel ...)."""
    P = [Vector(p) for p in pts]
    out = [P[0]]
    for i in range(1, len(P) - 1):
        A, B, C = P[i - 1], P[i], P[i + 1]
        r = radii[i] if isinstance(radii, (list, tuple)) else radii
        u1 = (A - B).normalized()
        u2 = (C - B).normalized()
        cosang = max(-1.0, min(1.0, u1.dot(u2)))
        th = math.acos(cosang)
        if r <= 1e-9 or th > math.pi - 1e-4 or th < 1e-4:
            out.append(B)
            continue
        t = r / math.tan(th / 2.0)
        t = min(t, 0.48 * (A - B).length, 0.48 * (C - B).length)
        r = t * math.tan(th / 2.0)
        T1, T2 = B + u1 * t, B + u2 * t
        bis = (u1 + u2).normalized()
        Cc = B + bis * (r / math.sin(th / 2.0))
        a, b = (T1 - Cc), (T2 - Cc)
        om = math.acos(max(-1.0, min(1.0, a.normalized().dot(b.normalized()))))
        for k in range(n + 1):
            s = k / float(n)
            if om < 1e-6:
                out.append(T1)
                continue
            v = (a * math.sin((1 - s) * om) + b * math.sin(s * om)) / math.sin(om)
            out.append(Cc + v)
    out.append(P[-1])
    return out


def rrect_path(cx, cy, hx, hy, z, r, n=6):
    """Closed rounded-rectangle loop in the XY plane at height z (list of Vectors, counter-clockwise from above)."""
    r = min(r, hx - 1e-6, hy - 1e-6)
    pts = []
    for (ox, oy, a0) in ((hx - r, hy - r, 0.0), (-hx + r, hy - r, 90.0), (-hx + r, -hy + r, 180.0), (hx - r, -hy + r, 270.0)):
        for i in range(n + 1):
            a = math.radians(a0 + 90.0 * i / n)
            pts.append(Vector((cx + ox + r * math.cos(a), cy + oy + r * math.sin(a), z)))
    return pts


def tube(path, r=0.01, sides=8, mat='M_TrimBlack', caps=True, closed=False, up=(0, 0, 1)):
    return prim_tube([Vector(p) for p in path], radius=r, sides=sides, mat=mat, caps=caps, closed=closed, up=up)


def box_between(p0, p1, w=0.02, h=0.02, mat='M_TrimBlack', bevel=0.003, up=(0, 0, 1)):
    """Rectangular bar between two points (w across the 'side' axis, h along the 'up' axis); bevelled."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    L = d.length
    if L < 1e-6:
        return bmesh.new()
    t = d / L
    upv = Vector(up)
    side = t.cross(upv)
    if side.length < 1e-6:
        side = t.cross(Vector((1, 0, 0)))
    side.normalize()
    u = side.cross(t).normalized()
    bm = prim_box((L, w, h), (0, 0, 0), mat=mat, bevel=bevel, segments=1)
    m = Matrix((t, side, u)).transposed().to_4x4()
    m.translation = (p0 + p1) * 0.5
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm


def place(bm, loc=(0, 0, 0), rot=(0, 0, 0)):
    bmesh.ops.transform(bm, matrix=T(loc, rot), verts=bm.verts)
    return bm


def hull_box_pts(x0, x1, y0, y1, z0, z1, cx=0.0, cy=0.0, cz=0.0, cmin=0.0):
    """Points of a chamfered box for a convex collision hull (|y| <= y1, symmetric about y = 0 when y0 = 0).  c* = chamfers
    (positive = pull the top / front / rear edges in).  Returns Vectors."""
    pts = []
    for sy in ((1, -1) if y0 == 0.0 else (1,)):
        for (x, zl, yy) in ((x0 + cx, z0, y1 - cy), (x1 - cx, z0, y1 - cy), (x0, z0 + cz, y1), (x1, z0 + cz, y1),
                            (x0, z1 - cz, y1), (x1, z1 - cz, y1), (x0 + cx, z1, y1 - cy), (x1 - cx, z1, y1 - cy)):
            pts.append(Vector((x, sy * yy, zl)))
    return pts


def clean_tiny(bm, thr=1.0e-3):
    """Collapse sub-millimetre boolean slivers (edges shorter than thr, zero-thickness double faces) before finish_object."""
    es = [e for e in bm.edges if e.calc_length() < thr]
    if es:
        try:
            bmesh.ops.dissolve_degenerate(bm, dist=thr, edges=es)
        except Exception as ex:
            log("clean_tiny failed:", ex)
    bm.faces.ensure_lookup_table()
    return len(es)


# ======================================================================================================================
# tyres (knobbly / all-terrain) and wheel helpers
# ======================================================================================================================
def knobbly_tyre(R, w, rb, segs=80, g=0.022, bulge=1.0, period=4, wrap=True, emboss=True, mat='M_Tyre'):
    """Off-road tyre as one closed revolve around Y: bead + embossed sidewall rings + rounded shoulder + three lug lanes
    (centre lane, two shoulder lanes, staggered by half a period) separated by circumferential grooves.  Lug flanks are one
    segment wide ramps, the lug tops are flat.  segs must be a multiple of `period`.  g = lug height.  Origin = axle centre."""
    hw = w / 2.0
    sw = [(rb - 0.004, 0.62 * hw), (rb + 0.006, 0.72 * hw), (rb + 0.020, 0.90 * hw * bulge), (rb + 0.052, 0.992 * hw * bulge),
          (R - 0.062, 1.0 * hw * bulge), (R - 0.034, 0.975 * hw)]
    emb = {rb + 0.036: 0.0024, R - 0.052: 0.0016} if emboss else {}
    half = []          # (r, y, lane, drop)  lane: None smooth, 'S' shoulder lug, 'G' groove, 'C' centre lug
    for i, (r, y) in enumerate(sw):
        half.append((r, y, None, 0.0))
        if i + 1 < len(sw):
            for re, he in sorted(emb.items()):
                if r < re < sw[i + 1][0] - 0.004:
                    for dr, dy in ((-0.0035, 0.0), (-0.0024, he), (0.0024, he), (0.0035, 0.0)):
                        half.append((re + dr, _interp(sw, re + dr) + dy, None, 0.0))
    if wrap:       # lugs wrap round the shoulder onto the sidewall
        half += [(R - 0.018, 0.93 * hw, 'S', 0.55), (R - 0.006, 0.865 * hw, 'S', 0.25)]
    half += [(R, 0.80 * hw, 'S', 0.0), (R, 0.50 * hw, 'S', 0.0),
             (R, 0.43 * hw, 'G', 1.0), (R, 0.30 * hw, 'G', 1.0),
             (R, 0.23 * hw, 'C', 0.0), (R, 0.0, 'C', 0.0)]
    prof = list(half)
    for (r, y, lane, dp) in reversed(half[:-1]):
        prof.append((r, -y, lane, dp))
    bm = bmesh.new()
    n = len(prof)
    half_n = len(half)
    rows = []
    for idx, (r, y, lane, dp) in enumerate(prof):
        side = 0 if idx < half_n else 1
        row = []
        for k in range(segs):
            drop = 0.0
            if lane == 'G':
                drop = dp * g
            elif lane in ('S', 'C'):
                off = (0 if lane == 'S' else period // 2) + (1 if side == 1 else 0)
                if ((k + off) % period) >= period // 2:
                    drop = g * (1.0 if dp == 0.0 else dp)
            a = 2 * math.pi * k / segs
            rr = r - drop
            row.append(bm.verts.new((rr * math.cos(a), y, rr * math.sin(a))))
        rows.append(row)
    for i in range(n):
        i2 = (i + 1) % n
        for k in range(segs):
            k2 = (k + 1) % segs
            try:
                bm.faces.new((rows[i][k], rows[i][k2], rows[i2][k2], rows[i2][k]))
            except ValueError:
                pass
    recalc(bm)
    for f in bm.faces:
        f.material_index = mi(mat)
    return bm


def swap_tyre(bm, tyre):
    """Replace the M_Tyre faces of a wheel bmesh (from build_wheel) by `tyre` (a bmesh).  Do it BEFORE mirroring."""
    mt = mi('M_Tyre')
    dead = [f for f in bm.faces if f.material_index == mt]
    if dead:
        bmesh.ops.delete(bm, geom=dead, context='FACES')
    bm_append(bm, tyre)
    tyre.free()
    return bm


def off_road_wheel(radius, width, rim_radius, rim_width, tyre_kw=None, side=+1, tyre_fn=None, **kw):
    """Complete wheel: kit rim/brake assembly (build_wheel, tread-less) with the knobbly tyre swapped in (tyre_fn = knobbly_tyre or
    block_tyre; both take (R, w, rb, **tyre_kw))."""
    kw = dict(kw)
    segs = kw.pop('segments', 48)
    wb = build_wheel(radius=radius, width=width, rim_radius=rim_radius, rim_width=rim_width, side=+1, tread=False,
                     segments=segs, tyre_segments=24, **kw)
    t = (tyre_fn or knobbly_tyre)(radius, width, rim_radius - 0.0127, **(tyre_kw or {}))
    swap_tyre(wb, t)
    if side < 0:
        m = mirrored_copy(wb)
        wb.free()
        return m
    return wb


def spare_wheel(radius=0.40, width=0.265, rim_radius=0.205, segs=56, tyre_kw=None, cover=True, tyre_fn=None):
    """Spare wheel for a rear door: axle along Y, visible face +Y (rotate it afterwards).  Knobbly tyre, steel barrel, a dished
    painted steel face with five lug nuts and (cover=True) a round chrome-rimmed hub cover."""
    rb = rim_radius - 0.0127
    kw = dict(segs=segs)
    kw.update(tyre_kw or {})
    bm = (tyre_fn or knobbly_tyre)(radius, width, rb, **kw)
    yo = 0.10
    O = [(rim_radius, -yo), (rb, -(yo - 0.015)), (rb - 0.012, -(yo - 0.03)), (rb - 0.03, -(yo - 0.045)),
         (rb - 0.03, (yo - 0.045)), (rb - 0.012, (yo - 0.03)), (rb, (yo - 0.015)), (rim_radius, yo)]
    I = [(r - 0.009, y) for (r, y) in reversed(O)]
    _add(bm, prim_revolve(O + I, segments=40, axis='Y', closed=True, mat='M_Rim'))
    face = [(0.0, yo - 0.045), (rb - 0.05, yo - 0.045), (rb - 0.02, yo - 0.012), (rb - 0.0, yo - 0.012), (rb - 0.0, yo - 0.026),
            (rb - 0.05, yo - 0.058), (0.0, yo - 0.058)]
    _add(bm, prim_revolve(face, segments=40, axis='Y', closed=True, mat='M_RimDark'))
    for i in range(5):
        a = 2 * math.pi * i / 5 + math.radians(90.0)
        _add(bm, prim_cylinder(radius=0.011, depth=0.016, segments=6, axis='Y', center=(0.058 * math.cos(a), yo - 0.037, 0.058 * math.sin(a)),
                               mat='M_Chrome', bevel=0.0012, bevel_segments=1))
    if cover:
        _add(bm, prim_cylinder(radius=0.085, depth=0.02, segments=28, axis='Y', center=(0, yo - 0.040, 0), mat='M_Rim', bevel=0.005,
                               bevel_segments=2))
        _add(bm, prim_torus(R=0.080, r=0.0035, seg_major=28, seg_minor=6, axis='Y', center=(0, yo - 0.031, 0), mat='M_Chrome'))
    return bm


# ======================================================================================================================
# lamps
# ======================================================================================================================
def stacked_lamp(surf, center, ray, axes, w, h, depth=0.035, split=(0.24, 0.52, 0.24),
                 mats=('M_Indicator', 'M_Taillight', 'M_Reverse'), corner=0.014, rib=0.007, bezel=True, inset=0.004, bulge=0.003,
                 horizontal=False, taper=0.92):
    """Rectangular multi-segment lamp cluster seated on the skin (vertical stack from +V to -V, or along +U -> -U when
    horizontal=True).  Returns (cutter, [inserts]); subtract the cutter in the body boolean, append the inserts afterwards."""
    U, V = Vector(axes[0]), Vector(axes[1])
    c = Vector(center)
    outline = outline_rrect(w, h, min(corner, w / 2 - 1e-4, h / 2 - 1e-4), 4)
    cut = pocket_cutter(surf, outline, c, ray, depth=depth, lift=0.03, taper=taper, mat='M_TrimBlack', axes=(U, V))
    if cut is None:
        return None, []
    c0 = surf.hit(c, ray)
    for f in cut.faces:
        if (f.calc_center_median() - c0[0]).dot(c0[1]) < -depth * 0.8:
            f.material_index = mi('M_TrimGrey')
    ins = []
    if bezel:
        pts = [c + U * p[0] + V * p[1] for p in outline]
        bz = surface_sweep(surf, pts, ray, rib_profile(0.0115, 0.0022, 0.006, 0.001), closed=True, mat='M_TrimBlack')
        if bz is not None:
            ins.append(bz)
    n = len(split)
    ext = (w if horizontal else h)
    usable = ext - 2 * 0.0065 - rib * (n - 1)
    tot = float(sum(split))
    pos = (-ext / 2 + 0.0065) if horizontal else (ext / 2 - 0.0065)
    for sp, m in zip(split, mats):
        L = usable * sp / tot
        if horizontal:
            seg = outline_rrect(L, h - 0.013, min(corner * 0.7, L / 2 - 1e-4, (h - 0.013) / 2 - 1e-4), 3)
            off = U * (pos + L / 2)
            pos += L + rib
        else:
            seg = outline_rrect(w - 0.013, L, min(corner * 0.7, L / 2 - 1e-4, (w - 0.013) / 2 - 1e-4), 3)
            off = V * (pos - L / 2)
            pos -= L + rib
        p = surface_patch(surf, seg, c + off, ray, offset=inset, rings=3, mat=m, axes=(U, V), bulge=bulge)
        if p is not None:
            ins.append(p)
    return cut, ins


def round_lamp(radius=0.09, depth=0.07, mat_shell='M_Chrome', mat_lens='M_Headlight', style='bucket', rim=0.008):
    """Round lamp in its own frame: axis = +X (lens faces +X), origin = centre of the rear of the bucket.  Returns bmesh.
    style 'bucket' = classic chrome bucket with a domed lens and a reflector ring (headlamp), 'tail' = small flat tail lamp."""
    bm = bmesh.new()
    R = radius
    prof = [(0.0, 0.0), (R * 0.55, 0.0), (R * 0.93, depth * 0.30), (R * 1.0, depth * 0.62), (R * 1.0, depth * 0.92), (R * 1.02, depth),
            (R * 0.965, depth), (R * 0.93, depth * 0.96)]
    _add(bm, prim_revolve(prof, segments=32, axis='X', closed=False, mat=mat_shell))
    # inner reflector bowl + lens dome
    bowl = [(R * 0.93, depth * 0.96), (R * 0.86, depth * 0.80), (R * 0.45, depth * 0.52), (0.0, depth * 0.46)]
    _add(bm, prim_revolve(bowl, segments=32, axis='X', closed=False, mat='M_Chrome'))
    lens = [(R * 0.93, depth * 0.965), (R * 0.82, depth * 1.0), (R * 0.45, depth * 1.045), (0.0, depth * 1.06)]
    _add(bm, prim_revolve(lens, segments=32, axis='X', closed=False, mat=mat_lens))
    if style == 'bucket':
        _add(bm, prim_cylinder(radius=R * 0.17, depth=depth * 0.30, segments=14, axis='X', center=(depth * 0.55, 0, 0), mat='M_Chrome'))
        _add(bm, prim_torus(R=R * 0.62, r=0.0022, seg_major=32, seg_minor=5, axis='X', center=(depth * 1.02, 0, 0), mat='M_Chrome'))
    # a short stalk base
    _add(bm, prim_cylinder(radius=R * 0.14, depth=R * 0.55, segments=10, axis='Z', center=(depth * 0.25, 0, -R * 0.95), mat=mat_shell))
    return bm


# ======================================================================================================================
# vintage roadster helpers (car10 Brisa): cockpit outline, swept cycle wings, wire wheels, gauges, seats
# ======================================================================================================================
def outline_rrect4(x0, x1, y0, y1, radii, n=6):
    """Rounded rectangle (u = x, v = y) with a different corner radius per corner, counter-clockwise.
    radii = (r(x1,y1), r(x0,y1), r(x0,y0), r(x1,y0))."""
    pts = []
    corners = [(x1, y1, radii[0], 0.0), (x0, y1, radii[1], 90.0), (x0, y0, radii[2], 180.0), (x1, y0, radii[3], 270.0)]
    for (cx, cy, r, a0) in corners:
        sx = -1.0 if cx == x0 else 1.0
        sy = -1.0 if cy == y0 else 1.0
        ox, oy = cx - sx * r, cy - sy * r
        for i in range(n + 1):
            a = math.radians(a0 + 90.0 * i / n)
            pts.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    return pts


def _bez(p0, p1, p2, p3, n):
    out = []
    for i in range(n + 1):
        t = i / float(n)
        u = 1.0 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def fender_path(xa, za, Rc, phi0, phi1, tail_pt, tail_at_rear, n_arc=26, n_tail=12, l1=0.18, l2=0.12):
    """Centre line (XZ plane, ordered by increasing x) of a cycle wing: an arc of radius Rc around the axle (xa, za) from
    angle phi0 to phi1 (degrees from +Z towards +X) plus a Bezier tail that flows down to `tail_pt` (the running board).
    Returns (list of (x, z), index of the first arc point, index of the last arc point)."""
    arc = []
    for i in range(n_arc + 1):
        ph = math.radians(phi0 + (phi1 - phi0) * i / float(n_arc))
        arc.append((xa + Rc * math.sin(ph), za + Rc * math.cos(ph)))
    if tail_at_rear:
        ph = math.radians(phi0)
        d = (-math.cos(ph), math.sin(ph))
        A = arc[0]
        p1 = (A[0] + d[0] * l1, A[1] + d[1] * l1)
        p2 = (tail_pt[0] + l2, tail_pt[1])
        tail = _bez(A, p1, p2, tail_pt, n_tail)
        pts = list(reversed(tail))[:-1] + arc
        return pts, len(tail) - 1, len(pts) - 1
    ph = math.radians(phi1)
    d = (math.cos(ph), -math.sin(ph))
    A = arc[-1]
    p1 = (A[0] + d[0] * l1, A[1] + d[1] * l1)
    p2 = (tail_pt[0] - l2, tail_pt[1])
    tail = _bez(A, p1, p2, tail_pt, n_tail)
    pts = arc + tail[1:]
    return pts, 0, len(arc) - 1


# normalised cross-section of a cycle wing: (v across: 0 = inner edge .. 1 = outer lip, h above the centre line [m], lip flag)
_WING_SEC = [(0.00, -0.022, 0), (0.03, -0.006, 0), (0.09, 0.012, 0), (0.20, 0.030, 0), (0.36, 0.040, 0), (0.52, 0.038, 0), (0.67, 0.027, 0),
             (0.79, 0.008, 0), (0.88, -0.028, 1), (0.94, -0.075, 1), (0.98, -0.115, 1), (1.00, -0.140, 1)]


def fender_loft(path, y_in, y_out, width_keys, lip_keys, crown_keys, thick=0.008, mat='M_Paint2', sec=None):
    """Closed thin-shell cycle wing: the cross-section (crowned, rolled lip) is swept along `path` ((x, z) points in the XZ plane,
    increasing x) at lateral position y_in..y_out (left side, +Y).  width_keys / lip_keys / crown_keys = [(u, value)] with u =
    normalised length along the path (value scales the section width, the lip drop and the crown height).  Returns a bmesh."""
    sec = sec or _WING_SEC
    n = len(path)
    L = [0.0]
    for i in range(1, n):
        L.append(L[-1] + math.hypot(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]))
    wk, lk, ck = Curve1D(width_keys), Curve1D(lip_keys), Curve1D(crown_keys)
    rings = []
    for i in range(n):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, n - 1)]
        tx, tz = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(tx, tz) or 1.0
        tx, tz = tx / ln, tz / ln
        nx, nz = -tz, tx
        u = L[i] / L[-1]
        ws, ls, cs = wk(u), lk(u), ck(u)
        top, bot = [], []
        for (v, h, lp) in sec:
            hh = h * (ls if lp else cs)
            y = y_in + (y_out - y_in) * ws * v
            top.append(Vector((path[i][0] + nx * hh, y, path[i][1] + nz * hh)))
            bot.append(Vector((path[i][0] + nx * (hh - thick), y, path[i][1] + nz * (hh - thick))))
        rings.append(top + list(reversed(bot)))
    return ring_loft(rings, closed=True, caps=True, mat=mat)


def vintage_tyre(R, w, rb, segs=56, mat='M_Tyre'):
    """Balloon tyre (narrow, round section, shallow circumferential ribs), axle along Y, origin = axle centre.  Fix round 2: monotone profile
    (the first version folded back on itself for small tyres) and two moulded concentric rings on the sidewall."""
    hw = w / 2.0
    H = R - rb
    side = [(rb - 0.003, 0.58 * hw), (rb + 0.005, 0.70 * hw), (rb + 0.20 * H, 0.90 * hw), (rb + 0.38 * H, 0.995 * hw), (rb + 0.50 * H, hw),
            (rb + 0.62 * H, 0.975 * hw)]
    tail = [(R - 0.020, 0.88 * hw), (R - 0.008, 0.72 * hw), (R - 0.001, 0.56 * hw), (R, 0.50 * hw),
            (R - 0.0035, 0.45 * hw), (R - 0.0035, 0.32 * hw), (R, 0.27 * hw), (R, 0.0)]
    pts = side + tail[:1]

    def y_at(r):
        for i in range(len(pts) - 1):
            if pts[i][0] <= r <= pts[i + 1][0]:
                t = (r - pts[i][0]) / max(pts[i + 1][0] - pts[i][0], 1e-9)
                return pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t
        return pts[-1][1]
    ring_pts = []
    for rr_, hh_ in ((rb + 0.33 * H, 0.0028), (rb + 0.52 * H, 0.0028)):       # two moulded rings (3-point ridges), 2.8 mm high
        y0 = y_at(rr_)
        ring_pts += [(rr_ - 0.0040, y_at(rr_ - 0.0040)), (rr_, y0 + hh_), (rr_ + 0.0040, y_at(rr_ + 0.0040))]
    half = sorted(side + ring_pts, key=lambda p: p[0]) + tail
    prof = list(half)
    for (r, y) in reversed(half[:-1]):
        prof.append((r, -y))
    bm = bmesh.new()
    n = len(prof)
    rows = []
    for (r, y) in prof:
        rows.append([bm.verts.new((r * math.cos(2 * math.pi * k / segs), y, r * math.sin(2 * math.pi * k / segs))) for k in range(segs)])
    for i in range(n):
        i2 = (i + 1) % n
        for k in range(segs):
            k2 = (k + 1) % segs
            try:
                bm.faces.new((rows[i][k], rows[i][k2], rows[i2][k2], rows[i2][k]))
            except ValueError:
                pass
    recalc(bm)
    for f in bm.faces:
        f.material_index = mi(mat)
    return bm


def wire_wheel(R=0.30, w=0.12, rim_r=0.2075, rim_w=0.075, n_spokes=36, side=+1, segs=56, drum=True, spoke_r=0.0019, spoke_sides=4):
    """Laced wire wheel: balloon tyre, polished rim, 2 x n_spokes tangent-laced thin spokes, chrome hub with a three-eared
    knock-off spinner, brake drum behind.  Axle along Y, outer face +Y (side=+1) / mirror built copy (side=-1)."""
    rb = rim_r - 0.010
    bm = vintage_tyre(R, w, rb, segs)
    yo = rim_w / 2.0
    O = [(rim_r, -yo), (rb, -(yo - 0.008)), (rb - 0.012, -(yo - 0.018)), (rb - 0.022, -(yo - 0.030)),
         (rb - 0.022, (yo - 0.030)), (rb - 0.012, (yo - 0.018)), (rb, (yo - 0.008)), (rim_r, yo)]
    I = [(r - 0.004, y) for (r, y) in reversed(O)]
    _add(bm, prim_revolve(O + I, segments=segs, axis='Y', closed=True, mat='M_Rim'))
    hr, hf = 0.034, 0.062
    prof = [(0.0, -0.058), (hr, -0.058), (hr, -0.036), (hf, -0.036), (hf, -0.030), (hr * 0.9, -0.030), (hr * 0.9, 0.030), (hf, 0.030),
            (hf, 0.036), (hr, 0.036), (hr, 0.062), (0.0, 0.062)]
    _add(bm, prim_revolve([(r, y) for (r, y) in prof], segments=24, axis='Y', closed=True, mat='M_Chrome'))
    for k in range(3):                                       # knock-off spinner ears
        e = prim_box((0.040, 0.020, 0.012), (0.036, 0.052, 0.0), mat='M_Chrome', bevel=0.003, segments=1)
        bmesh.ops.transform(e, matrix=T((0, 0, 0), (0, math.degrees(2 * math.pi * k / 3), 0)), verts=e.verts)
        _add(bm, e)
    for sgn in (-1, 1):                                      # tangent-laced spokes
        yh = sgn * 0.033
        yr = sgn * 0.016
        for i in range(n_spokes):
            a0 = 2 * math.pi * i / n_spokes
            a1 = a0 + math.radians(34.0) * (1 if (i % 2 == 0) else -1)
            p0 = Vector((hf * 0.92 * math.cos(a0), yh, hf * 0.92 * math.sin(a0)))
            p1 = Vector(((rb - 0.012) * math.cos(a1), yr, (rb - 0.012) * math.sin(a1)))
            _add(bm, prim_tube([p0, p1], radius=spoke_r, sides=spoke_sides, mat='M_Chrome', caps=True))
    if drum:
        _add(bm, prim_cylinder(radius=0.150, depth=0.048, segments=32, axis='Y', center=(0, -0.034, 0), mat='M_BrakeDisc', bevel=0.004,
                               bevel_segments=1))
        _add(bm, prim_cylinder(radius=0.160, depth=0.010, segments=32, axis='Y', center=(0, -0.056, 0), mat='M_Underbody'))
    if side < 0:
        m = mirrored_copy(bm)
        bm.free()
        return m
    return bm


def gauge(r=0.045, depth=0.04, needle_deg=-40.0, mat_dial='M_TrimBlack'):
    """Round instrument in its own frame: axis X, the dial faces -X (towards the driver) and sits at x = 0; the body extends to +X."""
    bm = bmesh.new()
    _add(bm, prim_torus(R=r, r=0.0055, seg_major=28, seg_minor=6, axis='X', center=(-0.004, 0, 0), mat='M_Chrome'))
    _add(bm, prim_cylinder(radius=r * 0.97, depth=0.006, segments=28, axis='X', center=(0.002, 0, 0), mat=mat_dial))
    _add(bm, prim_cylinder(radius=r * 1.02, depth=depth, segments=24, axis='X', center=(0.005 + depth / 2, 0, 0), mat='M_TrimGrey'))
    for k in range(11):
        ang = math.radians(-120.0 + 24.0 * k)
        tk = prim_box((0.0012, 0.0020, 0.0070 if k % 5 == 0 else 0.0045), (0, 0, 0), mat='M_Chrome')
        bmesh.ops.transform(tk, matrix=T((-0.0012, math.sin(ang) * r * 0.80, math.cos(ang) * r * 0.80), (math.degrees(ang) * -1.0, 0, 0)),
                            verts=tk.verts)
        _add(bm, tk)
    nd = prim_box((0.0012, 0.0030, r * 0.78), (0, 0, r * 0.39), mat='M_Caliper')
    bmesh.ops.transform(nd, matrix=T((-0.0022, 0, 0), (needle_deg, 0, 0)), verts=nd.verts)
    _add(bm, nd)
    _add(bm, prim_cylinder(radius=0.007, depth=0.004, segments=10, axis='X', center=(-0.0035, 0, 0), mat='M_Chrome'))
    return bm


def vintage_seat(width=0.44, depth=0.46, back_h=0.52, recline=14.0):
    """Leather bucket seat in its own frame: origin = centre of the seat base on the floor, +X forward, +Z up.  Pillowy cushion,
    side bolsters, pleated rolled back (rolled top tube, pleat strips), chrome runner feet.  Returns bmesh."""
    bm = bmesh.new()
    _add(bm, prim_box((depth * 0.9, width * 0.84, 0.11), (0.0, 0, 0.065), mat='M_TrimBlack', bevel=0.02, segments=1))
    _add(bm, prim_box((depth, width, 0.125), (0.01, 0, 0.19), mat='M_IntSeat', bevel=0.05, segments=3, rot=(0, -3, 0)))
    for s in (1, -1):
        _add(bm, prim_box((depth * 0.8, 0.055, 0.075), (-0.02, s * (width / 2 - 0.035), 0.26), mat='M_IntSeat', bevel=0.028, segments=2))
        _add(bm, prim_box((0.34, 0.012, 0.012), (0.0, s * width * 0.28, 0.012), mat='M_Chrome', bevel=0.003, segments=1))
    back = bmesh.new()
    _add(back, prim_box((0.10, width, back_h), (0, 0, back_h / 2), mat='M_IntSeat', bevel=0.045, segments=3))
    for k in range(5):
        _add(back, prim_box((0.006, width * 0.86, 0.010), (0.052, 0, 0.06 + k * (back_h - 0.12) / 4.0), mat='M_IntTrim', bevel=0.002, segments=1))
    for s in (1, -1):
        _add(back, prim_box((0.12, 0.05, back_h * 0.78), (0.012, s * (width / 2 - 0.03), back_h * 0.46), mat='M_IntSeat', bevel=0.025, segments=2))
    _add(back, prim_tube([(0, -width * 0.43, back_h - 0.012), (0, width * 0.43, back_h - 0.012)], radius=0.028, sides=10, mat='M_IntSeat',
                         caps=True, up=(1, 0, 0)))
    bm_append(bm, back, matrix=T((-depth * 0.5 + 0.015, 0, 0.22), (0, -recline, 0)))
    back.free()
    return bm


# ======================================================================================================================
# fix round 2 (art-director findings) - block tyre, window seals, utility dash / interior
# ======================================================================================================================
def _blk_prism(bm, poly, th0, th1, th0t=None, th1t=None, mat='M_Tyre'):
    """Closed lug: the (r, y) polygon swept around the Y axis from th0 to th1 (radians); points whose r is above the polygon mean can be
    slanted by giving th0t / th1t (slanted block).  Walls + two end caps."""
    n = len(poly)
    rm = sum(p[0] for p in poly) / n
    verts = []
    for (th, tht) in ((th0, th0t), (th1, th1t)):
        ring = []
        for (r, y) in poly:
            t = th if (tht is None or r < rm) else tht
            ring.append(bm.verts.new((r * math.cos(t), y, r * math.sin(t))))
        verts.append(ring)
    a, b = verts
    fl = []
    for i in range(n):
        j = (i + 1) % n
        fl.append(bm.faces.new((a[i], a[j], b[j], b[i])))
    fl.append(bm.faces.new(list(reversed(a))))
    fl.append(bm.faces.new(b))
    for f in fl:
        f.material_index = mi(mat)
    return fl


def block_tyre(R, w, rb, segs=40, n=28, lug_h=0.026, seed=3, vary=0.5, sidewall=True, n_sw=32, mat='M_Tyre'):
    """All-terrain tyre with real tread blocks (fix round 2): a smooth bead / sidewall / shoulder revolve (monotone profile, two embossed
    rings) carrying three families of separate lug blocks per side - two staggered tread lanes (slanted blocks, seeded size jitter), a
    shoulder block that wraps the shoulder curve - plus a ring of small raised blocks on the sidewall (alternating long / short, like an
    M/T tyre).  Local frame like build_wheel: axle = Y, origin = axle centre; no vertex is farther than R from the axle.
    Signature matches knobbly_tyre(R, w, rb, ...) so it can be passed as tyre_fn to off_road_wheel / spare_wheel."""
    rng = random.Random(seed)
    w2 = w / 2.0
    base = R - lug_h * 0.9
    H = base - rb
    sw = [(rb - 0.004, 0.64 * w2), (rb + 0.008, 0.74 * w2), (rb + 0.18 * H, 0.93 * w2), (rb + 0.36 * H, 0.995 * w2),
          (rb + 0.62 * H, 1.0 * w2), (rb + 0.80 * H, 0.975 * w2), (rb + 0.91 * H, 0.915 * w2), (rb + 0.97 * H, 0.84 * w2),
          (base, 0.74 * w2), (base, 0.0)]
    half = []
    for i, p in enumerate(sw):
        half.append(p)
        if i == 3:
            rr = (sw[3][0] + sw[4][0]) * 0.5
            yy = (sw[3][1] + sw[4][1]) * 0.5
            half += [(rr - 0.006, yy), (rr - 0.0035, yy + 0.003), (rr + 0.0035, yy + 0.003), (rr + 0.006, yy)]
    prof = list(half)
    for (r, y) in reversed(half[:-1]):
        prof.append((r, -y))
    bm = prim_revolve(prof, segments=segs, axis='Y', closed=True, mat=mat)
    lanes = [(0.28 * w2, 0.46 * w2, 0.0, 0.022), (0.72 * w2, 0.34 * w2, 0.5, 0.032)]       # (yc, width, phase, slant)
    for side in (1, -1):
        nl = n if side == 1 else n + 1                       # different counts per side: the two halves never line up
        step = 2.0 * math.pi / nl
        for k in range(nl):
            for li, (yc, ww, ph, sk) in enumerate(lanes):
                if vary > 0 and li == 1 and rng.random() < 0.08 * vary:
                    continue
                a0 = (k + ph) * step + (rng.random() - 0.5) * step * 0.10 * vary
                hl = step * 0.27 * (1.0 + (rng.random() - 0.5) * 0.30 * vary)
                wv = ww * (1.0 + (rng.random() - 0.5) * 0.20 * vary)
                skv = sk * (1.0 + (rng.random() - 0.5) * 0.5 * vary)
                top = R - rng.random() * 0.0030 * vary
                y0, y1 = side * (yc - wv / 2), side * (yc + wv / 2)
                if side < 0:
                    y0, y1 = y1, y0
                drop = 0.012 if li == 1 else 0.0
                pol = [(base - 0.003, y0), (base - 0.003 - drop, y1), (top - drop, y1 - side * 0.004), (top, y0 + side * 0.004)]
                if side < 0:
                    pol = list(reversed(pol))
                _blk_prism(bm, pol, a0 - hl, a0 + hl, a0 - hl + skv * side, a0 + hl + skv * side, mat=mat)
            # shoulder block wrapping the shoulder curve
            a0 = (k + 0.25) * step + (rng.random() - 0.5) * step * 0.12 * vary
            hl = step * 0.24 * (1.0 + (rng.random() - 0.5) * 0.26 * vary)
            hh = lug_h * 0.62 * (1.0 - rng.random() * 0.30 * vary)
            curve = [(rb + 0.91 * H, 0.915 * w2), (rb + 0.97 * H, 0.84 * w2), (base, 0.76 * w2)]
            outer = [(r + hh, y) for (r, y) in curve]
            inner = [(r - 0.002, y) for (r, y) in curve]
            pol = [(p[0], p[1] * side) for p in inner] + [(p[0], p[1] * side) for p in reversed(outer)]
            if side < 0:
                pol = list(reversed(pol))
            _blk_prism(bm, pol, a0 - hl, a0 + hl, mat=mat)
        if sidewall and n_sw > 0:
            nsw = n_sw if side == 1 else n_sw + 1
            stp = 2.0 * math.pi / nsw
            for k in range(nsw):
                ra = rb + 0.40 * H
                rbk = rb + (0.74 if k % 2 == 0 else 0.62) * H
                th = (k + 0.5 * (1 if side == 1 else 0)) * stp
                hl = stp * 0.21
                ys = w2 * 0.992
                pol = [(ra, side * (ys - 0.003)), (ra, side * (ys + 0.0065)), (rbk, side * (ys + 0.0065)), (rbk, side * (ys - 0.003))]
                if side < 0:
                    pol = list(reversed(pol))
                _blk_prism(bm, pol, th - hl, th + hl, mat=mat)
    recalc(bm)
    return bm


def window_seal(glass, surf, width=0.0125, height=0.0038, mat='M_TrimBlack', spacing=0.05, turn_deg=10.0):
    """Rubber seal bead round every window opening: walks the boundary loops of the glass sheets (`glass` bmesh from extract_glass),
    seats a low flat-topped bead (width x height) on the UNCUT skin (`surf` = Surface of the shell) just outside the window edge and
    sweeps it along the loop (the path is thinned to `spacing` m unless the outline turns by more than `turn_deg`).  Returns a bmesh
    (append it to the body before finish_object) or None."""
    adj = {}
    for e in glass.edges:
        if len(e.link_faces) != 1:
            continue
        a, b = e.verts
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    seen = set()
    loops = []
    for v0 in list(adj):
        if v0 in seen or len(adj[v0]) != 2:
            continue
        chain = [v0]
        seen.add(v0)
        cur = v0
        while True:
            nxt = [v for v in adj[cur] if v not in seen]
            if not nxt:
                break
            cur = nxt[0]
            chain.append(cur)
            seen.add(cur)
        if len(chain) >= 8 and v0 in adj[chain[-1]]:
            loops.append([Vector(v.co) for v in chain])
    out = bmesh.new()
    prof = [(-0.0015, -0.0025), (0.0010, height), (width - 0.0035, height), (width, -0.0025)]
    n_beads = 0
    for pts in loops:
        keep = [0]
        last = pts[0]
        m = len(pts)
        for i in range(1, m):
            d_prev = (pts[i] - pts[i - 1]).normalized()
            d_next = (pts[(i + 1) % m] - pts[i]).normalized()
            turn = math.degrees(math.acos(max(-1.0, min(1.0, d_prev.dot(d_next)))))
            if (pts[i] - last).length >= spacing or turn > turn_deg:
                keep.append(i)
                last = pts[i]
        P = [pts[i] for i in keep]
        if len(P) < 8:
            continue
        sk = []
        for p in P:
            c = surf.closest(p)
            if c is None:
                sk = []
                break
            sk.append(c)
        if not sk:
            continue
        m = len(P)
        q = [c[0] for c in sk]
        nrm = []
        for i in range(m):
            nv = sk[i - 1][1] + sk[i][1] + sk[(i + 1) % m][1]
            nrm.append(nv.normalized() if nv.length > 1e-9 else sk[i][1])
        cen = sum(q, Vector()) / m
        rings = []
        for i in range(m):
            t = q[(i + 1) % m] - q[i - 1]
            t = t - nrm[i] * t.dot(nrm[i])
            if t.length < 1e-9:
                t = Vector((1, 0, 0))
            t.normalize()
            wv = nrm[i].cross(t).normalized()
            if wv.dot(q[i] - cen) < 0:
                wv = -wv
            rings.append([q[i] + wv * a + nrm[i] * b for (a, b) in prof])
        rings.append(rings[0])
        sub = ring_loft(rings, closed=True, caps=False)
        bmesh.ops.remove_doubles(sub, verts=list(sub.verts), dist=1e-7)
        recalc(sub)
        for f in sub.faces:
            f.material_index = mi(mat)
        bm_append(out, sub)
        sub.free()
        n_beads += 1
    if n_beads == 0:
        out.free()
        return None
    return out


def build_dash_utility(x_back=0.40, x_front=0.80, z_top=1.06, z_low=0.60, half_width=0.82, driver_y=0.38):
    """Utilitarian off-road dash in car space: flat squared pad, hooded two-dial cluster over the driver, tall vertical-vent centre block with
    rotary heater knobs, round end vents, glovebox outline with a latch and a passenger grab handle.  The dash face looks to -X (towards the
    driver); parameters are the same as the kit's build_dash.  No lamp slots; needles / ticks are chrome."""
    bm = bmesh.new()
    prof = [(x_front, z_top + 0.004), (x_back + 0.04, z_top), (x_back, z_top - 0.03), (x_back - 0.012, z_top - 0.20),
            (x_back + 0.07, z_low + 0.14), (x_back + 0.20, z_low), (x_front, z_low)]
    pad = prim_prism(prof, half_width * 2, plane='XZ', center=(0, 0, 0), mat='M_IntDash')
    bevel_edges = [e for e in pad.edges if abs(e.verts[0].co.y) > half_width * 0.99 and abs(e.verts[1].co.y) > half_width * 0.99]
    try:
        bmesh.ops.bevel(pad, geom=bevel_edges, offset=0.03, segments=2, profile=0.5, material=-1, affect='EDGES', clamp_overlap=True)
    except Exception:
        pass
    _add(bm, pad)
    sg = 1.0 if driver_y >= 0 else -1.0
    # hooded instrument cluster (squared hood, two dials, warning strip)
    xc = x_back - 0.018
    _add(bm, prim_box((0.15, 0.40, 0.145), (x_back + 0.058, driver_y, z_top + 0.052), mat='M_IntDash', bevel=0.022, segments=2))
    _add(bm, prim_box((0.012, 0.37, 0.115), (xc + 0.004, driver_y, z_top + 0.045), mat='M_TrimBlack', bevel=0.004, segments=1))
    for dy, nd in ((-0.095, -50.0), (0.095, 15.0)):
        g = gauge(0.056, 0.03, nd)
        bmesh.ops.transform(g, matrix=T((xc, driver_y + dy, z_top + 0.040)), verts=g.verts)
        _add(bm, g)
    for k in range(4):
        _add(bm, prim_box((0.003, 0.016, 0.010), (xc - 0.001, driver_y - 0.036 + 0.024 * k, z_top + 0.093),
                          mat='M_Caliper' if k % 2 == 0 else 'M_IntTrim', bevel=0.001, segments=1))
    # centre block with vertical vents + rotary controls (its face stands 6 cm proud of the dash pad)
    cx_ = 0.0
    xf = x_back - 0.060
    _add(bm, prim_box((0.12, 0.25, 0.37), (x_back, cx_, z_top - 0.215), mat='M_TrimGrey', bevel=0.02, segments=2))
    for k in range(5):
        _add(bm, prim_box((0.006, 0.014, 0.115), (xf - 0.001, cx_ - 0.080 + 0.040 * k, z_top - 0.100), mat='M_TrimBlack', bevel=0.002, segments=1))
    _add(bm, prim_box((0.010, 0.20, 0.060), (xf - 0.0015, cx_, z_top - 0.215), mat='M_TrimBlack', bevel=0.004, segments=1))          # radio blank
    for k in range(3):
        _add(bm, prim_cylinder(radius=0.022, depth=0.020, segments=14, axis='X', center=(xf - 0.010, cx_ - 0.07 + 0.07 * k, z_top - 0.31),
                               mat='M_IntDash', bevel=0.003, bevel_segments=1))
        _add(bm, prim_box((0.004, 0.003, 0.016), (xf - 0.0205, cx_ - 0.07 + 0.07 * k, z_top - 0.31), mat='M_Chrome'))
    # round end vents + defrost slot
    for s in (1, -1):
        _add(bm, prim_cylinder(radius=0.040, depth=0.012, segments=18, axis='X', center=(x_back - 0.004, s * (half_width - 0.10), z_top - 0.075),
                               mat='M_TrimGrey', bevel=0.003, bevel_segments=1))
        for k in range(4):
            _add(bm, prim_box((0.004, 0.058, 0.004), (x_back - 0.011, s * (half_width - 0.10), z_top - 0.075 - 0.018 + 0.012 * k), mat='M_TrimBlack'))
    _add(bm, prim_box((0.10, 0.62, 0.006), (x_back + 0.17, 0.0, z_top + 0.003), mat='M_TrimBlack', bevel=0.001, segments=1))
    # glovebox outline + latch, passenger grab handle (side opposite the driver)
    py = -sg * 0.43
    gz = z_top - 0.155
    for (cy, cz, wy, wz) in ((py, gz + 0.085, 0.38, 0.005), (py, gz - 0.085, 0.38, 0.005), (py - 0.19, gz, 0.005, 0.175), (py + 0.19, gz, 0.005, 0.175)):
        _add(bm, prim_box((0.006, wy, wz), (x_back - 0.005, cy, cz), mat='M_TrimBlack', bevel=0.001, segments=1))
    _add(bm, prim_box((0.014, 0.050, 0.022), (x_back - 0.010, py, gz + 0.050), mat='M_TrimGrey', bevel=0.004, segments=1))
    grab = fillet_path3([(x_back - 0.004, py - 0.22, z_top - 0.015), (x_back - 0.060, py - 0.22, z_top - 0.015),
                         (x_back - 0.060, py + 0.22, z_top - 0.015), (x_back - 0.004, py + 0.22, z_top - 0.015)], [0, 0.02, 0.02, 0], 4)
    _add(bm, tube(grab, 0.0125, 8, 'M_TrimBlack', caps=True))
    return bm


def build_interior_utility(shell=None, spec=None):
    """Interior for the off-road cars (Ranger / Mule): same spec keys as carkit_ext_05_06_07.build_interior_ext (rubber floor, console, plain
    upright seats, door cards from the shell), but with the utilitarian dash (`build_dash_utility`), a long gear lever + a short transfer-case
    lever, a pedal set with a dead pedal and door grab handles instead of the sport binnacle / screen dash."""
    S = dict(floor_z=0.43, front_x=-0.22, driver_y=0.38, rear_x=-1.02, rear_width=1.40, dash_x_back=0.40, dash_x_front=0.80, dash_z_top=1.06,
             dash_z_low=0.60, hw=0.865, x_front_floor=0.72, x_rear_floor=-1.95, door_x=(-0.46, 0.70), quarter_x=(-1.90, -0.50),
             roof_x=(-1.80, 0.12), seats_rear=True, rear_z=0.47, front_z=0.47, back_h=0.66, console=(-0.40, 0.46), console_h=0.28, shifter_x=0.05,
             mirror=(0.30, 0.0, 1.30), rear_cushion=0.46, rear_recline=18.0, front_recline=18.0, seat_w=0.50, headliner=False, armrest_x=0.06,
             rear_back_h=0.58)
    if spec:
        S.update(spec)
    bm = bmesh.new()
    fz = S['floor_z']
    _add(bm, prim_box((S['x_front_floor'] - S['x_rear_floor'], S['hw'] * 2 - 0.1, 0.03),
                      ((S['x_front_floor'] + S['x_rear_floor']) / 2, 0, fz - 0.015), mat='M_IntCarpet', bevel=0.01, segments=1))
    c0, c1 = S['console']
    _add(bm, build_console(x0=c0, x1=c1, z_floor=fz, z_top=fz + S['console_h']))
    dy = S['driver_y']
    for yy in (dy, -dy):
        _add(bm, build_seat(width=S['seat_w'], sport=False, back_h=S['back_h'], recline=S['front_recline'], headrest=True),
             matrix=T((S['front_x'], yy, S['front_z'])))
    if S['seats_rear']:
        _add(bm, build_seat(width=S['rear_width'], sport=False, back_h=S['rear_back_h'], cushion_len=S['rear_cushion'], recline=S['rear_recline'],
                            bench=True), matrix=T((S['rear_x'], 0, S['rear_z'])))
    _add(bm, build_dash_utility(x_back=S['dash_x_back'], x_front=S['dash_x_front'], z_top=S['dash_z_top'], z_low=S['dash_z_low'],
                                half_width=S['hw'] - 0.03, driver_y=dy))
    _add(bm, build_pedals(x=S['dash_x_back'] + 0.16, y=dy, z=fz + 0.07))
    sx, sz = S['shifter_x'], fz + S['console_h']
    _add(bm, build_shifter(x=sx, y=0.0, z=sz))
    _add(bm, tube([(sx - 0.11, 0.075, sz + 0.02), (sx - 0.15, 0.075, sz + 0.20)], 0.0085, 8, 'M_Chrome'))                    # transfer lever
    _add(bm, prim_sphere(0.022, 12, 8, scale=(1, 1, 1.1), center=(sx - 0.153, 0.075, sz + 0.215), mat='M_IntSeat'))
    col_hub = Vector((S['dash_x_back'] - 0.06, dy, S['dash_z_top'] - 0.04))
    _add(bm, prim_cylinder(radius=0.052, depth=0.2, segments=16, axis='X', center=(col_hub.x + 0.09, col_hub.y, col_hub.z - 0.03),
                           mat='M_IntDash', rot=(0, -20, 0), bevel=0.01))
    mx, my, mz = S['mirror']
    _add(bm, prim_box((0.03, 0.22, 0.065), (mx, my, mz), mat='M_IntDash', bevel=0.012, segments=2))
    _add(bm, prim_cylinder(radius=0.008, depth=0.07, segments=8, axis='Z', center=(mx + 0.03, my, mz + 0.035), mat='M_IntDash'))
    if shell is not None:
        x0, x1 = S['door_x']
        for sd in (1, -1):
            _add(bm, shell_skin(shell, 'sill', 'belt_up', x0, x1, offset=0.045, side=sd, mat='M_IntTrim'))
            q0, q1 = S['quarter_x']
            _add(bm, shell_skin(shell, 'sill', 'belt_up', q0, q1, offset=0.045, side=sd, mat='M_IntTrim'))
        if S.get('headliner', False):
            r0, r1 = S['roof_x']
            _add(bm, shell_skin(shell, 'edge', 'edge', r0, r1, offset=0.04, wrap=True, mat='M_IntTrim'))
        xa = S['armrest_x']
        for sd in (1, -1):
            _add(bm, prim_box((0.34, 0.05, 0.05), (xa, sd * (S['hw'] - 0.08), S['dash_z_top'] - 0.23), mat='M_IntDash', bevel=0.02, segments=2))
            _add(bm, prim_box((0.20, 0.03, 0.03), (xa - 0.16, sd * (S['hw'] - 0.07), S['dash_z_top'] - 0.35), mat='M_Chrome', bevel=0.008, segments=1))
            _add(bm, tube([(xa + 0.10, sd * (S['hw'] - 0.045), S['dash_z_top'] - 0.18), (xa + 0.18, sd * (S['hw'] - 0.045), S['dash_z_top'] - 0.18)],
                          0.011, 8, 'M_TrimBlack'))
    return bm
