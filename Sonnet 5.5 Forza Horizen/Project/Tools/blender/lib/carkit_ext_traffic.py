"""
carkit_ext_traffic.py - traffic-vehicle extension of the car kit (Blender 5.2 / Python 3.13).

Load AFTER carkit.py inside the verified Blender MCP session (localhost:9889); both are exec'd into the same globals:

    _P = os.path.dirname(bpy.data.filepath)
    for _f in ("carkit.py", "carkit_ext_traffic.py"):
        exec(compile(open(os.path.join(_P, "Tools", "blender", "lib", _f), encoding="utf8").read(), _f, "exec"), globals())

carkit.py is NOT modified; everything here is built on top of its generic helpers (prim_*, bm_boolean, Surface, ...).

Contents
  1  materials        traffic_materials(): the contract materials (created only when missing) + 3 traffic-specific ones
  2  section loft     sect_loft(): boxy / rounded vehicle shells from parametric rounded-polygon cross sections
  3  windows          make_frame / win_cutter / win_glass / cabin_void : real window openings with reveals + thin glass sheets
  4  details          lamps, plates, mirrors, bumpers, tubes, racks, steps ...
  5  wheels           traffic_wheel(): tyre + rim (steel / alloy / truck / tractor lug tyre), variable wheel counts
  6  interior         seats / dash / steering wheel / driver silhouette (dark, cheap)
  7  assembly         new_vehicle(), finish helpers, UCX hulls
  8  validate/export  traffic_validate(), traffic_export() (variable number of wheels, JSON sidecar), qa
"""
import os
import json
import math
import time
import bpy
import bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

TRAFFIC_EXT_VERSION = "1.0.0"
UP = Vector((0, 0, 1))


# =====================================================================================================================
# 1. materials
# =====================================================================================================================
TRAFFIC_MATERIALS = {
    'M_Traffic_Rust': dict(base_color=(0.30, 0.085, 0.035), metallic=0.20, roughness=0.80),
    'M_Traffic_Wood': dict(base_color=(0.23, 0.14, 0.07), metallic=0.0, roughness=0.82),
}
TRAFFIC_ALLOWED = set(TRAFFIC_MATERIALS.keys())


def traffic_materials():
    """Create the contract materials that are missing (never edits an existing shared M_* material) + the traffic ones, and
    extend this namespace's MAT_ORDER so mi('M_Traffic_*') works in bmeshes (standard indices are unchanged)."""
    for n, kw in STANDARD_MATERIALS.items():
        if bpy.data.materials.get(n) is None:
            ensure_material(n, **kw)
    for n, kw in TRAFFIC_MATERIALS.items():
        if bpy.data.materials.get(n) is None:
            ensure_material(n, **kw)
        if n not in MAT_ORDER:
            MAT_ORDER.append(n)
            _MAT_INDEX[n] = len(MAT_ORDER) - 1


# Three recommended paint variants per vehicle (the engine recolours M_Paint / M_Paint2; Blender keeps the shared preview).
def paint_variants(*rows):
    """rows: (name, paint_srgb_hex, paint2_srgb_hex, metallic, roughness)"""
    def lin(h):
        h = h.lstrip('#')
        c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
        return [round(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92, 4) for v in c]
    out = []
    for (name, p1, p2, met, rough) in rows:
        out.append({"name": name, "M_Paint": {"srgb": p1, "linear": lin(p1), "metallic": met, "roughness": rough},
                    "M_Paint2": {"srgb": p2, "linear": lin(p2), "metallic": 0.0, "roughness": 0.55}})
    return out


# =====================================================================================================================
# 2. section loft
# =====================================================================================================================
def _bez_corner(pp, p, pn, cut, n):
    """Corner of a 2D polygon replaced by a quadratic Bezier (n+1 points). `cut` = distance along both edges where the curve
    starts / ends (clamped to 48 % of the shorter edge).  n <= 0 or degenerate edges give the plain vertex."""
    a, b = pp - p, pn - p
    la, lb = a.length, b.length
    if n <= 0 or la < 1e-6 or lb < 1e-6:
        return [p.copy()]
    c = max(min(cut, 0.48 * la, 0.48 * lb), 1e-3)
    t0 = p + a * (c / la)
    t1 = p + b * (c / lb)
    out = []
    for i in range(n + 1):
        s = i / float(n)
        out.append(t0 * ((1 - s) * (1 - s)) + p * (2 * s * (1 - s)) + t1 * (s * s))
    return out


def round_poly(pts, cuts, n=3):
    """Rounded polygon: pts [(u,v)...], cuts = number or list (cut distance per vertex), n segments per corner.
    Returns list of (u,v)."""
    m = len(pts)
    P = [Vector(p) for p in pts]
    if not isinstance(cuts, (list, tuple)):
        cuts = [cuts] * m
    out = []
    for i in range(m):
        k = n if cuts[i] > 0 else 0
        for q in _bez_corner(P[i - 1], P[i], P[(i + 1) % m], cuts[i], k):
            out.append((q.x, q.y))
    return out


def rrect(u0, u1, v0, v1, r=0.04, n=3):
    """Rounded-rectangle outline (u,v); r = corner cut (number or 4 values: bottom-left, bottom-right, top-right, top-left)."""
    rs = r if isinstance(r, (list, tuple)) else [r] * 4
    return round_poly([(u0, v0), (u1, v0), (u1, v1), (u0, v1)], list(rs), n)


_SEC_DEFAULT = dict(cam=0.0, cb=0.05, cw=0.02, cs=0.04, ct=0.08, zw=None, hwb=None)


