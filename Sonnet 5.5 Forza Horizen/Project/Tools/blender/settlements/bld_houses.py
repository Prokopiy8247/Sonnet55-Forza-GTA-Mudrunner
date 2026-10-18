# -*- coding: utf-8 -*-
"""Settlements kit - village houses (4 footprints). exec'd into the kit namespace by settlements_kit.py"""

SH = 2.75      # storey height
ZB = 0.4       # plinth height (floor level)
WT = 0.32      # wall thickness


def _rects(cfg):
    opens = {}; units = []
    for e, items in cfg['open'].items():
        for it in items:
            kind = it[0]
            opt = it[-1] if isinstance(it[-1], dict) else {}
            if kind == 'w':
                uc, ww, hh, fl = it[1:5]
                v0 = ZB + fl * SH + 0.85; v1 = v0 + hh
                r = (uc - ww / 2, uc + ww / 2, v0, v1)
            else:
                uc, ww, hh = it[1:4]
                r = (uc - ww / 2, uc + ww / 2, ZB, ZB + hh)
            opens.setdefault(e, []).append(r)
            units.append((e, kind, r, opt))
    return opens, units


def wing_hulls(mb, w, eave):
    ov = w.get('ov_e', 0.55); g0 = w.get('ov_g0', 0.3); g1 = w.get('ov_g1', 0.3)
    x0, x1, y0, y1 = w['x0'], w['x1'], w['y0'], w['y1']
    mb.hull_box((x0, y0, 0.0), (x1, y1, eave))
    tn = tan(radians(w['pitch']))
    if w['axis'] == 'y':
        xm = (x0 + x1) / 2; rz = eave + (x1 - x0) / 2 * tn
        ya, yb = y0 - g0, y1 + g1
        mb.hull_pts([(x0 - ov, ya, eave - ov * tn), (x1 + ov, ya, eave - ov * tn), (xm, ya, rz + 0.1),
                     (x0 - ov, yb, eave - ov * tn), (x1 + ov, yb, eave - ov * tn), (xm, yb, rz + 0.1)])
    else:
        ym = (y0 + y1) / 2; rz = eave + (y1 - y0) / 2 * tn
        xa, xb = x0 - g0, x1 + g1
        mb.hull_pts([(xa, y0 - ov, eave - ov * tn), (xa, y1 + ov, eave - ov * tn), (xa, ym, rz + 0.1),
                     (xb, y0 - ov, eave - ov * tn), (xb, y1 + ov, eave - ov * tn), (xb, ym, rz + 0.1)])
    return rz


def build_house(mb, cfg):
    poly = cfg['poly']; floors = cfg.get('floors', 1)
    eave = ZB + SH * floors
    wmat = cfg.get('wall', 'M_Bld_Plaster'); tint = cfg.get('tint', PAL['cream'])
    opens, units = _rects(cfg)
    wfs, convex = house_walls(mb, poly, ZB, eave, WT, opens, wmat, col=tint)
    plinth(mb, poly, ZB, 0.05)
    shut = cfg.get('shutters', 'M_Bld_Wood')
    for (e, kind, r, opt) in units:
        if kind == 'w':
            window_unit(mb, wfs[e], r[0], r[1], r[2], r[3], WT, shutters=opt.get('sh', shut), panes=opt.get('panes', (2, 2)),
                        box=opt.get('box'))
        else:
            door_unit(mb, wfs[e], r[0], r[1], r[2], r[3], WT, steps=opt.get('steps', True))
    quoins(mb, wfs, convex, ZB, eave)
    if floors > 1:
        band(mb, poly, ZB + SH - 0.08, 0.16, 0.06)
    for (e, ua, ub, pitch) in cfg.get('gables', []):
        rise = (ub - ua) / 2 * tan(radians(pitch))
        gable_fill(mb, wfs[e], ua, ub, eave, rise, WT, wmat, col=tint)
        if cfg.get('attic', True) and rise > 1.7:
            gable_window(mb, wfs[e], (ua + ub) / 2, eave + 0.95, 0.75, 0.95)
    rzs = []
    for w in cfg['roofs']:
        rz, _ = gable_wing(mb, w['x0'], w['x1'], w['y0'], w['y1'], eave, w['pitch'], w['axis'], ov_e=w.get('ov_e', 0.55),
                           ov_g0=w.get('ov_g0', 0.3), ov_g1=w.get('ov_g1', 0.3), ridge_mat=w.get('ridge'))
        rzs.append(rz)
        wing_hulls(mb, w, eave)
    for (cx, cy, zt, cw, cd, cm) in cfg.get('chimneys', []):
        chimney(mb, cx, cy, eave - 0.6, zt, cw, cd, cm)
    for (x, y) in cfg.get('pipes', []):
        downpipe(mb, x, y, ZB, eave - 0.1)
    return eave, rzs


