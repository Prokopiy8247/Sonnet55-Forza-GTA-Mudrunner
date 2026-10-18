# -*- coding: utf-8 -*-
"""
Settlements kit - library layer.  exec'd into a PRIVATE namespace by settlements_kit.py (never import directly).

Re-uses the verified roadside harness (MB mesh builder, idempotent build/validate/export) by exec'ing a patched copy of
Tools/blender/roadside/rs_lib.py: staging y=100, Exports/Settlements, collection FORZA_UE/Settlements, M_Bld_* materials.
Adds the building toolkit: wall runs with real window/door openings, roofs with tile courses, chimneys, quoins ...
Conventions (Docs/BLENDER_CONTRACT.md): 1 BU = 1 m, Z up, +X = front (door side), origin = ground centre of the footprint.
"""
import os
_HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else \
    r"W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza\Tools\blender\settlements"
_RS = os.path.join(os.path.dirname(_HERE), 'roadside')

def _patched(path, reps):
    src = open(path, encoding='utf8').read()
    for a, b in reps:
        if a not in src:
            raise RuntimeError('patch anchor missing: ' + a)
        src = src.replace(a, b)
    return src

_reps = [
    ("STAGE_Y = 80.0", "STAGE_Y = 100.0"),
    ("Exports\\Roadside", "Exports\\Settlements"),
    ("m.name.startswith('M_RS_')", "m.name.startswith('M_Bld_')"),
    ("'Roadside'", "'Settlements'"),
    ("return Vector((REG[aid]['x'], STAGE_Y, 0.0))", "return Vector((REG[aid]['x'], STAGE_Y, REG[aid].get('z', 0.0)))"),
    ("usage='', nanite=True):", "usage='', nanite=True, z=0.0):"),
    ("usage=usage, nanite=nanite)", "usage=usage, nanite=nanite, z=z)"),
    ("kit='roadside'", "kit='settlements'"),
    ("staging='y=80'", "staging='y=100'"),
]
_p = os.path.join(_RS, 'rs_lib.py')
exec(compile(_patched(_p, _reps), _p, 'exec'), globals())
_pf = os.path.join(_RS, 'rs_font.py')
exec(compile(open(_pf, encoding='utf8').read(), _pf, 'exec'), globals())

# ----------------------------------------------------------------------------------------------------------------------
# materials  (UE master-material instances by NAME; <= 6 per asset)
# ----------------------------------------------------------------------------------------------------------------------
MATS.clear()
MATS.update({
    'M_Bld_Plaster':    dict(c='#ece3cf', m=0.0, r=0.92, tint=True),
    'M_Bld_RoofTile':   dict(c='#b4573b', m=0.0, r=0.78, tint=True),
    'M_Bld_Wood':       dict(c='#7b5535', m=0.0, r=0.80, tint=True),
    'M_Bld_Stone':      dict(c='#9b9587', m=0.0, r=0.95, tint=True),
    'M_Bld_Metal':      dict(c='#aab0b6', m=0.8, r=0.45),
    'M_Bld_Window':     dict(c='#2b3d4d', m=0.0, r=0.06, e=('#ffd9a0', 0.0)),
    'M_Bld_Brick':      dict(c='#a95e47', m=0.0, r=0.90, tint=True),
    'M_Bld_PaintRed':   dict(c='#a8281f', m=0.0, r=0.55, tint=True),
    'M_Bld_PaintWhite': dict(c='#ebe9e2', m=0.0, r=0.55, tint=True),
    'M_Bld_PaintBlue':  dict(c='#2b5d8c', m=0.0, r=0.55, tint=True),
    'M_Bld_Neon':       dict(c='#ff5a7a', m=0.0, r=0.2, e=('#ff4f78', 4.0)),
    'M_Bld_Rubber':     dict(c='#18181a', m=0.0, r=0.88),
})

PAL = dict(cream=(1, 1, 1, 1), ochre=(1.0, 0.86, 0.62, 1), pink=(1.0, 0.80, 0.74, 1), blue=(0.80, 0.88, 1.0, 1),
           sage=(0.82, 0.92, 0.80, 1), grey=(0.78, 0.78, 0.78, 1), dark=(0.55, 0.50, 0.46, 1), red=(1, 1, 1, 1))