def section_poly(s, ncor):
    """One cross section (YZ) of the vehicle as a rounded polygon.  Vertices (+y side first, then the -y side):
    A (hwb, zb) lower edge / B (hw, zw) lower side / C (hw, zs) shoulder (belt) / D (hwt, zt) roof (hood) edge / E (0, zt+cam)
    crown.  Returns list of Vector2 (y, z)."""
    hw, hwt, zb, zs, zt = s['hw'], s['hwt'], s['zb'], s['zs'], s['zt']
    hwb = s['hwb'] if s.get('hwb') is not None else hw - 0.02
    zw = s['zw'] if s.get('zw') is not None else zb + 0.05
    cam = s.get('cam', 0.0)
    V = [(hwb, zb, 'A'), (hw, zw, 'B'), (hw, zs, 'C'), (hwt, zt, 'D'), (0.0, zt + cam, 'E'),
         (-hwt, zt, 'D'), (-hw, zs, 'C'), (-hw, zw, 'B'), (-hwb, zb, 'A')]
    cuts = dict(A=s.get('cb', 0.05), B=s.get('cw', 0.02), C=s.get('cs', 0.04), D=s.get('ct', 0.08))
    pts = []
    m = len(V)
    for i in range(m):
        pp, p, pn = Vector(V[i - 1][:2]), Vector(V[i][:2]), Vector(V[(i + 1) % m][:2])
        k = V[i][2]
        if k == 'E':
            pts.append(p)
        else:
            pts += _bez_corner(pp, p, pn, cuts[k], ncor[k])
    return pts


def _end_ins(x, x0, x1, r0, r1):
    ins = 0.0
    if r0 > 1e-6 and x < x0 + r0:
        t = x0 + r0 - x
        ins = max(ins, r0 - math.sqrt(max(r0 * r0 - t * t, 0.0)))
    if r1 > 1e-6 and x > x1 - r1:
        t = x - (x1 - r1)
        ins = max(ins, r1 - math.sqrt(max(r1 * r1 - t * t, 0.0)))
    return ins


def end_stations(x_end, r, n=5, at_start=False):
    """Extra station positions that resolve a quarter-circle end rounding of radius r."""
    out = []
    for i in range(1, n + 1):
        t = i / float(n + 1)                       # 0..1 along the arc (angle)
        d = r * (1.0 - math.cos(t * math.pi / 2))  # distance from the end face
        out.append(x_end + d if at_start else x_end - d)
    return out


def frange(a, b, step):
    """a..b inclusive in (approximately) equal steps of `step`"""
    n = max(int(round(abs(b - a) / step)), 1)
    return [a + (b - a) * i / n for i in range(n + 1)]


def merge_stations(lists, min_gap=0.012):
    xs = sorted(set(round(x, 5) for l in lists for x in l))
    out = []
    for x in xs:
        if not out or x - out[-1] >= min_gap:
            out.append(x)
    return out


class Loft:
    """Result of sect_loft: .bm (closed shell), .xs, .cv (curves), .ring_pts, .ref/.ref_bvh (for apply_shell_normals)."""

    def at(self, x, k):
        return self.cv[k](x)

    def make_ref(self):
        self.ref = self.bm.copy()
        self.ref.normal_update()
        self.ref.faces.ensure_lookup_table()
        self.ref_bvh = BVHTree.FromBMesh(self.ref)
        return self


def sect_station_params(cv, x, ins=0.0):
    s = {k: f(x) for k, f in cv.items()}
    s.setdefault('cam', 0.0)
    if s.get('hwb') is None:
        s['hwb'] = s['hw'] - 0.02
    if s.get('zw') is None:
        s['zw'] = s['zb'] + 0.05
    if ins > 1e-9:
        s['hw'] -= ins
        s['hwb'] -= ins
        s['hwt'] -= ins
        s['zt'] -= ins
        s['zb'] += ins
        s['cam'] = s['cam'] * 0.5
        for k in ('cb', 'cw', 'cs', 'ct'):
            if k in s:
                s[k] = max(s[k] - ins * 0.5, 0.01)
    # keep the polygon ordered / non-degenerate
    s['hwt'] = max(min(s['hwt'], s['hw']), 0.03)
    s['hwb'] = max(min(s['hwb'], s['hw']), 0.03)
    s['zw'] = max(s['zw'], s['zb'] + 0.012)
    s['zs'] = max(s['zs'], s['zw'] + 0.012)
    s['zt'] = max(s['zt'], s['zs'] + 0.012)
    return s


def sect_loft(P, xs, ncor=None, r0=0.0, r1=0.0, cap=True, smooth_passes=0, smooth_strength=0.5, keep_ends=3):
    """Loft a closed vehicle shell along +X from rounded-polygon cross sections.
    P: dict of parameter curves (number | [(x,v),..] | callable): hw (max half width), hwt (half width at the roof/hood edge),
       zb (bottom z), zs (shoulder/belt z), zt (top z); optional zw, hwb, cam (crown), cb/cw/cs/ct (corner cut distances).
    xs: stations (carkit.station_list); r0 / r1: end rounding radius at the first / last station (flat end face, quarter circle).
    ncor: segments per corner dict(A,B,C,D).  smooth_passes: Laplacian smoothing of the rows along X (y, z only; the rows inside
    the end roundings are kept) - removes twists where the section changes quickly (A-pillar).
    Returns Loft (closed manifold bmesh with n-gon end caps)."""
    ncor = ncor or dict(A=2, B=1, C=2, D=3)
    cv = {k: as_curve(v) for k, v in P.items()}
    x0, x1 = xs[0], xs[-1]
    rings = []
    inset = []
    for x in xs:
        ins = _end_ins(x, x0, x1, r0, r1)
        inset.append(ins)
        s = sect_station_params(cv, x, ins)
        poly = section_poly(s, ncor)
        rings.append([Vector((x, p.x, p.y)) for p in poly])
    nr = len(rings)
    for _ in range(max(smooth_passes, 0)):
        new = {}
        for r in range(keep_ends, nr - keep_ends):
            if inset[r] > 1e-9 or inset[r - 1] > 1e-9 or inset[r + 1] > 1e-9:
                continue
            w = (xs[r] - xs[r - 1]) / (xs[r + 1] - xs[r - 1])
            new[r] = []
            for j in range(len(rings[r])):
                a, b, c = rings[r - 1][j], rings[r][j], rings[r + 1][j]
                ty, tz = a.y + (c.y - a.y) * w, a.z + (c.z - a.z) * w
                new[r].append(Vector((b.x, b.y + (ty - b.y) * smooth_strength, b.z + (tz - b.z) * smooth_strength)))
        for r, row in new.items():
            rings[r] = row
    bm = ring_loft(rings, closed=True, caps=cap)
    lf = Loft()
    lf.bm, lf.xs, lf.cv, lf.ring_pts = bm, list(xs), cv, len(rings[0])
    return lf


