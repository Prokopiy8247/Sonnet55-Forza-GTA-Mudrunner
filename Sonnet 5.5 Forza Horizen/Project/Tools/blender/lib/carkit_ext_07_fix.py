"""
carkit_ext_07_fix.py - round-2 additions for car07 "Ridge" (art-director fixes).  Load AFTER carkit.py and carkit_ext_05_06_07.py:
    exec(compile(open(KIT, encoding="utf8").read(), KIT, "exec"), globals())
    exec(compile(open(EXT, encoding="utf8").read(), EXT, "exec"), globals())
    exec(compile(open(FIX, encoding="utf8").read(), FIX, "exec"), globals())
Nothing here edits carkit.py or carkit_ext_05_06_07.py (cars 05 / 06 keep using the originals); everything is plain bmesh code.

    build_rally_wing2      double-plane wing: raised blade, flat raked pylons with foot plates, SMALL rounded end plates with an accent inset
    build_roof_scoop2      roof scoop with a rounded hump, a recessed black intake mouth with vanes and a raised lip
    number_panel           recessed door number panel: pocket cutter + white plate + black numeral (7-segment-like strokes)
    build_gravel_tyre2     gravel tyre with seeded random lug jitter (height, width, slant, spacing, skipped lugs)
    build_wheel_gravel2    build_wheel + gravel tyre 2
"""
import math
import random
import bmesh
from mathutils import Vector, Matrix

EXT07_VERSION = "1.0"


# ======================================================================================================================
# rear wing
# ======================================================================================================================
def _scaled_outline(pts, k):
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    return [(cx + (p[0] - cx) * k, cy + (p[1] - cy) * k) for p in pts]


def build_rally_wing2(span=1.40, chord=0.29, flap_chord=0.165, gap=0.082, thick=0.036, plate_h=0.23, pylon_y=0.46,
                      drop_l=0.30, drop_r=None, foot_x=0.02, mat='M_Paint2', mat_plate='M_Paint2', mat_accent='M_Paint'):
    """Double-plane rally wing in its own frame: origin = centre of the main plane (leading edge +X, z up).
    * main plane + upper flap (airfoils, 8 / 24 degrees of pitch), a small black gurney lip on the flap
    * two flat raked pylons (airfoil-shaped struts) from the underside of the main plane down to z = -drop (feet at x = foot_x, i.e. leaning
      forwards at the bottom) with small foot plates - the car script measures the deck height and passes drop_l / drop_r
    * SMALL end plates (plate_h 0.23 m, rounded corners, bevelled, `mat_plate`) with a slightly raised inset in `mat_accent`
    Returns a bmesh."""
    drop_r = drop_l if drop_r is None else drop_r
    bm = bmesh.new()
    c = chord
    main = prim_prism(_airfoil_pts(c, thick), span, plane='XZ', mat=mat)
    bmesh.ops.transform(main, matrix=T(rot=(0, -8, 0)), verts=main.verts)
    _add(bm, main)
    flap = prim_prism(_airfoil_pts(flap_chord, thick * 0.7), span * 0.97, plane='XZ', mat=mat)
    bmesh.ops.transform(flap, matrix=T((-c * 0.28, 0, gap), (0, -24, 0)), verts=flap.verts)
    _add(bm, flap)
    # gurney lip at the trailing edge of the flap
    ca = math.cos(math.radians(24.0))
    sa = math.sin(math.radians(24.0))
    lx = -c * 0.28 - (flap_chord * 0.5) * ca
    lz = gap + (flap_chord * 0.5) * sa
    lip = prim_box((0.006, span * 0.94, 0.020), (lx - 0.001, 0, lz + 0.004), mat='M_TrimBlack', bevel=0.0015, segments=1)
    bmesh.ops.transform(lip, matrix=T(rot=(0, -24, 0)), verts=lip.verts)
    _add(bm, lip)
    # end plates: small, swept, rounded, bevelled; accent inset on the outside
    base = [(c * 0.50, -plate_h * 0.30), (-c * 0.56, -plate_h * 0.30), (-c * 0.70, plate_h * 0.48), (-c * 0.30, plate_h * 0.72),
            (c * 0.36, plate_h * 0.42)]
    outline = outline_rounded_poly(base, r=0.022, n=4)
    inset = outline_rounded_poly(_scaled_outline(base, 0.50), r=0.010, n=3)
    for s in (-1, 1):
        y0 = s * (span / 2 + 0.006)
        plate = prim_prism(outline, 0.010, plane='XZ', center=(0, y0, 0.0), mat=mat_plate)
        try:
            bmesh.ops.bevel(plate, geom=list(plate.edges), offset=0.0022, segments=1, profile=0.5, material=-1, affect='EDGES', clamp_overlap=True)
        except Exception:
            pass
        _add(bm, plate)
        _add(bm, prim_prism(inset, 0.006, plane='XZ', center=(0, y0 + s * 0.0055, 0.0), mat=mat_accent))
    # pylons: flat airfoil-ish struts, raked forward at the foot, with foot plates
    for s, drop in ((1, drop_l), (-1, drop_r)):
        yy = s * pylon_y
        top0, top1 = -0.105, 0.015
        strut = [(foot_x + 0.040, -drop), (foot_x - 0.040, -drop), (top0, 0.004), (top1, 0.004)]
        _add(bm, prim_prism(outline_rounded_poly(strut, r=0.008, n=2), 0.022, plane='XZ', center=(0, yy, 0.0), mat='M_TrimBlack'))
        _add(bm, prim_box((0.150, 0.060, 0.010), (foot_x, yy, -drop + 0.004), mat='M_TrimBlack', bevel=0.003, segments=1))
        for fx in (-0.045, 0.045):
            _add(bm, prim_cylinder(radius=0.0065, depth=0.006, segments=8, axis='Z', center=(foot_x + fx, yy, -drop + 0.012), mat='M_Chrome'))
    return bm


