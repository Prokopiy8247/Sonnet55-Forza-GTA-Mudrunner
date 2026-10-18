# -*- coding: utf-8 -*-
"""Roadside kit part 3: road signs (flat modelled panels with raised borders + geometric pictograms, original symbols).
All signs: face towards +X (panel back plane at x=0.05, post axis on the origin), screen-right = +Y, up = +Z."""

T_PLATE = 0.016      # plate thickness
T_BAND = 0.0012      # border/band decal height above the plate (single-sided cards)
T_ICON = 0.0012      # pictogram decal height above the band level
XBACK = 0.05

# ----------------------------------------------------------------------------------------------------------------------
# outlines  (all CCW, identical point count for any inset -> ring_prism friendly)
# ----------------------------------------------------------------------------------------------------------------------
def sh_poly(kind, p, inset=0.0):
    rc = p.get('rc', 0.03)
    if kind == 'circle':
        r = p['r'] - inset
        return ellipse_pts(0, 0, r, r, 40)
    if kind == 'tri_up':
        s = p['side']; h = s * sqrt(3) / 2
        corners = [(-s / 2, -h / 3), (s / 2, -h / 3), (0, 2 * h / 3)]
    elif kind == 'tri_down':
        s = p['side']; h = s * sqrt(3) / 2
        corners = [(-s / 2, h / 3), (s / 2, h / 3), (0, -2 * h / 3)]
    elif kind == 'diamond':
        d = p['diag'] / 2
        corners = [(0, -d), (d, 0), (0, d), (-d, 0)]
    elif kind == 'oct':
        R = p['across'] / 2 / cos(radians(22.5))
        corners = [(R * cos(radians(22.5 + 45 * i)), R * sin(radians(22.5 + 45 * i))) for i in range(8)]
    elif kind == 'rect':
        w, h = p['w'] / 2, p['h'] / 2
        corners = [(-w, -h), (w, -h), (w, h), (-w, h)]
    else:
        raise ValueError(kind)
    if inset != 0:
        corners = offset_poly(corners, -inset)
    return rounded_poly(corners, max(rc - inset, 0.006), 4)

def rectpoly(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]

def arrow_poly(p0, p1, w, hw, hl):
    p0 = Vector(p0); p1 = Vector(p1)
    d = (p1 - p0).normalized(); n = perp2(d); base = p1 - d * hl
    pts = [p0 + n * w / 2, base + n * w / 2, base + n * hw / 2, p1, base - n * hw / 2, base - n * w / 2, p0 - n * w / 2]
    return [(q.x, q.y) for q in pts]

def poly2(pts):
    return [(q[0], q[1]) for q in pts]

def curved_arrow(mb, pl, pts, w, w0, w1, mat, hw=None, hl=None):
    """thick path with arrow head at the end. pts = list of 2D points."""
    hw = hw or w * 2.3; hl = hl or w * 2.0
    P = [Vector(q) for q in pts]
    # walk back hl from the end
    acc = 0.0
    i = len(P) - 1
    while i > 0 and acc + (P[i] - P[i - 1]).length < hl:
        acc += (P[i] - P[i - 1]).length
        i -= 1
    rem = hl - acc
    d = (P[i] - P[i - 1]).normalized() if i > 0 else (P[1] - P[0]).normalized()
    base = P[i] - d * rem
    stroke = P[:i] + [base]
    if len(stroke) >= 2:
        mb.prism(pl, stroke_poly([(q.x, q.y) for q in stroke], w), w0, w1, mat, mat, mat, flat=True)
    tip = P[-1]
    dd = (tip - base).normalized(); n = perp2(dd)
    mb.prism(pl, [(q.x, q.y) for q in (base + n * hw / 2, tip, base - n * hw / 2)], w0, w1, mat, mat, mat, flat=True)

def emb(mb, pl, poly, w0, w1, mat):
    mb.prism(pl, poly, w0, w1, mat, mat, mat, flat=True)

def emb_stroke(mb, pl, pts, wd, w0, w1, mat):
    mb.prism(pl, stroke_poly(pts, wd), w0, w1, mat, mat, mat, flat=True)

def emb_ring(mb, pl, outer, inner, w0, w1, mat):
    mb.ring_prism(pl, outer, inner, w0, w1, mat, mat, mat, flat=True)

# ----------------------------------------------------------------------------------------------------------------------
# generic panel + post
# ----------------------------------------------------------------------------------------------------------------------
def sign_post(mb, y, ztop, r=0.038, zbot=0.0):
    mb.cyl((0.0, y, zbot), (0.0, y, ztop), r, r, 'M_RS_GalvSteel', seg=10, smooth=True)
    mb.cyl((0.0, y, ztop), (0.0, y, ztop + 0.012), r + 0.003, r * 0.8, 'M_RS_GalvDark', seg=10, smooth=True)
    mb.cyl((0.0, y, 0.0), (0.0, y, 0.06), r + 0.012, r + 0.012, 'M_RS_GalvDark', seg=10, smooth=True, cap0=True, cap1=True)