def inner_void(P, xs, wall, z_floor, ncor=None, mat_wall='M_IntTrim', mat_floor='M_IntCarpet', mat_roof=None):
    """Closed 'cabin void' solid following the outer sections `P` shrunk by `wall` (m), bottom at z_floor, flat end caps at the
    first / last station.  Subtracting it from the shell leaves a hollow cabin with wall thickness (inner faces keep the
    material given here), so windows cut through the wall show a real interior."""
    ncor = ncor or dict(A=1, B=1, C=2, D=3)
    cv = {k: as_curve(v) for k, v in P.items()}
    rings = []
    for x in xs:
        s = sect_station_params(cv, x)
        s2 = dict(s)
        s2['hw'] = s['hw'] - wall
        s2['hwb'] = s['hw'] - wall
        s2['hwt'] = max(s['hwt'] - wall * 1.25, 0.05)
        s2['zt'] = s['zt'] - wall
        s2['zb'] = z_floor
        s2['zw'] = z_floor + 0.04
        s2['zs'] = min(s['zs'], s2['zt'] - 0.06)
        s2['cam'] = s.get('cam', 0.0)
        for k in ('cb', 'cw', 'cs', 'ct'):
            s2[k] = max(s.get(k, 0.04) - wall * 0.5, 0.012)
        s2['cb'] = 0.02
        s2 = sect_station_params({k: (lambda v: (lambda x_: v))(v) for k, v in s2.items()}, 0.0)
        poly = section_poly(s2, ncor)
        rings.append([Vector((x, p.x, p.y)) for p in poly])
    bm = ring_loft(rings, closed=True, caps=True)
    mw, mf = mi(mat_wall), mi(mat_floor)
    mr = mi(mat_roof) if mat_roof else mw
    for f in bm.faces:
        if f.normal.z < -0.85:
            f.material_index = mf
        elif f.normal.z > 0.85:
            f.material_index = mr
        else:
            f.material_index = mw
    return bm


# =====================================================================================================================
# 3. windows: frames, cutters, glass sheets
# =====================================================================================================================
class Frame:
    """Plane frame for a window / panel feature.  O origin (a point on the plane), N outward normal, V = up the slope, U across.
    uv(h, z): world horizontal coordinate (x for side frames, y for front / rear frames) and z -> frame (u, v)."""

    def __init__(self, O, N, side_like=True):
        self.O = Vector(O)
        self.N = Vector(N).normalized()
        V = UP - self.N * UP.dot(self.N)
        self.V = V.normalized()
        U = self.V.cross(self.N)
        if side_like and U.x < 0 or (not side_like and U.y < 0):
            U = -U
        self.U = U.normalized()
        self.side_like = side_like

    def uv(self, h, z):
        if self.side_like:
            u = (h - self.O.x) / self.U.x if abs(self.U.x) > 1e-6 else 0.0
        else:
            u = (h - self.O.y) / self.U.y if abs(self.U.y) > 1e-6 else 0.0
        v = (z - self.O.z) / self.V.z if abs(self.V.z) > 1e-6 else 0.0
        return u, v

    def pt(self, u, v, d=0.0):
        return self.O + self.U * u + self.V * v + self.N * d

    def outline_world(self, pts_hz):
        """[(h, z)...] world coordinates -> [(u, v)...]"""
        return [self.uv(h, z) for (h, z) in pts_hz]


def side_frame(x, hw, zs, hwt, zt, side=+1):
    """Frame on the tumblehome plane through the belt point (hw, zs) and the roof edge point (hwt, zt) at station x.
    side=+1 left (+y), -1 right."""
    a, b = hwt - hw, zt - zs                      # a <= 0
    n = Vector((0, side * b, -a if a < 0 else 0.0))
    if n.length < 1e-9:
        n = Vector((0, side, 0))
    O = Vector((x, side * hw, zs))
    return Frame(O, n, side_like=True)


def _centroid(poly):
    return (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))


def win_cutter(frame, outline, d_in=-0.30, d_out=0.12, s_in=0.985, mat='M_TrimBlack'):
    """Closed prism cutter for a window opening: outline [(u,v)] in the frame, from depth d_in (inside) to d_out (outside) along
    the frame normal; the inner end is scaled by s_in (slight reveal taper).  Returns bmesh."""
    cu, cv_ = _centroid(outline)
    bm = bmesh.new()
    rings = []
    for d, s in ((d_in, s_in), (d_out, 1.0)):
        rings.append([bm.verts.new(frame.pt(cu + (u - cu) * s, cv_ + (v - cv_) * s, d)) for (u, v) in outline])
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[1])
    recalc(bm)
    for f in bm.faces:
        f.material_index = mi(mat)
    return bm


def win_glass(frame, outline, d=-0.014, shrink=0.992, mat='M_Glass', bulge=0.0):
    """Thin glass sheet (single n-gon polygon fan, normal along the frame normal) for a window opening."""
    cu, cv_ = _centroid(outline)
    bm = bmesh.new()
    ring = [bm.verts.new(frame.pt(cu + (u - cu) * shrink, cv_ + (v - cv_) * shrink, d)) for (u, v) in outline]
    ctr = bm.verts.new(frame.pt(cu, cv_, d + bulge))
    n = len(ring)
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new((ring[i], ring[j], ctr))
        f.material_index = mi(mat)
        f.smooth = True
    bm.normal_update()
    avg = Vector()
    for f in bm.faces:
        avg += f.normal
    if avg.dot(frame.N) < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    return bm


# =====================================================================================================================
# 4. generic detail builders (all return NEW bmeshes in car space)
# =====================================================================================================================
def box(sx, sy, sz, c, mat, bevel=0.0, seg=1, rot=(0, 0, 0)):
    return prim_box((sx, sy, sz), c, mat=mat, bevel=bevel, segments=seg, rot=rot)


def box_span(x0, x1, y0, y1, z0, z1, mat, bevel=0.0, seg=1):
    return prim_box((x1 - x0, y1 - y0, z1 - z0), ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), mat=mat, bevel=bevel, segments=seg)


