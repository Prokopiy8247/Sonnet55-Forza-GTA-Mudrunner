# -*- coding: utf-8 -*-
"""Roadside kit part 4: street lamp, gantry lamp, wooden utility pole, catenary wire span.
Origin = base centre on the ground. Arms / booms reach towards +Y (the road side)."""

def _lerp(a, b, t):
    return a + (b - a) * t

def _lamp_head(mb, ycen, zc, pitch=0.0):
    """streamlined 'cobra head' LED luminaire along Y, centred on (0, ycen, zc)"""
    prof = rounded_poly([(-0.15, -0.045), (0.15, -0.045), (0.15, 0.055), (-0.15, 0.055)], 0.035, 3)
    n = 8
    L = 0.80
    path = [Vector((0, ycen - L / 2 + L * i / (n - 1), zc + (i / (n - 1) - 0.5) * L * sin(radians(pitch)))) for i in range(n)]
    mb.sweep(prof, path, 'M_RS_PaintGrey', True, True, up=(0, 0, 1), scale=lambda t: (1.0 - 0.28 * t ** 1.6, 1.0 - 0.12 * t), cap0=True, cap1=True)
    # underside lens
    pl = Plane((0, ycen, zc - 0.043), (0, 1, 0), (1, 0, 0))
    lens = rounded_poly([(-0.30, -0.1), (0.30, -0.1), (0.30, 0.1), (-0.30, 0.1)], 0.04, 3)
    mb.prism(pl, lens, 0.0, 0.007, 'M_RS_LampLens', 'M_RS_PaintGrey', 'M_RS_PaintGrey')
    # cooling fins + photocell on top
    for x in (-0.07, 0.0, 0.07):
        mb.box((x - 0.006, ycen - 0.22, zc + 0.052), (x + 0.006, ycen + 0.22, zc + 0.085), 'M_RS_PaintGrey')
    mb.cyl((0.0, ycen - 0.30, zc + 0.05), (0.0, ycen - 0.30, zc + 0.11), 0.034, 0.034, 'M_RS_PaintBlack', seg=10, smooth=True)

@asset('rs_streetlamp_8m', 'Street lamp 8 m curved arm LED', x=215.0, ext=(-0.6, 0.6), group='lighting', budget=3200, collision='box',
       pivot='ground_base', tags=['all_biomes', 'road_verge', 'village', 'highway'], scale=(1.0, 1.0),
       usage='Place on the verge every 30-45 m. Arm reaches 2.5 m towards +Y (the road). LED head lens faces down; emissive material M_RS_LampLens; light socket in JSON.')
def b_streetlamp(mb):
    seg = 14
    H = 7.25
    # concrete plinth + anchor nuts
    mb.cyl((0, 0, 0), (0, 0, 0.07), 0.26, 0.26, 'M_RS_Concrete', seg=16, smooth=False)
    for a in (45, 135, 225, 315):
        hexbolt(mb, (0.215 * cos(radians(a)), 0.215 * sin(radians(a)), 0.07), (0, 0, 1), r=0.016, ln=0.03, wash=0.03)
    # base cover + pole (one lathe with slip-joint collars)
    def rp(z):
        return _lerp(0.1, 0.052, (z - 0.74) / (H - 0.74))
    rz = [(0.19, 0.07), (0.19, 0.10), (0.162, 0.16), (0.150, 0.58), (0.162, 0.60), (0.162, 0.66), (0.104, 0.74)]
    for zj in (3.3, 5.5):
        rz += [(rp(zj), zj), (rp(zj) + 0.007, zj), (rp(zj) + 0.007, zj + 0.14), (rp(zj + 0.14), zj + 0.14)]
    rz += [(rp(H), H), (0.056, H + 0.03), (0.0, H + 0.045)]
    # rebuild monotonically: insert rows between joints
    pts = []
    last = None
    for (r, z) in rz:
        pts.append((r, z))
    # smooth flags per row for the final list (rows = len-1): mark steps (equal z or big r jump) as flat
    flags = []
    for i in range(len(pts) - 1):
        dz = pts[i + 1][1] - pts[i][1]
        dr = abs(pts[i + 1][0] - pts[i][0])
        flags.append(not (dz < 0.02 or dr > 0.03))
    mb.lathe(pts, 'M_RS_GalvSteel', seg=seg, smooth=True, row_smooth=flags)
    # hatch door on the +X side of the base cover
    mb.box((0.143, -0.065, 0.2), (0.162, 0.065, 0.52), 'M_RS_GalvDark', c=0.004)
    mb.box((0.161, 0.03, 0.34), (0.168, 0.05, 0.38), 'M_RS_PaintBlack')
    # curved arm
    arm = bezier((0, 0, 7.0), (0, 0.0, 8.15), (0, 0.9, 8.3), (0, 1.85, 7.97), 18)
    mb.tube(arm, 0.046, 'M_RS_GalvSteel', seg=10, smooth=True, scale=lambda t: 1.0 - 0.32 * t)
    ap = arm[10]
    brace = bezier((0, 0.045, 6.15), (0, 0.45, 6.5), (0, ap.y - 0.25, ap.z - 0.55), (0, ap.y, ap.z - 0.03), 12)
    mb.tube(brace, 0.021, 'M_RS_GalvSteel', seg=8, smooth=True)
    mb.cyl((0, 0.0, 6.12), (0, 0.075, 6.18), 0.05, 0.05, 'M_RS_GalvDark', seg=10, smooth=True)
    mb.cyl((0, 1.78, 7.935), (0, 1.9, 7.94), 0.04, 0.04, 'M_RS_GalvDark', seg=10, smooth=True)
    _lamp_head(mb, 2.12, 7.94, pitch=-3.0)
    mb.sockets['light'] = (0.0, 2.15, 7.88)
    mb.sockets['arm_tip'] = (0.0, 1.9, 7.95)
    mb.hull_cyl((0, 0, 0), (0, 0, 7.3), 0.17, 8)
    mb.hull_box((-0.17, 1.7, 7.8), (0.17, 2.55, 8.08))
    return dict(height=8.3, arm_reach=2.55, light_height=7.9, pole_height=7.25)