def sign_clamps(mb, y, zlist):
    for z in zlist:
        mb.box((0.026, y - 0.05, z - 0.03), (XBACK, y + 0.05, z + 0.03), 'M_RS_GalvDark', c=0.003)
        mb.cyl((0.0, y, z - 0.03), (0.0, y, z + 0.03), 0.043, 0.043, 'M_RS_GalvDark', seg=10, smooth=True)

def plate(mb, pl, kind, p, face, rim=0.012, thick=T_PLATE):
    """plate + folded rim (grey).  returns nothing"""
    out = sh_poly(kind, p, 0.0)
    inn = sh_poly(kind, p, rim)
    mb.prism(pl, inn, 0.0, thick, face, 'M_RS_SignBack', 'M_RS_SignBack')
    mb.ring_prism(pl, out, inn, 0.0, thick + 0.007, 'M_RS_SignBack', 'M_RS_SignBack', 'M_RS_SignBack')

def band(mb, pl, kind, p, i0, i1, mat, w0=T_PLATE, h=T_BAND):
    mb.ring_prism(pl, sh_poly(kind, p, i0), sh_poly(kind, p, i1), w0, w0 + h, mat, mat, mat, flat=True)

def single_post_sign(mb, kind, p, face, zc, draw=None, bands=(), rim=0.012, post_extra=0.12, name=None, hull_w=None, hull_h=None):
    top = zc + (p.get('top', 0.5))
    bot = zc - (p.get('bot', 0.5))
    sign_post(mb, 0.0, top + post_extra)
    sign_clamps(mb, 0.0, [bot + 0.1, top - 0.1] if (top - bot) > 0.35 else [zc])
    pl = sign_plane(XBACK, zc, 0.0)
    plate(mb, pl, kind, p, face, rim)
    for (a, b, m) in bands:
        band(mb, pl, kind, p, a, b, m)
    if draw:
        draw(mb, Plane(pl.O, pl.U, pl.V), T_PLATE + T_BAND)
    mb.sockets['panel_center'] = (XBACK + T_PLATE, 0.0, zc)
    hw = hull_w or p.get('hw', 0.4)
    mb.hull_cyl((0, 0, 0), (0, 0, top + post_extra), 0.045, 8)
    mb.hull_box((XBACK - 0.005, -hw, bot), (XBACK + T_PLATE + 0.012, hw, top))
    return dict(panel_zc=zc, post_height=top + post_extra, panel_top=top, panel_bottom=bot)

# ----------------------------------------------------------------------------------------------------------------------
# speed limits
# ----------------------------------------------------------------------------------------------------------------------
def _speed(mb, n):
    p = dict(r=0.35, top=0.35, bot=0.35, hw=0.35)
    def draw(mb, pl, w0):
        w1 = w0 + T_ICON
        txt = str(n)
        h = 0.20 if len(txt) == 2 else 0.152
        draw_text(mb, pl, txt, 0.0, 0.0, h, 'M_RS_SignBlack', sw=h * 0.17, w0=w0, w1=w1, gap=0.15 if len(txt) == 2 else 0.11)
    return single_post_sign(mb, 'circle', p, 'M_RS_SignWhite', 2.25, draw, bands=[(0.012, 0.012 + 0.065, 'M_RS_SignRed')])

def _mk_speed(n, x):
    @asset('rs_sign_speed_%d' % n, 'Road sign speed limit %d' % n, x=x, ext=(-0.45, 0.5), group='sign', budget=2000, collision='box',
           tags=['all_biomes', 'sign'], scale=(1.0, 1.0), usage='Roadside regulatory sign, face +X, one galvanised post (2.75 m). Place 2-4 m from the road edge.')
    def f(mb):
        return _speed(mb, n)
    return f

for _n, _x in ((30, 120.0), (50, 123.5), (70, 127.0), (90, 130.5), (110, 134.0)):
    _mk_speed(_n, _x)

# ----------------------------------------------------------------------------------------------------------------------
# warning triangles
# ----------------------------------------------------------------------------------------------------------------------
TRI = dict(side=0.92, rc=0.05, top=0.531, bot=0.266, hw=0.46)
TRI_B = [(0.012, 0.012 + 0.085, 'M_RS_SignRed')]

def _tri_sign(mb, draw):
    return single_post_sign(mb, 'tri_up', dict(TRI), 'M_RS_SignWhite', 2.2, draw, bands=TRI_B)