def cyl(radius, depth, center, axis, mat, segs=16, radius2=None, caps=True, bevel=0.0):
    return prim_cylinder(radius=radius, depth=depth, segments=segs, axis=axis, center=center, mat=mat, radius2=radius2, caps=caps,
                         bevel=bevel, bevel_segments=1)


def tube(path, r, mat, sides=8, caps=True):
    return prim_tube(path, radius=r, sides=sides, mat=mat, caps=caps)


def put(dst, src, matrix=None, mat=None):
    """append src into dst and free src"""
    bm_append(dst, src, matrix=matrix, mat=mat)
    src.free()


def put_pair(dst, left, mat=None):
    """append a left-side (+y) bmesh and its mirror image (right side)"""
    m = mirrored_copy(left)
    bm_append(dst, left, mat=mat)
    bm_append(dst, m, mat=mat)
    left.free()
    m.free()


def lens_box(c, size, mat, bevel=0.01, seg=2):
    return prim_box(size, c, mat=mat, bevel=bevel, segments=seg)


def pocket_box(c, size, mat='M_TrimBlack', bevel=0.0, seg=1):
    return prim_box(size, c, mat=mat, bevel=bevel, segments=seg)


def plate_quad(x, y, z, w=0.52, h=0.11, face=+1, mat='M_Plate'):
    """Number plate lying in the YZ plane facing +X (face=+1) or -X"""
    bm = prim_box((0.006, w, h), (x, y, z), mat=mat, bevel=0.003, segments=1)
    return bm


def bar_x(x0, x1, y, z, r, mat, sides=8):
    return prim_tube([Vector((x0, y, z)), Vector((x1, y, z))], radius=r, sides=sides, mat=mat)


def bar_y(y0, y1, x, z, r, mat, sides=8):
    return prim_tube([Vector((x, y0, z)), Vector((x, y1, z))], radius=r, sides=sides, mat=mat)


def bar_z(z0, z1, x, y, r, mat, sides=8):
    return prim_tube([Vector((x, y, z0)), Vector((x, y, z1))], radius=r, sides=sides, mat=mat, up=(1, 0, 0))


def mirror_arm(base, tip, head_c, head_size, mat_head='M_TrimBlack', mat_arm='M_TrimBlack', mat_glass='M_Chrome', side=+1,
               bevel=0.02, face_x=-1):
    """Wing mirror: arm tube from `base` to `tip` + a rounded box head centred at head_c; mirror glass on the rear face (-X)."""
    bm = bmesh.new()
    put(bm, tube([Vector(base), Vector(tip)], 0.012, mat_arm, sides=6))
    put(bm, box(head_size[0], head_size[1], head_size[2], head_c, mat_head, bevel=bevel, seg=2))
    put(bm, box(0.006, head_size[1] * 0.86, head_size[2] * 0.86, (head_c[0] + face_x * (head_size[0] / 2 + 0.001), head_c[1], head_c[2]),
                mat_glass, bevel=0.004, seg=1))
    return bm


def extend_cutter_prism(bm_cut):
    return bm_cut


def sweep_groove(surf, pts_xz_or_3d, ray, width=0.006, depth=0.008, y=0.0, closed=False, step=0.05, mat='M_TrimBlack'):
    """Groove cutter projected on the surface.  pts: [(x,z)] (y given) or [Vector(x,y,z)]."""
    pts = []
    for p in pts_xz_or_3d:
        pts.append(Vector((p[0], y, p[1])) if len(p) == 2 else Vector(p))
    pts = resample_poly(pts + ([pts[0]] if closed else []), step)
    if closed:
        pts = pts[:-1]
    return surface_sweep(surf, pts, ray, groove_profile(width, depth), closed=closed, mat=mat)


# =====================================================================================================================
# 5. wheels (tyre + rim), variable wheel counts.  Local frame: axle = Y through the origin, outer face +Y for side=+1.
# =====================================================================================================================
def _rev(profile, segs, mat, closed=True, face_dir=(0, 1, 0)):
    """Revolve a (r, y) profile around the axle (Y).  Open profiles are oriented so that their faces look along face_dir."""
    bm = prim_revolve(profile, segments=segs, axis='Y', closed=closed, mat=mat)
    if not closed:
        bm.normal_update()
        d = Vector(face_dir)
        score = sum(f.calc_area() * f.normal.dot(d) for f in bm.faces)
        if score < 0:
            bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    return bm


def orient_closed_islands(bm):
    """Flip every CLOSED island whose signed volume is negative (thin revolve shells sometimes come out inverted)."""
    bm.normal_update()
    seen = set()
    flipped = 0
    for f0 in list(bm.faces):
        if f0 in seen:
            continue
        stack, isl, closed = [f0], [], True
        seen.add(f0)
        while stack:
            f = stack.pop()
            isl.append(f)
            for e in f.edges:
                if len(e.link_faces) != 2:
                    closed = False
                for nf in e.link_faces:
                    if nf not in seen:
                        seen.add(nf)
                        stack.append(nf)
        if closed:
            vol = sum(f.calc_area() * f.normal.dot(f.calc_center_median()) for f in isl)
            if vol < 0:
                bmesh.ops.reverse_faces(bm, faces=isl)
                flipped += 1
    return flipped


