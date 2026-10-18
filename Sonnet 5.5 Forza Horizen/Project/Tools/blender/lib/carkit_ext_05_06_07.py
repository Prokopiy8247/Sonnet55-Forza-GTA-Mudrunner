"""
carkit_ext_05_06_07.py - extra generic helpers for the player cars 05 (Meridian GT), 06 (Aether) and 07 (Ridge).
Load AFTER carkit.py in the same namespace:
    exec(compile(open(KIT, encoding="utf8").read(), KIT, "exec"), globals())
    exec(compile(open(EXT, encoding="utf8").read(), EXT, "exec"), globals())
Nothing here edits carkit.py; everything is built on its public helpers (bmesh in car space, global material indices).
"""
import math
import bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

EXT_VERSION = "1.0"


# ======================================================================================================================
# shell sculpting: displace the lofted shell (before cutters / projections) and refresh the reference surface
# ======================================================================================================================
def refresh_shell(shell):
    """Re-sync shell.pos / shell.ref / shell.ref_bvh after the shell vertices were moved (shell_deform)."""
    shell.bm.normal_update()
    shell.pos = [[Vector(v.co) for v in row] for row in shell.rows]
    shell.ref.free()
    shell.ref = shell.bm.copy()
    shell.ref.normal_update()
    shell.ref.faces.ensure_lookup_table()
    shell.ref_bvh = BVHTree.FromBMesh(shell.ref)


def shell_deform(shell, fn, refresh=True):
    """Move every vertex of the (mirror symmetric) shell.  fn(x, ay, z) -> (dx, dy, dz) with ay = |y|; dy is applied away from
    the centre line (so the result stays symmetric); the centre-line vertices never move sideways."""
    for v in shell.bm.verts:
        x, y, z = v.co.x, v.co.y, v.co.z
        s = 1.0 if y >= 0 else -1.0
        dx, dy, dz = fn(x, abs(y), z)
        if abs(y) < 1e-7:
            dy = 0.0
        v.co.x = x + dx
        v.co.y = y + s * dy
        v.co.z = z + dz
    if refresh:
        refresh_shell(shell)


def bump(x, y, z, cx, cy, cz, rx, ry, rz, amp):
    """smooth 3-D bump (cosine falloff on an ellipsoid) used by the sculpt functions"""
    d = math.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2)
    if d >= 1.0:
        return 0.0
    t = 0.5 + 0.5 * math.cos(math.pi * d)
    return amp * t


