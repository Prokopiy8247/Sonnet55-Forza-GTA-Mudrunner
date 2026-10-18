"""
traffic06_pickup.py - idempotent build of the traffic work pickup (5.0 m, older single cab, slab fenders, open wooden-floor bed with
tailgate, headache rack, chrome bumpers, patchy rust).  Deliberately different from the modern double-cab player car09.

Run in the verified Blender MCP session (localhost:9889):
    TRAFFIC_STAGE = "geometry"   # "geometry" | "uv_a" | "uv_b" | "uv_wheels" | "validate" | "export"
    exec(compile(open(r"<project>/Tools/blender/traffic/traffic06_pickup.py", encoding="utf8").read(), "pickup", "exec"), globals())
Car space: +X forward, +Y left, +Z up, origin on the ground under the middle of the wheelbase.  Staged at (84, 30, 0).
"""
import os
import math
import time
import bpy
import bmesh
from mathutils import Vector, Matrix

_PROJECT = os.path.dirname(bpy.data.filepath)
for _f in ("carkit.py", "carkit_ext_traffic.py", "traffic_export.py"):
    _p = os.path.join(_PROJECT, "Tools", "blender", "lib", _f)
    exec(compile(open(_p, encoding="utf8").read(), _p, "exec"), globals())

VID = "traffic06_pickup"
INDEX = 6
STAGE = globals().get("TRAFFIC_STAGE", "geometry")

P = dict(L=5.00, W=1.86, H=1.64, wheelbase=3.10, track_f=1.52, track_r=1.50, R=0.37, WW=0.235, ride=0.30, x_front=2.40, rim_r=0.2032,
         x_cab_b=-0.62, x_bed_b=-2.40)
XF, XR = 1.55, -1.55
RAY_L, RAY_R, RAY_F, RAY_B, RAY_T = (0, -1, 0), (0, 1, 0), (-1, 0, 0), (1, 0, 0), (0, 0, -1)
PAINT_VARIANTS = paint_variants(("Faded rust orange", "#9a4a22", "#1d1d1b", 0.0, 0.62),
                                ("Sun-bleached green", "#6f7f52", "#cfc9b8", 0.0, 0.58),
                                ("Old cream", "#d6cfb4", "#6b3a22", 0.0, 0.52))


def curves():
    ztk = fillet_profile([(-0.66, 1.60), (0.24, 1.62), (0.60, 1.18), (1.5, 1.14), (2.50, 1.06)], [0, 0.14, 0.30, 4.0, 0], step=0.01)
    ztc = as_curve(ztk)
    zs = lambda x: min(1.12, ztc(x) - 0.07)
    hw = lambda x: 0.89 + 0.035 * smoothstep(0.35, 0.65, x) - 0.05 * smoothstep(1.9, 2.4, x)
    hwt = lambda x: 0.80 + 0.075 * smoothstep(0.35, 0.75, x)
    zb = as_curve([(-0.7, 0.46), (0.5, 0.46), (1.0, 0.40), (2.0, 0.40), (2.4, 0.44)])
    return dict(hw=hw, hwt=hwt, zt=ztk, zs=zs, zb=zb, hwb=lambda x: hw(x) - 0.03, zw=lambda x: zb(x) + 0.10, cs=0.05,
                ct=lambda x: 0.12 - 0.07 * smoothstep(0.3, 0.9, x), cb=0.06, cw=0.03, cam=0.0)