def _tyre_profile(R, W, rb, kind):
    """Closed tyre section [(r, y)] (full loop, y from -W/2 to +W/2 on the outside, back along the bead)."""
    w2 = W / 2.0
    h = R - rb
    if kind == 'simple':           # cheap truck tyre (inner wheel of a dual pair): rounded sidewall, plain tread
        half = [(rb - 0.004, 0.64 * w2), (rb + 0.012, 0.84 * w2), (rb + 0.30 * h, 1.0 * w2), (rb + 0.72 * h, 0.985 * w2),
                (R - 0.030, 0.94 * w2), (R, 0.86 * w2), (R, 0.0)]
    elif kind in ('truck', 'bus'):   # tall rounded sidewall, grooved tread (2 circumferential grooves), squared shoulder
        half = [(rb - 0.004, 0.64 * w2), (rb + 0.012, 0.84 * w2), (rb + 0.30 * h, 1.0 * w2), (rb + 0.72 * h, 0.985 * w2),
                (R - 0.030, 0.94 * w2), (R, 0.86 * w2), (R, 0.60 * w2), (R - 0.012, 0.56 * w2), (R - 0.012, 0.36 * w2), (R, 0.32 * w2), (R, 0.0)]
    else:                      # car / van / pickup: rounded shoulder, 3 tread ribs, sidewall ridge
        half = [(rb - 0.004, 0.66 * w2), (rb + 0.010, 0.86 * w2), (rb + 0.30 * h, 1.0 * w2), (rb + 0.45 * h, 1.0 * w2),
                (rb + 0.49 * h, 1.0 * w2 + 0.004), (rb + 0.53 * h, 1.0 * w2), (rb + 0.75 * h, 0.97 * w2),
                (R - 0.018, 0.90 * w2), (R, 0.80 * w2), (R, 0.62 * w2), (R - 0.008, 0.58 * w2), (R - 0.008, 0.40 * w2), (R, 0.36 * w2), (R, 0.0)]
    prof = list(half)
    for (r, y) in reversed(half[:-1]):
        prof.append((r, -y))
    return prof


def _hex_nut_ring(y, r, n, size, depth, mat, phase=90.0):
    bm = bmesh.new()
    for i in range(n):
        a = math.radians(phase) + 2 * math.pi * i / n
        nut = prim_cylinder(radius=size, depth=depth, segments=6, axis='Y', center=(r * math.cos(a), y, r * math.sin(a)), mat=mat)
        put(bm, nut)
    return bm


def lug_tyre_extras(R, W, lug_h, n_lugs):
    """Agricultural chevron lugs sitting on a base tyre of radius R - lug_h.  Returns bmesh (M_Tyre)."""
    bm = bmesh.new()
    lug_len = W * 0.5 * 0.92        # axial length of one chevron arm
    for row in (-1, 1):
        for k in range(n_lugs):
            ph = 2 * math.pi * (k + (0.5 if row > 0 else 0.0)) / n_lugs
            yc = row * W * 0.25
            rc = R - (lug_h + 0.012) * 0.5
            lg = prim_box((lug_h + 0.012, lug_len, 0.05), (0, 0, 0), mat='M_Tyre')          # height along X (radial), length along Y (1.2 cm sunk into the tyre)
            bmesh.ops.transform(lg, matrix=Matrix.Rotation(math.radians(34.0 * row), 4, 'X'), verts=lg.verts)   # chevron angle
            bmesh.ops.transform(lg, matrix=Matrix.Translation(Vector((rc, yc, 0))), verts=lg.verts)
            bmesh.ops.transform(lg, matrix=Matrix.Rotation(-ph, 4, 'Y'), verts=lg.verts)
            put(bm, lg)
    return bm


def _flat_disc(center, radius, n, mat):
    """single n-gon facing +Y (cheap fake hole / decal)"""
    bm = bmesh.new()
    vs = [bm.verts.new((center[0] + radius * math.cos(2 * math.pi * k / n), center[1], center[2] + radius * math.sin(2 * math.pi * k / n))) for k in range(n)]
    f = bm.faces.new(vs)
    f.material_index = mi(mat)
    bm.normal_update()
    if f.normal.y < 0:
        f.normal_flip()
    return bm


def _spoke_box(phi, r0, r1, w0, w1, y0, y1, th, mat):
    """tapered chamfer-less spoke (8 verts) from hub radius r0 (axial y0) to rim radius r1 (axial y1) at angle phi in the XZ plane"""
    e = Vector((math.cos(phi), 0, math.sin(phi)))
    t = Vector((-math.sin(phi), 0, math.cos(phi)))
    rings = []
    for (r, w, y) in ((r0, w0, y0), (r1, w1, y1)):
        c = e * r + Vector((0, y, 0))
        rings.append([c + t * (w / 2) + Vector((0, th / 2, 0)), c - t * (w / 2) + Vector((0, th / 2, 0)),
                      c - t * (w / 2) - Vector((0, th / 2, 0)), c + t * (w / 2) - Vector((0, th / 2, 0))])
    return ring_loft(rings, closed=True, caps=True, mat=mat)


def _disc_y(profile, r):
    """axial position of the (r, y) profile (any order) at radius r"""
    pts = sorted(profile)
    if r <= pts[0][0]:
        return pts[0][1]
    for (r0, y0), (r1, y1) in zip(pts[:-1], pts[1:]):
        if r <= r1:
            return y0 + (y1 - y0) * (r - r0) / max(r1 - r0, 1e-9)
    return pts[-1][1]