def _icon_curve(mirror):
    def draw(mb, pl, w0):
        w1 = w0 + T_ICON
        m = -1 if mirror else 1
        pts = bezier((0.04, -0.2), (0.04, -0.02), (0.02, 0.05), (-0.17, 0.13), 14)
        pts = [(q.x * m, q.y) for q in pts]
        curved_arrow(mb, pl, pts, 0.058, w0, w1, 'M_RS_SignBlack', hw=0.14, hl=0.115)
    return draw

@asset('rs_sign_curve_left', 'Warning sign curve left', x=138.0, ext=(-0.5, 0.5), group='sign', budget=2000, collision='box', tags=['sign', 'warning'], scale=(1.0, 1.0),
       usage='Place 60-120 m before a left-hand bend; face +X.')
def b_sign_curve_left(mb):
    return _tri_sign(mb, _icon_curve(False))

@asset('rs_sign_curve_right', 'Warning sign curve right', x=141.5, ext=(-0.5, 0.5), group='sign', budget=2000, collision='box', tags=['sign', 'warning'], scale=(1.0, 1.0),
       usage='Place 60-120 m before a right-hand bend; face +X.')
def b_sign_curve_right(mb):
    return _tri_sign(mb, _icon_curve(True))

@asset('rs_sign_hairpin', 'Warning sign hairpin bend', x=145.0, ext=(-0.5, 0.5), group='sign', budget=2000, collision='box', tags=['sign', 'warning', 'mountain'], scale=(1.0, 1.0),
       usage='Before hairpin switchbacks; face +X.')
def b_sign_hairpin(mb):
    def draw(mb, pl, w0):
        w1 = w0 + T_ICON
        pts = [(0.09, -0.19), (0.09, 0.0)] + [(0.0 + 0.09 * cos(radians(a)), 0.0 + 0.09 * sin(radians(a))) for a in range(0, 181, 20)][1:] + [(-0.09, -0.04), (-0.09, -0.09)]
        curved_arrow(mb, pl, pts, 0.048, w0, w1, 'M_RS_SignBlack', hw=0.115, hl=0.09)
    return _tri_sign(mb, draw)

@asset('rs_sign_steep_descent', 'Warning sign steep descent 12%', x=148.5, ext=(-0.5, 0.5), group='sign', budget=2000, collision='box', tags=['sign', 'warning', 'mountain'], scale=(1.0, 1.0),
       usage='Before steep downhill sections; face +X.')
def b_sign_steep(mb):
    def draw(mb, pl, w0):
        w1 = w0 + T_ICON
        emb(mb, pl, [(-0.19, -0.04), (0.19, -0.15), (-0.19, -0.15)], w0, w1, 'M_RS_SignBlack')
        draw_text(mb, pl, '12%', 0.0, 0.065, 0.1, 'M_RS_SignBlack', sw=0.017, w0=w0, w1=w1)
    return _tri_sign(mb, draw)

@asset('rs_sign_tunnel', 'Warning sign tunnel ahead', x=152.0, ext=(-0.5, 0.5), group='sign', budget=2000, collision='box', tags=['sign', 'warning', 'tunnel'], scale=(1.0, 1.0),
       usage='80-150 m before tunnel portals; face +X.')
def b_sign_tunnel(mb):
    def draw(mb, pl, w0):
        w1 = w0 + T_ICON
        arch = [(-0.13, -0.17), (0.13, -0.17), (0.13, -0.04)] + [(0.13 * cos(radians(a)), -0.04 + 0.13 * sin(radians(a))) for a in range(20, 161, 20)] + [(-0.13, -0.04)]
        emb(mb, pl, arch, w0, w1, 'M_RS_SignBlack')
        emb(mb, pl, [(-0.075, -0.17), (0.075, -0.17), (0.022, -0.02), (-0.022, -0.02)], w1, w1 + T_ICON, 'M_RS_SignWhite')
    return _tri_sign(mb, draw)

@asset('rs_sign_bridge', 'Warning sign bridge / narrow bridge', x=155.5, ext=(-0.5, 0.5), group='sign', budget=2000, collision='box', tags=['sign', 'warning', 'bridge'], scale=(1.0, 1.0),
       usage='Before bridges; face +X.')
