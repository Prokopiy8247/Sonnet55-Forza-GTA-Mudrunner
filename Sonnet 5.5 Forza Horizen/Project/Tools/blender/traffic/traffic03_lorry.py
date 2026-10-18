"""
traffic03_lorry.py - idempotent build of the traffic rigid 3-axle box lorry (8.5 m): cab-over-engine cab + box body + chassis,
single front tyres, two rear axles with dual wheels (10 wheel objects), mud flaps, rear ladder, underrun bar.

Run in the verified Blender MCP session (localhost:9889):
    TRAFFIC_STAGE = "geometry"   # "geometry" | "uv_a" | "uv_b" | "uv_wheels" | "validate" | "export"
    exec(compile(open(r"<project>/Tools/blender/traffic/traffic03_lorry.py", encoding="utf8").read(), "lorry", "exec"), globals())
Car space: +X forward, +Y left, +Z up, origin on the ground under the middle of the wheelbase (front axle to the centre of the
rear tandem).  Staged at (42, 30, 0).
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

VID = "traffic03_lorry"
INDEX = 3
STAGE = globals().get("TRAFFIC_STAGE", "geometry")

P = dict(L=8.50, W=2.50, H=3.58, wheelbase=5.20, track_f=2.04, R=0.50, WW=0.30, WD=0.28, ride=0.62,
         x_cab_f=3.70, x_cab_b=1.55, x_box_f=1.30, x_box_b=-4.45, rim_r=0.285)
XF, XR1, XR2 = 2.60, -1.95, -3.25
Y_IN, Y_OUT = 0.78, 1.08               # centres of the inner / outer dual wheel
RAY_L, RAY_R, RAY_F, RAY_B, RAY_T = (0, -1, 0), (0, 1, 0), (-1, 0, 0), (1, 0, 0), (0, 0, -1)
PAINT_VARIANTS = paint_variants(("Haulage white", "#e9ebec", "#1f4e8c", 0.0, 0.32),
                                ("Depot red", "#b3212b", "#e9ebec", 0.15, 0.30),
                                ("Fleet green", "#2d6a3d", "#e9ebec", 0.10, 0.32))


def cab_curves():
    ztk = fillet_profile([(1.45, 2.88), (3.30, 2.90), (3.64, 1.60), (3.78, 1.46)], [0, 0.20, 0.22, 0], step=0.01)
    ztc = as_curve(ztk)
    zs = lambda x: min(1.62, ztc(x) - 0.08)
    return dict(hw=1.20, hwt=1.10, zt=ztk, zs=zs, zb=0.62, hwb=1.16, zw=0.70, cs=0.05, ct=0.14, cb=0.09, cw=0.03, cam=0.0)


def box_curves():
    return dict(hw=1.25, hwt=1.20, zt=3.58, zs=3.40, zb=1.05, hwb=1.22, zw=1.12, cs=0.06, ct=0.10, cb=0.08, cw=0.03, cam=0.0)


def build_cab(v):
    cv = cab_curves()
    xs = merge_stations([end_stations(P['x_cab_f'], 0.08, 4), [P['x_cab_f']], frange(3.28, 3.66, 0.04), frange(2.2, 3.2, 0.4),
                         end_stations(P['x_cab_b'], 0.08, 4, True), [P['x_cab_b'], 1.9]], min_gap=0.02)
    shell = sect_loft(cv, xs, ncor=dict(A=2, B=1, C=2, D=3), r0=0.08, r1=0.08, smooth_passes=2, smooth_strength=0.5)
    bm = shell.bm
    check_manifold(bm, 'cab shell')
    split_planes(bm, [((0, 0, 0.96), (0, 0, 1)), ((0, 0, 1.55), (0, 0, 1))])
    for f in bm.faces:
        c = f.calc_center_median()
        m = 'M_Paint'
        if f.normal.z < -0.6 or c.z < 0.96:
            m = 'M_TrimBlack'
        elif c.x > 3.55 and c.z < 1.55:
            m = 'M_TrimGrey'                       # grille panel
        f.material_index = mi(m)
    surf = Surface(bm)
    cut = []
    for sd in (1, -1):
        cut.append(wheel_arch_cutter(XF, P['R'], P['R'] + 0.07, sd, inner_y=0.72, outer_y=1.5, segments=26, mat='M_TrimBlack'))
    xs_void = [3.55 - 0.1 * i for i in range(0, 20)]                           # 3.55 ... 1.65
    cut.append(inner_void(cv, xs_void, 0.045, 0.82, mat_wall='M_TrimGrey', mat_floor='M_TrimBlack'))
    # windscreen
    fr_ws = Frame(Vector((3.47, 0.0, 2.25)), Vector((0.97, 0.0, 0.254)), side_like=False)
    ws_out = round_poly(fr_ws.outline_world([(-0.98, 1.80), (0.98, 1.80), (0.98, 2.74), (-0.98, 2.74)]), 0.08, 3)
    cut.append(win_cutter(fr_ws, ws_out, d_in=-0.35, d_out=0.12))
    side_glass = []
    for sd in (1, -1):
        fr = side_frame(2.6, 1.20, 1.62, 1.10, 2.90, side=sd)
        out = round_poly(fr.outline_world([(3.30, 1.82), (2.05, 1.82), (2.05, 2.70), (3.08, 2.72)]), [0.05, 0.05, 0.05, 0.14], 3)
        cut.append(win_cutter(fr, out, d_in=-0.30, d_out=0.12))
        side_glass.append((fr, out))
    # door seams / panel lines
    for sd, ray in ((1, RAY_L), (-1, RAY_R)):
        door = [Vector((3.42, sd * 1.6, 0.80)), Vector((3.42, sd * 1.6, 2.30)), Vector((3.30, sd * 1.6, 2.76)), Vector((2.00, sd * 1.6, 2.76)),
                Vector((2.00, sd * 1.6, 0.80)), Vector((3.42, sd * 1.6, 0.80))]
        g = dir_groove(surf, door, ray, closed=False, step=0.07, name='cab door')
        if g is not None:
            cut.append(g)
    # grille + lamps on the nose face
    gp = pocket_cutter(surf, outline_rrect(1.30, 0.62, 0.06, 3), Vector((3.9, 0.0, 1.12)), RAY_F, depth=0.07, taper=0.97, mat='M_TrimBlack',
                       floor_follows=False)
    if gp is not None:
        cut.append(gp)
    lenses = []
    cs_, ls_ = lens_pair(surf, (3.9, 0.90, 1.18), RAY_F, outline_rrect(0.34, 0.28, 0.06, 3), 0.06, 'M_Headlight', lens_scale=0.95)
    cut += cs_
    lenses += ls_
    cs_, ls_ = lens_pair(surf, (3.9, 0.90, 0.92), RAY_F, outline_rrect(0.34, 0.09, 0.03, 3), 0.04, 'M_Indicator', lens_scale=0.95)
    cut += cs_
    lenses += ls_
    body = bm_boolean(bm, cut)
    for l in lenses:
        put(body, l)
    # grille bars + cab details
    g = grille_mesh(outline_rrect(1.20, 0.52, 0.05, 3), kind='bars', pitch=0.06, bar=0.026, depth=0.04, frame=0.016, mat='M_TrimGrey',
                    frame_mat='M_TrimGrey')
    hit = surf.hit(Vector((3.9, 0.0, 1.12)), RAY_F)
    bmesh.ops.transform(g, matrix=Matrix.Translation(Vector((hit[0].x - 0.035, 0.0, 1.12))), verts=g.verts)
    put(body, g)
    # bumper, steps, plate, mirrors, deflector, marker lights, exhaust stack
    put(body, box(0.20, 2.42, 0.28, (3.80, 0.0, 0.50), 'M_Paint2', bevel=0.06, seg=2))
    put(body, plate_quad(3.905, 0.0, 0.52, 0.52, 0.11))
    put(body, box(0.22, 2.0, 0.035, (3.62, 0.0, 2.84), 'M_Paint', bevel=0.012))                        # sun visor
    for sd in (1, -1):
        put(body, box(0.30, 0.20, 0.03, (3.10, sd * 1.27, 0.40), 'M_TrimGrey'))
        put(body, box(0.30, 0.16, 0.03, (3.10, sd * 1.22, 0.78), 'M_TrimGrey'))
        put(body, box(0.14, 0.05, 0.40, (3.28, sd * 1.19, 0.60), 'M_TrimBlack', bevel=0.01))
    for sd, ray in ((1, RAY_L), (-1, RAY_R)):
        h = door_handle(surf, 2.20, 1.55, ray, length=0.20, width=0.035, height=0.02)
        if h is not None:
            put(body, h)
    mir = bmesh.new()
    # mirrors: arms reach only ~0.3 m beyond the 2.5 m box (overall 3.09 m), slim tall heads
    put(mir, tube([Vector((3.28, 1.20, 2.35)), Vector((3.33, 1.36, 2.40)), Vector((3.36, 1.46, 2.42))], 0.015, 'M_TrimBlack', sides=6))
    put(mir, tube([Vector((3.28, 1.20, 1.85)), Vector((3.33, 1.38, 1.95)), Vector((3.36, 1.46, 2.02))], 0.013, 'M_TrimBlack', sides=6))
    put(mir, box(0.08, 0.09, 0.46, (3.35, 1.50, 2.38), 'M_TrimBlack', bevel=0.022, seg=2))
    put(mir, box(0.004, 0.075, 0.40, (3.309, 1.50, 2.38), 'M_TrimGrey'))
    put(mir, box(0.07, 0.09, 0.17, (3.37, 1.49, 2.02), 'M_TrimBlack', bevel=0.022, seg=2))
    put_pair(body, mir)
    # roof deflector (wedge) + marker lights
    defl = prim_prism([(0.0, 0.0), (1.65, 0.0), (1.65, 0.55), (1.50, 0.58), (0.20, 0.10)], 2.20, plane='XZ', mat='M_Paint')
    bmesh.ops.translate(defl, vec=Vector((1.60, 0.0, 2.88)), verts=defl.verts)
    bevel_hard_edges(defl, angle_deg=40, width=0.035, segments=2)
    put(body, defl)
    for yy in (-0.70, -0.35, 0.0, 0.35, 0.70):
        put(body, box(0.05, 0.12, 0.05, (3.33, yy, 2.93), 'M_Indicator', bevel=0.012))
    put(body, tube([Vector((1.42, -1.18, 0.95)), Vector((1.42, -1.18, 3.40))], 0.065, 'M_Chrome', sides=12))
    put(body, tube([Vector((1.42, -1.18, 3.40)), Vector((1.50, -1.18, 3.52))], 0.05, 'M_Chrome', sides=10))
    # wipers
    for sd in (1, -1):
        put(body, tube([fr_ws.pt(sd * 0.85, -0.80, 0.02), fr_ws.pt(sd * 0.05, -0.76, 0.02)], 0.01, 'M_TrimBlack', sides=5))
    # interior
    it = bmesh.new()
    put(it, seat_block(2.55, 0.52, 1.14, w=0.56, depth=0.52, back_h=0.68))
    put(it, seat_block(2.55, -0.42, 1.14, w=0.86, depth=0.52, back_h=0.68, headrest=False))
    put(it, box(0.50, 2.20, 0.50, (3.28, 0.0, 1.30), 'M_IntDash', bevel=0.06, seg=2))
    put(it, box(0.30, 0.70, 0.16, (3.18, 0.52, 1.62), 'M_IntDash', bevel=0.05, seg=2))
    put(it, steering_wheel(3.00, 0.52, 1.50, r=0.23, tilt=18.0))
    put(it, driver_figure(2.55, 0.52, 1.14, scale=1.05))
    put(it, box(0.45, 0.32, 0.40, (2.35, 0.0, 1.0), 'M_IntTrim', bevel=0.03, seg=1))
    glass = bmesh.new()
    put(glass, win_glass(fr_ws, ws_out))
    for fr, out in side_glass:
        put(glass, win_glass(fr, out))
    return body, glass, it


def build_box(v):
    cv = box_curves()
    xs = merge_stations([end_stations(P['x_box_f'], 0.07, 3), end_stations(P['x_box_b'], 0.07, 3, True), [P['x_box_f'], P['x_box_b']],
                         frange(-4.2, 0.9, 1.0)], min_gap=0.02)
    shell = sect_loft(cv, xs, ncor=dict(A=2, B=1, C=2, D=2), r0=0.07, r1=0.07)
    bm = shell.bm
    check_manifold(bm, 'box shell')
    split_planes(bm, [((0, 0, 1.60), (0, 0, 1)), ((0, 0, 1.92), (0, 0, 1)), ((0, 0, 1.15), (0, 0, 1))])
    for f in bm.faces:
        c = f.calc_center_median()
        m = 'M_Paint'
        if f.normal.z < -0.6 or c.z < 1.15:
            m = 'M_TrimBlack'
        elif 1.60 < c.z < 1.92 and abs(f.normal.y) > 0.9:
            m = 'M_Paint2'
        f.material_index = mi(m)
    surf = Surface(bm)
    cut = []
    posts = []
    for sd, ray in ((1, RAY_L), (-1, RAY_R)):
        for xg in (0.45, -0.55, -1.55, -2.55, -3.55):                      # vertical panel joints = aluminium posts + dark gap
            g = dir_groove(surf, [Vector((xg, sd * 1.6, 1.22)), Vector((xg, sd * 1.6, 3.34))], ray, closed=False, step=0.12, name='box joint')
            if g is not None:
                cut.append(g)
            pr = rib_line(surf, [Vector((xg + 0.035, sd * 1.6, 1.20)), Vector((xg + 0.035, sd * 1.6, 3.36))], ray, 0.05, 0.012, step=0.4, name='post')
            if pr is not None:
                posts.append(pr)
        pr = rib_line(surf, [Vector((xx, sd * 1.6, 1.185)) for xx in (-4.35, -2.0, 0.0, 1.2)], ray, 0.06, 0.014, step=0.5, name='lower rail')
        if pr is not None:
            posts.append(pr)
    # rear door seams
    for g in (dir_groove(surf, [(-5.0, 0.0, 1.30), (-5.0, 0.0, 3.38)], RAY_B, closed=False, step=0.12, name='rear seam'),
              dir_groove(surf, [(-5.0, 1.12, 1.30), (-5.0, 1.12, 3.38), (-5.0, -1.12, 3.38), (-5.0, -1.12, 1.30), (-5.0, 1.12, 1.30)], RAY_B,
                         closed=False, step=0.12, name='rear outline')):
        if g is not None:
            cut.append(g)
    lenses = []
    for (zc, outline, depth, mat) in ((1.58, outline_rrect(0.16, 0.26, 0.04, 3), 0.04, 'M_Taillight'), (1.31, outline_rrect(0.16, 0.10, 0.03, 3), 0.035, 'M_Indicator')):
        cs_, ls_ = lens_pair(surf, (-5.0, 1.06, zc), RAY_B, outline, depth, mat, lens_scale=0.95)
        cut += cs_
        lenses += ls_
    body = bm_boolean(bm, cut)
    for l in lenses + posts:
        put(body, l)
    # rear details: hinges, lock bars, handles, plate, ladder, underrun bar, corner posts
    xb = P['x_box_b']
    for sd in (1, -1):
        for zz in (1.55, 2.30, 3.05):
            put(body, cyl(0.025, 0.16, (xb - 0.01, sd * 1.19, zz), 'Z', 'M_TrimGrey', segs=8))
        for yy in (0.16, 0.60):
            put(body, bar_z(1.35, 3.30, xb - 0.03, sd * yy, 0.018, 'M_TrimGrey', sides=6))
            put(body, box(0.05, 0.05, 0.12, (xb - 0.04, sd * yy, 2.15), 'M_TrimBlack', bevel=0.01))
        put(body, box(0.05, 0.10, 2.20, (xb - 0.0, sd * 1.22, 2.35), 'M_TrimGrey', bevel=0.012))
    put(body, plate_quad(xb - 0.004, 0.0, 1.30, 0.52, 0.11))
    # ladder (rear left door): 2 rails + rungs
    for yy in (-0.98, -0.70):
        put(body, bar_z(1.45, 3.35, xb - 0.09, yy, 0.022, 'M_TrimGrey', sides=6))
    for zz in [1.55 + 0.26 * i for i in range(8)]:
        put(body, bar_y(-0.98, -0.70, xb - 0.09, zz, 0.014, 'M_TrimGrey', sides=6))
    for yy in (-0.98, -0.70):
        for zz in (1.55, 3.20):
            put(body, box(0.09, 0.04, 0.05, (xb - 0.045, yy, zz), 'M_TrimGrey'))
    # underrun bar
    put(body, bar_y(-1.10, 1.10, xb - 0.12, 0.64, 0.05, 'M_TrimGrey', sides=10))
    for sd in (1, -1):
        put(body, box(0.10, 0.05, 0.40, (xb - 0.06, sd * 0.95, 0.84), 'M_TrimGrey', bevel=0.01))
        put(body, box(0.55, 0.06, 0.06, (xb + 0.28, sd * 0.95, 0.99), 'M_TrimGrey'))
    # side marker strip (red/white reflectors) below the stripe + roof clearance lights
    for sd in (1, -1):
        for xx in (-3.9, -2.4, -0.9, 0.5):
            put(body, box(0.016, 0.20, 0.07, (xx, sd * 1.26, 1.30), 'M_Indicator', bevel=0.004, seg=1))
    for yy in (-0.6, 0.0, 0.6):
        put(body, box(0.06, 0.12, 0.04, (P['x_box_f'] - 0.03, yy, 3.59), 'M_Indicator', bevel=0.01))
    return body


def build_chassis():
    ch = bmesh.new()
    for sd in (1, -1):
        put(ch, box_span(-4.25, 3.40, sd * 0.40 - 0.06, sd * 0.40 + 0.06, 0.80, 1.04, 'M_TrimBlack'))
    for x in (3.0, 1.2, -0.4, -1.0, -2.6, -4.0):
        put(ch, box_span(x - 0.06, x + 0.06, -0.45, 0.45, 0.82, 0.96, 'M_TrimBlack'))
    for x in (XF, XR1, XR2):                                              # axles + differentials
        put(ch, bar_y(-1.05 if x == XF else -0.85, 1.05 if x == XF else 0.85, x, P['R'], 0.065, 'M_TrimBlack', sides=10))
        if x != XF:
            put(ch, prim_sphere(0.20, u=12, v=8, center=(x, 0.0, P['R']), mat='M_TrimGrey', scale=(1.0, 1.1, 0.9)))
        for sd in (1, -1):
            put(ch, box(0.12, 0.10, 0.12, (x, sd * 0.36, P['R'] + 0.20), 'M_TrimGrey'))
            put(ch, box(1.10, 0.07, 0.04, (x, sd * 0.36, P['R'] + 0.30), 'M_TrimBlack'))
    put(ch, cyl(0.35, 0.95, (-0.80, 0.80, 0.70), 'Y', 'M_TrimGrey', segs=18))                     # fuel tank (left)
    for dxs in (-0.27, 0.27):
        put(ch, cyl(0.36, 0.05, (-0.80 + 0.0, 0.80 + dxs, 0.70), 'Y', 'M_TrimBlack', segs=18))
    put(ch, cyl(0.055, 0.06, (-0.80, 1.30, 0.80), 'Y', 'M_TrimBlack', segs=10))
    put(ch, cyl(0.20, 0.80, (0.30, -0.80, 0.72), 'Y', 'M_TrimGrey', segs=14))                     # air tank (right)
    put(ch, box(0.5, 0.45, 0.35, (-1.0, -0.80, 0.78), 'M_TrimBlack', bevel=0.02))                 # battery box
    put(ch, bar_x(0.9, -3.1, 0.0, 0.62, 0.05, 'M_TrimGrey', sides=8))                              # propshaft
    # mud flaps: behind the front axle and behind both rear tandem axles (outer / inner pair as one wide flap)
    for sd in (1, -1):
        put(ch, box(0.015, 0.50, 0.36, (XF - 0.60, sd * 1.02, 0.42), 'M_Rubber'))
        put(ch, box(0.016, 0.20, 0.07, (XF - 0.605, sd * 1.02, 0.26), 'M_Plate'))
        for xr in (XR1, XR2):
            put(ch, box(0.015, 0.90, 0.38, (xr - 0.64, sd * 0.93, 0.44), 'M_Rubber'))
            put(ch, bar_y(sd * 0.48, sd * 1.38, xr - 0.62, 0.64, 0.012, 'M_TrimGrey', sides=6))
            put(ch, box(0.016, 0.30, 0.07, (xr - 0.645, sd * 0.93, 0.26), 'M_Plate'))
    return ch


def build():
    v = new_vehicle(VID, INDEX, "Box Lorry", wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=1.86,
                    wheel_radius_front=P['R'], wheel_radius_rear=P['R'], wheel_width_front=P['WW'], wheel_width_rear=P['WD'],
                    ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], drivetrain='6x2')
    cab, glass, it = build_cab(v)
    lap(v, "cab: %d tris" % tri_count(cab))
    box_bm = build_box(v)
    lap(v, "box: %d tris" % tri_count(box_bm))
    ch = build_chassis()
    lap(v, "chassis: %d tris" % tri_count(ch))
    body = bmesh.new()
    for part in (cab, box_bm, ch):
        put(body, part)
    hulls = [hull_pts([(1.55, 1.18, 0.62, 2.90), (3.64, 1.12, 0.62, 1.60), (3.72, 1.10, 0.62, 1.50)]),
             hull_pts([(1.30, 1.25, 1.05, 3.58), (-4.45, 1.25, 1.05, 3.58)]),
             hull_pts([(3.40, 0.52, 0.78, 1.04), (-4.25, 0.52, 0.78, 1.04)]),
             hull_pts([(-3.60, 1.20, 0.0, 0.80), (-1.60, 1.20, 0.0, 0.80)])]
    ob = finish_core(v, body, glass, it, hulls, remap={'M_Chrome': 'M_TrimGrey', 'M_Rubber': 'M_TrimBlack'})
    mn, mx = measure_root(v, ob, width=P['W'])
    lap(v, "core objects: body %d tris, size %.2f x %.2f x %.2f" % (tri_count(ob['body'].data), mx.x - mn.x, mx.y - mn.y, mx.z))

    specs = []
    kwo = dict(kind='truck', rim_r=P['rim_r'], nuts=8, rim_mat='M_Rim', cap_mat='M_RimDark', segs=28, rim_segs=24, hub_r=0.11, dish=0.045, hub_proud=0.05, style='steel', holes=8)
    n = 0

    def add(x, y, W, axle, steer, driven, dual=''):
        nonlocal n
        n += 1
        sd = 1 if y > 0 else -1
        specs.append(dict(key=str(n), x=x, y=y, R=P['R'], W=W, side=sd, axle=axle, steering=steer, driven=driven, order=n, dual_with=dual, kw=dict(kwo)))
        return n

    add(XF, P['track_f'] / 2, P['WW'], 0, True, False)
    add(XF, -P['track_f'] / 2, P['WW'], 0, True, False)
    for axle, x in ((1, XR1), (2, XR2)):
        for sd in (1, -1):
            base = n + 1
            drv = (axle == 1)                         # 6x2: only the first rear axle is driven, the second one is a (dual) tag axle
            a = add(x, sd * Y_OUT, P['WD'], axle, False, drv, dual="%s_Wheel_%d" % (VID, base + 1))
            b = add(x, sd * Y_IN, P['WD'], axle, False, drv, dual="%s_Wheel_%d" % (VID, base))
            specs[-1]['kw'] = dict(kwo, inner_only=True, nuts=0)
    add_wheels(v, specs)
    make_empties(v, {'LP_HeadL': (3.80, 0.90, 1.18), 'LP_HeadR': (3.80, -0.90, 1.18), 'LP_TailL': (-4.49, 1.06, 1.58),
                     'LP_TailR': (-4.49, -1.06, 1.58), 'LP_Reverse': (-4.49, 0.70, 1.31), 'CAM_Cockpit': (2.80, 0.52, 2.15),
                     'CAM_Bumper': (3.92, 0.0, 0.65), 'EXHAUST_1': (1.50, -1.18, 3.52)})
    lap(v, "wheels + empties")
    return v


def export_extra():
    return {"paint_variants": PAINT_VARIANTS,
            "paint_slots": {"M_Paint": "cab + box panels, roof deflector", "M_Paint2": "box side stripe, front bumper (accent)"},
            "traffic": {"role": "rigid box lorry (6x2)", "cruise_speed_kmh": [30, 80], "mass_kg_hint": 11000, "drivetrain": "6x2: front axle steered, first rear axle (axle 1) driven, second rear axle (axle 2) is an undriven tag axle",
                        "dual_wheels": "rear axles carry outer+inner wheel meshes; JSON 'dual_with' links the pair - drive both from one physics wheel",
                        "wheel_layout": "JSON 'wheels' (10 entries, key 1..10) + 'axles' (3 entries) - no FL/FR wheel_map for 6+ wheel vehicles"},
            "collision": {"recommended": "UCX hulls in the Body FBX (4 convex hulls: cab, box, chassis rails, tandem underside); wheels without collision",
                          "ucx_count": 4},
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