def traffic_wheel(kind='car', R=0.30, W=0.19, side=+1, segs=32, rim_r=None, nuts=5, rim_mat='M_Rim', cap_mat='M_RimDark',
                  dish=0.03, inner_only=False, lug_n=0, lug_h=0.07, hub_r=0.07, hub_proud=0.03, nut_r=None, rim_segs=None,
                  style='steel', holes=0, spokes=5, dark_mat='M_RimDark', cap_r=None):
    """One complete wheel as a bmesh: tyre (closed solid) + rim lip + dished disc + hub cap + lug nuts.  kind: 'car' | 'truck' |
    'bus' | 'tractor' (pass lug_n > 0 for the lugged farm tyre).  R tyre radius, W tyre width, rim_r rim flange radius (default
    0.62 R), inner_only = inner wheel of a dual pair (no hub / nuts).  style: 'steel' (pressed steel disc, `holes` dark hand
    holes), 'alloy' (dark disc + `spokes` tapered spokes) or 'dogdish' (steel disc + large chrome hub cap, cap_r).
    Origin = axle centre, axle = Y; outer face +Y for side=+1 (mirror-built for -1).  Rim parts are open single-sided surfaces on
    the visible side only (cheap)."""
    rb = rim_r if rim_r is not None else 0.62 * R
    rs = rim_segs or segs
    bm = bmesh.new()
    base_R = R - (lug_h if lug_n else 0.0)
    put(bm, _rev(_tyre_profile(base_R, W, rb - 0.012, 'truck' if lug_n else ('simple' if (inner_only and kind in ('truck', 'bus')) else kind)), segs, 'M_Tyre'))
    if lug_n:
        put(bm, lug_tyre_extras(R, W, lug_h, lug_n))
    rw = W * 0.74 / 2.0                     # rim half width
    y_face = rw - dish
    lip = [(rb + 0.004, rw + 0.002), (rb - 0.004, rw - 0.004), (rb - 0.022, rw - 0.016), (rb - 0.040, rw - 0.030)]
    disc = [(rb - 0.040, rw - 0.030), (rb - 0.058, y_face - dish * 0.25), (rb * 0.52, y_face - 0.006), (rb * 0.40, y_face), (hub_r * 1.15, y_face)]
    disc_mat = dark_mat if style == 'alloy' else rim_mat
    put(bm, _rev(lip, rs, rim_mat, closed=False))
    put(bm, _rev(disc, rs, disc_mat, closed=False))
    if style == 'alloy' and not inner_only:
        for i in range(spokes):
            phi = 2 * math.pi * i / spokes + math.radians(90.0)
            yh, yr = y_face + 0.008, rw - 0.016
            put(bm, _spoke_box(phi, hub_r * 1.0, rb - 0.040, 0.034, 0.050, yh, yr, 0.016, rim_mat))
    if holes and not inner_only:
        rh = rb * 0.64
        for i in range(holes):
            a = 2 * math.pi * (i + 0.5) / holes
            yy = _disc_y(disc, rh) + 0.002
            put(bm, _flat_disc((rh * math.cos(a), yy, rh * math.sin(a)), rb * 0.115, 8, dark_mat))
    if not inner_only:
        hr = hub_r
        cr = cap_r if cap_r else hr
        hubp = [(cr * 1.15, y_face), (cr * 1.02, y_face + hub_proud * 0.6), (cr * 0.78, y_face + hub_proud), (0.0, y_face + hub_proud * 1.02)]
        put(bm, _rev(hubp, max(rs // 2, 14), cap_mat, closed=False))
        if nuts > 0:
            nr = hr * 1.62 if nut_r is None else nut_r
            put(bm, _hex_nut_ring(y_face + 0.004, nr, nuts, max(0.010, hr * 0.15), 0.014, 'M_Chrome'))
    orient_closed_islands(bm)
    if side < 0:
        m = mirrored_copy(bm)
        bm.free()
        bm = m
    return bm


# =====================================================================================================================
# 6. interior (dark, cheap)
# =====================================================================================================================
def seat_block(x, y, z, w=0.50, depth=0.50, back_h=0.55, mat='M_IntSeat', headrest=True, lean=8.0):
    """Seat: cushion + back (+ headrest), x = seat reference (cushion centre), z = cushion top."""
    bm = bmesh.new()
    put(bm, box(depth, w, 0.11, (x, y, z - 0.055), mat, bevel=0.025, seg=1))
    back = box(0.10, w, back_h, (0, 0, 0), mat, bevel=0.03, seg=1)
    bmesh.ops.transform(back, matrix=Matrix.Translation(Vector((x - depth / 2 + 0.03, y, z + back_h / 2 - 0.02))) @
                        Matrix.Rotation(math.radians(lean), 4, 'Y'), verts=back.verts)
    put(bm, back)
    if headrest:
        put(bm, box(0.07, w * 0.5, 0.15, (x - depth / 2 - 0.0, y, z + back_h + 0.07), mat, bevel=0.03, seg=1))
    return bm


def driver_figure(x, y, z, scale=1.0, mat='M_IntSeat'):
    """Very simple dark driver silhouette seated with the hip point at (x, y, z): torso, head, arms to the wheel."""
    bm = bmesh.new()
    s = scale
    put(bm, box(0.20 * s, 0.38 * s, 0.50 * s, (x - 0.02 * s, y, z + 0.30 * s), mat, bevel=0.05 * s, seg=1))      # torso
    put(bm, prim_sphere(0.11 * s, u=10, v=6, center=(x, y, z + 0.69 * s), mat=mat))                                  # head
    for sy in (-1, 1):                                                                                             # arms
        put(bm, tube([Vector((x - 0.01 * s, y + sy * 0.20 * s, z + 0.48 * s)), Vector((x + 0.20 * s, y + sy * 0.18 * s, z + 0.42 * s)),
                      Vector((x + 0.40 * s, y + sy * 0.15 * s, z + 0.56 * s))], 0.04 * s, mat, sides=5))
    put(bm, box(0.40 * s, 0.30 * s, 0.14 * s, (x + 0.12 * s, y, z + 0.06 * s), mat, bevel=0.04 * s, seg=1))        # thighs
    return bm


def steering_wheel(x, y, z, r=0.19, tilt=28.0, mat='M_IntDash', mat_hub='M_TrimBlack', column=True):
    """Steering wheel (torus) with hub, tilted; hub centre at (x, y, z)."""
    bm = bmesh.new()
    t = prim_torus(R=r, r=0.016, seg_major=18, seg_minor=5, axis='X', center=(0, 0, 0), mat=mat)
    put(bm, t)
    put(bm, cyl(0.045, 0.05, (0, 0, 0), 'X', mat_hub, segs=10))
    for a in (0, 120, 240):
        ca, sa = math.cos(math.radians(a + 90)), math.sin(math.radians(a + 90))
        put(bm, tube([Vector((0, 0, 0)), Vector((0, ca * r, sa * r))], 0.009, mat_hub, sides=4, caps=True))
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector((x, y, z))) @ Matrix.Rotation(math.radians(tilt), 4, 'Y'), verts=bm.verts)
    if column:
        put(bm, tube([Vector((x - 0.03, y, z - 0.02)), Vector((x + 0.22, y, z - 0.14))], 0.03, mat_hub, sides=6))
    return bm


# =====================================================================================================================
# 7. assembly helpers
# =====================================================================================================================
def hull_box(x0, x1, y0, y1, z0, z1, ch=0.0, chz=0.0):
    """Corner points of a (chamfered) box for a convex hull; ch = chamfer in plan, chz = chamfer top/bottom"""
    pts = []
    for z, zi in ((z0, chz), (z1, -chz)):
        pts += [Vector((x0 + ch, y0, z + (zi if zi > 0 else 0))), Vector((x1 - ch, y0, z)), Vector((x1, y0 + ch, z)),
                Vector((x1, y1 - ch, z)), Vector((x1 - ch, y1, z)), Vector((x0 + ch, y1, z)), Vector((x0, y1 - ch, z)),
                Vector((x0, y0 + ch, z))]
    out = []
    # slightly pull the top ring in by chz so roof edges are chamfered
    for i, p in enumerate(pts):
        if i >= 8 and chz > 0:
            p = Vector((p.x + (chz if p.x < (x0 + x1) / 2 else -chz), p.y + (chz if p.y < (y0 + y1) / 2 else -chz), z1))
        out.append(p)
    return out


def hull_pts(rings):
    """rings: list of (x, y_half, z0, z1) -> 4 points per ring mirrored: convex-hull point cloud"""
    pts = []
    for (x, yh, z0, z1) in rings:
        for z in (z0, z1):
            pts.append(Vector((x, yh, z)))
            pts.append(Vector((x, -yh, z)))
    return pts


class Vehicle:
    """Small container for a vehicle build: ids, collection, root, parts."""
    pass


def new_vehicle(vid, index, display_name, **root_props):
    traffic_materials()
    remove_asset(vid)
    v = Vehicle()
    v.id = vid
    v.col = ensure_collection("FORZA_UE/Traffic/" + vid)
    v.root = make_empty(vid + "_ROOT", v.col, location=(14.0 * index, 30.0, 0.0), display='ARROWS', size=0.8)
    set_root_props(v.root, display_name=display_name, car_id=vid, category='traffic', **root_props)
    v.t0 = time.time()
    return v


def lap(v, msg):
    print("[%s %.2fs] %s" % (v.id, time.time() - v.t0, msg))


def bounds_of(bm_or_ob):
    if hasattr(bm_or_ob, 'data'):
        vs = [x.co for x in bm_or_ob.data.vertices]
        mn = Vector((min(a.x for a in vs), min(a.y for a in vs), min(a.z for a in vs)))
        mx = Vector((max(a.x for a in vs), max(a.y for a in vs), max(a.z for a in vs)))
        return mn, mx
    return bm_bounds(bm_or_ob)


def make_empties(v, spec):
    """spec: {name_suffix: (x, y, z)} -> empties <id>_<suffix> parented to the root."""
    out = {}
    for k, p in spec.items():
        out[k] = make_empty("%s_%s" % (v.id, k), v.col, parent=v.root, location=tuple(p), display='PLAIN_AXES', size=0.12)
    return out


def check_manifold(bm, name):
    bad = [e for e in bm.edges if len(e.link_faces) != 2]
    if bad:
        log("WARNING %s is not closed manifold: %d edges" % (name, len(bad)))
    return len(bad)


def weld(bm, d=1e-5):
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=d)
    return bm