def b_sign_bridge(mb):
    def draw(mb, pl, w0):
        w1 = w0 + T_ICON
        emb(mb, pl, rectpoly(-0.2, -0.045, 0.2, -0.005), w0, w1, 'M_RS_SignBlack')
        arc = [(0.15 * cos(radians(a)), -0.17 + 0.125 * sin(radians(a))) for a in range(180, -1, -20)]
        emb_stroke(mb, pl, arc, 0.032, w0, w1, 'M_RS_SignBlack')
        for sx in (-1, 1):
            emb(mb, pl, rectpoly(sx * 0.15 - 0.015, -0.175, sx * 0.15 + 0.015, -0.045), w0, w1, 'M_RS_SignBlack')
        emb(mb, pl, rectpoly(-0.2, -0.185, 0.2, -0.165), w0, w1, 'M_RS_SignBlack')
    return _tri_sign(mb, draw)

@asset('rs_sign_junction', 'Warning sign junction ahead', x=159.0, ext=(-0.5, 0.5), group='sign', budget=2000, collision='box', tags=['sign', 'warning', 'junction'], scale=(1.0, 1.0),
       usage='Before side-road junctions; face +X.')
def b_sign_junction(mb):
    def draw(mb, pl, w0):
        w1 = w0 + T_ICON
        emb(mb, pl, rectpoly(-0.026, -0.18, 0.026, 0.115), w0, w1, 'M_RS_SignBlack')
        emb(mb, pl, rectpoly(-0.16, -0.045, 0.16, -0.015), w0, w1, 'M_RS_SignBlack')
        emb(mb, pl, [(-0.055, 0.11), (0.0, 0.17), (0.055, 0.11)], w0, w1, 'M_RS_SignBlack')
    return _tri_sign(mb, draw)

@asset('rs_sign_give_way', 'Regulatory sign give way', x=166.0, ext=(-0.5, 0.5), group='sign', budget=2000, collision='box', tags=['sign', 'junction'], scale=(1.0, 1.0),
       usage='At minor road junctions; face +X.')
def b_sign_giveway(mb):
    p = dict(side=0.92, rc=0.05, top=0.266, bot=0.531, hw=0.46)
    return single_post_sign(mb, 'tri_down', p, 'M_RS_SignWhite', 2.2, None, bands=[(0.012, 0.012 + 0.085, 'M_RS_SignRed')])

@asset('rs_sign_stop', 'Regulatory sign STOP', x=162.5, ext=(-0.5, 0.5), group='sign', budget=2000, collision='box', tags=['sign', 'junction'], scale=(1.0, 1.0),
       usage='At stop-controlled junctions; face +X.')
def b_sign_stop(mb):
    p = dict(across=0.78, rc=0.02, top=0.39, bot=0.39, hw=0.39)
    def draw(mb, pl, w0):
        w1 = w0 + T_ICON
        draw_text(mb, pl, 'STOP', 0.0, 0.0, 0.17, 'M_RS_SignWhite', sw=0.03, w0=w0, w1=w1)
    return single_post_sign(mb, 'oct', p, 'M_RS_SignRed', 2.2, draw, bands=[(0.016, 0.016 + 0.022, 'M_RS_SignWhite')])

# ----------------------------------------------------------------------------------------------------------------------
# direction signs (blue) 3 sizes
# ----------------------------------------------------------------------------------------------------------------------
def _dir_border(mb, pl, kind, p):
    band(mb, pl, kind, p, 0.016, 0.016 + 0.014, 'M_RS_SignWhite')

def _right_arrow(mb, pl, cx, cy, s, w0, w1, mat='M_RS_SignWhite', ang=0.0):
    """chunky arrow of height s, pointing along angle ang (deg, 0 = right)"""
    a = radians(ang)
    d = Vector((cos(a), sin(a)))
    c = Vector((cx, cy))
    emb(mb, pl, arrow_poly(c - d * s * 0.5, c + d * s * 0.5, s * 0.26, s * 0.62, s * 0.42), w0, w1, mat)

def _badge(mb, pl, cx, cy, size, txt, w0, w1):
    p = dict(w=size, h=size * 0.78, rc=size * 0.16)
    outer = [(cx + q[0], cy + q[1]) for q in sh_poly('rect', p, 0.0)]
    emb(mb, pl, outer, w0, w1, 'M_RS_SignWhite')
    draw_text(mb, pl, txt, cx, cy, size * 0.45, 'M_RS_SignBlack', sw=size * 0.075, w0=w1, w1=w1 + T_ICON)

