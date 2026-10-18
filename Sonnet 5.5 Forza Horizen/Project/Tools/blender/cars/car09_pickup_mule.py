"""
car09_pickup_mule.py - parametric, idempotent build of player car #9 "Mule" (double-cab pickup, RWD / AWD optional, LHD).
Two lofted shells share one <id>_Body object: the CAB (hood, doors, greenhouse) and the open BED (box with liner, tailgate,
wheel boxes); a visible gap separates them.  Built with carkit.py + carkit_ext_08_09_10.py.

    CAR09_STAGE = "all"      # optional: "geometry" | "uv1" | "uv2" | "all" (default)
    exec(compile(open(r"<project>/Tools/blender/cars/car09_pickup_mule.py", encoding="utf8").read(), "car09", "exec"), globals())
Car space: +X forward, +Y left (driver side, LHD), +Z up; origin on the ground under the middle of the wheelbase.
Staged at x = 108 m (cars row, index 9), collection FORZA_UE/Cars/car09_pickup_mule, root car09_pickup_mule_ROOT.
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

CAR = "car09_pickup_mule"
STAGE = globals().get("CAR09_STAGE", "all")

P = dict(
    id=CAR, display_name="Mule", index=9,
    L=5.30, W=1.96, H=1.88, wheelbase=3.25, track_f=1.65, track_r=1.65,
    r_f=0.38, r_r=0.38, w_f=0.255, w_r=0.255, ride=0.30,
    cab_x0=-1.15, cab_x1=2.50, bed_x0=-2.54, bed_x1=-1.21,
    roof_z=1.862, bed_rail=1.272, bed_floor=0.90,
    x_ws_base=0.95, x_ws_top=0.45,
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
RIM_R, RIM_W = 0.2286, 0.205          # 18" alloys, 255/60 R18 (outer radius 0.38)
VL = Vector((0, 0, 1))
RAY_L, RAY_F, RAY_R = (0, -1, 0), (-1, 0, 0), (1, 0, 0)


def cab_curves():
    zt = fillet_profile([(-1.15, 1.78), (-1.095, 1.856), (-0.9, P['roof_z']), (0.45, P['roof_z']), (0.95, 1.282), (2.31, 1.292),
                         (2.50, 1.17)], [0, 0.05, 0.06, 0.40, 0.18, 0.16, 0], step=0.01)
    zf = smooth_keys([(-1.15, 0.46), (-0.8, 0.40), (0.0, 0.38), (1.0, 0.38), (1.8, 0.42), (2.15, 0.52), (2.50, 0.60)], sigma=0.08)
    hwm = smooth_keys([(-1.15, 0.90), (-1.08, 0.935), (-0.9, 0.945), (2.0, 0.945), (2.36, 0.94), (2.50, 0.90)], sigma=0.06)
    zw = smooth_keys([(-1.2, 0.64), (-0.5, 0.62), (2.0, 0.62), (2.50, 0.68)], sigma=0.15)
    zb = smooth_keys([(-1.15, 1.245), (-0.9, 1.255), (0.6, 1.255), (1.0, 1.245), (1.6, 1.22), (2.26, 1.19), (2.50, 1.12)], sigma=0.11)
    zc = smooth_keys([(-1.2, 0.90), (2.6, 0.90)], sigma=0.2)
    cdepth = smooth_keys([(-1.15, 0.0), (-1.0, 0.006), (-0.8, 0.022), (1.6, 0.022), (2.26, 0.006), (2.50, 0.0)], sigma=0.1)
    hwe = smooth_keys([(-1.15, 0.80), (-1.0, 0.835), (0.35, 0.835), (1.0, 0.895), (2.31, 0.90), (2.50, 0.80)], sigma=0.1)
    dz = as_curve(smooth_keys([(-1.15, 0.035), (0.4, 0.035), (0.95, 0.055), (1.6, 0.065), (2.50, 0.06)], sigma=0.12))
    ztc, hwmc, zfc = as_curve(zt), as_curve(hwm), as_curve(zf)
    return dict(zf=zf, zt=zt, hwm=hwm, zw=zw, zb=zb, zc=zc, cdepth=cdepth, hwe=hwe, ze=lambda x: ztc(x) - dz(x),
                hwb=lambda x: hwmc(x) - 0.008, zs=lambda x: zfc(x) + 0.09, belt_step=0.03, crease=0.014, rail_w=0.05)


def bed_curves():
    zt = fillet_profile([(-2.54, 1.20), (-2.50, 1.266), (-1.28, 1.272), (-1.21, 1.20)], [0, 0.04, 0.04, 0], step=0.01)
    zf = smooth_keys([(-2.54, 0.62), (-2.4, 0.58), (-2.0, 0.55), (-1.21, 0.50)], sigma=0.08)
    hwm = smooth_keys([(-2.54, 0.90), (-2.46, 0.940), (-1.3, 0.945), (-1.21, 0.925)], sigma=0.05)
    zw = smooth_keys([(-2.6, 0.75), (-1.2, 0.75)], sigma=0.2)
    zb = smooth_keys([(-2.6, 1.215), (-1.2, 1.215)], sigma=0.2)
    zc = smooth_keys([(-2.6, 0.90), (-1.2, 0.90)], sigma=0.2)
    cdepth = smooth_keys([(-2.54, 0.0), (-2.4, 0.012), (-1.4, 0.018), (-1.21, 0.0)], sigma=0.1)
    hwe = smooth_keys([(-2.54, 0.86), (-2.46, 0.925), (-1.3, 0.925), (-1.21, 0.90)], sigma=0.05)
    ztc, hwmc, zfc = as_curve(zt), as_curve(hwm), as_curve(zf)
    return dict(zf=zf, zt=zt, hwm=hwm, zw=zw, zb=zb, zc=zc, cdepth=cdepth, hwe=hwe, ze=lambda x: ztc(x) - 0.045,
                hwb=lambda x: hwmc(x) - 0.004, zs=lambda x: zfc(x) + 0.09, belt_step=0.0, crease=0.01, rail_w=0.04)


def bm_bounds_obj(ob):
    vs = [v.co for v in ob.data.vertices]
    return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
            Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def build():
    t0 = time.time()

    def lap(msg):
        print("[car09 %.2fs] %s" % (time.time() - t0, msg))

    remove_asset(CAR)
    build_standard_materials()
    col = ensure_collection("FORZA_UE/Cars/" + CAR)
    root = make_empty(CAR + "_ROOT", col, location=(12.0 * P['index'], 0, 0), display='ARROWS', size=0.6)
    set_root_props(root, wheelbase=P['wheelbase'], track_front=P['track_f'], track_rear=P['track_r'],
                   wheel_radius_front=P['r_f'], wheel_radius_rear=P['r_r'], wheel_width_front=P['w_f'], wheel_width_rear=P['w_r'],
                   ride_height=P['ride'], length=P['L'], width=P['W'], height=P['H'], display_name=P['display_name'],
                   car_id=CAR, drivetrain="RWD", steering_side="LHD")

    inserts = []       # add-ons of the cab (appended after its boolean)
    inserts_bed = []

    def keep(b, bed=False):
        if b is not None:
            (inserts_bed if bed else inserts).append(b)
        return b

    def add_pair(bm_left, cutl=None, into=None):
        if bm_left is None:
            return
        tgt = cutl if into is None else into
        tgt.append(mirrored_copy(bm_left))
        tgt.append(bm_left)

    # ==================================================================================================================
    # A. CAB shell
    # ==================================================================================================================
    cv = cab_curves()
    x0, x1 = P['cab_x0'], P['cab_x1']
    rr0, rr1 = 0.06, 0.085
    xs = station_list(x0, x1, dx=0.05, end_dx=0.02, end_len=0.26, min_gap=0.007,
                      extra=[P['x_ws_base'], P['x_ws_top'], 0.45, 0.95] + end_round_stations(x0, rr0, 5, at_start=True)
                      + end_round_stations(x1, rr1, 5, at_start=False))
    shell = loft_body(cv, xs, cap_bulge=0.006, ring_density=2.0, cap_rings=4, round_x0=rr0, round_x1=rr1)
    bm = shell.bm
    tc, ts = face_tags(bm)
    lap("cab loft %d stations, %d faces" % (len(xs), len(bm.faces)))
    under_cols, pillar_cols, roof_cols, lower_cols, lower_blk = set(), set(), set(), set(), set()
    for sd in (1, -1):
        under_cols |= shell_quad_cols(shell, 'floor_c', 'sill', sd)
        pillar_cols |= shell_quad_cols(shell, 'belt_up', 'edge', sd)
        roof_cols |= shell_quad_cols(shell, 'edge', 'top_c', sd)
        lower_cols |= shell_quad_cols(shell, 'sill', 'wide', sd)
    for z_cut, in_zone in ((0.82, lambda x: x > 2.36),):
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
        elif tag in lower_cols and -1.2 < c.x < 2.36:
            m = 'M_Paint2'                              # two-tone lower body (accent colour)
        elif c.x > 2.36 and c.z < 0.82:
            m = 'M_TrimBlack'                           # lower fascia
        f.material_index = mi(m)

    cut_cab = []
    for name in ('FL', 'FR'):
        w = WHEELS[name]
        cx, cy, cz = w['center']
        cut_cab.append(wheel_arch_cutter(cx, cz, w['radius'] + ARCH_PAD, 1 if cy > 0 else -1, inner_y=0.30, mat='M_Underbody'))

    zb_door = 1.235
    door_f = [(0.80, zb_door), (0.80, 0.52), (0.76, 0.46), (0.70, 0.438), (-0.08, 0.438), (-0.12, 0.46)]
    door_r = [(-0.14, zb_door), (-0.14, 0.52), (-0.18, 0.46), (-0.24, 0.438), (-1.02, 0.438), (-1.07, 0.46), (-1.07, 1.1), (-1.06, zb_door)]
    for pl in (door_f, door_r):
        add_pair(surface_sweep(surf0, poly_pts(pl, subdiv=2), RAY_L, GROOVE, mat='M_Underbody'), cut_cab)
    hood_l = [(0.97, 0.0), (0.97, 0.45), (0.98, 0.84), (1.3, 0.87), (2.0, 0.875), (2.40, 0.85), (2.47, 0.80)]
    hp = [Vector((x, y, 0)) for x, y in hood_l] + [Vector((x, -y, 0)) for x, y in reversed(hood_l[:-1])]
    cut_cab.append(surface_sweep(surf0, resample_poly(hp, 0.03), (0, 0, -1), GROOVE, mat='M_Underbody'))

    # grille, headlamps, fog lamps
    def nose_pocket(center, outline, depth, mat='M_TrimBlack'):
        return pocket_cutter(surf0, outline, Vector(center), RAY_F, depth=depth, taper=0.97, mat=mat, floor_follows=False)
    g_out = outline_rrect(0.86, 0.33, 0.035, 4)
    pk = nose_pocket((2.515, 0.0, 0.93), g_out, 0.08)
    if pk is not None:
        cut_cab.append(pk)
        fm = anchor_frame(surf0, (2.515, 0, 0.93), RAY_F, sink=0.045)
        g = grille_mesh([(p[0] * 0.97, p[1] * 0.9) for p in g_out], kind='bars', pitch=0.060, bar=0.022, depth=0.04, frame=0.018,
                        frame_mat='M_Chrome')
        bmesh.ops.transform(g, matrix=fm, verts=g.verts)
        keep(g)
        keep(surface_patch(surf0, outline_ellipse(0.05, 0.05, 22), Vector((2.515, 0, 0.93)), RAY_F, offset=-0.012, rings=2, mat='M_Chrome'))
        keep(surface_patch(surf0, outline_ellipse(0.034, 0.034, 20), Vector((2.515, 0, 0.93)), RAY_F, offset=-0.014, rings=2, mat='M_Paint2'))
    RH = ('radial', Vector((2.10, 0.50, 1.0)))
    UL = Vector((0.18, -0.98, 0.0)).normalized()
    c_head = Vector((2.495, 0.725, 0.99))
    cut, ins = build_headlight(surf0, c_head, RH, (UL, VL), length=0.185, height=0.092, rot=0.0, depth=0.08, floor_mat='M_TrimGrey')
    if cut is None:
        lap("headlight FAILED")
    add_pair(cut, cut_cab)
    for b in ins:
        add_pair(b, into=inserts)
    fogd = Vector((-0.97, -0.20, 0.0)).normalized()
    fogU = Vector((0.20, -0.97, 0.0)).normalized()
    cut, lens = lamp_unit(surf0, Vector((2.485, 0.62, 0.60)), fogd, outline_ellipse(0.055, 0.045, 20), depth=0.05, lens_inset=0.004,
                          axes=(fogU, VL), lens_mat='M_Headlight', taper=0.8)
    if cut is not None:
        add_pair(cut, cut_cab)
        add_pair(lens, into=inserts)
    lap("cab cutters ready")

    lap("cab cutters: %d, None at %s" % (len(cut_cab), [i for i, c in enumerate(cut_cab) if c is None]))
    cut_cab = [c for c in cut_cab if c is not None]
    bm = bm_boolean(bm, cut_cab)
    lap("cab boolean: %d faces, manifold=%s" % (len(bm.faces), is_manifold(bm)))
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
    bevel_hard_edges(bm, angle_deg=60.0, width=0.0035, segments=1, edge_filter=pocket_rim)

    # --- cab add-ons -----------------------------------------------------------------------------------------------
    for name in ('FL', 'FR'):
        w = WHEELS[name]
        cx, cy, cz = w['center']
        sw = arch_moulding(surf0, cx, cz, w['radius'] + ARCH_PAD + 0.045, (0, -1, 0) if cy > 0 else (0, 1, 0), a0=22.0, a1=176.0, n=36,
                           width=0.115, height=0.028)
        lap("front flare %s: %s" % (name, sw is not None))
        keep(sw)
    belt = []
    for x in [0.82 - 0.06 * i for i in range(0, 34)]:
        pts_x = dict(ring_controls(shell.cv, x))
        belt.append((x, pts_x['belt_up'][1] - 0.006))
    add_pair(surface_sweep(surf0, poly_pts(belt), RAY_L, rib_profile(0.012, 0.004, 0.004, 0.002), mat='M_Chrome'), into=inserts)
    for (hx, hz) in ((0.02, 1.10), (-0.84, 1.10)):
        add_pair(door_handle(surf0, hx, hz, RAY_L, length=0.17, width=0.03, height=0.016, mat='M_Chrome'), into=inserts)
    keep(surface_sweep(surf0, [Vector((1.02, y, 0)) for y in [0.88 - 0.08 * i for i in range(23)]], (0, 0, -1),
                       rib_profile(0.075, 0.010, 0.012, 0.004), mat='M_TrimBlack'))
    for (p0, p1) in (((0.98, 0.10), (0.92, 0.76)), ((0.98, -0.76), (0.92, -0.06))):
        pts = [Vector((p0[0] + (p1[0] - p0[0]) * i / 8.0, p0[1] + (p1[1] - p0[1]) * i / 8.0, 0)) for i in range(9)]
        keep(surface_sweep(surf0, pts, (0, 0, -1), rib_profile(0.014, 0.014, 0.0095, 0.003), mat='M_TrimBlack'))
    # raised hood centre (power dome) + two vents
    keep(surface_sweep(surf0, [Vector((1.25 + 0.075 * i, 0, 0)) for i in range(15)], (0, 0, -1), rib_profile(0.56, 0.028, 0.02, 0.014),
                       mat='M_Paint'))
    for s in (1, -1):
        keep(surface_sweep(surf0, [Vector((1.55 + 0.08 * i, s * 0.17, 0)) for i in range(7)], (0, 0, -1),
                           rib_profile(0.05, 0.010, 0.020, 0.004), mat='M_TrimBlack'))
    # mirrors (big tow mirrors on arms)
    for s in (1, -1):
        mh = surf0.hit(Vector((0.88, 0.0, 1.20)), (0, -s, 0))
        my = (abs(mh[0].y) - 0.01) if mh else 0.94
        # fix round 2: tow mirrors pulled in (short arm, compact head): width incl. mirrors ~2.2 m instead of 2.4 m
        m = build_mirror(side=s, mat_shell='M_TrimBlack', length=0.20, width=0.105, height=0.235, arm_len=0.07)
        bmesh.ops.transform(m, matrix=T((0.86, s * my, 1.36)), verts=m.verts)
        keep(m)
    # roof drip rails + side marker lamps
    for s_ in (1, -1):
        pts_r = []
        for x in [0.40 - 0.12 * i for i in range(0, 13)]:
            ye = dict(ring_controls(shell.cv, x))['edge'][0]
            pts_r.append(Vector((x, s_ * (ye - 0.012), 0.0)))
        keep(surface_sweep(surf0, pts_r, (0, 0, -1), rib_profile(0.022, 0.008, 0.006, 0.003), mat='M_TrimBlack'))
    add_pair(surface_patch(surf0, outline_ellipse(0.034, 0.014, 12), Vector((2.12, 0.0, 1.04)), RAY_L, offset=-0.0015, rings=2,
                           mat='M_Indicator'), into=inserts)
    # chrome sport bar behind the cab (stands in the bed)
    sbar = fillet_path3([(-1.45, 0.80, 0.92), (-1.45, 0.80, 1.62), (-1.45, -0.80, 1.62), (-1.45, -0.80, 0.92)], [0, 0.13, 0.13, 0], 7)
    keep(tube(sbar, 0.028, 14, 'M_Chrome'), bed=True)
    keep(tube([(-1.45, -0.80, 1.36), (-1.45, 0.80, 1.36)], 0.020, 10, 'M_Chrome'), bed=True)
    for s_ in (1, -1):
        keep(prim_cylinder(radius=0.045, depth=0.03, segments=14, axis='Z', center=(-1.45, s_ * 0.80, 0.915), mat='M_TrimBlack'), bed=True)
    # roof marker lamps + antenna
    for k in range(-1, 2):
        keep(prim_box((0.04, 0.07, 0.020), (0.52, k * 0.14, P['roof_z'] + 0.006), mat='M_Indicator', bevel=0.006, segments=1))
    keep(prim_cylinder(radius=0.018, depth=0.025, segments=10, axis='Z', center=(-0.75, -0.78, P['roof_z'] - 0.004), mat='M_TrimBlack'))
    keep(tube([(-0.75, -0.78, P['roof_z']), (-0.80, -0.785, P['roof_z'] + 0.017)], 0.004, 5, 'M_TrimBlack'))
    # side steps (running boards) + mud flaps front
    for s in (1, -1):
        keep(prim_box((1.90, 0.16, 0.05), (-0.16, s * 0.935 - s * 0.03, 0.372), mat='M_TrimBlack', bevel=0.015, segments=2))
        keep(prim_box((1.90, 0.012, 0.045), (-0.16, s * 1.0 - s * 0.02, 0.372), mat='M_Chrome', bevel=0.004, segments=1))
        for k in range(16):
            keep(prim_box((0.022, 0.11, 0.007), (-1.04 + k * 0.118, s * 0.895, 0.399), mat='M_TrimGrey', bevel=0.002, segments=1))
        for bx in (-0.82, -0.16, 0.50):
            keep(prim_box((0.07, 0.11, 0.10), (bx, s * 0.84, 0.33), mat='M_TrimBlack', bevel=0.012, segments=1))
        keep(prim_box((0.012, 0.28, 0.24), (XF - 0.50, s * 0.84, 0.40), mat='M_Rubber', bevel=0.004, segments=1))

    # --- chunky front bumper: chrome bar sweeping round the corners + black valance + skid plate + tow hooks ---------
    fpath = [Vector(p) for p in ((2.31, 0.895, 0.66), (2.41, 0.875, 0.66), (2.515, 0.77, 0.66), (2.55, 0.5, 0.66), (2.57, 0.0, 0.66),
                                 (2.55, -0.5, 0.66), (2.515, -0.77, 0.66), (2.41, -0.875, 0.66), (2.31, -0.895, 0.66))]
    fpath = fillet_path3(fpath, [0, 0.2, 0.25, 0.4, 0.5, 0.4, 0.25, 0.2, 0], 5)
    keep(tube(fpath, (0.062, 0.088), 16, 'M_Chrome'))
    keep(prim_box((0.12, 1.50, 0.15), (2.50, 0.0, 0.50), mat='M_TrimBlack', bevel=0.03, segments=2))
    keep(prim_box((0.05, 0.94, 0.12), (2.545, 0.0, 0.42), mat='M_TrimGrey', bevel=0.015, segments=2))
    pl = build_plate(0.52, 0.112)
    bmesh.ops.transform(pl, matrix=T((2.637, 0.0, 0.66), (0, 0, 0)), verts=pl.verts)
    keep(pl)
    for s in (1, -1):
        keep(prim_torus(R=0.036, r=0.008, seg_major=18, seg_minor=6, axis='X', center=(2.585, s * 0.36, 0.45), mat='M_Caliper'))
        keep(prim_box((0.04, 0.26, 0.04), (2.59, s * 0.74, 0.66), mat='M_TrimBlack', bevel=0.008, segments=1))
    lap("cab add-ons")

    # --- glass (cab only) ------------------------------------------------------------------------------------------
    side_cols = shell_quad_cols(shell, 'belt_up', 'edge', 1) | shell_quad_cols(shell, 'belt_up', 'edge', -1)
    top_cols = shell_quad_cols(shell, 'rail', 'top_c', 1) | shell_quad_cols(shell, 'rail', 'top_c', -1)
    A0, A1 = (0.88, 1.24), (0.405, 1.840)
    B0, B1 = (-0.07, 1.20), (-0.07, 1.92)
    Bq0, Bq1 = (-0.215, 1.20), (-0.215, 1.92)
    C0, C1 = (-1.00, 1.20), (-1.00, 1.92)

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
    cap_zone = lambda f: f[tc] == 0 and f.calc_center_median().x < -1.13

    def rear_pred(f):
        if f[tc] != 0:
            return False
        c = f.calc_center_median()
        return c.x < -1.13 and 1.42 < c.z < 1.74 and abs(c.y) < 0.56

    def ws_pred(f):
        return f[tc] in top_cols and P['x_ws_top'] < f.calc_center_median().x < P['x_ws_base']

    wins = [dict(name='door_f', pred=mk_side((A0, A1), (B0, B1)), zone=side_zone, planes=[plane(A0, A1), plane(B0, B1)]),
            dict(name='door_r', pred=mk_side((Bq0, Bq1), (C0, C1)), zone=side_zone, planes=[plane(Bq0, Bq1), plane(C0, C1)]),
            dict(name='windscreen', pred=ws_pred),
            dict(name='rear', pred=rear_pred, zone=cap_zone,
                 planes=[(Vector((0, 0, 1.42)), Vector((0, 0, 1))), (Vector((0, 0, 1.74)), Vector((0, 0, 1))),
                         (Vector((0, 0.56, 0)), Vector((0, 1, 0))), (Vector((0, -0.56, 0)), Vector((0, 1, 0)))])]
    for ib in inserts:
        if ib is not None:
            bm_append(bm, ib)
            ib.free()
    tc, ts = face_tags(bm)
    glass = extract_glass(bm, wins, offset=0.014)
    lap("glass: %d faces" % len(glass.faces))
    # fix round 2: black rubber seal bead round every cab window opening
    seal = window_seal(glass, surf0, width=0.0125, height=0.0040, mat='M_TrimBlack')
    if seal is not None:
        bm_append(bm, seal)
        seal.free()
        lap("window seals appended")
    # fix round 2: cab-back seal panel closes the 6 cm slot between the cab and the bed (shell edges / sky no longer show through it)
    _add(bm, prim_box((0.080, 1.76, 0.60), (-1.18, 0.0, 0.92), mat='M_TrimBlack', bevel=0.012, segments=1))

    def lining_pred(f):
        if f[tc] == 0 or f[tc] not in (pillar_cols | roof_cols):
            return False
        c = f.calc_center_median()
        return -1.14 < c.x < 0.92 and c.z > 1.22
    pillar_trim = inner_trim_from_faces(bm, lining_pred, offset=0.03, mat='M_IntTrim')

    # ==================================================================================================================
    # B. BED shell (open box)
    # ==================================================================================================================
    cvb = bed_curves()
    bx0, bx1 = P['bed_x0'], P['bed_x1']
    rb0, rb1 = 0.05, 0.04
    xsb = station_list(bx0, bx1, dx=0.05, end_dx=0.02, end_len=0.2, min_gap=0.007,
                       extra=end_round_stations(bx0, rb0, 5, at_start=True) + end_round_stations(bx1, rb1, 5, at_start=False))
    shb = loft_body(cvb, xsb, cap_bulge=0.006, ring_density=2.0, cap_rings=4, round_x0=rb0, round_x1=rb1)
    bmb = shb.bm
    tcb, tsb = face_tags(bmb)
    ubc, lowb = set(), set()
    for sd in (1, -1):
        ubc |= shell_quad_cols(shb, 'floor_c', 'sill', sd)
        lowb |= shell_quad_cols(shb, 'sill', 'wide', sd)
    for z_cut in (0.84,):
        geom = set()
        for f in bmb.faces:
            geom.add(f)
            geom.update(f.edges)
            geom.update(f.verts)
        bmesh.ops.bisect_plane(bmb, geom=list(geom), dist=1e-6, plane_co=(0, 0, z_cut), plane_no=(0, 0, 1))
    bmb.normal_update()
    surfb = Surface(bmb)
    for f in bmb.faces:
        c = f.calc_center_median()
        tag = f[tcb]
        m = 'M_Paint'
        if tag in ubc:
            m = 'M_Underbody'
        elif c.z < 0.84 and abs(c.x) < 3.0 and (tag in lowb or tag == 0):
            m = 'M_Paint2'
        f.material_index = mi(m)
    cut_bed = []
    for name in ('RL', 'RR'):
        w = WHEELS[name]
        cx, cy, cz = w['center']
        cut_bed.append(wheel_arch_cutter(cx, cz, w['radius'] + ARCH_PAD, 1 if cy > 0 else -1, inner_y=0.30, mat='M_Underbody'))
    # the cargo box: rounded pocket from the rim down to the floor; walls / floor in liner black
    px0, px1 = -2.46, -1.335
    pocket = prim_prism(outline_rrect(px1 - px0, 1.70, 0.05, 5), 0.62, plane='XY', center=((px0 + px1) / 2, 0.0, P['bed_floor'] + 0.31),
                        mat='M_TrimBlack')
    cut_bed.append(pocket)
    # tailgate: two vertical shut lines + a bottom line
    tg = [Vector((-2.54, 0.80, 1.20)), Vector((-2.54, 0.80, 0.66)), Vector((-2.54, -0.80, 0.66)), Vector((-2.54, -0.80, 1.20))]
    cut_bed.append(surface_sweep(surfb, resample_poly(tg, 0.04), RAY_R, GROOVE, mat='M_Underbody'))
    cut, hnd = pocket_cutter(surfb, outline_rrect(0.26, 0.060, 0.022, 4), Vector((-2.54, 0.0, 1.16)), RAY_R, depth=0.035, taper=0.9,
                             mat='M_TrimBlack', floor_follows=False), None
    if cut is not None:
        cut_bed.append(cut)
        keep(prim_box((0.012, 0.18, 0.016), (-2.525, 0.0, 1.158), mat='M_Chrome', bevel=0.004, segments=1), bed=True)
    # fuel flap on the left side of the bed front
    fuel = surface_sweep(surfb, circle_pts(-1.52, 1.05, 0.065, n=26, y=0), (0, -1, 0), GROOVE, closed=True, mat='M_Underbody')
    if fuel is not None:
        cut_bed.append(fuel)
    # stacked tail lamps in the rear corners
    RT = ('radial', Vector((-2.10, 0.45, 1.0)))
    cut, ins = stacked_lamp(surfb, Vector((-2.54, 0.80, 1.00)), RT, (Vector((0, -1, 0)), VL), 0.11, 0.34, depth=0.04)
    if cut is None:
        lap("taillight FAILED")
    add_pair(cut, cut_bed)
    for b in ins:
        add_pair(b, into=inserts_bed)
    # recessed side marker + exhaust holes
    for s in (1, -1):
        cut_bed.append(prim_cylinder(radius=0.05, depth=0.22, segments=24, axis='X', center=(-2.475, s * 0.66, 0.46), mat='M_Underbody'))
        tip = build_exhaust_tip(radius=0.038, length=0.12, lip=0.004)
        bmesh.ops.transform(tip, matrix=T((-2.555, s * 0.66, 0.46)), verts=tip.verts)
        keep(tip, bed=True)
    lap("bed cutters: %d, None at %s" % (len(cut_bed), [i for i, c in enumerate(cut_bed) if c is None]))
    cut_bed = [c for c in cut_bed if c is not None]
    bmb = bm_boolean(bmb, cut_bed)
    lap("bed boolean: %d faces, manifold=%s" % (len(bmb.faces), is_manifold(bmb)))
    tcb, tsb = face_tags(bmb)
    # bed add-ons: rail caps, flares, liner ribs, wheel boxes, tie-downs, bumper, hitch
    for name in ('RL', 'RR'):
        w = WHEELS[name]
        cx, cy, cz = w['center']
        sw = arch_moulding(surfb, cx, cz, w['radius'] + ARCH_PAD + 0.045, (0, -1, 0) if cy > 0 else (0, 1, 0), a0=36.0, a1=148.0, n=30,
                           width=0.115, height=0.028)
        lap("bed flare %s: %s" % (name, sw is not None))
        keep(sw, bed=True)
    for s in (1, -1):
        pts = [Vector((-2.45 + 0.1 * i, s * 0.895, 0)) for i in range(13)]
        keep(surface_sweep(surfb, pts, (0, 0, -1), rib_profile(0.10, 0.008, 0.01, 0.003), mat='M_TrimBlack'), bed=True)
        keep(prim_box((1.16, 0.20, 0.13), (-1.805 - 0.0, s * 0.735, P['bed_floor'] + 0.055), mat='M_TrimBlack', bevel=0.03, segments=2), bed=True)
        for hx in (-2.25, -1.42):
            keep(prim_torus(R=0.026, r=0.005, seg_major=14, seg_minor=5, axis='Y', center=(hx, s * 0.838, 1.08), mat='M_Chrome'), bed=True)
    add_pair(surface_patch(surfb, outline_ellipse(0.034, 0.014, 12), Vector((-2.30, 0.0, 1.12)), RAY_L, offset=-0.0015, rings=2,
                           mat='M_Taillight'), into=inserts_bed)
    for k in range(-4, 5):
        keep(prim_box((1.12, 0.045, 0.012), (-1.92, k * 0.155, P['bed_floor'] + 0.006), mat='M_TrimGrey', bevel=0.003, segments=1), bed=True)
    keep(prim_box((0.012, 1.60, 0.10), (-1.345, 0.0, P['bed_floor'] + 0.05), mat='M_TrimGrey', bevel=0.004, segments=1), bed=True)
    # rear bumper: chrome step bumper + black step pad + receiver hitch + plate
    rpath = [Vector(p) for p in ((-2.35, 0.895, 0.62), (-2.45, 0.875, 0.62), (-2.56, 0.76, 0.62), (-2.595, 0.4, 0.62), (-2.60, 0.0, 0.62),
                                 (-2.595, -0.4, 0.62), (-2.56, -0.76, 0.62), (-2.45, -0.875, 0.62), (-2.35, -0.895, 0.62))]
    rpath = fillet_path3(rpath, [0, 0.2, 0.25, 0.4, 0.5, 0.4, 0.25, 0.2, 0], 5)
    keep(tube(rpath, (0.062, 0.095), 16, 'M_Chrome'), bed=True)
    keep(prim_box((0.14, 0.62, 0.016), (-2.575, 0.0, 0.725), mat='M_TrimBlack', bevel=0.005, segments=1), bed=True)
    for k in range(7):
        keep(prim_box((0.12, 0.012, 0.006), (-2.575, -0.27 + k * 0.09, 0.735), mat='M_TrimGrey', bevel=0.002, segments=1), bed=True)
    keep(prim_box((0.22, 0.075, 0.075), (-2.575, 0.0, 0.50), mat='M_TrimGrey', bevel=0.012, segments=1), bed=True)
    keep(prim_box((0.05, 0.40, 0.17), (-2.475, 0.0, 0.52), mat='M_TrimBlack', bevel=0.012, segments=1), bed=True)
    pl = build_plate(0.52, 0.112)
    bmesh.ops.transform(pl, matrix=T((-2.658, 0.0, 0.54), (0, 0, 180)), verts=pl.verts)
    keep(pl, bed=True)
    for s in (1, -1):
        keep(prim_torus(R=0.032, r=0.007, seg_major=16, seg_minor=6, axis='X', center=(-2.655, s * 0.40, 0.50), mat='M_Caliper'), bed=True)
        keep(prim_box((0.012, 0.30, 0.22), (XR - 0.50, s * 0.84, 0.42), mat='M_Rubber', bevel=0.004, segments=1), bed=True)
    for ib in inserts_bed:
        if ib is not None:
            bm_append(bmb, ib)
            ib.free()
    lap("bed add-ons")

    # ==================================================================================================================
    # C. underbody: frame rails, axles, leaf springs, driveshaft, fuel tank, exhaust
    # ==================================================================================================================
    ub = bmesh.new()
    for s in (1, -1):
        _add(ub, prim_box((5.0, 0.085, 0.14), (0.0, s * 0.44, 0.44), mat='M_TrimBlack', bevel=0.012, segments=1))
        for ax_x in (XF, XR):
            _add(ub, tube([(ax_x - 0.02, s * 0.52, 0.45), (ax_x - 0.02, s * 0.52, 0.85)], 0.022, 8, 'M_TrimGrey'))
    for ax_x in (XF, XR):
        _add(ub, tube([(ax_x, -0.62, 0.38), (ax_x, 0.62, 0.38)], 0.052, 12, 'M_TrimBlack'))
        _add(ub, prim_sphere(0.14, 18, 10, scale=(1.0, 1.1, 0.92), center=(ax_x + 0.06, 0.0, 0.385), mat='M_TrimGrey'))
    for s in (1, -1):
        leaf = [Vector((XR + dx, s * 0.58, 0.455 + 0.07 * (1 - (dx / 0.55) ** 2))) for dx in [-0.55 + 0.11 * i for i in range(11)]]
        _add(ub, tube(leaf, 0.020, 6, 'M_TrimBlack'))
        _add(ub, prim_box((0.10, 0.07, 0.07), (XR, s * 0.58, 0.43), mat='M_TrimGrey', bevel=0.01, segments=1))
    _add(ub, tube([(XF - 0.10, 0.0, 0.40), (XR + 0.10, 0.0, 0.40)], 0.034, 10, 'M_TrimBlack'))
    _add(ub, prim_box((0.46, 0.34, 0.16), (0.25, 0.0, 0.40), mat='M_TrimGrey', bevel=0.03, segments=2))
    _add(ub, prim_box((0.72, 0.62, 0.25), (-0.95, -0.12, 0.43), mat='M_TrimGrey', bevel=0.03, segments=2))        # fuel tank
    for s in (1, -1):
        _add(ub, tube(fillet_path3([(0.0, s * 0.30, 0.37), (-1.2, s * 0.40, 0.38), (-2.35, s * 0.64, 0.45), (-2.595, s * 0.66, 0.46)],
                                   [0, 0.3, 0.25, 0], 5), 0.032, 10, 'M_Exhaust'))
    _add(ub, prim_cylinder(radius=0.095, depth=0.70, segments=16, axis='X', center=(-2.0, 0.40, 0.37), mat='M_Exhaust', bevel=0.012))
    _add(ub, prim_box((0.70, 0.95, 0.025), (1.80, 0.0, 0.34), mat='M_TrimGrey', bevel=0.006, segments=1))          # skid plate
    bm_append(bm, ub)
    ub.free()

    # merge bed into the body bmesh
    bm_append(bm, bmb)
    bmb.free()
    n_healed = heal_nonmanifold(bm) if 'heal_nonmanifold' in globals() else 0
    n_tiny = clean_tiny(bm)
    lap("merged: %d faces, tiny %d" % (len(bm.faces), n_tiny))

    body = finish_object(CAR + "_Body", bm, col, parent=root, smooth_angle=62.0)
    n1 = apply_shell_normals(body, shell)
    n2 = apply_shell_normals(body, shb)
    shell.ref.free()
    shb.ref.free()
    lap("custom normals cab %d bed %d" % (n1, n2))
    finish_object(CAR + "_Glass", glass, col, parent=root)

    # ==================================================================================================================
    # D. wheels
    # ==================================================================================================================
    for name, w in WHEELS.items():
        wb = build_wheel(radius=w['radius'], width=w['width'], rim_radius=RIM_R, rim_width=RIM_W, spokes=5, style='multi', side=+1,
                         brake_disc_radius=0.165, hub_radius=0.062, caliper_angle=30.0 if name[0] == 'F' else 150.0, tread=False, segments=48,
                         tyre_segments=24)
        swap_tyre(wb, block_tyre(w['radius'], w['width'], RIM_R - 0.0127, segs=40, n=26, lug_h=0.024, seed=41 + 9 * list(WHEELS).index(name),
                                 vary=0.5))          # fix round 2: real block tread + sidewall blocks
        if w['side'] < 0:
            m = mirrored_copy(wb)
            wb.free()
            wb = m
        finish_object("%s_Wheel_%s" % (CAR, name), wb, col, parent=root, location=w['center'], smooth_angle=40)
    lap("wheels done")

    # ==================================================================================================================
    # E. interior + steering wheel
    # ==================================================================================================================
    ib = build_interior_utility(shell, dict(floor_z=0.52, front_x=-0.28, front_z=0.56, driver_y=0.40, rear_x=-0.90, rear_z=0.56, rear_width=1.46,
                                            dash_x_back=0.48, dash_x_front=0.92, dash_z_top=1.15, dash_z_low=0.70, hw=0.88, x_front_floor=0.88,
                                            x_rear_floor=-1.12, door_x=(-0.12, 0.80), quarter_x=(-1.12, -0.16), roof_x=(-1.1, 0.2),
                                            back_h=0.68, headliner=False, shifter_x=0.0, console=(-0.40, 0.50)))    # fix round 2: utilitarian dash
    _add(ib, pillar_trim)
    _add(ib, prim_box((0.03, 1.46, 0.60), (-1.115, 0.0, 1.20), mat='M_IntTrim', bevel=0.01, segments=1))          # rear cab wall lining
    finish_object(CAR + "_Interior", ib, col, parent=root)
    hub = (0.335, 0.40, 1.095)
    swb, axis = build_steering_wheel(rim_radius=0.19, tilt=32.0)
    sw = finish_object(CAR + "_SteeringWheel", swb, col, parent=root, location=hub, smooth_angle=40)
    sw['rim_axis'] = [axis.x, axis.y, axis.z]
    lap("interior done")

    # ==================================================================================================================
    # F. collision + anchors
    # ==================================================================================================================
    hulls = [
        [Vector((p.x, p.y, min(p.z, 1.22))) for p in hull_points_from_shell(shell, [0.90, 1.6, 2.50], ['floor_e', 'wide', 'belt_up', 'edge', 'top_c'],
                                                                              z_clip=(0.46, None), shrink=0.04)],
        hull_points_from_shell(shell, [-1.12, -0.3, 0.6, 0.92], ['floor_e', 'wide', 'belt_lo'], z_clip=(0.42, 1.22), shrink=0.04),
        [Vector((p.x, p.y, p.z - 0.02)) for p in
         hull_points_from_shell(shell, [0.88, 0.3, -0.5, -1.12], ['belt_up', 'edge', 'top_c'], z_clip=(1.20, None), shrink=0.05)],
        hull_box_pts(-2.52, -1.22, 0.0, 0.93, 0.56, 1.27, cx=0.02, cy=0.0, cz=0.04),
    ]
    ucx = make_ucx_hulls(CAR, hulls, col, root)
    for h in ucx:
        h.hide_set(True)

    def E(suffix, loc, disp='PLAIN_AXES', size=0.08):
        return make_empty("%s_%s" % (CAR, suffix), col, parent=root, location=loc, display=disp, size=size)

    def lamp_point(sf, center, ray, lift=0.03):
        h = sf.hit(Vector(center), ray)
        return tuple(round(c, 4) for c in (h[0] + h[1] * lift)) if h else tuple(center)

    hl = lamp_point(surf0, c_head, RH)
    tl = lamp_point(surfb, Vector((-2.54, 0.80, 1.00)), RT)
    E('LP_HeadL', hl)
    E('LP_HeadR', (hl[0], -hl[1], hl[2]))
    E('LP_TailL', tl)
    E('LP_TailR', (tl[0], -tl[1], tl[2]))
    E('LP_Reverse', (tl[0], tl[1], tl[2] - 0.12))
    E('CAM_Hood', (1.45, 0.0, 1.46), 'ARROWS', 0.15)
    E('CAM_Cockpit', (-0.10, 0.40, 1.42), 'ARROWS', 0.15)
    E('CAM_Bumper', (2.66, 0.0, 0.78), 'ARROWS', 0.15)
    E('EXHAUST_L', (-2.595, 0.66, 0.46))
    E('EXHAUST_R', (-2.595, -0.66, 0.46))

    lo, hi = bm_bounds_obj(body)
    vs = [v.co for v in body.data.vertices if v.co.z < 1.0 and abs(v.co.x) < 2.4 and v.co.y > 0]
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
            print("[car09] uv %s %.1fs" % (suf, time.time() - t0))


if STAGE in ("all", "geometry"):
    build()
if STAGE in ("all", "uv", "uv1"):
    unwrap_parts(['Body', 'Glass', 'Interior', 'SteeringWheel'])
if STAGE in ("all", "uv", "uv2"):
    unwrap_parts(['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'])