# ======================================================================================================================
# roof scoop with a real duct
# ======================================================================================================================
def build_roof_scoop2(surf, x0, x1, half_w, h, n_x=12, n_y=14, mat='M_Paint2', sink=0.010):
    """Forward-facing roof air scoop (front = +X at x1).  Rounded hump that fades into the roof towards x0; the front face carries a
    raised body-colour lip, a recessed black intake mouth and two chrome vanes, so it reads as an open duct.  Returns bmesh or None."""
    rings = []
    zc_front = None
    for k in range(n_x + 1):
        t = k / float(n_x)
        x = x1 + (x0 - x1) * t
        hh = h * (1.0 - t) ** 1.25 if t < 1.0 else 0.0
        ww = half_w * (1.0 - 0.34 * t)
        top, bot = [], []
        for j in range(n_y + 1):
            u = -1.0 + 2.0 * j / n_y
            y = u * ww
            hit = surf.hit(Vector((x, y, 0.0)), (0, 0, -1))
            if hit is None:
                return None
            z = hit[0].z
            # rounded shoulders: superellipse-ish cross section
            top.append(Vector((x, y, z - sink + hh * (max(1.0 - abs(u) ** 2.4, 0.0)) ** 0.55)))
            bot.append(Vector((x, y, z - sink * 1.5)))
        if k == 0:
            hit0 = surf.hit(Vector((x, 0.0, 0.0)), (0, 0, -1))
            zc_front = hit0[0].z
        rings.append(top + list(reversed(bot[1:-1])))
    bm = ring_loft(rings, closed=True, caps=True, mat=mat)
    bm.faces.ensure_lookup_table()
    fc = max(bm.faces, key=lambda f: f.calc_center_median().x if len(f.verts) > 4 else -1e9)
    fc.material_index = mi(mat)
    # intake: lip frame (paint), black mouth plate, chrome vanes
    mw, mh = half_w * 2 * 0.74, h * 0.64
    zc = zc_front - sink + h * 0.40
    out_l = outline_rrect(mw + 0.022, mh + 0.018, 0.016, 4)
    mouth = outline_rrect(mw, mh, 0.012, 4)
    _add(bm, prim_prism(out_l, 0.020, plane='YZ', center=(x1 + 0.002, 0.0, zc), mat=mat))
    _add(bm, prim_prism(mouth, 0.014, plane='YZ', center=(x1 + 0.0125, 0.0, zc), mat='M_TrimBlack'))
    for k in range(2):
        vz = zc + (k - 0.5) * mh * 0.46
        _add(bm, prim_box((0.010, mw * 0.90, 0.0042), (x1 + 0.0200, 0.0, vz), mat='M_Chrome', bevel=0.0008, segments=1))
    _add(bm, prim_box((0.010, 0.004, mh * 0.88), (x1 + 0.0200, 0.0, zc), mat='M_TrimGrey', bevel=0.0008, segments=1))
    return bm