def _dir_sign(mb, W, H, posts_y, ztop_panel, rows, badge=None, zbot=None):
    zc = ztop_panel - H / 2
    p = dict(w=W, h=H, rc=0.045)
    pl = sign_plane(XBACK, zc, 0.0)
    plate(mb, pl, 'rect', p, 'M_RS_SignBlue', 0.014, thick=0.02)
    band(mb, pl, 'rect', p, 0.014 + 0.018, 0.014 + 0.018 + 0.014, 'M_RS_SignWhite', w0=0.02)
    w0 = 0.02 + T_BAND; w1 = w0 + T_ICON
    zb = zc - H / 2
    for y in posts_y:
        sign_post(mb, y, ztop_panel + 0.12)
    if len(posts_y) == 1:
        sign_clamps(mb, posts_y[0], [zb + 0.08, ztop_panel - 0.08])
    else:
        # horizontal back rails
        for z in (zb + 0.1, ztop_panel - 0.1):
            mb.box((0.03, posts_y[0] - 0.04, z - 0.025), (XBACK, posts_y[-1] + 0.04, z + 0.025), 'M_RS_GalvDark', c=0.003)
        for y in posts_y:
            for z in (zb + 0.1, ztop_panel - 0.1):
                mb.cyl((0.0, y, z - 0.03), (0.0, y, z + 0.03), 0.043, 0.043, 'M_RS_GalvDark', seg=10, smooth=True)
    for r in rows:
        r(mb, pl, w0, w1)
    mb.sockets['panel_center'] = (XBACK + 0.02, 0.0, zc)
    for y in posts_y:
        mb.hull_cyl((0, y, 0), (0, y, ztop_panel + 0.12), 0.045, 8)
    mb.hull_box((XBACK - 0.005, -W / 2, zb), (XBACK + 0.03, W / 2, ztop_panel))
    return dict(panel_w=W, panel_h=H, panel_zc=zc, post_height=ztop_panel + 0.12)

@asset('rs_sign_direction_s', 'Direction sign blue small 1.2 x 0.45', x=170.0, ext=(-0.7, 0.7), group='sign', budget=2000, collision='box', tags=['sign', 'direction'], scale=(1.0, 1.0),
       usage='Small direction sign on one post (rural junction). Face +X.')
def b_dir_s(mb):
    def r1(mb, pl, w0, w1):
        draw_text(mb, pl, 'HARBOR', -0.10, 0.07, 0.15, 'M_RS_SignWhite', sw=0.026, w0=w0, w1=w1, align='center')
        draw_text(mb, pl, '12 KM', -0.10, -0.115, 0.085, 'M_RS_SignWhite', sw=0.015, w0=w0, w1=w1, align='center')
        _right_arrow(mb, pl, 0.43, 0.0, 0.2, w0, w1)
    return _dir_sign(mb, 1.2, 0.45, [0.0], 2.45, [r1])

@asset('rs_sign_direction_m', 'Direction sign blue medium 1.8 x 0.65', x=174.5, ext=(-1.0, 1.0), group='sign', budget=2000, collision='box', tags=['sign', 'direction'], scale=(1.0, 1.0),
       usage='Medium direction sign on two posts. Face +X.')
def b_dir_m(mb):
    def r1(mb, pl, w0, w1):
        _badge(mb, pl, -0.73, 0.14, 0.2, '7', w0, w1)
        draw_text(mb, pl, 'OAKRIDGE', -0.05, 0.14, 0.14, 'M_RS_SignWhite', sw=0.024, w0=w0, w1=w1, align='center')
        draw_text(mb, pl, 'HARBOR', -0.17, -0.14, 0.14, 'M_RS_SignWhite', sw=0.024, w0=w0, w1=w1, align='center')
        _right_arrow(mb, pl, 0.66, 0.14, 0.17, w0, w1, ang=90)
        _right_arrow(mb, pl, 0.66, -0.14, 0.17, w0, w1, ang=0)
    return _dir_sign(mb, 1.8, 0.65, [-0.62, 0.62], 2.55, [r1])

@asset('rs_sign_direction_l', 'Direction sign blue large 2.8 x 1.15', x=181.0, ext=(-1.6, 1.6), group='sign', budget=2000, collision='box', tags=['sign', 'direction', 'highway'], scale=(1.0, 1.0),
       usage='Large direction sign on two posts for highways / major junctions. Face +X.')
def b_dir_l(mb):
    def r1(mb, pl, w0, w1):
        rows = [('OAKRIDGE', '12', 0.34), ('HARBOR', '27', 0.0), ('SUMMIT', '41', -0.34)]
        for (a, b, y) in rows:
            draw_text(mb, pl, a, -0.62, y, 0.2, 'M_RS_SignWhite', sw=0.032, w0=w0, w1=w1, align='left')
            draw_text(mb, pl, b, 1.0, y, 0.2, 'M_RS_SignWhite', sw=0.032, w0=w0, w1=w1, align='right')
        _badge(mb, pl, -1.08, 0.0, 0.3, '9', w0, w1)
        _right_arrow(mb, pl, 1.22, 0.0, 0.34, w0, w1, ang=90)
    return _dir_sign(mb, 2.8, 1.15, [-0.95, 0.95], 3.0, [r1])

