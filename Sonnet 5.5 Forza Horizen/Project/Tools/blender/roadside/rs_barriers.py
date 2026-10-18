# -*- coding: utf-8 -*-
"""Roadside kit part 1: guard rails (+ handed end pieces), parapet, jersey barrier, bridge rail, delineators, bollards.
Tileable segments: origin at segment start on the centreline, run along +X. Traffic face of rails/barriers = +Y (road is on the
+Y side when driving +X; i.e. the rail sits on the right-hand verge). Posts/blocks are behind the rail on -Y.

Guard-rail run convention (walking +X with the road on +Y):
    rs_guardrail_end_terminal   = START of a run  (free impact head at x=0 flared away from the road, bolts to the next rail at x=4.0)
    rs_guardrail_4m             = body, posts at x=0 and x=2.0 (no post at its far end: that is the first post of the next piece)
    rs_guardrail_end_terminal_R = END of a run (bolts to the previous rail at x=0, free head at x=4.0, mirror-built, brings its own joint post)
    rs_guardrail_curved_end     = END of a run, turned down (like the _R terminal: joins at x=0, anchors at x=4.2)
    rs_guardrail_curved_end_R   = START of a run, turned down (anchor at x=0, joins at x=4.2)
For the opposite verge rotate the whole run 180 deg about Z (never mirror / negative scale)."""

# ----------------------------------------------------------------------------------------------------------------------
# shared helpers
# ----------------------------------------------------------------------------------------------------------------------
def Rz(deg):
    return Matrix.Rotation(radians(deg), 4, 'Z')

def lbox(mb, pos, yaw, lx0, lx1, ly0, ly1, z0, z1, mat, c=0.0, col=None):
    """box in a local frame at pos rotated by yaw(deg) about Z. lx/ly are local offsets, z absolute."""
    cx, cy = (lx0 + lx1) / 2, (ly0 + ly1) / 2
    w = Rz(yaw) @ Vector((cx, cy, 0))
    center = Vector((pos[0] + w.x, pos[1] + w.y, (z0 + z1) / 2))
    mb.obox(center, (lx1 - lx0, ly1 - ly0, z1 - z0), mat, (0, 0, yaw), c, col=col)

def lbox_hull(mb, pos, yaw, lx0, lx1, ly0, ly1, z0, z1):
    """collision hull of an lbox (8 corners of the yawed box)"""
    pts = []
    for lx in (lx0, lx1):
        for ly in (ly0, ly1):
            w = Rz(yaw) @ Vector((lx, ly, 0))
            for z in (z0, z1):
                pts.append(Vector((pos[0] + w.x, pos[1] + w.y, z)))
    mb.hull_pts(pts)

def hexbolt(mb, p, d, r=0.015, ln=0.012, mat='M_RS_GalvDark', wash=0.03, wash_t=0.004):
    """hex head bolt at p pointing along unit vector d (head sticks out), optional round washer."""
    p = v3(p); d = v3(d).normalized()
    if wash:
        mb.cyl(p, p + d * wash_t, wash, wash, mat, seg=10, smooth=True)
        p = p + d * wash_t
    mb.cyl(p, p + d * ln, r, r, mat, seg=6, smooth=False, roll=radians(30))

def _wbeam_profile(t=0.0032, depth=0.083, half=0.155):
    def bump(u):
        if u < 0.10: return 0.0
        if u < 0.50: return 0.5 - 0.5 * cos(pi * (u - 0.10) / 0.40)
        return 0.20 + 0.80 * (0.5 + 0.5 * cos(pi * (u - 0.5) / 0.5))
    us = [0, 0.10, 0.19, 0.30, 0.41, 0.50, 0.61, 0.74, 0.88, 1.0]
    top = [(depth * bump(u) - depth, half * (1 - u)) for u in us]       # a<=0 (peak at 0) , b from +half to 0
    front = top + [(a, -b) for (a, b) in reversed(top[:-1])]
    back = [(a - t, b) for (a, b) in front]
    prof = front + back[::-1]
    L = len(front)
    sm = [True] * (L - 1) + [False] + [True] * (L - 1) + [False]
    return prof, sm, depth