# ======================================================================================================================
# recessed door number panel
# ======================================================================================================================
def _patch_poly(surf, c0, U, V, poly, ray, offset, mat, rings=2, step=0.012):
    """surface_patch of a convex polygon given in (u, v) panel coordinates around the point c0 (the polygon is re-centred on its
    own centroid and densified)."""
    cu = sum(p[0] for p in poly) / len(poly)
    cv = sum(p[1] for p in poly) / len(poly)
    rel = [(p[0] - cu, p[1] - cv) for p in poly]
    rel = densify_outline(rel, step)
    cen = Vector(c0) + Vector(U) * cu + Vector(V) * cv
    return surface_patch(surf, rel, cen, ray, offset=offset, rings=rings, mat=mat, axes=(Vector(U), Vector(V)))


_DIGITS = {   # strokes of the numeral in reading coordinates (r right, v up), glyph box 0.10 x 0.15 around (0, 0)
    '7': [[(-0.05, 0.049), (0.05, 0.049), (0.05, 0.075), (-0.05, 0.075)],
          [(0.050, 0.049), (0.020, 0.049), (-0.030, -0.075), (0.000, -0.075)]],
    '1': [[(-0.012, -0.075), (0.016, -0.075), (0.016, 0.075), (-0.004, 0.075)],
          [(-0.040, 0.030), (-0.040, 0.054), (-0.004, 0.075), (-0.004, 0.050)]],
}


def number_panel(surf, center, ray, U_read, V, w=0.36, h=0.27, digit='7', recess=0.006, plate_inset=0.0035, glyph_inset=0.0027, corner=0.03):
    """Recessed rally number panel on a flank.  center = a point outside the skin on the ray line, ray = direction towards the body,
    U_read = world direction that reads as "to the right" for a viewer looking at the panel, V = up.
    Returns (cutter, [inserts]): subtract the cutter in the body boolean (black pocket, `recess` m deep), append the inserts afterwards
    (white plate `plate_inset` m below the skin, black numeral on top).  None / [] when a ray misses."""
    U, V = Vector(U_read), Vector(V)
    cut = pocket_cutter(surf, outline_rrect(w, h, corner, 5), Vector(center), ray, depth=recess, lift=0.03, taper=1.0, mat='M_TrimBlack',
                        axes=(U, V), floor_follows=True)
    if cut is None:
        return None, []
    ins = []
    plate = _patch_poly(surf, center, U, V, outline_rrect(w - 0.026, h - 0.026, corner * 0.55, 5), ray, plate_inset, 'M_Plate', rings=4, step=0.02)
    if plate is not None:
        ins.append(plate)
    for stroke in _DIGITS.get(digit, []):
        g = _patch_poly(surf, center, U, V, stroke, ray, glyph_inset, 'M_TrimBlack', rings=2, step=0.012)
        if g is not None:
            ins.append(g)
    return cut, ins