# ----------------------------------------------------------------------------------------------------------------------
# village name sign / mile marker / chevron / jump / speed trap
# ----------------------------------------------------------------------------------------------------------------------
@asset('rs_sign_village', 'Village name sign (white, black border)', x=187.0, ext=(-0.9, 0.9), group='sign', budget=2000, collision='box', tags=['sign', 'village'], scale=(1.0, 1.0),
       usage='Village entrance sign on two posts. Face +X.')
def b_village(mb):
    W, H = 1.5, 0.55
    zc = 1.55
    p = dict(w=W, h=H, rc=0.05)
    pl = sign_plane(XBACK, zc, 0.0)
    plate(mb, pl, 'rect', p, 'M_RS_SignWhite', 0.014, thick=0.02)
    band(mb, pl, 'rect', p, 0.014 + 0.012, 0.014 + 0.012 + 0.02, 'M_RS_SignBlack', w0=0.02)
    w0 = 0.02 + T_BAND; w1 = w0 + T_ICON
    draw_text(mb, pl, 'OAKRIDGE', 0.0, 0.04, 0.185, 'M_RS_SignBlack', sw=0.031, w0=w0, w1=w1)
    emb(mb, pl, rectpoly(-0.5, -0.12, 0.5, -0.105), w0, w1, 'M_RS_SignBlack')
    for y in (-0.62, 0.62):
        sign_post(mb, y, zc + H / 2 + 0.1)
        for z in (zc - 0.17, zc + 0.17):
            mb.box((0.03, y - 0.04, z - 0.025), (XBACK, y + 0.04, z + 0.025), 'M_RS_GalvDark', c=0.003)
            mb.cyl((0.0, y, z - 0.03), (0.0, y, z + 0.03), 0.043, 0.043, 'M_RS_GalvDark', seg=10, smooth=True)
        mb.hull_cyl((0, y, 0), (0, y, zc + H / 2 + 0.1), 0.045, 8)
    mb.hull_box((XBACK - 0.005, -W / 2, zc - H / 2), (XBACK + 0.03, W / 2, zc + H / 2))
    mb.sockets['panel_center'] = (XBACK + 0.02, 0.0, zc)
    return dict(panel_w=W, panel_h=H)

@asset('rs_milemarker', 'Kilometre marker post (white, green plate)', x=191.0, ext=(-0.3, 0.3), group='sign', budget=2000, collision='box', tags=['sign', 'highway', 'all_biomes'], scale=(1.0, 1.0),
       usage='Every 1 km along primary roads; plate faces +X.')
def b_milemarker(mb):
    W, D, H = 0.2, 0.09, 1.0
    prof = rounded_poly([(-D / 2, -W / 2), (D / 2, -W / 2), (D / 2, W / 2), (-D / 2, W / 2)], 0.02, 3)
    zs = [0.0, 0.9, 0.96, 1.0]
    scl = [(1, 1), (1, 1), (0.95, 0.96), (0.8, 0.9)]
    mb.vsweep(prof, zs, 'M_RS_PlasticWhite', scale=lambda t: scl[min(3, int(round(t * 3)))], smooth=True)
    pl = Plane((D / 2, 0.0, 0.0), (0, 1, 0), (0, 0, 1))
    # green plate top, black band below
    emb(mb, pl, rectpoly(-W / 2 + 0.01, 0.62, W / 2 - 0.01, 0.9), 0.0, 0.0012, 'M_RS_SignGreen')
    draw_text(mb, pl, '12', 0.0, 0.8, 0.11, 'M_RS_SignWhite', sw=0.02, w0=0.0012, w1=0.0024)
    draw_text(mb, pl, 'KM', 0.0, 0.67, 0.05, 'M_RS_SignWhite', sw=0.009, w0=0.0012, w1=0.0024)
    emb(mb, pl, rectpoly(-W / 2 + 0.002, 0.40, W / 2 - 0.002, 0.5), 0.0, 0.0012, 'M_RS_PaintBlack')
    # amber reflector button (a real raised button)
    mb.prism(pl, ellipse_pts(0.0, 0.2, 0.03, 0.03, 14), 0.0, 0.006, 'M_RS_ReflectorAmber', 'M_RS_ReflectorAmber', 'M_RS_ReflectorAmber')
    mb.lathe([(0.12, 0.0), (0.12, 0.012), (0.09, 0.022), (0.05, 0.05), (0.0, 0.05)], 'M_RS_Rubber', seg=12, smooth=False, row_smooth=[False, False, True, False])
    mb.hull_box((-D / 2, -W / 2, 0.0), (D / 2, W / 2, 1.0))
    return dict(height=H)