# ---------------------------------------------------------------------------------------------------------------------
@asset('bld_house_a', 'Village house A (7x9 m, plaster, gabled)', x=0.0, ext=(-5.5, 5.5), group='houses', budget=14000, collision='box',
       tags=['village', 'temperate', 'greenvale'], scale=(0.9, 1.15), usage='Village house, ridge along Y, door on +X eave side')
def house_a(mb):
    cfg = dict(poly=[(-3.5, -4.5), (3.5, -4.5), (3.5, 4.5), (-3.5, 4.5)], tint=PAL['cream'],
               open={1: [('w', 1.7, 1.0, 1.25, 0), ('d', 4.5, 1.05, 2.1), ('w', 7.3, 1.0, 1.25, 0)],
                     0: [('w', 3.5, 1.0, 1.25, 0)], 2: [('w', 3.5, 1.0, 1.25, 0)],
                     3: [('w', 2.2, 1.0, 1.25, 0), ('w', 6.8, 1.0, 1.25, 0)]},
               gables=[(0, 0.0, 7.0, 38), (2, 0.0, 7.0, 38)],
               roofs=[dict(x0=-3.5, x1=3.5, y0=-4.5, y1=4.5, axis='y', pitch=38)],
               chimneys=[(0.0, 3.2, 6.4, 0.8, 0.95, 'M_Bld_Stone')], pipes=[(3.62, -4.38)])
    eave, rz = build_house(mb, cfg)
    return dict(footprint=[7.0, 9.0], height=round(rz[0] + 0.9, 2))


@asset('bld_house_b', 'Village house B (9x11 m, front gable + porch)', x=18.0, ext=(-6.5, 8.0), group='houses', budget=18000, collision='box',
       tags=['village', 'temperate', 'greenvale'], scale=(0.9, 1.15), usage='Larger village house, gable faces +X, porch over the door')
def house_b(mb):
    cfg = dict(poly=[(-5.5, -4.5), (5.5, -4.5), (5.5, 4.5), (-5.5, 4.5)], tint=PAL['ochre'],
               open={1: [('w', 1.6, 1.0, 1.25, 0), ('d', 4.5, 1.1, 2.15, dict(steps=False)), ('w', 7.4, 1.0, 1.25, 0)],
                     0: [('w', 2.0, 1.0, 1.25, 0), ('w', 5.5, 1.0, 1.25, 0), ('w', 9.0, 1.0, 1.25, 0)],
                     2: [('w', 2.0, 1.0, 1.25, 0), ('w', 5.5, 1.0, 1.25, 0), ('w', 9.0, 1.0, 1.25, 0)],
                     3: [('w', 2.5, 1.0, 1.25, 0), ('w', 6.5, 1.0, 1.25, 0)]},
               gables=[(1, 0.0, 9.0, 36), (3, 0.0, 9.0, 36)],
               roofs=[dict(x0=-5.5, x1=5.5, y0=-4.5, y1=4.5, axis='x', pitch=36, ov_g0=0.35, ov_g1=0.45)],
               chimneys=[(-2.6, 0.0, 7.5, 0.85, 0.95, 'M_Bld_Stone')], pipes=[(-5.62, 4.38)])
    eave, rzs = build_house(mb, cfg)
    # porch over the front door
    px = 5.5
    mb.box((px, -1.7, 0.0), (px + 1.9, 1.7, 0.22), 'M_Bld_Stone', c=0.02)
    for sy in (-1.45, 1.45):
        mb.box((px + 1.55, sy - 0.08, 0.22), (px + 1.7, sy + 0.08, 2.9), 'M_Bld_Wood', c=0.01)
        mb.box((px + 1.5, sy - 0.14, 0.22), (px + 1.76, sy + 0.14, 0.34), 'M_Bld_Stone')
    mb.box((px + 1.5, -1.62, 2.86), (px + 1.78, 1.62, 3.05), 'M_Bld_Wood', c=0.01)
    roof_slope(mb, (px + 2.0, -1.9, 2.95), (px - 0.05, -1.9, 3.5), (0, 1, 0), 3.8, 'M_Bld_RoofTile', 'M_Bld_Wood', course=0.28)
    mb.hull_box((px, -1.8, 0.0), (px + 2.0, 1.8, 3.4))
    return dict(footprint=[11.0, 9.0], porch=True)