def build_front_cab(v):
    cv = curves()
    xf, xb = P['x_front'], P['x_cab_b']
    xs = merge_stations([end_stations(xf, 0.05, 4), end_stations(xb, 0.05, 3, True), [xf, xb], frange(-0.5, 0.9, 0.1), [0.22, 0.24, 0.6],
                         frange(1.0, 2.2, 0.3)], min_gap=0.03)
    shell = sect_loft(cv, xs, ncor=dict(A=1, B=1, C=2, D=3), r0=0.05, r1=0.05, smooth_passes=2, smooth_strength=0.5)
    bm = shell.bm
    check_manifold(bm, 'shell')
    lap(v, "shell %d stations x %d pts" % (len(xs), shell.ring_pts))
    split_planes(bm, [((0, 0, 0.55), (0, 0, 1))])
    for f in bm.faces:
        c = f.calc_center_median()
        m = 'M_Paint'
        if f.normal.z < -0.6:
            m = 'M_TrimBlack'
        elif c.z < 0.55:
            m = 'M_Traffic_Rust'                      # rusty rocker panels / lower fender edges
        f.material_index = mi(m)
    surf = Surface(bm)
    cut = []
    for (x, sd) in ((XF, 1), (XF, -1)):
        cut.append(wheel_arch_cutter(x, P['R'], P['R'] + 0.055, sd, inner_y=0.40, outer_y=1.3, segments=28, mat='M_TrimBlack'))
    xs_void = [0.50 - 0.1 * i for i in range(0, 11)] + [-0.56]
    cut.append(inner_void(cv, xs_void, 0.04, 0.60, mat_wall='M_TrimGrey', mat_floor='M_TrimBlack'))
    # windscreen: plane through the cowl (0.60, 1.18) and the roof edge (0.24, 1.62)
    fr_ws = Frame(Vector((0.42, 0.0, 1.40)), Vector((0.44, 0.0, 0.36)), side_like=False)
    ws_out = round_poly(fr_ws.outline_world([(-0.72, 1.27), (0.72, 1.27), (0.68, 1.55), (-0.68, 1.55)]), 0.05, 3)
    cut.append(win_cutter(fr_ws, ws_out, d_in=-0.25, d_out=0.10))
    fr_rw = Frame(Vector((P['x_cab_b'], 0.0, 1.40)), Vector((-1.0, 0.0, 0.0)), side_like=False)
    rw_out = round_poly(fr_rw.outline_world([(-0.42, 1.24), (0.42, 1.24), (0.40, 1.52), (-0.40, 1.52)]), 0.05, 3)
    cut.append(win_cutter(fr_rw, rw_out, d_in=-0.25, d_out=0.10))
    side_glass = []
    for sd in (1, -1):
        fr = side_frame(-0.05, 0.89, 1.12, 0.80, 1.62, side=sd)
        out = round_poly(fr.outline_world([(0.42, 1.22), (-0.50, 1.22), (-0.50, 1.52), (0.34, 1.54)]), [0.04, 0.04, 0.04, 0.10], 3)
        cut.append(win_cutter(fr, out, d_in=-0.25, d_out=0.10))
        side_glass.append((fr, out))
    # panel seams: door, cowl / fender joint, hood outline
    for sd, ray in ((1, RAY_L), (-1, RAY_R)):
        door = [Vector((0.48, sd * 1.5, 0.52)), Vector((0.48, sd * 1.5, 1.18)), Vector((-0.54, sd * 1.5, 1.18)), Vector((-0.54, sd * 1.5, 0.52)),
                Vector((0.48, sd * 1.5, 0.52))]
        g = dir_groove(surf, door, ray, closed=False, step=0.06, name='door')
        if g is not None:
            cut.append(g)
        g = dir_groove(surf, [Vector((0.58, sd * 1.5, 0.46)), Vector((0.58, sd * 1.5, 1.08))], ray, closed=False, step=0.06, name='cowl joint')
        if g is not None:
            cut.append(g)
    hood = [Vector((0.64, 0.84, 0)), Vector((2.30, 0.84, 0)), Vector((2.36, 0.78, 0)), Vector((2.36, -0.78, 0)), Vector((2.30, -0.84, 0)),
            Vector((0.64, -0.84, 0))]
    for g in (dir_groove(surf, hood, RAY_T, closed=False, step=0.06, name='hood outline'),
              dir_groove(surf, [Vector((0.64, 0.0, 0)), Vector((2.34, 0.0, 0))], RAY_T, closed=False, step=0.1, name='hood centre')):
        if g is not None:
            cut.append(g)
    # grille opening + round headlamps + indicators
    gp = pocket_cutter(surf, outline_rrect(0.84, 0.30, 0.03, 3), Vector((2.6, 0.0, 0.80)), RAY_F, depth=0.07, taper=0.97, mat='M_TrimBlack',
                       floor_follows=False)
    if gp is not None:
        cut.append(gp)
    lenses = []
    for sd in (1, -1):
        cu, le = lamp_unit(surf, Vector((2.6, sd * 0.70, 0.80)), RAY_F, outline_ellipse(0.10, 0.10, 18), depth=0.06, lens_inset=0.004, lens_scale=0.92,
                           lens_mat='M_Headlight', housing_mat='M_TrimBlack', floor_mat='M_Chrome', taper=0.9)
        if cu is not None:
            cut.append(cu)
            lenses.append(le)
    cs_, ls_ = lens_pair(surf, (2.6, 0.70, 0.60), RAY_F, outline_rrect(0.15, 0.07, 0.02, 3), 0.04, 'M_Indicator', lens_scale=0.95)
    cut += cs_
    lenses += ls_
    body = bm_boolean(bm, cut)
    lap(v, "front+cab boolean: %d tris" % tri_count(body))
    for l in lenses:
        put(body, l)
    # chrome grille bars + bezels
    g = grille_mesh(outline_rrect(0.80, 0.26, 0.03, 3), kind='bars', pitch=0.05, bar=0.016, depth=0.03, frame=0.014, mat='M_Chrome', frame_mat='M_Chrome')
    hit = surf.hit(Vector((2.6, 0.0, 0.80)), RAY_F)
    bmesh.ops.transform(g, matrix=Matrix.Translation(Vector((hit[0].x - 0.03, 0.0, 0.80))), verts=g.verts)
    put(body, g)
    for sd in (1, -1):
        hh = surf.hit(Vector((2.6, sd * 0.70, 0.80)), RAY_F)
        put(body, prim_torus(R=0.108, r=0.012, seg_major=20, seg_minor=6, axis='X', center=(hh[0].x + 0.006, sd * 0.70, 0.80), mat='M_Chrome'))
    # rust / patina patches (irregular, hugging the skin)
    for k, (c, ray, size) in enumerate([((0.05, 1.5, 0.62), RAY_L, 0.17), ((-0.40, -1.5, 0.78), RAY_R, 0.13), ((1.1, 1.5, 0.66), RAY_L, 0.16),
                                        ((1.95, -1.5, 0.82), RAY_R, 0.18), ((0.30, 1.5, 1.05), RAY_L, 0.08), ((1.6, 0.4, 0), RAY_T, 0.12),
                                        ((0.9, -0.6, 0), RAY_T, 0.10), ((-0.20, 0.0, 0), RAY_T, 0.18), ((1.25, -1.5, 0.95), RAY_R, 0.09)]):
        rp = rust_patch(surf, c, ray, size, seed=11 + k, squash=(1.25, 1.0))
        if rp is not None:
            put(body, rp)
    # chrome front bumper + overriders, plate, hood latch, mirrors, door handles, wipers, cab lamps, arch lips
    put(body, box(0.13, 1.92, 0.15, (2.435, 0.0, 0.43), 'M_Chrome', bevel=0.045, seg=2))
    for sd in (1, -1):
        put(body, box(0.16, 0.09, 0.30, (2.45, sd * 0.62, 0.48), 'M_Chrome', bevel=0.03, seg=2))
        put(body, box(0.08, 0.10, 0.10, (2.50, sd * 0.40, 0.43), 'M_Chrome', bevel=0.02, seg=1))
    put(body, plate_quad(2.50, 0.0, 0.42, 0.46, 0.10))
    for sd, ray in ((1, RAY_L), (-1, RAY_R)):
        h = door_handle(surf, -0.38, 0.98, ray, length=0.12, width=0.03, height=0.02, mat='M_Chrome')
        if h is not None:
            put(body, h)
        am = arch_moulding(surf, XF, P['R'], P['R'] + 0.075, ray, a0=8, a1=172, n=16, width=0.05, height=0.016, mat='M_Traffic_Rust')
        if am is not None:
            put(body, am)
    mir = bmesh.new()
    put(mir, tube([Vector((0.40, 0.84, 1.32)), Vector((0.30, 1.00, 1.34))], 0.011, 'M_Chrome', sides=6))
    put(mir, tube([Vector((0.40, 0.84, 1.14)), Vector((0.30, 1.00, 1.20))], 0.011, 'M_Chrome', sides=6))
    put(mir, box(0.05, 0.14, 0.34, (0.28, 1.06, 1.27), 'M_TrimBlack', bevel=0.01, seg=1))
    put(mir, box(0.004, 0.12, 0.30, (0.253, 1.06, 1.27), 'M_Chrome'))
    put_pair(body, mir)
    for sd in (1, -1):
        put(body, tube([fr_ws.pt(sd * 0.60, -0.18, 0.015), fr_ws.pt(sd * 0.05, -0.12, 0.015)], 0.007, 'M_TrimBlack', sides=5))
    for yy in (-0.22, 0.0, 0.22):                                      # amber cab lamps
        put(body, box(0.06, 0.12, 0.05, (0.24, yy, 1.665), 'M_Indicator', bevel=0.012))
    glass = bmesh.new()
    put(glass, win_glass(fr_ws, ws_out))
    put(glass, win_glass(fr_rw, rw_out))
    for fr, out in side_glass:
        put(glass, win_glass(fr, out))
    return body, glass, (fr_ws,)


