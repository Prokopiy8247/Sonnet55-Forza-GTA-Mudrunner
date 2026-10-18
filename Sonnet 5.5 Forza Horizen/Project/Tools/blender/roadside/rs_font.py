# -*- coding: utf-8 -*-
"""Roadside kit: original geometric stroke font (digits, A-Z, a few symbols) used for sign text.
Glyphs are centre-lines in a unit box (x 0..1 across the glyph width, y 0..1 over the cap height).
Strokes are expanded to thick polygons; sharp joints are split into separate overlapping strokes (square-capped) so the
outlines never self-intersect."""

def _E(cx, cy, rx, ry, n, st=90):
    return ellipse_pts(cx, cy, rx, ry, n, st)

GLYPHS = {
    '0': (0.60, [('c', _E(.5, .5, .5, .5, 22))]),
    '1': (0.42, [('o', [(.08, .72), (.58, 1.0), (.58, 0.0)])]),
    '2': (0.60, [('o', arc_pts(.5, .73, .5, .27, 155, -35, 11) + [(0.0, 0.0), (1.0, 0.0)])]),
    '3': (0.60, [('o', arc_pts(.47, .75, .47, .25, 150, -90, 10)), ('o', arc_pts(.5, .26, .5, .26, 90, -150, 12)), ('o', [(.2, .5), (.5, .5)])]),
    '4': (0.62, [('o', [(.74, 0.0), (.74, 1.0)]), ('o', [(.74, 1.0), (0.0, .3)]), ('o', [(0.0, .3), (1.0, .3)])]),
    '5': (0.60, [('o', [(.92, 1.0), (.14, 1.0), (.1, .56)]), ('o', arc_pts(.47, .31, .53, .31, 125, -150, 13))]),
    '6': (0.60, [('c', _E(.5, .31, .5, .31, 18)), ('o', [(q.x, q.y) for q in bezier((0.95, .88), (0.55, 1.12), (-0.05, 0.98), (0.0, 0.33), 10)])]),
    '7': (0.60, [('o', [(0.0, 1.0), (1.0, 1.0), (.32, 0.0)])]),
    '8': (0.60, [('c', _E(.5, .77, .42, .23, 18)), ('c', _E(.5, .27, .5, .27, 20))]),
    '9': (0.60, [('c', _E(.5, .69, .5, .31, 18)), ('o', [(q.x, q.y) for q in bezier((1.0, .67), (1.0, .2), (.7, -.02), (.06, .12), 10)])]),
    'A': (0.66, [('o', [(0, 0), (.5, 1)]), ('o', [(.5, 1), (1, 0)]), ('o', [(.2, .34), (.8, .34)])]),
    'B': (0.60, [('o', [(0, 0), (0, 1)]), ('o', [(0, 1), (.6, 1)] + arc_pts(.6, .76, .4, .24, 90, -90, 9)[1:] + [(0, .52)]),
                 ('o', [(0, .52), (.66, .52)] + arc_pts(.66, .26, .34, .26, 90, -90, 9)[1:] + [(0, 0)])]),
    'C': (0.64, [('o', arc_pts(.52, .5, .5, .5, 42, 318, 18))]),
    'D': (0.64, [('o', [(0, 0), (0, 1)]), ('o', [(0, 1), (.38, 1)] + arc_pts(.38, .5, .62, .5, 90, -90, 12)[1:] + [(0, 0)])]),
    'E': (0.54, [('o', [(1, 1), (0, 1)]), ('o', [(0, 1), (0, 0)]), ('o', [(0, 0), (1, 0)]), ('o', [(0, .5), (.78, .5)])]),
    'F': (0.52, [('o', [(1, 1), (0, 1)]), ('o', [(0, 1), (0, 0)]), ('o', [(0, .5), (.75, .5)])]),
    'G': (0.66, [('o', arc_pts(.5, .5, .5, .5, 38, 322, 19)), ('o', [(.98, .46), (.56, .46)]), ('o', [(.98, .46), (.88, .2)])]),
    'H': (0.64, [('o', [(0, 0), (0, 1)]), ('o', [(1, 0), (1, 1)]), ('o', [(0, .5), (1, .5)])]),
    'I': (0.22, [('o', [(.5, 0), (.5, 1)])]),
    'J': (0.52, [('o', [(1, 1), (1, .34)] + arc_pts(.5, .34, .5, .34, 0, -170, 10)[1:])]),
    'K': (0.62, [('o', [(0, 0), (0, 1)]), ('o', [(1, 1), (0.02, .4)]), ('o', [(.3, .6), (1, 0)])]),
    'L': (0.52, [('o', [(0, 1), (0, 0)]), ('o', [(0, 0), (.95, 0)])]),
    'M': (0.84, [('o', [(0, 0), (0, 1)]), ('o', [(0, 1), (.5, .38)]), ('o', [(.5, .38), (1, 1)]), ('o', [(1, 1), (1, 0)])]),
    'N': (0.66, [('o', [(0, 0), (0, 1)]), ('o', [(0, 1), (1, 0)]), ('o', [(1, 0), (1, 1)])]),
    'O': (0.68, [('c', _E(.5, .5, .5, .5, 22))]),
    'P': (0.58, [('o', [(0, 0), (0, 1)]), ('o', [(0, 1), (.62, 1)] + arc_pts(.62, .74, .38, .26, 90, -90, 9)[1:] + [(0, .48)])]),
    'Q': (0.68, [('c', _E(.5, .5, .5, .5, 22)), ('o', [(.55, .3), (1.0, -.06)])]),
    'R': (0.60, [('o', [(0, 0), (0, 1)]), ('o', [(0, 1), (.62, 1)] + arc_pts(.62, .74, .38, .26, 90, -90, 9)[1:] + [(0, .48)]), ('o', [(.4, .48), (1, 0)])]),
    'S': (0.58, [('o', arc_pts(.5, .75, .5, .25, 25, 270, 14) + arc_pts(.5, .25, .5, .25, 90, -155, 14)[1:])]),
    'T': (0.60, [('o', [(0, 1), (1, 1)]), ('o', [(.5, 1), (.5, 0)])]),
    'U': (0.64, [('o', [(0, 1), (0, .34)] + arc_pts(.5, .34, .5, .34, 180, 360, 11)[1:] + [(1, 1)])]),
    'V': (0.64, [('o', [(0, 1), (.5, 0)]), ('o', [(.5, 0), (1, 1)])]),
    'W': (0.92, [('o', [(0, 1), (.25, 0)]), ('o', [(.25, 0), (.5, .7)]), ('o', [(.5, .7), (.75, 0)]), ('o', [(.75, 0), (1, 1)])]),
    'X': (0.62, [('o', [(0, 0), (1, 1)]), ('o', [(0, 1), (1, 0)])]),
    'Y': (0.62, [('o', [(0, 1), (.5, .5)]), ('o', [(.5, .5), (1, 1)]), ('o', [(.5, .5), (.5, 0)])]),
    'Z': (0.60, [('o', [(0, 1), (1, 1)]), ('o', [(1, 1), (0, 0)]), ('o', [(0, 0), (1, 0)])]),
    '-': (0.44, [('o', [(.05, .5), (.95, .5)])]),
    '.': (0.18, [('o', [(.5, 0.0), (.5, .1)])]),
    '/': (0.50, [('o', [(.9, 1), (.1, 0)])]),
    '%': (0.86, [('c', _E(.2, .8, .2, .17, 12)), ('c', _E(.8, .2, .2, .17, 12)), ('o', [(.88, 1), (.12, 0)])]),
    ' ': (0.30, []),
}