# ======================================================================================================================
# gravel tyre with irregular lugs
# ======================================================================================================================
def build_gravel_tyre2(R=0.33, w=0.215, rb=0.1905, segs=64, lug_h=0.024, n_lug=26, mat='M_Tyre', vary=1.0, seed=7):
    """Like build_gravel_tyre (carkit_ext_05_06_07) but every lug gets seeded random jitter: angle, half width, slant, top radius
    (<= R) and a few inner-row lugs are skipped; lug count per side alternates 26 / 25 so the pattern never lines up across the tread."""
    rng = random.Random(seed)
    w2 = w / 2.0
    base = R - lug_h * 0.9
    H = base - rb
    # monotone sidewall profile (round 1 used absolute offsets that folded the sidewall back on itself by 3 cm on this small tyre)
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
    tread_r = base
    for side in (1, -1):
        nl = n_lug if side == 1 else n_lug - 1
        step = 2.0 * math.pi / nl
        for k in range(nl):
            for ri, (yc, ww, ph, sk) in enumerate(((0.030, 0.050, 0.0, 0.020), (0.087, 0.042, 0.5, 0.030))):
                if vary > 0 and ri == 1 and rng.random() < 0.12 * vary:
                    continue
                a0 = (k + ph) * step + (rng.random() - 0.5) * step * 0.16 * vary
                hl = step * 0.27 * (1.0 + (rng.random() - 0.5) * 0.36 * vary)
                wv = ww * (1.0 + (rng.random() - 0.5) * 0.30 * vary)
                skv = sk * (1.0 + (rng.random() - 0.5) * 0.7 * vary)
                top = R - rng.random() * 0.0032 * vary
                y0, y1 = side * (yc - wv / 2), side * (yc + wv / 2)
                if side < 0:
                    y0, y1 = y1, y0
                pol = [(tread_r - 0.003, y0), (tread_r - 0.003, y1), (top, y1 - side * 0.004), (top, y0 + side * 0.004)]
                if side < 0:
                    pol = list(reversed(pol))
                _sector_prism(bm, pol, a0 - hl, a0 + hl, a0 - hl + skv * side, a0 + hl + skv * side)
            # shoulder lug
            if vary > 0 and rng.random() < 0.06 * vary:
                continue
            a0 = (k + 0.25) * step + (rng.random() - 0.5) * step * 0.14 * vary
            hl = step * 0.24 * (1.0 + (rng.random() - 0.5) * 0.30 * vary)
            hh = 0.016 * (1.0 - rng.random() * 0.35 * vary)           # never taller than the plain lug: tyre radius stays <= R
            curve = [(rb + 0.80 * H, 0.975 * w2), (rb + 0.91 * H, 0.915 * w2), (rb + 0.97 * H, 0.84 * w2), (base, 0.76 * w2)]
            outer = [(r + hh, y) for (r, y) in curve]
            inner = [(r - 0.002, y) for (r, y) in curve]
            pol = [(p[0], p[1] * side) for p in inner] + [(p[0], p[1] * side) for p in reversed(outer)]
            if side < 0:
                pol = list(reversed(pol))
            _sector_prism(bm, pol, a0 - hl, a0 + hl)
    recalc(bm)
    return bm


def build_wheel_gravel2(radius=0.33, width=0.215, rim_radius=0.2032, style='star', spokes=6, side=+1, segments=48, seed=7, vary=1.0, **kw):
    """build_wheel with the stock tyre replaced by the jittered gravel tyre (the rim part comes from the kit)."""
    kw.setdefault('tread', False)
    bm = build_wheel(radius=radius, width=width, rim_radius=rim_radius, style=style, spokes=spokes, side=+1, segments=segments, **kw)
    tyre = build_gravel_tyre2(R=radius, w=width, rb=rim_radius - 0.0127, segs=segments + 16, vary=vary, seed=seed)
    swap_tyre(bm, tyre)
    if side < 0:
        m = mirrored_copy(bm)
        bm.free()
        bm = m
    return bm