@asset('rs_gantry_lamp', 'Highway gantry lamp 10 m (cantilever truss, 3 flood heads)', x=224.0, ext=(-0.6, 0.6), group='lighting', budget=4200, collision='box',
       pivot='ground_base', tags=['highway', 'interchange', 'tunnel_approach'], scale=(1.0, 1.0),
       usage='Highway interchanges / tunnel approaches. Truss boom reaches 5.7 m towards +Y over the carriageway; three flood heads face down (emissive M_RS_LampLens).')
def b_gantry_lamp(mb):
    H = 9.9
    # base plate, bolts, gussets
    mb.box((-0.36, -0.36, 0.0), (0.36, 0.36, 0.05), 'M_RS_GalvDark', c=0.006)
    for sx in (-1, 1):
        for sy in (-1, 1):
            hexbolt(mb, (sx * 0.29, sy * 0.29, 0.05), (0, 0, 1), r=0.022, ln=0.045, wash=0.045)
    # tapered pole
    def rp(z):
        return _lerp(0.185, 0.095, z / H)
    rz = [(0.205, 0.05), (0.205, 0.12), (0.185, 0.2)]
    z = 0.2
    while z < H - 0.05:
        z = min(H, z + 1.1)
        rz.append((rp(z), z))
    rz += [(0.1, H + 0.04), (0.0, H + 0.1)]
    mb.lathe(rz, 'M_RS_GalvSteel', seg=14, smooth=True)
    # service door + cabinet ring
    mb.box((0.17, -0.1, 0.45), (0.19, 0.1, 1.15), 'M_RS_GalvDark', c=0.006)
    mb.box((0.188, 0.04, 0.75), (0.196, 0.075, 0.85), 'M_RS_PaintBlack')
    # cantilever truss boom (to +Y)
    yb0, yb1 = 0.1, 5.7
    zb0, zb1 = 9.05, 9.2      # bottom chord (slight rise)
    zt0, zt1 = 9.75, 9.38     # top chord (tapers down)
    n = 10
    ys = [yb0 + (yb1 - yb0) * i / n for i in range(n + 1)]
    def zb(y): return zb0 + (zb1 - zb0) * (y - yb0) / (yb1 - yb0)
    def zt(y): return zt0 + (zt1 - zt0) * (y - yb0) / (yb1 - yb0)
    mb.tube([Vector((0, yb0, zb(yb0))), Vector((0, yb1, zb(yb1)))], 0.045, 'M_RS_GalvSteel', seg=8, smooth=True)
    mb.tube([Vector((0, yb0, zt(yb0))), Vector((0, yb1, zt(yb1)))], 0.045, 'M_RS_GalvSteel', seg=8, smooth=True)
    for i in range(n):
        ya, yb = ys[i], ys[i + 1]
        if i % 2 == 0:
            a = Vector((0, ya, zb(ya))); b = Vector((0, yb, zt(yb)))
        else:
            a = Vector((0, ya, zt(ya))); b = Vector((0, yb, zb(yb)))
        mb.tube([a, b], 0.022, 'M_RS_GalvSteel', seg=6, smooth=True)
        mb.tube([Vector((0, ya, zb(ya))), Vector((0, ya, zt(ya)))], 0.02, 'M_RS_GalvSteel', seg=6, smooth=True)
    mb.tube([Vector((0, yb1, zb(yb1))), Vector((0, yb1, zt(yb1)))], 0.025, 'M_RS_GalvSteel', seg=6, smooth=True)
    # attachment plate on the pole
    mb.box((-0.14, 0.02, 8.95), (0.14, 0.16, 9.85), 'M_RS_GalvDark', c=0.008)
    # three flood heads hanging from the bottom chord
    for y in (1.35, 3.25, 5.15):
        zc = zb(y) - 0.42
        mb.tube([Vector((0, y, zb(y))), Vector((0, y, zc + 0.08))], 0.02, 'M_RS_GalvDark', seg=8, smooth=True)
        mb.obox((0, y, zc), (0.42, 0.78, 0.2), 'M_RS_PaintGrey', (-9.0, 0, 0), c=0.03)
        mb.obox((0, y, zc - 0.095), (0.34, 0.68, 0.012), 'M_RS_LampLens', (-9.0, 0, 0))
        mb.box((-0.14, y - 0.2, zc + 0.1), (0.14, y + 0.2, zc + 0.16), 'M_RS_PaintGrey', c=0.01)
        mb.sockets['light_%d' % int(y)] = (0.0, y, zc - 0.12)
    # pole cap + aircraft-warning-style top lamp housing
    mb.hull_cyl((0, 0, 0), (0, 0, H), 0.2, 8)
    mb.hull_box((-0.1, 0.1, 8.95), (0.1, 5.8, 9.8))
    mb.hull_box((-0.25, 0.9, 8.5), (0.25, 5.6, 9.05))
    return dict(height=H + 0.1, boom_reach=5.7, heads=3)