def build_bed():
    """open bed: side walls with wheel arches (outer skin down to the rocker), floor planks, front wall, wheel houses, tailgate, lamps"""
    bed = bmesh.new()
    x0, x1 = P['x_bed_b'] + 0.08, P['x_cab_b'] - 0.02                         # wall extent (tailgate closes the rear)
    xc, L = (x0 + x1) / 2, x1 - x0
    for sd in (1, -1):
        wall = prim_box((L, 0.07, 0.86), (xc, sd * 0.885, 0.97), mat='M_Paint', bevel=0.022, segments=2)
        bmesh.ops.bisect_plane(wall, geom=list(wall.verts) + list(wall.edges) + list(wall.faces), dist=1e-6, plane_co=(0, 0, 0.66), plane_no=(0, 0, 1))
        wall.normal_update()
        for f in wall.faces:
            c = f.calc_center_median()
            if abs(f.normal.y) > 0.7:
                inside = (f.normal.y * sd) < 0
                f.material_index = mi('M_Traffic_Rust' if inside else ('M_Traffic_Rust' if c.z < 0.66 else 'M_Paint'))
            else:
                f.material_index = mi('M_Paint')
        wall = bm_boolean(wall, [wheel_arch_cutter(XR, P['R'], P['R'] + 0.06, sd, inner_y=0.70, outer_y=1.3, segments=28, mat='M_TrimBlack')])
        put(bed, wall)
        put(bed, box(0.85, 0.30, 0.30, (XR, sd * 0.64, 1.10), 'M_Paint', bevel=0.05, seg=2))             # wheel house
        for xx in (-0.95, -1.55, -2.15):                                                                  # stake pockets on the rail
            put(bed, box(0.07, 0.04, 0.05, (xx, sd * 0.885, 1.405), 'M_TrimBlack'))
        put(bed, box(0.05, 0.05, 0.28, (-2.40 + 0.02, sd * 0.90, 1.15), 'M_Taillight', bevel=0.012))     # tail lamp lens on the wall end
        put(bed, box(0.04, 0.05, 0.06, (-2.40 + 0.02, sd * 0.90, 0.92), 'M_Indicator', bevel=0.01))
    # floor planks + frame
    n = 9
    for i in range(n):
        yy = -0.80 + 1.60 * (i + 0.5) / n
        put(bed, box(1.80, 1.60 / n - 0.012, 0.04, (xc, yy, 0.93), 'M_Traffic_Wood'))
    put(bed, box_span(P['x_bed_b'] + 0.1, x1, -0.86, 0.86, 0.80, 0.91, 'M_TrimBlack'))
    # front wall + headache rack
    put(bed, box(0.06, 1.80, 0.52, (P['x_cab_b'] - 0.04, 0.0, 1.18), 'M_Paint', bevel=0.02, seg=1))
    for yy in (-0.82, 0.82):
        put(bed, bar_z(1.42, 2.02, P['x_cab_b'] - 0.12, yy, 0.025, 'M_Paint2', sides=8))
    put(bed, bar_y(-0.82, 0.82, P['x_cab_b'] - 0.12, 2.02, 0.025, 'M_Paint2', sides=8))
    put(bed, bar_y(-0.82, 0.82, P['x_cab_b'] - 0.12, 1.72, 0.02, 'M_Paint2', sides=6))
    for yy in (-0.45, 0.0, 0.45):
        put(bed, bar_z(1.42, 2.02, P['x_cab_b'] - 0.12, yy, 0.016, 'M_Paint2', sides=6))
    # tailgate with inset panel, hinges, latch
    xt = P['x_bed_b'] + 0.03
    put(bed, box(0.06, 1.72, 0.48, (xt, 0.0, 1.14), 'M_Paint', bevel=0.02, seg=2))
    put(bed, box(0.012, 1.40, 0.28, (xt - 0.035, 0.0, 1.14), 'M_Traffic_Rust', bevel=0.01))
    put(bed, box(0.035, 0.34, 0.035, (xt - 0.04, 0.0, 1.32), 'M_Chrome', bevel=0.01))
    for sd in (1, -1):
        for zz in (1.02, 1.28):
            put(bed, cyl(0.016, 0.07, (xt + 0.02, sd * 0.88, zz), 'Y', 'M_TrimBlack', segs=8))
    # rear chrome bumper + plate + reversing lamp
    put(bed, box(0.12, 1.84, 0.14, (P['x_bed_b'] - 0.055, 0.0, 0.50), 'M_Chrome', bevel=0.04, seg=2))
    put(bed, plate_quad(P['x_bed_b'] - 0.002, 0.0, 0.88, 0.40, 0.10))
    put(bed, box(0.04, 0.12, 0.05, (P['x_bed_b'] + 0.0, 0.62, 0.62), 'M_Reverse', bevel=0.01))
    return bed