WB_PROF, WB_SM, WB_DEPTH = _wbeam_profile()
GR_ZC = 0.595            # beam centre height: beam spans 0.440 .. 0.750 m (top of rail 0.75 m)
GR_HALF = 0.155
GR_POST_TOP = GR_ZC + 0.205     # 0.80 m

def _gr_post(mb, pos, yaw, zc, ztop=None, zbot=-0.15, depth=WB_DEPTH):
    """galvanised C-channel post + black composite offset block + bolt for a W-beam rail whose back plane passes through pos."""
    ztop = ztop if ztop is not None else zc + 0.205
    yb = -depth                   # beam back plane (local)
    yw = yb - 0.14                # post web front face
    lbox(mb, pos, yaw, -0.05, 0.05, yw, yb, zc - 0.15, zc + 0.15, 'M_RS_PaintBlack')              # offset block
    lbox(mb, pos, yaw, -0.055, 0.055, yw - 0.006, yw, zbot, ztop, 'M_RS_GalvSteel')                # C web
    for sx in (-1, 1):
        lbox(mb, pos, yaw, sx * 0.0495 - 0.0035, sx * 0.0495 + 0.0035, yw - 0.07, yw - 0.006, zbot, ztop, 'M_RS_GalvSteel')   # flanges
    lbox(mb, pos, yaw, -0.058, 0.058, yw - 0.074, yw + 0.001, ztop, ztop + 0.006, 'M_RS_GalvDark')   # cap plate
    z0 = max(zc + 0.157, ztop - 0.05)
    if ztop - z0 > 0.03:           # white retro-reflective tab on the part of the post that shows above the rail
        lbox(mb, pos, yaw, -0.04, 0.04, yw, yw + 0.012, z0, ztop - 0.006, 'M_RS_ReflectorWhite')
    d = Rz(yaw) @ Vector((0, 1, 0))
    d = Vector((d.x, d.y, 0))
    valley_y = -depth * (1 - 0.20)
    h = Rz(yaw) @ Vector((0, valley_y, 0))
    hexbolt(mb, Vector((pos[0] + h.x, pos[1] + h.y, zc)), d, r=0.014, ln=0.012, wash=0.032)         # bolt head in the valley
    n = Rz(yaw) @ Vector((0, yw - 0.074, 0))
    hexbolt(mb, Vector((pos[0] + n.x, pos[1] + n.y, zc)), -d, r=0.013, ln=0.012, wash=0.0)          # nut behind the post

def _beam(mb, path, mat='M_RS_GalvSteel'):
    mb.sweep(WB_PROF, path, mat, True, WB_SM, up=(0, 0, 1), cap0=True, cap1=True, strip_caps=True)

def _splice_bolts(mb, x, yaw=0.0, y=0.0, zc=GR_ZC, depth=WB_DEPTH):
    """4 rail-splice bolts on the flat lips either side of a joint"""
    for dz in (-0.12, 0.12):
        for dx in (-0.045, 0.045):
            d = Rz(yaw) @ Vector((0, 1, 0))
            pp = Rz(yaw) @ Vector((dx, -depth, 0))
            hexbolt(mb, Vector((x + pp.x, y + pp.y, zc + dz)), Vector((d.x, d.y, 0)), r=0.0095, ln=0.008, wash=0.0)

def _beam_hull(mb, path, zc_of=None):
    """convex hull of a beam stretch: section at each path point (path normal in XY), spans back by the beam depth, +-half height"""
    pts = []
    n = len(path)
    for i, p in enumerate(path):
        a = path[max(i - 1, 0)]; b = path[min(i + 1, n - 1)]
        t = Vector((b.x - a.x, b.y - a.y, 0)).normalized()
        nl = Vector((-t.y, t.x, 0))
        for k in (0.0, WB_DEPTH + 0.004):
            for dz in (-GR_HALF, GR_HALF):
                q = p - nl * k
                pts.append(Vector((q.x, q.y, p.z + dz)))
    mb.hull_pts(pts)