_Z = Vector((0, 0, 1))

def gcol(col, amt=0.0):
    return col

# ----------------------------------------------------------------------------------------------------------------------
# wall frame + wall runs
# ----------------------------------------------------------------------------------------------------------------------
class WF:
    """Wall frame: origin A, along-wall d, outward normal n (right of d for CCW footprints), up = +Z.
    p(u, v, w): u along the wall, v = absolute height, w = outward distance from the outer face (negative = into the wall)."""
    def __init__(s, A, B):
        s.A = Vector((A[0], A[1], 0.0)); B = Vector((B[0], B[1], 0.0))
        dd = B - s.A
        s.L = dd.length
        s.d = dd.normalized()
        s.n = Vector((s.d.y, -s.d.x, 0.0))
        s.R = Matrix(((s.d.x, s.n.x, 0), (s.d.y, s.n.y, 0), (0, 0, 1)))

    def p(s, u, v, w=0.0):
        return s.A + s.d * u + s.n * w + Vector((0, 0, v))

    def box(s, mb, u0, u1, v0, v1, w0, w1, mat, c=0.0, col=None):
        mb.obox(s.p((u0 + u1) / 2, (v0 + v1) / 2, (w0 + w1) / 2), (u1 - u0, w1 - w0, v1 - v0), mat, s.R, c, col=col)

    def plane(s, w=0.0):
        """prism plane: U = along wall, V = up, N = outward"""
        return Plane(s.p(0, 0, w), s.d, _Z)


def wall_run(mb, wf, z0, z1, t, openings, mat, ua=0.0, ub=None, col=None, matin=None):
    """Closed wall slab (outer face on the wall frame line, thickness t inward) with REAL rectangular openings
    (u0,u1,v0,v1) incl. reveals. ua..ub = used range of the wall (to trim at corners)."""
    ub = wf.L if ub is None else ub
    us = {ua, ub}; vs = {z0, z1}
    ops = []
    for (u0, u1, v0, v1) in openings:
        if u1 <= ua + 1e-6 or u0 >= ub - 1e-6:
            continue
        u0 = max(u0, ua); u1 = min(u1, ub)
        ops.append((u0, u1, max(v0, z0), min(v1, z1)))
        us.update((u0, u1)); vs.update((max(v0, z0), min(v1, z1)))
    U = sorted(us); V = sorted(vs)
    nu = len(U) - 1; nv = len(V) - 1
    solid = [[True] * nv for _ in range(nu)]
    for i in range(nu):
        uc = (U[i] + U[i + 1]) / 2
        for j in range(nv):
            vc = (V[j] + V[j + 1]) / 2
            for (u0, u1, v0, v1) in ops:
                if u0 < uc < u1 and v0 < vc < v1:
                    solid[i][j] = False
                    break
    OVc = {}; IVc = {}
    def ov(i, j):
        k = (i, j)
        if k not in OVc: OVc[k] = mb.vert(wf.p(U[i], V[j], 0.0))
        return OVc[k]
    def iv(i, j):
        k = (i, j)
        if k not in IVc: IVc[k] = mb.vert(wf.p(U[i], V[j], -t))
        return IVc[k]
    def S(i, j):
        return 0 <= i < nu and 0 <= j < nv and solid[i][j]
    mi = matin or mat
    for i in range(nu):
        for j in range(nv):
            if not solid[i][j]:
                continue
            mb.face([ov(i, j), ov(i + 1, j), ov(i + 1, j + 1), ov(i, j + 1)], mat, col=col)
            mb.face([iv(i, j), iv(i, j + 1), iv(i + 1, j + 1), iv(i + 1, j)], mi, col=col)
            if not S(i - 1, j): mb.face([ov(i, j), ov(i, j + 1), iv(i, j + 1), iv(i, j)], mat, col=col)
            if not S(i + 1, j): mb.face([ov(i + 1, j), iv(i + 1, j), iv(i + 1, j + 1), ov(i + 1, j + 1)], mat, col=col)
            if not S(i, j - 1): mb.face([ov(i, j), iv(i, j), iv(i + 1, j), ov(i + 1, j)], mat, col=col)
            if not S(i, j + 1): mb.face([ov(i, j + 1), ov(i + 1, j + 1), iv(i + 1, j + 1), iv(i, j + 1)], mat, col=col)