def build_chassis():
    ch = bmesh.new()
    for sd in (1, -1):
        put(ch, box_span(-2.30, 2.05, sd * 0.48 - 0.05, sd * 0.48 + 0.05, 0.48, 0.64, 'M_TrimBlack'))
        for xx in (XF, XR):
            put(ch, box(0.90, 0.06, 0.05, (xx, sd * 0.56, 0.62), 'M_TrimBlack'))                      # leaf springs
            put(ch, box(0.12, 0.10, 0.14, (xx, sd * 0.56, 0.52), 'M_TrimGrey'))
    for x in (1.8, 0.4, -0.8, -2.0):
        put(ch, box_span(x - 0.05, x + 0.05, -0.48, 0.48, 0.52, 0.62, 'M_TrimBlack'))
    put(ch, bar_y(-0.68, 0.68, XF, P['R'], 0.04, 'M_TrimBlack', sides=8))
    put(ch, bar_y(-0.68, 0.68, XR, P['R'], 0.05, 'M_TrimBlack', sides=8))
    put(ch, prim_sphere(0.15, u=10, v=6, center=(XR, 0.0, P['R']), mat='M_TrimGrey', scale=(1.0, 1.1, 0.9)))
    put(ch, bar_x(1.1, -1.50, 0.0, 0.52, 0.035, 'M_TrimGrey', sides=8))                                 # propshaft
    put(ch, cyl(0.17, 0.50, (-1.15, -0.62, 0.62), 'Y', 'M_TrimGrey', segs=12))                          # fuel tank
    put(ch, cyl(0.075, 0.70, (-1.30, 0.30, 0.50), 'X', 'M_TrimGrey', segs=10))                          # muffler
    put(ch, tube([Vector((0.2, 0.30, 0.50)), Vector((-0.9, 0.30, 0.50))], 0.025, 'M_TrimGrey', sides=6))
    put(ch, tube([Vector((-1.65, 0.30, 0.50)), Vector((-2.44, 0.30, 0.46))], 0.03, 'M_TrimGrey', sides=8))
    for sd in (1, -1):
        put(ch, box(0.015, 0.34, 0.30, (XR - 0.60, sd * 0.78, 0.42), 'M_Rubber'))                       # mud flaps
        put(ch, box(0.015, 0.30, 0.28, (XF - 0.55, sd * 0.80, 0.40), 'M_Rubber'))
    # engine bay hint under the hood: radiator + block (seen through the grille)
    put(ch, box(0.10, 0.80, 0.34, (2.18, 0.0, 0.80), 'M_TrimBlack'))
    put(ch, box(0.70, 0.55, 0.40, (1.60, 0.0, 0.82), 'M_TrimGrey', bevel=0.03))
    return ch


