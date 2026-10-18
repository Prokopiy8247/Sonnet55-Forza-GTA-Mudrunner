"""
car08_suv_ranger.py - parametric, idempotent build of player car #8 "Ranger" (tall boxy off-road SUV, AWD, LHD).
Built with the shared car kit (Tools/blender/lib/carkit.py + my helpers Tools/blender/lib/carkit_ext_08_09_10.py).

Run inside the verified Blender MCP session (localhost:9889):
    CAR08_STAGE = "all"      # optional: "geometry" | "uv1" | "uv2" | "all" (default)
    exec(compile(open(r"<project>/Tools/blender/cars/car08_suv_ranger.py", encoding="utf8").read(), "car08", "exec"), globals())
Car space: +X forward, +Y left (driver side, LHD), +Z up; origin on the ground under the middle of the wheelbase.
Staged at x = 96 m (cars row, index 8), collection FORZA_UE/Cars/car08_suv_ranger, root car08_suv_ranger_ROOT.
"""
import os
import time
import math
import bpy
import bmesh
from mathutils import Vector, Matrix

_PROJECT = os.path.dirname(bpy.data.filepath)
_KIT = os.path.join(_PROJECT, "Tools", "blender", "lib", "carkit.py")
_EXT = os.path.join(_PROJECT, "Tools", "blender", "lib", "carkit_ext_08_09_10.py")
exec(compile(open(_KIT, encoding="utf8").read(), _KIT, "exec"), globals())
exec(compile(open(_EXT, encoding="utf8").read(), _EXT, "exec"), globals())

CAR = "car08_suv_ranger"
STAGE = globals().get("CAR08_STAGE", "all")