def footprint_frames(poly):
    """CCW polygon -> list of WF per edge + convex flags per corner (corner i = start of edge i)."""
    poly = [tuple(p) for p in poly]
    n = len(poly)
    wfs = [WF(poly[i], poly[(i + 1) % n]) for i in range(n)]
    convex = []
    for i in range(n):
        d0 = wfs[i - 1].d; d1 = wfs[i].d
        convex.append((d0.x * d1.y - d0.y * d1.x) > 0)
    return wfs, convex


def house_walls(mb, poly, z0, z1, t, openings, mat, col=None, matin=None):
    """Walls around a CCW footprint polygon. Edge i owns its END corner when convex; edge i+1 is trimmed by t there.
    openings: dict edge_index -> list of (u0,u1,v0,v1)."""
    wfs, convex = footprint_frames(poly)
    n = len(wfs)
    for i, wf in enumerate(wfs):
        ua = t if convex[i] else 0.0
        ub = wf.L
        wall_run(mb, wf, z0, z1, t, openings.get(i, []), mat, ua=ua, ub=ub, col=col, matin=matin)
    return wfs, convex


# ----------------------------------------------------------------------------------------------------------------------
# openings: windows / doors / details
# ----------------------------------------------------------------------------------------------------------------------
def window_unit(mb, wf, u0, u1, v0, v1, t, frame='M_Bld_Wood', shutters=None, sill=True, lintel='M_Bld_Stone', panes=(2, 2), box=None):
    W = u1 - u0
    gw = -t * 0.55
    wf.box(mb, u0 + 0.02, u1 - 0.02, v0 + 0.02, v1 - 0.02, gw, gw + 0.03, 'M_Bld_Window')
    fw = 0.06
    f0, f1 = gw - 0.05, gw + 0.07
    wf.box(mb, u0, u0 + fw, v0, v1, f0, f1, frame)
    wf.box(mb, u1 - fw, u1, v0, v1, f0, f1, frame)
    wf.box(mb, u0 + fw, u1 - fw, v1 - fw, v1, f0, f1, frame)
    wf.box(mb, u0 + fw, u1 - fw, v0, v0 + fw, f0, f1, frame)
    for k in range(1, panes[0]):
        uc = u0 + W * k / panes[0]
        wf.box(mb, uc - 0.022, uc + 0.022, v0 + fw, v1 - fw, f0 + 0.02, f1 - 0.02, frame)
    for k in range(1, panes[1]):
        vc = v0 + (v1 - v0) * k / panes[1]
        wf.box(mb, u0 + fw, u1 - fw, vc - 0.022, vc + 0.022, f0 + 0.02, f1 - 0.02, frame)
    if sill:
        wf.box(mb, u0 - 0.09, u1 + 0.09, v0 - 0.07, v0 + 0.02, -0.03, 0.13, 'M_Bld_Stone', c=0.012)
    if lintel:
        wf.box(mb, u0 - 0.09, u1 + 0.09, v1, v1 + 0.15, -0.02, 0.07, lintel, c=0.01)
    if box:   # flower box
        wf.box(mb, u0 - 0.02, u1 + 0.02, v0 - 0.32, v0 - 0.08, 0.0, 0.26, 'M_Bld_Wood', c=0.01)
        wf.box(mb, u0 + 0.04, u1 - 0.04, v0 - 0.1, v0 + 0.02, 0.03, 0.22, box)
    if shutters:
        sw = W / 2 - 0.015
        H = v1 - v0 + 0.12
        for side in (-1, 1):
            if side < 0:
                a0, a1 = u0 - 0.045 - sw, u0 - 0.045
            else:
                a0, a1 = u1 + 0.045, u1 + 0.045 + sw
            wf.box(mb, a0, a1, v0 - 0.06, v0 - 0.06 + H, 0.0, 0.045, shutters)
            n = 5
            for k in range(n):
                vv = v0 - 0.06 + 0.12 + (H - 0.24) * (k + 0.5) / n
                wf.box(mb, a0 + 0.05, a1 - 0.05, vv - 0.025, vv + 0.025, 0.04, 0.075, shutters)