def build():
    v = new_vehicle(VID, INDEX, "Work Pickup", wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=P['track_r'],
                    wheel_radius_front=P['R'], wheel_radius_rear=P['R'], wheel_width_front=P['WW'], wheel_width_rear=P['WW'],
                    ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], drivetrain='RWD')
    cab, glass, (fr_ws,) = build_front_cab(v)
    bed = build_bed()
    ch = build_chassis()
    lap(v, "cab %d, bed %d, chassis %d tris" % (tri_count(cab), tri_count(bed), tri_count(ch)))
    body = bmesh.new()
    for part in (cab, bed, ch):
        put(body, part)
    it = bmesh.new()
    put(it, seat_block(-0.08, 0.0, 0.90, w=1.30, depth=0.50, back_h=0.62, headrest=False))
    put(it, driver_figure(-0.08, 0.40, 0.90, scale=0.97))
    put(it, steering_wheel(0.28, 0.40, 1.08, r=0.19, tilt=34.0))
    put(it, box(0.30, 1.70, 0.38, (0.46, 0.0, 0.82), 'M_IntDash', bevel=0.04, seg=2))
    put(it, box(0.22, 0.50, 0.12, (0.40, 0.40, 1.04), 'M_IntDash', bevel=0.03, seg=1))
    put(it, tube([Vector((0.18, 0.0, 0.60)), Vector((0.14, 0.0, 0.92))], 0.015, 'M_TrimBlack', sides=5))
    hulls = [hull_pts([(2.38, 0.86, 0.40, 1.08), (1.0, 0.92, 0.40, 1.16), (0.60, 0.92, 0.42, 1.20)]),
             hull_pts([(0.60, 0.90, 0.42, 1.20), (0.24, 0.80, 0.46, 1.62), (-0.62, 0.84, 0.46, 1.60)]),
             hull_pts([(-0.64, 0.92, 0.55, 1.42), (-2.38, 0.92, 0.55, 1.42)])]
    # contract: <= 8 material slots on the Body -> the bed floor planks share the weathered M_Traffic_Rust slot (rusty steel / dirty bed)
    ob = finish_core(v, body, glass, it, hulls, remap={'M_TrimGrey': 'M_TrimBlack', 'M_Rubber': 'M_TrimBlack', 'M_Reverse': 'M_Headlight', 'M_Paint2': 'M_TrimBlack',
                                                       'M_Traffic_Wood': 'M_Traffic_Rust'})
    mn, mx = measure_root(v, ob, width=P['W'])
    v.root['height_cab_roof'] = 1.62                      # the reported height (2.0 m) includes the headache rack
    v.root['height_rack_top'] = round(mx.z, 4)
    lap(v, "core objects: body %d tris, size %.2f x %.2f x %.2f" % (tri_count(ob['body'].data), mx.x - mn.x, mx.y - mn.y, mx.z))
    specs = []
    kw = dict(kind='car', rim_r=P['rim_r'], nuts=0, rim_mat='M_Rim', cap_mat='M_Chrome', segs=32, rim_segs=28, hub_r=0.095, cap_r=0.115, dish=0.025, hub_proud=0.022, style='dogdish', holes=0)
    for key, x, sd, axle, steer, driven in (('FL', XF, 1, 0, True, False), ('FR', XF, -1, 0, True, False), ('RL', XR, 1, 1, False, True),
                                            ('RR', XR, -1, 1, False, True)):
        tr = P['track_f'] if axle == 0 else P['track_r']
        specs.append(dict(key=key, x=x, y=sd * tr / 2, R=P['R'], W=P['WW'], side=sd, axle=axle, steering=steer, driven=driven, order=len(specs), kw=dict(kw)))
    add_wheels(v, specs)
    make_empties(v, {'LP_HeadL': (2.46, 0.70, 0.80), 'LP_HeadR': (2.46, -0.70, 0.80), 'LP_TailL': (-2.40, 0.90, 1.15),
                     'LP_TailR': (-2.40, -0.90, 1.15), 'LP_Reverse': (-2.40, 0.62, 0.62), 'CAM_Cockpit': (-0.02, 0.40, 1.40),
                     'CAM_Bumper': (2.52, 0.0, 0.50), 'EXHAUST_L': (-2.44, 0.30, 0.46)})
    lap(v, "wheels + empties")
    return v