# =====================================================================================================================
# 8. wheels -> objects, core objects, QA
# =====================================================================================================================
def add_wheels(v, specs):
    """specs: list of dict(key, x, y, R, W, side, axle, steering, driven, dual_with, order, kw=dict(traffic_wheel kwargs)).
    Creates <id>_Wheel_<key> objects (origin = axle centre, identity rotation) with the custom properties the exporter reads."""
    objs = []
    for i, sp in enumerate(specs):
        kw = dict(sp.get('kw', {}))
        bm = traffic_wheel(R=sp['R'], W=sp['W'], side=sp['side'], **kw)
        ob = finish_object("%s_Wheel_%s" % (v.id, sp['key']), bm, v.col, parent=v.root, location=(sp['x'], sp['y'], sp['R']), smooth_angle=48)
        ob['axle'] = int(sp.get('axle', 0))
        ob['side'] = 'L' if sp['y'] > 0 else 'R'
        ob['steering'] = bool(sp.get('steering', False))
        ob['driven'] = bool(sp.get('driven', False))
        ob['dual_with'] = sp.get('dual_with', '')
        ob['order'] = int(sp.get('order', i))
        objs.append(ob)
    sync_wheel_root_props(v, objs)
    return objs


def sync_wheel_root_props(v, wheels):
    """Write the MEASURED tyre width of the first and the last axle into the ROOT custom properties, so Blender, the FBX and
    the JSON sidecar agree (the tyre profile bulges a few mm beyond the nominal width)."""
    if not wheels:
        return
    axles = sorted(set(int(w.get('axle', 0)) for w in wheels))

    def width(w):
        ys = [c.co.y for c in w.data.vertices]
        return max(ys) - min(ys)
    for key, ax in (('front', axles[0]), ('rear', axles[-1])):
        v.root['wheel_width_' + key] = round(max(width(w) for w in wheels if int(w.get('axle', 0)) == ax), 4)


def remap_mats(bm, mapping):
    """Re-assign material indices of a bmesh: mapping {'M_Chrome': 'M_TrimGrey', ...} (keeps the slot count of an asset small)."""
    m = {mi(a): mi(b) for a, b in mapping.items()}
    n = 0
    for f in bm.faces:
        if f.material_index in m:
            f.material_index = m[f.material_index]
            n += 1
    return n


def heal_degenerate(me, area=1e-9):
    """Remove the last zero-area faces of a finished mesh (boolean slivers that survive finish_object): weld the vertices of
    those faces (1 mm) so the sliver collapses, then drop whatever is still degenerate.  Returns the number of faces removed."""
    bm = bmesh.new()
    bm.from_mesh(me)
    n0 = len(bm.faces)
    bad = [f for f in bm.faces if f.calc_area() < area]
    if not bad:
        bm.free()
        return 0
    bmesh.ops.remove_doubles(bm, verts=list({vv for f in bad for vv in f.verts}), dist=1e-3)
    bm.faces.ensure_lookup_table()
    bad = [f for f in bm.faces if f.calc_area() < area]
    if bad:
        bmesh.ops.delete(bm, geom=bad, context='FACES_ONLY')
    loose_e = [e for e in bm.edges if not e.link_faces]
    if loose_e:
        bmesh.ops.delete(bm, geom=loose_e, context='EDGES')
    loose = [vv for vv in bm.verts if not vv.link_edges]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(me)
    n1 = len(bm.faces)
    bm.free()
    me.update()
    return n0 - n1