def door_unit(mb, wf, u0, u1, v0, v1, t, leaf='M_Bld_Wood', frame='M_Bld_Stone', steps=True, knob=True):
    W = u1 - u0
    lw = -t * 0.45
    wf.box(mb, u0 + 0.03, u1 - 0.03, v0, v1 - 0.03, lw, lw + 0.06, leaf)
    for (a0, a1) in ((u0 + 0.14, u0 + W / 2 - 0.05), (u0 + W / 2 + 0.05, u1 - 0.14)):
        wf.box(mb, a0, a1, v0 + 0.15, v0 + 0.95, lw + 0.06, lw + 0.095, leaf, c=0.008)
        wf.box(mb, a0, a1, v0 + 1.08, v1 - 0.18, lw + 0.06, lw + 0.095, leaf, c=0.008)
    if knob:
        wf.box(mb, u1 - 0.22, u1 - 0.14, v0 + 0.98, v0 + 1.06, lw + 0.06, lw + 0.14, 'M_Bld_Metal')
    wf.box(mb, u0 - 0.12, u0, v0, v1 + 0.12, -0.04, 0.12, frame, c=0.01)
    wf.box(mb, u1, u1 + 0.12, v0, v1 + 0.12, -0.04, 0.12, frame, c=0.01)
    wf.box(mb, u0 - 0.16, u1 + 0.16, v1, v1 + 0.2, -0.04, 0.14, frame, c=0.012)
    if steps:
        wf.box(mb, u0 - 0.25, u1 + 0.25, 0.0, v0 - 0.18, 0.0, 0.75, 'M_Bld_Stone', c=0.012)
        wf.box(mb, u0 - 0.05, u1 + 0.05, 0.0, v0 - 0.02, 0.0, 0.42, 'M_Bld_Stone', c=0.012)
        if v0 - 0.18 < 0.1:
            pass


def plinth(mb, poly, h, proud=0.05, mat='M_Bld_Stone'):
    pl = Plane((0, 0, 0), (1, 0, 0), (0, 1, 0))
    mb.prism(pl, offset_poly(poly, proud), 0.0, h, mat)


def quoins(mb, wfs, convex, z0, z1, mat='M_Bld_Stone'):
    n = len(wfs)
    for i in range(n):
        if not convex[(i + 1) % n]:
            pass
    for i, wf in enumerate(wfs):
        # END corner of edge i  (corner index i+1)
        if convex[(i + 1) % n]:
            z = z0; k = 0
            while z < z1 - 0.05:
                h = min(0.36, z1 - z)
                bw = 0.55 if k % 2 == 0 else 0.34
                wf.box(mb, wf.L - bw, wf.L, z + 0.01, z + h - 0.01, 0.0, 0.045, mat, c=0.01)
                z += h; k += 1
        # START corner of edge i (corner index i)
        if convex[i]:
            z = z0; k = 0
            while z < z1 - 0.05:
                h = min(0.36, z1 - z)
                bw = 0.34 if k % 2 == 0 else 0.55
                wf.box(mb, -0.045, bw, z + 0.01, z + h - 0.01, 0.0, 0.045, mat, c=0.01)
                z += h; k += 1


def band(mb, poly, z, h, proud=0.05, mat='M_Bld_Stone'):
    pl = Plane((0, 0, 0), (1, 0, 0), (0, 1, 0))
    outer = offset_poly(poly, proud)
    inner = offset_poly(poly, -0.12)
    mb.ring_prism(pl, outer, inner, z, z + h, mat)


