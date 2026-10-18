"""
traffic05_tractor.py - idempotent build of the traffic farm tractor (4.2 m): huge lugged rear tyres (R 0.8 m), small front tyres,
glazed cab, bonnet with grille, exhaust stack, rear fenders, 3-point linkage + drawbar hitch.

Run in the verified Blender MCP session (localhost:9889):
    TRAFFIC_STAGE = "geometry"   # "geometry" | "uv_a" | "uv_b" | "uv_wheels" | "validate" | "export"
    exec(compile(open(r"<project>/Tools/blender/traffic/traffic05_tractor.py", encoding="utf8").read(), "tractor", "exec"), globals())
Car space: +X forward, +Y left, +Z up, origin on the ground under the middle of the wheelbase.  Staged at (70, 30, 0).
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

VID = "traffic05_tractor"
INDEX = 5
STAGE = globals().get("TRAFFIC_STAGE", "geometry")

P = dict(L=4.20, W=2.30, H=2.85, wheelbase=2.35, track_f=1.60, track_r=1.80, R_f=0.48, W_f=0.26, R_r=0.80, W_r=0.50, ride=0.40,
         x_hood_f=1.90, x_hood_b=-0.08, x_cab_f=-0.10, x_cab_b=-1.52)
XF, XR = 1.175, -1.175
RAY_L, RAY_R, RAY_F, RAY_B, RAY_T = (0, -1, 0), (0, 1, 0), (-1, 0, 0), (1, 0, 0), (0, 0, -1)
PAINT_VARIANTS = paint_variants(("Field green", "#2f7a35", "#e0b61d", 0.1, 0.34),
                                ("Harvest red", "#b02a1f", "#d9d9d6", 0.1, 0.34),
                                ("Farm blue", "#1f4f93", "#d9d9d6", 0.1, 0.34))


def fender_shell(cx, cz, r, width, thick, arc=190.0, y_center=0.0, mat='M_Paint', segs=22):
    """Half-ring mudguard over a wheel at (cx, cz): closed rectangular section revolved around the axle (Y)."""
    prof = [(r, -width / 2), (r + thick, -width / 2), (r + thick, width / 2), (r, width / 2)]
    bm = prim_revolve(prof, segments=segs, axis='Y', closed=True, mat=mat, angle=arc)
    bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.radians(-90.0 - arc / 2.0), 4, 'Y'), verts=bm.verts)
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector((cx, y_center, cz))), verts=bm.verts)
    return bm


def build_cab():
    xf, xb = P['x_cab_f'], P['x_cab_b']
    cv = dict(hw=0.66, hwt=0.62, zt=2.62, zs=1.58, zb=1.10, hwb=0.64, zw=1.16, cs=0.05, ct=0.12, cb=0.06, cw=0.03, cam=0.0)
    xs = merge_stations([end_stations(xf, 0.05, 3), end_stations(xb, 0.05, 3, True), [xf, xb, -0.8]], min_gap=0.02)
    shell = sect_loft(cv, xs, ncor=dict(A=1, B=1, C=1, D=3), r0=0.05, r1=0.05)
    bm = shell.bm
    check_manifold(bm, 'cab')
    split_planes(bm, [((0, 0, 1.58), (0, 0, 1)), ((0, 0, 2.44), (0, 0, 1))])
    for f in bm.faces:
        c = f.calc_center_median()
        m = 'M_Paint2'
        if f.normal.z < -0.6:
            m = 'M_TrimBlack'
        elif c.z > 2.44 or c.z < 1.58:
            m = 'M_Paint'
        f.material_index = mi(m)
    surf = Surface(bm)
    cut = []
    cut.append(inner_void(cv, [-0.15, -0.5, -0.9, -1.47], 0.04, 1.20, mat_wall='M_TrimGrey', mat_floor='M_TrimBlack'))
    # windscreen on the front cap, rear window on the rear cap
    fr_ws = Frame(Vector((xf, 0.0, 2.0)), Vector((1.0, 0.0, 0.0)), side_like=False)
    ws_out = round_poly(fr_ws.outline_world([(-0.58, 1.66), (0.58, 1.66), (0.58, 2.50), (-0.58, 2.50)]), 0.06, 3)
    cut.append(win_cutter(fr_ws, ws_out, d_in=-0.30, d_out=0.12))
    fr_rw = Frame(Vector((xb, 0.0, 2.0)), Vector((-1.0, 0.0, 0.0)), side_like=False)
    rw_out = round_poly(fr_rw.outline_world([(-0.58, 1.66), (0.58, 1.66), (0.58, 2.50), (-0.58, 2.50)]), 0.06, 3)
    cut.append(win_cutter(fr_rw, rw_out, d_in=-0.30, d_out=0.12))
    side_glass = []
    for sd in (1, -1):
        fr = side_frame(-0.8, 0.66, 1.58, 0.62, 2.62, side=sd)
        for (xa, xb_) in ((-0.20, -0.98), (-1.06, -1.44)):
            out = round_poly(fr.outline_world([(xa, 1.66), (xb_, 1.66), (xb_, 2.50), (xa, 2.50)]), 0.05, 3)
            cut.append(win_cutter(fr, out, d_in=-0.25, d_out=0.12))
            side_glass.append((fr, out))
        door = [Vector((-0.16, sd * 1.5, 1.22)), Vector((-0.16, sd * 1.5, 2.54)), Vector((-1.02, sd * 1.5, 2.54)), Vector((-1.02, sd * 1.5, 1.22)),
                Vector((-0.16, sd * 1.5, 1.22))]
        g = dir_groove(surf, door, RAY_L if sd > 0 else RAY_R, closed=False, step=0.06, name='cab door')
        if g is not None:
            cut.append(g)
    body = bm_boolean(bm, cut)
    # roof cap, visor, gutters, pillars highlight, lights, beacon
    put(body, box(1.78, 1.50, 0.05, (-0.81, 0.0, 2.645), 'M_Paint2', bevel=0.02, seg=1))
    put(body, box(0.22, 1.30, 0.04, (0.05, 0.0, 2.58), 'M_Paint2', bevel=0.012))
    for yy in (-0.50, -0.17, 0.17, 0.50):
        put(body, box(0.07, 0.11, 0.07, (0.02, yy, 2.69), 'M_Headlight', bevel=0.012))
    for yy in (-0.42, 0.42):
        put(body, box(0.07, 0.11, 0.07, (-1.60, yy, 2.69), 'M_Headlight', bevel=0.012))
    put(body, cyl(0.07, 0.14, (-0.70, 0.45, 2.73), 'Z', 'M_Indicator', segs=10, radius2=0.05))
    put(body, cyl(0.03, 0.05, (-0.70, 0.45, 2.65), 'Z', 'M_TrimBlack', segs=8))
    put(body, tube([Vector((-1.40, -0.40, 2.67)), Vector((-1.42, -0.40, 2.86))], 0.006, 'M_TrimBlack', sides=5))
    # mirrors on the front corners
    mir = bmesh.new()
    put(mir, tube([Vector((0.0, 0.62, 2.20)), Vector((0.02, 0.80, 2.24)), Vector((0.03, 0.92, 2.27))], 0.014, 'M_TrimBlack', sides=6))
    put(mir, box(0.05, 0.12, 0.30, (0.04, 0.96, 2.22), 'M_TrimBlack', bevel=0.012, seg=1))
    put_pair(body, mir)
    for sd, ray in ((1, RAY_L), (-1, RAY_R)):
        h = door_handle(surf, -0.88, 1.85, ray, length=0.12, width=0.03, height=0.018)
        if h is not None:
            put(body, h)
    # left access steps + rails
    put(body, box(0.50, 0.28, 0.035, (-0.60, 0.80, 0.78), 'M_TrimBlack'))
    put(body, box(0.50, 0.24, 0.035, (-0.60, 0.74, 1.08), 'M_TrimBlack'))
    put(body, bar_z(1.10, 1.95, 0.0, 0.70, 0.016, 'M_TrimGrey', sides=6))
    glass = bmesh.new()
    put(glass, win_glass(fr_ws, ws_out))
    put(glass, win_glass(fr_rw, rw_out))
    for fr, out in side_glass:
        put(glass, win_glass(fr, out))
    return body, glass, (fr_ws,)


def build_hood():
    xf, xb = P['x_hood_f'], P['x_hood_b']
    ztk = fillet_profile([(xb - 0.05, 1.50), (1.30, 1.50), (xf + 0.05, 1.36)], [0, 0.6, 0], step=0.02)
    cv = dict(hw=lambda x: 0.43 - 0.03 * smoothstep(0.8, 1.9, x), hwt=lambda x: 0.38 - 0.02 * smoothstep(0.8, 1.9, x), zt=ztk,
              zs=lambda x: as_curve(ztk)(x) - 0.13, zb=0.72, hwb=0.36, zw=0.82, cs=0.08, ct=0.10, cb=0.05, cw=0.03, cam=0.02)
    xs = merge_stations([end_stations(xf, 0.07, 4), end_stations(xb, 0.04, 2, True), [xf, xb], frange(0.2, 1.7, 0.3)], min_gap=0.03)
    shell = sect_loft(cv, xs, ncor=dict(A=1, B=1, C=2, D=3), r0=0.04, r1=0.07, smooth_passes=1)
    bm = shell.bm
    check_manifold(bm, 'hood')
    for f in bm.faces:
        f.material_index = mi('M_TrimBlack' if f.normal.z < -0.6 else 'M_Paint')
    surf = Surface(bm)
    cut = []
    gp = pocket_cutter(surf, outline_rrect(0.46, 0.42, 0.04, 3), Vector((2.2, 0.0, 1.06)), RAY_F, depth=0.07, taper=0.97, mat='M_TrimBlack', floor_follows=False)
    if gp is not None:
        cut.append(gp)
    lenses = []
    cs_, ls_ = lens_pair(surf, (2.2, 0.31, 1.20), RAY_F, outline_rrect(0.15, 0.12, 0.04, 3), 0.04, 'M_Headlight', lens_scale=0.95)
    cut += cs_
    lenses += ls_
    # hood centre seam + side louvres
    g = dir_groove(surf, [Vector((0.0, 0.0, 0)), Vector((1.75, 0.0, 0))], RAY_T, closed=False, step=0.08, name='hood seam')
    if g is not None:
        cut.append(g)
    for sd, ray in ((1, RAY_L), (-1, RAY_R)):
        for xx in (0.55, 0.64, 0.73, 0.82, 0.91):
            g = dir_groove(surf, [Vector((xx, sd * 1.0, 1.03)), Vector((xx, sd * 1.0, 1.26))], ray, closed=False, step=0.05, name='louvre')
            if g is not None:
                cut.append(g)
    body = bm_boolean(bm, cut)
    for l in lenses:
        put(body, l)
    g = grille_mesh(outline_rrect(0.42, 0.38, 0.03, 3), kind='bars', pitch=0.045, bar=0.018, depth=0.04, frame=0.012, mat='M_TrimGrey', frame_mat='M_TrimGrey')
    hit = surf.hit(Vector((2.2, 0.0, 1.06)), RAY_F)
    bmesh.ops.transform(g, matrix=Matrix.Translation(Vector((hit[0].x - 0.035, 0.0, 1.06))), verts=g.verts)
    put(body, g)
    # exhaust stack + cap, front weight, tow hook
    put(body, tube([Vector((0.40, -0.30, 1.40)), Vector((0.40, -0.30, 2.40))], 0.045, 'M_TrimGrey', sides=10))
    put(body, cyl(0.075, 0.02, (0.40, -0.30, 2.44), 'Z', 'M_TrimBlack', segs=10))
    put(body, box(0.30, 0.30, 0.20, (0.40, -0.30, 1.28), 'M_TrimGrey', bevel=0.03))
    put(body, box(0.14, 0.70, 0.46, (1.94, 0.0, 0.62), 'M_TrimGrey', bevel=0.03, seg=1))
    put(body, box(0.10, 0.52, 0.06, (1.98, 0.0, 0.40), 'M_Paint2', bevel=0.015))
    for sd in (1, -1):
        put(body, box(0.05, 0.12, 0.10, (1.95, sd * 0.36, 1.30), 'M_Indicator', bevel=0.012))
    return body


def build_chassis():
    ch = bmesh.new()
    put(ch, box_span(0.20, 1.80, -0.30, 0.30, 0.52, 1.00, 'M_TrimGrey', bevel=0.03, seg=1))             # engine block
    put(ch, box_span(-1.45, 0.25, -0.30, 0.30, 0.55, 1.10, 'M_TrimGrey', bevel=0.03, seg=1))            # gearbox
    put(ch, box_span(-0.30, 0.90, -0.60, 0.60, 1.18, 1.22, 'M_Paint2'))                                    # platform floor under the cab
    put(ch, bar_y(-0.72, 0.72, XF, P['R_f'], 0.07, 'M_TrimBlack', sides=10))
    put(ch, box_span(XF - 0.25, XF + 0.25, -0.20, 0.20, 0.42, 0.66, 'M_TrimGrey', bevel=0.03, seg=1))
    put(ch, bar_y(-0.68, 0.68, XR, P['R_r'], 0.11, 'M_TrimBlack', sides=12))
    put(ch, prim_sphere(0.28, u=12, v=8, center=(XR, 0.0, P['R_r']), mat='M_TrimGrey', scale=(1.0, 1.0, 0.9)))
    for sd in (1, -1):                                                                                   # rear fenders + front step
        put(ch, fender_shell(XR, P['R_r'], 0.86, 0.60, 0.03, arc=200.0, y_center=sd * 0.90, mat='M_Paint'))
        put(ch, box(0.30, 0.58, 0.035, (XR + 0.85, sd * 0.90, 1.52), 'M_Paint'))
        put(ch, box(0.48, 0.10, 0.20, (XR - 0.30, sd * 0.66, 1.66), 'M_TrimBlack', bevel=0.012))
        put(ch, box(0.015, 0.50, 0.32, (XR - 0.98, sd * 0.90, 0.58), 'M_Rubber'))
        for sy in (0.74, 1.06):
            put(ch, box(0.40, 0.04, 0.05, (XR + 0.75, sd * sy, 1.57), 'M_TrimGrey'))
    # drawbar hitch + 3-point linkage + PTO
    put(ch, box(0.80, 0.14, 0.04, (-1.76, 0.0, 0.60), 'M_TrimGrey', bevel=0.01))
    put(ch, box(0.12, 0.30, 0.14, (-1.45, 0.0, 0.64), 'M_TrimGrey', bevel=0.015))
    put(ch, cyl(0.022, 0.20, (-2.12, 0.0, 0.62), 'Z', 'M_TrimBlack', segs=8))
    for sd in (1, -1):
        put(ch, tube([Vector((-1.00, sd * 0.30, 0.56)), Vector((-1.85, sd * 0.52, 0.60))], 0.022, 'M_TrimGrey', sides=6))
        put(ch, prim_torus(R=0.045, r=0.012, seg_major=10, seg_minor=5, axis='Y', center=(-1.88, sd * 0.52, 0.60), mat='M_TrimGrey'))
        put(ch, tube([Vector((-1.30, sd * 0.58, 0.64)), Vector((-1.30, sd * 0.62, 1.22))], 0.016, 'M_TrimGrey', sides=6))
    put(ch, tube([Vector((-1.15, 0.0, 1.25)), Vector((-1.75, 0.0, 0.95))], 0.022, 'M_TrimGrey', sides=6))
    put(ch, cyl(0.028, 0.18, (-1.62, 0.0, 0.80), 'X', 'M_TrimGrey', segs=10))
    put(ch, cyl(0.045, 0.06, (-1.52, 0.0, 0.80), 'X', 'M_TrimBlack', segs=10))
    put(ch, box(0.35, 0.40, 0.20, (-0.55, -0.62, 1.00), 'M_TrimGrey', bevel=0.03))                         # fuel tank
    return ch


def build():
    v = new_vehicle(VID, INDEX, "Farm Tractor", wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=P['track_r'],
                    wheel_radius_front=P['R_f'], wheel_radius_rear=P['R_r'], wheel_width_front=P['W_f'], wheel_width_rear=P['W_r'],
                    ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], drivetrain='4WD')
    cab, glass, (fr_ws,) = build_cab()
    lap(v, "cab: %d tris" % tri_count(cab))
    hood = build_hood()
    lap(v, "hood: %d tris" % tri_count(hood))
    ch = build_chassis()
    lap(v, "chassis: %d tris" % tri_count(ch))
    body = bmesh.new()
    for part in (cab, hood, ch):
        put(body, part)
    it = bmesh.new()
    put(it, seat_block(-0.92, 0.0, 1.52, w=0.50, depth=0.48, back_h=0.60))
    put(it, driver_figure(-0.92, 0.0, 1.52, scale=0.95))
    put(it, steering_wheel(-0.42, 0.0, 1.88, r=0.20, tilt=62.0))
    put(it, box(0.30, 0.90, 0.40, (-0.28, 0.0, 1.48), 'M_IntDash', bevel=0.04, seg=2))
    put(it, box(0.50, 0.14, 0.34, (-0.70, -0.40, 1.40), 'M_IntTrim', bevel=0.02))
    for yy in (0.28, 0.40):
        put(it, tube([Vector((-0.78, yy, 1.30)), Vector((-0.74, yy, 1.62))], 0.012, 'M_TrimBlack', sides=5))
    hulls = [hull_pts([(1.95, 0.40, 0.55, 1.35), (0.20, 0.44, 0.50, 1.50), (-0.10, 0.50, 0.50, 1.55)]),
             hull_pts([(-0.10, 0.66, 1.10, 2.66), (-1.52, 0.66, 1.10, 2.66)]),
             hull_pts([(-0.10, 0.60, 0.50, 1.20), (-1.52, 0.60, 0.50, 1.20), (-2.10, 0.20, 0.55, 0.70)])]
    # one 16-sided "fender + big rear tyre" hull per side (r = fender radius 0.89, y = tyre/fender span), so traffic and the player
    # cannot drive into the huge rear wheels; z is clamped at the ground
    for sd in (1, -1):
        pts = []
        for yy in (0.62, 1.18):
            for k in range(16):
                a = 2 * math.pi * k / 16
                pts.append(Vector((XR + 0.89 * math.cos(a), sd * yy, max(0.0, P['R_r'] + 0.89 * math.sin(a)))))
        hulls.append(pts)
    ob = finish_core(v, body, glass, it, hulls)
    mn, mx = measure_root(v, ob, width=P['W'])
    lap(v, "core objects: body %d tris, size %.2f x %.2f x %.2f" % (tri_count(ob['body'].data), mx.x - mn.x, mx.y - mn.y, mx.z))

    specs = []
    kf = dict(kind='truck', rim_r=0.27, nuts=5, rim_mat='M_Paint2', cap_mat='M_RimDark', segs=28, rim_segs=24, hub_r=0.085, dish=0.03, lug_n=14, lug_h=0.05,
              hub_proud=0.04, style='steel', holes=5)
    kr = dict(kind='truck', rim_r=0.47, nuts=8, rim_mat='M_Paint2', cap_mat='M_RimDark', segs=36, rim_segs=28, hub_r=0.16, dish=0.08, lug_n=20, lug_h=0.095,
              hub_proud=0.07, nut_r=0.26, style='steel', holes=8)
    for key, x, y, R, W, sd, axle, steer, drv, kw in (('FL', XF, P['track_f'] / 2, P['R_f'], P['W_f'], 1, 0, True, True, kf),
                                                      ('FR', XF, -P['track_f'] / 2, P['R_f'], P['W_f'], -1, 0, True, True, kf),
                                                      ('RL', XR, P['track_r'] / 2, P['R_r'], P['W_r'], 1, 1, False, True, kr),
                                                      ('RR', XR, -P['track_r'] / 2, P['R_r'], P['W_r'], -1, 1, False, True, kr)):
        specs.append(dict(key=key, x=x, y=y, R=R, W=W, side=sd, axle=axle, steering=steer, driven=drv, order=len(specs), kw=dict(kw)))
    add_wheels(v, specs)
    make_empties(v, {'LP_HeadL': (1.96, 0.31, 1.20), 'LP_HeadR': (1.96, -0.31, 1.20), 'LP_TailL': (-1.60, 0.42, 2.69),
                     'LP_TailR': (-1.60, -0.42, 2.69), 'LP_Reverse': (-1.60, 0.0, 2.69), 'CAM_Cockpit': (-0.80, 0.0, 2.10),
                     'CAM_Bumper': (2.00, 0.0, 0.75), 'EXHAUST_1': (0.40, -0.30, 2.46)})
    lap(v, "wheels + empties")
    return v


def export_extra():
    return {"paint_variants": PAINT_VARIANTS,
            "paint_slots": {"M_Paint": "bonnet, fenders, cab roof band", "M_Paint2": "cab frame, wheel rims (accent colour)"},
            "traffic": {"role": "farm tractor (slow traffic on farm roads)", "cruise_speed_kmh": [12, 35], "mass_kg_hint": 5200, "drivetrain": "4WD"},
            "collision": {"recommended": "UCX hulls in the Body FBX (5 convex hulls: bonnet, cab, chassis + hitch, left and right rear fender/tyre blocks); wheels without collision",
                          "ucx_count": 5},
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
