"""
traffic02_van.py - idempotent build of the traffic panel van (5.4 m, high roof, sliding door on the right, rear barn doors, roof rack).

Run in the verified Blender MCP session (localhost:9889):
    TRAFFIC_STAGE = "geometry"   # "geometry" | "uv_a" | "uv_b" | "uv_wheels" | "validate" | "export"
    exec(compile(open(r"<project>/Tools/blender/traffic/traffic02_van.py", encoding="utf8").read(), "van", "exec"), globals())
Car space: +X forward, +Y left, +Z up, origin on the ground under the middle of the wheelbase.  Staged at (28, 30, 0).
Built from Tools/blender/lib/carkit.py + carkit_ext_traffic.py: section loft + ONE boolean (hollow cab, window openings, wheel arches,
panel seams, lamp pockets) + add-ons (bumpers, mirrors, rack ...).
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

VID = "traffic02_van"
INDEX = 2
STAGE = globals().get("TRAFFIC_STAGE", "geometry")

P = dict(L=5.40, W=2.00, H=2.30, wheelbase=3.20, track=1.70, R=0.343, WW=0.215, ride=0.31, x_front=2.43, x_rear=-2.70,
         hw=1.0, rim_r=0.2032)
XF, XR = 1.60, -1.60                      # axle x positions (middle of the wheelbase = 0)
RAY_L, RAY_R, RAY_F, RAY_B, RAY_T = (0, -1, 0), (0, 1, 0), (-1, 0, 0), (1, 0, 0), (0, 0, -1)
PAINT_VARIANTS = paint_variants(("Delivery white", "#e8e9ea", "#2a2d31", 0.0, 0.30),
                                ("Courier blue", "#1f4f8f", "#e8e9ea", 0.25, 0.28),
                                ("Post yellow", "#e0b21c", "#202224", 0.0, 0.32))


def export_extra():
    return {"paint_variants": PAINT_VARIANTS,
            "paint_slots": {"M_Paint": "body panels, doors, roof", "M_Paint2": "bumpers (accent colour, satin black by default)"},
            "traffic": {"role": "delivery van", "cruise_speed_kmh": [40, 90], "mass_kg_hint": 2300, "drivetrain": "FWD",
                        "sliding_door_side": "right (-Y in UE)", "roof_rack": True},
            "collision": {"recommended": "UCX hulls in the Body FBX (3 convex hulls); wheels without collision (vehicle physics)",
                          "ucx_count": 3},
            "ue_scale_range": [0.97, 1.03],
            "dimensions_note": "dimensions.height includes the roof rack; the cargo roof is 2.30 m (ROOT height_roof)",
            "height_roof": 2.30}


def curves():
    """Side profile (top line zt), belt line zs and plan-view widths of the shell."""
    ztk = fillet_profile([(-2.95, 2.30), (0.62, 2.30), (1.40, 1.12), (2.62, 0.98)], [0, 0.35, 0.45, 0], step=0.01)
    ztc = as_curve(ztk)

    def zs(x):
        hood = ztc(x) - 0.13
        t = smoothstep(1.50, 1.12, x)
        return hood + (1.22 - hood) * t

    def hwt(x):
        return 0.80 + 0.08 * smoothstep(1.46, 1.10, x)

    def hw(x):
        return 1.0 - 0.035 * smoothstep(2.0, 2.55, x)

    zb = as_curve([(-2.95, 0.46), (-2.70, 0.40), (-2.30, 0.31), (2.0, 0.31), (2.35, 0.34), (2.60, 0.42)], mode='pchip')
    return dict(hw=hw, hwt=hwt, zt=ztk, zs=zs, zb=zb, hwb=lambda x: hw(x) - 0.03,
                cs=lambda x: 0.12 - 0.07 * smoothstep(1.4, 1.0, x), ct=lambda x: 0.12, cb=0.07, cw=0.02, cam=0.0)


def build():
    v = new_vehicle(VID, INDEX, "Panel Van", wheelbase=P['wheelbase'], track_front=P['track'], track_rear=P['track'],
                    wheel_radius_front=P['R'], wheel_radius_rear=P['R'], wheel_width_front=P['WW'], wheel_width_rear=P['WW'],
                    ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], drivetrain='FWD')
    cv = curves()
    xs = merge_stations([end_stations(P['x_front'], 0.11, 5), end_stations(P['x_rear'], 0.11, 5, True), [P['x_front'], P['x_rear']],
                         frange(P['x_rear'] + 0.45, -0.1, 0.5), frange(0.0, 1.6, 0.08), [0.62, 0.52, 1.12, 1.40, 1.50],
                         frange(1.7, P['x_front'] - 0.2, 0.2)], min_gap=0.03)
    shell = sect_loft(cv, xs, r0=0.11, r1=0.11, smooth_passes=3, smooth_strength=0.6)
    bm = shell.bm
    check_manifold(bm, 'shell')
    lap(v, "shell %d stations x %d pts, %d faces" % (len(xs), shell.ring_pts, len(bm.faces)))

    # ---- material zones: split the shell at z=0.56 (sill / bumper band) then colour by position ------------------------
    split_planes(bm, [((0, 0, 0.56), (0, 0, 1))])
    for f in bm.faces:
        c = f.calc_center_median()
        m = 'M_Paint'
        if f.normal.z < -0.6 or c.z < 0.56:
            m = 'M_TrimBlack'                       # underbody, sill cladding
        f.material_index = mi(m)
    surf0 = Surface(bm)

    # ---- cutters ----------------------------------------------------------------------------------------------------
    cutters = []
    for (x, y) in ((XF, 1), (XF, -1), (XR, 1), (XR, -1)):
        cutters.append(wheel_arch_cutter(x, P['R'], P['R'] + 0.055, y, inner_y=0.46, outer_y=1.3, segments=28, mat='M_TrimBlack'))

    xs_void = [1.34 - 0.1 * i for i in range(0, 17)]                        # 1.34 ... -0.26
    cutters.append(inner_void(cv, xs_void, 0.045, 0.52, mat_wall='M_TrimGrey', mat_floor='M_TrimBlack'))

    # windscreen on the raked top face + two door windows
    nws = Vector((1.16, 0.0, 0.78))
    fr_ws = Frame(Vector((1.0, 0.0, 1.12 + (1.40 - 1.0) / 0.78 * 1.16)), nws, side_like=False)
    ws_out = round_poly(fr_ws.outline_world([(-0.70, 1.37), (0.70, 1.37), (0.755, 2.10), (-0.755, 2.10)]), 0.10, 3)
    cutters.append(win_cutter(fr_ws, ws_out, d_in=-0.30, d_out=0.12))
    side_glass = []
    for sd in (1, -1):
        fr = side_frame(0.6, 1.0, 1.22, 0.88, 2.30, side=sd)
        out = round_poly(fr.outline_world([(1.17, 1.31), (0.14, 1.31), (0.14, 2.08), (0.66, 2.08)]), [0.05, 0.03, 0.05, 0.12], 3)
        cutters.append(win_cutter(fr, out, d_in=-0.30, d_out=0.12))
        side_glass.append((fr, out))

    # panel seams (grooves)
    def seam(pts_xz, ray, y, closed=True):
        pp = [Vector((p[0], y, p[1])) for p in pts_xz]
        return dir_groove(surf0, pp, ray, closed=closed)

    front_door = [(1.19, 1.26), (1.20, 0.58), (0.10, 0.58), (0.10, 2.12), (0.60, 2.12)]
    for g in (seam(front_door, RAY_L, 1.5, closed=False), seam(front_door, RAY_R, -1.5, closed=False),
              seam([(0.02, 0.58), (0.02, 2.12), (-1.50, 2.12), (-1.50, 0.58)], RAY_R, -1.5)):               # sliding door (right)
        if g is not None:
            cutters.append(g)
    hood = [Vector((1.42, 0.70, 0)), Vector((2.26, 0.74, 0)), Vector((2.37, 0.66, 0)), Vector((2.37, -0.66, 0)), Vector((2.26, -0.74, 0)),
            Vector((1.42, -0.70, 0))]
    for g in (dir_groove(surf0, hood, RAY_T, closed=False, step=0.05),
              dir_groove(surf0, [(-3.0, 0.0, 0.62), (-3.0, 0.0, 2.14)], RAY_B, closed=False, step=0.05),               # barn door seam
              dir_groove(surf0, [(-3.0, 0.80, 0.62), (-3.0, 0.80, 2.14), (-3.0, -0.80, 2.14), (-3.0, -0.80, 0.62)], RAY_B, closed=True, step=0.05),
              dir_groove(surf0, circle_pts(-1.90, 0.98, 0.085, n=24, y=1.5), RAY_L, closed=True, step=0.03)):         # fuel flap
        if g is not None:
            cutters.append(g)

    lenses = []
    for (cl, outline, depth, mat) in (((2.7, 0.60, 0.82), outline_rrect(0.40, 0.17, 0.05, 3), 0.05, 'M_Headlight'),
                                      ((2.7, 0.60, 0.63), outline_rrect(0.40, 0.065, 0.02, 3), 0.04, 'M_Indicator')):
        cs_, ls_ = lens_pair(surf0, cl, RAY_F, outline, depth, mat)
        cutters += cs_
        lenses += ls_
    for (cl, outline, mat) in (((-3.0, 0.78, 1.16), outline_rrect(0.14, 0.34, 0.03, 3), 'M_Taillight'),
                               ((-3.0, 0.78, 0.89), outline_rrect(0.14, 0.12, 0.025, 3), 'M_Indicator')):
        cs_, ls_ = lens_pair(surf0, cl, RAY_B, outline, 0.04, mat)
        cutters += cs_
        lenses += ls_
    gp = pocket_cutter(surf0, outline_rrect(0.64, 0.20, 0.045, 3), Vector((2.7, 0.0, 0.70)), RAY_F, depth=0.06, taper=0.95, mat='M_TrimBlack',
                       floor_follows=False)
    if gp is not None:
        cutters.append(gp)
    lap(v, "cutters ready: %d" % len(cutters))

    body = bm_boolean(bm, cutters)
    lap(v, "boolean done: %d faces, %d tris" % (len(body.faces), tri_count(body)))

    # ---- add-ons ----------------------------------------------------------------------------------------------------
    for l in lenses:
        put(body, l)
    g = grille_mesh(outline_rrect(0.60, 0.16, 0.04, 3), kind='bars', pitch=0.034, bar=0.009, depth=0.03, frame=0.012, mat='M_TrimGrey',
                    frame_mat='M_TrimGrey')
    bmesh.ops.transform(g, matrix=Matrix.Translation(Vector((2.40, 0.0, 0.70))), verts=g.verts)
    put(body, g)
    # bumpers
    put(body, box(0.22, 1.96, 0.27, (2.445, 0.0, 0.50), 'M_Paint2', bevel=0.075, seg=3))
    put(body, box(0.22, 1.96, 0.20, (-2.75, 0.0, 0.50), 'M_Paint2', bevel=0.05, seg=3))
    put(body, box(0.16, 1.55, 0.016, (-2.78, 0.0, 0.608), 'M_TrimBlack'))
    put(body, plate_quad(2.559, 0.0, 0.50, 0.50, 0.11))
    put(body, plate_quad(-2.704, 0.0, 0.80, 0.50, 0.11))
    # fog lamps in the bumper
    for sd in (1, -1):
        put(body, box(0.02, 0.14, 0.06, (2.553, sd * 0.70, 0.46), 'M_Headlight', bevel=0.01, seg=1))
    # mirrors (left built, right mirrored)
    mir = mirror_arm((1.20, 0.98, 1.50), (1.14, 1.16, 1.58), (1.13, 1.22, 1.60), (0.075, 0.10, 0.27), mat_head='M_TrimBlack', mat_glass='M_TrimGrey')
    put_pair(body, mir)
    # door handles
    for sd, ray in ((1, RAY_L), (-1, RAY_R)):
        h = door_handle(surf0, 0.30, 1.08, ray, length=0.16, width=0.03, height=0.016)
        if h is not None:
            put(body, h)
    h = door_handle(surf0, -0.20, 1.10, RAY_R, length=0.18, width=0.03, height=0.016)
    if h is not None:
        put(body, h)
    for sd in (1, -1):
        put(body, bar_z(0.98, 1.20, -2.712, sd * 0.07, 0.014, 'M_TrimBlack', sides=6))
    # sliding-door rail + rub strips
    pts = [Vector((x, -1.5, 1.13)) for x in (-1.5, -2.0, -2.5, -2.56)]
    rail = rib_line(surf0, pts, RAY_R, 0.05, 0.014, step=0.25, name='rail')
    if rail is not None:
        put(body, rail)
    for sd, ray, x0, x1 in ((1, RAY_L, -2.56, -0.05), (-1, RAY_R, -2.56, -1.58)):
        pts = [Vector((x, sd * 1.5, 0.86)) for x in (x0, (x0 + x1) / 2, x1)]
        rs = rib_line(surf0, pts, ray, 0.07, 0.014, step=0.3, name='rub')
        if rs is not None:
            put(body, rs)
    # body-colour belt bead on the cargo sides
    for sd, ray, x0, x1 in ((1, RAY_L, -2.56, -0.02), (-1, RAY_R, -2.56, -1.56)):
        bead = rib_line(surf0, [Vector((x, sd * 1.5, 1.42)) for x in (x0, (x0 + x1) / 2, x1)], ray, 0.05, 0.012, step=0.3, mat='M_Paint', name='bead')
        if bead is not None:
            put(body, bead)
    # arch mouldings
    for (x, sd, ray) in ((XF, 1, RAY_L), (XF, -1, RAY_R), (XR, 1, RAY_L), (XR, -1, RAY_R)):
        am = arch_moulding(surf0, x, P['R'], P['R'] + 0.075, ray, a0=10, a1=170, n=22, width=0.06, height=0.016)
        if am is not None:
            put(body, am)
    # exhaust tail pipe
    put(body, tube([Vector((-2.45, 0.55, 0.37)), Vector((-2.88, 0.55, 0.36))], 0.038, 'M_TrimGrey', sides=10))
    # wipers (parked) on the windscreen plane
    for sd in (1, -1):
        p0 = fr_ws.pt(sd * 0.60, -0.41, 0.02)
        p1 = fr_ws.pt(sd * 0.02, -0.36, 0.02)
        put(body, tube([p0, p1], 0.007, 'M_TrimBlack', sides=5))
        put(body, tube([fr_ws.pt(sd * 0.56, -0.375, 0.016), fr_ws.pt(sd * 0.02, -0.33, 0.016)], 0.0055, 'M_TrimBlack', sides=4))
    # roof rack + vent
    zr = 2.30 + 0.12
    for sd in (1, -1):
        put(body, bar_x(-2.45, 0.28, sd * 0.72, zr, 0.018, 'M_TrimGrey', sides=6))
    for x in (0.28, -0.30, -0.90, -1.50, -2.10, -2.45):
        put(body, bar_y(-0.72, 0.72, x, zr, 0.016, 'M_TrimGrey', sides=6))
    for x in (0.28, -0.90, -2.10, -2.45):
        for sd in (1, -1):
            put(body, bar_z(2.28, zr, x, sd * 0.72, 0.016, 'M_TrimGrey', sides=6))
    put(body, cyl(0.032, 1.46, (-2.52, 0.0, zr + 0.01), 'Y', 'M_TrimBlack', segs=10))                 # rear roller
    put(body, box(0.55, 0.42, 0.07, (-1.30, 0.0, 2.33), 'M_Paint2', bevel=0.025, seg=2))               # roof vent
    lap(v, "add-ons done: %d tris" % tri_count(body))
    surf0 = None

    # ---- glass ------------------------------------------------------------------------------------------------------
    glass = bmesh.new()
    put(glass, win_glass(fr_ws, ws_out))
    for fr, out in side_glass:
        put(glass, win_glass(fr, out))

    # ---- interior (dark cabin) ---------------------------------------------------------------------------------------
    it = bmesh.new()
    put(it, seat_block(0.50, 0.46, 0.90, w=0.52, depth=0.52, back_h=0.62))
    put(it, seat_block(0.50, -0.40, 0.90, w=0.98, depth=0.52, back_h=0.62, headrest=False))
    put(it, box(0.36, 1.88, 0.40, (1.15, 0.0, 0.90), 'M_IntDash', bevel=0.05, seg=2))                  # dash
    put(it, box(0.24, 0.60, 0.13, (1.08, 0.46, 1.17), 'M_IntDash', bevel=0.04, seg=2))                  # binnacle
    put(it, box(0.30, 0.26, 0.46, (0.90, 0.0, 0.76), 'M_IntTrim', bevel=0.03, seg=1))                  # tunnel / console
    put(it, steering_wheel(0.92, 0.46, 1.10, r=0.20, tilt=30.0))
    put(it, driver_figure(0.50, 0.46, 0.90))
    lap(v, "glass + interior")

    # ---- collision hulls ---------------------------------------------------------------------------------------------
    hulls = [hull_pts([(-2.69, 0.90, 0.45, 2.26), (0.30, 0.98, 0.32, 2.30)]),
             hull_pts([(0.30, 0.98, 0.32, 2.30), (0.64, 0.86, 0.32, 2.28), (1.40, 0.80, 0.32, 1.13)]),
             hull_pts([(1.40, 0.92, 0.32, 1.13), (2.40, 0.90, 0.40, 0.98)])]
    ob = finish_core(v, body, glass, it, hulls)
    mn, mx = measure_root(v, ob, width=2.0)
    v.root['height_roof'] = 2.30                         # cargo roof; the reported height (2.46 m) includes the roof rack
    lap(v, "core objects: body %d tris, size %.2f x %.2f x %.2f" % (tri_count(ob['body'].data), mx.x - mn.x, mx.y - mn.y, mx.z))

    # ---- wheels ------------------------------------------------------------------------------------------------------
    specs = []
    for key, x, sd, axle, steer, driven in (('FL', XF, 1, 0, True, True), ('FR', XF, -1, 0, True, True), ('RL', XR, 1, 1, False, False),
                                            ('RR', XR, -1, 1, False, False)):
        specs.append(dict(key=key, x=x, y=sd * P['track'] / 2, R=P['R'], W=P['WW'], side=sd, axle=axle, steering=steer, driven=driven, order=len(specs),
                          kw=dict(kind='car', rim_r=P['rim_r'], nuts=5, rim_mat='M_Rim', cap_mat='M_TrimGrey', segs=32, rim_segs=28, hub_r=0.075, dish=0.03, style='steel', holes=5)))
    add_wheels(v, specs)

    # ---- empties -----------------------------------------------------------------------------------------------------
    make_empties(v, {'LP_HeadL': (2.45, 0.60, 0.82), 'LP_HeadR': (2.45, -0.60, 0.82), 'LP_TailL': (-2.72, 0.78, 1.16),
                     'LP_TailR': (-2.72, -0.78, 1.16), 'LP_Reverse': (-2.72, 0.0, 0.88), 'CAM_Cockpit': (0.62, 0.46, 1.62),
                     'CAM_Bumper': (2.58, 0.0, 0.55), 'EXHAUST_L': (-2.88, 0.55, 0.36)})
    lap(v, "wheels + empties")
    return v


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
elif STAGE == "all":
    v = build()
