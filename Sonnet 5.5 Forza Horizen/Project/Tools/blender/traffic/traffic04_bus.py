"""
traffic04_bus.py - idempotent build of the traffic intercity coach (12 m, 2 axles: front pair + dual rear wheels = 6 wheel objects),
large side windows in a dark window band, luggage bays, roof air-conditioning pods, visible seat rows.

Run in the verified Blender MCP session (localhost:9889):
    TRAFFIC_STAGE = "geometry"   # "geometry" | "uv_a" | "uv_b" | "uv_wheels" | "validate" | "export"
    exec(compile(open(r"<project>/Tools/blender/traffic/traffic04_bus.py", encoding="utf8").read(), "bus", "exec"), globals())
Car space: +X forward, +Y left, +Z up, origin on the ground under the middle of the wheelbase.  Staged at (56, 30, 0).
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

VID = "traffic04_bus"
INDEX = 4
STAGE = globals().get("TRAFFIC_STAGE", "geometry")

P = dict(L=12.0, W=2.55, H=3.66, wheelbase=6.10, track_f=2.05, R=0.52, WW=0.295, ride=0.42, x_front=5.65, x_rear=-5.98, hw=1.275,
         rim_r=0.285, Z_FLOOR=1.08)
XF, XR = 3.05, -3.05
Y_IN, Y_OUT = 0.76, 1.07
RAY_L, RAY_R, RAY_F, RAY_B, RAY_T = (0, -1, 0), (0, 1, 0), (-1, 0, 0), (1, 0, 0), (0, 0, -1)
PAINT_VARIANTS = paint_variants(("Coach white", "#ebecee", "#1c3d6e", 0.0, 0.30),
                                ("Express blue", "#1d4f9c", "#e9eaec", 0.20, 0.28),
                                ("Regional green", "#26704a", "#e9eaec", 0.15, 0.30))
WIN_Z0, WIN_Z1 = 1.68, 2.84


def curves():
    ztk = fillet_profile([(-6.40, 2.80), (-6.06, 3.40), (4.90, 3.42), (5.52, 3.30), (5.92, 1.60)], [0, 0.65, 0.9, 0.8, 0], step=0.02)
    ztc = as_curve(ztk)
    zs = lambda x: min(2.97, ztc(x) - 0.09)
    hw = lambda x: P['hw'] - 0.05 * smoothstep(5.0, 5.65, x) - 0.06 * smoothstep(-5.3, -5.98, x)
    hwt = lambda x: hw(x) - 0.125
    zb = as_curve([(-6.1, 0.58), (-5.5, 0.44), (-4.8, 0.40), (4.8, 0.40), (5.4, 0.46), (5.8, 0.62)])
    return dict(hw=hw, hwt=hwt, zt=ztk, zs=zs, zb=zb, hwb=lambda x: hw(x) - 0.015, zw=lambda x: zb(x) + 0.30, cs=0.10, ct=0.26, cb=0.10, cw=0.04, cam=0.04)


def window_x_ranges(first_x1=4.55, pitch=1.05, width=0.93, n=10):
    return [(first_x1 - pitch * i - width, first_x1 - pitch * i) for i in range(n)]


def seat_simple(x, y, z, w=0.44, mat='M_IntSeat'):
    """cheap seat: cushion box + tall back box (no bevel)"""
    bm = bmesh.new()
    put(bm, box(0.46, w, 0.10, (x, y, z - 0.05), mat))
    put(bm, box(0.10, w, 0.72, (x - 0.22, y, z + 0.34), mat))
    return bm


def build():
    v = new_vehicle(VID, INDEX, "Intercity Coach", wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=1.83,
                    wheel_radius_front=P['R'], wheel_radius_rear=P['R'], wheel_width_front=P['WW'], wheel_width_rear=P['WW'],
                    ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], drivetrain='RWD')
    cv = curves()
    xf, xr = P['x_front'], P['x_rear']
    xs = merge_stations([end_stations(xf, 0.18, 5), end_stations(xr, 0.18, 5, True), [xf, xr], frange(xr + 0.6, 4.7, 0.9),
                         frange(4.7, 5.3, 0.15), frange(-5.9, -5.3, 0.15), [-6.0]], min_gap=0.03)
    shell = sect_loft(cv, xs, ncor=dict(A=2, B=1, C=2, D=4), r0=0.18, r1=0.18, smooth_passes=2, smooth_strength=0.5)
    bm = shell.bm
    check_manifold(bm, 'shell')
    lap(v, "shell %d stations x %d pts" % (len(xs), shell.ring_pts))
    split_planes(bm, [((0, 0, 0.78), (0, 0, 1)), ((0, 0, WIN_Z0 - 0.10), (0, 0, 1)), ((0, 0, 2.98), (0, 0, 1))])
    for f in bm.faces:
        c = f.calc_center_median()
        m = 'M_Paint'
        if f.normal.z < -0.6 or c.z < 0.78:
            m = 'M_TrimBlack'
        elif WIN_Z0 - 0.10 < c.z < 2.98 and abs(f.normal.y) > 0.75 and xr + 0.2 < c.x < 5.2:
            m = 'M_Paint2'                           # dark window band
        f.material_index = mi(m)
    surf = Surface(bm)

    cut = []
    for (x, sd) in ((XF, 1), (XF, -1), (XR, 1), (XR, -1)):
        cut.append(wheel_arch_cutter(x, P['R'], P['R'] + 0.07, sd, inner_y=0.80 if x == XF else 0.56, outer_y=1.6, segments=26, mat='M_TrimBlack'))
    xs_void = [5.50 - 0.5 * i for i in range(0, 22)] + [-5.90]
    xs_void = sorted(set(round(x, 3) for x in xs_void), reverse=True)
    cut.append(inner_void(cv, xs_void, 0.05, P['Z_FLOOR'], mat_wall='M_TrimGrey', mat_floor='M_IntCarpet'))

    # windscreen: plane through the roof edge (5.52, 3.30) and the nose (5.92, 1.60)
    nws = Vector((1.70, 0.0, 0.40))
    fr_ws = Frame(Vector((5.72, 0.0, 2.45)), nws, side_like=False)
    ws_out = round_poly(fr_ws.outline_world([(-1.08, 1.82), (1.08, 1.82), (1.08, 3.18), (-1.08, 3.18)]), 0.12, 3)
    cut.append(win_cutter(fr_ws, ws_out, d_in=-0.40, d_out=0.15))
    # rear window (in the rear cap / top face region)
    fr_rw = Frame(Vector((-6.15, 0.0, 2.45)), Vector((-0.6, 0.0, 0.25)), side_like=False)
    rw_out = round_poly(fr_rw.outline_world([(-0.8, 2.15), (0.8, 2.15), (0.8, 2.75), (-0.8, 2.75)]), 0.10, 3)
    cut.append(win_cutter(fr_rw, rw_out, d_in=-0.30, d_out=0.15))
    side_glass = []
    wins = window_x_ranges()
    for sd in (1, -1):
        fr = side_frame(0.0, P['hw'], 2.97, P['hw'], 3.4, side=sd)           # vertical wall plane (normal = +-Y)
        for i, (xa, xb) in enumerate(wins):
            if sd == -1 and i == 0:
                continue                                                      # entrance door on the right
            if sd == 1 and i == 0:
                xa = xa + 0.12
            out = round_poly(fr.outline_world([(xb, WIN_Z0), (xa, WIN_Z0), (xa, WIN_Z1), (xb, WIN_Z1)]), 0.10, 3)
            cut.append(win_cutter(fr, out, d_in=-0.30, d_out=0.12))
            side_glass.append((fr, out))
    # entrance door glass (right side, two leaves) + driver side window handled above
    frr = side_frame(0.0, P['hw'], 2.97, P['hw'], 3.4, side=-1)
    for (xa, xb) in ((4.60, 5.02), (5.08, 5.50)):
        out = round_poly(frr.outline_world([(xb, 0.98), (xa, 0.98), (xa, 2.84), (xb, 2.84)]), 0.06, 3)
        cut.append(win_cutter(frr, out, d_in=-0.30, d_out=0.12))
        side_glass.append((frr, out))

    # luggage bays (both sides), entrance door outline, engine louvre area
    for sd, ray in ((1, RAY_L), (-1, RAY_R)):
        for (xa, xb) in ((-2.30, -1.10), (-0.95, 0.25), (0.40, 1.60)):
            outline = [Vector((xa, sd * 1.8, 0.82)), Vector((xb, sd * 1.8, 0.82)), Vector((xb, sd * 1.8, 1.50)), Vector((xa, sd * 1.8, 1.50)),
                       Vector((xa, sd * 1.8, 0.82))]
            g = dir_groove(surf, outline, ray, closed=False, step=0.1, name='bay', width=0.013, depth=0.016)
            if g is not None:
                cut.append(g)
    door = [Vector((4.56, -1.8, 0.62)), Vector((4.56, -1.8, 2.90)), Vector((5.54, -1.8, 2.90)), Vector((5.54, -1.8, 0.62)), Vector((4.56, -1.8, 0.62))]
    g = dir_groove(surf, door, RAY_R, closed=False, step=0.1, name='door', width=0.013, depth=0.016)
    if g is not None:
        cut.append(g)
    g = dir_groove(surf, [Vector((5.05, -1.8, 0.62)), Vector((5.05, -1.8, 0.98))], RAY_R, closed=False, step=0.1, name='door_mid', width=0.013, depth=0.016)
    if g is not None:
        cut.append(g)
    # front lamps + grille + rear lamps
    lenses = []
    cs_, ls_ = lens_pair(surf, (6.1, 0.92, 0.95), RAY_F, outline_rrect(0.46, 0.20, 0.06, 3), 0.06, 'M_Headlight', lens_scale=0.95)
    cut += cs_
    lenses += ls_
    cs_, ls_ = lens_pair(surf, (6.1, 0.92, 0.70), RAY_F, outline_rrect(0.46, 0.09, 0.03, 3), 0.04, 'M_Indicator', lens_scale=0.95)
    cut += cs_
    lenses += ls_
    gp = pocket_cutter(surf, outline_rrect(0.90, 0.30, 0.05, 3), Vector((6.1, 0.0, 0.84)), RAY_F, depth=0.07, taper=0.97, mat='M_TrimBlack', floor_follows=False)
    if gp is not None:
        cut.append(gp)
    for (zc, outline, depth, mat) in ((1.20, outline_rrect(0.16, 0.50, 0.04, 3), 0.05, 'M_Taillight'), (0.80, outline_rrect(0.16, 0.12, 0.03, 3), 0.04, 'M_Indicator')):
        cs_, ls_ = lens_pair(surf, (-6.2, 1.06, zc), RAY_B, outline, depth, mat, lens_scale=0.95)
        cut += cs_
        lenses += ls_
    lap(v, "cutters ready: %d" % len(cut))
    body = bm_boolean(bm, cut)
    lap(v, "boolean done: %d tris" % tri_count(body))
    for l in lenses:
        put(body, l)
    g = grille_mesh(outline_rrect(0.86, 0.26, 0.04, 3), kind='bars', pitch=0.05, bar=0.018, depth=0.04, frame=0.014, mat='M_TrimGrey', frame_mat='M_TrimGrey')
    hit = surf.hit(Vector((6.1, 0.0, 0.84)), RAY_F)
    bmesh.ops.transform(g, matrix=Matrix.Translation(Vector((hit[0].x - 0.035, 0.0, 0.84))), verts=g.verts)
    put(body, g)
    # bumpers + plates + sunshade + destination sign
    put(body, box(0.24, 2.46, 0.32, (5.73, 0.0, 0.58), 'M_Paint2', bevel=0.07, seg=2))
    put(body, box(0.24, 2.46, 0.32, (-6.03, 0.0, 0.60), 'M_Paint2', bevel=0.07, seg=2))
    put(body, plate_quad(5.855, 0.0, 0.58, 0.52, 0.11))
    put(body, plate_quad(-6.16, 0.0, 0.86, 0.52, 0.11))
    hit = surf.hit(Vector((6.1, 0.0, 3.0)), RAY_F)
    put(body, box(0.06, 1.50, 0.26, (hit[0].x + 0.005, 0.0, 3.14), 'M_TrimBlack', bevel=0.028, seg=2))     # destination sign housing
    put(body, box(0.012, 1.30, 0.13, (hit[0].x + 0.033, 0.0, 3.14), 'M_Indicator', bevel=0.004))            # lit destination display
    # luggage bay handles, door handles
    for sd, ray in ((1, RAY_L), (-1, RAY_R)):
        for (xa, xb) in ((-2.30, -1.10), (-0.95, 0.25), (0.40, 1.60)):
            h = door_handle(surf, (xa + xb) / 2, 1.30, ray, length=0.22, width=0.035, height=0.02)
            if h is not None:
                put(body, h)
        h = door_handle(surf, 5.30 if sd == -1 else 5.0, 1.20, ray, length=0.12, width=0.03, height=0.018)
        if h is not None and sd == -1:
            put(body, h)
    # mirrors (large, on arms), wipers, side markers, arch lips
    mir = bmesh.new()                                                  # arms reach ~0.3 m beyond the body, slim tall heads
    put(mir, tube([Vector((5.30, 1.22, 2.40)), Vector((5.38, 1.38, 2.46)), Vector((5.42, 1.48, 2.48))], 0.016, 'M_TrimBlack', sides=6))
    put(mir, tube([Vector((5.30, 1.22, 2.02)), Vector((5.38, 1.38, 2.12)), Vector((5.42, 1.48, 2.18))], 0.013, 'M_TrimBlack', sides=6))
    put(mir, box(0.075, 0.085, 0.46, (5.42, 1.52, 2.32), 'M_TrimBlack', bevel=0.022, seg=2))
    put(mir, box(0.004, 0.07, 0.40, (5.378, 1.52, 2.32), 'M_TrimGrey'))
    put_pair(body, mir)
    for sd in (1, -1):
        put(body, tube([fr_ws.pt(sd * 0.85, -0.55, 0.02), fr_ws.pt(sd * 0.05, -0.50, 0.02)], 0.011, 'M_TrimBlack', sides=5))
        for xx in (-5.0, -3.8, -0.8, 1.9, 4.1):
            put(body, box(0.14, 0.02, 0.05, (xx, sd * 1.285, 2.97), 'M_Indicator', bevel=0.006))
    for (x, sd, ray) in ((XF, 1, RAY_L), (XF, -1, RAY_R), (XR, 1, RAY_L), (XR, -1, RAY_R)):
        am = arch_moulding(surf, x, P['R'], P['R'] + 0.095, ray, a0=10, a1=170, n=16, width=0.07, height=0.018)
        if am is not None:
            put(body, am)
    # roof pods
    zr = 3.42
    put(body, box(2.30, 1.55, 0.24, (-1.55, 0.0, zr + 0.06), 'M_Paint', bevel=0.12, seg=3))
    put(body, box(1.50, 1.15, 0.20, (-4.00, 0.0, zr + 0.04), 'M_Paint', bevel=0.10, seg=3))
    put(body, box(0.95, 0.95, 0.07, (1.9, 0.0, zr + 0.02), 'M_Paint2', bevel=0.03, seg=2))
    for xx in (-0.85, -1.05, -1.25, -1.45, -1.65, -1.85, -2.05, -2.25):                      # louvre slots on the big pod
        put(body, box(0.045, 1.2, 0.02, (xx, 0.0, zr + 0.185), 'M_TrimBlack'))
    put(body, prim_sphere(0.17, u=12, v=6, center=(-5.2, 0.0, zr + 0.02), mat='M_TrimBlack', scale=(1.0, 1.0, 0.7)))
    # rear engine grille + exhaust
    put(body, box(0.04, 1.30, 0.40, (-6.00, 0.0, 1.70), 'M_TrimBlack'))
    for zz in [1.52 + 0.075 * i for i in range(5)]:
        put(body, box(0.05, 1.22, 0.02, (-6.015, 0.0, zz), 'M_TrimGrey'))
    put(body, tube([Vector((-5.4, -0.75, 0.50)), Vector((-6.05, -0.75, 0.48))], 0.055, 'M_TrimGrey', sides=10))
    # chassis bits visible under the body
    for xx in (XF, XR):
        put(body, bar_y(-0.95 if xx == XF else -0.80, 0.95 if xx == XF else 0.80, xx, P['R'], 0.07, 'M_TrimBlack', sides=10))
    put(body, prim_sphere(0.22, u=12, v=8, center=(XR, 0.0, P['R']), mat='M_TrimGrey', scale=(1.0, 1.1, 0.9)))
    # mud flaps
    for sd in (1, -1):
        put(body, box(0.015, 0.55, 0.36, (XF - 0.62, sd * 1.02, 0.44), 'M_Rubber'))
        put(body, box(0.015, 0.95, 0.36, (XR - 0.66, sd * 0.92, 0.44), 'M_Rubber'))
    lap(v, "add-ons done: %d tris" % tri_count(body))

    glass = bmesh.new()
    put(glass, win_glass(fr_ws, ws_out))
    put(glass, win_glass(fr_rw, rw_out))
    for fr, out in side_glass:
        put(glass, win_glass(fr, out))

    # interior: driver cab + 10 seat rows + stairs well hint
    it = bmesh.new()
    put(it, seat_block(4.95, 0.62, P['Z_FLOOR'] + 0.42, w=0.52, depth=0.52, back_h=0.62))
    put(it, driver_figure(4.95, 0.62, P['Z_FLOOR'] + 0.42, scale=1.0))
    put(it, steering_wheel(5.40, 0.62, 1.82, r=0.23, tilt=24.0))
    put(it, box(0.50, 2.20, 0.48, (5.46, 0.0, 1.45), 'M_IntDash', bevel=0.05, seg=2))
    for i in range(10):
        xs_ = 3.6 - 0.95 * i
        for yy in (0.52, 0.98, -0.52, -0.98):
            put(it, seat_simple(xs_, yy, P['Z_FLOOR'] + 0.38, w=0.42))
    for xx in (4.9, 5.2):
        put(it, box(0.30, 0.60, 0.15, (xx, -0.70, P['Z_FLOOR'] - 0.02 + (0.0 if xx > 5 else 0.14)), 'M_IntTrim'))

    # 3 chunky convex hulls: nose wedge, passenger deck, tail wedge (every one >= 0.7 m deep - no thin plates)
    hulls = [hull_pts([(5.85, 1.18, 0.50, 1.90), (5.40, 1.22, 0.45, 3.28), (4.90, 1.27, 0.40, 3.40)]),
             hull_pts([(4.90, 1.27, 0.40, 3.42), (-5.20, 1.27, 0.40, 3.42)]),
             hull_pts([(-5.20, 1.27, 0.40, 3.42), (-6.10, 1.19, 0.55, 2.90)])]
    ob = finish_core(v, body, glass, it, hulls, remap={'M_Rubber': 'M_TrimBlack', 'M_IntCarpet': 'M_TrimBlack'})
    mn, mx = measure_root(v, ob, width=P['W'])
    lap(v, "core objects: body %d tris, size %.2f x %.2f x %.2f" % (tri_count(ob['body'].data), mx.x - mn.x, mx.y - mn.y, mx.z))

    specs = []
    kwo = dict(kind='bus', rim_r=P['rim_r'], nuts=8, rim_mat='M_Rim', cap_mat='M_RimDark', segs=28, rim_segs=24, hub_r=0.11, dish=0.045, hub_proud=0.05, style='steel', holes=8)
    specs.append(dict(key='1', x=XF, y=P['track_f'] / 2, R=P['R'], W=P['WW'], side=1, axle=0, steering=True, driven=False, order=1, kw=dict(kwo)))
    specs.append(dict(key='2', x=XF, y=-P['track_f'] / 2, R=P['R'], W=P['WW'], side=-1, axle=0, steering=True, driven=False, order=2, kw=dict(kwo)))
    n = 2
    for sd in (1, -1):
        base = n + 1
        specs.append(dict(key=str(base), x=XR, y=sd * Y_OUT, R=P['R'], W=P['WW'], side=sd, axle=1, steering=False, driven=True, order=base,
                          dual_with="%s_Wheel_%d" % (VID, base + 1), kw=dict(kwo)))
        specs.append(dict(key=str(base + 1), x=XR, y=sd * Y_IN, R=P['R'], W=P['WW'], side=sd, axle=1, steering=False, driven=True, order=base + 1,
                          dual_with="%s_Wheel_%d" % (VID, base), kw=dict(kwo, inner_only=True, nuts=0)))
        n += 2
    add_wheels(v, specs)
    make_empties(v, {'LP_HeadL': (5.70, 0.92, 0.95), 'LP_HeadR': (5.70, -0.92, 0.95), 'LP_TailL': (-6.00, 1.06, 1.20),
                     'LP_TailR': (-6.00, -1.06, 1.20), 'LP_Reverse': (-6.00, 0.70, 0.80), 'CAM_Cockpit': (5.00, 0.62, 2.20),
                     'CAM_Bumper': (5.90, 0.0, 0.70), 'EXHAUST_1': (-6.05, -0.75, 0.48)})
    lap(v, "wheels + empties")
    return v


def export_extra():
    return {"paint_variants": PAINT_VARIANTS,
            "paint_slots": {"M_Paint": "lower body, roof, AC pods", "M_Paint2": "dark window band, bumpers (accent)"},
            "traffic": {"role": "intercity coach", "cruise_speed_kmh": [40, 100], "mass_kg_hint": 14500, "drivetrain": "rear axle driven",
                        "seats": 41, "dual_wheels": "rear axle: outer+inner wheel mesh per side, JSON 'dual_with' links the pair"},
            "collision": {"recommended": "UCX hulls in the Body FBX (3 convex hulls, each >= 0.7 m deep: nose wedge, passenger deck, tail wedge); wheels without collision",
                          "ucx_count": 3},
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