P = dict(
    id=CAR, display_name="Ranger", index=8,
    L=4.60, W=1.92, H=1.92, wheelbase=2.78, track_f=1.64, track_r=1.64,
    r_f=0.40, r_r=0.40, w_f=0.265, w_r=0.265, ride=0.30,
    x_end=2.17, x_start=-2.00, cap_bulge=0.006,
    x_ws_base=0.80, x_ws_top=0.20,
    roof_z=1.806,
)
XF, XR = P['wheelbase'] / 2, -P['wheelbase'] / 2
WHEELS = {
    'FL': dict(center=(XF, P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=1),
    'FR': dict(center=(XF, -P['track_f'] / 2, P['r_f']), radius=P['r_f'], width=P['w_f'], side=-1),
    'RL': dict(center=(XR, P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=1),
    'RR': dict(center=(XR, -P['track_r'] / 2, P['r_r']), radius=P['r_r'], width=P['w_r'], side=-1),
}
ARCH_PAD = 0.062
GROOVE = groove_profile(0.0055, 0.007)
RIM_R, RIM_W = 0.205, 0.215          # 16" steel/alloy, tyre 265/75 R16 (outer radius 0.40)
VL = Vector((0, 0, 1))
RAY_L, RAY_F, RAY_R = (0, -1, 0), (-1, 0, 0), (1, 0, 0)


def body_curves():
    zt = fillet_profile([(-2.00, 1.690), (-1.940, 1.800), (-1.80, P['roof_z']), (0.34, P['roof_z']), (0.80, 1.150), (2.02, 1.135),
                         (2.18, 1.030)], [0, 0.06, 0.05, 0.40, 0.18, 0.20, 0], step=0.01)
    zf = smooth_keys([(-2.00, 0.56), (-1.92, 0.52), (-1.70, 0.40), (-1.55, 0.33), (-1.2, 0.30), (-0.5, 0.29), (0.5, 0.29), (1.2, 0.30),
                      (1.65, 0.34), (1.95, 0.46), (2.10, 0.52), (2.18, 0.55)], sigma=0.07)
    hwm = smooth_keys([(-2.00, 0.84), (-1.95, 0.890), (-1.85, 0.924), (-1.5, 0.928), (1.6, 0.928), (1.95, 0.922), (2.10, 0.900),
                       (2.17, 0.85)], sigma=0.06)
    zw = smooth_keys([(-2.0, 0.64), (-1.6, 0.58), (1.6, 0.58), (2.18, 0.66)], sigma=0.12)
    zb = smooth_keys([(-2.0, 1.10), (-1.9, 1.118), (-1.6, 1.125), (0.5, 1.125), (0.9, 1.11), (1.4, 1.07), (2.0, 1.01), (2.18, 0.97)],
                     sigma=0.11)
    zc = smooth_keys([(-2.0, 0.80), (-1.5, 0.80), (1.5, 0.80), (2.18, 0.80)], sigma=0.2)
    cdepth = smooth_keys([(-2.0, 0.0), (-1.85, 0.007), (-1.6, 0.028), (-1.0, 0.036), (0.8, 0.036), (1.6, 0.028), (2.0, 0.008), (2.18, 0.0)],
                         sigma=0.1)                                              # fix round 2: shoulder crease 3.6 cm deep (was 2.0 cm)
    hwe = smooth_keys([(-2.00, 0.77), (-1.92, 0.795), (-1.7, 0.80), (0.25, 0.80), (0.9, 0.872), (2.0, 0.880), (2.18, 0.80)], sigma=0.1)
    dz = as_curve(smooth_keys([(-2.0, 0.035), (-1.7, 0.04), (0.4, 0.035), (0.85, 0.05), (1.5, 0.065), (2.18, 0.07)], sigma=0.12))
    ztc, hwmc, zfc = as_curve(zt), as_curve(hwm), as_curve(zf)
    return dict(
        zf=zf, zt=zt, hwm=hwm, zw=zw, zb=zb, zc=zc, cdepth=cdepth, cwidth=0.03,
        hwe=hwe, ze=lambda x: ztc(x) - dz(x),
        hwb=lambda x: hwmc(x) - 0.008,
        zs=lambda x: zfc(x) + 0.09,
        belt_step=0.028, crease=0.014, rail_w=0.05,
    )


def bm_bounds_obj(ob):
    vs = [v.co for v in ob.data.vertices]
    return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
            Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def build():
    t0 = time.time()

    def lap(msg):
        print("[car08 %.2fs] %s" % (time.time() - t0, msg))

    remove_asset(CAR)
    build_standard_materials()
    col = ensure_collection("FORZA_UE/Cars/" + CAR)
    root = make_empty(CAR + "_ROOT", col, location=(12.0 * P['index'], 0, 0), display='ARROWS', size=0.6)
    set_root_props(root, wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=P['track_r'],
                   wheel_radius_front=P['r_f'], wheel_radius_rear=P['r_r'], wheel_width_front=P['w_f'], wheel_width_rear=P['w_r'],
                   ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], display_name=P['display_name'],
                   car_id=CAR, drivetrain="AWD", steering_side="LHD")

    # ------------------------------------------------------------------------------------------------------------------
    # 1. body shell loft
    # ------------------------------------------------------------------------------------------------------------------
    cv = body_curves()
    x0, x1 = P['x_start'], P['x_end']
    rr0, rr1 = 0.07, 0.10
    xs = station_list(x0, x1, dx=0.05, end_dx=0.02, end_len=0.26, min_gap=0.007,
                      extra=[P['x_ws_base'], P['x_ws_top'], 0.34, 0.80] + end_round_stations(x0, rr0, 5, at_start=True)
                      + end_round_stations(x1, rr1, 5, at_start=False))
    shell = loft_body(cv, xs, cap_bulge=P['cap_bulge'], ring_density=2.0, cap_rings=4, round_x0=rr0, round_x1=rr1)
    bm = shell.bm
    tc, ts = face_tags(bm)
    lap("loft %d stations, %d faces" % (len(xs), len(bm.faces)))

    under_cols, pillar_cols, roof_cols, rocker_cols, edgerail_cols = set(), set(), set(), set(), set()
    for sd in (1, -1):
        under_cols |= shell_quad_cols(shell, 'floor_c', 'sill', sd)
        pillar_cols |= shell_quad_cols(shell, 'belt_up', 'edge', sd)
        roof_cols |= shell_quad_cols(shell, 'edge', 'top_c', sd)
        edgerail_cols |= shell_quad_cols(shell, 'edge', 'rail', sd)
        rocker_cols |= shell_quad_cols(shell, 'sill', 'wide', sd, frac=(0.0, 0.8))
    # crisp horizontal split lines for the black bumper valances (domed caps are rings -> bisect first)
    for z_cut, in_zone in ((0.755, lambda x: x > 1.9), (0.70, lambda x: x < -1.9)):
        geom = set()
        for f in bm.faces:
            if in_zone(f.calc_center_median().x):
                geom.add(f)
                geom.update(f.edges)
                geom.update(f.verts)
        bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-6, plane_co=(0, 0, z_cut), plane_no=(0, 0, 1))
    bm.normal_update()
    surf0 = Surface(bm)

    for f in bm.faces:
        c = f.calc_center_median()
        tag = f[tc]
        m = 'M_Paint'
        if tag in under_cols:
            m = 'M_Underbody'
        elif tag in rocker_cols and -1.95 < c.x < 1.95:
            m = 'M_TrimBlack'                         # rocker cladding
        elif tag in pillar_cols and -1.99 < c.x < 0.86 and c.z > 1.11:
            m = 'M_Paint2'                            # blacked-out pillars
        elif tag in edgerail_cols and 0.10 < c.x < 0.86 and c.z > 1.30:
            m = 'M_Paint2'
        elif (c.x > 1.9 and c.z < 0.755) or (c.x < -1.9 and c.z < 0.70):
            m = 'M_TrimBlack'                         # bumper valances
        f.material_index = mi(m)

    # ------------------------------------------------------------------------------------------------------------------
    # 2. cutters: arches, shut lines, lamp / grille / plate pockets, exhaust holes
    # ------------------------------------------------------------------------------------------------------------------
    cutters, inserts = [], []

    def keep(b):
        if b is not None:
            inserts.append(b)
        return b

    def add_pair(bm_left, into=None):
        tgt = cutters if into is None else into
        if bm_left is None:
            return
        tgt.append(mirrored_copy(bm_left))
        tgt.append(bm_left)

    for name, w in WHEELS.items():
        cx, cy, cz = w['center']
        cutters.append(wheel_arch_cutter(cx, cz, w['radius'] + ARCH_PAD, 1 if cy > 0 else -1, inner_y=0.30, mat='M_Underbody'))

    zb_door = 1.095
    door_f = [(0.70, zb_door), (0.70, 0.46), (0.66, 0.40), (0.60, 0.378), (-0.43, 0.378), (-0.47, 0.41)]
    door_r = [(-0.49, zb_door), (-0.49, 0.46), (-0.53, 0.40), (-0.60, 0.378), (-0.90, 0.378)]
    door_rr = [(-1.41, zb_door), (-1.41, 0.92)]
    for pl in (door_f, door_r, door_rr):
        add_pair(surface_sweep(surf0, poly_pts(pl, subdiv=2), RAY_L, GROOVE, mat='M_Underbody'))
    # hood: rear edge + sides + front corners (plan view, ray down)
    hood_l = [(0.87, 0.0), (0.87, 0.45), (0.88, 0.80), (1.2, 0.84), (1.7, 0.845), (2.05, 0.83), (2.13, 0.80)]
    hp = [Vector((x, y, 0)) for x, y in hood_l] + [Vector((x, -y, 0)) for x, y in reversed(hood_l[:-1])]
    cutters.append(surface_sweep(surf0, resample_poly(hp, 0.03), (0, 0, -1), GROOVE, mat='M_Underbody'))
    # tailgate (side hinged): a loop on the rear face
    tg = [Vector((-2.0, y, z)) for (y, z) in ((0.74, 0.62), (0.74, 1.735), (-0.74, 1.735), (-0.74, 0.62), (0.74, 0.62))]
    cutters.append(surface_sweep(surf0, resample_poly(tg, 0.04), RAY_R, GROOVE, closed=False, mat='M_Underbody'))
    fuel = surface_sweep(surf0, circle_pts(-1.62, 0.93, 0.075, n=28, y=0), (0, 1, 0), GROOVE, closed=True, mat='M_Underbody')
    if fuel is not None:
        cutters.append(fuel)
    lap("arches + shut lines")

    # --- front: grille, headlamps, fog lamps, plate ------------------------------------------------------------------
    def nose_pocket(center, outline, depth, mat='M_TrimBlack'):
        return pocket_cutter(surf0, outline, Vector(center), RAY_F, depth=depth, taper=0.97, mat=mat, floor_follows=False)

    g_out = outline_rrect(0.86, 0.19, 0.03, 4)
    pk = nose_pocket((2.19, 0.0, 0.855), g_out, 0.07)
    if pk is not None:
        cutters.append(pk)
        fm = anchor_frame(surf0, (2.19, 0, 0.855), RAY_F, sink=0.04)
        g = grille_mesh([(p[0] * 0.97, p[1] * 0.88) for p in g_out], kind='bars', pitch=0.034, bar=0.012, depth=0.03, frame=0.012,
                        frame_mat='M_TrimGrey')
        bmesh.ops.transform(g, matrix=fm, verts=g.verts)
        keep(g)
        keep(surface_patch(surf0, outline_ellipse(0.045, 0.045, 22), Vector((2.19, 0, 0.855)), RAY_F, offset=-0.010, rings=2, mat='M_Chrome'))
    RH = ('radial', Vector((1.80, 0.30, 0.88)))
    UL = Vector((0.12, -0.99, 0.0)).normalized()
    c_head = Vector((2.16, 0.64, 0.90))
    cut, ins = build_headlight(surf0, c_head, RH, (UL, VL), length=0.135, height=0.088, rot=0.0, depth=0.07, floor_mat='M_TrimGrey')
    if cut is None:
        lap("headlight FAILED")
    add_pair(cut)
    for b in ins:
        add_pair(b, into=inserts)
    cut, plate = plate_recess(surf0, (2.19, 0.0, 0.64), RAY_F)
    if cut is not None:
        cutters.append(cut)
        keep(plate)
    fogd = Vector((-0.97, -0.24, 0.0)).normalized()
    fogU = Vector((0.24, -0.97, 0.0)).normalized()
    cut, lens = lamp_unit(surf0, Vector((2.15, 0.66, 0.61)), fogd, outline_rrect(0.085, 0.07, 0.02, 3), depth=0.05, lens_inset=0.004,
                          axes=(fogU, VL), lens_mat='M_Headlight', taper=0.8)
    if cut is not None:
        add_pair(cut)
        add_pair(lens, into=inserts)
    lap("front pockets")

    # roof drip rails
    for s_ in (1, -1):
        pts_r = []
        for x in [0.14 - 0.17 * i for i in range(0, 13)]:
            ye = dict(ring_controls(shell.cv, x))['edge'][0]
            pts_r.append(Vector((x, s_ * (ye - 0.012), 0.0)))
        keep(surface_sweep(surf0, pts_r, (0, 0, -1), rib_profile(0.022, 0.008, 0.006, 0.003), mat='M_TrimBlack'))

    # --- rear: stacked tail lamps, plate, exhaust --------------------------------------------------------------------
    RT = ('radial', Vector((-1.45, 0.35, 1.05)))
    cut, ins = stacked_lamp(surf0, Vector((-2.0, 0.81, 1.02)), RT, (Vector((0, -1, 0)), VL), 0.105, 0.40, depth=0.04)
    if cut is None:
        lap("taillight FAILED")
    add_pair(cut)
    for b in ins:
        add_pair(b, into=inserts)
    cut, plate = plate_recess(surf0, (-2.0, 0.0, 0.47), RAY_R)
    if cut is not None:
        cutters.append(cut)
        keep(plate)
    for s in (1, -1):
        cutters.append(prim_cylinder(radius=0.05, depth=0.22, segments=24, axis='X', center=(-1.93, s * 0.64, 0.40), mat='M_Underbody'))
        tip = build_exhaust_tip(radius=0.036, length=0.12, lip=0.004)
        bmesh.ops.transform(tip, matrix=T((-2.01, s * 0.64, 0.40)), verts=tip.verts)
        keep(tip)
    lap("rear pockets: %d cutters" % len([c for c in cutters if c is not None]))

    # ------------------------------------------------------------------------------------------------------------------
    # 3. boolean + add-ons that hug the skin
    # ------------------------------------------------------------------------------------------------------------------
    cutters = [c for c in cutters if c is not None]
    bm = bm_boolean(bm, cutters)
    lap("boolean done: %d faces, manifold=%s" % (len(bm.faces), is_manifold(bm)))
    tc, ts = face_tags(bm)
    wall_mats = (mi('M_TrimBlack'), mi('M_Chrome'), mi('M_Taillight'))

    def pocket_rim(e):
        if len(e.link_faces) != 2:
            return False
        a, b = e.link_faces
        if (a[tc] != 0) == (b[tc] != 0):
            return False
        wall = b if a[tc] != 0 else a
        return wall.material_index in wall_mats
    n_rim = bevel_hard_edges(bm, angle_deg=60.0, width=0.0035, segments=1, edge_filter=pocket_rim)
    lap("pocket rims chamfered: %d" % n_rim)

    # fender flares (black), side steps, belt strip, door handles, mirrors, cowl + wipers
    for name, w in WHEELS.items():
        cx, cy, cz = w['center']
        sw = arch_moulding(surf0, cx, cz, w['radius'] + ARCH_PAD + 0.045, (0, -1, 0) if cy > 0 else (0, 1, 0), a0=4.0, a1=176.0, n=36,
                           width=0.105, height=0.024)
        if sw is not None:
            keep(sw)
    belt = []
    for x in [0.62 - 0.06 * i for i in range(0, 38)]:
        pts_x = dict(ring_controls(shell.cv, x))
        belt.append((x, pts_x['belt_up'][1] - 0.006))
    add_pair(surface_sweep(surf0, poly_pts(belt), RAY_L, rib_profile(0.012, 0.004, 0.004, 0.002), mat='M_Chrome'), into=inserts)
    # fix round 2: black body-side protection strip across the doors (breaks up the flat slab) + low body-colour character line below it
    add_pair(surface_sweep(surf0, poly_pts([(x, 0.80) for x in [-0.86 + 0.12 * i for i in range(15)]], subdiv=1), RAY_L,
                           rib_profile(0.050, 0.013, 0.008, 0.005), mat='M_TrimBlack'), into=inserts)
    # fix round 2: low character line (body-colour bead above the rocker cladding) between the arches
    add_pair(surface_sweep(surf0, poly_pts([(x, 0.66) for x in [-0.84 + 0.12 * i for i in range(15)]]), RAY_L,
                           rib_profile(0.030, 0.009, 0.006, 0.004), mat='M_Paint'), into=inserts)
    for (hx, hz) in ((-0.24, 1.00), (-0.98, 1.00)):
        add_pair(door_handle(surf0, hx, hz, RAY_L, length=0.17, width=0.03, height=0.016), into=inserts)
    keep(surface_sweep(surf0, [Vector((0.90, y, 0)) for y in [0.82 - 0.08 * i for i in range(21)]], (0, 0, -1),
                       rib_profile(0.075, 0.010, 0.012, 0.004), mat='M_TrimBlack'))
    for (p0, p1) in (((0.86, 0.10), (0.80, 0.74)), ((0.86, -0.74), (0.80, -0.06))):
        pts = [Vector((p0[0] + (p1[0] - p0[0]) * i / 8.0, p0[1] + (p1[1] - p0[1]) * i / 8.0, 0)) for i in range(9)]
        keep(surface_sweep(surf0, pts, (0, 0, -1), rib_profile(0.014, 0.014, 0.0095, 0.003), mat='M_TrimBlack'))
    zm = 1.30
    for s in (1, -1):
        mh = surf0.hit(Vector((0.70, 0.0, zm - 0.04)), (0, -s, 0))
        my = (abs(mh[0].y) - 0.01) if mh else 0.90
        m = build_mirror(side=s, mat_shell='M_TrimBlack', length=0.20, width=0.115, height=0.19, arm_len=0.10)
        bmesh.ops.transform(m, matrix=T((0.68, s * my, zm)), verts=m.verts)
        keep(m)
    # bonnet vents / power bulge strips (two raised ribs)
    for s in (1, -1):
        keep(surface_sweep(surf0, [Vector((1.15 + 0.08 * i, s * 0.30, 0)) for i in range(7)], (0, 0, -1),
                           rib_profile(0.07, 0.012, 0.012, 0.005), mat='M_TrimBlack'))
    # side steps (tread plate on 3 brackets) + mud flaps
    for s in (1, -1):
        keep(prim_box((1.52, 0.17, 0.045), (-0.04, s * 0.875, 0.352), mat='M_TrimGrey', bevel=0.014, segments=2))
        for k in range(14):
            keep(prim_box((0.020, 0.12, 0.007), (-0.72 + k * 0.108, s * 0.875, 0.379), mat='M_TrimBlack', bevel=0.002, segments=1))
        for bx in (-0.62, -0.04, 0.54):
            keep(prim_box((0.07, 0.15, 0.11), (bx, s * 0.84, 0.30), mat='M_TrimBlack', bevel=0.012, segments=1))
        for bx in (XF - 0.52, XR - 0.52):
            keep(prim_box((0.012, 0.30, 0.30), (bx, s * 0.80, 0.37), mat='M_Rubber', bevel=0.004, segments=1))

    # ----- bull bar (front): chrome tubes, skid plate, spot lamps, recovery shackles ------------------------------------
    xb = 2.265
    for s in (1, -1):
        path = fillet_path3([(2.16, s * 0.84, 0.97), (2.27, s * 0.79, 0.99), (xb, s * 0.70, 1.00), (xb, s * 0.36, 1.03), (xb, 0.0, 1.03)],
                            [0, 0.08, 0.09, 0.10, 0], 6)
        keep(tube(path, 0.0245, 12, 'M_Chrome', caps=True))
        post = fillet_path3([(xb, s * 0.60, 0.99), (xb + 0.012, s * 0.60, 0.80), (xb + 0.012, s * 0.60, 0.50), (2.18, s * 0.60, 0.46)],
                            [0, 0.04, 0.06, 0], 6)
        keep(tube(post, 0.0245, 12, 'M_Chrome'))
        keep(tube(fillet_path3([(2.19, s * 0.82, 0.58), (2.27, s * 0.76, 0.54), (xb, s * 0.60, 0.50), (xb + 0.012, 0.0, 0.50)],
                               [0, 0.10, 0.10, 0], 6), 0.0245, 12, 'M_Chrome'))
        sp = round_lamp(0.065, 0.075, mat_shell='M_TrimBlack', mat_lens='M_Headlight', style='bucket')
        bmesh.ops.transform(sp, matrix=T((xb - 0.02, s * 0.30, 1.11)), verts=sp.verts)
        keep(sp)
        keep(prim_torus(R=0.032, r=0.006, seg_major=18, seg_minor=6, axis='Y', center=(xb + 0.02, s * 0.60, 0.50), mat='M_Caliper'))
    keep(prim_box((0.045, 0.72, 0.16), (xb - 0.015, 0.0, 0.52), mat='M_TrimGrey', bevel=0.014, segments=2))       # skid plate
    keep(prim_box((0.06, 0.86, 0.05), (2.205, 0.0, 0.43), mat='M_TrimBlack', bevel=0.012, segments=1))
    keep(tube([(xb, -0.60, 0.74), (xb, 0.60, 0.74)], 0.0215, 10, 'M_Chrome'))
    for s in (1, -1):
        keep(tube([(2.19, s * 0.60, 0.74), (xb, s * 0.60, 0.74)], 0.0215, 10, 'M_Chrome'))

    # ----- roof rack, light bar, snorkel --------------------------------------------------------------------------------
    zr = 1.885
    rail = rrect_path(-0.68, 0.0, 0.88, 0.715, zr, 0.12, 6)
    keep(tube(rail, 0.0165, 10, 'M_TrimBlack', closed=True))
    for k in range(9):
        xx = -1.50 + k * 0.205
        keep(tube([(xx, -0.715, zr), (xx, 0.715, zr)], 0.0105, 8, 'M_TrimBlack'))
    for yy in (-0.36, 0.0, 0.36):
        keep(tube([(-1.56, yy, zr - 0.006), (0.20, yy, zr - 0.006)], 0.0075, 6, 'M_TrimBlack'))
    for fx in (-1.50, -0.68, 0.10):
        for fy in (-0.715, 0.715):
            h = surf0.hit(Vector((fx, fy, 0)), (0, 0, -1))
            zl = (h[0].z - 0.006) if h else 1.77
            keep(prim_box((0.075, 0.055, zr - zl + 0.01), (fx, fy, (zr + zl) / 2), mat='M_TrimBlack', bevel=0.012, segments=1))
    keep(prim_box((0.05, 0.98, 0.045), (0.17, 0.0, zr + 0.005), mat='M_TrimBlack', bevel=0.012, segments=2))
    keep(prim_box((0.004, 0.94, 0.028), (0.196, 0.0, zr + 0.005), mat='M_Headlight', bevel=0.005, segments=1))
    # roof cargo: two jerry-can-like boxes + a rolled mat would be too much; a plain cargo box keeps the silhouette tall
    # snorkel (passenger side = -Y): follows the A-pillar (positions from the shell's ring control points)
    def pillar_pt(z, off=0.052):
        x = 0.80 - (z - 1.14) * 0.69
        ctrl = dict(ring_controls(shell.cv, x))
        yb, zb_ = ctrl['belt_up']
        ye, ze_ = ctrl['edge']
        t = clamp((z - zb_) / max(ze_ - zb_, 1e-4), 0.0, 1.0)
        return Vector((x, -(yb + (ye - yb) * t + off), z))
    ph = dict(ring_controls(shell.cv, 0.98))
    pts = [Vector((0.97, -(ph['wide'][0] + 0.03), 0.90)), Vector((0.93, -(ph['wide'][0] + 0.05), 1.02))]
    pts += [pillar_pt(1.14 + i * 0.08) for i in range(0, 9)]
    pts = fillet_path3(pts, [0.0] + [0.08] * (len(pts) - 2) + [0.0], 4)
    keep(tube(pts, 0.034, 12, 'M_TrimBlack', caps=True))
    top = pts[-1]
    keep(prim_box((0.16, 0.085, 0.10), (top.x - 0.02, top.y, top.z + 0.03), mat='M_TrimBlack', bevel=0.028, segments=2))
    keep(prim_box((0.012, 0.060, 0.064), (top.x + 0.058, top.y, top.z + 0.032), mat='M_Underbody', bevel=0.004, segments=1))
    keep(prim_box((0.14, 0.075, 0.20), (0.985, -(ph['wide'][0] + 0.005), 0.88), mat='M_TrimBlack', bevel=0.03, segments=2))
    for k in range(5):
        keep(prim_box((0.004, 0.07, 0.012), (1.056, -(ph['wide'][0] + 0.005), 0.82 + k * 0.032), mat='M_Underbody', bevel=0.001, segments=1))
    # whip antenna on the left fender
    keep(prim_cylinder(radius=0.022, depth=0.03, segments=10, axis='Z', center=(0.62, 0.84, 1.13), mat='M_TrimBlack'))
    keep(tube([(0.62, 0.84, 1.14), (0.50, 0.855, 1.60), (0.44, 0.86, 1.90)], 0.0042, 5, 'M_TrimBlack'))
    # recovery boards (sand ladders) lying on the rack
    for s in (1, -1):
        keep(prim_box((1.28, 0.28, 0.022), (-0.74, s * 0.45, zr + 0.0105 + 0.0165 + 0.002), mat='M_TrimGrey', bevel=0.005, segments=1))
        for k in range(9):
            keep(prim_box((0.04, 0.26, 0.012), (-1.30 + k * 0.145, s * 0.45, zr + 0.0105 + 0.0165 + 0.012), mat='M_TrimBlack', bevel=0.002, segments=1))
    # side marker repeaters + undercarriage (axles, diffs, shocks + springs, driveshaft, exhaust) -----------------------
    add_pair(surface_patch(surf0, outline_ellipse(0.032, 0.014, 12), Vector((1.74, 0.0, 0.93)), RAY_L, offset=-0.0015, rings=2,
                           mat='M_Indicator'), into=inserts)
    for ax_x in (XF, XR):
        keep(tube([(ax_x, -0.58, 0.40), (ax_x, 0.58, 0.40)], 0.050, 12, 'M_TrimBlack'))
        keep(prim_sphere(0.135, 18, 10, scale=(1.0, 1.1, 0.92), center=(ax_x + 0.05, 0.0, 0.405), mat='M_TrimGrey'))
        for s in (1, -1):
            keep(tube([(ax_x - 0.02, s * 0.50, 0.46), (ax_x - 0.02, s * 0.50, 0.80)], 0.022, 8, 'M_TrimGrey'))
            helix = [Vector((ax_x - 0.02 + 0.062 * math.cos(a), s * 0.50 + 0.062 * math.sin(a), 0.50 + 0.30 * a / (2 * math.pi * 5)))
                     for a in [2 * math.pi * 5 * i / 40.0 for i in range(41)]]
            keep(tube(helix, 0.0085, 5, 'M_TrimBlack'))
    keep(tube([(XF - 0.10, 0.0, 0.38), (XR + 0.10, 0.0, 0.38)], 0.034, 10, 'M_TrimBlack'))
    keep(prim_box((0.34, 0.30, 0.16), (0.30, 0.0, 0.36), mat='M_TrimGrey', bevel=0.03, segments=2))
    for s in (1, -1):
        keep(tube(fillet_path3([(-0.20, s * 0.24, 0.31), (-0.95, s * 0.36, 0.32), (-1.70, s * 0.62, 0.36), (-2.00, s * 0.64, 0.40)],
                               [0, 0.3, 0.25, 0], 5), 0.030, 10, 'M_Exhaust'))
        keep(prim_cylinder(radius=0.085, depth=0.62, segments=16, axis='X', center=(-1.30, s * 0.46, 0.34), mat='M_Exhaust', bevel=0.012))
    keep(prim_box((0.62, 0.86, 0.025), (1.52, 0.0, 0.325), mat='M_TrimGrey', bevel=0.006, segments=1))

    # rear: step bumper pads, hitch receiver, recovery hooks, spare wheel carrier
    keep(prim_box((0.11, 1.70, 0.20), (-2.045, 0.0, 0.47), mat='M_TrimBlack', bevel=0.03, segments=2))
    for s in (1, -1):
        keep(prim_box((0.09, 0.30, 0.012), (-2.04, s * 0.70, 0.575), mat='M_TrimGrey', bevel=0.004, segments=1))
        keep(prim_torus(R=0.030, r=0.007, seg_major=16, seg_minor=6, axis='X', center=(-2.12, s * 0.36, 0.43), mat='M_Caliper'))
    keep(prim_box((0.20, 0.07, 0.07), (-2.10, 0.0, 0.34), mat='M_TrimGrey', bevel=0.012, segments=1))
    # spare wheel on the tailgate (axis along X, face rearwards)
    sp = spare_wheel(0.40, 0.265, RIM_R, segs=40, tyre_fn=block_tyre, tyre_kw=dict(segs=40, n=28, lug_h=0.028, seed=21, vary=0.5))
    bmesh.ops.transform(sp, matrix=T((-2.155, 0.0, 0.975), (0, 0, 90)), verts=sp.verts)
    keep(sp)
    keep(prim_cylinder(radius=0.08, depth=0.07, segments=18, axis='X', center=(-2.035, 0.0, 0.975), mat='M_TrimBlack', bevel=0.01))

    for ib in inserts:
        if ib is None:
            continue
        bm_append(bm, ib)
        ib.free()
    lap("add-ons appended: %d faces" % len(bm.faces))
    tc, ts = face_tags(bm)

    # ------------------------------------------------------------------------------------------------------------------
    # 4. greenhouse (thin separate glass sheets)
    # ------------------------------------------------------------------------------------------------------------------
    side_cols = shell_quad_cols(shell, 'belt_up', 'edge', 1) | shell_quad_cols(shell, 'belt_up', 'edge', -1)
    top_cols = shell_quad_cols(shell, 'rail', 'top_c', 1) | shell_quad_cols(shell, 'rail', 'top_c', -1)
    A0, A1 = (0.74, 1.10), (0.205, 1.778)           # A-pillar line (side glass lies behind it)
    B0, B1 = (-0.43, 1.0), (-0.43, 1.90)            # front door glass rear edge
    Bq0, Bq1 = (-0.555, 1.0), (-0.555, 1.90)        # rear door glass front edge
    C0, C1 = (-1.38, 1.0), (-1.38, 1.90)            # rear door glass rear edge
    Q0, Q1 = (-1.52, 1.0), (-1.52, 1.90)            # quarter glass front edge
    D0, D1 = (-1.83, 1.0), (-1.83, 1.90)            # quarter glass rear edge

    def behind(c, p0, p1):
        xl = p0[0] + (p1[0] - p0[0]) * (c.z - p0[1]) / (p1[1] - p0[1])
        return c.x < xl

    def plane(p0, p1):
        return (Vector((p0[0], 0, p0[1])), Vector((-(p1[1] - p0[1]), 0, p1[0] - p0[0])).normalized())

    def side_zone(f):
        return f[tc] in side_cols

    def mk_side(front, back):
        def pred(f):
            if f[tc] not in side_cols:
                return False
            c = f.calc_center_median()
            return behind(c, *front) and not behind(c, *back)
        return pred
    cap_zone = lambda f: f[tc] == 0 and f.calc_center_median().x < -1.97

    def rear_pred(f):
        if f[tc] != 0:
            return False
        c = f.calc_center_median()
        return c.x < -1.97 and 1.36 < c.z < 1.64 and abs(c.y) < 0.64

    def ws_pred(f):
        return f[tc] in top_cols and P['x_ws_top'] < f.calc_center_median().x < P['x_ws_base']

    wins = [dict(name='door_f', pred=mk_side((A0, A1), (B0, B1)), zone=side_zone, planes=[plane(A0, A1), plane(B0, B1)]),
            dict(name='door_r', pred=mk_side((Bq0, Bq1), (C0, C1)), zone=side_zone, planes=[plane(Bq0, Bq1), plane(C0, C1)]),
            dict(name='quarter', pred=mk_side((Q0, Q1), (D0, D1)), zone=side_zone, planes=[plane(Q0, Q1), plane(D0, D1)]),
            dict(name='windscreen', pred=ws_pred),
            dict(name='rear', pred=rear_pred, zone=cap_zone,
                 planes=[(Vector((0, 0, 1.36)), Vector((0, 0, 1))), (Vector((0, 0, 1.64)), Vector((0, 0, 1))),
                         (Vector((0, 0.64, 0)), Vector((0, 1, 0))), (Vector((0, -0.64, 0)), Vector((0, 1, 0)))])]
    glass = extract_glass(bm, wins, offset=0.014)
    lap("glass: %d faces; body %d faces" % (len(glass.faces), len(bm.faces)))
    # fix round 2: black rubber seal bead round every window opening (the greenhouse no longer reads as a glass box with thin pillars)
    seal = window_seal(glass, surf0, width=0.0125, height=0.0040, mat='M_TrimBlack')
    if seal is not None:
        bm_append(bm, seal)
        seal.free()
        lap("window seals appended")

    def lining_pred(f):
        if f[tc] == 0:
            return False
        if f[tc] not in (pillar_cols | roof_cols):
            return False
        c = f.calc_center_median()
        return -1.99 < c.x < 0.78 and c.z > 1.10 and f.material_index != mi('M_TrimBlack')
    pillar_trim = inner_trim_from_faces(bm, lining_pred, offset=0.03, mat='M_IntTrim')

    n_healed = heal_nonmanifold(bm) if 'heal_nonmanifold' in globals() else 0
    n_tiny = clean_tiny(bm)
    lap("tiny edges collapsed: %d" % n_tiny)
    body = finish_object(CAR + "_Body", bm, col, parent=root, smooth_angle=62.0)
    n_sm = apply_shell_normals(body, shell)
    shell.ref.free()
    lap("custom normals on %d loops" % n_sm)
    finish_object(CAR + "_Glass", glass, col, parent=root)

    # ------------------------------------------------------------------------------------------------------------------
    # 5. wheels
    # ------------------------------------------------------------------------------------------------------------------
    for wi, (name, w) in enumerate(WHEELS.items()):
        # fix round 2: real block tread (block_tyre: two staggered tread lanes + shoulder blocks + sidewall blocks, seeded jitter per wheel)
        wb = off_road_wheel(w['radius'], w['width'], RIM_R, RIM_W, tyre_kw=dict(segs=40, n=28, lug_h=0.028, seed=31 + 7 * wi, vary=0.5),
                            tyre_fn=block_tyre, style='star', spokes=6,
                            brake_disc_radius=0.15, segments=40, side=w['side'], caliper_angle=20.0 if name[0] == 'F' else 160.0,
                            hub_radius=0.058)
        finish_object("%s_Wheel_%s" % (CAR, name), wb, col, parent=root, location=w['center'], smooth_angle=40)
    lap("wheels done")

    # ------------------------------------------------------------------------------------------------------------------
    # 6. interior + steering wheel
    # ------------------------------------------------------------------------------------------------------------------
    ib = build_interior_utility(shell, dict(floor_z=0.43, front_x=-0.22, front_z=0.47, driver_y=0.38, rear_x=-1.02, rear_z=0.47,
                                            rear_width=1.40, dash_x_back=0.40, dash_z_top=1.06, hw=0.865, x_front_floor=0.72,
                                            x_rear_floor=-1.95, door_x=(-0.46, 0.70), quarter_x=(-1.90, -0.50), roof_x=(-1.80, 0.12),
                                            back_h=0.66, headliner=False))             # fix round 2: utilitarian dash instead of the kit's sport dash
    _add(ib, pillar_trim)
    _add(ib, prim_box((0.62, 1.50, 0.03), (-1.62, 0.0, 0.58), mat='M_IntCarpet', bevel=0.008, segments=1))        # cargo floor
    _add(ib, prim_box((0.03, 1.44, 0.74), (-1.945, 0.0, 1.02), mat='M_IntTrim', bevel=0.01, segments=1))          # tailgate lining
    for sd in (1, -1):
        _add(ib, shell_skin(shell, 'sill', 'belt_up', -1.95, -1.50, offset=0.045, side=sd, mat='M_IntTrim'))
    finish_object(CAR + "_Interior", ib, col, parent=root)
    hub = (0.255, 0.38, 1.03)
    swb, axis = build_steering_wheel(rim_radius=0.19, tilt=30.0)
    sw = finish_object(CAR + "_SteeringWheel", swb, col, parent=root, location=hub, smooth_angle=40)
    sw['rim_axis'] = [axis.x, axis.y, axis.z]
    lap("interior done")

    # ------------------------------------------------------------------------------------------------------------------
    # 7. collision hulls + empties
    # ------------------------------------------------------------------------------------------------------------------
    low = ['floor_e', 'wide', 'belt_lo']
    hulls = [
        hull_points_from_shell(shell, [-1.98, -0.6, 0.9, 2.15], low, z_clip=(0.34, 1.05), shrink=0.04),
        [Vector((p.x, p.y, min(p.z, 1.08) - 0.012)) for p in
         hull_points_from_shell(shell, [0.78, 1.5, 2.16], ['sill', 'belt_up', 'edge', 'top_c'], z_clip=(0.52, None), shrink=0.05)],
        [Vector((p.x, p.y, p.z - 0.02)) for p in
         hull_points_from_shell(shell, [0.76, 0.3, -0.9, -1.95], ['belt_up', 'edge', 'top_c'], z_clip=(1.02, None), shrink=0.05)],
    ]
    ucx = make_ucx_hulls(CAR, hulls, col, root)
    for h in ucx:
        h.hide_set(True)

    def E(suffix, loc, disp='PLAIN_AXES', size=0.08):
        return make_empty("%s_%s" % (CAR, suffix), col, parent=root, location=loc, display=disp, size=size)

    def lamp_point(center, ray, lift=0.03):
        h = surf0.hit(Vector(center), ray)
        return tuple(round(c, 4) for c in (h[0] + h[1] * lift)) if h else tuple(center)

    hl = lamp_point(c_head, RH)
    tl = lamp_point(Vector((-2.0, 0.81, 1.02)), RT)
    E('LP_HeadL', hl)
    E('LP_HeadR', (hl[0], -hl[1], hl[2]))
    E('LP_TailL', tl)
    E('LP_TailR', (tl[0], -tl[1], tl[2]))
    E('LP_Reverse', (tl[0], tl[1] - 0.0, tl[2] - 0.15))
    E('CAM_Hood', (1.30, 0.0, 1.24), 'ARROWS', 0.15)
    E('CAM_Cockpit', (-0.14, 0.38, 1.30), 'ARROWS', 0.15)
    E('CAM_Bumper', (2.34, 0.0, 0.62), 'ARROWS', 0.15)
    E('EXHAUST_L', (-2.01, 0.64, 0.40))
    E('EXHAUST_R', (-2.01, -0.64, 0.40))

    lo, hi = bm_bounds_obj(body)
    vs = [v.co for v in body.data.vertices if v.co.z < 0.9 and abs(v.co.x) < 1.7 and v.co.y > 0]
    set_root_props(root, length=round(hi.x - lo.x, 4), width=round(2 * max(abs(v.y) for v in vs), 4), height=round(hi.z, 4))
    lap("done. body bounds %s %s | L x W x H = %.3f x %.3f x %.3f (mirrors: %.3f wide)" % (
        tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi), root['length'], root['width'], root['height'], hi.y - lo.y))
    return root


def unwrap_parts(parts):
    t0 = time.time()
    for suf in parts:
        o = bpy.data.objects.get("%s_%s" % (CAR, suf))
        if o is not None:
            uv_unwrap(o)
            if suf == 'Body':
                uv_livery_layer(o)
            print("[car08] uv %s %.1fs" % (suf, time.time() - t0))


if STAGE in ("all", "geometry"):
    build()
if STAGE in ("all", "uv", "uv1"):
    unwrap_parts(['Body', 'Glass', 'Interior', 'SteeringWheel'])
if STAGE in ("all", "uv", "uv2"):
    unwrap_parts(['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'])