def _chevron(mb, mirror):
    W = 0.80
    p = dict(w=W, h=W, rc=0.04, top=W / 2, bot=W / 2, hw=W / 2)
    def draw(mb, pl, w0):
        w1 = w0 + T_ICON
        m = -1 if mirror else 1
        # bold chevron '>' (pointing right as seen from the front when not mirrored)
        pts = [(-0.18 * m, 0.26), (0.02 * m, 0.26), (0.2 * m, 0.0), (0.02 * m, -0.26), (-0.18 * m, -0.26), (0.0 * m, 0.0)]
        emb(mb, pl, pts, w0, w1, 'M_RS_SignBlack')
    return single_post_sign(mb, 'rect', p, 'M_RS_SignYellow', 1.95, draw, bands=[(0.012 + 0.018, 0.012 + 0.018 + 0.028, 'M_RS_SignBlack')])

@asset('rs_sign_chevron_right', 'Chevron arrow board (right)', x=194.0, ext=(-0.5, 0.5), group='sign', budget=2000, collision='box', tags=['sign', 'warning', 'mountain'], scale=(1.0, 1.0),
       usage='Outside of bends; chevron points right as seen by the driver (face +X).')
def b_chev_r(mb):
    return _chevron(mb, False)

@asset('rs_sign_chevron_left', 'Chevron arrow board (left)', x=197.5, ext=(-0.5, 0.5), group='sign', budget=2000, collision='box', tags=['sign', 'warning', 'mountain'], scale=(1.0, 1.0),
       usage='Outside of bends; chevron points left as seen by the driver (face +X).')
def b_chev_l(mb):
    return _chevron(mb, True)

@asset('rs_sign_jump', 'Danger jump yellow diamond sign + JUMP plate', x=201.0, ext=(-0.6, 0.6), group='sign', budget=2000, collision='box', tags=['sign', 'warning', 'stunt'], scale=(1.0, 1.0),
       usage='Before stunt ramps / road crests marked as jumps; face +X.')
def b_jump(mb):
    p = dict(diag=0.92, rc=0.045, top=0.46, bot=0.46, hw=0.46)
    zc = 2.25
    # diamond
    def draw(mb, pl, w0):
        w1 = w0 + T_ICON
        emb(mb, pl, [(-0.22, -0.16), (0.12, -0.16), (0.12, -0.02)], w0, w1, 'M_RS_SignBlack')       # ramp wedge rising to the right
        pts = bezier((-0.02, 0.0), (0.05, 0.22), (0.2, 0.2), (0.28, 0.02), 14)
        curved_arrow(mb, pl, [(q.x, q.y) for q in pts], 0.032, w0, w1, 'M_RS_SignBlack', hw=0.085, hl=0.075)
    info = single_post_sign(mb, 'diamond', p, 'M_RS_SignYellow', zc, draw, bands=[(0.012 + 0.016, 0.012 + 0.016 + 0.026, 'M_RS_SignBlack')], post_extra=0.12)
    sign_clamps(mb, 0.0, [zc - 0.46 - 0.12])
    # supplementary plate below
    pw = dict(w=0.62, h=0.2, rc=0.03)
    pl = sign_plane(XBACK, zc - 0.46 - 0.12, 0.0)
    plate(mb, pl, 'rect', pw, 'M_RS_SignYellow', 0.012)
    band(mb, pl, 'rect', pw, 0.012 + 0.012, 0.012 + 0.012 + 0.012, 'M_RS_SignBlack')
    draw_text(mb, pl, 'JUMP', 0.0, 0.0, 0.1, 'M_RS_SignBlack', sw=0.018, w0=T_PLATE + T_BAND, w1=T_PLATE + T_BAND + T_ICON)
    mb.hull_box((XBACK - 0.005, -0.31, zc - 0.46 - 0.22), (XBACK + 0.03, 0.31, zc - 0.46 - 0.02))
    return info

@asset('rs_speedtrap_camera', 'Speed trap camera post (3.4 m pole, housing, cabinet)', x=206.0, ext=(-0.6, 0.6), group='sign', budget=2000, collision='box', tags=['enforcement', 'highway', 'all_biomes'], scale=(1.0, 1.0),
       usage='Speed-trap gameplay prop: camera housing looks along +X (towards approaching traffic from the front). Flash lens sockets in JSON.')