WSCALE = 1.14

def text_width(txt, h, gap=0.15):
    w = 0.0
    for i, ch in enumerate(txt.upper()):
        g = GLYPHS.get(ch, GLYPHS[' '])
        w += g[0] * h * WSCALE + (gap * h if i < len(txt) - 1 else 0)
    return w

def _split_sharp(pts, hw, max_turn=62.0):
    """Split a polyline where the turn is sharp; extend split ends by hw so neighbours overlap (square joint)."""
    P = [Vector(p) for p in pts]
    pieces = []
    cur = [P[0]]
    flags = [False]      # start extended?
    for i in range(1, len(P) - 1):
        a = (P[i] - P[i - 1]).normalized(); b = (P[i + 1] - P[i]).normalized()
        turn = degrees(acos(max(-1.0, min(1.0, a.dot(b)))))
        cur.append(P[i])
        if turn > max_turn:
            pieces.append((cur, flags[-1], True))
            cur = [P[i]]
            flags.append(True)
    cur.append(P[-1])
    pieces.append((cur, flags[-1], False))
    out = []
    for (pl, ext0, ext1) in pieces:
        pl = list(pl)
        if ext0:
            d = (pl[1] - pl[0]).normalized(); pl[0] = pl[0] - d * hw * 0.92
        if ext1:
            d = (pl[-1] - pl[-2]).normalized(); pl[-1] = pl[-1] + d * hw * 0.92
        out.append([(q.x, q.y) for q in pl])
    return out

def draw_text(mb, plane, txt, uc, vc, h, mat, sw=None, w0=0.0, w1=0.004, align='center', gap=0.15, ms=None, mb_mat=None, flat=True):
    """Stroke text on `plane`, centred on (uc,vc). h = cap height (m). Returns total width.
    flat=True (default): single-sided decal cards at height w1 above the plane (no hidden bottom / side faces); flat=False: solid relief w0..w1."""
    sw = min(sw or h * 0.13, h * 0.14)
    tw = text_width(txt, h, gap)
    if align == 'center': x = uc - tw / 2
    elif align == 'left': x = uc
    else: x = uc - tw
    y0 = vc - h / 2
    for ch in txt.upper():
        gw, strokes = GLYPHS.get(ch, GLYPHS[' '])
        W = gw * h * WSCALE
        for kind, pts in strokes:
            q = [(x + sw / 2 + px * (W - sw), y0 + sw / 2 + py * (h - sw)) for (px, py) in pts]
            if kind == 'o':
                for piece in _split_sharp(q, sw / 2):
                    mb.prism(plane, stroke_poly(piece, sw, 1.5), w0, w1, mat, ms or mat, mb_mat or ms or mat, flat=flat)
            else:
                o, i = stroke_ring(q, sw, 1.5)
                mb.ring_prism(plane, o, i, w0, w1, mat, ms or mat, mb_mat or ms or mat, flat=flat)
        x += W + gap * h
    return tw