# ======================================================================================================================
# generic small builders
# ======================================================================================================================
def box_between(p0, p1, w=0.02, h=0.02, mat='M_TrimBlack', bevel=0.003, up=(0, 0, 1)):
    """Rectangular bar from p0 to p1 (section w x h; w along the in-plane normal)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    L = d.length
    if L < 1e-6:
        return bmesh.new()
    x = d.normalized()
    z = Vector(up)
    y = z.cross(x)
    if y.length < 1e-6:
        y = Vector((0, 1, 0))
    y.normalize()
    z = x.cross(y).normalized()
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = (p0 + p1) * 0.5
    bm = prim_box((L, w, h), (0, 0, 0), mat=mat, bevel=bevel, segments=1)
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm


def add_all(bm, parts):
    for p in parts:
        if p is not None:
            bm_append(bm, p)
            p.free()


def tube_path(pts, r=0.01, sides=8, mat='M_TrimGrey', caps=True):
    return prim_tube([Vector(p) for p in pts], radius=r, sides=sides, mat=mat, caps=caps)


def lerp3(a, b, t):
    return Vector(a) * (1.0 - t) + Vector(b) * t


# ======================================================================================================================
# wheels
# ======================================================================================================================
def swap_tyre(bm, tyre_bm):
    """Replace the M_Tyre faces of a wheel bmesh (from build_wheel) with `tyre_bm`."""
    mt = mi('M_Tyre')
    old = [f for f in bm.faces if f.material_index == mt]
    if old:
        bmesh.ops.delete(bm, geom=old, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm_append(bm, tyre_bm)
    tyre_bm.free()
    return bm


def _sector_prism(bm, poly, th0, th1, th0t=None, th1t=None, shrink_top=0.0, mat='M_Tyre'):
    """Add a lug: the closed (r, y) polygon `poly` (list of (r, y)) swept around the Y axis from th0 to th1 (radians).  Points
    whose index is in the upper half of the polygon (r larger than the mean) can be shifted in angle by th0t/th1t (slanted
    block).  Walls + two end caps."""
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


def build_gravel_tyre(R=0.33, w=0.215, rb=0.1905, segs=64, lug_h=0.024, n_lug=26, mat='M_Tyre'):
    """Chunky gravel tyre: tall sidewall with embossed ring, flat tread base and three staggered rows of slanted lugs per side
    (two on the tread, one wrapping the shoulder).  Local frame like build_wheel: axle = Y, origin = axle centre."""
    w2 = w / 2.0
    base = R - lug_h * 0.9          # tread base radius
    sw = [(rb - 0.004, 0.64 * w2), (rb + 0.008, 0.74 * w2), (rb + 0.028, 0.93 * w2), (rb + 0.075, 0.995 * w2),
          (base - 0.075, 1.0 * w2), (base - 0.040, 0.975 * w2), (base - 0.020, 0.915 * w2), (base - 0.006, 0.84 * w2),
          (base, 0.74 * w2), (base, 0.0)]
    # sidewall emboss ring (small raised ridge) halfway up the sidewall
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
    tread_r = base
    step = 2.0 * math.pi / n_lug
    top = R
    for side in (1, -1):
        for k in range(n_lug):
            # inner tread row (blocks hugging the centre): slanted
            for (yc, ww, ph, sk) in ((0.030, 0.050, 0.0, 0.020), (0.087, 0.042, 0.5, 0.030)):
                a0 = (k + ph) * step
                hl = step * 0.27
                y0, y1 = side * (yc - ww / 2), side * (yc + ww / 2)
                if side < 0:
                    y0, y1 = y1, y0
                pol = [(tread_r - 0.003, y0), (tread_r - 0.003, y1), (top, y1 - side * 0.004), (top, y0 + side * 0.004)]
                if side < 0:
                    pol = list(reversed(pol))
                _sector_prism(bm, pol, a0 - hl, a0 + hl, a0 - hl + sk * side, a0 + hl + sk * side)
            # shoulder lug wraps the shoulder curve (follows profile points 5..8)
            a0 = (k + 0.25) * step
            hl = step * 0.24
            curve = [(base - 0.030, 0.975 * w2), (base - 0.020, 0.93 * w2), (base - 0.006, 0.86 * w2), (base + 0.004, 0.77 * w2)]
            outer = [(r + 0.016, y) for (r, y) in curve]
            inner = [(r - 0.002, y) for (r, y) in curve]
            pol = [(p[0], p[1] * side) for p in inner] + [(p[0], p[1] * side) for p in reversed(outer)]
            if side < 0:
                pol = list(reversed(pol))
            _sector_prism(bm, pol, a0 - hl, a0 + hl)
    recalc(bm)
    return bm


def build_wheel_gravel(radius=0.33, width=0.215, rim_radius=0.2032, style='star', spokes=6, side=+1, segments=48, **kw):
    """build_wheel with the stock tyre replaced by the gravel tyre (the rim part comes from the kit)."""
    kw.setdefault('tread', False)
    bm = build_wheel(radius=radius, width=width, rim_radius=rim_radius, style=style, spokes=spokes, side=+1,
                     segments=segments, **kw)
    tyre = build_gravel_tyre(R=radius, w=width, rb=rim_radius - 0.0127, segs=segments + 16)
    swap_tyre(bm, tyre)
    if side < 0:
        m = mirrored_copy(bm)
        bm.free()
        bm = m
    return bm


# ======================================================================================================================
# interior (parametrised copy of carkit.build_interior: every x position comes from the spec, nothing is hard-wired)
# ======================================================================================================================
def build_interior_ext(shell=None, spec=None):
    S = dict(floor_z=0.22, front_x=-0.12, driver_y=0.36, rear_x=-0.98, rear_width=1.22, dash_x_back=0.46, dash_x_front=0.82,
             dash_z_top=0.93, dash_z_low=0.52, hw=0.74, x_front_floor=0.80, x_rear_floor=-1.72, door_x=(-0.58, 0.64),
             quarter_x=(-1.72, -0.58), roof_x=(-1.72, 0.12), seats_rear=True, rear_z=0.26, front_z=0.27, back_h=0.62, sport=True,
             console=(-0.40, 0.46), console_h=0.30, shifter_x=0.10, mirror=(0.30, 0.0, 1.30), rear_cushion=0.46,
             rear_recline=18.0, front_recline=22.0, seat_w=0.50, headliner=True, armrest_x=0.06, rear_back_h=0.56,
             door_cards=True, rear_bench=True, seat_headrest=True, pedals=True, column=True)
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
        _add(bm, build_seat(width=S['seat_w'], sport=S['sport'], back_h=S['back_h'], recline=S['front_recline'], headrest=S['seat_headrest']),
             matrix=T((S['front_x'], yy, S['front_z'])))
    if S['seats_rear']:
        _add(bm, build_seat(width=S['rear_width'], sport=False, back_h=S['rear_back_h'], cushion_len=S['rear_cushion'],
                            recline=S['rear_recline'], bench=True), matrix=T((S['rear_x'], 0, S['rear_z'])))
    _add(bm, build_dash(x_back=S['dash_x_back'], x_front=S['dash_x_front'], z_top=S['dash_z_top'], z_low=S['dash_z_low'],
                        half_width=S['hw'] - 0.03, driver_y=dy))
    if S['pedals']:
        _add(bm, build_pedals(x=S['dash_x_back'] + 0.16, y=dy, z=fz + 0.07))
    _add(bm, build_shifter(x=S['shifter_x'], y=0.0, z=fz + S['console_h']))
    if S['column']:
        col_hub = Vector((S['dash_x_back'] - 0.06, dy, S['dash_z_top'] - 0.04))
        _add(bm, prim_cylinder(radius=0.048, depth=0.2, segments=16, axis='X', center=(col_hub.x + 0.09, col_hub.y, col_hub.z - 0.03),
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
        if S.get('headliner', True):
            r0, r1 = S['roof_x']
            _add(bm, shell_skin(shell, 'edge', 'edge', r0, r1, offset=0.04, wrap=True, mat='M_IntTrim'))
        if S['door_cards']:
            xa = S['armrest_x']
            for sd in (1, -1):
                _add(bm, prim_box((0.34, 0.05, 0.05), (xa, sd * (S['hw'] - 0.08), S['dash_z_top'] - 0.23), mat='M_IntDash', bevel=0.02, segments=2))
                _add(bm, prim_box((0.20, 0.03, 0.03), (xa - 0.16, sd * (S['hw'] - 0.07), S['dash_z_top'] - 0.35), mat='M_Chrome', bevel=0.008, segments=1))
    return bm


# ======================================================================================================================
# body refinements after the boolean
# ======================================================================================================================
def bevel_arch_lips(bm, wheels, pad, tc, width=0.010, segments=2, y_min=0.45):
    """Round the outer rim of every wheel-arch hole: edges whose vertices lie on the arch cylinder and that separate a skin
    face (TAG_COL != 0) from a cutter face (tag 0).  Returns the number of edges bevelled."""
    sel = []
    seen = set()
    for name, w in wheels.items():
        cx, cy, cz = w['center']
        R = w['radius'] + pad
        for e in bm.edges:
            if e in seen or len(e.link_faces) != 2:
                continue
            if not all(abs(math.hypot(v.co.x - cx, v.co.z - cz) - R) < 4e-4 and abs(v.co.y) > y_min for v in e.verts):
                continue
            a, b = e.link_faces
            if (a[tc] != 0) == (b[tc] != 0):
                continue
            seen.add(e)
            sel.append(e)
    if not sel:
        return 0
    try:
        bmesh.ops.bevel(bm, geom=sel, offset=width, segments=segments, profile=0.5, material=-1, affect='EDGES', clamp_overlap=True)
    except Exception as ex:
        print("bevel_arch_lips failed:", ex)
        return 0
    return len(sel)


# ======================================================================================================================
# vents, louvres, engine bay, wings
# ======================================================================================================================
def slat_vent(surf, center, ray, U, V, w, h, n, depth=0.03, slat_mat='M_TrimBlack', wall_mat='M_TrimBlack', corner=0.02, lift=0.03,
              slat_w=0.0030, taper=1.0):
    """Rounded-rectangle pocket (w along U, h along V) with n slats running along U spaced along V.  Returns (cutter, [slat_bms])
    for the LEFT side (mirror both for the right side).  center = a point on the ray line, ray = parallel direction."""
    U, V = Vector(U), Vector(V)
    cut = pocket_cutter(surf, outline_rrect(w, h, corner, 3), Vector(center), ray, depth=depth, lift=lift, taper=taper, mat=wall_mat,
                        floor_follows=True, axes=(U, V))
    if cut is None:
        return None, []
    ins = []
    L = w * 0.5 - corner * 0.8
    prof = [(-slat_w, -depth * 0.8), (slat_w, -depth * 0.8), (slat_w, -0.0015), (-slat_w, -0.0015)]
    for k in range(n):
        v = -h / 2 + (k + 0.5) * h / n
        pts = [Vector(center) + U * (L * (2.0 * i / 6.0 - 1.0)) + V * v for i in range(7)]
        sl = surface_sweep(surf, pts, ray, prof, mat=slat_mat)
        if sl is not None:
            ins.append(sl)
    return cut, ins


def build_louvre_slats(xs, y_half, z_fn, tilt=35.0, thick=0.010, height=0.050, mat='M_TrimBlack', spine=True, spine_mat='M_TrimBlack'):
    """Parallel louvre slats (transverse, tilted about Y) at the x positions `xs`; y_half / z_fn may be numbers or callables of x.
    Returns bmesh in car space."""
    bm = bmesh.new()
    yh = y_half if callable(y_half) else (lambda x: y_half)
    zf = z_fn if callable(z_fn) else (lambda x: z_fn)
    for x in xs:
        b = prim_box((thick, 2.0 * yh(x), height), (0, 0, 0), mat=mat, bevel=0.002, segments=1)
        bmesh.ops.transform(b, matrix=T((x, 0, zf(x)), (0, tilt, 0)), verts=b.verts)
        bm_append(bm, b)
        b.free()
    if spine and len(xs) > 1:
        x0, x1 = min(xs), max(xs)
        b = prim_box((x1 - x0 + 0.06, 0.035, 0.03), ((x0 + x1) / 2, 0, zf((x0 + x1) / 2) - 0.012), mat=spine_mat, bevel=0.006, segments=1)
        bm_append(bm, b)
        b.free()
    return bm


def build_engine_bay(x0=-1.95, x1=-0.60, z_floor=0.28, half_w=0.60):
    """Mid-engine bay detail visible through the glass engine hatch: undertray, transaxle, V8 block with red cam covers, intake
    plenum + trumpets, exhaust headers, chrome strut brace.  Car space bmesh."""
    bm = bmesh.new()
    xc = (x0 + x1) * 0.5 + 0.10
    zb = z_floor
    _add(bm, prim_box((x1 - x0, 2 * half_w, 0.025), ((x0 + x1) / 2, 0, zb - 0.0125), mat='M_Underbody', bevel=0.006, segments=1))
    _add(bm, prim_box((0.36, 0.42, 0.25), (xc - 0.56, 0, zb + 0.15), mat='M_TrimGrey', bevel=0.04, segments=2))       # transaxle
    _add(bm, prim_box((0.64, 0.46, 0.20), (xc, 0, zb + 0.13), mat='M_TrimGrey', bevel=0.035, segments=2))               # block
    for s in (1, -1):                                                                                                  # heads + red covers
        _add(bm, prim_box((0.60, 0.17, 0.11), (xc, s * 0.20, zb + 0.27), mat='M_RimDark', bevel=0.02, segments=2, rot=(-s * 22, 0, 0)))
        _add(bm, prim_box((0.54, 0.13, 0.04), (xc, s * 0.235, zb + 0.335), mat='M_Caliper', bevel=0.012, segments=2, rot=(-s * 22, 0, 0)))
        for k in range(4):
            _add(bm, prim_cylinder(radius=0.011, depth=0.03, segments=8, axis='Z', center=(xc - 0.21 + 0.14 * k, s * 0.235, zb + 0.365), mat='M_Chrome'))
    _add(bm, prim_box((0.40, 0.24, 0.05), (xc - 0.02, 0, zb + 0.37), mat='M_Exhaust', bevel=0.02, segments=2))        # plenum
    for ix in range(4):
        for iy in (-1, 1):
            _add(bm, prim_cylinder(radius=0.024, depth=0.07, segments=12, axis='Z', center=(xc - 0.16 + 0.107 * ix, iy * 0.075, zb + 0.43),
                                   mat='M_Chrome', radius2=0.030))
    for s in (1, -1):                                                                                                  # headers
        path = [(xc + 0.30, s * 0.30, zb + 0.18), (xc + 0.12, s * 0.38, zb + 0.10), (xc - 0.30, s * 0.34, zb + 0.07),
                (xc - 0.62, s * 0.26, zb + 0.07), (x0 + 0.10, s * 0.24, zb + 0.07)]
        _add(bm, prim_tube(path, radius=0.027, sides=10, mat='M_Exhaust'))
    _add(bm, prim_tube([(xc + 0.16, -0.50, zb + 0.46), (xc + 0.16, 0.50, zb + 0.46)], radius=0.011, sides=8, mat='M_Chrome'))   # strut brace
    for s in (1, -1):
        _add(bm, prim_cylinder(radius=0.016, depth=0.26, segments=8, axis='Z', center=(xc + 0.16, s * 0.50, zb + 0.34), mat='M_Chrome'))
    return bm


def _airfoil_pts(chord, thick, n=14):
    pts = []
    for i in range(n + 1):
        t = i / float(n)
        x = chord * (0.5 - t)
        z = thick * 0.5 * (1 - (2 * t - 1) ** 2) ** 0.7 + thick * 0.15 * (1 - t)
        pts.append((x, z))
    for i in range(n - 1, 0, -1):
        t = i / float(n)
        x = chord * (0.5 - t)
        pts.append((x, -thick * 0.35 * (1 - (2 * t - 1) ** 2) ** 0.7))
    return pts


def build_swan_wing(span=1.50, chord=0.27, thick=0.034, rake=-6.0, stand_y=0.38, drop=0.17, mat='M_Paint2', mat_stand='M_TrimBlack',
                    endplate_h=0.14):
    """GT / supercar rear wing in its own frame (blade centre at the origin, leading edge +X, z up): airfoil blade, tall swan-neck
    pylons that attach to the TOP of the blade (reaching `drop` m below the blade), end plates with a swept top.  Returns bmesh."""
    bm = bmesh.new()
    blade = prim_prism(_airfoil_pts(chord, thick), span, plane='XZ', mat=mat)
    bmesh.ops.transform(blade, matrix=T(rot=(0, rake, 0)), verts=blade.verts)
    _add(bm, blade)
    for s in (-1, 1):
        path = [(-0.085, s * stand_y, -drop), (-0.085, s * stand_y, -drop * 0.35), (-0.075, s * stand_y, 0.010), (-0.040, s * stand_y, 0.062),
                (0.020, s * stand_y, 0.060), (0.075, s * stand_y, 0.034)]
        _add(bm, prim_tube(path, radius=(0.011, 0.020), sides=10, mat=mat_stand))
        # end plate: swept trapezoid
        ep = [(chord * 0.52, -0.012), (-chord * 0.52, -0.020), (-chord * 0.55, endplate_h * 0.62), (-chord * 0.20, endplate_h),
              (chord * 0.30, endplate_h * 0.55)]
        _add(bm, prim_prism(ep, 0.010, plane='XZ', center=(0, s * (span / 2 + 0.005), 0), mat=mat))
    return bm


def conform_to_surface(bm, surf, center, ray, U, V, sink=0.02, far=6.0):
    """Wrap an insert that was modelled in the YZ plane facing +X (grille_mesh etc., origin = its centre) onto the skin: every
    vertex (lx, ly, lz) is projected along `ray` from the point center + U*ly + V*lz and placed at hit - ray_dir * (lx - sink).
    U / V = the world directions of the insert's local +Y / +Z (see anchor_frame: for a side panel with ray (0,-1,0) U = (-1,0,0),
    for the nose ray (-1,0,0) U = (0,1,0), for the tail ray (1,0,0) U = (0,-1,0); V = (0,0,1))."""
    c = Vector(center)
    U, V = Vector(U), Vector(V)
    moved = 0
    for v in bm.verts:
        lx, ly, lz = v.co.x, v.co.y, v.co.z
        h = surf.hit(c + U * ly + V * lz, ray, far)
        if h is None:
            continue
        loc, nor = h
        d = surf.dir_at(c + U * ly + V * lz, ray)          # insert thickness is kept along the projection ray (no skew on curved corners)
        v.co = loc - d * (lx - sink)
        moved += 1
    return moved


# ======================================================================================================================
# rally parts: roof scoop, spot-light pod, mud flap, tow hook, double-plane wing, roll cage, harness
# ======================================================================================================================
def build_roof_scoop(surf, x0, x1, half_w, h, n_x=10, n_y=12, mat='M_Paint2', open_mat='M_TrimBlack', sink=0.010):
    """Forward-facing roof air scoop: a hump that starts with its full height `h` at x1 (front, opening facing +X) and fades into the
    roof skin at x0 (rear).  Rings follow the roof camber (ray casts on the uncut skin).  Returns bmesh or None."""
    rings = []
    for k in range(n_x + 1):
        t = k / float(n_x)                       # 0 = front opening, 1 = rear (flush)
        x = x1 + (x0 - x1) * t
        hh = h * (1.0 - t) ** 1.35 if t < 1.0 else 0.0
        ww = half_w * (1.0 - 0.38 * t)
        top, bot = [], []
        for j in range(n_y + 1):
            u = -1.0 + 2.0 * j / n_y
            y = u * ww
            hit = surf.hit(Vector((x, y, 0.0)), (0, 0, -1))
            if hit is None:
                return None
            z = hit[0].z
            top.append(Vector((x, y, z - sink + hh * math.sqrt(max(1.0 - u * u, 0.0)) ** 0.9)))
            bot.append(Vector((x, y, z - sink * 1.5)))
        rings.append(top + list(reversed(bot[1:-1])))
    bm = ring_loft(rings, closed=True, caps=True, mat=mat)
    bm.faces.ensure_lookup_table()
    # the front cap (largest x) is the opening: black
    fc = max(bm.faces, key=lambda f: f.calc_center_median().x if len(f.verts) > 4 else -1e9)
    fc.material_index = mi(open_mat)
    return bm


def build_spot_pod(width=0.92, lamps=4, r=0.072, depth=0.085, mat_body='M_TrimBlack'):
    """Auxiliary lamp bar in its own frame: lens faces +X, bar centre at the origin (bar axis Y), mounting feet reach down to z=-0.12.
    Returns bmesh."""
    bm = bmesh.new()
    _add(bm, prim_box((0.05, width + 0.04, 0.05), (-depth * 0.55, 0, 0), mat=mat_body, bevel=0.008, segments=1))
    pitch = (width - 2 * r) / (lamps - 1)
    for i in range(lamps):
        y = -width / 2 + r + i * pitch
        _add(bm, prim_cylinder(radius=r, depth=depth, segments=26, axis='X', center=(0, y, 0), mat=mat_body, bevel=0.004, bevel_segments=1))
        _add(bm, prim_torus(R=r - 0.004, r=0.0055, seg_major=26, seg_minor=6, axis='X', center=(depth / 2 + 0.002, y, 0), mat='M_Chrome'))
        _add(bm, prim_cylinder(radius=r - 0.011, depth=0.006, segments=26, axis='X', center=(depth / 2 - 0.0005, y, 0), mat='M_Headlight'))
        _add(bm, prim_cylinder(radius=0.022, depth=0.004, segments=14, axis='X', center=(depth / 2 + 0.0015, y, 0), mat='M_Reverse'))
    for s in (-1, 1):
        _add(bm, prim_box((0.05, 0.035, 0.13), (-depth * 0.55, s * (width / 2 - 0.05), -0.095), mat=mat_body, bevel=0.006, segments=1))
    return bm


def build_mud_flap(w=0.22, h=0.26, t=0.012):
    """Mud flap hanging behind a wheel (plane normal along X, origin = top centre).  Returns bmesh."""
    bm = bmesh.new()
    _add(bm, prim_box((t, w, h), (0, 0, -h / 2), mat='M_Rubber', bevel=0.003, segments=1))
    _add(bm, prim_box((t * 0.6, w * 0.55, 0.012), (t * 0.9, 0, -h * 0.80), mat='M_TrimGrey', bevel=0.002, segments=1))
    _add(bm, prim_box((t * 1.6, w + 0.012, 0.02), (0, 0, -0.01), mat='M_TrimBlack', bevel=0.003, segments=1))
    return bm


def build_tow_hook(front=True):
    """Red tow eye (loop in the horizontal plane) on a bracket; origin = bracket anchor on the bumper skin, loop protrudes to +X
    (front=True) or -X."""
    bm = bmesh.new()
    sg = 1.0 if front else -1.0
    _add(bm, prim_box((0.05, 0.05, 0.04), (sg * 0.0, 0, 0), mat='M_TrimBlack', bevel=0.006, segments=1))
    _add(bm, prim_cylinder(radius=0.0115, depth=0.05, segments=10, axis='X', center=(sg * 0.04, 0, 0), mat='M_Caliper'))
    _add(bm, prim_torus(R=0.040, r=0.0115, seg_major=22, seg_minor=8, axis='Z', center=(sg * 0.085, 0, 0), mat='M_Caliper'))
    return bm


def build_rally_wing(span=1.46, chord=0.36, flap_chord=0.20, gap=0.095, thick=0.04, plate_h=0.34, mat='M_Paint2', mat_plate='M_Paint'):
    """Big double-plane rally wing in its own frame: origin = centre of the main plane (leading edge +X), upper flap `gap` above and
    behind, tall end plates with a cut-out, two raked pylons that reach down to z = -0.26.  Returns bmesh."""
    bm = bmesh.new()
    main = prim_prism(_airfoil_pts(chord, thick), span, plane='XZ', mat=mat)
    bmesh.ops.transform(main, matrix=T(rot=(0, -8, 0)), verts=main.verts)
    _add(bm, main)
    flap = prim_prism(_airfoil_pts(flap_chord, thick * 0.7), span * 0.97, plane='XZ', mat=mat)
    bmesh.ops.transform(flap, matrix=T((-chord * 0.30, 0, gap), (0, -26, 0)), verts=flap.verts)
    _add(bm, flap)
    for s in (-1, 1):
        outline = [(chord * 0.62, -plate_h * 0.34), (-chord * 0.56, -plate_h * 0.34), (-chord * 0.66, plate_h * 0.52), (-chord * 0.18, plate_h * 0.66),
                   (chord * 0.40, plate_h * 0.40)]
        _add(bm, prim_prism(outline, 0.012, plane='XZ', center=(0, s * (span / 2 + 0.006), 0.04), mat=mat_plate))
        _add(bm, prim_tube([(0.02, s * 0.46, -0.26), (-0.04, s * 0.46, -0.10), (-0.07, s * 0.46, 0.0)], radius=(0.014, 0.030), sides=8,
                           mat='M_TrimBlack'))
    return bm


def build_roll_cage(x_hoop=-0.76, x_a_base=0.56, x_a_top=0.14, y_half=0.60, z_floor=0.32, z_roof=1.29, z_dash=0.84, x_rear=-1.50,
                    r=0.0215, mat='M_IntTrim'):
    """Rally roll cage (tube sweeps): main hoop with diagonal, A-pillar hoops + roof bars, door bars (X), rear stays, rear brace.
    Car-space bmesh."""
    bm = bmesh.new()

    def tube(pts, rr=r):
        _add(bm, prim_tube([Vector(p) for p in pts], radius=rr, sides=8, mat=mat))

    yh = y_half
    c = 0.07
    tube([(x_hoop, yh, z_floor), (x_hoop, yh, z_roof - 0.12), (x_hoop, yh - 0.02, z_roof - 0.05), (x_hoop, yh - c, z_roof),
          (x_hoop, -(yh - c), z_roof), (x_hoop, -(yh - 0.02), z_roof - 0.05), (x_hoop, -yh, z_roof - 0.12), (x_hoop, -yh, z_floor)])
    tube([(x_hoop, yh * 0.92, z_roof - 0.14), (x_hoop, 0.0, (z_roof + z_floor) * 0.5), (x_hoop, -yh * 0.92, z_floor + 0.30)], rr=r * 0.9)
    tube([(x_hoop, -yh * 0.92, z_roof - 0.14), (x_hoop, 0.0, (z_roof + z_floor) * 0.5), (x_hoop, yh * 0.92, z_floor + 0.30)], rr=r * 0.9)
    for s in (1, -1):
        tube([(x_hoop, s * (yh - c), z_roof), (x_hoop + 0.35, s * (yh - 0.02), z_roof - 0.01), (x_a_top, s * (yh - 0.03), z_roof - 0.04),
              (x_a_base - 0.04, s * (yh + 0.0), z_dash + 0.10), (x_a_base, s * yh, z_dash), (x_a_base + 0.02, s * yh, z_floor + 0.02)])
        tube([(x_a_base, s * yh, 0.64), (-0.1, s * yh, 0.64), (x_hoop, s * yh, 0.64)])
        tube([(x_a_base, s * yh, 0.50), (-0.1, s * yh, 0.72), (x_hoop, s * yh, 0.50)], rr=r * 0.85)
        tube([(x_hoop, s * (yh - c), z_roof), (-1.15, s * 0.56, 0.95), (x_rear, s * 0.50, z_floor + 0.04)])
        tube([(x_hoop, s * yh, z_floor + 0.02), (x_rear, s * 0.50, z_floor + 0.04)], rr=r * 0.85)
    tube([(x_a_top, -(yh - 0.03), z_roof - 0.04), (x_a_top, 0.0, z_roof - 0.02), (x_a_top, yh - 0.03, z_roof - 0.04)])
    tube([(x_hoop, 0.0, z_roof), (x_a_top, 0.0, z_roof - 0.02)], rr=r * 0.85)
    tube([(x_rear, -0.50, z_floor + 0.04), (x_rear, 0.50, z_floor + 0.04)], rr=r * 0.9)
    return bm


def build_harness(base, seat_w=0.50, back_h=0.60, recline=20.0):
    """Four-point racing harness for a seat whose origin (cushion centre on the floor) is `base` in car space: two shoulder straps
    from the head-rest height to the lap belt + lap belt + buckle.  M_Caliper (red webbing) + chrome buckle."""
    bm = bmesh.new()
    bx, by, bz = base
    top = Vector((bx - 0.06 - math.sin(math.radians(recline)) * back_h, by, bz + 0.16 + math.cos(math.radians(recline)) * back_h * 0.92))
    lap_c = Vector((bx + 0.10, by, bz + 0.27))
    for s in (-1, 1):
        a = top + Vector((0.0, s * 0.085, 0.0))
        b = lap_c + Vector((0.0, s * 0.045, 0.0))
        _add(bm, box_between(a, b, w=0.048, h=0.006, mat='M_Caliper', bevel=0.001, up=(1, 0, 0)))
        _add(bm, box_between(lap_c + Vector((-0.20, s * 0.20, -0.03)), lap_c + Vector((0.0, s * 0.045, 0.0)), w=0.048, h=0.006, mat='M_Caliper',
                             bevel=0.001, up=(0, 0, 1)))
    _add(bm, prim_box((0.035, 0.07, 0.012), (lap_c.x, by, lap_c.z + 0.004), mat='M_Chrome', bevel=0.003, segments=1))
    return bm


def surface_decal(surf, center, ray, U, V, w, h, nu=16, nv=12, offset=-0.002, mat='M_Plate', far=6.0):
    """Dense rectangular sheet hugging the skin (number panels, stripes, badges): a nu x nv grid of ray hits on `surf` (centre +
    U*u + V*v), moved `offset` m outwards (offset < 0).  Returns bmesh with outward normals, or None when a ray misses."""
    U, V = Vector(U), Vector(V)
    c = Vector(center)
    bm = bmesh.new()
    rows = []
    for j in range(nv + 1):
        row = []
        for i in range(nu + 1):
            u = (i / float(nu) - 0.5) * w
            v = (j / float(nv) - 0.5) * h
            hit = surf.hit(c + U * u + V * v, ray, far)
            if hit is None:
                bm.free()
                return None
            row.append(bm.verts.new(hit[0] - hit[1] * offset))
        rows.append(row)
    for j in range(nv):
        for i in range(nu):
            bm.faces.new((rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]))
    bm.normal_update()
    c0 = surf.hit(c, ray, far)
    avg = Vector()
    for f in bm.faces:
        avg += f.normal
    if c0 is not None and avg.dot(c0[1]) < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    return _set_mat(bm, mat)


def heal_slivers(bm, max_area=2e-6, passes=3):
    """Delete paper-thin sliver faces (area < max_area) that touch a non-manifold edge (left by booleans that only graze the skin).
    Same idea as carkit.heal_nonmanifold, kept here so the car scripts do not depend on the kit revision.  Returns #faces deleted."""
    total = 0
    for _ in range(passes):
        bad = [e for e in bm.edges if len(e.link_faces) > 2]
        if not bad:
            break
        dead = {f for e in bad for f in e.link_faces if f.calc_area() < max_area}
        if not dead:
            break
        bmesh.ops.delete(bm, geom=list(dead), context='FACES')
        total += len(dead)
        loose_e = [e for e in bm.edges if not e.link_faces]
        if loose_e:
            bmesh.ops.delete(bm, geom=loose_e, context='EDGES')
        loose_v = [v for v in bm.verts if not v.link_edges]
        if loose_v:
            bmesh.ops.delete(bm, geom=loose_v, context='VERTS')
    return total


def heal_mesh(ob, max_area=2e-6):
    """heal_slivers on a finished mesh object (call right after finish_object, before custom normals / UVs)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    n = heal_slivers(bm, max_area)
    if n:
        bm.to_mesh(ob.data)
        ob.data.update()
    bm.free()
    return n