# ----------------------------------------------------------------------------------------------------------------------
# utility pole 9 m + wire span
# ----------------------------------------------------------------------------------------------------------------------
_INS_PROFILE = [(0.03, 0.0), (0.03, 0.03), (0.068, 0.04), (0.07, 0.055), (0.03, 0.075), (0.029, 0.085), (0.058, 0.095), (0.06, 0.108),
                (0.028, 0.125), (0.027, 0.145), (0.044, 0.155), (0.044, 0.178), (0.0, 0.184)]

def _insulator(mb, x, y, z):
    mb.cyl((x, y, z - 0.07), (x, y, z + 0.004), 0.012, 0.012, 'M_RS_GalvDark', seg=8, smooth=True)
    rz = [(r, z + dz) for (r, dz) in _INS_PROFILE]
    flags = [not (abs(rz[i + 1][1] - rz[i][1]) < 0.012) for i in range(len(rz) - 1)]
    mb.lathe(rz, 'M_RS_Insulator', seg=10, center=(x, y), smooth=True, row_smooth=[True] * len(flags))

@asset('rs_utility_pole_9m', 'Wooden utility pole 9 m with crossarm and insulators', x=232.0, ext=(-1.4, 1.4), group='utility', budget=3000, collision='box',
       pivot='ground_base', tags=['rural', 'village', 'all_biomes', 'power_line'], scale=(0.95, 1.1),
       usage='Place every 30 m along rural roads; crossarm along Y, wires run along +-X. Attach rs_utility_wire_span_30m at the insulator tips listed in sockets.')