def chimney(mb, cx, cy, zb, zt, w=0.8, d=0.95, mat='M_Bld_Stone', cap=True, rot=0.0):
    mb.obox((cx, cy, (zb + zt) / 2), (w, d, zt - zb), mat, (0, 0, rot), c=0.01)
    if cap:
        mb.obox((cx, cy, zt + 0.06), (w + 0.2, d + 0.2, 0.12), mat, (0, 0, rot), c=0.015)
        mb.obox((cx, cy, zt + 0.17), (w - 0.18, d - 0.18, 0.1), 'M_Bld_Metal', (0, 0, rot))
        mb.obox((cx, cy, zt - 0.32), (w + 0.12, d + 0.12, 0.1), mat, (0, 0, rot), c=0.012)


def downpipe(mb, x, y, z0, z1, r=0.045, mat='M_Bld_Metal'):
    mb.cyl((x, y, z0), (x, y, z1), r, r, mat, seg=8, cap0=True, cap1=True)


# ----------------------------------------------------------------------------------------------------------------------
# roofs
# ----------------------------------------------------------------------------------------------------------------------
def roof_slope(mb, P0, P1, W, length, mat, matcap=None, course=0.30, nose=0.055, thick=0.05, seg=1.2, col=None, amt=0.12):
    """One roof plane with stepped tile courses. P0 = eave edge point, P1 = point at the ridge/upper edge (same ridge-direction
    coordinate), W = direction along the ridge/eave, length = extent along W starting at P0."""
    P0 = Vector(P0); P1 = Vector(P1); W = Vector(W).normalized()
    U = (P1 - P0); sl = U.length; U.normalize()
    V = W.cross(U)
    if V.z < 0: V = -V
    nc = max(2, int(round(sl / course))); lc = sl / nc
    prof = [(0.0, -thick)]
    for i in range(nc):
        # tiny deterministic jitter so nose/tail points are never exactly collinear (avoids zero-area triangles in the end-cap triangulation)
        prof.append((i * lc, nose + 0.003 * (((i * i * 5 + i * 3) % 17) / 17.0))); prof.append(((i + 1) * lc, 0.004 * (((i * i * 7 + i * 5 + 1) % 19) / 19.0)))
    prof.append((sl, -thick))
    nseg = max(1, int(round(length / seg)))
    rings = []
    for k in range(nseg + 1):
        w = length * k / nseg
        rings.append([P0 + U * u + V * v + W * w for (u, v) in prof])
    start = len(mb.bm.faces)
    mb.loft(rings, mat, True, False, cap0=True, cap1=True, matcap=matcap or mat, cap_tri=True, col=col)
    mb.speckle([mat], amt, start=start)


def ridge_cap(mb, R0, R1, across, tanp, mat, half=0.30, h=0.10):
    """Ridge cap prism along R0->R1; `across` = horizontal unit vector perpendicular to the ridge."""
    R0 = Vector(R0); R1 = Vector(R1); a = Vector(across).normalized()
    ring = [R0 + a * (-half) + Vector((0, 0, -half * tanp - 0.03)), R0 + Vector((0, 0, h)), R0 + a * half + Vector((0, 0, -half * tanp - 0.03))]
    ring2 = [p + (R1 - R0) for p in ring]
    mb.loft([ring, ring2], mat, True, False, cap0=True, cap1=True)