def _post_hull(mb, x, y, ztop, w=0.06):
    mb.hull_box((x - w, y - 0.31, -0.15), (x + w, y - WB_DEPTH, ztop + 0.006))

# ----------------------------------------------------------------------------------------------------------------------
# 1a. W-beam guard rail 4.0 m
# ----------------------------------------------------------------------------------------------------------------------
@asset('rs_guardrail_4m', 'Guard rail W-beam segment 4.0 m', x=0.0, ext=(-0.1, 4.1), group='barrier', budget=1500, collision='box',
       pivot='segment_start', tags=['all_biomes', 'road_verge'], scale=(1.0, 1.0),
       usage='Tile every 4.0 m along +X on the verge (traffic face +Y). Start a run with rs_guardrail_end_terminal / rs_guardrail_curved_end_R, end it with rs_guardrail_end_terminal_R / rs_guardrail_curved_end.')
def b_guardrail_4m(mb):
    zc = GR_ZC
    _beam(mb, [Vector((0, 0, zc)), Vector((4.0, 0, zc))])
    for x in (0.0, 2.0):
        _gr_post(mb, (x, 0.0), 0.0, zc)
    _splice_bolts(mb, 0.0)
    _beam_hull(mb, [Vector((0, 0, zc)), Vector((4.0, 0, zc))])
    for x in (0.0, 2.0):
        _post_hull(mb, x, 0.0, GR_POST_TOP)
    return dict(length=4.0, post_spacing=2.0, beam_height_top=zc + GR_HALF, post_top=GR_POST_TOP, traffic_side='+Y',
                run_role='body', next_piece_post_at=4.0)

# ----------------------------------------------------------------------------------------------------------------------
# 1b. end terminal (flared, energy-absorbing head) : free end at x=0, joins a standard rail at x=4.0   (+ mirror-built _R)
# ----------------------------------------------------------------------------------------------------------------------
def _flare(x):
    return -0.32 * (1 - x / 4.0) ** 2

def _flare_slope(x):
    return 0.16 * (1 - x / 4.0)