def b_utility_pole(mb):
    rng = mb.rng
    H = 9.0
    # wooden pole with slight irregularity, tar-black butt
    rz = []
    z = 0.0
    while z < H + 0.001:
        r = _lerp(0.165, 0.108, z / H) + rng.uniform(-0.004, 0.004)
        rz.append((r, z))
        z += 0.5
    rz[0] = (rz[0][0], 0.0)
    rz += [(0.1, H + 0.03), (0.06, H + 0.07), (0.0, H + 0.08)]
    mb.lathe(rz, 'M_RS_Wood', seg=12, smooth=True, col=mb.tint(0.05, (0.92, 0.85, 0.78)))
    mb.lathe([(0.172, 0.0), (0.171, 1.2), (0.168, 1.25), (0.0, 1.25)], 'M_RS_PaintBlack', seg=12, smooth=True, cap0=True, row_smooth=[True, False, False])
    # crossarm (wood) + two diagonal braces + through bolts
    zc = 8.4
    mb.box((-0.06, -1.2, zc - 0.07), (0.06, 1.2, zc + 0.07), 'M_RS_Wood', c=0.01, col=mb.tint(0.1))
    for sy in (-1, 1):
        mb.bar((0.0, sy * 0.12, 7.78), (0.0, sy * 0.74, zc - 0.05), 0.07, 0.05, 'M_RS_Wood', c=0.006, col=mb.tint(0.1), roll=pi / 2)
    hexbolt(mb, (0.06, 0.0, zc), (1, 0, 0), r=0.02, ln=0.03, wash=0.05)
    hexbolt(mb, (-0.06, 0.0, zc), (-1, 0, 0), r=0.02, ln=0.03, wash=0.05)
    # insulators: two on the crossarm, one on the pole top
    _insulator(mb, 0.0, -0.9, zc + 0.07)
    _insulator(mb, 0.0, 0.9, zc + 0.07)
    mb.cyl((0, 0, H + 0.02), (0, 0, H + 0.1), 0.03, 0.03, 'M_RS_GalvDark', seg=8, smooth=True)
    _insulator(mb, 0.0, 0.0, H + 0.1)
    # climbing steps, ground wire, tag plate
    for i, z in enumerate((2.4, 3.3, 4.2, 5.1, 6.0)):
        a = radians(20 + 180 * (i % 2))
        mb.cyl((0.12 * cos(a) * 0.9, 0.12 * sin(a) * 0.9, z), (0.19 * cos(a), 0.19 * sin(a), z - 0.02), 0.012, 0.012, 'M_RS_GalvDark', seg=6, smooth=True)
    mb.tube([Vector((0.0, -0.152, 0.2)), Vector((0.0, -0.14, 4.5)), Vector((0.0, -0.126, 8.7))], 0.007, 'M_RS_GalvSteel', seg=5, smooth=True)
    mb.box((0.138, -0.045, 2.0), (0.146, 0.045, 2.14), 'M_RS_GalvSteel')
    z_in = zc + 0.07 + 0.184
    mb.sockets['wire_L'] = (0.0, -0.9, z_in)
    mb.sockets['wire_R'] = (0.0, 0.9, z_in)
    mb.sockets['wire_top'] = (0.0, 0.0, H + 0.1 + 0.184)
    mb.hull_cyl((0, 0, 0), (0, 0, H), 0.15, 8)
    mb.hull_box((-0.07, -1.2, 8.3), (0.07, 1.2, 8.5))
    return dict(height=H + 0.3, crossarm_height=zc, span_to_next=30.0)

POLE_WIRE_Z = 8.4 + 0.07 + 0.184          # insulator-top height on the crossarm of rs_utility_pole_9m (= 8.654 m)

def _wire_span(mb, sag):
    L = 30.0
    n = 30
    for (y, dz) in ((-0.9, 0.0), (0.9, 0.0), (0.0, 0.63)):
        path = []
        for i in range(n + 1):
            t = i / n
            path.append(Vector((L * t, y, dz - 4 * sag * t * (1 - t))))
        mb.tube(path, 0.0085, 'M_RS_Wire', seg=5, smooth=True, caps=True)
    mb.sockets['span_end'] = (L, 0.0, 0.0)
    return dict(length=L, sag=sag, place_at_pole_base_offset=[0.0, 0.0, round(POLE_WIRE_Z, 3)], next_pole_offset=[30.0, 0.0, 0.0],
                parent_pole='rs_utility_pole_9m', conductors_y=[-0.9, 0.0, 0.9], pole_top_conductor_dz=0.63)

_WIRE_USAGE = ('Origin = the pole centreline at crossarm-insulator-top height, i.e. spawn it at pole_base + (0, 0, 8.654) (sidecar extra.place_at_pole_base_offset); '
               'the conductors then start exactly on the insulator tops of rs_utility_pole_9m (y = -0.9 / +0.9 on the crossarm, y = 0 and +0.63 m on the pole-top insulator) '
               'and end 30 m along +X (next pole at +30 m, extra.next_pole_offset). Sag %s m. Rotate about Z to follow the line; scale X 0.9-1.1 re-aims it (sag scales with it). No collision.')

@asset('rs_utility_wire_span_30m', 'Utility wire span 30 m (3 catenary conductors)', x=242.0, ext=(0.0, 30.0), group='utility', budget=1600, collision='none',
       pivot='attach_point', tags=['rural', 'village', 'power_line'], scale=(1.0, 1.0), nanite=True, usage=_WIRE_USAGE % '0.70')
def b_wire_span(mb):
    return _wire_span(mb, 0.70)

@asset('rs_utility_wire_span_30m_taut', 'Utility wire span 30 m, taut (0.40 m sag)', x=400.0, ext=(0.0, 30.0), group='utility', budget=1600, collision='none',
       pivot='attach_point', tags=['rural', 'village', 'power_line'], scale=(1.0, 1.0), nanite=True, usage=_WIRE_USAGE % '0.40' + ' Variant for cold / short spans.')
def b_wire_span_taut(mb):
    return _wire_span(mb, 0.40)

@asset('rs_utility_wire_span_30m_slack', 'Utility wire span 30 m, slack (1.05 m sag)', x=436.0, ext=(0.0, 30.0), group='utility', budget=1600, collision='none',
       pivot='attach_point', tags=['rural', 'village', 'power_line'], scale=(1.0, 1.0), nanite=True, usage=_WIRE_USAGE % '1.05' + ' Variant for warm / long spans.')
def b_wire_span_slack(mb):
    return _wire_span(mb, 1.05)