def b_speedtrap(mb):
    H = 3.4
    # base plate + pole (octagonal tapered)
    mb.box((-0.18, -0.18, 0.0), (0.18, 0.18, 0.02), 'M_RS_GalvDark', c=0.004)
    for sx in (-1, 1):
        for sy in (-1, 1):
            hexbolt(mb, (sx * 0.135, sy * 0.135, 0.02), (0, 0, 1), r=0.012, ln=0.016, wash=0.022, wash_t=0.003)
    mb.lathe([(0.075, 0.02), (0.065, 0.30), (0.055, H - 0.15), (0.058, H - 0.1), (0.058, H - 0.04), (0.0, H - 0.04)], 'M_RS_PaintGrey', seg=12, smooth=True, row_smooth=[True, True, False, False, False])
    # cabinet at the foot (equipment box)
    mb.box((-0.55, -0.25, 0.0), (-0.12, 0.25, 1.05), 'M_RS_PaintGrey', c=0.012)
    mb.box((-0.55 - 0.003, -0.22, 0.12), (-0.55 + 0.008, 0.22, 0.95), 'M_RS_PaintBlack', c=0.004)
    mb.box((-0.56, 0.18, 0.5), (-0.54, 0.205, 0.6), 'M_RS_GalvDark')                              # lock
    for k in range(6):                                                                        # louvre vent in the cabinet door
        mb.box((-0.575, -0.17, 0.16 + k * 0.045), (-0.55, 0.05, 0.16 + k * 0.045 + 0.018), 'M_RS_PaintBlack')
    mb.box((-0.56, -0.235, 0.1), (-0.545, -0.215, 0.97), 'M_RS_GalvDark')                      # hinge strap
    # armoured cable conduit from the cabinet roof up the pole to the arm
    cp = [Vector((-0.34, 0.0, 1.05)), Vector((-0.30, 0.0, 1.16)), Vector((-0.12, -0.02, 1.26)), Vector((0.0, -0.085, 1.35)),
          Vector((0.0, -0.088, 2.2)), Vector((0.0, -0.088, H - 0.55))]
    mb.tube(cp, 0.014, 'M_RS_PaintBlack', seg=6, smooth=True)
    for zz in (1.5, 2.0, 2.5):
        mb.box((-0.02, -0.12, zz - 0.012), (0.02, -0.06, zz + 0.012), 'M_RS_GalvDark')
    # horizontal arm + housing
    zc = H - 0.42
    mb.box((-0.05, -0.045, zc - 0.045), (0.5, 0.045, zc + 0.045), 'M_RS_PaintGrey', c=0.008)
    mb.box((0.30, -0.19, zc - 0.17), (0.88, 0.19, zc + 0.17), 'M_RS_PaintGrey', c=0.03)
    mb.box((0.31, -0.20, zc + 0.17), (0.98, 0.20, zc + 0.205), 'M_RS_PaintBlack', c=0.01)      # sun visor (projects past the lens)
    # side vents (louvre slats) on both flanks of the housing, rear heat-sink fins, status LED
    for sy in (-1, 1):
        for k in range(4):
            zz = zc - 0.10 + k * 0.055
            mb.box((0.42, sy * 0.190 if sy > 0 else -0.196, zz), (0.62, sy * 0.196 if sy > 0 else -0.190, zz + 0.016), 'M_RS_PaintBlack')
    for k in range(5):
        mb.box((0.27, -0.15 + k * 0.075, zc - 0.12), (0.30, -0.15 + k * 0.075 + 0.02, zc + 0.12), 'M_RS_GalvDark')
    mb.box((0.84, 0.15, zc + 0.12), (0.86, 0.175, zc + 0.145), 'M_RS_ReflectorRed')
    # lens + flash window on the +X face
    mb.cyl((0.88, -0.07, zc + 0.02), (0.905, -0.07, zc + 0.02), 0.075, 0.075, 'M_RS_PaintBlack', seg=14, smooth=True)
    mb.cyl((0.905, -0.07, zc + 0.02), (0.912, -0.07, zc + 0.02), 0.052, 0.052, 'M_RS_ReflectorWhite', seg=14, smooth=True)
    mb.box((0.88, 0.04, zc - 0.07), (0.9, 0.16, zc + 0.11), 'M_RS_PaintBlack', c=0.004)
    mb.box((0.9, 0.05, zc - 0.055), (0.907, 0.15, zc + 0.095), 'M_RS_ReflectorAmber')
    # warning plate on the pole (small yellow rectangle with black border)
    mb.box((0.052, -0.11, 2.45), (0.062, 0.11, 2.75), 'M_RS_SignYellow', c=0.003)
    mb.sockets['camera_lens'] = (0.912, -0.07, zc + 0.02)
    mb.sockets['flash'] = (0.907, 0.10, zc + 0.02)
    mb.hull_cyl((0, 0, 0), (0, 0, H), 0.09, 8)
    mb.hull_box((-0.55, -0.25, 0.0), (-0.12, 0.25, 1.05))
    mb.hull_box((0.30, -0.2, zc - 0.17), (0.92, 0.2, zc + 0.2))
    return dict(height=H, camera_height=zc)