def _terminal_geometry(mb):
    zc = GR_ZC
    n = 8
    xs = [0.25 + i * (4.0 - 0.25) / n for i in range(n + 1)]
    path = [Vector((x, _flare(x), zc)) for x in xs]
    _beam(mb, path)
    for x in (0.60, 2.0):
        yaw = degrees(atan2(_flare_slope(x), 1.0))
        zt = zc + 0.105 if x < 1 else zc + 0.205
        _gr_post(mb, (x, _flare(x)), yaw, zc, ztop=zt)
    # impact head (extruder): chamfered yellow housing, steel throat behind, stiffener ribs, bolts
    yaw = degrees(atan2(_flare_slope(0.2), 1.0))
    R = Rz(yaw)
    p = (0.0, _flare(0.0))
    z0, z1 = zc - 0.245, zc + 0.245
    lbox(mb, p, yaw, 0.0, 0.40, -0.215, 0.07, z0, z1, 'M_RS_PaintYellow', c=0.03)
    lbox(mb, p, yaw, 0.38, 0.66, -0.19, 0.045, z0 + 0.04, z1 - 0.04, 'M_RS_GalvSteel', c=0.012)
    # stiffener ribs on both flanks of the housing
    for ly in (-0.2155, 0.0705):
        for lx in (0.09, 0.20, 0.31):
            lbox(mb, p, yaw, lx - 0.012, lx + 0.012, ly - (0.006 if ly < 0 else 0.0), ly + (0.0 if ly < 0 else 0.006), z0 + 0.03, z1 - 0.03, 'M_RS_PaintBlack')
    # amber reflector strip along the top of the housing
    lbox(mb, p, yaw, 0.04, 0.36, -0.12, 0.0, z1, z1 + 0.008, 'M_RS_ReflectorAmber')
    # throat bolts
    for lz in (zc - 0.11, zc + 0.11):
        for lx in (0.46, 0.58):
            q = R @ Vector((lx, 0.045, 0))
            hexbolt(mb, Vector((p[0] + q.x, p[1] + q.y, lz)), Vector((R.col[1].x, R.col[1].y, 0)), r=0.012, ln=0.012, wash=0.0)
    # hazard stripes on the front (-X) face of the head: plane normal = -X rotated by yaw
    O = Vector((p[0], p[1], 0)) + R @ Vector((-0.0015, 0.0, 0))
    U = R @ Vector((0, -1, 0)); V = Vector((0, 0, 1))
    pl = Plane(O, U, V)
    u0, u1 = -(0.07 - 0.03), -(-0.215 + 0.03)
    v0, v1 = z0 + 0.03, z1 - 0.03
    k = 0.085
    i = -6
    while i < 12:
        a = u0 + i * k
        stripe = [(a, v0), (a + k * 0.5, v0), (a + k * 0.5 + (v1 - v0) * 0.55, v1), (a + (v1 - v0) * 0.55, v1)]
        cl = clip_rect(stripe, u0, v0, u1, v1)
        if len(cl) >= 3 and abs(poly_area(cl)) > 6e-4:
            mb.prism(pl, cl, 0.0, 0.004, 'M_RS_PaintBlack', 'M_RS_PaintBlack', 'M_RS_PaintBlack')
        i += 2
    mb.hull_box((0.0, _flare(0.0) - 0.22, z0), (0.66, _flare(0.0) + 0.07, z1))
    _beam_hull(mb, path[1:5])
    _beam_hull(mb, path[4:])
    _post_hull(mb, 0.6, _flare(0.6), zc + 0.105 + 0.0, w=0.07)
    _post_hull(mb, 2.0, _flare(2.0), zc + 0.205)

@asset('rs_guardrail_end_terminal', 'Guard rail end terminal START (flared, impact head) 4.0 m', x=10.0, ext=(-0.1, 4.1), group='barrier', budget=1500,
       collision='box', pivot='segment_start', tags=['all_biomes', 'road_verge'], scale=(1.0, 1.0),
       usage='START of a run (walking +X, road on +Y): free impact head at x=0 flared 0.32 m away from the road, bolts onto the first post of a normal rail at x=4.0. For the END of the same run use rs_guardrail_end_terminal_R; for the opposite verge rotate the run 180 deg about Z.')
def b_guardrail_terminal(mb):
    _terminal_geometry(mb)
    return dict(length=4.0, flare=0.32, traffic_side='+Y', run_role='start', joins_next_at_x=4.0)

@asset('rs_guardrail_end_terminal_R', 'Guard rail end terminal END (mirror-built, flared, impact head) 4.0 m', x=356.0, ext=(-0.1, 4.1), group='barrier', budget=1500,
       collision='box', pivot='segment_start', tags=['all_biomes', 'road_verge'], scale=(1.0, 1.0),
       usage='END of a run (walking +X, road on +Y): bolts onto the far end of the previous rail at x=0 (brings its own joint post + splice bolts) and finishes with the flared impact head at x=4.0. Mirror-built (X mirror, winding fixed), no negative scale.')
def b_guardrail_terminal_R(mb):
    _terminal_geometry(mb)
    mirror_x(mb, 4.0)
    _gr_post(mb, (0.0, 0.0), 0.0, GR_ZC)
    _splice_bolts(mb, 0.0)
    _post_hull(mb, 0.0, 0.0, GR_POST_TOP)
    return dict(length=4.0, flare=0.32, traffic_side='+Y', run_role='end', joins_previous_at_x=0.0)