@asset('bld_house_c', 'Village house C (6x8 m two-storey, brick)', x=36.0, ext=(-4.5, 4.5), group='houses', budget=16000, collision='box',
       tags=['village', 'town', 'temperate'], scale=(0.9, 1.15), usage='Narrow two-storey brick town house, ridge along Y')
def house_c(mb):
    cfg = dict(poly=[(-3.0, -4.0), (3.0, -4.0), (3.0, 4.0), (-3.0, 4.0)], floors=2, wall='M_Bld_Brick', tint=(1, 1, 1, 1),
               open={1: [('d', 2.1, 1.05, 2.1), ('w', 4.6, 1.0, 1.25, 0), ('w', 6.6, 1.0, 1.25, 0),
                         ('w', 2.1, 1.0, 1.25, 1), ('w', 4.6, 1.0, 1.25, 1), ('w', 6.6, 1.0, 1.25, 1)],
                     0: [('w', 3.0, 1.0, 1.25, 0), ('w', 3.0, 1.0, 1.25, 1)],
                     2: [('w', 3.0, 1.0, 1.25, 0), ('w', 3.0, 1.0, 1.25, 1)],
                     3: [('w', 2.0, 1.0, 1.25, 0), ('w', 6.0, 1.0, 1.25, 0), ('w', 2.0, 1.0, 1.25, 1), ('w', 6.0, 1.0, 1.25, 1)]},
               gables=[(0, 0.0, 6.0, 42), (2, 0.0, 6.0, 42)], attic=False,
               roofs=[dict(x0=-3.0, x1=3.0, y0=-4.0, y1=4.0, axis='y', pitch=42, ov_e=0.5)],
               chimneys=[(0.0, 3.0, 9.5, 0.8, 0.9, 'M_Bld_Brick'), (0.0, -3.0, 9.5, 0.8, 0.9, 'M_Bld_Brick')],
               pipes=[(3.12, 3.88)])
    eave, rzs = build_house(mb, cfg)
    return dict(footprint=[6.0, 8.0], floors=2)


@asset('bld_house_l', 'Village house L-shape (10x11 m)', x=52.0, ext=(-6.5, 6.5), group='houses', budget=22000, collision='box',
       tags=['village', 'temperate', 'greenvale'], scale=(0.9, 1.15), usage='L-shaped farm/village house, front arm along +X, door on the arm')
def house_l(mb):
    cfg = dict(poly=[(-5, -5.5), (5, -5.5), (5, 0), (0, 0), (0, 5.5), (-5, 5.5)], tint=PAL['pink'],
               open={1: [('d', 1.8, 1.05, 2.1), ('w', 4.2, 1.0, 1.25, 0)],
                     3: [('w', 1.5, 1.0, 1.25, 0), ('w', 4.0, 1.0, 1.25, 0)],
                     2: [('w', 2.5, 1.0, 1.25, 0)],
                     0: [('w', 2.5, 1.0, 1.25, 0), ('w', 6.5, 1.0, 1.25, 0), ('w', 8.5, 1.0, 1.25, 0)],
                     4: [('w', 2.5, 1.0, 1.25, 0)],
                     5: [('w', 2.0, 1.0, 1.25, 0), ('w', 5.5, 1.0, 1.25, 0), ('w', 9.0, 1.0, 1.25, 0)]},
               gables=[(0, 0.0, 5.0, 38), (4, 0.0, 5.0, 38), (1, 0.0, 5.5, 33)],
               roofs=[dict(x0=-5, x1=0, y0=-5.5, y1=5.5, axis='y', pitch=38),
                      dict(x0=-2.3, x1=5, y0=-5.5, y1=0, axis='x', pitch=33, ov_g0=0.0, ov_g1=0.3)],
               chimneys=[(-2.5, 3.6, 5.9, 0.8, 0.95, 'M_Bld_Stone')], pipes=[(5.12, -5.38), (-4.88, 5.38)])
    eave, rzs = build_house(mb, cfg)
    return dict(footprint=[10.0, 11.0], shape='L')