def gable_wing(mb, x0, x1, y0, y1, eave_z, pitch, axis, mat='M_Bld_RoofTile', trim='M_Bld_Wood', ov_e=0.55, ov_g0=0.3, ov_g1=0.3,
               col=None, ridge_mat=None, course=0.30):
    """Gable roof over a rectangle. axis='y': ridge runs along Y (eaves on +-X); axis='x': ridge along X (eaves on +-Y).
    Returns (ridge_z, (ridge p0, ridge p1))."""
    tn = tan(radians(pitch))
    if axis == 'y':
        half = (x1 - x0) / 2; xm = (x0 + x1) / 2
        ya, yb = y0 - ov_g0, y1 + ov_g1
        rz = eave_z + half * tn
        for sgn, xe in ((1, x1 + ov_e), (-1, x0 - ov_e)):
            roof_slope(mb, (xe, ya, eave_z - ov_e * tn), (xm, ya, rz), (0, 1, 0), yb - ya, mat, trim, col=col, course=course)
        ridge_cap(mb, (xm, ya, rz), (xm, yb, rz), (1, 0, 0), tn, ridge_mat or mat)
        return rz, ((xm, ya, rz), (xm, yb, rz))
    else:
        half = (y1 - y0) / 2; ym = (y0 + y1) / 2
        xa, xb = x0 - ov_g0, x1 + ov_g1
        rz = eave_z + half * tn
        for sgn, ye in ((1, y1 + ov_e), (-1, y0 - ov_e)):
            roof_slope(mb, (xa, ye, eave_z - ov_e * tn), (xa, ym, rz), (1, 0, 0), xb - xa, mat, trim, col=col, course=course)
        ridge_cap(mb, (xa, ym, rz), (xb, ym, rz), (0, 1, 0), tn, ridge_mat or mat)
        return rz, ((xa, ym, rz), (xb, ym, rz))


def gable_fill(mb, wf, ua, ub, z_eave, rise, t, mat, col=None):
    """Triangular gable wall slab on a wall frame between u=ua..ub (thickness t inward)."""
    pl = Plane(wf.p(0, 0, -t), wf.d, _Z)
    mb.prism(pl, [(ua, z_eave), (ub, z_eave), ((ua + ub) / 2, z_eave + rise)], 0.0, t, mat, col=col)


def gable_window(mb, wf, uc, vc, w, h, frame='M_Bld_Wood'):
    """Applied attic window (frame + glass) on a gable face."""
    wf.box(mb, uc - w / 2, uc + w / 2, vc - h / 2, vc + h / 2, 0.0, 0.05, 'M_Bld_Window')
    fw = 0.06
    wf.box(mb, uc - w / 2 - fw, uc - w / 2, vc - h / 2 - fw, vc + h / 2 + fw, 0.0, 0.09, frame)
    wf.box(mb, uc + w / 2, uc + w / 2 + fw, vc - h / 2 - fw, vc + h / 2 + fw, 0.0, 0.09, frame)
    wf.box(mb, uc - w / 2, uc + w / 2, vc + h / 2, vc + h / 2 + fw, 0.0, 0.09, frame)
    wf.box(mb, uc - w / 2, uc + w / 2, vc - h / 2 - fw, vc - h / 2, 0.0, 0.11, 'M_Bld_Stone')
    wf.box(mb, uc - 0.02, uc + 0.02, vc - h / 2, vc + h / 2, 0.04, 0.085, frame)


def gutter(mb, p0, p1, mat='M_Bld_Metal'):
    p0 = Vector(p0); p1 = Vector(p1)
    mb.bar(p0, p1, 0.1, 0.09, mat)


# ----------------------------------------------------------------------------------------------------------------------
# generic helpers for round things / rotated boxes
# ----------------------------------------------------------------------------------------------------------------------
def ring_poly(r, n, start=0.0):
    return [(r * cos(start + 2 * pi * i / n), r * sin(start + 2 * pi * i / n)) for i in range(n)]

def rbox(mb, M, center, size, mat, rotM=None, c=0.0):
    """box whose centre/orientation are transformed by the 4x4 matrix M (used for blades, rotated parts)."""
    cc = M @ Vector(center)
    R = M.to_3x3()
    if rotM is not None:
        R = R @ rotM
    mb.obox(cc, size, mat, R.to_4x4(), c)

def asset_ready(aid):
    return aid in REG

def shift_all(mb, dx=0.0, dy=0.0, dz=0.0):
    """translate everything built so far (verts + collision hulls + sockets) - used to centre the footprint on the origin"""
    d = Vector((dx, dy, dz))
    for v in mb.bm.verts:
        v.co += d
    mb.hulls = [[Vector(p) + d for p in h] for h in mb.hulls]
    mb.sockets = {k: (p[0] + dx, p[1] + dy, p[2] + dz) for k, p in mb.sockets.items()}