# ----------------------------------------------------------------------------------------------------------------------
# 1c. curved (turned-down) end : normal rail for the first 1.2 m then curves away from the road and dives into the ground
# ----------------------------------------------------------------------------------------------------------------------
def _cend(x):
    s = max(0.0, x - 1.2) / 3.0
    return -1.15 * s * s, GR_ZC - 0.43 * s ** 2.4

def _curved_geometry(mb, joint_post=True, bolts=True):
    ncv = 8
    xs = [0.0, 1.2] + [1.2 + 3.0 * (i + 1) / ncv for i in range(ncv)]
    path = [Vector((x, _cend(x)[0], _cend(x)[1])) for x in xs]
    _beam(mb, path)
    def yaw_at(x):
        a = _cend(x - 0.05); b = _cend(x + 0.05)
        return degrees(atan2(b[0] - a[0], 0.1))
    posts = ([0.0] if joint_post else []) + [2.0, 3.45]
    for x in posts:
        y, z = _cend(x)
        _gr_post(mb, (x, y), yaw_at(x) if x > 0 else 0.0, z, ztop=z + 0.205, zbot=-0.15)
        _post_hull(mb, x, y, z + 0.205, w=0.07)
    # ground anchor: chamfered concrete block with a steel eye and strap plate where the beam bottoms out
    ye, ze = _cend(4.2)
    yaw = yaw_at(4.15)
    lbox(mb, (4.2, ye), yaw, -0.18, 0.32, -0.30, 0.10, 0.0, 0.17, 'M_RS_Concrete', c=0.02)
    lbox(mb, (4.2, ye), yaw, -0.25, 0.0, -0.08, 0.0, 0.05, 0.25, 'M_RS_GalvDark')
    q = Rz(yaw) @ Vector((0.12, -0.10, 0))
    mb.torus((4.2 + q.x, ye + q.y, 0.17 + 0.03), 0.032, 0.008, 'M_RS_GalvDark', nmaj=8, nmin=4, axis='Y', smooth=True)
    if bolts:
        _splice_bolts(mb, 0.0)
    _beam_hull(mb, path[:3])
    _beam_hull(mb, path[2:7])
    _beam_hull(mb, path[6:])
    lbox_hull(mb, (4.2, ye), yaw, -0.25, 0.32, -0.30, 0.10, 0.0, 0.25)

@asset('rs_guardrail_curved_end', 'Guard rail curved turned-down END 4.2 m', x=20.0, ext=(-0.1, 4.4), group='barrier', budget=1500,
       collision='box', pivot='segment_start', tags=['all_biomes', 'road_verge'], scale=(1.0, 1.0),
       usage='END of a run (walking +X, road on +Y): joins the previous rail at x=0 (own joint post + splice bolts), sweeps away from the road (-Y) and ground-anchors at x~4.2. For the START of a run use rs_guardrail_curved_end_R; for the opposite verge rotate 180 deg about Z.')
def b_guardrail_curved(mb):
    _curved_geometry(mb, joint_post=True, bolts=True)
    return dict(length=4.2, lateral_offset=1.15, run_role='end', joins_previous_at_x=0.0)

@asset('rs_guardrail_curved_end_R', 'Guard rail curved turned-down START (mirror-built) 4.2 m', x=364.0, ext=(-0.1, 4.4), group='barrier', budget=1500,
       collision='box', pivot='segment_start', tags=['all_biomes', 'road_verge'], scale=(1.0, 1.0),
       usage='START of a run (walking +X, road on +Y): ground anchor at x=0, rail rises and returns to the run line, joins the next rail (whose own post sits at x=4.2). Mirror-built, no negative scale.')
def b_guardrail_curved_R(mb):
    _curved_geometry(mb, joint_post=False, bolts=False)
    mirror_x(mb, 4.2)
    return dict(length=4.2, lateral_offset=1.15, run_role='start', joins_next_at_x=4.2)