def finish_core(v, body, glass, interior, hulls, body_smooth=40.0, remap=None):
    """Body / Glass / Interior objects + UCX hulls (hidden).  Returns dict of objects.  remap: material remap applied to the body."""
    if remap:
        remap_mats(body, remap)
    ob = {}
    ob['body'] = finish_object(v.id + "_Body", body, v.col, parent=v.root, smooth_angle=body_smooth)
    heal_degenerate(ob['body'].data)
    ob['glass'] = finish_object(v.id + "_Glass", glass, v.col, parent=v.root, smooth_angle=None)
    ob['interior'] = finish_object(v.id + "_Interior", interior, v.col, parent=v.root, smooth_angle=50.0)
    ob['ucx'] = make_ucx_hulls(v.id, hulls, v.col, v.root)
    for h in ob['ucx']:
        h.hide_set(True)
    return ob


def measure_root(v, ob, width=None):
    mn, mx = bounds_of(ob['body'])
    v.root['length'] = round(mx.x - mn.x, 4)
    v.root['height'] = round(mx.z, 4)
    v.root['width'] = round(width if width is not None else (mx.y - mn.y), 4)
    return mn, mx


def anchor_point(surf, p, ray, sink=0.0):
    h = surf.hit(Vector(p), ray)
    return None if h is None else h[0] - h[1] * sink


def split_planes(bm, planes):
    """Bisect the whole bmesh at the given planes [(co, normal)] so material borders / seams get real edge loops."""
    for (co, no) in planes:
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=co, plane_no=no)
    bm.normal_update()


def dir_groove(surf, pts, ray, width=0.008, depth=0.011, closed=False, step=0.06, name='groove'):
    """Groove cutter along a 3D polyline projected with ray; returns bmesh or None (logs the first missing point)."""
    pp = [Vector(p) for p in pts]
    if closed:
        pp = pp + [pp[0]]
    pp = resample_poly(pp, step)
    if closed:
        pp = pp[:-1]
    for p in pp:
        if surf.hit(p, ray) is None:
            log("WARNING %s: ray misses the surface at %s - groove dropped" % (name, tuple(round(c, 3) for c in p)))
            return None
    return surface_sweep(surf, pp, ray, groove_profile(width, depth), closed=closed, mat='M_TrimBlack')


def rib_line(surf, pts, ray, width=0.05, height=0.014, sink=0.008, round_=0.005, step=0.1, mat='M_TrimBlack', name='rib'):
    """Raised strip (moulding, rub strip, rail) hugging the skin along a 3D polyline projected with `ray`; logs misses."""
    pp = resample_poly([Vector(p) for p in pts], step)
    for p in pp:
        if surf.hit(p, ray) is None:
            log("WARNING %s: ray misses the surface at %s - rib dropped" % (name, tuple(round(c, 3) for c in p)))
            return None
    return surface_sweep(surf, pp, ray, rib_profile(width, height, sink, round_), mat=mat)


def lamp_unit_domed(surf, center, ray, outline, depth=0.05, lens_inset=0.003, lens_scale=0.96, lens_mat='M_Headlight',
                    housing_mat='M_TrimBlack', floor_mat='M_Chrome', taper=0.85, lift=0.03, rings=3, bulge=0.012):
    """carkit.lamp_unit with a convex (domed) lens: the lens patch bulges `bulge` m outwards in the middle, so the lamp catches
    highlights instead of reading as a flat disc.  Returns (cutter_bm, lens_bm)."""
    cut = pocket_cutter(surf, outline, center, ray, depth=depth, lift=lift, taper=taper, mat=housing_mat)
    if cut is None:
        return None, None
    c0 = surf.hit(Vector(center), ray)
    for f in cut.faces:
        if (f.calc_center_median() - c0[0]).dot(c0[1]) < -depth * 0.8:
            f.material_index = mi(floor_mat)
    lens = surface_patch(surf, outline, center, ray, offset=lens_inset, rings=rings, mat=lens_mat, scale=lens_scale, bulge=bulge)
    return cut, lens


def lens_pair(surf, center_left, ray, outline, depth, mat, lens_scale=0.94, lens_inset=0.003, housing='M_TrimBlack', floor='M_TrimBlack',
              taper=0.9, bulge=0.0, rings=3):
    """lamp_unit on both sides (center_left has y > 0): returns ([cutters], [lenses]).  bulge > 0 gives domed lenses."""
    cuts, lens = [], []
    for sd in (1, -1):
        c = Vector((center_left[0], sd * center_left[1], center_left[2]))
        if bulge > 0.0:
            cu, le = lamp_unit_domed(surf, c, ray, outline, depth=depth, lens_inset=lens_inset, lens_scale=lens_scale, lens_mat=mat,
                                     housing_mat=housing, floor_mat=floor, taper=taper, rings=rings, bulge=bulge)
        else:
            cu, le = lamp_unit(surf, c, ray, outline, depth=depth, lens_inset=lens_inset, lens_scale=lens_scale, lens_mat=mat,
                               housing_mat=housing, floor_mat=floor, taper=taper)
        if cu is not None:
            cuts.append(cu)
            lens.append(le)
    return cuts, lens


def rust_patch(surf, center, ray, size, seed=1, n=18, mat='M_Traffic_Rust', offset=-0.003, rings=2, squash=(1.0, 1.0)):
    """Irregular rust / patina patch hugging the skin (deterministic blob outline from `seed`).  Returns bmesh or None."""
    import random
    rnd = random.Random(seed)
    ph = [rnd.random() * 6.283 for _ in range(3)]
    amp = [0.30, 0.16, 0.08]
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        r = size * (0.62 + sum(amp[k] * math.sin((k + 2) * a + ph[k]) for k in range(3)) + 0.06 * rnd.random())
        out.append((r * math.cos(a) * squash[0], r * math.sin(a) * squash[1]))
    return surface_patch(surf, out, Vector(center), ray, offset=offset, rings=rings, mat=mat)
