"""
traffic01_compact.py - idempotent build of the traffic city hatchback (3.6 m, 5-door, rounded, 15" wheels).

Run in the verified Blender MCP session (localhost:9889):
    TRAFFIC_STAGE = "geometry"   # "geometry" | "uv_a" | "uv_b" | "uv_wheels" | "validate" | "export"
    exec(compile(open(r"<project>/Tools/blender/traffic/traffic01_compact.py", encoding="utf8").read(), "compact", "exec"), globals())
Car space: +X forward, +Y left, +Z up, origin on the ground under the middle of the wheelbase.  Staged at (14, 30, 0).
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

VID = "traffic01_compact"
INDEX = 1
STAGE = globals().get("TRAFFIC_STAGE", "geometry")

P = dict(L=3.60, W=1.62, H=1.50, wheelbase=2.35, track_f=1.40, track_r=1.38, R=0.295, WW=0.175, ride=0.15, x_front=1.80, x_rear=-1.80,
         rim_r=0.1905)
XF, XR = 1.175, -1.175
RAY_L, RAY_R, RAY_F, RAY_B, RAY_T = (0, -1, 0), (0, 1, 0), (-1, 0, 0), (1, 0, 0), (0, 0, -1)
PAINT_VARIANTS = paint_variants(("Citrus yellow", "#e6c21b", "#1c1d1f", 0.0, 0.26),
                                ("Teal", "#1f7a78", "#e8e8e8", 0.30, 0.25),
                                ("Cherry red", "#a8141e", "#1c1d1f", 0.35, 0.22))


def curves():
    ztk = fillet_profile([(-1.90, 0.76), (-1.40, 1.39), (-0.35, 1.50), (0.22, 1.47), (0.92, 0.93), (1.86, 0.80)],
                         [0, 0.55, 4.0, 0.40, 0.55, 0], step=0.01)
    ztc = as_curve(ztk)

    def zs(x):
        base = 0.94 + 0.03 * smoothstep(0.0, -1.2, x)
        hood = ztc(x) - 0.085
        t = smoothstep(1.05, 0.80, x)                  # cabin belt for x < 0.8, hood belt for x > 1.05
        z = hood + (base - hood) * t
        return min(z, ztc(x) - 0.075)

    def hwt(x):
        return 0.71 + (0.61 - 0.71) * smoothstep(1.05, 0.75, x) - 0.05 * smoothstep(-1.0, -1.7, x)

    def hw(x):
        return 0.81 - 0.065 * smoothstep(1.15, 1.80, x) - 0.085 * smoothstep(-1.05, -1.80, x)

    zb = as_curve([(-1.90, 0.32), (-1.70, 0.24), (-1.40, 0.175), (1.20, 0.175), (1.60, 0.21), (1.90, 0.29)])
    return dict(hw=hw, hwt=hwt, zt=ztk, zs=zs, zb=zb, hwb=lambda x: hw(x) - 0.05, zw=lambda x: zb(x) + 0.17,
                cs=lambda x: 0.10, ct=0.24, cb=0.10, cw=0.05, cam=0.045)


def build():
    v = new_vehicle(VID, INDEX, "City Compact", wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=P['track_r'],
                    wheel_radius_front=P['R'], wheel_radius_rear=P['R'], wheel_width_front=P['WW'], wheel_width_rear=P['WW'],
                    ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], drivetrain='FWD')
    cv = curves()
    r_t, r_n = 0.13, 0.12
    xs = merge_stations([end_stations(P['x_front'], r_n, 5), end_stations(P['x_rear'], r_t, 5, True), [P['x_front'], P['x_rear']],
                         frange(-1.62, 1.75, 0.08), [0.92, 0.20, -1.44, 0.85, 1.0]], min_gap=0.03)
    shell = sect_loft(cv, xs, ncor=dict(A=3, B=1, C=2, D=4), r0=r_t, r1=r_n, smooth_passes=5, smooth_strength=0.6)
    bm = shell.bm
    check_manifold(bm, 'shell')
    lap(v, "shell %d stations x %d pts, %d faces" % (len(xs), shell.ring_pts, len(bm.faces)))

    split_planes(bm, [((0, 0, 0.30), (0, 0, 1)), ((0, 0, 0.47), (0, 0, 1))])
    for f in bm.faces:
        c = f.calc_center_median()
        m = 'M_Paint'
        if f.normal.z < -0.6:
            m = 'M_TrimBlack'
        elif c.z < 0.30:
            m = 'M_TrimBlack'
        elif c.z < 0.47 and abs(c.x) > 1.30:
            m = 'M_Paint2'                              # bumper bands front / rear
        f.material_index = mi(m)
    surf0 = Surface(bm)

    cutters = []
    for (x, y) in ((XF, 1), (XF, -1), (XR, 1), (XR, -1)):
        cutters.append(wheel_arch_cutter(x, P['R'], P['R'] + 0.045, y, inner_y=0.40, outer_y=1.2, segments=28, mat='M_TrimBlack'))
    xs_void = [0.84 - 0.1 * i for i in range(0, 25)]                         # 0.84 ... -1.56
    cutters.append(inner_void(cv, xs_void, 0.04, 0.34, mat_wall='M_TrimGrey', mat_floor='M_TrimBlack'))

    # windscreen (plane through the cowl (0.92, 0.93) and the roof edge (0.20, 1.47))
    fr_ws = Frame(Vector((0.56, 0.0, 0.93 + (0.92 - 0.56) / 0.72 * 0.54)), Vector((0.54, 0.0, 0.72)), side_like=False)
    ws_out = round_poly(fr_ws.outline_world([(-0.56, 1.03), (0.56, 1.03), (0.50, 1.38), (-0.50, 1.38)]), 0.07, 3)
    cutters.append(win_cutter(fr_ws, ws_out, d_in=-0.28, d_out=0.10))
    # rear hatch glass (plane through (-1.44, 1.41) and (-1.84, 0.82))
    fr_rg = Frame(Vector((-1.65, 0.0, 1.075)), Vector((-0.63, 0.0, 0.50)), side_like=False)
    rg_out = round_poly(fr_rg.outline_world([(-0.44, 1.06), (0.44, 1.06), (0.40, 1.30), (-0.40, 1.30)]), 0.07, 3)
    cutters.append(win_cutter(fr_rg, rg_out, d_in=-0.28, d_out=0.10))
    # side windows: front door window + rear door window (left built, right mirrored by the loop)
    side_glass = []
    for sd in (1, -1):
        fr = side_frame(0.30, 0.805, 0.94, 0.62, 1.47, side=sd)
        o1 = round_poly(fr.outline_world([(0.64, 1.02), (0.02, 1.02), (0.02, 1.36), (0.25, 1.37)]), [0.03, 0.02, 0.04, 0.12], 3)
        o2 = round_poly(fr.outline_world([(-0.14, 1.02), (-0.95, 1.02), (-1.15, 1.26), (-1.04, 1.32), (-0.14, 1.36)]), [0.02, 0.02, 0.10, 0.04, 0.03], 3)
        for o in (o1, o2):
            cutters.append(win_cutter(fr, o, d_in=-0.28, d_out=0.10))
            side_glass.append((fr, o))

    def seam(pts_xz, ray, y, closed=False, name='seam'):
        return dir_groove(surf0, [Vector((p[0], y, p[1])) for p in pts_xz], ray, closed=closed, name=name)

    for sd, ray in ((1, RAY_L), (-1, RAY_R)):
        for nm, pts in (('door_f', [(0.80, 0.98), (0.80, 0.40)]), ('door_b', [(-0.06, 1.38), (-0.06, 0.40)]), ('door_r', [(-0.93, 1.00), (-0.93, 0.40)])):
            g = seam(pts, ray, sd * 1.5, name=nm)
            if g is not None:
                cutters.append(g)
    hood = [Vector((0.98, 0.52, 0)), Vector((1.52, 0.56, 0)), Vector((1.60, 0.50, 0)), Vector((1.60, -0.50, 0)), Vector((1.52, -0.56, 0)),
            Vector((0.98, -0.52, 0))]
    for g in (dir_groove(surf0, hood, RAY_T, closed=False, step=0.05, name='hood'),
              dir_groove(surf0, [(-2.0, 0.58, 0.60), (-2.0, 0.58, 0.82)], RAY_B, closed=False, name='hatch_l'),
              dir_groove(surf0, [(-2.0, -0.58, 0.60), (-2.0, -0.58, 0.82)], RAY_B, closed=False, name='hatch_r'),
              dir_groove(surf0, [(-2.0, 0.58, 0.60), (-2.0, -0.58, 0.60)], RAY_B, closed=False, name='hatch_low')):
        if g is not None:
            cutters.append(g)

    lenses = []
    cs_, ls_ = lens_pair(surf0, (2.0, 0.50, 0.625), RAY_F, outline_rrect(0.36, 0.15, 0.055, 3), 0.05, 'M_Headlight', lens_scale=0.95,
                         bulge=0.016, rings=4, floor='M_Chrome')                 # domed lens over a chrome reflector bowl
    cutters += cs_
    lenses += ls_
    cs_, ls_ = lens_pair(surf0, (2.0, 0.50, 0.505), RAY_F, outline_rrect(0.30, 0.040, 0.018, 3), 0.035, 'M_Indicator', lens_scale=0.95)
    cutters += cs_
    lenses += ls_
    cs_, ls_ = lens_pair(surf0, (-2.1, 0.60, 0.64), RAY_B, outline_rrect(0.14, 0.20, 0.04, 3), 0.04, 'M_Taillight', lens_scale=0.95, bulge=0.010, rings=4)
    cutters += cs_
    lenses += ls_
    cs_, ls_ = lens_pair(surf0, (-2.1, 0.60, 0.50), RAY_B, outline_rrect(0.14, 0.06, 0.02, 3), 0.035, 'M_Indicator', lens_scale=0.95)
    cutters += cs_
    lenses += ls_
    gp = pocket_cutter(surf0, outline_rrect(0.54, 0.09, 0.03, 3), Vector((2.0, 0.0, 0.395)), RAY_F, depth=0.05, taper=0.95, mat='M_TrimBlack',
                       floor_follows=False)
    if gp is not None:
        cutters.append(gp)
    pc, plate = plate_recess(surf0, Vector((-2.1, 0.0, 0.52)), RAY_B)       # rear plate recess
    if pc is not None:
        cutters.append(pc)
    lap(v, "cutters ready: %d" % len(cutters))

    body = bm_boolean(bm, cutters)
    lap(v, "boolean done: %d faces, %d tris" % (len(body.faces), tri_count(body)))

    for l in lenses:
        put(body, l)
    if plate is not None:
        put(body, plate)
    g = grille_mesh(outline_rrect(0.50, 0.085, 0.025, 3), kind='bars', pitch=0.026, bar=0.008, depth=0.025, frame=0.010, mat='M_TrimGrey',
                    frame_mat='M_TrimGrey')
    hit = surf0.hit(Vector((2.0, 0.0, 0.395)), RAY_F)
    bmesh.ops.transform(g, matrix=Matrix.Translation(Vector((hit[0].x - 0.028, 0.0, 0.395))), verts=g.verts)
    put(body, g)
    pf = plate_quad(hit[0].x + 0.0, 0.0, 0.52, 0.46, 0.10)
    surf_hit = surf0.hit(Vector((2.0, 0.0, 0.53)), RAY_F)
    pf = plate_quad(surf_hit[0].x + 0.003, 0.0, 0.53, 0.46, 0.10)
    put(body, pf)
    # mirrors
    mir = build_mirror(side=+1, length=0.16, width=0.09, height=0.105, mat_shell='M_Paint2', mat_glass='M_TrimGrey', arm_len=0.05)
    bmesh.ops.transform(mir, matrix=Matrix.Translation(Vector((0.66, 0.77, 0.99))), verts=mir.verts)
    put_pair(body, mir)
    for sd, ray in ((1, RAY_L), (-1, RAY_R)):
        for x in (0.30, -0.55):
            h = door_handle(surf0, x, 0.84, ray, length=0.12, width=0.024, height=0.013)
            if h is not None:
                put(body, h)
    for sd, ray in ((1, RAY_L), (-1, RAY_R)):                              # door protection strips
        rs_ = rib_line(surf0, [Vector((x, sd * 1.5, 0.56)) for x in (-0.80, -0.1, 0.6)], ray, 0.06, 0.013, step=0.2, name='rub')
        if rs_ is not None:
            put(body, rs_)
    for (x, sd, ray) in ((XF, 1, RAY_L), (XF, -1, RAY_R), (XR, 1, RAY_L), (XR, -1, RAY_R)):
        am = arch_moulding(surf0, x, P['R'], P['R'] + 0.06, ray, a0=15, a1=165, n=16, width=0.045, height=0.012)
        if am is not None:
            put(body, am)
    # wipers (parked), exhaust tip, roof antenna
    for sd in (1, -1):
        put(body, tube([fr_ws.pt(sd * 0.50, -0.30, 0.016), fr_ws.pt(sd * 0.02, -0.26, 0.016)], 0.0065, 'M_TrimBlack', sides=5))
    put(body, tube([fr_rg.pt(0.0, -0.20, 0.014), fr_rg.pt(-0.0, 0.0, 0.014)], 0.0055, 'M_TrimBlack', sides=5))
    put(body, tube([Vector((-1.58, 0.45, 0.30)), Vector((-1.835, 0.45, 0.30))], 0.030, 'M_TrimGrey', sides=10))
    put(body, tube([Vector((-0.95, 0.0, 1.46)), Vector((-0.98, 0.0, 1.62))], 0.006, 'M_TrimBlack', sides=5))
    lap(v, "add-ons done: %d tris" % tri_count(body))
    surf0 = None

    glass = bmesh.new()
    put(glass, win_glass(fr_ws, ws_out))
    put(glass, win_glass(fr_rg, rg_out))
    for fr, out in side_glass:
        put(glass, win_glass(fr, out))

    it = bmesh.new()
    put(it, seat_block(0.28, 0.36, 0.55, w=0.46, depth=0.46, back_h=0.52))
    put(it, seat_block(0.28, -0.36, 0.55, w=0.46, depth=0.46, back_h=0.52))
    put(it, seat_block(-0.62, 0.0, 0.55, w=1.25, depth=0.44, back_h=0.46, headrest=False))
    put(it, box(0.30, 1.40, 0.34, (0.72, 0.0, 0.64), 'M_IntDash', bevel=0.05, seg=2))
    put(it, box(0.20, 0.50, 0.10, (0.66, 0.36, 0.86), 'M_IntDash', bevel=0.03, seg=2))
    put(it, box(0.50, 0.22, 0.14, (0.42, 0.0, 0.42), 'M_IntTrim', bevel=0.03, seg=1))
    put(it, steering_wheel(0.52, 0.36, 0.80, r=0.17, tilt=26.0))
    put(it, driver_figure(0.28, 0.36, 0.55, scale=0.95))

    hulls = [hull_pts([(-1.78, 0.74, 0.32, 0.80), (-1.40, 0.80, 0.22, 1.40), (0.20, 0.80, 0.19, 1.45)]),
             hull_pts([(0.20, 0.80, 0.19, 1.45), (0.92, 0.72, 0.19, 0.93), (1.78, 0.68, 0.30, 0.66)])]
    ob = finish_core(v, body, glass, it, hulls, remap={'M_Chrome': 'M_TrimGrey'})
    mn, mx = measure_root(v, ob, width=1.62)
    lap(v, "core objects: body %d tris, size %.2f x %.2f x %.2f" % (tri_count(ob['body'].data), mx.x - mn.x, mx.y - mn.y, mx.z))

    specs = []
    for key, x, sd, axle, steer, driven in (('FL', XF, 1, 0, True, True), ('FR', XF, -1, 0, True, True), ('RL', XR, 1, 1, False, False),
                                            ('RR', XR, -1, 1, False, False)):
        tr = P['track_f'] if axle == 0 else P['track_r']
        specs.append(dict(key=key, x=x, y=sd * tr / 2, R=P['R'], W=P['WW'], side=sd, axle=axle, steering=steer, driven=driven, order=len(specs),
                          kw=dict(kind='car', rim_r=P['rim_r'], nuts=4, rim_mat='M_Rim', cap_mat='M_Rim', segs=28, rim_segs=24, hub_r=0.064, dish=0.035, style='alloy', spokes=5)))
    add_wheels(v, specs)
    make_empties(v, {'LP_HeadL': (1.84, 0.50, 0.65), 'LP_HeadR': (1.84, -0.50, 0.65), 'LP_TailL': (-1.84, 0.60, 0.74),
                     'LP_TailR': (-1.84, -0.60, 0.74), 'LP_Reverse': (-1.84, 0.0, 0.62), 'CAM_Cockpit': (0.40, 0.36, 1.18),
                     'CAM_Bumper': (1.90, 0.0, 0.45), 'EXHAUST_L': (-1.94, 0.45, 0.30)})
    lap(v, "wheels + empties")
    return v


def export_extra():
    return {"paint_variants": PAINT_VARIANTS,
            "paint_slots": {"M_Paint": "body panels, doors, roof", "M_Paint2": "bumper bands + mirror caps (accent, satin black by default)"},
            "traffic": {"role": "city car", "cruise_speed_kmh": [30, 80], "mass_kg_hint": 950, "drivetrain": "FWD"},
            "collision": {"recommended": "UCX hulls in the Body FBX (2 convex hulls); wheels without collision (vehicle physics)", "ucx_count": 2},
            "ue_scale_range": [0.96, 1.04]}


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