def export_extra():
    return {"paint_variants": PAINT_VARIANTS,
            "paint_slots": {"M_Paint": "cab, fenders, bed (weathered paint); rust / wood / chrome parts are separate slots"},
            "extra_materials": {"M_Traffic_Rust": "rust patches / bed interior / bed floor planks / lower sills (one slot, so the Body stays at <= 8 slots)"},
            "dimensions_note": "dimensions.height (about 2.0 m) is the top of the headache rack; the cab roof is 1.62 m (ROOT height_cab_roof)",
            "height_cab_roof": 1.62,
            "traffic": {"role": "old work pickup", "cruise_speed_kmh": [30, 85], "mass_kg_hint": 1700, "drivetrain": "RWD", "open_bed": True},
            "collision": {"recommended": "UCX hulls in the Body FBX (3 convex hulls: bonnet, cab, bed); wheels without collision", "ucx_count": 3},
            "ue_scale_range": [0.97, 1.03]}


if STAGE == "geometry":
    v = build()
elif STAGE == "uv_a":
    uv_parts(VID, ["Body", "Glass"])
elif STAGE == "uv_b":
    uv_parts(VID, ["Interior"])
elif STAGE == "uv_wheels":
    uv_parts(VID, ["Wheels"])
elif STAGE == "validate":
    traffic_validate(VID + "_ROOT", targets=dict(length=P['L'], width=P['W'], wheelbase=P['wheelbase']))
elif STAGE == "export":
    traffic_export(VID + "_ROOT", extra=export_extra())
